# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

include $(GPIO_DIR)/hardware/hardware.mk

DEFINE+=$(defmacro)VCD

VSRC+=$(wildcard $(GPIO_HW_DIR)/testbench/*.v)
