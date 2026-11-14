"""Exercise Super gestures without starting a compositor or touching the desktop."""

import ctypes
from pathlib import Path
import unittest


class PillTests(unittest.TestCase):
    def test_super_gestures(self):
        try:
            lua = ctypes.CDLL("liblua-5.4.so")
        except OSError:
            self.skipTest("Lua 5.4 runtime is unavailable")
        lua.luaL_newstate.restype = ctypes.c_void_p
        lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                                 ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
        lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lua.lua_tolstring.restype = ctypes.c_char_p
        lua.lua_close.argtypes = [ctypes.c_void_p]
        root = Path(__file__).resolve().parent
        script = f'assert(loadfile([[{root / "pill.lua"}]]))([[{root.parent / "config/modules/pill.lua"}]])'
        state = lua.luaL_newstate()
        try:
            lua.luaL_openlibs(state)
            status = lua.luaL_loadstring(state, script.encode())
            if not status:
                status = lua.lua_pcallk(state, 0, 0, 0, 0, None)
            self.assertEqual(status, 0, lua.lua_tolstring(state, -1, None))
        finally:
            lua.lua_close(state)
