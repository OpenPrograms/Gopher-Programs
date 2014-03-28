--just hrere to force reloading the api so I don't have to reboot
local package=require("package")
package.loaded["gml"]=nil

local gml=require("gml")
local component=require("component")

local gui=gml.create("center","center",32,9)

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

local scrollBar

scrollBar=gui:addScrollBarV(30,1,9,100,function() textField.text=tostring(scrollBar.scrollPos) textField:draw() end)

gui:run()

