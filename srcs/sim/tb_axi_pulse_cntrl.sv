
`timescale 1ns / 1ps

module tb_axi_pulse_cntrl;

    localparam integer CLK_HALF_NS = 10;
    localparam integer SIM_PERIOD = 20;
    localparam integer SIM_WIDTH = 10;

    localparam logic [3: 0] OFF_CTRL = 4'h0;
    localparam logic [3: 0] OFF_PERIOD = 4'h4;
    localparam logic [3: 0] OFF_WIDTH = 4'h8;
    localparam logic [3: 0] OFF_STATUS = 4'hC;

    localparam logic [31: 0] CTRL_ENABLE = 32'h1;
    localparam logic [31: 0] CTRL_INVERT = 32'h2;

    logic clk = 1'b0;
    logic resetn = 1'b0;

    always #(CLK_HALF_NS) clk = ~clk;

    if_axi_lite #(
        .ADDR_WIDTH(4),
        .DATA_WIDTH(32)
    ) axi ();

    assign axi.aclk = clk;
    assign axi.aresetn = resetn;

    logic pulse_out;

    axi_pulse_cntrl dut (
        .s_axi    (axi.slave),
        .pulse_out(pulse_out)
    );

    task automatic axi_write(input logic [3: 0] addr, input logic [31: 0] data);
        @(posedge clk); #1;
        axi.awaddr = addr;
        axi.awprot = 3'b000;
        axi.awvalid = 1'b1;
        axi.wdata = data;
        axi.wstrb = 4'hF;
        axi.wvalid = 1'b1;
        axi.bready = 1'b1;

        forever begin
            @(posedge clk);
            if (axi.awready && axi.wready) break;
        end

		#1; axi.awvalid = 1'b0;
        axi.wvalid = 1'b0;

        forever begin
            @(posedge clk);
            if (axi.bvalid) break;
        end

		#1; axi.bready = 1'b0;
    endtask

    task automatic axi_read(input logic [3: 0] addr, output logic [31: 0] data);
        @(posedge clk); #1;
        axi.araddr = addr;
        axi.arprot = 3'b000;
        axi.arvalid = 1'b1;
        axi.rready = 1'b1;

        forever begin
            @(posedge clk);
            if (axi.arready) break;
        end

		#1; axi.arvalid = 1'b0;

        forever begin
            @(posedge clk);
            if (axi.rvalid) break;
        end
        data = axi.rdata; #1;
        axi.rready = 1'b0;
    endtask

    int pass_count = 0;
    int fail_count = 0;

    task automatic check(input string label, input logic [31: 0] got, input logic [31: 0] expected);
        if (got === expected) begin
            $display("  [PASS] %s", label);
            pass_count++;
        end else begin
            $display("  [FAIL] %s - expected 0x%08h, got 0x%08h", label, expected, got);
            fail_count++;
        end
    endtask

    logic [31: 0] rdata;
    logic pulse_before_invert;

    initial begin
        axi.awvalid = 1'b0;
        axi.awaddr = '0;
        axi.awprot = '0;
        axi.wvalid = 1'b0;
        axi.wdata = '0;
        axi.wstrb = '0;
        axi.bready = 1'b0;
        axi.arvalid = 1'b0;
        axi.araddr = '0;
        axi.arprot = '0;
        axi.rready = 1'b0;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (5) @(posedge clk);

        $display("\n=== Test 1: Disabled by default ===");
        @(posedge clk); #1;
        check("pulse_out == 0 after reset", {31'b0, pulse_out}, 32'h0);

        $display("\n=== Test 2: Register write/read ===");
        axi_write(OFF_PERIOD, SIM_PERIOD);
        axi_write(OFF_WIDTH, SIM_WIDTH);

        axi_read(OFF_PERIOD, rdata);
        check("PERIOD readback", rdata, SIM_PERIOD);

        axi_read(OFF_WIDTH, rdata);
        check("WIDTH readback", rdata, SIM_WIDTH);

        $display("\n=== Test 3: Pulse toggles when enabled ===");
        axi_write(OFF_CTRL, CTRL_ENABLE);

        @(posedge pulse_out);
        check("pulse_out rises after enable", {31'b0, pulse_out}, 32'h1);

        @(negedge pulse_out);
        check("pulse_out falls after WIDTH cycles", {31'b0, pulse_out}, 32'h0);

        $display("\n=== Test 4: STATUS register mirrors pulse_out ===");

        @(posedge pulse_out);
        axi_read(OFF_STATUS, rdata);
        check("STATUS[0] = 1 while pulse_out is high", rdata & 32'h1, 32'h1);

        @(negedge pulse_out);
        axi_read(OFF_STATUS, rdata);
        check("STATUS[0] = 0 while pulse_out is low", rdata & 32'h1, 32'h0);

        $display("\n=== Test 5: Invert ===");

        @(posedge clk); #1;
        pulse_before_invert = pulse_out;

        axi_write(OFF_CTRL, CTRL_ENABLE | CTRL_INVERT);

        @(posedge clk); #1;
        check("pulse_out inverted after CTRL_INVERT set", {31'b0, pulse_out}, { 31'b0, ~pulse_before_invert});

        @(posedge pulse_out);
        check("inverted pulse still has rising edges", {31'b0, pulse_out}, 32'h1);
        @(negedge pulse_out);
        check("inverted pulse still has falling edges", {31'b0, pulse_out}, 32'h0);

        axi_write(OFF_CTRL, CTRL_ENABLE);

        $display("\n=== Test 6: Disable ===");
        axi_write(OFF_CTRL, 32'h0);

        repeat (SIM_PERIOD * 4) @(posedge clk);
        check("pulse_out held low after CTRL_ENABLE cleared", {31'b0, pulse_out}, 32'h0);

        $display("\n=== Test 7: PERIOD = 0 clamped to 1 ===");
        axi_write(OFF_PERIOD, 32'h0);
        axi_read(OFF_PERIOD, rdata);
        check("PERIOD register clamped from 0 to 1", rdata, 32'h1);

        $display("\n========================================");
        $display("  %0d passed  /  %0d failed", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("  ALL TESTS PASSED\n");
        else $display("  SOME TESTS FAILED\n");

        $finish;
    end

    initial begin #1_000_000;
        $display("[TIMEOUT] Simulation exceeded limit");
        $finish;
    end

endmodule
