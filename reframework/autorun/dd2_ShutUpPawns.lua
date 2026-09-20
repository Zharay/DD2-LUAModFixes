-- DragonsDogma2 ShutUpPawns! script by emoose
-- https://www.nexusmods.com/dragonsdogma2/mods/248

local DefaultConfig = {
    KeepMinimapMarkers = true, -- if set to false, will also stop the ! markers from appearing on minimap
    AutoSaveChanges = false, -- if true, blocklist changes will automatically be saved to config without needing to press "Save Config"
    DefaultParams = {
        Action = "Block", -- "Block", "Cooldown", "Probability"
        Cooldown = 5, -- In minutes
        Probability = 50, -- Percentage chance to block the message
        Geofence = "All", -- "All", "Towns", "Wilderness"
    },
    HighFives = {
        AllowAfter = true,
        AllowAfterMinutes = 2,
        AllowBosses = true,
        AllowMainPawn = true,
        AllowAll = true,
    },
    BlockList = {},
}

-- Certain variations of the messages below will also get blocked, not just the text shown next to it
-- Adding to the Presets table will also make the preset show up in the UI
local Presets = {
    Ladders = {
        "This ladder can take us to new heights",
        "Perhaps new discoveries await us above",
        "Ladder looks promising, but we have to drop it down",
    },
    Chests = {
        "Look master, a treasure chest!",
        "I've got a good feeling about this one!",
        "Not all chests contain treasure, you know.",
        "Now there's a worthy prize! If only 'tweren't so far away.",
    },
    Annoyances = {
        "These writings could be of import.",
        "Shall we take a closer look?", -- (follow up of above)
        "Different combinations of materials result in different creations.",
        "Pray, slow your feet! You run too fast",
        "No time to catch your breath. Try to keep up!",
        "They can be most convenient, though they travel only during the day.",
        "Different masters prefer different pawns",
    }
}

--- Code section

-- Pawn messages seem to be kept inside PawnTalkMonologueSegmentData instances
-- which keep different minor variants of the message under _Candidates field (as instances of PawnTalkMonologueMessageData)
-- We'll just scan the candidates for specific message GUIDs, if any matches then we'll block that SegmentData instance

local Config = {}

local Session = {
    Messages = {}, -- details of all messages spoken in the current session, kept seperate to Config.BlockList / MessageLog so it won't be cleared
    BlockedMessages = 0,
    BlockedHighFives = 0,
    ProbabilityBlocked = 0,
    ProbabilityTotal = 0,
    CooldownBlocked = 0,
    UnsavedChanges = false,
    IdTextLog = {}, -- every unique ID seen this session, mapped to the text it resolved to (or nil), for investigating the ID format
    IdTextLogCount = 0
}

local COLOR_DELETE_BUTTON = 0x700000FF
local COLOR_PRESET_BUTTON = 0xA0800000
local UI_ID = 1 -- increment to force blocklist trees to collapse
local MESSAGE_LOG_SIZE = 10

---
--- Helpers
---

local app_BattleManager = sdk.get_managed_singleton("app.BattleManager")
local app_PawnManager = sdk.get_managed_singleton("app.PawnManager")
local app_MessageManager = sdk.get_managed_singleton("app.MessageManager")

local LOG_PREFIX = "[ShutUpPawns] "
local function logDebug(message)
    log.info(LOG_PREFIX .. message)
end
local function logError(message)
    log.error(LOG_PREFIX .. message)
end

local MessageLog = {} -- log of the last few messages, separate to Session.Messages so it'll be kept in the right order

local function addToLog(id, messageText)
    table.insert(MessageLog, 1, {id = id, text = messageText, time = os.clock()})
    if #MessageLog > MESSAGE_LOG_SIZE then
        table.remove(MessageLog)
    end
end

-- returns the raw message text for a guid, or nil if there's none (doesn't log errors or build placeholder text)
local function getRawMessageText(guid)
    if not app_MessageManager then
        app_MessageManager = sdk.get_managed_singleton("app.MessageManager")
    end
    if not app_MessageManager or not guid then
        return nil
    end
    local msg = app_MessageManager:getMessage(guid)
    if not msg or msg == "" then
        return nil
    end
    return msg
end

local function getMessageFromGuid(guid)
    local msg = getRawMessageText(guid)
    if not msg then
        local guid_str = guid.ToString and guid:ToString() or tostring(guid)
        -- lots of candidate slots have no text at all (unused condition/variant combos), so this is just informational
        logDebug("no message text for ID " .. guid_str)
        msg = "(failed to find message text for ID " .. guid_str .. ")"
    end
    return msg
end

local app_PawnUtil_isPlayerInTownArea = sdk.find_type_definition("app.PawnUtil") and sdk.find_type_definition("app.PawnUtil"):get_method("isPlayerInTownArea") or nil
local function playerIsInTown()
    if not app_PawnUtil_isPlayerInTownArea then
        local t = sdk.find_type_definition("app.PawnUtil")
        if t then
            app_PawnUtil_isPlayerInTownArea = t:get_method("isPlayerInTownArea")
        end
    end
    if app_PawnUtil_isPlayerInTownArea then
        return app_PawnUtil_isPlayerInTownArea:call(nil)
    end
    return false
end

local function isMainPawn(character)
    -- this used to call app.PawnUtil::isMainPawn(app.Character), but calling that was unreliable
    -- instead we just implement same thing that func checks
    return character ~= nil and character.CharacterID == 0x88143F7B
end

local function formatTimeDifference(timeDifference)
    local seconds = math.floor(timeDifference)
    if seconds == 1 then
        return "1 second ago"
    elseif seconds >= 60 then
        local minutes = math.floor(seconds / 60)
        if minutes == 1 then
            return "1 minute ago"
        end
        return string.format("%.0f minutes ago", minutes)
    end
    return string.format("%.0f seconds ago", seconds)
end

local function tableCopy(dest, src)
    for k, v in pairs(src) do
        dest[k] = v
    end
end

---
--- Blocklist
---

-- blocklist entries are matched as a case-insensitive substring of the spoken message text,
-- so a single preset entry can cover multiple message variants that share a grouping of words
local function blockListFindEntry(messageText)
    if not messageText or messageText == "" then
        return nil
    end
    local haystack = messageText:lower()
    for _, entry in ipairs(Config.BlockList) do
        if entry.id and entry.id ~= "" and haystack:find(entry.id:lower(), 1, true) then
            return entry
        end
    end
    return nil
end

local function blockListAdd(messageId)
    if not messageId or messageId == "" then
        return false
    end
    for _, entry in ipairs(Config.BlockList) do
        if entry.id:lower() == messageId:lower() then
            return false
        end
    end
    local messageInfo = {id = messageId, action = "Default"}
    table.insert(Config.BlockList, messageInfo)
    return true
end

local function blockListAddList(list)
    local has_changed = false
    for _, v in ipairs(list) do
        if blockListAdd(v) then
            has_changed = true
        end
    end
    return has_changed
end

local function blockListContains(messageText)
    return blockListFindEntry(messageText) ~= nil
end

local function blockListRemove(messageText)
    local match = blockListFindEntry(messageText)
    if not match then
        return false
    end
    for i, entry in ipairs(Config.BlockList) do
        if entry == match then
            table.remove(Config.BlockList, i)
            return true
        end
    end
    return false
end

local block_action_handlers = {
    Block = function(message_id, block_params) return true end,
    
    Cooldown = function(message_id, block_params)
        logDebug("Cooldown called for " .. message_id)
        
        local prev_time = Session.Messages[message_id] and Session.Messages[message_id].last_spoken or 0
        local cooldown_duration = (block_params.Cooldown or 0) * 60
        local time_delta = os.clock() - prev_time
        
        logDebug("  prev_time = " .. prev_time)
        logDebug("  cooldown_duration = " .. cooldown_duration)
        logDebug("  time_delta = " .. time_delta)
        
        local is_blocked = prev_time > 0 and cooldown_duration > time_delta
        logDebug("  is_blocked = " .. tostring(is_blocked))
        
        if is_blocked then
            Session.CooldownBlocked = Session.CooldownBlocked + 1
        end

        return is_blocked
    end,
    
    Probability = function(message_id, block_params)
        logDebug("Probability called for " .. message_id)
        
        local random_num = math.random()
        local probability = block_params.Probability or 0
        logDebug("  random_num = " .. random_num)
        logDebug("  probability/100 = " .. probability/100)

        if not Session.Messages[message_id] then
            Session.Messages[message_id] = {}
        end
        
        local details = Session.Messages[message_id]
        details.last_roll = math.floor(random_num * 100)
        details.last_roll_success = (random_num > probability / 100)
        logDebug("  last_roll_success = " .. tostring(details.last_roll_success))
        
        Session.ProbabilityTotal = Session.ProbabilityTotal + 1
        if not details.last_roll_success then
            Session.ProbabilityBlocked = Session.ProbabilityBlocked + 1
        end
        
        return not details.last_roll_success
    end
}

local function blockListCheckActionBlocked(message_id)
    local list_entry = nil
    for _, v in ipairs(Config.BlockList) do
        if v.id == message_id then
            list_entry = v
            break
        end
    end
    
    if not list_entry then
        return false
    end
    
    -- message ID is on blocklist, check parameters
    
    local block_params = {}
    tableCopy(block_params, Config.DefaultParams)
    if list_entry.Action and list_entry.Action ~= "Default" then
        tableCopy(block_params, list_entry)
    end
    
    if list_entry.Geofence then
        block_params.Geofence = list_entry.Geofence
    end
    
    if block_params.Geofence == "Default" then
        block_params.Geofence = Config.DefaultParams.Geofence
    end
    
    if block_params.Geofence and block_params.Geofence ~= "All" then
        local in_town = playerIsInTown()
        if block_params.Geofence == "Towns" and not in_town then
            logDebug("block skipped, not inside Towns geofence for " .. message_id)
            return false
        elseif block_params.Geofence == "Wilderness" and in_town then
            logDebug("block skipped, not inside Wilderness geofence for " .. message_id)
            return false
        end
    end
    
    logDebug("checking " .. block_params.Action .. " handler for " .. message_id)
    local handler = block_action_handlers[block_params.Action]
    return handler and handler(message_id, block_params) or false
end

local function blockListDrawEntry(entry, entryIndex)
    local is_drawing_defaults = entry == nil -- default params panel is also drawn with this func
    if is_drawing_defaults then
        entry = Config.DefaultParams
    end
    
    local ui_id = "DefaultAction"
    local ui_text = "Default blocklist action"
    local ui_entry = {
        Action = entry.Action or "Default",
        Cooldown = entry.Cooldown or Config.DefaultParams.Cooldown,
        Probability = entry.Probability or Config.DefaultParams.Probability,
        Geofence = entry.Geofence or "Default"
    }
    
    if not is_drawing_defaults then
        ui_id = entry.id .. UI_ID
        ui_text = entry.id
        
        if ui_entry.Action ~= "Default" then
            ui_text = ui_entry.Action .. ": " .. ui_text
        end
    end
    
    ui_text = string.gsub(ui_text .. "###" .. ui_id, "\n", " ")

    imgui.push_item_width(300)
    if imgui.tree_node(ui_text) then
        local changed = nil
        
        if not is_drawing_defaults then
            imgui.push_style_color(21, COLOR_DELETE_BUTTON)
            if imgui.button("X") then
                table.remove(Config.BlockList, entryIndex)
                Session.UnsavedChanges = true
            end
            imgui.pop_style_color(1)
            imgui.same_line()
        end
        
        imgui.text("Action: ")
        
        local block_actions = {
          "Default (" .. Config.DefaultParams.Action .. ")",
          "Block",
          "Cooldown",
          "Probability"
        }
        
        local geofences = {
          "Default (" .. Config.DefaultParams.Geofence .. ")",
          "All",
          "Towns",
          "Wilderness"
        }
        
        if is_drawing_defaults then
            table.remove(block_actions, 1)
            table.remove(geofences, 1)
        end
        
        local action_index = 1
        if ui_entry.Action ~= "Default" then
            for i, action in ipairs(block_actions) do
                if action == ui_entry.Action then
                    action_index = i
                    break
                end
            end
        end
        
        imgui.same_line()
        changed, action_index = imgui.combo("###" .. ui_id .. "action", action_index, block_actions)
        if changed then
            local new_action = block_actions[action_index]
            if not is_drawing_defaults and action_index == 1 then
                new_action = "Default"
            end
            
            Session.UnsavedChanges = entry.Action ~= new_action
            entry.Action = new_action
        end
        
        if ui_entry.Action == "Cooldown" then
            imgui.text("Cooldown time (minutes): ")
            imgui.same_line()
            
            changed, ui_entry.Cooldown = imgui.slider_int("###" .. ui_id .. "cooldown", ui_entry.Cooldown, 1, 120)
            if changed then
                Session.UnsavedChanges = entry.Cooldown ~= ui_entry.Cooldown
                entry.Cooldown = ui_entry.Cooldown
            end
        end
        
        if ui_entry.Action == "Probability" then
            imgui.text("Block chance (%): ")
            imgui.same_line()
            
            changed, ui_entry.Probability = imgui.slider_int("###" .. ui_id .. "probability", ui_entry.Probability, 0, 100)
            if changed then
                Session.UnsavedChanges = entry.Probability ~= ui_entry.Probability
                entry.Probability = ui_entry.Probability
            end
        end
        
        local geofence_index = 1
        if ui_entry.Geofence ~= "Default" then
            for i, geofence in ipairs(geofences) do
                if geofence == ui_entry.Geofence then
                    geofence_index = i
                    break
                end
            end
        end
        
        imgui.text("Block inside: ")
        imgui.same_line()
        changed, geofence_index = imgui.combo("###" .. ui_id .. "geofence", geofence_index, geofences)
        if changed then
            local new_geofence = geofences[geofence_index]
            if not is_drawing_defaults and geofence_index == 1 then
                new_geofence = "Default"
            end
            
            Session.UnsavedChanges = entry.Geofence ~= new_geofence
            entry.Geofence = new_geofence
        end
        
        if not is_drawing_defaults then
            -- draw stats for the message (last spoken/last blocked/etc)
            local msg_info = Session.Messages[entry.id]

            if msg_info then
                local function formatTimeString(last_time)
                    return last_time and last_time > 0 and formatTimeDifference(os.clock() - last_time) or "Never"
                end
                
                if msg_info.last_spoken then
                    imgui.text("Last spoken: " .. formatTimeString(msg_info.last_spoken))
                end
                
                if msg_info.last_blocked then
                    imgui.text("Last blocked: " .. formatTimeString(msg_info.last_blocked))
                end
                
                if msg_info.last_roll then
                    local success = msg_info.last_roll_success and " (success, unblocked)" or " (failure, blocked)"
                    imgui.text("Last roll: " .. msg_info.last_roll .. success)
                end
                imgui.separator()
            end
        end
        
        imgui.tree_pop()
    end
    imgui.pop_item_width()
end

---
--- Config
---

local function config_reset(seedBlockList)
    Config = {}
    tableCopy(Config, DefaultConfig)
    
    Config.DefaultParams = {}
    tableCopy(Config.DefaultParams, DefaultConfig.DefaultParams)
    
    Config.BlockList = {}
    if seedBlockList then
        blockListAddList(Presets.Ladders)
    end
end

local function config_load()
    UI_ID = UI_ID + 1 -- collapse blocklist entries
    local config = json.load_file("dd2_ShutUpPawns.json")
    config_reset(config == nil)
    config = config or {}
    
    for k, v in pairs(config) do
        if k ~= "BlockList" and k ~= "BlockListActions" and k ~= "DefaultParams" then
            Config[k] = v
        end
    end
    
    if config.DefaultParams then
        tableCopy(Config.DefaultParams, config.DefaultParams)
    end
    
    -- Our config json contains two lists, BlockList and BlockListActions
    -- ideally these should just be a single list, but older versions of script had BlockList as a flat array
    -- don't really want to break anyones existing config, so the newer actions are stored in a separate BlockListActions list instead
    
    if config.BlockList then
        Config.BlockList = {}
        for _, v in ipairs(config.BlockList) do
            blockListAdd(v)
        end
    end
    
    if config.BlockListActions then
        for k, v in pairs(config.BlockListActions) do
            local action = v.Action or "Default"
            
            for _, entry in ipairs(Config.BlockList) do
                if entry.id == k then
                    entry.Action = action
                    entry.Cooldown = v.Cooldown
                    entry.Probability = v.Probability
                    entry.Geofence = v.Geofence
                    break
                end
            end
        end
    end
    
    if Config.DefaultParams.Action ~= "Block" and Config.DefaultParams.Action ~= "Cooldown" and Config.DefaultParams.Action ~= "Probability" then
        Config.DefaultParams.Action = "Block"
    end
    if Config.DefaultParams.Geofence ~= "All" and Config.DefaultParams.Geofence ~= "Towns" and Config.DefaultParams.Geofence ~= "Wilderness" then
        Config.DefaultParams.Geofence = "All"
    end
end

local function config_save()
    local saved_config = {}
    
    for k, v in pairs(Config) do
        if k ~= "BlockList" then
            saved_config[k] = v
        end
    end
    
    -- massage our Config.BlockList data to remain compatible with previous versions...
    
    saved_config.BlockList = {}
    saved_config.BlockListActions = {}
    
    if Config.BlockList then
        for _, v in ipairs(Config.BlockList) do
            table.insert(saved_config.BlockList, v.id)
            
            local action = v.Action ~= "Default" and v.Action or nil
            saved_config.BlockListActions[v.id] = {
                Action = action,
                Cooldown = v.Cooldown,
                Probability = v.Probability,
                Geofence = v.Geofence
            }
            
            if next(saved_config.BlockListActions[v.id]) == nil then
                saved_config.BlockListActions[v.id] = nil
            end
        end
    end
    
    -- delete BlockListActions section if it's empty
    if next(saved_config.BlockListActions) == nil then
        saved_config.BlockListActions = nil
    end
    
    json.dump_file("dd2_ShutUpPawns.json", saved_config)
end

config_load()

---
--- Game hooks
---

local BattleStartTime = os.clock()
local BattleDuration = 0

local EnemyDangerousRank = 0
local IsBossEnemyType = false
local IsRegisterBossBGMandBossGauge = true

sdk.hook(
    sdk.find_type_definition("app.MainFlowManager"):get_method("onBattleStart"),
    function(args)
        BattleStartTime = os.clock()
        IsBossEnemyType = app_PawnManager.TalkController._CombatInfo:isBossEnemyType() -- not always correct? maybe is set sometime after battle start
        EnemyDangerousRank = app_BattleManager["<EnemyDangerousRank>k__BackingField"]
        
        return sdk.PreHookResult.CALL_ORIGINAL
    end,
    function(retval)
        return retval
    end
)

sdk.hook(
    sdk.find_type_definition("app.EnemyController"):get_method("update"),
    function(args)
        return sdk.PreHookResult.CALL_ORIGINAL
    end,
    function(retval)
        -- app.EnemyController::update seems to set IsRegisterBossBGMandBossGauge
        -- but sadly IsRegisterBossBGMandBossGauge seems to get unset before requestHighFiveAll is ran
        -- so this func will only allow switching isBoss = true, while requestHighFiveAll has to reset it to false
        if not IsRegisterBossBGMandBossGauge then
            IsRegisterBossBGMandBossGauge = app_BattleManager["<IsRegisterBossBGMandBossGauge>k__BackingField"]
        end
        return retval
    end
)

local isHighFiveBlocked = false

sdk.hook(
    sdk.find_type_definition("app.PawnHighFiveActionController"):get_method("checkStart"),
    function(args)
        -- if our requestHighFiveAll code hasn't blocked it then carry on
        if not isHighFiveBlocked then
            return sdk.PreHookResult.CALL_ORIGINAL
        end
        
        -- if AllowMainPawn isn't set the checks below are pointless
        if not Config.HighFives.AllowMainPawn then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
        
        local controller = sdk.to_managed_object(args[2])
        
        local targetChara = nil
        if controller.Target ~= nil then
            targetChara = controller.Target:get_Chara()
        end
        local humanChara = nil
        if controller.Human ~= nil then
            humanChara = controller.Human:get_Chara()
        end
        
        local allowed = isMainPawn(targetChara) or isMainPawn(humanChara)
        if not allowed then
            logDebug("highFiveController = " .. tostring(controller:get_address()))
            
            -- try checking if PawnManager._MainPawn.HighFiveController == this instance
            if app_PawnManager ~= nil and app_PawnManager._MainPawn ~= nil then
                local mainHighFiveController = app_PawnManager._MainPawn["<HighFiveController>k__BackingField"]
                logDebug("mainHighFiveController = " .. tostring(mainHighFiveController:get_address()))
                if controller:get_address() == mainHighFiveController:get_address() then
                    allowed = true
                end
            end
        end
        
        if allowed then
            logDebug("PawnHighFiveActionController: allowed high-five for main pawn")
        else
            logDebug("PawnHighFiveActionController: disallowed high-five for non-main-pawn")
        end
        
        -- if this is main pawn then we're good, commence high fiving
        if allowed then
            return sdk.PreHookResult.CALL_ORIGINAL
        end
        
        -- not the main pawn, lets get outta here scoob
        return sdk.PreHookResult.SKIP_ORIGINAL
    end,
    function(retval)
        return retval
    end
)

sdk.hook(
    sdk.find_type_definition("app.PawnHighFiveController"):get_method("requestHighFive"),
    function(args)
        -- if our requestHighFiveAll code hasn't blocked it then carry on
        if not isHighFiveBlocked then
            return sdk.PreHookResult.CALL_ORIGINAL
        end
        
        -- if AllowMainPawn isn't set the checks below are pointless
        if not Config.HighFives.AllowMainPawn then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
        
        -- check if this is the main pawn:
        local owner = sdk.to_managed_object(args[3])
        local target = sdk.to_managed_object(args[4])
        
        logDebug("PawnHighFiveController: isMainPawn(owner) = " .. tostring(isMainPawn(owner)))
        logDebug("PawnHighFiveController: isMainPawn(target) = " .. tostring(isMainPawn(target)))
        
        local allowed = isMainPawn(owner) or isMainPawn(target)
        
        if allowed then
            logDebug("PawnHighFiveController: allowed high-five for main pawn")
            return sdk.PreHookResult.CALL_ORIGINAL
        end
        
        logDebug("PawnHighFiveController: disallowed high-five for non-main-pawn")
        return sdk.PreHookResult.SKIP_ORIGINAL
    end,
    function(retval)
        return retval
    end
)

sdk.hook(
    sdk.find_type_definition("app.PawnHighFiveController"):get_method("requestHighFiveAll"),
    function(args)
        local reasons = sdk.to_int64(args[3]) & 0xFF
        
        local function IsHighFiveBlocked(reason)
            BattleDuration = (os.clock() - BattleStartTime) / 60
            
            local EnemyDangerousRank_cur = app_BattleManager["<EnemyDangerousRank>k__BackingField"]
            local IsBossEnemyType_cur = app_PawnManager.TalkController._CombatInfo:isBossEnemyType()
            local IsRegisterBossBGMandBossGauge_cur = app_BattleManager["<IsRegisterBossBGMandBossGauge>k__BackingField"]
            
            local EnemyDangerousRank_last = EnemyDangerousRank
            local IsBossEnemyType_last = IsBossEnemyType
            local IsRegisterBossBGMandBossGauge_last = IsRegisterBossBGMandBossGauge
            
            -- reset for next battle
            EnemyDangerousRank = 0
            IsBossEnemyType = false
            IsRegisterBossBGMandBossGauge = false
            
            if Config.HighFives.AllowAll then
                return false
            end
            
            if Config.HighFives.AllowAfter and BattleDuration >= Config.HighFives.AllowAfterMinutes then
                return false
            end
            
            if Config.HighFives.AllowBosses then
                if reason == 3 then -- SpecialBattleFinish
                    logDebug("Not blocked, reason == 3")
                    return false
                end
                
                if EnemyDangerousRank_cur >= 4 or EnemyDangerousRank_last >= 4 then -- app.BattleManager.EnemyDangerousRank.Hard
                    logDebug("Not blocked, EnemyDangerousRank >= 4")
                    return false
                end
                
                if IsRegisterBossBGMandBossGauge_cur or IsRegisterBossBGMandBossGauge_last or
                    IsBossEnemyType_cur or IsBossEnemyType_last
                then
                    logDebug("Not blocked, IsRegisterBossBGMandBossGauge or IsBossEnemyType")
                    return false
                end
            end
            
            logDebug("High-five blocked!")
            
            return true
        end

        isHighFiveBlocked = IsHighFiveBlocked(reasons)
        
        if isHighFiveBlocked then
            Session.BlockedHighFives = Session.BlockedHighFives + 1
        end
        
        -- call orig func, the requestHighFive / checkStart hooks above will handle blocking it (or unblocking it for main-pawn)
        return sdk.PreHookResult.CALL_ORIGINAL
    end,
    function(retval)
        return retval
    end
)

sdk.hook(
    sdk.find_type_definition("app.PLPartyTalkController.TalkEntity"):get_method("play"),
    function(args)
        local entity = sdk.is_managed_object(args[2]) and sdk.to_managed_object(args[2])
        if not entity then
            return sdk.PreHookResult.CALL_ORIGINAL
        end
        
        local segment = entity:get_CurrentSegment()
        if not segment then
            return sdk.PreHookResult.CALL_ORIGINAL
        end
        
        local candidateIndex = sdk.to_int64(args[5]) & 0xFF
        local candidate = segment._Candidates[candidateIndex]
        
        logDebug("TalkEntity::play, index = " .. candidateIndex)
        
        local bannedId = nil
        local loggedId = nil
        local loggedMessage = nil
        
        if candidate ~= nil and candidate._MsgId ~= nil then
            local text = getMessageFromGuid(candidate._MsgId)
            if text ~= nil and text ~= "" then
                loggedId = text
                loggedMessage = text
            end
        end
        
        for i = 0, #segment._Candidates - 1 do
            local cur_candidate = segment._Candidates[i]
            if cur_candidate ~= nil and cur_candidate._MsgId ~= nil then
                local msgid = cur_candidate._MsgId:ToString()
                local candidateText = getMessageFromGuid(cur_candidate._MsgId)
                logDebug("_Candidates[" .. i .. "].Guid = " .. msgid .. ", text = " .. tostring(candidateText))
                
                if Session.IdTextLog[msgid] == nil then
                    Session.IdTextLog[msgid] = candidateText or ""
                    Session.IdTextLogCount = Session.IdTextLogCount + 1
                end
                
                if not loggedId and candidateText ~= nil and candidateText ~= "" then
                    loggedId = candidateText
                end
                
                if not loggedMessage and candidateText ~= nil and candidateText ~= "" then
                    loggedMessage = candidateText
                    loggedId = candidateText
                end
                
                if bannedId == nil and candidateText ~= nil and candidateText ~= "" then
                    local matchedEntry = blockListFindEntry(candidateText)
                    if matchedEntry then
                        bannedId = matchedEntry.id
                    end
                end
            end
        end
        
        -- if we failed to convert any messageid to a usable string then just use the guid itself
        if not loggedMessage then
            loggedMessage = loggedId
        end
        
        local cur_time = os.clock()
        
        if loggedId then
            if Session.Messages[loggedId] == nil then
                Session.Messages[loggedId] = {}
            end
            Session.Messages[loggedId].last_attempt = cur_time
        end
        
        local isBlocked = false
        if bannedId then
            -- bannedId might be different than the actual ID being played, since we look for any banned IDs in the same CategoryData
            -- make sure to also log last_attempt/last_spoken for bannedId
            if Session.Messages[bannedId] == nil then
                Session.Messages[bannedId] = {}
            end
            Session.Messages[bannedId].last_attempt = cur_time
            
            isBlocked = blockListCheckActionBlocked(bannedId)
            
            if not isBlocked then
                Session.Messages[bannedId].last_spoken = cur_time
            else
                Session.Messages[bannedId].last_blocked = cur_time
            end
        end
        
        if loggedMessage then
            if isBlocked then
                loggedMessage = "(blocked) " .. loggedMessage
            end
            addToLog(loggedId, loggedMessage)
        end
        
        if not isBlocked then
            if loggedId then
                Session.Messages[loggedId].last_spoken = cur_time
            end
        else
            logDebug("  Message " .. bannedId .. " is blocked")
            Session.BlockedMessages = Session.BlockedMessages + 1
            
            if not Config.KeepMinimapMarkers then
                entity:set_CurrentSegment(nil) -- null out CurrentSegment to fix crash inside TalkEntity::setLookAt
                return sdk.PreHookResult.SKIP_ORIGINAL -- prevent minimap marker by skipping the play function
            end
            
            -- For minimap marker to display we need original func to get called
            -- To stop message playing we can just set all message candidates MsgIds to nil
            for i = 0, #segment._Candidates - 1 do
                if segment._Candidates[i] ~= nil then
                    segment._Candidates[i]._MsgId = nil
                end
            end
        end
        
        return sdk.PreHookResult.CALL_ORIGINAL
    end,
    function(retval) return retval end
)

---
--- imgui
---

re.on_draw_ui(function()
    local node_text = "ShutUpPawns!"
    if Session.UnsavedChanges then
        node_text = node_text .. " (unsaved changes)"
    end
    node_text = node_text .. "###shutuppawns" -- id for imgui
    
    if imgui.tree_node(node_text) then
        local changed = nil
        
        if imgui.button("Save Config") then
            config_save()
            Session.UnsavedChanges = false
        end

        imgui.same_line()

        if imgui.button("Reload Config") then
            config_load()
            Session.UnsavedChanges = false
        end
        
        imgui.same_line()
        
        if imgui.button("Reset Config") then
            config_reset()
            Session.UnsavedChanges = true
        end
        
        imgui.separator()
        
        changed, Config.KeepMinimapMarkers = imgui.checkbox("Keep minimap markers from blocked messages", Config.KeepMinimapMarkers)
        if changed then
            Session.UnsavedChanges = true
        end
        
        changed, Config.AutoSaveChanges = imgui.checkbox("Automatically save changes", Config.AutoSaveChanges)
        if changed then
            Session.UnsavedChanges = true
        end
        
        if imgui.tree_node("Highfive settings") then
            changed, Config.HighFives.AllowAll = imgui.checkbox("Allow all", Config.HighFives.AllowAll)
            if changed then
                Session.UnsavedChanges = true
            end
            changed, Config.HighFives.AllowAfter = imgui.checkbox("Allow after battle has lasted:", Config.HighFives.AllowAfter)
            if changed then
                Session.UnsavedChanges = true
            end
            changed, Config.HighFives.AllowAfterMinutes = imgui.slider_int("Minutes", Config.HighFives.AllowAfterMinutes, 1, 30)
            if changed then
                Session.UnsavedChanges = true
            end
            changed, Config.HighFives.AllowBosses = imgui.checkbox("Allow after bosses", Config.HighFives.AllowBosses)
            if changed then
                Session.UnsavedChanges = true
            end
            changed, Config.HighFives.AllowMainPawn = imgui.checkbox("Always allow main pawn", Config.HighFives.AllowMainPawn)
            if changed then
                Session.UnsavedChanges = true
            end
            
            imgui.tree_pop()
        end
        
        imgui.separator()
        blockListDrawEntry(nil, 0)
        imgui.separator()
        
        imgui.text("Add preset: ")
        
        imgui.push_style_color(21, COLOR_PRESET_BUTTON)
        for k, v in pairs(Presets) do
            imgui.same_line()
            if imgui.button(k) then
                if blockListAddList(v) then
                    Session.UnsavedChanges = true
                end
            end
        end
        imgui.pop_style_color(1)
        
        if imgui.tree_node("Blocklist (" .. #Config.BlockList .. " items)###supBlocklist") then
            imgui.text("(some variants of blocked lines will also be blocked)")
            imgui.separator()
            if #Config.BlockList == 0 then
                imgui.text("    Empty!")
            else
                imgui.push_style_color(21, COLOR_DELETE_BUTTON)
                if imgui.button("Clear Blocklist") then
                    Config.BlockList = {}
                    Session.UnsavedChanges = true
                end
                imgui.pop_style_color(1)
                imgui.separator()
                for i, entry in ipairs(Config.BlockList) do
                    blockListDrawEntry(entry, i)
                end
            end
            imgui.tree_pop()
        end
        
        if imgui.tree_node("Message history###supMessageHistory") then
            imgui.separator()
            if #MessageLog == 0 then
                imgui.text("    Empty!")
            else
                imgui.push_style_color(21, COLOR_DELETE_BUTTON)
                if imgui.button("Clear History") then
                    MessageLog = {}
                end
                imgui.pop_style_color(1)
                local currentTime = os.clock()
                for i, message in ipairs(MessageLog) do
                    
                    if message.id ~= nil then
                        if blockListContains(message.id) then
                            imgui.push_style_color(21, COLOR_DELETE_BUTTON)
                            if imgui.button("Unblock##" .. tostring(i)) then
                                if blockListRemove(message.id) then
                                    Session.UnsavedChanges = true
                                end
                            end
                            imgui.pop_style_color(1)
                        else
                            if imgui.button("Block##" .. tostring(i)) then
                                if blockListAdd(message.id) then
                                    Session.UnsavedChanges = true
                                end
                            end
                        end
                    end
                    
                    imgui.same_line()
                    imgui.text(formatTimeDifference(currentTime - message.time) .. ": " .. message.text)
                end
            end
            imgui.tree_pop()
        end
        
        if imgui.tree_node("ID/Text log (" .. Session.IdTextLogCount .. " unique IDs seen)###supIdTextLog") then
            imgui.text("Every unique message ID seen this session, with the text it resolved to.")
            imgui.text("Use this to compare ID formats across messages (for investigating ID generation changes).")
            if imgui.button("Dump to dd2_ShutUpPawns_idlog.json") then
                json.dump_file("dd2_ShutUpPawns_idlog.json", Session.IdTextLog)
            end
            imgui.tree_pop()
        end
        
        imgui.separator()
        imgui.text("Session stats:")
        imgui.text("    " .. Session.BlockedMessages .. " lines blocked")
        imgui.text("    " .. Session.CooldownBlocked .. " lines blocked via cooldown")
        if Session.ProbabilityTotal > 0 then
            imgui.text(string.format("    %d/%d lines blocked via dice roll (%.2f%%)", Session.ProbabilityBlocked, Session.ProbabilityTotal, (Session.ProbabilityBlocked / Session.ProbabilityTotal) * 100))
        end
        imgui.text("    " .. Session.BlockedHighFives .. " potential highfives blocked")
        imgui.text("    Last battle duration: " .. BattleDuration)
        
        imgui.tree_pop()
    end
    
    if Config.AutoSaveChanges and Session.UnsavedChanges then
        config_save()
        Session.UnsavedChanges = false
    end
end)
