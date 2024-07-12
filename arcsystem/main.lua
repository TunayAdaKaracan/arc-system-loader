--[[pod_format="raw",created="2024-06-26 12:33:32",modified="2024-07-12 19:40:39",revision=1142]]
include("utils/json.lua")
include("utils/basexx.lua")
include("utils/textwrap.lua")
include("gui.lua")

bootfile = {}

function bootfile.local()
	return fetch("resource/boot.lua")
end

function bootfile.remote()
	local url = "https://raw.githubusercontent.com/TunayAdaKaracan/arc-system-loader/main/boot.lua"
	return fetch(url)
end

local function install_system_selector()
end

local function install_defaults()
	-- First create the systems folder to hold installed ones
	mkdir("/systems")
	
	-- Not sure why can't directly transfer but this is the way
	cp("/system", "/original")
	cp("/original", "/systems/picotron")
	
	-- Rename boot.lua to sysboot.lua and delete old file
	cp("/systems/picotron/boot.lua", "/systems/picotron/sysboot.lua")
	rm("/systems/picotron/boot.lua")
	
	-- Create /system folder in host so it will stay same between starts.
	rm("/system")
	cp("/original", "/system")
	rm("/original")
	
	-- Rename loaded boot.lua to sysboot.lua as well.
	cp("/system/boot.lua", "/system/sysboot.lua")
	rm("/system/boot.lua")
	
	-- Finally save system loader as boot.lua
	store("/system/boot.lua", bootfile.local())
	
	-- Settings
	store_metadata("/systems", {os="picotron", timer=5, type=})
end

function install_loader()
	install_defaults()
	install_system_selector()
end

-- System Installation

-- Assume we are on /apps/arcsystem.p64
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
	
	print("Select your system.\nCurrent: "..fetch_metadata("/systems").os,15,10)
end

function _update()
	if is_installed and not is_up_to_date_checked then
		is_up_to_date = bootfile.remote() == fetch("/system/boot.lua")
		is_up_to_date_checked = true
		
		if not is_up_to_date then
			gui.attach_update_button()
		else
			gui.attach_system_selector()
		end
	end
	gui:update_all()
end