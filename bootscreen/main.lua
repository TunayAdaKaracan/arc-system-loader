--[[pod_format="raw",created="2024-07-12 16:10:18",modified="2024-07-12 16:26:38",revision=91]]
all_os = ls("/systems")
selected_i = 1
timer = fetch_metadata("/systems").timer or 5
start = time()

function _draw()
	cls(0)
	for i, os in ipairs(all_os) do
		text_color = 7
		bg_color = 0
		if selected_i == i then
			text_color = 0
			bg_color = 7
		end
		
		rectfill(0, (i-1)*8, get_display():width(), i*8-1, bg_color)
		print(os, 2, (i-1)*8, text_color)
	end
end

function _update()
	if keyp("down") then
		selected_i = min(selected_i+1, #all_os)
	elseif keyp("up") then
		selected_i = max(selected_i-1, 1)
	elseif keyp("space") or time() - start > timer then
		store_metadata("/systems", {os=all_os[selected_i]})
		send_message(2, {event="reboot"}) -- reboot
	end
end