BOARD=tangnano9k
FAMILY=GW1N-9C
DEVICE=GW1NR-LV9QN88PC6/I5

# Default ROM source (can be overridden on the `make` command-line)
rom ?= src/eater.s

# yosys -p "read_verilog $(jq -r '.includedFiles | join(" ")' your_file.json); synth_gowin -top top -json TN9k-BE65C02.json"

clean:
    rm /rtl/build/*.mem /rtl/build/*.bin /rtl/build/*.json /rtl/build/*.fs

# Compile rom 
rom:
    @echo Using ROM: $(rom)
    tools/vasm6502_oldstyle -Fbin -dotdir -o rtl/build/eater.bin $(rom)
	tools/gen_mem.py rtl/build/eater.bin rtl/build/eater.mem 32768

synth:
	yosys -p "read_verilog $(jq -r '.includedFiles | join(" ")' TN9K-BE65C02.lushay.json); synth_gowin -top top -json TN9K-BE65C02.json"

pnr: 
    nextpnr-himbaechel --json TN9K-BE65C02.json --freq 27 --write TN9K-BE65C02_pnr.json --device ${DEVICE} --vopt family=${FAMILY} --vopt cst=${BOARD}.cst

fs:
    gowin_pack -d ${FAMILY} -o TN9K-BE65C02.fs TN9K-BE65C02_pnr.json

load:
	openFPGALoader -b ${BOARD} TN9K-BE65C02.fs -f

all: rom synth pnr fs load

.PHONY: clean all

