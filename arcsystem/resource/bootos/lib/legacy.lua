--[[

	deprecated

]]

if (false) then

	function notify_user(...)
		printh("*** DELETEME (LEGACY): notify_user")
		return notify(...)
	end

	function log(...)
		printh("*** DELETEME (LEGACY): log")
		return notify(...)
	end


	function print_p8scii(...)
		printh("*** DELETEME (LEGACY): print_p8scii")
		return print(...)
	end

	function set_window_title(title, description, location)
		printh("*** DELETEME (LEGACY): set_window_title")
		window{title = title, description = description, location = location}
	end

	function set_window_icon(icon)
		printh("*** DELETEME (LEGACY): set_window_icon")
		window{icon = icon}
	end


	function set_window(...)
		printh("*** DELETEME (LEGACY): set_window")
		return window(...)
	end

	function create_window(...)
		printh("*** DELETEME (LEGACY): create_window")
		return window(...)
	end

	function create_tab(location)
		printh("*** DELETEME (LEGACY): create_tab")
		window{tabbed   = true}
	end

	function Gui(...)
		printh("*** DELETEME (LEGACY): Gui")
		return create_gui(...)
	end


	--[[
	get_key_pressed = keyp
	get_key_state = key
	]]

end

