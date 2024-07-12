--[[

	menuitem{
		id = 3,                   -- unique identifier. integer ids are used to sort items (otherwise in order added)
		label = "Foo",            -- user-facing label
		shortcut = "CTRL-O",      -- drawn right justified in menu
		greyed = false,           -- greyed out item (use for ---)
		action = function(b) end  -- callback on select -- b is the button pressed (left / right)
	}

]]

local _menu = {}

function menuitem(m, a, b)

	-- legacy pico-8 calling format
	if (a) then
		m = {
			id = m, -- integer position
			label = a,
			action = b
		}
	end

	_menu[m.id] = m

	send_message(3, {event = "app_menu_item", attribs = m})

end


-- default hooks
on_event("menu_action", function(msg)
	local item = _menu[msg.id]
	if (item and item.action) then
		item.action(msg.b)
	end
end)

