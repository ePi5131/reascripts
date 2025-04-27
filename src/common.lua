--[[
@provides
  [nomain] . > ..
  [nomain] common/*.lua > ../common/
@description ePi5131-ReaScripts Common Lib
@version 1.0
@author ePi
]]
local C={}

local R=reaper

C.root_dir=R.GetResourcePath()..[[\Scripts\ePi5131-ReaScripts\]]

local sub_dir=C.root_dir..[[common\]]

function C.version()
  return {1,0,0}
end

local function load_sub(name)
  local f,e=loadfile(("%s%s.lua"):format(sub_dir,name))
  if not f then
    error(e)
  end
  return f(C)
end

function C.get_script_name()
  local _,filename=reaper.get_action_context()
  return filename:match".*[\\/](.+)"
end

function C.print(...)
  local function ts(x)
    local ty=type(x)
    if ty=="table" then
      local mt=getmetatable(x)
      if mt and mt.__tostring then
        return mt.__tostring(x)
      end
      local ret={}
      for k,v in pairs(x)do
        ret[1+#ret]=("[%s]=%s"):format(k,ts(v))
      end
      return "{"..table.concat(ret,",").."}"
    else
      return tostring(x)
    end
  end
  local n=select("#",...)
  local s="!SHOW:"
  for i=1,n-1 do
    s=s..ts(select(i,...)).."\t"
  end
  if(n>0)then
    s=s..ts(select(n,...))
  end
  s=s.."\n"
  R.ShowConsoleMsg(s)
end

function C.error_print(name)
  if(name==nil)then
    name=C.get_script_name()
  end
  return function(msg)
    R.ShowConsoleMsg(("[%s error]\n%s\n"):format(name,msg))
  end
end

---@generic T
---@alias BoundFunc fun(t:T[], x:T, c:CompFunc, p:function | string | nil): number

---@param name "lower"|"upper"
---@return BoundFunc
local function t4_bound(name)
  local c1=[[
local t,x,c,p=...
local n=#t
local a,b=1,n+1
local type_p=type(p)

if c~=nil then
%s
else
%s
end
return a]]

  local c2=[[
if type_p=="nil" then
%s
elseif type_p=="string" then
%s
else
%s
end]]

  local c3=[[
while a<b do
  local m=a+(b-a)//2
  if %s then %s
  else %s end
end]]

  -- cmp_pattern
  local cp={
    "c(%s,%s)",
    "%s<%s"
  }

  -- proj_pattern
  local pp={
    "%s",
    "%s[p]",
    "p(%s)"
  }

  local itra=({
    lower={"a=m+1","b=m"},
    upper={"b=m","a=m+1"}
  })[name]

  local cmpa=({
    lower=function(p)return p:format"t[m]","x"end,
    upper=function(p)return "x",p:format"t[m]"end
  })[name]

  local c0=c1:format(
    c2:format(
      c3:format(cp[1]:format(cmpa(pp[1])),table.unpack(itra)),
      c3:format(cp[1]:format(cmpa(pp[2])),table.unpack(itra)),
      c3:format(cp[1]:format(cmpa(pp[3])),table.unpack(itra))
    ),
    c2:format(
      c3:format(cp[2]:format(cmpa(pp[1])),table.unpack(itra)),
      c3:format(cp[2]:format(cmpa(pp[2])),table.unpack(itra)),
      c3:format(cp[2]:format(cmpa(pp[3])),table.unpack(itra))
    )
  )

  return assert(load(c0,("t4_bound(%s)"):format(name),"t"))
end

C.lower_bound=t4_bound"lower"
C.upper_bound=t4_bound"upper"

do -- common.include
  ---@param name string
  ---@return integer
  ---@return integer
  ---@return any
  ---@overload fun(name:string):nil
  local function find_local_var(name)
    local i=5 while debug.getinfo(i,"")do
      local j=1 while true do
        local k,v=debug.getlocal(i,j)
        if k==name then return i,j,v end
        if k==nil then break end
      j=j+1 end
    i=i+1 end
    return nil
  end

  local function index(_,k)
    local i,j,v=find_local_var(k)
    if i~=nil then return v
    else return _ENV[k] end
  end

  local function newindex(_,k,v)
    local i,j=find_local_var(k)
    if(i~=nil)then debug.setlocal(i-1,j,v)
    else _ENV[k]=v end
  end

  local meta={
    __index=index,
    __newindex=newindex
  }

  function C.include(file)
    return assert(loadfile(("%s%s.lua"):format(sub_dir,file),nil,setmetatable({},meta)))()
  end
end


---@param proj ReaProject
function C.get_selected_items(proj)
  local n=R.CountSelectedMediaItems(proj)
  local ret={}
  for i=0,n-1 do
    table.insert(ret,R.GetSelectedMediaItem(proj,i))
  end
  return ret
end

---@param proj ReaProject
function C.each_selected_items(proj)
  local n=R.CountSelectedMediaItems(proj)
  local i=0
  local itr=function()
    if(i>=n)then return nil end
    local t=i
    i=i+1
    return i,R.GetSelectedMediaItem(proj,t)
  end
  return itr
end

---@param take MediaItem_Take
function C.each_midi_note(take)
  local retval,notecnt,ccevtcnt,textsyxevtcnt=R.MIDI_CountEvts(take)
  local i=0
  local function itr()
    if(i>=notecnt)then return nil end
    local t=i
    i=i+1
    local retval,selected,muted,startppqpos,endppqpos,chan,pitch,vel=R.MIDI_GetNote(take,t)
    if not retval then return nil end
    return i,selected,muted,startppqpos,endppqpos,chan,pitch,vel
  end
  return itr
end


---@param keys string[]
---@return function
function C.create_compare(keys)
  local n=#keys
  return function(a,b)
    for i=1,n-1 do
      if(a[keys[i]]~=b[keys[i]])then
        return a[keys[i]]<b[keys[i]]
      end
    end
    return a[keys[n]]<b[keys[n]]
  end
end


---@param proj ReaProject
---@return integer
function C.get_max_group_id(proj)
  local max_group=0
  for _=0,R.CountMediaItems(proj)-1 do local item=R.GetMediaItem(proj,_)
    local group_id=R.GetMediaItemInfo_Value(item,"I_GROUPID")--[[@as integer]]
    if(max_group<group_id)then max_group=group_id end
  end
  return max_group
end

load_sub"rppxml"
load_sub"table"
load_sub"scope"
load_sub"array"

return C
