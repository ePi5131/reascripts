-- @noindex
---@meta
local C=...
local R=reaper

do
	local tbc_mt={__close=function(o)R.Undo_EndBlock2(o.proj,o.name,-1)end}
	---@param proj ReaProject
	---@param name string
	function C.undo_scope(proj,name)
		R.Undo_BeginBlock2(proj)
		local tbc=setmetatable({proj=proj,name=name},tbc_mt)
		return tbc
	end
end

do
	local tbc = setmetatable({},{__close=function()R.PreventUIRefresh(-1)end})
	function C.prevent_ui_refresh_scope()
		R.PreventUIRefresh(1)
		return tbc
	end
end

---@param f function
---@return table
function C.defer(f,...)
	local tbc=setmetatable({...},{__close=function(o)pcall(f,table.unpack(o))end})
	return tbc
end

---@param f fun(e)
---@return table
function C.defer_onerr(f)
	local tbc=setmetatable({},{__close=function(_,e)if e~=nil then return f(e)end end})
	return tbc
end

---@param proj ReaProject
---@param name string
---@param f function
function C.undo_section(proj,name,f,...)
	R.Undo_BeginBlock2(proj)
	local b,e=xpcall(f,function(e)return debug.traceback(e,2)end,...)
	R.Undo_EndBlock2(proj,name,-1)
	if not b then error(e)end
end

---@param f function
function C.prevent_ui_refresh_section(f,...)
	R.PreventUIRefresh(1)
	local b,e=xpcall(f,function(e)return debug.traceback(e,2)end,...)
	R.PreventUIRefresh(-1)
	if not b then error(e)end
 end

---@param f function
function C.section(f,...)
	local stack={}
	local function defer(f)
		stack[#stack+1]=f
	end

	local old_env
	do local i=1 while true do
		local k,v=debug.getupvalue(f,i)
		if(k=="_ENV")then
			old_env=v
			local new_env=setmetatable({defer=defer},{__index=old_env})
			debug.upvaluejoin(f,i,function()return new_env end,1)
			break
		elseif k==nil then break
		end
	i=i+1 end end

	if(old_env==nil)then error("_ENV not found",2)end

	local b,e=xpcall(f,function(e)return debug.traceback(e,2)end,...)
	for i=#stack,1,-1 do
		stack[i]()
	end

	do local i=1 while true do
		local k=debug.getupvalue(f,i)
		if(k=="_ENV")then
			debug.upvaluejoin(f,i,function()return old_env end,1)
			break
		elseif k==nil then break
		end
	i=i+1 end end

	if not b then error(e,0)end
end
