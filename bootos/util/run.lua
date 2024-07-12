--[[pod_format="raw",created="2023-00-01 20:00:59",modified="2024-04-25 01:04:50",revision=1]]

local argv = env().argv

if (#argv < 1) then
	print"hit ctrl-r!"
	exit(1)
end

--[[

cd(env().path)


show_in_workspace = true

for i = 1, #argv do

	if (argv[i] == "-b") then
		show_in_workspace = false
	else
		-- run
		
		local proc_id = create_process(
			fullpath(prog_name), 
			{
				print_to_proc_id = pid(),  -- tell new process where to print to
				argv = argv,
				path = pwd(), -- used by commandline programs -- cd(env().path)
				window_attribs = {show_in_workspace = show_in_workspace}
			}
		)
	)

	end
end

]]
