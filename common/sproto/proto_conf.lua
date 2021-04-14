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
]]

conf.s2c = [[
.package {
	type    0 : integer
	session 1 : integer
}
]]

return conf
