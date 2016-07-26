#!/usr/bin/python
import numpy as np
import matplotlib.pyplot as plt
import os
import sys
import pylab as lab
import subprocess

timesteps = 10000
print "RUNNING GPU SYSTEM:"
os.system('rm GPUBRUTE.out')
os.system('rm CPUBRUTE.out')
os.system("cmake -DNBODY_OPENCL=ON -DCMAKE_BUILD_TYPE=DEBUG -DCMAKE_C_FLAGS='-funsafe-math-optimizations' ")
os.system('make')
executeString = './bin/milkyway_nbody -f nbody/sample_workunits/EMD_10k_plummer.lua -o GPUBRUTE.out -x -i -e 36912 ' + str(timesteps) + ' 1 .2 12'
os.system(executeString)


print "RUNNING CPU SYSTEM:"
os.system("cmake -DNBODY_OPENCL=ON -DCMAKE_BUILD_TYPE=DEBUG -DCMAKE_C_FLAGS='-funsafe-math-optimizations' ")
os.system('make')
executeString = './bin/milkyway_nbody -f nbody/sample_workunits/EMD_10k_plummer.lua -o CPUBRUTE.out -x -i -e 36912 ' + str(timesteps) + ' 1 .2 12'
os.system(executeString)
print "PLOTTING DATA"

os.system('python2 PlotNbodyResidual.py GPUBRUTE.out CPUBRUTE.out')
