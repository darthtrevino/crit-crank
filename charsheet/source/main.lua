-- charsheet: a D&D character sheet with crank-powered dice.

import "CoreLibs/graphics"
import "CoreLibs/timer"

import "dice"
import "dice3d"
import "characters"
import "resources"
import "importer"
import "sheet"
import "rules"
import "ui"

local pd <const> = playdate
local gfx <const> = pd.graphics

-- Crank tuning (degrees / frames)
local CRANK_START = 30   -- rotation needed to pick up the dice
local CRANK_TICK = 40    -- rotation per face change while tumbling
local SETTLE_FRAMES = 8  -- frames of stillness before the dice land
local AUTO_FRAMES = 16   -- length of the Ⓐ-button quick roll
local CRANK_ADJUST = 20  -- rotation per ±1 on a resource row
local TOAST_FRAMES = 75
local POOL_MAX_DICE = 12
local POOL_BONUS = 20    -- modifier range is ±POOL_BONUS
local REST_CRANK = 720   -- rotation needed to confirm a rest
local REST_STEP = 90     -- rotation per progress tick sound
local REST_DECAY = 30    -- progress lost per frame once the crank stops
local REST_RELOCK = 15   -- still frames needed before another rest can start

math.randomseed(pd.getSecondsSinceEpoch())
pd.display.setRefreshRate(30)

local state = {
	charIndex = 1,
	pages = nil,
	page = 1,
	sel = {},       -- selected row per page
	scroll = {},    -- scroll offset per page
	mode = "normal", -- d20 mode: normal | adv | dis
	critPending = false,
	roll = nil,
	preview = nil,  -- resting 3D dice for the selected row
	res = nil,      -- tracked resources for the current character
	allRes = {},    -- saved resources per character key
	allView = {},   -- saved page, selection, d20 mode, crit, last cast and pool per character key
	lastCast = nil, -- actionKey of the last action that spent a resource
	toast = nil,
	toastFrames = 0,
	dirty = false,
	pool = {},      -- custom dice pool: d4..d20 counts and bonus
	rest = nil,     -- crank progress on a rest row: { row, progress, idle, done }
}

-- restLock: set after a rest; cleared once the crank is still for REST_RELOCK
-- frames. Lives here, not on the rest row, so changing rows can't skip it.
local crank = { windup = 0, tick = 0, idle = 0, adjust = 0, restLock = false, still = 0 }

---------------------------------------------------------------- sound

local tickSynth = pd.sound.synth.new(pd.sound.kWaveSquare)
tickSynth:setADSR(0, 0.02, 0, 0)
local landSynth = pd.sound.synth.new(pd.sound.kWaveTriangle)
landSynth:setADSR(0, 0.15, 0.2, 0.2)

local function playTick()
	tickSynth:playNote(600 + math.random(0, 600), 0.12, 0.02)
end

local function playLand(result)
	if result.crit then
		landSynth:playNote(1047, 0.5, 0.4)
	elseif result.fumble then
		landSynth:playNote(131, 0.5, 0.4)
	else
		landSynth:playNote(523, 0.35, 0.1)
	end
end

-- DJ air horn for natural 20s: BRAP-BRAP-BRAP-BRAAAAP on F#5, matching the
-- web demo. Each blast is a plain square + saw + octave saw that fades out
-- exponentially; the long blast sags a semitone as it dies away.
local HORN_VOICES = {
	{ 740.0, pd.sound.kWaveSquare },
	{ 745.0, pd.sound.kWaveSawtooth },
	{ 1480.0, pd.sound.kWaveSawtooth },
}
local HORN_SAG = -1.07 -- half-steps; 0.94x the pitch
local hornSag = pd.sound.lfo.new(pd.sound.kLFOSine)
hornSag:setDepth(0)
local hornChannel = pd.sound.channel.new()
local function hornSet(len)
	local set = {}
	for i, def in ipairs(HORN_VOICES) do
		local v = pd.sound.synth.new(def[2])
		v:setADSR(0.02, len - 0.02, 0, 0.03)
		v:setEnvelopeCurvature(1)
		hornChannel:addSource(v)
		set[i] = v
	end
	return set
end
local hornShort, hornLong = hornSet(0.11), hornSet(0.9)
for _, v in ipairs(hornLong) do v:setFrequencyMod(hornSag) end

local function hornBlast(set, len)
	for i, v in ipairs(set) do v:playNote(HORN_VOICES[i][1], 0.15, len) end
end

local function playHorn()
	for i = 0, 2 do
		pd.timer.performAfterDelay(i * 150, function() hornBlast(hornShort, 0.11) end)
	end
	pd.timer.performAfterDelay(480, function()
		hornSag:setCenter(0)
		hornBlast(hornLong, 0.9)
		local t = pd.timer.new(900, 0, HORN_SAG)
		t.updateCallback = function(timer) hornSag:setCenter(timer.value) end
	end)
end

-- Sad trombone for natural 1s: wah wah wah waaaaah, muted brass with a wobble.
local trombone = pd.sound.synth.new(pd.sound.kWaveSawtooth)
trombone:setADSR(0.04, 0.1, 0.8, 0.15)
local tromboneLFO = pd.sound.lfo.new(pd.sound.kLFOSine)
tromboneLFO:setRate(5.5)
tromboneLFO:setDepth(0)
trombone:setFrequencyMod(tromboneLFO)
local tromboneFilter = pd.sound.twopolefilter.new(pd.sound.kFilterLowPass)
tromboneFilter:setFrequency(1100)
tromboneFilter:setResonance(0.5)
local tromboneChannel = pd.sound.channel.new()
tromboneChannel:addEffect(tromboneFilter)
tromboneChannel:addSource(trombone)

local function playTrombone()
	local notes = { 233.1, 220.0, 207.7, 196.0 } -- Bb A Ab G
	for i, f in ipairs(notes) do
		local last = i == #notes
		pd.timer.performAfterDelay((i - 1) * 430, function()
			tromboneLFO:setDepth(last and 0.25 or 0)
			trombone:playNote(f, 0.45, last and 1.3 or 0.32)
		end)
	end
end

---------------------------------------------------------------- selection

local function currentPage()
	return state.pages[state.page]
end

local function isSelectable(row)
	return row and (row.kind == "roll" or row.kind == "resource" or row.kind == "counter" or row.kind == "rest")
end

local function firstSelectable(rows)
	for i, r in ipairs(rows) do
		if isSelectable(r) then return i end
	end
	return 1
end

local function ensureVisible(p)
	p = p or state.page
	local rows = state.pages[p].rows
	local sel = state.sel[p]
	local scroll = state.scroll[p] or 0
	-- keep the section header above the selection in view when possible
	local top = sel
	while top > 1 and not isSelectable(rows[top - 1]) and rows[top - 1].kind == "header" do
		top -= 1
	end
	if top - 1 < scroll then scroll = top - 1 end
	if sel > scroll + UI.VISIBLE_ROWS then scroll = sel - UI.VISIBLE_ROWS end
	-- show trailing info rows when we reach the last selectable row
	local last = sel
	while rows[last + 1] and not isSelectable(rows[last + 1]) and rows[last + 1].kind ~= "header" do
		last += 1
	end
	if last == #rows and last > scroll + UI.VISIBLE_ROWS then
		scroll = math.min(last - UI.VISIBLE_ROWS, sel - 1)
	end
	state.scroll[p] = math.max(0, scroll)
end

local function selectedRow()
	local row = currentPage().rows[state.sel[state.page]]
	if isSelectable(row) then return row end
	return nil
end

local function selectedRollRow()
	local row = selectedRow()
	if row and row.kind == "roll" then return row end
	return nil
end

---------------------------------------------------------------- resources

local function character()
	return Characters[state.charIndex]
end

local function toast(msg)
	state.toast = msg
	state.toastFrames = TOAST_FRAMES
end

local function getResource(key)
	return Resources.get(character(), state.res, key)
end

-- A row's identity across rebuilds, so selection survives the STATUS page changing.
local function rowId(row)
	return row and (row.kind .. ":" .. (row.key or row.actionKey or "") .. ":" .. (row.label or ""))
end

local refreshPool

-- Show or hide death save tracking when HP reaches or leaves 0.
local function syncDying()
	local dying = Resources.dying(state.res)
	if not dying then Resources.clearDeath(state.res) end
	if dying == state.dying then return end
	state.dying = dying
	local old = state.pages
	state.pages = Sheet.build(character(), dying)
	for p, page in ipairs(state.pages) do
		local was = old[p] and old[p].rows[state.sel[p]]
		local sel = firstSelectable(page.rows)
		for i, r in ipairs(page.rows) do
			if was and rowId(r) == rowId(was) then sel = i; break end
		end
		state.sel[p] = sel
		-- bring the new Dying section into view
		if dying and page.title == "STATUS" then state.scroll[p] = 0 end
		ensureVisible(p)
	end
	refreshPool()
end

local function adjustResource(key, delta)
	local before = state.res[key]
	local after = Resources.add(character(), state.res, key, delta)
	if after ~= before then
		state.dirty = true
		tickSynth:playNote(delta > 0 and 900 or 500, 0.1, 0.02)
		if key == "hp" then syncDying() end
	end
end

---------------------------------------------------------------- dice pool

local function getCounter(key)
	return state.pool[key] or 0
end

local function poolExpr()
	local parts = {}
	-- biggest dice first, like "2d6+1d4"
	for i = #Sheet.POOL_SIDES, 1, -1 do
		local s = Sheet.POOL_SIDES[i]
		local n = getCounter("d" .. s)
		if n > 0 then parts[#parts + 1] = n .. "d" .. s end
	end
	local expr = table.concat(parts, "+")
	local b = getCounter("bonus")
	if b ~= 0 then expr = expr .. Dice.signed(b) end
	return expr
end

local function poolDiceCount()
	local n = 0
	for _, s in ipairs(Sheet.POOL_SIDES) do n += getCounter("d" .. s) end
	return n
end

-- Push the pool into the "Roll pool" row.
function refreshPool()
	for _, page in ipairs(state.pages) do
		for _, row in ipairs(page.rows) do
			if row.pool then
				local expr = poolExpr()
				row.spec = Dice.parse(expr == "" and "0" or expr)
				if #row.spec.terms == 0 then
					row.value = "empty"
				else
					local f = Dice.format(row.spec)
					row.value = #f <= 11 and f or (poolDiceCount() .. " dice")
				end
			end
		end
	end
end

local function adjustCounter(key, delta)
	local cur = getCounter(key)
	local new
	if key == "bonus" then
		new = math.max(-POOL_BONUS, math.min(POOL_BONUS, cur + delta))
	else
		new = math.max(0, cur + delta)
		if delta > 0 and poolDiceCount() >= POOL_MAX_DICE then
			toast("Pool is full (" .. POOL_MAX_DICE .. " dice max)")
			return
		end
	end
	if new == cur then return end
	state.pool[key] = new
	state.dirty = true
	tickSynth:playNote(delta > 0 and 900 or 500, 0.1, 0.02)
	refreshPool()
end

local function clearPool()
	state.pool = {}
	state.dirty = true
	refreshPool()
	toast("Pool cleared")
end

local function adjustRow(row, delta)
	if row.kind == "counter" then
		adjustCounter(row.key, delta)
	else
		adjustResource(row.key, delta)
	end
end

-- Selection is stored by page title and row identity so it survives sheet changes.
local function captureView()
	local v = {
		page = state.pages[state.page].title, sel = {}, scroll = {}, mode = state.mode,
		critPending = state.critPending, lastCast = state.lastCast, pool = state.pool,
	}
	for p, page in ipairs(state.pages) do
		v.sel[page.title] = rowId(page.rows[state.sel[p]])
		v.scroll[page.title] = state.scroll[p]
	end
	return v
end

local function cleanPool(pool)
	local clean = {}
	if type(pool) == "table" then
		for k, n in pairs(pool) do
			if type(k) == "string" and type(n) == "number" then clean[k] = math.floor(n) end
		end
	end
	return clean
end

local function restoreView(v)
	v = type(v) == "table" and v or {}
	local sel = type(v.sel) == "table" and v.sel or {}
	local scroll = type(v.scroll) == "table" and v.scroll or {}
	state.page = 1
	state.sel, state.scroll = {}, {}
	for p, page in ipairs(state.pages) do
		state.sel[p] = firstSelectable(page.rows)
		for i, r in ipairs(page.rows) do
			if isSelectable(r) and rowId(r) == sel[page.title] then
				state.sel[p] = i
				break
			end
		end
		state.scroll[p] = math.max(0, math.floor(tonumber(scroll[page.title]) or 0))
		ensureVisible(p)
		if page.title == v.page then state.page = p end
	end
	state.mode = (v.mode == "adv" or v.mode == "dis") and v.mode or "normal"
	state.critPending = v.critPending == true
	state.lastCast = type(v.lastCast) == "string" and v.lastCast or nil
	state.pool = cleanPool(v.pool)
end

local function loadCharacter(i)
	if state.res then
		state.allRes[character().key] = state.res
		state.allView[character().key] = captureView()
	end
	state.charIndex = i
	local key = Characters[i].key
	state.res = Resources.load(Characters[i], state.allRes[key])
	state.allRes[key] = state.res
	state.dying = Resources.dying(state.res)
	state.pages = Sheet.build(Characters[i], state.dying)
	restoreView(state.allView[key])
	refreshPool()
	state.roll = nil
	state.rest = nil
end

local function diceMoving()
	return state.roll ~= nil and state.roll.phase ~= "done"
end

local function moveSel(dir)
	if diceMoving() then return end
	local rows = currentPage().rows
	local i = state.sel[state.page]
	repeat
		i += dir
	until i < 1 or i > #rows or isSelectable(rows[i])
	if i >= 1 and i <= #rows then
		state.sel[state.page] = i
		state.roll = nil
		state.rest = nil
		ensureVisible()
	end
end

local function changePage(dir)
	if diceMoving() then return end
	state.page = ((state.page - 1 + dir) % #state.pages) + 1
	state.roll = nil
	state.rest = nil
	ensureVisible()
end

---------------------------------------------------------------- rests

local takeRest -- defined with the persistence code below

-- Cranking on a rest row fills a bar; a full bar takes the rest. Stopping
-- drains it, and after a rest the crank must rest a moment before another.
local function updateRest(row, amount)
	local r = state.rest
	if not r or r.row ~= row then
		r = { row = row, progress = 0, idle = 0 }
		state.rest = r
	end
	if amount <= 0.5 then
		r.idle += 1
		if r.idle > SETTLE_FRAMES then r.progress = math.max(0, r.progress - REST_DECAY) end
		return
	end
	r.idle = 0
	if crank.restLock then return end
	r.done = false
	local before = r.progress
	r.progress = math.min(REST_CRANK, r.progress + amount)
	if math.floor(before / REST_STEP) ~= math.floor(r.progress / REST_STEP) then
		tickSynth:playNote(400 + 600 * r.progress / REST_CRANK, 0.12, 0.03)
	end
	if r.progress >= REST_CRANK then
		r.progress, r.done = 0, true
		crank.restLock, crank.still = true, 0
		takeRest(row.key)
		landSynth:playNote(784, 0.4, 0.3)
	end
end

---------------------------------------------------------------- rolling

local function effectiveSpec(row)
	local spec = row.spec
	local crit = false
	if spec.check then
		spec = Dice.withMode(spec, state.mode)
	elseif row.critable and state.critPending then
		spec = Dice.crit(spec)
		crit = true
	end
	return spec, crit
end

local function previewDice(spec)
	local dice = {}
	for _, t in ipairs(spec.terms) do
		for _ = 1, t.count do
			dice[#dice + 1] = { sides = t.sides, value = "?", kept = true }
		end
	end
	return dice
end

local function previewFor(row)
	local spec = effectiveSpec(row)
	local key = tostring(row) .. Dice.format(spec)
	if state.preview and state.preview.key == key then return state.preview end
	local dice, bodies = previewDice(spec), {}
	for i, d in ipairs(dice) do
		bodies[i] = Dice3D.newBody(d.sides, d.sides)
	end
	state.preview = { key = key, dice = dice, bodies = bodies }
	return state.preview
end

local function spinAll(amount)
	for _, b in ipairs(state.roll.bodies) do
		Dice3D.spin(b, amount * (0.8 + math.random() * 0.4))
	end
end

local function startRoll(auto)
	local row = selectedRollRow()
	if not row then return end
	if row.pool and #row.spec.terms == 0 then
		toast("Add dice to the pool first")
		return
	end
	local cost = row.cost
	if cost and cost.strict and row.selfHeal and state.res.hp >= character().hp then
		toast("Already at full HP")
		return
	end
	if cost and (cost.each or row.actionKey ~= state.lastCast) then
		local c = character()
		local label = Resources.label(c, cost.key)
		if Resources.spend(c, state.res, cost.key) then
			state.dirty = true
			local left = state.res[cost.key]
			toast("Used " .. label .. " (" .. left .. " left)")
		elseif cost.strict then
			toast("No " .. label .. " left")
			landSynth:playNote(131, 0.3, 0.2)
			return
		else
			toast("Out of " .. label .. "! Rolling anyway")
		end
	end
	state.lastCast = row.actionKey
	local spec, crit = effectiveSpec(row)
	local faces = Dice.faces(spec)
	local bodies = {}
	local preview = previewFor(row)
	for i, d in ipairs(faces) do
		-- pick the dice up from where they were resting
		bodies[i] = Dice3D.newBody(d.sides)
		local last = state.roll and state.roll.row == row and state.roll.bodies[i]
		local from = last or preview.bodies[i]
		if from and from.sides == d.sides then bodies[i].q = from.q end
	end
	state.roll = {
		phase = "tumble", row = row, spec = spec, crit = crit, mode = state.mode,
		faces = faces, bodies = bodies, auto = auto and AUTO_FRAMES or nil,
	}
	spinAll(0.35)
	crank.tick, crank.idle = 0, 0
	playTick()
end

local function settle()
	local roll = state.roll
	local c = Characters[state.charIndex]
	roll.result = Dice.roll(roll.spec, { lucky = c.lucky })
	roll.phase = "landing"
	for i, d in ipairs(roll.result.dice) do
		Dice3D.land(roll.bodies[i], d.value)
	end
end

local function finishLanding()
	local roll = state.roll
	roll.phase = "done"

	if roll.spec.check then
		-- a crit on an attack primes the next damage rolls; any other d20 clears it
		state.critPending = roll.result.crit and roll.row.rollKind == "check"
			and currentPage().title == "ACTIONS"
		state.mode = "normal"
		state.dirty = true
	end
	if roll.row.selfHeal then
		local c = character()
		local before = state.res.hp
		local after = Resources.add(c, state.res, "hp", math.max(0, roll.result.total))
		state.dirty = true
		toast("Healed " .. (after - before) .. " HP (" .. after .. "/" .. c.hp .. ")")
		syncDying()
	end
	if roll.row.deathSave and Resources.dying(state.res) then
		toast(Resources.deathSave(character(), state.res, roll.result))
		state.dirty = true
		syncDying()
	end
	playLand(roll.result)
	-- dice pools (Dice page) stay quiet
	if roll.row.rollKind ~= "pool" then
		if roll.result.natural == 20 then
			playHorn()
		elseif roll.result.natural == 1 then
			playTrombone()
		end
	end
end

local function updateRoll()
	local change = pd.getCrankChange()
	local amount = math.abs(change)
	local roll = state.roll

	if crank.restLock then
		crank.still = amount > 0.5 and 0 or crank.still + 1
		if crank.still >= REST_RELOCK then crank.restLock = false end
	end

	if roll and roll.phase ~= "done" then
		for _, b in ipairs(roll.bodies) do Dice3D.update(b) end
	end

	if roll and roll.phase == "landing" then
		local settled = true
		for _, b in ipairs(roll.bodies) do
			if not Dice3D.isSettled(b) then settled = false end
		end
		if settled then finishLanding() end
		return
	end

	if roll and roll.phase == "tumble" then
		if roll.auto then
			roll.auto -= 1
			spinAll(0.12)
			if roll.auto % 3 == 0 then
				roll.faces = Dice.faces(roll.spec)
				playTick()
			end
			if roll.auto <= 0 then settle() end
			return
		end
		if amount > 0.5 then
			crank.idle = 0
			spinAll(amount * 0.004)
			crank.tick += amount
			if crank.tick >= CRANK_TICK then
				crank.tick %= CRANK_TICK
				roll.faces = Dice.faces(roll.spec)
				playTick()
			end
		else
			crank.idle += 1
			if crank.idle >= SETTLE_FRAMES then settle() end
		end
		return
	end

	local sel = selectedRow()
	if sel and sel.kind == "rest" then
		updateRest(sel, amount)
		return
	end
	if sel and (sel.kind == "resource" or sel.kind == "counter") then
		crank.adjust += change
		while math.abs(crank.adjust) >= CRANK_ADJUST do
			local dir = crank.adjust > 0 and 1 or -1
			crank.adjust -= dir * CRANK_ADJUST
			adjustRow(sel, dir)
		end
		return
	end
	crank.adjust = 0

	if amount > 0.5 then
		crank.idle = 0
		crank.windup += amount
		if crank.windup >= CRANK_START then
			crank.windup = 0
			startRoll(false)
		end
	else
		crank.idle += 1
		if crank.idle > 10 then crank.windup = 0 end
	end
end

---------------------------------------------------------------- input

local repeatTimers = {}

local function holdRepeat(key, fn)
	if repeatTimers[key] then repeatTimers[key]:remove() end
	repeatTimers[key] = pd.timer.keyRepeatTimer(fn)
end

local function release(key)
	if repeatTimers[key] then
		repeatTimers[key]:remove()
		repeatTimers[key] = nil
	end
end

function pd.upButtonDown() holdRepeat("up", function() moveSel(-1) end) end
function pd.upButtonUp() release("up") end
function pd.downButtonDown() holdRepeat("down", function() moveSel(1) end) end
function pd.downButtonUp() release("down") end
function pd.leftButtonDown() changePage(-1) end
function pd.rightButtonDown() changePage(1) end

local function restHint()
	local row = selectedRow()
	if row and row.kind == "rest" then
		toast("Crank to take a " .. row.label:lower())
		return true
	end
end

local function resourceRow()
	local row = selectedRow()
	if row and (row.kind == "resource" or row.kind == "counter") then return row end
end

function pd.AButtonDown()
	if diceMoving() or restHint() then return end
	local r = resourceRow()
	if r then
		holdRepeat("a", function() adjustRow(r, -1) end)
		return
	end
	startRoll(true)
end
function pd.AButtonUp() release("a") end

function pd.BButtonDown()
	if diceMoving() or restHint() then return end
	local r = resourceRow()
	if r then
		holdRepeat("b", function() adjustRow(r, 1) end)
		return
	end
	local sel = selectedRow()
	if sel and sel.pool then
		state.roll = nil
		clearPool()
		return
	end
	local nextMode = { normal = "adv", adv = "dis", dis = "normal" }
	state.mode = nextMode[state.mode]
	state.dirty = true
	if state.roll then state.roll = nil end
end

function pd.BButtonUp() release("b") end

---------------------------------------------------------------- rules viewer

local RULES_SLIDE_FRAMES = 9
local RULES_LINE = 22      -- px per ⬆️⬇️ step
local RULES_CRANK = 0.8    -- px per degree of crank
local RULES_EASE = 0.3     -- fraction of the remaining scroll covered per frame

local function rulesMaxScroll(v)
	return math.max(v.height - UI.RULES_BODY_H, 0)
end

local function scrollRules(delta)
	local v = state.rules
	if not v or v.closing then return end
	v.target = math.max(0, math.min(rulesMaxScroll(v), v.target + delta))
end

local function closeRules()
	if state.rules then state.rules.closing = true end
	for key in pairs(repeatTimers) do release(key) end
end

local rulesInput = {
	upButtonDown = function() holdRepeat("up", function() scrollRules(-RULES_LINE) end) end,
	upButtonUp = function() release("up") end,
	downButtonDown = function() holdRepeat("down", function() scrollRules(RULES_LINE) end) end,
	downButtonUp = function() release("down") end,
	AButtonDown = function()
		local v = state.rules
		if v and v.target >= rulesMaxScroll(v) then closeRules() else scrollRules(UI.RULES_BODY_H - RULES_LINE) end
	end,
	BButtonDown = closeRules,
	cranked = function(change) scrollRules(change * RULES_CRANK) end,
}

local function openRules()
	local d = Rules.describe(character(), selectedRow(), currentPage())
	local img, height = UI.renderRuleBody(Rules.plain(d.body or ""))
	for key in pairs(repeatTimers) do release(key) end
	if not state.rules then pd.inputHandlers.push(rulesInput, true) end
	state.rules = {
		title = Rules.plain(d.title or ""), sub = Rules.plain(d.sub or ""),
		img = img, height = height, scroll = 0, target = 0, t = 0, bob = 0,
	}
end

-- Advances the slide and scroll easing; returns the panel's y offset.
local function updateRules()
	local v = state.rules
	v.t = math.max(0, math.min(RULES_SLIDE_FRAMES, v.t + (v.closing and -1 or 1)))
	if v.closing and v.t == 0 then
		state.rules = nil
		pd.inputHandlers.pop()
		return nil
	end
	local d = v.target - v.scroll
	v.scroll = math.abs(d) < 0.5 and v.target or v.scroll + d * RULES_EASE
	v.bob += 0.2
	local p = 1 - v.t / RULES_SLIDE_FRAMES
	return UI.H * p * p * p -- ease-out cubic
end

---------------------------------------------------------------- persistence / menu

-- Prebuilt heroes keep their list position as their key (matches old saves);
-- imported heroes use "ddb<id>".
local PREBUILT = {}
for i, c in ipairs(Characters) do
	c.key = tostring(i)
	PREBUILT[i] = c
end
local imports = Importer.load()

local function rebuildCharacters()
	Characters = {}
	for _, c in ipairs(PREBUILT) do Characters[#Characters + 1] = c end
	for _, c in ipairs(imports) do Characters[#Characters + 1] = c end
end
rebuildCharacters()

local function indexOfKey(key)
	for i, c in ipairs(Characters) do
		if c.key == key then return i end
	end
end

local function save()
	state.allRes[character().key] = state.res
	state.allView[character().key] = captureView()
	pd.datastore.write({
		charKey = character().key, resources = state.allRes, views = state.allView,
	})
	state.dirty = false
end

local saved = pd.datastore.read()
if saved and type(saved.resources) == "table" then
	for k, r in pairs(saved.resources) do
		if type(k) == "string" and type(r) == "table" then state.allRes[k] = r end
	end
end
if saved and type(saved.views) == "table" then
	for k, v in pairs(saved.views) do
		if type(k) == "string" and type(v) == "table" then state.allView[k] = v end
	end
end
local savedKey = saved and (saved.charKey or (saved.charIndex and tostring(saved.charIndex)))
-- Older saves kept one shared dice pool; give it to the hero who was active.
if savedKey and saved and type(saved.pool) == "table" and not state.allView[savedKey] then
	state.allView[savedKey] = { pool = saved.pool }
end
loadCharacter(indexOfKey(savedKey) or 1)

local menu = pd.getSystemMenu()

-- Short names for the Hero menu, made unique.
local function heroNames()
	local names, seen = {}, {}
	for i, c in ipairs(Characters) do
		local n = c.name:match("^(%S+)") or c.name
		if n == "Brother" or n == "Sister" then n = c.name:match("(%S+)$") end
		if seen[n] then n = n .. " " .. i end
		seen[n] = true
		names[i] = n
	end
	return names
end

local function buildMenu()
	menu:removeAllMenuItems()
	local names = heroNames()
	menu:addOptionsMenuItem("Hero", names, names[state.charIndex], function(choice)
		for i, n in ipairs(names) do
			if n == choice and i ~= state.charIndex then
				save()
				loadCharacter(i)
				save()
			end
		end
	end)
	menu:addMenuItem("Rules", openRules)
end

local function shortRest()
	local restored = Resources.shortRest(character(), state.res)
	state.lastCast = nil
	if #restored > 0 then
		toast("Short rest: " .. table.concat(restored, ", ") .. " restored")
	else
		toast("Short rest: spend Hit Dice to heal")
	end
	save()
end

local function longRest()
	local regained = Resources.longRest(character(), state.res)
	state.lastCast = nil
	state.critPending = false
	syncDying()
	toast("Long rest: fully restored, +" .. regained .. " Hit Dice")
	save()
end

function takeRest(kind)
	if kind == "long" then longRest() else shortRest() end
end

buildMenu()

Importer.listen({
	imported = function(c)
		save()
		Importer.upsert(imports, c)
		Importer.save(imports)
		rebuildCharacters()
		loadCharacter(indexOfKey(c.key))
		buildMenu()
		save()
		toast("Imported " .. c.name)
	end,
	removed = function(key)
		if not Importer.remove(imports, key) then return false end
		Importer.save(imports)
		local current = character().key
		save()
		state.allRes[key] = nil
		state.allView[key] = nil
		state.res = nil
		rebuildCharacters()
		loadCharacter(indexOfKey(current) or 1)
		buildMenu()
		save()
		toast("Removed imported hero")
		return true
	end,
})

function pd.gameWillTerminate() save() end
function pd.deviceWillSleep() save() end

-- The left half of the pause screen explains the selected row.
function pd.gameWillPause()
	local d = Rules.describe(character(), selectedRow(), currentPage())
	pd.setMenuImage(UI.drawRuleCard(Rules.plain(d.title or ""), Rules.plain(d.sub or ""), Rules.plain(d.body or "")))
end

---------------------------------------------------------------- main loop

function pd.update()
	pd.timer.updateTimers()
	local rulesY
	if state.rules then
		pd.getCrankChange() -- the viewer owns the crank; don't let it wind up a roll
		rulesY = updateRules()
	else
		updateRoll()
	end
	if state.toastFrames > 0 then
		state.toastFrames -= 1
		if state.toastFrames == 0 then state.toast = nil end
	end
	-- save shortly after changes settle
	if state.dirty and not diceMoving() then
		state.dirtyFrames = (state.dirtyFrames or 0) + 1
		if state.dirtyFrames > 30 then
			state.dirtyFrames = 0
			save()
		end
	end

	if rulesY == 0 then
		UI.drawRuleViewer(state.rules, 0)
		return
	end
	gfx.clear(gfx.kColorWhite)
	local c = Characters[state.charIndex]
	local page = currentPage()

	UI.drawHeader(c, state.res.hp)
	UI.drawTabs(state.pages, state.page)
	UI.drawList(page, state.sel[state.page], state.scroll[state.page], state.critPending, getResource, getCounter)

	local row = selectedRow()
	local tray = {
		row = row, mode = state.mode, critPending = state.critPending, roll = state.roll,
		getResource = getResource, getCounter = getCounter,
		rest = state.rest and state.rest.row == row and state.rest or nil, restMax = REST_CRANK,
	}
	if row and row.kind == "roll" and not (row.pool and #row.spec.terms == 0) then
		tray.spec = effectiveSpec(row)
		tray.preview = previewFor(row)
	elseif row and row.kind == "counter" then
		local poolRow
		for _, r in ipairs(page.rows) do if r.pool then poolRow = r end end
		if #poolRow.spec.terms > 0 then
			tray.spec = poolRow.spec
			tray.preview = previewFor(poolRow)
		end
	end
	UI.drawTray(tray)
	local footerMode = state.mode
	if row and (row.kind == "resource" or row.kind == "counter") then
		footerMode = "resource"
	elseif row and row.kind == "rest" then
		footerMode = "rest"
	elseif row and row.pool then
		footerMode = "pool"
	end
	UI.drawFooter(footerMode, state.toast)	if rulesY then UI.drawRuleViewer(state.rules, rulesY) end
end
