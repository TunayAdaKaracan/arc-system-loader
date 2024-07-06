--[[pod_format="raw",created="2024-06-26 12:33:32",modified="2024-07-06 11:38:13",revision=1046]]
include("utils/json.lua")
include("utils/basexx.lua")
include("utils/textwrap.lua")
include("gui.lua")
include("installer.lua")

function _init()
	window({
		x=177,y=77,
		width = 128,
		height = 128,
		resizeable = false,
		title = "Arc Installer"
	})
end

function _draw()
	cls(32)
	gui:draw_all()
	if not is_installed then
		print("Arc is not installed.",16,47,6)
		return
	end	
	
	if not is_up_to_date_checked then
		print("Checking boot.lua\nversion...",20,50,6)
		return
	end
	
	if not is_up_to_date then
		print("File is not\nup to date",20,50,6)
		return
	end
	
	print("Select your system.\nCurrent: "..fetch_metadata("/systems").system,15,10)
end

function _update()
	if is_installed and not is_up_to_date_checked then
		is_up_to_date = get_boot_file_remote() == fetch("/system/boot.lua")
		is_up_to_date_checked = true
		
		if not is_up_to_date then
			gui.attach_update_button()
		else
			gui.attach_system_selector()
		end
	end
	gui:update_all()
end