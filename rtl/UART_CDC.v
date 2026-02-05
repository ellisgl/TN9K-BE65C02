`timescale 1ns / 1ps
`default_nettype none

////////////////////////////////////////////////////////////////////////////////
// UART Module with CDC Synchronization
// Designed for UART on fast clock (27 MHz) with CPU on slow clock (1 MHz)
////////////////////////////////////////////////////////////////////////////////
module UART #(
    parameter clk_freq_hz = 27_000_000,
    parameter baud_rate   = 9600,
    parameter oversample  = 16
) (
    input  wire        clk,       // UART clock (27 MHz)
    input  wire        cpu_clk,   // CPU clock (1 MHz) - NEW
    input  wire        rst,
    input  wire        rw,        // 1=read, 0=write (from CPU clock domain)
    input  wire        rs0,
    input  wire        rs1,
    input  wire        cs,        // Chip select (from CPU clock domain)
    input  wire [7:0]  data_in,
    input  wire        rx,
    output reg  [7:0]  data_out,
    output wire        tx,
    output wire        irq
);
    localparam integer BAUD_DIV = clk_freq_hz / (baud_rate * oversample);

    //==========================================================================
    // CPU Interface Synchronization (CDC)
    //==========================================================================
    // Synchronize chip select to UART clock domain
    reg [2:0] cs_sync;
    reg [2:0] rw_sync;
    reg [1:0] rs_sync;
    reg [7:0] data_in_sync;
    
    always @(posedge clk) begin
        if (rst) begin
            cs_sync <= 3'b000;
            rw_sync <= 3'b111;
            rs_sync <= 2'b00;
            data_in_sync <= 8'h00;
        end else begin
            cs_sync <= {cs_sync[1:0], cs};
            rw_sync <= {rw_sync[1:0], rw};
            if (cs) begin
                rs_sync <= {rs1, rs0};
                data_in_sync <= data_in;
            end
        end
    end
    
    wire cs_synced = cs_sync[2];
    wire rw_synced = rw_sync[2];
    wire cs_rising = cs_sync[2] && !cs_sync[1];  // Detect rising edge
    
    //==========================================================================
    // Register Map
    //==========================================================================
    wire [1:0] reg_addr = rs_sync;
    
    reg [7:0] tx_data_reg;
    reg [7:0] rx_data_reg;
    reg [7:0] command_reg;
    reg [7:0] control_reg;

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
    reg [3:0] tx_bit_index;
    reg [3:0] tx_tick_count;
    reg       tx_active;
    reg       tx_out;

    always @(posedge clk) begin
        if (rst) begin
            tx_out <= 1'b1;
            tx_active <= 0;
            tx_data_empty <= 1;
            tx_bit_index <= 0;
            tx_tick_count <= 0;
            tx_shift_reg <= 0;
        end else begin
            if (!tx_active) begin
                tx_out <= 1'b1;
                if (!tx_data_empty) begin
                    tx_shift_reg <= tx_data_reg;
                    tx_data_empty <= 1;
                    tx_active <= 1;
                    tx_bit_index <= 0;
                    tx_tick_count <= 0;
                    tx_out <= 1'b0;
                end
            end else begin
                if (baud_tick) begin
                    if (tx_tick_count >= oversample - 1) begin
                        tx_tick_count <= 0;
                        
                        if (tx_bit_index == 9) begin
                            tx_active <= 0;
                            tx_out <= 1'b1;
                        end else begin
                            tx_bit_index <= tx_bit_index + 1;
                            
                            if (tx_bit_index == 0) begin
                                tx_out <= tx_shift_reg[0];
                                tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            end else if (tx_bit_index < 8) begin
                                tx_out <= tx_shift_reg[0];
                                tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                            end else begin
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
    // Register Read/Write Logic - Only on CS rising edge
    //==========================================================================
    always @(posedge clk) begin
        if (rst) begin
            data_out <= 8'h00;
            tx_data_reg <= 8'h00;
            command_reg <= 8'h00;
            control_reg <= 8'h00;
            dcd <= 0;
            dsr <= 0;
        end else if (cs_rising) begin  // ← Only on rising edge of synchronized CS
            if (rw_synced) begin
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
                case (reg_addr)
                    2'b00: begin
                        tx_data_reg <= data_in_sync;
                        tx_data_empty <= 0;
                    end
                    2'b01: begin
                        command_reg <= 8'h00;
                        control_reg <= 8'h00;
                        overrun_error <= 0;
                        framing_error <= 0;
                        parity_error <= 0;
                    end
                    2'b10: command_reg <= data_in_sync;
                    2'b11: control_reg <= data_in_sync;
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
