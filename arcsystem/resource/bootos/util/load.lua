--[[pod_format="raw",created="2024-03-14 19:41:44",modified="2024-03-18 19:25:51",revision=2]]
--[[
	load
		copy to /ram/cart
]]

cd(env().path)

local argv = env().argv
if (#argv < 1) then
	print("\f6usage: load filename -- can be file or directory")
	exit(1)
end


filename = argv[1]


-- load an earlier version of cartridge via anywhen

if (filename:find("@")) then

	filename, when = unpack(split(filename, "@", false))
	filename = fullpath(filename)

	-- expand when into full local time string
	
	local padding = "0000-01-01 00:00:00"
		
	if (when:find(":")) then
		-- time at start: put date at start
		local now_local = date("%Y-%m-%d %H:%M:%S")
		when = now_local:sub(1,11)..when
	end

	-- pad remaining time
	when ..= padding:sub(#when + 1)

	-- convert to UTC
	when = date(nil, when, stat(87))

	--...

	local loc = "anywhen:/"..filename.."@"..when
	print("fetching: "..loc)

	local a = fetch(loc)
	if (type(a) == "string") then
		-- switcheroony
		filename = "/ram/anywhen_temp."..filename:ext()

--		print("opening as "..filename)
		rm(filename)
		store(filename, a)
	else
		print("could not locate")
		exit(0)
	end

	
end


-- bbs cart?

if (filename:sub(1,1) == "#") then
	-- print("downloading..")
	local cart_id = filename:sub(2)
	local cart_png, err = fetch("https://www.lexaloffle.com/bbs/get_cart.php?cat=8&lid="..cart_id)  -- ***** this is not a public api! [yet?] *****
	--local cart_png = fetch("http://localhost/bbs/get_cart.php?cat=8&lid="..cart_id)

	if (err) print(err)

	if (type(cart_png) == "string" and #cart_png > 0) then
		print(#cart_png.." bytes")
		rm "/ram/bbs_cart.p64.png" -- unmount. deleteme -- should be unnecessary
		store("/ram/bbs_cart.p64.png", cart_png)

		-- switcheroony
		filename = "/ram/bbs_cart.p64.png"
	else
		print("download failed")
		exit(0)
	end
end


attrib = fstat(filename)
if (attrib ~= "folder") then
	-- doesn't exist or a file --> try with .p64 extension
	filename = filename..".p64"
	if (fstat(filename) ~= "folder") then
		print("could not load")
		exit(1)
	end
end


-- remove currently loaded cartridge
rm("/ram/cart")

-- create new one
local result = cp(filename, "/ram/cart")
if (result) then
	print(result)
	exit(1)
end

-- set current project filename

store("/ram/system/pwc.pod", fullpath(filename))


-- tell window manager to clear out all workspaces
send_message(3, {event="clear_project_workspaces"})



meta = fetch_metadata("/ram/cart")

if (meta and type(meta.runtime) == "number" and meta.runtime > stat(5)) then
	print("** warning: this cart was created using a future version of picotron.")
	print("** some functionality might be broken or behave differently.")
	print("** please upgrade to the latest version of picotron.")
end


if (meta) dat = meta.workspaces

--[[ deleteme
	dat = fetch("/ram/cart".."/.workspaces.pod")
	if (not dat) printh("*** could not find\n")
]]

-- legacy location;  to do: deleteme
if (not dat) then
	dat = fetch("/ram/cart/_meta/workspaces.pod")
	if (dat) printh("** fixme: using legacy _meta/workspaces.pod")
end

-- legacy location;  to do: deleteme
if (not dat) then
	dat = fetch("/ram/cart/workspaces.pod")
	if (dat) printh("** fixme: found /workspaces.pod")
end

-- at the very least, open main.lua if it exists
if ((type(dat) ~= "table" or #dat == 0) and fstat("/ram/cart/main.lua")) then
	dat = {{location="main.lua"}} -- relative to /ram/cart/
end

if (type(dat) == "table") then

	-- open in background (don't show in workspace)
	local edit_argv = {"-b"}

	for i=1,#dat do

		local ti = dat[i]
		local location = ti.location or ti.cproj_file -- cproj_file is dev legacy
		if (location) then
			add(edit_argv, "/ram/cart/"..location)
		end
	end

	-- open all at once
	create_process("/system/util/open.lua",
		{
			argv = edit_argv,
			pwd = "/ram/cart"
		}
	)

end

print("\f6loaded "..filename.." into /ram/cart")


