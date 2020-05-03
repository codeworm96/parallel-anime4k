#include "anime4k_omp.h"

#include "instrument.h"

#include <stdlib.h>
#include <math.h>

static inline float min(float a, float b)
{
    return a < b ? a : b;
}

static inline float min3v(float a, float b, float c) {
    return min(min(a, b), c);
}

static inline float max(float a, float b)
{
    return a > b ? a : b;
}

static inline float max3v(float a, float b, float c) {
    return max(max(a, b), c);
}

Anime4kOmp::Anime4kOmp(
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

static inline void extend_rgb(float *buf, unsigned int width, unsigned int height)
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

static void decode(unsigned int width, unsigned int height,
    unsigned char *src, float *dst)
{
    START_ACTIVITY(ACTIVITY_DECODE);

    #pragma omp parallel for schedule(static)
    for (unsigned int i = 0; i < height; i++) {
        for (unsigned int j = 0; j < width; j++) {
            int old_ix = 4 * (i * width + j);
            int new_ix = 3 * ((i + 1) * (width + 2) + j + 1);
            dst[new_ix] = src[old_ix] / 255.0f;
            dst[new_ix + 1] = src[old_ix + 1] / 255.0f;
            dst[new_ix + 2] = src[old_ix + 2] / 255.0f;
        }
    }

    extend_rgb(dst, width, height);

    FINISH_ACTIVITY(ACTIVITY_DECODE);
}

static inline float interpolate(
    float tl, float tr,
    float bl, float br, float f, float g)
{
    float l = tl * (1 - f) + bl * f;
    float r = tr * (1 - f) + br * f;
    return l * (1 - g) + r * g;
}

static void linear_upscale(
    unsigned int old_width, unsigned int old_height, float *src,
    unsigned int width, unsigned int height, float *dst)
{
    START_ACTIVITY(ACTIVITY_LINEAR);

    #pragma omp parallel for schedule(static)
    for (unsigned int i = 0; i < height; i++) {
        for (unsigned int j = 0; j < width; j++) {
            float x = (float)(i * old_height) / height;
            float y = (float)(j * old_width) / width;
            float floor_x = floor(x);
            float floor_y = floor(y);
            int h = (int)floor_x + 1;
            int w = (int)floor_y + 1;
            float f = x - floor_x;
            float g = y - floor_y;

            int ix = 3 * ((i + 1) * (width + 2) + j + 1);
            int tl = 3 * (h * (old_width + 2) + w);
            int tr = tl + 3;
            int bl = tl + 3 * (old_width + 2);
            int br = bl + 3;

            dst[ix] = interpolate(
                src[tl], src[tr],
                src[bl], src[br], f, g);

            dst[ix + 1] = interpolate(
                src[tl + 1], src[tr + 1],
                src[bl + 1], src[br + 1], f, g);

            dst[ix + 2] = interpolate(
                src[tl + 2], src[tr + 2],
                src[bl + 2], src[br + 2], f, g);
        }
    }

    extend_rgb(dst, width, height);

    FINISH_ACTIVITY(ACTIVITY_LINEAR);
}

static void compute_luminance(
    unsigned int width, unsigned int height, float *src, float *dst)
{
    START_ACTIVITY(ACTIVITY_LUM);

    #pragma omp parallel for schedule(dynamic, 1)
    for (unsigned int i = 0; i < height + 2; i++) {
        for (unsigned int j = 0; j < width + 2; j++) {
            int lum_ix = i * (width + 2) + j;
            int ix = 3 * lum_ix;

            dst[lum_ix] =
                (src[ix] * 2 + src[ix + 1] * 3 + src[ix + 2]) / 6;
        }
    }

    FINISH_ACTIVITY(ACTIVITY_LUM);
}

static inline void get_largest(float strength, float *image, float *lum,
    float color[4], int cc, int a, int b, int c)
{
    float new_lum = lum[cc] * (1 - strength) +
        ((lum[a] + lum[b] + lum[c]) / 3) * strength;
    
    if (new_lum > color[3]) {
        color[0] = image[cc * 3] * (1 - strength) +
            ((image[a * 3] + image[b * 3] + image[c * 3]) / 3) * strength;
        color[1] = image[cc * 3 + 1] * (1 - strength) +
            ((image[a * 3 + 1] + image[b * 3 + 1] + image[c * 3 + 1]) / 3) * strength;
        color[2] = image[cc * 3 + 2] * (1 - strength) +
            ((image[a * 3 + 2] + image[b * 3 + 2] + image[c * 3 + 2]) / 3) * strength;
        color[3] = new_lum;
    }
}

static void thin_lines(
    float strength, unsigned int width, unsigned int height,
    float *image, float *lum, float *dst)
{
    START_ACTIVITY(ACTIVITY_THINLINES);

    unsigned int new_width = width + 2;

    #pragma omp parallel for schedule(dynamic, 1)
    for (unsigned int i = 1; i <= height; i++) {
        for (unsigned int j = 1; j <= width; j++) {
            /*
             * [tl  t tr]
             * [ l cc  r]
             * [bl  b br]
             */
            int cc_ix = i * new_width + j;
            int r_ix = cc_ix + 1;
            int l_ix = cc_ix - 1;
            int t_ix = cc_ix - new_width;
            int tl_ix = t_ix - 1;
            int tr_ix = t_ix + 1;
            int b_ix = cc_ix + new_width;
            int bl_ix = b_ix - 1;
            int br_ix = b_ix + 1;

            float cc = lum[cc_ix];
            float r = lum[r_ix];
            float l = lum[l_ix];
            float t = lum[t_ix];
            float tl = lum[tl_ix];
            float tr = lum[tr_ix];
            float b = lum[b_ix];
            float bl = lum[bl_ix];
            float br = lum[br_ix];

            float color[4];
            color[0] = image[3 * cc_ix];
            color[1] = image[3 * cc_ix + 1];
            color[2] = image[3 * cc_ix + 2];
            color[3] = cc;

            /* pattern 0 and 4 */
            float maxDark = max3v(br, b, bl);
            float minLight = min3v(tl, t, tr);

            if (minLight > cc && minLight > maxDark) {
                get_largest(strength, image, lum, color,
                    cc_ix, tl_ix, t_ix, tr_ix);
            } else {
                maxDark = max3v(tl, t, tr);
                minLight = min3v(br, b, bl);
                if (minLight > cc && minLight > maxDark) {
                    get_largest(strength, image, lum, color,
                        cc_ix, br_ix, b_ix, bl_ix);
                }
            }

            /* pattern 1 and 5 */
            maxDark = max3v(cc, l, b);
            minLight = min3v(r, t, tr);

            if (minLight > maxDark) {
                get_largest(strength, image, lum, color,
                    cc_ix, r_ix, t_ix, tr_ix);
            } else {
                maxDark = max3v(cc, r, t);
                minLight = min3v(bl, l, b);
                if (minLight > maxDark) {
                    get_largest(strength, image, lum, color,
                        cc_ix, bl_ix, l_ix, b_ix);
                }
            }

            /* pattern 2 and 6 */
            maxDark = max3v(l, tl, bl);
            minLight = min3v(r, br, tr);

            if (minLight > cc && minLight > maxDark) {
                get_largest(strength, image, lum, color,
                    cc_ix, r_ix, br_ix, tr_ix);
            } else {
                maxDark = max3v(r, br, tr);
                minLight = min3v(l, tl, bl);
                if (minLight > cc && minLight > maxDark) {
                    get_largest(strength, image, lum, color,
                        cc_ix, l_ix, tl_ix, bl_ix);
                }
            }

            /* pattern 3 and 7 */
            maxDark = max3v(cc, l, t);
            minLight = min3v(r, br, b);

            if (minLight > maxDark) {
                get_largest(strength, image, lum, color,
                    cc_ix, r_ix, br_ix, b_ix);
            } else {
                maxDark = max3v(cc, r, b);
                minLight = min3v(t, l, tl);
                if (minLight > maxDark) {
                    get_largest(strength, image, lum, color,
                        cc_ix, t_ix, l_ix, tl_ix);
                }
            }

            dst[3 * cc_ix] = color[0];
            dst[3 * cc_ix + 1] = color[1];
            dst[3 * cc_ix + 2] = color[2];
        }
    }

    extend_rgb(dst, width, height);

    FINISH_ACTIVITY(ACTIVITY_THINLINES);
}

static inline float clamp(float x, float lower, float upper)
{
    return x < lower ? lower : (x > upper ? upper : x);
}

static void compute_gradient(unsigned int width, unsigned int height,
    float *src, float *dst)
{
    START_ACTIVITY(ACTIVITY_GRADIENT);

    unsigned int new_width = width + 2;

    #pragma omp parallel for schedule(static)
    for (unsigned int i = 1; i <= height; i++) {
        for (unsigned int j = 1; j <= width; j++) {
            /*
             * [tl  t tr]
             * [ l cc  r]
             * [bl  b br]
             */
            int cc_ix = i * new_width + j;
            int r_ix = cc_ix + 1;
            int l_ix = cc_ix - 1;
            int t_ix = cc_ix - new_width;
            int tl_ix = t_ix - 1;
            int tr_ix = t_ix + 1;
            int b_ix = cc_ix + new_width;
            int bl_ix = b_ix - 1;
            int br_ix = b_ix + 1;

            float r = src[r_ix];
            float l = src[l_ix];
            float t = src[t_ix];
            float tl = src[tl_ix];
            float tr = src[tr_ix];
            float b = src[b_ix];
            float bl = src[bl_ix];
            float br = src[br_ix];

            /* Horizontal Gradient
             * [-1  0  1]
             * [-2  0  2]
             * [-1  0  1]
             */
            float xgrad = tr - tl + r + r - l - l + br - bl;

            /* Vertical Gradient
             * [-1 -2 -1]
             * [ 0  0  0]
             * [ 1  2  1]
             */
            float ygrad = bl - tl + b + b - t - t + br - tr;

            dst[cc_ix] =
                1.0f - clamp(sqrt(xgrad * xgrad + ygrad * ygrad), 0.0f, 1.0f);
        }
    }

    extend(dst, width, height);

    FINISH_ACTIVITY(ACTIVITY_GRADIENT);
}

static inline unsigned char quantize(float x)
{
    int r = x * 255;
    return r < 0 ? 0 : (r > 255 ? 255 : r);
}

static inline void get_average(float strength, float *src, unsigned char *dst,
    int ix, int cc, int a, int b, int c)
{
    float red = src[cc * 3] * (1 - strength) +
        ((src[a * 3] + src[b * 3] + src[c * 3]) / 3) * strength;
    float green = src[cc * 3 + 1] * (1 - strength) +
        ((src[a * 3 + 1] + src[b * 3 + 1] + src[c * 3 + 1]) / 3) * strength;
    float blue = src[cc * 3 + 2] * (1 - strength) +
        ((src[a * 3 + 2] + src[b * 3 + 2] + src[c * 3 + 2]) / 3) * strength;

    dst[ix] = quantize(red);
    dst[ix + 1] = quantize(green);
    dst[ix + 2] = quantize(blue);
    dst[ix + 3] = 255;
}

static void refine(float strength, unsigned int width, unsigned int height,
    float *image, float *gradients, unsigned char *dst)
{
    START_ACTIVITY(ACTIVITY_REFINE);

    unsigned int new_width = width + 2;

    #pragma omp parallel for schedule(dynamic, 1)
    for (unsigned int i = 1; i <= height; i++) {
        for (unsigned int j = 1; j <= width; j++) {
            /*
             * [tl  t tr]
             * [ l cc  r]
             * [bl  b br]
             */
            int ix = 4 * ((i - 1) * width + j - 1);
            int cc_ix = i * new_width + j;
            int r_ix = cc_ix + 1;
            int l_ix = cc_ix - 1;
            int t_ix = cc_ix - new_width;
            int tl_ix = t_ix - 1;
            int tr_ix = t_ix + 1;
            int b_ix = cc_ix + new_width;
            int bl_ix = b_ix - 1;
            int br_ix = b_ix + 1;

            float cc = gradients[cc_ix];
            float r = gradients[r_ix];
            float l = gradients[l_ix];
            float t = gradients[t_ix];
            float tl = gradients[tl_ix];
            float tr = gradients[tr_ix];
            float b = gradients[b_ix];
            float bl = gradients[bl_ix];
            float br = gradients[br_ix];

            /* pattern 0 and 4 */
            float maxDark = max3v(br, b, bl);
            float minLight = min3v(tl, t, tr);

            if (minLight > cc && minLight > maxDark) {
                get_average(strength, image, dst,
                    ix, cc_ix, tl_ix, t_ix, tr_ix);
                continue;
            } else {
                maxDark = max3v(tl, t, tr);
                minLight = min3v(br, b, bl);
                if (minLight > cc && minLight > maxDark) {
                    get_average(strength, image, dst,
                        ix, cc_ix, br_ix, b_ix, bl_ix);
                    continue;
                }
            }

            /* pattern 1 and 5 */
            maxDark = max3v(cc, l, b);
            minLight = min3v(r, t, tr);

            if (minLight > maxDark) {
                get_average(strength, image, dst,
                    ix, cc_ix, r_ix, t_ix, tr_ix);
                continue;
            } else {
                maxDark = max3v(cc, r, t);
                minLight = min3v(bl, l, b);
                if (minLight > maxDark) {
                    get_average(strength, image, dst,
                        ix, cc_ix, bl_ix, l_ix, b_ix);
                    continue;
                }
            }

            /* pattern 2 and 6 */
            maxDark = max3v(l, tl, bl);
            minLight = min3v(r, br, tr);

            if (minLight > cc && minLight > maxDark) {
                get_average(strength, image, dst,
                    ix, cc_ix, r_ix, br_ix, tr_ix);
                continue;
            } else {
                maxDark = max3v(r, br, tr);
                minLight = min3v(l, tl, bl);
                if (minLight > cc && minLight > maxDark) {
                    get_average(strength, image, dst,
                        ix, cc_ix, l_ix, tl_ix, bl_ix);
                    continue;
                }
            }

            /* pattern 3 and 7 */
            maxDark = max3v(cc, l, t);
            minLight = min3v(r, br, b);

            if (minLight > maxDark) {
                get_average(strength, image, dst,
                    ix, cc_ix, r_ix, br_ix, b_ix);
                continue;
            } else {
                maxDark = max3v(cc, r, b);
                minLight = min3v(t, l, tl);
                if (minLight > maxDark) {
                    get_average(strength, image, dst,
                        ix, cc_ix, t_ix, l_ix, tl_ix);
                    continue;
                }
            }

            /* fallback */
            dst[ix] = quantize(image[3 * cc_ix]);
            dst[ix + 1] = quantize(image[3 * cc_ix + 1]);
            dst[ix + 2] = quantize(image[3 * cc_ix + 2]);
            dst[ix + 3] = 255;
        }
    }

    /* this is the final step, no need to extend the border */

    FINISH_ACTIVITY(ACTIVITY_REFINE);
}

void Anime4kOmp::run()
{
    decode(old_width_, old_height_, image_, original_);
    linear_upscale(old_width_, old_height_, original_,
        width_, height_, enlarge_);
    compute_luminance(width_, height_, enlarge_, lum_);
    thin_lines(strength_thinlines_, width_, height_,
        enlarge_, lum_, thinlines_);
    compute_luminance(width_, height_, thinlines_, lum_);
    compute_gradient(width_, height_, lum_, gradients_);
    refine(strength_refine_, width_, height_, thinlines_, gradients_, result_);
}

Anime4kOmp::~Anime4kOmp()
{
    delete [] original_;
    delete [] enlarge_;
    delete [] lum_;
    delete [] thinlines_;
    delete [] gradients_;
    delete [] result_;
}
