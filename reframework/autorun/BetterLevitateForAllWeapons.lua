local modname = "BetterLevitateForAllWeapons"
local sdk = sdk
local log = log
local json = json
local re  = re

local hk = require("Hotkeys/Hotkeys")

local default_hotkeys = {
    ["Jump"]              = "A (X)",
    ["Jump2"]             = "Space",
    ["CancelLevitation"]  = "RT (R2)",
    ["CancelLevitation2"] = "E",
}
local lss = hk.recurse_def_settings({}, { hotkeys = default_hotkeys })
hk.setup_hotkeys(lss.hotkeys, default_hotkeys)

-- ===================== DEFAULT SETTINGS (edit here) =====================
-- Levitate for all weapons:
local DEFAULT_ALL_WEAPONS     = false    -- let every weapon levitate (not just Sorcerer/Mage)

-- Better Levitate (custom levitation values):
local DEFAULT_BETTER_LEVITATE = true   -- false = vanilla values, true = the values below
local DEFAULT_MAX_HEIGHT      = 6.0     -- max rise height
local DEFAULT_MAX_DURATION    = 8.0     -- how long levitation lasts (seconds)
local DEFAULT_MOVE_SPEED      = 6.0     -- horizontal move speed while levitating
-- ========================================================================

local NORMAL = { MaxHeight = 2.0, MaxKeepSec = 2.8, MoveSpeed = 0.0 }  -- vanilla game values
local BETTER = { MaxHeight = DEFAULT_MAX_HEIGHT, MaxKeepSec = DEFAULT_MAX_DURATION, MoveSpeed = DEFAULT_MOVE_SPEED }

local CFG_FILE = "BetterLevitate.json"
local cfg = json.load_file(CFG_FILE) or {}
if cfg.enabled == nil then cfg.enabled = DEFAULT_BETTER_LEVITATE end
if cfg.allWeapons == nil then cfg.allWeapons = DEFAULT_ALL_WEAPONS end
cfg.MaxHeight  = cfg.MaxHeight  or BETTER.MaxHeight
cfg.MaxKeepSec = cfg.MaxKeepSec or BETTER.MaxKeepSec
cfg.MoveSpeed  = cfg.MoveSpeed  or BETTER.MoveSpeed
local function save_cfg() pcall(function() json.dump_file(CFG_FILE, cfg) end) end

local function Log(message, level)
    level = level or "info"
    local previousLevel = log.get_level and log.get_level() or "error"
    log.set_level(level)
    local ok, err = pcall(log[level], "["..modname.."] "..message)
    log.set_level(previousLevel)
    if not ok then error(err, 0) end
end

local function cur_values()
    if cfg.enabled then
        return cfg.MaxHeight, cfg.MaxKeepSec, cfg.MoveSpeed
    end
    return NORMAL.MaxHeight, NORMAL.MaxKeepSec, NORMAL.MoveSpeed
end

local function apply_params(lev)
    if not lev then return end
    pcall(function()
        local p = lev:get_field("Param")
        if not p then return end
        local mh, mk = cur_values()
        p:set_field("MaxHeight", mh)
        p:set_field("MaxKeepSec", mk)
    end)
end

local function apply_move_boost(human, lev)
    local _, _, moveSpeed = cur_values()
    if moveSpeed <= 0 then return end
    pcall(function()
        local ms = human:get_field("MoveSpeedTypeValueInternal") or 0
        if ms > 0 then
            lev:set_field("HorizontalSpeed", moveSpeed * (ms / 3))
        end
    end)
end

local function enum(typename)
    local t = sdk.find_type_definition(typename)
    if not t then return {} end
    local e = {}
    for _, f in ipairs(t:get_fields()) do
        if f:is_static() then e[f:get_name()] = f:get_data(nil) end
    end
    return e
end
local UpDown = enum("app.LevitateController.UpDownModeEnum")

local g_forceFall = false

local cachedAction = nil
local cachedArg    = nil

local la_def    = sdk.find_type_definition("app.LevitateAction")
local la_start  = la_def:get_method("start")
local la_update = la_def:get_method("update")
local la_end    = la_def:get_method("end")
local la_selectFirst = la_def:get_method("selectFirstRoutine")
local la_startLev    = la_def:get_method("startLevitate")

local ct_def   = sdk.find_type_definition("app.LevitateController")
local c_start  = ct_def:get_method("start")
local c_update = ct_def:get_method("update")
local c_end    = ct_def:get_method("end")

-- Resolve field offsets from runtime metadata; hard-coded offsets went stale after game updates.
local function field_offset(tdef, name)
    if not tdef then return nil end
    local f = tdef:get_field(name)
    return f and f:get_offset_from_base() or nil
end
local OFF = {
    routine  = field_offset(la_def, "<Routine>k__BackingField"),
    prevMove = field_offset(la_def, "PrevMoveSpeedTypeValue"),
    isStart  = field_offset(la_def, "IsStartAction"),
    human    = field_offset(sdk.find_type_definition("app.UseHumanAction"), "Human"),
    levTimer = field_offset(ct_def, "Timer"),
}
local ACTION_OFFSETS_OK = OFF.routine ~= nil and OFF.prevMove ~= nil and OFF.isStart ~= nil
local CREATE_ACTION_OK  = ACTION_OFFSETS_OK and OFF.human ~= nil
if not CREATE_ACTION_OK then
    Log("LevitateAction layout not found; custom levitation disabled", "warn")
else
    Log("LevitateAction layout found; custom levitation enabled", "info")
end

local _lastClock = os.clock()
local function get_dt()
    local now = os.clock()
    local dt = now - _lastClock
    _lastClock = now
    if dt <= 0.0 or dt > 0.1 then dt = 0.0166 end
    return dt
end

local snapRoutine, snapPrevMove, snapIsStart = nil, nil, nil
local replaying = false
local nativeLevitating = false
local g_freshCast = false
local g_nativeVocation = false
local lastStartClock = 0
local lastLevUpdateClock = 0

sdk.hook(la_start,
    function(args)
        if g_nativeVocation then return end
        if not replaying then nativeLevitating = true end
        local action = sdk.to_managed_object(args[2])
        local arg    = sdk.to_managed_object(args[3])
        if action and arg then
            cachedAction = action:add_ref()
            cachedArg    = arg:add_ref()
        end
    end,
    function(retval)
        if g_nativeVocation then return retval end
        if cachedAction and not replaying and ACTION_OFFSETS_OK then
            pcall(function()
                local isStart = cachedAction:read_byte(OFF.isStart)
                if isStart == 1 then
                    if g_freshCast then
                        g_freshCast = false
                        snapRoutine  = cachedAction:read_dword(OFF.routine)
                        snapPrevMove = cachedAction:read_dword(OFF.prevMove)
                        snapIsStart  = isStart
                    else
                        cachedAction:write_byte(OFF.isStart, 0)
                        cachedAction:write_dword(OFF.routine, 2)
                    end
                end
            end)
        end
        return retval
    end
)

sdk.hook(la_update,
    function(args) lastLevUpdateClock = os.clock() end,
    function(retval) return retval end
)

sdk.hook(la_end,
    function(args)
        if not replaying then nativeLevitating = false end
    end,
    function(retval) return retval end
)

local function action_start()
    if cachedAction and cachedArg then
        replaying = true
        local ok = pcall(function() la_start:call(cachedAction, cachedArg) end)
        replaying = false
        if snapRoutine ~= nil and ACTION_OFFSETS_OK then
            pcall(function()
                cachedAction:write_dword(OFF.routine, snapRoutine)
                cachedAction:write_dword(OFF.prevMove, snapPrevMove)
                cachedAction:write_byte(OFF.isStart, snapIsStart)
            end)
        end
        return ok
    end
    return false
end
local function action_update()
    if cachedAction and cachedArg then
        pcall(function() la_update:call(cachedAction, cachedArg) end)
    end
end
local function action_end()
    if cachedAction and cachedArg then
        pcall(function() la_end:call(cachedAction, cachedArg) end)
    end
end
local function has_cached_action() return cachedAction ~= nil and cachedArg ~= nil end

local keepAlive = {}
local function create_action(human)
    if not CREATE_ACTION_OK then return false end
    local ok = pcall(function()
        if cachedAction then keepAlive[#keepAlive + 1] = cachedAction end
        if cachedArg then keepAlive[#keepAlive + 1] = cachedArg end
        if #keepAlive > 40 then table.remove(keepAlive, 1); table.remove(keepAlive, 1) end
        local chara = human:call("get_Chara()")
        local act = sdk.create_instance("app.LevitateAction")
        local arg = sdk.create_instance("via.behaviortree.ActionArg")
        if not act or not arg then return end
        act = act:add_ref()
        arg = arg:add_ref()
        -- Native start/update expect the original hand-built layout (Chara at +0x20), not the reflected field.
        if chara then act:write_qword(0x20, chara:get_address()) end
        act:write_qword(OFF.human, human:get_address())
        act:write_dword(0x10, 0x33062E7A)
        cachedAction = act
        cachedArg    = arg
        snapRoutine  = 0
        snapPrevMove = 0
        snapIsStart  = 1
    end)
    return ok and has_cached_action()
end

local set_node = sdk.find_type_definition("via.motion.MotionFsm2Layer")
    :get_method("setCurrentNode(System.String, via.behaviortree.SetNodeInfo, via.motion.SetMotionTransitionInfo)")
local setn = ValueType.new(sdk.find_type_definition("via.behaviortree.SetNodeInfo"))
setn:call("set_Fullname", true)
local interp = sdk.create_instance("via.motion.SetMotionTransitionInfo"):add_ref()
interp:set_InterpolationFrame(20.0)

local LEVITATE_START_NODES = {
    "JobMagicUser.JobMagicUser_StartLevitate",
    "Job03.Job03_StartLevitate",
    "Job10.Job10_StartLevitate",
    "Common.Common_StartLevitate",
}
local LEVITATE_END_NODES = {
    "JobMagicUser.JobMagicUser_EndLevitate",
    "Job03.Job03_EndLevitate",
    "Job10.Job10_EndLevitate",
}

local function try_anim_start(mfsm2)
    local layerCount = mfsm2:getLayerCount()
    for li = 0, layerCount - 1 do
        local layer = mfsm2:getLayer(li)
        if layer then
            for _, node in ipairs(LEVITATE_START_NODES) do
                local ok = pcall(function()
                    set_node:call(layer, node, setn, interp)
                end)
                if ok then return true end
            end
        end
    end
    return false
end

local function try_anim_end(mfsm2)
    local layerCount = mfsm2:getLayerCount()
    for li = 0, layerCount - 1 do
        local layer = mfsm2:getLayer(li)
        if layer then
            for _, node in ipairs(LEVITATE_END_NODES) do
                local ok = pcall(function() set_node:call(layer, node, setn, interp) end)
                if ok then return end
            end
        end
    end
end

local function try_anim(mfsm2, node)
    pcall(function() set_node:call(mfsm2:getLayer(0), node, setn, interp) end)
end

local function get_human()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return nil end
    local p = cm:get_ManualPlayer()
    if not p then return nil end
    return p:get_Human()
end

local function get_lev_ctrl(human)
    return human and human:get_LevitateCtrl()
end

local function get_char_ctrl(human)
    local chara = human and human:call("get_Chara()")
    return chara and chara:call("get_CharaController()")
end

local function get_mfsm2(human)
    local go = human and human:get_GameObject()
    return go and go:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
end

local function is_grounded(human, chara, ctrl)
    if chara then
        local r
        local ok = pcall(function() r = chara:call("get_IsGround") end)
        if ok and type(r) == "boolean" then return r end
    end
    local j = true
    pcall(function() j = ctrl:call("get_Jump()") end)
    return not j
end

local GamePad_t  = sdk.find_type_definition("via.hid.GamePad")
local function get_stick()
    local gs = sdk.get_native_singleton("via.hid.GamePad")
    if not gs then return 0, 0 end
    if not GamePad_t then return 0, 0 end
    local dev
    pcall(function() dev = sdk.call_native_func(gs, GamePad_t, "get_MergedDevice") end)
    if not dev then return 0, 0 end
    local ax
    pcall(function() ax = dev:call("get_AxisL") end)
    if not ax then pcall(function() ax = dev:call("getAxisL") end) end
    if not ax then return 0, 0 end
    local x, y = nil, nil
    pcall(function() x = ax.x; y = ax.y end)
    return x or 0, y or 0
end

local function get_buttons_down()
    local gs = sdk.get_native_singleton("via.hid.GamePad")
    if not gs or not GamePad_t then return 0 end
    local dev
    pcall(function() dev = sdk.call_native_func(gs, GamePad_t, "get_MergedDevice") end)
    if not dev then return 0 end
    local b = 0
    pcall(function() b = dev:call("get_ButtonDown") end)
    return b or 0
end

local function get_buttons_held()
    local gs = sdk.get_native_singleton("via.hid.GamePad")
    if not gs or not GamePad_t then return 0 end
    local dev
    pcall(function() dev = sdk.call_native_func(gs, GamePad_t, "get_MergedDevice") end)
    if not dev then return 0 end
    local b = 0
    pcall(function() b = dev:call("get_Button") end)
    return b or 0
end

local TURN_LERP = 0.25
local RISE_START_SPEED = 1.5
local GRAB_BUTTON = 0x800
local NATIVE_FIRST = false
local g_steerYaw = 0.0
local g_steerMag = 0.0
local g_steerOn  = false
local g_levActive = false
local g_riseHold = false
local g_grabbed = false

local function request_fall(lev, human)
    if g_forceFall then return end
    g_forceFall = true
    pcall(function()
        local mk = 2.8
        local p = lev:get_field("Param")
        if p then mk = p:get_field("MaxKeepSec") or 2.8 end
        if OFF.levTimer then lev:write_float(OFF.levTimer, mk + 0.05) end
    end)
    pcall(function() lev:set_field("<IsActive>k__BackingField", false) end)
    pcall(function() c_end:call(lev) end)
end

local function apply_turn(human, dbg)
    g_steerOn = false
    local sx, sy = get_stick()
    if (sx * sx + sy * sy) < 0.04 then return end
    local cam = sdk.get_primary_camera()
    if not cam then return end
    local cam_go = cam:call("get_GameObject")
    local cam_tr = cam_go and cam_go:call("get_Transform")
    if not cam_tr then return end
    local fwd = cam_tr:call("get_AxisZ")
    local rgt = cam_tr:call("get_AxisX")
    if not fwd or not rgt then return end
    local fy = -sy
    local dx = rgt.x * sx + fwd.x * fy
    local dz = rgt.z * sx + fwd.z * fy
    if (dx * dx + dz * dz) < 1e-6 then return end
    local yaw = math.atan(dx, dz)
    local go = human:get_GameObject()
    local tr = go and go:call("get_Transform")
    if not tr then return end
    local q = Quaternion.new(0, 0, 0, 1)
    q.x = 0.0
    q.y = math.sin(yaw * 0.5)
    q.z = 0.0
    q.w = math.cos(yaw * 0.5)
    tr:call("set_Rotation", q)
    g_steerYaw = math.deg(yaw)
    g_steerMag = math.min(1.0, math.sqrt(sx * sx + sy * sy))
    g_steerOn  = true
end

local IDLE     = 0
local RISING   = 1
local HOVERING = 2
local ACTIVE   = 3

local state     = IDLE
local jumpCount = 0
local lastJump  = false
local levitatedSinceGround = false
local riseFrames = 0
local activeFrames = 0
local fallFrames = 0

sdk.hook(c_update,
    function(args)
        if g_grabbed then
            pcall(function()
                local c = sdk.to_managed_object(args[2])
                if c then c:set_field("<IsActive>k__BackingField", false) end
            end)
            return
        end
        if g_levActive then
            pcall(function()
                if g_riseHold and not g_forceFall then args[4] = sdk.to_ptr(1) end
                if g_steerOn then
                    args[5] = sdk.to_ptr(0)
                    args[7] = sdk.float_to_ptr(g_steerYaw)
                    args[8] = sdk.float_to_ptr(g_steerMag)
                end
            end)
        end
    end,
    function(retval) return retval end
)

local hookedHuman = nil
sdk.hook(
    sdk.find_type_definition("app.Human"):get_method("updateMoveOnAir"),
    function(args)
        hookedHuman = sdk.to_managed_object(args[2])
    end,
    function(retval)
        return retval
    end
)

local pIP = nil
sdk.hook(
    sdk.find_type_definition("app.PlayerInputProcessor"):get_method("processMove()"),
    function(args) pIP = sdk.to_managed_object(args[2]) end,
    function(rtVal)
        return rtVal
    end
)

re.on_application_entry("LateUpdateBehavior", function()
    local human = get_human()
    if not human then return end

    local lev      = get_lev_ctrl(human)
    local ctrl     = get_char_ctrl(human)
    if not lev or not ctrl then return end

    do
        local chara = human:call("get_Chara()")
        local job = -1
        if chara then
            for _, m in ipairs({ "calcWeaponJob", "getWeaponJob", "get_WeaponJob" }) do
                local r
                pcall(function() r = chara:call(m) end)
                if type(r) == "number" and r >= 0 then job = r; break end
            end
        end
        g_nativeVocation = (job == 6 or job == 3)
        if g_nativeVocation then
            apply_params(lev)
            apply_move_boost(human, lev)
            g_steerOn  = false
            g_riseHold = false
            if state ~= IDLE then state = IDLE; jumpCount = 0 end
            return
        end
    end

    if not cfg.allWeapons then
        g_steerOn  = false
        g_riseHold = false
        g_levActive = false
        g_forceFall = false
        if state ~= IDLE then state = IDLE; jumpCount = 0 end
        return
    end

    g_levActive = false
    pcall(function() g_levActive = lev:get_field("<IsActive>k__BackingField") == true end)
    g_riseHold = hk.check_hotkey("Jump", true) or hk.check_hotkey("Jump2", true)
    if g_levActive then
        if ((get_buttons_held() | get_buttons_down()) & GRAB_BUTTON) ~= 0
           or hk.check_hotkey("CancelLevitation", true) or hk.check_hotkey("CancelLevitation2", true) then
            request_fall(lev, human)
            g_steerOn = false
            g_riseHold = false
        else
            apply_turn(human, false)
            apply_move_boost(human, lev)
        end
    else
        g_steerOn = false
    end

    local chara_for_ground = human:call("get_Chara()")
    local onGround = is_grounded(human, chara_for_ground, ctrl)

    if g_forceFall then
        local active = false
        pcall(function() active = lev:get_field("<IsActive>k__BackingField") == true end)
        if not active then g_forceFall = false end
    end

    if nativeLevitating then
        if state ~= IDLE then state = IDLE end
        return
    end

    if state == IDLE then
        if onGround then jumpCount = 0; levitatedSinceGround = false end

        local jp = hk.check_hotkey("Jump", true) or hk.check_hotkey("Jump2", true)
        if jp ~= lastJump then
            lastJump = jp
            jumpCount = jumpCount + 0.5
        end

        if jumpCount % 1 == 0.5 and jumpCount > 1.0 and not levitatedSinceGround then
            jumpCount = 0
            local alreadyLev = lev:get_field("<IsActive>k__BackingField")
            if not alreadyLev and NATIVE_FIRST then
            elseif not alreadyLev then
                pcall(function()
                    if human:call("get_IsDrawedWeapon()") ~= true then
                        human:call("forceChangeDrawingWeapon", true)
                    end
                end)
                local created = create_action(human)
                apply_params(lev)
                g_freshCast = true
                if created and action_start() then
                    -- Pin the mod-owned action's refcount so the engine doesn't free it mid-levitation.
                    pcall(function() cachedAction:write_dword(0x8, 2) end)
                    pcall(function() c_start:call(lev, Vector3f.new(0.0, RISE_START_SPEED, 0.0)) end)
                    action_update()
                    local mfsm2 = get_mfsm2(human)
                    if mfsm2 then try_anim_start(mfsm2) end
                    state = ACTIVE
                    activeFrames = 0
                    levitatedSinceGround = true
                end
            end
        end

    elseif state == ACTIVE then
        activeFrames = activeFrames + 1

        action_update()

        if hk.check_hotkey("CancelLevitation", true) or hk.check_hotkey("CancelLevitation2", true) then
            request_fall(lev, human)
        end
        if activeFrames > 5 and not lev:get_field("<IsActive>k__BackingField") then
            state = IDLE
            jumpCount = 0
            g_forceFall = false
        end
    end
end)

re.on_draw_ui(function()
    if not imgui.tree_node("Better Levitate For All Weapons") then return end

    local changed, v
    changed, v = imgui.checkbox("Enable levitate for all weapons", cfg.allWeapons)
    if changed then cfg.allWeapons = v; save_cfg() end

    changed, v = imgui.checkbox("Better Levitate values", cfg.enabled)
    if changed then cfg.enabled = v; save_cfg() end

    if cfg.enabled then
        imgui.text("Applied on your next levitation.")
        changed, v = imgui.slider_float("Max Height", cfg.MaxHeight, 1.0, 30.0, "%.1f")
        if changed then cfg.MaxHeight = v; save_cfg() end
        changed, v = imgui.slider_float("Max Duration (s)", cfg.MaxKeepSec, 1.0, 60.0, "%.1f")
        if changed then cfg.MaxKeepSec = v; save_cfg() end
        changed, v = imgui.slider_float("Move Speed", cfg.MoveSpeed, 0.0, 20.0, "%.1f")
        if changed then cfg.MoveSpeed = v; save_cfg() end
        if imgui.button("Reset to Better defaults") then
            cfg.MaxHeight  = BETTER.MaxHeight
            cfg.MaxKeepSec = BETTER.MaxKeepSec
            cfg.MoveSpeed  = BETTER.MoveSpeed
            save_cfg()
        end
    else
        imgui.text(string.format("Normal (game) values: Height %.1f, Duration %.1fs",
            NORMAL.MaxHeight, NORMAL.MaxKeepSec))
    end
end)
