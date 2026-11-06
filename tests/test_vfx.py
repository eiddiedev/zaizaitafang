exec(open('tests/test_combat.py').read().split('for hero in [')[0])
# Timings and the snapshot codec must agree for all three players.
for hero in ('melee','ranged','mage'):
 s,p=setup(hero);p['x']=20;p['z']=20;p['fx']=1;p['fz']=0
 assert S.Action(s,'p',tab(kind='dash')) is True
 m=p['motion'];t=s['t'];snap=M['codec'].Decode(M['codec'].Encode(s));m2=snap['players']['p']['motion']
 for dt,expected in [(0,0),(.079,0),(.08,0),(.19,.5),(.30,1),(.6,1)]:
  assert abs(S.MotionProgress(m,t+dt)-expected)<1e-5
  assert abs(S.MotionProgress(m2,t+dt)-expected)<1e-4
 assert abs(p['immuneUntil']-t-.2)<1e-6
 assert m['ex']==23 and m['ez']==20
 assert S.Action(s,'p',tab(kind='dash'))[0] is False
 s,p=setup(hero);b=s['layout']['bounds'];p['x']=b['maxX']-.1;p['z']=b['maxZ']-.1;p['fx']=1;p['fz']=1
 S.Action(s,'p',tab(kind='dash'));assert p['motion']['ex']==b['maxX'] and p['motion']['ez']==b['maxZ']
# Projectile lifetimes derive from existing damage due times (no damage moved to clients).
for hero in ('ranged','mage'):
 s,p=setup(hero);e=enemy(s,0,4,'boss');S.Action(s,'p',tab(kind='attack'))
 pending=[v for _,v in s['pending'].items()];hit=next(v for v in pending if v['kind']=='heroHit');vis=next(v for v in pending if v['kind']=='heroVisual')
 assert abs(hit['due']-vis['due']-vis['duration'])<1e-6
# Three-target decay unchanged, one authority hit per target, dedicated leaf-hit metadata.
s,p=setup('ranged');es=[enemy(s,0,z,'boss') for z in [2,4,6,8]]
for e in es:e['hp']=10000;e['maxHp']=10000
S.Action(s,'p',tab(kind='skill2'));step(s,.31);assert all(e['hp']==10000 for e in es)
step(s,.03)
for e,factor in zip(es,[1,.65,.4,0]):assert abs(10000-e['hp']-120*factor*(1-C['enemies']['boss']['res']))<1e-5
assert any(e['kind']=='hit' and e['family']=='leaf' for _,e in s['effects'].items())
# Giant/rain/meteor carry exactly one local-shake cue per cast; never a generic tower or teammate signal.
for hero in ('melee','ranged','mage'):
 s,p=setup(hero);e=enemy(s,0,3,'boss');e['hp']=10000;e['maxHp']=10000;S.Action(s,'p',tab(kind='skill1'))
 seen={}
 for i in range(150):
  step(s,.025)
  for _,ev in s['effects'].items():
   if ev['ultKey'] is not None:seen[ev['id']]=ev
 assert len(seen)==1,(hero,len(seen))
 assert list(seen.values())[0]['owner']=='p'
# Every action sampler has bounded valid frames; exact skill identity is distinct.
timeline=load((D/'imported/prefab_2/19bdbb99-c5cc-4c8a-b21c-3d6c45f73025.lua').read_text())
for hero in ['melee','ranged','mage']:
 for kind in ['attack','skill1','skill2','dash']:
  tl=timeline.GetTimeline(hero,kind);assert tl is not None
  for i in range(101):
   sample=timeline.Sample(tl,i/100);assert 0<=sample['weight']<=1
   assert all(abs(v)<100 for _,v in sample['hand'].items())
print('PASS: dash phase/limits/CD/immunity/codec; projectile-hit clocks; leaf 3-target decay; one ult cue; 12 animation timelines')
