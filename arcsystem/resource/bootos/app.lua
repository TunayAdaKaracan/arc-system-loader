--[[pod_format="raw",created="2024-09-27 21:01:58",modified="2024-09-27 21:17:42",revision=12]]
local function include(path)
    local fn = load(_fetch_local(path))
    fn()
end

function min(a, b)
    if a < b then return a end
    return b
end

function max(a, b)
    if a > b then return a end
    return b
end

_printh("Imports")
include("/system/basic_fs.lua")
include("/system/events.lua")

local all_os = ls("/systems")
local metadata = fetch_metadata("/systems")
local selected_i = 1

local logo = --[[pod_type="gfx"]]unpod("b64:bHo0APEDAABEBAAA8E1weHUAQyCgjATw--8fDxPwiQ5gLvCDHpBO8H4O0E7weh7gbvB3HvABbvB1LoAOcG7wcy6gTiB_8HEu4N7wby7wAd7wbS7wA97wbC7wA_7wai7wA-4B8Gke8AX_AAcA8AQG-gDwZy7wBv4B8GYe8Af_AfBlDgAwA-BkHAAQBAcA8B0E-gfwYi7wAf4K8GIe0P4P8GAuoP4S8GAugP4U8GAegA7wAP4F8F4u8A3_AgcAYBIOAL7wXT8A8A8L8Fwu8Aj_CvBbLhAe8Av_A-BbfnDeYP4B8FluUJ6cAPFEWl4wfvAIvvBaThB_8Ayu8FsuAG7wEa7wWX7wFZ7wV37wGY7wVW7wHI7wU17wH37wUl7wIm7wUU7wI37wT07wJW7wTk7wJ27wTU7wKG7wS07wKl4GADFO8EwGAFBLXvAqPh4AAwYAEC42APBrKD7wUD7wKC7wUj7wJj7wUk7wJS7wVD7wJC7wVj7wIj7wVz7wIG7wUn7wHq7wS87wHO7wRf4B8Br_AvBB-gPwGf4G8D3_BfAY-gjwO34AvvAX-gnwOm4wvvAVniDe8DleUD4AbvAUbkDu8DhegB4QXvATXlD_AfA2TrANAPAAEj5gHnB_8DZOwA4wTvAQDgDQnvA0TtAOQE7wDy7wAg0A8CLgDkA_8A4ucA6APhBe8DNO8Acu8A0e8AM_IF7wMz7wCR7wDA7wBC4wXvAwbvALDvAKDgDwCFBO8C9_8DsuUF7wLY7wOx5wXvArPvBBCADwAypO8EEOkE7wKV7wQQ6gTvAoXg4BISdeRAHwHU7wUU4ALvAgXvBRPgBO8B5u8FGe8B1u8FKu8BtO8Fae8BpO8Fie8Bhu8FiOBgAwIA4AAgDxOP4WsD4QPvAWLgA_8AD_PKAuIF7wFT4APuD_PJAeQG7wFD4QPtD_JwAO8AAu8AJu8BJOIC7gTgAO8DEu8AKO8A9uMB7QHvA28gBBDm7wBAwAkQOO8AwOAH7wAw4A9AYFbvALHgCO8AIe8DYe8AZ_8Ane8AEMAEEHfvAJDAClBY7wBs7wBS7wNQwAARgAcQSe8AXu8AQYAIADTgBO8AT_AlkA0TUe8AI_IE7wA-4E8AIPAHIIXvADvvAKDABxfvAA-gHwBg0AcQeu0P4H8AAMAHEF3rBukL6gDACRBP4AoC6w-gFwDgChA-4CkA6wLoCeQA8A8AkBrmAucA7wB25AHiAe8DUOwM6wHvAOPtAMAFCg-gGgDssBoAIO8DUOQP4IoA7AARAEDgCggA4AvjAukA7wIA4AcfACbjAe8CoLAGEGPjAe8CkLAEEILvAuCQBBCh7wLQkAH0kGAASg------------hQ==")

for i, os in ipairs(all_os) do
    if metadata.os == os then
        selected_i = i
    end
end

local timer = metadata.timer or 5
local start = time()
local any_input = false
local disp = userdata("u8", 480, 270)
function _init()
    pal()
    poke(0x5508, 0x3f)
    poke(0x5509, 0x3f)
    poke(0x5f56, 0x40)
    poke(0x4000, get(fetch("/system/lil.font")))

    _map_ram(disp, 0x10000)
    _set_draw_target(disp)
end

function centered_text(text, y, clr)
	local size = #text * 5 -1
	local x = 240 - size/2
	_print_p8scii(text, x, y, clr)
end

function draw_OS_list(yoffset)
	for i, os in ipairs(all_os) do
		text_color = 19
		bg_color = 0
		
		if selected_i == i then
			text_color = 7
			bg_color = 17
		end
		
		rectfill(10, (i-1)*11 + yoffset, 470, i*11-1 + yoffset, bg_color)
		_print_p8scii(os, 12, (i-1)*11+2 + yoffset, text_color)
	end
end

function _draw()
    cls(0)
    rect(0, 0, 479, 269, 19)
    --print("Hello World", 0, 0, 7)
    spr(logo, 160, 10)
    centered_text("Choose an operating system", 150, 7)
    if not any_input then
    	centered_text("You will boot to "..all_os[selected_i].." automatically in "..tostring(ceil(timer - start - time())), 160, 7)
    end
    draw_OS_list(170)
end

function _update()
    _handle_events()

    if keyp(keys.DOWN) then
        selected_i = min(selected_i+1, #all_os)
        any_input = true
    elseif keyp(keys.UP) then
        selected_i = max(selected_i-1, 1)
        any_input = true
    elseif keyp(keys.SPACE) or (time() - start > timer and not any_input) then
		store_metadata("/systems", {os=all_os[selected_i]})
		
		-- if it is on type 2 setting, do not set bypass to true.
		-- Changing type 2 -> type 1 while bypass set to true will run the selected system immediatly.
		-- Prevents unwanted behaviour.
		if metadata.type == 1 then
			store_metadata("/systems", {bypass=true})
		end
		
		_signal(34)
    end
end

_init()
while true do
    _update()
    _draw()
    flip()
end