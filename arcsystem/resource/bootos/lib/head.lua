--[[

	head.lua -- kernal space header for each process
	(c) Lexaloffle Games LLP

]]

do

local _stop = _stop
local _mkdir = _mkdir
local _print_p8scii = _print_p8scii
local _map_ram = _map_ram
local _ppeek = _ppeek
local _create_process_from_code = _create_process_from_code
local _unmap_ram = _unmap_ram
local _store_metadata = _store_metadata
local _fdelete = _fdelete
local _apply_system_settings = _apply_system_settings
local _get_process_display_size = _get_process_display_size
local _run_process_slice = _run_process_slice
local _fetch_local = _fetch_local
local _get_clipboard_text = _get_clipboard_text
local _blit_process_video = _blit_process_video
local _set_clipboard_text = _set_clipboard_text
local _req_clipboard_text = _req_clipboard_text
local _set_spr = _set_spr
local _ppeek4 = _ppeek4
local _fetch_metadata = _fetch_metadata
local _store_local = _store_local
local _set_draw_target = _set_draw_target
local _get_process_list = _get_process_list
local _pod = _pod
local _kill_process = _kill_process
local _read_message = _read_message
local _fcopy = _fcopy
local _draw_map = _draw_map
local _halt = _halt

local _fetch_local = _fetch_local
local _fetch_remote = _fetch_remote
local _fetch_anywhen = _fetch_anywhen
local _fetch_remote_result = _fetch_remote_result
local _store_local = _store_local
local _signal = _signal


function reset()

	-- reset palette (including scanline palette selection, rgb palette)

	pal()

	-- line drawing state

	memset(0x551f, 0, 9)

	-- bitplane masks

	poke(0x5508, 0x3f) -- read mask    //  masks raw draw colour (8-bit sprite pixel or parameter)
	poke(0x5509, 0x3f) -- write mask   //  determines which bits to write to
	poke(0x550a, 0x3f) -- target mask  //  (sprites)  applies to colour table lookup & selection
	poke(0x550b, 0x00) -- target mask  //  (shapes)   applies to colour table lookup & selection

	-- draw colour

	color(6)

	-- fill pattern 0x5500

	fillp()

	-- fonts (reset really does reset everthing!)

	poke(0x5f56, 0x40) -- primary font
	poke(0x5f57, 0x56) -- secondary font
	poke(0x4000,get(fetch"/system/fonts/lil.font"))
	poke(0x5600,get(fetch"/system/fonts/p8.font"))

	-- set tab width to be a multiple of char width

	poke(0x5606, (@0x5600) * 4)
	poke(0x5605, 0x2)             -- apply tabs relative to home

	-- mouselock event sensitivity, move sensitivity (64 means x1.0)
	poke(0x5f28, 64)
	poke(0x5f29, 64)


end


local function init_runtime_state()

	-- experiment: always start with a display
	-- should be able to start drawing stuff in _init!
	-- extra 128k per process, but not many headless processes
--[[
	_disp = userdata("u8", 480, 270)
	memmap(0x10000, _disp)
	set_draw_target() -- reset target to display\
	poke2(0x5478, 480, 270)
	poke (0x547c, 0)  -- video mode
]]

	-- runtime state
	srand()

	-- default map
	memmap(0x100000, userdata("i16", 32, 32))

	-- reset() does most of the work but doesn't reset entire runtime state (maybe it should?)
	reset()

end


local function get_short_prog_name(p)
	if (not p) then return "no_prog_name" end
	--p = split0(p, "/")
	p = split(p, "/", false)
	p = p[#p]
	--p = split0(p, ".")[1]
	p = split(p, ".", false)[1]
	return p
end

function create_process(prog_name, env_patch, do_debug)

	prog_name = fullpath(prog_name)

	-- .p64 files: find boot file in root of .p64 (and thus set default path there too)
	local boot_file = prog_name
	if  string.sub(prog_name,-4) == ".p64"     or 
		string.sub(prog_name,-8) == ".p64.rom" or
		string.sub(prog_name,-8) == ".p64.png"
	then
		boot_file ..= "/main.lua"

		-- only check runtime on carts; not stored on lua files
		local meta = fetch_metadata(prog_name)
		if (meta and type(meta.runtime) == "number" and meta.runtime > stat(5)) then
			notify("** warning: running cartridge with future runtime version **")
		end
	end

--	printh("create_process "..prog_name.." ("..boot_file..") env: "..pod(env_patch))

	--===== construct new environment table if needed ======

--	local new_env = env() and unpod(pod(env())) or {}
	local new_env = {} -- don't inherit anything! env means "launch parameters"

	-- default path is same directory as boot file
	local segs = split(boot_file,"/",false)
	local program_path = string.sub(boot_file, 1, -#segs[#segs] - 2)


	-- deleteme
--	new_env.pwd = string.sub(boot_file, 1, -#segs[#segs] - 2)

	-- add new attributes from env_patch (note: can copy trees)
	if (env_patch) then
		for k,v in pairs(env_patch) do
			new_env[k] = v
		end
	end


	-- when corunning, start in folder of corun program
	-- needs to happen here so that load_resources has the correct path
	-- to do: shouldn't terminal be able to have its own resources / includes?
	if (new_env.corun_program) then
		local ppath = fullpath(new_env.corun_program)
		local segs = split(ppath,"/",false)
		program_path = string.sub(ppath, 1, -#segs[#segs] - 2)
	end


	
	-- add system env info


	new_env.prog_name = prog_name
	new_env.title = get_short_prog_name(prog_name)
	new_env.parent_pid = pid()
	new_env.argv = new_env.argv or {} -- guaranteed to exist at least as an empty table

	local str = [[
		
		do
			local head_code = load(fetch("/system/lib/head.lua", "@/system/lib/head.lua", "t", _ENV))
			if (not head_code) then printh"*** ERROR: could not load head. borked file system / out of pfile slots? ***" end
			head_code()
		end

		include("/system/lib/legacy.lua")
		include("/system/lib/api.lua")
		include("/system/lib/events.lua")
		include("/system/lib/gui.lua")
		include("/system/lib/app_menu.lua")
		include("/system/lib/wrangle.lua")

		include("/system/lib/jettison.lua")
		
		
		-- pass along environment. env() return value is read-only-ish
		
		function env() 
			return ]]..pod(new_env,0x0)..[[
		end
		
		-- always start in program path
		cd("]]..program_path..[[")

		-- autoload resources (must be after setting pwd)
		include("/system/lib/resources.lua")

		-- to do: preprocess_file() here // update: no need!
		include("]]..boot_file..[[")

		-- footer; includes mainloop
		include("/system/lib/foot.lua")

	]]

	-- printh("create_process with env: "..pod(env))

	local proc_id = _create_process_from_code(str, get_short_prog_name(prog_name))

	
	if (not proc_id) then
		
		return nil
	end

--	printh("$ created process "..proc_id..": "..prog_name.." ppath:"..program_path)

	if (env_patch and env_patch.window_attribs and env_patch.window_attribs.pwc_output) then
		store("/ram/system/pop.pod", proc_id) -- present output process
	end

	return proc_id

end

-- manage process-level data: dispay, env

	-- hidden from userland program
	local _disp = nil
	local _target = nil

	-- default to display
	function set_draw_target(d)
		d = d or _disp

		--printh("setting draw target to:"..tostr(d))
		local ret = _target
		_target = d
		_set_draw_target(d)

		-- map to 0x60000 automatically? nope -- user should decide to do this / wrap set_draw_target()
		-- and in most cases, target is _disp and drawing straight to 0x10000 anyway.
		-- let window manager handle frame holding

		-- but.. want to poke(0x10000, 8) in terminal / when running on top of terminal.
		-- maybe "draw_target" /is/ "display". np if wm is holding frames.
		-- up to user to set_draw_target() before end of _draw()
		-- (or happens automatically in mainloop)

		if (d ~= nil) then
			memmap(0x10000, d)
		end

		return ret

	end

	function get_draw_target()
		return _target
	end

	-- used to have a set_display to match, but only need get_display(). (keep name though; display() feels too ambiguous)
	function get_display()
		return _disp
	end

	-- starting environment: none; overwritten by injected process code
	function env() return {} end

	---------------------------------------------------------------------------------------------------

	local first_set_window_call = true

	local function set_window_1(attribs)

		-- to do: shouldn't be needed by window manager itself (?)
		-- to what extent should the wm be considered a visual application that happens to be running in kernel?
		-- if (pid() <= 3) return

		attribs = attribs or {}


		-- on first call, observe attributes from env().window_attribs
		-- they **overwrite** any same key attributes passed to set_window
		-- (includes pwc_output set by window manager)

		if (first_set_window_call) then

			first_set_window_call = false
		
			if type(env().window_attribs) == "table" then
				for k,v in pairs(env().window_attribs) do
					attribs[k] = v
				end
			end

			-- set the program this window was created with (for workspace matching)

			attribs.prog = env().prog_name
			
			-- first call: decide on an initial window size so that can immediately create display

			-- default size: fullscreen (dimensions set below)
			if not attribs.tabbed and (not attribs.width or not attribs.height) then
				attribs.fullscreen = true
			end

			-- not fullscreen, tabbed or desktop, and (explicitly or implicitly) moveable -> assume regular moveable desktop window
			if (not attribs.fullscreen and not attribs.tabbed and not attribs.wallpaper and
				(attribs.moveable == nil or attribs.moveable == true)) 
			then
				if (attribs.has_frame  == nil) attribs.has_frame  = true
				if (attribs.moveable   == nil) attribs.moveable   = true
				if (attribs.resizeable == nil) attribs.resizeable = true
			end


			-- wallpaper has a default z of -1000
			if (attribs.wallpaper) then
				attribs.z = attribs.z or -1000 -- filenav is -999
			end


		end

		-- video mode implies fullscreen

		if (attribs.video_mode) then
			attribs.fullscreen = true
		end


		-- setting fullscreen implies a size and position

		if attribs.fullscreen then
			attribs.width = 480
			attribs.height = 270
			attribs.x = 0
			attribs.y = 0
		end

		-- setting tabbed implies a size and position  // but might be altered by wm

		if attribs.tabbed then
			attribs.fullscreen = nil
			attribs.width = 480
			attribs.height = 248+11
			attribs.x = 0
			attribs.y = 11
		end

		-- setting new display size
		if attribs.width and attribs.height then

			local scale = 1
			if (attribs.video_mode == 3) scale = 2 -- 240x135
			if (attribs.video_mode == 4) scale = 3 -- 160x90
			local new_display_w = attribs.width  / scale
			local new_display_h = attribs.height / scale


			local w,h = -1,-1
			if (get_display()) then
				w = get_display():width()
				h = get_display():height()
			end

			-- create new bitmap when display size changes
			if (w != new_display_w or h != new_display_h) then
				-- this used to call set_display(); moved inline as it should only ever happen here

				_disp = userdata("u8", new_display_w, new_display_h)
				memmap(0x10000, _disp)
				set_draw_target() -- reset target to display

				-- set display attributes in ram
				poke2(0x5478, new_display_w)
				poke2(0x547a, new_display_h)

				poke (0x547c, attribs.video_mode or 0)

				poke(0x547f, peek(0x547f) & ~0x2) -- safety: clear hold_frame bit
				-- 0x547d is blitting mask; keep previous value
			end
		end

		send_message(3, {event="set_window", attribs = attribs})

	end

	-- set preferred size; wm can still override
	function window(w, h, attribs)

		-- this function wrangles parameters;
		-- set_window_1 doesn't do any further transformation / validation on parameters

		if (type(w) == "table") then
			attribs = w
			w,h = nil,nil

			-- special case: adjust position by dx, dy
			-- discard other 
			if (attribs.dx or attribs.dy) then
				send_message(3, {event="move_window", dx=attribs.dx, dy=attribs.dy})
				return
			end

		end

		attribs = attribs or {}
		attribs.width = attribs.width or w
		attribs.height = attribs.height or h

		return set_window_1(attribs)
	end
	
------- standard library   -----  (see also api.lua for temporary api implementation for functions that should be rewritten in C)

--  deleteme
--	load_54 = load
--	loadstring = load
--	load = load_object -- to do: don't use load for anything -- too ambiguous and confusing! just "fetch" 


	-- to do: remove use of _get_system_global when these values are standardized
--[[
	local sys_global = {
		pm_proc_id = 2,
		wm_proc_id = 3,
		cart_path = "/ram/cart"
	}
	function _get_system_global(k)
		if (sys_global[k]) return sys_global[k]
		printh("**** _get_system_global failed for key: "..k)
	end
]]

	-- fullscreen videomode with no cursor
	function vid(mode)
		window{
			video_mode = mode,
			cursor = 0
		}
	end

	-- immediately close program & window
	function exit(exit_code)
		if (env().immortal) return
		
		--send_message(pid(), {event="halt"})
		send_message(2, {event="kill_process", proc_id=pid()})
		_halt() -- stop executing immediately
	end

	-- stop executing in a resumable way 
	-- use for debugging via terminal: stop when something of interest happens and then inspect state
	function stop(txt, ...)
		if (txt) print(txt, ...)

		send_message(pid(), {event="halt"}) -- same as pressing escape; goes to terminal
		yield() -- get out of terminal callback (only works if not inside a coroutine ** and doesn't resume at that point **)
	end

	-- any process can kill any other process!
	-- deleteme -- send a message to process manager instead. process manager might want to decline.
	--[[
	function kill_process(proc_id, exit_code)
		send_message(2, {event="kill_process", proc_id=proc_id, exit_code = exit_code})
	end
	]]

	-- 
	function get_clipboard()
		_req_clipboard_text()

		-- ** commented; can't support get_clipboard on web yet
		--flip() -- wait at least one frame (even on binary platforms -- just how it be)

		-- wait up to 10 frames for the browser to separately process ctrl-v (setting codo_textarea contents) 
		for i=1,10 do
			
			local ret = _get_clipboard_text()
			if (ret) then return ret end
			flip()
		end

		return nil -- could not fetch
	end

	function set_clipboard(...)
		return _set_clipboard_text(...)
	end

	-- generate metadata string in plain text pod format
	local function generate_meta_str(meta_p)

		-- use a copy so that can remove pod_format without sideffect
		local meta = unpod(pod(meta_p)) or {}

		local meta_str = "--[["

		if (meta.pod_format and type(meta.pod_format) == "string") then
			meta_str ..= "pod_format=\""..meta.pod_format.."\""
			meta.pod_format = nil -- don't write twice
		elseif (meta.pod_type and type(meta.pod_type) == "string") then
			meta_str ..= "pod_type=\""..meta.pod_type.."\""
			meta.pod_type = nil -- don't write twice
		else
			meta_str ..= "pod"
		end

		local meta_str1 = _pod(meta, 0x0) -- 0x0: metadata always plain text. want to read it!

		if (meta_str1 and #meta_str1 > 2) then
			meta_str1 = sub(meta_str1, 2, #meta_str1-1) -- remove {}
			meta_str ..= ","
			meta_str ..= meta_str1
		end

		meta_str..="]]"

		return meta_str

	end


	function pod(obj, flags, meta)

		-- safety: fail if there are multiple references to the same table
		-- to do: allow this but write a reference marker in C code? maybe don't need to support that!
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
			-- table is not a tree
			return nil, "error: multiple references to same table"
		end

		if (meta) then
			local meta_str = generate_meta_str(meta)
			return _pod(obj, flags, meta_str) -- new meaning of 3rd parameter!
		end

		return _pod(obj, flags)
	end

	
	local function fix_metadata_dates(result)
		if (result) then
			
			-- time string generation bug that happened 2023-10! (to do: fix files in /system)
			if (type(result.modified) == "string" and tonumber(result.modified:sub(6,7)) > 12) then
				result.modified = result.modified:sub(1,5).."10"..result.modified:sub(8)
			end
			if (type(result.created) == "string" and tonumber(result.created:sub(6,7)) > 12) then
				result.created = result.created:sub(1,5).."10"..result.created:sub(8)
			end

			-- use legacy value .stored if .modified was not set
			if (not result.modified) result.modified = result.stored

		end
	end



	-- fetch and store can be passed locations instead of filenames

	function fetch(location, do_yield, ...)
		local filename, hash_part = table.unpack(split(location, "#", false))

		-- anywhen: used for testing rollback (please don't use this for anything important yet!)
		-- fetch("anywhen://foo.txt@2024-04-05_13:02:27"
		-- to do: allow fetch("foo.txt@2024-04-05_13:02:27") -- shorthand for anywhen://..
		if (string.sub(location, 1, 10) == "anywhen://") then
			local ret, meta = _fetch_anywhen(filename:sub(10)) -- include second '/' to give absolute path 
			return ret, meta, hash_part
		end


		--[[
			remote fetches are logically the same as local ones -- they block the thread
			but.. can be put into a coroutine and polled
		]]
		if (string.sub(location, 1, 8) == "https://" or string.sub(location, 1, 7) == "http://" ) then
			-- blocking call: download

			-- printh("[fetch] calling _fetch_remote: "..filename)
			local job_id, err = _fetch_remote(filename, ...)
			-- printh("[fetch] job id: "..job_id)

			if (err) return nil, err

			local tt = time()

			while time() < tt + 10 do -- to do: configurable timeout.

				-- printh("[fetch] about to fetch result for job id "..job_id)

				local result, meta, hash_part, err = _fetch_remote_result(job_id)

				-- printh("[fetch] result: "..type(result))

				if (result or err) then
					--printh("[fetch remote] returned an obj type: "..type(result).."  // err: "..tostring(err))
					--printh("[fetch remote] err: "..pod(err))
					return result, meta, hash_part, err
				end

				flip(0x1)
				yield() -- allow pollable pattern from program.  to do: review cpu hogging

			end
			return nil, nil, nil, "timeout"

		else
			-- local file
			local ret, meta = _fetch_local(filename, do_yield, ...)
			fix_metadata_dates(meta)
			return ret, meta, hash_part  -- no error
		end
	end

	function mkdir(p)
		if (fstat(p)) return -- is already a file or directory
		local ret = _mkdir(p)
		store_metadata(p, {created = date(), modified = date()}) -- 0.1.0f: replaced stored with modified; not useful as a separate concept
		return ret
	end


	function store(location, obj, meta)

		-- treat web as read-only!
		if (string.sub(location, 1, 8) == "https://") then
			return nil
		end

		-- special case: can write raw .p64 / .p64.rom / .p64.png binary data out to host file without mounting it
		local ext = location:ext()

		if (type(obj) == "string" and (ext == "p64" or ext == "p64.rom" or ext == "p64.png")) then
			rm(location:path()) -- unmount existing cartridge // to do: be more efficient
			return _store_local(location, obj)
		end

		-- ignore location string
		local filename = split(location, "#", false)[1]
		
		-- grab old metadata
		local old_meta = fetch_metadata(filename)
		
		if (type(old_meta) == "table") then
			if (type(meta) == "table") then			
				-- merge with existing metadata.   // to do: how to remove an item?			
				for k,v in pairs(meta) do
					old_meta[k] = v
				end
			end
			meta = old_meta
		end

		if (type(meta) != "table") meta = {}
		if (not meta.created) meta.created = date()
		if (not meta.revision or type(meta.revision) ~= "number") meta.revision = -1
		meta.revision += 1   -- starts at 0
		meta.modified = date()

		-- use pod_format=="raw" if is just a string
		-- (_store_local()  will see this and use the host-friendly file format)

		if (type(obj) == "string") then
			meta.pod_format = "raw"
		else
			-- default pod format otherwise
			-- (remove pod_format="raw", otherwise the pod data will be read in as a string!)
			meta.pod_format = nil 
		end


		local meta_str = generate_meta_str(meta)

		-- /ram/system/settings.pod is special
		if (fullpath(filename) == "/ram/system/settings.pod") then
			-- printh("setting fullscreen: "..tostr(obj.fullscreen))
			_apply_system_settings(obj)
		end

		-- printh("storing meta_str: "..meta_str)

		local result, err_str = _store_local(filename, obj, meta_str)
		
		-- dev: assume no error for now! return stored metadata
		-- return meta -- 0.1.0f: removed; was for debugging
		return nil

	end

	
	
	function fetch_metadata(filename)
		local result = _fetch_metadata(fstat(filename) == "folder" and filename.."/.info.pod" or filename)
		fix_metadata_dates(result)
		return result
	end

	function store_metadata(filename, meta)

		local old_meta = fetch_metadata(filename)
		
		if (type(old_meta) == "table") then
			if (type(meta) == "table") then			
				-- merge with existing metadata.   // to do: how to remove an item? maybe can't! just recreate from scratch if really needed.
				for k,v in pairs(meta) do
					old_meta[k] = v
				end
			end
			meta = old_meta
		end

		if (type(meta) != "table") meta = {}
		meta.modified = date() -- 0.1.0f: was ".stored", but nicer just to have a single, more general "file was modified" value.


		local meta_str = generate_meta_str(meta)

		if (fstat(filename) == "folder") then
			-- directory
			-- printh("writing meta_str to directory: "..meta_str)
			local info_filename = filename.."/.info.pod" 
--			if fstat(info_filename) then
			if false then

				-- modify existing file metadata
				_store_metadata(info_filename, meta_str)
				
			else
				-- create new .info.pod file containing only metadata + content of nil
				_store_local(info_filename, nil, meta_str) 
			end
		else
			_store_metadata(filename, meta_str)
		end
	end


	local _printh = _printh
	local _tostring  = tostring
	function printh(str)
		_printh(string.format("[%03d] %s", pid(), _tostring(str)))
	end

	

	function print(str, x, y, col)

		if (y or (get_display() and not _is_terminal_command)) then
			return _print_p8scii(str, x, y, col)
		end

		-- when print_to_proc_id is not set, send to self (e.g. printing to terminal)
		send_message(env().print_to_proc_id or pid(), {event="print",content=tostr(str)})
		
	end


	sub = string.sub

	-- get filename extension
	-- include double extensions; .p64.png is treated differently from .png
	-- "" is also a legit extension distinct from no extension ("wut." vs "wut")

	function string:ext()
		local loc = split(self,"#",false)[1]
		-- max extension length: 16
		for i = 1,16 do
			if (string.sub(loc,-i,-i) == ".") then
				-- try to find double ext first e.g. .p8.png  but not .info.pod
				for j = i+1,16 do
					if (string.sub(loc,-j,-j) == "/") return string.sub(loc, -i + 1) -- path separator -> return just the single segment
					if (string.sub(loc,-j,-j) == "." and #loc > j) return string.sub(loc, -j + 1)
				end
				return string.sub(loc, -i + 1)
			end
		end
		return nil -- "no extension"
	end

	function string:path()
		return split(self,"#")[1]
	end

	function string:hloc()
		return split(self,"#")[2]
	end

	function string:basename()
		local segs = split(self:path(),"/")
		return segs[#segs]
	end

	function string:dirname()
		local segs = split(self:path(),"/")
		return self:sub(1,-#segs[#segs]-2)
	end

	-- PICO-8 style string indexing;  ("abcde")[2] --> "b"  
	-- to do: implement in lvm.c?
	local string_mt_index=getmetatable('').__index
	getmetatable('').__index = function(str,i) 
		return string_mt_index[i] or _strindex(str,i)
	end

--[[
	local string_mt = getmetatable("")

	setmetatable(string_mt.__index, {__index = function(a,b) return pod{a,b} end})
]]

--	setmetatable(string_mt.__index, {__index = function(a,b) return a end})

--[[
	function string:__index()
		return "zxc"
	end
]]

--	local string_mt = getmetatable("")
--	string_mt.__index.__index = function() return "#" end

--	setmetatable(getmetatable("").__index, {__index=function(s, i) return pod(i) end})

	--[[
		** experimental -- perhaps a bad idea **  

		//  goal: want a simple, transparent, commonly used path for including code

		include is similar to require() but searches:
			1. current path (libraries bundled with program)
			2. /system/lib  (common libraries -- dunno what that would be though! font should be standard)
				// maybe should use pico-8 style #include so can manage .p64.png packaging automatically
				// could just rewrite #include filename as include "filename" in preprocessor! 

		** "include" is a bad name -- included code has scope and can't read parent locals

		related reading: Lua Module Function Critiqued // old module system deprecated in 5.2 in favor of require()
			// avoids multiple module authors writing to the same global environment

			http://lua-users.org/wiki/LuaModuleFunctionCritiqued
			https://web.archive.org/web/20170703165506/https://lua-users.org/wiki/LuaModuleFunctionCritiqued

	]]

	function include(filename)
		local filename = fullpath(filename)
		local src = fetch(filename)

		if (type(src) ~= "string") then 
			notify("could not include "..filename)
			stop()
			return
		end

		local pwd0 = pwd()
		
		-- https://www.lua.org/manual/5.4/manual.html#pdf-load
		-- chunk name (for error reporting), mode ("t" for text only -- no binary chunk loading), _ENV upvalue
		-- @ is a special character that tells debugger the string is a filename
		local func,err = load(src, "@"..filename, "t", _ENV)

		-- syntax error while loading
		if (not func) then 
			-- printh("** syntax error in "..filename..": "..tostr(err))
			--notify("syntax error in "..filename.."\n"..tostr(err))
			send_message(3, {event="report_error", content = "*syntax error"})
			send_message(3, {event="report_error", content = tostr(err)})

			stop()
			return
		end

--[[
		-- method 1. run as a coroutine
		--local res, err = coresume(cocreate(func))

		-- method 2: pcall
		--local res, err = pcall(func)

		if (not res) then
			notify(debug.traceback())
			notify(err) -- will show the filename the runtime error ocurred in			
			--notify(":: runtime error in "..filename)
			stop()
		end
		return res, err
]]

		-- call directly; allows complete stacktrace -- runtime error can be handled in general case
		
		-- hrrm
		-- if (filename:sub(1,12) ~= "/system/lib/") cd(filename:dirname())
			func()
		--cd(pwd0)

		return true -- ok, no error including
	end
	
	-- only for holding reference
	local userdata_ref = {}
	local _current_map = nil

	function memmap(addr, a, offset, len)

		if (_map_ram(addr, a, offset, len)) then
			if (a) then
				userdata_ref[a] = a
				if (addr == 0x100000) _current_map = a
			end
		end

	end

	-- unmap by array
	-- removes all pages mapped to somewhere inside that array.
	-- ** this is the only way to free mapped userdata, even if there are no remaining mapped pages **

	function unmap(a)
		if (type(a) == "userdata") then
				-- remove c-side pointer references
			if _unmap_ram(a) then
				-- _unmap_ram refused to unmap because used in base ram
				return
			end
			
			 -- can release reference and be garbage collected 	
			userdata_ref[a] = nil              
		end

	end


--------------------------------------------------------------------------------------------------------------------------------
--    Sprite Registry
--------------------------------------------------------------------------------------------------------------------------------

	-- sprites are owned by head -- process can assume exists
	local _spr = {} 

	-- add or remove a sprite at index
	-- flags stored at 0xc000 (16k)
	function set_spr(index, s, flags_val)
		index &= 0x3fff
		_spr[index] = s    -- reference held by head
		_set_spr(index, s) -- notify process
		if (flags_val) poke(0xc000 + index, flags_val)
	end

	function get_spr(index)
		return _spr[flr(index) & 0x3fff]
	end


	function map(ud, b, ...)
		
		if (type(ud) == "userdata") then
			-- userdata is first parameter -- use that and set current map
			_draw_map(ud, b, ...)
		else
			-- pico-8 syntax
			_draw_map(_current_map, ud, b, ...)
		end
	end

	
	

--------------------------------------------------------------------------------------------------------------------------------
--    Undo
--------------------------------------------------------------------------------------------------------------------------------

function create_undo_stack(...)

	if (not UNDO) then
		include("/system/lib/undo.lua")
	end
	return UNDO:new(...)
end

--------------------------------------------------------------------------------------------------------------------------------
--    Theme
--------------------------------------------------------------------------------------------------------------------------------

local theme_dat = nil
local theme_t   = -1
function theme(which)

	-- reload up to 5 times a second 
	-- is a tiny file and in ram, so not worth introducing a push scheme. just poll
	-- to do: checking metadata / attributes to see if it has changed? not worth it ~ just reload!
	if (not theme_dat or time() > theme_t + 0.2) then
		theme_t = time()
		theme_dat = fetch"/ram/shared/theme.pod"
		if (not theme_dat) then
			local sdat = fetch"/appdata/system/settings.pod"
			if (not sdat) sdat = fetch"/system/misc/default_settings.pod"
			if (sdat and sdat.theme) theme_dat = fetch(sdat.theme) -- if there is a theme file set in settings, use that
			if (not theme_dat) theme_dat = fetch"/appdata/system/theme.pod" or fetch"/system/themes/classic.theme"
			store("/ram/shared/theme.pod", theme_dat)
		end
	end

	return theme_dat[which]
end


--------------------------------------------------------------------------------------------------------------------------------
--    Coroutines
--------------------------------------------------------------------------------------------------------------------------------


yield = coroutine.yield
cocreate = coroutine.create
costatus = coroutine.status

local _coresume = coroutine.resume -- used internally

-- move to local; only used here
local _yielded_to_escape_slice = __yielded_to_escape_slice
__yielded_to_escape_slice = nil

--[[

	coresume wrapper needed to preserve and restore call stack
	when interuppting program due to cpu / memory limits

]]

function coresume(c,...)
	
	_yielded_to_escape_slice(0)
	local r0,r1 =_coresume(c,...)
	--printh("coresume() -> _yielded_to_escape_slice():"..tostr(_yielded_to_escape_slice()))
	while (_yielded_to_escape_slice() and costatus(c) == "suspended") do
		_yielded_to_escape_slice(0)
		r0,r1 = _coresume(c,...)
	end
	_yielded_to_escape_slice(0)
	return r0,r1
end


--------------------------------------------------------------------------------------------------------------------------------

--[[
	
	notify("syntax error: ...", "error")
	-> shows up in /ram/log/error, as a tab in infobar (shown in code editor workspace)
	
	can also use logger.p64 to view / manage logs
	how to do realtime feed with atomic file access? perhaps via messages to logger? [sent by program manager]

]]
function notify(msg_str)

	-- notify user and add to infobar history
	send_message(3, {event="user_notification", content = msg_str})

	-- logged by window manager
	-- send_message(3, {event="log", content = msg_str})
	
	-- printh("@notify: "..msg_str.."\n")
end



-- notifications

init_runtime_state()


end



