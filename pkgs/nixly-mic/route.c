/* Capture gain of the selected mic, on the card's input route — the same
 * knob wpctl turns, so WirePlumber stores it and the hardware follows. */
#include "app.h"

#include <spa/param/audio/raw.h>
#include <spa/param/props.h>
#include <spa/param/route.h>
#include <spa/pod/builder.h>
#include <spa/pod/iter.h>
#include <spa/pod/parser.h>

void push_volume(struct app *a)
{
	uint8_t buf[512];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof(buf));
	struct spa_pod_frame f[2];
	const struct spa_pod *pod;
	float vols[SPA_AUDIO_MAX_CHANNELS];
	uint32_t i, n = a->route_nch ? a->route_nch : 1;

	if (a->dev_proxy == NULL || a->route_index < 0)
		return;
	if (a->pushed_vol == a->ctl.vol)
		return;
	a->pushed_vol = a->ctl.vol;
	for (i = 0; i < n; i++)
		vols[i] = a->ctl.vol;

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
	if (dir != SPA_DIRECTION_INPUT || (int)dev != a->route_device)
		return;

	a->route_index = idx;
	if (props == NULL)
		return;
	SPA_POD_OBJECT_FOREACH((struct spa_pod_object *)props, p)
		if (p->key == SPA_PROP_channelVolumes)
			n = spa_pod_copy_array(&p->value, SPA_TYPE_Float, vols,
					       SPA_AUDIO_MAX_CHANNELS);
	if (n == 0)
		return;
	a->route_nch = n;
	if (!a->vol_known) {
		/* Nothing stored yet: start from whatever the session restored. */
		a->vol_known = true;
		a->pushed_vol = vols[0];
		control_reset(&a->ctl, vols[0], a->ctl.sens_db, a->ctl.learned);
	}
	info(a, "mic: %s route %d, volume %.4f", a->selected, a->route_index,
	     a->ctl.vol);
	push_volume(a);
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

void route_bind(struct app *a, uint32_t device_id, int profile_device)
{
	if (device_id == a->dev_id)
		return;
	route_unbind(a);
	a->dev_id = device_id;
	a->route_device = profile_device;
	a->dev_proxy = pw_registry_bind(a->registry, device_id,
					PW_TYPE_INTERFACE_Device, PW_VERSION_DEVICE, 0);
	pw_device_add_listener((struct pw_device *)a->dev_proxy, &a->dev_listener,
			       &dev_events, a);
	pw_device_enum_params((struct pw_device *)a->dev_proxy, 0, SPA_PARAM_Route,
			      0, UINT32_MAX, NULL);
}
