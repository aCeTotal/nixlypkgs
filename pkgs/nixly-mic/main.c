/* Automatic microphone setup: keeps the active mic at a sane capture level
 * and drives the gain stages of the nixly-mic filter chain. */
#include "app.h"

#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define SAVE_DELAY 15.0

double mono_now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}

void info(struct app *a, const char *fmt, ...)
{
	va_list ap;

	if (!a->verbose)
		return;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fputc('\n', stderr);
}

static void on_timer(void *data, uint64_t expirations)
{
	struct app *a = data;
	double now = mono_now();

	if (a->stream && now >= a->ref_hot_until) {
		int changed = control_tick(&a->ctl, &a->meter, now);

		info(a, "level: floor %.1f card %.1f speech %.1fs hist %d",
		     a->meter.floor_db, a->ctl.hw_db, a->meter.speech_secs,
		     a->meter.hist_len);
		/* Gain steps are audible, so they wait for a pause in speech. */
		if ((changed & CONTROL_GAIN) && now >= a->speech_until)
			push_props(a);
		if (changed) {
			store_gains(a);
			if (a->save_at == 0.0)
				a->save_at = now + SAVE_DELAY;
		}
	}
	/* Anything else that writes the card's gain is undone here, in a pause. */
	if (now >= a->speech_until)
		push_hw(a);
	if (a->save_at != 0.0 && now >= a->save_at) {
		state_save(a->state);
		a->save_at = 0.0;
	}
}

static void on_signal(void *data, int signal)
{
	struct app *a = data;

	pw_main_loop_quit(a->loop);
}

int main(int argc, char *argv[])
{
	struct app a = { 0 };
	struct pw_loop *loop;
	struct spa_source *timer;
	struct timespec every = { .tv_sec = 1 };

	pw_init(&argc, &argv);
	a.verbose = getenv("NIXLY_MIC_DEBUG") != NULL;
	a.state = state_load();
	if (a.state == NULL)
		return 1;
	meter_init(&a.meter, RATE);

	a.loop = pw_main_loop_new(NULL);
	loop = pw_main_loop_get_loop(a.loop);
	pw_loop_add_signal(loop, SIGINT, on_signal, &a);
	pw_loop_add_signal(loop, SIGTERM, on_signal, &a);

	a.context = pw_context_new(loop, NULL, 0);
	a.core = pw_context_connect(a.context, NULL, 0);
	if (a.core == NULL) {
		fprintf(stderr, "nixly-mic: cannot connect to pipewire\n");
		return 1;
	}
	pick_setup(&a);

	timer = pw_loop_add_timer(loop, on_timer, &a);
	pw_loop_update_timer(loop, timer, &every, &every, false);

	pw_main_loop_run(a.loop);

	store_gains(&a);
	state_save(a.state);
	meter_stop(&a);
	refgate_stop(&a);
	mixer_close(&a.mixer);
	state_free(a.state);
	pw_proxy_destroy((struct pw_proxy *)a.registry);
	pw_core_disconnect(a.core);
	pw_context_destroy(a.context);
	pw_main_loop_destroy(a.loop);
	pw_deinit();
	return 0;
}
