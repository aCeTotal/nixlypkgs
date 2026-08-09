/*
 * Gaea rendrer 3D-viewporten i en egen prosess (Gaea.Viewport.exe, Unity).
 * Paa Windows blir det vinduet embedded i hovedvinduet. Under Wine skjer
 * ingen reparenting: vinduet blir staaende som et eget toplevel (parent=0,
 * UnityWndClass) med tittellinje og ramme, plassert oppe paa panelet der
 * viewporten skal vaere.
 *
 * Denne hjelperen kjoerer i samme Wine-desktop som Gaea og retter opp:
 *   - fjerner ramme/tittellinje, saa klientflaten dekker nøyaktig
 *     rektangelet Gaea plasserer vinduet i
 *   - gjoer Gaea-hovedvinduet til eier, saa viewporten alltid ligger over
 *     hovedvinduet i staden for aa havne bak det ved klikk
 *
 * Poller fordi vinduet dukker opp etter oppstart, og fordi Unity setter
 * stilen tilbake naar vinduet endrer stoerrelse. Avslutter naar Gaea er
 * borte.
 */
#include <windows.h>
#include <string.h>

static HWND g_viewport;
static HWND g_main;

static BOOL CALLBACK find_cb(HWND h, LPARAM l)
{
	char cls[256] = {0}, title[256] = {0};

	GetClassNameA(h, cls, sizeof cls);
	GetWindowTextA(h, title, sizeof title);

	if (!strcmp(cls, "UnityWndClass") && !strcmp(title, "Gaea.Viewport"))
		g_viewport = h;
	/* WPF-vinduene heter HwndWrapper[Gaea;;<guid>]. Hovedvinduet har tittel
	 * "Gaea - <prosjekt>"; splash-vinduet heter "Welcome to Gaea ...". */
	else if (!strncmp(cls, "HwndWrapper[Gaea;", 17) &&
			!strncmp(title, "Gaea - ", 7))
		g_main = h;
	return TRUE;
}

static void fix_viewport(void)
{
	LONG_PTR st;
	RECT r;

	st = GetWindowLongPtrA(g_viewport, GWL_STYLE);
	if (!(st & (WS_CAPTION | WS_THICKFRAME)))
		return;                 /* allerede rammefri */

	st &= ~(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU |
		WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_DLGFRAME | WS_BORDER);
	st |= WS_POPUP;
	SetWindowLongPtrA(g_viewport, GWL_STYLE, st);

	if (g_main)
		SetWindowLongPtrA(g_viewport, GWLP_HWNDPARENT, (LONG_PTR)g_main);

	/* SWP_FRAMECHANGED faar Wine til aa regne ut klientflaten paa nytt.
	 * Posisjon og stoerrelse eies fortsatt av Gaea, saa de beholdes. */
	GetWindowRect(g_viewport, &r);
	SetWindowPos(g_viewport, HWND_TOP, r.left, r.top,
			r.right - r.left, r.bottom - r.top,
			SWP_FRAMECHANGED | SWP_NOACTIVATE);
}

int main(void)
{
	int seen = 0, missing = 0;

	for (;;) {
		g_viewport = NULL;
		g_main = NULL;
		EnumWindows(find_cb, 0);

		if (g_viewport || g_main) {
			seen = 1;
			missing = 0;
		} else if (seen && ++missing > 20) {
			break;          /* Gaea avsluttet — ikke bli liggende */
		}

		if (g_viewport)
			fix_viewport();
		Sleep(500);
	}
	return 0;
}
