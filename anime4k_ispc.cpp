#include "anime4k_ispc.h"

#include "instrument.h"
#include "anime4k_kernel_ispc.h"

#include <stdlib.h>

static inline float min(float a, float b)
{
    return a < b ? a : b;
}

Anime4kIspc::Anime4kIspc(
    unsigned int width, unsigned int height, unsigned char *image,
    unsigned int new_width, unsigned int new_height)
{
    old_width_ = width;
    old_height_ = height;
    image_ = image;
    width_ = new_width;
    height_ = new_height;

    /* ghost pixels added to avoid out-of-bounds */
    unsigned int pixels = (new_width + 2) * (new_height + 2);

    enlarge_red_ = new float[pixels];
    enlarge_green_ = new float[pixels];
    enlarge_blue_ = new float[pixels];

    lum1_ = new float[pixels];

    thinlines_red_ = new float[pixels];
    thinlines_green_ = new float[pixels];
    thinlines_blue_ = new float[pixels];

    lum2_ = new float[pixels];

    gradients_ = new float[pixels];

    // result does not need ghost pixels
    result_ = new unsigned char[4 * new_width * new_height];

    strength_thinlines_ =
        min((float)new_width / width / 6, 1.0f);
    strength_refine_ =
        min((float)new_width / width / 2, 1.0f);
}

static inline void extend(float *buf, unsigned int width, unsigned int height)
{
    unsigned int new_width = width + 2;

    for (unsigned int i = 1; i <= height; i++) {
        /* left */
        int left = i * new_width;
        buf[left] = buf[left + 1];

        /* right */
        int right = i * new_width + width;
        buf[right + 1] = buf[right];
    }

    for (unsigned int i = 0; i < new_width; i++) {
        /* top */
        buf[i] = buf[i + new_width];

        /* bottom */
        int bottom_from = height * new_width + i;
        int bottom_to = bottom_from + new_width;
        buf[bottom_to] = buf[bottom_from];
    }
}

static inline void linear_upscale(int old_width, int old_height, int *src,
    int width, int height,
    float *dst_red, float *dst_green, float *dst_blue, float *lum)
{
    START_ACTIVITY(ACTIVITY_LINEAR);

    #pragma omp parallel for schedule(static)
    for (int i = 0; i < height; i++) {
        ispc::linear_upscale_kernel(old_width, old_height, src,
            width, height, dst_red, dst_green, dst_blue, lum, i);
    }

    extend(dst_red, width, height);
    extend(dst_green, width, height);
    extend(dst_blue, width, height);
    extend(lum, width, height);

    FINISH_ACTIVITY(ACTIVITY_LINEAR);
}

static inline void thin_lines(float strength,
    unsigned int width, unsigned int height,
    float *image_red, float *image_green, float *image_blue,
    float *src_lum,
    float *dst_red, float *dst_green, float *dst_blue,
    float *dst_lum)
{
    START_ACTIVITY(ACTIVITY_THINLINES);

    #pragma omp parallel for schedule(static)
    for (unsigned int i = 1; i <= height; i++) {
        ispc::thin_lines_kernel(strength, width, height,
            image_red, image_green, image_blue, src_lum,
            dst_red, dst_green, dst_blue, dst_lum, i);
    }

    extend(dst_red, width, height);
    extend(dst_green, width, height);
    extend(dst_blue, width, height);
    extend(dst_lum, width, height);

    FINISH_ACTIVITY(ACTIVITY_THINLINES);
}

static inline void compute_gradient(
    unsigned int width, unsigned int height,
    float *src, float *dst)
{
    START_ACTIVITY(ACTIVITY_GRADIENT);

    #pragma omp parallel for schedule(static)
    for (unsigned int i = 1; i <= height; i++) {
        ispc::compute_gradient_kernel(width, height, src, dst, i);
    }

    extend(dst, width, height);

    FINISH_ACTIVITY(ACTIVITY_GRADIENT);
}

static inline void refine(
    float strength, unsigned int width, unsigned int height,
    float *image_red, float *image_green, float *image_blue,
    float *gradients, int *dst)
{
    START_ACTIVITY(ACTIVITY_REFINE);

    #pragma omp parallel for schedule(static)
    for (unsigned int i = 1; i <= height; i++) {
        ispc::refine_kernel(strength, width, height,
            image_red, image_green, image_blue,
            gradients, dst, i);
    }

    FINISH_ACTIVITY(ACTIVITY_REFINE);
}

void Anime4kIspc::run()
{
    linear_upscale(old_width_, old_height_, (int *)image_,
        width_, height_,
        enlarge_red_, enlarge_green_, enlarge_blue_, lum1_);

    thin_lines(strength_thinlines_, width_, height_,
        enlarge_red_, enlarge_green_, enlarge_blue_, lum1_,
        thinlines_red_, thinlines_green_, thinlines_blue_, lum2_);

    compute_gradient(width_, height_, lum2_, gradients_);

    refine(strength_refine_, width_, height_,
        thinlines_red_, thinlines_green_, thinlines_blue_,
        gradients_, (int *)result_);
}

Anime4kIspc::~Anime4kIspc()
{
    delete [] enlarge_red_;
    delete [] enlarge_green_;
    delete [] enlarge_blue_;
    delete [] lum1_;
    delete [] thinlines_red_;
    delete [] thinlines_green_;
    delete [] thinlines_blue_;
    delete [] lum2_;
    delete [] gradients_;
    delete [] result_;
}
