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

local proj=0

local dbg_frame<const> =false

local fonts={
	set=function(o,i)
		gfx.setfont(i,table.unpack(o[i]))
	end,
	{ "Arial",16 },
	{ "Arial",14 }
}

local state_mt={

}
local function make_state(v)
	return setmetatable({value=v},state_mt)
end

local function state_read(x)
	if type(x)=="table"then
		local mt=getmetatable(x)
		if mt==state_mt then
			return x.value
		end
	end
	return x
end

local function state_write(x,v)
	if type(x)=="table"then
		local mt=getmetatable(x)
		if mt==state_mt then
			x.value=v
		end
	end
end

---@class rect_edge
---@field [1] integer
---@field [2] integer
---@field [3] integer
---@field [4] integer
---@field left integer
---@field top integer
---@field right integer
---@field bottom integer
---@field row fun(o:rect_edge):integer,integer
---@field col fun(o:rect_edge):integer,integer
---@field width fun(o:rect_edge):integer
---@field height fun(o:rect_edge):integer

local rect_edge_mt={
	keys={
		left=1,top=2,right=3,bottom=4
	},
	methods={
		horizontal=function(o)
			return o.left,o.right
		end,
		vertical=function(o)
			return o.top,o.bottom
		end,
		width=function(o)
			return o.left+o.right
		end,
		height=function(o)
			return o.top+o.bottom
		end
	},
	__index=function(o,k)
		local mt=getmetatable(o)
		local i=mt.keys[k]
		if i then return o[i]end
		return mt.methods[k]
	end
}

---@return rect_edge
local function make_rect_edge(t)
	if t==nil then return setmetatable({0,0,0,0},rect_edge_mt)end
	if type(t)=="number"then return setmetatable({t,t,t,t},rect_edge_mt)end
	local n=#t
	if n==4 then
		return setmetatable({t[1],t[2],t[3],t[4]},rect_edge_mt)
	elseif n==3 then
		return setmetatable({t[1],t[2],t[3],t[2]},rect_edge_mt)
	elseif n==2 then
		return setmetatable({t[1],t[2],t[1],t[2]},rect_edge_mt)
	elseif n==1 then
		return setmetatable({t[1],t[1],t[1],t[1]},rect_edge_mt)
	end
	error("invalid arguments",2)
end

---@class draw_context
---@field x integer
---@field y integer

---@class window_object
---@field update fun(o:window_object,ctx:draw_context,mouse,char)
---@field draw fun(o:window_object,ctx:draw_context)
---@field x integer
---@field y integer
---@field width integer
---@field height integer
---@field padding rect_edge
---@field margin rect_edge
---@field user table
---@field states table

---@class window_param
---@field width? integer
---@field height? integer
---@field padding integer[]
---@field margin integer[]
---@overload fun(window_param):window_object

local function make_window_object(t)
	local states=t.states
	if states==nil then return t end
	for k,v in pairs(states)do
		if type(v)~="table" or getmetatable(v)~=state_mt then
			states[k]=make_state(v)
		end
	end
	t.states=setmetatable({},{
		__index=function(o,k)
			return states[k].value
		end,
		__newindex=function(o,k,v)
			states[k].value=v
		end
	})
	return t
end

local ctx_mt={
	__index={
		---@param x integer
		---@param y integer
		---@param w integer
		---@param h integer
		---@param flll boolean
		rect=function(o,x,y,w,h,color,flll)
			gfx.set(table.unpack(color))
			gfx.rect(o.x+x,o.y+y,w,h,flll)
		end,
		---@param x integer
		---@param y integer
		---@param str string
		text=function(o,x,y,str,color)
			gfx.x=o.x+x gfx.y=o.y+y
			gfx.set(table.unpack(color))
			gfx.drawstr(str)
		end,
		line=function(o,x1,y1,x2,y2,color,aa)
			gfx.set(table.unpack(color))
			gfx.line(o.x+x1,o.y+y1,o.x+x2,o.y+y2,aa)
		end,
		line_seq=function(o,seq,color,aa)
			gfx.set(table.unpack(color))
			gfx.x=o.x+seq[1][1]
			gfx.y=o.y+seq[1][2]
			for i=2,#seq do
				gfx.lineto(o.x+seq[i][1],o.y+seq[i][2],aa)
			end
		end,
		intersects=function(o,mouse,x,y,w,h)
			x=mouse.x-o.x-x
			y=mouse.y-o.y-y
			return 0<=x and x<w and 0<=y and y<h
		end
	}
}

---@param ctx? draw_context
local function make_ctx(ctx)
	if ctx then return C.table.copy(ctx) end
	return setmetatable({
		x=0,
		y=0,
	},ctx_mt)
end

local br<const> ={
	init=function()end,
	update=function()end,
	draw=function()end
}

local check_mt={__index={
	update=function(o,ctx,mouse,c)
		local us=o.user
		if not o.states.enabled then
			us.hover=false
			us.pressed=false
			return
		end
		if ctx:intersects(mouse,0,0,o.width,o.height)then
			us.hover=true
			if mouse.LMB_clicked then
				us.pressed=true
			elseif mouse.LMB_released then
				if us.pressed then
					o.states.value=not o.states.value
					us.pressed=false
				end
			end
		else
			us.hover=false
			if us.pressed then
				if mouse.LMB_released then
					us.pressed=false
				end
			end
		end
	end,
	draw=function(o,ctx)
		local e=o.states.enabled
		ctx:rect(o.padding[1],o.padding[2]+3,10,10,e and {.98} or {.4},false)
		if o.states.value then
			local col=e and (o.user.hover and (o.user.pressed and {.2,.3,.22} or {.2,.75,.27}) or {.2,.8,.3}) or {.4}
			ctx:rect(o.padding[1]+2,o.padding[2]+5,6,6,col,true)
		else
			local col=e and (o.user.hover and (o.user.pressed and {.3,.85,.35} or {.2,.3,.22}) or {.2,.2,.2}) or {.2}
			ctx:rect(o.padding[1]+2,o.padding[2]+5,6,6,col,true)
		end
		fonts:set(o.user.font)
		ctx:text(o.padding[1]+15,o.padding[2],o.states.caption,e and {.98} or {.4})
	end
}}
local check_factory_mt={__call=function(o)
	fonts:set(o.font)
	local p=make_rect_edge(o.padding)
	local m=make_rect_edge(o.margin)
	local c=o.caption or make_state("")
	local v=o.value or make_state(false)
	local e=o.enabled or make_state(true)
	return make_window_object(setmetatable({
		padding=p,
		margin=m,
		width=(o.width or (gfx.measurestr(tostring(state_read(c)))+15))+p:width(),
		height=(o.height or math.max(gfx.texth,13))+p:height(),
		user={
			font=o.font,
			hover=false,
			pressed=false,
		},
		states={
			value=v,
			caption=c,
			enabled=e,
		},
	},check_mt))
end}
---@return window_object
local function check(t)return setmetatable(t,check_factory_mt)end

local label_mt={__index={
	update=function()end,
	draw=function(o,ctx)
		local col=o.states.enabled and {.98} or {.4}
		fonts:set(o.user.font)
		ctx:text(o.padding[1],o.padding[2],tostring(o.states.caption),col)
	end
}}
local label_factory_mt={__call=function(o)
	fonts:set(o.font)
	local p=make_rect_edge(o.padding)
	local m=make_rect_edge(o.margin)
	local c=o.caption or make_state("")
	local e=o.enabled or make_state(true)
	return make_window_object(setmetatable({
		padding=p,
		margin=m,
		width=(o.width or gfx.measurestr(tostring(state_read(c))))+p:width(),
		height=(o.height or gfx.texth)+p:height(),
		user={
			font=o.font,
		},
		states={
			caption=c,
			enabled=e,
		}
	},label_mt))
end}
---@return window_object
local function label(t)return setmetatable(t,label_factory_mt)end

local button_mt={__index={
	update=function(o,ctx,mouse)
		local us=o.user
		if ctx:intersects(mouse,0,0,o.width,o.height)then
			us.hover=true
			if mouse.LMB_clicked then
				us.pressed=true
			elseif mouse.LMB_released then
				if us.pressed then
					if us.on_click then us.on_click()end
					us.pressed=false
				end
			end
		else
			us.hover=false
			if us.pressed then
				if mouse.LMB_released then
					us.pressed=false
				end
			end
		end
	end,
	draw=function(o,ctx)
		local col=o.user.hover and (o.user.pressed and {.2,.6,.3} or {.22,.35,.2}) or {.2}
		ctx:rect(0,0,o.width,o.height,col,true)
		ctx:rect(0,0,o.width,o.height,{.98},false)
		fonts:set(o.user.font)
		ctx:text(o.padding[1],o.padding[2],o.states.caption,{.98})
	end
}}
local button_factory_mt={__call=function(o)
	local p=make_rect_edge(o.padding)
	local m=make_rect_edge(o.margin)
	local c=o.caption or make_state("")
	fonts:set(o.font)
	return make_window_object(setmetatable({
		padding=p,
		margin=m,
		width=(o.width or gfx.measurestr(tostring(state_read(c))))+p:width(),
		height=(o.height or gfx.texth)+p:height(),
		user={
			font=o.font,
			hover=false,
			pressed=false,
			on_click=o.on_click
		},
		states={
			caption=c
		}
	},button_mt))
end}
---@return window_object
local function button(t)
	return setmetatable(t,button_factory_mt)
end

local spin_mt={__index={
	update=function(o,ctx,mouse,c)
		if not ctx:intersects(mouse,0,0,o.width,o.height)then return end
		local wheel=o.user.wheel_remain+mouse.wheel
		if math.abs(wheel)>=120 then
			local amount=wheel//120
			o.user.wheel_remain=0
			local v0=o.states.value
			if mouse.Shift then amount=amount*o.user.jump end
			local v1=v0+amount
			if o.user.min and v1<o.user.min then v1=o.user.min end
			if o.user.max and v1>o.user.max then v1=o.user.max end
			if v0~=v1 then
				o.states.value=v1
				if o.user.on_change then o.user.on_change(o.states.value)end
			end
		end
	end,
	draw=function(o,ctx)
		local e=o.states.enabled
		ctx:rect(0,0,o.width,o.height,e and {.3} or {.2},true)
		ctx:rect(0,0,o.width,o.height,e and {.98} or {.4},false)
		fonts:set(o.user.font)
		ctx:text(o.padding[1],o.padding[2],tostring(o.states.value),e and {.98} or {.4})
	end
}}
local spin_factory_mt={__call=function(o)
	fonts:set(o.font)
	local p=make_rect_edge(o.padding)
	local m=make_rect_edge(o.margin)
	local c=o.value or 0
	local e=o.enabled or true
	local r=make_window_object(setmetatable({
		padding=p,
		margin=m,
		width=(o.width or gfx.measurestr(tostring(state_read(c))))+p:width(),
		height=(o.height or gfx.texth)+p:height(),
		user={
			font=o.font,
			hover=false,
			pressed=false,
			wheel_remain=0,
			on_change=o.on_change,
			min=o.min,
			max=o.max,
			jump=o.jump or 1
		},
		states={
			value=c,
			enabled=e,
		}
	},spin_mt))
	if r.user.on_change then r.user.on_change()end
	return r
end}
---@return window_param
local function spin(t)return setmetatable(t,spin_factory_mt)
end

local child_mt={__index={
	update=function(o,ctx,mouse,c)
		local wins=o.user.windows
		for i=1,#wins do local win=wins[i]
			local child_ctx=make_ctx(ctx)
			child_ctx.x=child_ctx.x+win.x
			child_ctx.y=child_ctx.y+win.y
			win:update(child_ctx,mouse,c)
		end
	end,
	draw=function(o,ctx)
		local wins=o.user.windows
		for i=1,#wins do local win=wins[i]
			local child_ctx=make_ctx(ctx)
			child_ctx.x=child_ctx.x+win.x
			child_ctx.y=child_ctx.y+win.y
			win:draw(child_ctx)
			if dbg_frame then
				child_ctx:rect(0,0,win.width,win.height,{.5},false)
			end
		end
	end
}}
local child_factory_mt={__call=function(o)
	local p=make_rect_edge(o.padding)
	local m=make_rect_edge(o.margin)
	local x<const>,y<const> =p[1],p[2]
	local ox,oy=0,0
	local width=0
	local row_height=0
	local windows={} ---@type window_object[]
	for _,wp in ipairs(o)do ---@cast wp window_param
		if wp==br then
			if width<ox then width=ox end
			oy=oy+row_height
			ox=0
			row_height=0
		else
			local win=wp()
			windows[1+#windows]=win
			win.x=x+ox+win.margin[1]
			win.y=y+oy+win.margin[2]
			ox=ox+win.width+win.margin:width()
			local th=win.height+win.margin:height()
			if row_height<th then row_height=th end
		end
	end
	if width<ox then width=ox end
	oy=oy+row_height
	return make_window_object(setmetatable({
		padding=p,
		margin=m,
		width=width,
		height=oy,
		user={
			windows=windows,
		},
	},child_mt))
end}
---@return window_param
local function child(t)return setmetatable(t,child_factory_mt)end


---@class windows_args
---@field title string
---@field width integer
---@field height integer
---@field margin rect_edge
---@field bg { r: number, g: number, b: number }
---@field [integer] window_param

local function window(t)
	if R.BR_Win32_GetMainHwnd and R.BR_Win32_GetWindowRect then
		local hwnd=R.BR_Win32_GetMainHwnd()
		local _,left,top,right,bottom=R.BR_Win32_GetWindowRect(hwnd)
		gfx.init(t.title,t.width,t.height,0,left+(right-left-t.width)//2,top+(bottom-top-t.height)//2)
	else
		gfx.init(t.title,t.width,t.height,0,R.GetMousePosition())
	end

	local mouse_cap_mask<const> ={
			LMB  =1 ,
			RMB  =2 ,
			Ctrl =4 ,
			Shift=8 ,
			Alt  =16,
			Win  =32,
			MMB  =64
	}

	local mouse=setmetatable(
			{last_state=0,clicked=0,released=0},
			{__index=function(o,k)
					local btn,op=k:match("(%S+)_(%S+)")
					if(btn)then
							if(op=="clicked")then
									return (o.clicked &mouse_cap_mask[btn])~=0
							elseif(op=="released")then
									return (o.released&mouse_cap_mask[btn])~=0
							end
					end
					if(mouse_cap_mask[k])then
							return (o.last_state&mouse_cap_mask[k])~=0
					end
					return nil
			end})

	local function mouse_update()
			local diff=mouse.last_state~gfx.mouse_cap
			mouse.clicked=diff&gfx.mouse_cap
			mouse.released=diff&~gfx.mouse_cap
			mouse.last_state=math.tointeger(gfx.mouse_cap)
			mouse.x=gfx.mouse_x
			mouse.y=gfx.mouse_y
			mouse.wheel=math.tointeger(gfx.mouse_wheel)
			gfx.mouse_wheel=0
	end

	local root=child(t)()

	local function callback()
		xpcall(function()
			local c=gfx.getchar()
			mouse_update()
			local _<close> =C.defer(gfx.update)
			if c~=-1 and c~=27 then R.runloop(callback) end
			gfx.set(t.bg.r,t.bg.g,t.bg.b)
			gfx.rect(0,0,gfx.w,gfx.h,1)

			local ctx=make_ctx()
			ctx.x=root.margin[1]
			ctx.y=root.margin[2]
			root:update(ctx,mouse,c)
			root:draw(ctx)
			if dbg_frame then
				ctx:rect(0,0,root.width,root.height,{.5},false)
			end
		end,function(e)C.print(debug.traceback(e,2),2)end)
	end
	R.runloop(callback)
end

xpcall(function()
local f,e=loadfile(C.root_dir.."_midi2item_common.lua")
if not f then error(e)end
local m2i=f()

local base_pitch_enabled=make_state(true)
local base_pitch=make_state(60)
local base_pitch_str=make_state("")
local base_vel_enabled=make_state(true)
local base_vel=make_state(96)
local use_take_pitch=make_state(true)
local channel_aware=make_state(true)
local make_new_root=make_state(true)
local name_track=make_state(true)
local default_pitchbend_range=make_state(2)
local use_pitchbend_change=make_state(true)
local preset_index=make_state(1)

local function from_state()
	local p={
		use_take_pitch=use_take_pitch.value,
		channel_aware=channel_aware.value,
		make_new_root=make_new_root.value,
		name_track=name_track.value,
		default_pitchbend_range=default_pitchbend_range.value,
		use_pitchbend_change=use_pitchbend_change.value,
	}
	if base_pitch_enabled.value then p.base_pitch=base_pitch.value end
	if base_vel_enabled.value then p.base_vel=base_vel.value end
	return p
end

local function to_state(p)
	base_pitch_enabled.value=p.base_pitch~=nil
	if p.base_pitch then base_pitch.value=p.base_pitch end
	base_vel_enabled.value=p.base_vel~=nil
	if p.base_vel then base_vel.value=p.base_vel end
	use_take_pitch.value=p.use_take_pitch
	channel_aware.value=p.channel_aware
	make_new_root.value=p.make_new_root
	name_track.value=p.name_track
	default_pitchbend_range.value=p.default_pitchbend_range
	use_pitchbend_change.value=p.use_pitchbend_change
end

window{
	title="midi2itemの設定",
	width=240,
	height=342,
	margin={10,6},
	bg={r=.2,g=.2,b=.2},
	child{
		check{
			margin=4,
			padding={0,2},
			caption="音高",
			font=1,
			value=base_pitch_enabled,
		},
		label{
			caption=" - 基準",
			padding={0,2},
			margin={8,4,4},
			font=1,
			enabled=base_pitch_enabled,
		},
		spin{
			padding=2,
			margin=4,
			width=24,
			font=1,
			enabled=base_pitch_enabled,
			value=base_pitch,
			jump=12,
			min=0,
			max=127,
			on_change=function()
				state_write(base_pitch_str,("(%s)"):format(m2i.pitch_i2s(state_read(base_pitch))))
			end
		},
		label{
			padding={0,2},
			margin=4,
			font=1,
			enabled=base_pitch_enabled,
			caption=base_pitch_str,
		},
	},
	br,
	child{
		check{
			caption="ベロシティ",
			padding={0,2},
			margin=4,
			font=1,
			value=base_vel_enabled,
		},
		label{
			caption=" - 基準",
			padding={0,2},
			margin={8,4,4},
			font=1,
			enabled=base_vel_enabled,
		},
		spin{
			padding=2,
			margin=4,
			width=24,
			font=1,
			enabled=base_vel_enabled,
			value=base_vel,
			jump=16,
			min=0,
			max=127,
		},
	},
	br,
	check{
		caption="テイクのピッチを加算",
		margin=4,
		font=1,
		value=use_take_pitch,
	},
	br,
	check{
		caption="チャンネルを区別する",
		margin=4,
		font=1,
		value=channel_aware,
	},
	br,
	check{
		caption="親トラックを新規作成",
		margin=4,
		font=1,
		value=make_new_root,
	},
	br,
	check{
		caption="トラック名を付加",
		margin=4,
		font=1,
		value=name_track,
	},
	br,
	label{
		caption="ピッチベンド",
		margin={4,8,4,4},
		font=1,
	},
	br,
	label{
		caption=" - 幅",
		padding={0,2},
		margin=4,
		font=1,
	},
	spin{
		padding=2,
		margin=4,
		width=24,
		font=1,
		value=default_pitchbend_range,
		min=0,
		max=12,
	},
	br,
	label{
		caption=" -",
		margin=4,
		font=1,
	},
	check{
		caption="範囲変更メッセージ",
		margin={0,4,4},
		font=1,
		value=use_pitchbend_change,
	},
	br,
	child{
		margin={0,4},
		label{
			caption="プリセット",
			padding={0,2},
			margin=4,
			font=1,
		},
		spin{
			padding=2,
			margin=4,
			width=12,
			font=1,
			value=preset_index,
			min=1,
			max=5,
		},
		button{
			caption="読込",
			padding=2,
			margin=4,
			font=1,
			on_click=function()
				local p=m2i.preset_global_load(preset_index.value)
				if p then
					to_state(p)
				else
					R.ShowMessageBox("保存された設定はありません。","midi2item",0)
				end
			end
		},
		button{
			caption="保存",
			padding=2,
			margin=4,
			font=1,
			on_click=function()
				m2i.preset_global_store(preset_index.value,from_state())
			end
		},
		button{
			caption="削除",
			padding=2,
			margin=4,
			font=1,
			on_click=function()
				m2i.preset_global_delete(preset_index.value)
			end
		}
	},
	br,
	child{
		label{
			padding={0,2},
			margin=4,
			caption="トラックの設定",
			font=1,
		},
		button{
			caption="読込",
			padding=2,
			margin=4,
			font=1,
			on_click=function()
				local units=m2i.prepare(proj)
				local p0=nil
				for i=1,#units do local unit=units[i]
					local p=m2i.preset_local_load(unit.track)
					if p0==nil then p0=p
					elseif not m2i.preset_equals(p,p0)then
						R.ShowMessageBox("異なる設定のアイテムが選択されています。","midi2item",0)
						return
					end
				end
				if p0==nil then
					R.ShowMessageBox("保存された設定はありません。","midi2item",0)
				elseif p0~=false then
					to_state(p0)
				end
			end
		},
		button{
			caption="保存",
			padding=2,
			margin=4,
			font=1,
			on_click=function()
				local units=m2i.prepare(proj)
				local _<close> =C.defer(R.Undo_OnStateChange2,proj,"midi2item (Set track configuration)")
				for _=1,#units do local unit=units[_]
					m2i.preset_local_store(unit.track,from_state())
				end
			end
		},
		button{
			caption="削除",
			padding=2,
			margin=4,
			font=1,
			on_click=function()
				local units=m2i.prepare(proj)
				local _<close> =C.defer(R.Undo_OnStateChange2,proj,"midi2item (Delete track configuration)")
				for _=1,#units do local unit=units[_]
					m2i.preset_local_delete(unit.track)
				end
			end
		}
	},
	br,
	child{
		margin={0,4},
		button{
			caption="実行",
			padding=4,
			margin=4,
			font=1,
			on_click=function()
				local param=from_state()
				local units=m2i.prepare(proj)
				m2i.main(proj,function()return C.defer(R.Undo_OnStateChange2,proj,"midi2item (Configurated)")end,units,param)
			end,
		},
		button{
			caption="閉じる",
			padding=4,
			margin=4,
			font=1,
			on_click=function()gfx.quit()end
		},
	}
}
end,function(e)C.print(debug.traceback(e,2),2)end)
