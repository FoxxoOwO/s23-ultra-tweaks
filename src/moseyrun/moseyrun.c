/*
 * Start /system_ext/bin/mosey_server the way its init .rc would:
 *   user system, group system inet, capabilities NET_ADMIN NET_RAW, domain u:r:mosey_server:s0
 * Run as root (from KernelSU su). Exits with the daemon's status.
 */
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <linux/capability.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#define AID_SYSTEM 1000
#define AID_INET 3003
static const char *CTX = "u:r:mosey_server:s0";
static const char *BIN = "/system_ext/bin/mosey_server";

static int die(const char *what) { fprintf(stderr, "moseyrun: %s: %s\n", what, strerror(errno)); return 1; }

int main(void)
{
	gid_t groups[] = { AID_SYSTEM, AID_INET };
	struct __user_cap_header_struct h = { _LINUX_CAPABILITY_VERSION_3, 0 };
	struct __user_cap_data_struct d[2];
	unsigned keep = (1u << CAP_NET_ADMIN) | (1u << CAP_NET_RAW);
	int fd;

	if (prctl(PR_SET_KEEPCAPS, 1) < 0) return die("keepcaps");
	if (setgroups(2, groups) < 0) return die("setgroups");
	if (setresgid(AID_SYSTEM, AID_SYSTEM, AID_SYSTEM) < 0) return die("setresgid");
	if (setresuid(AID_SYSTEM, AID_SYSTEM, AID_SYSTEM) < 0) return die("setresuid");
	memset(d, 0, sizeof(d));
	d[0].effective = d[0].permitted = d[0].inheritable = keep;
	if (syscall(SYS_capset, &h, d) < 0) return die("capset");
	if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, CAP_NET_ADMIN, 0, 0) < 0) return die("ambient net_admin");
	if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, CAP_NET_RAW, 0, 0) < 0) return die("ambient net_raw");
	fd = open("/proc/self/attr/exec", O_WRONLY | O_CLOEXEC);
	if (fd < 0 || write(fd, CTX, strlen(CTX)) < 0) return die("setexeccon");
	close(fd);
	execl(BIN, BIN, (char *)NULL);
	return die("exec");
}
