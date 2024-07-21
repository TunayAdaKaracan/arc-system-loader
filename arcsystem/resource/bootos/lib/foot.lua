--[[pod_format="raw",created="2024-03-11 18:02:01",modified="2024-04-23 11:47:10",revision=5]]
--[[
	foot.lua
]]

-- init first; might set window inside _init
-- only problem: no visual feedback while _init does a lot of work. maybe need to spin the picotron button gfx!
if (_init) then _init() end


--[[
	every program runs in headless until window() called, either
		- explicitly by program
		- automatically, when _draw exists (but window doesn't) just before entering main loop

	handle the second case here
]]


if (_draw and not get_display()) then

	-- create window (use fullscreen by default unless overridden by env().window_attribs)
	window()

end

if (pid() > 3) then
	on_event("pause",       function() poke(0x547f, peek(0x547f) |  0x4) end)
	on_event("unpause",     function() poke(0x547f, peek(0x547f) & ~0x4) end)
	on_event("toggle_mute", function() poke(0x547f, peek(0x547f) ^^ 0x8) end)
end

-- mainloop
-- only loop if there is a _draw or _update
-- logic here applies to window manager too!

-- printh("entering mainloop at cpu:"..flr(stat(1)/100).."%   mem:"..flr(stat(0)/1024).."k")

while (_draw or _update) do


	-- called once before every _update()  --  otherwise keyp() returns true for multiple _update calls
	_process_event_messages()


	if (peek(0x547f) & 0x4) > 0 and pid() > 3 then

		-- paused: nothing left to do this frame
		-- still need to process buttons though
		_update_buttons()
		flip(0x3)

	else

		-- set a hold_frame flag here and unset after mainloop completes (in flip) 
		-- window manager can decide to discard half-drawn frame. --> PICO-8 semantics
		-- moved to start of mainloop so that _update() can also be halfway through
		-- drawing something (perhaps to a different target) without it being exposed

		poke(0x547f, peek(0x547f) | 0x2)

		-- to do: process can be run in background when not visible
		-- @0x547f:0x1 currently means "window is visible", and apps only run when visible

		if (peek(0x547f) & 0x1) > 0 then

			-- always exactly one call to _update_buttons() before each _update() when it is defined (allows keyp to work)
			-- when _update is not defined, still call once per draw.
			_update_buttons()

			if (_update) then
				_update()

				local fps = stat(7)
				if (fps < 60) _process_event_messages() _update_buttons() _update()
				if (fps < 30) _process_event_messages() _update_buttons() _update()

				-- below 20fps, just start running slower. It might be that _update is slow, not _draw.
			end
		end


		if (_draw and (peek(0x547f) & 0x1) > 0) then

			_draw()

			flip() -- unsets 0x547f:0x2
		else
			-- safety: draw next frame. // to do: why is this ever 0 for kernel processes? didn't received gained_visibility message?
			if (pid() <= 3) poke(0x547f, peek(0x547f) | 0x1)

			flip() -- no more computation this frame, and show whatever is in video memory
		end
	end

end
