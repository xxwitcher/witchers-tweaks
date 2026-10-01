-- Witcher's Tweaks for Hyprland.
--
-- Loaded at the end of ~/.config/hypr/hyprland.lua (a marked block the
-- installer adds), after Omarchy's defaults and your own input, bindings and
-- looknfeel files, which this never replaces. Each tweak below runs only when
-- its name is listed in ~/.config/witchers-tweaks/tweaks.conf, one per line;
-- the installer keeps that list (Setup > Witcher's Tweaks, or install.sh).

local home = os.getenv("HOME")
local state = home .. "/.config/witchers-tweaks"

local function read_lines(path)
  local lines = {}
  local file = io.open(path, "r")
  if not file then return lines end
  for line in file:lines() do lines[#lines + 1] = line end
  file:close()
  return lines
end

local enabled = {}
for _, line in ipairs(read_lines(state .. "/tweaks.conf")) do
  local name = line:match("^%s*([%w%-]+)%s*$")
  if name then enabled[name] = true end
end

local function on(name) return enabled[name] == true end

-- ---------------------------------------------------------------- settings app

-- The Settings app opens as a floating window, like macOS's System Settings,
-- and what it saves (input settings, custom shortcuts) is loaded here, before
-- the tweaks below so they build on it (swapkeys adds to its keyboard
-- options).
if on("settings-app") then
  o.window("^(org\\.witcher\\.settings)$", { float = true, center = true, size = { 980, 680 } })
  local settings = loadfile(state .. "/settings.lua")
  if settings then
    local ok, err = pcall(settings)
    if not ok then
      hl.exec_cmd("notify-send 'Witcher Settings' " .. string.format("%q", "settings.lua: " .. tostring(err)))
    end
  end
end

-- ---------------------------------------------------------------- look

if on("no-gaps") then
  hl.config({ general = { gaps_in = 0, gaps_out = 0 } })
end

-- The scrolling layout shows one column per screen instead of two.
if on("wide-columns") then
  hl.config({ scrolling = { column_width = 0.97 } })
end

-- Workspaces slide in with a fade instead of switching instantly.
-- Window corners rounded by the percentage in rounding.conf (Setup >
-- Witcher's Tweaks > Configure > Corners): 0 is sharp, 100 % a 32 px radius,
-- the same scale as the dock's corner rounding.
if on("window-rounding") then
  for _, line in ipairs(read_lines(state .. "/rounding.conf")) do
    local percent = tonumber(line:match("^%s*roundness%s*=%s*(%d+)%s*$"))
    if percent then
      hl.config({ decoration = { rounding = math.floor(math.min(100, percent) * 32 / 100 + 0.5) } })
    end
  end
end

if on("workspace-fade") then
  hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slidefade 20%" })
end

-- A three-color gradient border (light, main, accent) spinning around the
-- active window, and an inactive color. The colors come from border.conf,
-- which the border picker writes (default purple):
--
--   active=c4b5fd a855f7 da70d6
--   inactive=5b3a7a
--
-- The picker previews live by replacing _G.witcher_border, so the spinning
-- gradient reads it on every tick.
if on("gradient-border") then
  local border = { active = { "c4b5fd", "a855f7", "da70d6" }, inactive = "5b3a7a" }
  for _, line in ipairs(read_lines(state .. "/border.conf")) do
    local key, value = line:match("^%s*(%w+)%s*=%s*(.-)%s*$")
    if key == "active" then
      local colors = {}
      for hex in value:gmatch("%x%x%x%x%x%x") do colors[#colors + 1] = hex:lower() end
      if #colors == 3 then border.active = colors end
    elseif key == "inactive" and value:match("^%x%x%x%x%x%x$") then
      border.inactive = value:lower()
    end
  end
  _G.witcher_border = border

  -- Colors are evenly spaced around the border, so repeating one gives it
  -- more of it: 3 parts light, 3 main, 2 accent.
  function _G.witcher_border_gradient(b)
    local out, weights = {}, { 3, 3, 2 }
    for i, hex in ipairs(b.active) do
      for _ = 1, weights[i] do out[#out + 1] = "rgba(" .. hex .. "ee)" end
    end
    return out
  end

  hl.config({
    general = {
      col = {
        active_border = { colors = _G.witcher_border_gradient(border), angle = 45 },
        inactive_border = "rgba(" .. border.inactive .. "aa)",
      },
    },
  })

  -- Hyprland's borderangle "loop" animation stops after one turn on 0.56, so
  -- a timer turns the gradient instead: one turn every ~13 s at ~30 fps. The
  -- one timer for the session calls a tick every reload redefines, so edits
  -- here and new colors apply without restarting Hyprland.
  local spin_seconds, spin_interval = 13.33, 33
  _G.witcher_border_angle = _G.witcher_border_angle or 45
  function _G.witcher_border_tick()
    _G.witcher_border_angle = (_G.witcher_border_angle + 360 * spin_interval / (spin_seconds * 1000)) % 360
    hl.config({ general = { col = { active_border = { colors = _G.witcher_border_gradient(_G.witcher_border), angle = _G.witcher_border_angle } } } })
  end
  if not _G.witcher_border_timer then
    _G.witcher_border_timer = hl.timer(function()
      if _G.witcher_border_tick then _G.witcher_border_tick() end
    end, { timeout = spin_interval, type = "repeat" })
  end
else
  -- Turned off: the timer (which outlives reloads) has nothing to do.
  _G.witcher_border_tick = nil
end

-- ---------------------------------------------------------------- input

-- Left Ctrl and left Super trade places; right Ctrl and right Super stay.
-- Added to whatever keyboard options are already set rather than replacing
-- them.
if on("swap-ctrl-super") then
  local options = hl.get_config("input.kb_options")
  options = type(options) == "string" and options or ""
  if not options:find("ctrl:swap_lwin_lctl", 1, true) then
    options = options == "" and "ctrl:swap_lwin_lctl" or options .. ",ctrl:swap_lwin_lctl"
    hl.config({ input = { kb_options = options } })
  end
end

-- Caps Lock turns on capitals. Omarchy makes it the compose key, so only that
-- option is taken out and the rest are kept.
if on("caps-lock") then
  local options = hl.get_config("input.kb_options")
  options = type(options) == "string" and options or ""
  local kept = {}
  for option in options:gmatch("[^,]+") do
    if option ~= "compose:caps" then table.insert(kept, option) end
  end
  local new = table.concat(kept, ",")
  if new ~= options then
    hl.config({ input = { kb_options = new } })
  end
end

-- 3-finger horizontal swipe between workspaces, tuned to feel like macOS: a
-- short swipe is enough and a quick flick commits.
if on("workspace-swipe") then
  hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
  hl.config({
    gestures = {
      workspace_swipe_distance = 150, -- px for a full swipe (default 300)
      workspace_swipe_cancel_ratio = 0.15, -- commit after 15% instead of 50%
      workspace_swipe_min_speed_to_force = 5, -- a quick flick switches (default 30)
      workspace_swipe_create_new = true, -- past the last workspace makes a new one
      workspace_swipe_forever = true, -- keep going past neighbours in one swipe
    },
  })
end

-- 3-finger swipe up opens the window overview, down closes it.
-- Title bars on floating windows: the hyprbars plugin (built for this
-- Hyprland by titlebars/build-hyprbars) as an invisible strip just above the
-- window's top edge, to drag it by (double-click maximizes). The close,
-- minimize and maximize buttons pop up over the strip's left end on hover
-- (the witcher.titlebars shell plugin). Tiled windows get no strip. A build
-- for another Hyprland version doesn't load (Hyprland checks), so after an
-- update it just waits for the rebuild.
local function titlebars()
  local so = home .. "/.local/share/witchers-tweaks/hyprbars/hyprbars.so"
  local built_for = read_lines(home .. "/.local/share/witchers-tweaks/hyprbars/built-for")[1]
  -- hl.plugin.load only lists the plugin; Hyprland loads it after the parse.
  -- It has to be listed on every parse, loaded or not: one that goes unlisted
  -- is unloaded and the config reloaded, which would list it again, and
  -- Hyprland would loop there forever (it hung at login that way).
  if built_for then pcall(hl.plugin.load, so) end

  if hl.plugin.hyprbars then
    hl.config({ plugin = { hyprbars = {
      bar_height = 14,
      bar_color = "rgba(00000000)",
      bar_title_enabled = false,
      bar_part_of_window = false,
      bar_precedence_over_border = false,
      bar_blur = false,
      on_double_click = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })'",
    } } })
    hl.window_rule({ match = { float = false }, ["hyprbars:no_bar"] = true })
    -- Maximized (and fullscreen) windows reach every edge; their buttons
    -- move to the top bar.
    hl.window_rule({ match = { fullscreen = true }, ["hyprbars:no_bar"] = true })
  end
end
-- A mistake here mustn't stop the rest of the tweaks from loading.
if on("titlebars") then
  local ok, err = pcall(titlebars)
  if not ok then hl.exec_cmd("notify-send 'Witcher title bars' " .. string.format("%q", tostring(err))) end
end

-- Floating windows resize by dragging their border. Hyprland's switch for it
-- covers every window, so it's on only while the focused window is floating
-- (and not fullscreen); tiled windows never resize this way. It follows
-- Hyprland's own events, so nothing polls.
if on("float-border-resize") then
  local resizing = nil
  local function follow()
    local w = hl.get_active_window()
    local want = w ~= nil and w.floating == true and (tonumber(w.fullscreen) or 0) == 0
    if want ~= resizing then
      resizing = want
      hl.config({ general = { resize_on_border = want } })
    end
  end
  for _, event in ipairs({ "window.active", "window.update_rules", "window.fullscreen", "window.close", "workspace.active" }) do
    hl.on(event, function() pcall(follow) end)
  end
  pcall(follow)
end

if on("overview-gesture") then
  hl.gesture({ fingers = 3, direction = "up", action = function()
    hl.dispatch(hl.dsp.exec_cmd("omarchy-shell -q shell summon witcher.overview '{}'"))
  end })
  hl.gesture({ fingers = 3, direction = "down", action = function()
    hl.dispatch(hl.dsp.exec_cmd("omarchy-shell -q shell hide witcher.overview"))
  end })
end

-- ---------------------------------------------------------------- keybindings

if on("bind-browser") then
  hl.unbind("SUPER + SHIFT + B")
  o.bind("SUPER + B", "Browser", { omarchy = "browser" })
end

if on("bind-agent") then
  hl.unbind("SUPER + SHIFT + A")
  o.bind("SUPER + A", "Agent", "omarchy-agent")
end

if on("bind-close") then
  o.bind("CTRL + Q", "Close window", hl.dsp.window.close())
end

-- ---------------------------------------------------------------- dock

-- SUPER+M minimizes the focused window, like CMD+M on macOS: it goes to a
-- hidden special workspace, and the dock shows it (or its app) to bring it
-- back.
if on("dock-minimize") then
  -- Through the dock, which animates it without a blink; straight to the
  -- minimized workspace when the dock isn't running.
  o.bind("SUPER + M", "Minimize window",
    "omarchy-shell witcher.dock minimize active >/dev/null 2>&1 || hyprctl dispatch 'hl.dsp.window.move({ workspace = \"special:minimized\", follow = false })'")
end

-- ---------------------------------------------------------------- top bar

-- Hides the bar until the cursor touches the top edge of the screen.
if on("autohide-bar") then
  o.launch_on_start(home .. "/.local/share/witchers-tweaks/autohide-bar")
end
