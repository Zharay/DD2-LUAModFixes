
local re = re
local sdk = sdk
local d2d = d2d
local imgui = imgui
local log = log
local json = json
local draw = draw


log.info("[Carry It For Me] Loaded");

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

local function GetPawn(extraWeight)
    local pawnMgr = GetPawnManager();
    if pawnMgr and ItemManager then
        local list = pawnMgr:call("get_PawnCharacterList()")
        if list then
            local len = list:call("get_Count")
            for i = 0, len - 1, 1 do
                local pawnChar = list:call("get_Item", i)
                if pawnChar then
                    local limit = ItemManager:call("getWeightLimit(app.Character)", pawnChar)
                    local weight = ItemManager:call("getStorageWeight(app.Character)", pawnChar)
                    -- log.info("weight: " .. tostring(weight) .. ", extra: " .. tostring(extraWeight) .. ", limit: " .. tostring(limit))
                    local rank = ItemManager:call("getWeightRank(System.Single, System.Single)", weight + extraWeight, limit)
                    if rank <= 2 then
                        return pawnChar
                    end
                end
            end
        end
    end
end

local function PassItemToPawn(ret)
    if Config.Enabled and ItemManager and itemEventType then
        if (itemEventType & Config.ItemEvent) == 0 then
            -- no enabled event bit matches this pickup, e.g. 8 is Talk
            return ret
        end
        local player = GetPlayer()
        local playerID = player:get_CharaID()
        local stroageData = ItemManager:getStorageData(itemID, playerID)
        if stroageData and stroageData._ItemData then
            local itemData = stroageData._ItemData
            -- log.info("weight: " .. tostring(itemData._Weight * 0.01))

            local isCategoryEnabled = Config.ItemCategory[tostring(itemData._Category)]
            local isSubCategoryEnabled = Config.ItemSubCategory[tostring(itemData:get_ItemParam()._SubCategory)]
            if isCategoryEnabled and isSubCategoryEnabled then
                local pawn = GetPawn(stroageData._ItemData._Weight * 0.01)
                if pawn then
                    -- storage, num, char id to, is new
                    ItemManager:passItem(stroageData, itemNum, pawn:get_CharaID(), true)
                end
            end
        end
    end

    return ret
end

-- sdk.hook(sdk.find_type_definition("app.ItemManager"):get_method("getWeightRank(System.Single, System.Single)"),
-- function (args)
--     log.info("weight: " .. tostring(sdk.to_float(args[3])) .. ", limit: " .. tostring(sdk.to_float(args[4])))
-- end, function (ret)
--     return ret
-- end)

-- as of the current game version, getItem's flags/event type are bundled into an app.ItemDefine.GetItemOption struct arg
sdk.hook(sdk.find_type_definition("app.ItemManager"):get_method("getItem(System.Int32, System.Int32, app.Character, app.ItemDefine.GetItemOption)"),
function (args)
    local player = GetPlayer()
    local chara = sdk.to_managed_object(args[5])
    if chara and player then
        if chara:get_CharaID() == player:get_CharaID() then
            ItemManager = sdk.to_managed_object(args[2])
            itemID = sdk.to_int64(args[3])
            itemNum = sdk.to_int64(args[4])
            local option = sdk.to_valuetype(args[6], "app.ItemDefine.GetItemOption")
            itemEventType = option and option:get_field("EventType")
        end
    else
        ItemManager = nil
        itemID = nil
        itemNum = nil
        itemEventType = nil
    end
end, PassItemToPawn)

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