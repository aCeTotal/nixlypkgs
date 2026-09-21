/* The two digital gain stages of the nixly-mic filter chain. */
#include "app.h"

#include <spa/param/props.h>
#include <spa/pod/builder.h>

void push_props(struct app *a)
{
	uint8_t buf[512];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof(buf));
	struct spa_pod_frame f[2];
	const struct spa_pod *pod;
	float g1 = control_gain1_mult(&a->ctl);
	float g2 = control_gain2_mult(&a->ctl);

	if (a->fc_proxy == NULL)
		return;
	if (g1 == a->pushed_g1 && g2 == a->pushed_g2)
		return;

	spa_pod_builder_push_object(&b, &f[0], SPA_TYPE_OBJECT_Props, SPA_PARAM_Props);
	spa_pod_builder_prop(&b, SPA_PROP_params, 0);
	spa_pod_builder_push_struct(&b, &f[1]);
	spa_pod_builder_string(&b, "g1:Mult");
	spa_pod_builder_float(&b, g1);
	spa_pod_builder_string(&b, "g2:Mult");
	spa_pod_builder_float(&b, g2);
	spa_pod_builder_pop(&b, &f[1]);
	pod = spa_pod_builder_pop(&b, &f[0]);

	pw_node_set_param((struct pw_node *)a->fc_proxy, SPA_PARAM_Props, 0, pod);
	a->pushed_g1 = g1;
	a->pushed_g2 = g2;
	info(a, "gain: card %.1f dB, chain %.1f dB", a->ctl.hw_db, a->ctl.sens_db);
}
