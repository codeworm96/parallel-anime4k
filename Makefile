EXECUTABLE := upscale
LDFLAGS=-L/usr/local/depot/cuda-10.2/lib64/ -lcudart

all: $(EXECUTABLE)

###########################################################

ARCH=$(shell uname | sed -e 's/-.*//g')
OBJDIR=objs
CXX=g++ -m64
CXXFLAGS=-Iobjs/ -O3 -Wall -mavx2 -mfma -std=c++11
HOSTNAME=$(shell hostname)

LIBS       :=
FRAMEWORKS :=

NVCCFLAGS=-O3 -m64 --gpu-architecture compute_61 -ccbin /usr/bin/gcc

LDLIBS  := $(addprefix -l, $(LIBS))
LDFRAMEWORKS := $(addprefix -framework , $(FRAMEWORKS))

NVCC=nvcc

ISPC=ispc
ISPCFLAGS=-O3 --target=avx2-i32x8 --arch=x86-64 --pic

OMP=-fopenmp -DISPC_USE_OMP

OBJS=$(OBJDIR)/upscale.o $(OBJDIR)/lodepng.o $(OBJDIR)/anime4k_seq.o\
	$(OBJDIR)/instrument.o $(OBJDIR)/anime4k_cpu.o\
	$(OBJDIR)/anime4k_kernel_task_ispc.o $(OBJDIR)/tasksys.o\
	$(OBJDIR)/anime4k_cuda.o $(OBJDIR)/anime4k_omp.o\
	$(OBJDIR)/anime4k_ispc.o $(OBJDIR)/anime4k_kernel_ispc.o

.PHONY: dirs clean

default: $(EXECUTABLE)

dirs:
		mkdir -p $(OBJDIR)/

clean:
		rm -rf $(OBJDIR) *~ $(EXECUTABLE)

$(EXECUTABLE): dirs $(OBJS)
		$(CXX) $(CXXFLAGS) $(OMP) -o $@ $(OBJS) $(LDFLAGS) $(LDLIBS) $(LDFRAMEWORKS)

$(OBJDIR)/%.o: %.cpp
		$(CXX) $< $(CXXFLAGS) -c -o $@

$(OBJDIR)/%.o: %.cu
		$(NVCC) $< $(NVCCFLAGS) -c -o $@

$(OBJDIR)/anime4k_cpu.o: $(OBJDIR)/anime4k_kernel_task_ispc.h

$(OBJDIR)/anime4k_ispc.o: $(OBJDIR)/anime4k_kernel_ispc.h

$(OBJDIR)/anime4k_omp.o: anime4k_omp.cpp
		$(CXX) $< $(CXXFLAGS) $(OMP) -c -o $@

$(OBJDIR)/tasksys.o: tasksys.cpp
		$(CXX) $< $(CXXFLAGS) $(OMP) -c -o $@

$(OBJDIR)/%_ispc.h $(OBJDIR)/%_ispc.o: %.ispc
		$(ISPC) $(ISPCFLAGS) $< -o $(OBJDIR)/$*_ispc.o -h $(OBJDIR)/$*_ispc.h
