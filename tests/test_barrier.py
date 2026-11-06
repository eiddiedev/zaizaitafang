exec(open('tests/test_combat.py').read().split('for hero in [')[0])
def arena():
 s,p=setup('melee');p['x']=30;p['z']=-30;s['teamGold']=10000
 assert S.Action(s,'p',tab(kind='build',tower='barrier',slot=4)) is True
 w=s['towers'][4];w['wallHp']=w['wallMax']=100000;w['wallUntil']=s['t']+100
 return s,w

def spawn(s,w,kind,d):
 e=S.Debug(s,'spawn',tab(type=kind,route=1,d=d));e['cd']=999
 return e
for kind in ['basic','runner','armored','resistant','ranged','healer','breaker','splitter','child','guard','caster']:
 s,w=arena();e=spawn(s,w,kind,w['wallD']-1);step(s,1)
 assert abs(e['d']-(w['wallD']-.65))<1e-6,(kind,e['d'],w['wallD'])
 assert e['d']<w['wallD']
# An already-passed unit must not be captured when the wall activates behind it.
s,w=arena();e=spawn(s,w,'basic',w['wallD']+.1);d=e['d'];step(s,.3);assert e['d']>d+.4
# Different routes at the same physical point are not captured.
s,w=arena();s['layout']['routes'][2]=s['layout']['routes'][1];e=spawn(s,w,'basic',w['wallD']-.5);e['route']=2;d=e['d'];step(s,.3);assert e['d']>d+.4
# Full capacity no longer lets the next group leak through the wall.
s,w=arena();es=[spawn(s,w,'basic',w['wallD']-.7-i*.03) for i in range(8)];step(s,1)
assert all(abs(e['d']-(w['wallD']-.65))<1e-6 for e in es)
# Swept crossing catches even a complete one-frame crossing at unusually high speed.
s,w=arena();e=spawn(s,w,'runner',w['wallD']-3);old=C['enemies']['runner']['speed'];C['enemies']['runner']['speed']=100
S.Step(s,.1);C['enemies']['runner']['speed']=old;assert abs(e['d']-(w['wallD']-.65))<1e-6
# Root must not be moved toward the stop line by the collision check.
s,w=arena();e=spawn(s,w,'runner',w['wallD']-.7);e['rootUntil']=s['t']+1;d=e['d'];step(s,.2);assert e['d']==d
# Expiry releases blocked units; boss is briefly stopped then breaks the wall.
s,w=arena();e=spawn(s,w,'basic',w['wallD']-.65);w['wallUntil']=s['t']+.2;step(s,.4);assert e['d']>w['wallD']-.65
s,w=arena();e=spawn(s,w,'boss',w['wallD']-.65);step(s,1.9);assert e['d']==w['wallD']-.65 and w['wallHp']>0
step(s,.4);assert w['wallHp']==0 and e['d']>w['wallD']-.65
print('PASS 11 enemy types; already-passed/other-route exclusion; 8-enemy overflow; swept crossing; root; expiry; boss 2-second break')
