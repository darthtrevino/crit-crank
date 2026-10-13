// Tracked resources: a port of charsheet/source/resources.lua.

const DEATH = { deathSaves: "Death save successes", deathFails: "Death save failures" };

// Conditions also start empty: [max, label].
const CONDITION = {
	inspiration: [1, "Heroic Inspiration"],
	exhaustion: [6, "Exhaustion"],
};
export const RESERVED = new Set(["hp", "hitDice", "deathSaves", "deathFails", "inspiration", "exhaustion"]);

const featureById = (c, id) => (c.features || []).find((f) => f.id === id);

export function max(c, key) {
	if (key === "hp") return c.hp;
	if (key === "hitDice") return c.level;
	if (DEATH[key]) return 3;
	if (CONDITION[key]) return CONDITION[key][0];
	const m = key.match(/^slot(\d+)$/);
	if (m) return (c.slots || [])[+m[1] - 1] || 0;
	const f = featureById(c, key);
	return f ? f.max : 0;
}

export function label(c, key) {
	if (key === "hp") return "Hit Points";
	if (key === "hitDice") return "Hit Dice";
	if (DEATH[key]) return DEATH[key];
	if (CONDITION[key]) return CONDITION[key][1];
	const m = key.match(/^slot(\d+)$/);
	if (m) return "Level " + m[1] + " slot";
	const f = featureById(c, key);
	return f ? f.name : key;
}

export function keys(c) {
	return ["hp", "hitDice", "deathSaves", "deathFails", "inspiration", "exhaustion",
		...(c.slots || []).map((_, i) => "slot" + (i + 1)),
		...(c.features || []).map((f) => f.id)];
}

export function fresh(c) {
	const r = {};
	for (const k of keys(c)) r[k] = DEATH[k] || CONDITION[k] ? 0 : max(c, k);
	return r;
}

export function load(c, saved) {
	const r = fresh(c);
	if (saved && typeof saved === "object") {
		for (const k of Object.keys(r)) {
			const v = Number(saved[k]);
			if (Number.isFinite(v)) r[k] = Math.max(0, Math.min(max(c, k), Math.floor(v)));
		}
	}
	if (r.hp > 0) clearDeath(r);
	return r;
}

export const get = (c, r, key) => [r[key] || 0, max(c, key)];

export function add(c, r, key, delta) {
	r[key] = Math.max(0, Math.min(max(c, key), (r[key] || 0) + delta));
	return r[key];
}

export function spend(c, r, key) {
	if ((r[key] || 0) <= 0) return false;
	r[key] -= 1;
	return true;
}

export const dying = (r) => r.hp === 0;

export function clearDeath(r) {
	r.deathSaves = 0;
	r.deathFails = 0;
}

export function deathSave(c, r, result) {
	const n = result.natural;
	if (n === 20) {
		r.hp = Math.min(1, c.hp);
		clearDeath(r);
		return "Natural 20! Back up with 1 HP";
	}
	const fails = n === 1 ? 2 : (result.total >= 10 ? 0 : 1);
	if (fails > 0) add(c, r, "deathFails", fails);
	else add(c, r, "deathSaves", 1);
	if (r.deathFails >= 3) return "Three failures: you have died";
	if (r.deathSaves >= 3) return "Three successes: you're stable";
	return fails > 0 ? `Failure (${r.deathFails}/3)` : `Success (${r.deathSaves}/3)`;
}

export function shortRest(c, r) {
	const restored = [];
	for (const f of c.features || []) {
		if (f.reset === "short" && r[f.id] < f.max) {
			r[f.id] = f.max;
			restored.push(f.name);
		}
	}
	return restored;
}

// Long rest: full HP, all slots and features, regain half your hit dice (min 1),
// and one less level of exhaustion. Returns [hit dice regained, exhaustion removed].
export function longRest(c, r) {
	const before = r.hitDice, tired = r.exhaustion;
	r.hp = c.hp;
	clearDeath(r);
	r.hitDice = Math.min(c.level, r.hitDice + Math.max(1, Math.floor(c.level / 2)));
	(c.slots || []).forEach((m, i) => { r["slot" + (i + 1)] = m; });
	for (const f of c.features || []) r[f.id] = f.max;
	r.exhaustion = Math.max(0, tired - 1);
	return [r.hitDice - before, tired - r.exhaustion];
}
