# Recreate Samsung's vendor-module kernel config for S918WVLU8GZIF (gki_defconfig + kalama_GKI +
# lego + kalama_sec) in /work/out23v and run modules_prepare. Runs inside the build container.
set -e
export PATH=/clang/bin:$PATH
K=/work/s23/kernel_platform/msm-kernel; O=/work/out23v
MK="make -C $K O=$O ARCH=arm64 LLVM=1 LLVM_IAS=1 HOSTCC=gcc HOSTCXX=g++"
cd $K; ls lego.config >/dev/null
rm -rf $O; mkdir -p $O
KCONFIG_CONFIG=$O/.config scripts/kconfig/merge_config.sh -m -r -O $O arch/arm64/configs/gki_defconfig \
  arch/arm64/configs/vendor/kalama_GKI.config lego.config arch/arm64/configs/vendor/kalama_sec_defconfig >/dev/null
$MK olddefconfig >/dev/null
scripts/config --file $O/.config --disable TRIM_UNUSED_KSYMS --set-str UNUSED_KSYMS_WHITELIST ""
$MK olddefconfig >/dev/null
$MK -j$(nproc) modules_prepare >/dev/null 2>&1
echo '#define UTS_RELEASE "5.15.197-android13-8-34343818-abS918WVLU8GZIF"' > $O/include/generated/utsrelease.h
echo "vendor tree ready in $O"
