--[[

	Picotron Window Manager
	(c) Lexaloffle Games LLP

	Warning: this is a WIP -- a lot of internals are experimental and/or will change

]]


include("/system/wm/toolbar.lua")
include("/system/wm/infobar.lua")
include("/system/wm/sparkles.lua")

local default_cursor_gfx = userdata("[gfx]10100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000001710000000000000177100000000000017771000000000001777710000000000177110000000000001171000000000000000000000000000000000000[/gfx]")


local bar_h = 12 -- same as toolbar.lua. how to sync? global data?
local tooltray_default_h = 80

local mx, my, mb, mdx, mdy

local head_gui = nil

local workspace = {} -- desktop workspace
local ws_gui = nil   -- current workspace
local tooltray_gui = nil   -- global tooltray gui
local tooltray_active_window = nil -- set to a tooltray window when has focus
local workspace_index = 1
local last_desktop_workspace = nil
local last_fullscreen_workspace = nil
local toolbar_y        = 0
local toolbar_y_target = 0
local infobar_y        = 270 --270-11
local infobar_y_target = infobar_y
local held_frames = 0

local sdat = fetch"/appdata/system/settings.pod" or {}


function show_reported_error() -- happens when error is reported
	open_infobar()
	infobar_y_target = 200 -- not too high, want to see code
end


local last_input_activity_t = 0

-- store some things by process so that they can be manipulated before window is created
local proc_icon = {}
local proc_menu = {}

local char_w = peek(0x5600)

local prev_frame = nil

local last_mx, last_my, last_mb


function generate_head_gui()

--	printh("generate_infobar_gui "..time())
	
	head_gui = create_gui{
		x = 0, y = 0, 
		width = 480, height = 270
	}

--[[
	-- debug
	function head_gui:draw()
		cls(9)
		camera() clip()
		rectfill(0,0,1000,1000,8)
		rectfill(0,0,1000,30,10)
		for i=1,#head_gui.child do
			local c = head_gui.child[i]
			print(pod{c.sx, c.sy, c.width, c.height}, 340, 30+i*10, 7)
		end
		for i=1,#ws_gui.child do
			local c = ws_gui.child[i]
			print(pod{c.sx, c.sy, c.width, c.height}, 340, 90+i*10, 7)
		end
	end
]]

	toolbar_gui = generate_toolbar_gui()
	infobar_gui = generate_infobar_gui()

	head_gui.child = {}
	head_gui:attach(tooltray_gui)
	head_gui:attach(ws_gui)
	head_gui:attach(toolbar_gui)
	head_gui:attach(infobar_gui)

	
--[[
	--printh("@@ generate_head_gui: #ws_gui.child: "..#ws_gui.child)
	printh("@@ generate_head_gui: ws_gui "..tostr(ws_gui).."  (workspace_index: "..workspace_index..")")
	if (ws_gui and ws_gui.child) printh("  // #ws_gui.child: "..#ws_gui.child)
	if (ws_gui and ws_gui.child and ws_gui.child[1]) printh("  // ws_gui.child[1].width: "..tostr(ws_gui.child[1].width))
]]

	function head_gui:update()

		-- slide infobar / infobar to targets
		toolbar_y = (toolbar_y * 3 + toolbar_y_target) / 4
		infobar_y = (infobar_y * 3 + infobar_y_target) / 4
		
		-- move towards target a pixel so that can reach exact value. also just nicer motion (no single-pixel creep at end; small transitions are faster)

		if (toolbar_y < toolbar_y_target) then
			toolbar_y = min(toolbar_y + 1, toolbar_y_target) else
			toolbar_y = max(toolbar_y - 1, toolbar_y_target) end

		if (infobar_y < infobar_y_target) then
			infobar_y = min(infobar_y + 1, infobar_y_target) else
			infobar_y = max(infobar_y - 1, infobar_y_target) end
		

		-- tooltray visibility
		if (tooltray_is_open() ~= last_tooltray_is_open) then
			for i=1,#tooltray_gui.child do
				send_message(tooltray_gui.child[i].proc_id, {event=tooltray_is_open() and "gained_visibility" or "lost_visibility"})
			end
		end
		last_tooltray_is_open = tooltray_is_open()

		-- don't draw under toolbar (optimisation)
		tooltray_gui.height = toolbar_y - tooltray_gui.y


		-- to do: show_bars should be initial state, and then docked is optional
		local show_toolbar = ws_gui.show_toolbar 
--		local show_infobar = ws_gui.show_infobar
		local show_infobar = get_show_infobar()

		if (key("alt")) show_toolbar = true

		-- auto-showing bars using mouse position is annoying in fullscreen; just for tools / desktop
		-- fullscreen has ESC, but tools have no other way to reach toolbar (without knowing kbd shortcut)
		--if (false) then
		if (ws_gui.style ~= "fullscreen") then
			--if ((my < 2 and mb == 0) or my < toolbar_y + toolbar_gui.height) then 
			if ((my < 2 and mb == 0)) then -- don't need second test if doing ws_gui.show_toolbar = true; allows ctrl-1 to immediately hide even while mouse is at top
				show_toolbar = true
				ws_gui.show_toolbar = true -- experimental: low friction to de-fullscreenify. can turn off at system settings level
			end
			-- if ((my >= 270-2 and mb == 0) or my >= infobar_y) show_infobar = true
		end

		if (screensaver_proc_id) then
			show_toolbar, show_infobar = false, false
		end



		if (show_toolbar) then
			toolbar_y_target = max(toolbar_y_target, 0)
			-- snap. assumption: never want to leave an 8px (or less) sliver visible at top
			if (toolbar_y_target < 8 and mb == 0) toolbar_y_target = 0
		else
			-- hide [unless pulled out]
			--if (toolbar_y < 40) 
			toolbar_y_target = -toolbar_gui.height 
		end

		if (show_infobar) then
			infobar_y_target = min(infobar_y_target, 270-12)
			-- snap. assumption: never want to leave an 8px (or less) sliver visible at top
			if (infobar_y_target >= 270 - 12-8 and mb == 0) infobar_y_target = 270-12 -- can't use infobar_gui.height -- is 270, not 12!
		else
			-- hide [unless pulled out]
			--if (infobar_y > 270-40) 

			infobar_y_target = 270
		end



		-- jump when workspace changed (otherwise can see uncovered area e.g. above tabbed window)
		if (time() < head_gui.t0 + 0.2) then
			toolbar_y = toolbar_y_target
		end


		--------- apply toolbar / infobar position --------		

--		tooltray_gui.y = min(0, - tooltray_default_h / 1.5 + toolbar_y / 1.5) \ 1 -- move at different speed; feels more like a deep drawer. ottoman
--		tooltray_gui.y = toolbar_y - tooltray_default_h  -- same speed (testing concept: toolbar / tray is more of a single thing. too chunky)
		
		toolbar_gui.y  = toolbar_y \ 1
		toolbar_gui.sy = toolbar_y \ 1
		ws_gui.y       = max(0, toolbar_y \ 1) -- when toolbar is overlapping (fullscreen) and above top, workspace stops moving up at 0
		infobar_gui.y  = infobar_y \ 1
		infobar_gui.sy = infobar_gui.y

	end

end

-- new version: derive attributes from window and calling program
function create_workspace_1(proc_id, win_attribs)
	local ws = head_gui:new()
	ws.x = 0
	ws.y = 0
	ws.width = 480
	ws.height = 270
	ws.index = #workspace       -- ** should be "id"; can be out of order. to do: unique ids
	ws.icon = win_attribs.icon 
	ws.head_proc_id = proc_id
	ws.prog = win_attribs.prog
	ws.tabs = {}

	-- workspace inherits some of the attributes of window; 
	-- used when deciding which workspace to create windows in
	ws.style = "fullscreen"
	if (win_attribs.fullscreen) ws.style = "fullscreen"       -- default, but tested here for clarity
	if (win_attribs.workspace == "new") ws.style = "desktop"  -- requesting new workspace mean requesting new desktop
	if (win_attribs.tabbed) ws.style = "tabbed"               -- ignore fullscreen if it is set

	-- workspace inherits immportality
	if (win_attribs.immortal) ws.immortal = true

	-- workspace inherits pwc_output during recovery (out of memory crash requires recreating terminal)
	if (win_attribs.pwc_output) ws.pwc_output = true  ws.recovering = false

	-- default desktop workspace icon
	if not ws.icon then
		ws.icon = ws.style == "desktop" and 
			userdata"[gfx]08087777777777777777777777777777777700000000777777777700007700000000[/gfx]" or  -- desktop
			userdata"[gfx]09070007070000000700007777777777700000777700000777700000777777777770[/gfx]"     -- tv
	end

	-- initialise toolbar / infobar docking based on style
	ws.show_toolbar = ws.style ~= "fullscreen"
	ws.show_infobar = false

	-- opening a window into a desktop that has no underlay -> clear each frame 
	-- (harmless if false positive -- just slightly inefficient)
	if (ws.desktop and win_attribs.width < 480) then
		ws.clear_each_frame = true
	end
	
	-- ignore workspace flow while booting
	visit_workspace(ws)

	function ws:draw()
		--cls(3) -- debug: see when workspace is redrawn
		if (#self.child == 0) then
			rectfill(0,0,self.width,self.height,1)
			print("[ empty workspace ]",self.width/2-19*2.5,self.height/2,13)
		end
	end

	local pos = 1
	while (workspace[pos] and ws.head_proc_id > workspace[pos].head_proc_id) do
		pos += 1
	end

	local result = add(workspace, ws, pos)

	return result, pos
end

-- globals used by toolbar.lua

function get_workspace(index)
	if (not index) return ws_gui or {}
	return workspace[index] or {}
end

function get_num_workspaces()
	--printh("get_num_workspaces(): "..tostr(#workspace))
	return #workspace
end

function get_workspace_index()
	return workspace_index
end

function get_workspace_tabs()
	return (ws_gui and ws_gui.tabs) or {}
end

function get_workspace_icon(index)
	local icon = nil
	if (workspace[index]) then
		icon = proc_icon[workspace[index].head_proc_id]
		if (not icon and workspace[index].style == "desktop") then
			icon = userdata("[gfx]08087777777777777777777777777777777700000000777777777700007700000000[/gfx]")
		end
	end

	-- default: tv
	if (not icon) icon = userdata("[gfx]0907000707000000070000777777777770000077770000077770000077777777777[/gfx]")
	return icon
end



local last_active_win = nil


local put_x = 0
local put_y = 0



function tooltray_is_open()
	return toolbar_y > 0
end

-- used for keeping track of which workspace to toggle between (ESC) or where desktop is
-- when deciding to put new windows
function visit_workspace(ws)

	if (ws.style == "fullscreen") last_fullscreen_workspace = ws
	if (ws.style ~= "fullscreen") last_non_fullscreen_workspace = ws
	if (ws.style == "desktop") last_desktop_workspace = ws
	if (ws.style ~= "desktop") last_non_desktop_workspace = ws
	
end



--[[
	set_workspace(index)

	index can be the workspace value -- this is because index might change
	when creating new workspace, so sometimes references should be by value
	(last_desktop_workspace, last_fullscreen_workspace)
]]
function set_workspace(index)

	if (index == nil) return

--	printh("set_workspace "..tostring(index))

	-- find by value
	if (type(index) == "table") then		
		for i=1,#workspace do
			if (workspace[i] == index) index = i
		end
	end

	-- couldn't find; use first workspace
	if (type(index) == "table") then
		index = 1
	end

	-- hide any modal gui elements
	dismiss_modal()

	-- safety: no workspaces exists
	if (#workspace == 0) then
		return
	end

	-- loop around
	workspace_index = 1 + ((index - 1) % #workspace)

	ws_gui = workspace[workspace_index]
	
	visit_workspace(ws_gui)

	-- invalidate active window if not found
	if (ws_gui.active_window) then
		local found = 0
		for i=1,#ws_gui.child do
			if (ws_gui.child == ws_gui.active_window) found = true
		end
		if (not found) ws_gui.active_window = false
	end

	generate_head_gui()


--  deleteme: should only need to happen on save
--	save_open_locations_metadata()
	
--[[
	printh("set workspace: "..ws_gui.index)
	if (ws_gui.child) then
	for i=1,#ws_gui.child do
		printh("  "..ws_gui.child[i].proc_id)
	end
	end
]]

end

-- can return nil
function get_active_window()

	-- to do: might not need this
	if (tooltray_active_window and tooltray_is_open()) then 
		return tooltray_active_window
	end
	
	if (not ws_gui or #ws_gui.child == 0) then 
		return nil 
	end

	if (ws_gui.active_window) return ws_gui.active_window

	return ws_gui.child[#ws_gui.child]
end

function _init()

	cursor_gfx = fetch"/system/misc/cursors.gfx"

	prev_frame = userdata("u8", 480, 270)

	------------------------ separate font for window manager ------------------------


	poke(0x4000,get(fetch"/system/fonts/lil.font"))
	poke(0x5600,get(fetch"/system/fonts/p8.font"))

--	poke(0x5600,get(fetch"/system/fonts/pug.font"))

--	poke(0x4002, (@0x4002)+3)
--	poke(0x4004, 1) -- offset_y

	----------------------------------------------------------------------------------


	-- safety: window manager itself needs to be visible! (also safety in foot though)
	send_message(pid(), {event="gained_visibility"})  --  pokes 0x547f:0x1

--	open initial processes: desktop (default workspace), code, gfx, map, sfx, full-screen terminal (esc to toggle)
	
	-- ==========================================================================================================================================
	-- single global tooltray gui
	-- ==========================================================================================================================================
	-- 

	tooltray_gui = {x=0, y=0, width=480, height=270, 
		draw=function(self) 
			--[[
			rectfill(0,0,self.width,self.height, 3) -- green background for debugging
			print("tooltray:"..#self.child, 4,4, 7)
			for i=1,#self.child do
				local c = self.child[i]
				print(pod{c.x,c.y,c.width,c.height},30,12+i*10,7)
				
			end
			]]
		end
	}

	-- ==========================================================================================================================================

	-- forward (low-level) event messages to active window
	-- should be fast; everything has to go throught here

	_subscribe_to_events( 
		function(msg)
			if (ws_gui == nil) then return end

			local forward_events = {keydown=1, keyup=1, textinput=1, mousewheel=1, mouselockedmove=1, drop_items=1}
			local activity_events = {keydown=1, keyup=1, textinput=1, mousewheel=1, mouse=1}

			
			if msg.event == "keydown" then

				last_input_activity_t = time()

				-- alt + left,right,enter filtered out (used by window manager)
				-- needs to be here (and not in events.lua) because key state is reset when switching tabs

				if key("alt") then
					if (msg.scancode == 79 or msg.scancode == 80 or msg.scancode == 40) return
				end

				-- filter ctrl combinations
				if key("ctrl") then
					-- needs to be here (and not in events.lua) because key state is reset when switching tabs
					if (msg.scancode == 43) return -- tab / ctrl+shift+tab

					-- moved to events.lua so that can be mapped; especially for ctrl-s
					-- if (msg.scancode == 22) return -- ctrl+s 
					-- if (msg.scancode == 35) return -- ctrl+6 capture screenshot
					-- if (msg.scancode == 36) return -- ctrl+7 capture label
				end

			end


			if (forward_events[msg.event]) then
				local win = get_active_window()
				if (win and win.proc_id) then
					send_message(win.proc_id, msg)
				end
			end
		end
	)

	-- ==========================================================================================================================================

	-- to do: maybe no longer used / needed?
--[[
	on_event("set_workspace",
		function (msg)
			set_workspace(msg.index)
		end
	)
]]
	on_event("drag_toolbar",
		function (msg)
			--toolbar_y_target = mid(0, toolbar_y + msg.dy, tooltray_default_h) -- limiting feels bad
			toolbar_y_target = mid(0, toolbar_y + msg.dy, infobar_y-11)
			toolbar_y = toolbar_y_target
		end
	)

	on_event("drag_infobar",
		function (msg)
			infobar_y_target = mid(0, infobar_y + msg.dy, 270-11)
			infobar_y = infobar_y_target
		end
	)

	-- used by toolbar; maybe should just be a function call
	on_event("bring_window_to_front",
		function (msg)
			local win = get_window_by_proc_id(msg.proc_id)
			set_active_window(win)		
		end
	)


	on_event("modified:/appdata/system/settings.pod",
		function (msg)
			sdat = fetch"/appdata/system/settings.pod"
		end
	)
	
	toolbar_gui = toolbar_init()
	infobar_gui = infobar_init()

	generate_head_gui()

	--_signal(36) -- finished loading core processes  (deleteme -- shouldn't need)
	--flip()
end



function draw_window_frame(win)


	local x0 = win.x
	local y0 = win.y
	local x1 = win.x + win.width  - 1
	local y1 = win.y + win.height - 1

	
	local bar_col = theme"dormant_frame"
	local border_col = theme"dormant_border"
	local title_col = theme"dormant_title"

	-- adjust for base gui position; to do: shouldn't be necessary

	camera()
	x0 = x0 + ws_gui.sx
	y0 = y0 + ws_gui.sy
	x1 = x1 + ws_gui.sx
	y1 = y1 + ws_gui.sy

	if (get_active_window() == win) then 
		-- active window colours
		
		bar_col = theme"window_frame"
		border_col = theme"window_border"
		title_col = theme"window_title"
	end

	rectfill(x0,y0-bar_h, x1,y0-1,  bar_col)
	rectfill(x0,y0-1, x1,y0-1,  border_col)

	-- outside outline: cuts into corners by 1 pixel
	y0 = y0 - bar_h


	-- to do: need to calculate width for variable width font
	-- to do: need to calculate y offset based on font

	clip(x0+16, y0, (x1-x0)-26, y1-y0)
	print(win.title,max(x0 + 16, (x0+x1)/2 - #win.title*char_w/2), y0+2, title_col)
	clip()

	line(x0+1, y0-1, x1-1, y0-1, border_col)
	pset(x0,y0,border_col)
	pset(x1,y0,border_col)

	if not sdat.squishy_windows then

		-- sides, bottom
		line(x0+1, y1+1, x1-1, y1+1, border_col)
		line(x0-1, y0+1, x0-1, y1-1, border_col)
		line(x1+1, y0+1, x1+1, y1-1, border_col)

		-- bottom corners
		pset(x0,y1,border_col)
		pset(x1,y1,border_col)

	else

		-- partial sides
		line(x0-1, y0+1, x0-1, y0+12, border_col)
		line(x1+1, y0+1, x1+1, y0+12, border_col)
	end


	-- shadow around the side: 2px left 3px down
	-- to do: rectfill_shadow
	--[[
	-- left
	rectfill_shadow(x0-2, y0+3, x0-2, y1+1)
	rectfill_shadow(x0-3, y0+4, x0-3, y1+1)

	-- bottom
	rectfill_shadow(x0-3, y1+2, x1-1, y1+2)
	rectfill_shadow(x0-2, y1+3, x1-2, y1+3)
	rectfill_shadow(x0-1, y1+4, x1-3, y1+4)

	-- L-shaped gap bottom left
	rectfill_shadow(x0-1,y1,x0-1,y1+1)
	rectfill_shadow(x0,y1+1,x0,y1+1)

	]]


	-- solid shadow  -- niche but kinda interesting. could be a theme attribute along with square window corners.
	--[[
		color(32)
		rectfill(x0-2, y0+3, x0-2, y1+1)
		rectfill(x0-3, y0+4, x0-3, y1+1)
		rectfill(x0-3, y1+2, x1-1, y1+2)
		rectfill(x0-2, y1+3, x1-2, y1+3)
		rectfill(x0-1, y1+4, x1-3, y1+4)
		rectfill(x0-1,y1,x0-1,y1+1)
		rectfill(x0,y1+1,x0,y1+1)
	]]


end


function draw_window_paused_menu(win,sx,sy)
	
	if (not win.pmenu) return

	local ww,hh = 70, 12 + (#win.pmenu) * 6
	local x0,y0 = sx + win.width/2 - ww, sy + win.height/2 - hh
	local x1,y1 = x0 + ww*2 - 1, y0 + hh * 2 - 1

	rectfill(x0,y0,x1,y1,0)
	rect(x0+1,y0+1,x1-1,y1-1,7)


	for i=1,#win.pmenu do 
		local xx = x0 + 20
		local yy = y0 + 3 + i * 12
		local label = "??"

		if (type(win.pmenu[i].label) == "function") label = win.pmenu[i].label()
		if (type(win.pmenu[i].label) == "string")   label = win.pmenu[i].label
		print(label, xx, yy, 7)
		if (i == win.pmenu.ii) print("\^:0103070f07030100",xx-10,yy,7)
	end
end

function update_window_paused_menu(win)

	if (not win) return

	if (win.paused) then
		local buttons = btnp()
		if (win.pmenu) then

			if ((buttons & 0x73) > 0) then
				-- printh("selected pause menu item "..win.pmenu.ii)
				local item = win.pmenu[win.pmenu.ii]
				if (type(item.action) == "function") item.action(buttons)
			end

			if (btnp(2)) win.pmenu.ii -= 1
			if (btnp(3)) win.pmenu.ii += 1
			if (win.pmenu.ii < 1) win.pmenu.ii = #win.pmenu
			if (win.pmenu.ii > #win.pmenu) win.pmenu.ii = 1
		end

	else
		-- pause button to pause (not within first 6 frames  ~ is left over button state)
		-- to do: button blocking scheme?
		if (btnp(6) and time() > win.created_t + 0.1) then
			win.paused = true
			generate_paused_menu(win)
			send_message(win.proc_id, {event = "pause"})
		end
	end

end




function generate_paused_menu(win)
	win.pmenu = {}

	add(win.pmenu, {label = "Continue", action = function() 
		win.paused = false
		send_message(win.proc_id, {event = "unpause"})
	end})

	-- insert userland menu items
	local menu = proc_menu[win.proc_id]

	if (menu) then
		for i=1,#menu do
			add(win.pmenu,
			{
				label = menu[i].label or "??",
				action = function(b)
					send_message(win.proc_id, {event="menu_action", id=menu[i].id, b=b})
				end
			})
		end
	end

--	add(win.pmenu, {label = "Options", action = function() end}) -- later

	add(win.pmenu,{
		label  = function(self) return (_ppeek(win.proc_id, 0x547f) or 0) & 0x8 > 0 and "Sound: Off" or "Sound: On" end,
		action = function(b) send_message(win.proc_id, {event = "toggle_mute"}) end
	})

--	add(win.pmenu, {label = "Favourite"}) -- later; need to decide what this means!
	add(win.pmenu, {label = "Reset Cartridge", action = function() 

		if (haltable_proc_id == win.proc_id) then
			-- pwc: same as hitting ctrl-r (dupe)
			haltable_proc_id = create_process("/system/apps/terminal.lua",{
				corun_program = "/ram/cart/main.lua",       -- program to run // terminal.lua observes this and is also used to set pwd
				reload_history = true,                      -- observed by terminal.lua
				window_attribs = {
					pwc_output = true,                      -- replace existing pwc_output process			
					show_in_workspace = true,               -- immediately show running process
				}
			})
		else
			send_message(2, {event="restart_process", proc_id = win.proc_id})
			win.paused = false
			win.resetting = true -- don't kill process in win:update() while resetting
		end

	end})

	-- to do: can the process that launched a process have a say in its pause menu?
	-- add(win.pmenu, {label = "Exit to Splore", action = function() end})

	-- useful when running locally -- often just want to close the whole workspace when done running a fullscreen cart
	if haltable_proc_id ~= win.proc_id then
		add(win.pmenu, {label = "Exit", action = function()
			if (haltable_proc_id == win.proc_id) then
				-- halt program and enable command prompt (update: never happens -- menu item is not added in that case)
				win.paused = false
				send_message(win.proc_id, {event = "unpause"})
				send_message(haltable_proc_id, {event="halt"})
				haltable_proc_id = false
			else
				if (win.fullscreen) then
					close_workspace(workspace_index) -- fullscreen: assume running as sole child in a workspace created for that purpose
					set_workspace(previous_workspace)
				else
					close_window(win, true) -- windowed programs can be pauseable too, but is not on by default
				end
			end
		end})
	end

	win.pmenu.ii = 1
	
end

	

-- doesn't kill process -- that's up to process manager
-- update: seems almost always want to kill at the same time; added as a parameter
function close_window(win, do_kill)

	if (win.immortal and not do_kill) return -- terminal needs to be able to die when broked from out of memory
	
	_kill_process(do_kill and win and win.proc_id)

	win = win or get_active_window() -- is the get_active_window default ever used? to do: review and remove
	if (win.closing) then return end

	-- invalidate active window
	if (win.parent.active_window == win) win.parent.active_window = nil

	-- headless process should not be hogging cpu / calling _draw
	send_message(win.proc_id, {event="lost_visibility"})

	-- send message to self to close after end of frame
	-- (otherwise can invalidate an iterator somewhere?)

	send_message(pid(), {event="close_window",proc_id = win.proc_id})
	win.closing = true

end



function generate_windat()

	local windat = {
		--{x=0,y=infobar_y,width=480,height=270-infobar_y} -- first entry is always infobar
	}

	for i=1,#ws_gui.child do
		local w2 = ws_gui.child[i]
		-- only windows that have a frame and are solid
		-- later: could send a low-res 160x90 mask including non-rectangular windows
		if (w2.has_frame and _ppeek(w2.proc_id, 0x547d) == 0 and w2 ~= win) then
			add(windat, {
				x = w2.x, y = w2.y - bar_h,
				width = w2.width, height = w2.height + bar_h
			})
		end
	end

	return windat
end


function set_active_window(win)

	if (not win) return

	-- bring to front of same-z group
	win:bring_to_front()

	-- set active window for that sub-gui
	win.parent.active_window = win

	-- give focus to / take focus from tooltray
	tooltray_active_window = (win.parent == tooltray_gui) and win or nil
end



-- new version
function create_window(target_ws, attribs)

	local win = nil

--	printh("creating window: "..pod{attribs})

	add(boot_messages, attribs.prog)

	attribs = attribs or {}

	if (not attribs.width or not attribs.height or attribs.fullscreen) then
		attribs.width = 480
		attribs.height = 270
		attribs.x = 0
		attribs.y = 0
		attribs.fullscreen = true
	end

	attribs.x = attribs.x or (attribs.tabbed and 0  or rnd(480 - attribs.width)\1)
	attribs.y = attribs.y or (attribs.tabbed and 11 or (30 + rnd(230 - attribs.height)\1))


	-- default attributes

	if (attribs.has_frame  == nil)   attribs.has_frame  = false
	if (attribs.moveable   == nil)   attribs.moveable   = true
	if (attribs.resizeable == nil)   attribs.resizeable = true
	if (attribs.fullscreen       )   attribs.width, attribs.height, attribs.x, attribs.y = 480, 270, 0, 0
	if (attribs.maximised        )   attribs.width, attribs.height, attribs.x, attribs.y = 480, 248, 0, 11

	if (attribs.pauseable == nil) attribs.pauseable = attribs.fullscreen and not attribs.desktop_filenav and not attribs.wallpaper

	win = target_ws:attach(attribs)
	
	-- position at top of same-z stack
	win:push_to_back()    -- bottom of same-z stack (push behind any foreground layers)
	win:bring_to_front()  -- bring back up to front of same-z stack

	win.send_mouse_update = true -- send mouse message on first frame
	win.created_t = time()

	win.test_point = function(self, x, y)
		-- process is using transparency on display bitmap?
		local alphabits = _ppeek(win.proc_id, 0x547e) -- INTERACT_ALPHABITS_ADDR
		if (not alphabits or alphabits == 0) return true

		if (win.interactive == false) return false -- e.g. cursor charms should never block mouse click

		-- look up the pixel
		local disp_width = _ppeek(win.proc_id, 0x5478) + (_ppeek(win.proc_id, 0x5479) << 8)
		local val = _ppeek(win.proc_id, 0x10000 + (y * disp_width) + x)

		-- considered solid when at least one of the alpha bits is set in this pixel
		return (val & alphabits ~= 0)
	end

	
	function win:draw()

		-- not visible or about to close --> skip
		if (not win.visible or win.closing) return
		--if (win.closing) return

		-- don't render on first visible frame as process :draw has likely not been called
		-- without this, get flickering when switching tabs
		-- update: this mechanism seems redundant if entire wm skipping a frame when chaning window focus (see last_draw_window)
			-- but actually prevents a different type of flicker -- e.g. switching from gfx to map editor at start.
			-- to do: investigate why; just a result of 2 frames instead of 1? need to formalise wm guarantees

		-- commented: should be doing this at the workspace level anyway; 
		-- consider stacked tabs that are drawn except for the top one on the first frame after changing workspace

		--[[
		if (not win.process_had_a_chance_to_draw) then
			win.process_had_a_chance_to_draw = true
			return
		end
		]]

		local blit_result = false
		
		if sdat.squishy_windows and win.has_frame then

			local border_col = theme(get_active_window() == win and "window_border" or "dormant_border")

			clip()
			if (not win.sxa) win.sxa = {}
			if (not win.sya) win.sya = {}
			win.sxa[0] = win.sx + 0.5
			win.sya[0] = win.sy + 0.5

			while (#win.sxa < win.height) add(win.sxa, win.sxa[#win.sxa])
			while (#win.sya < win.height) add(win.sya, win.sya[#win.sya] + 1)
			
			for yy = 1, #win.sxa do
				win.sxa[yy] = win.sxa[yy] * 0.03 + win.sxa[yy-1] * 0.97
				win.sya[yy] = win.sya[yy] * 0.03 + (win.sya[yy-1] + 1) * 0.97
				if (abs(win.sya[yy] - (win.sya[yy-1] + 1)) < 0.05) win.sya[yy] = win.sya[yy-1] + 1.0
			end

			camera()
			local yy1 = win.sya[0]
			for yy = 0, win.height-1 do
				local ht = (win.sya[yy+1] - win.sya[yy])\1 -- draw > 1px high when stretched out

				while (yy1 <= win.sya[yy]) do
					blit_result = _blit_process_video(win.proc_id, 0, yy, nil, 1 + ht, win.sxa[yy], yy1)
					pset(win.sxa[yy]-1, yy1, border_col)
					pset(win.sxa[yy]+ win.width, yy1, border_col)
					yy1 += 1
				end

			end

			-- bottom line
			local yy = win.height-1
			line(win.sxa[yy], yy1, win.sxa[yy] + win.width - 1, yy1, border_col)

		else
			-- regular rectangular blit

			blit_result = _blit_process_video(win.proc_id, 0, 0, nil, nil, win.sx, win.sy)

			-- clear squishy positions

			win.sxa = nil
			win.sya = nil

		end
		
		-- could not blit (_draw didn't complete?) 
			--> blit from desktop copy instead (when not fullscreen -- fullscreen can just do nothing!)
		-- non-rectangular windows (w/ PROCBLIT_TRANSP_ADDR set) should make sure 
		if (blit_result and not win.fullscreen) then
			blit(prev_frame, nil, win.sx, win.sy, win.sx, win.sy, win.width, win.height)
			--clip() circfill(0,0,16,8) circfill(0,0,24,7) -- debug: show that (desktop) window is frame-skipping			
		end


		-- debug: show window size
--		local ww,hh = _get_process_display_size(win.proc_id)
--		print(pod{win.width, win.height, ww, hh}, 5,15,8+rnd(16))

		-- always draw frame for now (lazy)  // to do: check visibility
		if (win.has_frame) then
			clip()
			draw_window_frame(win)
		end

		-- paused menu

		if (win.paused) then
			draw_window_paused_menu(win, win.sx, win.sy)
		end

		-- stickers
		if (type(win.stickers) == "table") then
			clip() camera()
			for i=1,#win.stickers do
				local s = win.stickers[i]
				if (type(s) == "table" and type(s.bmp) == "userdata" and s.x and s.y) then
					local ww, hh = s.bmp:attribs()
					if (s.x >= 0 and s.y >= -12 and s.x < win.width and s.y < win.height) then
						spr(s.bmp, win.sx + s.x - ww\2, win.sy + s.y - hh\2)
					else
						-- to do: fall off? sparkle puff?
						del(win.stickers, s)
					end
				end
			end
		end
		
	end


	function win:update()
		
		win.width, win.height = _get_process_display_size(win.proc_id)

		win.is_active = self == get_active_window()

		-- no process --> close 
		-- except when in the middle of resetting cartridge: there might be a few frames where process has no display
		if (win.width == 0 or win.height == 0) and not win.resetting then
			close_window(win)
			return
		end
		

		-- autoclose a non-tabbed window that is covered by a tabbed window
		-- otherwise: need some way to access that window. don't want to tab it! sheesh

		if (win.autoclose and
			win.parent.child[#win.parent.child].tabbed and
			not win.tabbed and            -- also means that this window isn't the window on top, which is tabbed
			time() > win.created_t + 0.5) -- don't close in the first half a second (give a chance to get focus)
		then
			close_window(win, true)
			return
		end

		-- tabbed: adapt position and size to useable desktop space

		if (win.tabbed) then

			-- slide with toolbar (means change height every frame when transitioning)
			win.y = min(0, toolbar_gui.sy) + toolbar_gui.height
			win.sy = win.y

			if (win.height ~= 270 - win.y) then
				win.height = 270 - win.y
				send_message(win.proc_id, {event="resize", width = win.width, height = 270 - win.y})
			end
		end

	end

	

	function win:click(msg)

		set_active_window(win)

			-- context menu on mb2 (used by filenav -- need to provide nicer mechanism for generating that menu)
			if (win.has_context_menu and msg.mb == 2) then
				-- keep above 150 -- assume menu is shorter than that. to do: maybe need a keep_inside_parent attribute
				send_message(3, {event = "toggle_app_menu", _delay = 0.1 , x = win.sx + msg.mx - 70, y = min(win.sy + msg.my - 30, 150) , proc_id = win.proc_id })
				
			end

		return true -- processed
	end

	function win:drag(msg)
		-- drag event is generate by window's own gui.lua
		-- send_message(win.proc_id, msg) -- forward to window 
	end


	-- titlebar

	if (win.has_frame) then

		local bar = win:attach(
			{
				x = 0, y = -bar_h,
				width = win.width,
				height = bar_h,
				clip_to_parent = false,
				cursor = "grab", -- to do: why doesn't this work? because outside of parent?
				is_window_bar = true
			}
		)

		function bar:draw()
		end

		-- close button
		bar:attach(
			{
				cursor = "pointer",
				x = -2, justify="right",
				y = 0, vjustify="center",
				width = 7, height = 7,
				tap = function(self)
					close_window(self.parent.parent, true)
				end,
				draw = function(self, msg)
					(msg.has_pointer and circfill or circ)(self.width / 2, self.height / 2, self.width/3, 
						win.parent.active_window == win and theme("window_button") or theme("dormant_button")) 					
				end
			}
		)

		-- app menu button
		bar:attach(make_window_button(bar, "app menu", 4, 1, 10, 10 +1)) -- height +1 so that window frame border is not clobbered


		function bar:update(event)
			self.width = self.parent.width
			self.col_k = win.parent.active_window == win and "window_button" or "dormant_button"

			-- to do: also need to adjust buttons
			-- maybe positions could be right-justified? would be nice!
			-- e.g. btn.justify = "left" | "center" | "right"
		end
		

		function bar:drag(event)
			if (not win.moveable) return
			win.x += event.dx
			win.y = max(24, win.y + event.dy)
			-- let application know! app can also send message requesting move
			send_message(win.proc_id, {event="move", x = win.x, y = win.y, dx = event.dx, dy = event.dy})
		end

		function bar:click()
			if (not key("lshift")) then -- key state test, but actually quite useful! drag windows around underneath
				bar.parent:bring_to_front()
			end
			win.parent.active_window = win -- either way: this window becomes the active window
		end

		function bar:doubletap()
			-- maximise
--			win.x = 0
--			win.y = 12

			if (not win.resizeable) return

			if (win.maximised) then
				win.maximised = false
				send_message(win.proc_id, {event="resize", x = win.old_x, y = win.old_y, width = win.old_width, height = win.old_height})
			else
				win.maximised = true
				win.old_x = win.x
				win.old_y = win.y
				win.old_width = win.width
				win.old_height = win.height
				-- space to see frame
				send_message(win.proc_id, {event="resize", x = 1, y = 24, width = 478, height = 245})
			end

		end



		--[[--------------------------------------------------------------------------------------------------------------

			resize widget

			// always attach if not resizeable; window attribute can change after creation

			to do: could be a single large rectangle behind window
			(so only works when cursor is slightly outside of window)
			or -- put in front and use test_point (ha!)
		
		--------------------------------------------------------------------------------------------------------------]]--


		local function resize_click(self, event) 
			win.start_mx, win.start_my = mx, my
			win.start_w, win.start_h = win.width, win.height
			win.start_x, win.start_y = win.x, win.y
		end

		function resize_draw(self, event) 
			-- debug: view the widget // don't need to clip() because .clip_to_parent == false
			-- rect(0, 0, self.width-1, self.height-1, 5)
		end

		-- resize bottom right
		win:attach({
			width = 8, height = 8,
			clip_to_parent = false,
			cursor  = 8,

			update = function(self)
				self.x = win.width - 4
				self.y = win.height - 4
			end,
			draw  = resize_draw,
			click = resize_click,
			drag = function(self, event)
				if (win.resizeable and (event.dx ~= 0 or event.dy ~= 0)) then
					-- use window manager mx, my because using relative event.mx,event.my will jump around as window resizes
					-- hard-coded minimum window size: 64x32
					local new_width  = max(64, win.start_w + (mx - win.start_mx))
					local new_height = max(32, win.start_h + (my - win.start_my))
					send_message(win.proc_id, {event="resize", width = new_width, height = new_height})
				end
			end
		})

		-- resize bottom left
		win:attach({
			width = 8, height = 8,
			clip_to_parent = false,
			cursor  = 9,

			update = function(self)
				self.x = -4
				self.y = win.height - 4
			end,
			draw  = resize_draw,
			click = resize_click,

			drag = function(self, event) 
				if (win.resizeable and (event.dx ~= 0 or event.dy ~= 0)) then
					-- set x in same message so that visible change is simultaneously (otherwise jitters)
					local new_width  = max(64, win.start_w\1 - (mx - win.start_mx))
					local new_height = max(32, win.start_h + (my - win.start_my))
					send_message(win.proc_id, {event="resize", 
						width = new_width, 
						height = new_height, 
						x = win.start_x + (mx - win.start_mx)
				})

				end
			end
		})

--[[
		-- commented; maybe nice to have just bottom left, bottom right widgets.

		-- resize bottom
		win:attach({
			x = 4, 
			y = win.height - 4,
			width = win.width - 8,
			height = 8,
			clip_to_parent = false,
			update = function(self)
				self.y = win.height - 4
				self.width = win.width - 8
			end,
			draw  = resize_draw,
			click = resize_click,
			drag = function(self, event) 
				if (event.dx ~= 0 or event.dy ~= 0) then
					send_message(win.proc_id, {event="resize", height = win.start_h + (my - win.start_my)})
				end
			end
		})

		-- resize left
		win:attach({
			x = -4, y = 0, 
			width = 8, height = win.height  - 4,
			clip_to_parent = false,
			update = function(self)
				self.height = win.height  - 4
			end,
			draw  = resize_draw,
			click = resize_click,
			drag = function(self, event) 
				if (event.dx ~= 0 or event.dy ~= 0) then
					send_message(win.proc_id, {event="resize", 
						width = win.start_w\1 - (mx - win.start_mx)\1, 
						x = win.start_x + (mx - win.start_mx)
					})
				end
			end
		})

		-- resize right
		win:attach({
			x = win.width-4, y = 0, 
			width = 8, height = win.height  - 4,
			clip_to_parent = false,
			update = function(self)
				self.height = win.height  - 4
				self.x = win.width-4
			end,
			draw  = resize_draw,
			click = resize_click,
			drag = function(self, event) 
				if (event.dx ~= 0 or event.dy ~= 0) then
					send_message(win.proc_id, {event="resize", 
						width = win.start_w\1 + (mx - win.start_mx)\1, 
					})
				end
			end
		})
]]



	end


	-- creating a desktop wallpaper --> automatically create a filenav overlay

	if win.wallpaper and target_ws and (win.workspace == "new" or win.workspace == "tooltray") then

		local filenav_workspace = win.workspace == "tooltray" and "tooltray" or target_ws.index

		target_ws.desktop_filenav_proc_id = 
		create_process("/system/apps/filenav.p64",{
			 -- window attribs of the desktop program launching the desktop filenav
			argv = {"-desktop", win.desktop_path or "/desktop"},
			window_attribs = {
				workspace = filenav_workspace, -- same workspace as the wallpaper
				width = win.width, height = win.height,
				x = win.x, y = win.y, z = win.z + 1, -- desktop is -1000 (head.lua)
				has_frame = false,
				moveable = false,
				resizeable = false,
				desktop_filenav = true
			}
		})
	end


	
	return win	
end

--[[
	mouse_scaled()
	takes video mode into account
	to do: lower level
]]
function mouse_scaled()

	local x,y,b,dx,dy = mouse()


	local scale = 1
	local video_mode = @0x547c

	if (video_mode == 3) scale = 2
	if (video_mode == 4) scale = 3

	x \= scale
	y \= scale

	return x,y,b,dx,dy
end

local last_draw_t = 0
local smoothed_fps = 0
local show_fps = false
local last_drawn_ws = nil
local ws_gui_frames = 0

local inited_font = false

boot_messages = {}


local xodat = {26,22,19,17,15,14,12,11,10,9,8,7,6,5,5,4,3,3,2,2,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,2,2,3,3,4,5,5,6,7,8,9,10,11,12,14,15,17,19,22,26}


function _draw()

	pal(0) -- reset colourtable but leave rgb display palette alone

	-- don't draw frame when changing window or workspace; allows messages to complete and prevents flicker
	-- (e.g. switch through newly opened tabs, or gfx setting current sprite picked up by map editor)
	if (last_draw_window ~= get_active_window()) then
		last_draw_window = get_active_window()
		return
	end

	-- also skip first frame when changing workspace
	-- to do: unnecessary? prevents gfx->map flicker, but maybe just because skipping 2 frames instead of 1
	-- also: causes no visible refresh when holding alt-right/left (only see where workspace index ended up on release) -> why?
	if (last_drawn_ws ~= ws_gui) then last_drawn_ws = ws_gui return end


	-- sanity
	if (ws_gui) then
		if (ws_gui.width < 480) printh("*** ws_gui.width: "..ws_gui.width)
		if (ws_gui.height < 240) printh("*** ws_gui.height: "..ws_gui.height)
	end

	--[[
		wm should never hold frames (or need to)
		if becomes relevant, then is a bug and is extremely hard to see what's going on with wm holding frames
		e.g. if 30fps app is showing frames every second frame, the ones wm is holding --> appears frozen
		better to just let the wm interface start flickering
		0.1.0h: commented. too many moments that genuinely need to be hidden for a frame! 
		e.g. click between channels in pattern editor -> causes cpu debt that wm can't easily avoid being starved from 	
		--> uncomment while debugging wm refresh issues
	]]
	-- poke(0x547f, peek(0x547f) & ~0x2) -- unset hold_frame bit

	
	-- workspace doesn't have a fullscreen window covering it
	-- e.g. launch filenav when there is no desktop workspace, or running web cart player
	-- ** important not to clear each frame for fullscreen apps -- otherwise get flashing when < 60fps
	-- ** note: can be fullscreen but still width < 480 (because videomode) 
	if (ws_gui and (ws_gui.clear_each_frame or (ws_gui.child[1] and ws_gui.child[1].width < 480 and not ws_gui.child[1].fullscreen))) then
		rectfill(0,0,479, 269, 0x10)
		rectfill(0,0,479,11,7) -- toolbar-ish shape for cart player
	end

	-- cls(10) -- debug

	local awin = get_active_window()


	if (not ws_gui or #workspace == 0) then
		cls()
		if (time() > 3) print("[no workspaces found] "..#workspace,20,20,13)
		if (#workspace > 0) set_workspace(1)
		return
	end


	if (screensaver_proc_id) then
		local win = get_window_by_proc_id(screensaver_proc_id)
		if (win) win:draw()
	else

		head_gui:draw_all()
	
	end

	camera()
	clip()

	-- keep a copy of window output
	-- cheap, general way to do frame holding. should cost ~2% cpu. just a 128k memcpy!
	-- can optimise later for full-screen programs that don't need cursor (just skip drawing anything)

	if (not awin or not awin.fullscreen) 
	then
		blit(nil, prev_frame)
		--prev_frame:copy(8)
	end


	-- toolbar
	if (do_draw_toolbar) then

		-- toolbar shadow
		-- doesn't work! on top of window. need stencil bit for window frame!
		-- but doesn't work visually anyway
		-- rectfill_shadow(0,ws_gui.y + 11, 480, ws_gui.y + 12) 


--		draw_toolbar()

--		line(0,11,479,11,32) -- too much

--		printh(pod(ws_gui))
--		draw_infobar()
		
	end

	-- sparkles (under mouse cursor)

	if (sdat.sparkles) draw_sparkles()


	-- draw cursor
	-- mouse cursor is visible by default
	-- use hide_cursor() to hide it

	local show_cursor = not screensaver_proc_id

	if (show_cursor) then
		mx, my, mb = mouse_scaled()

		-- show default cursor when active window doesn't have one, and not holding alt


		local gfx = cursor_gfx[1].bmp or default_cursor_gfx

--		if (head_gui.mouse_cursor_gfx) gfx = head_gui.mouse_cursor_gfx 
		
		if (awin and awin.cursor and not key("alt")) gfx = awin.cursor
		if (head_gui.mouse_cursor_gfx) gfx = head_gui.mouse_cursor_gfx -- override with wm cursor (resize window)

		if (gfx == "crosshair") gfx = 2
		if (gfx == "grab") gfx = mb == 0 and 3 or 4
		if (gfx == "pointer") gfx = mb == 0 and 5 or 6
		if (gfx == "dial") gfx = mb == 0 and 7 or 0


		if (type(gfx) == "number") gfx = cursor_gfx[flr(gfx)].bmp
		if (type(gfx) != "userdata") gfx = default_cursor_gfx

		
		if (dragging_items) then

			-- dragging: override cursor gfx
			gfx = cursor_gfx[4].bmp

			-- follow: mouse
			local fx = mx - 8
			local fy = my - 8

			for i=1,#dragging_items do
				local item = dragging_items[i]
				if (not item.xo) item.xo = item.x - mx
				if (not item.yo) item.yo = item.y - my
			end

			local hover_win = head_gui:el_at_xy(mx, my)
			local keep_original_positions = not hover_win or hover_win.desktop_filenav
			for i=1,#dragging_items do
				
				local item = dragging_items[i]

				local dx,dy = fx - item.x, fy - item.y
				local aa = atan2(dx, dy)
				local tx,ty

				if (keep_original_positions) then
					tx,ty = mx + item.xo, my + item.yo
				else
					tx,ty = fx - cos(aa)*2, fy - sin(aa)*2
				end

				if (#dragging_items > 10) then
					-- catch up faster
					item.x = (item.x*2 + tx) / 3
					item.y = (item.y*2 + ty) / 3
				else
					item.x = (item.x*3 + tx) / 4
					item.y = (item.y*3 + ty) / 4
				end
	
				if (i==1) item.x, item.y = tx,ty

				-- follow: the item in front
				fx = item.x
				fy = item.y
				
			end

			-- draw with item closest to cursor on top
			for i=#dragging_items,1,-1 do
				local item = dragging_items[i]
				spr(item.icon, item.x, item.y)
			end

		end

		last_mx9, last_my9 = mx, my

		-- 
		local gfx_w, gfx_h = gfx:attribs()
		spr(gfx, mx - (gfx_w+1)\2, my - (gfx_h+1)\2)  -- +1 so exactly at center for odd-sizes bitmaps. ref: paint bucket
	end

	-- notifications  --  show for 2~3 seconds (to do: customisable)

	local notify_duration = 2
	if (user_notification_message and #user_notification_message > 15) notify_duration = 3
	if (time() < 3) notify_duration = 5 -- startup message; e.g. mended drive.loc

	if (user_notification_message and time() < user_notification_message_t + notify_duration) then
		local y = 270
		if (@0x547c == 3) y = 135
		if (@0x547c == 4) y = 90

		rectfill(0,y-11,479,y-1,32)
		print(user_notification_message, 4,y-9, 7)
	end

	

	-- fps

	if (show_fps) then
		-- has no effect if 0 is transparent! need to be able to turn blending on / off.
		-- gives programmer option of faster code path too
		rectfill(450,259,479,469,32) 
		local fps_target = (1/(time() - last_draw_t))
		smoothed_fps = (smoothed_fps * 31 + fps_target * 1) / 32
		local num_str = (smoothed_fps + 0.5) // 1
		print(tostr(num_str), 452, 261, 7)
		last_draw_t = time()
	end

	-- grab palette and video mode from active window's process (if there is one)

	if (awin) then

		-- 0.1.0c: only update when frame is not held (avoid flashing when running < 60fps)
		local val = _ppeek(awin.proc_id, 0x547f) -- might be nil if process recently ended
		if (val and val & 0x2 == 0)
		then
			--printh("@@ process palette "..time())

			-- grab the rgb display palette and video mode from that process
			-- to do: cross-process memcpy
			for i=0x5000,0x54ff,4 do
				poke4(i, _ppeek4(awin.proc_id, i))
			end
			poke(0x547c, _ppeek(awin.proc_id, 0x547c))

		else
			--printh("-- skipped resetting palette "..time())
		end

		-- copy mouselock state bits

		poke(0x5f28, _ppeek(awin.proc_id, 0x5f28))
		poke(0x5f29, _ppeek(awin.proc_id, 0x5f29))
		poke(0x5f2d, _ppeek(awin.proc_id, 0x5f2d))

	else
		--printh("** default rgb palette "..time())
		pal(2) -- otherwise use default palette
	end

	-- magnify

	if (sdat.rshift_magnify and key("rshift")) then

		local masks = peek4(0x5508); -- backup

		poke(0x5508, 0x3f, 0x3f, 0, 0) -- ignore target value; no transparency

		if (not mag_bmp) mag_bmp = userdata("u8", 64, 64)
		blit(get_display(), mag_bmp, mx-32, my-32)
		palt(0) -- nothing is transparent

		local sx,sy = mx-64, my-64
		for y=0,63 do
			local xo = xodat[y+1]
			sspr(mag_bmp, xo, y, 64-xo*2, 1, sx + xo*2, sy+y*2, 128 - xo*4, 2)
		end

		circ(mx,my,65,7) -- close enough

		circfill(mx+38,my-38,5,7) -- haha
		circfill(mx+46,my-28,3,7)

		poke4(0x5508, masks); -- restore
	end

--	print("cpu: "..(stat(1)\.01).." mem:"..(stat(0)\1024).."k",30,260,8)

	-- don't open on a tabbed tool (wait for desktop or terminal to be ready before displaying)
	if (ws_gui.style != "tabbed") then 
		if (not sent_presentable_signal) _signal(37) -- wm is presentable
		sent_presentable_signal = true
	end

end


--[[
	before running or saving cart, need to make sure that any changes made to location of current window is auto-saved.
	don't care about which window is active; there might have been changes in background! -> save everything
]]
function sync_working_cartridge_files()

	for i=1,#workspace do
		for j=1, #workspace[i].child do
			local win = workspace[i].child[j]
			--printh(win.proc_id..": "..(win.location or "no location"))
			if (win.location and string.sub(win.location, 1, 10) == "/ram/cart/") then
				send_message(win.proc_id, {event="save_file"})
				--printh("@@sync_working_cartridge_files: requesting save from "..win.location)
			end
		end
	end

	-- hack: wait for saves to complete. maybe sufficient!

	-- to do: could count number of requests and wait for each process to report save completed (or timeout)
	-- would normally complete in one frame. and then process the pending save_cart / run at end of _update
	-- update: no-Rube-Goldberg-machines policy

	for i=1,2 do flip() end

end

function run_pwc(argv, do_inject, path)

	sync_working_cartridge_files()

	clear_infobar()
	hide_infobar()

	if (do_inject and haltable_proc_id) then
		-- inject 
		send_message(haltable_proc_id,{event="reload_src", location = get_active_window().location})
	else
		-- launch terminal and request it to corun cproj
		-- terminal will skip creating a window and allow guest program to create it
		-- when haltable_proc_id is set, ESC means halt for that process

		-- create new one; because pwc_output is true, will clobber old one (if there is one)
		haltable_proc_id = create_process("/system/apps/terminal.lua",{
			corun_program = "/ram/cart/main.lua",       -- program to run // terminal.lua observes this and is also used to set pwd
			reload_history = true,
			argv = argv,
			path = path,
			window_attribs = {				
				pwc_output = true,                      -- replace existing pwc_output process			
				show_in_workspace = true,               -- immediately show running process
			}
		})

	end
end

on_event("run_pwc", function(msg)
	-- printh("@@ event run_pwc: "..pod(msg))
	run_pwc(msg.argv, false, msg.path)
end)


function _update()

	-- happens while loading
	if (not ws_gui) then
		--printh("no ws_gui!!")
		return
	end

	-- temporary hack: start on desktop
	if (time() == 1.5) set_workspace(5)

	-- make sure fullscreen terminal process exists
	if (time() > 5) then -- temporary hack: finished with booting
		for i=1,#workspace do
			if (workspace[i].style == "fullscreen" and workspace[i].pwc_output and #workspace[i].child == 0 and not workspace[i].recovering) then
				create_process("/system/apps/terminal.lua",
				{
					window_attribs = {
						fullscreen = true,
						pwc_output = true,        -- run present working cartridge in this window
						immortal   = true,        -- no close pulldown
						workspace = workspace[i].index
					},
					immortal   = true, -- exit() is a NOP
					reload_history = true,
				})

				workspace[i].recovering = true -- avoid restarting terminal more than once
			end 
		end
	end


--[[
	if (#ws_gui.child == 0) then
		close_workspace(workspace_index)
		if (not ws_gui) return
	end
]]
	if (screensaver_proc_id) then

		-- allow test to run for at least half a second before observing new input activity
		if (test_screensaver_t0 and time() < test_screensaver_t0 + 0.5) then
			last_input_activity_t = 0
		end

		-- kill when activity happened in the last second
		if (last_input_activity_t > time() - 1) then			
			_kill_process(screensaver_proc_id)
			test_screensaver_t0 = nil
			screensaver_proc_id = nil
		end
	else
		
		-- 3 minutes; to do: store in settings.pod
		if ((time() > last_input_activity_t + 180 or test_screensaver_t0) and not screensaver_proc_id) 
		then
			-- printh(pod(sdat))
			if (sdat and sdat.screensaver) then
				-- note: program doesn't need to know it is a screensaver; just kill process on activity event
				screensaver_proc_id = create_process(sdat.screensaver, 
					{window_attribs = {workspace="current", autoclose = true}})
				test_screensaver_t0 = time() -- abuse same mechanism to ignore interrupts for first half second
			else
				last_input_activity_t = time() -- don't check again for another 3 minutes
			end
		end
	end


	last_mx, last_my = mx, my
	mx, my, mb, mdx, mdy = mouse_scaled()

	if (mb > 0 and last_mb == 0) then
		start_mx = mx
		start_my = my
	end

	-- update visibility; send message

	local large_front_window = false
	local awin = get_active_window()


	local num_visible = 0

	for i=1,#workspace do
		local found_covering_window = false
--		for j=1,#workspace[i].child do
		for j=#workspace[i].child,1,-1 do

			local w = workspace[i].child[j]
			local was_visible = w.visible
	
			-- rough visibility test:
			-- same workspace, and either top (active) window, or there isn't a large window on top covering everything

			local visible = false
			if (i == workspace_index and (w == awin or not found_covering_window)) then
				visible = true
			end

			-- notify on change
			if (not was_visible and visible) then
				send_message(w.proc_id, {event="gained_visibility"})
			end
			if (was_visible and not visible) then
				send_message(w.proc_id, {event="lost_visibility"})
				-- don't draw on first frame when becomes visible again, because process needs
				-- a chance to :draw first (prevents flickering; showing a single stale frame)
				w.process_had_a_chance_to_draw = false 
			end

			w.visible = visible
			num_visible = num_visible + (visible and 1 or 0)

			-- (optimisation)
			-- placeholder test for window is covering everything underneath it   // 0x547d: alpha bits
			if (w.width==480 and w.y <= bar_h and w.y + w.height >= 270-bar_h and _ppeek(w.proc_id, 0x547d) == 0) then
				found_covering_window = true
				--printh("found covering window")
			end

		end
	end

	-- printh("num_visible: "..num_visible)

	-- tool tray visibility (DUPE)

	for i=1,#tooltray_gui.child do
		local w = tooltray_gui.child[i]
		local was_visible = w.visible
		local visible = tooltray_is_open()

		-- notify on change
		if (not was_visible and visible) then
			send_message(w.proc_id, {event="gained_visibility"})
		end
		if (was_visible and not visible) then
			send_message(w.proc_id, {event="lost_visibility"})
			w.process_had_a_chance_to_draw = false 
		end

		w.visible = visible
	end

	-- ctrl-q to fastquit // dangerous so needs to be turned on
	if (key("ctrl") and keyp("q")) then
		if (sdat.fastquit) _signal(33)
	end

	-- alt-f4 always available (er.. does windows do that anyway?	
	if (key("alt") and keyp("f4")) then
		_signal(33)
	end


	-- :: ctrl-r  (is a window manager thing!)

	-- happens first so that there's time to send lost_focus messages to tools so they
	-- can save their files to /ram/cart before the running program picks them up
	if (key("ctrl") and keyp("r")) then

		run_pwc("", key("lshift"))

	end


	-- :: ctrl-p: open tooltray
--[[
	if (key("ctrl") and keyp("p")) then
		toolbar_y_target = tooltray_default_h
	end
]]

	-- :: ctrl-o: open file (update: and other custom shortcuts)
	-- to do: more general rules for specifying shortcuts? e.g. not ctrl-
	if (key("ctrl")) then
		local win = get_active_window()
		if (win and proc_menu[win.proc_id]) then
			local menu = proc_menu[win.proc_id]
			for i=1,#menu do
				local mi = menu[i]
				if (type(mi.shortcut) == "string") then
					local letter = string.sub(mi.shortcut, -1)
					if (ord(letter) >= ord("A") and ord(letter) <= ord("Z")) then
						letter = chr(ord(letter) - ord("A") + ord("a"))
						-- handle s separately; context sensitive
						if (letter ~= "s" and keyp(letter)) then
							send_message(win.proc_id, {event="menu_action", id = mi.id, b = 0})
						end
					end
				end
			end
		end
	end

	-- :: ctrl-s

	if (key("ctrl") and keyp("s")) then

		local win = get_active_window()

		if (win.location and sub(win.location, 1, 10) ~= "/ram/cart/") then
			-- program has set a non-cartridge working file --> don't need to do anything else
			send_message(win.proc_id, {event="save_file"})
		else
			-- otherwise, always save cartridge
			-- [currently] only way to stop this is by using wrangle_working_file() / setting a .location
			sync_working_cartridge_files()

			if (fetch("/ram/system/pwc.pod")) then
				notify("saving cartridge: "..fetch("/ram/system/pwc.pod"))
				create_process("/system/util/save.lua")
			end
		end
	end

	

	-- :: ctrl-1, ctrl-2 to toggle toolbar / infobar

	if (key("ctrl") and keyp("1")) then
		ws_gui.show_toolbar = not ws_gui.show_toolbar
		if (not ws_gui.show_toolbar) toolbar_y_target = 0 -- immediately close even when mouse cursor is over it (intention + visual feedback)

		-- should show a message near the toolbar? need a "speech bubble" concept?
--		notify(ws_gui.show_toolbar and "docked toolbar" or "auto-hide toolbar")
	end

	if (key("ctrl") and keyp("2")) ws_gui.show_infobar = not ws_gui.show_infobar


	-- audio capture
	if (key("ctrl") and keyp("0")) then
		if (not fstat("/desktop/host")) _signal(65)
		_signal(16)
	end

	-- screenshot

	if (key("ctrl") and keyp("6")) then

		local dd = get_display()
		local w,h = 480,270
		if (awin and _ppeek(awin.proc_id, 0x547c) == 3) w,h = 240,135
		if (awin and _ppeek(awin.proc_id, 0x547c) == 4) w,h = 160,90
		
		local screen = userdata("u8", 480*2,270*2)
		set_draw_target(screen)
		sspr(dd,0,0,w,h,0,0,480*2,270*2)
		set_draw_target()

		if (not fstat("/desktop/host")) _signal(65) -- /desktop/host

		local num=0
		while (fstat("/desktop/host/sshot"..num..".png") and num < 64) do
			num += 1
		end
		store("/desktop/host/sshot"..num..".png", screen)

		notify("captured screenshot to /desktop/host/sshot"..num..".png")
	end

	-- capture label

	if (key("ctrl") and keyp("7")) then

		-- to do: custom desktop location from settings?

		local dd = get_display()

		local w,h = 480,270
		if (awin and _ppeek(awin.proc_id, 0x547c) == 3) w,h = 240,135
		if (awin and _ppeek(awin.proc_id, 0x547c) == 4) w,h = 160,90

		local label = userdata("u8", 480,270)
		set_draw_target(label)
		sspr(dd,0,0,w,h,0,0,480,270)
		set_draw_target()

		store("/ram/cart/label.png", label)
		notify("captured label")
	end


	-- window focus messages

	local win = get_active_window()

	if (win and last_active_win ~= win) then
		
		if (last_active_win) then 
			send_message(last_active_win.proc_id, {event="lost_focus"})
			last_active_win.is_active = false
		end

		-- give lost_focus message a chance to be processed before next window gains focus
		flip()

		win.is_active = true
		send_message(win.proc_id, {event="gained_focus"})
		-- when a click causes focus to change, that click should register in the window's gui immediately
		-- -> need to send updated mouse state below so that click is generated in that window's events.lua
		win.send_mouse_update = true 

		last_active_win = win
	end


	-- forward (filtered, modified) events to active window
	-- vertatim forwards also happen in _subscribe_to_events
	-- only need to send low-level device data -- click,tap etc is generated from them
	
	-- modified mouse position or mouse button
	if (win and win.proc_id) then
		if (mx ~= last_mx or my ~= last_my or mb ~= last_mb or win.send_mouse_update) then

			last_input_activity_t = time()

			--printh("mouse event "..pod{proc_id = win.proc_id, mx, my, mb})

			win.send_mouse_update = nil

			-- every window can read the mouse position, but only the active window can read mouse button state.
			-- dorky iterator for ws_gui and tooltray_gui
			local pointer_el = head_gui:get_pointer_element()
			if (@0x547c > 0) pointer_el = win -- video mode set -> assume pointing at active window
			for i=1,#ws_gui.child + #tooltray_gui.child do
				local win2 = i <= #ws_gui.child and ws_gui.child[i] or tooltray_gui.child[i - #ws_gui.child]

					send_message(win2.proc_id, {event="mouse",dx = mdx, dy = mdy, mx_abs = mx, my_abs = my, mx = mx-win2.sx, my=my-win2.sy, 
						-- only active window is allowed to read mouse button (title bar / resizer widget doesn't count)
						mb = (win == win2 and win == pointer_el) and mb or 0
					})
			end

		end
		last_mx, last_my, last_mb = mx, my, mb
	end


	-- reset; so that e.g. alt + left doesn't bring up tooltray menu
	if (keyp("alt")) then
		used_alt_navigation = false
	end


	-- to do: terminal AND desktop filenav(!) should be allowed to capture enter
	-- a little different from capture_escapes ~ window can just have pauseable property (turn off to capture enter)
	-- wallpaper should never be pausible
	-- awin.fullscreen and not awin.pwc_output and not awin.desktop_filenav and not awin.wallpaper) then 

	if (awin and awin.pauseable) then

		update_window_paused_menu(awin)

	end

	if (keyp("escape")) then

		-- look for haltable process
		-- (assumes there is only one)
		local width, height = _get_process_display_size(haltable_proc_id)

		if (modal_gui) then
			dismiss_modal()
		elseif (awin and awin.paused) then
			awin.paused = false
			send_message(awin.proc_id, {event = "unpause"})
		elseif (get_active_window() and get_active_window().autoclose) then
			close_window(get_active_window(), true) -- e.g. about / settings
		elseif toolbar_y_target > 0 then
			-- close tooltray if open
			toolbar_y_target = 0
		elseif infobar_y_target < 270 then
			-- close infobar if open
			hide_infobar()
		elseif (get_active_window() and get_active_window().capture_escapes) then
			-- let active window handle it
		elseif (width and width > 0) then 
			-- stop haltable process
			send_message(haltable_proc_id, {event="halt"})
			haltable_proc_id = false
		else
			-- toggle between output / last workspace
			if (ws_gui.style == "fullscreen") then
				set_workspace(last_non_fullscreen_workspace or last_desktop_workspace)
			elseif (awin and awin.pwc_output) then
				-- back to editor
				set_workspace(last_non_desktop_workspace or last_fullscreen_workspace)
			else
				set_workspace(last_fullscreen_workspace)
			end
		end

	end

	-- keyboard control
	if (key("alt")) then
		if (keyp("left")) then set_workspace(workspace_index - 1) used_alt_navigation = true end
		if (keyp("right")) then set_workspace(workspace_index + 1) used_alt_navigation = true end

	end

	-- toggle fullscreen

	if (key("alt") and key("enter") and not last_enter_key_state) then		
		sdat.fullscreen = not sdat.fullscreen
		store("/appdata/system/settings.pod", sdat)
		-- clear key buffer (avoid "enter" being sent to text editor)
		readtext(true)
	end
	last_enter_key_state = key("enter")



	local dtab_index = 0

	if (key("ctrl") and keyp("tab")) dtab_index = key("shift") and -1 or 1

--[[
	-- don't need yet -- no flipping through windows, and ctrl-tab is nicer for tabs.
	if (key("alt") and keyp("up")) dtab_index = -1
	if (key("alt") and keyp("down")) dtab_index = 1
]]

	if (dtab_index != 0) then
		local tab = get_workspace_tabs()

		-- to do: for windows, need to keep a list of windows in order they are visited and use that
		-- perhaps only count windows with z==0 or something? don't want desktop, filenav, birds

		-- if (#tab < 2) tab = ws_gui.child -- cycle through windows instead;  

		for i=1,#tab do
			if (tab[i].is_active) then

				j = i + (#tab + dtab_index)
				while (j > #tab) do j = j - #tab end

				set_active_window(tab[j])

			end
		end

	end

	-- to do: while dragging items, switch between active window
	-- causes gui logic complexity but is nice and should drive gui logic to be cleaner
	-- annoying case: drag files out and back in to a window -> spurious events cause selection to start
		-- maybe just up to wm to manage which events get through while dragging files
	-- update: ah.. maybe switching window focus is not desired behaviour anyway
	-- -> light provisional version: just bring to front for a little visual feedback
	if (dragging_items) then
		local win2 = head_gui:el_at_xy(mx, my)
		if (win2) then
			if (win2.is_window_bar) win2 = win2.parent
			win2:bring_to_front()
		end
	end

--[[
	if (dragging_items) then
		local win2 = head_gui:el_at_xy(mx, my)
		if (win2 and win2.is_window_bar) win2 = win2.parent
		if (win2 ~= get_active_window()) then
			set_active_window(win2)
			send_message(win2.proc_id, {event = "block_mouse_events"})  --  need to block events until mb == 0
		end
	end
]]

	-- drop

	if (mb == 0 and dragging_items) then

		-- send a message to whatever window the cursor is over
		local win2 = head_gui:el_at_xy(mx, my)

		-- titlebar counts! (can drag and drop into titlebar, put sticker on titlebar)
		if (win2 and win2.is_window_bar) win2 = win2.parent

		--printh("dropping into proc: "..tostr(win2.proc_id))
		
		if (win2 and win2.proc_id) then

			-- first, window manager might consume some of the items (stickers)
			
			for i=1,#dragging_items do
				local item = dragging_items[i]
				--printh("item: "..pod(item))
				if (item.pod_type == "sticker") then
					if (type(win2.stickers) != "table") win2.stickers = {} 
					add(win2.stickers, {
						x = mx - win2.x,
						y = my - win2.y,
						bmp =  item.icon -- lazy change of meaning; the icon /is/ the content
					})
				end
			end

			-- send to window for processing
			send_message(win2.proc_id, {event="drop_items", 
				items = dragging_items,
				from_proc_id = dragging_items_from_proc_id,
				dx = mx - start_mx, dy = my - start_my, 
				mx = mx - win2.sx, 
				my = my - win2.sy
			})
		end

		dragging_items = nil
	end


	-- update
	if (not screensaver_proc_id) then
		head_gui:update_all()
	end

	-- store state of windows data
	-- store("/ram/shared/windows.pod", generate_windat()) -- commented during dev because noisy

	if (sdat.sparkles) then
		update_sparkles()
	else
		init_sparkles() -- reset. to do: existing sparkles should be allowed to live out their life? anti-module pattern though!
	end

end


-- to do: could maintain a lookup
-- to do: tooltray_gui windows
--local 
function get_window_by_proc_id(proc_id)

	for i=1,#workspace do
		for j=1,#workspace[i].child do
			if workspace[i].child[j].proc_id == proc_id then
				return workspace[i].child[j], i
			end 
		end
	end

	if (tooltray_gui) then
		for i=1,#tooltray_gui.child do
			if (tooltray_gui.child[i].proc_id == proc_id) return tooltray_gui.child[i], -1
		end
	end

	return nil -- none
end

function remove_workspace(index)
	for i=index, #workspace do
		workspace[i] = workspace[i+1]
	end
	set_workspace(ws_gui)
end

-- close window here so that don't invalidate window iterator
on_event("close_window", 
	function(msg)

		for i=1,#workspace do
			local pos = 1
			local num = #workspace[i].child
			
			for j=1,num do
				if workspace[i].child[j].proc_id == msg.proc_id then
					-- remove from list of tabs
					del(workspace[i].tabs, workspace[i].child[j])
				else
					-- shunt -- keep only processes that don't match those to be removed
					workspace[i].child[pos] = workspace[i].child[j]					
					pos = pos + 1
				end
			end

			-- clear end
			while (pos <= num) do
				workspace[i].child[pos] = nil
				pos = pos + 1
			end
		end

		generate_head_gui()

		-- finally, kill the process
		_kill_process(msg.proc_id)
	end
)



function choose_workspace(attribs)

	if (attribs.workspace == "current") return ws_gui

	if (attribs.workspace == "tooltray") return tooltray_gui
	
	-- explicitly requested a new workspace (e.g. New Desktop from toolbar right click menu)
	if (attribs.workspace == "new") return nil

	-- by workspace id
	if (type(attribs.workspace) == "number") then
		for i=1,#workspace do
			if (workspace[i].index == attribs.workspace) return workspace[i]
		end
	end

	---- no particular workspace requested --> choose cased on attributes

	-- wallpaper should open in same workspace (when new workspace was not requested)
	if (attribs.wallpaper) return ws_gui

	-- tabbed window get workspace running same program (to do)
	if (attribs.tabbed) then

		for i=1,#workspace do
			if (workspace[i].style == "tabbed" and workspace[i].prog == attribs.prog) then
				return workspace[i]
			end
		end

		return nil
	end

	-- fullscreen window gets new workspace
	if (attribs.fullscreen) return nil

	-- otherwise: desktop app
	return last_desktop_workspace

end

on_event("app_menu_item", function(msg)
	proc_menu[msg._from] = proc_menu[msg._from] or {}
	local menu = proc_menu[msg._from]
	-- look for existing item by label
	local pos = #menu + 1 -- default: add new
	for i=1,#menu do
		if (menu[i].id == msg.attribs.id) pos = i
	end
	
	menu[pos] = msg.attribs
	update_app_menu_item(menu[pos])
end)



on_event("set_window", function(msg)

--	printh("set_window: "..pod(msg))

	if (msg._from <= pid()) return -- safety: don't create window for window manager

	local win = get_window_by_proc_id(msg._from)
	local attribs = msg.attribs or {}
	local target_ws = nil
	local old_win = nil
	local old_location = win and win.location or nil
	

	-- creating cart output window:  replace any existing output window

	if not win and msg.attribs.pwc_output then
		for i=1,#workspace do
			for j=1,#workspace[i].child do
				if (workspace[i].child[j].pwc_output) then
					-- match: replace fullscreen output when running fullscreen program / window when running windowed
					if (attribs.fullscreen == workspace[i].child[j].fullscreen or
						not attribs.fullscreen and not workspace[i].child[j].fullscreen) then 
						old_win = workspace[i].child[j]
						close_window(old_win, true)
						_kill_process(old_win.proc_id) -- need to kill explicitly here because pwc_output window is immortal
						target_ws = workspace[i]
					end
				end
			end
		end
	end

	

	-- if no existing window, create it
	if not win then

		--printh("creating window "..pod(attribs))

		-- 1. find workspace for it
		if (not target_ws) target_ws = choose_workspace(attribs)

		-- 2. if no existing workspace, create it
		if (not target_ws) then
			target_ws = create_workspace_1(msg._from, attribs)
		end

		-- 3. create the window

		-- if tooltray, force fixed position and frameless
		if (target_ws == tooltray_gui) then
			attribs.has_frame  = false
			attribs.moveable   = false
			attribs.resizeable = false
		end

		-- use a copy of attribs -- create_window() adds gui stuff, and want to iterate over original below
		local attribs_1 = unpod(pod(attribs))
		win = create_window(target_ws, attribs_1)

		

		-- if position is specified and has frame, should stay inside
		if (attribs.has_frame) then
			if (attribs.x) attribs.x = mid(0, attribs.x, 480 - attribs.width)
			if (attribs.y) attribs.y = mid(24, attribs.y, 270 - attribs.height)
		end

		-- 4. set starting window attributes. guess a title
		win.proc_id = msg._from

		local segs1 = split(attribs.prog,"/",false) or {}
		win.title = attribs.title or segs1[#segs1] or "proc_"..msg._from

		-- 4.a: when present working cart output, replace existing window at same position
		if (old_win) then
			win.x = old_win.x
			win.y = old_win.y
		end

		-- 5. add to tabs
		if (msg.attribs.tabbed) then
			add(target_ws.tabs, win)
		end

		-- 6. show in workspace if requested
		if (msg.attribs.show_in_workspace) then
			previous_workspace = ws_gui
			set_workspace(target_ws)
			target_ws.active_window = win -- give focus immediately
		end

		-- 7. give focus immediately when requested (autoclose implies should start with focus)
		if (msg.attribs.give_focus or msg.attribs.autoclose) then
			target_ws.active_window = win -- give focus immediately
		end

		-- 8. do some validation 
		-- was removed for 0.1.0f but caused [no workspaces] bug which seems to happen frequently but couldn't reproduce yet. race condition?
		-- to do: what is actually responsible for ensuring a valid workspace? should it really happen here?
		local workspace_index1 = mid(1, workspace_index, #workspace)
		if (workspace_index ~= workspace_index1 or ws_gui ~= workspace[workspace_index1]) then
			set_workspace(workspace_index1)
		end


		generate_head_gui()

	end

	
	-- modify / set attributes
	-- these are requested by program itself, so allowed to disregard restrictions in x,y (.moveable), width,height (.resizeable)

	for k,v in pairs(attribs) do
		win[k] = v
	end

	if (attribs.icon) then
		proc_icon[msg._from] = attribs.icon

		-- to do: update workspace button icon
		if (ws_gui and ws_gui.head_proc_id == msg._from) then
			ws_gui.icon = win.icon
			--printh("updating icon "..pod(win.icon))
		end
	end


	-- when changing location or creating new window, apply unique location logic:
	-- open in existing process where possible and optionally show in workspace
	if (attribs.unique_location and old_location ~= win.location) then

		-- printh("set_window change of location: "..pod{old_location, win.location})

		-- kill self if another window open with same location ** using same program **
		for i=1,#workspace do
			for j=1, #workspace[i].child do
				local win2 = workspace[i].child[j]
				if (win2 ~= win and not win2.closing and
					type(win.location) == "string" and type(win2.location) == "string" and
					win.location:path() == win2.location:path() and  -- same location (disregarding the hloc part after the #)
					win.prog     and win.prog     == win2.prog    -- editing using same program
				) then
				
					-- kill self!  -- to do: don't create the window in the first place
					_kill_process(win.proc_id)
					win.hidden = true

					-- kill newly created workspace if created one for this
					if (target_ws and #target_ws.child == 0) then
						del(ws_gui, target_ws)
					end

					-- go to other window
					if (win.show_in_workspace) then
						set_workspace(i)
						win2:bring_to_front()
					end

					-- tell win2 about the hash location
					send_message(win2.proc_id, {event = "jump_to_hloc", hloc = win.location:hloc()})
					
					-- file wranger thing
					notify("editing "..win.location.." using existing process")

					break -- iteration invalid?
				end
			end
		end
	end

	-- create wallpaper

	if (msg.attribs.wallpaper) then
		-- kill old wallpaper
		for i=1,#target_ws.child do
			if (target_ws.child[i].wallpaper and target_ws.child[i] != win) then
				-- send_message(pid(), {event="close_window",proc_id = target_ws.child[i].proc_id}) -- kill next frame
				_kill_process(target_ws.child[i].proc_id)
				--send_message(2, {event="kill_process", proc_id=target_ws.child[i].proc_id})
			end
		end

	end

	-- sign of life from process -- proof that finished resetting
	win.resetting = nil
	
	-- not here -- messes up dragging
	--generate_head_gui()

end)

-- program can ask window manager to move self by dx, dy
-- useful for implementing alternative title bar (drag self)
-- to set absolute x,y: use set_window
on_event("move_window", function(msg)
	local win = get_window_by_proc_id(msg._from)

	if (msg.dx) win.x += msg.dx
	if (msg.dy) win.y += msg.dy

end)


on_event("set_haltable_proc_id",
	function(msg)
		haltable_proc_id = msg.haltable_proc_id
	end
)

-- to do: nicer name for this; "log_message"?
on_event("user_notification",
	function(msg)
		-- printh("##################### "..pod(msg))
		user_notification_message = msg.content
		user_notification_message_t = time()

		-- log it in infobar
		-- send_message(3, {event="log", content = msg.content})

	end
)

--[[
	-- used by util/save.lua
	-- brute force save of anything editing cart files
]]
on_event("save_working_cart_files",
	function(msg)
		for i=1,#workspace do
			for j=1, #workspace[i].child do
				local win = workspace[i].child[j]
				if (win.location and sub(fullpath(win.location), 1, 10) == "/ram/cart/") then
					send_message(win.proc_id, {event="save_file"})
				end
			end
		end
	end
)

on_event("save_open_locations_metadata",
	function(msg)
		save_open_locations_metadata()
	end
)





--[[
	-- used by util/load.lua
	-- close any programs that are editing carts
]]
on_event("clear_project_workspaces",
	function(msg)
		for i=1,#workspace do
			local num = #workspace[i].child
			-- close / kill all windows under that workspace
			for j=1, #workspace[i].child do
				local win = workspace[i].child[j]
				if (win.location and string.sub(fullpath(win.location), 1, 10) == "/ram/cart/") then
					close_window(workspace[i].child[j], true)
					num -= 1
				end
			end
		end
		generate_head_gui()
	end
)


on_event("dock_toolbar",
	function(msg)
		-- to do: should modify the workspace that the window belongs to
		ws_gui.show_toolbar = msg.state
	end
)


on_event("drag_items",
	function(msg)
		-- to do: should modify the workspace that the window belongs to
		dragging_items = msg.items
		if (dragging_items) then
			dragging_items_from_proc_id = msg._from
			local win = get_window_by_proc_id(msg._from)
			for i=1,#dragging_items do
				local item = dragging_items[i]
				item.x = (item.x or 0) + win.sx
				item.y = (item.y or 0) + win.sy
			end
		end
	end
)


on_event("set_wallpaper",
	function (msg)

		-- kill existing desktop process

		--local wallpaper_win = last_desktop_workspace.child[1]
		--local wallpaper_win = ws_gui.child[1]

		--_kill_process(last_desktop_workspace.child[1]) -- test

		-- works
		create_process(msg.wallpaper, {window_attribs = { wallpaper = true, workspace = "current"}})

		-- why doesn't this work?
--		create_process(msg.wallpaper, {window_attribs = { wallpaper = true, workspace = "current"}})

		
	end
)

on_event("test_screensaver",
	function(msg) 
		test_screensaver_t0 = time()
	end
)

on_event("toggle_app_menu",
	function(msg)
		toggle_app_menu(msg.x, msg.y, get_window_by_proc_id(msg.proc_id))
	end
)


function save_open_locations_metadata()
	-- store all cart file locations /ram/cart/.info.pod

	local ws_info = {}
	for i=1,#workspace do
		for j=1, #workspace[i].tabs do
			local tt = workspace[i].tabs[j]

			-- add tab if a cart file (store relative to /ram/cart/)

			if sub(fullpath(tt.location), 1, 10) == "/ram/cart/" then

				-- printh("save_open_locations_metadata location: "..pod(tt.location))

				-- is cart file
				add(ws_info,{
					workspace_index = i,                    -- probably can't use but might be handy to group files
					location = sub(tt.location, #"/ram/cart" + 2)   -- store relative to /ram/cart/ (+2 to skip the /)
				})

			end
		end
	end

	-- metadata is normally not very large
--	printh("@@ storing workspace metadata: "..pod(ws_info))
	store_metadata("/ram/cart", {workspaces = ws_info})

end


function dismiss_modal()
	if (modal_gui) modal_gui:detach()
	modal_gui = nil
end


function create_modal_gui()

	modal_gui = head_gui:attach{
		x = 0, y = 0, width = 480, height = 270,
		--draw = function() rectfill(0,0,480,270,8) end, -- debug
		click = dismiss_modal
	}

	return modal_gui
end

function close_workspace(ws_index, force)
	local ws = get_workspace(ws_index)

--	if (ws.immortal and not force) return

	if (ws) then
		for i=1,#ws.child do
			_kill_process(ws.child[i].proc_id)
		end
	end

	-- fix workspace index; when delete current, hop to left unless already at left-most
	if (ws_index <= workspace_index and workspace_index > 1) workspace_index -= 1

	deli(workspace, ws_index)
	set_workspace(workspace_index)
end




function toggle_workspace_menu(x, y, ws_index)

	local pulldown = create_modal_gui():attach_pulldown{
		is_app_menu = true,
		x = x, y = y,
		width = 100, 
		ws_index = ws_index,
		onclose = dismiss_modal
	}

	pulldown:attach_pulldown_item
	{
		label = "\^:1c3e6b776b3e1c00 Close Workspace", 
		cursor="pointer",
		action = function()
			close_workspace(ws_index)

		end
	}

end


-- update the single label of an appmenu item rather than regenerating the interface on change
function update_app_menu_item(ii)
	if (not app_menu_pulldown) return
	for i=1,#app_menu_pulldown.child do
		if (app_menu_pulldown.child[i].id == ii.id) then
			app_menu_pulldown.child[i].label = ii.label
		end
	end
end

function toggle_app_menu(x, y, win)

	local win = win or get_active_window()

	if (not win) return

	-- app menu is already open
	if (modal_gui and modal_gui.child[2] and modal_gui.child[2].is_app_menu) then
		modal_gui = nil
		return
	end

	-- empty workspace

	if (#ws_gui.child == 0) return


	local mm = {}

	x = mid(0,x,480-142)
	y = max(0,y)


	local pulldown = create_modal_gui():attach_pulldown{
		is_app_menu = true,
		x = x, y = y,
		width = 142, -- to do: be adaptive when drawing
		onclose = dismiss_modal
	}

	app_menu_pulldown = pulldown

	-- add about item // to do: get icon & title from .p64 when create window (can be default title too)

	-- to do: generate icon from win.icon

	add(mm, {icon = win.icon, label = "About "..win.prog:basename(), action = function() 
		create_process("/system/apps/about.p64", {prog=win.prog, window_attribs={workspace="current", autoclose = true}}) end})

	-- userland items created by menuitem()

	local menu = proc_menu[win.proc_id]

	if (menu and #menu > 0) then

		add(mm, {divider=true})

		for i=1,#menu do

			if (menu[i].label) then
				local item = menu[i]
				local pulldown_item = unpod(pod(item)) -- copy all attributes

				--printh("pulldown item "..pod(item))
				pulldown_item.action = function(b)
					send_message(win.proc_id, {event="menu_action", id=menu[i].id, b=b})
				end

				add(mm,pulldown_item)
			end
		end

	end

	-- window management items at bottom

	

	-- is a tab
	if (win.height == 270) then -- hack: window is fullscreen file navigator (desktop)
		-- no close
	elseif (win.sy < 12) then
		add(mm, {divider=true})
		add(mm, {label="\^:1c3e6b776b3e1c00 Close Tab", action = function() close_window(win, true) end})
	else
		add(mm, {divider=true})
		add(mm, {label="\^:1c3e6b776b3e1c00 Close Window", action = function() close_window(win, true) end})
	end


	for i=1,#mm do
		mm[i].cursor = "pointer"
		pulldown:attach_pulldown_item(mm[i])
	end


end

function toggle_picotron_menu()

	if (modal_gui and modal_gui.child[2] and modal_gui.child[2].is_pictron_menu) then
		modal_gui = nil
		return
	end

	
	----------------------------------------
	-- pulldown
	----------------------------------------

	-- to do: populate some of this from a configurable shortcuts list
	-- could just look for shortcuts in /appdata/system/shortcuts

	local item =
	{
		{"\^:3f7f5077057f7e00 About Picotron", function() create_process("/system/apps/about.p64", 
			{prog="/system",window_attribs={workspace="current",  autoclose = true}}) end},
		"---",

		{"\^:307f3000067f0600 System Settings",	function() create_process("/system/apps/settings.p64", 
			{prog="/system",window_attribs={workspace="current", autoclose = true}}) end},

--		{"\^:3f7f5077057f7e00 New Desktop", function() end},

--[[	
		"\^:fec7838383c7fe00\^:1f3f3f3f3f3f1f00\-f Audio",
		"\^:fec7838383c7fe00\^:1f3f3f3f3f3f1f00\-f Fullscreen",
		"\^:fec7838383c7fe00\^:1f3f3f3f3f3f1f00\-f Battery Saver",
]]

		{"\^:7f77777f777f0301 Show Messages", show_reported_error},

		"---",

--		{"\^:00387f7f7f7f7f00 Apps", function() create_process("/system/apps/filenav.p64", {argv={"/apps"}, window_attribs={show_in_workspace=true}}) end},
		{"\^:00387f7f7f7f7f00 Files", function() create_process("/system/apps/filenav.p64", {argv={"/"}, window_attribs={show_in_workspace=true}}) end},
		{"\^:7f7d7b7d7f083e00 Terminal", function() create_process("/system/apps/terminal.lua", {window_attribs={show_in_workspace=true}}) end},
--		{"\^:00387f7f7f7f7f00 Host Desktop", function() _signal(65) end},

		--[[ underlay test; -10 means always under regular windows
		{"\^:7f7d7b7d7f083e00 Terminal2", function() create_process("/system/apps/terminal.lua", 
			{window_attribs={moveable=false,width=100,height=100,x=50,y=50,z=-10}}) end},
		--]]

--[[
		-- later (using filenav intention); use load / save commands for now

		"---",
		"\^:00ff8181ffc17f00 Load Cartridge",
		-- "Save Cartridge  (Ctrl-S)",  --  can show shortcut in message bar
		"\^:00ff8181ffc17f00 Save Cartridge",
		"\^:00ff8181ffc17f00 Save Cartridge As",
		"\^:1c367f7777361c00 Cartridge Info",
]]

		"---",
		 -- pop up menu: [Shutdown] [Reboot] [Cancel] 
		 -- perhaps show unsaved changes 
		 -- (checkbox: "discard unsaved changes" ~ once checked, buttons clickable)


		{"\^:1c22494949221c00 Reboot", function() send_message(2, {event="reboot"}) end},
		{"\^:082a494141221c00 Shutdown", function() send_message(2, {event="shutdown"}) end}
	}


	local pulldown = create_modal_gui():attach_pulldown{
		is_pictron_menu = true,
		x = 4, y = toolbar_y + 11,
		width = 122,
		onclose = dismiss_modal
	}
	
	for i=1,#item do
		if item[i] == "---" then
			pulldown:attach_pulldown_item{divider=true}
		elseif (type(item[i]) == "table") then
			pulldown:attach_pulldown_item{label=item[i][1], action = item[i][2]}
		else
			pulldown:attach_pulldown_item{label=item[i]}
		end
	end
	
	
end



