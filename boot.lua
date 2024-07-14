--[[pod_format="raw",created="2024-07-12 20:06:39",modified="2024-07-14 21:41:44",revision=16]]
--[[
	Arc Loader by Kutup Tilkisi & 369px
]] 

function pod(obj, flags, meta)
	local encountered = {}
	local function check(n)
		local res = false
		if (encountered[n]) return true
		encountered[n] = true
		for k,v in pairs(n) do
			if (type(v) == "table") res = res or check(v)
		end
		return res
	end
	if (type(obj) == "table" and check(obj)) then
		return nil, "error: multiple references to same table"
	end

	if (meta) then
		local meta_str = generate_meta_str(meta)
		return _pod(obj, flags, meta_str)
	end

	return _pod(obj, flags)
end

function fetch_metadata(filename)
	local result = _fetch_metadata(fstat(filename) == "folder" and filename.."/.info.pod" or filename)
	return result
end

local function generate_meta_str(meta_p)
	local meta = unpod(pod(meta_p)) or {}

	local meta_str = "--[["
	if (meta.pod_format and type(meta.pod_format) == "string") then
		meta_str ..= "pod_format=\""..meta.pod_format.."\""
		meta.pod_format = nil
	elseif (meta.pod_type and type(meta.pod_type) == "string") then
		meta_str ..= "pod_type=\""..meta.pod_type.."\""
		meta.pod_type = nil
	else
		meta_str ..= "pod"
	end

	local meta_str1 = _pod(meta, 0x0) 
	if (meta_str1 and #meta_str1 > 2) then
		meta_str1 = string.sub(meta_str1, 2, #meta_str1-1)
		meta_str ..= ","
		meta_str ..= meta_str1
	end

	meta_str..="]]"

	return meta_str

end


function store_metadata(filename, meta)
	local old_meta = fetch_metadata(filename)
		
	if (type(old_meta) == "table") then
		if (type(meta) == "table") then			
			for k,v in pairs(meta) do
				old_meta[k] = v
			end
		end
		meta = old_meta
	end
	if (type(meta) != "table") meta = {}
	meta.modified = date() 
	local meta_str = generate_meta_str(meta)

	if (fstat(filename) == "folder") then
		local info_filename = filename.."/.info.pod" 
		if false then
			_store_metadata(info_filename, meta_str)
				
		else
			_store_local(info_filename, nil, meta_str) 
		end
	else
		_store_metadata(filename, meta_str)
	end
end

-- Actual boot.lua
local systems_metadata = fetch_metadata("/systems")
local selected_os = systems_metadata.os or "picotron"
local type = systems_metadata.type or 1

-- from api.lua#_rm
local function delete(path)
	local attribs = fstat(path)

	if (not attribs) then
		-- does not exist
		return
	end

	if (attribs == "folder") then
		local l = ls(path)
		for _, fn in pairs(l) do
			delete(path.."/"..fn)
		end

		-- remove metadata (not listed)
		delete(path.."/.info.pod")
	end


	-- delete single file / now-empty folder
	return _fdelete(path)
end

local function copy_system(path)
	local source_path, target_path = "/systems/"..selected_os..path, "/system"..path
	local attribs = fstat(source_path)

	if attribs == "folder" then
		mkdir(target_path)

		local l = ls(source_path)
		add(l, ".info.pod")
		for k, fn in pairs(l) do	
			copy_system(path.."/"..fn)
		end
		return
	end

	cp(source_path, target_path)
end

local function prepare_system()
	-- Create a temporary folder to store our bootloader
	mkdir("/arcloadertemp")
	cp("/system/boot.lua", "/arcloadertemp/boot.lua")

	-- Delete entire system for a fresh start
	-- TODO: Diff files? Causes too much delay to delete each file & folder
	delete("/system")
	
	-- Copy entire /system/selected_system to /system
	copy_system("")
	
	-- Copy our bootloader back to system main file
	cp("/arcloadertemp/boot.lua", "/system/boot.lua")

	-- Delete our temporary folder.
	delete("/arcloadertemp")
end

local function run_system()
	prepare_system()

	local sysboot_src = fetch("/system/sysboot.lua")
	if not sysboot_src and selected_os != "picotron" then
		selected_os = "picotron"
		run_system()
		return
	end	

	local booter, err = load(sysboot_src)
	if not booter or err  then
		selected_os = "picotron"
		run_system()
		return
	end

	-- Will never return. No problem
	booter()
end

if type == 1 then
	if not systems_metadata.bypass then
		selected_os = ".bootos"
	else
		store_metadata("/systems", {bypass=false})
	end
elseif type == 2 then
	for i=1,20 do
		flip()
		if (stat(988) > 0) then
			selected_os = ".bootos"
			break
		end
	end	
end
run_system()
