local modname="Clock"
local configfile=modname..".json"
log.info("["..modname.."]".."Start")
--settings
local _config={
    {name="Style",type="mutualbox"},
    {name="fontsize",type="int",default=60,min=1,max=250,needrestart=true},
    {name="offset",type="intN",default={50,50},min=-300,max=8000},
    {name="color",type="rgba32",default=0xffEEEEEE},
    {name="backgroundcolor",type="rgba32",default=0x88777777},

    {name="Format",type="mutualbox"},
    {name="zerofill",type="bool",default=true},
    {name="showbackground",type="bool",default=true},
    {name="showtimeslot",type="bool",default=true},
    {name="useAMPM",type="bool",default=false},
    {name="customFormat",type="string",default="{D}-Day {T} {h}:{m} {a}"},
    
    {name="Enable",type="mutualbox"},
    {name="disableInMenu",type="bool",default=false},
    {name="enable",type="bool",default=true},
    {name="enableHotkey",type="hotkey",default="Alpha3",actionName="ClockEnable8293"},
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
--cached render state, rebuilt only when the in-game minute (or a setting) changes
local cached_msg=nil
local cached_w,cached_h=0,0
local cached_key=nil
local next_poll=0
--On setting Change
local function OnChanged()
    cached_key=nil
end
--try load api and draw ui
local function prequire(...)
    local status, lib = pcall(require, ...)
    if(status) then return lib end
    return nil
end

local hk = prequire("Hotkeys/Hotkeys")
local font = imgui.load_font("times.ttf", config.fontsize)
local guiManager=sdk.get_managed_singleton("app.GuiManager")
local function Log(msg)
    log.info(modname..msg)
end

re.on_frame(function()
    if hk~=nil and hk.check_hotkey("ClockEnable8293",false,true) then
        config.enable=not config.enable
    end
    if not config.enable then return end
    if config.disableInMenu and guiManager:get_IsLoadGui() then return end

    -- 1 in-game minute = 2 real seconds, so polling 4x per in-game minute is plenty
    local now=os.clock()
    if now>=next_poll or cached_key==nil then
        next_poll=now+0.5
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
                if config.showtimeslot then
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
                if config.useAMPM==true then
                    if h<12 then ampm="AM"
                    else ampm="PM" end
                    -- 0:30 PM should be 12:30 PM?
                    if h>12 then h=h%12 end
                end

                local dformat=config.zerofill and "%02d" or "%2d"
                local msg=config.customFormat
                msg=msg:gsub(":?{s}","")
                msg=msg:gsub("{h}", string.format(dformat,h))
                msg=msg:gsub("{m}", string.format(dformat,m))
                msg=msg:gsub("{D}", tostring(d))
                msg=msg:gsub("{T}", state)
                msg=msg:gsub("{a}", ampm)
                cached_msg=msg

                if config.showbackground==true then
                    imgui.push_font(font)
                    local size=imgui.calc_text_size(msg)
                    imgui.pop_font()
                    cached_w,cached_h=size.x,size.y
                end
            end
        end
    end

    if cached_msg==nil then return end

    imgui.push_font(font)
    if config.showbackground==true then
        draw.filled_rect(config.offset[1]-5, config.offset[2]-5, cached_w+10, cached_h+10, config.backgroundcolor)
    end
    draw.text(cached_msg,config.offset[1],config.offset[2],config.color)
    imgui.pop_font()
end)



local myapi = prequire("_XYZApi/_XYZApi")
if myapi~=nil then myapi.DrawIt(modname,configfile,_config,config,OnChanged) end
