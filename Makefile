.PHONY: all build test test-pe test-elf clean

MKJI_WIN = ./mkji.exe
MKJI_ELF = ./mkji_elf

all: build

build:
	$(MKJI_WIN) src/main.mk -o mkji.exe --target pe
	$(MKJI_WIN) src/main.mk -o mkji_self.exe --target pe

test: test-pe

test-pe:
	powershell -ExecutionPolicy Bypass -File tests/run_pe_tests.ps1

test-elf:
	sh tests/run_elf_tests.sh

clean:
	rm -f tests/*.exe tests/*.elf tests/*.out tests/bad_all.exe tests/bad_all.elf
