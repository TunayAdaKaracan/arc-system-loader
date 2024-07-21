--[[

	undo.lua

	// loaded dynamically in head.lua

	my_stack = create_undo_stack(mysave, myload, pod_flags, item)
	
		function mysave()   -- return program state
		function myload(s)  -- load s into program state
		pod_flags           -- pod format for pod() -- default to 0
		item                -- extra info that the caller can use (usually to identify which item)

]]


local Undo = {}

function Undo:reset()

	self.prev_state_str = nil
	self.next_state_str = nil

	self.undo_stack = {}
	self.redo_stack = {}

	self:checkpoint()

end

function Undo:undo()

	if (#self.undo_stack < 1) return false -- nothing to undo

	-- 0. assymetrical case for undo (and not redo): if there is no next state (redo stack is empty), make a new one
	if (not self.next_state_str) self.next_state_str = pod(self.save_state(self.item), self.pod_flags)

	-- 1. add patch to get from prev -> next on redo stack
	local patch = create_delta(self.prev_state_str, self.next_state_str)
	add(self.redo_stack, patch)

	-- 2. grab older state from undo stack
	self.next_state_str = self.prev_state_str
	self.prev_state_str = apply_delta(self.prev_state_str, deli(self.undo_stack))
	self.load_state(unpod(self.next_state_str), self.item)

	return true
end

function Undo:redo()

	if (#self.redo_stack < 1) return false -- nothing to redo
	
	-- 1. add patch to get from next -> prev on undo stack
	local patch = create_delta(self.next_state_str, self.prev_state_str)
	add(self.undo_stack, patch)

	-- 2. grab newer state from redo stack
	self.prev_state_str = self.next_state_str
	self.next_state_str = apply_delta(self.next_state_str, deli(self.redo_stack))
	self.load_state(unpod(self.next_state_str), self.item)

	return true
end



function Undo:checkpoint()

	local s0 = pod(self.save_state(self.item), self.pod_flags)
	local s1 = self.prev_state_str

	if (s0 == s1 and #self.undo_stack > 0) return false -- no change

	-- delta allowed to be nil 
	local delta = create_delta(s0, s1)

	add(self.undo_stack, delta)
	self.prev_state_str = s0
	self.next_state_str = nil
	self.redo_stack = {}
	return true
end



function Undo:new(save_state, load_state, pod_flags, item)

	local u = {
		save_state = save_state,
		load_state = load_state,
		pod_flags  = pod_flags or 0,
		item = item
	}

	setmetatable(u, self)
	self.__index = self

	u:reset()
	
	return u
end

-- export class used by head
UNDO = Undo

