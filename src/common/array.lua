-- @noindex
---@meta
local c_array={}
(...).array=c_array

function c_array.new(t)
    local ret
    if(t)then
        ret={[0]=#t}
        table.move(t,1,#t,1,ret)
    else
        ret={[0]=0}
    end
    return setmetatable(ret,{
        __index=c_array,
        __len=function(o)
            return o[0]
        end
    })
end

function c_array:set_len(x)
    getmetatable(self).len=x
end

--function c_array:
