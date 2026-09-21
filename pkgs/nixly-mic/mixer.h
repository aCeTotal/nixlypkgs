#pragma once

#include <stdbool.h>

#include <alsa/asoundlib.h>

/* The capture element of the sound card: the only gain stage that sits ahead
 * of the converter, so it is the one that decides clipping. */
#define MAX_BOOST 4

struct mixer {
	snd_mixer_t *handle;
	snd_mixer_elem_t *elem;
	snd_mixer_elem_t *boost[MAX_BOOST];
	int n_boost;
	float min_db;
	float max_db;
};

bool mixer_open(struct mixer *m, int card);
void mixer_close(struct mixer *m);
bool mixer_set_db(struct mixer *m, float db);
bool mixer_get_db(struct mixer *m, float *db);
void mixer_pin_boost(struct mixer *m);
