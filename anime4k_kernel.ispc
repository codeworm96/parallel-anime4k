inline float min3v(float a, float b, float c) {
    return min(min(a, b), c);
}

inline float max3v(float a, float b, float c) {
    return max(max(a, b), c);
}

export void decode(
    uniform unsigned int width, uniform unsigned int height,
    uniform unsigned int8 src[], uniform float dst[])
{
    for (uniform unsigned int i = 0; i < height; i++) {
        foreach (j = 0 ... width) {
            int old_ix = 4 * (i * width + j);
            int new_ix = 3 * ((i + 1) * (width + 2) + j + 1);
            dst[new_ix] = src[old_ix] / 255.0f;
            dst[new_ix + 1] = src[old_ix + 1] / 255.0f;
            dst[new_ix + 2] = src[old_ix + 2] / 255.0f;
        }
    }
}

inline float interpolate(
    float tl, float tr,
    float bl, float br, float f, float g)
{
    float l = tl * (1 - f) + bl * f;
    float r = tr * (1 - f) + br * f;
    return l * (1 - g) + r * g;
}

export void linear_upscale(
    uniform unsigned int old_width, uniform unsigned int old_height, uniform float src[],
    uniform unsigned int width, uniform unsigned int height, uniform float dst[])
{
    for (uniform unsigned int i = 0; i < height; i++) {
        foreach(j = 0 ... width) {
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
}

export void compute_luminance(
    uniform unsigned int width, uniform unsigned int height,
    uniform float src[], uniform float dst[])
{
    for (uniform unsigned int i = 0; i < height + 2; i++) {
        foreach (j = 0 ... width + 2) {
            int lum_ix = i * (width + 2) + j;
            int ix = 3 * lum_ix;

            dst[lum_ix] =
                (src[ix] * 2 + src[ix + 1] * 3 + src[ix + 2]) / 6;
        }
    }
}

inline void get_largest(float strength, float *image, float *lum,
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

export void thin_lines(
    uniform float strength, uniform unsigned int width, uniform unsigned int height,
    uniform float image[], uniform float lum[], uniform float dst[])
{
    uniform unsigned int new_width = width + 2;

    for (uniform unsigned int i = 1; i <= height; i++) {
        foreach (j = 1 ... width + 1) {
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
}

export void compute_gradient(
    uniform unsigned int width, uniform unsigned int height,
    uniform float src[], uniform float dst[])
{
    uniform unsigned int new_width = width + 2;

    for (uniform unsigned int i = 1; i <= height; i++) {
        foreach (j = 1 ... width + 1) {
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
}

inline void get_average(float strength, float *src, float *dst,
    int cc, int a, int b, int c)
{
    dst[cc * 3] = src[cc * 3] * (1 - strength) +
        ((src[a * 3] + src[b * 3] + src[c * 3]) / 3) * strength;
    dst[cc * 3 + 1] = src[cc * 3 + 1] * (1 - strength) +
        ((src[a * 3 + 1] + src[b * 3 + 1] + src[c * 3 + 1]) / 3) * strength;
    dst[cc * 3 + 2] = src[cc * 3 + 2] * (1 - strength) +
        ((src[a * 3 + 2] + src[b * 3 + 2] + src[c * 3 + 2]) / 3) * strength;
}

export void refine(
    uniform float strength, uniform unsigned int width, uniform unsigned int height,
    uniform float image[], uniform float gradients[], uniform float dst[])
{
    uniform unsigned int new_width = width + 2;

    for (uniform unsigned int i = 1; i <= height; i++) {
        foreach (j = 1 ... width + 1) {
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
}

inline unsigned int8 quantize(float x)
{
    int r = x * 255;
    return r < 0 ? 0 : (r > 255 ? 255 : r);
}

export void encode(
    uniform unsigned int width, uniform unsigned int height,
    uniform float src[], uniform unsigned int8 dst[])
{
    for (uniform unsigned int i = 0; i < height; i++) {
        foreach (j = 0 ... width) {
            int old_ix = 3 * ((i + 1) * (width + 2) + j + 1);
            int new_ix = 4 * (i * width + j);

            dst[new_ix] = quantize(src[old_ix]);
            dst[new_ix + 1] = quantize(src[old_ix + 1]);
            dst[new_ix + 2] = quantize(src[old_ix + 2]);
            dst[new_ix + 3] = 255;
        }
    }
}
