#!/bin/bash

## Specifies the interpreting shell for the job.
#$ -S /bin/bash

## Specifies that all environment variables active within the qsub utility be exported to the context of the job.
#$ -V

## Parallel programming environment (mpich) to instantiate and number of computing slots.
#$ -pe mpich 32

##Passes an environment variable to the job
#$ -v  OMP_NUM_THREADS=4

## Execute the job from the current working directory.
#$ -cwd 

## The  name  of  the  job.
#$ -N heat_mpi_nx_2000_st_100000_th_4_pr_32

## Output file path (optional)
#$ -o /home/jap26/HeatSolver/mpi/results/heat_mpi_nx_2000_st_100000_th_4_pr_32
#$ -e /home/jap26/HeatSolver/mpi/errors/heat_mpi_nx_2000_st_100000_th_4_pr_32_errors

##send an email when the job ends
#$ -m e

##email addrees notification
##$ -M jap26@alumnes.udl.cat

MPICH_MACHINES=$TMPDIR/mpich_machines
cat $PE_HOSTFILE | awk '{print $1":"$2}' > $MPICH_MACHINES

## In this line you have to write the command that will execute your application.
mpiexec -f $MPICH_MACHINES -n $NSLOTS ./heat_mpi 2000 100000 /home/jap26/HeatSolver/mpi/bmp/output_mpi_nx_2000_st_100000_th_4_pr_32.bmp

rm -rf $MPICH_MACHINES

