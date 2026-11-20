#!/bin/sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ -x "./mkji_elf" ]; then
  MKJI=./mkji_elf
else
  MKJI=./mkji.exe
fi

cases="examples/hello.mk examples/classes.mk tests/smoke.mk"

for src in $cases; do
  name=$(basename "$src" .mk)
  echo "=== $name (elf) ==="
  "$MKJI" "$src" -o "tests/$name.elf" --target elf
  chmod +x "tests/$name.elf"
  "tests/$name.elf"
done

echo "=== negative test (expect failure) ==="
if "$MKJI" tests/bad_all.mk -o tests/bad_all.elf --target elf >/tmp/mkji_bad.out 2>&1; then
  echo "expected compile to fail" >&2
  exit 1
fi
echo "negative test failed as expected"

echo "all ELF tests passed"
