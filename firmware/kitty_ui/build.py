#!/usr/bin/env python3
"""Build 64 KiB RV32IM presentation RAM. Book data is never compiled in."""
from pathlib import Path
import os
import shutil
import struct
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
TOOL_DIR = Path("/tools/Xilinx/2026.1/gnu/riscv/lin/bin")


def tool(name):
    candidate = os.environ.get("RISCV_TOOL_PREFIX", "riscv64-unknown-elf-") + name
    return shutil.which(candidate) or str(TOOL_DIR / candidate)


def main():
    with tempfile.TemporaryDirectory(prefix="fpga-kitty-ui-") as tmp:
        elf = Path(tmp) / "ui.elf"
        binary = Path(tmp) / "ui.bin"
        subprocess.run([
            tool("gcc"), "-march=rv32im", "-mabi=ilp32", "-Os", "-ffreestanding",
            "-fno-builtin", "-fno-stack-protector", "-nostdlib", "-nostartfiles",
            "-Wl,--build-id=none", f"-Wl,-T{HERE / 'link.ld'}",
            str(HERE / "start.s"), str(HERE / "main.c"), "-lgcc", "-o", str(elf),
        ], check=True)
        subprocess.run([tool("objcopy"), "-O", "binary", str(elf), str(binary)], check=True)
        code = binary.read_bytes()
        if len(code) > 56 * 1024:
            raise ValueError(f"Presentation firmware too large: {len(code)} bytes")
        data = code.ljust(65536, b"\0")
        (HERE / "kitty_ui.hex").write_text("".join(
            f"{word:08x}\n" for (word,) in struct.iter_unpack("<I", data)))
        print(f"Built {len(code)} bytes of presentation firmware")


if __name__ == "__main__":
    main()
