#include "anime4k_seq.h"

#include <stdlib.h>
#include <math.h>

static inline double min(double a, double b)
{
    return a < b ? a : b;
}

static inline double min3v(double a, double b, double c) {
    return min(min(a, b), c);
}

static inline double max(double a, double b)
{
    return a > b ? a : b;
}

static inline double max3v(double a, double b, double c) {
    return max(max(a, b), c);
}

Anime4kSeq::Anime4kSeq(
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

    original_ = new double[3 * old_pixels];
    enlarge_ = new double[3 * pixels];
    lum_ = new double[pixels];
    preprocessing_ = new double[3 * pixels];
    gradients_ = new double[pixels];
    final_ = new double[3 * pixels];

    // result does not need ghost pixels
    result_ = new unsigned char[4 * new_width * new_height];

    strength_preprocessing_ =
        min((double)new_width / width / 6.0, 1.0);
    strength_push_ =
        min((double)new_width / width / 2.0, 1.0);
}

static void extend(double *buf, unsigned int width, unsigned int height)
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

static void extend_rgb(double *buf, unsigned int width, unsigned int height)
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
    unsigned char *src, double *dst)
{
    for (unsigned int i = 0; i < height; i++) {
        for (unsigned int j = 0; j < width; j++) {
            int old_ix = 4 * (i * width + j);
            int new_ix = 3 * ((i + 1) * (width + 2) + j + 1);
            dst[new_ix] = src[old_ix] / 255.0;
            dst[new_ix + 1] = src[old_ix + 1] / 255.0;
            dst[new_ix + 2] = src[old_ix + 2] / 255.0;
        }
    }

    extend_rgb(dst, width, height);
}

static inline double interpolate(
    double tl, double tr,
    double bl, double br, double f, double g)
{
    double l = tl * (1.0 - f) + bl * f;
    double r = tr * (1.0 - f) + br * f;
    return l * (1.0 - g) + r * g;
}

static void linear_upscale(
    unsigned int old_width, unsigned int old_height, double *src,
    unsigned int width, unsigned int height, double *dst)
{
    for (unsigned int i = 0; i < height; i++) {
        for (unsigned int j = 0; j < width; j++) {
            double x = (double)(i * old_height) / height;
            double y = (double)(j * old_width) / width;
            double floor_x = floor(x);
            double floor_y = floor(y);
            int h = (int)floor_x + 1;
            int w = (int)floor_y + 1;
            double f = x - floor_x;
            double g = y - floor_y;

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
}

static void compute_luminance(
    unsigned int width, unsigned int height, double *src, double *dst)
{
    for (unsigned int i = 0; i < height + 2; i++) {
        for (unsigned int j = 0; j < width + 2; j++) {
            int lum_ix = i * (width + 2) + j;
            int ix = 3 * lum_ix;

            dst[lum_ix] =
                (src[ix] * 2 + src[ix + 1] * 3 + src[ix + 2]) / 6;
        }
    }
}

static inline void get_largest(double strength, double *image, double *lum,
    double color[4], int cc, int a, int b, int c)
{
    double new_lum = lum[cc] * (1.0 - strength) +
        ((lum[a] + lum[b] + lum[c]) / 3.0) * strength;
    
    if (new_lum > color[3]) {
        color[0] = image[cc * 3] * (1.0 - strength) +
            ((image[a * 3] + image[b * 3] + image[c * 3]) / 3.0) * strength;
        color[1] = image[cc * 3 + 1] * (1.0 - strength) +
            ((image[a * 3 + 1] + image[b * 3 + 1] + image[c * 3 + 1]) / 3.0) * strength;
        color[2] = image[cc * 3 + 2] * (1.0 - strength) +
            ((image[a * 3 + 2] + image[b * 3 + 2] + image[c * 3 + 2]) / 3.0) * strength;
        color[3] = new_lum;
    }
}

static void preprocess(
    double strength, unsigned int width, unsigned int height,
    double *image, double *lum, double *dst)
{
    unsigned int new_width = width + 2;

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

            double cc = lum[cc_ix];
            double r = lum[r_ix];
            double l = lum[l_ix];
            double t = lum[t_ix];
            double tl = lum[tl_ix];
            double tr = lum[tr_ix];
            double b = lum[b_ix];
            double bl = lum[bl_ix];
            double br = lum[br_ix];

            double color[4];
            color[0] = image[3 * cc_ix];
            color[1] = image[3 * cc_ix + 1];
            color[2] = image[3 * cc_ix + 2];
            color[3] = cc;

            /* pattern 0 and 4 */
            double maxDark = max3v(br, b, bl);
            double minLight = min3v(tl, t, tr);

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
}

static inline double clamp(double x, double lower, double upper)
{
    return x < lower ? lower : (x > upper ? upper : x);
}

static void compute_gradient(unsigned int width, unsigned int height,
    double *src, double *dst)
{
    unsigned int new_width = width + 2;

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

            double r = src[r_ix];
            double l = src[l_ix];
            double t = src[t_ix];
            double tl = src[tl_ix];
            double tr = src[tr_ix];
            double b = src[b_ix];
            double bl = src[bl_ix];
            double br = src[br_ix];

            /* Horizontal Gradient
             * [-1  0  1]
             * [-2  0  2]
             * [-1  0  1]
             */
            double xgrad = tr - tl + r + r - l - l + br - bl;

            /* Vertical Gradient
             * [-1 -2 -1]
             * [ 0  0  0]
             * [ 1  2  1]
             */
            double ygrad = bl - tl + b + b - t - t + br - tr;

            dst[cc_ix] =
                1.0 - clamp(sqrt(xgrad * xgrad + ygrad * ygrad), 0.0, 1.0);
        }
    }

    extend(dst, width, height);
}

static inline void get_average(double strength, double *src, double *dst,
    int cc, int a, int b, int c)
{
    dst[cc * 3] = src[cc * 3] * (1.0 - strength) +
        ((src[a * 3] + src[b * 3] + src[c * 3]) / 3.0) * strength;
    dst[cc * 3 + 1] = src[cc * 3 + 1] * (1.0 - strength) +
        ((src[a * 3 + 1] + src[b * 3 + 1] + src[c * 3 + 1]) / 3.0) * strength;
    dst[cc * 3 + 2] = src[cc * 3 + 2] * (1.0 - strength) +
        ((src[a * 3 + 2] + src[b * 3 + 2] + src[c * 3 + 2]) / 3.0) * strength;
}

static void push(double strength, unsigned int width, unsigned int height,
    double *image, double *gradients, double *dst)
{
    unsigned int new_width = width + 2;

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

            double cc = gradients[cc_ix];
            double r = gradients[r_ix];
            double l = gradients[l_ix];
            double t = gradients[t_ix];
            double tl = gradients[tl_ix];
            double tr = gradients[tr_ix];
            double b = gradients[b_ix];
            double bl = gradients[bl_ix];
            double br = gradients[br_ix];

            /* pattern 0 and 4 */
            double maxDark = max3v(br, b, bl);
            double minLight = min3v(tl, t, tr);

            if (minLight > cc && minLight > maxDark) {
                get_average(strength, image, dst,
                    cc_ix, tl_ix, t_ix, tr_ix);
                continue;
            } else {
                maxDark = max3v(tl, t, tr);
                minLight = min3v(br, b, bl);
                if (minLight > cc && minLight > maxDark) {
                    get_average(strength, image, dst,
                        cc_ix, br_ix, b_ix, bl_ix);
                    continue;
                }
            }

            /* pattern 1 and 5 */
            maxDark = max3v(cc, l, b);
            minLight = min3v(r, t, tr);

            if (minLight > maxDark) {
                get_average(strength, image, dst,
                    cc_ix, r_ix, t_ix, tr_ix);
                continue;
            } else {
                maxDark = max3v(cc, r, t);
                minLight = min3v(bl, l, b);
                if (minLight > maxDark) {
                    get_average(strength, image, dst,
                        cc_ix, bl_ix, l_ix, b_ix);
                    continue;
                }
            }

            /* pattern 2 and 6 */
            maxDark = max3v(l, tl, bl);
            minLight = min3v(r, br, tr);

            if (minLight > cc && minLight > maxDark) {
                get_average(strength, image, dst,
                    cc_ix, r_ix, br_ix, tr_ix);
                continue;
            } else {
                maxDark = max3v(r, br, tr);
                minLight = min3v(l, tl, bl);
                if (minLight > cc && minLight > maxDark) {
                    get_average(strength, image, dst,
                        cc_ix, l_ix, tl_ix, bl_ix);
                    continue;
                }
            }

            /* pattern 3 and 7 */
            maxDark = max3v(cc, l, t);
            minLight = min3v(r, br, b);

            if (minLight > maxDark) {
                get_average(strength, image, dst,
                    cc_ix, r_ix, br_ix, b_ix);
                continue;
            } else {
                maxDark = max3v(cc, r, b);
                minLight = min3v(t, l, tl);
                if (minLight > maxDark) {
                    get_average(strength, image, dst,
                        cc_ix, t_ix, l_ix, tl_ix);
                    continue;
                }
            }

            /* fallback */
            dst[3 * cc_ix] = image[3 * cc_ix];
            dst[3 * cc_ix + 1] = image[3 * cc_ix + 1];
            dst[3 * cc_ix + 2] = image[3 * cc_ix + 2];
        }
    }

    /* this is the final step, no need to extend the border */
}

static inline unsigned char quantize(double x)
{
    int r = x * 255;
    return r < 0 ? 0 : (r > 255 ? 255 : r);
}

static void encode(unsigned int width, unsigned int height, double *src,
    unsigned char *dst)
{
    for (unsigned int i = 0; i < height; i++) {
        for (unsigned int j = 0; j < width; j++) {
            int old_ix = 3 * ((i + 1) * (width + 2) + j + 1);
            int new_ix = 4 * (i * width + j);

            dst[new_ix] = quantize(src[old_ix]);
            dst[new_ix + 1] = quantize(src[old_ix + 1]);
            dst[new_ix + 2] = quantize(src[old_ix + 2]);
            dst[new_ix + 3] = 255;
        }
    }
}

void Anime4kSeq::run()
{
    decode(old_width_, old_height_, image_, original_);
    linear_upscale(old_width_, old_height_, original_,
        width_, height_, enlarge_);
    compute_luminance(width_, height_, enlarge_, lum_);
    preprocess(strength_preprocessing_, width_, height_,
        enlarge_, lum_, preprocessing_);
    compute_luminance(width_, height_, preprocessing_, lum_);
    compute_gradient(width_, height_, lum_, gradients_);
    push(strength_push_, width_, height_, preprocessing_, gradients_, final_);
    encode(width_, height_, final_, result_);
}

Anime4kSeq::~Anime4kSeq()
{
    delete [] original_;
    delete [] enlarge_;
    delete [] lum_;
    delete [] preprocessing_;
    delete [] gradients_;
    delete [] final_;
    delete [] result_;
}
