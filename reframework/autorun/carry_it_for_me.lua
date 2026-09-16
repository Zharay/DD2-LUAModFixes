
local re = re
local sdk = sdk
local d2d = d2d
local imgui = imgui
local log = log
local json = json
local draw = draw
local debug = false

if debug then
    log.set_level("info")
    log.info("[Carry It For Me] Loaded")
end

local Config = json.load_file('carry_it_for_me.json') or {}
if Config.Enabled == nil then
	Config.Enabled = true
end

if Config.ItemCategory == nil then
    Config.ItemCategory = {
		["0"] = true,
		["1"] = true,
		["2"] = true,
		["3"] = true,
	}
end

if Config.ItemSubCategory == nil then
    Config.ItemSubCategory = {
		["0"] = true,
		["1"] = true,
		["2"] = true,
		["3"] = false,
		["4"] = false,
		["5"] = true,
		["6"] = false,
		["7"] = false,
		["8"] = false,
		["9"] = true,
		["10"] = true,
	}
end

if Config.ItemEvent == nil then
    Config.ItemEvent = 2 | 4 | 8 | 16
end


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

local function GetPlayer()
    local playerMgr = GetPlayerManager();
    if playerMgr then
        return playerMgr:call("get_ManualPlayer()");
    end
end

-- autoEquipItem()

-- called by app.SearchDeadBodyInteractController.executeInteract(System.UInt32, app.Character)

-- id, num, charac, is notice, .....
local ItemManager = nil
local itemID = nil
local itemNum = nil
local itemEventType = nil
local itemSource = nil

local function Log(msg)
    if debug then
        log.info("[Carry It For Me] " .. msg)
    end
end

local function ClearPendingItem()
    ItemManager = nil
    itemID = nil
    itemNum = nil
    itemEventType = nil
    itemSource = nil
end

local function GetPawn(extraWeight)
    local pawnMgr = GetPawnManager();
    if not pawnMgr then
        Log("GetPawn: PawnManager singleton unavailable")
        return
    end
    if not ItemManager then
        Log("GetPawn: ItemManager unavailable")
        return
    end
    local list = pawnMgr:call("get_PawnCharacterList()")
    if not list then
        Log("GetPawn: PawnCharacterList was nil")
        return
    end
    local len = list:call("get_Count")
    Log("GetPawn: evaluating " .. tostring(len) .. " pawn(s) for extra weight " .. tostring(extraWeight))
    for i = 0, len - 1, 1 do
        local pawnChar = list:call("get_Item", i)
        if pawnChar then
            local limit = ItemManager:call("getWeightLimit(app.Character)", pawnChar)
            local weight = ItemManager:call("getStorageWeight(app.Character)", pawnChar)
            local rank = ItemManager:call("getWeightRank(System.Single, System.Single)", weight + extraWeight, limit)
            Log("GetPawn: pawn " .. tostring(i) .. " id=" .. tostring(pawnChar:get_CharaID())
                .. " weight=" .. tostring(weight) .. ", extra=" .. tostring(extraWeight)
                .. ", limit=" .. tostring(limit) .. ", rank=" .. tostring(rank))
            if rank <= 2 then
                return pawnChar
            end
        else
            Log("GetPawn: pawn " .. tostring(i) .. " entry was nil")
        end
    end
    return nil
end

local function TryPassPendingItem()
    Log("TryPassPendingItem called, source=" .. tostring(itemSource) .. ", itemID=" .. tostring(itemID) .. ", itemNum=" .. tostring(itemNum) .. ", itemEventType=" .. tostring(itemEventType))
    if not Config.Enabled then
        Log("skipped: mod is disabled in config")
        return
    end
    if not ItemManager or not itemID then
        Log("skipped: no player pickup captured by the pre-hook")
        return
    end
    if itemEventType == nil then
        -- overloads without a GetItemOption carry no event info, so only the category filters apply
        Log("no event type on this overload; event filter bypassed")
    elseif (itemEventType & Config.ItemEvent) == 0 then
        -- no enabled event bit matches this pickup, e.g. 8 is Talk
        Log("skipped: itemEventType " .. tostring(itemEventType) .. " not in Config.ItemEvent " .. tostring(Config.ItemEvent))
        return
    end
    do
        local player = GetPlayer()
        if not player then
            Log("skipped: player character unavailable")
            return
        end
        local playerID = player:get_CharaID()
        local stroageData = ItemManager:getStorageData(itemID, playerID)
        if stroageData and stroageData._ItemData then
            local itemData = stroageData._ItemData
            Log("weight: " .. tostring(itemData._Weight * 0.01))

            -- Equipment can have no ItemDataParam, and therefore no subcategory.
            local ok, param = pcall(function() return itemData:call("get_ItemParam()") end)
            local subCategory = ok and param and param:get_field("_SubCategory")

            local isCategoryEnabled = Config.ItemCategory[tostring(itemData._Category)]
            local isSubCategoryEnabled = subCategory == nil or Config.ItemSubCategory[tostring(subCategory)] == true
            Log("category=" .. tostring(itemData._Category) .. " (enabled=" .. tostring(isCategoryEnabled) .. "), subCategory=" .. tostring(subCategory) .. " (enabled=" .. tostring(isSubCategoryEnabled) .. ")")
            if isCategoryEnabled and isSubCategoryEnabled then
                local pawn = GetPawn(stroageData._ItemData._Weight * 0.01)
                if pawn then
                    -- storage, num, char id to, is new
                    Log("passing item " .. tostring(itemID) .. " x" .. tostring(itemNum) .. " to pawn " .. tostring(pawn:get_CharaID()))
                    local ok, err = pcall(function()
                        ItemManager:passItem(stroageData, itemNum, pawn:get_CharaID(), true)
                    end)
                    if ok then
                        Log("passItem completed")
                    else
                        Log("passItem FAILED: " .. tostring(err))
                    end
                else
                    Log("no eligible pawn found (all pawns overweight or full)")
                end
            else
                Log("skipped: category/subcategory filtered out by config")
            end
        else
            Log("no storage data found for itemID=" .. tostring(itemID))
        end
    end
end

local function PassItemToPawn(ret)
    local ok, err = pcall(TryPassPendingItem)
    if not ok then
        Log("ERROR while passing item: " .. tostring(err))
    end
    ClearPendingItem()
    return ret
end

-- sdk.hook(sdk.find_type_definition("app.ItemManager"):get_method("getWeightRank(System.Single, System.Single)"),
-- function (args)
--     log.info("weight: " .. tostring(sdk.to_float(args[3])) .. ", limit: " .. tostring(sdk.to_float(args[4])))
-- end, function (ret)
--     return ret
-- end)

local ItemManagerType = sdk.find_type_definition("app.ItemManager")
if not ItemManagerType then
    Log("FATAL: app.ItemManager type not found")
end

local function ReadEventType(optionPtr)
    if optionPtr == nil then return nil end
    local ok, option = pcall(sdk.to_valuetype, optionPtr, "app.ItemDefine.GetItemOption")
    if ok and option then
        return option:get_field("EventType")
    end
    return nil
end

local function ReadItemResult(resultPtr)
    local ok, result = pcall(sdk.to_managed_object, resultPtr)
    if ok and result then
        local okFields, id, num = pcall(function()
            return result:get_field("Id"), result:get_field("Num")
        end)
        if okFields and id then return id, num end
    end
    local okVt, vt = pcall(sdk.to_valuetype, resultPtr, "app.ItemDropLottery.ItemResult")
    if okVt and vt then
        return vt:get_field("Id"), vt:get_field("Num")
    end
    return nil, nil
end

-- captures the pickup only when it belongs to the player, so the post-hook can hand it off
local function CapturePickup(label, itemMgrPtr, id, num, charaPtr, optionPtr)
    local player = GetPlayer()
    local okChara, chara = pcall(sdk.to_managed_object, charaPtr)
    local charaID = okChara and chara and chara:get_CharaID()
    local playerID = player and player:get_CharaID()
    Log(label .. " fired: charaID=" .. tostring(charaID) .. ", playerID=" .. tostring(playerID)
        .. ", itemID=" .. tostring(id) .. ", itemNum=" .. tostring(num))
    if charaID and playerID and charaID == playerID then
        ItemManager = sdk.to_managed_object(itemMgrPtr)
        itemID = id
        itemNum = num
        itemEventType = ReadEventType(optionPtr)
        itemSource = label
        Log("player pickup captured via " .. label .. ": itemID=" .. tostring(itemID)
            .. ", itemNum=" .. tostring(itemNum) .. ", eventType=" .. tostring(itemEventType))
    else
        -- clear so the post-hook never re-passes a previously captured item
        Log("ignored: pickup was not the player's (" .. label .. ")")
        ClearPendingItem()
    end
end

local function RegisterHook(signature, preHook)
    local method = ItemManagerType and ItemManagerType:get_method(signature)
    if not method then
        Log("FATAL: method not found, these pickups can never be detected: " .. signature)
        return
    end
    sdk.hook(method, function (args)
        local ok, err = pcall(preHook, args)
        if not ok then
            Log("ERROR in pre-hook for " .. signature .. ": " .. tostring(err))
            ClearPendingItem()
        end
    end, PassItemToPawn)
    Log("hook registered: " .. signature)
end

-- Chests use the option overload; gathering and enemy drops route through the others.
RegisterHook("getItem(System.Int32, System.Int32, app.Character, app.ItemDefine.GetItemOption)", function (args)
    CapturePickup("getItem(id, num, Character, option)", args[2], sdk.to_int64(args[3]), sdk.to_int64(args[4]), args[5], args[6])
end)

RegisterHook("getItem(System.Int32, System.Int32, app.Character)", function (args)
    CapturePickup("getItem(id, num, Character)", args[2], sdk.to_int64(args[3]), sdk.to_int64(args[4]), args[5], nil)
end)

RegisterHook("getItem(app.ItemDropLottery.ItemResult, app.Character, app.ItemDefine.GetItemOption)", function (args)
    local id, num = ReadItemResult(args[3])
    CapturePickup("getItem(ItemResult, Character, option)", args[2], id, num, args[4], args[5])
end)

RegisterHook("getItem(app.ItemDropLottery.ItemResult, app.Character)", function (args)
    local id, num = ReadItemResult(args[3])
    CapturePickup("getItem(ItemResult, Character)", args[2], id, num, args[4], nil)
end)

-- The CharacterID overloads have no Character to identify the player with, so only log them for now.
for _, signature in ipairs({
    "getItem(System.Int32, System.Int32, app.CharacterID)",
    "getItem(System.Int32, System.Int32, app.CharacterID, app.ItemDefine.GetItemOption)",
}) do
    local method = ItemManagerType and ItemManagerType:get_method(signature)
    if not method then
        Log("probe NOT registered, method missing: " .. signature)
    else
        sdk.hook(method, function (args)
            pcall(function()
                Log("probe fired: " .. signature)
            end)
        end, function (ret) return ret end)
        Log("probe registered: " .. signature)
    end
end

local function toBits(num)
    -- returns a table of bits, least significant first.
    local t={} -- will contain the bits
    local rest
    while num>0 do
        rest=math.fmod(num,2)
        t[#t+1]=rest
        num=(num-rest)/2
    end
    return t
end

re.on_draw_ui(function()
    local configChanged = false
    if imgui.tree_node("Carry It For Me") then
        local changed = false

		changed, Config.Enabled = imgui.checkbox("Enabled", Config.Enabled)
        configChanged = configChanged or changed

        -- Item Category
        -- imgui.text("Config.ItemCategory: " .. json.dump_string(Config.ItemCategory["0"], 2))
        -- imgui.text("Config.ItemCategory: " .. json.dump_string(Config.ItemCategory["1"], 2))
        -- imgui.text("Config.ItemCategory: " .. json.dump_string(Config.ItemCategory["2"], 2))
        -- imgui.text("Config.ItemCategory: " .. json.dump_string(Config.ItemCategory["3"], 2))
		changed, Config.ItemCategory["0"] = imgui.checkbox("ItemCategory - Use", Config.ItemCategory["0"])
        configChanged = configChanged or changed

		changed, Config.ItemCategory["1"] = imgui.checkbox("ItemCategory - Material", Config.ItemCategory["1"])
        configChanged = configChanged or changed

		changed, Config.ItemCategory["2"] = imgui.checkbox("ItemCategory - Other", Config.ItemCategory["2"])
        configChanged = configChanged or changed

		changed, Config.ItemCategory["3"] = imgui.checkbox("ItemCategory - Equip", Config.ItemCategory["3"])
        configChanged = configChanged or changed

        imgui.new_line()
        -- ItemSubCategory
		changed, Config.ItemSubCategory["0"] = imgui.checkbox("ItemSubCategory - Heal", Config.ItemSubCategory["0"])
        configChanged = configChanged or changed

		changed, Config.ItemSubCategory["1"] = imgui.checkbox("ItemSubCategory - Buff", Config.ItemSubCategory["1"])
        configChanged = configChanged or changed

		changed, Config.ItemSubCategory["2"] = imgui.checkbox("ItemSubCategory - Material", Config.ItemSubCategory["2"])
        configChanged = configChanged or changed

		changed, Config.ItemSubCategory["3"] = imgui.checkbox("ItemSubCategory - Special", Config.ItemSubCategory["3"])
        configChanged = configChanged or changed

		changed, Config.ItemSubCategory["4"] = imgui.checkbox("ItemSubCategory - Quest", Config.ItemSubCategory["4"])
        configChanged = configChanged or changed

		changed, Config.ItemSubCategory["5"] = imgui.checkbox("ItemSubCategory - Book", Config.ItemSubCategory["5"])
        configChanged = configChanged or changed

		changed, Config.ItemSubCategory["6"] = imgui.checkbox("ItemSubCategory - Arrow", Config.ItemSubCategory["6"])
        configChanged = configChanged or changed

		changed, Config.ItemSubCategory["7"] = imgui.checkbox("ItemSubCategory - CustomSkill", Config.ItemSubCategory["7"])
        configChanged = configChanged or changed

		changed, Config.ItemSubCategory["8"] = imgui.checkbox("ItemSubCategory - PawnSkill", Config.ItemSubCategory["8"])
        configChanged = configChanged or changed

		changed, Config.ItemSubCategory["9"] = imgui.checkbox("ItemSubCategory - MagicBook", Config.ItemSubCategory["9"])
        configChanged = configChanged or changed

		changed, Config.ItemSubCategory["10"] = imgui.checkbox("ItemSubCategory - Online", Config.ItemSubCategory["10"])
        configChanged = configChanged or changed

        imgui.new_line()
        -- Get Item Event Type
        local enabled = false
		changed, enabled = imgui.checkbox("GetItemEventType - Gather", Config.ItemEvent & 2 ~= 0)
        if changed then
            if enabled then
                Config.ItemEvent = Config.ItemEvent | 2
            else
                Config.ItemEvent = Config.ItemEvent ~ 2
            end
        end
        configChanged = configChanged or changed

		changed, enabled = imgui.checkbox("GetItemEventType - TreasureBox", Config.ItemEvent & 4 ~= 0)
        if changed then
            if enabled then
                Config.ItemEvent = Config.ItemEvent | 4
            else
                Config.ItemEvent = Config.ItemEvent ~ 4
            end
        end
        configChanged = configChanged or changed
		changed, enabled = imgui.checkbox("GetItemEventType - Talk", Config.ItemEvent & 8 ~= 0)
        if changed then
            if enabled then
                Config.ItemEvent = Config.ItemEvent | 8
            else
                Config.ItemEvent = Config.ItemEvent ~ 8
            end
        end
        configChanged = configChanged or changed
		changed, enabled = imgui.checkbox("GetItemEventType - DeadEnemy", Config.ItemEvent & 16 ~= 0)
        if changed then
            if enabled then
                Config.ItemEvent = Config.ItemEvent | 16
            else
                Config.ItemEvent = Config.ItemEvent ~ 16
            end
        end
        configChanged = configChanged or changed

        -- imgui.text("Config.ItemEvent: " .. table.concat(toBits(Config.ItemEvent)))
        -- imgui.text("Config.ItemEvent: " .. tostring(Config.ItemEvent & 2))
        -- imgui.text("Config.ItemEvent: " .. tostring(Config.ItemEvent & 4))
        -- imgui.text("Config.ItemEvent: " .. tostring(Config.ItemEvent & 8))
        -- imgui.text("Config.ItemEvent: " .. tostring(Config.ItemEvent & 16))

        imgui.tree_pop();
    end
    if configChanged then
        json.dump_file("carry_it_for_me.json", Config)
    end
end)

re.on_config_save(function()
	json.dump_file("carry_it_for_me.json", Config)
end)