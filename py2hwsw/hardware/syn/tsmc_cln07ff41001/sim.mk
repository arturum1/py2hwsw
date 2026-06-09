# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

LIBFILE=$(LIBDIR)/sch240mc_base_svt_c11/r12p0/lib/sch240mc_cln07ff41001_base_svt_c11_ssgnp_cworstccworstt_max_0p75v_25c.lib

ifneq ($(wildcard $(LIBFILE)),)
VSRC+= $(LIBFILE)
endif
