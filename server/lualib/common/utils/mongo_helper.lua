--[[
ModuleName :
Path : lualib/common/utils/mongo_helper.lua
Author : jinlei
CreateTime : 2020-07-05 13:52:07
Description :
--]]

local mongo_helper = {}

local key_chain_list = {

}

local collection_name2key_map = false
local function init_collection_name2key_map()
	collection_name2key_map = {}
	for _, key_chain in ipairs(key_chain_list) do
		local key_list = string.split(key_chain, ".")
		local size = #key_list
		local key_map = collection_name2key_map
		for idx, key in ipairs(key_list) do
			local subkeymap = key_map[key]
			if not subkeymap then
				if idx < size then
					subkeymap = {}
				else
					subkeymap = 1
				end
				key_map[key] = subkeymap
			end
		end
	end
end
init_collection_name2key_map()

local function convert_key(tbl, key_map, convfunc)
	convfunc = convfunc or tonumber

	for key, subkeymap in pairs(key_map) do
		local convkeys = {}
		if key == "*" then
			convkeys = table.keys(tbl)
		elseif tbl[key] then
			table.insert(convkeys, key)
		end

		for _, convkey in ipairs(convkeys) do
			local subtbl = tbl[convkey]
			if subkeymap == 1 then
				for k, v in pairs(subtbl) do
					subtbl[k] = nil
					subtbl[convfunc(k)] = v
				end
			else
				convert_key(subtbl, subkeymap, convfunc)
			end
		end
	end
end

function mongo_helper.mongo2lua(name, tbl)
	local key_map = collection_name2key_map[name]
	if not key_map then
		return tbl
	end
	return convert_key(tbl, key_map, tonumber)
end

return mongo_helper
