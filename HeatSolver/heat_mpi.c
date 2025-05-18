#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <mpi.h>
#include <omp.h>

#define BMP_HEADER_SIZE 54
#define ALPHA 0.01      //Thermal diffusivity
#define L 0.2           // Length (m) of the square domain
#define DX 0.02         // local_grid spacing in x-direction
#define DY 0.02         // local_grid spacing in y-direction
#define DT 0.0005       // Time step
#define T 1500.0        //Temperature on ºk of the heat source

void exchange_ghost_cells(double *local_grid, int local_nx, int global_ny, int rank, int size) {
    if (rank > 0) {
        MPI_Sendrecv(&local_grid[1 * global_ny], global_ny, MPI_DOUBLE, rank - 1, 0,
                     &local_grid[0 * global_ny], global_ny, MPI_DOUBLE, rank - 1, 0,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    }
    if (rank < size - 1) {
        MPI_Sendrecv(&local_grid[(local_nx - 2) * global_ny], global_ny, MPI_DOUBLE, rank + 1, 0,
                     &local_grid[(local_nx - 1) * global_ny], global_ny, MPI_DOUBLE, rank + 1, 0,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    }
}

void update_local_grid(double *local_grid, double *new_local_grid, int nx, int ny, double r) {
    int i, j;
    #pragma omp parallel for private(i, j) collapse(2)
    for (i = 1; i < nx - 1; i++) {
        for (j = 1; j < ny - 1; j++) {
            new_local_grid[i * ny + j] = local_grid[i * ny + j] 
                + r * (local_grid[(i + 1) * ny + j] + local_grid[(i - 1) * ny + j] - 2 * local_grid[i * ny + j])
                + r * (local_grid[i * ny + j + 1] + local_grid[i * ny + j - 1] - 2 * local_grid[i * ny + j]);
        }
    }
}

void apply_boundaries(double *local_grid, int local_nx, int ny, int rank, int size) {
    int i, j;

    if (rank == 0) {    
        // First process sets the first row to 0
        #pragma omp parallel for private(j)
        for (j = 0; j < ny; j++) {
            local_grid[1 * ny + j] = 0.0;
        }
    } else if (rank == size - 1) {  
        // Last process sets the last row to 0
        #pragma omp parallel for private(j)
        for (j = 0; j < ny; j++) {
            local_grid[(local_nx - 2) * ny + j] = 0.0;
        }
    }

    // Lateral boundaries are set to 0
    #pragma omp parallel for private(i)
    for (i = 0; i < local_nx; i++) {
        local_grid[i * ny + 0] = 0.0;
        local_grid[i * ny + (ny - 1)] = 0.0;
    }
}

void solve_heat_equation(double *local_grid, double *new_local_grid, int steps, double r, int local_nx, int global_ny, int rank, int size) {
    for (int step = 0; step < steps; step++) {
        exchange_ghost_cells(local_grid, local_nx, global_ny, rank, size);
        update_local_grid(local_grid, new_local_grid, local_nx, global_ny, r);
        apply_boundaries(new_local_grid, local_nx, global_ny, rank, size); 

        double *tmp = local_grid;
        local_grid = new_local_grid;
        new_local_grid = tmp;
    }
}

void initialize_local_grid(double *local_grid, int local_nx, int ny, int global_start) {
    int i, j;

    #pragma omp parallel for private(i, j)
    for (i = 1; i < local_nx - 1; i++) {
        int global_i = global_start + i - 1;
        for (j = 0; j < ny; j++) {
            if (global_i == j || global_i == ny - 1 - j) local_grid[i * ny + j] = T;
            else local_grid[i * ny + j] = 0.0;
        }
    }
}

// Function to write BMP file header
void write_bmp_header(FILE *file, int width, int height) {
    unsigned char header[BMP_HEADER_SIZE] = { 0 };

    int file_size = BMP_HEADER_SIZE + 3 * width * height;
    header[0] = 'B';
    header[1] = 'M';
    header[2] = file_size & 0xFF;
    header[3] = (file_size >> 8) & 0xFF;
    header[4] = (file_size >> 16) & 0xFF;
    header[5] = (file_size >> 24) & 0xFF;
    header[10] = BMP_HEADER_SIZE;

    header[14] = 40;  // Info header size
    header[18] = width & 0xFF;
    header[19] = (width >> 8) & 0xFF;
    header[20] = (width >> 16) & 0xFF;
    header[21] = (width >> 24) & 0xFF;
    header[22] = height & 0xFF;
    header[23] = (height >> 8) & 0xFF;
    header[24] = (height >> 16) & 0xFF;
    header[25] = (height >> 24) & 0xFF;
    header[26] = 1;   // Planes
    header[28] = 24;  // Bits per pixel

    fwrite(header, 1, BMP_HEADER_SIZE, file);
}

void get_color(double value, unsigned char *r, unsigned char *g, unsigned char *b) {

    if (value >= 500.0) {
        *r = 255; *g = 0; *b = 0; // Red
    }
    else if (value >= 100.0) {
        *r = 255; *g = 128; *b = 0; // Orange
    }
    else if (value >= 50.0) {
        *r = 171; *g = 71; *b = 188; // Lilac
    }
    else if (value >= 25) {
        *r = 255; *g = 255; *b = 0; // Yellow
    }
    else if (value >= 1) {
        *r = 0; *g = 0; *b = 255; // Blue
    }
    else if (value >= 0.1) {
        *r = 5; *g = 248; *b = 252; // Cyan
    }
    else {
        *r = 255; *g = 255; *b = 255; // white
    }
}

//Function to write the local_grid matrix into the file
void write_local_grid(FILE *file, double *local_grid, int nx, int ny) {
    int i, j, padding;
    
    // Write pixel data to BMP file
    for (i = nx - 1; i >= 0; i--) { // BMP format stores pixels bottom-to-top
        for (j = 0; j < ny; j++) {
            unsigned char r, g, b;
            get_color(local_grid[i * ny + j], &r, &g, &b);
            fwrite(&b, 1, 1, file); // Write blue channel
            fwrite(&g, 1, 1, file); // Write green channel
            fwrite(&r, 1, 1, file); // Write red channel
        }
        // Row padding for 4-byte alignment (if necessary)
        for (padding = 0; padding < (4 - (nx * 3) % 4) % 4; padding++) {
            fputc(0, file);
        }
    }
}

int main(int argc, char *argv[]) {
    double time_begin, time_end;
    double r; // constant of the heat equation
    int global_nx, global_ny; // Grid size in x-direction and y-direction
    int steps; // Number of time steps
    int rank, size;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (argc != 4) {
        if (rank == 0) {
            printf("Command line wrong\n");
            printf("Command line should be: heat_serial size steps name_output_file.bmp. \n");
            printf("Try again!!!!\n");
        }
        MPI_Finalize();
        return 1;
    }

    global_nx = global_ny = atoi(argv[1]);
    r = ALPHA * DT / (DX * DY);
    steps = atoi(argv[2]);
    time_begin = MPI_Wtime();

    int base_rows = global_nx / size;
    int remainder = global_nx % size;
    int local_real_nx = base_rows + (rank < remainder ? 1 : 0);
    int global_start = rank * base_rows + (rank < remainder ? rank : remainder);
    int local_nx = local_real_nx + 2;

    // Allocate memory for the grids
    double *local_grid = calloc(local_nx * global_ny, sizeof(double));
    double *new_local_grid = calloc(local_nx * global_ny, sizeof(double));
    double *global_grid = NULL;

    if (rank == 0) global_grid = malloc(global_nx * global_ny * sizeof(double));

    initialize_local_grid(local_grid, local_nx, global_ny, global_start);

    // Solve heat equation
    solve_heat_equation(local_grid, new_local_grid, steps, r, local_nx, global_ny, rank, size);

    int *recvcounts = NULL,
    *displs = NULL;
    
    if (rank == 0) {
        recvcounts = malloc(size * sizeof(int));
        displs = malloc(size * sizeof(int));
    }

    int sendcount = local_real_nx * global_ny;
    MPI_Gather(&sendcount, 1, MPI_INT, recvcounts, 1, MPI_INT, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        displs[0] = 0;
        for (int i = 1; i < size; i++)
            displs[i] = displs[i - 1] + recvcounts[i - 1];
    }

    MPI_Gatherv(&local_grid[1 * global_ny], sendcount, MPI_DOUBLE,
                global_grid, recvcounts, displs, MPI_DOUBLE,
                0, MPI_COMM_WORLD);


    free(local_grid); 
    free(new_local_grid);
    
    if (rank == 0) {
        //Write grid into a bmp file
        FILE *file = fopen(argv[3], "wb");
        if (!file) {
            printf("Error opening the output file.\n");
            return 1;
        }

        write_bmp_header(file, global_nx, global_ny);
        write_local_grid(file, global_grid, global_nx, global_ny);
        fclose(file);

        free(global_grid);
        free(recvcounts);
        free(displs);

        double time_end = MPI_Wtime();
        printf("The Execution Time=%fs with a matrix size of %dx%d and %d steps\n", (time_end - time_begin), global_nx, global_ny, steps);
    }

    MPI_Finalize();
    return 0;
}