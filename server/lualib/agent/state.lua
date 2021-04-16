--[[
ModuleName : AGENT_STATE
Path : lualib/agent/state.lua
Author : jinlei
CreateTime : 2021-04-16 16:50:40
Description :
--]]

local skynet = require "skynet"
local logger = require "common.utils.logger"
local config_agent = require "config_system".agent


-- 从数据库加载数据
local LoadingAccount = {}


local states = {
	loading_account = loading_account,
	loading_character = {},
	waiting_character_choice = {},
	creating_character = {},
	deleting_character = {},
	entering_game = {},
	reentering_game = {},
	gaming = {},
}
