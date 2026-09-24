-- PIXEL FILTER "omniscale": OmniScale.  Driven by src/render/PixelFilter.lua.
--
-- A pattern-matching scaler (the SameBoy family, after HQx): it reads E's
-- 3x3 neighbourhood as an 8-bit "differs from E" pattern, matches it
-- against a table of known shapes -- straight edges, 1:2 and 2:1 slopes,
-- rounded corners -- and draws that shape analytically at the true output
-- resolution, anti-aliased one output pixel wide.  Softer and rounder than
-- xBRZ.  One pass per output pixel.
--
-- Needs GLSL 3 (integer bit ops); on a GLES2-only driver the build fails
-- and the filter reports inactive, like any shader the driver refuses.
-- is_different() also compares alpha, so the transparent UI layer's edges
-- read as edges; on opaque frames it is the reference test.
--
-- OmniScale by Lior Halphon, ported to slang by hunterk (MIT):
--
-- Copyright (c) 2015-2016 Lior Halphon
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local SOURCE = [[
#pragma language glsl3

extern vec2 srcSize;
extern float outScale;

// the width of one output pixel, in source pixels, along the diagonal
#define pixelSize (1.41421356 / outScale)

/* We use the same colorspace as the HQ algorithms. */
vec3 rgb_to_hq_colospace(vec4 rgb)
{
    return vec3( 0.250 * rgb.r + 0.250 * rgb.g + 0.250 * rgb.b,
                 0.250 * rgb.r - 0.000 * rgb.g - 0.250 * rgb.b,
                -0.125 * rgb.r + 0.250 * rgb.g - 0.125 * rgb.b);
}

bool is_different(vec4 a, vec4 b)
{
    vec3 diff = abs(rgb_to_hq_colospace(a) - rgb_to_hq_colospace(b));
    return diff.x > 0.125 || diff.y > 0.027 || diff.z > 0.031 || abs(a.a - b.a) > 0.125;
}

#define P(m, r) ((pattern & (m)) == (r))

vec4 omniscale(Image image, vec2 coord)
{
    // o = offset, the width of a pixel
    vec2 o = 1.0 / srcSize;
    vec2 texCoord = coord;
    // sample around E's centre: at a pixel's very edge a raw coordinate can
    // round into the neighbour while p still says this pixel
    vec2 center = (floor(coord * srcSize) + vec2(0.5)) / srcSize;

    /* We always calculate the top left quarter.  If we need a different quarter, we flip our co-ordinates */

    // p = the position within a pixel [0...1]
    vec2 p = fract(texCoord * srcSize);

    if (p.x > 0.5) {
        o.x = -o.x;
        p.x = 1.0 - p.x;
    }
    if (p.y > 0.5) {
        o.y = -o.y;
        p.y = 1.0 - p.y;
    }

    vec4 w0 = Texel(image, center + vec2( -o.x, -o.y));
    vec4 w1 = Texel(image, center + vec2(  0.0, -o.y));
    vec4 w2 = Texel(image, center + vec2(  o.x, -o.y));
    vec4 w3 = Texel(image, center + vec2( -o.x,  0.0));
    vec4 w4 = Texel(image, center + vec2(  0.0,  0.0));
    vec4 w5 = Texel(image, center + vec2(  o.x,  0.0));
    vec4 w6 = Texel(image, center + vec2( -o.x,  o.y));
    vec4 w7 = Texel(image, center + vec2(  0.0,  o.y));
    vec4 w8 = Texel(image, center + vec2(  o.x,  o.y));

    int pattern = 0;
    if (is_different(w0, w4)) pattern |= 1 << 0;
    if (is_different(w1, w4)) pattern |= 1 << 1;
    if (is_different(w2, w4)) pattern |= 1 << 2;
    if (is_different(w3, w4)) pattern |= 1 << 3;
    if (is_different(w5, w4)) pattern |= 1 << 4;
    if (is_different(w6, w4)) pattern |= 1 << 5;
    if (is_different(w7, w4)) pattern |= 1 << 6;
    if (is_different(w8, w4)) pattern |= 1 << 7;

    if ((P(0xbf,0x37) || P(0xdb,0x13)) && is_different(w1, w5))
        return mix(w4, w3, 0.5 - p.x);
    if ((P(0xdb,0x49) || P(0xef,0x6d)) && is_different(w7, w3))
        return mix(w4, w1, 0.5 - p.y);
    if ((P(0x0b,0x0b) || P(0xfe,0x4a) || P(0xfe,0x1a)) && is_different(w3, w1))
        return w4;
    if ((P(0x6f,0x2a) || P(0x5b,0x0a) || P(0xbf,0x3a) || P(0xdf,0x5a) ||
         P(0x9f,0x8a) || P(0xcf,0x8a) || P(0xef,0x4e) || P(0x3f,0x0e) ||
         P(0xfb,0x5a) || P(0xbb,0x8a) || P(0x7f,0x5a) || P(0xaf,0x8a) ||
         P(0xeb,0x8a)) && is_different(w3, w1))
        return mix(w4, mix(w4, w0, 0.5 - p.x), 0.5 - p.y);
    if (P(0x0b,0x08))
        return mix(mix(w0 * 0.375 + w1 * 0.25 + w4 * 0.375, w4 * 0.5 + w1 * 0.5, p.x * 2.0), w4, p.y * 2.0);
    if (P(0x0b,0x02))
        return mix(mix(w0 * 0.375 + w3 * 0.25 + w4 * 0.375, w4 * 0.5 + w3 * 0.5, p.y * 2.0), w4, p.x * 2.0);
    if (P(0x2f,0x2f)) {
        float dist = length(p - vec2(0.5));
        float pixel_size = pixelSize;
        if (dist < 0.5 - pixel_size / 2.0) {
            return w4;
        }
        vec4 r;
        if (is_different(w0, w1) || is_different(w0, w3)) {
            r = mix(w1, w3, p.y - p.x + 0.5);
        }
        else {
            r = mix(mix(w1 * 0.375 + w0 * 0.25 + w3 * 0.375, w3, p.y * 2.0), w1, p.x * 2.0);
        }

        if (dist > 0.5 + pixel_size / 2.0) {
            return r;
        }
        return mix(w4, r, (dist - 0.5 + pixel_size / 2.0) / pixel_size);
    }
    if (P(0xbf,0x37) || P(0xdb,0x13)) {
        float dist = p.x - 2.0 * p.y;
        float pixel_size = pixelSize * sqrt(5.0);
        if (dist > pixel_size / 2.0) {
            return w1;
        }
        vec4 r = mix(w3, w4, p.x + 0.5);
        if (dist < -pixel_size / 2.0) {
            return r;
        }
        return mix(r, w1, (dist + pixel_size / 2.0) / pixel_size);
    }
    if (P(0xdb,0x49) || P(0xef,0x6d)) {
        float dist = p.y - 2.0 * p.x;
        float pixel_size = pixelSize * sqrt(5.0);
        if (p.y - 2.0 * p.x > pixel_size / 2.0) {
            return w3;
        }
        vec4 r = mix(w1, w4, p.x + 0.5);
        if (dist < -pixel_size / 2.0) {
            return r;
        }
        return mix(r, w3, (dist + pixel_size / 2.0) / pixel_size);
    }
    if (P(0xbf,0x8f) || P(0x7e,0x0e)) {
        float dist = p.x + 2.0 * p.y;
        float pixel_size = pixelSize * sqrt(5.0);

        if (dist > 1.0 + pixel_size / 2.0) {
            return w4;
        }

        vec4 r;
        if (is_different(w0, w1) || is_different(w0, w3)) {
            r = mix(w1, w3, p.y - p.x + 0.5);
        }
        else {
            r = mix(mix(w1 * 0.375 + w0 * 0.25 + w3 * 0.375, w3, p.y * 2.0), w1, p.x * 2.0);
        }

        if (dist < 1.0 - pixel_size / 2.0) {
            return r;
        }

        return mix(r, w4, (dist + pixel_size / 2.0 - 1.0) / pixel_size);

    }

    if (P(0x7e,0x2a) || P(0xef,0xab)) {
        float dist = p.y + 2.0 * p.x;
        float pixel_size = pixelSize * sqrt(5.0);

        if (p.y + 2.0 * p.x > 1.0 + pixel_size / 2.0) {
            return w4;
        }

        vec4 r;

        if (is_different(w0, w1) || is_different(w0, w3)) {
            r = mix(w1, w3, p.y - p.x + 0.5);
        }
        else {
            r = mix(mix(w1 * 0.375 + w0 * 0.25 + w3 * 0.375, w3, p.y * 2.0), w1, p.x * 2.0);
        }

        if (dist < 1.0 - pixel_size / 2.0) {
            return r;
        }

        return mix(r, w4, (dist + pixel_size / 2.0 - 1.0) / pixel_size);
    }

    if (P(0x1b,0x03) || P(0x4f,0x43) || P(0x8b,0x83) || P(0x6b,0x43))
        return mix(w4, w3, 0.5 - p.x);

    if (P(0x4b,0x09) || P(0x8b,0x89) || P(0x1f,0x19) || P(0x3b,0x19))
        return mix(w4, w1, 0.5 - p.y);

    if (P(0xfb,0x6a) || P(0x6f,0x6e) || P(0x3f,0x3e) || P(0xfb,0xfa) ||
        P(0xdf,0xde) || P(0xdf,0x1e))
        return mix(w4, w0, (1.0 - p.x - p.y) / 2.0);

    if (P(0x4f,0x4b) || P(0x9f,0x1b) || P(0x2f,0x0b) ||
        P(0xbe,0x0a) || P(0xee,0x0a) || P(0x7e,0x0a) || P(0xeb,0x4b) ||
        P(0x3b,0x1b)) {
        float dist = p.x + p.y;
        float pixel_size = pixelSize;

        if (dist > 0.5 + pixel_size / 2.0) {
            return w4;
        }

        vec4 r;
        if (is_different(w0, w1) || is_different(w0, w3)) {
            r = mix(w1, w3, p.y - p.x + 0.5);
        }
        else {
            r = mix(mix(w1 * 0.375 + w0 * 0.25 + w3 * 0.375, w3, p.y * 2.0), w1, p.x * 2.0);
        }

        if (dist < 0.5 - pixel_size / 2.0) {
            return r;
        }

        return mix(r, w4, (dist + pixel_size / 2.0 - 0.5) / pixel_size);
    }

    if (P(0x0b,0x01))
        return mix(mix(w4, w3, 0.5 - p.x), mix(w1, (w1 + w3) / 2.0, 0.5 - p.x), 0.5 - p.y);

    if (P(0x0b,0x00))
        return mix(mix(w4, w3, 0.5 - p.x), mix(w1, w0, 0.5 - p.x), 0.5 - p.y);

    float dist = p.x + p.y;
    float pixel_size = pixelSize;

    if (dist > 0.5 + pixel_size / 2.0)
        return w4;

    /* We need more samples to "solve" this diagonal */
    vec4 x0 = Texel(image, center + vec2( -o.x * 2.0, -o.y * 2.0));
    vec4 x1 = Texel(image, center + vec2( -o.x      , -o.y * 2.0));
    vec4 x2 = Texel(image, center + vec2(  0.0      , -o.y * 2.0));
    vec4 x3 = Texel(image, center + vec2(  o.x      , -o.y * 2.0));
    vec4 x4 = Texel(image, center + vec2( -o.x * 2.0, -o.y      ));
    vec4 x5 = Texel(image, center + vec2( -o.x * 2.0,  0.0      ));
    vec4 x6 = Texel(image, center + vec2( -o.x * 2.0,  o.y      ));

    if (is_different(x0, w4)) pattern |= 1 << 8;
    if (is_different(x1, w4)) pattern |= 1 << 9;
    if (is_different(x2, w4)) pattern |= 1 << 10;
    if (is_different(x3, w4)) pattern |= 1 << 11;
    if (is_different(x4, w4)) pattern |= 1 << 12;
    if (is_different(x5, w4)) pattern |= 1 << 13;
    if (is_different(x6, w4)) pattern |= 1 << 14;

    int diagonal_bias = -7;
    while (pattern != 0) {
        diagonal_bias += pattern & 1;
        pattern >>= 1;
    }

    if (diagonal_bias <=  0) {
        vec4 r = mix(w1, w3, p.y - p.x + 0.5);
        if (dist < 0.5 - pixel_size / 2.0) {
            return r;
        }
        return mix(r, w4, (dist + pixel_size / 2.0 - 0.5) / pixel_size);
    }
    
    return w4;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    return omniscale(tex, uv) * color;
}
]]

return {
  id = "omniscale",
  label = "OMNISCALE",
  passes = {
    { scope = "output", source = SOURCE },
  },
}
