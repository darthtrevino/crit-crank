-- charsheet: a D&D character sheet with crank-powered dice.

import "CoreLibs/graphics"
import "CoreLibs/timer"

import "dice"
import "characters"
import "sheet"
import "ui"

local pd <const> = playdate
local gfx <const> = pd.graphics

-- Crank tuning (degrees / frames)
local CRANK_START = 30   -- rotation needed to pick up the dice
local CRANK_TICK = 40    -- rotation per face change while tumbling
local SETTLE_FRAMES = 8  -- frames of stillness before the dice land
local AUTO_FRAMES = 16   -- length of the Ⓐ-button quick roll

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
}

local crank = { windup = 0, tick = 0, idle = 0 }

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
	return row and row.kind == "roll"
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

local function loadCharacter(i)
	state.charIndex = i
	state.pages = Sheet.build(Characters[i])
	state.sel, state.scroll = {}, {}
	for p, page in ipairs(state.pages) do
		state.sel[p] = firstSelectable(page.rows)
		state.scroll[p] = 0
	end
	state.roll = nil
	state.critPending = false
	state.mode = "normal"
end

local function moveSel(dir)
	if state.roll and state.roll.phase == "tumble" then return end
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
	if state.roll and state.roll.phase == "tumble" then return end
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

local function startRoll(auto)
	local row = selectedRow()
	if not row then return end
	local spec, crit = effectiveSpec(row)
	state.roll = {
		phase = "tumble", row = row, spec = spec, crit = crit, mode = state.mode,
		faces = Dice.faces(spec), auto = auto and AUTO_FRAMES or nil,
	}
	crank.tick, crank.idle = 0, 0
	playTick()
end

local function settle()
	local roll = state.roll
	local c = Characters[state.charIndex]
	roll.result = Dice.roll(roll.spec, { lucky = c.lucky })
	roll.phase = "done"

	if roll.spec.check then
		-- a crit on an attack primes the next damage rolls; any other d20 clears it
		state.critPending = roll.result.crit and roll.row.rollKind == "check"
			and currentPage().title == "ACTIONS"
		state.mode = "normal"
	end
	playLand(roll.result)
end

local function updateRoll()
	local change = pd.getCrankChange()
	local amount = math.abs(change)
	local roll = state.roll

	if roll and roll.phase == "tumble" then
		if roll.auto then
			roll.auto -= 1
			if roll.auto % 2 == 0 then
				roll.faces = Dice.faces(roll.spec)
				playTick()
			end
			if roll.auto <= 0 then settle() end
			return
		end
		if amount > 0.5 then
			crank.idle = 0
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

function pd.AButtonDown()
	if state.roll and state.roll.phase == "tumble" then return end
	startRoll(true)
end

function pd.BButtonDown()
	if state.roll and state.roll.phase == "tumble" then return end
	local nextMode = { normal = "adv", adv = "dis", dis = "normal" }
	state.mode = nextMode[state.mode]
	if state.roll then state.roll = nil end
end

---------------------------------------------------------------- persistence / menu

local function save()
	pd.datastore.write({ charIndex = state.charIndex })
end

local saved = pd.datastore.read()
loadCharacter((saved and Characters[saved.charIndex or 0]) and saved.charIndex or 1)

local names = {}
for i, c in ipairs(Characters) do
	names[i] = c.name:match("^(%S+)")
	if names[i] == "Brother" then names[i] = c.name:match("(%S+)$") end
end

pd.getSystemMenu():addOptionsMenuItem("Hero", names, names[state.charIndex], function(choice)
	for i, n in ipairs(names) do
		if n == choice then
			loadCharacter(i)
			save()
		end
	end
end)

function pd.gameWillTerminate() save() end
function pd.deviceWillSleep() save() end

---------------------------------------------------------------- main loop

function pd.update()
	pd.timer.updateTimers()
	updateRoll()

	gfx.clear(gfx.kColorWhite)
	local c = Characters[state.charIndex]
	local page = currentPage()

	UI.drawHeader(c)
	UI.drawTabs(state.pages, state.page)
	UI.drawList(page, state.sel[state.page], state.scroll[state.page], state.critPending)

	local row = selectedRow()
	local tray = { row = row, mode = state.mode, critPending = state.critPending, roll = state.roll }
	if row then
		tray.spec = effectiveSpec(row)
		tray.preview = previewDice(tray.spec)
	end
	UI.drawTray(tray)
	UI.drawFooter(state.mode)
end
