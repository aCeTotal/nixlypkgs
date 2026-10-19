#define _GNU_SOURCE
#include <glob.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>

#define IOPRIO_WHO_PROCESS 1
#define IOPRIO_CLASS_BE 2
#define IOPRIO_CLASS_SHIFT 13
#define IOPRIO_BE_NORM 4
#define IOPRIO_BE_DEFAULT ((IOPRIO_CLASS_BE << IOPRIO_CLASS_SHIFT) | IOPRIO_BE_NORM)

static const char *const nvidia_offload[][2] = {
	{ "__NV_PRIME_RENDER_OFFLOAD", "1" },
	{ "__NV_PRIME_RENDER_OFFLOAD_PROVIDER", "NVIDIA-G0" },
	{ "__GLX_VENDOR_LIBRARY_NAME", "nvidia" },
	{ "__VK_LAYER_NV_optimus", "NVIDIA_only" },
};

static int hybrid_gpu(void)
{
	glob_t cards;
	int many = glob("/sys/class/drm/card[0-9]", 0, NULL, &cards) == 0 && cards.gl_pathc > 1;

	globfree(&cards);
	return many;
}

static void use_dgpu(void)
{
	unsetenv("VK_DRIVER_FILES");
	unsetenv("VK_ICD_FILENAMES");
	if (access("/proc/driver/nvidia/version", F_OK) != 0) {
		setenv("DRI_PRIME", "1", 1);
		return;
	}
	for (size_t i = 0; i < sizeof nvidia_offload / sizeof *nvidia_offload; i++)
		setenv(nvidia_offload[i][0], nvidia_offload[i][1], 1);
}

static int prepend_env(const char *name, const char *value)
{
	const char *old = getenv(name);
	char *joined;

	if (asprintf(&joined, "%s%s%s", value, old ? ":" : "", old ? old : "") < 0)
		return -1;
	return setenv(name, joined, 1);
}

int main(int argc, char **argv)
{
	const struct sched_param normal = { 0 };

	if (argc < 2) {
		fputs("usage: nixly-boost command [args...]\n", stderr);
		return 2;
	}
	/* Defaults, so gamemode can boost. */
	sched_setscheduler(0, SCHED_OTHER, &normal);
	setpriority(PRIO_PROCESS, 0, 0);
	syscall(SYS_ioprio_set, IOPRIO_WHO_PROCESS, 0, IOPRIO_BE_DEFAULT);
	if (hybrid_gpu())
		use_dgpu();
	if (prepend_env("LD_LIBRARY_PATH", GAMEMODE_LIB) != 0 ||
	    prepend_env("LD_PRELOAD", "libgamemodeauto.so.0") != 0) {
		perror("nixly-boost");
		return 1;
	}
	execvp(argv[1], argv + 1);
	perror(argv[1]);
	return 127;
}
