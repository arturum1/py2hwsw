# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT


def setup(py_params_dict):
    # System parameters passed by issuer
    params = py_params_dict["iob_system_params"]

    attributes_dict = {
        "name": params["name"] + "_iob_smart_zynq_sl",
        "generate_hw": True,
    }

    #
    # Configuration
    #
    attributes_dict["confs"] = [
        {
            "name": "AXI_ID_W",
            "descr": "AXI ID bus width",
            "type": "D",
            "val": "4",
            "min": "1",
            "max": "32",
        },
        {
            "name": "AXI_LEN_W",
            "descr": "AXI burst length width",
            "type": "D",
            "val": "8",
            "min": "1",
            "max": "8",
        },
        {
            "name": "AXI_ADDR_W",
            "descr": "AXI address bus width. Smart Zynq SL has 512 MiB of DDR3 memory.",
            "type": "D",
            "val": "27",
            "min": "1",
            "max": "32",
        },
        {
            "name": "AXI_DATA_W",
            "descr": "AXI data bus width.",
            "type": "D",
            "val": "32",
            "min": "1",
            "max": "32",
        },
        {
            "name": "BAUD",
            "descr": "UART baud rate",
            "type": "D",
            "val": "115200",
        },
        {
            "name": "FREQ",
            "descr": "Clock frequency",
            "type": "D",
            "val": "50000000",
        },
        {
            "name": "XILINX",
            "descr": "xilinx flag",
            "type": "D",
            "val": "1",
        },
    ]

    #
    # Ports
    #
    attributes_dict["ports"] = [
        {
            "name": "rs232_io",
            "descr": "Serial port",
            "signals": [
                {"name": "uart_rxd_i", "width": "1"},
                {"name": "uart_txd_o", "width": "1"},
            ],
        },
        {
            "name": "leds_o",
            "descr": "debug leds",
            "signals": [
                {"name": "led1_o", "width": "1"},
                {"name": "led2_o", "width": "1"},
            ],
        },
        {
            "name": "ps7_io",
            "descr": "Silicon fixed IO for Zynq PS7",
            "signals": [
                {"name": "DDR_CAS_n_io", "width": "1"},
                {"name": "DDR_CKE_io", "width": "1"},
                {"name": "DDR_Clk_n_io", "width": "1"},
                {"name": "DDR_Clk_io", "width": "1"},
                {"name": "DDR_CS_n_io", "width": "1"},
                {"name": "DDR_DRSTB_io", "width": "1"},
                {"name": "DDR_ODT_io", "width": "1"},
                {"name": "DDR_RAS_n_io", "width": "1"},
                {"name": "DDR_WEB_io", "width": "1"},
                {"name": "DDR_BankAddr_io", "width": "3"},
                {"name": "DDR_Addr_io", "width": "15"},
                {"name": "DDR_VRN_io", "width": "1"},
                {"name": "DDR_VRP_io", "width": "1"},
                {"name": "DDR_DM_io", "width": "4"},
                {"name": "DDR_DQ_io", "width": "32"},
                {"name": "DDR_DQS_n_io", "width": "4"},
                {"name": "DDR_DQS_io", "width": "4"},
                {"name": "PS_SRSTB_io", "width": "1"},
                {"name": "PS_CLK_io", "width": "1"},
                {"name": "PS_PORB_io", "width": "1"},
            ],
        },
    ]
    if params["use_ethernet"]:
        attributes_dict["ports"] += [
            {
                "name": "rgmii_io",
                "descr": "RGMII ethernet interface",
                "signals": {
                    "type": "mii",
                    "widths": {
                        "VARIANT": "rgmii",
                    },
                },
            },
        ]

    #
    # Wires
    #
    attributes_dict["wires"] = [
        {
            "name": "clk_en_rst",
            "descr": "Clock, clock enable and reset",
            "signals": {
                "type": "iob_clk",
            },
        },
        {
            "name": "arst_n",
            "descr": "Negated reset",
            "signals": [
                {"name": "arst_n", "width": "1"},
            ],
        },
        {
            "name": "rs232_int",
            "descr": "IOb_System UART interface",
            "signals": {
                "type": "rs232",
            },
        },
    ]

    if params["use_extmem"]:
        attributes_dict["wires"] += [
            {
                "name": "axi",
                "descr": "AXI interface to connect SoC to memory",
                "signals": {
                    "type": "axi",
                    "ID_W": "AXI_ID_W",
                    "LEN_W": "AXI_LEN_W",
                    "ADDR_W": "AXI_ADDR_W",
                    "DATA_W": "AXI_DATA_W",
                },
            },
        ]

    if params["use_ethernet"]:
        attributes_dict["wires"] += [
            # eth clock
            {
                "name": "rxclk_buf_io",
                "descr": "IBUFG io",
                "signals": [
                    {"name": "enet_rx_clk_i"},
                    {"name": "eth_clk", "width": "1"},
                ],
            },
            {
                "name": "oddre1_io",
                "descr": "ODDRE1 io",
                "signals": [
                    {"name": "enet_gtx_clk_o"},
                    {"name": "eth_clk"},
                    {"name": "high"},
                    {"name": "low", "width": "1"},
                    {
                        "name": "enet_resetn_inv",
                        "width": "1",
                    },
                ],
            },
            {
                "name": "phy",
                "descr": "PHY Interface Ports",
                "signals": [
                    {"name": "eth_MTxClk", "width": "1"},
                    {"name": "MTxEn", "width": "1"},
                    {"name": "MTxD", "width": "4"},
                    {"name": "MTxErr", "width": "1"},
                    {"name": "eth_MRxClk", "width": "1"},
                    {"name": "MRxDv", "width": "1"},
                    {"name": "MRxD", "width": "4"},
                    {"name": "MRxErr", "width": "1"},
                    {"name": "eth_MColl", "width": "1"},
                    {"name": "eth_MCrS", "width": "1"},
                    {"name": "MDC", "width": "1"},
                    {"name": "MDIO", "width": "1"},
                    {"name": "phy_rstn", "width": "1"},
                ],
            },
        ]

    #
    # Blocks
    #
    attributes_dict["subblocks"] = [
        {
            "core_name": py_params_dict["issuer"]["original_name"],
            "instance_name": py_params_dict["issuer"]["original_name"],
            "instance_description": "Issuer of this fpga wrapper module. Normally the IOb-System memory wrapper.",
            "parameters": {
                "AXI_ID_W": "AXI_ID_W",
                "AXI_LEN_W": "AXI_LEN_W",
                "AXI_ADDR_W": "AXI_ADDR_W",
                "AXI_DATA_W": "AXI_DATA_W",
            },
            "connect": {
                "clk_en_rst_s": "clk_en_rst",
                "rs232_m": "rs232_int",
            },
            "dest_dir": "hardware/common_src",
        },
    ]
    if params["use_extmem"]:
        attributes_dict["subblocks"][-1]["connect"].update({"axi_m": "axi"})
    if params["use_ethernet"]:
        attributes_dict["subblocks"][-1]["connect"].update({"phy_io": "phy"})

    #
    # Snippets
    #

    snippet = """
   // General connections
   assign cke = 1'b1;
   assign arst = ~arst_n;

   assign uart_txd_o = rs232_txd;
   assign rs232_rxd = uart_rxd_i;
   assign rs232_cts = 1'b1;

   // DEBUG LEDS
   localparam T1MS = 26'd50_000_000 ; //50MHz - Timer target reached in 1 second
   reg [25:0] time_count=26'd0;
   reg led_reg=1'b0;
   always@(posedge clk)
       if(time_count>=T1MS)begin
           time_count<=26'd0;
           led_reg<=~led_reg;
       end
       else time_count<=time_count+1'b1;
   assign led1_o=led_reg;
   assign led2_o=arst;

   // ZYNQ7 Processing System module
   zynq_design_processing_system7_0_0 processing_system7_0
   (
      // Silicon fixed ports (non-configurable)
      .MIO(),
      .DDR_CAS_n(DDR_CAS_n_io),
      .DDR_CKE(DDR_CKE_io),
      .DDR_Clk_n(DDR_Clk_n_io),
      .DDR_Clk(DDR_Clk_io),
      .DDR_CS_n(DDR_CS_n_io),
      .DDR_DRSTB(DDR_DRSTB_io),
      .DDR_ODT(DDR_ODT_io),
      .DDR_RAS_n(DDR_RAS_n_io),
      .DDR_WEB(DDR_WEB_io),
      .DDR_BankAddr(DDR_BankAddr_io),
      .DDR_Addr(DDR_Addr_io),
      .DDR_VRN(DDR_VRN_io),
      .DDR_VRP(DDR_VRP_io),
      .DDR_DM(DDR_DM_io),
      .DDR_DQ(DDR_DQ_io),
      .DDR_DQS_n(DDR_DQS_n_io),
      .DDR_DQS(DDR_DQS_io),
      .PS_SRSTB(PS_SRSTB_io),
      .PS_CLK(PS_CLK_io),
      .PS_PORB(PS_PORB_io),

      // Configurable ports
      .FCLK_CLK0(clk),
      .FCLK_RESET0_N(arst_n),
"""
    if params["use_extmem"]:
        snippet += """
   //.HP0(axi_araddr),
   //.HP0(axi_arvalid),
   //.HP0(axi_arready),
   //.HP0(axi_rdata),
   //.HP0(axi_rresp),
   //.HP0(axi_rvalid),
   //.HP0(axi_rready),
   //.HP0(axi_arid),
   //.HP0(axi_arlen),
   //.HP0(axi_arsize),
   //.HP0(axi_arburst),
   //.HP0(axi_arlock),
   //.HP0(axi_arcache),
   //.HP0(axi_arqos),
   //.HP0(axi_rid),
   //.HP0(axi_rlast),
   //.HP0(axi_awaddr),
   //.HP0(axi_awvalid),
   //.HP0(axi_awready),
   //.HP0(axi_wdata),
   //.HP0(axi_wstrb),
   //.HP0(axi_wvalid),
   //.HP0(axi_wready),
   //.HP0(axi_bresp),
   //.HP0(axi_bvalid),
   //.HP0(axi_bready),
   //.HP0(axi_awid),
   //.HP0(axi_awlen),
   //.HP0(axi_awsize),
   //.HP0(axi_awburst),
   //.HP0(axi_awlock),
   //.HP0(axi_awcache),
   //.HP0(axi_awqos),
   //.HP0(axi_wlast),
   //.HP0(axi_bid),
"""
    # Remove last comma
    lines = snippet.splitlines()
    lines[-1] = lines[-1].rstrip(",")
    snippet = "\n".join(lines)

    snippet += """
   );
"""

    attributes_dict["snippets"] = [
        {
            "verilog_code": snippet,
        },
    ]

    return attributes_dict
