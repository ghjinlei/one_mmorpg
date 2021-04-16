--[[
ModuleName :
Path : service/agent.lua
Author : jinlei
CreateTime : 2021-04-14 20:07:16
Description :
--]]

local skynet = require "skynet"
local sproto_helper = require "common.utils.sproto_helper"
local skynet_helper = require "common.utils.skynet_helper"
dofile("lualib/common/base/preload.lua")

MAIN = import("lualib/agent/main.lua")
MAIN.gate = ...

skynet.start(function()
	sproto_helper.load(1)
	skynet_helper.dispatch_lua_cmds()
end)
