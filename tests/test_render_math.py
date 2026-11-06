from pathlib import Path
from lupa.lua53 import LuaRuntime
p=Path('scripts/modules/ms-armory_9.lua')
s=p.read_text();chunk=s[s.index('local function slashTextureYaw'):s.index('local function updateEffects')]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
function vector(x,y,z)return{x=x or 0,y=y or 0,z=z or 0}end
function clamp(x,a,b)return math.max(a,math.min(b,x))end
function ground(x,z)return math.sin(x*.03)*.1 end
function visibleAt()return true end
function alive(x)return x~=nil end
U={Quaternion={identity={},Euler=function()return{}end,LookRotation=function()return{}end},Camera={},Color=function(r,g,b,a)return{r=r,g=g,b=b,a=a}end}
V={weapons={},slashTextureYaw=-90}
function piece()return{gameObject={SetActive=function(self,v)self.active=v end}}end
''')
lua.execute(chunk+'\nRunV2=renderV2')
helpers=s[s.index('local V2_LAYOUTS='):s.index('local function discoverV2')]
lua.execute(helpers+'\nLayouts=V2_LAYOUTS')
run=lua.eval('''function()
 local total=0
 for name,parts in pairs(Layouts)do
  local f={v2=true,name=name,e={},started=0,duration=.6,sx=0,sy=2,sz=0,go={transform={}},pieces={},partNames=parts,partMats={}}
  for j in ipairs(parts)do f.pieces[j]=piece()end
  local s={enemies={},players={},layout={bounds={minX=-32,maxX=32,minZ=-32,maxZ=32}}}
  local e={x=0,z=0,tx=4,tz=5,id=7,radius=2,kind="shot"}
  for i=0,100 do
   assert(RunV2(f,e,s,i*.006,i/100))
   for _,p in ipairs(f.pieces)do
    for _,v in pairs(p.localPosition or {})do assert(v==v and math.abs(v)<1000,name)end
    for _,v in pairs(p.localScale or {})do assert(v==v and v>0 and v<1000,name)end
   end
   total=total+1
  end
 end
 return total
end''')
print('PASS finite bounded VFX transforms:',run(),'frames')
