--[[pod_format="raw",created="2024-06-19 18:35:04",modified="2024-06-27 20:30:21",revision=245]]
function text_wrap(text, count)
	local messages = {}
	local temp_str = ""
	local max_length = 0
	for word in string.gmatch(text, "%S+") do	   
		if #temp_str == 0 then
	  		temp_str = word
	  	else
	  		-- + 1 for space between words.
	  		if #temp_str + #word + 1 <= count then
	   			temp_str = temp_str .. " " .. word
		   	else
		   		if #temp_str > max_length then
		   			max_length = #temp_str
		   		end
		   		add(messages, temp_str)
		   		temp_str = word
		   	end
	  	end
	end
	-- If there is still remaining text on temp, it should be added as a new line
	if #temp_str ~= 0 then
		if #temp_str > max_length then
		   	max_length = #temp_str
		end
		add(messages, temp_str)
	end
	return messages, max_length
end

return text_wrap