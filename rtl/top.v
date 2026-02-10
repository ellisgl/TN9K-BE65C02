`timescale 1ns / 1ps
`default_nettype none
module top #(
    parameter integer SYS_CLK_HZ  = 27_000_000, // Input oscillator frequency
    parameter integer CLK_DIVISOR = 14          // Divides sys_clk; clk = sys_clk / (2 * DIVISOR)
)(
    input  wire       sys_clk,
    input  wire       rst_n,
    input  wire       uartRx,
    input  wire       uartCts,
    input  wire       sdMiso,
    output wire       uartTx,
    output wire       uartRts,
    output wire       sdClk,
    output wire       sdCs,
    output wire       sdMosi,
    inout  wire [7:0] PB      // VIA6522 Port B
);

    localparam  integer CPU_HZ = SYS_CLK_HZ / (2 * CLK_DIVISOR);
    localparam  integer XTLI_FREQ = SYS_CLK_HZ;
    wire        clk;  // Divided clock, about 1.929 MHz with DIVISOR=7 from 27 MHz input
    wire        reset;
    reg  [15:0] address;
    wire [15:0] address_unregistered;
    wire        cpu_we;
    wire        cpu_rdy = 1'b1;
    wire  [7:0] cpu_di;
    wire  [7:0] cpu_do;
    wire        cpu_irq;
    wire        via_cs;
    wire        rom_cs;
    wire        ram_cs;
    wire        uart_cs;
    wire  [7:0] via_do;
    wire        via_irq_n;
    wire        uart_irq_n;
    wire  [7:0] rom_do;
    wire  [7:0] ram_do;
    wire  [7:0] uart_do;
    wire  [7:0] pb_out;
    wire  [7:0] pb_mask;
    wire  [7:0] PA;
    wire  [7:0] pa_out;
    wire  [7:0] pa_mask;
    
    assign sdMiso = PA[1];
    assign sdMosi = PA[2];
    assign sdClk  = PA[3];
    assign sdCs   = PA[4];

    // Instantiate Clock Divider (e.g., divide 27 MHz to ~1 MHz)
    clock_divider #(
        .DIVISOR(CLK_DIVISOR)
    ) clk_div_inst (
        .clk_in(sys_clk),
        .clk_out(clk)
    );

        reset reset_inst (
        .clk(clk),
        .reset_n(rst_n),
        .reset(reset)
    );

    // 16KB RAM at 16'h0000 - 16'h3FFF
    ram ram_inst (
        .clk(clk),
        .ADDR(address[13:0]),
        .WE(cpu_we),
        .CS(ram_cs),
        .DI(cpu_do),
        .DO(ram_do)
    );

    // 32KB ROM at 16'h8000 - 16'hFFFF
    rom rom_inst (
        .ADDR(address[14:0]),
        .CS(rom_cs),
        .DO(rom_do)
    );

    // VIA6522 at 16'h6000 - 16'h6007
    via6522 via6522_inst (
        .cs(via_cs),
        .phi2(clk),
        .nReset(~reset),
        .rs(address[3:0]),
        .rWb(~cpu_we),
        .dataIn(cpu_do),
        .dataOut(via_do),
        .paIn(),
        .paOut(pa_out),
        .paMask(pa_mask),
        .pbIn(),
        .pbOut(pb_out),
        .pbMask(pb_mask),
        .nIrq(via_irq_n)
    );

    // UART at 16'h5000 - 16'h5003
    ACIA #(
        .XTLI_FREQ(XTLI_FREQ)
    ) uart_inst (
        .RESET(~reset),
        .PHI2(clk),
        .CS(~uart_cs),
        .RWN(~cpu_we),
        .RS(address[1:0]),
        .DATAIN(cpu_do),
        .DATAOUT(uart_do),
        .XTLI(sys_clk),// Use the raw oscillator for accurate baud generation
        .RTSB(uartRts),
        .CTSB(1'b0), // Tie CTS low if hardware flow control is unused
        .DTRB(), // Not used
        .RXD(uartRx),
        .TXD(uartTx),
        .IRQn(uart_irq_n)
    );

    cpu cpu_inst (
        .clk(clk),
        .RST(reset),
        .AD(address_unregistered),
        .DI(cpu_di),
        .DO(cpu_do),
        .WE(cpu_we),
        .IRQ(cpu_irq),
        .NMI(1'b0),
        .RDY(cpu_rdy),
        .sync(),
        .debug(1'b0)
    );

    // Tri-state logic for open-drain emulation
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : pb_tristate
            assign PB[i] = pb_mask[i] ? pb_out[i] : 1'bz;
            assign PA[i] = pa_mask[i] ? pa_out[i] : 1'bz;
        end
    endgenerate

    // CPU Interrupt ORing
    assign cpu_irq    = ~via_irq_n | ~uart_irq_n; // CPU input is active high

    // CPU DIN MUX
    assign ram_cs     = (address[15:14] == 2'b00);      // 0x0000 - 0x3FFF
    assign uart_cs    = (address[15:4]  == 12'h500);    // 0x5000 - 0x500F
    assign via_cs     = (address[15:4]  == 12'h600);    // 0x6000 - 0x600F
    assign rom_cs     = address[15];                    // 0x8000 - 0xFFFF
    assign cpu_di     =
        rom_cs  ? rom_do  :
        ram_cs  ? ram_do  :
        via_cs  ? via_do  :
        uart_cs ? uart_do : 8'hXX;
    
        // "When using external asynchronous memory, you should register the "AD" signals"
    // Also register uart_rx_in to break long paths and resample UART input
    always @(posedge clk) begin
        address    <= address_unregistered;
    end

endmodule
`default_nettype wire
