--[[*********************************************

gui element module


todo list:
extension of features/refactor:
-separate border code from button, add frame to gui

new features:
-implement gml loader, parsing gml files and outputing executable lua programs

new components:
-implement scrollBar component - vertical and horizontal
-implement compositeComponent - singular components that are composed of
  sub-components, like listboxes. NOT true containers - sub components are not individually
  focusable, don't fit in the tab order, etc - but are rendered separately and can be treated
  separately for event handling purposes. Listbox example, has a scrollbar and a stack of label
  components which are manipulated by the listbox object but capable of drawing themselves.
-implement listbox, using compositeComponent
-implement textbox, multi-line vert-scrolling version of textfield
-implement messageBox element, that wraps up a gui with label + standard buttons,
  with messageBox:run returning the label of the clicked button.
    mb=gml:createMessageBox(width,height,text,buttonLabels...)
    choice=mb:run()
  possibly: automatically determine width & height based on text and button labels?
-implement tables - editable fields (double-click),
  column headers, resizable columns?

milestone 1: file picker dialog, with saveAs/load modes offered.

--***********************************************]]

local event=require("event")
local component=require("component")
local term=require("term")
local computer=require("computer")
local shell=require("shell")
--local os=require("os")
local filesystem=require("filesystem")
local keyboard=require("keyboard")
local unicode=require("unicode")


local gml={}

local defaultStyle=nil

--clipboard is global between guis and gui sessions, as long as you don't reboot.
local clipboard=nil

local validElements = {
  ["*"]=true,
  gui=true,       --top gui container
  label=true,     --text labels, non-focusable (naturally), non-readable
  button=true,    --buttons, text label, clickable
  textfield=true, --single-line text input, can scroll left-right, never has scrollbar, just scrolls with cursor
  scrollbar=true, --scroll bar, scrolls. Can be horizontal or vertical.
  textbox=true,   --multi-line text input, line wraps, scrolls up-down, has scroll bar if needed
  listbox=true,   --list, vertical stack of labels with a scrollbar
}

local validStates = {
  ["*"]=true,
  enabled=true,
  disabled=true,
  checked=true,
  focus=true,
  empty=true,
}

local validDepths = {
  ["*"]=true,
  [1]=true,
  [4]=true,
  [8]=true,
}

--**********************

function gml.loadStyle(name)
  --search for file
  local fullName=name
  if name:match(".gss$") then
    name=name:match("^(.*)%.gss$")
  else
    fullname=name..".gss"
  end

  local filepath

  --search for styles in working directory, running program directory, /lib /usr/lib. Just because.
  local dirs={shell.getWorkingDirectory(),shell.running():match("^(.*/).+$"), "/lib/", "/usr/lib/"}
  if dirs[1]~="/" then
    dirs[1]=dirs[1].."/"
  end
  for i=1,#dirs do
    if filesystem.exists(dirs[i]..fullname) and not filesystem.isDirectory(dirs[i]..fullname) then
      filepath=dirs[i]..fullname
      break
    end
  end

  if not filepath then
    error("Could not find gui stylesheet \""..name.."\"",2)
  end

  --found it, open and parse
  local file=assert(io.open(filepath,"r"))

  local text=file:read("*all")
  file:close()
  text=text:gsub("/%*.-%*/",""):gsub("\r\n","\n")

  local styleTree={}

  --util method used in loop later when building styleTree
  local function descend(node,to)
    if node[to]==nil then
      node[to]={}
    end
    return node[to]
  end


  for selectorStr, body in text:gmatch("%s*([^{]*)%s*{([^}]*)}") do
    --parse the selectors!
    local selectors={}
    for element in selectorStr:gmatch("([^,^%s]+)") do
      --could have a !depth modifier
      local depth,state,class, temp
      temp,depth=element:match("(%S+)!(%S+)")
      element=temp or element
      temp,state=element:match("(%S+):(%S+)")
      element=temp or element
      temp,class=element:match("(%S+)%.(%S+)")
      element=temp or element
      if element and validElements[element]==nil then
        error("Encountered invalid element "..element.." loading style "..name)
      end
      if state and validStates[state]==nil then
        error("Encountered invalid state "..state.." loading style "..name)
      end
      if depth and validDepths[tonumber(depth)]==nil then
        error("Encountered invalid depth "..depth.." loading style "..name)
      end

      selectors[#selectors+1]={element=element or "*",depth=tonumber(depth) or "*",state=state or "*",class=class or "*"}
    end

    local props={}
    for prop,val in body:gmatch("(%S*)%s*:%s*(.-);") do
      if tonumber(val) then
        val=tonumber(val)
      elseif val:match("^%s*[tT][rR][uU][eE]%s*$") then
        val=true
      elseif val:match("^%s*[fF][aA][lL][sS][eE]%s*$") then
        val=false
      elseif val:match("%s*(['\"]).*(%1)%s*") then
        _,val=val:match("%s*(['\"])(.*)%1%s*")
      else
        error("invalid property value '"..val.."'!")
      end

      props[prop]=val
    end

    for i=1,#selectors do
      local sel=selectors[i]
      local node=styleTree


      node=descend(node,sel.depth)
      node=descend(node,sel.state)
      node=descend(node,sel.class)
      node=descend(node,sel.element)
      --much as I'd like to save mem, dupe selectors cause merges, which, if
      --instances are duplicated in the final style tree, could result in spraying
      --props in inappropriate places
      for k,v in pairs(props) do
        node[k]=v
      end
    end

  end

  return styleTree
end


local function tableCopy(t1)
  local copy={}
  for k,v in pairs(t1) do
    if type(v)=="table" then
      copy[k]=tableCopy(v)
    else
      copy[j]=v
    end
  end
end

local function mergeStyles(t1, t2)
  for k,v in pairs(t2) do
    if t1[k]==nil then
      t1[k]=tableCopy(v)
    elseif type(t1[k])=="table" then
      if type(v)=="table" then
        tableMerge(t1[k],v)
      else
        error("inexplicable error in mergeStyles - malformed style table, attempt to merge "..type(v).." with "..type(t1[k]))
      end
    elseif type(v)=="table" then
      error("inexplicable error in mergeStyles - malformed style table, attempt to merge "..type(v).." with "..type(t1[k]))
    else
      t1[k]=v
    end
  end
end


local function findStyleProperties(element,...)
  local props={...}
  local styleRoot=element.style
  assert(styleRoot)

  --descend, unless empty, then back up... so... wtf
  local depth,state,class,elementType=component.gpu.getDepth(),element.state or "*",element.class or "*", element.type

  local nodes={styleRoot}
  local function filterDown(nodes,key)
    local newNodes={}
    for i=1,#nodes do
      if key~="*" and nodes[i][key] then
        newNodes[#newNodes+1]=nodes[i][key]
      end
      if nodes[i]["*"] then
        newNodes[#newNodes+1]=nodes[i]["*"]
      end
    end
    return newNodes
  end
  nodes=filterDown(nodes,depth)
  nodes=filterDown(nodes,state)
  nodes=filterDown(nodes,class)
  nodes=filterDown(nodes,elementType)
  --nodes is now a list of all terminal branches that could possibly apply to me
  local vals={}
  for i=1,#props do
    if element[props[i]] then
      vals[#vals+1]=element[props[i]]
    else
      for j=1,#nodes do
        local v=nodes[j][props[i]]
        if v~=nil then
          vals[#vals+1]=v
          break
        end
      end
    end
    if #vals~=i then
      for k,v in pairs(nodes[1]) do print('"'..k..'"',v,k==props[i] and "<-----!!!" or "") end
      error("Could not locate value for style property "..props[i].."!")
    end
  end
  return table.unpack(vals)
end


--**********************



local function parsePosition(x,y,width,height,maxWidth, maxHeight)

  width=math.min(width,maxWidth)
  height=math.min(height,maxHeight)

  if x=="left" then
    x=1
  elseif x=="right" then
    x=maxWidth-width+1
  elseif x=="center" then
    x=math.floor((maxWidth-width)/2)
  elseif x<0 then
    x=maxWidth-width+1+x
  elseif x<1 then
    x=1
  elseif x+width-1>maxWidth then
    x=maxWidth-width+1
  end

  if y=="top" then
    y=1
  elseif y=="bottom" then
    y=maxHeight-height+1
  elseif y=="center" then
    y=math.floor((maxHeight-height)/2)
  elseif y<0 then
    y=maxHeight-height+1+y
  elseif y<1 then
    y=1
  elseif y+height-1>maxHeight then
    y=maxHeight-height+1
  end

  return x,y,width,height
end


local function frameAndSave(element)
  local t={}
  local x,y,width,height=element.posX,element.posY,element.width,element.height
  --TODO: when this starts being used on elements besides guis themselves, will
  --need to adjsut for parent position. getAbsPosition method?

  local pcb=term.getCursorBlink()
  local curx,cury=term.getCursor()
  local pfg,pbg=component.gpu.getForeground(),component.gpu.getBackground()

  local fillCh,fillFG,fillBG=findStyleProperties(element,"fill-ch","fill-color-fg","fill-color-bg")

  local blankRow=fillCh:rep(width)

  component.gpu.setForeground(fillFG)
  component.gpu.setBackground(fillBG)
  term.setCursorBlink(false)

  for ly=1,height do
    t[ly]={}
    local str, cfg, cbg=component.gpu.get(x,y+ly-1)
    for lx=2,width do
      local ch, fg, bg=component.gpu.get(x+lx-1,y+ly-1)
      if fg==cfg and bg==cbg then
        str=str..ch
      else
        t[ly][#t[ly]+1]={str,cfg,cbg}
        str,cfg,cbg=ch,fg,bg
      end
    end
    t[ly][#t[ly]+1]={str,cfg,cbg}
    component.gpu.set(x,ly+y-1,blankRow)
  end

  return {curx,cury,pcb,pfg,pbg, t}

end

local function restoreFrame(x,y,prevState)

  local curx,cury,pcb,pfg,pbg, behind=table.unpack(prevState)

  for ly=1,#behind do
    local lx=x
    for i=1,#behind[ly] do
      local str,fg,bg=table.unpack(behind[ly][i])
      component.gpu.setForeground(fg)
      component.gpu.setBackground(bg)
      component.gpu.set(lx,ly+y-1,str)
      lx=lx+#str
    end
  end

  term.setCursor(curx,cury)
  component.gpu.setForeground(pfg)
  component.gpu.setBackground(pbg)
  term.setCursorBlink(pcb)
end

local function elementHide(element)
  if element.visible then
    element.visible=false
    element.gui.redrawRect(element.posX,element.posY,element.width,1)
  end
  element.hidden=true
end

local function elementShow(element)
  element.hidden=false
  if not element.visible then
    element:draw()
  end
end


local function drawLabel(label)
  if not label.hidden then
    local guiX,guiY=label.gui.posX,label.gui.posY
    local fg, bg=findStyleProperties(label,"text-color","text-background")
    component.gpu.setForeground(fg)
    component.gpu.setBackground(bg)
    component.gpu.set(guiX+label.posX-1,guiY+label.posY-1,label.text)
    label.visible=true
  end
end


local function drawButton(button)
  if not button.hidden then
    local guiX,guiY=button.gui.posX,button.gui.posY
    local fg,bg, borderFG, borderBG,
          border,borderLeft,borderRight,borderTop,borderBottom,borderCh,
          borderChL,borderChR,borderChT,borderChB,
          borderChTL,borderChTR,borderChBL,borderChBR,
          fillFG,fillBG,fillCh=
      findStyleProperties(button,
        "text-color","text-background","border-color-fg","border-color-bg",
        "border","border-left","border-right","border-top","border-bottom","border-ch",
        "border-ch-left","border-ch-right","border-ch-top","border-ch-bottom",
        "border-ch-topleft","border-ch-topright","border-ch-bottomleft","border-ch-bottomright",
        "fill-color-fg","fill-color-bg","fill-ch")

    local posX,posY=button.posX+guiX-1,button.posY+guiY-1
    local width,height=button.width,button.height

    local bodyX,bodyY=posX,posY
    local bodyW,bodyH=width,height

    local gpu=component.gpu

    if border then
      gpu.setBackground(borderBG)
      gpu.setForeground(borderFG)

      --as needed, leave off top and bottom borders if height doesn't permit them
      if borderTop and bodyH>1 then
        bodyX=bodyX+1
        bodyH=bodyH-1
        --do the top bits
        local str=(borderLeft and borderChTL or borderChT)..borderChT:rep(bodyW-2)..(borderRight and borderChTR or borderChB)
        gpu.set(posX,posY,str)
      end
      if borderBottom and bodyH>1 then
        bodyH=bodyH-1
        --do the top bits
        local str=(borderLeft and borderChBL or borderChB)..borderChB:rep(bodyW-2)..(borderRight and borderChBR or borderChB)
        gpu.set(posX,posY+height-1,str)
      end
      if borderLeft then
        bodyX=bodyX+1
        bodyW=bodyW-1
        gpu.set(posX,bodyY,borderChL:rep(bodyH))
      end
      if borderRight then
        bodyW=bodyW-1
        gpu.set(posX+width-1,bodyY,borderChR:rep(bodyH))
      end
    end

    gpu.setBackground(fillBG)
    gpu.setForeground(fillFG)
    local bodyRow=fillCh:rep(bodyW)
    for i=1,bodyH do
      gpu.set(bodyX,bodyY+i-1,bodyRow)
    end

    --now center the label
    gpu.setBackground(bg)
    gpu.setForeground(fg)
    --calc position
    local text=button.text
    local textX=bodyX
    local textY=bodyY+math.floor((bodyH-1)/2)
    if #text>bodyW then
      text=text:sub(1,bodyW)
    else
      textX=bodyX+math.floor((bodyW-#text)/2)
    end
    gpu.set(textX,textY,text)
  end
end


local function drawTextField(tf)
  if not tf.hidden then
    local textFG,textBG,selectedFG,selectedBG=
        findStyleProperties(tf,"text-color","text-background","selected-color","selected-background")

    local posX,posY=tf.posX+tf.gui.posX-1,tf.posY+tf.gui.posY-1
    local gpu=component.gpu

    --grab the subset of text visible
    local text=tf.text

    local visibleText=text:sub(tf.scrollIndex,tf.scrollIndex+tf.width-1)
    visibleText=visibleText..(" "):rep(tf.width-#visibleText)
    --this may be split into as many as 3 parts - pre-selection, selection, and post-selection
    --if there is any selection at all...
    if tf.state=="focus" and not tf.dragging then
      term.setCursorBlink(false)
    end
    if tf.selectEnd~=0 then
      local visSelStart, visSelEnd, preSelText,selText,postSelText
      visSelStart=math.max(1,tf.selectStart-tf.scrollIndex+1)
      visSelEnd=math.min(tf.width,tf.selectEnd-tf.scrollIndex+1)

      selText=visibleText:sub(visSelStart,visSelEnd)

      if visSelStart>1 then
        preSelText=visibleText:sub(1,visSelStart-1)
      end

      if visSelEnd<tf.width then
        postSelText=visibleText:sub(visSelEnd+1,tf.width)
      end

      gpu.setForeground(selectedFG)
      gpu.setBackground(selectedBG)
      gpu.set(posX+visSelStart-1,posY,selText)

      if preSelText or postSelText then
        gpu.setForeground(textFG)
        gpu.setBackground(textBG)
        if preSelText then
          gpu.set(posX,posY,preSelText)
        end
        if postSelText then
          gpu.set(posX+visSelEnd,posY,postSelText)
        end
      end
    else
      --no selection, just draw
      gpu.setForeground(textFG)
      gpu.setBackground(textBG)
      gpu.set(posX,posY,visibleText)
    end
    if tf.state=="focus" and not tf.dragging then
      term.setCursor(posX+tf.cursorIndex-tf.scrollIndex,posY)
      term.setCursorBlink(true)
    end
  end
end


local function loadHandlers(gui)
  local handlers=gui.handlers
  for i=1,#handlers do
    event.listen(handlers[i][1],handlers[i][2])
  end
end

local function unloadHandlers(gui)
  local handlers=gui.handlers
  for i=1,#handlers do
    event.ignore(handlers[i][1],handlers[i][2])
  end
end

local function guiAddHandler(gui,eventType,func)
  checkArg(1,gui,"table")
  checkArg(2,eventType,"string")
  checkArg(3,func,"function")

  gui.handlers[#gui.handlers+1]={eventType,func}
  if gui.running then
    event.listen(eventType,func)
  end
end


local function cleanup(gui)
  --remove handlers
  unloadHandlers(gui)

  --hide gui, redraw beneath?
  if gui.prevTermState then
    restoreFrame(gui.posX,gui.posY,gui.prevTermState)
    gui.prevTermState=nil
  end
end

local function contains(element,x,y)
  local ex,ey,ew,eh=element.posX,element.posY,element.width,element.height

  return x>=ex and x<=ex+ew-1 and y>=ey and y<=ey+eh-1
end

local function runGui(gui)
  gui.running=true
  --draw gui background, preserving underlying screen
  gui.prevTermState=frameAndSave(gui)

  --drawing components
  local firstFocusable, prevFocusable
  for i=1,#gui.components do
    if gui.components[i].focusable then
      if firstFocusable==nil then
        firstFocusable=gui.components[i]
      else
        gui.components[i].tabPrev=prevFocusable
        prevFocusable.tabNext=gui.components[i]
      end
      if not gui.focusElement and not gui.components[i].hidden then
        gui.focusElement=gui.components[i]
        gui.focusElement.state="focus"
      end
      prevFocusable=gui.components[i]
    end
    gui.components[i]:draw()
  end
  if firstFocusable then
    firstFocusable.tabPrev=prevFocusable
    prevFocusable.tabNext=firstFocusable
  end
  if gui.focusElement and gui.focusElement.gotFocus then
    gui.focusElement.gotFocus()
  end

  loadHandlers(gui)

  --run the gui's onRun, if any
  if gui.onRun then
    gui.onRun()
  end

  local function getComponentAt(tx,ty)
    for i=1,#gui.components do
      local c=gui.components[i]
      if not c.hidden and c:contains(tx,ty) then
        return c
      end
    end
  end

  local lastClickTime, lastClickPos, dragButton, dragging=0,0,0,false
  local draggingObj=nil

  while true do
    local e={event.pull()}
    if e[1]=="gui_close" then
      break
    elseif e[1]=="touch" then
      --figure out what was touched!
      local tx, ty, button=e[3],e[4],e[5]
      if gui:contains(tx,ty) then
        tx=tx-gui.posX+1
        ty=ty-gui.posY+1
        lastClickTime=computer.uptime()
        lastClickPos={tx,ty}
        dragButton=button
        local target=getComponentAt(tx,ty)
        clickedOn=target
        if target then
          if target.focusable and target~=gui.focusElement then
            gui:changeFocusTo(clickedOn)
          end
          if target.onClick then
            target:onClick(tx-target.posX+1,ty-target.posY+1)
          end
        end
      end
    elseif e[1]=="drag" then
      --if we didn't click /on/ something to start this drag, we do nada
      if clickedOn then
        local tx,ty=e[3],e[4]
        tx=tx-gui.posX+1
        ty=ty-gui.posY+1
        --is this is the beginning of a drag?
        if not dragging then
          if clickedOn.onBeginDrag then
            draggingObj=clickedOn:onBeginDrag(lastClickPos[1],lastClickPos[2],dragButton)
            dragging=true
          end
        end
        --now do the actual drag bit
        --draggingObj is for drag proxies, which are for drag and drop operations like moving files
        if draggingObj and draggingObj.onDrag then
          draggingObj:onDrag(tx,ty)
        end
        --
        if clickedOn and clickedOn.onDrag then
          clickedOn:onDrag(tx,ty)
        end
      end
    elseif e[1]=="drop" then
      local tx,ty=e[3],e[4]
      tx=tx-gui.posX+1
      ty=ty-gui.posY+1
      if draggingObj and draggingObj.onDrop then
        local dropOver=getComponentAt(tx,ty)
        draggingObj:onDrop(tx,ty,dropOver)
      end
      if clickedOn.onDrop then
        clickedOn:onDrop(tx,ty,dropOver)
      end
      draggingObj=nil
      dragging=false

    elseif e[1]=="key_down" then
      local char,code=e[3],e[4]
      if code==15 and gui.focusElement then
        local newFocus=gui.focusElement
        if keyboard.isShiftDown() then
          repeat
            newFocus=newFocus.tabPrev
          until newFocus.hidden==false
        else
          repeat
            newFocus=newFocus.tabNext
          until newFocus.hidden==false
        end
        if newFocus~=gui.focusElement then
          gui:changeFocusTo(newFocus)
        end
      elseif char==3 then
        --copy!
        if gui.focusElement.doCopy then
          clipboard=gui.focusElement:doCopy() or clipboard
        end
      elseif char==22 then
        --paste!
        if gui.focusElement.doPaste and type(clipboard)=="string" then
          gui.focusElement:doPaste(clipboard)
        end
      elseif char==24 then
        --cut!
        if gui.focusElement.doCut then
          clipboard=gui.focusElement:doCut() or clipboard
        end
      elseif gui.focusElement and gui.focusElement.keyHandler then
        gui.focusElement:keyHandler(char,code)
      end
    end
  end

  running=false

  cleanup(gui)

  if gui.onExit then
    gui.onExit()
  end
end

local function baseComponent(gui,x,y,width,height,type,focusable)
  local c={
      visible=false,
      hidden=false,
      gui=gui,
      style=gui.style,
      focusable=focusable,
      type=type,
    }

  c.posX, c.posY, c.width, c.height =
    parsePosition(x, y, width, height, gui.width, gui.height)

  c.hide=elementHide
  c.show=elementShow
  c.contains=contains

  return c
end


local function addLabel(gui,x,y,width,labelText)
  local label=baseComponent(gui,x,y,width,1,"label",false)

  label.text=labelText

  label.draw=drawLabel

  gui.addComponent(label)
  return label
end

local function addButton(gui,x,y,width,height,buttonText,onClick)
  local button=baseComponent(gui,x,y,width,height,"button",true)

  button.text=buttonText
  button.onClick=onClick

  button.draw=drawButton
  button.keyHandler=function(button,char,code)
      if code==28 then
         button:onClick()
      end
    end
  gui.addComponent(button)
  return button
end

local function updateSelect(tf, prevCI )
  if tf.selectEnd==0 then
    --begin selecting
    tf.selectOrigin=prevCI
  end
  if tf.cursorIndex==tf.selectOrigin then
    tf.selectEnd=0
  elseif tf.cursorIndex>tf.selectOrigin then
    tf.selectStart=tf.selectOrigin
    tf.selectEnd=tf.cursorIndex-1
  else
    tf.selectStart=tf.cursorIndex
    tf.selectEnd=tf.selectOrigin-1
  end
end

local function removeSelectedTF(tf)
  tf.text=tf.text:sub(1,tf.selectStart-1)..tf.text:sub(tf.selectEnd+1)
  tf.cursorIndex=tf.selectStart
  tf.selectEnd=0
end

local function insertTextTF(tf,text)
  if tf.selectEnd~=0 then
    tf:removeSelected()
  end
  tf.text=tf.text:sub(1,tf.cursorIndex-1)..text..tf.text:sub(tf.cursorIndex)
  tf.cursorIndex=tf.cursorIndex+#text
  if tf.cursorIndex-tf.scrollIndex+1>tf.width then
    local ts=tf.scrollIndex+math.floor(tf.width/3)
    if tf.cursorIndex-ts+1>tf.width then
      ts=tf.cursorIndex-tf.width+math.floor(tf.width/3)
    end
    tf.scrollIndex=ts
  end
end

local function addTextField(gui,x,y,width)
  local tf=baseComponent(gui,x,y,width,1,"textfield",true)

  tf.text=""
  tf.cursorIndex=1
  tf.scrollIndex=1
  tf.selectStart=1
  tf.selectEnd=0
  tf.draw=drawTextField
  tf.insertText=insertTextTF
  tf.removeSelected=removeSelectedTF

  tf.doPaste=function(tf,text)
      tf:insertText(text)
      tf:draw()
    end
  tf.doCopy=function(tf)
      if tf.selectEnd~=0 then
        return tf.text:sub(tf.selectStart,tf.selectEnd)
      end
      return nil
    end
  tf.doCut=function(tf)
      local text=tf:doCopy()
      tf:removeSelected()
      tf:draw()
      return text
    end

  tf.onClick=function(tf,tx,ty)
      tf.selectEnd=0
      tf.cursorIndex=math.min(tx+tf.scrollIndex-1,#tf.text+1)
      tf:draw()
    end

  tf.onBeginDrag=function(tf,tx,ty,button)
      --drag events are in gui coords, not component, so correct
      if button==0 then
        tf.selectOrigin=math.min(tx-tf.posX+tf.scrollIndex,#tf.text+1)
        tf.dragging=tf.selectOrigin
        term.setCursorBlink(false)

      end
    end

  tf.onDrag=function(tf,tx,ty)
      if tf.dragging then
        local dragX=tx-tf.posX+1
        local prevCI=tf.cursorIndex
        tf.cursorIndex=math.max(math.min(dragX+tf.scrollIndex-1,#tf.text+1),1)
        if prevCI~=cursorIndex then
          updateSelect(tf,tf.selectOrigin)
          tf:draw()
        end
        if dragX<1 or dragX>tf.width then
          --it's dragging outside.
          local dragMagnitude=dragX-1
          if dragMagnitude>=0 then
            dragMagnitude=dragX-tf.width
          end
          local dragDir=dragMagnitude<0 and -1 or 1
          dragMagnitude=math.abs(dragMagnitude)
          local dragStep, dragRate
          if dragMagnitude>5 then
            dragRate=.1
            dragStep=dragMagnitude/5*dragDir
          else
            dragRate=(6-dragMagnitude)/10
            dragStep=dragDir
          end
          if tf.dragTimer then
            event.cancel(tf.dragTimer)
          end
          tf.dragTimer=event.timer(dragRate,function()
              tf.cursorIndex=math.max(math.min(tf.cursorIndex+dragStep,#tf.text+1),1)
              if tf.cursorIndex<tf.scrollIndex then
                tf.scrollIndex=tf.cursorIndex
              elseif tf.cursorIndex>tf.scrollIndex+tf.width-2 then
                tf.scrollIndex=tf.cursorIndex-tf.width+1
              end
              updateSelect(tf,tf.selectOrigin)
              tf:draw()
            end, math.huge)
        else
          if tf.dragTimer then
            event.cancel(tf.dragTimer)
          end
        end

      end
    end

  tf.onDrop=function()
    if tf.dragging then
      tf.dragging=nil
      if tf.dragTimer then
        event.cancel(tf.dragTimer)
      end
      term.setCursor(tf.posX+gui.posX-1+tf.cursorIndex-tf.scrollIndex,tf.posY+gui.posY-1)
      term.setCursorBlink(true)
    end
  end

  tf.keyHandler=function(tf,char,code)
      local dirty=false
      if not keyboard.isControl(char) then
        tf:insertText(unicode.char(char))
        dirty=true
      elseif code==28 and tf.tabNext then
        gui:changeFocusTo(tf.tabNext)
      elseif code==keyboard.keys.left then
        local prevCI=tf.cursorIndex
        if tf.cursorIndex>1 then
          tf.cursorIndex=tf.cursorIndex-1
          if tf.cursorIndex<tf.scrollIndex then
            tf.scrollIndex=math.max(1,tf.scrollIndex-math.floor(tf.width/3))
            dirty=true
          else
            term.setCursor(tf.posX+gui.posX-1+tf.cursorIndex-tf.scrollIndex,tf.posY+gui.posY-1)
          end
          term.setCursor(tf.posX+gui.posX-1+tf.cursorIndex-tf.scrollIndex,tf.posY+gui.posY-1)
        end
        if keyboard.isShiftDown() then
          updateSelect(tf,prevCI)
          dirty=true
        elseif tf.selectEnd~=0 then
          tf.selectEnd=0
          dirty=true
        end
      elseif code==keyboard.keys.right then
        local prevCI=tf.cursorIndex
        if tf.cursorIndex<#tf.text+1 then
          tf.cursorIndex=tf.cursorIndex+1

          if tf.cursorIndex>=tf.scrollIndex+tf.width then
            tf.scrollIndex=tf.scrollIndex+math.floor(tf.width/3)
            dirty=true
          else
            term.setCursor(tf.posX+gui.posX-1+tf.cursorIndex-tf.scrollIndex,tf.posY+gui.posY-1)
          end
        end
        if keyboard.isShiftDown() then
          updateSelect(tf,prevCI)
          dirty=true
        elseif tf.selectEnd~=0 then
          tf.selectEnd=0
          dirty=true
        end
      elseif code==keyboard.keys.home then
        local prevCI=tf.cursorIndex
        if tf.cursorIndex~=1 then
          tf.cursorIndex=1
          if tf.scrollIndex~=1 then
            tf.scrollIndex=1
            dirty=true
          else
            term.setCursor(tf.posX+gui.posX-1+tf.cursorIndex-tf.scrollIndex,tf.posY+gui.posY-1)
          end
        end
        if keyboard.isShiftDown() then
          updateSelect(tf,prevCI)
          dirty=true
        elseif tf.selectEnd~=0 then
          tf.selectEnd=0
          dirty=true
        end
      elseif code==keyboard.keys["end"] then
        local prevCI=tf.cursorIndex
        if tf.cursorIndex~=#tf.text+1 then
          tf.cursorIndex=#tf.text+1
          if tf.scrollIndex+tf.width-1<=tf.cursorIndex then
            tf.scrollIndex=tf.cursorIndex-tf.width+1
            dirty=true
          else
            term.setCursor(tf.posX+gui.posX-1+tf.cursorIndex-tf.scrollIndex,tf.posY+gui.posY-1)
          end
        end
        if keyboard.isShiftDown() then
          updateSelect(tf,prevCI)
          dirty=true
        elseif tf.selectEnd~=0 then
          tf.selectEnd=0
          dirty=true
        end
      elseif code==keyboard.keys.back then
        if tf.selectEnd~=0 then
          tf:removeSelected()
          dirty=true
        elseif tf.cursorIndex>1 then
          tf.text=tf.text:sub(1,tf.cursorIndex-2)..tf.text:sub(tf.cursorIndex)
          tf.cursorIndex=tf.cursorIndex-1
          if tf.cursorIndex<tf.scrollIndex then
            tf.scrollIndex=math.max(1,tf.scrollIndex-math.floor(tf.width/3))
          end
          dirty=true
        end
      elseif code==keyboard.keys.delete then
        if tf.selectEnd~=0 then
          tf:removeSelected()
          dirty=true
        elseif tf.cursorIndex<=#tf.text then
          tf.text=tf.text:sub(1,tf.cursorIndex-1)..tf.text:sub(tf.cursorIndex+1)
          dirty=true
        end
      end
      if dirty then
        tf:draw()
      end
    end


  tf.gotFocus=function()
    --we may want to scroll here, cursor to end of text on gaining focus
    local effText=tf.text

    if #effText>tf.width then
      tf.scrollIndex=#effText-tf.width+3
    else
      tf.scrollIndex=1
    end
    tf.cursorIndex=#effText+1
    tf:draw()
  end

  tf.lostFocus=function()
    tf.scrollIndex=1
    tf.selectEnd=0
    term.setCursorBlink(false)
    tf:draw()
  end

  gui.addComponent(tf)
  return tf
end


function gml.create(x,y,width,height)
  local screenWidth,screenHeight=component.gpu.getResolution()

  local newGui={type="gui", handlers={}, components={}, style=defaultStyle }
  assert(defaultStyle)
  newGui.posX,newGui.posY,newGui.width,newGui.height=parsePosition(x,y,width,height,screenWidth,screenHeight)

  local running=false
  function newGui.close()
    computer.pushSignal("gui_close")
  end

  function newGui.addComponent(component)
    newGui.components[#newGui.components+1]=component
  end

  newGui.addHandler=guiAddHandler

  function newGui.redrawRect(x,y,w,h)
    local fillCh,fillFG,fillBG=findStyleProperties(newGui,"fill-ch","fill-color-fg","fill-color-bg")
    local blank=(fillCh):rep(w)
    component.gpu.setForeground(fillFG)
    component.gpu.setBackground(fillBG)

    x=x+newGui.posX-1
    for y=y+newGui.posY-1,y+h+newGui.posY-2 do
      component.gpu.set(x,y,blank)
    end
  end

  function newGui.changeFocusTo(gui,target)
    if gui.focusElement then
      gui.focusElement.state=nil
      if gui.focusElement.lostFocus then
        gui.focusElement.lostFocus()
      else
        gui.focusElement:draw()
      end
      gui.focusElement=target
      target.state="focus"
      if target.gotFocus then
        target.gotFocus()
      else
        target:draw()
      end
    end
  end

  newGui.run=runGui
  newGui.contains=contains
  newGui.addLabel=addLabel
  newGui.addButton=addButton
  newGui.addTextField=addTextField

  return newGui
end




--**********************

defaultStyle=gml.loadStyle("default")


return gml