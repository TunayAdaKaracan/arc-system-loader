--[[pod_format="raw",created="2024-07-13 20:44:58",modified="2024-07-13 20:44:58",revision=0]]
include "gui.lua"

local all_os = ls("/systems")
local systems_data = fetch_metadata("/systems")
local selected_i = 1 -- fallback if system is no longer available

for i, os in all(all_os) do
	if systems_data.os == os then
		selected_i = i
	end
end

local timer = systems_data.timer or 5
local start = time()

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
