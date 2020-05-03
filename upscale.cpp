#include "lodepng.h"
#include "cycleTimer.h"
#include "instrument.h"

#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>

#include "anime4k.h"
#include "anime4k_seq.h"
#include "anime4k_cuda.h"
#include "anime4k_cpu.h"
#include "anime4k_omp.h"
#include "anime4k_ispc.h"

static void usage(char *name) {
    const char *use_string = "-i IFILE [-o OFILE] [-b IMP] [-n TIMES] [-W WIDTH] [-H HEIGHT] [-I]";
    printf("Usage: %s %s\n", name, use_string);
    printf("   -h        Print this message\n");
    printf("   -i IFILE  Input image file\n");
    printf("   -o OFILE  Output image file\n");
    printf("   -b IMP    Backend implementation\n");
    printf("   -n TIMES  Number of benchmark rounds\n");
    printf("   -W WIDTH  Width of the output\n");
    printf("   -H HEIGHT Height of the output\n");
    printf("   -I        Instrument\n");
    exit(0);
}


int main(int argc, char *argv[]) {
    char *ifile = NULL;
    char *ofile = NULL;
    const char *backend = "cuda";
    int times = 100;
    unsigned int width = 3840;
    unsigned int height = 2160;
    unsigned int error;
    unsigned char* image = 0;
    unsigned int old_width, old_height;
    bool instrument = false;

    const char *optstring = "hi:o:b:n:W:H:I";
    int c;
    while ((c = getopt(argc, argv, optstring)) != -1) {
        switch(c) {
        case 'h':
            usage(argv[0]);
            break;
        case 'i':
            ifile = optarg;
            break;
        case 'o':
            ofile = optarg;
            break;
        case 'b':
            backend = optarg;
            break;
        case 'n':
            times = atoi(optarg);
            break;
        case 'W':
            width = atoi(optarg);
            break;
        case 'H':
            height = atoi(optarg);
            break;
        case 'I':
            instrument = true;
            break;
        default:
            printf("Unknown option '%c'\n", c);
            usage(argv[0]);
            exit(1);
        }
    }

    if (ifile == NULL) {
        printf("Need input file\n");
        usage(argv[0]);
        exit(1);
    }

    error = lodepng_decode32_file(&image, &old_width, &old_height, ifile);
    if (error) {
        printf("error %u: %s\n", error, lodepng_error_text(error));
        exit(1);
    }

    Anime4k* upscaler;
    if (strcasecmp(backend, "seq")==0) {
        upscaler = new Anime4kSeq(old_width, old_height, image, width, height);
    } else if (strcasecmp(backend, "cuda")==0) {
        upscaler = new Anime4kCuda(old_width, old_height, image, width, height);
    } else if (strcasecmp(backend, "cpu")==0) {
        upscaler = new Anime4kCpu(old_width, old_height, image, width, height);
    } else if (strcasecmp(backend, "omp")==0) {
        upscaler = new Anime4kOmp(old_width, old_height, image, width, height);
    } else if (strcasecmp(backend, "ispc")==0) {
        upscaler = new Anime4kIspc(old_width, old_height, image, width, height);
    } else {
        printf("%s backend is not implemented\n", backend);
        exit(1);
    }

    track_activity(instrument);
    double startTime = CycleTimer::currentSeconds();

    for (int i = 0; i < times; i++) {
        upscaler->run();
    }

    double endTime = CycleTimer::currentSeconds();
    double totalTime = endTime - startTime;

    SHOW_ACTIVITY(stderr, instrument);
    fprintf(stderr, "Upscaled %d frames in %.4f s (%.4f fps)\n",
        times, totalTime, times / totalTime);

    if (ofile) {
        error = lodepng_encode32_file(ofile, upscaler->get_image(), width, height);
        if (error) {
            printf("error %u: %s\n", error, lodepng_error_text(error));
        }   
    }

    delete upscaler;
    free(image);

    return 0;
}
