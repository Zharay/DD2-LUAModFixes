local modname = "[ItemHalfWeight] "
local originals = {}
local pending = true
local waiting = false
local stopped = false

local function apply_weights()
    local manager = sdk.get_managed_singleton("app.ItemManager")
    local items = manager and manager:get_field("_ItemDataDict")
    if items == nil or items:call("get_Count()") == 0 then
        if not waiting then
            log.info(modname .. "Waiting for item data")
            waiting = true
        end
        return
    end

    -- The interface returns a boxed enumerator; the generic accessor path is broken.
    local iter = items:call("System.Collections.IEnumerable.GetEnumerator()")
    if iter == nil then
        error("Item dictionary returned no enumerator")
    end
    local count = 0
    while iter:call("MoveNext()") do
        local item = iter:get_field("_current"):get_field("value")
        if item == nil then
            error("Item dictionary contains a null parameter")
        end
        local address = item:get_address()
        local weight = item:get_field("_Weight")
        local previous = originals[address]
        if previous == nil or weight ~= previous.reduced then
            -- _Weight is System.Int16, so half-units cannot be stored.
            local reduced = math.floor(weight / 2)
            if previous == nil then
                item:add_ref()
            end
            originals[address] = { item = item, weight = weight, reduced = reduced }
            item:set_field("_Weight", reduced)
            count = count + 1
        end
    end
    pending = false
    waiting = false
    log.info(modname .. "Applied 50% item weight to " .. count .. " parameters")
end

local item_manager_type = sdk.find_type_definition("app.ItemManager")
local setup = item_manager_type and item_manager_type:get_method("setupItemData")
if setup == nil then
    stopped = true
    log.error(modname .. "Cannot find app.ItemManager.setupItemData; weights were not changed")
else
    sdk.hook(setup, nil, function(retval)
        pending = true
        return retval
    end)
end

re.on_frame(function()
    if not pending or stopped then
        return
    end
    local ok, err = pcall(apply_weights)
    if not ok then
        stopped = true
        log.error(modname .. "Failed to apply item weights: " .. tostring(err))
    end
end)

re.on_script_reset(function()
    for _, previous in pairs(originals) do
        -- Do not overwrite a subsequent change made by another mod.
        if previous.item:get_field("_Weight") == previous.reduced then
            previous.item:set_field("_Weight", previous.weight)
        end
    end
end)
