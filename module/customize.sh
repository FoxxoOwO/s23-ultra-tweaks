# s23-ultra-tweaks: KernelSU install-time script. KernelSU's installer sources this (BusyBox ash)
# after it has unpacked the zip to $MODPATH. It changes nothing on the phone except the module
# folder, /data/adb/s23tweaks (created) and an old installer's boot script (removed, see below).

V=/data/adb/s23tweaks            # state: picks, logs, Play services backup (kept across updates)
OLD_BOOT=/data/adb/service.d/s23tweaks.sh

model=$(getprop ro.product.model)
build=$(getprop ro.build.PDA)
csc=$(getprop ro.csc.sales_code)
android=$(getprop ro.build.version.release)
kern=$(uname -r)

ui_print "- Phone: $model, firmware $build ($csc), Android $android"
case "$model" in
  SM-S918*) ;;
  *) abort "! This module is for the Galaxy S23 Ultra (SM-S918*), not $model" ;;
esac

# The kernel the AirDrop/Wi-Fi 7 payload was built for (tweaks.sh is the single source)
want=$(sed -n 's/^AIRDROP_KERNEL=\([^ #]*\).*/\1/p' "$MODPATH/tweaks.sh" | head -n 1)
if [ ! -f "$MODPATH/airdrop/kiwi_v2.ko" ]; then
  ui_print "! The AirDrop payload is missing from this zip: AirDrop and Wi-Fi 7 won't be offered"
elif [ -n "$want" ] && [ "$kern" = "$want" ]; then
  ui_print "- AirDrop / Wi-Fi 7: the kernel modules match this kernel"
else
  ui_print "! AirDrop / Wi-Fi 7 need firmware S918WVLU8GZIF (kernel ${want:-unknown});"
  ui_print "!   this phone runs $kern. Those two stay unavailable; the other tweaks still work."
fi

# Permissions: directories 755, files 644, the scripts and the payload's programs 755
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in tweaks.sh service.sh action.sh uninstall.sh airdrop/moseyrun airdrop/sqlite3 airdrop/pbflag; do
  [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
# moseyrun starts mosey_server in its own SELinux domain; that transition needs this label
[ -f "$MODPATH/airdrop/moseyrun" ] && chcon u:object_r:system_file:s0 "$MODPATH/airdrop/moseyrun"

mkdir -p "$V"

# An earlier computer (install.sh) install keeps its own boot script in service.d. The module's
# service.sh replaces it; the saved picks, autostart setting and backups in $V stay.
if [ -f "$OLD_BOOT" ]; then
  rm -f "$OLD_BOOT"
  ui_print "- Removed the computer installer's boot script; the module now does the boot apply"
fi
if [ -s "$V/choices" ]; then
  ui_print "- Saved picks kept: $(cat "$V/choices")"
  [ -f "$V/autostart" ] && ui_print "- Apply at every boot is on: they re-apply after the reboot"
fi

ui_print "- Next: reboot, then open KernelSU > Modules > S23 Ultra Tweaks"
ui_print "  and tap the page icon to choose tweaks."
