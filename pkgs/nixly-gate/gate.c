/* Mic gate driven by nixlytile's shared word. */
#include <fcntl.h>
#include <ladspa.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define GATE_FILE "nixly-gate"
#define GATE_ID 5130068
#define BIT_MAX 31
#define MS_PER_SEC 1000.0f
#define REOPEN_MAX_MS 1000.0f
#define FADE_MAX_MS 100.0f

enum { PORT_INPUT, PORT_OUTPUT, PORT_BIT, PORT_REOPEN, PORT_FADE, PORT_COUNT };

struct gate {
	LADSPA_Data *port[PORT_COUNT];
	const uint32_t *word;
	float rate;
	unsigned long hold;
	float gain;
};

static const uint32_t open_word;

static const uint32_t *map_word(void)
{
	const char *dir = getenv("XDG_RUNTIME_DIR");
	char path[PATH_MAX];
	struct stat st;
	void *map;
	int fd;

	if (dir)
		snprintf(path, sizeof(path), "%s/" GATE_FILE, dir);
	else
		snprintf(path, sizeof(path), "/run/user/%u/" GATE_FILE, getuid());

	fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
	if (fd < 0)
		return NULL;
	if (fstat(fd, &st) < 0 ||
	    (st.st_size < (off_t)sizeof(uint32_t) && ftruncate(fd, sizeof(uint32_t)) < 0)) {
		close(fd);
		return NULL;
	}
	map = mmap(NULL, sizeof(uint32_t), PROT_READ, MAP_SHARED, fd, 0);
	close(fd);
	return map == MAP_FAILED ? NULL : map;
}

static int closed(const struct gate *g)
{
	uint32_t bit = (uint32_t)*g->port[PORT_BIT] & BIT_MAX;

	return __atomic_load_n(g->word, __ATOMIC_ACQUIRE) >> bit & 1;
}

static unsigned long samples(const struct gate *g, LADSPA_Data ms)
{
	return ms > 0.0f ? (unsigned long)(ms * g->rate / MS_PER_SEC) : 0;
}

static void fade_out(struct gate *g, const LADSPA_Data *in, LADSPA_Data *out,
		     unsigned long n)
{
	unsigned long len = samples(g, *g->port[PORT_FADE]);
	float step = len ? 1.0f / (float)len : 1.0f;

	for (unsigned long i = 0; i < n; i++) {
		g->gain = g->gain > step ? g->gain - step : 0.0f;
		out[i] = g->gain > 0.0f ? in[i] * g->gain : 0.0f;
	}
}

static LADSPA_Handle instantiate(const LADSPA_Descriptor *desc, unsigned long rate)
{
	struct gate *g = calloc(1, sizeof(*g));

	(void)desc;
	if (!g)
		return NULL;
	g->rate = (float)rate;
	g->word = map_word();
	if (g->word)
		return g;
	fprintf(stderr, "nixly-gate: cannot map " GATE_FILE ", gate stays open\n");
	g->word = &open_word;
	return g;
}

static void connect_port(LADSPA_Handle h, unsigned long port, LADSPA_Data *buf)
{
	struct gate *g = h;

	g->port[port] = buf;
}

static void activate(LADSPA_Handle h)
{
	struct gate *g = h;

	g->hold = 0;
	g->gain = closed(g) ? 0.0f : 1.0f;
}

static void run(LADSPA_Handle h, unsigned long n)
{
	struct gate *g = h;
	const LADSPA_Data *in = g->port[PORT_INPUT];
	LADSPA_Data *out = g->port[PORT_OUTPUT];

	if (closed(g)) {
		g->hold = samples(g, *g->port[PORT_REOPEN]);
		fade_out(g, in, out, n);
		return;
	}
	if (g->hold) {
		g->hold = g->hold > n ? g->hold - n : 0;
		fade_out(g, in, out, n);
		return;
	}
	g->gain = 1.0f;
	for (unsigned long i = 0; i < n; i++)
		out[i] = in[i];
}

static void cleanup(LADSPA_Handle h)
{
	struct gate *g = h;

	if (g->word != &open_word)
		munmap((void *)g->word, sizeof(uint32_t));
	free(g);
}

static const LADSPA_PortDescriptor port_kinds[PORT_COUNT] = {
	LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO,
	LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO,
	LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
	LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
	LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
};

static const char *const port_names[PORT_COUNT] = {
	"Input", "Output", "Bit", "Reopen (ms)", "Fade (ms)",
};

static const LADSPA_PortRangeHint port_hints[PORT_COUNT] = {
	{ 0, 0.0f, 0.0f },
	{ 0, 0.0f, 0.0f },
	{ LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
	  LADSPA_HINT_INTEGER | LADSPA_HINT_DEFAULT_0, 0.0f, BIT_MAX },
	{ LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
	  LADSPA_HINT_DEFAULT_0, 0.0f, REOPEN_MAX_MS },
	{ LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
	  LADSPA_HINT_DEFAULT_0, 0.0f, FADE_MAX_MS },
};

static const LADSPA_Descriptor descriptor = {
	.UniqueID = GATE_ID,
	.Label = "nixly_gate",
	.Properties = LADSPA_PROPERTY_HARD_RT_CAPABLE,
	.Name = "Nixly gate",
	.Maker = "NixlyOS",
	.Copyright = "None",
	.PortCount = PORT_COUNT,
	.PortDescriptors = port_kinds,
	.PortNames = port_names,
	.PortRangeHints = port_hints,
	.instantiate = instantiate,
	.connect_port = connect_port,
	.activate = activate,
	.run = run,
	.cleanup = cleanup,
};

const LADSPA_Descriptor *ladspa_descriptor(unsigned long index)
{
	return index == 0 ? &descriptor : NULL;
}
