// Flat-shaded 3D polyhedral dice: a port of charsheet/source/dice3d.lua.
import { fonts } from "./gfx.js";

const PHI = (1 + Math.sqrt(5)) / 2;
const { sqrt, cos, sin, acos, atan2, random, PI } = Math;

const norm = (x, y, z) => { const l = sqrt(x * x + y * y + z * z); return [x / l, y / l, z / l]; };
const cross = (ax, ay, az, bx, by, bz) => [ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx];

function qAxis(x, y, z, angle) {
	[x, y, z] = norm(x, y, z);
	const s = sin(angle / 2);
	return [cos(angle / 2), x * s, y * s, z * s];
}

const qMul = (a, b) => [
	a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
	a[0] * b[1] + a[1] * b[0] + a[2] * b[3] - a[3] * b[2],
	a[0] * b[2] - a[1] * b[3] + a[2] * b[0] + a[3] * b[1],
	a[0] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[0],
];

const qNormalize = (q) => { const l = Math.hypot(...q); return q.map((v) => v / l); };

function qMatrix([w, x, y, z]) {
	return [
		1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y),
		2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x),
		2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y),
	];
}

function qSlerp(a, b, t) {
	let d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
	if (d < 0) { b = b.map((v) => -v); d = -d; }
	if (d > 0.9995) return qNormalize(a.map((v, i) => v + (b[i] - v) * t));
	const th = acos(d), s = sin(th);
	const wa = sin((1 - t) * th) / s, wb = sin(t * th) / s;
	return a.map((v, i) => v * wa + b[i] * wb);
}

function qFaceToViewer(x, y, z) {
	if (z > 0.9999) return [1, 0, 0, 0];
	if (z < -0.9999) return qAxis(1, 0, 0, PI);
	const [ax, ay, az] = cross(x, y, z, 0, 0, 1);
	return qAxis(ax, ay, az, acos(z));
}

const randomAxis = () => norm(random() * 2 - 1, random() * 2 - 1, random() * 2 - 1 + 0.001);
const randomQuat = () => qAxis(...randomAxis(), random() * PI * 2);

// ------------------------------------------------------------ solids

function facesFromNormals(verts, normals) {
	return normals.map((n) => {
		const [nx, ny, nz] = norm(...n);
		let best = -Infinity;
		for (const v of verts) best = Math.max(best, v[0] * nx + v[1] * ny + v[2] * nz);
		const idx = [];
		verts.forEach((v, i) => { if (v[0] * nx + v[1] * ny + v[2] * nz > best - 1e-4) idx.push(i); });
		const [ux, uy, uz] = norm(...cross(nx, ny, nz, 0.3, 0.5, 0.81));
		const [wx, wy, wz] = cross(nx, ny, nz, ux, uy, uz);
		const ang = (v) => atan2(v[0] * wx + v[1] * wy + v[2] * wz, v[0] * ux + v[1] * uy + v[2] * uz);
		idx.sort((a, b) => ang(verts[a]) - ang(verts[b]));
		return { idx, n: [nx, ny, nz] };
	});
}

function faceNormal(verts, idx) {
	let nx = 0, ny = 0, nz = 0, cx = 0, cy = 0, cz = 0;
	idx.forEach((vi, i) => {
		const a = verts[vi], b = verts[idx[(i + 1) % idx.length]];
		nx += (a[1] - b[1]) * (a[2] + b[2]);
		ny += (a[2] - b[2]) * (a[0] + b[0]);
		nz += (a[0] - b[0]) * (a[1] + b[1]);
		cx += a[0]; cy += a[1]; cz += a[2];
	});
	[nx, ny, nz] = norm(nx, ny, nz);
	return nx * cx + ny * cy + nz * cz < 0 ? [-nx, -ny, -nz] : [nx, ny, nz];
}

function scaled(verts, s) {
	const maxR = Math.max(...verts.map((v) => Math.hypot(...v)));
	return verts.map((v) => v.map((x) => x / maxR * s));
}

const corners = () => {
	const v = [];
	for (const x of [-1, 1]) for (const y of [-1, 1]) for (const z of [-1, 1]) v.push([x, y, z]);
	return v;
};

function icosaVerts() {
	const v = [];
	for (const a of [-1, 1]) for (const b of [-PHI, PHI]) v.push([0, a, b], [a, b, 0], [b, 0, a]);
	return v;
}

function dodecaVerts() {
	const v = corners();
	const ip = 1 / PHI;
	for (const a of [-ip, ip]) for (const b of [-PHI, PHI]) v.push([0, b, a], [b, a, 0], [a, 0, b]);
	return v;
}

function trapezohedron() {
	const a = 0.1, h = 0.9472136;
	let v = [[0, 0, h], [0, 0, -h]];
	for (let k = 0; k < 5; k++) {
		const t = k * 2 * PI / 5;
		v.push([cos(t), sin(t), a], [cos(t + PI / 5), sin(t + PI / 5), -a]);
	}
	const faces = [];
	for (let k = 0; k < 5; k++) {
		const u0 = 2 + 2 * k, l0 = 3 + 2 * k;
		const u1 = 2 + 2 * ((k + 1) % 5), l1 = 3 + 2 * ((k + 1) % 5);
		faces.push([0, u0, l0, u1], [1, l0, u1, l1]);
	}
	for (const p of v) p[2] *= 1.25;
	v = scaled(v, 1.1);
	return [v, faces.map((idx) => ({ idx, n: faceNormal(v, idx) }))];
}

const solids = {};

function solidFor(sides) {
	if (sides === 100) sides = 10;
	if (solids[sides]) return solids[sides];
	let verts, faces;
	if (sides === 4) {
		const t = [[1, 1, 1], [1, -1, -1], [-1, 1, -1], [-1, -1, 1]];
		verts = scaled(t, 1.15);
		faces = facesFromNormals(verts, t.map((p) => p.map((x) => -x)));
	} else if (sides === 6) {
		verts = scaled(corners(), 1.05);
		faces = facesFromNormals(verts, [[0, 0, 1], [1, 0, 0], [0, 1, 0], [0, -1, 0], [-1, 0, 0], [0, 0, -1]]);
	} else if (sides === 8) {
		verts = scaled([[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]], 1.05);
		faces = facesFromNormals(verts, corners());
	} else if (sides === 10) {
		[verts, faces] = trapezohedron();
	} else if (sides === 12) {
		verts = scaled(dodecaVerts(), 1.0);
		faces = facesFromNormals(verts, icosaVerts());
	} else {
		verts = scaled(icosaVerts(), 1.0);
		faces = facesFromNormals(verts, dodecaVerts());
	}
	solids[sides] = { verts, faces };
	return solids[sides];
}

// ------------------------------------------------------------ bodies

const REST_TILT = qMul(qAxis(1, 0, 0, -0.42), qAxis(0, 1, 0, 0.32));
const REST_TILT_D4 = qMul(qAxis(1, 0, 0, -0.7), qAxis(0, 1, 0, 0.5));
const [LX, LY, LZ] = norm(-0.45, 0.65, 0.75);

function faceIndexFor(sides, value) {
	if (typeof value !== "number") return 0;
	if (sides === 100) return (value - 1) % 10;
	return value - 1;
}

function restingQuat(sides, value) {
	const solid = solidFor(sides);
	const face = solid.faces[faceIndexFor(sides, value)] || solid.faces[0];
	return qMul(sides === 4 ? REST_TILT_D4 : REST_TILT, qFaceToViewer(...face.n));
}

export function newBody(sides, value) {
	return { sides, q: value ? restingQuat(sides, value) : randomQuat(), axis: randomAxis(), speed: 0 };
}

export function spin(body, amount) {
	if (random() < 0.3) body.axis = randomAxis();
	body.speed = Math.min(0.9, body.speed + amount);
}

export function update(body) {
	if (body.landing) {
		body.landT = Math.min(1, body.landT + 0.16);
		const t = 1 - (1 - body.landT) ** 3;
		body.q = qSlerp(body.landFrom, body.landTo, t);
		if (body.landT >= 1) body.landing = false;
		return;
	}
	if (body.speed > 0.001) {
		body.q = qNormalize(qMul(qAxis(...body.axis, body.speed), body.q));
		body.speed *= 0.9;
	}
}

export function land(body, value) {
	Object.assign(body, { landing: true, landT: 0, landFrom: body.q, landTo: restingQuat(body.sides, value), speed: 0 });
}

export const isSettled = (body) => !body.landing;

// ------------------------------------------------------------ tray physics
// Bodies with a position (x, y, r in screen pixels) slide around a box,
// bouncing off its walls and each other and rolling the way they travel.

const WALL_BOUNCE = 0.75;
const ROLL_DRAG = 0.95;
const LAND_DRAG = 0.7;
const MAX_SPEED = 9;
const TOSS = 15; // pixels per frame per unit of spin

export function place(body, x, y, r) {
	Object.assign(body, { x, y, r, vx: 0, vy: 0 });
}

// Shoves a placed body; `amount` uses the same scale as spin().
// A moving die is pushed along (with a wobble) so it keeps bouncing.
export function toss(body, amount) {
	if (body.x == null) return;
	const v = amount * TOSS;
	const a = body.vx * body.vx + body.vy * body.vy > 0.25
		? atan2(body.vy, body.vx) + (random() - 0.5) * 1.2
		: random() * 2 * PI;
	body.vx += cos(a) * v;
	body.vy += sin(a) * v;
}

function clampToBox(b, left, top, right, bottom) {
	let hit = false;
	if (b.x < left + b.r) [b.x, b.vx, hit] = [left + b.r, Math.abs(b.vx) * WALL_BOUNCE, true];
	else if (b.x > right - b.r) [b.x, b.vx, hit] = [right - b.r, -Math.abs(b.vx) * WALL_BOUNCE, true];
	if (b.y < top + b.r) [b.y, b.vy, hit] = [top + b.r, Math.abs(b.vy) * WALL_BOUNCE, true];
	else if (b.y > bottom - b.r) [b.y, b.vy, hit] = [bottom - b.r, -Math.abs(b.vy) * WALL_BOUNCE, true];
	return hit;
}

// Moves every placed body one frame inside the box. Returns true if any die
// hit a wall or another die hard enough to hear.
export function step(bodies, left, top, right, bottom) {
	let clack = false;
	for (const b of bodies) {
		if (b.x == null) continue;
		const drag = b.landing ? LAND_DRAG : ROLL_DRAG;
		b.vx *= drag;
		b.vy *= drag;
		let s = sqrt(b.vx * b.vx + b.vy * b.vy);
		if (s > MAX_SPEED) {
			b.vx *= MAX_SPEED / s;
			b.vy *= MAX_SPEED / s;
			s = MAX_SPEED;
		}
		b.x += b.vx;
		b.y += b.vy;
		if (clampToBox(b, left, top, right, bottom) && s > 2) clack = true;
		if (s > 0.3 && !b.landing) {
			// roll toward the direction of travel (screen y points down)
			b.axis = norm(b.vy, b.vx, 0);
			b.speed = Math.max(b.speed, Math.min(0.9, s / b.r));
		}
	}
	for (let i = 0; i < bodies.length; i++) {
		const a = bodies[i];
		for (let j = i + 1; j < bodies.length; j++) {
			const b = bodies[j];
			if (a.x == null || b.x == null) continue;
			const dx = b.x - a.x, dy = b.y - a.y;
			const min = a.r + b.r;
			const d2 = dx * dx + dy * dy;
			if (d2 >= min * min) continue;
			const d = sqrt(d2);
			let nx, ny;
			if (d < 0.01) {
				const ang = random() * 2 * PI;
				[nx, ny] = [cos(ang), sin(ang)];
			} else {
				[nx, ny] = [dx / d, dy / d];
			}
			const push = (min - d) / 2;
			a.x -= nx * push;
			a.y -= ny * push;
			b.x += nx * push;
			b.y += ny * push;
			const rel = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
			if (rel < 0) {
				const imp = -rel * (1 + WALL_BOUNCE) / 2;
				a.vx -= imp * nx;
				a.vy -= imp * ny;
				b.vx += imp * nx;
				b.vy += imp * ny;
				if (-rel > 2) clack = true;
			}
		}
	}
	for (const b of bodies) if (b.x != null) clampToBox(b, left, top, right, bottom);
	return clack;
}

// ------------------------------------------------------------ drawing

// style: "normal" | "dropped" | "hot"
export function draw(g, body, cx, cy, r, label, style) {
	const solid = solidFor(body.sides);
	const m = qMatrix(body.q);
	const px = [], py = [];
	for (const v of solid.verts) {
		px.push(cx + (m[0] * v[0] + m[1] * v[1] + m[2] * v[2]) * r);
		py.push(cy - (m[3] * v[0] + m[4] * v[1] + m[5] * v[2]) * r);
	}

	let frontFace = null, frontZ = -1;
	const visible = [];
	for (const f of solid.faces) {
		const n = f.n;
		const nz = m[6] * n[0] + m[7] * n[1] + m[8] * n[2];
		if (nz > 0.01) {
			const nx = m[0] * n[0] + m[1] * n[1] + m[2] * n[2];
			const ny = m[3] * n[0] + m[4] * n[1] + m[5] * n[2];
			visible.push({ f, light: nx * LX + ny * LY + nz * LZ });
			if (nz > frontZ) { frontFace = f; frontZ = nz; }
		}
	}

	for (const vf of visible) {
		const pts = [];
		for (const vi of vf.f.idx) pts.push(px[vi], py[vi]);
		const isFront = vf.f === frontFace && label != null;
		g.setColor("white");
		g.fillPolygon(pts);
		g.setColor("black");
		if (style === "hot") {
			if (!isFront) g.setDither(0.2 + 0.4 * Math.max(0, vf.light));
			g.fillPolygon(pts);
		} else if (!isFront) {
			let lightness = 0.35 + 0.6 * Math.max(0, vf.light);
			if (style === "dropped") lightness = 0.75 + 0.25 * lightness;
			g.setDither(lightness);
			g.fillPolygon(pts);
		}
		g.setColor("black");
		if (style === "dropped") g.setDither(0.5, "bayer2");
		g.drawPolygon(pts);
		g.setColor("black");
	}

	if (label != null && frontFace) {
		let fx = 0, fy = 0;
		for (const vi of frontFace.idx) { fx += px[vi]; fy += py[vi]; }
		fx /= frontFace.idx.length;
		fy /= frontFace.idx.length;
		const s = String(label);
		const f = fonts.small;
		g.text(f, s, Math.floor(fx - g.textW(f, s) / 2), Math.floor(fy - f.height / 2), undefined, style === "hot" ? "white" : "copy");
	}

	if (style === "dropped") g.line(cx - r * 0.6, cy + r * 0.6, cx + r * 0.6, cy - r * 0.6, 2);
}
