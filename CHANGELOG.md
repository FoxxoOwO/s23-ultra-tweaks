# Changelog

## v1.0.0

First release, for the Galaxy S23 Ultra on One UI 9 / Android 17 (AirDrop and Wi-Fi 7 need firmware S918WVLU8GZIF).

- Seven tweaks: AirDrop with Apple devices, battery health page, extra settings (auto power on/off, louder VoIP calls), call recording, India (INS) carrier config, 6 GHz Mobile Hotspot, Wi-Fi 7 multi-link (MLO).
- KernelSU module with a settings page: install from KernelSU → Modules, pick tweaks and apply on the phone, no computer needed.
- Apply at every boot: the saved tweaks re-apply automatically after each reboot, with fail-safes against boot loops.
- Computer installer (`install.sh`) over adb for macOS and Linux.
- Nothing is written to a partition; a reboot returns the phone to stock.
