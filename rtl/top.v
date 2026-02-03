`timescale 1ns / 1ps
`default_nettype none
module top #(
    parameter integer CLK_DIVISOR = 27  // Clock divider for CPU domain (overridable in sim)
)(
    input  wire       sys_clk,
    input  wire       rst_n,
    input  wire       uartRx,
    output wire       uartTx,
    inout  wire [7:0] PB,      // VIA6522 Port B
    inout  wire [7:0] PA       // VIA6522 Port A
);

    wire        clk;
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

    wire  [7:0] via_data_out;
    wire        via_irq_n;
    wire        uart_irq_n;
    wire  [7:0] rom_data_out;
    wire  [7:0] ram_data_out;
    wire  [7:0] uart_data_out;
    wire  [7:0] pbOut;
    wire  [7:0] pbMask;
    wire  [7:0] paOut;
    wire  [7:0] paMask;

    // Instantiate Clock Divider (e.g., divide 27 MHz to 1 MHz)
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
        .DO(ram_data_out)
    );

    // 32KB ROM at 16'h8000 - 16'hFFFF
    rom rom_inst (
        .ADDR(address[14:0]),
        .CS(rom_cs),
        .DO(rom_data_out)
    );

    // VIA6522 at 16'h6000 - 16'h6007
    via6522 via6522_inst (
        .cs(via_cs),
        .phi2(clk),
        .nReset(~reset),
        .rs(address[3:0]),
        .rWb(~cpu_we),
        .dataIn(cpu_do),
        .dataOut(via_data_out),
        .paIn(),
        .paOut(paOut),
        .paMask(paMask),
        .pbIn(),
        .pbOut(pbOut),
        .pbMask(pbMask),
        .nIrq(via_irq_n)
    );

    // DATA   = 0x5000
    // STATUS = 0x5001
    // CMD    = 0x5002
    // CTRL   = 0x5003
    UART uart (
        .clk(clk),
        .rst(reset),
        .rw(~cpu_we),
        .rs0(address[0]),
        .rs1(address[1]),
        .cs(uart_cs),
        .data_in(cpu_do),
        .rx(uartRx),
        .data_out(uart_data_out),
        .tx(uartTx),
        .irq(uart_irq_n)
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
            assign PB[i] = pbMask[i] ? pbOut[i] : 1'bz;
            assign PA[i] = paMask[i] ? paOut[i] : 1'bz;
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
        rom_cs  ? rom_data_out  :
        ram_cs  ? ram_data_out  :
        via_cs  ? via_data_out  :
        uart_cs ? uart_data_out : 8'hXX;

    // "When using external asynchronous memory, you should register the "AD" signals"
    always @(posedge clk) begin
        address <= address_unregistered;
    end

endmodule
`default_nettype wire
