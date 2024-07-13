--[[pod_format="raw",created="2024-07-13 20:17:57",modified="2024-07-13 21:05:24",revision=22]]
-- Compiles all arcsystem and makes them ready to publish.

-- IMPORTANT !!!!!!
local PATH = "/dev" -- directory that contains contents of arc-system-loader repo


local function save(location)
	rm(location)
	create_process("/system/util/save.lua", {argv={location}})
end

local function empty_ram_cart()
	rm("/ram/cart")
	mkdir("/ram/cart")
end

local function move(src, dest)
	cp(src, dest)
	rm(src)
end

local function wait(tick)
	for i=1, tick do
		flip()
	end
end

-- Store ram contents in case there is a currently developed application.
mkdir("/ram/tempcart")
cp("/ram/cart", "/ram/tempcart")
print("Storing ram cart contents")

-- Empty Ram Cart for compilation
empty_ram_cart()

-- Copy boot.lua to /arcsystem/resource/boot.lua as well as /system/boot.lua
print("Reflecting boot.lua changes")
rm(PATH.."/arcsystem/resource/boot.lua")
rm("/system/boot.lua")
cp(PATH.."/boot.lua", PATH.."/arcsystem/resource/boot.lua")
cp(PATH.."/boot.lua", "/system/boot.lua")

-- bootscreen compilation
print("Bundling bootscreen")
cp(PATH.."/bootscreen", "/ram/cart")
save(PATH.."/bundled/arcselector.p64")

-- copy bootscreen to /arcsystem/resource/bootos/apps/arcselector.p64
print("Bundling bootscreen to bootos")
save(PATH.."/arcsystem/resource/bootos/apps/arcselector.p64")

-- move /arcsystem/bootos to /systems/.bootos
print("Copying /arcsystem/resource/bootos to /systems/.bootos")
rm("/systems/.bootos")
cp(PATH.."/arcsystem/resource/bootos", "/systems/.bootos")

wait(20)
empty_ram_cart()

-- compilation of arcsystem
print("Bundling arcsystem")
cp(PATH.."/arcsystem", "/ram/cart")
save(PATH.."/bundled/arcsystem.p64.png")
store_metadata(PATH.."/bundled/arcsystem.p64.png", fetch_metadata(PATH.."/arcsystem"))

wait(20)

-- Restore ram cart
print("Restoring ram cart")
cp("/ram/tempcart", "/ram/cart")
rm("/ram/tempcart")