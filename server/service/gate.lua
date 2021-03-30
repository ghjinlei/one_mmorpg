local skynet = require "skynet"
local netpack = require "skynet.netpack"
local socketdriver = require "skynet.socketdriver"
local config_gate = require "config_system".gate
local skynet_helper = require "common.utils.skynet_helper"
local logger = require "common.utils.logger"
dofile("lualib/common/base/preload.lua")

local socket          -- listen socket
local queue           -- message queue
local maxclient = config_gate.maxclient or 1024
local client_number = 0
local CMD = setmetatable({}, { __gc = function() netpack.clear(queue) end })
local nodelay = false

local connection = {}
local auth_list = false
local auth_idx = 0

--[[
	[fd] = {
		agent = xxx,
		conn = xxx,
	}
--]]

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
}

local MSG = {}

skynet.register_protocol {
	name = "socket",
	id = skynet.PTYPE_SOCKET,       -- PTYPE_SOCKET = 6
	unpack = function ( msg, sz )
		return netpack.filter( queue, msg, sz)
	end,
	dispatch = function (_, _, q, type, ...)
		queue = q
		if type then
			MSG[type](...)
		end
	end
}

local function dispatch_msg(fd, msg, sz)
	-- recv a package, forward it
	local c = connection[fd]
	local agent = c.agent
	if agent then
		-- It's safe to redirect msg directly , gateserver framework will not free msg.
		skynet.redirect(agent, c.client, "client", fd, msg, sz)
	else
		skynet.send(c.conn, "lua", "socket", "data", fd, skynet.tostring(msg, sz))
		-- skynet.tostring will copy msg to a string, so we must free msg here.
		skynet.trash(msg,sz)
	end
end

MSG.data = dispatch_msg

local function dispatch_queue()
	local fd, msg, sz = netpack.pop(queue)
	if fd then
		-- may dispatch even the handler.message blocked
		-- If the handler.message never block, the queue should be empty, so only fork once and then exit.
		skynet.fork(dispatch_queue)
		dispatch_msg(fd, msg, sz)

		for fd, msg, sz in netpack.pop, queue do
			dispatch_msg(fd, msg, sz)
		end
	end
end

MSG.more = dispatch_queue

function MSG.open(fd, address)
	if client_number >= maxclient then
		logger.infof("msg.open too many client! will close! fd=%d address=%s", fd, address)
		socketdriver.close(fd)
		return
	end
	logger.infof("msg.open fd=%d address=%s", fd, address)

	if nodelay then
		socketdriver.nodelay(fd)
	end

	--负载均衡,选择一个authd;
	local auth_num = #auth_list
	if auth_num == 0 then
		logger.errorf("msg.open has no authd")
		socketdriver.close(fd)
		return
	end

	auth_idx = auth_idx + 1
	if auth_idx > auth_num then
		auth_idx = 1
	end

	local auth = auth_list[auth_idx]

	connection[fd] = { conn = auth, address = address }
	client_number = client_number + 1
	socketdriver.start(fd)
	skynet.send(auth, "lua", "socket", "open", fd, address)
end

local function close_fd(fd)
	local c = connection[fd]
	if c then
		connection[fd] = nil
	end
end

function MSG.close(fd)
	if fd ~= socket then
		local c = connection[fd]
		if c then
			skynet.send(c.conn, "lua", "socket", "close", fd)
		end
		close_fd(fd)
	else
		socket = nil
	end
end

function MSG.error(fd, msg)
	if fd ~= socket then
		skynet.send(c.conn, "lua", "socket", "error", fd, msg)
		close_fd(fd)
	else
		socketdriver.close(fd)
		logger.errorf("gateserver close listen socket, accept error:%s", tostring(msg))
	end
end

function MSG.warning(fd, sz)
	local c= connection[fd]
	if c then
		skynet.send(c.conn, "lua", "socket", "warning", fd, sz)
	end
end

-- 启动监听,开始服务
function CMD.open(source)
	assert(not socket)
	local ip, port = table.unpack(string.split(config_gate.listen_addr, ":"))
	port = tonumber(port)
 
	socket = socketdriver.listen(ip, port)
	logger.infof("******************socket open %d %s:%d******************", socket, ip, port)
	socketdriver.start(socket)
	return true
end

-- 关闭监听
function CMD.close()
	logger.infof("******************socket close %d***********************", socket or 0)
	if not socket then 
		return 
	end
	socketdriver.close(socket)
	socket = nil
end

function CMD.forward_agent(source, fd, client, address)
	local c = assert(connection[fd])
	c.client = client or 0
	c.agent = address or source
	c.conn = nil
end

function CMD.forward_conn(source, fd, client, address)
	local c = assert(connection[fd])
	c.client = client or 0
	c.conn = address or source
	c.agent = nil
end

-- 关闭客户端连接
function CMD.close_fd(source, fd, reason)
	assert(fd and fd ~= socket)
	logger.infof("gate_close_fd,source=%s,fd=%s,reason=%s", tostring(source), tostring(fd), tostring(reason))

	connection[fd].conn = nil
	socketdriver.close(fd)
end

-- 强制关闭客户端连接
function CMD.shutdown_fd(source, fd, reason)
	assert(fd and fd ~= socket)
	logger.infof("gate_shutdown_fd,source=%s,fd=%s,reason=%s", tostring(source), tostring(fd), tostring(reason))

	connection[fd].conn = nil
	socketdriver.shutdown(fd)
end

function CMD.set_auth_list(auths)
	auth_list = auths
end

skynet.start(function()
	skynet_helper.dispatch_lua_by_cmd(CMD)
end)

