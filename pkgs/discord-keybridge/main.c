/* discord-keybridge — turns compositor global shortcuts into X11 keys.
 *
 * Registers a handful of shortcuts with the xdg-desktop-portal
 * GlobalShortcuts interface (nixlytile implements the backend) and
 * replays each Activated/Deactivated as an XTEST press/release of
 * F13..F16 on Xwayland.  Discord then sees them through its X11 keybind
 * path, so its own in-app bindings work from anywhere in the session —
 * hold-to-talk included, since the portal reports press and release.
 *
 * Bind the triggers once: the first run prompts on screen per shortcut,
 * and nixlytile stores them in ~/.local/nixlyos/shortcuts.conf.
 */

#define _GNU_SOURCE

#include "xkeys.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <systemd/sd-bus.h>
#include <systemd/sd-event.h>

#define BUS_NAME  "org.nixlyos.DiscordKeybridge"
#define PORTAL    "org.freedesktop.portal.Desktop"
#define PORTAL_PATH "/org/freedesktop/portal/desktop"
#define GS_IFACE  "org.freedesktop.portal.GlobalShortcuts"

static const struct {
	const char *id;
	const char *description;
	KeySym sym;
} shortcuts[] = {
	{ "key1", "Discord key 1 (F13)", XK_F13 },
	{ "key2", "Discord key 2 (F14)", XK_F14 },
	{ "key3", "Discord key 3 (F15)", XK_F15 },
	{ "key4", "Discord key 4 (F16)", XK_F16 },
};
#define NSHORTCUTS ((int)(sizeof(shortcuts) / sizeof(shortcuts[0])))

static sd_bus *bus;
static sd_bus_slot *request_slot;
static char *session_handle;
static int slots[NSHORTCUTS];

static int create_session(void);

/* Portal Request objects live at a path derived from our unique name, so
 * the Response match can be installed before the call goes out. */
static char *
request_path(const char *token)
{
	const char *unique = NULL;
	char *path, *p;

	if (sd_bus_get_unique_name(bus, &unique) < 0 || !unique)
		return NULL;
	if (asprintf(&path, "%s/request/%s/%s", PORTAL_PATH,
			unique[0] == ':' ? unique + 1 : unique, token) < 0)
		return NULL;
	for (p = path + strlen(PORTAL_PATH) + 9; *p && *p != '/'; p++)
		if (*p == '.')
			*p = '_';
	return path;
}

static int
read_response(sd_bus_message *m, uint32_t *code, char **out_session)
{
	int r;

	if ((r = sd_bus_message_read(m, "u", code)) < 0)
		return r;
	if ((r = sd_bus_message_enter_container(m, 'a', "{sv}")) < 0)
		return r;
	while (sd_bus_message_enter_container(m, 'e', "sv") > 0) {
		const char *key, *val;

		sd_bus_message_read(m, "s", &key);
		if (out_session && strcmp(key, "session_handle") == 0 &&
		    sd_bus_message_enter_container(m, 'v', "s") > 0) {
			sd_bus_message_read(m, "s", &val);
			sd_bus_message_exit_container(m);
			free(*out_session);
			*out_session = strdup(val);
		} else {
			sd_bus_message_skip(m, "v");
		}
		sd_bus_message_exit_container(m);
	}
	return sd_bus_message_exit_container(m);
}

static int
on_bind_response(sd_bus_message *m, void *userdata, sd_bus_error *err)
{
	uint32_t code = 1;

	(void)userdata; (void)err;
	read_response(m, &code, NULL);
	if (code != 0)
		fprintf(stderr, "discord-keybridge: BindShortcuts refused (%u)\n",
			code);
	return 0;
}

static int
bind_shortcuts(void)
{
	static unsigned generation;
	sd_bus_message *m = NULL;
	char token[32], *path = NULL;
	int i, r = -1;

	snprintf(token, sizeof(token), "dkb_bind%u", generation++);
	if (!(path = request_path(token)))
		goto out;

	sd_bus_slot_unref(request_slot);
	request_slot = NULL;
	r = sd_bus_match_signal(bus, &request_slot, PORTAL, path,
		"org.freedesktop.portal.Request", "Response",
		on_bind_response, NULL);
	if (r < 0)
		goto out;

	r = sd_bus_message_new_method_call(bus, &m, PORTAL, PORTAL_PATH,
		GS_IFACE, "BindShortcuts");
	if (r < 0)
		goto out;
	sd_bus_message_append(m, "o", session_handle);
	sd_bus_message_open_container(m, 'a', "(sa{sv})");
	for (i = 0; i < NSHORTCUTS; i++) {
		sd_bus_message_open_container(m, 'r', "sa{sv}");
		sd_bus_message_append(m, "s", shortcuts[i].id);
		sd_bus_message_append(m, "a{sv}", 1, "description", "s",
			shortcuts[i].description);
		sd_bus_message_close_container(m);
	}
	sd_bus_message_close_container(m);
	sd_bus_message_append(m, "s", "");
	sd_bus_message_append(m, "a{sv}", 1, "handle_token", "s", token);
	r = sd_bus_call_async(bus, NULL, m, NULL, NULL, 0);
out:
	sd_bus_message_unref(m);
	free(path);
	return r;
}

static int
on_session_closed(sd_bus_message *m, void *userdata, sd_bus_error *err)
{
	(void)m; (void)userdata; (void)err;
	free(session_handle);
	session_handle = NULL;
	return create_session();
}

static int
on_create_response(sd_bus_message *m, void *userdata, sd_bus_error *err)
{
	uint32_t code = 1;

	(void)userdata; (void)err;
	read_response(m, &code, &session_handle);
	if (code != 0 || !session_handle) {
		fprintf(stderr, "discord-keybridge: no portal session (%u)\n",
			code);
		return 0;
	}
	sd_bus_match_signal(bus, NULL, PORTAL, session_handle,
		"org.freedesktop.portal.Session", "Closed",
		on_session_closed, NULL);
	return bind_shortcuts();
}

static int
create_session(void)
{
	sd_bus_message *m = NULL;
	char *path;
	int r;

	if (!(path = request_path("dkb_session")))
		return -1;
	sd_bus_slot_unref(request_slot);
	request_slot = NULL;
	r = sd_bus_match_signal(bus, &request_slot, PORTAL, path,
		"org.freedesktop.portal.Request", "Response",
		on_create_response, NULL);
	free(path);
	if (r < 0)
		return r;

	r = sd_bus_message_new_method_call(bus, &m, PORTAL, PORTAL_PATH,
		GS_IFACE, "CreateSession");
	if (r < 0)
		return r;
	sd_bus_message_append(m, "a{sv}", 2,
		"handle_token", "s", "dkb_session",
		"session_handle_token", "s", "dkb");
	r = sd_bus_call_async(bus, NULL, m, NULL, NULL, 0);
	sd_bus_message_unref(m);
	return r;
}

static int
on_shortcut(sd_bus_message *m, void *userdata, sd_bus_error *err)
{
	const char *handle, *id;
	int press = userdata != NULL, i;

	(void)err;
	if (sd_bus_message_read(m, "os", &handle, &id) < 0)
		return 0;
	for (i = 0; i < NSHORTCUTS; i++)
		if (strcmp(id, shortcuts[i].id) == 0)
			xkeys_send(slots[i], press);
	return 0;
}

static int
on_x_ready(sd_event_source *s, int fd, uint32_t revents, void *userdata)
{
	(void)s; (void)fd; (void)revents; (void)userdata;
	xkeys_dispatch();
	return 0;
}

int
main(void)
{
	sd_event *event = NULL;
	int i, r;

	if (xkeys_open() < 0)
		return 1;
	for (i = 0; i < NSHORTCUTS; i++)
		slots[i] = xkeys_bind(shortcuts[i].sym);

	if ((r = sd_bus_open_user(&bus)) < 0) {
		fprintf(stderr, "discord-keybridge: no session bus\n");
		return 1;
	}
	/* Single instance: Discord's wrapper starts one per launch. */
	if (sd_bus_request_name(bus, BUS_NAME, 0) < 0)
		return 0;

	sd_bus_match_signal(bus, NULL, PORTAL, PORTAL_PATH, GS_IFACE,
		"Activated", on_shortcut, (void *)1);
	sd_bus_match_signal(bus, NULL, PORTAL, PORTAL_PATH, GS_IFACE,
		"Deactivated", on_shortcut, NULL);

	if ((r = create_session()) < 0)
		return 1;

	if (sd_event_default(&event) < 0)
		return 1;
	sd_bus_attach_event(bus, event, 0);
	sd_event_add_io(event, NULL, xkeys_fd(), EPOLLIN, on_x_ready, NULL);
	return sd_event_loop(event) < 0;
}
