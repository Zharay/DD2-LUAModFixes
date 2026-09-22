-- ==========================================
-- DEPENDENCIES & SETUP
-- ==========================================
local udb = require('content_editor.database')
local weather_utils = require('editors.weathers.weather_utils')

local save_file_path = "purgener_weather_save.json"

-- Human-readable names for the UI dropdowns
local weather_names = {
    "Stage 0: Thickest Clouds",
    "Stage 1: Heavy Clouds",
    "Stage 2: Medium Clouds",
    "Stage 3: Light Clouds",
    "Stage 4: Clearest Sky"
}

-- The actual database IDs corresponding to the names above
local weather_ids = {
    706, -- Stage 0
    707, -- Stage 1
    708, -- Stage 2
    709, -- Stage 3
    710  -- Stage 4
}

-- Default progression (0 kills = Stage 0, 1 = Stage 0, 2 = Stage 1, etc.)
-- The numbers represent the INDEX of the weather_names/ids tables (1 to 5)
local default_mapping = {
    [0] = 1,
    [1] = 1,
    [2] = 2,
    [3] = 3,
    [4] = 4,
    [5] = 5
}

local state = {
    user_mapping = default_mapping,
    step_back_nex = true -- Defaulting to true as it's intended vanilla behavior
}

-- ==========================================
-- LOAD & SAVE STATE
-- ==========================================

-- 1. Define save_state FIRST
local function save_state()
    json.dump_file(save_file_path, state)
end

-- 2. Define load_state SECOND, so it knows what save_state is
local function load_state()
    local loaded_data = json.load_file(save_file_path)
   
    if loaded_data then
        if loaded_data.user_mapping then
            -- Normalize keys: JSON encodes numeric table keys as strings, so coerce back to numeric keys 0..5
            local normalized = {}
            for i = 0, 5 do
                local v = loaded_data.user_mapping[tostring(i)]
                if v == nil then v = loaded_data.user_mapping[i] end
                normalized[i] = v or default_mapping[i]
            end
            state.user_mapping = normalized
        else
            state.user_mapping = default_mapping
        end
        
        -- Load the new Nex toggle setting
        if loaded_data.step_back_nex ~= nil then
            state.step_back_nex = loaded_data.step_back_nex
        end

        log.info("[Parting The Clouds] Loaded user mapping & settings.")
    else
        -- If the file doesn't exist on first startup, create it with the defaults.
        save_state()
        log.info("[Parting The Clouds] Created default save file.")
    end
end

-- Initialize state on startup
load_state()

-- ==========================================
-- CORE LOGIC
-- ==========================================

-- Safely checks if the player is currently in the Unmoored World
local function is_in_unmoored_world()
    local main_flow_mgr = sdk.get_managed_singleton("app.MainFlowManager")
    if not main_flow_mgr then return false end
    
    -- Wrap in pcall just in case the method isn't immediately available on load
    local success, result = pcall(function()
        return main_flow_mgr:call("get_IsBackStage")
    end)
    
    return success and (result == true)
end

-- Safely checks if the final Nex sequence is currently active
local function is_nex_battle_active()
    local quest_mgr = sdk.get_managed_singleton("app.QuestManager")
    if not quest_mgr then return false end
    
    local success, result = pcall(function()
        return quest_mgr:call("get_UA010Mode")
    end)
    
    return success and (result == true)
end

-- Dynamically counts how many Purgener tornadoes have been disabled
local function get_dead_purgener_count()
    local backstage_mgr = sdk.get_managed_singleton("app.BackStageManager")
    
    -- Fallback to 0 if the manager isn't loaded yet
    if not backstage_mgr then return 0 end 
    
    local dead_count = 0
    -- The five specific IDs you found that represent the Purgener beacons
    local beacon_ids = {4, 8, 16, 32, 64} 
    
    for _, id in ipairs(beacon_ids) do
        -- Call the method directly. It returns true if the tornado is active.
        local is_active = backstage_mgr:call("checkEnableStateTornado", id)
        
        -- If the tornado is gone, the dragon is dead
        if is_active == false then
            dead_count = dead_count + 1
        end
    end
    
    return dead_count
end

local last_logged_stage = -1

-- Prevents apply_custom_weather from re-entering itself: changeWeather/changeWeatherBackWorld
-- are hooked below, and calling weather_utils.changeWeather() from inside this function can
-- retrigger those same hooks. Without this guard that becomes an unbounded feedback loop.
local is_applying_weather = false

local function apply_custom_weather()
    if is_applying_weather then return end

    -- 1. Abort completely if we are not in the Unmoored World
    if not is_in_unmoored_world() then return end

    -- 2. Step back and let vanilla take over if the user enabled the Nex toggle and the battle is active
    if state.step_back_nex and is_nex_battle_active() then return end

    local weather_manager = sdk.get_managed_singleton('app.WeatherManager')
    if not weather_manager then return end
    
    -- 3. Area 7 check (Good to keep just in case they enter a sub-dungeon)
    if weather_manager:call("get_NowArea") == 7 then
        local current_stage = get_dead_purgener_count()
        if current_stage > 5 then current_stage = 5 end
        
        local selected_weather_index = state.user_mapping[current_stage]
        -- Fallback if the loaded mapping doesn't contain a numeric key (JSON may have string keys)
        selected_weather_index = selected_weather_index or default_mapping[current_stage] or 1
        local target_weather_id = weather_ids[selected_weather_index]
        
        local weather_entity = udb.get_entity('weather', target_weather_id)
        
        -- Only issue a change if the weather isn't already what we want; otherwise every
        -- hook firing forces a brand new transition, which never lets the game settle.
        if weather_entity and not weather_utils.isCurrentWeather(weather_entity) then
            is_applying_weather = true
            local ok, err = pcall(weather_utils.changeWeather, weather_entity, false)
            is_applying_weather = false

            if not ok then
                log.error("[Parting The Clouds] Failed to change weather: " .. tostring(err))
                return
            end

            -- Only print to the log if the stage actually changed
            if last_logged_stage ~= current_stage then
                log.info("[Parting The Clouds] Weather synced to: " .. tostring(current_stage) .. " dead Purgeners.")
                last_logged_stage = current_stage
            end
        end
    end
end

-- ==========================================
-- WEATHER OVERRIDE FAILSAFES
-- ==========================================
local weather_mgr_def = sdk.find_type_definition("app.WeatherManager")
if weather_mgr_def then
    local change_weather_method = weather_mgr_def:get_method("changeWeather")
    if change_weather_method then
        sdk.hook(change_weather_method,
            function(args) end,
            function(retval)
                apply_custom_weather()
                return retval
            end
        )
    end
    
    local change_back_world_method = weather_mgr_def:get_method("changeWeatherBackWorld")
    if change_back_world_method then
        sdk.hook(change_back_world_method,
            function(args) end,
            function(retval)
                apply_custom_weather()
                return retval
            end
        )
    end
end

-- ==========================================
-- PERIODIC FALLBACK CHECK
-- ==========================================
local last_check_time = 0
local check_interval = 5.0 -- 5 seconds in real-time

re.on_frame(function()
    -- 1. Initialize on the very first frame
    if not _G.weather_mod_initialized then
        apply_custom_weather()
        _G.weather_mod_initialized = true
    end
    
    -- 2. Fallback timer: Run the check every 5 seconds
    local current_time = os.clock()
    if current_time - last_check_time >= check_interval then
        apply_custom_weather()
        last_check_time = current_time
    end
end)

-- ==========================================
-- CONFIGURATION UI
-- ==========================================
re.on_draw_ui(function()
    if imgui.tree_node("Parting the Clouds") then
        
        local in_unmoored = is_in_unmoored_world()

        imgui.text_colored("Status", 0xFF00FFFF)
        
        -- Display "Disabled" if not in the Unmoored World
        if in_unmoored then
            local current_kill_count = get_dead_purgener_count()
            imgui.text("Purgeners Defeated: " .. tostring(current_kill_count))
            
            if state.step_back_nex and is_nex_battle_active() then
                imgui.text_colored("Vanilla Weather Active (Nex Battle)", 0x00FF00FF)
            end
        else
            imgui.text("Mod Disabled (Not in Unmoored World)")
        end
        
        imgui.spacing()
        imgui.separator()
        imgui.spacing()

        imgui.text_colored("Mod Settings", 0xFF00FFFF)
        local changed_nex, new_nex = imgui.checkbox("Restore Vanilla Weather During Nex Battle", state.step_back_nex)
        if changed_nex then
            state.step_back_nex = new_nex
            save_state()
            -- Force an immediate update to ensure weather corrects if toggled mid-battle
            apply_custom_weather() 
        end

        imgui.spacing()
        imgui.separator()
        imgui.spacing()

        imgui.text_colored("Weather Progression Settings", 0xFF00FFFF)
        imgui.text("Choose which weather state activates at each milestone.")
        imgui.spacing()

        -- Generate a dropdown for 0 through 5 kills
        for i = 0, 5 do
            local current_selection = state.user_mapping[i] or default_mapping[i]
            
            local changed, new_selection = imgui.combo(tostring(i) .. " Dragons Defeated", current_selection, weather_names)
            
            if changed then
                state.user_mapping[i] = new_selection
                save_state()
                
                -- Only attempt to immediately update the weather if we are actually in the Unmoored World
                if in_unmoored and get_dead_purgener_count() == i then
                    apply_custom_weather()
                end
            end
        end
        
        imgui.tree_pop()
    end
end)