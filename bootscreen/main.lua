include "gui.lua"

all_os = ls("/systems")
selected_i = 1
timer = fetch_metadata("/systems").timer or 5
start = time()

function _draw()
	cls(0)
	gui:draw_all()
end

function _update()
	if keyp("down") then
		selected_i = min(selected_i+1, #all_os)
	elseif keyp("up") then
		selected_i = max(selected_i-1, 1)
	elseif keyp("space") or time() - start > timer then
		store_metadata("/systems", {os=all_os[selected_i]})
		
		-- if it is on type 2 setting, do not set bypass to true.
		-- Changing type 2 -> type 1 while bypass set to true will run the selected system immediatly.
		-- Prevents unwanted behaviour.
		if fetch_metadata("/systems").type == 1 then
			store_metadata("/systems", {bypass=true})
		end
		
		send_message(2, {event="reboot"})
	end
end
