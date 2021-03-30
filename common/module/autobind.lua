--[[
ModuleName :
Path : ../common/module/autobind.lua
Author : jinlei
CreateTime : 2020-12-01 11:50:54
Description :
--]]

--[[
bindmap = {
	key = {
		OT = OT_NUM,
		OP = {get = get, set = set, add = add, sub = sub},
	}
}
--]]

local function get(key, keydata)
	local fieldtype = keydata.FT or FT_TEMP
	return function(self)
		local fieldmap = rawget(self, fieldtype)
		if not fieldmap then
			return
		end
		return rawget(fieldmap, key)
	end
end

local function getfrom(key, keydata)
	local fieldtype = keydata.FT or FT_TEMP
	return function(self, index)
		local fieldmap = rawget(self, fieldtype)
		if not fieldmap then
			return
		end
		local tbl = rawget(fieldmap, key)
		if not tbl then
			return
		end
		return rawget(tbl, index)
	end
end

local function set(key, keydata)
	local fieldtype = keydata.FT or FT_TEMP
	return function(self, value)
		local fieldmap = rawget(self, fieldtype)
		if not fieldmap then
			return
		end
		return rawset(fieldmap, key, value)
	end
end

local function setinto(key, keydata)
	local fieldtype = keydata.FT or FT_TEMP
	return function(self, index, value)
		local fieldmap = rawget(self, fieldtype)
		if not fieldmap then
			return
		end
		local tbl = rawget(self, key)
		if not tbl then
			tbl = {}
			rawset(self, key, tbl)
		end
		return rawset(tbl, index, value)
	end
end

local OP_MAP = {
	[OT_NUM]   = {get = get, set = set, add = add, sub = sub},
	[OT_TABLE] = {get = get, getfrom = getfrom, set = set, setinto = setinto},
	[OT_ANY]   = {get = get, set = set},
}
local function get_default_op(type_)
	return OP_MAP[type_] or OP_MAP[OT_ANY]
end

local function gen_opmap(keydata)
	local op = {}
	table.merge(op, get_default_op(keydata.OT))
	table.merge(op, keydata.OP)
	return op
end

local function appendkey(class, key, keydata)
	local bindmap = class.__bindmap
	assert(not bindmap[key])

	bindmap[key] = keydata

	local opmap = gen_opmap(keydata)
	for opkey, func in pairs(opmap) do
		local funcname = string.format("%s_%s", opkey, key)
		class[funcname] = func
	end
end

function bind(class, bindmap)
	for key, keydata in pairs(bindmap) do
		appendkey(class, key, keydata)
	end
end

function Object:init_by_data(data)
	for k, v in pairs(data) do
		local setfunc = self[string.format("set_%s", k)]
		if setfunc then
			setfunc(data)
		end
	end
end

