-- Turns a character definition into pages of rows for display.
--
-- Row kinds:
--   header: { kind="header", label }
--   info:   { kind="info", label, detail, value }
--   roll:   { kind="roll", label, detail, value, spec, mark, indent, rollKind, critable }
--     mark: nil | "none" | "prof" | "exp"   (proficiency marker)
--     rollKind: "check" | "damage" | "heal"

Sheet = {}

Sheet.ABILITIES = { "str", "dex", "con", "int", "wis", "cha" }
Sheet.ABILITY_NAMES = {
	str = "Strength", dex = "Dexterity", con = "Constitution",
	int = "Intelligence", wis = "Wisdom", cha = "Charisma",
}

Sheet.SKILLS = {
	{ "acrobatics", "Acrobatics", "dex" },
	{ "animalHandling", "Animal Handling", "wis" },
	{ "arcana", "Arcana", "int" },
	{ "athletics", "Athletics", "str" },
	{ "deception", "Deception", "cha" },
	{ "history", "History", "int" },
	{ "insight", "Insight", "wis" },
	{ "intimidation", "Intimidation", "cha" },
	{ "investigation", "Investigation", "int" },
	{ "medicine", "Medicine", "wis" },
	{ "nature", "Nature", "int" },
	{ "perception", "Perception", "wis" },
	{ "performance", "Performance", "cha" },
	{ "persuasion", "Persuasion", "cha" },
	{ "religion", "Religion", "int" },
	{ "sleightOfHand", "Sleight of Hand", "dex" },
	{ "stealth", "Stealth", "dex" },
	{ "survival", "Survival", "wis" },
}

local signed = function(n)
	return n >= 0 and ("+" .. n) or tostring(n)
end
Sheet.signed = signed

function Sheet.mod(score)
	return math.floor((score - 10) / 2)
end

function Sheet.proficiency(level)
	return 2 + math.floor((level - 1) / 4)
end

local function hasSave(c, ab)
	for _, s in ipairs(c.saves) do
		if s == ab then return true end
	end
	return false
end

function Sheet.skillBonus(c, key, ab)
	local pb = Sheet.proficiency(c.level)
	local level = c.skills[key] or 0
	return Sheet.mod(c.abilities[ab]) + pb * level, level
end

local function abilitiesPage(c)
	local rows = {}
	for _, ab in ipairs(Sheet.ABILITIES) do
		local score = c.abilities[ab]
		local m = Sheet.mod(score)
		rows[#rows + 1] = {
			kind = "roll", label = Sheet.ABILITY_NAMES[ab], detail = tostring(score),
			value = signed(m), spec = Dice.check(m), rollKind = "check",
			title = Sheet.ABILITY_NAMES[ab] .. " check",
		}
	end
	local dexMod = Sheet.mod(c.abilities.dex)
	local passive = 10 + Sheet.skillBonus(c, "perception", "wis")
	rows[#rows + 1] = { kind = "header", label = "Combat" }
	rows[#rows + 1] = {
		kind = "roll", label = "Initiative", value = signed(dexMod),
		spec = Dice.check(dexMod), rollKind = "check",
	}
	rows[#rows + 1] = { kind = "info", label = "Proficiency Bonus", value = signed(Sheet.proficiency(c.level)) }
	rows[#rows + 1] = { kind = "info", label = "Passive Perception", value = tostring(passive) }
	if c.spellAbility then
		local pb = Sheet.proficiency(c.level)
		local sm = Sheet.mod(c.abilities[c.spellAbility])
		rows[#rows + 1] = { kind = "info", label = "Spell Save DC", value = tostring(8 + pb + sm) }
		rows[#rows + 1] = { kind = "info", label = "Spell Attack", value = signed(pb + sm) }
	end
	return { title = "ABILITY", rows = rows }
end

local function savesPage(c)
	local rows = {}
	local pb = Sheet.proficiency(c.level)
	for _, ab in ipairs(Sheet.ABILITIES) do
		local prof = hasSave(c, ab)
		local b = Sheet.mod(c.abilities[ab]) + (prof and pb or 0)
		rows[#rows + 1] = {
			kind = "roll", label = Sheet.ABILITY_NAMES[ab], value = signed(b),
			mark = prof and "prof" or "none", spec = Dice.check(b), rollKind = "check",
			title = Sheet.ABILITY_NAMES[ab] .. " save",
		}
	end
	rows[#rows + 1] = { kind = "header", label = "Other" }
	rows[#rows + 1] = {
		kind = "roll", label = "Death Save", detail = "10+ ok", value = "d20",
		spec = Dice.check(0), rollKind = "check",
	}
	return { title = "SAVES", rows = rows }
end

local function skillsPage(c)
	local rows = {}
	for _, sk in ipairs(Sheet.SKILLS) do
		local key, name, ab = sk[1], sk[2], sk[3]
		local b, level = Sheet.skillBonus(c, key, ab)
		rows[#rows + 1] = {
			kind = "roll", label = name, detail = ab:upper(), value = signed(b),
			mark = (level == 2 and "exp") or (level == 1 and "prof") or "none",
			spec = Dice.check(b), rollKind = "check",
		}
	end
	return { title = "SKILLS", rows = rows }
end

local function actionsPage(c)
	local rows = {}
	local pb = Sheet.proficiency(c.level)
	for _, a in ipairs(c.actions) do
		if a.section then
			rows[#rows + 1] = { kind = "header", label = a.section }
		elseif a.info then
			rows[#rows + 1] = { kind = "info", label = a.name, value = a.info }
		elseif a.heal then
			rows[#rows + 1] = {
				kind = "roll", label = a.name, detail = a.note, value = a.heal,
				spec = Dice.parse(a.heal), rollKind = "heal",
			}
		elseif a.atk then
			local ab = (a.atk == "spell") and c.spellAbility or a.atk
			local hit = Sheet.mod(c.abilities[ab]) + pb
			local crit = (a.atk ~= "spell") and c.critRange or 20
			rows[#rows + 1] = {
				kind = "roll", label = a.name, detail = a.note, value = signed(hit),
				spec = Dice.check(hit, crit), rollKind = "check", title = a.name .. " attack",
			}
			rows[#rows + 1] = {
				kind = "roll", label = a.type or "damage", value = a.dmg, indent = true,
				spec = Dice.parse(a.dmg), rollKind = "damage", critable = true,
				title = a.name .. " damage",
			}
		else
			local detail = a.note
			if a.save then
				local dc = 8 + pb + Sheet.mod(c.abilities[c.spellAbility])
				detail = "DC" .. dc .. " " .. a.save:upper()
			elseif a.auto then
				detail = "auto-hit"
			end
			rows[#rows + 1] = {
				kind = "roll", label = a.name, detail = detail, value = a.dmg,
				spec = Dice.parse(a.dmg), rollKind = "damage", critable = a.critable,
				title = a.name .. (a.type and (" (" .. a.type .. ")") or ""),
			}
		end
	end
	return { title = "ACTIONS", rows = rows }
end

local function dicePage()
	local rows = {}
	local function add(label, expr, value)
		local spec = Dice.parse(expr)
		if expr == "1d20" then spec.check = true end
		rows[#rows + 1] = {
			kind = "roll", label = label, value = value, spec = spec, rollKind = "pool",
		}
	end
	for _, s in ipairs({ 4, 6, 8, 10, 12, 20, 100 }) do
		add("d" .. s, "1d" .. s)
	end
	add("2d6", "2d6")
	add("Ability score", "4d6kh3", "4d6 drop 1")
	add("Fireball", "8d6", "8d6")
	return { title = "DICE", rows = rows }
end

function Sheet.build(c)
	return {
		abilitiesPage(c),
		savesPage(c),
		skillsPage(c),
		actionsPage(c),
		dicePage(),
	}
end
