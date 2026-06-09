# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

## Synchronizers
set_property ASYNC_REG TRUE [get_cells -hier {*iob_sync_reg_data_o*[*]}]
