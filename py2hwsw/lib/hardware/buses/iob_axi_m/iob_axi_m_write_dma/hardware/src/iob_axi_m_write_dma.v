`timescale 1ns / 1ps

module iob_axi_m_write_dma #(
   parameter AXI_ADDR_W  = 0,
   parameter AXI_LEN_W   = 8,
   parameter AXI_DATA_W  = 32,
   parameter AXI_ID_W    = 1,
   parameter WLENGTH_W   = 0,
   parameter FIFO_ADDR_W = 0
) (
   // Global signals
   `include "iob_axi_m_wrtie_dma_iob_clk_s_port.vs"
   input rst_i,

   // Configuration IO's
   input      [AXI_ADDR_W-1:0] w_addr_i,
   input      [ WLENGTH_W-1:0] w_length_i,
   input                       w_start_transfer_i,
   input                       w_dma_req_en_i,
   input                       w_dma_req_i,
   output                      w_dma_req_pending_o,
   output                      w_dma_ack_o,
   input      [ AXI_LEN_W-1:0] w_max_len_i,
   input      [         2-1:0] w_burst_type_i,
   output     [ WLENGTH_W-1:0] w_remaining_data_o,
   output reg                  w_busy_o,
   output     [         2-1:0] w_resp_o,

   // AXIS Slave Interface
   input  [AXI_DATA_W-1:0] axis_in_data_i,
   input                   axis_in_valid_i,
   output                  axis_in_ready_o,

   // External memory interface
   output                   ext_mem_w_en_o,
   output [FIFO_ADDR_W-1:0] ext_mem_w_addr_o,
   output [ AXI_DATA_W-1:0] ext_mem_w_data_o,
   output                   ext_mem_r_en_o,
   output [FIFO_ADDR_W-1:0] ext_mem_r_addr_o,
   input  [ AXI_DATA_W-1:0] ext_mem_r_data_i,

   // AXI Master (write only) Interface
   `include "iob_axi_m_wrtie_dma_axi_write_m_port.vs"
);

   localparam [2-1:0] WAIT_START = 2'd0,
      WAIT_DATA_IN_FIFO = 2'd1,
      WAIT_DMA_REQ = 2'd2,
      WAIT_DMA_TRANSFER = 2'd3;
   localparam LEN_DIFF = WLENGTH_W - (AXI_LEN_W + 1);
   localparam INT_LEVEL_DIFF = (FIFO_ADDR_W + 2) - (AXI_LEN_W + 1);
   localparam WLEN_DIFF = WLENGTH_W - (FIFO_ADDR_W + 2);

   wire [(FIFO_ADDR_W+1)-1:0] fifo_level;
   wire                       fifo_full;
   assign axis_in_ready_o = ~fifo_full;
   wire                  fifo_ren;
   wire [AXI_DATA_W-1:0] fifo_rdata;
   wire                  fifo_empty;

   // FIFO
   iob_fifo_sync #(
      .W_DATA_W(AXI_DATA_W),
      .R_DATA_W(AXI_DATA_W),
      .ADDR_W  (FIFO_ADDR_W)
   ) buffer_inst (
       // Global signals
       `include "iob_axi_m_wrtie_dma_iob_clk_s_s_portmap.vs"
       .rst_i           (rst_i),
       // Write port
       .w_en_i          (axis_in_valid_i),
       .w_data_i        (axis_in_data_i),
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

   wire [         2-1:0] fifo2axis_lvl;
   wire                  axis_tvalid_int;
   wire [AXI_DATA_W-1:0] axis_tdata_int;
   wire                  axis_tready_int;
   wire                  fifo2axis_en;
   assign fifo2axis_en = ~rst_i;

   iob_fifo2axis #(
      .DATA_W    (AXI_DATA_W),
      .AXIS_LEN_W(1)
   ) fifo2axis_inst (
       // Global signals
       `include "iob_axi_m_wrtie_dma_iob_clk_s_s_portmap.vs"
       .rst_i        (rst_i),
       .en_i         (fifo2axis_en),
       .len_i        (1'b1),
       .level_o      (fifo2axis_lvl),
       // FIFO I/F
       .fifo_empty_i (fifo_empty),
       .fifo_read_o  (fifo_ren),
       .fifo_rdata_i (fifo_rdata),
       // AXIS I/F
       .axis_tvalid_o(axis_tvalid_int),
       .axis_tdata_o (axis_tdata_int),
       .axis_tready_i(axis_tready_int),
       .axis_tlast_o ()
   );

   wire [(FIFO_ADDR_W+2)-1:0] level_int = {1'd0, fifo_level} + {1'd0, fifo2axis_lvl};

   reg  [              2-1:0] w_state_nxt;
   wire [              2-1:0] w_state;
   reg  [      WLENGTH_W-1:0] w_remaining_data_nxt;
   reg  [  (AXI_LEN_W+1)-1:0] burst_length;
   reg  [     AXI_ADDR_W-1:0] burst_addr_nxt;
   wire [     AXI_ADDR_W-1:0] burst_addr;
   reg                        start_burst;
   wire                       busy;
   wire [  (AXI_LEN_W+1)-1:0] max_burst_length = {1'b0, w_max_len_i} + 1'b1;
   wire [      AXI_LEN_W-1:0] burst_length_decr = burst_length - 1'b1;

   wire                       w_dma_req_pending;
   reg                        w_dma_req_pending_nxt;
   wire                       w_dma_ack;
   reg                        w_dma_ack_nxt;
   wire                       w_busy_d;
   reg                        w_busy_d_nxt;
   reg                        w_busy_fall;

   always @* begin
      // FSM
      // Default assignments
      w_busy_o              = 1'b1;
      w_state_nxt           = w_state;
      w_remaining_data_nxt  = w_remaining_data_o;
      burst_addr_nxt        = burst_addr;
      start_burst           = 1'b0;
      burst_length          = 0;

      w_busy_fall           = w_busy_d & ~busy;

      w_dma_req_pending_nxt = w_dma_req_pending;
      w_dma_ack_nxt         = w_dma_ack;
      w_busy_d_nxt          = busy;

      if (w_busy_fall && w_dma_req_pending) begin
         w_dma_ack_nxt = 1'b1;
      end

      if (w_dma_ack && ~w_dma_req_i) begin
         w_dma_ack_nxt         = 1'b0;
         w_dma_req_pending_nxt = 1'b0;
      end

      case (w_state)
         WAIT_START: begin
            w_busy_o = 1'b0;
            if (w_start_transfer_i) begin
               w_remaining_data_nxt = w_length_i;
               burst_addr_nxt       = w_addr_i;
               if (w_dma_req_en_i) begin
                  w_state_nxt = WAIT_DMA_REQ;
               end else begin
                  w_state_nxt = WAIT_DATA_IN_FIFO;
               end
            end
         end

         WAIT_DATA_IN_FIFO: begin
            if (!busy) begin
               if (w_remaining_data_o > 0) begin
                  if (({{WLEN_DIFF{1'b0}}, level_int} >= w_remaining_data_o) &&
                        (w_remaining_data_o <= {{LEN_DIFF{1'b0}}, max_burst_length})) begin
                     // RX FIFO has enough data to transfer the remaining data
                     burst_length = w_remaining_data_o[0+:(AXI_LEN_W+1)];
                  end else if (level_int >= {{INT_LEVEL_DIFF{1'b0}}, max_burst_length}) begin
                     // RX FIFO has enough data for a burst transfer
                     burst_length = max_burst_length;
                  end

                  if (burst_length > 0) begin
                     start_burst          = 1'd1;
                     w_remaining_data_nxt = w_remaining_data_o - burst_length;
                     if (w_burst_type_i == 2'b00) begin
                        burst_addr_nxt = burst_addr;
                     end else begin
                        burst_addr_nxt = burst_addr + (burst_length << 2);
                     end
                  end
               end else begin
                  w_state_nxt = WAIT_START;
               end
            end
         end

         WAIT_DMA_REQ: begin
            if (w_dma_req_i) begin
               w_dma_req_pending_nxt = 1'b1;
               w_state_nxt           = WAIT_DMA_TRANSFER;
            end
         end

         default: begin  // WAIT_DMA_TRANSFER
            if (!busy) begin
               if (w_dma_ack) begin
                  if (w_remaining_data_o > 0) begin
                     w_state_nxt = WAIT_DMA_REQ;
                  end else begin
                     w_state_nxt = WAIT_START;
                  end
               end else if (!w_busy_d && (w_remaining_data_o > 0)) begin
                  if (({{WLEN_DIFF{1'b0}}, level_int} >= w_remaining_data_o) &&
                        (w_remaining_data_o <= {{LEN_DIFF{1'b0}}, max_burst_length})) begin
                     burst_length = w_remaining_data_o[0+:(AXI_LEN_W+1)];
                  end else if (level_int >= {{INT_LEVEL_DIFF{1'b0}}, max_burst_length}) begin
                     burst_length = max_burst_length;
                  end

                  if (burst_length > 0) begin
                     start_burst          = 1'd1;
                     w_remaining_data_nxt = w_remaining_data_o - burst_length;
                     if (w_burst_type_i == 2'b00) begin
                        burst_addr_nxt = burst_addr;
                     end else begin
                        burst_addr_nxt = burst_addr + (burst_length << 2);
                     end
                  end
               end
            end
         end
      endcase
   end

   assign w_dma_req_pending_o = w_dma_req_pending;
   assign w_dma_ack_o         = w_dma_ack;

   // State register
   iob_reg_car #(
      .DATA_W (2),
      .RST_VAL(1'd0)
   ) w_state_reg (
       `include "iob_axi_m_wrtie_dma_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(w_state_nxt),
       .data_o(w_state)
   );

   // Length registers
   iob_reg_car #(
      .DATA_W (WLENGTH_W),
      .RST_VAL({WLENGTH_W{1'b0}})
   ) w_length_reg (
       `include "iob_axi_m_wrtie_dma_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(w_remaining_data_nxt),
       .data_o(w_remaining_data_o)
   );

   // Address registers
   iob_reg_car #(
      .DATA_W (AXI_ADDR_W),
      .RST_VAL({AXI_ADDR_W{1'b0}})
   ) w_addr_reg (
       `include "iob_axi_m_wrtie_dma_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(burst_addr_nxt),
       .data_o(burst_addr)
   );

   iob_reg_car #(
      .DATA_W (1),
      .RST_VAL(1'd0)
   ) w_dma_req_pending_reg (
       `include "iob_axi_m_wrtie_dma_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(w_dma_req_pending_nxt),
       .data_o(w_dma_req_pending)
   );

   iob_reg_car #(
      .DATA_W (1),
      .RST_VAL(1'd0)
   ) w_dma_ack_reg (
       `include "iob_axi_m_wrtie_dma_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(w_dma_ack_nxt),
       .data_o(w_dma_ack)
   );

   iob_reg_car #(
      .DATA_W (1),
      .RST_VAL(1'd0)
   ) w_busy_d_reg (
       `include "iob_axi_m_wrtie_dma_iob_clk_s_s_portmap.vs"
       .rst_i (rst_i),
       .data_i(w_busy_d_nxt),
       .data_o(w_busy_d)
   );

   iob_axis_s_axi_m_write #(
      .AXI_ADDR_W(AXI_ADDR_W),
      .AXI_DATA_W(AXI_DATA_W),
      .AXI_LEN_W (AXI_LEN_W),
      .AXI_ID_W  (AXI_ID_W)
   ) axis_s_axi_m_write_inst (
       `include "iob_axi_m_wrtie_dma_iob_clk_s_s_portmap.vs"
       .rst_i(rst_i),

       `include "iob_axi_m_wrtie_dma_axi_write_m_m_portmap.vs"

       .w_addr_i          (burst_addr),
       .w_length_i        (burst_length_decr),
       .w_start_transfer_i(start_burst),
       .w_burst_type_i    (w_burst_type_i),
       .w_busy_o          (busy),
       .w_resp_o          (w_resp_o),

       .axis_in_data_i (axis_tdata_int),
       .axis_in_valid_i(axis_tvalid_int),
       .axis_in_ready_o(axis_tready_int)
   );

endmodule
