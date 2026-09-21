/* Which microphone feeds the chain, and keeping NixlyMic the default source. */
#include "app.h"

#include <stdlib.h>
#include <string.h>

static struct node_info *find_node(struct app *a, const char *name)
{
	int i;

	for (i = 0; i < a->n_nodes; i++)
		if (strcmp(a->nodes[i].name, name) == 0)
			return &a->nodes[i];
	return NULL;
}

void store_gains(struct app *a)
{
	if (a->selected[0])
		state_set(a->state, a->selected, a->ctl.vol, a->ctl.sens_db,
			  a->ctl.learned);
}

/* device.id and the profile device index only show up in the full node info. */
static void on_sel_info(void *data, const struct pw_node_info *i)
{
	struct app *a = data;
	const char *dev, *pd;

	if (!(i->change_mask & PW_NODE_CHANGE_MASK_PROPS) || i->props == NULL)
		return;
	if ((dev = spa_dict_lookup(i->props, PW_KEY_DEVICE_ID)) == NULL)
		return;
	pd = spa_dict_lookup(i->props, "card.profile.device");
	route_bind(a, (uint32_t)atoi(dev), pd ? atoi(pd) : 0);
}

static const struct pw_node_events sel_events = {
	PW_VERSION_NODE_EVENTS,
	.info = on_sel_info,
};

static void select_node(struct app *a, struct node_info *n)
{
	float vol = 0.35f, sens = 0.0f;
	bool learned = false;

	if (strcmp(a->selected, n->name) == 0)
		return;
	store_gains(a);
	state_set_preferred(a->state, n->name);
	snprintf(a->selected, sizeof(a->selected), "%s", n->name);

	route_unbind(a);
	if (a->sel_proxy) {
		spa_hook_remove(&a->sel_listener);
		pw_proxy_destroy(a->sel_proxy);
	}
	a->sel_proxy = pw_registry_bind(a->registry, n->id,
					PW_TYPE_INTERFACE_Node, PW_VERSION_NODE, 0);
	pw_node_add_listener((struct pw_node *)a->sel_proxy, &a->sel_listener,
			     &sel_events, a);

	meter_init(&a->meter, RATE);
	a->vol_known = state_get(a->state, n->name, &vol, &sens, &learned);
	control_reset(&a->ctl, vol, sens, learned);
	a->pushed_g1 = a->pushed_g2 = 0.0f;
	a->pushed_vol = -1.0f;

	info(a, "mic: %s (%s)", n->name, a->vol_known ? "remembered" : "learning");
	update_metering(a);
	push_props(a);
}

/* The chain is a smart filter, so WirePlumber decides which microphone feeds
 * it — a headset that connects outranks the built-in mic on its own. We only
 * follow that choice to gain-stage the right device. */
static void reselect(struct app *a)
{
	struct node_info *n;

	if (a->wanted[0] && (n = find_node(a, a->wanted)) != NULL)
		select_node(a, n);
}

static void on_fc_info(void *data, const struct pw_node_info *i)
{
	struct app *a = data;
	bool run;

	if (!(i->change_mask & PW_NODE_CHANGE_MASK_STATE))
		return;
	run = i->state == PW_NODE_STATE_RUNNING;
	if (run == a->fc_running)
		return;
	a->fc_running = run;
	update_metering(a);
}

static const struct pw_node_events fc_events = {
	PW_VERSION_NODE_EVENTS,
	.info = on_fc_info,
};

static int json_name(const char *json, char *out, size_t len)
{
	const char *p = strstr(json, "\"name\"");
	size_t i = 0;

	if (p == NULL || (p = strchr(p + 6, ':')) == NULL)
		return -1;
	while (*p && *p != '"')
		p++;
	if (*p++ != '"')
		return -1;
	while (*p && *p != '"' && i + 1 < len)
		out[i++] = *p++;
	out[i] = '\0';
	return i ? 0 : -1;
}

static int on_metadata_prop(void *data, uint32_t subject, const char *key,
			    const char *type, const char *value)
{
	struct app *a = data;
	char name[NAME_LEN];

	if (subject != PW_ID_CORE || key == NULL || value == NULL)
		return 0;
	if (strcmp(key, "default.audio.source") != 0)
		return 0;
	if (json_name(value, name, sizeof(name)) < 0)
		return 0;

	snprintf(a->wanted, sizeof(a->wanted), "%s", name);
	reselect(a);
	return 0;
}

static const struct pw_metadata_events metadata_events = {
	PW_VERSION_METADATA_EVENTS,
	.property = on_metadata_prop,
};

static void add_source(struct app *a, uint32_t id, const char *name)
{
	struct node_info *n;

	if (a->n_nodes >= MAX_NODES)
		return;
	n = &a->nodes[a->n_nodes++];
	n->id = id;
	snprintf(n->name, sizeof(n->name), "%s", name);
	reselect(a);
}

static void on_global(void *data, uint32_t id, uint32_t permissions,
		      const char *type, uint32_t version,
		      const struct spa_dict *props)
{
	struct app *a = data;
	const char *name, *cls, *dev;

	if (props == NULL)
		return;

	if (strcmp(type, PW_TYPE_INTERFACE_Metadata) == 0) {
		const char *mn = spa_dict_lookup(props, PW_KEY_METADATA_NAME);

		if (a->metadata || mn == NULL || strcmp(mn, "default") != 0)
			return;
		a->metadata = pw_registry_bind(a->registry, id, type,
					       PW_VERSION_METADATA, 0);
		pw_metadata_add_listener(a->metadata, &a->metadata_listener,
					 &metadata_events, a);
		return;
	}
	if (strcmp(type, PW_TYPE_INTERFACE_Node) != 0)
		return;
	if ((name = spa_dict_lookup(props, PW_KEY_NODE_NAME)) == NULL)
		return;

	if (strcmp(name, FC_NODE) == 0) {
		if (a->fc_proxy)
			return;
		a->fc_proxy = pw_registry_bind(a->registry, id, type,
					       PW_VERSION_NODE, 0);
		pw_node_add_listener((struct pw_node *)a->fc_proxy,
				     &a->fc_listener, &fc_events, a);
		a->pushed_g1 = a->pushed_g2 = 0.0f;
		push_props(a);
		return;
	}

	/* device.id separates real capture devices from virtual sources. */
	cls = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
	dev = spa_dict_lookup(props, PW_KEY_DEVICE_ID);
	if (cls == NULL || dev == NULL || strcmp(cls, "Audio/Source") != 0)
		return;
	add_source(a, id, name);
}

static void on_global_remove(void *data, uint32_t id)
{
	struct app *a = data;
	int i;

	for (i = 0; i < a->n_nodes; i++) {
		if (a->nodes[i].id != id)
			continue;
		if (strcmp(a->nodes[i].name, a->selected) == 0) {
			store_gains(a);
			a->selected[0] = '\0';
			route_unbind(a);
			if (a->sel_proxy) {
				spa_hook_remove(&a->sel_listener);
				pw_proxy_destroy(a->sel_proxy);
				a->sel_proxy = NULL;
			}
			meter_stop(a);
		}
		a->nodes[i] = a->nodes[--a->n_nodes];
		break;
	}
	if (!a->selected[0])
		reselect(a);
}

static const struct pw_registry_events registry_events = {
	PW_VERSION_REGISTRY_EVENTS,
	.global = on_global,
	.global_remove = on_global_remove,
};

void pick_setup(struct app *a)
{
	a->registry = pw_core_get_registry(a->core, PW_VERSION_REGISTRY, 0);
	pw_registry_add_listener(a->registry, &a->registry_listener,
				 &registry_events, a);
}
