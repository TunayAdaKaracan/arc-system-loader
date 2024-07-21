--[[pod_format="raw",created="2024-47-08 23:47:10",modified="2024-04-05 14:04:42",revision=2]]
--[[

	edit a file

	choose an editor based on extension [and possibly content if needed]

	** never runs the file -- up to caller to manage that depending on context **

	used by:
		filenav.p64: double click on file
		load.lua: to restore workspace tabs

]]

cd(env().path)


local argv = env().argv
if (#argv < 1) then
	print("usage: edit filename")
	exit(1)
end

-- future: could be a list per extension (open a chooser widget)

local prog_for_ext = fetch("/appdata/system/default_apps.pod")

if (type(prog_for_ext) ~= "table") prog_for_ext = {}

prog_for_ext.lua   = prog_for_ext.lua   or "/system/apps/code.p64"
prog_for_ext.txt   = prog_for_ext.txt   or "/system/apps/notebook.p64"
prog_for_ext.pn    = prog_for_ext.pn    or "/system/apps/notebook.p64"
prog_for_ext.gfx   = prog_for_ext.gfx   or "/system/apps/gfx.p64"
prog_for_ext.map   = prog_for_ext.map   or "/system/apps/map.p64"
prog_for_ext.sfx   = prog_for_ext.sfx   or "/system/apps/sfx.p64"
prog_for_ext.pod   = prog_for_ext.pod   or "/system/apps/podtree.p64"
prog_for_ext.theme = prog_for_ext.theme or "/system/apps/themed.p64"


local show_in_workspace = true

for i = 1, #argv do

	if (argv[i] == "-b") then
		-- open in background
		show_in_workspace = false
	else

		filename = fullpath(argv[i])
		local prog_name = prog_for_ext[filename:ext()]


		if (fstat(filename) == "folder") then

			-- open folder / cartridge
			create_process("/system/apps/filenav.p64", 
			{
				argv = {filename},
				window_attribs = {show_in_workspace = show_in_workspace}
			})

		elseif (prog_name) then

			create_process(prog_name,
				{
					argv = {filename},
					
					window_attribs = {
						show_in_workspace = show_in_workspace,
						unique_location = true, -- to do: could be optional. wrangle also sets this.
					}
				}
			)

		else
			-- to do: use podtree (generic pod editor)
			print("no program found to open this file")

			notify("* * * file type not found * * *")
		end
	end

end
