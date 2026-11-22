#define _GNU_SOURCE
#include <sched.h>
#include <stdio.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>

#define IOPRIO_WHO_PROCESS 1
#define IOPRIO_CLASS_BE 2
#define IOPRIO_CLASS_SHIFT 13
#define IOPRIO_BE_NORM 4
#define IOPRIO_BE_DEFAULT ((IOPRIO_CLASS_BE << IOPRIO_CLASS_SHIFT) | IOPRIO_BE_NORM)

int main(int argc, char **argv)
{
	const struct sched_param normal = { 0 };

	if (argc < 2) {
		fputs("usage: nixly-boost command [args...]\n", stderr);
		return 2;
	}
	/* Undo inherited idle priority. */
	sched_setscheduler(0, SCHED_OTHER, &normal);
	setpriority(PRIO_PROCESS, 0, 0);
	syscall(SYS_ioprio_set, IOPRIO_WHO_PROCESS, 0, IOPRIO_BE_DEFAULT);
	execvp(argv[1], argv + 1);
	perror(argv[1]);
	return 127;
}
