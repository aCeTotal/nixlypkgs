#include "control.h"

#include <math.h>

#define TARGET_IN_DB -24.0f  /* quiet speech RMS handed to the compressor */
#define LOUD_AIM_DB -12.0f   /* where the decayed speech peak should sit */
#define LOUD_HI_DB -6.0f     /* above this the ADC is running out of room */
#define LOUD_LO_DB -18.0f    /* below this it has room to spare */
#define CLIP_LOCK 300.0      /* no volume increase for 5 min after clipping */
#define FAST_WINDOW 30.0     /* re-converge quickly after a volume change */
#define VOL_MIN 0.0005f
#define VOL_MAX 1.0f
#define GAIN_LIMIT 20.0f     /* per linear node, two of them in the chain */

static float clampf(float v, float lo, float hi)
{
	return v < lo ? lo : (v > hi ? hi : v);
}

void control_reset(struct control *c, float vol, float sens_db, bool learned)
{
	c->vol = clampf(vol, VOL_MIN, VOL_MAX);
	c->sens_db = sens_db;
	c->learned = learned;
	c->clip_lock = 0.0;
	c->last_up = 0.0;
	c->last_sens = 0.0;
	c->fast_until = 0.0;
}

/* The volume curve is the card's, not ours, so aim for the measured error and
 * under-relax instead of assuming a dB per step. */
static bool tick_volume(struct control *c, struct meter *m, double now)
{
	float want = 0.0f, vol;

	if (m->clips > 0) {
		want = -8.0f;
		c->clip_lock = now + CLIP_LOCK;
	} else if (m->speech_secs > 3.0f && m->loud_db > LOUD_HI_DB) {
		want = LOUD_AIM_DB - m->loud_db;
	} else if (m->speech_secs > 3.0f && m->loud_db < LOUD_LO_DB &&
		   now > c->clip_lock &&
		   now - c->last_up >= (c->learned ? 10.0 : 3.0)) {
		want = LOUD_AIM_DB - m->loud_db;
		c->last_up = now;
	}
	m->clips = 0;
	if (want == 0.0f)
		return false;

	vol = clampf(c->vol * powf(10.0f, clampf(0.7f * want, -12.0f, 12.0f) / 20.0f),
		     VOL_MIN, VOL_MAX);
	if (vol == c->vol)
		return false;
	c->vol = vol;
	/* Every level we measured was taken at the old volume. */
	meter_init(m, m->rate);
	c->fast_until = now + FAST_WINDOW;
	return true;
}

static bool tick_sens(struct control *c, struct meter *m, double now)
{
	bool fast = !c->learned || now < c->fast_until;
	double period = fast ? 5.0 : 60.0;
	int min_len = fast ? 5 : 120;
	float dead = fast ? 1.0f : 4.0f;
	float up = fast ? 6.0f : 1.0f;
	float down = fast ? 6.0f : 0.5f;
	float quiet, want, d;

	if (now - c->last_sens < period)
		return false;
	c->last_sens = now;
	/* A low percentile of speech loudness: shouting only adds high values,
	 * so it can never drag the gain down. */
	if (!meter_level(m, min_len, 0.25f, &quiet))
		return false;
	if (!c->learned && m->hist_len >= 60)
		c->learned = true;

	want = TARGET_IN_DB - quiet;
	d = want - c->sens_db;
	if (fabsf(d) <= dead)
		return false;
	c->sens_db = clampf(c->sens_db + clampf(d, -down, up),
			    -2.0f * GAIN_LIMIT, 2.0f * GAIN_LIMIT);
	return true;
}

int control_tick(struct control *c, struct meter *m, double now)
{
	int changed = 0;

	if (tick_volume(c, m, now))
		changed |= CONTROL_VOLUME | CONTROL_GAIN;
	if (tick_sens(c, m, now))
		changed |= CONTROL_GAIN;
	return changed;
}

float control_gain1_mult(const struct control *c)
{
	return powf(10.0f, clampf(c->sens_db, -GAIN_LIMIT, GAIN_LIMIT) / 20.0f);
}

float control_gain2_mult(const struct control *c)
{
	float rest = c->sens_db - clampf(c->sens_db, -GAIN_LIMIT, GAIN_LIMIT);

	return powf(10.0f, clampf(rest, -GAIN_LIMIT, GAIN_LIMIT) / 20.0f);
}
