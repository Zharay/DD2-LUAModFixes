-- k1ng4
-- 1.2

local re = re
local sdk = sdk
local json = json
local dataPath = "RestorationMagicOverhaul.json"
local next = next
local Cleansable = {}
local PlayerAndPawns = {}

local PlayerManager = sdk.get_managed_singleton("app.CharacterManager")
local function GetPlayerManager()
    if PlayerManager == nil then PlayerManager = sdk.get_managed_singleton("app.CharacterManager") end
	return PlayerManager
end

local PawnManager = sdk.get_managed_singleton("app.PawnManager")
local function GetPawnManager()
    if PawnManager == nil then PawnManager = sdk.get_managed_singleton("app.PawnManager") end
	return PawnManager
end

local ItemManager = sdk.get_managed_singleton("app.ItemManager")
local function GetItemManager()
    if ItemManager == nil then ItemManager = sdk.get_managed_singleton("app.ItemManager") end
	return ItemManager
end

local CharacterPlayer
local function GetPlayerCharacter()
    playerMgr = GetPlayerManager()
    if playerMgr then
        if CharacterPlayer == nil then CharacterPlayer = playerMgr:call("get_ManualPlayer()") end
	    return CharacterPlayer
    end
    return nil
end

local function updatePlayerAndPawns()
	PlayerAndPawns = {}
	PlayerAndPawns[GetPlayerCharacter()] = GetPlayerCharacter():call('get_Human()'):get_field("Hit")
	PlayerAndPawns[0] = GetPlayerCharacter()
	local pawns = GetPawnManager():call("get_PawnCharacterList()")
	if pawns then
		for i = 0, pawns:call("get_Count()")-1 do
			local tempPawn = pawns:call("get_Item(System.Int32)", i)
			PlayerAndPawns[pawns:call("get_Item(System.Int32)", i)] = tempPawn:call('get_Human()'):get_field("Hit")
			PlayerAndPawns[i+1] = tempPawn
		end
	end
end

local function nextRot(characterID)
	local items = GetItemManager():call("getStorageMasterList(app.CharacterID)", characterID)
	for i = 0, items:call("get_Count()") - 1 do
		local item = items:call("get_Item(System.Int32)", i)
		if item ~= nil then
			local id = item:call("get_ItemId()")
			-- name = item:call("get_ItemData()"):call("get_item_name(System.Int32)", id)
			-- print("ID: " .. tostring(id))
			-- print("Item: " .. name)
			if Cleansable[tostring(id)] then
				return id
			end
		end
	end
end

local function cleanseRot(targetCharcter)
	local currentRot = nextRot(targetCharcter:call("get_CharaID"))
	if currentRot then
		ItemManager:call("deleteItem(System.Int32, System.Int32, app.Character)", currentRot, 1, targetCharcter)
		ItemManager:call("getItem(System.Int32, System.Int32, app.Character, System.Boolean, System.Boolean, System.Boolean, app.ItemManager.GetItemEventType, System.Boolean, System.Boolean)", Cleansable[tostring(currentRot)], 1, targetCharcter, true, false, false, 1, false, false)
		return true
	end
	return false
end

local function regenLossGage(targetHealth, amount)
	local health = targetHealth:call("get_Hp()")
	if health > 0 then
		local maxHealth = targetHealth:call("get_OriginalMaxHp()")
		local lossGage = targetHealth:call("get_ReducedMaxHp()");
		local heal = maxHealth * amount
		targetHealth:call("set_ReducedMaxHp(System.Single)", math.min(lossGage+heal, maxHealth))
		return true
	end
	return false
end

local function loadData()
	config = json.load_file(dataPath)
	if config then
		for key, value in pairs(config) do
			if key == "Cleansable" then
				Cleansable = config["Cleansable"]
			end
		end
	end
end

local function init()
	CharacterPlayer = nil
	updatePlayerAndPawns()
end


-- Celestial Paean
sdk.hook(sdk.find_type_definition("app.HolyGlareShell"):get_method("awake"),
function (args)
	init()
end, nil)

local countCleanse = 0
local cureCount = {}
sdk.hook(sdk.find_type_definition("app.HolyGlareShell"):get_method("onAttackHit"),
function (args)
	target = sdk.to_managed_object(args[3]):get_field("<DamageOwnerHitController>k__BackingField"):get_field("<CachedCharacter>k__BackingField")
	if PlayerAndPawns[target] then
		if not cureCount[target] then cureCount[target] = 0 end
		countCleanse = countCleanse+1
		cureCount[target] = cureCount[target] + 1
		-- Regen 15% if full effect
		regenLossGage(PlayerAndPawns[target], 0.000375)
		-- Cure negative status effects
		-- target:call("get_StatusConditionCtrl()"):call("reqStatusConditionCureAllNoCureDamage()")
		-- print(countCleanse)
	end
	-- if not target:call("isHostile(app.Character)", PlayerAndPawns[0]) then
		-- -- Cure negative status effects
		-- target:call("get_StatusConditionCtrl()"):call("reqStatusConditionCureAllNoCureDamage()")
	-- end
	if (countCleanse % 300) == 0 then
		if cleanseRot(PlayerAndPawns[0]) then
		elseif cleanseRot(PlayerAndPawns[1]) then
		elseif cleanseRot(PlayerAndPawns[2]) then
		else
			cleanseRot(PlayerAndPawns[3])
		end
	end
	for key, value in pairs(cureCount) do
		if value % 390 == 0 then
			key:call("get_StatusConditionCtrl()"):call("reqStatusConditionCureAllNoCureDamage()")
		end
	end
end, nil)

sdk.hook(sdk.find_type_definition("app.HolyGlareShell"):get_method("evShellDestroy"),
function (args)
	countCleanse = 0
end, nil)

-- Recovery Arrow
sdk.hook(sdk.find_type_definition("app.ShellAdditionalLifeReturn"):get_method("onAttackHit(app.HitController.DamageInfo)"),
function (args)
	local target = sdk.to_managed_object(args[3])
	if target:get_field("<AttackOwnerHitController>k__BackingField"):get_field("<CachedCharacter>k__BackingField") == GetPlayerCharacter() then
		if sdk.to_managed_object(args[2]):get_field("<DetailParam>k__BackingField"):get_field("IsRevive") then
			regenLossGage(target:get_field("<DamageHitController>k__BackingField"), 0.07)
		end
	end
end, nil)

-- Argent Succor
local isCured = false
sdk.hook(sdk.find_type_definition("app.Job03CastFullRecover"):get_method("start"),
function (args)
	init()
	isCured = false
end, nil)

sdk.hook(sdk.find_type_definition("app.Job03CastFullRecover"):get_method("updateFullRecoverEffect"),
function (args)
	local target = sdk.to_managed_object(args[2]):get_field("AimChara")
	if target ~= nil then
		if not target:call("isHostile(app.Character)", PlayerAndPawns[0]) then
			-- Regen 7%
			targetHit = target:call('get_Human()'):get_field("Hit")
			if targetHit ~= nil then
				regenLossGage(targetHit, 0.07)
			end
		end
	end
end, nil)

-- Anodyne
sdk.hook(sdk.find_type_definition("app.AnodyneShell"):get_method("awake"),
function (args)
	init()
end, nil)

sdk.hook(sdk.find_type_definition("app.AnodyneShell"):get_method("onAttackHit"),
function (args)
	local target = sdk.to_managed_object(args[3]):get_field("<DamageOwnerHitController>k__BackingField"):get_field("<CachedCharacter>k__BackingField")
	if target ~= nil then
		if not target:call("isHostile(app.Character)", PlayerAndPawns[0]) then
			targetHit = target:call('get_Human()'):get_field("Hit")
			if targetHit ~= nil then
				regenLossGage(targetHit, 0.00012)
			end
		end
	end
end, nil)


-- Dechanter
sdk.hook(sdk.find_type_definition("app.ShellAdditionalSaintDrain"):get_method("awake"),
function (args)
	init()
end, nil)

sdk.hook(sdk.find_type_definition("app.ShellAdditionalSaintDrain"):get_method("onAtkCalcDamageEnd"),
function (args)
	local damageInfo = sdk.to_managed_object(args[3])
	local caster = damageInfo:get_field("<AttackOwnerHitController>k__BackingField"):get_field("<CachedCharacter>k__BackingField")
	if PlayerAndPawns[caster] then
		-- Regen 20% of damage dealt
		local heal = damageInfo:get_field("Damage") * 0.2
		 regenLossGage(PlayerAndPawns[caster], heal)
	end
end, nil)

-- Halidom
local targets = {}
sdk.hook(sdk.find_type_definition("app.CureSpotShell"):get_method("onShellStart"),
function (args)
	init()
	targets = {}
end, nil)

sdk.hook(sdk.find_type_definition("app.CureSpotShell"):get_method("onAttackHit"),
function (args)
	local target = sdk.to_managed_object(args[3]):get_field("<DamageOwnerHitController>k__BackingField"):get_field("<CachedCharacter>k__BackingField")
	if target ~= nil then
		if not target:call("isHostile(app.Character)", PlayerAndPawns[0]) then
			if not targets[target] then targets[target] = 0 end
			targets[target] = targets[target] + 1
		end
		-- Cure petrification if stay in full duration
		if next(targets) ~= nil then
			for key, value in pairs(targets) do
				if value % 450 == 0 then
					statusCtrl = key:call("get_StatusConditionCtrl()")
					cureInfo = statusCtrl:call("getStatusCondition(app.StatusConditionDef.StatusConditionEnum)", 12)
					statusCtrl:call("reqStatusConditionCure(app.StatusConditionDef.StatusConditionFlag, app.StatusConditionDef.CureInfo)", 4096, cureInfo)
				end
			end
		end
	end
end, nil)

sdk.hook(sdk.find_type_definition("app.GuiManager"):get_method("OnChangeSceneType"),
function() 
end, function()
	CharacterPlayer = nil
end)

loadData()

-- -- Update Targets
-- sdk.hook(sdk.find_type_definition("app.PawnManager"):get_method("hirePawn(app.Character, System.Boolean)"),
-- function (args)
-- end, function (retval)
	-- updatePlayerAndPawns()
	-- return retval
-- end)

-- sdk.hook(sdk.find_type_definition("app.PawnManager"):get_method("dismissPawn(app.Pawn)"),
-- function (args)
-- end, function (retval)
	-- updatePlayerAndPawns()
	-- return retval
-- end)
