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

#ifndef LOVE_ANDROID_H
#define LOVE_ANDROID_H

#include "config.h"

#ifdef LOVE_ANDROID

#include <string>

namespace love
{
namespace android
{

/**
 * Enables or disables immersive mode where the navigation bar is hidden.
 **/
void setImmersive(bool immersive_active);
bool getImmersive();

/**
 * Gets the scale factor of the window's screen, e.g. on Retina displays this
 * will return 2.0.
 **/
double getScreenScale();

/**
 * Gets the window safe area, e.g. phone with notch display.
 * Returns false if safe area is not set.
 **/
bool getSafeArea(int &top, int &left, int &bottom, int &right);

/**
 * Gets the selected love file in the device filesystem.
 **/
const char *getSelectedGameFile();

bool openURL(const std::string &url);

void vibrate(double seconds);

/**
 * Shows the system's "pick a document" UI (Storage Access Framework).
 * Returns true if the picker was launched; the picked file (if any) is
 * copied asynchronously by GameActivity.onActivityResult into the app's
 * external save directory under destFilename (default picked_rom.gb), not
 * returned here -- see src/import/RomImporter.lua.
 **/
bool showFilePicker(const char *destFilename = nullptr);

/**
 * Shows ACTION_CREATE_DOCUMENT so Lua can export a staged pending_export.sav
 * to a user-chosen location. suggestedName is the dialog default filename.
 **/
bool showCreateDocument(const char *suggestedName = nullptr);

/**
 * Whether GameActivity has found a secondary (Presentation-category) Android
 * Display and attached a rendering surface to it -- e.g. the AYN Thor's
 * bottom panel. False on single-screen devices/desktop, and false until the
 * Java side has finished attaching (see GameActivity.attachSecondaryDisplay).
 * Mods should check this before calling presentUIFrame every frame.
 **/
bool hasSecondaryDisplay();

/**
 * Copies an RGBA8 pixel buffer (w*h*4 bytes, row-major, no padding -- the
 * same layout love.graphics.Canvas:newImageData():getString() returns) to
 * the secondary display's Bitmap and requests a redraw. A no-op returning
 * false if hasSecondaryDisplay() is false or the buffer size doesn't match
 * w*h*4. See GameActivity.pushUIFrame.
 **/
bool presentUIFrame(const char *pixels, size_t size, int w, int h);

/**
 * Reverse channel for presentUIFrame: pops the oldest pending touch on the
 * secondary display, if any. action is 0 (down), 1 (move), 2 (up) or 3
 * (cancel); x/y are in the same pixel space as the w/h a presentUIFrame
 * call last used. Returns false (leaving the outputs untouched) when
 * nothing is queued -- callers should poll every frame they care about
 * input, draining until it returns false, since more than one touch can
 * queue between polls. See GameActivity.pollSecondScreenTouch.
 **/
bool pollSecondScreenTouch(int &action, float &x, float &y);

/*
 * Helper functions for the filesystem module
 */
void freeGameArchiveMemory(void *ptr);

bool loadGameArchiveToMemory(const char *filename, char **ptr, size_t *size);

bool directoryExists(const char *path);

bool mkdir(const char *path);

bool createStorageDirectories();

bool hasBackgroundMusic();

bool hasRecordingPermission();

void requestRecordingPermission();

void showRecordingPermissionMissingDialog();

/**
 * Initialize Android AAsset virtual archive.
 * @return true if successful.
 */
bool initializeVirtualArchive();

/**
 * Deinitialize Android AAsset virtual archive.
 * @return true if successful.
 */
void deinitializeVirtualArchive();

/**
 * Retrieve the fused game inside the APK
 * @param physfsIO_Out Pointer to PHYSFS_Io* struct
 * @return true if there's game inside the APK. If physfsIO_Out is not null, then it contains
 * the game.love which needs to be mounted to root. false if it's not fused, in which case
 * physfsIO_Out is undefined.
 */
bool checkFusedGame(void **physfsIO_Out);

const char *getCRequirePath();

/**
 * Retrieve PHYSFS_AndroidInit structure.
 * @return Pointer to PHYSFS_AndroidInit structure, casted to pointer of char.
 */
const char *getArg0();

} // android
} // love

#endif // LOVE_ANDROID
#endif // LOVE_ANDROID_H
