-- @noindex
---@meta
local c_table={}
(...).table=c_table

---@param t table
---@return table
function c_table.copy(t)
  local ret={}
  for k,v in pairs(t)do
    ret[k]=v
  end
  setmetatable(ret,getmetatable(t))
  return ret
end

---@param t table
---@return table
function c_table.deep_copy(t)
  local ret={}
  for k,v in pairs(t)do
    if(type(v)=="table")then
      ret[k]=c_table.deep_copy(v)
    else
      ret[k]=v
    end
  end
  setmetatable(ret,getmetatable(t))
  return ret
end

---@param t table
---@param n integer
---@return table
function c_table.pop_n(t,n)
  -- 末尾-n+1から末尾方向にnilを代入するより末尾から逆順に削除した方が良い
  if(n<0)then
    n=#t+n
  end
  for i=#t,#t-n+1,-1 do
    t[i]=nil
  end
  return t
end

---@param t table
---@param comp fun(a:any, b:any):boolean
---@param proj fun(x:any):any
---@return table
function c_table.stable_sort(t,comp,proj)
    local tmp={}

    local function merge(L,m,R)
        table.move(t,L,m-1,1,tmp)
        for i=1,R-m+1 do
            tmp[m-L+i]=t[R-i+1]
        end

        local a,b,i=1,R-L+1,0
        while(a<=b)do
            if not comp(proj(tmp[b]),proj(tmp[a]))then
                t[L+i]=tmp[a]
                a=a+1
            else
                t[L+i]=tmp[b]
                b=b-1
            end
            i=i+1
        end
    end

    local function f(i,j)
        if(i>=j)then return end
        local m=i+(j-i+1)//2
        f(i,m-1)
        f(m,j)
        merge(i,m,j)
    end

    f(1,#t)
    return t
end
