# Arc System Loader
Arc is a system loader for Picotron. With Arc, you can have multiple systems within your Picotron and easily change your systems. This project targets to make it easier to create new systems and publish them.
Project is still on very early stage and shouldn't be used for anything else than test purposes. Sudden crashes and file loses might happen. Since it is hard to debug you might have to remove Arc from your system and reinstall again which might result in losing your changes.
If you want to contribute to project, you are free to do so.

## Installation
Download arcinstaller.p64 and run it. It will automatically mount /system to host drive. Then you can reboot and continue to use your picotron as usual.
To download systems you need to manually copy system folders to /systems/ and set `selected_system` on boot.lua

#### TODO
- [ ] OS selector like you would see in real computers.
- [ ] Find a way to share applications which system you are on.
