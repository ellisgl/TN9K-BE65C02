`timescale 1ns / 1ps
`default_nettype none
////////////////////////////////////////////////////////////////////////////////
// Clock Divider Module
// Generates a divided clock output from input clock using a counter.
// Default divisor is 27 (e.g., 27 MHz -> 1 MHz).
////////////////////////////////////////////////////////////////////////////////
module clock_divider #(
    parameter DIVISOR = 27  // Clock division factor (must be even for 50% duty cycle)
) (
    input  wire clk_in,   // Input clock
    output reg  clk_out   // Divided output clock
);

    // Internal counter for division
    reg [31:0] counter;
    
    initial begin
        counter = 0;
        clk_out = 0;
    end

    // Synchronous logic 
    always @(posedge clk_in) begin
        if (counter >= DIVISOR - 1) begin
            counter <= 0;
            clk_out <= ~clk_out;
        end else begin
            counter <= counter + 1;
        end
    end

endmodule
`default_nettype wire
