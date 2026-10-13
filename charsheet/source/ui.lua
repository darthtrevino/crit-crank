-- Drawing routines for the character sheet.

local gfx <const> = playdate.graphics

UI = {}

UI.W, UI.H = 400, 240
UI.HEADER_H = 24
UI.TABS_Y = 24
UI.TABS_H = 18
UI.BODY_Y = 44
UI.FOOTER_Y = 224
UI.ROW_H = 22
UI.LIST_W = 258
UI.TRAY_X = 262
UI.VISIBLE_ROWS = math.floor((UI.FOOTER_Y - UI.BODY_Y) / UI.ROW_H)

local fonts = {
	small = gfx.font.new("fonts/Roobert-10-Bold"),
	body = gfx.font.new("fonts/Roobert-11-Medium"),
	title = gfx.font.new("fonts/Asheville-Sans-14-Bold"),
	big = gfx.font.new("fonts/Roobert-24-Medium"),
}
UI.fonts = fonts

local function textW(font, s)
	return font:getTextWidth(s)
end

local function drawText(font, s, x, y, align)
	gfx.setFont(font)
	if align == "right" then
		x -= textW(font, s)
	elseif align == "center" then
		x -= math.floor(textW(font, s) / 2)
	end
	gfx.drawText(s, x, y)
end

-- Shortens a string with "…" until it fits in maxW pixels.
local function fit(font, s, maxW)
	if textW(font, s) <= maxW then return s end
	while #s > 1 and textW(font, s .. "…") > maxW do
		s = s:sub(1, -2)
	end
	return s .. "…"
end
UI.fit = fit

---------------------------------------------------------------- header / tabs

function UI.drawHeader(c, hp)
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(0, 0, UI.W, UI.HEADER_H)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	drawText(fonts.title, c.name, 6, 3)
	local nameW = textW(fonts.title, c.name)
	local stats = "AC " .. c.ac .. "  HP " .. hp .. "/" .. c.hp .. "  " .. c.speed .. "ft"
	local statsW = textW(fonts.small, stats)
	local room = UI.W - 6 - statsW - 10 - (12 + nameW)
	local sub = "Lv" .. c.level .. " " .. c.race .. " " .. c.class
	if textW(fonts.small, sub) > room then sub = "Lv" .. c.level .. " " .. c.class end
	drawText(fonts.small, fit(fonts.small, sub, room), 12 + nameW, 7)
	drawText(fonts.small, stats, UI.W - 6, 7, "right")
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function UI.drawTabs(pages, current)
	local w = UI.W / #pages
	for i, p in ipairs(pages) do
		local x = math.floor((i - 1) * w)
		local selected = i == current
		if selected then
			gfx.setColor(gfx.kColorBlack)
			gfx.fillRoundRect(x + 2, UI.TABS_Y + 2, math.floor(w) - 4, UI.TABS_H - 2, 4)
			gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
		end
		drawText(fonts.small, p.title, x + math.floor(w / 2), UI.TABS_Y + 4, "center")
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
	end
	gfx.setColor(gfx.kColorBlack)
	gfx.drawLine(0, UI.BODY_Y - 1, UI.W, UI.BODY_Y - 1)
end

---------------------------------------------------------------- list

local function drawMark(mark, x, cy)
	if mark == "prof" then
		gfx.fillCircleAtPoint(x, cy, 3)
	elseif mark == "exp" then
		gfx.fillCircleAtPoint(x, cy, 3)
		gfx.drawCircleAtPoint(x, cy, 5)
	elseif mark == "none" then
		gfx.drawCircleAtPoint(x, cy, 3)
	end
end

local PIP_GAP = 11

local function drawPips(cur, max, rightX, cy)
	for i = 1, max do
		local x = rightX - (max - i) * PIP_GAP - 4
		if i <= cur then
			gfx.fillCircleAtPoint(x, cy, 4)
		else
			gfx.drawCircleAtPoint(x, cy, 4)
		end
	end
end

-- Small counters are drawn as pips; HP and big pools as "cur/max".
local function usePips(key, max)
	return key ~= "hp" and max <= 6
end

-- getResource(key) -> cur, max
local function counterText(key, n)
	if key == "bonus" then return n == 0 and "+0" or Dice.signed(n) end
	return n == 0 and "-" or ("x" .. n)
end

-- getCounter(key) -> n
function UI.drawList(page, sel, scroll, critPending, getResource, getCounter)
	local rows = page.rows
	local valueX = UI.LIST_W - 8
	for vi = 1, UI.VISIBLE_ROWS do
		local i = scroll + vi
		local row = rows[i]
		if not row then break end
		local y = UI.BODY_Y + (vi - 1) * UI.ROW_H
		local selected = i == sel

		if row.kind == "header" then
			drawText(fonts.small, row.label:upper(), 6, y + 6)
			local lx = 12 + textW(fonts.small, row.label:upper())
			gfx.setColor(gfx.kColorBlack)
			gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
			gfx.drawLine(lx, y + 12, UI.LIST_W - 6, y + 12)
			gfx.setColor(gfx.kColorBlack)
		else
			if selected then
				gfx.setColor(gfx.kColorBlack)
				gfx.fillRoundRect(2, y + 1, UI.LIST_W - 6, UI.ROW_H - 1, 4)
				gfx.setColor(gfx.kColorWhite)
				gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
			else
				gfx.setColor(gfx.kColorBlack)
			end

			local textY = y + 2
			local labelX = 18
			if row.indent then
				labelX = 30
				gfx.drawLine(20, y + 5, 20, y + 12)
				gfx.drawLine(20, y + 12, 26, y + 12)
			end
			drawMark(row.mark, 10, y + UI.ROW_H / 2)

			local valueFont = fonts.body
			local value = row.value
			local pips
			if row.kind == "resource" then
				local cur, max = getResource(row.key)
				if usePips(row.key, max) then
					pips = { cur, max }
					value = nil
				else
					value = cur .. "/" .. max
				end
			elseif row.kind == "counter" then
				value = counterText(row.key, getCounter(row.key))
			end
			local valueW = pips and (pips[2] * PIP_GAP) or textW(valueFont, value or "")
			local labelFont = row.indent and fonts.small or fonts.body
			local detailW = row.detail and (textW(fonts.small, row.detail) + 8) or 0
			local labelRoom = valueX - valueW - labelX - 6
			-- drop the detail text before truncating the label
			local showDetail = row.detail and textW(labelFont, row.label) <= labelRoom - detailW
			if not showDetail then detailW = 0 end
			local label = fit(labelFont, row.label, labelRoom - detailW)
			drawText(labelFont, label, labelX, row.indent and (y + 5) or textY)
			if showDetail then
				drawText(fonts.small, row.detail, valueX - valueW - 8, y + 5, "right")
			end
			if value then
				drawText(valueFont, value, valueX, textY, "right")
			elseif pips then
				drawPips(pips[1], pips[2], valueX, y + UI.ROW_H / 2)
			end
			if critPending and row.critable and not selected then
				drawText(fonts.small, "x2", valueX - valueW - detailW - 4, y + 5, "right")
			end

			gfx.setImageDrawMode(gfx.kDrawModeCopy)
			gfx.setColor(gfx.kColorBlack)
		end
	end

	-- scrollbar
	if #rows > UI.VISIBLE_ROWS then
		local trackH = UI.VISIBLE_ROWS * UI.ROW_H
		local h = math.max(10, math.floor(trackH * UI.VISIBLE_ROWS / #rows))
		local maxScroll = #rows - UI.VISIBLE_ROWS
		local y = UI.BODY_Y + math.floor((trackH - h) * scroll / maxScroll)
		gfx.setColor(gfx.kColorBlack)
		gfx.fillRect(UI.LIST_W - 3, y, 2, h)
	end
end

---------------------------------------------------------------- dice tray

local TRAY_CX = UI.TRAY_X + math.floor((UI.W - UI.TRAY_X) / 2)
local TRAY_W = UI.W - UI.TRAY_X - 8

local function drawPill(text, cx, y)
	local w = textW(fonts.small, text) + 10
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRoundRect(cx - w / 2, y, w, 15, 7)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	drawText(fonts.small, text, cx, y + 1, "center")
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- dice: list of { sides, value, kept }; bodies: matching Dice3D bodies.
local function drawDiceGrid(dice, bodies, top, bottom, result)
	local n = #dice
	if n == 0 then return end
	local r, cols
	if n == 1 then
		r, cols = 30, 1
	elseif n == 2 then
		r, cols = 24, 2
	elseif n <= 6 then
		r, cols = 17, 3
	elseif n <= 12 then
		r, cols = 14, 4
	else
		r, cols = 11, 5
	end
	local gap = math.min(r * 2 + 4, math.floor((UI.W - UI.TRAY_X - 4) / cols))
	local rowsN = math.ceil(n / cols)
	local gridH = rowsN * gap
	local startY = top + math.floor((bottom - top - gridH) / 2) + gap / 2
	for i, d in ipairs(dice) do
		local row = math.floor((i - 1) / cols)
		local inRow = math.min(cols, n - row * cols)
		local col = (i - 1) % cols
		local cx = TRAY_CX - (inRow - 1) * gap / 2 + col * gap
		local cy = startY + row * gap
		local style = "normal"
		if not d.kept then
			style = "dropped"
		elseif result and d.sides == 20 and result.natural == d.value and (result.crit or result.fumble) then
			style = "hot"
		end
		Dice3D.draw(bodies[i], cx, cy, r, d.value, style, fonts.small)
	end
end

-- tray = { row, spec, mode, critPending, preview = {dice, bodies},
--          roll = {phase, faces, bodies, result, spec, crit, mode} }
function UI.drawTray(t)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawLine(UI.TRAY_X - 2, UI.BODY_Y, UI.TRAY_X - 2, UI.FOOTER_Y - 1)

	local row = t.row
	local y = UI.BODY_Y + 3
	if not row then
		drawText(fonts.small, "Nothing to roll", TRAY_CX, y + 70, "center")
		return
	end

	local title = row.title or row.label
	drawText(fonts.small, fit(fonts.small, title, TRAY_W), TRAY_CX, y, "center")

	if row.kind == "resource" then
		local cur, max = t.getResource(row.key)
		if row.detail then
			drawText(fonts.small, row.detail, TRAY_CX, y + 16, "center")
		end
		drawText(fonts.big, tostring(cur), TRAY_CX, y + 50, "center")
		drawText(fonts.small, "of " .. max, TRAY_CX, y + 90, "center")
		if usePips(row.key, max) then
			drawPips(cur, max, TRAY_CX + math.floor(max * PIP_GAP / 2), y + 118)
		end
		drawText(fonts.small, "🎣 adjust", TRAY_CX, y + 140, "center")
		drawText(fonts.small, "Ⓐ -1   Ⓑ +1", TRAY_CX, y + 158, "center")
		return
	end

	if row.kind == "counter" then
		local n = t.getCounter(row.key)
		drawText(fonts.big, counterText(row.key, n), TRAY_CX, y + 18, "center")
		if t.preview then
			drawText(fonts.small, fit(fonts.small, "Pool: " .. Dice.format(t.spec), TRAY_W), TRAY_CX, y + 56, "center")
			drawDiceGrid(t.preview.dice, t.preview.bodies, y + 70, y + 136)
		else
			drawText(fonts.small, "Pool is empty", TRAY_CX, y + 90, "center")
		end
		drawText(fonts.small, "🎣 adjust", TRAY_CX, y + 140, "center")
		drawText(fonts.small, "Ⓐ -1   Ⓑ +1", TRAY_CX, y + 158, "center")
		return
	end

	if row.kind == "rest" then
		drawText(fonts.small, row.detail, TRAY_CX, y + 16, "center")
		local lines = row.key == "long"
			and { "Full HP, spell slots", "and features, half", "your Hit Dice back" }
			or { "Recharge short-rest", "features, then spend", "Hit Dice to heal" }
		for i, l in ipairs(lines) do
			drawText(fonts.small, l, TRAY_CX, y + 38 + (i - 1) * 15, "center")
		end
		local rest = t.rest
		local barW, barY = TRAY_W - 16, y + 100
		local barX = TRAY_CX - barW / 2
		gfx.setColor(gfx.kColorBlack)
		gfx.drawRoundRect(barX, barY, barW, 14, 4)
		local fill = rest and math.floor((barW - 4) * rest.progress / t.restMax) or 0
		if fill > 0 then gfx.fillRoundRect(barX + 2, barY + 2, fill, 10, 3) end
		if rest and rest.done then
			drawPill("RESTED", TRAY_CX, y + 126)
		end
		local hint = playdate.isCrankDocked() and "Undock the crank" or "Crank to rest 🎣"
		drawText(fonts.small, hint, TRAY_CX, y + 150, "center")
		return
	end

	local roll = t.roll
	local spec = roll and roll.spec or t.spec
	if row.pool and not roll and not spec then
		drawText(fonts.small, "Pool is empty", TRAY_CX, y + 60, "center")
		drawText(fonts.small, "Add dice with the", TRAY_CX, y + 90, "center")
		drawText(fonts.small, "rows below ⬇️", TRAY_CX, y + 106, "center")
		return
	end
	local tag
	if roll and roll.crit then
		tag = "CRITICAL x2"
	elseif not roll and t.critPending and row.critable then
		tag = "CRITICAL x2"
	elseif spec.check then
		local mode = roll and roll.mode or t.mode
		if mode == "adv" then tag = "ADVANTAGE" elseif mode == "dis" then tag = "DISADVANTAGE" end
	end
	if tag then
		drawPill(tag, TRAY_CX, y + 15)
	else
		drawText(fonts.small, Dice.format(spec), TRAY_CX, y + 16, "center")
	end

	local diceTop, diceBottom = y + 32, y + 120
	if not roll then
		drawDiceGrid(t.preview.dice, t.preview.bodies, diceTop, diceBottom)
		if row.detail then
			drawText(fonts.small, fit(fonts.small, row.detail, TRAY_W), TRAY_CX, y + 128, "center")
		end
		local hint = playdate.isCrankDocked() and "Press Ⓐ to roll" or "Crank to roll 🎣"
		drawText(fonts.small, hint, TRAY_CX, y + 150, "center")
		return
	end

	if roll.phase == "tumble" then
		drawDiceGrid(roll.faces, roll.bodies, diceTop, diceBottom)
		drawText(fonts.small, "rolling...", TRAY_CX, y + 150, "center")
		return
	end

	local res = roll.result
	if roll.phase == "landing" then
		drawDiceGrid(res.dice, roll.bodies, diceTop, diceBottom)
		return
	end
	drawDiceGrid(res.dice, roll.bodies, diceTop, diceBottom, res)
	drawText(fonts.big, tostring(res.total), TRAY_CX, y + 122, "center")

	local note
	if res.crit then
		note = (res.natural == 20) and "NATURAL 20!" or ("CRIT! (" .. res.natural .. ")")
	elseif res.fumble then
		note = "NATURAL 1"
	elseif res.lucky then
		note = "Lucky! rerolled a 1"
	elseif spec.bonus ~= 0 then
		note = tostring(res.total - spec.bonus) .. " " .. (spec.bonus > 0 and "+ " or "- ") .. math.abs(spec.bonus)
	end
	if note then
		if res.crit or res.fumble then
			drawPill(note, TRAY_CX, y + 158)
		else
			drawText(fonts.small, note, TRAY_CX, y + 160, "center")
		end
	end
end

---------------------------------------------------------------- footer

function UI.drawFooter(mode, toast)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawLine(0, UI.FOOTER_Y, UI.W, UI.FOOTER_Y)
	if toast then
		gfx.fillRect(0, UI.FOOTER_Y, UI.W, UI.H - UI.FOOTER_Y)
		gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
		drawText(fonts.small, fit(fonts.small, toast, UI.W - 12), UI.W / 2, UI.FOOTER_Y + 2, "center")
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
		return
	end
	if mode == "pool" then
		drawText(fonts.small, "⬅️➡️ page  ⬆️⬇️ select  🎣/Ⓐ roll", 6, UI.FOOTER_Y + 2)
		drawText(fonts.small, "Ⓑ clear", UI.W - 6, UI.FOOTER_Y + 2, "right")
		return
	end
	if mode == "rest" then
		drawText(fonts.small, "⬅️➡️ page  ⬆️⬇️ select  🎣 crank to rest", 6, UI.FOOTER_Y + 2)
		return
	end
	if mode == "resource" then
		drawText(fonts.small, "⬅️➡️ page  ⬆️⬇️ select  🎣 adjust", 6, UI.FOOTER_Y + 2)
		drawText(fonts.small, "Ⓐ -1  Ⓑ +1", UI.W - 6, UI.FOOTER_Y + 2, "right")
		return
	end
	drawText(fonts.small, "⬅️➡️ page  ⬆️⬇️ select  🎣/Ⓐ roll", 6, UI.FOOTER_Y + 2)
	if mode == "plain" then return end
	local modeText = (mode == "adv" and "ADV") or (mode == "dis" and "DIS")
		or (mode == "crit" and "CRIT") or "normal"
	drawText(fonts.small, "Ⓑ " .. modeText, UI.W - 6, UI.FOOTER_Y + 2, "right")
end

---------------------------------------------------------------- pause card

-- Renders rule text into the 200px the system menu leaves visible.
function UI.drawRuleCard(title, sub, body)
	local img = gfx.image.new(400, 240, gfx.kColorWhite)
	local X, W = 10, 180
	gfx.pushContext(img)
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(0, 0, 200, 30)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	drawText(fonts.title, fit(fonts.title, title, W), X, 8)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	local y = 36
	if sub ~= "" then
		drawText(fonts.small, fit(fonts.small, sub, W), X, y)
		y += 16
		gfx.setDitherPattern(0.5)
		gfx.drawLine(X, y, X + W, y)
		gfx.setColor(gfx.kColorBlack)
		y += 6
	end
	local h = 236 - y
	local font = fonts.body
	local _, need = gfx.getTextSizeForMaxWidth(body, W, nil, font)
	if need > h then font = fonts.small end
	_, need = gfx.getTextSizeForMaxWidth(body, W, nil, font)
	if need > h then
		-- Too long for the card: point at the scrolling viewer.
		h -= 18
		gfx.fillRect(0, 222, 199, 18)
		gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
		drawText(fonts.small, fit(fonts.small, "More: Read Rule in menu", W), X, 224)
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
	end
	gfx.setFont(font)
	gfx.drawTextInRect(body, X, y, W, h, nil, "…")
	gfx.setColor(gfx.kColorBlack)
	gfx.drawLine(199, 0, 199, 240)
	gfx.popContext()
	return img
end

---------------------------------------------------------------- rules viewer

UI.RULES_BODY_Y = 52
UI.RULES_BODY_H = UI.FOOTER_Y - UI.RULES_BODY_Y - 2
local RULES_X, RULES_W = 12, UI.W - 32

-- Pre-renders rule text once so scrolling only blits an image.
function UI.renderRuleBody(body)
	if body == "" then body = "No extra rules for this row." end
	local _, h = gfx.getTextSizeForMaxWidth(body, RULES_W, nil, fonts.body)
	h = math.max(h + 4, 1)
	local img = gfx.image.new(RULES_W, h)
	gfx.pushContext(img)
	gfx.setFont(fonts.body)
	gfx.drawTextInRect(body, 0, 0, RULES_W, h)
	gfx.popContext()
	return img, h
end

-- Full-screen rule text. v = { title, sub, img, height, scroll, bob };
-- dy slides the panel down (0 = fully open).
function UI.drawRuleViewer(v, dy)
	dy = math.floor(dy)
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(0, dy, UI.W, UI.H)
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(0, dy, UI.W, 28)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	drawText(fonts.title, fit(fonts.title, v.title, UI.W - 24), RULES_X, dy + 7)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)
	drawText(fonts.small, fit(fonts.small, v.sub, RULES_W), RULES_X, dy + 31)
	gfx.setDitherPattern(0.5)
	gfx.drawLine(RULES_X, dy + 47, UI.W - RULES_X, dy + 47)
	gfx.setColor(gfx.kColorBlack)

	local top, h = dy + UI.RULES_BODY_Y, UI.RULES_BODY_H
	gfx.setClipRect(0, top, UI.W, h)
	v.img:draw(RULES_X, top - math.floor(v.scroll))
	gfx.clearClipRect()

	local maxScroll = math.max(v.height - h, 0)
	if maxScroll > 0 then
		local trackX = UI.W - 8
		local thumbH = math.max(math.floor(h * h / v.height), 12)
		local thumbY = top + math.floor((h - thumbH) * v.scroll / maxScroll)
		gfx.setDitherPattern(0.75)
		gfx.drawLine(trackX + 1, top, trackX + 1, top + h)
		gfx.setColor(gfx.kColorBlack)
		gfx.fillRoundRect(trackX, thumbY, 3, thumbH, 1)
		if v.scroll < maxScroll - 1 then
			-- bobbing "more below" arrow
			local ax = UI.W - 100
			local ay = dy + UI.FOOTER_Y + 6 + math.floor(math.sin(v.bob) * 2 + 0.5)
			gfx.fillTriangle(ax - 5, ay, ax + 5, ay, ax, ay + 5)
		end
	end

	gfx.drawLine(0, dy + UI.FOOTER_Y, UI.W, dy + UI.FOOTER_Y)
	drawText(fonts.small, "🎣/⬆️⬇️ scroll  Ⓐ page", 6, dy + UI.FOOTER_Y + 2)
	drawText(fonts.small, "Ⓑ close", UI.W - 6, dy + UI.FOOTER_Y + 2, "right")
end
