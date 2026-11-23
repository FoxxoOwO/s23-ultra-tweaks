#!/bin/sh
# Builds aodbright.apk (static framework overlay, no code) into the folder given (default out/); device/files holds the copy the module ships. Needs the Android SDK build-tools and platform 37.
set -e; cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}; BT=$(ls -d $SDK/build-tools/* | sort -V | tail -1)
J=$(ls -d $SDK/platforms/android-*/android.jar | sort -V | tail -1); O=${1:-out}; mkdir -p $O
$BT/aapt2 compile --dir res -o $O/res.zip
$BT/aapt2 link -I $J --manifest AndroidManifest.xml -o $O/unsigned.apk $O/res.zip
$BT/zipalign -f -p 4 $O/unsigned.apk $O/aligned.apk
$BT/apksigner sign --ks ${KS:-$HOME/.android/debug.keystore} --ks-pass pass:${KSPASS:-android} --out $O/aodbright.apk $O/aligned.apk
rm -f $O/res.zip $O/unsigned.apk $O/aligned.apk $O/aodbright.apk.idsig; ls -l $O/aodbright.apk
