
local p = fetch"/ram/system/processes.pod"

for i=1,#p do

	print(string.format("%4d %-20s %0.3f", p[i].id, p[i].name, p[i].cpu))
	
end
