#!/usr/bin/env bash
# Shared setup for experimental Mali PanVK Android CI.
# Reuses the runner's NDK, cached apt lists/.deb files, Python venv and ccache.
# Usage: bash ci/h42-setup.sh [path-to-repository-with-ci-directory]
set -euo pipefail

SOURCE_ROOT="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
cd "$WORKSPACE"
mkdir -p .ci-apt/lists/partial .ci-apt/archives/partial .ci-ccache
sudo chown -R "$(id -u):$(id -g)" .ci-apt
export DEBIAN_FRONTEND=noninteractive
SOURCES=/etc/apt/sources.list.d/ubuntu.sources
if [ -f "$SOURCES" ]; then
  sudo sed -i \
    -e 's|mirror+file:/etc/apt/apt-mirrors.txt|https://mirrors.mit.edu/ubuntu|g' \
    -e 's|http://azure.archive.ubuntu.com/ubuntu|https://mirrors.mit.edu/ubuntu|g' \
    -e 's|http://archive.ubuntu.com/ubuntu|https://mirrors.mit.edu/ubuntu|g' \
    -e 's|http://security.ubuntu.com/ubuntu|https://mirrors.mit.edu/ubuntu|g' \
    -e 's|https://security.ubuntu.com/ubuntu|https://mirrors.mit.edu/ubuntu|g' \
    "$SOURCES"
fi

APT_OPTS=(
  -o "Dir::State::lists=$WORKSPACE/.ci-apt/lists"
  -o "Dir::Cache::archives=$WORKSPACE/.ci-apt/archives"
  -o "Acquire::Languages=none"
  -o "Acquire::Retries=0"
  -o "Acquire::http::Timeout=10"
  -o "Acquire::https::Timeout=10"
)
echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' |
  sudo tee /etc/apt/apt.conf.d/01h42-keep-debs >/dev/null
mapfile -t APT_PACKAGES < <(sed 's/[[:space:]]*#.*$//; /^[[:space:]]*$/d' "$SOURCE_ROOT/ci/h42-apt.txt")
NEED_PACKAGES=false
for p in "${APT_PACKAGES[@]}"; do
  if ! dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q '^install ok installed$'; then
    NEED_PACKAGES=true
    break
  fi
done
if [ "$NEED_PACKAGES" = true ]; then
  if ! sudo apt-cache "${APT_OPTS[@]}" policy build-essential |
       grep -qE 'Candidate: [^ (][^ ]*'; then
    echo "H42: no usable cached Ubuntu package index; fetching once"
    timeout 120s sudo apt-get "${APT_OPTS[@]}" \
      -o APT::Update::Error-Mode=any update
  else
    echo "H42: reusing cached Ubuntu package indexes"
  fi
  if ! sudo apt-cache "${APT_OPTS[@]}" policy build-essential |
       grep -qE 'Candidate: [^ (][^ ]*'; then
    echo "H42-APT: build-essential has no candidate even after apt update."
    dpkg --print-architecture
    sudo apt-cache "${APT_OPTS[@]}" policy build-essential || true
    find "$WORKSPACE/.ci-apt/lists" -maxdepth 1 -type f | head -n 20
    exit 2
  fi
  echo "H42: installing only missing host packages (using local .deb cache)"
  timeout 170s sudo apt-get "${APT_OPTS[@]}" install -y --no-install-recommends "${APT_PACKAGES[@]}"
else
  echo "H42: host dependencies already installed; skipping apt entirely"
fi

VENV="$WORKSPACE/.ci-venv"
if [ -x "$VENV/bin/meson" ] && "$VENV/bin/python3" -c 'import mako, yaml, packaging' 2>/dev/null; then
  echo "H42: using cached Meson/Python environment"
else
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --disable-pip-version-check -r "$SOURCE_ROOT/ci/h42-python.txt"
fi
echo "$VENV/bin" >> "${GITHUB_PATH:-/dev/null}"
echo "/usr/lib/llvm-18/bin" >> "${GITHUB_PATH:-/dev/null}"
export CCACHE_DIR="$WORKSPACE/.ci-ccache"
export CCACHE_BASEDIR="$WORKSPACE"
export CCACHE_COMPILERCHECK=content
export CCACHE_NOHASHDIR=true
if command -v ccache >/dev/null 2>&1; then
  ccache --max-size=600M
  ccache --show-stats
fi
{
  echo "CCACHE_DIR=$CCACHE_DIR"
  echo "CCACHE_BASEDIR=$CCACHE_BASEDIR"
  echo "CCACHE_COMPILERCHECK=content"
  echo "CCACHE_NOHASHDIR=true"
} >> "${GITHUB_ENV:-/dev/null}"

NDK_DIR="${ANDROID_HOME:-/usr/local/lib/android/sdk}/ndk/29.0.14206865"
if [ -x "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang" ]; then
  echo "H42: already installed NDK r29, skipping SDK download"
else
  echo "H42: NDK r29 missing; installing only this NDK"
  SDK_ROOT="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
  SDKMANAGER="$(find "$SDK_ROOT/cmdline-tools" -type f -name sdkmanager | sort -Vr | head -n 1)"
  test -x "$SDKMANAGER" || { echo "sdkmanager missing" >&2; exit 2; }
  timeout 180s "$SDKMANAGER" --sdk_root="$SDK_ROOT" --install 'ndk;29.0.14206865'
fi
test -x "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang"
echo "H42: host dependencies, Python, ccache and Android NDK ready"