// Screen drawing: a port of charsheet/source/ui.lua.
import { fonts, W, H } from "./gfx.js";
import * as Dice from "./dice.js";
import * as Dice3D from "./dice3d.js";

export const HEADER_H = 24;
export const TABS_Y = 24;
export const TABS_H = 18;
export const BODY_Y = 44;
export const FOOTER_Y = 224;
export const ROW_H = 22;
export const LIST_W = 258;
export const TRAY_X = 262;
export const VISIBLE_ROWS = Math.floor((FOOTER_Y - BODY_Y) / ROW_H);
export const RULES_BODY_Y = 52;
export const RULES_BODY_H = FOOTER_Y - RULES_BODY_Y - 2;

const TRAY_CX = TRAY_X + Math.floor((W - TRAY_X) / 2);
const TRAY_W = W - TRAY_X - 8;
const PIP_GAP = 11;
const RULES_X = 12;
const RULES_W = W - 32;

// ------------------------------------------------------------ header / tabs

export function drawHeader(g, c, hp) {
	g.setColor("black");
	g.fillRect(0, 0, W, HEADER_H);
	const nameW = g.textW(fonts.title, c.name);
	g.text(fonts.title, c.name, 6, 3, undefined, "white");
	const stats = `AC ${c.ac}  HP ${hp}/${c.hp}  ${c.speed}ft`;
	const statsW = g.textW(fonts.small, stats);
	const room = W - 6 - statsW - 10 - (12 + nameW);
	let sub = `Lv${c.level} ${c.race} ${c.class}`;
	if (g.textW(fonts.small, sub) > room) sub = `Lv${c.level} ${c.class}`;
	g.text(fonts.small, g.fit(fonts.small, sub, room), 12 + nameW, 7, undefined, "white");
	g.text(fonts.small, stats, W - 6, 7, "right", "white");
}

export function drawTabs(g, pages, current) {
	const w = W / pages.length;
	pages.forEach((p, i) => {
		const x = Math.floor(i * w);
		const selected = i === current;
		if (selected) {
			g.setColor("black");
			g.fillRoundRect(x + 2, TABS_Y + 2, Math.floor(w) - 4, TABS_H - 2, 4);
		}
		g.text(fonts.small, p.title, x + Math.floor(w / 2), TABS_Y + 4, "center", selected ? "white" : "copy");
	});
	g.setColor("black");
	g.line(0, BODY_Y - 1, W, BODY_Y - 1);
}

// ------------------------------------------------------------ list

function drawMark(g, mark, x, cy) {
	if (mark === "prof") g.fillCircle(x, cy, 3);
	else if (mark === "exp") { g.fillCircle(x, cy, 3); g.drawCircle(x, cy, 5); }
	else if (mark === "none") g.drawCircle(x, cy, 3);
}

function drawPips(g, cur, max, rightX, cy) {
	for (let i = 1; i <= max; i++) {
		const x = rightX - (max - i) * PIP_GAP - 4;
		if (i <= cur) g.fillCircle(x, cy, 4);
		else g.drawCircle(x, cy, 4);
	}
}

const usePips = (key, max) => key !== "hp" && max <= 6;

function counterText(key, n) {
	if (key === "bonus") return n === 0 ? "+0" : Dice.signed(n);
	return n === 0 ? "-" : "x" + n;
}

export function drawList(g, page, sel, scroll, critPending, getResource, getCounter) {
	const rows = page.rows;
	const valueX = LIST_W - 8;
	for (let vi = 0; vi < VISIBLE_ROWS; vi++) {
		const i = scroll + vi;
		const row = rows[i];
		if (!row) break;
		const y = BODY_Y + vi * ROW_H;
		const selected = i === sel;

		if (row.kind === "header") {
			const label = row.label.toUpperCase();
			g.text(fonts.small, label, 6, y + 6);
			const lx = 12 + g.textW(fonts.small, label);
			g.setColor("black");
			g.setDither(0.5, "bayer2");
			g.line(lx, y + 12, LIST_W - 6, y + 12);
			g.setColor("black");
			continue;
		}
		const mode = selected ? "white" : "copy";
		if (selected) {
			g.setColor("black");
			g.fillRoundRect(2, y + 1, LIST_W - 6, ROW_H - 1, 4);
			g.setColor("white");
		} else {
			g.setColor("black");
		}

		const textY = y + 2;
		let labelX = 18;
		if (row.indent) {
			labelX = 30;
			g.line(20, y + 5, 20, y + 12);
			g.line(20, y + 12, 26, y + 12);
		}
		drawMark(g, row.mark, 10, y + ROW_H / 2);

		let value = row.value;
		let pips = null;
		if (row.kind === "resource") {
			const [cur, max] = getResource(row.key);
			if (usePips(row.key, max)) { pips = [cur, max]; value = null; }
			else value = `${cur}/${max}`;
		} else if (row.kind === "counter") {
			value = counterText(row.key, getCounter(row.key));
		}
		const valueW = pips ? pips[1] * PIP_GAP : g.textW(fonts.body, value || "");
		const labelFont = row.indent ? fonts.small : fonts.body;
		let detailW = row.detail ? g.textW(fonts.small, row.detail) + 8 : 0;
		const labelRoom = valueX - valueW - labelX - 6;
		const showDetail = row.detail && g.textW(labelFont, row.label) <= labelRoom - detailW;
		if (!showDetail) detailW = 0;
		g.text(labelFont, g.fit(labelFont, row.label, labelRoom - detailW), labelX, row.indent ? y + 5 : textY, undefined, mode);
		if (showDetail) g.text(fonts.small, row.detail, valueX - valueW - 8, y + 5, "right", mode);
		if (value) g.text(fonts.body, value, valueX, textY, "right", mode);
		else if (pips) drawPips(g, pips[0], pips[1], valueX, y + ROW_H / 2);
		if (critPending && row.critable && !selected) {
			g.text(fonts.small, "x2", valueX - valueW - detailW - 4, y + 5, "right");
		}
		g.setColor("black");
	}

	if (rows.length > VISIBLE_ROWS) {
		const trackH = VISIBLE_ROWS * ROW_H;
		const h = Math.max(10, Math.floor(trackH * VISIBLE_ROWS / rows.length));
		const maxScroll = rows.length - VISIBLE_ROWS;
		const y = BODY_Y + Math.floor((trackH - h) * scroll / maxScroll);
		g.setColor("black");
		g.fillRect(LIST_W - 3, y, 2, h);
	}
}

// ------------------------------------------------------------ dice tray

function drawPill(g, text, cx, y) {
	const w = g.textW(fonts.small, text) + 10;
	g.setColor("black");
	g.fillRoundRect(cx - w / 2, y, w, 15, 7);
	g.text(fonts.small, text, cx, y + 1, "center", "white");
}

function drawDiceGrid(g, dice, bodies, top, bottom, result) {
	const n = dice.length;
	if (n === 0) return;
	let r, cols;
	if (n === 1) [r, cols] = [30, 1];
	else if (n === 2) [r, cols] = [24, 2];
	else if (n <= 6) [r, cols] = [17, 3];
	else if (n <= 12) [r, cols] = [14, 4];
	else [r, cols] = [11, 5];
	const gap = Math.min(r * 2 + 4, Math.floor((W - TRAY_X - 4) / cols));
	const rowsN = Math.ceil(n / cols);
	const startY = top + Math.floor((bottom - top - rowsN * gap) / 2) + gap / 2;
	dice.forEach((d, i) => {
		const row = Math.floor(i / cols);
		const inRow = Math.min(cols, n - row * cols);
		const col = i % cols;
		const cx = TRAY_CX - (inRow - 1) * gap / 2 + col * gap;
		const cy = startY + row * gap;
		let style = "normal";
		if (!d.kept) style = "dropped";
		else if (result && d.sides === 20 && result.natural === d.value && (result.crit || result.fumble)) style = "hot";
		Dice3D.draw(g, bodies[i], cx, cy, r, d.value, style);
	});
}

export function drawTray(g, t) {
	g.setColor("black");
	g.line(TRAY_X - 2, BODY_Y, TRAY_X - 2, FOOTER_Y - 1);
	const s = fonts.small;
	const row = t.row;
	const y = BODY_Y + 3;
	if (!row) {
		g.text(s, "Nothing to roll", TRAY_CX, y + 70, "center");
		return;
	}
	g.text(s, g.fit(s, row.title || row.label, TRAY_W), TRAY_CX, y, "center");

	if (row.kind === "resource") {
		const [cur, max] = t.getResource(row.key);
		if (row.detail) g.text(s, row.detail, TRAY_CX, y + 16, "center");
		g.text(fonts.big, String(cur), TRAY_CX, y + 50, "center");
		g.text(s, "of " + max, TRAY_CX, y + 90, "center");
		if (usePips(row.key, max)) drawPips(g, cur, max, TRAY_CX + Math.floor(max * PIP_GAP / 2), y + 118);
		g.text(s, "🎣 adjust", TRAY_CX, y + 140, "center");
		g.text(s, "Ⓐ -1   Ⓑ +1", TRAY_CX, y + 158, "center");
		return;
	}

	if (row.kind === "counter") {
		g.text(fonts.big, counterText(row.key, t.getCounter(row.key)), TRAY_CX, y + 18, "center");
		if (t.preview) {
			g.text(s, g.fit(s, "Pool: " + Dice.format(t.spec), TRAY_W), TRAY_CX, y + 56, "center");
			drawDiceGrid(g, t.preview.dice, t.preview.bodies, y + 70, y + 136);
		} else {
			g.text(s, "Pool is empty", TRAY_CX, y + 90, "center");
		}
		g.text(s, "🎣 adjust", TRAY_CX, y + 140, "center");
		g.text(s, "Ⓐ -1   Ⓑ +1", TRAY_CX, y + 158, "center");
		return;
	}

	if (row.kind === "rest") {
		g.text(s, row.detail, TRAY_CX, y + 16, "center");
		const lines = row.key === "long"
			? ["Full HP, spell slots", "and features, half", "your Hit Dice back"]
			: ["Recharge short-rest", "features, then spend", "Hit Dice to heal"];
		lines.forEach((l, i) => g.text(s, l, TRAY_CX, y + 38 + i * 15, "center"));
		const rest = t.rest;
		const barW = TRAY_W - 16, barY = y + 100;
		const barX = TRAY_CX - barW / 2;
		g.setColor("black");
		g.drawRoundRect(barX, barY, barW, 14, 4);
		const fill = rest ? Math.floor((barW - 4) * rest.progress / t.restMax) : 0;
		if (fill > 0) g.fillRoundRect(barX + 2, barY + 2, fill, 10, 3);
		if (rest && rest.done) drawPill(g, "RESTED", TRAY_CX, y + 126);
		g.text(s, t.docked ? "Undock the crank" : "Crank to rest 🎣", TRAY_CX, y + 150, "center");
		return;
	}

	const roll = t.roll;
	const spec = roll ? roll.spec : t.spec;
	if (row.pool && !roll && !spec) {
		g.text(s, "Pool is empty", TRAY_CX, y + 60, "center");
		g.text(s, "Add dice with the", TRAY_CX, y + 90, "center");
		g.text(s, "rows below ⬇️", TRAY_CX, y + 106, "center");
		return;
	}
	let tag;
	if (roll && roll.crit) tag = "CRITICAL x2";
	else if (!roll && t.critPending && row.critable) tag = "CRITICAL x2";
	else if (spec.check) {
		const mode = roll ? roll.mode : t.mode;
		if (mode === "adv") tag = "ADVANTAGE";
		else if (mode === "dis") tag = "DISADVANTAGE";
	}
	if (tag) drawPill(g, tag, TRAY_CX, y + 15);
	else g.text(s, Dice.format(spec), TRAY_CX, y + 16, "center");

	const diceTop = y + 32, diceBottom = y + 120;
	if (!roll) {
		drawDiceGrid(g, t.preview.dice, t.preview.bodies, diceTop, diceBottom);
		if (row.detail) g.text(s, g.fit(s, row.detail, TRAY_W), TRAY_CX, y + 128, "center");
		g.text(s, t.docked ? "Press Ⓐ to roll" : "Crank to roll 🎣", TRAY_CX, y + 150, "center");
		return;
	}
	if (roll.phase === "tumble") {
		drawDiceGrid(g, roll.faces, roll.bodies, diceTop, diceBottom);
		g.text(s, "rolling...", TRAY_CX, y + 150, "center");
		return;
	}
	const res = roll.result;
	if (roll.phase === "landing") {
		drawDiceGrid(g, res.dice, roll.bodies, diceTop, diceBottom);
		return;
	}
	drawDiceGrid(g, res.dice, roll.bodies, diceTop, diceBottom, res);
	g.text(fonts.big, String(res.total), TRAY_CX, y + 122, "center");

	let note;
	if (res.crit) note = res.natural === 20 ? "NATURAL 20!" : `CRIT! (${res.natural})`;
	else if (res.fumble) note = "NATURAL 1";
	else if (res.lucky) note = "Lucky! rerolled a 1";
	else if (spec.bonus !== 0) note = `${res.total - spec.bonus} ${spec.bonus > 0 ? "+ " : "- "}${Math.abs(spec.bonus)}`;
	if (note) {
		if (res.crit || res.fumble) drawPill(g, note, TRAY_CX, y + 158);
		else g.text(s, note, TRAY_CX, y + 160, "center");
	}
}

// ------------------------------------------------------------ footer

export function drawFooter(g, mode, toast) {
	const s = fonts.small;
	const fy = FOOTER_Y + 2;
	g.setColor("black");
	g.line(0, FOOTER_Y, W, FOOTER_Y);
	if (toast) {
		g.fillRect(0, FOOTER_Y, W, H - FOOTER_Y);
		g.text(s, g.fit(s, toast, W - 12), W / 2, fy, "center", "white");
		return;
	}
	if (mode === "pool") {
		g.text(s, "⬅️➡️ page  ⬆️⬇️ select  🎣/Ⓐ roll", 6, fy);
		g.text(s, "Ⓑ clear", W - 6, fy, "right");
		return;
	}
	if (mode === "rest") {
		g.text(s, "⬅️➡️ page  ⬆️⬇️ select  🎣 crank to rest", 6, fy);
		return;
	}
	if (mode === "resource") {
		g.text(s, "⬅️➡️ page  ⬆️⬇️ select  🎣 adjust", 6, fy);
		g.text(s, "Ⓐ -1  Ⓑ +1", W - 6, fy, "right");
		return;
	}
	g.text(s, "⬅️➡️ page  ⬆️⬇️ select  🎣/Ⓐ roll", 6, fy);
	if (mode === "plain") return;
	const modeText = mode === "adv" ? "ADV" : mode === "dis" ? "DIS" : mode === "crit" ? "CRIT" : "normal";
	g.text(s, "Ⓑ " + modeText, W - 6, fy, "right");
}

// ------------------------------------------------------------ pause screen

// The left 200px of the pause screen: rule text for the selected row.
export function drawRuleCard(g, title, sub, body) {
	const X = 10, CW = 180;
	g.setColor("white");
	g.fillRect(0, 0, 200, H);
	g.setColor("black");
	g.fillRect(0, 0, 200, 30);
	g.text(fonts.title, g.fit(fonts.title, title, CW), X, 8, undefined, "white");
	let y = 36;
	if (sub !== "") {
		g.text(fonts.small, g.fit(fonts.small, sub, CW), X, y);
		y += 16;
		g.setDither(0.5);
		g.line(X, y, X + CW, y);
		g.setColor("black");
		y += 6;
	}
	let h = 236 - y;
	let font = fonts.body;
	if (g.textHeight(font, body, CW) > h) font = fonts.small;
	if (g.textHeight(font, body, CW) > h) {
		h -= 18;
		g.fillRect(0, 222, 199, 18);
		g.text(fonts.small, g.fit(fonts.small, "More: Rules in menu", CW), X, 224, undefined, "white");
	}
	g.textInRect(font, body, X, y, CW, h);
	g.setColor("black");
	g.line(199, 0, 199, H);
}

// The system menu on the right half. items: [{ label, value? }]
export function drawSystemMenu(g, items, sel) {
	g.setColor("white");
	g.fillRect(200, 0, 200, H);
	g.setColor("black");
	g.fillRect(200, 0, 2, H);
	const x = 214, w = 172;
	items.forEach((it, i) => {
		const y = 14 + i * 32;
		const selected = i === sel;
		if (selected) g.fillRoundRect(x - 6, y, w + 6, 28, 6);
		const mode = selected ? "white" : "copy";
		g.text(fonts.title, it.label, x + 4, y + 6, undefined, mode);
		if (it.value) {
			g.text(fonts.body, it.value, x + w - 10, y + 5, "right", mode);
			if (selected) {
				const ax = x + w - 18 - g.textW(fonts.body, it.value);
				g.setColor("white");
				g.fillPolygon([ax, y + 14, ax + 5, y + 9, ax + 5, y + 19]);
				g.fillPolygon([x + w - 4, y + 14, x + w - 9, y + 9, x + w - 9, y + 19]);
				g.setColor("black");
			}
		}
	});
	g.setDither(0.5);
	g.line(x, 200, x + w - 6, 200);
	g.setColor("black");
	g.text(fonts.small, "Ⓑ or menu to resume", x, 210);
}

// ------------------------------------------------------------ rules viewer

export function measureRuleBody(g, body) {
	if (body === "") body = "No extra rules for this row.";
	return { text: body, height: Math.max(g.textHeight(fonts.body, body, RULES_W) + 4, 1) };
}

export function drawRuleViewer(g, v, dy) {
	dy = Math.floor(dy);
	const s = fonts.small;
	g.setColor("white");
	g.fillRect(0, dy, W, H);
	g.setColor("black");
	g.fillRect(0, dy, W, 28);
	g.text(fonts.title, g.fit(fonts.title, v.title, W - 24), RULES_X, dy + 7, undefined, "white");
	g.text(s, g.fit(s, v.sub, RULES_W), RULES_X, dy + 31);
	g.setDither(0.5);
	g.line(RULES_X, dy + 47, W - RULES_X, dy + 47);
	g.setColor("black");

	const top = dy + RULES_BODY_Y, h = RULES_BODY_H;
	g.clip(0, top, W, h);
	g.textInRect(fonts.body, v.text, RULES_X, top - Math.floor(v.scroll), RULES_W, 10000);
	g.unclip();

	const maxScroll = Math.max(v.height - h, 0);
	if (maxScroll > 0) {
		const trackX = W - 8;
		const thumbH = Math.max(Math.floor(h * h / v.height), 12);
		const thumbY = top + Math.floor((h - thumbH) * v.scroll / maxScroll);
		g.setDither(0.75);
		g.line(trackX + 1, top, trackX + 1, top + h);
		g.setColor("black");
		g.fillRoundRect(trackX, thumbY, 3, thumbH, 1);
		if (v.scroll < maxScroll - 1) {
			const ax = W - 100;
			const ay = dy + FOOTER_Y + 6 + Math.floor(Math.sin(v.bob) * 2 + 0.5);
			g.fillPolygon([ax - 5, ay, ax + 5, ay, ax, ay + 5]);
		}
	}
	g.line(0, dy + FOOTER_Y, W, dy + FOOTER_Y);
	g.text(s, "🎣/⬆️⬇️ scroll  Ⓐ page", 6, dy + FOOTER_Y + 2);
	g.text(s, "Ⓑ close", W - 6, dy + FOOTER_Y + 2, "right");
}
