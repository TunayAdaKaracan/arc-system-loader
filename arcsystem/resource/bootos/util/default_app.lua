
local ext = env().argv[1]
local prog = env().argv[2]

if (type(ext) ~= "string" or not prog) then
	
	print("\f7usage: default_app ext path_to_program")
	print("\f6sets the default application to be used with a file extension.")
	print("\f6e.g.: default_app loop /apps/tools/loop_editor.p64")
	exit(0)
end

if (not fstat(prog)) then
	print("could not find "..prog)
end

prog = fullpath(prog)

local dat = fetch("/appdata/system/default_apps.pod")
if (type(dat) != "table") dat = {}
dat[ext] = prog
store("/appdata/system/default_apps.pod", dat)

print("set files of type \fe."..ext.."\f7 to be opened with \fe"..prog)
