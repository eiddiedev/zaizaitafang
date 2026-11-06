---@id 6622c120-0f04-4b66-b0a8-982d7373c250
---@referenceName ms-armory.lua
---@assetRef eyJhc3NldElkIjoibWl4LWNyeXN0YWwtZGVmZW5zZTpoYW1sZXQtdWdjL2FpZ2NfZWRpdG9yL2Rldi91bml0eS9NUzR3TGpBQkFBQUFpWGVTbVJUZzVIekJKb1pRTkE0OEh1eXBoeWkxME4zNmk4QjJpenpZSjNZL21peC1wYXJ0LTRfX3VwbG9hZF91c2gzM3c1Yi5nbGIiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvbWl4LXBhcnQtNF9fdXBsb2FkX3VzaDMzdzViLmdsYiIsInJlZmVyZW5jZU5hbWUiOiJtcy1hcm1vcnkubHVhIn0
-- 渲染防御塔、英雄武器与可发布的网格战斗反馈；所有伤害和金币由主控结算。
---@displayName 防御塔与战斗反馈
local U = CS.UnityEngine
local RuntimeScope = require("official.core.runtime_scope")
local Logger = require("official.core.logger")
local logger = Logger.create("armory-view")
local scope, scopeReason = RuntimeScope.from(self)
local resourceRoot = scope and scope:GetResourceRoot() or nil
local V={templates={},towers={},weapons={},fx={},pool={},persistent={},seen={},round=nil,root=nil,entry=nil,started=false,primed=false,sounds={},soundAt=-1,soundCount=0,nextActors=0,actors={},counter=0}
local FAMILIES={"crossbow","prism","mortar","slow","barrier","economy"}
local STAGES={"1","2","3","a","b"}
local COLORS={crossbow={1,.75,.3},prism={.8,.4,1},mortar={1,.48,.16},slow={.35,.9,.88},barrier={.35,.6,1},economy={.45,1,.55},warning={1,.23,.26},heal={.4,1,.65},physical={1,.92,.65},ranged={1,.63,.25},caster={.75,.35,1},boss={1,.22,.18},healer={.3,1,.6}}
local Sfx = {}
function Sfx.find(go, name)
  local t = go ~= nil and go.transform or nil
  while t ~= nil do
    local node = t:Find("RuntimeAudio/" .. name)
    if node ~= nil then return node end
    t = t.parent
  end
  return nil
end
function Sfx.play(go, name)
  return pcall(function()
    local AudioSource = typeof(CS.UnityEngine.AudioSource)
    local node = Sfx.find(go, name)
    if not node and V.pack then
     node=Sfx.find(V.pack,name)
     if not node then
      local nodes=V.pack:GetComponentsInChildren(typeof(CS.UnityEngine.Transform),true)
      for i=0,nodes.Length-1 do if nodes[i].name==name then node=nodes[i];break end end
     end
    end
    if not node then return false end
    local source=node:GetComponent(AudioSource)
    if not source or not source.clip then return false end
    local mixer=V.audioSource or node.parent:GetComponent(AudioSource) or source
    mixer.enabled=true
    mixer.volume=V.volume or .8
    mixer:PlayOneShot(source.clip,1)
    return true
  end)
end
function Sfx.loop(go, name, on)
  local ok, source = pcall(function()
    local source = Sfx.find(go, name):GetComponent(typeof(CS.UnityEngine.AudioSource))
    if on and not source.isPlaying then source.enabled = true source:Play()
    elseif not on then source:Stop() end
    return source
  end)
  return ok and source or nil
end
local function ground(x,z)
 local h=scope and scope:GetRuntimeHostScript("runtime-host.lua");return h and h.GroundY(x,z) or 0
end
local padNames={"石制圆坛塔基 (6)","石制圆坛塔基 (7)","石制圆坛塔基 (2)","石制圆坛塔基","石制圆坛塔基 (4)","石制圆坛塔基 (3)","石制圆坛塔基 (5)","石制圆坛塔基 (1)","石制圆坛塔基 (10)","石制圆坛塔基 (8)","石制圆坛塔基 (9)"}
local padTopCache={}
local function towerHeight(id)
 local key=tonumber(id)
 if padTopCache[key]then return padTopCache[key]end
 local pad=key and padNames[key]and U.GameObject.Find(padNames[key])
 if pad and V.root then
  local renderers=pad:GetComponentsInChildren(typeof(U.Renderer),true);local top=-math.huge
  for i=0,renderers.Length-1 do top=math.max(top,renderers[i].bounds.max.y)end
  if top~=-math.huge then
   local y=V.root.transform:InverseTransformPoint(U.Vector3(pad.transform.position.x,top,pad.transform.position.z)).y+.015
   padTopCache[key]=y;return y
  end
 end
 local h=scope and scope:GetRuntimeHostScript("runtime-host.lua");return (h and h.TowerY(id)or 0)+.30
end
local function alive(go)
  if go==nil then return false end
  local ok,t=pcall(function() return go.transform end)
  return ok and t~=nil
end
local function destroy(go) if alive(go) then U.Object.Destroy(go) end end
local function host()
  if not scope then return nil end
  local h=scope:GetRuntimeHostScript("runtime-host.lua")
  if not h or type(h.GetRenderState)~="function" then return nil end
  return h
end
local function vector(x,y,z) return U.Vector3(tonumber(x) or 0,tonumber(y) or 0,tonumber(z) or 0) end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function presentationTime(h,s)
  local t=type(h.GetPresentationTime)=="function" and tonumber(h.GetPresentationTime()) or nil
  return t or tonumber(s.t) or 0
end
-- Audio clips are 2D; filter distant ordinary events without claiming spatial audio.
local function updateAudio(h,arena)
  local settings=type(h.GetLocalSettings)=="function" and h.GetLocalSettings() or nil
  local volume=math.max(0,math.min(1,tonumber(settings and settings.volume) or .8))
  if V.volume~=volume or V.audioSource==nil then
    local ok=pcall(function()
      local audioRoot=resourceRoot.transform:Find("RuntimeAudio")
      if audioRoot then
        local source=audioRoot:GetComponent(typeof(U.AudioSource))
        if source then source.volume=volume V.audioSource=source V.volume=volume end
      end
    end)
    if not ok then V.audioSource=nil end
  end
  V.listenerX=nil V.listenerZ=nil
  pcall(function()
    local actor=CS.DouyinActorService.GetLocalActor()
    if actor then local pos=arena:InverseTransformPoint(actor.position) V.listenerX=pos.x V.listenerZ=pos.z end
  end)
end
local function audible(x,z)
  if V.listenerX==nil or x==nil or z==nil then return true end
  return (x-V.listenerX)^2+(z-V.listenerZ)^2<=2304
end
local function play(name,t,priority)
  local minGap=priority and .25 or .11
  if t-(V.sounds[name] or -100)<minGap then return end
  V.soundTokens=math.min(10,(V.soundTokens or 10)+math.max(0,t-(V.soundTokenAt or t))*32);V.soundTokenAt=t
  if V.soundTokens<1 and not priority then return end
  V.soundTokens=math.max(0,V.soundTokens-1);V.sounds[name]=t
  local ok,played=Sfx.play(resourceRoot,name)
  if not ok or played==false then V.missingSounds=V.missingSounds or {};V.missingSounds[name]=true end
end
-- V2 parts are authored, metre-sized resources. No procedural cylinder/ring geometry.
local V2_LAYOUTS={
 V2_SlashSweep={"Slash","Slash","Slash"},
 V2_ArrowShot={"Arrow","Streak","Streak","Streak"},
 V2_LeafShot={"LeafArrow","Leaf","Leaf","Leaf","Leaf","Leaf","Spark","Spark"},
 V2_OrbShot={"Orb","Spark","Spark","Spark","Spark","Spark"},
 V2_Beam={"Streak","Streak","Streak","Streak","Streak","Streak"},
 V2_Shell={"Cannonball","Flame","Smoke","Smoke"},
 V2_MeteorFall={"Meteor","Flame","Flame","Flame","Smoke","Smoke","Spark","Spark"},
 V2_Blast={"Spark","Flame","Flame","Flame","Flame","Cannonball","Cannonball","Cannonball","Smoke","Smoke","Smoke","Smoke"},
 V2_MeteorBlast={"Rune","Spark","Flame","Flame","Meteor","Meteor","Meteor","Meteor","Smoke","Smoke","Smoke","Smoke","Spark","Spark"},
 V2_LeafHit={"Spark","Leaf","Leaf","Leaf","Leaf","Leaf"},
 V2_MagicHit={"MagicHit","Spark","Spark","Spark","Spark","Spark"},
 V2_SwordHit={"Spark","Spark","Spark","Spark","Spark","Spark","Spark"},
 V2_ArrowHit={"Spark","Spark","Spark","Spark","Spark"},
 V2_MageFocus={"Rune","Spark","Spark","Spark","Spark"},
 V2_MageBurst={"Rune","Spark","Spark","Spark","Spark","Spark","Spark","Spark","Spark"},
 V2_Charge={"Spark","Spark","Spark","Spark","Spark"},
 V2_GiantAwaken={"Spark","Spark","Spark","Spark","Spark","Spark","Spark","Spark"},
 V2_Dash={"Streak","Streak","Streak","Streak","Streak","Streak","Streak"},
 V2_Muzzle={"Flame","Spark","Spark","Smoke","Smoke"},
 V2_Coin={"Spark","Spark","Spark","Spark","Spark"},
 V2_WallHit={"Spark","Spark","Spark","Spark","Spark","Spark"},
 V2_WallBreak={"Spark","Spark","Spark","Spark","Spark","Spark","Spark","Spark"},
 V2_TimeHit={"Rune","Spark","Spark","Spark","Spark"},
 V2_Mark={"Rune","Spark","Spark"},
 V2_WardSigil={"Rune","Spark","Spark","Spark","Spark","Spark","Spark"},
 V2_Embers={"Flame","Flame","Flame","Flame","Flame"},
}
V2_LAYOUTS.V2_GlobalRain={};for i=1,24 do V2_LAYOUTS.V2_GlobalRain[i]="Arrow"end
local function discoverV2()
 if alive(V.pack)then return true end
 local pack=U.GameObject.Find("晶界守卫 战斗表现素材V2")
 if not pack then return false end
 V.pack=pack
 local all=pack:GetComponentsInChildren(typeof(U.Transform),true)
 for i=0,all.Length-1 do
  local tr=all[i];if ({V2_Arrow=true,V2_LeafArrow=true,V2_Cannonball=true,V2_Meteor=true,V2_Leaf=true,V2_Spark=true,V2_Smoke=true,V2_Flame=true,V2_Rune=true,V2_Orb=true,V2_Slash=true,V2_MagicHit=true,V2_Streak=true})[tr.name]and not V.templates[tr.name]then V.templates[tr.name]=tr.gameObject;tr.gameObject:SetActive(false)end
 end
 U.Debug.LogError("VFX_CHECK discovered pack="..tostring(pack.name).." orb="..tostring(V.templates.V2_Orb~=nil).." meteor="..tostring(V.templates.V2_Meteor~=nil))
 return true
end
local function isLocalOwner(owner)
 local h=host();local id=h and h.GetLocalPlayerId and h.GetLocalPlayerId()
 return id~=nil and tostring(id)==tostring(owner)
end
local function visibleAt(x,y,z)
 local cam=U.Camera.main
 if not cam or not alive(V.root)then return true end
 local v=cam:WorldToViewportPoint(V.root.transform:TransformPoint(vector(x,y,z)))
 return v.z>0 and v.x>-.08 and v.x<1.08 and v.y>-.08 and v.y<1.08
end
local function effectPriority(e)
 if e.kind=="warning"or e.kind=="core-hit"or e.kind=="hero-hurt"then return 5 end
 if isLocalOwner(e.owner)and (e.ultKey or e.kind=="meteor-fall"or e.kind=="hero-spin"or e.kind=="hero-pierce"or e.kind=="dash")then return 4 end
 if e.kind=="hit"or e.kind=="impact"or e.kind=="meteor-impact"or e.kind=="mage-burst"then return 3 end
 if e.kind=="global-arrow-rain"or e.kind=="death"or e.kind=="coin"then return 1 end
 return 2
end

local function clone(name,parent)
  local template=V.templates[name]
  if not alive(template) then logger:warnOnce("missing-template","战斗表现模板缺失",name) return nil end
  local go=U.Object.Instantiate(template)
  go.name="View_"..name
  go.transform:SetParent(parent,false)
  go.transform.localPosition=vector(0,0,0)
  go.transform.localRotation=U.Quaternion.identity
  go.transform.localScale=vector(1,1,1)
  go:SetActive(true)
  return go
end
-- Compound bursts use authored meshes; no editor-only particle dependency on mobile.
local function compoundFx(name)
 if V2_LAYOUTS[name] then
  local go=U.GameObject(name);go.transform:SetParent(V.root.transform,false)
  local pieces,names={},{}
  for _,partName in ipairs(V2_LAYOUTS[name])do
   local part=clone("V2_"..partName,go.transform)
   if part then pieces[#pieces+1]=part.transform;names[#names+1]=partName end
  end
  if #pieces==0 then destroy(go);return nil end
  return go,pieces,names
 end
 local count=({FX_ImpactBurst=7,FX_MuzzleBurst=7,FX_BuildBurst=9,FX_CoreShatter=9,FX_SlashRibbon=9,FX_DashStreak=5,FX_ArcBolt=6,FX_HealRise=7,FX_GroundWarning=4,FX_ArrowRain=12,FX_MeteorFall=9,FX_Blink=8,FX_WardSigil=60,FX_GlobalRain=72})[name]
 if not count then return nil end
 local go=U.GameObject(name);go.transform:SetParent(V.root.transform,false)
 local pieces={}
 for i=1,count do
  local mesh=(name=="FX_ArrowRain" or name=="FX_GlobalRain") and "FX_Bolt" or ((name=="FX_CoreShatter" or name=="FX_BuildBurst" or name=="FX_MeteorFall")and "FX_Crystal" or "FX_Spark")
  local part=clone(mesh,go.transform)
  if part then pieces[#pieces+1]=part.transform end
 end
 return go,pieces
end
local function configureAtlasMaterial(m,partName)
 -- Preserve the Douyin importer texture binding (_BaseTex). Billboard cards
 -- must be double-sided: imported glTF DoubleSide is not reliable on mobile.
 if partName~="Arrow"and partName~="LeafArrow"and partName~="Cannonball"and partName~="Meteor"then
  for _,property in ipairs({"_CullMode","_Cull_Mode1","_Cull_Mode","_Zwrite"})do
   if m:HasProperty(property)then m:SetFloat(property,0)end
  end
 end
end
local function newFx(name)
  local b=V.pool[name]
  local f=b and table.remove(b) or nil
  if f and not alive(f.go) then f=nil end
  if not f then
    local go,pieces,partNames=compoundFx(name)
    if not go then go=clone(name,V.root.transform)end
    if not go then return nil end
    f={go=go,name=name,mats={},pieces=pieces,v2=partNames~=nil,partNames=partNames,partMats={}}
    if partNames then
     for j,part in ipairs(pieces)do
      f.partMats[j]={};local rs=part:GetComponentsInChildren(typeof(U.Renderer),true)
      for i=0,rs.Length-1 do
       local r=rs[i];r.enabled=true;r.shadowCastingMode=U.Rendering.ShadowCastingMode.Off;r.receiveShadows=false
       local mats=r.materials
       for k=0,mats.Length-1 do local m=mats[k];configureAtlasMaterial(m,partNames[j]);local color=m:HasProperty("_BaseColor")and m:GetColor("_BaseColor")or m:HasProperty("_Color")and m:GetColor("_Color")or U.Color(1,1,1,1);f.partMats[j][#f.partMats[j]+1]={mat=m,color=color};f.mats[#f.mats+1]=m end
      end
     end
     local tones={V2_LeafShot={.35,1,.4},V2_LeafHit={.35,1,.4},V2_MagicHit={.7,.65,1},V2_MageBurst={.6,.7,1},V2_TimeHit={.3,1,1},V2_WardSigil={.4,.85,1},V2_Coin={1,.8,.3}}
     local color=tones[name]
     if color then for j,entries in ipairs(f.partMats)do if partNames[j]=="Spark"then for _,entry in ipairs(entries)do entry.color=U.Color(color[1],color[2],color[3],entry.color.a)end end end end
    end
    local renderers=go:GetComponentsInChildren(typeof(U.MeshRenderer),true)
    if not f.v2 then for i=0,renderers.Length-1 do local material=renderers[i].material if material then table.insert(f.mats,material) end end end
  end
  f.go:SetActive(true) f.go.transform:SetParent(V.root.transform,false)
  f.go.transform.localPosition=vector(0,0,0) f.go.transform.localRotation=U.Quaternion.identity f.go.transform.localScale=vector(1,1,1)
  return f
end
local function disposeFx(f)
  if not f then return end
  for _,mat in ipairs(f.mats or {}) do if mat~=nil then U.Object.Destroy(mat) end end
  destroy(f.go)
end
local function releaseFx(f)
  if not f then return end
  if alive(f.go) then
    f.go:SetActive(false) f.e=nil;f.zoneX=nil;f.zoneZ=nil
    V.pool[f.name]=V.pool[f.name] or {}
    if #V.pool[f.name]<(f.v2 and 4 or 12) then table.insert(V.pool[f.name],f) else disposeFx(f) end
  end
end
local function tint(f,color)
  if not f or f.v2 then return end
  local c=color or COLORS.physical local col=U.Color(c[1],c[2],c[3],f.name=="FX_Wall" and .24 or 1)
  for _,mat in ipairs(f.mats or {}) do
    mat.color=col
    if mat:HasProperty("_BaseColor") then mat:SetColor("_BaseColor",col) end
    if mat:HasProperty("_EmissionColor") then mat:SetColor("_EmissionColor",U.Color(c[1]*.4,c[2]*.4,c[3]*.4,1)) mat:EnableKeyword("_EMISSION") end
  end
end
local hiddenHeroes={}
local function restoreHeroRenderers(key)
 local saved=hiddenHeroes[key];if not saved then return end
 for renderer,enabled in pairs(saved.renderers)do pcall(function()renderer.enabled=enabled end)end
 hiddenHeroes[key]=nil
end
local function setHeroHidden(key,actor,hidden)
 local saved=hiddenHeroes[key]
 if saved and (not hidden or saved.actor~=actor)then restoreHeroRenderers(key);saved=nil end
 if not hidden or not actor then return end
 if not saved then saved={actor=actor,renderers={}};hiddenHeroes[key]=saved end
 -- Keep the native actor/controller active; hide only its visual renderers.
 pcall(function()
  local renderers=actor.gameObject:GetComponentsInChildren(typeof(U.Renderer),true)
  for i=0,renderers.Length-1 do
   local r=renderers[i]
   if saved.renderers[r]==nil then saved.renderers[r]=r.enabled end
   r.enabled=false
  end
 end)
end
local hurtFlashes={}
local function restoreHurt(key)
 local f=hurtFlashes[key];if not f then return end
 for _,r in ipairs(f.renderers)do pcall(function()
  if r.originalMaterials then r.renderer.sharedMaterials=r.originalMaterials end
  r.renderer:SetPropertyBlock(r.original)
 end)end
 if f.material then U.Object.Destroy(f.material)end
 hurtFlashes[key]=nil
end
local function updateHurt(key,actor,p,t)
 local f=hurtFlashes[key]
 -- Latch newly received hits in presentation time; a delayed snapshot must not skip the flash.
 V.hurtSeen=V.hurtSeen or {}
 local fresh=p.hitAt and V.hurtSeen[key]~=p.hitAt and t-p.hitAt>=0 and t-p.hitAt<1
 if fresh then V.hurtSeen[key]=p.hitAt end
 if f and (f.actor~=actor or p.hp<=0 or U.Time.time>=f.untilTime)then restoreHurt(key);f=nil end
 if fresh and f then f.untilTime=U.Time.time+.3 end
 if not actor or p.hp<=0 or not fresh or f then return end
 f={actor=actor,renderers={},untilTime=U.Time.time+.3};hurtFlashes[key]=f
 local shader=U.Shader.Find("Universal Render Pipeline/Unlit")or U.Shader.Find("Unlit/Color")
 if shader then
  f.material=U.Material(shader)
  f.material:SetColor("_BaseColor",U.Color(1,.08,.08,1));f.material:SetColor("_Color",U.Color(1,.08,.08,1))
 end
 local rs=actor.gameObject:GetComponentsInChildren(typeof(U.Renderer),true)
 for i=0,rs.Length-1 do
  local r=rs[i]
  if r:GetComponent(typeof(U.SkinnedMeshRenderer))or r:GetComponent(typeof(U.MeshRenderer))then
   pcall(function()
    local original=U.MaterialPropertyBlock();r:GetPropertyBlock(original)
    local entry={renderer=r,original=original};f.renderers[#f.renderers+1]=entry
    if f.material then
     entry.originalMaterials=r.sharedMaterials
     local replacement=r.sharedMaterials
     for j=0,replacement.Length-1 do replacement[j]=f.material end
     r.sharedMaterials=replacement
    end
    local flash=U.MaterialPropertyBlock()
    flash:SetColor("_BaseColor",U.Color(1,.08,.08,1));flash:SetColor("_Color",U.Color(1,.08,.08,1))
    r:SetPropertyBlock(flash)
   end)
  end
 end
end
local function playHeroHurt(t)
 if t-(V.hurtSoundAt or -100)<.12 then return end
 V.hurtSoundAt=t
 pcall(function()
  if not V.hurtAudio then
   local go=U.GameObject("HeroHurtAudio");go.transform:SetParent(V.root.transform,false)
   V.hurtAudio=go:AddComponent(typeof(U.AudioSource));V.hurtAudio.spatialBlend=0;V.hurtAudio.playOnAwake=false
  end
  local node=Sfx.find(resourceRoot,"hurt")or Sfx.find(resourceRoot,"hit-physical")
  local source=node and node:GetComponent(typeof(U.AudioSource))
  if source and source.clip then V.hurtAudio.volume=V.volume or .8;V.hurtAudio:PlayOneShot(source.clip,1)end
 end)
end

local function clearOutfits()
 for _,entry in pairs(V.outfits or {})do pcall(entry.driver.Unequip,entry.actor)end
 V.outfits={}
end
local function clear()
  clearOutfits()
  for key in pairs(hurtFlashes)do restoreHurt(key)end
  for key in pairs(hiddenHeroes)do restoreHeroRenderers(key)end
  for _,v in pairs(V.towers) do destroy(v.go) end
  for _,v in pairs(V.weapons) do if v.driver and v.actor then pcall(v.driver.Unequip,v.actor)else destroy(v.go)end end
  for _,f in ipairs(V.fx) do disposeFx(f) end
  for _,f in pairs(V.persistent) do disposeFx(f) end
  for _,bucket in pairs(V.pool) do for _,f in ipairs(bucket) do disposeFx(f) end end
  if V.hurtAudio then destroy(V.hurtAudio.gameObject)end
  V.hurtAudio=nil;V.hurtSeen={};V.hurtSoundAt=nil
  V.towers={} V.weapons={} V.fx={} V.pool={} V.persistent={} V.seen={} V.sounds={} V.primed=false V.soundAt=-1 V.soundCount=0
end
local authoredTowerNames={
 ["1"]={prism="棱晶塔一阶",slow="时缓信标一阶",crossbow="连弩塔一阶",mortar="震爆炮台一阶",barrier="晶壁发生器一阶",economy="辉晶采集器一阶"},
 ["2"]={prism="棱晶塔二阶",slow="时缓信标二阶",crossbow="连弩塔二阶",mortar="震爆炮台二阶",barrier="晶壁发生器二阶",economy="辉晶采集器二阶"},
 ["3"]={prism="棱晶塔三阶",slow="时缓信标三阶",crossbow="连弩塔三阶",mortar="震爆炮台三阶",barrier="晶壁发生器三阶",economy="辉晶采集器三阶"},
 ["a"]={prism="棱晶塔四阶·穿透光束",slow="时缓信标四阶A",crossbow="连弩塔四阶·极速连射",mortar="震爆炮台四阶A（二次爆破专精）",barrier="晶壁发生器四阶A（坚韧护壁专精）",economy="辉晶采集器四阶A（稳定产出专精）"},
 ["b"]={prism="棱晶塔四阶·蚀甲聚焦",slow="时缓信标四阶B",crossbow="连弩塔四阶·标记协击",mortar="震爆炮台四阶B（燃烧弹专精）",barrier="晶壁发生器四阶B（破壁击退专精）",economy="辉晶采集器四阶B（击杀收益专精）"},
}
local function cloneAuthoredTower(family,stage,parent)
 local names=authoredTowerNames[stage]; local name=names and names[family]; local source=name and U.GameObject.Find(name)
 local filter=source and source:GetComponentInChildren(typeof(U.MeshFilter),true)
 if not filter or not filter.sharedMesh then return nil end
 local sr=filter.gameObject:GetComponent(typeof(U.MeshRenderer)); if not sr then return nil end
 local go=U.GameObject("View_Tower_"..family);go.transform:SetParent(parent,false)
 local body=U.GameObject("Body");body.transform:SetParent(go.transform,false)
 body:AddComponent(typeof(U.MeshFilter)).sharedMesh=filter.sharedMesh
 body:AddComponent(typeof(U.MeshRenderer)).sharedMaterials=sr.sharedMaterials
 local bounds=filter.sharedMesh.bounds;local k=(family=="prism"and 3.2 or 2.5)/math.max(.01,bounds.size.y)
 body.transform.localScale=U.Vector3(k,k,k)
 local mechanical=family=="crossbow" or family=="mortar"
 -- glTF forward is reversed when imported into Unity's coordinate system.
 -- Turn only the visible mesh; the parent and muzzle keep aiming at the target.
 if mechanical then
  body.transform.localRotation=U.Quaternion.Euler(0,180,0)
  body.transform.localPosition=U.Vector3(bounds.center.x*k,-bounds.min.y*k,bounds.center.z*k)
 else
  body.transform.localPosition=U.Vector3(-bounds.center.x*k,-bounds.min.y*k,-bounds.center.z*k)
 end
 -- Models are one mesh, so use a stable ground pivot for whole-body reaction.
 local muzzle=U.GameObject("Muzzle");muzzle.transform:SetParent(go.transform,false)
 muzzle.transform.localPosition=family=="mortar" and vector(0,1.95,1.15) or (family=="crossbow" and vector(0,2.25,1.0) or vector(0,family=="prism"and 3.0 or 2.3,0))
 return go
end
local function ensureTower(key,tw)
  local stage=(tonumber(tw.tier) or 1)>=4 and (tw.branch=="b" and "b" or "a") or tostring(tw.tier or 1)
  local family=tw.type or "crossbow"
  local sig=family.."_"..stage
  local v=V.towers[key]
  if v and v.sig~=sig then destroy(v.go) V.towers[key]=nil v=nil end
  if not v then
    local go=cloneAuthoredTower(family,stage,V.root.transform)
    if not go then go=clone("Tower_"..sig,V.root.transform) end if not go then return nil end
    local turret=go.transform:Find("Turret") local pulse=go.transform:Find("Turret/Pulse") local body=go.transform:Find("Body") local muzzle=go.transform:Find("Turret/Muzzle") or go.transform:Find("Muzzle")
    v={go=go,sig=sig,family=family,stage=stage,body=body,turret=turret,pulse=pulse,muzzle=muzzle,lastAttack=-100,attackFloor=tonumber(tw.attackAt) or -100,rootAt=U.Time.time}
    if turret then local p=turret.localPosition v.base={x=p.x,y=p.y,z=p.z} end
    V.towers[key]=v
  end
  return v
end
local function updateTowers(s,t)
  local seen={}
  for id,tw in pairs(s.towers or {}) do
    local key=tostring(id) seen[key]=true local v=ensureTower(key,tw)
    if v then
      v.id=tostring(tw.id or id) v.x=tw.x v.z=tw.z
      v.go.transform.localPosition=vector(tw.x,towerHeight(tw.id or id),tw.z)
      local age=t-(tonumber(tw.attackAt) or -100)
      local kick=(tonumber(tw.attackAt) or -100)>v.attackFloor and age>=0 and age<.2 and (1-age/.2) or 0
      if v.turret then
        v.turret.localEulerAngles=vector(0,tw.angle or 0,0)
        v.turret.localPosition=vector(v.base.x,v.base.y,v.base.z-kick*.11)
      end
      if v.body then
        -- Static authored meshes cannot move their weapons independently. Rotate the
        -- whole emplacement to aim and add a restrained recoil around its foot.
        local mechanical=(v.family=="crossbow" or v.family=="mortar")
        local yaw=mechanical and (tonumber(tw.angle) or 0) or 0
        local strength=v.family=="mortar" and 7 or (v.family=="crossbow" and 3 or 1.6)
        local pulse=kick*strength
        v.go.transform.localRotation=U.Quaternion.Euler(-pulse,yaw,0)
      end
      if v.pulse then local q=1+math.sin(t*2.5)*.035+kick*.2 v.pulse.localScale=vector(q,q,q) end
      local elapsed=U.Time.time-v.rootAt local grow=clamp(elapsed/.24,0,1) local pop=1+math.sin(grow*math.pi)*.05
      v.go.transform.localScale=vector(pop*.72,clamp(grow,.06,1)*.72,pop*.72)
    end
  end
  for id,v in pairs(V.towers) do if not seen[id] then destroy(v.go) V.towers[id]=nil end end
end
local function sourcePoint(e,arena,s)
  if e.owner then
    for key,v in pairs(V.towers) do if key==tostring(e.owner) or v.id==tostring(e.owner) then
      if v.muzzle then local p=arena:InverseTransformPoint(v.muzzle.position) return p.x,p.y,p.z end
    end end
    local w=V.weapons[tostring(e.owner)]
    if w and alive(w.go) then local p=arena:InverseTransformPoint(w.muzzle and w.muzzle.position or w.go.transform.position) return p.x,p.y,p.z end
  end
  return tonumber(e.x) or 0,ground(tonumber(e.x) or 0,tonumber(e.z) or 0)+(e.kind=="shot" and COLORS[e.family]~=nil and (e.family=="ranged" or e.family=="caster" or e.family=="boss") and 1.2 or (e.kind=="shot" and 2.1 or .8)),tonumber(e.z) or 0
end
local function effectTemplate(e)
 local k,f=e.kind,e.family
 if k=="global-arrow-rain"then return "V2_GlobalRain"end
 if k=="meteor-fall"then return "V2_MeteorFall"end
 if k=="meteor-impact"then return "V2_MeteorBlast"end
 if k=="giant-awaken"then return "V2_GiantAwaken"end
 if k=="hero-pierce"then return "V2_LeafShot"end
 if k=="hero-ranged"then return "V2_ArrowShot"end
 if k=="hero-magic"then return "V2_OrbShot"end
 if k=="mage-focus"then return "V2_MageFocus"end
 if k=="mage-burst"then return "V2_MageBurst"end
 if k=="hero-charge"then return "V2_Charge"end
 if k=="dash"or k=="attack-approach"then return "V2_Dash"end
 if k=="hero-melee"or k=="hero-spin"or k=="hero-heavy"then return "V2_SlashSweep"end
 if k=="shot"then
  if f=="mortar"then return "V2_Shell"end
  if f=="crossbow"or f=="ranged"then return "V2_ArrowShot"end
  if f=="prism"and e.branch=="a"then return "V2_Beam"end
  if f=="slow"then return "V2_OrbShot"end
  if f=="barrier"then return "V2_Charge"end
  return "V2_OrbShot"
 end
 if k=="hit"then
  if f=="leaf"then return "V2_LeafHit"end
  if f=="arrow"or f=="rain"then return "V2_ArrowHit"end
  if f=="sword"or f=="giant"or f=="spin"or f=="physical"then return "V2_SwordHit"end
  if f=="time"then return "V2_TimeHit"end
  return "V2_MagicHit"
 end
 if k=="impact"then return f=="mortar"and "V2_Blast"or "V2_MagicHit"end
 if k=="wall-hit"then return "V2_WallHit"end
 if k=="wall-break"then return "V2_WallBreak"end
 if k=="coin"then return "V2_Coin"end
 if k=="mark"then return "V2_Mark"end
 if k=="hero-hurt"then return "V2_SwordHit"end
 if k=="heal"or k=="revive"then return "FX_HealRise"end
 if k=="warning"then return "FX_GroundWarning"end
 if k=="build"or k=="upgrade"then return "FX_BuildBurst"end
 if k=="core-hit"then return "FX_CoreShatter"end
 return "FX_ImpactBurst"
end
local function effectSound(e,t)
  if e.kind=="hero-hurt"then playHeroHurt(t);return end
  if not audible(tonumber(e.x),tonumber(e.z)) and not (e.kind=="death" and e.family=="boss") then return end
  if e.kind=="shot" and e.family then
    for _,family in ipairs(FAMILIES) do if family==e.family then play("shoot-"..family,t,false) break end end
  elseif e.kind=="upgrade" or e.kind=="build" then play("upgrade-"..(e.family or "crossbow"),t,true)
  elseif e.kind=="wall-break" then play("wall-break",t,true)
  elseif e.kind=="hero-hurt"or e.kind=="hit" or e.kind=="impact" or e.kind=="core-hit" then play(e.family=="mortar" and "impact" or ((e.family=="prism" or e.family=="slow" or e.family=="caster" or e.family=="beam" or e.family=="corrosion" or e.family=="time" or e.family=="ward" or e.family=="mage-burst") and "hit-magic" or "hit-physical"),t,false)
  elseif e.kind=="death" and e.family=="boss" then play("impact",t,true)
  elseif e.kind=="meteor-impact"then play("hit-physical",t,true)
  elseif e.kind=="global-arrow-rain"then play("shoot-crossbow",t,false)
  elseif e.kind=="hero-melee" or e.kind=="hero-heavy" or e.kind=="hero-spin" or e.kind=="giant-awaken" then play("hit-physical",t,false)
  elseif e.kind=="hero-ranged"or e.kind=="hero-pierce" then play("shoot-crossbow",t,false)
  elseif e.kind=="hero-magic" or e.kind=="mage-burst" then play("shoot-prism",t,false)
  elseif e.kind=="heal" or e.kind=="revive" then play("shoot-economy",t,false)
  end
end
local function attackWindow(e,t)
 local start=tonumber(e.t0)or t
 local duration=math.max(.01,tonumber(e.hitAt)and e.hitAt-start or tonumber(e.duration)or .45)
 if e.kind=="hero-pierce"then return start,.30 end
 local short=e.kind=="shot"or e.kind=="hero-ranged"or e.kind=="hero-magic"or e.kind=="hero-melee"or e.kind=="hit"or e.kind=="impact"
 if short and t-start>=0 and t-start<.65 then
  -- Leave at least 100 ms of visible feedback on a late snapshot. Do not replay
  -- old volleys on join, or alter hitAt/the simulation clock.
  local remaining=math.max(.10,duration-(t-start))
  if remaining>duration then return t,remaining end
  return math.max(start,t+remaining-duration),duration
 end
 return start,duration
end
local function addEffect(e,t,arena,s)
  if e.kind=="damage-number"then return end
  if e.kind=="rain-impact"then return end
  local priority=effectPriority(e)
  local pieces=0;for _,old in ipairs(V.fx)do pieces=pieces+#(old.pieces or {})end
  if #V.fx>=48 or pieces>=280 then
    local victim,lowest=nil,priority
    for i,old in ipairs(V.fx)do if (old.priority or 1)<lowest then victim=i;lowest=old.priority or 1 end end
    if not victim then return end
    releaseFx(table.remove(V.fx,victim))
  end
  local f=newFx(effectTemplate(e)) if not f then return end
  f.priority=priority;f.e=e;f.started,f.duration=attackWindow(e,t)
  f.sx,f.sy,f.sz=sourcePoint(e,arena,s)
  V.trace=V.trace or {};local traceKey=e.kind..":"..tostring(e.family)
  if not V.trace[traceKey]and (e.kind=="shot"or e.kind=="hero-magic"or e.kind=="hero-ranged"or e.kind=="hero-melee")then
   V.trace[traceKey]=true;U.Debug.LogError("VFX_PRIMARY "..traceKey.." parts="..#(f.pieces or {}).." age="..tostring(t-(e.t0 or t)).." life="..f.duration.." source="..f.sx..","..f.sy..","..f.sz)
  end
  local col=((e.kind=="warning" or e.kind=="down" or e.kind=="defeat" or e.kind=="core-hit") and COLORS.warning) or ((e.kind=="heal" or e.kind=="revive" or e.kind=="victory") and COLORS.heal) or COLORS[e.family] or COLORS.physical
  if e.kind=="global-arrow-rain"then col={1,.94,.58}end
  if f.v2 and (e.kind=="dash"or e.kind=="hero-charge")then
   local c=(e.family=="ranged"or e.family=="leaf")and {.35,1,.5}or e.family=="mage"and {.65,.7,1}or {1,.94,.75}
   for _,entries in ipairs(f.partMats)do for _,entry in ipairs(entries)do entry.color=U.Color(c[1],c[2],c[3],entry.color.a)end end
  end
  tint(f,col) table.insert(V.fx,f)
  if t-f.started<.22 then
    -- Small short-lived muzzle flash accompanies projectiles; impact remains a
    -- separate event driven by actual damage, not a second damage calculation.
    if e.kind=="shot" and (e.family=="crossbow" or e.family=="mortar" or e.family=="prism") and #V.fx<27 then
      local flash=newFx("V2_Muzzle")
      if flash then flash.priority=1;flash.e={kind="muzzle",family=e.family,id=e.id,x=f.sx,z=f.sz,tx=e.tx,tz=e.tz};flash.started=f.started;flash.duration=.18;flash.sx=f.sx;flash.sy=f.sy;flash.sz=f.sz;tint(flash,col);table.insert(V.fx,flash) end
    end
  end
end
-- Resolve the luminous side from imported mesh UVs, rather than guessing the
-- glTF -> Unity handedness. The crescent's bright edge is the texture's left.
local function slashTextureYaw(part)
 if V.slashTextureYaw~=nil then return V.slashTextureYaw end
 local ok,yaw=pcall(function()
  local mf=part:GetComponentInChildren(typeof(U.MeshFilter))
  if not mf or not mf.sharedMesh then return nil end
  local vertices,uv=mf.sharedMesh.vertices,mf.sharedMesh.uv
  if vertices.Length<3 or vertices.Length~=uv.Length then return nil end
  local lo,hi=math.huge,-math.huge
  for i=0,uv.Length-1 do lo=math.min(lo,uv[i].x);hi=math.max(hi,uv[i].x)end
  if hi-lo<.001 then return nil end
  local lx,lz,hx,hz,ln,hn=0,0,0,0,0,0
  for i=0,uv.Length-1 do
   local point=part:InverseTransformPoint(mf.transform:TransformPoint(vertices[i]))
   if uv[i].x<(lo+hi)*.5 then lx=lx+point.x;lz=lz+point.z;ln=ln+1
   else hx=hx+point.x;hz=hz+point.z;hn=hn+1 end
  end
  if ln==0 or hn==0 then return nil end
  return -math.deg(math.atan(lx/ln-hx/hn,lz/ln-hz/hn))
 end)
 V.slashTextureYaw=ok and yaw or -90
 U.Debug.LogError("VFX_SLASH textureYaw="..V.slashTextureYaw.." meshCalibrated="..tostring(ok and yaw~=nil))
 return V.slashTextureYaw
end
local function slashPose(e,q,j,textureYaw)
 -- Never aim back from a sword tip that has already passed the enemy.
 local dx,dz=(e.tx or e.x)-(e.x or 0),(e.tz or e.z)-(e.z or 0)
 local yaw=math.deg(math.atan(dx,dz))
 local spin=e.kind=="hero-spin"
 local sweep=spin and -q*360 or 50-100*q
 local rad=e.radius or 1
 local offset=spin and 0 or math.min(.24,rad*.12)
 local size=(rad-offset)*2*(1-(j-1)*.055)
 -- A right-hand swing travels from the wielder's right to left; its afterimage
 -- trails to the right. The spinning skill retains its circular footprint.
 return math.sin(math.rad(yaw))*offset,math.cos(math.rad(yaw))*offset,size,
        yaw+textureYaw+sweep+(j-1)*12
end
local function renderV2(f,e,s,t,q)
 if not f.v2 then return false end
 local tr=f.go.transform;local age=t-f.started
 local x,z=e.x or 0,e.z or 0;local tx,tz=e.tx or x,e.tz or z
 local name=f.name;local rad=e.radius or 1;local fade=math.max(0,1-q)
 local tierBoost=1+math.min(3,math.max(0,(tonumber(e.tier)or 1)-1))*.12
 local target=e.target and s.enemies and s.enemies[e.target]
 if target and name~="V2_Shell" and name~="V2_LeafShot"then tx,tz=target.x,target.z end
 local dx,dz=tx-f.sx,tz-f.sz;local len=math.sqrt(dx*dx+dz*dz)
 local vx,vz=len>.001 and dx/len or 0,len>.001 and dz/len or 1
 local angle=math.deg(math.atan(vx,vz));local y=ground(x,z)
 tr.localPosition=vector(x,y+.65,z);tr.localRotation=U.Quaternion.identity
 local function pose(j,px,py,pz,sx,sy,sz,rx,ry,rz)
  local p=f.pieces[j];p.localPosition=vector(px,py,pz);p.localScale=vector(math.max(.001,sx),math.max(.001,sy),math.max(.001,sz));p.localEulerAngles=vector(rx or 0,ry or 0,rz or 0)
 end
 for j,part in ipairs(f.pieces)do
  local mesh=f.partNames[j];local theta=(j-1)*2.39996+(tonumber(e.id)or 0)*.73
  local sn,cs=math.sin(theta),math.cos(theta)
  local a=fade
  part.gameObject:SetActive(true)
  if name=="V2_SlashSweep"then
   local ox,oz,size,yaw=slashPose(e,q,j,slashTextureYaw(part))
   tr.localPosition=vector(x+ox,y+.7,z+oz)
   pose(j,0,(j-1)*.035,0,size,1,size,0,yaw,0)
   a=math.sin(q*math.pi)*(j==1 and 1 or .28/(j-1))
  elseif name=="V2_ArrowShot"or name=="V2_LeafShot"or name=="V2_OrbShot"or name=="V2_Shell"then
   local lag=j==1 and 0 or (j-1)*.025
   local u=clamp(q-lag,0,1);local arch=name=="V2_Shell"and math.sin(u*math.pi)*math.min(3.4,len*.4)or 0
   tr.localPosition=vector(f.sx+dx*u,f.sy+(ground(tx,tz)+.65-f.sy)*u+arch,f.sz+dz*u)
   -- Each piece has its own world path: root stays at origin to avoid cumulative trail lag.
   local center=tr.localPosition;tr.localPosition=vector(0,0,0)
   local px,py,pz=center.x,center.y,center.z
   if j==1 then
    a=1 -- Solid projectile core stays readable until impact; only its trail fades.
    local size=(name=="V2_Shell"and .40 or name=="V2_OrbShot"and .85 or name=="V2_LeafShot"and 1.7 or 1.1)*tierBoost
    pose(j,px,py,pz,size,size,size,0,angle,0)
    local dy=(ground(tx,tz)+.65-f.sy)+(name=="V2_Shell"and math.cos(u*math.pi)*math.pi*math.min(3.4,len*.4)or 0)
    if name~="V2_OrbShot"then part.localRotation=U.Quaternion.LookRotation(vector(dx,dy,dz))end
   elseif mesh=="Leaf"then
    local spin=theta+t*24;local r=.18+.12*math.sin(q*math.pi)
    pose(j,px+vz*math.cos(spin)*r,py+math.sin(spin)*r,pz-vx*math.cos(spin)*r,1.6,1.6,1.6,math.deg(spin),angle,40)
   elseif mesh=="Smoke"then
    pose(j,px,py,pz,.23+.4*lag,.23+.4*lag,.23+.4*lag,0,0,0);a=.35*(1-q)
   else
    local r=name=="V2_OrbShot"and .22 or .035
    pose(j,px+cs*r,py+sn*r,pz,.18*tierBoost,.18,name=="V2_OrbShot"and .35 or .8,0,angle,0);a=.85
   end
  elseif name=="V2_Beam"then
   tr.localPosition=vector(f.sx,f.sy,f.sz);tr.localRotation=U.Quaternion.LookRotation(vector(dx,ground(tx,tz)+.65-f.sy,dz))
   -- Charges into a line; the bright full-length pulse occurs at the authority impact time.
   local u=clamp(q/.85,0,1);pose(j,cs*.04,sn*.04,len*u*.5,.055,.055,math.max(.01,len*u),0,0,0);a=.35+.65*q
  elseif name=="V2_GlobalRain"then
   tr.localPosition=vector(0,0,0)
   local b=s.layout.bounds;local col,row=(j-1)%6,math.floor((j-1)/6)
   local px=b.minX+(col+.5+.18*sn)*(b.maxX-b.minX)/6
   local pz=b.minZ+(row+.5+.18*cs)*(b.maxZ-b.minZ)/4
   -- Select only on-screen landing points. No hidden-world rain objects consume draw calls.
   if not visibleAt(px,ground(px,pz)+.4,pz)then part.gameObject:SetActive(false)
   else
    local u=clamp((q-(j%3)*.045)/(1-(j%3)*.045),0,1);local height=10*(1-u)
    pose(j,px-height*.28,ground(px,pz)+height+.15,pz+height*.12,1.6,1.6,1.8,75,165,0)
    part.localRotation=U.Quaternion.LookRotation(vector(.28,-1,-.12));a=1
   end
  elseif name=="V2_MeteorFall"then
   local fall=1-q*q;tr.localPosition=vector(x-4*fall,y+.5+15*fall,z+2*fall)
   if j==1 then pose(j,0,0,0,2.2,2.2,2.2,q*130,q*70,15);a=1
   elseif mesh=="Flame"then pose(j,-.15*j,.28*j,.08*j,1.2,2+j*.25,1.2,-15,0,-15);a=.9
   elseif mesh=="Smoke"then pose(j,-.16*j,.34*j,.08*j,1.4,1.4,1.4,0,0,0);a=.35
   else pose(j,sn*.7,cs*.7,0,.16,.16,2.2,0,0,25);a=.9 end
  elseif name=="V2_Dash"then
   local u=clamp((age-.08)/.22,0,1);local ddx,ddz=tx-x,tz-z;local yaw=math.deg(math.atan(ddx,ddz))
   tr.localPosition=vector(x,y+.65,z)
   if age<.08 then
    pose(j,cs*.3*(1-age/.08),-.48,sn*.3*(1-age/.08),.16,.06,.30,0,theta*57,0);a=age/.08
   else
    local trail=math.max(0,u-(j-1)*.09)
    pose(j,ddx*trail,(j%3)*.12-.1,ddz*trail,.10+(j%2)*.05,.12,1.15-(j-1)*.09,0,yaw,0);a=fade
   end
  elseif name=="V2_GiantAwaken"then
   local w=V.weapons[tostring(e.owner)]
   if w and alive(w.go)then
    tr.position=w.go.transform.position;tr.rotation=w.go.transform.rotation
   end
   pose(j,cs*.1,sn*.1,(j-1)*.30+q*.9,.16,.16,.8,0,0,0);a=math.sin(q*math.pi)
  elseif name=="V2_Charge"then
   tr.localPosition=vector(f.sx,f.sy,f.sz)
   local r=(1-q)*.5;pose(j,cs*r,sn*r,.1,.1,.1,.4,0,theta*57,0);a=.5+.5*q
  elseif name=="V2_Muzzle"then
   tr.localPosition=vector(f.sx,f.sy,f.sz);tr.localRotation=U.Quaternion.Euler(0,angle,0)
   if mesh=="Smoke"then pose(j,cs*q*.35,q*.3,q*.6,.3+q*.45,.3+q*.45,.3+q*.45,0,0,0);a=.45*fade
   else pose(j,cs*q*.1,sn*q*.1,.2+q*.5,.35*fade,.35*fade,1.2*fade,0,0,theta*57);a=math.max(0,1-q*2.5)end
  elseif name=="V2_MageFocus"then
   tr.localPosition=vector(tx,ground(tx,tz)+.04,tz)
   local r=rad*(1-q*.75)
   if j==1 then pose(j,0,0,0,r*2,1,r*2,0,q*70,0)else pose(j,cs*r,.1,sn*r,.12,.12,.6,0,-theta*57,0)end;a=q
  elseif name=="V2_Coin"then
   pose(j,cs*(1-q)*.45,1+q*1.2+j*.05,sn*(1-q)*.45,.15*fade,.22*fade,.15*fade,0,q*300,0)
  elseif name=="V2_WallHit"or name=="V2_WallBreak"then
   local r=q*(name=="V2_WallBreak"and rad or .7)
   pose(j,cs*r,sn*.5+q*.3,sn*r,.14*fade,.05,.8*fade,0,theta*57,40)
  else
   -- Material-coded short bursts. Boundary particles stay within the actual damage radius.
   local blast=name=="V2_Blast"or name=="V2_MeteorBlast"or name=="V2_MageBurst"
   local strength=blast and rad or (name=="V2_LeafHit"and .75 or .55)
   local r=strength*math.sin(q*math.pi*.5)*(.45+.55*(j%3)/2)
   if mesh=="Rune"then
    tr.localPosition=vector(x,y+.035,z);pose(j,0,0,0,rad*2,1,rad*2,0,0,0);a=fade*.7
   elseif mesh=="Smoke"then
    local p=clamp((q-.13)/.87,0,1);pose(j,cs*r,.2+p*.6,sn*r,.3+p*rad*.65,.25+p*.5,.3+p*rad*.65,0,0,0);a=.28*math.sin(p*math.pi)
   elseif mesh=="Cannonball"or mesh=="Meteor"then
    local size=(name=="V2_MeteorBlast"and .3 or .12)*fade
    pose(j,cs*r,math.sin(q*math.pi)*1.2-q*.4,sn*r,size,size*.7,size,q*300,j*60,q*120)
   elseif mesh=="Flame"then
    pose(j,cs*r*.6,q*.5,sn*r*.6,rad*.6*fade,rad*.7*fade,rad*.6*fade,0,0,theta*57);a=math.max(0,1-q*2)
   elseif mesh=="Leaf"then
    pose(j,cs*r,sn*r*.5+.2,sn*r,1.7*fade,1.7*fade,1.7*fade,q*260,j*60,q*180)
   elseif j==1 or (j==2 and name=="V2_MeteorBlast")then
    local flash=math.max(0,1-q*4);local size=(blast and math.min(rad*1.2,3)or .7)*flash
    pose(j,0,0,0,size,size,size,0,0,35);a=flash
   else
    pose(j,cs*r,sn*r*.4,sn*r,.11*fade,.08*fade,(blast and .9 or .6)*fade,0,90-theta*57,30)
   end
  end
  -- Spark art is authored on XY. Stretch in its Y axis, then face the camera;
  -- scaling a flat card's Z axis would otherwise produce invisible trails.
  if mesh=="Spark"or mesh=="Streak"then
   local sc=part.localScale;local ea=part.localEulerAngles
   part.localScale=mesh=="Streak"and vector(sc.z,sc.x,1)or vector(sc.x,sc.z,1)
   local camera=U.Camera.main
   if camera then
    local yaw=math.rad(ea.y);local up=V.root.transform:TransformDirection(vector(math.sin(yaw),.05,math.cos(yaw)))
    if math.abs(U.Vector3.Dot(up.normalized,camera.transform.forward))>.94 then up=camera.transform.up end
    part.rotation=U.Quaternion.LookRotation(camera.transform.forward,up)*(mesh=="Streak"and U.Quaternion.Euler(0,0,90)or U.Quaternion.identity)
   else part.localEulerAngles=vector(90,ea.y,0)end
  elseif (mesh=="Smoke"or mesh=="Orb"or mesh=="Flame"or mesh=="MagicHit")and U.Camera.main then
   part.rotation=U.Camera.main.transform.rotation
  end
  local mats=f.partMats[j]
  for _,entry in ipairs(mats or {})do
   local c=entry.color;local mat=entry.mat
   local col=U.Color(c.r,c.g,c.b,c.a*clamp(a,0,1))
   if mat:HasProperty("_BaseColor")then mat:SetColor("_BaseColor",col)end
   if mat:HasProperty("_Color")then mat:SetColor("_Color",col)end
  end
 end
 if (name=="V2_OrbShot"or name=="V2_SlashSweep"or name=="V2_ArrowShot")and q>.15 and q<.85 then
  V.boundsTrace=V.boundsTrace or {}
  if not V.boundsTrace[name]then
   V.boundsTrace[name]=true
   pcall(function()
    local r=f.pieces[1]:GetComponentInChildren(typeof(U.Renderer));local m=r.material;local cam=U.Camera.main
    local vp=cam and cam:WorldToViewportPoint(r.bounds.center)
    local tex=m:HasProperty("_BaseTex")and m:GetTexture("_BaseTex")
    U.Debug.LogError("VFX_BOUNDS "..name.." size="..tostring(r.bounds.size).." center="..tostring(r.bounds.center).." camera="..tostring(cam and cam.name).." viewport="..tostring(vp).." color="..tostring(m:GetColor("_BaseColor")).." texture="..tostring(tex and tex.name).." active="..tostring(r.gameObject.activeInHierarchy))
   end)
  end
 end
 return true
end

local function updateEffects(s,t,arena)
  local first=not V.primed
  for _,e in ipairs(s.effects or {}) do
    local id=tostring(e.id or "")
    if not V.seen[id] then
      local age=t-(tonumber(e.t0)or t)
      -- Future cues stay pending rather than being marked consumed early.
      if age>=0 or first then
       V.seen[id]=tonumber(e.t0)or t
       local restoredZone=(e.kind=="burn"or e.kind=="field")and type(s.zones)=="table"and #s.zones>0
       if not first and not restoredZone then
        if age<.65 then effectSound(e,t)end
        local start,duration=attackWindow(e,t)
        if t-start<duration then addEffect(e,t,arena,s)end
       end
      end
    end
  end
  V.primed=true
  for id,when in pairs(V.seen) do if t-when>10 then V.seen[id]=nil end end
  for i=#V.fx,1,-1 do
    local f=V.fx[i] local e=f.e local age=t-f.started local q=clamp(age/f.duration,0,1)
    if age>f.duration or age<-.5 then releaseFx(f) table.remove(V.fx,i)
    else
      local tr=f.go.transform local x,z=tonumber(e.x) or 0,tonumber(e.z) or 0 local tx,tz=tonumber(e.tx) or x,tonumber(e.tz) or z
      local kind=e.kind local rad=tonumber(e.radius) or 1
      local projectile=kind=="shot" and e.family~="slow" or kind=="hero-ranged"or kind=="hero-pierce"
      if renderV2(f,e,s,t,q)then
      elseif f.pieces then
        local dx,dz=tx-x,tz-z;local angle=math.deg(math.atan(dx,dz))
        tr.localPosition=vector(x,kind=="muzzle" and f.sy or ground(x,z)+(kind=="core-hit" and 1.5 or .7),z)
        tr.localRotation=U.Quaternion.Euler(0,0,0)
        for j,part in ipairs(f.pieces)do
          local theta=(j-1)*math.pi*2/#f.pieces+(tonumber(e.id)or 0)*.7
          local fade=math.max(.001,1-q)
          if f.name=="FX_GlobalRain"then
            local b=s.layout and s.layout.bounds
            local minX,maxX,minZ,maxZ=b and b.minX or x-rad,b and b.maxX or x+rad,b and b.minZ or z-rad,b and b.maxZ or z+rad
            local col,row=(j-1)%9,math.floor((j-1)/9)
            local px=minX+(col+.5+math.sin(j*5+e.id)*.3)*(maxX-minX)/9
            local pz=minZ+(row+.5+math.cos(j*3+e.id)*.3)*(maxZ-minZ)/8
            tr.localPosition=vector(0,0,0)
            local fall=math.max(0,math.min(1,q*1.4-(j%4)*.1))
            part.localPosition=vector(px,ground(px,pz)+.1+8*(1-fall),pz)
            part.localEulerAngles=vector(90,0,0);part.localScale=vector(2.2,2.2,7)
          elseif f.name=="FX_ArrowRain"then
            local a=j*2.4;local r=rad*math.sqrt(j/#f.pieces)*.85
            tr.localPosition=vector(tx,ground(tx,tz),tz)
            local fall=math.max(0,math.min(1,q*1.35-(j%3)*.12))
            part.localPosition=vector(math.cos(a)*r,7*(1-fall)+.1,math.sin(a)*r)
            part.localEulerAngles=vector(90,0,0);part.localScale=vector(.25,.25,4*(1-.6*fall))
          elseif f.name=="FX_MeteorFall"then
            tr.localPosition=vector(x,ground(x,z)+.8+(1-q*q)*15,z)
            local a=j*2.4;local r=j==1 and 0 or .4
            part.localPosition=vector(math.cos(a)*r,(j-1)*.16,math.sin(a)*r)
            part.localEulerAngles=vector(q*220,j*43,q*150)
            local size=j==1 and 11 or 4*(1-q*.4)
            part.localScale=vector(size,size,size)
          elseif f.name=="FX_Blink"then
            local ex=j%2==0 and tx or x;local ez=j%2==0 and tz or z
            tr.localPosition=vector(0,0,0)
            part.localPosition=vector(ex+math.cos(theta)*q*.7,ground(ex,ez)+.7+q,ez+math.sin(theta)*q*.7)
            part.localEulerAngles=vector(0,j*45,0);part.localScale=vector(.5*fade,3*fade,.5*fade)
          elseif f.name=="FX_GroundWarning"then
            local a=math.pi*.25+(j-1)*math.pi*.5
            tr.localPosition=vector(x,ground(x,z)+.025,z)
            part.localPosition=vector(math.cos(a)*rad,0,math.sin(a)*rad)
            part.localEulerAngles=vector(0,45+j*90,0);part.localScale=vector(2,.08,5)
          elseif f.name=="FX_HealRise"then
            local a=j*2.4;local r=.3+(j%3)*.18
            part.localPosition=vector(math.cos(a)*r,q*1.8+(j%2)*.15,math.sin(a)*r)
            part.localScale=vector(.45*fade,1.4*fade,.45*fade)
          elseif f.name=="FX_ArcBolt"then
            local u=math.max(0,q-(j-1)*.025)
            tr.localPosition=vector(f.sx+(tx-f.sx)*u,f.sy+(ground(tx,tz)+.7-f.sy)*u,f.sz+(tz-f.sz)*u)
            part.localPosition=vector(math.sin(j*2.3+q*9)*.08,math.cos(j*2.3+q*9)*.08,0)
            part.localScale=vector(.8*fade,.8*fade,1.6*fade)
          elseif f.name=="FX_SlashRibbon"then
            -- Overlapping tapered facets form a broad swept blade, not a thin circular outline.
            local u=(j-1)/math.max(1,#f.pieces-1);local a=kind=="hero-spin"and (q*math.pi*2-u*1.3)or ((u-.5)*1.4+(q-.5)*1.3)
            local reach=rad*.8
            part.localPosition=vector(math.sin(a)*reach,.15,math.cos(a)*reach)
            part.localEulerAngles=vector(0,math.deg(a),0)
            local width=math.sin(u*math.pi)*.75+.12
            part.localScale=vector(rad*.65*fade,.20,rad*width*fade)
            tr.localRotation=U.Quaternion.Euler(0,angle,0)
          elseif f.name=="FX_DashStreak"then
            local u=(j-1)/#f.pieces;part.localPosition=vector(dx*(q-u*.25),.05,dz*(q-u*.25))
            part.localRotation=U.Quaternion.LookRotation(vector(dx,0,dz))
            part.localScale=vector(.35*fade,.35*fade,(4-j*.4)*fade)
          elseif f.name=="FX_MuzzleBurst"then
            local r=q*.65;part.localPosition=vector(math.cos(theta)*r,math.sin(theta)*r,0)
            part.localEulerAngles=vector(0,0,math.deg(theta))
            local power=e.family=="mortar" and 1.6 or 1
            part.localScale=vector(.7*fade*power,.7*fade*power,2.5*fade*power)
            tr.localRotation=U.Quaternion.LookRotation(vector(dx,0,dz))
          elseif f.name=="FX_BuildBurst"then
            local r=1.3*(1-q*.6);part.localPosition=vector(math.cos(theta)*r,q*3+(j%3)*.22-.5,math.sin(theta)*r)
            part.localEulerAngles=vector(0,math.deg(theta)+q*120,15)
            part.localScale=vector(.8*fade,1.7*fade,.8*fade)
          elseif f.name=="FX_CoreShatter"then
            local strength=kind=="meteor-impact" and 2 or 1
            local r=.25+q*2.5*strength;part.localPosition=vector(math.cos(theta)*r,math.sin(q*math.pi)*1.3-q*.8,math.sin(theta)*r)
            part.localEulerAngles=vector(q*330,j*47+q*170,q*210)
            part.localScale=vector(1.8*fade,2.8*fade,1.8*fade)
          else
            local strength=kind=="impact" and math.min(2.5,rad)or (kind=="death" and 1.2 or .65)
            local r=q*strength*1.8;local vy=(j%3)*.4
            part.localPosition=vector(math.cos(theta)*r,vy+math.sin(q*math.pi)*.55-q*.3,math.sin(theta)*r)
            part.localEulerAngles=vector(0,90-math.deg(theta),0)
            local flash=j==1 and math.max(0,1-q*4) or fade
            part.localScale=vector((j==1 and 4 or .7)*flash,(j==1 and 4 or .7)*flash,(j==1 and 4 or 3.4)*flash)
          end
        end
      elseif f.name=="FX_ArcBolt" then
        local dx,dy,dz=tx-f.sx,ground(tx,tz)+.65-f.sy,tz-f.sz local len=math.sqrt(dx*dx+dy*dy+dz*dz)
        tr.localPosition=vector((tx+f.sx)*.5,(f.sy+ground(tx,tz)+.65)*.5,(tz+f.sz)*.5)
        if len>.001 then tr.localRotation=U.Quaternion.LookRotation(vector(dx,dy,dz)) end
        tr.localScale=vector(1+(1-q)*1.6,1+(1-q)*1.6,math.max(.1,len))
      elseif projectile then
        local dx,dz=tx-f.sx,tz-f.sz local arch=(e.family=="mortar") and math.sin(q*math.pi)*3.4 or 0
        tr.localPosition=vector(f.sx+dx*q,f.sy+(ground(tx,tz)+.55-f.sy)*q+arch,f.sz+dz*q)
        tr.localEulerAngles=vector(0,math.deg(math.atan(dx,dz)),e.family=="mortar" and q*360 or 0)
        if kind=="hero-pierce"then tr.localScale=vector(2.5,2.5,7) elseif e.family=="mortar" then tr.localScale=vector(2,2,2) elseif f.name=="FX_Crystal" then tr.localScale=vector(1.2,1.2,1.2) end
      elseif kind=="hero-melee" or kind=="hero-heavy" then
        local player=e.owner and s.players and s.players[tostring(e.owner)] or nil
        tr.localPosition=vector(x,ground(x,z)+.65,z) tr.localEulerAngles=vector(0,(player and player.angle or e.angle or 0)+(q-.5)*42,0)
        local size=kind=="hero-heavy" and 1.9 or 1.2 tr.localScale=vector(size*(.75+.25*q),1,size*(.75+.25*q))
      elseif kind=="hit" or kind=="impact" or kind=="death" then
        tr.localPosition=vector(x,ground(x,z)+.6+q*.5,z) local sc=(1-q)*(kind=="death" and 3.5 or 1.6) tr.localScale=vector(sc,sc,sc) tr.localEulerAngles=vector(q*160,q*260,q*80)
      elseif kind=="coin" or kind=="mark" then
        tr.localPosition=vector(x,ground(x,z)+1.4+q*.9,z) local sc=kind=="mark" and 1.8 or 1 tr.localScale=vector(sc,sc,sc) tr.localEulerAngles=vector(0,t*160,0)
      else
        local expand=(kind=="warning") and (1+.04*math.sin(t*13)) or (.2+.8*q)
        local rr=math.max(.3,rad*2*expand) local y=kind=="upgrade" and .08+q*2.5 or .08
        tr.localPosition=vector(x,ground(x,z)+y,z) tr.localScale=vector(rr,kind=="upgrade" and 2 or 1,rr) tr.localEulerAngles=vector(0,t*45,0)
      end
    end
  end
end
local function persistent(key,name,color)
  local f=V.persistent[key]
  if not f then f=newFx(name) if not f then return nil end tint(f,color) V.persistent[key]=f end
  return f
end
local function updatePersistent(s,t)
  local seen={}
  for id,tw in pairs(s.towers or {}) do
    if tw.type=="barrier" and (tonumber(tw.wallHp) or 0)>0 and (tonumber(tw.wallUntil) or 0)>t then
      local key="wall:"..tostring(id) seen[key]=true local f=persistent(key,"FX_Wall",COLORS.barrier)
      if f then
        local length=tonumber(tw.wallLength) or 3.2 local ratio=clamp((tw.wallHp or 0)/math.max(1,tw.wallMax or 1),0,1)
        f.go.transform.localPosition=vector(tw.wallX or tw.x,ground(tw.wallX or tw.x,tw.wallZ or tw.z)+1.15,tw.wallZ or ((tw.z or 0)+1.4))
        local slot=s.layout and s.layout.slots and s.layout.slots[tonumber(tw.id or id)]
        f.go.transform.localEulerAngles=vector(0,tw.wallAngle or (slot and slot.yaw) or 0,0)
        f.go.transform.localScale=vector(length,1.4+ratio*.5,1)
      end
    end
  end
  for id,e in pairs(s.enemies or {}) do
    if (e.hp or 0)>0 then
     local rooted=(e.rootUntil or 0)>t;local slowed=(e.slowUntil or 0)>t and (e.slow or 0)>0
     local marked=(e.markUntil or 0)>t
     if rooted or slowed or marked then
      local key="status:"..tostring(id);seen[key]=true
      local f=persistent(key,"V2_Mark",COLORS.slow)
      if f then
       f.go.transform.localPosition=vector(e.x,ground(e.x,e.z)+.035,e.z);f.go.transform.localRotation=U.Quaternion.identity;f.go.transform.localScale=vector(1,1,1)
       for j,part in ipairs(f.pieces or {})do
        part.gameObject:SetActive(true)
        if j==1 then part.localPosition=vector(0,0,0);part.localEulerAngles=vector(0,rooted and 0 or t*25,0);part.localScale=vector(1.1,1,1.1)
        else local a=t*2+j*math.pi;part.localPosition=vector(math.cos(a)*.45,.12,math.sin(a)*.45);part.localScale=vector(.10,.15,.25)end
       end
      end
     end
    end
    if type(e.cast)=="table" and (tonumber(e.cast.untilTime) or 0)>t then
      local key="warning:"..tostring(id) seen[key]=true local f=persistent(key,"FX_GroundWarning",COLORS.warning)
      if f then f.zoneX=e.cast.x;f.zoneZ=e.cast.z;local r=math.max(.4,tonumber(e.cast.radius) or 2)*2 f.go.transform.localPosition=vector(e.cast.x,ground(e.cast.x,e.cast.z)+.09,e.cast.z) f.go.transform.localScale=vector(r,1.3+math.sin(t*17)*.3,r) end
    end
  end
  for i,zone in ipairs(s.zones or {}) do
    if (tonumber(zone.untilTime) or 0)>t then
      local kind=zone.kind or "slow" local key="zone:"..kind..":"..tostring(zone.id or i) seen[key]=true
      local f=persistent(key,kind=="ward" and "V2_WardSigil" or kind=="burn"and "V2_Embers"or "FX_GroundWarning",kind=="burn" and COLORS.mortar or COLORS.slow)
      if f then f.zoneX=zone.x;f.zoneZ=zone.z;local size=math.max(.5,tonumber(zone.radius) or 1)*2 f.go.transform.localPosition=vector(zone.x,ground(zone.x,zone.z)+.08,zone.z) f.go.transform.localScale=vector(size,1+math.sin(t*7)*.12,size) end
    end
  end
  for id,p in pairs(s.players or {}) do
    if p.online~=false and (tonumber(p.hp) or 1)<=0 then
      local key="down:"..tostring(id) seen[key]=true local f=persistent(key,"FX_GroundWarning",COLORS.warning)
      if f then f.zoneX=p.x;f.zoneZ=p.z;f.go.transform.localPosition=vector(p.x,ground(p.x,p.z)+.09,p.z) local size=1.8+math.sin(t*5)*.12 f.go.transform.localScale=vector(size,1,size) end
    end
  end
  for _,f in pairs(V.persistent)do
   if f.v2 and f.zoneX then
    local scale=f.go.transform.localScale;local r=scale.x*.5;f.go.transform.localScale=vector(1,1,1)
    for j,part in ipairs(f.pieces or {})do
     part.gameObject:SetActive(true)
     if f.partNames[j]=="Rune"then part.localPosition=vector(0,0,0);part.localEulerAngles=vector(0,0,0);part.localScale=vector(r*2,1,r*2)
     else
      local a=j*2.4;local rr=r*(.35+.5*(j%3)/2);local px,pz=math.cos(a)*rr,math.sin(a)*rr
      part.localPosition=vector(px,ground(f.zoneX+px,f.zoneZ+pz)-ground(f.zoneX,f.zoneZ)+.12+math.sin(t*4+j)*.08,pz)
      local size=f.partNames[j]=="Flame"and .35 or .14
      part.localScale=vector(size,size*1.6,size);part.localEulerAngles=vector(0,t*30+j*70,0)
     end
    end
   elseif f.pieces and not f.v2 then
    local scale=f.go.transform.localScale;local r=scale.x*.5
    f.go.transform.localScale=vector(1,1,1)
    for j,part in ipairs(f.pieces)do local a=math.pi*.25+(j-1)*math.pi*.5
     if f.name=="FX_WardSigil"then
      if j<=48 then
       a=(j-1)*math.pi*2/48
       local px,pz=math.cos(a)*r,math.sin(a)*r
       local y=f.zoneX and ground(f.zoneX+px,f.zoneZ+pz)-ground(f.zoneX,f.zoneZ)+.015 or .015
       part.localPosition=vector(px,y,pz)
       part.localEulerAngles=vector(0,-math.deg(a),0)
       part.localScale=vector(.4,.025,r*.8)
      else
       a=(j-49)*math.pi/6
       local px,pz=math.cos(a)*r*.7,math.sin(a)*r*.7
       local y=f.zoneX and ground(f.zoneX+px,f.zoneZ+pz)-ground(f.zoneX,f.zoneZ)+.015 or .015
       part.localPosition=vector(px,y,pz)
       part.localEulerAngles=vector(0,-math.deg(a)+90,0)
       part.localScale=vector(.35,.025,r*.9)
      end
     else
      local px,pz=math.cos(a)*r,math.sin(a)*r
      local y=f.zoneX and ground(f.zoneX+px,f.zoneZ+pz)-ground(f.zoneX,f.zoneZ)+.015 or .015
      part.localPosition=vector(px,y,pz)
      part.localEulerAngles=vector(0,45+j*90,0);part.localScale=vector(2,.08,4)
     end
    end
   end
  end
  for id,p in pairs(s.players or {})do
   if p.hp>0 and p.loadout=="melee"and (p.giantUntil or 0)>t then
    local weapon=V.weapons[tostring(id)]
    if weapon and alive(weapon.go)then
     local key="blade:"..tostring(id);seen[key]=true;local f=persistent(key,"V2_GiantAwaken",COLORS.physical)
     if f then
      f.go.transform.position=weapon.go.transform.position;f.go.transform.rotation=weapon.go.transform.rotation;f.go.transform.localScale=vector(1,1,1)
      local tip=weapon.muzzle and V.root.transform:InverseTransformPoint(weapon.muzzle.position)
      local origin=V.root.transform:InverseTransformPoint(weapon.go.transform.position)
      local length=tip and math.sqrt((tip.x-origin.x)^2+(tip.y-origin.y)^2+(tip.z-origin.z)^2)or 3
      for j,part in ipairs(f.pieces or {})do
       part.gameObject:SetActive(true);part.localPosition=vector((j%2==0 and .09 or -.09),0,length*.15+length*.8*(j-1)/#f.pieces)
       part.localEulerAngles=vector(0,0,0);part.localScale=vector(.055,.055,length*.18)
      end
     end
    end
   end
  end
  for key,f in pairs(V.persistent) do
   if not seen[key]then releaseFx(f);V.persistent[key]=nil
   elseif f.v2 then
    for j,part in ipairs(f.pieces or {})do
     local mesh=f.partNames[j]
     if mesh=="Spark"then
      local sc=part.localScale;part.localScale=vector(sc.x,math.max(sc.y,sc.z),1)
      if U.Camera.main then part.rotation=U.Camera.main.transform.rotation end
     elseif mesh=="Flame"and U.Camera.main then part.rotation=U.Camera.main.transform.rotation end
     for _,entry in ipairs(f.partMats[j]or {})do
      local m,c=entry.mat,entry.color;local col=U.Color(c.r,c.g,c.b,c.a*.65)
      if m:HasProperty("_BaseColor")then m:SetColor("_BaseColor",col)end
      if m:HasProperty("_Color")then m:SetColor("_Color",col)end
     end
    end
   end
  end
end
local function refreshActors(t)
  if t<V.nextActors then return end
  V.nextActors=t+.5 V.actors={}
  local ok,players=pcall(CS.DouyinPlayerService.GetPlayers)
  if not ok or not players then return end
  for i=0,players.Length-1 do
    local p=players[i]
    local good,actor=pcall(function() return p:GetActor() end)
    if good and actor then
      local key=tostring(p.playerOpenID or p.playerID)
      V.actors[key]=actor
      V.actors[tostring(p.playerID)]=actor
      V.actors["session:"..tostring(p.playerID)]=actor
    end
  end
end
local function heroDriver(t)
 if V.heroDriver then return V.heroDriver end
 if t<(V.nextHeroSearch or -1)then return nil end
 V.nextHeroSearch=t+1
 local root=U.GameObject.Find("英雄武器与动作组件")
 if not root then V.heroStatus="root missing";return nil end
 local transforms=root:GetComponentsInChildren(typeof(U.Transform),true)
 for i=0,transforms.Length-1 do
  local ok,component=pcall(function()return transforms[i].gameObject:GetDouyinScript("pi-hero-weapon-rig.lua")end)
  if ok and component and component.script and type(component.script.Equip)=="function"then V.heroStatus="driver ready";V.heroDriver=component.script;return V.heroDriver end
 end
 V.heroStatus="root found, script missing"
 return nil
end
local function updateOutfits(s,t)
 local driver=V.outfitDriver
 if not driver and t>=(V.nextOutfitSearch or -1)then
  V.nextOutfitSearch=t+1
  local root=U.GameObject.Find("晶界守卫 · 三职业仔仔职装")
  if root then
   local nodes=root:GetComponentsInChildren(typeof(U.Transform),true)
   for i=0,nodes.Length-1 do
    local ok,c=pcall(function()return nodes[i].gameObject:GetDouyinScript("ms-outfit-rig.lua")end)
    if ok and c and c.script and type(c.script.Equip)=="function"then driver=c.script;V.outfitDriver=driver;break end
   end
  end
 end
 if not driver then return end
 V.outfits=V.outfits or {};local seen={}
 for id,p in pairs(s.players or {})do
  local key=tostring(id);local actor=V.actors[key];local previous=V.outfits[key]
  if actor and p.online~=false and not p.spectator then
   seen[key]=true
   if previous and previous.actor~=actor then pcall(previous.driver.Unequip,previous.actor);V.outfits[key]=nil end
   local ok,equipped=pcall(driver.Equip,actor,p.loadout)
   if ok and equipped then
    V.outfits[key]={actor=actor,driver=driver}
    pcall(driver.SetVisible,actor,(tonumber(p.hp)or 0)>0)
   end
  end
 end
 for key,entry in pairs(V.outfits)do
  if not seen[key]then pcall(entry.driver.Unequip,entry.actor);V.outfits[key]=nil end
 end
end
local function updateWeapons(s,t)
 refreshActors(t)
 local dead={}
 for id,p in pairs(s.players or {})do
  local key=tostring(id);local actor=V.actors[key]
  pcall(updateHurt,key,actor,p,t)
  if p.online~=false and (tonumber(p.hp)or 0)<=0 then dead[key]=true;setHeroHidden(key,actor,true)
  else setHeroHidden(key,actor,false)end
 end
 for key in pairs(hiddenHeroes)do if not dead[key]then restoreHeroRenderers(key)end end
 updateOutfits(s,t)
 local driver=heroDriver(t);if not driver then return end
 local seen={}
 for id,p in pairs(s.players or {})do
  local key=tostring(id);local actor=V.actors[key];local v=V.weapons[key]
  if actor and p.online~=false and (tonumber(p.hp)or 0)>0 then
   seen[key]=true
   if v and (v.actor~=actor or v.kind~=p.loadout)then pcall(driver.Unequip,v.actor);V.weapons[key]=nil;v=nil end
   local ok,equipped=pcall(driver.Equip,actor,p.loadout)
   V.heroStatus="equip "..tostring(ok)..":"..tostring(equipped).." "..tostring(p.loadout)
   if ok and equipped then
    if not v then v={actor=actor,kind=p.loadout,driver=driver,seq=-1};V.weapons[key]=v end
    if driver.SetUltimateScale then pcall(driver.SetUltimateScale,actor,p.loadout=="melee" and t<(tonumber(p.giantUntil)or 0) and 4 or 1)end
    v.go=driver.GetWeapon and driver.GetWeapon(actor);v.muzzle=driver.GetMuzzle and driver.GetMuzzle(actor)
    local at=tonumber(p.actionAt)or -100;local ends=tonumber(p.actionUntil)or -100
    if p.actionKind and v.seq~=p.actionSeq and t>=at and t<ends then
     local target=V.root.transform:TransformPoint(vector(p.actionX or p.x,ground(p.actionX or p.x,p.actionZ or p.z)+.8,p.actionZ or p.z))
     local good,played=pcall(driver.Attack,actor,p.loadout,p.actionKind,target,ends-at,t-at)
     if good and played then v.seq=p.actionSeq else logger:warnOnce("hero-attack", "英雄动作调用未成功", tostring(played))end
    end
   elseif not ok then logger:warnOnce("hero-equip","英雄武器挂接失败",tostring(equipped))end
  elseif v then pcall(driver.Unequip,v.actor);V.weapons[key]=nil end
 end
 for key,v in pairs(V.weapons)do if not seen[key]then pcall(driver.Unequip,v.actor);V.weapons[key]=nil end end
end

function Start()
  if not scope or not resourceRoot then logger:warnOnce("scope","防御塔视觉未就绪",scopeReason) return end
  for _,family in ipairs(FAMILIES) do for _,stage in ipairs(STAGES) do local name="Tower_"..family.."_"..stage local go=scope:FindGameObject("ModelRoot/"..name) V.templates[name]=go if alive(go) then go:SetActive(false) end end end
  for _,name in ipairs({"Weapon_melee","Weapon_ranged","FX_Bolt","FX_Crystal","FX_Ring","FX_Disc","FX_Wall","FX_ArcBolt","FX_Spark","FX_Slash","BuildPad"}) do local go=scope:FindGameObject("ModelRoot/"..name) V.templates[name]=go if alive(go) then go:SetActive(false) end end
  local h=host() if h and type(h.RegisterResource)=="function" then V.entry=h.RegisterResource(resourceRoot,"module-armory",{tags={"armory","visual"},events={},options={resourceId="module-armory"}}) end
  discoverV2()
  V.started=true
end
function Update()
  if not V.started then return end
  local h=host() if not h then return end
  local s=h.GetRenderState() if type(s)~="table" then return end
  local arena=type(h.GetArenaRoot)=="function" and h.GetArenaRoot() or nil if not arena then return end
  if not alive(V.root) then V.root=U.GameObject("CrystalDefenseArmoryViews") V.root.transform:SetParent(arena,false) end
  if V.round~=s.round then clear() V.round=s.round V.nextActors=0 end
  if not V.pack and U.Time.time>=(V.packRetry or 0)then V.packRetry=U.Time.time+1;discoverV2()end
  updateAudio(h,arena)
  local t=presentationTime(h,s)
  updateWeapons(s,t) updateTowers(s,t) updateEffects(s,t,arena) updatePersistent(s,t)
end
function LateUpdate()
  if not V.started or not alive(V.root) then return end
  local h=host() if not h then return end local s=h.GetRenderState() if type(s)~="table" then return end
  -- The weapon rig owns LateUpdate so that hand pose and weapon remain in the same frame.
end
function DebugVisuals()
  local towers=0 local weapons=0 local persistentCount=0 local pooled=0
  for _ in pairs(V.towers) do towers=towers+1 end for _ in pairs(V.weapons) do weapons=weapons+1 end for _ in pairs(V.persistent) do persistentCount=persistentCount+1 end for _,b in pairs(V.pool) do pooled=pooled+#b end
  return {towers=towers,weapons=weapons,effects=#V.fx,persistent=persistentCount,pooled=pooled,round=V.round,started=V.started,volume=V.volume,audioReady=V.audioSource~=nil,v2Ready=V.pack~=nil,missingSounds=V.missingSounds}
end
function OnDisable()
  clear() destroy(V.root) V.root=nil
  local h=host() if h and V.entry and type(h.UnregisterResource)=="function" then h.UnregisterResource(V.entry) end V.entry=nil
end
function OnDestroy() OnDisable() end

function DebugHero()return V.heroStatus or "waiting update"end
