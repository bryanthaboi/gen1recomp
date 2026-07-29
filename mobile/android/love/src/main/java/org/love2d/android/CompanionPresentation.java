package org.love2d.android;

import android.app.Presentation;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Display;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.Locale;

/**
 * OLED-black, read-only game companion for a physically smaller Android
 * display.  This window can neither take focus nor receive touch, which is
 * essential on a handheld: the controls always belong to the game panel.
 */
final class CompanionPresentation extends Presentation {
    private static final String SAVE_IDENTITY = "pokemon-love2d";
    private static final String SNAPSHOT = "companion-state.json";

    private final Handler handler = new Handler(Looper.getMainLooper());
    private CompanionView companionView;
    private File snapshotFile;
    private long lastModified = -1;

    private final Runnable poller = new Runnable() {
        @Override
        public void run() {
            loadSnapshot();
            handler.postDelayed(this, 250);
        }
    };

    CompanionPresentation(Context context, Display display) {
        super(context, display);
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        requestWindowFeature(Window.FEATURE_NO_TITLE);
        Window window = getWindow();
        window.setFlags(
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
        window.setNavigationBarColor(Color.BLACK);
        window.setStatusBarColor(Color.BLACK);
        immersive();

        companionView = new CompanionView(getContext());
        setContentView(companionView);
        File external = getContext().getExternalFilesDir(null);
        snapshotFile = external == null ? null
            : new File(new File(external, "save/" + SAVE_IDENTITY), SNAPSHOT);
        handler.post(poller);
    }

    private void immersive() {
        getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        immersive();
    }

    @Override
    protected void onStop() {
        handler.removeCallbacks(poller);
        super.onStop();
    }

    private void loadSnapshot() {
        if (snapshotFile == null || !snapshotFile.isFile()) return;
        long modified = snapshotFile.lastModified();
        if (modified == lastModified) return;
        try {
            String json = readAll(snapshotFile);
            JSONObject parsed = new JSONObject(json);
            lastModified = modified;
            companionView.setSnapshot(parsed);
        } catch (Exception ignored) {
            // A reader can catch the file between LOVE's truncate and write.
            // Retain the last complete frame and try again on the next poll.
        }
    }

    private static String readAll(File file) throws IOException {
        try (BufferedInputStream input =
                 new BufferedInputStream(new FileInputStream(file));
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) >= 0) output.write(buffer, 0, count);
            return output.toString("UTF-8");
        }
    }

    private static final class CompanionView extends View {
        private static final float DESIGN_W = 1240f;
        private static final float DESIGN_H = 1080f;
        private static final int TEXT = Color.rgb(244, 244, 247);
        private static final int MUTED = Color.rgb(151, 154, 164);
        private static final int CARD = Color.rgb(17, 18, 22);
        private static final int CARD_STROKE = Color.rgb(37, 39, 46);
        private static final int RED = Color.rgb(239, 73, 77);
        private static final int BLUE = Color.rgb(76, 139, 245);
        private static final int GREEN = Color.rgb(73, 201, 126);
        private static final int YELLOW = Color.rgb(240, 184, 67);

        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Typeface regular = Typeface.create("sans-serif", Typeface.NORMAL);
        private final Typeface medium = Typeface.create("sans-serif-medium", Typeface.NORMAL);
        private JSONObject snapshot;

        CompanionView(Context context) {
            super(context);
            setBackgroundColor(Color.BLACK);
        }

        void setSnapshot(JSONObject value) {
            snapshot = value;
            postInvalidate();
        }

        private void text(Canvas canvas, String value, float x, float y,
                          float size, int color, boolean bold) {
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(color);
            paint.setTextSize(size);
            paint.setTypeface(bold ? medium : regular);
            canvas.drawText(value == null ? "" : value, x, y, paint);
        }

        private void rounded(Canvas canvas, float l, float t, float r, float b,
                             float radius, int fill, int stroke) {
            RectF rect = new RectF(l, t, r, b);
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(fill);
            canvas.drawRoundRect(rect, radius, radius, paint);
            if (stroke != Color.TRANSPARENT) {
                paint.setStyle(Paint.Style.STROKE);
                paint.setStrokeWidth(2);
                paint.setColor(stroke);
                canvas.drawRoundRect(rect, radius, radius, paint);
            }
        }

        private void bar(Canvas canvas, float x, float y, float width,
                         float fraction, int color) {
            fraction = Math.max(0, Math.min(1, fraction));
            rounded(canvas, x, y, x + width, y + 12, 6,
                Color.rgb(43, 45, 52), Color.TRANSPARENT);
            if (fraction > 0) {
                rounded(canvas, x, y, x + Math.max(12, width * fraction), y + 12,
                    6, color, Color.TRANSPARENT);
            }
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float sx = getWidth() / DESIGN_W;
            float sy = getHeight() / DESIGN_H;
            canvas.save();
            canvas.scale(sx, sy);
            canvas.drawColor(Color.BLACK);

            JSONObject state = snapshot;
            if (state == null) {
                text(canvas, "POKéMON", 56, 92, 28, MUTED, true);
                text(canvas, "Ready when you are", 56, 166, 52, TEXT, true);
                text(canvas, "Game details will appear after your adventure loads.",
                    56, 222, 24, MUTED, false);
                canvas.restore();
                return;
            }

            boolean blue = "blue".equalsIgnoreCase(state.optString("version", "red"));
            int accent = blue ? BLUE : RED;
            String context = state.optString("contextLabel", "Exploring");
            text(canvas, state.optString("location", "Unknown location"),
                56, 92, 46, TEXT, true);
            text(canvas, String.format(Locale.US, "%s  •  %s",
                    state.optString("playerName", "TRAINER"), context.toUpperCase()),
                58, 136, 22, accent, true);

            JSONObject battle = state.optJSONObject("battle");
            if (battle != null) {
                JSONObject enemy = battle.optJSONObject("enemy");
                if (enemy != null) {
                    String opponent = enemy.optString("name", "Opponent")
                        + "  Lv" + enemy.optInt("level", 1);
                    paint.setTextSize(28);
                    paint.setTypeface(medium);
                    float tw = paint.measureText(opponent);
                    text(canvas, opponent, DESIGN_W - 56 - tw, 92, 28, TEXT, true);
                    text(canvas, "NOW BATTLING", DESIGN_W - 247, 128,
                        16, MUTED, true);
                }
            } else {
                String position = String.format(Locale.US, "MAP %02d, %02d",
                    state.optInt("x", 0), state.optInt("y", 0));
                paint.setTextSize(20);
                paint.setTypeface(medium);
                text(canvas, position, DESIGN_W - 56 - paint.measureText(position),
                    104, 20, MUTED, true);
            }

            JSONArray party = state.optJSONArray("party");
            int partyCount = party == null ? 0 : party.length();
            if (partyCount == 0) {
                rounded(canvas, 56, 184, 1184, 790, 26, CARD, CARD_STROKE);
                text(canvas, "Your adventure is waiting.", 94, 308, 42, TEXT, true);
                text(canvas, "Your party will appear here after you choose a partner.",
                    94, 360, 24, MUTED, false);
            } else {
                for (int i = 0; i < Math.min(6, partyCount); i++) {
                    drawPokemon(canvas, party.optJSONObject(i), i, accent);
                }
            }

            drawFooter(canvas, state, accent);
            canvas.restore();
        }

        private void drawPokemon(Canvas canvas, JSONObject mon, int index, int accent) {
            if (mon == null) return;
            int col = index % 2;
            int row = index / 2;
            float x = col == 0 ? 56 : 636;
            float y = 184 + row * 205;
            float w = 548;
            rounded(canvas, x, y, x + w, y + 180, 24, CARD, CARD_STROKE);

            String name = mon.optString("name", "?");
            text(canvas, name, x + 28, y + 46, 28, TEXT, true);
            String level = "Lv " + mon.optInt("level", 1);
            paint.setTextSize(22);
            paint.setTypeface(medium);
            text(canvas, level, x + w - 28 - paint.measureText(level),
                y + 44, 22, MUTED, true);

            int hp = mon.optInt("hp", 0);
            int maxHp = Math.max(1, mon.optInt("maxHp", 1));
            int hpColor = hp * 2 < maxHp ? (hp * 5 < maxHp ? RED : YELLOW) : GREEN;
            text(canvas, "HP", x + 28, y + 84, 17, MUTED, true);
            String hpText = hp + " / " + maxHp;
            paint.setTextSize(17);
            paint.setTypeface(medium);
            text(canvas, hpText, x + w - 28 - paint.measureText(hpText),
                y + 84, 17, TEXT, true);
            bar(canvas, x + 28, y + 97, w - 56, (float) hp / maxHp, hpColor);

            int exp = mon.optInt("expIntoLevel", 0);
            int expLevel = Math.max(1, mon.optInt("expForLevel", 1));
            text(canvas, "EXP", x + 28, y + 140, 17, MUTED, true);
            String expText = mon.optInt("expToNext", 0) + " to next";
            String status = mon.optString("status", "");
            if (!status.isEmpty()) expText = status + "  •  " + expText;
            paint.setTextSize(17);
            paint.setTypeface(medium);
            text(canvas, expText, x + w - 28 - paint.measureText(expText),
                y + 140, 17, status.isEmpty() ? MUTED : accent, true);
            bar(canvas, x + 28, y + 153, w - 56, (float) exp / expLevel, accent);
        }

        private void drawFooter(Canvas canvas, JSONObject state, int accent) {
            float top = 816;
            paint.setColor(CARD_STROKE);
            paint.setStrokeWidth(2);
            canvas.drawLine(56, top, 1184, top, paint);

            text(canvas, "BADGES", 56, 866, 18, MUTED, true);
            JSONArray badges = state.optJSONArray("badges");
            for (int i = 0; i < 8; i++) {
                boolean earned = badges != null && i < badges.length()
                    && badges.optJSONObject(i) != null
                    && badges.optJSONObject(i).optBoolean("earned", false);
                float cx = 76 + i * 58;
                float cy = 920;
                paint.setStyle(Paint.Style.FILL);
                paint.setColor(earned ? accent : Color.rgb(31, 33, 39));
                canvas.drawCircle(cx, cy, 18, paint);
                if (!earned) {
                    paint.setStyle(Paint.Style.STROKE);
                    paint.setStrokeWidth(2);
                    paint.setColor(CARD_STROKE);
                    canvas.drawCircle(cx, cy, 18, paint);
                }
                text(canvas, Integer.toString(i + 1), cx - 5, cy + 6,
                    15, earned ? Color.WHITE : MUTED, true);
            }

            String money = String.format(Locale.US, "¥%,d", state.optInt("money", 0));
            paint.setTextSize(34);
            paint.setTypeface(medium);
            text(canvas, money, 1184 - paint.measureText(money), 923, 34, TEXT, true);
            text(canvas, "CASH", 1108, 866, 18, MUTED, true);
            text(canvas, "LIVE COMPANION", 56, 1030, 16, Color.rgb(70, 72, 80), true);
        }
    }
}
