--[[pod_format="raw",created="2024-03-13 18:17:04",modified="2024-06-30 01:20:27",revision=10]]
--[[

	/dev/ed/gui_ed.lua

	text editor widget

	good for ~128k

]]

local _has_focus = true
on_event("gained_focus", function() _has_focus = true end)
on_event("lost_focus", function() _has_focus = false end)


local function apply_markup(l)

	-- require space; better to be strict
	if (sub(l,1,2) == "# ") then
		--return "\14\06t\06w"..sub(l,3)
		-- return "\^t\^w"..sub(l,3).."\^g\-h"..sub(l,3) -- haha
		return "------------------------------------\n  "..sub(l, 3).."\n------------------------------------\n"
	end

	if (sub(l,1,3) == "## ") then
		return ":: "..sub(l, 4).."\n"
	end

	if (sub(l,1,3) == "```") then

	end

	-- no markup; need to let "]]" pass through!
	return l
end


local search_box_height = 18
local search_box_width  = 240

function close_search_pane(container)
	
	if (not container.search_box) return

	window{capture_escapes = false}
	container.search_box:detach()

	container.search_box = false

end



function open_search_pane(container, search_func, prompt_str)

	-- already open
	if (container.search_box) return

	prompt_str = prompt_str or "Find:"

--	printh("opening search pane from container: "..tostr(container))

	local search_box = container.parent:attach({
		x = container.x + container.width - search_box_width - 8, y = container.y, 
		width = search_box_width, height = search_box_height
	})

	function search_box:draw()
		rectfill(0,0,self.width,self.height,6)
		line(0,self.height-1,self.width,self.height-1,13)
		print(prompt_str,8,6, 5)
	end

	local search_field = search_box:attach_text_editor({
		x=34, y=3, width=search_box_width - 48, height=12, block_scrolling = true, max_lines = 1,
		key_callback = {enter = function () search_func(1) close_search_pane(container) end }
	})

	if (prompt_str == "Find:") then
		search_field:set_text({container.last_search_str or ""})
		search_field:select_all()
	end

	search_field:set_keyboard_focus(true) -- to do: perhaps should allow search_field:set_keyboard_focus()
	
	container.search_box = search_box
	container.search_field = search_field

	window{capture_escapes = true}

end

-- attach_text_editor
-- returns the content -- all exposed methods (incl :attach_scrollbars!) and attributes can be stored there  
function attach_text_editor(g, parent)

	
	local container = g:attach(parent)
	local content                -- referenced by container:draw
	local undo_stack



	local char_w = peek(0x4000) -- only used for cursor
	local char_h = peek(0x4002)

	
	local cursor_y0 = -1
	local cursor_y1 = 7

	local cur_x, cur_y = 1, 1
	local cur_xp = 0 -- cursor x in pixels (preserve original position when moving across a shorter line that clamps cur_x)

	local hydrated = {}
	local hydrate_y = 1


	local sel = {{line=0, char=0}, {line=0, char=-1}, {line=0, char=0}}





	-- note: need a draw function so that parent clipping is set!

	function container:draw()
		-- default container draw: clear to blue
		-- perhaps could be optional though if caller wants to manage background (e.g. live coding w/ code shown on top of output)
		rectfill(0,0,self.width-1, self.height-1, content.bgcol)

		-- print("\^w\^t ***"..tostring(cur_y), 10,10,8)

		-- show keyboard focus state (debug, but maybe useful in future)
		-- have blinking cursor!
		--[[
		if (content:has_keyboard_focus() and self.max_lines == 1) then
			rect(0, 0, self.width-1, self.height-1, 10)
		end
		]]

	end
	
	-- returns true when call back exists AND callback doesn't opt to pass-through
	local function key_pressed_callback(k)
		if (type(content.key_callback[k]) == "function") then
			return not content.key_callback[k](k, text)
		end
		return false
	end


	
	-- make the scrollable thing
	-- start same height as container

	content = container:attach({x=0,y=0,width=container.width, height=container.height})

	-- copy attributes passed to container
	-- stored in content so that caller can deal only with return value of attach_code_editor (content, not container) 
	-- don't do an pairs() copy because don't want to copy over internal values
	
	content.show_line_numbers   = container.show_line_numbers
	content.embed_pods          = container.embed_pods
	content.syntax_highlighting = container.syntax_highlighting
	content.markup              = container.markup
	content.max_lines           = container.max_lines
	content.has_search          = container.has_search
	content.bgcol               = container.bgcol or 1
	content.fgcol               = container.fgcol or 6
	content.curcol              = container.curcol or 14
	content.selcol              = container.selcol or 10
	content.lncol               = container.lncol or 16
	content.block_scrolling     = container.block_scrolling
	content.key_callback        = container.key_callback or {}

	content.margin_top          = container.margin_top or 3
	content.margin_left         = container.margin_left or 4
	content.margin_left1        = content.margin_left + (content.show_line_numbers and 28 or 0) -- updated every frame


	---
	local text = {""}

	local num = rnd(20)
	local x = container.x or 0
	local y = container.y or 0
	local width = container.width or 200
	local height = container.height or 100
	

-- colour when editing a line
	local editing_line_col = content.bgcol == 1 and 9 or 5


	------------------------------------------------------------------------------------

	local function set_selection(tbl)
		sel = tbl
		-- starting point (for adjusting with shift+click / shift+navigate)
		if (not sel[3]) then
			sel[3] = unpod(pod(sel[1]))
		end
	end


	local function get_sx_for_cur_x(str, pos)
		if (pos < 1) then return 0 end
		local s = sub(str, 1, pos)
		return print(s, 0, -100)
	end

	-- don't care about x for now
	local function find_cur_y_for_click(my)

		local yy = content.margin_top

		my += 1  -- slight fudge to match cursor / because space below characters visually part of next row

		for i = 1, #text do			
			yy += (hydrated[i] and hydrated[i].draw_h) or char_h
			if (my < yy) return i
		end

		return #text

	end

	
	local function find_x_for_cur_x(cur_x, str)
		if (not str) return 0
		return print(sub(str, 1, cur_x - 1), 0, -1000)
	end

	-- assumes tabs rendered relative to home_x ------
	local function find_cur_x_for_click(cx, str)
		if (not str) return 0

		if (#str == 0) then return 1 end

		-- printh("find_cur_x_for_click: "..cx)
		
		for i=1,#str do
			local xx = print(sub(str, 1, i), 0, -1000)
			if (xx and xx >= cx) then return i end
		end
		return #str+1
	end

	------------------------------------------------------------------------------------

	function content:set_text(t)
		if (type(t) == "string") t = split(t,"\n",false)

		text = t 

		-- behave as if editing a new file
		-- (can't undo across set_texts)
		cur_y = 1
		hydrated = {}
		undo_stack:reset()
	end

	function content:get_text() return text end

	function content:select_all()
		set_selection{{line=1, char=1}, {line=#text, char=#text[#text]}}
	end

	function content:search_box_is_open()
		return container.search_box
	end

	

	local identcol = {}
	local reserved = {"and", "break", "do", "else", "elseif", "end", "for", "function", "if", "in", "local", "not", "or", "repeat", "return", "then", "until", "while"}
	local reserved_val = {"true", "false", "nil"}
	local api_name = {
		"camera", "clip", "cls", "color", "pal", "palt",
		"fillp", "flip", "line", "rect", "rectfill",
		"oval", "ovalfill", "circ", "circfill",
		"pget", "pset", "print", "printh", "cursor",
		"map", "tline", "spr", "sspr",

		"peek", "peek2", "peek4", "poke", "poke2", "poke4",
		"memset", "memcpy",

		"sub", "chr", "ord", "split", "tostr", "tonum",	
		"add", "del", "deli", "all", "foreach", "pairs",
		
		"reset", "yield", "time", "stat",
		"btn", "btnp",

		"cos", "sin", "atan2", "sqrt", "srand", "rnd",
		"max", "min", "mid", "flr", "ceil", "sgn", "abs"
	}
	for i=1,#reserved do
		identcol[reserved[i]] = "e"
	end
	for i=1,#api_name do
		identcol[api_name[i]] = "b"
	end
	for i=1,#reserved_val do
		identcol[reserved_val[i]] = "c"
	end

	local multi_catcol ={[3] = "d", [4] = "c"} -- multiline categories take priority
	local catcol={[0]="7","6","c","d", "c", "7"}

	local function highlight_line(line, token_state)

		if (not line) return

		if (not content.syntax_highlighting) return line

		local pos = 1
		local out = ""
		
		while (pos <= #line) do
			local str, pos1, cat
			str, pos1, cat, token_state = tokenoid(line, pos, token_state)
			
			if (not str) then return out end
			local colstr = multi_catcol[cat] or identcol[str] or catcol[cat] or ""
			out = out .. "\f" .. colstr .. str
			pos = pos1
		end

		return out,token_state
	end

	------------------------------------------------------------------------------------

	-- hydrate can invalidate total height
	local total_height = nil

	--[[
		hydrate()
		applies syntax hydrateing, pod embedding, pn markup 
		to do: handle markup. need 2 standard banks of fonts

		renderable   -- the thing to render (could be a userdata)
		draw_h       -- height of the item
		text_src     -- invalid when no longer matches (need to recalcuate)
		token_state0 -- state of tokenoidizer ad start of line (should match previous line when valid)
		token_state  -- state of tokenoidizer (optional) after line

	]]
--	local function hydrate(line, token_state)

	local function hydrate(i, from)

		if (i > #text) return -- safety

		-- no need
		if (
			hydrated[i] and 
			hydrated[i].text_src == text[i] and
			(i == 1 or (hydrated[i-1] and hydrated[i-1].token_state == hydrated[i].token_state0))
		) 
		then
			return
		end

		-- always invalidate total height when something is hydrated
		total_height = nil

		-- make sure previous line is hydrated
		if (i > 1) then
			hydrate(i-1, i)
			-- safety
			if (not hydrated[i-1]) return
		end


		--[[
			-- debug: show reason hydration is happening

			local reason = "unknown reason"
			if (not hydrated[i]) then reason = "not hydrated yet"
			elseif (hydrated[i].text_src != text[i]) then reason = "text_src changed"
			elseif (not hydrated[i-1]) then reason = "previous lie not hydrated"
			elseif (hydrated[i-1].token_state != hydrated[i].token_state0) then reason = "previous token_state doesn't match"
			end

			printh("hydrating: "..i.."   (from: "..(from or "")..") because "..reason)
		]]

		local token_state = i > 1 and hydrated[i-1].token_state or 0
		local line = text[i]

		local item = {
			text_src = line,
			token_state = token_state,
			token_state0 = (i == 1 or not hydrated[i-1]) and 0 or hydrated[i-1].token_state,
			-- draw_y includes the top margin
			draw_y = i > 1 and (hydrated[i-1].draw_y + hydrated[i-1].draw_h) or content.margin_top
		}

		hydrated[i] = item

		-- pod
		if (content.embed_pods and sub(line,1,7) == "--[[pod") then
			item.renderable = unpod(line)
			if (type(item.renderable) == "userdata") then
				item.draw_h = item.renderable:height() + 4 -- give 4 pixels margin below image
				return
			else
				item.renderable = line
			end
		end
		
		-- marked up line
		if (content.markup and (not content.syntax_highlighting or (token_state >> 8) == 3)) then

			-- when syntax highlight is on, only apply markup when inside a comment!
			-- for multiline string: (token_state >> 8) == 3
			
			local marked_up_line = apply_markup(line)
			local x1, y1 = print(marked_up_line, 0, -1000)

			if (token_state >= 256) marked_up_line = "\fd"..marked_up_line -- commented markup should still be commented colour

			-- still need to do highlighting to close comment block. consider: "# foo ]]"
			-- (alternative strategy: apply_markup() can return nil)
			if (content.syntax_highlighting) _, item.token_state = highlight_line(line, token_state)

			item.has_markup = true
			item.renderable = marked_up_line
			item.draw_h = y1 + 1000
			return
		
		end

		-- syntax highlighted line

		item.renderable, item.token_state = highlight_line(line, token_state)
		item.token_state = item.token_state or 0


		local x1, y1 = print(item.renderable, 0, -1000)
		if (y1) item.draw_h = y1 + 1000
	end
	

		
	
	local function set_cur_xp()
		-- -2 (~ half character width) so that can move between characters that are <= 2px apart without getting rounded down
		cur_xp = find_x_for_cur_x(cur_x, text[cur_y]) - 2 
		--printh("set cur_xp: "..cur_xp)
	end


	-- visible_x / visible_y: minimum distance from cusor to edge
	-- e.g. when searching, want to see above and below
	-- with 12px minimum edge disance, means can also drag-scroll-select more easily
	local function show_cursor(visible_x, visible_y)

		visible_x = visible_x or 12
		visible_y = visible_y or 12

		hydrate(cur_y) -- might cause a delay while hydrating a bunch of earlier lines

		if (not hydrated[cur_y]) return -- to do: how/when does this happen?

		local xx = find_x_for_cur_x(cur_x, text[cur_y]) -- raw text
		local yy = hydrated[cur_y].draw_y

		if (not xx or not yy) return

		content.y = mid (-(yy - visible_y), content.y, -(yy - (container.height - content.margin_top) + char_h + 4 + visible_y))
		content.x = mid (-(xx - visible_x), content.x, -(xx - (container.width - content.margin_left1) + char_w + 8 + visible_x))

		--printh(xx)

		content.clamp_scrolling()

	end

	local function center_cursor(q)

		visible_x = 12
		visible_y = 12

		-- dupe
		hydrate(cur_y) -- might cause a delay while hydrating a bunch of earlier lines
		if (not hydrated[cur_y]) printh("couldn't center 1") return -- to do: how/when does this happen?
		local xx = find_x_for_cur_x(cur_x, text[cur_y]) -- raw text
		local yy = hydrated[cur_y].draw_y
		if (not xx or not yy) printh("couldn't center 2") return

		content.y = -yy + container.height * (1-q)
		content.x = 0 ---yy + container.height/2

		content.clamp_scrolling()

	end



	-- safety; shouldn't happen
	local function contain_cursor()
		if (not text or #text == 0) text = {""}
		cur_y = mid(1, cur_y, #text)
		cur_x = mid(1, cur_x, #text[cur_y] + 1)
	end

	local function is_something_selected()
		return sel[2].line > sel[1].line or (sel[2].line == sel[1].line and sel[2].char >= sel[1].char)
	end
	
	-- scrollbars calls this if it exists  -- UPDATE: nope; scrollbars not resposible for clamping at all
	-- just always clamp internally. (so clamp_scrolling is not a special name here)
	function content:clamp_scrolling()
		local max_y = max(0, content.height - container.height)
		content.y = mid(0, content.y, -max_y)
		content.x = min(0, content.x)

		if (content.block_scrolling) then
			content.x = 0
			content.y = 0
		end
	end

	function content:draw()

		-- rhs: clip at container (hack so that don't need to calculate content width)
		poke2(0x552c, container.sx + container.width)

		-- draw tabs relative to home
		poke(0x4005, (@0x4005) | 0x2)

		-- line number background
		if (self.show_line_numbers) then
			rectfill(0, 0, 26, self.height, content.lncol)
		end
		
		local x = content.margin_left1
		local y = content.margin_top 
		local inside_comment = false
		local something_selected = is_something_selected()

		local start_i = mid(1, find_cur_y_for_click(0 - content.y),       #text)
		local end_i   = mid(1, find_cur_y_for_click(container.height - content.y),  #text)

		-- draw_y includes the top margin
		y = (hydrated[start_i] and hydrated[start_i].draw_y or content.margin_top)

		for i= start_i, end_i do

			-- draw selection
			if (sel and i >= sel[1].line and i <= sel[2].line) then
				
				local c0 = i > sel[1].line and 1 or sel[1].char
				local c1 = i < sel[2].line and #text[i]+1 or sel[2].char -- +1 for implied \n
				if (c1 >= c0) then -- c1==c0 means single character selected
					local sx0 = content.margin_left1 + get_sx_for_cur_x(text[i], c0-1)
					local sx1 = content.margin_left1 + get_sx_for_cur_x(text[i].." ", c1)-1 -- extra char on right so that newline selection is visible
					rectfill(sx0, y + cursor_y0, sx1, y + cursor_y1, content.selcol)
				end
			end


			-- =====================================================
			-- print line
			-- =====================================================

			local y0 = y

			-- print line number on left
		
			--clip()
			if (self.parent.show_line_numbers) then
				print(string.format("%4d",i), 3, y, content.bgcol)
			end

			-- validate line to print; might propagate backwards
			hydrate(i)

			-- safety
			if (not hydrated[i]) return -- nothing much can do

			local y1 = 0

			-- record where it was drawn (used for cursor_y -> line_index lookup)
			hydrated[i].draw_x = x
			hydrated[i].draw_y = y

			if (cur_y == i or (sel[1].line <= i and sel[2].line >= i)) then

				-- cursor is over, or selection covers that line
				--> show raw text (but still with syntax highlighting when enabled)

				local token_state = hydrated[i-1] and hydrated[i-1].token_state or 0

				-- highlight text outside of a comment (when it doesn't have any markup)
				-- i.e. regular code should still be highlighted as usual when the cursor is over it
--[[
				local highlighted_line = 
					(content.syntax_highlighting and type(hydrated[i].renderable) == "string" and not hydrated[i].has_markup) and
					highlight_line(text[i], token_state) or text[i]
				_,y1 = print(highlighted_line, x, y, editing_line_col)
]]

				if (type(hydrated[i].renderable) == "userdata" or hydrated[i].has_markup) then
					-- show true form
					_,y1 = print(text[i], x, y, editing_line_col)
				else
					-- show as usual (just highlighting)
					_,y1 = print(hydrated[i].renderable, x, y, content.fgcol)
				end

			else

				if (type(hydrated[i].renderable) == "userdata") then
					-- embedded pod; only happens when content.embed_pods is true					
					spr(hydrated[i].renderable, x, y)
				else
					-- text [with markup]
					_,y1 = print(hydrated[i].renderable, x, y, content.fgcol)
				end

			end

			-- move cursor down
			-- if hydrated height is greater, use that -- so that page doesn't jump around when cursor goes on/off
			y = max(y1, hydrated[i].draw_h and (y + hydrated[i].draw_h) or 0)

			-- cursor: when no selection and has focus
			if (content:has_keyboard_focus() and _has_focus and i == cur_y and not something_selected and t()%0.5 < 0.25) then
				local sx = x
				local sy = y0
				if (cur_x > 1) then
					local substr = sub(text[i], 1, cur_x-1)
					sx = print(substr,x,-100)
				end
				
				rectfill(sx, sy + cursor_y0, sx+char_w-1, sy+cursor_y1, content.curcol)

			end
			
		end

	end



	local function insert_string(orig, pos, str)
		if (not orig or not pos or not str) return
		str = tostr(str)
		return sub(orig, 1, pos-1) .. tostr(str) .. sub(orig, pos)
	end

	local function insert_multiline_string(str, y, x)

		if (type(str) ~= "string") return

		local lines = split(str, "\n", false) -- false for no mixed types (numbers also returned as strings)

		if (#lines == 1) then
			-- printh("just one line")
			text[y] = insert_string(text[y], x, str)
			cur_x += #str
			set_cur_xp()
			return
		end

		-- 1. split -- same as pressing enter

		local nl = #lines - 1

		-- printh("inserting "..nl.." lines")

		for i=#text + nl, cur_y + 1, -1 do
			text[i] = text[i - nl]
		end

		
		text[cur_y + nl] = lines[#lines] .. sub(text[cur_y], cur_x)
		text[cur_y] = sub(text[cur_y], 1, cur_x-1) .. lines[1]

		for i=2, #lines-1 do
			text[cur_y + i - 1] = lines[i]
		end

		cur_y += nl
		cur_x = #lines[#lines] + 1
		set_cur_xp()

		hydrate_y = y

	end

	local function delete_string(orig, pos0, pos1)
		return sub(orig, 1, pos0-1) .. sub(orig, pos1+1)
	end
	local function insert_line(pos, str)
		for i=#text+1, pos+1, -1 do
			text[i] = text[i-1]
		end
		text[pos] =  str or ""
	end
	local function delete_line(pos)
		local n = #text
		for i=pos,n do
			text[i] = text[i+1] -- last one will be nil
		end
	end
	local function delete_char()
		if (cur_x == 1) then
			-- join w/ previous line
			if (cur_y > 1) then
				cur_x = #text[cur_y-1] + 1
				text[cur_y-1] = text[cur_y-1] .. text[cur_y]
				delete_line(cur_y)
				cur_y = cur_y - 1
			end
		else
			text[cur_y] = delete_string(text[cur_y], cur_x-1, cur_x-1)
			cur_x = cur_x - 1
		end
		set_cur_xp()
	end

	

	local function deselect()
		set_selection{{line=0, char=0}, {line=0, char=-1}}
	end

	local function get_selected_text()

		local str = ""

		if (not is_something_selected()) return ""

		if (sel[1].line == sel[2].line) then
			-- select within single line
			str = sub(text[sel[1].line], sel[1].char, sel[2].char)
		else
			-- select across multiple lines
			str ..= (sub(text[sel[1].line], sel[1].char) or "") .. "\n"
			for i = sel[1].line + 1, sel[2].line - 1 do
				str ..= text[i] .. "\n"
			end
			str ..= (sub(text[sel[2].line], 1, sel[2].char) or "")
		end

		if (sel[2].char > #text[sel[2].line]) str ..= "\n" -- trailing \n
		return str
	end



	local function delete_selected()

		if (not is_something_selected()) then return end

		local l0 = sel[1].line + 1
		local l1 = sel[2].line

		cur_x = sel[1].char
		cur_y = sel[1].line

		-- perfectly delete from start of line0 to end of line1 --> don't keep first line
		if (sel[1].char == 1 and sel[2].char > #text[sel[2].line]) then  -- "sel[2].char >" means newline is selected
			l0 = sel[1].line
		end

		-- 1. join start of line0 and end of line1
		text[sel[1].line] = (sub(text[sel[1].line], 1, sel[1].char - 1) or "") .. (sub(text[sel[2].line], sel[2].char + 1) or "")
		
		-- 2. remove anything inbetween

		local n = l1 - l0 + 1 -- number of lines to delete


		if (n > 0) then
			for i = l0, #text do
				text[i] = text[i + n]
			end
		end
		
		deselect()

		if (#text == 0) then
			text = {""}
		end

		set_cur_xp()

	end




	local function extend_selection_to_cursor()

		sel[2] = {line = cur_y, char = cur_x}
		
		-- copy initalial position (might swap)
		sel[1].line, sel[1].char = sel[3].line, sel[3].char
		
		-- swap so that start is always first
		if (sel[2].line < sel[1].line or
			(sel[2].line == sel[1].line and sel[2].char < sel[1].char))
		then
			sel[1].line, sel[2].line = sel[2].line, sel[1].line
			sel[1].char, sel[2].char = sel[2].char, sel[1].char
		end

		-- half open
		sel[2].char = sel[2].char - 1
		if (sel[2].char < 1 and sel[2].line > 1) then
			sel[2].line -= 1
			sel[2].char = #text[sel[2].line] + 1 -- +1 for implicit \n
		end

	end

	function content:get_cursor()
		return cur_x, cur_y
	end


	function content:set_cursor(x,y)
		if (not x and not y) then
			-- set based on mouse
			local mx, my = mouse()
			-- printh(string.format("mx %d my %d", mx, my))
			mx -= container.sx
			my -= container.sy
			-- printh(string.format(" --> mx %d my %d", mx, my))
			local cy = find_cur_y_for_click(my)
			cur_y = mid(1, cy, #text)
			cur_x = find_cur_x_for_click(mx - content.margin_left1, text[cur_y])
			deselect()
			show_cursor()
			return
		end

		if (x) cur_x = x
		if (y) cur_y = y

		set_cur_xp()
		show_cursor() -- always show
		
	end

	function content:center_cursor(...)
		-- experimental; disable for now
		--center_cursor(...)
	end


	------------------------------------------------------------------------------------------------
	-- update
	------------------------------------------------------------------------------------------------

	
	local function get_total_height()

		-- current total is valid
		if (total_height) return total_height

		-- re-calculate (only happens after something was hydrated)
		total_height = 0
		for i=1,#text do
			total_height += (hydrated[i] and hydrated[i].draw_h) or char_h
		end

		return total_height
	end

	-- deleteme -- hydration should be 100% lazy
	local function hydrate_all()
		for i=1,#text do
			hydrate(i)
		end
	end


	----------------------------------------------------------------------------------------------------------------

	local function checkpoint()
		--printh("@ checkpoint")
		undo_stack:checkpoint()
	end

	local last_line_y = -1
	local function backup_line_edit()
		-- to do: should be whitespace check
		if (cur_y ~= last_line_y or ((sub(text[cur_y],cur_x-1,cur_x-1) == " ") != (sub(text[cur_y],cur_x,cur_x) == " "))) then
			checkpoint()
		end
		last_line_y = cur_y
	end



	local function strchr(s, c)
		return string.find (s, c, 1, true)
	end

	local function get_char_cat(c)
		if (strchr("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", c)) return 1
		if (ord(c) >= 128 or ord(c) < 0) return 1

		-- pico-8 0.2.4d: added some operators for pico-8 help system
		if (strchr("@%$", c)) return 3
		if (strchr("#^?", c)) return 4
		if (strchr("(){}[]<>", c)) return 5
		
		if (strchr("!@#$%^&*:;.,~=+-/\\`'\"", c)) return 2;

		return 6 -- something else. whitespace
	end

	local function select_from_double_tap(line, pos, sel)

		checkpoint()

		local cat = get_char_cat(sub(line,pos,pos))
		
		local sel0 = pos;
		local sel1 = pos;
		
		
		while (sel0 > 1 and get_char_cat(sub(line,sel0-1,sel0-1)) == cat) do
			sel0 -= 1
		end

		while (sel1 < #line and get_char_cat(sub(line,sel1+1,sel1+1)) == cat) do
			sel1 +=1
		end

		set_selection{{line=cur_y, char=sel0}, {line=cur_y, char=sel1}}

	end


	local function calculate_skip_steps(dir)
		
		local line = text[cur_y]
		
		-- normal cursor movement: one character at a time
		if not key("ctrl") then
			if (dir < 0 and (cur_y > 1 or cur_x > 1)) return -1
			if (dir > 0 and (cur_y < #text or cur_x <= #line)) return 1
			return 0;
		end

		

		local pos = cur_x
		local cat0 = 0 -- unknown starting category
		
		while ((dir < 0 and pos > 1) or (dir > 0 and pos <= #line + 1)) do -- #line + 1 for \n

			if (dir < 0) pos += dir
			
			-- category of current char
			cat = get_char_cat(sub(line,pos,pos));
			
			-- found a character that disagrees with starting category -> end of span
			if ((cat0 > 0) and (cat != cat0)) then
				if (dir > 0 and pos > 0) pos -= 1

				if (cat0 == 6 and cat ~= 6) then
					-- skip whitespace and search for end of non-whitespace
					-- going left: jump to start of word; going right: jump to end of word
					cat0 = cat
				else
					return (pos - cur_x) + 1
				end
			end

			if (cat0 == 0 and cat != 0) then		
				cat0 = cat
			end

			if (dir > 0) pos += dir
		end

		if (dir > 0 and pos > 1) pos -= 1

		return pos - cur_x
	end


	local function comment_selection()
		local found_uncommented = false
		
		local something_selected = is_something_selected()
		local line1 = something_selected and sel[1].line or cur_y
		local line2 = something_selected and sel[2].line or cur_y

		for i=line1,line2 do
			if (text[i] and text[i]:sub(1,2) ~= "--") found_uncommented = true
		end		
			
		if found_uncommented then
			for i=line1,line2 do
				text[i] = "--"..text[i]
			end
		else
			-- uncomment all
			for i=line1,line2 do
				if (text[i]) text[i] = text[i]:sub(3)
			end
		end
	end


	local function indent_selection()

		checkpoint()

		line1, line2 = sel[1].line, sel[2].line
	
		if (key("shift")) then
			for i=line1, line2 do
				if text[i] and (ord(text[i],1) == 9 or sub(text[i],1,1) == " ") then
					text[i] = sub(text[i],2)
					if (i == sel[1].line) sel[1].char -= 1
					if (i == sel[2].line) sel[2].char -= 1
				end
			end
		else
			for i=line1,line2 do
				if (text[i]) text[i] = "\009"..text[i]
			end
			sel[1].char += 1
			sel[2].char += 1
		end


	end

	----------------------------------------------------------------------------------------------------------------

	local function search_text(dir, needle)
		local x = cur_x
		local y = cur_y

		if (is_something_selected()) then
			x = sel[2].char
			y = sel[2].line
			-- printh("starting at "..pod(sel[2]))
		end

		local start_x = x
		local start_y = y

		local first = true
		while (first or y != start_y) do

			local x0, x1 = string.find(text[y], needle, x, true)

			if x0 then
				sel[1].line, cur_y = y,  y
				sel[1].char, cur_x = x0, x0
				sel[2] = {line = y, char = x1}
				show_cursor(50, 80)
				set_cur_xp()
				return
			end
			y += 1 x = 1
			if (y > #text) y = 1
			first = false
		end

		notify("could not find: "..needle)

	end

	local function block_closer(line)

		-- find first and last non-whitespace tokenoid
		local str, pos, cat, tok0, tok1
		pos = 1
		while (pos <= #line) do
			str, pos, cat = tokenoid(line, pos)
			if ((not tok0 or tok0 == "local") and cat==1) tok0 = str -- first identifier tokenoid (ignore "local")
			if (cat ~= 0) tok1 = str                                 -- last non-whitespace tokenoid
		end

		if (tok1 == "do" or tok1 == "then" or tok1 == "else") return "end"
		if (tok1 == "repeat") return "until"

		-- function definition
		if (tok0 == "function") return "end"

		return nil
	end

	function content:update()

		self.width = 10000 -- hack; don't need to know width [yet]. but need to catch mouse events when scrolled to the right

		-- update content.margin_left1 -- adjusted dynamically when line numbers turned on/off
		content.margin_left1 = content.margin_left + (content.show_line_numbers and 28 or 0)

		-- rolling hydration (semi-lazy layout evaluation; spread out computation before e.g. jump to end of file)

		for i=1,5 do
			hydrate_y = hydrate_y + 1
			if (hydrate_y > #text) hydrate_y = 1
			hydrate(hydrate_y)
		end
	


		local new_height = max(get_total_height() + 32, container.height) -- 32 px space at the bottom

		if (self.height != new_height) then
			self.height = new_height
			show_cursor()
		end


		content.clamp_scrolling()


		-- don't need to have focus -- can close from anywhere
		if (keyp("escape")) then
			if (container.search_box) then
				close_search_pane(container)
			else
				key_pressed_callback("escape")
			end
		end


		if (self:has_keyboard_focus()) then

			while peektext() do
				backup_line_edit()
				local k = readtext()

				if (type(content.key_callback[k]) == "function") then
					content.key_callback(k)
				else
				
					delete_selected()
					text[cur_y] = insert_string(text[cur_y], cur_x, k)
					cur_x = cur_x + 1
					set_cur_xp()
					show_cursor()
				end
			end


			-- tab
			if (keyp("tab")) then

				if key_pressed_callback("tab") then
					-- skip
				elseif (is_something_selected()) then
					indent_selection()
				else
					backup_line_edit()
					local k = "\009"
					delete_selected()
					text[cur_y] = insert_string(text[cur_y], cur_x, k)
					cur_x = cur_x + 1
					set_cur_xp()
					show_cursor()
				end
			end

			-- enter
			if (keyp("enter")) then

				if key_pressed_callback("enter") then
					-- skip
				else

					checkpoint()

					-- find tabs & spaces at start to match indentation
					local whitespace=""
					local pos = 1
					while (pos < #text[cur_y] and (sub(text[cur_y], pos, pos) == "\t" or sub(text[cur_y], pos, pos) == " ")) do
						whitespace ..= sub(text[cur_y], pos, pos)
						pos += 1
					end

					--split current line
					insert_line(cur_y + 1, whitespace .. sub(text[cur_y], cur_x))
					text[cur_y] = sub(text[cur_y], 1, cur_x-1)
					cur_x = 1 + #whitespace
					cur_y = cur_y + 1
					show_cursor()

					-- block
					if (key"shift") then
						local blc = block_closer(text[cur_y-1])
						if (blc) then
							insert_line(cur_y+1, whitespace..blc)
							text[cur_y] ..= "\t" -- indent
							cur_x += 1
						end
					end

				end
				set_cur_xp()
			end

			-- backspace
			if (keyp("backspace")) then
				backup_line_edit()
				if (is_something_selected()) then
					delete_selected()
				else
					delete_char()
				end
				show_cursor()
			end

			-- delete
			if (keyp("del")) then

				backup_line_edit()
				if (is_something_selected()) then
					delete_selected()
				elseif (cur_y < #text or cur_x <= #text[#text]) then
					-- dupe: same as pressing right and then backspace
					if (cur_x > #text[cur_y]) then
						if (cur_y < #text) then
							cur_x = 1
							cur_y = cur_y + 1				
						end
					else
						cur_x = cur_x + 1
					end
		 
					delete_char()
				end
				show_cursor()
			end


			-----------------------------------------------------
			-- cursor navigation
			-----------------------------------------------------
			local pressed_cursor_nav_key = false

			local nav_keys = {"left","right","up","down", "home","end", "pageup","pagedown"}

			for i=1,#nav_keys do
				local k = nav_keys[i]
				if keyp(k) then
					if key_pressed_callback(k) then
						-- callback called for this navigation key: ignore following logic
						clear_key(k)
					else
						pressed_cursor_nav_key = true
					end
				end
			end


			if pressed_cursor_nav_key then

				if (not is_something_selected()) then
					set_selection{{line=cur_y, char=cur_x}, {line=cur_y, char=cur_x-1}}
				end

				show_cursor()
			end


			if (keyp("left")) then
				if (cur_x < 2) then
					if (cur_y > 1) then
						cur_y = cur_y - 1				
						cur_x = #text[cur_y] + 1
					end
				else
					--cur_x = cur_x - 1
					cur_x += calculate_skip_steps(-1)
				end
				set_cur_xp()
			end
			if (keyp("right")) then
				if (cur_x > #text[cur_y]) then
					if (cur_y < #text) then
						cur_x = 1
						cur_y = cur_y + 1				
					end
				else
					cur_x += calculate_skip_steps(1)
				end
				set_cur_xp()
			end
			if (keyp("up") or keyp("pageup")) then
				local n = keyp("pageup") and 20 or 1
				for i=1,n do
					if (cur_y < 2) then
						cur_x = 1
					else
						local xx = cur_xp and cur_xp or find_x_for_cur_x(cur_x, text[cur_y])
						cur_y = cur_y - 1
						cur_x = xx > 0 and 1 + find_cur_x_for_click(xx, text[cur_y]) or 1
						cur_x = mid(1, cur_x, #text[cur_y] + 1)
					end
				end
				contain_cursor()
			end
			if (keyp("down") or keyp("pagedown")) then
				local n = keyp("pagedown") and 20 or 1
				for i=1,n do
					if (cur_y >= #text) then
						cur_x = #text[cur_y]+1
					else
						local xx = cur_xp and cur_xp or find_x_for_cur_x(cur_x, text[cur_y])
						cur_y = cur_y + 1
						cur_x = xx > 0 and 1 + find_cur_x_for_click(xx, text[cur_y]) or 1
						cur_x = mid(1, cur_x, #text[cur_y] + 1)
					end
				end
				contain_cursor()
			end

			if (keyp("home") or (key"ctrl" and keyp"up")) then
				if (key"ctrl") cur_y = 1
				cur_x = 1
				show_cursor()
				set_cur_xp()
			end

			if (keyp("end") or (key"ctrl" and keyp"down")) then
				if (key"ctrl") cur_y = #text
				cur_x = #text[cur_y]+1
				show_cursor()
				set_cur_xp()
			end

			
			if (pressed_cursor_nav_key) then

				-- hold shift to extend
				if (key("shift")) then
					extend_selection_to_cursor()
				else
					deselect()
				end

				-- keep cursor visible
				show_cursor()
			end


			-- ctrl-* presses

			if (key("ctrl")) then

				if keyp("x") and is_something_selected() then
					checkpoint()
					set_clipboard(get_selected_text())
					delete_selected()
				end

				if keyp("c") and is_something_selected() then
					set_clipboard(get_selected_text())
				end

				if keyp("v") then
					checkpoint()
					delete_selected()
					insert_multiline_string(get_clipboard(), cur_y, cur_x)
					show_cursor()
				end

				if keyp("z") then
					undo_stack:undo()
				end

				if keyp("y") then
					undo_stack:redo()
				end

				if keyp("a") then
					set_selection{{line=1, char=1}, {line=#text, char=#text[#text]}}
				end
				
				if keyp("f") and content.has_search then
					open_search_pane(container, function ()
						local needle = container.search_field:get_text()[1]
						container.last_search_str = needle
						search_text(1, needle)	
					end)
				end

				if keyp("l") and content.has_search then
					open_search_pane(container, function ()
						local line_num = tostring(container.search_field:get_text()[1])
						if (line_num) then
							cur_y = mid(1, flr(line_num), #text)
							show_cursor()
							set_cur_xp()
						end
					end, "Line:")
				end

				if keyp("g") and container.last_search_str then
					search_text(1, container.last_search_str)
				end

				if keyp("e") then  -- End
					cur_x = #text[cur_y]+1
					show_cursor()
					set_cur_xp()
				end

				if keyp("w") then  -- staWt
					cur_x = 1
					show_cursor()
					set_cur_xp()
				end

				-- ctrl+b: block comment
				if keyp("b") then
					checkpoint()
					comment_selection()
				end

				-- ctrl+d: duplicate line
				if keyp("d") then
					checkpoint()
					deselect()
					insert_line(cur_y, text[cur_y])
					cur_y += 1
					show_cursor()
				end

			end

			-- cproj file -> save every keypress!
			-- to do: "about_to_run_cproj" message on pressing ctrl-r, or something
			-- (and save when leave focus or idle)

			-- any keypress that is not shift or ctrl
			local found_keypress = false
			for i=1,255 do
				if (keyp(i) and i~= 225 and i~=57) found_keypress = true
			end


		end -- keyboard focus

		contain_cursor()

--		printh(string.format("cpu %.3f",stat(1)),440,2,7)

	end



	-- ======================================================================================================================

	----------------------------------------------------------------------------------------
	-- undo
	----------------------------------------------------------------------------------------


	-- don't want to unpod(pod(text)) because only need separate copy of string references

	local function duplicate_text_table(text)
		local t2={}
		for i=1,#text do
			t2[i] = text[i]	
		end
		return t2
	end

	undo_stack = create_undo_stack(
		function() return {
			duplicate_text_table(text),
			cur_x,
			cur_y,
			content.x,
			content.y,
			pod(sel)
		} end,

		function(s)
			text = s[1] 
			cur_x = s[2]
			cur_y = s[3]
			content.x = s[4]
			content.y = s[5]
			sel = unpod(s[6])

			show_cursor()
		end
	)

	

	-------------------------------------------------------------------------------------------------------------------------


	-- to do: how to manage scroll speed?
--[[
	function content:mousewheel(msg)
		if (key("ctrl")) then
			self.x += msg.wheel_y * 32 
		else
			self.y += msg.wheel_y * 32 
		end

	end
]]
	


	function content:click(msg)
		self:set_keyboard_focus(true)
		local cy = find_cur_y_for_click(msg.my)
		if (cy ~= cur_y) checkpoint()
		cur_y = mid(1, cy, #text)
		cur_x = find_cur_x_for_click(msg.mx - content.margin_left1, text[cur_y])
		set_cur_xp()
		if (key("shift")) then
			-- add to selection
			sel[2] = {line=cur_y, char=cur_x-1}
		else
			-- no selection: start new one
			set_selection{{line=cur_y, char=cur_x}, {line=cur_y, char=cur_x-1}}
		end
		show_cursor()
		return true
	end

	-- stop tap messages inside editor from rising to parent
	function content:tap(msg)
		return true
	end

	function content:doubletap(msg)
		-- dupe from click
		local cy = find_cur_y_for_click(msg.my)
		cur_y = mid(1, cy, #text)
		cur_x = find_cur_x_for_click(msg.mx - content.margin_left1, text[cur_y])
		select_from_double_tap(text[cur_y], cur_x, sel)
		return true
	end


	function content:drag(msg)
		-- dupe from click
		local cy = find_cur_y_for_click(msg.my)
		cur_y = mid(1, cy, #text)
		cur_x = find_cur_x_for_click(msg.mx - content.margin_left1, text[cur_y])
		extend_selection_to_cursor()
		show_cursor()
		return true
	end

	
	-------------------------------------------------------------------------------------------------------------------------


	--[[
		allow caller to operate only only content
		ce = gui:attach_text_editor()
		ce:attach_scrollbars()  -- instead of ce.parent:attach_scrollbars()
	]]
	function content:attach_scrollbars(...)
		self.parent:attach_scrollbars(...)
	end

	
	-- container:attach_scrollbars()
	-- return container

	return content
end





