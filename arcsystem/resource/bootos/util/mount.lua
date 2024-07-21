--[[pod_format="raw",created="2023-27-22 05:27:04",modified="2023-30-22 05:30:21",revision=2]]
cd(env().path)

local target = env().argv[1]
local origin = env().argv[2]

if (not target or not origin) then
	print("mount target origin")
	exit(1)
end

if (fstat(target)) then
	print("target already exists: "..target)
	exit(1)
end

if (not fstat(origin)) then
	print("origin not found: "..origin)
	exit(1)
end

if (not fullpath(target)) then
	print("could not resolve target path")
	exit(1)
end

local kind = fstat(origin)

print("mounting "..kind.." "..origin.." at "..target)

mount(target, origin)
