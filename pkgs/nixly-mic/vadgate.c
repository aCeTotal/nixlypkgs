/* Tells the meter when someone is actually talking. The noise suppressor lets
 * a voice through untouched and holds everything else far down, so how much of
 * the signal survives the chain — not how loud it is — is the speech test. */
#include "app.h"

#include <math.h>

#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>

#define SPEECH_HOLD 0.3
#define SPEECH_KEPT 0.35f    /* share of the input the chain keeps for a voice */
#define QUIET_IN 1e-4f       /* below this there is nothing to judge */

static void on_process(void *data)
{
	struct app *a = data;
	struct pw_buffer *b;
	struct spa_data *d;
	const float *s;
	uint32_t i, n;

	if ((b = pw_stream_dequeue_buffer(a->vad_stream)) == NULL)
		return;
	d = &b->buffer->datas[0];
	if (d->data && d->chunk->size) {
		double sumsq = 0.0;
		float rms, kept;

		s = (const float *)((uint8_t *)d->data + d->chunk->offset);
		n = d->chunk->size / sizeof(float);
		for (i = 0; i < n; i++)
			sumsq += (double)s[i] * s[i];
		rms = sqrtf((float)(sumsq / n));
		/* The chain's own make-up gain is ours, so divide it back out. */
		kept = rms / powf(10.0f, a->ctl.sens_db / 20.0f);
		if (a->ec_rms > QUIET_IN && kept > SPEECH_KEPT * a->ec_rms)
			a->speech_until = mono_now() + SPEECH_HOLD;
	}
	pw_stream_queue_buffer(a->vad_stream, b);
}

static const struct pw_stream_events stream_events = {
	PW_VERSION_STREAM_EVENTS,
	.process = on_process,
};

void vadgate_stop(struct app *a)
{
	if (a->vad_stream == NULL)
		return;
	spa_hook_remove(&a->vad_listener);
	pw_stream_destroy(a->vad_stream);
	a->vad_stream = NULL;
	a->speech_until = 0.0;
}

void vadgate_start(struct app *a)
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

	if (a->vad_stream != NULL)
		return;
	a->vad_stream = pw_stream_new(a->core, "nixly-mic-vad",
		pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio",
				  PW_KEY_MEDIA_CATEGORY, "Capture",
				  PW_KEY_NODE_NAME, "nixly-mic-vad",
				  PW_KEY_NODE_DESCRIPTION, "NixlyMic speech gate",
				  PW_KEY_TARGET_OBJECT, FC_NODE,
				  PW_KEY_NODE_PASSIVE, "true",
				  PW_KEY_NODE_LATENCY, "1024/48000",
				  NULL));
	if (a->vad_stream == NULL)
		return;
	pw_stream_add_listener(a->vad_stream, &a->vad_listener, &stream_events, a);
	params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &fmt);
	pw_stream_connect(a->vad_stream, SPA_DIRECTION_INPUT, PW_ID_ANY,
			  PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS,
			  params, 1);
}
