// SPDX-FileCopyrightText: 2026 IObundle
//
// SPDX-License-Identifier: CERN-OHL-S-2.0

`timescale 1ns / 1ps

module iob_axis_m_axi_m_read #(
   parameter AXI_ADDR_W = 0,
   parameter AXI_DATA_W = 32,  // We currently only support 4 byte transfers
   parameter AXI_LEN_W  = 8,
   parameter AXI_ID_W   = 1
) (
   // Global signals
   `include "iob_axis_m_axi_m_read_iob_clk_s_port.vs"
   input rst_i,

   // Axi master interface
   `include "iob_axis_m_axi_m_read_axi_read_m_port.vs"

   // Configuration
   input  [AXI_ADDR_W-1:0] r_addr_i,
   input  [ AXI_LEN_W-1:0] r_length_i,
   input                   r_start_transfer_i,
   input  [         2-1:0] r_burst_type_i,
   output                  r_busy_o,
   output [         2-1:0] r_resp_o,

   // Axi stream input
   output [AXI_DATA_W-1:0] axis_out_data_o,
   output                  axis_out_valid_o,
   input                   axis_out_ready_i
);

   localparam WAIT_START = 2'd0, START_BURST = 2'd1, TRANSF_DATA = 2'd2;

   // Instantiation wires
   wire [(AXI_LEN_W+1)-1:0] length;
   wire [            2-1:0] state;
   wire [(AXI_LEN_W+1)-1:0] burst_length_beats = {1'b0, r_length_i} + 1'b1;

   // Input saved signals
   wire [   AXI_DATA_W-1:0] axi_rdata_reg;
   wire                     axi_rvalid_reg;

   // Assignment to outputs
   // Inputs mux in case of saved signals due to ready signal down
   assign axis_out_data_o  = axi_rready_o ? axi_rdata_i : axi_rdata_reg;
   assign axis_out_valid_o = axi_rready_o ? axi_rvalid_i : axi_rvalid_reg;

   // Constants
   assign axi_arid_o       = {AXI_ID_W{1'd0}};
   assign axi_arsize_o     = 3'd2;
   assign axi_arburst_o    = r_burst_type_i;
   assign axi_arlock_o     = 2'd0;
   assign axi_arcache_o    = 4'd2;
   assign axi_arprot_o     = 3'd2;
   assign axi_arqos_o      = 4'd0;

   // AXI Stream ready signal
   wire axi_rready_nxt;
   assign axi_rready_nxt = axis_out_ready_i;

   // Busy signal
   assign r_busy_o = state != WAIT_START;  // Converter is busy if not waiting for a new transfer

   // AXI Stream ready signal2axi
   // FSM signals
   reg [             2-1:0] state_nxt;
   reg [    AXI_ADDR_W-1:0] axi_araddr_nxt;
   reg [ (AXI_LEN_W+1)-1:0] length_nxt;
   reg [     AXI_LEN_W-1:0] axi_arlen_nxt;
   reg                      axi_arvalid_nxt;
   reg [(AXI_ADDR_W+1)-1:0] last_addr;
   reg [             2-1:0] r_resp_nxt;

   always @* begin
      // Calculate the last address of the burst using the normal burst length
      last_addr       = r_addr_i + ((burst_length_beats << 2) - 1);

      // FSM
      // Default assignments
      state_nxt       = state;
      axi_arvalid_nxt = 1'd0;
      axi_araddr_nxt  = axi_araddr_o;
      length_nxt      = length;
      axi_arlen_nxt   = axi_arlen_o;
      r_resp_nxt      = r_resp_o;

      // Latch AXI read response type on accepted R beats until next transfer starts.
      if (axi_rvalid_i && axi_rready_o && (axi_rresp_i != 2'b00)) begin
         r_resp_nxt = axi_rresp_i;
      end

      case (state)
         WAIT_START: begin
            r_resp_nxt = 2'b00;
            if (r_start_transfer_i) begin  // Start transfer in the next state
               // FIXED bursts do not advance address, so no 4k split is required.
               // INCR bursts use full length only if they remain in the same 4k boundary.
               if ((r_burst_type_i == 2'b00) || (r_addr_i[12] == last_addr[12])) begin
                  axi_arlen_nxt = r_length_i;
               end else begin
                  // If the burst's last address is in the next 4k boundary,
                  // the burst length is the remaining space in the current 4k boundary
                  axi_arlen_nxt = ((13'd4096 - r_addr_i[0+:13]) >> 2) - 1;
               end

               axi_araddr_nxt  = r_addr_i;  // Set start address
               axi_arvalid_nxt = 1'd1;  // Start transfer
               length_nxt      = burst_length_beats - (axi_arlen_nxt + 1);  // Set remaining length
               state_nxt       = START_BURST;
            end
         end

         START_BURST: begin  // Send burst address and length and wait for ready signal
            if (axi_arready_i) begin
               state_nxt = TRANSF_DATA;
            end else begin
               axi_arvalid_nxt = 1'd1;
            end
         end

         default: begin  // TRANSF_DATA: Transfer data
            if (axi_rlast_i && axi_rvalid_i && axi_rready_o) begin // Check if the last data was received
               if ((length == 0) || (r_resp_nxt != 2'b00)) begin
                  state_nxt = WAIT_START;
               end else begin  // Transfer the remaining data
                  // The previous burst was not in the same 4k boundary, so the next burst will be
                  axi_arlen_nxt   = length - 1;
                  axi_araddr_nxt  = axi_araddr_o + ((axi_arlen_o + 1) << 2);
                  axi_arvalid_nxt = 1'd1;
                  length_nxt      = 0;
                  state_nxt       = START_BURST;
               end
            end
         end
      endcase
   end

   iob_reg_car #(
      .DATA_W ((AXI_LEN_W + 1)),
      .RST_VAL(0)
   ) length_reg (
       `include "iob_axis_m_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(length_nxt),
       .data_o(length)
   );

   iob_reg_car #(
      .DATA_W (2),
      .RST_VAL(0)
   ) state_reg (
       `include "iob_axis_m_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(state_nxt),
       .data_o(state)
   );

   // AXI interface registers
   iob_reg_car #(
      .DATA_W (AXI_LEN_W),
      .RST_VAL(0)
   ) axi_arlen_reg (
       `include "iob_axis_m_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(axi_arlen_nxt),
       .data_o(axi_arlen_o)
   );

   iob_reg_car #(
      .DATA_W (AXI_ADDR_W),
      .RST_VAL(0)
   ) axi_araddr_reg (
       `include "iob_axis_m_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(axi_araddr_nxt),
       .data_o(axi_araddr_o)
   );

   iob_reg_car #(
      .DATA_W (1),
      .RST_VAL(0)
   ) axi_arvalid_reg (
       `include "iob_axis_m_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(axi_arvalid_nxt),
       .data_o(axi_arvalid_o)
   );

   iob_reg_car #(
      .DATA_W (1),
      .RST_VAL(0)
   ) axi_rready_reg (
       `include "iob_axis_m_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(axi_rready_nxt),
       .data_o(axi_rready_o)
   );

   iob_reg_care #(
      .DATA_W (AXI_DATA_W),
      .RST_VAL(0)
   ) axi_rdata_reg_inst (
       `include "iob_axis_m_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .en_i  (axi_rready_o),
       .data_i(axi_rdata_i),
       .data_o(axi_rdata_reg)
   );

   iob_reg_care #(
      .DATA_W (1),
      .RST_VAL(0)
   ) axi_rvalid_reg_inst (
       `include "iob_axis_m_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .en_i  (axi_rready_o),
       .data_i(axi_rvalid_i),
       .data_o(axi_rvalid_reg)
   );

   iob_reg_car #(
      .DATA_W (2),
      .RST_VAL(2'b00)
   ) r_resp_reg (
       `include "iob_axis_m_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(r_resp_nxt),
       .data_o(r_resp_o)
   );

endmodule
