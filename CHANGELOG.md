# Changelog

## v1.1.0

- **Categories:** the tweaks are grouped into Connectivity, Camera, Display and graphics, Galaxy AI and Samsung apps, Battery and settings, and Carrier. The module page has a checkbox per category (all, some or none), and the installer takes a category letter or single tweak numbers.
- New tweaks: `camextras` (Director's view and Super steady horizontal lock), `autoframe` (4K auto framing, untested), `settingssearch` (S24 Settings search bar, 10 MB download), `bargein` (Bixby barge-in, untested) and `callscreen` (Call screening via Samsung Language Core; screening works, the AI summary doesn't; persistent; bring your own 3.1 GB APK).
- Camera settings from several tweaks now share one rebuilt camera-feature.xml.

- New tweaks: `display` (Vividness slider and full-screen AOD wallpaper), `logvideo` (Log recording and LUT preview in Pro video) and `vulkan` (Skia on Vulkan for apps).
- Feature flags can now be set to values, replacing the stock ones (not only added as TRUE).
- New tweaks with their own download, fetched by the phone only when picked: `camerahdr` (untested: puts back the multi-frame and low-light HDR camera processing One UI 9 removed), `audioeraser` (Audio Eraser in Gallery), `colortone` (Adaptive color tone) and `galaxyai` (S24 Now Brief, Creative Studio and Call Assist).
- `docs/findings.md`: research notes, starting with the One UI 9 camera processing regression.

## v1.0.0

First release, for the Galaxy S23 Ultra on One UI 9 / Android 17 (AirDrop and Wi-Fi 7 need firmware S918WVLU8GZIF).

- Seven tweaks: AirDrop with Apple devices, battery health page, extra settings (auto power on/off, louder VoIP calls), call recording, India (INS) carrier config, 6 GHz Mobile Hotspot, Wi-Fi 7 multi-link (MLO).
- KernelSU module with a settings page: install from KernelSU → Modules, pick tweaks and apply on the phone, no computer needed.
- Apply at every boot: the saved tweaks re-apply automatically after each reboot, with fail-safes against boot loops.
- Computer installer (`install.sh`) over adb for macOS and Linux.
- Nothing is written to a partition; a reboot returns the phone to stock.
