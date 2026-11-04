-- DD2 Volumetric Clouds (reframework/plugins/DD2Clouds.dll): in-game controls, in the REFramework menu under
-- "Script Generated UI" > "DD2 Clouds". They edit reframework/data/DD2Clouds/dd2_clouds.ini, which the add-on watches.
-- The add-on reads these keys at runtime (its settings buffer), so a change shows within a second, no recompile; with
-- "Live" on, the file is written a moment after a slider stops moving. Resolution divider still recompiles (1-2 min).
-- Comments and keys not shown here are kept as they are.

local INI = "DD2Clouds/dd2_clouds.ini"

-- key, label, min, max, default (the shader's default when the ini has no line for it), integer?
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
  { "Light", {
    { "exposure", "Brightness", 0.2, 3.0, 1.0 },
    { "sun_intensity", "Sunlight", 0.0, 10.0, 8.0 },
    { "ambient", "Sky light", 0.0, 12.0, 2.2 },
    { "base_dark", "Base sky light", 0.0, 1.0, 0.35 },
    { "amb_occ", "Dark bellies", 0.0, 1.0, 0.8 },
    { "amb_tint", "Sun tint in sky light", 0.0, 1.0, 0.5 },
    { "bounce", "Ground bounce", 0.0, 0.5, 0.12 },
    { "powder", "Powder (dark sun-side skin)", 0.0, 1.0, 0.6 },
    { "ms", "Light through thick cloud", 0.0, 1.0, 0.5 },
    { "phase_g", "Silver lining (forward glow)", 0.0, 0.95, 0.7 },
    { "shadow", "Cloud shadows on the ground", 0.0, 1.0, 0.65 },
    { "golden_tint", "Sunset colour in sky light", 0.0, 1.0, 0.65 },
    { "golden_sun", "Sunset sunlight boost", 1.0, 4.0, 2.0 },
    { "dusk_brightness", "Dusk / dawn brightness", 0.2, 4.0, 1.0 },
    { "sky_floor", "Dusk floor (vs sky behind)", 0.0, 1.0, 0.3 },
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

local function parse_value(line)
  local key, val = line:match("^%s*([%w_]+)%s*=%s*([^#;\r]*)")
  if not key then return nil end
  return key, (val:gsub("%s+$", ""))
end

local function load()
  lines, values = {}, {}
  local f = io.open(INI, "r")
  if not f then status = "could not read " .. INI; return end
  for line in f:lines() do
    lines[#lines + 1] = line
    local k, v = parse_value(line)
    if k then values[k] = v end
  end
  f:close()
  pending = {}
  status = "loaded"
end

-- replaces the value of each changed key in place (keeping its comment), appends keys the file did not have.
-- The file is read again first: the panel's copy dates from when it opened, and writing it back would undo edits
-- made since then by hand or by other tools.
local function save()
  local f = io.open(INI, "r")
  if f then
    lines = {}
    for line in f:lines() do
      lines[#lines + 1] = line
      local k, v = parse_value(line)
      if k then values[k] = v end
    end
    f:close()
  end
  local done = {}
  for i, line in ipairs(lines) do
    local k = parse_value(line)
    if k and pending[k] ~= nil then
      lines[i] = line:gsub("^(%s*[%w_]+%s*=%s*)[^#;\r]*", "%1" .. pending[k] .. " ", 1)
      done[k] = true
    end
  end
  for k, v in pairs(pending) do
    if not done[k] then lines[#lines + 1] = k .. " = " .. v end
  end
  f = io.open(INI, "w")
  if not f then status = "could not write " .. INI; return end
  -- text mode: "\n" is written as CRLF ("\r\n" here made CR CR LF)
  for _, line in ipairs(lines) do f:write((line:gsub("\r+$", "")), "\n") end
  f:close()
  local slow = false
  for k, v in pairs(pending) do
    values[k] = v
    slow = slow or RECOMPILE[k] == true
  end
  pending = {}
  status = "applied at " .. os.date("%H:%M:%S") .. (slow and ": this one recompiles the shader (1-2 min)" or "")
end

local function current(key, default)
  local v = pending[key] or values[key]
  return tonumber(v) or default
end

local function fmt(x, int)
  if int then return tostring(math.floor(x + 0.5)) end
  return string.format("%.4g", x)
end

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
