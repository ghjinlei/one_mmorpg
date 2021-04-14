local skynet = require "skynet"
require "skynet.manager"	-- import skynet.register
local skynet_helper = require "common.utils.skynet_helper"
local logger = require "common.utils.logger"
dofile("lualib/common/base/preload.lua")

MAIN = import("lualib/main/main.lua")

skynet.start(function()
	xpcall(MAIN.main, function(err)
		local err = debug.traceback(err)
		print(err)
		os.exit()
	end)

	skynet_helper.dispatch_lua_cmds()
	skynet.register ".main"
end)
