-- Squirrel and other frontends load this file when a schema names a Lua component.
-- 合成的测试样本：新版 librime-lua 也可以在方案里直接写 lua_translator@*date_translator。
date_translator = require("date_translator")
