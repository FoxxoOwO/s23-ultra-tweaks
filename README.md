# s23-ultra-tweaks

Turns on Galaxy S24-and-newer features on a rooted Galaxy S23 Ultra running One UI 9 / Android 17, with no flashing:

| # | Tweak | What you get | Works on |
|---|---|---|---|
| 1 | `airdrop` | **AirDrop with iPhones, iPads and Macs.** Quick Share → *Share with Apple devices* | SM-S918W, firmware **S918WVLU8GZIF** only (the kernel modules are built for that exact kernel) |
| 2 | `battery` | Settings → Battery → **Battery information** shows battery health and cycle count | any S23 Ultra on One UI 9 |
| 3 | `features` | **Auto power on/off** schedule, **louder VoIP calls** | any S23 Ultra on One UI 9 |
| 4 | `callrec` | **Call recording** in the Samsung Phone app | XAC (Canadian) firmware S918WVLU8GZIF |
| 5 | `india` | India (INS) carrier config: call recording, Smart IVR, message cards and more. The sales code stays XAC | XAC (Canadian) firmware S918WVLU8GZIF |
| 6 | `hotspot6g` | **6 GHz Mobile Hotspot** (Wi-Fi 6E, 160 MHz): Mobile Hotspot → Band → 6 GHz | any S23 Ultra on One UI 9 |
| 7 | `wifi7` | **Wi-Fi 7 multi-link (MLO)** with Wi-Fi 7 routers. Includes `airdrop` | same as `airdrop` |

The installer asks which ones you want and greys out the ones your phone can't take.

**Nothing is written to any partition.** Every change is a kernel module load, a RAM overlay, a bind mount or a runtime setting. A reboot puts the phone back to stock, so you run the installer again after each reboot (it remembers your picks). The one exception is two Google Play services flag overrides that `airdrop` adds (see [Undo](#undo)).

## Before you start

You need:

1. **A Galaxy S23 Ultra** on One UI 9 with **USB debugging** on (Settings → About phone → Software information → tap *Build number* 7 times, then Settings → Developer options → *USB debugging*).
2. **A computer** (macOS or Linux) with [Android platform-tools](https://developer.android.com/tools/releases/platform-tools) (`adb`) and a USB cable. Run `adb devices` once and accept the prompt on the phone.
3. **Root, from two apps:**
   - **DFRoot** (by diabl0w): <https://github.com/diabl0w/DFRoot>. It roots the stock, locked-bootloader firmware at runtime by loading KernelSU.
   - **KernelSU manager, Samsung build `samsung-v2.2`**: <https://github.com/diabl0w/KernelSU/releases/tag/samsung-v2.2>. DFRoot needs it installed to load root.

   Install both APKs, open DFRoot and tap **LAUNCH ROOT**. Then open KernelSU → **Superuser** and allow **Shell** (that is what `adb` uses).

> Root has side effects. Some apps with anti-tamper checks refuse to run while the KernelSU manager app is installed (for example CRED in India). You do this at your own risk.

## Install

With the phone plugged in and rooted:

```sh
curl -fsSL https://raw.githubusercontent.com/dtechterminal/s23-ultra-tweaks/main/install.sh | bash
```

Or clone and run it:

```sh
git clone https://github.com/dtechterminal/s23-ultra-tweaks && cd s23-ultra-tweaks && ./install.sh
```

What happens:

- It checks the phone model, firmware, root and Play services version, then shows the menu.
- It downloads the tweaks. `airdrop` and `wifi7` also download a 20 MB payload from this repo's release, which is checked against a SHA-256 pinned in `install.sh`.
- It copies everything to `/data/local/tmp/s23tweaks` on the phone and applies your picks.
- With `airdrop`, Wi-Fi and the hotspot drop for about 30 s while the driver is swapped.
- The screen goes black for about 30 s while Android restarts its framework. Leave the cable in.

**After every reboot:** open DFRoot → **LAUNCH ROOT**, then run the installer again and press Enter to reuse your last picks.

### Using AirDrop

1. On the iPhone/Mac: Control Center → AirDrop → **Everyone for 10 minutes**, and keep it unlocked and close by.
2. On the S23: share a photo → **Quick Share** → **Share with Apple devices**. Apple devices show up in the list.

The S23's Wi-Fi briefly disconnects while Quick Share is looking for Apple devices. The S24 does the same.

## How AirDrop works on an S23

Samsung's S24-and-newer phones do AirDrop through Google's **Mosey** stack. The phone runs Apple's peer-to-peer Wi-Fi protocol (AWDL) itself, using a Qualcomm firmware feature called *Wondertap*. The S23 Ultra has the same Wi-Fi chip as the S24 Ultra (Qualcomm WCN7850), but its firmware, driver and system image leave all of this out. The `airdrop` tweak adds the S24 pieces at runtime:

1. **S24 Wi-Fi driver** (`kiwi_v2.ko`): Samsung's GPL source for the S24 Ultra's qcacld-3.0 driver with Wondertap, built against the S23 kernel. The patches are in `src/qcacld-patch`; they cover the S23's older cnss2 platform driver and a CFI function-type mismatch.
2. **S24 Wi-Fi firmware** (`amss20.bin`, `phy_ucode20.elf`, `regdb.bin`) in a RAM overlay. The S23's own board file stays.
3. **`mhifix.ko`**: cnss2 sizes its firmware-download buffers for the boot-time firmware, and loading the bigger S24 image would crash the kernel. mhifix frees those buffers first.
4. **`bwfix.ko`**: when AirDrop starts, the S24 firmware asks for a PCIe Gen3 link. The S23's PCIe root port tops out at Gen2, so the request is refused, and the firmware crashes on the refusal. bwfix sets Gen2 and acknowledges.
5. **`wonder.ko`**: Google's virtual Wi-Fi driver that Mosey drives, with small S23 patches (`src/wonder-patch`).
6. **Mosey**: `MoseyApp.apk`, `mosey_server` and `libmosey_daemon_ffi.so` from the S24 Ultra system image, added to `/system_ext` in a RAM overlay. `moseyrun` starts the daemon as uid `system` with only `NET_ADMIN`/`NET_RAW`, the same way the S24's init script does.
7. **Play services**: two Nearby flags (`45704091`, `45723015`) that make Play services hand AirDrop to Mosey, set as local overrides.

A watchdog script also runs. If the Wi-Fi firmware ever crashes, it saves the kernel log and reboots cleanly. Without it, the S24 driver's recovery leaves the phone to hard-reset about a minute later.

## Status and logs

```sh
adb shell su -c "sh /data/local/tmp/s23tweaks/tweaks.sh status"
adb shell su -c "cat /data/local/tmp/s23tweaks/tweaks.log"
```

## Wi-Fi 7 multi-link (MLO)

The S23 Ultra's chip (WCN7850) does Wi-Fi 7, including multi-link operation (MLO): one connection to a Wi-Fi 7 router over two bands at once. The S23's software only does part of it. Its `wpa_supplicant` has no 802.11be/MLO code, and its driver config leaves MLO off. `wifi7` builds on the `airdrop` driver, whose S24 source has MLO built in:

- **S24 `wpa_supplicant`** bind-mounted over the S23's. It speaks the same Samsung HAL extensions and needs one library the S23 vendor image lacks (`android.hardware.wifi.supplicant-V2-ndk.so`), which is added to `/vendor/lib64` with a read-only RAM overlay.
- **Driver config:** the S23's own `WCNSS_qcom_cfg.ini` plus the S24's four MLO lines (`mlo_support_link_num=2`, `mlo_5gl_5gh_mlsr=1`, `oem_eht_mlo_crypto_bitmap=0`, `epcs_support_enable=1`).

If Wi-Fi doesn't come up with the S24 supplicant, the installer switches back to the S23's and carries on without MLO.

Tested so far: Wi-Fi runs and connects normally with the S24 supplicant, and the driver's MLO code checks each network it joins. A multi-link connection itself hasn't been tested yet; that needs a Wi-Fi 7 router with MLO on. With one, Settings → Wi-Fi → (network) should show Wi-Fi 7, and `adb shell cmd wifi status` shows `MLO Link Id`s.

### Wi-Fi 7 mode page

One UI has a **Wi-Fi 7 mode** page (an on/off switch and *Maximum multi link count*). On the S23 its menu entry is hard-coded as unsupported, so it never shows up. The page itself works. To open it:

```sh
adb shell su -c "sh /data/local/tmp/s23tweaks/tweaks.sh wifi7page"
```

The switch stores `Settings.Secure sec_wifi_7_mode_enabled` (default 1 = on). Samsung's Wi-Fi service applies a change at the next Wi-Fi disconnect. It switches Wi-Fi 7 off anyway in countries on Samsung's blocklist.

## 6 GHz hotspot

The S23 Ultra's Wi-Fi chip and its stock `hostapd` run a 6 GHz hotspot fine (tested: channel 1, 5975 MHz, 160 MHz wide, with an iPhone connected). Samsung's Settings only offers the 6 GHz band when the firmware's CSC country is on a hard-coded list (`SemWifiApServiceImpl.isRegionFor6GCountry`). For most S23 firmware it isn't: Canada, for example, needs a phone that launched with Android 15. `hotspot6g` sets the runtime property `ro.csc.countryiso_code` to `IN`, which passes on every Qualcomm phone. The sales code isn't touched.

- The hotspot's security must be **WPA3** on 6 GHz (Settings switches it for you).
- Transmit power and channels still follow the regulatory country the Wi-Fi driver detects, not this property.
- Apps that read the CSC country see `IN` until the next reboot.

The hotspot can't do Wi-Fi 7 (802.11be): neither the S23's nor the S24's `hostapd` is built with it.

## Undo

Reboot. Everything goes back to stock except the two Play services flag overrides. They do nothing without the rest, but to remove them:

```sh
adb shell su -c "sh /data/local/tmp/s23tweaks/tweaks.sh unflag"
```

## Known limitations

- **AirDrop needs firmware S918WVLU8GZIF.** Kernel modules only load on the kernel they were built for. For other firmware, rebuild them (below) against that firmware's kernel source.
- Only **sending** to Apple devices has been tested. Receiving from them hasn't.
- The Wi-Fi link to the PCIe bus stays at Gen2, so very large transfers may be slower than on an S24.
- `callrec` and `india` replace three carrier config files. They only apply when those files exactly match the S918WVLU8GZIF XAC ones (checked by MD5), and never touch the sales code (`mps_code.dat`, `sales_code.dat`, `omc.info`). Changing the sales code can factory-reset the phone.
- Tested on one phone: SM-S918W, S918WVLU8GZIF, Android 17, Play services 26.45.

## Building the kernel modules

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

## Legal

The scripts and the source in `src/` are GPL-2.0 (see `LICENSE`); the kernel modules have to be. The driver and `wonder` binaries are built from Samsung's and Google's GPL sources listed above. The release payload also contains files from the Galaxy S24 Ultra firmware (Qualcomm Wi-Fi firmware, Google's Mosey app and daemon). Those belong to their owners and are only provided so the S23 can use a feature its hardware supports. This project is not affiliated with Samsung, Google, Qualcomm or Apple. AirDrop is a trademark of Apple Inc.
