#!/usr/bin/env bash
# s23-ultra-tweaks installer. Runs on your computer (macOS or Linux) with the phone on USB:
#   curl -fsSL https://raw.githubusercontent.com/dtechterminal/s23-ultra-tweaks/main/install.sh | bash
# It asks which tweaks you want, then pushes them to the phone and applies them. Everything it
# does on the phone is undone by a reboot. Run it again after each reboot (it offers your last picks).
set -euo pipefail
# The whole script is inside main(), so a partial download can't run half a script and nothing
# below can read the rest of the script from stdin (curl | bash).
main() {
REPO=dtechterminal/s23-ultra-tweaks
VERSION=v1.0.0
PAYLOAD=airdrop-payload-S918WVLU8GZIF.tar.gz
PAYLOAD_SHA256=84787b2527d71cbb6cb23ba04a51e3539e1f466e6ab6fe1e489fc67b04879202
AIRDROP_KERNEL=5.15.197-android13-8-34343818-abS918WVLU8GZIF
PHONE_DIR=/data/adb/s23tweaks          # state (and the code, when the module isn't installed)
MODULE_DIR=/data/adb/modules/s23_ultra_tweaks

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }
ask()  { local a; read -r -p "$1" a </dev/tty || true; printf '%s' "$a"; }

command -v adb >/dev/null || die "adb not found. Install Android platform-tools: https://developer.android.com/tools/releases/platform-tools"
command -v curl >/dev/null || die "curl not found"
command -v tar >/dev/null || die "tar not found"
if command -v sha256sum >/dev/null; then sha() { sha256sum "$1" | cut -d' ' -f1; }; else sha() { shasum -a 256 "$1" | cut -d' ' -f1; }; fi
[ -r /dev/tty ] || die "needs an interactive terminal (it asks questions)"

# ---- pick the phone ----
devs=(); while read -r d; do devs+=("$d"); done < <(adb devices </dev/null | awk 'NR>1 && $2=="device" {print $1}')
[ ${#devs[@]} -gt 0 ] || die "no phone found. Plug it in over USB, enable USB debugging and accept the prompt on the phone."
if [ ${#devs[@]} -gt 1 ]; then
  say "Several devices are connected:"; for i in "${!devs[@]}"; do info "$((i+1))) ${devs[$i]}"; done
  n=$(ask "Which one? "); [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#devs[@]} ] || die "no device picked"
  SERIAL=${devs[$((n-1))]}
else SERIAL=${devs[0]}; fi
a() { adb -s "$SERIAL" "$@" </dev/null; }
sh_() { a shell "$@" | tr -d '\r'; }

model=$(sh_ getprop ro.product.model); build=$(sh_ getprop ro.build.PDA); csc=$(sh_ getprop ro.csc.sales_code)
kernel=$(sh_ uname -r); android=$(sh_ getprop ro.build.version.release)
say "Phone: $model, firmware $build ($csc), Android $android"
case "$model" in SM-S918*) ;; *) die "this is for the Galaxy S23 Ultra (SM-S918*), not $model" ;; esac

# ---- root ----
root_ok() { [ "$(sh_ 'su -c id -u' 2>/dev/null)" = 0 ]; }
if ! root_ok; then
  info "No root for adb yet. Restarting adb on the phone (a shell started before KernelSU never gets root)..."
  a usb >/dev/null 2>&1 || true; sleep 3; a wait-for-device; sleep 2
fi
root_ok || die "no root. On the phone: open DFRoot and tap LAUNCH ROOT, then in KernelSU > Superuser allow Shell. Then run this again. See https://github.com/$REPO#before-you-start"

# ---- what can this phone take? ----
gms=$(sh_ 'dumpsys package com.google.android.gms | grep -m1 versionCode' | grep -oE 'versionCode=[0-9]+' | cut -d= -f2)
can_airdrop=1; why_airdrop=""
[ "$kernel" = "$AIRDROP_KERNEL" ] || { can_airdrop=0; why_airdrop="needs firmware S918WVLU8GZIF (this phone runs $build)"; }
[ "${gms:-0}" -ge 261125000 ] || { can_airdrop=0; why_airdrop="needs Google Play services 26.11 or newer"; }
can_csc=1; why_csc=""; [ "$csc" = XAC ] || { can_csc=0; why_csc="needs XAC (Canadian) firmware"; }

ids=(airdrop battery features callrec india hotspot6g wifi7 display logvideo vulkan)
desc=("AirDrop: Quick Share > Share with Apple devices (S24 Wi-Fi driver + Google's Mosey)"
      "Battery health page: Settings > Battery > Battery information shows health and cycles"
      "Extra settings: Auto power on/off schedule, louder VoIP calls"
      "Call recording in the Samsung Phone app"
      "India (INS) carrier config: call recording, Smart IVR, message cards; sales code stays XAC"
      "6 GHz hotspot: Mobile Hotspot > Band offers 6 GHz (Wi-Fi 6E, 160 MHz)"
      "Wi-Fi 7 multi-link (MLO) with Wi-Fi 7 routers: S24 wpa_supplicant + driver MLO settings (adds 1)"
      "Vividness slider (Screen mode > Advanced settings) and lock screen wallpaper on Always On Display"
      "Log video: Log recording and LUT preview in Camera > Pro video"
      "Vulkan rendering: apps draw with Vulkan instead of OpenGL")
avail=($can_airdrop 1 1 $can_csc $can_csc 1 $can_airdrop 1 1 1)
why=("$why_airdrop" "" "" "$why_csc" "$why_csc" "" "$why_airdrop" "" "" "")

# pre-release builds lived in /data/local/tmp/s23tweaks: carry the picks and the Play services backup over
sh_ "su -c '[ -d /data/local/tmp/s23tweaks ] && [ ! -e $PHONE_DIR/choices ] && mkdir -p $PHONE_DIR && cp -r /data/local/tmp/s23tweaks/choices /data/local/tmp/s23tweaks/backup $PHONE_DIR/ 2>/dev/null; true'" >/dev/null
# With the KernelSU module installed (and active), drive its copy instead of installing a second one
TW=$PHONE_DIR/tweaks.sh; use_module=0
if [ "$(sh_ "su -c '[ -f $MODULE_DIR/tweaks.sh ] && [ ! -e $MODULE_DIR/remove ] && [ ! -e $MODULE_DIR/disable ] && echo yes'")" = yes ]; then
  TW=$MODULE_DIR/tweaks.sh; use_module=1
  info "The S23 Ultra Tweaks KernelSU module is installed; using it (no download needed)."
fi
last=$(sh_ "su -c 'cat $PHONE_DIR/choices 2>/dev/null'" || true)
picked=""
if [ -n "$last" ]; then
  r=$(ask "Apply your last picks again ($last)? [Y/n] ")
  [[ "$r" =~ ^[Nn] ]] || picked=$last
fi
if [ -z "$picked" ]; then
  say "Which tweaks do you want?"
  for i in "${!ids[@]}"; do
    if [ "${avail[$i]}" = 1 ]; then info "$((i+1))) ${desc[$i]}"; else info "$((i+1))) (unavailable: ${why[$i]}) ${desc[$i]}"; fi
  done
  info "4 and 5 both touch the carrier config; 5 already includes call recording."
  r=$(ask "Numbers separated by spaces, Enter for all available: ")
  [ -n "$r" ] || r=$(for i in "${!ids[@]}"; do [ "${avail[$i]}" = 1 ] && printf '%s ' $((i+1)); done; true)
  for n in $r; do
    [[ "$n" =~ ^[1-9][0-9]?$ ]] && [ "$n" -le ${#ids[@]} ] || die "not an option: $n"
    i=$((n-1)); [ "${avail[$i]}" = 1 ] || die "${ids[$i]} is unavailable on this phone: ${why[$i]}"
    case " $picked " in *" ${ids[$i]} "*) ;; *) picked="$picked ${ids[$i]}" ;; esac
  done
  case " $picked " in *" india "*) picked=$(echo "$picked" | sed 's/ callrec//') ;; esac
  case " $picked " in *" wifi7 "*) case " $picked " in *" airdrop "*) ;; *) info "wifi7 runs on the AirDrop Wi-Fi driver, so airdrop is added too."; picked="airdrop $picked" ;; esac ;; esac
  picked=$(echo $picked)
fi
[ -n "$picked" ] || die "nothing picked"
say "Applying: $picked"
case " $picked " in *" airdrop "*) info "Wi-Fi (and the hotspot) drop for ~30 s while the driver is swapped." ;; esac
info "The screen goes black for ~30 s while Android restarts its framework. Don't unplug the phone."
r=$(ask "Continue? [Y/n] "); [[ "$r" =~ ^[Nn] ]] && exit 0
r=$(ask "Re-apply these automatically at every boot, with no computer? [Y/n] "); [[ "$r" =~ ^[Nn] ]] && auto=off || auto=on

# ---- download ----
if [ $use_module = 0 ]; then
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
say "Downloading $VERSION..."
mkdir "$W/src"
if [ -n "${S23T_SRC:-}" ]; then cp -R "$S23T_SRC/device" "$W/src/"     # development: local checkout
else
  curl -fsSL "https://github.com/$REPO/archive/refs/tags/$VERSION.tar.gz" -o "$W/src.tar.gz"
  tar -xzf "$W/src.tar.gz" -C "$W/src" --strip-components=1
fi
case " $picked " in *" airdrop "*|*" wifi7 "*)
  if [ -n "${S23T_PAYLOAD:-}" ]; then cp "$S23T_PAYLOAD" "$W/payload.tar.gz"   # development: local payload
  else curl -fSL --progress-bar "https://github.com/$REPO/releases/download/$VERSION/$PAYLOAD" -o "$W/payload.tar.gz"; fi
  [ "$(sha "$W/payload.tar.gz")" = "$PAYLOAD_SHA256" ] || die "AirDrop payload checksum mismatch"
  mkdir -p "$W/src/device/airdrop"; tar -xzf "$W/payload.tar.gz" -C "$W/src/device/airdrop"
;; esac

# ---- push and run ----
say "Copying to the phone..."
a shell "su -c 'mkdir -p $PHONE_DIR'"
a push "$W/src/device/." /data/local/tmp/s23tweaks_new >/dev/null
a shell "su -c 'cp -r /data/local/tmp/s23tweaks_new/. $PHONE_DIR/ && rm -rf /data/local/tmp/s23tweaks_new && chmod -R 755 $PHONE_DIR && chcon u:object_r:system_file:s0 $PHONE_DIR/airdrop/moseyrun 2>/dev/null; true'"
fi
a shell "su -c 'sh $TW start \"$picked\"'" >/dev/null

say "Applying (2-3 minutes)..."
shown=0; end=$((SECONDS + 420))
while [ $SECONDS -lt $end ]; do
  sleep 3
  out=$(a shell "su -c 'cat $PHONE_DIR/tweaks.log'" 2>/dev/null | tr -d '\r') || continue
  n=$(printf '%s\n' "$out" | grep -c . || true)
  [ "$n" -gt "$shown" ] && { printf '%s\n' "$out" | tail -n +$((shown+1)) | sed 's/^[0-9.]* /  /'; shown=$n; }
  case "$out" in *DONE*) break ;; *FAILED*) die "see the line above. Rebooting the phone undoes everything." ;; esac
done
case "${out:-}" in *DONE*) ;; *) die "timed out; check $PHONE_DIR/tweaks.log on the phone" ;; esac

say "Done."
a shell "su -c 'sh $TW autostart $auto'" | tr -d '\r' | sed 's/^/  /'
case " $picked " in *" airdrop "*)
  info "AirDrop: on the Apple device set AirDrop to 'Everyone for 10 minutes'. On the S23 share something with"
  info "Quick Share and pick 'Share with Apple devices'." ;; esac
case " $picked " in *" battery "*) info "Battery: Settings > Battery > Battery information." ;; esac
case " $picked " in *" wifi7 "*) info "Wi-Fi 7: multi-link works with Wi-Fi 7 routers that have MLO on. Settings > Wi-Fi > (network) shows Wi-Fi 7." ;; esac
case " $picked " in *" hotspot6g "*) info "6 GHz hotspot: Settings > Connections > Mobile Hotspot > Band > 6 GHz (security must be WPA3)." ;; esac
if [ "$auto" = on ]; then
  info "At each boot DFRoot roots the phone by itself and the tweaks re-apply about a minute later (the screen"
  info "goes black for ~30 s once). A notification says when they're on. To stop: run this again and answer n."
else
  info "All of this lasts until the next reboot. Run this again after a reboot (it offers your last picks)."
fi
}
main "$@"
