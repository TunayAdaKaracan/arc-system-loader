--[[pod_format="raw",created="2024-07-13 20:44:58",modified="2024-07-15 13:10:43",revision=26]]
include "gui.lua"

all_os = ls("/systems")
systems_data = fetch_metadata("/systems")
selected_i = 1 -- fallback if system is no longer available.

for i, os in ipairs(all_os) do
	if systems_data.os == os then
		selected_i = i
	end
end

timer = systems_data.timer or 5
start = time()
any_input = false

function _draw()
	cls(0)
	gui:draw_all()
end

function _update()
	if keyp("down") then
		selected_i = min(selected_i+1, #all_os)
		any_input = true
	elseif keyp("up") then
		selected_i = max(selected_i-1, 1)
		any_input = true
	elseif keyp("space") or (time() - start > timer and not any_input) then
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