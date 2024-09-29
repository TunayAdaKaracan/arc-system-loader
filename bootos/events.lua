--[[pod_format="raw",author="",created="2024-09-28 21:27:50",modified="2024-09-29 20:57:00",notes="",revision=1,title="orul",version=""]]
do
    keys = {
        UP = 82,
        DOWN = 81,
        SPACE = 44
    }
    local pressed_keys = {}
    local frame_keys = {}

    function _handle_events()
        frame_keys = {}

        repeat
            local msg = _read_message()
            if not msg then return end

            if msg.event == "keydown" then
                add(keys, msg.scancode)
                add(frame_keys, msg.scancode)
            elseif msg.event == "keyup" then
                del(keys, msg.scancode)
            end

        until not msg
    end

    local function contains(t, val)
        for _, tval in pairs(t) do
            if tval == val then return true end
        end
        return false
    end

    function keyp(scancode)
        return contains(frame_keys, scancode)
    end

    function key(scancode)
        return contains(pressed_keys, scancode)
    end
end