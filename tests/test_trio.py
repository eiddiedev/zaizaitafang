exec(open('tests/test_combat.py').read().split('for hero in [')[0])
def act(s,pid,kind,**kw):return S.Action(s,pid,tab(kind=kind,**kw)) is True
def room(n):
 s=S.NewState(42)
 for pid in ['a','b','c'][:n]:S.AddPlayer(s,pid,pid,True)
 assert act(s,'a','start')
 assert act(s,'a','beginChallenge')
 return s
assert C['maxPlayers']==3
s=room(1);assert s['teamGold']==360
assert act(s,'a','build',slot=1,tower='crossbow');assert s['teamGold']==260
q=S.AddPlayer(s,'b','friend',True);assert S.GetAvailableGold(s,'b')==260
assert act(s,'b','upgrade',slot=1);assert s['teamGold']==120
assert act(s,'b','build',slot=2,tower='crossbow');assert s['teamGold']==20
assert not act(s,'a','build',slot=3,tower='crossbow');assert s['teamGold']==20
assert act(s,'a','sell',slot=1);assert s['towers'][1] is not None
assert not act(s,'a','sell',slot=1)
assert act(s,'b','sell',slot=1);assert s['towers'][1] is None and s['teamGold']==176
assert act(s,'a','sell',slot=2);step(s,15.1);assert s['saleVote'] is None and s['towers'][2] is not None
s['phase']='WAVE_ACTIVE';assert act(s,'b','sell',slot=2)
snap=M['codec'].Decode(M['codec'].Encode(s));assert S.GetAvailableGold(snap,'a')==S.GetAvailableGold(snap,'b')==176
third=S.AddPlayer(s,'c','third',True);assert not third['spectator'];assert act(s,'c','build',slot=3,tower='crossbow')
fourth=S.AddPlayer(s,'d','fourth',True);assert fourth['spectator'];assert not act(s,'d','upgrade',slot=3)
print('PASS: solo treasury, late join shared funds, cross-player upgrade, overdraft rejection, 2-person sale approval, expiry, combat sale request, snapshots, third can build, fourth spectator')
s=room(2);assert s['teamGold']==720
assert act(s,'a','build',slot=1,tower='crossbow')
s['players']['b']['online']=False;assert act(s,'a','sell',slot=1)
assert s['teamGold']==685
S.AddPlayer(s,'c','replacement',True);S.AddPlayer(s,'d','replacement2',True);S.AddPlayer(s,'b','reconnect',True);assert s['players']['b']['spectator']
print('PASS: dual start funds, solo sale, reconnect cannot exceed three active players')
# All slots shared, no per-player cap.
s=room(2);S.Debug(s,'gold',10000)
for slot in range(1,12):assert act(s,'a','build',slot=slot,tower='crossbow')
assert not S.GetBuildQuota(s,'b')['allowed'];assert act(s,'b','upgrade',slot=1)
for n in ['config_9.lua','simulation_9.lua','runtime-host_9.lua','ui_31.lua']:lua.eval('function(s)assert(load(s))end')((D/n).read_text())
print('PASS: eleven shared slots, teammate upgrades, Lua syntax')

s=room(3);assert s['teamGold']==1080
assert act(s,'a','build',slot=1,tower='crossbow');assert act(s,'c','upgrade',slot=1)
assert S.GetAvailableGold(s,'a')==S.GetAvailableGold(s,'b')==S.GetAvailableGold(s,'c')==840
print('PASS: three-player start, shared treasury, third player upgrades')
