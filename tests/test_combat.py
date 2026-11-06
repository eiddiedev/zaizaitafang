from pathlib import Path
from lupa.lua53 import LuaRuntime
D=Path('scripts/modules')
lua=LuaRuntime(unpack_returned_tuples=True)
load=lua.eval('function(s) local e=setmetatable({},{__index=_G});assert(load(s,"test","t",e))();return e end')
M={n:load((D/f'{n}_9.lua').read_text()) for n in ['config','layout','simulation','codec']}
C,L,S=M['config'].GetConfig(),M['layout'],M['simulation'];S.Configure(C,L)
def tab(**kw):return lua.table_from(kw)
def setup(hero):
 s=S.NewState(42);p=S.AddPlayer(s,'p','test',True)
 assert S.Action(s,'p',tab(kind='loadout',value=hero)) is True
 assert S.Action(s,'p',tab(kind='start')) is True
 assert S.Action(s,'p',tab(kind='beginChallenge')) is True
 assert S.Action(s,'p',tab(kind='ready')) is True
 s["t"]=s["deadline"];S.Step(s,.05);s['spawnQueue']=lua.table();p['x']=0;p['z']=0;p['fx']=0;p['fz']=1
 return s,p
def enemy(s,x,z,kind='basic'):
 e=S.Debug(s,'spawn',tab(type=kind,route=1,d=25));e['x']=x;e['z']=z;e['cd']=999;e['rootUntil']=999
 return e
def step(s,t):
 while t>1e-8:
  dt=min(t,.025);S.Step(s,dt);t-=dt
for hero in ['melee','ranged','mage']:
 s,p=setup(hero);assert p['loadout']==hero and p['hp']==C['hero'][hero]['hp']
 e=enemy(s,0,1.2 if hero=='melee' else 4)
 assert S.Action(s,'p',tab(kind='attack')) is True
 assert p['actionKind']=='attack' and p['actionSeq']==1
 step(s,.1);assert e['hp']==e['maxHp'],hero+' hits before windup'
 step(s,.5);assert e['hp']<e['maxHp'],hero+' missed'
 snapshot=M['codec'].Decode(M['codec'].Encode(s));assert snapshot['players']['p']['loadout']==hero
s,p=setup('mage');e=enemy(s,0,4,'armored')
assert S.Action(s,'p',tab(kind='attack')) is True
step(s,.55);assert abs(e['maxHp']-e['hp']-34)<1e-5,'mage must ignore physical armor'
s,p=setup('mage');e=enemy(s,0,4,'resistant')
assert S.Action(s,'p',tab(kind='attack')) is True
step(s,.55);assert abs(e['maxHp']-e['hp']-34*.55)<1e-5,'magic resistance must apply'
s,p=setup('mage');a=enemy(s,0,4);b=enemy(s,1,4);c=enemy(s,5,4)
assert S.Action(s,'p',tab(kind='skill2')) is True
step(s,.45);assert a['hp']==a['maxHp']
step(s,.1);assert a['hp']==a['maxHp']-90 and b['hp']==b['maxHp']-90 and c['hp']==c['maxHp']
assert S.Action(s,'p',tab(kind='skill2'))[0] is False,'cooldown'
s,p=setup('mage');e=enemy(s,0,4);S.Action(s,'p',tab(kind='skill2'));p['hp']=0
step(s,.6);assert e['hp']==e['maxHp'],'death cancels cast'
s,p=setup('melee');e=enemy(s,3,0);S.Action(s,'p',tab(kind='attack'))
assert p['motion']['kind']=='attackApproach' and p['actionAt']>=p['motion']['ends']
step(s,.4);assert e['hp']==e['maxHp']-28
s,p=setup('mage');s['phase']='INTERMISSION';p['hp']=p['maxHp']/2
assert S.Action(s,'p',tab(kind='loadout',value='melee')) is True
assert p['hp']==p['maxHp']/2 and p['actionKind'] is None
parse=lua.eval('function(s) local f,e=load(s);assert(f,e) end')
for p in (D/'prepared').glob('*.lua'):parse(p.read_text())
print('PASS: 3 classes, windup, action sequence, snapshot roundtrip, mage armor/resistance, AoE radius, cooldown, cast overlap, death cancellation, melee approach, class swap health, Lua syntax')
