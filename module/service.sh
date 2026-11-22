# s23-ultra-tweaks: KernelSU late_start service. Re-applies the saved tweaks once the phone has
# booted, if "Apply at every boot" is on (tweaks.sh boot checks that, waits for the boot to finish
# and ignores a second call in the same boot).
# Runs tweaks.sh detached in init's mount namespace, so its mounts are visible to every app, with
# Android's own sh and tools (full paths: KernelSU runs this file in BusyBox standalone mode, where
# bare names would resolve to BusyBox applets). Returns right away.
MODDIR=${0%/*}
unset ASH_STANDALONE
/system/bin/nsenter -t 1 -m -- /system/bin/setsid /system/bin/sh "$MODDIR/tweaks.sh" boot </dev/null >/dev/null 2>&1 &
