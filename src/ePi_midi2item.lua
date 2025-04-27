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
local units=m2i.prepare(proj)
m2i.main(proj,function()return C.undo_scope(proj,"midi2item")end,units,nil)
