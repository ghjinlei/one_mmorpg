--[[
ModuleName :
Path : lualib/auth/main.lua
Author : jinlei
CreateTime : 2020-03-21 00:10:00
Description :
--]]
local skynet = require "skynet"
local skynet_queue = require "skynet.queue"
local socket = require "skynet.socket"
local logger = require "common.utils.logger"
local config_system = require "config_system"
local skynet_helper = require "common.utils.skynet_helper"
local sproto_helper = require "common.utils.sproto_helper"

gate, agentmgr = false, false

local fd2client = { }

local function gen_salt()
	local a = math.random(1 << 31)
	local b = math.random(1 << 31)
	return string.format("%08x%08x", a, b)
end

-- 客户端
local Client = { }
function Client.new(fd, addr)
	local o = {
		fd = fd,
		addr = addr,
		salt = gen_salt(),
		accountid = nil,
		userinfo = nil,
		mq = skynet_queue(),
	}
	setmetatable(o, {__index = Client})
	return o
end

function Client:handshake(args)
	logger.infof("hand_shake,operator=%s,channel=%s,platform=%s,openid=%s,appid=%s,os=%s,imei=%s,idfa=%s", 
		tostring(args.operator), tostring(args.channel), tostring(args.platform), tostring(args.openid), tostring(args.appid), tostring(os), tostring(imei), tostring(idfa))

	self.userinfo = args

	-- 超时检查
	self._timerid = TIMER.table_call_after(self, config_system.auth.max_auth_time, function()
		if self._finish then
			return
		end
		logger.infof("client_handshake_timeout,operator=%s,channel=%s,platform=%s,openid=%s")
		self:close_fd("auth timeout")
	end)

	return {code = 0, salt = self.salt, patch = config_system.client_patch}
end

function Client:auth(args)
	-- 可能已经超时
	if self._finish then
		return {code = 1}
	end

	logger.infof("auth,data=%s", tostring(args.data))

	--TODO: 处理登录超时
	TIMER.table_remove_timer(self, self._timerid)
	--TODO: 认证合法性
	--TODO: 检查是否封号
	--
	local userinfo = self.userinfo
	-- 如果有多个平台，各平台公用角色，即账号ID=平台账号
	self.accountid = tostring(userinfo.openid)

	self.mq = nil
	skynet.send(agentmgr, "lua", "hand_client", self)

	-- 校验成功
	self._finish = true

	return {code = 0, openid = userinfo.openid}
end

function Client:close_fd(reason)
	self._finish = true
	fd2client[self.fd] = nil
	skynet.send(gate, "lua", "close_fd", skynet.self(), self.fd, reason)
end

function Client:send_bin_msg(msg)
	if self.fd then
		local packet = string.pack(">s2", msg)
		socket.write(self.fd, packet)
	end
end

function Client:handle_client_msg(msg)
	self.mq(function()
		if self._finish then --认证结束
			self:close_fd("dumplicated client login packet")
			return
		end

		local ok, _type, name, args, response = pcall(sproto_helper.dispatch, msg)
		if not ok then
			self:close_fd("handle_client_msg error: dispatch")
			return
		end
		local ok, result = pcall(sproto_helper.handle, name, args, response, self)
		if not ok then
			self:close_fd(string.format("handle_client_msg error: handle(%s)", tostring(result)))
			return
		end

		if result then
			self:send_bin_msg(result)
		end

		if self._finish then
			fd2client[self.fd] = nil
		end
	end)
end

local SOCKET = {}
function SOCKET.data(fd, msg)
	local client = fd2client[fd]
	if not client then
		logger.warningf("SOCKET.data:fd=%d,client is missing", fd)
		return
	end

	local raw_msg = msg           -- 为了测试方便,暂时不做任何数据加密解密
	logger.debugf("SOCKET.data:fd=%d,raw_msg=%s,len=%d", fd, tostring(raw_msg), #raw_msg)
	client:handle_client_msg(raw_msg)
end

function SOCKET.open(fd, address)
	logger.debugf("SOCKET.open:fd=%d,address=%s", fd, address)
	assert(not fd2client[fd])
	local client = Client.new(fd, address)
	fd2client[fd] = client
end

local function handle_socket_close(fd)
	local client = fd2client[fd]
	if not client then
		return
	end
	fd2client[fd] = nil
end

function SOCKET.close(fd)
	logger.debugf("SOCKET.close:fd=%d", fd)
	handle_socket_close(fd)
end

function SOCKET.error(fd, msg)
	logger.debugf("SOCKET.error:fd=%d,msg=%s", fd, msg)
	handle_socket_close(fd)
end

function SOCKET.warning(fd, sz)
	logger.debugf("SOCKET.warning:fd=%d,sz=%s", fd, sz)
end

local CMD = {}
function CMD.socket(cmd, ...)
	return SOCKET[cmd](...)
end

local function register_msghandler(name, func)
	local func = function(args, client)
		func(client, args)
	end
	sproto_helper.reg_msghandler(name, func)
end

function __init__(module)
	register_msghandler("AUTH_handshake", Client.handshake)
	register_msghandler("AUTH_auth", Client.auth)

	skynet_helper.register_lua_cmds(CMD)
end
