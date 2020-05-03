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
    unsigned int old_pixels = (width + 2) * (height + 2);
    unsigned int pixels = (new_width + 2) * (new_height + 2);

    original_red_ = new float[old_pixels];
    original_green_ = new float[old_pixels];
    original_blue_ = new float[old_pixels];

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

static void extend(float *buf, unsigned int width, unsigned int height)
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

void Anime4kIspc::run()
{
    START_ACTIVITY(ACTIVITY_DECODE);
    ispc::decode(old_width_, old_height_, (int *)image_,
        original_red_, original_green_, original_blue_);
    extend(original_red_, old_width_, old_height_);
    extend(original_green_, old_width_, old_height_);
    extend(original_blue_, old_width_, old_height_);
    FINISH_ACTIVITY(ACTIVITY_DECODE);

    START_ACTIVITY(ACTIVITY_LINEAR);
    ispc::linear_upscale(old_width_, old_height_,
        original_red_, original_green_, original_blue_,
        width_, height_,
        enlarge_red_, enlarge_green_, enlarge_blue_, lum1_);
    extend(enlarge_red_, width_, height_);
    extend(enlarge_green_, width_, height_);
    extend(enlarge_blue_, width_, height_);
    extend(lum1_, width_, height_);
    FINISH_ACTIVITY(ACTIVITY_LINEAR);

    START_ACTIVITY(ACTIVITY_THINLINES);
    ispc::thin_lines(strength_thinlines_, width_, height_,
        enlarge_red_, enlarge_green_, enlarge_blue_, lum1_,
        thinlines_red_, thinlines_green_, thinlines_blue_, lum2_);
    extend(thinlines_red_, width_, height_);
    extend(thinlines_green_, width_, height_);
    extend(thinlines_blue_, width_, height_);
    extend(lum2_, width_, height_);
    FINISH_ACTIVITY(ACTIVITY_THINLINES);

    START_ACTIVITY(ACTIVITY_GRADIENT);
    ispc::compute_gradient(width_, height_, lum2_, gradients_);
    extend(gradients_, width_, height_);
    FINISH_ACTIVITY(ACTIVITY_GRADIENT);

    START_ACTIVITY(ACTIVITY_REFINE);
    ispc::refine(strength_refine_, width_, height_,
        thinlines_red_, thinlines_green_, thinlines_blue_,
        gradients_, (int *)result_);
    FINISH_ACTIVITY(ACTIVITY_REFINE);
}

Anime4kIspc::~Anime4kIspc()
{
    delete [] original_red_;
    delete [] original_green_;
    delete [] original_blue_;
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
