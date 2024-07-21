
local p = fetch"/ram/system/processes.pod"

for i=1,#p do

	print(string.format("%4d %-20s %0.3f  %dk", p[i].id, p[i].name, p[i].cpu, p[i].memory\1024))
	
end
