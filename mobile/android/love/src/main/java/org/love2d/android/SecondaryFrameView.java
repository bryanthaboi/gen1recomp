package org.love2d.android;

import android.content.Context;
import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.view.MotionEvent;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/** A retained, on-demand GLES output. No filtered frame crosses the JNI bridge. */
class SecondaryFrameView extends GLSurfaceView implements GLSurfaceView.Renderer {
    interface TouchSink { void enqueue(String event); }
    private final TouchSink touchSink;
    private final Object lock = new Object();
    private final FramePlacement placement = new FramePlacement();
    private final android.graphics.RectF dst = new android.graphics.RectF();
    private final FloatBuffer vertices = ByteBuffer.allocateDirect(16 * 4)
        .order(ByteOrder.nativeOrder()).asFloatBuffer();
    private final float[] quad = new float[16];
    private ByteBuffer pixels;
    private int fw, fh, vw, vh, textureWidth, textureHeight;
    private int scaling, filter = FrameFilter.NEAREST, backgroundColor = 0xFF000000;
    private int activePointer = -1, texture, plain, sharp;
    private int plainSampler, sharpSampler, sharpSourceSize, sharpPrescale;
    private boolean uploadPending;

    SecondaryFrameView(Context context, TouchSink sink) {
        super(context);
        touchSink = sink;
        setEGLContextClientVersion(2);
        setEGLConfigChooser(8, 8, 8, 0, 0, 0);
        setPreserveEGLContextOnPause(true);
        setRenderer(this);
        setRenderMode(GLSurfaceView.RENDERMODE_WHEN_DIRTY);
    }

    void updateFrame(ByteBuffer buf, int w, int h) {
        updateFrame(buf, w, h, FramePlacement.LEGACY);
    }
    void updateFrame(ByteBuffer buf, int w, int h, int mode) {
        updateFrame(buf, w, h, mode, FrameFilter.NEAREST);
    }
    void updateFrame(ByteBuffer buf, int w, int h, int mode, int sampling) {
        synchronized (lock) {
            int size = w * h * 4;
            if (pixels == null || fw != w || fh != h) pixels = ByteBuffer.allocateDirect(size);
            fw = w; fh = h; scaling = mode; filter = sampling;
            pixels.clear();
            ByteBuffer frame = buf.duplicate(); frame.position(0); frame.limit(size);
            pixels.put(frame); pixels.flip();
            uploadPending = true;
        }
        requestRender();
    }
    void setFrameBackground(int color) {
        synchronized (lock) { backgroundColor = 0xFF000000 | (color & 0x00FFFFFF); }
        // The caller submits the matching frame immediately after its border.
    }

    private static int compile(int type, String source) {
        int shader = GLES20.glCreateShader(type);
        GLES20.glShaderSource(shader, source); GLES20.glCompileShader(shader);
        int[] status = new int[1]; GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0);
        if (status[0] == 0) throw new IllegalStateException(GLES20.glGetShaderInfoLog(shader));
        return shader;
    }
    private static int program(String fragment) {
        int p = GLES20.glCreateProgram();
        int[] range = new int[2], precision = new int[1];
        GLES20.glGetShaderPrecisionFormat(GLES20.GL_FRAGMENT_SHADER, GLES20.GL_HIGH_FLOAT, range, 0, precision, 0);
        String vertexSource = FrameFilter.VERTEX;
        if (precision[0] == 0) {
            vertexSource = vertexSource.replace("highp", "mediump");
            fragment = fragment.replace("varying highp", "varying mediump");
        }
        int vertex = compile(GLES20.GL_VERTEX_SHADER, vertexSource);
        int pixel = compile(GLES20.GL_FRAGMENT_SHADER, fragment);
        GLES20.glAttachShader(p, vertex); GLES20.glAttachShader(p, pixel);
        GLES20.glBindAttribLocation(p, 0, "position"); GLES20.glBindAttribLocation(p, 1, "uv");
        GLES20.glLinkProgram(p); GLES20.glDeleteShader(vertex); GLES20.glDeleteShader(pixel);
        int[] status = new int[1]; GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, status, 0);
        if (status[0] == 0) throw new IllegalStateException(GLES20.glGetProgramInfoLog(p));
        return p;
    }
    @Override public void onSurfaceCreated(GL10 gl, EGLConfig config) {
        synchronized (lock) {
            plain = program(FrameFilter.PLAIN); sharp = program(FrameFilter.SHARP_FRAGMENT);
            plainSampler = GLES20.glGetUniformLocation(plain, "image");
            sharpSampler = GLES20.glGetUniformLocation(sharp, "image");
            sharpSourceSize = GLES20.glGetUniformLocation(sharp, "sourceSize");
            sharpPrescale = GLES20.glGetUniformLocation(sharp, "prescale");
            int[] ids = new int[1]; GLES20.glGenTextures(1, ids, 0); texture = ids[0];
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture);
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);
            GLES20.glPixelStorei(GLES20.GL_UNPACK_ALIGNMENT, 1);
            GLES20.glDisable(GLES20.GL_DITHER); GLES20.glDisable(GLES20.GL_BLEND);
            textureWidth = textureHeight = 0; uploadPending = true;
        }
    }
    @Override public void onSurfaceChanged(GL10 gl, int w, int h) {
        synchronized (lock) { vw = w; vh = h; GLES20.glViewport(0, 0, w, h); }
    }
    @Override public void onDrawFrame(GL10 gl) {
        synchronized (lock) {
            GLES20.glClearColor(((backgroundColor >> 16) & 255) / 255f,
                ((backgroundColor >> 8) & 255) / 255f, (backgroundColor & 255) / 255f, 1);
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT);
            if (pixels == null || fw <= 0 || fh <= 0 || vw <= 0 || vh <= 0) return;
            placement.update(vw, vh, fw, fh, scaling);
            dst.set(placement.x, placement.y, placement.x + placement.width, placement.y + placement.height);
            int sampling = FrameFilter.resolve(filter, (double) placement.width / fw, (double) placement.height / fh);
            int p = sampling == FrameFilter.SHARP ? sharp : plain;
            GLES20.glUseProgram(p); GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture);
            int interpolation = sampling == FrameFilter.NEAREST ? GLES20.GL_NEAREST : GLES20.GL_LINEAR;
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, interpolation);
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, interpolation);
            if (uploadPending) {
                pixels.position(0);
                if (textureWidth != fw || textureHeight != fh) {
                    GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, fw, fh, 0,
                        GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixels);
                    textureWidth = fw; textureHeight = fh;
                } else GLES20.glTexSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, fw, fh,
                    GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixels);
                uploadPending = false;
            }
            GLES20.glUniform1i(sampling == FrameFilter.SHARP ? sharpSampler : plainSampler, 0);
            if (sampling == FrameFilter.SHARP) {
                GLES20.glUniform2f(sharpSourceSize, fw, fh);
                GLES20.glUniform2f(sharpPrescale,
                    Math.max(1, (float) Math.floor((double) placement.width / fw + 1e-7)),
                    Math.max(1, (float) Math.floor((double) placement.height / fh + 1e-7)));
            }
            float left = 2 * dst.left / vw - 1, right = 2 * dst.right / vw - 1;
            float top = 1 - 2 * dst.top / vh, bottom = 1 - 2 * dst.bottom / vh;
            quad[0]=left;quad[1]=bottom;quad[2]=0;quad[3]=1;
            quad[4]=right;quad[5]=bottom;quad[6]=1;quad[7]=1;
            quad[8]=left;quad[9]=top;quad[10]=0;quad[11]=0;
            quad[12]=right;quad[13]=top;quad[14]=1;quad[15]=0;
            vertices.position(0); vertices.put(quad); vertices.position(0);
            GLES20.glEnableVertexAttribArray(0); GLES20.glEnableVertexAttribArray(1);
            GLES20.glVertexAttribPointer(0, 2, GLES20.GL_FLOAT, false, 16, vertices);
            vertices.position(2); GLES20.glVertexAttribPointer(1, 2, GLES20.GL_FLOAT, false, 16, vertices);
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
        }
    }

    private int logicalX(float x) { return Math.min(fw - 1, Math.max(0, (int) ((x - dst.left) * fw / dst.width()))); }
    private int logicalY(float y) { return Math.min(fh - 1, Math.max(0, (int) ((y - dst.top) * fh / dst.height()))); }
    @Override public boolean onTouchEvent(MotionEvent event) {
        synchronized (lock) {
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_DOWN && fw > 0 && dst.contains(event.getX(), event.getY())) {
                activePointer = event.getPointerId(0);
                touchSink.enqueue("down," + logicalX(event.getX()) + "," + logicalY(event.getY()));
            } else if (action == MotionEvent.ACTION_MOVE && activePointer >= 0) {
                int index = event.findPointerIndex(activePointer);
                if (index >= 0 && fw > 0) {
                    for (int sample = 0; sample < event.getHistorySize(); sample++)
                        touchSink.enqueue("move," + logicalX(event.getHistoricalX(index, sample)) + "," + logicalY(event.getHistoricalY(index, sample)));
                    touchSink.enqueue("move," + logicalX(event.getX(index)) + "," + logicalY(event.getY(index)));
                } else { activePointer = -1; touchSink.enqueue("cancel,0,0"); }
            } else if ((action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_POINTER_UP
                    && event.getPointerId(event.getActionIndex()) == activePointer) && activePointer >= 0) {
                int index = event.findPointerIndex(activePointer);
                if (index >= 0 && fw > 0) touchSink.enqueue("up," + logicalX(event.getX(index)) + "," + logicalY(event.getY(index)));
                activePointer = -1;
            } else if (action == MotionEvent.ACTION_CANCEL) {
                activePointer = -1; touchSink.enqueue("cancel,0,0");
            }
        }
        return true;
    }
}
