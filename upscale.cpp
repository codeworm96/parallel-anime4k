#include "lodepng.h"

#include <stdio.h>
#include <stdlib.h>

#include "anime4k.h"
#include "anime4k_seq.h"

int main() {
    unsigned int error;
    unsigned char* image = 0;
    unsigned int width, height;

    unsigned char* image2 = 0;

    error = lodepng_decode32_file(&image, &width, &height, "test.png");
    if(error) printf("error %u: %s\n", error, lodepng_error_text(error));

    /*use image here*/
    printf("width %u, height %u\n", width, height);

    unsigned int uwidth = width * 6;
    unsigned int uheight = height * 6;

    Anime4k* upscaler = new Anime4kSeq(width, height, image, uwidth, uheight);

    upscaler->run();

    image2 = upscaler->get_image();

    error = lodepng_encode32_file("out.png", image2, uwidth, uheight);

    /*if there's an error, display it*/
    if(error) printf("error %u: %s\n", error, lodepng_error_text(error));

    free(image);
    delete upscaler;

    return 0;
}
