# s23-ultra-tweaks: runs when the module is removed. Stops the automatic apply at boot. The rest of
# /data/adb/s23tweaks stays (it holds the Play services database backup). Live changes are undone by
# the reboot that completes the removal.
# If the computer installer has its own copy in /data/adb/s23tweaks, the autostart flag and the
# service.d script belong to that copy now: leave them.
[ -f /data/adb/s23tweaks/tweaks.sh ] || rm -f /data/adb/s23tweaks/autostart /data/adb/service.d/s23tweaks.sh
