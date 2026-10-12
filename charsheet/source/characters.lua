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
-- Optional overrides (used by imported characters):
--   hit = 7   attack bonus instead of ability mod + proficiency
--   dc = 13   save DC instead of 8 + proficiency + spellcasting mod
-- Optional action costs (spent automatically when rolled):
--   slot = 1        uses a spell slot of that level
--   uses = "id"     uses a charge of a limited feature
--   selfHeal = true healing is applied to the character's own HP
-- Optional rule = "text" on actions and features: shown on the pause screen.
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
			{ id = "secondWind", name = "Second Wind", max = 1, reset = "short", rule = "Bonus action: catch your breath and regain 1d10 + fighter level hit points." },
			{ id = "actionSurge", name = "Action Surge", max = 1, reset = "short", rule = "Push past your limits: take one extra action on your turn." },
		},
		actions = {
			{ section = "Weapons" },
			{ name = "Longsword", atk = "str", dmg = "1d8+5", type = "slashing", note = "Dueling", rule = "Versatile martial blade. Dueling style adds +2 damage when you fight with one weapon in one hand and nothing in the other." },
			{ name = "Handaxe", atk = "str", dmg = "1d6+3", type = "slashing", note = "20/60 ft", rule = "Light simple weapon you can also throw (20 ft normal, 60 ft long range at disadvantage)." },
			{ section = "Features" },
			{ name = "Second Wind", heal = "1d10+3", note = "bonus", uses = "secondWind", selfHeal = true, rule = "Bonus action: catch your breath and regain 1d10 + fighter level hit points." },
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
			{ id = "arcaneRecovery", name = "Arcane Recovery", max = 1, reset = "long", rule = "Once a day during a short rest, recover spell slots totaling up to half your wizard level (rounded up)." },
		},
		actions = {
			{ section = "Weapons" },
			{ name = "Dagger", atk = "dex", dmg = "1d4+3", type = "piercing", note = "finesse", rule = "Finesse, light and thrown (20/60 ft). Finesse lets you use STR or DEX for attack and damage." },
			{ section = "Cantrips" },
			{ name = "Fire Bolt", atk = "spell", dmg = "1d10", type = "fire", note = "120 ft", rule = "Cantrip. Hurl a mote of fire; it ignites flammable objects that aren't worn or carried." },
			{ name = "Ray of Frost", atk = "spell", dmg = "1d8", type = "cold", note = "60 ft", rule = "Cantrip. A frigid beam; on a hit the target's speed drops by 10 ft until your next turn." },
			{ section = "Spells" },
			{ name = "Magic Missile", auto = true, dmg = "3d4+3", type = "force", note = "L1", slot = 1, rule = "Three glowing darts that always hit, 1d4+1 force each. Aim them at one target or several." },
			{ name = "Burning Hands", save = "dex", dmg = "3d6", type = "fire", note = "L1", slot = 1, rule = "A 15-ft cone of flame. Creatures in it make a DEX save, taking half on a success." },
			{ name = "Scorching Ray", atk = "spell", dmg = "2d6", type = "fire", note = "L2 x3", slot = 2, rule = "Three rays, each a separate spell attack for 2d6 fire. Split them between targets as you like." },
			{ name = "Shatter", save = "con", dmg = "3d8", type = "thunder", note = "L2", slot = 2, rule = "A ringing burst in a 10-ft sphere. CON save for half; inorganic creatures save at disadvantage." },
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
			{ name = "Shortsword", atk = "dex", dmg = "1d6+3", type = "piercing", note = "finesse", rule = "Finesse and light, perfect for Sneak Attack or fighting with two weapons." },
			{ name = "Shortbow", atk = "dex", dmg = "1d6+3", type = "piercing", note = "80/320", rule = "Two-handed ranged weapon (80 ft normal, 320 ft long range at disadvantage)." },
			{ name = "Dagger", atk = "dex", dmg = "1d4+3", type = "piercing", note = "20/60", rule = "Finesse, light and thrown (20/60 ft). Finesse lets you use STR or DEX for attack and damage." },
			{ section = "Features" },
			{ name = "Sneak Attack", dmg = "2d6", type = "extra", note = "1/turn", critable = true, rule = "Once per turn, add this to a finesse or ranged hit if you have advantage, or an ally is next to the target (and you don't have disadvantage)." },
			{ name = "Cunning Action", info = "bonus", rule = "Your quick wits let you Dash, Disengage or Hide as a bonus action." },
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
			{ id = "channelDivinity", name = "Channel Divinity", max = 1, reset = "short", rule = "Channel divine energy for an effect like Turn Undead or Preserve Life. Recharges on a short rest." },
		},
		actions = {
			{ section = "Weapons" },
			{ name = "Mace", atk = "str", dmg = "1d6+2", type = "bludgeoning", rule = "Simple one-handed bludgeon, favored by clerics." },
			{ section = "Cantrips" },
			{ name = "Sacred Flame", save = "dex", dmg = "1d8", type = "radiant", note = "60 ft", rule = "Cantrip. Radiant flame descends on a creature you can see; it gets no benefit from cover against the DEX save." },
			{ section = "Spells" },
			{ name = "Guiding Bolt", atk = "spell", dmg = "4d6", type = "radiant", note = "L1", slot = 1, rule = "A flash of light. On a hit, the next attack roll against the target before your next turn has advantage." },
			{ name = "Cure Wounds", heal = "1d8+6", note = "L1", slot = 1, rule = "Touch a creature to heal it. Life Domain's Disciple of Life adds 2 + the spell's level." },
			{ name = "Healing Word", heal = "1d4+6", note = "L1", slot = 1, rule = "Bonus action, 60 ft range. A quick word heals a creature you can see; great for picking up downed allies." },
			{ name = "Spiritual Weapon", atk = "spell", dmg = "1d8+3", type = "force", note = "L2", slot = 2, rule = "Bonus action: a floating spectral weapon appears and attacks. On later turns, move it 20 ft and attack again as a bonus action. Lasts 1 minute." },
			{ name = "Preserve Life", info = "15 HP", rule = "Channel Divinity: split 5 x cleric level hit points among creatures within 30 ft, but heal none of them above half their maximum." },
		},
	},
}
