// Dice expressions: a port of charsheet/source/dice.lua.

const rnd = (n) => 1 + Math.floor(Math.random() * n);

const copySpec = (spec) => ({ ...spec, terms: spec.terms.map((t) => ({ ...t })) });

export function signed(n) {
	if (n > 0) return "+" + n;
	if (n < 0) return String(n);
	return "";
}

// Parses "1d20+5", "3d4+3", "2d6", "d100", "4d6kh3", "1d6-1".
export function parse(str) {
	const spec = { terms: [], bonus: 0 };
	const s = str.replace(/\s/g, "");
	for (const [, sign, part] of s.matchAll(/([+-]?)([^+-]+)/g)) {
		const m = part.match(/^(\d*)d(\d+)(.*)$/);
		if (m) {
			const term = { count: m[1] ? +m[1] : 1, sides: +m[2] };
			const k = m[3].match(/^k([hl])(\d+)$/);
			if (k) { term.keep = k[1]; term.keepN = +k[2]; }
			spec.terms.push(term);
		} else {
			spec.bonus += (sign === "-" ? -1 : 1) * (Number(part) || 0);
		}
	}
	return spec;
}

export function check(bonus, critRange = 20) {
	return { ...parse("1d20"), bonus, check: true, critRange };
}

// mode: "normal" | "adv" | "dis"
export function withMode(spec, mode) {
	if (!spec.check || mode === "normal") return spec;
	const out = copySpec(spec);
	Object.assign(out.terms[0], { count: 2, keep: mode === "adv" ? "h" : "l", keepN: 1 });
	return out;
}

export function crit(spec) {
	const out = copySpec(spec);
	for (const t of out.terms) {
		t.count *= 2;
		if (t.keepN) t.keepN *= 2;
	}
	out.critical = true;
	return out;
}

export function format(spec) {
	const parts = spec.terms.map((t, i) =>
		(i > 0 ? "+" : "") + (t.count === 1 ? "d" : t.count + "d") + t.sides + (t.keep ? "k" + t.keep + (t.keepN || 1) : ""));
	return parts.join("") + signed(spec.bonus);
}

function rollTerm(term, rerollOnes) {
	const dice = [];
	for (let i = 0; i < term.count; i++) {
		const d = { sides: term.sides, value: rnd(term.sides), kept: true };
		if (rerollOnes && d.value === 1) { d.value = rnd(term.sides); d.rerolled = true; }
		dice.push(d);
	}
	if (term.keep) {
		const order = dice.map((_, i) => i).sort((a, b) =>
			term.keep === "h" ? dice[b].value - dice[a].value : dice[a].value - dice[b].value);
		order.forEach((idx, rank) => { dice[idx].kept = rank < (term.keepN || 1); });
	}
	return dice;
}

// -> { dice, total, natural, crit, fumble, lucky }
export function roll(spec, opts = {}) {
	const result = { dice: [], total: spec.bonus };
	const lucky = opts.lucky && spec.check;
	for (const term of spec.terms) {
		for (const d of rollTerm(term, lucky && term.sides === 20)) {
			if (d.rerolled) result.lucky = true;
			result.dice.push(d);
			if (d.kept) result.total += d.value;
		}
	}
	if (spec.check) {
		const nat = result.dice.find((d) => d.kept && d.sides === 20);
		result.natural = nat ? nat.value : undefined;
		result.crit = result.natural !== undefined && result.natural >= (spec.critRange || 20);
		result.fumble = result.natural === 1;
	}
	return result;
}

// Random faces for the tumbling animation.
export function faces(spec) {
	const out = [];
	for (const t of spec.terms) for (let i = 0; i < t.count; i++) out.push({ sides: t.sides, value: rnd(t.sides), kept: true });
	return out;
}
