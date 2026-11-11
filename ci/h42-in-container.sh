#!/usr/bin/env bash
# Invoke a compile command in the published reusable H42 host-tools image.
# Image contains LLVM/Meson/glslang/ccache; NDK r29 is mounted from runner.
# Use only after the image publish + verification workflow succeeds.
set -euo pipefail
: "${GITHUB_WORKSPACE:?This script runs inside GitHub Actions}"
IMAGE="${H42_BUILDER_IMAGE:-ghcr.io/dissidius/panvk-h42-builder:llvm18-v1}"
NDK="${ANDROID_HOME:-/usr/local/lib/android/sdk}/ndk/29.0.14206865"
test -x "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang" || {
  echo "H42: runner does not contain NDK r29; refusing container build" >&2
  exit 2
}
mkdir -p "$GITHUB_WORKSPACE/.ci-ccache" "$GITHUB_WORKSPACE/.ci-home"
if [ -n "${H42_GHCR_TOKEN:-}" ]; then
  printf '%s' "$H42_GHCR_TOKEN" | docker login ghcr.io -u "${GITHUB_ACTOR:-dissidius}" --password-stdin
fi
docker pull "$IMAGE"
exec docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$GITHUB_WORKSPACE:$GITHUB_WORKSPACE" \
  -v "$NDK:$NDK:ro" \
  -w "$GITHUB_WORKSPACE" \
  -e HOME="$GITHUB_WORKSPACE/.ci-home" \
  -e ANDROID_HOME="${ANDROID_HOME:-/usr/local/lib/android/sdk}" \
  -e CC=clang-18 -e CXX=clang++-18 -e LLVM_CONFIG=llvm-config-18 \
  -e CCACHE_DIR="$GITHUB_WORKSPACE/.ci-ccache" \
  -e CCACHE_BASEDIR="$GITHUB_WORKSPACE" \
  -e CCACHE_COMPILERCHECK=content \
  -e CCACHE_NOHASHDIR=true \
  "$IMAGE" "$@"
