--[[

	procman.lua

	Process Manager

	doesn't have much to do!
	process slices are run from the kernel mainloop

]]


function _update()

	-- to do: adjust process cpu allocations based on previous frame
	
end


on_event("kill_process", 
	function(msg)

		-- silentely refuse to kill system processes: kernel, process manager, window manager
		-- commented; fun to kill these processes! can have useful error screen when core processes have crashed

		-- if (msg.proc_id < 3) return

--		printh("killing process via message "..tostr(msg.proc_id))

		_kill_process(msg.proc_id)

	end
)

on_event("restart_process", 
	function(msg)
		_kill_process(msg.proc_id, 1)
		send_message(msg.proc_id, {event = "unpause"})
	end
)


on_event("open_host_path", 
	function(msg)
		_open_host_path(msg.path)
	end
)

-- placeholder; to do: allow communication by program name?
on_event("broadcast",
	function (msg)

		local pl = _get_process_list()

		for i=1,#pl do
			if (pl[i].id > 3) then
				send_message(pl[i].id, msg.msg)
			end
		end

	end
)

-- to do: care about who is asking!
on_event("shutdown",
	function()
		_signal(33)
	end
)

on_event("reboot",
	function()
		_signal(34)
	end
)

on_event("mount_host_desktop",
	function()
		_signal(65)
	end
)




