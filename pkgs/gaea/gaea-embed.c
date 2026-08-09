#include <windows.h>
#include <string.h>

#define POLL_MS		150
#define GRACE_START	(120000 / POLL_MS)
#define GRACE_GONE	(20000 / POLL_MS)

static HWND g_viewport;
static HWND g_main;

static BOOL CALLBACK find_cb(HWND h, LPARAM l)
{
	char cls[64] = "";
	char txt[128] = "";

	GetClassNameA(h, cls, sizeof cls);
	GetWindowTextA(h, txt, sizeof txt);

	if (!strcmp(cls, "UnityWndClass"))
		g_viewport = h;
	else if (!strncmp(cls, "HwndWrapper[Gaea", 16) && strstr(txt, "Gaea - "))
		g_main = h;
	return TRUE;
}

static void follow_cursor(void)
{
	GUITHREADINFO gti;
	POINT p;
	HWND hit;
	DWORD me, vt, mt;

	memset(&gti, 0, sizeof gti);
	gti.cbSize = sizeof gti;

	me = GetCurrentThreadId();
	vt = GetWindowThreadProcessId(g_viewport, NULL);
	mt = GetWindowThreadProcessId(g_main, NULL);

	if (!GetGUIThreadInfo(vt, &gti))
		return;

	GetCursorPos(&p);
	hit = WindowFromPoint(p);

	if (hit == g_viewport && gti.hwndFocus != g_viewport) {
		AttachThreadInput(me, vt, TRUE);
		AttachThreadInput(mt, vt, TRUE);
		SetFocus(g_viewport);
	} else if (hit != g_viewport && gti.hwndFocus == g_viewport) {
		AttachThreadInput(me, mt, TRUE);
		SetFocus(g_main);
	}
}

int main(void)
{
	int seen = 0;
	int miss = 0;

	for (;;) {
		g_viewport = NULL;
		g_main = NULL;
		EnumWindows(find_cb, 0);
		if (g_main && !g_viewport)
			EnumChildWindows(g_main, find_cb, 0);

		if (g_viewport || g_main) {
			seen = 1;
			miss = 0;
		} else if (++miss > (seen ? GRACE_GONE : GRACE_START)) {
			break;
		}

		if (g_viewport && g_main)
			follow_cursor();
		Sleep(POLL_MS);
	}
	return 0;
}
