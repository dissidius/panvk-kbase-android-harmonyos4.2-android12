#!/bin/sh
# fetch-mesa.sh — clone/fetch the exact pinned Mesa commit from sources.lock
# Usage: ./scripts/fetch-mesa.sh [--work work] [--checkout-only]
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${1:-$ROOT/work}"
MESA_DIR="$WORK/mesa"
REPO="$(python3 -c "import json;print(json.load(open('$ROOT/sources.lock'))['mesaRepo'])")"
COMMIT="$(python3 -c "import json;print(json.load(open('$ROOT/sources.lock'))['mesaCommit'])")"
mkdir -p "$WORK"
if [ ! -d "$MESA_DIR/.git" ]; then
  # Initialize empty rather than clone an entire moving Mesa branch.
  mkdir -p "$MESA_DIR"
  git -C "$MESA_DIR" init -q
  git -C "$MESA_DIR" remote add origin "$REPO"
fi
if ! git -C "$MESA_DIR" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
  echo "H42: Mesa pinned commit not cached; fetching exactly $COMMIT"
  timeout 150s git -C "$MESA_DIR" fetch --no-tags --depth 1 origin "$COMMIT"
else
  echo "H42: reusing pinned Mesa source from Actions cache (offline)"
fi
git -C "$MESA_DIR" checkout --detach --force "$COMMIT"
git -C "$MESA_DIR" reset --hard "$COMMIT"
# Prior jobs leave generated and copied patch files; never reuse these accidentally.
git -C "$MESA_DIR" clean -ffdx
git -C "$MESA_DIR" rev-parse HEAD
echo "OK mesa=$COMMIT dir=$MESA_DIR"
