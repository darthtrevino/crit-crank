-- Prebuilt level 3 characters (D&D 5e SRD rules).
--
-- skills: 1 = proficient, 2 = expertise.
-- actions entries:
--   { section = "Title" }                         section header
--   { name, atk = "str"|"dex"|"spell", dmg, ... } attack roll + damage roll
--   { name, save = "dex", dmg, ... }              saving-throw effect (damage only)
--   { name, auto = true, dmg, ... }               auto-hit damage
--   { name, heal = "1d8+6", ... }                 healing
--   { name, info = "text" }                       non-rollable note
-- Optional action costs (spent automatically when rolled):
--   slot = 1        uses a spell slot of that level
--   uses = "id"     uses a charge of a limited feature
--   selfHeal = true healing is applied to the character's own HP
--
-- hitDie: hit die size; slots: spell slots per level;
-- features: limited-use features restored by a "short" or "long" rest.

Characters = {
	{
		name = "Brenna Stoutheart",
		race = "Dwarf",
		class = "Fighter",
		level = 3,
		ac = 18, hp = 31, speed = 25,
		abilities = { str = 16, dex = 12, con = 16, int = 10, wis = 13, cha = 8 },
		saves = { "str", "con" },
		skills = { athletics = 1, intimidation = 1, perception = 1, survival = 1 },
		critRange = 19, -- Champion: Improved Critical
		hitDie = 10,
		features = {
			{ id = "secondWind", name = "Second Wind", max = 1, reset = "short" },
			{ id = "actionSurge", name = "Action Surge", max = 1, reset = "short" },
		},
		actions = {
			{ section = "Weapons" },
			{ name = "Longsword", atk = "str", dmg = "1d8+5", type = "slashing", note = "Dueling" },
			{ name = "Handaxe", atk = "str", dmg = "1d6+3", type = "slashing", note = "20/60 ft" },
			{ section = "Features" },
			{ name = "Second Wind", heal = "1d10+3", note = "bonus", uses = "secondWind", selfHeal = true },
		},
	},
	{
		name = "Elowen Starwhisper",
		race = "High Elf",
		class = "Wizard",
		level = 3,
		ac = 13, hp = 17, speed = 30,
		abilities = { str = 8, dex = 16, con = 13, int = 16, wis = 12, cha = 10 },
		saves = { "int", "wis" },
		skills = { arcana = 1, history = 1, investigation = 1, insight = 1, perception = 1 },
		spellAbility = "int",
		hitDie = 6,
		slots = { 4, 2 },
		features = {
			{ id = "arcaneRecovery", name = "Arcane Recovery", max = 1, reset = "long" },
		},
		actions = {
			{ section = "Weapons" },
			{ name = "Dagger", atk = "dex", dmg = "1d4+3", type = "piercing", note = "finesse" },
			{ section = "Cantrips" },
			{ name = "Fire Bolt", atk = "spell", dmg = "1d10", type = "fire", note = "120 ft" },
			{ name = "Ray of Frost", atk = "spell", dmg = "1d8", type = "cold", note = "60 ft" },
			{ section = "Spells" },
			{ name = "Magic Missile", auto = true, dmg = "3d4+3", type = "force", note = "L1", slot = 1 },
			{ name = "Burning Hands", save = "dex", dmg = "3d6", type = "fire", note = "L1", slot = 1 },
			{ name = "Scorching Ray", atk = "spell", dmg = "2d6", type = "fire", note = "L2 x3", slot = 2 },
			{ name = "Shatter", save = "con", dmg = "3d8", type = "thunder", note = "L2", slot = 2 },
		},
	},
	{
		name = "Pip Thistlefoot",
		race = "Halfling",
		class = "Rogue",
		level = 3,
		ac = 14, hp = 24, speed = 25,
		abilities = { str = 8, dex = 17, con = 14, int = 12, wis = 10, cha = 14 },
		saves = { "dex", "int" },
		skills = {
			acrobatics = 1, deception = 1, investigation = 1,
			perception = 2, sleightOfHand = 1, stealth = 2,
		},
		lucky = true, -- Halfling Lucky: reroll natural 1s on d20 tests
		hitDie = 8,
		actions = {
			{ section = "Weapons" },
			{ name = "Shortsword", atk = "dex", dmg = "1d6+3", type = "piercing", note = "finesse" },
			{ name = "Shortbow", atk = "dex", dmg = "1d6+3", type = "piercing", note = "80/320" },
			{ name = "Dagger", atk = "dex", dmg = "1d4+3", type = "piercing", note = "20/60" },
			{ section = "Features" },
			{ name = "Sneak Attack", dmg = "2d6", type = "extra", note = "1/turn", critable = true },
			{ name = "Cunning Action", info = "bonus" },
		},
	},
	{
		name = "Brother Aldric",
		race = "Human",
		class = "Cleric",
		level = 3,
		ac = 18, hp = 24, speed = 30,
		abilities = { str = 14, dex = 10, con = 14, int = 10, wis = 16, cha = 12 },
		saves = { "wis", "cha" },
		skills = { insight = 1, medicine = 1, persuasion = 1, religion = 1 },
		spellAbility = "wis",
		hitDie = 8,
		slots = { 4, 2 },
		features = {
			{ id = "channelDivinity", name = "Channel Divinity", max = 1, reset = "short" },
		},
		actions = {
			{ section = "Weapons" },
			{ name = "Mace", atk = "str", dmg = "1d6+2", type = "bludgeoning" },
			{ section = "Cantrips" },
			{ name = "Sacred Flame", save = "dex", dmg = "1d8", type = "radiant", note = "60 ft" },
			{ section = "Spells" },
			{ name = "Guiding Bolt", atk = "spell", dmg = "4d6", type = "radiant", note = "L1", slot = 1 },
			{ name = "Cure Wounds", heal = "1d8+6", note = "L1", slot = 1 },
			{ name = "Healing Word", heal = "1d4+6", note = "L1", slot = 1 },
			{ name = "Spiritual Weapon", atk = "spell", dmg = "1d8+3", type = "force", note = "L2", slot = 2 },
			{ name = "Preserve Life", info = "15 HP" },
		},
	},
}
