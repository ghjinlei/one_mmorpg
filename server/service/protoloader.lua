local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local sprotoparser = require "sprotoparser"

local proto_conf = require "common.sproto.proto_conf"

skynet.start(function()
	sprotoloader.save(sprotoparser.parse(proto_conf.c2s), 1)
	sprotoloader.save(sprotoparser.parse(proto_conf.s2c), 2)

	skynet.error("protoloader.lua finish")
	-- don't call skynet.exit() , because sproto.core may unload and the global slot become invalid
end)
