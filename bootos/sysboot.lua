_apply_system_settings(fetch("/appdata/system/settings.pod") or {})

_printh("BootOS Booting")
_create_process_from_code('', "2")
_create_process_from_code(fetch("/system/app.lua"), "app")
_signal(37)

while true do
    _run_process_slice(3, 0.9)
    flip()
end