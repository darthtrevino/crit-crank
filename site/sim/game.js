// Game state and input: a port of charsheet/source/main.lua.
import * as Dice from "./dice.js";
import * as Dice3D from "./dice3d.js";
import * as Resources from "./resources.js";
import * as Sheet from "./sheet.js";
import * as Rules from "./rules.js";
import * as UI from "./ui.js";
import * as Sound from "./sound.js";
import { CHARACTERS } from "./characters.js";
import { H } from "./gfx.js";

const CRANK_START = 30;
const CRANK_TICK = 40;
const SETTLE_FRAMES = 8;
const CRANK_ADJUST = 20;
const TOAST_FRAMES = 75;
const POOL_MAX_DICE = 12;
const POOL_BONUS = 20;
export const REST_CRANK = 720;
const REST_STEP = 90;
const REST_DECAY = 30;
const REST_RELOCK = 15;
const RULES_SLIDE_FRAMES = 9;
// With reduced motion, rolls land at once and the Rules panel doesn't slide.
const REDUCED = globalThis.matchMedia?.("(prefers-reduced-motion: reduce)");
const calm = () => !!REDUCED?.matches;
const RULES_LINE = 22;
const RULES_CRANK = 0.8;
const RULES_EASE = 0.3;
const STORE_KEY = "critcrank-sim-v1";

CHARACTERS.forEach((c, i) => { c.key = String(i + 1); });

const isSelectable = (row) => row && ["roll", "resource", "counter", "rest", "trait"].includes(row.kind);
const firstSelectable = (rows) => Math.max(0, rows.findIndex(isSelectable));
const rowId = (row) => row && `${row.kind}:${row.key || row.actionKey || ""}:${row.label || ""}`;

// Short names for the Hero menu.
function heroNames() {
	const seen = new Set();
	return CHARACTERS.map((c, i) => {
		let n = c.name.split(" ")[0];
		if (n === "Brother" || n === "Sister") n = c.name.split(" ").pop();
		if (seen.has(n)) n = n + " " + (i + 1);
		seen.add(n);
		return n;
	});
}

export class Game {
	constructor(g, { onChange } = {}) {
		this.g = g;
		this.onChange = onChange || (() => {});
		this.state = {
			charIndex: 0, pages: null, page: 0, sel: [], scroll: [], mode: "normal",
			critPending: false, roll: null, preview: null, res: null, allRes: {}, allView: {},
			lastCast: null, toast: null, toastFrames: 0, dirty: false, dirtyFrames: 0,
			pool: {}, rest: null, rules: null, menu: null, dying: false,
		};
		this.crank = { windup: 0, tick: 0, idle: 0, adjust: 0, restLock: false, still: 0, change: 0 };
		this.repeats = {};
		this.docked = false;
		this.names = heroNames();
		const saved = this.loadStore();
		this.state.allRes = saved.resources || {};
		this.state.allView = saved.views || {};
		const idx = CHARACTERS.findIndex((c) => c.key === saved.charKey);
		this.loadCharacter(idx >= 0 ? idx : 0);
	}

	// ------------------------------------------------------------ helpers

	get character() { return CHARACTERS[this.state.charIndex]; }
	currentPage() { return this.state.pages[this.state.page]; }

	selectedRow() {
		const row = this.currentPage().rows[this.state.sel[this.state.page]];
		return isSelectable(row) ? row : null;
	}

	selectedRollRow() {
		const row = this.selectedRow();
		return row && row.kind === "roll" ? row : null;
	}

	toast(msg) {
		this.state.toast = msg;
		this.state.toastFrames = TOAST_FRAMES;
	}

	getResource = (key) => Resources.get(this.character, this.state.res, key);
	getCounter = (key) => this.state.pool[key] || 0;

	ensureVisible(p = this.state.page) {
		const s = this.state;
		const rows = s.pages[p].rows;
		const sel = s.sel[p];
		let scroll = s.scroll[p] || 0;
		let top = sel;
		while (top > 0 && !isSelectable(rows[top - 1]) && rows[top - 1].kind === "header") top--;
		if (top < scroll) scroll = top;
		if (sel >= scroll + UI.VISIBLE_ROWS) scroll = sel - UI.VISIBLE_ROWS + 1;
		let last = sel;
		while (rows[last + 1] && !isSelectable(rows[last + 1]) && rows[last + 1].kind !== "header") last++;
		if (last === rows.length - 1 && last >= scroll + UI.VISIBLE_ROWS) scroll = Math.min(last - UI.VISIBLE_ROWS + 1, sel);
		s.scroll[p] = Math.max(0, scroll);
	}

	syncDying() {
		const s = this.state;
		const dying = Resources.dying(s.res);
		if (!dying) Resources.clearDeath(s.res);
		if (dying === s.dying) return;
		s.dying = dying;
		const old = s.pages;
		s.pages = Sheet.build(this.character, dying);
		s.pages.forEach((page, p) => {
			const was = old[p] && old[p].rows[s.sel[p]];
			let sel = firstSelectable(page.rows);
			const i = page.rows.findIndex((r) => was && rowId(r) === rowId(was));
			if (i >= 0) sel = i;
			s.sel[p] = sel;
			if (dying && page.title === "STATUS") s.scroll[p] = 0;
			this.ensureVisible(p);
		});
		this.refreshPool();
	}

	adjustResource(key, delta) {
		const s = this.state;
		const before = s.res[key];
		const after = Resources.add(this.character, s.res, key, delta);
		if (after !== before) {
			s.dirty = true;
			Sound.tick(delta > 0 ? 900 : 500, 0.1, 0.02);
			if (key === "hp") this.syncDying();
			if (key === "exhaustion" && after === 6) this.toast("Exhaustion 6: you die");
		}
	}

	// ------------------------------------------------------------ dice pool

	poolDiceCount() {
		return Sheet.POOL_SIDES.reduce((n, sd) => n + this.getCounter("d" + sd), 0);
	}

	poolExpr() {
		const parts = [];
		for (const sd of [...Sheet.POOL_SIDES].reverse()) {
			const n = this.getCounter("d" + sd);
			if (n > 0) parts.push(n + "d" + sd);
		}
		let expr = parts.join("+");
		const b = this.getCounter("bonus");
		if (b !== 0) expr += Dice.signed(b);
		return expr;
	}

	refreshPool() {
		for (const page of this.state.pages) {
			for (const row of page.rows) {
				if (!row.pool) continue;
				const expr = this.poolExpr();
				row.spec = Dice.parse(expr === "" ? "0" : expr);
				if (row.spec.terms.length === 0) row.value = "empty";
				else {
					const f = Dice.format(row.spec);
					row.value = f.length <= 11 ? f : this.poolDiceCount() + " dice";
				}
			}
		}
	}

	adjustCounter(key, delta) {
		const s = this.state;
		const cur = this.getCounter(key);
		let next;
		if (key === "bonus") next = Math.max(-POOL_BONUS, Math.min(POOL_BONUS, cur + delta));
		else {
			next = Math.max(0, cur + delta);
			if (delta > 0 && this.poolDiceCount() >= POOL_MAX_DICE) {
				this.toast(`Pool is full (${POOL_MAX_DICE} dice max)`);
				return;
			}
		}
		if (next === cur) return;
		s.pool[key] = next;
		s.dirty = true;
		Sound.tick(delta > 0 ? 900 : 500, 0.1, 0.02);
		this.refreshPool();
	}

	clearPool() {
		this.state.pool = {};
		this.state.dirty = true;
		this.refreshPool();
		this.toast("Pool cleared");
	}

	adjustRow(row, delta) {
		if (row.kind === "counter") this.adjustCounter(row.key, delta);
		else this.adjustResource(row.key, delta);
	}

	// ------------------------------------------------------------ heroes & saving

	captureView() {
		const s = this.state;
		const v = {
			page: s.pages[s.page].title, sel: {}, scroll: {}, mode: s.mode,
			critPending: s.critPending, lastCast: s.lastCast, pool: s.pool,
		};
		s.pages.forEach((page, p) => {
			v.sel[page.title] = rowId(page.rows[s.sel[p]]);
			v.scroll[page.title] = s.scroll[p];
		});
		return v;
	}

	restoreView(v) {
		const s = this.state;
		v = v && typeof v === "object" ? v : {};
		const sel = v.sel || {};
		const scroll = v.scroll || {};
		s.page = 0;
		s.sel = [];
		s.scroll = [];
		s.pages.forEach((page, p) => {
			s.sel[p] = firstSelectable(page.rows);
			const i = page.rows.findIndex((r) => isSelectable(r) && rowId(r) === sel[page.title]);
			if (i >= 0) s.sel[p] = i;
			s.scroll[p] = Math.max(0, Math.floor(Number(scroll[page.title]) || 0));
			this.ensureVisible(p);
			if (page.title === v.page) s.page = p;
		});
		s.mode = v.mode === "adv" || v.mode === "dis" ? v.mode : "normal";
		s.critPending = v.critPending === true;
		s.lastCast = typeof v.lastCast === "string" ? v.lastCast : null;
		s.pool = {};
		for (const [k, n] of Object.entries(v.pool || {})) if (typeof n === "number") s.pool[k] = Math.floor(n);
	}

	loadCharacter(i) {
		const s = this.state;
		if (s.res) {
			s.allRes[this.character.key] = s.res;
			s.allView[this.character.key] = this.captureView();
		}
		s.charIndex = i;
		const c = CHARACTERS[i];
		s.res = Resources.load(c, s.allRes[c.key]);
		s.allRes[c.key] = s.res;
		s.dying = Resources.dying(s.res);
		s.pages = Sheet.build(c, s.dying);
		this.restoreView(s.allView[c.key]);
		this.refreshPool();
		s.roll = null;
		s.rest = null;
		s.preview = null;
		this.onChange();
	}

	loadStore() {
		try {
			return JSON.parse(localStorage.getItem(STORE_KEY)) || {};
		} catch {
			return {};
		}
	}

	save() {
		const s = this.state;
		s.allRes[this.character.key] = s.res;
		s.allView[this.character.key] = this.captureView();
		try {
			localStorage.setItem(STORE_KEY, JSON.stringify({ charKey: this.character.key, resources: s.allRes, views: s.allView }));
		} catch {
			// storage may be unavailable (private mode); the demo still works
		}
		s.dirty = false;
	}

	reset() {
		try { localStorage.removeItem(STORE_KEY); } catch { /* ignore */ }
		const s = this.state;
		s.allRes = {};
		s.allView = {};
		s.res = null;
		s.rules = null;
		s.menu = null;
		this.loadCharacter(s.charIndex);
		this.toast("Demo reset");
	}

	selectHero(i) {
		if (i === this.state.charIndex) return;
		this.save();
		this.loadCharacter(i);
		this.save();
	}

	// ------------------------------------------------------------ navigation

	diceMoving() {
		return this.state.roll != null && this.state.roll.phase !== "done";
	}

	moveSel(dir) {
		if (this.diceMoving()) return;
		const s = this.state;
		const rows = this.currentPage().rows;
		let i = s.sel[s.page];
		do { i += dir; } while (i >= 0 && i < rows.length && !isSelectable(rows[i]));
		if (i >= 0 && i < rows.length) {
			s.sel[s.page] = i;
			s.roll = null;
			s.rest = null;
			this.ensureVisible();
		}
	}

	changePage(dir) {
		if (this.diceMoving()) return;
		const s = this.state;
		s.page = (s.page + dir + s.pages.length) % s.pages.length;
		s.roll = null;
		s.rest = null;
		this.ensureVisible();
	}

	// ------------------------------------------------------------ rests

	updateRest(row, amount) {
		const s = this.state;
		let r = s.rest;
		if (!r || r.row !== row) {
			r = { row, progress: 0, idle: 0 };
			s.rest = r;
		}
		if (amount <= 0.5) {
			r.idle++;
			if (r.idle > SETTLE_FRAMES) r.progress = Math.max(0, r.progress - REST_DECAY);
			return;
		}
		r.idle = 0;
		if (this.crank.restLock) return;
		r.done = false;
		const before = r.progress;
		r.progress = Math.min(REST_CRANK, r.progress + amount);
		if (Math.floor(before / REST_STEP) !== Math.floor(r.progress / REST_STEP)) {
			Sound.tick(400 + 600 * r.progress / REST_CRANK, 0.12, 0.03);
		}
		if (r.progress >= REST_CRANK) {
			r.progress = 0;
			r.done = true;
			this.crank.restLock = true;
			this.crank.still = 0;
			this.takeRest(row.key);
			Sound.land(784, 0.4, 0.3);
		}
	}

	takeRest(kind) {
		const s = this.state;
		const c = this.character;
		s.lastCast = null;
		if (kind === "long") {
			const [regained, rested] = Resources.longRest(c, s.res);
			s.critPending = false;
			this.syncDying();
			this.toast(`Long rest: fully restored, +${regained} Hit Dice${rested > 0 ? ", -1 Exhaustion" : ""}`);
		} else {
			const restored = Resources.shortRest(c, s.res);
			this.toast(restored.length ? `Short rest: ${restored.join(", ")} restored` : "Short rest: spend Hit Dice to heal");
		}
		this.save();
	}

	// ------------------------------------------------------------ rolling

	effectiveSpec(row) {
		let spec = row.spec;
		let crit = false;
		if (spec.check) spec = Dice.withMode(spec, this.state.mode);
		else if (row.critable && this.state.critPending) {
			spec = Dice.crit(spec);
			crit = true;
		}
		return [spec, crit];
	}

	previewFor(row) {
		const s = this.state;
		const [spec] = this.effectiveSpec(row);
		const key = rowId(row) + s.page + Dice.format(spec);
		if (s.preview && s.preview.key === key) return s.preview;
		const dice = [];
		for (const t of spec.terms) for (let i = 0; i < t.count; i++) dice.push({ sides: t.sides, value: "?", kept: true });
		s.preview = { key, dice, bodies: dice.map((d) => Dice3D.newBody(d.sides, d.sides)) };
		return s.preview;
	}

	spinAll(amount) {
		if (calm()) return;
		for (const b of this.state.roll.bodies) {
			const a = amount * (0.8 + Math.random() * 0.4);
			Dice3D.spin(b, a);
			Dice3D.toss(b, a);
		}
	}

	startRoll() {
		const s = this.state;
		const row = this.selectedRollRow();
		if (!row) return;
		if (row.pool && row.spec.terms.length === 0) {
			this.toast("Add dice to the pool first");
			return;
		}
		const c = this.character;
		const cost = row.cost;
		if (cost && cost.strict && row.selfHeal && s.res.hp >= c.hp) {
			this.toast("Already at full HP");
			return;
		}
		if (cost && (cost.each || row.actionKey !== s.lastCast)) {
			const label = Resources.label(c, cost.key);
			if (Resources.spend(c, s.res, cost.key)) {
				s.dirty = true;
				this.toast(`Used ${label} (${s.res[cost.key]} left)`);
			} else if (cost.strict) {
				this.toast(`No ${label} left`);
				Sound.land(131, 0.3, 0.2);
				return;
			} else {
				this.toast(`Out of ${label}! Rolling anyway`);
			}
		}
		s.lastCast = row.actionKey || null;
		const [spec, crit] = this.effectiveSpec(row);
		const faces = Dice.faces(spec);
		const preview = this.previewFor(row);
		const { r, xs, ys } = UI.diceLayout(faces.length, UI.diceTop(spec, s.mode));
		const bodies = faces.map((d, i) => {
			const b = Dice3D.newBody(d.sides);
			const last = s.roll && s.roll.row === row && s.roll.bodies[i];
			const from = last || preview.bodies[i];
			if (from && from.sides === d.sides) b.q = from.q;
			if (last && last.x != null) Dice3D.place(b, last.x, last.y, r);
			else Dice3D.place(b, xs[i], ys[i], r);
			return b;
		});
		s.roll = { phase: "tumble", row, spec, crit, mode: s.mode, faces, bodies };
		this.spinAll(0.35);
		this.crank.tick = 0;
		this.crank.idle = 0;
		Sound.tick();
	}

	settle() {
		const roll = this.state.roll;
		roll.result = Dice.roll(roll.spec, { lucky: this.character.lucky });
		roll.phase = "landing";
		roll.result.dice.forEach((d, i) => Dice3D.land(roll.bodies[i], d.value));
		if (calm()) for (const b of roll.bodies) Object.assign(b, { q: b.landTo, landing: false });
	}

	finishLanding() {
		const s = this.state;
		const roll = s.roll;
		roll.phase = "done";
		const c = this.character;
		if (roll.spec.check) {
			s.critPending = !!roll.result.crit && roll.row.rollKind === "check" && this.currentPage().title === "ACTIONS";
			s.mode = "normal";
			s.dirty = true;
		}
		if (roll.row.selfHeal) {
			const before = s.res.hp;
			const after = Resources.add(c, s.res, "hp", Math.max(0, roll.result.total));
			s.dirty = true;
			this.toast(`Healed ${after - before} HP (${after}/${c.hp})`);
			this.syncDying();
		}
		if (roll.row.deathSave && Resources.dying(s.res)) {
			this.toast(Resources.deathSave(c, s.res, roll.result));
			s.dirty = true;
			this.syncDying();
		}
		Sound.landFor(roll.result);
		if (roll.row.rollKind !== "pool") {
			if (roll.result.natural === 20) Sound.horn();
			else if (roll.result.natural === 1) Sound.trombone();
		}
	}

	updateRoll(change) {
		const s = this.state;
		const crank = this.crank;
		const amount = Math.abs(change);
		const roll = s.roll;

		if (crank.restLock) {
			crank.still = amount > 0.5 ? 0 : crank.still + 1;
			if (crank.still >= REST_RELOCK) crank.restLock = false;
		}
		if (roll && roll.phase !== "done") {
			const inset = UI.DICE_INSET;
			const clack = Dice3D.step(roll.bodies, UI.DICE_LEFT + inset, UI.diceTop(roll.spec, roll.mode) + inset, UI.DICE_RIGHT - inset, UI.DICE_BOTTOM - inset);
			if (clack) Sound.tick(250 + Math.random() * 150, 0.08, 0.015);
			for (const b of roll.bodies) Dice3D.update(b);
		}

		if (roll && roll.phase === "landing") {
			if (roll.bodies.every(Dice3D.isSettled)) this.finishLanding();
			return;
		}
		if (roll && roll.phase === "tumble") {
			if (amount > 0.5) {
				crank.idle = 0;
				this.spinAll(amount * 0.004);
				crank.tick += amount;
				if (crank.tick >= CRANK_TICK) {
					crank.tick %= CRANK_TICK;
					roll.faces = Dice.faces(roll.spec);
					Sound.tick();
				}
			} else {
				crank.idle++;
				if (crank.idle >= SETTLE_FRAMES) this.settle();
			}
			return;
		}

		const sel = this.selectedRow();
		if (sel && sel.kind === "rest") {
			this.updateRest(sel, amount);
			return;
		}
		if (sel && (sel.kind === "resource" || sel.kind === "counter")) {
			crank.adjust += change;
			while (Math.abs(crank.adjust) >= CRANK_ADJUST) {
				const dir = crank.adjust > 0 ? 1 : -1;
				crank.adjust -= dir * CRANK_ADJUST;
				this.adjustRow(sel, dir);
			}
			return;
		}
		crank.adjust = 0;
		if (amount > 0.5) {
			crank.idle = 0;
			crank.windup += amount;
			if (crank.windup >= CRANK_START) {
				crank.windup = 0;
				this.startRoll();
			}
		} else {
			crank.idle++;
			if (crank.idle > 10) crank.windup = 0;
		}
	}

	// ------------------------------------------------------------ rules viewer

	rulesMaxScroll(v) {
		return Math.max(v.height - UI.RULES_BODY_H, 0);
	}

	scrollRules(delta) {
		const v = this.state.rules;
		if (!v || v.closing) return;
		v.target = Math.max(0, Math.min(this.rulesMaxScroll(v), v.target + delta));
	}

	openRules() {
		const d = Rules.describe(this.character, this.selectedRow(), this.currentPage());
		const { text, height } = UI.measureRuleBody(this.g, d.body || "");
		this.releaseAll();
		this.state.rules = { title: d.title || "", sub: d.sub || "", text, height, scroll: 0, target: 0, t: calm() ? RULES_SLIDE_FRAMES : 0, bob: 0 };
	}

	closeRules() {
		if (this.state.rules) this.state.rules.closing = true;
		this.releaseAll();
	}

	updateRules() {
		const s = this.state;
		const v = s.rules;
		if (calm()) v.t = v.closing ? 0 : RULES_SLIDE_FRAMES;
		else v.t = Math.max(0, Math.min(RULES_SLIDE_FRAMES, v.t + (v.closing ? -1 : 1)));
		if (v.closing && v.t === 0) {
			s.rules = null;
			return null;
		}
		const d = v.target - v.scroll;
		v.scroll = Math.abs(d) < 0.5 || calm() ? v.target : v.scroll + d * RULES_EASE;
		if (!calm()) v.bob += 0.2;
		const p = 1 - v.t / RULES_SLIDE_FRAMES;
		return H * p * p * p;
	}

	// ------------------------------------------------------------ pause menu

	toggleMenu() {
		const s = this.state;
		this.releaseAll();
		if (s.menu) {
			const hero = s.menu.hero;
			s.menu = null;
			this.selectHero(hero);
			return;
		}
		if (s.rules) s.rules = null;
		this.save();
		s.menu = { sel: 0, hero: s.charIndex };
		this.onChange();
	}

	menuInput(button) {
		const m = this.state.menu;
		if (button === "up") m.sel = Math.max(0, m.sel - 1);
		else if (button === "down") m.sel = Math.min(1, m.sel + 1);
		else if (button === "b") this.toggleMenu();
		else if (m.sel === 0 && (button === "left" || button === "right" || button === "a")) {
			const n = CHARACTERS.length;
			m.hero = (m.hero + (button === "left" ? -1 : 1) + n) % n;
		} else if (m.sel === 1 && button === "a") {
			this.toggleMenu();
			this.openRules();
		}
	}

	// ------------------------------------------------------------ input

	// Like playdate.timer.keyRepeatTimer: fire now, after 300ms, then every 100ms.
	holdRepeat(key, fn) {
		this.release(key);
		fn();
		const r = { fn, next: performance.now() + 300 };
		this.repeats[key] = r;
	}

	release(key) {
		delete this.repeats[key];
	}

	releaseAll() {
		this.repeats = {};
	}

	press(button) {
		Sound.unlock();
		const s = this.state;
		if (button === "menu") { this.toggleMenu(); return; }
		if (s.menu) { this.menuInput(button); return; }
		if (s.rules) {
			if (button === "up") this.holdRepeat("up", () => this.scrollRules(-RULES_LINE));
			else if (button === "down") this.holdRepeat("down", () => this.scrollRules(RULES_LINE));
			else if (button === "a") {
				const v = s.rules;
				if (v.target >= this.rulesMaxScroll(v)) this.closeRules();
				else this.scrollRules(UI.RULES_BODY_H - RULES_LINE);
			} else if (button === "b") this.closeRules();
			return;
		}
		switch (button) {
			case "up": this.holdRepeat("up", () => this.moveSel(-1)); break;
			case "down": this.holdRepeat("down", () => this.moveSel(1)); break;
			case "left": this.changePage(-1); break;
			case "right": this.changePage(1); break;
			case "a": this.pressA(); break;
			case "b": this.pressB(); break;
		}
	}

	unpress(button) {
		this.release(button);
	}

	restHint() {
		const row = this.selectedRow();
		if (row && row.kind === "rest") {
			this.toast(`Crank to take a ${row.label.toLowerCase()}`);
			return true;
		}
		return false;
	}

	resourceRow() {
		const row = this.selectedRow();
		return row && (row.kind === "resource" || row.kind === "counter") ? row : null;
	}

	traitRow() {
		const row = this.selectedRow();
		return !!row && row.kind === "trait";
	}

	// Only the crank rolls; Ⓐ explains the row (or takes one off a counter).
	pressA() {
		if (this.diceMoving()) return;
		const r = this.resourceRow();
		if (r) { this.holdRepeat("a", () => this.adjustRow(r, -1)); return; }
		if (this.selectedRow()) this.openRules();
	}

	pressB() {
		const s = this.state;
		if (this.diceMoving() || this.restHint() || this.traitRow()) return;
		const r = this.resourceRow();
		if (r) { this.holdRepeat("b", () => this.adjustRow(r, 1)); return; }
		const sel = this.selectedRow();
		if (sel && sel.pool) {
			s.roll = null;
			this.clearPool();
			return;
		}
		if (sel && sel.spec && !sel.spec.check) {
			// damage rolls toggle normal / critical instead of the d20 mode
			if (!sel.critable) return;
			s.critPending = !s.critPending;
		} else {
			s.mode = { normal: "adv", adv: "dis", dis: "normal" }[s.mode];
		}
		s.dirty = true;
		s.roll = null;
	}

	cranked(degrees) {
		Sound.unlock();
		this.crank.change += degrees;
	}

	// ------------------------------------------------------------ frame

	update() {
		const s = this.state;
		const now = performance.now();
		for (const r of Object.values(this.repeats)) {
			if (now >= r.next) { r.fn(); r.next = now + 100; }
		}
		const change = this.crank.change;
		this.crank.change = 0;

		if (s.menu) return;
		let rulesY = null;
		if (s.rules) {
			this.scrollRules(change * RULES_CRANK);
			rulesY = this.updateRules();
		} else {
			this.updateRoll(change);
		}
		if (s.toastFrames > 0 && --s.toastFrames === 0) s.toast = null;
		if (s.dirty && !this.diceMoving()) {
			if (++s.dirtyFrames > 30) { s.dirtyFrames = 0; this.save(); }
		}
		this.rulesY = rulesY;
	}

	draw() {
		const g = this.g;
		const s = this.state;
		if (s.menu) {
			const d = Rules.describe(this.character, this.selectedRow(), this.currentPage());
			UI.drawRuleCard(g, d.title || "", d.sub || "", d.body || "");
			UI.drawSystemMenu(g, [{ label: "Hero", value: this.names[s.menu.hero] }, { label: "Read Rule" }], s.menu.sel);
			g.present();
			return;
		}
		if (s.rules && this.rulesY === 0) {
			UI.drawRuleViewer(g, s.rules, 0);
			g.present();
			return;
		}
		g.clear("white");
		const c = this.character;
		const page = this.currentPage();
		UI.drawHeader(g, c, s.res.hp);
		UI.drawTabs(g, s.pages, s.page);
		UI.drawList(g, page, s.sel[s.page], s.scroll[s.page], s.critPending, this.getResource, this.getCounter);

		const row = this.selectedRow();
		const tray = {
			row, mode: s.mode, critPending: s.critPending, roll: s.roll, docked: this.docked,
			getResource: this.getResource, getCounter: this.getCounter,
			rest: s.rest && s.rest.row === row ? s.rest : null, restMax: REST_CRANK,
		};
		if (row && row.kind === "roll" && !(row.pool && row.spec.terms.length === 0)) {
			[tray.spec] = this.effectiveSpec(row);
			tray.preview = this.previewFor(row);
		} else if (row && row.kind === "trait") {
			if (!row.blurb) row.blurb = Rules.describe(c, row, page).body || "";
			tray.blurb = row.blurb;
		} else if (row && row.kind === "counter") {
			const poolRow = page.rows.find((r) => r.pool);
			if (poolRow.spec.terms.length > 0) {
				tray.spec = poolRow.spec;
				tray.preview = this.previewFor(poolRow);
			}
		}
		UI.drawTray(g, tray);
		let footerMode = s.mode;
		if (row && (row.kind === "resource" || row.kind === "counter")) footerMode = "resource";
		else if (row && row.kind === "rest") footerMode = "rest";
		else if (row && row.kind === "trait") footerMode = "trait";
		else if (row && row.pool) footerMode = "pool";
		else if (row && row.spec && !row.spec.check) footerMode = !row.critable ? "plain" : s.critPending ? "crit" : "dmg";
		UI.drawFooter(g, footerMode, s.toast);
		if (s.rules && this.rulesY != null) UI.drawRuleViewer(g, s.rules, this.rulesY);
		g.present();
	}

	// Plain-text summary of what's on screen, for the page's live region.
	statusText() {
		const s = this.state;
		if (s.menu) return s.menu.sel === 0 ? `Pause menu. Hero: ${this.names[s.menu.hero]}` : "Pause menu. Read Rule";
		if (s.rules) return `Rules: ${s.rules.title}. ${s.rules.sub} ${s.rules.text}`;
		const page = this.currentPage();
		const row = this.selectedRow();
		const parts = [`${page.title} page`];
		if (row) {
			let value = row.value || "";
			if (row.kind === "resource") value = this.getResource(row.key).join(" of ");
			else if (row.kind === "counter") value = String(this.getCounter(row.key));
			parts.push(`${row.label}${value ? " " + value : ""}`);
		}
		if (row && row.critable && s.critPending) parts.push("Critical");
		else if (s.mode !== "normal" && row && row.spec && row.spec.check) parts.push(s.mode === "adv" ? "Advantage" : "Disadvantage");
		const roll = s.roll;
		if (roll && roll.phase === "done") {
			const r = roll.result;
			parts.push(`Rolled ${r.total}${r.crit ? ", natural 20" : r.fumble ? ", natural 1" : ""}`);
		}
		if (s.toast) parts.push(s.toast);
		return parts.join(". ");
	}

	// Jump straight to a page/row for the docs ("STATUS", "Long Rest").
	focus(pageTitle, label) {
		const s = this.state;
		const p = s.pages.findIndex((pg) => pg.title === pageTitle);
		if (p < 0) return;
		s.page = p;
		if (label) {
			const i = s.pages[p].rows.findIndex((r) => isSelectable(r) && r.label === label);
			if (i >= 0) s.sel[p] = i;
		}
		s.roll = null;
		s.rest = null;
		this.ensureVisible();
	}

	get heroIndex() { return this.state.charIndex; }
	get heroNames() { return this.names; }
	get paused() { return !!this.state.menu; }
}
