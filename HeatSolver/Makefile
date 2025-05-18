CC = mpicc
CFLAGS = -fopenmp -lm -std=c99
TARGET = heat_mpi
SRC = heat_mpi.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(SRC) -o $(TARGET) $(CFLAGS)

clean:
	rm -f $(TARGET)