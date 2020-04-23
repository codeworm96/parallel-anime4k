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

    original_ = new float[3 * old_pixels];
    enlarge_ = new float[3 * pixels];
    lum_ = new float[pixels];
    thinlines_ = new float[3 * pixels];
    gradients_ = new float[pixels];
    refined_ = new float[3 * pixels];

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

static void extend_rgb(float *buf, unsigned int width, unsigned int height)
{
    unsigned int new_width = width + 2;

    for (unsigned int i = 1; i <= height; i++) {
        /* left */
        int left = 3 * (i * new_width + 1);
        buf[left - 3] = buf[left];
        buf[left - 2] = buf[left + 1];
        buf[left - 1] = buf[left + 2];

        /* right */
        int right = 3 * (i * new_width + width);
        buf[right + 3] = buf[right];
        buf[right + 4] = buf[right + 1];
        buf[right + 5] = buf[right + 2];
    }

    for (unsigned int i = 0; i < new_width; i++) {
        /* top */
        int top_from = 3 * (new_width + i);
        int top_to = 3 * i;
        buf[top_to] = buf[top_from];
        buf[top_to + 1] = buf[top_from + 1];
        buf[top_to + 2] = buf[top_from + 2];

        /* bottom */
        int bottom_from = 3 * (height * new_width + i);
        int bottom_to = 3 * ((height + 1) * new_width + i);
        buf[bottom_to] = buf[bottom_from];
        buf[bottom_to + 1] = buf[bottom_from + 1];
        buf[bottom_to + 2] = buf[bottom_from + 2];
    }
}

void Anime4kIspc::run()
{
    START_ACTIVITY(ACTIVITY_DECODE);
    ispc::decode(old_width_, old_height_, image_, original_);
    extend_rgb(original_, old_width_, old_height_);
    FINISH_ACTIVITY(ACTIVITY_DECODE);

    START_ACTIVITY(ACTIVITY_LINEAR);
    ispc::linear_upscale(old_width_, old_height_, original_,
        width_, height_, enlarge_);
    extend_rgb(enlarge_, width_, height_);
    FINISH_ACTIVITY(ACTIVITY_LINEAR);

    START_ACTIVITY(ACTIVITY_LUM);
    ispc::compute_luminance(width_, height_, enlarge_, lum_);
    FINISH_ACTIVITY(ACTIVITY_LUM);

    START_ACTIVITY(ACTIVITY_THINLINES);
    ispc::thin_lines(strength_thinlines_, width_, height_,
        enlarge_, lum_, thinlines_);
    extend_rgb(thinlines_, width_, height_);
    FINISH_ACTIVITY(ACTIVITY_THINLINES);

    START_ACTIVITY(ACTIVITY_LUM);
    ispc::compute_luminance(width_, height_, thinlines_, lum_);
    FINISH_ACTIVITY(ACTIVITY_LUM);

    START_ACTIVITY(ACTIVITY_GRADIENT);
    ispc::compute_gradient(width_, height_, lum_, gradients_);
    extend(gradients_, width_, height_);
    FINISH_ACTIVITY(ACTIVITY_GRADIENT);

    START_ACTIVITY(ACTIVITY_REFINE);
    ispc::refine(strength_refine_, width_, height_, thinlines_, gradients_, refined_);
    FINISH_ACTIVITY(ACTIVITY_REFINE);

    START_ACTIVITY(ACTIVITY_ENCODE);
    ispc::encode(width_, height_, refined_, result_);
    FINISH_ACTIVITY(ACTIVITY_ENCODE);
}

Anime4kIspc::~Anime4kIspc()
{
    delete [] original_;
    delete [] enlarge_;
    delete [] lum_;
    delete [] thinlines_;
    delete [] gradients_;
    delete [] refined_;
    delete [] result_;
}
