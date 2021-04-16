--[[
ModuleName :
Path : proto_conf.lua
Author : jinlei
CreateTime : 2021-03-29 20:52:45
Description :
--]]
local conf = {}

conf.c2s = [[
.package {
	type    0 : integer
	session 1 : integer
}

AUTH_handshake 1 {
	request {
		operator      0 : integer
		channel       1 : integer
		platform      2 : integer
		openid        3 : string
		appid         4 : string
		os            5 : string
		imei          6 : string
		idfa          7 : string
	}
	response {
		code          0 : integer
		msg           1 : string
		salt          2 : string
		patch         3 : string
		server_sec    4 : integer
		server_usec   5 : integer
		server_tzone  6 : integer
	}
}

AUTH_auth 2 {
	request {
		data          0 : string
	}
	response {
		code          0 : integer
		msg           1 : string
	}
}

]]

conf.s2c = [[
.package {
	type    0 : integer
	session 1 : integer
}
]]

return conf
