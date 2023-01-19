OS = $(shell uname -s)
ARCH := x86
BUILD_DIR := build
BUILD_ABS_DIR := $(CURDIR)/$(BUILD_DIR)
VBOX_VM_NAME := bare-metal-gophers

kernel_target :=$(BUILD_DIR)/kernel-$(ARCH).bin
iso_target := $(BUILD_DIR)/kernel-$(ARCH).iso

ifeq ($(OS), Linux)
export SHELL := /bin/bash -o pipefail

LD := ld
AS := nasm

GOOS := linux
GOARCH := 386

LD_FLAGS := -n -melf_i386 -T arch/$(ARCH)/script/linker.ld -static --no-ld-generated-unwind-info
AS_FLAGS := -g -f elf32 -F dwarf -I arch/$(ARCH)/asm/

asm_src_files := $(wildcard arch/$(ARCH)/asm/*.s)
asm_obj_files := $(patsubst arch/$(ARCH)/asm/%.s, $(BUILD_DIR)/arch/$(ARCH)/asm/%.o, $(asm_src_files))

.PHONY: kernel iso clean

kernel: $(kernel_target)

$(kernel_target): $(asm_obj_files) go.o
	@echo "[$(LD)] linking kernel-$(ARCH).bin"
	@$(LD) $(LD_FLAGS) -o $(kernel_target) $(asm_obj_files) $(BUILD_DIR)/go.o

go.o:
	@mkdir -p $(BUILD_DIR)

	@echo "[go] compiling go sources into a standalone .o file"
	@GOARCH=386 GOOS=linux go build -n 2>&1 | sed \
	    -e "1s|^|set -e\n|" \
	    -e "1s|^|export GOOS=linux\n|" \
	    -e "1s|^|export GOARCH=386\n|" \
	    -e "1s|^|WORK='$(BUILD_ABS_DIR)'\n|" \
	    -e "1s|^|alias pack='go tool pack'\n|" \
	    -e "/^mv/d" \
	    -e "s|-extld|-tmpdir='$(BUILD_ABS_DIR)' -linkmode=external -extldflags='-nostdlib' -extld|g" \
	    | sh 2>&1 | sed -e "s/^/  | /g"

	@# build/go.o is a elf32 object file but all Go symbols are unexported. Our
	@# asm entrypoint code needs to know the address to 'main.main' and 'runtime.g0'
	@# so we use objcopy to globalize them
	@echo "[objcopy] globalizing symbols {runtime.g0, main.main} in go.o"
	@objcopy \
		--globalize-symbol runtime.g0 \
		--globalize-symbol main.main \
		 $(BUILD_DIR)/go.o $(BUILD_DIR)/go.o

$(BUILD_DIR)/arch/$(ARCH)/asm/%.o: arch/$(ARCH)/asm/%.s
	@mkdir -p $(shell dirname $@)
	@echo "[$(AS)] $<"
	@$(AS) $(AS_FLAGS) $< -o $@

iso: $(iso_target)

$(iso_target): $(kernel_target)
	@echo "[grub] building ISO kernel-$(ARCH).iso"

	@mkdir -p $(BUILD_DIR)/isofiles/boot/grub
	@cp $(kernel_target) $(BUILD_DIR)/isofiles/boot/kernel.bin
	@cp arch/$(ARCH)/script/grub.cfg $(BUILD_DIR)/isofiles/boot/grub
	@grub-mkrescue -o $(iso_target) $(BUILD_DIR)/isofiles 2>&1 | sed -e "s/^/  | /g"
	@rm -r $(BUILD_DIR)/isofiles

else
VAGRANT_SRC_FOLDER = /home/vagrant/bare-metal-gophers

.PHONY: kernel iso vagrant-up vagrant-down vagrant-ssh run gdb clean

kernel:
	vagrant ssh -c 'cd $(VAGRANT_SRC_FOLDER); make kernel'

iso:
	vagrant ssh -c 'cd $(VAGRANT_SRC_FOLDER); make iso'

run-qemu: iso
	qemu-system-i386 -cdrom $(iso_target)

run-vbox: iso
	VBoxManage createvm --name $(VBOX_VM_NAME) --ostype "Linux_64" --register || true
	VBoxManage storagectl $(VBOX_VM_NAME) --name "IDE Controller" --add ide || true
	VBoxManage storageattach $(VBOX_VM_NAME) --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive \
		--medium $(iso_target) || true
	VBoxManage setextradata $(VBOX_VM_NAME) GUI/ScaleFactor 2
	VBoxManage startvm $(VBOX_VM_NAME)

gdb: iso
	qemu-system-i386 -s -S -cdrom $(iso_target) &
	sleep 1
	gdb \
	    -ex "add-auto-load-safe-path $(pwd)" \
	    -ex "file $(kernel_target)" \
	    -ex "set disassembly-flavor intel" \
	    -ex 'set arch i386:intel' \
	    -ex 'target remote localhost:1234' \
	    -ex 'layout asm' \
	    -ex 'b _rt0_entry' \
	    -ex 'continue' \
	    -ex 'disass'
	@killall qemu-system-i386 || true
endif

clean:
	@test -d $(BUILD_DIR) && rm -rf $(BUILD_DIR) || true
