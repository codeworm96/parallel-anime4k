#include "lodepng.h"

#include <stdio.h>
#include <stdlib.h>

#include "anime4k_seq.h"

int main() {
    unsigned int error;
    unsigned char* image = 0;
    unsigned int width, height;
    int i;
    int j;

    unsigned char* image2 = 0;

    error = lodepng_decode32_file(&image, &width, &height, "test.png");
    if(error) printf("error %u: %s\n", error, lodepng_error_text(error));

    /*use image here*/
    printf("width %u, height %u\n", width, height);

    unsigned int uwidth = width * 6;
    unsigned int uheight = height * 6;

    anime4k_seq_ctx_t *ctx = anime4k_seq_init(width, height, image, uwidth, uheight);
    anime4k_seq_run(ctx);

    image2 = anime4k_seq_get_image(ctx);

    error = lodepng_encode32_file("out.png", image2, uwidth, uheight);

    /*if there's an error, display it*/
    if(error) printf("error %u: %s\n", error, lodepng_error_text(error));

    free(image);
    anime4k_seq_free(ctx);

    return 0;
}
