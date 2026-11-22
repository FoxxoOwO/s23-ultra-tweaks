# Build bwfix.ko against the S23 vendor tree (clang 14 + clang-16 strict CFI type check).
export PATH=/clang/bin:$PATH
K=/work/s23/kernel_platform/msm-kernel; O=/work/out23v; M=/work/bwfix
rm -rf $M; cp -a /repo/src/bwfix $M; rm -f /out/cfi_strict.log
make -C $K CC=/repo/build/cc16wrap.sh O=$O ARCH=arm64 LLVM=1 LLVM_IAS=1 HOSTCC=gcc HOSTCXX=g++ M=$M modules \
  KCFLAGS="-D__ANDROID_COMMON_KERNEL__" KBUILD_EXTRA_SYMBOLS="/repo/build/Module.symvers.base /repo/build/extra.symvers" > /out/b9.log 2>&1
echo "make exit=$?"; grep -E "error|warning:|undefined" /out/b9.log | head
echo "cfi strict hits:"; grep -E "warning:" /out/cfi_strict.log | grep -v "sock.h\|android_dst_ops" | head
cp $M/bwfix.ko /out/bwfix.ko && /clang/bin/llvm-strip --strip-debug /out/bwfix.ko; strings /out/bwfix.ko | grep vermagic
