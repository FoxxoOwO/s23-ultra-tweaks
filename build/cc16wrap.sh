#!/bin/sh
# Compiler wrapper: for each C compile, first run clang-16 -fsyntax-only with only the strict
# function-pointer type warnings (CFI-relevant), logging hits; then run the real S23 clang 14.
case " $* " in
  *" -c "*.c" "*|*" -c "*.c)
    src=""; for a in "$@"; do case $a in *.c) src=$a;; esac; done
    clang-16 "$@" -fsyntax-only -Wno-everything -Wno-unknown-warning-option \
      -Wincompatible-function-pointer-types-strict -Wincompatible-function-pointer-types \
      -Wcast-function-type-strict -Wno-error -o /dev/null 2>>/out/cfi_strict.log >/dev/null || echo "clang16-failed $src" >> /out/cfi_strict.log ;;
esac
exec /clang/bin/clang "$@"
