package org.love2d.android;

/** Physical-pixel placement shared by secondary presentation and its pointer mapping. */
final class FramePlacement {
    static final int LEGACY = 0, FIT = 1, INTEGER = 2, COVER = 3;
    float x, y, width, height;

    void update(int viewWidth, int viewHeight, int sourceWidth, int sourceHeight, int mode) {
        double fit = Math.min((double) viewWidth / sourceWidth, (double) viewHeight / sourceHeight);
        double scale = fit;
        if (mode == COVER) {
            scale = Math.max((double) viewWidth / sourceWidth, (double) viewHeight / sourceHeight);
        } else if (mode == INTEGER && fit >= 1 || mode == LEGACY && fit >= 2) {
            scale = Math.floor(fit + 1e-7);
        }
        double w = sourceWidth * scale, h = sourceHeight * scale;
        x = (float) Math.floor((viewWidth - w) / 2 + 1e-7);
        y = (float) Math.floor((viewHeight - h) / 2 + 1e-7);
        width = (float) w;
        height = (float) h;
    }
}
