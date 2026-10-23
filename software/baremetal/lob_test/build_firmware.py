#!/usr/bin/env python3
"""Build the 4-KiB RV32IM monitor ROM from its assembly source."""

from pathlib import Path
import os
import shutil
import struct
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
TOOL_DIR = Path("/tools/Xilinx/2026.1/gnu/riscv/lin/bin")


def tool(name: str) -> str:
    prefix = os.environ.get("RISCV_TOOL_PREFIX", "riscv64-unknown-elf-")
    executable = prefix + name
    found = shutil.which(executable)
    if found:
        return found
    fallback = TOOL_DIR / executable
    if fallback.is_file():
        return str(fallback)
    raise FileNotFoundError(f"RISC-V tool not found: {executable}")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fpga-lob-fw-") as temp:
        elf = Path(temp) / "monitor.elf"
        binary = Path(temp) / "monitor.bin"
        subprocess.run(
            [tool("gcc"), "-march=rv32im", "-mabi=ilp32", "-nostdlib",
             "-Wl,--build-id=none", "-Wl,-Ttext=0", "-Wl,-e,_start",
             str(HERE / "firmware_monitor.s"), "-o", str(elf)],
            check=True,
        )
        subprocess.run(
            [tool("objcopy"), "-O", "binary", "-j", ".text",
             str(elf), str(binary)],
            check=True,
        )
        code = binary.read_bytes()
        if len(code) > 4096 or len(code) % 4:
            raise ValueError(f"Firmware must fit 4 KiB and be word aligned: {len(code)} bytes")
        words = code.ljust(4096, b"\0")
        hex_text = "".join(f"{word:08x}\n" for (word,) in struct.iter_unpack("<I", words))
        (HERE / "imem.hex").write_text(hex_text)
        shutil.copyfile(elf, HERE / "firmware_lob_test.elf")
        shutil.copyfile(binary, HERE / "imem.bin")
        print(f"Built {len(code)} bytes of RV32IM monitor firmware")


if __name__ == "__main__":
    main()
