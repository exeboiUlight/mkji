#!/bin/sh
set -e
cd "$(dirname "$0")/../.."

if [ -x "./mkji_elf" ]; then
  MKJI=./mkji_elf
else
  MKJI=./mkji.exe
fi

"$MKJI" tests/features/main.mk -o tests/features/main.elf --target elf
chmod +x tests/features/main.elf
tests/features/main.elf
