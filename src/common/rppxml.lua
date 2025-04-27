-- @noindex
---@meta
local c_rppxml={}
(...).rppxml=c_rppxml

local rppxml_method={}
local mt_rppxml={__index=rppxml_method}

---@param s string
---@async
local gnewline=function(s)return coroutine.wrap(function()
	-- 0x0a \n
	-- 0x0d \r
	local bi=0
	local bbs=0x0a
	for ss,i,l in s:gmatch"(.-)()([\r\n])"do
		local bs=l:byte()
		if not(bi+1==i and bbs==0x0d and bs==0x0a)then
            coroutine.yield(ss)
        end
		bi,bbs=i,bs
	end
    coroutine.yield(s:sub(bi+1))
end)end

----@enum line_type
local line_type={
	invalid=-1,
	field=0,
	block_begin=1,
	block_end=2,
	multiline_string=3
}
c_rppxml.line_type=line_type

function c_rppxml.parse_line(s)
	--[[
		space = 0x20
		quote = 0x22
		curly_bracket_L = 0x7b
		curly_bracket_R = 0x7d
		lt = 0x3c
		gt = 0x3e
		bar = 0x7c
	]]
	local CO=coroutine

	local co=CO.wrap(function(c)
		local t={type="field"}

		local block_begin=false

		while c==0x20 do c=CO.yield()end

		if(c==0x3c)then -- lt
			block_begin=true
			c=CO.yield()
		elseif(c==0x3e)then -- gt
			while c~=nil do c=CO.yield()end
			return line_type.block_end
		elseif(c==0x7c)then -- bar
			local t={}
			repeat
				c=CO.yield()
				t[1+#t]=c
			until c==nil
			return line_type.multiline_string,string.char(table.unpack(t))
		end

		-- key
		local key={}
		repeat
			key[1+#key]=c
			c=CO.yield()
		until c==0x20 or c==nil
		t[0]=string.char(table.unpack(key))

		if(c==nil)then
			return (block_begin and line_type.block_begin or line_type.field),t
		end

		repeat c=CO.yield()until c~=0x20 and c~=nil

		local i=1
		while(c~=nil)do
			if(c==0x22)then -- quote: string
				local v={type="string"}
				local vv={}
				c=CO.yield()
				while c~=0x22 do
					vv[1+#vv]=c
					c=CO.yield()
					if(c==nil)then error([['"' expected to close string '"' near newline]])end
				end
				v.value=string.char(table.unpack(vv))
				t[i]=v
				i=i+1
				c=CO.yield()
			elseif(c==0x7b)then -- curly_bracket_L: guid
				local v={type="guid"}
				local vv={c}
				repeat
					c=CO.yield()
					vv[1+#vv]=c
					if(c==nil)then error("'}' expected to close guid '{' near newline")end
				until c==0x7d -- curly_brecket_R
				v.value=string.char(table.unpack(vv))
				t[i]=v
				i=i+1
				c=CO.yield()
			elseif(c==0x20)then
				repeat c=CO.yield()until c~=0x20 and c~=nil
			else
				local vv_str={}
				repeat
					vv_str[1+#vv_str]=c
					c=CO.yield()
				until c==0x20 or c==nil -- space

				---@type number|string
				local vv=string.char(table.unpack(vv_str))
				local v={}
				local vv_n=tonumber(vv)
				if(vv_n==nil)then
					v.value=vv
					v.type="enum"
				else
					v.value=vv_n
					v.type="number"
				end
				v.value=vv
				t[i]=v
				i=i+1
			end
		end
		return (block_begin and line_type.block_begin or line_type.field),t
	end)

	for i=1,#s do
		co(s:byte(i))
	end
	return co(nil)
end
local parse_line=c_rppxml.parse_line

---@param s string
---@return RPPXML_Field
function c_rppxml.parse_field(s)
	local lt,r=parse_line(s)
	if lt~=line_type.field then error("") end
	return r
end
local parse_field=c_rppxml.parse_field

---@param str string
---@return RPPXML_Block
function c_rppxml.parse_block(str)
	local CO=coroutine

	local co=CO.wrap(function(line)
		local lt,r=parse_line(line)
		if lt~=line_type.block_begin then error("invalid rppxml")end

		local ret=c_rppxml.new_block{[0]=r}

		local stack={ret}
		-- #stack
		local level=1

		line=CO.yield()
		while line~=nil do
			lt,r=parse_line(line)
			if(lt==line_type.block_end)then
				stack[level]=nil level=level-1
			elseif(lt==line_type.block_begin)then
				local tt=c_rppxml.new_block{[0]=r}
				stack[level][1+#stack[level]]=tt
				stack[level+1]=tt level=level+1
			elseif(lt==line_type.multiline_string)then
				local t=stack[level]
				if(t.multiline==nil)then
					t.multiline=r
				else
					t.multiline=t.multiline.."\n"..r
				end
			elseif(lt==line_type.field)then
				stack[level][1+#stack[level]]=r
			end
			line=CO.yield()
		end
		if(level~=0)then error("invalid rppxml block")end
		return ret
	end)

	for line in gnewline(str)do
		if line~=""then co(line)end
	end
	return setmetatable(co(nil),mt_rppxml)
end

---@param a table|string
---@return RPPXML_Block
---@nodiscard
function c_rppxml.new_block(a)
	local type_a=type(a)
	if(type_a=="table")then
		local t=setmetatable(a,mt_rppxml)
		t.type="rppxml"
		return t
	elseif(type_a=="string")then
		return c_rppxml.parse_block(a)
	else
		error(("bad argument to 'rppxml.new_block' (table or string expected, got %s)"):format(type_a))
	end
end

function c_rppxml.new_field(a)
	local type_a=type(a)
	if(type_a=="table")then
		return a
	elseif(type_a=="string")then
		return parse_field(a)
	else
		error(("bad argument to 'rppxml.new_field' (table or string expected, got %s)"):format(type_a))
	end
end

---@return string
---@nodiscard
function rppxml_method:tostring()
	local function field_tostr(t)
		local s=t[0]
		for i=1,#t do
			s=s.." "
			if(t[i].type=="number")then
				s=s..t[i].value
			elseif(t[i].type=="string")then
				s=s..'"'..t[i].value..'"'
			elseif(t[i].type=="enum")then
				s=s..t[i].value
			elseif(t[i].type=="guid")then
				s=s..t[i].value
			end
		end
		return s
	end

	local function f(t,level)
		level=level or 0
		local s=("  "):rep(level).."<"..field_tostr(t[0]).."\n"
		level=level+1
		local space=("  "):rep(level)
		if(t.multiline)then
			for l in gnewline(t.multiline)do
				s=s..space.."|"..l.."\n"
			end
		end
		for i=1,#t do
			if(t[i].type=="rppxml")then
				s=s..f(t[i],level).."\n"
			elseif(t[i].type=="field")then
				s=s..space..field_tostr(t[i]).."\n"
			end
		end
		s=s..("  "):rep(level-1)..">"
		return s
	end

	return f(self)
end

---@param key string
---@param index integer?
---@return integer?
---@nodiscard
function rppxml_method:find(key,index)
	for i=index or 1,#self do local v=self[i]
		if(v.type=="field")then
			if(v[0]==key)then
				return i
			end
		elseif(v.type=="rppxml")then
			if(v[0][0]==key)then
				return i
			end
		end
	end
	return nil
end
