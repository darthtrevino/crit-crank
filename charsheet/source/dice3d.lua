-- Flat-shaded 3D polyhedral dice.
--
-- Each die is a convex solid rotated by a quaternion and drawn with an
-- orthographic projection. Back faces are culled (enough for convex shapes),
-- and visible faces get a dither shade based on a fixed light direction.
-- The viewer looks down -z, so a face is visible when its rotated normal has z > 0.

local gfx <const> = playdate.graphics
local geo <const> = playdate.geometry
local sqrt, cos, sin, acos, atan = math.sqrt, math.cos, math.sin, math.acos, math.atan
local PHI <const> = (1 + sqrt(5)) / 2

Dice3D = {}

---------------------------------------------------------------- vectors & quaternions

local function norm(x, y, z)
	local l = sqrt(x * x + y * y + z * z)
	return x / l, y / l, z / l
end

local function cross(ax, ay, az, bx, by, bz)
	return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function qAxis(x, y, z, angle)
	x, y, z = norm(x, y, z)
	local s = sin(angle / 2)
	return { cos(angle / 2), x * s, y * s, z * s }
end

local function qMul(a, b)
	return {
		a[1] * b[1] - a[2] * b[2] - a[3] * b[3] - a[4] * b[4],
		a[1] * b[2] + a[2] * b[1] + a[3] * b[4] - a[4] * b[3],
		a[1] * b[3] - a[2] * b[4] + a[3] * b[1] + a[4] * b[2],
		a[1] * b[4] + a[2] * b[3] - a[3] * b[2] + a[4] * b[1],
	}
end

local function qNormalize(q)
	local l = sqrt(q[1] * q[1] + q[2] * q[2] + q[3] * q[3] + q[4] * q[4])
	return { q[1] / l, q[2] / l, q[3] / l, q[4] / l }
end

-- Returns the 3x3 rotation matrix (row-major) for quaternion q.
local function qMatrix(q)
	local w, x, y, z = q[1], q[2], q[3], q[4]
	return {
		1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y),
		2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x),
		2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y),
	}
end

local function qSlerp(a, b, t)
	local d = a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
	if d < 0 then
		b = { -b[1], -b[2], -b[3], -b[4] }
		d = -d
	end
	if d > 0.9995 then
		return qNormalize({
			a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
			a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t,
		})
	end
	local th = acos(d)
	local s = sin(th)
	local wa, wb = sin((1 - t) * th) / s, sin(t * th) / s
	return {
		a[1] * wa + b[1] * wb, a[2] * wa + b[2] * wb,
		a[3] * wa + b[3] * wb, a[4] * wa + b[4] * wb,
	}
end

-- Quaternion rotating unit vector (x, y, z) onto +z (towards the viewer).
local function qFaceToViewer(x, y, z)
	local d = z
	if d > 0.9999 then return { 1, 0, 0, 0 } end
	if d < -0.9999 then return qAxis(1, 0, 0, math.pi) end
	local ax, ay, az = cross(x, y, z, 0, 0, 1)
	return qAxis(ax, ay, az, acos(d))
end

local function randomAxis()
	return norm(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1 + 0.001)
end

local function randomQuat()
	local x, y, z = randomAxis()
	return qAxis(x, y, z, math.random() * math.pi * 2)
end

---------------------------------------------------------------- solids

-- Builds faces for a convex solid: for each face direction, pick the vertices
-- furthest along it and order them around the face.
local function facesFromNormals(verts, normals)
	local faces = {}
	for _, n in ipairs(normals) do
		local nx, ny, nz = norm(n[1], n[2], n[3])
		local best = -math.huge
		for _, v in ipairs(verts) do
			best = math.max(best, v[1] * nx + v[2] * ny + v[3] * nz)
		end
		local idx = {}
		for i, v in ipairs(verts) do
			if v[1] * nx + v[2] * ny + v[3] * nz > best - 1e-4 then idx[#idx + 1] = i end
		end
		-- order vertices by angle around the normal
		local ux, uy, uz = cross(nx, ny, nz, 0.3, 0.5, 0.81)
		ux, uy, uz = norm(ux, uy, uz)
		local wx, wy, wz = cross(nx, ny, nz, ux, uy, uz)
		table.sort(idx, function(a, b)
			local va, vb = verts[a], verts[b]
			local aa = atan(va[1] * wx + va[2] * wy + va[3] * wz, va[1] * ux + va[2] * uy + va[3] * uz)
			local ab = atan(vb[1] * wx + vb[2] * wy + vb[3] * wz, vb[1] * ux + vb[2] * uy + vb[3] * uz)
			return aa < ab
		end)
		faces[#faces + 1] = { idx = idx, n = { nx, ny, nz } }
	end
	return faces
end

local function faceNormal(verts, idx)
	-- Newell's method; flipped outward using the face centroid.
	local nx, ny, nz, cx, cy, cz = 0, 0, 0, 0, 0, 0
	for i = 1, #idx do
		local a, b = verts[idx[i]], verts[idx[i % #idx + 1]]
		nx += (a[2] - b[2]) * (a[3] + b[3])
		ny += (a[3] - b[3]) * (a[1] + b[1])
		nz += (a[1] - b[1]) * (a[2] + b[2])
		cx += a[1]; cy += a[2]; cz += a[3]
	end
	nx, ny, nz = norm(nx, ny, nz)
	if nx * cx + ny * cy + nz * cz < 0 then nx, ny, nz = -nx, -ny, -nz end
	return { nx, ny, nz }
end

local function scaled(verts, s)
	local maxR = 0
	for _, v in ipairs(verts) do
		maxR = math.max(maxR, sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]))
	end
	local out = {}
	for i, v in ipairs(verts) do
		out[i] = { v[1] / maxR * s, v[2] / maxR * s, v[3] / maxR * s }
	end
	return out
end

local function tetrahedron()
	local v = { { 1, 1, 1 }, { 1, -1, -1 }, { -1, 1, -1 }, { -1, -1, 1 } }
	local n = {}
	for i, p in ipairs(v) do n[i] = { -p[1], -p[2], -p[3] } end
	return scaled(v, 1.15), n
end

local function cube()
	local v = {}
	for _, x in ipairs({ -1, 1 }) do
		for _, y in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do v[#v + 1] = { x, y, z } end
		end
	end
	local n = { { 0, 0, 1 }, { 1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { -1, 0, 0 }, { 0, 0, -1 } }
	return scaled(v, 1.05), n
end

local function octahedron()
	local v = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
	local n = {}
	for _, x in ipairs({ -1, 1 }) do
		for _, y in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do n[#n + 1] = { x, y, z } end
		end
	end
	return scaled(v, 1.05), n
end

local function icosaVerts()
	local v = {}
	for _, a in ipairs({ -1, 1 }) do
		for _, b in ipairs({ -PHI, PHI }) do
			v[#v + 1] = { 0, a, b }
			v[#v + 1] = { a, b, 0 }
			v[#v + 1] = { b, 0, a }
		end
	end
	return v
end

local function dodecaVerts()
	local v = {}
	for _, x in ipairs({ -1, 1 }) do
		for _, y in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do v[#v + 1] = { x, y, z } end
		end
	end
	local ip = 1 / PHI
	for _, a in ipairs({ -ip, ip }) do
		for _, b in ipairs({ -PHI, PHI }) do
			-- (0, ±φ, ±1/φ) cyclic: oriented to be the dual of icosaVerts()
			v[#v + 1] = { 0, b, a }
			v[#v + 1] = { b, a, 0 }
			v[#v + 1] = { a, 0, b }
		end
	end
	return v
end

-- Pentagonal trapezohedron (d10): two apexes and two offset rings of 5.
local function trapezohedron()
	local a, h = 0.1, 0.9472136
	local v = { { 0, 0, h }, { 0, 0, -h } }
	for k = 0, 4 do
		local t = k * 2 * math.pi / 5
		v[#v + 1] = { cos(t), sin(t), a }
		v[#v + 1] = { cos(t + math.pi / 5), sin(t + math.pi / 5), -a }
	end
	local faces = {}
	for k = 0, 4 do
		local u0, l0 = 3 + 2 * k, 4 + 2 * k
		local u1, l1 = 3 + 2 * ((k + 1) % 5), 4 + 2 * ((k + 1) % 5)
		faces[#faces + 1] = { 1, u0, l0, u1 }
		faces[#faces + 1] = { 2, l0, u1, l1 }
	end
	-- stretch along the apex axis so it reads as a d10
	for _, p in ipairs(v) do p[3] *= 1.25 end
	v = scaled(v, 1.1)
	local out = {}
	for i, idx in ipairs(faces) do out[i] = { idx = idx, n = faceNormal(v, idx) } end
	return v, out
end

local solids = {}

local function solidFor(sides)
	if sides == 100 then sides = 10 end
	if solids[sides] then return solids[sides] end
	local verts, faces
	if sides == 4 then
		local v, n = tetrahedron()
		verts, faces = v, facesFromNormals(v, n)
	elseif sides == 6 then
		local v, n = cube()
		verts, faces = v, facesFromNormals(v, n)
	elseif sides == 8 then
		local v, n = octahedron()
		verts, faces = v, facesFromNormals(v, n)
	elseif sides == 10 then
		verts, faces = trapezohedron()
	elseif sides == 12 then
		verts = scaled(dodecaVerts(), 1.0)
		faces = facesFromNormals(verts, icosaVerts())
	else
		verts = scaled(icosaVerts(), 1.0)
		faces = facesFromNormals(verts, dodecaVerts())
	end
	-- reach: the farthest vertex, so r * reach bounds the drawn silhouette
	local reach = 0
	for _, v in ipairs(verts) do reach = math.max(reach, sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])) end
	solids[sides] = { verts = verts, faces = faces, reach = reach }
	return solids[sides]
end

-- Warm the cache so the first roll doesn't stall.
for _, s in ipairs({ 4, 6, 8, 10, 12, 20 }) do solidFor(s) end

---------------------------------------------------------------- bodies

-- A slight tilt applied to resting dice so they read as 3D rather than flat.
local REST_TILT = qMul(qAxis(1, 0, 0, -0.42), qAxis(0, 1, 0, 0.32))
-- A tetrahedron's side faces sit at a steep angle, so it needs more tilt to show them.
local REST_TILT_D4 = qMul(qAxis(1, 0, 0, -0.7), qAxis(0, 1, 0, 0.5))

local LX, LY, LZ = norm(-0.45, 0.65, 0.75)

local function faceIndexFor(sides, value)
	if type(value) ~= "number" then return 1 end
	if sides == 100 then return ((value - 1) % 10) + 1 end
	return value
end

local function restingQuat(sides, value)
	local solid = solidFor(sides)
	local face = solid.faces[faceIndexFor(sides, value)] or solid.faces[1]
	local tilt = (sides == 4) and REST_TILT_D4 or REST_TILT
	return qMul(tilt, qFaceToViewer(face.n[1], face.n[2], face.n[3]))
end

function Dice3D.newBody(sides, value)
	return {
		sides = sides,
		q = value and restingQuat(sides, value) or randomQuat(),
		axis = { randomAxis() },
		speed = 0,
	}
end

-- Adds spin; `amount` is roughly radians per frame.
function Dice3D.spin(body, amount)
	if math.random() < 0.3 then body.axis = { randomAxis() } end
	body.speed = math.min(0.9, body.speed + amount)
end

function Dice3D.update(body)
	if body.landing then
		body.landT = math.min(1, body.landT + 0.16)
		local t = 1 - (1 - body.landT) ^ 3
		body.q = qSlerp(body.landFrom, body.landTo, t)
		if body.landT >= 1 then body.landing = false end
		return
	end
	if body.speed > 0.001 then
		local a = body.axis
		body.q = qNormalize(qMul(qAxis(a[1], a[2], a[3], body.speed), body.q))
		body.speed *= 0.9
	end
end

function Dice3D.land(body, value)
	body.landing = true
	body.landT = 0
	body.landFrom = body.q
	body.landTo = restingQuat(body.sides, value)
	body.speed = 0
end

function Dice3D.isSettled(body)
	return not body.landing
end

---------------------------------------------------------------- tray physics
-- Bodies with a position (x, y, r in screen pixels) slide around a box,
-- bouncing off its walls and each other and rolling the way they travel.

local WALL_BOUNCE <const> = 0.75
local ROLL_DRAG <const> = 0.95
local LAND_DRAG <const> = 0.7
local MAX_SPEED <const> = 9
local TOSS <const> = 15 -- pixels per frame per unit of spin

function Dice3D.place(body, x, y, r)
	body.x, body.y, body.r = x, y, r
	body.vx, body.vy = 0, 0
end

-- Shoves a placed body; `amount` uses the same scale as Dice3D.spin.
-- A moving die is pushed along (with a wobble) so it keeps bouncing.
function Dice3D.toss(body, amount)
	if not body.x then return end
	local v = amount * TOSS
	local a
	if body.vx * body.vx + body.vy * body.vy > 0.25 then
		a = atan(body.vy, body.vx) + (math.random() - 0.5) * 1.2
	else
		a = math.random() * 2 * math.pi
	end
	body.vx += cos(a) * v
	body.vy += sin(a) * v
end

-- Collision radius: the draw scale times the solid's farthest vertex.
local function reach(b)
	return b.r * solidFor(b.sides).reach
end

local function clampToBox(b, left, top, right, bottom)
	local hit = false
	local r = reach(b)
	if b.x < left + r then
		b.x, b.vx, hit = left + r, math.abs(b.vx) * WALL_BOUNCE, true
	elseif b.x > right - r then
		b.x, b.vx, hit = right - r, -math.abs(b.vx) * WALL_BOUNCE, true
	end
	if b.y < top + r then
		b.y, b.vy, hit = top + r, math.abs(b.vy) * WALL_BOUNCE, true
	elseif b.y > bottom - r then
		b.y, b.vy, hit = bottom - r, -math.abs(b.vy) * WALL_BOUNCE, true
	end
	return hit
end

-- Moves every placed body one frame inside the box. Returns true if any die
-- hit a wall or another die hard enough to hear.
function Dice3D.step(bodies, left, top, right, bottom)
	local clack = false
	for _, b in ipairs(bodies) do
		if b.x then
			local drag = b.landing and LAND_DRAG or ROLL_DRAG
			b.vx *= drag
			b.vy *= drag
			local s = sqrt(b.vx * b.vx + b.vy * b.vy)
			if s > MAX_SPEED then
				b.vx, b.vy, s = b.vx * MAX_SPEED / s, b.vy * MAX_SPEED / s, MAX_SPEED
			end
			b.x += b.vx
			b.y += b.vy
			if clampToBox(b, left, top, right, bottom) and s > 2 then clack = true end
			if s > 0.3 and not b.landing then
				-- roll toward the direction of travel (screen y points down)
				b.axis = { norm(b.vy, b.vx, 0) }
				b.speed = math.max(b.speed, math.min(0.9, s / b.r))
			end
		end
	end
	-- a few passes so crowded dice fully separate
	for _ = 1, 3 do
		for i = 1, #bodies do
			local a = bodies[i]
			for j = i + 1, #bodies do
				local b = bodies[j]
				if a.x and b.x then
					local dx, dy = b.x - a.x, b.y - a.y
					local min = reach(a) + reach(b)
					local d2 = dx * dx + dy * dy
					if d2 < min * min then
						local d = sqrt(d2)
						local nx, ny
						if d < 0.01 then
							local ang = math.random() * 2 * math.pi
							nx, ny = cos(ang), sin(ang)
						else
							nx, ny = dx / d, dy / d
						end
						local push = (min - d) / 2
						a.x -= nx * push
						a.y -= ny * push
						b.x += nx * push
						b.y += ny * push
						local rel = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
						if rel < 0 then
							local j2 = -rel * (1 + WALL_BOUNCE) / 2
							a.vx -= j2 * nx
							a.vy -= j2 * ny
							b.vx += j2 * nx
							b.vy += j2 * ny
							if -rel > 2 then clack = true end
						end
					end
				end
			end
		end
		for _, b in ipairs(bodies) do
			if b.x then clampToBox(b, left, top, right, bottom) end
		end
	end
	return clack
end

---------------------------------------------------------------- drawing

local function drawLabel(font, s, x, y)
	gfx.setFont(font)
	local w = font:getTextWidth(s)
	gfx.drawText(s, math.floor(x - w / 2), math.floor(y - font:getHeight() / 2))
end

-- style: "normal" | "dropped" | "hot"
function Dice3D.draw(body, cx, cy, r, label, style, font)
	local solid = solidFor(body.sides)
	local m = qMatrix(body.q)
	local px, py = {}, {}
	for i, v in ipairs(solid.verts) do
		local x = m[1] * v[1] + m[2] * v[2] + m[3] * v[3]
		local y = m[4] * v[1] + m[5] * v[2] + m[6] * v[3]
		px[i] = cx + x * r
		py[i] = cy - y * r
	end

	local frontFace, frontZ = nil, -1
	local visible = {}
	for _, f in ipairs(solid.faces) do
		local n = f.n
		local nz = m[7] * n[1] + m[8] * n[2] + m[9] * n[3]
		if nz > 0.01 then
			local nx = m[1] * n[1] + m[2] * n[2] + m[3] * n[3]
			local ny = m[4] * n[1] + m[5] * n[2] + m[6] * n[3]
			visible[#visible + 1] = { f = f, light = nx * LX + ny * LY + nz * LZ }
			if nz > frontZ then frontFace, frontZ = f, nz end
		end
	end

	gfx.setLineWidth(1)
	for _, vf in ipairs(visible) do
		local idx = vf.f.idx
		local pts = {}
		for k, vi in ipairs(idx) do
			pts[2 * k - 1] = px[vi]
			pts[2 * k] = py[vi]
		end
		local poly = geo.polygon.new(table.unpack(pts))
		poly:close()
		local isFront = vf.f == frontFace and label ~= nil
		gfx.setColor(gfx.kColorWhite)
		gfx.fillPolygon(poly)
		if style == "hot" then
			gfx.setColor(gfx.kColorBlack)
			if not isFront then
				gfx.setDitherPattern(0.2 + 0.4 * math.max(0, vf.light), gfx.image.kDitherTypeBayer4x4)
			end
			gfx.fillPolygon(poly)
		elseif not isFront then
			-- black dither; alpha closer to 1 = lighter
			local lightness = 0.35 + 0.6 * math.max(0, vf.light)
			if style == "dropped" then lightness = 0.75 + 0.25 * lightness end
			gfx.setColor(gfx.kColorBlack)
			gfx.setDitherPattern(lightness, gfx.image.kDitherTypeBayer4x4)
			gfx.fillPolygon(poly)
		end
		gfx.setColor(gfx.kColorBlack)
		if style == "dropped" then
			gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
		end
		gfx.drawPolygon(poly)
		gfx.setColor(gfx.kColorBlack)
	end

	if label and frontFace then
		local fx, fy = 0, 0
		for _, vi in ipairs(frontFace.idx) do
			fx += px[vi]
			fy += py[vi]
		end
		fx /= #frontFace.idx
		fy /= #frontFace.idx
		if style == "hot" then gfx.setImageDrawMode(gfx.kDrawModeFillWhite) end
		drawLabel(font, tostring(label), fx, fy)
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
	end

	if style == "dropped" then
		gfx.setLineWidth(2)
		gfx.drawLine(cx - r * 0.6, cy + r * 0.6, cx + r * 0.6, cy - r * 0.6)
		gfx.setLineWidth(1)
	end
end
