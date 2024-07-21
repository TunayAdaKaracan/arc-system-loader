--[[

	proof of concept: module that hooks into wm with update, draw callbacks

		** don't really want to invite code running in kernel though
		** and don't want to try to sandbox /within/ a lua state [yet?]

		how to specify callback draw / update order without modifying wm.lua?
		this file should return the module table, including a key that matches settings.pod item (or have own settings)
		
		// result: maybe this kind of thing should just run in a separate process as an overlay
		// expensive, but mostly used for silly things anyway? birds.p64
		// push to homogenous userland patterns as much as possible (see red notebook)

]]

local sparkle = {}

-- currently used to reset when option turned off / on
function init_sparkles()
	sparkle = {}
end


function make_sparkle(x,y)
	local mag = 0.5

	return add(sparkle, {
		x = x, y = y,
		dx = rnd(mag)-rnd(mag),
		dy = rnd(mag)-rnd(mag),
		t = 0, max_t = 40 + rnd(30),
		col = 8+rnd(8)
	})
end

local last_mx, last_my

function update_sparkles()

	local mx,my,mb = mouse()
	mx += 4 my += 4 -- fudge

	if (not last_mx) then
		last_mx, last_my = mx, my
	end

	local dx = mx - last_mx
	local dy = my - last_my

	last_mx, last_my = mx, my

	local steps = min(10, max(abs(dx), abs(dy)))

	if (steps > 1) steps \= 2 -- sparser trail is nicer

	if (steps >= 1) then
		dx /= steps
		dy /= steps
		for i=1,steps do
			make_sparkle(mx, my)
			mx += dx 
			my += dy
		end
	end

	for i=#sparkle,1,-1 do
		local s = sparkle[i]

		s.x += s.dx
		s.y += s.dy

		s.t += 1
		if (s.t >= s.max_t) del(sparkle, s)
		
	end

end

function draw_sparkles()
	for i=1,#sparkle do
		local s = sparkle[i]

		if (s.t > s.max_t - 15) then
			pset(s.x, s.y, 6)
		else
			circ(s.x, s.y, 1, s.col)
			pset(s.x, s.y, 7)
		end
	end
	
end

