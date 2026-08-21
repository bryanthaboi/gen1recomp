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
 * Pokéwalker step bridge: asks GameActivity to read the hardware step
 * counter and stage steps_pending.json in the save identity dir (see
 * GameActivity.syncHealthSteps). Returns whether a sync could start.
 */
bool syncHealthSteps();

/**
 * Full process relaunch (GameActivity.restartApp): schedules the app's
 * launch intent and kills the process, because the in-process
 * quit("restart") loop double-inits physfs and crashes (#575). On success
 * the process dies inside the Java call and this never returns; false
 * means the relaunch could not be scheduled.
 **/
bool restartApp();

/**
 * Stages a checksum-verified APK from the current save directory and starts
 * Android's user-confirmed Package Installer flow. Android-only.
 **/
bool installApk(const char *path);

/**
 * Dynamic App Shortcuts: updates Android ShortcutManager with ready game versions.
 **/
bool updateAppShortcuts(const std::vector<std::string> &versions);

/**
 * Returns the game version requested via initial launch Intent (if any).
 **/
std::string getLaunchGame();

/**
 * Blocking HTTPS GET into destPath (GameActivity.httpDownload). Android has
 * no curl binary, so this is the transport src/core/HostShell.lua uses there
 * for the mod index and mod updates (#597). userAgent / accept may be null.
 * Returns whether a complete file was written.
 **/
bool httpDownload(const char *url, const char *destPath, const char *userAgent, const char *accept);

/**
 * Blocking HTTPS POST of a raw byte body (GameActivity.httpPost). The
 * mirror of httpDownload for mod.postLog log sends, which need POST and
 * have no curl on Android. contentType / userAgent may be null. Returns
 * whether the server accepted the send (2xx).
 **/
bool httpPost(const char *url, const char *body, int bodyLen, const char *contentType, const char *userAgent);

/**
 * Blocking HTTPS request with a method, headers and a byte body
 * (GameActivity.httpRequest). What save sync needs and neither of the two
 * above can give it: PUT, per-request auth headers, and the response body of
 * a 4xx as well as a 2xx. headerPairs is a flat name, value array of
 * headerPairCount entries; body/userAgent may be null. `out` receives the
 * Java side's envelope -- a head line of "STATUS <code>" or "ERROR <text>",
 * a newline, then the raw response bytes. False means the platform has no
 * such bridge at all (an old APK under a newer liblove), which the Lua side
 * reports as "update the app" rather than as a failed request.
 **/
bool httpRequest(const char *url, const char *method,
	const char *const *headerPairs, int headerPairCount,
	const char *body, int bodyLen, const char *userAgent, std::string &out);

/**
 * TLS client sockets (GameActivity.tls*, implemented by TlsSocket.java).
 * LuaSocket, which is what LOVE ships, does TCP only, so wss:// is otherwise
 * unreachable -- and an Archipelago room hosted on archipelago.gg accepts a
 * plain connection only to drop it. The platform has both a TLS stack and the
 * system trust store, so this borrows them rather than vendoring mbedTLS.
 *
 * tlsOpen returns a handle immediately and connects on its own thread: poll
 * tlsStatus for 0 connecting / 1 open / 2 closed, and -1 for a handle that
 * does not exist. Bytes given to tlsSend before the handshake finishes are
 * queued rather than refused. tlsReceive fills buf and returns how much it
 * took, 0 when nothing is waiting. A closed connection keeps both its reason
 * (tlsError) and whatever arrived before it closed until tlsClose.
 **/
int tlsOpen(const char *host, int port);
int tlsStatus(int handle);
int tlsSend(int handle, const char *data, int length);
int tlsReceive(int handle, char *buf, int max);
bool tlsError(int handle, char *buf, int max);
void tlsClose(int handle);

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
