// Rule text for the pause card and Rules viewer: a port of charsheet/source/rules.lua.
import { signed, mod, proficiency, ABILITY_NAMES } from "./sheet.js";

const ABILITY = {
	str: "Physical power: lifting, pushing, climbing and breaking things. Adds to melee attack and damage rolls (except finesse) and to Athletics.",
	dex: "Agility, reflexes and balance. Adds to AC in light or medium armor, initiative, ranged and finesse attacks, Acrobatics, Sleight of Hand and Stealth.",
	con: "Health and stamina. Adds to your hit points at every level and to the saves that keep you concentrating on a spell.",
	int: "Reasoning and memory. Used for Arcana, History, Investigation, Nature and Religion. Wizards cast spells with it.",
	wis: "Awareness and intuition. Used for Animal Handling, Insight, Medicine, Perception and Survival. Clerics, druids and rangers cast with it.",
	cha: "Force of personality. Used for Deception, Intimidation, Performance and Persuasion. Bards, paladins, sorcerers and warlocks cast with it.",
};

const SAVE = {
	str: "Resist a force that would shove, grapple or pin you in place.",
	dex: "Dodge out of harm's way: fireballs, traps, breath weapons, collapsing ceilings.",
	con: "Endure poison, disease and exhaustion. When you take damage while concentrating on a spell, make one (DC 10 or half the damage, whichever is higher) to keep it going.",
	int: "Disbelieve illusions and resist effects that attack the logic of your mind.",
	wis: "Resist being charmed, frightened or otherwise having your will controlled.",
	cha: "Resist possession, banishment and effects that assault your sense of self.",
};

const SKILL = {
	acrobatics: "Keep your balance on ice or a tightrope, tumble past foes, or wriggle free of a grapple.",
	animalHandling: "Calm an animal, keep a mount from panicking, or read an animal's intentions.",
	arcana: "Recall lore about spells, magic items, eldritch symbols, magical traditions and the planes.",
	athletics: "Climb, jump and swim, or grapple and shove with raw strength.",
	deception: "Hide the truth convincingly, with words or actions: bluffs, disguises, misdirection.",
	history: "Recall lore about past events, legendary people, ancient kingdoms and lost civilizations.",
	insight: "Read body language and tone to tell if someone is lying or guess their next move.",
	intimidation: "Sway someone with threats, hostile actions or a show of force.",
	investigation: "Look for clues and make deductions: find a hidden lever, spot a weak point, piece together evidence.",
	medicine: "Stabilize a dying companion (DC 10) or diagnose an illness.",
	nature: "Recall lore about terrain, plants, animals, weather and natural cycles.",
	perception: "Spot, hear or otherwise notice something: an ambush, voices behind a door, a hidden trapdoor.",
	performance: "Delight an audience with music, dance, acting or storytelling.",
	persuasion: "Win someone over with tact, social graces and good nature.",
	religion: "Recall lore about deities, rites, prayers, holy symbols and religious orders.",
	sleightOfHand: "Pick a pocket, plant an item on someone, or palm a small object unseen.",
	stealth: "Hide, sneak past guards, or slip away without being noticed.",
	survival: "Follow tracks, hunt game, find your way through the wilds and avoid natural hazards.",
};

const CHECK = "Roll d20 + modifier and meet the DM's DC (10 easy, 15 medium, 20 hard).";
const CRIT = "A natural 20 always hits and crits (x2 damage dice); a natural 1 always misses.";

const abName = (ab) => ABILITY_NAMES[ab] || ab;
const join = (...parts) => parts.filter((s) => typeof s === "string" && s !== "").join("\n\n");
const featureById = (c, id) => (c.features || []).find((f) => f.id === id);

function costText(c, a) {
	if (a.slot) return "Uses a level " + a.slot + " spell slot.";
	if (a.uses) {
		const f = featureById(c, a.uses);
		if (f) return `Uses ${f.name} (${f.max} per ${f.reset} rest).`;
	}
	return undefined;
}

function featureRule(c, f) {
	if (f.rule) return f.rule;
	const a = c.actions.find((x) => x.uses === f.id && x.rule);
	return a && a.rule;
}

function describeAction(c, row, h) {
	const a = h.action;
	const pb = proficiency(c.level);
	const cost = costText(c, a);
	if (h.kind === "attack") {
		const ab = a.atk === "spell" ? c.spellAbility : a.atk;
		const how = a.hit != null ? signed(a.hit) + " to hit"
			: `${signed(mod(c.abilities[ab]) + pb)} = ${ab.toUpperCase()} ${signed(mod(c.abilities[ab]))}, prof ${signed(pb)}`;
		return { title: a.name, sub: how, body: join(a.rule, "Roll vs the target's AC. " + CRIT, cost) };
	}
	if (h.kind === "damage") {
		return {
			title: a.name + " damage", sub: a.dmg + " " + (a.type || ""),
			body: join(a.rule, "Roll after a hit; a crit doubles the dice. Resistance halves the total, vulnerability doubles it."),
		};
	}
	if (h.kind === "spellSave") {
		const dc = a.dc ?? (8 + pb + mod(c.abilities[c.spellAbility]));
		return {
			title: a.name, sub: `DC ${dc} ${abName(a.save)} save`,
			body: join(a.rule,
				`Each target rolls a ${abName(a.save)} save against DC ${dc}. A failure takes the full ${a.dmg}${a.type ? " " + a.type : ""}; many effects deal half on a success.`,
				cost),
		};
	}
	if (h.kind === "heal") {
		return {
			title: a.name, sub: "Heals " + a.heal,
			body: join(a.rule, a.selfHeal ? "The rolled amount is added to your current HP."
				: "A creature regains the rolled hit points, up to its maximum.", cost),
		};
	}
	if (h.kind === "info") return { title: a.name, sub: a.info, body: a.rule || "" };
	return {
		title: a.name, sub: a.dmg + (a.type ? " " + a.type : ""),
		body: join(a.rule, a.auto ? "Hits automatically; no attack roll." : undefined, cost),
	};
}

const TRAIT = {
	fly: "Fly up to this speed on your turn. If you're knocked prone or your speed drops to 0 while flying, you fall unless you can hover.",
	swim: "Swim at this speed without spending extra movement.",
	climb: "Climb at this speed without spending extra movement.",
	burrow: "Burrow through sand, earth, mud or ice at this speed.",
	darkvision: "Within this range you see in dim light as if it were bright light, and in darkness as if it were dim light. In darkness you see only shades of gray.",
	blindsight: "You perceive your surroundings within this range without relying on sight.",
	tremorsense: "You sense and pinpoint vibrations within this range, as long as you and the source touch the same ground or liquid.",
	truesight: "Within this range you see in normal and magical darkness, see invisible creatures and objects, see through visual illusions, and see the true form of shapechangers.",
};

const TRAIT_GROUP = {
	speeds: ["Speed", "Split your move between your speeds; whatever you've moved counts against each of them."],
	senses: ["Sense", ""],
	languages: ["Language", "You can speak, read and write this language."],
	resistances: ["Damage resistance", "You take half damage of this type (rounded down)."],
	immunities: ["Damage immunity", "You take no damage of this type."],
	vulnerabilities: ["Damage vulnerability", "You take double damage of this type."],
	conditionImmunities: ["Condition immunity", "This condition can't affect you."],
	armor: ["Armor proficiency", "You're trained to wear this. In armor you aren't trained with, you have disadvantage on STR and DEX rolls and can't cast spells."],
	weapons: ["Weapon proficiency", "Add your proficiency bonus to attack rolls with these weapons."],
	tools: ["Tool proficiency", "Add your proficiency bonus to ability checks you make with these tools."],
};

function describeTrait(row, h) {
	const g = (Object.hasOwn(TRAIT_GROUP, h.group) && TRAIT_GROUP[h.group]) || ["Trait", ""];
	const title = h.group === "speeds" ? row.label + " Speed" : row.label;
	let sub = g[0];
	if (row.value && (h.group === "speeds" || h.group === "senses")) sub += ", " + row.value;
	return { title, sub, body: join(Object.hasOwn(TRAIT, h.key) ? TRAIT[h.key] : undefined, g[1]) };
}

function describeResource(c, row) {
	const key = row.key;
	if (key === "inspiration") {
		return {
			title: "Heroic Inspiration", sub: "Have it or not",
			body: "The DM awards it for great roleplaying or heroics (2024 humans gain it on every long rest). " +
				"Spend it to reroll one die right after you roll it, and use the new roll. You can't hold more than one.\n\n" +
				"In 2014 rules, Inspiration instead gives advantage on one attack, save or check.\n\nⒶ to spend, Ⓑ to gain.",
		};
	}
	if (key === "exhaustion") {
		return {
			title: "Exhaustion", sub: "Levels 0-6",
			body: "Each long rest removes one level. At level 6 you die.\n\n" +
				"2024 rules: d20 tests take -2 per level and your speed drops by 5 ft per level.\n\n" +
				"2014 rules, by level: 1 disadvantage on ability checks; 2 speed halved; " +
				"3 disadvantage on attacks and saves; 4 HP max halved; 5 speed 0.\n\n" +
				"Penalties aren't applied to rolls here. Crank or Ⓐ/Ⓑ to adjust.",
		};
	}
	if (key === "hp") {
		return {
			title: "Hit Points", sub: "Max " + c.hp,
			body: "Damage lowers your HP. At 0 you fall unconscious and start making death saves. " +
				"Healing can't take you above your maximum. A long rest restores all of it.\n\n" +
				"Crank or Ⓐ/Ⓑ to track damage and healing.",
		};
	}
	if (key === "hitDice") {
		return {
			title: "Hit Dice", sub: `${c.level} x d${c.hitDie}`,
			body: `During a short rest, spend Hit Dice to heal: each one heals d${c.hitDie} + CON modifier. A long rest gives back half your total (at least 1).`,
		};
	}
	if (key === "deathSaves" || key === "deathFails") {
		return {
			title: key === "deathSaves" ? "Death Save Successes" : "Death Save Failures", sub: "At 0 HP",
			body: "Three successes and you're stable; three failures and you die. Taking damage at 0 HP " +
				"is a failure (a critical hit is two). Rolling Death Save here records it for you; " +
				"any healing clears both.\n\nCrank or Ⓐ/Ⓑ to adjust.",
		};
	}
	const m = key.match(/^slot(\d+)$/);
	if (m) {
		const lvl = +m[1];
		return {
			title: `Level ${lvl} Spell Slots`, sub: "Max " + (c.slots[lvl - 1] || 0),
			body: `Casting a spell of level ${lvl} spends one of these (or a higher slot to power it up). Cantrips are free. All slots come back after a long rest.`,
		};
	}
	const f = featureById(c, key);
	if (f) {
		return {
			title: f.name, sub: `${f.max} per ${f.reset} rest`,
			body: join(featureRule(c, f), f.reset === "short"
				? "Uses come back after a short or long rest." : "Uses come back after a long rest."),
		};
	}
	return undefined;
}

const PAGE = {
	ABILITY: "Your six ability scores. Each modifier is (score - 10) / 2, rounded down, and adds to the checks, saves and attacks that use it.",
	SAVES: "Saving throws resist spells, traps and poisons. Roll d20 + modifier, plus proficiency if you're proficient, against the effect's DC.",
	SKILLS: "Skills are ability checks you can be trained in. ● adds your proficiency bonus, ◉ (expertise) adds it twice.",
	TRAITS: "Speeds, senses, languages, damage and condition defenses, and armor, weapon and tool proficiencies. Ⓐ on a row explains it.",
	ACTIONS: "Your attacks, spells and features. Crank on an attack, then on its damage.",
	STATUS: "Track HP, Hit Dice, Heroic Inspiration, Exhaustion, spell slots and limited features. Crank on a rest at the bottom to recover them.",
	DICE: "Free rolls, plus a custom dice pool you can build.",
};

function describeRow(c, row, page) {
	const h = row && row.help;
	const pb = proficiency(c.level);
	if (!h) {
		if (row && row.kind === "resource") {
			const d = describeResource(c, row);
			if (d) return d;
		}
		return { title: page.title, sub: c.name, body: PAGE[page.title] || "" };
	}
	switch (h.kind) {
		case "ability": {
			const score = c.abilities[h.ab];
			return { title: abName(h.ab), sub: `Score ${score}, modifier ${signed(mod(score))}`, body: join(ABILITY[h.ab], CHECK) };
		}
		case "save": {
			const m = mod(c.abilities[h.ab]);
			return {
				title: abName(h.ab) + " Save",
				sub: `${signed(m + (h.prof ? pb : 0))} = ${h.ab.toUpperCase()} ${signed(m)}${h.prof ? ", prof " + signed(pb) : ""}`,
				body: join(SAVE[h.ab], "Roll d20 + this bonus against the effect's DC."),
			};
		}
		case "skill": {
			const m = mod(c.abilities[h.ab]);
			let sub = `${signed(m + pb * h.level)} = ${h.ab.toUpperCase()} ${signed(m)}`;
			if (h.level === 1) sub += ", prof " + signed(pb);
			if (h.level === 2) sub += ", expert " + signed(pb * 2);
			return { title: row.label, sub, body: join(SKILL[h.key], CHECK) };
		}
		case "death":
			return {
				title: "Death Save", sub: "At 0 HP, each turn",
				body: "Roll a d20 at the start of each turn: 10 or higher is a success, 9 or lower a failure. " +
					"Three successes and you're stable, three failures and you die. A natural 1 counts as two failures; " +
					"a natural 20 brings you back with 1 HP.",
			};
		case "initiative":
			return {
				title: "Initiative", sub: signed(mod(c.abilities.dex)) + " = DEX",
				body: "When combat starts, everyone rolls d20 + DEX modifier. Turns go from highest to lowest.",
			};
		case "pb":
			return {
				title: "Proficiency Bonus", sub: `${signed(pb)} at level ${c.level}`,
				body: "Added to attacks with weapons you're proficient with, your spell attacks and save DCs, " +
					"and saves and skills you're proficient in (twice with expertise). It's +2 at level 1 and rises every 4 levels.",
			};
		case "passive":
			return {
				title: "Passive Perception", sub: "10 + Perception",
				body: "The DM compares hidden creatures' Stealth against this to see if you notice them without rolling.",
			};
		case "spelldc":
		case "spellatk": {
			const m = mod(c.abilities[c.spellAbility]);
			const dc = h.kind === "spelldc";
			return {
				title: dc ? "Spell Save DC" : "Spell Attack",
				sub: (dc ? "8 + prof " + signed(pb) : "prof " + signed(pb)) + ", " + c.spellAbility.toUpperCase() + " " + signed(m),
				body: dc ? "Creatures targeted by your spells roll their save against this number."
					: "Roll d20 + this for spells that make an attack roll, against the target's AC.",
			};
		}
		case "spendHitDie":
			return {
				title: "Spend Hit Die", sub: `d${c.hitDie} + CON`,
				body: `During a short rest, spend a Hit Die to heal d${c.hitDie} + your CON modifier. You can spend as many as you have left, one at a time.`,
			};
		case "rest":
			if (h.rest === "long") {
				return {
					title: "Long Rest", sub: "8 hours, once a day",
					body: "Restores all HP, spell slots and limited-use features, gives back half your total Hit Dice " +
						"(at least 1), and removes one level of Exhaustion.\n\nCrank for a few moments to confirm.",
				};
			}
			return {
				title: "Short Rest", sub: "At least 1 hour",
				body: "Recharges features that come back on a short rest. During it you can spend Hit Dice " +
					"to heal (the row under Hit Dice).\n\nCrank for a few moments to confirm.",
			};
		case "trait":
			return describeTrait(row, h);
		case "pool":
			return {
				title: "Dice Pool", sub: "Build it below",
				body: "Add dice and a modifier with the rows below, then crank here to roll them all together. Ⓑ clears the pool. Saved between launches.",
			};
		case "counter":
			return {
				title: row.label, sub: "Pool builder",
				body: "Crank, or press Ⓐ/Ⓑ, to change how many of these go into the pool (up to 12 dice, modifier ±20).",
			};
		case "quick":
			return { title: row.label, sub: h.expr, body: h.text || "A quick roll, no modifiers." };
		default:
			if (h.action) return describeAction(c, row, h);
	}
	return { title: row.label || page.title, sub: "", body: "" };
}

export function describe(c, row, page) {
	const d = describeRow(c, row, page);
	if (c.lucky && row && row.spec && row.spec.check && row.rollKind === "check") {
		d.body = join(d.body, "Halfling Lucky: a natural 1 on this roll is rerolled.");
	}
	return d;
}
