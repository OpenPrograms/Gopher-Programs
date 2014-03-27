--just hrere to force reloading the api so I don't have to reboot
local package=require("package")
package.loaded["gml"]=nil

local gml=require("gml")
local component=require("component")

local gui=gml.create("center","center",30,7)


local label=gui:addLabel("center",2,13,"Hello, World!")

local function toggleLabel()
  if label.visible then
    label:hide()
  else
    label:show()
  end
end

local function closeGui()
  gui.close()
end

local textField=gui:addTextField("center",4,18)

local button1=gui:addButton(4,6,10,1,"Toggle",toggleLabel)
local button2=gui:addButton(-4,6,10,1,"Close",gui.close)

gui:addHandler("key_down",
  function(event,addy,char,key)
    --ctrl-r
    if char==18 then
      local fg,bg=component.gpu.getForeground(), component.gpu.getBackground()
      label["text-color"]=math.random(0,0xffffff)
      label:draw()
      component.gpu.setForeground(fg)
      component.gpu.setBackground(bg)
    end
  end)

gui:run()

--[[
This program as gml:

[gml]
  [gui name=gui]
    [label name=label x=center y=2 width=13]Hello, World![/label]
    [textfield x=center y=4 width=18][/textfield]
    [button name=button1 x=4 y=6 width=10 height=1 onClick=toggleLabel]Toggle[/button]
    [button name=button2 x=-4 y=6 width=10 height=1 onClick=gui.close]Close[/button]
  [/gui]
  [function name=toggleLabel]
    if label.visible then
      label:hide()
    else
      label:show()
    end
  [/function]
  [handler event=key_down]
    if char==18 then
      local fg, bg=component.gpu.getForeground(), component.gpu.getBackground()
      label["text-color"]=math.random(0,0xffffff)
      label:draw()
      component.gpu.setForeground(fg)
      component.gpu.setBackground(bg)
    end
  [/handler]
[/gml]

--]]