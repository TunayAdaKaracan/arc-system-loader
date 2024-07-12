--[[pod_format="raw",created="2024-28-16 08:28:46",modified="2024-28-16 08:28:46",revision=0]]

last_update_t = 0
plist = {}

window(200,160)

function generate_gui()
	
	local item_h = 12

	gui = create_gui()
	local w,h = get_display():width(), get_display():height()
--	w -= 20 h -= 20

	container = gui:attach{x = 0, y = 0, width = w, height = h,
		draw = function(self)
			rectfill(0,0,self.width-1,self.height-1,7)
		end
	}
	content  = container:attach{
		x = 0, y = 0, width = w, height = #plist * item_h,

		draw = function(self, msg)
			for i=1,#plist do
				print(string.format("%4d %-20s %0.3f", plist[i].id, plist[i].name, plist[i].cpu), 2, (i-1)*item_h+2, 5)
			end			
		end,
		
	}

	function content:mousewheel(msg)
		if (key("ctrl")) then
			self.x += msg.wheel_y * 16 
		else
			self.y += msg.wheel_y * 16
		end

	end

	
	container:attach_scrollbars()

end


function _init()

	generate_gui()

end

function _update()

	local x,y,b = mouse()

	local last_num = #plist
	plist = fetch"/ram/system/processes.pod"


	if (b == 0) then -- to do: allow regenerating gui while dragging an element (scrollbar in this case)
		if (last_num ~= #plist) generate_gui()
		--if (t() - last_update_t >= 0.25) generate_gui()	last_update_t = t()
	end

	gui:update_all()
	

	
end

function _draw()
	gui:draw_all()

end

on_event("request_resize", function(msg)
	generate_gui()
end)



