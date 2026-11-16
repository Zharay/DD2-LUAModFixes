-- k1ng4 + Jarol
-- 1.X

local sdk = sdk
local json = json
local re = re
local imgui = imgui
local math = math
local os = os
local ipairs = ipairs
local dataPath = "RestorationMagicOverhaul.json"

local Cleansable = {
	["3"] = 2, ["6"] = 5, ["9"] = 8, ["12"] = 11,
	["15"] = 14, ["18"] = 17, ["21"] = 20, ["24"] = 23,
	["27"] = 26, ["30"] = 29, ["33"] = 32, ["36"] = 35,
	["51"] = 50, ["54"] = 53, ["99"] = 98, ["100"] = 98,
	["512"] = 505
}
local PlayerManager
local PawnManager
local ItemManager
local CharacterPlayer
local PartyCharacters = {}
local PartyCharacterSet = {}
local PartyHitControllers = {}

local PaeanStates = {}
local AnodyneStates = {}
local SuccorStates = {}
local HalidomStates = {}
local ArrowStates = {}

-- Hit counts are native spell-hit events, not seconds.
local PaeanItemRestoreInterval = 300
local PaeanFullDurationHits = 390
local HalidomFullDurationHits = 450
local AnodyneDurationSeconds = 10
local PaeanDurationSeconds = 15
local PaeanStartDelaySeconds = 3

local defaults = {
	Enabled = true,
	MaxPaeanItems = 5,
	MaxPaeanLossGauge = 0.15,
	MaxAnodyneLossGauge = 0.03,
	DecanterDamageRecovery = 0.2,
	RestorationArrowLossGauge = 0.07
}
-- Integer options use { key, label, "int", max }; percent options store fractions and display a format.
local advancedOptions = {
	{ "MaxPaeanItems", "C Paean: Items restored", "int", 10 },
	{ "MaxPaeanLossGauge", "C Paean: Max loss-gauge recovered (15 seconds)", "percent", "%.1f%%" },
	{ "MaxAnodyneLossGauge", "Anodyne: Max loss-gauge recovered (10 seconds)", "percent", "%.1f%%" },
	{ "DecanterDamageRecovery", "Decanter: Damage dealt recovered as loss gauge", "percent", "%.1f%%" },
	{ "RestorationArrowLossGauge", "Restoration Arrow: Loss-gauge recovered (fully charged)", "percent", "%.1f%%" }
}
local settings = {}

local function resetSpellStates()
	PaeanStates = {}
	AnodyneStates = {}
	SuccorStates = {}
	HalidomStates = {}
	ArrowStates = {}
end

local StoneConditionFlag = sdk.find_type_definition("app.StatusConditionDef.StatusConditionFlag")
	:get_field("Flg_Stone"):get_data()
local FullyChargedArrow = sdk.find_type_definition("app.ShellAdditionalLifeReturn.ChargeState")
	:get_field("ChargeLvEx"):get_data()

local function GetPlayerManager()
	if PlayerManager == nil then
		PlayerManager = sdk.get_managed_singleton("app.CharacterManager")
	end
	return PlayerManager
end

local function GetPawnManager()
	if PawnManager == nil then
		PawnManager = sdk.get_managed_singleton("app.PawnManager")
	end
	return PawnManager
end

local function GetItemManager()
	if ItemManager == nil then
		ItemManager = sdk.get_managed_singleton("app.ItemManager")
	end
	return ItemManager
end

local function addPartyCharacter(character, characters, characterSet, hitControllers)
	if character == nil or characterSet[character] then
		return
	end

	characterSet[character] = true
	characters[#characters + 1] = character

	local hitController = character:call("get_Hit()")
	if hitController ~= nil then
		hitControllers[character] = hitController
	end
end

local function refreshParty()
	local playerManager = GetPlayerManager()
	local player = playerManager and playerManager:call("get_ManualPlayer()")

	CharacterPlayer = player
	PartyCharacters = {}
	PartyCharacterSet = {}
	PartyHitControllers = {}

	if player == nil then
		return false
	end

	addPartyCharacter(player, PartyCharacters, PartyCharacterSet, PartyHitControllers)

	local pawnManager = GetPawnManager()
	local pawns = pawnManager and pawnManager:call("get_PawnCharacterList()")
	if pawns ~= nil then
		for i = 0, pawns:call("get_Count()") - 1 do
			local pawn = pawns:call("get_Item(System.Int32)", i)
			addPartyCharacter(pawn, PartyCharacters, PartyCharacterSet, PartyHitControllers)
		end
	end

	return true
end

local function getHitControllerCharacter(hitController)
	return hitController and hitController:get_field("<CachedCharacter>k__BackingField")
end

local function getCharacterFromDamageInfo(damageInfo, hitControllerField)
	if damageInfo == nil then
		return nil
	end
	return getHitControllerCharacter(damageInfo:get_field(hitControllerField))
end

local function getCharacterHitController(character)
	if character == nil then
		return nil
	end

	local hitController = PartyHitControllers[character]
	if hitController ~= nil then
		return hitController
	end

	return character:call("get_Hit()")
end

local function isFriendly(target)
	if target == nil then
		return false
	end
	if CharacterPlayer == nil then
		refreshParty()
	end
	return CharacterPlayer ~= nil
		and not target:call("isHostile(app.Character)", CharacterPlayer)
end

local function restoreLossGauge(targetHit, amount, isFraction, allowDead)
	if targetHit == nil or amount == nil or amount <= 0 then
		return 0, nil
	end

	if not allowDead then
		local health = targetHit:call("get_Hp()")
		if health == nil or health <= 0 then
			return 0, nil
		end
	end

	local maxHealth = targetHit:call("get_OriginalMaxHp()")
	local reducedMaxHealth = targetHit:call("get_ReducedMaxHp()")
	if maxHealth == nil or maxHealth <= 0 or reducedMaxHealth == nil then
		return 0, nil
	end

	local amountToRestore = isFraction and maxHealth * amount or amount
	local restoreAmount = math.min(amountToRestore, math.max(0, maxHealth - reducedMaxHealth))
	if restoreAmount <= 0 then
		return 0, maxHealth
	end

	targetHit:call("recoverMaxHp(System.Single)", restoreAmount)
	local updatedReducedMaxHealth = targetHit:call("get_ReducedMaxHp()")
	local restored = updatedReducedMaxHealth and math.max(0, updatedReducedMaxHealth - reducedMaxHealth) or 0
	return math.min(restored, restoreAmount), maxHealth
end

local function regenLossGauge(targetHit, fraction, allowDead)
	return restoreLossGauge(targetHit, fraction, true, allowDead)
end

local function nextRot(character)
	local itemManager = GetItemManager()
	if itemManager == nil or character == nil then
		return nil
	end

	local characterId = character:call("get_CharaID()")
	local items = itemManager:call("getStorageMasterList(app.CharacterID)", characterId)
	if items == nil then
		return nil
	end

	for i = 0, items:call("get_Count()") - 1 do
		local item = items:call("get_Item(System.Int32)", i)
		if item ~= nil then
			local itemId = item:call("get_ItemId()")
			local replacementItemId = Cleansable[tostring(itemId)]
			if replacementItemId ~= nil then
				return itemId, replacementItemId
			end
		end
	end
	return nil
end

local function cleanseRot(character)
	local itemManager = GetItemManager()
	if itemManager == nil then
		return false
	end

	local itemId, replacementItemId = nextRot(character)
	if itemId == nil then
		return false
	end

	itemManager:call("deleteItem(System.Int32, System.Int32, app.Character)", itemId, 1, character)
	itemManager:call("getItem(System.Int32, System.Int32, app.Character)", replacementItemId, 1, character)
	return true
end

local function restoreOneExpiredItem()
	for _, character in ipairs(PartyCharacters) do
		if cleanseRot(character) then
			return true
		end
	end
	return false
end

local function newPaeanState()
	return {
		startTime = os.clock(),
		hitCount = 0,
		restoredItems = 0,
		lossGaugeRestored = {},
		targetHitCounts = {}
	}
end

local function beginPaean(args)
	local shellKey = sdk.to_int64(args[2])
	if shellKey == nil or shellKey == 0 then
		return
	end
	refreshParty()
	PaeanStates[shellKey] = newPaeanState()
end

local function curePaeanTargets(state)
	for character, hitCount in pairs(state.targetHitCounts) do
		if settings.Enabled and hitCount >= PaeanFullDurationHits then
			local statusController = character:call("get_StatusConditionCtrl()")
			if statusController ~= nil then
				statusController:call("reqStatusConditionCureAllNoCureDamage()")
			end
		end
	end
end

local function loadData()
	local config = json.load_file(dataPath)
	if config ~= nil and type(config) ~= "table" then
		log.error("[RestorationMagicOverhaul] Invalid settings; using defaults")
	end
	for key, default in pairs(defaults) do
		settings[key] = default
		local value
		if type(config) == "table" then value = config[key] end
		if value ~= nil then
			if type(value) == type(default) then
				settings[key] = value
			else
				log.error("[RestorationMagicOverhaul] Invalid setting " .. key .. "; using default")
			end
		end
	end
	for _, option in ipairs(advancedOptions) do
		local key, kind = option[1], option[3]
		local value = settings[key]
		local isInt = kind == "int"
		local valid = value == value and value >= 0
			and value <= (isInt and option[4] or 1)
			and (not isInt or value == math.floor(value))
		if not valid then
			log.error("[RestorationMagicOverhaul] Invalid setting " .. key .. "; using default")
			settings[key] = defaults[key]
		end
	end
	json.dump_file(dataPath, settings)
end

-- Celestial Paean
local holyGlare = sdk.find_type_definition("app.HolyGlareShell")
sdk.hook(holyGlare:get_method("awake"), function(args)
	beginPaean(args)
end, nil)

sdk.hook(holyGlare:get_method("evShellStart"), function(args)
	beginPaean(args)
end, nil)

sdk.hook(holyGlare:get_method("onAttackHit(app.HitController.DamageInfo)"), function(args)
	if not settings.Enabled then return end
	local shellKey = sdk.to_int64(args[2])
	local damageInfo = sdk.to_managed_object(args[3])
	if shellKey == nil or shellKey == 0 or damageInfo == nil then
		return
	end

	if CharacterPlayer == nil then
		refreshParty()
	end

	local targetHit = damageInfo:get_field("<DamageHitController>k__BackingField")
	local target = getHitControllerCharacter(targetHit)
	if target == nil or not PartyCharacterSet[target] then
		return
	end

	local state = PaeanStates[shellKey]
	if state == nil then
		state = newPaeanState()
		PaeanStates[shellKey] = state
	end

	state.hitCount = state.hitCount + 1
	state.targetHitCounts[target] = (state.targetHitCounts[target] or 0) + 1

	-- Exclude the casting delay before spreading recovery over the active duration.
	local elapsed = math.max(0, os.clock() - state.startTime - PaeanStartDelaySeconds)
	local progress = math.min(elapsed / PaeanDurationSeconds, 1)
	local restoredFraction = state.lossGaugeRestored[target] or 0
	local dueFraction = settings.MaxPaeanLossGauge * progress - restoredFraction
	if dueFraction > 0 then
		local restored, maxHealth = regenLossGauge(targetHit, dueFraction)
		if maxHealth ~= nil and maxHealth > 0 then
			state.lossGaugeRestored[target] = restoredFraction + restored / maxHealth
		end
	end

	if state.hitCount % PaeanItemRestoreInterval == 0
		and state.restoredItems < settings.MaxPaeanItems
		and restoreOneExpiredItem()
	then
		state.restoredItems = state.restoredItems + 1
	end
end, nil)

sdk.hook(holyGlare:get_method("evShellDestroy"), function(args)
	local shellKey = sdk.to_int64(args[2])
	local state = shellKey and PaeanStates[shellKey]
	if state ~= nil then
		curePaeanTargets(state)
		PaeanStates[shellKey] = nil
	end
end, nil)

-- Restoration Arrow
local lifeReturn = sdk.find_type_definition("app.ShellAdditionalLifeReturn")
sdk.hook(lifeReturn:get_method("onStart"), function(args)
	refreshParty()
	local shellKey = sdk.to_int64(args[2])
	if shellKey ~= nil and shellKey ~= 0 then
		ArrowStates[shellKey] = {}
	end
end, nil)

sdk.hook(lifeReturn:get_method("onAttackHit(app.HitController.DamageInfo)"), function(args)
	if not settings.Enabled then return end
	local shellKey = sdk.to_int64(args[2])
	local damageInfo = sdk.to_managed_object(args[3])
	local shell = sdk.to_managed_object(args[2])
	if shellKey == nil or shellKey == 0 or shell == nil
		or damageInfo == nil or shell:get_field("ChargeType") ~= FullyChargedArrow
	then
		return
	end

	if CharacterPlayer == nil then
		refreshParty()
	end

	local owner = getCharacterFromDamageInfo(damageInfo, "<AttackOwnerHitController>k__BackingField")
	if owner ~= CharacterPlayer then
		return
	end

	local target = getCharacterFromDamageInfo(damageInfo, "<DamageHitController>k__BackingField")
	local targetHit = damageInfo:get_field("<DamageHitController>k__BackingField")
	if target == nil or targetHit == nil then
		return
	end

	local hitTargets = ArrowStates[shellKey]
	if hitTargets == nil then
		hitTargets = {}
		ArrowStates[shellKey] = hitTargets
	end
	if hitTargets[target] then
		return
	end

	regenLossGauge(targetHit, settings.RestorationArrowLossGauge, true)
	hitTargets[target] = true
end, nil)

-- Argent Succor
local fullRecover = sdk.find_type_definition("app.Job03CastFullRecover")
sdk.hook(fullRecover:get_method("start(via.behaviortree.ActionArg)"), function(args)
	refreshParty()
	local actionKey = sdk.to_int64(args[2])
	if actionKey ~= nil and actionKey ~= 0 then
		SuccorStates[actionKey] = false
	end
end, nil)

sdk.hook(fullRecover:get_method("updateFullRecoverEffect"), function(args)
	if not settings.Enabled then return end
	local actionKey = sdk.to_int64(args[2])
	local action = sdk.to_managed_object(args[2])
	if actionKey == nil or actionKey == 0 or action == nil or SuccorStates[actionKey] then
		return
	end

	local target = action:get_field("AimChara")
	if target ~= nil and isFriendly(target) then
		local targetHit = getCharacterHitController(target)
		if targetHit ~= nil then
			regenLossGauge(targetHit, 0.07)
			SuccorStates[actionKey] = true
		end
	end
end, nil)

-- Anodyne
local anodyne = sdk.find_type_definition("app.AnodyneShell")
local function beginAnodyne(args)
	refreshParty()
	local shellKey = sdk.to_int64(args[2])
	if shellKey ~= nil and shellKey ~= 0 then
		AnodyneStates[shellKey] = { startTime = os.clock(), restoredByTarget = {} }
	end
end

sdk.hook(anodyne:get_method("awake"), beginAnodyne, nil)
sdk.hook(anodyne:get_method("evShellStart"), beginAnodyne, nil)

sdk.hook(anodyne:get_method("onAttackHit(app.HitController.DamageInfo)"), function(args)
	if not settings.Enabled then return end
	local shellKey = sdk.to_int64(args[2])
	local damageInfo = sdk.to_managed_object(args[3])
	if shellKey == nil or shellKey == 0 or damageInfo == nil then
		return
	end

	local target = getCharacterFromDamageInfo(damageInfo, "<DamageHitController>k__BackingField")
	if not isFriendly(target) then
		return
	end

	local state = AnodyneStates[shellKey]
	if state == nil then
		state = { startTime = os.clock(), restoredByTarget = {} }
		AnodyneStates[shellKey] = state
	end
	local restoredByTarget = state.restoredByTarget

	-- Recovery scales with elapsed time so the maximum is reached over the spell's duration, regardless of hit rate.
	local progress = math.min((os.clock() - state.startTime) / AnodyneDurationSeconds, 1)
	local restoredFraction = restoredByTarget[target] or 0
	local dueFraction = settings.MaxAnodyneLossGauge * progress - restoredFraction
	if dueFraction > 0 then
		local restored, maxHealth = regenLossGauge(
			damageInfo:get_field("<DamageHitController>k__BackingField"),
			dueFraction
		)
		if maxHealth ~= nil and maxHealth > 0 then
			restoredByTarget[target] = restoredFraction + restored / maxHealth
		end
	end
end, nil)

-- Decanter
local saintDrain = sdk.find_type_definition("app.ShellAdditionalSaintDrain")
sdk.hook(saintDrain:get_method("awake"), function()
	refreshParty()
end, nil)

sdk.hook(saintDrain:get_method("onAtkCalcDamageEnd(app.HitController.DamageInfo)"), function(args)
	if not settings.Enabled then return end
	local damageInfo = sdk.to_managed_object(args[3])
	if damageInfo == nil then
		return
	end

	local caster = getCharacterFromDamageInfo(damageInfo, "<AttackOwnerHitController>k__BackingField")
	local casterHit = PartyHitControllers[caster]
	local damage = damageInfo:get_field("Damage")
	if casterHit ~= nil and damage ~= nil and damage > 0 then
		-- Only the normal max-HP ceiling applies, with no cumulative recovery cap.
		restoreLossGauge(casterHit, damage * settings.DecanterDamageRecovery, false)
	end
end, nil)

-- Halidom
local cureSpot = sdk.find_type_definition("app.CureSpotShell")
sdk.hook(cureSpot:get_method("onShellStart"), function(args)
	refreshParty()
	local shellKey = sdk.to_int64(args[2])
	if shellKey ~= nil and shellKey ~= 0 then
		HalidomStates[shellKey] = {}
	end
end, nil)

sdk.hook(cureSpot:get_method("onAttackHit(app.HitController.DamageInfo)"), function(args)
	if not settings.Enabled then return end
	local shellKey = sdk.to_int64(args[2])
	local damageInfo = sdk.to_managed_object(args[3])
	if shellKey == nil or shellKey == 0 or damageInfo == nil then
		return
	end

	local target = getCharacterFromDamageInfo(damageInfo, "<DamageHitController>k__BackingField")
	if not isFriendly(target) then
		return
	end

	local hitCounts = HalidomStates[shellKey]
	if hitCounts == nil then
		hitCounts = {}
		HalidomStates[shellKey] = hitCounts
	end

	local hitCount = (hitCounts[target] or 0) + 1
	hitCounts[target] = hitCount
	if hitCount == HalidomFullDurationHits then
		local statusController = target:call("get_StatusConditionCtrl()")
		if statusController ~= nil then
			statusController:call(
				"reqStatusConditionCure(app.StatusConditionDef.StatusConditionFlag)",
				StoneConditionFlag
			)
		end
	end
end, nil)

sdk.hook(sdk.find_type_definition("app.GuiManager"):get_method("OnChangeSceneType"), nil, function()
	CharacterPlayer = nil
	PlayerManager = nil
	PawnManager = nil
	ItemManager = nil
	PartyCharacters = {}
	PartyCharacterSet = {}
	PartyHitControllers = {}
	resetSpellStates()
end)

loadData()

re.on_draw_ui(function()
	if not imgui.tree_node("Restoration Magic Overhaul##RestorationMagicOverhaul") then return end

	local changed, enabled = imgui.checkbox("Enabled##RestorationMagicOverhaul", settings.Enabled)
	if changed then
		settings.Enabled = enabled
		resetSpellStates()
	end

	if imgui.tree_node("Advanced##RestorationMagicOverhaul") then
		imgui.text("Recovery percentages are of original max HP, except Decanter (damage dealt).")
		for _, option in ipairs(advancedOptions) do
			local key, label, kind, extra = option[1], option[2], option[3], option[4]
			local id = label .. "##RMO_" .. key
			if kind == "int" then
				local edited, value = imgui.slider_int(id, settings[key], 0, extra)
				if edited then
					settings[key] = math.max(0, math.min(math.floor(value), extra))
					changed = true
				end
			else
				local edited, value = imgui.slider_float(id, settings[key] * 100, 0, 100, extra)
				if edited then
					settings[key] = math.max(0, math.min(value / 100, 1))
					changed = true
				end
			end
		end
		imgui.tree_pop()
	end

	if changed then
		json.dump_file(dataPath, settings)
	end
	imgui.tree_pop()
end)

re.on_config_save(function()
	json.dump_file(dataPath, settings)
end)
