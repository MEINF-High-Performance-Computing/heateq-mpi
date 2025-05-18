#!/bin/bash

HEAT_DIR="$HOME/HeatSolver"

SIZES=("100" "1000" "2000")
STEPS=("100" "1000" "10000" "100000")

EMAIL="jap26@alumnes.udl.cat"

CONFIG=("MPI")

# Serial configuration
SERIAL_DIR="${HEAT_DIR}/serial"

# MPI configuration
MPI_DIR="${HEAT_DIR}/mpi"

OMP_THREADS=("2" "4")
MPI_PROCESSES=("2" "4" "8" "16" "32")

FINISHED=0

declare -A job_ids

declare -A job_config

declare -a orders;

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color (reset)


delete_files() {

    for config in "${CONFIG[@]}"; do
        if [ "$config" == "SER" ]; then
            cd "$SERIAL_DIR"
            # # Backup the current directory
            # tar -czf "$SERIAL_DIR/backup/backup_$(date +%Y%m%d_%H%M%S).tar.gz" results errors bmp
            # rm -f results/*
            # rm -f errors/*
            # rm -f bmp/*
        elif [ "$config" == "MPI" ]; then
            cd "$MPI_DIR"
            tar -czf "$MPI_DIR/backup/backup_$(date +%Y%m%d_%H%M%S).tar.gz" results errors bmp
            rm -f results/*
            rm -f errors/*
            rm -f bmp/*
        fi
    done

    cd "$HOME"
}

create_results_folder() {
    mkdir -p "$HEAT_DIR"

    for config in "${CONFIG[@]}"; do
        if [ "$config" == "SER" ]; then
            mkdir -p "$SERIAL_DIR"
            cd "$SERIAL_DIR"
            mkdir -p backup
            mkdir -p results
            mkdir -p errors
            mkdir -p bmp
        elif [ "$config" == "MPI" ]; then
            mkdir -p "$MPI_DIR"
            cd "$MPI_DIR"
            mkdir -p backup
            mkdir -p results
            mkdir -p errors
            mkdir -p bmp
        fi
    done

    cd "$HOME"
}

# Step 1: Compile the heat solver

compile_serial() {
    cd "$SERIAL_DIR"
    make clean
    make all
    cd "$HOME"
}

compile_mpi() {
    cd "$MPI_DIR"
    make clean
    make all
    cd "$HOME"
}

compile_heat() {
    compile_serial
    compile_mpi
}

# Step 2: Create job scripts

create_serial_script() {
    local SIZE=$1
    local STEPS=$2
    local JOB_SCRIPT="run_simple_serial.sh"
    local RESULTS_DIR="${SERIAL_DIR}/results"
    local ERRORS_DIR="${SERIAL_DIR}/errors"
    local BMP_DIR="${OMP_DIR}/bmp"
    cat > "${SERIAL_DIR}/${JOB_SCRIPT}" <<EOF
#!/bin/bash

## Specifies the interpreting shell for the job.
#$ -S /bin/bash

## Specifies that all environment variables active within the qsub utility be exported to the context of the job.
#$ -V

## Specifies the parallel environment if it is needed

## Execute the job from the current working directory.
#$ -cwd 

## The  name  of  the  job.
#$ -N heat_serial_nx_${SIZE}_st_${STEPS}

## Output file path (optional)
#$ -o ${RESULTS_DIR}/heat_serial_nx_${SIZE}_st_${STEPS}
#$ -e ${ERRORS_DIR}/heat_serial_nx_${SIZE}_st_${STEPS}_errors

##send an email when the job ends
#$ -m e

##email addrees notification
##$ -M ${EMAIL}


## In this line you have to write the command that will execute your application.
./heat_serial ${SIZE} ${STEPS} ${BMP_DIR}/output_serial_nx_${SIZE}_st_${STEPS}.bmp
EOF
}

create_mpi_script() {
    local SIZE=$1
    local STEPS=$2
    local THREADS=$3
    local PROCESSES=$4
    local JOB_SCRIPT="run_extended_mpi.sh"
    local RESULTS_DIR="${MPI_DIR}/results"
    local ERRORS_DIR="${MPI_DIR}/errors"
    local BMP_DIR="${MPI_DIR}/bmp"
    cat > "${MPI_DIR}/${JOB_SCRIPT}" <<EOF
#!/bin/bash

## Specifies the interpreting shell for the job.
#$ -S /bin/bash

## Specifies that all environment variables active within the qsub utility be exported to the context of the job.
#$ -V

## Parallel programming environment (mpich) to instantiate and number of computing slots.
#$ -pe mpich ${PROCESSES}

##Passes an environment variable to the job
#$ -v  OMP_NUM_THREADS=${THREADS}

## Execute the job from the current working directory.
#$ -cwd 

## The  name  of  the  job.
#$ -N heat_mpi_nx_${SIZE}_st_${STEPS}_th_${THREADS}_pr_${PROCESSES}

## Output file path (optional)
#$ -o ${RESULTS_DIR}/heat_mpi_nx_${SIZE}_st_${STEPS}_th_${THREADS}_pr_${PROCESSES}
#$ -e ${ERRORS_DIR}/heat_mpi_nx_${SIZE}_st_${STEPS}_th_${THREADS}_pr_${PROCESSES}_errors

##send an email when the job ends
#$ -m e

##email addrees notification
##$ -M ${EMAIL}

MPICH_MACHINES=\$TMPDIR/mpich_machines
cat \$PE_HOSTFILE | awk '{print \$1":"\$2}' > \$MPICH_MACHINES

## In this line you have to write the command that will execute your application.
mpiexec -f \$MPICH_MACHINES -n \$NSLOTS ./heat_mpi ${SIZE} ${STEPS} ${BMP_DIR}/output_mpi_nx_${SIZE}_st_${STEPS}_th_${THREADS}_pr_${PROCESSES}.bmp

rm -rf \$MPICH_MACHINES

EOF
}


# Step 3: Submit the jobs

execute_script() {
    local JOB_SCRIPT=$1

    local response=$(qsub "$JOB_SCRIPT")
    local JOB_ID=$(echo $response | awk '{print $3}')
    local JOB_NAME=$(echo $response | awk -F '[()"]' '{print $3}')
    echo "Submitted job with ID: $JOB_ID ($JOB_NAME)"
    job_ids["$JOB_ID"]="$JOB_NAME"
    orders+=( "$JOB_ID" )
    if [[ "$JOB_NAME" == *"serial"* ]]; then
        job_config["$JOB_ID"]="SER"
    elif [[ "$JOB_NAME" == *"mpi"* ]]; then
        job_config["$JOB_ID"]="MPI"
    fi
}

execute_serial() {
    local size=$1
    local steps=$2
    local JOB_SCRIPT="run_simple_serial.sh"

    cd "$SERIAL_DIR"
    # Execute the script for each size and steps
    for size in "${SIZES[@]}"; do
        for steps in "${STEPS[@]}"; do
            local JOB_SCRIPT="run_simple_serial.sh"
            create_serial_script "$size" "$steps"
            execute_script $JOB_SCRIPT
        done
    done
}

execute_mpi() {
    local size=$1
    local steps=$2
    local JOB_SCRIPT="run_extended_mpi.sh"

    cd "$MPI_DIR"
    for thread in "${OMP_THREADS[@]}"; do
        for process in "${MPI_PROCESSES[@]}"; do
            for size in "${SIZES[@]}"; do
                for steps in "${STEPS[@]}"; do
                    create_mpi_script "$size" "$steps" "$thread" "$process"
                    execute_script $JOB_SCRIPT
                done
            done
        done
    done
}

find_element() {
    local element=$1
    local arr_name=("${!2}")  # Use indirect reference to the passed array

    # Loop through the array and check if the element matches
    for item in "${arr[@]}"; do
        if [[ "$item" == "$element" ]]; then
            return 0
        fi
    done

    return 1
}


# Function to check running jobs and remove finished ones
check_jobs() {
    FINISHED=1
    for job in "${orders[@]}"; do
        local found=$(qstat | awk -v id="$job" 'BEGIN { found = 0 } $1 == id {found = 1; exit;} END {print found}')
        if [ "$found" == "0" ]; then
            if [[ "${job_config[$job]}" == "SER" ]]; then
                exec_time=$(grep -oP "The Execution Time=\K[0-9\.]+" "$SERIAL_DIR/results/${job_ids[$job]}")
                printf "${GREEN}Job %s → Name: %-32s | Status: COMPLETED | Time (s): %-10.6f | Result: %s ${NC}\n" "$job" "${job_ids[$job]}" "$exec_time" "PASSED"
            elif [[ "${job_config[$job]}" == "MPI" ]]; then
                exec_time=$(grep -oP "The Execution Time=\K[0-9\.]+" "$MPI_DIR/results/${job_ids[$job]}")
                heat=$(echo "${job_ids[$job]}" | cut -d'_' -f2)
                nx=$(echo "${job_ids[$job]}" | cut -d'_' -f4)
                st=$(echo "${job_ids[$job]}" | cut -d'_' -f6)
                th=$(echo "${job_ids[$job]}" | cut -d'_' -f8)
                pr=$(echo "${job_ids[$job]}" | cut -d'_' -f10)
                # Compare the output files
                if cmp -s "$SERIAL_DIR/bmp/output_serial_nx_${nx}_st_${st}.bmp" "$MPI_DIR/bmp/output_mpi_nx_${nx}_st_${st}_th_${th}_pr_${pr}.bmp"; then
                    printf "${GREEN}Job %s → Name: %-32s | Status: COMPLETED | Time (s): %-10.6f | Result: %s ${NC}\n" "$job" "${job_ids[$job]}" "$(echo $exec_time | bc -l)" "PASSED"
                else
                    printf "${RED}Job %s → Name: %-32s | Status: COMPLETED | Time (s): %-10.6f | Result: %s ${NC}\n" "$job" "${job_ids[$job]}" "$(echo $exec_time | bc -l)" "FAILED"
                fi
            fi
        else
            printf "${YELLOW}Job %s → Name: %-32s | Status: RUNNING ${NC}\n" "$job" "${job_ids[$job]}"
            FINISHED=0
        fi
    done
}

clear_last_lines() {
    local lines=$1
    for ((i=0; i<lines; i++)); do
        tput cuu1   # Move cursor up one line
        tput el     # Clear the entire line
    done
}

set_up() {
    delete_files
    create_results_folder
    compile_heat
}

print_jobs_table() {
    finished=0
    
    echo "--> Jobs for Heat Equation Matrix <--" 
    while [[ $FINISHED -eq 0 ]]; do
        check_jobs
        if [[ $FINISHED -eq 0 ]]; then
            sleep 10
            clear_last_lines "${#job_ids[@]}"
        fi
    done
}

execute_benchmarks() {
    for config in "${CONFIG[@]}"; do
        if [ "$config" == "SER" ]; then
            execute_serial 
        elif [ "$config" == "MPI" ]; then
            execute_mpi
        fi
    done
}

extract_times() {
    sleep 2
    local RESULTS_DIR="${HEAT_DIR}/heat_results.csv"
    
    echo "config,size,steps,threads,processes,time" > "$RESULTS_DIR"
    cd "$SERIAL_DIR"
    for size in "${SIZES[@]}"; do
        for steps in "${STEPS[@]}"; do
            local exec_time=$(grep -oP "The Execution Time=\K[0-9\.]+" "$SERIAL_DIR/results/heat_serial_nx_${size}_st_${steps}")
            echo "SER,$size,$steps,1,1,$exec_time" >> "$RESULTS_DIR"
        done
    done
    for config in "${CONFIG[@]}"; do
        if [ "$config" == "MPI" ]; then
            cd "$MPI_DIR"
            for thread in "${OMP_THREADS[@]}"; do
                for process in "${MPI_PROCESSES[@]}"; do
                    for size in "${SIZES[@]}"; do
                        for steps in "${STEPS[@]}"; do
                            local exec_time=$(grep -oP "The Execution Time=\K[0-9\.]+" "$MPI_DIR/results/heat_mpi_nx_${size}_st_${steps}_th_${thread}_pr_${process}")
                            echo "MPI,$size,$steps,$thread,$process,$exec_time" >> "$RESULTS_DIR"
                        done
                    done
                done
            done
        fi
    done
    echo "Results saved to $RESULTS_DIR"
}

do_benchmarking() {
    # execute_benchmarks
    # print_jobs_table
    extract_times
}

# set_up
do_benchmarking