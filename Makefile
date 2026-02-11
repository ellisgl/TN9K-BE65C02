BOARD=tangnano9k
FAMILY=GW1N-9C
DEVICE=GW1NR-LV9QN88PC6/I5

# Files listed in the lushay JSON (computed at make parse time)
INCLUDED_FILES := $(shell jq -r '.includedFiles | join(" ")' TN9K-BE65C02.lushay.json)

# Default ROM source (can be overridden on the `make` command-line)
rom ?= src/eater.s

# yosys -p "read_verilog $(jq -r '.includedFiles | join(" ")' your_file.json); synth_gowin -top top -json TN9K-BE65C02.json"

clean:
	- rm -f rtl/build/*.mem rtl/build/*.bin rtl/build/*.json rtl/build/*.fs

# Compile rom
rom:
	@echo Using ROM: $(rom)
	tools/vasm6502_oldstyle -Fbin -dotdir -c02 -o rtl/build/eater.bin $(rom)
	python tools/gen_mem.py rtl/build/eater.bin rtl/build/eater.mem 32768

# Quick targets for specific ROMs
wozmon:
	$(MAKE) rom rom=src/wozmon.s

brosloader:
	$(MAKE) rom rom=6502brosloader/brosloader.s

i2c1602:
	$(MAKE) rom rom=src/1602-I2C-demo.s

synth:
	yosys -p "read_verilog $(INCLUDED_FILES); synth_gowin -top top -json rtl/build/TN9K-BE65C02.json"

pnr:
	nextpnr-himbaechel --json rtl/build/TN9K-BE65C02.json --freq 27 --write rtl/build/TN9K-BE65C02_pnr.json --device ${DEVICE} --vopt family=${FAMILY} --vopt cst=${BOARD}.cst

fs:
	gowin_pack -d ${FAMILY} -o rtl/build/TN9K-BE65C02.fs rtl/build/TN9K-BE65C02_pnr.json

load:
	openFPGALoader -b ${BOARD} rtl/build/TN9K-BE65C02.fs -f

all: rom synth pnr fs load

.PHONY: clean all
