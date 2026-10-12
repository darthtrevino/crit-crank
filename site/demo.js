// Interactive Crit Crank demo: a tiny re-creation of the Playdate sheet in the browser.
(() => {
	const $ = (id) => document.getElementById(id);
	const screen = $("screen"), tabsEl = $("tabs"), listEl = $("list");
	const trayTitle = $("trayTitle"), traySpec = $("traySpec"), die = $("die");
	const totalEl = $("total"), noteEl = $("note"), crank = $("crank"), arm = $("arm");
	const modeEl = document.querySelector(".ftr span:last-child");
	if (!screen) return;

	const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
	const mod = (s) => Math.floor((s - 10) / 2);
	const sign = (n) => (n >= 0 ? "+" : "") + n;
	const PB = 2, CRIT = 19;
	const abil = { STR: 16, DEX: 12, CON: 16, INT: 10, WIS: 13, CHA: 8 };
	const saveProf = new Set(["STR", "CON"]);

	const pages = [
		{ name: "ABILITY", rows: Object.entries(abil).map(([k, v]) => ({ label: k, det: String(v), dice: "1d20", bonus: mod(v), d20: true })) },
		{ name: "SAVES", rows: Object.keys(abil).map((k) => ({ label: k + " save", det: saveProf.has(k) ? "●" : "", dice: "1d20", bonus: mod(abil[k]) + (saveProf.has(k) ? PB : 0), d20: true })) },
		{ name: "ACTIONS", rows: [
			{ hdr: "Longsword" },
			{ label: "Attack", dice: "1d20", bonus: 5, d20: true, attack: true },
			{ label: "Damage", det: "slashing", dice: "1d8", bonus: 5 },
			{ hdr: "Handaxe" },
			{ label: "Attack", dice: "1d20", bonus: 5, d20: true, attack: true },
			{ label: "Damage", det: "slashing", dice: "1d6", bonus: 3 },
			{ hdr: "Other" },
			{ label: "Initiative", dice: "1d20", bonus: 1, d20: true },
		] },
	];
	const modes = ["normal", "advantage", "disadvantage"];
	let page = 0, sel = 0, mode = 0;

	const selectable = () => pages[page].rows.map((r, i) => (r.hdr ? -1 : i)).filter((i) => i >= 0);
	const row = () => pages[page].rows[sel];

	// --- rendering -------------------------------------------------------------
	function renderTabs() {
		tabsEl.innerHTML = pages.map((p, i) => `<span class="${i === page ? "on" : "off"}">${p.name}</span>`).join("");
	}
	function renderList() {
		listEl.innerHTML = pages[page].rows.map((r, i) => r.hdr
			? `<li class="hdrrow">${r.hdr}</li>`
			: `<li class="${i === sel ? "sel" : ""}"><span class="lbl">${r.label}</span><span class="det">${r.det ?? ""}</span><span class="val">${r.dice === "1d20" ? sign(r.bonus) : r.dice + sign(r.bonus)}</span></li>`).join("");
	}
	function renderTray() {
		const r = row();
		trayTitle.textContent = r.label;
		traySpec.textContent = r.dice + sign(r.bonus) + (r.d20 && mode ? (mode === 1 ? " adv" : " dis") : "");
		modeEl.textContent = "Ⓑ " + modes[mode];
	}
	function sides() { return parseInt(row().dice.split("d")[1], 10); }

	// Simple flat-shaded die silhouettes keyed by side count.
	const shapes = {
		20: { outer: "0,-46 40,-23 40,23 0,46 -40,23 -40,-23", inner: "0,-26 23,14 -23,14", shade: "40,23 0,46 -40,23 -23,14 23,14" },
		8: { outer: "0,-46 40,0 0,46 -40,0", inner: "0,-46 40,0 -40,0", shade: "40,0 0,46 -40,0" },
		6: { outer: "-36,-36 36,-36 36,36 -36,36", inner: "", shade: "" },
	};
	function drawDie(n, face) {
		const s = shapes[n] || shapes[20];
		die.innerHTML =
			`<polygon points="${s.outer}"/>` +
			(s.shade ? `<polygon class="shade" points="${s.shade}"/>` : "") +
			(s.inner ? `<polygon points="${s.inner}" style="fill:none"/>` : "") +
			`<text y="${n === 20 ? 2 : n === 8 ? -8 : 0}">${face ?? n}</text>`;
	}
	function idle() {
		drawDie(sides());
		totalEl.textContent = "";
		noteEl.className = "note";
		noteEl.textContent = "Crank to roll";
	}
	function render() { renderTabs(); renderList(); renderTray(); idle(); }

	// --- sound -----------------------------------------------------------------
	let ctx;
	function audio() { ctx ??= new (window.AudioContext || window.webkitAudioContext)(); return ctx; }
	function tone(t, f, dur, type, gain = 0.12, f2) {
		const a = audio(), o = a.createOscillator(), g = a.createGain();
		o.type = type; o.frequency.setValueAtTime(f, t);
		if (f2) o.frequency.exponentialRampToValueAtTime(f2, t + dur);
		g.gain.setValueAtTime(0.0001, t);
		g.gain.exponentialRampToValueAtTime(gain, t + 0.02);
		g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
		o.connect(g).connect(a.destination); o.start(t); o.stop(t + dur + 0.05);
	}
	function airHorn() {
		const t = audio().currentTime;
		// DJ air horn: three quick BRAPs then a long blast on F#5
		[[0, 0.11], [0.15, 0.11], [0.3, 0.11], [0.48, 0.9]].forEach(([d, len]) =>
			[[740, "square"], [745, "sawtooth"], [1480, "sawtooth"]].forEach(([f, type]) =>
				tone(t + d, f, len, type, 0.035, len > 0.5 ? f * 0.94 : undefined)));
	}
	function sadTrombone() {
		const t = audio().currentTime;
		[[0, 294, 0.32], [0.36, 277, 0.32], [0.72, 262, 0.32], [1.08, 247, 0.9]].forEach(([d, f, len]) =>
			tone(t + d, f, len, "triangle", 0.14, len > 0.5 ? 233 : undefined));
	}
	function tick() { tone(audio().currentTime, 1800, 0.03, "square", 0.025); }

	// --- rolling ---------------------------------------------------------------
	const rand = (n) => 1 + Math.floor(Math.random() * n);
	let spinTimer = null;
	function startSpin() {
		if (spinTimer) return;
		totalEl.textContent = "";
		noteEl.className = "note"; noteEl.textContent = "rolling…";
		die.classList.remove("land");
		if (!reduceMotion) die.classList.add("spin");
		const n = sides();
		spinTimer = setInterval(() => drawDie(n, rand(n)), 70);
	}
	function land() {
		clearInterval(spinTimer); spinTimer = null;
		const r = row(), n = sides();
		let face = rand(n), detail = "";
		if (r.d20 && mode) {
			const other = rand(20);
			const pick = mode === 1 ? Math.max(face, other) : Math.min(face, other);
			detail = `${face} / ${other} → `; face = pick;
		}
		die.classList.remove("spin");
		void die.getBoundingClientRect();
		if (!reduceMotion) die.classList.add("land");
		drawDie(n, face);
		totalEl.textContent = face + r.bonus;
		noteEl.className = "note";
		if (r.d20 && face === 20) {
			noteEl.textContent = "NATURAL 20!"; noteEl.className = "note badge pop"; airHorn();
		} else if (r.attack && face >= CRIT) {
			noteEl.textContent = "CRITICAL HIT"; noteEl.className = "note badge pop"; airHorn();
		} else if (r.d20 && face === 1) {
			noteEl.textContent = "natural 1…"; sadTrombone();
		} else {
			noteEl.textContent = `${detail}${face} ${r.bonus < 0 ? "−" : "+"} ${Math.abs(r.bonus)}`;
		}
	}
	function quickRoll() { startSpin(); setTimeout(land, reduceMotion ? 0 : 600); }

	// --- crank -----------------------------------------------------------------
	let angle = 0, wound = 0, lastTick = 0, stopTimer = null, dragging = false, prev = null;
	function setAngle(a) {
		angle = ((a % 360) + 360) % 360;
		arm.style.transform = `rotate(${angle}deg)`;
		crank.setAttribute("aria-valuenow", Math.round(angle));
	}
	function crankBy(delta) {
		setAngle(angle + delta);
		wound += Math.abs(delta);
		if (wound > 20) startSpin();
		if (Math.abs(wound - lastTick) > 30) { lastTick = wound; tick(); }
		clearTimeout(stopTimer);
		stopTimer = setTimeout(() => {
			if (spinTimer && wound >= 180) land();
			else if (spinTimer) { clearInterval(spinTimer); spinTimer = null; die.classList.remove("spin"); idle(); noteEl.textContent = "Keep cranking!"; }
			wound = 0; lastTick = 0;
		}, 220);
	}
	const pointerAngle = (e) => {
		const b = crank.getBoundingClientRect();
		return Math.atan2(e.clientY - (b.top + b.height / 2), e.clientX - (b.left + b.width / 2)) * 180 / Math.PI;
	};
	crank.addEventListener("pointerdown", (e) => { dragging = true; prev = pointerAngle(e); crank.setPointerCapture(e.pointerId); e.preventDefault(); });
	crank.addEventListener("pointermove", (e) => {
		if (!dragging) return;
		const a = pointerAngle(e);
		let d = a - prev; if (d > 180) d -= 360; if (d < -180) d += 360;
		prev = a; if (d) crankBy(d);
	});
	const endDrag = () => { dragging = false; };
	crank.addEventListener("pointerup", endDrag);
	crank.addEventListener("pointercancel", endDrag);
	crank.addEventListener("wheel", (e) => { e.preventDefault(); crankBy(Math.sign(e.deltaY || e.deltaX) * 24); }, { passive: false });
	crank.addEventListener("keydown", (e) => {
		if (["ArrowUp", "ArrowRight"].includes(e.key)) { e.preventDefault(); crankBy(30); }
		else if (["ArrowDown", "ArrowLeft"].includes(e.key)) { e.preventDefault(); crankBy(-30); }
		else if (e.key === "Enter" || e.key === " ") { e.preventDefault(); quickRoll(); }
	});

	// --- buttons ---------------------------------------------------------------
	function press(key) {
		const s = selectable(), i = s.indexOf(sel);
		switch (key) {
			case "ArrowUp": sel = s[(i - 1 + s.length) % s.length]; renderList(); renderTray(); idle(); break;
			case "ArrowDown": sel = s[(i + 1) % s.length]; renderList(); renderTray(); idle(); break;
			case "ArrowLeft": case "ArrowRight":
				page = (page + (key === "ArrowRight" ? 1 : pages.length - 1)) % pages.length;
				sel = selectable()[0]; render(); break;
			case "b": mode = (mode + 1) % modes.length; renderTray(); break;
			case " ": case "a": case "Enter": quickRoll(); break;
			default: return false;
		}
		return true;
	}
	document.querySelectorAll("[data-key]").forEach((b) => b.addEventListener("click", () => { press(b.dataset.key); }));
	screen.addEventListener("keydown", (e) => {
		if (press(e.key.length === 1 ? e.key.toLowerCase() : e.key)) e.preventDefault();
	});

	sel = selectable()[0];
	render();
})();
