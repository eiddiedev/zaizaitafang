---@id cdf08d89-759a-40be-93a8-12ebaa61737d
---@referenceName helpers_codec.lua
---@assetRef eyJhc3NldElkIjoibWl4LWNyeXN0YWwtZGVmZW5zZTpoYW1sZXQtdWdjL2FpZ2NfZWRpdG9yL2Rldi91bml0eS9NUzR3TGpBQkFBQUFpWGVTbVJUZzVIekJKb1pRTkE0OEh1eXBoeWkxME4zNmk4QjJpenpZSjNZL21peC1wYXJ0LTBfX3VwbG9hZF9qeTQyZGQzeC5nbGIiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvbWl4LXBhcnQtMF9fdXBsb2FkX2p5NDJkZDN4LmdsYiIsInJlZmVyZW5jZU5hbWUiOiJoZWxwZXJzX2NvZGVjLmx1YSJ9
-- 有界的纯数据网络编码；不会执行接收到的文本。
---@displayName 网络快照编码
local MAX=250000
local function encode(v,out,depth)
 if depth>20 then error("snapshot too deep")end
 local t=type(v)
 if t=="nil" then out[#out+1]="z"
 elseif t=="boolean" then out[#out+1]=v and "b1" or "b0"
 elseif t=="number" then if v~=v or math.abs(v)==math.huge then error("nonfinite")end;out[#out+1]="d"..string.format("%.5f",v)..";"
 elseif t=="string" then out[#out+1]="s"..#v..":"..v
 elseif t=="table" then
  local keys={};for k in pairs(v)do if type(k)~="string" and type(k)~="number" then error("key")end;keys[#keys+1]=k end
  table.sort(keys,function(a,b)return type(a)==type(b) and a<b or type(a)<type(b)end)
  out[#out+1]="t"..#keys..":";for _,k in ipairs(keys)do encode(k,out,depth+1);encode(v[k],out,depth+1)end
 else error("unsupported")end
end
function Encode(v)local out={};encode(v,out,0);local s=table.concat(out);if #s>MAX then error("snapshot too large")end;return s end
function Decode(s)
 if type(s)~="string" or #s>MAX then return nil,"size" end
 local pos,nodes=1,0
 local function untilChar(c)local e=string.find(s,c,pos,true);if not e then error("truncated")end;local x=string.sub(s,pos,e-1);pos=e+1;return x end
 local function parse(depth)
  nodes=nodes+1;if depth>20 or nodes>30000 then error("limits")end
  local tag=string.sub(s,pos,pos);pos=pos+1
  if tag=="z" then return nil
  elseif tag=="b" then local x=string.sub(s,pos,pos);pos=pos+1;if x~="0" and x~="1"then error("bool")end;return x=="1"
  elseif tag=="d"then local n=tonumber(untilChar(";"));if not n or n~=n or math.abs(n)==math.huge then error("number")end;return n
  elseif tag=="s"then local n=tonumber(untilChar(":"));if not n or n<0 or n%1~=0 or pos+n-1>#s then error("string")end;local v=string.sub(s,pos,pos+n-1);pos=pos+n;return v
  elseif tag=="t"then local n=tonumber(untilChar(":"));if not n or n<0 or n>10000 or n%1~=0 then error("table")end;local v={};for i=1,n do local k=parse(depth+1);if type(k)~="number" and type(k)~="string"then error("key")end;v[k]=parse(depth+1)end;return v
  end;error("tag")
 end
 local ok,v=pcall(parse,0);if not ok or pos~=#s+1 then return nil,"invalid"end;return v
end
function Hash(s)local h=17;for i=1,#s do h=(h*31+string.byte(s,i))%2147483647 end;return h end