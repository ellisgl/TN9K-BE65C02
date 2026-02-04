`timescale 1ns / 1ps
`default_nettype none

// Ultra-simple UART test - sends 'U' (0x55) every 100ms
// This is the simplest possible test of UART TX
module uart_simple_test (
    input  wire sys_clk,    // 27 MHz - pin 52
    input  wire rst_n,      // Reset button - pin 4
    output wire uartTx,     // TX output - pin 17
    input  wire uartRx      // RX input - pin 18 (unused but keep for synthesis)
);

    // Simple counter and state machine
    reg [23:0] counter;
    reg [3:0] state;
    reg [3:0] bit_idx;
    reg [15:0] baud_count;
    reg tx_out;
    
    // At 27 MHz, for 9600 baud: 27000000/9600 = 2812.5 ≈ 2813
    localparam BAUD_DIV = 2813;
    
    // States
    localparam IDLE  = 0;
    localparam START = 1;
    localparam BIT0  = 2;
    localparam BIT1  = 3;
    localparam BIT2  = 4;
    localparam BIT3  = 5;
    localparam BIT4  = 6;
    localparam BIT5  = 7;
    localparam BIT6  = 8;
    localparam BIT7  = 9;
    localparam STOP  = 10;
    localparam DELAY = 11;
    
    wire reset = ~rst_n;
    
    always @(posedge sys_clk) begin
        if (reset) begin
            state <= IDLE;
            tx_out <= 1'b1;  // Idle high
            counter <= 0;
            baud_count <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx_out <= 1'b1;
                    // Wait a bit before starting
                    if (counter >= 24'd2_700_000) begin  // ~100ms
                        counter <= 0;
                        state <= START;
                        baud_count <= 0;
                    end else begin
                        counter <= counter + 1;
                    end
                end
                
                START: begin
                    // Start bit (0)
                    tx_out <= 1'b0;
                    if (baud_count >= BAUD_DIV - 1) begin
                        baud_count <= 0;
                        state <= BIT0;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                
                BIT0: begin
                    tx_out <= 1'b1;  // 'U' = 0x55 = 01010101, bit 0 = 1
                    if (baud_count >= BAUD_DIV - 1) begin
                        baud_count <= 0;
                        state <= BIT1;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                
                BIT1: begin
                    tx_out <= 1'b0;  // bit 1 = 0
                    if (baud_count >= BAUD_DIV - 1) begin
                        baud_count <= 0;
                        state <= BIT2;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                
                BIT2: begin
                    tx_out <= 1'b1;  // bit 2 = 1
                    if (baud_count >= BAUD_DIV - 1) begin
                        baud_count <= 0;
                        state <= BIT3;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                
                BIT3: begin
                    tx_out <= 1'b0;  // bit 3 = 0
                    if (baud_count >= BAUD_DIV - 1) begin
                        baud_count <= 0;
                        state <= BIT4;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                
                BIT4: begin
                    tx_out <= 1'b1;  // bit 4 = 1
                    if (baud_count >= BAUD_DIV - 1) begin
                        baud_count <= 0;
                        state <= BIT5;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                
                BIT5: begin
                    tx_out <= 1'b0;  // bit 5 = 0
                    if (baud_count >= BAUD_DIV - 1) begin
                        baud_count <= 0;
                        state <= BIT6;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                
                BIT6: begin
                    tx_out <= 1'b1;  // bit 6 = 1
                    if (baud_count >= BAUD_DIV - 1) begin
                        baud_count <= 0;
                        state <= BIT7;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                
                BIT7: begin
                    tx_out <= 1'b0;  // bit 7 = 0
                    if (baud_count >= BAUD_DIV - 1) begin
                        baud_count <= 0;
                        state <= STOP;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                
                STOP: begin
                    tx_out <= 1'b1;  // Stop bit
                    if (baud_count >= BAUD_DIV - 1) begin
                        baud_count <= 0;
                        state <= IDLE;
                        counter <= 0;
                    end else begin
                        baud_count <= baud_count + 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    assign uartTx = tx_out;

endmodule

`default_nettype wire