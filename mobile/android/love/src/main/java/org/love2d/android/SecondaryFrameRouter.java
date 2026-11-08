package org.love2d.android;

import java.nio.ByteBuffer;

/** Selects the new backend only for explicit scaled/filtered submissions. */
final class SecondaryFrameRouter {
    interface Output {
        void background(int color);
        void frame(ByteBuffer data, int w, int h, int scaling, int filter);
        void visible(boolean value);
    }
    interface Factory { Output create(); }
    interface Dispatcher { void post(Runnable action); }
    private final Output legacy;
    private final Factory factory;
    private final Dispatcher dispatcher;
    private Output gpu;
    private boolean requestedGpu, showingGpu, posted, closed;
    private int background, width, height, scaling, filter;
    private ByteBuffer pending;

    SecondaryFrameRouter(Output legacy, Factory factory, Dispatcher dispatcher) {
        this.legacy = legacy; this.factory = factory; this.dispatcher = dispatcher;
    }

    synchronized void background(int color) { background = color; }

    synchronized void legacy(ByteBuffer data, int w, int h, boolean cover) {
        if (closed) return;
        requestedGpu = false; pending = null;
        legacy.background(background);
        legacy.frame(data, w, h, cover ? FramePlacement.COVER : FramePlacement.LEGACY, FrameFilter.NEAREST);
        if (showingGpu || posted) select();
    }

    synchronized void explicit(ByteBuffer data, int w, int h, int mode, int sampling) {
        if (closed) return;
        requestedGpu = true;
        if (gpu != null) {
            gpu.background(background); gpu.frame(data, w, h, mode, sampling);
        } else {
            int size = w * h * 4;
            if (pending == null || pending.capacity() != size) pending = ByteBuffer.allocateDirect(size);
            ByteBuffer copy = data.duplicate(); copy.position(0); copy.limit(size);
            pending.clear(); pending.put(copy); pending.flip();
            width = w; height = h; scaling = mode; filter = sampling;
        }
        if (gpu == null || !showingGpu) select();
    }

    private void select() {
        if (posted) return;
        posted = true;
        dispatcher.post(new Runnable() {
            @Override public void run() {
                synchronized (SecondaryFrameRouter.this) {
                    posted = false;
                    if (closed) return;
                    if (requestedGpu) {
                        if (gpu == null) gpu = factory.create();
                        if (pending != null) {
                            gpu.background(background); gpu.frame(pending, width, height, scaling, filter);
                            pending = null;
                        }
                        legacy.visible(false); gpu.visible(true); showingGpu = true;
                    } else {
                        if (gpu != null) gpu.visible(false);
                        legacy.visible(true); showingGpu = false;
                    }
                }
            }
        });
    }

    synchronized void close() { closed = true; pending = null; }
}
