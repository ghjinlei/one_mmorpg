local __global_listener_map__ = {
--[[
	[subject] = {
		[type#key] = listener_list,
	}
--]]
}

local global_observer = {}
function get_global_observer()
	return global_observer
end

local global_subject = {}
function get_global_subject()
	return global_subject
end

local KEY_ALL = "*"
--{{ begin of Event
local Event = {}
local eventclass_mt = {__index = Event}
function Event.create(subject, type, key, data)
	local o = {
		subject or get_global_subject(),
		type,
		key or KEY_ALL,
		data,
	}
	setmetatable(o, eventclass_mt)
	return o
end

function Event:get_subject()       return self[1] end
function Event:get_type()         return self[2] end
function Event:get_key()          return self[3] end
function Event:get_data()         return self[4] end
--}} end of Event

local next_listenerid = 0
local function gen_listenerid()
	next_listenerid = next_listenerid + 1
	return next_listenerid
end

local function gen_typekey(type, key)
	return string.format("%s#%s", type, key)
end

--{{ begin of Listener
local Listener = {}
local listenerclass_mt = {__index = Listener}
function Listener.create(observer, subject, type, key, callback)
	local oid = gen_listenerid()
	local listener =  {
		observer,
		subject,
		type,
		key,
		callback,
		oid,
	}
	setmetatable(listener, listenerclass_mt)

	local typelistener_map = get_subtable_with_default(__global_listener_map__, subject)
	local typekey = gen_typekey(type, key)
	local listener_list = get_subtable_with_default(typelistener_map, typekey)
	table.insert(listener_list, listener)

	if is_table(observer) then
		local objlistener_map = get_subtable_with_default(observer, "__eventlistener_map")
		objlistener_map[oid] = listener
	end

	return listener
end

function Listener:get_observer()    return self[1] end
function Listener:get_subject()      return self[2] end
function Listener:get_type()        return self[3] end
function Listener:get_key()         return self[4] end
function Listener:get_callback()    return self[5] end
function Listener:get_oid()         return self[6] end

function Listener:handle(event)
	local callback = self:get_callback()
	xpcall(callback, __G_TRACE_BACK__, event)
end

function Listener:remove()
	local observer = self:get_observer()
	if is_table(observer) then  ----type(nil) ~= "table"
		local oId = self:get_oid()
		observer.__eventlistener_map[oId] = nil
	end

	local subject = self:get_subject()
	local typelistener_map = __global_listener_map__[subject]
	local type, key = self[3], self[4]
	local listener_list = typelistener_map[gen_typekey(type, key)]
	local idx = table.member_key(listener_list, self)
	if idx < #listener_list then
		listener_list[idx] = listener_list[len]
	end
	table.remove(listener_list)
end
--}} end of Listener

-- 一次性移除所有事件(避免反复判断和移动)
function remove_all_events(subject)
	if subject.__eventlistener_map then
		-- 移除自己监听别人的
		for _, listener in pairs(subject.__eventlistener_map) do
			listener:Remove()
		end
		subject.__eventlistener_map = nil
	end

	local subjectlistener_map = __global_listener_map__[subject]
	if subjectlistener_map then
		----移除别人监听自己的
		for _, listener_list in pairs(subjectlistener_map) do
			for _, listener in pairs(listener_list) do
				listener:Remove()
			end
		end
		__global_listener_map__[subject] = nil
	end
end

function remove_listener(listener)
	if listener then
		listener:remove()
	end
end

function add_listener(observer, subject, type, key, callback)
    key = key or KEY_ALL
    observer = observer or get_global_observer()
    subject = subject or get_global_subject()
    return Listener.create(observer, subject, type, key, callback)
end

function dispatch(subject, type, key, data)
	subject = subject or get_global_subject()
	local subjectlistener_map = __global_listener_map__[subject]
	if not subjectlistener_map then
		return
	end

	key = key or KEY_ALL

	local all_listener_list
	local listener_list = subjectlistener_map[gen_typekey(type, KEY_ALL)]
	if listener_list then
		all_listener_list = all_listener_list or {}
		array.merge(all_listener_list, listener_list)
	end

	if key ~= KEY_ALL then
		listener_list = subjectlistener_map[gen_typekey(type, key)]
		if listener_list then
			all_listener_list = all_listener_list or {}
			array.merge(all_listener_list, listener_list)
		end
	end

	if all_listener_list then
		local event = Event.create(subject, type, key, data)
		for _, listener in ipairs(all_listener_list) do
			listener:handle(event)
		end
	end
end

function __init__(module, updated)
end
