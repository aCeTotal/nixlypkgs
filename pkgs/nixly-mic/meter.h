#pragma once

#include <stdbool.h>

#define METER_HIST 600

/* Speech level statistics measured on the raw (post-hardware-gain) mic. */
struct meter {
	int rate;
	int frame_len;

	int n;
	float peak;
	double sumsq;

	float floor_db;
	float loud_db;
	float speech_secs;
	int clips;

	double sec_acc;
	double sec_sum;
	int sec_n;

	float hist[METER_HIST];
	int hist_len;
	int hist_pos;
};

void meter_init(struct meter *m, int rate);
void meter_push(struct meter *m, const float *s, int n);
bool meter_level(const struct meter *m, int min_len, float pct, float *out_db);
