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
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.security.MessageDigest;

import android.Manifest;
import android.app.AlarmManager;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.app.UiModeManager;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.ClipData;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.pm.ApplicationInfo;
import android.content.res.AssetManager;
import android.content.res.Configuration;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.media.AudioAttributes;
import android.media.AudioDeviceCallback;
import android.media.AudioDeviceInfo;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.Vibrator;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.Log;
import android.util.DisplayMetrics;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.content.pm.PackageManager;
import android.graphics.drawable.Icon;
import android.view.*;

import androidx.annotation.Keep;
import androidx.core.app.ActivityCompat;
import androidx.core.content.FileProvider;

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
    public static final int STEP_PERMISSION_REQUEST_CODE = 6;
    public static final int RESTART_REQUEST_CODE = 7;
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
    // Kept separate from the game-ROM destination so a dependency pick can
    // never be mistaken for a game import when the picker returns on Android.
    private static final String PICKED_REQUIRED_IMPORT_FILENAME = "picked_required_import.bin";
    private static final String PENDING_EXPORT_FILENAME = "pending_export.sav";
    private static final String EXPORT_DONE_FILENAME = "export_done.flag";
    // Written when a SAF pick cannot be read at all, with the destination
    // basename as its body, so RomImporter:focus can say so in the launcher
    // instead of leaving the player on "No ROM imported" (issue #442).
    private static final String PICK_ERROR_FILENAME = "pick_error.flag";
    private static final String PICK_CANCELLED_PREFIX = "cancelled:";
    // Written after a direct required-import copy has been fully published.
    private static final String PICK_COMPLETE_FILENAME = "pick_complete.flag";
    // Step bridge (love.system.syncHealthSteps): pending-steps delivery
    // consumed by the Pokéwalker mod, same contract as the iOS
    // GRHealthBridge. Steps come from the hardware TYPE_STEP_COUNTER
    // (cumulative since boot, counted by the OS whether or not any app is
    // running), anchored in SharedPreferences so a walk is never credited
    // twice.
    private static final String PENDING_STEPS_FILENAME = "steps_pending.json";
    private static final String STEP_PREFS = "pokewalker_steps";
    private static final String STEP_PREF_ANCHOR = "anchor";
    private static final String STEP_PREF_ANCHOR_WALLTIME = "anchor_walltime";
    private static final long STEP_MAX_PER_SYNC = 50000;
    // Destination basename for the in-flight SAF pick (set by showFilePicker).
    // Saved/restored across instance state: the picker is a separate activity
    // and Android may destroy this one while it is up (memory pressure, or
    // "Don't keep activities"). A recreated instance still receives
    // onActivityResult, so without this a mod or save pick came back with the
    // field reset and was filed as picked_rom.gb, which Lua then rejected as a
    // bad ROM instead of installing it (#553).
    private String pendingPickFilename = PICKED_ROM_FILENAME;
    private static final String STATE_PENDING_PICK = "pendingPickFilename";
    // Absolute save directory physfs actually mounted, as reported by the
    // native bridge call that opened the picker (love/src/common/android.cpp,
    // bridgeSaveDirectory).  This activity used to recompute
    // getExternalFilesDir(null)/save/<identity> on its own at result time; on
    // merged / adopted-SD storage that can name a different volume than the
    // one LOVE mounted, so the copied pick (and pick_error.flag) landed where
    // Lua never scans -- the launcher then "did nothing" after a pick (#604)
    // and the folders a file manager can browse stayed empty while the game
    // saved fine elsewhere (#839).  Empty string means "not told yet": fall
    // back to the historical computation.
    private String pendingPickSaveDir = "";
    private static final String STATE_PENDING_PICK_DIR = "pendingPickSaveDir";
    private static final String STATE_PENDING_CREATE = "pendingCreateSuggestedName";
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

    private static native void nativeSetDefaultStreamValues(int sampleRate, int framesPerBurst);

    private static native void nativeAudioFocusLost();

    private static native void nativeAudioFocusGained();

    private static native void nativeAudioDeviceChanged();

    private static native void nativeOnGameIntent(String game);

    private static native void nativeOnLaunchURI(String uri);

    private static String initialGame = "";
    private static String initialLaunchURI = "";

    private AudioManager.OnAudioFocusChangeListener audioFocusListener = null;
    private Object audioFocusRequest = null;
    private Object audioDeviceCallback = null;
    private boolean audioFocusHeld = false;
    private boolean audioDeviceCallbackPrimed = false;

    /**
     * Native libraries required by an optional Android host extension.
     *
     * Subclasses supplied by another product flavor may override this method.
     * The libraries are loaded after LÖVE's dependencies and before liblove;
     * liblove must remain last because SDL treats the final entry as the main
     * shared object.
     */
    protected String[] getHostLibraries() {
        return new String[0];
    }

    @Override
    protected String[] getLibraries() {
        String[] hostLibraries = getHostLibraries();
        String[] libraries = new String[hostLibraries.length + 4];
        libraries[0] = "c++_shared";
        libraries[1] = "mpg123";
        libraries[2] = "openal";
        System.arraycopy(hostLibraries, 0, libraries, 3, hostLibraries.length);
        libraries[libraries.length - 1] = "love";
        return libraries;
    }

    protected void onHostCreateBeforeSDL(Bundle savedInstanceState) {}
    protected void onHostCreateAfterSDL(Bundle savedInstanceState) {}
    protected void onHostResume() {}
    protected void onHostPause() {}
    protected void onHostDestroy() {}

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

        Intent startIntent = getIntent();
        if (startIntent != null && startIntent.hasExtra("game")) {
            initialGame = startIntent.getStringExtra("game");
        }
        Uri launchURI = getLaunchURI(startIntent);
        if (launchURI != null) {
            initialLaunchURI = launchURI.toString();
        }
        if (!embed) {
            Intent intent = getIntent();
            handleIntent(intent);
            intent.setData(null);
        }

        onHostCreateBeforeSDL(savedInstanceState);
        super.onCreate(savedInstanceState);
        onHostCreateAfterSDL(savedInstanceState);
        if (savedInstanceState != null) {
            // Restore the in-flight SAF destinations, so a pick that returns to
            // a recreated activity still lands under the basename it asked for.
            String pick = savedInstanceState.getString(STATE_PENDING_PICK);
            if (pick != null) pendingPickFilename = pick;
            String pickDir = savedInstanceState.getString(STATE_PENDING_PICK_DIR);
            if (pickDir != null) pendingPickSaveDir = pickDir;
            String create = savedInstanceState.getString(STATE_PENDING_CREATE);
            if (create != null) pendingCreateSuggestedName = create;
        }
        metrics = getResources().getDisplayMetrics();

        // Set low-latency audio values
        nativeSetDefaultStreamValues(getAudioFreq(), getAudioSMP());

        if (android.os.Build.VERSION.SDK_INT >= 28) {
            getWindow().getAttributes().layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER;
            shortEdgesMode = false;
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        Log.d("GameActivity", "onNewIntent() with " + intent);
        Uri launchURI = getLaunchURI(intent);
        if (launchURI != null) {
            nativeOnLaunchURI(launchURI.toString());
        } else if (intent != null && intent.hasExtra("game")) {
            String game = intent.getStringExtra("game");
            if (game != null && !game.isEmpty()) {
                nativeOnGameIntent(game);
            }
        }
        if (!embed && launchURI == null) {
            handleIntent(intent);
            resetNative();
            startNative();
        }
    }

    private static Uri getLaunchURI(Intent intent) {
        if (intent == null) return null;
        Uri uri = intent.getData();
        if (uri == null) return null;
        String scheme = uri.getScheme();
        String host = uri.getHost();
        if (scheme == null || host == null) return null;
        if (!"gen1recomp++".equalsIgnoreCase(scheme)) return null;
        if (!"launch".equalsIgnoreCase(host)) return null;
        return uri;
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
        secondaryHostResumed = false;
        if (vibrator != null) {
            Log.d("GameActivity", "Cancelling vibration");
            vibrator.cancel();
        }
        unregisterSecondaryDisplayListener();
        teardownSecondaryDisplay();
        secondaryEnabled = false;
        synchronized (secondaryFrameLock) { secondaryFrame = null; }
        unregisterAudioDeviceCallback();
        abandonAudioFocus();
        onHostDestroy();
        super.onDestroy();
    }

    @Override
    protected void onPause() {
        secondaryHostResumed = false;
        if (vibrator != null) {
            Log.d("GameActivity", "Cancelling vibration");
            vibrator.cancel();
        }
        unregisterSecondaryDisplayListener();
        teardownSecondaryDisplay();
        unregisterAudioDeviceCallback();
        abandonAudioFocus();
        onHostPause();
        super.onPause();
    }

    @Override
    public void onResume() {
        super.onResume();
        secondaryHostResumed = true;
        onHostResume();
        requestGameAudioFocus();
        registerAudioDeviceCallback();
        refreshDualScreenDisplayMode();
        if (secondaryEnabled) registerSecondaryDisplayListener();
        setupSecondaryDisplay();
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        // AYN's panel toggle emits virtual Right Shift, which SDL maps to a
        // gameplay button. The setting is absent on other Android devices.
        if (secondaryEnabled && dualScreenDisplayMode != -1
                && event.getKeyCode() == KeyEvent.KEYCODE_SHIFT_RIGHT
                && event.getDeviceId() == KeyCharacterMap.VIRTUAL_KEYBOARD) {
            return true;
        }
        return super.dispatchKeyEvent(event);
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
     * is. The picked file (if any) arrives later in onActivityResult, not
     * synchronously here.
     *
     * API 21+ uses ACTION_OPEN_DOCUMENT; API 16-20 and television devices use
     * an ACTION_GET_CONTENT chooser instead. Below 19 OPEN_DOCUMENT does not
     * exist, and on 19/20 the stock DocumentsUI is unreliable -- it launches
     * and then hands back RESULT_CANCELED with no data, which onActivityResult
     * cannot tell apart from the player cancelling (#584); Android TV ships no
     * DocumentsUI at all and behaves the same way (#1535). GET_CONTENT lets any
     * installed file manager serve the pick, and both intents return the same
     * content:// or file:// URI shapes, so the result path in onActivityResult
     * stays picker-agnostic and unchanged.
     *
     * @param destFilename basename under the app save identity (e.g.
     *                     picked_rom.gb, picked_mod.zip, picked_save.sav, or
     *                     picked_required_import.bin)
     */
    private static boolean isTelevision(Context context) {
        if (context == null) return false;
        try {
            UiModeManager modes =
                (UiModeManager) context.getSystemService(Context.UI_MODE_SERVICE);
            if (modes != null
                    && modes.getCurrentModeType() == Configuration.UI_MODE_TYPE_TELEVISION) {
                return true;
            }
        } catch (Exception e) {
            Log.d("GameActivity", "could not read ui mode: " + e.getMessage());
        }
        PackageManager packages = context.getPackageManager();
        return packages != null
            && packages.hasSystemFeature(PackageManager.FEATURE_LEANBACK);
    }

    private static boolean isDirectRequiredDestination(String relative) {
        if (relative == null || relative.length() == 0 || relative.startsWith("/")) return false;
        String normalized = relative.replace('\\', '/');
        if (!normalized.startsWith("mods/")) return false;
        int marker = normalized.indexOf("/baseroms/");
        if (marker <= "mods/".length() || marker + "/baseroms/".length() >= normalized.length()) {
            return false;
        }
        return !normalized.contains("//")
            && !normalized.equals("..")
            && !normalized.startsWith("../")
            && !normalized.contains("/../")
            && !normalized.endsWith("/..");
    }

    /** Legacy single-argument entry; resolves the save dir itself. */
    @Keep
    public static boolean showFilePicker(String destFilename) {
        return showFilePicker(destFilename, null);
    }

    @Keep
    public static boolean showFilePicker(String destFilename, String saveDir) {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (destFilename == null || destFilename.length() == 0) {
            destFilename = PICKED_ROM_FILENAME;
        }
        // Remember where LOVE's filesystem is really mounted so
        // onActivityResult copies the pick there, not into a recomputed
        // (possibly different-volume) root (#604, #839).
        self.pendingPickSaveDir = (saveDir != null) ? saveDir : "";
        // Basename destinations keep the historical ROM/mod/save staging path.
        // A nested destination is accepted only for an engine-generated mod
        // baseroms path, then canonicalized beneath LOVE's mounted save root.
        String normalizedDest = destFilename.replace('\\', '/');
        boolean nested = normalizedDest.indexOf('/') >= 0;
        if (nested && !isDirectRequiredDestination(normalizedDest)) {
            Log.d("GameActivity", "refusing non-baseroms picker dest: " + destFilename);
            return false;
        }
        try {
            File rootCanonical = self.saveIdentityDir().getCanonicalFile();
            File destCanonical = new File(rootCanonical, normalizedDest).getCanonicalFile();
            String rootPrefix = rootCanonical.getPath() + File.separator;
            if (destCanonical.equals(rootCanonical)
                    || !destCanonical.getPath().startsWith(rootPrefix)) {
                Log.d("GameActivity", "refusing unsafe picker dest: " + destFilename);
                return false;
            }
        } catch (IOException e) {
            Log.d("GameActivity", "could not validate picker dest: " + e.getMessage());
            return false;
        }

        self.pendingPickFilename = normalizedDest;
        if (android.os.Build.VERSION.SDK_INT >= 21 && !isTelevision(self)) {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("*/*");
            // The Storage Access Framework grants the returned content URI
            // directly to this activity. Request the read grant explicitly as
            // well: Android 13's scoped storage deliberately does not expose
            // arbitrary paths or require broad media/storage permissions.
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            try {
                self.startActivityForResult(intent, FILE_PICKER_REQUEST_CODE);
                return true;
            } catch (Exception e) {
                // Some OEM / TV builds ship without DocumentsUI; fall through
                // to the GET_CONTENT chooser below instead of giving up (#584).
                Log.d("GameActivity", "could not open document picker: " + e.getMessage());
            }
        }
        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            self.startActivityForResult(
                Intent.createChooser(intent, "Choose a file"),
                FILE_PICKER_REQUEST_CODE);
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

    /** Required-mod-file wrapper used by love.system.pickFile("required_import"). */
    @Keep
    public static boolean showRequiredImportFilePicker() {
        return showFilePicker(PICKED_REQUIRED_IMPORT_FILENAME);
    }

    /**
     * Relaunches the whole app for love.system.restartApp, used by
     * src/core/HostShell.lua when a mod toggle needs a cold boot (#575).
     * love.event.quit("restart") re-runs LOVE's boot inside the same
     * process, and the second love.filesystem.init throws once physfs
     * failed to deinit ("already initialized"), killing the app. Instead
     * we hand our launch intent to AlarmManager and then exit the process:
     * the alarm lives in system_server, so it survives our death and
     * cannot race the exit the way a plain startActivity right before
     * Runtime.exit can on some OEMs, and the dead process guarantees no
     * native (physfs / SDL / JNI) state leaks into the fresh run.
     */
    @Keep
    public static boolean restartApp() {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        try {
            Context context = self.getApplicationContext();
            Intent intent = context.getPackageManager()
                .getLaunchIntentForPackage(context.getPackageName());
            if (intent == null) return false;
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
            int pendingFlags = PendingIntent.FLAG_CANCEL_CURRENT;
            if (android.os.Build.VERSION.SDK_INT >= 23) {
                // Mandatory mutability flag on API 31+; harmless from 23 up.
                pendingFlags |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent pending = PendingIntent.getActivity(
                context, RESTART_REQUEST_CODE, intent, pendingFlags);
            AlarmManager alarm = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
            if (alarm == null) return false;
            alarm.set(AlarmManager.RTC, System.currentTimeMillis() + 250, pending);
        } catch (Exception e) {
            Log.d("GameActivity", "could not schedule restart: " + e.getMessage());
            return false;
        }
        Runtime.getRuntime().exit(0);
        return true; // unreachable, but keeps the JNI signature honest
    }

    /**
     * Stages a verified release APK in cache and asks Android's Package
     * Installer to update this package. This never silently installs an APK:
     * the platform owns both the unknown-sources consent and final install
     * confirmation. `updateRoot` comes from the native save directory and is
     * checked before any file is read, so a Lua caller cannot turn this into a
     * general-purpose local-file sharing bridge.
     */
    @Keep
    public static boolean installApk(final String sourcePath, final String updateRoot) {
        final GameActivity self = (GameActivity) mSingleton;
        if (self == null || sourcePath == null || updateRoot == null) return false;
        final File source;
        try {
            source = new File(sourcePath).getCanonicalFile();
            File root = new File(updateRoot, "updates").getCanonicalFile();
            String rootPath = root.getPath() + File.separator;
            if (!source.getPath().startsWith(rootPath)
                    || !source.isFile() || source.length() == 0
                    || !source.getName().matches("gen1recomp-[0-9]+\\.[0-9]+\\.[0-9]+-android\\.apk")) {
                return false;
            }
        } catch (IOException e) {
            Log.d("GameActivity", "invalid update APK path: " + e.getMessage());
            return false;
        }

        // Android 8+ lets the user decide whether this app is trusted to
        // request package installs. Send them to the per-app setting first;
        // they deliberately tap Install again after granting it.
        if (android.os.Build.VERSION.SDK_INT >= 26
                && !self.getPackageManager().canRequestPackageInstalls()) {
            try {
                Intent settings = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + self.getPackageName()));
                self.startActivity(settings);
                return true;
            } catch (Exception e) {
                Log.d("GameActivity", "could not open install-source settings: " + e.getMessage());
                return false;
            }
        }

        // Copying an APK can be large; keep both I/O and checksum-verified
        // source access off the UI thread. The FileProvider exposes this cache
        // child only after it has been fully written and renamed.
        new Thread(new Runnable() {
            @Override public void run() {
                File stagedDir = new File(self.getCacheDir(), "full-update");
                File partial = new File(stagedDir, "update.apk.part");
                File staged = new File(stagedDir, "update.apk");
                try {
                    if (!stagedDir.exists() && !stagedDir.mkdirs()) return;
                    copyFile(source, partial);
                    if (staged.exists() && !staged.delete()) return;
                    if (!partial.renameTo(staged)) return;
                    self.runOnUiThread(new Runnable() {
                        @Override public void run() { launchPackageInstaller(self, staged); }
                    });
                } catch (Exception e) {
                    Log.d("GameActivity", "could not stage update APK: " + e.getMessage());
                } finally {
                    if (partial.exists()) partial.delete();
                }
            }
        }, "gen1recomp-apk-stage").start();
        return true;
    }

    private static void copyFile(File source, File destination) throws IOException {
        InputStream in = new BufferedInputStream(new FileInputStream(source));
        OutputStream out = new BufferedOutputStream(new FileOutputStream(destination));
        try {
            byte[] buffer = new byte[32768];
            int count;
            while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
        } finally {
            try { out.close(); } catch (IOException ignored) {}
            try { in.close(); } catch (IOException ignored) {}
        }
    }

    private static void launchPackageInstaller(GameActivity activity, File apk) {
        try {
            Context context = activity.getApplicationContext();
            Uri uri = FileProvider.getUriForFile(context,
                context.getPackageName() + ".full_update_provider", apk);
            Intent install = new Intent(Intent.ACTION_INSTALL_PACKAGE);
            install.setData(uri);
            install.setClipData(ClipData.newRawUri("apk", uri));
            install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            activity.startActivity(install);
        } catch (Exception e) {
            Log.d("GameActivity", "could not open package installer: " + e.getMessage());
        }
    }

    @Keep
    public static String getLaunchGame() {
        return initialGame != null ? initialGame : "";
    }

    @Keep
    public static String getLaunchURI() {
        return initialLaunchURI != null ? initialLaunchURI : "";
    }

    @Keep
    public static boolean updateAppShortcuts(String[] readyVersions) {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (android.os.Build.VERSION.SDK_INT < 25) return false;
        try {
            Context context = self.getApplicationContext();
            ShortcutManager shortcutManager = context.getSystemService(ShortcutManager.class);
            if (shortcutManager == null) return false;

            if (readyVersions == null || readyVersions.length == 0) {
                shortcutManager.removeAllDynamicShortcuts();
                return true;
            }

            List<ShortcutInfo> shortcuts = new ArrayList<>();
            int maxShortcuts = Math.min(readyVersions.length, 4);

            for (int i = 0; i < maxShortcuts; i++) {
                String ver = readyVersions[i];
                if (ver == null || ver.isEmpty()) continue;
                String lower = ver.toLowerCase();
                String shortLabel;
                String longLabel;
                int iconResId;

                switch (lower) {
                    case "red":
                        shortLabel = "Play Red";
                        longLabel = "Play Red";
                        iconResId = context.getResources().getIdentifier("ic_shortcut_red", "drawable", context.getPackageName());
                        break;
                    case "blue":
                        shortLabel = "Play Blue";
                        longLabel = "Play Blue";
                        iconResId = context.getResources().getIdentifier("ic_shortcut_blue", "drawable", context.getPackageName());
                        break;
                    case "yellow":
                        shortLabel = "Play Yellow";
                        longLabel = "Play Yellow";
                        iconResId = context.getResources().getIdentifier("ic_shortcut_yellow", "drawable", context.getPackageName());
                        break;
                    case "gold":
                        shortLabel = "Play Gold";
                        longLabel = "Play Gold";
                        iconResId = context.getResources().getIdentifier("ic_shortcut_gold", "drawable", context.getPackageName());
                        break;
                    default:
                        String capitalized = lower.substring(0, 1).toUpperCase() + lower.substring(1);
                        shortLabel = "Play " + capitalized;
                        longLabel = "Play " + capitalized;
                        iconResId = context.getResources().getIdentifier("ic_shortcut_" + lower, "drawable", context.getPackageName());
                        break;
                }

                if (iconResId == 0) {
                    iconResId = context.getResources().getIdentifier("ic_launcher_foreground", "drawable", context.getPackageName());
                }

                Intent intent = new Intent(context, GameActivity.class);
                intent.setAction(Intent.ACTION_VIEW);
                intent.putExtra("game", lower);
                intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);

                ShortcutInfo.Builder builder = new ShortcutInfo.Builder(context, "shortcut_" + lower)
                    .setShortLabel(shortLabel)
                    .setLongLabel(longLabel)
                    .setIntent(intent);

                if (iconResId != 0) {
                    builder.setIcon(Icon.createWithResource(context, iconResId));
                }

                shortcuts.add(builder.build());
            }

            shortcutManager.setDynamicShortcuts(shortcuts);
            return true;
        } catch (Exception e) {
            Log.d("GameActivity", "could not update shortcuts: " + e.getMessage());
            return false;
        }
    }

    /**
     * Blocking HTTPS GET into destPath, exposed as love.system.httpDownload
     * and used by src/core/HostShell.lua. Android ships no curl binary, so
     * every remote fetch the desktop builds do with curl (mod index feeds,
     * mod release lists, mod zips, thumbnails) comes through here (#597).
     * Runs on LOVE's Lua thread, never the UI thread, so the platform's
     * network-on-main-thread rule is not in play and a blocking call matches
     * the curl semantics the Lua callers already expect.
     *
     * Redirects are followed by hand because HttpURLConnection silently drops
     * a redirect that changes protocol, and only https is accepted: the feeds
     * live on GitHub Pages / raw and a downgrade to http must fail, not fetch.
     * The body lands in a .part file and is renamed only once complete, so a
     * dropped connection can never leave a half file the caller trusts.
     */
    /**
     * TLS client sockets, exposed as love.system.tls* and used by the
     * Archipelago mod for wss:// rooms. LuaSocket speaks TCP only, so without
     * these a hosted room -- every one of which is TLS-only -- is unreachable
     * from the game. The work is in TlsSocket; these are the static entry
     * points, because the JNI side resolves methods on the activity's own
     * class (see love/src/common/android.cpp) and cannot see other classes
     * from a worker thread.
     */
    @Keep
    public static int tlsOpen(String host, int port) {
        return TlsSocket.open(host, port);
    }

    @Keep
    public static int tlsStatus(int handle) {
        return TlsSocket.status(handle);
    }

    @Keep
    public static int tlsSend(int handle, byte[] data) {
        return TlsSocket.send(handle, data);
    }

    @Keep
    public static byte[] tlsReceive(int handle, int max) {
        return TlsSocket.receive(handle, max);
    }

    @Keep
    public static String tlsError(int handle) {
        return TlsSocket.error(handle);
    }

    @Keep
    public static void tlsClose(int handle) {
        TlsSocket.close(handle);
    }

    @Keep
    public static boolean httpDownload(String url, String destPath, String userAgent, String accept) {
        if (url == null || destPath == null) return false;
        HttpURLConnection conn = null;
        File tmp = new File(destPath + ".part");
        try {
            String current = url;
            for (int hop = 0; hop < 5; hop++) {
                URL parsed = new URL(current);
                if (!"https".equalsIgnoreCase(parsed.getProtocol())) return false;
                conn = (HttpURLConnection) parsed.openConnection();
                conn.setInstanceFollowRedirects(false);
                conn.setConnectTimeout(15000);
                conn.setReadTimeout(60000);
                conn.setRequestProperty("User-Agent",
                    userAgent == null ? "gen1recomp" : userAgent);
                if (accept != null) conn.setRequestProperty("Accept", accept);
                int code = conn.getResponseCode();
                if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
                    String next = conn.getHeaderField("Location");
                    conn.disconnect();
                    conn = null;
                    if (next == null) return false;
                    current = new URL(parsed, next).toString();
                    continue;
                }
                if (code < 200 || code > 299) return false;
                InputStream in = new BufferedInputStream(conn.getInputStream());
                OutputStream out = new BufferedOutputStream(new FileOutputStream(tmp));
                try {
                    byte[] buf = new byte[16384];
                    int n;
                    while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                } finally {
                    try { out.close(); } catch (IOException ignored) {}
                    try { in.close(); } catch (IOException ignored) {}
                }
                File dest = new File(destPath);
                dest.delete();
                if (!tmp.renameTo(dest)) return false;
                return dest.length() > 0;
            }
            return false;
        } catch (Exception e) {
            Log.d("GameActivity", "httpDownload failed: " + e.getMessage());
            return false;
        } finally {
            if (conn != null) conn.disconnect();
            if (tmp.exists()) tmp.delete();
        }
    }

    /**
     * Blocking HTTPS POST, exposed as love.system.httpPost and used by
     * src/core/HostShell.lua for mod.postLog. The GET bridge above covers
     * downloads; log sends need POST, and Android ships no curl, so this is
     * the only POST transport the platform has. Strictly one-way, matching
     * the curl branch it mirrors: the response body is drained and
     * discarded, and only the 2xx verdict comes back.
     *
     * Same rules as httpDownload: https only, redirects followed by hand
     * (re-POSTing the body on each hop, the way curl -X POST behaves), and
     * the call is blocking on the Lua/worker thread -- never the UI thread.
     * The body arrives as raw bytes (a jbyteArray across the JNI) because a
     * log ring can carry arbitrary UTF-8; a String would risk modified-UTF-8
     * corruption on characters outside the BMP.
     */
    @Keep
    public static boolean httpPost(String url, byte[] body, String contentType, String userAgent) {
        if (url == null || body == null) return false;
        HttpURLConnection conn = null;
        try {
            String current = url;
            for (int hop = 0; hop < 5; hop++) {
                URL parsed = new URL(current);
                if (!"https".equalsIgnoreCase(parsed.getProtocol())) return false;
                conn = (HttpURLConnection) parsed.openConnection();
                conn.setInstanceFollowRedirects(false);
                conn.setConnectTimeout(15000);
                conn.setReadTimeout(60000);
                conn.setRequestMethod("POST");
                conn.setDoOutput(true);
                conn.setRequestProperty("User-Agent",
                    userAgent == null ? "gen1recomp" : userAgent);
                conn.setRequestProperty("Content-Type",
                    contentType == null ? "text/plain" : contentType);
                OutputStream out = new BufferedOutputStream(conn.getOutputStream());
                try {
                    out.write(body);
                } finally {
                    try { out.close(); } catch (IOException ignored) {}
                }
                int code = conn.getResponseCode();
                if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
                    String next = conn.getHeaderField("Location");
                    conn.disconnect();
                    conn = null;
                    if (next == null) return false;
                    current = new URL(parsed, next).toString();
                    continue;
                }
                if (code < 200 || code > 299) return false;
                // drain and discard, so a slow server cannot wedge the
                // worker on a full socket buffer
                InputStream in = new BufferedInputStream(conn.getInputStream());
                try {
                    byte[] buf = new byte[16384];
                    while (in.read(buf) > 0) {}
                } finally {
                    try { in.close(); } catch (IOException ignored) {}
                }
                return true;
            }
            return false;
        } catch (Exception e) {
            Log.d("GameActivity", "httpPost failed: " + e.getMessage());
            return false;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    /** Response ceiling for httpRequest; anything larger is refused, not buffered. */
    private static final int HTTP_REQUEST_MAX_RESPONSE = 4 * 1024 * 1024;

    /** Builds an httpRequest envelope: one head line, a newline, then the body. */
    private static byte[] httpEnvelope(String head, byte[] payload) {
        byte[] prefix;
        try {
            prefix = (head + "\n").getBytes("UTF-8");
        } catch (Exception e) {
            prefix = (head + "\n").getBytes();
        }
        if (payload == null || payload.length == 0) return prefix;
        byte[] out = new byte[prefix.length + payload.length];
        System.arraycopy(prefix, 0, out, 0, prefix.length);
        System.arraycopy(payload, 0, out, prefix.length, payload.length);
        return out;
    }

    /** One-line, CR/LF-free failure text, so an envelope head stays one line. */
    private static String httpErrorText(Exception e) {
        String text = e.getMessage();
        if (text == null || text.length() == 0) text = e.getClass().getSimpleName();
        text = text.replace('\r', ' ').replace('\n', ' ');
        if (text.length() > 160) text = text.substring(0, 160);
        return text;
    }

    /**
     * Blocking HTTPS request with a chosen method, headers and byte body,
     * exposed as love.system.httpRequest and used by src/core/HostShell.lua
     * for save sync. Sync needs PUT, per-request auth headers and the response
     * body of a 4xx as well as a 2xx (a conflict answers 409 with the save
     * that won), none of which httpDownload or httpPost above can express.
     *
     * Same rules as those two: https only, redirects followed by hand
     * (re-sending method and body on each hop), 15s connect / 60s read, and
     * blocking on the Lua/worker thread -- never the UI thread. Headers arrive
     * as a flat name, value array; a field carrying CR or LF is refused rather
     * than sent, so a header value can never inject a second header.
     *
     * The reply is an envelope: a head line of "STATUS &lt;code&gt;" or
     * "ERROR &lt;text&gt;", a newline, then the raw response bytes.
     */
    @Keep
    public static byte[] httpRequest(String url, String method, String[] headerPairs,
                                     byte[] body, String userAgent) {
        if (url == null) return httpEnvelope("ERROR missing url", null);
        String verb = method == null ? "GET" : method.toUpperCase(Locale.US);
        if (!"GET".equals(verb) && !"POST".equals(verb)
                && !"PUT".equals(verb) && !"DELETE".equals(verb)) {
            return httpEnvelope("ERROR unsupported request method", null);
        }
        if (headerPairs != null) {
            if ((headerPairs.length % 2) != 0) {
                return httpEnvelope("ERROR bad request header", null);
            }
            for (int i = 0; i < headerPairs.length; i++) {
                String field = headerPairs[i];
                if (field == null) return httpEnvelope("ERROR bad request header", null);
                if (field.indexOf('\r') >= 0 || field.indexOf('\n') >= 0) {
                    return httpEnvelope("ERROR bad request header", null);
                }
                if ((i % 2) == 0 && field.length() == 0) {
                    return httpEnvelope("ERROR bad request header", null);
                }
            }
        }
        HttpURLConnection conn = null;
        try {
            String current = url;
            for (int hop = 0; hop < 5; hop++) {
                URL parsed = new URL(current);
                if (!"https".equalsIgnoreCase(parsed.getProtocol())) {
                    return httpEnvelope("ERROR https only", null);
                }
                conn = (HttpURLConnection) parsed.openConnection();
                conn.setInstanceFollowRedirects(false);
                conn.setConnectTimeout(15000);
                conn.setReadTimeout(60000);
                conn.setRequestMethod(verb);
                conn.setRequestProperty("User-Agent",
                    userAgent == null ? "gen1recomp" : userAgent);
                if (headerPairs != null) {
                    for (int i = 0; i + 1 < headerPairs.length; i += 2) {
                        conn.setRequestProperty(headerPairs[i], headerPairs[i + 1]);
                    }
                }
                if (body != null && !"GET".equals(verb)) {
                    conn.setDoOutput(true);
                    conn.setFixedLengthStreamingMode(body.length);
                    OutputStream out = new BufferedOutputStream(conn.getOutputStream());
                    try {
                        out.write(body);
                    } finally {
                        try { out.close(); } catch (IOException ignored) {}
                    }
                }
                int code = conn.getResponseCode();
                if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
                    String next = conn.getHeaderField("Location");
                    conn.disconnect();
                    conn = null;
                    if (next == null) {
                        return httpEnvelope("ERROR redirect without a location", null);
                    }
                    current = new URL(parsed, next).toString();
                    continue;
                }
                // A rejection's body is the diagnosis the caller wants, so 4xx
                // and 5xx are read through getErrorStream rather than dropped.
                InputStream in;
                try {
                    in = conn.getInputStream();
                } catch (IOException e) {
                    in = conn.getErrorStream();
                }
                ByteArrayOutputStream sink = new ByteArrayOutputStream();
                if (in != null) {
                    InputStream reader = new BufferedInputStream(in);
                    try {
                        byte[] buf = new byte[16384];
                        int n;
                        while ((n = reader.read(buf)) > 0) {
                            if (sink.size() + n > HTTP_REQUEST_MAX_RESPONSE) {
                                return httpEnvelope("ERROR the reply was too large", null);
                            }
                            sink.write(buf, 0, n);
                        }
                    } finally {
                        try { reader.close(); } catch (IOException ignored) {}
                    }
                }
                return httpEnvelope("STATUS " + code, sink.toByteArray());
            }
            return httpEnvelope("ERROR too many redirects", null);
        } catch (Exception e) {
            Log.d("GameActivity", "httpRequest failed: " + e.getMessage());
            return httpEnvelope("ERROR " + httpErrorText(e), null);
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    /**
     * Shows ACTION_CREATE_DOCUMENT so the player can save a staged export
     * (pending_export.sav in the app save identity) to Downloads / Drive /
     * etc. Suggested name is the dialog's default filename.
     *
     * CREATE_DOCUMENT does not exist below API 19 and has no pre-SAF
     * equivalent, so unlike showFilePicker this stays 19+ (#584); the false
     * return degrades on the Lua side (RomImporter export) to "Exported
     * inside the app folder", which is the correct pre-KitKat behavior.
     */
    /** Legacy single-argument entry; resolves the save dir itself. */
    @Keep
    public static boolean showCreateDocument(String suggestedName) {
        return showCreateDocument(suggestedName, null);
    }

    @Keep
    public static boolean showCreateDocument(String suggestedName, String saveDir) {
        if (android.os.Build.VERSION.SDK_INT < 19) return false;
        // (see showFilePicker for why the import side got a pre-19 path)
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (suggestedName == null || suggestedName.length() == 0) {
            suggestedName = "export.sav";
        }
        if (suggestedName.indexOf('/') >= 0 || suggestedName.indexOf('\\') >= 0) {
            Log.d("GameActivity", "refusing unsafe create name: " + suggestedName);
            return false;
        }
        // Route through the mounted save dir (#604, #839): Lua staged
        // pending_export.sav where physfs writes, which is not necessarily
        // where a fresh getExternalFilesDir(null) points on merged /
        // adopted-SD storage.
        self.pendingPickSaveDir = (saveDir != null) ? saveDir : "";
        File source = new File(self.saveIdentityDir(), PENDING_EXPORT_FILENAME);
        if (!source.isFile()) {
            Log.d("GameActivity", "no pending export at " + source);
            return false;
        }

        self.pendingCreateSuggestedName = suggestedName;
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        // PNG exports (diploma / dex prints) should open as images so the
        // picker offers Photos / Gallery, not only generic "Documents".
        String mime = "application/octet-stream";
        String lower = suggestedName.toLowerCase(Locale.US);
        if (lower.endsWith(".png")) mime = "image/png";
        else if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) mime = "image/jpeg";
        intent.setType(mime);
        intent.putExtra(Intent.EXTRA_TITLE, suggestedName);
        try {
            self.startActivityForResult(intent, FILE_CREATE_REQUEST_CODE);
            return true;
        } catch (Exception e) {
            Log.d("GameActivity", "could not open create-document picker: " + e.getMessage());
            return false;
        }
    }

    /**
     * Copy a PNG/JPEG already written under the LOVE save identity (e.g.
     * prints/diploma_….png) into the public Pictures/Gen1Recomp album and
     * media-scan the in-app copy so USB / file managers can see it (#2103).
     * No picker: diploma / dex print should not interrupt the game.
     */
    @Keep
    public static boolean exportImageToGallery(String relativePath, String saveDir) {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (relativePath == null || relativePath.length() == 0) return false;
        if (relativePath.indexOf("..") >= 0) {
            Log.d("GameActivity", "refusing unsafe export path: " + relativePath);
            return false;
        }
        self.pendingPickSaveDir = (saveDir != null) ? saveDir : "";
        File source = new File(self.saveIdentityDir(), relativePath);
        if (!source.isFile()) {
            Log.d("GameActivity", "exportImage missing at " + source);
            return false;
        }
        String name = source.getName();
        String lower = name.toLowerCase(Locale.US);
        String mime = "image/png";
        if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) mime = "image/jpeg";
        else if (!lower.endsWith(".png")) {
            Log.d("GameActivity", "exportImage refusing non-image: " + name);
            return false;
        }

        // Make the app-private prints/ copy visible over MTP / file managers.
        MediaScannerConnection.scanFile(self,
            new String[]{ source.getAbsolutePath() },
            new String[]{ mime },
            null);

        try {
            if (Build.VERSION.SDK_INT >= 29) {
                ContentResolver resolver = self.getContentResolver();
                ContentValues values = new ContentValues();
                values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
                values.put(MediaStore.MediaColumns.MIME_TYPE, mime);
                values.put(MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_PICTURES + "/Gen1Recomp");
                values.put(MediaStore.MediaColumns.IS_PENDING, 1);
                Uri collection = MediaStore.Images.Media
                    .getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);
                Uri uri = resolver.insert(collection, values);
                if (uri == null) {
                    Log.d("GameActivity", "MediaStore insert returned null");
                    return false;
                }
                OutputStream out = resolver.openOutputStream(uri);
                if (out == null) {
                    resolver.delete(uri, null, null);
                    return false;
                }
                try {
                    copyStream(new FileInputStream(source), out);
                } finally {
                    out.close();
                }
                values.clear();
                values.put(MediaStore.MediaColumns.IS_PENDING, 0);
                resolver.update(uri, values, null, null);
                return true;
            }

            // Pre-Q: write into public Pictures and ask the scanner to index it.
            File pictures = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_PICTURES);
            File album = new File(pictures, "Gen1Recomp");
            if (!album.exists() && !album.mkdirs()) {
                Log.d("GameActivity", "could not create " + album);
                return false;
            }
            File dest = new File(album, name);
            copyFileToFile(source, dest);
            MediaScannerConnection.scanFile(self,
                new String[]{ dest.getAbsolutePath() },
                new String[]{ mime },
                null);
            return true;
        } catch (Exception e) {
            Log.d("GameActivity", "exportImage failed: " + e.getMessage());
            return false;
        }
    }

    private static void copyStream(InputStream in, OutputStream out) throws IOException {
        try {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) >= 0) {
                if (n > 0) out.write(buf, 0, n);
            }
        } finally {
            try { in.close(); } catch (IOException ignored) {}
        }
    }

    private static void copyFileToFile(File source, File dest) throws IOException {
        FileOutputStream out = new FileOutputStream(dest);
        try {
            copyStream(new FileInputStream(source), out);
        } finally {
            out.close();
        }
    }

    private File saveIdentityDir() {
        // Prefer the mounted save dir the last bridge call reported: the
        // recomputation below can name a different volume than the one LOVE
        // mounted on merged / adopted-SD storage (#604, #839).
        if (pendingPickSaveDir != null && pendingPickSaveDir.length() > 0) {
            return new File(pendingPickSaveDir);
        }
        File ext = getExternalFilesDir(null);
        if (ext == null) {
            // Shared storage unavailable (ejected / mid-adoption): without
            // this guard File(null, "save") silently built the RELATIVE
            // path save/<identity>, mkdirs() failed against "/", and the
            // pick was dropped with no message at all (#604).
            ext = getFilesDir();
        }
        return new File(new File(ext, "save"), ROM_SAVE_IDENTITY);
    }

    /** Drops a small flag file in the save identity for Lua to consume on focus. */
    private void writeSaveDirFlag(String name, String body) {
        writeFlagFile(saveIdentityDir(), name, body);
    }

    /**
     * Step sync, called from Lua as love.system.syncHealthSteps()
     * (see modules/system/wrap_System.cpp). Asynchronous like the picker:
     * returns whether a sync could be started; the result lands later as
     * steps_pending.json in the save identity dir, where the Pokéwalker
     * mod's poll consumes it.
     *
     * Android 10+ gates the step counter behind the ACTIVITY_RECOGNITION
     * runtime permission; the first call shows the system prompt and a later
     * sync (the mod retries on save load / option change) delivers.
     */
    @Keep
    public static boolean syncHealthSteps() {
        final GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (android.os.Build.VERSION.SDK_INT >= 29
                && ActivityCompat.checkSelfPermission(self,
                    Manifest.permission.ACTIVITY_RECOGNITION)
                    != PackageManager.PERMISSION_GRANTED) {
            self.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    ActivityCompat.requestPermissions(self,
                        new String[]{Manifest.permission.ACTIVITY_RECOGNITION},
                        STEP_PERMISSION_REQUEST_CODE);
                }
            });
            return true;
        }
        self.startStepSensorRead();
        return true;
    }

    /**
     * One-shot read of the cumulative hardware step counter. The sensor
     * usually reports its cached value moments after registration; some
     * devices hold the event until the next physical step, so the listener
     * is given 20 seconds before being torn down (the next sync retries).
     */
    private void startStepSensorRead() {
        final SensorManager manager =
            (SensorManager) getSystemService(Context.SENSOR_SERVICE);
        if (manager == null) return;
        Sensor counter = manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER);
        if (counter == null) {
            Log.d("GameActivity", "no step counter sensor on this device");
            return;
        }
        final SensorEventListener listener = new SensorEventListener() {
            private boolean delivered = false;

            @Override
            public void onSensorChanged(SensorEvent event) {
                if (delivered || event.values.length == 0) return;
                delivered = true;
                manager.unregisterListener(this);
                deliverSteps((long) event.values[0]);
            }

            @Override
            public void onAccuracyChanged(Sensor sensor, int accuracy) {
            }
        };
        if (!manager.registerListener(listener, counter,
                SensorManager.SENSOR_DELAY_NORMAL)) {
            Log.d("GameActivity", "step counter listener registration failed");
            return;
        }
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override
            public void run() {
                // No-op if the listener already delivered and unregistered.
                manager.unregisterListener(listener);
            }
        }, 20000);
    }

    /**
     * Convert a cumulative counter reading into pending steps. The counter
     * resets to zero on reboot: a reading below the stored anchor re-anchors
     * without crediting (steps walked between the reboot and this sync are
     * lost, which errs on the honest side).
     */
    private void deliverSteps(long counterNow) {
        SharedPreferences prefs = getSharedPreferences(STEP_PREFS, MODE_PRIVATE);
        long anchor = prefs.getLong(STEP_PREF_ANCHOR, -1);
        long now = System.currentTimeMillis();
        if (anchor < 0 || counterNow < anchor) {
            prefs.edit()
                .putLong(STEP_PREF_ANCHOR, counterNow)
                .putLong(STEP_PREF_ANCHOR_WALLTIME, now)
                .apply();
            Log.d("GameActivity", "step anchor set at " + counterNow);
            return;
        }
        long steps = Math.min(counterNow - anchor, STEP_MAX_PER_SYNC);
        long fromWalltime = prefs.getLong(STEP_PREF_ANCHOR_WALLTIME, now);
        if (steps <= 0) return;
        prefs.edit()
            .putLong(STEP_PREF_ANCHOR, counterNow)
            .putLong(STEP_PREF_ANCHOR_WALLTIME, now)
            .apply();

        File dir = saveIdentityDir();
        if (!dir.isDirectory() && !dir.mkdirs()) {
            Log.d("GameActivity", "cannot create save dir for steps: " + dir);
            return;
        }
        File pending = new File(dir, PENDING_STEPS_FILENAME);
        long total = steps;
        // Merge with an unconsumed earlier delivery so steps are never lost
        // (same contract as the iOS bridge).
        if (pending.isFile()) {
            try {
                byte[] raw = new byte[(int) Math.min(pending.length(), 4096)];
                FileInputStream in = new FileInputStream(pending);
                int read = in.read(raw);
                in.close();
                if (read > 0) {
                    org.json.JSONObject old =
                        new org.json.JSONObject(new String(raw, 0, read, "UTF-8"));
                    total += Math.max(0, old.optLong("steps", 0));
                }
            } catch (Exception e) {
                Log.d("GameActivity", "ignoring unreadable pending steps: " + e);
            }
        }
        try {
            org.json.JSONObject payload = new org.json.JSONObject();
            payload.put("steps", total);
            payload.put("from", isoTime(fromWalltime));
            payload.put("to", isoTime(now));
            File tmp = new File(dir, PENDING_STEPS_FILENAME + ".tmp");
            FileOutputStream out = new FileOutputStream(tmp);
            out.write(payload.toString().getBytes("UTF-8"));
            out.close();
            if (!tmp.renameTo(pending)) {
                tmp.delete();
                Log.d("GameActivity", "could not publish pending steps");
                return;
            }
            Log.d("GameActivity", total + " steps pending for the Pokewalker mod");
        } catch (Exception e) {
            Log.d("GameActivity", "could not write pending steps: " + e);
        }
    }

    private static String isoTime(long millis) {
        java.text.SimpleDateFormat format =
            new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US);
        format.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
        return format.format(new java.util.Date(millis));
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
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        outState.putString(STATE_PENDING_PICK, pendingPickFilename);
        outState.putString(STATE_PENDING_PICK_DIR, pendingPickSaveDir);
        outState.putString(STATE_PENDING_CREATE, pendingCreateSuggestedName);
    }

    private static Uri pickedUri(int resultCode, Intent data) {
        if (resultCode != RESULT_OK || data == null) return null;
        if (data.getData() != null) return data.getData();
        ClipData clip = data.getClipData();
        if (clip != null && clip.getItemCount() > 0) {
            return clip.getItemAt(0).getUri();
        }
        return null;
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
        final String destName = pendingPickFilename != null
            ? pendingPickFilename : PICKED_ROM_FILENAME;
        Uri uri = pickedUri(resultCode, data);
        if (uri == null) {
            Log.d("GameActivity", "file picker returned no file (cancelled?)");
            if (isTelevision(this)) {
                writeSaveDirFlag(PICK_ERROR_FILENAME, PICK_CANCELLED_PREFIX + destName);
            }
            return;
        }
        File destDir = saveIdentityDir();
        if (!destDir.exists() && !destDir.mkdirs()) {
            Log.d("GameActivity", "could not create " + destDir);
            writeSaveDirFlag(PICK_ERROR_FILENAME, destName);
            return;
        }
        final boolean directRequired = isDirectRequiredDestination(destName);
        final File destFile;
        try {
            File rootCanonical = destDir.getCanonicalFile();
            destFile = new File(rootCanonical, destName).getCanonicalFile();
            String rootPrefix = rootCanonical.getPath() + File.separator;
            if (destFile.equals(rootCanonical)
                    || !destFile.getPath().startsWith(rootPrefix)
                    || (destName.indexOf('/') >= 0 && !directRequired)) {
                Log.d("GameActivity", "refusing unsafe result dest: " + destName);
                writeSaveDirFlag(PICK_ERROR_FILENAME, destName);
                return;
            }
        } catch (IOException e) {
            Log.d("GameActivity", "could not validate result dest: " + e.getMessage());
            writeSaveDirFlag(PICK_ERROR_FILENAME, destName);
            return;
        }

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
        final InputStream pickedSource = source;
        final File pickedRoot = destDir;
        if (directRequired) {
            // Optical-disc-sized imports must not block Android's UI thread and
            // must not create a second picked_required_import.bin copy.
            new Thread(new Runnable() {
                @Override public void run() {
                    PickCopyResult result = copyRequiredImport(pickedSource, destFile);
                    if (!result.ok) {
                        writeFlagFile(pickedRoot, PICK_ERROR_FILENAME, destName);
                        return;
                    }
                    String marker = "v1\n" + destName + "\n" + result.md5 + "\n"
                        + Long.toString(result.bytes) + "\n";
                    writeFlagFile(pickedRoot, PICK_COMPLETE_FILENAME, marker);
                }
            }, "gen1recomp-required-import").start();
            return;
        }

        if (!copyAssetFile(pickedSource, destFile.getPath())) {
            Log.d("GameActivity", "could not copy picked file to " + destFile);
            destFile.delete();
            writeSaveDirFlag(PICK_ERROR_FILENAME, destName);
        }
    }

    private static final class PickCopyResult {
        boolean ok = false;
        long bytes = 0;
        String md5 = "";
    }

    private static String hex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) out.append(String.format(Locale.US, "%02x", b & 0xff));
        return out.toString();
    }

    private static void writeFlagFile(File dir, String name, String body) {
        try {
            if (!dir.isDirectory() && !dir.mkdirs()) return;
            File tmp = new File(dir, name + ".tmp");
            File dest = new File(dir, name);
            FileOutputStream out = new FileOutputStream(tmp, false);
            out.write(body.getBytes("UTF-8"));
            out.getFD().sync();
            out.close();
            if (dest.exists() && !dest.delete()) { tmp.delete(); return; }
            if (!tmp.renameTo(dest)) tmp.delete();
        } catch (Exception e) {
            Log.d("GameActivity", "could not write " + name + ": " + e.getMessage());
        }
    }

    private static PickCopyResult copyRequiredImport(InputStream source, File destination) {
        PickCopyResult result = new PickCopyResult();
        File parent = destination.getParentFile();
        File partial = new File(destination.getPath() + ".part");
        BufferedInputStream in = null;
        BufferedOutputStream out = null;
        FileOutputStream rawOut = null;
        try {
            if (parent != null && !parent.isDirectory() && !parent.mkdirs()) return result;
            if (partial.exists() && !partial.delete()) return result;
            MessageDigest md5 = MessageDigest.getInstance("MD5");
            in = new BufferedInputStream(source, 1024 * 1024);
            rawOut = new FileOutputStream(partial, false);
            out = new BufferedOutputStream(rawOut, 1024 * 1024);
            byte[] buf = new byte[1024 * 1024];
            int n;
            long total = 0;
            while ((n = in.read(buf)) != -1) {
                if (n == 0) continue;
                out.write(buf, 0, n);
                md5.update(buf, 0, n);
                total += n;
            }
            out.flush();
            rawOut.getFD().sync();
            out.close(); out = null; rawOut = null;
            in.close(); in = null;

            // Publish only a complete same-directory file. Validation still
            // happens in Lua against the manifest before a receipt is written.
            if (destination.exists() && !destination.delete()) return result;
            if (!partial.renameTo(destination)) return result;
            result.ok = true;
            result.bytes = total;
            result.md5 = hex(md5.digest());
            Log.d("GameActivity", "direct required import copied " + total
                + " bytes to " + destination);
            return result;
        } catch (Exception e) {
            Log.d("GameActivity", "direct required import failed: " + e.getMessage());
            return result;
        } finally {
            try { if (in != null) in.close(); } catch (IOException ignored) {}
            try { if (out != null) out.close(); } catch (IOException ignored) {}
            try { if (rawOut != null) rawOut.close(); } catch (IOException ignored) {}
            if (!result.ok && partial.exists()) partial.delete();
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
            byte[] buf = new byte[1024 * 1024];
            while ((chunk_read = source.read(buf)) != -1) {
                if (chunk_read == 0) continue;
                destination.write(buf, 0, chunk_read);
                bytes_written += chunk_read;
            }
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
                case STEP_PERMISSION_REQUEST_CODE: {
                    if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                        Log.d("GameActivity", "Step permission granted");
                        // Deliver right away so the sync the player just
                        // opted into doesn't wait for the next launch.
                        startStepSensorRead();
                    } else {
                        Log.d("GameActivity", "Did not get step permission.");
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

    private void requestGameAudioFocus() {
        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

        if (audioManager == null) {
            return;
        }

        if (audioFocusListener == null) {
            audioFocusListener = new AudioManager.OnAudioFocusChangeListener() {
                @Override
                public void onAudioFocusChange(int focusChange) {
                    handleAudioFocusChange(focusChange);
                }
            };
        }

        int result;

        if (android.os.Build.VERSION.SDK_INT >= 26) {
            result = requestGameAudioFocusModern(audioManager);
        } else {
            result = audioManager.requestAudioFocus(audioFocusListener,
                AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN);
        }

        audioFocusHeld = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;

        if (!audioFocusHeld) {
            Log.d("GameActivity", "audio focus request was not granted: " + result);
        }
    }

    private int requestGameAudioFocusModern(AudioManager audioManager) {
        if (audioFocusRequest == null) {
            AudioAttributes attributes = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build();
            audioFocusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes)
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(audioFocusListener)
                .build();
        }

        return audioManager.requestAudioFocus((AudioFocusRequest) audioFocusRequest);
    }

    private void abandonAudioFocus() {
        if (!audioFocusHeld) {
            return;
        }

        audioFocusHeld = false;

        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

        if (audioManager == null) {
            return;
        }

        if (android.os.Build.VERSION.SDK_INT >= 26 && audioFocusRequest != null) {
            abandonAudioFocusModern(audioManager);
        } else if (audioFocusListener != null) {
            audioManager.abandonAudioFocus(audioFocusListener);
        }
    }

    private void abandonAudioFocusModern(AudioManager audioManager) {
        audioManager.abandonAudioFocusRequest((AudioFocusRequest) audioFocusRequest);
    }

    private void handleAudioFocusChange(int focusChange) {
        try {
            switch (focusChange) {
                case AudioManager.AUDIOFOCUS_LOSS:
                    audioFocusHeld = false;
                    nativeAudioFocusLost();
                    break;
                case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
                    nativeAudioFocusLost();
                    break;
                case AudioManager.AUDIOFOCUS_GAIN:
                case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT:
                case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK:
                    audioFocusHeld = true;
                    nativeAudioFocusGained();
                    break;
                default:
                    break;
            }
        } catch (UnsatisfiedLinkError e) {
            Log.d("GameActivity", "audio focus change before liblove was ready", e);
        }
    }

    private void registerAudioDeviceCallback() {
        if (android.os.Build.VERSION.SDK_INT < 23 || audioDeviceCallback != null) {
            return;
        }

        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

        if (audioManager == null) {
            return;
        }

        audioDeviceCallbackPrimed = false;
        audioDeviceCallback = createAudioDeviceCallback(audioManager);
    }

    private Object createAudioDeviceCallback(AudioManager audioManager) {
        AudioDeviceCallback callback = new AudioDeviceCallback() {
            @Override
            public void onAudioDevicesAdded(AudioDeviceInfo[] addedDevices) {
                if (!audioDeviceCallbackPrimed) {
                    audioDeviceCallbackPrimed = true;
                    return;
                }
                notifyAudioDeviceChanged();
            }

            @Override
            public void onAudioDevicesRemoved(AudioDeviceInfo[] removedDevices) {
                audioDeviceCallbackPrimed = true;
                notifyAudioDeviceChanged();
            }
        };

        audioManager.registerAudioDeviceCallback(callback, new Handler(Looper.getMainLooper()));
        return callback;
    }

    private void unregisterAudioDeviceCallback() {
        if (android.os.Build.VERSION.SDK_INT < 23 || audioDeviceCallback == null) {
            return;
        }

        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

        if (audioManager != null) {
            audioManager.unregisterAudioDeviceCallback((AudioDeviceCallback) audioDeviceCallback);
        }

        audioDeviceCallback = null;
        audioDeviceCallbackPrimed = false;
    }

    private void notifyAudioDeviceChanged() {
        try {
            nativeAudioDeviceChanged();
        } catch (UnsatisfiedLinkError e) {
            Log.d("GameActivity", "audio device change before liblove was ready", e);
        }
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

    // Dual-screen: mirror the engine's bottom-screen canvas onto a secondary
    // physical display. Driven from the engine through love_android_secondary_*
    // in src/jni/love/src/common/android.cpp.
    private static final int SECONDARY_TARGET_AUTO = 0;
    private static final int SECONDARY_TARGET_HANDHELD = 1;
    private static final int SECONDARY_TARGET_EXTERNAL = 2;
    // AYN keeps disabled panels registered as ON. This optional setting is the
    // usable-state signal: 0 = both, 1 = main only, 2 = second only.
    private static final String DUAL_SCREEN_DISPLAY_MODE = "dual_screen_display_mode";
    private static final String AYN_SECOND_SCREEN = "Screen-2";
    private static volatile SecondaryPresentation secondaryPresentation;
    private static volatile SecondaryActivity secondaryActivity;
    private static volatile boolean secondaryActivityPending;
    private static volatile int secondaryActivityTarget = Display.INVALID_DISPLAY;
    private static volatile long secondaryRetryAfter;
    private static volatile boolean secondaryEnabled = false;
    private static volatile boolean secondaryHostResumed = false;
    private static volatile int secondaryTarget = SECONDARY_TARGET_AUTO;
    private static volatile int dualScreenDisplayMode = -1;
    private static volatile byte[] secondaryFrame;
    private static volatile int secondaryFrameWidth;
    private static volatile int secondaryFrameHeight;
    private static volatile int secondaryBackground;
    private static volatile boolean secondaryFrameCover;
    private static final Object secondaryFrameLock = new Object();
    private static volatile long secondaryDetectionAt;
    private static volatile boolean secondaryDetected;
    private SecondaryDisplayMonitor secondaryDisplayMonitor;
    private boolean dualScreenModeObserverRegistered;
    private final android.database.ContentObserver dualScreenModeObserver =
        new android.database.ContentObserver(new Handler(Looper.getMainLooper())) {
            @Override public void onChange(boolean selfChange, Uri uri) {
                refreshDualScreenDisplayMode();
                rebindSecondaryDisplay();
            }
        };
    private static final int MAX_SECONDARY_TOUCHES = 32;
    private static final java.util.ArrayDeque<String> secondaryTouches =
        new java.util.ArrayDeque<>();

    @Keep
    public static void setSecondaryEnabled(final boolean on) {
        secondaryEnabled = on;
        final GameActivity self = (GameActivity) mSingleton;
        if (self == null) return;
        self.runOnUiThread(new Runnable() {
            @Override public void run() {
                if (on && secondaryHostResumed) {
                    self.refreshDualScreenDisplayMode();
                    self.registerSecondaryDisplayListener();
                    rebindSecondaryDisplay();
                } else {
                    self.unregisterSecondaryDisplayListener();
                    teardownSecondaryDisplay();
                    secondaryRetryAfter = 0;
                    synchronized (secondaryFrameLock) { secondaryFrame = null; }
                }
            }
        });
    }

    @Keep
    public static void setSecondaryDisplayTarget(int target) {
        int normalized = target == SECONDARY_TARGET_HANDHELD
            || target == SECONDARY_TARGET_EXTERNAL ? target : SECONDARY_TARGET_AUTO;
        if (secondaryTarget == normalized) return;
        secondaryTarget = normalized;
        secondaryDetectionAt = 0;
        rebindSecondaryDisplay();
    }

    private void refreshDualScreenDisplayMode() {
        int mode = Settings.System.getInt(
            getContentResolver(), DUAL_SCREEN_DISPLAY_MODE, -1);
        if (dualScreenDisplayMode != mode) secondaryDetectionAt = 0;
        dualScreenDisplayMode = mode;
    }

    private void registerSecondaryDisplayListener() {
        if (secondaryDisplayMonitor == null && android.os.Build.VERSION.SDK_INT >= 17) {
            SecondaryDisplayMonitor monitor = new SecondaryDisplayMonitor(this);
            if (monitor.register()) secondaryDisplayMonitor = monitor;
        }
        if (dualScreenDisplayMode != -1 && !dualScreenModeObserverRegistered) {
            getContentResolver().registerContentObserver(
                Settings.System.getUriFor(DUAL_SCREEN_DISPLAY_MODE), false,
                dualScreenModeObserver);
            dualScreenModeObserverRegistered = true;
        }
    }

    private void unregisterSecondaryDisplayListener() {
        SecondaryDisplayMonitor monitor = secondaryDisplayMonitor;
        secondaryDisplayMonitor = null;
        if (monitor != null) monitor.unregister();
        if (dualScreenModeObserverRegistered) {
            getContentResolver().unregisterContentObserver(dualScreenModeObserver);
            dualScreenModeObserverRegistered = false;
        }
    }

    private static boolean secondaryOutputIsPreferred(GameActivity self) {
        Display preferred = findSecondaryDisplay(self, false);
        if (preferred == null) return false;
        SecondaryPresentation presentation = secondaryPresentation;
        Display display = presentation == null
            ? null : presentation.getDisplay();
        if (display == null) {
            SecondaryActivity activity = secondaryActivity;
            display = activity == null ? null : getActivityDisplay(activity);
        }
        SecondaryDisplayMonitor monitor = self.secondaryDisplayMonitor;
        if (display == null || (monitor != null
                && !monitor.hasDisplay(display.getDisplayId()))) return false;
        return display.getDisplayId() == preferred.getDisplayId();
    }

    private static void rebindSecondaryDisplay() {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null || !secondaryHostResumed || !secondaryEnabled
                || secondaryOutputIsPreferred(self)) return;
        self.runOnUiThread(() -> {
            if (!secondaryHostResumed || !secondaryEnabled
                    || secondaryOutputIsPreferred(self)) return;
            teardownSecondaryDisplay();
            setupSecondaryDisplay();
        });
    }

    private static void setupSecondaryDisplay() {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null || !secondaryHostResumed || !secondaryEnabled
                || secondaryPresentation != null
                || secondaryActivity != null || secondaryActivityPending
                || android.os.SystemClock.elapsedRealtime() < secondaryRetryAfter) return;
        try {
            Display chosen = findSecondaryDisplay(self, true);
            if (chosen == null) {
                Log.d("GameActivity", "no secondary display found");
                return;
            }
            if (!isPresentationDisplay(chosen)) {
                if (android.os.Build.VERSION.SDK_INT < 29) return;
                secondaryActivityPending = true;
                secondaryActivityTarget = chosen.getDisplayId();
                Intent intent = new Intent(self, SecondaryActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
                android.app.ActivityOptions options = android.app.ActivityOptions.makeBasic();
                options.setLaunchDisplayId(secondaryActivityTarget);
                self.startActivity(intent, options.toBundle());
                final int requestedDisplay = secondaryActivityTarget;
                new Handler(Looper.getMainLooper()).postDelayed(() -> {
                    if (secondaryActivityPending
                            && secondaryActivityTarget == requestedDisplay) {
                        secondaryActivityPending = false;
                        secondaryRetryAfter = android.os.SystemClock.elapsedRealtime() + 1000;
                    }
                }, 1000);
                return;
            }
            SecondaryPresentation p = new SecondaryPresentation(self, chosen);
            p.setOnDismissListener(dialog -> {
                if (secondaryPresentation == p) {
                    secondaryPresentation = null;
                    rebindSecondaryDisplay();
                }
            });
            p.show();
            secondaryPresentation = p;
            secondaryRetryAfter = 0;
            synchronized (secondaryFrameLock) {
                if (secondaryFrame != null) {
                    p.setBackground(secondaryBackground);
                    p.updateFrame(java.nio.ByteBuffer.wrap(secondaryFrame),
                        secondaryFrameWidth, secondaryFrameHeight, secondaryFrameCover);
                }
            }
            Log.d("GameActivity", "secondary display presentation started on id=" + chosen.getDisplayId());
        } catch (Throwable t) {
            Log.d("GameActivity", "secondary display setup failed: " + t);
            secondaryActivityPending = false;
            secondaryActivityTarget = Display.INVALID_DISPLAY;
            secondaryRetryAfter = android.os.SystemClock.elapsedRealtime() + 1000;
            teardownSecondaryDisplay();
        }
    }

    private static Display findSecondaryDisplay(GameActivity self, boolean logDisplays) {
        android.hardware.display.DisplayManager dm =
            (android.hardware.display.DisplayManager) self.getSystemService(Context.DISPLAY_SERVICE);
        if (dm == null || android.os.Build.VERSION.SDK_INT < 17) return null;
        Display gameDisplay = getActivityDisplay(self);
        int gameDisplayId = gameDisplay == null
            ? Display.DEFAULT_DISPLAY : gameDisplay.getDisplayId();
        Display handheld = dm.getDisplay(Display.DEFAULT_DISPLAY);
        boolean handheldAvailable = android.os.Build.VERSION.SDK_INT >= 29
            && gameDisplayId != Display.DEFAULT_DISPLAY && isDisplayUsable(handheld);
        Display external = null;
        Display[] presentations = dm.getDisplays(
            android.hardware.display.DisplayManager.DISPLAY_CATEGORY_PRESENTATION);
        for (Display d : presentations) {
            if (logDisplays) {
                android.graphics.Point size = new android.graphics.Point();
                d.getRealSize(size);
                Log.d("GameActivity", "display id=" + d.getDisplayId()
                    + " name=" + d.getName() + " size=" + size.x + "x" + size.y);
            }
            if (external == null && d.getDisplayId() != gameDisplayId
                    && isDisplayUsable(d)) external = d;
        }
        if (secondaryTarget == SECONDARY_TARGET_HANDHELD && handheldAvailable) return handheld;
        if (secondaryTarget == SECONDARY_TARGET_EXTERNAL && external != null) return external;
        return handheldAvailable ? handheld : external;
    }

    private static Display getActivityDisplay(android.app.Activity activity) {
        return android.os.Build.VERSION.SDK_INT >= 30
            ? activity.getDisplay() : activity.getWindowManager().getDefaultDisplay();
    }

    private static boolean isPresentationDisplay(Display display) {
        if (display == null || display.getDisplayId() == Display.DEFAULT_DISPLAY) return false;
        return android.os.Build.VERSION.SDK_INT < 20
            || (display.getFlags() & Display.FLAG_PRESENTATION) != 0;
    }

    private static boolean isDisplayUsable(Display display) {
        if (display == null) return false;
        if (android.os.Build.VERSION.SDK_INT >= 20
                && display.getState() == Display.STATE_OFF) return false;
        if (dualScreenDisplayMode == 1 && AYN_SECOND_SCREEN.equals(display.getName())) {
            return false;
        }
        return dualScreenDisplayMode != 2
            || display.getDisplayId() != Display.DEFAULT_DISPLAY;
    }

    private static void teardownSecondaryDisplay() {
        SecondaryPresentation p = secondaryPresentation;
        secondaryPresentation = null;
        SecondaryActivity a = secondaryActivity;
        secondaryActivity = null;
        secondaryActivityPending = false;
        secondaryActivityTarget = Display.INVALID_DISPLAY;
        synchronized (secondaryTouches) { secondaryTouches.clear(); }
        if (p != null) {
            try { p.dismiss(); } catch (Throwable t) {}
        }
        if (a != null) {
            try { a.finish(); } catch (Throwable t) {}
        }
    }

    @android.annotation.TargetApi(17)
    private static class SecondaryDisplayMonitor
        implements android.hardware.display.DisplayManager.DisplayListener {
        private final android.hardware.display.DisplayManager manager;

        SecondaryDisplayMonitor(GameActivity activity) {
            manager = (android.hardware.display.DisplayManager)
                activity.getSystemService(Context.DISPLAY_SERVICE);
        }

        boolean register() {
            if (manager == null) return false;
            manager.registerDisplayListener(this, new Handler(Looper.getMainLooper()));
            return true;
        }

        void unregister() {
            manager.unregisterDisplayListener(this);
        }

        boolean hasDisplay(int displayId) {
            return manager.getDisplay(displayId) != null;
        }

        private void changed() {
            secondaryDetectionAt = 0;
            rebindSecondaryDisplay();
        }

        @Override public void onDisplayAdded(int displayId) { changed(); }
        @Override public void onDisplayRemoved(int displayId) { changed(); }
        @Override public void onDisplayChanged(int displayId) { changed(); }
    }

    @Keep
    public static boolean hasSecondaryDisplay() {
        return secondaryPresentation != null || secondaryActivity != null;
    }

    @Keep
    public static boolean hasSecondaryDisplayCandidate() {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (secondaryPresentation != null || secondaryActivity != null) return true;
        self.refreshDualScreenDisplayMode();
        long now = android.os.SystemClock.uptimeMillis();
        if (secondaryDetectionAt != 0 && now - secondaryDetectionAt < 500) {
            return secondaryDetected;
        }
        secondaryDetected = findSecondaryDisplay(self, false) != null;
        secondaryDetectionAt = now;
        return secondaryDetected;
    }

    @Keep
    public static boolean presentSecondaryFrame(
            java.nio.ByteBuffer rgba, int width, int height,
            int backgroundColor, boolean cover) {
        long bytes = (long) width * height * 4;
        if (rgba == null || width <= 0 || height <= 0
                || bytes <= 0 || bytes > Integer.MAX_VALUE
                || rgba.capacity() < bytes) return false;
        synchronized (secondaryFrameLock) {
            if (secondaryFrame == null || secondaryFrame.length != (int) bytes) {
                secondaryFrame = new byte[(int) bytes];
            }
            rgba.rewind();
            rgba.get(secondaryFrame, 0, (int) bytes);
            rgba.rewind();
            secondaryFrameWidth = width;
            secondaryFrameHeight = height;
            secondaryBackground = backgroundColor;
            secondaryFrameCover = cover;
            SecondaryPresentation p = secondaryPresentation;
            SecondaryActivity a = secondaryActivity;
            if (p == null && a == null) return false;
            try {
                if (p != null) {
                    p.setBackground(backgroundColor);
                    p.updateFrame(rgba, width, height, cover);
                } else {
                    a.setBackground(backgroundColor);
                    a.updateFrame(rgba, width, height, cover);
                }
                return true;
            } catch (Throwable t) {
                GameActivity self = (GameActivity) mSingleton;
                if (self != null) self.runOnUiThread(() -> {
                    teardownSecondaryDisplay();
                    setupSecondaryDisplay();
                });
                return false;
            }
        }
    }

    @Keep
    public static void updateSecondaryFrame(java.nio.ByteBuffer buf, int w, int h) {
        SecondaryPresentation p = secondaryPresentation;
        SecondaryActivity a = secondaryActivity;
        if ((p != null || a != null) && buf != null && w > 0 && h > 0) {
            if (p != null) p.updateFrame(buf, w, h);
            else a.updateFrame(buf, w, h);
        }
    }

    @Keep
    public static String pollSecondaryDisplayTouch() {
        synchronized (secondaryTouches) {
            return secondaryTouches.pollFirst();
        }
    }

    private static void applySecondaryImmersive(android.view.Window w) {
        if (w == null) return;
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            w.setDecorFitsSystemWindows(false);
            android.view.WindowInsetsController c = w.getInsetsController();
            if (c != null) {
                c.hide(android.view.WindowInsets.Type.systemBars());
                c.setSystemBarsBehavior(
                    android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            w.getDecorView().setSystemUiVisibility(
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                | android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        }
    }

    public static class SecondaryActivity extends android.app.Activity {
        private FrameView frameView;

        @Override
        protected void onCreate(Bundle savedInstanceState) {
            super.onCreate(savedInstanceState);
            Display display = getActivityDisplay(this);
            if (!secondaryEnabled || display == null
                    || display.getDisplayId() != secondaryActivityTarget) {
                secondaryActivityPending = false;
                secondaryActivityTarget = Display.INVALID_DISPLAY;
                secondaryRetryAfter = android.os.SystemClock.elapsedRealtime() + 1000;
                finish();
                return;
            }
            frameView = new FrameView(this);
            android.view.Window w = getWindow();
            w.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN
                | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                WindowManager.LayoutParams.FLAG_FULLSCREEN
                | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
            setContentView(frameView);
            applySecondaryImmersive(w);
            secondaryActivity = this;
            secondaryActivityPending = false;
            secondaryRetryAfter = 0;
            synchronized (secondaryFrameLock) {
                if (secondaryFrame != null) {
                    setBackground(secondaryBackground);
                    updateFrame(java.nio.ByteBuffer.wrap(secondaryFrame),
                        secondaryFrameWidth, secondaryFrameHeight, secondaryFrameCover);
                }
            }
        }

        @Override
        protected void onDestroy() {
            if (secondaryActivity == this) secondaryActivity = null;
            super.onDestroy();
        }

        @Override
        public void onWindowFocusChanged(boolean hasFocus) {
            super.onWindowFocusChanged(hasFocus);
            if (hasFocus) applySecondaryImmersive(getWindow());
        }

        @Override
        public boolean dispatchKeyEvent(android.view.KeyEvent event) {
            GameActivity activity = (GameActivity) mSingleton;
            return activity != null
                ? activity.dispatchKeyEvent(event) : super.dispatchKeyEvent(event);
        }

        @Override
        public boolean dispatchGenericMotionEvent(android.view.MotionEvent event) {
            GameActivity activity = (GameActivity) mSingleton;
            return activity != null
                ? activity.dispatchGenericMotionEvent(event)
                : super.dispatchGenericMotionEvent(event);
        }

        void updateFrame(java.nio.ByteBuffer buf, int w, int h) {
            frameView.updateFrame(buf, w, h);
        }

        void updateFrame(java.nio.ByteBuffer buf, int w, int h, boolean cover) {
            frameView.updateFrame(buf, w, h, cover);
        }

        void setBackground(int color) {
            frameView.setFrameBackground(color);
        }
    }

    private static class SecondaryPresentation extends android.app.Presentation {
        private final FrameView frameView;

        SecondaryPresentation(Context context, Display display) {
            super(context, display);
            frameView = new FrameView(context);
        }

        @Override
        protected void onCreate(Bundle savedInstanceState) {
            super.onCreate(savedInstanceState);
            android.view.Window w = getWindow();
            if (w != null) {
                w.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN
                    | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    WindowManager.LayoutParams.FLAG_FULLSCREEN
                    | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
                w.setLayout(WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT);
            }
            setContentView(frameView);
            applyImmersive();
            frameView.post(new Runnable() {
                @Override public void run() { applyImmersive(); }
            });
        }

        @Override
        public void onWindowFocusChanged(boolean hasFocus) {
            super.onWindowFocusChanged(hasFocus);
            if (hasFocus) applyImmersive();
        }

        @Override
        public boolean dispatchKeyEvent(android.view.KeyEvent event) {
            GameActivity activity = (GameActivity) mSingleton;
            return activity != null
                ? activity.dispatchKeyEvent(event) : super.dispatchKeyEvent(event);
        }

        @Override
        public boolean dispatchGenericMotionEvent(android.view.MotionEvent event) {
            GameActivity activity = (GameActivity) mSingleton;
            return activity != null
                ? activity.dispatchGenericMotionEvent(event)
                : super.dispatchGenericMotionEvent(event);
        }

        private void applyImmersive() {
            applySecondaryImmersive(getWindow());
        }

        void updateFrame(java.nio.ByteBuffer buf, int w, int h) {
            frameView.updateFrame(buf, w, h);
        }

        void updateFrame(java.nio.ByteBuffer buf, int w, int h, boolean cover) {
            frameView.updateFrame(buf, w, h, cover);
        }

        void setBackground(int color) {
            frameView.setFrameBackground(color);
        }
    }

    private static class FrameView extends View {
        private android.graphics.Bitmap bitmap;
        private final android.graphics.Rect dst = new android.graphics.Rect();
        private final android.graphics.Paint paint = new android.graphics.Paint();
        private final Object lock = new Object();
        private int fw, fh;
        private int backgroundColor = 0xFF000000;
        private int activePointer = -1;
        private boolean cover;

        FrameView(Context context) {
            super(context);
            paint.setFilterBitmap(false);
            paint.setAntiAlias(false);
            setBackgroundColor(0xFF000000);
        }

        void updateFrame(java.nio.ByteBuffer buf, int w, int h) {
            updateFrame(buf, w, h, false);
        }

        void updateFrame(java.nio.ByteBuffer buf, int w, int h, boolean cover) {
            synchronized (lock) {
                this.cover = cover;
                if (bitmap == null || fw != w || fh != h) {
                    if (bitmap != null) bitmap.recycle();
                    bitmap = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888);
                    fw = w; fh = h;
                }
                buf.rewind();
                bitmap.copyPixelsFromBuffer(buf);
            }
            postInvalidate();
        }

        void setFrameBackground(int color) {
            synchronized (lock) {
                backgroundColor = 0xFF000000 | (color & 0x00FFFFFF);
            }
            postInvalidate();
        }

        private void enqueueTouch(String event) {
            synchronized (secondaryTouches) {
                if (secondaryTouches.size() >= MAX_SECONDARY_TOUCHES) {
                    secondaryTouches.clear();
                    secondaryTouches.addLast("cancel,0,0");
                } else {
                    secondaryTouches.addLast(event);
                }
            }
        }

        private int logicalX(float x) {
            return Math.min(fw - 1, Math.max(0,
                (int) ((x - dst.left) * fw / dst.width())));
        }

        private int logicalY(float y) {
            return Math.min(fh - 1, Math.max(0,
                (int) ((y - dst.top) * fh / dst.height())));
        }

        @Override
        public boolean onTouchEvent(android.view.MotionEvent event) {
            synchronized (lock) {
                int action = event.getActionMasked();
                if (action == android.view.MotionEvent.ACTION_DOWN && fw > 0
                        && dst.contains((int) event.getX(), (int) event.getY())) {
                    activePointer = event.getPointerId(0);
                    enqueueTouch("down," + logicalX(event.getX()) + ","
                        + logicalY(event.getY()));
                } else if (action == android.view.MotionEvent.ACTION_UP
                        && activePointer >= 0) {
                    int index = event.findPointerIndex(activePointer);
                    if (index >= 0 && fw > 0) {
                        enqueueTouch("up," + logicalX(event.getX(index)) + ","
                            + logicalY(event.getY(index)));
                    }
                    activePointer = -1;
                } else if (action == android.view.MotionEvent.ACTION_CANCEL) {
                    activePointer = -1;
                    enqueueTouch("cancel,0,0");
                }
            }
            return true;
        }

        @Override
        protected void onDraw(android.graphics.Canvas canvas) {
            synchronized (lock) {
                if (bitmap == null || fw == 0 || fh == 0) return;
                int vw = getWidth(), vh = getHeight();
                float fit = Math.min((float) vw / fw, (float) vh / fh);
                if (fit <= 0) return;
                float scale = cover
                    ? Math.max((float) vw / fw, (float) vh / fh)
                    : fit >= 2f ? (float) Math.floor(fit) : fit;
                int dw = Math.round(fw * scale), dh = Math.round(fh * scale);
                int dx = (vw - dw) / 2, dy = (vh - dh) / 2;
                dst.set(dx, dy, dx + dw, dy + dh);
                canvas.drawColor(backgroundColor);
                canvas.drawBitmap(bitmap, null, dst, paint);
            }
        }
    }
}
