-- Drawing routines for the character sheet.

local gfx <const> = playdate.graphics
local geo <const> = playdate.geometry

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

function UI.drawHeader(c)
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(0, 0, UI.W, UI.HEADER_H)
	gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	drawText(fonts.title, c.name, 6, 3)
	local nameW = textW(fonts.title, c.name)
	local stats = "AC " .. c.ac .. "  HP " .. c.hp .. "  " .. c.speed .. "ft"
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

function UI.drawList(page, sel, scroll, critPending)
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
			local valueW = textW(valueFont, row.value or "")
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
			if row.value then
				drawText(valueFont, row.value, valueX, textY, "right")
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

---------------------------------------------------------------- dice

local function regular(cx, cy, r, n, rot)
	local pts = {}
	for i = 0, n - 1 do
		local a = rot + i * 2 * math.pi / n
		pts[#pts + 1] = cx + r * math.cos(a)
		pts[#pts + 1] = cy + r * math.sin(a)
	end
	return pts
end

local function dieShape(sides, cx, cy, r)
	if sides == 4 then
		return regular(cx, cy + r * 0.2, r * 1.1, 3, -math.pi / 2), r * 0.15
	elseif sides == 6 then
		return { cx - r * 0.8, cy - r * 0.8, cx + r * 0.8, cy - r * 0.8, cx + r * 0.8, cy + r * 0.8, cx - r * 0.8, cy + r * 0.8 }, 0
	elseif sides == 8 then
		return regular(cx, cy, r, 4, -math.pi / 2), 0
	elseif sides == 10 or sides == 100 then
		return { cx, cy - r, cx + r, cy - r * 0.1, cx + r * 0.6, cy + r * 0.7, cx, cy + r,
			cx - r * 0.6, cy + r * 0.7, cx - r, cy - r * 0.1 }, 0
	elseif sides == 12 then
		return regular(cx, cy, r, 5, -math.pi / 2), r * 0.05
	else
		return regular(cx, cy, r, 6, -math.pi / 2), 0
	end
end

-- style: "normal" | "dropped" | "hot" (inverted, for crits)
function UI.drawDie(sides, value, cx, cy, r, style)
	local pts, textOffset = dieShape(sides, cx, cy, r)
	local poly = geo.polygon.new(table.unpack(pts))
	poly:close()

	if style == "hot" then
		gfx.setColor(gfx.kColorBlack)
		gfx.fillPolygon(poly)
	else
		gfx.setColor(gfx.kColorWhite)
		gfx.fillPolygon(poly)
	end
	gfx.setColor(gfx.kColorBlack)
	if style == "dropped" then
		-- faded outline for dice that don't count
		gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
		gfx.setLineWidth(1)
	else
		gfx.setLineWidth(2)
	end
	gfx.drawPolygon(poly)
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)

	if style == "hot" then gfx.setImageDrawMode(gfx.kDrawModeFillWhite) end
	local s = tostring(value)
	local f = fonts.small
	drawText(f, s, cx, math.floor(cy + textOffset - f:getHeight() / 2), "center")
	gfx.setImageDrawMode(gfx.kDrawModeCopy)

	if style == "dropped" then
		gfx.drawLine(cx - r * 0.6, cy + r * 0.6, cx + r * 0.6, cy - r * 0.6)
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

local function drawDiceGrid(dice, top, bottom, jitter, result)
	local n = #dice
	if n == 0 then return end
	local r, gap, cols
	if n <= 2 then
		r, cols = 22, n
	elseif n <= 6 then
		r, cols = 15, 3
	elseif n <= 12 then
		r, cols = 13, 4
	else
		r, cols = 10, 5
	end
	gap = r * 2 + 6
	local rowsN = math.ceil(n / cols)
	local gridH = rowsN * gap
	local startY = top + math.floor((bottom - top - gridH) / 2) + gap / 2
	for i, d in ipairs(dice) do
		local row = math.floor((i - 1) / cols)
		local inRow = math.min(cols, n - row * cols)
		local col = (i - 1) % cols
		local cx = TRAY_CX - (inRow - 1) * gap / 2 + col * gap
		local cy = startY + row * gap
		if jitter then
			cx += math.random(-2, 2)
			cy += math.random(-2, 2)
		end
		local style = "normal"
		if not d.kept then
			style = "dropped"
		elseif result and d.sides == 20 and result.natural == d.value and (result.crit or result.fumble) then
			style = "hot"
		end
		UI.drawDie(d.sides, d.value, cx, cy, r, style)
	end
end

-- tray = { row, spec, mode, critPending, roll = {phase, faces, result, spec, crit, lucky} }
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

	local roll = t.roll
	local spec = roll and roll.spec or t.spec
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
		drawDiceGrid(t.preview, diceTop, diceBottom, false)
		if row.detail then
			drawText(fonts.small, fit(fonts.small, row.detail, TRAY_W), TRAY_CX, y + 128, "center")
		end
		local hint = playdate.isCrankDocked() and "Press Ⓐ to roll" or "Crank to roll 🎣"
		drawText(fonts.small, hint, TRAY_CX, y + 150, "center")
		return
	end

	if roll.phase == "tumble" then
		drawDiceGrid(roll.faces, diceTop, diceBottom, true)
		drawText(fonts.small, "rolling...", TRAY_CX, y + 150, "center")
		return
	end

	local res = roll.result
	drawDiceGrid(res.dice, diceTop, diceBottom, false, res)
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

function UI.drawFooter(mode)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawLine(0, UI.FOOTER_Y, UI.W, UI.FOOTER_Y)
	local modeText = (mode == "adv" and "ADV") or (mode == "dis" and "DIS") or "normal"
	drawText(fonts.small, "⬅️➡️ page  ⬆️⬇️ select  🎣/Ⓐ roll", 6, UI.FOOTER_Y + 2)
	drawText(fonts.small, "Ⓑ " .. modeText, UI.W - 6, UI.FOOTER_Y + 2, "right")
end
