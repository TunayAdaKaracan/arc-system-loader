--[[pod_format="raw",created="2024-05-28 08:10:08",modified="2024-05-28 08:13:55",revision=5]]
--[[

	events.lua
	part of head.lua

]]

do

	local _read_message = _read_message


	local message_hooks = {}
	local message_subscriber = {}
	local mouse_x = 0
	local mouse_y = 0
	local mouse_b = 0
	local wheel_x = 0
	local wheel_y = 0
	local locked_dx = 0
	local locked_dy = 0



	local ident = math.random()

	local key_state={}
	local last_key_state={}
	local repeat_key_press_t={}

	local frame_keypressed_result={}
	local scancode_blocked = {} -- deleteme -- not used or needed   //  update: maybe do? ancient sticky keys problem

	function mouse()
		return mouse_x, mouse_y, mouse_b, wheel_x, wheel_y -- wheel
	end

	--[[
		do_lock bits
			0x1 enable mouse (P8)       //  ignored; always enabled!
			0x2 mouse_btn    (P8)       //  mouse buttons trigger player buttons (not implemented)
			0x4 mouse lock   (P8)       //  lock cursor to picotron host window when set
			0x8 auto-unlock on mouseup  //  common pattern for dials (observed by gui.lua)
	]]
	function mouselock(do_lock, event_sensitivity, move_sensitivity)
		if (event_sensitivity) poke(0x5f28, mid(0,event_sensitivity*64, 255)) -- controls scale of deltas (64 == 1 per picotron pixel)
		if (move_sensitivity)  poke(0x5f29, mid(0,move_sensitivity *64, 255)) -- controls speed of cursor while locked (64 == 1 per host pixel)
		if (type(do_lock) == "number") poke(0x5f2d, do_lock)
		if (do_lock == true)  poke(0x5f2d, peek(0x5f2d) | 0x4)  -- don't alter flags, just set the lock bit
		if (do_lock == false) poke(0x5f2d, peek(0x5f2d) & ~0x4) -- likewise
		return locked_dx, locked_dy -- wheel, locked is since last frame
	end



	--[[

		// 3 levels of keyboard mapping:

		1. raw key names  //  key("a")
	
			"a" means the key to the right of capslock
			defaults to US layout, patched by /appdata/system/scancodes.pod
			example: tracker music input -- layout should physically match a piano

		2. mapped key names  // key("a")

			"a" means the key with "a" written on it
			e.g. the key to the right of tab on a typical azerty keyboard
			defaults to OS mapping, patched by /appdata/system/keycodes.pod
			example: key"f" to flip sprite horiontally should respond to the key with "f" written on it

		3. text entry  // readtext()

			"a" is a unicode string triggered by pressing a when shift is not held (-> SDL_TEXTINPUT event)
			ctrl-a or enter does not trigger a textinput event; need to read with mapped key names using key() + keyp()
			defaults to host OS keyboard layout and text entry method; not configurable inside Picotron [yet?]
	]]
	

	-- physical key names
	-- include everything from sdl -- might want to make a POS terminal; but later could define a "commonly supported" subset
	local scancode_name = {
	"", "", "", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", 
	"m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "1", "2", 
	"3", "4", "5", "6", "7", "8", "9", "0", "enter", "escape", "backspace", "tab", "space", "-", "=", "[", 
	"]", "\\", "#", ";", "'", "`", ",", ".", "/", "capslock", "f1", "f2", "f3", "f4", "f5", "f6", 
	"f7", "f8", "f9", "f10", "f11", "f12", "printscreen", "scrolllock", "pause", "insert", "home", "pageup", "delete", "end", "pagedown", "right", 
	"left", "down", "up", "numlock", "kp /", "kp *", "kp -", "kp +", "kp enter", "kp 1", "kp 2", "kp 3", "kp 4", "kp 5", "kp 6", "kp 7", 
	"kp 8", "kp 9", "kp 0", "kp .", "<", "menu0", "", "kp =", "", "", "", "", "", "", "", "f20", 
	"f21", "f22", "f23", "f24", "execute", "help", "menu1", "select", "stop0", "again", "undo", "", "", "", "find", "", 
	"", "", "", "", "", "kp ,", "kp = (as400)", "", "", "", "", "", "", "", "", "", 
	"", "", "", "", "", "", "", "", "", "alterase", "right alt", "stop1", "clear", "prior", "return", "separator", 
	"out", "oper", "clear / again", "crsel", "exsel", "", "", "", "", "", "", "", "", "", "", "", 
	"kp 00", "kp 000", "thousandsseparator", "decimalseparator", "currencyunit", "currencysubunit", "kp (", "kp )", "kp {", "kp }", "kp tab", 
		"kp backspace", "kp a", "kp b", "kp c", "kp d", 
	"kp e", "kp f", "kp xor", "kp ^", "kp %", "kp <", "kp >", "kp &", "kp &&", "kp |", "kp ||", "kp :", "kp #", "kp space", "kp @", "kp !", 
	"kp memstore", "kp memrecall", "kp memclear", "kp memadd", "kp memsubtract", "kp memmultiply", "kp memdivide", "kp +/-", "kp clear", 
		"kp clearentry", "kp binary", "kp octal", "kp decimal", "kp hexadecimal", "", "", 
	"lctrl", "lshift", "lalt", "lcommand", "rctrl", "rshift", "ralt", "rcommand"
	}



	local raw_name_to_scancode = {}

	for i=1,#scancode_name do
		local name = scancode_name[i]
		if (name ~= "") raw_name_to_scancode[name] = i
	end

	-- patch with /settings/scancodes
	-- e.g. store("/appdata/system/scancodes.pod", {lctrl=57}) to use capslock as lctrl

	local patch_scancodes = fetch"/appdata/system/scancodes.pod"
	if type(patch_scancodes) == "table" then
		for k,v in pairs(patch_scancodes) do
			raw_name_to_scancode[k] = v
		end
	end

	-------------------------------------------------------------------------
	--	name_to_scancodes:  default host OS default mapping
	--  each entry is a table of one or more scancodes that trigger it
	-------------------------------------------------------------------------

	local name_to_scancodes = {}

	for i=1,255 do
		local mapped_name = stat(302, i)
		if (mapped_name and mapped_name ~= "") then
			-- temporary hack -- convert from SDL names (should happen at lower level)
			mapped_name = mapped_name:lower()
			if (mapped_name:sub(1,7) == "keypad ") mapped_name = "kp "..mapped_name:sub(8)
			if (mapped_name:sub(1,5) == "left ") mapped_name = "l"..mapped_name:sub(6)
			if (mapped_name:sub(1,6) == "right ") mapped_name = "r"..mapped_name:sub(7)
			if (mapped_name == "return") mapped_name = "enter"
			if (mapped_name == "lgui") mapped_name = "lcommand"
			if (mapped_name == "rgui") mapped_name = "rcommand"
			if (mapped_name == "loption") mapped_name = "lalt"
			if (mapped_name == "roption") mapped_name = "ralt"

--			printh("mapping "..mapped_name.." to "..i.."    // ".._get_key_from_scancode(i))

			if (not name_to_scancodes[mapped_name]) name_to_scancodes[mapped_name] = {}

			add(name_to_scancodes[mapped_name], i)

		end
	end


	-- raw  scancode names that are not mapped to anything -> dummy scancode (simplify logic)
	for i=1,#scancode_name do
		if (scancode_name[i] ~= "") then
			if (raw_name_to_scancode[scancode_name[i]] == nil) raw_name_to_scancode[scancode_name[i]] = -i
		end
	end

	
	-- patch keycodes (can also overwrite multi-keys like ctrl)

	local patch_keycodes = fetch"/appdata/system/keycodes.pod"
	if type(patch_keycodes) == "table" then
		for k,v in pairs(patch_keycodes) do
			-- /replace/ existing table; can use keycodes.pod to turn off mappings
			if (type(v) == "table") then
				name_to_scancodes[k] = v
			else
				name_to_scancodes[k] = {raw_name_to_scancode[v] or v} -- can use raw name or scancode directly.
			end
			--printh("mapping keycode "..k.." to "..pod(name_to_scancodes[k]))
		end
	end

	-- scancodes map to themselves unless explicitly remapped
	-- (avoids an extra "or scancode" in get_scancode)

	for i=0,511 do
		name_to_scancodes[i]    = name_to_scancodes[i] or {i}
		raw_name_to_scancode[i] = raw_name_to_scancode[i] or i
	end

	-- faster lookup for lctrl, rctrl, lalt, ralt wm filtering combinations
	local lctrl = (name_to_scancodes.lctrl and name_to_scancodes.lctrl[1]) or -1
	local rctrl = (name_to_scancodes.rctrl and name_to_scancodes.rctrl[1]) or -1
	local lalt =  (name_to_scancodes.lalt  and name_to_scancodes.lalt[1])  or -1
	local ralt =  (name_to_scancodes.ralt  and name_to_scancodes.ralt[1])  or -1


	-- alternative names
	-- (if the name being aliased is unmapped, then inherit its dummy mapping)

	name_to_scancodes["del"]      = name_to_scancodes["delete"] -- 0.1.0b used del
	name_to_scancodes["return"]   = name_to_scancodes["enter"]   
	name_to_scancodes["+"]        = name_to_scancodes["="]
	name_to_scancodes["~"]        = name_to_scancodes["`"]
	name_to_scancodes["<"]        = name_to_scancodes[","]
	name_to_scancodes[">"]        = name_to_scancodes["."]


	-- super-keys that are triggered by a bunch of other keys
	-- common to want to test for "any ctrl" (+ picotron includes apple command keys as ctrl)

	function create_meta_key(k)
		local result = {}
		for i=1,#k do	
			local t2 = name_to_scancodes[k[i]]
			if (t2) then -- key might not be mapped to anything (ref: rctrl on robot)
				for j=1,#t2 do
					add(result, t2[j])
				end
			end
		end
		--printh("@@@ "..pod(k).."  -->  "..pod(result))
		return result
	end

	name_to_scancodes["ctrl"]  = create_meta_key{"lctrl",  "rctrl",  "lcommand", "rcommand"}
	name_to_scancodes["alt"]   = create_meta_key{"lalt",   "ralt"}
	name_to_scancodes["shift"] = create_meta_key{"lshift", "rshift"}
	name_to_scancodes["menu"]  = create_meta_key{"menu0",  "menu1"}
	name_to_scancodes["stop"]  = create_meta_key{"stop0",  "stop1"}


	-- is allowed to return a table of scancodes that a key is mapped to
	local function get_scancode(scancode, raw)
		local scancode = (raw and raw_name_to_scancode or name_to_scancodes)[scancode]
		--[[
		if (scancode_blocked[scancode]) then
			-- unblock when not down. to do: could do this proactively and not just when queried 
			if (key_state[scancode] != 1) scancode_blocked[scancode] = nil 
			return 0 
		end
		]]
		return scancode
	end

	--[[

		keyp(scancode, raw)

			raw means: use US layout; same physical layout regardless of locale.
			use for things like music keyboard layout in tracker

			otherwise: map via appdata/system/scancodes.pod (should be "kbd_layout.pod"?)

		-- frame_keypressed_result is determined before each call to _update()
		--  (e.g. ctrl-r shouldn't leave a keypress of 'r' to be picked up by tracker. consumed by window manager)

	]]

	function keyp(scancode, raw, depth)

--		if (scancode == "escape") printh("get_scancode(\"escape\"): "..get_scancode(escape))

		scancode = get_scancode(scancode, raw)

		if (type(scancode) == "table") then			
			
			if (#scancode == 1) then
				-- common case: just process that single scancode
				scancode = scancode[1]
			else
				if (depth == 1) return false -- eh?
				local res = false
				for i=1,#scancode do res = res or keyp(scancode[i], raw, 1) end
				return res
			end
		end

		-- keep returning same result until end of frame
		if (frame_keypressed_result[scancode]) return frame_keypressed_result[scancode]

		-- first press
		if (key_state[scancode] and not last_key_state[scancode]) then
			repeat_key_press_t[scancode] = time() + 0.5
			frame_keypressed_result[scancode] = true
			return true
		end

		-- repeat
		if (key_state[scancode] and repeat_key_press_t[scancode] and time() > repeat_key_press_t[scancode]) then
			repeat_key_press_t[scancode] = time() + 0.04
			frame_keypressed_result[scancode] = true
			return true
		end

		return false
	end
	
	
	function key(scancode, raw)

		scancode = get_scancode(scancode, raw)

		if (type(scancode) == "table") then
			local res = false
			for i=1,#scancode do 
				if (key_state[scancode[i]]) return true
			end
			return false
		end

		return key_state[scancode]
	end



	-- clear state until end of frame
	-- (mapped keys only -- can't be used with raw scancodes)
	function clear_key(scancode)

		scancode = get_scancode(scancode)

		if (type(scancode) == "table") then
			for i=1,#scancode do 
				frame_keypressed_result[scancode[i]] = nil
				key_state[scancode[i]] = nil
			end
			return
		end

		frame_keypressed_result[scancode] = nil
		key_state[scancode] = nil
	end

	
	local text_queue={}

	function readtext(clear_remaining)
		local ret=text_queue[1]

		for i=1,#text_queue do -- to do: use table operation
			text_queue[i] = text_queue[i+1] -- includes last nil
		end

		if (clear_remaining) text_queue = {}
		return ret
	end

	function peektext(i)
		return text_queue[i or 1]
	end

	-- when window gains or loses focus
	local function reset_kbd_state()
		--printh("resetting kbd")
		text_queue={}
		key_state={}
		last_key_state={}

		-- block all keys
		--[[
			scancode_blocked = {}
			for k,v in pairs(name_to_scancode) do
				scancode_blocked[v] = true
			end
		]]

	end


--[[
	deleteme -- don't need. app can just listen to gained/lost focus themselves. 
	local _window_has_focus = false

	function window_has_focus()
		return _window_has_focus
	end
]]
	
	local future_messages = {}

	--[[
		called once before each _update
	]]
	
	function _process_event_messages()

		frame_keypressed_result = {}

		wheel_x, wheel_y, locked_dx, locked_dy = 0, 0, 0, 0


--[[		for i=0,511 do
			last_key_state[i] = key_state[i]
		end
]]

		last_key_state = unpod(pod(key_state))

		local future_index = 1

		repeat
			
			local msg = _read_message()

			if (msg and msg._delay) msg._open_t = time() + msg._delay

			-- future messages: when _open_t is specified, open message at that time

			if (not msg and future_index <= #future_messages) then
				-- look for next future message that is ready to be received
				while (future_index <= #future_messages and future_messages[future_index]._open_t >= time()) do
					future_index += 1
				end
				msg = deli(future_messages, future_index)
			elseif (msg and msg._open_t and time() < msg._open_t) then
				-- don't process yet! put in queue of future messages
				add(future_messages, msg)
				msg = nil
			end

			
			if (msg) then

			--	printh(ser(msg))

				local blocked_by_hook = false

				if (message_hooks[msg.event]) then
					for i = 1, #message_hooks[msg.event] do
						blocked_by_hook = blocked_by_hook or message_hooks[msg.event][i](msg)
					end
				end

				if (not blocked_by_hook) then
					for i=1,#message_subscriber do
						blocked_by_hook = message_subscriber[i](msg)
						if (blocked_by_hook) then break end
					end

				end

				if (not blocked_by_hook) then

					-- 2. system

					if (msg.event == "mouse") then

						mouse_x = msg.mx
						mouse_y = msg.my
						mouse_b = msg.mb
						
					end

					if (msg.event == "mousewheel") then
						wheel_x += msg.wheel_x or 0
						wheel_y += msg.wheel_y or 0

					end

					if (msg.event == "mouselockedmove") then
						locked_dx += msg.locked_dx or 0
						locked_dy += msg.locked_dy or 0
					end

					if (msg.event == "keydown") then


						local accept = true

						if (pid() > 3) then
							if (key_state[lctrl] or key_state[rctrl]) then
								-- to do (efficiency) maintain a reverse lookup of keys to filter when ctrl is held
								if (msg.scancode == name_to_scancodes["s"][1]) accept = false
								if (msg.scancode == name_to_scancodes["6"][1]) accept = false
								if (msg.scancode == name_to_scancodes["7"][1]) accept = false
								if (msg.scancode == name_to_scancodes["0"][1]) accept = false
								if (msg.scancode == name_to_scancodes["tab"][1]) accept = false

							end

							if (key_state[lalt] or key_state[ralt]) then
								if (msg.scancode == name_to_scancodes["left"][1])  accept = false -- wm workspace flipping
								if (msg.scancode == name_to_scancodes["right"][1]) accept = false -- wm workspace flipping
								if (msg.scancode == name_to_scancodes["enter"][1]) accept = false -- host alt+enter
								if (msg.scancode == name_to_scancodes["tab"][1])   accept = false -- host alt+tab
							end
						end

						if (accept) key_state[msg.scancode] = 1
						--printh("@@ keydown scancode: "..msg.scancode)
					end

					if (msg.event == "keyup") then
						key_state[msg.scancode] = nil
					end

					if (msg.event == "textinput" and #text_queue < 1024) then
						if not(key"ctrl") then -- block some stray ctrl+ combinations getting through. e.g. ctrl+1
							text_queue[#text_queue+1] = msg.text;
						end
					end

					if (msg.event == "gained_focus") then
						--_window_has_focus = true -- deleteme
						reset_kbd_state()
					end

					if (msg.event == "lost_focus") then
						--_window_has_focus = false -- deleteme
						reset_kbd_state()
					end

					if (msg.event == "gained_visibility") then
						poke(0x547f, peek(0x547f) | 0x1)
					end

					if (msg.event == "lost_visibility") then
						if (pid() > 3) poke(0x547f, peek(0x547f) & ~0x1) -- safety: only userland processes can lose visibility
					end

					if (msg.event == "resize") then
						-- throw out old display and create new one. can adjust a single dimension
						if (get_display()) then
							-- sometimes want to use resize message to also adjust window position so that
							-- e.g. width and x visibly change at the same frame to avoid jitter (ref: window resizing widget)
							window{width = msg.width, height = msg.height, x = msg.x, y = msg.y}
						end
					end

				end
			end

		until not msg

		-- 0.1.0g: disable control keys when alt is held
		-- don't want ALTgr + 7 to count as ctrl + 7 (some hosts consider ctrl + alt to be held when ALTgr is held)
		if (key_state[lalt] or key_state[ralt]) then
			key_state[lctrl] = nil
			key_state[rctrl] = nil
		end


	end


	-----
	-- only one hook per event. simplifies logic.

	function on_event(event, f)
		if (not message_hooks[event]) message_hooks[event] = {}
		add(message_hooks[event], f)

		-- for file modification events: let pm know this process is listening for that file
		if (sub(event, 1, 9) == "modified:") then
			send_message(2, {
				event = "_subscribe_to_file",
				filename = sub(event, 10)
			})
		end
	end

	-- kernel space for now -- used by wm (jettisoned)
	function _subscribe_to_events(f)
		add(message_subscriber, f)
	end

end


