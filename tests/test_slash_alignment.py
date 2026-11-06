from pathlib import Path
from lupa.lua53 import LuaRuntime
s=Path('scripts/modules/ms-armory_9.lua').read_text()
l=LuaRuntime(unpack_returned_tuples=True)
l.execute(s[s.index('local function slashPose'):s.index('local function renderV2')]+'\nPose=slashPose')
l.execute('''
for _,rad in ipairs({1.95,5})do
 for heading=0,315,45 do
  local fx,fz=math.sin(math.rad(heading)),math.cos(math.rad(heading))
  for _,textureForward in ipairs({-90,90})do
   for i=0,20 do
    local q=i/20
    local x,z,size,yaw=Pose({kind="hero-melee",x=10,z=20,tx=10+fx*rad,tz=20+fz*rad,radius=rad},q,1,-textureForward)
    local litAngle=math.rad(yaw+textureForward)
    assert(math.sin(litAngle)*fx+math.cos(litAngle)*fz>.64,'bright edge behind hero')
    assert(x*fx+z*fz>0,'origin behind hero')
    assert(math.abs(math.sqrt(x*x+z*z)+size*.5-rad)<1e-5,'visual radius changed')
   end
  end
 end
end
local x,z,size=Pose({kind="hero-spin",x=0,z=0,tx=0,tz=1,radius=2.2},.5,1,90)
assert(x==0 and z==0 and size==4.4)
''')
print('PASS 672 slash poses: mirrored UVs, 8 directions, ordinary/giant ranges; blade stays forward; spin radius unchanged')
