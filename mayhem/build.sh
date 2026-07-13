#!/usr/bin/env bash
#
# mayhem/build.sh — build the gum-graft libFuzzer harness (instrumented) AND the upstream
# GLib test suite (normal flags). Additive: upstream sources are untouched; everything
# new lives under mayhem/. Idempotent + air-gapped: meson setup is guarded so an offline
# re-run on the already-built tree is a no-op incremental ninja (subprojects are already
# vendored from the first, networked build).
#
# The historical Mayhem target was the raw gum-graft CLI (a file-input Mach-O grafter).
# Under Mayhem it produced ZERO coverage edges (no in-process feedback on a native CLI),
# so per the porting harness policy we drive the SAME code path in-process via a libFuzzer
# harness (mayhem/gumgraft_fuzz.c) over sanitizer-coverage-instrumented libfrida-gum. The
# Mayhem target NAME stays `gum-graft` so run history isn't orphaned.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"

# gum-graft parses attacker-controlled Mach-O with GLib/GObject underneath. GObject's
# type system legitimately calls class/instance init through generic GCallback pointers
# and reads packed Mach-O structs at natural-but-unaligned offsets — both are benign and
# would otherwise flood UBSan with non-defects that halt the run. Relax exactly those four
# checks; ASan (heap/stack/UAF) and the rest of UBSan stay fully halting.
RELAX="-fno-sanitize=function,alignment,nonnull-attribute,pointer-overflow"
# -fsanitize=fuzzer-no-link instruments EVERY translation unit (libfrida-gum + its static
# deps) with SanitizerCoverage so the in-process harness gets edge feedback; the libFuzzer
# driver/runtime is added only at the final harness link (LIB_FUZZING_ENGINE).
COV="-fsanitize=fuzzer-no-link"
FUZZ_CFLAGS="$SANITIZER_FLAGS $RELAX $DEBUG_FLAGS $COV"

: "${FRIDA_VERSION:=17.0.0-mayhem}"

cd "$SRC"

# 1) Instrumented build of libfrida-gum + the (upstream) gum-graft tool. We enable the
#    graft tool purely so meson emits its compile/link commands, which we reuse verbatim
#    (same include dirs + static-archive group) to build our harness — no upstream edits.
if [ ! -d build ]; then
  CC="$CC" CXX="$CXX" \
  CFLAGS="$FUZZ_CFLAGS" CXXFLAGS="$FUZZ_CFLAGS" LDFLAGS="$SANITIZER_FLAGS $RELAX" \
  meson setup build \
    --default-library=static \
    -Dfrida_version="$FRIDA_VERSION" \
    -Dgraft_tool=enabled -Dtests=disabled -Dgumpp=disabled -Dgumjs=disabled \
    -Ddiet=false
fi
ninja -C build tools/gum-graft

# 2) Compile the harness + sanitizer-defaults objects, reusing the EXACT compile command
#    meson generated for gumgraft.c (all -I flags, the sanitizer/coverage/debug flags).
CC_CMD="$(ninja -C build -t commands tools/gum-graft.p/gumgraft.c.o | tail -1)"
compile_like_gumgraft () {  # <src> <out>
  ( cd build && eval "$(printf '%s' "$CC_CMD" \
      | sed -E "s#-c[[:space:]]+[^[:space:]]*gumgraft\.c#-c $1#" \
      | sed -E "s#-o[[:space:]]+[^[:space:]]*gumgraft\.c\.o#-o $2#")" )
}
compile_like_gumgraft "$SRC/mayhem/gumgraft_fuzz.c" "$SRC/build/gumgraft_fuzz.o"
"$CC" $FUZZ_CFLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$SRC/build/standalone_main.o"

# 3) Relink gum-graft's captured final link command, swapping the CLI main object
#    (gumgraft.c.o) for our harness objects and retargeting the output. Twice:
#      - the libFuzzer target      /mayhem/gum-graft            (+ LIB_FUZZING_ENGINE)
#      - a standalone reproducer   /mayhem/gum-graft-standalone (run-once, no libFuzzer)
LINK_CMD="$(ninja -C build -t commands tools/gum-graft | tail -1)"
HARNESS_OBJS="$SRC/build/gumgraft_fuzz.o"
relink () {  # <out> <engine...>
  local out="$1"; shift
  ( cd build && eval "$(printf '%s' "$LINK_CMD" \
      | sed -E "s#[^[:space:]]*gumgraft\.c\.o#$HARNESS_OBJS#" \
      | sed -E "s#-o[[:space:]]+[^[:space:]]*tools/gum-graft#-o $out#") $*" )
}
relink /mayhem/gum-graft $LIB_FUZZING_ENGINE
relink /mayhem/gum-graft-standalone -fsanitize=fuzzer-no-link "$SRC/build/standalone_main.o"

# 4) Upstream test suite — INDEPENDENT build with the project's NORMAL flags (no sanitizer),
#    so mayhem/test.sh is an honest functional oracle. This is exactly `./configure ... && make`
#    at upstream defaults (tests=auto → enabled; gumpp/gumjs off — their tests are gated behind
#    optional bindings, V8 is unavailable offline). Produces build-tests/tests/gum-tests.
if [ ! -d build-tests ]; then
  CC="$CC" CXX="$CXX" \
  CFLAGS="$COVERAGE_FLAGS" CXXFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" \
  meson setup build-tests \
    --default-library=static \
    -Dfrida_version="$FRIDA_VERSION" \
    -Dtests=enabled -Dgraft_tool=disabled -Dgumpp=disabled -Dgumjs=disabled \
    -Ddiet=false
fi
ninja -C build-tests tests/gum-tests

echo "build.sh OK: gum-graft (libFuzzer) + gum-graft-standalone + gum-tests built"
