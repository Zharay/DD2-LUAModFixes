local re = re
local sdk = sdk
local imgui = imgui
local json = json

if reframework:get_game_name() ~= "dd2" then return end

local json_filename = "FakeSpotlightDisabler.json"
local config = json.load_file(json_filename)
if type(config) ~= "table" then config = {} end

local defaults = {
    sweet_light_disable = false,
    lantern_sweet_light_disable = false,
    falloff_display = 0,
}

for key, default in pairs(defaults) do
    if type(config[key]) ~= type(default) then
        if config[key] ~= nil then
            log.error("[FakeSpotlightDisabler] Invalid setting " .. key .. "; using default")
        end
        config[key] = default
    end
end
if config.falloff_display ~= config.falloff_display or config.falloff_display < 0 or config.falloff_display > 10 then
    log.error("[FakeSpotlightDisabler] Invalid dimming strength; using default")
    config.falloff_display = defaults.falloff_display
end

local spot_type = sdk.find_type_definition("via.render.SpotLight")
local changer_type = sdk.find_type_definition("app.CameraSweetLightChanger")
local manager_type = sdk.find_type_definition("app.CharacterManager")
local flow_type = sdk.find_type_definition("app.MainFlowManager")
local gui_type = sdk.find_type_definition("app.GuiManager")
local ferrystone_type = sdk.find_type_definition("app.FerrystoneFlowController")
local compatible = spot_type and changer_type and manager_type
    and flow_type and gui_type and ferrystone_type
    and spot_type:get_method("set_Cone(System.Single)")
    and spot_type:get_method("set_Falloff(System.Single)")
    and changer_type:get_field("LanternSweetLight")
    and changer_type:get_field("SweetLight")
    and changer_type:get_field("IsFoundCameraLight")
    and manager_type:get_method("get_CameraLightChanger()")
    and flow_type:get_method("get_IsInGamePhase()")
    and gui_type:get_method("isFadeDispAny()")
    and gui_type:get_field("CrossGuide")
    and ferrystone_type:get_method("get_IsActive()")

if not compatible then
    log.error("[FakeSpotlightDisabler] Required game light or readiness API is unavailable")
end

local reported_wrong_type = false
local function adjust_spot(light, cone, falloff)
    if not light then return false end
    local game_object = light:call("get_GameObject()")
    if not game_object or not game_object:call("get_Valid()") then return false end
    if not light:get_type_definition():is_a("via.render.SpotLight") then
        if not reported_wrong_type then
            log.error("[FakeSpotlightDisabler] Camera light is not a via.render.SpotLight")
            reported_wrong_type = true
        end
        return false
    end
    if cone ~= nil then light:call("set_Cone(System.Single)", cone) end
    if falloff ~= nil then light:call("set_Falloff(System.Single)", falloff) end
    return true
end

local lantern_applied = false
local sweet_applied = false

local function adjust_lights()
    local manager = sdk.get_managed_singleton("app.CharacterManager")
    local changer = manager and manager:call("get_CameraLightChanger()")
    if not changer or changer:get_field("IsFoundCameraLight") ~= true then return end
    if config.lantern_sweet_light_disable or lantern_applied then
        if adjust_spot(changer:get_field("LanternSweetLight"), config.lantern_sweet_light_disable and 0.0 or 65.0) then
            lantern_applied = config.lantern_sweet_light_disable
        end
    end
    if config.sweet_light_disable or sweet_applied then
        local falloff = config.sweet_light_disable and (6.5 + config.falloff_display * 1.85) or 6.5
        if adjust_spot(changer:get_field("SweetLight"), nil, falloff) then
            sweet_applied = config.sweet_light_disable
        end
    end
end

local next_update = 0
local ready_since
re.on_frame(function()
    if not compatible then return end
    if not (config.lantern_sweet_light_disable or config.sweet_light_disable
        or lantern_applied or sweet_applied) then
        ready_since = nil
        return
    end

    local flow = sdk.get_managed_singleton("app.MainFlowManager")
    local gui = sdk.get_managed_singleton("app.GuiManager")
    local ferrystone = sdk.get_managed_singleton("app.FerrystoneFlowController")
    if not flow or flow:call("get_IsInGamePhase()") ~= true
        or not gui or not gui:get_field("CrossGuide") or gui:call("isFadeDispAny()") ~= false
        or not ferrystone or ferrystone:call("get_IsActive()") ~= false then
        ready_since = nil
        return
    end

    local now = os.clock()
    if not ready_since then ready_since = now end
    if now - ready_since < 2.0 then return end
    if now < next_update then return end
    next_update = now + 0.5
    adjust_lights()
end)

re.on_draw_ui(function()
    if not imgui.tree_node("Fake Spotlight Disabler") then return end

    if not compatible then
        imgui.text("Required actors are unavailable; see REFramework log.")
    end

    local lantern_changed, lantern_disabled = imgui.checkbox("Disable -Lantern- rim light", config.lantern_sweet_light_disable)
    if imgui.is_item_hovered() then imgui.set_tooltip("Disables character lighting produced by the lantern.") end
    if lantern_changed then
        config.lantern_sweet_light_disable = lantern_disabled
    end

    local sweet_changed, sweet_disabled = imgui.checkbox("Dim -Character- rim light", config.sweet_light_disable)
    if imgui.is_item_hovered() then imgui.set_tooltip("Enables the editing of character rim lighting when enveloped by darkness.") end
    if sweet_changed then config.sweet_light_disable = sweet_disabled end

    local falloff_changed, falloff = imgui.slider_float("Dimming Strength", config.falloff_display, 0.0, 10.0, "%.2f")
    if imgui.is_item_hovered() then imgui.set_tooltip("Dimming strength of character rim lighting when enveloped by darkness. Requires `Dim -Character- rim light` be enabled.") end
    if falloff_changed then config.falloff_display = falloff end

    if lantern_changed or sweet_changed or falloff_changed then
        json.dump_file(json_filename, config)
        next_update = 0
    end

    imgui.tree_pop()
end)
