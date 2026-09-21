/* ALSA capture gain of the card the selected microphone belongs to. */
#include "mixer.h"

#include <stdio.h>
#include <string.h>

#define PREFERRED "Capture"
#define BOOST "Boost"
#define BOOST_STEPS 1   /* one step of mic preamp, never the coarse jumps above */

static bool is_boost(snd_mixer_elem_t *e)
{
	const char *n = snd_mixer_selem_get_name(e);
	size_t len = strlen(n), suf = strlen(BOOST);

	return len > suf && strcmp(n + len - suf, BOOST) == 0;
}

/* WirePlumber writes the whole ALSA path when it sets the route to unity,
 * which lands the preamp on its maximum. The card's gain is ours, so it is
 * held at one step and the capture element does the moving. */
void mixer_pin_boost(struct mixer *m)
{
	int i;

	for (i = 0; i < m->n_boost; i++) {
		long lo, hi, want, cur;

		if (snd_mixer_selem_get_capture_volume_range(m->boost[i], &lo, &hi) < 0)
			continue;
		want = lo + BOOST_STEPS < hi ? lo + BOOST_STEPS : hi;
		if (snd_mixer_selem_get_capture_volume(m->boost[i],
						       SND_MIXER_SCHN_FRONT_LEFT, &cur) == 0 &&
		    cur == want)
			continue;
		snd_mixer_selem_set_capture_volume_all(m->boost[i], want);
	}
}

static snd_mixer_elem_t *pick_elem(snd_mixer_t *h)
{
	snd_mixer_elem_t *e, *first = NULL;

	for (e = snd_mixer_first_elem(h); e; e = snd_mixer_elem_next(e)) {
		long lo, hi;

		if (!snd_mixer_selem_has_capture_volume(e) || is_boost(e))
			continue;
		if (snd_mixer_selem_get_capture_dB_range(e, &lo, &hi) < 0 || lo >= hi)
			continue;
		if (strcmp(snd_mixer_selem_get_name(e), PREFERRED) == 0)
			return e;
		if (first == NULL)
			first = e;
	}
	return first;
}

bool mixer_open(struct mixer *m, int card)
{
	snd_mixer_elem_t *e;
	char name[16];
	long lo, hi;

	snprintf(name, sizeof(name), "hw:%d", card);
	memset(m, 0, sizeof(*m));
	if (snd_mixer_open(&m->handle, 0) < 0)
		return false;
	if (snd_mixer_attach(m->handle, name) < 0 ||
	    snd_mixer_selem_register(m->handle, NULL, NULL) < 0 ||
	    snd_mixer_load(m->handle) < 0) {
		mixer_close(m);
		return false;
	}
	if ((m->elem = pick_elem(m->handle)) == NULL) {
		mixer_close(m);
		return false;
	}
	for (e = snd_mixer_first_elem(m->handle); e; e = snd_mixer_elem_next(e))
		if (is_boost(e) && snd_mixer_selem_has_capture_volume(e) &&
		    m->n_boost < MAX_BOOST)
			m->boost[m->n_boost++] = e;
	mixer_pin_boost(m);
	snd_mixer_selem_get_capture_dB_range(m->elem, &lo, &hi);
	m->min_db = lo / 100.0f;
	m->max_db = hi / 100.0f;
	return true;
}

void mixer_close(struct mixer *m)
{
	if (m->handle)
		snd_mixer_close(m->handle);
	memset(m, 0, sizeof(*m));
}

bool mixer_set_db(struct mixer *m, float db)
{
	if (m->elem == NULL)
		return false;
	/* Round towards less gain so a step never buys clipping. */
	return snd_mixer_selem_set_capture_dB_all(m->elem, (long)(db * 100.0f), -1) == 0;
}

bool mixer_get_db(struct mixer *m, float *db)
{
	long v;

	if (m->elem == NULL)
		return false;
	snd_mixer_handle_events(m->handle);
	if (snd_mixer_selem_get_capture_dB(m->elem, SND_MIXER_SCHN_FRONT_LEFT, &v) < 0)
		return false;
	*db = v / 100.0f;
	return true;
}
