// SPDX-License-Identifier: GPL-2.0
/*
 * hidemnt - hide the module's bind/overlay mounts from chosen apps (hideksu).
 *
 * The module binds every tweak into init's mount namespace (nsenter -t 1 -m), so the mounts are
 * inherited by every app. Detectors flag them as "suspicious"/"inconsistent" mounts. KernelSU's
 * own umount is global (all non-root apps) and would also strip them from the Samsung apps that
 * consume them (Camera, Gallery, Settings, ...), breaking those tweaks. So instead we umount the
 * module mounts only in the mount namespace of apps the user names.
 *
 * Every module mount line in /proc/<pid>/mountinfo contains the token "s23tweaks" (overlay source
 * names s23tweaks_*, or a bind whose mount-root is /adb/s23tweaks/...). We enter the target's mount
 * namespace and umount2(MNT_DETACH) each such mount point, deepest path first. Only that app's view
 * changes; init and every other process keep the mounts.
 *
 * Modes:
 *   hidemnt once <pid>              umount module mounts in that pid's mount namespace, now.
 *   hidemnt daemon <hidelist-file>  watch for processes of the listed packages (kernel proc
 *                                   connector) and umount in each as it starts; also cleans any
 *                                   already-running ones at startup. One package per line, '#'
 *                                   comments and blanks ignored; a ':' process suffix still matches.
 *
 * A single setns()+umount2() pass is microseconds, so when the daemon fires on the fork/comm event
 * it finishes before the app's own code (e.g. a native root check in onCreate) reads the mounts.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sched.h>
#include <signal.h>
#include <errno.h>
#include <sys/mount.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <linux/netlink.h>
#include <linux/connector.h>
#include <linux/cn_proc.h>

#define TOKEN      "s23tweaks"
#define MAX_MP     512
#define MAX_PKGS   256
#define PATH_MAX_  512

/* ---- read this pid's process name (cmdline[0] basename of the package) ---- */
static int proc_name(int pid, char *out, size_t n)
{
	char p[64];
	snprintf(p, sizeof(p), "/proc/%d/cmdline", pid);
	int fd = open(p, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	ssize_t r = read(fd, out, n - 1);
	close(fd);
	if (r <= 0)
		return -1;
	out[r] = '\0';		/* cmdline is NUL-separated; first token is the process name */
	return 0;
}

/* true if proc name matches a package: exact, or "<pkg>:suffix" (private process) */
static int name_matches(const char *name, char pkgs[][128], int npkgs)
{
	for (int i = 0; i < npkgs; i++) {
		size_t l = strlen(pkgs[i]);
		if (strncmp(name, pkgs[i], l) == 0 && (name[l] == '\0' || name[l] == ':'))
			return 1;
	}
	return 0;
}

/* collect module mount points from /proc/<pid>/mountinfo, longest path first */
static int collect_mounts(int pid, char mps[][PATH_MAX_])
{
	char p[64];
	snprintf(p, sizeof(p), "/proc/%d/mountinfo", pid);
	FILE *f = fopen(p, "re");
	if (!f)
		return 0;
	int n = 0;
	char line[4096];
	while (n < MAX_MP && fgets(line, sizeof(line), f)) {
		if (!strstr(line, TOKEN))
			continue;
		/* field 5 (1-based) is the mount point: skip 4 space-separated fields */
		char *s = line, *mp = NULL;
		int field = 1;
		for (char *c = line; *c; c++) {
			if (*c == ' ') {
				field++;
				if (field == 5) { mp = c + 1; }
				else if (field == 6) { *c = '\0'; break; }
			}
			(void)s;
		}
		if (!mp || !*mp)
			continue;
		strncpy(mps[n], mp, PATH_MAX_ - 1);
		mps[n][PATH_MAX_ - 1] = '\0';
		n++;
	}
	fclose(f);
	/* sort by descending path length so children umount before parents */
	for (int i = 0; i < n; i++)
		for (int j = i + 1; j < n; j++)
			if (strlen(mps[j]) > strlen(mps[i])) {
				char t[PATH_MAX_];
				strcpy(t, mps[i]); strcpy(mps[i], mps[j]); strcpy(mps[j], t);
			}
	return n;
}

/* enter pid's mount namespace and detach every module mount. returns mounts removed, -1 on setns fail. */
static int hide_in(int pid)
{
	static char mps[MAX_MP][PATH_MAX_];
	int n = collect_mounts(pid, mps);
	if (n == 0)
		return 0;
	char p[64];
	snprintf(p, sizeof(p), "/proc/%d/ns/mnt", pid);
	int fd = open(p, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	if (setns(fd, CLONE_NEWNS) != 0) {
		close(fd);
		return -1;
	}
	close(fd);
	int done = 0;
	for (int i = 0; i < n; i++)
		if (umount2(mps[i], MNT_DETACH) == 0)
			done++;
	return done;
}

/* fork a child that does hide_in (so the daemon stays in init's namespace) */
static void hide_fork(int pid)
{
	pid_t c = fork();
	if (c == 0) {
		_exit(hide_in(pid) < 0 ? 1 : 0);
	} else if (c > 0) {
		int st;
		waitpid(c, &st, 0);
	}
}

static int load_pkgs(const char *file, char pkgs[][128])
{
	FILE *f = fopen(file, "re");
	if (!f)
		return 0;
	int n = 0;
	char line[256];
	while (n < MAX_PKGS && fgets(line, sizeof(line), f)) {
		char *s = line;
		while (*s == ' ' || *s == '\t') s++;
		if (*s == '#' || *s == '\n' || *s == '\0')
			continue;
		char *e = s + strlen(s);
		while (e > s && (e[-1] == '\n' || e[-1] == '\r' || e[-1] == ' ' || e[-1] == '\t'))
			*--e = '\0';
		if (*s) {
			strncpy(pkgs[n], s, 127);
			pkgs[n][127] = '\0';
			n++;
		}
	}
	fclose(f);
	return n;
}

/* clean any already-running listed apps */
static void sweep(char pkgs[][128], int npkgs)
{
	DIR *d = opendir("/proc");
	if (!d)
		return;
	struct dirent *e;
	char name[256];
	while ((e = readdir(d))) {
		int pid = atoi(e->d_name);
		if (pid <= 0)
			continue;
		if (proc_name(pid, name, sizeof(name)) == 0 && name_matches(name, pkgs, npkgs))
			hide_fork(pid);
	}
	closedir(d);
}

static int daemon_loop(const char *file)
{
	static char pkgs[MAX_PKGS][128];
	int npkgs = load_pkgs(file, pkgs);
	if (npkgs == 0) {
		fprintf(stderr, "hidemnt: no packages in %s\n", file);
		return 0;		/* nothing to do, exit cleanly */
	}
	sweep(pkgs, npkgs);	/* catch apps already running */

	int s = socket(PF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_CONNECTOR);
	if (s < 0) {
		perror("hidemnt: netlink socket");
		return 1;
	}
	struct sockaddr_nl addr = { .nl_family = AF_NETLINK, .nl_pid = (unsigned)getpid(),
				    .nl_groups = CN_IDX_PROC };
	if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
		perror("hidemnt: bind");
		close(s);
		return 1;
	}
	/* subscribe to process events */
	struct {
		struct nlmsghdr nlh;
		struct cn_msg cn;
		enum proc_cn_mcast_op op;
	} __attribute__((packed)) sub = {0};
	sub.nlh.nlmsg_len = sizeof(sub);
	sub.nlh.nlmsg_type = NLMSG_DONE;
	sub.nlh.nlmsg_pid = (unsigned)getpid();
	sub.cn.id.idx = CN_IDX_PROC;
	sub.cn.id.val = CN_VAL_PROC;
	sub.cn.len = sizeof(enum proc_cn_mcast_op);
	sub.op = PROC_CN_MCAST_LISTEN;
	if (send(s, &sub, sizeof(sub), 0) != (ssize_t)sizeof(sub)) {
		perror("hidemnt: subscribe");
		close(s);
		return 1;
	}

	signal(SIGCHLD, SIG_IGN);	/* reap nothing: children are waited in hide_fork */
	char buf[4096];
	char name[256];
	for (;;) {
		ssize_t len = recv(s, buf, sizeof(buf), 0);
		if (len <= 0) {
			if (errno == EINTR)
				continue;
			break;
		}
		for (struct nlmsghdr *nlh = (struct nlmsghdr *)buf; NLMSG_OK(nlh, (unsigned)len);
		     nlh = NLMSG_NEXT(nlh, len)) {
			if (nlh->nlmsg_type != NLMSG_DONE)
				continue;
			struct cn_msg *cn = (struct cn_msg *)NLMSG_DATA(nlh);
			struct proc_event *ev = (struct proc_event *)cn->data;
			int pid = 0;
			/* COMM: process name was just set (zygote specialization) - earliest reliable point.
			 * EXEC/FORK: also handle, cheap. */
			if (ev->what == PROC_EVENT_COMM)
				pid = ev->event_data.comm.process_pid;
			else if (ev->what == PROC_EVENT_EXEC)
				pid = ev->event_data.exec.process_pid;
			else
				continue;
			if (pid <= 0)
				continue;
			if (proc_name(pid, name, sizeof(name)) == 0 &&
			    name_matches(name, pkgs, npkgs))
				hide_fork(pid);
		}
	}
	close(s);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc == 3 && strcmp(argv[1], "once") == 0) {
		int r = hide_in(atoi(argv[2]));
		if (r < 0) {
			fprintf(stderr, "hidemnt: setns/umount failed for pid %s\n", argv[2]);
			return 1;
		}
		printf("hidemnt: %d mounts hidden from pid %s\n", r, argv[2]);
		return 0;
	}
	if (argc == 3 && strcmp(argv[1], "daemon") == 0)
		return daemon_loop(argv[2]);

	fprintf(stderr, "usage: %s once <pid> | daemon <hidelist-file>\n", argv[0]);
	return 2;
}
