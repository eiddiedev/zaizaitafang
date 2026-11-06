---@id 7ce33de0-041b-450b-9134-666ba7c6edcd
---@referenceName helpers_simulation.lua
---@assetRef eyJhc3NldElkIjoibWl4LWNyeXN0YWwtZGVmZW5zZTpoYW1sZXQtdWdjL2FpZ2NfZWRpdG9yL2Rldi91bml0eS9NUzR3TGpBQkFBQUFpWGVTbVJUZzVIekJKb1pRTkE0OEh1eXBoeWkxME4zNmk4QjJpenpZSjNZL21peC1wYXJ0LTBfX3VwbG9hZF9qeTQyZGQzeC5nbGIiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvbWl4LXBhcnQtMF9fdXBsb2FkX2p5NDJkZDN4LmdsYiIsInJlZmVyZW5jZU5hbWUiOiJoZWxwZXJzX3NpbXVsYXRpb24ubHVhIn0
-- 权威赛局规则：地图投票、经济、二十四波、塔与英雄战斗；仅处理纯数据。
---@displayName 塔防赛局规则
local C,L
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function dist(a,b)return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2)end
local function stats(t)return C.towers[t.type][t.tier==4 and t.branch or t.tier]end
local function active(p)return p.online and not p.spectator end
local function alive(e)return e.hp>0 and not e.deadAt end
local function countAlive(S)local n=0;for _,e in pairs(S.enemies)do if alive(e)then n=n+1 end end;return n end
local function listPlayers(S)local r={};for _,p in pairs(S.players)do if active(p)then r[#r+1]=p end end;table.sort(r,function(a,b)return a.id<b.id end);return r end
local function effect(S,kind,x,z,tx,tz,family,owner,radius,duration)
 S.nextEvent=S.nextEvent+1;local ev={id=S.nextEvent,kind=kind,x=x,z=z,tx=tx or x,tz=tz or z,family=family,owner=owner,t0=S.t,duration=duration or .6,radius=radius or 1};S.effects[#S.effects+1]=ev
 while #S.effects>64 do
  local index,fallback=nil,nil
  for i=1,#S.effects-1 do
   local old=S.effects[i]
   if old.kind=="death"or old.kind=="coin"or old.kind=="burn"or old.kind=="field"then index=i;break end
   local critical=old.ultKey or old.kind=="warning"or old.kind=="hero-hurt"or old.kind=="core-hit"or old.kind=="giant-awaken"or old.kind=="meteor-impact"or old.kind=="rain-impact"
   if not critical and not fallback then fallback=i end
  end
  table.remove(S.effects,index or fallback or 1)
 end
 return ev
end
local function delayed(S,p)S.pending[#S.pending+1]=p end
local function message(p,text)p.message=text;p.messageAt=0 end
local function refreshHero(p)
 local h=C.hero[p.loadout];p.maxHp=h.hp*(1+.18*p.healthUp);p.damageScale=1+.12*p.damageUp;p.cooldownScale=math.max(.45,1-.08*p.cooldownUp)
end
local function resetHero(p)
 p.damageUp=0;p.healthUp=0;p.cooldownUp=0;p.growthPoints=0;p.earnedGrowth=0;p.cooldowns={attack=0,skill1=0,skill2=0,dash=0};p.downUntil=0;p.immuneUntil=0;p.attackHeld=false;p.contribution={damage=0,kills=0,control=0,support=0,invested=0};refreshHero(p);p.hp=p.maxHp
 p.actionSeq=0;p.actionAt=-100;p.actionKind=nil;p.actionUntil=0;p.castUntil=0;
 p.giantUntil=0;p.message=nil;p.messageAt=nil;p.motion=nil;p.lockedEnemy=nil;p.guardUntil=0;p.hitAt=nil;p.revive=nil
end
function Configure(config,layout)C=config;L=layout end
function NewState(seed)
 return {version=C.version,t=0,round=0,phase="LOBBY",wave=0,deadline=0,core=C.core,coreMax=C.core,seed=seed or 91231,players={},towers={},enemies={},effects={},pending={},spawnQueue={},pings={},votes={},acks={},nextEnemy=0,nextEvent=0,teamFunds=0,teamGold=0,candidates={},economyQuote=nil,saleVote=nil,layout=nil}
end
function AddPlayer(S,id,name,stable)
 local p=S.players[id]
 if p then
  if not p.online then p.spectator=#listPlayers(S)>=C.maxPlayers end
  p.online=true;p.leftAt=nil;p.name=name or p.name;return p end
 p={id=id,name=name or "仔仔",online=true,stable=stable==true,loadout="melee",gold=0,x=0,z=-11.4,angle=0,fx=0,fz=1,ready=false,selectedSlot=1,joinedRound=S.round,late=S.phase~="LOBBY" and S.phase~="RANKING" and S.phase~="PREPARE",hasGrant=false}
 if #listPlayers(S)>=C.maxPlayers then p.spectator=true end
 resetHero(p);S.players[id]=p
 if p.late then p.growthPoints=math.floor(math.max(0,S.wave-1)/C.growthEvery);p.earnedGrowth=p.growthPoints;p.eligibleFrom=S.wave+1
 elseif S.phase=="PREPARE" then p.gold=0;p.hasGrant=true;p.eligibleFrom=1 end
 return p
end
function SetRoster(S,roster)
 local seen={};for _,r in ipairs(roster)do
  local p=AddPlayer(S,r.id,r.name,r.stable);seen[r.id]=true;p.online=true;p.x=r.x;p.z=r.z;p.angle=r.angle;p.fx=r.fx;p.fz=r.fz
 end
 for id,p in pairs(S.players)do if not seen[id] and p.online then p.online=false;p.leftAt=S.t;p.attackHeld=false;p.revive=nil end end

end
local function readyAll(S)local ps=listPlayers(S);if #ps==0 then return false end;for _,p in ipairs(ps)do if not p.ready then return false end end;return true end
local function startRound(S)
 S.round=S.round+1;S.phase="RANKING";S.endless=false;S.completedWaves=0;S.wave=0;S.core=C.core;S.deadline=S.t+C.voteTime;S.seed=(S.seed*48271+97)%2147483647
 S.towers={};S.enemies={};S.pending={};S.effects={};S.spawnQueue={};S.pings={};S.votes={};S.layout=nil;S.teamFunds=0;S.teamGold=0;S.economyQuote=nil;S.saleVote=nil;S.result=nil;S.zones={};S.wallCooldowns={};S.economyWaveSpent=0;S.economyKillSpent=0
 S.buildMembers={};S.buildPlayerCount=0
 for _,member in ipairs(listPlayers(S))do S.buildMembers[member.id]=true;S.buildPlayerCount=S.buildPlayerCount+1 end
 S.candidates={}
 for _,p in pairs(S.players)do p.gold=0;p.ready=false;p.late=false;p.hasGrant=false;p.eligibleFrom=1;p.selectedSlot=1;p.joinedRound=S.round;resetHero(p)end
end
local function selectMap(S,theme)
 S.theme="forest";S.layout=L.Generate("forest",S.seed)
 if not S.layout then return end
 S.phase="PREPARE";S.deadline=S.t+C.prepare;S.teamGold=C.startGold*#listPlayers(S)
 for i,p in ipairs(listPlayers(S))do
  p.gold=0;p.hasGrant=true;p.ready=false;p.selectedSlot=math.min(i,#S.layout.slots-1)
  local slot=S.layout.slots[p.selectedSlot];local spawn=S.layout.spawn;p.teleport={x=spawn and spawn.x+(i-1)*.65 or slot.x+1,z=spawn and spawn.z or slot.z+1,id=S.round*100+i};p.x=p.teleport.x;p.z=p.teleport.z
 end
 effect(S,"start",S.layout.core.x,S.layout.core.z)
end
local function addIncome(S,amount)
 S.teamGold=(S.teamGold or 0)+amount
end
local function enemyWaveScale(wave,boss,damage)
 if wave<=24 then return 1+(damage and .06 or .09)*(wave-1) end
 local key=damage and (boss and "bossDamage"or"damage")or(boss and "bossHp"or"hp")
 local curve=C.endlessCurve
 for i=2,#curve do
  local a,b=curve[i-1],curve[i]
  if wave<=b.wave then return a[key]+(b[key]-a[key])*(wave-a.wave)/(b.wave-a.wave) end
 end
 local last=curve[#curve]
 return last[key]+(wave-last.wave)*(damage and .04 or (boss and .10 or .16))
end
local function spawnEnemy(S,typeName,routeId,d,threat)
 local cfg=C.enemies[typeName];S.nextEnemy=S.nextEnemy+1
 local hp
 local scale=(cfg.elite or cfg.boss) and C.eliteScale[S.waveN]or C.healthScale[S.waveN]
 hp=cfg.hp*enemyWaveScale(S.wave,cfg.boss,false)*scale*(cfg.boss and .7 or (S.wave<=23 and 1.2 or 1))
 local x,z,angle=L.PointAt(S.layout.routes[routeId],d or 0)
 local e={id=S.nextEnemy,type=typeName,route=routeId,d=d or 0,x=x,z=z,angle=angle,hp=hp,maxHp=hp,threat=threat or cfg.threat,cd=S.t+.5,rootUntil=0,rootImmuneUntil=0,slowUntil=0,slow=0,burnUntil=0,burnNext=0,burn=0,hitAt=-10,attackAt=-10,phase=1}
 S.enemies[e.id]=e;return e
end
local function waveSpec(index)
 if C.waves[index]then return C.waves[index]end
 if C.endlessWaves[index]then return C.endlessWaves[index]end
 -- Beyond 60, repeat the final authored stage with bounded extra escorts.
 local depth=index-60
 local source=C.endlessWaves[55+(depth-1)%6];local wave={window=math.min(60,source.window+math.floor(depth/12))}
 for kind,n in pairs(source)do
  if kind~="window"then
   wave[kind]=(kind=="boss")and n or math.min(C.enemies[kind].elite and 4 or 32,math.ceil(n*(1+math.min(depth,60)*.01)))
  end
 end
 return wave
end
local function beginWave(S)
 S.wave=S.wave+1;S.phase="WAVE_ACTIVE";S.waveStart=S.t;S.waveMembers={};S.waveThreat=0;S.killedThreat=0;S.spawnQueue={};S.waveN=clamp(#listPlayers(S),1,4)
 for _,p in ipairs(listPlayers(S))do
  p.ready=false
  if p.late and not p.hasGrant then
   -- Late joiners use the existing team treasury; reconnects never mint gold.
   p.hasGrant=true;p.late=false
  end
  p.eligibleFrom=p.eligibleFrom or S.wave
  if p.eligibleFrom<=S.wave then S.waveMembers[#S.waveMembers+1]=p.id end
 end
 local wave=waveSpec(S.wave);local entries,total,baseTotal={},0,0
 for name,n in pairs(wave)do if name~="window"then local cfg=C.enemies[name];local exact=(cfg.elite or cfg.boss) and n or n*C.countScale[S.waveN];entries[#entries+1]={name=name,n=math.floor(exact),frac=exact%1,elite=cfg.elite or cfg.boss};total=total+math.floor(exact);baseTotal=baseTotal+exact end end
 table.sort(entries,function(a,b)if a.frac==b.frac then return a.name<b.name end;return a.frac>b.frac end)
 local missing=math.floor(baseTotal+.5)-total;for _,e in ipairs(entries)do if missing>0 and not e.elite then e.n=e.n+1;missing=missing-1;total=total+1 end end
 local names={};local maxN=0;for _,e in ipairs(entries)do maxN=math.max(maxN,e.n)end
 for j=1,maxN do for _,e in ipairs(entries)do if e.n>=j then names[#names+1]=e.name end end end
 for i,name in ipairs(names)do local cfg=C.enemies[name];local at=(i-1)/math.max(1,#names-1)*wave.window;if name=="boss"then at=0 end
  S.spawnQueue[#S.spawnQueue+1]={type=name,route=((i-1)%#S.layout.routes)+1,at=S.t+at};S.waveThreat=S.waveThreat+cfg.threat
 end
 table.sort(S.spawnQueue,function(a,b)return a.at<b.at end)
 S.economyWaveSpent=0;S.economyKillSpent=0
 for _,t in pairs(S.towers)do t.waveIncome=0;t.killIncome=0;t.incomeNext=S.t+5;t.incomeTimer=0 end
 effect(S,"wave",S.layout.core.x,S.layout.core.z,nil,nil,nil,nil,nil,.8)
end
local function finishWave(S)
 local reward=math.floor((C.waveRewardBase+C.waveRewardStep*S.wave)*(.7+.3*clamp(S.killedThreat/math.max(1,S.waveThreat),0,1))+1e-6)
 for _,id in ipairs(S.waveMembers or {})do local p=S.players[id];if p then addIncome(S,reward);p.message="守住第"..S.wave.."波 +"..reward.."金";if p.hp>0 then p.hp=math.min(p.maxHp,p.hp+p.maxHp*.3);effect(S,"heal",p.x,p.z,nil,nil,"wave",p.id,1,.8)end end end
 for _,t in pairs(S.towers)do if t.type=="economy" and t.branch=="a"then addIncome(S,12)end end
 if S.wave%C.growthEvery==0 then for _,p in pairs(S.players)do local target=math.floor(S.wave/C.growthEvery);if p.earnedGrowth<target then p.growthPoints=p.growthPoints+target-p.earnedGrowth;p.earnedGrowth=target end end end
 S.completedWaves=S.wave
 if S.wave==#C.waves and not S.endless then
  S.phase="MAIN_CLEAR";S.pending={};S.result={won=true,title="已通过主线关卡",waves=S.wave,core=S.core}
  for _,p in pairs(S.players)do p.attackHeld=false;p.ready=false end
  effect(S,"victory",S.layout.core.x,S.layout.core.z);return
 end
 local intro=C.introductions[S.wave+1]or{}
 S.phase="INTERMISSION";S.deadline=S.t+(#intro>0 and 30 or C.intermission);S.pending={};for _,p in pairs(S.players)do p.ready=false;p.attackHeld=false end
end
local killEnemy
local function damageEnemy(S,e,damage,magic,owner,hero,style)
 if not e or not alive(e)then return 0 end
 local cfg=C.enemies[e.type];local res=cfg.res;if (e.corrosionUntil or 0)>S.t then res=math.max(0,res-(e.corrosion or 0))end
 local actual=damage*(magic and (1-res)or 100/(100+cfg.armor));actual=math.min(actual,e.hp);e.hp=e.hp-actual;e.hitAt=S.t
 if actual>0 then
  local numberFx=effect(S,"damage-number",e.x,e.z,nil,nil,magic and "magic"or "physical",owner,1,.85)
  numberFx.amount=actual;numberFx.target=e.id;numberFx.hero=hero==true;numberFx.enemyType=e.type
 end
 if actual>0 and S.t-(e.lastHitFx or -10)>=.12 then e.lastHitFx=S.t;local hit=effect(S,"hit",e.x,e.z,nil,nil,style or (magic and "prism"or "physical"),owner,.35,.22);hit.target=e.id end
 local p=S.players[owner];if p then p.contribution.damage=p.contribution.damage+actual end
 if hero and e.markUntil and e.markUntil>S.t then local t=S.towers[e.markTower];if t and (t.markReady or 0)<=S.t then t.markReady=S.t+1.5;e.markUntil=0;damageEnemy(S,e,40,false,t.owner,false);effect(S,"mark",e.x,e.z,nil,nil,"crossbow",owner,1,.4)end end
 if e.hp<=0 and not e.deadAt then killEnemy(S,e,owner)end;return actual
end
killEnemy=function(S,e,owner)
 e.hp=0;e.deadAt=S.t;e.cast=nil;local reward=e.threat
 if e.type=="splitter"then reward=e.threat/3;for i=1,2 do S.spawnQueue[#S.spawnQueue+1]={type="child",route=e.route,d=math.max(0,e.d+(i-1)*.7),at=S.t+.25,threat=e.threat/3}end;table.sort(S.spawnQueue,function(a,b)return a.at<b.at end)end
 S.killedThreat=S.killedThreat+reward;local p=S.players[owner];if p then p.contribution.kills=p.contribution.kills+1 end
 for _,t in pairs(S.towers)do if t.type=="economy" and t.branch=="b" and dist(t,e)<=10 then local amount=math.min(88-(S.economyKillSpent or 0),2*reward);if amount>0 then S.economyKillSpent=(S.economyKillSpent or 0)+amount;t.killIncome=(t.killIncome or 0)+amount;addIncome(S,amount);effect(S,"coin",t.x,t.z,e.x,e.z,"economy",t.id,.6,.6)end end end
 effect(S,"death",e.x,e.z,nil,nil,e.type,owner,C.enemies[e.type].boss and 4 or 1,.7)
end
local function damageHero(S,p,damage,magic)
 if not p or not active(p)or p.hp<=0 or (p.immuneUntil or 0)>S.t then return end
 local h=C.hero[p.loadout];local reduction=1
 for _,zone in ipairs(S.zones or {})do if zone.kind=="ward" and zone.untilTime>S.t and dist(p,zone)<=zone.radius then reduction=.65;break end end
 local d=damage*reduction*(magic and 1 or 100/(100+h.armor));if (p.guardUntil or 0)>S.t then d=d*.6 end
 p.hp=math.max(0,p.hp-d);p.hitAt=S.t;effect(S,"hero-hurt",p.x,p.z,nil,nil,magic and "caster"or "physical",p.id,.55,.24)
 if p.hp<=0 then p.downUntil=S.t+25;p.giantUntil=0;p.attackHeld=false;p.motion=nil;effect(S,"down",p.x,p.z,nil,nil,nil,p.id)end
end
local function slowEnemy(S,e,amount,duration)
 if C.enemies[e.type].boss then amount=math.min(.2,amount)end
 if amount>=e.slow or e.slowUntil<=S.t then e.slow=amount;e.slowUntil=S.t+duration end
end
local function rootEnemy(S,e,duration)
 local cfg=C.enemies[e.type]
 if cfg.boss then slowEnemy(S,e,.2,1);return end
 if S.t<e.rootImmuneUntil then return end
 if cfg.elite then duration=duration*.5 end;e.rootUntil=S.t+duration;e.rootImmuneUntil=e.rootUntil+3
end
local function targets(S,x,z,range)
 local a={};for _,e in pairs(S.enemies)do if alive(e)and (e.x-x)^2+(e.z-z)^2<=range*range then a[#a+1]=e end end
 table.sort(a,function(e,f)local a1=S.layout.routes[e.route].length-e.d;local b1=S.layout.routes[f.route].length-f.d;if a1==b1 then return e.id<f.id end;return a1<b1 end);return a
end
local function areaDamage(S,x,z,radius,damage,magic,owner,limit,falloff,style)
 local a=targets(S,x,z,radius);table.sort(a,function(e,f)return (e.x-x)^2+(e.z-z)^2<(f.x-x)^2+(f.z-z)^2 end)
 for i=1,math.min(limit or 5,#a)do local factor=(falloff and dist(a[i],{x=x,z=z})>radius*.45)and .6 or 1;damageEnemy(S,a[i],damage*factor,magic,owner,false,style)end
end
local function lineTargets(S,x,z,fx,fz,range,width)
 local a={};for _,e in pairs(S.enemies)do if alive(e)then local dx,dz=e.x-x,e.z-z;local along=dx*fx+dz*fz;local side=math.abs(dx*fz-dz*fx);if along>=0 and along<=range and side<=width then a[#a+1]={e=e,along=along}end end end
 table.sort(a,function(a,b)return a.along<b.along end);return a
end
local function breakWall(S,t,byDamage)
 if not t.wallUntil or t.wallUntil<=0 then return end
 t.wallUntil=0;t.wallHp=0;t.cd=S.t+12
 effect(S,"wall-break",t.wallX,t.wallZ,nil,nil,"barrier",t.id,2,.5)
 if byDamage and t.branch=="b"then local a=targets(S,t.wallX,t.wallZ,3);for i=1,math.min(5,#a)do local e=a[i];local cfg=C.enemies[e.type];if not cfg.boss then e.d=math.max(0,e.d-(cfg.elite and .5 or 1.5))end end end
end
local function towerAttack(S,t)
 local cfg=stats(t);if t.type=="economy" or t.type=="barrier"then return end
 if (t.cd or 0)>S.t then return end
 local a=targets(S,t.x,t.z,cfg.range);if #a==0 then return end
 local e=a[1];local interval=cfg.interval
 if t.type=="crossbow" and t.branch=="a"then if t.lastTarget==e.id then t.streak=(t.streak or 0)+1 else t.streak=1 end;interval=math.max(.2,.25-math.floor(t.streak/2)*.01)end
 t.lastTarget=e.id;t.cd=S.t+interval;t.attackAt=S.t;t.angle=math.deg(math.atan(e.x-t.x,e.z-t.z))
 local shot=effect(S,"shot",t.x,t.z,e.x,e.z,t.type,t.id,cfg.radius or 1,t.type=="mortar" and .9 or .4);shot.branch=t.branch;shot.tier=t.tier;shot.target=e.id
 local delay=t.type=="mortar" and (.3+dist(t,e)/16)or (t.type=="prism" and .28 or .1+dist(t,e)/35)
 shot.duration=delay;shot.hitAt=S.t+delay
 delayed(S,{due=S.t+delay,kind="tower",id=t.id,type=t.type,branch=t.branch,damage=cfg.damage,range=cfg.range,radius=cfg.radius,slow=cfg.slow,target=e.id,x=e.x,z=e.z,sx=t.x,sz=t.z,owner=t.owner})
end
local function resolvePending(S,a)
 if a.kind=="heroVisual"then
  local p=S.players[a.owner];if not p or not active(p)or p.hp<=0 then return end
  local ev=effect(S,a.visual,p.x,p.z,a.x,a.z,a.family,a.owner,a.radius,a.duration);ev.target=a.target;ev.hitAt=a.hitAt or (S.t+a.duration)
 elseif a.kind=="tower"then
  local e=S.enemies[a.target];local t=S.towers[a.id]
  if a.type=="mortar"then areaDamage(S,a.x,a.z,a.radius,a.damage,false,a.owner,5,true,"mortar");local blast=effect(S,"impact",a.x,a.z,nil,nil,"mortar",a.id,a.radius,.6);blast.branch=a.branch
   if a.branch=="a"then delayed(S,{kind="area",due=S.t+.65,x=a.x,z=a.z,radius=a.radius,damage=90,owner=a.owner})
   elseif a.branch=="b"then S.zones=S.zones or {};S.zones[#S.zones+1]={x=a.x,z=a.z,radius=a.radius,untilTime=S.t+3,nextTick=S.t,damage=9,owner=a.owner,kind="burn"}end
  elseif a.type=="slow"then local es=targets(S,a.sx,a.sz,a.range);for i=1,math.min(8,#es)do slowEnemy(S,es[i],a.slow,a.branch=="a" and 2.5 or 1.4);damageEnemy(S,es[i],a.damage,true,a.owner,false,"time")end
   if a.branch=="b"and t and (t.rootCd or 0)<=S.t then t.rootCd=S.t+6;for i=1,math.min(5,#es)do rootEnemy(S,es[i],1.4)end end
  elseif a.type=="prism"and a.branch=="a"then local dx,dz=a.x-a.sx,a.z-a.sz;local n=math.sqrt(dx*dx+dz*dz);if n>0 then local es=lineTargets(S,a.sx,a.sz,dx/n,dz/n,a.range,.8);for i=1,math.min(3,#es)do damageEnemy(S,es[i].e,a.damage*({1,.65,.4})[i],true,a.owner,false,"beam")end end
  elseif e and alive(e)then
   damageEnemy(S,e,a.damage,a.type=="prism",a.owner,false,a.type=="crossbow" and "arrow" or (a.branch=="b" and "corrosion" or "prism"))
   if a.type=="crossbow"and a.branch=="b"then e.markUntil=S.t+2;e.markTower=a.id end
   if a.type=="prism"and a.branch=="b"then e.corrosion=math.min(.15,(e.corrosion or 0)+.03);e.corrosionUntil=S.t+3;if t then if t.focus~=e.id then t.focus=e.id;t.focusHits=0 end;t.focusHits=(t.focusHits or 0)+1;if t.focusHits%6==0 then damageEnemy(S,e,40,true,a.owner,false)end end end
  end
 elseif a.kind=="area"then areaDamage(S,a.x,a.z,a.radius,a.damage,a.magic,a.owner,5,false,"mortar");effect(S,"impact",a.x,a.z,nil,nil,"mortar",nil,a.radius,.4)
 elseif a.kind=="meleeStrike"then
  local p=S.players[a.owner];if not p or not active(p)or p.hp<=0 then return end
  -- Read the authority's approach endpoint, not a delayed client roster sample.
  if p.motion and p.motion.id==a.motionId then p.x=p.motion.ex;p.z=p.motion.ez end
  local target=S.enemies[a.target];local fx,fz=a.fx,a.fz
  if target and alive(target)then
   local dx,dz=target.x-p.x,target.z-p.z;local d=math.sqrt(dx*dx+dz*dz)
   if d>.01 and d<=2.15 then fx,fz=dx/d,dz/d end
  end
  p.fx=fx;p.fz=fz;p.angle=math.deg(math.atan(fx,fz));p.attackAt=S.t
  local giant=(p.giantUntil or 0)>S.t
  local strikeRange=giant and 5 or 1.95
  local candidates=targets(S,p.x,p.z,strikeRange)
  table.sort(candidates,function(a,b)
   if a.id==b.id then return false elseif a.id==p.lockedEnemy then return true elseif b.id==p.lockedEnemy then return false end
   local da,db=dist(p,a),dist(p,b);return da==db and a.id<b.id or da<db
  end)
  local count=0
  for _,e in ipairs(candidates)do
   local d=dist(p,e)
   if d<.15 or ((e.x-p.x)*fx+(e.z-p.z)*fz)/d>=.35 then
    count=count+1;damageEnemy(S,e,a.damage*(giant and 1.75 or 1)*({1,.65,.45,.35,.25})[count],false,p.id,true,giant and "giant" or "sword")
    if count==(giant and 5 or 3)then break end
   end
  end
  local visualRange=strikeRange
  effect(S,"hero-melee",p.x,p.z,p.x+fx*visualRange,p.z+fz*visualRange,giant and "giant"or nil,p.id,visualRange,.28)
 elseif a.kind=="mageBurst"then
  local p=S.players[a.owner];if not p or not active(p)or p.hp<=0 then return end
  local es=targets(S,a.x,a.z,a.radius)
  for i=1,math.min(6,#es)do damageEnemy(S,es[i],a.damage,true,a.owner,true,"mage-burst")end
  effect(S,"mage-burst",a.x,a.z,nil,nil,"prism",a.owner,a.radius,.42)
 elseif a.kind=="globalRainVisual"then
  local p=S.players[a.owner];if not p or not active(p)or p.hp<=0 then return end
   local bounds=S.layout.bounds
   effect(S,"global-arrow-rain",(bounds.minX+bounds.maxX)/2,(bounds.minZ+bounds.maxZ)/2,nil,nil,"crossbow",a.owner,math.max(bounds.maxX-bounds.minX,bounds.maxZ-bounds.minZ)/2,.55)
 elseif a.kind=="ultimateImpact"then
  local p=S.players[a.owner];if not p or not active(p)or p.hp<=0 then return end
  if a.style=="arrows"then
   for _,e in pairs(S.enemies)do if alive(e)then damageEnemy(S,e,a.damage,false,a.owner,true,"rain")end end
   if a.first then local cue=effect(S,"rain-impact",p.x,p.z,nil,nil,"rain",a.owner,1,.2);cue.ultKey=a.ultKey end

  else
   areaDamage(S,a.x,a.z,a.radius,a.damage,a.style=="meteor",a.owner,24,true,"meteor")
   local cue=effect(S,"meteor-impact",a.x,a.z,nil,nil,"mortar",a.owner,a.radius,.85);cue.ultKey=a.ultKey
   if a.style=="meteor"then S.zones[#S.zones+1]={kind="ward",x=a.x,z=a.z,radius=4.2,untilTime=S.t+8,nextTick=S.t+.5,damage=12*p.damageScale,owner=a.owner}end
  end
 elseif a.kind=="mageWard"then
  local p=S.players[a.owner];if not p or not active(p)or p.hp<=0 then return end
  p.guardUntil=S.t+3
  for _,e in ipairs(targets(S,p.x,p.z,3))do damageEnemy(S,e,a.damage,true,a.owner,true);slowEnemy(S,e,.35,2)end
  effect(S,"impact",p.x,p.z,nil,nil,"slow",a.owner,3,.45)
 elseif a.kind=="heroHit"then for _,hit in ipairs(a.hits)do local e=S.enemies[hit.id];if e and alive(e)then damageEnemy(S,e,a.damage*hit.factor,a.magic,a.owner,true,a.style)end end
 elseif a.kind=="heroBottle"then areaDamage(S,a.x,a.z,2.4,35,true,a.owner,8,false);S.zones=S.zones or {};S.zones[#S.zones+1]={x=a.x,z=a.z,radius=2.4,untilTime=S.t+3,nextTick=S.t,slow=.25,kind="slow",owner=a.owner}
 elseif a.kind=="enemyLaunch"then
  local e=S.enemies[a.enemy];if not e or not alive(e)then return end
  local travel=math.max(.25,math.min(.75,dist(e,{x=a.x,z=a.z})/11))
  effect(S,"shot",e.x,e.z,a.x,a.z,e.type,e.id,.5,travel)
  a.kind="enemyHit";a.due=S.t+travel;if e.cast then e.cast.untilTime=a.due end;delayed(S,a)
 elseif a.kind=="enemyHit"then
  local e=S.enemies[a.enemy];if not e or not alive(e)then return end;e.cast=nil;effect(S,"impact",a.x,a.z,nil,nil,e.type,e.id,a.radius,.3)
  if a.wall then local t=S.towers[a.wall];if t and (t.wallUntil or 0)>S.t then t.wallHp=t.wallHp-a.damage;effect(S,"wall-hit",t.wallX,t.wallZ,nil,nil,"barrier",t.id,1,.22);if t.branch=="a" and not t.reserveUsed and t.wallHp<=t.wallMax*.3 then t.wallHp=t.wallHp+700;t.reserveUsed=true end;if t.wallHp<=0 then breakWall(S,t,true)end end
  else for _,p in ipairs(listPlayers(S))do if p.hp>0 and dist(p,{x=a.x,z=a.z})<a.radius then damageHero(S,p,a.damage,a.magic)end end end
 elseif a.kind=="heal"then local e=S.enemies[a.enemy];if e and alive(e)then e.cast=nil;local es=targets(S,e.x,e.z,5);local n=0;for _,other in ipairs(es)do if other.id~=e.id and other.type~="boss"and other.hp<other.maxHp then other.hp=math.min(other.maxHp,other.hp+other.maxHp*.08);effect(S,"heal",other.x,other.z,nil,nil,"healer",e.id,.7,.6);n=n+1;if n==3 then break end end end end
 end
end

local function heroAttack(S,p,kind)
 if S.phase~="WAVE_ACTIVE"or p.hp<=0 then return false,"战斗开始后使用"end
 local h=C.hero[p.loadout];local cd=p.cooldowns[kind]or 0;if cd>S.t then return false,"技能冷却中"end
 if (p.castUntil or 0)>S.t then return false,"动作尚未结束"end
 local fx,fz=p.fx or 0,p.fz or 1;local n=math.sqrt(fx*fx+fz*fz);if n<.01 then fx,fz=0,1 else fx,fz=fx/n,fz/n end
 local damage,magic,hits,delay,range=0,false,{},.16,h.range
 p.attackAt=S.t;p.immuneUntil=0
 p.actionSeq=(p.actionSeq or 0)+1;p.actionKind=kind;p.actionAt=S.t;p.actionUntil=S.t+.5
 p.castUntil=S.t+(kind=="attack" and .28 or .5)
 if p.loadout~="melee" and kind~="dash" then
  local target=nil;local best=math.huge
  for _,e in ipairs(targets(S,p.x,p.z,h.range))do
   local d=dist(p,e);local facing=d>.01 and ((e.x-p.x)*fx+(e.z-p.z)*fz)/d or 1
   local score=d+.8*(1-facing)
   if score<best then best=score;target=e end
  end
  if target then local d=dist(p,target);if d>.01 then fx,fz=(target.x-p.x)/d,(target.z-p.z)/d end;p.lockedEnemy=target.id else p.lockedEnemy=nil end
  p.fx=fx;p.fz=fz;p.angle=math.deg(math.atan(fx,fz))
  p.actionX=target and target.x or p.x+fx*h.range;p.actionZ=target and target.z or p.z+fz*h.range
 end
 if kind=="skill1"then
  p.cooldowns.skill1=S.t+h.skill1*p.cooldownScale;p.castUntil=S.t+.65;p.actionUntil=S.t+.9
  local x,z=p.actionX or p.x+fx*3,p.actionZ or p.z+fz*3
  if p.loadout=="melee"then
   p.giantUntil=S.t+15;p.castUntil=S.t+.25;p.actionUntil=S.t+.35
   local cue=effect(S,"giant-awaken",p.x,p.z,p.x+fx*3.8,p.z+fz*3.8,"giant",p.id,3.8,.4);cue.ultKey=p.actionSeq
  elseif p.loadout=="ranged"then
   for i=1,6 do
    delayed(S,{kind="globalRainVisual",due=S.t+.05+(i-1)*.5,owner=p.id,cancelOnDeath=true})
    delayed(S,{kind="ultimateImpact",style="arrows",first=i==1,ultKey=p.actionSeq,due=S.t+.6+(i-1)*.5,damage=10*p.damageScale,owner=p.id,cancelOnDeath=true})
   end
  else
   effect(S,"meteor-fall",x,z,nil,nil,"mortar",p.id,4.2,1.1)
   delayed(S,{kind="ultimateImpact",style="meteor",ultKey=p.actionSeq,due=S.t+1.1,x=x,z=z,radius=4.2,damage=160*p.damageScale,owner=p.id,cancelOnDeath=true})
  end
  return true
 end
 if p.loadout=="mage" and kind~="dash" then
  if kind=="attack"then
   p.cooldowns.attack=S.t+h.interval;p.castUntil=S.t+.32;p.actionUntil=S.t+.40
   local target=S.enemies[p.lockedEnemy]
   local travel=target and dist(p,target)/22 or h.range/22
   if target and alive(target)then delayed(S,{kind="heroHit",style="orb",due=S.t+.28+travel,damage=h.damage*p.damageScale,magic=true,hits={{id=target.id,factor=1}},owner=p.id,cancelOnDeath=true})end
   delayed(S,{kind="heroVisual",due=S.t+.28,visual="hero-magic",x=p.actionX,z=p.actionZ,family="prism",owner=p.id,radius=.5,duration=travel,target=target and target.id,hitAt=S.t+.28+travel})
   effect(S,"hero-charge",p.x,p.z,nil,nil,"mage",p.id,.4,.28)
  elseif kind=="skill2"then
   p.cooldowns.skill2=S.t+h.skill2*p.cooldownScale;p.castUntil=S.t+.5;p.actionUntil=S.t+.60
   delayed(S,{kind="mageBurst",due=S.t+.48,x=p.actionX,z=p.actionZ,radius=2.6,damage=90*p.damageScale,owner=p.id,cancelOnDeath=true})
   delayed(S,{kind="heroVisual",due=S.t+.40,visual="mage-focus",x=p.actionX,z=p.actionZ,family="prism",owner=p.id,radius=2.6,duration=.08})
  else return false,"未知技能"end
  return true
 end
 if kind=="dash"then
  p.cooldowns.dash=S.t+4;p.immuneUntil=S.t+.2;p.motion={sx=p.x,sz=p.z,ex=clamp(p.x+fx*3,S.layout.bounds.minX,S.layout.bounds.maxX),ez=clamp(p.z+fz*3,S.layout.bounds.minZ,S.layout.bounds.maxZ),t0=S.t,moveAt=S.t+.08,ends=S.t+.30,id=S.nextEvent+1,kind="dash"};p.actionUntil=S.t+.30;effect(S,"dash",p.x,p.z,p.motion.ex,p.motion.ez,p.loadout,p.id,1,.3);return true
 elseif kind=="attack"then
  p.cooldowns.attack=S.t+h.interval;damage=h.damage*p.damageScale
  if p.loadout=="ranged"then p.actionUntil=S.t+.365 end
  if p.loadout=="melee"then
   local target,best=nil,math.huge
   local existing=S.enemies[p.lockedEnemy]
   if existing and alive(existing)and dist(p,existing)<=4.2 then target=existing end
   if not target then
    for _,e in ipairs(targets(S,p.x,p.z,4.2))do
     local d=dist(p,e);local facing=d>.01 and ((e.x-p.x)*fx+(e.z-p.z)*fz)/d or 1
     local score=d+.35*(1-facing)
     if score<best or (score==best and target and e.id<target.id)then target=e;best=score end
    end
   end
   local motionId=nil
   if target then
    p.lockedEnemy=target.id
    local dx,dz=target.x-p.x,target.z-p.z;local d=math.sqrt(dx*dx+dz*dz)
    if d>.01 then fx,fz=dx/d,dz/d end
    p.fx=fx;p.fz=fz;p.angle=math.deg(math.atan(fx,fz))
    if d>((p.giantUntil or 0)>S.t and 4.6 or 1.55) and not(p.motion and p.motion.ends>S.t)then
     local travel=math.min(3.1,math.max(0,d-((p.giantUntil or 0)>S.t and 4.2 or 1.1)));local duration=clamp(travel/14,.09,.23)
     local ex=clamp(p.x+fx*travel,S.layout.bounds.minX,S.layout.bounds.maxX)
     local ez=clamp(p.z+fz*travel,S.layout.bounds.minZ,S.layout.bounds.maxZ)
     local ev=effect(S,"attack-approach",p.x,p.z,ex,ez,nil,p.id,.5,duration)
     motionId=ev.id;p.motion={sx=p.x,sz=p.z,ex=ex,ez=ez,t0=S.t,ends=S.t+duration,id=motionId,kind="attackApproach"}
     p.actionAt=S.t+duration;delay=duration+.22
    else delay=.22 end
   else p.lockedEnemy=nil;delay=.22 end
   p.actionX=p.x+fx*1.7;p.actionZ=p.z+fz*1.7;p.actionUntil=p.actionAt+.52;p.castUntil=S.t+delay+.06
   delayed(S,{kind="meleeStrike",due=S.t+delay,damage=damage,owner=p.id,target=target and target.id,fx=fx,fz=fz,motionId=motionId,cancelOnDeath=true})
   return true
  else local es=lineTargets(S,p.x,p.z,fx,fz,9,.6);local target=es[1] and es[1].e;if target then hits={{id=target.id,factor=1}};delay=.18+es[1].along/25 end;delayed(S,{kind="heroVisual",due=S.t+.18,visual="hero-ranged",x=target and target.x or p.x+fx*9,z=target and target.z or p.z+fz*9,owner=p.id,radius=.5,duration=target and math.max(.01,delay-.18)or .36,target=target and target.id,hitAt=target and S.t+delay or S.t+.54}) end
 elseif kind=="skill2"then
  p.cooldowns.skill2=S.t+h.skill2*p.cooldownScale
  if p.loadout=="melee"then p.actionUntil=S.t+.365;damage=60*p.damageScale;delay=.22;local es=targets(S,p.x,p.z,2.2);for i=1,math.min(5,#es)do hits[#hits+1]={id=es[i].id,factor=1}end;delayed(S,{kind="heroVisual",due=S.t+.16,visual="hero-spin",x=p.x+fx,z=p.z+fz,owner=p.id,radius=2.2,duration=.205})
  else effect(S,"hero-charge",p.x,p.z,nil,nil,"leaf",p.id,.4,.20);damage=120*p.damageScale;magic=true;delay=.32;local es=lineTargets(S,p.x,p.z,fx,fz,12,.8);for i=1,math.min(3,#es)do hits[#hits+1]={id=es[i].e.id,factor=({1,.65,.4})[i]}end;delayed(S,{kind="heroVisual",due=S.t+.20,visual="hero-pierce",x=p.x+fx*12,z=p.z+fz*12,family="leaf",owner=p.id,radius=1,duration=.12})end
 else return false,"未知技能"end
 delayed(S,{kind="heroHit",style=p.loadout=="melee" and "spin" or (kind=="skill2" and "leaf" or "arrow"),due=S.t+delay,damage=damage,magic=magic,hits=hits,owner=p.id,cancelOnDeath=p.loadout=="melee"});return true
end

local function available(S,p)return math.max(0,S.teamGold or 0)end
-- Both active heroes share all eight authored slots, including late arrivals.
function GetBuildQuota(S,id)
 local total=0;for _ in pairs(S.towers)do total=total+1 end
 local capacity=S.layout and #S.layout.slots or 8;local p=S.players[id]
 return {owned=total,base=capacity,extra=0,allowed=p~=nil and active(p) and total<capacity,team=true}
end
local function applyBuild(S,p,slotId,kind,tier,branch,contributors)
 local slot=S.layout.slots[slotId];local t=S.towers[slotId];local isNew=t==nil;local cfg=C.towers[kind][tier==4 and branch or tier]
 if not t then t={id=slotId,type=kind,tier=tier,owner=p.id,x=slot.x,z=slot.z,wallX=slot.wallX,wallZ=slot.wallZ,route=slot.route,wallD=slot.d,angle=0,cd=S.t+.3,invested=0,investors={},incomeNext=S.t+5,waveIncome=0,killIncome=0,attackAt=-100};S.towers[slotId]=t end
 if kind=="economy"then t.waveIncome=S.economyWaveSpent or 0;t.killIncome=S.economyKillSpent or 0 end
 t.tier=tier;t.branch=branch;t.invested=t.invested+cfg.cost;t.upgradeAt=S.t
 for id,amount in pairs(contributors)do local donor=S.players[id];S.teamGold=(S.teamGold or 0)-amount;donor.contribution.invested=donor.contribution.invested+amount;t.investors[id]=(t.investors[id]or 0)+amount end
 t.wallMax=cfg.hp or 0
 effect(S,isNew and "build"or "upgrade",t.x,t.z,nil,nil,kind,t.id,2,1.2)
end
local function sellNow(S,t)
 addIncome(S,math.floor(t.invested*.65))
 if t.type=="economy"then S.economyWaveSpent=math.max(S.economyWaveSpent or 0,t.waveIncome or 0);S.economyKillSpent=math.max(S.economyKillSpent or 0,t.killIncome or 0)end
 if t.type=="barrier"then S.wallCooldowns=S.wallCooldowns or {};S.wallCooldowns[t.id]=S.t+12 end
 S.towers[t.id]=nil;S.saleVote=nil;effect(S,"coin",t.x,t.z,nil,nil,"economy",nil,1,.6)
end
function Action(S,id,a)
 local p=S.players[id];if not p or not active(p)then return false,"当前为观战席"end
 if type(a)~="table"or type(a.kind)~="string"then return false,"无效操作"end
 local k=a.kind
 if k=="start"or k=="rematch"then if S.phase~="LOBBY"and S.phase~="RESULT"then return false,"本局已经开始"end;startRound(S);return true
 elseif k=="beginChallenge"then
  if S.phase~="RANKING"then return false,"挑战已经开始"end
  selectMap(S,"forest");return true
 elseif k=="continueEndless"then
  if S.phase~="MAIN_CLEAR"then return false,"请先完成主线"end
  S.endless=true;S.result=nil;S.phase="INTERMISSION";S.deadline=S.t+C.intermission
  for _,member in pairs(S.players)do member.ready=false;member.attackHeld=false end
  return true
 elseif k=="finishChallenge"then
  if S.phase~="MAIN_CLEAR"then return false,"当前不能结算"end
  S.phase="RESULT";return true
 elseif k=="loadout"then if S.phase~="LOBBY"and S.phase~="RANKING"and S.phase~="PREPARE"and S.phase~="INTERMISSION"then return false,"波间可以切换套件"end;local v=a.value;if not C.hero[v]then return false,"无效套件"end;local ratio=p.hp/p.maxHp;p.loadout=v;p.giantUntil=0;p.attackHeld=false;p.actionKind=nil;p.actionUntil=0;p.castUntil=0;p.lockedEnemy=nil;p.motion=nil;refreshHero(p);p.hp=p.maxHp*ratio;return true
 elseif k=="ready"then if S.phase~="PREPARE"and S.phase~="INTERMISSION"then return false,"无需准备"end;p.ready=true;return true
 elseif k=="selectSlot"then local n=tonumber(a.slot);if not S.layout or not n or n%1~=0 or not S.layout.slots[n]then return false,"塔位不存在"end;p.selectedSlot=n;return true
 elseif k=="attackHold"then p.attackHeld=a.value==true and S.phase=="WAVE_ACTIVE" and p.hp>0;return true
 elseif k=="attack"or k=="skill1"or k=="skill2"or k=="dash"then return heroAttack(S,p,k)
 elseif k=="growth"then if p.growthPoints<=0 then return false,"暂无成长点"end;local field=({damage="damageUp",health="healthUp",cooldown="cooldownUp"})[a.choice];if not field then return false,"无效成长"end;local ratio=p.hp/p.maxHp;p[field]=p[field]+1;p.growthPoints=p.growthPoints-1;refreshHero(p);p.hp=p.maxHp*ratio;return true
 elseif k=="ping"then if (p.pingCd or 0)>S.t then return false,"标记稍后再发"end;p.pingCd=S.t+2;S.pings[#S.pings+1]={owner=id,value=a.value or "守这里",x=p.x,z=p.z,untilTime=S.t+5};effect(S,"ping",p.x,p.z,nil,nil,a.value,id,2,3);return true
 elseif k=="revive"then if p.hp<=0 then return false,"等待复起"end;for _,other in pairs(S.players)do if active(other)and other.hp<=0 and dist(p,other)<2.7 then p.revive={target=other.id,t0=S.t,hitAt=p.hitAt};return true end end;return false,"靠近倒地队友后援助"
 end
 if S.phase~="PREPARE"and S.phase~="INTERMISSION"and S.phase~="WAVE_ACTIVE"then return false,"当前不能建设"end
 if not S.layout then return false,"地图尚未就绪"end
 local slotId=tonumber(a.slot)or p.selectedSlot;local slot=S.layout.slots[slotId];if not slot then return false,"先选择塔位"end
 local t=S.towers[slotId]
 if k=="build"then
  local kind=a.tower;if not C.towers[kind]then return false,"未知防御塔"end
  if t then return false,"塔位已经占用"end
  local quota=GetBuildQuota(S,id)
  if not quota.allowed then return false,quota.reason or "已用完本人的建塔名额"end
  if not S.layout.anyTowerSlot and slot.economy~=(kind=="economy")and (slot.economy or kind=="economy")then return false,slot.economy and "这里是团队经济位"or "经济塔建在绿色团队位"end
  if kind=="economy"then for _,x in pairs(S.towers)do if x.type=="economy"then return false,"全队只能建一座经济塔"end end end
  local cost=C.towers[kind][1].cost
  if available(S,p)<cost then return false,"金币不足，还差"..math.ceil(cost-available(S,p))end
  applyBuild(S,p,slotId,kind,1,nil,{[id]=cost})
  local built=S.towers[slotId];if kind=="economy"then built.waveIncome=S.economyWaveSpent or 0;built.killIncome=S.economyKillSpent or 0 elseif kind=="barrier"then built.cd=math.max(built.cd,S.wallCooldowns and S.wallCooldowns[slotId]or 0)end;return true
 elseif k=="upgrade"then
  if not t then return false,"先建造防御塔"end
  if t.tier==4 then return false,"已经是最高等级"end
  S.saleVote=nil
  local tier=t.tier+1;local branch=tier==4 and a.branch or nil;if tier==4 and branch~="a"and branch~="b"then return false,"选择终阶专精"end
  local cfg=C.towers[t.type][tier==4 and branch or tier]
  if available(S,p)<cfg.cost then return false,"升级金币不足"end
  applyBuild(S,p,slotId,t.type,tier,branch,{[id]=cfg.cost});return true
 elseif k=="contribute"then
  return false,"使用团队金币，无需资助"
 elseif k=="sell"then
  if not t then return false,"这里还没有塔"end
  if #listPlayers(S)<=1 then sellNow(S,t);return true end
  local vote=S.saleVote
  if vote and vote.slot==slotId and vote.expires>S.t then
   if vote.requester==id then return false,"等待队友确认拆塔"end
   sellNow(S,t);return true
  end
  S.nextEvent=S.nextEvent+1
  S.saleVote={id=S.nextEvent,slot=slotId,requester=id,expires=S.t+15}
  return true
 end
 return false,"未识别的操作"
end

local function enemyStep(S,e,dt,wallUse)
 local cfg=C.enemies[e.type]
 if e.hp<=0 then return end
 -- Route progress is authoritative. A proximity sphere can capture enemies
 -- downstream and on an adjacent bend; use a swept stop line instead.
 local speed=cfg.speed*((e.slowUntil>S.t)and(1-e.slow)or 1)
 local canMove=e.rootUntil<=S.t and not(e.cast and e.cast.untilTime>S.t)
 local nextD=e.d+(canMove and speed*dt or 0)
 local barrier,stopD=nil,nil
 for _,t in pairs(S.towers)do
  if t.type=="barrier"and (t.wallUntil or 0)>S.t and (t.wallHp or 0)>0 and t.route==e.route and t.wallD and e.d<=t.wallD+.0001 then
   local contact=math.max(0,t.wallD-.65)
   if nextD>=contact and (not barrier or t.wallD<barrier.wallD or (t.wallD==barrier.wallD and t.id<barrier.id))then barrier=t;stopD=contact end
  end
 end
 local wall=nil
 if barrier then
  if cfg.boss then
   barrier.overload=barrier.overload or S.t+2
   if S.t>=barrier.overload then breakWall(S,barrier,true);barrier=nil else wall=barrier end
  elseif (wallUse[barrier.id]or 0)+(cfg.weight or 1)<=stats(barrier).capacity then
   wall=barrier;wallUse[barrier.id]=(wallUse[barrier.id]or 0)+(cfg.weight or 1)
  end
  if barrier and canMove then
   -- Never pull an enemy backwards. Clip only the movement that crosses the
   -- front face; overflow waits here instead of walking through a full wall.
   e.d=math.max(e.d,math.min(nextD,stopD))
   e.x,e.z,e.angle=L.PointAt(S.layout.routes[e.route],e.d)
  end
 end
 local hero=nil
 for _,p in ipairs(listPlayers(S))do if p.hp>0 and dist(p,e)<(cfg.range or 1.35)then if not hero or dist(p,e)<dist(hero,e)then hero=p end end end
 if e.rootUntil>S.t then return end
 if e.cast and e.cast.untilTime>S.t then return end
 if cfg.boss then
  local phase=e.hp/e.maxHp>.65 and 1 or (e.hp/e.maxHp>.3 and 2 or 3)
  if phase~=e.phase then e.phase=phase;effect(S,"warning",e.x,e.z,nil,nil,"boss",e.id,5,1.1)end
 end
 if e.cd<=S.t and (wall or hero or e.type=="healer")then
  local x,z,radius=e.x,e.z,cfg.boss and (e.phase==2 and 2.8 or 2.2) or (e.type=="guard"and 2.4 or 1.5)
  if wall then x,z=wall.wallX,wall.wallZ elseif hero then x,z=hero.x,hero.z end
  local windup=cfg.boss and e.phase==2 and 1.5 or (cfg.windup or .35);e.attackAt=S.t;e.cd=S.t+cfg.interval/(cfg.boss and e.phase==3 and 1.15 or 1);e.cast={x=x,z=z,radius=radius,untilTime=S.t+windup}
  effect(S,"warning",x,z,nil,nil,e.type,e.id,radius,windup)
  if e.type=="healer"then delayed(S,{kind="heal",enemy=e.id,due=S.t+windup})
  else local damage=cfg.damage*enemyWaveScale(S.wave,cfg.boss,true);if wall and e.type=="breaker"then damage=damage*3 end
   delayed(S,{kind=(e.type=="ranged"or e.type=="caster")and "enemyLaunch"or "enemyHit",enemy=e.id,due=S.t+windup,x=x,z=z,radius=radius,damage=damage*(cfg.boss and .7 or 1),magic=e.type=="caster" or (cfg.boss and e.phase==2),wall=wall and wall.id})
  end
  return
 end
 if barrier then return end
 -- Heroes may intercept briefly, but enemies cannot be pulled away from their route.
 if hero and not cfg.boss and e.type~="runner"then e.engageUntil=e.engageUntil or S.t+2;if S.t<e.engageUntil then return end else e.engageUntil=nil end
 e.d=e.d+speed*dt
 local r=S.layout.routes[e.route];e.x,e.z,e.angle=L.PointAt(r,e.d)
 if e.d>=r.length then e.hp=0;e.deadAt=S.t;e.escaped=true;e.cast=nil;S.core=math.max(0,S.core-cfg.leak);effect(S,"core-hit",S.layout.core.x,S.layout.core.z,nil,nil,e.type,e.id,3,.7)end
end
function Step(S,dt)
 dt=clamp(dt,0,.1);S.t=S.t+dt
 for i=#S.effects,1,-1 do local e=S.effects[i];if S.t>e.t0+math.max(3,e.duration or 0)then table.remove(S.effects,i)end end
 for i=#S.pings,1,-1 do if S.pings[i].untilTime<S.t then table.remove(S.pings,i)end end
 if S.economyQuote and S.economyQuote.expires<=S.t then S.economyQuote=nil end
 if S.saleVote and S.saleVote.expires<=S.t then S.saleVote=nil end
 if S.layout and (S.phase=="PREPARE" or S.phase=="INTERMISSION" or S.phase=="WAVE_ACTIVE")then
 -- Paused phase time is excluded even if a downed player temporarily disconnects.
 if S.phase~="WAVE_ACTIVE" then
  for _,p in pairs(S.players)do
   if p.hp<=0 and (p.downUntil or 0)>0 then p.downUntil=p.downUntil+dt end
  end
 end
 for _,p in ipairs(listPlayers(S))do
  if S.phase=="WAVE_ACTIVE" and p.hp<=0 and p.downUntil>0 and p.downUntil<=S.t then p.hp=p.maxHp*.5;p.downUntil=0;p.immuneUntil=S.t+2;p.teleport={x=S.layout.spawn.x,z=S.layout.spawn.z,id=S.nextEvent+1};effect(S,"revive",S.layout.spawn.x,S.layout.spawn.z,nil,nil,nil,p.id)
  elseif S.phase=="WAVE_ACTIVE" and p.hp>0 and p.attackHeld and p.cooldowns.attack<=S.t then heroAttack(S,p,"attack")end
  if p.revive and S.phase~="WAVE_ACTIVE" then p.revive.t0=p.revive.t0+dt end
  if p.revive then local target=S.players[p.revive.target]
   if not target or target.hp>0 or p.hp<=0 or dist(p,target)>2.7 or p.hitAt~=p.revive.hitAt then p.revive=nil
   elseif S.phase=="WAVE_ACTIVE" and S.t-p.revive.t0>=2 then target.hp=target.maxHp*.35;target.downUntil=0;target.immuneUntil=S.t+.75;p.contribution.support=p.contribution.support+1;effect(S,"revive",target.x,target.z,nil,nil,nil,target.id);p.revive=nil end
  end
 end
 end
 if S.phase=="RANKING"or S.phase=="MAIN_CLEAR"then return end
 if S.phase=="PREPARE"or S.phase=="INTERMISSION"then if S.t>=S.deadline or readyAll(S)then beginWave(S)end;return end
 if S.phase~="WAVE_ACTIVE"then return end
 while S.spawnQueue[1]and S.spawnQueue[1].at<=S.t and countAlive(S)<C.maxEnemies do local q=table.remove(S.spawnQueue,1);spawnEnemy(S,q.type,q.route,q.d,q.threat)end
 local live=countAlive(S);local validIncome=#S.spawnQueue>0 or live>=2
 for _,e in pairs(S.enemies)do if e.type=="boss"and alive(e)then validIncome=true end end
 for _,t in pairs(S.towers)do
  local cfg=stats(t)
  if t.type=="economy"then
   if validIncome then t.incomeTimer=(t.incomeTimer or 0)+dt;if t.incomeTimer>=5 then t.incomeTimer=t.incomeTimer-5;local n=math.max(0,math.min(cfg.income,cfg.cap-(S.economyWaveSpent or 0)));if n>0 then S.economyWaveSpent=(S.economyWaveSpent or 0)+n;t.waveIncome=S.economyWaveSpent;addIncome(S,n);effect(S,"coin",t.x,t.z,nil,nil,"economy",t.id,1,.5)end end end
  elseif t.type=="barrier"then
   if (t.wallUntil or 0)>0 then if t.wallUntil<=S.t then breakWall(S,t,false)end
   elseif (t.cd or 0)<=S.t and #targets(S,t.wallX,t.wallZ,5)>0 then t.wallHp=cfg.hp;t.wallMax=cfg.hp;t.wallUntil=S.t+cfg.duration;t.reserveUsed=false;t.overload=nil;effect(S,"shot",t.wallX,t.wallZ,nil,nil,"barrier",t.id,3,.4)end
  else towerAttack(S,t)end
 end
 local wallUse={};local ids={};for id in pairs(S.enemies)do ids[#ids+1]=id end;table.sort(ids,function(a,b)local ea,eb=S.enemies[a],S.enemies[b];if ea.route~=eb.route then return ea.route<eb.route end;if ea.d~=eb.d then return ea.d>eb.d end;return a<b end)
 for _,id in ipairs(ids)do local e=S.enemies[id];if e.deadAt then if S.t-e.deadAt>1.2 then S.enemies[id]=nil end else enemyStep(S,e,dt,wallUse)end end
 for i=#S.pending,1,-1 do local a=S.pending[i];if a.due<=S.t then table.remove(S.pending,i);if not(a.cancelOnDeath and S.players[a.owner]and S.players[a.owner].hp<=0)then resolvePending(S,a)end end end
 for i=#(S.zones or {}),1,-1 do local z=S.zones[i];if S.t>=z.untilTime then table.remove(S.zones,i)elseif z.kind=="ward" and S.t>=z.nextTick then
   z.nextTick=S.t+.5
   for _,e in ipairs(targets(S,z.x,z.z,z.radius))do damageEnemy(S,e,z.damage or 12,true,z.owner,true,"ward")end
  elseif S.t>=z.nextTick then z.nextTick=S.t+.5;local es=targets(S,z.x,z.z,z.radius);for j=1,math.min(5,#es)do local e=es[j];if z.kind=="burn"then if (e.burnNext or 0)<=S.t then e.burnNext=S.t+.49;e.burnUntil=z.untilTime;damageEnemy(S,e,z.damage,true,z.owner,false)end else slowEnemy(S,e,z.slow,.7)end end;effect(S,z.kind=="burn"and"burn"or"field",z.x,z.z,nil,nil,z.kind,z.owner,z.radius,.6)end end
 if S.core<=0 then S.phase="RESULT";S.result={won=false,title="晶核失守，再来一局！",waves=math.max(0,S.wave-1),core=0};S.pending={};effect(S,"defeat",S.layout.core.x,S.layout.core.z);return end
 if #S.spawnQueue==0 and countAlive(S)==0 then finishWave(S)end
end
function GetAvailableGold(S,id)local p=S.players[id];return p and available(S,p)or 0 end
function Debug(S,kind,arg)
 if kind=="gold"then S.teamGold=arg or 10000
 elseif kind=="ready"then S.deadline=S.t
 elseif kind=="clear"then local ids={};for id,e in pairs(S.enemies)do if alive(e)then ids[#ids+1]=id end end;for _,id in ipairs(ids)do damageEnemy(S,S.enemies[id],10000000,true,nil,false)end
 elseif kind=="spawn"then if type(arg)=="table"then return spawnEnemy(S,arg.type or "basic",arg.route or 1,arg.d or 0)end;return spawnEnemy(S,arg or"basic",1,0)
 elseif kind=="damage"then local e=S.enemies[arg.id];return damageEnemy(S,e,arg.amount,arg.magic,arg.owner,false)
 elseif kind=="root"then rootEnemy(S,S.enemies[arg],1.4)
 elseif kind=="hurtHero"then local p=S.players[arg.id];damageHero(S,p,arg.amount,false)
 end
 return true
end
-- Presentation-only motion curve; the original 0.20s immunity is never extended.
function MotionProgress(m,t)
 if not m then return 1 end
 local start=m.moveAt or m.t0
 return clamp((t-start)/math.max(.001,m.ends-start),0,1)
end
