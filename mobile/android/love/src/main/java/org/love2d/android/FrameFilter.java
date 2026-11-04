package org.love2d.android;

/** Output sampling policy. Geometry and touch coordinates are independent. */
final class FrameFilter {
    static final int AUTO = 0, NEAREST = 1, BILINEAR = 2, SHARP = 3;

    static int resolve(int requested, double sx, double sy) {
        if (requested >= NEAREST && requested <= SHARP) return requested;
        if (sx < 1 || sy < 1) return BILINEAR;
        if (Math.abs(sx - Math.rint(sx)) < 1e-6
                && Math.abs(sy - Math.rint(sy)) < 1e-6) return NEAREST;
        return SHARP;
    }

    static final String VERTEX =
        "attribute vec2 position;attribute vec2 uv;varying highp vec2 tex;"
        + "void main(){tex=uv;gl_Position=vec4(position,0.0,1.0);}";
    private static final String HEADER =
        "#ifdef GL_FRAGMENT_PRECISION_HIGH\nprecision highp float;\n"
        + "#else\nprecision mediump float;\n#endif\n"
        + "varying highp vec2 tex;uniform sampler2D image;";
    static final String PLAIN = HEADER
        + "void main(){gl_FragColor=texture2D(image,tex);}";
    // Sharp-bilinear UV mapping: Themaister / rsn8887, public domain.
    static final String SHARP_FRAGMENT = HEADER
        + "uniform vec2 sourceSize;uniform vec2 prescale;"
        + "void main(){vec2 t=tex*sourceSize;vec2 c=fract(t)-0.5;"
        + "vec2 r=0.5-0.5/prescale;"
        + "vec2 f=(c-clamp(c,-r,r))*prescale+0.5;"
        + "gl_FragColor=texture2D(image,(floor(t)+f)/sourceSize);}";
}
