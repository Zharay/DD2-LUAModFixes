local re = re
local sdk = sdk
local imgui = imgui
local json = json

local config
local json_filename = "FakeSpotlightDisabler.json"

local function setup_config()
    config = json.load_file(json_filename) or {}

    config.sweet_light_disable = config.sweet_light_disable or false
    config.lantern_sweet_light_disable = config.lantern_sweet_light_disable or false
    config.adjust_lantern_pt = config.adjust_lantern_pt or true
    config.falloff_display = config.falloff_display or 0 -- Slider display value (0 to 10)
end

local function get_falloff_value(display_value)
    -- Map display value (0 to 10) to actual falloff (6.5 to 20.0)
    return 6.5 + (display_value * (25.0 - 6.5) / 10.0)
end

local function adjust_lights()
    local character_manager = sdk.get_managed_singleton("app.CharacterManager")
    if not character_manager then return end
    local camera_light_changer = character_manager:get_CameraLightChanger()
    if not camera_light_changer then return end

    local lantern_sweet_cone = config.lantern_sweet_light_disable and 0.0 or 65.0
    camera_light_changer.LanternSweetLight:set_Cone(lantern_sweet_cone)

    -- Keep SweetLight cone size at 65.0
    camera_light_changer.SweetLight:set_Cone(65.0)

    -- Falloff adjustment for SweetLight
    local falloff = config.sweet_light_disable and get_falloff_value(config.falloff_display) or 6.5 -- 6.5 for default, higher for dimming
    if camera_light_changer.SweetLight.set_Falloff then
        camera_light_changer.SweetLight:set_Falloff(falloff)
    end
    if camera_light_changer.SweetLight.set_Attenuation then
        camera_light_changer.SweetLight:set_Attenuation(falloff)
    end
    if camera_light_changer.SweetLight.Falloff then
        camera_light_changer.SweetLight.Falloff = falloff
    end
    if camera_light_changer.SweetLight.set_AttenuationRadius then
        camera_light_changer.SweetLight:set_AttenuationRadius(falloff)
    end
end

if reframework:get_game_name() == "dd2" then
    sdk.hook(
        sdk.find_type_definition("app.TowerReLibLightBehavior"):get_method("lateUpdate"),
        function(args)
            if not config then return end

            local this = sdk.to_managed_object(args[2])
            local cached_light = this._cacheLightElement

            if not cached_light then return end
            local game_obj = cached_light.LightBase:get_GameObject()
            local light_name = game_obj:get_Name()

            if light_name == "LanternLight_pl_IES" or
               light_name == "LanternLight_pl_Spot" then

                local transform = game_obj:get_Transform()
                local local_position = transform:get_LocalPosition()

                local_position.z = config.adjust_lantern_pt and 0.25 or 0.0
                transform:set_LocalPosition(local_position)
            end
        end,
        nil
    )
end

setup_config()
adjust_lights()

re.on_draw_ui(function()
    local any_changed

    if not config then return end

    if imgui.tree_node("Fake Spotlight Disabler") then
        local any_spot_changed
        local spot_light_changed
		
        spot_light_changed, config.lantern_sweet_light_disable = imgui.checkbox("Disable -Lantern- fake spotlight", config.lantern_sweet_light_disable)
        any_spot_changed = spot_light_changed or any_spot_changed
        any_changed = spot_light_changed or any_changed

        spot_light_changed, config.sweet_light_disable = imgui.checkbox("Dim -Character- fake spotlight", config.sweet_light_disable)
        any_spot_changed = spot_light_changed or any_spot_changed
        any_changed = spot_light_changed or any_changed

        -- Falloff display slider (0 to 10 maps to 6.5 to 20.0)
        local changed, new_falloff_display = imgui.slider_float("Dimming Strength", config.falloff_display, 0.0, 10.0, "%.2f")
        if changed then
            config.falloff_display = new_falloff_display
            any_changed = true
        end

        if spot_light_changed then
            config.adjust_lantern_pt = config.lantern_sweet_light_disable
        end

        if any_spot_changed or changed then
            adjust_lights()
        end

        imgui.tree_pop()
    end

    if any_changed then
        json.dump_file(json_filename, config)
    end
end)