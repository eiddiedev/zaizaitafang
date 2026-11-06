---@id e0c41571-70fd-4b87-ac38-91bea227133b
---@referenceName ms-world.lua
---@assetRef eyJhc3NldElkIjoibWl4LWNyeXN0YWwtZGVmZW5zZTpoYW1sZXQtdWdjL2FpZ2NfZWRpdG9yL2Rldi91bml0eS9NUzR3TGpBQkFBQUFpWGVTbVJUZzVIekJKb1pRTkE0OEh1eXBoeWkxME4zNmk4QjJpenpZSjNZL21peC1wYXJ0LTRfX3VwbG9hZF91c2gzM3c1Yi5nbGIiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvbWl4LXBhcnQtNF9fdXBsb2FkX3VzaDMzdzViLmdsYiIsInJlZmVyZW5jZU5hbWUiOiJtcy13b3JsZC5sdWEifQ
-- 从已提交布局绘制四主题道路、建造位、晶核与循环音乐，不参与伤害或经济结算。
---@displayName 四境地图表现
---@start
---@var MusicEnabled:boolean=true
---@name 启用背景音乐
---@var MusicVolume:number=0.8
---@name 背景音乐音量
---@end

local U = CS.UnityEngine
local Time = CS.UnityEngine.Time
local Logger = require("official.core.logger")
local RuntimeScope = require("official.core.runtime_scope")
local scope, scopeReason = RuntimeScope.from(self)
local logger = Logger.create("world-view")
local resourceRoot = scope ~= nil and scope:GetResourceRoot() or nil
local V = { started=false, templates={}, themes={}, dynamic={}, materials={}, pads={}, hash=nil,
  theme="forest", music={}, desiredMusic=nil, entry=nil, retryAt=0, lastError=nil, tick=0 }
local themeNames = { forest="ThemeForest", snow="ThemeSnow", desert="ThemeDesert", night="ThemeNight" }
local musicNames = { "music-forest", "music-snow", "music-desert", "music-night", "music-boss" }
local palettes = {
  forest={road={0.72,0.63,0.43},edge={0.66,0.69,0.53}},
  snow={road={0.51,0.62,0.69},edge={0.82,0.88,0.91}},
  desert={road={0.76,0.60,0.35},edge={0.87,0.73,0.49}},
  night={road={0.39,0.40,0.53},edge={0.56,0.58,0.70}},
}

-- 官方 RuntimeAudio 播放入口，循环片段只从本资源节点读取。
local Sfx = {}
function Sfx.find(go,name)
  local t = go ~= nil and go.transform or nil
  while t ~= nil do
    local node = t:Find("RuntimeAudio/" .. name)
    if node ~= nil then return node end
    t = t.parent
  end
  return nil
end
function Sfx.loop(go,name,on)
  local h=scope and scope:GetRuntimeHostScript("runtime-host.lua")
  return h and type(h.LoopAudioBank)=="function" and h.LoopAudioBank("world",name,on)or nil
end

local function host()
  if scope == nil then return nil end
  local h,reason = scope:GetRuntimeHostScript("runtime-host.lua")
  if h == nil then logger:warnOnce("host-unavailable","地图表现等待宿主接口",reason) end
  return h
end

local function alive(go)
  if go == nil then return false end
  local ok,t = pcall(function() return go.transform end)
  return ok and t ~= nil
end

local function clearDynamic()
  for _,go in ipairs(V.dynamic) do if alive(go) then pcall(U.Object.Destroy,go) end end
  for _,material in ipairs(V.materials) do pcall(U.Object.Destroy,material) end
  V.dynamic={};V.materials={};V.pads={};V.hash=nil
end

local function stopMusic()
  for _,name in ipairs(musicNames) do Sfx.loop(resourceRoot,name,false) end
  for _,entry in pairs(V.music) do pcall(function() entry.source.volume=entry.baseVolume end) end
  V.music={};V.desiredMusic=nil
end

local function writeColor(material, rgb, glow)
  if material == nil then return end
  local c=U.Color(rgb[1],rgb[2],rgb[3],1)
  material.color=c
  if material:HasProperty("_BaseColor") then material:SetColor("_BaseColor",c) end
  if glow ~= nil and material:HasProperty("_EmissionColor") then
    material:SetColor("_EmissionColor",U.Color(rgb[1]*glow,rgb[2]*glow,rgb[3]*glow,1))
    material:EnableKeyword("_EMISSION")
  end
end

local function ownMaterial(t,path)
  local node=path ~= nil and t:Find(path) or t
  if node == nil then return nil end
  local renderer=node:GetComponent(typeof(U.MeshRenderer))
  if renderer == nil then return nil end
  local material=renderer.material
  if material ~= nil then V.materials[#V.materials+1]=material end
  return material
end

local function clone(name,arena,x,y,z,sx,sy,sz,yaw)
  local source=V.templates[name]
  if source == nil then error("missing world template " .. name) end
  -- 仅克隆无脚本视觉后代；同步权威仍在宿主快照中。
  local go=U.Object.Instantiate(source.gameObject)
  go.name="MapView_" .. name .. "_" .. tostring(#V.dynamic+1)
  local t=go.transform;t:SetParent(arena,false)
  t.localPosition=U.Vector3(x,y,z)
  t.localRotation=U.Quaternion.Euler(0,yaw or 0,0)
  t.localScale=U.Vector3(sx or 1,sy or 1,sz or 1)
  go:SetActive(true)
  V.dynamic[#V.dynamic+1]=go
  return t
end

local function chooseTheme(name)
  name=themeNames[name] ~= nil and name or "forest"
  for key,t in pairs(V.themes) do t.gameObject:SetActive(false) end
  V.theme=name
end

local function rebuild(layout,arena,round)
  clearDynamic();chooseTheme(layout.theme)
  if layout.nativeScene then
    for _,slot in ipairs(layout.slots)do
      local pad=clone("BuildPad",arena,slot.x,slot.y,slot.z,.72,1,.72,0)
      local ring=pad:Find("Ring")
      for i=0,pad.childCount-1 do local child=pad:GetChild(i);child.gameObject:SetActive(false) end
      local material=ownMaterial(pad,"Ring")
      V.pads[#V.pads+1]={id=slot.id,root=pad,ring=ring,economy=false,material=material}
    end
    V.hash=tostring(round or "")..":"..tostring(layout.hash)
    return
  end
  local colors=palettes[V.theme]
  local jointKeys={}
  for routeIndex,route in ipairs(layout.routes or {}) do
    for i,p in ipairs(route.points or {}) do
      local key=tostring(math.floor(p.x*10))..":"..tostring(math.floor(p.z*10))
      if not jointKeys[key] then
        local joint=clone("RoadJoint",arena,p.x,0.025,p.z,1,1,1,0)
        writeColor(ownMaterial(joint,"Surface"),colors.road)
        jointKeys[key]=true
      end
      if i > 1 then
        local a=route.points[i-1];local dx,dz=p.x-a.x,p.z-a.z
        local length=math.sqrt(dx*dx+dz*dz)
        if length > 0.01 then
          local yaw=math.deg(math.atan(dx,dz))
          local segment=clone("RoadSegment",arena,(a.x+p.x)*0.5,0.025,(a.z+p.z)*0.5,3,1,length,yaw)
          writeColor(ownMaterial(segment,"Surface"),colors.road)
          -- 短石块沿真实路线排列，转角留空，避免拉长装饰石纹。
          local count=math.max(1,math.floor((length-2)/4.5))
          for k=1,count do
            local q=k/(count+1);local x,z=a.x+dx*q,a.z+dz*q
            for _,side in ipairs({-1,1}) do
              local edge=clone("RoadEdge",arena,x+dz/length*1.58*side,0.025,z-dx/length*1.58*side,1,1,math.min(2.5,length*.45),yaw)
              writeColor(ownMaterial(edge,"Stone"),colors.edge)
            end
          end
          if length>5 then
            for distance=3,length-2,9 do
              clone("PathArrow",arena,a.x+dx*distance/length,0.025,a.z+dz*distance/length,.68,1,.68,yaw)
            end
          end
        end
      end
    end
  end
  for _,slot in ipairs(layout.slots or {}) do
    local pad=clone("BuildPad",arena,slot.x,0,slot.z,1,1,1,0)
    local ring=pad:Find("Ring");local gem=pad:Find("EconomicGem")
    if gem ~= nil then gem.gameObject:SetActive(slot.economy == true) end
    local material=ownMaterial(pad,"Ring")
    V.pads[#V.pads+1]={id=slot.id,root=pad,ring=ring,gem=gem,economy=slot.economy == true,material=material,lastState=nil}
  end
  if V.theme=="forest" then
    local first=layout.routes[1].points[1]
    clone("SceneryArch",arena,first.x,0,first.z,1,1,1,0)
  end
  -- Library scenery follows the actual route clearance, filling the islands between lanes.
  if V.theme=="forest" or V.theme=="snow" then
    local function clearance(x,z)
      for _,r in ipairs(layout.routes)do for i=2,#r.points do
        local a,b=r.points[i-1],r.points[i];local dx,dz=b.x-a.x,b.z-a.z
        local q=math.max(0,math.min(1,((x-a.x)*dx+(z-a.z)*dz)/(dx*dx+dz*dz)))
        if (x-a.x-dx*q)^2+(z-a.z-dz*q)^2<23 then return false end
      end end
      for _,p in ipairs(layout.slots)do if (x-p.x)^2+(z-p.z)^2<15 then return false end end
      return x*x+(z+14.4)^2>40
    end
    local seed=layout.seed
    local function random()seed=(seed*48271)%2147483647;return seed/2147483647 end
    for x=-27,27,4 do for z=-21,21,4 do
      local px,pz=x+(random()-.5)*1.8,z+(random()-.5)*1.8
      if clearance(px,pz) then
        local scale=.7+random()*.5
        clone("SceneryPine",arena,px,0,pz,scale,scale,scale,random()*360)
        if random()>.6 then clone("SceneryBush",arena,px+1,0,pz+1,.65,.65,.65,random()*360)end
      end
    end end
  end
  V.hash=tostring(round or "")..":"..tostring(layout.hash)
  V.lastError=nil
  logger:info("地图表现就绪",V.theme,V.hash,#V.dynamic,#V.pads)
end

local function updatePads(state,view,time)
  local towers=state.towers or {}
  local selected=view ~= nil and view.selectedSlot ~= nil and tostring(view.selectedSlot) or nil
  for _,pad in ipairs(V.pads) do
    local occupied=towers[pad.id] ~= nil or towers[tostring(pad.id)] ~= nil
    local isSelected=selected ~= nil and selected == tostring(pad.id)
    local mode=(occupied and "built" or "empty")..(isSelected and ":selected" or "")
    if pad.lastState ~= mode then
      local color=isSelected and {1,.74,.25} or (pad.economy and {.32,.82,.57} or {.40,.68,.78})
      writeColor(pad.material,color,isSelected and .65 or .12)
      if pad.ring ~= nil then pad.ring.gameObject:SetActive(false) end
      if pad.gem ~= nil then pad.gem.gameObject:SetActive(pad.economy and not occupied) end
      pad.lastState=mode
    end
    if pad.ring ~= nil and isSelected then
      local pulse=1.03+math.sin(time*4)*.025
      pad.ring.localScale=U.Vector3(pulse,pulse,pulse)
    elseif pad.ring ~= nil then pad.ring.localScale=U.Vector3(1,1,1) end
    if pad.gem ~= nil and pad.economy and not occupied then pad.gem.localEulerAngles=U.Vector3(0,time*35,0) end
  end
end

local function updateMusic(state,dt,h)
  local settings=h ~= nil and type(h.GetLocalSettings)=="function" and h.GetLocalSettings() or nil
  local masterVolume=type(settings)=="table" and tonumber(settings.volume) or 1
  masterVolume=math.max(0,math.min(1,masterVolume or 1))
  V.masterVolume=masterVolume
  local ended=state.phase == "RESULT" or state.phase == "RESETTING"
  local desired=MusicEnabled and not ended and ((state.wave == 24 and "music-boss") or ("music-"..V.theme)) or nil
  V.desiredMusic=desired
  if desired ~= nil and V.music[desired] == nil then
    local source=Sfx.loop(resourceRoot,desired,true)
    if source ~= nil then
      local volume=source.volume;source.volume=0
      V.music[desired]={source=source,baseVolume=volume,level=0}
    else logger:warnOnce("music-not-ready","背景音频尚未可用，地图继续运行") end
  end
  for name,entry in pairs(V.music) do
    if name==desired then entry.source.loop=true;entry.source.spatialBlend=0;entry.source.priority=0;if not entry.source.isPlaying then entry.source:Play()end end
    local target=name == desired and 1 or 0
    local step=dt/.65
    if entry.level<target then entry.level=math.min(target,entry.level+step) else entry.level=math.max(target,entry.level-step) end
    entry.source.volume=entry.baseVolume*math.max(0,math.min(1,MusicVolume or .8))*masterVolume*entry.level
    if target==0 and entry.level<=0 then
      entry.source:Stop();entry.source.volume=entry.baseVolume;V.music[name]=nil
    end
  end
end

local function register()
  local h=host()
  if h ~= nil and type(h.RegisterResource)=="function" and resourceRoot ~= nil and V.entry == nil then
    V.entry=h.RegisterResource(resourceRoot,"module-world",{tags={"world","map"}})
  end
end

function Start()
  if scope == nil or resourceRoot == nil then logger:warnOnce("scope-missing","地图资源上下文不可用",scopeReason);return end
  for key,name in pairs(themeNames) do
    local t=scope:FindTransform("ModelRoot/"..name)
    if t ~= nil then V.themes[key]=t else logger:warnOnce("theme-missing-"..key,"缺少主题节点",name) end
  end
  for _,name in ipairs({"RoadSegment","RoadEdge","RoadJoint","BuildPad","PathArrow","SceneryPine","SceneryBush","SceneryArch","SceneryBridge"}) do
    V.templates[name]=scope:FindTransform("ModelRoot/RuntimeTemplates/"..name)
  end
  -- The editor public library tree is a textured production asset, distinct from CLI geometry samples.
  -- Clone only renderer descendants into a private visual template, never the scene object wrapper.
  V.nativeSources={}
  local native=nil -- authored environment is retained as placed
  if native then
    local wrapper=U.GameObject("CrystalDefense_NativeTreeTemplate")
    local source=native.transform
    local renderers=native:GetComponentsInChildren(typeof(U.MeshRenderer),true)
    for i=0,renderers.Length-1 do
      local r=renderers[i];local node=U.Object.Instantiate(r.gameObject);node.transform:SetParent(wrapper.transform,false)
      local p=source:InverseTransformPoint(r.transform.position);local ls=r.transform.lossyScale;local ss=source.lossyScale
      node.transform.localPosition=U.Vector3(p.x*4.8,(p.y+.015)*4.8,p.z*4.8)
      node.transform.localRotation=U.Quaternion.LookRotation(source:InverseTransformDirection(r.transform.forward),source:InverseTransformDirection(r.transform.up))
      node.transform.localScale=U.Vector3(ls.x/ss.x*4.8,ls.y/ss.y*4.8,ls.z/ss.z*4.8)
      local colliders=node:GetComponentsInChildren(typeof(U.Collider),true);for j=0,colliders.Length-1 do colliders[j].enabled=false end
    end
    wrapper:SetActive(false);V.nativeTemplate=wrapper;V.templates.SceneryPine=wrapper.transform
    V.nativeSources[#V.nativeSources+1]=native;native:SetActive(false)
  end
  local old=U.GameObject.Find("古老花树01");if old then V.nativeSources[#V.nativeSources+1]=old;old:SetActive(false)end
  local templates=scope:FindTransform("ModelRoot/RuntimeTemplates")
  if templates ~= nil then templates.gameObject:SetActive(false) end
  local oldCore=scope:FindTransform("ModelRoot/Core")
  if oldCore then oldCore.gameObject:SetActive(false) end
  V.crystal=nil
  V.halo=scope:FindTransform("ModelRoot/Core/Halo")
  local prism=scope:FindTransform("ModelRoot/Core/Crystal/Prism")
  if prism ~= nil then
    local r=prism:GetComponent(typeof(U.MeshRenderer))
    if r ~= nil then V.coreMaterial=r.material end
  end
  V.started=true;chooseTheme("forest");register()
end

function Update()
  if not V.started then return end
  local h=host()
  if h == nil or type(h.GetRenderState)~="function" or type(h.GetArenaRoot)~="function" then return end
  local state=h.GetRenderState()
  if type(state) ~= "table" then return end
  if state.phase == "RESETTING" then
    if #V.dynamic>0 then clearDynamic() end
    updateMusic(state,math.min(Time.deltaTime,.1),h)
    return
  end
  local arena=h.GetArenaRoot()
  if arena == nil then return end
  arena=arena.transform
  local time=tonumber(state.t) or Time.time
  local layout=state.layout
  if type(layout)=="table" and layout.hash ~= nil then
    local stamp=tostring(state.round or "")..":"..tostring(layout.hash)
    if V.hash ~= stamp and Time.time>=V.retryAt then
      local ok,err=pcall(rebuild,layout,arena,state.round)
      if not ok then
        V.lastError=tostring(err);V.retryAt=Time.time+1
        logger:warnOnce("map-render-failed","地图表现重建失败",err)
      end
    end
  end
  local view=type(h.GetGameView)=="function" and h.GetGameView() or nil
  updatePads(state,view,time)
  local hp=tonumber(state.core) or 20;local hpMax=tonumber(state.coreMax) or 20
  local danger=hp<=hpMax*.3
  if V.crystal ~= nil then
    local pulse=1+math.sin(time*(danger and 5.5 or 1.7))*(danger and .065 or .025)
    V.crystal.localScale=U.Vector3(pulse,pulse,pulse)
    V.crystal.localEulerAngles=U.Vector3(0,time*12,0)
  end
  if V.halo ~= nil then V.halo.localEulerAngles=U.Vector3(82+math.sin(time*.6)*6,time*18,0) end
  if V.lastDanger ~= danger then
    writeColor(V.coreMaterial,danger and {1,.28,.20} or {.40,.79,.94},danger and .75 or .65)
    V.lastDanger=danger
  end
  updateMusic(state,math.min(Time.deltaTime,.1),h)
end

function GetWorldViewDebug()
  return {ready=V.started,layoutHash=V.hash,theme=V.theme,objects=#V.dynamic,pads=#V.pads,music=V.desiredMusic,masterVolume=V.masterVolume,error=V.lastError}
end

function OnEnable()
  if V.started then register() end
end

function OnDisable()
  clearDynamic();stopMusic()
  local h=host()
  if h ~= nil and type(h.UnregisterResource)=="function" and V.entry ~= nil then h.UnregisterResource(V.entry) end
  V.entry=nil
end

function OnDestroy()
  if V.nativeTemplate then pcall(U.Object.Destroy,V.nativeTemplate)end
  for _,go in ipairs(V.nativeSources or {})do if alive(go)then go:SetActive(true)end end
  clearDynamic();stopMusic()
  if V.coreMaterial ~= nil then pcall(U.Object.Destroy,V.coreMaterial);V.coreMaterial=nil end
end