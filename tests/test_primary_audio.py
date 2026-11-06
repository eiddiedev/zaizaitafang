from pathlib import Path
from lupa.lua53 import LuaRuntime
p=Path('scripts/modules/ms-armory_9.lua');s=p.read_text();lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('played=nil;function play(name)played=name end;function playHeroHurt()played="hurt"end;function audible()return true end;FAMILIES={"crossbow","prism","mortar","slow","barrier","economy"}')
lua.execute(s[s.index('local function effectSound'):s.index('local function addEffect')]+'\nSound=effectSound;Window=attackWindow')
lua.execute('''
for _,family in ipairs(FAMILIES)do played=nil;Sound({kind="shot",family=family},1);assert(played=="shoot-"..family)end
for _,kind in ipairs({"hero-melee","hero-spin","giant-awaken"})do Sound({kind=kind},1);assert(played=="hit-physical")end
for _,kind in ipairs({"hero-ranged","hero-pierce","global-arrow-rain"})do Sound({kind=kind},1);assert(played=="shoot-crossbow")end
for _,kind in ipairs({"hero-magic","mage-burst"})do Sound({kind=kind},1);assert(played=="shoot-prism")end
for _,kind in ipairs({"shot","hero-magic","hero-ranged","hero-melee","hit"})do
 for _,latency in ipairs({0,.05,.16,.29,.45,.64})do
  local ev={kind=kind,t0=10,duration=.12,hitAt=10.12};local start,duration=Window(ev,10+latency)
  assert(start<=10+latency);assert(start+duration-(10+latency)>=.0999)
  assert(ev.hitAt==10.12 and ev.t0==10 and ev.duration==.12)
 end
 local start,duration=Window({kind=kind,t0=10,duration=.12},11);assert(start+duration<11)
end
local start,duration=Window({kind="hero-pierce",t0=10,duration=.12},10.1);assert(start==10 and duration==.3)
local start,duration=Window({kind="meteor-fall",t0=10,duration=.6},10.4);assert(start==10 and duration==.6)
''')
assert 'v2-' not in s[s.index('local function effectSound'):s.index('local function attackWindow')]
print('PASS original tower/hero audio routing; 30 delayed primary cues stay visible; damage clocks/skills unchanged; old volleys not replayed')
