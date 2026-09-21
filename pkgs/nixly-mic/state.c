#include "state.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAX_MICS 32
#define KEY_LEN 160

struct entry {
	char key[KEY_LEN];
	float hw_db;
	float sens_db;
	bool learned;
};

struct state {
	struct entry e[MAX_MICS];
	int n;
	char preferred[KEY_LEN];
	char path[512];
	bool dirty;
};

static void state_path(char *buf, size_t len)
{
	const char *base = getenv("XDG_STATE_HOME");
	char dir[448];

	if (base && base[0])
		snprintf(dir, sizeof(dir), "%s/nixly-mic", base);
	else
		snprintf(dir, sizeof(dir), "%s/.local/state/nixly-mic", getenv("HOME"));
	mkdir(dir, 0700);
	snprintf(buf, len, "%s/gains", dir);
}

struct state *state_load(void)
{
	struct state *s = calloc(1, sizeof(*s));
	char line[KEY_LEN + 64];
	FILE *f;

	if (s == NULL)
		return NULL;
	state_path(s->path, sizeof(s->path));
	if ((f = fopen(s->path, "r")) == NULL)
		return s;

	while (fgets(line, sizeof(line), f)) {
		char key[KEY_LEN];
		float hw, sens;
		int learned;

		if (sscanf(line, "preferred\t%159[^\n]", key) == 1) {
			snprintf(s->preferred, sizeof(s->preferred), "%s", key);
			continue;
		}
		if (sscanf(line, "%159[^\t]\t%f\t%f\t%d", key, &hw, &sens, &learned) != 4)
			continue;
		if (s->n >= MAX_MICS)
			break;
		snprintf(s->e[s->n].key, KEY_LEN, "%s", key);
		s->e[s->n].hw_db = hw;
		s->e[s->n].sens_db = sens;
		s->e[s->n].learned = learned != 0;
		s->n++;
	}
	fclose(f);
	return s;
}

void state_free(struct state *s)
{
	free(s);
}

static struct entry *find(struct state *s, const char *key)
{
	int i;

	for (i = 0; i < s->n; i++)
		if (strcmp(s->e[i].key, key) == 0)
			return &s->e[i];
	return NULL;
}

bool state_get(struct state *s, const char *key, float *hw_db, float *sens_db,
	       bool *learned)
{
	struct entry *e = find(s, key);

	if (e == NULL)
		return false;
	*hw_db = e->hw_db;
	*sens_db = e->sens_db;
	*learned = e->learned;
	return true;
}

void state_set(struct state *s, const char *key, float hw_db, float sens_db,
	       bool learned)
{
	struct entry *e = find(s, key);

	if (e == NULL) {
		/* Oldest entry is recycled once the table is full. */
		if (s->n < MAX_MICS)
			e = &s->e[s->n++];
		else
			e = &s->e[0];
		snprintf(e->key, KEY_LEN, "%s", key);
	}
	if (e->hw_db == hw_db && e->sens_db == sens_db && e->learned == learned)
		return;
	e->hw_db = hw_db;
	e->sens_db = sens_db;
	e->learned = learned;
	s->dirty = true;
}

const char *state_preferred(struct state *s)
{
	return s->preferred[0] ? s->preferred : NULL;
}

void state_set_preferred(struct state *s, const char *key)
{
	if (strcmp(s->preferred, key) == 0)
		return;
	snprintf(s->preferred, sizeof(s->preferred), "%s", key);
	s->dirty = true;
}

void state_save(struct state *s)
{
	char tmp[540];
	FILE *f;
	int i;

	if (!s->dirty)
		return;
	snprintf(tmp, sizeof(tmp), "%s.new", s->path);
	if ((f = fopen(tmp, "w")) == NULL)
		return;
	if (s->preferred[0])
		fprintf(f, "preferred\t%s\n", s->preferred);
	for (i = 0; i < s->n; i++)
		fprintf(f, "%s\t%.2f\t%.2f\t%d\n", s->e[i].key, s->e[i].hw_db,
			s->e[i].sens_db, s->e[i].learned);
	fclose(f);
	if (rename(tmp, s->path) == 0)
		s->dirty = false;
}
