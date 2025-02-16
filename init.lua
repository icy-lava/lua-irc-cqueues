local socket = require "cqueues.socket"
local auxlib = require "cqueues.auxlib"
local errno = require "cqueues.errno"

local error = error
local setmetatable = setmetatable
local rawget = rawget
local unpack = unpack
local pairs = pairs
local assert = assert
local require = require
local tonumber = tonumber
local type = type
local pcall = pcall

module "irc"

local meta = {}
meta.__index = meta
_META = meta

require "irc.util"
require "irc.asyncoperations"
require "irc.handlers"

local meta_preconnect = {}
function meta_preconnect.__index(o, k)
	local v = rawget(meta_preconnect, k)

	if not v and meta[k] then
		error(("field '%s' is not accessible before connecting"):format(k), 2)
	end
	return v
end

function new(data)
	local o = {
		nick = assert(data.nick, "Field 'nick' is required");
		username = data.username or "lua";
		realname = data.realname or "Lua owns";
		nickGenerator = data.nickGenerator or defaultNickGenerator;
		hooks = {};
		track_users = true;
	}
	assert(checkNick(o.nick), "Erroneous nickname passed to irc.new")
	return setmetatable(o, meta_preconnect)
end

function meta:hook(name, id, f)
	f = f or id
	self.hooks[name] = self.hooks[name] or {}
	self.hooks[name][id] = f
	return id or f
end
meta_preconnect.hook = meta.hook


function meta:unhook(name, id)
	local hooks = self.hooks[name]

	assert(hooks, "no hooks exist for this event")
	assert(hooks[id], "hook ID not found")

	hooks[id] = nil
end
meta_preconnect.unhook = meta.unhook

function meta:invoke(name, ...)
	local hooks = self.hooks[name]
	if hooks then
		for id,f in pairs(hooks) do
			if f(...) then
				return true
			end
		end
	end
end

function meta_preconnect:connect(_host, _port)
	local host, port, password, secure, timeout

	if type(_host) == "table" then
		host = _host.host
		port = _host.port
		timeout = _host.timeout
		password = _host.password
		secure = _host.secure
	else
		host = _host
		port = _port
	end

	host = host or error("host name required to connect", 2)
	port = port or 6667

	local s = socket.connect(host, port)

	auxlib.assert(s:connect(timeout or 30))
	
	if secure ~= false then
		local success, errmsg = s:starttls()
		if not success then
			error(("could not make secure connection: %s"):format(errmsg), 2)
		end
	end
	
	self.socket = s
	setmetatable(self, meta)

	self:send("CAP REQ multi-prefix")

	self:invoke("PreRegister", self)
	self:send("CAP END")

	if password then
		self:send("PASS %s", password)
	end

	self:send("NICK %s", self.nick)
	self:send("USER %s 0 * :%s", self.username, self.realname)

	self.channels = {}

	repeat
		self:waitAuthenticate(false)
	until self.authed
end

function meta:disconnect(message)
	message = message or "Bye!"

	self:invoke("OnDisconnect", message, false)
	self:send("QUIT :%s", message)

	self:shutdown()
end

function meta:shutdown()
	self.socket:close()
	setmetatable(self, nil)
end

local function getline(self, errlevel, timeout)
	if timeout == nil then timeout = 0 end
	local line, err = self.socket:xread("*l", nil, timeout)
	if not line then
		err = errno[err]
		if err == "ETIMEDOUT" or err == "EAGAIN" then
			self.socket:clearerr()
		else
			self:invoke("OnDisconnect", err, true)
			self:shutdown()
			error(err, errlevel)
		end
	end

	return line
end

local function think(self, timeout, waitAuthenticate)
	while true do
		local line = getline(self, 3, timeout)
		if line and #line > 0 then
			local authed = self.authed
			if not self:invoke("OnRaw", line) then
				self:handle(parse(line))
			end
			if waitAuthenticate and self.authed and not authed then
				break
			end
		else
			break
		end
	end
end

function meta:waitAuthenticate(timeout)
	think(self, timeout, true)
end

function meta:think(timeout)
	think(self, timeout, false)
end

function meta:loop()
	self:think(false)
end

local handlers = handlers

function meta:handle(prefix, cmd, params)
	local handler = handlers[cmd]
	if handler then
		return handler(self, prefix, unpack(params))
	end
end

local whoisHandlers = {
	["311"] = "userinfo";
	["312"] = "node";
	["319"] = "channels";
	["330"] = "account"; -- Freenode
	["307"] = "registered"; -- Unreal
}

function meta:whois(nick)
	self:send("WHOIS %s", nick)

	local result = {}

	while true do
		local line = getline(self, 3)
		if line then
			local prefix, cmd, args = parse(line)

			local handler = whoisHandlers[cmd]
			if handler then
				result[handler] = args
			elseif cmd == "318" then
				break
			else
				self:handle(prefix, cmd, args)
			end
		end
	end

	if result.account then
		result.account = result.account[3]
	elseif result.registered then
		result.account = result.registered[2]
	end

	return result
end

function meta:topic(channel)
	self:send("TOPIC %s", channel)
end

