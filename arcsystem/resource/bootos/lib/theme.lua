

local theme_dat = nil

function theme(which)

	-- fetch lazily
	if (not theme_dat) then
		theme_dat = fetch"/ram/shared/theme.pod"
		if (not theme_dat) then
			local sdat = fetch"/appdata/system/settings.pod"
			if (not sdat) sdat = fetch"/system/misc/default_settings.pod"
			if (sdat and sdat.theme) theme_dat = fetch(sdat.theme) -- if there is a theme file set in settings, use that
			if (not theme_dat) theme_dat = fetch"/appdata/system/theme.pod" or fetch"/system/themes/classic.theme"
			store("/ram/shared/theme.pod", theme_dat)
		end
	end

	return theme_dat[which]
end

on_event("modified:/ram/shared/theme.pod", function()
	-- replace only if this process is using theme data
	if (theme_dat) theme_dat = fetch"/ram/shared/theme.pod"
end)

