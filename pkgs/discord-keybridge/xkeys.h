/* X11/XTEST side of the bridge. */
#ifndef XKEYS_H
#define XKEYS_H

#include <X11/Xlib.h>
#include <X11/keysym.h>

int xkeys_open(void);
int xkeys_bind(KeySym sym);
void xkeys_send(int slot, int press);
int xkeys_fd(void);
void xkeys_dispatch(void);

#endif
