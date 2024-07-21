--[[pod_format="raw",created="2024-03-12 18:17:15",modified="2024-03-12 18:18:07",revision=1]]
--[[

	wrangle.lua

	not designed to be customisible; aim to take care of 90% of cases with a minimal replacement for boilerplate.
	to customise: copy and modify (internals will not change [much] after 0.1)

	wrangle_working_file(save_state, load_state, untitled_filename)

	user supplies two callbacks, similar to create_undo_stack():

		save_state()          -- should return data (and optionally metadata)
		load_state(dat, meta) -- takes data and restores program state

]]


local current_filename

-- last known metadata on disk for a given filename
-- can use to check if contents of file has changed due to another process
local last_known_filename  = nil
local last_known_meta      = nil

-- set when contents is found to be stale due to external changes
-- ( --> stop auto-saving)
local stale_filename       = nil


function pwf()
	return current_filename
end





local function update_menu_items()
	
	-- don't need -- can do file open, CTRL-I to get file info
	-- also: can hover over tab to see filename
	-- ** maybe: right click on tab gives a different tab-specific menu
	--    at the moment it is only really useful for "close tab", and maybe confusing that there is the same menu twice
--[[
	menuitem{
		id = "file_info",
		label = "\^:1f3171414141417f About "..current_filename:basename(),
		action = function() create_process("/system/apps/about.p64", {argv={current_filename}, window_attribs={workspace = "current"}}) end
	}
	-- \^:1c367f7777361c00  -- i in circle
]]


	--** fundamental problem (maybe wrangler could tackle):
	--** when edit metadata, doesn't feel like anything changes on disk until save it
	--** But then Save As, what happens? Should wrangler store current metadata and pass it on?
--[[
	menuitem{
		id = "file_info",
		label = "\^:1c367f7777361c00 File Metadata",
		action = function() create_process("/system/apps/about.p64", {argv={current_filename}, window_attribs={workspace = "current"}}) end
	}
]]

	menuitem{
		id = "open_file",
		label = "\^:7f4141417f616500 Open File",
		shortcut = "CTRL-O",
		action = function()
			local segs = split(current_filename,"/",false)
			local path = string.sub(current_filename, 1, -#segs[#segs] - 2) -- same folder as current file
			--create_process("/system/apps/filenav.p64", {path = path, window_attribs= {workspace = "current", autoclose=true}})

			printh("Open File // env().prog_name: "..env().prog_name)
			-- can assume when program is terminal, co-running /ram/cart and should use that to open the file (useful for developing tools that use file wrangler)
			local open_with = env().prog_name

			-- when opening with terminal, can assume co-running ram/cart
			--> use /ram/cart to run it.   //  allows wrangling files from load'ed cartridge; useful for tool dev
			if (open_with == "/system/apps/terminal.lua") then
				open_with = "/ram/cart/main.lua"
			end

			create_process("/system/apps/filenav.p64", {path = path, open_with = open_with, window_attribs= {workspace = "current", autoclose=true}})
		end
	}

	-- save file doesn't go through filenav -- can send straight to even handler installed by wrangle.lua
	if (current_filename:sub(1,10) == "/ram/cart/") then
		menuitem{
			id = "save_file",
			label = "\f6\^:7f4141417f616500 Save File (auto)",
			shortcut = "CTRL-S", -- ctrl-s is handled by window manager
			action = function() send_message(pid(), {event = "save_file"}) return true end -- still save just in case!
		}
	else
		menuitem{
			id = "save_file",
			label = "\^:7f4141417f616500 Save File",
			shortcut = "CTRL-S", -- ctrl-s is handled by window manager
			action = function() send_message(pid(), {event = "save_file"}) end
		}
	end

	menuitem{
		id = "save_file_as",
		label = "\^:7f4141417f616500 Save File As",

		action = function() 
			local segs = split(current_filename,"/",false)
			local path = string.sub(current_filename, 1, -#segs[#segs] - 2) -- same folder as current file
			create_process("/system/apps/filenav.p64", 
				{path=path, intention="save_file_as", use_ext = current_filename:ext(), window_attribs={workspace = "current", autoclose=true}})
		end
	}

end




local function set_current_filename(fn)
	fn = fullpath(fn) -- nil for bad filenames
	if (not fn) return false
	current_filename = fn
	stale_filename = nil
	window{
		title = current_filename:basename(),
		location = current_filename, 
		unique_location = true
	}
	update_menu_items() -- (auto) shown on /ram/cart files
	return true -- could set
end




function wrangle_working_file(save_state, load_state, untitled_filename, get_hlocation, set_hlocation)

	local w = {
		save = function(w)
			-- printh("## save "..current_filename)
			local content, meta = save_state()
			if (not meta) meta = {}

			local meta1 = store(current_filename, content, meta)

			-- use callback to modify current_filename with new location suffix (e.g. foo.lua#23 line number changes)

			if (get_hlocation) then
				w.update_hloc(w, get_hlocation())
			end


			last_known_filename = current_filename
			last_known_meta = unpod(pod(meta1))

		end,

		load = function(w)
			local content, meta, hloc = fetch(current_filename)

			load_state(content, meta)
			if (set_hlocation) set_hlocation(hloc)

			last_known_filename = current_filename
			last_known_meta = unpod(pod(meta))

			return content, meta
		end,


		update_hloc = function(w, newloc)

			newloc = tostring(newloc) -- could be a number
			if (type(newloc) ~= "string") return

			local old_filename = current_filename
			current_filename = split(current_filename, "#", false)[1].."#"..newloc
			if (current_filename ~= old_filename) then
				-- tell wm new location
				--printh("telling wm new location: "..current_filename)
				window{location = current_filename}

				if (set_hlocation) set_hlocation(newloc) -- callback that e.g. changes cursor position
			end

		end


	}

	untitled_filename = untitled_filename or "untitled.pod"
	
	
	-- derive current_file
	
	cd(env().path)

	current_filename = (env().argv and env().argv[1]) or untitled_filename
	current_filename = fullpath(current_filename)


	-- load (or create) current working file
	-- to do: what happens if it is a folder?
	if (fstat(current_filename)) then
		-- to do: check error
		w:load()
	else
		w:load() -- initialise state
		w:save() -- create
	end

	
	-- tell window manager working file
	-- ** [currently] needs to happen after creating window **

	window{
		title = current_filename:basename(),
		location = current_filename, 
		unique_location = true
	}



	------ install events ------

	-- invoked directly from app menu, and by wm when about to run / save cartridge
	on_event("save_file", function(msg)
		-- can optionally 
		if (msg.filename) then
			current_filename = msg.filename
		end

		-- refuse to save over external changes. to do: nicer way to handle this
		if (stale_filename == current_filename) then
			notify(stale_filename..": skipped saving over external changes")
			return
		end

		w:save()
		
		-- show message only when NOT auto-saving /ram/cart files
		if (sub(current_filename, 1, 10) ~= "/ram/cart/") then

			if (fullpath(current_filename):sub(1,8) == "/system/") then
				notify("saved "..current_filename.." ** warning: changes to /system/ not written to disk **")
			else
				notify("saved "..current_filename)

			end
		end

	end)

	-- invoked by filenav intention
	on_event("open_file", function(msg)
		set_current_filename(msg.filename)
		w:load()
	end)

	on_event("jump_to_hloc", function(msg)
		local newloc_str = msg.hloc and "#"..msg.hloc or ""

		if (w.set_hlocation) w:set_hlocation(newloc)
		local old_filename = current_filename
		current_filename = split(current_filename, "#", false)[1]..newloc_str
		if (current_filename ~= old_filename) then
			-- tell wm new location
--			printh("request setting window location: "..current_filename)
			window{location = current_filename}
		end

	end)

	-- invoked by filenav intention
	on_event("save_file_as", function(msg)
		
		if (set_current_filename(msg.filename)) then

			-- 0.1.0c: automatically add extension if none is given
			if (not current_filename:ext() and untitled_filename:ext()) then
				set_current_filename(current_filename.."."..untitled_filename:ext())
			end

			w:save()			
			notify("saved as "..current_filename) -- show message even if cart file
		end
		
	end)


	-- autosave cart file when lose focus

	on_event("lost_focus", function(msg)
		if (sub(current_filename, 1, 10) == "/ram/cart/") then
			w:save()
		end
	end)

	
	--[[
		when gaining focus, check that file being edited has a newer version on disk
		if so, warn that external changes are detected (user might want to reload)
	]]
	on_event("gained_focus", function(msg)
	
		if split(last_known_filename,"#",false)[1] == split(current_filename,"#",false)[1] then
			local md1 = fetch_metadata(current_filename)
			if (md1) then
--				printh("revision on disk:"..(md1.revision or -1).."   last_known_meta: "..pod(last_known_meta))
				if (last_known_meta and last_known_meta.revision < md1.revision) then
					-- to do: how to disable autosave / 
					stale_filename = current_filename
					--notify("warning: external changes detected -- this version is stale")
					notify("warning: external changes detected")
				end
			end
		end
	end)

	update_menu_items()

	return w
end






