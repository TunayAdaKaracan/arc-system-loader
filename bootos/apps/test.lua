function _init()
    start = time()
end

function _draw()
    cls(5)
    print("Hello world", 0, 0, 7)
end

function _update()
    if time() - start > 10 then
        store_metadata("/systems", {pass=true, system="picotron"})
        send_message(2, {event="reboot"})
        exit()
    end
end