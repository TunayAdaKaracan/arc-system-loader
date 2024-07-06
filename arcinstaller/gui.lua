--[[pod_format="raw",created="2024-06-30 22:32:35",modified="2024-07-06 11:34:30",revision=248]]
include "utils/369gui.lua"
gui = create_gui()

function gui.attach_system_selector()
	local container = gui:attach({
		x = 0, --it was 64-30
		y = 40,--it was 20
		width = get_display():width()+5, --60
		height=100,
		draw = function(self) --g369.CLS(self,8)
			-- I have zero idea why this is even required at all to work properly.
		end
	})
	local pulldown = container:attach_pulldown({
		x = 2,
		y = 0,
		width = container.width-12,
		height=1000
	})
	container:attach_scrollbars()
	
	local systems = ls("/systems")
	for system in all(systems) do
		pulldown:attach_pulldown_item({
			label = "\t"..system,
			stay_open = true,
			action = function(self)
				store_metadata("/systems", {system=system})
			end,
		})
	end
end

function gui.attach_update_button()
	gui:attach_button({
		x=64-20,
		y=60,
		label="Update",
		click=function(self)
			store("/system/boot.lua", get_boot_file_remote())
			gui:detach(self)
			is_up_to_date = true
			gui.attach_system_selector()
		end
	})
end

is_installed = (ls("/systems")~=nil)
is_up_to_date_checked = false
is_up_to_date = nil


if not is_installed then
	gui:attach_button({
		x=64-22,
		y=60,
		label="Install",
		click=function(self)
			install_loader()
			gui:detach(self)
			is_installed = true
		end
	})
end

