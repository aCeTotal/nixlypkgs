#pragma once

#include <stdbool.h>

#define METER_HIST 600

/* Speech level statistics measured on the echo cancelled microphone. Which
 * frames hold speech is decided by the chain's noise suppressor, not by level,
 * so a noisy room cannot pass for a voice. */
struct meter {
	int rate;
	int frame_len;

	int n;
	float peak;
	double sumsq;

	float floor_db;
	float speech_secs;
	float quiet_secs;
	int clips;

	double sec_acc;
	double sec_sum;
	int sec_n;
	float sec_peak;

	float hist[METER_HIST];
	int hist_len;
	int hist_pos;

	float peaks[METER_HIST];
	int peaks_len;
	int peaks_pos;
};

void meter_init(struct meter *m, int rate);
void meter_push(struct meter *m, const float *s, int n, bool speech);
bool meter_level(const struct meter *m, int min_len, float pct, float *out_db);
bool meter_peak_level(const struct meter *m, int min_len, float pct, float *out_db);
