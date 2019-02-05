.DEFAULT_GOAL := help
.PHONY: clean-lib clean
.PHONY: build-deps firmware-deps bootloader bootloader-mem-protect
.PHONY: firmware sign full-firmware-mem-protect full-firmware
.PHONY: emulator run-emulator st-flash

UNAME_S ?= $(shell uname -s)

install-linters-Darwin:
	brew install yamllint

install-linters-Linux:
	pip install --user yamllint

install-linters: install-linters-$(UNAME_S) ## Install code quality checking tools

lint: ## Check code quality
	yamllint -d relaxed .travis.yml

clean-lib: ## Delete all files generated by tiny-firmware library dependencies
	make -C tiny-firmware/vendor/libopencm3/ clean

clean: ## Delete all files generated by build
	make -C skycoin-api/ clean
	make -C tiny-firmware/bootloader/ clean
	make -C tiny-firmware/ clean
	make -C tiny-firmware/emulator/ clean
	make -C tiny-firmware/protob/ clean
	rm -f emulator.img emulator
	rm -f tiny-firmware/bootloader/combine/bl.bin
	rm -f tiny-firmware/bootloader/combine/fw.bin
	rm -f tiny-firmware/bootloader/combine/combined.bin
	rm -f tiny-firmware/bootloader/libskycoin-crypto.so
	rm -f bootloader-memory-protected.bin  bootloader-no-memory-protect.bin  full-firmware-no-mem-protect.bin full-firmware-memory-protected.bin

build-deps: ## Build common dependencies (protob, nanopb)
	make -C tiny-firmware/vendor/nanopb/generator/proto/
	make -C tiny-firmware/protob/

firmware-deps: build-deps ## Build firmware dependencies
	make -C tiny-firmware/vendor/libopencm3/

bootloader: firmware-deps ## Build bootloader (RDP level 0)
	rm -f tiny-firmware/memory.o tiny-firmware/gen/bitmaps.o # Force rebuild of these two files
	SIGNATURE_PROTECT=1 REVERSE_BUTTONS=1 make -C tiny-firmware/bootloader/ align
	mv tiny-firmware/bootloader/bootloader.bin bootloader-no-memory-protect.bin

bootloader-mem-protect: firmware-deps ## Build bootloader (RDP level 2)
	rm -f tiny-firmware/memory.o tiny-firmware/gen/bitmaps.o # Force rebuild of these two files
	MEMORY_PROTECT=1 SIGNATURE_PROTECT=1 REVERSE_BUTTONS=1 make -C tiny-firmware/bootloader/ align
	mv tiny-firmware/bootloader/bootloader.bin bootloader-memory-protected.bin

firmware: tiny-firmware/skycoin.bin ## Build wallet firmware

build-libc: tiny-firmware/bootloader/libskycoin-crypto.so ## Build the Skycoin cipher library for firmware

tiny-firmware/bootloader/libskycoin-crypto.so:
	make -C skycoin-api clean
	make -C skycoin-api libskycoin-crypto.so
	cp skycoin-api/libskycoin-crypto.so tiny-firmware/bootloader/
	make -C skycoin-api clean

tiny-firmware/skycoin.bin: firmware-deps
	rm -f tiny-firmware/memory.o tiny-firmware/gen/bitmaps.o # Force rebuild of these two files
	REVERSE_BUTTONS=1 make -C tiny-firmware/ sign

sign: tiny-firmware/bootloader/libskycoin-crypto.so tiny-firmware/skycoin.bin ## Sign wallet firmware
	tiny-firmware/bootloader/firmware_sign.py -s -f tiny-firmware/skycoin.bin

full-firmware-mem-protect: bootloader-mem-protect firmware ## Build full firmware (RDP level 2)
	cp bootloader-memory-protected.bin tiny-firmware/bootloader/combine/bl.bin
	cp tiny-firmware/skycoin.bin tiny-firmware/bootloader/combine/fw.bin
	cd tiny-firmware/bootloader/combine/ ; /usr/bin/python prepare.py
	mv tiny-firmware/bootloader/combine/combined.bin full-firmware-memory-protected.bin

full-firmware: bootloader firmware ## Build full firmware (RDP level 0)
	cp bootloader-no-memory-protect.bin tiny-firmware/bootloader/combine/bl.bin
	cp tiny-firmware/skycoin.bin tiny-firmware/bootloader/combine/fw.bin
	cd tiny-firmware/bootloader/combine/ ; /usr/bin/python prepare.py
	mv tiny-firmware/bootloader/combine/combined.bin full-firmware-no-mem-protect.bin

emulator: build-deps ## Build emulator
	EMULATOR=1 make -C tiny-firmware/emulator/
	EMULATOR=1 make -C tiny-firmware/
	mv tiny-firmware/skycoin-emulator emulator

run-emulator: emulator ## Run wallet emulator
	./emulator

test: build-deps
	EMULATOR=1 make -C tiny-firmware/emulator/
	EMULATOR=1 make -C tiny-firmware/ test

st-flash: ## Deploy (flash) firmware on physical wallet
	cd tiny-firmware/bootloader/combine/; st-flash write combined.bin 0x08000000

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
