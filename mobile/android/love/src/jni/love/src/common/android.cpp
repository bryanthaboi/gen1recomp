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

#include "android.h"

#ifdef LOVE_ANDROID

#include <cerrno>
#include <cstring>
#include <unordered_map>

#include <SDL.h>

#include <jni.h>
#include <android/asset_manager.h>
#include <android/asset_manager_jni.h>

#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "filesystem/physfs/PhysfsIo.h"

// #604 / #839: the SAF bridges below must hand GameActivity the exact
// directory physfs mounted as the save dir -- the same contract the iOS
// GRPickerBridge already gets (mobile/ios/patch_love_src.py,
// gr_saveDirectory) -- instead of letting Java recompute the root on its
// own, which can name a different volume on merged / adopted-SD storage.
#include "filesystem/Filesystem.h"

#include "common/Module.h"
#include "audio/Audio.h"
#include "audio/openal/Audio.h"
#include "event/Event.h"

namespace love
{
namespace android
{

void setImmersive(bool immersive_active)
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();

	jobject activity = (jobject) SDL_AndroidGetActivity();

	jclass clazz(env->GetObjectClass(activity));
	jmethodID method_id = env->GetMethodID(clazz, "setImmersiveMode", "(Z)V");

	env->CallVoidMethod(activity, method_id, immersive_active);

	env->DeleteLocalRef(activity);
	env->DeleteLocalRef(clazz);
}

bool getImmersive()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();

	jobject activity = (jobject) SDL_AndroidGetActivity();

	jclass clazz(env->GetObjectClass(activity));
	jmethodID method_id = env->GetMethodID(clazz, "getImmersiveMode", "()Z");

	jboolean immersive_active = env->CallBooleanMethod(activity, method_id);

	env->DeleteLocalRef(activity);
	env->DeleteLocalRef(clazz);

	return immersive_active;
}

double getScreenScale()
{
	static double result = -1.;

	if (result == -1.)
	{
		JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
		jclass activity = env->FindClass("org/love2d/android/GameActivity");

		jmethodID getMetrics = env->GetStaticMethodID(activity, "getMetrics", "()Landroid/util/DisplayMetrics;");
		jobject metrics = env->CallStaticObjectMethod(activity, getMetrics);
		jclass metricsClass = env->GetObjectClass(metrics);

		result = env->GetFloatField(metrics, env->GetFieldID(metricsClass, "density", "F"));

		env->DeleteLocalRef(metricsClass);
		env->DeleteLocalRef(metrics);
		env->DeleteLocalRef(activity);
	}

	return result;
}

bool getSafeArea(int &top, int &left, int &bottom, int &right)
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jobject activity = (jobject) SDL_AndroidGetActivity();
	jclass clazz(env->GetObjectClass(activity));
	jmethodID methodID = env->GetMethodID(clazz, "initializeSafeArea", "()Z");
	bool hasSafeArea = false;

	if (methodID == nullptr)
		// NoSuchMethodException is thrown in case methodID is null
		env->ExceptionClear();
	else if ((hasSafeArea = env->CallBooleanMethod(activity, methodID)))
	{
		top = env->GetIntField(activity, env->GetFieldID(clazz, "safeAreaTop", "I"));
		left = env->GetIntField(activity, env->GetFieldID(clazz, "safeAreaLeft", "I"));
		bottom = env->GetIntField(activity, env->GetFieldID(clazz, "safeAreaBottom", "I"));
		right = env->GetIntField(activity, env->GetFieldID(clazz, "safeAreaRight", "I"));
	}

	env->DeleteLocalRef(clazz);
	env->DeleteLocalRef(activity);

	return hasSafeArea;
}

const char *getSelectedGameFile()
{
	static const char *path = NULL;

	if (path)
	{
		delete path;
		path = NULL;
	}

	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");

	jmethodID getGamePath = env->GetStaticMethodID(activity, "getGamePath", "()Ljava/lang/String;");
	jstring gamePath = (jstring) env->CallStaticObjectMethod(activity, getGamePath);
	const char *utf = env->GetStringUTFChars(gamePath, 0);
	if (utf)
	{
		path = SDL_strdup(utf);
		env->ReleaseStringUTFChars(gamePath, utf);
	}

	env->DeleteLocalRef(gamePath);
	env->DeleteLocalRef(activity);

	return path;
}

bool openURL(const std::string &url)
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");

	jmethodID openURL = env->GetStaticMethodID(activity, "openURLFromLOVE", "(Ljava/lang/String;)Z");

	if (openURL == nullptr)
	{
		env->ExceptionClear();
		openURL = env->GetStaticMethodID(activity, "openURL", "(Ljava/lang/String;)Z");
	}

	jstring url_jstring = (jstring) env->NewStringUTF(url.c_str());

	jboolean result = env->CallStaticBooleanMethod(activity, openURL, url_jstring);

	env->DeleteLocalRef(url_jstring);
	env->DeleteLocalRef(activity);
	return result;
}

void vibrate(double seconds)
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");

	jmethodID vibrate_method = env->GetStaticMethodID(activity, "vibrate", "(D)V");
	env->CallStaticVoidMethod(activity, vibrate_method, seconds);

	env->DeleteLocalRef(activity);
}

// The directory physfs actually mounted as the save dir, or "" before the
// filesystem module is up.  GameActivity must copy SAF picks HERE: its own
// getExternalFilesDir(null) recomputation can disagree with the mounted
// root on merged / adopted-SD storage (#604, #839).
static const char *bridgeSaveDirectory()
{
	auto fs = Module::getInstance<love::filesystem::Filesystem>(Module::M_FILESYSTEM);
	if (fs == nullptr)
		return "";
	const char *dir = fs->getSaveDirectory();
	return dir != nullptr ? dir : "";
}

bool showFilePicker(const char *destFilename)
{
	if (destFilename == nullptr || destFilename[0] == '\0')
		destFilename = "picked_rom.gb";

	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");

	jmethodID method = env->GetStaticMethodID(activity, "showFilePicker",
		"(Ljava/lang/String;Ljava/lang/String;)Z");
	jstring jname = env->NewStringUTF(destFilename);
	jstring jsavedir = env->NewStringUTF(bridgeSaveDirectory());
	jboolean result = env->CallStaticBooleanMethod(activity, method, jname, jsavedir);
	env->DeleteLocalRef(jsavedir);
	env->DeleteLocalRef(jname);

	env->DeleteLocalRef(activity);
	return result;
}

bool showCreateDocument(const char *suggestedName)
{
	if (suggestedName == nullptr || suggestedName[0] == '\0')
		suggestedName = "export.sav";

	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");

	jmethodID method = env->GetStaticMethodID(activity, "showCreateDocument",
		"(Ljava/lang/String;Ljava/lang/String;)Z");
	jstring jname = env->NewStringUTF(suggestedName);
	jstring jsavedir = env->NewStringUTF(bridgeSaveDirectory());
	jboolean result = env->CallStaticBooleanMethod(activity, method, jname, jsavedir);
	env->DeleteLocalRef(jsavedir);
	env->DeleteLocalRef(jname);

	env->DeleteLocalRef(activity);
	return result;
}

bool syncHealthSteps()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");

	jmethodID method = env->GetStaticMethodID(activity, "syncHealthSteps", "()Z");
	jboolean result = env->CallStaticBooleanMethod(activity, method);

	env->DeleteLocalRef(activity);
	return result;
}

bool restartApp()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");

	// Old APK / new liblove skew: fail soft so HostShell.restart can fall
	// back to a clean quit instead of aborting on a missing method (#575).
	jmethodID method = env->GetStaticMethodID(activity, "restartApp", "()Z");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return false;
	}

	// Does not return on success: the Java side exits the process.
	jboolean result = env->CallStaticBooleanMethod(activity, method);

	env->DeleteLocalRef(activity);
	return result;
}

bool installApk(const char *path)
{
	if (path == nullptr || path[0] == '\0')
		return false;

	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	// This may be called from Lua's main thread, but use the activity object
	// class just like httpDownload so a future worker caller does not depend on
	// the system JNI class loader finding the app class.
	void *rawActivity = SDL_AndroidGetActivity();
	if (rawActivity == nullptr)
		return false;
	jobject activityObj = (jobject) rawActivity;
	jclass activity = env->GetObjectClass(activityObj);
	env->DeleteLocalRef(activityObj);

	jmethodID method = env->GetStaticMethodID(activity, "installApk",
		"(Ljava/lang/String;Ljava/lang/String;)Z");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return false;
	}

	jstring jpath = env->NewStringUTF(path);
	jstring jroot = env->NewStringUTF(bridgeSaveDirectory());
	jboolean result = env->CallStaticBooleanMethod(activity, method, jpath, jroot);
	env->DeleteLocalRef(jroot);
	env->DeleteLocalRef(jpath);
	env->DeleteLocalRef(activity);
	return result;
}

bool updateAppShortcuts(const std::vector<std::string> &versions)
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");
	if (activity == nullptr)
		return false;

	jmethodID method = env->GetStaticMethodID(activity, "updateAppShortcuts", "([Ljava/lang/String;)Z");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return false;
	}

	jclass stringClass = env->FindClass("java/lang/String");
	jobjectArray array = env->NewObjectArray((jsize) versions.size(), stringClass, nullptr);
	for (size_t i = 0; i < versions.size(); ++i)
	{
		jstring jstr = env->NewStringUTF(versions[i].c_str());
		env->SetObjectArrayElement(array, (jsize) i, jstr);
		env->DeleteLocalRef(jstr);
	}

	jboolean result = env->CallStaticBooleanMethod(activity, method, array);

	env->DeleteLocalRef(array);
	env->DeleteLocalRef(stringClass);
	env->DeleteLocalRef(activity);
	return result;
}

std::string getLaunchGame()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");
	if (activity == nullptr)
		return "";

	jmethodID method = env->GetStaticMethodID(activity, "getLaunchGame", "()Ljava/lang/String;");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return "";
	}

	jstring jgame = (jstring) env->CallStaticObjectMethod(activity, method);
	if (jgame == nullptr)
	{
		env->DeleteLocalRef(activity);
		return "";
	}

	const char *str = env->GetStringUTFChars(jgame, nullptr);
	std::string result = (str != nullptr) ? str : "";
	if (str != nullptr)
		env->ReleaseStringUTFChars(jgame, str);

	env->DeleteLocalRef(jgame);
	env->DeleteLocalRef(activity);
	return result;
}

bool httpDownload(const char *url, const char *destPath, const char *userAgent, const char *accept)
{
	if (url == nullptr || destPath == nullptr)
		return false;

	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	// NOT FindClass: this is the one bridge called off the main thread
	// (love.thread workers in src/net/fetch_worker.lua and
	// src/update/check_worker.lua).  A worker is a raw pthread whose JNI
	// class loader is the system one, which cannot see app classes, so
	// FindClass("org/love2d/android/GameActivity") left a pending
	// ClassNotFoundException and the next JNI call aborted the process --
	// opening FIND MODS killed the app on the first stats fetch.  Resolving
	// through the live activity instance works from any attached thread.
	jobject activityObj = (jobject) SDL_AndroidGetActivity();
	if (activityObj == nullptr)
		return false;
	jclass activity = env->GetObjectClass(activityObj);
	env->DeleteLocalRef(activityObj);

	// Old APK / new liblove skew: report "no transport" the same way a
	// missing curl does, instead of aborting on a missing method (#597).
	jmethodID method = env->GetStaticMethodID(activity, "httpDownload",
		"(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return false;
	}

	jstring jurl = env->NewStringUTF(url);
	jstring jdest = env->NewStringUTF(destPath);
	jstring jua = env->NewStringUTF(userAgent != nullptr ? userAgent : "gen1recomp");
	jstring jaccept = accept != nullptr ? env->NewStringUTF(accept) : nullptr;

	jboolean result = env->CallStaticBooleanMethod(activity, method, jurl, jdest, jua, jaccept);

	env->DeleteLocalRef(jurl);
	env->DeleteLocalRef(jdest);
	env->DeleteLocalRef(jua);
	if (jaccept != nullptr)
		env->DeleteLocalRef(jaccept);
	env->DeleteLocalRef(activity);
	return result;
}

bool httpPost(const char *url, const char *body, int bodyLen, const char *contentType, const char *userAgent)
{
	if (url == nullptr || body == nullptr || bodyLen < 0)
		return false;

	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	// Same resolution rule as httpDownload: the activity's own class via
	// SDL_AndroidGetActivity, never FindClass -- this bridge is called off
	// the main thread (love.thread workers), whose class loader cannot see
	// app classes.
	jobject activityObj = (jobject) SDL_AndroidGetActivity();
	if (activityObj == nullptr)
		return false;
	jclass activity = env->GetObjectClass(activityObj);
	env->DeleteLocalRef(activityObj);

	// Old APK / new liblove skew: report "no transport" the same way a
	// missing curl does, instead of aborting on a missing method (#597).
	jmethodID method = env->GetStaticMethodID(activity, "httpPost",
		"(Ljava/lang/String;[BLjava/lang/String;Ljava/lang/String;)Z");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return false;
	}

	jstring jurl = env->NewStringUTF(url);
	// raw bytes across the bridge: a log ring can carry arbitrary UTF-8,
	// and a jstring would run it through modified UTF-8
	jbyteArray jbody = env->NewByteArray(bodyLen);
	if (jbody != nullptr)
		env->SetByteArrayRegion(jbody, 0, bodyLen, (const jbyte*) body);
	jstring jct = contentType != nullptr ? env->NewStringUTF(contentType) : nullptr;
	jstring jua = userAgent != nullptr ? env->NewStringUTF(userAgent) : nullptr;

	jboolean result = env->CallStaticBooleanMethod(activity, method, jurl, jbody, jct, jua);

	env->DeleteLocalRef(jurl);
	if (jbody != nullptr)
		env->DeleteLocalRef(jbody);
	if (jct != nullptr)
		env->DeleteLocalRef(jct);
	if (jua != nullptr)
		env->DeleteLocalRef(jua);
	env->DeleteLocalRef(activity);
	return result;
}

bool httpRequest(const char *url, const char *method,
	const char *const *headerPairs, int headerPairCount,
	const char *body, int bodyLen, const char *userAgent, std::string &out)
{
	out.clear();
	if (url == nullptr)
		return false;
	if (headerPairCount < 0 || (headerPairCount > 0 && headerPairs == nullptr))
		return false;

	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	// Same resolution rule as httpDownload: the activity's own class via
	// SDL_AndroidGetActivity, never FindClass for an app class -- save sync
	// runs on a love.thread worker, whose class loader cannot see them.
	jobject activityObj = (jobject) SDL_AndroidGetActivity();
	if (activityObj == nullptr)
		return false;
	jclass activity = env->GetObjectClass(activityObj);
	env->DeleteLocalRef(activityObj);

	// Old APK / new liblove skew: report "no transport" instead of aborting
	// on a missing method (#597).
	jmethodID method_id = env->GetStaticMethodID(activity, "httpRequest",
		"(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;[BLjava/lang/String;)[B");
	if (method_id == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return false;
	}

	jobjectArray jheaders = nullptr;
	if (headerPairCount > 0)
	{
		// java/lang/String, unlike an app class, resolves from any thread.
		jclass stringClass = env->FindClass("java/lang/String");
		if (stringClass == nullptr)
		{
			env->ExceptionClear();
			env->DeleteLocalRef(activity);
			return false;
		}
		jheaders = env->NewObjectArray((jsize) headerPairCount, stringClass, nullptr);
		env->DeleteLocalRef(stringClass);
		if (jheaders == nullptr)
		{
			env->ExceptionClear();
			env->DeleteLocalRef(activity);
			return false;
		}
		for (int i = 0; i < headerPairCount; i++)
		{
			jstring field = env->NewStringUTF(headerPairs[i] != nullptr ? headerPairs[i] : "");
			env->SetObjectArrayElement(jheaders, (jsize) i, field);
			if (field != nullptr)
				env->DeleteLocalRef(field);
		}
	}

	jstring jurl = env->NewStringUTF(url);
	jstring jmethod = env->NewStringUTF(method != nullptr ? method : "GET");
	// raw bytes across the bridge, as httpPost does: a request body is JSON
	// carrying a base64 save, and a jstring would run it through modified UTF-8
	jbyteArray jbody = nullptr;
	if (body != nullptr && bodyLen >= 0)
	{
		jbody = env->NewByteArray((jsize) bodyLen);
		if (jbody != nullptr && bodyLen > 0)
			env->SetByteArrayRegion(jbody, 0, (jsize) bodyLen, (const jbyte*) body);
	}
	jstring jua = env->NewStringUTF(userAgent != nullptr ? userAgent : "gen1recomp");

	jobject result = env->CallStaticObjectMethod(activity, method_id, jurl, jmethod,
		jheaders, jbody, jua);

	env->DeleteLocalRef(jurl);
	env->DeleteLocalRef(jmethod);
	if (jheaders != nullptr)
		env->DeleteLocalRef(jheaders);
	if (jbody != nullptr)
		env->DeleteLocalRef(jbody);
	env->DeleteLocalRef(jua);
	env->DeleteLocalRef(activity);

	if (result == nullptr)
		return false;

	jbyteArray bytes = (jbyteArray) result;
	jsize length = env->GetArrayLength(bytes);
	if (length > 0)
	{
		out.resize((size_t) length);
		env->GetByteArrayRegion(bytes, 0, length, (jbyte*) &out[0]);
	}
	env->DeleteLocalRef(result);
	return true;
}

/*
 * TLS sockets. Same resolution rule as httpDownload above -- the activity's
 * own class, never FindClass -- and the same tolerance for an old APK: a
 * missing method answers like a platform without TLS instead of aborting.
 */
static jclass tlsActivityClass(JNIEnv *env)
{
	jobject activityObj = (jobject) SDL_AndroidGetActivity();
	if (activityObj == nullptr)
		return nullptr;
	jclass activity = env->GetObjectClass(activityObj);
	env->DeleteLocalRef(activityObj);
	return activity;
}

int tlsOpen(const char *host, int port)
{
	if (host == nullptr)
		return -1;
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = tlsActivityClass(env);
	if (activity == nullptr)
		return -1;

	jmethodID method = env->GetStaticMethodID(activity, "tlsOpen", "(Ljava/lang/String;I)I");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return -1;
	}

	jstring jhost = env->NewStringUTF(host);
	jint result = env->CallStaticIntMethod(activity, method, jhost, (jint) port);
	env->DeleteLocalRef(jhost);
	env->DeleteLocalRef(activity);
	return (int) result;
}

int tlsStatus(int handle)
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = tlsActivityClass(env);
	if (activity == nullptr)
		return -1;

	jmethodID method = env->GetStaticMethodID(activity, "tlsStatus", "(I)I");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return -1;
	}

	jint result = env->CallStaticIntMethod(activity, method, (jint) handle);
	env->DeleteLocalRef(activity);
	return (int) result;
}

int tlsSend(int handle, const char *data, int length)
{
	if (data == nullptr || length <= 0)
		return 0;
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = tlsActivityClass(env);
	if (activity == nullptr)
		return -1;

	jmethodID method = env->GetStaticMethodID(activity, "tlsSend", "(I[B)I");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return -1;
	}

	jbyteArray payload = env->NewByteArray((jsize) length);
	if (payload == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return -1;
	}
	env->SetByteArrayRegion(payload, 0, (jsize) length, (const jbyte*) data);

	jint result = env->CallStaticIntMethod(activity, method, (jint) handle, payload);
	env->DeleteLocalRef(payload);
	env->DeleteLocalRef(activity);
	return (int) result;
}

int tlsReceive(int handle, char *buf, int max)
{
	if (buf == nullptr || max <= 0)
		return 0;
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = tlsActivityClass(env);
	if (activity == nullptr)
		return -1;

	jmethodID method = env->GetStaticMethodID(activity, "tlsReceive", "(II)[B");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return -1;
	}

	jobject result = env->CallStaticObjectMethod(activity, method, (jint) handle, (jint) max);
	env->DeleteLocalRef(activity);
	if (result == nullptr)
		return 0;

	jbyteArray bytes = (jbyteArray) result;
	jsize length = env->GetArrayLength(bytes);
	if (length > max)
		length = max;
	env->GetByteArrayRegion(bytes, 0, length, (jbyte*) buf);
	env->DeleteLocalRef(result);
	return (int) length;
}

bool tlsError(int handle, char *buf, int max)
{
	if (buf == nullptr || max <= 0)
		return false;
	buf[0] = '\0';
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = tlsActivityClass(env);
	if (activity == nullptr)
		return false;

	jmethodID method = env->GetStaticMethodID(activity, "tlsError", "(I)Ljava/lang/String;");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return false;
	}

	jobject result = env->CallStaticObjectMethod(activity, method, (jint) handle);
	env->DeleteLocalRef(activity);
	if (result == nullptr)
		return false;

	jstring text = (jstring) result;
	const char *utf = env->GetStringUTFChars(text, nullptr);
	if (utf != nullptr)
	{
		strncpy(buf, utf, (size_t) max - 1);
		buf[max - 1] = '\0';
		env->ReleaseStringUTFChars(text, utf);
	}
	env->DeleteLocalRef(result);
	return buf[0] != '\0';
}

void tlsClose(int handle)
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = tlsActivityClass(env);
	if (activity == nullptr)
		return;

	jmethodID method = env->GetStaticMethodID(activity, "tlsClose", "(I)V");
	if (method == nullptr)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return;
	}

	env->CallStaticVoidMethod(activity, method, (jint) handle);
	env->DeleteLocalRef(activity);
}

/*
 * Helper functions for the filesystem module
 */
void freeGameArchiveMemory(void *ptr)
{
	char *game_love_data = static_cast<char*>(ptr);
	delete[] game_love_data;
}

bool loadGameArchiveToMemory(const char* filename, char **ptr, size_t *size)
{
	SDL_RWops *asset_game_file = SDL_RWFromFile(filename, "rb");
	if (!asset_game_file) {
		SDL_Log("Could not find %s", filename);
		return false;
	}

	Sint64 file_size = asset_game_file->size(asset_game_file);
	if (file_size <= 0) {
		SDL_Log("Could not load game from %s. File has invalid file size: %d.", filename, (int) file_size);
		return false;
	}

	*ptr = new char[file_size];
	if (!*ptr) {
		SDL_Log("Could not allocate memory for in-memory game archive");
		return false;
	}

	size_t bytes_copied = asset_game_file->read(asset_game_file, (void*) *ptr, sizeof(char), (size_t) file_size);
	if (bytes_copied != file_size) {
		SDL_Log("Incomplete copy of in-memory game archive!");
		delete[] *ptr;
		return false;
	}

	*size = (size_t) file_size;
	return true;
}

bool directoryExists(const char *path)
{
	struct stat s;
	int err = stat(path, &s);
	if (err == -1)
	{
		if (errno != ENOENT)
			SDL_Log("Error checking for directory %s errno = %d: %s", path, errno, strerror(errno));
		return false;
	}

	return S_ISDIR(s.st_mode);
}

bool mkdir(const char *path)
{
	int err = ::mkdir(path, 0770);
	if (err == -1)
	{
		SDL_Log("Error: Could not create directory %s", path);
		return false;
	}

	return true;
}

bool createStorageDirectories()
{
	std::string internal_storage_path = SDL_AndroidGetInternalStoragePath();

	std::string save_directory = internal_storage_path + "/save";
	if (!directoryExists(save_directory.c_str()) && !mkdir(save_directory.c_str()))
		return false;

	std::string game_directory = internal_storage_path + "/game";
	if (!directoryExists (game_directory.c_str()) && !mkdir(game_directory.c_str()))
		return false;

	return true;
}

bool hasBackgroundMusic()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jobject activity = (jobject) SDL_AndroidGetActivity();

	jclass clazz(env->GetObjectClass(activity));
	jmethodID method_id = env->GetMethodID(clazz, "hasBackgroundMusic", "()Z");

	jboolean result = env->CallBooleanMethod(activity, method_id);

	env->DeleteLocalRef(activity);
	env->DeleteLocalRef(clazz);

	return result;
}

bool hasRecordingPermission()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jobject activity = (jobject) SDL_AndroidGetActivity();

	jclass clazz(env->GetObjectClass(activity));
	jmethodID methodID = env->GetMethodID(clazz, "hasRecordAudioPermission", "()Z");
	jboolean result = false;

	if (methodID == nullptr)
		env->ExceptionClear();
	else
		result = env->CallBooleanMethod(activity, methodID);

	env->DeleteLocalRef(activity);
	env->DeleteLocalRef(clazz);

	return result;
}


void requestRecordingPermission()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jobject activity = (jobject) SDL_AndroidGetActivity();
	jclass clazz(env->GetObjectClass(activity));
	jmethodID methodID = env->GetMethodID(clazz, "requestRecordAudioPermission", "()V");

	if (methodID == nullptr)
		env->ExceptionClear();
	else
		env->CallVoidMethod(activity, methodID);

	env->DeleteLocalRef(clazz);
	env->DeleteLocalRef(activity);
}

void showRecordingPermissionMissingDialog()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jobject activity = (jobject) SDL_AndroidGetActivity();
	jclass clazz(env->GetObjectClass(activity));
	jmethodID methodID = env->GetMethodID(clazz, "showRecordingAudioPermissionMissingDialog", "()V");

	if (methodID == nullptr)
		env->ExceptionClear();
	else
		env->CallVoidMethod(activity, methodID);

	env->DeleteLocalRef(clazz);
	env->DeleteLocalRef(activity);
}

/* A container for AssetManager Java object */
class AssetManagerObject
{
public:
	AssetManagerObject()
	{
		JNIEnv *env = (JNIEnv *) SDL_AndroidGetJNIEnv();
		jobject am = getLocalAssetManager(env);

		assetManager = env->NewGlobalRef(am);
		env->DeleteLocalRef(am);
	}

	~AssetManagerObject()
	{
		JNIEnv *env = (JNIEnv *) SDL_AndroidGetJNIEnv();
		env->DeleteGlobalRef(assetManager);
	}

	static jobject getLocalAssetManager(JNIEnv *env) {
		jobject self = (jobject) SDL_AndroidGetActivity();
		jclass activity = env->GetObjectClass(self);
		jmethodID method = env->GetMethodID(activity, "getAssets", "()Landroid/content/res/AssetManager;");
		jobject am = env->CallObjectMethod(self, method);

		env->DeleteLocalRef(self);
		env->DeleteLocalRef(activity);
		return am;
	}

	explicit operator jobject()
	{
		return assetManager;
	};
private:
	jobject assetManager;
};

/*
 * Helper functions to aid new fusing method
 */

// This returns *global* reference, no need to free it.
static jobject getJavaAssetManager()
{
	static AssetManagerObject assetManager;
	return (jobject) assetManager;
}

static AAssetManager *getAssetManager()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	return AAssetManager_fromJava(env, (jobject) getJavaAssetManager());
}

namespace aasset
{

struct AssetInfo: public love::filesystem::physfs::PhysfsIo<AssetInfo>
{
	static const uint32_t version = 0;

	AAssetManager *assetManager;
	AAsset *asset;
	char *filename;
	size_t size;

	static AssetInfo *fromAAsset(AAssetManager *assetManager, const char *filename, AAsset *asset)
	{
		return new AssetInfo(assetManager, filename, asset);
	}

	int64_t read(void* buf, uint64_t len) const
	{
		int readed = AAsset_read(asset, buf, (size_t) len);

		PHYSFS_setErrorCode(readed < 0 ? PHYSFS_ERR_OS_ERROR : PHYSFS_ERR_OK);
		return (PHYSFS_sint64) readed;
	}

	int64_t write(const void* buf, uint64_t len) const
	{
		LOVE_UNUSED(buf);
		LOVE_UNUSED(len);

		PHYSFS_setErrorCode(PHYSFS_ERR_READ_ONLY);
		return -1;
	}

	int64_t seek(uint64_t offset) const
	{
		int64_t success = AAsset_seek64(asset, (off64_t) offset, SEEK_SET) != -1;

		PHYSFS_setErrorCode(success ? PHYSFS_ERR_OK : PHYSFS_ERR_OS_ERROR);
		return success;
	}

	int64_t tell() const
	{
		off64_t len = AAsset_getLength64(asset);
		off64_t remain = AAsset_getRemainingLength64(asset);

		return len - remain;
	}

	int64_t length() const
	{
		return AAsset_getLength64(asset);
	}

	int64_t flush() const
	{
		// Do nothing
		PHYSFS_setErrorCode(PHYSFS_ERR_OK);
		return 1;
	}

	AssetInfo *duplicate() const
	{
		AAsset *newAsset = AAssetManager_open(assetManager, filename, AASSET_MODE_RANDOM);

		if (newAsset == nullptr)
		{
			PHYSFS_setErrorCode(PHYSFS_ERR_OS_ERROR);
			return nullptr;
		}

		AAsset_seek64(asset, tell(), SEEK_SET);
		return fromAAsset(assetManager, filename, asset);
	}

	~AssetInfo() override
	{
		AAsset_close(asset);
		delete[] filename;
	}

private:
	AssetInfo(AAssetManager *assetManager, const char *filename, AAsset *asset)
	: assetManager(assetManager)
	, asset(asset)
	, size(strlen(filename) + 1)
	{
		this->filename = new (std::nothrow) char[size];
		memcpy(this->filename, filename, size);
	}
};

static std::unordered_map<std::string, PHYSFS_FileType> fileTree;

void *openArchive(PHYSFS_Io *io, const char *name, int forWrite, int *claimed)
{
	if (forWrite || io->opaque == nullptr || memcmp(io->opaque, "ASET", 4) != 0)
		return nullptr;

	// It's our archive
	*claimed = 1;
	AAssetManager *assetManager = getAssetManager();

	if (fileTree.empty())
	{
		// AAssetDir_getNextFileName intentionally excludes directories, so
		// we have to use JNI that calls AssetManager.list() recursively.
		JNIEnv *env = (JNIEnv *) SDL_AndroidGetJNIEnv();
		jobject activity = (jobject) SDL_AndroidGetActivity();
		jclass clazz = env->GetObjectClass(activity);

		jmethodID method = env->GetMethodID(clazz, "buildFileTree", "()[Ljava/lang/String;");
		jobjectArray list = (jobjectArray) env->CallObjectMethod(activity, method);

		for (jsize i = 0; i < env->GetArrayLength(list); i++)
		{
			jstring jstr = (jstring) env->GetObjectArrayElement(list, i);
			const char *str = env->GetStringUTFChars(jstr, nullptr);

			fileTree[str + 1] = str[0] == 'd' ? PHYSFS_FILETYPE_DIRECTORY : PHYSFS_FILETYPE_REGULAR;

			env->ReleaseStringUTFChars(jstr, str);
			env->DeleteLocalRef(jstr);
		}

		env->DeleteLocalRef(list);
		env->DeleteLocalRef(clazz);
		env->DeleteLocalRef(activity);
	}

	return assetManager;
}

PHYSFS_EnumerateCallbackResult enumerate(
	void *opaque,
	const char *dirname,
	PHYSFS_EnumerateCallback cb,
	const char *origdir,
	void *callbackdata
)
{
	using FileTreeIterator = std::unordered_map<std::string, PHYSFS_FileType>::iterator;
	LOVE_UNUSED(opaque);

	const char *path = dirname;
	if (path == nullptr || (path[0] == '/' && path[1] == 0))
		path = "";

	if (path[0] != 0)
	{
		FileTreeIterator result = fileTree.find(path);

		if (result == fileTree.end() || result->second != PHYSFS_FILETYPE_DIRECTORY)
		{
			PHYSFS_setErrorCode(PHYSFS_ERR_NOT_FOUND);
			return PHYSFS_ENUM_ERROR;
		}
	}

	JNIEnv *env = (JNIEnv *) SDL_AndroidGetJNIEnv();
	jobject assetManager = getJavaAssetManager();
	jclass clazz = env->GetObjectClass(assetManager);
	jmethodID method = env->GetMethodID(clazz, "list", "(Ljava/lang/String;)[Ljava/lang/String;");

	jstring jstringDir = env->NewStringUTF(path);
	jobjectArray dir = (jobjectArray) env->CallObjectMethod(assetManager, method, jstringDir);

	PHYSFS_EnumerateCallbackResult ret = PHYSFS_ENUM_OK;

	if (env->ExceptionCheck())
	{
		// IOException occured
		ret = PHYSFS_ENUM_ERROR;
		env->ExceptionClear();
	}
	else
	{
		jsize i = 0;
		jsize len = env->GetArrayLength(dir);

		while (ret == PHYSFS_ENUM_OK && i < len) {
			jstring jstr = (jstring) env->GetObjectArrayElement(dir, i++);
			const char *name = env->GetStringUTFChars(jstr, nullptr);

			ret = cb(callbackdata, origdir, name);

			env->ReleaseStringUTFChars(jstr, name);
			env->DeleteLocalRef(jstr);
		}

		env->DeleteLocalRef(dir);
	}

	env->DeleteLocalRef(jstringDir);
	env->DeleteLocalRef(clazz);
	return ret;
}

PHYSFS_Io *openRead(void *opaque, const char *name)
{
	AAssetManager *assetManager = (AAssetManager *) opaque;
	AAsset *file = AAssetManager_open(assetManager, name, AASSET_MODE_UNKNOWN);

	if (file == nullptr)
	{
		PHYSFS_setErrorCode(PHYSFS_ERR_NOT_FOUND);
		return nullptr;
	}

	PHYSFS_setErrorCode(PHYSFS_ERR_OK);
	return AssetInfo::fromAAsset(assetManager, name, file);
}

PHYSFS_Io *openWriteAppend(void *opaque, const char *name)
{
	LOVE_UNUSED(opaque);
	LOVE_UNUSED(name);

	// AAsset doesn't support modification
	PHYSFS_setErrorCode(PHYSFS_ERR_READ_ONLY);
	return nullptr;
}

int removeMkdir(void *opaque, const char *name)
{
	LOVE_UNUSED(opaque);
	LOVE_UNUSED(name);

	// AAsset doesn't support modification
	PHYSFS_setErrorCode(PHYSFS_ERR_READ_ONLY);
	return 0;
}

int stat(void *opaque, const char *name, PHYSFS_Stat *out)
{
	using FileTreeIterator = std::unordered_map<std::string, PHYSFS_FileType>::iterator;
	LOVE_UNUSED(opaque);

	FileTreeIterator result = fileTree.find(name);

	if (result != fileTree.end())
	{
		out->filetype = result->second;
		out->modtime = -1;
		out->createtime = -1;
		out->accesstime = -1;
		out->readonly = 1;

		PHYSFS_setErrorCode(PHYSFS_ERR_OK);
		return 1;
	}

	PHYSFS_setErrorCode(PHYSFS_ERR_NOT_FOUND);
	return 0;
}

void closeArchive(void *opaque)
{
	// Do nothing
	LOVE_UNUSED(opaque);
	PHYSFS_setErrorCode(PHYSFS_ERR_OK);
}

static PHYSFS_Archiver g_AAssetArchiver = {
	0,
	{
		"AASSET",
		"Android AAsset Wrapper",
		"LOVE Development Team",
		"https://developer.android.com/ndk/reference/group/asset",
		0
	},
	openArchive,
	enumerate,
	openRead,
	openWriteAppend,
	openWriteAppend,
	removeMkdir,
	removeMkdir,
	stat,
	closeArchive
};

static PHYSFS_sint64 dummyReturn0(PHYSFS_Io *io)
{
	LOVE_UNUSED(io);
	PHYSFS_setErrorCode(PHYSFS_ERR_OK);
	return 0;
}

static PHYSFS_Io *getDummyIO(PHYSFS_Io *io);

static char dummyOpaque[] = "ASET";
static PHYSFS_Io dummyIo = {
	0,
	dummyOpaque,
	nullptr,
	nullptr,
	[](PHYSFS_Io *io, PHYSFS_uint64 offset) -> int
	{
		PHYSFS_setErrorCode(offset == 0 ? PHYSFS_ERR_OK : PHYSFS_ERR_PAST_EOF);
		return offset == 0;
	},
	dummyReturn0,
	dummyReturn0,
	getDummyIO,
	nullptr,
	[](PHYSFS_Io *io) { LOVE_UNUSED(io); }
};

static PHYSFS_Io *getDummyIO(PHYSFS_Io *io)
{
	return &dummyIo;
}

}

static bool isVirtualArchiveInitialized = false;

bool initializeVirtualArchive()
{
	if (isVirtualArchiveInitialized)
		return true;

	if (!PHYSFS_registerArchiver(&aasset::g_AAssetArchiver))
		return false;
	if (!PHYSFS_mountIo(&aasset::dummyIo, "ASET.AASSET", nullptr, 0))
	{
		PHYSFS_deregisterArchiver(aasset::g_AAssetArchiver.info.extension);
		return false;
	}

	isVirtualArchiveInitialized = true;
	return true;
}

void deinitializeVirtualArchive()
{
	if (isVirtualArchiveInitialized)
	{
		PHYSFS_deregisterArchiver(aasset::g_AAssetArchiver.info.extension);
		isVirtualArchiveInitialized = false;
	}
}

bool checkFusedGame(void **physfsIO_Out)
{
	// TODO: Reorder the loading in 12.0
	PHYSFS_Io *&io = *(PHYSFS_Io **) physfsIO_Out;
	AAssetManager *assetManager = getAssetManager();

	// Prefer game.love inside assets/ folder
	AAsset *asset = AAssetManager_open(assetManager, "game.love", AASSET_MODE_RANDOM);
	if (asset)
	{
		io = aasset::AssetInfo::fromAAsset(assetManager, "game.love", asset);
		return true;
	}

	// If there's no game.love inside assets/ try main.lua
	asset = AAssetManager_open(assetManager, "main.lua", AASSET_MODE_STREAMING);

	if (asset)
	{
		AAsset_close(asset);
		io = nullptr;
		return true;
	}

	// Not found
	return false;
}

const char *getCRequirePath()
{
	static bool initialized = false;
	static const char *path = nullptr;

	if (!initialized)
	{
		JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
		jobject activity = (jobject) SDL_AndroidGetActivity();

		jclass clazz(env->GetObjectClass(activity));
		jmethodID method_id = env->GetMethodID(clazz, "getCRequirePath", "()Ljava/lang/String;");

		path = "";
		initialized = true;

		if (method_id)
		{
			jstring cpath = (jstring) env->CallObjectMethod(activity, method_id);
			const char *utf = env->GetStringUTFChars(cpath, nullptr);
			if (utf)
			{
				path = SDL_strdup(utf);
				env->ReleaseStringUTFChars(cpath, utf);
			}

			env->DeleteLocalRef(cpath);
		}
		else
		{
			// NoSuchMethodException is thrown in case methodID is null
			env->ExceptionClear();
			return "";
		}

		env->DeleteLocalRef(activity);
		env->DeleteLocalRef(clazz);
	}

	return path;
}

const char *getArg0()
{
	static PHYSFS_AndroidInit androidInit = {nullptr, nullptr};
	androidInit.jnienv = SDL_AndroidGetJNIEnv();
	androidInit.context = SDL_AndroidGetActivity();
	return (const char *) &androidInit;
}

} // android
} // love

extern "C" __attribute__((visibility("default")))
int love_android_secondary_ready()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");
	jmethodID m = env->GetStaticMethodID(activity, "hasSecondaryDisplay", "()Z");
	jboolean ready = JNI_FALSE;
	if (m)
		ready = env->CallStaticBooleanMethod(activity, m);
	else
		env->ExceptionClear();
	env->DeleteLocalRef(activity);
	return ready ? 1 : 0;
}

extern "C" __attribute__((visibility("default")))
void love_android_push_secondary(const void *rgba, int w, int h)
{
	if (!rgba || w <= 0 || h <= 0)
		return;
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");
	jmethodID m = env->GetStaticMethodID(activity, "updateSecondaryFrame", "(Ljava/nio/ByteBuffer;II)V");
	if (m)
	{
		jobject buf = env->NewDirectByteBuffer((void*) rgba, (jlong) w * (jlong) h * 4);
		env->CallStaticVoidMethod(activity, m, buf, w, h);
		env->DeleteLocalRef(buf);
	}
	else
		env->ExceptionClear();
	env->DeleteLocalRef(activity);
}

extern "C" __attribute__((visibility("default")))
void love_android_secondary_enable(int on)
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");
	jmethodID m = env->GetStaticMethodID(activity, "setSecondaryEnabled", "(Z)V");
	if (m)
		env->CallStaticVoidMethod(activity, m, on ? JNI_TRUE : JNI_FALSE);
	else
		env->ExceptionClear();
	env->DeleteLocalRef(activity);
}

extern "C" __attribute__((visibility("default")))
void love_android_secondary_target(int target)
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");
	jmethodID method = env->GetStaticMethodID(activity,
		"setSecondaryDisplayTarget", "(I)V");
	if (method)
		env->CallStaticVoidMethod(activity, method, target);
	else
		env->ExceptionClear();
	env->DeleteLocalRef(activity);
}

extern "C" __attribute__((visibility("default")))
int love_android_secondary_detected()
{
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");
	jmethodID method = env->GetStaticMethodID(activity,
		"hasSecondaryDisplayCandidate", "()Z");
	jboolean detected = JNI_FALSE;
	if (method)
		detected = env->CallStaticBooleanMethod(activity, method);
	else
		env->ExceptionClear();
	env->DeleteLocalRef(activity);
	return detected ? 1 : 0;
}

extern "C" __attribute__((visibility("default")))
int love_android_present_secondary(const void *rgba, int width, int height,
	unsigned int background, int cover)
{
	if (!rgba || width <= 0 || height <= 0)
		return 0;
	jlong size = (jlong) width * (jlong) height * 4;
	if (size <= 0)
		return 0;
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");
	jmethodID method = env->GetStaticMethodID(activity, "presentSecondaryFrame",
		"(Ljava/nio/ByteBuffer;IIIZ)Z");
	if (!method)
	{
		env->ExceptionClear();
		env->DeleteLocalRef(activity);
		return 0;
	}
	jobject frame = env->NewDirectByteBuffer((void *) rgba, size);
	if (!frame)
	{
		env->DeleteLocalRef(activity);
		return 0;
	}
	jboolean shown = env->CallStaticBooleanMethod(activity, method, frame,
		width, height, (jint) background, cover ? JNI_TRUE : JNI_FALSE);
	env->DeleteLocalRef(frame);
	env->DeleteLocalRef(activity);
	return shown ? 1 : 0;
}

extern "C" __attribute__((visibility("default")))
const char *love_android_poll_secondary_touch()
{
	static thread_local std::string event;
	event.clear();
	JNIEnv *env = (JNIEnv*) SDL_AndroidGetJNIEnv();
	jclass activity = env->FindClass("org/love2d/android/GameActivity");
	jmethodID method = env->GetStaticMethodID(activity, "pollSecondaryDisplayTouch",
		"()Ljava/lang/String;");
	if (!method)
		env->ExceptionClear();
	else
	{
		jstring value = (jstring) env->CallStaticObjectMethod(activity, method);
		if (value)
		{
			const char *utf = env->GetStringUTFChars(value, nullptr);
			if (utf)
			{
				event = utf;
				env->ReleaseStringUTFChars(value, utf);
			}
			env->DeleteLocalRef(value);
		}
	}
	env->DeleteLocalRef(activity);
	return event.empty() ? nullptr : event.c_str();
}

static love::audio::openal::Audio *love_android_openal_audio()
{
	love::audio::Audio *audio = love::Module::getInstance<love::audio::Audio>(love::Module::M_AUDIO);

	if (audio == nullptr)
		return nullptr;

	const char *name = audio->getName();

	if (name == nullptr || strcmp(name, "love.audio.openal") != 0)
		return nullptr;

	return (love::audio::openal::Audio *) audio;
}

extern "C" JNIEXPORT void JNICALL
Java_org_love2d_android_GameActivity_nativeAudioFocusLost(JNIEnv *env, jclass cls)
{
	(void) env;
	(void) cls;

	love::audio::openal::pushAudioSuspendEvent();

	love::audio::openal::Audio *audio = love_android_openal_audio();

	if (audio != nullptr)
		audio->pauseContext();
}

extern "C" JNIEXPORT void JNICALL
Java_org_love2d_android_GameActivity_nativeAudioFocusGained(JNIEnv *env, jclass cls)
{
	(void) env;
	(void) cls;

	love::audio::openal::Audio *audio = love_android_openal_audio();

	if (audio == nullptr)
		return;

	audio->resumeContext();

	if (!audio->isDeviceConnected())
		audio->reopenDevice();

	love::audio::openal::pushAudioResetEvent();
}

extern "C" JNIEXPORT void JNICALL
Java_org_love2d_android_GameActivity_nativeAudioDeviceChanged(JNIEnv *env, jclass cls)
{
	(void) env;
	(void) cls;

	love::audio::openal::Audio *audio = love_android_openal_audio();

	if (audio == nullptr)
		return;

	audio->pauseContext();
	audio->reopenDevice();
	audio->resumeContext();

	love::audio::openal::pushAudioResetEvent();
}

static void pushGameIntentEvent(const char *game)
{
	auto eventmodule = love::Module::getInstance<love::event::Event>(love::Module::M_EVENT);
	if (eventmodule == nullptr || game == nullptr)
		return;

	std::vector<love::Variant> args;
	args.push_back(love::Variant(std::string(game)));

	love::event::Message *msg = new love::event::Message("intent_game", args);
	eventmodule->push(msg);
	msg->release();
}

extern "C" JNIEXPORT void JNICALL
Java_org_love2d_android_GameActivity_nativeOnGameIntent(JNIEnv *env, jclass cls, jstring game)
{
	(void) cls;
	if (game == nullptr)
		return;
	const char *str = env->GetStringUTFChars(game, nullptr);
	if (str != nullptr)
	{
		pushGameIntentEvent(str);
		env->ReleaseStringUTFChars(game, str);
	}
}

#endif // LOVE_ANDROID
