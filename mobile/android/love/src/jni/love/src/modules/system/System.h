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

#ifndef LOVE_SYSTEM_H
#define LOVE_SYSTEM_H

// LOVE
#include "common/config.h"
#include "common/Module.h"
#include "common/StringMap.h"

// stdlib
#include <string>

namespace love
{
namespace system
{

class System : public Module
{
public:

	enum PowerState
	{
		POWER_UNKNOWN,
		POWER_BATTERY,
		POWER_NO_BATTERY,
		POWER_CHARGING,
		POWER_CHARGED,
		POWER_MAX_ENUM
	};

	System();
	virtual ~System() {}

	// Implements Module.
	virtual ModuleType getModuleType() const { return M_SYSTEM; }

	/**
	 * Gets the current operating system.
	 **/
	std::string getOS() const;

	/**
	 * Gets the number of reported CPU cores on the current system.
	 * Does not account for technologies such as Hyperthreading: a 4-core
	 * Hyperthreading-enabled Intel CPU will report 8, instead of 4.
	 **/
	virtual int getProcessorCount() const = 0;

	/**
	 * Replaces the contents of the system's text clipboard with a string.
	 * @param text The clipboard text to set.
	 **/
	virtual void setClipboardText(const std::string &text) const = 0;

	/**
	 * Gets the contents of the system's text clipboard.
	 **/
	virtual std::string getClipboardText() const = 0;

	/**
	 * Gets information about the system's power supply.
	 *
	 * @param[out] seconds Time in seconds of battery life left.
	 *             -1 if a value can't be determined.
	 * @param[out] percent The percentage of battery life left (0-100.)
	 *             -1 if a value can't be determined.
	 *
	 * @return The current state of the battery.
	 **/
	virtual PowerState getPowerInfo(int &seconds, int &percent) const = 0;

	/**
	 * Opens the specified URL with the user's default program to handle that
	 * particular URL type.
	 *
	 * @param url The URL to open.
	 *
	 * @return Whether the URL was opened successfully.
	 **/
	virtual bool openURL(const std::string &url) const;

	/**
	 * Vibrates for the specified amount of seconds.
	 *
	 * @param number of seconds to vibrate.
	 */
	virtual void vibrate(double seconds) const;

	/**
	 * Shows the platform's native "pick a file" UI, if one is available.
	 * Android only for now; the result (if any) is not returned here -- see
	 * love::android::showFilePicker and src/import/RomImporter.lua.
	 *
	 * @param kind Optional pick kind: nullptr/"rom" -> picked_rom.gb,
	 *             "mod" -> picked_mod.zip, "sav"/"save" -> picked_save.sav,
	 *             "required_import" -> picked_required_import.bin.
	 * @return Whether the picker was shown.
	 **/
	virtual bool pickFile(const char *kind = nullptr) const;
	virtual const char *pickFileKinds() const;

	/**
	 * Shows the platform's native "create / save a file" UI (Android SAF
	 * ACTION_CREATE_DOCUMENT). Copies staged pending_export.sav from the app
	 * save directory to the user-chosen URI. See GameActivity.showCreateDocument.
	 *
	 * @param suggestedName Default filename shown in the dialog.
	 * @return Whether the create dialog was shown.
	 **/
	virtual bool createFile(const char *suggestedName = nullptr) const;

	/**
	 * Pokéwalker: stage pending real-world steps (steps_pending.json in the
	 * save dir) from the platform step source. Android-only; false elsewhere.
	 */
	virtual bool syncHealthSteps() const;

	/**
	 * Relaunches the whole app with a fresh process (Android only; false
	 * elsewhere). The in-process love.event.quit("restart") double-inits
	 * physfs on Android and crashes, so src/core/HostShell.lua calls this
	 * instead (#575). Does not return on success -- the process exits.
	 **/
	virtual bool restartApp() const;

	/** Starts Android's user-confirmed install flow for a verified APK. */
	virtual bool installApk(const char *path) const;

	virtual bool updateShortcuts(const std::vector<std::string> &versions) const;
	virtual std::string getLaunchGame() const;

	/**
	 * Blocking HTTPS GET into an absolute host path (Android only; false
	 * elsewhere). Android has no curl, which is what every other platform
	 * fetches the mod index with (#597).
	 **/
	virtual bool httpDownload(const char *url, const char *destPath,
		const char *userAgent = nullptr, const char *accept = nullptr) const;

	/**
	 * Blocking HTTPS POST of a raw byte body (Android only; false
	 * elsewhere). The mirror of httpDownload for mod.postLog log sends,
	 * which need POST and have no curl on Android (#597).
	 **/
	virtual bool httpPost(const char *url, const char *body, int bodyLen,
		const char *contentType = nullptr, const char *userAgent = nullptr) const;

	/**
	 * Blocking HTTPS request with a method, headers and a byte body (Android
	 * only; false elsewhere). Save sync needs PUT, auth headers and the body
	 * of a 4xx, none of which the two bridges above can express. headerPairs
	 * is a flat name, value array; `out` receives the response envelope
	 * ("STATUS <code>" or "ERROR <text>", a newline, then the raw body).
	 **/
	virtual bool httpRequest(const char *url, const char *method,
		const char *const *headerPairs, int headerPairCount,
		const char *body, int bodyLen, const char *userAgent,
		std::string &out) const;

	/**
	 * TLS client sockets (Android only; every call fails elsewhere, where
	 * LuaSec or another provider is the answer). Non-blocking by contract:
	 * tlsOpen returns a handle and connects on its own thread, tlsStatus
	 * reports 0 connecting / 1 open / 2 closed / -1 unknown, and bytes sent
	 * before the handshake completes are queued rather than refused.
	 **/
	virtual int tlsOpen(const char *host, int port) const;
	virtual int tlsStatus(int handle) const;
	virtual int tlsSend(int handle, const char *data, int length) const;
	virtual int tlsReceive(int handle, char *buf, int max) const;
	virtual bool tlsError(int handle, char *buf, int max) const;
	virtual void tlsClose(int handle) const;

	/**
	 * Gets if the user is playing music on background.
	 * Throws an exception on unsupported platforms.
	 *
	 * @return Whether a music is playing on background.
	 **/
	bool hasBackgroundMusic() const;

	static bool getConstant(const char *in, PowerState &out);
	static bool getConstant(PowerState in, const char *&out);

private:

	static StringMap<PowerState, POWER_MAX_ENUM>::Entry powerEntries[];
	static StringMap<PowerState, POWER_MAX_ENUM> powerStates;

}; // System

} // system
} // love

#endif // LOVE_SYSTEM_H
