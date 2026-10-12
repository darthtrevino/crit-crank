// Synthesised sounds, after main.lua's playdate.sound setup (Web Audio).

let ac = null;
let master = null;
let muted = false;

function audio() {
	if (muted) return null;
	if (!ac) {
		const AC = window.AudioContext || window.webkitAudioContext;
		if (!AC) return null;
		ac = new AC();
		master = ac.createGain();
		master.gain.value = 0.5;
		master.connect(ac.destination);
	}
	if (ac.state === "suspended") ac.resume();
	return ac;
}

export function setMuted(m) {
	muted = m;
	if (master) master.gain.value = m ? 0 : 0.5;
}

export const isMuted = () => muted;

// Call from a user gesture so later sounds are allowed to play.
export function unlock() {
	audio();
}

// A synth note with a Playdate-style ADSR envelope (seconds; sustain is a level).
function note({ wave, freq, vol, len, a = 0, d = 0, s = 1, r = 0, at = 0, dest, detune = 0, vibrato }) {
	const ctx = audio();
	if (!ctx) return;
	const t0 = ctx.currentTime + at;
	const osc = ctx.createOscillator();
	osc.type = wave;
	osc.frequency.value = freq;
	osc.detune.value = detune;
	if (vibrato) {
		const lfo = ctx.createOscillator();
		const depth = ctx.createGain();
		lfo.type = vibrato.wave || "sine";
		lfo.frequency.value = vibrato.rate;
		depth.gain.value = freq * vibrato.depth;
		lfo.connect(depth).connect(osc.frequency);
		lfo.start(t0);
		lfo.stop(t0 + len + r + 0.05);
	}
	const env = ctx.createGain();
	const peak = vol * 0.4;
	env.gain.setValueAtTime(0, t0);
	env.gain.linearRampToValueAtTime(peak, t0 + a + 0.001);
	env.gain.linearRampToValueAtTime(peak * s, t0 + a + d + 0.002);
	const end = t0 + Math.max(len, a + d + 0.003);
	env.gain.setValueAtTime(peak * s, end);
	env.gain.linearRampToValueAtTime(0, end + r + 0.005);
	osc.connect(env).connect(dest || master);
	osc.start(t0);
	osc.stop(end + r + 0.05);
	return osc;
}

export function tick(freq = 600 + Math.random() * 600, vol = 0.12, len = 0.02) {
	note({ wave: "square", freq, vol, len, d: 0.02, s: 0 });
}

export function land(freq, vol, len) {
	note({ wave: "triangle", freq, vol: vol * 2, len, d: 0.15, s: 0.2, r: 0.2 });
}

export function landFor(result) {
	if (result.crit) land(1047, 0.5, 0.4);
	else if (result.fumble) land(131, 0.5, 0.4);
	else land(523, 0.35, 0.1);
}

// DJ air horn for natural 20s, as in main.lua. HORN must match main.lua's;
// the sound-design skill's tuner passes its own settings to horn().
export const HORN = Object.freeze({ hitHz: 587.3, hitMs: 155, hz: 740, sagAt: 150, sag: -4.05, sagMs: 90, holdMs: 310 });
const HORN_VOICES = [[0.5, "sawtooth", 0.2], [737 / 740, "sawtooth", 0.15], [743.5 / 740, "sawtooth", 0.15], [1, "square", 0.12], [2, "sawtooth", 0.06]];
export function horn(h = HORN) {
	const ctx = audio();
	if (!ctx) return;
	const lp = ctx.createBiquadFilter();
	lp.type = "lowpass";
	lp.frequency.value = 4200;
	lp.connect(master);
	// pd.easingFunctions.outQuad, sampled for the drop
	const curve = Float32Array.from({ length: 32 }, (_, i) => { const x = i / 31; return h.sag * 100 * x * (2 - x); });
	const blast = (at, hz, len, env, sag) => {
		for (const [ratio, wave, vol] of HORN_VOICES) {
			const osc = note({ wave, freq: hz * ratio, vol, len, ...env, at, dest: lp });
			if (osc && sag && h.sag && h.sagMs > 0) {
				osc.detune.setValueCurveAtTime(curve, ctx.currentTime + at + h.sagAt / 1000, h.sagMs / 1000);
			}
		}
	};
	const shortEnv = { a: 0.008, d: 0.04, s: 0.85, r: 0.05 };
	for (let i = 0; i < 3; i++) blast(i * h.hitMs / 1000, h.hitHz, 0.1, shortEnv);
	const len = (h.sagAt + h.sagMs + h.holdMs) / 1000;
	blast((3 * h.hitMs + 30) / 1000, h.hz, len, { a: 0.012, d: 0.08, s: 0.9, r: 0.3 }, true);
}

// Sad trombone for natural 1s: wah wah wah waaaaah.
export function trombone() {
	const ctx = audio();
	if (!ctx) return;
	const lp = ctx.createBiquadFilter();
	lp.type = "lowpass";
	lp.frequency.value = 1100;
	lp.Q.value = 2;
	lp.connect(master);
	[233.1, 220.0, 207.7, 196.0].forEach((f, i) => {
		const last = i === 3;
		note({
			wave: "sawtooth", freq: f, vol: 0.45, len: last ? 1.3 : 0.32, a: 0.04, d: 0.1, s: 0.8, r: 0.15,
			at: i * 0.43, dest: lp, vibrato: last ? { rate: 5.5, depth: 0.03 } : undefined,
		});
	});
}
