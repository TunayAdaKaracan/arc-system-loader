--[[pod_format="raw",created="2023-29-10 02:29:44",modified="2023-29-10 02:29:44",revision=0]]
cd(env().path)
local path = fullpath(env().argv[1] or ".")

if (not path) then
	print("could not resolve path")
	exit(1)
end


if (path:sub(1,5) == "/ram/" or path == "/ram") then
	print("can not open a ram folder on host")
	exit(1)
end

-- send a message to process manager
send_message(2, {event="open_host_path", path = path})
