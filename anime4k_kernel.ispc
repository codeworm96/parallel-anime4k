inline float min3v(float a, float b, float c) {
    return min(min(a, b), c);
}

inline float max3v(float a, float b, float c) {
    return max(max(a, b), c);
}

inline float<3> decode(uniform int src[], int ix)
{
    float<3> res;
    int rgba = src[ix];
    res.r = (rgba & 0xFF) / 255.0f;
    res.g = ((rgba >> 8) & 0xFF) / 255.0f;
    res.b = ((rgba >> 16) & 0xFF) / 255.0f;
    return res;
}

inline float<3> interpolate(
    float<3> tl, float<3> tr,
    float<3> bl, float<3> br, float f, float g)
{
    float<3> l = tl * (1 - f) + bl * f;
    float<3> r = tr * (1 - f) + br * f;
    return l * (1 - g) + r * g;
}

export void linear_upscale(
    uniform int old_width, uniform int old_height, uniform int src[],
    uniform int width, uniform int height,
    uniform float dst_red[], uniform float dst_green[], uniform float dst_blue[], uniform float lum[])
{
    uniform unsigned int new_width = width + 2;
    uniform int maxh = old_height - 1;
    uniform int maxw = old_width - 1;

    for (uniform int i = 0; i < height; i++) {
        foreach(j = 0 ... width) {
            float x = (float)(i * old_height) / height;
            float y = (float)((int)j * old_width) / width;
            float floor_x = floor(x);
            float floor_y = floor(y);
            int ht = (int)floor_x;
            int hb = min(ht + 1, maxh);
            int wl = (int)floor_y;
            int wr = min(wl + 1, maxw);
            float f = x - floor_x;
            float g = y - floor_y;

            int ix = (i + 1) * new_width + j + 1;
            int tl = ht * old_width + wl;
            int tr = ht * old_width + wr;
            int bl = hb * old_width + wl;
            int br = hb * old_width + wr;

            float<3> color = interpolate(
                decode(src, tl), decode(src, tr),
                decode(src, bl), decode(src, br), f, g);

            lum[ix] = (color.r * 2 + color.g * 3 + color.b) / 6;
            dst_red[ix] = color.r;
            dst_green[ix] = color.g;
            dst_blue[ix] = color.b;
        }
    }
}

inline void get_largest(uniform float strength,
    bool &mark, float &old_lum, int &ix1, int &ix2, int &ix3,
    float cc, float a, float b, float c, int a_ix, int b_ix, int c_ix)
{
    float new_lum = cc * (1 - strength) +
        ((a + b + c) / 3) * strength;

    if (new_lum > old_lum) {
        old_lum = new_lum;
        mark = true;
        ix1 = a_ix;
        ix2 = b_ix;
        ix3 = c_ix;
    }
}

export void thin_lines(
    uniform float strength, uniform unsigned int width, uniform unsigned int height,
    uniform float image_red[], uniform float image_green[], uniform float image_blue[],
    uniform float src_lum[],
    uniform float dst_red[], uniform float dst_green[], uniform float dst_blue[],
    uniform float dst_lum[])
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

            float cc = src_lum[cc_ix];
            float r = src_lum[r_ix];
            float l = src_lum[l_ix];
            float t = src_lum[t_ix];
            float tl = src_lum[tl_ix];
            float tr = src_lum[tr_ix];
            float b = src_lum[b_ix];
            float bl = src_lum[bl_ix];
            float br = src_lum[br_ix];

            float lum = cc;
            int ix1;
            int ix2;
            int ix3;

            bool mark = false;

            /* pattern 0 */
            float maxDark = max3v(br, b, bl);
            float minLight = min3v(tl, t, tr);
            if (minLight > cc && minLight > maxDark) {
                get_largest(strength,
                    mark, lum, ix1, ix2, ix3,
                    cc, tl, t, tr, tl_ix, t_ix, tr_ix);
            }

            /* pattern 4 */
            maxDark = max3v(tl, t, tr);
            minLight = min3v(br, b, bl);
            if (minLight > cc && minLight > maxDark) {
                get_largest(strength,
                    mark, lum, ix1, ix2, ix3,
                    cc, br, b, bl, br_ix, b_ix, bl_ix);
            }

            /* pattern 1 */
            maxDark = max3v(cc, l, b);
            minLight = min3v(r, t, tr);
            if (minLight > maxDark) {
                get_largest(strength,
                    mark, lum, ix1, ix2, ix3,
                    cc, r, t, tr, r_ix, t_ix, tr_ix);
            }

            /* pattern 5 */
            maxDark = max3v(cc, r, t);
            minLight = min3v(bl, l, b);
            if (minLight > maxDark) {
                get_largest(strength,
                    mark, lum, ix1, ix2, ix3,
                    cc, bl, l, b, bl_ix, l_ix, b_ix);
            }

            /* pattern 2 */
            maxDark = max3v(l, tl, bl);
            minLight = min3v(r, br, tr);
            if (minLight > cc && minLight > maxDark) {
                get_largest(strength,
                    mark, lum, ix1, ix2, ix3,
                    cc, r, br, tr, r_ix, br_ix, tr_ix);
            }

            /* pattern 6 */
            maxDark = max3v(r, br, tr);
            minLight = min3v(l, tl, bl);
            if (minLight > cc && minLight > maxDark) {
                get_largest(strength,
                    mark, lum, ix1, ix2, ix3,
                    cc, l, tl, bl, l_ix, tl_ix, bl_ix);
            }

            /* pattern 3 */
            maxDark = max3v(cc, l, t);
            minLight = min3v(r, br, b);
            if (minLight > maxDark) {
                get_largest(strength,
                    mark, lum, ix1, ix2, ix3,
                    cc, r, br, b, r_ix, br_ix, b_ix);
            }

            /* pattern 7 */
            maxDark = max3v(cc, r, b);
            minLight = min3v(t, l, tl);
            if (minLight > maxDark) {
                get_largest(strength,
                    mark, lum, ix1, ix2, ix3,
                    cc, t, l, tl, t_ix, l_ix, tl_ix);
            }

            float<3> color = {
                image_red[cc_ix],
                image_green[cc_ix],
                image_blue[cc_ix]
            };

            if (mark) {
                color.r = color.r * (1 - strength) +
                    ((image_red[ix1] + image_red[ix2] + image_red[ix3]) / 3) * strength;
                color.g = color.g * (1 - strength) +
                    ((image_green[ix1] + image_green[ix2] + image_green[ix3]) / 3) * strength;
                color.b = color.b * (1 - strength) +
                    ((image_blue[ix1] + image_blue[ix2] + image_blue[ix3]) / 3) * strength;
            }

            dst_lum[cc_ix] = (color.r * 2 + color.g * 3 + color.b) / 6;
            dst_red[cc_ix] = color.r;
            dst_green[cc_ix] = color.g;
            dst_blue[cc_ix] = color.b;
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

inline int quantize(float x)
{
    int r = x * 255;
    return clamp(r, 0, 255);
}

export void refine(
    uniform float strength, uniform unsigned int width, uniform unsigned int height,
    uniform float image_red[], uniform float image_green[], uniform float image_blue[],
    uniform float gradients[], uniform int dst[])
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

            bool mask = true;
            int ix1;
            int ix2;
            int ix3;

            /* pattern 0 */
            float maxDark = max3v(br, b, bl);
            float minLight = min3v(tl, t, tr);
            if (mask && minLight > cc && minLight > maxDark) {
                ix1 = tl_ix;
                ix2 = t_ix;
                ix3 = tr_ix;
                mask = false;
            }

            /* pattern 4 */
            maxDark = max3v(tl, t, tr);
            minLight = min3v(br, b, bl);
            if (mask && minLight > cc && minLight > maxDark) {
                ix1 = br_ix;
                ix2 = b_ix;
                ix3 = bl_ix;
                mask = false;
            }

            /* pattern 1 */
            maxDark = max3v(cc, l, b);
            minLight = min3v(r, t, tr);
            if (mask && minLight > maxDark) {
                ix1 = r_ix;
                ix2 = t_ix;
                ix3 = tr_ix;
                mask = false;
            }

            /* pattern 5 */
            maxDark = max3v(cc, r, t);
            minLight = min3v(bl, l, b);
            if (mask && minLight > maxDark) {
                ix1 = bl_ix;
                ix2 = l_ix;
                ix3 = b_ix;
                mask = false;
            }

            /* pattern 2 */
            maxDark = max3v(l, tl, bl);
            minLight = min3v(r, br, tr);
            if (mask && minLight > cc && minLight > maxDark) {
                ix1 = r_ix;
                ix2 = br_ix;
                ix3 = tr_ix;
                mask = false;
            }

            /* pattern 6 */
            maxDark = max3v(r, br, tr);
            minLight = min3v(l, tl, bl);
            if (mask && minLight > cc && minLight > maxDark) {
                ix1 = l_ix;
                ix2 = tl_ix;
                ix3 = bl_ix;
                mask = false;
            }

            /* pattern 3 */
            maxDark = max3v(cc, l, t);
            minLight = min3v(r, br, b);
            if (mask && minLight > maxDark) {
                ix1 = r_ix;
                ix2 = br_ix;
                ix3 = b_ix;
                mask = false;
            }

            /* pattern 7 */
            maxDark = max3v(cc, r, b);
            minLight = min3v(t, l, tl);
            if (mask && minLight > maxDark) {
                ix1 = t_ix;
                ix2 = l_ix;
                ix3 = tl_ix;
                mask = false;
            }

            float<3> color = {
                image_red[cc_ix],
                image_green[cc_ix],
                image_blue[cc_ix]
            };

            if (!mask) {
                color.r = color.r * (1 - strength) +
                    ((image_red[ix1] + image_red[ix2] + image_red[ix3]) / 3) * strength;
                color.g = color.g * (1 - strength) +
                    ((image_green[ix1] + image_green[ix2] + image_green[ix3]) / 3) * strength;
                color.b = color.b * (1 - strength) +
                    ((image_blue[ix1] + image_blue[ix2] + image_blue[ix3]) / 3) * strength;
            }

            int ix = (i - 1) * width + (j - 1);
            int rgba = 0xFF000000;
            rgba |= quantize(color.b) << 16;
            rgba |= quantize(color.g) << 8;
            rgba |= quantize(color.r);
            dst[ix] = rgba;
        }
    }
}
