#include "anime4k_seq.h"

#include <stdlib.h>
#include <math.h>

struct anime4k_seq_ctx
{
    unsigned int old_width;
    unsigned int old_height;
    unsigned char *image;
    unsigned int width;
    unsigned int height;
    double *original;
    double *enlarge;
    double *lum;
    double *preprocessing;
    double *gradients;
    double *final;
    unsigned char *result;
    double strength_preprocessing;
    double strength_push;
};

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

anime4k_seq_ctx_t *anime4k_seq_init(
    unsigned int width, unsigned int height, unsigned char *image,
    unsigned int new_width, unsigned int new_height)
{
    anime4k_seq_ctx_t *res =
        (anime4k_seq_ctx_t *)malloc(sizeof(anime4k_seq_ctx_t));

    res->old_width = width;
    res->old_height = height;
    res->image = image;
    res->width = new_width;
    res->height = new_height;

    /* ghost pixels added to avoid out-of-bounds */
    unsigned int old_pixels = (width + 2) * (height + 2);
    unsigned int pixels = (new_width + 2) * (new_height + 2);

    res->original = (double *)malloc(3 * old_pixels * sizeof(double));
    res->enlarge = (double *)malloc(3 * pixels * sizeof(double));
    res->lum = (double *)malloc(pixels * sizeof(double));
    res->preprocessing = (double *)malloc(3 * pixels * sizeof(double));
    res->gradients = (double *)malloc(pixels * sizeof(double));
    res->final = (double *)malloc(3 * pixels * sizeof(double));

    // result does not need ghost pixels
    res->result = (unsigned char *)malloc(4 * new_width * new_height * sizeof(unsigned char));

    res->strength_preprocessing =
        min((double)res->width / res->old_width / 6.0, 1.0);
    res->strength_push =
        min((double)res->width / res->old_width / 2.0, 1.0);
    return res;
}

static void extend(double *buf, unsigned int width, unsigned int height)
{
    unsigned int new_width = width + 2;

    for (int i = 1; i <= height; i++) {
        /* left */
        int left = i * new_width;
        buf[left] = buf[left + 1];

        /* right */
        int right = i * new_width + width;
        buf[right + 1] = buf[right];
    }

    for (int i = 0; i < new_width; i++) {
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

    for (int i = 1; i <= height; i++) {
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

    for (int i = 0; i < new_width; i++) {
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

static void decode(anime4k_seq_ctx_t *ctx)
{
    for (int i = 0; i < ctx->old_height; i++) {
        for (int j = 0; j < ctx->old_width; j++) {
            int old_ix = 4 * (i * ctx->old_width + j);
            int new_ix = 3 * ((i + 1) * (ctx->old_width + 2) + j + 1);
            ctx->original[new_ix] = ctx->image[old_ix] / 255.0;
            ctx->original[new_ix + 1] = ctx->image[old_ix + 1] / 255.0;
            ctx->original[new_ix + 2] = ctx->image[old_ix + 2] / 255.0;
        }
    }

    extend_rgb(ctx->original, ctx->old_width, ctx->old_height);
}

static inline double interpolate(
    double tl, double tr,
    double bl, double br, double f, double g)
{
    double l = tl * (1.0 - f) + bl * f;
    double r = tr * (1.0 - f) + br * f;
    return l * (1.0 - g) + r * g;
}

static void linear_upscale(anime4k_seq_ctx_t *ctx)
{
    for (int i = 0; i < ctx->height; i++) {
        for (int j = 0; j < ctx->width; j++) {
            double x = (double)(i * ctx->old_height) / ctx->height;
            double y = (double)(j * ctx->old_width) / ctx->width;
            double floor_x = floor(x);
            double floor_y = floor(y);
            int h = (int)floor_x + 1;
            int w = (int)floor_y + 1;
            double f = x - floor_x;
            double g = y - floor_y;

            int ix = 3 * ((i + 1) * (ctx->width + 2) + j + 1);
            int tl = 3 * (h * (ctx->old_width + 2) + w);
            int tr = tl + 3;
            int bl = tl + 3 * (ctx->old_width + 2);
            int br = bl + 3;

            ctx->enlarge[ix] = interpolate(
                ctx->original[tl], ctx->original[tr],
                ctx->original[bl], ctx->original[br], f, g);

            ctx->enlarge[ix + 1] = interpolate(
                ctx->original[tl + 1], ctx->original[tr + 1],
                ctx->original[bl + 1], ctx->original[br + 1], f, g);

            ctx->enlarge[ix + 2] = interpolate(
                ctx->original[tl + 2], ctx->original[tr + 2],
                ctx->original[bl + 2], ctx->original[br + 2], f, g);
        }
    }

    extend_rgb(ctx->enlarge, ctx->width, ctx->height);
}

static void compute_luminance(anime4k_seq_ctx_t *ctx, double *image)
{
    for (int i = 0; i < ctx->height + 2; i++) {
        for (int j = 0; j < ctx->width + 2; j++) {
            int lum_ix = i * (ctx->width + 2) + j;
            int ix = 3 * lum_ix;

            ctx->lum[lum_ix] =
                (image[ix] * 2 + image[ix + 1] * 3 + image[ix + 2]) / 6;
        }
    }
}

static inline void get_largest(anime4k_seq_ctx_t *ctx,
    double color[4], int cc, int a, int b, int c)
{
    double strength = ctx->strength_preprocessing;
    double new_lum = ctx->lum[cc] * (1.0 - strength) +
        ((ctx->lum[a] + ctx->lum[b] + ctx->lum[c]) / 3.0) * strength;
    
    if (new_lum > color[3]) {
        color[0] = ctx->enlarge[cc * 3] * (1.0 - strength) +
            ((ctx->enlarge[a * 3] + ctx->enlarge[b * 3] + ctx->enlarge[c * 3]) / 3.0) * strength;
        color[1] = ctx->enlarge[cc * 3 + 1] * (1.0 - strength) +
            ((ctx->enlarge[a * 3 + 1] + ctx->enlarge[b * 3 + 1] + ctx->enlarge[c * 3 + 1]) / 3.0) * strength;
        color[2] = ctx->enlarge[cc * 3 + 2] * (1.0 - strength) +
            ((ctx->enlarge[a * 3 + 2] + ctx->enlarge[b * 3 + 2] + ctx->enlarge[c * 3 + 2]) / 3.0) * strength;
        color[3] = new_lum;
    }
}

static void preprocess(anime4k_seq_ctx_t *ctx)
{
    unsigned int new_width = ctx->width + 2;

    for (int i = 1; i <= ctx->height; i++) {
        for (int j = 1; j <= ctx->width; j++) {
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

            double cc = ctx->lum[cc_ix];
            double r = ctx->lum[r_ix];
            double l = ctx->lum[l_ix];
            double t = ctx->lum[t_ix];
            double tl = ctx->lum[tl_ix];
            double tr = ctx->lum[tr_ix];
            double b = ctx->lum[b_ix];
            double bl = ctx->lum[bl_ix];
            double br = ctx->lum[br_ix];

            double color[4];
            color[0] = ctx->enlarge[3 * cc_ix];
            color[1] = ctx->enlarge[3 * cc_ix + 1];
            color[2] = ctx->enlarge[3 * cc_ix + 2];
            color[3] = cc;

            /* pattern 0 and 4 */
            double maxDark = max3v(br, b, bl);
            double minLight = min3v(tl, t, tr);

            if (minLight > cc && minLight > maxDark) {
                get_largest(ctx, color, cc_ix, tl_ix, t_ix, tr_ix);
            } else {
                maxDark = max3v(tl, t, tr);
                minLight = min3v(br, b, bl);
                if (minLight > cc && minLight > maxDark) {
                    get_largest(ctx, color, cc_ix, br_ix, b_ix, bl_ix);
                }
            }

            /* pattern 1 and 5 */
            maxDark = max3v(cc, l, b);
            minLight = min3v(r, t, tr);

            if (minLight > maxDark) {
                get_largest(ctx, color, cc_ix, r_ix, t_ix, tr_ix);
            } else {
                maxDark = max3v(cc, r, t);
                minLight = min3v(bl, l, b);
                if (minLight > maxDark) {
                    get_largest(ctx, color, cc_ix, bl_ix, l_ix, b_ix);
                }
            }

            /* pattern 2 and 6 */
            maxDark = max3v(l, tl, bl);
            minLight = min3v(r, br, tr);

            if (minLight > cc && minLight > maxDark) {
                get_largest(ctx, color, cc_ix, r_ix, br_ix, tr_ix);
            } else {
                maxDark = max3v(r, br, tr);
                minLight = min3v(l, tl, bl);
                if (minLight > cc && minLight > maxDark) {
                    get_largest(ctx, color, cc_ix, l_ix, tl_ix, bl_ix);
                }
            }

            /* pattern 3 and 7 */
            maxDark = max3v(cc, l, t);
            minLight = min3v(r, br, b);

            if (minLight > maxDark) {
                get_largest(ctx, color, cc_ix, r_ix, br_ix, b_ix);
            } else {
                maxDark = max3v(cc, r, b);
                minLight = min3v(t, l, tl);
                if (minLight > maxDark) {
                    get_largest(ctx, color, cc_ix, t_ix, l_ix, tl_ix);
                }
            }

            ctx->preprocessing[3 * cc_ix] = color[0];
            ctx->preprocessing[3 * cc_ix + 1] = color[1];
            ctx->preprocessing[3 * cc_ix + 2] = color[2];
        }
    }

    extend_rgb(ctx->preprocessing, ctx->width, ctx->height);
}

static inline double clamp(double x, double lower, double upper)
{
    return x < lower ? lower : (x > upper ? upper : x);
}

static void compute_gradient(anime4k_seq_ctx_t *ctx)
{
    unsigned int new_width = ctx->width + 2;

    for (int i = 1; i <= ctx->height; i++) {
        for (int j = 1; j <= ctx->width; j++) {
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

            double cc = ctx->lum[cc_ix];
            double r = ctx->lum[r_ix];
            double l = ctx->lum[l_ix];
            double t = ctx->lum[t_ix];
            double tl = ctx->lum[tl_ix];
            double tr = ctx->lum[tr_ix];
            double b = ctx->lum[b_ix];
            double bl = ctx->lum[bl_ix];
            double br = ctx->lum[br_ix];

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

            ctx->gradients[cc_ix] =
                1.0 - clamp(sqrt(xgrad * xgrad + ygrad * ygrad), 0.0, 1.0);
        }
    }

    extend(ctx->gradients, ctx->width, ctx->height);
}

static inline void get_average(anime4k_seq_ctx_t *ctx,
    int cc, int a, int b, int c)
{
    double strength = ctx->strength_push;
    double *src = ctx->preprocessing;
    double *dst = ctx->final;

    dst[cc * 3] = src[cc * 3] * (1.0 - strength) +
        ((src[a * 3] + src[b * 3] + src[c * 3]) / 3.0) * strength;
    dst[cc * 3 + 1] = src[cc * 3 + 1] * (1.0 - strength) +
        ((src[a * 3 + 1] + src[b * 3 + 1] + src[c * 3 + 1]) / 3.0) * strength;
    dst[cc * 3 + 2] = src[cc * 3 + 2] * (1.0 - strength) +
        ((src[a * 3 + 2] + src[b * 3 + 2] + src[c * 3 + 2]) / 3.0) * strength;
}

static void push(anime4k_seq_ctx_t *ctx)
{
    unsigned int new_width = ctx->width + 2;

    for (int i = 1; i <= ctx->height; i++) {
        for (int j = 1; j <= ctx->width; j++) {
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

            double cc = ctx->gradients[cc_ix];
            double r = ctx->gradients[r_ix];
            double l = ctx->gradients[l_ix];
            double t = ctx->gradients[t_ix];
            double tl = ctx->gradients[tl_ix];
            double tr = ctx->gradients[tr_ix];
            double b = ctx->gradients[b_ix];
            double bl = ctx->gradients[bl_ix];
            double br = ctx->gradients[br_ix];

            /* pattern 0 and 4 */
            double maxDark = max3v(br, b, bl);
            double minLight = min3v(tl, t, tr);

            if (minLight > cc && minLight > maxDark) {
                get_average(ctx, cc_ix, tl_ix, t_ix, tr_ix);
                continue;
            } else {
                maxDark = max3v(tl, t, tr);
                minLight = min3v(br, b, bl);
                if (minLight > cc && minLight > maxDark) {
                    get_average(ctx, cc_ix, br_ix, b_ix, bl_ix);
                    continue;
                }
            }

            /* pattern 1 and 5 */
            maxDark = max3v(cc, l, b);
            minLight = min3v(r, t, tr);

            if (minLight > maxDark) {
                get_average(ctx, cc_ix, r_ix, t_ix, tr_ix);
                continue;
            } else {
                maxDark = max3v(cc, r, t);
                minLight = min3v(bl, l, b);
                if (minLight > maxDark) {
                    get_average(ctx, cc_ix, bl_ix, l_ix, b_ix);
                    continue;
                }
            }

            /* pattern 2 and 6 */
            maxDark = max3v(l, tl, bl);
            minLight = min3v(r, br, tr);

            if (minLight > cc && minLight > maxDark) {
                get_average(ctx, cc_ix, r_ix, br_ix, tr_ix);
                continue;
            } else {
                maxDark = max3v(r, br, tr);
                minLight = min3v(l, tl, bl);
                if (minLight > cc && minLight > maxDark) {
                    get_average(ctx, cc_ix, l_ix, tl_ix, bl_ix);
                    continue;
                }
            }

            /* pattern 3 and 7 */
            maxDark = max3v(cc, l, t);
            minLight = min3v(r, br, b);

            if (minLight > maxDark) {
                get_average(ctx, cc_ix, r_ix, br_ix, b_ix);
                continue;
            } else {
                maxDark = max3v(cc, r, b);
                minLight = min3v(t, l, tl);
                if (minLight > maxDark) {
                    get_average(ctx, cc_ix, t_ix, l_ix, tl_ix);
                    continue;
                }
            }

            /* fallback */
            ctx->final[3 * cc_ix] = ctx->preprocessing[3 * cc_ix];
            ctx->final[3 * cc_ix + 1] = ctx->preprocessing[3 * cc_ix + 1];
            ctx->final[3 * cc_ix + 2] = ctx->preprocessing[3 * cc_ix + 2];
        }
    }

    /* this is the final step, no need to extend the border */
}

static inline unsigned char quantize(double x)
{
    int r = x * 255;
    return r < 0 ? 0 : (r > 255 ? 255 : r);
}

static void encode(anime4k_seq_ctx_t *ctx)
{
    for (int i = 0; i < ctx->height; i++) {
        for (int j = 0; j < ctx->width; j++) {
            int old_ix = 3 * ((i + 1) * (ctx->width + 2) + j + 1);
            int new_ix = 4 * (i * ctx->width + j);

            ctx->result[new_ix] = quantize(ctx->final[old_ix]);
            ctx->result[new_ix + 1] = quantize(ctx->final[old_ix + 1]);
            ctx->result[new_ix + 2] = quantize(ctx->final[old_ix + 2]);
            ctx->result[new_ix + 3] = 255;
        }
    }
}

void anime4k_seq_run(anime4k_seq_ctx_t *ctx)
{
    decode(ctx);
    linear_upscale(ctx);
    compute_luminance(ctx, ctx->enlarge);
    preprocess(ctx);
    compute_luminance(ctx, ctx->preprocessing);
    compute_gradient(ctx);
    push(ctx);
    encode(ctx);
}

unsigned char *anime4k_seq_get_image(anime4k_seq_ctx_t *ctx)
{
    return ctx->result;
}

void anime4k_seq_free(anime4k_seq_ctx_t *ctx)
{
    free(ctx->original);
    free(ctx->enlarge);
    free(ctx->lum);
    free(ctx->preprocessing);
    free(ctx->gradients);
    free(ctx->final);
    free(ctx->result);
    free(ctx);
}
