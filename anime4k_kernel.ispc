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
    uniform float red[], uniform float green[], uniform float blue[],
    uniform float lum[],
    float color[4], int cc, int a, int b, int c)
{
    float new_lum = lum[cc] * (1 - strength) +
        ((lum[a] + lum[b] + lum[c]) / 3) * strength;
    
    if (new_lum > color[3]) {
        color[0] = red[cc] * (1 - strength) +
            ((red[a] + red[b] + red[c]) / 3) * strength;
        color[1] = green[cc] * (1 - strength) +
            ((green[a] + green[b] + green[c]) / 3) * strength;
        color[2] = blue[cc] * (1 - strength) +
            ((blue[a] + blue[b] + blue[c]) / 3) * strength;
        color[3] = new_lum;
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

            float color[4];
            color[0] = image_red[cc_ix];
            color[1] = image_green[cc_ix];
            color[2] = image_blue[cc_ix];
            color[3] = cc;

            /* pattern 0 */
            float maxDark = max3v(br, b, bl);
            float minLight = min3v(tl, t, tr);
            if (minLight > cc && minLight > maxDark) {
                get_largest(strength, image_red, image_green, image_blue,
                    src_lum, color, cc_ix, tl_ix, t_ix, tr_ix);
            }

            /* pattern 4 */
            maxDark = max3v(tl, t, tr);
            minLight = min3v(br, b, bl);
            if (minLight > cc && minLight > maxDark) {
                get_largest(strength, image_red, image_green, image_blue,
                    src_lum, color, cc_ix, br_ix, b_ix, bl_ix);
            }

            /* pattern 1 */
            maxDark = max3v(cc, l, b);
            minLight = min3v(r, t, tr);
            if (minLight > maxDark) {
                get_largest(strength, image_red, image_green, image_blue,
                    src_lum, color, cc_ix, r_ix, t_ix, tr_ix);
            }

            /* pattern 5 */
            maxDark = max3v(cc, r, t);
            minLight = min3v(bl, l, b);
            if (minLight > maxDark) {
                get_largest(strength, image_red, image_green, image_blue,
                    src_lum, color, cc_ix, bl_ix, l_ix, b_ix);
            }

            /* pattern 2 */
            maxDark = max3v(l, tl, bl);
            minLight = min3v(r, br, tr);
            if (minLight > cc && minLight > maxDark) {
                get_largest(strength, image_red, image_green, image_blue,
                    src_lum, color, cc_ix, r_ix, br_ix, tr_ix);
            }

            /* pattern 6 */
            maxDark = max3v(r, br, tr);
            minLight = min3v(l, tl, bl);
            if (minLight > cc && minLight > maxDark) {
                get_largest(strength, image_red, image_green, image_blue,
                    src_lum, color, cc_ix, l_ix, tl_ix, bl_ix);
            }

            /* pattern 3 */
            maxDark = max3v(cc, l, t);
            minLight = min3v(r, br, b);
            if (minLight > maxDark) {
                get_largest(strength, image_red, image_green, image_blue,
                    src_lum, color, cc_ix, r_ix, br_ix, b_ix);
            }

            /* pattern 7 */
            maxDark = max3v(cc, r, b);
            minLight = min3v(t, l, tl);
            if (minLight > maxDark) {
                get_largest(strength, image_red, image_green, image_blue,
                    src_lum, color, cc_ix, t_ix, l_ix, tl_ix);
            }

            dst_lum[cc_ix] = (color[0] * 2 + color[1] * 3 + color[2]) / 6;
            dst_red[cc_ix] = color[0];
            dst_green[cc_ix] = color[1];
            dst_blue[cc_ix] = color[2];
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

inline void get_average(
    uniform float src_red[], uniform float src_green[], uniform float src_blue[],
    float<3> &color1, float<3> &color2, float<3> &color3,
    int a, int b, int c)
{
    color1.r = src_red[a];
    color1.g = src_green[a];
    color1.b = src_blue[a];
    color2.r = src_red[b];
    color2.g = src_green[b];
    color2.b = src_blue[b];
    color3.r = src_red[c];
    color3.g = src_green[c];
    color3.b = src_blue[c];
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
            float<3> color = {
                image_red[cc_ix],
                image_green[cc_ix],
                image_blue[cc_ix]
            };
            float<3> color1;
            float<3> color2;
            float<3> color3;

            /* pattern 0 */
            float maxDark = max3v(br, b, bl);
            float minLight = min3v(tl, t, tr);
            if (mask && minLight > cc && minLight > maxDark) {
                get_average(image_red, image_green, image_blue,
                    color1, color2, color3,
                    tl_ix, t_ix, tr_ix);
                mask = false;
            }

            /* pattern 4 */
            maxDark = max3v(tl, t, tr);
            minLight = min3v(br, b, bl);
            if (mask && minLight > cc && minLight > maxDark) {
                get_average(image_red, image_green, image_blue,
                    color1, color2, color3,
                    br_ix, b_ix, bl_ix);
                mask = false;
            }

            /* pattern 1 */
            maxDark = max3v(cc, l, b);
            minLight = min3v(r, t, tr);
            if (mask && minLight > maxDark) {
                get_average(image_red, image_green, image_blue,
                    color1, color2, color3,
                    r_ix, t_ix, tr_ix);
                mask = false;
            }

            /* pattern 5 */
            maxDark = max3v(cc, r, t);
            minLight = min3v(bl, l, b);
            if (mask && minLight > maxDark) {
                get_average(image_red, image_green, image_blue,
                    color1, color2, color3,
                    bl_ix, l_ix, b_ix);
                mask = false;
            }

            /* pattern 2 */
            maxDark = max3v(l, tl, bl);
            minLight = min3v(r, br, tr);
            if (mask && minLight > cc && minLight > maxDark) {
                get_average(image_red, image_green, image_blue,
                    color1, color2, color3,
                    r_ix, br_ix, tr_ix);
                mask = false;
            }

            /* pattern 6 */
            maxDark = max3v(r, br, tr);
            minLight = min3v(l, tl, bl);
            if (mask && minLight > cc && minLight > maxDark) {
                get_average(image_red, image_green, image_blue,
                    color1, color2, color3,
                    l_ix, tl_ix, bl_ix);
                mask = false;
            }

            /* pattern 3 */
            maxDark = max3v(cc, l, t);
            minLight = min3v(r, br, b);
            if (mask && minLight > maxDark) {
                get_average(image_red, image_green, image_blue,
                    color1, color2, color3,
                    r_ix, br_ix, b_ix);
                mask = false;
            }

            /* pattern 7 */
            maxDark = max3v(cc, r, b);
            minLight = min3v(t, l, tl);
            if (mask && minLight > maxDark) {
                get_average(image_red, image_green, image_blue,
                    color1, color2, color3,
                    t_ix, l_ix, tl_ix);
                mask = false;
            }

            if (!mask) {
                color.r = color.r * (1 - strength) +
                    ((color1.r + color2.r + color3.r) / 3) * strength;
                color.g = color.g * (1 - strength) +
                    ((color1.g + color2.g + color3.g) / 3) * strength;
                color.b = color.b * (1 - strength) +
                    ((color1.b + color2.b + color3.b) / 3) * strength;
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
