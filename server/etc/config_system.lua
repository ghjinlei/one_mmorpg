--[[
ModuleName :
Path : config_system.lua
Author : jinlei
CreateTime : 2020-10-05 23:52:31
Description :
--]]
local config = {}

config.server = {}
config.server.host_id = 1001
config.server.host_name = "1001"
config.server.debug_console_port = 9001

config.gate = {}
config.gate.listen_addr = "127.0.0.1:8001"

config.dbserver = {}
config.dbserver.db_name = tostring(config.server.host_id)

config.log = {}
config.log.level = 1
config.log.level_for_console = 1
config.log.dir = "../log"
config.log.cache_count = 1
config.log.time_format = "%Y%m%d %H:%M:%S"

config.agentmgr = {}
config.agentmgr.max_agent_count = 5000
config.agentmgr.pre_alloc_agent_count = 1000
config.agentmgr.agent_per_database = 100
config.agentmgr.max_enter_per_batch = 100

return config

