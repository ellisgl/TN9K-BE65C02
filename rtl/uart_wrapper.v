`timescale 1ns / 1ns
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
//
// Simple UART Wrapper for 8-bit system - FIXED VERSION
// Wraps UART modules from https://github.com/ben-marshall/uart/
//
// FIX: Latches uart_rx_data when uart_rx_valid pulses
//
//////////////////////////////////////////////////////////////////////////////////

module gs_uart_top (
    input clk,           // Top level system clock input.
    input resetn,        // System reset (active low)
    input [1:0] ADDR,    // 2-bit address (00=data, 01=status, others ignored)
    input CS,            // Chip select (active high)
    input WE,            // active high
    input [7:0] DI,      // data bus in
    output [7:0] DO,     // data bus out
    output IRQ,          // IRQ active high (reading status register clears this)
    input uart_rxd,      // UART Recieve pin.
    output uart_txd      // UART transmit pin.
);

// UART parameters
parameter CLK_HZ = 1_000_000;
parameter BIT_RATE = 115200;
parameter PAYLOAD_BITS = 8;

// UART RX
wire [PAYLOAD_BITS-1:0] uart_rx_data;
wire uart_rx_valid;
wire uart_rx_break;
uart_rx #(
    .BIT_RATE(BIT_RATE),
    .PAYLOAD_BITS(PAYLOAD_BITS),
    .CLK_HZ(CLK_HZ)
) i_uart_rx(
    .clk          (clk),
    .resetn       (resetn),
    .uart_rxd     (uart_rxd),
    .uart_rx_en   (1'b1),
    .uart_rx_break(uart_rx_break),
    .uart_rx_valid(uart_rx_valid),
    .uart_rx_data (uart_rx_data)
);

// UART TX
wire [PAYLOAD_BITS-1:0]  uart_tx_data;
wire uart_tx_busy;
wire uart_tx_en;
uart_tx #(
    .BIT_RATE(BIT_RATE),
    .PAYLOAD_BITS(PAYLOAD_BITS),
    .CLK_HZ(CLK_HZ)
) i_uart_tx(
    .clk          (clk),
    .resetn       (resetn),
    .uart_txd     (uart_txd),
    .uart_tx_en   (uart_tx_en),
    .uart_tx_busy (uart_tx_busy),
    .uart_tx_data (uart_tx_data)
);

// Databus CPU-Read Logic
reg uart_rx_break_r;
reg uart_rx_valid_r;
reg [7:0] uart_rx_data_r;  // ← NEW: Latch the received data!

always @ (posedge clk) begin
    if (~resetn) begin
        uart_rx_break_r <= 1'b0;
        uart_rx_valid_r <= 1'b0;
        uart_rx_data_r  <= 8'h00;  // ← NEW
    end else begin
        // Latch UART Break
        if (uart_rx_break)
            uart_rx_break_r <= 1'b1;
        else if (CS & ~WE & (ADDR == 2'b01))
            uart_rx_break_r <= 1'b0;
            
        // Latch UART RX Valid AND Data  ← FIXED
        if (uart_rx_valid) begin
            uart_rx_valid_r <= 1'b1;
            uart_rx_data_r  <= uart_rx_data;  // ← NEW: Latch data when valid
        end else if (CS & ~WE & (ADDR == 2'b01)) begin
            uart_rx_valid_r <= 1'b0;
        end
    end
end

wire [7:0] status_register;
// Map rx_valid to bit3 to satisfy Wozmon's AND #$08 poll for "key ready"
assign status_register = {4'b0000, uart_rx_valid_r, uart_tx_busy, uart_rx_break_r, 1'b0};

// ← FIXED: Use latched data instead of direct uart_rx_data
assign DO = (ADDR == 2'b00) ? uart_rx_data_r[7:0] :  // Was: uart_rx_data[7:0]
            (ADDR == 2'b01) ? status_register   :
            8'hFF;

// Generate IRQ output
assign IRQ = uart_rx_break_r | uart_rx_valid_r;

// Databus CPU-Write Logic
assign uart_tx_data = DI;
assign uart_tx_en = (CS & WE & (ADDR == 2'b00)); // write to data register only

endmodule
`default_nettype wire
