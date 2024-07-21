--[[

	infobar.lua


	each entry can have a location tied to it (double click to open that location)
		// handy for jumping to code in stack traces

]]



local logdat={
}


local infobar_is_visible = false

local gui = create_gui()
gui.width = 480
gui.height = 270


function get_show_infobar()
	--return #logdat > 0
	return infobar_is_visible
end

function clear_infobar()
	logdat = {}
end

function hide_infobar()
	infobar_is_visible = false
end

-- dorky name because show_infobar is used in wm -- to do: delete old logic and organise names 
function open_infobar()
	infobar_is_visible = true
end


function update_infobar()
	
	gui:update_all()

end


function generate_infobar_gui()

	gui = create_gui{
		-- position,size will be adjusted by window manager
		x=0, y=0, 
		width=480, height=270,

		draw = function(self, msg)

			rectfill(0, 0, self.width, 11, 7)
			rectfill(0, 12, self.width, self.height, 16)

			-- title
			print(logdat[1], 3, 2, 1)
			circ(474, 6, 2, 1)

			-- dummy text
			local yy = 16  -- don't write on the bar -- can leave that empty! active message is drawn separtely.
			local xx = 0

			local mx, my = mouse() -- screen space; relative to head_gui
			my -= gui.y            -- ..so need to adjust manually here

			-- printh("infobar: "..pod{msg.mx, msg.my, mx, my})

			--for i=2, 30 do -- to do: why does printing nil here cause a freeze?
			for i=2, #logdat do

				if (my and my >= yy-1 and my < yy + 10) then
					rectfill(0,yy-2,480,yy+9,10)
					hover_item = i
				end
				xx, yy = print(logdat[i], 3, yy, 6)				
			end
		
		end,

		-- ** don't need update --
		--update = gui_update,

		update = function(self, msg)
			--printh("infobar gui position: "..pod{gui.x, gui.y})
			--printh("msg: "..pod(msg))
		end,


		
		tap = function(self, e)

			-- close // to do: button
			if (e.mx > 460 and e.my < 12) hide_infobar() return

			local str = logdat[hover_item]
			if (type(str) != "string") return
			local pos = 1
			while (pos < #str and (sub(str,pos,pos) == "\t" or sub(str,pos,pos) == " ")) pos += 1

			-- 
			local pos1 = pos+1
			while (pos1 < #str and sub(str,pos1,pos1) ~= ":") pos1 += 1
			if (sub(str,pos1,pos1) == ":") then
				
				-- get number
				local pos2 = pos1+1
				while (pos2 < #str and sub(str,pos2,pos2) ~=  ":") pos2 += 1
				if (sub(str,pos2,pos2) == ":") then
					create_process("/system/util/open.lua",{
						argv = {sub(str, pos, pos1-1).."#"..sub(str, pos1+1, pos2-1)}
					}
				)

				end
			end

		end,

		drag = function(self,e)
			send_message(3, {event="drag_infobar", dy=e.dy})
		end
	}

	return gui

end

function infobar_init()
	return generate_infobar_gui()
end


--[[
on_event("log", function(msg)

	if (type(msg.content) == "string") then

		local strs = split(msg.content, "\n", false)

		for i=1,#strs do

			add(logdat, strs[i], 1)
			while(#logdat > 64) deli(logdat) -- trim

		end

		printh("** log (removeme -- deprecated) "..msg.content) 
	end

	--printh("@@@@@ infobar received log: "..pod(msg))

end)
]]

local last_reported_error_t = 0

on_event("report_error", function(msg)

	if (type(msg.content) == "string") then

		-- don't reset immediately after last error (want to see the first error. e.g syntax error causes runtime error)
		if (sub(msg.content,1,1) == "*" and time() > last_reported_error_t + 1) then
			logdat = {}
			msg.content = sub(msg.content, 2)

			show_reported_error()
			last_reported_error_t = time()
		end

		local strs = split(msg.content, "\n", false)

		for i=1,#strs do
			-- maximum: 20 entries
			if (#strs[i] > 0 and #logdat < 20) add(logdat, strs[i])
		end

		--add(logdat, msg.content)
		infobar_is_visible = true
	end

end)




