exec(open('tests/test_combat.py').read().split('for hero in [')[0])
s,p=setup('melee');s['phase']='INTERMISSION';s['deadline']=s['t']+60;s['ready']=lua.table();p['hp']=0;p['downUntil']=s['t']+15
step(s,20);assert p['hp']==0 and abs(p['downUntil']-s['t']-15)<1e-6,'intermission must not count'
s['phase']='WAVE_ACTIVE';e=enemy(s,20,20,'boss');e['hp']=100000;e['maxHp']=100000
step(s,10);assert p['hp']==0 and abs(p['downUntil']-s['t']-5)<1e-6
s['phase']='INTERMISSION';s['deadline']=s['t']+60;step(s,20)
assert p['hp']==0 and abs(p['downUntil']-s['t']-5)<1e-6
s['phase']='WAVE_ACTIVE';step(s,4.9);assert p['hp']==0
step(s,.2);assert p['hp']==p['maxHp']*.5
assert p['immuneUntil']>s['t'] and p['teleport'] is not None
s,p=setup('melee');s['phase']='INTERMISSION';s['deadline']=s['t']+60;s['ready']=lua.table()
q=S.AddPlayer(s,'q','friend',True);q['hp']=0;q['downUntil']=s['t']+15;q['x']=p['x'];q['z']=p['z']
assert S.Action(s,'p',tab(kind='revive')) is True
step(s,10);assert q['hp']==0 and abs(s['t']-p['revive']['t0'])<1e-6
s['phase']='WAVE_ACTIVE';e=enemy(s,20,20,'boss');e['hp']=100000
step(s,1.9);assert q['hp']==0
step(s,.2);assert q['hp']==q['maxHp']*.35
print('PASS: countdown pauses across intermissions; 15 combat seconds restores 50%, immunity; teammate aid also pauses and restores 35%')

# A disconnected downed player does not consume waiting time either.
s,p=setup('melee');s['phase']='INTERMISSION';s['deadline']=s['t']+60;s['ready']=lua.table()
p['hp']=0;p['downUntil']=s['t']+7;p['online']=False
step(s,12);assert abs(p['downUntil']-s['t']-7)<1e-6
S.AddPlayer(s,'p','reconnected',True)
assert p['hp']==0 and abs(p['downUntil']-s['t']-7)<1e-6
print('PASS: disconnected/reconnected hero keeps remaining combat-only respawn time')
