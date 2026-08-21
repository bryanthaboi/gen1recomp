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

// LOVE
#include "wrap_System.h"
#include "sdl/System.h"

#include <string>
#include <vector>

namespace love
{
namespace system
{

#define instance() (Module::getInstance<System>(Module::M_SYSTEM))

int w_getOS(lua_State *L)
{
	luax_pushstring(L, instance()->getOS());
	return 1;
}

int w_getProcessorCount(lua_State *L)
{
	lua_pushinteger(L, instance()->getProcessorCount());
	return 1;
}

int w_setClipboardText(lua_State *L)
{
	const char *text = luaL_checkstring(L, 1);
	luax_catchexcept(L, [&]() { instance()->setClipboardText(text); });
	return 0;
}

int w_getClipboardText(lua_State *L)
{
	std::string text;
	luax_catchexcept(L, [&]() { text = instance()->getClipboardText(); });
	luax_pushstring(L, text);
	return 1;
}

int w_getPowerInfo(lua_State *L)
{
	int seconds = -1, percent = -1;
	const char *str;

	System::PowerState state = instance()->getPowerInfo(seconds, percent);

	if (!System::getConstant(state, str))
		str = "unknown";

	lua_pushstring(L, str);

	if (percent >= 0)
		lua_pushinteger(L, percent);
	else
		lua_pushnil(L);

	if (seconds >= 0)
		lua_pushinteger(L, seconds);
	else
		lua_pushnil(L);

	return 3;
}

int w_openURL(lua_State *L)
{
	std::string url = luax_checkstring(L, 1);
	luax_pushboolean(L, instance()->openURL(url));
	return 1;
}

int w_vibrate(lua_State *L)
{
	double seconds = luaL_optnumber(L, 1, 0.5);
	instance()->vibrate(seconds);
	return 0;
}

int w_pickFile(lua_State *L)
{
	const char *kind = luaL_optstring(L, 1, nullptr);
	luax_pushboolean(L, instance()->pickFile(kind));
	return 1;
}

int w_pickFileKinds(lua_State *L)
{
	luax_pushstring(L, instance()->pickFileKinds());
	return 1;
}

int w_createFile(lua_State *L)
{
	const char *suggested = luaL_optstring(L, 1, nullptr);
	luax_pushboolean(L, instance()->createFile(suggested));
	return 1;
}

int w_syncHealthSteps(lua_State *L)
{
	luax_pushboolean(L, instance()->syncHealthSteps());
	return 1;
}

int w_restartApp(lua_State *L)
{
	// Does not return on success: GameActivity.restartApp exits the process
	// after scheduling the relaunch (#575).
	luax_pushboolean(L, instance()->restartApp());
	return 1;
}

int w_installApk(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	luax_pushboolean(L, instance()->installApk(path));
	return 1;
}

int w_httpDownload(lua_State *L)
{
	const char *url = luaL_checkstring(L, 1);
	const char *dest = luaL_checkstring(L, 2);
	const char *ua = luaL_optstring(L, 3, nullptr);
	const char *accept = luaL_optstring(L, 4, nullptr);
	luax_pushboolean(L, instance()->httpDownload(url, dest, ua, accept));
	return 1;
}

int w_httpPost(lua_State *L)
{
	const char *url = luaL_checkstring(L, 1);
	size_t bodyLen = 0;
	const char *body = luaL_checklstring(L, 2, &bodyLen);
	const char *ct = luaL_optstring(L, 3, nullptr);
	const char *ua = luaL_optstring(L, 4, nullptr);
	luax_pushboolean(L, instance()->httpPost(url, body, (int) bodyLen, ct, ua));
	return 1;
}

/*
 * love.system.httpRequest(url, method, headers, body, userAgent) -> envelope
 *
 * `headers` is a flat array of alternating header name and value strings, so
 * it maps straight onto the Java bridge's String[] without any parsing here.
 * The single return is the response envelope -- a head line of
 * "STATUS <code>" or "ERROR <text>", a newline, then the raw body -- or nil
 * where the build has no bridge, which src/core/HostShell.lua turns into an
 * "update the app" notice rather than a failed request.
 */
int w_httpRequest(lua_State *L)
{
	const char *url = luaL_checkstring(L, 1);
	const char *method = luaL_optstring(L, 2, "GET");

	std::vector<std::string> fields;
	if (!lua_isnoneornil(L, 3))
	{
		luaL_checktype(L, 3, LUA_TTABLE);
		size_t count = luax_objlen(L, 3);
		for (size_t i = 1; i <= count; i++)
		{
			lua_rawgeti(L, 3, (int) i);
			const char *field = lua_tostring(L, -1);
			fields.push_back(field != nullptr ? field : "");
			lua_pop(L, 1);
		}
	}
	std::vector<const char *> pairs;
	for (size_t i = 0; i < fields.size(); i++)
		pairs.push_back(fields[i].c_str());

	size_t bodyLen = 0;
	const char *body = nullptr;
	if (!lua_isnoneornil(L, 4))
		body = luaL_checklstring(L, 4, &bodyLen);
	const char *ua = luaL_optstring(L, 5, nullptr);

	std::string out;
	bool ok = instance()->httpRequest(url, method,
		pairs.empty() ? nullptr : &pairs[0], (int) pairs.size(),
		body, (int) bodyLen, ua, out);
	if (!ok)
	{
		lua_pushnil(L);
		return 1;
	}
	lua_pushlstring(L, out.data(), out.size());
	return 1;
}

int w_hasBackgroundMusic(lua_State *L)
{
	lua_pushboolean(L, instance()->hasBackgroundMusic());
	return 1;
}

/*
 * TLS sockets. Deliberately a handle-and-poll API rather than an object:
 * the caller is a per-frame pump that must never block, and everything with
 * a thread behind it lives on the Java side.
 */
int w_tlsOpen(lua_State *L)
{
	const char *host = luaL_checkstring(L, 1);
	int port = (int) luaL_checknumber(L, 2);
	lua_pushnumber(L, instance()->tlsOpen(host, port));
	return 1;
}

int w_tlsStatus(lua_State *L)
{
	int handle = (int) luaL_checknumber(L, 1);
	lua_pushnumber(L, instance()->tlsStatus(handle));
	return 1;
}

int w_tlsSend(lua_State *L)
{
	int handle = (int) luaL_checknumber(L, 1);
	size_t length = 0;
	const char *data = luaL_checklstring(L, 2, &length);
	lua_pushnumber(L, instance()->tlsSend(handle, data, (int) length));
	return 1;
}

int w_tlsReceive(lua_State *L)
{
	int handle = (int) luaL_checknumber(L, 1);
	int max = (int) luaL_optnumber(L, 2, 8192);
	if (max <= 0)
	{
		lua_pushliteral(L, "");
		return 1;
	}
	// A frame's worth of a busy room, on the C stack rather than the heap:
	// this runs every frame and an allocation per poll is not worth it.
	if (max > 65536)
		max = 65536;
	char buf[65536];
	int got = instance()->tlsReceive(handle, buf, max);
	if (got < 0)
	{
		lua_pushnil(L);
		return 1;
	}
	lua_pushlstring(L, buf, (size_t) got);
	return 1;
}

int w_tlsError(lua_State *L)
{
	int handle = (int) luaL_checknumber(L, 1);
	char buf[512];
	if (!instance()->tlsError(handle, buf, (int) sizeof(buf)))
	{
		lua_pushnil(L);
		return 1;
	}
	lua_pushstring(L, buf);
	return 1;
}

int w_tlsClose(lua_State *L)
{
	int handle = (int) luaL_checknumber(L, 1);
	instance()->tlsClose(handle);
	return 0;
}

int w_updateShortcuts(lua_State *L)
{
	if (!lua_istable(L, 1))
		return luaL_error(L, "Expected table of game version strings");

	std::vector<std::string> versions;
	int len = (int) luax_objlen(L, 1);
	for (int i = 1; i <= len; ++i)
	{
		lua_rawgeti(L, 1, i);
		if (lua_isstring(L, -1))
			versions.push_back(lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	luax_pushboolean(L, instance()->updateShortcuts(versions));
	return 1;
}

int w_getLaunchGame(lua_State *L)
{
	std::string game = instance()->getLaunchGame();
	if (game.empty())
		lua_pushnil(L);
	else
		luax_pushstring(L, game);
	return 1;
}

static const luaL_Reg functions[] =
{
	{ "getOS", w_getOS },
	{ "getProcessorCount", w_getProcessorCount },
	{ "setClipboardText", w_setClipboardText },
	{ "getClipboardText", w_getClipboardText },
	{ "getPowerInfo", w_getPowerInfo },
	{ "openURL", w_openURL },
	{ "vibrate", w_vibrate },
	{ "pickFile", w_pickFile },
	{ "pickFileKinds", w_pickFileKinds },
	{ "createFile", w_createFile },
	{ "syncHealthSteps", w_syncHealthSteps },
	{ "restartApp", w_restartApp },
	{ "installApk", w_installApk },
	{ "updateShortcuts", w_updateShortcuts },
	{ "getLaunchGame", w_getLaunchGame },
	{ "httpDownload", w_httpDownload },
	{ "httpPost", w_httpPost },
	{ "httpRequest", w_httpRequest },
	{ "tlsOpen", w_tlsOpen },
	{ "tlsStatus", w_tlsStatus },
	{ "tlsSend", w_tlsSend },
	{ "tlsReceive", w_tlsReceive },
	{ "tlsError", w_tlsError },
	{ "tlsClose", w_tlsClose },
	{ "hasBackgroundMusic", w_hasBackgroundMusic },
	{ 0, 0 }
};

extern "C" int luaopen_love_system(lua_State *L)
{
	System *instance = instance();
	if (instance == nullptr)
	{
		instance = new love::system::sdl::System();
	}
	else
		instance->retain();

	WrappedModule w;
	w.module = instance;
	w.name = "system";
	w.type = &Module::type;
	w.functions = functions;
	w.types = nullptr;

	return luax_register_module(L, w);
}

} // system
} // love
