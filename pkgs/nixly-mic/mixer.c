/* ALSA capture gain of the card the selected microphone belongs to. */
#include "mixer.h"

#include <stdio.h>
#include <string.h>

#define PREFERRED "Capture"

static snd_mixer_elem_t *pick_elem(snd_mixer_t *h)
{
	snd_mixer_elem_t *e, *first = NULL;

	for (e = snd_mixer_first_elem(h); e; e = snd_mixer_elem_next(e)) {
		long lo, hi;

		if (!snd_mixer_selem_has_capture_volume(e))
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
