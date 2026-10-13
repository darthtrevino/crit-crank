-- Per-character tracked resources: HP, hit dice, conditions, spell slots, feature uses.
--
-- State is a flat table keyed by resource id:
--   hp, hitDice, deathSaves, deathFails, inspiration, exhaustion,
--   slot1..slotN, and each feature id.

Resources = {}

-- Death save counters start empty instead of full.
local DEATH <const> = { deathSaves = "Death save successes", deathFails = "Death save failures" }

-- Conditions also start empty: { max, label }.
local CONDITION <const> = {
	inspiration = { 1, "Heroic Inspiration" },
	exhaustion = { 6, "Exhaustion" },
}
Resources.RESERVED = { hp = true, hitDice = true, deathSaves = true, deathFails = true, inspiration = true, exhaustion = true }

local function featureById(c, id)
	for _, f in ipairs(c.features or {}) do
		if f.id == id then return f end
	end
end

function Resources.max(c, key)
	if key == "hp" then return c.hp end
	if key == "hitDice" then return c.level end
	if DEATH[key] then return 3 end
	if CONDITION[key] then return CONDITION[key][1] end
	local lvl = key:match("^slot(%d+)$")
	if lvl then return (c.slots or {})[tonumber(lvl)] or 0 end
	local f = featureById(c, key)
	return f and f.max or 0
end

function Resources.label(c, key)
	if key == "hp" then return "Hit Points" end
	if key == "hitDice" then return "Hit Dice" end
	if DEATH[key] then return DEATH[key] end
	if CONDITION[key] then return CONDITION[key][2] end
	local lvl = key:match("^slot(%d+)$")
	if lvl then return "Level " .. lvl .. " slot" end
	local f = featureById(c, key)
	return f and f.name or key
end

function Resources.keys(c)
	local keys = { "hp", "hitDice", "deathSaves", "deathFails", "inspiration", "exhaustion" }
	for lvl in ipairs(c.slots or {}) do keys[#keys + 1] = "slot" .. lvl end
	for _, f in ipairs(c.features or {}) do keys[#keys + 1] = f.id end
	return keys
end

function Resources.fresh(c)
	local r = {}
	for _, k in ipairs(Resources.keys(c)) do r[k] = (DEATH[k] or CONDITION[k]) and 0 or Resources.max(c, k) end
	return r
end

-- Merges saved values onto a fresh state so data changes don't break old saves.
function Resources.load(c, saved)
	local r = Resources.fresh(c)
	if type(saved) == "table" then
		for k, max in pairs(r) do
			local v = tonumber(saved[k])
			if v then r[k] = math.max(0, math.min(max, math.floor(v))) end
		end
	end
	if r.hp > 0 then Resources.clearDeath(r) end
	return r
end

function Resources.get(c, r, key)
	return r[key] or 0, Resources.max(c, key)
end

-- Returns the clamped new value.
function Resources.add(c, r, key, delta)
	local max = Resources.max(c, key)
	r[key] = math.max(0, math.min(max, (r[key] or 0) + delta))
	return r[key]
end

-- Spends one; returns true if one was available.
function Resources.spend(c, r, key)
	if (r[key] or 0) <= 0 then return false end
	r[key] -= 1
	return true
end

function Resources.dying(r)
	return r.hp == 0
end

function Resources.clearDeath(r)
	r.deathSaves, r.deathFails = 0, 0
end

-- Records a death save roll at 0 HP; returns a short outcome message.
function Resources.deathSave(c, r, result)
	local n = result.natural
	if n == 20 then
		r.hp = math.min(1, c.hp)
		Resources.clearDeath(r)
		return "Natural 20! Back up with 1 HP"
	end
	local fails = n == 1 and 2 or (result.total >= 10 and 0 or 1)
	if fails > 0 then
		Resources.add(c, r, "deathFails", fails)
	else
		Resources.add(c, r, "deathSaves", 1)
	end
	if r.deathFails >= 3 then return "Three failures: you have died" end
	if r.deathSaves >= 3 then return "Three successes: you're stable" end
	return fails > 0 and ("Failure (" .. r.deathFails .. "/3)") or ("Success (" .. r.deathSaves .. "/3)")
end

-- Short rest: restores features that recharge on a short rest.
-- (Hit dice are spent separately via the "Spend Hit Die" roll.)
function Resources.shortRest(c, r)
	local restored = {}
	for _, f in ipairs(c.features or {}) do
		if f.reset == "short" and r[f.id] < f.max then
			r[f.id] = f.max
			restored[#restored + 1] = f.name
		end
	end
	return restored
end

-- Long rest: full HP, all slots and features, regain half your hit dice (min 1),
-- and one less level of exhaustion. Returns hit dice regained, exhaustion removed.
function Resources.longRest(c, r)
	local before, tired = r.hitDice, r.exhaustion
	r.hp = c.hp
	Resources.clearDeath(r)
	r.hitDice = math.min(c.level, r.hitDice + math.max(1, math.floor(c.level / 2)))
	for lvl, max in ipairs(c.slots or {}) do r["slot" .. lvl] = max end
	for _, f in ipairs(c.features or {}) do r[f.id] = f.max end
	r.exhaustion = math.max(0, tired - 1)
	return r.hitDice - before, tired - r.exhaustion
end
