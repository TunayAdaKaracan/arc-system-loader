--gui.lua by 369px
local logo = --[[pod_type="gfx"]]unpod("b64:bHo0APEDAABEBAAA8E1weHUAQyCgjATw--8fDxPwiQ5gLvCDHpBO8H4O0E7weh7gbvB3HvABbvB1LoAOcG7wcy6gTiB_8HEu4N7wby7wAd7wbS7wA97wbC7wA_7wai7wA-4B8Gke8AX_AAcA8AQG-gDwZy7wBv4B8GYe8Af_AfBlDgAwA-BkHAAQBAcA8B0E-gfwYi7wAf4K8GIe0P4P8GAuoP4S8GAugP4U8GAegA7wAP4F8F4u8A3_AgcAYBIOAL7wXT8A8A8L8Fwu8Aj_CvBbLhAe8Av_A-BbfnDeYP4B8FluUJ6cAPFEWl4wfvAIvvBaThB_8Ayu8FsuAG7wEa7wWX7wFZ7wV37wGY7wVW7wHI7wU17wH37wUl7wIm7wUU7wI37wT07wJW7wTk7wJ27wTU7wKG7wS07wKl4GADFO8EwGAFBLXvAqPh4AAwYAEC42APBrKD7wUD7wKC7wUj7wJj7wUk7wJS7wVD7wJC7wVj7wIj7wVz7wIG7wUn7wHq7wS87wHO7wRf4B8Br_AvBB-gPwGf4G8D3_BfAY-gjwO34AvvAX-gnwOm4wvvAVniDe8DleUD4AbvAUbkDu8DhegB4QXvATXlD_AfA2TrANAPAAEj5gHnB_8DZOwA4wTvAQDgDQnvA0TtAOQE7wDy7wAg0A8CLgDkA_8A4ucA6APhBe8DNO8Acu8A0e8AM_IF7wMz7wCR7wDA7wBC4wXvAwbvALDvAKDgDwCFBO8C9_8DsuUF7wLY7wOx5wXvArPvBBCADwAypO8EEOkE7wKV7wQQ6gTvAoXg4BISdeRAHwHU7wUU4ALvAgXvBRPgBO8B5u8FGe8B1u8FKu8BtO8Fae8BpO8Fie8Bhu8FiOBgAwIA4AAgDxOP4WsD4QPvAWLgA_8AD_PKAuIF7wFT4APuD_PJAeQG7wFD4QPtD_JwAO8AAu8AJu8BJOIC7gTgAO8DEu8AKO8A9uMB7QHvA28gBBDm7wBAwAkQOO8AwOAH7wAw4A9AYFbvALHgCO8AIe8DYe8AZ_8Ane8AEMAEEHfvAJDAClBY7wBs7wBS7wNQwAARgAcQSe8AXu8AQYAIADTgBO8AT_AlkA0TUe8AI_IE7wA-4E8AIPAHIIXvADvvAKDABxfvAA-gHwBg0AcQeu0P4H8AAMAHEF3rBukL6gDACRBP4AoC6w-gFwDgChA-4CkA6wLoCeQA8A8AkBrmAucA7wB25AHiAe8DUOwM6wHvAOPtAMAFCg-gGgDssBoAIO8DUOQP4IoA7AARAEDgCggA4AvjAukA7wIA4AcfACbjAe8CoLAGEGPjAe8CkLAEEILvAuCQBBCh7wLQkAH0kGAASg------------hQ==")

gui = create_gui()

local logoGui = gui:attach{x=160,y=10,width=160,height=160,
			draw=function(self)
				spr(logo,0,0)
				print("Choose an Operating System",15,150,7)
			end		
}

local OS_list = gui:attach{x=160,y=logoGui.height+20,width=160,height=80,
			draw=function(self)
				--rectfill(0,0,self.width,self.height,7)
				draw_OS_list()
			end	
}


function draw_OS_list()

	for i, os in ipairs(all_os) do
		text_color = 19
		bg_color = 0
		
		if selected_i == i then
			text_color = 7
			bg_color = 17
		end
		
		rectfill(0, (i-1)*11, get_display():width(), i*11-1, bg_color)
		print(os, 2, (i-1)*11+2, text_color)
	end
end
