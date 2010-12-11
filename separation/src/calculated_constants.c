/*
Copyright 2008-2010 Travis Desell, Dave Przybylo, Nathan Cole, Matthew Arsenault,
Boleslaw Szymanski, Heidi Newberg, Carlos Varela, Malik Magdon-Ismail
and Rensselaer Polytechnic Institute.

This file is part of Milkway@Home.

Milkyway@Home is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Milkyway@Home is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Milkyway@Home.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "separation_types.h"
#include "separation_constants.h"
#include "calculated_constants.h"
#include "milkyway_util.h"
#include "milkyway_math.h"
#include "coordinates.h"
#include "gauss_legendre.h"
#include "integrals.h"
#include "integrals_common.h"

static inline mwvector streamA(real* parameters)
{
    mwvector a;
    X(a) = mw_sin(parameters[2]) * mw_cos(parameters[3]);
    Y(a) = mw_sin(parameters[2]) * mw_sin(parameters[3]);
    Z(a) = mw_cos(parameters[2]);
    W(a) = 0.0;
    return a;
}

static inline mwvector streamC(const AstronomyParameters* ap, int wedge, real mu, real r)
{
    LB lb;
    mwvector lbr;

    lb = gc2lb(wedge, mu, 0.0);

    L(lbr) = LB_L(lb);
    B(lbr) = LB_B(lb);
    R(lbr) = r;
    W(lbr) = 0.0;
    return lbr2xyz(ap, lbr);
}
int setAstronomyParameters(AstronomyParameters* ap, const BackgroundParameters* bgp)

{
    ap->alpha = bgp->parameters[0];
    ap->q     = bgp->parameters[1];

    ap->r0    = bgp->parameters[2];
    ap->delta = bgp->parameters[3];

    ap->q_inv_sqr = inv(sqr(ap->q));

    if (ap->aux_bg_profile)
    {
        ap->bg_a = bgp->parameters[4];
        ap->bg_b = bgp->parameters[5];
        ap->bg_c = bgp->parameters[6];
    }
    else
    {
        ap->bg_a = 0.0;
        ap->bg_b = 0.0;
        ap->bg_c = 0.0;
    }

    if (ap->sgr_coordinates)
    {
        warn("gc2sgr not implemented\n");
        return 1;
    }

    ap->coeff = 1.0 / (stdev * SQRT_2PI);
    ap->alpha_delta3 = 3.0 - ap->alpha + ap->delta;

    ap->fast_h_prob = (ap->alpha == 1 && ap->delta == 1);

    ap->sun_r0 = const_sun_r0;
    ap->m_sun_r0 = -ap->sun_r0;

  #if !SEPARATION_OPENCL
    ap->bg_prob_func = ap->fast_h_prob ? bg_probability_fast_hprob : bg_probability_slow_hprob;
  #endif /* !SEPARATION_OPENCL */

    return 0;
}

StreamConstants* getStreamConstants(const AstronomyParameters* ap, const Streams* streams)

{
    unsigned int i;
    StreamConstants* sc;
    real stream_sigma;
    real sigma_sq2;

    sc = (StreamConstants*) mwMallocA(sizeof(StreamConstants) * streams->number_streams);

    for (i = 0; i < streams->number_streams; i++)
    {
        stream_sigma = streams->parameters[i].stream_parameters[4];
        sc[i].large_sigma = (stream_sigma > SIGMA_LIMIT || stream_sigma < -SIGMA_LIMIT);
        sigma_sq2 = 2.0 * sqr(stream_sigma);
        sc[i].sigma_sq2_inv = 1.0 / sigma_sq2;

        sc[i].a = streamA(streams->parameters[i].stream_parameters);
        sc[i].c = streamC(ap,
                          ap->wedge,
                          streams->parameters[i].stream_parameters[0],
                          streams->parameters[i].stream_parameters[1]);
    }

    return sc;
}

void freeStreamGauss(StreamGauss sg)
{
    mwFreeA(sg.dx);
    mwFreeA(sg.qgaus_W);
}

StreamGauss getStreamGauss(const unsigned int convolve)
{
    unsigned int i;
    StreamGauss sg;
    real* qgaus_X;

    qgaus_X = (real*) mwMallocA(sizeof(real) * convolve);
    sg.qgaus_W = (real*) mwMallocA(sizeof(real) * convolve);

    gaussLegendre(-1.0, 1.0, qgaus_X, sg.qgaus_W, convolve);

    sg.dx = (real*) mwMallocA(sizeof(real) * convolve);

    for (i = 0; i < convolve; ++i)
        sg.dx[i] = 3.0 * stdev * qgaus_X[i];

    mwFreeA(qgaus_X);

    return sg;
}

NuConstants* prepareNuConstants(const unsigned int nu_steps, const real nu_step_size, const real nu_min)
{
    unsigned int i;
    real tmp1, tmp2;
    NuConstants* nu_consts;

    nu_consts = (NuConstants*) mwMallocA(sizeof(NuConstants) * nu_steps);

    for (i = 0; i < nu_steps; ++i)
    {
        nu_consts[i].nu = nu_min + (i * nu_step_size);

        tmp1 = d2r(90.0 - nu_consts[i].nu - nu_step_size);
        tmp2 = d2r(90.0 - nu_consts[i].nu);

        nu_consts[i].id = mw_cos(tmp1) - mw_cos(tmp2);
        nu_consts[i].nu += 0.5 * nu_step_size;
    }

    return nu_consts;
}

NuId calcNuStep(const IntegralArea* ia, const unsigned int nu_step)
{
    NuId nuid;
    real tmp1, tmp2;

    nuid.nu = ia->nu_min + (nu_step * ia->nu_step_size);

    tmp1 = d2r(90.0 - nuid.nu - ia->nu_step_size);
    tmp2 = d2r(90.0 - nuid.nu);

    nuid.id = mw_cos(tmp1) - mw_cos(tmp2);
    nuid.nu += 0.5 * ia->nu_step_size;

    return nuid;
}

LBTrig* precalculateLBTrig(const AstronomyParameters* ap, const IntegralArea* ia)
{
    unsigned int i, j;
    LBTrig* lbts;
    NuId nuid;
    LB lb;
    real mu;

    lbts = (LBTrig*) mwMallocA(sizeof(LBTrig) * ia->mu_steps * ia->nu_steps);

    for (i = 0; i < ia->nu_steps; ++i)
    {
        nuid = calcNuStep(ia, i);
        for (j = 0; j < ia->mu_steps; ++j)
        {
            mu = ia->mu_min + (((real) j + 0.5) * ia->mu_step_size);
            lb = gc2lb(ap->wedge, mu, nuid.nu);
            lbts[i * ia->mu_steps + j] = lb_trig(lb);
        }
    }

    return lbts;
}

