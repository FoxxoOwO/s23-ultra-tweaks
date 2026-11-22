# Build the S24 qcacld-3.0 (Wondertap) as qca_cld3_kiwi_v2 against the S23 vendor kernel tree + S23 cnss2 headers.
export PATH=/clang/bin:$PATH
K=/work/s23/kernel_platform/msm-kernel; O=/work/out23v; B=/work/b24
if [ ! -d $B/qcacld-3.0 ]; then
  mkdir -p $B
  cp -a /work/s24/vendor/qcom/opensource/wlan/qcacld-3.0 /work/s24/vendor/qcom/opensource/wlan/qca-wifi-host-cmn /work/s24/vendor/qcom/opensource/wlan/fw-api $B/
fi
bash /repo/src/qcacld-patch/apply.sh; echo "nproc=$(nproc)"
make -C $K O=$O ARCH=arm64 LLVM=1 LLVM_IAS=1 HOSTCC=gcc HOSTCXX=g++ M=$B/qcacld-3.0 -j$(nproc) -k modules \
  WLAN_ROOT=$B/qcacld-3.0 MODNAME=kiwi_v2 CHIP_NAME=kiwi_v2 WLAN_CTRL_NAME=wlan \
  CONFIG_QCA_CLD_WLAN_PROFILE=pineapple_gki_kiwi-v2 CONFIG_QCA_CLD_WLAN=m CONFIG_QCA_WIFI_ISOC=0 CONFIG_QCA_WIFI_2_0=1 QCA_WIFI_FTM_NL80211=y \
  WLAN_PLATFORM_INC=/work/s23/vendor/qcom/opensource/wlan/platform/inc \
  DATA_IPA_INC=/work/s23/vendor/qcom/opensource/dataipa/drivers/platform/msm/include \
  KBUILD_EXTRA_SYMBOLS="/repo/build/Module.symvers.base /repo/build/extra.symvers" KCFLAGS="-D__ANDROID_COMMON_KERNEL__ -Wno-error=declaration-after-statement -include /work/b24/qcacld-3.0/core/pld/src/s23_cnss_compat.h -I/work/s24/vendor/qcom/opensource/wlan/wonder/include" > /out/b6.log 2>&1
echo "make exit=$?"
grep -cE "error:" /out/b6.log; cp $B/qcacld-3.0/kiwi_v2.ko /out/kiwi_v2.ko && /clang/bin/llvm-strip --strip-debug /out/kiwi_v2.ko
