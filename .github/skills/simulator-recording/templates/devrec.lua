-- DEVTEMP: Simulator screen recorder. Never commit this file.
-- Copied from .github/skills/simulator-recording/templates/devrec.lua.
-- Load it with `import "devrec" -- DEVTEMP` as the LAST line of main.lua so it
-- can wrap playdate.update after main.lua defines it.
--
-- Every frame it runs the scripted input below, then writes the frame to
-- OUT/f00000.png, f00001.png, ... When the script ends it writes OUT/done.png.

local pd <const> = playdate
local gfx <const> = playdate.graphics

local OUT <const> = "/tmp/critcrank-rec"

-------------------------------------------------------------- edit the script
-- Steps run in order:
--   { "wait", frames }               idle (30 frames = 1 second)
--   { "press", button }              tap: down this frame, up next frame
--   { "hold", button, frames }       hold down (triggers key repeat), then up
--   { "crank", degPerFrame, frames } turn the crank (undocks it while turning)
--   { "dock", true|false }           force isCrankDocked() (nil = real value)
--   { "call", function() ... end }   anything else
-- Buttons: "a", "b", "up", "down", "left", "right".
local SCRIPT = {
	{ "wait", 30 },
	{ "press", "down" },
	{ "wait", 15 },
	{ "crank", 20, 30 },
	{ "wait", 90 },
}
------------------------------------------------------------------------------

local handlers = {}
local origPush, origPop = pd.inputHandlers.push, pd.inputHandlers.pop
pd.inputHandlers.push = function(h, ...)
	handlers[#handlers + 1] = h
	return origPush(h, ...)
end
pd.inputHandlers.pop = function(...)
	handlers[#handlers] = nil
	return origPop(...)
end

local NAMES <const> = { a = "A", b = "B", up = "up", down = "down", left = "left", right = "right" }
local function fire(button, suffix)
	local key = NAMES[button] .. "Button" .. suffix
	local top = handlers[#handlers]
	local fn = (top and top[key]) or pd[key]
	if fn then fn() end
end

local crankDelta = 0
local origCrankChange = pd.getCrankChange
pd.getCrankChange = function()
	local change, accel = origCrankChange()
	change += crankDelta
	crankDelta = 0
	return change, accel
end

local docked = nil
local origDocked = pd.isCrankDocked
pd.isCrankDocked = function()
	if docked ~= nil then return docked end
	return origDocked()
end

local step, left, held = 1, nil, nil
local function runScript()
	if held then
		fire(held, "Up")
		held = nil
	end
	local s = SCRIPT[step]
	if not s then return false end
	local kind = s[1]
	if kind == "wait" then
		left = (left or s[2]) - 1
	elseif kind == "press" then
		fire(s[2], "Down")
		held, left = s[2], 0
	elseif kind == "hold" then
		if not left then fire(s[2], "Down") end
		left = (left or s[3]) - 1
		if left <= 0 then fire(s[2], "Up") end
	elseif kind == "crank" then
		docked = false
		local top = handlers[#handlers]
		if top and top.cranked then top.cranked(s[2], s[2]) else crankDelta += s[2] end
		left = (left or s[3]) - 1
	elseif kind == "dock" then
		docked, left = s[2], 0
	elseif kind == "call" then
		s[2]()
		left = 0
	end
	if left <= 0 then step, left = step + 1, nil end
	return true
end

local frame, finished = 0, false
local origUpdate = pd.update
pd.update = function()
	local running = not finished and runScript()
	origUpdate()
	if finished then return end
	pd.simulator.writeToFile(gfx.getWorkingImage(), string.format("%s/f%05d.png", OUT, frame))
	frame += 1
	if not running then
		finished = true
		pd.simulator.writeToFile(gfx.getWorkingImage(), OUT .. "/done.png")
		print("devrec: recorded " .. frame .. " frames to " .. OUT)
	end
end
