--[[pod_format="raw",author="zep",created="2023-10-07 14:33:59",icon=userdata("u8",16,16,"00000001010101010101010101000000000001070707070707070707070100000001070d0d0d0d0d0d0d0d0d0d07010001070d0d0d0d0d0d0d0d0d0d0d0d070101070d0d0d0d07070d0d0d0d0d0d070101070d0d0d0d0d07070d0d0d0d0d070101070d0d0d0d0d0d07070d0d0d0d070101070d0d0d0d0d0d07070d0d0d0d070101070d0d0d0d0d07070d0d0d0d0d070101070d0d0d0d07070d0d0d0d0d0d070101070d0d0d0d0d0d0d0d0d0d0d0d07010106070d0d0d0d0d0d0d0d0d0d07060101060607070707070707070707060601000106060606060606060606060601000000010606060606060606060601000000000001010101010101010101000000"),modified="2024-07-19 07:59:01",notes="",revision=152,stored="2024-03-09 10:31:21",title="Terminal",version=""]]
--[[

	terminal.lua
	(c) Lexaloffle Games LLP

	-- ** terminal is also an application launcher. manages cproj / decides permissions **

	-- to consider: line entry in terminal can be a bitmap


]]


-- set preferred window size unless about to corun a program (which should be the one to create the window w/ size, icon)
-- this window size might be overwritten by env().window_attribs
if (not env().corun_program) then
	window{
		width=320,
		height=160,
		icon = userdata"[gfx]0907000707000000070000777777777770000077770000077770000077777777777[/gfx]"
	}
end



if (pwd() == "/system/apps") cd("/") -- start in root instead of location of terminal.lua


-- print to self, not to terminal that launched it!
-- env().print_to_proc_id = pid()


--- *** NO GLOBALS ***   --   don't want to collide with co-running program

local cmd=""

--local line={"picotron 0.0.1","(c) lexaloffle games 2020~2022 ",""}
local line={}
local lineh={}
local history={}
local history_pos = 1
local scroll_y = 0
local char_h = peek(0x4002)
local char_w = peek(0x4000)
local cursor_pos = 0
local disp_w, disp_h = 0, 0
local back_page = userdata("u8", 480, 270)
local last_total_text_h = 0
local max_lines = 64 -- to do: increase w/ more efficient rendering (cache variable line offsets)
local left_margin = 2

local terminal_draw 
local terminal_update

local cproj_draw, cproj_update


-- to do: perhaps cproj can be any program; -> should be "corunning_prog"
-- (or two separate concepts if need)
local running_cproj = false
local last_pauseable = -1

local _has_focus = true
on_event("gained_focus", function() _has_focus = true end)
on_event("lost_focus", function() _has_focus = false end)


--corunning coroutines

local coco = {}


function _init()

	-- don't pause fullscreen terminal when not corunning pwc
	if (not env().corun_program) then
		window{pauseable = false}
	end

	-- add_line("picotron terminal // "..flr(stat(0)).." bytes used")

end

-- to do: string format for custom prompts?
-- for now, create a return value so that can use sedit
local function get_prompt()
	local result = "\f6"..pwd().."\f7> "
	return result -- custom prompt goes here
end


local function run_cproj_callback(func, label)
	if (type(func) ~= "function") then return end

	-- run as a coroutine (separate lua_State) so that errors don't bring terminal itself down

	coco[func] = coco[func] or cocreate(func)

	local res, err = coresume(coco[func])
	

	--if (res == 3) running_cproj = false -- 

	if (err) then
		set_draw_target() -- prevent drawing error to back page or whatever the program is drawing to
		add_line("\feRUNTIME ERROR: [callback] "..tostr(label))
		add_line(err)

		send_message(3, {event="report_error", content = "*runtime error"})
		send_message(3, {event="report_error", content = err})
		send_message(3, {event="report_error", content = debug.traceback()})

		running_cproj = false
		window{pauseable = false}

		-- nothing haltable (esc should go straight back into code editor)
		send_message(3, {event="set_haltable_proc_id", haltable_proc_id = nil})

	end

	if (costatus(coco[func]) == "dead") coco[func] = nil


end




local function suspend_cproj()

	if (not running_cproj) return

	-- kill all audio channels
	note()

	-- copy whatever is on screen
	blit(get_display(), back_page)
	
	-- consume keypresses
	readtext(true)

	running_cproj = false

	scroll_y = 0
--	show_last_line()

	-- back to last directory that user chose
	local pwd = fetch("/ram/system/pwd.pod")
	if (pwd) then cd(pwd) end

	-- terminal is not pauseable unless running something (to do: lose this state when resuming)
	window{pauseable = false}

	-- stop playing any sound  // to do: need to pause mixer so that it is resumable 
	-- play_note(0,-1,0,0,0, 0)

end



local function get_file_extension(s)

	if (type(s) ~= "string") return nil
	return s:ext()

end


local function try_multiple_extensions(prog_name)
--	printh(" - - - - trying multiple entensions for: "..tostr(prog_name))

	if (type(prog_name) ~= "string") return nil

	local res =
		--(fstat(prog_name) and prog_name and get_file_extension(prog_name)) or  --  needs extension because don't want regular folder to match
		(fstat(prog_name) and prog_name:ext() and prog_name) or  --  needs extension because don't want regular folder to match
		(fstat(prog_name..".lua") and prog_name..".lua") or
		(fstat(prog_name..".p64") and prog_name..".p64") or -- only .p64 carts can be run without specifying extension (would be overkill; reduce ambiguity)
		nil
	--printh(" - - - - - - - - -")
	return res

end


--[[
	find a program 

	look in /system/util, /system/apps, /appdata/system/util and finally current path

	to do: some kind of customisable $PATH? would be nice to avoid the need for that
]]
local function resolve_program_path(prog_name)

	if (not prog_name) return nil

	local prog_name_0 = prog_name

	-- /appdata/system/util/ can be used to extend built-in apps (same pattern as other collections)
	-- update: not true, other collections (wallpapers) are replaced rather than extended by /appdata

	return
		try_multiple_extensions("/system/util/"..prog_name) or
		try_multiple_extensions("/system/apps/"..prog_name) or
		try_multiple_extensions("/appdata/system/util/"..prog_name) or
		try_multiple_extensions(prog_name) -- 0.1.0c: moved last 

end


-- assume is cproj for now
local function run_program_inside_terminal(prog_name)

	if (not prog_name) return

	local prog_str = fetch(prog_name)

	if (not prog_str) then
		printh("** could not run "..prog_name.." **")
		return
	end

	coco = {}

	terminal_draw = _draw
	terminal_update = _update

	_draw,_update,_init = nil,nil,nil


	-- to do: need to preprocess in the same way as create_process()
	-- but don't need to inject libraries / head / mainloop (use terminal's and manage mainloop from terminal)
	local f, err = load(prog_str, "@"..prog_name, "t", _ENV)


--	printh(":: run_program_inside_terminal: "..tostr(prog_name))

	
	if (f) then

		run_cproj_callback(f, prog_name) -- to do: fix runtime error causes message written to back page
		--run_cproj_callback(_init, "_init") -- gets run from foot

		-- record callbacks and revert to terminal ones
		cproj_draw = _draw
		cproj_update = _update

		running_cproj = true

	else
		send_message(3, {event="report_error", content = "*syntax error"})
		send_message(3, {event="report_error", content = tostr(err)})

		--add_line("\fesyntax error")
		add_line("\fe"..err)
		printh(err)
		suspend_cproj()
	end

	_draw = terminal_draw
	_update = terminal_update



end


--[[

	run_program_in_new_process()

	initial pwd is always program path (even for stand-alone .lua scripts), so if planning to run
	from a different directory (e.g. /system/util), program needs to start with cd(env().path)

]]
local function run_program_in_new_process(prog_name, argv)

	local proc_id = create_process(
		prog_name, 
		{
			print_to_proc_id = pid(),  -- tell new process where to print to               
			argv = argv,
			path = pwd(), -- used by commandline programs -- cd(env().path)
			window_attribs = {show_in_workspace = true}
		}
	)

end


--[[

	run_terminal_command

	try in order:

		1. built-in commands (cd / exit etc) that can not be replaced by lua or program names
		2. programs          // can't have spaces in them
		3. lua command

	note: running a program might be in the form of a legal lua statement, but if the program
		doesn't exist, then the lua statement is never executed. e.g.

		ls = 3 -- runs list with args {"=","3"}
		xx = 3 -- assigns 3 to xx (assuming there is no program called xx)

]]

local function run_terminal_command(cmd)

	local prog_name = resolve_program_path(split(cmd," ",false)[1])

--	printh("run_terminal_command program: "..tostr(prog_name))

	local argv = split(cmd," ",false)

	-- 0-based so that 1 is first argument!
	for i=1,#argv+1 do
		argv[i-1] = argv[i]
	end

	-----
	
	if (argv[0] == "cd") then

		local result = cd(argv[1])
		if (result) then add_line(result) end -- result is an error message

	elseif (cmd == "exit") then

		exit(0)
		
	elseif (cmd == "cls") then

		set_draw_target(back_page)
		cls()
		set_draw_target()
		scroll_y = last_total_text_h

	elseif (cmd == "reset") then

		reset()

	elseif (cmd == "resume") then

		running_cproj = true
		send_message(3, {event="set_haltable_proc_id", haltable_proc_id = pid()})

	elseif (prog_name) then

		run_program_in_new_process(prog_name, argv) -- could do filename expansion etc. for arguments

	else
		-- last: try lua

		local f, err = load(cmd, nil, "t", _ENV)

		if (f) then
		
			-- run loaded lua as a coroutine
			local cor = cocreate(f)

			repeat
				set_draw_target(back_page)
				_is_terminal_command = true -- temporary hack so that print() goes to terminal. e.g. pset(100,100,8)?pget(100,100)

				local res,err = coresume(cor)
				
				set_draw_target() 
				_is_terminal_command = false
				
				if (err) then
					add_line("\feRUNTIME ERROR")
					add_line(err)
					
				end
			until (costatus ~= "running")
		else

			-- try to differenciate between syntax error /command not found

			local near_msg = "syntax error near"
			if (near_msg == sub(err, 5, 5 + #near_msg - 1)) then
				-- caused by e.g.: "foo" or "foo -a" or "foo a.png" when foo doesn't resolve to a program
				add_line "command not found"
			else
				add_line(err)
			end

		end

	end

end


-- scroll down only if needed
local function show_last_line()

	-- need to print same as will be printed so that wrapping behaves the same

	local hh = 0
	for i=1,#lineh do
		hh += lineh[i]
	end
	last_total_text_h = hh

--	last_total_text_h = #line * char_h -- assumes constant line height

	scroll_y = mid(scroll_y, last_total_text_h - disp_h + 18, last_total_text_h + char_h - 18)

end



local function clamp_scroll()

	local x, y = 0, 0
	for i=1,#line do
		x, y = print(line[i], 1000, y, 7)
	end
	last_total_text_h = y

	scroll_y = mid(0, scroll_y, last_total_text_h - (disp_h - 10 - char_h))
end



--local  -- to do: where is this being called from?
function add_line(s)
	s = tostr(s)
	if (not s) then return end

	if (#line > max_lines) then
		deli(line, 1)		
		deli(lineh, 1)
	end
	
	local xx,yy = print(s, 0, 1000, 7)
	add(line,  s)
	add(lineh, (yy or 1012) - 1000)

	show_last_line()
end


-- ** incredibly inefficient! to do: need to replace with string matching
local function find_common_prefix(s0, s1)

	if (type(s0) ~= "string") then return nil end
	if (type(s1) ~= "string") then return nil end

	if (s0 == s1) then return s0 end

	local len = 0
	while(sub(s0,1,len+1) == sub(s1,1,len+1)) do
		len = len + 1
		--printh(len)
	end

	return sub(s0,1,len)
end

--[[
	
	tab_complete_filename
	
]]
local function tab_complete_filename()

	if (cmd == "") then return end

	-- get string
	local args = split(cmd, " \"", false)  -- also split on " to allow tab-completing filenames inside strings
	local prefix = args[#args] or ""

	-- construct path prefix  -- everything (canonical path) except the filename
	local prefix = fullpath(prefix)
	if (not prefix) return -- bad path
	local pathseg = split(prefix,"/",false)
	local path_part = ""
	for i=1,#pathseg-1 do
		path_part = path_part .. "/" .. pathseg[i]
	end
	if (path_part == "") then path_part = "/" end -- canonical filename special case

	prefix = (pathseg and pathseg[#pathseg]) or "/"


	-- printh("@@@ path part: "..path_part.." pwd:"..pwd())
	local files = ls(path_part)

	if (not files) return

	-- find matches

	local segment = nil
	local matches = 0
	local single_filename = nil

	for i=1,#files do
		--printh(prefix.." :: "..files[i])
		if (sub(files[i], 1, #prefix) == prefix) then
			matches = matches + 1
			local candidate = sub(files[i], #prefix + 1) -- remainder

			-- set segment to starting sequence common to candidate and segment
			segment = segment and find_common_prefix(candidate, segment) or candidate
			single_filename = path_part.."/"..files[i] -- used when single match is found
		end
	end

	if (segment) then
		cmd = cmd .. segment
		cursor_pos = cursor_pos + #segment
	end

	-- show files if >= 2
	if (matches > 1) then
		add_line("-- "..matches.." matching files --")
		for i=1,#files do
			if (sub(files[i], 1, #prefix) == prefix) then
				add_line(files[i])
			end
		end
	elseif single_filename and fstat(single_filename) == "folder" then
		-- trailing slash when a single match is a folder
		-- for folders with an extension, need to already match the full name;
		--> press tab once for foo.p64 and once more for foo.p64/)
		-- the vast majority of the time, user wants to refer to the cart itself
		if not single_filename:ext() or prefix == sub(cmd,-#prefix) 
		then
			cmd ..= "/"
			cursor_pos += 1
		end
	end

end


local tv_frames = 
{	[0] =
	userdata"[gfx]0907000707000000070000777777777770000077770070077770000077777777777[/gfx]",
	userdata"[gfx]0907000707000000070000777777777770070077770707077770070077777777777[/gfx]",
	userdata"[gfx]0907000707000000070000777777777770707077770000077770707077777777777[/gfx]",
}

function _update()

	-- app is pauseable when and only when running_cproj is true and fullscreen
	-- deleteme -- wrong; want to be able to disable pausing from fullscreen app corunning in terminal
--[[
	if (get_display()) then
		local w,h = get_display():attribs()
		local pauseable1 = running_cproj and w == 480 and h == 270
		if (last_pauseable ~= pauseable1) then
			last_pauseable = pauseable1
			window{pauseable = last_pauseable}
		end
	end
]]
	if (running_cproj and not cproj_update and not cproj_draw) then
		suspend_cproj()
	end

	-- while co-running program, use that update instead 
	if (running_cproj) then
		run_cproj_callback(cproj_update, "_update")
--		window{ icon = tv_frames[((t()*10)\1)%3] }
		return
	end


	if (key("ctrl")) then

		if keyp("l") then
			set_draw_target(back_page)
			cls()
			set_draw_target()
			scroll_y = last_total_text_h + 5
		end

		if keyp("v") then

			local str = get_clipboard()
			cmd = sub(cmd, 1, cursor_pos) .. str .. sub(cmd, cursor_pos+1)
			cursor_pos = cursor_pos + #str

		end

		if keyp("c") then

			set_clipboard(cmd)
			
		end

		if keyp("x") then

			set_clipboard(cmd)
			cmd = ""
			cursor_pos = 0
			
		end

		if (keyp("e")) cursor_pos = #cmd

		-- clear text intput queue; don't let anything else pass through
		-- readtext(true) -- 0.1.0f: wrong! ctrl sometimes used for text entry (altgr), and anyway ctrl-* shouldn't ever produce textinput event
	end


	while (peektext()) do
		local k = readtext()

		-- insert at cursor

		cmd = sub(cmd, 1, cursor_pos) .. k .. sub(cmd, cursor_pos+1)

		cursor_pos = cursor_pos + 1
	end

	if (keyp("tab")) then
		tab_complete_filename();
	end

	if (keyp("up")) then
		history[history_pos] = cmd
		history_pos = mid(1, history_pos-1, #history	)
		cmd = history[history_pos]
		cursor_pos = #cmd
	end

	if (keyp("down")) then
		history[history_pos] = cmd
		history_pos = mid(1, history_pos+1, #history)
		cmd = history[history_pos]
		cursor_pos = #cmd
	end

	if (keyp("left")) then
		cursor_pos = mid(0, cursor_pos - 1, #cmd)
	end

	if (keyp("right")) then
		cursor_pos = mid(0, cursor_pos + 1, #cmd)
	end

	if (keyp("home") or (key("ctrl") and keyp("a"))) cursor_pos = 0
	if (keyp("end")) cursor_pos = #cmd


	if (keyp("enter")) then

		add_line(get_prompt()..cmd)

		-- execute the command

		run_terminal_command(cmd)
		show_last_line()


		if (history[#history] == "") then 
			history[#history] = cmd
		else
			add(history, cmd)
			store("/ram/system/history.pod", history)
			store("/ram/system/pwd.pod", pwd()) 
		end

		history_pos = #history+1

		
		cmd = ""
		cursor_pos = #cmd -- cursor at end of command

	end

	if (keyp("backspace") and #cmd > 0) then
		cmd = sub(cmd, 1, max(0,cursor_pos-1))..sub(cmd, cursor_pos+1)
		cursor_pos = mid(0, cursor_pos - 1, #cmd)
	end

	if (keyp("delete") or (key("ctrl") and keyp("d"))) then
		cmd = sub(cmd, 1, max(0,cursor_pos))..sub(cmd, cursor_pos+2)
	end


end


function _draw()

	local disp = get_display()
	disp_w, disp_h = disp:width(), disp:height()

--	printh("terminal draw "..pod{disp_w, disp_h})

	if (running_cproj) then
		run_cproj_callback(cproj_draw, "_draw")
	else
		camera()
		clip()
	end

	--set_draw_target() -- commented to make debugging easier

	if (not running_cproj) then
		cls()
		blit(back_page, nil, 0, 0, 0, 0, 480, 270)
	end


	-- experiment: run painto / dots3d in terminal
--[[
	if (running_proc_id) then
		_blit_process_video(running_proc_id, 0, 0)
	end
]]


	--scroll_y = mid(0, scroll_y, #line * char_h - disp_h)

	

	--printh("disp_h: "..disp_h.." scroll_y: "..scroll_y.." max: "..(#line * char_h - disp_h))

	local function draw_text_masked(str, x, y, col)

		-- to do: how to allow colour codes?

		for yy=y-1,y+1 do
 			for xx=x-1,x+1 do
				print(str,xx, yy, 32)
			end
		end

		return print(str, x, y, col)
	end

	if (not running_cproj) then
		
		local x = left_margin
		local y = 7 - scroll_y

		local y0 = y

		-- to do: could cache wrapped strings
		-- and/or add a picotron-specific p8scii address for rhs wrap
		--local wrap_prefix = "\006r"..chr(ord("a") + max(6, disp_w \ 4 - 10))
		local wrap_prefix = ""
		
		poke(0x5f36, (@0x5f36) | 0x80) -- turn on wrap

		for i=1,#line do
			_, y = print(line[i], x, y, 7)
		end

		last_total_text_h = y - y0

		-- poke(0x5f36, (@0x5f36) | 0x80) -- turn on wrap

		camera()
		print(wrap_prefix..get_prompt()..cmd.."\0", x, y, 7)

		print(wrap_prefix..get_prompt()..sub(cmd,1,cursor_pos).."\0", x, y, 7)

		local cx, cy = peek4(0x54f0, 2)
		if (cx > disp_w - peek(0x4000)) cx,cy = peek4(0x54f8), cy + peek(0x4002) -- where next character is (probably) going to be after warpping

		-- show cursor when window is active
		if (_has_focus) then
			if (time()%1 < .5) then
				rectfill(cx, cy, cx+char_w-1, cy+char_h-4, 14)
			end
		end

	end

end

on_event("print", function(msg)


	add_line(msg.content)	

end)



-- window manager can tell guest program to halt
-- (usually by pressing escape)
on_event("halt", function(msg)
	if (running_cproj) then
		suspend_cproj()
		
	end
end)



scroll_y = 0

-- run e.g. pwc output
if (env().corun_program) then
	run_program_inside_terminal(env().corun_program)
end

-- happens when open terminal with ctrl-r
-- or when terminal window is recreated (because died due to out of ram)
if (env().reload_history) then

	local history1 = fetch("/ram/system/history.pod")
	if (type(history1) == "table") history = history1
	history_pos = #history + 1

	scroll_y = 0
end


-- process events like this because corunning program might have own handlers
-- (only one handler per event -- see event.lua)
-- update: have multiple events per subscriber now; can keep _subscribe_to_events out of userspace (extraneous)
--[[
subscribe_to_events(function(msg)

	-- ignore all events while running cproj
	if (running_cproj) then return end

	if (msg.event == "mousewheel") then
		scroll_y = scroll_y - msg.wheel_y * char_h * 2
	end

end)

]]

on_event("mousewheel", function(msg)
	scroll_y = scroll_y - msg.wheel_y * char_h * 2
end)


on_event("reload_src", function(msg)

	-- security: only accept from window manager
	if (msg._from ~= 3) then
		return
	end

	local prog_name = msg.working_file -- env().corun_program
	local prog_str = fetch(prog_name)

	local f = load(prog_str, "@"..prog_name, "t", _ENV)

	if (f) then
		f()
	else
		-- to do: how to return error?
	end


end)


on_event("resize", function(msg)
	show_last_line()
end)
