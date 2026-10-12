local modname="[HigherDropRateOrNumber]"

local function Log(message, level)
    level = level or "info"
    local previousLevel = log.get_level and log.get_level() or "error"
    log.set_level(level)
    local ok, err = pcall(log[level], modname..message)
    log.set_level(previousLevel)
    if not ok then error(err, 0) end
end

Log("Start")
local config = json.load_file("HigherDropRateOrNumber.json") or {}
if config.DropNumber==nil then config.DropNumber=1 end

if type(config.DropNumber) ~= "number" or config.DropNumber < 1
    or config.DropNumber > 5 or config.DropNumber ~= math.floor(config.DropNumber) then
    Log("DropNumber must be an integer between 1 and 5; resetting to 1.", "error")
    config.DropNumber = 1
end

Log("DropNumber="..tostring(config.DropNumber).."; disabling zero-quantity options in multi-option lots.", "debug")

local originals = {}
local function ModifyDropData(itemDropDataDict, modifiedLots, name, multiplier)
    local count = itemDropDataDict:call("get_Count()")
    Log(name..": active entries="..count..", allocated entries="..itemDropDataDict._count, "debug")
    if count == 0 then
        Log(name..": empty; nothing to modify.", "debug")
        return
    end
    local entries = itemDropDataDict._entries
    assert(entries ~= nil, "Drop dictionary has no entries array.")
    local records, lots, shared, ratesChanged, numbersChanged, samples = 0, 0, 0, 0, 0, 0

    -- The current SDK uses _currentValue, not _current; avoid struct enumerators.
    for i=0,itemDropDataDict._count-1 do
        local entry = entries[i]
        if entry.next >= -1 and entry.value ~= nil then
            records = records + 1
            local lotlist = entry.value._LotList
            assert(lotlist ~= nil, "ItemDropParam has no _LotList.")
            for j=0,#lotlist-1 do
                local lot = lotlist[j]
                -- Default and specific dictionaries can share the same lot.
                if not modifiedLots[lot] then
                    lots = lots + 1
                    local oldNum, oldRate = lot._Num, lot._Rate
                    local original = originals[lot]
                    if original == nil then
                        original = {num = oldNum, rate = oldRate}
                        originals[lot] = original
                    end
                    local num = original.num * multiplier
                    assert(num >= -2147483648 and num <= 2147483647,
                        "Multiplied drop quantity exceeds System.Int32.")
                    if #lotlist > 1 and original.num == 0 then
                        lot._Rate = 0
                    end
                    lot._Num = num
                    modifiedLots[lot] = true
                    local newNum, newRate = lot._Num, lot._Rate
                    if newRate ~= oldRate then ratesChanged = ratesChanged + 1 end
                    if newNum ~= oldNum then numbersChanged = numbersChanged + 1 end
                    if (newNum ~= oldNum or newRate ~= oldRate) and samples < 10 then
                        samples = samples + 1
                        Log(name..": key="..tostring(entry.key)..", lot="..j
                            ..", _Num="..oldNum.." -> "..newNum
                            ..", _Rate="..oldRate.." -> "..newRate, "debug")
                    end
                else
                    shared = shared + 1
                end
            end
        end
    end
    Log(name..": records="..records..", unique lots="..lots..", shared lots skipped="..shared
        ..", rates changed="..ratesChanged..", quantities changed="..numbersChanged
        .." (up to 10 changed-lot samples above).", "debug")
    if ratesChanged == 0 and numbersChanged == 0 then
        Log(name..": no values changed; entries may already be modified, contain no eligible zero-quantity options, or use DropNumber=1.", "debug")
    end
end

local waitingReason
local function WaitForDropData(reason)
    if waitingReason ~= reason then
        waitingReason = reason
        Log("Not ready: "..reason, "debug")
    end
    return false
end

local function ApplyDropData(multiplier)
    local im = sdk.get_managed_singleton("app.ItemManager")
    if im == nil then
        return WaitForDropData("app.ItemManager is unavailable.")
    end
    if im.EnemyDefaultItemDropDataDict == nil or im.EnemyItemDropDataDict == nil then
        return WaitForDropData("Enemy drop dictionaries are unavailable.")
    end
    if im.EnemyDefaultItemDropDataDict:call("get_Count()") == 0 then
        return WaitForDropData("EnemyDefaultItemDropDataDict is empty.")
    end

    Log("Enemy drop database ready; applying DropNumber="..tostring(multiplier)..".", "debug")
    local modifiedLots = {}
    ModifyDropData(im.EnemyDefaultItemDropDataDict, modifiedLots, "EnemyDefaultItemDropDataDict", multiplier)
    ModifyDropData(im.EnemyItemDropDataDict, modifiedLots, "EnemyItemDropDataDict", multiplier)
    Log("Done")
    return true
end

local function SaveConfig()
    local ok, result = pcall(json.dump_file, "HigherDropRateOrNumber.json", config)
    if not ok or result == false then
        Log("Could not save settings: "..tostring(result), "error")
        return false
    end
    return true
end

local selectedMultiplier = config.DropNumber
local pendingMultiplier = config.DropNumber
local applyRequested = true
local saveAfterApply = false
local status = "Waiting for the enemy drop database."
local function TryApplyDropData()
    if not applyRequested then return end
    local ok, result = pcall(ApplyDropData, pendingMultiplier)
    if not ok then
        applyRequested = false
        status = "Apply failed; see the REFramework log. Click Apply to retry."
        Log("Applying drop changes failed; retries stopped: "..tostring(result), "error")
        return
    end
    if result then
        config.DropNumber = pendingMultiplier
        applyRequested = false
        status = string.format("Applied quantity multiplier: %dx", config.DropNumber)
        if saveAfterApply and not SaveConfig() then
            status = status.." (save failed; see the REFramework log)."
        end
        saveAfterApply = false
    end
end

TryApplyDropData()
if applyRequested then
    Log("Waiting for the enemy drop database.")
end
re.on_application_entry("UpdateBehavior", TryApplyDropData)
re.on_config_save(SaveConfig)

re.on_draw_ui(function()
    if not imgui.tree_node("Higher Drop Rate or Number") then return end
    local changed, value = imgui.slider_int("Drop quantity multiplier", selectedMultiplier, 1, 5)
    if changed then selectedMultiplier = math.max(1, math.min(5, value)) end
    if imgui.button("Apply") then
        pendingMultiplier = selectedMultiplier
        applyRequested = true
        saveAfterApply = true
        waitingReason = nil
        status = "Apply requested; waiting for the enemy drop database."
        Log("Apply requested: DropNumber="..tostring(pendingMultiplier)..".", "debug")
    end
    imgui.text(status)
    imgui.tree_pop()
end)

-- Restore the baseline before reload so the multiplier is not compounded.
re.on_script_reset(function()
    for lot, original in pairs(originals) do
        lot._Num = original.num
        lot._Rate = original.rate
    end
end)
