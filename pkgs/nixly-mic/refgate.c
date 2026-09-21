/* Freezes metering while speakers play. */
#include "app.h"

#include <math.h>

#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>

#define REF_OPEN 0.003f
#define REF_HOLD 0.6

static void on_process(void *data)
{
	struct app *a = data;
	struct pw_buffer *b;
	struct spa_data *d;
	const float *s;
	float peak = 0.0f;
	uint32_t i, n;

	if ((b = pw_stream_dequeue_buffer(a->ref_stream)) == NULL)
		return;
	d = &b->buffer->datas[0];
	if (d->data && d->chunk->size) {
		s = (const float *)((uint8_t *)d->data + d->chunk->offset);
		n = d->chunk->size / sizeof(float);
		for (i = 0; i < n; i++)
			peak = fmaxf(peak, fabsf(s[i]));
	}
	if (peak > REF_OPEN)
		a->ref_hot_until = mono_now() + REF_HOLD;
	pw_stream_queue_buffer(a->ref_stream, b);
}

static const struct pw_stream_events stream_events = {
	PW_VERSION_STREAM_EVENTS,
	.process = on_process,
};

void refgate_stop(struct app *a)
{
	if (a->ref_stream == NULL)
		return;
	spa_hook_remove(&a->ref_listener);
	pw_stream_destroy(a->ref_stream);
	a->ref_stream = NULL;
	a->ref_hot_until = 0.0;
}

void refgate_start(struct app *a)
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

	if (a->ref_stream != NULL)
		return;
	a->ref_stream = pw_stream_new(a->core, "nixly-mic-refgate",
		pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio",
				  PW_KEY_MEDIA_CATEGORY, "Capture",
				  PW_KEY_STREAM_CAPTURE_SINK, "true",
				  PW_KEY_NODE_NAME, "nixly-mic-refgate",
				  PW_KEY_NODE_DESCRIPTION, "NixlyMic playback gate",
				  PW_KEY_NODE_PASSIVE, "true",
				  PW_KEY_NODE_LATENCY, "1024/48000",
				  NULL));
	if (a->ref_stream == NULL)
		return;
	pw_stream_add_listener(a->ref_stream, &a->ref_listener, &stream_events, a);
	params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &fmt);
	pw_stream_connect(a->ref_stream, SPA_DIRECTION_INPUT, PW_ID_ANY,
			  PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS,
			  params, 1);
}
