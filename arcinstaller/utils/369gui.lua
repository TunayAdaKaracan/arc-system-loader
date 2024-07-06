--[[pod_format="raw",created="2024-05-03 23:30:30",modified="2024-07-02 08:46:51",revision=9782]]
--[[
								 369 GUI Functions
	BGbord, bottomLine, CLS, emptySlot, lLine, rLine, rRect, topLine
--]]

g369 = {}

function g369.CLS(el,col) --fills an element with a color, input: element & color
	rectfill(0,0,el.width,el.height,col)
end

--BackGround border: makes a border for the element
function g369.BGbord(el,col)
	rect(0,0,el.width-1,el.height-1,col)
end

--makes a border for an element
function g369.elBord(el,col)
	rect(0,0,el.width-1,el.height-1,col)
end

function g369.topLine(el,col) --makes a line at the top of an element
	line(2,0,el.width-3,0,col)
end

function g369.bottomLine(el,col) --makes a line at the bottom of an element
	line(0,el.height-1,el.width,el.height-1,col)
end

function g369.rLine(el,col) --makes a line at the right side of an element
	line(el.width-1,2,el.width-1,el.height-3,col)
end

function g369.rRect(el,col) --makes a simple document style graphic at the right
	rectfill(el.width-3,2,el.width-1,el.height-3,col)
end

function g369.lLine(el,col) --makes a line at the right side of an element
	line(0,2,0,el.height-3,col)
end

--"Vector" Icons!
function g369.emptySlot(x,y,slotID,col) --24x24 icon displaying an empty slot
	rectfill(x,y,x+24,y+24,7)
	print("SLOT\n #"..slotID,x+3,y+3,col)
end