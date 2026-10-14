local sdk = sdk
local re = re

local CONFIG_FILE = 'pawn-sd.json'

local config = json.load_file(CONFIG_FILE) or {}

if config.Enabled == nil then
    config.Enabled = true
end

-- app.PawnOrderController.PawnOrder.Wait
local ORDER_WAIT = 4

-- Frames after a (re)load during which a leftover standby state is released.
local RELEASE_WINDOW_FRAMES = 600

local requestRelease = false
local didForceWait = false
local lastController = nil
local controllerFrames = 0

-- app.PawnManager is registered as a managed singleton under its own name,
-- not under 'app.AppSingleton`1<app.PawnManager>'.
local function getPawnManager()
    return sdk.get_managed_singleton('app.PawnManager')
end

local function hook(typeName, methodName, pre, post)
    local typeDef = sdk.find_type_definition(typeName)
    local method = typeDef and typeDef:get_method(methodName)
    if method == nil then
        log.error('[Pawn Standby Disabler] Could not find ' .. typeName .. '.' .. methodName)
        return
    end
    sdk.hook(method, pre, post)
end

local function skipIfEnabled()
    if config.Enabled then
        return sdk.PreHookResult.SKIP_ORIGINAL
    end
end

-- Releases the party from standby (same routine the game uses when resting at an inn).
local function releaseStandby(pawnManager)
    if pawnManager ~= nil and pawnManager:get_field('_IsStandby') then
        pawnManager:call('insuranceComebackPartyPawn')
    end
end

-- Ch1StandbyArea.start -> StandbyAreaInfo.setup + caches the controller.
-- Skipping it means the standby areas never detect the player.
-- Ch1StandbyArea.update null-checks the cached controller, so this is safe.
hook('app.Ch1StandbyArea', 'start', skipIfEnabled, nil)
hook('app.StandbyAreaInfo', 'setup', skipIfEnabled, nil)

-- Ch1StandbyAreaController.start and .update must keep running:
--  * start assigns PawnManager.StandbyAreaController, which
--    PLPartyTalkController.start dereferences unconditionally (crash if null).
--  * update is what calls PawnManager.comebackPartyPawn to bring a standing-by
--    party back. Skipping it leaves pawns frozen once PawnManager._IsStandby is
--    set (e.g. restored from a save), since registPawn then puts every pawn
--    straight back into standby.
-- Instead, clear the area triggers so update can only ever bring pawns back.
hook('app.Ch1StandbyAreaController', 'update', function(args)
    if not config.Enabled then
        return
    end

    local controller = sdk.to_managed_object(args[2])
    if controller == nil then
        return
    end

    controller:set_field('_IsHitPlayer', false)
    controller:set_field('_StandbyType', 0)

    if controller ~= lastController then
        lastController = controller
        controllerFrames = 0
    end

    local pawnManager = getPawnManager()
    if pawnManager == nil then
        return
    end

    -- A standby state with no active area (left over from a save or from
    -- before the mod was enabled) would never be released by update itself.
    if controllerFrames < RELEASE_WINDOW_FRAMES then
        controllerFrames = controllerFrames + 1
        if not controller:get_field('_IsNeedStandby') and pawnManager:get_field('_IsStandby') then
            releaseStandby(pawnManager)
            controllerFrames = RELEASE_WINDOW_FRAMES
        end
    end

    if requestRelease then
        requestRelease = false
        releaseStandby(pawnManager)
    end
end, nil)

-- updateWaitPosition is also called by Ferrystone loading/teleport and the AI
-- meta controller, so only force the wait event for an actual Wait order.
hook('app.PawnOrderController', 'updateWaitPosition', function(args)
    if not config.Enabled then
        return
    end

    local orderController = sdk.to_managed_object(args[2])
    if orderController == nil or orderController:call('get_NextOrder') ~= ORDER_WAIT then
        return
    end

    local pawnManager = getPawnManager()
    if pawnManager ~= nil and not pawnManager:get_field('_IsForcedWaitEvent') then
        pawnManager:set_field('_IsForcedWaitEvent', true)
        didForceWait = true
    end
end, nil)

-- Only undo a forced wait this script set, never one started by the game
-- (quests / StandbyAreaRDL use the same flag).
hook('app.PawnOrderController', 'onExitWait', function()
    if not didForceWait then
        return
    end
    didForceWait = false

    local pawnManager = getPawnManager()
    if pawnManager ~= nil then
        pawnManager:set_field('_IsForcedWaitEvent', false)
    end
end, nil)

re.on_draw_ui(function()
    if imgui.tree_node("Pawn Standby Disabler") then
        local configChanged = false
        configChanged, config.Enabled = imgui.checkbox("Enabled", config.Enabled)

        if imgui.button("Release pawns from standby") then
            requestRelease = true
        end

        imgui.tree_pop()
        if configChanged then
            json.dump_file(CONFIG_FILE, config)
        end
    end
end)
