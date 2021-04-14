--[[
ModuleName :
Path : service/database.lua
Author : jinlei
CreateTime : 2021-04-14 10:46:38
Description :
--]]

local skynet = require "skynet"
local mongo = require "skynet.db.mongo"
local skynet_helper = require "common.utils.skynet_helper"
local logger = require "common.utils.logger"
dofile("script/lualib/common/base/preload.lua")

local client = nil
local the_db = nil
local collections = {}

local function get_collection(name)
	local collection = collections[name]
	if not collection then
		collection = the_db.get_collection(name)
		collections[name] = collection
	end
	return collection
end

local function collection_query(name, action, ...)
	assert(the_db, "database.collection_query,msg=no the_db")

	local collection = get_collection(name)
	assert(the_db, string.format("database.collection_query,msg=no collection(%s)", name))

	return collection[action](collection, ...)
end


local CMD = {}

function CMD.open(conf_list, dbname)
	client = mongo.client({rs = conf_list})

	local conf = conf_list[1]
	if not client then
		logger.debugf("database.cmd.open,host=%s,port=%s,username=%s,dbname=%s,msg=failed to connect server.", tostring(conf.host), tostring(conf.port), tostring(conf.username), tostring(dbname))
		return false
	end

	the_db = client:getDB(dbname)
	if not the_db then
		client:disconnect()
		client = nil
		logger.debugf("database.cmd.open,host=%s,port=%s,username=%s,dbname=%s,msg=failed to get_db.", tostring(conf.host), tostring(conf.port), tostring(conf.username), tostring(dbname))
		return false
	end

	return true
end

function CMD.close()
	the_db = nil
	collections = {}

	if client then
		client:disconnect()
		client = nil
	end
end

local collection2index { 
-- [collection_name] = {field_name, ...}
}
function CMD.ensure_indexs()
	for name, idx in pairs(collection2index) do
		local collection = get_collection(name)
		if not collection then
			return false, string.format("database.cmd.ensure_indexs,msg=no collection(%s)", tostring(name))
		end
		collection:ensure_indexs(idx)
	end
	return true
end

function CMD.find_one(name, query, selector)
	local ret = collection_query(name, "findOne", query, selector)
	return ret
end

function CMD.find_one_by_id(name, id, selector)
	local ret = collection_query(name, "findOne", {_id = id}, selector)
	return ret
end

function CMD.find_all(name, query, selector)
	local cursor = collection_query(name, "find", query, selector)
	
	local ret_list = {}
	while cursor:hasNext() do
		local ret = cursor:next()
		table.insert(ret_list, ret)
	end
	cursor:close()

	return ret_list
end

function CMD.count(name, selector)
	return collection_query(name, "find", selector)
end

function CMD.insert(name, data)
	return collection_query(name, "insert", data)
end

function CMD.update(name, selector, update, upsert, multi)
	return collection_query(name, "update", selector, update, upsert, multi)
end

function CMD.update_by_id(name, id, update, upsert, multi)
	return collection_query(name, "update", {_id = id}, update, upsert, multi)
end

function CMD.delete(name, selector)
	return CMD.collection_query(name, "delete", selector)
end

function CMD.drop(name)
	local collection = get_collection(name)
	assert(collection, string.format("database.cmd.drop no collection(%s)", name))
	return collection_query(name, "drop")
end

skynet.start(function()
	skynet_helper.register_lua_cmds(CMD)
	skynet_helper.dispatch_lua_cmds()
end)
