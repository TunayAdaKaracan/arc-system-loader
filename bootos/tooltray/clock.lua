--[[pod_format="raw",created="2024-03-10 04:01:54",revision=5]]

-- timezones not implemented yet! everything is stored/shown in GMT
show_date = false
show_local = true

function _draw()

	cls(0)
	local format = show_local and "%Y-%m-%d %H:%M:%S" or nil

	if show_date then
		print(date(format):sub(1,10),0,0,13)
	else
		print(date(format):sub(12),4,0,13)
	end

	print("\014"..(show_local and "local" or " gmt"),52,1,16)

	poke(0x547d,0xff) -- wm draw mask; colour 0 is transparent

end

function _update()
	mx,my,mb = mouse()
	if (mb > 0 and last_mb == 0) then
		if (mx > 48) then
			show_local = not show_local
		else
			show_date = not show_date
		end
	end

	last_mb = mb
end
