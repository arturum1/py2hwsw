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
            "name": "rgmii_io",
            "descr": "RGMII ethernet interface",
            "signals": [
                {
                    "name": "rgmii_txc_o",
                    "width": "1",
                    "descr": "Clock signal",
                },
                {
                    "name": "rgmii_txd_o",
                    "width": "4",
                    "descr": "Data to be transmitted",
                },
                {
                    "name": "rgmii_tx_ctl_o",
                    "width": "1",
                    "descr": "Multiplexing of transmitter enable and transmitter error",
                },
                {
                    "name": "rgmii_rxc_i",
                    "width": "1",
                    "descr": "Received clock signal (recovered from incoming received data)",
                },
                {
                    "name": "rgmii_rxd_i",
                    "width": "4",
                    "descr": "Received data",
                },
                {
                    "name": "rgmii_rx_ctl_i",
                    "width": "1",
                    "descr": "Multiplexing of data received is valid and receiver error",
                },
                {
                    "name": "rgmii_mdc_o",
                    "width": "1",
                    "descr": "Management interface clock",
                },
                {
                    "name": "rgmii_mdio_io",
                    "width": "1",
                    "descr": "Management interface I/O",
                },
            ],
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
    attributes_dict["snippets"] = [
        {
            "verilog_code": """
   // General connections
   assign cke = 1'b1;
   assign arst = ~arst_n;

   assign uart_txd_o = rs232_txd;
   assign rs232_rxd = uart_rxd_i;
   assign rs232_cts = 1'b1;

   // ZYNQ7 Processing System module
   processing_system7_0 processing_system7_0
   (
      .PS_CLK(FIXED_IO_ps_clk_io),
      .PS_PORB(FIXED_IO_ps_porb_io),
      .PS_SRSTB(FIXED_IO_ps_srstb_io),

      .FCLK_CLK0(clk),
      .FCLK_RESET0_N(arst_n),

      .DDR_Addr(DDR_addr),
      .DDR_BankAddr(DDR_ba),
      .DDR_CAS_n(DDR_cas_n),
      .DDR_CKE(DDR_cke),
      .DDR_CS_n(DDR_cs_n),
      .DDR_Clk(DDR_ck_p),
      .DDR_Clk_n(DDR_ck_n),
      .DDR_DM(DDR_dm),
      .DDR_DQ(DDR_dq),
      .DDR_DQS(DDR_dqs_p),
      .DDR_DQS_n(DDR_dqs_n),
      .DDR_DRSTB(DDR_reset_n),
      .DDR_ODT(DDR_odt),
      .DDR_RAS_n(DDR_ras_n),
      .DDR_VRN(FIXED_IO_ddr_vrn),
      .DDR_VRP(FIXED_IO_ddr_vrp),
      .DDR_WEB(DDR_we_n)
   );
            """,
        },
    ]

    return attributes_dict
