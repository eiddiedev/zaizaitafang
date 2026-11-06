exec(open('tests/test_combat.py').read().split('for hero in [')[0])
# Offline stress harness: full towers and extra core HP isolate runtime stability.
# This is not a normal-economy or human skill balance test; no online host is loaded.
run=lua.eval('''function(M,C,n)
 local s=M.NewState(71)
 for i=1,n do local p=M.AddPlayer(s,tostring(i),"QA",true);p.x=-100;p.z=-100 end
 assert(M.Action(s,"1",{kind="start"}));assert(M.Action(s,"1",{kind="beginChallenge"}))
 s.teamGold=100000
 local kinds={"crossbow","prism","mortar","slow","prism","barrier","crossbow","mortar","prism","mortar","crossbow"}
 for i,k in ipairs(kinds)do
  assert(M.Action(s,"1",{kind="build",slot=i,tower=k}))
  for j=2,4 do assert(M.Action(s,"1",{kind="upgrade",slot=i,branch=i%2==0 and "a"or"b"}))end
 end
 local maxLive,maxFx,maxPending,leaks=0,0,0,0
 for wave=1,60 do
  s.core=100000
  for i=1,n do assert(M.Action(s,tostring(i),{kind="ready"}))end
  M.Step(s,.1);assert(s.wave==wave)
  local ticks=0
  while s.phase=="WAVE_ACTIVE"do
   M.Step(s,.1);ticks=ticks+1;assert(ticks<9000,"wave stuck "..wave)
   local alive=0;for _,e in pairs(s.enemies)do if e.hp>0 then alive=alive+1 end;assert(e.hp==e.hp)end
   assert(alive<=C.maxEnemies);maxLive=math.max(maxLive,alive);maxFx=math.max(maxFx,#s.effects);maxPending=math.max(maxPending,#s.pending)
  end
  leaks=leaks+100000-s.core
  assert(s.completedWaves==wave)
  if wave==24 then assert(s.phase=="MAIN_CLEAR");assert(M.Action(s,"1",{kind="continueEndless"}))end
 end
 return maxLive,maxFx,maxPending,leaks
end''')
for n in (1,2,3):print('SOAK',n,'players, peak alive/effects/pending, leaked core damage:',run(S,C,n),flush=True)
