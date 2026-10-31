-- Authur K1ng4
-- Version 2.2
-- This took me forever :D
local re = re
local sdk = sdk
local json = json
local ui = imgui
local modname = "AugmentsUnleashed"
local dataPath = "AugmentsUnleashed.json"
local configPath = "AugmentsUnleashedConfig.json"
-- 1 = Player, 2 = Pawn (index into the Augments Menu drop-list)
local SelectedTarget = 1
local AugmentsInfinityEnabled = false
local AugmentsOverhualEnabled = false
local AbilitiesParam = {}
local AbilitiesParamMod = {}
local AbilitiesParamDefault = {}
local next = next
local ModStrings = { 
	["ModName"] = "Augments Unleashed",
	["AugmentsMenu"] = "Augments Menu",
	["DiscriptiveMode"] = "Discriptive Mode",
	["PlayerToggle"] = "Player Augments",
	["PawnToggle"] = "Pawn Augments",
	["TargetSelect"] = "Editing",
	["EquippedTooltip"] = "Already equipped in-game for the current vocation.",
	["AugmentsMenuNote"] = "Any augments past the default amount will not show in the game's menus.\nClose & open the Pause Menu to update the Status menu.",
	["AugmentsOverhualMenu"] = "Augments Overhual Menu",
	["AugmentsOverhualMenu_Label_Stat"] = "Stat",
	["AugmentsOverhualModeEnable"] = "Enable",
	["AugmentsOverhualModeSave"] = "Save",
	["AugmentsOverhualModeReset"] = "Reset",
	["AugmentsOverhualModeResetWarning"] = "I know all my custom augments overhual will reset to default."
}
local dataAugments = {}
local dataAugmentsDescribtion = {}
local dataAugmentsModDescribtion = {}
local dataAugmentsPlayerEnabled = {}
local dataAugmentsPawnEnabled = {}
local dataDescriptiveMode = false

local ABILITY_MIN = 4
local ABILITY_MAX = 54
local PLAYER_ONLY_AUGMENTS = {
	[51] = true,
	[52] = true,
	[53] = true,
	[54] = true,
}

local function canUseAugment(id, isPawn)
	return not isPawn or not PLAYER_ONLY_AUGMENTS[id]
end

-- The game's own augment slots (app.AbilityContext.AbilitySlot No0..No6). These are kept
-- untouched; mod augments are written after them.
local NATIVE_SLOT_COUNT = 7
local ABILITY_ARRAY_SIZE = NATIVE_SLOT_COUNT + (ABILITY_MAX - ABILITY_MIN + 1)

local App = {
    _version = "1.0"
}

local function Log(message, level)
    level = level or "info"
    local previousLevel = log.get_level and log.get_level() or "error"
    log.set_level(level)
    local ok, err = pcall(log[level], "["..modname.."] "..message)
    log.set_level(previousLevel)
    if not ok then error(err, 0) end
end

local PlayerManager = sdk.get_managed_singleton("app.CharacterManager")
local function GetCharacterManager()
    if PlayerManager == nil then PlayerManager = sdk.get_managed_singleton("app.CharacterManager") end
	return PlayerManager
end

local PawnManager = sdk.get_managed_singleton("app.PawnManager")
local function GetPawnManager()
    if PawnManager == nil then PawnManager = sdk.get_managed_singleton("app.PawnManager") end
	return PawnManager
end

local MainPawn
local function GetMainPawn()
	local pawnMgr = GetPawnManager()
	if pawnMgr then
		if MainPawn == nil then MainPawn = pawnMgr:call("get_MainPawn") end
		return MainPawn
	end
	return nil
end

local HumanPawn
local function GetHumanPawn()
	local mainPawn = GetMainPawn()
	if mainPawn then
		if HumanPawn == nil then HumanPawn = mainPawn:call("get_CachedHuman") end
		return HumanPawn
	end
	return nil
end

local HumanPlayer
local function GetPlayerHuman()
    local playerMgr = GetCharacterManager()
    if playerMgr then
        if HumanPlayer == nil then HumanPlayer = playerMgr:call("get_ManualPlayerHuman()") end
	    return HumanPlayer
    end
    return nil
end

local HumanParameter
local function GetAbilitiesParam()
	local characterManager = GetCharacterManager()
	if characterManager == nil then return nil end
	HumanParameter = characterManager:call("get_HumanParam")
	if HumanParameter == nil then return nil end
	local abilityParam = HumanParameter:call("get_Ability")
	if abilityParam == nil then return nil end
	local tempAbilitiesParam = {}
	for i = ABILITY_MIN, ABILITY_MAX do
		-- IDs the game has no parameter for are skipped rather than failing the whole setup.
		local ok, param = pcall(abilityParam.call, abilityParam, "getParam", i)
		if ok and param ~= nil then tempAbilitiesParam[tostring(i)] = param end
	end
	if next(tempAbilitiesParam) == nil then return nil end
	return tempAbilitiesParam
end

local function CopyAbilitiesParam(copyParamTo)
	if copyParamTo and next(AbilitiesParam) ~= nil then
		for i = ABILITY_MIN, ABILITY_MAX do
			local param = AbilitiesParam[tostring(i)]
			if param then
				copyParamTo[tostring(i)] = {
					["Value"] = param:get_field("Value"),
					["Value2"] = param:get_field("Value2")
				}
			end
		end
		return true
	end
	return false
end

local function UpdateAbilitiesParam(copyedParam)
	if copyedParam and next(AbilitiesParam) ~= nil then
		for i = ABILITY_MIN, ABILITY_MAX do
			local param = AbilitiesParam[tostring(i)]
			local entry = copyedParam[tostring(i)]
			if param and type(entry) == "table" then
				if entry["Value"] ~= nil then param:set_field("Value", entry["Value"]) end
				if entry["Value2"] ~= nil then param:set_field("Value2", entry["Value2"]) end
			end
		end
		return true
	end
	return false
end

local abilitiesParamInitialized = false
local function InitAbilitiesParam()
	if abilitiesParamInitialized then return true end
	local params = GetAbilitiesParam()
	if params == nil then return false end
	AbilitiesParam = params
	CopyAbilitiesParam(AbilitiesParamDefault)
	if next(AbilitiesParamMod) == nil then CopyAbilitiesParam(AbilitiesParamMod) end
	-- Fill in any entries missing from an older or partial config (e.g. newly added augments).
	for i = ABILITY_MIN, ABILITY_MAX do
		local key = tostring(i)
		local default = AbilitiesParamDefault[key]
		if default then
			local entry = AbilitiesParamMod[key]
			if type(entry) ~= "table" then
				entry = {}
				AbilitiesParamMod[key] = entry
			end
			if entry["Value"] == nil then entry["Value"] = default["Value"] end
			if entry["Value2"] == nil then entry["Value2"] = default["Value2"] end
		end
	end
	if AugmentsOverhualEnabled then UpdateAbilitiesParam(AbilitiesParamMod) end
	abilitiesParamInitialized = true
	return true
end

local JobManagerPawn
local function GetPawnJob()
	local pawnHuman = GetHumanPawn()
	if pawnHuman then
		if JobManagerPawn == nil then JobManagerPawn = pawnHuman:get_field("<JobContext>k__BackingField") end
		if JobManagerPawn == nil then return nil end
		return JobManagerPawn:get_field("CurrentJob")
	end
	return nil
end

local JobManagerPlayer
local function GetPlayerJob()
	local playerHuman = GetPlayerHuman()
	if playerHuman then
		if JobManagerPlayer == nil then JobManagerPlayer = playerHuman:get_field("<JobContext>k__BackingField") end
		if JobManagerPlayer == nil then return nil end
		return JobManagerPlayer:get_field("CurrentJob")
	end
	return nil
end

local PawnAbilityContext
local function GetPawnAbilityContext()
    local pawnHuman = GetHumanPawn()
    if pawnHuman then
        if PawnAbilityContext == nil then PawnAbilityContext = pawnHuman:call("get_AbilityContext()") end
	    return PawnAbilityContext
    end
    return nil
end

local PlayerAbilityContext
local function GetPlayerAbilityContext()
    local playerHuman = GetPlayerHuman()
    if playerHuman then
        if PlayerAbilityContext == nil then PlayerAbilityContext = playerHuman:call("get_AbilityContext()") end
	    return PlayerAbilityContext
    end
    return nil
end

local PlayerID
local function isPlayer(target)
	local playerAbilityContext = GetPlayerAbilityContext()
	local jobPlayer = GetPlayerJob()
	if playerAbilityContext and jobPlayer then
		if PlayerID == nil then PlayerID = playerAbilityContext:call("getEquipAbilityList", jobPlayer) end
		
		return PlayerID == target
	end
	return false
end

local function getArraySize(arr)
	if arr == nil then return 0 end
	local ok, size = pcall(function() return arr:get_size() end)
	if ok and type(size) == "number" then return size end
	ok, size = pcall(function() return arr:call("get_Length") end)
	if ok and type(size) == "number" then return size end
	return 0
end

local function getAbilityValue(arr, index)
	local value = arr:call("Get", index)
	if type(value) == "userdata" then value = value:get_field("value__") end
	return tonumber(value) or 0
end

local reportedUnknownAugments = {}
local function reportUnknownAugment(id, slot, job, target)
	if id == 0 or reportedUnknownAugments[id] then return end
	local name = dataAugments[tostring(id)]
	if type(name) == "string" and name:match("%S") then return end
	Log(string.format(
		": Unknown equipped augment: ID=%d, character=%s, vocation=%s, native slot=%d (zero-based). Missing Augments[\"%d\"] in %s.",
		id, target, tostring(job), slot, id, dataPath))
	reportedUnknownAugments[id] = true
end

-- Use the typed HumanAbilityID[]::Set instead of arr[i] = v, which no longer works for
-- value-type arrays in current REFramework builds.
local function setAbilityValue(arr, index, value)
	arr:call("Set", index, value)
end

local function getAddress(obj)
	if obj == nil then return nil end
	local ok, address = pcall(function() return obj:get_address() end)
	if ok then return address end
	return nil
end

local function createAbilityList(currentList)
	local currentSize = getArraySize(currentList)
	if currentSize <= 0 then return nil end
	-- Do not chain :add_ref() here: it returns a plain REManagedObject and the
	-- SystemArray methods (get_size, indexing) are lost.
	local newList = sdk.create_managed_array("app.HumanAbilityID", ABILITY_ARRAY_SIZE)
	if newList == nil then return nil end
	newList:add_ref()
	if getArraySize(newList) ~= ABILITY_ARRAY_SIZE then return nil end
	-- Only the native slots are copied, so a game-made copy of our array never feeds
	-- previously injected augments back in as "equipped".
	for i = 0, math.min(currentSize, NATIVE_SLOT_COUNT) - 1 do
		setAbilityValue(newList, i, getAbilityValue(currentList, i))
	end
	return newList
end

local function applyAugments(abilityList, enabledAugments, isPawn)
	for i = ABILITY_MIN, ABILITY_MAX do
		local enabled = canUseAugment(i, isPawn) and enabledAugments[tostring(i)]
		setAbilityValue(abilityList, NATIVE_SLOT_COUNT + (i - ABILITY_MIN), enabled and i or 0)
	end
end

-- Returns a set of augment IDs equipped through the game's own augment slots.
local function getNativeEquipped(abilityContext, job, target)
	local equipped = {}
	if abilityContext == nil or job == nil then return equipped end
	local currentEquiped = abilityContext:call("getEquipAbilityList", job)
	if currentEquiped == nil then return equipped end
	local currentList = currentEquiped:get_field("Abilities")
	for i = 0, math.min(getArraySize(currentList), NATIVE_SLOT_COUNT) - 1 do
		local id = getAbilityValue(currentList, i)
		reportUnknownAugment(id, i, job, target)
		if id ~= 0 then equipped[id] = true end
	end
	return equipped
end

local PlayerAbilityState = { list = nil, init = false, target = "Player" }
local PawnAbilityState = { list = nil, init = false, target = "Main Pawn", isPawn = true }

local function resetAbilityState(state)
	state.list = nil
	state.init = false
end

-- Swaps the character's equipped ability array for one with the enabled augments added.
-- When onlyIfStale is set, nothing is done if our array is already in place.
local function updateEquipedList(state, abilityContext, job, enabledAugments, onlyIfStale)
	if abilityContext == nil or job == nil then return false end
	local currentEquiped = abilityContext:call("getEquipAbilityList", job)
	if currentEquiped == nil then return false end
	local currentList = currentEquiped:get_field("Abilities")
	for i = 0, math.min(getArraySize(currentList), NATIVE_SLOT_COUNT) - 1 do
		reportUnknownAugment(getAbilityValue(currentList, i), i, job, state.target)
	end
	local isOurList = state.init and state.list ~= nil and getAddress(currentList) == getAddress(state.list)
	if onlyIfStale and isOurList then return true end
	if not isOurList then
		local newList = createAbilityList(currentList)
		if newList == nil then return false end
		state.list = newList
		state.init = true
	end
	applyAugments(state.list, enabledAugments, state.isPawn)
	if not isOurList then currentEquiped:set_field("Abilities", state.list) end
	return true
end

local function updateEquipedListPlayer(onlyIfStale)
	return updateEquipedList(PlayerAbilityState, GetPlayerAbilityContext(), GetPlayerJob(), dataAugmentsPlayerEnabled, onlyIfStale)
end

local function updateEquipedListPawn(onlyIfStale)
	return updateEquipedList(PawnAbilityState, GetPawnAbilityContext(), GetPawnJob(), dataAugmentsPawnEnabled, onlyIfStale)
end

local PawnID
local function isPawn(target)
	local pawnAbilityContext = GetPawnAbilityContext()
	local jobPawn = GetPawnJob()
	if pawnAbilityContext and jobPawn then
		if PawnID == nil then PawnID = pawnAbilityContext:call("getEquipAbilityList", jobPawn) end
		return PawnID == target
	end
	return false
end

local function save()
	-- Data --
	-- local saveData = {}
	-- saveData["Augments"] = dataAugments
	-- saveData["Augment_Describtions"] = dataAugmentsDescribtion
	-- json.dump_file(dataPath, saveData)
	-- Config --
	local saveConfig = {}
	saveConfig["Player"] = dataAugmentsPlayerEnabled
	saveConfig["Pawn"] = dataAugmentsPawnEnabled
	saveConfig["DescriptiveMode"] = dataDescriptiveMode
	saveConfig["AugmentsOverhualEnabled"] = AugmentsOverhualEnabled
	saveConfig["AugmentsOverhualSettings"] = AbilitiesParamMod
	json.dump_file(configPath, saveConfig)
end

sdk.hook(sdk.find_type_definition("app.GuiManager"):get_method("OnChangeSceneType"),
function() 
end, function()
	HumanPlayer = nil
	JobManagerPlayer = nil
	PlayerAbilityContext = nil
	Player = nil
	MainPawn = nil
	HumanPawn = nil
	JobManagerPawn = nil
	PawnAbilityContext = nil
	PlayerID = nil
	PawnID = nil
	resetAbilityState(PlayerAbilityState)
	resetAbilityState(PawnAbilityState)
end)

re.on_script_reset(function()
	-- Addressed user reset mid game
	if abilitiesParamInitialized and next(AbilitiesParamDefault) ~= nil then UpdateAbilitiesParam(AbilitiesParamDefault) end
end)

re.on_config_save(function()
    save()
end)

local uiInputState = {}
local resetInit = false
local resetConfirm = false
-- ImGuiHoveredFlags_AllowWhenDisabled (ImGui 1.92, not exposed as an enum by REFramework)
local HOVERED_ALLOW_WHEN_DISABLED = 1 << 10
local CROSS_COLOR = 0xFF3C3CE6 -- ABGR: red

-- imgui.set_tooltip treats its text as a printf format string, so escape '%'.
local function setTooltip(text)
	ui.set_tooltip((tostring(text):gsub("%%", "%%%%")))
end

local function drawCross(x, y, size)
	local inset = size * 0.25
	local thickness = math.max(1.5, size * 0.12)
	local left, top, right, bottom = x + inset, y + inset, x + size - inset, y + size - inset
	ui.draw_list_path_clear()
	ui.draw_list_path_line_to({ left, top })
	ui.draw_list_path_line_to({ right, bottom })
	ui.draw_list_path_stroke(CROSS_COLOR, false, thickness)
	ui.draw_list_path_clear()
	ui.draw_list_path_line_to({ right, top })
	ui.draw_list_path_line_to({ left, bottom })
	ui.draw_list_path_stroke(CROSS_COLOR, false, thickness)
end

re.on_draw_ui(function()
	if ui.tree_node(ModStrings["ModName"]) then


		-- Augments Menu
		if ui.tree_node(ModStrings["AugmentsMenu"]) then
			-- local changed, value = ui.checkbox(ModStrings["AugmentsOverhualModeEnable"], AugmentsInfinityEnabled)
			-- if changed then
				-- AugmentsInfinityEnabled = value
				-- save()
			-- end
			
			ui.text_colored(ModStrings["AugmentsMenuNote"], 0xFF00D7FF)
			ui.separator()

			-- local changed, value = ui.checkbox(ModStrings["DiscriptiveMode"], dataDescriptiveMode)
			-- if changed then
			-- 	dataDescriptiveMode = value
			-- 	save()
			-- end

			local targetOptions = { ModStrings["PlayerToggle"], ModStrings["PawnToggle"] }
			local comboTextWidth, comboTextHeight = 0, 0
			for _, option in ipairs(targetOptions) do
				local size = ui.calc_text_size(option)
				if size.x > comboTextWidth then comboTextWidth = size.x end
				if size.y > comboTextHeight then comboTextHeight = size.y end
			end
			-- Widest option + arrow button (roughly square, scales with font) + frame padding.
			ui.set_next_item_width(comboTextWidth + comboTextHeight + 22)
			local targetChanged, targetValue = ui.combo(ModStrings["TargetSelect"], SelectedTarget, targetOptions)
			if targetChanged then SelectedTarget = targetValue end

			local isPawnTarget = SelectedTarget == 2
			local enabledAugments = isPawnTarget and dataAugmentsPawnEnabled or dataAugmentsPlayerEnabled
			local updateEquipedListTarget = isPawnTarget and updateEquipedListPawn or updateEquipedListPlayer
			local okEquipped, nativeEquipped = pcall(function()
				if isPawnTarget then return getNativeEquipped(GetPawnAbilityContext(), GetPawnJob(), "Main Pawn") end
				return getNativeEquipped(GetPlayerAbilityContext(), GetPlayerJob(), "Player")
			end)
			if not okEquipped or type(nativeEquipped) ~= "table" then nativeEquipped = {} end

			-- Pin the box-to-label gap so equipped rows (box and label drawn separately) line up with the rest.
			local labelGap = math.max(4, math.floor(ui.calc_text_size("X").y * 0.3))
			local pushedInnerSpacing = Vector2f ~= nil
			if pushedInnerSpacing then ui.push_style_var(ui.ImGuiStyleVar.ItemInnerSpacing, Vector2f.new(labelGap, labelGap)) end

			-- Augments
			for i = ABILITY_MIN, ABILITY_MAX do
				if canUseAugment(i, isPawnTarget) then
					local key = tostring(i)
					local description = dataAugmentsDescribtion[key]
					local info = dataAugments[key] or ("Augment " .. key)
					if dataDescriptiveMode and description then info = info .. " [" .. description .. "]" end
					if not enabledAugments[key] then enabledAugments[key] = false end
					if nativeEquipped[i] then
						local tooltip = ModStrings["EquippedTooltip"]
						if description then tooltip = tooltip .. "\n" .. description end
						local boxPos = ui.get_cursor_screen_pos()
						ui.begin_disabled()
						ui.checkbox("##AugmentEquipped" .. key, false)
						local hovered = ui.is_item_hovered(HOVERED_ALLOW_WHEN_DISABLED)
						ui.same_line(0, 0)
						-- A label-less checkbox is square, so the cursor now sits on its right edge.
						local boxSize = ui.get_cursor_screen_pos().x - boxPos.x
						ui.same_line(0, labelGap)
						ui.text(info)
						hovered = hovered or ui.is_item_hovered(HOVERED_ALLOW_WHEN_DISABLED)
						ui.end_disabled()
						drawCross(boxPos.x, boxPos.y, boxSize)
						if hovered then setTooltip(tooltip) end
					else
						local changed, value = ui.checkbox(info, enabledAugments[key])
						if description and ui.is_item_hovered() then setTooltip(description) end
						if changed then
							enabledAugments[key] = value
							updateEquipedListTarget()
							save()
						end
					end
				end
			end
			if pushedInnerSpacing then ui.pop_style_var() end
			ui.tree_pop()
		end
		
		
		
		
		-- Augments Overhual Menu
		if ui.tree_node(ModStrings["AugmentsOverhualMenu"]) then
			if not InitAbilitiesParam() then
				ui.text("Augment parameters are not available yet. Load into the game first.")
			else
			
			local changed, value = ui.checkbox(ModStrings["AugmentsOverhualModeEnable"], AugmentsOverhualEnabled)
			if changed then
				AugmentsOverhualEnabled = value
				if AugmentsOverhualEnabled then
					UpdateAbilitiesParam(AbilitiesParamMod)
				else
					UpdateAbilitiesParam(AbilitiesParamDefault)
				end
				for i = ABILITY_MIN, ABILITY_MAX do
					uiInputState[i][1] = false
					uiInputState[i][2] = false
				end
				save()
			end
			ui.same_line()
			
			if imgui.button("Save") then
				UpdateAbilitiesParam(AbilitiesParamMod)
				save()
			end
			ui.same_line()
			
			-- Provide saving grace for misclick
			if imgui.button("Rest") then
				resetInit = true
			end
			if resetInit then
				ui.same_line()
				if imgui.button("NOPE") then
					resetInit = false
					resetConfirm = false
				end
				
				local changed, value = ui.checkbox(ModStrings["AugmentsOverhualModeResetWarning"], resetConfirm)
				if changed then
					resetConfirm = value
				end
				if resetConfirm then
					if imgui.button("Rest Confirm") then
						UpdateAbilitiesParam(AbilitiesParamDefault)
						CopyAbilitiesParam(AbilitiesParamMod)
						save()
						resetInit = false
						resetConfirm = false
					end
				end
			end

			if AugmentsOverhualEnabled then
				-- Augments Active Mode
				for i = ABILITY_MIN, ABILITY_MAX do
					local key = tostring(i)
					-- Augments the game has no parameter for can't be tuned.
					if AbilitiesParamDefault[key] and AbilitiesParamMod[key] and ui.tree_node((dataAugments[key] or ("Augment " .. key)) .. "##Overhaul" .. key) then
						local description = "Description: "
						local descriptionMod = "Mod Machienic: "
						local modValue = AbilitiesParamMod[key]["Value"]
						local modValue2 = AbilitiesParamMod[key]["Value2"]
						local defaultValue = AbilitiesParamDefault[key]["Value"]
						local defaultValue2 = AbilitiesParamDefault[key]["Value2"]
						description = description .. (dataAugmentsDescribtion[key] or "-")
						local modFormat = dataAugmentsModDescribtion[key] or "Stat [1]: %f, Stat [2]: %f"
						local okFormat, formatted = pcall(string.format, descriptionMod .. modFormat, modValue, modValue2)
						descriptionMod = okFormat and formatted or (descriptionMod .. modFormat)
						ui.indent(20)
						ui.text(description)
						ui.text(descriptionMod)
						local slideMax = 1000
						if (tonumber(defaultValue) or 0) < 3 then slideMax = 10 end
						if imgui.small_button("T:1") then uiInputState[i][1] = not uiInputState[i][1] end
						ui.same_line()
						local changed, value = ui.slider_float(ModStrings["AugmentsOverhualMenu_Label_Stat"] .. " [1]", modValue, 0, slideMax)
						if changed then
							if value <= 0 then value = 0.000001 end
							AbilitiesParamMod[tostring(i)]["Value"] = value
						end
						if uiInputState[i][1] then
							ui.indent(36)
							local changed, value, _, __ = ui.input_text("##AugmentStat1", tostring(modValue))
							if changed then
								value = tonumber(value)
								if value then
									if value <= 0 then value = 0.000001 end
									AbilitiesParamMod[tostring(i)]["Value"] = value
								end
							end
							ui.unindent(36)
						end
						local slideMax = 1000
						if (tonumber(defaultValue) or 0) < 3 then slideMax = 10 end
						if ui.small_button("T:2") then uiInputState[i][2] = not uiInputState[i][2] end
						ui.same_line()
						local changed, value = ui.slider_float(ModStrings["AugmentsOverhualMenu_Label_Stat"] .. " [2]", modValue2, 0, slideMax)
						if changed then
							if value <= 0 then value = 0.000001 end
							AbilitiesParamMod[tostring(i)]["Value2"] = value
						end
						if uiInputState[i][2] then
							ui.indent(36)
							local changed, value2, _, __ = ui.input_text("##AugmentStat2", tostring(modValue2))
							if changed then
								value2 = tonumber(value2)
								if value2 then
									if value2 <= 0 then value2 = 0.000001 end
									AbilitiesParamMod[tostring(i)]["Value2"] = value2
								end
							end
							ui.unindent(36)
						end
						ui.unindent(20)
						ui.tree_pop()
					end
				end
			end
			end
			ui.tree_pop()
		end
		ui.tree_pop()
	end
end)

-- re.on_frame(
-- function()
	-- if not initPlayerAbilityList then updateEquipedListPlayer() end
	-- if not initPawnAbilityList then updateEquipedListPawn() end
-- end)


sdk.hook(sdk.find_type_definition("app.PlayerStatusCalculatorParameter"):get_method("getJobStatusParam"),
function (args)
	if not abilitiesParamInitialized then InitAbilitiesParam() end
	updateEquipedListPlayer(true)
	updateEquipedListPawn(true)
end, nil)


-- Vocation switching handling. Handled after the original runs so CurrentJob is already the new vocation.
local jobChangedTarget
sdk.hook(sdk.find_type_definition("app.JobContext"):get_method("setJobChanged(app.Character.JobEnum)"),
function (args)
	jobChangedTarget = sdk.to_managed_object(args[2])
end, function (retval)
	local target = jobChangedTarget
	jobChangedTarget = nil
	local targetAddress = getAddress(target)
	if targetAddress == nil then return retval end

	local playerHuman = GetPlayerHuman()
	if playerHuman and getAddress(playerHuman:get_field("<JobContext>k__BackingField")) == targetAddress then
		resetAbilityState(PlayerAbilityState)
		updateEquipedListPlayer()
		return retval
	end

	local pawnHuman = GetHumanPawn()
	if pawnHuman and getAddress(pawnHuman:get_field("<JobContext>k__BackingField")) == targetAddress then
		resetAbilityState(PawnAbilityState)
		updateEquipedListPawn()
	end
	return retval
end)

-- local isAugmented = false
-- local currentAbilityID
-- local currentEquipedAbility
-- sdk.hook(sdk.find_type_definition("app.AbilityContext.EquipedAbility"):get_method("hasAbility(app.HumanAbilityID)"),
-- function (args)
	-- currentEquipedAbility = sdk.to_managed_object(args[2])
	-- currentAbilityID = tostring(sdk.to_int64(args[3]) & 0xFF)
	-- if isPlayer(currentEquipedAbility) then
		-- isAugmented = dataAugmentsPlayerEnabled[currentAbilityID]
		-- return sdk.PreHookResult.SKIP_ORIGINAL 
	-- end
	-- if isPawn(currentEquipedAbility) then
		-- isAugmented = dataAugmentsPawnEnabled[currentAbilityID]
		-- return sdk.PreHookResult.SKIP_ORIGINAL 
	-- end
	-- return sdk.PreHookResult.CALL_ORIGINAL
-- end, function(retval)
	-- if isAugmented then
		-- isAugmented = false
		-- return sdk.to_ptr(true)
	-- end
	-- return retval
-- end)

function App.Init()
	local data = {}
	local config = {}
	Log("Augments Unleashed Initilization!")
	-- Loading Data
	data = json.load_file(dataPath) or {}
	for key, value in pairs(data) do
		if key == "Augments" then
			dataAugments = data["Augments"]
		end
		if key == "AugmentDescribtions" then
			dataAugmentsDescribtion = data["AugmentDescribtions"]
		end
		if key == "AugmentModDescriptions" then
			dataAugmentsModDescribtion = data["AugmentModDescriptions"]
		end
		if key == "ModStrings" then
			for key, value in pairs(data["ModStrings"]) do
				if key == "Name" then
					if ModStrings["ModName"] ~= value then
						ModStrings["ModName"] = ModStrings["ModName"] .. "[" .. value .. "]"
					end
				end
				if key == "DiscriptiveMode" then
					ModStrings["DiscriptiveMode"] = value
				end
				if key == "PlayerToggle" then
					ModStrings["PlayerToggle"] = value
				end
				if key == "PawnToggle" then
					ModStrings["PawnToggle"] = value
				end
			end
		end
	end
	-- Loading Config
	config = json.load_file(configPath)
	if config then
		for key, value in pairs(config) do
			if key == "Player" then
				dataAugmentsPlayerEnabled = config["Player"]
			end
			if key == "Pawn" then
				dataAugmentsPawnEnabled = config["Pawn"]
			end
			if key == "DescriptiveMode" then
				dataDescriptiveMode = config["DescriptiveMode"]
			end
			if key == "AugmentsOverhualSettings" then
				AbilitiesParamMod = config["AugmentsOverhualSettings"]
			end
			if key == "AugmentsOverhualEnabled" then
				AugmentsOverhualEnabled = config["AugmentsOverhualEnabled"]
			end
		end
	end
	
	-- Augments Init (retried later from the hooks/UI if the game isn't ready yet)
	InitAbilitiesParam()
	
	-- Populate Custom Typeing State
	for i = ABILITY_MIN, ABILITY_MAX do
		uiInputState[i] = {
			[1] = false,
			[2] = false
		}
	end
end

App.Init()
