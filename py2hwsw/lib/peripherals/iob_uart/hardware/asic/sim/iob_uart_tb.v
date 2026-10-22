// SPDX-FileCopyrightText: 2026 IObundle
//
// SPDX-License-Identifier: GPL-3.0-only

`timescale 1ns / 1ps

// Gate-level smoke test of the UART. It configures the UART through its CSR
// bus and checks that the transmitter sends a character. It instantiates the
// top module of the design (the ASIC wrapper is not added to peripheral
// cores), so it can run against the place-and-route netlist.
module iob_uart_tb;

   localparam DATA_W = 32;
   localparam ADDR_W = 4;
   localparam DIV = 40;
   localparam CLK_PER = 10;

   localparam [ADDR_W-1:0] SOFTRESET_ADDR = 0;
   localparam [ADDR_W-1:0] TXREADY_ADDR = 0;
   localparam [ADDR_W-1:0] DIV_ADDR = 2;
   localparam [ADDR_W-1:0] TXDATA_ADDR = 4;
   localparam [ADDR_W-1:0] TXEN_ADDR = 5;

   reg clk;
   initial clk = 0;
   always #(CLK_PER / 2) clk = ~clk;

   reg arst;
   reg cke;

   reg  rs232_rxd;
   wire rs232_txd;
   wire rs232_rts;
   reg  rs232_cts;

   reg  [ADDR_W-1:0] csr_addr;
   reg  [DATA_W-1:0] csr_wdata;
   reg  [DATA_W/8-1:0] csr_wstrb;
   reg  csr_valid;
   wire csr_rvalid;
   wire [DATA_W-1:0] csr_rdata;
   wire csr_ready;

   integer errors;
   integer i;
   integer fd;

   reg [DATA_W-1:0] rdata;
   reg [7:0] rxd_byte;

   iob_uart uut (
      .clk_i(clk),
      .cke_i(cke),
      .arst_i(arst),
      .rs232_rxd_i(rs232_rxd),
      .rs232_txd_o(rs232_txd),
      .rs232_rts_o(rs232_rts),
      .rs232_cts_i(rs232_cts),
      .csrs_iob_valid_i(csr_valid),
      .csrs_iob_addr_i(csr_addr),
      .csrs_iob_wdata_i(csr_wdata),
      .csrs_iob_wstrb_i(csr_wstrb),
      .csrs_iob_rvalid_o(csr_rvalid),
      .csrs_iob_rdata_o(csr_rdata),
      .csrs_iob_ready_o(csr_ready)
   );

   // Write a word of the CSR bus
   task csr_write;
      input [ADDR_W-1:0] addr;
      input [DATA_W-1:0] data;
      input [DATA_W/8-1:0] strb;
      begin
         @(negedge clk);
         csr_addr  = addr;
         csr_wdata = data;
         csr_wstrb = strb;
         csr_valid = 1;
         @(posedge clk) #1;
         while (!csr_ready) @(posedge clk) #1;
         @(negedge clk);
         csr_valid = 0;
         csr_wstrb = 0;
         @(posedge clk) #1;
      end
   endtask

   // Read a word of the CSR bus
   task csr_read;
      input [ADDR_W-1:0] addr;
      output [DATA_W-1:0] data;
      begin
         @(negedge clk);
         csr_addr  = addr;
         csr_wdata = 0;
         csr_wstrb = 0;
         csr_valid = 1;
         @(posedge clk) #1;
         while (!csr_ready) @(posedge clk) #1;
         while (!csr_rvalid) @(posedge clk) #1;
         data      = csr_rdata;
         @(negedge clk);
         csr_valid = 0;
         @(posedge clk) #1;
      end
   endtask

   task check_errors;
      begin
         if (errors == 0) begin
            $display("Test completed successfully.");
            fd = $fopen("test.log", "w");
            $fdisplay(fd, "Test passed!");
            $fclose(fd);
         end else begin
            $display("Test failed: %0d error(s).", errors);
            fd = $fopen("test.log", "w");
            $fdisplay(fd, "Test failed: %0d error(s).", errors);
            $fclose(fd);
         end
      end
   endtask

   initial begin
`ifdef VCD
      $dumpfile("uart.vcd");
      $dumpvars();
`endif
      errors = 0;
      arst = 1;
      cke = 1;
      rs232_rxd = 1;
      // CTS is active low in this UART (the transmitter is enabled when it is
      // not asserted)
      rs232_cts = 0;
      csr_addr = 0;
      csr_wdata = 0;
      csr_wstrb = 0;
      csr_valid = 0;

      // Hold the reset for a few cycles
      repeat (5) @(posedge clk);
      @(negedge clk) arst = 0;
      repeat (5) @(posedge clk);

      // The transmitter must be idle high and known after the reset
      if (rs232_txd !== 1'b1) begin
         $display("ERROR: rs232_txd_o is not high after the reset (value %b)", rs232_txd);
         errors = errors + 1;
      end
      if (rs232_rts !== 1'b0 && rs232_rts !== 1'b1) begin
         $display("ERROR: rs232_rts_o is unknown (value %b)", rs232_rts);
         errors = errors + 1;
      end

      // Set the bit duration (the DIV register is at byte offset 2 of the
      // word, so its 16 bits are the upper half of the data word) and enable
      // the TX
      csr_write(DIV_ADDR, {DIV[15:0], 16'd0}, 4'b1100);
      csr_write(TXEN_ADDR, 32'h0000_0100, 4'b0010);

      // Check that the transmitter is ready
      csr_read(TXREADY_ADDR, rdata);
      if (rdata[0] !== 1'b1) begin
         $display("ERROR: the transmitter is not ready after it was enabled");
         errors = errors + 1;
      end

      // Send a character ('A') through the TX data register
      csr_write(TXDATA_ADDR, 32'h0000_0041, 4'b0001);

      // Wait for the start bit
      i = 0;
      while (rs232_txd !== 1'b0 && i < 4 * DIV) begin
         @(posedge clk);
         i = i + 1;
      end
      if (rs232_txd !== 1'b0) begin
         $display("ERROR: the start bit was not sent");
         errors = errors + 1;
      end

      // Sample the start bit, the data bits and the stop bit in the middle of
      // their bit periods
      repeat (DIV / 2) @(posedge clk);
      if (rs232_txd !== 1'b0) begin
         $display("ERROR: the start bit is not low");
         errors = errors + 1;
      end
      for (i = 0; i < 8; i = i + 1) begin
         repeat (DIV) @(posedge clk);
         rxd_byte[i] = rs232_txd;
      end
      repeat (DIV) @(posedge clk);
      if (rs232_txd !== 1'b1) begin
         $display("ERROR: the stop bit is not high");
         errors = errors + 1;
      end
      if (rxd_byte !== 8'h41) begin
         $display("ERROR: received byte 0x%02x, expected 0x41", rxd_byte);
         errors = errors + 1;
      end

      // The transmitter must be ready again after the stop bit
      repeat (DIV) @(posedge clk);
      csr_read(TXREADY_ADDR, rdata);
      if (rdata[0] !== 1'b1) begin
         $display("ERROR: the transmitter is not ready after the transfer");
         errors = errors + 1;
      end

      check_errors();
      $finish();
   end

endmodule
