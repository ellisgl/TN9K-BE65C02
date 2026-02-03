# W65C51N-Compatible UART for Tang Nano 9K

## Overview
This UART module provides W65C51N-compatible functionality for your 65C02 system. It includes:
- Full-duplex asynchronous serial communication
- Programmable baud rate generation
- Status and error detection (overrun, framing errors)
- Interrupt support
- Compatible register interface with W65C51N

## Register Map

| RS1 | RS0 | R/W | Register               | Address |
|-----|-----|-----|------------------------|---------|
| 0   | 0   | R   | RX Data Register       | 0x00    |
| 0   | 0   | W   | TX Data Register       | 0x00    |
| 0   | 1   | R   | Status Register        | 0x01    |
| 0   | 1   | W   | Programmed Reset       | 0x01    |
| 1   | 0   | R/W | Command Register       | 0x02    |
| 1   | 1   | R/W | Control Register       | 0x03    |

### Status Register (Read-only at offset 0x01)

| Bit | Name | Description                          |
|-----|------|--------------------------------------|
| 7   | IRQ  | Interrupt flag (1 = interrupt active)|
| 6   | DSR  | Data Set Ready (not implemented)     |
| 5   | DCD  | Data Carrier Detect (not impl.)      |
| 4   | TxE  | Transmitter Data Register Empty      |
| 3   | RxF  | Receiver Data Register Full          |
| 2   | OVR  | Overrun Error                        |
| 1   | FER  | Framing Error                        |
| 0   | PER  | Parity Error (not implemented)       |

### Command Register (R/W at offset 0x02)

| Bit   | Function                           |
|-------|------------------------------------|
| 7     | Parity mode (not implemented)      |
| 6-5   | Parity control (not implemented)   |
| 4     | Receiver echo mode (not impl.)     |
| 3-2   | TX interrupt control               |
|       | 00 = disabled                      |
|       | 01 = enabled on TxE                |
| 1     | RX interrupt enable                |
| 0     | Data Terminal Ready (not impl.)    |

### Control Register (R/W at offset 0x03)
Currently not fully implemented - reserved for future baud rate selection.

## Parameters

```verilog
parameter clk_freq_hz = 1_000_000  // System clock frequency in Hz
parameter baud_rate   = 9600       // Desired baud rate
parameter oversample  = 16         // Oversampling ratio (typically 16)
```

The baud rate divisor is automatically calculated as: `clk_freq_hz / (baud_rate * oversample)`

## Pin Connections

```verilog
input  wire        clk       // System clock
input  wire        rst       // Active-high reset
input  wire        rw        // Read/Write: 1=Read, 0=Write
input  wire        rs0       // Register select bit 0
input  wire        rs1       // Register select bit 1
input  wire        cs        // Chip select (active high)
input  wire [7:0]  data_in   // Data bus input
input  wire        rx        // Serial receive input
output wire [7:0]  data_out  // Data bus output
output wire        tx        // Serial transmit output
output wire        irq       // Interrupt request (active low)
```

## Usage Example

### Integration with 65C02 System

```verilog
module top_module (
    input  wire        clk_27mhz,    // Tang Nano 9K 27MHz clock
    input  wire        rst_n,         // Reset button (active low)
    input  wire        uart_rx,       // UART RX pin
    output wire        uart_tx,       // UART TX pin
    // ... other signals
);

    wire cpu_clk;
    wire [15:0] cpu_addr;
    wire [7:0] cpu_data_out;
    wire [7:0] cpu_data_in;
    wire cpu_rw;

    // UART chip select decode (e.g., at 0x7F00-0x7F03)
    wire uart_cs = (cpu_addr[15:2] == 14'h1FC0); // 0x7F00-0x7F03

    UART #(
        .clk_freq_hz(27_000_000),  // 27 MHz system clock
        .baud_rate(115200),         // 115200 baud
        .oversample(16)
    ) uart (
        .clk(clk_27mhz),
        .rst(~rst_n),
        .rw(cpu_rw),
        .rs0(cpu_addr[0]),
        .rs1(cpu_addr[1]),
        .cs(uart_cs),
        .data_in(cpu_data_out),
        .rx(uart_rx),
        .data_out(uart_data),
        .tx(uart_tx),
        .irq(uart_irq)
    );

    // ... CPU and other peripherals

endmodule
```

### 65C02 Assembly Example

```assembly
UART_BASE   = $5000
UART_DATA   = UART_BASE + $00
UART_STATUS = UART_BASE + $01
UART_CMD    = UART_BASE + $02
UART_CTRL   = UART_BASE + $03

; Initialize UART
init_uart:
    LDA #$00
    STA UART_STATUS    ; Programmed reset
    LDA #$02           ; Enable RX interrupts
    STA UART_CMD
    RTS

; Send a byte (blocking)
; Input: A = byte to send
uart_putc:
    PHA                ; Save byte
.wait:
    LDA UART_STATUS    ; Check status
    AND #$10           ; Test TxE bit
    BEQ .wait          ; Wait if not empty
    PLA                ; Restore byte
    STA UART_DATA      ; Send it
    RTS

; Receive a byte (blocking)
; Output: A = received byte
uart_getc:
    LDA UART_STATUS    ; Check status
    AND #$08           ; Test RxF bit
    BEQ uart_getc      ; Wait if no data
    LDA UART_DATA      ; Read byte (clears RxF)
    RTS

; Send a string
; Input: X,Y = pointer to null-terminated string (little endian)
uart_puts:
    STX $00
    STY $01
    LDY #$00
.loop:
    LDA ($00),Y
    BEQ .done
    JSR uart_putc
    INY
    BNE .loop
    INC $01
    JMP .loop
.done:
    RTS
```

## Features

### Implemented
- ✅ Full-duplex TX/RX
- ✅ Configurable baud rate
- ✅ 8-N-1 format (8 data bits, no parity, 1 stop bit)
- ✅ Status register with error flags
- ✅ Overrun detection
- ✅ Framing error detection
- ✅ Interrupt generation (RX and TX)
- ✅ RX input synchronization
- ✅ Programmed reset

### Not Implemented (can be added if needed)
- ❌ Parity generation/checking
- ❌ Hardware flow control (RTS/CTS)
- ❌ Configurable data bits (5/6/7/8)
- ❌ Configurable stop bits (1/1.5/2)
- ❌ DCD/DSR input signals
- ❌ Echo mode
- ❌ Break detection/transmission

## Timing Specifications

### At 27 MHz Clock, 115200 Baud
- Bit period: ~8.68 μs
- Character transmission time: ~86.8 μs (10 bits: start + 8 data + stop)
- Maximum throughput: ~11,520 bytes/second

### Recommended Baud Rates for 27 MHz Clock
- 9600 baud: Divisor = 175.78 ≈ 176 (actual: 9602 baud, error: 0.02%)
- 19200 baud: Divisor = 87.89 ≈ 88 (actual: 19176 baud, error: -0.13%)
- 38400 baud: Divisor = 43.95 ≈ 44 (actual: 38352 baud, error: -0.13%)
- 57600 baud: Divisor = 29.30 ≈ 29 (actual: 58189 baud, error: 1.02%)
- 115200 baud: Divisor = 14.65 ≈ 15 (actual: 112500 baud, error: -2.34%)

## Testing

Run the provided testbench:
```bash
iverilog -o uart_sim uart.v uart_tb.v
vvp uart_sim
gtkwave uart_tb.vcd
```

## Tang Nano 9K Pin Constraints Example

```tcl
# UART pins (adjust to your actual pinout)
IO_LOC "uart_rx" 18;
IO_PORT "uart_rx" IO_TYPE=LVCMOS33 PULL_MODE=UP;

IO_LOC "uart_tx" 17;
IO_PORT "uart_tx" IO_TYPE=LVCMOS33;
```

## Common Issues and Solutions

### Issue: Incorrect baud rate
**Solution**: Verify your system clock frequency matches the `clk_freq_hz` parameter. Use a logic analyzer to measure actual TX bit timing.

### Issue: Framing errors
**Solution**: Ensure RX and TX devices agree on baud rate. Check for clock frequency accuracy.

### Issue: Overrun errors
**Solution**: Service RX interrupts faster, or read the RX data register more frequently.

### Issue: No data received
**Solution**:
- Check RX pin connection
- Verify baud rate matches transmitter
- Ensure proper voltage levels (3.3V for Tang Nano 9K)
- Check TX/RX aren't swapped

## License
This module is provided as-is for educational and hobby use.
