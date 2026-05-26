// SPDX-FileCopyrightText: 2026 IObundle
//
// SPDX-License-Identifier: MIT

`timescale 1ns / 1ps

/*
AXI Master interface
   This unit breaks down an AXIS into multiple bursts of AXI.
   Address (and length) are set by using the write_ or read_ interfaces.
   The busy signals can be used to probe the state of the transfer. When asserted,
   they indicate that the unit is doing a data transfer.
   Both AXIStream Master and AXIStream Slave operate individually and can work simultaneously (these units can also
   be instantiated individually)
   4k boundaries are handled automatically.

AXIStream Master:
   After configuring read_addr and read_length, the transfer can start by setting the
   read_start_transfer signal. There is no limit to the amount of data that can be sent.

AXIStream Slave:
   After configuring write_addr and write_length, the transfer can start by setting the
   write_start_transfer signal.
   Length is given as the amount of dwords. A length of 1 means that one transfer is performed.

Note: if the transfer goes over the maximum size, given by AXI_ADDR_W,
   the transfer will wrap around and will start reading/writing to the lower addresses.
*/

module iob_axi_m #(
   parameter AXI_ADDR_W  = 0,
   parameter AXI_LEN_W   = 8,
   parameter AXI_DATA_W  = 32,
   parameter AXI_ID_W    = 1,
   parameter WLENGTH_W   = 0,
   parameter RLENGTH_W   = 0,
   parameter FIFO_ADDR_W = 0
) (
   // Global signals
   `include "iob_axi_m_iob_clk_s_port.vs"
   input rst_i,

   // Configuration IO's
   input  [AXI_ADDR_W-1:0] w_addr_i,
   input  [ WLENGTH_W-1:0] w_length_i,
   input                   w_start_transfer_i,
   input  [ AXI_LEN_W-1:0] w_max_len_i,
   input  [         2-1:0] w_burst_type_i,
   output [ WLENGTH_W-1:0] w_remaining_data_o,
   output                  w_busy_o,

   input  [AXI_ADDR_W-1:0] r_addr_i,
   input  [ RLENGTH_W-1:0] r_length_i,
   input                   r_start_transfer_i,
   input  [ AXI_LEN_W-1:0] r_max_len_i,
   input  [         2-1:0] r_burst_type_i,
   output [ RLENGTH_W-1:0] r_remaining_data_o,
   output                  r_busy_o,

   // AXIStream Interfaces
   input  [AXI_DATA_W-1:0] axis_in_data_i,
   input                   axis_in_valid_i,
   output                  axis_in_ready_o,

   output [AXI_DATA_W-1:0] axis_out_data_o,
   output                  axis_out_valid_o,
   input                   axis_out_ready_i,

   // External Memory interface
   output                  w_ext_mem_clk_o,
   output                  w_ext_mem_w_en_o,
   output [ AXI_LEN_W-1:0] w_ext_mem_w_addr_o,
   output [AXI_DATA_W-1:0] w_ext_mem_w_data_o,
   output                  w_ext_mem_r_en_o,
   output [ AXI_LEN_W-1:0] w_ext_mem_r_addr_o,
   input  [AXI_DATA_W-1:0] w_ext_mem_r_data_i,

   output                  r_ext_mem_clk_o,
   output                  r_ext_mem_w_en_o,
   output [ AXI_LEN_W-1:0] r_ext_mem_w_addr_o,
   output [AXI_DATA_W-1:0] r_ext_mem_w_data_o,
   output                  r_ext_mem_r_en_o,
   output [ AXI_LEN_W-1:0] r_ext_mem_r_addr_o,
   input  [AXI_DATA_W-1:0] r_ext_mem_r_data_i,

   // AXI master interface
   `include "iob_axi_m_axi_m_port.vs"
);


   // Drive memory clock from system clock
   assign r_ext_mem_clk_o = clk_i;
   assign w_ext_mem_clk_o = clk_i;

   // AXI Master read, AXIStream master
   iob_axi_m_read #(
      .AXI_ADDR_W (AXI_ADDR_W),
      .AXI_LEN_W  (AXI_LEN_W),
      .AXI_DATA_W (AXI_DATA_W),
      .AXI_ID_W   (AXI_ID_W),
      .RLENGTH_W  (RLENGTH_W),
      .FIFO_ADDR_W(FIFO_ADDR_W)
   ) axi_m_read_inst (
       `include "iob_axi_m_iob_clk_s_s_portmap.vs"
       .rst_i(rst_i),

       .r_addr_i          (r_addr_i),
       .r_length_i        (r_length_i),
       .r_start_transfer_i(r_start_transfer_i),
       .r_max_len_i       (r_max_len_i),
       .r_burst_type_i    (r_burst_type_i),
       .r_remaining_data_o(r_remaining_data_o),
       .r_busy_o          (r_busy_o),

       .axis_out_tdata_o (axis_out_data_o),
       .axis_out_tvalid_o(axis_out_valid_o),
       .axis_out_tready_i(axis_out_ready_i),

       .ext_mem_w_en_o  (r_ext_mem_w_en_o),
       .ext_mem_w_addr_o(r_ext_mem_w_addr_o),
       .ext_mem_w_data_o(r_ext_mem_w_data_o),
       .ext_mem_r_en_o  (r_ext_mem_r_en_o),
       .ext_mem_r_addr_o(r_ext_mem_r_addr_o),
       .ext_mem_r_data_i(r_ext_mem_r_data_i),

       `include "iob_axi_m_read_axi_read_m_m_portmap.vs"
   );

   // AXI Master write, AXIStream slave
   iob_axi_m_write #(
      .AXI_ADDR_W (AXI_ADDR_W),
      .AXI_LEN_W  (AXI_LEN_W),
      .AXI_DATA_W (AXI_DATA_W),
      .AXI_ID_W   (AXI_ID_W),
      .WLENGTH_W  (WLENGTH_W),
      .FIFO_ADDR_W(FIFO_ADDR_W)
   ) axi_m_write_inst (
       `include "iob_axi_m_iob_clk_s_s_portmap.vs"
       .rst_i(rst_i),

       .w_addr_i          (w_addr_i),
       .w_length_i        (w_length_i),
       .w_start_transfer_i(w_start_transfer_i),
       .w_max_len_i       (w_max_len_i),
       .w_burst_type_i    (w_burst_type_i),
       .w_remaining_data_o(w_remaining_data_o),
       .w_busy_o          (w_busy_o),

       .axis_in_data_i (axis_in_data_i),
       .axis_in_valid_i(axis_in_valid_i),
       .axis_in_ready_o(axis_in_ready_o),

       .ext_mem_w_en_o  (w_ext_mem_w_en_o),
       .ext_mem_w_addr_o(w_ext_mem_w_addr_o),
       .ext_mem_w_data_o(w_ext_mem_w_data_o),
       .ext_mem_r_en_o  (w_ext_mem_r_en_o),
       .ext_mem_r_addr_o(w_ext_mem_r_addr_o),
       .ext_mem_r_data_i(w_ext_mem_r_data_i),

       `include "iob_axi_m_write_axi_write_m_m_portmap.vs"
   );

endmodule
