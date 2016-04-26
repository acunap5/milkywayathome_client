/*
 * Copyright (c) 2010 The University of Texas at Austin
 * Copyright (c) 2010 Dr. Martin Burtscher
 * Copyright (c) 2011-2012 Matthew Arsenault
 * Copyright (c) 2011 Rensselaer Polytechnic Institute
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

/* In case there isn't a space a space between the -D and the
 * symbol. if the thing begins with D there's an Apple OpenCL compiler
 * bug on 10.6 where the D will be stripped. -DDOUBLEPREC=1 will
 * actually define OUBLEPREC */

#ifdef OUBLEPREC
  #define DOUBLEPREC OUBLEPREC
#endif

#ifdef EBUG
  #define DEBUG EBUG
#endif

#ifdef ISK_MASS
  #define DISK_MASS ISK_MASS
#endif

#ifdef ISK_SCALE_LENGTH
  #define DISK_SCALE_LENGTH ISK_SCALE_LENGTH
#endif

#ifdef ISK_SCALE_HEIGHT
  #define DISK_SCALE_HEIGHT ISK_SCALE_HEIGHT
#endif


#ifndef DOUBLEPREC
  #error Precision not defined
#endif


#if !BH86 && !SW93 && !NEWCRITERION && !EXACT
  #error Opening criterion not set
#endif

#if USE_EXTERNAL_POTENTIAL && ((!MIYAMOTO_NAGAI_DISK && !EXPONENTIAL_DISK) || (!LOG_HALO && !NFW_HALO && !TRIAXIAL_HALO))
  #error Potential defines misspecified
#endif

#if WARPSIZE <= 0
  #error Invalid warp size
#endif

/* These were problems when being lazy and writing it */
#if (THREADS6 / WARPSIZE) <= 0
  #error (THREADS6 / WARPSIZE) must be > 0
#elif (MAXDEPTH * THREADS6 / WARPSIZE) <= 0
  #error (MAXDEPTH * THREADS6 / WARPSIZE) must be > 0
#endif

#if DEBUG && cl_amd_printf
  #pragma OPENCL EXTENSION cl_amd_printf : enable
#endif

#if DOUBLEPREC
  /* double precision is optional core feature in 1.2, not an extension */
  #if __OPENCL_VERSION__ < 120
    #if cl_khr_fp64
      #pragma OPENCL EXTENSION cl_khr_fp64 : enable
    #elif cl_amd_fp64
      #pragma OPENCL EXTENSION cl_amd_fp64 : enable
    #else
      #error Missing double precision extension
    #endif
  #endif
#endif /* DOUBLEPREC */


#pragma OPENCL EXTENSION cl_khr_global_int32_base_atomics : enable
#pragma OPENCL EXTENSION cl_khr_global_int32_extended_atomics : enable
#pragma OPENCL EXTENSION cl_khr_local_int32_base_atomics : enable


/* Reserve positive numbers for reporting depth > MAXDEPTH. Should match on host */
typedef enum
{
    NBODY_KERNEL_OK                   = 0,
    NBODY_KERNEL_CELL_OVERFLOW        = -1,
    NBODY_KERNEL_TREE_INCEST          = -2,
    NBODY_KERNEL_TREE_STRUCTURE_ERROR = -3,
    NBODY_KERNEL_ERROR_OTHER          = -4
} NBodyKernelError;

#if DEBUG
/* Want first failed assertion to be where it is marked */
#define cl_assert(treeStatus, x)                        \
    do                                                  \
    {                                                   \
      if (!(x))                                         \
      {                                                 \
          if ((treeStatus)->assertionLine < 0)          \
          {                                             \
              (treeStatus)->assertionLine = __LINE__;   \
          }                                             \
      }                                                 \
    }                                                   \
    while (0)

#define cl_assert_rtn(treeStatus, x)                    \
    do                                                  \
    {                                                   \
      if (!(x))                                         \
      {                                                 \
          if ((treeStatus)->assertionLine < 0)          \
          {                                             \
              (treeStatus)->assertionLine = __LINE__;   \
          }                                             \
          return;                                       \
      }                                                 \
    }                                                   \
    while (0)

#else
#define cl_assert(treeStatus, x)
#define cl_assert_rtn(treeStatus, x)
#endif /* DEBUG */


#if DOUBLEPREC
typedef double real;
typedef double2 real2;
typedef double4 real4;
#else
typedef float real;
typedef float2 real2;
typedef float4 real4;
#endif /* DOUBLEPREC */


#if DOUBLEPREC
  #define REAL_EPSILON DBL_EPSILON
  #define REAL_MAX DBL_MAX
  #define REAL_MIN DBL_MIN
#else
  #define REAL_EPSILON FLT_EPSILON
  #define REAL_MAX FLT_MAX
  #define REAL_MIN FLT_MIN
#endif


#define sqr(x) ((x) * (x))
#define cube(x) ((x) * (x) * (x))

#define NSUB 8

#define isBody(n) ((n) < NBODY)
#define isCell(n) ((n) >= NBODY)

#define NULL_BODY (-1)
#define LOCK (-2)


/* This needs to be the same as on the host */
typedef struct __attribute__((aligned(64)))
{
    real radius;
    int bottom;
    uint maxDepth;
    uint blkCnt;
    int doneCnt;

    int errorCode;
    int assertionLine;

    char _pad[64 - (1 * sizeof(real) + 6 * sizeof(int))];

    struct
    {
        real f[32];
        int i[64];
        int wg1[256];
        int wg2[256];
        int wg3[256];
        int wg4[256];
    } debug;
} TreeStatus;


typedef struct
{
    real xx, xy, xz;
    real yy, yz;
    real zz;
} QuadMatrix;

//Structure that holds flattened GPU tree:
typedef struct 
{
    real pos[3];
    real vel[3];
    real acc[3];
    
    real mass;
    
    unsigned int next;
    unsigned int more;
    
    int isBody;
    struct
    {
        real xx, xy, xz;
        real yy, yz;
        real zz;
    }quad;
}gpuTree;

//gpuTree pointer:
typedef __global volatile gpuTree* restrict GTPtr;
typedef __global volatile real* restrict RVPtr;
typedef __global volatile int* restrict IVPtr;



inline real4 sphericalAccel(real4 pos, real r)
{
    const real tmp = SPHERICAL_SCALE + r;

    return (-SPHERICAL_MASS / (r * sqr(tmp))) * pos;
}

/* gets negative of the acceleration vector of this disk component */
inline real4 miyamotoNagaiDiskAccel(real4 pos, real r)
{
    real4 acc;
    const real a   = DISK_SCALE_LENGTH;
    const real b   = DISK_SCALE_HEIGHT;
    const real zp  = sqrt(sqr(pos.z) + sqr(b));
    const real azp = a + zp;

    const real rp  = sqr(pos.x) + sqr(pos.y) + sqr(azp);
    const real rth = sqrt(cube(rp));  /* rp ^ (3/2) */

    acc.x = -DISK_MASS * pos.x / rth;
    acc.y = -DISK_MASS * pos.y / rth;
    acc.z = -DISK_MASS * pos.z * azp / (zp * rth);
    acc.w = 0.0;

    return acc;
}

inline real4 exponentialDiskAccel(real4 pos, real r)
{
    const real b = DISK_SCALE_LENGTH;

    const real expPiece = exp(-r / b) * (r + b) / b;
    const real factor   = DISK_MASS * (expPiece - 1.0) / cube(r);

    return factor * pos;
}

inline real4 logHaloAccel(real4 pos, real r)
{
    real4 acc;

    const real tvsqr = -2.0 * sqr(HALO_VHALO);
    const real qsqr  = sqr(HALO_FLATTEN_Z);
    const real d     = HALO_SCALE_LENGTH;
    const real zsqr  = sqr(pos.z);

    const real arst  = sqr(d) + sqr(pos.x) + sqr(pos.y);
    const real denom = (zsqr / qsqr) +  arst;

    acc.x = tvsqr * pos.x / denom;
    acc.y = tvsqr * pos.y / denom;
    acc.z = tvsqr * pos.z / ((qsqr * arst) + zsqr);

    return acc;
}

inline real4 nfwHaloAccel(real4 pos, real r)
{
    const real a  = HALO_SCALE_LENGTH;
    const real ar = a + r;
    const real c  = a * sqr(HALO_VHALO) * (r - ar * log((a + r) / a)) / (0.2162165954 * cube(r) * ar);

    return c * pos;
}

inline real4 triaxialHaloAccel(real4 pos, real r)
{
    real4 acc;

    const real qzs      = sqr(HALO_FLATTEN_Z);
    const real rhalosqr = sqr(HALO_SCALE_LENGTH);
    const real mvsqr    = -sqr(HALO_VHALO);

    const real xsqr = sqr(pos.x);
    const real ysqr = sqr(pos.y);
    const real zsqr = sqr(pos.z);

    const real c1 = HALO_C1;
    const real c2 = HALO_C2;
    const real c3 = HALO_C3;

    const real arst  = rhalosqr + (c1 * xsqr) + (c3 * pos.x * pos.y) + (c2 * ysqr);
    const real arst2 = (zsqr / qzs) + arst;

    acc.x = mvsqr * (((2.0 * c1) * pos.x) + (c3 * pos.y) ) / arst2;

    acc.y = mvsqr * (((2.0 * c2) * pos.y) + (c3 * pos.x) ) / arst2;

    acc.z = (2.0 * mvsqr * pos.z) / ((qzs * arst) + zsqr);

    acc.w = 0.0;

    return acc;
}

inline real4 externalAcceleration(real x, real y, real z)
{
    real4 pos = { x, y, z, 0.0 };
    real r = sqrt(sqr(x) + sqr(y) + sqr(z));
    //real r = length(pos); // crashes AMD compiler
    real4 acc;

    if (MIYAMOTO_NAGAI_DISK)
    {
        acc = miyamotoNagaiDiskAccel(pos, r);
    }
    else if (EXPONENTIAL_DISK)
    {
        acc = exponentialDiskAccel(pos, r);
    }

    if (LOG_HALO)
    {
        acc += logHaloAccel(pos, r);
    }
    else if (NFW_HALO)
    {
        acc += nfwHaloAccel(pos, r);
    }
    else if (TRIAXIAL_HALO)
    {
        acc += triaxialHaloAccel(pos, r);
    }

    acc += sphericalAccel(pos, r);

    return acc;
}




/* All kernels will use the same parameters for now */

// #define NBODY_KERNEL(name) name(                        \
//     GTPtr _gTreeIn, GTPtr _gTreeOut                     \
//     )
//     

//OLD KERNEL ARGUMENTS:
#define NBODY_KERNEL(name) name(                        \
    RVPtr _posX, RVPtr _posY, RVPtr _posZ,              \
    RVPtr _velX, RVPtr _velY, RVPtr _velZ,              \
    RVPtr _accX, RVPtr _accY, RVPtr _accZ,              \
    RVPtr _mass,                                        \
                                                        \
                                                        \
    IVPtr _more, IVPtr _next,                           \
                                                        \
                                                        \
    RVPtr _quadXX, RVPtr _quadXY, RVPtr _quadXZ,        \
    RVPtr _quadYY, RVPtr _quadYZ,                       \
    RVPtr _quadZZ                                       \
    )




#if HAVE_INLINE_PTX
inline void strong_global_mem_fence_ptx()
{
    asm("{\n\t"
        "membar.gl;\n\t"
        "}\n\t"
        );
}
#endif

#if HAVE_INLINE_PTX
  #define maybe_strong_global_mem_fence() strong_global_mem_fence_ptx()
#else
  #define maybe_strong_global_mem_fence() mem_fence(CLK_GLOBAL_MEM_FENCE)
#endif /* HAVE_INLINE_PTX */


/* FIXME: should maybe have separate threadcount, but
   Should have attributes most similar to integration */


/* Used by sw93 */
inline real bmax2Inc(real cmPos, real pPos, real psize)
{
    real dmin = cmPos - (pPos - 0.5 * psize);         /* dist from 1st corner */
    real tmp = fmax(dmin, psize - dmin);
    return tmp * tmp;      /* sum max distance^2 */
}

inline bool checkTreeDim(real cmPos, real pPos, real halfPsize)
{
    return (cmPos < pPos - halfPsize || cmPos > pPos + halfPsize);
}


/*
  According to the OpenCL specification, global memory consistency is
  only guaranteed between workitems in the same workgroup.

  We rely on AMD and Nvidia GPU implementation details and pretend
  this doesn't exist when possible.

  - On AMD GPUs, mem_fence(CLK_GLOBAL_MEM_FENCE) compiles to a
  fence_memory instruction which ensures a write is not in the cache
  and is committed to memory before completing.
  We have to be more careful when it comes to reading.

  On previous AMD architectures it was sufficient to have a write
  fence and then other items, not necessarily in the same workgroup,
  would read the value committed by the fence.

  On GCN/Tahiti, the caching architecture was changed. A single
  workgroup will run on the same compute unit. A GCN compute unit has
  it's own incoherent L1 cache (and workgroups have always stayed on
  the same compute unit). A write by one compute unit will be
  committed to memory by a fence there, but a second compute unit may
  read a stale value from its private L1 cache afterwards.

  We may need to use an atomic to ensure we bypass the L1 cache in
  places where we need stronger consistency across workgroups.

  Since Evergreen, the hardware has had a "GDS" buffer for global
  synchronization, however 3 years later we still don't yet have an
  extension to access it from OpenCL. When that finally happens, it
  will probably be a better option to use that for these places.


  - On Nvidia, mem_fence(CLK_GLOBAL_MEM_FENCE) seems to compile to a
  membar.gl instruction, the same as the global sync
  __threadfence(). It may change to a workgroup level membar.cta at
  some point. To be sure we use the correct global level sync, use
  inline PTX to make sure we use membar.gl

  Not sure what to do about Nvidia on Apple's implementation. I'm not
  sure how to even see what PTX it is generating, and there is no
  inline PTX.

*/


#if DOUBLEPREC

inline real atomic_read_real(RVPtr arr, int idx)
{
    union
    {
        int2 i;
        double f;
    } u;

    IVPtr src = (IVPtr) &arr[idx];

    /* Breaks aliasing rules */
    u.i.x = atomic_or(src + 0, 0);
    u.i.y = atomic_or(src + 1, 0);

    return u.f;
}

#else

inline real atomic_read_real(RVPtr arr, int idx)
{
    union
    {
        int2 i;
        float f;
    } u;

    IVPtr src = (IVPtr) &arr[idx];

    u.i = atomic_or(src, 0);

    return u.f;
}
#endif /* DOUBLEPREC */

#if HAVE_CONSISTENT_MEMORY
  #define read_bypass_cache_int(arr, idx) ((arr)[idx])
  #define read_bypass_cache_real(arr, idx) ((arr)[idx])
#else
  #define read_bypass_cache_int(arr, idx) atomic_or(&((arr)[idx]), 0)
  #define read_bypass_cache_real(base, idx) atomic_read_real(base, idx)
#endif /* HAVE_CONSISTENT_MEMORY */

// __attribute__ ((reqd_work_group_size(THREADS7, 1, 1)))
// __kernel void NBODY_KERNEL(summarizationClear)
// {
//     __local int bottom;
// 
//     if (get_local_id(0) == 0)
//     {
//         bottom = _treeStatus->bottom;
//     }
// 
//     barrier(CLK_LOCAL_MEM_FENCE);
// 
//     int inc = get_local_size(0) * get_num_groups(0);
//     int k = (bottom & (-WARPSIZE)) + get_global_id(0);  /* Align to warp size */
// 
//     if (k < bottom)
//     {
//         k += inc;
//     }
// 
//     while (k < NNODE)
//     {
//         _mass[k] = -1.0;
//         _start[k] = NULL_BODY;
// 
//         if (USE_QUAD)
//         {
//             _quadXX[k] = NAN;
//             _quadXY[k] = NAN;
//             _quadXZ[k] = NAN;
// 
//             _quadYY[k] = NAN;
//             _quadYZ[k] = NAN;
// 
//             _quadZZ[k] = NAN;
//         }
// 
//         k += inc;
//     }
// }

// __attribute__ ((reqd_work_group_size(THREADS3, 1, 1)))
// __kernel void NBODY_KERNEL(summarization)
// {
//     __local int bottom;
//     __local volatile int child[NSUB * THREADS3];
//     __local real rootSize;
// 
//     if (get_local_id(0) == 0)
//     {
//         rootSize = _treeStatus->radius;
//         bottom = _treeStatus->bottom;
//     }
//     barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);
// 
//     int inc = get_local_size(0) * get_num_groups(0);
//     int k = (bottom & (-WARPSIZE)) + get_global_id(0);  /* Align to warp size */
//     if (k < bottom)
//         k += inc;
// 
//     int missing = 0;
//     while (k <= NNODE) /* Iterate over all cells assigned to thread */
//     {
//         real m, cm, px, py, pz;
//         int cnt, ch;
//         real mk;
// 
//         if (!HAVE_CONSISTENT_MEMORY)
//         {
//             mk = _mass[k];
//         }
// 
//         if (HAVE_CONSISTENT_MEMORY || mk < 0.0)         /* Skip if we finished this cell already */
//         {
//             if (missing == 0)
//             {
//                 /* New cell, so initialize */
//                 cm = px = py = pz = 0.0;
//                 cnt = 0;
//                 int j = 0;
// 
//                 #pragma unroll NSUB
//                 for (int i = 0; i < NSUB; ++i)
//                 {
//                     ch = _child[NSUB * k + i];
//                     if (ch >= 0)
//                     {
// 
//                         if (i != j)
//                         {
//                             /* Move children to front (needed later for speed) */
//                             _child[NSUB * k + i] = -1;
//                             _child[NSUB * k + j] = ch;
//                         }
// 
//                         m = _mass[ch];
//                         child[THREADS3 * missing + get_local_id(0)] = ch; /* Cache missing children */
// 
//                         ++missing;
// 
//                         if (m >= 0.0)
//                         {
//                             /* Child is ready */
//                             --missing;
//                             if (ch >= NBODY) /* Count bodies (needed later) */
//                             {
//                                 cnt += read_bypass_cache_int(_count, ch) - 1;
//                             }
// 
//                             real chx = read_bypass_cache_real(_posX, ch);
//                             real chy = read_bypass_cache_real(_posY, ch);
//                             real chz = read_bypass_cache_real(_posZ, ch);
// 
// 
//                             /* Add child's contribution */
// 
//                             cm += m;
//                             px = mad(m, chx, px);
//                             py = mad(m, chy, py);
//                             pz = mad(m, chz, pz);
//                         }
//                         ++j;
//                     }
//                 }
//                 mem_fence(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE); /* Only for performance */
//                 cnt += j;
//             }
// 
//             if ((HAVE_CONSISTENT_MEMORY || get_num_groups(0) == 1) && missing != 0)
//             {
//                 do
//                 {
//                     /* poll missing child */
//                     ch = child[THREADS3 * (missing - 1) + get_local_id(0)];
//                     m = _mass[ch];
//                     if (m >= 0.0) /* Body children can never be missing, so this is a cell */
//                     {
//                         cl_assert(_treeStatus, ch >= NBODY /* Missing child must be a cell */);
// 
//                         /* child is now ready */
//                         --missing;
// 
//                         /* count bodies (needed later) */
//                         cnt += _count[ch] - 1;
// 
//                         real chx = _posX[ch];
//                         real chy = _posY[ch];
//                         real chz = _posZ[ch];
// 
// 
//                         /* add child's contribution */
//                         cm += m;
//                         px = mad(m, chx, px);
//                         py = mad(m, chy, py);
//                         pz = mad(m, chz, pz);
//                     }
//                     /* repeat until we are done or child is not ready */
//                 }
//                 while ((m >= 0.0) && (missing != 0));
//             }
// 
//             if (missing == 0)
//             {
//                 /* All children are ready, so store computed information */
//                 _count[k] = cnt;
//                 real cx = _posX[k];  /* Load geometric center */
//                 real cy = _posY[k];
//                 real cz = _posZ[k];
// 
//                 real psize;
// 
//                 if (SW93 || NEWCRITERION)
//                 {
//                     psize = _critRadii[k]; /* Get saved size (half cell = radius) */
//                 }
// 
//                 m = 1.0 / cm;
//                 px *= m; /* Scale up to position */
//                 py *= m;
//                 pz *= m;
// 
//                 /* Calculate opening criterion if necessary */
//                 real rc2;
// 
//                 if (THETA == 0.0)
//                 {
//                     rc2 = sqr(2.0 * rootSize);
//                 }
//                 else if (SW93)
//                 {
//                     real bmax2 = bmax2Inc(px, cx, psize);
//                     bmax2 += bmax2Inc(py, cy, psize);
//                     bmax2 += bmax2Inc(pz, cz, psize);
//                     rc2 = bmax2 / (THETA * THETA);
//                 }
//                 else if (NEWCRITERION)
//                 {
//                     real dx = px - cx;  /* Find distance from center of mass to geometric center */
//                     real dy = py - cy;
//                     real dz = pz - cz;
//                     real dr = sqrt(mad(dz, dz, mad(dy, dy, dx * dx)));
// 
//                     real rc = (psize / THETA) + dr;
// 
//                     rc2 = rc * rc;
//                 }
// 
//                 if (SW93 || NEWCRITERION)
//                 {
//                     /* We don't have the size of the cell for BH86, but really still should check */
//                     bool xTest = checkTreeDim(px, cx, psize);
//                     bool yTest = checkTreeDim(py, cy, psize);
//                     bool zTest = checkTreeDim(pz, cz, psize);
//                     bool structureCheck = xTest || yTest || zTest;
//                     if (structureCheck)
//                     {
//                         _treeStatus->errorCode = NBODY_KERNEL_TREE_STRUCTURE_ERROR;
//                     }
//                 }
// 
//                 _posX[k] = px;
//                 _posY[k] = py;
//                 _posZ[k] = pz;
// 
//                 if (SW93 || NEWCRITERION)
//                 {
//                     _critRadii[k] = rc2;
//                 }
// 
//                 if (USE_QUAD)
//                 {
//                     /* We must initialize all cells quad moments to NaN */
//                     _quadXX[k] = NAN;
//                 }
// 
//                 maybe_strong_global_mem_fence(); /* Make sure data is visible before setting mass */
//                 _mass[k] = cm;
// 
//                 if (HAVE_CONSISTENT_MEMORY)
//                 {
//                     k += inc;  /* Move on to next cell */
//                 }
//             }
//         }
// 
//         if (!HAVE_CONSISTENT_MEMORY)
//         {
//             missing = 0;
//             cnt = 0;
//             k += inc;  /* Move on to next cell */
//         }
//     }
// }


#if NOSORT
/* Debugging */
__attribute__ ((reqd_work_group_size(THREADS4, 1, 1)))
__kernel void NBODY_KERNEL(sort)
{
    __local int bottoms;

    if (get_local_id(0) == 0)
    {
        bottoms = _treeStatus->bottom;
    }
    barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);

    int bottom = bottoms;
    int dec = get_local_size(0) * get_num_groups(0);
    int k = NNODE + 1 - dec + get_global_id(0);

    while (k >= bottom)
    {
        _sort[k] = k;
        k -= dec;  /* Move on to next cell */
    }
}

#else

/* Real sort kernel, will never finish unless all threads can be launched at once */
// __attribute__ ((reqd_work_group_size(THREADS4, 1, 1)))
// __kernel void NBODY_KERNEL(sort)
// {
//     __local int bottoms;
// 
//     if (get_local_id(0) == 0)
//     {
//         bottoms = _treeStatus->bottom;
//     }
//     barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);
// 
//     int bottom = bottoms;
//     int dec = get_local_size(0) * get_num_groups(0);
//     int k = NNODE + 1 - dec + get_global_id(0);
// 
//     while (k >= bottom) /* Iterate over all cells assigned to thread */
//     {
//         int start = _start[k];
//         if (start >= 0)
//         {
//             #pragma unroll NSUB
//             for (int i = 0; i < NSUB; ++i)
//             {
//                 int ch = _child[NSUB * k + i];
//                 if (ch >= NBODY)         /* Child is a cell */
//                 {
//                     _start[ch] = start;  /* Set start ID of child */
//                     start += _count[ch]; /* Add #bodies in subtree */
//                 }
//                 else if (ch >= 0)        /* Child is a body */
//                 {
//                     _sort[start] = ch;   /* Record body in sorted array */
//                     ++start;
//                 }
//             }
//         }
// 
//         k -= dec;  /* Move on to next cell */
//     }
// }

#endif /* NOSORT */

inline void incAddMatrix(QuadMatrix* restrict a, QuadMatrix* restrict b)
{
    a->xx += b->xx;
    a->xy += b->xy;
    a->xz += b->xz;

    a->yy += b->yy;
    a->yz += b->yz;

    a->zz += b->zz;
}

inline void quadCalc(QuadMatrix* quad, real4 chCM, real4 kp)
{
    real4 dr;
    dr.x = chCM.x - kp.x;
    dr.y = chCM.y - kp.y;
    dr.z = chCM.z - kp.z;

    real drSq = mad(dr.z, dr.z, mad(dr.y, dr.y, dr.x * dr.x));

    quad->xx = chCM.w * (3.0 * (dr.x * dr.x) - drSq);
    quad->xy = chCM.w * (3.0 * (dr.x * dr.y));
    quad->xz = chCM.w * (3.0 * (dr.x * dr.z));

    quad->yy = chCM.w * (3.0 * (dr.y * dr.y) - drSq);
    quad->yz = chCM.w * (3.0 * (dr.y * dr.z));

    quad->zz = chCM.w * (3.0 * (dr.z * dr.z) - drSq);
}


/* Very similar to summarization kernel. Calculate the quadrupole
 * moments for the cells in an almost identical way */
// __attribute__ ((reqd_work_group_size(THREADS5, 1, 1)))
// __kernel void NBODY_KERNEL(quadMoments)
// {
//     __local int bottom;
//     __local volatile int child[NSUB * THREADS5];
//     __local real rootSize;
//     __local int maxDepth;
// 
//     if (get_local_id(0) == 0)
//     {
//         rootSize = _treeStatus->radius;
//         bottom = _treeStatus->bottom;
//         maxDepth = _treeStatus->maxDepth;
//     }
//     barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);
// 
//     int inc = get_local_size(0) * get_num_groups(0);
//     int k = (bottom & (-WARPSIZE)) + get_global_id(0);  /* Align to warp size */
//     if (k < bottom)
//         k += inc;
// 
//     if (maxDepth > MAXDEPTH)
//     {
//         _treeStatus->errorCode = maxDepth;
//         return;
//     }
// 
//     int missing = 0;
//     while (k <= NNODE)   /* Iterate over all cells assigned to thread */
//     {
//         int ch;          /* Child index */
//         real4 kp;        /* Position of this cell k */
//         QuadMatrix kq;   /* Quad moment for this cell */
//         QuadMatrix qCh;  /* Loads of child quad moments */
//         real kQxx;
// 
//         kp.x = _posX[k]; /* This cell's center of mass position */
//         kp.y = _posY[k];
//         kp.z = _posZ[k];
// 
//         if (!HAVE_CONSISTENT_MEMORY)
//         {
//             kQxx = _quadXX[k];
//         }
// 
//         if (HAVE_CONSISTENT_MEMORY || isnan(kQxx))
//         {
//             if (missing == 0)
//             {
//                 /* New cell, so initialize */
//                 kq.xx = kq.xy = kq.xz = 0.0;
//                 kq.yy = kq.yz = 0.0;
//                 kq.zz = 0.0;
// 
//                 int j = 0;
// 
//                 #pragma unroll NSUB
//                 for (int i = 0; i < NSUB; ++i)
//                 {
//                     QuadMatrix quad; /* Increment from this descendent */
//                     ch = _child[NSUB * k + i];
// 
//                     if (ch >= 0)
//                     {
//                         if (isBody(ch))
//                         {
//                             real4 chCM;
// 
//                             chCM.x = _posX[ch];
//                             chCM.y = _posY[ch];
//                             chCM.z = _posZ[ch];
//                             chCM.w = _mass[ch];
// 
//                             quadCalc(&quad, chCM, kp);
//                             incAddMatrix(&kq, &quad);  /* Add to total moment */
//                         }
// 
//                         if (isCell(ch))
//                         {
//                             child[THREADS5 * missing + get_local_id(0)] = ch; /* Cache missing children */
//                             ++missing;
// 
//                             qCh.xx = _quadXX[ch];
//                             if (!isnan(qCh.xx))
//                             {
//                                 real4 chCM;
// 
//                                 /* Load the rest */
//                               //qCh.xx = read_bypass_cache_real(_quadXX, ch);
//                                 qCh.xy = read_bypass_cache_real(_quadXY, ch);
//                                 qCh.xz = read_bypass_cache_real(_quadXZ, ch);
// 
//                                 qCh.yy = read_bypass_cache_real(_quadYY, ch);
//                                 qCh.yz = read_bypass_cache_real(_quadYZ, ch);
// 
//                                 qCh.zz = read_bypass_cache_real(_quadZZ, ch);
// 
//                                 chCM.x = _posX[ch];
//                                 chCM.y = _posY[ch];
//                                 chCM.z = _posZ[ch];
//                                 chCM.w = _mass[ch];
// 
//                                 quadCalc(&quad, chCM, kp);
// 
//                                 --missing;  /* Child is ready */
// 
//                                 incAddMatrix(&quad, &qCh);  /* Add child's contribution */
//                                 incAddMatrix(&kq, &quad);   /* Add to total moment */
//                             }
//                         }
// 
//                         ++j;
//                     }
//                 }
//                 mem_fence(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE); /* Only for performance */
//             }
// 
//             if ((HAVE_CONSISTENT_MEMORY || get_num_groups(0) == 1) && missing != 0)
//             {
//                 do
//                 {
//                     QuadMatrix quad; /* Increment from this missing child */
// 
//                     /* poll missing child */
//                     ch = child[THREADS5 * (missing - 1) + get_local_id(0)];
//                     cl_assert(_treeStatus, ch > 0);
//                     cl_assert(_treeStatus, ch >= NBODY);
//                     if (ch >= NBODY) /* Is a cell */
//                     {
//                         qCh.xx = _quadXX[ch];
//                         if (!isnan(qCh.xx))
//                         {
//                             real4 chCM;
// 
//                             chCM.x = _posX[ch];
//                             chCM.y = _posY[ch];
//                             chCM.z = _posZ[ch];
//                             chCM.w = _mass[ch];
// 
//                             //qCh.xx = _quadXX[ch];
//                             qCh.xy = _quadXY[ch];
//                             qCh.xz = _quadXZ[ch];
// 
//                             qCh.yy = _quadYY[ch];
//                             qCh.yz = _quadYZ[ch];
// 
//                             qCh.zz = _quadZZ[ch];
// 
//                             quadCalc(&quad, chCM, kp);
// 
//                             --missing;  /* Child is now ready */
// 
//                             incAddMatrix(&quad, &qCh);  /* Add subcell's moment */
//                             incAddMatrix(&kq, &quad);   /* add child's contribution */
//                         }
//                     }
//                     /* repeat until we are done or child is not ready */
//                 }
//                 while ((!isnan(qCh.xx)) && (missing != 0));
//             }
// 
//             if (missing == 0)
//             {
//                 /* All children are ready, so store computed information */
//                 //_quadXX[k] = kq.xx;  /* Store last */
//                 _quadXY[k] = kq.xy;
//                 _quadXZ[k] = kq.xz;
// 
//                 _quadYY[k] = kq.yy;
//                 _quadYZ[k] = kq.yz;
// 
//                 _quadZZ[k] = kq.zz;
// 
//                 write_mem_fence(CLK_GLOBAL_MEM_FENCE); /* Make sure data is visible before setting tested quadx */
//                 _quadXX[k] = kq.xx;
//                 write_mem_fence(CLK_GLOBAL_MEM_FENCE);
// 
//                 if (HAVE_CONSISTENT_MEMORY)
//                 {
//                     k += inc;  /* Move on to next cell */
//                 }
//             }
//         }
// 
//         if (!HAVE_CONSISTENT_MEMORY)
//         {
//             missing = 0;
//             k += inc;
//         }
//     }
// }

#if HAVE_INLINE_PTX
inline int warpAcceptsCellPTX(real rSq, real rCritSq)
{
    uint result;

  #if DOUBLEPREC
    asm("{\n\t"
        ".reg .pred cond, out;\n\t"
        "setp.ge.f64 cond, %1, %2;\n\t"
        "vote.all.pred out, cond;\n\t"
        "selp.u32 %0, 1, 0, out;\n\t"
        "}\n\t"
        : "=r"(result)
        : "d"(rSq), "d"(rCritSq));
  #else
    asm("{\n\t"
        ".reg .pred cond, out;\n\t"
        "setp.ge.f32 cond, %1, %2;\n\t"
        "vote.all.pred out, cond;\n\t"
        "selp.u32 %0, 1, 0, out;\n\t"
        "}\n\t"
        : "=r"(result)
        : "f"(rSq), "f"(rCritSq));
  #endif /* DOUBLEPREC */

    return result;
}
#endif /* HAVE_INLINE_PTX */


/*
 * This should be equivalent roughtly to CUDA's __all() with the conditions
 * A barrier should be unnecessary here since
 * all the threads in a wavefront should be
 * forced to run simulatenously. This is not
 * over the workgroup, but the actual
 * wavefront.
 */
inline int warpAcceptsCellSurvey(__local volatile int allBlock[THREADS6 / WARPSIZE], int warpId, int cond)
{
    /* Relies on underlying wavefronts (not whole workgroup)
       executing in lockstep to not require barrier */

    int old = allBlock[warpId];

    /* Increment if true, or leave unchanged */
    (void) atom_add(&allBlock[warpId], cond);

    int ret = (allBlock[warpId] == WARPSIZE);
    allBlock[warpId] = old;

    return ret;
}

#if HAVE_INLINE_PTX
/* Need to do this horror to avoid wasting __local if we can use the real warp vote */
#define warpAcceptsCell(allBlock, base, rSq, dq) warpAcceptsCellPTX(rSq, dq)
#else
#define warpAcceptsCell(allBlock, base, rSq, dq) warpAcceptsCellSurvey(allBlock, base, (rSq) >= (dq))
#endif

// __kernel void bruteForceCalculationManager(GTPtr _gTreeIn, GTPtr _gTreeOut)
// {
//  forceCalculation(GTPtr _gTreeIn, GTPtr _gTreeOut   
// }

__attribute__ ((reqd_work_group_size(THREADS6, 1, 1)))
__kernel void forceCalculation(GTPtr _gTreeIn, GTPtr _gTreeOut)
{
    
    int a = (int)get_global_id(0);
//     if(a == 0){ //We set the output array in the first thread, since we don't want to do it in every thread; That would be a waste.
//         _gTreeOut = _gTreeIn;
//     }
    _gTreeOut[a].mass = _gTreeIn[a].mass;
    _gTreeOut[a].isBody = _gTreeIn[a].isBody;
    for(int i = 0; i < 3; ++i){
       _gTreeOut[a].acc[i] = 0; //Initialize accelerations to zero before we do calculations
    }
    //TODO: start writing force calculations
    if(_gTreeIn[a].isBody){
        GTPtr tmp = _gTreeIn;
        while(tmp != NULL){
            if(tmp->isBody){ //If it's a body we can go to the next value
                if(tmp != &_gTreeIn[a]){    //make sure we aren't self-interacting:
                    real pos1[3];
                    real pos2[3];
                    real drVec[3];
                    for(int i = 0; i < 3; ++i){
                        pos1[i] = _gTreeIn[a].pos[i];
                        pos2[i] = tmp->pos[i];
                        drVec[i] = (pos2[i] - pos1[i]);               
                    }
                    //Calculate distance between two bodies:
                    
                    real dr2 = mad(drVec[0], drVec[0], mad(drVec[1], drVec[1], drVec[2] * drVec[2])) + EPS2;
                    real dr = sqrt(dr2);
                    
                    //Calculate acceleration between the two bodies:
//                     _gTreeOut[a].acc[0] += 10;
//                     _gTreeOut[a].acc[1] += 10;
//                     _gTreeOut[a].acc[2] += 10;
                    _gTreeOut[a].acc[0] += (tmp->mass * drVec[0])/(dr2*dr);
                    _gTreeOut[a].acc[1] += (tmp->mass * drVec[1])/(dr2*dr);
                    _gTreeOut[a].acc[2] += (tmp->mass * drVec[2])/(dr2*dr);
                }
                    
                
                
                if(tmp->next != 0){ //Check to see that we aren't at the end and pointing back to root
                    tmp = &_gTreeIn[tmp->next];
                }
                else{ //If there are no more bodies in the (next) index, we must be at the end of the tree
                    tmp = NULL;
                }
            }
            else{ //If not body, then must be cell
                tmp = &_gTreeIn[tmp->more]; //cells MUST have a (more) index
            }
        }
//=============================================================
        //_gTreeOut[0].pos[0] = _gTreeOut[0].acc[0];
        //Finally, after finding the total acceleration, we can integrate it:
        //Integrate the acceleration by the timestep and get the values for velocity and position:
        
        real px = _gTreeIn[a].pos[0];
        real py = _gTreeIn[a].pos[1];
        real pz = _gTreeIn[a].pos[2];
        
        real vx = _gTreeIn[a].vel[0];
        real vy = _gTreeIn[a].vel[1];
        real vz = _gTreeIn[a].vel[2];

//         real vx = 1;
//         real vy = 1;
//         real vz = 1;

        
        real ax = _gTreeOut[a].acc[0];
        real ay = _gTreeOut[a].acc[1];
        real az = _gTreeOut[a].acc[2];
        
        real dvx = 0.5 * TIMESTEP * _gTreeOut[a].acc[0];
        real dvy = 0.5 * TIMESTEP * _gTreeOut[a].acc[1];
        real dvz = 0.5 * TIMESTEP * _gTreeOut[a].acc[2];
        
        vx += dvx;
        vy += dvy;
        vz += dvz;
        
        _gTreeOut[a].pos[0] = mad(TIMESTEP, vx, _gTreeIn[a].pos[0]);
        _gTreeOut[a].pos[1] = mad(TIMESTEP, vy, _gTreeIn[a].pos[1]);
        _gTreeOut[a].pos[2] = mad(TIMESTEP, vz, _gTreeIn[a].pos[2]);
        
//         _gTreeOut[a].pos[0] = _gTreeIn[a].pos[0];
//         _gTreeOut[a].pos[1] = _gTreeIn[a].pos[1];
//         _gTreeOut[a].pos[2] = _gTreeIn[a].pos[2];
//         
        vx += dvx;
        vy += dvy;
        vz += dvz;
        
        _gTreeOut[a].vel[0] = vx;
        _gTreeOut[a].vel[1] = vy;
        _gTreeOut[a].vel[2] = vz;
    }
    
    barrier(CLK_LOCAL_MEM_FENCE | CLK_GLOBAL_MEM_FENCE);
//=========================================
}
    
    
    
    

//     __local uint maxDepth;
//     __local real rootCritRadius;
// 
//     __local volatile int ch[THREADS6 / WARPSIZE];
//     __local volatile real nx[THREADS6 / WARPSIZE], ny[THREADS6 / WARPSIZE], nz[THREADS6 / WARPSIZE];
//     __local volatile real nm[THREADS6 / WARPSIZE];
// 
//     /* Stack things */
//     __local volatile int pos[MAXDEPTH * THREADS6 / WARPSIZE], node[MAXDEPTH * THREADS6 / WARPSIZE];
//     __local volatile real dq[MAXDEPTH * THREADS6 / WARPSIZE];
// 
//   #if USE_QUAD
//     __local real rootQXX, rootQXY, rootQXZ;
//     __local real rootQYY, rootQYZ;
//     __local real rootQZZ;
// 
//     __local volatile real quadXX[MAXDEPTH * THREADS6 / WARPSIZE];
//     __local volatile real quadXY[MAXDEPTH * THREADS6 / WARPSIZE];
//     __local volatile real quadXZ[MAXDEPTH * THREADS6 / WARPSIZE];
// 
//     __local volatile real quadYY[MAXDEPTH * THREADS6 / WARPSIZE];
//     __local volatile real quadYZ[MAXDEPTH * THREADS6 / WARPSIZE];
// 
//     __local volatile real quadZZ[MAXDEPTH * THREADS6 / WARPSIZE];
//   #endif /* USE_QUAD */
// 
// 
//   #if !HAVE_INLINE_PTX
//     /* Used by the fake thread voting function.
//        We rely on the lockstep behaviour of warps/wavefronts to avoid using a barrier
//     */
//     __local volatile int allBlock[THREADS6 / WARPSIZE];
//   #endif /* !HAVE_INLINE_PTX */
// 
//     if (get_local_id(0) == 0)
//     {
//         maxDepth = _treeStatus->maxDepth;
//         real rootSize = _treeStatus->radius;
// 
//       #if USE_QUAD
//         rootQXX = _quadXX[NNODE];
//         rootQXY = _quadXY[NNODE];
//         rootQXZ = _quadXZ[NNODE];
//         rootQYY = _quadYY[NNODE];
//         rootQYZ = _quadYZ[NNODE];
//         rootQZZ = _quadZZ[NNODE];
//       #endif
// 
//         if (SW93 || NEWCRITERION)
//         {
//             rootCritRadius = _critRadii[NNODE];
//         }
//         else if (BH86)
//         {
//             real rc;
// 
//             if (THETA == 0.0)
//             {
//                 rc = 2.0 * rootSize;
//             }
//             else
//             {
//                 rc = rootSize / THETA;
//             }
// 
//             /* Precompute values that depend only on tree level */
//             dq[0] = rc * rc;
//             for (uint i = 1; i < maxDepth; ++i)
//             {
//                 dq[i] = 0.25 * dq[i - 1];
//             }
//         }
// 
//       #if !HAVE_INLINE_PTX
//         for (uint i = 0; i < THREADS6 / WARPSIZE; ++i)
//         {
//             allBlock[i] = 0;
//         }
//       #endif
// 
//         if (maxDepth > MAXDEPTH)
//         {
//             _treeStatus->errorCode = maxDepth;
//         }
//     }
//     barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);
// 
//     if (maxDepth <= MAXDEPTH)
//     {
//         /* Figure out first thread in each warp */
//         uint base = get_local_id(0) / WARPSIZE;
//         uint sbase = base * WARPSIZE;
//         int j = base * MAXDEPTH;
//         int diff = get_local_id(0) - sbase; /* Index in warp */
// 
//         if (BH86 || EXACT)
//         {
//             /* Make multiple copies to avoid index calculations later */
//             if (diff < MAXDEPTH)
//             {
//                 dq[diff + j] = dq[diff];
//             }
//             barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);
//         }
// 
//         uint k = get_global_id(0);
// 
//       #if !HAVE_INLINE_PTX
//         (void) atom_add(&allBlock[base], k >= maxNBody);
//       #endif

        /* iterate over all bodies assigned to thread */
//         while (k < maxNBody)
//         {
//             int i = _sort[k];  /* Get permuted index */
// 
//             /* Cache position info */
//             real px = _posX[i];
//             real py = _posY[i];
//             real pz = _posZ[i];
// 
//             real ax = 0.0;
//             real ay = 0.0;
//             real az = 0.0;
// 
//             /* Initialize iteration stack, i.e., push root node onto stack */
//             int depth = j;
//             if (get_local_id(0) == sbase)
//             {
//                 node[j] = NNODE;
//                 pos[j] = 0;
// 
//                 if (SW93 || NEWCRITERION)
//                 {
//                     dq[j] = rootCritRadius;
//                 }
// 
//                 #if USE_QUAD
//                 {
//                     quadXX[j] = rootQXX;
//                     quadXY[j] = rootQXY;
//                     quadXZ[j] = rootQXZ;
//                     quadYY[j] = rootQYY;
//                     quadYZ[j] = rootQYZ;
//                     quadZZ[j] = rootQZZ;
//                 }
//                 #endif
//             }
//             mem_fence(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);
// 
//             bool skipSelf = false;
//             do
//             {
//                 int curPos;
// 
//                 /* Stack is not empty */
//                 while ((curPos = pos[depth]) < NSUB)
//                 {
//                     int n;
//                     /* Node on top of stack has more children to process */
//                     if (get_local_id(0) == sbase)
//                     {
//                         /* I'm the first thread in the warp */
//                         n = _child[NSUB * node[depth] + curPos]; /* Load child pointer */
//                         pos[depth] = curPos + 1;
//                         ch[base] = n; /* Cache child pointer */
//                         if (n >= 0)
//                         {
//                             /* Cache position and mass */
//                             nx[base] = _posX[n];
//                             ny[base] = _posY[n];
//                             nz[base] = _posZ[n];
//                             nm[base] = _mass[n];
//                         }
//                     }
//                     mem_fence(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);
// 
//                     /* All threads retrieve cached data */
//                     n = ch[base];
//                     if (n >= 0)
//                     {
//                         real dx = nx[base] - px;
//                         real dy = ny[base] - py;
//                         real dz = nz[base] - pz;
//                         real rSq = mad(dz, dz, mad(dy, dy, dx * dx));  /* Compute distance squared */
// 
//                         /* Check if all threads agree that cell is far enough away (or is a body) */
//                         if (isBody(n) || warpAcceptsCell(allBlock, base, rSq, dq[depth]))
//                         {
//                             rSq += EPS2;
// 
//                           #ifdef __FAST_RELAXED_MATH__
//                             real rInv = rsqrt(rSq);   /* Compute distance with softening */
//                             real ai = nm[base] * rInv * rInv * rInv;
//                             /* FIXME: If EPS is 0, we can get nan */
//                           #else
//                             real r = sqrt(rSq);   /* Compute distance with softening */
//                             real ai = nm[base] / (rSq * r);
//                           #endif
// 
//                             ax = mad(ai, dx, ax);
//                             ay = mad(ai, dy, ay);
//                             az = mad(ai, dz, az);
// 
//                           #if USE_QUAD
//                             {
//                                 if (isCell(n))
//                                 {
//                                     real quad_dx, quad_dy, quad_dz;
// 
//                                     real dr5inv = 1.0 / (sqr(rSq) * r);
// 
//                                     /* Matrix multiply Q . dr */
//                                     quad_dx = mad(quadXZ[depth], dz, mad(quadXY[depth], dy, quadXX[depth] * dx));
//                                     quad_dy = mad(quadYZ[depth], dz, mad(quadYY[depth], dy, quadXY[depth] * dx));
//                                     quad_dz = mad(quadZZ[depth], dz, mad(quadYZ[depth], dy, quadXZ[depth] * dx));
// 
//                                     /* dr . Q . dr */
//                                     real drQdr = mad(quad_dz, dz, mad(quad_dy, dy, quad_dx * dx));
// 
//                                     real phiQuad = 2.5 * (dr5inv * drQdr) / rSq;
// 
//                                     ax = mad(phiQuad, dx, ax);
//                                     ay = mad(phiQuad, dy, ay);
//                                     az = mad(phiQuad, dz, az);
// 
//                                     ax = mad(-dr5inv, quad_dx, ax);
//                                     ay = mad(-dr5inv, quad_dy, ay);
//                                     az = mad(-dr5inv, quad_dz, az);
//                                 }
//                             }
//                           #endif /* USE_QUAD */
// 
// 
//                             /* Watch for self interaction. It's OK to
//                              * not skip because dx, dy, dz will be
//                              * 0.0 */
//                             if (n == i)
//                             {
//                                 skipSelf = true;
//                             }
//                         }
//                         else
//                         {
//                             /* Push cell onto stack */
//                             ++depth;
//                             if (get_local_id(0) == sbase)
//                             {
//                                 node[depth] = n;
//                                 pos[depth] = 0;
// 
//                                 if (SW93 || NEWCRITERION)
//                                 {
//                                     dq[depth] = _critRadii[n];
//                                 }
// 
//                                 #if USE_QUAD
//                                 {
//                                     quadXX[depth] = _quadXX[n];
//                                     quadXY[depth] = _quadXY[n];
//                                     quadXZ[depth] = _quadXZ[n];
// 
//                                     quadYY[depth] = _quadYY[n];
//                                     quadYZ[depth] = _quadYZ[n];
// 
//                                     quadZZ[depth] = _quadZZ[n];
//                                 }
//                                 #endif /* USE_QUAD */
//                             }
//                             /* Full barrier not necessary since items only synced on wavefront level */
//                             mem_fence(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);
//                         }
//                     }
//                     else
//                     {
//                         /* Early out because all remaining children are also zero */
//                         depth = max(j, depth - 1);
//                     }
//                 }
//                 --depth;  /* Done with this level */
//             }
//             while (depth >= j);
// 
//             real accX = _accX[i];
//             real accY = _accY[i];
//             real accZ = _accZ[i];
// 
//             real vx = _velX[i];
//             real vy = _velY[i];
//             real vz = _velZ[i];
// 
// 
//             if (USE_EXTERNAL_POTENTIAL)
//             {
//                 real4 acc = externalAcceleration(px, py, pz);
// 
//                 ax += acc.x;
//                 ay += acc.y;
//                 az += acc.z;
//             }
// 
//             vx = mad(0.5 * TIMESTEP, ax - accX, vx);
//             vy = mad(0.5 * TIMESTEP, ay - accY, vy);
//             vz = mad(0.5 * TIMESTEP, az - accZ, vz);
// 
//             /* Save computed acceleration */
//             _accX[i] = ax;
//             _accY[i] = ay;
//             _accZ[i] = az;
// 
//             if (updateVel)
//             {
//                 _velX[i] = vx;
//                 _velY[i] = vy;
//                 _velZ[i] = vz;
//             }
// 
//             if (!skipSelf)
//             {
//                 _treeStatus->errorCode = NBODY_KERNEL_TREE_INCEST;
//             }
// 
// 
//             k += get_local_size(0) * get_num_groups(0);
// 
//           #if !HAVE_INLINE_PTX
//             /* In case this thread is done with bodies and others in the wavefront aren't */
//             (void) atom_add(&allBlock[base], k >= maxNBody);
//           #endif /* !HAVE_INLINE_PTX */
//         }
//    }
//}

__attribute__ ((reqd_work_group_size(THREADS7, 1, 1)))
__kernel void NBODY_KERNEL(integration)
{
//     uint inc = get_local_size(0) * get_num_groups(0);
// 
//     /* Iterate over all bodies assigned to thread */
//     for (uint i = (uint) get_global_id(0); i < NBODY; i += inc)
//     {
//         real px = _posX[i];
//         real py = _posY[i];
//         real pz = _posZ[i];
// 
//         real ax = _accX[i];
//         real ay = _accY[i];
//         real az = _accZ[i];
// 
//         real vx = _velX[i];
//         real vy = _velY[i];
//         real vz = _velZ[i];
// 
// 
//         real dvx = (0.5 * TIMESTEP) * ax;
//         real dvy = (0.5 * TIMESTEP) * ay;
//         real dvz = (0.5 * TIMESTEP) * az;
// 
//         vx += dvx;
//         vy += dvy;
//         vz += dvz;
// 
//         px = mad(TIMESTEP, vx, px);
//         py = mad(TIMESTEP, vy, py);
//         pz = mad(TIMESTEP, vz, pz);
// 
//         vx += dvx;
//         vy += dvy;
//         vz += dvz;
// 
// 
//         _posX[i] = px;
//         _posY[i] = py;
//         _posZ[i] = pz;
// 
//         _velX[i] = vx;
//         _velY[i] = vy;
//         _velZ[i] = vz;
//     }
}

/* EFFNBODY must be divisible by workgroup size to prevent conditional barrier */
// __attribute__ ((reqd_work_group_size(THREADS8, 1, 1)))
// __kernel void NBODY_KERNEL(forceCalculation_Exact)
// {
//     __local real xs[THREADS8];
//     __local real ys[THREADS8];
//     __local real zs[THREADS8];
//     __local real ms[THREADS8];
// 
//     cl_assert(_treeStatus, EFFNBODY % THREADS8 == 0);
// 
//     for (uint i = get_global_id(0); i < maxNBody; i += get_local_size(0) * get_num_groups(0))
//     {
//         real px = _posX[i];
//         real py = _posY[i];
//         real pz = _posZ[i];
// 
//         real dax = _accX[i];
//         real day = _accY[i];
//         real daz = _accZ[i];
// 
//         real dvx = _velX[i];
//         real dvy = _velY[i];
//         real dvz = _velZ[i];
// 
// 
// 
//         real ax = 0.0;
//         real ay = 0.0;
//         real az = 0.0;
// 
//         uint nTile = EFFNBODY / THREADS8;
//         for (uint j = 0; j < nTile; ++j)
//         {
//             uint idx = THREADS8 * j + get_local_id(0);
//             xs[get_local_id(0)] = _posX[idx];
//             ys[get_local_id(0)] = _posY[idx];
//             zs[get_local_id(0)] = _posZ[idx];
// 
//             ms[get_local_id(0)] = _mass[idx];
// 
//             barrier(CLK_LOCAL_MEM_FENCE);
// 
//             /* WTF: This doesn't happen the correct number of times
//              * unless unrolling forced with on AMD */
//             #pragma unroll 8
//             for (int k = 0; k < THREADS8; ++k)
//             {
//                 real dx = xs[k] - px;
//                 real dy = ys[k] - py;
//                 real dz = zs[k] - pz;
// 
//                 real rSq = mad(dz, dz, mad(dy, dy, dx * dx)) + EPS2;
//                 real r = sqrt(rSq);
//                 real ai = ms[k] / (r * rSq);
// 
//                 ax = mad(ai, dx, ax);
//                 ay = mad(ai, dy, ay);
//                 az = mad(ai, dz, az);
//             }
// 
//             barrier(CLK_LOCAL_MEM_FENCE);
//         }
// 
//         if (USE_EXTERNAL_POTENTIAL)
//         {
//             real4 acc = externalAcceleration(px, py, pz);
// 
//             ax += acc.x;
//             ay += acc.y;
//             az += acc.z;
//         }
// 
//         if (updateVel)
//         {
//             dvx = mad(0.5 * TIMESTEP, ax - dax, dvx);
//             dvy = mad(0.5 * TIMESTEP, ay - day, dvy);
//             dvz = mad(0.5 * TIMESTEP, az - daz, dvz);
// 
//             _velX[i] = dvx;
//             _velY[i] = dvy;
//             _velZ[i] = dvz;
//         }
// 
//         _accX[i] = ax;
//         _accY[i] = ay;
//         _accZ[i] = az;
//     }
// }


/////////////
//TESTING:
/////////////

__kernel void testAddition(__global real* _input, __global real* _output)
{
    _output[0] = _input[0];
}
