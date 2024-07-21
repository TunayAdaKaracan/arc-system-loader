--[[pod_format="raw",created="2023-17-26 21:17:14",modified="2024-04-04 08:23:25",revision=6]]
cd(env().path)

local path0 = env().argv[1] or "."

-- to do: why is this resolving to / when directory no longer exists? maybe terminal is validating pwd?
path = fullpath(path0)

if (not path) then
	print("could not resolve path "..tostr(path0))
	exit(0)
end

local res=ls(path)

if (not res) then
	print("could not find path "..tostr(res))
	exit(0)
end


-- stat each file and show which ones are directories (except for .p64s)
for i=1,#res do

	if (string.sub(res[i],-4) ~= ".p64" and
		 string.sub(res[i],-8) ~= ".p64.rom" and
		 string.sub(res[i],-8) ~= ".p64.png"
		) then
		if (fstat(path.."/"..res[i]) == "folder") then res[i] = res[i].."/" end 
	end

end

if (res) then
	-- to do: pick cols that will fit display width
	-- easiest method: just start at and decrease until fits (or increase until doesn't fit)
	local cols = 2
	for i=1,#res,cols do
		local str=""
		for j=0, cols-1 do
			if (i+j <= #res) then
				local col = "6"
				if (sub(res[i+j],-4)==".lua") then col="c" end
				if (sub(res[i+j],-4)==".txt") then col="a" end -- documents: yellow
				if (sub(res[i+j],-4)==".pod") then col="9" end
				--if (sub(res[i+j],-4)==".png") then col="b" end -- images: green?
				--if (sub(res[i+j],-4)==".p64") then col="s" end

				if (
					string.sub(res[i+j],-4) ~= ".p64" and
					string.sub(res[i+j],-8) ~= ".p64.rom" and
					string.sub(res[i+j],-8) ~= ".p64.png"
				) then
					local attrib, size, mount_point = fstat(path.."/"..res[i+j])
					if (attrib == "folder") col = "e"
					if (mount_point) col = "b"
				end

				str = str .. "\f"..col..res[i+j]
				for k=0,(20 - #res[i+j]) do
					str = str .. " "
				end

			end
		end
		print(str)
	end
else
print("could not list")
end
