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

// DJ air horn for natural 20s: BRAP-BRAP-BRAP-BRAAAAAP.
export function horn() {
	const ctx = audio();
	if (!ctx) return;
	const shaper = ctx.createWaveShaper();
	const curve = new Float32Array(256);
	for (let i = 0; i < 256; i++) { const x = i / 128 - 1; curve[i] = Math.tanh(x * 2.5) * 0.6; }
	shaper.curve = curve;
	const hp = ctx.createBiquadFilter();
	hp.type = "highpass";
	hp.frequency.value = 700;
	shaper.connect(hp).connect(master);
	const voices = [[740, "square"], [744, "sawtooth"], [736, "sawtooth"], [742, "square"], [1480, "sawtooth"], [1485, "square"]];
	const blast = (at, len, droop) => {
		for (const [f, wave] of voices) {
			const osc = note({ wave, freq: f, vol: 0.16, len, a: 0.006, d: 0.03, s: 0.9, r: 0.06, at, dest: shaper, vibrato: { rate: 38, depth: 0.012, wave: "triangle" } });
			if (!osc) continue;
			const t = ctx.currentTime + at;
			osc.detune.setValueAtTime(-150, t);
			osc.detune.linearRampToValueAtTime(0, t + 0.04);
			if (droop) {
				osc.detune.setValueAtTime(0, t + 0.7);
				osc.detune.linearRampToValueAtTime(-700, t + len);
			}
		}
	};
	for (let i = 0; i < 3; i++) blast(i * 0.15, 0.1);
	blast(0.45, 1.1, true);
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
