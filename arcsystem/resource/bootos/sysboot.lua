--[[pod_format="raw",created="2024-09-28 21:37:54",modified="2024-09-28 21:37:54",revision=0]]
_apply_system_settings(fetch("/appdata/system/settings.pod") or {})

_printh("BootOS Booting")
_create_process_from_code('', "2")
local code = fetch("/system/app.lua")
_create_process_from_code(code, "app")
_signal(37)

while true do
    _run_process_slice(3, 0.9)
    flip()
end