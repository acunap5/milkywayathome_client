/*
 * Copyright (c) 2012 Rensselaer Polytechnic Institute
 *
 * This file is part of Milkway@Home.
 *
 * Milkyway@Home is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Milkyway@Home is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Milkyway@Home.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef _NBODY_MASS_H_
#define _NBODY_MASS_H_

#include "nbody_types.h"
#include "milkyway_math.h"

#ifdef __cplusplus
extern "C" {
#endif

real probability_match(int n, real k, real pobs);

real GammaFunc(const real z);

real IncompleteGammaFunc(real a, real x);

real nbCostComponent(const NBodyHistogram* data, const NBodyHistogram* histogram);

real calc_vLOS(const mwvector v, const mwvector p, real sunGCdist);

real nbVelocityDispersion(const NBodyHistogram* data, const NBodyHistogram* histogram);

#ifdef __cplusplus
}
#endif

#endif
