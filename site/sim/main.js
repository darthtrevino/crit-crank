// Entry point: wires the Playdate-shaped device on the page to the game.
import { Gfx } from "./gfx.js";
import { Game } from "./game.js";
import * as Sound from "./sound.js";

const root = document.querySelector("[data-sim]");
if (root) start(root);

function start(root) {
	const canvas = root.querySelector("canvas.pd-screen");
	const fitCanvas = () => {
		const scale = Math.max(1, Math.round(canvas.clientWidth * (window.devicePixelRatio || 1) / 400));
		if (canvas.width !== 400 * scale) {
			canvas.width = 400 * scale;
			canvas.height = 240 * scale;
		}
	};
	fitCanvas();
	const g = new Gfx(canvas);
	const game = new Game(g);
	new ResizeObserver(() => { fitCanvas(); game.draw(); }).observe(canvas);
	window.critCrank = game;

	// ---------------------------------------------------------------- buttons
	const buttons = root.querySelectorAll("[data-btn]");
	for (const el of buttons) {
		const name = el.dataset.btn;
		const down = (e) => {
			e.preventDefault();
			el.setPointerCapture?.(e.pointerId);
			el.classList.add("is-down");
			game.press(name);
		};
		const up = () => {
			if (!el.classList.contains("is-down")) return;
			el.classList.remove("is-down");
			game.unpress(name);
		};
		el.addEventListener("pointerdown", down);
		el.addEventListener("pointerup", up);
		el.addEventListener("pointercancel", up);
		el.addEventListener("lostpointercapture", up);
		el.addEventListener("contextmenu", (e) => e.preventDefault());
	}
	const btnEl = (name) => root.querySelector(`[data-btn="${name}"]`);

	// ---------------------------------------------------------------- keyboard
	const KEYS = {
		ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
		w: "up", s: "down", a: "left", d: "right",
		x: "a", Enter: "a", z: "b", Backspace: "b",
		Escape: "menu", m: "menu",
	};
	const CRANK_KEYS = { "]": 15, ".": 15, "[": -15, ",": -15 };
	const held = new Set();
	const crankHeld = new Map();
	let active = false;

	root.addEventListener("pointerdown", () => { active = true; });
	document.addEventListener("pointerdown", (e) => { if (!root.contains(e.target)) active = false; });
	root.addEventListener("focusin", () => { active = true; });

	document.addEventListener("keydown", (e) => {
		if (!active || e.metaKey || e.ctrlKey || e.altKey) return;
		const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
		if (key in CRANK_KEYS) {
			e.preventDefault();
			crankHeld.set(key, CRANK_KEYS[key]);
			return;
		}
		const btn = KEYS[key];
		if (!btn) return;
		e.preventDefault();
		if (held.has(key)) return;
		held.add(key);
		btnEl(btn)?.classList.add("is-down");
		game.press(btn);
	});
	document.addEventListener("keyup", (e) => {
		const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
		crankHeld.delete(key);
		if (!held.delete(key)) return;
		const btn = KEYS[key];
		btnEl(btn)?.classList.remove("is-down");
		game.unpress(btn);
	});
	window.addEventListener("blur", () => {
		held.clear();
		crankHeld.clear();
		game.releaseAll();
		for (const el of buttons) el.classList.remove("is-down");
	});

	// ---------------------------------------------------------------- crank
	const crank = root.querySelector(".pd-crank");
	const hub = root.querySelector(".pd-crank-hub");
	let crankAngle = 90;
	const turn = (deg) => {
		crankAngle = (crankAngle + deg) % 360;
		const rad = crankAngle * Math.PI / 180;
		crank.style.setProperty("--sin", Math.sin(rad).toFixed(4));
		crank.style.setProperty("--cos", Math.cos(rad).toFixed(4));
		crank.setAttribute("aria-valuenow", String(Math.round((crankAngle + 360) % 360)));
		game.cranked(deg);
	};

	let drag = null;
	const angleAt = (e) => {
		const r = hub.getBoundingClientRect();
		const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
		return Math.atan2(e.clientY - cy, e.clientX - cx) * 180 / Math.PI;
	};
	crank.addEventListener("pointerdown", (e) => {
		e.preventDefault();
		active = true;
		crank.setPointerCapture(e.pointerId);
		drag = angleAt(e);
		crank.classList.add("is-turning");
	});
	crank.addEventListener("pointermove", (e) => {
		if (drag == null) return;
		const a = angleAt(e);
		let d = a - drag;
		if (d > 180) d -= 360;
		if (d < -180) d += 360;
		drag = a;
		turn(d);
	});
	const endDrag = () => { drag = null; crank.classList.remove("is-turning"); };
	crank.addEventListener("pointerup", endDrag);
	crank.addEventListener("pointercancel", endDrag);

	// Scrolling over the crank or the screen turns the crank.
	const wheel = (e) => {
		e.preventDefault();
		active = true;
		const d = e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY;
		turn(Math.max(-60, Math.min(60, d * 0.6)));
	};
	crank.addEventListener("wheel", wheel, { passive: false });
	canvas.addEventListener("wheel", wheel, { passive: false });

	// ---------------------------------------------------------------- extras
	const mute = root.querySelector("[data-mute]");
	if (mute) {
		const sync = () => {
			mute.setAttribute("aria-pressed", String(Sound.isMuted()));
			mute.textContent = Sound.isMuted() ? "Sound off" : "Sound on";
		};
		mute.addEventListener("click", () => { Sound.setMuted(!Sound.isMuted()); sync(); });
		sync();
	}
	root.querySelector("[data-reset]")?.addEventListener("click", () => game.reset());
	for (const el of document.querySelectorAll("[data-sim-focus]")) {
		el.addEventListener("click", () => {
			const [page, label] = el.dataset.simFocus.split("|");
			game.focus(page, label);
			root.scrollIntoView({ behavior: "smooth", block: "center" });
			active = true;
		});
	}

	// docs.html links here as index.html#try=PAGE|Row Label
	const tryHash = /^#try=(.+)$/.exec(location.hash);
	if (tryHash) {
		const [page, label] = decodeURIComponent(tryHash[1]).split("|");
		game.focus(page, label);
		requestAnimationFrame(() => root.scrollIntoView({ block: "center" }));
	}

	// ---------------------------------------------------------------- loop
	let visible = true;
	new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; }).observe(root);
	const FRAME = 1000 / 30;
	let last = performance.now();
	let acc = 0;
	function frame(now) {
		requestAnimationFrame(frame);
		acc += Math.min(now - last, 250);
		last = now;
		if (!visible || document.hidden) { acc = 0; return; }
		if (acc < FRAME) return;
		while (acc >= FRAME) {
			for (const deg of crankHeld.values()) turn(deg);
			game.update();
			acc -= FRAME;
		}
		game.draw();
	}
	game.draw();
	requestAnimationFrame(frame);
}
