--[[pod_format="raw",created="2024-03-10 04:01:54",modified="2024-03-10 04:04:33",revision=4]]

window(80,40) -- preferred size

function draw_eyeball(x, y, r)
	local mx, my, mb = mouse()

	local angle = atan2(mx - x, my - y)

	circfill(x, y, r, 7)
	circfill(x + cos(angle)*r/2, y + sin(angle)*r/2, r/2, 3)
	circfill(x + cos(angle)*r/2, y + sin(angle)*r/2, r/3, 1)
end

function _draw()

	local w, h = get_display():attribs()
	local r = min(w/2,h)

	cls(0)

	draw_eyeball(w*.25,h/2,r*.48)
	draw_eyeball(w*.75,h/2,r*.48)

	poke(0x547d,0xff) -- wm draw mask; colour 0 is transparent

end
