// A tiny 1-bit drawing layer that mimics playdate.graphics on a 400×240 canvas.
//
// Everything is drawn in pure black and white on an offscreen canvas, then
// thresholded and tinted to look like the Playdate's Memory LCD. Lines, circles
// and round rects are rasterised by hand so edges stay crisp; dither patterns
// leave their "off" pixels untouched, like setDitherPattern on the device.
// Text uses system fonts: the game's Panic fonts are licensed for Playdate games only.

export const W = 400;
export const H = 240;

const SANS = '"Helvetica Neue", Helvetica, Arial, sans-serif';

// y passed to text() is the top of the glyph cell, like gfx.drawText.
export const fonts = {
	small: { css: `bold 13px ${SANS}`, base: 12, height: 15 },
	body: { css: `400 20px ${SANS}`, base: 16, height: 21 },
	title: { css: `bold 16px ${SANS}`, base: 14, height: 18 },
	big: { css: `500 33px ${SANS}`, base: 27, height: 32 },
};

const BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
const BAYER2 = [0, 2, 3, 1];

// Inline glyphs used by the game's strings.
const ICON_RE = /(⬅️|➡️|⬆️|⬇️|🎣|Ⓐ|Ⓑ|●|◉|⬅|➡|⬆|⬇)/u;
const ICON_W = { pad: 13, crank: 12, button: 13, dot: 9 };

// Bitmaps traced from the game's font so the glyphs match the device.
const PAD = [
	".....##.....",
	"....#..#....",
	"....#..#....",
	"....#..#....",
	".####..####.",
	"#..........#",
	"#..........#",
	".####..####.",
	"....#..#....",
	"....#..#....",
	"....#..#....",
	".....##.....",
];
const PAD_FILL = {
	l: ["", "", "", "", "", "#####", "#####"],
	r: ["", "", "", "", "", ".......#####", ".......#####"],
	u: ["", ".....##", ".....##", ".....##", ".....##"],
	d: ["", "", "", "", "", "", "", ".....##", ".....##", ".....##", ".....##"],
};
const CRANK = [
	"...#######",
	"..##.....##",
	"###.......#",
	"###.......#",
	"###.......#",
	"####.....##",
	"##########",
	"###",
	"###",
	"###",
	"###",
	"###",
	"###",
];
const BUTTON = [
	"....####....",
	"..##....##..",
	".#........#.",
	".#........#.",
	"#..........#",
	"#..........#",
	"#..........#",
	"#..........#",
	".#........#.",
	".#........#.",
	"..##....##..",
	"....####....",
];
const LETTER_A = ["..##..", ".####.", "##..##", "######", "##..##", "##..##"];
const LETTER_B = ["#####.", "##..##", "#####.", "##..##", "##..##", "#####."];
const iconKind = (s) => {
	if (/^[⬅➡⬆⬇]/u.test(s)) return "pad";
	if (s === "🎣") return "crank";
	if (s === "Ⓐ" || s === "Ⓑ") return "button";
	return "dot";
};

export class Gfx {
	constructor(screen) {
		this.screen = screen;
		this.out = screen.getContext("2d");
		this.canvas = document.createElement("canvas");
		this.canvas.width = W;
		this.canvas.height = H;
		this.ctx = this.canvas.getContext("2d", { willReadFrequently: true });
		this.ctx.textBaseline = "alphabetic";
		this.patterns = new Map();
		this.color = "#000";
		this.fill = "#000";
		this.measureCache = new Map();
		this.ink = [0x31, 0x2f, 0x28];
		this.paper = [0xb1, 0xae, 0xa7];
		this.lcd = document.createElement("canvas");
		this.lcd.width = W;
		this.lcd.height = H;
		this.lcdCtx = this.lcd.getContext("2d");
		this.frame = this.lcdCtx.createImageData(W, H);
	}

	// ------------------------------------------------------------ state

	clear(color = "white") {
		const c = this.ctx;
		c.setTransform(1, 0, 0, 1, 0, 0);
		c.fillStyle = color === "white" ? "#fff" : "#000";
		c.fillRect(0, 0, W, H);
		this.setColor("black");
	}

	setColor(color) {
		this.color = color === "white" ? "#fff" : "#000";
		this.fill = this.color;
	}

	// alpha: 0 = solid, 1 = clear (fraction of pixels left untouched).
	setDither(alpha, type = "bayer4") {
		const q = Math.round(alpha * 16) / 16;
		const key = type + q + this.color;
		let p = this.patterns.get(key);
		if (!p) {
			const size = type === "bayer2" ? 2 : 4;
			const m = type === "bayer2" ? BAYER2 : BAYER4;
			const levels = size * size;
			const tile = document.createElement("canvas");
			tile.width = tile.height = size;
			const t = tile.getContext("2d");
			t.fillStyle = this.color;
			for (let i = 0; i < levels; i++) {
				if ((m[i] + 0.5) / levels >= q) t.fillRect(i % size, Math.floor(i / size), 1, 1);
			}
			p = this.ctx.createPattern(tile, "repeat");
			this.patterns.set(key, p);
		}
		this.fill = p;
	}

	clip(x, y, w, h) {
		this.ctx.save();
		this.ctx.beginPath();
		this.ctx.rect(x, y, w, h);
		this.ctx.clip();
	}

	unclip() {
		this.ctx.restore();
	}

	// ------------------------------------------------------------ shapes

	fillRect(x, y, w, h) {
		this.ctx.fillStyle = this.fill;
		this.ctx.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h));
	}

	px(x, y) {
		this.ctx.fillRect(x, y, 1, 1);
	}

	line(x0, y0, x1, y1, width = 1) {
		x0 = Math.round(x0); y0 = Math.round(y0); x1 = Math.round(x1); y1 = Math.round(y1);
		const c = this.ctx;
		c.fillStyle = this.fill;
		const o = Math.floor((width - 1) / 2);
		if (y0 === y1) { c.fillRect(Math.min(x0, x1), y0 - o, Math.abs(x1 - x0) + 1, width); return; }
		if (x0 === x1) { c.fillRect(x0 - o, Math.min(y0, y1), width, Math.abs(y1 - y0) + 1); return; }
		const dx = Math.abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
		const dy = -Math.abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
		let err = dx + dy;
		for (;;) {
			c.fillRect(x0 - o, y0 - o, width, width);
			if (x0 === x1 && y0 === y1) break;
			const e2 = 2 * err;
			if (e2 >= dy) { err += dy; x0 += sx; }
			if (e2 <= dx) { err += dx; y0 += sy; }
		}
	}

	// Horizontal inset of each row in a corner of radius r.
	cornerInsets(r) {
		const out = [];
		for (let i = 0; i < r; i++) {
			const dy = r - i - 0.5;
			out.push(Math.round(r - Math.sqrt(Math.max(0, r * r - dy * dy))));
		}
		return out;
	}

	fillRoundRect(x, y, w, h, r) {
		x = Math.round(x); y = Math.round(y); w = Math.round(w); h = Math.round(h);
		r = Math.min(Math.round(r), Math.floor(w / 2), Math.floor(h / 2));
		const c = this.ctx;
		c.fillStyle = this.fill;
		const ins = this.cornerInsets(r);
		for (let i = 0; i < r; i++) {
			c.fillRect(x + ins[i], y + i, w - 2 * ins[i], 1);
			c.fillRect(x + ins[i], y + h - 1 - i, w - 2 * ins[i], 1);
		}
		c.fillRect(x, y + r, w, h - 2 * r);
	}

	drawRoundRect(x, y, w, h, r) {
		x = Math.round(x); y = Math.round(y); w = Math.round(w); h = Math.round(h);
		r = Math.min(Math.round(r), Math.floor(w / 2), Math.floor(h / 2));
		const c = this.ctx;
		c.fillStyle = this.fill;
		const ins = this.cornerInsets(r);
		c.fillRect(x + r, y, w - 2 * r, 1);
		c.fillRect(x + r, y + h - 1, w - 2 * r, 1);
		c.fillRect(x, y + r, 1, h - 2 * r);
		c.fillRect(x + w - 1, y + r, 1, h - 2 * r);
		for (let i = 0; i < r; i++) {
			const a = ins[i];
			const b = i + 1 < r ? ins[i + 1] : 0;
			const len = Math.max(1, a - b);
			for (const yy of [y + i, y + h - 1 - i]) {
				c.fillRect(x + b, yy, len, 1);
				c.fillRect(x + w - b - len, yy, len, 1);
			}
		}
	}

	fillCircle(cx, cy, r) {
		const c = this.ctx;
		c.fillStyle = this.fill;
		cx = Math.round(cx); cy = Math.round(cy);
		for (let dy = -r; dy <= r; dy++) {
			const dx = Math.floor(Math.sqrt(r * r + r * 0.8 - dy * dy));
			c.fillRect(cx - dx, cy + dy, 2 * dx + 1, 1);
		}
	}

	drawCircle(cx, cy, r) {
		const c = this.ctx;
		c.fillStyle = this.fill;
		cx = Math.round(cx); cy = Math.round(cy);
		let x = r, y = 0, err = 1 - r;
		while (x >= y) {
			for (const [px, py] of [[x, y], [y, x], [-y, x], [-x, y], [-x, -y], [-y, -x], [y, -x], [x, -y]]) {
				c.fillRect(cx + px, cy + py, 1, 1);
			}
			y++;
			if (err < 0) err += 2 * y + 1;
			else { x--; err += 2 * (y - x) + 1; }
		}
	}

	fillPolygon(pts) {
		const c = this.ctx;
		c.fillStyle = this.fill;
		c.beginPath();
		c.moveTo(pts[0], pts[1]);
		for (let i = 2; i < pts.length; i += 2) c.lineTo(pts[i], pts[i + 1]);
		c.closePath();
		c.fill();
	}

	drawPolygon(pts, width = 1) {
		const n = pts.length;
		for (let i = 0; i < n; i += 2) this.line(pts[i], pts[i + 1], pts[(i + 2) % n], pts[(i + 3) % n], width);
	}

	// ------------------------------------------------------------ text

	splitIcons(s) {
		return String(s).split(ICON_RE).filter((p) => p !== "" && p !== "\uFE0F");
	}

	textW(font, s) {
		const key = font.css + "\u0000" + s;
		let w = this.measureCache.get(key);
		if (w === undefined) {
			const c = this.ctx;
			c.font = font.css;
			w = 0;
			for (const part of this.splitIcons(s)) {
				w += ICON_RE.test(part) ? ICON_W[iconKind(part)] : c.measureText(part).width;
			}
			w = Math.round(w);
			this.measureCache.set(key, w);
		}
		return w;
	}

	// mode: "copy" (black ink) or "white" (kDrawModeFillWhite)
	text(font, s, x, y, align, mode = "copy") {
		s = String(s);
		if (align === "right") x -= this.textW(font, s);
		else if (align === "center") x -= Math.floor(this.textW(font, s) / 2);
		const c = this.ctx;
		c.font = font.css;
		c.fillStyle = mode === "white" ? "#fff" : "#000";
		let cx = Math.round(x);
		const base = Math.round(y) + font.base;
		for (const part of this.splitIcons(s)) {
			if (ICON_RE.test(part)) {
				const kind = iconKind(part);
				this.icon(kind, part, cx, base, c.fillStyle);
				cx += ICON_W[kind];
			} else {
				c.fillText(part, cx, base);
				cx += c.measureText(part).width;
			}
		}
	}

	icon(kind, ch, x, base, color) {
		const c = this.ctx;
		c.fillStyle = color;
		const blit = (rows, ox, oy) => rows.forEach((row, yy) => {
			for (let xx = 0; xx < row.length; xx++) if (row[xx] === "#") c.fillRect(ox + xx, oy + yy, 1, 1);
		});
		if (kind === "pad") {
			const arm = { "⬅": "l", "➡": "r", "⬆": "u", "⬇": "d" }[ch[0]];
			blit(PAD, x, base - 11);
			blit(PAD_FILL[arm], x, base - 11);
			return;
		}
		if (kind === "crank") {
			blit(CRANK, x, base - 12);
			return;
		}
		if (kind === "button") {
			blit(BUTTON, x, base - 11);
			blit(ch === "Ⓐ" ? LETTER_A : LETTER_B, x + 3, base - 8);
			return;
		}
		const save = this.fill;
		const top = base - 11;
		this.fill = color;
		if (ch === "◉") { this.fillCircle(x + 4, top + 5, 2); this.drawCircle(x + 4, top + 5, 4); }
		else this.fillCircle(x + 4, top + 5, 3);
		this.fill = save;
	}

	// Shortens s with "…" until it fits in maxW pixels.
	fit(font, s, maxW) {
		s = String(s);
		if (this.textW(font, s) <= maxW) return s;
		let chars = [...s];
		while (chars.length > 1 && this.textW(font, chars.join("") + "…") > maxW) chars.pop();
		return chars.join("") + "…";
	}

	// Word wraps text (with \n paragraphs) into lines no wider than w.
	wrap(font, text, w) {
		const lines = [];
		for (const para of String(text).split("\n")) {
			let line = "";
			for (const word of para.split(" ")) {
				const next = line ? line + " " + word : word;
				if (line && this.textW(font, next) > w) {
					lines.push(line);
					line = word;
				} else {
					line = next;
				}
			}
			lines.push(line);
		}
		return lines;
	}

	textHeight(font, text, w) {
		return this.wrap(font, text, w).length * font.height;
	}

	// Like gfx.drawTextInRect with "…" truncation; align is "left" (default) or "center".
	textInRect(font, text, x, y, w, h, align) {
		const lines = this.wrap(font, text, w);
		const max = Math.max(1, Math.floor(h / font.height));
		if (lines.length > max) {
			lines.length = max;
			lines[max - 1] = this.fit(font, lines[max - 1] + "…", w);
		}
		const lx = align === "center" ? x + w / 2 : x;
		lines.forEach((l, i) => this.text(font, l, lx, y + i * font.height, align));
	}

	// ------------------------------------------------------------ output

	// Thresholds the frame to 1-bit and tints it like the LCD.
	present() {
		const src = this.ctx.getImageData(0, 0, W, H).data;
		const dst = this.frame.data;
		const [ir, ig, ib] = this.ink;
		const [pr, pg, pb] = this.paper;
		for (let i = 0; i < src.length; i += 4) {
			const black = src[i] + src[i + 1] + src[i + 2] < 400;
			dst[i] = black ? ir : pr;
			dst[i + 1] = black ? ig : pg;
			dst[i + 2] = black ? ib : pb;
			dst[i + 3] = 255;
		}
		this.lcdCtx.putImageData(this.frame, 0, 0);
		// The screen canvas is an integer multiple of 400×240 sized to the
		// device pixels, so each LCD pixel stays a crisp square.
		this.out.imageSmoothingEnabled = false;
		this.out.drawImage(this.lcd, 0, 0, this.screen.width, this.screen.height);
	}
}
