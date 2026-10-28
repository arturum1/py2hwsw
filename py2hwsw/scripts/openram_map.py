#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

"""OpenRAM memory mapping for py2hwsw cores."""


def get_openram_recipe(mem_info, params=None):
    """Get OpenRAM recipe for a memory instance.
    
    Returns None if no OpenRAM recipe is available for this memory.
    """
    mem_type = mem_info.get("type", "")
    addr_w = mem_info.get("addr_w", 0)
    data_w = mem_info.get("data_w", 32)
    
    # Calculate number of words
    num_words = 1 << addr_w if addr_w > 0 else 1
    
    if mem_type.startswith("iob_ram_t2p"):
        # 1RW + 1R port SRAM
        name = f"openram_sram_1rw1r_{data_w}x{num_words}"
        return {
            "name": name,
            "type": "sram",
            "num_words": num_words,
            "word_size": data_w,
            "write_size": data_w,
            "num_rw_ports": 1,
            "num_r_ports": 1,
            "num_w_ports": 0,
            "tech_name": "sky130",
            "nominal_corner_only": True,
        }
    elif mem_type.startswith("iob_ram_t2p_be"):
        # 1RW + 1R with byte enable
        name = f"openram_sram_1rw1r_{data_w}x{num_words}_be"
        return {
            "name": name,
            "type": "sram",
            "num_words": num_words,
            "word_size": data_w,
            "write_size": 8,
            "num_rw_ports": 1,
            "num_r_ports": 1,
            "num_w_ports": 0,
            "tech_name": "sky130",
            "nominal_corner_only": True,
        }
    elif mem_type.startswith("iob_rom_"):
        # ROM
        hexfile = mem_info.get("hexfile") or params.get("HEXFILE") or "bootrom.hex"
        name = f"openram_rom_{data_w}x{num_words}"
        return {
            "name": name,
            "type": "rom",
            "num_words": num_words,
            "word_size": data_w // 8 if data_w % 8 == 0 else data_w,
            "rom_data": hexfile,
            "data_type": "hex" if hexfile.endswith(".hex") else "bin",
            "tech_name": "sky130",
            "nominal_corner_only": True,
        }
    
    return None


# Default mapping
MEMORY_OPENRAM_MAP = {}
