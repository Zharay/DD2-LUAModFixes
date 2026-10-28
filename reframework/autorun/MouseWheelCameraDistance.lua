-- DragonsDogma2 MouseWheel Camera Distance mod by emoose
-- https://www.nexusmods.com/dragonsdogma2/mods/152
-- Requires _ScriptCore's Hotkeys/Hotkeys (v1.3.54 or newer for current DD2 input support).
-- Controls: wheel / Up / Down to zoom, LB + right stick or LB + LT (out) / RT (in), middle click / R3 to reset.

-- User settings section
-- Feel free to edit these here, or you can edit them from REFramework overlay during gameplay ("Script Generated UI" > "MouseWheel Camera")

-- RequireCtrlKey and DisallowCtrlKey affect only the mouse wheel and middle-click reset.

local DefaultConfig = {
    CameraMinDistance = -3.0,
    CameraMaxDistance = 10.0,
    WheelStepDistance = 1.0, -- distance camera should move for each wheel step
    CameraSpeed = 1.5, -- camera movement speed (if you prefer it to snap to each step, change this to 100)
    CameraDistance = 0.0, -- default distance once game is loaded in, your current distance can be saved via REFramework overlay
    ResetDistanceOnMiddleClick = true, -- resets camera distance on middle-click / right-stick (same as the default binding for games "reset camera" hotkey)
    RequireCtrlKey = false, -- if set to true, will only have an effect when used with CTRL key held
    DisallowCtrlKey = false, -- if using another mousewheel mod that uses CTRL+MouseWheel, enable this to stop camera from seeing inputs meant for that mod
    GamePadMode = "LB + RSUp/RSDown", -- Disabled, LB + RSUp/RSDown, or LB + LT/RT (press RS to reset in either enabled mode)
    KeyZoomIn = "Up", -- optional key binding to zoom in
    KeyZoomOut = "Down" -- optional key binding to zoom out
}

-- Code section
local hotkeys = require("Hotkeys/Hotkeys")
local Config = {}
local gamepad_modes = {"Disabled", "LB + RSUp/RSDown", "LB + LT/RT"}

local function gamepad_mode_index(mode)
    for i, value in ipairs(gamepad_modes) do
        if value == mode then
            return i
        end
    end
end

local function clamp(value, minimum, maximum)
    return math.min(math.max(value, minimum), maximum)
end

local function config_reset()
    Config = {}
    for k, v in pairs(DefaultConfig) do
        Config[k] = v
    end
end

local function config_load()
    config_reset()
    
    local config = json.load_file("dd2_mousewheel_cameradistance.json")
    if config == nil then
        return
    end
    if type(config) ~= "table" then
        log.error("[MouseWheel Camera] Invalid config; using defaults")
        return
    end
    for k, default in pairs(DefaultConfig) do
        local value = config[k]
        if value ~= nil then
            if type(value) == type(default)
                and (type(value) ~= "number" or (value == value and math.abs(value) < math.huge)) then
                Config[k] = value
            else
                log.error("[MouseWheel Camera] Invalid setting " .. k .. "; using default")
            end
        end
        if config.GamePadMode == nil and config.EnableGamePad ~= nil then
            if type(config.EnableGamePad) == "boolean" then
                Config.GamePadMode = config.EnableGamePad and "LB + RSUp/RSDown" or "Disabled"
            else
                log.error("[MouseWheel Camera] Invalid legacy EnableGamePad setting; using default mode")
            end
        end
        if not gamepad_mode_index(Config.GamePadMode) then
            log.error("[MouseWheel Camera] Invalid GamePadMode; using default mode")
            Config.GamePadMode = DefaultConfig.GamePadMode
        end
    end
    if Config.CameraMinDistance > Config.CameraMaxDistance then
        log.error("[MouseWheel Camera] Min distance exceeds max distance; using default bounds")
        Config.CameraMinDistance = DefaultConfig.CameraMinDistance
        Config.CameraMaxDistance = DefaultConfig.CameraMaxDistance
    end
    for _, key in ipairs({"WheelStepDistance", "CameraSpeed"}) do
        if Config[key] <= 0 then
            log.error("[MouseWheel Camera] Invalid setting " .. key .. "; using default")
            Config[key] = DefaultConfig[key]
        end
    end
end

config_load()

local app_CameraManager
local app_MainFlowManager
local app_PauseManager
local app_GuiManager

local keyboard_aliases = {Menu = "Alt", LMenu = "LAlt", RMenu = "RAlt", DefinedEnter = "Enter"}
local function key_down(name)
    if name == "Shift" then
        return hotkeys.check_kb_key("LShift", true) or hotkeys.check_kb_key("RShift", true)
    end
    return hotkeys.check_kb_key(keyboard_aliases[name] or name, true)
end

local function is_input_enabled()
    app_MainFlowManager = app_MainFlowManager or sdk.get_managed_singleton("app.MainFlowManager")
    app_PauseManager = app_PauseManager or sdk.get_managed_singleton("app.PauseManager")
    app_GuiManager = app_GuiManager or sdk.get_managed_singleton("app.GuiManager")

    -- disable updates if on mainmenu
    if app_MainFlowManager == nil or not app_MainFlowManager:get_IsInGamePhase() then
        return false
    end

    -- disable updates if game paused (menus or anything)
    if app_PauseManager == nil or app_PauseManager:isPausedAny() then
       return false
    end

    -- disable updates if GUI active, or mouse cursor is being shown on screen (likely in a conversation/menu)
    if app_GuiManager == nil or app_GuiManager:isPausedGUI() or app_GuiManager:IsMousePointerDispGui() then
        return false
    end
    
    return true
end

local updates_enabled = false

local function update_hid(dt)
    updates_enabled = false
    if not is_input_enabled() then
        return
    end
    
    local wheel_delta = 0
    local reset_distance = false
    
    if Config.GamePadMode ~= "Disabled" and hotkeys.pad then
        if hotkeys.check_pad_button("LB (L1)", true) then
            if Config.GamePadMode == "LB + RSUp/RSDown" then
                local rs = hotkeys.pad:call("get_AxisR")
                if rs and rs.y ~= 0 then
                    wheel_delta = rs.y
                    -- Consume only vertical look on the same merged device the game reads.
                    hotkeys.pad:call("set_AxisR", Vector2f.new(rs.x, 0))
                end
            elseif Config.GamePadMode == "LB + LT/RT" then
                local zoom_out = hotkeys.check_pad_button("LT (L2)", true) and 1 or 0
                local zoom_in = hotkeys.check_pad_button("RT (R2)", true) and 1 or 0
                wheel_delta = zoom_in - zoom_out
            end
        end
        reset_distance = Config.ResetDistanceOnMiddleClick and hotkeys.check_pad_button("R3", true)
    end
    
    if key_down(Config.KeyZoomIn) then
        wheel_delta = 1.0
    end
    if key_down(Config.KeyZoomOut) then
        wheel_delta = -1.0
    end
    
    if wheel_delta ~= 0 then
        wheel_delta = (wheel_delta * 10) * dt
        Config.CameraDistance = Config.CameraDistance - (wheel_delta * Config.WheelStepDistance)
        Config.CameraDistance = clamp(Config.CameraDistance, Config.CameraMinDistance, Config.CameraMaxDistance)
    end
    
    local ctrl_pressed = key_down("Control")
    updates_enabled = hotkeys.mouse ~= nil
        and (not Config.RequireCtrlKey or not not ctrl_pressed)
        and (not Config.DisallowCtrlKey or not ctrl_pressed)

    if updates_enabled then
        wheel_delta = hotkeys.mouse:call("get_WheelDelta")
        if wheel_delta ~= 0 then
            Config.CameraDistance = Config.CameraDistance - (wheel_delta * Config.WheelStepDistance)
            Config.CameraDistance = clamp(Config.CameraDistance, Config.CameraMinDistance, Config.CameraMaxDistance)
        end

        if Config.ResetDistanceOnMiddleClick and hotkeys.check_mouse_button("M Mouse", true) then
            reset_distance = true
        end
    end
    if reset_distance then
        Config.CameraDistance = 0
    end
end

local last_time = os.clock()
re.on_application_entry("UpdateHID", function()
    local dt = os.clock() - last_time
    last_time = os.clock()
    
    update_hid(dt)
    
    app_CameraManager = app_CameraManager or sdk.get_managed_singleton("app.CameraManager")
    if app_CameraManager == nil then
        return
    end
    
    local cam_dist = app_CameraManager:get_DistanceOffset()
    if cam_dist == nil or Config.CameraDistance == cam_dist then
        return
    end
    
    -- try to interpolate toward the new camera distance...
    local distance_delta = Config.CameraDistance - cam_dist
    local interp_amount = (Config.CameraSpeed * 10) * dt
    if math.abs(distance_delta) > interp_amount then
        cam_dist = cam_dist + (distance_delta > 0 and interp_amount or -interp_amount)
    else
        cam_dist = Config.CameraDistance
    end

    app_CameraManager:set_DistanceOffset(cam_dist)
end)

local has_unsaved_changes = false
re.on_draw_ui(function()
    local node_text = "MouseWheel Camera"
    if has_unsaved_changes then
        node_text = node_text .. " (unsaved changes)"
    end
    node_text = node_text .. "###mousewheelcamera" -- id for imgui
    
    if imgui.tree_node(node_text) then
        local changed = false

        if imgui.button("Save Config") then
            json.dump_file("dd2_mousewheel_cameradistance.json", Config)
            has_unsaved_changes = false
        end

        imgui.same_line()

        if imgui.button("Reload Config") then
            config_load()
            has_unsaved_changes = false
        end
        
        imgui.same_line()
        
        if imgui.button("Reset Config") then
            config_reset()
            has_unsaved_changes = true
        end
        
        imgui.separator()

        imgui.text("Min Camera Distance")
        changed, Config.CameraMinDistance = imgui.slider_float("##mincamdist", Config.CameraMinDistance, -10, Config.CameraMaxDistance)
        if changed then
            has_unsaved_changes = true
        end
        
        imgui.text("Max Camera Distance")
        changed, Config.CameraMaxDistance = imgui.slider_float("##maxcamdist", Config.CameraMaxDistance, Config.CameraMinDistance, 100)
        if changed then
            has_unsaved_changes = true
        end
        
        imgui.text("Wheel/Pad Step Distance")
        changed, Config.WheelStepDistance = imgui.slider_float("##wheelstepdist", Config.WheelStepDistance, 0.01, 10)
        if changed then
            has_unsaved_changes = true
        end
        
        imgui.text("Camera Speed")
        changed, Config.CameraSpeed = imgui.slider_float("##cameraspeed", Config.CameraSpeed, 0.25, 10)
        if changed then
            has_unsaved_changes = true
        end

        imgui.text("Gamepad controls")
        local gamepad_mode
        changed, gamepad_mode = imgui.combo("##mousewheelcamera_gamepadmode", gamepad_mode_index(Config.GamePadMode), gamepad_modes)
        if changed then
            Config.GamePadMode = gamepad_modes[gamepad_mode]
            has_unsaved_changes = true
        end
        
        changed, Config.ResetDistanceOnMiddleClick = imgui.checkbox("Reset on middle click / RS", Config.ResetDistanceOnMiddleClick)
        if changed then
            has_unsaved_changes = true
        end
        
        local ctrl_options = { 
          "Ignore (wheel always affects camera)", 
          "Require (CTRL required for wheel to work)",
          "Disallow (CTRL prevents wheel taking effect)"
        }
        
        local ctrl_option_cur = 1
        if not Config.RequireCtrlKey and not Config.DisallowCtrlKey then
            ctrl_option_cur = 1
        elseif Config.RequireCtrlKey and not Config.DisallowCtrlKey then
            ctrl_option_cur = 2
        elseif not Config.RequireCtrlKey and Config.DisallowCtrlKey then
            ctrl_option_cur = 3
        end
        imgui.text("")
        imgui.text("CTRL key behavior")
        local changed, ctrl_setting = imgui.combo("##ctrlkey", ctrl_option_cur, ctrl_options)
        if changed then
            has_unsaved_changes = true
            
            if ctrl_setting == 1 then
                Config.RequireCtrlKey = false
                Config.DisallowCtrlKey = false
            elseif ctrl_setting == 2 then
                Config.RequireCtrlKey = true
                Config.DisallowCtrlKey = false
            elseif ctrl_setting == 3 then
                Config.RequireCtrlKey = false
                Config.DisallowCtrlKey = true
            end
        end
        imgui.text("(Disallow is useful if another mod uses CTRL+Wheel)")
        
        imgui.separator()

        imgui.text("Debug info:")
        imgui.text("  Config.CameraDistance: " .. Config.CameraDistance)
        imgui.text("  Config.RequireCtrlKey: " .. tostring(Config.RequireCtrlKey))
        imgui.text("  Config.DisallowCtrlKey: " .. tostring(Config.DisallowCtrlKey))
        imgui.text("  Wheel Enabled: " .. tostring(updates_enabled))
        imgui.text("  Gamepad Available: " .. tostring(hotkeys.pad ~= nil))

        imgui.tree_pop()
    end
end)
