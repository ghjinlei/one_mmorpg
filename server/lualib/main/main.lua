--[[
ModuleName :
Path : main.lua
Author : jinlei
CreateTime : 2021-03-29 19:22:40
Description :
--]]
local skynet = require "skynet"
local skynet_helper = require "common.utils.skynet_helper"
local config_system = require "config_system"
local config_server = config_system.server
local config_auth = config_system.auth

debug_console = false
protoloader = false
gate = false
agentmgr = false
auth_list = {}

function main()
	debug_console = skynet.uniqueservice("debug_console", config_server.debug_console_port)

	protoloader = skynet.uniqueservice("protoloader")

	gate = skynet.newservice("gate")
--
	agentmgr = skynet.newservice("agentmgr", gate)

	-- 启动多个auth
	for i = 1, config_auth.auth_count do
		local auth = skynet.newservice("auth", gate, agentmgr)
		table.insert(auth_list, auth)
	end
	skynet.call(gate, "lua", "set_auth_list", auth_list)
--
	skynet.call(agentmgr, "lua", "start")
--
	skynet.call(gate, "lua", "open")
end

local CMD = {}
function CMD.hotfix()

end

function CMD.shutdown()

end

function CMD.kick_all_users()

end

function __init__(module)
	skynet_helper.register_lua_cmds(CMD)
end

