#!/bin/sh
# Пересборка self-hosted компилятора mkji в Linux/WSL (ELF64).
# Запускать из корня проекта: sh build.sh
set -e
cd "$(dirname "$0")"

MKJI=./mkji_elf
if [ ! -x "$MKJI" ]; then
  MKJI=./mkji.exe
fi

"$MKJI" src/main.mk -o mkji_elf --target elf
chmod +x mkji_elf

echo "mkji rebuilt successfully"
