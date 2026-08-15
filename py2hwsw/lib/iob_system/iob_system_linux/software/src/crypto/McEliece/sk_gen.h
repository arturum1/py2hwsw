/*
 * SPDX-FileCopyrightText: 2026 IObundle
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SK_GEN_H
#define SK_GEN_H
/*
  This file is for secret-key generation
*/

#include "namespace.h"

#define genpoly_gen CRYPTO_NAMESPACE(genpoly_gen)

#include "gf.h"

#include <stdint.h>

int genpoly_gen(gf *out, gf *f);

#endif
