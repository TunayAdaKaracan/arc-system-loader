
-- send a message to process manager
send_message(2, {event="kill_process", proc_id = tonum(env().argv[1])})
