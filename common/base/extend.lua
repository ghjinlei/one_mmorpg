--[[
ModuleName :
Path : extend.lua
Author : jinlei
CreateTime : 2019-05-21 11:48:30
Description :
--]]
local string = string
local table = table
local math = math

function string.split(str, sep, num)
	assert(not num or num > 0)
	sep = sep or " "
	local list = {}
	local count = 0
	for substr in string.gmatch(str, "[^" .. sep .. "]+") do
		table.insert(list, substr)
		count = count + 1
		if num and count >= num then
			break
		end
	end
	return list
end

function table.copy(tbl)
	local new_tbl = {}
	for k, v in pairs(tbl) do
		new_tbl[k] = v
	end
	return new_tbl
end

function table.reverse(arr)
	local size = #arr
	for i = 1, math.floor(size / 2) do
		t = arr[i]
		arr[i] = arr[size + 1 - i]
		arr[size + 1 - i] = t
	end
	return arr
end

-- 有序遍历
function pairs_orderly(tbl, comp)
	local keys = {}
	for k, v in pairs(tbl) do
		table.insert(keys, k)
	end
	table.sort(keys, comp)
	local index = 0
	local keys_count = #keys
	local next_orderly = function()
		index = index + 1
		if index > keys_count then return end
		return keys[index], tbl[keys[index]]
	end
	return next_orderly
end

function math.checkbit(num, pos)
	local mask = math.pow(2, pos)
	return math.floor(num / mask) % 2 == 1
end

function math.setbit(num, pos)
	local mask = math.pow(2, pos)
	if not math.checkbit(num, pos) then
		num = num + mask
	end
	return num
end

function math.unsetbit(num, pos)
	local mask = math.pow(2, pos)
	if math.checkbit(num, pos) then
		num = num - mask
	end
end

