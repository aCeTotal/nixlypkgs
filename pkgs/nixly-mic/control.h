#pragma once

#include <stdbool.h>

#include "meter.h"

#define CONTROL_HW 1
#define CONTROL_GAIN 2
#define CONTROL_LEARNED 4

/* Headroom below the card's maximum when nothing has been learned yet. */
#define HW_START_BELOW_MAX 20.0f

/* The card's capture gain rides the converter headroom; sens_db sets the level
 * the chain works at. Loud talking never moves either: both react to long
 * windows. */
struct control {
	float hw_db;
	float hw_min;
	float hw_max;
	float hw_start;
	float sens_db;
	bool learned;
	float learn_secs;
	float seen_speech;

	double clip_lock;
	double last_clip;
	double last_up;
	double last_sens;
	double fast_until;
};

void control_range(struct control *c, float min_db, float max_db);
void control_reset(struct control *c, float hw_db, float sens_db, bool learned);
int control_tick(struct control *c, struct meter *m, double now);
float control_gain1_mult(const struct control *c);
float control_gain2_mult(const struct control *c);
