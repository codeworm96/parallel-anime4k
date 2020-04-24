EXECUTABLE := upscale
LDFLAGS=-L/usr/local/depot/cuda-10.2/lib64/ -lcudart

all: $(EXECUTABLE)

###########################################################

ARCH=$(shell uname | sed -e 's/-.*//g')
OBJDIR=objs
CXX=g++ -m64
CXXFLAGS=-Iobjs/ -O3 -Wall -mavx2 -mfma
HOSTNAME=$(shell hostname)

LIBS       :=
FRAMEWORKS :=

NVCCFLAGS=-O3 -m64 --gpu-architecture compute_61 -ccbin /usr/bin/gcc

LDLIBS  := $(addprefix -l, $(LIBS))
LDFRAMEWORKS := $(addprefix -framework , $(FRAMEWORKS))

NVCC=nvcc

ISPC=ispc
ISPCFLAGS=-O3 --target=avx2-i32x8 --arch=x86-64 --pic

OBJS=$(OBJDIR)/upscale.o $(OBJDIR)/lodepng.o $(OBJDIR)/anime4k_seq.o\
	$(OBJDIR)/instrument.o $(OBJDIR)/anime4k_ispc.o\
	$(OBJDIR)/anime4k_kernel_ispc.o $(OBJDIR)/anime4k_cuda.o

.PHONY: dirs clean

default: $(EXECUTABLE)

dirs:
		mkdir -p $(OBJDIR)/

clean:
		rm -rf $(OBJDIR) *~ $(EXECUTABLE)

$(EXECUTABLE): dirs $(OBJS)
		$(CXX) $(CXXFLAGS) -o $@ $(OBJS) $(LDFLAGS) $(LDLIBS) $(LDFRAMEWORKS)

$(OBJDIR)/%.o: %.cpp
		$(CXX) $< $(CXXFLAGS) -c -o $@

$(OBJDIR)/%.o: %.cu
		$(NVCC) $< $(NVCCFLAGS) -c -o $@

$(OBJDIR)/anime4k_ispc.o: $(OBJDIR)/anime4k_kernel_ispc.h

$(OBJDIR)/%_ispc.h $(OBJDIR)/%_ispc.o: %.ispc
		$(ISPC) $(ISPCFLAGS) $< -o $(OBJDIR)/$*_ispc.o -h $(OBJDIR)/$*_ispc.h
