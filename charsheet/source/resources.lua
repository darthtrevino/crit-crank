-- Per-character tracked resources: HP, hit dice, spell slots, feature uses.
--
-- State is a flat table keyed by resource id:
--   hp, hitDice, slot1..slotN, and each feature id.

Resources = {}

local function featureById(c, id)
	for _, f in ipairs(c.features or {}) do
		if f.id == id then return f end
	end
end

function Resources.max(c, key)
	if key == "hp" then return c.hp end
	if key == "hitDice" then return c.level end
	local lvl = key:match("^slot(%d+)$")
	if lvl then return (c.slots or {})[tonumber(lvl)] or 0 end
	local f = featureById(c, key)
	return f and f.max or 0
end

function Resources.label(c, key)
	if key == "hp" then return "Hit Points" end
	if key == "hitDice" then return "Hit Dice" end
	local lvl = key:match("^slot(%d+)$")
	if lvl then return "Level " .. lvl .. " slot" end
	local f = featureById(c, key)
	return f and f.name or key
end

function Resources.keys(c)
	local keys = { "hp", "hitDice" }
	for lvl in ipairs(c.slots or {}) do keys[#keys + 1] = "slot" .. lvl end
	for _, f in ipairs(c.features or {}) do keys[#keys + 1] = f.id end
	return keys
end

function Resources.fresh(c)
	local r = {}
	for _, k in ipairs(Resources.keys(c)) do r[k] = Resources.max(c, k) end
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

-- Long rest: full HP, all slots and features, regain half your hit dice (min 1).
function Resources.longRest(c, r)
	local before = r.hitDice
	r.hp = c.hp
	r.hitDice = math.min(c.level, r.hitDice + math.max(1, math.floor(c.level / 2)))
	for lvl, max in ipairs(c.slots or {}) do r["slot" .. lvl] = max end
	for _, f in ipairs(c.features or {}) do r[f.id] = f.max end
	return r.hitDice - before
end
