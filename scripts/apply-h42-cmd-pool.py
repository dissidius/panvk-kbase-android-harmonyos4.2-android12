#!/usr/bin/env python3
"""Fix outdated CSF auto-trim pool inventory in the experimental universal build.

The pinned Mesa panvk_cmd_pool struct has 5 BO pools. The 226/231 patches
carry an obsolete sixth geometry-shader (gs_bo_pool) reference. On a tree
with an actual gs_bo_pool this compatibility change must do nothing.
Fail closed if the source layout differs.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: apply-h42-cmd-pool.py MESA_ROOT")
root = Path(sys.argv[1])
source = root / "src/panfrost/vulkan/panvk_cmd_pool.c"
header = root / "src/panfrost/vulkan/panvk_cmd_pool.h"
c, h = source.read_text(), header.read_text()
if "gs_bo_pool" in h:
    print("H42: gs_bo_pool exists in header; no compatibility edit needed")
    raise SystemExit(0)

replacements = [
    ("#define PANVK_CMD_POOL_BO_POOLS 6", "#define PANVK_CMD_POOL_BO_POOLS 5"),
    ("""   out[3] = &pool->gs_bo_pool;
   out[4] = &pool->tls_bo_pool;
   out[5] = &pool->tls_big_bo_pool;""",
     """   out[3] = &pool->tls_bo_pool;
   out[4] = &pool->tls_big_bo_pool;"""),
]
for old, new in replacements:
    if c.count(old) != 1:
        raise SystemExit("H42 cmd pool mismatch: expected exactly one " + repr(old[:60]))
    c = c.replace(old, new, 1)

old, new = "uint32_t cur[6], prev[6];", "uint32_t cur[5], prev[5];"
if h.count(old) != 1:
    raise SystemExit("H42 cmd pool mismatch: expected the 231 patch hysteresis array")
h = h.replace(old, new, 1)
source.write_text(c)
header.write_text(h)
print("H42: removed obsolete GS slab from 226/231, kept 5 valid BO pools")
