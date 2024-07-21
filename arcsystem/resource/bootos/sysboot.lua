--[[
	Picotron Kernel
	Handle process creation and slice allocation
	-- should be small so that can configure to just run a single cart (update: why?)
]]


-- need to fetch early to determine fullscreen or windowed
local sdat = fetch"/appdata/system/settings.pod" or  {}
_apply_system_settings(sdat)



-- allowed to assume / and /ram is mounted before boot.lua is run
-- and that there is already /system

cp("/system/misc/ram_info.pod", "/ram/.info.pod")

mkdir("/ram/cart")
mkdir("/ram/system") -- system state (userland)
mkdir("/ram/shared") -- system state visible to sandboxed carts
mkdir("/ram/drop")   -- host files dropped into picotron -- can just leave them kicking around until reboot
--mkdir("/ram/log")    -- logs for this session -- to do

mkdir("/desktop")
-- mkdir("/apps")       -- later; could be optional!

mkdir("/appdata")
mkdir("/appdata/system")
mkdir("/appdata/system/desktop2") -- for the tooltray

--mkdir("/ram/dev") -- experimental; devices are an extraneous concept if have messages and ram file publishing


local head_func, err = load(fetch("/system/lib/head.lua"))
if (not head_func) io.write ("** could not load head ** "..err)
head_func()


-- user can extend this with /appdata/system/startup.lua (is daisy-chained)

local startup_src  = fetch("/system/startup.lua")

if (type(startup_src) ~= "string") then
	printh("** could not read startup.lua")
else
	local startup_func = load(startup_src)
	if (type(startup_func) ~= "function") then
		printh("** could not load startup.lua")
	else
		startup_func()
	end
end

local last_processes_list_publish = 0

function run_userland_processes(allotment)

	local pl = _get_process_list()
	local wm_proc_id = 3

	-- publish! 4 times a second so can at least some spikes show up
	if (time() > last_processes_list_publish + 0.25) then
		store("/ram/system/processes.pod", pl)
		last_processes_list_publish = time()
	end


	while(pl[1] and pl[1].id <= wm_proc_id) do
		deli(pl, 1)
	end

	--printh("---")

	local max = #pl
	local num = max
	local keep_going = true
	local remaining = allotment - stat(301)
	local slices = 0
	local safety = 0

	-- safety: might not make any progress towards zero -- e.g. if still a tiny bit of cpu left
	-- that rounds down to 0 cycles; or for some other anamolous reason a process keeps returning
	-- 0 cpu spent, but also never reaches end of frame. 

	while (keep_going and remaining > 0 and safety < 4096) do
		keep_going = false
		local cpu = remaining / num
		
		-- tiny slices for debugging -- find issues caused due to process switching
		-- 0.0001 is only ~30/slices (and very slow because of switching overhead) but should still work (need 
		-- cpu = 0.0001 -- 30 insts/slice. need high safety value (4096) to prevent flickering on desktop

		for i = 1, max do
			local p = pl[i]
			if (p) then
				--printh("  running "..p.id.." "..cpu.." slice: "..slices)
				--local completed, cpu_spent, err = _run_process_slice(p.id, p.id < 10 and 0.2 or cpu) -- debug: only microslice cproj output
				local completed, cpu_spent, err = _run_process_slice(p.id, cpu)

				if (cpu_spent) remaining -= cpu_spent

				if (completed) then
					-- completed
					-- printh("    completed "..p.name.." cpu:"..string.format("%3.3f",cpu_spent))
					pl[i] = nil
					num -= 1
				else
					-- at least one process made progress
					keep_going = true
				end

				slices += 1
			end
			
		end

		
		safety += 1

	end

--	printh("slices: "..slices)

end


-- boot sound
sfx_index = 0
sfx_delay = 1000 --1200
r = fetch"/system/misc/boot.sfx"


for i=0,0x2ff do
	poke(0x30000+i*0x100, get(r,i*0x100,0x100))
end


local total_frames = 0
local max_wm_cpu = 0.02

local wm_cpu = {}
local max_cpu_samples = 64
for i=0,max_cpu_samples-1 do wm_cpu[i] = 0 end
local wm_cpu_index = 0
local played_boot_sound = false

while (true) do -- \m/

	
--	printh("------------ mainloop "..total_frames.." ----------------")
	total_frames += 1

	-- use time() for better sync
	if not played_boot_sound and stat(987) >= sfx_delay then
		played_boot_sound = true
		sfx(sfx_index)
	end


	-- maybe don't need procman
	-- to do: just let any (local security context) process kill any other process
	-- can assume completes within 0.1 cpu
	_run_process_slice(2, 0.1)

	-- allocate longest time spent in wm within the last 8 frames
	local wm_cpu_max = 0.01 -- at least 1%
	for i=0,max_cpu_samples-1 do
		if (wm_cpu[i] > wm_cpu_max) wm_cpu_max = wm_cpu[i]
	end


--	printh("wm_cpu_max:"..wm_cpu_max)

--[[	printh(string.format("%3.3f %3.3f %3.3f %3.3f %3.3f %3.3f %3.3f %3.3f ",
		wm_cpu[0],wm_cpu[1],wm_cpu[2],wm_cpu[3],wm_cpu[4],wm_cpu[5],wm_cpu[6],wm_cpu[7]))
]]

	-- 0.98 to give 2% margin
	-- problem is: run_userland_processes can't guarantee to run under allotment; e.g. finish on expensive operation
	-- also allows wm to spike by 1% without causing frame overrun (e.g. when desktop apps are maxing out userland cpu)
	-- to do: perhaps could be less when desktop workspaces / more for fullscreen workspace

	local userland_cpu = 0.98 - wm_cpu_max - stat(301)
	local cpu0 = stat(301)

	run_userland_processes(userland_cpu)

	local cpu1 = stat(301)

	-- run window manager last: want to see most recent state of every program; otherwise a frame behind?
	
	-- make sure wm process completes
	local wm_slice_completed = false 
	local total_wm_cpu = 0
	while not wm_slice_completed do

		local completed, cpu_spent, err = _run_process_slice(3, 0.5)

		-- printh(" wm slice cpu: "..pod{completed, cpu_spent, err})

		if (cpu_spent) total_wm_cpu += cpu_spent

		if (err) then

			poke(0x0, 1) -- low level error code
			--printh("*** wm error: "..err)

			wm_slice_completed = true -- give up
		elseif completed then
			--printh("completed: "..cpu_spent)
			wm_cpu[wm_cpu_index] = total_wm_cpu
			wm_cpu_index = (wm_cpu_index + 1) % max_cpu_samples
			wm_slice_completed = true
			-- if (total_wm_cpu > wm_cpu_max) printh("wm cpu spike: "..total_wm_cpu.." / "..wm_cpu_max) 
		else
			-- printh("** wm slice did not complete; running again **")
			-- to do: when does this happen? genuine large spike in wm usage?
				-- or because of unexpected yields / superyields? (run_process_slice does not currently run subslices)
		end

	end

	local cpu2 = stat(301)

	-- to do: allow it to complete (assuming 1 whole frame of cpu is enough) -- don't want to discard (or show!) half-rendered frames 

--[[
	 printh(string.format("cpu0: %3.3f [userland: %3.3f/%3.3f] -> cpu1: %3.3f [wm:%3.3f/%3.3f] -> %3.3f",
			cpu0, cpu1-cpu0, userland_cpu, cpu1, cpu2-cpu1, wm_cpu_max, cpu2))
--]]

	-- return control to c program 
	-- (let emscripten mainloop function end to return control to the browser)

--	coroutine.yield()
	flip() -- reset cpu_cycles for next frame? doesn't matter now that using stat(301) though.

end
