
cd(env().path)

if (not env().argv[1]) then
	print("usage: mkdir path")
	exit(1)
end
local path = env().argv[1]

if (fstat(path) == "folder") then
	print("directory already exists")
	exit(1)
end

if (fstat(path) == "file") then
	print("file already exists")
	exit(1)
end

err = mkdir(path)

if (err) then
	print(err)
end
