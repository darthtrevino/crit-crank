-- Imported characters (from the charsync desktop tool).
--
-- Imports live in the "imports" datastore file as { characters = { ... } },
-- using the same shape as characters.lua plus a unique `key` ("ddb<id>").
--
-- charsync can also push a character over USB while the game runs, using
-- serial `msg` commands (one line each, answered with print()):
--   msg cs ping              -> cs pong <protocol>
--   msg cs begin <bytes>     -> cs ready
--   msg cs data <seq> <text> -> cs ack <seq>   (seq starts at 1)
--   msg cs end               -> cs done <key> | cs err <reason>
--   msg cs remove <key>      -> cs removed <key> | cs err <reason>

Importer = {}

Importer.PROTOCOL = 1

local ABILITIES <const> = { "str", "dex", "con", "int", "wis", "cha" }

local function num(v, default)
	v = tonumber(v)
	if v == nil then return default end
	return math.floor(v)
end

local function str(v, default)
	if type(v) == "string" and v ~= "" then return v end
	return default
end

local function strings(v)
	local out = {}
	for _, s in ipairs(type(v) == "table" and v or {}) do
		if str(s) then out[#out + 1] = s end
	end
	return out
end

local function ranges(v)
	local out = {}
	for k, ft in pairs(type(v) == "table" and v or {}) do
		if type(k) == "string" and num(ft, 0) > 0 then out[k] = num(ft, 0) end
	end
	return out
end

-- Traits page data; older imports have none.
local function traits(raw)
	raw = type(raw) == "table" and raw or {}
	local t = { speeds = ranges(raw.speeds), senses = ranges(raw.senses) }
	for _, k in ipairs({
		"languages", "resistances", "immunities", "vulnerabilities", "conditionImmunities",
		"armor", "weapons", "tools",
	}) do
		t[k] = strings(raw[k])
	end
	return t
end

-- Validates and normalizes a decoded character; returns c or nil, reason.
function Importer.normalize(raw)
	if type(raw) ~= "table" then return nil, "not an object" end
	local key = str(raw.key)
	if not key then return nil, "missing key" end
	if type(raw.abilities) ~= "table" then return nil, "missing abilities" end

	local c = {
		key = key,
		imported = true,
		name = str(raw.name, "Unnamed"),
		race = str(raw.race, ""),
		class = str(raw.class, "Adventurer"),
		level = math.max(1, num(raw.level, 1)),
		ac = num(raw.ac, 10),
		hp = math.max(1, num(raw.hp, 1)),
		speed = num(raw.speed, 30),
		abilities = {},
		saves = {},
		skills = {},
		hitDie = num(raw.hitDie, 8),
		critRange = num(raw.critRange, 20),
		lucky = raw.lucky == true,
		spellAbility = str(raw.spellAbility),
		slots = {},
		features = {},
		actions = {},
		traits = traits(raw.traits),
	}
	for _, a in ipairs(ABILITIES) do
		c.abilities[a] = num(raw.abilities[a], 10)
	end
	for _, s in ipairs(type(raw.saves) == "table" and raw.saves or {}) do
		if type(s) == "string" then c.saves[#c.saves + 1] = s end
	end
	for k, v in pairs(type(raw.skills) == "table" and raw.skills or {}) do
		if type(k) == "string" then c.skills[k] = math.max(1, math.min(2, num(v, 1))) end
	end
	for _, n in ipairs(type(raw.slots) == "table" and raw.slots or {}) do
		c.slots[#c.slots + 1] = math.max(0, num(n, 0))
	end
	for _, f in ipairs(type(raw.features) == "table" and raw.features or {}) do
		if type(f) == "table" and str(f.id) and not Resources.RESERVED[f.id] and num(f.max, 0) > 0 then
			c.features[#c.features + 1] = {
				id = f.id, name = str(f.name, f.id), max = num(f.max, 1),
				reset = f.reset == "short" and "short" or "long", rule = str(f.rule),
			}
		end
	end
	for _, a in ipairs(type(raw.actions) == "table" and raw.actions or {}) do
		if type(a) == "table" and (str(a.name) or str(a.section)) then
			-- older files may point at a dropped feature whose id is a built-in tracker
			if a.uses ~= nil and (type(a.uses) ~= "string" or Resources.RESERVED[a.uses]) then a.uses = nil end
			c.actions[#c.actions + 1] = a
		end
	end
	return c
end

function Importer.load()
	local data = playdate.datastore.read("imports")
	local list = {}
	if data and type(data.characters) == "table" then
		for _, raw in ipairs(data.characters) do
			local c = Importer.normalize(raw)
			if c then list[#list + 1] = c end
		end
	end
	return list
end

function Importer.save(list)
	playdate.datastore.write({ characters = list }, "imports")
end

-- Inserts or replaces by key; returns the updated list.
function Importer.upsert(list, c)
	for i, old in ipairs(list) do
		if old.key == c.key then
			list[i] = c
			return list
		end
	end
	list[#list + 1] = c
	return list
end

function Importer.remove(list, key)
	for i, old in ipairs(list) do
		if old.key == key then
			table.remove(list, i)
			return true
		end
	end
	return false
end

---------------------------------------------------------------- serial

-- handlers: { imported = fn(c), removed = fn(key) -> bool }
function Importer.listen(handlers)
	local buf, expected, seq = nil, 0, 0

	local function reply(s) print("cs " .. s) end

	function playdate.serialMessageReceived(msg)
		local cmd, rest = msg:match("^cs (%S+) ?(.*)$")
		if not cmd then return end

		if cmd == "ping" then
			reply("pong " .. Importer.PROTOCOL)
		elseif cmd == "begin" then
			buf, expected, seq = {}, num(rest, 0), 0
			reply("ready")
		elseif cmd == "data" then
			local n, text = rest:match("^(%d+) (.*)$")
			n = tonumber(n)
			if not buf or not n then
				reply("err no transfer")
			elseif n == seq + 1 then
				buf[#buf + 1] = text
				seq = n
				reply("ack " .. n)
			elseif n == seq then
				reply("ack " .. n) -- duplicate resend
			else
				reply("err out of order " .. n)
			end
		elseif cmd == "end" then
			if not buf then
				reply("err no transfer")
				return
			end
			local text = table.concat(buf)
			buf = nil
			if #text ~= expected then
				reply("err length " .. #text .. "/" .. expected)
				return
			end
			local ok, raw = pcall(json.decode, text)
			if not ok or raw == nil then
				reply("err bad json")
				return
			end
			local c, why = Importer.normalize(raw)
			if not c then
				reply("err " .. why)
				return
			end
			handlers.imported(c)
			reply("done " .. c.key)
		elseif cmd == "remove" then
			if handlers.removed(rest) then
				reply("removed " .. rest)
			else
				reply("err unknown " .. rest)
			end
		else
			reply("err unknown command")
		end
	end
end
