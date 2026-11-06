exec(open("tests/test_combat.py").read().split("for hero in [")[0])
def attacker(kind,distance):
 s,p=setup('melee');e=enemy(s,0,distance,kind);e['rootUntil']=0;e['cd']=0
 S.Step(s,.025)
 return s,p,e
for kind in ['ranged','caster','boss']:
 s,p,e=attacker(kind,3)
 assert e['cast'] is not None,kind+' must telegraph'
 original=p['hp'];end=e['cast']['untilTime'];step(s,end-s['t']+.01)
 if kind!='boss':
  assert p['hp']==original,kind+' must wait for projectile flight'
  assert e['cast'] and e['cast']['untilTime']>s['t'],kind+' warning disappeared during flight'
  step(s,1)
 assert p['hp']<original,kind+' attack should hit stationary target'
 s,p,e=attacker(kind,3);original=p['hp'];p['x']=10;step(s,2)
 assert p['hp']==original,kind+' must miss after leaving warned location'
s,p,e=attacker('boss',20)
assert e['cast'] is None,'boss must not target outside finite range'
original=p['hp'];step(s,2)
assert p['hp']==original,'boss must not deal global damage'
s,p,e=attacker('caster',3);original=p['hp'];e['hp']=0;step(s,2)
assert p['hp']==original,'dead caster must not hit'
print('PASS: ranged/caster/Boss windup, projectile travel warning, stationary hit, dodge, finite boss range, caster death cancellation')
