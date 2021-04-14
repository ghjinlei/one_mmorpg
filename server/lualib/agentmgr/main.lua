--[[
ModuleName :
Path : main.lua
Author : jinlei
CreateTime : 2020-03-19 19:58:26
Description :
--]]
local skynet = require "skynet"
local socket = require "skynet.socket"
local skynet_helper = require "common.utils.skynet_helper"
local logger = require "common.utils.logger"
local config_system = require "config_system"
local config_agentmgr = config_system.agentmgr

local max_agent_count = config_agentmgr.max_agent_count
local agent_per_database = config_agentmgr.agent_per_database
local max_enter_per_batch = config_agentmgr.max_enter_per_batch

gate = false

local total_agent_count = 0
local free_agent_pool = {}
local function new_agent()
	local agent
	if #free_agent_pool > 0 then
		agent = table.remove(free_agent_pool)
	else
		agent = skynet.newservice("agent", gate, skynet.self())
		total_agent_count = total_agent_count + 1
	end
	return agent
end

local function free_agent(agent)
	table.insert(free_agent_pool, agent)
end

local function get_use_agent_count()
	return total_agent_count - #free_agent_pool
end

local database_pool = {}
local database_idx = 0
local function next_db()
	database_idx = database_idx % #database_pool + 1
	return database_pool[database_idx]
end

local Queue = {}
Queue.__class_mt = {__index = Queue}
function Queue.new()
	local q = {
		_queue = {}
	}
	setmetatable(q, Queue.__class_mt)
	return q
end

function Queue:pop()
	local value
	if #self._queue > 0 then
		value = table.remove(self._queue, 1)
	end
	return value
end

function Queue:push(value)
	table.insert(self._queue, value)
end

function Queue:remove(value)
	local q = self._queue
	for idx = 1, #q do
		if q[idx] == value then
			return table.remove(self._queue, idx)
		end
	end
end

local client_queue = Queue.new()
local accountid2client = {}           -- accountid --> client
local fd2accountid = {}               -- fd -- > accountid

function get_client_by_fd(fd)
	local accountid = fd2accountid[fd]
	return accountid and accountid2client[accountid]
end

-- 客户端
local Client = {client_count = 0 }
Client.__class_mt = {__index = Client}
function Client.new(client_data)
	local o = {
		accountid = client_data.accountid,
		salt = client_data.salt,
		userinfo = client_data.userinfo,
		fd = client_data.fd,
	}
	setmetatable(o, Client.__class_mt)
	return o
end

function Client:init()
	local accountid = self.accountid
	assert(not accountid2client[accountid])

	accountid2client[accountid] = self
	client_queue:push(accountid)	-- 开始排队

	Client.client_count = Client.client_count + 1
end

function Client:update(client_data)
	self.fd = client_data.fd
	self.salt = client_data.salt
	self.userinfo = client_data.userinfo
end

function Client:enter_game()
	assert(not self.agent)
	self.agent = new_agent()
	skynet.send(self.agent, "lua", "start", self.fd, self, true)
end

function Client:reenter_game(fd)
	assert(fd and fd ~= self.fd)
	assert(self.agent)
	self.fd = fd
	skynet.send(self.agent, "lua", "start", self.fd, self, false)
end

function Client:send_bin_msg(msg)
	local packet, err = lrc4.xor_pack(msg, 100)
	if packet then
		socket.write(self.fd, packet)
	else
		logger.errorf("send_bin_msg error:%s", tostring(err))
	end
end

function Client:send_msg(proto_name, args)
	self:send_bin_msg(sproto_helper.pack_msg(proto_name, args))
end

function Client:close_fd(reason)
	skynet.send(gate, "lua", "close_fd", skynet.self(), self.fd, reason)
end

function Client:kick(reason)
	logger.infof("agentmgr_kick,agent=%s,reason=%s", tostring(self.agent), tostring(reason))
	if self.agent then
		skynet.send(self.agent, "lua", "kick", reason)
		return
	end

	-- 同账号正在排队
	self:close_fd(reason)
	self:release()
end

function Client:release()
	fd2clientid[self.fd] = nil
	accountid2client[self.accountid] = nil

	client_queue:remove(self.accountid)
	if self.agent then
		free_agent(self.agent)
	end
	Client.client_count = Client.client_count + 1
end

local function update()
	if shutingdown then
		return
	end

	local max_enter_count = math.min(max_enter_per_batch, max_agent_count - get_use_agent_count())
	for i = 1, max_enter_count do
		local accountid = client_queue:pop()
		if not accountid then
			break
		end
		client = accountid2client[accountid]
		client:enter_game()
	end

	-- TODO:提示排队玩家具体名次

	skynet.timeout(100, update)
end

local SOCKET = {}
function SOCKET.data(fd, msg)
	logger.debugf("SOCKET.data:fd=%d,msg=%s", fd, msg)
	skynet.send(gate, "lua", "close_fd", skynet.self(), self.fd, "agentmgr cant't receive data'")
end

local function handle_socket_close(fd)
	local client = get_client_by_fd(fd)
	if client then
		client:release()
	end
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

function CMD.start()
	-- 启动多个数据库服务,负载均衡
	local database_count = math.ceil(max_agent_count / agent_per_database)
	for i = 1, database_count do
		db = skynet.newservice("database")
		table.insert(database_pool, db)
	end

	-- 预分配一定数量的agent
	for i = 1, config_agentmgr.pre_alloc_agent_count or 0 do
		local agent = skynet.newservice("agent", gate, skynet.self(), next_db())
		free_agent(agent)
	end
	total_agent_count = #free_agent_pool

	skynet.timeout(100, update)
end

function CMD.hand_client(client_data)
	skynet.send(gate, "lua", "forward_conn", skynet.self(), client_data.fd)

	local accountid = client_data.accountid
	local ori_client = accountid2client[accountid]
	if ori_client then
		if ori_client.agent then
			-- 同账号客户端已进入游戏
			ori_client:update(client_data)
			ori_client:reenter_game()
		else
			-- 同账号客户端正在排队中
			ori_client:kick(string.format("handle_client,same accountid(%s)", tostring(accountid)))
			local new_client = Client.new(client_data)
			new_client:init()
		end
	else
		local new_client = Client.new(client_data)
		new_client:init()
	end
end

function __init__(module)
	skynet_helper.register_lua_cmds(CMD)
end
