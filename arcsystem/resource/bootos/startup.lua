
-- load settings
local sdat = fetch"/appdata/system/settings.pod"
if not sdat then
	-- install defaults
	sdat = fetch"/system/misc/default_settings.pod"
	store("/appdata/system/settings.pod", sdat)
end

-- settings added since first release should default to a non-nil value

if (sdat.anywhen == nil) then
	sdat.anywhen = true
	store("/appdata/system/settings.pod", sdat)
end

if (sdat.pixel_scale == nil) then
	sdat.pixel_scale = 2
	store("/appdata/system/settings.pod", sdat)
end


-- present working cartridge
local num = 0
local num=0
while (fstat("/untitled"..num..".p64") and num < 64) num += 1
store("/ram/system/pwc.pod", "/untitled"..num..".p64")


-- custom startup could opt to run different window / program manager
create_process("/system/pm/pm.lua")
create_process("/system/wm/wm.lua")

------------------------------------------------------------------------------------------------
--   hold down lctrl + rctrl on boot to start with a minimal terminal setup
--   useful for recovering from borked /appdata/system/startup.lua
------------------------------------------------------------------------------------------------

-- give a guaranteed short window to skip

for i=1,20 do
	flip()
	if (stat(988) > 0) bypass = true _signal(35) 
end

if (bypass) then
	create_process("/system/apps/terminal.lua", 
		{
			window_attribs = {fullscreen = true, pwc_output = true, immortal = true},
			immortal   = true -- exit() is a NOP; separate from window attribute :/
		}
	)
	return
end


create_process("/system/apps/arcselector.p64", 
	{
			window_attribs = {fullscreen = true, pwc_output = true, immortal = true},
			immortal   = true -- exit() is a NOP; separate from window attribute :/
	}
)

