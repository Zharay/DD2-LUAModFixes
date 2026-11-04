-- DD2 Volumetric Clouds (reframework/plugins/DD2Clouds.dll): in-game controls, in the REFramework menu under
-- "Script Generated UI" > "DD2 Clouds". They edit reframework/data/DD2Clouds/dd2_clouds.ini, which the add-on watches.
-- The add-on reads these keys at runtime (its settings buffer), so a change shows within a second, no recompile; with
-- "Live" on, the file is written a moment after a slider stops moving. Resolution divider still recompiles (1-2 min).
-- Comments and keys not shown here are kept as they are.

local INI = "DD2Clouds/dd2_clouds.ini"

-- key, label, min, max, default (the shader's default when the ini has no line for it), integer?
-- Light profiles are stored as <key>_day / <key>_night; the active profile is written to the original <key>.
local SECTIONS = {
  { "Sky cover", {
    { "coverage", "Cover", 0.0, 1.0, 0.45 },
    { "cover_vary", "Cover drift over time (+/-)", 0.0, 0.3, 0.1 },
    { "cover_period", "Drift period (minutes)", 2.0, 120.0, 20.0 },
    { "rain_cover", "Rain: sky closed", 0.0, 1.0, 0.85 },
    { "fill", "Fill (more / bigger clouds)", 0.5, 3.0, 1.5 },
    { "fair_cover_max", "Fair-weather max cover (gaps)", 0.3, 1.0, 0.45 },
    { "shape_size", "Cloud size (m)", 300, 4000, 2400 },
    { "weather_size", "Cloud field size (m)", 1000, 20000, 9000 },
    { "height_var", "Height variety", 0.0, 1.0, 0.45 },
    { "bottom", "Base altitude (m)", 300, 6000, 1500 },
    { "top", "Top altitude (m)", 800, 9000, 3200 },
  } },
  { "Shape", {
    { "billow", "Cauliflower (crowns)", 0.0, 1.0, 0.55 },
    { "base_billow", "Lumps (bases)", 0.0, 1.0, 0.3 },
    { "base_wisps", "Wisps (bases)", 0.0, 1.0, 0.35 },
    { "base_frizz", "Ragged bases", 0.0, 1.0, 0.3 },
    { "billow_size", "Billow size (m)", 50, 800, 260 },
    { "fine", "Fine detail", 0.0, 1.0, 0.45 },
    { "lumps", "Outline lumps", 0.0, 1.0, 0.45 },
    { "crown", "Crown rounding start", 0.0, 0.9, 0.35 },
    { "softness", "Edge softness", 0.03, 0.6, 0.25 },
    { "density", "Density", 0.01, 0.4, 0.035 },
    { "churn", "Boil speed (m/s)", 0.0, 5.0, 0.6 },
  } },
  { "Light (Day)", {
    { "exposure_day", "Brightness", 0.2, 3.0, 1.0 },
    { "sun_intensity_day", "Sunlight", 0.0, 10.0, 8.0 },
    { "ambient_day", "Sky light", 0.0, 12.0, 2.2 },
    { "base_dark_day", "Base sky light", 0.0, 1.0, 0.35 },
    { "amb_occ_day", "Dark bellies", 0.0, 1.0, 0.8 },
    { "amb_tint_day", "Sun tint in sky light", 0.0, 1.0, 0.5 },
    { "bounce_day", "Ground bounce", 0.0, 0.5, 0.12 },
    { "powder_day", "Powder (dark sun-side skin)", 0.0, 1.0, 0.6 },
    { "ms_day", "Light through thick cloud", 0.0, 1.0, 0.5 },
    { "phase_g_day", "Silver lining (forward glow)", 0.0, 0.95, 0.7 },
    { "shadow_day", "Cloud shadows on the ground", 0.0, 1.0, 0.65 },
    { "golden_tint_day", "Sunset colour in sky light", 0.0, 1.0, 0.65 },
    { "golden_sun_day", "Sunset sunlight boost", 1.0, 4.0, 2.0 },
    { "dusk_brightness_day", "Dusk / dawn brightness", 0.2, 4.0, 1.0 },
    { "sky_floor_day", "Dusk floor (vs sky behind)", 0.0, 1.0, 0.3 },
  } },
  { "Light (Night)", {
    { "exposure_night", "Brightness", 0.2, 3.0, 1.0 },
    { "sun_intensity_night", "Sunlight", 0.0, 10.0, 8.0 },
    { "ambient_night", "Sky light", 0.0, 12.0, 2.2 },
    { "base_dark_night", "Base sky light", 0.0, 1.0, 0.35 },
    { "amb_occ_night", "Dark bellies", 0.0, 1.0, 0.8 },
    { "amb_tint_night", "Sun tint in sky light", 0.0, 1.0, 0.5 },
    { "bounce_night", "Ground bounce", 0.0, 0.5, 0.12 },
    { "powder_night", "Powder (dark sun-side skin)", 0.0, 1.0, 0.6 },
    { "ms_night", "Light through thick cloud", 0.0, 1.0, 0.5 },
    { "phase_g_night", "Silver lining (forward glow)", 0.0, 0.95, 0.7 },
    { "shadow_night", "Cloud shadows on the ground", 0.0, 1.0, 0.65 },
    { "golden_tint_night", "Sunset colour in sky light", 0.0, 1.0, 0.65 },
    { "golden_sun_night", "Sunset sunlight boost", 1.0, 4.0, 2.0 },
    { "dusk_brightness_night", "Dusk / dawn brightness", 0.2, 4.0, 1.0 },
    { "sky_floor_night", "Dusk floor (vs sky behind)", 0.0, 1.0, 0.3 },
  } },
  { "Quality", {
    { "steps", "March steps", 16, 160, 64, true },
    { "light_steps", "Sun samples", 1, 8, 5, true },
    { "res_div", "Resolution divider", 1, 4, 2, true },
    { "temporal", "New frame weight", 0.02, 1.0, 0.12 },
  } },
}

local lines, values, pending = {}, {}, {}
local status = ""
local live, last_change = true, 0
local RECOMPILE = { res_div = true, enabled = true, sky_ibl = true }
local LIGHT_KEYS = {}
for _, sec in ipairs(SECTIONS) do
  if sec[1] == "Light (Day)" then
    for _, setting in ipairs(sec[2]) do
      LIGHT_KEYS[#LIGHT_KEYS + 1] = {
        key = setting[1]:match("^(.*)_day$"),
        default = setting[5],
      }
    end
  end
end
local active_is_night, exported_is_night = nil, nil
local next_time_poll = 0

local function parse_value(line)
  local key, val = line:match("^%s*([%w_]+)%s*=%s*([^#;\r]*)")
  if not key then return nil end
  return key, (val:gsub("%s+$", ""))
end

local function read_file()
  local new_lines, new_values = {}, {}
  local f = io.open(INI, "r")
  if not f then
    lines, values = {}, {}
    status = "could not read " .. INI
    return false
  end
  for line in f:lines() do
    new_lines[#new_lines + 1] = line
    local k, v = parse_value(line)
    if k then new_values[k] = v end
  end
  f:close()
  lines, values = new_lines, new_values
  status = "loaded"
  return true
end

local function load()
  read_file()
  pending = {}
end

-- replaces the value of each changed key in place (keeping its comment), appends keys the file did not have.
-- The file is read again first: the panel's copy dates from when it opened, and writing it back would undo edits
-- made since then by hand or by other tools.
local function write(changes)
  local done = {}
  for i, line in ipairs(lines) do
    local k = parse_value(line)
    if k and changes[k] ~= nil then
      lines[i] = line:gsub("^(%s*[%w_]+%s*=%s*)[^#;\r]*", "%1" .. changes[k] .. " ", 1)
      done[k] = true
    end
  end
  local append = {}
  for k in pairs(changes) do
    if not done[k] then append[#append + 1] = k end
  end
  table.sort(append)
  for _, k in ipairs(append) do lines[#lines + 1] = k .. " = " .. changes[k] end
  local f = io.open(INI, "w")
  if not f then status = "could not write " .. INI; return false end
  -- text mode: "\n" is written as CRLF ("\r\n" here made CR CR LF)
  for _, line in ipairs(lines) do
    local ok, err = f:write((line:gsub("\r+$", "")), "\n")
    if not ok then
      f:close()
      status = "could not write " .. INI .. ": " .. tostring(err)
      return false
    end
  end
  local ok, err = f:close()
  if not ok then
    status = "could not write " .. INI .. ": " .. tostring(err)
    return false
  end
  local slow = false
  for k, v in pairs(changes) do
    values[k] = v
    slow = slow or RECOMPILE[k] == true
  end
  status = "applied at " .. os.date("%H:%M:%S") .. (slow and ": this one recompiles the shader (1-2 min)" or "")
  return true
end

local function fmt(x, int)
  if int then return tostring(math.floor(x + 0.5)) end
  return string.format("%.4g", x)
end

local function save(force, include_pending)
  if not force and next(pending) == nil then return false end
  if include_pending == nil then include_pending = true end
  read_file()
  local changes = {}
  if include_pending then
    for k, v in pairs(pending) do changes[k] = v end
  end
  for _, setting in ipairs(LIGHT_KEYS) do
    local key = setting.key
    local day_key, night_key = key .. "_day", key .. "_night"
    changes[day_key] = (include_pending and pending[day_key]) or values[day_key] or values[key] or fmt(setting.default)
    changes[night_key] = (include_pending and pending[night_key]) or values[night_key] or values[key] or fmt(setting.default)
    if active_is_night ~= nil then
      changes[key] = active_is_night and changes[night_key] or changes[day_key]
    end
  end
  if not write(changes) then return false end
  if include_pending then pending = {} end
  exported_is_night = active_is_night
  return true
end

local function current(key, default)
  local v = pending[key] or values[key]
  if v == nil then
    local base = key:match("^(.*)_day$") or key:match("^(.*)_night$")
    if base then v = values[base] end
  end
  return tonumber(v) or default
end

re.on_frame(function()
  local now = os.clock()
  if now < next_time_poll then return end
  next_time_poll = now + 1.0
  local tm = sdk.get_managed_singleton("app.TimeManager")
  if tm ~= nil then
    local is_night = tm:isNight()
    if type(is_night) == "boolean" then active_is_night = is_night end
  end
  if active_is_night ~= nil and active_is_night ~= exported_is_night then
    save(true, false)
  end
end)

re.on_draw_ui(function()
  if not imgui.tree_node("DD2 Clouds") then return end
  if next(lines) == nil and status == "" then load() end

  local on = current("enabled", 1) > 0.5
  local changed, v = imgui.checkbox("Clouds on", on)
  if changed then pending.enabled = v and "1" or "0"; last_change = os.clock() end
  local ibl = current("sky_ibl", 1) > 0.5
  changed, v = imgui.checkbox("Clouds in reflections and sky light", ibl)
  if changed then pending.sky_ibl = v and "1" or "0"; last_change = os.clock() end

  for _, sec in ipairs(SECTIONS) do
    if imgui.tree_node(sec[1]) then
      for _, s in ipairs(sec[2]) do
        local key, label, lo, hi, def, int = s[1], s[2], s[3], s[4], s[5], s[6]
        local x = current(key, def)
        if int then
          changed, v = imgui.slider_int(label, math.floor(x + 0.5), lo, hi)
        else
          changed, v = imgui.slider_float(label, x, lo, hi)
        end
        if changed then pending[key] = fmt(v, int); last_change = os.clock() end
      end
      imgui.tree_pop()
    end
  end

  local n = 0
  for _ in pairs(pending) do n = n + 1 end
  changed, live = imgui.checkbox("Live", live)
  imgui.same_line()
  if live and n > 0 and os.clock() - last_change > 0.3 then save(); n = 0 end
  if imgui.button(n > 0 and ("Apply " .. n .. " change(s)") or "Apply") and n > 0 then save() end
  imgui.same_line()
  if imgui.button("Revert / reload file") then load() end
  if status ~= "" then imgui.text(status) end
  imgui.tree_pop()
end)
