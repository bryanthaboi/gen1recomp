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

int w_createFile(lua_State *L)
{
	const char *suggested = luaL_optstring(L, 1, nullptr);
	luax_pushboolean(L, instance()->createFile(suggested));
	return 1;
}

int w_hasSecondaryDisplay(lua_State *L)
{
	luax_pushboolean(L, instance()->hasSecondaryDisplay());
	return 1;
}

// pixels: a string of raw RGBA8 bytes, e.g. from
// canvas:newImageData():getString() -- exactly w*h*4 bytes, or this
// returns false without sending anything.
int w_presentUIFrame(lua_State *L)
{
	size_t len = 0;
	const char *pixels = luaL_checklstring(L, 1, &len);
	int w = (int) luaL_checkinteger(L, 2);
	int h = (int) luaL_checkinteger(L, 3);
	luax_pushboolean(L, instance()->presentUIFrame(std::string(pixels, len), w, h));
	return 1;
}

// Returns a table {action=0|1|2|3, x=.., y=..} for the oldest pending
// second-screen touch (action: 0 down, 1 move, 2 up, 3 cancel; x/y in the
// same pixel space as the w/h the last presentUIFrame call used), or nil
// if none is queued. Callers should loop until nil since more than one
// touch can queue between polls.
int w_pollSecondScreenTouch(lua_State *L)
{
	int action = 0;
	float x = 0, y = 0;
	if (!instance()->pollSecondScreenTouch(action, x, y))
	{
		lua_pushnil(L);
		return 1;
	}
	lua_newtable(L);
	lua_pushinteger(L, action);
	lua_setfield(L, -2, "action");
	lua_pushnumber(L, x);
	lua_setfield(L, -2, "x");
	lua_pushnumber(L, y);
	lua_setfield(L, -2, "y");
	return 1;
}

int w_hasBackgroundMusic(lua_State *L)
{
	lua_pushboolean(L, instance()->hasBackgroundMusic());
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
	{ "createFile", w_createFile },
	{ "hasSecondaryDisplay", w_hasSecondaryDisplay },
	{ "presentUIFrame", w_presentUIFrame },
	{ "pollSecondScreenTouch", w_pollSecondScreenTouch },
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
