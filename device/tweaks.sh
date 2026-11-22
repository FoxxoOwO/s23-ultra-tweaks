# s23-ultra-tweaks, phone side. Two ways it gets onto the phone:
#  - the KernelSU module: code in /data/adb/modules/s23_ultra_tweaks (this folder has module.prop)
#  - install.sh (adb): code in /data/adb/s23tweaks
# State (picks, logs, backups) always lives in /data/adb/s23tweaks, so module updates keep it.
# Everything runs as root. "start" runs "apply" detached in init's mount namespace, because the
# framework restart kills the caller (adb shell, KernelSU's WebUI):
#   su -c "sh <this folder>/tweaks.sh start 'airdrop battery'"
# Commands:
#   start "<tweaks>"  apply the listed tweaks in the background; follow tweaks.log in the state folder
#   apply "<tweaks>"  the same in the foreground (what start runs)
#   probe             one line of JSON: phone, which tweaks it can take and why not, what's active
#   status            print what is active
#   unflag            remove the two Play services flag overrides that the airdrop tweak adds
#   autostart on|off  re-apply the saved tweaks at every boot. DFRoot roots the phone by itself at
#                     boot, then KernelSU runs the module's service.sh (module) or a script in
#                     /data/adb/service.d (install.sh). Both call "boot".
#   boot              (internal) the automatic apply at boot
#   wifi7page         open Samsung's hidden "Wi-Fi 7 mode" settings page (Wi-Fi Labs)
#   loop | guard      (internal) keep mosey_server running / reboot cleanly on a Wi-Fi firmware crash
# Tweaks: airdrop battery features callrec india hotspot6g wifi7  (see README.md)
#
# Nothing here writes to a partition. Every change is a module load, a RAM (tmpfs) overlay, a bind
# mount or a runtime setting, so a reboot always returns the phone to stock. The one exception is
# the airdrop tweak's two Play services flag overrides, stored in Play services' own database
# (harmless without the rest; "unflag" removes them).
# Never touched: the sales code (mps_code.dat, sales_code.dat, omc.info, persist.sys.matched_code).
# Changing those can factory-reset the phone.

D=$(cd "$(dirname "$0")" && pwd)            # code: this script, files/, airdrop/ (the payload)
V=${S23T_STATE:-/data/adb/s23tweaks}         # state: choices, logs, backups, autostart flag
mkdir -p $V; L=$V/tweaks.log; R=$V/run
[ -f $D/module.prop ] && MODULE=1 || MODULE=0
APPLY_LOCK=/dev/s23tweaks_apply.lock         # /dev is tmpfs: locks never survive a reboot
TWEAK_IDS="airdrop battery features callrec india hotspot6g wifi7"
GMS_MIN=261125000                            # Play services 26.11, the first with Mosey support
AIRDROP_KERNEL=5.15.197-android13-8-34343818-abS918WVLU8GZIF
STOCK_KO=/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko
FF=/system/etc/floating_feature.xml
XAC=/optics/configs/carriers/XAC/conf; PRISM=/prism/etc/carriers/XAC
# md5 of the stock (encoded) XAC files on S918WVLU8GZIF: the CSC tweaks replace them, so they only
# run when the phone has exactly these
XAC_CSC_MD5=4921cc4fa8a85213856630d0bf7b661a
XAC_CCF_MD5=71e37a386615cc5db6b4e94fef72bea3
XAC_CUST_MD5=8d2f19740e35a0d0f30759bebd033043
NEARBY_FLAGS="45704091 45723015"   # Nearby Sharing: enableExternalProviders + the provider-registry gate

log() { m="$(cut -d' ' -f1 /proc/uptime) $*"; echo "$m" >> $L; echo "s23tweaks: $*" > /dev/kmsg; sync; }
fail() { log "FAILED: $*"; exit 1; }
wait_for() { n=$1; shift; while [ $n -gt 0 ]; do "$@" && return 0; n=$((n-1)); sleep 1; done; return 1; }
mounted() { mount | grep -q " $1 type $2"; }
bound() { mount | grep -q " $1 "; }
running() { ps -A -o ARGS | grep -q "[t]weaks.sh $1"; }
has() { case " $TWEAKS " in *" $1 "*) return 0 ;; esac; return 1; }
md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

# kallsyms address of a symbol in a module (kptr_restrict is lowered only for the read)
ksym() {
  o=$(cat /proc/sys/kernel/kptr_restrict); echo 1 > /proc/sys/kernel/kptr_restrict
  a=$(grep -E " $1\$" /proc/kallsyms | grep "\[$2\]" | head -1 | cut -d' ' -f1)
  echo $o > /proc/sys/kernel/kptr_restrict
  [ -n "$a" ] && [ "$a" != 0000000000000000 ] && echo $a
}

# ---------- airdrop: kernel side ----------
wlan_up() { [ -e /sys/class/net/wlan0 ] && [ $(( $(cat /sys/class/net/wlan0/flags) & 1 )) = 1 ]; }
hal_stopped() { [ "$(getprop init.svc.vendor.wifi_hal_legacy)" = stopped ]; }
hostapd_stopped() { [ "$(getprop init.svc.hostapd)" != running ]; }
wifi_off() { cmd wifi status | grep -q "Wifi is disabled"; }
sup_stopped() { [ "$(getprop init.svc.wpa_supplicant)" != running ]; }
wifi_down() {
  # Samsung turns Wi-Fi back on by itself right after a hotspot stops, so stop the hotspot first,
  # let that settle, and make sure Wi-Fi stays off before the driver is unloaded.
  if [ "$(getprop init.svc.hostapd)" = running ]; then
    cmd wifi stop-softap >/dev/null 2>&1; wait_for 15 hostapd_stopped || log "hotspot did not stop"; sleep 5
  fi
  cmd wifi set-scan-always-available disabled
  for i in 1 2 3; do cmd wifi set-wifi-enabled disabled; wait_for 10 wifi_off && sleep 4 && wifi_off && break; done
  wifi_off || { cmd wifi set-wifi-enabled enabled; cmd wifi set-scan-always-available enabled; fail "Wi-Fi keeps turning itself back on"; }
  wait_for 20 sup_stopped || log "wpa_supplicant still running after Wi-Fi off"
  [ -d /sys/module/wonder ] && { rmmod wonder || log "could not unload wonder"; }
  stop wpa_supplicant; stop vendor.wifi_hal_legacy; stop vendor.wifi_hal_ext
  wait_for 20 hal_stopped || log "Wi-Fi HAL did not stop"
  rmmod kiwi_v2 || { wifi_up; fail "could not unload the stock Wi-Fi driver"; }
}
wifi_up() {
  start vendor.wifi_hal_ext; start vendor.wifi_hal_legacy; start wpa_supplicant
  cmd wifi set-wifi-enabled enabled
  wait_for 45 wlan_up && log "Wi-Fi back on" || log "Wi-Fi did not come back by itself"
  cmd wifi set-scan-always-available enabled
}
back_to_stock() { mounted /vendor/firmware/kiwi overlay && umount /vendor/firmware/kiwi; insmod $STOCK_KO; wifi_up; }

airdrop_kernel() {
  A=$D/airdrop
  if [ -d /sys/module/wonder ] && [ -d /sys/module/bwfix ]; then log "airdrop: kernel side already loaded"; AK_LOADED=1; return 0; fi
  log "airdrop: swapping in the S24 Wi-Fi driver and firmware (Wi-Fi drops for ~30 s)"
  wifi_down
  # cnss2/MHI keep buffers sized for the boot-time firmware; mhifix frees them so the bigger S24
  # firmware gets correctly sized ones. It needs the address of cnss2's static plat_env pointer.
  pe=$(ksym plat_env cnss2) || { back_to_stock; fail "plat_env not found in kallsyms"; }
  b=$(cat /sys/module/cnss2/sections/.bss); d=$(( 0x$pe - b ))
  [ $d -ge 0 ] && [ $d -lt 1048576 ] || { back_to_stock; fail "plat_env 0x$pe is not in cnss2 .bss"; }
  insmod $A/mhifix.ko mode=1 plat_env=0x$pe; r=$(dmesg | grep mhifix | tail -4 | tr '\n' ' ')
  case "$r" in *"tables freed"*"fw_mem DDR freed"*) ;; *) back_to_stock; fail "mhifix: $r" ;; esac
  # S24 firmware in a RAM overlay over /vendor/firmware/kiwi (the S23 board file stays)
  T=/dev/s23tweaks_fw; mkdir -p $T; mounted $T tmpfs || mount -t tmpfs -o mode=755 s23tweaks_fw $T
  cp $A/fw/amss20.bin $A/fw/phy_ucode20.elf $A/fw/regdb.bin $T/ && chmod 644 $T/* && chcon u:object_r:vendor_firmware_file:s0 $T $T/*
  mount -t overlay s23tweaks_fwov -o ro,lowerdir=$T:/vendor/firmware/kiwi /vendor/firmware/kiwi || { back_to_stock; fail "firmware overlay"; }
  insmod $A/kiwi_v2.ko || { back_to_stock; fail "S24 Wi-Fi driver: $(dmesg | tail -2 | tr '\n' ' ')"; }
  wifi_up; sleep 5
  # bwfix: the S24 firmware asks for a PCIe Gen3 link when AirDrop starts; the S23 refuses (Gen2
  # max) and the firmware crashes on the refusal. bwfix sets Gen2 and acknowledges.
  cb=$(ksym cnss_mhi_bw_scale.cfi_jt cnss2)
  [ -d /sys/module/bwfix ] || insmod $A/bwfix.ko ${cb:+orig=0x$cb} || fail "bwfix: $(dmesg | tail -2 | tr '\n' ' ')"
  insmod $A/wonder.ko || fail "wonder: $(dmesg | tail -3 | tr '\n' ' ')"
  log "airdrop: kernel side loaded ($(dmesg | grep -o 'wonder: connected to wlan.*' | tail -1))"
}

# ---------- wifi7: Wi-Fi 7 multi-link (MLO) as a Wi-Fi client ----------
# The S24 driver (airdrop) has MLO built in, but the S23's wpa_supplicant has no 802.11be/MLO code
# and the S23's driver config doesn't turn MLO on. Use the S24's wpa_supplicant (same Samsung HAL
# extensions; it needs one AIDL library the S23 vendor image lacks, added to /vendor/lib64 with a
# read-only RAM overlay) and the S23's own driver config plus the S24's four MLO lines.
W7=/dev/s23tweaks_mlo; INI=/vendor/etc/wifi/kiwi_v2/WCNSS_qcom_cfg.ini; WPAS=/vendor/bin/hw/wpa_supplicant
MLO_INI="mlo_support_link_num=2 mlo_5gl_5gh_mlsr=1 oem_eht_mlo_crypto_bitmap=0 epcs_support_enable=1"
wifi7_bind() {   # sets W7_INI_NEW=1 when the driver has to be reloaded to read the config
  A=$D/airdrop/wifi7
  mkdir -p $W7; mounted $W7 tmpfs || mount -t tmpfs -o mode=755 s23tweaks_mlo $W7; mkdir -p $W7/lib
  if ! bound $WPAS; then
    cp $A/wpa_supplicant $W7/wpa_supplicant; chmod 755 $W7/wpa_supplicant
    chcon u:object_r:hal_wifi_supplicant_default_exec:s0 $W7/wpa_supplicant
    mount --bind $W7/wpa_supplicant $WPAS || fail "wifi7: bind wpa_supplicant"
  fi
  if ! mounted /vendor/lib64 overlay; then
    cp $A/android.hardware.wifi.supplicant-V2-ndk.so $W7/lib/; chmod 755 $W7/lib; chmod 644 $W7/lib/*.so
    chcon u:object_r:vendor_file:s0 $W7/lib $W7/lib/*.so
    mount -t overlay s23tweaks_mlolib -o ro,lowerdir=$W7/lib:/vendor/lib64 /vendor/lib64 || { umount $WPAS; fail "wifi7: library overlay"; }
  fi
  if ! bound $INI; then
    lab=$(ls -Z $INI | cut -d' ' -f1); cp $INI $W7/ini
    for kv in $MLO_INI; do grep -q "^${kv%%=*}=" $W7/ini || sed -i "/^END$/i $kv" $W7/ini; done
    grep -q "^mlo_support_link_num=" $W7/ini || fail "wifi7: no END marker in $INI"
    chmod 644 $W7/ini; chcon $lab $W7/ini; mount --bind $W7/ini $INI || fail "wifi7: bind driver config"
    W7_INI_NEW=1
  fi
  log "wifi7: S24 wpa_supplicant and MLO driver settings in place"
}
wifi7_unbind_sup() { bound $WPAS && umount $WPAS; mounted /vendor/lib64 overlay && umount /vendor/lib64; }
wifi7_reload() {   # the AirDrop driver was already loaded before the config was bound
  log "wifi7: reloading the Wi-Fi driver so it reads the MLO settings (Wi-Fi drops for ~15 s)"
  wifi_down
  insmod $D/airdrop/kiwi_v2.ko || { back_to_stock; fail "wifi7: kiwi_v2 reload: $(dmesg | tail -2 | tr '\n' ' ')"; }
  wifi_up
  insmod $D/airdrop/wonder.ko || fail "wonder: $(dmesg | tail -3 | tr '\n' ' ')"
}
wifi7_check() {
  # If Wi-Fi can't run with the S24 supplicant, go back to the S23's and carry on without MLO
  wait_for 60 wlan_up; wait_for 90 connected
  if [ "$(getprop init.svc.wpa_supplicant)" = running ] && cmd wifi status | grep -q "Wifi is enabled" &&
     [ "$(md5 /proc/$(pidof wpa_supplicant)/exe)" = "$(md5 $D/airdrop/wifi7/wpa_supplicant)" ]; then
    log "wifi7: Wi-Fi running with the S24 supplicant ($(cmd wifi status | grep -oE 'Wi-Fi standard: [^,]*' | head -1))"
  else
    log "wifi7: warning: Wi-Fi didn't come up with the S24 supplicant; switching back to the S23 one (no MLO)"
    cmd wifi set-wifi-enabled disabled; wait_for 15 wifi_off; wait_for 20 sup_stopped; wifi7_unbind_sup
    cmd wifi set-wifi-enabled enabled; wait_for 60 wlan_up
  fi
}
connected() { cmd wifi status | grep -q "Supplicant state: COMPLETED"; }

# ---------- airdrop: Mosey (Google's AirDrop stack from the S24) ----------
airdrop_overlays() {
  bound /system_ext/bin && { log "airdrop: Mosey already in /system_ext"; return 1; }
  M=$D/airdrop/mosey; T=/dev/s23tweaks_mosey
  mkdir -p $T; mounted $T tmpfs || mount -t tmpfs -o mode=755 s23tweaks_mosey $T
  mkdir -p $T/bin $T/lib64 $T/priv-app/MoseyApp $T/perm $T/sysconfig $T/vintf
  cp $M/mosey_server $T/bin/; cp $M/libmosey_daemon_ffi.so $T/lib64/; cp $M/MoseyApp.apk $T/priv-app/MoseyApp/
  cp $M/privapp-permissions-com.google.android.mosey.xml $T/perm/
  cp $M/preinstalled-packages-com.google.android.mosey.xml $M/hiddenapi-allowlist-mosey.xml $T/sysconfig/
  cp $M/manifest_mosey.xml $T/vintf/
  chmod -R 755 $T; find $T -type f -exec chmod 644 {} +; chmod 755 $T/bin/mosey_server
  chcon -R u:object_r:system_file:s0 $T
  chcon u:object_r:system_lib_file:s0 $T/lib64 $T/lib64/libmosey_daemon_ffi.so
  chcon u:object_r:mosey_server_exec:s0 $T/bin/mosey_server
  for p in "bin /system_ext/bin" "lib64 /system_ext/lib64" "priv-app /system_ext/priv-app" \
           "perm /system_ext/etc/permissions" "sysconfig /system_ext/etc/sysconfig" "vintf /system_ext/etc/vintf/manifest"; do
    set -- $p
    mount -t overlay s23tweaks_$1 -o ro,lowerdir=$T/$1:$2 $2 || fail "overlay on $2"
  done
  log "airdrop: Mosey added to /system_ext (RAM overlay)"
}

airdrop_post() {
  # On the S24 a default-permissions file pre-grants these; Quick Share only starts Mosey when
  # every dangerous permission Mosey asks for is granted.
  for p in BLUETOOTH_SCAN BLUETOOTH_ADVERTISE NEARBY_WIFI_DEVICES ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION \
           ACCESS_BACKGROUND_LOCATION ACCESS_MEDIA_LOCATION ACCESS_LOCAL_NETWORK READ_MEDIA_VISUAL_USER_SELECTED; do
    pm grant --user 0 com.google.android.mosey android.permission.$p 2>/dev/null
  done
  den=$(dumpsys package com.google.android.mosey | sed -n '/User 0:/,/User [1-9]/p' | grep -c granted=false)
  [ "$den" = 0 ] || log "airdrop: warning: $den Mosey permissions are still denied"
  # libvintf caches the VINTF manifests keyed on this file's mtime; touching it makes servicemanager
  # pick up manifest_mosey.xml (IMoseyService/default). Never restart servicemanager itself: Android
  # then reboots with "checkpoint_commit_failed".
  touch /apex/apex-info-list.xml
  running loop || setsid sh $D/tweaks.sh loop </dev/null >/dev/null 2>&1 &
  running guard || setsid sh $D/tweaks.sh guard </dev/null >/dev/null 2>&1 &
  n=20; until service check com.google.android.moseyservice.IMoseyService/default | grep -q found; do
    n=$((n-1)); [ $n = 0 ] && fail "IMoseyService did not register"; sleep 1; done
  log "airdrop: mosey_server running"
  gms_flags
}

# Play services only binds Mosey when two server-side Nearby flags are on. Add them as local
# overrides (account 0 = the device) and patch the current flag snapshot so they apply right away.
gms_flags() {
  G=/data/data/com.google.android.gms; DB=$G/databases/phenotype.db
  SNAP=$G/files/phenotype/shared/com.google.android.gms.nearby.pb
  SQ=$D/airdrop/sqlite3; W=$R/gms; rm -rf $W; mkdir -p $W $V/backup
  if [ ! -f $DB ]; then
    # Before the first unlock after a boot, app storage is still encrypted. The overrides set on an
    # earlier run are stored in Play services' database and stay in effect, so nothing is lost.
    if [ "${S23T_BOOT:-0}" = 1 ]; then log "airdrop: Play services storage is locked until first unlock; flags from the earlier run stay on"
    else log "airdrop: Play services database not found; flags not set"; fi
    return
  fi
  # edit a copy (opening the live WAL database as root would leave root-owned -wal/-shm files)
  am force-stop com.google.android.gms
  cp $DB $W/p.db; [ -f $DB-wal ] && cp $DB-wal $W/p.db-wal
  [ -f $V/backup/phenotype.db ] || cp $W/p.db* $V/backup/ 2>/dev/null
  id=$($SQ $W/p.db "select config_package_id from config_packages where name='com.google.android.gms.nearby'")
  [ -n "$id" ] || { log "airdrop: Play services has no Nearby config yet; open Quick Share once and run again"; return; }
  sql="PRAGMA integrity_check;"
  for f in $NEARBY_FLAGS; do
    sql="$sql INSERT OR IGNORE INTO flag_overrides (config_package_id, account_id, name, value, type, source) VALUES ($id, 0, '$f', 1, 2, 0);"
  done
  sql="$sql INSERT OR IGNORE INTO experiment_states_to_overrides (experiment_state_id, override_id)
    SELECT s.experiment_state_id, o.override_id FROM experiment_states s, flag_overrides o
    WHERE s.config_package_id=$id AND o.config_package_id=$id AND o.name IN ('${NEARBY_FLAGS% *}', '${NEARBY_FLAGS#* }');
    PRAGMA wal_checkpoint(TRUNCATE);"
  ok=$($SQ $W/p.db "$sql" | head -1)
  [ "$ok" = ok ] || { log "airdrop: Play services database check failed ($ok); flags not set"; return; }
  n=$($SQ $W/p.db "select count(*) from flag_overrides where config_package_id=$id and name in ('${NEARBY_FLAGS% *}', '${NEARBY_FLAGS#* }') and value=1")
  am force-stop com.google.android.gms
  cat $W/p.db > $DB && rm -f $DB-wal $DB-shm    # cat keeps the file's owner and SELinux label
  if [ -f $SNAP ]; then
    cp $SNAP $W/s0.pb
    $D/airdrop/pbflag $W/s0.pb $W/s1.pb ${NEARBY_FLAGS% *} 1 >/dev/null && \
    $D/airdrop/pbflag $W/s1.pb $W/s2.pb ${NEARBY_FLAGS#* } 1 >/dev/null && cat $W/s2.pb > $SNAP
  fi
  rm -rf $W
  log "airdrop: Play services Nearby flags on ($n of 2 overrides present)"
}

# ---------- Samsung feature flags (battery, features) ----------
ff_tags=""
ff_apply() {
  [ -z "$ff_tags" ] && return 1
  mkdir -p $R; bound $FF && umount $FF       # rebuild from the stock file each time
  grep -v '^</SecFloatingFeatureSet>' $FF > $R/ff.new
  for t in $ff_tags; do
    grep -q "<SEC_FLOATING_FEATURE_$t>" $R/ff.new || echo "    <SEC_FLOATING_FEATURE_$t>TRUE</SEC_FLOATING_FEATURE_$t>" >> $R/ff.new
  done
  echo '</SecFloatingFeatureSet>' >> $R/ff.new
  mv $R/ff.new $R/floating_feature.xml; chmod 644 $R/floating_feature.xml
  chcon u:object_r:system_file:s0 $R/floating_feature.xml
  mount --bind $R/floating_feature.xml $FF || fail "floating_feature bind mount"
  log "feature flags on: $ff_tags"
}

# Settings > Battery > Battery information shows health only when an authenticated battery IC
# (sec_auth) exists. Present one whose values mirror /efs/FactoryApp, so syncs are no-ops.
battery_auth() {
  PS=/sys/class/power_supply; T=/dev/s23tweaks_ps; E=/efs/FactoryApp
  mounted $PS tmpfs && { log "battery: auth IC already present"; return 0; }
  for f in HwParamBattQR batt_beginning_date asoc batt_discharge_level batt_full_status_usage; do
    [ -f $E/$f ] || { log "battery: $E/$f missing; skipping the battery health page"; return 1; }
  done
  [ -e $PS/sec_auth ] && { log "battery: this phone already has a battery auth IC"; return 0; }
  mkdir -p $T
  mount -t tmpfs -o mode=755,context=u:object_r:sysfs:s0 s23tweaks_ps $T
  for e in $(ls $PS); do ln -s "$(readlink $PS/$e)" $T/$e; done
  mkdir $T/sec_auth
  mount -t tmpfs -o mode=755,uid=1000,gid=1000,context=u:object_r:sysfs_battery:s0 s23tweaks_auth $T/sec_auth
  w() { printf '%s' "$1" > $T/sec_auth/$2; }
  w "$(cat $E/HwParamBattQR)" qr_code; w 1 presence; w 1 batt_auth
  w "$(cat $E/batt_beginning_date)" first_use_date; w 0 fai_expired; w "$(cat $E/asoc)" asoc
  w "$(cat $E/batt_discharge_level)" batt_discharge_level; w "$(cat $E/batt_full_status_usage)" batt_full_status_usage
  chown 1000:1000 $T/sec_auth/*; chmod 664 $T/sec_auth/*
  mount --rbind $T $PS || fail "power_supply overlay"
  log "battery: auth IC presented"
}

# ---------- CSC (callrec, india): XAC firmware only ----------
csc_check() {
  [ "$(getprop ro.csc.sales_code)" = XAC ] || { log "$1: needs XAC (Canadian) firmware; skipped"; return 1; }
  for p in "$XAC/system/cscfeature.xml $XAC_CSC_MD5" "$XAC/system/customer_carrier_feature.json $XAC_CCF_MD5" "$XAC/customer.xml $XAC_CUST_MD5"; do
    set -- $p; bound $1 && umount $1
    [ "$(md5 $1)" = $2 ] || { log "csc: $1 differs from S918WVLU8GZIF; skipped"; return 1; }
  done
  bound $PRISM && umount $PRISM
  return 0
}
csc_bind() { cp "$1" $R/$3; chmod 644 $R/$3; chcon u:object_r:vendor_configs_file:s0 $R/$3; mount --bind $R/$3 "$2" || fail "bind $2"; }
callrec_apply() {
  csc_check callrec || return 1; mkdir -p $R
  csc_bind $D/files/xac-callrec/cscfeature.xml $XAC/system/cscfeature.xml csc_xac.xml
  log "callrec: call recording on (Phone app > Settings > Record calls)"
}
india_apply() {
  csc_check india || return 1; mkdir -p $R; I=$D/files/ins
  csc_bind $I/cscfeature.xml $XAC/system/cscfeature.xml csc_ins.xml
  csc_bind $I/customer_carrier_feature.json $XAC/system/customer_carrier_feature.json ccf_ins.json
  csc_bind $I/customer.xml $XAC/customer.xml customer_ins.xml
  # prism: full copy of the XAC folder (sales_code.dat etc. unchanged) plus INS keystrings/images
  rm -rf $R/prism; mkdir $R/prism; cp -p $PRISM/* $R/prism/; cp $I/prism/* $R/prism/
  chmod 755 $R/prism; chmod 644 $R/prism/*; chcon -R u:object_r:vendor_configs_file:s0 $R/prism
  mount --bind $R/prism $PRISM || fail "bind $PRISM"
  log "india: INS carrier config on (sales code stays XAC)"
}

# Samsung's Mobile Hotspot only offers 6 GHz when the firmware's CSC country is on its list
# (SemWifiApServiceImpl.isRegionFor6GCountry). Most S23 CSCs aren't, though the hardware and the
# stock hostapd run a 6 GHz hotspot fine. IN passes on every Qualcomm phone. Runtime property only;
# the sales code is untouched. The radio still follows the real regulatory country.
hotspot6g_apply() {
  RP=/data/adb/ksu/bin/resetprop; [ -x $RP ] || { log "hotspot6g: KernelSU resetprop not found; skipped"; return 1; }
  c=$(getprop ro.csc.countryiso_code); [ "$c" = IN ] && { log "hotspot6g: already on"; return 0; }
  $RP ro.csc.countryiso_code IN && log "hotspot6g: CSC country $c -> IN; Mobile hotspot > Band now offers 6 GHz (needs WPA3)"
}

restart_framework() {
  old=$(pidof system_server); log "restarting the Android framework (screen goes black for ~30 s)"
  setprop ctl.restart zygote
  n=150; until p=$(pidof system_server) && [ -n "$p" ] && [ "$p" != "$old" ] && pm path android >/dev/null 2>&1; do
    n=$((n-1)); [ $n = 0 ] && fail "framework did not come back"; sleep 1; done
  sleep 10; log "framework back"
}

case "$1" in
apply)
  [ "$(id -u)" = 0 ] || { echo "needs root" >&2; exit 1; }
  mkdir $APPLY_LOCK 2>/dev/null || { echo "another apply is already running (see $L)" >&2; exit 3; }
  trap 'rmdir $APPLY_LOCK 2>/dev/null' EXIT
  TWEAKS=" $2 "; : > $L
  log "applying:$TWEAKS"
  for x in $2; do case " $TWEAK_IDS " in *" $x "*) ;; *) fail "unknown tweak: $x" ;; esac; done
  echo "$2" > $V/choices
  has wifi7 && ! has airdrop && fail "wifi7 needs airdrop (the S24 Wi-Fi driver)"
  if has airdrop; then
    [ "$(uname -r)" = "$AIRDROP_KERNEL" ] || fail "airdrop needs kernel $AIRDROP_KERNEL (firmware S918WVLU8GZIF)"
    has wifi7 && wifi7_bind   # before the driver loads, so it reads the MLO settings
    airdrop_kernel
    if has wifi7; then [ "${AK_LOADED:-0}" = 1 ] && [ "${W7_INI_NEW:-0}" = 1 ] && wifi7_reload; wifi7_check; fi
  fi
  restart=0
  has airdrop && airdrop_overlays && restart=1
  has battery && { ff_tags="$ff_tags BATTERY_SUPPORT_BSOH_SETTINGS SETTINGS_ENABLE_EU_BATTERY_REGULATORY"; battery_auth; }
  has features && ff_tags="$ff_tags SETTINGS_SUPPORT_AUTO_POWER_ON_OFF AUDIO_SUPPORT_VOIP_SOUND_LOUDER"
  ff_apply && restart=1
  if has india; then india_apply && { setprop ctl.restart ril-daemon; log "india: mobile network restarting"; restart=1; }
  elif has callrec; then callrec_apply && restart=1; fi
  [ $restart = 1 ] && restart_framework
  has hotspot6g && hotspot6g_apply
  has airdrop && airdrop_post
  log "DONE"
  ;;
start)
  [ "$(id -u)" = 0 ] || { echo "needs root" >&2; exit 1; }
  [ -d $APPLY_LOCK ] && { echo "another apply is already running (see $L)" >&2; exit 3; }
  [ -n "$2" ] || { echo "usage: tweaks.sh start \"<tweaks>\"" >&2; exit 2; }
  : > $L
  nsenter -t 1 -m -- setsid sh $D/tweaks.sh apply "$2" </dev/null >/dev/null 2>&1 &
  echo "started; progress in $L"
  ;;
probe)
  # One line of JSON for the WebUI and install.sh. Values never contain quotes or backslashes.
  model=$(getprop ro.product.model); build=$(getprop ro.build.PDA); csc=$(getprop ro.csc.sales_code)
  kern=$(uname -r); android=$(getprop ro.build.version.release)
  gms=$(dumpsys package com.google.android.gms 2>/dev/null | grep -m1 -oE 'versionCode=[0-9]+' | cut -d= -f2)
  ver=$( [ $MODULE = 1 ] && grep -m1 '^version=' $D/module.prop | cut -d= -f2 || echo script)
  why_s23=""; case "$model" in SM-S918*) ;; *) why_s23="this is for the Galaxy S23 Ultra (SM-S918*), not $model" ;; esac
  why_ad=$why_s23
  [ -z "$why_ad" ] && [ "$kern" != "$AIRDROP_KERNEL" ] && why_ad="needs firmware S918WVLU8GZIF (this phone runs $build)"
  [ -z "$why_ad" ] && [ "${gms:-0}" -lt $GMS_MIN ] && why_ad="needs Google Play services 26.11 or newer"
  [ -z "$why_ad" ] && [ ! -f $D/airdrop/kiwi_v2.ko ] && why_ad="the AirDrop payload isn't installed"
  why_csc=$why_s23; [ -z "$why_csc" ] && [ "$csc" != XAC ] && why_csc="needs XAC (Canadian) firmware (this phone is $csc)"
  why_bat=$why_s23; [ -z "$why_bat" ] && [ ! -f /efs/FactoryApp/asoc ] && why_bat="this phone has no battery data in /efs/FactoryApp"
  why_6g=$why_s23; [ -z "$why_6g" ] && [ ! -x /data/adb/ksu/bin/resetprop ] && why_6g="needs KernelSU's resetprop"
  act() { "$@" && echo true || echo false; }
  a_air=$(act eval '[ -d /sys/module/wonder ] && bound /system_ext/bin')
  a_bat=$(act mounted /sys/class/power_supply tmpfs)
  a_fea=$(act eval 'bound $FF && grep -q SETTINGS_SUPPORT_AUTO_POWER_ON_OFF $FF')
  a_ind=$(act bound $PRISM)
  a_rec=$(act eval 'bound $XAC/system/cscfeature.xml && ! bound $PRISM')
  a_6g=$(act eval '[ "$(getprop ro.csc.countryiso_code)" = IN ]')
  a_w7=$(act eval 'bound $WPAS && bound $INI')
  j() { printf '{"id":"%s","available":%s,"why":"%s","active":%s}' "$1" "$( [ -z "$2" ] && echo true || echo false)" "$2" "$3"; }
  printf '{"version":"%s","module":%s,"phone":{"model":"%s","firmware":"%s","csc":"%s","android":"%s","kernel":"%s","gms":%s},' \
    "$ver" "$( [ $MODULE = 1 ] && echo true || echo false)" "$model" "$build" "$csc" "$android" "$kern" "${gms:-0}"
  printf '"picked":"%s","autostart":%s,"applying":%s,"tweaks":[' "$(cat $V/choices 2>/dev/null)" \
    "$( [ -f $V/autostart ] && echo true || echo false)" "$( [ -d $APPLY_LOCK ] && echo true || echo false)"
  printf '%s,%s,%s,%s,%s,%s,%s]}\n' "$(j airdrop "$why_ad" $a_air)" "$(j battery "$why_bat" $a_bat)" \
    "$(j features "$why_s23" $a_fea)" "$(j callrec "$why_csc" $a_rec)" "$(j india "$why_csc" $a_ind)" \
    "$(j hotspot6g "$why_6g" $a_6g)" "$(j wifi7 "$why_ad" $a_w7)"
  ;;
loop)
  # init can't start mosey_server (its .rc isn't loaded on this boot). moseyrun starts it the way
  # mosey.rc does: uid system, groups system+inet, ambient NET_ADMIN/NET_RAW, u:r:mosey_server:s0
  # (as root it fails to open /dev/tun). It's a lazy service that exits when idle: restart it.
  while true; do $D/airdrop/moseyrun; sleep 1; done
  ;;
guard)
  # If the Wi-Fi firmware ever crashes, the S24 driver's recovery leaks the AirDrop interface and
  # ~50 s later the phone hard-resets. Stop the daemon, keep the log, and reboot cleanly instead.
  hangs() { dmesg | grep -c "Received firmware hang event"; }
  base=$(hangs)
  while sleep 1; do
    [ "$(hangs)" -gt "$base" ] || continue
    log "Wi-Fi firmware crashed: saving the kernel log and rebooting"
    echo "the Wi-Fi firmware crashed before the last reboot (log saved in $V)" > $V/boot.skip
    ps -A -o PID,ARGS | grep "[t]weaks.sh loop" | while read pid rest; do kill $pid; done
    pkill mosey_server; sleep 3; dmesg > $V/fwcrash_$(cut -d. -f1 /proc/uptime).txt; sync
    reboot
  done
  ;;
status)
  echo "saved choices: $(cat $V/choices 2>/dev/null); $(sh $D/tweaks.sh autostart)"
  echo "airdrop:  modules [$(grep -oE '^(wonder|bwfix) ' /proc/modules | tr -d '\n')]," \
       "Mosey $(bound /system_ext/bin && echo on || echo off), daemon $(running loop && echo running || echo stopped)," \
       "$(service check com.google.android.moseyservice.IMoseyService/default | sed 's/.*: //')"
  echo "features: $(bound $FF && grep -oE 'SEC_FLOATING_FEATURE_(BATTERY_SUPPORT_BSOH_SETTINGS|SETTINGS_SUPPORT_AUTO_POWER_ON_OFF|AUDIO_SUPPORT_VOIP_SOUND_LOUDER)>' $FF | sed 's/SEC_FLOATING_FEATURE_//; s/>//' | tr '\n' ' ' || echo off)"
  echo "battery:  $(mounted /sys/class/power_supply tmpfs && echo on || echo off)"
  echo "wifi7:    wpa_supplicant $(bound $WPAS && echo S24 || echo stock), driver MLO settings $(bound $INI && echo on || echo off)"
  echo "6ghz ap:  CSC country $(getprop ro.csc.countryiso_code)"
  echo "csc:      $(bound $XAC/system/cscfeature.xml && grep -oE '<SalesCode>[A-Z]+' $XAC/system/cscfeature.xml | cut -c12- || echo stock)"
  ;;
unflag)
  G=/data/data/com.google.android.gms; DB=$G/databases/phenotype.db; SQ=$D/airdrop/sqlite3; W=$R/gms
  rm -rf $W; mkdir -p $W; am force-stop com.google.android.gms
  cp $DB $W/p.db; [ -f $DB-wal ] && cp $DB-wal $W/p.db-wal
  $SQ $W/p.db "DELETE FROM experiment_states_to_overrides WHERE override_id IN (SELECT override_id FROM flag_overrides WHERE name IN ('${NEARBY_FLAGS% *}', '${NEARBY_FLAGS#* }') AND account_id=0);
    DELETE FROM flag_overrides WHERE name IN ('${NEARBY_FLAGS% *}', '${NEARBY_FLAGS#* }') AND account_id=0; PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null
  am force-stop com.google.android.gms; cat $W/p.db > $DB && rm -f $DB-wal $DB-shm; rm -rf $W
  echo "Play services flag overrides removed"
  ;;
autostart)
  S=/data/adb/service.d/s23tweaks.sh
  case "$2" in
  on)
    # the module's own service.sh does the boot call; install.sh needs a service.d script
    if [ $MODULE = 1 ]; then rm -f $S; touch $V/autostart; echo "autostart on: the saved tweaks ($(cat $V/choices 2>/dev/null)) re-apply at every boot"; exit 0; fi
    mkdir -p /data/adb/service.d
    cat > $S <<EOF
#!/system/bin/sh
# s23-ultra-tweaks: re-apply the saved tweaks at boot. KernelSU runs this once DFRoot has rooted the
# phone. Remove with: sh $D/tweaks.sh autostart off
[ -f $V/autostart ] && nsenter -t 1 -m -- setsid sh $D/tweaks.sh boot </dev/null >/dev/null 2>&1 &
EOF
    chmod 700 $S; touch $V/autostart; echo "autostart on: the saved tweaks ($(cat $V/choices 2>/dev/null)) re-apply at every boot" ;;
  off) rm -f $S $V/autostart $V/boot.pending $V/boot.skip; echo "autostart off" ;;
  *) [ -f $V/autostart ] && { [ $MODULE = 1 ] || [ -f $S ]; } && echo "autostart on" || echo "autostart off" ;;
  esac
  ;;
boot)
  B=$V/boot.log
  blog() { echo "$(date '+%F %T') $*" >> $B; }
  note() { cmd notification post -S bigtext -t "S23 tweaks" s23tweaks "$1" >/dev/null 2>&1; }
  [ -f $V/autostart ] || exit 0
  t=$(cat $V/choices 2>/dev/null); [ -n "$t" ] || exit 0
  # KernelSU can run boot scripts more than once per boot (seen with DFRoot's late load): only the
  # first call goes on
  mkdir /dev/s23tweaks_boot.lock 2>/dev/null || exit 0
  n=600; until [ "$(getprop sys.boot_completed)" = 1 ]; do n=$((n-1)); [ $n = 0 ] && break; sleep 1; done
  sleep 30   # let Wi-Fi, Play services and the launcher settle before swapping the driver
  # Fail-safe against a boot loop: if the last boot's apply never finished (the phone rebooted in the
  # middle) or the Wi-Fi firmware crashed, skip this boot once and say so.
  why=""
  [ -f $V/boot.pending ] && why="the last automatic apply didn't finish"
  [ -f $V/boot.skip ] && why=$(cat $V/boot.skip)
  if [ -n "$why" ]; then
    rm -f $V/boot.pending $V/boot.skip; blog "skipped: $why"
    note "Tweaks not applied at this boot: $why. Apply them from KernelSU > Modules > S23 Ultra Tweaks (or the installer), or reboot to try again."
    exit 0
  fi
  touch $V/boot.pending; sync; blog "applying: $t"
  S23T_BOOT=1 sh $D/tweaks.sh apply "$t"
  rm -f $V/boot.pending
  if grep -q DONE $L; then blog "done"; note "Applied: $t"
  else f=$(grep FAILED $L | tail -1 | cut -d' ' -f2-); blog "failed: $f"; note "Applying the tweaks failed: $f. Details: $L"; fi
  ;;
wifi7page)
  # Samsung ships this page on the S23, but its entry in Wi-Fi Labs is hard-coded as unsupported
  # (WifiLabs7ModeSettingsController.getAvailabilityStatus() returns 3). The page itself has no
  # check. SubSettings isn't exported, so it can only be opened as root/system.
  am start -n com.android.settings/.SubSettings \
    --es :settings:show_fragment com.samsung.android.settings.wifi.develop.WifiLabs7ModeSettingsFragment
  ;;
*) echo "usage: tweaks.sh start|apply \"<tweaks>\" | probe | status | unflag | autostart on|off | wifi7page"; exit 2 ;;
esac
