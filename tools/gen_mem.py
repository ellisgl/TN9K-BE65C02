#!/usr/bin/env python3
import sys
from pathlib import Path

# Usage: gen_mem.py <bin_path> <mem_path> <rom_size>

def main():
    if len(sys.argv) != 4:
        sys.exit("Usage: gen_mem.py <bin_path> <mem_path> <rom_size>")
    bin_path = Path(sys.argv[1])
    mem_path = Path(sys.argv[2])
    rom_size = int(sys.argv[3])

    rom = bin_path.read_bytes()
    if len(rom) > rom_size:
        sys.exit(f"Binary too large: {len(rom)} bytes (limit {rom_size})")

    padded = rom + bytes([0xFF]) * (rom_size - len(rom))
    mem_path.write_text('\n'.join(f"{b:02x}" for b in padded) + '\n')
    print(f"Wrote {mem_path} ({len(padded)} bytes, padded to {rom_size} lines)")

if __name__ == "__main__":
    main()
