-- charsheet: a D&D character sheet with crank-powered dice.

import "CoreLibs/graphics"
import "CoreLibs/timer"

import "dice"
import "dice3d"
import "characters"
import "resources"
import "sheet"
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
	allRes = {},    -- saved resources per character index
	lastCast = nil, -- actionKey of the last action that spent a resource
	toast = nil,
	toastFrames = 0,
	dirty = false,
	pool = {},      -- custom dice pool: d4..d20 counts and bonus
}

local crank = { windup = 0, tick = 0, idle = 0, adjust = 0 }

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

---------------------------------------------------------------- selection

local function currentPage()
	return state.pages[state.page]
end

local function isSelectable(row)
	return row and (row.kind == "roll" or row.kind == "resource" or row.kind == "counter")
end

local function firstSelectable(rows)
	for i, r in ipairs(rows) do
		if isSelectable(r) then return i end
	end
	return 1
end

local function ensureVisible()
	local p = state.page
	local rows = currentPage().rows
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

local function adjustResource(key, delta)
	local before = state.res[key]
	local after = Resources.add(character(), state.res, key, delta)
	if after ~= before then
		state.dirty = true
		tickSynth:playNote(delta > 0 and 900 or 500, 0.1, 0.02)
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
local function refreshPool()
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

local function loadCharacter(i)
	if state.res then state.allRes[state.charIndex] = state.res end
	state.charIndex = i
	state.res = Resources.load(Characters[i], state.allRes[i])
	state.allRes[i] = state.res
	state.lastCast = nil
	state.pages = Sheet.build(Characters[i])
	refreshPool()
	state.sel, state.scroll = {}, {}
	for p, page in ipairs(state.pages) do
		state.sel[p] = firstSelectable(page.rows)
		state.scroll[p] = 0
	end
	state.roll = nil
	state.critPending = false
	state.mode = "normal"
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
		ensureVisible()
	end
end

local function changePage(dir)
	if diceMoving() then return end
	state.page = ((state.page - 1 + dir) % #state.pages) + 1
	state.roll = nil
	ensureVisible()
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
	end
	if roll.row.selfHeal then
		local c = character()
		local before = state.res.hp
		local after = Resources.add(c, state.res, "hp", math.max(0, roll.result.total))
		state.dirty = true
		toast("Healed " .. (after - before) .. " HP (" .. after .. "/" .. c.hp .. ")")
	end
	playLand(roll.result)
end

local function updateRoll()
	local change = pd.getCrankChange()
	local amount = math.abs(change)
	local roll = state.roll

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

local function resourceRow()
	local row = selectedRow()
	if row and (row.kind == "resource" or row.kind == "counter") then return row end
end

function pd.AButtonDown()
	if diceMoving() then return end
	local r = resourceRow()
	if r then
		holdRepeat("a", function() adjustRow(r, -1) end)
		return
	end
	startRoll(true)
end
function pd.AButtonUp() release("a") end

function pd.BButtonDown()
	if diceMoving() then return end
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
	if state.roll then state.roll = nil end
end

---------------------------------------------------------------- persistence / menu

function pd.BButtonUp() release("b") end

local function save()
	state.allRes[state.charIndex] = state.res
	-- string keys: the datastore is JSON
	local res = {}
	for i, r in pairs(state.allRes) do res[tostring(i)] = r end
	pd.datastore.write({ charIndex = state.charIndex, resources = res, pool = state.pool })
	state.dirty = false
end

local saved = pd.datastore.read()
if saved and type(saved.resources) == "table" then
	for k, r in pairs(saved.resources) do
		local i = tonumber(k)
		if i and Characters[i] then state.allRes[i] = r end
	end
end
if saved and type(saved.pool) == "table" then
	for k, v in pairs(saved.pool) do
		if type(v) == "number" then state.pool[k] = math.floor(v) end
	end
end
loadCharacter((saved and Characters[saved.charIndex or 0]) and saved.charIndex or 1)

local names = {}
for i, c in ipairs(Characters) do
	names[i] = c.name:match("^(%S+)")
	if names[i] == "Brother" then names[i] = c.name:match("(%S+)$") end
end

local menu = pd.getSystemMenu()

menu:addOptionsMenuItem("Hero", names, names[state.charIndex], function(choice)
	for i, n in ipairs(names) do
		if n == choice and i ~= state.charIndex then
			loadCharacter(i)
			save()
		end
	end
end)

local function shortRest()
	local restored = Resources.shortRest(character(), state.res)
	state.lastCast = nil
	if #restored > 0 then
		toast("Short rest: " .. table.concat(restored, ", ") .. " restored")
	else
		toast("Short rest: spend Hit Dice on STATUS to heal")
	end
	save()
end

local function longRest()
	local regained = Resources.longRest(character(), state.res)
	state.lastCast = nil
	state.critPending = false
	toast("Long rest: fully restored, +" .. regained .. " Hit Dice")
	save()
end

menu:addMenuItem("Short Rest", shortRest)
menu:addMenuItem("Long Rest", longRest)

function pd.gameWillTerminate() save() end
function pd.deviceWillSleep() save() end

---------------------------------------------------------------- main loop

function pd.update()
	pd.timer.updateTimers()
	updateRoll()
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
	elseif row and row.pool then
		footerMode = "pool"
	end
	UI.drawFooter(footerMode, state.toast)
end

