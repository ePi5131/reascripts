-- @noindex

local R=reaper
R.defer(function()end)
do local n,f,e="ePi5131-ReaScripts Common Lib",loadfile(R.GetResourcePath()..[[\Scripts\ePi5131-ReaScripts\common.lua]],"t")
  if not f then
    if e:match"cannot open"then---@diagnostic disable-line
      local r=R.ShowMessageBox("This script requires '"..n.."'.\nWould you like to open ReaPack now?","midi2item",4)
      if r==6 then R.ReaPack_BrowsePackages(n)end
      return
    end
    error(e)
  end
  package.loaded.ePi5131=f()
end
local C=require"ePi5131"

local f,e=loadfile(C.root_dir.."_midi2item_common.lua")
if not f then error(e)end

local proj=0
local m2i=f()

local tracks={}
local bb=false
local n=R.CountTracks(proj)
for i=0,n-1 do local track=R.GetTrack(proj,i)
  local b=m2i.preset_local_has(track)
  bb=bb or b
  tracks[i]=b
end

if not bb then
  R.ShowMessageBox("保存された設定はありません。","midi2item",0)
  return
end

local _<close> =C.defer(R.UpdateArrange)
local _<close> =C.prevent_ui_refresh_scope()
-- トラックの選択状態は設定次第ではアンドゥできない
-- General > Undo settings を参照
local _<close> =C.undo_scope(proj,"midi2item - Select configurated tracks")

for i=0,n-1 do local track=R.GetTrack(proj,i)
  R.SetTrackSelected(track,tracks[i])
end
