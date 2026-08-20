-- Niri window strip for Noctalia v5
--
-- Displays windows from the currently focused workspace in Niri's
-- scrolling-layout order.
--
--   inactive window -> icon
--   focused window  -> icon + title
--
-- Clicking any item focuses that window.

local function configNumber(key, fallback)
	local value = noctalia.getConfig(key)

	if value == nil or value == 0 then
		return fallback
	end

	return tonumber(value) or fallback
end

local function iconSize()
	return configNumber("icon_size", nil)
end

local function iconGap()
	return configNumber("icon_gap", 6)
end

local function windowGap()
	return configNumber("window_gap", 6)
end

local function titleMaxWidth()
	return configNumber("title_max_width", nil)
end

local windows = {}
local requestPending = false

local iconCache = {}

local function getIcon(appId)
	if appId == nil or appId == "" then
		return nil
	end

	local size = iconSize()
	local cacheKey = appId .. ":" .. tostring(size or "auto")

	if iconCache[cacheKey] ~= nil then
		return iconCache[cacheKey]
	end

	local lookupSize = size or 24
	local path = noctalia.appIconPath(appId, lookupSize)

	iconCache[cacheKey] = path or false

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
	local size = iconSize()

	if path then
		local props = {
			key = "icon-" .. tostring(window.id),
			path = path,
			fit = "contain",
		}
		if size ~= nil then
			props.width = size
			props.height = size
		end

		return ui.image(props)
	end

	local props = {
		key = "icon-" .. tostring(window.id),
		name = "square",
	}
	if size ~= nil then
		props.size = size
	end

	return ui.glyph(props)
end

local function makeWindow(window)
	local children = {
		makeIcon(window),
	}

	if window.is_focused then
		local labelProps = {
			key = "title-" .. tostring(window.id),
			text = window.title or window.app_id or "",
			maxLines = 1,
		}

		local maxWidth = titleMaxWidth()

		if maxWidth ~= nil then
			labelProps.maxWidth = maxWidth
		end

		table.insert(children, ui.label(labelProps))
	end

	return ui.row({
		key = "window-" .. tostring(window.id),
		gap = iconGap(),
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
		gap = windowGap(),
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
