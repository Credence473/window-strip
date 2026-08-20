-- Niri window strip for Noctalia v5
--
-- Displays windows from the currently focused workspace in Niri's
-- scrolling-layout order.
--
--   inactive window -> icon
--   focused window  -> icon + title
--
-- Clicking any item focuses that window.

local windows = {}
local requestPending = false

local iconCache = {}

local ICON_SIZE = 18
local ICON_GAP = 6
local WINDOW_GAP = 8
local TITLE_MAX_WIDTH = 260

local function getIcon(appId)
	if appId == nil or appId == "" then
		return nil
	end

	if iconCache[appId] ~= nil then
		return iconCache[appId]
	end

	local path = noctalia.appIconPath(appId, ICON_SIZE)

	-- Cache false as well, so unresolved app IDs do not cause
	-- an icon-theme scan on every update.
	iconCache[appId] = path or false

	return path
end

local function position(window)
	if window.layout == nil then
		return nil, nil
	end

	local pos = window.layout.pos_in_scrolling_layout

	if pos == nil then
		return nil, nil
	end

	return pos[1], pos[2]
end

local function compareWindows(a, b)
	local acol, arow = position(a)
	local bcol, brow = position(b)

	-- Tiled windows come before floating windows.
	if acol == nil and bcol ~= nil then
		return false
	elseif acol ~= nil and bcol == nil then
		return true
	elseif acol == nil and bcol == nil then
		return a.id < b.id
	end

	-- Niri column order.
	if acol ~= bcol then
		return acol < bcol
	end

	-- Multiple windows inside one column are ordered top -> bottom.
	if arow ~= brow then
		return arow < brow
	end

	return a.id < b.id
end

local function focusWindow(id)
	noctalia.runAsync("niri msg action focus-window --id " .. tostring(id))
end

local function makeIcon(window)
	local path = getIcon(window.app_id)

	if path then
		return ui.image({
			key = "icon-" .. tostring(window.id),
			path = path,
			width = ICON_SIZE,
			height = ICON_SIZE,
			fit = "contain",
		})
	end

	-- Generic fallback if the app_id cannot be resolved to a .desktop icon.
	return ui.glyph({
		key = "icon-" .. tostring(window.id),
		name = "square",
		size = ICON_SIZE,
	})
end

local function makeWindow(window)
	local children = {
		makeIcon(window),
	}

	if window.is_focused then
		table.insert(
			children,
			ui.label({
				key = "title-" .. tostring(window.id),
				text = window.title or window.app_id or "",
				maxWidth = TITLE_MAX_WIDTH,
				maxLines = 1,
			})
		)
	end

	return ui.row({
		key = "window-" .. tostring(window.id),
		gap = ICON_GAP,
		align = "center",

		onClick = function()
			focusWindow(window.id)
		end,
	}, children)
end

local function render()
	local children = {}

	for _, window in ipairs(windows) do
		table.insert(children, makeWindow(window))
	end

	local container = barWidget.isVertical() and ui.column or ui.row

	barWidget.render(container({
		gap = WINDOW_GAP,
		align = "center",
	}, children))
end

local function processWindows(allWindows)
	local focused = nil

	for _, window in ipairs(allWindows) do
		if window.is_focused then
			focused = window
			break
		end
	end

	-- No normal Niri window currently owns keyboard focus.
	-- This happens, for example, while a launcher is open.
	if focused == nil then
		windows = {}
		render()
		return
	end

	local workspaceId = focused.workspace_id
	local filtered = {}

	for _, window in ipairs(allWindows) do
		if window.workspace_id == workspaceId then
			table.insert(filtered, window)
		end
	end

	table.sort(filtered, compareWindows)

	windows = filtered
	render()
end

local function queryWindows()
	if requestPending then
		return
	end

	requestPending = true

	local accepted = noctalia.runAsync("niri msg --json windows", function(result)
		requestPending = false

		if result.exitCode ~= 0 then
			noctalia.log("niri msg windows failed: " .. (result.stderr or ""))
			return
		end

		local decoded, err = noctalia.json.decode(result.stdout)

		if decoded == nil then
			noctalia.log("could not decode niri windows JSON: " .. tostring(err))
			return
		end

		processWindows(decoded)
	end)

	if not accepted then
		requestPending = false
	end
end

-- 250 ms is responsive without continuously spawning overlapping niri
-- requests. requestPending prevents a new process while the previous one
-- is still running.
noctalia.setUpdateInterval(250)

function update()
	queryWindows()
end
