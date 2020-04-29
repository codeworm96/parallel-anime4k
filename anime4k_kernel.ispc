inline float min3v(float a, float b, float c) {
    return min(min(a, b), c);
}

inline float max3v(float a, float b, float c) {
    return max(max(a, b), c);
}

export void decode(
    uniform unsigned int width, uniform unsigned int height, uniform int src[],
    uniform float red[], uniform float green[], uniform float blue[])
{
    for (uniform unsigned int i = 0; i < height; i++) {
        foreach (j = 0 ... width) {
            int old_ix = i * width + j;
            int new_ix = (i + 1) * (width + 2) + j + 1;
            int rgba = src[old_ix];
            red[new_ix] = (rgba & 0xFF) / 255.0f;
            green[new_ix] = ((rgba >> 8) & 0xFF) / 255.0f;
            blue[new_ix] = ((rgba >> 16) & 0xFF) / 255.0f;
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
    uniform int old_width, uniform int old_height,
    uniform float src_red[], uniform float src_green[], uniform float src_blue[],
    uniform int width, uniform int height,
    uniform float dst_red[], uniform float dst_green[], uniform float dst_blue[], uniform float lum[])
{
    for (uniform int i = 0; i < height; i++) {
        foreach(j = 0 ... width) {
            float x = (float)(i * old_height) / height;
            float y = (float)((int)j * old_width) / width;
            float floor_x = floor(x);
            float floor_y = floor(y);
            int h = (int)floor_x + 1;
            int w = (int)floor_y + 1;
            float f = x - floor_x;
            float g = y - floor_y;

            int ix = (i + 1) * (width + 2) + j + 1;
            int tl = h * (old_width + 2) + w;
            int tr = tl + 1;
            int bl = tl + old_width + 2;
            int br = bl + 1;

            float red = interpolate(
                src_red[tl], src_red[tr],
                src_red[bl], src_red[br], f, g);

            float green = interpolate(
                src_green[tl], src_green[tr],
                src_green[bl], src_green[br], f, g);

            float blue = interpolate(
                src_blue[tl], src_blue[tr],
                src_blue[bl], src_blue[br], f, g);

            lum[ix] = (red * 2 + green * 3 + blue) / 6;
            dst_red[ix] = red;
            dst_green[ix] = green;
            dst_blue[ix] = blue;
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

inline int get_average(uniform float strength,
    uniform float src_red[], uniform float src_green[], uniform float src_blue[],
    int cc, int a, int b, int c)
{
    float red = src_red[cc] * (1 - strength) +
        ((src_red[a] + src_red[b] + src_red[c]) / 3) * strength;
    float green = src_green[cc] * (1 - strength) +
        ((src_green[a] + src_green[b] + src_green[c]) / 3) * strength;
    float blue = src_blue[cc] * (1 - strength) +
        ((src_blue[a] + src_blue[b] + src_blue[c]) / 3) * strength;

    int rgba = 0xFF000000;
    rgba |= quantize(blue) << 16;
    rgba |= quantize(green) << 8;
    rgba |= quantize(red);

    return rgba;
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
            int res;

            /* pattern 0 */
            float maxDark = max3v(br, b, bl);
            float minLight = min3v(tl, t, tr);
            if (mask && minLight > cc && minLight > maxDark) {
                res = get_average(strength, image_red, image_green, image_blue,
                    cc_ix, tl_ix, t_ix, tr_ix);
                mask = false;
            }

            /* pattern 4 */
            maxDark = max3v(tl, t, tr);
            minLight = min3v(br, b, bl);
            if (mask && minLight > cc && minLight > maxDark) {
                res = get_average(strength, image_red, image_green, image_blue,
                    cc_ix, br_ix, b_ix, bl_ix);
                mask = false;
            }

            /* pattern 1 */
            maxDark = max3v(cc, l, b);
            minLight = min3v(r, t, tr);
            if (mask && minLight > maxDark) {
                res = get_average(strength, image_red, image_green, image_blue,
                    cc_ix, r_ix, t_ix, tr_ix);
                mask = false;
            }

            /* pattern 5 */
            maxDark = max3v(cc, r, t);
            minLight = min3v(bl, l, b);
            if (mask && minLight > maxDark) {
                res = get_average(strength, image_red, image_green, image_blue,
                    cc_ix, bl_ix, l_ix, b_ix);
                mask = false;
            }

            /* pattern 2 */
            maxDark = max3v(l, tl, bl);
            minLight = min3v(r, br, tr);
            if (mask && minLight > cc && minLight > maxDark) {
                res = get_average(strength, image_red, image_green, image_blue,
                    cc_ix, r_ix, br_ix, tr_ix);
                mask = false;
            }

            /* pattern 6 */
            maxDark = max3v(r, br, tr);
            minLight = min3v(l, tl, bl);
            if (mask && minLight > cc && minLight > maxDark) {
                res = get_average(strength, image_red, image_green, image_blue,
                    cc_ix, l_ix, tl_ix, bl_ix);
                mask = false;
            }

            /* pattern 3 */
            maxDark = max3v(cc, l, t);
            minLight = min3v(r, br, b);
            if (mask && minLight > maxDark) {
                res = get_average(strength, image_red, image_green, image_blue,
                    cc_ix, r_ix, br_ix, b_ix);
                mask = false;
            }

            /* pattern 7 */
            maxDark = max3v(cc, r, b);
            minLight = min3v(t, l, tl);
            if (mask && minLight > maxDark) {
                res = get_average(strength, image_red, image_green, image_blue,
                    cc_ix, t_ix, l_ix, tl_ix);
                mask = false;
            }

            /* fallback */
            if (mask) {
                int rgba = 0xFF000000;
                rgba |= quantize(image_blue[cc_ix]) << 16;
                rgba |= quantize(image_green[cc_ix]) << 8;
                rgba |= quantize(image_red[cc_ix]);
                res = rgba;
            }

            int ix = (i - 1) * width + (j - 1);
            dst[ix] = res;
        }
    }
}

export void encode(
    uniform unsigned int width, uniform unsigned int height,
    uniform float red[], uniform float green[], uniform float blue[],
    uniform int dst[])
{
    for (uniform unsigned int i = 0; i < height; i++) {
        foreach (j = 0 ... width) {
            int old_ix = (i + 1) * (width + 2) + j + 1;
            int new_ix = i * width + j;
            int rgba = 0xFF000000;

            rgba |= quantize(blue[old_ix]) << 16;
            rgba |= quantize(green[old_ix]) << 8;
            rgba |= quantize(red[old_ix]);

            dst[new_ix] = rgba;
        }
    }
}
