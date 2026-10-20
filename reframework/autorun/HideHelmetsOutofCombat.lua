-- Set some core variables.
	local re = re
	local sdk = sdk
	local d2d = d2d
	local imgui = imgui
	local log = log
	local json = json
	local draw = draw
	local hotkeys = require("Hotkeys/Hotkeys")


-- Set some mod specific variables.
	local hideModes_labels = { "Never Hide", "Hide Out of Combat", "Always Hide" }
	local hideModes = { Never = 1, Combat = 2, Always = 3 }
	local inCombat= false
	local toggleAction = "HideHelmetsOutOfCombat.AlwaysHide"
	local defaultHotkeys = { [toggleAction] = "[Not Bound]" }


-- Mod config setup and saving
	local config = {
	    confPlayer = hideModes.Combat,
	    confPawns = hideModes.Combat,
	    alwaysHide = false,
	    hotkeys = { [toggleAction] = defaultHotkeys[toggleAction] }
	}
	
	local function load_config()
	    local f = json.load_file('HideHelmetsOutOfCombat.json')
	    if f ~= nil then
	        if type(f.confPlayer) == 'number' then config.confPlayer = f.confPlayer end
	        if type(f.confPawns) == 'number' then config.confPawns = f.confPawns end
	        if type(f.alwaysHide) == 'boolean' then config.alwaysHide = f.alwaysHide end
	        if type(f.hotkeys) == 'table' and type(f.hotkeys[toggleAction]) == 'string' then
	            config.hotkeys[toggleAction] = f.hotkeys[toggleAction]
	        end
	    end
	end
	
	local function save_config()
	    json.dump_file('HideHelmetsOutOfCombat.json', config)
	end


-- Log that the mod has indeed loaded.
	log.info("[Hide Helmet Out Of Combat] Loaded")
	load_config()
	hotkeys.setup_hotkeys(config.hotkeys, defaultHotkeys)


-- The battle manager gets the combat state.
	local BattleManager = sdk.get_managed_singleton("app.BattleManager")
	local function GetBattleManager()
	    if BattleManager == nil then BattleManager = sdk.get_managed_singleton("app.BattleManager") end
		return BattleManager
	end
	if BattleManager then
	    inCombat = BattleManager:call("get_IsBattleMode()");
	end

	local PlayerManager = sdk.get_managed_singleton("app.CharacterEditManager")
	local function GetCharacterEditManager()
	    if PlayerManager == nil then PlayerManager = sdk.get_managed_singleton("app.CharacterEditManager") end
		return PlayerManager
	end

	local CharacterEditManagerType = sdk.find_type_definition("app.CharacterEditManager")
	local function findHelmetField(role)
	    local expectedName = role == "player" and "_HidePlayerHelm" or "_HidePawnHelm"
	    local field = CharacterEditManagerType and CharacterEditManagerType:get_field(expectedName)
	    if field then return expectedName end

	    for _, candidate in ipairs(CharacterEditManagerType and CharacterEditManagerType:get_fields() or {}) do
	        local name = candidate:get_name()
	        local normalizedName = name:lower()
	        if normalizedName:find("hide", 1, true)
	            and normalizedName:find("helm", 1, true)
	            and normalizedName:find(role, 1, true) then
	            return name
	        end
	    end

	    log.warn("[Hide Helmet Out Of Combat] No " .. role .. " helmet field found; that setting is disabled")
	    return nil
	end

	local hidePlayerHelmField = findHelmetField("player")
	local hidePawnHelmField = findHelmetField("pawn")


-- Function to apply the hidden status of helmets.
	local function applyChanges()
	    local hide0 = false;
	        if config.confPlayer == hideModes.Always then hide0 = true end
	        if config.confPlayer == hideModes.Combat then hide0 = not inCombat end
	    local hide1 = false;
	        if config.confPawns == hideModes.Always then hide1 = true end
	        if config.confPawns == hideModes.Combat then hide1 = not inCombat end
	    if config.alwaysHide then hide0, hide1 = true, true end
	    local characterEditManager = GetCharacterEditManager()
	    if characterEditManager == nil then return end
	    if hidePlayerHelmField then characterEditManager:set_field(hidePlayerHelmField, hide0) end
	    if hidePawnHelmField then characterEditManager:set_field(hidePawnHelmField, hide1) end
	end


-- Apply checks to see if the party is or is not in combat.
	local frameCounter = 0
	re.on_frame(function()
	    if not reframework:is_drawing_ui() and hotkeys.check_hotkey(toggleAction, false, true) then
	        config.alwaysHide = not config.alwaysHide
	        save_config()
	        applyChanges()
	    end
	    frameCounter = frameCounter + 1
	    if frameCounter < 15 then return end
	    frameCounter = 0
	    local battleManager = GetBattleManager()
	    if battleManager then inCombat = battleManager:call("get_IsBattleMode()") end
	    applyChanges();
	end)


-- GUI to apply settings
	re.on_draw_ui(function()
	    local changed
	
	    if imgui.tree_node("Hide Helmets Out of Combat") then
	        changed, config.confPlayer = imgui.combo('Player', config.confPlayer, hideModes_labels)
	        if changed then save_config() applyChanges() end
	        changed, config.confPawns = imgui.combo('Pawns', config.confPawns, hideModes_labels)
	        if changed then save_config() applyChanges() end
			imgui.text(" ")
	        imgui.text("Overrides")
			changed, config.alwaysHide = imgui.checkbox('Always hide helmets (player and pawns)', config.alwaysHide)
	        if changed then save_config() applyChanges() end
	        if hotkeys.hotkey_setter(toggleAction, false, "Toggle always hide helmets") then
	            hotkeys.update_hotkey_table(config.hotkeys)
	            save_config()
	        end
	        imgui.text("Click the hotkey button, then press an input. Right-click to clear.")
	        imgui.tree_pop()
	    end
	end)