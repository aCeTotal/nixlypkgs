#pragma once

#include <stdbool.h>

#include <pipewire/pipewire.h>
#include <pipewire/extensions/metadata.h>

#include "control.h"
#include "meter.h"
#include "mixer.h"
#include "state.h"

#define FC_NODE "nixly-mic"
#define TAP_SOURCE "nixly-mic-tap"
#define METER_NODE "nixly-mic-meter"
#define RATE 48000
#define NAME_LEN 160
#define MAX_NODES 64

struct node_info {
	uint32_t id;
	char name[NAME_LEN];
};

struct app {
	struct pw_main_loop *loop;
	struct pw_context *context;
	struct pw_core *core;
	struct pw_registry *registry;
	struct spa_hook registry_listener;

	struct pw_metadata *metadata;
	struct spa_hook metadata_listener;

	struct pw_proxy *fc_proxy;
	struct spa_hook fc_listener;

	struct pw_proxy *sel_proxy;
	struct spa_hook sel_listener;

	struct pw_proxy *dev_proxy;
	struct spa_hook dev_listener;
	uint32_t dev_id;
	int route_device;
	int route_index;
	uint32_t route_nch;
	bool hw_known;

	struct mixer mixer;
	int card;

	struct node_info nodes[MAX_NODES];
	int n_nodes;

	char selected[NAME_LEN];
	char wanted[NAME_LEN];

	struct meter meter;
	struct control ctl;
	struct state *state;

	struct pw_stream *stream;
	struct spa_hook stream_listener;
	struct pw_stream *ref_stream;
	struct spa_hook ref_listener;
	double ref_hot_until;
	double speech_until;
	bool fc_running;

	float pushed_g1;
	float pushed_g2;
	double save_at;
	bool verbose;
};

double mono_now(void);
void info(struct app *a, const char *fmt, ...);

void push_props(struct app *a);

void route_bind(struct app *a, uint32_t device_id);
void route_unbind(struct app *a);
void push_hw(struct app *a);

void meter_start(struct app *a);
void meter_stop(struct app *a);
void update_metering(struct app *a);

void refgate_start(struct app *a);
void refgate_stop(struct app *a);

void pick_setup(struct app *a);
void store_gains(struct app *a);
