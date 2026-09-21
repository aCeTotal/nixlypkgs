/* Level measurement stream, tapped off the echo-cancelled mic. It only runs
 * while something is actually using NixlyMic, so an idle machine never holds
 * the microphone open. */
#include "app.h"

#include <math.h>

#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>

/* What the speech gate compares the chain's output against. */
static float buffer_rms(const float *s, uint32_t n)
{
	double sumsq = 0.0;
	uint32_t i;

	for (i = 0; i < n; i++)
		sumsq += (double)s[i] * s[i];
	return n ? sqrtf((float)(sumsq / n)) : 0.0f;
}

static void on_process(void *data)
{
	struct app *a = data;
	struct pw_buffer *b;
	struct spa_data *d;

	if ((b = pw_stream_dequeue_buffer(a->stream)) == NULL)
		return;
	d = &b->buffer->datas[0];
	if (d->data && d->chunk->size) {
		double now = mono_now();

		a->ec_rms = buffer_rms((float *)((uint8_t *)d->data + d->chunk->offset),
				       d->chunk->size / sizeof(float));
		if (now >= a->ref_hot_until)
			meter_push(&a->meter,
				   (float *)((uint8_t *)d->data + d->chunk->offset),
				   d->chunk->size / sizeof(float),
				   now < a->speech_until);
	}
	pw_stream_queue_buffer(a->stream, b);
}

static const struct pw_stream_events stream_events = {
	PW_VERSION_STREAM_EVENTS,
	.process = on_process,
};

void meter_stop(struct app *a)
{
	if (a->stream == NULL)
		return;
	spa_hook_remove(&a->stream_listener);
	pw_stream_destroy(a->stream);
	a->stream = NULL;
}

void meter_start(struct app *a)
{
	uint8_t buf[512];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof(buf));
	const struct spa_pod *params[1];
	struct spa_audio_info_raw fmt = {
		.format = SPA_AUDIO_FORMAT_F32,
		.rate = RATE,
		.channels = 1,
		.position = { SPA_AUDIO_CHANNEL_MONO },
	};

	if (a->stream != NULL)
		return;
	a->stream = pw_stream_new(a->core, METER_NODE,
		pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio",
				  PW_KEY_MEDIA_CATEGORY, "Capture",
				  PW_KEY_NODE_NAME, METER_NODE,
				  PW_KEY_NODE_DESCRIPTION, "NixlyMic level meter",
				  PW_KEY_TARGET_OBJECT, TAP_SOURCE,
				  PW_KEY_NODE_LATENCY, "1024/48000",
				  NULL));
	if (a->stream == NULL)
		return;
	pw_stream_add_listener(a->stream, &a->stream_listener, &stream_events, a);
	params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &fmt);
	pw_stream_connect(a->stream, SPA_DIRECTION_INPUT, PW_ID_ANY,
			  PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS,
			  params, 1);
}

void update_metering(struct app *a)
{
	if (a->fc_running && a->selected[0]) {
		meter_start(a);
		refgate_start(a);
		vadgate_start(a);
		return;
	}
	meter_stop(a);
	refgate_stop(a);
	vadgate_stop(a);
}
