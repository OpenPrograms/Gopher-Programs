--[[
git repo downloader

downloads the full contents of a git repo to a directory on the computer.
--]]


local internet=require("internet")
local text=require("text")
local filesystem=require("filesystem")
local unicode=require("unicode")
local term=require("term")
local event=require("event")
local keyboard=require("keyboard")


local repo,target

local args={...}

if #args<1 or #args>2 then
  print("Usage: gitrepo <repo> [<targetdir>]]\nrepo should be the owner/repo, ex, \"OpenPrograms/Gopher-Programs\"\ntargetdir is an optional local path to download to, default will be /tmp/<repo>/")
  return
end

repo=args[1]
if not repo:match("^[%w-.]*/[%w-.]*$") then
  print('"'..args[1]..'" does not look like a valid repo identifier.\nShould be <owner>/<reponame>')
  return
end

target=args[2]
target=target and ("/"..target:match("^/?(.-)/?$").."/") or "/tmp/"..repo
if filesystem.exists(target) then
  if not filesystem.isDirectory(target) then
    print("target directory already exists and is not a directory.")
    return
  end
  if filesystem.get(target).isReadOnly() then
    print("target directory is read-only.")
    return
  end
else
  if not filesystem.makeDirectory(target) then
    print("target directory is read-only")
    return
  end
end



-- this isn't acually used, but it is tested and works on decoding the base64 encoded data that github
--sends for some queries, leaving it in here for possible future/related use, might be able to pull
--and display difs and things like that?
local symb="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function decode64(text)
  local val,bits=0,0
  local output=""
  for ch in text:gmatch(".") do
    if symb:find(ch) then
      --print("ch "..ch.."-> "..(symb:find(ch)-1))
      val=bit32.lshift(val,6)+symb:find(ch)-1
    else
      print(ch.."?")
      return
    end
    bits=bits+6
    --print("bits : "..bits)
    --print(string.format("val : 0x%04x",val))
    if bits>=8 then
      local och=unicode.char(bit32.rshift(val,bits-8))
      --print("os<<"..och)
      --print("& with "..(2^(bits-8)-1))
      val=bit32.band(val,2^(bits-8)-1)
      bits=bits-8
      --print(string.format("val : 0x%04x",val))
      output=output..och
    end
  end
  return output
end



local function gitContents(repo,dir)
  print("fetching contents for "..repo..dir)
  local url="https://api.github.com/repos/"..repo.."/contents"..dir
  local result,response=pcall(internet.request,url)
  local raw=""
  local files={}
  local directories={}

  if result then
    for chunk in response do
      raw=raw..chunk
    end
  else
    error("you've been cut off. Serves you right.")
  end

  response=nil
  raw=raw:gsub("%[","{"):gsub("%]","}"):gsub("(\".-\"):(.-[,{}])",function(a,b) return "["..a.."]="..b end)
  local t=load("return "..raw)()

  for i=1,#t do
    if t[i].type=="dir" then
      table.insert(directories,dir.."/"..t[i].name)

      local subfiles,subdirs=gitContents(repo,dir.."/"..t[i].name)
      for i=1,#subfiles do
        table.insert(files,subfiles[i])
      end
      for i=1,#subdirs do
        table.insert(directories,subdirs[i])
      end
    else
      files[#files+1]=dir.."/"..t[i].name
    end
  end

  return files, directories
end

local files,dirs=gitContents(repo,"")

for i=1,#dirs do
  print("making dir "..target..dirs[i])
  if filesystem.exists(target..dirs[i]) then
    if not filesystem.isDirectory(target..dirs[i]) then
      print("error: directory "..target..dirs[i].." blocked by file with the same name")
      return
    end
  else
    filesystem.makeDirectory(target..dirs[i])
  end
end

local replaceMode="ask"
for i=1,#files do
  local replace=nil
  if filesystem.exists(target..files[i]) then
    if filesystem.isDirectory(target..files[i]) then
      print("Error: file "..target..files[i].." blocked by directory with same name!")
      return
    end
    if replaceMode=="always" then
      replace=true
    elseif replaceMode=="never" then
      replace=false
    else
      print("\nFile "..target..files[i].." already exists.\nReplace with new version?")
      local response=""
      while replace==nil do
        term.write("yes,no,always,skip all[ynAS]: ")
        local char
        repeat
          _,_,char=event.pull("key_down")
        until not keyboard.isControl(char)
        char=unicode.char(char)
        print(char)
        if char=="A" then
          replaceMode="always"
          replace=true
          char="y"
        elseif char=="S" then
          replaceMode="never"
          replace=false
          char="n"
        elseif char:lower()=="y" then
          replace=true
        elseif char:lower()=="n" then
          replace=false
        else
          print("invalid response.")
        end
      end
    end
    if replace then
      filesystem.remove(target..files[i])
    end
  end
  if replace~=false then
    print("downloading "..files[i])
    local url="https://raw.github.com/"..repo.."/master"..files[i]
    local result,response=pcall(internet.request,url)
    if result then
      local raw=""
      for chunk in response do
        raw=raw..chunk
      end
      print("writing to "..target..files[i])
      local file=io.open(target..files[i],"w")
      file:write(raw)
      file:close()

    else
      print("failed, skipping")
    end
  end
end


