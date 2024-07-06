--[[pod_format="raw",created="2024-07-02 08:48:44",modified="2024-07-06 11:38:14",revision=101]]
-- Default Arcsystem installer

function get_boot_file_local()
	return fetch("resource/boot.lua")
end

function get_boot_file_remote()
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
	store("/system/boot.lua", get_boot_file_local())
	
	store_metadata("/systems", {system="picotron"})
end

function install_loader()
	install_defaults()
	install_system_selector()
end

-- System Installation

-- Assume we are on /apps/arcsystem.p64
function install_system()
	
end