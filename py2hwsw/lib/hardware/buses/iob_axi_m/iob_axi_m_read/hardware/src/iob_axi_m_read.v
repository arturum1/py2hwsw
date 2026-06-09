// SPDX-FileCopyrightText: 2026 IObundle
//
// SPDX-License-Identifier: CERN-OHL-V2-S

`timescale 1ns / 1ps

module iob_axi_m_read #(
   parameter AXI_ADDR_W  = 0,
   parameter AXI_LEN_W   = 8,
   parameter AXI_DATA_W  = 32,
   parameter AXI_ID_W    = 1,
   parameter RLENGTH_W   = 0,
   parameter FIFO_ADDR_W = 0
) (
   // Global signals
   `include "iob_axi_m_read_iob_clk_s_port.vs"
   input rst_i,

   // Configuration IO's
   input      [AXI_ADDR_W-1:0] r_addr_i,
   input      [ RLENGTH_W-1:0] r_length_i,
   input                       r_start_transfer_i,
   input      [ AXI_LEN_W-1:0] r_max_len_i,
   input      [         2-1:0] r_burst_type_i,
   output     [ RLENGTH_W-1:0] r_remaining_data_o,
   output reg                  r_busy_o,
   output     [         2-1:0] r_resp_o,

   // AXIS Master Interface
   output [AXI_DATA_W-1:0] axis_out_tdata_o,
   output                  axis_out_tvalid_o,
   input                   axis_out_tready_i,

   // External memory interface
   output                   ext_mem_w_en_o,
   output [FIFO_ADDR_W-1:0] ext_mem_w_addr_o,
   output [ AXI_DATA_W-1:0] ext_mem_w_data_o,
   output                   ext_mem_r_en_o,
   output [FIFO_ADDR_W-1:0] ext_mem_r_addr_o,
   input  [ AXI_DATA_W-1:0] ext_mem_r_data_i,

   // AXI Master (read only) Interface
   `include "iob_axi_m_read_axi_read_m_port.vs"
);

   localparam WAIT_START = 1'd0, WAIT_SPACE_IN_FIFO = 1'd1;
   localparam FIFO_MAX_LEVEL = 1 << FIFO_ADDR_W;

   // Calculate empty space in FIFO
   wire [(FIFO_ADDR_W+1)-1:0] fifo_level;
   wire [(FIFO_ADDR_W+1)-1:0] space_in_fifo = FIFO_MAX_LEVEL - fifo_level;

   wire [     AXI_DATA_W-1:0] fifo_wdata;
   wire                       fifo_wen;
   wire                       fifo_full;
   wire                       fifo_wready;
   assign fifo_wready = ~fifo_full;
   wire                  fifo_ren;
   wire [AXI_DATA_W-1:0] fifo_rdata;
   wire                  fifo_empty;

   // FIFO2AXIS converter
   wire                  fifo2axis_en = ~rst_i;
   iob_fifo2axis #(
      .DATA_W    (AXI_DATA_W),
      .AXIS_LEN_W(1)
   ) fifo2axis_inst (
       // Global signals
       `include "iob_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i        (rst_i),
       .en_i         (fifo2axis_en),
       .len_i        (1'b1),
       .level_o      (),
       .fifo_empty_i (fifo_empty),
       .fifo_read_o  (fifo_ren),
       .fifo_rdata_i (fifo_rdata),
       .axis_tvalid_o(axis_out_tvalid_o),
       .axis_tdata_o (axis_out_tdata_o),
       .axis_tready_i(axis_out_tready_i),
       .axis_tlast_o ()
   );

   // FIFO
   iob_fifo_sync #(
      .W_DATA_W(AXI_DATA_W),
      .R_DATA_W(AXI_DATA_W),
      .ADDR_W  (FIFO_ADDR_W)
   ) buffer_inst (
       // Global signals
       `include "iob_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i           (rst_i),
       // Write port
       .w_en_i          (fifo_wen),
       .w_data_i        (fifo_wdata),
       .w_full_o        (fifo_full),
       // Read port
       .r_en_i          (fifo_ren),
       .r_data_o        (fifo_rdata),
       .r_empty_o       (fifo_empty),
       // External memory interface
       .ext_mem_w_en_o  (ext_mem_w_en_o),
       .ext_mem_w_addr_o(ext_mem_w_addr_o),
       .ext_mem_w_data_o(ext_mem_w_data_o),
       .ext_mem_r_en_o  (ext_mem_r_en_o),
       .ext_mem_r_addr_o(ext_mem_r_addr_o),
       .ext_mem_r_data_i(ext_mem_r_data_i),
       // FIFO level
       .level_o         (fifo_level)
   );

   reg                      r_state_nxt;
   wire                     r_state;
   reg  [    RLENGTH_W-1:0] r_remaining_data_nxt;
   reg  [(AXI_LEN_W+1)-1:0] burst_length;
   reg  [   AXI_ADDR_W-1:0] burst_addr_nxt;
   wire [   AXI_ADDR_W-1:0] burst_addr;
   reg                      start_burst;
   wire                     busy;
   wire [(AXI_LEN_W+1)-1:0] max_burst_length = {1'b0, r_max_len_i} + 1'b1;
   wire [    AXI_LEN_W-1:0] burst_length_decr = burst_length[0+:(AXI_LEN_W)] - 1'b1;

   always @* begin
      // FSM
      // Default assignments
      r_busy_o             = 1'b1;
      r_state_nxt          = r_state;
      r_remaining_data_nxt = r_remaining_data_o;
      burst_addr_nxt       = burst_addr;
      start_burst          = 1'b0;
      burst_length         = 0;

      case (r_state)
         WAIT_START: begin
            r_busy_o = 1'b0;
            if (r_start_transfer_i) begin
               r_remaining_data_nxt = r_length_i;
               burst_addr_nxt       = r_addr_i;
               r_state_nxt          = WAIT_SPACE_IN_FIFO;
            end
         end
         default: begin  // WAIT_SPACE_IN_FIFO
            if (!busy) begin
               if (r_resp_o != 2'b00) begin
                  r_state_nxt = WAIT_START;
               end else if (r_remaining_data_o > 0) begin
                  if (({{RLENGTH_W-(FIFO_ADDR_W+1){1'b0}}, space_in_fifo} >= r_remaining_data_o)
                        && (r_remaining_data_o <= {{RLENGTH_W-(AXI_LEN_W+1){1'b0}}, max_burst_length}))
                  begin
                     // TX FIFO has enough space left to transfer the remaining data
                     burst_length = r_remaining_data_o[0+:(AXI_LEN_W+1)];
                  end else if ({{AXI_LEN_W-FIFO_ADDR_W{1'b0}}, space_in_fifo} >= max_burst_length) begin
                     // TX FIFO has enough space for a burst transfer
                     burst_length = max_burst_length;
                  end

                  if (burst_length > 0) begin
                     // Start the transfer
                     start_burst          = 1'd1;
                     // Set values for the next transfer
                     r_remaining_data_nxt = r_remaining_data_o - burst_length;
                     if (r_burst_type_i == 2'b00) begin
                        // FIXED burst: keep address constant across beats/bursts
                        burst_addr_nxt = burst_addr;
                     end else begin
                        // INCR burst: advance address by burst length in bytes
                        burst_addr_nxt = burst_addr + (burst_length << 2);
                     end
                  end
               end else begin
                  r_state_nxt = WAIT_START;
               end
            end
         end
      endcase
   end

   iob_reg_car #(
      .DATA_W (1),
      .RST_VAL(1'd0)
   ) r_state_reg (
       `include "iob_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(r_state_nxt),
       .data_o(r_state)
   );

   iob_reg_car #(
      .DATA_W (RLENGTH_W),
      .RST_VAL({RLENGTH_W{1'b0}})
   ) r_length_reg (
       `include "iob_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(r_remaining_data_nxt),
       .data_o(r_remaining_data_o)
   );

   iob_reg_car #(
      .DATA_W (AXI_ADDR_W),
      .RST_VAL({AXI_ADDR_W{1'b0}})
   ) r_addr_reg (
       `include "iob_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(burst_addr_nxt),
       .data_o(burst_addr)
   );

   iob_axis_m_axi_m_read #(
      .AXI_ADDR_W(AXI_ADDR_W),
      .AXI_DATA_W(AXI_DATA_W),
      .AXI_LEN_W (AXI_LEN_W),
      .AXI_ID_W  (AXI_ID_W)
   ) axis_m_axi_m_read_inst (
       `include "iob_axi_m_read_iob_clk_s_s_portmap.vs"
       .rst_i(rst_i),

       `include "iob_axi_m_read_axi_read_m_m_portmap.vs"

       .r_addr_i          (burst_addr),
       .r_length_i        (burst_length_decr),
       .r_start_transfer_i(start_burst),
       .r_burst_type_i    (r_burst_type_i),
       .r_busy_o          (busy),
       .r_resp_o          (r_resp_o),

       .axis_out_data_o (fifo_wdata),
       .axis_out_valid_o(fifo_wen),
       .axis_out_ready_i(fifo_wready)
   );

endmodule
