#pragma once

#include <stdbool.h>

struct state;

/* Learned gains per microphone, kept across sessions. */
struct state *state_load(void);
void state_free(struct state *s);
bool state_get(struct state *s, const char *key, float *hw_db, float *sens_db,
	       bool *learned);
void state_set(struct state *s, const char *key, float hw_db, float sens_db,
	       bool learned);
const char *state_preferred(struct state *s);
void state_set_preferred(struct state *s, const char *key);
void state_save(struct state *s);
