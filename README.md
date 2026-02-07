# TN9K-BE65C02

A port of Ben Eater’s 65C02 computer for the Tang Nano 9K FPGA, with enhancements for modern usability and performance.

## Features

- Runs at ~1.929 MHz (configurable in smon6502/config.asm)
- Quality-of-life improvements: uses 6551 ACIA for faster serial communication (no 65C51N bug)
- Modular peripherals: VIA 6522 (GPIO/timer/interrupt), UART, RAM, ROM, LCD (I2C)
- Includes classic monitor programs (SMON, WOZMON) and demo software

## Included Modules

- **VIA 6522**: Verilog implementation for GPIO/timer/interrupts ([6522/README.md](6522/README.md))
- **6551 ACIA**: Fast/flexible serial interface ([6551-ACIA/README.md](6551-ACIA/README.md))
- **SMON Monitor**: Direct assembler and memory monitor ([smon6502/README.md](smon6502/README.md))
- **I2C LCD Driver**: 16x2 LCD via PCF8574 ([docs/1602-I2C.md](docs/1602-I2C.md))
- **UART**: W65C51N-compatible module ([docs/UART.md](docs/UART.md))

## Build Instructions

1. Clone with submodules:
	```
	git clone --recursive https://github.com/ellisgl/TN9K-BE65C02.git
	```
2. Build with oss-cad-suite tools:
	```
	make all
	```
	 - `make smon` or `make wozmon` to quickly build and copy the respective ROMs.
	 - To synthesize, place, generate bitstream, and load onto the FPGA after building a ROM, run:
		 ```
		 make synth pnr fs load
		 ```

## Customization

- Update `CPU_CLOCK_RATE` in `smon6502/config.asm` to match your desired clock frequency.
- ROM source can be changed via the `rom` variable in the Makefile.

## Documentation

- See module READMEs and docs for hardware details, register maps, and usage examples.
