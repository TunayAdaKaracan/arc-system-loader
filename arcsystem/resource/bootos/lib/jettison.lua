--[[pod_format="raw",created="2023-14-26 21:14:41",modified="2023-14-26 21:14:41",revision=0]]
--------------------------------------------------------------------------------------------------------------------------------

-- **** jettison kernel functions before entering userland code
--[[

if (pid() > 3) then
	printh("----- globals at boot ------")
	local str = ""
	for k,v in pairs(_G) do
		if (sub(k,1,1) == "_" and #k > 3) then
			--str..= "local "..k.." = "..tostr(k).."\n"
			str..= k.." = nil\n"
		else
			-- keep
			--str..= k.."\n"
		end
	end
	printh(str)
end

]]

if (pid() > 3) then

	_draw_map = nil
	_fcopy = nil
	_store_metadata = nil
	_fdelete = nil
	_mkdir = nil
	_get_process_display_size = nil
	_kill_process = nil
	_get_clipboard_text = nil
	_apply_system_settings = nil
	_pod = nil
	_map_ram = nil
	_halt = nil
	_set_draw_target = nil
	_store = nil
	_set_spr = nil
	_open_host_path = nil
	_print_p8scii = nil
	_fetch_metadata = nil
	_get_process_list = nil
	_read_message = nil
	_unmap_ram = nil
	_ppeek4 = nil
	_ppeek = nil
	_blit_process_video = nil
	_req_clipboard_text = nil
	_set_clipboard_text = nil
	_fetch = nil
	_fetch_remote_result = nil
	_create_process_from_code = nil
	_run_process_slice = nil
	
	_subscribe_to_events = nil -- events.lua, only used by wm
	_superyield = nil

	-- commented: even pico-8 has tostring! is slightly different
	-- tostring = nil
	-- tonumber = nil

	_fetch_local = nil
	_fetch_remote = nil
	_fetch_anywhen = nil
	_store_local = nil
	_signal = nil
	_printh = nil


	-- needed by foot
	-- _process_event_messages = nil  
	-- _update_buttons = nil



end

--[[
if (pid() > 3) then
	printh("----- candidates for jettison ------")
	local str = ""
	for k,v in pairs(_G) do
		if (sub(k,1,1) == "_" and #k > 3) then
			str..= k.." = nil\n"
		end
	end
	printh(str)
end
]]

