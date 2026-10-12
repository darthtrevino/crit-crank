-- Dice expressions: parsing, rolling, and formatting.
--
-- A spec looks like:
--   { terms = { {count=1, sides=20, keep="h", keepN=1}, ... }, bonus = 5, check = true }
-- `check` marks a d20 test (ability check, save, attack) that can take
-- advantage/disadvantage and can be a natural 20 / natural 1.

Dice = {}

local function copySpec(spec)
	local out = {}
	for k, v in pairs(spec) do out[k] = v end
	out.terms = {}
	for i, t in ipairs(spec.terms) do
		out.terms[i] = { count = t.count, sides = t.sides, keep = t.keep, keepN = t.keepN }
	end
	return out
end

-- Parses strings like "1d20+5", "3d4+3", "2d6", "d100", "4d6kh3", "1d6-1".
function Dice.parse(str)
	local spec = { terms = {}, bonus = 0 }
	local s = str:gsub("%s", "")
	for sign, part in s:gmatch("([%+%-]?)([^%+%-]+)") do
		local n, sides, keep = part:match("^(%d*)d(%d+)(.*)$")
		if sides then
			local term = { count = tonumber(n) or 1, sides = tonumber(sides) }
			local kt, kn = keep:match("^k([hl])(%d+)$")
			if kt then
				term.keep, term.keepN = kt, tonumber(kn)
			end
			table.insert(spec.terms, term)
		else
			local v = tonumber(part) or 0
			if sign == "-" then v = -v end
			spec.bonus += v
		end
	end
	return spec
end

function Dice.check(bonus, critRange)
	local spec = Dice.parse("1d20")
	spec.bonus = bonus
	spec.check = true
	spec.critRange = critRange or 20
	return spec
end

-- mode: "normal" | "adv" | "dis"
function Dice.withMode(spec, mode)
	if not spec.check or mode == "normal" then return spec end
	local out = copySpec(spec)
	out.terms[1].count = 2
	out.terms[1].keep = (mode == "adv") and "h" or "l"
	out.terms[1].keepN = 1
	return out
end

-- Critical hit: roll all of the damage dice twice.
function Dice.crit(spec)
	local out = copySpec(spec)
	for _, t in ipairs(out.terms) do
		t.count *= 2
		if t.keepN then t.keepN *= 2 end
	end
	return out
end

local function signed(n)
	if n > 0 then return "+" .. n end
	if n < 0 then return tostring(n) end
	return ""
end
Dice.signed = signed

function Dice.format(spec)
	local parts = {}
	for i, t in ipairs(spec.terms) do
		local s = (t.count == 1 and "d" or (t.count .. "d")) .. t.sides
		if t.keep then
			s = s .. "k" .. t.keep .. (t.keepN or 1)
		end
		parts[#parts + 1] = (i > 1 and "+" or "") .. s
	end
	return table.concat(parts) .. signed(spec.bonus)
end

local function rollTerm(term, rerollOnes)
	local dice = {}
	for i = 1, term.count do
		local d = { sides = term.sides, value = math.random(1, term.sides), kept = true }
		if rerollOnes and d.value == 1 then
			d.value = math.random(1, term.sides)
			d.rerolled = true
		end
		dice[i] = d
	end
	if term.keep then
		local order = {}
		for i = 1, #dice do order[i] = i end
		table.sort(order, function(a, b)
			if term.keep == "h" then return dice[a].value > dice[b].value end
			return dice[a].value < dice[b].value
		end)
		for rank, idx in ipairs(order) do
			dice[idx].kept = rank <= (term.keepN or 1)
		end
	end
	return dice
end

-- Returns { dice = {...}, total = n, natural = n|nil, crit = bool, fumble = bool }
-- opts.lucky rerolls natural 1s on d20 tests once (Halfling Lucky).
function Dice.roll(spec, opts)
	local result = { dice = {}, total = spec.bonus }
	local lucky = opts and opts.lucky and spec.check
	for ti, term in ipairs(spec.terms) do
		for _, d in ipairs(rollTerm(term, lucky and term.sides == 20)) do
			if d.rerolled then result.lucky = true end
			d.term = ti
			table.insert(result.dice, d)
			if d.kept then result.total += d.value end
		end
	end
	if spec.check then
		for _, d in ipairs(result.dice) do
			if d.kept and d.sides == 20 then
				result.natural = d.value
				break
			end
		end
		result.crit = result.natural ~= nil and result.natural >= (spec.critRange or 20)
		result.fumble = result.natural == 1
	end
	return result
end

-- Random faces for the tumbling animation (no keep/total bookkeeping needed).
function Dice.faces(spec)
	local dice = {}
	for _, term in ipairs(spec.terms) do
		for _ = 1, term.count do
			table.insert(dice, { sides = term.sides, value = math.random(1, term.sides), kept = true })
		end
	end
	return dice
end
