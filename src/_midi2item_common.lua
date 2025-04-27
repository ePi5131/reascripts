-- @noindex
---@meta _midi2item_common
local m2i={}

local R,C=reaper,require"ePi5131"

---@class (exact) m2i_param
---@field base_pitch integer? # 基準ピッチ nilの場合ドラムモード
---@field base_vel integer? # 基準ベロシティ nilの場合見ない
---@field use_take_pitch boolean # テイクのピッチを加算する
---@field channel_aware boolean # 異なるチャンネルを区別する
---@field make_new_root boolean # MIDIアイテムの子トラックではなく、新しいトラックへ展開する
---@field name_track boolean # トラック名をつける
---@field default_pitchbend_range integer # ピッチベンドのデフォルト値
---@field use_pitchbend_change boolean # ピッチベンド範囲の変更メッセージを読む

---@type m2i_param
m2i.param_default={
	base_pitch=60,
	base_vel=96,
	use_take_pitch=false,
	channel_aware=true,
	make_new_root=true,
	name_track=true,
	default_pitchbend_range=2,
	use_pitchbend_change=true,
}

local param_keys={"base_pitch","base_vel","use_take_pitch","channel_aware","make_new_root","name_track","default_pitchbend_range","use_pitchbend_change"}

local CHANNEL_MAX<const> =16

---C4 や Gb5 のような音名をピッチに変換
---REAPERではC4=60
---@param s string
---@return integer?
function m2i.pitch_s2i(s)
	local match={s:match("^([A-Ga-g])([#b]?)(%-?%d)$")}
	if not match[1] then return nil end

	local classes={9,11,0,2,4,5,7}
	local pitch=classes[tonumber(match[1],17)-9]+(tonumber(match[3])+1)*12
	if match[2]=="#" then pitch=pitch+1
	elseif match[2]=="b" then pitch=pitch-1 end

	if pitch<0 or pitch>127 then return nil end
	return pitch
end

local pitch_map={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
---ピッチを音名に変換
---REAPERではC4=60
---@param i integer
---@return string
function m2i.pitch_i2s(i)
	return pitch_map[i%12+1]..(i//12-1)
end

---{"key1,key2,...",val1,val2,...}
---@alias m2i_param_serialized string

---@param s m2i_param_serialized
---@return m2i_param
function m2i.deserialize(s)
	local p=load("return "..s)()
	local p_keys={}
	local i=2
	for s in p[1]:gmatch("[^,]+")do p_keys[s]=i i=i+1 end

	local r={}
	for _=1,#param_keys do local k=param_keys[_]
		if p_keys[k]==nil then
			r[k]=m2i.param_default[k]
		else
			r[k]=p[p_keys[k]]
		end
	end
	return r
end

---@param p m2i_param
---@return m2i_param_serialized
function m2i.serialize(p)
	local t={'"'..table.concat(param_keys,",")..'"'}
	for _=1,#param_keys do local k=param_keys[_]
		t[1+#t]=tostring(p[k])
	end
	return "{"..table.concat(t,",").."}"
end

---@param idx integer
---@return m2i_param?
function m2i.preset_global_load(idx)
	if R.HasExtState("midi2item","preset")then
		local presets=load("return "..R.GetExtState("midi2item","preset"))()
		local p_raw=presets[idx]
		if p_raw then
			return m2i.deserialize(p_raw)
		end
	end
	return nil
end

---@return table<integer,m2i_param_serialized>
local function preset_global_load_all()
	if not R.HasExtState("midi2item","preset")then
		return {}
	end
	return load("return "..R.GetExtState("midi2item","preset"))()
end

---@param presets table<integer,m2i_param_serialized>
local function preset_global_store_all(presets)
	local t={}
	for k,v in pairs(presets)do
		t[1+#t]=string.format("[%d]=%q",k,v)
	end
	local s="{"..table.concat(t,",").."}"
	R.SetExtState("midi2item","preset",s,true)
end

---@param idx integer
---@param p m2i_param
function m2i.preset_global_store(idx,p)
	local presets=preset_global_load_all()
	presets[idx]=m2i.serialize(p)
	preset_global_store_all(presets)
end

---@param idx integer
function m2i.preset_global_delete(idx)
	local presets=preset_global_load_all()
	presets[idx]=nil
	preset_global_store_all(presets)
end

---@param track MediaTrack
---@return m2i_param?
function m2i.preset_local_load(track)
	local retval,p_ser=R.GetSetMediaTrackInfo_String(track,"P_EXT:midi2item_preset","",false)
	if not retval then return nil end
	return m2i.deserialize(p_ser)
end

---@param track MediaTrack
---@param p m2i_param
function m2i.preset_local_store(track,p)
	local p_ser=m2i.serialize(p)
	R.GetSetMediaTrackInfo_String(track,"P_EXT:midi2item_preset",p_ser,true)
end

---@param track MediaTrack
function m2i.preset_local_delete(track)
	R.GetSetMediaTrackInfo_String(track,"P_EXT:midi2item_preset","",true)
end

---@param track MediaTrack
---@return boolean
function m2i.preset_local_has(track)
	local retval=R.GetSetMediaTrackInfo_String(track,"P_EXT:midi2item_preset","",false)
	return retval
end

---@param p1 m2i_param?
---@param p2 m2i_param?
---@return boolean
function m2i.preset_equals(p1,p2)
	if p1==p2 then return true end
	if p1==nil or p2==nil then return false end
	for _=1,#param_keys do local k=param_keys[_]
		if p1[k]~=p2[k]then return false end
	end
	return true
end


---@alias Channel integer

---@class BendQ
---@field qn ProjQN
---@field value number
---@field shape number
---@field beztension number

---@class BendT
---@field time ProjTimePos
---@field value number
---@field shape number
---@field beztension number

---@class Note
---@field st ProjTimePos
---@field ed ProjTimePos
---@field pitch_raw integer
---@field pitch number
---@field chan Channel
---@field bends BendT[]
---@field vel integer

---@class Unit
---@field track_no integer
---@field track MediaTrack
---@field track_name string
---@field items MediaItem[]
---@field takes MediaItem_Take[]

---@class Lane
---@field name string?
---@field [integer] Note

---@class LaneExpanded
---@field name string?
---@field [integer] Note[]

local function add_pitchenv(item)
	local _,xml_str=R.GetItemStateChunk(item,"",false)

	local xml=C.rppxml.new_block(xml_str)
	table.insert(xml,xml:find("SOURCE")+1,C.rppxml.new_block[[
<PITCHENV
ACT 1 -1
VIS 1 1 1
LANEHEIGHT 0 0
ARM 1
DEFSHAPE 0 -1 -1
PT 0 0 0
>]]
	)

	R.SetItemStateChunk(item,xml:tostring(),false)
end

local function ilerp(t,a,b) return (t-a)/(b-a) end

---@param t ProjQN
---@param t0 ProjQN
---@param v0 number
---@param t1 ProjQN
---@param v1 number
---@param s envelope_shape
---@param b number
local function split_envelope(t,t0,v0,t1,v1,s,b)
	--[[
		shape={[0]=
			Linear,
			Square,
			Slow start/end,
			Fast start,
			Fast end,
			Bezier
		}
	]]

	if(s==0)then -- Linear
		return v0+(v1-v0)*ilerp(t,t0,t1),0,0
	elseif(s==1)then -- Square
		return v0,1,0
	else -- TODO: 他の形状の計算
		-- とりあえず線形でごまかす
		return v0+(v1-v0)*ilerp(t,t0,t1),0,0
	end
end

---@param proj ReaProject
---@param item MediaItem
---@return ProjQN
---@return ProjQN
local function get_item_section(proj,item)
	local st_time=R.GetMediaItemInfo_Value(item,"D_POSITION")--[[@as ProjTimePos]]
	local ed_time=st_time+R.GetMediaItemInfo_Value(item,"D_LENGTH")
	local st_qn=R.TimeMap2_timeToQN(proj,st_time)
	local ed_qn=R.TimeMap2_timeToQN(proj,ed_time)
	return st_qn,ed_qn
end

---@param proj ReaProject
---@param take MediaItem_Take
---@return ProjQN
local function get_take_length_qn(proj,take)
	-- MIDIアイテムなら常にQNだとは思う
	local len,isQN=R.GetMediaSourceLength(R.GetMediaItemTake_Source(take))
	return isQN and len or R.TimeMap2_timeToQN(proj,len)
end

---@param track MediaTrack
---@param st number
---@param ed number
---@param refreshUI boolean
local function new_empty_item(track,st,ed,refreshUI)
	local item=R.AddMediaItemToTrack(track)
	R.SetMediaItemPosition(item,st,refreshUI)
	R.SetMediaItemLength(item,ed-st,refreshUI)
	return item
end

---なくてもいいビッチベンドを消す
---(最後-1)番目の移動方法がSquareで最後の時間が終端なら最後の値は問わない
---@param bend BendQ
---@param ed_qn ProjQN
local function check_zero_bend(bend,ed_qn)
	if(#bend==0)then return end

	local zero=true
	if(#bend==1)then
		zero=bend[1].value==0
	else
		for i=1,#bend-1 do
			if(bend[i].value~=0)then
				zero=false
				break
			end
		end
		if(bend[#bend].value~=0)then
			if(bend[#bend-1].shape==0 and bend[#bend].qn~=ed_qn)then
				zero=false
			end
		end
	end

	if zero then C.table.pop_n(bend,#bend)end
end

-- フェーズ0: 対象となるMIDIアイテムを探す
---@param proj ReaProject
---@return Unit[]
local function phase0(proj)
	local units={} ---@type Unit[]

	local selecting_items_n=R.CountSelectedMediaItems(proj)
	if(selecting_items_n>0)then
		for _=0,selecting_items_n-1 do local item=R.GetSelectedMediaItem(proj,_)
			local take=R.GetActiveTake(item)
			if(take==nil)then goto continue end
			if(R.TakeIsMIDI(take))then
				local track=R.GetMediaItem_Track(item)
				local track_no=R.GetMediaTrackInfo_Value(track,"IP_TRACKNUMBER")-1
				local _,track_name=R.GetSetMediaTrackInfo_String(track,"P_NAME","",false)
				local i=C.lower_bound(units,track_no,nil,"track_no")
				if(units[i]==nil or units[i].track_no~=track_no)then
					table.insert(units,i,{track_no=track_no,track=track,track_name=track_name,items={},takes={}})
				end
				units[i].items[1+#units[i].items]=item
				units[i].takes[1+#units[i].takes]=take
			end
			::continue::
		end
	else
		local function insert_from_track(units,track)
			local track_no=R.GetMediaTrackInfo_Value(track,"IP_TRACKNUMBER")-1
			local _,track_name=R.GetSetMediaTrackInfo_String(track,"P_NAME","",false)
			local i=C.lower_bound(units,track_no,nil,"track_no")
			local items={}
			local takes={}
			for _=0,R.CountTrackMediaItems(track)-1 do local item=R.GetTrackMediaItem(track,_)
				local take=R.GetActiveTake(item)
				if(take==nil)then goto continue end
				if(R.TakeIsMIDI(take))then
					items[1+#items]=item
					takes[1+#takes]=take
				end
				::continue::
			end
			table.insert(units,i,{track_no=track_no,track=track,track_name=track_name,items=items,takes=takes})
		end

		local selecting_tracks_n=R.CountSelectedTracks2(proj,false)
		if(selecting_tracks_n>0)then
			for _=0,selecting_tracks_n-1 do local track=R.GetSelectedTrack2(proj,_,false)
				insert_from_track(units,track)
			end
		else
			local track=R.GetLastTouchedTrack()
			if track then insert_from_track(units,track)
			else
				R.ShowMessageBox("対象となるアイテムがありません。\n選択中のトラックやアイテムがMIDIテイクを含むことを確認してください","midi2item",0)
				error()
			end
		end
	end
	return units
end

-- フェーズ1: MIDIアイテムから必要な情報を吸う
---@param proj ReaProject
---@param unit Unit
---@param base_pitch number?
---@param use_take_pitch boolean
---@param base_vel integer
---@param default_pitchbend_range integer
---@param use_pitchbend_change boolean
---@return Note[]
local function phase1(proj,unit,base_pitch,use_take_pitch,base_vel,default_pitchbend_range,use_pitchbend_change)
	---@type Note[]
	local notes={}

	---@param chan integer
	---@param st number
	---@param ed number
	---@param pitch number
	---@param vel integer
	---@param bends BendQ[]
	local function insert_note(chan,st,ed,pitch,vel,bends,take_pitch)
		local st_time=R.TimeMap2_QNToTime(proj,st)

		local tbends={} ---@type BendT[]
		for i=1,#bends do
			tbends[i]={
				time=R.TimeMap2_QNToTime(proj,bends[i].qn)-st_time,
				value=bends[i].value,
				shape=bends[i].shape,
				beztension=bends[i].beztension
			}
		end

		notes[1+#notes]={
			st=st_time,
			ed=R.TimeMap2_QNToTime(proj,ed),
			pitch_raw=pitch,
			pitch=base_pitch and pitch-base_pitch+take_pitch or 0,
			chan=chan,
			bends=tbends,
			vel=vel,
		}
	end

	--for _,item in ipairs(midi.items)do
	for _=1,#unit.items do local item=unit.items[_] local take=unit.takes[_]
		local item_st_qn,item_ed_qn=get_item_section(proj,item)
		local take_rate=R.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")
		local length_qn=get_take_length_qn(proj,take)/take_rate
		local take_pitch=use_take_pitch and R.GetMediaItemTakeInfo_Value(take,"D_PITCH")or 0

		---@types BendQ[][]
		local bendss={}
		for i=1,CHANNEL_MAX do bendss[i]={}end

		local _,nn,cn,_=R.MIDI_CountEvts(take)

		local rpn={} ---@type ({msb:integer,lsb:integer})[]
		for i=1,CHANNEL_MAX do rpn[i]={msb=127,lsb=127}end
		-- PitchBend Sensitivity
		local pbs={} ---@type integer[]
		for i=1,CHANNEL_MAX do pbs[i]=default_pitchbend_range end

		for ci=0,cn-1 do
			local _,_,mutes,ppqpos,hanmsg,chan,msg2,msg3=R.MIDI_GetCC(take,ci)
			chan=chan+1 -- to 1-indexed
			if(mutes)then goto CONTINUE end
			if(hanmsg==224)then -- pitch
				local _,shape,beztension=R.MIDI_GetCCShape(take,ci)
				local function msg2bend(chan,lo,hi)
					local i=(lo|(hi<<7))-8192
					return i/(i<0 and 8192 or 8191)*pbs[chan]
				end
				local bend=msg2bend(chan,msg2,msg3)
				local pos_qn=R.MIDI_GetProjQNFromPPQPos(take,ppqpos)
				local map_shape={[0]=1,0,2,3,4,5} -- MIDI CC shape to REAPER envelope point shape
				bendss[chan][1+#bendss[chan]]={qn=pos_qn,value=bend,shape=map_shape[shape],beztension=beztension}
			elseif(hanmsg==176)then -- CC
				if(msg2==101)then -- RPN MSB
					rpn[chan].msb=msg3
				elseif(msg2==100)then -- RPN LSB
					rpn[chan].lsb=msg3
				elseif(msg2==6)then -- Data Entry MSB
					if(use_pitchbend_change and rpn[chan].msb==0 and rpn[chan].lsb==0)then -- PitchBend Sensitivity
						pbs[chan]=msg3
					end
				end
			end
		::CONTINUE:: end

		for ni=0,nn-1 do local _,_,mutes,st_ppq,ed_ppq,chan,pitch,vel=R.MIDI_GetNote(take,ni)
			if(mutes)then goto CONTINUE end
			chan=chan+1 -- to 1-indexed
			vel=base_vel and vel/base_vel or 1

			local st_qn=R.MIDI_GetProjQNFromPPQPos(take,st_ppq)
			local ed_qn=R.MIDI_GetProjQNFromPPQPos(take,ed_ppq)

			local bends=bendss[chan]
			local bbi=C.upper_bound(bends,st_qn,nil,"qn")
			local bei=C.lower_bound(bends,ed_qn,nil,"qn")

			---このノーツに関わるピッチベンド情報
			---@type BendQ[]
			local nbend={}

			if(bei~=1)then
				local exb
				if(bbi==1)then
					nbend[1+#nbend]={qn=st_qn,value=0,shape=1,beztension=0}
					exb=1
				elseif(bends[bbi-1].qn<=st_qn)then
					exb=bbi-1
				else
					local sv,ss,sb=split_envelope(
						st_qn,
						bends[bbi-1].qn,bends[bbi-1].value,
						bends[bbi  ].qn,bends[bbi  ].value,
						bends[bbi-1].shape,bends[bbi-1].beztension)

					nbend[1+#nbend]={qn=st_qn,value=sv,shape=ss,beztension=sb}

					exb=bbi
				end

				local last_b=nil
				local exe
				if(bei==#bends+1)then
					exe=#bends
				elseif(bends[bei].qn==ed_qn)then
					exe=bei
				else
					local sv,_,sb=split_envelope(
						ed_qn,
						bends[bei-1].qn,bends[bei-1].value,
						bends[bei  ].qn,bends[bei  ].value,
						bends[bei-1].shape,bends[bei-1].beztension)

					exe=bbi-1
					last_b={qn=ed_qn,value=sv,shape=0,beztension=sb}
				end

				for i=exb,exe do
					nbend[1+#nbend]=C.table.copy(bends[i])
				end
				if(last_b)then nbend[1+#nbend]=last_b end
			end

			check_zero_bend(nbend,ed_qn)

			-- MIDIアイテムのループを展開
			local l_st_qn,l_ed_qn=st_qn,ed_qn
			local l_nbend=C.table.deep_copy(nbend)
			---@type fun()
			local advance do
				local loop_i=0
				function advance()
					loop_i=loop_i+1

					l_nbend={}
					for i=1,#nbend do local nb=nbend[i]
						l_nbend[1+#l_nbend]={
							qn=nb.qn+length_qn*loop_i,
							value=nb.value,
							shape=nb.shape,
							beztension=nb.beztension
						}
					end

					l_st_qn=st_qn+length_qn*loop_i
					l_ed_qn=ed_qn+length_qn*loop_i
				end
			end

			if(ed_qn<=item_st_qn)then
				advance()
			elseif(st_qn<=item_st_qn)then
				if(ed_qn-item_st_qn<1e-5)then -- 短すぎる
					advance()
				else
					-- 先頭が半端

					-- 最初に関係あるポイントの次
					local u=C.upper_bound(l_nbend,item_st_qn,nil,"qn")
					if(u~=1)then
						-- 先頭 u-2 個を削除
						table.move(l_nbend,u-1,#l_nbend,1)
						C.table.pop_n(l_nbend,u-2)

						if(#l_nbend==1)then
							l_nbend[1].qn=item_st_qn
						else
							if(l_nbend[1].qn~=item_st_qn)then
								local sv,ss,sb=split_envelope(
									item_st_qn,
									l_nbend[1].qn,l_nbend[1].value,
									l_nbend[2].qn,l_nbend[2].value,
									l_nbend[1].shape,l_nbend[1].beztension)

								l_nbend[1]={qn=item_st_qn,value=sv,shape=ss,beztension=sb}
							end
						end

						check_zero_bend(l_nbend,l_ed_qn)
					end

					l_st_qn=item_st_qn
				end
			end

			while true do
				if(item_ed_qn<=l_st_qn)then break end

				if(item_ed_qn<l_ed_qn)then
					-- 末尾が半端

					if(item_ed_qn-l_st_qn<1e-5)then break end -- 短すぎるものは捨てる

					local l=C.lower_bound(l_nbend,item_ed_qn,nil,"qn")
					if(l~=1 and l<=#l_nbend)then
						C.table.pop_n(l_nbend,-l)
						if(l_nbend[l].qn~=item_ed_qn)then
							local sv,ss,sb=split_envelope(
								item_ed_qn,
								l_nbend[#l_nbend-1].qn,l_nbend[#l_nbend-1].value,
								l_nbend[#l_nbend  ].qn,l_nbend[#l_nbend  ].value,
								l_nbend[#l_nbend-1].shape,l_nbend[#l_nbend-1].beztension)

							l_nbend[#l_nbend]={qn=item_ed_qn,value=sv,shape=ss,beztension=sb}
						end
					end

					check_zero_bend(l_nbend,item_ed_qn)

					insert_note(chan,l_st_qn,item_ed_qn,pitch,vel,l_nbend,take_pitch)
					break
				end

				insert_note(chan,l_st_qn,l_ed_qn,pitch,vel,l_nbend,take_pitch)

				advance()
			end
		::CONTINUE:: end
	end

	return notes
end

--- フェーズ2: 区別したいものを分けておく
---@param proj ReaProject
---@param unit Unit
---@param notes Note[]
---@param channel_aware boolean
---@param pitch_aware boolean
---@return Lane[]
local function phase2(proj,unit,notes,channel_aware,pitch_aware)
	local lanes={} ---@type Lane[]

	if pitch_aware then
		if channel_aware then
			local lanes_t={}

			for _=1,#notes do local note=notes[_]
				local id=note.pitch_raw+(note.chan-1)*128+1
				local t=lanes_t[id]
				if(t==nil)then t={}lanes_t[id]=t end
				t[1+#t]=note
			end

			local lanes_t_keys={}
			for k in pairs(lanes_t)do lanes_t_keys[1+#lanes_t_keys]=k end
			table.sort(lanes_t_keys)

			for _=1,#lanes_t_keys do local lane=lanes_t[lanes_t_keys[_]]
				lanes[1+#lanes]=lane
				local name=R.GetTrackMIDINoteNameEx(proj,unit.track,lane[1].pitch_raw,lane[1].chan-1)
				if name==nil then name=("%s:%s"):format(lane[1].chan,m2i.pitch_i2s(lane[1].pitch_raw))end
				lane.name=name
			end
		else
			local lanes_t={}

			for _=1,#notes do local note=notes[_]
				local id=note.pitch_raw+1
				local t=lanes_t[id]
				if(t==nil)then t={}lanes_t[id]=t end
				t[1+#t]=note
			end

			local lanes_t_keys={}
			for k in pairs(lanes_t)do lanes_t_keys[1+#lanes_t_keys]=k end
			table.sort(lanes_t_keys)

			for _=1,#lanes_t_keys do local lane=lanes_t[lanes_t_keys[_]]
				lanes[1+#lanes]=lane
				local name=R.GetTrackMIDINoteNameEx(proj,unit.track,lane[1].pitch_raw,-1)
				if name==nil then name=m2i.pitch_i2s(lane[1].pitch_raw)end
				lane.name=name
			end
		end
	else
		if channel_aware then
			local lanes_t={}
			for _=1,CHANNEL_MAX do lanes_t[_]={}end

			for _=1,#notes do local note=notes[_]
				local t=lanes_t[note.chan]
				t[1+#t]=note
			end

			for _=1,CHANNEL_MAX do local lane=lanes_t[_]
				if #lane~=0 then
					lanes[1+#lanes]=lane
					lane.name=("ch%d"):format(lane[1].chan)
				end
			end
		else
			lanes[1]=notes
		end
	end

	return lanes
end

--- フェーズ3: 重複部分を開く
---@param lanes Lane[]
---@return LaneExpanded[]
local function phase3(lanes)
	local rows={} ---@type LaneExpanded[]

	for _=1,#lanes do local lane=lanes[_]
		table.sort(lane,function(a,b)
			if(a.st~=b.st)then return a.st<b.st end
			if(a.ed~=b.ed)then return a.ed<b.ed end
			return a.pitch_raw<b.pitch_raw
		end)

		local row={name=lane.name} ---@type LaneExpanded
		for _=1,#lane do local note=lane[_]
			local k=1
			while true do
				if(row[k]==nil)then row[k]={} break end
				if(row[k][#row[k]].ed<=note.st)then break end
				k=k+1
			end
			row[k][1+#row[k]]=note
		end

		rows[1+#rows]=row
	end

	return rows
end

-- フェーズ4: アイテムとして配置する
---@param proj ReaProject
---@param unit Unit
---@param rows LaneExpanded[]
---@param make_new_root boolean
---@param name_track boolean
local function phase4(proj,unit,rows,make_new_root,name_track)
	local track_no_base=unit.track_no

	local root=R.GetTrack(proj,track_no_base)
	local root_depth=R.GetMediaTrackInfo_Value(root,"I_FOLDERDEPTH")

	if make_new_root then
		track_no_base=track_no_base+1
		R.InsertTrackAtIndex(track_no_base,true)
		local new_root=R.GetTrack(proj,track_no_base)
		R.SetMediaTrackInfo_Value(root,"I_FOLDERDEPTH",1)
		R.SetMediaTrackInfo_Value(new_root,"I_FOLDERDEPTH",root_depth-1)
		root=new_root
		root_depth=root_depth-1
		if name_track then
			R.GetSetMediaTrackInfo_String(new_root,"P_NAME",unit.track_name,true)
		end
	end

	local track_no_i=track_no_base+1

	for _=1,#rows do local row=rows[_]
		for _=#row,1,-1 do local notes=row[_]
			R.InsertTrackAtIndex(track_no_i,true)
			local track=R.GetTrack(proj,track_no_i)
			if name_track and row.name then
				R.GetSetMediaTrackInfo_String(track,"P_NAME",row.name,true)
			end

			for _=1,#notes do local note=notes[_]
				local item=new_empty_item(track,note.st,note.ed,false)
				local take=R.AddTakeToMediaItem(item)
				R.SetMediaItemTakeInfo_Value(take,"D_PITCH",note.pitch)
				R.SetMediaItemInfo_Value(item,"D_VOL",note.vel)

				if(note.bends~=nil and #note.bends>0)then
					local bends=note.bends
					local pcm=R.PCM_Source_CreateFromType("WAVE")
					R.SetMediaItemTake_Source(take,pcm)
					add_pitchenv(item)
					local tenv=R.GetTakeEnvelopeByName(take,"Pitch")

					local b=bends[1]
					local _<close> =C.defer(function()R.Envelope_SortPoints(tenv)end)
					R.SetEnvelopePointEx(tenv,-1,0,b.time,b.value,b.shape,b.beztension,false,true)
					for i=2,#bends do
						local b=bends[i]
						R.InsertEnvelopePointEx(tenv,-1,b.time,b.value,b.shape,b.beztension,false,true)
					end
				end
			end
			track_no_i=track_no_i+1
		end
	end

	local track_count=track_no_i-track_no_base-1
	if track_count>0 then
		R.SetMediaTrackInfo_Value(root,"I_FOLDERDEPTH",1)
		R.SetMediaTrackInfo_Value(R.GetTrack(proj,track_no_i-1),"I_FOLDERDEPTH",root_depth-1)
	end
end

m2i.prepare=phase0

---@param proj ReaProject
---@param undo table
---@param units Unit[]
---@param param m2i_param?
function m2i.main(proj,undo,units,param)
	local _<close> =C.prevent_ui_refresh_scope()
	local _<close> =undo()

	for _=#units,1,-1 do local unit=units[_]
		local p=param or m2i.preset_local_load(unit.track) or m2i.param_default
		local notes=phase1(proj,unit,p.base_pitch,p.use_take_pitch,p.base_vel,p.default_pitchbend_range,p.use_pitchbend_change)
		local lanes=phase2(proj,unit,notes,p.channel_aware,not p.base_pitch)
		local rows=phase3(lanes)
		phase4(proj,unit,rows,p.make_new_root,p.name_track)
	end
end

return m2i
