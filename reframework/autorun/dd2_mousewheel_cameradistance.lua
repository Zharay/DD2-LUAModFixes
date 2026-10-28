-- DragonsDogma2 MouseWheel Camera Distance mod by emoose
-- https://www.nexusmods.com/dragonsdogma2/mods/152

-- User settings section
-- Feel free to edit these here, or you can edit them from REFramework overlay during gameplay ("Script Generated UI" > "MouseWheel Camera")

-- If you'd like RequireCtrlKey to use a different bind than CTRL+MouseWheel, you can search for via.hid.KeyboardKey.Control in the code section below and change it
--   (eg. use via.hid.KeyboardKey.Menu to make it ALT+MouseWheel)

local DefaultConfig = {
    CameraMinDistance = -3.0,
    CameraMaxDistance = 10.0,
    WheelStepDistance = 1.0, -- distance camera should move for each wheel step
    CameraSpeed = 1.5, -- camera movement speed (if you prefer it to snap to each step, change this to 100)
    CameraDistance = 0.0, -- default distance once game is loaded in, your current distance can be saved via REFramework overlay
    ResetDistanceOnMiddleClick = true, -- resets camera distance on middle-click / right-stick (same as the default binding for games "reset camera" hotkey)
    RequireCtrlKey = false, -- if set to true, will only have an effect when used with CTRL key held
    DisallowCtrlKey = false, -- if using another mousewheel mod that uses CTRL+MouseWheel, enable this to stop camera from seeing inputs meant for that mod
    EnableGamePad = true, -- if enabled, camera can be controlled by pressing LB + RSUp/RSDown (press RS to reset camera)
    KeyZoomIn = "Up", -- optional key binding to zoom in
    KeyZoomOut = "Down" -- optional key binding to zoom out
}

-- Code section
local Config = {}

local function config_reset()
    Config = {}
    for k, v in pairs(DefaultConfig) do
        Config[k] = v
    end
end

local function config_load()
    config_reset()
    
    local config = json.load_file("dd2_mousewheel_cameradistance.json") or {}
    for k, v in pairs(config) do
        Config[k] = v
    end
end

config_load()

local via_hid_mouse = sdk.get_native_singleton("via.hid.Mouse")
local via_hid_mouse_typedef = sdk.find_type_definition("via.hid.Mouse")
local via_hid_keyboard = sdk.get_native_singleton("via.hid.Keyboard")
local via_hid_keyboard_typedef = sdk.find_type_definition("via.hid.Keyboard")
local via_hid_keyboardkey_typedef = sdk.find_type_definition("via.hid.KeyboardKey")
local via_hid_gamepad = sdk.get_native_singleton("via.hid.GamePad")
local via_hid_gamepad_typedef = sdk.find_type_definition("via.hid.GamePad")
local app_CameraManager = sdk.get_managed_singleton("app.CameraManager")
local app_MainFlowManager = sdk.get_managed_singleton("app.MainFlowManager")
local app_PauseManager = sdk.get_managed_singleton("app.PauseManager")
local app_GuiManager = sdk.get_managed_singleton("app.GuiManager")

-- Mouse/keyboard input code from https://gist.github.com/praydog/31317fef2a2f3d0670a68560ed0aa7e0
--generate enums
local function generate_statics(typename)
    local t = sdk.find_type_definition(typename)
    if not t then
        return {}
    end

    local fields = t:get_fields()
    local enum = {}

    for i, field in ipairs(fields) do
        if field:is_static() then
            local name = field:get_name()
            local raw_value = field:get_data(nil)

            enum[name] = raw_value
        end
    end

    return enum
end

local function generate_statics_global(typename)
    local parts = {}
    for part in typename:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    local global = _G
    for i, part in ipairs(parts) do
        if not global[part] then
            global[part] = {}
        end
        global = global[part]
    end
    if global ~= _G then
        local static_class = generate_statics(typename)

        for k, v in pairs(static_class) do
            global[k] = v
            global[v] = k
        end
    end
    return global
end

generate_statics_global("via.hid.MouseButton")
generate_statics_global("via.hid.KeyboardKey")
generate_statics_global("via.hid.GamePadButton")

local function is_input_enabled()
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

local updates_enabled = true

local function update_hid(dt)
    if not is_input_enabled() then
        updates_enabled = false
        return
    end
    
    local wheel_delta = 0
    
    if Config.EnableGamePad then
        local gamepad_device = sdk.call_native_func(via_hid_gamepad, via_hid_gamepad_typedef, "get_LastInputDevice")
        if gamepad_device == nil then
            gamepad_device = sdk.call_native_func(via_hid_gamepad, via_hid_gamepad_typedef, "get_Device")
        end
        if gamepad_device ~= nil then
            if gamepad_device:call("isDown", via.hid.GamePadButton.LTrigTop) then
                local rs = gamepad_device:get_AxisR()
                if rs.y ~= 0 then
                    wheel_delta = rs.y
                    -- zero RStick.y so that game doesn't act on it
                    gamepad_device:set_AxisR(Vector2f:new(rs.x,0))
                end
            end
            
            if Config.ResetDistanceOnMiddleClick and gamepad_device:call("isDown", via.hid.GamePadButton.RStickPush) then
                Config.CameraDistance = 0
                wheel_delta = 0
            end
        end
    end
    
    if Config.KeyZoomIn ~= "" or Config.KeyZoomOut ~= "" then
        local ZoomIn_key = via_hid_keyboardkey_typedef:get_field(Config.KeyZoomIn)
        local ZoomOut_key = via_hid_keyboardkey_typedef:get_field(Config.KeyZoomOut)
        
        if ZoomIn_key ~= nil or ZoomOut_key ~= nil then
            local kb_device = sdk.call_native_func(via_hid_keyboard, via_hid_keyboard_typedef, "get_Device")
            if ZoomIn_key ~= nil then
                if kb_device:call("isDown", ZoomIn_key:get_data(nil)) then
                    wheel_delta = 1.0
                end
            end
            if ZoomOut_key ~= nil then
                if kb_device:call("isDown", ZoomOut_key:get_data(nil)) then
                    wheel_delta = -1.0
                end
            end
        end
    end
    
    if wheel_delta ~= 0 then
        wheel_delta = (wheel_delta * 10) * dt
        Config.CameraDistance = Config.CameraDistance - (wheel_delta * Config.WheelStepDistance)
        Config.CameraDistance = math.clamp(Config.CameraDistance, Config.CameraMinDistance, Config.CameraMaxDistance)
    end
    
    local enabled = true
    
    if Config.RequireCtrlKey or Config.DisallowCtrlKey then
        local kb_device = sdk.call_native_func(via_hid_keyboard, via_hid_keyboard_typedef, "get_Device")
        local ctrl_pressed = kb_device:call("isDown", via.hid.KeyboardKey.Control)

        if Config.RequireCtrlKey and not ctrl_pressed then
            enabled = false
        end
        
        if Config.DisallowCtrlKey and ctrl_pressed then
            enabled = false
        end
    end

    -- update imgui status
    if updates_enabled ~= enabled then
        updates_enabled = enabled
    end

    if not enabled then
        return
    end

    local mouse_device = sdk.call_native_func(via_hid_mouse, via_hid_mouse_typedef, "get_Device")
    wheel_delta = mouse_device:get_WheelDelta()

    if wheel_delta ~= 0 then
        Config.CameraDistance = Config.CameraDistance - (wheel_delta * Config.WheelStepDistance)
        Config.CameraDistance = math.clamp(Config.CameraDistance, Config.CameraMinDistance, Config.CameraMaxDistance)
    end

    if Config.ResetDistanceOnMiddleClick then
        local mouse_middleclick = mouse_device:call("isDown", via.hid.MouseButton.C)
        if mouse_middleclick then
            Config.CameraDistance = 0
        end
    end
end

local last_time = os.clock()
re.on_application_entry("UpdateHID", function()
    local dt = os.clock() - last_time
    last_time = os.clock()
    
    update_hid(dt)
    
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
        cam_dist = cam_dist + interp_amount * math.sign(distance_delta)
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
        changed, Config.CameraMinDistance = imgui.slider_float("##mincamdist", Config.CameraMinDistance, -10, 100)
        if changed then
            has_unsaved_changes = true
        end
        
        imgui.text("Max Camera Distance")
        changed, Config.CameraMaxDistance = imgui.slider_float("##maxcamdist", Config.CameraMaxDistance, -10, 100)
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

        changed, Config.EnableGamePad = imgui.checkbox("Enable Gamepad (LB + RSUp/RSDown)", Config.EnableGamePad)
        if changed then
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

        imgui.tree_pop()
    end
end)

-- util functions
function math.sign(x)
    return x > 0 and 1 or x < 0 and -1 or 0
end

function math.clamp(x, min, max)
    return math.min(math.max(x, min), max)
end
