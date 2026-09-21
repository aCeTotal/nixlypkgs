#pragma once

#include <stdbool.h>

#include "meter.h"

#define CONTROL_VOLUME 1
#define CONTROL_GAIN 2

/* Capture volume rides the ADC headroom; sens_db sets the level the chain
 * works at. Loud talking never moves either: both react to long windows. */
struct control {
	float vol;
	float sens_db;
	bool learned;

	double clip_lock;
	double last_up;
	double last_sens;
	double fast_until;
};

void control_reset(struct control *c, float vol, float sens_db, bool learned);
int control_tick(struct control *c, struct meter *m, double now);
float control_gain1_mult(const struct control *c);
float control_gain2_mult(const struct control *c);
