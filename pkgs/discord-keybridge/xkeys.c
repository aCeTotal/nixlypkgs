/* Injects keys into Xwayland with XTEST so X11-only clients see them.
 *
 * Discord's global keybinds are XInput2 raw events on the X root window,
 * which under Wayland only fire for keys Xwayland itself receives — i.e.
 * never, unless an X client has focus.  XTEST fake input is processed by
 * the X server regardless of focus and does raise raw events, so an
 * injected key reaches Discord from anywhere in the session.
 */

#include "xkeys.h"

#include <X11/extensions/XTest.h>
#include <stdio.h>
#include <string.h>

#define MAX_SLOTS 8

static Display *dpy;
static KeySym slot_sym[MAX_SLOTS];
static KeyCode slot_code[MAX_SLOTS];
static int nslots;

/* Resolve sym to a keycode, mapping it onto a free one when the session
 * keymap lacks it (F13.. are absent from the usual pc105 layouts). */
static KeyCode
ensure_code(KeySym sym, int self)
{
	int min, max, per, kc, i, j;
	KeySym *map;
	KeyCode found = 0;

	if ((found = XKeysymToKeycode(dpy, sym)))
		return found;

	XDisplayKeycodes(dpy, &min, &max);
	map = XGetKeyboardMapping(dpy, min, max - min + 1, &per);
	if (!map)
		return 0;

	for (kc = max; kc >= min && !found; kc--) {
		for (i = 0; i < nslots; i++)
			if (i != self && slot_code[i] == kc)
				break;
		if (i < nslots)
			continue;
		for (j = 0; j < per; j++)
			if (map[(kc - min) * per + j] != NoSymbol)
				break;
		if (j == per)
			found = kc;
	}
	XFree(map);

	if (found) {
		XChangeKeyboardMapping(dpy, found, 1, &sym, 1);
		XSync(dpy, False);
	}
	return found;
}

int
xkeys_open(void)
{
	int ev, err, major = 2, minor = 2;

	if (!(dpy = XOpenDisplay(NULL))) {
		fprintf(stderr, "discord-keybridge: no X display\n");
		return -1;
	}
	if (!XTestQueryExtension(dpy, &ev, &err, &major, &minor)) {
		fprintf(stderr, "discord-keybridge: no XTEST extension\n");
		return -1;
	}
	return 0;
}

int
xkeys_bind(KeySym sym)
{
	int slot = nslots;

	if (slot >= MAX_SLOTS)
		return -1;
	slot_sym[slot] = sym;
	slot_code[slot] = ensure_code(sym, slot);
	nslots++;
	if (!slot_code[slot])
		fprintf(stderr, "discord-keybridge: no free keycode for %s\n",
			XKeysymToString(sym));
	else
		fprintf(stderr, "discord-keybridge: %s = keycode %d\n",
			XKeysymToString(sym), slot_code[slot]);
	return slot;
}

void
xkeys_send(int slot, int press)
{
	if (slot < 0 || slot >= nslots || !slot_code[slot])
		return;
	XTestFakeKeyEvent(dpy, slot_code[slot], press, CurrentTime);
	XFlush(dpy);
}

int
xkeys_fd(void)
{
	return ConnectionNumber(dpy);
}

/* A keymap reload drops our mappings; re-apply them. */
void
xkeys_dispatch(void)
{
	XEvent e;
	int i;

	while (XPending(dpy)) {
		XNextEvent(dpy, &e);
		if (e.type != MappingNotify)
			continue;
		XRefreshKeyboardMapping(&e.xmapping);
		for (i = 0; i < nslots; i++)
			slot_code[i] = ensure_code(slot_sym[i], i);
	}
}
