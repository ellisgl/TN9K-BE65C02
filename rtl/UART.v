`timescale 1ns / 1ps
`default_nettype none

////////////////////////////////////////////////////////////////////////////////
// UART Module
// W65C51N compatible UART with configurable clock and baud rate.
////////////////////////////////////////////////////////////////////////////////
module UART #(
    parameter clk_freq_hz = 1_000_000,
    parameter baud_rate   = 9600,
    parameter oversample  = 16
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        rw,       // 1=read, 0=write
    input  wire        rs0,
    input  wire        rs1,
    input  wire        cs,       // Chip select (active high)
    input  wire [7:0]  data_in,
    input  wire        rx,       // From the real world
    output reg  [7:0]  data_out,
    output wire        tx,       // To the real world
    output wire        irq
);
    parameter baud_divisor = clk_freq_hz / (baud_rate * oversample);

    //==========================================================================
    // Register Map (W65C51N compatible)
    //==========================================================================
    // RS1 RS0  R/W  Register
    //  0   0    R   RX Data Register
    //  0   0    W   TX Data Register
    //  0   1    R   Status Register
    //  0   1    W   Programmed Reset
    //  1   0   R/W  Command Register
    //  1   1   R/W  Control Register

    wire chip_select = cs;
    wire [1:0] reg_addr = {rs1, rs0};

    //==========================================================================
    // Registers
    //==========================================================================
    reg [7:0] tx_data_reg;
    reg [7:0] rx_data_reg;
    reg [7:0] command_reg;   // Command register
    reg [7:0] control_reg;   // Control register

    // Status Register bits
    reg parity_error;
    reg framing_error;
    reg overrun_error;
    reg rx_data_ready;
    reg tx_data_empty;
    reg dcd;                 // Data Carrier Detect (not implemented, tied low)
    reg dsr;                 // Data Set Ready (not implemented, tied low)
    reg irq_flag;

    wire [7:0] status_reg = {
        irq_flag,           // bit 7: IRQ flag
        dsr,                // bit 6: DSR (tied low)
        dcd,                // bit 5: DCD (tied low)
        tx_data_empty,      // bit 4: Transmitter Data Register Empty
        rx_data_ready,      // bit 3: Receiver Data Register Full
        overrun_error,      // bit 2: Overrun error
        framing_error,      // bit 1: Framing error
        parity_error        // bit 0: Parity error
    };

    //==========================================================================
    // Baud Rate Generator
    //==========================================================================
    reg [$clog2(baud_divisor)-1:0] baud_counter;
    reg baud_tick;

    always @(posedge clk) begin
        if (rst) begin
            baud_counter <= 0;
            baud_tick <= 0;
        end else begin
            if (baud_counter >= baud_divisor - 1) begin
                baud_counter <= 0;
                baud_tick <= 1;
            end else begin
                baud_counter <= baud_counter + 1;
                baud_tick <= 0;
            end
        end
    end

    //==========================================================================
    // Transmitter
    //==========================================================================
    reg [3:0] tx_state;
    reg [3:0] tx_bit_count;
    reg [7:0] tx_shift_reg;
    reg       tx_reg;
    reg       tx_busy;
    reg [3:0] tx_sample_count;

    localparam TX_IDLE  = 4'd0;
    localparam TX_START = 4'd1;
    localparam TX_DATA  = 4'd2;
    localparam TX_STOP  = 4'd3;

    assign tx = tx_reg;

    always @(posedge clk) begin
        if (rst) begin
            tx_state <= TX_IDLE;
            tx_reg <= 1'b1;
            tx_busy <= 0;
            tx_bit_count <= 0;
            tx_sample_count <= 0;
            tx_data_empty <= 1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_reg <= 1'b1;
                    if (!tx_data_empty && !tx_busy) begin
                        tx_shift_reg <= tx_data_reg;
                        tx_busy <= 1;
                        tx_data_empty <= 1;
                        tx_state <= TX_START;
                        tx_sample_count <= 0;
                    end
                end

                TX_START: begin
                    if (baud_tick) begin
                        if (tx_sample_count >= oversample - 1) begin
                            tx_sample_count <= 0;
                            tx_reg <= 1'b0;  // Start bit
                            tx_state <= TX_DATA;
                            tx_bit_count <= 0;
                        end else begin
                            tx_sample_count <= tx_sample_count + 1;
                        end
                    end
                end

                TX_DATA: begin
                    if (baud_tick) begin
                        if (tx_sample_count >= oversample - 1) begin
                            tx_sample_count <= 0;
                            tx_reg <= tx_shift_reg[0];
                            tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            if (tx_bit_count >= 7) begin
                                tx_state <= TX_STOP;
                            end else begin
                                tx_bit_count <= tx_bit_count + 1;
                            end
                        end else begin
                            tx_sample_count <= tx_sample_count + 1;
                        end
                    end
                end

                TX_STOP: begin
                    if (baud_tick) begin
                        if (tx_sample_count >= oversample - 1) begin
                            tx_sample_count <= 0;
                            tx_reg <= 1'b1;  // Stop bit
                            tx_busy <= 0;
                            tx_state <= TX_IDLE;
                        end else begin
                            tx_sample_count <= tx_sample_count + 1;
                        end
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    //==========================================================================
    // Receiver
    //==========================================================================
    reg [3:0] rx_state;
    reg [3:0] rx_bit_count;
    reg [7:0] rx_shift_reg;
    reg [3:0] rx_sample_count;
    reg [2:0] rx_sync;

    localparam RX_IDLE  = 4'd0;
    localparam RX_START = 4'd1;
    localparam RX_DATA  = 4'd2;
    localparam RX_STOP  = 4'd3;

    // Synchronize RX input
    always @(posedge clk) begin
        if (rst)
            rx_sync <= 3'b111;
        else
            rx_sync <= {rx_sync[1:0], rx};
    end

    wire rx_filtered = rx_sync[2];

    always @(posedge clk) begin
        if (rst) begin
            rx_state <= RX_IDLE;
            rx_bit_count <= 0;
            rx_sample_count <= 0;
            rx_data_ready <= 0;
            framing_error <= 0;
            overrun_error <= 0;
            parity_error <= 0;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    rx_sample_count <= 0;
                    if (!rx_filtered) begin  // Start bit detected
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (baud_tick) begin
                        if (rx_sample_count >= (oversample / 2) - 1) begin
                            rx_sample_count <= 0;
                            if (!rx_filtered) begin  // Confirm start bit
                                rx_state <= RX_DATA;
                                rx_bit_count <= 0;
                            end else begin
                                rx_state <= RX_IDLE;  // False start
                            end
                        end else begin
                            rx_sample_count <= rx_sample_count + 1;
                        end
                    end
                end

                RX_DATA: begin
                    if (baud_tick) begin
                        if (rx_sample_count >= oversample - 1) begin
                            rx_sample_count <= 0;
                            rx_shift_reg <= {rx_filtered, rx_shift_reg[7:1]};
                            if (rx_bit_count >= 7) begin
                                rx_state <= RX_STOP;
                            end else begin
                                rx_bit_count <= rx_bit_count + 1;
                            end
                        end else begin
                            rx_sample_count <= rx_sample_count + 1;
                        end
                    end
                end

                RX_STOP: begin
                    if (baud_tick) begin
                        if (rx_sample_count >= oversample - 1) begin
                            rx_sample_count <= 0;
                            if (rx_filtered) begin  // Valid stop bit
                                if (rx_data_ready) begin
                                    overrun_error <= 1;  // Data not read yet
                                end else begin
                                    rx_data_reg <= rx_shift_reg;
                                    rx_data_ready <= 1;
                                end
                                framing_error <= 0;
                            end else begin
                                framing_error <= 1;  // Missing stop bit
                            end
                            rx_state <= RX_IDLE;
                        end else begin
                            rx_sample_count <= rx_sample_count + 1;
                        end
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    //==========================================================================
    // Register Read/Write Logic
    //==========================================================================
    always @(posedge clk) begin
        if (rst) begin
            data_out <= 8'h00;
            tx_data_reg <= 8'h00;
            command_reg <= 8'h00;
            control_reg <= 8'h00;
            dcd <= 0;
            dsr <= 0;
        end else if (chip_select) begin
            if (rw) begin
                // Read operation
                case (reg_addr)
                    2'b00: begin
                        data_out <= rx_data_reg;
                        rx_data_ready <= 0;  // Clear on read
                        overrun_error <= 0;
                        framing_error <= 0;
                        parity_error <= 0;
                    end
                    2'b01: data_out <= status_reg;
                    2'b10: data_out <= command_reg;
                    2'b11: data_out <= control_reg;
                endcase
            end else begin
                // Write operation
                case (reg_addr)
                    2'b00: begin
                        tx_data_reg <= data_in;
                        tx_data_empty <= 0;
                    end
                    2'b01: begin
                        // Programmed reset
                        command_reg <= 8'h00;
                        control_reg <= 8'h00;
                        overrun_error <= 0;
                        framing_error <= 0;
                        parity_error <= 0;
                    end
                    2'b10: command_reg <= data_in;
                    2'b11: control_reg <= data_in;
                endcase
            end
        end
    end

    //==========================================================================
    // Interrupt Logic
    //==========================================================================
    // Command register bit 1: RX IRQ enable
    // Command register bit 3,2: TX interrupt control
    wire rx_irq_enable = command_reg[1];
    wire tx_irq_enable = command_reg[3:2] == 2'b01;

    always @(posedge clk) begin
        if (rst) begin
            irq_flag <= 0;
        end else begin
            irq_flag <= (rx_irq_enable & rx_data_ready) |
                        (tx_irq_enable & tx_data_empty);
        end
    end

    assign irq = ~irq_flag;  // Active low interrupt

endmodule

`default_nettype wire
