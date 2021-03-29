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

config.dbserver = {}
config.dbserver.db_name = tostring(config.server.host_id)

config.log = {}
config.log.level = 1
config.log.level_for_console = 1
config.log.dir = "../log"
config.log.cache_count = 1
config.log.time_format = "%Y%m%d %H:%M:%S"

return config

