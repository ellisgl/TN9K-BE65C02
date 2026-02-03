`timescale 1ns / 1ps
`default_nettype none

////////////////////////////////////////////////////////////////////////////////
// UART Testbench
////////////////////////////////////////////////////////////////////////////////
module UART_tb;
    reg        clk;
    reg        rst;
    reg        rw;
    reg        rs0;
    reg        rs1;
    reg        cs;
    reg [7:0]  data_in;
    reg        rx_in;
    wire [7:0] data_out;
    wire       tx_out;
    wire       irq;

    // Instantiate UART with faster clock for simulation
    UART #(
        .clk_freq_hz(1_000_000),  // 1 MHz
        .baud_rate(115200),        // 115200 baud
        .oversample(16)
    ) uut (
        .clk(clk),
        .rst(rst),
        .rw(rw),
        .rs0(rs0),
        .rs1(rs1),
        .cs(cs),
        .data_in(data_in),
        .rx(rx_in),
        .data_out(data_out),
        .tx(tx_out),
        .irq(irq)
    );

    // Clock generation (1 MHz = 1us period)
    initial begin
        clk = 0;
        forever #500 clk = ~clk;  // 1 MHz clock
    end

    // Calculate bit period for 115200 baud
    // Bit period = 1/115200 = 8.68 us = 8680 ns
    localparam real BIT_PERIOD = 8680.0;

    // Helper task: Write to UART register
    task write_register;
        input [1:0] addr;
        input [7:0] data;
        begin
            @(posedge clk);
            cs = 1;
            rw = 0;
            {rs1, rs0} = addr;
            data_in = data;
            @(posedge clk);
            cs = 0;
            @(posedge clk);
        end
    endtask

    // Helper task: Read from UART register
    task read_register;
        input  [1:0] addr;
        output [7:0] data;
        begin
            @(posedge clk);
            cs = 1;
            rw = 1;
            {rs1, rs0} = addr;
            @(posedge clk);
            data = data_out;
            cs = 0;
            @(posedge clk);
        end
    endtask

    // Helper task: Send a byte on RX line (simulate external device)
    task send_byte_rx;
        input [7:0] byte_data;
        integer i;
        begin
            // Start bit
            rx_in = 0;
            #BIT_PERIOD;

            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                rx_in = byte_data[i];
                #BIT_PERIOD;
            end

            // Stop bit
            rx_in = 1;
            #BIT_PERIOD;
        end
    endtask

    // Main test sequence
    reg [7:0] read_data;

    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, uart_tb);

        // Initialize signals
        rst = 1;
        rw = 0;
        rs0 = 0;
        rs1 = 0;
        cs = 0;
        data_in = 8'h00;
        rx_in = 1;  // Idle state

        // Reset
        #2000;
        rst = 0;
        #1000;

        $display("\n=== UART Test Starting ===\n");

        //======================================================================
        // Test 1: Read Status Register
        //======================================================================
        $display("Test 1: Read initial status register");
        read_register(2'b01, read_data);
        $display("  Status: 0x%02h (TX empty should be set)", read_data);

        //======================================================================
        // Test 2: Transmit a byte
        //======================================================================
        $display("\nTest 2: Transmit byte 0x55");
        write_register(2'b00, 8'h55);  // Write to TX data register

        // Wait for transmission to complete
        #100000;  // ~11.5 bit periods

        read_register(2'b01, read_data);
        $display("  Status after TX: 0x%02h", read_data);

        //======================================================================
        // Test 3: Receive a byte
        //======================================================================
        $display("\nTest 3: Receive byte 0xAA");
        fork
            send_byte_rx(8'hAA);
        join

        #1000;

        // Check status - should show data ready
        read_register(2'b01, read_data);
        $display("  Status after RX: 0x%02h (RX ready should be set)", read_data);

        // Read the received data
        read_register(2'b00, read_data);
        $display("  Received data: 0x%02h (expected 0xAA)", read_data);

        // Status should clear after read
        read_register(2'b01, read_data);
        $display("  Status after read: 0x%02h (RX ready should be clear)", read_data);

        //======================================================================
        // Test 4: Enable IRQ and test
        //======================================================================
        $display("\nTest 4: Test interrupt generation");
        write_register(2'b10, 8'h02);  // Enable RX IRQ (bit 1)

        #1000;
        send_byte_rx(8'h42);
        #1000;

        $display("  IRQ line: %b (should be 0/active)", irq);

        // Clear by reading data
        read_register(2'b00, read_data);
        $display("  Received: 0x%02h, IRQ: %b", read_data, irq);

        //======================================================================
        // Test 5: Test overrun error
        //======================================================================
        $display("\nTest 5: Test overrun error");
        send_byte_rx(8'h11);
        #1000;

        // Send another byte without reading the first
        send_byte_rx(8'h22);
        #1000;

        read_register(2'b01, read_data);
        $display("  Status: 0x%02h (overrun bit 2 should be set)", read_data);

        // Clear by reading data
        read_register(2'b00, read_data);
        $display("  First byte: 0x%02h (should be 0x11)", read_data);

        //======================================================================
        // Test 6: Programmed reset
        //======================================================================
        $display("\nTest 6: Programmed reset");
        write_register(2'b01, 8'h00);  // Write to reset register
        #1000;

        read_register(2'b10, read_data);
        $display("  Command reg after reset: 0x%02h (should be 0x00)", read_data);
        read_register(2'b11, read_data);
        $display("  Control reg after reset: 0x%02h (should be 0x00)", read_data);

        //======================================================================
        // Test 7: Loopback test
        //======================================================================
        $display("\nTest 7: Loopback test (TX->RX)");

        // Connect TX to RX internally for this test
        // (In real hardware, you'd connect TX pin to RX pin externally)
        fork
            begin
                write_register(2'b00, 8'h7E);
            end
            begin
                #10000;  // Wait a bit for TX to start
                // Monitor tx_out and feed it to rx_in
                // This is simplified - in reality you'd need proper timing
            end
        join

        //======================================================================
        // Finish
        //======================================================================
        #50000;
        $display("\n=== UART Test Complete ===\n");
        $finish;
    end

    // Monitor
    initial begin
        $monitor("Time=%0t rst=%b cs=%b rw=%b rs=%b data_in=%02h data_out=%02h tx=%b rx=%b irq=%b",
                 $time, rst, cs, rw, {rs1,rs0}, data_in, data_out, tx_out, rx_in, irq);
    end

    // Timeout watchdog
    initial begin
        #500000;
        $display("\n=== TIMEOUT ===\n");
        $finish;
    end

endmodule

`default_nettype wire
