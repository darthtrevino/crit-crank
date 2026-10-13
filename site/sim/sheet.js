// Pages and rows: a port of charsheet/source/sheet.lua.
import * as Dice from "./dice.js";

export const ABILITIES = ["str", "dex", "con", "int", "wis", "cha"];
export const ABILITY_NAMES = {
	str: "Strength", dex: "Dexterity", con: "Constitution",
	int: "Intelligence", wis: "Wisdom", cha: "Charisma",
};

export const SKILLS = [
	["acrobatics", "Acrobatics", "dex"],
	["animalHandling", "Animal Handling", "wis"],
	["arcana", "Arcana", "int"],
	["athletics", "Athletics", "str"],
	["deception", "Deception", "cha"],
	["history", "History", "int"],
	["insight", "Insight", "wis"],
	["intimidation", "Intimidation", "cha"],
	["investigation", "Investigation", "int"],
	["medicine", "Medicine", "wis"],
	["nature", "Nature", "int"],
	["perception", "Perception", "wis"],
	["performance", "Performance", "cha"],
	["persuasion", "Persuasion", "cha"],
	["religion", "Religion", "int"],
	["sleightOfHand", "Sleight of Hand", "dex"],
	["stealth", "Stealth", "dex"],
	["survival", "Survival", "wis"],
];

export const signed = (n) => (n >= 0 ? "+" + n : String(n));
export const mod = (score) => Math.floor((score - 10) / 2);
export const proficiency = (level) => 2 + Math.floor((level - 1) / 4);

export function skillBonus(c, key, ab) {
	const level = c.skills[key] || 0;
	return [mod(c.abilities[ab]) + proficiency(c.level) * level, level];
}

function abilitiesPage(c) {
	const rows = ABILITIES.map((ab) => {
		const m = mod(c.abilities[ab]);
		return {
			kind: "roll", label: ABILITY_NAMES[ab], detail: String(c.abilities[ab]),
			value: signed(m), spec: Dice.check(m), rollKind: "check",
			title: ABILITY_NAMES[ab] + " check", help: { kind: "ability", ab },
		};
	});
	const dexMod = mod(c.abilities.dex);
	const passive = 10 + skillBonus(c, "perception", "wis")[0];
	rows.push({ kind: "header", label: "Combat" });
	rows.push({ kind: "roll", label: "Initiative", value: signed(dexMod), spec: Dice.check(dexMod), rollKind: "check", help: { kind: "initiative" } });
	rows.push({ kind: "info", label: "Proficiency Bonus", value: signed(proficiency(c.level)), help: { kind: "pb" } });
	rows.push({ kind: "info", label: "Passive Perception", value: String(passive), help: { kind: "passive" } });
	if (c.spellAbility) {
		const pb = proficiency(c.level);
		const sm = mod(c.abilities[c.spellAbility]);
		rows.push({ kind: "info", label: "Spell Save DC", value: String(8 + pb + sm), help: { kind: "spelldc" } });
		rows.push({ kind: "info", label: "Spell Attack", value: signed(pb + sm), help: { kind: "spellatk" } });
	}
	return { title: "ABILITY", rows };
}

const deathSaveRow = () => ({
	kind: "roll", label: "Death Save", detail: "10+ ok", value: "d20",
	spec: Dice.check(0), rollKind: "check", help: { kind: "death" }, deathSave: true,
});

function savesPage(c) {
	const pb = proficiency(c.level);
	const rows = ABILITIES.map((ab) => {
		const prof = c.saves.includes(ab);
		const b = mod(c.abilities[ab]) + (prof ? pb : 0);
		return {
			kind: "roll", label: ABILITY_NAMES[ab], value: signed(b),
			mark: prof ? "prof" : "none", spec: Dice.check(b), rollKind: "check",
			title: ABILITY_NAMES[ab] + " save", help: { kind: "save", ab, prof },
		};
	});
	rows.push({ kind: "header", label: "Other" }, deathSaveRow());
	return { title: "SAVES", rows };
}

function skillsPage(c) {
	const rows = SKILLS.map(([key, name, ab]) => {
		const [b, level] = skillBonus(c, key, ab);
		return {
			kind: "roll", label: name, detail: ab.toUpperCase(), value: signed(b),
			mark: level === 2 ? "exp" : level === 1 ? "prof" : "none",
			spec: Dice.check(b), rollKind: "check", help: { kind: "skill", key, ab, level },
		};
	});
	return { title: "SKILLS", rows };
}

// Traits page groups, in display order: [key in c.traits, label].
export const SPEEDS = [["fly", "Fly"], ["swim", "Swim"], ["climb", "Climb"], ["burrow", "Burrow"]];
export const SENSES = [
	["darkvision", "Darkvision"], ["blindsight", "Blindsight"],
	["tremorsense", "Tremorsense"], ["truesight", "Truesight"],
];
export const DEFENSES = [
	["resistances", "Resist"], ["immunities", "Immune"],
	["vulnerabilities", "Vulnerable"], ["conditionImmunities", "Immune"],
];
export const PROFICIENCIES = [["armor", "Armor"], ["weapons", "Weapons"], ["tools", "Tools"]];

function traitsPage(c) {
	const t = c.traits || {};
	const rows = [];
	const header = (label) => rows.push({ kind: "header", label });
	const trait = (group, key, label, value, detail) => rows.push({
		kind: "trait", key: group + ":" + key, label, value, detail,
		help: { kind: "trait", group, key },
	});
	for (const [group, list, title] of [["speeds", SPEEDS, "Speeds"], ["senses", SENSES, "Senses"]]) {
		const map = t[group] || {};
		let first = true;
		for (const [key, label] of list) {
			const ft = Number(map[key]);
			if (ft > 0) {
				if (first) { header(title); first = false; }
				trait(group, key, label, ft + " ft");
			}
		}
	}
	if (t.languages && t.languages.length) {
		header("Languages");
		for (const l of t.languages) trait("languages", l, l);
	}
	let first = true;
	for (const [group, value] of DEFENSES) {
		for (const name of t[group] || []) {
			if (first) { header("Defenses"); first = false; }
			trait(group, name, name, value, group === "conditionImmunities" ? "condition" : undefined);
		}
	}
	for (const [group, label] of PROFICIENCIES) {
		const list = t[group] || [];
		if (list.length) {
			header(label);
			for (const name of list) trait(group, name, name);
		}
	}
	if (!rows.length) rows.push({ kind: "info", label: c.imported ? "Re-import to add traits" : "No traits recorded" });
	return { title: "TRAITS", rows };
}

function actionsPage(c) {
	const rows = [];
	const pb = proficiency(c.level);
	c.actions.forEach((a, ai) => {
		let cost = null;
		if (a.slot) cost = { key: "slot" + a.slot };
		else if (a.uses) cost = { key: a.uses };
		const first = rows.length;
		if (a.section) {
			rows.push({ kind: "header", label: a.section });
		} else if (a.info) {
			rows.push({ kind: "info", label: a.name, value: a.info, help: { kind: "info", action: a } });
		} else if (a.heal) {
			rows.push({
				kind: "roll", label: a.name, detail: a.note, value: a.heal,
				spec: Dice.parse(a.heal), rollKind: "heal", help: { kind: "heal", action: a },
			});
		} else if (a.atk) {
			const ab = a.atk === "spell" ? c.spellAbility : a.atk;
			const hit = a.hit ?? (mod(c.abilities[ab]) + pb);
			const crit = a.atk !== "spell" ? (c.critRange || 20) : 20;
			rows.push({
				kind: "roll", label: a.name, detail: a.note, value: signed(hit),
				spec: Dice.check(hit, crit), rollKind: "check", title: a.name + " attack",
				help: { kind: "attack", action: a },
			});
			rows.push({
				kind: "roll", label: a.type || "damage", value: a.dmg, indent: true,
				spec: Dice.parse(a.dmg), rollKind: "damage", critable: true,
				title: a.name + " damage", help: { kind: "damage", action: a },
			});
		} else {
			let detail = a.note;
			if (a.save) detail = "DC" + (a.dc ?? (8 + pb + mod(c.abilities[c.spellAbility]))) + " " + a.save.toUpperCase();
			else if (a.auto) detail = "auto-hit";
			rows.push({
				kind: "roll", label: a.name, detail, value: a.dmg,
				spec: Dice.parse(a.dmg), rollKind: "damage", critable: a.critable,
				title: a.name + (a.type ? ` (${a.type})` : ""),
				help: { kind: a.save ? "spellSave" : "auto", action: a },
			});
		}
		const rollRows = rows.slice(first).filter((r) => r.kind === "roll");
		if (cost) cost.each = rollRows.length === 1;
		for (const r of rollRows) {
			r.actionKey = "action" + (ai + 1);
			r.cost = cost;
			r.selfHeal = a.selfHeal;
		}
	});
	return { title: "ACTIONS", rows };
}

function statusPage(c, isDying) {
	const rows = [];
	if (isDying) {
		rows.push({ kind: "header", label: "Dying" }, deathSaveRow(),
			{ kind: "resource", key: "deathSaves", label: "Successes", indent: true },
			{ kind: "resource", key: "deathFails", label: "Failures", indent: true });
	}
	rows.push({ kind: "header", label: "Health" });
	rows.push({ kind: "resource", key: "hp", label: "Hit Points" });
	rows.push({ kind: "resource", key: "hitDice", label: "Hit Dice", detail: "d" + c.hitDie });
	const con = mod(c.abilities.con);
	const expr = "1d" + c.hitDie + (con !== 0 ? signed(con) : "");
	rows.push({
		kind: "roll", label: "Spend Hit Die", value: expr, spec: Dice.parse(expr),
		rollKind: "heal", cost: { key: "hitDice", strict: true, each: true }, selfHeal: true,
		actionKey: "hitDie", indent: true, help: { kind: "spendHitDie" },
	});
	rows.push({ kind: "header", label: "Condition" });
	rows.push({ kind: "resource", key: "inspiration", label: "Heroic Inspiration" });
	rows.push({ kind: "resource", key: "exhaustion", label: "Exhaustion" });
	if (c.slots && c.slots.length) {
		rows.push({ kind: "header", label: "Spell Slots" });
		c.slots.forEach((_, i) => rows.push({ kind: "resource", key: "slot" + (i + 1), label: "Level " + (i + 1) }));
	}
	if (c.features && c.features.length) {
		rows.push({ kind: "header", label: "Features" });
		for (const f of c.features) rows.push({ kind: "resource", key: f.id, label: f.name, detail: f.reset });
	}
	rows.push({ kind: "header", label: "Rest" });
	rows.push({ kind: "rest", key: "short", label: "Short Rest", detail: "1 hour", help: { kind: "rest", rest: "short" } });
	rows.push({ kind: "rest", key: "long", label: "Long Rest", detail: "8 hours", help: { kind: "rest", rest: "long" } });
	return { title: "STATUS", rows };
}

export const POOL_SIDES = [4, 6, 8, 10, 12, 20];

function dicePage() {
	const rows = [{ kind: "header", label: "Build a pool" }];
	rows.push({ kind: "roll", label: "Roll pool", spec: Dice.parse("0"), rollKind: "pool", pool: true, help: { kind: "pool" } });
	for (const s of POOL_SIDES) rows.push({ kind: "counter", key: "d" + s, label: "d" + s, indent: true, help: { kind: "counter" } });
	rows.push({ kind: "counter", key: "bonus", label: "Modifier", indent: true, help: { kind: "counter" } });
	rows.push({ kind: "header", label: "Quick rolls" });
	const add = (label, expr, value, text) => {
		const spec = Dice.parse(expr);
		if (expr === "1d20") spec.check = true;
		rows.push({ kind: "roll", label, value, spec, rollKind: "pool", help: { kind: "quick", expr, text } });
	};
	for (const s of [4, 6, 8, 10, 12, 20, 100]) add("d" + s, "1d" + s);
	add("2d6", "2d6");
	add("Ability score", "4d6kh3", "4d6 drop 1", "Roll 4d6 and drop the lowest die. Do it six times to generate ability scores.");
	add("Fireball", "8d6", "8d6", "The classic 3rd-level spell: 8d6 fire in a 20-foot radius, DEX save for half.");
	return { title: "DICE", rows };
}

export function build(c, isDying) {
	return [abilitiesPage(c), savesPage(c), skillsPage(c), traitsPage(c), actionsPage(c), statusPage(c, isDying), dicePage()];
}
