-- luacheck config for Playdate Lua (run via tools/lint.sh).
std = "lua54"
max_line_length = false
codes = true
-- Playdate Lua supports compound assignment
operators = { "+=", "-=", "*=", "/=", "%=" }

globals = {
	"playdate", "import", "json", "kTextAlignment",
	-- modules shared between files
	"UI", "Dice", "Dice3D", "Sheet", "Rules", "Characters", "Resources", "Importer",
	"shortRest", "longRest",
}

ignore = {
	"212", -- unused argument (callbacks keep their full signature)
}
