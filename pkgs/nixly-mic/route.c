/* Capture gain of the selected mic. The card's own capture element carries it,
 * so PipeWire's volume is pinned at unity and never attenuates behind us. */
#include "app.h"

#include <math.h>

#include <spa/param/audio/raw.h>
#include <spa/param/props.h>
#include <spa/param/route.h>
#include <spa/pod/builder.h>
#include <spa/pod/iter.h>
#include <spa/pod/parser.h>

#define DRIFT_DB 1.0f

void push_hw(struct app *a)
{
	float cur;

	if (a->mixer.elem == NULL)
		return;
	if (mixer_get_db(&a->mixer, &cur) && fabsf(cur - a->ctl.hw_db) < DRIFT_DB)
		return;
	if (mixer_set_db(&a->mixer, a->ctl.hw_db))
		info(a, "card gain: %.1f dB", a->ctl.hw_db);
}

static void push_unity(struct app *a)
{
	uint8_t buf[512];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof(buf));
	struct spa_pod_frame f[2];
	const struct spa_pod *pod;
	float vols[SPA_AUDIO_MAX_CHANNELS];
	uint32_t i, n = a->route_nch ? a->route_nch : 1;

	if (a->dev_proxy == NULL || a->route_index < 0)
		return;
	for (i = 0; i < n; i++)
		vols[i] = 1.0f;

	spa_pod_builder_push_object(&b, &f[0], SPA_TYPE_OBJECT_ParamRoute,
				    SPA_PARAM_Route);
	spa_pod_builder_add(&b,
			    SPA_PARAM_ROUTE_index, SPA_POD_Int(a->route_index),
			    SPA_PARAM_ROUTE_device, SPA_POD_Int(a->route_device),
			    0);
	spa_pod_builder_prop(&b, SPA_PARAM_ROUTE_props, 0);
	spa_pod_builder_push_object(&b, &f[1], SPA_TYPE_OBJECT_Props,
				    SPA_PARAM_Props);
	spa_pod_builder_prop(&b, SPA_PROP_channelVolumes, 0);
	spa_pod_builder_array(&b, sizeof(float), SPA_TYPE_Float, n, vols);
	spa_pod_builder_pop(&b, &f[1]);
	spa_pod_builder_prop(&b, SPA_PARAM_ROUTE_save, 0);
	spa_pod_builder_bool(&b, true);
	pod = spa_pod_builder_pop(&b, &f[0]);

	pw_device_set_param((struct pw_device *)a->dev_proxy, SPA_PARAM_Route,
			    0, pod);
}

static void on_dev_param(void *data, int seq, uint32_t id, uint32_t index,
			 uint32_t next, const struct spa_pod *param)
{
	struct app *a = data;
	struct spa_pod *props = NULL;
	struct spa_pod_prop *p;
	uint32_t idx, dev, dir;
	float vols[SPA_AUDIO_MAX_CHANNELS];
	uint32_t n = 0;

	if (id != SPA_PARAM_Route || param == NULL)
		return;
	if (spa_pod_parse_object(param, SPA_TYPE_OBJECT_ParamRoute, NULL,
				 SPA_PARAM_ROUTE_index, SPA_POD_Int(&idx),
				 SPA_PARAM_ROUTE_device, SPA_POD_Int(&dev),
				 SPA_PARAM_ROUTE_direction, SPA_POD_Id(&dir),
				 SPA_PARAM_ROUTE_props, SPA_POD_OPT_Pod(&props)) < 0)
		return;
	/* The card decides which profile device carries the input route, so take
	 * it from the route itself rather than from the node's properties. */
	if (dir != SPA_DIRECTION_INPUT)
		return;

	a->route_index = idx;
	a->route_device = dev;
	if (props == NULL)
		return;
	SPA_POD_OBJECT_FOREACH((struct spa_pod_object *)props, p)
		if (p->key == SPA_PROP_channelVolumes)
			n = spa_pod_copy_array(&p->value, SPA_TYPE_Float, vols,
					       SPA_AUDIO_MAX_CHANNELS);
	if (n == 0)
		return;
	a->route_nch = n;
	/* Whoever lowered it, the card's gain is the only level control here. */
	if (fabsf(vols[0] - 1.0f) > 0.001f)
		push_unity(a);
	push_hw(a);
}

static const struct pw_device_events dev_events = {
	PW_VERSION_DEVICE_EVENTS,
	.param = on_dev_param,
};

void route_unbind(struct app *a)
{
	a->dev_id = 0;
	a->route_index = -1;
	a->route_nch = 0;
	if (a->dev_proxy == NULL)
		return;
	spa_hook_remove(&a->dev_listener);
	pw_proxy_destroy(a->dev_proxy);
	a->dev_proxy = NULL;
}

void route_bind(struct app *a, uint32_t device_id)
{
	uint32_t ids[] = { SPA_PARAM_Route };

	if (device_id == a->dev_id)
		return;
	route_unbind(a);
	a->dev_id = device_id;
	a->dev_proxy = pw_registry_bind(a->registry, device_id,
					PW_TYPE_INTERFACE_Device, PW_VERSION_DEVICE, 0);
	pw_device_add_listener((struct pw_device *)a->dev_proxy, &a->dev_listener,
			       &dev_events, a);
	/* Subscribed, so a volume set anywhere else comes back to us. */
	pw_device_subscribe_params((struct pw_device *)a->dev_proxy, ids, 1);
	pw_device_enum_params((struct pw_device *)a->dev_proxy, 0, SPA_PARAM_Route,
			      0, UINT32_MAX, NULL);
}
