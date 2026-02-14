# TN9K-BE65C02

A port of Ben Eater’s 65C02 computer for the Tang Nano 9K FPGA, with enhancements for modern usability and performance.

## Features

- Runs at ~1.929 MHz (You'll need to set this in smon6502/config.asm)
- Quality-of-life improvements: uses 6551 ACIA for faster serial communication (no 65C51N bug)
- Modular peripherals: VIA 6522 (GPIO/timer/interrupt), UART, RAM, ROM, LCD (I2C)
- Includes classic monitor programs (SMON, WOZMON) and demo software

## Included Modules

- **VIA 6522**: Verilog implementation for GPIO/timer/interrupts ([6522/README.md](6522/README.md))
- **6551 ACIA**: Fast/flexible serial interface ([6551-ACIA/README.md](6551-ACIA/README.md))

- **I2C LCD Driver**: 16x2 LCD via PCF8574 ([docs/1602-I2C.md](docs/1602-I2C.md))

## Build Instructions

1. Clone with submodules:
	```
	git clone --recursive https://github.com/ellisgl/TN9K-BE65C02.git
	```
2. Build with oss-cad-suite tools:
	```
	make all
	```
	 - `make brosloadedr` or `make wozmon` to quickly build and copy the respective ROMs.
	 - To synthesize, place, generate bitstream, and load onto the FPGA after building a ROM, run:
		 ```
		 make synth pnr fs load
		 ```

## Customization

- Update `CPU_CLOCK_RATE` in `smon6502/config.asm` to match your desired clock frequency.
- ROM source can be changed via the `rom` variable in the Makefile.

## Documentation

- See module READMEs and docs for hardware details, register maps, and usage examples.

# SD Card Drivers for Tang Nano 9K

Complete SPI and SD card drivers for the 65C02 system using VIA6522 bit-banging.

## Files

- **spi_driver.s** - Low-level SPI communication driver
- **sd_driver.s** - High-level SD card driver (init, read, write blocks)
- **sd_test_driver.s** - Example program demonstrating usage

## Installation

1. Copy drivers to your include directory:
```bash
cp spi_driver.s ~/TN9K-BE65C02/src/inc/
cp sd_driver.s ~/TN9K-BE65C02/src/inc/
```

2. Include in your programs:
```assembly
.include "inc/spi_driver.s"
.include "inc/sd_driver.s"
```

## Hardware Configuration

**Port A Pin Mapping (VIA6522):**
- PA0 (Pin 38) = CS   (Chip Select)
- PA1 (Pin 37) = MOSI (Master Out Slave In)
- PA2 (Pin 36) = SCK  (Clock)
- PA3 (Pin 39) = MISO (Master In Slave Out)

These connect to the Tang Nano 9K's onboard microSD card slot.

## Usage

### Initialize SD Card

```assembly
JSR SD_Init
CMP #$00
BNE error       ; A = 0 on success, error code otherwise
```

### Read a Block (512 bytes)

```assembly
; Set destination buffer
LDA #$00
STA SD_PTR_LO   ; Buffer at $0200
LDA #$02
STA SD_PTR_HI

; Read block 0
LDX #$00        ; Block number low byte
LDY #$00        ; Block number high byte
JSR SD_ReadBlock

CMP #$00
BNE error
```

### Write a Block (512 bytes)

```assembly
; Set source buffer
LDA #$00
STA SD_PTR_LO   ; Buffer at $0400
LDA #$04
STA SD_PTR_HI

; Write to block 1
LDX #$01        ; Block number low byte
LDY #$00        ; Block number high byte
JSR SD_WriteBlock

CMP #$00
BNE error
```

## Zero Page Usage

The drivers use zero page locations $20-$23:

- **$20 (SD_TEMP)** - Temporary storage
- **$21 (SD_TEMP2)** - Temporary storage
- **$22 (SD_PTR_LO)** - Buffer pointer low byte
- **$23 (SD_PTR_HI)** - Buffer pointer high byte

You can change these by editing the drivers if these conflict with your program.

## Response Codes

### Success:
- `$00` = Operation successful

### Error Codes:
- `$01` = Card in idle state (during init, may be OK)
- `$FF` = Timeout / No response

### SD Card R1 Response Bits:
- Bit 0: Idle state
- Bit 1: Erase reset
- Bit 2: Illegal command
- Bit 3: CRC error
- Bit 4: Erase sequence error
- Bit 5: Address error
- Bit 6: Parameter error

## Performance

- **SPI Clock Speed:** ~1-10 kHz (depends on CPU speed)
- **Block Read Time:** ~5-10 seconds per 512-byte block
- **Block Write Time:** ~5-10 seconds per 512-byte block

Bit-banging SPI is slow but reliable. For higher performance, consider implementing an FPGA-based SPI controller.

## Limitations

- Only supports SDHC cards (block addressing)
- Fixed 512-byte block size
- No filesystem support (raw block access only)
- Single block operations only (no multi-block)
- CRC checking disabled

## Example Programs

### Test Program

```bash
cd ~/TN9K-BE65C02
cp sd_test_driver.s src/
make rom rom=src/sd_test_driver.s
make synth pnr fs load
```

**Expected output:**
```
Initializing...
Reading Block 0
```
Then shows first 6 bytes of block 0 in hex.

### Read Boot Sector

```assembly
; Read MBR/boot sector (block 0)
LDA #$00
STA SD_PTR_LO
LDA #$02
STA SD_PTR_HI

LDX #$00
LDY #$00
JSR SD_ReadBlock

; Check for boot signature (0x55 0xAA at offset 510-511)
LDA $03FE      ; Byte 510
CMP #$55
BNE not_bootable

LDA $03FF      ; Byte 511
CMP #$AA
BNE not_bootable
```

## Future Enhancements

Possible additions:
- FAT16/FAT32 filesystem support
- Multi-block read/write
- Directory listing
- File open/read/write/close
- Integration with ROM monitor
- DMA-style transfer routines

## Troubleshooting

### Card not initializing ($FF error)
- Check SD card is inserted
- Try different SD card (some old cards don't work)
- Verify pin connections in constraints file

### Card initializes but can't read ($FF on read)
- Card may not support block 0 read
- Try reading block 1 or higher
- Check card is not write-protected

### Wrong data read
- Verify SD_PTR_LO/HI point to valid RAM
- Check you're reading the correct block number
- Some cards have unusual block layouts

## API Reference

### SPI Driver Functions

| Function | Inputs | Outputs | Description |
|----------|--------|---------|-------------|
| `SPI_Init` | None | None | Initialize SPI interface |
| `SPI_CS_Assert` | None | None | Select device (CS low) |
| `SPI_CS_Deassert` | None | None | Deselect device (CS high) |
| `SPI_WriteByte` | A = byte | None | Send one byte |
| `SPI_ReadByte` | None | A = byte | Receive one byte |

### SD Driver Functions

| Function | Inputs | Outputs | Description |
|----------|--------|---------|-------------|
| `SD_Init` | None | A = status | Initialize SD card |
| `SD_ReadBlock` | X,Y = block#<br>SD_PTR = buffer | A = status | Read 512 bytes |
| `SD_WriteBlock` | X,Y = block#<br>SD_PTR = buffer | A = status | Write 512 bytes |

## License

Public domain / MIT - use as you wish!

## Credits

Based on SD card specifications and various 6502 SD card projects.
Designed for the Tang Nano 9K FPGA board with 65C02 CPU core.