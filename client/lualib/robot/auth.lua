--[[
ModuleName :
Path : ../lualib/robot/auth.lua
Author : jinlei
CreateTime : 2020-03-23 16:28:18
Description :
--]]

local skynet = require "skynet"
local sproto_helper = require "common.utils.sproto_helper"

local auth_data = {
	openid = nil,
	characterid = nil,
}

function set_openid(openid)
	auth_data.openid = openid
end

function set_openkey(openkey)
	auth_data.openkey = openkey
end

function set_characterid(characterid)
	auth_data.characterid = characterid
end

local function get_login_data()
	local data = {
		operator      = 0,
		channel       = 0,
		platform      = 0,
		openid        = auth_data.openid,
		appId         = "appid_robot",
		os            = "ios",
		imei          = "imei_robot",
		idfa          = "idfa_robot",
	}
	return data
end

function login(host, port)
	NETWORK.connect(host, port)

	local login_data = get_login_data()
	NETWORK.send_request("AUTH_handshake", login_data, function(args)
		local salt = args.salt
		skynet.error("AUTH_handshake callback!")

		NETWORK.send_request("AUTH_auth", {}, function(args)
			skynet.error("AUTH_auth callback!")
			if args.code ~= 0 then
				skynet.error("login failed!")
			else
				skynet.error("login success!")
			end
		end)
	end)
end

local msgHandlers = {}

function __init__(module, updated)
	sproto_helper.reg_msghandlers(msgHandlers)
end

