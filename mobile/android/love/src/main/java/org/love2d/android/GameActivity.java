/**
 * Copyright (c) 2006-2023 LOVE Development Team
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 **/

package org.love2d.android;

import org.libsdl.app.SDLActivity;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import android.Manifest;
import android.app.AlertDialog;
import android.app.Presentation;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.ApplicationInfo;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.Paint;
import android.hardware.display.DisplayManager;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.os.Vibrator;
import android.util.Log;
import android.util.DisplayMetrics;
import android.view.*;
import android.content.pm.PackageManager;

import androidx.annotation.Keep;
import androidx.core.app.ActivityCompat;

public class GameActivity extends SDLActivity {
    private static DisplayMetrics metrics = null;
    private static String gamePath = "";
    private static Vibrator vibrator = null;
    protected final int[] externalStorageRequestDummy = new int[1];
    protected final int[] recordAudioRequestDummy = new int[1];
    public static final int EXTERNAL_STORAGE_REQUEST_CODE = 2;
    public static final int RECORD_AUDIO_REQUEST_CODE = 3;
    public static final int FILE_PICKER_REQUEST_CODE = 4;
    public static final int FILE_CREATE_REQUEST_CODE = 5;
    /** @deprecated Prefer FILE_PICKER_REQUEST_CODE; kept for older call sites. */
    public static final int ROM_PICKER_REQUEST_CODE = FILE_PICKER_REQUEST_CODE;
    // Mirrors conf.lua's t.identity ("pokemon-love2d"): where the picked file
    // is dropped so RomImporter's existing folder scan finds it -- see
    // src/import/RomImporter.lua and Filesystem::setIdentity (sets Android's
    // save directory to getExternalFilesDir()/save/<identity>).
    private static final String ROM_SAVE_IDENTITY = "pokemon-love2d";
    private static final String PICKED_ROM_FILENAME = "picked_rom.gb";
    private static final String PICKED_MOD_FILENAME = "picked_mod.zip";
    private static final String PICKED_SAVE_FILENAME = "picked_save.sav";
    private static final String PENDING_EXPORT_FILENAME = "pending_export.sav";
    private static final String EXPORT_DONE_FILENAME = "export_done.flag";
    // Written when a SAF pick cannot be read at all, with the destination
    // basename as its body, so RomImporter:focus can say so in the launcher
    // instead of leaving the player on "No ROM imported" (issue #442).
    private static final String PICK_ERROR_FILENAME = "pick_error.flag";
    // Destination basename for the in-flight SAF pick (set by showFilePicker).
    private String pendingPickFilename = PICKED_ROM_FILENAME;
    // Suggested download name for the in-flight SAF create (set by showCreateDocument).
    private String pendingCreateSuggestedName = "export.sav";
    private static boolean immersiveActive = false;
    private static boolean needToCopyGameInArchive = false;
    private boolean storagePermissionUnnecessary = false;
    private boolean shortEdgesMode = false;
    public boolean embed = false;
    public int safeAreaTop = 0;
    public int safeAreaLeft = 0;
    public int safeAreaBottom = 0;
    public int safeAreaRight = 0;

    // Secondary-display support (e.g. the bottom panel on an AYN Thor,
    // exposed by Android as a Presentation-category Display -- see
    // mobile/ANDROID.md and docs on love.system.hasSecondaryDisplay /
    // love.system.presentUIFrame). Static because the JNI bridge in
    // src/common/android.cpp calls these as static methods, matching the
    // rest of this class's existing statics (gamePath, vibrator, etc).
    private static Presentation secondaryPresentation = null;
    private static UIFrameView secondaryView = null;

    // A plain View that just blits whatever Bitmap it's given. Deliberately
    // NOT part of SDL's/LÖVE's GL surface or event loop -- it's a second,
    // independent Android window, fed frames explicitly via pushUIFrame
    // rather than sharing LÖVE's renderer or draw thread.
    private static class UIFrameView extends View {
        private Bitmap frame;
        private final Paint paint = new Paint();
        private boolean touchDown = false;

        UIFrameView(Context context) {
            super(context);
            setBackgroundColor(0xFFFFFFFF); // matches the white GB-style
                                             // panels (Font.drawBox, etc.)
                                             // pushed frames are drawn
                                             // with, while no frame has
                                             // arrived yet or outside the
                                             // letterboxed content rect
            paint.setFilterBitmap(false); // nearest-neighbour: pushed frames
                                           // are pixel art, same as the main
                                           // screen's integer-scale pipeline
        }

        void setFrame(Bitmap bitmap) {
            frame = bitmap;
            postInvalidate();
        }

        // Shared by onDraw and onTouchEvent so the letterbox math (and thus
        // the coordinate space touches get reported in) can never drift
        // from what is actually on screen. Returns null if there is nothing
        // sane to compute against yet (no frame, zero-size view).
        private android.graphics.RectF contentRect() {
            if (frame == null) {
                return null;
            }
            int vw = getWidth();
            int vh = getHeight();
            int fw = frame.getWidth();
            int fh = frame.getHeight();
            if (vw <= 0 || vh <= 0 || fw <= 0 || fh <= 0) {
                return null;
            }
            float scale = Math.min((float) vw / fw, (float) vh / fh);
            float dw = fw * scale;
            float dh = fh * scale;
            float left = (vw - dw) / 2f;
            float top = (vh - dh) / 2f;
            return new android.graphics.RectF(left, top, left + dw, top + dh);
        }

        @Override
        protected void onDraw(android.graphics.Canvas canvas) {
            super.onDraw(canvas);
            android.graphics.RectF dst = contentRect();
            if (dst != null) {
                canvas.drawBitmap(frame, null, dst, paint);
            }
        }

        // Reverse channel for pushUIFrame: reports taps back in the pushed
        // frame's own pixel space (clamped to its bounds), so Lua-side
        // hit-testing (see src/render/SecondScreenInput.lua) can work
        // against the exact coordinates it drew at, independent of the
        // panel's actual resolution or the letterbox offset. Single-touch
        // only -- plenty for menu taps, and multi-touch on a status/menu
        // panel is not a case worth the extra complexity yet.
        @Override
        public boolean onTouchEvent(MotionEvent event) {
            android.graphics.RectF dst = contentRect();
            if (dst == null) {
                return true;
            }
            int action;
            switch (event.getAction() & MotionEvent.ACTION_MASK) {
                case MotionEvent.ACTION_DOWN:
                    action = 0;
                    touchDown = true;
                    break;
                case MotionEvent.ACTION_MOVE:
                    if (!touchDown) return true;
                    action = 1;
                    break;
                case MotionEvent.ACTION_UP:
                    action = 2;
                    touchDown = false;
                    break;
                default: // CANCEL and anything else: treat as a cancel
                    action = 3;
                    touchDown = false;
                    break;
            }
            float scale = dst.width() / frame.getWidth();
            float fx = (event.getX() - dst.left) / scale;
            float fy = (event.getY() - dst.top) / scale;
            fx = Math.max(0f, Math.min((float) frame.getWidth(), fx));
            fy = Math.max(0f, Math.min((float) frame.getHeight(), fy));
            queueSecondScreenTouch(action, fx, fy);
            return true;
        }
    }

    // Queued taps on the second screen, drained by pollSecondScreenTouch
    // (called from love::android::pollSecondScreenTouch in android.cpp,
    // itself driven by love.system.pollSecondScreenTouch). Capped so a
    // Lua side that stops polling (wrong phase, second screen torn down
    // mid-gesture) cannot grow this unboundedly; dropping the OLDEST entry
    // once full keeps the most current finger position, which is the one
    // that matters for a menu tap.
    private static final int MAX_QUEUED_SECOND_SCREEN_TOUCHES = 64;
    private static final ArrayDeque<float[]> secondScreenTouchQueue = new ArrayDeque<>();

    private static synchronized void queueSecondScreenTouch(int action, float x, float y) {
        if (secondScreenTouchQueue.size() >= MAX_QUEUED_SECOND_SCREEN_TOUCHES) {
            secondScreenTouchQueue.pollFirst();
        }
        secondScreenTouchQueue.addLast(new float[] { action, x, y });
    }

    // {action, x, y} for the oldest queued touch, or null if none is
    // pending. action: 0 = down, 1 = move, 2 = up, 3 = cancel. x/y are in
    // the same pixel space as the w/h a presentUIFrame call last used.
    @Keep
    public static synchronized float[] pollSecondScreenTouch() {
        return secondScreenTouchQueue.pollFirst();
    }

    // Looks for a Presentation-category secondary display (DisplayManager's
    // term for a display meant to host separate content, as opposed to a
    // mirrored one) and, if found, shows a Presentation with a UIFrameView
    // on it. Safe to call more than once; a no-op after the first display is
    // attached. Called from onCreate; does nothing on single-screen devices.
    private void attachSecondaryDisplay() {
        if (secondaryPresentation != null) {
            return;
        }

        DisplayManager displayManager = (DisplayManager) getSystemService(Context.DISPLAY_SERVICE);
        if (displayManager == null) {
            return;
        }

        Display[] presentationDisplays =
            displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION);
        if (presentationDisplays.length == 0) {
            Log.d("GameActivity", "No secondary (presentation) display found.");
            return;
        }

        // First presentation display found; devices seen so far (AYN Thor)
        // expose exactly one.
        Display secondaryDisplay = presentationDisplays[0];
        Presentation presentation = new Presentation(this, secondaryDisplay);
        // A Presentation's Window is focusable by default, so a touch on it
        // could pull KEY input focus (D-pad/A/B, delivered as key events by
        // SDL) away from the main game window onto this one -- the second
        // screen is touch-only UI and must never intercept physical button
        // presses meant for gameplay. FLAG_NOT_FOCUSABLE only blocks that;
        // touch delivery (onTouchEvent above) doesn't require window focus
        // and is unaffected.
        presentation.getWindow().setFlags(
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
        UIFrameView view = new UIFrameView(presentation.getContext());
        presentation.setContentView(view);

        try {
            presentation.show();
        } catch (WindowManager.InvalidDisplayException e) {
            Log.d("GameActivity", "Secondary display went away before show()", e);
            return;
        }

        secondaryPresentation = presentation;
        secondaryView = view;
        Log.d("GameActivity", "Attached secondary display: " + secondaryDisplay);
    }

    // Counterpart to attachSecondaryDisplay: dismisses the Presentation so
    // the second screen goes blank/closes whenever the main screen does
    // (onPause -- home button, screen lock, task switch away). Safe to call
    // when nothing is attached. hasSecondaryDisplay() correctly reports
    // false once this runs, so Lua-side pushers (see
    // src/render/SecondScreen.lua) stop on their own without needing to
    // know the activity backgrounded -- attachSecondaryDisplay() re-shows
    // it from onResume.
    private void dismissSecondaryDisplay() {
        if (secondaryPresentation == null) {
            return;
        }
        secondaryPresentation.dismiss();
        secondaryPresentation = null;
        secondaryView = null;
        synchronized (GameActivity.class) {
            secondScreenTouchQueue.clear();
        }
        Log.d("GameActivity", "Dismissed secondary display (activity backgrounded)");
    }

    @Keep
    public static boolean hasSecondaryDisplay() {
        return secondaryPresentation != null && secondaryView != null;
    }

    // pixels: raw RGBA8 bytes, row-major, no padding -- w*h*4 bytes exactly,
    // the same layout love.graphics.Canvas:newImageData():getString() hands
    // back in Lua. Called from the JNI bridge in src/common/android.cpp
    // (love::android::presentUIFrame), itself called from
    // love.system.presentUIFrame. Runs on LÖVE's thread, not the UI thread,
    // so the actual Bitmap update + invalidate is posted over to it.
    @Keep
    public static boolean pushUIFrame(byte[] pixels, int w, int h) {
        if (secondaryView == null || pixels == null || w <= 0 || h <= 0) {
            return false;
        }
        if (pixels.length != w * h * 4) {
            return false;
        }

        final Bitmap bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        bitmap.copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(pixels));

        final UIFrameView view = secondaryView;
        view.post(new Runnable() {
            @Override
            public void run() {
                view.setFrame(bitmap);
            }
        });
        return true;
    }

    private static native void nativeSetDefaultStreamValues(int sampleRate, int framesPerBurst);

    @Override
    protected String[] getLibraries() {
        return new String[] {
            "c++_shared",
            "mpg123",
            "openal",
            "love",
        };
    }

    @Override
    protected String getMainSharedObject() {
        String[] libs = getLibraries();
        String libname = "lib" + libs[libs.length - 1] + ".so";

        // Since Lollipop, you can simply pass "libname.so" to dlopen
        // and it will resolve correct paths and load correct library.
        // This is mandatory for extractNativeLibs=false support in
        // Marshmallow.
        if (android.os.Build.VERSION.SDK_INT >= 21) {
            return libname;
        } else {
            return getContext().getApplicationInfo().nativeLibraryDir + "/" + libname;
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        Log.d("GameActivity", "started");

        int res = checkCallingOrSelfPermission(Manifest.permission.VIBRATE);
        if (res == PackageManager.PERMISSION_GRANTED) {
            vibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        } else {
            Log.d("GameActivity", "Vibration disabled: could not get vibration permission.");
        }

        // These 2 variables must be reset or it will use the existing value.
        gamePath = "";
        storagePermissionUnnecessary = false;
        embed = getResources().getBoolean(R.bool.embed);
        needToCopyGameInArchive = embed;

        if (!embed) {
            Intent intent = getIntent();
            handleIntent(intent);
            intent.setData(null);
        }

        super.onCreate(savedInstanceState);
        metrics = getResources().getDisplayMetrics();

        // Set low-latency audio values
        nativeSetDefaultStreamValues(getAudioFreq(), getAudioSMP());

        if (android.os.Build.VERSION.SDK_INT >= 28) {
            getWindow().getAttributes().layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER;
            shortEdgesMode = false;
        }

        attachSecondaryDisplay();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        Log.d("GameActivity", "onNewIntent() with " + intent);
        if (!embed) {
            handleIntent(intent);
            resetNative();
            startNative();
        }
    }

    protected void handleIntent(Intent intent) {
        Uri game = intent.getData();

        if (!embed && game != null) {
            String scheme = game.getScheme();
            String path = game.getPath();
            // If we have a game via the intent data we we try to figure out how we have to load it. We
            // support the following variations:
            // * a main.lua file: set gamePath to the directory containing main.lua
            // * otherwise: set gamePath to the file
            if (scheme.equals("file")) {
                Log.d("GameActivity", "Received file:// intent with path: " + path);
                // If we were given the path of a main.lua then use its
                // directory. Otherwise use full path.
                List<String> path_segments = game.getPathSegments();
                if (path_segments.get(path_segments.size() - 1).equals("main.lua")) {
                    gamePath = path.substring(0, path.length() - "main.lua".length());
                } else {
                    gamePath = path;
                }
            } else if (scheme.equals("content")) {
                Log.d("GameActivity", "Received content:// intent with path: " + path);
                try {
                    String filename = "game.love";
                    String[] pathSegments = path.split("/");
                    if (pathSegments.length > 0) {
                        filename = pathSegments[pathSegments.length - 1];
                    }

                    // Sanitize filename to prevent PhysFS complaining later.
                    filename = filename.replaceAll("[^a-zA-Z0-9_\\\\-\\\\.]", "_");

                    String destination_file = this.getCacheDir().getPath() + "/" + filename;
                    InputStream data = getContentResolver().openInputStream(game);

                    // copyAssetFile automatically closes the InputStream
                    if (copyAssetFile(data, destination_file)) {
                        gamePath = destination_file;
                        storagePermissionUnnecessary = true;
                    }
                } catch (Exception e) {
                    Log.d("GameActivity", "could not read content uri " + game.toString() + ": " + e.getMessage());
                }
            } else {
                Log.e("GameActivity", "Unsupported scheme: '" + game.getScheme() + "'.");

                AlertDialog.Builder alert_dialog = new AlertDialog.Builder(this);
                alert_dialog.setMessage("Could not load LÖVE game '" + path
                        + "' as it uses unsupported scheme '" + game.getScheme()
                        + "'. Please contact the developer.");
                alert_dialog.setTitle("LÖVE for Android Error");
                alert_dialog.setPositiveButton("Exit",
                        new DialogInterface.OnClickListener() {
                            @Override
                            public void onClick(DialogInterface dialog, int id) {
                                finish();
                            }
                        });
                alert_dialog.setCancelable(false);
                alert_dialog.create().show();
            }
        }

        Log.d("GameActivity", "new gamePath: " + gamePath);
    }

    private void copyGameInsideArchive() {
        try {
            // If we have a game.love in our assets folder copy it to the cache folder
            // so that we can load it from native LÖVE code
            AssetManager assetManager = getAssets();
            InputStream gameStream = assetManager.open("game.love");
            String destinationFile = this.getCacheDir().getPath() + "/game.love";

            if (copyAssetFile(gameStream, destinationFile))
                gamePath = destinationFile;
            else
                gamePath = "game.love";
            storagePermissionUnnecessary = true;
        } catch (IOException e) {
            // There's no game.love in our assets
            Log.d("GameActivity", "Could not open game.love from assets: " + e.getMessage());
        }
    }

    protected void checkLovegameFolder() {
        // If no game.love was found and embed flavor is not used, fall back to the game in
        // <external storage>/Android/data/<package name>/games/lovegame
        if (!embed) {
            Log.d("GameActivity", "fallback to lovegame folder");
            File ext = getExternalFilesDir("games");
            if ((new File(ext, "/lovegame/main.lua")).exists()) {
                gamePath = ext.getPath() + "/lovegame/";
                storagePermissionUnnecessary = true;
            } else if (android.os.Build.VERSION.SDK_INT <= 28) {
                // Try to fallback to /sdcard/lovegame in Android 9 and earlier too.
                if (hasExternalStoragePermission()) {
                    ext = Environment.getExternalStorageDirectory();
                    if ((new File(ext, "/lovegame/main.lua")).exists()) {
                        gamePath = ext.getPath() + "/lovegame/";
                        storagePermissionUnnecessary = false;
                    }
                } else {
                    Log.d("GameActivity", "Cannot load game from /sdcard/lovegame: permission not granted");
                }
            }

            Log.d("GameActivity", "lovegame directory: " + gamePath);
        }
    }

    @Override
    protected void onDestroy() {
        if (vibrator != null) {
            Log.d("GameActivity", "Cancelling vibration");
            vibrator.cancel();
        }
        dismissSecondaryDisplay();
        super.onDestroy();
    }

    @Override
    protected void onPause() {
        if (vibrator != null) {
            Log.d("GameActivity", "Cancelling vibration");
            vibrator.cancel();
        }
        dismissSecondaryDisplay();
        super.onPause();
    }

    @Override
    public void onResume() {
        super.onResume();
        attachSecondaryDisplay();
    }

    /**
     * SDL decides the activity's requested orientation at window creation
     * (SDLActivity.setOrientationBis). With a resizable window and no
     * SDL_HINT_ORIENTATIONS -- exactly what conf.lua produces on Android --
     * it asks for SCREEN_ORIENTATION_FULL_SENSOR, and that request overrides
     * the android:screenOrientation="fullUser" set in the manifest. The
     * *_SENSOR constants follow the accelerometer even when the player has
     * turned auto-rotate off, so the game kept rotating on a device whose
     * rotation was locked.
     *
     * Remap SDL's choice onto the matching *_USER constant, which allows the
     * same orientations but defers to the system rotation setting. Applied
     * after super so SDL keeps deciding *which* orientations the window may
     * take; this only changes who breaks the tie, the sensor or the player.
     */
    @Override
    public void setOrientationBis(int w, int h, boolean resizable, String hint) {
        super.setOrientationBis(w, h, resizable, hint);

        // The *_USER constants only exist from API 18; below that the sensor
        // ones are all there is, so leave SDL's request alone.
        if (android.os.Build.VERSION.SDK_INT < 18) {
            return;
        }

        int requested = getRequestedOrientation();
        int userRequested;
        switch (requested) {
            case ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR:
                userRequested = ActivityInfo.SCREEN_ORIENTATION_FULL_USER;
                break;
            case ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE:
                userRequested = ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE;
                break;
            case ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT:
                userRequested = ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT;
                break;
            default:
                // SENSOR / plain LANDSCAPE / PORTRAIT etc: either already
                // explicit or never produced by setOrientationBis.
                return;
        }

        Log.d("GameActivity", "requestedOrientation " + requested + " -> " + userRequested
            + " (honour the device rotation lock)");
        setRequestedOrientation(userRequested);
    }

    @Keep
    public void setImmersiveMode(boolean immersive_mode) {
        if (android.os.Build.VERSION.SDK_INT >= 28) {
            getWindow().getAttributes().layoutInDisplayCutoutMode = immersive_mode ?
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES :
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER;
            shortEdgesMode = immersive_mode;
        }

        immersiveActive = immersive_mode;
    }

    @Keep
    public boolean getImmersiveMode() {
        return immersiveActive;
    }

    @Keep
    public static String getGamePath() {
        GameActivity self = (GameActivity) mSingleton; // use SDL provided one
        Log.d("GameActivity", "called getGamePath(), game path = " + gamePath);

        if (gamePath.length() > 0) {
            if (self.storagePermissionUnnecessary || self.hasExternalStoragePermission()) {
                return gamePath;
            } else {
                Log.d("GameActivity", "cannot open game " + gamePath + ": no external storage permission given!");
            }
        } else if (needToCopyGameInArchive) {
            self.copyGameInsideArchive();
        } else {
            self.checkLovegameFolder();
        }

        return gamePath;
    }

    public static DisplayMetrics getMetrics() {
        return metrics;
    }

    @Keep
    public static void vibrate(double seconds) {
        if (vibrator != null) {
            vibrator.vibrate((long) (seconds * 1000.));
        }
    }

    @Keep
    public static boolean openURLFromLOVE(String url) {
        Log.d("GameActivity", "opening url = " + url);
        return openURL(url) == 0;
    }

    /**
     * Shows the system document picker (Storage Access Framework) so the
     * player can pick a ROM / mod / save from anywhere (Downloads, Drive,
     * etc.) without needing to know where the app's external files folder
     * is. Requires API 19+ (ACTION_OPEN_DOCUMENT); the picked file (if any)
     * arrives later in onActivityResult, not synchronously here.
     *
     * @param destFilename basename under the app save identity (e.g.
     *                     picked_rom.gb, picked_mod.zip, picked_save.sav)
     */
    @Keep
    public static boolean showFilePicker(String destFilename) {
        if (android.os.Build.VERSION.SDK_INT < 19) return false;
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (destFilename == null || destFilename.length() == 0) {
            destFilename = PICKED_ROM_FILENAME;
        }
        // Reject path separators so a hostile JNI caller cannot escape the
        // save identity directory.
        if (destFilename.indexOf('/') >= 0 || destFilename.indexOf('\\') >= 0) {
            Log.d("GameActivity", "refusing unsafe picker dest: " + destFilename);
            return false;
        }

        self.pendingPickFilename = destFilename;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        try {
            self.startActivityForResult(intent, FILE_PICKER_REQUEST_CODE);
            return true;
        } catch (Exception e) {
            Log.d("GameActivity", "could not open file picker: " + e.getMessage());
            return false;
        }
    }

    /** ROM convenience wrapper; prefer showFilePicker with an explicit name. */
    @Keep
    public static boolean showRomFilePicker() {
        return showFilePicker(PICKED_ROM_FILENAME);
    }

    /** Mod .zip convenience wrapper used by love.system.pickFile("mod"). */
    @Keep
    public static boolean showModFilePicker() {
        return showFilePicker(PICKED_MOD_FILENAME);
    }

    /** Battery .sav convenience wrapper used by love.system.pickFile("sav"). */
    @Keep
    public static boolean showSaveFilePicker() {
        return showFilePicker(PICKED_SAVE_FILENAME);
    }

    /**
     * Shows ACTION_CREATE_DOCUMENT so the player can save a staged export
     * (pending_export.sav in the app save identity) to Downloads / Drive /
     * etc. Suggested name is the dialog's default filename.
     */
    @Keep
    public static boolean showCreateDocument(String suggestedName) {
        if (android.os.Build.VERSION.SDK_INT < 19) return false;
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (suggestedName == null || suggestedName.length() == 0) {
            suggestedName = "export.sav";
        }
        if (suggestedName.indexOf('/') >= 0 || suggestedName.indexOf('\\') >= 0) {
            Log.d("GameActivity", "refusing unsafe create name: " + suggestedName);
            return false;
        }
        File source = new File(
            new File(self.getExternalFilesDir(null), "save"),
            ROM_SAVE_IDENTITY + "/" + PENDING_EXPORT_FILENAME);
        if (!source.isFile()) {
            Log.d("GameActivity", "no pending export at " + source);
            return false;
        }

        self.pendingCreateSuggestedName = suggestedName;
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/octet-stream");
        intent.putExtra(Intent.EXTRA_TITLE, suggestedName);
        try {
            self.startActivityForResult(intent, FILE_CREATE_REQUEST_CODE);
            return true;
        } catch (Exception e) {
            Log.d("GameActivity", "could not open create-document picker: " + e.getMessage());
            return false;
        }
    }

    private File saveIdentityDir() {
        return new File(new File(getExternalFilesDir(null), "save"), ROM_SAVE_IDENTITY);
    }

    /** Drops a small flag file in the save identity for Lua to consume on focus. */
    private void writeSaveDirFlag(String name, String body) {
        try {
            FileOutputStream fos = new FileOutputStream(new File(saveIdentityDir(), name), false);
            fos.write(body.getBytes());
            fos.close();
        } catch (IOException e) {
            Log.d("GameActivity", "could not write " + name + ": " + e.getMessage());
        }
    }

    private boolean copyFileToUri(File source, Uri destUri) {
        InputStream in = null;
        OutputStream out = null;
        try {
            in = new BufferedInputStream(new FileInputStream(source));
            out = getContentResolver().openOutputStream(destUri);
            if (out == null) return false;
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) != -1) {
                out.write(buf, 0, n);
            }
            out.flush();
            return true;
        } catch (IOException e) {
            Log.d("GameActivity", "copy to URI failed: " + e.getMessage());
            return false;
        } finally {
            try { if (in != null) in.close(); } catch (IOException ignored) {}
            try { if (out != null) out.close(); } catch (IOException ignored) {}
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == FILE_CREATE_REQUEST_CODE) {
            if (resultCode != RESULT_OK || data == null || data.getData() == null) {
                Log.d("GameActivity", "create-document cancelled");
                return;
            }
            File source = new File(saveIdentityDir(), PENDING_EXPORT_FILENAME);
            if (!source.isFile()) {
                Log.d("GameActivity", "pending export missing at result time");
                return;
            }
            Uri uri = data.getData();
            if (copyFileToUri(source, uri)) {
                // Signal Lua on next focus that the SAF export finished.
                writeSaveDirFlag(EXPORT_DONE_FILENAME, "ok");
                // Keep pending_export.sav so a retry still works; Lua may remove it.
            } else {
                Log.d("GameActivity", "could not write export to " + uri);
            }
            return;
        }
        if (requestCode != FILE_PICKER_REQUEST_CODE) return;
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            Log.d("GameActivity", "file picker returned no file (cancelled?)");
            return;
        }

        Uri uri = data.getData();
        File destDir = saveIdentityDir();
        if (!destDir.exists() && !destDir.mkdirs()) {
            Log.d("GameActivity", "could not create " + destDir);
            return;
        }
        String destName = pendingPickFilename != null
            ? pendingPickFilename : PICKED_ROM_FILENAME;
        File destFile = new File(destDir, destName);

        // ACTION_OPEN_DOCUMENT is meant to land in the system documents UI, but
        // some OEM shells (ColorOS) offer third-party file managers in a
        // chooser, and those hand back either a provider URI this app has no
        // grant for (SecurityException / FileNotFoundException) or a bare
        // file:// path (unreadable without storage permission on targetSdk 34).
        // Try the resolver, then the path, then tell Lua why nothing imported.
        InputStream source = null;
        try {
            source = getContentResolver().openInputStream(uri);
        } catch (Exception e) {
            Log.d("GameActivity", "could not open picked file: " + e.getMessage());
        }
        if (source == null && "file".equals(uri.getScheme()) && uri.getPath() != null) {
            try {
                source = new FileInputStream(uri.getPath());
            } catch (FileNotFoundException e) {
                Log.d("GameActivity", "could not open picked path: " + e.getMessage());
            }
        }
        if (source == null) {
            Log.d("GameActivity", "no readable stream for picked file " + uri);
            writeSaveDirFlag(PICK_ERROR_FILENAME, destName);
            return;
        }
        if (!copyAssetFile(source, destFile.getPath())) {
            Log.d("GameActivity", "could not copy picked file to " + destFile);
            // A truncated pick would only fail verification later, so drop it
            // and report instead.
            destFile.delete();
            writeSaveDirFlag(PICK_ERROR_FILENAME, destName);
        }
    }

    /**
     * Copies a given file from the assets folder to the destination.
     *
     * @return true if successful
     */
    boolean copyAssetFile(InputStream source, String destinationFileName) {
        boolean success = false;

        BufferedOutputStream destination = null;
        try {
            destination = new BufferedOutputStream(new FileOutputStream(destinationFileName, false));
        } catch (IOException e) {
            Log.d("GameActivity", "Could not open destination file: " + e.getMessage());
        }

        // perform the copying
        int chunk_read;
        int bytes_written = 0;

        assert (source != null && destination != null);

        try {
            byte[] buf = new byte[1024];
            chunk_read = source.read(buf);
            do {
                destination.write(buf, 0, chunk_read);
                bytes_written += chunk_read;
                chunk_read = source.read(buf);
            } while (chunk_read != -1);
        } catch (IOException e) {
            Log.d("GameActivity", "Copying failed:" + e.getMessage());
        }

        // close streams
        try {
            source.close();
            destination.close();
            success = true;
        } catch (IOException e) {
            Log.d("GameActivity", "Copying failed: " + e.getMessage());
        }

        Log.d("GameActivity", "Successfully copied stream to " + destinationFileName + " (" + bytes_written + " bytes written).");
        return success;
    }

    @Keep
    public boolean hasBackgroundMusic() {
        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        return audioManager.isMusicActive();
    }

    @Keep
    public void showRecordingAudioPermissionMissingDialog() {
        Log.d("GameActivity", "showRecordingAudioPermissionMissingDialog()");
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                AlertDialog dialog = new AlertDialog.Builder(mSingleton)
                    .setTitle("Audio Recording Permission Missing")
                    .setMessage("It appears that this game uses mic capabilities. The game may not work correctly without mic permission!")
                    .setNeutralButton("Continue", new DialogInterface.OnClickListener() {
                        public void onClick(DialogInterface di, int id) {
                            synchronized (recordAudioRequestDummy) {
                                recordAudioRequestDummy.notify();
                            }
                        }
                    })
                    .create();
                dialog.show();
            }
        });

        synchronized (recordAudioRequestDummy) {
            try {
                recordAudioRequestDummy.wait();
            } catch (InterruptedException e) {
                Log.d("GameActivity", "mic permission dialog", e);
            }
        }
    }

    public void showExternalStoragePermissionMissingDialog() {
        AlertDialog dialog = new AlertDialog.Builder(mSingleton)
            .setTitle("Storage Permission Missing")
            .setMessage("LÖVE for Android will not be able to run non-packaged games without storage permission.")
            .setNeutralButton("Continue", null)
            .create();
        dialog.show();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (grantResults.length > 0) {
            Log.d("GameActivity", "Received a request permission result");

            switch (requestCode) {
                case EXTERNAL_STORAGE_REQUEST_CODE: {
                    if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                        Log.d("GameActivity", "Permission granted");
                    } else {
                        Log.d("GameActivity", "Did not get permission.");
                        if (ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.READ_EXTERNAL_STORAGE)) {
                            showExternalStoragePermissionMissingDialog();
                        }
                    }

                    Log.d("GameActivity", "Unlocking LÖVE thread");
                    synchronized (externalStorageRequestDummy) {
                        externalStorageRequestDummy[0] = grantResults[0];
                        externalStorageRequestDummy.notify();
                    }
                    break;
                }
                case RECORD_AUDIO_REQUEST_CODE: {
                    if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                        Log.d("GameActivity", "Mic permission granted");
                    } else {
                        Log.d("GameActivity", "Did not get mic permission.");
                    }

                    Log.d("GameActivity", "Unlocking LÖVE thread");
                    synchronized (recordAudioRequestDummy) {
                        recordAudioRequestDummy[0] = grantResults[0];
                        recordAudioRequestDummy.notify();
                    }
                    break;
                }
                default:
                    super.onRequestPermissionsResult(requestCode, permissions, grantResults);
            }
        }
    }

    @Keep
    public boolean hasExternalStoragePermission() {
        if (ActivityCompat.checkSelfPermission(this,
                Manifest.permission.READ_EXTERNAL_STORAGE)
                == PackageManager.PERMISSION_GRANTED) {
            return true;
        }

        Log.d("GameActivity", "Requesting permission and locking LÖVE thread until we have an answer.");
        ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.READ_EXTERNAL_STORAGE}, EXTERNAL_STORAGE_REQUEST_CODE);

        synchronized (externalStorageRequestDummy) {
            try {
                externalStorageRequestDummy.wait();
            } catch (InterruptedException e) {
                Log.d("GameActivity", "requesting external storage permission", e);
                return false;
            }
        }

        return ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED;
    }

    @Keep
    public boolean hasRecordAudioPermission() {
        return ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
    }

    @Keep
    public void requestRecordAudioPermission() {
        if (ActivityCompat.checkSelfPermission(this,
                Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED) {
            return;
        }

        Log.d("GameActivity", "Requesting mic permission and locking LÖVE thread until we have an answer.");
        ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.RECORD_AUDIO}, RECORD_AUDIO_REQUEST_CODE);

        synchronized (recordAudioRequestDummy) {
            try {
                recordAudioRequestDummy.wait();
            } catch (InterruptedException e) {
                Log.d("GameActivity", "requesting mic permission", e);
            }
        }
    }

    @Keep
    public boolean initializeSafeArea() {
        if (android.os.Build.VERSION.SDK_INT >= 28 && shortEdgesMode) {
            DisplayCutout cutout = getWindow().getDecorView().getRootWindowInsets().getDisplayCutout();

            if (cutout != null) {
                safeAreaTop = cutout.getSafeInsetTop();
                safeAreaLeft = cutout.getSafeInsetLeft();
                safeAreaBottom = cutout.getSafeInsetBottom();
                safeAreaRight = cutout.getSafeInsetRight();
                return true;
            }
        }

        return false;
    }

    @Keep
    public String[] buildFileTree() {
        // Map key is path, value is directory flag
        HashMap<String, Boolean> map = buildFileTree(getAssets(), "", new HashMap<String, Boolean>());
        ArrayList<String> result = new ArrayList<String>();

        for (Map.Entry<String, Boolean> data: map.entrySet()) {
            result.add((data.getValue() ? "d" : "f") + data.getKey());
        }

        String[] r = new String[result.size()];
        result.toArray(r);
        return r;
    }

    private HashMap<String, Boolean> buildFileTree(AssetManager assetManager, String dir, HashMap<String, Boolean> map) {
        String strippedDir = dir.endsWith("/") ? dir.substring(0, dir.length() - 1) : dir;

        // Try open dir
        try {
            InputStream test = assetManager.open(strippedDir);
            // It's a file
            test.close();
            map.put(strippedDir, false);
        } catch (FileNotFoundException e) {
            // It's a directory
            String[] list = null;

            // List files
            try {
                list = assetManager.list(strippedDir);
            } catch (IOException e2) {
                Log.e("GameActivity", strippedDir, e2);
            }

            // Mark as file
            map.put(dir, true);

            // This Object comparison is intentional.
            if (strippedDir != dir) {
                map.put(strippedDir, true);
            }

            if (list != null) {
                for (String path: list) {
                    buildFileTree(assetManager, dir + path + "/", map);
                }
            }
        } catch (IOException e) {
            Log.e("GameActivity", dir, e);
        }

        return map;
    }

    public int getAudioSMP() {
        int smp = 256;

        if (android.os.Build.VERSION.SDK_INT >= 17) {
            AudioManager a = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            int b = Integer.parseInt(a.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER));
            return b > 0 ? b : smp;
        }

        return smp;
    }

    public int getAudioFreq() {
        int freq = 44100;

        if (android.os.Build.VERSION.SDK_INT >= 17) {
            AudioManager a = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            int b = Integer.parseInt(a.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE));
            return b > 0 ? b : freq;
        }

        return freq;
    }

    public boolean isNativeLibsExtracted() {
        ApplicationInfo appInfo = getApplicationInfo();

        if (android.os.Build.VERSION.SDK_INT >= 23) {
            return (appInfo.flags & ApplicationInfo.FLAG_EXTRACT_NATIVE_LIBS) != 0;
        }

        return true;
    }

    @Keep
    public String getCRequirePath() {
        ApplicationInfo applicationInfo = getApplicationInfo();

        if (isNativeLibsExtracted()) {
            return applicationInfo.nativeLibraryDir + "/?.so";
        } else {
            // The native libs are inside the APK and can be loaded directly.
            // FIXME: What about split APKs?
            String abi;

            if (android.os.Build.VERSION.SDK_INT >= 21) {
                 abi = android.os.Build.SUPPORTED_ABIS[0];
            } else {
                // This codepath should NEVER be taken as if isNativeLibsExtracted()
                // returns false, it's 100% safe to assume we're on API level 23 or later.
                abi = android.os.Build.CPU_ABI;
            }

            return applicationInfo.sourceDir + "!/lib/" + abi + "/?.so";
        }
    }
}
