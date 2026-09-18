local modname="Clock"
local configfile=modname..".json"
log.info("["..modname.."]".."Start")
--settings
local _config={
    {name="Style",type="mutualbox"},
    {name="FontSize",type="int",default=60,min=1,max=250},
    {name="Offset",type="intN",default={50,50},min=-300,max=8000},
    {name="Color",type="rgba32",default=0xffEEEEEE},
    {name="BgColor",type="rgba32",default=0x88777777},

    {name="Format",type="mutualbox"},
    {name="ZeroFill",type="bool",default=true},
    {name="ShowBg",type="bool",default=true},
    {name="ShowTimeSlot",type="bool",default=true},
    {name="UseAMPM",type="bool",default=false},
    {name="CustomFormat",type="string",default="Day {D} - {T} {h}:{m} {a}"},
    
    {name="Enable",type="mutualbox"},
    {name="DisableInMenu",type="bool",default=false},
    {name="DisableInCutscene",type="bool",default=true},
    {name="EnableClock",type="bool",default=true},
    {name="ToggleHotkey",type="hotkey",default="Alpha3",actionName="ClockEnable8293"},
}
--merge config file to default config
local function recurse_def_settings(tbl, new_tbl)
	for key, value in pairs(new_tbl) do
		if type(tbl[key]) == type(value) then
		    if type(value) == "table" then
			    tbl[key] = recurse_def_settings(tbl[key], value)
            else
    		    tbl[key] = value
            end
		end
	end
	return tbl
end
local config = {} 
for key,para in pairs(_config) do
    config[para.name]=para.default
end
config= recurse_def_settings(config, json.load_file(configfile) or {})

local current_FontSize=config.FontSize
local font=imgui.load_font("times.ttf", config.FontSize)

--cached render state, rebuilt only when the in-game minute (or a setting) changes
local cached_msg=nil
local cached_w,cached_h=0,0
local cached_key=nil
local next_poll=0

--On setting Change
local function OnChanged()
    if config.FontSize ~= current_FontSize then
        current_FontSize = config.FontSize
        local new_font = imgui.load_font("times.ttf", config.FontSize)
        if new_font ~= nil then
            font = new_font
        end
    end
    cached_key=nil
end
--try load api and draw ui
local function prequire(...)
    local status, lib = pcall(require, ...)
    if(status) then return lib end
    return nil
end

local hk = prequire("Hotkeys/Hotkeys")
local guiManager=sdk.get_managed_singleton("app.GuiManager")
local demoMediator=sdk.get_managed_singleton("app.DemoMediator")
local function Log(msg)
    log.info(modname..msg)
end

re.on_frame(function()
    if hk~=nil and hk.check_hotkey("ClockEnable8293",false,true) then
        config.EnableClock=not config.EnableClock
    end
    if not config.EnableClock then return end
    if config.DisableInMenu and guiManager~=nil and guiManager:get_IsLoadGui() then return end

    -- 1 in-game minute = 2 real seconds, so polling 4x per in-game minute is plenty
    local now=os.clock()
    if now>=next_poll or cached_key==nil then
        next_poll=now+0.5
        local in_cutscene=false
        if config.DisableInCutscene then
            if demoMediator==nil then
                demoMediator=sdk.get_managed_singleton("app.DemoMediator")
            end
            in_cutscene=(demoMediator~=nil and demoMediator:get_IsPlayingDemo())
        end

        if in_cutscene then
            cached_msg=nil
            cached_key=nil
        else
            local tm=sdk.get_managed_singleton("app.TimeManager")
            if tm==nil then
                cached_msg=nil
            else
                local d=tm:get_InGameDay()
                local h=tm:get_InGameHour()
                local m=tm:get_InGameMinute()
                local key=((d*24)+h)*60+m
                if key~=cached_key then
                    cached_key=key
                    local state=""
                    if config.ShowTimeSlot then
                        if tm:isNight() then
                            state="Night"
                        elseif tm:isDawn() then
                            state="Dawn"
                        elseif tm:isNoon() then
                            state="Noon"
                        elseif tm:isDusk() then
                            state="Dusk"
                        end
                    end
                    local ampm=""
                    if config.UseAMPM==true then
                        if h<12 then ampm="AM"
                        else ampm="PM" end
                        -- 0:30 PM should be 12:30 PM?
                        if h>12 then h=h%12 end
                    end

                    local dformat=config.ZeroFill and "%02d" or "%2d"
                    local msg=config.CustomFormat
                    msg=msg:gsub(":?{s}","")
                    msg=msg:gsub("{h}", string.format(dformat,h))
                    msg=msg:gsub("{m}", string.format(dformat,m))
                    msg=msg:gsub("{D}", tostring(d))
                    msg=msg:gsub("{T}", state)
                    msg=msg:gsub("{a}", ampm)
                    cached_msg=msg

                    if config.ShowBg==true then
                        imgui.push_font(font)
                        local size=imgui.calc_text_size(msg)
                        imgui.pop_font()
                        cached_w,cached_h=size.x,size.y
                    end
                end
            end
        end
    end

    if cached_msg==nil then return end

    imgui.push_font(font)
    if config.ShowBg==true then
        draw.filled_rect(config.Offset[1]-5, config.Offset[2]-5, cached_w+10, cached_h+10, config.BgColor)
    end
    draw.text(cached_msg,config.Offset[1],config.Offset[2],config.Color)
    imgui.pop_font()
end)



local myapi = prequire("_XYZApi/_XYZApi")
if myapi~=nil then myapi.DrawIt(modname,configfile,_config,config,OnChanged) end
