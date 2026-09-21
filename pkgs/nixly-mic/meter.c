#include "meter.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define FRAME_SEC 0.020f
#define FLOOR_RISE (0.04f * FRAME_SEC)   /* noise floor climbs 0.04 dB/s */
#define FLOOR_FALL 0.25f
#define SPEECH_FRAMES 10                 /* per second, before it counts */
#define SPEECH_OVER 12.0f                /* dB above the floor to be a voice */
#define CLIP_LEVEL 0.985f

void meter_init(struct meter *m, int rate)
{
	memset(m, 0, sizeof(*m));
	m->rate = rate;
	m->frame_len = (int)(rate * FRAME_SEC);
	/* High, so the first quiet gap pulls it down to the real floor. */
	m->floor_db = -20.0f;
}

static void push_hist(float *hist, int *len, int *pos, float v)
{
	hist[*pos] = v;
	*pos = (*pos + 1) % METER_HIST;
	if (*len < METER_HIST)
		(*len)++;
}

static void second_done(struct meter *m)
{
	if (m->sec_n >= SPEECH_FRAMES) {
		push_hist(m->hist, &m->hist_len, &m->hist_pos,
			  (float)(m->sec_sum / m->sec_n));
		push_hist(m->peaks, &m->peaks_len, &m->peaks_pos,
			  20.0f * log10f(m->sec_peak + 1e-12f));
	} else {
		m->quiet_secs += 1.0f;
	}
	m->sec_acc = 0.0;
	m->sec_sum = 0.0;
	m->sec_n = 0;
	m->sec_peak = 0.0f;
}

static bool frame_done(struct meter *m)
{
	float rms_db = 10.0f * log10f((float)(m->sumsq / m->n) + 1e-12f);
	bool speech;

	if (rms_db < m->floor_db)
		m->floor_db += (rms_db - m->floor_db) * FLOOR_FALL;
	else
		m->floor_db += FLOOR_RISE;

	speech = rms_db > m->floor_db + SPEECH_OVER;
	if (speech) {
		m->speech_secs += FRAME_SEC;
		m->quiet_secs = 0.0f;
		m->sec_sum += rms_db;
		m->sec_n++;
		if (m->peak > m->sec_peak)
			m->sec_peak = m->peak;
	}
	if (m->peak >= CLIP_LEVEL)
		m->clips++;

	m->sec_acc += FRAME_SEC;
	if (m->sec_acc >= 1.0)
		second_done(m);

	m->n = 0;
	m->peak = 0.0f;
	m->sumsq = 0.0;
	return speech;
}

bool meter_push(struct meter *m, const float *s, int n)
{
	bool speech = false;
	int i;

	for (i = 0; i < n; i++) {
		float v = fabsf(s[i]);
		if (v > m->peak)
			m->peak = v;
		m->sumsq += (double)s[i] * s[i];
		if (++m->n >= m->frame_len)
			speech |= frame_done(m);
	}
	return speech;
}

static int cmp_float(const void *a, const void *b)
{
	float x = *(const float *)a, y = *(const float *)b;
	return x < y ? -1 : x > y;
}

static bool percentile(const float *hist, int len, int min_len, float pct,
		       float *out_db)
{
	float tmp[METER_HIST];

	if (len < min_len)
		return false;
	memcpy(tmp, hist, len * sizeof(float));
	qsort(tmp, len, sizeof(float), cmp_float);
	*out_db = tmp[(int)(pct * (len - 1))];
	return true;
}

bool meter_level(const struct meter *m, int min_len, float pct, float *out_db)
{
	return percentile(m->hist, m->hist_len, min_len, pct, out_db);
}

bool meter_peak_level(const struct meter *m, int min_len, float pct, float *out_db)
{
	return percentile(m->peaks, m->peaks_len, min_len, pct, out_db);
}
