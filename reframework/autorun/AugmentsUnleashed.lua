-- Authur K1ng4
-- Version 2.2
-- This took me forever :D

local re = re
local sdk = sdk
local json = json
local ui = imgui
local dataPath = "AugmentsUnleashed.json"
local configPath = "AugmentsUnleashedConfig.json"
local PlayerSelected = true
local PawnSelected = false
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
	["PlayerToggle"] = "Player's Enabled Augments",
	["PawnToggle"] = "Pawn's Enabled Augments",
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

local App = {
    _version = "1.0"
}

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
	pawnMgr = GetPawnManager()
	if pawnMgr then
		if MainPawn == nil then MainPawn = pawnMgr:call("get_MainPawn") end
		return MainPawn
	end
	return nil
end

local HumanPawn
local function GetHumanPawn()
	mainPawn = GetMainPawn()
	if mainPawn then
		if HumanPawn == nil then HumanPawn = mainPawn:call("get_CachedHuman") end
		return HumanPawn
	end
	return nil
end

local HumanPlayer
local function GetPlayerHuman()
    playerMgr = GetCharacterManager()
    if playerMgr then
        if HumanPlayer == nil then HumanPlayer = playerMgr:call("get_ManualPlayerHuman()") end
	    return HumanPlayer
    end
    return nil
end

local HumanParameter
local function GetAbilitiesParam()
	HumanParameter = GetCharacterManager():call("get_HumanParam")
	local abilityParam = HumanParameter:call("get_Ability")
	local tempAbilitiesParam = {}
	for i = 4, 50 do
		tempAbilitiesParam[tostring(i)] = abilityParam:call("getParam", i)
	end
	return tempAbilitiesParam
end

local function CopyAbilitiesParam(copyParamTo)
	if next(AbilitiesParam) == nil then AbilitiesParam = GetAbilitiesParam() end
	if copyParamTo then
		for i = 4, 50 do
			copyParamTo[tostring(i)] = {
				["Value"] = AbilitiesParam[tostring(i)]:get_field("Value"),
				["Value2"] = AbilitiesParam[tostring(i)]:get_field("Value2")
			}
		end
		return true
	end
	return false
end

local function UpdateAbilitiesParam(copyedParam)
	if next(AbilitiesParam) == nil then AbilitiesParam = GetAbilitiesParam() end
	if copyedParam then
		for i = 4,50 do
			AbilitiesParam[tostring(i)]:set_field("Value", copyedParam[tostring(i)]["Value"])
			AbilitiesParam[tostring(i)]:set_field("Value2", copyedParam[tostring(i)]["Value2"])
		end
		return true
	end
	return false
end

local JobManagerPawn
local function GetPawnJob()
	local JobPlayer
	pawnHuman = GetHumanPawn()
	if pawnHuman then
		if JobManagerPawn == nil then JobManagerPawn = pawnHuman:get_field("<JobContext>k__BackingField") end
		JobPlayer = JobManagerPawn:get_field("CurrentJob")
		return JobPlayer
	end
	return nil
end

local JobManagerPlayer
local function GetPlayerJob()
	local JobPlayer
	playerHuman = GetPlayerHuman()
	if playerHuman then
		if JobManagerPlayer == nil then JobManagerPlayer = playerHuman:get_field("<JobContext>k__BackingField") end
		JobPlayer = JobManagerPlayer:get_field("CurrentJob")
		return JobPlayer
	end
	return nil
end

local PawnAbilityContext
local function GetPawnAbilityContext()
    pawnHuman = GetHumanPawn()
    if pawnHuman then
        if PawnAbilityContext == nil then PawnAbilityContext = pawnHuman:call("get_AbilityContext()") end
	    return PawnAbilityContext
    end
    return nil
end

local PlayerAbilityContext
local function GetPlayerAbilityContext()
    playerHuman = GetPlayerHuman()
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

local PlayerAbilityList
local initPlayerAbilityList = false
-- local PlayerCurrentAbilityList
local function updateEquipedListPlayer()
	local playerAbilityContext = GetPlayerAbilityContext()
	local jobPlayer = GetPlayerJob()
	local tempAbilityList
	local PlayerCurrentAbilityList
	if PlayerAbilityList == nil then PlayerAbilityList = sdk.create_managed_array("app.HumanAbilityID", 53):add_ref() end
	-- Problem when array being create, try again.
	if PlayerAbilityList ~= nil then
		if PlayerAbilityList:get_size() ~= 53 then
			-- PlayerAbilityList:release()
			PlayerAbilityList = nil
		end
	end
	if PlayerAbilityList ~= nil and playerAbilityContext and jobPlayer then
		-- if PlayerCurrentAbilityList == nil then PlayerCurrentAbilityList = playerAbilityContext:call("getEquipAbilityList", jobPlayer) end
		PlayerCurrentAbilityList = playerAbilityContext:call("getEquipAbilityList", jobPlayer)
		if not initPlayerAbilityList then
			-- Populate PlayerAbilityList
			tempAbilityList = PlayerCurrentAbilityList:get_field("Abilities")
			for key, value in pairs(tempAbilityList) do
				PlayerAbilityList[key] = value:get_field("value__")
			end
			for i = 4,50 do
				if dataAugmentsPlayerEnabled[tostring(i)] then
					PlayerAbilityList[i+2] = i
				else
					PlayerAbilityList[i+2] = 0
				end
			end
			initPlayerAbilityList = true
		end
		PlayerCurrentAbilityList:set_field("Abilities", PlayerAbilityList)
		return true
	end
	return false
end

local PawnAbilityList
local initPawnAbilityList = false
-- local PawnCurrentAbilityList
local function updateEquipedListPawn()
	local pawnAbilityContext = GetPawnAbilityContext()
	local jobPawn = GetPawnJob()
	local tempAbilityList
	local PawnCurrentAbilityList

	if PawnAbilityList == nil then PawnAbilityList = sdk.create_managed_array("app.HumanAbilityID", 53):add_ref() end
	-- Problem when array being create, try again.
	if PawnAbilityList ~= nil then
		if PawnAbilityList:get_size() ~= 53 then
			-- PawnAbilityList:release()
			PawnAbilityList = nil
		end
	end
	if PawnAbilityList ~= nil and pawnAbilityContext and jobPawn then
		-- if PawnCurrentAbilityList == nil then PawnCurrentAbilityList = pawnAbilityContext:call("getEquipAbilityList", jobPawn) end
		PawnCurrentAbilityList = pawnAbilityContext:call("getEquipAbilityList", jobPawn)
		if not initPawnAbilityList then
			-- Populate PawnAbilityList
			tempAbilityList = PawnCurrentAbilityList:get_field("Abilities")
			local index = 0
			for key, value in pairs(tempAbilityList) do
				PawnAbilityList[key] = value:get_field("value__")
			end
			for i = 4,50 do
				if dataAugmentsPawnEnabled[tostring(i)] then
					PawnAbilityList[i+2] = i
				else
					PawnAbilityList[i+2] = 0
				end
			end
			initPawnAbilityList = true
		end
		PawnCurrentAbilityList:set_field("Abilities", PawnAbilityList)
		return true
	end
	return false
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
	-- PlayerAbilityList:release()
	-- PawnAbilityList:release()
	PlayerAbilityList = nil
	PawnAbilityList = nil
	-- PlayerCurrentAbilityList = nil
	-- PawnCurrentAbilityList = nil
	initPawnAbilityList = false
	initPlayerAbilityList = false
end)

re.on_script_reset(function()
	-- Addressed user reset mid game
	if next(AbilitiesParamDefault) == nill then UpdateAbilitiesParam(AbilitiesParamDefault) end
end)

re.on_config_save(function()
    save()
end)

local uiInputState = {}
local resetInit = false
local resetConfirm = false
re.on_draw_ui(function()
	if ui.tree_node(ModStrings["ModName"]) then


		-- Augments Menu
		if ui.tree_node(ModStrings["AugmentsMenu"]) then
			-- local changed, value = ui.checkbox(ModStrings["AugmentsOverhualModeEnable"], AugmentsInfinityEnabled)
			-- if changed then
				-- AugmentsInfinityEnabled = value
				-- save()
			-- end
			
			local changed, value = ui.checkbox(ModStrings["DiscriptiveMode"], dataDescriptiveMode)
			if changed then
				dataDescriptiveMode = value
				save()
			end
			
			if PlayerSelected then
				local changed, value = ui.checkbox(ModStrings["PlayerToggle"], PlayerSelected)
				if changed then
					PlayerSelected = value
					PawnSelected = not value
					save()
				end

				-- Augments 
				for i = 4,50 do
					-- Description
					local info = dataAugments[tostring(i)]
					if dataDescriptiveMode then info = info .. " [" .. dataAugmentsDescribtion[tostring(i)] .. "]" end
					-- Option
					if not dataAugmentsPlayerEnabled[tostring(i)] then dataAugmentsPlayerEnabled[tostring(i)] = false end
					local changed, value = ui.checkbox(info, dataAugmentsPlayerEnabled[tostring(i)])
					if changed then
						dataAugmentsPlayerEnabled[tostring(i)] = value
						if PlayerAbilityList == nil then updateEquipedListPlayer() end
						if dataAugmentsPlayerEnabled[tostring(i)] then
							PlayerAbilityList[i+2] = i
						else
							PlayerAbilityList[i+2] = 0
						end
						updateEquipedListPlayer()
						save()
					end
				end
			end
			
			if PawnSelected then
				local changed, value = ui.checkbox(ModStrings["PawnToggle"], PawnSelected)
				if changed then
					PawnSelected = value
					PlayerSelected = not value
					save()
				end

				-- Augments 
				for i = 4,50 do
					-- Description
					local info = dataAugments[tostring(i)]
					if dataDescriptiveMode then info = info .. " [" .. dataAugmentsDescribtion[tostring(i)] .. "]" end
					-- Option
					if not dataAugmentsPawnEnabled[tostring(i)] then dataAugmentsPawnEnabled[tostring(i)] = false end
					local changed, value = ui.checkbox(info, dataAugmentsPawnEnabled[tostring(i)])
					if changed then
						dataAugmentsPawnEnabled[tostring(i)] = value
						if PawnAbilityList == nil then updateEquipedListPawn() end
						if dataAugmentsPawnEnabled[tostring(i)] then
							PawnAbilityList[i+2] = i
						else
							PawnAbilityList[i+2] = 0
						end
						updateEquipedListPawn()
						save()
					end
				end
			end
			ui.tree_pop()
		end
		
		
		
		
		-- Augments Overhual Menu
		if ui.tree_node(ModStrings["AugmentsOverhualMenu"]) then
			
			local changed, value = ui.checkbox(ModStrings["AugmentsOverhualModeEnable"], AugmentsOverhualEnabled)
			if changed then
				AugmentsOverhualEnabled = value
				if AugmentsOverhualEnabled then
					UpdateAbilitiesParam(AbilitiesParamMod)
				else
					UpdateAbilitiesParam(AbilitiesParamDefault)
				end
				for i = 4, 50 do
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
				if next(AbilitiesParam) == nil then AbilitiesParam = GetAbilitiesParam() end
				-- Augments Active Mode
				for i = 4,50 do
					if ui.tree_node(dataAugments[tostring(i)]) then
						local description = "Description: "
						local descriptionMod = "Mod Machienic: "
						local modValue = AbilitiesParamMod[tostring(i)]["Value"]
						local modValue2 = AbilitiesParamMod[tostring(i)]["Value2"]
						local defaultValue = AbilitiesParamDefault[tostring(i)]["Value"]
						local defaultValue2 = AbilitiesParamDefault[tostring(i)]["Value2"]
						description = description .. dataAugmentsDescribtion[tostring(i)]
						descriptionMod = string.format(descriptionMod .. dataAugmentsModDescribtion[tostring(i)], modValue, modValue2)
						ui.indent(20)
						ui.text(description)
						ui.text(descriptionMod)
						local slideMax = 1000
						if tonumber(defaultValue) < 3 then slideMax = 10 end
						if imgui.small_button("T:1") then uiInputState[i][1] = not uiInputState[i][1] end
						ui.same_line()
						local changed, value = ui.slider_float(ModStrings["AugmentsOverhualMenu_Label_Stat"] .. " [1]", modValue, 0, slideMax)
						if changed then
							if value <= 0 then value = 0.000001 end
							AbilitiesParamMod[tostring(i)]["Value"] = value
						end
						if uiInputState[i][1] then
							ui.indent(36)
							local changed, value, _, __ = ui.input_text("", modValue)
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
						if tonumber(defaultValue) < 3 then slideMax = 10 end
						if ui.small_button("T:2") then uiInputState[i][2] = not uiInputState[i][2] end
						ui.same_line()
						local changed, value = ui.slider_float(ModStrings["AugmentsOverhualMenu_Label_Stat"] .. " [2]", modValue2, 0, slideMax)
						if changed then
							if value <= 0 then value = 0.000001 end
							AbilitiesParamMod[tostring(i)]["Value2"] = value
						end
						if uiInputState[i][2] then
							ui.indent(36)
							local changed, value2, _, __ = ui.input_text("", modValue2)
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
	if not initPlayerAbilityList then updateEquipedListPlayer() end
	if not initPawnAbilityList then updateEquipedListPawn() end
end, nil)


-- Vocation switching handling.
sdk.hook(sdk.find_type_definition("app.JobContext"):get_method("setJobChanged(app.Character.JobEnum)"),
function (args)
	local target = sdk.to_managed_object(args[2])
	-- print(tostring(target))
	-- print(tostring(GetPlayerHuman():get_field("<JobContext>k__BackingField")))
	if target == GetPlayerHuman():get_field("<JobContext>k__BackingField") then
		-- print("Is Player")
		initPlayerAbilityList = false
		PlayerAbilityList = nil
		updateEquipedListPlayer()
	else
		-- print("Is MainPawn")
		initPawnAbilityList = false
		PawnAbilityList = nil
		updateEquipedListPawn()
	end
end, nil)

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
	print("Augments Unleashed Initilization!")
	-- Loading Data
	data = json.load_file(dataPath)
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
				dataAugmentsDescribtive = config["DescriptiveMode"]
			end
			if key == "AugmentsOverhualSettings" then
				AbilitiesParamMod = config["AugmentsOverhualSettings"]
			end
			if key == "AugmentsOverhualEnabled" then
				AugmentsOverhualEnabled = config["AugmentsOverhualEnabled"]
			end
		end
	end
	
	-- Augments Init
	AbilitiesParam = GetAbilitiesParam()
	CopyAbilitiesParam(AbilitiesParamDefault)
	if next(AbilitiesParamMod) == nill then CopyAbilitiesParam(AbilitiesParamMod) end
	if AugmentsOverhualEnabled then UpdateAbilitiesParam(AbilitiesParamMod) end
	
	-- Populate Custom Typeing State
	for i = 4, 50 do
		uiInputState[i] = {
			[1] = false,
			[2] = false
		}
	end
end

App.Init()
