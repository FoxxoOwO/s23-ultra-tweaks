# s23-ultra-tweaks

Turns on Galaxy S24-and-newer features on a rooted Galaxy S23 Ultra running One UI 9 / Android 17, with no flashing.

The tweaks come in six categories. The installer and the module page let you pick a whole category
or single tweaks; the numbers below are the installer's. Each one works on any S23 Ultra on One UI 9
unless it says otherwise.

### 🌐 Connectivity

- 📲 **1 · AirDrop** with iPhones, iPads and Macs: Quick Share → *Share with Apple devices* · `airdrop`
  - Works on: One UI 9 build **GZIF** on SM-S918W, S918B, S918U1, S918U or S918N (tested on the S918W and S918B)
- 📶 **2 · Wi-Fi 7 multi-link (MLO)** with Wi-Fi 7 routers. Includes AirDrop · `wifi7`
  - Works on: same as AirDrop
- 📡 **3 · 6 GHz Mobile Hotspot** (Wi-Fi 6E, 160 MHz): Mobile Hotspot → Band → 6 GHz · `hotspot6g`

### 📷 Camera

- 🎞️ **4 · Log video**: Camera → Pro video gets the LOG button (10-bit HEVC). No LUT preview: on the S24 the camera HAL draws it, and the S23's can't · `logvideo`
- 🎬 **5 · Director's view** (front and back camera at once, hidden by One UI 9) and Super steady's **horizontal lock** · `camextras`
- 🌗 **6 · Camera HDR processing**: puts back the multi-frame and low-light HDR steps One UI 9 removed from the S23 ([details](docs/findings.md)). **Untested** · `camerahdr`
  - 21 MB download
- 🕰️ **7 · 2023 ArcSoft HDR**: One UI 6's hybrid and bracketed HDR engines instead of today's. Bracketed HDR tested, hybrid HDR (ordinary daylight) **untested**. Not included when you pick the whole Camera category · `hdr2023`
  - Works on: any S23 Ultra on One UI 9; tested on S918WVLU8GZIF (28 MB download)
- 🎯 **8 · 4K auto framing** in video, as on the S24. Works on the SM-S918W (front camera, UHD with auto framing on); **reported to make the camera fail** on an S918B, so it's not included when you pick the whole Camera category · `autoframe`
- 🌈 **9 · 10-bit HDR video from the front cameras in any app** (Camera2 HLG10), as the rear cameras already allow. Samsung Camera keeps its own HDR10+. Patches a copy of the phone's own camera driver and keeps it only if a front camera then really offers 10-bit; the first apply takes about 15 s longer · `tenbit`
  - Works on: any S23 Ultra whose camera driver has the expected code (found in One UI 6 and 9 builds; tested on S918WVLU8GZIF)

### 🎨 Display and graphics

- 🖌️ **10 · Vividness slider** (Settings → Display → Screen mode → Advanced settings) and the **lock screen wallpaper on Always On Display** · `display`
- 🌤️ **11 · Adaptive color tone**: Settings → Display, the screen's colour follows the room light · `colortone`
  - Works on: firmware S918WVLU8GZIF or S918BXXUAGZIF (1 MB download)
- ⚡ **12 · Vulkan rendering**: apps draw with Vulkan instead of OpenGL, as on the S24 · `vulkan`

### ✨ Galaxy AI and Samsung apps

- 🧠 **13 · Now Brief, Creative Studio and Call Assist** from the S24 · `galaxyai`
  - Works on: firmware S918WVLU8GZIF (219 MB download)
- 🔇 **14 · Audio Eraser**: Gallery → video → Edit → remove wind, noise, music or voices · `audioeraser`
  - Works on: firmware S918WVLU8GZIF (34 MB download)
- 🔎 **15 · Settings search** bar from the S24. Natural-language answers stay off (they need Samsung's Semantic Search Core 4.x) · `settingssearch`
  - Works on: firmware S918WVLU8GZIF (10 MB download)
- 📞 **16 · Call screening** in the Phone app: screening, greeting and voice messages work; the AI summary and replies don't. **Stays after a reboot** · `callscreen`
  - Works on: firmware S918WVLU8GZIF (3.1 GB download, about 7 GB free while it installs)
- 🗣️ **17 · Bixby barge-in**: talk over Bixby while it answers. **Untested** · `bargein`

### 🔋 Battery and settings

- 🩺 **18 · Battery health**: Settings → Battery → Battery information shows health and cycle count · `battery`
- ⏰ **19 · Auto power on/off** schedule and **louder VoIP calls** · `features`

### 📱 Carrier

- ⏺️ **20 · Call recording** in the Samsung Phone app · `callrec`
  - Works on: XAC (Canadian) firmware S918WVLU8GZIF, or EUX (European) firmware S918BXXUAGZIF
- 🇮🇳 **21 · India carrier config** for Airtel / Jio SIMs: the **Use 5G standalone networks** switch (Settings → Connections → Mobile networks), call recording, Smart IVR, message cards and more. The sales code stays XAC. With an Indian SIM, picking the Carrier category takes this instead of call recording · `india`
  - Works on: XAC (Canadian) firmware S918WVLU8GZIF

Not included, because they don't work on the S23: the S24's AI weather wallpaper (its model is built
only for the S24's NPU), Dual rec (can't open the S23's cameras), and two-lens or seamless-zoom
Portrait video (they crash the camera).

The installer asks which ones you want and greys out the ones your phone can't take.

**Nothing is written to any partition.** Every change is a kernel module load, an overlay, a bind mount or a runtime setting. The files behind them stay on storage in `/data/adb/s23tweaks`, so they use no RAM. A reboot puts the phone back to stock, and then the tweaks re-apply by themselves (see [After a reboot](#after-a-reboot)). The exceptions: two Google Play services flag overrides that `airdrop` adds, the camera setting that shows Director's view (`camextras`), and Samsung Language Core, which `callscreen` installs as an app update (see [Undo](#undo)).

**Different firmware?** Point your AI coding agent at [AGENTS.md](AGENTS.md) and it can build the kernel modules for your phone (see [Other firmware](#other-firmware-let-your-ai-agent-build-it)).

<a id="before-you-start"></a>

## ✅ Before you start

You need:

1. **A Galaxy S23 Ultra** on One UI 9.
2. **Root, from two apps:**
   - **DFRoot** (by diabl0w): [github.com/diabl0w/DFRoot](https://github.com/diabl0w/DFRoot). It roots the stock, locked-bootloader firmware at runtime by loading KernelSU, and does it again by itself at every boot.
   - **KernelSU manager, Samsung build `samsung-v2.2`**: [its samsung-v2.2 release](https://github.com/diabl0w/KernelSU/releases/tag/samsung-v2.2). DFRoot needs it installed to load root.

   Install both APKs, open DFRoot and tap **LAUNCH ROOT** once.
3. **Only for the computer installer:** a computer (macOS or Linux) with [Android platform-tools](https://developer.android.com/tools/releases/platform-tools) (`adb`), a USB cable, and **USB debugging** on (Settings → About phone → Software information → tap *Build number* 7 times, then Settings → Developer options → *USB debugging*). Run `adb devices` once and accept the prompt on the phone, then in KernelSU → **Superuser** allow **Shell**.

> Root has side effects. Some apps with anti-tamper checks refuse to run while the KernelSU manager app is installed (for example CRED in India). You do this at your own risk.

<a id="install"></a>

## 📦 Install

### On the phone: KernelSU module (no computer)

1. On the phone, download the `s23-ultra-tweaks-v….zip` file from the [latest release](https://github.com/dtechterminal/s23-ultra-tweaks/releases/latest).
2. Open **KernelSU** → **Modules** → **Install** and pick the zip. It checks that this is an S23 Ultra and whether the AirDrop files match your firmware.
3. **Reboot.** DFRoot roots the phone by itself during boot and KernelSU activates the module.
4. Open **KernelSU** → **Modules** → **S23 Ultra Tweaks** → the page icon. Tick the tweaks you want, switch on **Apply at every boot** if you like, and tap **Apply**.

The page greys out tweaks your phone can't take and says why. During the apply, Wi-Fi drops for ~30 s (AirDrop and Wi-Fi 7), and the screen goes black for ~30 s while Android restarts. The page closes during that; reopen it to see the result. The module's action button (▶) re-applies your saved picks.

To remove it: KernelSU → Modules → S23 Ultra Tweaks → Remove, then reboot.

### From a computer: installer script

With the phone plugged in and rooted:

```sh
curl -fsSL https://raw.githubusercontent.com/dtechterminal/s23-ultra-tweaks/main/install.sh | bash
```

Or clone and run it:

```sh
git clone https://github.com/dtechterminal/s23-ultra-tweaks
cd s23-ultra-tweaks
./install.sh
```

What happens:

- It checks the phone model, firmware, root and Play services version, then shows the menu.
- It downloads the tweak scripts. The files some tweaks need (the AirDrop driver, the S24 apps, Language Core) are downloaded by the phone itself from this repo's release when it applies them, each checked against a SHA-256 pinned in `device/tweaks.sh`.
- It copies everything to `/data/adb/s23tweaks` on the phone (a root-only folder) and applies your picks.
- It asks whether to re-apply them automatically at every boot.
- With `airdrop`, Wi-Fi and the hotspot drop for about 30 s while the driver is swapped.
- The screen goes black for about 30 s while Android restarts its framework. Leave the cable in.

### After a reboot

If you said yes to *re-apply automatically at every boot*, there's nothing to do and no computer is needed:

1. DFRoot roots the phone by itself during boot (its boot receiver runs the same exploit as **LAUNCH ROOT**).
2. KernelSU then runs the scripts in `/data/adb/service.d/`, and the installer put one there.
3. About a minute after boot, the tweaks re-apply: Wi-Fi drops for ~30 s and the screen goes black for ~30 s once. A notification says when they're on.

A fail-safe prevents boot loops. If a boot's apply never finished (the phone rebooted in the middle), or the Wi-Fi firmware crashed, the next boot skips the tweaks once and a notification says why. Reboot again or run the installer to bring them back.

If DFRoot didn't root the phone at boot (no notification after a few minutes), open DFRoot and tap **LAUNCH ROOT**. The tweaks then apply by themselves.

**Don't want root at every boot?** In DFRoot's settings, turn off **Start at Boot**. The phone then boots stock, with no KernelSU loaded, until you tap **LAUNCH ROOT**. With autostart on, the tweaks apply by themselves a minute after you tap it, still with no computer. So you get root, and the tweaks, only when you ask for them.

Without autostart, run the installer again after each reboot and press Enter to reuse your last picks.

To turn autostart off, run the installer and answer **n**, or:

```sh
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh autostart off"
```

### Using AirDrop

1. On the iPhone/Mac: Control Center → AirDrop → **Everyone for 10 minutes**, and keep it unlocked and close by.
2. On the S23: share a photo → **Quick Share** → **Share with Apple devices**. Apple devices show up in the list.

The S23's Wi-Fi briefly disconnects while Quick Share is looking for Apple devices. The S24 does the same.

If no Apple device shows up after the first apply, Play services may not have picked up its two flags yet. On an S918B it started offering Apple devices only after being restarted some minutes later: `adb shell su -c 'am force-stop com.google.android.gms'`, then open Quick Share again.

<a id="how-airdrop-works-on-an-s23"></a>

## 🍏 How AirDrop works on an S23

Samsung's S24-and-newer phones do AirDrop through Google's **Mosey** stack. The phone runs Apple's peer-to-peer Wi-Fi protocol (AWDL) itself, using a Qualcomm firmware feature called *Wondertap*. The S23 Ultra has the same Wi-Fi chip as the S24 Ultra (Qualcomm WCN7850), but its firmware, driver and system image leave all of this out. The `airdrop` tweak adds the S24 pieces at runtime:

1. **S24 Wi-Fi driver** (`kiwi_v2.ko`): Samsung's GPL source for the S24 Ultra's qcacld-3.0 driver with Wondertap, built against the S23 kernel. The patches are in `src/qcacld-patch`; they cover the S23's older cnss2 platform driver and a CFI function-type mismatch.
2. **S24 Wi-Fi firmware** (`amss20.bin`, `phy_ucode20.elf`, `regdb.bin`) in an overlay. The S23's own board file stays.
3. **`mhifix.ko`**: cnss2 sizes its firmware-download buffers for the boot-time firmware, and loading the bigger S24 image would crash the kernel. mhifix frees those buffers first.
4. **`bwfix.ko`**: when AirDrop starts, the S24 firmware asks for a PCIe Gen3 link. The S23's PCIe root port tops out at Gen2, so the request is refused, and the firmware crashes on the refusal. bwfix sets Gen2 and acknowledges.
5. **`wonder.ko`**: Google's virtual Wi-Fi driver that Mosey drives, with small S23 patches (`src/wonder-patch`).
6. **Mosey**: `MoseyApp.apk`, `mosey_server` and `libmosey_daemon_ffi.so` from the S24 Ultra system image, added to `/system_ext` in an overlay. `moseyrun` starts the daemon as uid `system` with only `NET_ADMIN`/`NET_RAW`, the same way the S24's init script does.
7. **Play services**: two Nearby flags (`45704091`, `45723015`) that make Play services hand AirDrop to Mosey, set as local overrides.

A watchdog script also runs. If the Wi-Fi firmware ever crashes, it saves the kernel log and reboots cleanly. Without it, the S24 driver's recovery leaves the phone to hard-reset about a minute later.

<a id="reporting-a-problem"></a>

## 🐞 Reporting a problem

Module page → Status → **Make a bug report**. It saves one text file in Download and offers to copy it.
Attach the file (or paste the text) in a [new issue](https://github.com/dtechterminal/s23-ultra-tweaks/issues),
with what you expected and what happened. Without the module page:

```sh
# prints the report file's path
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh report"
```

The report has the phone model, firmware, kernel and app versions, which tweaks are on and why any
aren't offered, the camera and feature settings the tweaks change (and what the phone had before),
the files the module mounts, the last apply and boot logs, and summaries of recent crashes. It leaves
out the serial number, email addresses, MAC addresses and long numbers such as the IMEI.

<a id="status-and-logs"></a>

## 📋 Status and logs

The module page shows all of this. From a computer (if you used the computer installer instead of the module, the script is `/data/adb/s23tweaks/tweaks.sh`):

```sh
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh status"
adb shell su -c "cat /data/adb/s23tweaks/tweaks.log"
# automatic applies at boot
adb shell su -c "cat /data/adb/s23tweaks/boot.log"
```

<a id="wi-fi-7-multi-link-mlo"></a>

## 📶 Wi-Fi 7 multi-link (MLO)

The S23 Ultra's chip (WCN7850) does Wi-Fi 7, including multi-link operation (MLO): one connection to a Wi-Fi 7 router over two bands at once. The S23's software only does part of it. Its `wpa_supplicant` has no 802.11be/MLO code, and its driver config leaves MLO off. `wifi7` builds on the `airdrop` driver, whose S24 source has MLO built in:

- **S24 `wpa_supplicant`** bind-mounted over the S23's. It speaks the same Samsung HAL extensions and needs one library the S23 vendor image lacks (`android.hardware.wifi.supplicant-V2-ndk.so`), which is added to `/vendor/lib64` with a read-only RAM overlay.
- **Driver config:** the S23's own `WCNSS_qcom_cfg.ini` plus the S24's four MLO lines (`mlo_support_link_num=2`, `mlo_5gl_5gh_mlsr=1`, `oem_eht_mlo_crypto_bitmap=0`, `epcs_support_enable=1`).

If Wi-Fi doesn't come up with the S24 supplicant, the installer switches back to the S23's and carries on without MLO.

Tested so far: Wi-Fi runs and connects normally with the S24 supplicant, and the driver's MLO code checks each network it joins. A multi-link connection itself hasn't been tested yet; that needs a Wi-Fi 7 router with MLO on. With one, Settings → Wi-Fi → (network) should show Wi-Fi 7, and `adb shell cmd wifi status` shows `MLO Link Id`s.

### Wi-Fi 7 mode page

One UI has a **Wi-Fi 7 mode** page (an on/off switch and *Maximum multi link count*). On the S23 its menu entry is hard-coded as unsupported, so it never shows up. The page itself works. To open it:

```sh
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh wifi7page"
```

The switch stores `Settings.Secure sec_wifi_7_mode_enabled` (default 1 = on). Samsung's Wi-Fi service applies a change at the next Wi-Fi disconnect. It switches Wi-Fi 7 off anyway in countries on Samsung's blocklist.

<a id="6-ghz-hotspot"></a>

## 📡 6 GHz hotspot

The S23 Ultra's Wi-Fi chip and its stock `hostapd` run a 6 GHz hotspot fine (tested: channel 1, 5975 MHz, 160 MHz wide, with an iPhone connected). Samsung's Settings only offers the 6 GHz band when the firmware's CSC country is on a hard-coded list (`SemWifiApServiceImpl.isRegionFor6GCountry`). For most S23 firmware it isn't: Canada, for example, needs a phone that launched with Android 15. `hotspot6g` sets the runtime property `ro.csc.countryiso_code` to `IN`, which passes on every Qualcomm phone. The sales code isn't touched.

- The hotspot's security must be **WPA3** on 6 GHz (Settings switches it for you).
- Transmit power and channels still follow the regulatory country the Wi-Fi driver detects, not this property.
- Apps that read the CSC country see `IN` until the next reboot.

The hotspot can't do Wi-Fi 7 (802.11be): neither the S23's nor the S24's `hostapd` is built with it.

<a id="display-log-video-and-vulkan"></a>

## 🎨 Display, Log video and Vulkan

- **Vividness**: Samsung hides *Screen mode → Advanced settings* (where the slider is) while **Eye comfort shield** or a vision accessibility feature is on. That's stock behaviour, the S24 does the same.
- **Always On Display**: *Lock screen and AOD → Always On Display* gets *Show Lock screen wallpaper*. *Erase background* only works with a photo wallpaper whose subject was cut out by the wallpaper editor (a "layered" wallpaper), not with the AI weather wallpaper.
- **Log video**: in *Pro video*, tap **LOG** at the top. The S23's camera already records 10-bit; the tweak only turns on Samsung's switches for it.
- **Vulkan**: Samsung's renderer ignores the S24's `ro.hwui.use_vulkan`; the tweak sets `debug.hwui.renderer=skiavk`. Check with `adb shell dumpsys gfxinfo com.android.systemui | grep Pipeline` (should say `Skia (Vulkan)`).

<a id="downloaded-tweaks-camerahdr-hdr2023-audioeraser-colortone-galaxyai-settingssearch"></a>

## ⬇️ Downloaded tweaks: camerahdr, hdr2023, audioeraser, colortone, galaxyai, settingssearch

These need files from Samsung firmware (from the S24's for the last three, and from the S23's own One UI 6
firmware for `camerahdr` and `hdr2023`). Each one is a separate file in the GitHub release `payloads-S918WVLU8GZIF`,
downloaded by the phone only when you pick that tweak. Its SHA-256 is pinned in `device/tweaks.sh`, and
it's kept in `/data/adb/s23tweaks/payload/` so it isn't downloaded again.

- **camerahdr** (untested): One UI 9 dropped the S23's ArcSoft multi-frame HDR and low-light HDR steps.
  The camera app still has them and, without them, runs a pass-through step that leaves the photo
  unprocessed. The tweak adds back the One UI 6 libraries and their entries in the camera's processing
  list. Details and how to check it: [docs/findings.md](docs/findings.md).
- **hdr2023**: binds the One UI 6 (2023) builds of the ArcSoft hybrid HDR and bracketed HDR engines and
  their Samsung wrappers over today's four libraries in `/system/lib64` (each checked by MD5 before use).
  For anyone who prefers the older HDR look; pick it by number.
- **audioeraser**: the S23's video editor engine was built without the audio scanner. The tweak swaps in
  the S24 engine and adds its sound-separation libraries and two models.
- **colortone**: Samsung compiled the S23's Settings to hide the switch. The tweak patches one byte in
  a patched copy of Settings, kept on storage (`device/files/SecSettings-ead-<firmware>.patch`, checked by MD5; `tools/eadpatch.py` makes one for another firmware's Settings app) and adds the S24's
  colour-tone service.
- **galaxyai**: binds the S24 builds of the three apps over the S23's. While it's on, it replaces any
  Galaxy Store update of Personal Data Intelligence; after a reboot without it, Galaxy Store offers the
  update again.
- **settingssearch**: binds the S24's Settings search app (same Samsung signature) over the S23's. The
  new search bar shows; the natural-language answers stay off, because they need Samsung's Semantic
  Search Core 4.x and both phones ship only a 1.0 placeholder.

<a id="call-screening"></a>

## 📞 Call screening

The Phone app's Call screening needs Samsung Language Core. The S23 firmware doesn't have it, and
Galaxy Store refuses the S23 ("not compatible", 9908). `callscreen` installs it (version 4.0.01.24,
signed by Samsung) as an ordinary app.

- **What works:** the Call screening switch, *Screen call* on incoming calls, the greeting read to the
  caller, and recording the caller's voice message.
- **What doesn't:** the caller/purpose summary ("Something went wrong while summarizing this call") and
  the AI replies to the caller. Samsung's language model inside Language Core is compiled only for the
  S26's NPU. On the S23 it stops before anything reaches the NPU, so it fails safely.
- **A 3.1 GB download.** GitHub caps a release file at 2 GB, so the phone downloads Language Core in
  two parts, checks each against its SHA-256, joins them, checks the APK's MD5, installs it and
  deletes the download. It needs about 7 GB free while it does this; use Wi-Fi.
- **It stays after a reboot**, unlike the other tweaks. Remove it with
  `adb shell pm uninstall com.samsung.android.offline.languagemodel`.

<a id="undo"></a>

## ↩️ Undo

**Remove the module** (KernelSU → Modules → S23 Ultra Tweaks → Uninstall) and reboot. During that
boot the module cleans up after itself once the phone is unlocked:

- removes AirDrop's two Play services flag overrides;
- uninstalls Samsung Language Core and its Call screening settings, if `callscreen` installed it;
- puts the Camera app's Director's view setting back the way it was (`camextras`);
- drops Android's cached manifests of the apps the tweaks swap, so the stock apps are re-read;
- deletes `/data/adb/s23tweaks` (downloads, logs, backups) and the boot script.

The mounts themselves were already undone by the reboot. If the computer installer also has its own
copy in `/data/adb/s23tweaks`, removing the module leaves that copy alone. To clean up by hand:

```sh
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh cleanup"
```

Without removing anything, a plain reboot puts the phone back to stock except for those persistent
items (the flags do nothing on their own; `tweaks.sh unflag` removes just them).

<a id="known-limitations"></a>

## ⚠️ Known limitations

- **AirDrop needs One UI 9 build GZIF** (S918WVLU8GZIF, S918BXXUAGZIF, S918U1UEU8GZIF, S918USQU8GZIF or S918NKSU8GZIF). The modules are built on the S918W kernel. The other four have the same Wi-Fi drivers and the same kernel symbol CRCs, checked with `tools/kocompat.py` and `tools/modcmp.py` against their firmware files, but only the S918W and S918B have been tested on a phone. A different build needs the modules rebuilt (below).
- Only **sending** to Apple devices has been tested. Receiving from them hasn't.
- The Wi-Fi link to the PCIe bus stays at Gen2, so very large transfers may be slower than on an S24.
- `callrec` and `india` replace three carrier config files. They only apply when those files exactly match the S918WVLU8GZIF XAC ones (checked by MD5). On EUX firmware S918BXXUAGZIF `callrec` replaces one file, `cscfeature.xml`, under the same MD5 check. Neither tweak ever touches the sales code (`mps_code.dat`, `sales_code.dat`, `omc.info`). Changing the sales code can factory-reset the phone.
- Tested on an SM-S918W (S918WVLU8GZIF, XAC, Android 17, Play services 26.45). On an SM-S918B (S918BXXUAGZIF, EUX) `airdrop`, `wifi7` (without a multi-link connection), `colortone`, `callrec` and `battery` have also been tested. Reports from other models are welcome.

<a id="other-firmware-let-your-ai-agent-build-it"></a>

## 🤖 Other firmware: let your AI agent build it

The kernel modules only load on the exact kernel they were built for. If your S23 Ultra runs different firmware, the installer marks `airdrop` and `wifi7` as unavailable. You can build your own modules by handing the job to an AI coding agent (Claude Code, Codex, Cursor and similar):

1. Clone this repo and open the agent in it, on a computer with Docker and your phone connected over USB (rooted, USB debugging on).
2. Tell it something like:

   > Read AGENTS.md and build the kernel modules and payload for my phone's firmware. Show me every script before you run it on the phone.

[AGENTS.md](AGENTS.md) tells the agent:

- **Rules for working on your phone:** show every script before running it, never write to a partition, and never touch the sales code.
- **What to download:** the Samsung kernel source for your firmware, the matching compiler, and the S24 firmware the payload files come from.
- **How to rebuild:** regenerate the symbol-version data from your phone's own modules, re-derive the values that change per firmware, and rebuild the payload.
- **How to test** safely on the phone, step by step.

It takes a few hours of mostly downloading and compiling. The Samsung source and the S24 firmware together are about 25 GB. The rest of the tweaks (`battery`, `features`, `hotspot6g`) don't need any of this.

<a id="building-the-kernel-modules"></a>

## 🛠️ Building the kernel modules

You only need this to change the modules or to support other firmware. To port everything to another firmware, see [AGENTS.md](AGENTS.md). You need Docker (an x86-64 image; it runs under emulation on Apple Silicon), AOSP clang `clang-r450784e`, and Samsung's kernel sources from <https://opensource.samsung.com>:

- `SM-S918B_17_Opensource.zip` (S23 Ultra): extract `Kernel.tar.gz` to `/work/s23` in a Docker volume.
- `SM-S928B_17_Opensource.zip` (S24 Ultra): extract `Kernel.tar.gz` to `/work/s24`. The driver, Wondertap and `wonder` sources are under `vendor/qcom/opensource/wlan`.

```sh
docker build -t s23kbuild build -f build/Dockerfile
docker build -t s23kbuild16 build -f build/Dockerfile.cc16
run() { docker run --rm --platform linux/amd64 -v s23kvol:/work -v /path/to/clang-r450784e:/clang:ro \
          -v "$PWD":/repo:ro -v "$PWD/out":/out "$@"; }
run s23kbuild   bash /repo/build/prep-vendor-tree.sh   # Samsung's vendor-module config for GZIF
run s23kbuild   bash /repo/build/build-kiwi.sh         # out/kiwi_v2.ko
run s23kbuild   bash /repo/build/build-wonder.sh       # out/wonder.ko
run s23kbuild16 bash /repo/build/build-mhifix.sh       # out/mhifix.ko
run s23kbuild16 bash /repo/build/build-bwfix.sh        # out/bwfix.ko
```

`build/Module.symvers.base` and `build/extra.symvers` hold the export CRCs of the GZIF kernel and its vendor modules, so the modules load without `modprobe --force`. The phone-side helpers (`moseyrun`, `pbflag`, plus a static `sqlite3`) build with the Android NDK: `aarch64-linux-android34-clang -O2 -static`.

<a id="legal"></a>

## ⚖️ Legal

The scripts and the source in `src/` are GPL-2.0 (see `LICENSE`); the kernel modules have to be. The driver and `wonder` binaries are built from Samsung's and Google's GPL sources listed above. The release payload also contains files from the Galaxy S24 Ultra firmware (Qualcomm Wi-Fi firmware, Google's Mosey app and daemon). Those belong to their owners and are only provided so the S23 can use a feature its hardware supports. This project is not affiliated with Samsung, Google, Qualcomm or Apple. AirDrop is a trademark of Apple Inc.
