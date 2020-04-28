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

inline float<4> get_largest(uniform float strength,
    float<4> color, float<4> cc, float<4> a, float<4> b, float<4> c)
{
    float new_lum = cc.a * (1 - strength) + ((a.a + b.a + c.a) / 3) * strength;
    float<4> res;
    
    if (new_lum > color.a) {
        res.r = cc.r * (1 - strength) + ((a.r + b.r + c.r) / 3) * strength;
        res.g = cc.g * (1 - strength) + ((a.g + b.g + c.g) / 3) * strength;
        res.b = cc.b * (1 - strength) + ((a.b + b.b + c.b) / 3) * strength;
        res.a = new_lum;
    } else {
        res = color;
    }

    return res;
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

            float<4> cc = { image_red[cc_ix], image_green[cc_ix],
                image_blue[cc_ix], src_lum[cc_ix] };
            float<4> r = { image_red[r_ix], image_green[r_ix],
                image_blue[r_ix], src_lum[r_ix] };
            float<4> l = { image_red[l_ix], image_green[l_ix],
                image_blue[l_ix], src_lum[l_ix] };
            float<4> t = { image_red[t_ix], image_green[t_ix],
                image_blue[t_ix], src_lum[t_ix] };
            float<4> tl = { image_red[tl_ix], image_green[tl_ix],
                image_blue[tl_ix], src_lum[tl_ix] };
            float<4> tr = { image_red[tr_ix], image_green[tr_ix],
                image_blue[tr_ix], src_lum[tr_ix] };
            float<4> b = { image_red[b_ix], image_green[b_ix],
                image_blue[b_ix], src_lum[b_ix] };
            float<4> bl = { image_red[bl_ix], image_green[bl_ix],
                image_blue[bl_ix], src_lum[bl_ix] };
            float<4> br = { image_red[br_ix], image_green[br_ix],
                image_blue[br_ix], src_lum[br_ix] };

            float<4> color = cc;

            /* pattern 0 */
            float maxDark = max3v(br.a, b.a, bl.a);
            float minLight = min3v(tl.a, t.a, tr.a);
            if (minLight > cc.a && minLight > maxDark) {
                color = get_largest(strength, color, cc, tl, t, tr);
            }

            /* pattern 4 */
            maxDark = max3v(tl.a, t.a, tr.a);
            minLight = min3v(br.a, b.a, bl.a);
            if (minLight > cc.a && minLight > maxDark) {
                color = get_largest(strength, color, cc, br, b, bl);
            }

            /* pattern 1 */
            maxDark = max3v(cc.a, l.a, b.a);
            minLight = min3v(r.a, t.a, tr.a);
            if (minLight > maxDark) {
                color = get_largest(strength, color, cc, r, t, tr);
            }

            /* pattern 5 */
            maxDark = max3v(cc.a, r.a, t.a);
            minLight = min3v(bl.a, l.a, b.a);
            if (minLight > maxDark) {
                color = get_largest(strength, color, cc, bl, l, b);
            }

            /* pattern 2 */
            maxDark = max3v(l.a, tl.a, bl.a);
            minLight = min3v(r.a, br.a, tr.a);
            if (minLight > cc.a && minLight > maxDark) {
                color = get_largest(strength, color, cc, r, br, tr);
            }

            /* pattern 6 */
            maxDark = max3v(r.a, br.a, tr.a);
            minLight = min3v(l.a, tl.a, bl.a);
            if (minLight > cc.a && minLight > maxDark) {
                color = get_largest(strength, color, cc, l, tl, bl);
            }

            /* pattern 3 */
            maxDark = max3v(cc.a, l.a, t.a);
            minLight = min3v(r.a, br.a, b.a);
            if (minLight > maxDark) {
                color = get_largest(strength, color, cc, r, br, b);
            }

            /* pattern 7 */
            maxDark = max3v(cc.a, r.a, b.a);
            minLight = min3v(t.a, l.a, tl.a);
            if (minLight > maxDark) {
                color = get_largest(strength, color, cc, t, l, tl);
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

inline int get_average(uniform float strength,
    float<4> cc, float<4> a, float<4> b, float<4> c)
{
    float red = cc.r * (1 - strength) + ((a.r + b.r + c.r) / 3) * strength;
    float green = cc.g * (1 - strength) + ((a.g + b.g + c.g) / 3) * strength;
    float blue = cc.b * (1 - strength) + ((a.b + b.b + c.b) / 3) * strength;

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

            float<4> cc = { image_red[cc_ix], image_green[cc_ix],
                image_blue[cc_ix], gradients[cc_ix] };
            float<4> r = { image_red[r_ix], image_green[r_ix],
                image_blue[r_ix], gradients[r_ix] };
            float<4> l = { image_red[l_ix], image_green[l_ix],
                image_blue[l_ix], gradients[l_ix] };
            float<4> t = { image_red[t_ix], image_green[t_ix],
                image_blue[t_ix], gradients[t_ix] };
            float<4> tl = { image_red[tl_ix], image_green[tl_ix],
                image_blue[tl_ix], gradients[tl_ix] };
            float<4> tr = { image_red[tr_ix], image_green[tr_ix],
                image_blue[tr_ix], gradients[tr_ix] };
            float<4> b = { image_red[b_ix], image_green[b_ix],
                image_blue[b_ix], gradients[b_ix] };
            float<4> bl = { image_red[bl_ix], image_green[bl_ix],
                image_blue[bl_ix], gradients[bl_ix] };
            float<4> br = { image_red[br_ix], image_green[br_ix],
                image_blue[br_ix], gradients[br_ix] };

            bool mask = true;
            int res;

            /* pattern 0 */
            float maxDark = max3v(br.a, b.a, bl.a);
            float minLight = min3v(tl.a, t.a, tr.a);
            if (mask && minLight > cc.a && minLight > maxDark) {
                res = get_average(strength, cc, tl, t, tr);
                mask = false;
            }

            /* pattern 4 */
            maxDark = max3v(tl.a, t.a, tr.a);
            minLight = min3v(br.a, b.a, bl.a);
            if (mask && minLight > cc.a && minLight > maxDark) {
                res = get_average(strength, cc, br, b, bl);
                mask = false;
            }

            /* pattern 1 */
            maxDark = max3v(cc.a, l.a, b.a);
            minLight = min3v(r.a, t.a, tr.a);
            if (mask && minLight > maxDark) {
                res = get_average(strength, cc, r, t, tr);
                mask = false;
            }

            /* pattern 5 */
            maxDark = max3v(cc.a, r.a, t.a);
            minLight = min3v(bl.a, l.a, b.a);
            if (mask && minLight > maxDark) {
                res = get_average(strength, cc, bl, l, b);
                mask = false;
            }

            /* pattern 2 */
            maxDark = max3v(l.a, tl.a, bl.a);
            minLight = min3v(r.a, br.a, tr.a);
            if (mask && minLight > cc.a && minLight > maxDark) {
                res = get_average(strength, cc, r, br, tr);
                mask = false;
            }

            /* pattern 6 */
            maxDark = max3v(r.a, br.a, tr.a);
            minLight = min3v(l.a, tl.a, bl.a);
            if (mask && minLight > cc.a && minLight > maxDark) {
                res = get_average(strength, cc, l, tl, bl);
                mask = false;
            }

            /* pattern 3 */
            maxDark = max3v(cc.a, l.a, t.a);
            minLight = min3v(r.a, br.a, b.a);
            if (mask && minLight > maxDark) {
                res = get_average(strength, cc, r, br, b);
                mask = false;
            }

            /* pattern 7 */
            maxDark = max3v(cc.a, r.a, b.a);
            minLight = min3v(t.a, l.a, tl.a);
            if (mask && minLight > maxDark) {
                res = get_average(strength, cc, t, l, tl);
                mask = false;
            }

            /* fallback */
            if (mask) {
                int rgba = 0xFF000000;
                rgba |= quantize(cc.b) << 16;
                rgba |= quantize(cc.g) << 8;
                rgba |= quantize(cc.r);
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
