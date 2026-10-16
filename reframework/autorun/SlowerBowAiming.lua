--[[ SlowerBowAiming 1.1.X
]]
-- globals
local modName = "SlowerBowAiming"
local hotkeys = require("Hotkeys/Hotkeys")
local aimHotkey = modName .. " Toggle Slow Aim"
local defaultHotkeys = {[aimHotkey] = "L3"}
local activationModes = {"Tap", "Hold"}
local configfile = modName .. '.json'
local enableLog = false
local enableLogVerbose = false
local _experimental = true
local enableDebug = false
local _Application = sdk.get_native_singleton("via.Application")
local _ApplicationType = sdk.find_type_definition("via.Application")
local _CameraManager = sdk.get_managed_singleton("app.CameraManager")
local _GuiManager = nil

local _CharacterManager = nil
local _Character = nil
local _Player = nil
local _Human = nil
local _InputProcessor = nil
local _CommonActionController = nil
local MOInitialized = false
local slowAimOn = false
local isAiming = false
local isPaused = false
local lastAimingVal = false
local _speed = {
    ["GLACIER"] = 0.10,
    ["SNAIL"] = 0.25,
    ["TURTLE"] = 0.4,
    ["HALF"] = 0.5,
    ["SLIGHT"] = 0.6,
    ["SQUINT"] = 0.75,
    ["NORMAL"] = 1.0
}
local speed_choices = {"GLACIER","SNAIL","TURTLE","HALF","SLIGHT","SQUINT","NORMAL"}
local default_config = {
    ["speed"] = "HALF",
    ["bow"] = true,
    ["magic_bow"] = true,
    ["throw"] = true,
    ["ignorePlayer"] = false,
    ["GamePadAimSpeedSync"] = false,
    ["DisableTSVFX"] = false,
    ["VFXColor"] = 0x270AB4D8,
    ["throwReleaseDamper"] = 250,
    ["bowReleaseDamper"] = 60,
    ["magicBowReleaseDamper"] = 60,
    ["easeTransition"] = true,
    ["showSkillTimer"] = false,
    ["skillTimerBarColor"] = 0x5578B4CF,
    ["skillTimerTargetColor"] = 0xBBFFFFFF,
    ["skillTimerCursorColor"] = 0xCC000000,
    ["oneSecSkillCharge"] = false,
    ["useHotkey"] = false,
    ["hotkeyActivationMode"] = "Tap",
    ["hotkeyActivationDelay"] = 0.25
}

-- load json configuration from json file or use default configuration if
-- file does not exist in the game data folder
local config = json.load_file(configfile) or {}
for key, value in pairs(default_config) do
    if config[key] == nil then
        config[key] = value
    end
end

config.Hotkeys = config.Hotkeys or {}
hotkeys.setup_hotkeys(config.Hotkeys, defaultHotkeys)
if config.hotkeyActivationMode ~= "Tap" and config.hotkeyActivationMode ~= "Hold" then
    log.error("[" .. modName .. "] Invalid hotkey activation mode; using Tap")
    config.hotkeyActivationMode = "Tap"
end
if type(config.hotkeyActivationDelay) ~= "number"
    or config.hotkeyActivationDelay ~= config.hotkeyActivationDelay
    or config.hotkeyActivationDelay < 0 or config.hotkeyActivationDelay > 1 then
    log.error("[" .. modName .. "] Invalid hotkey activation delay; using 0.25 seconds")
    config.hotkeyActivationDelay = 0.25
end

if _speed[config.speed] == nil then
    log.error("[" .. modName .. "] Invalid speed setting: " .. tostring(config.speed) .. "; using HALF")
    config.speed = default_config.speed
end

-- update the json configfile within the game folder
local function saveConfig()
    if json.load_file(configfile) ~= config then 
        json.dump_file(configfile, config)
    end
end

-- wrapper for logging actions
-- logging turned off when enableLog = false
local function _log(_cat,msg)
    if enableLog then 
        log.debug("[" .. tostring(modName) .. "][" .. tostring(_cat) .. "] " .. tostring(msg))
    end
end


local function _logV(_cat,msg)
    if enableLogVerbose then 
        _log(_cat,msg)
    end
end

_log('MOD','STARTED')

local fromSpeed = 1.000
local function setAppSpeed(spd, _step, _base)
    _step = _step or 1
    _base = _base or 1
    _log("easeStep", string.format("%d if %d", _step, _base))
    if (spd < fromSpeed and _step == 1)
        or (spd > fromSpeed and _step == _base) then 
        fromSpeed = sdk.call_native_func(_Application, _ApplicationType, "get_GlobalSpeed()")
    end
    spd = spd or _speed.NORMAL
    if _step ~= _base then 
        fromSpeed = fromSpeed or _speed.NORMAL
        spd = fromSpeed + ((spd - fromSpeed) * (_step / _base))
    end
    -- in the cases where we miss any incremental steps before finishing the easeIn process
    -- make sure that the speed is set
    if (_step == 0) then 
        spd = _speed.NORMAL
    --     fromSpeed = _speed.NORMAL
    -- elseif _base > 1 and _step == _base then 
    --     fromSpeed = spd
    end
    _log("AppTS CHANGE", spd)
    sdk.call_native_func(_Application, _ApplicationType, "set_GlobalSpeed(System.Single)", spd)

end

-- setup managed objects that need to wait until runtime availability
local function initManagedObjects()
    if not MOInitialized then
        _log("initManagedObjects", "start")
        _CharacterManager = sdk.get_managed_singleton("app.CharacterManager")
        if not _CharacterManager then return end
        _Character = sdk.to_managed_object(_CharacterManager:get_ManualPlayer())
        _Player = sdk.to_managed_object(_CharacterManager:get_ManualPlayerPlayer())
        _Human = sdk.to_managed_object(_CharacterManager:get_ManualPlayerHuman())
        if not _Character or not _Player or not _Human then return end
        _CommonActionController = _Human:get_HumanCommonActionCtrl()
        _InputProcessor = sdk.to_managed_object(_Player:get_field("InputProcessor"))
        _CameraManager = sdk.get_managed_singleton("app.CameraManager")
        _log("initManagedObjects", "end")
        if not _InputProcessor then 
            _log("InputProcessor", "NotFound")
            MOInitialized = false
        else 
            MOInitialized = true
        end
    end
end

-- return the numerical index of a value (v) if it exists in a table (t)
local function ioftval(t,v)
    for i,x in ipairs(t) do
        if v == x then return i end 
    end
    return nil
end

-- return the percentage string format of current speed
local function spdToString()
    local spd100 = _speed[config.speed] * 100
    return tostring(math.floor(spd100)) .. "%"
end

local function getBowCharge()
    local track = _Human and _Human:get_field("UpperDrawBowTrack")
    if track then return track:get_field("DrawRatio") end
end

local lastIsLoosed = {nil,nil}
local function isBowLoosed()
    local track = _Human and _Human:get_field("Track")
    if track then
        local scb = track:get_field("SpecialCancelBuffer")
        local BowCharge = getBowCharge()
        if BowCharge == nil then return false end
        if lastIsLoosed[1] ~= scb or lastIsLoosed[2] ~= BowCharge then 
            _logV("IsLoosed", string.format("[%s] and [%f]",tostring(scb),BowCharge))
            lastIsLoosed = {scb,BowCharge}
        end
        return not scb and BowCharge == 0
    else 
        return false
    end
end

-- app.Character.JobEnum.Job02 (archer) = 2; Job08 (magick archer) = 8.
local function isBowActive()
    local bowActive = false
    if _CommonActionController ~= nil 
        and _CommonActionController:get_field("PrevWeaponJob") == 2 then 
        bowActive = true 
    end
    return bowActive
end

-- infer player is using magic bow when PrevWeaponJob is equal to 8
local function isMagicBowActive()
    local magicBowActive = false
    if _CommonActionController ~= nil 
        and _CommonActionController:get_field("PrevWeaponJob") == 8 then 
        magicBowActive = true 
    end
    return magicBowActive
end


--[[
    Skill Perfect Release Logic
    --Show an indicator that visually represents the timing for releasing a skill at full charge.
    [ ] leverage the app.Human attributes:
        [ ] SecPrepareSkill -- the time when skill is charged
        [ ] <TimerPrepareSkill>k__BackingField -- current time held before full charge

    create a bar with the middle representing a fully charged skill window
    move an indicator for left to right as the TimerPrepareSkill is incremented
]]
local _display = imgui.get_display_size()
local dst = {
    ["Bar"] = {
        ["x"] = (_display.x * (3/10)) - (_display.x * (0.7/200)),
        ["y"] = _display.y * (22/24),
        ["w"] = _display.x * (4/10) + (_display.x * (0.7/100)),
        ["h"] = _display.y * (1/100),
        ["color"] = config.skillTimerBarColor
    },
    ["Circle"] = {
        ["radius"] = 0
    },
    ["PerfectRelease"] = {
        ["start"] = 0.5,
        ["window"] = 0.05,
        ["color"] = config.skillTimerTargetColor
    },
    ["Cursor"] = {
        ["y"] = _display.y * (22/24),
        ["w"] = _display.y * (1/100),
        ["h"] = _display.y * (1/100),
        ["color"] = config.skillTimerCursorColor
    },
    ["timer"] = {
        ["frame"] = 0,
        ["expire"] = 100,
        ["totalElapse"] = 0,
        ["logDiff"] = 0,
        ["logDiffLast"] = 0
    },
    ["is"] = {
        ["charging"] = false,
        ["released"] = false,
        ["expired"] = true
    }
}

local function getSkillPrepVals()
    if _Human ~= nil then 
        return table.unpack({
            _Human:get_field("SecPrepareSkill"),
            _Human:get_field("<TimerPrepareSkill>k__BackingField"),
            _Human:get_field("TimerElapsedAfterSkillPrepared")
        })
    else return table.unpack({nil,nil,nil})
    end
end

local function barStatus(sts)
    dst.is.charging = false
    dst.is.released = false 
    dst.is.expired = false
    dst.is[sts] = true
end

local function cursorHandler(s,b,a)
    if s and s > 0 then 
        local _totElapsed = a + b 
        
        if dst.is.expired and dst.timer.totalElapse ~= _totElapsed and b < s and 0 < b then 
            barStatus("charging")
            dst.timer.totalElapse = 0
        elseif dst.is.charging and dst.timer.totalElapse >= _totElapsed then 
            barStatus("released")
        end

        if dst.is.released then 
            if dst.timer.frame < dst.timer.expire then 
                dst.timer.frame = dst.timer.frame + 1
            else 
                dst.timer.frame = 0
                barStatus("expired")
            end 
        elseif dst.is.charging then 
            dst.timer.totalElapse = _totElapsed
        end

        if not dst.is.expired then 
            -- draw cursor relative to the b (before) and a (after) timers
            local progLen = dst.Bar.w * dst.PerfectRelease.start * (dst.timer.totalElapse)/s
            -- do not extend past bar end
            if progLen > dst.Bar.w - dst.Cursor.w then 
                progLen = dst.Bar.w - dst.Cursor.w
            end
            draw.filled_rect(
                -- dst.Bar.x + offset --  bar.w * prStart(0.5) * (a+b)/s
                dst.Bar.x + progLen,
                dst.Cursor.y,
                dst.Cursor.w,
                dst.Cursor.h,
                dst.Cursor.color
            )

            -- draw.filled_circle(
            --     -- dst.Bar.x + offset --  bar.w * prStart(0.5) * (a+b)/s
            --     dst.Bar.x + (dst.Bar.w * dst.PerfectRelease.start * (dst.timer.totalElapse)/s),
            --     dst.Cursor.y + dst.Bar.h/2,
            --     dst.Cursor.h/2,
            --     dst.Cursor.color
            -- )
        end
        local x = 0
        if dst.is.charging then x = x + 100 end 
        if dst.is.released then x = x + 10 end 
        if dst.is.expired then x = x + 1 end 
        dst.timer.logDiff = _totElapsed + x + dst.timer.frame
        if dst.timer.logDiff ~= dst.timer.logDiffLast then 
            dst.timer.logDiffLast = dst.timer.logDiff
            _log("dstVals", string.format("sba: (%f, %f, %f) | cre: %d | dst.t.totElap: %f | tframe: %d", s,b,a,x,dst.timer.totalElapse, dst.timer.frame))
        end 
        
    end
end

local function drawSkillTimer()
    local secPrepare, secBefore, secAfter = getSkillPrepVals()
    if not dst.is.expired then 
        draw.filled_rect(dst.Bar.x, dst.Bar.y, dst.Bar.w, dst.Bar.h, dst.Bar["color"])
        draw.filled_rect(
            dst.Bar.x + dst.Bar.w * dst.PerfectRelease.start,
            dst.Bar.y,
            dst.Bar.w * dst.PerfectRelease.window,
            dst.Bar.h,
            dst.PerfectRelease.color
        )
    end
    cursorHandler(secPrepare,secBefore,secAfter)
    --draw.
end

local function isCarryObject() 
    return _Human ~= nil and _Human:isCarryAnything()
end 

local function getAdjWorkRate(_step, _base)
    _step = _step or 1
    _base = _base or 1
    local adjWR = 1 + (_step/_base)*(1/_speed[config.speed] -1) 
    _logV("adjWorkrate", tostring(adjWR))
    return adjWR
end

local alphaMax = 40
local drawFilter = false
local currFilterColor = config.VFXColor

local function decimalToHex(num)
    if num == 0 then
        return '0'
    end
    local neg = false
    if num < 0 then
        neg = true
        num = num * -1
    end
    local hexstr = "0123456789ABCDEF"
    local result = ""
    while num > 0 do
        local n = math.fmod(num, 16)
        result = string.sub(hexstr, n + 1, n + 1) .. result
        num = math.floor(num / 16)
    end
    if neg then
        result = '-' .. result
    end
    return result
end

local function toggleVFXFilter(enable, _step, _base)
    _step = _step or 1 
    _base = _base or 1
    
    if not enable and _step <= 0 then 
        drawFilter = false
    elseif enable and _step == _base then 
        drawFilter = true 
        currFilterColor = config.VFXColor
    else 
        drawFilter = true
        local _clrNoAlpha = math.fmod(config.VFXColor,256^3)
        local _alpha = (config.VFXColor - _clrNoAlpha) / 256^3
        if _alpha > alphaMax then _alpha = alphaMax end
        local vMult = _step/_base
        currFilterColor = _clrNoAlpha + math.floor(_alpha*vMult) * (256^3)
    end
    _log("filterColor Change", decimalToHex(currFilterColor))
end

local function drawAimFilter()
    if drawFilter then 
        draw.filled_rect(0,0,8000, 4500, currFilterColor)
    end
end

-- modify the character object workrate which affects animation speed relative to global timescale
-- workrate and global timescale are typically both set to 1.0
-- the workrate adjustment is the inverse of the timescale adjustment
-- i.e. if the timescale is set to 0.5 then the workrate adjustment will be 2.0 ( 1 / 0.5 ) 
local showNextWorkRate = true
local lastWorkRate = nil
local playerSpeedCompensated = false
local workRateUnavailableLogged = false
local function getPlayerWorkRate()
    local workRate = _Player and _Player:get_field("<WorkRate>k__BackingField")
    if not workRate then
        if not workRateUnavailableLogged then
            log.error("[" .. modName .. "] Player WorkRate unavailable; skipping player speed adjustment until it is available")
            workRateUnavailableLogged = true
        end
        return nil
    end
    workRateUnavailableLogged = false
    return workRate
end

local function compensateWorkRate()
    local workRate = getPlayerWorkRate()
    if workRate then
        local workRateAdj = getAdjWorkRate()
        workRate.NextRateValue = workRateAdj
        workRate.NextApplyRate = workRateAdj
        playerSpeedCompensated = true
        if showNextWorkRate or workRateAdj ~= lastWorkRate then 
            _logV("WorkRateAdj", workRateAdj) 
            showNextWorkRate = false
            lastWorkRate = workRateAdj
        end
    end
end

--[[
    fix for the aiming speed of XBOX (and possibly other) controllers reduction in Yaw and Pitch speed
    relative to the reduction in global timescale
        [""] = false,
    [""] = false,
    [""] = false
]]
local origGamePadYawSpeed = nil
local origGamePadPitchSpeed = nil
local origGamePadYawSpeed_aim = nil
local origGamePadPitchSpeed_aim = nil
local origGamePadYawSpeed_prj = nil
local origGamePadPitchSpeed_prj = nil
local cameraSpeedCompensated = false
local function compensateGamePadAimSpeed(_activate, _step, _base)
    _step = _step or 1
    _base = _base or 1
    if _CameraManager then
        if _activate then 
            if _step == 1 then 
                origGamePadYawSpeed = _CameraManager:get_field("_YawSpeedRate") or 1.000
                origGamePadPitchSpeed = _CameraManager:get_field("_PitchSpeedRate") or 1.000
                origGamePadYawSpeed_aim = _CameraManager:get_field("_AimYawSpeedRate") or 1.000
                origGamePadPitchSpeed_aim = _CameraManager:get_field("_AimPitchSpeedRate") or 1.000
                origGamePadYawSpeed_prj = _CameraManager:get_field("_ThrowingAimYawSpeedRate") or 1.000
                origGamePadPitchSpeed_prj = _CameraManager:get_field("_ThrowingAimPitchSpeedRate") or 1.000
            end
            local workRateAdj = getAdjWorkRate(_step, _base)
            -- Camera Speed Settings
            _CameraManager._YawSpeedRate = workRateAdj * origGamePadYawSpeed
            _CameraManager._PitchSpeedRate = workRateAdj * origGamePadPitchSpeed
            _logV("GamePadAimSpeedAdj", string.format("[X: %f --> %f][Y: %f --> %f]", 
                origGamePadYawSpeed, _CameraManager._YawSpeedRate, origGamePadPitchSpeed, _CameraManager._PitchSpeedRate))
            -- Aiming Camera Speed Settings
            _CameraManager._AimYawSpeedRate = workRateAdj * origGamePadYawSpeed_aim
            _CameraManager._AimPitchSpeedRate = workRateAdj * origGamePadPitchSpeed_aim
            _logV("GamePadAimSpeedAdj", string.format("AIM [X: %f --> %f][Y: %f --> %f]", 
                origGamePadYawSpeed_aim, _CameraManager._AimYawSpeedRate, origGamePadPitchSpeed_prj, _CameraManager._AimPitchSpeedRate))
            -- Projectile Aiming Speed Settings
            _CameraManager._ThrowingAimYawSpeedRate = workRateAdj * origGamePadYawSpeed_prj
            _CameraManager._ThrowingAimPitchSpeedRate = workRateAdj * origGamePadPitchSpeed_prj
            cameraSpeedCompensated = true
            _logV("GamePadAimSpeedAdj", string.format("PRJ [X: %f --> %f][Y: %f --> %f]", 
                origGamePadYawSpeed_prj, _CameraManager._ThrowingAimYawSpeedRate, origGamePadPitchSpeed_prj, _CameraManager._ThrowingAimPitchSpeedRate))
        else 
            _CameraManager._YawSpeedRate = origGamePadYawSpeed
            _CameraManager._PitchSpeedRate = origGamePadPitchSpeed
            _logV("GamePadAimSpeedAdj", string.format("[X: %f][Y: %f]", _CameraManager._YawSpeedRate, _CameraManager._PitchSpeedRate))
            _CameraManager._AimYawSpeedRate = origGamePadYawSpeed_aim
            _CameraManager._AimPitchSpeedRate = origGamePadPitchSpeed_aim
            _logV("GamePadAimSpeedAdj", string.format("AIM [X: %f][Y: %f]", _CameraManager._AimYawSpeedRate, _CameraManager._AimPitchSpeedRate))
            _CameraManager._ThrowingAimYawSpeedRate = origGamePadYawSpeed_prj
            _CameraManager._ThrowingAimPitchSpeedRate = origGamePadPitchSpeed_prj
            cameraSpeedCompensated = false
            _logV("GamePadAimSpeedAdj", string.format("PRJ [X: %f][Y: %f]", _CameraManager._ThrowingAimYawSpeedRate, _CameraManager._ThrowingAimPitchSpeedRate))
        end
    end
end

local postLooseLock = false
local function aimLogicPre()
    if _InputProcessor then
        if (not isBowLoosed() or isCarryObject()) and _InputProcessor:get_field("TimerAimHoldKeep") < 1.000 then
            isAiming = _InputProcessor:get_field("IsAimHoldOn")
            if lastAimingVal ~= isAiming then 
                _logV("isAiming", tostring(isAiming))
                lastAimingVal = isAiming
            end
        else
            isAiming = false 
        end
    else 
        _log("InputProcessor", "NotFound")
        initManagedObjects()
    end
end 


local easeIn = false 
local easeOut = false
local easeSteps = 25
local easeElapsed = 0
local isDamping = false
local function easeInStep()
    if easeElapsed < easeSteps then 
        easeElapsed = easeElapsed + 1
        _logV("easeIn", string.format("%d/%d", easeElapsed, easeSteps))
        setAppSpeed(_speed[config.speed], easeElapsed, easeSteps)
        if config.GamePadAimSpeedSync then compensateGamePadAimSpeed(true, easeElapsed, easeSteps) end
        if not config["DisableTSVFX"] then 
            toggleVFXFilter(true, easeElapsed, easeSteps)
        end
    else 
        easeIn = false 
        easeElapsed = 0
        isDamping = false
    end
end 

local function easeOutStep()
    if easeElapsed < easeSteps then 
        easeElapsed = easeElapsed + 1
        _logV("easeOut", string.format("%d/%d", easeElapsed, easeSteps))
        setAppSpeed(_speed[config.speed], (easeSteps - easeElapsed), easeSteps)
        if config.GamePadAimSpeedSync then compensateGamePadAimSpeed(false, (easeSteps - easeElapsed), easeSteps) end
        if not config["DisableTSVFX"] then 
            toggleVFXFilter(false, (easeSteps - easeElapsed), easeSteps)
        end
    else 
        easeOut = false 
        easeElapsed = 0
        slowAimOn = false
        isDamping = false
    end
end

local function startEasing()
    easeIn = true 
end

local function endEasing()
    easeOut = true
end

local carryObjectAim = false
local dampingFrames = 0
local hotkeyActive = false
local hotkeyPendingAt = nil
local hotkeyWasDown = false

local function stopHotkeySlowAim()
    hotkeyActive = false
    hotkeyPendingAt = nil
    if not slowAimOn then return end
    setAppSpeed(_speed.NORMAL)
    if cameraSpeedCompensated then compensateGamePadAimSpeed(false) end
    if playerSpeedCompensated then
        local workRate = getPlayerWorkRate()
        if workRate then
            workRate.NextRateValue = 1
            workRate.NextApplyRate = 1
            playerSpeedCompensated = false
        end
    end
    toggleVFXFilter(false, 0)
    slowAimOn = false
    easeIn = false
    easeOut = false
    easeElapsed = 0
    isDamping = false
    dampingFrames = 0
    carryObjectAim = false
    showNextWorkRate = true
end

local function canSlowAim()
    if not MOInitialized or not isAiming then return false end
    if isCarryObject() then return config.throw end
    return (config.bow and isBowActive()) or (config.magic_bow and isMagicBowActive())
end

local function updateAimHotkey()
    local down = not not hotkeys.check_hotkey(aimHotkey, true)
    local pressed = hotkeys.check_hotkey(aimHotkey, false, true) and not hotkeyWasDown
    hotkeyWasDown = down
    if not config.useHotkey then
        hotkeyActive = false
        hotkeyPendingAt = nil
        return
    end
    local binding = hotkeys.hotkeys[aimHotkey]
    if isPaused or not canSlowAim() or binding == "[Press Input]" or binding == "[Not Bound]" then
        stopHotkeySlowAim()
        return
    end
    local now = os.clock()
    if pressed then
        if hotkeyActive or hotkeyPendingAt ~= nil then
            stopHotkeySlowAim()
            return
        end
        hotkeyPendingAt = now
    end
    if hotkeyPendingAt ~= nil then
        if config.hotkeyActivationMode == "Hold" and not down then
            hotkeyPendingAt = nil
        elseif now - hotkeyPendingAt >= config.hotkeyActivationDelay then
            hotkeyPendingAt = nil
            hotkeyActive = true
        end
    end
end

local function aimLogicPost()
    if _Application ~= nil and MOInitialized then
        if config.useHotkey then
            if not canSlowAim() then
                stopHotkeySlowAim()
                return
            elseif not hotkeyActive then
                if slowAimOn then stopHotkeySlowAim() end
                return
            end
        end
        if easeIn then 
            easeInStep()
        elseif easeOut then 
            easeOutStep()
        else
            if (isAiming or carryObjectAim) and config.ignorePlayer 
                and (
                    (config.bow and isBowActive()) 
                    or 
                    (config.magic_bow and isMagicBowActive())
                    or 
                    isCarryObject()
                ) then compensateWorkRate()
            end
            if isAiming and not slowAimOn and not isDamping then
                if (isBowActive() and config.bow and not isCarryObject()) 
                    or (isMagicBowActive() and config.magic_bow and not isCarryObject()) 
                    or (isCarryObject() and config.throw) then
                    slowAimOn = true
                    if isCarryObject() then carryObjectAim = true end
                    if not config.easeTransition then 
                        setAppSpeed(_speed[config.speed])
                        if config.GamePadAimSpeedSync then compensateGamePadAimSpeed(true) end
                        if not config["DisableTSVFX"] then 
                            toggleVFXFilter(true)
                        end
                    else 
                        startEasing()
                        easeSteps = 25
                    end
                end
            elseif (not isAiming or (isBowLoosed() and not isCarryObject())) and slowAimOn then 
                _log("Damping", dampingFrames)
                if isDamping then 
                    if dampingFrames < 1 then 
                        slowAimOn = false

                        setAppSpeed(_speed.NORMAL)
                        if config.GamePadAimSpeedSync then compensateGamePadAimSpeed(false) end
                        showNextWorkRate = true
                        if not config["DisableTSVFX"] then 
                            toggleVFXFilter(false)
                        end
                        carryObjectAim = false
                    else 
                        dampingFrames = dampingFrames - 1
                    end
                else 
                    if carryObjectAim then dampingFrames = config.throwReleaseDamper + 3
                    elseif isBowActive() then dampingFrames = config.bowReleaseDamper + 3
                    elseif isMagicBowActive() then dampingFrames = config.magicBowReleaseDamper + 3
                    else dampingFrames = 5
                    end
                    if config.easeTransition then 
                        if not easeOut then 
                            endEasing()
                            easeSteps = dampingFrames
                            carryObjectAim = false
                        end
                    else 
                        isDamping = true
                    end
                end
            else 
                isDamping = false
            end
        end
    end
end

-- updateAimHoldDown now takes an action/checker pair; the separate throw helper is gone.
-- Read the final bow/throw input state once per update.
sdk.hook(sdk.find_type_definition("app.PlayerInputProcessor"):get_method("update()"),
    function(args) initManagedObjects() end,
    function(retval)
        aimLogicPre()
        aimLogicPost()
        return retval
    end
)

re.on_script_reset(function()
    if config.useHotkey then stopHotkeySlowAim() end
end)

-- REFramework gui menu setup
local _changed = false
local indx = nil

re.on_draw_ui(function()
    if imgui.tree_node(modName) then
        local _uiWindow = imgui.get_window_size()
        imgui.set_next_item_width(175)
        _changed, indx = imgui.combo("Speed: ", ioftval(speed_choices, config.speed), speed_choices)
        imgui.same_line()
        imgui.text(spdToString())
        if _changed then 
            config.speed = speed_choices[indx]
            saveConfig() 
        end
        _changed, config.useHotkey = imgui.checkbox("Use slow-aim hotkey", config.useHotkey)
        if _changed then stopHotkeySlowAim() saveConfig() end
        if hotkeys.hotkey_setter(aimHotkey, false, "Slow-aim hotkey") then
            hotkeys.update_hotkey_table(config.Hotkeys)
            stopHotkeySlowAim()
            saveConfig()
        end
        _changed, indx = imgui.combo("Activation mode", ioftval(activationModes, config.hotkeyActivationMode), activationModes)
        if _changed then
            config.hotkeyActivationMode = activationModes[indx]
            stopHotkeySlowAim()
            saveConfig()
        end
        _changed, config.hotkeyActivationDelay = imgui.slider_float("Activation delay (seconds)", config.hotkeyActivationDelay, 0.00, 1.00, "%.2f")
        if _changed then stopHotkeySlowAim() saveConfig() end
        imgui.text("Tap: activate after delay; tap again during delay to cancel.")
        imgui.text("Hold: hold through delay. Press again or stop aiming to turn off.")
        _changed, config.bow = imgui.checkbox("Bow", config.bow)
        if _changed then saveConfig() end
        if config.bow then 
            imgui.same_line()
            imgui.set_next_item_width(_uiWindow.x/3)
            _changed, config.bowReleaseDamper = imgui.slider_int("Release Delay", config.bowReleaseDamper, 0, 1000)
            if _changed then saveConfig() end
        end

        _changed, config.magic_bow = imgui.checkbox("Magic Bow", config.magic_bow)
        if _changed then saveConfig() end
        if config.magic_bow then 
            imgui.same_line()
            imgui.set_next_item_width(_uiWindow.x/3)
            _changed, config.magicBowReleaseDamper = imgui.slider_int("Release Delay ", config.magicBowReleaseDamper, 0, 1000)
            if _changed then saveConfig() end
        end

        _changed, config.throw = imgui.checkbox("Throw Object", config.throw)
        if _changed then saveConfig() end
        if config.throw then 
            imgui.same_line()
            imgui.set_next_item_width(_uiWindow.x/3)
            _changed, config.throwReleaseDamper = imgui.slider_int("Release Delay  ", config.throwReleaseDamper, 0, 1000)
            if _changed then saveConfig() end
        end
        _changed, config.easeTransition = imgui.checkbox("Ease timescale shifts", config.easeTransition)
        if _changed then saveConfig() end
        _changed, config.ignorePlayer = imgui.checkbox("Keep Player Speed Normal", config.ignorePlayer)
        if _changed then saveConfig() end
        _changed, config.GamePadAimSpeedSync = imgui.checkbox("Sync Controller Camera/Aim Speed", config.GamePadAimSpeedSync)
        if _changed then saveConfig() end
        _changed, config.DisableTSVFX = imgui.checkbox("Disable Color Filter", config.DisableTSVFX)
        if _changed then saveConfig() end
        if not config.DisableTSVFX then 
            imgui.same_line()
            _changed, config.VFXColor = imgui.color_edit("Color", config.VFXColor, 32)
            if _changed then saveConfig() end
        end
        _changed, config.showSkillTimer = imgui.checkbox("Show skill timer", config.showSkillTimer)
        if _changed then saveConfig() end
        if config.showSkillTimer then 
            imgui.same_line()
            _changed, config.skillTimerBarColor = imgui.color_edit("Bar", dst.Bar.color, 32)
            if _changed then saveConfig() dst.Bar.color = config.skillTimerBarColor end
            imgui.same_line()
            _changed, config.skillTimerTargetColor = imgui.color_edit("Target", dst.PerfectRelease.color, 32)
            if _changed then saveConfig() dst.PerfectRelease.color = config.skillTimerTargetColor end
            imgui.same_line()
            _changed, config.skillTimerCursorColor = imgui.color_edit("Cursor", dst.Cursor.color, 32)
            if _changed then saveConfig() dst.Cursor.color = config.skillTimerCursorColor end
        end
        _changed, config.oneSecSkillCharge = imgui.checkbox("Fast Skill Charge Time", config.oneSecSkillCharge)
        if _changed then saveConfig() end
        
        if enableDebug then 
            imgui.text("Character")
            if _Character then object_explorer:handle_address(_Character) end
            imgui.text("Human")
            if _Human then object_explorer:handle_address(_Human) end
            imgui.text("PlayerInputProcessor")
            if _InputProcessor then object_explorer:handle_address(_InputProcessor) end
        end
        imgui.tree_pop()
    end
end
)


--[[ START EXPERIMENTAL
    section which contains code not ready for primetime
]]

local tempVal = sdk.create_single(10.000)
local appSkillReturn = nil
if _experimental then 
    -- app.Job02PrepareSkill.getPrepareSec()
    sdk.hook(sdk.find_type_definition("app.Job02PrepareSkill"):get_method("getPrepareSec()"),nil,
    function(retval)
        if config.oneSecSkillCharge then 
            local spdAdjustedSingleSecond = 1.00
            if not config.ignorePlayer then 
               spdAdjustedSingleSecond = _speed[config.speed]
            end
            return(sdk.float_to_ptr(spdAdjustedSingleSecond)) 
        else 
            return retval
        end
    end
    )

     -- app.Job08PrepareSkill.getPrepareSec()
     sdk.hook(sdk.find_type_definition("app.Job08PrepareSkill"):get_method("getPrepareSec()"),nil,
     function(retval)
         if config.oneSecSkillCharge then 
             local spdAdjustedSingleSecond = 1.00
             if not config.ignorePlayer then 
                spdAdjustedSingleSecond = _speed[config.speed]
             end
             return(sdk.float_to_ptr(spdAdjustedSingleSecond)) 
         else 
             return retval
         end
     end
     )
end

re.on_frame(function() 
    _GuiManager = _GuiManager or sdk.get_managed_singleton("app.GuiManager")
    isPaused = _GuiManager ~= nil and _GuiManager:isPausedGUI()
    updateAimHotkey()
    if config.showSkillTimer and (isBowActive() or isMagicBowActive()) then 
        drawSkillTimer()
    end
    if not config.DisableTSVFX and not isPaused then 
        drawAimFilter()
    end
end
)