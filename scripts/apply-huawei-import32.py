#!/usr/bin/env python3
"""Apply Huawei JM 32-byte MEM_IMPORT fallback after the upstream MTK 40-byte patch.
Only the experimental H42 branch calls this. Abort if the pinned Mesa layout changes.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: apply-huawei-import32.py MESA_KBASE_KMOD_C")
path = Path(sys.argv[1])
src = path.read_text()

before = """   if (p_atomic_read(&import_layout) != 2) {
      ret = ioctl(dev->fd, KBASE_IOCTL_MEM_IMPORT, &req);"""
after = """   if (p_atomic_read(&import_layout) != 2 &&
       p_atomic_read(&import_layout) != 3) {
      ret = ioctl(dev->fd, KBASE_IOCTL_MEM_IMPORT, &req);"""
if src.count(before) != 1:
    raise SystemExit("H42-PATCH-FAIL: expected one 24-byte MTK compatibility section")
src = src.replace(before, after, 1)

needle = """   if (ret && (p_atomic_read(&import_layout) == 2 || errno == ENOTTY)) {"""
if src.count(needle) != 1:
    raise SystemExit("H42-PATCH-FAIL: expected one MTK 40-byte retry section")

fallback = """   /*
    * HarmonyOS 4.2 Kirin 990 (Bifrost JM, kernel uAPI 11.38) requires a
    * 32-byte MEM_IMPORT ioctl. Preserve the preceding standard 24-byte
    * attempt and the following MTK 40-byte fallback for CSF devices.
    * Layout 3 is cached per process for repeated Huawei JM imports.
    */
   if (ret && !kbase_dev->is_csf &&
       (p_atomic_read(&import_layout) == 3 || errno == ENOTTY)) {
      union {
         struct {
            uint64_t flags;
            uint64_t phandle;
            uint32_t type;
            uint32_t padding;
            uint64_t reserved;
         } in;
         struct {
            uint64_t flags;
            uint64_t gpu_va;
            uint64_t va_pages;
            uint64_t reserved;
         } out;
      } huawei = {0};
      static_assert(sizeof(huawei) == 32, "Huawei JM import ioctl size");
      huawei.in.flags = req.in.flags;
      huawei.in.phandle = req.in.phandle;
      huawei.in.type = req.in.type;
      ret = ioctl(dev->fd,
                  _IOWR(KBASE_IOCTL_TYPE, 22, __typeof__(huawei)), &huawei);
      if (!ret) {
         req.out.flags = huawei.out.flags;
         req.out.gpu_va = huawei.out.gpu_va;
         req.out.va_pages = huawei.out.va_pages;
         if (p_atomic_cmpxchg(&import_layout, 0, 3) == 0)
            mesa_logi("kbase: mem_import via Huawei JM layout (32 bytes)");
      }
   }

"""
src = src.replace(needle, fallback + needle, 1)
path.write_text(src)
print("H42: appended Huawei JM 32-byte fallback after standard/MTK base patch")
