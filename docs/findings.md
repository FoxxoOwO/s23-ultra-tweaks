# Findings

Research notes from porting S24 features to the Galaxy S23 Ultra (SM-S918W, S918WVLU8GZIF, One UI 9 /
Android 17). Each section says what was confirmed on the phone and what is still unverified.

## Camera: photos not processed after capture (One UI 9)

Written 2026-11-22. Camera app 17.0.00.43. Compared against the S23's One UI 6 firmware (S918WVLS2BWKA,
2023) and the S24 Ultra (S928BXXU6EZJB).

Owners report that on One UI 9 S23 Ultra photos look flat and soft, that the final image appears
instantly, and that the old "processing" step after a shot is gone.

### Summary

- **Processing is not skipped everywhere.** A low-light shot ran the full path. The camera saved a
  draft, fed 11 RAW frames through Super Night (3.1 s), and replaced the draft with the processed photo
  5.4 s after the shot.
- **One UI 9 removed two of the S23's processing steps:** ArcSoft multi-frame HDR (`mfhdr.arcsoft.v4`)
  and low-light HDR (`llhdr.arcsoft.v4`). Both the feature-list entries and the libraries are gone. The
  camera app still contains both steps. When a step isn't listed, it substitutes a "dummy" step that
  returns the frame unchanged. That would produce exactly the reported symptom: a flat image that is
  "done" instantly.
- **Unverified: whether One UI 9 still picks those HDR modes for any scene.** Only dark scenes were shot,
  and they used Super Night or a single frame. Daylight, backlit, 3x and 10x shots will settle it.
- **Confirmed second cause:** if the camera process is killed while a photo is still processing, the
  unprocessed draft becomes the permanent photo. This happens on a swipe-away, a memory kill or a
  background app killer.

### 1. The low-light path still processes

```
19:53:05.639 SingleCaptureController: requestSingleCapture : PROCESSING_POST
19:53:05.656 RearPhotoMaker: takePostProcessingPicture - ... dsMode = SUPER_NIGHT_HANDHELD
19:53:06.493 RearPhotoMaker: onDraftPostProcessingPictureTaken ...      (draft saved)
19:53:06.804 V2/MpiSuperNightNode: processPicture - Start : (1/11) ... RAW_SENSOR
19:53:10.889 MFP30IF : MFRP Lib processTime: 3078.8 ms
19:53:11.886 PostSavingStateManager: postSavingStateChanged(ppSequenceId:0)  E : DRAFT->COMPLETE
```

### 2. A killed camera keeps the draft forever

A Super Night shot (6 RAW frames) was cut off by a force-stop about 10 s after capture. On the next
launch the camera discarded the pending work:

```
RecoveryProcessManager: deleteDanglingDraftImageFiles - /data/sec/camera/native/20261122_195149_temp.jpg
```

The unprocessed draft stayed in Gallery as the final photo. Leave the camera open until the processing
indicator is gone, and keep the camera out of any app killer.

### 3. What One UI 9 removed

| Item | S23 One UI 6 (2023) | S23 One UI 9 | S24 |
|---|---|---|---|
| `mfhdr.arcsoft.v4` in `CAMERA_CONFIG_VENDOR_LIB_INFO` | yes | **no** | no |
| `llhdr.arcsoft.v4` in `CAMERA_CONFIG_VENDOR_LIB_INFO` | yes | **no** | no |
| `scene_detection.samsung.v1` in `CAMERA_CONFIG_VENDOR_LIB_INFO` | yes | no (now done in the camera HAL) | no |
| `image_codec.samsung.v2` in `CAMERA_CONFIG_VENDOR_LIB_INFO` | no | yes | yes |
| `/system/lib64/libhigh_dynamic_range.arcsoft.so` | 13,032,680 B, md5 `c6b7aa034c3704dcfccc87ca32582dc6` | **absent** | absent |
| `/system/lib64/liblow_light_hdr.arcsoft.so` | 19,178,408 B, md5 `656c3c400bb9ebf74a05e23865c334cb` | **absent** | absent |
| both listed in `/system/etc/public.libraries-arcsoft.txt` | yes | no | no |

- **`camera-feature.xml`:** only UI-guide and Camera Assistant entries differ; nothing processing-related.
- **Other camera flags:** nothing else was removed; One UI 9 added some (AIFRC, GPPM, PREWARMING_LEVEL…).
- **`aimfisp.samsung.v1`:** the camera rejects it as an invalid node name in both builds. Not a
  regression.

### 4. Why the 2023 libraries should still work

- **Routing:** the camera app (`NodeChainKeyContainer`) sends shot modes 20–29 to the `MF_HDR` chain and
  30–35, 37–39 and 60 to the `LL_HDR` chain.
- **Dummy fallback:** `NodeFeature` maps each chain to `MfHdrDummyNode` / `LlHdrDummyNode` when its
  feature isn't registered. Their `processPicture*` methods return the input buffer unchanged.
- **Where the list comes from:** only `SemFloatingFeature.getString("SEC_FLOATING_FEATURE_CAMERA_CONFIG_VENDOR_LIB_INFO")`.
- **Native code is still there:** today's `libnode-jni.so` still has `mfhdr::arcsoft::v4::ArcMfHdrNode`
  and `llhdr::arcsoft::v4::ArcLlHdrNode`, and names both libraries.
- **Exports match:** the symbols it looks up match the 2023 libraries' exports exactly (8 `ARC_HDR_*_V4`,
  11 `ARC_LLHDR_*`).
- **Dependencies are present:** both libraries need only libmpbase, liblog, libc, libm and libdl, which
  are all on the phone.
- **Unverified:** compatibility beyond symbol names (struct layouts). The 2023 libraries also carry
  2023 tuning.

### 5. Shot modes seen live (dark scenes only)

- `SINGLE` (processing mode 0x2: no app processing, so the photo is final instantly)
- `SUPER_NIGHT_HANDHELD` (80)
- `SUPER_NIGHT_EXTREME_DARK` (83)
- `HYBRID_NNHDR_MERGE_QZ` (241, preview only)

No MF_HDR or LL_HDR mode appeared. The camera HAL's string tables list the same 21 MFHDR/LLHDR/NNHDR
mode names in 2023, today and on the S24, so the strings alone don't settle whether they are still used.

### 6. Settings and the Reddit claims

- **"Prioritize quality isn't the cause":** agrees with the code. This phone is on maximum
  (`quality_optimization=0`, i.e. MAX), with Scene optimizer and HDR on.
- **"The final image appears instantly":** confirmed for any `SINGLE` shot and for a draft whose
  processing was killed.
- **"The processing setting disappears without Camera Assistant":** not checked. The setting still exists
  in the camera code; Camera Assistant isn't installed on this phone.
- **No server-side processing config:** the camera has no downloaded config, and the Secure, System and
  Global tables hold no camera-processing keys.
- **Our tweaks don't cause it:** the module's flag changes (Log video, Motion Photo extras, high-res
  binning, document scan) don't touch the processing list. The losses above are in Samsung's stock files.

### Fix: `camerahdr` tweak (untested)

`camerahdr` puts back what One UI 9 removed. Everything is RAM-only and gone after a reboot.

- The two 2023 libraries, added to `/system/lib64` through a tmpfs overlay.
- Their two lines in `public.libraries-arcsoft.txt`, also through an overlay.
- `mfhdr.arcsoft.v4,llhdr.arcsoft.v4` appended to `CAMERA_CONFIG_VENDOR_LIB_INFO`.

`SemFloatingFeature` parses the flag file once per process, and zygote may hold the parsed copy. So the
tweak goes through the framework restart, like the other flag tweaks.

**How to check it on the phone:**

1. **Stock baseline.** Shoot a bright backlit window, a normal indoor scene, 3x and 10x. In logcat look
   for `takePostProcessingPicture ... dsMode = MFHDR_MERGE_*` or `LLHDR_MERGE_*`, and above all for
   `NodeFactory: creating dummyNode(...MfHdrDummyNode` or `...LlHdrDummyNode`. That line proves the step
   is being skipped.
2. **With `camerahdr` on.** The camera's start-up log should show
   `loadNodeFeature - register node feature info [mfhdr.arcsoft.v4]` and `[llhdr.arcsoft.v4]`. Shooting
   the same scenes should show `ArcMfHdrNode` / `ArcLlHdrNode` and `DRAFT->COMPLETE`, with no
   `dlopen` errors and no crash.
3. **Compare** the before/after photos at 100 %: detail, highlights in the backlit shot, colour.

If step 1 never shows a dummy node, the removal is harmless on this firmware. Then the remaining causes
are killed drafts and Samsung's HAL-side changes, and `camerahdr` should stay off.

### Lessons

- **Don't read the stock file from under a bind mount with toybox `unshare -m`.** It doesn't make mounts
  private, so the `umount` reached init's namespace and removed two live overrides for about 3 minutes.
  Use util-linux `unshare -m --propagation private`, or `mount --make-rprivate /` first, or read the file
  from the firmware image instead.

## AI weather wallpaper: what Samsung's pipeline expects

Written 2026-11-22. Samsung's weather wallpaper is built for the S24's NPU (Hexagon V75). The S23 has V73,
so its three model files have to be rebuilt. These notes say what the rebuilt files must accept. They come
from `libSSNeuralCoreVNDK.so` and `liblvm.samsung.so` in Samsung AI Core, and the wallpaper package in
VisionModel 200517500.

### Confirmed from the code

- **Pipeline:** the wallpaper runs the "Adapter3" pipeline (`SS_SR_WALLPAPER_ADAPTER`, foundation model
  `SD_V15_I2I`, 10 steps, OLSS scheduler with `olss_weights.json`).
- **Encoder (SSNet1):** the image goes in normalised to −1..1. The pipeline multiplies the output by
  `encoder_scale = 0.18215`, hard-coded in `liblvm` and logged as "scaling SSNet1 output by %f". So the
  encoder model must output **unscaled** latents.
- **Conditioning:** the pipeline concatenates `[one channel of ones, scaled image latents (4)]` for the
  **whole** image. No segmentation mask goes into the UNet. The sky mask (`segMaskBuffer`, fast guided
  filter in `liblvm`) is only used to blend the result afterwards.
- **Decoder (SSNet3):** the denoised latents go in unchanged, and afterwards the pipeline only clamps to
  0..1. So the decoder model must apply `1/0.18215` itself and output `x/2 + 0.5`.
- **Guidance:** each prompt pair has two scales (`wallpaper_prompt_scale.txt`, e.g. `6 7 6.5 1.6`), logged
  as "using guidance scaling factors %f and %f". There is a three-way concatenation in the denoise loop.
  This matches InstructPix2Pix guidance, with a text scale and an image scale.
- **Mode-2 scaling isn't this path:** the `Image2ImagePipeline` class also scales latents by 0.18215 / 1/0.18215,
  but only in its mode 2. The wallpaper uses Adapter3.

### Tested on a PC (float, public models, Samsung's conventions)

- **SD1.5-inpainting UNet (first rebuild): fails.** With Samsung's conditioning (mask all ones, full-image
  latents) it only blows out the colours and makes no weather change. It produced good edits only with a
  sky mask and masked latents, which Samsung's pipeline never provides.
- **InstructPix2Pix UNet (SD1.5 base): works.** With the image latents un-scaled inside the graph and
  three-pass guidance using Samsung's own prompt pairs and scales, it gives scene-preserving snow,
  snowy-evening, golden-hour, night, clear-after-rain and rainy-night edits. "Dark night" at text scale 9.0
  comes out nearly black.
- **Next:** rebuild the UNet and its time-embedding file from InstructPix2Pix for V73. Then test on the
  phone; the order of the UNet's 9 input channels is only inferred (`[noisy latents, ones, image latents]`).

## Call Screening (One UI 9 Phone app on the S23)

- **The app side works.** The S24 Phone and Call Assist builds show the Call screening page, and its switch
  sets `call_screening=1` in Settings.System. With the switch off, InCallUI logs
  `getCallScreeningConfigState: DISABLED` and calls go to Text call.
- **It needs Samsung Language Core** (`com.samsung.android.offline.languagemodel`). The firmware ships only a
  stub (1.0.00.38). InCallUI reads a `FUNCTION_INFO` JSON from Language Core's manifest. Call Screening
  needs the `CallScreeningResponse` function, which the real builds list for ko, en, es, fr, de, it, pt,
  zh, ja, pl, hi, th, vi, ru, id and ar.
- **No Language Core build fits the S23.** Each build carries Samsung's on-device LLM compiled for one NPU.
  The builds on APKMirror (checked by reading their file lists, not downloaded):

  | Version | Build number | Models | Target |
  |---|---|---|---|
  | 4.1.20.28 | 412028100 | `.nnc`, `lora_lsi_*` | Exynos S26 |
  | 4.0.01.24 | 400124010 | QNN 2.38/2.39, `libQnnHtpV81Stub` | Snapdragon S26 |
  | 3.2.40.5 | 324005500 | `.dla` | MediaTek |

  Galaxy Store answers "not compatible (9908)" on the S23, and Samsung's stub-download service refuses
  the package.
- **Possible partial route (untested):** a build whose manifest lists `CallScreeningResponse` would pass
  InCallUI's check. The LLM-written replies and summary would then fail, because the V81 models can't run
  on V73. Whether the greeting and transcription still work without them is unknown.
