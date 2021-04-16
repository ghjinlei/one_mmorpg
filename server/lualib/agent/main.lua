--[[
ModuleName :
Path : lualib/agent/main.lua
Author : jinlei
CreateTime : 2021-04-14 20:09:07
Description :
--]]
local skynet = require "skynet"
local cluster = require "skynet.cluster"
local logger = require "common.utils.logger"
local sproto_helper = require "common.utils.sproto_helper"
local config_system = require "config_system"
local config_agent = config_system.agent

gate = false

agent_ins = false

local Agent = Object:inherit()
function Agent:on_init(oci)

end

local snapshot_key_list = {"characterid", "name", "race", "sex", "level", "login_time"}
function Agent:set_character_data(character_data, sync_account)
	local characterid = character_data.characterid
	if not self.characterid or self.characterid ~= characterid then
		logger.debugf("Agent.set_character_data,msg=characterid not match(%s,%s)", tostring(self.characterid), tostring(characterid))
		return
	end

	self.character_data = character_data
	self.savedata_dirty = true

	if sync_account then
		local character_map = self.account_data.character_map
		local snapshot = character_map[characterid]
		if not snapshot then
			snapshot = {}
			character_map[characterid] = snapshot
		end

		for _, snapshot_key in ipairs(snapshot_key_list) do
			snapshot[snapshot_key] = character_data[snapshot_key]
		end
	end
end

-- 增量更新
function Agent:set_character_data_patch(characterid, setdata, unsetdata)
	if not self.characterid or self.characterid ~= characterid then
		logger.debugf("Agent.set_character_data_patch,msg=characterid not match(%s,%s)", tostring(self.characterid), tostring(characterid))
		return
	end

	local patch_data = {
		["$set"] = setdata,
		["unset"] = unsetdata
	}
	skynet.send(self.database, "lua", "update_by_id", "character", characterid, patch_data)
end

function Agent:save_account_data()
	skynet.call(self.database, "lua", "update_by_id", self.accountid, self.account_data)
end

local function send_scene_func_nserver(addr, ...)
	skynet.send(addr, "lua", ...)
end

local function call_scene_func_nserver(addr, ...)
	return skynet.call(addr, "lua", ...)
end

local function send_scene_func_xserver(addr, ...)
	cluster.send("xserver", addr, ...)
end

local function call_scene_func_xserver(addr, ...)
	return cluster.call("xserver", addr, ...)
end

function Agent:set_scene_addr(scene_addr)
	if not self._leaving_xserver and (self._jumping_xserver or self._in_xserver) then
		self._send_scene_func = send_scene_func_xserver
		self._call_scene_func = call_scene_func_xserver
	else
		self._send_scene_func = send_scene_func_nserver
		self._call_scene_func = call_scene_func_nserver
	end

	self._scene_addr = scene_addr
end

function Agent:send_scene(methond, ...)
	local func = self._send_scene_func
	if not func then
		logger.warningf("agent.call_scene,method=%s,msg=no send_scene_func", method)
		return
	end
	return func(self._scene_addr, method, ...)
end

function Agent:call_scene(method, ...)
	local func = self._call_scene_func
	if not func then
		logger.warningf("agent.call_scene,method=%s,msg=no call_scene_func", method)
		return
	end
	return func(self._scene_addr, method, ...)
end

-- 给scene中的character发消息，只有消息被处理了，才会删除
function Agent:send2scene_character(characterid, ...)
	if characterid ~= self.characterid then
		local module_name, func_name = ...
		logger.warningf("agent.send2scene_character,msg=characterid(%s,%s) not match", tostring(characterid), tostring(self.characterid))
		return
	end

	table.insert(self._msg_queue2scene_character, {characterid, ...})
	self:try_push_msg_queue2scene_character()
end

function Agent:try_push_msg_queue2scene_character()
	if self._pushing_msg_queue2scene_character then
		return
	end
	self._pushing_msg_queue2scene_character = true

	local msg_idx = 0
	while(#self._msg_queue2scene_character > msg_idx) and (not self._teleporting) do
		local msg = self._msg_queue2scene_character[msg_idx + 1]
		local processed = self:call_scene("send2scene_character", table.unpack(msg))
		if not processed then
			break
		end
		msg_idx = msg_idx + 1
	end

	if msg_idx == #self._msg_queue2scene_character then
		self._msg_queue2scene_character = {}
	else
		for idx = 1, msg_idx do
			table.remove(self._msg_queue2scene_character, 1)
		end
	end

	self._pushing_msg_queue2scene_character = false
end

local max_wait_heart_beat_time = config_agent.max_wait_heart_beat_time
function Agent:start_check_heart_beat()
	self:stop_check_heart_beat()

	if max_wait_heart_beat_time > 0 then
		logger.debugf("agent.start_check_heart_beat,fd=%s,accountid=%s,msg=heart beat start", self.fd, self.accountid)
		self._check_heart_beat_timer = self:call_fre(max_wait_heart_beat_time, function()
			if os.time()- self._last_beat_time > max_wait_heart_beat_time then
				logger.debugf("heart_beat_timer,msg=heart_beat timeout,fd=%s,accountid=%s", self.fd, self.accountid)
				self:stop_check_heart_beat()
			end
		end)
	end
end

function Agent:stop_check_heart_beat()
	if self._check_heart_beat_timer then
		self:remove_timer(self._check_heart_beat_timer)
		self._check_heart_beat_timer = nil
	end
end

function Agent:send_bin_msg(msgdata)
	if self.fd then
		local packeddata = lrc4.xor_pack(msgdata, 15)
		if packeddata then
			socket.write(self.fd, packeddata)
		else
			logger.errorf("agent.send_bin_msg,msg=pack error")
		end
	else
		logger.debugf("agent.send_bin_msg,msg=no fd, drop msgdata(len=%d)", #msgdata)
	end
end

function Agent:send_msg(proto_name, args)
	self:send_bin_msg(sproto_helper.pack_msg(proto_name, args))
end

function Agent:on_release()
	self:stop_check_heart_beat()
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function(msg, sz)
		return sproto_helper.dispatch(msg, sz)
	end,
	dispatch = function(fd, _, ok, type_, name, args, response)
		assert(type_ == "REQUEST" and ok and agent_ins and fd == agent_ins.fd)    -- You can use fd to reply message
		skynet.ignoreret()      -- session is fd, don't call skynet.ret
		skynet.trace()

		local ok, result = pcall(sproto_helper.handle, name, args, response, agent_ins)
		if not ok then
			logger.warningf("agent_msg_dispatch err,fd=%s,name=%s,result=%s", tostring(fd), tostring(name), tostring(result))
		        return
		end

		if agent_ins then
		        agent_ins:send_bin_msg(result)
		end
	end
}

local CMD = {}

function CMD.start(client_data, new_client)
	skynet.send(gate, "lua", "forward", skynet.self(), client_data.fd)

	if new_client then

	else

	end
end

function __init__(module, updated)
	local function register_msghandler(name, func)
		local func = function(args, agent_ins)
			func(agent_ins, args)
		end
		sproto_helper.reg_msghandler(name, func)
	end
end

