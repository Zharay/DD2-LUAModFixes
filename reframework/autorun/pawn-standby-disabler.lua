local sdk = sdk
local re = re

local config = json.load_file('pawn-sd.json.json') or {}

if config.Enabled == nil then
	config.Enabled = true
end

if config.IsForcedWaitEvent == nil then
    config.IsForcedWaitEvent = false
end

local function getPawnManager()
    if PawnManager == nil then PawnManager = sdk.get_managed_singleton('app.AppSingleton`1<app.PawnManager>'):get_Instance() end
    return PawnManager
end

local ChangeOnLoad = false
sdk.hook(
    sdk.find_type_definition('app.GuiManager'):get_method('OnChangeSceneType'),
    nil,
    function(retval)
        if not PawnManager and config.Enabled then
            PawnManager = getPawnManager()
            local configChanged = false
            if PawnManager._IsForcedWaitEvent then
                PawnManager._IsForcedWaitEvent = true
                --[[config.IsForcedWaitEvent = true
                configChanged = true
                ChangeOnLoad = true]]--
            elseif not PawnManager._IsForcedWaitEvent then
                PawnManager._IsForcedWaitEvent = false
                --[[config.IsForcedWaitEvent = false
                configChanged = true
                ChangeOnLoad = true]]--
            end

            --[[if configChanged then
                json.dump_file("pawn-sd.json", config)
            end]]--
        end

        return retval
    end
)

--[[sdk.hook(
    sdk.find_type_definition('app.HumanActionSelector'):get_method('update'),
    function()
        if ChangeOnLoad and config.Enabled and PawnManager then
            ChangeOnLoad = false

            if config.IsForcedWaitEvent then
                PawnManager._IsForcedWaitEvent = true
            else
                PawnManager._IsForcedWaitEvent = false
            end
        end
    end,
    nil
)]]--

sdk.hook(
    sdk.find_type_definition('app.StandbyAreaInfo'):get_method('setup'),
    function()
        if config.Enabled then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    nil
)

sdk.hook(
    sdk.find_type_definition('app.Ch1StandbyArea'):get_method('start'),
    function()
        if config.Enabled then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    nil
)

sdk.hook(
    sdk.find_type_definition('app.Ch1StandbyAreaController'):get_method('start'),
    function()
        if config.Enabled then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    nil
)

sdk.hook(
    sdk.find_type_definition('app.Ch1StandbyAreaController'):get_method('update'),
    function()
        if config.Enabled then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    nil
)

sdk.hook(
    sdk.find_type_definition('app.PawnOrderController'):get_method('updateWaitPosition'),
    function()
        PawnManager = getPawnManager()
        local configChanged = false
        if not PawnManager._IsForcedWaitEvent and config.Enabled then
            PawnManager._IsForcedWaitEvent = true
            --[[config.IsForcedWaitEvent = true
            configChanged = true

            if configChanged then
                json.dump_file("pawn-sd.json", config)
            end]]--
        end
    end,
    nil
)

sdk.hook(
    sdk.find_type_definition('app.PawnOrderController'):get_method('onExitWait'),
    function()
        PawnManager = getPawnManager()
        local configChanged = false
        if PawnManager._IsForcedWaitEvent and config.Enabled then
            PawnManager._IsForcedWaitEvent = false
            --[[config.IsForcedWaitEvent = false
            configChanged = true

            if configChanged then
                json.dump_file("pawn-sd.json", config)
            end]]--
        end
    end,
    nil
)

re.on_draw_ui(function()
    if imgui.tree_node("Pawn Standby Disabler") then
		local configChanged = false
		configChanged, config.Enabled = imgui.checkbox("Enabled", config.Enabled)

        imgui.tree_pop();
        if configChanged then
            json.dump_file("pawn-sd.json", config)
        end
    end
end)