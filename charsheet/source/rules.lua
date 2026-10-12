-- Rule text shown on the left of the pause screen for the selected row.
--
-- Rules.describe(c, row, page) -> { title, sub, body }
-- Rows carry a `help` table set by sheet.lua; actions and features may carry
-- their own `rule` text (prebuilt summaries, or D&D Beyond descriptions).

Rules = {}

local ABILITY <const> = {
	str = "Physical power: lifting, pushing, climbing and breaking things. Adds to melee attack and damage rolls (except finesse) and to Athletics.",
	dex = "Agility, reflexes and balance. Adds to AC in light or medium armor, initiative, ranged and finesse attacks, Acrobatics, Sleight of Hand and Stealth.",
	con = "Health and stamina. Adds to your hit points at every level and to the saves that keep you concentrating on a spell.",
	int = "Reasoning and memory. Used for Arcana, History, Investigation, Nature and Religion. Wizards cast spells with it.",
	wis = "Awareness and intuition. Used for Animal Handling, Insight, Medicine, Perception and Survival. Clerics, druids and rangers cast with it.",
	cha = "Force of personality. Used for Deception, Intimidation, Performance and Persuasion. Bards, paladins, sorcerers and warlocks cast with it.",
}

local SAVE <const> = {
	str = "Resist a force that would shove, grapple or pin you in place.",
	dex = "Dodge out of harm's way: fireballs, traps, breath weapons, collapsing ceilings.",
	con = "Endure poison, disease and exhaustion. When you take damage while concentrating on a spell, make one (DC 10 or half the damage, whichever is higher) to keep it going.",
	int = "Disbelieve illusions and resist effects that attack the logic of your mind.",
	wis = "Resist being charmed, frightened or otherwise having your will controlled.",
	cha = "Resist possession, banishment and effects that assault your sense of self.",
}

local SKILL <const> = {
	acrobatics = "Keep your balance on ice or a tightrope, tumble past foes, or wriggle free of a grapple.",
	animalHandling = "Calm an animal, keep a mount from panicking, or read an animal's intentions.",
	arcana = "Recall lore about spells, magic items, eldritch symbols, magical traditions and the planes.",
	athletics = "Climb, jump and swim, or grapple and shove with raw strength.",
	deception = "Hide the truth convincingly, with words or actions: bluffs, disguises, misdirection.",
	history = "Recall lore about past events, legendary people, ancient kingdoms and lost civilizations.",
	insight = "Read body language and tone to tell if someone is lying or guess their next move.",
	intimidation = "Sway someone with threats, hostile actions or a show of force.",
	investigation = "Look for clues and make deductions: find a hidden lever, spot a weak point, piece together evidence.",
	medicine = "Stabilize a dying companion (DC 10) or diagnose an illness.",
	nature = "Recall lore about terrain, plants, animals, weather and natural cycles.",
	perception = "Spot, hear or otherwise notice something: an ambush, voices behind a door, a hidden trapdoor.",
	performance = "Delight an audience with music, dance, acting or storytelling.",
	persuasion = "Win someone over with tact, social graces and good nature.",
	religion = "Recall lore about deities, rites, prayers, holy symbols and religious orders.",
	sleightOfHand = "Pick a pocket, plant an item on someone, or palm a small object unseen.",
	stealth = "Hide, sneak past guards, or slip away without being noticed.",
	survival = "Follow tracks, hunt game, find your way through the wilds and avoid natural hazards.",
}

local CHECK <const> = "Roll d20 + modifier and meet the DM's DC (10 easy, 15 medium, 20 hard)."
local CRIT <const> = "A natural 20 always hits and crits (x2 damage dice); a natural 1 always misses."

local function signed(n) return Sheet.signed(n) end

local function abName(ab) return Sheet.ABILITY_NAMES[ab] or ab end

local function costText(c, a)
	if a.slot then
		return "Uses a level " .. a.slot .. " spell slot."
	elseif a.uses then
		for _, f in ipairs(c.features or {}) do
			if f.id == a.uses then
				return "Uses " .. f.name .. " (" .. f.max .. " per " .. f.reset .. " rest)."
			end
		end
	end
end

local function join(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local s = select(i, ...)
		if type(s) == "string" and s ~= "" then parts[#parts + 1] = s end
	end
	return table.concat(parts, "\n\n")
end

local function featureById(c, id)
	for _, f in ipairs(c.features or {}) do
		if f.id == id then return f end
	end
end

-- The rule text of the action that spends a feature, if any.
local function featureRule(c, f)
	if f.rule then return f.rule end
	for _, a in ipairs(c.actions) do
		if a.uses == f.id and a.rule then return a.rule end
	end
end

local function describeAction(c, row, h)
	local a = h.action
	local pb = Sheet.proficiency(c.level)
	local cost = costText(c, a)
	if h.kind == "attack" then
		local spell = a.atk == "spell"
		local ab = spell and c.spellAbility or a.atk
		local how
		if a.hit then
			how = signed(a.hit) .. " to hit"
		else
			how = signed(Sheet.mod(c.abilities[ab]) + pb) .. " = " .. ab:upper() .. " " ..
				signed(Sheet.mod(c.abilities[ab])) .. ", prof " .. signed(pb)
		end
		return {
			title = a.name, sub = how,
			body = join(a.rule,
				"Roll vs the target's AC. " .. CRIT,
				cost),
		}
	elseif h.kind == "damage" then
		return {
			title = a.name .. " damage", sub = a.dmg .. " " .. (a.type or ""),
			body = join(a.rule,
				"Roll after a hit; a crit doubles the dice. Resistance halves the total, vulnerability doubles it."),
		}
	elseif h.kind == "spellSave" then
		local dc = a.dc or (8 + pb + Sheet.mod(c.abilities[c.spellAbility]))
		return {
			title = a.name, sub = "DC " .. dc .. " " .. abName(a.save) .. " save",
			body = join(a.rule,
				"Each target rolls a " .. abName(a.save) .. " save against DC " .. dc ..
				". A failure takes the full " .. a.dmg .. (a.type and (" " .. a.type) or "") ..
				"; many effects deal half on a success.",
				cost),
		}
	elseif h.kind == "heal" then
		return {
			title = a.name, sub = "Heals " .. a.heal,
			body = join(a.rule,
				a.selfHeal and "The rolled amount is added to your current HP." or
				"A creature regains the rolled hit points, up to its maximum.",
				cost),
		}
	elseif h.kind == "info" then
		return { title = a.name, sub = a.info, body = a.rule or "" }
	end
	return {
		title = a.name, sub = a.dmg .. (a.type and (" " .. a.type) or ""),
		body = join(a.rule, a.auto and "Hits automatically; no attack roll." or nil, cost),
	}
end

local function describeResource(c, row)
	local key = row.key
	if key == "hp" then
		return {
			title = "Hit Points", sub = "Max " .. c.hp,
			body = "Damage lowers your HP. At 0 you fall unconscious and start making death saves. " ..
				"Healing can't take you above your maximum. A long rest restores all of it.\n\n" ..
				"Crank or Ⓐ/Ⓑ to track damage and healing.",
		}
	elseif key == "hitDice" then
		return {
			title = "Hit Dice", sub = c.level .. " x d" .. c.hitDie,
			body = "During a short rest, spend Hit Dice to heal: each one heals d" .. c.hitDie ..
				" + CON modifier. A long rest gives back half your total (at least 1).",
		}
	elseif key:match("^slot%d+$") then
		local lvl = tonumber(key:sub(5))
		return {
			title = "Level " .. lvl .. " Spell Slots", sub = "Max " .. (c.slots[lvl] or 0),
			body = "Casting a spell of level " .. lvl .. " spends one of these (or a higher slot to power it up). " ..
				"Cantrips are free. All slots come back after a long rest.",
		}
	end
	local f = featureById(c, key)
	if f then
		return {
			title = f.name, sub = f.max .. " per " .. f.reset .. " rest",
			body = join(featureRule(c, f),
				f.reset == "short" and "Uses come back after a short or long rest." or "Uses come back after a long rest."),
		}
	end
end

local PAGE <const> = {
	ABILITY = "Your six ability scores. Each modifier is (score - 10) / 2, rounded down, and adds to the checks, saves and attacks that use it.",
	SAVES = "Saving throws resist spells, traps and poisons. Roll d20 + modifier, plus proficiency if you're proficient, against the effect's DC.",
	SKILLS = "Skills are ability checks you can be trained in. ● adds your proficiency bonus, ◉ (expertise) adds it twice.",
	ACTIONS = "Your attacks, spells and features. Crank on an attack, then on its damage.",
	STATUS = "Track HP, Hit Dice, spell slots and limited features. Rest from the menu to recover them.",
	DICE = "Free rolls, plus a custom dice pool you can build.",
}

local function describe(c, row, page)
	local h = row and row.help
	local pb = Sheet.proficiency(c.level)
	if not h then
		if row and row.kind == "resource" then
			local d = describeResource(c, row)
			if d then return d end
		end
		return { title = page.title, sub = c.name, body = PAGE[page.title] or "" }
	end

	if h.kind == "ability" then
		local score = c.abilities[h.ab]
		return {
			title = abName(h.ab), sub = "Score " .. score .. ", modifier " .. signed(Sheet.mod(score)),
			body = join(ABILITY[h.ab], CHECK),
		}
	elseif h.kind == "save" then
		local m = Sheet.mod(c.abilities[h.ab])
		return {
			title = abName(h.ab) .. " Save",
			sub = signed(m + (h.prof and pb or 0)) .. " = " .. h.ab:upper() .. " " .. signed(m) ..
				(h.prof and (", prof " .. signed(pb)) or ""),
			body = join(SAVE[h.ab], "Roll d20 + this bonus against the effect's DC."),
		}
	elseif h.kind == "skill" then
		local m = Sheet.mod(c.abilities[h.ab])
		local sub = signed(m + pb * h.level) .. " = " .. h.ab:upper() .. " " .. signed(m)
		if h.level == 1 then sub = sub .. ", prof " .. signed(pb) end
		if h.level == 2 then sub = sub .. ", expert " .. signed(pb * 2) end
		return { title = row.label, sub = sub, body = join(SKILL[h.key], CHECK) }
	elseif h.kind == "death" then
		return {
			title = "Death Save", sub = "At 0 HP, each turn",
			body = "Roll a d20 at the start of each turn: 10 or higher is a success, 9 or lower a failure. " ..
				"Three successes and you're stable, three failures and you die. A natural 1 counts as two failures; " ..
				"a natural 20 brings you back with 1 HP.",
		}
	elseif h.kind == "initiative" then
		return {
			title = "Initiative", sub = signed(Sheet.mod(c.abilities.dex)) .. " = DEX",
			body = "When combat starts, everyone rolls d20 + DEX modifier. Turns go from highest to lowest.",
		}
	elseif h.kind == "pb" then
		return {
			title = "Proficiency Bonus", sub = signed(pb) .. " at level " .. c.level,
			body = "Added to attacks with weapons you're proficient with, your spell attacks and save DCs, " ..
				"and saves and skills you're proficient in (twice with expertise). It's +2 at level 1 and rises every 4 levels.",
		}
	elseif h.kind == "passive" then
		return {
			title = "Passive Perception", sub = "10 + Perception",
			body = "The DM compares hidden creatures' Stealth against this to see if you notice them without rolling.",
		}
	elseif h.kind == "spelldc" or h.kind == "spellatk" then
		local m = Sheet.mod(c.abilities[c.spellAbility])
		local dc = h.kind == "spelldc"
		return {
			title = dc and "Spell Save DC" or "Spell Attack",
			sub = (dc and ("8 + prof " .. signed(pb)) or ("prof " .. signed(pb))) .. ", " ..
				c.spellAbility:upper() .. " " .. signed(m),
			body = dc and "Creatures targeted by your spells roll their save against this number." or
				"Roll d20 + this for spells that make an attack roll, against the target's AC.",
		}
	elseif h.kind == "spendHitDie" then
		return {
			title = "Spend Hit Die", sub = "d" .. c.hitDie .. " + CON",
			body = "During a short rest, spend a Hit Die to heal d" .. c.hitDie ..
				" + your CON modifier. You can spend as many as you have left, one at a time.",
		}
	elseif h.kind == "pool" then
		return {
			title = "Dice Pool", sub = "Build it below",
			body = "Add dice and a modifier with the rows below, then crank here to roll them all together. Ⓑ clears the pool. Saved between launches.",
		}
	elseif h.kind == "counter" then
		return {
			title = row.label, sub = "Pool builder",
			body = "Crank, or press Ⓐ/Ⓑ, to change how many of these go into the pool (up to 12 dice, modifier ±20).",
		}
	elseif h.kind == "quick" then
		return { title = row.label, sub = h.expr, body = h.text or "A quick roll, no modifiers." }
	elseif h.action then
		return describeAction(c, row, h)
	end
	return { title = row.label or page.title, sub = "", body = "" }
end

function Rules.describe(c, row, page)
	local d = describe(c, row, page)
	local d20 = row and row.spec and row.spec.check
	if c.lucky and d20 and row.rollKind == "check" then
		d.body = join(d.body, "Halfling Lucky: a natural 1 on this roll is rerolled.")
	end
	return d
end

-- Escapes Playdate text styling (*bold*, _italic_) in free text.
function Rules.plain(s)
	if type(s) ~= "string" then return "" end
	return (s:gsub("%*", "**"):gsub("_", "__"))
end
