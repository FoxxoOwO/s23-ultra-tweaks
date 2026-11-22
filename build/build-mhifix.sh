# Build mhifix.ko against the S23 vendor tree.
export PATH=/clang/bin:$PATH
K=/work/s23/kernel_platform/msm-kernel; O=/work/out23v; M=/work/mhifix
rm -rf $M; cp -a /repo/src/mhifix $M
make -C $K CC=/repo/build/cc16wrap.sh O=$O ARCH=arm64 LLVM=1 LLVM_IAS=1 HOSTCC=gcc HOSTCXX=g++ M=$M modules \
  KCFLAGS="-D__ANDROID_COMMON_KERNEL__" KBUILD_EXTRA_SYMBOLS="/repo/build/Module.symvers.base /repo/build/extra.symvers" > /out/mhifix.log 2>&1
echo "make exit=$?"; cp $M/mhifix.ko /out/mhifix.ko
