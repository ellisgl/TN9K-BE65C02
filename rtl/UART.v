`timescale 1ns / 1ps
`default_nettype none

////////////////////////////////////////////////////////////////////////////////
// UART Module - Completely Rewritten TX Logic
// W65C51N compatible UART with corrected timing
////////////////////////////////////////////////////////////////////////////////
module UART #(
    parameter clk_freq_hz = 27_000_000,
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
    // Simple baud divisor - no fancy rounding
    localparam integer BAUD_DIV = clk_freq_hz / (baud_rate * oversample);

    //==========================================================================
    // Register Map (W65C51N compatible)
    //==========================================================================
    wire [1:0] reg_addr = {rs1, rs0};

    //==========================================================================
    // Registers
    //==========================================================================
    reg [7:0] tx_data_reg;
    reg [7:0] rx_data_reg;
    reg [7:0] command_reg;
    reg [7:0] control_reg;

    // Status Register bits
    reg parity_error;
    reg framing_error;
    reg overrun_error;
    reg rx_data_ready;
    reg tx_data_empty;
    reg dcd;
    reg dsr;
    reg irq_flag;

    wire [7:0] status_reg = {
        irq_flag,
        dsr,
        dcd,
        tx_data_empty,
        rx_data_ready,
        overrun_error,
        framing_error,
        parity_error
    };

    //==========================================================================
    // Baud Rate Generator
    //==========================================================================
    reg [$clog2(BAUD_DIV):0] baud_counter;
    reg baud_tick;

    always @(posedge clk) begin
        if (rst) begin
            baud_counter <= 0;
            baud_tick <= 0;
        end else begin
            if (baud_counter >= BAUD_DIV - 1) begin
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
    reg [7:0] tx_shift_reg;
    reg [3:0] tx_bit_index;    // 0=start, 1-8=data, 9=stop
    reg [3:0] tx_tick_count;   // Count oversample ticks within a bit
    reg       tx_active;
    reg       tx_out;

    always @(posedge clk) begin
        if (rst) begin
            tx_out <= 1'b1;          // Idle high
            tx_active <= 0;
            tx_data_empty <= 1;
            tx_bit_index <= 0;
            tx_tick_count <= 0;
            tx_shift_reg <= 0;
        end else begin
            if (!tx_active) begin
                // Idle state - waiting for data
                tx_out <= 1'b1;
                if (!tx_data_empty) begin
                    // Start transmission
                    tx_shift_reg <= tx_data_reg;
                    tx_data_empty <= 1;
                    tx_active <= 1;
                    tx_bit_index <= 0;
                    tx_tick_count <= 0;
                    tx_out <= 1'b0;  // Start bit
                end
            end else begin
                // Transmitting
                if (baud_tick) begin
                    if (tx_tick_count >= oversample - 1) begin
                        // Move to next bit
                        tx_tick_count <= 0;

                        if (tx_bit_index == 9) begin
                            // Stop bit complete
                            tx_active <= 0;
                            tx_out <= 1'b1;
                        end else begin
                            // Move to next bit
                            tx_bit_index <= tx_bit_index + 1;

                            if (tx_bit_index == 0) begin
                                // Start bit done, output first data bit
                                tx_out <= tx_shift_reg[0];
                                tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            end else if (tx_bit_index < 8) begin
                                // Data bits
                                tx_out <= tx_shift_reg[0];
                                tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            end else begin
                                // Stop bit
                                tx_out <= 1'b1;
                            end
                        end
                    end else begin
                        tx_tick_count <= tx_tick_count + 1;
                    end
                end
            end
        end
    end

    assign tx = tx_out;

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
                    if (!rx_filtered) begin
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (baud_tick) begin
                        if (rx_sample_count >= (oversample / 2) - 1) begin
                            rx_sample_count <= 0;
                            if (!rx_filtered) begin
                                rx_state <= RX_DATA;
                                rx_bit_count <= 0;
                            end else begin
                                rx_state <= RX_IDLE;
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
                            if (rx_filtered) begin
                                if (rx_data_ready) begin
                                    overrun_error <= 1;
                                end else begin
                                    rx_data_reg <= rx_shift_reg;
                                    rx_data_ready <= 1;
                                end
                                framing_error <= 0;
                            end else begin
                                framing_error <= 1;
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
        end else if (cs) begin
            if (rw) begin
                case (reg_addr)
                    2'b00: begin
                        data_out <= rx_data_reg;
                        rx_data_ready <= 0;
                        overrun_error <= 0;
                        framing_error <= 0;
                        parity_error <= 0;
                    end
                    2'b01: data_out <= status_reg;
                    2'b10: data_out <= command_reg;
                    2'b11: data_out <= control_reg;
                endcase
            end else begin
                case (reg_addr)
                    2'b00: begin
                        tx_data_reg <= data_in;
                        tx_data_empty <= 0;
                    end
                    2'b01: begin
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

    assign irq = ~irq_flag;

endmodule

`default_nettype wire