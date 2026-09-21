#include "control.h"

#include <math.h>

#define TARGET_IN_DB -24.0f  /* quiet speech RMS handed to the compressor */
#define LOUD_AIM_DB -12.0f   /* where the loud seconds should peak */
#define LOUD_HI_DB -9.0f     /* above this the converter is running out of room */
#define LOUD_LO_DB -15.0f    /* below this it has room to spare */
#define PEAK_SECS 10         /* seconds of peak history before trusting it */
#define CLIP_LOCK 300.0      /* no gain increase for 5 min after clipping */
#define CLIP_STEP 3.0        /* min seconds between clip cuts */
#define LEARN_SECS 60.0f     /* speech heard before the mic counts as known */
#define QUIET_RESCUE 60.0f   /* silence that means the gain is too low */
#define RESCUE_STEP 6.0f
#define FAST_WINDOW 30.0     /* re-converge quickly after a gain change */
#define GAIN_LIMIT 20.0f     /* per linear node, two of them in the chain */

static float clampf(float v, float lo, float hi)
{
	return v < lo ? lo : (v > hi ? hi : v);
}

void control_range(struct control *c, float min_db, float max_db)
{
	c->hw_min = min_db;
	c->hw_max = max_db;
	c->hw_start = max_db - HW_START_BELOW_MAX;
	c->hw_db = clampf(c->hw_db, min_db, max_db);
}

void control_reset(struct control *c, float hw_db, float sens_db, bool learned)
{
	c->hw_db = hw_db;
	c->sens_db = sens_db;
	c->learned = learned;
	c->learn_secs = 0.0f;
	c->seen_speech = 0.0f;
	c->clip_lock = 0.0;
	c->last_clip = 0.0;
	c->last_up = 0.0;
	c->last_sens = 0.0;
	c->fast_until = 0.0;
}

/* Lowering the card's gain is allowed on any sound, since clipping ruins the
 * signal whoever made it; raising it waits for speech. */
static bool tick_hw(struct control *c, struct meter *m, double now)
{
	bool clipped = m->clips > 0;
	float loud, want = 0.0f, db;

	m->clips = 0;
	if (clipped && now - c->last_clip >= CLIP_STEP) {
		want = -6.0f;
		c->last_clip = now;
		c->clip_lock = now + CLIP_LOCK;
	} else if (m->quiet_secs > QUIET_RESCUE && m->peaks_len == 0 &&
		   now > c->clip_lock && c->hw_db < c->hw_max) {
		/* Not one word heard since this gain was set. Feel upwards: a
		 * voice too faint to detect is the only thing that looks like
		 * this, and the card's maximum bounds the search. */
		want = fminf(RESCUE_STEP, c->hw_max - c->hw_db);
	} else if (meter_peak_level(m, PEAK_SECS, 0.9f, &loud)) {
		if (loud > LOUD_HI_DB)
			want = LOUD_AIM_DB - loud;
		else if (loud < LOUD_LO_DB && m->speech_secs > 3.0f &&
			 now > c->clip_lock &&
			 now - c->last_up >= (c->learned ? 10.0 : 3.0)) {
			want = LOUD_AIM_DB - loud;
			c->last_up = now;
		}
	}
	if (want == 0.0f)
		return false;

	db = clampf(c->hw_db + clampf(want, -12.0f, 24.0f), c->hw_min, c->hw_max);
	if (db == c->hw_db)
		return false;
	c->hw_db = db;
	/* Every level we measured was taken at the old gain. */
	meter_init(m, m->rate);
	c->fast_until = now + FAST_WINDOW;
	return true;
}

/* The mic counts as known once a minute of speech has passed through it,
 * counted across the meter restarts a card gain change forces. */
static bool tick_learn(struct control *c, struct meter *m)
{
	if (m->speech_secs >= c->seen_speech)
		c->learn_secs += m->speech_secs - c->seen_speech;
	c->seen_speech = m->speech_secs;

	if (c->learned || c->learn_secs < LEARN_SECS)
		return false;
	c->learned = true;
	return true;
}

static bool tick_sens(struct control *c, struct meter *m, double now)
{
	bool fresh = !c->learned;
	bool fast = fresh || now < c->fast_until;
	double period = fast ? 5.0 : 60.0;
	int min_len = fast ? 5 : 120;
	float dead = fast ? 2.0f : 4.0f;
	/* Only an unknown mic may jump: every later step has to be inaudible. */
	float up = fresh ? 6.0f : (fast ? 2.0f : 1.0f);
	float down = fresh ? 6.0f : (fast ? 2.0f : 0.5f);
	float quiet, want, d;

	if (now - c->last_sens < period)
		return false;
	c->last_sens = now;
	/* A low percentile of speech loudness: shouting only adds high values,
	 * so it can never drag the gain down. */
	if (!meter_level(m, min_len, 0.25f, &quiet))
		return false;

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

	if (tick_learn(c, m))
		changed |= CONTROL_LEARNED;
	if (tick_hw(c, m, now))
		changed |= CONTROL_HW | CONTROL_GAIN;
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
