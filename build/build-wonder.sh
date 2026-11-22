# Build the S23-patched Google wonder.ko against the S23 vendor tree and the patched qcacld exports.
export PATH=/clang/bin:$PATH
K=/work/s23/kernel_platform/msm-kernel; O=/work/out23v; W=/work/wonder
rm -rf $W; cp -a /work/s24/vendor/qcom/opensource/wlan/wonder $W
cp /repo/src/wonder-patch/wonder_main.c $W/main.c; cp /repo/src/wonder-patch/wonder_mac80211.c $W/mac80211.c
make -C $K O=$O ARCH=arm64 LLVM=1 LLVM_IAS=1 HOSTCC=gcc HOSTCXX=g++ M=$W -j$(nproc) modules \
  KCFLAGS="-D__ANDROID_COMMON_KERNEL__ -I$W/include" \
  KBUILD_EXTRA_SYMBOLS="/repo/build/Module.symvers.base /repo/build/extra.symvers /work/b24/qcacld-3.0/Module.symvers" > /out/b7.log 2>&1
echo "make exit=$?"; grep -E "error|warning:|LD \[M\]|undefined" /out/b7.log | head -30
cp $W/wonder.ko /out/wonder.ko 2>/dev/null; strings $W/wonder.ko 2>/dev/null | grep -E "^vermagic="
