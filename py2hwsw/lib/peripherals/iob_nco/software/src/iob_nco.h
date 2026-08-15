/*
 * SPDX-FileCopyrightText: 2026 IObundle
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#pragma once
#include "iob_nco_csrs.h"
#include <stdbool.h>

// Functions
void nco_reset();
void nco_init(uint32_t base_address);
void nco_enable(bool enable);
void nco_set_period(uint64_t period);
