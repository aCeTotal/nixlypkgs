#include "meter.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define FRAME_SEC 0.020f
#define FLOOR_RISE (0.04f * FRAME_SEC)   /* noise floor climbs 0.04 dB/s */
#define FLOOR_FALL 0.25f
#define LOUD_DECAY (0.02f * FRAME_SEC)   /* shout memory: -0.02 dB/s */
#define SPEECH_OVER_FLOOR 9.0f
#define SPEECH_FLOOR_DB -55.0f
#define CLIP_LEVEL 0.985f

void meter_init(struct meter *m, int rate)
{
	memset(m, 0, sizeof(*m));
	m->rate = rate;
	m->frame_len = (int)(rate * FRAME_SEC);
	m->floor_db = -60.0f;
	m->loud_db = -60.0f;
}

static void frame_done(struct meter *m)
{
	float rms_db = 10.0f * log10f((float)(m->sumsq / m->n) + 1e-12f);
	float peak_db = 20.0f * log10f(m->peak + 1e-12f);
	bool speech;

	if (rms_db < m->floor_db)
		m->floor_db += (rms_db - m->floor_db) * FLOOR_FALL;
	else
		m->floor_db += FLOOR_RISE;

	speech = rms_db > m->floor_db + SPEECH_OVER_FLOOR && rms_db > SPEECH_FLOOR_DB;
	if (speech) {
		m->loud_db = fmaxf(m->loud_db - LOUD_DECAY, peak_db);
		m->speech_secs += FRAME_SEC;
		m->sec_sum += rms_db;
		m->sec_n++;
	} else {
		m->loud_db -= LOUD_DECAY;
	}
	if (m->peak >= CLIP_LEVEL)
		m->clips++;

	m->sec_acc += FRAME_SEC;
	if (m->sec_acc >= 1.0) {
		/* Keep only seconds that were mostly speech out of the median. */
		if (m->sec_n >= 10) {
			m->hist[m->hist_pos] = (float)(m->sec_sum / m->sec_n);
			m->hist_pos = (m->hist_pos + 1) % METER_HIST;
			if (m->hist_len < METER_HIST)
				m->hist_len++;
		}
		m->sec_acc = 0.0;
		m->sec_sum = 0.0;
		m->sec_n = 0;
	}

	m->n = 0;
	m->peak = 0.0f;
	m->sumsq = 0.0;
}

void meter_push(struct meter *m, const float *s, int n)
{
	int i;

	for (i = 0; i < n; i++) {
		float v = fabsf(s[i]);
		if (v > m->peak)
			m->peak = v;
		m->sumsq += (double)s[i] * s[i];
		if (++m->n >= m->frame_len)
			frame_done(m);
	}
}


static int cmp_float(const void *a, const void *b)
{
	float x = *(const float *)a, y = *(const float *)b;
	return x < y ? -1 : x > y;
}

bool meter_level(const struct meter *m, int min_len, float pct, float *out_db)
{
	float tmp[METER_HIST];

	if (m->hist_len < min_len)
		return false;
	memcpy(tmp, m->hist, m->hist_len * sizeof(float));
	qsort(tmp, m->hist_len, sizeof(float), cmp_float);
	*out_db = tmp[(int)(pct * (m->hist_len - 1))];
	return true;
}
