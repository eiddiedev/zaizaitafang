---@id bf5571bc-008e-4d8a-b0fc-43c6815492be
---@referenceName ms-foes.lua
---@assetRef eyJhc3NldElkIjoibWl4LWNyeXN0YWwtZGVmZW5zZTpoYW1sZXQtdWdjL2FpZ2NfZWRpdG9yL2Rldi91bml0eS9NUzR3TGpBQkFBQUFpWGVTbVJUZzVIekJKb1pRTkE0OEh1eXBoeWkxME4zNmk4QjJpenpZSjNZL21peC1wYXJ0LTRfX3VwbG9hZF91c2gzM3c1Yi5nbGIiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvbWl4LXBhcnQtNF9fdXBsb2FkX3VzaDMzdzViLmdsYiIsInJlZmVyZW5jZU5hbWUiOiJtcy1mb2VzLmx1YSJ9
-- 从已提交赛局快照重建敌人、机械动作和血条，不进行伤害或奖励结算。
---@displayName 敌人动作与血条
local U = CS.UnityEngine
local RuntimeScope = require("official.core.runtime_scope")
local Logger = require("official.core.logger")
local logger = Logger.create("foes-view")
local scope, scopeReason = RuntimeScope.from(self)
local resourceRoot = scope and scope:GetResourceRoot() or nil
local V = {templates={}, units={}, pool={}, materials={}, retired={}, round=nil, root=nil, entry=nil, sounds={}, soundAt=-1, soundCount=0, started=false, primed=false}
local KINDS = {"basic","runner","armored","resistant","ranged","healer","breaker","splitter","guard","caster","boss","child"}
local LIMBS = {"Limb_FL","Limb_FR","Limb_BL","Limb_BR"}
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
    node.parent:GetComponent(AudioSource):PlayOneShot(node:GetComponent(AudioSource).clip, 1)
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
local function alive(go)
  if go == nil then return false end
  local ok, t = pcall(function() return go.transform end)
  return ok and t ~= nil
end
local function destroy(go) if alive(go) then U.Object.Destroy(go) end end
local function xyz(v) return {x=v.x,y=v.y,z=v.z} end
local function host()
  if not scope then return nil end
  local h = scope:GetRuntimeHostScript("runtime-host.lua")
  if h == nil or type(h.GetRenderState) ~= "function" then return nil end
  return h
end
local function presentationTime(h,s)
  local t=type(h.GetPresentationTime)=="function" and tonumber(h.GetPresentationTime()) or nil
  return t or tonumber(s.t) or 0
end
-- Audio clips are 2D; filter distant ordinary events without claiming spatial audio.
local function updateAudio(h,arena)
  local settings=type(h.GetLocalSettings)=="function" and h.GetLocalSettings() or nil
  local volume=math.max(0,math.min(1,tonumber(settings and settings.volume) or .8))
  V.volume=volume;V.audioReady=type(h.PlayAudioBank)=="function"
  V.listenerX=nil V.listenerZ=nil
  pcall(function()
    local actor=CS.DouyinActorService.GetLocalActor()
    if actor then local pos=arena:InverseTransformPoint(actor.position) V.listenerX=pos.x V.listenerZ=pos.z end
  end)
end
local function audible(x,z)
  if V.listenerX==nil or x==nil or z==nil then return true end
  return (x-V.listenerX)^2+(z-V.listenerZ)^2<=576
end
local function play(name,t,priority,x,z)
  if not V.primed or (not priority and not audible(x,z)) then return end
  if t-(V.sounds[name] or -100)<(priority and .35 or .14) then return end
  if t-V.soundAt>=1 then V.soundAt=t V.soundCount=0 end
  if V.soundCount>=8 and not priority then return end
  V.sounds[name]=t V.soundCount=V.soundCount+1
  local h=host();if h and type(h.PlayAudioBank)=="function"then h.PlayAudioBank("foes",name,V.volume or 1)end
end
local function clone(name,parent)
  local template=V.templates[name]
  if not alive(template) then logger:warnOnce("missing-template","敌人可视模板缺失",name) return nil end
  local go=U.Object.Instantiate(template)
  go.name="View_"..name
  go.transform:SetParent(parent,false)
  go.transform.localPosition=U.Vector3(0,0,0)
  go.transform.localRotation=U.Quaternion.identity
  go.transform.localScale=U.Vector3(1,1,1)
  go:SetActive(true)
  return go
end
local function find(t,path) return t and t:Find(path) or nil end
local function releaseUnit(v)
  if not v then return end
  if alive(v.go) then
    v.go:SetActive(false)
    for _,go in ipairs({v.back,v.fill,v.rootFx,v.burnFx}) do if alive(go) then go:SetActive(false) end end
    V.pool[v.kind]=V.pool[v.kind] or {}
    if #V.pool[v.kind]<12 then table.insert(V.pool[v.kind],v) else
      destroy(v.go) destroy(v.back) destroy(v.fill) destroy(v.rootFx) destroy(v.burnFx)
    end
  end
end

-- Copy the generated mesh and shared materials only: source scripts/colliders are never cloned.
local sources={basic={"裂隙魔物·动画版",1.8},runner={"裂隙疾爪·动画版",1.65},armored={"裂隙铁背（动画版）",2},resistant={"裂隙晶壳·动画守卫",1.8},ranged={"裂隙投矛手（动画版）",1.8},healer={"灯祭者（动作版）",1.7},breaker={"破门兽（骨骼动画版）",2.4},splitter={"裂隙裂团（动画版）",1.85},child={"裂团子体·动画版",1.05},guard={"裂隙铁卫统领（动画版）",2.25},caster={"裂隙蚀光使（动画版）",2.15},boss={"界门巨兽（骨骼动画版）",3}}
local function riftMeshSource(kind)
 local spec=sources[kind];local go=spec and U.GameObject.Find(spec[1])
 return go and go:GetComponentInChildren(typeof(U.MeshFilter),true)or nil
end
local AnimatedFactories = {}
AnimatedFactories.armored=function(root,height)
local EnsureReady,Start,OnEnable,OnDisable,Update,Play,SetSpeed,GetAction,GetActionDuration,GetHitTime,GetRigStatus
local DefaultFade=0.18
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 逐骨骼驱动裂隙铁背的待机、行走、攻击与受击，供预览面板和局内调用

local Logger = require("official.core.logger")
local RuntimeScope={from=function()return boundScope end}
local UnityEngine = CS.UnityEngine
local Quaternion = CS.UnityEngine.Quaternion
local Time = clock

local logger = Logger.create("ms-armored-animation")
local runtimeScope, scopeReason = RuntimeScope.from(self)

-- 骨架按父级先于子级的顺序排列；parent 为 0 表示该骨骼直接挂在骨架根下。
local BONE_DEFS = {
  { name = "root", path = "Armature/root.x", parent = 0 },
  { name = "spine_01", path = "Armature/root.x/spine_01.x", parent = 1 },
  { name = "spine_02", path = "Armature/root.x/spine_01.x/spine_02.x", parent = 2 },
  { name = "spine_03", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x", parent = 3 },
  { name = "neck", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x", parent = 4 },
  { name = "head", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x/head.x", parent = 5 },
  { name = "shoulder.l", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l", parent = 4 },
  { name = "arm_stretch.l", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l", parent = 7 },
  { name = "forearm_stretch.l", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l", parent = 8 },
  { name = "hand.l", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l/hand.l", parent = 9 },
  { name = "shoulder.r", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r", parent = 4 },
  { name = "arm_stretch.r", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r", parent = 11 },
  { name = "forearm_stretch.r", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r", parent = 12 },
  { name = "hand.r", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r/hand.r", parent = 13 },
  { name = "thigh_stretch.l", path = "Armature/root.x/thigh_stretch.l", parent = 1 },
  { name = "leg_stretch.l", path = "Armature/root.x/thigh_stretch.l/leg_stretch.l", parent = 15 },
  { name = "foot.l", path = "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l", parent = 16 },
  { name = "toes_01.l", path = "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l/toes_01.l", parent = 17 },
  { name = "thigh_stretch.r", path = "Armature/root.x/thigh_stretch.r", parent = 1 },
  { name = "leg_stretch.r", path = "Armature/root.x/thigh_stretch.r/leg_stretch.r", parent = 19 },
  { name = "foot.r", path = "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r", parent = 20 },
  { name = "toes_01.r", path = "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r/toes_01.r", parent = 21 },
}
local BONE_COUNT = #BONE_DEFS
local IDENTITY = Quaternion(0, 0, 0, 1)

-- 基础站姿：把绑定用的 T-pose 手臂放下，重心略低，拳头置于身体前方。
BASE = {
  ["spine_01"] = { 2, 0, 0 },
  ["spine_02"] = { 1, 0, 0 },
  ["spine_03"] = { 1, 0, 0 },
  ["neck"] = { -2, 0, 0 },
  ["head"] = { 2, 0, 0 },
  ["shoulder.l"] = { 0, 0, -6 },
  ["arm_stretch.l"] = { -6, -4, -42 },
  ["forearm_stretch.l"] = { -24, 0, -6 },
  ["hand.l"] = { -6, 0, -4 },
  ["shoulder.r"] = { 0, 0, 6 },
  ["arm_stretch.r"] = { -6, 4, 42 },
  ["forearm_stretch.r"] = { -24, 0, 6 },
  ["hand.r"] = { -6, 0, 4 },
  ["thigh_stretch.l"] = { -2, 0, -1 },
  ["leg_stretch.l"] = { 6, 0, 0 },
  ["foot.l"] = { -4, 0, 0 },
  ["thigh_stretch.r"] = { -2, 0, 1 },
  ["leg_stretch.r"] = { 6, 0, 0 },
  ["foot.r"] = { -4, 0, 0 },
}

IDLE_CLIP = { duration = 4, loop = true, ease = "smooth", tracks = {
  ["spine_01"] = { { 0, 0, 0, 0 }, { 2, 0.8, 0, 1.4 }, { 4, 0, 0, 0 } },
  ["spine_02"] = { { 0, 0, 0, 0 }, { 1, 1, 0.4, 0 }, { 2, 1.6, 0, 0 }, { 3, 0.6, -0.4, 0 }, { 4, 0, 0, 0 } },
  ["spine_03"] = { { 0, 0, 0, 0 }, { 2, 0.8, 0, 0 }, { 4, 0, 0, 0 } },
  ["neck"] = { { 0, 0, 0, 0 }, { 2, -0.6, 0, 0 }, { 4, 0, 0, 0 } },
  ["head"] = { { 0, 0, 0, 0 }, { 1, 0.6, 0.8, 0 }, { 2, -0.4, 0, 0 }, { 3, 0.5, -0.8, 0 }, { 4, 0, 0, 0 } },
  ["shoulder.l"] = { { 0, 0, 0, 0 }, { 2, 0, 0, -1.2 }, { 4, 0, 0, 0 } },
  ["shoulder.r"] = { { 0, 0, 0, 0 }, { 2, 0, 0, 1.2 }, { 4, 0, 0, 0 } },
  ["arm_stretch.l"] = { { 0, 0, 0, 0 }, { 2, 1.4, 0, -1 }, { 4, 0, 0, 0 } },
  ["arm_stretch.r"] = { { 0, 0, 0, 0 }, { 2, 1.4, 0, 1 }, { 4, 0, 0, 0 } },
  ["forearm_stretch.l"] = { { 0, 0, 0, 0 }, { 2, -1.5, 0, 0 }, { 4, 0, 0, 0 } },
  ["forearm_stretch.r"] = { { 0, 0, 0, 0 }, { 2, -1.5, 0, 0 }, { 4, 0, 0, 0 } },
  ["leg_stretch.l"] = { { 0, 0, 0, 0 }, { 2, 1.2, 0, 0 }, { 4, 0, 0, 0 } },
  ["leg_stretch.r"] = { { 0, 0, 0, 0 }, { 3, 1.2, 0, 0 }, { 4, 0, 0, 0 } },
  },
}

WALK_CLIP = { duration = 1.5, loop = true, ease = "smooth", tracks = {
  ["thigh_stretch.l"] = { { 0, -20, 0, 0 }, { 0.375, 0, 0, 0 }, { 0.75, 14, 0, 0 }, { 1.125, -10, 0, 0 }, { 1.5, -20, 0, 0 } },
  ["thigh_stretch.r"] = { { 0, 14, 0, 0 }, { 0.375, -8, 0, 0 }, { 0.75, -20, 0, 0 }, { 1.125, 0, 0, 0 }, { 1.5, 14, 0, 0 } },
  ["leg_stretch.l"] = { { 0, 8, 0, 0 }, { 0.375, 10, 0, 0 }, { 0.75, 18, 0, 0 }, { 1.125, 58, 0, 0 }, { 1.5, 8, 0, 0 } },
  ["leg_stretch.r"] = { { 0, 18, 0, 0 }, { 0.375, 58, 0, 0 }, { 0.75, 8, 0, 0 }, { 1.125, 10, 0, 0 }, { 1.5, 18, 0, 0 } },
  ["foot.l"] = { { 0, 6, 0, 0 }, { 0.375, -4, 0, 0 }, { 0.75, -14, 0, 0 }, { 1.125, -48, 0, 0 }, { 1.5, 6, 0, 0 } },
  ["foot.r"] = { { 0, -14, 0, 0 }, { 0.375, -48, 0, 0 }, { 0.75, 6, 0, 0 }, { 1.125, -4, 0, 0 }, { 1.5, -14, 0, 0 } },
  ["toes_01.l"] = { { 0, 0, 0, 0 }, { 0.375, -6, 0, 0 }, { 0.75, 10, 0, 0 }, { 1.125, 0, 0, 0 }, { 1.5, 0, 0, 0 } },
  ["toes_01.r"] = { { 0, 10, 0, 0 }, { 0.375, 0, 0, 0 }, { 0.75, 0, 0, 0 }, { 1.125, -6, 0, 0 }, { 1.5, 10, 0, 0 } },
  ["spine_01"] = { { 0, 0, 0, -2.5 }, { 0.375, 2, 0, -2.5 }, { 0.75, 0, 0, 2.5 }, { 1.125, 2, 0, 2.5 }, { 1.5, 0, 0, -2.5 } },
  ["spine_02"] = { { 0, 0, 3.5, 0 }, { 0.375, 1, 0, 0 }, { 0.75, 0, -3.5, 0 }, { 1.125, 1, 0, 0 }, { 1.5, 0, 3.5, 0 } },
  ["spine_03"] = { { 0, 0, 2.5, 0 }, { 0.75, 0, -2.5, 0 }, { 1.5, 0, 2.5, 0 } },
  ["neck"] = { { 0, 0, -2.5, 0 }, { 0.75, 0, 2.5, 0 }, { 1.5, 0, -2.5, 0 } },
  ["head"] = { { 0, 0, -2, 0 }, { 0.375, -1.5, 0, 0 }, { 0.75, 0, 2, 0 }, { 1.125, -1.5, 0, 0 }, { 1.5, 0, -2, 0 } },
  ["arm_stretch.l"] = { { 0, 14, 0, 0 }, { 0.375, 0, 0, 0 }, { 0.75, -12, 0, 0 }, { 1.125, 0, 0, 0 }, { 1.5, 14, 0, 0 } },
  ["arm_stretch.r"] = { { 0, -12, 0, 0 }, { 0.375, 0, 0, 0 }, { 0.75, 14, 0, 0 }, { 1.125, 0, 0, 0 }, { 1.5, -12, 0, 0 } },
  ["forearm_stretch.l"] = { { 0, -4, 0, 0 }, { 0.375, 0, 0, 0 }, { 0.75, -12, 0, 0 }, { 1.125, -2, 0, 0 }, { 1.5, -4, 0, 0 } },
  ["forearm_stretch.r"] = { { 0, -12, 0, 0 }, { 0.375, -2, 0, 0 }, { 0.75, -4, 0, 0 }, { 1.125, 0, 0, 0 }, { 1.5, -12, 0, 0 } },
  ["shoulder.l"] = { { 0, -2, 0, -1.5 }, { 0.75, 1, 0, 1.5 }, { 1.5, -2, 0, -1.5 } },
  ["shoulder.r"] = { { 0, 1, 0, -1.5 }, { 0.75, -2, 0, 1.5 }, { 1.5, 1, 0, -1.5 } },
  },
}

ATTACK_CLIP = { duration = 1.6, loop = false, ease = "linear", tracks = {
  ["spine_01"] = { { 0, 0, 0, 0 }, { 0.25, 1, -3, -2 }, { 0.45, 1, -5, -2 }, { 0.62, 7, 5, 0 }, { 0.78, 5, 4, 0 }, { 0.95, 2, 2, 0 }, { 1.2, 0, 1, 0 }, { 1.6, 0, 0, 0 } },
  ["spine_02"] = { { 0, 0, 0, 0 }, { 0.25, -1, -6, 0 }, { 0.45, -2, -8, 0 }, { 0.62, 4, 7, 0 }, { 0.78, 3, 6, 0 }, { 0.95, 1, 3, 0 }, { 1.6, 0, 0, 0 } },
  ["spine_03"] = { { 0, 0, 0, 0 }, { 0.25, -1, -10, 0 }, { 0.45, -2, -13, 0 }, { 0.62, 3, 14, 0 }, { 0.78, 2, 11, 0 }, { 0.95, 1, 5, 0 }, { 1.6, 0, 0, 0 } },
  ["neck"] = { { 0, 0, 0, 0 }, { 0.25, 1, 5, 0 }, { 0.45, 2, 6, 0 }, { 0.62, -2, -6, 0 }, { 0.78, -1, -4, 0 }, { 1.6, 0, 0, 0 } },
  ["head"] = { { 0, 0, 0, 0 }, { 0.25, 2, 6, 0 }, { 0.45, 3, 8, 0 }, { 0.62, -3, -8, 0 }, { 0.78, -2, -6, 0 }, { 1.6, 0, 0, 0 } },
  ["shoulder.r"] = { { 0, 0, 0, 0 }, { 0.25, 0, -3, 0 }, { 0.45, 0, -4, 0 }, { 0.62, 0, 10, 0 }, { 0.78, 0, 8, 0 }, { 1.6, 0, 0, 0 } },
  ["arm_stretch.r"] = { { 0, 0, 0, 0 }, { 0.25, 22, 0, -8 }, { 0.45, 26, 0, -10 }, { 0.62, -40, 25, 0 }, { 0.78, -32, 16, -6 }, { 0.95, -16, 8, -2 }, { 1.2, -4, 2, 0 }, { 1.6, 0, 0, 0 } },
  ["forearm_stretch.r"] = { { 0, 0, 0, 0 }, { 0.25, -30, 0, 0 }, { 0.45, -34, 0, 0 }, { 0.62, -20, 0, 0 }, { 0.78, -14, 0, 0 }, { 0.95, -8, 0, 0 }, { 1.6, 0, 0, 0 } },
  ["hand.r"] = { { 0, 0, 0, 0 }, { 0.25, 8, 0, 0 }, { 0.45, 10, 0, 0 }, { 0.62, -6, 0, 0 }, { 0.78, -4, 0, 0 }, { 1.6, 0, 0, 0 } },
  ["shoulder.l"] = { { 0, 0, 0, 0 }, { 0.25, 0, 3, 0 }, { 0.45, 0, 4, 0 }, { 0.62, 0, -6, 0 }, { 0.78, 0, -4, 0 }, { 1.6, 0, 0, 0 } },
  ["arm_stretch.l"] = { { 0, 0, 0, 0 }, { 0.25, -10, 0, 3 }, { 0.45, -14, 0, 4 }, { 0.62, 12, 0, 0 }, { 0.78, 10, 0, 0 }, { 0.95, 4, 0, 0 }, { 1.6, 0, 0, 0 } },
  ["forearm_stretch.l"] = { { 0, 0, 0, 0 }, { 0.25, -6, 0, 0 }, { 0.45, -8, 0, 0 }, { 0.62, 6, 0, 0 }, { 0.78, 5, 0, 0 }, { 1.6, 0, 0, 0 } },
  ["thigh_stretch.r"] = { { 0, 0, 0, 0 }, { 0.25, 5, 0, 0 }, { 0.45, 7, 0, 0 }, { 0.62, -8, 0, 0 }, { 0.78, -6, 0, 0 }, { 0.95, -2, 0, 0 }, { 1.6, 0, 0, 0 } },
  ["leg_stretch.r"] = { { 0, 0, 0, 0 }, { 0.25, 6, 0, 0 }, { 0.45, 9, 0, 0 }, { 0.62, 2, 0, 0 }, { 0.78, 4, 0, 0 }, { 1.6, 0, 0, 0 } },
  ["leg_stretch.l"] = { { 0, 0, 0, 0 }, { 0.45, 4, 0, 0 }, { 0.62, 8, 0, 0 }, { 0.78, 6, 0, 0 }, { 1.6, 0, 0, 0 } },
  ["thigh_stretch.l"] = { { 0, 0, 0, 0 }, { 0.45, 2, 0, 0 }, { 0.62, 3, 0, 0 }, { 0.78, 2, 0, 0 }, { 1.6, 0, 0, 0 } },
  ["foot.l"] = { { 0, 0, 0, 0 }, { 0.62, -8, 0, 0 }, { 0.78, -6, 0, 0 }, { 1.6, 0, 0, 0 } },
  ["foot.r"] = { { 0, 0, 0, 0 }, { 0.25, -10, 0, 0 }, { 0.45, -18, 0, 0 }, { 0.62, -4, 0, 0 }, { 1.6, 0, 0, 0 } },
  },
}

HIT_CLIP = { duration = 0.8, loop = false, ease = "linear", tracks = {
  ["spine_01"] = { { 0, 0, 0, 0 }, { 0.1, -9, 0, 0 }, { 0.22, -6, 2, 0 }, { 0.45, 3, -1, 0 }, { 0.8, 0, 0, 0 } },
  ["spine_02"] = { { 0, 0, 0, 0 }, { 0.1, -6, 0, 0 }, { 0.22, -4, 0, 0 }, { 0.45, 2, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["spine_03"] = { { 0, 0, 0, 0 }, { 0.1, -5, 0, 0 }, { 0.22, -3, 0, 0 }, { 0.45, 2, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["neck"] = { { 0, 0, 0, 0 }, { 0.1, 6, 0, 0 }, { 0.22, 4, 0, 0 }, { 0.45, -2, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["head"] = { { 0, 0, 0, 0 }, { 0.1, 8, 0, 0 }, { 0.22, 6, 0, 0 }, { 0.45, -3, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["shoulder.l"] = { { 0, 0, 0, 0 }, { 0.1, 0, -3, 6 }, { 0.22, 0, -2, 4 }, { 0.8, 0, 0, 0 } },
  ["shoulder.r"] = { { 0, 0, 0, 0 }, { 0.1, 0, 3, -6 }, { 0.22, 0, 2, -4 }, { 0.8, 0, 0, 0 } },
  ["arm_stretch.l"] = { { 0, 0, 0, 0 }, { 0.1, 10, 0, 10 }, { 0.22, 8, 0, 8 }, { 0.45, -2, 0, -2 }, { 0.8, 0, 0, 0 } },
  ["arm_stretch.r"] = { { 0, 0, 0, 0 }, { 0.1, 10, 0, -10 }, { 0.22, 8, 0, -8 }, { 0.45, -2, 0, 2 }, { 0.8, 0, 0, 0 } },
  ["forearm_stretch.l"] = { { 0, 0, 0, 0 }, { 0.1, 6, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["forearm_stretch.r"] = { { 0, 0, 0, 0 }, { 0.1, 6, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["thigh_stretch.l"] = { { 0, 0, 0, 0 }, { 0.1, 4, 0, 0 }, { 0.22, 2, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["thigh_stretch.r"] = { { 0, 0, 0, 0 }, { 0.1, 4, 0, 0 }, { 0.22, 2, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["leg_stretch.l"] = { { 0, 0, 0, 0 }, { 0.1, 9, 0, 0 }, { 0.22, 6, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["leg_stretch.r"] = { { 0, 0, 0, 0 }, { 0.1, 9, 0, 0 }, { 0.22, 6, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["foot.l"] = { { 0, 0, 0, 0 }, { 0.1, -4, 0, 0 }, { 0.8, 0, 0, 0 } },
  ["foot.r"] = { { 0, 0, 0, 0 }, { 0.1, -4, 0, 0 }, { 0.8, 0, 0, 0 } },
  },
}

local CLIPS = {
  Idle = IDLE_CLIP,
  Walk = WALK_CLIP,
  Attack = ATTACK_CLIP,
  Hit = HIT_CLIP,
}

local HIT_TIMES = {
  Attack = 0.62,
  Hit = 0.1,
}

-- 运行时状态全部保存在脚本实例内，多个模组实例彼此独立。
local boneTransforms = {}
local restRotations = {}
local currentRotations = {}
local worldRotations = {}
local foundCount = 0
local missingNames = ""
local rendererReady = false
local initialized = false
local ready = false
local statusReason = "not-initialized"

local actionName = "Idle"
local animTime = 0
local animSpeed = 1
local currentLoop = true
local blendElapsed = 0
local blendDuration = 0

local function normalizeBoneName(value)
  local name = string.lower(value or "")
  name = string.gsub(name, "%.x$", "")
  name = string.gsub(name, "_x$", "")
  name = string.gsub(name, "_l$", ".l")
  name = string.gsub(name, "_r$", ".r")
  name = string.gsub(name, "%s", "")
  return name
end

local function createIdentityList()
  local list = {}
  for i = 1, BONE_COUNT do
    list[i] = IDENTITY
  end
  return list
end

local function resolveClip(name)
  if type(name) ~= "string" then return nil end
  local key = string.lower(name)
  if key == "idle" then return "Idle" end
  if key == "walk" then return "Walk" end
  if key == "attack" then return "Attack" end
  if key == "hit" then return "Hit" end
  return nil
end

local function findRenderer()
  local modelGo = nil
  if runtimeScope ~= nil then
    modelGo = runtimeScope:GetGameObjectByPath("Armature/model")
  end
  local renderer = nil
  if modelGo ~= nil then
    renderer = modelGo:GetComponent(typeof(UnityEngine.SkinnedMeshRenderer))
  end
  if renderer == nil and self.gameObject ~= nil then
    renderer = self.gameObject:GetComponentInChildren(typeof(UnityEngine.SkinnedMeshRenderer))
  end
  return renderer
end

local function buildBoneMap(renderer)
  local map = {}
  if renderer == nil then return map end
  local bones = renderer.bones
  if bones == nil then return map end
  -- C# 数组按 0 到 Length-1 遍历，不能用 # 取长度。
  for i = 0, bones.Length - 1 do
    local bone = bones[i]
    if bone ~= nil then
      local key = normalizeBoneName(bone.name)
      if map[key] == nil then map[key] = bone end
    end
  end
  return map
end

local function initializeRig()
  initialized = true
  boneTransforms = {}
  restRotations = {}
  currentRotations = {}
  worldRotations = createIdentityList()
  foundCount = 0
  missingNames = ""

  if runtimeScope == nil then
    statusReason = "资源作用域不可用：" .. tostring(scopeReason)
    logger:error("rig init failed:", statusReason)
    return false
  end

  local renderer = findRenderer()
  rendererReady = renderer ~= nil
  if renderer ~= nil then
    pcall(function()
      renderer.updateWhenOffscreen = true
    end)
  end
  if renderer == nil then
    logger:warn("SkinnedMeshRenderer 未找到，将继续尝试按路径绑定骨骼")
  end

  local nameMap = buildBoneMap(renderer)
  local missing = {}
  for i = 1, BONE_COUNT do
    local def = BONE_DEFS[i]
    local bone = nameMap[normalizeBoneName(def.name)]
    if bone == nil then
      bone = runtimeScope:GetTransformByPath(def.path)
    end
    if bone ~= nil then
      boneTransforms[i] = bone
      restRotations[i] = bone.localRotation
      currentRotations[i] = bone.localRotation
      foundCount = foundCount + 1
    else
      missing[#missing + 1] = def.name
    end
  end

  if #missing > 0 then
    missingNames = table.concat(missing, ",")
    statusReason = "缺少骨骼：" .. missingNames
    logger:error("rig init failed:", statusReason, "found", foundCount, "/", BONE_COUNT)
    return false
  end

  if renderer == nil then
    statusReason = "未找到 SkinnedMeshRenderer"
    logger:error("rig init failed:", statusReason)
    return false
  end

  ready = true
  statusReason = ""
  logger:info("rig ready:", "bones", foundCount, "/", BONE_COUNT, "renderer", tostring(renderer.gameObject.name))
  return true
end

local function sampleBone(clip, boneName, t)
  local base = BASE[boneName]
  local bx, by, bz = 0, 0, 0
  if base ~= nil then
    bx, by, bz = base[1], base[2], base[3]
  end
  local track = clip.tracks[boneName]
  if track == nil then return bx, by, bz end

  local count = #track
  if t <= track[1][1] then
    local key = track[1]
    return bx + key[2], by + key[3], bz + key[4]
  end
  if t >= track[count][1] then
    local key = track[count]
    return bx + key[2], by + key[3], bz + key[4]
  end

  for j = 1, count - 1 do
    local a = track[j]
    local b = track[j + 1]
    if t <= b[1] then
      local span = b[1] - a[1]
      local f = 0
      if span > 0 then f = (t - a[1]) / span end
      if clip.ease == "smooth" then f = f * f * (3 - 2 * f) end
      return bx + a[2] + (b[2] - a[2]) * f,
             by + a[3] + (b[3] - a[3]) * f,
             bz + a[4] + (b[4] - a[4]) * f
    end
  end
  return bx, by, bz
end

local function applyPose(clip, t, blendWeight)
  for i = 1, BONE_COUNT do
    local def = BONE_DEFS[i]
    local parentWorld = IDENTITY
    if def.parent > 0 then parentWorld = worldRotations[def.parent] end
    local rest = restRotations[i]
    local baseWorld = parentWorld * rest
    local ox, oy, oz = sampleBone(clip, def.name, t)

    local targetWorld = baseWorld
    local targetLocal = rest
    if ox ~= 0 or oy ~= 0 or oz ~= 0 then
      targetWorld = Quaternion.Euler(ox, oy, oz) * baseWorld
      targetLocal = Quaternion.Inverse(parentWorld) * targetWorld
    end
    worldRotations[i] = targetWorld

    local current = currentRotations[i]
    if blendWeight < 1 then
      current = Quaternion.Slerp(current, targetLocal, blendWeight)
    else
      current = targetLocal
    end
    currentRotations[i] = current
    local bone = boneTransforms[i]
    if bone ~= nil then
      bone.localRotation = current
    end
  end
end

local function startAction(key, fade, restart, forceLoop)
  if ready ~= true then return false, statusReason end
  local clip = CLIPS[key]
  if clip == nil then return false, "unknown-action" end
  if actionName == key and restart ~= true then return true end

  actionName = key
  animTime = 0
  currentLoop = clip.loop
  if forceLoop ~= nil then currentLoop = forceLoop end
  blendElapsed = 0
  blendDuration = fade or DefaultFade
  if blendDuration == nil then blendDuration = 0.18 end
  if blendDuration < 0 then blendDuration = 0 end
  return true
end

function EnsureReady()
  if ready then return true end
  if initialized then return false, statusReason end
  local ok = initializeRig()
  return ok, statusReason
end

function Start()
  local ok = EnsureReady()
  if not ok then
    logger:warnOnce("rig-not-ready", "animation disabled:", statusReason)
    return
  end
  startAction("Idle", 0.35, true, true)
end

function OnEnable()
  if ready then
    startAction("Idle", 0.2, true, true)
  end
end

function OnDisable()
  if ready then
    for i = 1, BONE_COUNT do
      local bone = boneTransforms[i]
      if bone ~= nil and restRotations[i] ~= nil then
        bone.localRotation = restRotations[i]
        currentRotations[i] = restRotations[i]
      end
    end
    actionName = "Idle"
    animTime = 0
    blendElapsed = blendDuration
  end
end

function Update()
  if not ready then return end
  local clip = CLIPS[actionName]
  if clip == nil then return end

  local delta = clock.deltaTime * animSpeed
  animTime = animTime + delta

  if currentLoop then
    if animTime >= clip.duration then
      animTime = animTime % clip.duration
    end
  elseif animTime >= clip.duration then
    animTime = clip.duration
    local finished = actionName
    if finished ~= "Idle" then
      startAction("Idle", 0.25, true, true)
      logger:info("action finished:", finished)
    end
  end

  blendElapsed = blendElapsed + clock.deltaTime
  local blendWeight = 1
  if blendDuration > 0 and blendElapsed < blendDuration then
    local f = blendElapsed / blendDuration
    blendWeight = f * f * (3 - 2 * f)
  end

  local activeClip = CLIPS[actionName]
  if activeClip == nil then return end
  applyPose(activeClip, animTime, blendWeight)
end

function Play(name, opts)
  local key = resolveClip(name)
  if key == nil then
    logger:warnOnce("unknown-action-" .. tostring(name), "unknown action:", tostring(name))
    return false, "unknown-action"
  end
  opts = opts or {}
  if opts.speed ~= nil then SetSpeed(opts.speed) end
  return startAction(key, opts.fade, opts.restart == true, opts.loop)
end

function SetSpeed(value)
  if type(value) ~= "number" then return false end
  if value < 0.05 then value = 0.05 end
  if value > 4 then value = 4 end
  animSpeed = value
  return true
end

function GetAction()
  return actionName
end

function GetActionDuration(name)
  local key = resolveClip(name)
  if key == nil then return 0 end
  return CLIPS[key].duration
end

function GetHitTime(name)
  local key = resolveClip(name)
  if key == nil then return 0 end
  return HIT_TIMES[key] or 0
end

function GetRigStatus()
  return {
    ready = ready,
    reason = statusReason,
    rendererFound = rendererReady,
    boneCount = BONE_COUNT,
    foundCount = foundCount,
    missing = missingNames,
  }
end


Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="Idle",walk="Walk",attack="Attack",hit="Hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.boss=function(root,height)
local Play,Stop,Pause,Resume,SetSpeed,GetSpeed,GetAction,GetRigStatus,IsPlaying,GetActionDuration,GetHitTime,IsLooping,RegisterHitHandler,ClearHitHandler,Start,OnDisable,Update
local PlaybackSpeed=1
local AutoIdle=true
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 界门巨兽骨骼动画：逐骨骼驱动蒙皮，播放待机、重步行走、双拳砸地与受击

local UnityEngine = CS.UnityEngine
local Quaternion = CS.UnityEngine.Quaternion
local Time = clock
local RuntimeScope={from=function()return boundScope end}
local Logger = require("official.core.logger")

local logger = Logger.create("ms-boss-animation")
local runtimeScope, runtimeScopeReason = RuntimeScope.from(self)

-- 骨骼路径来自该 GLB 的实际节点树；只改局部旋转，不移动任何节点，因此没有根位移。
local BONE_KEYS = {
  "root.x", "spine_01.x", "spine_02.x", "spine_03.x", "neck.x", "head.x",
  "shoulder.l", "arm_stretch.l", "forearm_stretch.l", "hand.l",
  "shoulder.r", "arm_stretch.r", "forearm_stretch.r", "hand.r",
  "thigh_stretch.l", "leg_stretch.l", "foot.l",
  "thigh_stretch.r", "leg_stretch.r", "foot.r",
}

local ROOT_PATH = "InputSkeleton_Armature"
local REL_PATHS = {
  ["root.x"] = "root.x",
  ["spine_01.x"] = "root.x/spine_01.x",
  ["spine_02.x"] = "root.x/spine_01.x/spine_02.x",
  ["spine_03.x"] = "root.x/spine_01.x/spine_02.x/spine_03.x",
  ["neck.x"] = "root.x/spine_01.x/spine_02.x/spine_03.x/neck.x",
  ["head.x"] = "root.x/spine_01.x/spine_02.x/spine_03.x/neck.x/head.x",
  ["shoulder.l"] = "root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l",
  ["arm_stretch.l"] = "root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l",
  ["forearm_stretch.l"] = "root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l",
  ["hand.l"] = "root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l/hand.l",
  ["shoulder.r"] = "root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r",
  ["arm_stretch.r"] = "root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r",
  ["forearm_stretch.r"] = "root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r",
  ["hand.r"] = "root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r/hand.r",
  ["thigh_stretch.l"] = "root.x/thigh_stretch.l",
  ["leg_stretch.l"] = "root.x/thigh_stretch.l/leg_stretch.l",
  ["foot.l"] = "root.x/thigh_stretch.l/leg_stretch.l/foot.l",
  ["thigh_stretch.r"] = "root.x/thigh_stretch.r",
  ["leg_stretch.r"] = "root.x/thigh_stretch.r/leg_stretch.r",
  ["foot.r"] = "root.x/thigh_stretch.r/leg_stretch.r/foot.r",
}

-- 关键帧由该模型的真实腿长、关节方向与拳块位置逐帧求解后写入；
-- 角度为绕骨骼自身局部轴的度数，运行时按 rest * offset 应用。
-- 换算自 glTF 局部旋转：Unity 侧 (x, -y, -z)，与模型导入的坐标映射一致。
local CLIPS = {
  Idle = {
    duration = 4.0, loop = true,
    keys = {
      { t = 0, pose = { ["spine_01.x"]={0,0,-0.44}, ["spine_02.x"]={0,0,-0.24}, ["spine_03.x"]={0,0,-0.12}, ["arm_stretch.l"]={0,0,-2.5}, ["forearm_stretch.l"]={-1,0,0}, ["arm_stretch.r"]={0,0,2.5}, ["forearm_stretch.r"]={-1,0,0} } },
      { t = 1, pose = { ["spine_01.x"]={-0.81,0,-1.76}, ["spine_02.x"]={-0.63,0,-0.96}, ["spine_03.x"]={-0.36,0,-0.48}, ["neck.x"]={1.02,0,0}, ["head.x"]={1.52,0,0}, ["shoulder.l"]={0,0,-1.4}, ["arm_stretch.l"]={0,0,-4}, ["forearm_stretch.l"]={-2.2,0,0}, ["shoulder.r"]={0,0,1.4}, ["arm_stretch.r"]={0,0,4}, ["forearm_stretch.r"]={-2.2,0,0} } },
      { t = 2, pose = { ["spine_01.x"]={0.54,0,0.11}, ["spine_02.x"]={0.42,0,0.06}, ["spine_03.x"]={0.24,0,0.03}, ["neck.x"]={-0.7,0,0}, ["head.x"]={-1.06,0,0}, ["arm_stretch.l"]={0,0,-1.6}, ["forearm_stretch.l"]={-0.6,0,0}, ["arm_stretch.r"]={0,0,1.6}, ["forearm_stretch.r"]={-0.6,0,0} } },
      { t = 3, pose = { ["spine_01.x"]={-0.63,0,1.65}, ["spine_02.x"]={-0.49,0,0.9}, ["spine_03.x"]={-0.28,0,0.45}, ["neck.x"]={0.81,0,0}, ["head.x"]={1.21,0,0}, ["shoulder.l"]={0,0,1.2}, ["arm_stretch.l"]={0,0,-3.6}, ["forearm_stretch.l"]={-1.8,0,0}, ["shoulder.r"]={0,0,-1.2}, ["arm_stretch.r"]={0,0,3.6}, ["forearm_stretch.r"]={-1.8,0,0} } },
      { t = 4, pose = { ["spine_01.x"]={0,0,-0.44}, ["spine_02.x"]={0,0,-0.24}, ["spine_03.x"]={0,0,-0.12}, ["arm_stretch.l"]={0,0,-2.5}, ["forearm_stretch.l"]={-1,0,0}, ["arm_stretch.r"]={0,0,2.5}, ["forearm_stretch.r"]={-1,0,0} } },
    },
  },
  Walk = {
    duration = 1.8, loop = true,
    keys = {
      { t = 0, pose = { ["root.x"]={3,0,0}, ["spine_01.x"]={0.68,0,1.76}, ["spine_02.x"]={0.52,0,0.96}, ["spine_03.x"]={0.3,0,0.48}, ["neck.x"]={0.22,0,0}, ["head.x"]={0.33,0,0}, ["shoulder.l"]={0,0,-1.2}, ["arm_stretch.l"]={-9,0,-2.5}, ["forearm_stretch.l"]={-3,0,0}, ["shoulder.r"]={0,0,1.2}, ["arm_stretch.r"]={9,0,2.5}, ["forearm_stretch.r"]={-3,0,0}, ["thigh_stretch.l"]={13.25,0,0}, ["leg_stretch.l"]={4,0,0}, ["foot.l"]={-14,0,-2}, ["thigh_stretch.r"]={-6.25,0,0}, ["leg_stretch.r"]={2.5,0,0}, ["foot.r"]={6,0,-1} } },
      { t = 0.23, pose = { ["root.x"]={3,0,0}, ["spine_01.x"]={1.8,0,1.76}, ["spine_02.x"]={1.4,0,0.96}, ["spine_03.x"]={0.8,0,0.48}, ["neck.x"]={-0.08,0,0}, ["head.x"]={-0.12,0,0}, ["shoulder.l"]={0,0,-1.2}, ["arm_stretch.l"]={-9,0,-2.5}, ["forearm_stretch.l"]={-3,0,0}, ["shoulder.r"]={0,0,1.2}, ["arm_stretch.r"]={9,0,2.5}, ["forearm_stretch.r"]={-3,0,0}, ["thigh_stretch.l"]={8.75,0,0}, ["leg_stretch.l"]={3,0,0}, ["foot.l"]={-9,0,-1}, ["thigh_stretch.r"]={23.75,0,0}, ["leg_stretch.r"]={-60,0,0}, ["foot.r"]={35.76,0,4} } },
      { t = 0.45, pose = { ["root.x"]={3,0,0}, ["spine_01.x"]={1.8,0,1.76}, ["spine_02.x"]={1.4,0,0.96}, ["spine_03.x"]={0.8,0,0.48}, ["neck.x"]={-0.08,0,0}, ["head.x"]={-0.12,0,0}, ["shoulder.l"]={0,0,-1.2}, ["arm_stretch.l"]={-9,0,-2.5}, ["forearm_stretch.l"]={-3,0,0}, ["shoulder.r"]={0,0,1.2}, ["arm_stretch.r"]={9,0,2.5}, ["forearm_stretch.r"]={-3,0,0}, ["thigh_stretch.l"]={4.75,0,0}, ["foot.l"]={-2,0,-1}, ["thigh_stretch.r"]={30,0,0}, ["leg_stretch.r"]={-60,0,0}, ["foot.r"]={28,0,5} } },
      { t = 0.68, pose = { ["root.x"]={3,0,0}, ["spine_01.x"]={1.8,0,1.76}, ["spine_02.x"]={1.4,0,0.96}, ["spine_03.x"]={0.8,0,0.48}, ["neck.x"]={-0.08,0,0}, ["head.x"]={-0.12,0,0}, ["shoulder.l"]={0,0,-1.2}, ["arm_stretch.l"]={-9,0,-2.5}, ["forearm_stretch.l"]={-3,0,0}, ["shoulder.r"]={0,0,1.2}, ["arm_stretch.r"]={9,0,2.5}, ["forearm_stretch.r"]={-3,0,0}, ["thigh_stretch.l"]={-1.25,0,0}, ["leg_stretch.l"]={2,0,0}, ["foot.l"]={2,0,0}, ["thigh_stretch.r"]={38,0,0}, ["leg_stretch.r"]={-60,0,0}, ["foot.r"]={21.76,0,7} } },
      { t = 0.9, pose = { ["root.x"]={3,0,0}, ["spine_01.x"]={0.68,0,-1.76}, ["spine_02.x"]={0.52,0,-0.96}, ["spine_03.x"]={0.3,0,-0.48}, ["neck.x"]={0.22,0,0}, ["head.x"]={0.33,0,0}, ["shoulder.l"]={0,0,-1.2}, ["arm_stretch.l"]={9,0,-2.5}, ["forearm_stretch.l"]={-3,0,0}, ["shoulder.r"]={0,0,1.2}, ["arm_stretch.r"]={-9,0,2.5}, ["forearm_stretch.r"]={-3,0,0}, ["thigh_stretch.l"]={-6.25,0,0}, ["leg_stretch.l"]={2.5,0,0}, ["foot.l"]={6,0,1}, ["thigh_stretch.r"]={13.25,0,0}, ["leg_stretch.r"]={4,0,0}, ["foot.r"]={-14,0,2} } },
      { t = 1.12, pose = { ["root.x"]={3,0,0}, ["spine_01.x"]={1.8,0,-1.76}, ["spine_02.x"]={1.4,0,-0.96}, ["spine_03.x"]={0.8,0,-0.48}, ["neck.x"]={-0.08,0,0}, ["head.x"]={-0.12,0,0}, ["shoulder.l"]={0,0,-1.2}, ["arm_stretch.l"]={9,0,-2.5}, ["forearm_stretch.l"]={-3,0,0}, ["shoulder.r"]={0,0,1.2}, ["arm_stretch.r"]={-9,0,2.5}, ["forearm_stretch.r"]={-3,0,0}, ["thigh_stretch.l"]={23.5,0,0}, ["leg_stretch.l"]={-60,0,0}, ["foot.l"]={35.76,0,-4}, ["thigh_stretch.r"]={8.75,0,0}, ["leg_stretch.r"]={3,0,0}, ["foot.r"]={-9,0,1} } },
      { t = 1.35, pose = { ["root.x"]={3,0,0}, ["spine_01.x"]={1.8,0,-1.76}, ["spine_02.x"]={1.4,0,-0.96}, ["spine_03.x"]={0.8,0,-0.48}, ["neck.x"]={-0.08,0,0}, ["head.x"]={-0.12,0,0}, ["shoulder.l"]={0,0,-1.2}, ["arm_stretch.l"]={9,0,-2.5}, ["forearm_stretch.l"]={-3,0,0}, ["shoulder.r"]={0,0,1.2}, ["arm_stretch.r"]={-9,0,2.5}, ["forearm_stretch.r"]={-3,0,0}, ["thigh_stretch.l"]={30,0,0}, ["leg_stretch.l"]={-60,0,0}, ["foot.l"]={28,0,-5}, ["thigh_stretch.r"]={6.5,0,0}, ["leg_stretch.r"]={-4,0,0}, ["foot.r"]={1,0,1} } },
      { t = 1.57, pose = { ["root.x"]={3,0,0}, ["spine_01.x"]={1.8,0,-1.76}, ["spine_02.x"]={1.4,0,-0.96}, ["spine_03.x"]={0.8,0,-0.48}, ["neck.x"]={-0.08,0,0}, ["head.x"]={-0.12,0,0}, ["shoulder.l"]={0,0,-1.2}, ["arm_stretch.l"]={9,0,-2.5}, ["forearm_stretch.l"]={-3,0,0}, ["shoulder.r"]={0,0,1.2}, ["arm_stretch.r"]={-9,0,2.5}, ["forearm_stretch.r"]={-3,0,0}, ["thigh_stretch.l"]={38.75,0,0}, ["leg_stretch.l"]={-60,0,0}, ["foot.l"]={20.76,0,-7}, ["thigh_stretch.r"]={-1.25,0,0}, ["leg_stretch.r"]={2,0,0}, ["foot.r"]={2,0,0} } },
      { t = 1.8, pose = { ["root.x"]={3,0,0}, ["spine_01.x"]={0.68,0,1.76}, ["spine_02.x"]={0.52,0,0.96}, ["spine_03.x"]={0.3,0,0.48}, ["neck.x"]={0.22,0,0}, ["head.x"]={0.33,0,0}, ["shoulder.l"]={0,0,-1.2}, ["arm_stretch.l"]={-9,0,-2.5}, ["forearm_stretch.l"]={-3,0,0}, ["shoulder.r"]={0,0,1.2}, ["arm_stretch.r"]={9,0,2.5}, ["forearm_stretch.r"]={-3,0,0}, ["thigh_stretch.l"]={13.25,0,0}, ["leg_stretch.l"]={4,0,0}, ["foot.l"]={-14,0,-2}, ["thigh_stretch.r"]={-6.25,0,0}, ["leg_stretch.r"]={2.5,0,0}, ["foot.r"]={6,0,-1} } },
    },
  },
  Attack = {
    duration = 2.7, loop = false, hitTime = 1.42, autoReturn = true,
    keys = {
      { t = 0, pose = { ["spine_01.x"]={0,0,-0.44}, ["spine_02.x"]={0,0,-0.24}, ["spine_03.x"]={0,0,-0.12}, ["arm_stretch.l"]={0,0,-2.5}, ["forearm_stretch.l"]={-1,0,0}, ["arm_stretch.r"]={0,0,2.5}, ["forearm_stretch.r"]={-1,0,0} } },
      { t = 0.35, pose = { ["root.x"]={6,0,0}, ["spine_01.x"]={1.8,0,0}, ["spine_02.x"]={1.4,0,0}, ["spine_03.x"]={0.8,0,0}, ["neck.x"]={0.32,0,0}, ["head.x"]={0.48,0,0}, ["shoulder.l"]={-12,0,0}, ["arm_stretch.l"]={-10,0,-8}, ["forearm_stretch.l"]={-4,0,0}, ["shoulder.r"]={-12,0,0}, ["arm_stretch.r"]={-10,0,8}, ["forearm_stretch.r"]={-4,0,0}, ["thigh_stretch.l"]={8.25,0,0}, ["leg_stretch.l"]={-4,0,0}, ["foot.l"]={2,0,-1}, ["thigh_stretch.r"]={6.5,0,0}, ["foot.r"]={0,0,1} } },
      { t = 0.85, pose = { ["root.x"]={-8,0,0}, ["spine_01.x"]={-4.5,0,0}, ["spine_02.x"]={-3.5,0,0}, ["spine_03.x"]={-2,0,0}, ["neck.x"]={4.4,0,0}, ["head.x"]={6.6,0,0}, ["shoulder.l"]={-20,0,-2}, ["arm_stretch.l"]={-15,0,-45}, ["forearm_stretch.l"]={-5,0,-25}, ["hand.l"]={-5,0,0}, ["shoulder.r"]={-20,0,2}, ["arm_stretch.r"]={-15,0,45}, ["forearm_stretch.r"]={-5,0,25}, ["hand.r"]={-5,0,0}, ["thigh_stretch.l"]={-10.5,0,0}, ["leg_stretch.l"]={4,0,0}, ["foot.l"]={-2,0,1}, ["thigh_stretch.r"]={-10.5,0,0}, ["leg_stretch.r"]={4,0,0}, ["foot.r"]={-2,0,-1} } },
      { t = 1.1, pose = { ["root.x"]={-9,0,0}, ["spine_01.x"]={-5.4,0,0}, ["spine_02.x"]={-4.2,0,0}, ["spine_03.x"]={-2.4,0,0}, ["neck.x"]={5.04,0,0}, ["head.x"]={7.56,0,0}, ["shoulder.l"]={-22,0,-2}, ["arm_stretch.l"]={-16,0,-48}, ["forearm_stretch.l"]={-6,0,-27}, ["hand.l"]={-6,0,0}, ["shoulder.r"]={-22,0,2}, ["arm_stretch.r"]={-16,0,48}, ["forearm_stretch.r"]={-6,0,27}, ["hand.r"]={-6,0,0}, ["thigh_stretch.l"]={-10.5,0,0}, ["leg_stretch.l"]={1.5,0,0}, ["foot.l"]={0,0,1}, ["thigh_stretch.r"]={-10.5,0,0}, ["leg_stretch.r"]={1.5,0,0}, ["foot.r"]={0,0,-1} } },
      { t = 1.42, pose = { ["root.x"]={30,0,0}, ["spine_01.x"]={9.9,0,0}, ["spine_02.x"]={7.7,0,0}, ["spine_03.x"]={4.4,0,0}, ["neck.x"]={-7.44,0,0}, ["head.x"]={-11.16,0,0}, ["shoulder.l"]={45,0,0}, ["arm_stretch.l"]={25,0,35}, ["forearm_stretch.l"]={-10,0,10}, ["hand.l"]={-35,0,-25}, ["shoulder.r"]={45,0,0}, ["arm_stretch.r"]={25,0,-35}, ["forearm_stretch.r"]={-10,0,-10}, ["hand.r"]={-35,0,25}, ["thigh_stretch.l"]={32.75,0,0}, ["foot.l"]={-2,0,-4}, ["thigh_stretch.r"]={32.75,0,0}, ["foot.r"]={-2,0,4} } },
      { t = 1.55, pose = { ["root.x"]={33,0,0}, ["spine_01.x"]={10.8,0,0}, ["spine_02.x"]={8.4,0,0}, ["spine_03.x"]={4.8,0,0}, ["neck.x"]={-8.08,0,0}, ["head.x"]={-12.12,0,0}, ["shoulder.l"]={50,0,0}, ["arm_stretch.l"]={28,0,40}, ["forearm_stretch.l"]={-12,0,12}, ["hand.l"]={-38,0,-28}, ["shoulder.r"]={50,0,0}, ["arm_stretch.r"]={28,0,-40}, ["forearm_stretch.r"]={-12,0,-12}, ["hand.r"]={-38,0,28}, ["thigh_stretch.l"]={35,0,0}, ["leg_stretch.l"]={2.5,0,0}, ["foot.l"]={-4,0,-4}, ["thigh_stretch.r"]={34.75,0,0}, ["leg_stretch.r"]={3,0,0}, ["foot.r"]={-4,0,4} } },
      { t = 1.85, pose = { ["root.x"]={12,0,0}, ["spine_01.x"]={3.6,0,0}, ["spine_02.x"]={2.8,0,0}, ["spine_03.x"]={1.6,0,0}, ["neck.x"]={-2.56,0,0}, ["head.x"]={-3.84,0,0}, ["shoulder.l"]={20,0,0}, ["arm_stretch.l"]={10,0,10}, ["forearm_stretch.l"]={-4,0,0}, ["shoulder.r"]={20,0,0}, ["arm_stretch.r"]={10,0,-10}, ["forearm_stretch.r"]={-4,0,0}, ["thigh_stretch.l"]={9,0,0}, ["leg_stretch.l"]={9.5,0,0}, ["foot.l"]={-7,0,-1}, ["thigh_stretch.r"]={8.75,0,0}, ["leg_stretch.r"]={10,0,0}, ["foot.r"]={-7,0,1} } },
      { t = 2.3, pose = { ["root.x"]={2,0,0}, ["spine_01.x"]={0.45,0,0}, ["spine_02.x"]={0.35,0,0}, ["spine_03.x"]={0.2,0,0}, ["neck.x"]={-0.12,0,0}, ["head.x"]={-0.18,0,0}, ["arm_stretch.l"]={0,0,-4}, ["forearm_stretch.l"]={-1,0,0}, ["arm_stretch.r"]={0,0,4}, ["forearm_stretch.r"]={-1,0,0}, ["thigh_stretch.l"]={1.5,0,0}, ["leg_stretch.l"]={1.5,0,0}, ["foot.l"]={-1,0,0}, ["thigh_stretch.r"]={1.5,0,0}, ["leg_stretch.r"]={1.5,0,0}, ["foot.r"]={-1,0,0} } },
      { t = 2.7, pose = { ["spine_01.x"]={0,0,-0.44}, ["spine_02.x"]={0,0,-0.24}, ["spine_03.x"]={0,0,-0.12}, ["arm_stretch.l"]={0,0,-2.5}, ["forearm_stretch.l"]={-1,0,0}, ["arm_stretch.r"]={0,0,2.5}, ["forearm_stretch.r"]={-1,0,0} } },
    },
  },
  Hit = {
    duration = 0.9, loop = false, autoReturn = true,
    keys = {
      { t = 0, pose = { ["spine_01.x"]={0,0,-0.44}, ["spine_02.x"]={0,0,-0.24}, ["spine_03.x"]={0,0,-0.12}, ["arm_stretch.l"]={0,0,-2.5}, ["forearm_stretch.l"]={-1,0,0}, ["arm_stretch.r"]={0,0,2.5}, ["forearm_stretch.r"]={-1,0,0} } },
      { t = 0.08, pose = { ["root.x"]={-4,0,0}, ["spine_01.x"]={-4.05,0,0}, ["spine_02.x"]={-3.15,0,0}, ["spine_03.x"]={-1.8,0,0}, ["neck.x"]={-2.12,0,0}, ["head.x"]={-3.18,0,0}, ["shoulder.l"]={-8,0,0}, ["arm_stretch.l"]={0,0,-14}, ["forearm_stretch.l"]={0,0,-8}, ["shoulder.r"]={-8,0,0}, ["arm_stretch.r"]={0,0,14}, ["forearm_stretch.r"]={0,0,8}, ["thigh_stretch.l"]={-5.25,0,0}, ["leg_stretch.l"]={2,0,0}, ["foot.l"]={-1,0,1}, ["thigh_stretch.r"]={-5.25,0,0}, ["leg_stretch.r"]={2,0,0}, ["foot.r"]={-1,0,-1} } },
      { t = 0.2, pose = { ["root.x"]={-7,0,0}, ["spine_01.x"]={-6.75,0,0}, ["spine_02.x"]={-5.25,0,0}, ["spine_03.x"]={-3,0,0}, ["neck.x"]={-3.4,0,0}, ["head.x"]={-5.1,0,0}, ["shoulder.l"]={-12,0,0}, ["arm_stretch.l"]={0,0,-20}, ["forearm_stretch.l"]={0,0,-10}, ["hand.l"]={-5,0,0}, ["shoulder.r"]={-12,0,0}, ["arm_stretch.r"]={0,0,20}, ["forearm_stretch.r"]={0,0,10}, ["hand.r"]={-5,0,0}, ["thigh_stretch.l"]={-8.75,0,0}, ["leg_stretch.l"]={2.5,0,0}, ["foot.l"]={-1,0,1}, ["thigh_stretch.r"]={-8.5,0,0}, ["leg_stretch.r"]={2,0,0}, ["foot.r"]={-1,0,-1} } },
      { t = 0.4, pose = { ["root.x"]={1,0,0}, ["spine_01.x"]={1.8,0,0}, ["spine_02.x"]={1.4,0,0}, ["spine_03.x"]={0.8,0,0}, ["neck.x"]={0.32,0,0}, ["head.x"]={0.48,0,0}, ["arm_stretch.l"]={0,0,-6}, ["forearm_stretch.l"]={-2,0,0}, ["arm_stretch.r"]={0,0,6}, ["forearm_stretch.r"]={-2,0,0}, ["thigh_stretch.l"]={-3.5,0,0}, ["leg_stretch.l"]={10.5,0,0}, ["foot.l"]={-6,0,0}, ["thigh_stretch.r"]={-2.5,0,0}, ["leg_stretch.r"]={8,0,0}, ["foot.r"]={-5,0,0} } },
      { t = 0.62, pose = { ["root.x"]={0.5,0,0}, ["spine_01.x"]={-0.45,0,0}, ["spine_02.x"]={-0.35,0,0}, ["spine_03.x"]={-0.2,0,0}, ["neck.x"]={-0.28,0,0}, ["head.x"]={-0.42,0,0}, ["arm_stretch.l"]={0,0,-2.5}, ["forearm_stretch.l"]={-1,0,0}, ["arm_stretch.r"]={0,0,2.5}, ["forearm_stretch.r"]={-1,0,0}, ["thigh_stretch.l"]={3.75,0,0}, ["leg_stretch.l"]={-7.5,0,0}, ["foot.l"]={4,0,0}, ["thigh_stretch.r"]={0.5,0,0} } },
      { t = 0.9, pose = { ["spine_01.x"]={0,0,-0.44}, ["spine_02.x"]={0,0,-0.24}, ["spine_03.x"]={0,0,-0.12}, ["arm_stretch.l"]={0,0,-2.5}, ["forearm_stretch.l"]={-1,0,0}, ["arm_stretch.r"]={0,0,2.5}, ["forearm_stretch.r"]={-1,0,0} } },
    },
  },
}

local bones = {}
local bonesFound = 0
local applied = {}
local fadeFrom = {}
local workPose = {}
local ready = false

local currentName = nil
local currentClip = nil
local clipTime = 0
local playing = false
local looping = false
local hitFired = false
local fadeLeft = 0
local fadeDuration = 0
local baseSpeed = 1
local onComplete = nil
local onHit = nil
local hitHandler = nil
local pendingPlay = nil
local autoReturnEnabled = true

local function copyPose(src, dst)
  for i = 1, #BONE_KEYS do
    local key = BONE_KEYS[i]
    local s = src[key]
    local d = dst[key]
    if s ~= nil then
      d[1] = s[1]
      d[2] = s[2]
      d[3] = s[3]
    else
      d[1] = 0
      d[2] = 0
      d[3] = 0
    end
  end
end

local function clearPose(dst)
  for i = 1, #BONE_KEYS do
    local d = dst[BONE_KEYS[i]]
    d[1] = 0
    d[2] = 0
    d[3] = 0
  end
end

local function sampleClip(clip, time, out)
  local keys = clip.keys
  local count = #keys
  clearPose(out)
  if count == 0 then return end

  local index = 1
  while index < count - 1 and time > keys[index + 1].t do
    index = index + 1
  end
  local first = keys[index]
  local second = keys[index + 1]
  if second == nil then second = first end

  local span = second.t - first.t
  local u = 0
  if span > 0.00001 then
    u = (time - first.t) / span
  end
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  local s = u * u * (3 - 2 * u)

  for i = 1, #BONE_KEYS do
    local key = BONE_KEYS[i]
    local a = first.pose[key]
    local b = second.pose[key]
    local ax, ay, az = 0, 0, 0
    local bx, by, bz = 0, 0, 0
    if a ~= nil then ax, ay, az = a[1], a[2], a[3] end
    if b ~= nil then bx, by, bz = b[1], b[2], b[3] end
    local target = out[key]
    target[1] = ax + (bx - ax) * s
    target[2] = ay + (by - ay) * s
    target[3] = az + (bz - az) * s
  end
end

local function applyPose(pose)
  for i = 1, #BONE_KEYS do
    local bone = bones[i]
    if bone ~= nil then
      local angle = pose[BONE_KEYS[i]]
      bone.transform.localRotation = bone.rest * Quaternion.Euler(angle[1], angle[2], angle[3])
    end
  end
end

local function finishClip()
  playing = false
  local callback = onComplete
  onComplete = nil
  onHit = nil
  if callback ~= nil then
    pcall(callback)
  end
  if autoReturnEnabled and currentName ~= nil and currentName ~= "Idle" then
    Play("Idle", { fade = 0.22 })
  end
end

local function startClip(name, opts)
  opts = opts or {}
  local clip = CLIPS[name]
  if clip == nil then
    logger:warnOnce("unknown-action-" .. tostring(name), "未知动作", name)
    return false
  end

  copyPose(applied, fadeFrom)
  fadeDuration = opts.fade or 0.18
  if fadeDuration < 0 then fadeDuration = 0 end
  fadeLeft = fadeDuration

  currentName = name
  currentClip = clip
  clipTime = 0
  playing = true
  looping = opts.loop
  if looping == nil then looping = clip.loop == true end
  hitFired = false
  onComplete = opts.onComplete
  onHit = opts.onHit
  autoReturnEnabled = opts.autoReturn
  if autoReturnEnabled == nil then autoReturnEnabled = clip.autoReturn == true end
  if opts.speed ~= nil and opts.speed > 0 then
    baseSpeed = opts.speed
  end
  return true
end

for i = 1, #BONE_KEYS do
  applied[BONE_KEYS[i]] = { 0, 0, 0 }
  fadeFrom[BONE_KEYS[i]] = { 0, 0, 0 }
  workPose[BONE_KEYS[i]] = { 0, 0, 0 }
end

-- 播放指定动作。opts: loop, speed, fade, autoReturn, onComplete, onHit。
function Play(name, opts)
  if name == nil or CLIPS[name] == nil then return false end
  if not ready then
    pendingPlay = { name = name, opts = opts }
    return true
  end
  return startClip(name, opts)
end

function Stop(fade)
  return Play("Idle", { fade = fade })
end

function Pause()
  playing = false
end

function Resume()
  if currentClip ~= nil then playing = true end
end

function SetSpeed(value)
  if value ~= nil and value > 0 then baseSpeed = value end
end

function GetSpeed()
  return baseSpeed
end

function GetAction()
  return currentName or "none"
end

function GetRigStatus()
  return bonesFound, #BONE_KEYS
end

function IsPlaying(name)
  if not playing then return false end
  if name == nil then return true end
  return currentName == name
end

function GetActionDuration(name)
  local clip = CLIPS[name]
  if clip == nil then return 0 end
  return clip.duration
end

function GetHitTime(name)
  local clip = CLIPS[name]
  if clip == nil or clip.hitTime == nil then return 0 end
  return clip.hitTime
end

function IsLooping(name)
  local clip = CLIPS[name]
  if clip == nil then return false end
  return clip.loop == true
end

function RegisterHitHandler(fn)
  hitHandler = fn
end

function ClearHitHandler()
  hitHandler = nil
end

function Start()
  if runtimeScope == nil then
    logger:warnOnce("scope-missing", "无法取得资源上下文", tostring(runtimeScopeReason))
    return
  end

  local prefixPath = true
  for i = 1, #BONE_KEYS do
    local key = BONE_KEYS[i]
    local transform, reason = runtimeScope:GetTransformByPath(ROOT_PATH .. "/" .. REL_PATHS[key])
    if transform == nil then
      -- 兼容导入器折叠同名外层节点的情况；两条路径都失败时如实记录，不静默隐藏。
      transform, reason = runtimeScope:GetTransformByPath(REL_PATHS[key])
      prefixPath = false
    end
    if transform == nil then
      logger:warnOnce("bone-missing-" .. key, "缺少骨骼", key, tostring(reason))
    else
      bones[i] = { transform = transform, rest = transform.localRotation }
      bonesFound = bonesFound + 1
    end
  end
  ready = true
  logger:info("骨骼已载入", "找到=" .. tostring(bonesFound) .. "/" .. tostring(#BONE_KEYS), "路径前缀=" .. tostring(prefixPath))

  baseSpeed = PlaybackSpeed
  if baseSpeed == nil or baseSpeed <= 0 then baseSpeed = 1 end

  if pendingPlay ~= nil then
    local pending = pendingPlay
    pendingPlay = nil
    startClip(pending.name, pending.opts)
    return
  end

  if AutoIdle ~= false then
    startClip("Idle", { fade = 0 })
  end
end

function OnDisable()
  -- 组件停用时恢复绑定姿势，避免下次启用时骨骼停在旧动作上。
  if not ready then return end
  for i = 1, #BONE_KEYS do
    local bone = bones[i]
    if bone ~= nil then
      bone.transform.localRotation = bone.rest
    end
  end
end

function Update()
  if not ready or not playing or currentClip == nil then return end

  local dt = clock.deltaTime * baseSpeed
  if dt <= 0 then return end

  local previous = clipTime
  local nextTime = clipTime + dt
  local duration = currentClip.duration
  local finished = false
  local looped = false

  if looping then
    if nextTime >= duration then
      nextTime = nextTime % duration
      looped = true
      hitFired = false
    end
  elseif nextTime >= duration then
    nextTime = duration
    finished = true
  end

  clipTime = nextTime

  if currentClip.hitTime ~= nil and not hitFired and not finished and not looped then
    local hit = currentClip.hitTime
    if previous < hit and nextTime >= hit then
      hitFired = true
      if onHit ~= nil then
        pcall(onHit)
      end
      if hitHandler ~= nil then
        pcall(hitHandler, currentName)
      end
    end
  end

  sampleClip(currentClip, clipTime, workPose)
  if fadeLeft > 0 then
    local fadeRatio = 1
    if fadeDuration > 0.00001 then
      fadeRatio = 1 - (fadeLeft / fadeDuration)
    end
    if fadeRatio < 0 then fadeRatio = 0 elseif fadeRatio > 1 then fadeRatio = 1 end
    local smooth = fadeRatio * fadeRatio * (3 - 2 * fadeRatio)
    for i = 1, #BONE_KEYS do
      local key = BONE_KEYS[i]
      local from = fadeFrom[key]
      local target = workPose[key]
      target[1] = from[1] + (target[1] - from[1]) * smooth
      target[2] = from[2] + (target[2] - from[2]) * smooth
      target[3] = from[3] + (target[3] - from[3]) * smooth
    end
    fadeLeft = fadeLeft - dt
  end

  applyPose(workPose)
  copyPose(workPose, applied)

  if finished then
    finishClip()
  end
end

Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="Idle",walk="Walk",attack="Attack",hit="Hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.basic=function(root,height)
local Play,SetSpeed,GetAction,GetActionDuration,GetHitTime,GetRigStatus,Start,Update,OnDisable,OnDestroy
local StepLength=0.12
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 裂隙魔物动画版：逐骨骼驱动待机 / 行走 / 攻击 / 受击四套动作

local Logger = require("official.core.logger")
local RuntimeScope={from=function()return boundScope end}

local UnityEngine = CS.UnityEngine
local Time = clock
local Vector3 = CS.UnityEngine.Vector3
local Quaternion = CS.UnityEngine.Quaternion

local logger = Logger.create("ms-basic-animated")
local runtimeScope, runtimeScopeReason = RuntimeScope.from(self)

local SKELETON_ROOT = "Armature/root.x"
local SPINE_03 = SKELETON_ROOT .. "/spine_01.x/spine_02.x/spine_03.x"

local BONE_PATHS = {
  { "hips", SKELETON_ROOT },
  { "spine1", SKELETON_ROOT .. "/spine_01.x" },
  { "spine2", SKELETON_ROOT .. "/spine_01.x/spine_02.x" },
  { "spine3", SPINE_03 },
  { "neck", SPINE_03 .. "/neck.x" },
  { "head", SPINE_03 .. "/neck.x/head.x" },
  { "shoulderL", SPINE_03 .. "/shoulder.l" },
  { "armL", SPINE_03 .. "/shoulder.l/arm_stretch.l" },
  { "forearmL", SPINE_03 .. "/shoulder.l/arm_stretch.l/forearm_stretch.l" },
  { "handL", SPINE_03 .. "/shoulder.l/arm_stretch.l/forearm_stretch.l/hand.l" },
  { "shoulderR", SPINE_03 .. "/shoulder.r" },
  { "armR", SPINE_03 .. "/shoulder.r/arm_stretch.r" },
  { "forearmR", SPINE_03 .. "/shoulder.r/arm_stretch.r/forearm_stretch.r" },
  { "handR", SPINE_03 .. "/shoulder.r/arm_stretch.r/forearm_stretch.r/hand.r" },
  { "thighL", SKELETON_ROOT .. "/thigh_stretch.l" },
  { "shinL", SKELETON_ROOT .. "/thigh_stretch.l/leg_stretch.l" },
  { "footL", SKELETON_ROOT .. "/thigh_stretch.l/leg_stretch.l/foot.l" },
  { "toesL", SKELETON_ROOT .. "/thigh_stretch.l/leg_stretch.l/foot.l/toes_01.l" },
  { "thighR", SKELETON_ROOT .. "/thigh_stretch.r" },
  { "shinR", SKELETON_ROOT .. "/thigh_stretch.r/leg_stretch.r" },
  { "footR", SKELETON_ROOT .. "/thigh_stretch.r/leg_stretch.r/foot.r" },
  { "toesR", SKELETON_ROOT .. "/thigh_stretch.r/leg_stretch.r/foot.r/toes_01.r" },
}

local SMOOTH_RATE = 16
local WALK_KEYS = {
  { thigh = -22, knee = 6, toe = 0, arm = 14 },
  { thigh = -16, knee = 10, toe = 0, arm = 10 },
  { thigh = -4, knee = 6, toe = 0, arm = 3 },
  { thigh = 12, knee = 12, toe = 12, arm = -8 },
  { thigh = 20, knee = 32, toe = -6, arm = -13 },
  { thigh = 6, knee = 38, toe = -12, arm = -4 },
  { thigh = -12, knee = 22, toe = -8, arm = 8 },
  { thigh = -20, knee = 10, toe = -2, arm = 13 },
}
-- 行走抬升表：按相位抬髋，抵消支撑脚入地，保持脚底贴地
local WALK_LIFT = {
  0.0050, 0.0027, 0.0018, 0.0007, 0.0, 0.0110, 0.0188, 0.0207,
  0.0230, 0.0180, 0.0118, 0.0056, 0.0010, 0.0133, 0.0215, 0.0039,
}

local bones = {}
local boneOrder = {}
local pose = {}
local smooth = {}
local hipsUpLocal = nil
local hipsBasePosition = nil
local foundBones = 0

local ready = false
local elapsed = 0
local walkPhase = 0
local walkSpeed = 1.0
local currentAction = "idle"
local locomotion = "idle"
local actionTime = 0
local smoothLift = 0
local returning = false

local function makeStance()
  return {
    thighL = { -4, 0 }, shinL = { 8, 0 }, footL = { -4, 0 },
    thighR = { -4, 0 }, shinR = { 8, 0 }, footR = { -4, 0 },
    forearmL = { 5, 0 }, forearmR = { 5, 0 },
  }
end

local function mergePose(base, extra)
  local result = {}
  for key, value in pairs(base) do
    result[key] = { value[1], value[2] }
  end
  for key, value in pairs(extra) do
    result[key] = { value[1], value[2] }
  end
  return result
end

local IDLE_KEYS = {
  { time = 0.0, lift = 0.0005, pose = makeStance() },
  { time = 0.9, lift = 0.0005, pose = mergePose(makeStance(), {
    spine2 = { 1.5, 0 }, spine3 = { 1.2, 0 }, neck = { -0.8, 0 }, head = { -0.8, 1.5 },
    armL = { 1.8, 0 }, armR = { 1.8, 0 }, forearmL = { 6, 0 }, forearmR = { 6, 0 }, hips = { 0, 1 },
  }) },
  { time = 1.8, lift = 0.0005, pose = mergePose(makeStance(), {
    spine2 = { 0.3, 0 }, spine3 = { 0.2, 0 }, head = { -0.2, 0 },
  }) },
  { time = 2.7, lift = 0.0008, pose = mergePose(makeStance(), {
    thighL = { -2, 0 }, shinL = { 6, 0 }, thighR = { -6, 0 }, shinR = { 10, 0 },
    hips = { 0, -2 }, spine3 = { 0.6, 2 }, head = { 0, -2.5 },
    armL = { -1, 0 }, armR = { 1, 0 }, forearmL = { 5, 0 }, forearmR = { 5, 0 },
  }) },
}
local IDLE_DURATION = 3.6

local ATTACK_KEYS = {
  { time = 0.00, lift = 0.0005, pose = mergePose(makeStance(), {}) },
  { time = 0.14, lift = 0.0007, pose = mergePose(makeStance(), {
    thighL = { -8, 0 }, shinL = { 13, 0 }, footL = { -5, 0 },
    thighR = { -7, 0 }, shinR = { 12, 0 }, footR = { -5, 0 },
    spine1 = { -2, -2 }, spine3 = { -2, -6 }, hips = { 0, -3 }, head = { -2, -4 },
    armR = { 22, 0 }, forearmR = { 30, 0 }, armL = { -8, 0 }, forearmL = { 20, 0 },
  }) },
  { time = 0.30, lift = 0.0006, pose = mergePose(makeStance(), {
    thighL = { -7, 0 }, shinL = { 12, 0 }, footL = { -5, 0 },
    thighR = { -6, 0 }, shinR = { 11, 0 }, footR = { -5, 0 },
    spine1 = { -4, 0 }, spine3 = { -4, -12 }, hips = { 0, -6 }, head = { -3, -8 },
    armR = { 45, 0 }, forearmR = { 55, 0 }, armL = { -14, 0 }, forearmL = { 42, 0 },
  }) },
  { time = 0.38, lift = 0.0005, pose = mergePose(makeStance(), {
    thighL = { -9, 0 }, shinL = { 13, 0 },
    thighR = { -4, 0 }, shinR = { 8, 0 },
    spine1 = { 2, 0 }, spine3 = { 0, 6 }, hips = { 0, 2 }, head = { 1, 2 },
    armR = { -18, 0 }, forearmR = { 6, 0 }, armL = { -4, 0 }, forearmL = { 30, 0 },
  }) },
  { time = 0.44, lift = 0.0, pose = mergePose(makeStance(), {
    thighL = { -10, 0 }, shinL = { 14, 0 },
    thighR = { -2, 0 }, shinR = { 6, 0 },
    spine1 = { 7, 0 }, spine3 = { 5, 22 }, hips = { 0, 9 }, head = { 5, 10 },
    armR = { -70, 0 }, forearmR = { -25, 0 }, handR = { -10, 0 },
    armL = { 25, 0 }, forearmL = { 35, 0 },
  }) },
  { time = 0.56, lift = 0.0005, pose = mergePose(makeStance(), {
    thighL = { -8, 0 }, shinL = { 12, 0 },
    thighR = { -4, 0 }, shinR = { 8, 0 },
    spine1 = { 4, 0 }, spine3 = { 2, 10 }, hips = { 0, 4 }, head = { 3, 5 },
    armR = { -30, 0 }, forearmR = { 10, 0 }, armL = { 8, 0 }, forearmL = { 20, 0 },
  }) },
  { time = 0.80, lift = 0.0005, pose = mergePose(makeStance(), {}) },
}
local ATTACK_DURATION = 0.80
local ATTACK_HIT_TIME = 0.44

local HIT_KEYS = {
  { time = 0.00, lift = 0.0005, pose = mergePose(makeStance(), {}) },
  { time = 0.08, lift = 0.0004, pose = mergePose(makeStance(), {
    thighL = { -12, 0 }, shinL = { 18, 0 }, footL = { -6, 0 },
    thighR = { -11, 0 }, shinR = { 17, 0 }, footR = { -6, 0 },
    spine1 = { -10, 0 }, spine2 = { -7, 0 }, spine3 = { -5, 6 }, neck = { -5, 0 }, head = { -14, 8 },
    armL = { -8, 0 }, armR = { -8, 0 }, forearmL = { 28, 0 }, forearmR = { 28, 0 }, hips = { 0, 4 },
  }) },
  { time = 0.20, lift = 0.0007, pose = mergePose(makeStance(), {
    thighL = { -9, 0 }, shinL = { 14, 0 }, footL = { -5, 0 },
    thighR = { -8, 0 }, shinR = { 13, 0 }, footR = { -5, 0 },
    spine1 = { -5, 0 }, spine2 = { -3, 0 }, spine3 = { -2, 3 }, head = { -7, 4 },
    armL = { -4, 0 }, armR = { -4, 0 }, forearmL = { 18, 0 }, forearmR = { 18, 0 }, hips = { 0, 2 },
  }) },
  { time = 0.50, lift = 0.0005, pose = mergePose(makeStance(), {}) },
}
local HIT_DURATION = 0.50

local function smoothstep(value)
  if value <= 0 then
    return 0
  end
  if value >= 1 then
    return 1
  end
  return value * value * (3 - 2 * value)
end

local function registerBone(key, path)  if runtimeScope == nil then
    return
  end
  local boneTransform = runtimeScope:GetTransformByPath(path)
  if boneTransform == nil then
    logger:warnOnce("bone-" .. key, "缺少骨骼节点", path)
    return
  end
  bones[key] = {
    transform = boneTransform,
    baseRotation = boneTransform.localRotation,
    basePosition = boneTransform.localPosition,
    sideAxis = boneTransform:InverseTransformDirection(Vector3.right),
    upAxis = boneTransform:InverseTransformDirection(Vector3.up),
  }
  boneOrder[#boneOrder + 1] = key
  pose[key] = { side = 0, up = 0 }
  smooth[key] = { side = 0, up = 0 }
  if key == "hips" then
    hipsUpLocal = boneTransform:InverseTransformDirection(Vector3.up)
    hipsBasePosition = boneTransform.localPosition
  end
  foundBones = foundBones + 1
end

-- 关键帧采样：相邻关键帧的每个骨骼角度按平滑权重插值
local function normalizeKeys(keys)
  for i = 1, #keys do
    local keyPose = keys[i].pose
    for j = 1, #boneOrder do
      local name = boneOrder[j]
      if keyPose[name] == nil then
        keyPose[name] = { 0, 0 }
      end
    end
  end
end

local function sampleKeys(keys, duration, time, loop)
  local count = #keys
  local localTime = time
  if loop then
    localTime = time % duration
  elseif localTime > keys[count].time then
    localTime = keys[count].time
  end
  local index = count
  for i = 1, count - 1 do
    if localTime < keys[i + 1].time then
      index = i
      break
    end
  end
  local first = keys[index]
  local second = keys[1]
  local span = duration - first.time
  if index < count then
    second = keys[index + 1]
    span = second.time - first.time
  end
  if span <= 0 then
    span = duration
  end
  local offset = localTime - first.time
  if offset < 0 then
    offset = 0
  end
  local weight = smoothstep(offset / span)
  local result = {}
  for key, values in pairs(first.pose) do
    local target = second.pose[key] or values
    result[key] = {
      side = values[1] + (target[1] - values[1]) * weight,
      up = values[2] + (target[2] - values[2]) * weight,
    }
  end
  local lift = first.lift + (second.lift - first.lift) * weight
  return result, lift
end

-- 行走循环：8 个关键帧循环，左右腿相差半周期
local function sampleWalk(phase)
  local count = #WALK_KEYS
  local scaled = phase * count
  local index = math.floor(scaled) % count + 1
  local nextIndex = index % count + 1
  local weight = smoothstep(scaled - math.floor(scaled))
  local a = WALK_KEYS[index]
  local b = WALK_KEYS[nextIndex]
  local aOpposite = WALK_KEYS[(index + 3) % count + 1]
  local bOpposite = WALK_KEYS[(nextIndex + 3) % count + 1]

  local function lerp(x, y)
    return x + (y - x) * weight
  end

  local thighL = lerp(a.thigh, b.thigh)
  local kneeL = lerp(a.knee, b.knee)
  local toeL = lerp(a.toe, b.toe)
  local armL = lerp(a.arm, b.arm)
  local thighR = lerp(aOpposite.thigh, bOpposite.thigh)
  local kneeR = lerp(aOpposite.knee, bOpposite.knee)
  local toeR = lerp(aOpposite.toe, bOpposite.toe)
  local armR = lerp(aOpposite.arm, bOpposite.arm)

  local twist = 0.16 * (thighL - thighR)
  local result = {
    thighL = { side = thighL, up = 0 },
    shinL = { side = kneeL, up = 0 },
    footL = { side = -(thighL + kneeL) + toeL, up = 0 },
    thighR = { side = thighR, up = 0 },
    shinR = { side = kneeR, up = 0 },
    footR = { side = -(thighR + kneeR) + toeR, up = 0 },
    armL = { side = armL, up = 0 },
    armR = { side = armR, up = 0 },
    forearmL = { side = 12, up = 0 },
    forearmR = { side = 12, up = 0 },
    spine1 = { side = 2, up = twist },
    spine3 = { side = 1, up = -twist * 1.2 },
    head = { side = -1, up = twist * 0.5 },
    hips = { side = 0, up = -twist * 0.6 },
  }

  local liftIndex = phase * #WALK_LIFT
  local li = math.floor(liftIndex) % #WALK_LIFT + 1
  local ln = li % #WALK_LIFT + 1
  local lw = liftIndex - math.floor(liftIndex)
  local lift = WALK_LIFT[li] + (WALK_LIFT[ln] - WALK_LIFT[li]) * lw
  return result, lift
end

local function walkCycleDuration()
  local stride = StepLength
  if stride < 0.08 then
    stride = 0.08
  end
  local speed = walkSpeed
  if speed < 0.15 then
    speed = 0.15
  end
  return (2 * stride) / speed
end

local function actionDuration(name)
  if name == "attack" then
    return ATTACK_DURATION
  elseif name == "hit" then
    return HIT_DURATION
  elseif name == "walk" then
    return walkCycleDuration()
  end
  return IDLE_DURATION
end

-- 计算当前动作的目标姿态（每骨骼左右轴角度 + 抬髋量）
local function evaluateAction(deltaTime)
  if currentAction == "walk" then
    local duration = walkCycleDuration()
    walkPhase = (walkPhase + deltaTime / duration) % 1
    return sampleWalk(walkPhase)
  elseif currentAction == "attack" then
    actionTime = actionTime + deltaTime
    if actionTime >= ATTACK_DURATION then
      return nil
    end
    return sampleKeys(ATTACK_KEYS, ATTACK_DURATION, actionTime, false)
  elseif currentAction == "hit" then
    actionTime = actionTime + deltaTime
    if actionTime >= HIT_DURATION then
      return nil
    end
    return sampleKeys(HIT_KEYS, HIT_DURATION, actionTime, false)
  end
  return sampleKeys(IDLE_KEYS, IDLE_DURATION, elapsed, true)
end

local function applyPose(lift)
  for i = 1, #boneOrder do
    local key = boneOrder[i]
    local entry = bones[key]
    local values = smooth[key]
    local rotation = entry.baseRotation
    if values.side ~= 0 then
      rotation = rotation * Quaternion.AngleAxis(values.side, entry.sideAxis)
    end
    if values.up ~= 0 then
      rotation = rotation * Quaternion.AngleAxis(values.up, entry.upAxis)
    end
    entry.transform.localRotation = rotation
  end
  if hipsUpLocal ~= nil and hipsBasePosition ~= nil then
    local hips = bones["hips"]
    hips.transform.localPosition = Vector3(
      hipsBasePosition.x + hipsUpLocal.x * lift,
      hipsBasePosition.y + hipsUpLocal.y * lift,
      hipsBasePosition.z + hipsUpLocal.z * lift
    )
  end
end

-- 外部接口：播放动作，opts 可含 speed / restart / loop
function Play(name, opts)
  if not ready then
    return false
  end
  if name ~= "idle" and name ~= "walk" and name ~= "attack" and name ~= "hit" then
    logger:warnOnce("play-unknown", "未知动作", name)
    return false
  end
  opts = opts or {}
  if opts.speed ~= nil then
    local value = tonumber(opts.speed)
    if value ~= nil and value > 0 then
      walkSpeed = value
    end
  end
  if name == "walk" then
    locomotion = "walk"
  elseif name == "idle" then
    locomotion = "idle"
  end
  if name == "attack" or name == "hit" then
    if currentAction == name and opts.restart ~= true then
      return false
    end
    locomotion = "idle"
    returning = true
  else
    returning = false
  end
  currentAction = name
  actionTime = 0
  if name == "walk" then
    walkPhase = 0
  end
  return true
end

function SetSpeed(speed)
  local value = tonumber(speed)
  if value == nil then
    return false
  end
  if value < 0 then
    value = 0
  end
  walkSpeed = value
  return true
end

function GetAction()
  return currentAction
end

function GetActionDuration(name)
  return actionDuration(name or currentAction)
end

function GetHitTime(name)
  local action = name or currentAction
  if action == "attack" then
    return ATTACK_HIT_TIME
  elseif action == "hit" then
    return 0
  end
  return -1
end

-- 返回：是否就绪、找到骨骼数、应有骨骼数、缺失骨骼名
function GetRigStatus()
  local missing = {}
  for i = 1, #BONE_PATHS do
    if bones[BONE_PATHS[i][1]] == nil then
      missing[#missing + 1] = BONE_PATHS[i][1]
    end
  end
  local text = nil
  if #missing > 0 then
    text = table.concat(missing, ",")
  end
  return ready, foundBones, #BONE_PATHS, text
end

function Start()
  local rootObject = nil
  if runtimeScope ~= nil then
    rootObject = runtimeScope:GetResourceRoot()
  end
  if rootObject == nil then
    logger:warnOnce("scope-missing", "缺少资源根，动画未启用", runtimeScopeReason)
    return
  end
  for i = 1, #BONE_PATHS do
    local item = BONE_PATHS[i]
    registerBone(item[1], item[2])
  end
  if foundBones == 0 then
    logger:warnOnce("bones-missing", "未找到任何骨骼节点")
    return
  end
  normalizeKeys(IDLE_KEYS)
  normalizeKeys(ATTACK_KEYS)
  normalizeKeys(HIT_KEYS)
  ready = true
  currentAction = "idle"
  locomotion = "idle"
  applyPose(0)
end

function Update()
  if not ready then
    return
  end
  local deltaTime = clock.deltaTime
  if deltaTime <= 0 then
    return
  end
  if deltaTime > 0.1 then
    deltaTime = 0.1
  end
  elapsed = elapsed + deltaTime

  local target, lift = evaluateAction(deltaTime)
  if target == nil then
    currentAction = locomotion
    returning = false
    actionTime = 0
    target, lift = evaluateAction(0)
  end
  if target == nil then
    target, lift = {}, 0
  end

  local blend = 1 - math.exp(-SMOOTH_RATE * deltaTime)
  for i = 1, #boneOrder do
    local key = boneOrder[i]
    local values = smooth[key]
    local goal = target[key]
    if goal ~= nil then
      values.side = values.side + (goal.side - values.side) * blend
      values.up = values.up + (goal.up - values.up) * blend
    else
      values.side = values.side * (1 - blend)
      values.up = values.up * (1 - blend)
    end
  end
  smoothLift = smoothLift + (lift - smoothLift) * blend
  applyPose(smoothLift)
end

function OnDisable()
  currentAction = "idle"
  actionTime = 0
  if ready then
    for i = 1, #boneOrder do
      local key = boneOrder[i]
      pose[key].side = 0
      pose[key].up = 0
      smooth[key].side = 0
      smooth[key].up = 0
    end
    smoothLift = 0
    applyPose(0)
  end
end

function OnDestroy()
  ready = false
end

Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="idle",walk="walk",attack="attack",hit="hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))*.50 -- slower foot cadence only; route speed and combat timing unchanged
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.healer=function(root,height)
local Start,OnEnable,OnDisable,Update,Play,SetSpeed,GetAction,GetActionTime,GetRigStatus,GetActionDuration,GetHitTime
local DefaultAction="Idle"
local PlaybackSpeed=1
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 灯祭者的逐骨骼关键帧动作：待机 / 行走 / 攻击 / 受击

local Logger = require("official.core.logger")
local RuntimeScope={from=function()return boundScope end}

local logger = Logger.create("ms-healer-anim")

local UnityEngine = CS.UnityEngine
local Quaternion = CS.UnityEngine.Quaternion
local Vector3 = CS.UnityEngine.Vector3
local Time = clock

local runtimeScope = RuntimeScope.from(self)

-- 骨骼节点路径均来自 inspect_resource_nodes 的真实层级，与 BONE_ORDER 一一对应
local BONE_PATHS = {
  "Armature/root.x",
  "Armature/root.x/spine_01.x",
  "Armature/root.x/spine_01.x/spine_02.x",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x/head.x",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l/hand.l",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r",
  "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r/hand.r",
  "Armature/root.x/thigh_stretch.l",
  "Armature/root.x/thigh_stretch.l/leg_stretch.l",
  "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l",
  "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l/toes_01.l",
  "Armature/root.x/thigh_stretch.r",
  "Armature/root.x/thigh_stretch.r/leg_stretch.r",
  "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r",
  "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r/toes_01.r",
}

local BONE_ORDER = {
  "root", "spine_01", "spine_02", "spine_03", "neck", "head", "shoulder.l", "arm.l", "forearm.l", "hand.l", "shoulder.r", "arm.r", "forearm.r", "hand.r", "thigh.l", "leg.l", "foot.l", "toes.l", "thigh.r", "leg.r", "foot.r", "toes.r"
}

-- 每个关键帧: { 时间, 根节点竖直偏移, { 22 根骨骼各 3 个局部欧拉角增量 } }
local ACTIONS = {
  Idle = {
    duration = 3.00, loop = true, hitTime = 0.00,
    keys = {
      {0.00, 0.0000, {0, 0, 0, -0, 0, -0, -0, 0, -0, 0, -0, 0, 0, -0, 0, -0, 0, -0, -0, 0, 0, -3.1, 0.1, -5.5, 6, 1, 12, -3.2, 0.2, -6.4, -0, 0, 0, -6, -0.3, 5.3, 17.5, -0.2, -8.6, -10.3, -0.5, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {0.25, 0.0000, {0, 0, 0, 0.6, 0, 0.4, -0.4, 0.2, 0.3, 0.5, 0.2, 0.2, -0.5, -0.2, -0.3, -0.3, -0.2, -0.2, 0.4, 0, -0.4, -5.8, 0.4, -5.1, 6, 1, 12, -2.1, 0.1, -6.3, 0.3, 0, 0.3, -5, -0, 9.5, 22.4, -1.8, -16.4, -14.6, -1.1, 8.9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {0.50, 0.0000, {0, 0, 0, 1, -0, 0.8, -0.7, 0.4, 0.5, 0.8, 0.3, 0.4, -0.8, -0.4, -0.6, -0.4, -0.3, -0.4, 0.7, 0, -0.7, -8.1, 0.6, -4.8, 6, 0.9, 12, -1.1, 0.1, -6.2, 0.6, 0, 0.6, -3.9, 0.2, 12.7, 26, -3.7, -22.5, -18.1, -1.9, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {0.75, 0.0000, {0, 0, 0, 1.1, -0, 1.1, -0.8, 0.6, 0.7, 0.9, 0.4, 0.6, -0.9, -0.6, -0.8, -0.5, -0.4, -0.5, 0.8, 0, -0.8, -9.7, 1, -4.5, 6, 0.9, 12, -0.3, 0, -6.1, 0.7, -0, 0.7, -2.6, 0.2, 14.4, 27.9, -5.2, -26.1, -20.5, -2.5, 13.8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {1.00, 0.0000, {0, 0, 0, 1, -0, 1.3, -0.7, 0.8, 0.9, 0.8, 0.5, 0.7, -0.8, -0.8, -1, -0.4, -0.5, -0.6, 0.7, 0, -0.7, -10.3, 1.4, -4.3, 6, 0.9, 12, 0.1, -0, -6.1, 0.6, 0, 0.6, -1.4, -0.1, 14.9, 28.8, -6.1, -27.8, -22, -2.9, 14.8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {1.25, 0.0000, {0, 0, 0, 0.6, -0, 1.4, -0.4, 0.9, 1, 0.5, 0.6, 0.8, -0.5, -0.9, -1.1, -0.3, -0.6, -0.7, 0.4, 0, -0.4, -10.1, 1.8, -4.2, 6, 0.8, 12, 0.3, -0, -6.1, 0.3, 0, 0.3, -0.4, -0.6, 14.4, 28.9, -6.3, -28, -22.6, -3, 15.1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {1.50, 0.0000, {0, 0, 0, 0, 0, 1.5, -0, 0.9, 1, -0, 0.6, 0.8, 0, -0.9, -1.1, -0, -0.6, -0.7, -0, 0, 0, -9.2, 2.3, -4.2, 6, 0.8, 12, 0.1, -0, -6.2, -0, 0, 0, 0.2, -1.2, 13.2, 28.4, -6, -27.1, -22.4, -3, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {1.75, 0.0000, {0, 0, 0, -0.6, -0, 1.4, 0.4, 0.9, 1, -0.5, 0.6, 0.8, 0.5, -0.9, -1.1, 0.3, -0.6, -0.7, -0.4, 0, 0.4, -7.9, 2.6, -4.3, 6, 0.9, 12, -0.2, 0, -6.3, -0.3, 0, -0.3, 0.2, -1.8, 11.7, 27.3, -5.2, -25.2, -21.5, -2.8, 14.4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {2.00, 0.0000, {0, 0, 0, -1, -0, 1.3, 0.7, 0.8, 0.9, -0.8, 0.5, 0.7, 0.8, -0.8, -0.9, 0.4, -0.5, -0.6, -0.7, 0, 0.7, -6.4, 2.6, -4.5, 6, 0.9, 12, -0.7, 0, -6.4, -0.6, 0, -0.6, -0.2, -2.2, 10, 26, -4.2, -22.7, -20.1, -2.4, 13.3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {2.25, 0.0000, {0, 0, 0, -1.1, 0, 1.1, 0.8, 0.6, 0.7, -0.9, 0.4, 0.6, 0.9, -0.6, -0.8, 0.5, -0.4, -0.5, -0.8, 0, 0.8, -5.2, 2.4, -4.7, 6, 0.9, 12, -1.3, 0.1, -6.5, -0.7, 0, -0.7, -1.1, -2.2, 8.5, 24.2, -3.1, -19.7, -18.1, -1.9, 11.7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {2.50, 0.0000, {0, 0, 0, -1, -0, 0.8, 0.7, 0.4, 0.5, -0.8, 0.3, 0.4, 0.8, -0.4, -0.5, 0.4, -0.3, -0.3, -0.7, 0, 0.7, -4.2, 1.8, -5, 6, 0.9, 12, -1.9, 0.1, -6.5, -0.6, 0, -0.6, -2.5, -1.8, 7.2, 22.1, -2, -16.1, -15.7, -1.3, 9.7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {2.75, 0.0000, {0, 0, 0, -0.6, 0, 0.4, 0.4, 0.2, 0.3, -0.5, 0.2, 0.2, 0.5, -0.2, -0.3, 0.3, -0.2, -0.2, -0.4, 0, 0.4, -3.6, 1, -5.2, 6, 1, 12, -2.6, 0.1, -6.5, -0.3, 0, -0.3, -4, -1.1, 5.8, 19.3, -0.9, -11.6, -12.8, -0.8, 6.9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
      {3.00, 0.0000, {0, 0, 0, -0, 0, 0, 0, 0, -0, 0, -0, 0, 0, -0, 0, 0, -0, -0, -0, 0, 0, -3.1, 0.1, -5.5, 6, 1, 12, -3.2, 0.2, -6.4, -0, 0, 0, -6, -0.3, 5.3, 17.5, -0.2, -8.6, -10.3, -0.5, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
    },
  },
  Walk = {
    duration = 1.20, loop = true, hitTime = 0.00,
    keys = {
      {0.00, -0.0096, {0, 0, 0, 2.8, 0, -0, -0.4, 0, -0, 0.8, 0, -0, -1, -0, -0, -0.6, 0, 0, -1.2, 0, -0, 0.7, -2.1, -2.9, 6, 0.9, 12, -7.8, 0.7, -9.9, 0.8, 0, 0, -4.4, 2.6, 10.6, 18.3, -0.5, -9.9, -11.6, -0.3, 3, -5.8, 0.5, -10.2, -8.3, -4.9, 16.1, 2.5, 10.4, 4, 0, 0, 0, 5.7, 0.1, 1.1, 3.5, -1.4, -4, -5.2, -0.6, 7.7, 0, 0, 0}},
      {0.10, -0.0011, {0, 0, 0, 2.4, -0, 0.6, -0.4, 1.2, 0.5, 0.8, 0.7, 0.3, -1, -1.1, -0.5, -0.6, -0.7, -0.3, -1, -0, 0.4, -4.4, -0.1, -5.1, 6, 0.9, 12, -4.2, 0.3, -8.4, 0.7, 0, -0.2, -2.7, 2.4, 11.3, 24.7, -3.1, -20.4, -17.4, -1.8, 11.7, -8.4, 0.4, -5, -3.1, -2.5, 5.6, 1.4, 6.1, 9, 0, 0, 0, 0.8, 0.1, 11, 14.7, -4.9, -17.1, -5.1, -4.5, 7.1, 0, 0, 0}},
      {0.20, -0.0002, {0, 0, 0, 1.6, -0, 1, -0.4, 2.1, 0.8, 0.8, 1.3, 0.6, -1, -1.9, -0.9, -0.6, -1.2, -0.5, -0.6, 0, 0.7, -8.4, 1.9, -7.7, 6, 0.9, 12, -1.3, 0.1, -5.9, 0.4, 0, -0.3, 0.1, 1.9, 11, 28.5, -5.9, -27.3, -22.5, -3.5, 17.3, -5.6, 0.2, -4.3, -3.1, -1.8, 5.7, 1.3, 5.7, 7.5, 0, 0, 0, -1.1, -0.1, 13.4, 17.1, -5.8, -19.9, -9.3, -5.1, 15.1, 0, 0, 0}},
      {0.30, -0.0006, {0, 0, 0, 1.2, 0, 1.1, -0.4, 2.4, 0.9, 0.8, 1.5, 0.7, -1, -2.2, -1, -0.6, -1.4, -0.6, -0, 0, 0.8, -11.6, 2.9, -9.9, 6, 1, 12, 1.2, -0, -3.6, -0, 0, -0.4, 1.8, 1.4, 10.2, 29.9, -7.4, -30.4, -25.1, -4.6, 20.3, -1.5, 0, -3.3, -3.1, -0.9, 5.7, 1.1, 4.3, 3.6, 0, 0, 0, -14.7, -4, 30.3, 32.2, -14.4, -37.9, -11, -9.5, 19.1, 0, 0, 0}},
      {0.40, -0.0036, {0, 0, 0, 1.6, -0, 1, -0.4, 2.1, 0.8, 0.8, 1.3, 0.6, -1, -1.9, -0.9, -0.6, -1.2, -0.5, 0.6, -0, 0.7, -13.3, 2.4, -11.4, 6, 1.1, 12, 2.3, -0, -2.1, -0.4, 0, -0.3, 2, 1.5, 10.7, 30.4, -8, -31.5, -26, -4.9, 21.2, 3.3, -0.1, -2.2, -3, 0.1, 5.6, 0.8, 2.7, -1, 0, 0, 0, -22.8, -7.7, 36.7, 36, -15.1, -43.5, -8.2, -9.8, 15.1, 0, 0, 0}},
      {0.50, -0.0092, {0, 0, 0, 2.4, -0, 0.6, -0.4, 1.2, 0.5, 0.8, 0.7, 0.3, -1, -1.1, -0.5, -0.6, -0.7, -0.3, 1, 0, 0.4, -15.8, 1.4, -15.1, 12.4, 2.9, 19, -1.9, 0.1, -5.5, -0.7, 0, -0.2, 0.5, 1.8, 12.4, 30, -7.5, -30.5, -25.1, -4.4, 19.7, 7.9, -0.1, -1.4, -3, 1.1, 5.9, 0.3, 1.2, -5.4, 0, 0, 0, -26.1, -8.7, 36.2, 33.7, -10.9, -42.3, -5.2, -9, 10.6, 0, 0, 0}},
      {0.60, -0.0152, {0, 0, 0, 2.8, 0, -0, -0.4, 0, 0, 0.8, 0, -0, -1, -0, -0, -0.6, -0, -0, 1.2, -0, -0, -16.4, 0, -18.3, 20.1, 6.4, 27.4, -8.6, 0.8, -11, -0.8, 0, 0, -2.2, 1.7, 13.6, 27.7, -5.3, -25.8, -21.6, -2.9, 15.1, 11.5, -0.1, -0.8, -2.9, 1.9, 5.9, -0.1, 0.1, -8.9, 0, 0, 0, -15.8, -1.9, 14, 12.2, 0.4, -15.2, -0.8, -3.4, 3.5, 0, 0, 0}},
      {0.70, -0.0043, {0, 0, 0, 2.4, -0, -0.6, -0.4, -1.2, -0.5, 0.8, -0.7, -0.3, -1, 1.1, 0.5, -0.6, 0.7, 0.3, 1, -0, -0.4, -11, -2.4, -13.2, 16.8, 4.6, 23.8, -8.3, 0.8, -11.4, -0.7, 0, 0.2, -7.2, 1.1, 7.7, 17.5, -0.2, -8.6, -9.9, -0.4, 5.1, 18, -1, -6.5, -10, 2.2, 19.2, 2.7, 8.4, -3.9, 0, 0, 0, -10.2, -0.5, 5.6, 3.3, 1.2, -4.3, 3.6, -1.7, -4.7, 0, 0, 0}},
      {0.80, -0.0026, {0, 0, 0, 1.6, 0, -1, -0.4, -2.1, -0.8, 0.8, -1.3, -0.6, -1, 1.9, 0.9, -0.6, 1.2, 0.5, 0.6, 0, -0.7, -4.6, -3.7, -8.5, 14.5, 3.7, 21.2, -9.9, 1.1, -12.3, -0.4, 0, 0.3, -11.7, -0.1, 10.4, 17.5, 0.3, -8.7, -6.9, -0.2, 3.8, 18.6, -1.4, -8.3, -12, 1.7, 22.9, 2.8, 7.6, -11.5, 0, 0, 0, -7.9, -0.3, 4.8, 3.3, 0.8, -4.2, 2.8, -1.6, -3.9, 0, 0, 0}},
      {0.90, -0.0017, {0, 0, 0, 1.2, -0, -1.1, -0.4, -2.4, -0.9, 0.8, -1.5, -0.7, -1, 2.2, 1, -0.6, 1.4, 0.6, -0, 0, -0.8, 3.2, -4.1, -1.6, 6.7, 1.1, 12.8, -8.1, 0.7, -9.7, -0, -0, 0.4, -13.8, -0.6, 12.1, 17.5, 0.5, -8.7, -5.2, -0.1, 2.7, 22.9, -4.5, -21.7, -24.5, -7.1, 48.7, 7.4, 21.9, -9.1, 0, 0, 0, -4.7, -0.2, 3.8, 3.4, 0.3, -4.1, 0.9, -1.2, -1.1, 0, 0, 0}},
      {1.00, -0.0027, {0, 0, 0, 1.6, 0, -1, -0.4, -2.1, -0.8, 0.8, -1.3, -0.6, -1, 1.9, 0.9, -0.6, 1.2, 0.5, -0.6, -0, -0.7, 4.9, -3.9, -0.1, 6, 0.9, 12, -9, 0.8, -10.7, 0.4, -0, 0.3, -13.1, 0, 12.8, 17.5, 0.5, -8.7, -5.5, -0.1, 2.2, 17.6, -4.2, -26.8, -25.8, -14.9, 54.7, 7.8, 29, -1.8, 0, 0, 0, -0.8, -0, 2.7, 3.4, -0.3, -4, -1.4, -0.9, 2.1, 0, 0, 0}},
      {1.10, -0.0058, {0, 0, 0, 2.4, -0, -0.6, -0.4, -1.2, -0.5, 0.8, -0.7, -0.3, -1, 1.1, 0.5, -0.6, 0.7, 0.3, -1, 0, -0.4, 3.7, -3.4, -0.9, 6, 0.9, 12, -9.1, 0.9, -10.9, 0.7, -0, 0.2, -9.6, 1.4, 12.1, 17.5, 0.2, -8.6, -7.6, -0.1, 2.1, 9.2, -2.2, -26.7, -22.8, -17.2, 50.7, 6.4, 29.8, 3.7, 0, 0, 0, 2.8, 0, 1.8, 3.5, -0.9, -4, -3.5, -0.7, 5.3, 0, 0, 0}},
      {1.20, -0.0096, {0, 0, 0, 2.8, 0, -0, -0.4, -0, -0, 0.8, 0, -0, -1, -0, -0, -0.6, 0, 0, -1.2, 0, -0, 0.7, -2.1, -2.9, 6, 0.9, 12, -7.8, 0.7, -9.9, 0.8, 0, 0, -4.4, 2.6, 10.6, 18.3, -0.5, -9.9, -11.6, -0.3, 3, -5.8, 0.5, -10.2, -8.3, -4.9, 16.1, 2.5, 10.4, 4, 0, 0, 0, 5.7, 0.1, 1.1, 3.5, -1.4, -4, -5.2, -0.6, 7.7, 0, 0, 0}},
    },
  },
  Attack = {
    duration = 1.60, loop = false, hitTime = 0.70,
    keys = {
      {0.00, 0.0000, {0, 0, 0, -0, 0, -0, -0, 0, -0, 0, -0, 0, 0, -0, 0, -0, 0, -0, -0, 0, 0, -3.1, 0.2, -5.6, 6, 1, 12, -3.2, 0.2, -6.3, -0, 0, 0, -5.9, -0.3, 5.3, 17.5, -0.2, -8.6, -10.4, -0.5, 5.1, 0.5, -0, -0.6, -0.8, -0, 1.4, 0.2, 0.8, 0.1, 0, 0, 0, -0.2, -0, 0.4, 0.4, -0, -0.5, -0.1, -0.1, 0.2, 0, 0, 0}},
      {0.15, -0.0300, {0, 0, 0, -3, 0, 0, -1.4, 0, 0, -0.7, 0, -0, -4, 0, -0, -2.4, 0, 0, -0.6, 0, 0, -16.4, 5.8, -14.1, 28.6, 9.6, 36.6, -10.5, 1.9, -20.2, -0.9, -0, 0, -23.1, -1.2, -14.6, 36.5, -1.1, -32.2, -20.2, -3.3, 51.1, 11.2, -1.5, -14.8, -16.6, -4.7, 32, 4.8, 17.4, 0.9, 0, 0, 0, -12.3, -2.2, 20, 21.7, -5.3, -25.7, -4.3, -6.2, 7.7, 0, 0, 0}},
      {0.35, -0.0150, {0, 0, 0, 1, -0, 0, 0.5, 0, 0, 0.2, 0, -0, -6, 0, 0, -3.6, 0, 0, 0.2, 0, 0, -42.1, 19.2, -51, 57.1, 48, 60.4, -29.5, 5.3, -19.9, 0.3, -0, -0, 38.7, 21.3, 52.2, -9.8, -53.7, -103.4, -76.7, -14.2, 31.9, 7.2, -0.6, -9.5, -11, -2, 20.8, 3.1, 11.3, 0.8, 0, 0, 0, -7.9, -0.9, 12.6, 14.1, -2.2, -16.6, -2.9, -4.1, 5, 0, 0, 0}},
      {0.52, -0.0060, {0, 0, 0, -5, 0, 0, -2.3, 0, 0, -1.2, -0, -0, -8, -0, -0, -4.8, 0, 0, -1, 0, -0, -49.6, 30.5, -48, 91.1, 63.6, 30.9, -41, 2.7, -7.3, -1.5, 0, -0, 60.4, 23.9, 54.1, 8.8, -59.4, -51.2, -102.1, 10.1, 4.4, 3.8, -0.2, -5, -6, -0.6, 11.1, 1.7, 6.1, 0.5, 0, 0, 0, -4.2, -0.2, 6.6, 7.5, -0.6, -8.8, -1.6, -2.2, 2.7, 0, 0, 0}},
      {0.70, -0.0400, {0, 0, 0, 11, 0, 0, 5, 0, -0, 2.7, -0, 0, 5, -0, 0, 3, 0, -0, 2.2, -0, -0, -31.2, -7.4, -25.8, 24.4, 7.7, 32, -10.1, 1.5, -16.8, 3.3, 0, -0, -2.3, 15.2, 61.1, 19, 1, -7.6, -18.9, -13.4, -60.5, 13.5, -2.1, -17.7, -19.4, -6.6, 37.9, 5.7, 20.6, 0.9, 0, 0, 0, -14.6, -3.1, 24, 25.6, -7.5, -30.3, -5.1, -7.3, 9.1, 0, 0, 0}},
      {0.88, -0.0320, {0, 0, 0, 9, -0, 0, 4.1, 0, 0, 2.2, 0, -0, 3, 0, 0, 1.8, 0, -0, 1.8, -0, -0, -28.4, -5.7, -24.6, 25.2, 8.4, 32.9, -10.9, 1.6, -17, 2.7, -0, -0, 0.3, 13.8, 55.5, 19, 0.5, -7.5, -18.2, -10.5, -53.7, 11.7, -1.6, -15.4, -17.2, -5.1, 33.2, 4.9, 18.1, 0.9, 0, 0, 0, -12.8, -2.4, 20.8, 22.5, -5.8, -26.7, -4.5, -6.4, 8, 0, 0, 0}},
      {1.10, -0.0140, {0, 0, 0, 5, -0, -0, 2.3, 0, -0, 1.2, -0, 0, 0, -0, 0, -0, 0, -0, 1, -0, -0, -17.2, -3.9, -16.3, 17.5, 4.8, 24.6, -8.2, 0.9, -12.3, 1.5, 0, 0, -6.4, 4.9, 40, 30.7, -6.1, -29.1, -16.2, -7.5, -7.6, 6.9, -0.5, -9, -10.6, -1.8, 19.8, 3, 10.8, 0.8, 0, 0, 0, -7.6, -0.8, 12.1, 13.5, -2, -15.9, -2.7, -3.9, 4.8, 0, 0, 0}},
      {1.35, -0.0030, {0, 0, 0, 1.5, -0, 0, 0.7, 0, -0, 0.4, -0, -0, -1.5, -0, -0, -0.9, 0, 0, 0.3, -0, -0, -5.5, -1.5, -6.6, 6, 1, 12, -2.9, 0.2, -6.2, 0.4, -0, -0, -5.4, 1.7, 11.3, 17.5, -0, -8.6, -9.5, -2.4, -1, 2.2, -0.1, -2.9, -3.5, -0.2, 6.6, 1, 3.6, 0.3, 0, 0, 0, -2.5, -0.1, 3.8, 4.4, -0.2, -5.2, -0.9, -1.3, 1.6, 0, 0, 0}},
      {1.60, 0.0000, {0, 0, 0, -0, 0, -0, -0, 0, -0, 0, -0, 0, 0, -0, 0, -0, 0, -0, -0, 0, 0, -3.1, 0.2, -5.6, 6, 1, 12, -3.2, 0.2, -6.3, -0, 0, 0, -5.9, -0.3, 5.3, 17.5, -0.2, -8.6, -10.4, -0.5, 5.1, 0.5, -0, -0.6, -0.8, -0, 1.4, 0.2, 0.8, 0.1, 0, 0, 0, -0.2, -0, 0.4, 0.4, -0, -0.5, -0.1, -0.1, 0.2, 0, 0, 0}},
    },
  },
  Hit = {
    duration = 0.65, loop = false, hitTime = 0.00,
    keys = {
      {0.00, 0.0000, {0, 0, 0, -0, 0, -0, -0, 0, 1.2, 0, -1.2, 0.8, 0, 0, -1.2, 0, 0, -0.8, -0, 0, 0, -5, 0.2, -1.1, 6, 0.8, 12, -2.1, 0.2, -8.5, -0, 0, 0, -1.6, -1.8, 9.2, 17.5, -0.5, -8.6, -12.6, -0.2, 1.7, 0.5, -0, -0.6, -0.8, -0, 1.4, 0.2, 0.8, 0.1, 0, 0, 0, -0.2, -0, 0.4, 0.4, -0, -0.5, -0.1, -0.1, 0.2, 0, 0, 0}},
      {0.08, -0.0280, {0, 0, 0, -8, -0, -0, -4, 0, 1.2, -2.4, -1.2, 0.7, -8, 0, -1.2, -4.8, 0, -0.8, -2.4, 0, 0, -21.4, 17.9, -31.4, 47.1, 36.6, 55, -28.7, 5, -19.4, -2.4, 0, -0, 5.4, -12.9, 32, 34.8, -32.8, -64.1, -47.8, -8.8, 31.4, 10.8, -1.3, -14.2, -16, -4.3, 30.7, 4.6, 16.7, 0.9, 0, 0, 0, -11.8, -2, 19.1, 20.8, -4.9, -24.6, -4.2, -6, 7.4, 0, 0, 0}},
      {0.20, -0.0480, {0, 0, 0, -12, 0, 0, -6, 0, 1.2, -3.6, -1.2, 0.7, -11, -0, -1.2, -6.6, 0, -0.8, -3.6, 0, 0, -22.5, 26.4, -37.7, 58.5, 55.2, 54.5, -41.4, 6, -15.7, -3.6, -0, 0, 15.7, -15.8, 39.8, 24, -43.7, -75.6, -60.3, -9.8, 32.1, 15, -2.6, -19.8, -21.3, -8.1, 42.2, 6.3, 22.8, 0.8, 0, 0, 0, -16.3, -3.9, 26.9, 28.3, -9.3, -33.6, -5.6, -8, 10, 0, 0, 0}},
      {0.34, -0.0220, {0, 0, 0, -4, 0, 0, -2, 0, 1.2, -1.2, -1.2, 0.8, -6, -0, -1.2, -3.6, 0, -0.8, -1.2, 0, -0, -19.2, 9.6, -24, 38.7, 22.6, 47.8, -21.7, 4, -20.8, -1.2, 0, -0, 1.1, -7.8, 27.3, 36.5, -20.2, -48.5, -36.6, -4.8, 23.2, 9.2, -1, -12.2, -13.9, -3.2, 26.5, 3.9, 14.4, 0.9, 0, 0, 0, -10.2, -1.5, 16.3, 18, -3.6, -21.2, -3.6, -5.2, 6.4, 0, 0, 0}},
      {0.48, -0.0040, {0, 0, 0, 1, -0, 0, 0.5, -0, 1.2, 0.3, -1.2, 0.8, -1, 0, -1.2, -0.6, 0, -0.8, 0.3, -0, -0, -6.6, -1, -2.1, 6, 0.8, 12, -2, 0.1, -8.2, 0.3, -0, -0, -1.2, -0.3, 14.3, 22, -2.2, -15.8, -16.3, -1.1, 4.8, 2.8, -0.1, -3.7, -4.4, -0.3, 8.2, 1.2, 4.5, 0.4, 0, 0, 0, -3.1, -0.1, 4.8, 5.5, -0.3, -6.5, -1.2, -1.6, 2, 0, 0, 0}},
      {0.65, 0.0000, {0, 0, 0, -0, 0, -0, -0, 0, 1.2, 0, -1.2, 0.8, 0, 0, -1.2, 0, 0, -0.8, -0, 0, 0, -5, 0.2, -1.1, 6, 0.8, 12, -2.1, 0.2, -8.5, -0, 0, 0, -1.6, -1.8, 9.2, 17.5, -0.5, -8.6, -12.6, -0.2, 1.7, 0.5, -0, -0.6, -0.8, -0, 1.4, 0.2, 0.8, 0.1, 0, 0, 0, -0.2, -0, 0.4, 0.4, -0, -0.5, -0.1, -0.1, 0.2, 0, 0, 0}},
    },
  },
}

local BLEND_TIME = 0.18
local boneCount = 0
local rigReady = false
local missingList = {}
local bones = {}
local restRot = {}
local restPos = nil
local clips = {}
local current = "Idle"
local actionTime = 0
local actionSpeed = 1
local playing = false
local started = false
local blendT = BLEND_TIME
local blendFrom = {}
local blendRootY = 0
local pendingName = nil
local pendingOpts = nil

local function smoothstep(x)
  if x <= 0 then return 0 end
  if x >= 1 then return 1 end
  return x * x * (3 - 2 * x)
end

local function buildClips()
  clips = {}
  for name, def in pairs(ACTIONS) do
    local built = { duration = def.duration, loop = def.loop, hitTime = def.hitTime, keys = {} }
    for _, key in ipairs(def.keys) do
      local quats = {}
      for i = 2, #BONE_ORDER do
        local base = i * 3 - 2
        local rest = restRot[i]
        if rest ~= nil then
          local euler = Quaternion.Euler(key[3][base], key[3][base + 1], key[3][base + 2])
          quats[i] = rest * euler
        end
      end
      built.keys[#built.keys + 1] = { t = key[1], dy = key[2], quats = quats }
    end
    clips[name] = built
  end
end

local function resolveBones()
  bones = {}
  restRot = {}
  missingList = {}
  boneCount = 0
  if runtimeScope == nil then
    logger:error("骨骼查找失败：当前脚本没有取得资源 Scope")
    return
  end
  for i, path in ipairs(BONE_PATHS) do
    local tr, reason = runtimeScope:GetTransformByPath(path)
    if tr == nil then
      missingList[#missingList + 1] = BONE_ORDER[i] .. "(" .. tostring(reason) .. ")"
    else
      bones[i] = tr
      restRot[i] = tr.localRotation
      boneCount = boneCount + 1
      if i == 1 then
        restPos = tr.localPosition
      end
    end
  end
  if #missingList > 0 then
    logger:error("骨骼缺失 " .. tostring(#missingList) .. " 根：" .. table.concat(missingList, ", "))
  end
end

local function applyRestPose()
  for i, tr in pairs(bones) do
    local rest = restRot[i]
    if rest ~= nil then
      tr.localRotation = rest
    end
  end
  if bones[1] ~= nil and restPos ~= nil then
    bones[1].localPosition = restPos
  end
end

local function captureBlend()
  blendFrom = {}
  for i, tr in pairs(bones) do
    blendFrom[i] = tr.localRotation
  end
  blendT = 0
  if bones[1] ~= nil and restPos ~= nil then
    blendRootY = bones[1].localPosition.y - restPos.y
  end
end

local function sampleClip(clip, t)
  local keys = clip.keys
  local idx = 1
  local n = #keys
  for i = 1, n - 1 do
    if t >= keys[i].t and t <= keys[i + 1].t then
      idx = i
      break
    end
    if t > keys[i + 1].t then idx = i + 1 end
  end
  if idx >= n then
    return keys[n], keys[n], 0
  end
  local a = keys[idx]
  local b = keys[idx + 1]
  local span = b.t - a.t
  local alpha = 0
  if span > 0.00001 then
    alpha = smoothstep((t - a.t) / span)
  end
  return a, b, alpha
end

local function applyPose()
  local clip = clips[current]
  if clip == nil then return end
  local a, b, alpha = sampleClip(clip, actionTime)
  local blend = 1
  if blendT < BLEND_TIME then
    blend = smoothstep(blendT / BLEND_TIME)
  end
  for i = 2, #BONE_ORDER do
    local tr = bones[i]
    if tr ~= nil then
      local target = a.quats[i]
      if alpha > 0 then
        target = Quaternion.Slerp(a.quats[i], b.quats[i], alpha)
      end
      if blend < 1 and blendFrom[i] ~= nil then
        target = Quaternion.Slerp(blendFrom[i], target, blend)
      end
      tr.localRotation = target
    end
  end
  if bones[1] ~= nil and restPos ~= nil then
    local dy = a.dy + (b.dy - a.dy) * alpha
    if blend < 1 then
      dy = blendRootY + (dy - blendRootY) * blend
    end
    bones[1].localPosition = Vector3(restPos.x, restPos.y + dy, restPos.z)
  end
end

function Start()
  if runtimeScope == nil then
    logger:error("动画初始化失败：没有取得资源 Scope（" .. tostring(scopeReason) .. "）")
    return
  end
  resolveBones()
  if boneCount == 0 then
    logger:error("动画初始化失败：没有找到任何骨骼，动作不会播放")
    return
  end
  buildClips()
  rigReady = boneCount == #BONE_ORDER
  if not rigReady then
    logger:warn("骨骼不完整，仅驱动已找到的 " .. tostring(boneCount) .. " 根骨骼")
  end
  actionSpeed = PlaybackSpeed
  started = true
  current = clips[DefaultAction] ~= nil and DefaultAction or "Idle"
  actionTime = 0
  if pendingName ~= nil and clips[pendingName] ~= nil then
    current = pendingName
    if pendingOpts ~= nil and pendingOpts.startTime ~= nil then
      actionTime = pendingOpts.startTime
    end
  end
  pendingName = nil
  pendingOpts = nil
  playing = true
  blendT = BLEND_TIME
  applyPose()
  logger:info("动作就绪：骨骼 " .. tostring(boneCount) .. "/" .. tostring(#BONE_ORDER) .. "，当前动作 " .. current)
end

function OnEnable()
  if started and rigReady then
    current = clips[DefaultAction] ~= nil and DefaultAction or "Idle"
    actionTime = 0
    playing = true
    captureBlend()
  end
end

function OnDisable()
  playing = false
  actionTime = 0
  blendT = BLEND_TIME
  applyRestPose()
end

function Update()
  if not rigReady then return end
  local dt = clock.deltaTime
  if dt > 0.2 then dt = 0.2 end
  if blendT < BLEND_TIME then
    blendT = blendT + dt
  end
  local clip = clips[current]
  if clip == nil then return end
  if playing then
    actionTime = actionTime + dt * actionSpeed
    if clip.loop then
      if actionTime >= clip.duration then
        actionTime = actionTime % clip.duration
      end
    elseif actionTime >= clip.duration then
      actionTime = clip.duration
      playing = false
      Play("Idle", { restart = true })
      return
    end
  end
  applyPose()
end

-- 供预览面板与局内逻辑调用：切换动作，opts = { restart, speed, startTime }
function Play(name, opts)
  if not started then
    pendingName = name
    pendingOpts = opts
    return true
  end
  local clip = clips[name]
  if clip == nil then
    logger:warnOnce("unknown-action", "未知动作 " .. tostring(name))
    return false
  end
  opts = opts or {}
  if current == name and playing and opts.restart ~= true then
    if opts.speed ~= nil then actionSpeed = opts.speed end
    return true
  end
  captureBlend()
  current = name
  actionTime = opts.startTime or 0
  playing = true
  if opts.speed ~= nil then actionSpeed = opts.speed end
  applyPose()
  return true
end

function SetSpeed(value)
  if type(value) ~= "number" then return end
  if value < 0.05 then value = 0.05 end
  if value > 5 then value = 5 end
  actionSpeed = value
  PlaybackSpeed = value
end

function GetAction()
  return current
end

function GetActionTime()
  return actionTime
end

function GetRigStatus()
  return {
    ready = rigReady,
    boneCount = boneCount,
    expected = #BONE_ORDER,
    missing = table.concat(missingList, ", "),
    action = current,
    message = rigReady and "ok" or "bone-missing",
  }
end

function GetActionDuration(name)
  local clip = clips[name]
  if clip == nil then return 0 end
  return clip.duration
end

function GetHitTime(name)
  local clip = clips[name]
  if clip == nil then return 0 end
  return clip.hitTime
end

Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="Idle",walk="Walk",attack="Attack",hit="Hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.ranged=function(root,height)
local Play,SetSpeed,GetAction,GetActionTime,GetRigStatus,GetActionDuration,GetHitTime,Start,OnEnable,Update,OnDisable,OnDestroy
local DefaultAction="idle"
local PlaybackSpeed=1
local FadeTime=0.18
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 裂隙投矛手：逐骨骼驱动的待机、行走、攻击、受击动作与对外播放接口

local UnityEngine = CS.UnityEngine
local Quaternion = UnityEngine.Quaternion
local Vector3 = UnityEngine.Vector3
local Time = UnityEngine.Time
local RuntimeScope={from=function()return boundScope end}
local Logger = require("official.core.logger")

local runtimeScope, scopeReason = RuntimeScope.from(self)
local logger = Logger.create("ms-ranged-anim")

local RAD = math.pi / 180

-- 骨骼角色：角色键不依赖骨骼命名，运行时按真实左右位置校正。
local BONE_DEFS = {
  { role = "root.x", bone = "root.x" },
  { role = "spine_01.x", bone = "spine_01.x" },
  { role = "spine_02.x", bone = "spine_02.x" },
  { role = "spine_03.x", bone = "spine_03.x" },
  { role = "neck.x", bone = "neck.x" },
  { role = "head.x", bone = "head.x" },
  { role = "shoulderL", bone = "shoulder.l" },
  { role = "armL", bone = "arm_stretch.l" },
  { role = "forearmL", bone = "forearm_stretch.l" },
  { role = "handL", bone = "hand.l" },
  { role = "shoulderR", bone = "shoulder.r" },
  { role = "armR", bone = "arm_stretch.r" },
  { role = "forearmR", bone = "forearm_stretch.r" },
  { role = "handR", bone = "hand.r" },
  { role = "thighL", bone = "thigh_stretch.l" },
  { role = "legL", bone = "leg_stretch.l" },
  { role = "footL", bone = "foot.l" },
  { role = "toesL", bone = "toes_01.l" },
  { role = "thighR", bone = "thigh_stretch.r" },
  { role = "legR", bone = "leg_stretch.r" },
  { role = "footR", bone = "foot.r" },
  { role = "toesR", bone = "toes_01.r" },
}

local ALL_ROLES = {
  "root.x", "spine_01.x", "spine_02.x", "spine_03.x", "neck.x", "head.x",
  "shoulderL", "shoulderR", "armL", "armR", "forearmL", "forearmR", "handL", "handR",
  "thighL", "thighR", "legL", "legR", "footL", "footR", "toesL", "toesR",
}

-- 基础姿势：绑定姿势已是自然站姿，这里只保留轻微前倾和持矛手臂抬起。
local BASE = {
  ["spine_01.x"] = { 1, 0, 0 },
  ["spine_02.x"] = { 2, 0, 0 },
  ["spine_03.x"] = { -1, 0, 0 },
  ["neck.x"] = { -1, 0, 0 },
  armR = { 0, 0, 8 },
}

local basePose = {}

local function makePose(overrides)
  local p = {}
  for i = 1, #ALL_ROLES do
    local r = ALL_ROLES[i]
    local b = basePose[r]
    p[r] = { b[1], b[2], b[3] }
  end
  if overrides ~= nil then
    for k, v in pairs(overrides) do
      p[k] = { v[1], v[2], v[3] }
    end
  end
  return p
end

local function initBasePose()
  for i = 1, #ALL_ROLES do
    basePose[ALL_ROLES[i]] = { 0, 0, 0 }
  end
  for k, v in pairs(BASE) do
    basePose[k] = { v[1], v[2], v[3] }
  end
end

-- 待机：呼吸与轻微重心变化，持矛手臂保持略抬起
local IDLE_KEYS = {
  { t = 0.0, p = {} },
  { t = 1.2, p = {
    ["spine_01.x"] = { 1, 0, 0.8 }, ["spine_02.x"] = { 3.5, 0, 0.4 }, ["spine_03.x"] = { -1.8, 0, 0 },
    ["neck.x"] = { -2, 0, 0 }, ["head.x"] = { 1, 0, 0 },
    shoulderL = { 0, 0, -1 }, shoulderR = { 0, 0, 1 },
    armL = { 1, 0, 0 }, armR = { 1, 0, 8 },
  } },
  { t = 2.4, p = {
    ["spine_01.x"] = { 1.2, 0, -0.6 }, ["spine_02.x"] = { 2.2, 0, -1.2 }, ["spine_03.x"] = { -0.6, 0, 0.4 },
    ["neck.x"] = { -1.2, -1, 0 }, ["head.x"] = { 0.5, -1.5, 0.6 },
    armR = { 0, 0, 9 },
  } },
  { t = 3.8, p = {
    ["spine_02.x"] = { 3.2, 0, 0 }, ["spine_03.x"] = { -1.6, 0, 0 },
    ["neck.x"] = { -2.4, 0.4, 0 }, ["head.x"] = { 1, 0.6, 0 },
    armL = { 0.5, 0, 0 }, armR = { 0.5, 0, 8.5 },
  } },
  { t = 5.0, p = {} },
}

-- 行走：原地循环，平脚落地，持矛侧手臂摆动幅度小
local WALK_KEYS = {
  { t = 0.0, p = {
    thighL = { -12, 0, 0 }, legL = { 4, 0, 0 }, footL = { 8, 0, 0 }, toesL = { -2, 0, 0 },
    thighR = { 12, 0, 0 }, legR = { 4, 0, 0 }, footR = { -16, 0, 0 }, toesR = { 4, 0, 0 },
    armL = { 10, 0, 0 }, armR = { -5, 0, 8 },
    ["spine_02.x"] = { 2, 2.5, 0 }, ["spine_03.x"] = { -1, -1.5, 0 }, ["neck.x"] = { -1, -1, 0 },
  } },
  { t = 0.275, p = {
    thighL = { 2, 0, 0 }, legL = { 2, 0, 0 }, footL = { -4, 0, 0 },
    thighR = { -10, 0, 0 }, legR = { 55, 0, 0 }, footR = { -40, 0, 0 },
    armL = { 2, 0, 0 }, armR = { 0, 0, 8 },
    ["spine_02.x"] = { 2, 0, 0 },
  } },
  { t = 0.55, p = {
    thighL = { 12, 0, 0 }, legL = { 4, 0, 0 }, footL = { -16, 0, 0 }, toesL = { 4, 0, 0 },
    thighR = { -12, 0, 0 }, legR = { 4, 0, 0 }, footR = { 8, 0, 0 }, toesR = { -2, 0, 0 },
    armL = { -10, 0, 0 }, armR = { 5, 0, 8 },
    ["spine_02.x"] = { 2, -2.5, 0 }, ["spine_03.x"] = { -1, 1.5, 0 }, ["neck.x"] = { -1, 1, 0 },
  } },
  { t = 0.825, p = {
    thighL = { -10, 0, 0 }, legL = { 55, 0, 0 }, footL = { -40, 0, 0 },
    thighR = { 2, 0, 0 }, legR = { 2, 0, 0 }, footR = { -4, 0, 0 },
    armL = { -2, 0, 0 }, armR = { 0, 0, 8 },
    ["spine_02.x"] = { 2, 0, 0 },
  } },
  { t = 1.1, p = {
    thighL = { -12, 0, 0 }, legL = { 4, 0, 0 }, footL = { 8, 0, 0 }, toesL = { -2, 0, 0 },
    thighR = { 12, 0, 0 }, legR = { 4, 0, 0 }, footR = { -16, 0, 0 }, toesR = { 4, 0, 0 },
    armL = { 10, 0, 0 }, armR = { -5, 0, 8 },
    ["spine_02.x"] = { 2, 2.5, 0 }, ["spine_03.x"] = { -1, -1.5, 0 }, ["neck.x"] = { -1, -1, 0 },
  } },
}

-- 攻击：右臂后拉蓄力，向前投掷，命中后收势回站姿
local ATTACK_KEYS = {
  { t = 0.0, p = {} },
  { t = 0.35, p = {
    ["spine_01.x"] = { 0, 3, 0 }, ["spine_02.x"] = { -4, 18, 0 }, ["spine_03.x"] = { 0, 10, 0 },
    ["neck.x"] = { 0, -10, 0 }, ["head.x"] = { 2, -6, 0 },
    armR = { 50, 0, 25 }, forearmR = { -75, 0, 0 }, handR = { -10, 0, 0 },
    armL = { -20, 0, -10 }, forearmL = { -30, 0, 0 },
    thighL = { -8, 0, 0 }, legL = { 6, 0, 0 }, footL = { 2, 0, 0 },
    thighR = { 6, 0, 0 }, legR = { 8, 0, 0 }, footR = { -14, 0, 0 },
  } },
  { t = 0.62, p = {
    ["spine_01.x"] = { 2, 0, 0 }, ["spine_02.x"] = { 8, -20, 0 }, ["spine_03.x"] = { 4, -12, 0 },
    ["neck.x"] = { -4, 14, 0 }, ["head.x"] = { -2, 8, 0 },
    armR = { -80, 0, -5 }, forearmR = { -8, 0, 0 }, handR = { 0, 0, 0 },
    armL = { 25, 0, 10 }, forearmL = { -15, 0, 0 },
    thighL = { -16, 0, 0 }, legL = { 8, 0, 0 }, footL = { 8, 0, 0 },
    thighR = { 14, 0, 0 }, legR = { 10, 0, 0 }, footR = { -24, 0, 0 }, toesR = { 6, 0, 0 },
  } },
  { t = 0.85, p = {
    ["spine_02.x"] = { 6, -12, 0 }, ["spine_03.x"] = { 2, -8, 0 },
    ["neck.x"] = { -3, 10, 0 }, ["head.x"] = { -1, 5, 0 },
    armR = { -45, 0, -20 }, forearmR = { -25, 0, 0 }, handR = { 0, 4, 0 },
    armL = { 15, 0, 5 }, forearmL = { -10, 0, 0 },
    thighL = { -12, 0, 0 }, legL = { 10, 0, 0 }, footL = { 2, 0, 0 },
    thighR = { 10, 0, 0 }, legR = { 8, 0, 0 }, footR = { -18, 0, 0 },
  } },
  { t = 1.15, p = {
    ["spine_02.x"] = { 4, -4, 0 }, ["spine_03.x"] = { 0, -2, 0 }, ["neck.x"] = { -2, 3, 0 },
    armR = { 5, 0, 4 }, forearmR = { -10, 0, 0 }, forearmL = { -3, 0, 0 },
    thighL = { -4, 0, 0 }, legL = { 4, 0, 0 }, footL = { 0, 0, 0 },
    thighR = { 4, 0, 0 }, legR = { 2, 0, 0 }, footR = { -6, 0, 0 },
  } },
  { t = 1.45, p = {} },
}

-- 受击：短促后仰并快速恢复
local HIT_KEYS = {
  { t = 0.0, p = {} },
  { t = 0.08, p = {
    ["spine_01.x"] = { -3, 0, 0 }, ["spine_02.x"] = { -8, 6, 0 }, ["spine_03.x"] = { -4, 4, 0 },
    ["neck.x"] = { -4, 2, 0 }, ["head.x"] = { -6, 3, 0 },
    armL = { -8, 0, -12 }, forearmL = { -25, 0, 0 },
    armR = { -6, 0, 15 }, forearmR = { -20, 0, 0 },
    thighL = { 6, 0, 0 }, legL = { 8, 0, 0 }, footL = { -14, 0, 0 },
    thighR = { 4, 0, 0 }, legR = { 6, 0, 0 }, footR = { -10, 0, 0 },
  } },
  { t = 0.2, p = {
    ["spine_01.x"] = { -2, 0, 0 }, ["spine_02.x"] = { -4, 4, 0 }, ["spine_03.x"] = { -2, 2, 0 },
    ["neck.x"] = { -2, 2, 0 }, ["head.x"] = { -3, 2, 0 },
    armL = { -4, 0, -6 }, forearmL = { -16, 0, 0 },
    armR = { -3, 0, 12 }, forearmR = { -16, 0, 0 },
    thighL = { 3, 0, 0 }, legL = { 5, 0, 0 }, footL = { -8, 0, 0 },
    thighR = { 2, 0, 0 }, legR = { 4, 0, 0 }, footR = { -6, 0, 0 },
  } },
  { t = 0.55, p = {} },
}

local CLIPS = {}

local function buildClip(keys, duration, loop, hit, interp)
  local built = {}
  for i = 1, #keys do
    built[i] = { t = keys[i].t, pose = makePose(keys[i].p) }
  end
  return { keys = built, duration = duration, loop = loop, hit = hit or 0, interp = interp or "smooth" }
end

local function buildClips()
  CLIPS.idle = buildClip(IDLE_KEYS, 5.0, true, 0, "smooth")
  CLIPS.walk = buildClip(WALK_KEYS, 1.1, true, 0, "linear")
  CLIPS.attack = buildClip(ATTACK_KEYS, 1.45, false, 0.62, "smooth")
  CLIPS.hit = buildClip(HIT_KEYS, 0.55, false, 0.08, "smooth")
end

-- 运行时状态
local initialized = false
local active = true
local rigOk = false
local rigMessage = "未初始化"
local foundCount = 0
local boundCount = 0
local missingNames = {}
local bones = {}
local boneByRole = {}
local smr = nil

local axisR = Vector3(1, 0, 0)
local axisU = Vector3(0, 1, 0)
local axisF = Vector3(0, 0, 1)

local action = "idle"
local clipTime = 0
local speed = 1
local finished = false
local blendT = 0
local blendDur = 0
local blendFrom = {}
local sampleBuf = {}
local tempZero = { 0, 0, 0 }

local function clampSpeed(v)
  if v == nil then return 1 end
  if v < 0.05 then return 0.05 end
  if v > 4 then return 4 end
  return v
end

local function normalize(v)
  local m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if m < 0.0001 then return nil end
  return Vector3(v.x / m, v.y / m, v.z / m)
end

local function dot(a, b)
  return a.x * b.x + a.y * b.y + a.z * b.z
end

-- 收集骨骼与蒙皮渲染器
local function collectNodes(t, map, meshes, depth)
  if t == nil or depth > 24 then return end
  local name = t.name
  if map[name] == nil then map[name] = t end
  local renderer = t:GetComponent(typeof(UnityEngine.SkinnedMeshRenderer))
  if renderer ~= nil then meshes[#meshes + 1] = renderer end
  local count = t.childCount
  for i = 0, count - 1 do
    collectNodes(t:GetChild(i), map, meshes, depth + 1)
  end
end

local function findBone(name)
  for i = 1, #bones do
    if bones[i].bone == name then return bones[i] end
  end
  return nil
end

local function computeAxes()
  local rootBone = findBone("root.x")
  local neckBone = findBone("neck.x")
  local footLBone = findBone("foot.l")
  local footRBone = findBone("foot.r")
  local toesLBone = findBone("toes_01.l")
  local toesRBone = findBone("toes_01.r")
  if rootBone == nil or neckBone == nil or footLBone == nil or footRBone == nil
    or toesLBone == nil or toesRBone == nil then
    return false
  end

  local up = normalize(Vector3(
    neckBone.t.position.x - rootBone.t.position.x,
    neckBone.t.position.y - rootBone.t.position.y,
    neckBone.t.position.z - rootBone.t.position.z))
  if up == nil then return false end

  local dl = Vector3(
    toesLBone.t.position.x - footLBone.t.position.x,
    toesLBone.t.position.y - footLBone.t.position.y,
    toesLBone.t.position.z - footLBone.t.position.z)
  local dr = Vector3(
    toesRBone.t.position.x - footRBone.t.position.x,
    toesRBone.t.position.y - footRBone.t.position.y,
    toesRBone.t.position.z - footRBone.t.position.z)
  local forward = Vector3(dl.x + dr.x, dl.y + dr.y, dl.z + dr.z)
  local vertical = dot(forward, up)
  forward = Vector3(forward.x - up.x * vertical, forward.y - up.y * vertical, forward.z - up.z * vertical)
  forward = normalize(forward)
  if forward == nil then return false end

  local right = normalize(Vector3(
    up.y * forward.z - up.z * forward.y,
    up.z * forward.x - up.x * forward.z,
    up.x * forward.y - up.y * forward.x))
  if right == nil then return false end

  axisR = right
  axisU = up
  axisF = normalize(Vector3(
    right.y * up.z - right.z * up.y,
    right.z * up.x - right.x * up.z,
    right.x * up.y - right.y * up.x))
  if axisF == nil then return false end
  return true
end

local function swapRolesIfMirrored()
  local rootBone = findBone("root.x")
  local handR = findBone("hand.r")
  if rootBone == nil or handR == nil then return false end
  local side = dot(Vector3(
    handR.t.position.x - rootBone.t.position.x,
    handR.t.position.y - rootBone.t.position.y,
    handR.t.position.z - rootBone.t.position.z), axisR)
  if side < 0 then
    for i = 1, #bones do
      local role = bones[i].role
      local last = string.sub(role, -1)
      if last == "L" then
        bones[i].role = string.sub(role, 1, #role - 1) .. "R"
      elseif last == "R" then
        bones[i].role = string.sub(role, 1, #role - 1) .. "L"
      end
    end
    boneByRole = {}
    for i = 1, #bones do
      boneByRole[bones[i].role] = bones[i]
    end
    logger:warn("rig-left-right-swapped", "骨骼左右与命名不一致，已按真实位置交换左右角色")
    return true
  end
  return false
end

local function init()
  if initialized then return true end
  if runtimeScope == nil then
    rigMessage = "无法取得资源作用域：" .. tostring(scopeReason)
    logger:error("scope-failed", rigMessage)
    return false
  end

  initBasePose()
  buildClips()

  local map = {}
  local meshes = {}
  collectNodes(self.transform, map, meshes, 0)
  if #meshes == 0 then
    rigMessage = "未找到 SkinnedMeshRenderer"
    logger:error("skin-missing", rigMessage)
    return false
  end
  smr = meshes[1]

  local boneSet = {}
  local bound = smr.bones
  if bound ~= nil then
    for i = 0, bound.Length - 1 do
      local b = bound[i]
      if b ~= nil then boneSet[b.name] = true end
    end
  end

  foundCount = 0
  boundCount = 0
  missingNames = {}
  bones = {}
  for i = 1, #BONE_DEFS do
    local def = BONE_DEFS[i]
    local t = map[def.bone]
    if t == nil then
      missingNames[#missingNames + 1] = def.bone
    else
      local parentQ = t.parent and t.parent.rotation or Quaternion.identity
      bones[#bones + 1] = {
        role = def.role,
        bone = def.bone,
        t = t,
        restLocal = t.localRotation,
        restPos = t.localPosition,
        restScale = t.localScale,
        parentQ = parentQ,
        parentQInv = Quaternion.Inverse(parentQ),
      }
      foundCount = foundCount + 1
      if boneSet[def.bone] then boundCount = boundCount + 1 end
    end
  end

  if foundCount < #BONE_DEFS then
    rigMessage = "缺少骨骼：" .. table.concat(missingNames, ",")
    logger:error("bone-missing", rigMessage)
    return false
  end

  if not computeAxes() then
    rigMessage = "无法从骨骼位置推导角色朝向"
    logger:error("axis-failed", rigMessage)
    return false
  end
  swapRolesIfMirrored()

  boneByRole = {}
  for i = 1, #bones do boneByRole[bones[i].role] = bones[i] end
  for i = 1, #ALL_ROLES do sampleBuf[ALL_ROLES[i]] = { 0, 0, 0 } end

  rigOk = boundCount >= foundCount - 2
  rigMessage = string.format("骨骼 %d/%d，蒙皮绑定 %d", foundCount, #BONE_DEFS, boundCount)
  initialized = true
  speed = clampSpeed(PlaybackSpeed)
  logger:info("rig-ready", rigMessage)

  local startAction = DefaultAction or "idle"
  if CLIPS[startAction] == nil then startAction = "idle" end
  Play(startAction, { fade = 0 })
  return true
end

local function buildLocalRotation(bone, rx, ry, rz)
  local d = Quaternion.AngleAxis(rx, axisR)
  d = d * Quaternion.AngleAxis(ry, axisU)
  d = d * Quaternion.AngleAxis(rz, axisF)
  return bone.parentQInv * d * bone.parentQ * bone.restLocal
end

local function captureBlendFrom()
  blendFrom = {}
  for i = 1, #bones do
    blendFrom[i] = bones[i].t.localRotation
  end
end

local function sampleClip(clip, t)
  local keys = clip.keys
  local n = #keys
  local idx = 1
  while idx < n - 1 and t >= keys[idx + 1].t do
    idx = idx + 1
  end
  local k0 = keys[idx]
  local k1 = keys[idx + 1]
  local span = k1.t - k0.t
  local u = 0
  if span > 0 then u = (t - k0.t) / span end
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  if clip.interp == "smooth" then u = u * u * (3 - 2 * u) end

  for i = 1, #ALL_ROLES do
    local role = ALL_ROLES[i]
    local a = k0.pose[role]
    local b = k1.pose[role]
    local out = sampleBuf[role]
    if a == nil then a = tempZero end
    if b == nil then b = tempZero end
    out[1] = a[1] + (b[1] - a[1]) * u
    out[2] = a[2] + (b[2] - a[2]) * u
    out[3] = a[3] + (b[3] - a[3]) * u
  end
end

local function renderPose()
  local clip = CLIPS[action]
  if clip == nil then return end
  sampleClip(clip, clipTime)
  local eased = 1
  if blendDur > 0 then
    if blendT < blendDur then
      local a = blendT / blendDur
      eased = a * a * (3 - 2 * a)
    end
  end
  for i = 1, #bones do
    local bone = bones[i]
    local p = sampleBuf[bone.role]
    local target = buildLocalRotation(bone, p[1], p[2], p[3])
    if eased < 1 and blendFrom[i] ~= nil then
      bone.t.localRotation = Quaternion.Slerp(blendFrom[i], target, eased)
    else
      bone.t.localRotation = target
    end
  end
end

local function restoreRestPose()
  for i = 1, #bones do
    local bone = bones[i]
    bone.t.localRotation = bone.restLocal
    bone.t.localPosition = bone.restPos
    bone.t.localScale = bone.restScale
  end
end

-- 对外接口：播放指定动作
function Play(name, opts)
  if not initialized then
    if not init() then return false, rigMessage end
  end
  local clip = CLIPS[name]
  if clip == nil then return false, "unknown-action" end
  local options = opts or {}
  if action == name and not options.restart then
    if clip.loop or not finished then return true end
  end
  captureBlendFrom()
  action = name
  clipTime = 0
  finished = false
  if options.speed ~= nil then
    speed = clampSpeed(options.speed)
  end
  local fade = options.fade
  if fade == nil then fade = FadeTime end
  if fade == nil or fade < 0 then fade = 0 end
  blendDur = fade
  blendT = 0
  return true
end

-- 对外接口：设置播放速度倍率
function SetSpeed(value)
  speed = clampSpeed(value)
  return speed
end

-- 对外接口：当前动作名
function GetAction()
  return action
end

-- 对外接口：当前动作内的播放时间（秒）
function GetActionTime()
  return clipTime
end

-- 对外接口：骨骼与蒙皮检查结果
function GetRigStatus()
  return {
    ok = rigOk,
    ready = initialized,
    boneCount = #BONE_DEFS,
    found = foundCount,
    bound = boundCount,
    missing = missingNames,
    action = action,
    message = rigMessage,
  }
end

-- 对外接口：动作总时长（秒）
function GetActionDuration(name)
  local clip = CLIPS[name or action]
  if clip == nil then return 0 end
  return clip.duration
end

-- 对外接口：命中时刻（秒，动作内时间）
function GetHitTime(name)
  local clip = CLIPS[name or action]
  if clip == nil then return 0 end
  return clip.hit
end

function Start()
  if not init() then
    logger:error("init-failed", rigMessage)
    return
  end
  logger:info("ready", rigMessage)
end

function OnEnable()
  if initialized and not active then
    active = true
    Play(action, { fade = 0.12 })
  end
end

function Update()
  if not initialized or not active then return end
  local dt = clock.deltaTime
  if dt == nil or dt <= 0 then return end
  if blendT < blendDur then
    blendT = math.min(blendDur, blendT + dt)
  end
  local clip = CLIPS[action]
  if clip == nil then return end
  clipTime = clipTime + dt * speed
  if clip.loop then
    if clipTime >= clip.duration then
      clipTime = clipTime % clip.duration
    end
  elseif clipTime >= clip.duration then
    clipTime = clip.duration
    finished = true
    Play("idle", { fade = 0.16 })
    return
  end
  renderPose()
end

function OnDisable()
  active = false
  if initialized then
    restoreRestPose()
  end
end

function OnDestroy()
  active = false
  initialized = false
end

Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="idle",walk="walk",attack="attack",hit="hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.splitter=function(root,height)
local Start,Update,OnDisable,OnEnable,OnDestroy,Play,SetSpeed,GetAction,GetRigStatus,GetActionDuration,GetHitTime,IsReady,Stop
local DefaultAction="Idle"
local BlendTime=0.18
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 裂隙裂团逐骨骼关键帧动画：待机 / 行走 / 双臂拍击 / 受击

local RuntimeScope={from=function()return boundScope end}
local Logger = require("official.core.logger")
local UnityEngine = CS.UnityEngine
local Quaternion = UnityEngine.Quaternion
local Vector3 = UnityEngine.Vector3
local Time = UnityEngine.Time

local runtimeScope, scopeReason = RuntimeScope.from(self)
local logger = Logger.create("splitter-anim")

-- 模型自带的全部骨骼节点。根骨骼不参与动作，只用于统计和恢复。
local BONE_NAMES = {
  "root.x",
  "spine_01.x",
  "spine_02.x",
  "spine_03.x",
  "neck.x",
  "head.x",
  "shoulder.l",
  "arm_stretch.l",
  "forearm_stretch.l",
  "hand.l",
  "shoulder.r",
  "arm_stretch.r",
  "forearm_stretch.r",
  "hand.r",
  "thigh_stretch.l",
  "leg_stretch.l",
  "foot.l",
  "toes_01.l",
  "thigh_stretch.r",
  "leg_stretch.r",
  "foot.r",
  "toes_01.r",
}

local EXPECTED_BONE_COUNT = #BONE_NAMES
local ZERO = { 0, 0, 0 }

-- 动作关键帧：姿势值按 Unity 世界轴语义书写（X 前后俯仰、Y 转向、Z 左右侧倾），
-- 运行时换算成各骨骼静止姿势下的局部轴，避免依赖骨骼的导出旋转。
local ACTIONS = {
  Idle = {
    duration = 2.0,
    loop = true,
    hitTime = -1,
    keys = {
      { t = 0.0, pose = {
        ["thigh_stretch.l"] = { 0, 0, 0 }, ["thigh_stretch.r"] = { 0, 0, 0 },
        ["leg_stretch.l"] = { 1.5, 0, 0 }, ["leg_stretch.r"] = { 1.5, 0, 0 },
        ["foot.l"] = { -1, 0, 0 }, ["foot.r"] = { -1, 0, 0 },
      } },
      { t = 0.5, pose = {
        ["spine_01.x"] = { 1.5, 0, 1.2 }, ["spine_02.x"] = { 1.0, 0, 0.8 },
        ["spine_03.x"] = { 0.6, 0, 0.6 }, ["neck.x"] = { -1.2, 0, -0.8 },
        ["head.x"] = { 0.8, 2.0, -0.6 },
        ["shoulder.l"] = { 0, 0, -2.0 }, ["shoulder.r"] = { 0, 0, 2.0 },
        ["arm_stretch.l"] = { 0, 2.0, -1.5 }, ["arm_stretch.r"] = { 0, -2.0, 1.5 },
        ["thigh_stretch.l"] = { 0.5, 0, 0 }, ["thigh_stretch.r"] = { 0.5, 0, 0 },
        ["leg_stretch.l"] = { 2.5, 0, 0 }, ["leg_stretch.r"] = { 2.5, 0, 0 },
        ["foot.l"] = { -1.5, 0, 0 }, ["foot.r"] = { -1.5, 0, 0 },
      } },
      { t = 1.0, pose = {
        ["spine_01.x"] = { 0, 0, 0 }, ["spine_02.x"] = { 0, 0, 0 },
        ["spine_03.x"] = { 0, 0, 0 }, ["neck.x"] = { 0, 0, 0 }, ["head.x"] = { 0, 0, 0 },
        ["shoulder.l"] = { 0, 0, 0 }, ["shoulder.r"] = { 0, 0, 0 },
        ["arm_stretch.l"] = { 0, 0, 0 }, ["arm_stretch.r"] = { 0, 0, 0 },
        ["thigh_stretch.l"] = { 0, 0, 0 }, ["thigh_stretch.r"] = { 0, 0, 0 },
        ["leg_stretch.l"] = { 1.5, 0, 0 }, ["leg_stretch.r"] = { 1.5, 0, 0 },
        ["foot.l"] = { -1, 0, 0 }, ["foot.r"] = { -1, 0, 0 },
      } },
      { t = 1.5, pose = {
        ["spine_01.x"] = { -1.0, 0, -1.2 }, ["spine_02.x"] = { -0.6, 0, -0.8 },
        ["spine_03.x"] = { -0.4, 0, -0.5 }, ["neck.x"] = { 0.8, 0, 0.7 },
        ["head.x"] = { -0.5, -2.0, 0.5 },
        ["shoulder.l"] = { 0, 0, 1.4 }, ["shoulder.r"] = { 0, 0, -1.4 },
        ["arm_stretch.l"] = { 0, -1.6, 1.2 }, ["arm_stretch.r"] = { 0, 1.6, -1.2 },
        ["thigh_stretch.l"] = { -0.4, 0, 0 }, ["thigh_stretch.r"] = { -0.4, 0, 0 },
        ["leg_stretch.l"] = { 1.0, 0, 0 }, ["leg_stretch.r"] = { 1.0, 0, 0 },
        ["foot.l"] = { -0.8, 0, 0 }, ["foot.r"] = { -0.8, 0, 0 },
      } },
      { t = 2.0, pose = {
        ["thigh_stretch.l"] = { 0, 0, 0 }, ["thigh_stretch.r"] = { 0, 0, 0 },
        ["leg_stretch.l"] = { 1.5, 0, 0 }, ["leg_stretch.r"] = { 1.5, 0, 0 },
        ["foot.l"] = { -1, 0, 0 }, ["foot.r"] = { -1, 0, 0 },
      } },
    },
  },

  Walk = {
    duration = 1.0,
    loop = true,
    hitTime = -1,
    keys = {
      { t = 0.0, pose = {
        ["spine_01.x"] = { 2, 3, 0 }, ["spine_02.x"] = { 1.2, 1.5, 0 }, ["spine_03.x"] = { 0.8, 0, 0 },
        ["neck.x"] = { -1.2, -2, 0 }, ["head.x"] = { -0.6, -2, 0 },
        ["thigh_stretch.l"] = { -12, 0, 0 }, ["leg_stretch.l"] = { 6, 0, 0 }, ["foot.l"] = { -3, 0, 0 },
        ["thigh_stretch.r"] = { 14, 0, 0 }, ["leg_stretch.r"] = { 12, 0, 0 }, ["foot.r"] = { -15, 0, 0 },
        ["shoulder.l"] = { 0, -4, -2 }, ["shoulder.r"] = { 0, -4, 2 },
        ["arm_stretch.l"] = { 0, -8, -2 }, ["arm_stretch.r"] = { 0, -8, 2 },
        ["forearm_stretch.l"] = { 0, -4, 0 }, ["forearm_stretch.r"] = { 0, -4, 0 },
      } },
      { t = 0.15, pose = {
        ["spine_01.x"] = { 3, 2, 3.5 }, ["spine_02.x"] = { 1.8, 1, 2.4 }, ["spine_03.x"] = { 1.0, 0, 1.6 },
        ["neck.x"] = { -1.6, -1.4, -2.0 }, ["head.x"] = { -0.8, -1.4, -1.4 },
        ["thigh_stretch.l"] = { -6, 0, 0 }, ["leg_stretch.l"] = { 2, 0, 0 }, ["foot.l"] = { -2, 0, 0 },
        ["thigh_stretch.r"] = { 4, 0, 0 }, ["leg_stretch.r"] = { 30, 0, 0 }, ["foot.r"] = { -25, 0, 0 },
        ["shoulder.l"] = { 0, -2, -4 }, ["shoulder.r"] = { 0, -2, 4 },
        ["arm_stretch.l"] = { 0, -4, -3 }, ["arm_stretch.r"] = { 0, -4, 3 },
        ["forearm_stretch.l"] = { 0, -2, 0 }, ["forearm_stretch.r"] = { 0, -2, 0 },
      } },
      { t = 0.30, pose = {
        ["spine_01.x"] = { 2, 0, 4 }, ["spine_02.x"] = { 1.2, 0, 2.8 }, ["spine_03.x"] = { 0.8, 0, 1.8 },
        ["neck.x"] = { -1.2, 0, -2.2 }, ["head.x"] = { -0.6, 0, -1.6 },
        ["thigh_stretch.l"] = { 0, 0, 0 }, ["leg_stretch.l"] = { 0, 0, 0 }, ["foot.l"] = { 0, 0, 0 },
        ["thigh_stretch.r"] = { -16, 0, 0 }, ["leg_stretch.r"] = { 22, 0, 0 }, ["foot.r"] = { -28, 0, 0 },
        ["shoulder.l"] = { 0, 2, -2 }, ["shoulder.r"] = { 0, 2, 2 },
        ["arm_stretch.l"] = { 0, 3, -2 }, ["arm_stretch.r"] = { 0, 3, 2 },
        ["forearm_stretch.l"] = { 0, 2, 0 }, ["forearm_stretch.r"] = { 0, 2, 0 },
      } },
      { t = 0.50, pose = {
        ["spine_01.x"] = { 2, -3, 0 }, ["spine_02.x"] = { 1.2, -1.5, 0 }, ["spine_03.x"] = { 0.8, 0, 0 },
        ["neck.x"] = { -1.2, 2, 0 }, ["head.x"] = { -0.6, 2, 0 },
        ["thigh_stretch.l"] = { 14, 0, 0 }, ["leg_stretch.l"] = { 12, 0, 0 }, ["foot.l"] = { -15, 0, 0 },
        ["thigh_stretch.r"] = { -12, 0, 0 }, ["leg_stretch.r"] = { 6, 0, 0 }, ["foot.r"] = { -3, 0, 0 },
        ["shoulder.l"] = { 0, 4, 2 }, ["shoulder.r"] = { 0, 4, -2 },
        ["arm_stretch.l"] = { 0, 8, 2 }, ["arm_stretch.r"] = { 0, 8, -2 },
        ["forearm_stretch.l"] = { 0, 4, 0 }, ["forearm_stretch.r"] = { 0, 4, 0 },
      } },
      { t = 0.65, pose = {
        ["spine_01.x"] = { 3, -2, -3.5 }, ["spine_02.x"] = { 1.8, -1, -2.4 }, ["spine_03.x"] = { 1.0, 0, -1.6 },
        ["neck.x"] = { -1.6, 1.4, 2.0 }, ["head.x"] = { -0.8, 1.4, 1.4 },
        ["thigh_stretch.l"] = { 4, 0, 0 }, ["leg_stretch.l"] = { 30, 0, 0 }, ["foot.l"] = { -25, 0, 0 },
        ["thigh_stretch.r"] = { -6, 0, 0 }, ["leg_stretch.r"] = { 2, 0, 0 }, ["foot.r"] = { -2, 0, 0 },
        ["shoulder.l"] = { 0, 2, 4 }, ["shoulder.r"] = { 0, 2, -4 },
        ["arm_stretch.l"] = { 0, 4, 3 }, ["arm_stretch.r"] = { 0, 4, -3 },
        ["forearm_stretch.l"] = { 0, 2, 0 }, ["forearm_stretch.r"] = { 0, 2, 0 },
      } },
      { t = 0.80, pose = {
        ["spine_01.x"] = { 2, 0, -4 }, ["spine_02.x"] = { 1.2, 0, -2.8 }, ["spine_03.x"] = { 0.8, 0, -1.8 },
        ["neck.x"] = { -1.2, 0, 2.2 }, ["head.x"] = { -0.6, 0, 1.6 },
        ["thigh_stretch.l"] = { -16, 0, 0 }, ["leg_stretch.l"] = { 22, 0, 0 }, ["foot.l"] = { -28, 0, 0 },
        ["thigh_stretch.r"] = { 0, 0, 0 }, ["leg_stretch.r"] = { 0, 0, 0 }, ["foot.r"] = { 0, 0, 0 },
        ["shoulder.l"] = { 0, -2, 2 }, ["shoulder.r"] = { 0, -2, -2 },
        ["arm_stretch.l"] = { 0, -3, 2 }, ["arm_stretch.r"] = { 0, -3, -2 },
        ["forearm_stretch.l"] = { 0, -2, 0 }, ["forearm_stretch.r"] = { 0, -2, 0 },
      } },
      { t = 1.00, pose = {
        ["spine_01.x"] = { 2, 3, 0 }, ["spine_02.x"] = { 1.2, 1.5, 0 }, ["spine_03.x"] = { 0.8, 0, 0 },
        ["neck.x"] = { -1.2, -2, 0 }, ["head.x"] = { -0.6, -2, 0 },
        ["thigh_stretch.l"] = { -12, 0, 0 }, ["leg_stretch.l"] = { 6, 0, 0 }, ["foot.l"] = { -3, 0, 0 },
        ["thigh_stretch.r"] = { 14, 0, 0 }, ["leg_stretch.r"] = { 12, 0, 0 }, ["foot.r"] = { -15, 0, 0 },
        ["shoulder.l"] = { 0, -4, -2 }, ["shoulder.r"] = { 0, -4, 2 },
        ["arm_stretch.l"] = { 0, -8, -2 }, ["arm_stretch.r"] = { 0, -8, 2 },
        ["forearm_stretch.l"] = { 0, -4, 0 }, ["forearm_stretch.r"] = { 0, -4, 0 },
      } },
    },
  },

  Attack = {
    duration = 1.1,
    loop = false,
    hitTime = 0.56,
    keys = {
      { t = 0.0, pose = {
        ["leg_stretch.l"] = { 1.5, 0, 0 }, ["leg_stretch.r"] = { 1.5, 0, 0 },
        ["foot.l"] = { -1, 0, 0 }, ["foot.r"] = { -1, 0, 0 },
      } },
      { t = 0.16, pose = {
        ["spine_01.x"] = { -2, 0, 0 }, ["spine_02.x"] = { -1, 0, 0 }, ["neck.x"] = { 1, 0, 0 },
        ["shoulder.l"] = { 0, 0, -6 }, ["shoulder.r"] = { 0, 0, 6 },
        ["arm_stretch.l"] = { 0, 0, -8 }, ["arm_stretch.r"] = { 0, 0, 8 },
        ["thigh_stretch.l"] = { 2, 0, 0 }, ["thigh_stretch.r"] = { 2, 0, 0 },
        ["leg_stretch.l"] = { 4, 0, 0 }, ["leg_stretch.r"] = { 4, 0, 0 },
        ["foot.l"] = { -6, 0, 0 }, ["foot.r"] = { -6, 0, 0 },
      } },
      { t = 0.36, pose = {
        ["spine_01.x"] = { -6, 0, 0 }, ["spine_02.x"] = { -3, 0, 0 }, ["spine_03.x"] = { -2, 0, 0 },
        ["neck.x"] = { 4, 0, 0 }, ["head.x"] = { 2, 0, 0 },
        ["shoulder.l"] = { 0, 0, -26 }, ["shoulder.r"] = { 0, 0, 26 },
        ["arm_stretch.l"] = { 0, 0, -36 }, ["arm_stretch.r"] = { 0, 0, 36 },
        ["forearm_stretch.l"] = { 0, 0, -10 }, ["forearm_stretch.r"] = { 0, 0, 10 },
        ["thigh_stretch.l"] = { 3, 0, 0 }, ["thigh_stretch.r"] = { 3, 0, 0 },
        ["leg_stretch.l"] = { 6, 0, 0 }, ["leg_stretch.r"] = { 6, 0, 0 },
        ["foot.l"] = { -8, 0, 0 }, ["foot.r"] = { -8, 0, 0 },
      } },
      { t = 0.50, pose = {
        ["spine_01.x"] = { 2, 0, 0 }, ["spine_02.x"] = { 1, 0, 0 }, ["neck.x"] = { -1, 0, 0 },
        ["shoulder.l"] = { 0, 14, -18 }, ["shoulder.r"] = { 0, -14, 18 },
        ["arm_stretch.l"] = { 0, 12, -26 }, ["arm_stretch.r"] = { 0, -12, 26 },
        ["forearm_stretch.l"] = { 0, 4, -6 }, ["forearm_stretch.r"] = { 0, -4, 6 },
        ["thigh_stretch.l"] = { 3, 0, 0 }, ["thigh_stretch.r"] = { 3, 0, 0 },
        ["leg_stretch.l"] = { 6, 0, 0 }, ["leg_stretch.r"] = { 6, 0, 0 },
        ["foot.l"] = { -8, 0, 0 }, ["foot.r"] = { -8, 0, 0 },
      } },
      { t = 0.56, pose = {
        ["spine_01.x"] = { 8, 0, 0 }, ["spine_02.x"] = { 5, 0, 0 }, ["spine_03.x"] = { 2, 0, 0 },
        ["neck.x"] = { -4, 0, 0 }, ["head.x"] = { -6, 0, 0 },
        ["shoulder.l"] = { 0, 50, -6 }, ["shoulder.r"] = { 0, -50, 6 },
        ["arm_stretch.l"] = { 0, 42, -10 }, ["arm_stretch.r"] = { 0, -42, 10 },
        ["forearm_stretch.l"] = { 0, 8, -4 }, ["forearm_stretch.r"] = { 0, -8, 4 },
        ["hand.l"] = { 0, 4, 0 }, ["hand.r"] = { 0, -4, 0 },
        ["thigh_stretch.l"] = { 4, 0, 0 }, ["thigh_stretch.r"] = { 4, 0, 0 },
        ["leg_stretch.l"] = { 8, 0, 0 }, ["leg_stretch.r"] = { 8, 0, 0 },
        ["foot.l"] = { -10, 0, 0 }, ["foot.r"] = { -10, 0, 0 },
      } },
      { t = 0.68, pose = {
        ["spine_01.x"] = { 7, 0, 0 }, ["spine_02.x"] = { 4, 0, 0 }, ["spine_03.x"] = { 2, 0, 0 },
        ["neck.x"] = { -3, 0, 0 }, ["head.x"] = { -4, 0, 0 },
        ["shoulder.l"] = { 0, 52, 2 }, ["shoulder.r"] = { 0, -52, -2 },
        ["arm_stretch.l"] = { 0, 44, 4 }, ["arm_stretch.r"] = { 0, -44, -4 },
        ["forearm_stretch.l"] = { 0, 10, 2 }, ["forearm_stretch.r"] = { 0, -10, -2 },
        ["hand.l"] = { 0, 6, 0 }, ["hand.r"] = { 0, -6, 0 },
        ["thigh_stretch.l"] = { 4, 0, 0 }, ["thigh_stretch.r"] = { 4, 0, 0 },
        ["leg_stretch.l"] = { 8, 0, 0 }, ["leg_stretch.r"] = { 8, 0, 0 },
        ["foot.l"] = { -10, 0, 0 }, ["foot.r"] = { -10, 0, 0 },
      } },
      { t = 0.86, pose = {
        ["spine_01.x"] = { 2, 0, 0 }, ["spine_02.x"] = { 1, 0, 0 }, ["neck.x"] = { -1, 0, 0 },
        ["shoulder.l"] = { 0, 18, -6 }, ["shoulder.r"] = { 0, -18, 6 },
        ["arm_stretch.l"] = { 0, 14, -6 }, ["arm_stretch.r"] = { 0, -14, 6 },
        ["forearm_stretch.l"] = { 0, 4, -2 }, ["forearm_stretch.r"] = { 0, -4, 2 },
        ["thigh_stretch.l"] = { 2, 0, 0 }, ["thigh_stretch.r"] = { 2, 0, 0 },
        ["leg_stretch.l"] = { 4, 0, 0 }, ["leg_stretch.r"] = { 4, 0, 0 },
        ["foot.l"] = { -6, 0, 0 }, ["foot.r"] = { -6, 0, 0 },
      } },
      { t = 1.1, pose = {
        ["leg_stretch.l"] = { 1.5, 0, 0 }, ["leg_stretch.r"] = { 1.5, 0, 0 },
        ["foot.l"] = { -1, 0, 0 }, ["foot.r"] = { -1, 0, 0 },
      } },
    },
  },

  Hit = {
    duration = 0.55,
    loop = false,
    hitTime = 0.07,
    keys = {
      { t = 0.0, pose = {
        ["leg_stretch.l"] = { 1.5, 0, 0 }, ["leg_stretch.r"] = { 1.5, 0, 0 },
        ["foot.l"] = { -1, 0, 0 }, ["foot.r"] = { -1, 0, 0 },
      } },
      { t = 0.07, pose = {
        ["spine_01.x"] = { -9, 0, 4 }, ["spine_02.x"] = { -3, 0, 2 }, ["spine_03.x"] = { -2, 0, 1 },
        ["neck.x"] = { 6, 0, -2 }, ["head.x"] = { 5, 0, -1 },
        ["shoulder.l"] = { 0, -8, 12 }, ["shoulder.r"] = { 0, 8, -12 },
        ["arm_stretch.l"] = { 0, -6, 8 }, ["arm_stretch.r"] = { 0, 6, -8 },
        ["thigh_stretch.l"] = { 3, 0, 0 }, ["thigh_stretch.r"] = { 3, 0, 0 },
        ["leg_stretch.l"] = { 6, 0, 0 }, ["leg_stretch.r"] = { 6, 0, 0 },
        ["foot.l"] = { -8, 0, 0 }, ["foot.r"] = { -8, 0, 0 },
      } },
      { t = 0.16, pose = {
        ["spine_01.x"] = { -11, 0, -3 }, ["spine_02.x"] = { -5, 0, -1.5 }, ["spine_03.x"] = { -3, 0, -1 },
        ["neck.x"] = { 7, 0, 1.5 }, ["head.x"] = { 6, 0, 1 },
        ["shoulder.l"] = { 0, -10, 16 }, ["shoulder.r"] = { 0, 10, -16 },
        ["arm_stretch.l"] = { 0, -8, 10 }, ["arm_stretch.r"] = { 0, 8, -10 },
        ["forearm_stretch.l"] = { 0, -4, 4 }, ["forearm_stretch.r"] = { 0, 4, -4 },
        ["thigh_stretch.l"] = { 4, 0, 0 }, ["thigh_stretch.r"] = { 4, 0, 0 },
        ["leg_stretch.l"] = { 8, 0, 0 }, ["leg_stretch.r"] = { 8, 0, 0 },
        ["foot.l"] = { -10, 0, 0 }, ["foot.r"] = { -10, 0, 0 },
      } },
      { t = 0.34, pose = {
        ["spine_01.x"] = { 3, 0, 0.8 }, ["spine_02.x"] = { 1, 0, 0 }, ["neck.x"] = { -2, 0, 0 },
        ["head.x"] = { -2, 0, 0 },
        ["shoulder.l"] = { 0, -2, -3 }, ["shoulder.r"] = { 0, 2, 3 },
        ["arm_stretch.l"] = { 0, -2, -2 }, ["arm_stretch.r"] = { 0, 2, 2 },
        ["thigh_stretch.l"] = { 2, 0, 0 }, ["thigh_stretch.r"] = { 2, 0, 0 },
        ["leg_stretch.l"] = { 4, 0, 0 }, ["leg_stretch.r"] = { 4, 0, 0 },
        ["foot.l"] = { -6, 0, 0 }, ["foot.r"] = { -6, 0, 0 },
      } },
      { t = 0.55, pose = {
        ["leg_stretch.l"] = { 1.5, 0, 0 }, ["leg_stretch.r"] = { 1.5, 0, 0 },
        ["foot.l"] = { -1, 0, 0 }, ["foot.r"] = { -1, 0, 0 },
      } },
    },
  },
}

local ALIAS = {
  Idle = "Idle", idle = "Idle", ["待机"] = "Idle",
  Walk = "Walk", walk = "Walk", ["行走"] = "Walk", Run = "Walk", ["跑步"] = "Walk",
  Attack = "Attack", attack = "Attack", ["攻击"] = "Attack",
  Hit = "Hit", hit = "Hit", ["受击"] = "Hit", Hurt = "Hit",
}

local rig = {}
local rigByName = {}
local rigReady = false
local rigMissing = {}
local statusNote = "not-initialized"

local currentName = nil
local currentAction = nil
local elapsed = 0
local speed = 1
local blending = false
local blendDuration = 0
local blendElapsed = 0
local active = false

local function normalizeActionName(name)
  if type(name) ~= "string" then return nil end
  return ALIAS[name] or ALIAS[string.lower(name)]
end

local function restoreRestPose()
  for i = 1, #rig do
    local entry = rig[i]
    if entry.bone ~= nil then
      entry.bone.localRotation = entry.restLocal
    end
  end
end

local function buildRig()
  rig = {}
  rigByName = {}
  rigMissing = {}

  if runtimeScope == nil then
    statusNote = "runtime-scope-unavailable"
    logger:error("阶段=初始化 原因=无法取得资源 Scope", scopeReason)
    return false
  end

  local root = runtimeScope:GetResourceRoot()
  if root == nil then
    statusNote = "resource-root-missing"
    logger:error("阶段=初始化 原因=资源根节点缺失")
    return false
  end

  local transforms = root:GetComponentsInChildren(typeof(UnityEngine.Transform), true)
  if transforms == nil then
    statusNote = "transform-query-failed"
    logger:error("阶段=初始化 原因=无法查询模型节点")
    return false
  end

  local found = {}
  for i = 0, transforms.Length - 1 do
    local item = transforms[i]
    if item ~= nil and found[item.name] == nil then
      found[item.name] = item
    end
  end

  for i = 1, #BONE_NAMES do
    local boneName = BONE_NAMES[i]
    local bone = found[boneName]
    if bone == nil then
      rigMissing[#rigMissing + 1] = boneName
    else
      local entry = {
        name = boneName,
        bone = bone,
        restLocal = bone.localRotation,
        fromRot = bone.localRotation,
        axPitch = bone:InverseTransformDirection(Vector3.right),
        axYaw = bone:InverseTransformDirection(Vector3.up),
        axRoll = bone:InverseTransformDirection(Vector3.forward),
      }
      rig[#rig + 1] = entry
      rigByName[boneName] = entry
    end
  end

  if #rigMissing > 0 then
    statusNote = "missing-bones"
    logger:error("阶段=骨骼绑定 原因=缺少骨骼 数量=" .. tostring(#rigMissing) ..
      " 列表=" .. table.concat(rigMissing, ","))
    rigReady = false
    return false
  end

  rigReady = true
  statusNote = "ready"
  logger:info("阶段=骨骼绑定 完成 骨骼数量=" .. tostring(#rig) ..
    " 根节点=" .. tostring(root.name))
  return true
end

local function captureFromPose()
  for i = 1, #rig do
    rig[i].fromRot = rig[i].bone.localRotation
  end
end

local function playInternal(actionName, blendSeconds, restart)
  local action = ACTIONS[actionName]
  if action == nil then return false, "unknown-action" end
  if currentName == actionName and not restart then return true end

  captureFromPose()
  currentName = actionName
  currentAction = action
  elapsed = 0
  blendDuration = blendSeconds or 0
  blendElapsed = 0
  blending = blendDuration > 0.0001
  return true
end

local function samplePose(action, t)
  local keys = action.keys
  local count = #keys
  local index = 1
  while index < count and t >= keys[index + 1].t do
    index = index + 1
  end
  local k0 = keys[index]
  local k1 = keys[index + 1]
  if k1 == nil then k1 = k0 end

  local span = k1.t - k0.t
  local u = 0
  if span > 0.000001 then
    u = (t - k0.t) / span
  end
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  local eased = u * u * (3 - 2 * u)
  return k0.pose, k1.pose, eased
end

local function applyPose(action, t, blendWeight)
  local poseA, poseB, k = samplePose(action, t)
  for i = 1, #rig do
    local entry = rig[i]
    local a = poseA[entry.name] or ZERO
    local b = poseB[entry.name] or ZERO
    local p = a[1] + (b[1] - a[1]) * k
    local y = a[2] + (b[2] - a[2]) * k
    local r = a[3] + (b[3] - a[3]) * k

    local delta = Quaternion.AngleAxis(p, entry.axPitch)
      * Quaternion.AngleAxis(y, entry.axYaw)
      * Quaternion.AngleAxis(r, entry.axRoll)
    local target = entry.restLocal * delta

    if blendWeight < 1 then
      entry.bone.localRotation = Quaternion.Slerp(entry.fromRot, target, blendWeight)
    else
      entry.bone.localRotation = target
    end
  end
end

function Start()
  if buildRig() then
    local wanted = normalizeActionName(DefaultAction) or "Idle"
    playInternal(wanted, 0, true)
    active = true
  end
end

function Update()
  if not rigReady or not active or currentAction == nil then return end

  local dt = clock.deltaTime
  elapsed = elapsed + dt * speed

  local t = elapsed
  if currentAction.loop then
    t = elapsed % currentAction.duration
  elseif elapsed > currentAction.duration then
    t = currentAction.duration
  end

  local weight = 1
  if blending then
    blendElapsed = blendElapsed + dt
    weight = blendElapsed / blendDuration
    if weight >= 1 then
      weight = 1
      blending = false
    end
  end

  applyPose(currentAction, t, weight)

  if not currentAction.loop and elapsed >= currentAction.duration then
    playInternal("Idle", 0.2, true)
  end
end

function OnDisable()
  active = false
  if rigReady then
    restoreRestPose()
  end
end

function OnEnable()
  if rigReady then
    restoreRestPose()
    local wanted = normalizeActionName(DefaultAction) or "Idle"
    playInternal(wanted, 0, true)
    active = true
  end
end

function OnDestroy()
  active = false
  if rigReady then
    restoreRestPose()
  end
end

function Play(name, opts)
  local actionName = normalizeActionName(name)
  if actionName == nil then
    logger:warnOnce("invalid-action", "阶段=播放 原因=未知动作", tostring(name))
    return false
  end
  if not rigReady then
    logger:warnOnce("rig-not-ready", "阶段=播放 原因=骨骼尚未绑定完成", tostring(statusNote))
    return false
  end

  local options = opts or {}
  local blend = options.blend
  if type(blend) ~= "number" then
    blend = BlendTime
  end
  if blend < 0 then blend = 0 end
  local restart = options.restart
  if restart == nil then restart = true end

  local action = ACTIONS[actionName]
  if action.loop and actionName == currentName and not restart then
    return true
  end

  local ok, reason = playInternal(actionName, blend, restart)
  if ok then
    if type(options.speed) == "number" and options.speed > 0 then
      speed = options.speed
    end
    active = true
  else
    logger:warnOnce("play-failed", "阶段=播放 原因=" .. tostring(reason))
  end
  return ok
end

function SetSpeed(value)
  if type(value) ~= "number" then return false end
  if value <= 0 then value = 0.01 end
  speed = value
  return true
end

function GetAction()
  return currentName
end

function GetRigStatus()
  return {
    ready = rigReady,
    boneCount = #rig,
    expectedBoneCount = EXPECTED_BONE_COUNT,
    missing = rigMissing,
    note = statusNote,
    action = currentName,
    speed = speed,
  }
end

function GetActionDuration(name)
  local actionName = normalizeActionName(name)
  if actionName == nil then actionName = currentName end
  local action = ACTIONS[actionName]
  if action == nil then return -1 end
  return action.duration
end

function GetHitTime(name)
  local actionName = normalizeActionName(name)
  if actionName == nil then actionName = currentName end
  local action = ACTIONS[actionName]
  if action == nil then return -1 end
  return action.hitTime
end

function IsReady()
  return rigReady
end

-- 停用或销毁时恢复到绑定姿势，避免网格停留在动作中间。
function Stop()
  active = false
  if rigReady then
    restoreRestPose()
  end
end


Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="Idle",walk="Walk",attack="Attack",hit="Hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.resistant=function(root,height)
local Play,Stop,Pause,Resume,SetSpeed,GetSpeed,GetAction,GetRigStatus,IsPlaying,GetActionDuration,GetHitTime,IsLooping,Start,OnDisable,Update
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 裂隙晶壳骨骼关键帧动画：逐骨骼驱动待机、行走、前爪拍击与受击，不含根节点水平位移

local UnityEngine = CS.UnityEngine
local Vector3 = UnityEngine.Vector3
local Quaternion = UnityEngine.Quaternion
local Time = UnityEngine.Time
local RuntimeScope={from=function()return boundScope end}
local Logger = require("official.core.logger")

local logger = Logger.create("ms-crystal-animation")
local runtimeScope, runtimeScopeReason = RuntimeScope.from(self)

-- 完整骨架用于统计找到的骨骼数量；驱动骨骼只包含会旋转的 15 根。
local RIG_KEYS = {
  "root",
  "spine1", "spine2", "spine3", "neck", "head",
  "shoulderL", "armL", "foreL", "handL",
  "shoulderR", "armR", "foreR", "handR",
  "thighL", "legL", "footL", "toesL",
  "thighR", "legR", "footR", "toesR",
}

local RIG_PATHS = {
  root = "Armature/root.x",
  spine1 = "Armature/root.x/spine_01.x",
  spine2 = "Armature/root.x/spine_01.x/spine_02.x",
  spine3 = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x",
  neck = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x",
  head = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x/head.x",
  shoulderL = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l",
  armL = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l",
  foreL = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l",
  handL = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l/hand.l",
  shoulderR = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r",
  armR = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r",
  foreR = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r",
  handR = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r/hand.r",
  thighL = "Armature/root.x/thigh_stretch.l",
  legL = "Armature/root.x/thigh_stretch.l/leg_stretch.l",
  footL = "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l",
  toesL = "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l/toes_01.l",
  thighR = "Armature/root.x/thigh_stretch.r",
  legR = "Armature/root.x/thigh_stretch.r/leg_stretch.r",
  footR = "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r",
  toesR = "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r/toes_01.r",
}

-- 这 15 根骨骼参与关键帧；肩、颈、头和脚趾保持静止，避免拉扯肩背晶壳。
local DRIVE_KEYS = {
  "spine1", "spine2", "spine3",
  "armL", "armR", "foreL", "foreR", "handL", "handR",
  "thighL", "thighR", "legL", "legR", "footL", "footR",
}

-- 每根骨骼在绑定姿势下对应 Unity 世界 X/Y/Z 的局部轴。
-- 关键帧角度依次表示绕世界 X（俯仰）、Y（偏航）、Z（侧倾）的旋转。
local AXES = {
  spine1 = { { 1.00000, 0.00000, -0.00000 }, { -0.00000, 0.99705, 0.07670 }, { 0.00000, -0.07670, 0.99705 } },
  spine2 = { { 1.00000, 0.00000, -0.00000 }, { 0.00000, 0.99705, 0.07670 }, { 0.00000, -0.07670, 0.99705 } },
  spine3 = { { 1.00000, 0.00000, -0.00000 }, { 0.00000, 0.99920, 0.03997 }, { 0.00000, -0.03997, 0.99920 } },
  armL = { { 0.09416, -0.99556, 0.00000 }, { -0.00000, 0.00000, 1.00000 }, { -0.99556, -0.09416, 0.00000 } },
  armR = { { 0.09507, 0.99547, -0.00000 }, { 0.00000, 0.00000, 1.00000 }, { 0.99547, -0.09507, -0.00000 } },
  foreL = { { 0.56795, -0.57261, -0.59123 }, { -0.59123, -0.78357, 0.19095 }, { -0.57261, 0.24110, -0.78357 } },
  foreR = { { 0.56795, 0.57261, 0.59123 }, { 0.59123, -0.78357, 0.19095 }, { 0.57261, 0.24110, -0.78357 } },
  handL = { { 0.86691, -0.28021, -0.41225 }, { -0.41225, -0.86795, -0.27696 }, { -0.28021, 0.41005, -0.86795 } },
  handR = { { 0.85632, 0.29434, 0.42436 }, { 0.42436, -0.86933, -0.25334 }, { 0.29434, 0.39702, -0.86933 } },
  thighL = { { 0.94603, -0.25013, -0.20608 }, { -0.20608, -0.95504, 0.21315 }, { -0.25013, -0.15917, -0.95504 } },
  thighR = { { 0.94603, 0.25013, 0.20608 }, { 0.20608, -0.95504, 0.21315 }, { 0.25013, -0.15917, -0.95504 } },
  legL = { { 0.96242, -0.21614, -0.16441 }, { -0.16441, -0.94560, 0.28073 }, { -0.21614, -0.24315, -0.94560 } },
  legR = { { 0.96242, 0.21614, 0.16440 }, { 0.16440, -0.94560, 0.28073 }, { 0.21614, -0.24315, -0.94560 } },
  footL = { { 0.58613, -0.28411, -0.75878 }, { -0.75878, -0.52086, -0.39110 }, { -0.28411, 0.80497, -0.52086 } },
  footR = { { 0.58611, 0.28411, 0.75879 }, { 0.75878, -0.52086, -0.39108 }, { 0.28411, 0.80497, -0.52086 } },
}

local AXIS_VECTORS = {}
for i = 1, #DRIVE_KEYS do
  local key = DRIVE_KEYS[i]
  local axes = AXES[key]
  AXIS_VECTORS[key] = {
    Vector3(axes[1][1], axes[1][2], axes[1][3]),
    Vector3(axes[2][1], axes[2][2], axes[2][3]),
    Vector3(axes[3][1], axes[3][2], axes[3][3]),
  }
end

-- 脚底真实顶点的局部偏移；运行时取这些点的最低位置校正根骨骼高度，
-- 保证行走、受击和动作淡入淡出时脚底不穿地，也不整体悬空。
local GROUND_EPSILON = 0.003
local SOLE_POINTS = {
  { key = "footL", offset = Vector3(0.01228, 0.20900, 0.11989) },
  { key = "toesL", offset = Vector3(0.06086, 0.10253, -0.04143) },
  { key = "footL", offset = Vector3(0.16158, 0.04874, 0.03600) },
  { key = "toesL", offset = Vector3(0.00283, 0.13563, 0.01836) },
  { key = "toesL", offset = Vector3(-0.00675, 0.10557, 0.07303) },
  { key = "toesL", offset = Vector3(0.07021, 0.04416, 0.00365) },
  { key = "footL", offset = Vector3(0.14563, 0.02053, 0.05804) },
  { key = "footL", offset = Vector3(0.11180, 0.04041, 0.09635) },
  { key = "toesL", offset = Vector3(0.01857, 0.10027, -0.08562) },
  { key = "toesR", offset = Vector3(-0.05844, 0.10164, -0.03158) },
  { key = "toesR", offset = Vector3(0.01698, 0.10790, 0.10406) },
  { key = "toesR", offset = Vector3(0.00048, 0.13083, 0.04088) },
  { key = "footR", offset = Vector3(-0.15702, 0.06096, 0.02803) },
  { key = "toesR", offset = Vector3(-0.08044, 0.02805, 0.01165) },
  { key = "footR", offset = Vector3(-0.13138, 0.05390, 0.08478) },
  { key = "toesR", offset = Vector3(-0.08009, 0.08198, -0.06655) },
  { key = "footR", offset = Vector3(-0.12219, 0.02161, 0.07971) },
  { key = "toesR", offset = Vector3(0.04345, 0.12718, -0.01094) },
}

-- rootY 是脚底接触校准的毫米级垂直起伏；水平位移始终为 0。
local CLIPS = {
  Idle = {
    duration = 2.0,
    loop = true,
    keys = {
      { t = 0, rootY = 0, pose = {} },
      { t = 0.5, rootY = 0, pose = { armL = { 0, 1.2, 0 }, armR = { 0, -1.2, 0 }, spine1 = { 0.8, 0, 0 }, spine2 = { 0.8, 0, 0 }, spine3 = { 0.6, 0, 0 } } },
      { t = 1.0, rootY = 0, pose = { spine1 = { 0, 0, -0.8 }, spine2 = { 0, 0, -0.5 } } },
      { t = 1.5, rootY = 0, pose = { armL = { 0, -1, 0 }, armR = { 0, 1, 0 }, spine1 = { -0.4, 0, 1.2 }, spine2 = { -0.4, 0, 0.8 }, spine3 = { -0.2, 0, 0.4 } } },
      { t = 2.0, rootY = 0, pose = {} },
    },
  },
  Walk = {
    duration = 1.2,
    loop = true,
    keys = {
      { t = 0, rootY = 0.0041, pose = { armL = { 0, -10, 0 }, armR = { 0, -10, 0 }, footL = { 12, 0, 0 }, footR = { 12, 0, 0 }, foreL = { 0, -3, 0 }, foreR = { 0, -3, 0 }, legL = { 6, 0, 0 }, legR = { 18, 0, 0 }, spine1 = { 0, 0, 2 }, spine3 = { 0, -2, 0 }, thighL = { -20, 0, 0 }, thighR = { 16, 0, 0 } } },
      { t = 0.15, rootY = 0.0074, pose = { armL = { 0, -6, 0 }, armR = { 0, -6, 0 }, footL = { 0, 0, 0 }, footR = { 0, 0, 0 }, legL = { 4, 0, 0 }, legR = { 30, 0, 0 }, spine1 = { 0, 0, 1.5 }, spine3 = { 0, -1, 0 }, thighL = { -10, 0, 0 }, thighR = { 8, 0, 0 } } },
      { t = 0.3, rootY = -0.0011, pose = { footL = { 0, 0, 0 }, footR = { 0, 0, 0 }, legL = { 0, 0, 0 }, legR = { 45, 0, 0 }, spine1 = { 0, 0, 1.2 }, thighL = { 0, 0, 0 }, thighR = { 6, 0, 0 } } },
      { t = 0.45, rootY = 0.0009, pose = { armL = { 0, 6, 0 }, armR = { 0, 6, 0 }, footL = { -3, 0, 0 }, footR = { -20, 0, 0 }, legL = { 8, 0, 0 }, legR = { 20, 0, 0 }, spine1 = { 0, 0, 0.5 }, spine3 = { 0, 1, 0 }, thighL = { 10, 0, 0 }, thighR = { -16, 0, 0 } } },
      { t = 0.6, rootY = 0.0041, pose = { armL = { 0, 10, 0 }, armR = { 0, 10, 0 }, footL = { 12, 0, 0 }, footR = { 12, 0, 0 }, legL = { 18, 0, 0 }, legR = { 6, 0, 0 }, spine1 = { 0, 0, -2 }, spine3 = { 0, 2, 0 }, thighL = { 16, 0, 0 }, thighR = { -20, 0, 0 } } },
      { t = 0.75, rootY = 0.0074, pose = { armL = { 0, -6, 0 }, armR = { 0, -6, 0 }, footL = { 0, 0, 0 }, footR = { 0, 0, 0 }, legL = { 30, 0, 0 }, legR = { 4, 0, 0 }, spine1 = { 0, 0, -1.5 }, spine3 = { 0, -1, 0 }, thighL = { 8, 0, 0 }, thighR = { -10, 0, 0 } } },
      { t = 0.9, rootY = -0.0011, pose = { footL = { 0, 0, 0 }, footR = { 0, 0, 0 }, legL = { 45, 0, 0 }, legR = { 0, 0, 0 }, spine1 = { 0, 0, -1.2 }, thighL = { 6, 0, 0 }, thighR = { 0, 0, 0 } } },
      { t = 1.05, rootY = 0.0009, pose = { armL = { 0, 6, 0 }, armR = { 0, 6, 0 }, footL = { -20, 0, 0 }, footR = { -3, 0, 0 }, legL = { 20, 0, 0 }, legR = { 8, 0, 0 }, spine1 = { 0, 0, -0.5 }, spine3 = { 0, 1, 0 }, thighL = { -16, 0, 0 }, thighR = { 10, 0, 0 } } },
      { t = 1.2, rootY = 0.0041, pose = { armL = { 0, -10, 0 }, armR = { 0, -10, 0 }, footL = { 12, 0, 0 }, footR = { 12, 0, 0 }, foreL = { 0, -3, 0 }, foreR = { 0, -3, 0 }, legL = { 6, 0, 0 }, legR = { 18, 0, 0 }, spine1 = { 0, 0, 2 }, spine3 = { 0, -2, 0 }, thighL = { -20, 0, 0 }, thighR = { 16, 0, 0 } } },
    },
  },
  Attack = {
    duration = 1.1,
    loop = false,
    hitTime = 0.46,
    autoReturn = true,
    keys = {
      { t = 0, rootY = 0, pose = {} },
      { t = 0.2, rootY = 0, pose = { armL = { 0, -3, 0 }, armR = { -6, 20, 28 }, foreR = { 0, 14, 0 }, handR = { 0, 0, -5 }, spine2 = { 0, 0, -1.5 }, spine3 = { 0, 3, 0 } } },
      { t = 0.34, rootY = 0, pose = { armL = { 0, -5, 0 }, armR = { -10, 35, 45 }, foreR = { 0, 20, 0 }, handR = { 0, 0, -8 }, spine2 = { 0, 0, -2 }, spine3 = { 0, 5, 0 } } },
      { t = 0.46, rootY = 0, pose = { armL = { 0, -12, 0 }, armR = { 20, -65, 5 }, foreR = { 0, -30, 0 }, handR = { 15, 0, 0 }, spine1 = { 1, 0, -1 }, spine2 = { 2, 0, 4 }, spine3 = { 3, -6, 0 } } },
      { t = 0.56, rootY = 0, pose = { armL = { 0, -12, 0 }, armR = { 25, -75, 0 }, foreR = { 0, -35, 0 }, handR = { 20, 0, 0 }, spine1 = { 1, 0, -2 }, spine2 = { 2, 0, 3 }, spine3 = { 4, -7, 0 } } },
      { t = 0.72, rootY = 0, pose = { armL = { 0, -3, 0 }, armR = { 5, -20, 5 }, foreR = { 0, -10, 0 }, spine3 = { 0, -2, 0 } } },
      { t = 1.1, rootY = 0, pose = {} },
    },
  },
  Hit = {
    duration = 0.6,
    loop = false,
    hitTime = 0,
    autoReturn = true,
    keys = {
      { t = 0, rootY = 0, pose = {} },
      { t = 0.06, rootY = 0, pose = { armL = { 0, -15, 8 }, armR = { 0, 15, 8 }, foreL = { -3, 0, 0 }, foreR = { -3, 0, 0 }, spine1 = { -2, 0, 0 }, spine2 = { -3, 0, 0 }, spine3 = { -4, 0, 0 } } },
      { t = 0.14, rootY = 0, pose = { armL = { 0, -20, 10 }, armR = { 0, 20, 10 }, foreL = { -5, 0, 0 }, foreR = { -5, 0, 0 }, spine1 = { -3, 0, 0 }, spine2 = { -4, 0, 0 }, spine3 = { -5, 0, 0 } } },
      { t = 0.3, rootY = 0, pose = { armL = { 0, -5, 3 }, armR = { 0, 5, 3 }, spine1 = { 1, 0, 0 }, spine2 = { 1, 0, 0 }, spine3 = { 1, 0, 0 } } },
      { t = 0.6, rootY = 0, pose = {} },
    },
  },
}

local RIG_TOTAL = #RIG_KEYS
local bones = {}
local boneRest = {}
local rootBone = nil
local rootRestPosition = nil
local bonesFound = 0
local ready = false
local groundSolverReady = false

local applied = {}
local fadeFrom = {}
local workPose = {}
for i = 1, #DRIVE_KEYS do
  local key = DRIVE_KEYS[i]
  applied[key] = { 0, 0, 0 }
  fadeFrom[key] = { 0, 0, 0 }
  workPose[key] = { 0, 0, 0 }
end

local currentName = nil
local currentClip = nil
local clipTime = 0
local playing = false
local looping = false
local fadeLeft = 0
local fadeDuration = 0
local fadeFromRootY = 0
local appliedRootY = 0
local baseSpeed = 1
local hitFired = false
local onComplete = nil
local onHit = nil
local pendingPlay = nil
local autoReturnEnabled = true

local function clearPose(target)
  for i = 1, #DRIVE_KEYS do
    local entry = target[DRIVE_KEYS[i]]
    entry[1], entry[2], entry[3] = 0, 0, 0
  end
end

local function copyPose(source, target)
  for i = 1, #DRIVE_KEYS do
    local key = DRIVE_KEYS[i]
    local src = source[key]
    local dst = target[key]
    if src ~= nil then
      dst[1], dst[2], dst[3] = src[1], src[2], src[3]
    else
      dst[1], dst[2], dst[3] = 0, 0, 0
    end
  end
end

-- 在相邻关键帧之间用平滑曲线采样，返回该帧的垂直起伏。
local function sampleClip(clip, time, target)
  local keys = clip.keys
  local count = #keys
  clearPose(target)
  if count == 0 then return 0 end

  local index = 1
  while index < count - 1 and time > keys[index + 1].t do
    index = index + 1
  end
  local first = keys[index]
  local second = keys[index + 1]
  if second == nil then second = first end

  local span = second.t - first.t
  local u = 0
  if span > 0.00001 then
    u = (time - first.t) / span
  end
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  local s = u * u * (3 - 2 * u)

  for i = 1, #DRIVE_KEYS do
    local key = DRIVE_KEYS[i]
    local a = first.pose[key]
    local b = second.pose[key]
    local ax, ay, az = 0, 0, 0
    local bx, by, bz = 0, 0, 0
    if a ~= nil then ax, ay, az = a[1], a[2], a[3] end
    if b ~= nil then bx, by, bz = b[1], b[2], b[3] end
    local out = target[key]
    out[1] = ax + (bx - ax) * s
    out[2] = ay + (by - ay) * s
    out[3] = az + (bz - az) * s
  end

  return first.rootY + (second.rootY - first.rootY) * s
end

local function applyRotations(pose)
  for i = 1, #DRIVE_KEYS do
    local key = DRIVE_KEYS[i]
    local bone = bones[key]
    if bone ~= nil then
      local angles = pose[key]
      local axes = AXIS_VECTORS[key]
      local delta = Quaternion.AngleAxis(angles[2], axes[2]) *
        Quaternion.AngleAxis(angles[1], axes[1]) *
        Quaternion.AngleAxis(angles[3], axes[3])
      bone.localRotation = boneRest[key] * delta
    end
  end
end

-- 先按静止根位置求脚底最低点，再把根骨骼抬到刚好不穿地的高度。
-- fallbackRootY 只在脚骨缺失时使用，取自关键帧中离线校准的接触高度。
local function applyRootAndGround(fallbackRootY)
  if rootBone == nil or rootRestPosition == nil then return end

  if groundSolverReady then
    rootBone.localPosition = rootRestPosition
    local parent = rootBone.parent
    local minY = 0
    for i = 1, #SOLE_POINTS do
      local point = SOLE_POINTS[i]
      local bone = bones[point.key]
      if bone ~= nil then
        local localPoint = parent:InverseTransformPoint(bone:TransformPoint(point.offset))
        if localPoint.y < minY then minY = localPoint.y end
      end
    end
    local solvedY = -minY + GROUND_EPSILON
    rootBone.localPosition = Vector3(rootRestPosition.x, rootRestPosition.y + solvedY, rootRestPosition.z)
    appliedRootY = solvedY
  else
    rootBone.localPosition = Vector3(rootRestPosition.x, rootRestPosition.y + fallbackRootY, rootRestPosition.z)
    appliedRootY = fallbackRootY
  end
end

local function finishClip()
  playing = false
  local complete = onComplete
  onComplete = nil
  onHit = nil
  if complete ~= nil then
    pcall(complete)
  end
  if autoReturnEnabled and currentName ~= nil and currentName ~= "Idle" then
    Play("Idle", { fade = 0.2 })
  end
end

local function startClip(name, opts)
  opts = opts or {}
  local clip = CLIPS[name]
  if clip == nil then
    logger:warnOnce("unknown-action-" .. tostring(name), "未知动作", name)
    return false
  end

  copyPose(applied, fadeFrom)
  fadeFromRootY = appliedRootY
  fadeDuration = opts.fade or 0.18
  if fadeDuration < 0 then fadeDuration = 0 end
  fadeLeft = fadeDuration

  currentName = name
  currentClip = clip
  clipTime = 0
  playing = true
  looping = opts.loop
  if looping == nil then looping = clip.loop == true end
  hitFired = false
  onComplete = opts.onComplete
  onHit = opts.onHit
  autoReturnEnabled = opts.autoReturn
  if autoReturnEnabled == nil then autoReturnEnabled = clip.autoReturn == true end
  if opts.speed ~= nil and opts.speed > 0 then
    baseSpeed = opts.speed
  end
  return true
end

-- 播放动作。opts: loop, speed, fade, autoReturn, onComplete, onHit。
function Play(name, opts)
  if name == nil or CLIPS[name] == nil then return false end
  if not ready then
    pendingPlay = { name = name, opts = opts }
    return true
  end
  return startClip(name, opts)
end

function Stop(fade)
  return Play("Idle", { fade = fade })
end

function Pause()
  playing = false
end

function Resume()
  if currentClip ~= nil then playing = true end
end

function SetSpeed(value)
  if value ~= nil and value > 0 then
    if value < 0.1 then value = 0.1 elseif value > 4 then value = 4 end
    baseSpeed = value
  end
  return baseSpeed
end

function GetSpeed()
  return baseSpeed
end

function GetAction()
  return currentName or "none"
end

-- 返回找到的骨骼数、骨架总数和状态详情；面板沿用前两个返回值。
function GetRigStatus()
  local missing = {}
  for i = 1, RIG_TOTAL do
    local key = RIG_KEYS[i]
    if bones[key] == nil then missing[#missing + 1] = key end
  end
  return bonesFound, RIG_TOTAL, {
    ready = ready,
    found = bonesFound,
    total = RIG_TOTAL,
    missing = missing,
    rootMotion = false,
    speed = baseSpeed,
    action = currentName or "none",
  }
end

function IsPlaying(name)
  if not playing then return false end
  if name == nil then return true end
  return currentName == name
end

function GetActionDuration(name)
  local clip = CLIPS[name or currentName]
  if clip == nil then return 0 end
  return clip.duration / baseSpeed
end

-- 返回动作中命中时刻的秒数（已按当前速度换算）；没有命中判定时返回 nil。
function GetHitTime(name)
  local clip = CLIPS[name or currentName]
  if clip == nil or clip.hitTime == nil then return nil end
  return clip.hitTime / baseSpeed
end

function IsLooping(name)
  local clip = CLIPS[name]
  if clip == nil then return false end
  return clip.loop == true
end

function Start()
  if runtimeScope == nil then
    logger:warnOnce("scope-missing", "无法取得资源上下文", tostring(runtimeScopeReason))
    return
  end

  for i = 1, RIG_TOTAL do
    local key = RIG_KEYS[i]
    local transform, reason = runtimeScope:GetTransformByPath(RIG_PATHS[key])
    if transform == nil then
      logger:warnOnce("bone-missing-" .. key, "缺少骨骼", key, tostring(reason))
    else
      bones[key] = transform
      boneRest[key] = transform.localRotation
      bonesFound = bonesFound + 1
    end
  end

  rootBone = bones.root
  if rootBone ~= nil then
    rootRestPosition = rootBone.localPosition
  end
  groundSolverReady = rootBone ~= nil and rootBone.parent ~= nil and
    bones.footL ~= nil and bones.footR ~= nil and bones.toesL ~= nil and bones.toesR ~= nil
  ready = true

  logger:info("骨骼绑定完成", "找到", bonesFound, "/", RIG_TOTAL, "脚底接触校正", tostring(groundSolverReady))

  if pendingPlay ~= nil then
    local pending = pendingPlay
    pendingPlay = nil
    startClip(pending.name, pending.opts)
    return
  end
  startClip("Idle", { fade = 0 })
end

function OnDisable()
  if not ready then return end
  for i = 1, RIG_TOTAL do
    local key = RIG_KEYS[i]
    local bone = bones[key]
    if bone ~= nil and boneRest[key] ~= nil then
      bone.localRotation = boneRest[key]
    end
  end
  if rootBone ~= nil and rootRestPosition ~= nil then
    rootBone.localPosition = rootRestPosition
  end
end

function Update()
  if not ready or not playing or currentClip == nil then return end

  local dt = clock.deltaTime * baseSpeed
  if dt <= 0 then return end

  local previous = clipTime
  local nextTime = clipTime + dt
  local duration = currentClip.duration
  local finished = false
  local looped = false

  if looping then
    if nextTime >= duration then
      nextTime = nextTime % duration
      looped = true
      hitFired = false
    end
  elseif nextTime >= duration then
    nextTime = duration
    finished = true
  end

  clipTime = nextTime

  if currentClip.hitTime ~= nil and not hitFired and not finished and not looped then
    local hit = currentClip.hitTime
    if previous < hit and nextTime >= hit then
      hitFired = true
      if onHit ~= nil then pcall(onHit) end
    end
  end

  local targetRootY = sampleClip(currentClip, clipTime, workPose)
  if fadeLeft > 0 then
    local fadeRatio = 1
    if fadeDuration > 0.00001 then
      fadeRatio = 1 - (fadeLeft / fadeDuration)
    end
    if fadeRatio < 0 then fadeRatio = 0 elseif fadeRatio > 1 then fadeRatio = 1 end
    local smooth = fadeRatio * fadeRatio * (3 - 2 * fadeRatio)
    for i = 1, #DRIVE_KEYS do
      local key = DRIVE_KEYS[i]
      local from = fadeFrom[key]
      local target = workPose[key]
      target[1] = from[1] + (target[1] - from[1]) * smooth
      target[2] = from[2] + (target[2] - from[2]) * smooth
      target[3] = from[3] + (target[3] - from[3]) * smooth
    end
    targetRootY = fadeFromRootY + (targetRootY - fadeFromRootY) * smooth
    fadeLeft = fadeLeft - dt
  end

  applyRotations(workPose)
  applyRootAndGround(targetRootY)
  copyPose(workPose, applied)

  if finished then
    finishClip()
  end
end


Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="Idle",walk="Walk",attack="Attack",hit="Hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.breaker=function(root,height)
local Play,Stop,Pause,Resume,SetSpeed,GetAction,GetRigStatus,IsPlaying,GetActionDuration,GetHitTime,IsLooping,RegisterHitHandler,ClearHitHandler,Start,OnDisable,Update
local PreviewAction="none"
local PreviewLoop=false
local PlaybackSpeed=1
local AutoIdle=true
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 破门兽骨骼关键帧动画组件：驱动蒙皮骨骼播放待机、重步行走、重拳砸击与受击

local UnityEngine = CS.UnityEngine
local Quaternion = CS.UnityEngine.Quaternion
local Time = clock
local RuntimeScope={from=function()return boundScope end}
local Logger = require("official.core.logger")

local logger = Logger.create("ms-beast-animation")
local runtimeScope, runtimeScopeReason = RuntimeScope.from(self)

-- 骨骼键顺序固定，路径来自模型检查结果；只旋转骨骼，不移动任何节点，因此没有根位移。
local BONE_KEYS = {
  "spine1", "spine2", "spine3", "neck", "head",
  "armL", "armR", "foreL", "foreR",
  "thighL", "thighR", "legL", "legR", "footL", "footR",
}

local BONE_PATHS = {
  spine1 = "Armature/root.x/spine_01.x",
  spine2 = "Armature/root.x/spine_01.x/spine_02.x",
  spine3 = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x",
  neck = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x",
  head = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x/head.x",
  armL = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l",
  armR = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r",
  foreL = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l",
  foreR = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r",
  thighL = "Armature/root.x/thigh_stretch.l",
  thighR = "Armature/root.x/thigh_stretch.r",
  legL = "Armature/root.x/thigh_stretch.l/leg_stretch.l",
  legR = "Armature/root.x/thigh_stretch.r/leg_stretch.r",
  footL = "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l",
  footR = "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r",
}

-- 每个关键帧只在 pose 中列出发生变化的骨骼，未列出的骨骼回到静止姿势。
-- 角度为绕骨骼自身局部轴的度数；四元数按 rest * offset 应用。
local CLIPS = {
  Idle = {
    duration = 3.2,
    loop = true,
    keys = {
      { t = 0, pose = { spine1 = { 1, 0, 1 }, spine2 = { 0.5, 0, 0 }, spine3 = { 0, 0, -0.5 }, neck = { -1, 0, 0 }, head = { -1, 0, 0 }, armL = { 2, 0, 4 }, armR = { 2, 0, -4 }, foreL = { -2, 0, 0 }, foreR = { -2, 0, 0 }, legL = { 2, 0, 0 }, legR = { 2, 0, 0 }, footL = { -1, 0, 0 }, footR = { -1, 0, 0 } } },
      { t = 0.8, pose = { spine1 = { -1.5, 0, 0.5 }, spine2 = { -1, 0, 0 }, spine3 = { -0.5, 0, 0.5 }, neck = { 1, 0, 0 }, head = { 1.5, 0, 0 }, armL = { 4, 0, 3 }, armR = { 4, 0, -3 }, foreL = { -3, 0, 0 }, foreR = { -3, 0, 0 }, legL = { 1, 0, 0 }, legR = { 1, 0, 0 }, footL = { -0.5, 0, 0 }, footR = { -0.5, 0, 0 } } },
      { t = 1.6, pose = { spine1 = { 1, 0, -1 }, spine2 = { 0.5, 0, 0 }, spine3 = { 0, 0, 0.5 }, neck = { -1, 0, 0 }, head = { -1, 0, 0 }, armL = { 2, 0, 5 }, armR = { 2, 0, -5 }, foreL = { -2, 0, 0 }, foreR = { -2, 0, 0 }, legL = { 2, 0, 0 }, legR = { 2, 0, 0 }, footL = { -1, 0, 0 }, footR = { -1, 0, 0 } } },
      { t = 2.4, pose = { spine1 = { 2.5, 0, -0.5 }, spine2 = { 1.5, 0, 0 }, neck = { -2, 0, 0 }, head = { -2, 0, 0 }, armL = { 0, 0, 7 }, armR = { 0, 0, -7 }, foreL = { -1, 0, 0 }, foreR = { -1, 0, 0 }, legL = { 3, 0, 0 }, legR = { 3, 0, 0 }, footL = { -1.5, 0, 0 }, footR = { -1.5, 0, 0 } } },
      { t = 3.2, pose = { spine1 = { 1, 0, 1 }, spine2 = { 0.5, 0, 0 }, spine3 = { 0, 0, -0.5 }, neck = { -1, 0, 0 }, head = { -1, 0, 0 }, armL = { 2, 0, 4 }, armR = { 2, 0, -4 }, foreL = { -2, 0, 0 }, foreR = { -2, 0, 0 }, legL = { 2, 0, 0 }, legR = { 2, 0, 0 }, footL = { -1, 0, 0 }, footR = { -1, 0, 0 } } },
    },
  },
  Walk = {
    duration = 1.2,
    loop = true,
    keys = {
      {t=0, pose={thighL={-20,0,0},thighR={14,0,0},legL={4,0,0},legR={16,0,0},spine1={4,0,-1.5},spine2={2,0,0},spine3={0,-6,1},neck={0,3,0},head={-2,2,0},armL={2,0,14},armR={2,0,14},foreL={-4,0,0},foreR={-6,0,0},footL={8,0,0},footR={1.5,0,0}}},
      {t=0.2, pose={thighL={-4,0,0},thighR={-26,0,0},legL={9,0,0},legR={62,0,0},spine1={5,0,-2},spine2={3,0,0},spine3={0,0,1},head={-2,0,0},armL={2,0,8},armR={2,0,8},foreL={-4,0,0},foreR={-6,0,0},footL={-4.5,0,0},footR={0,0,0}}},
      {t=0.3, pose={thighL={2,0,0},thighR={-23,0,0},legL={13,0,0},legR={48,0,0},spine1={4.5,0,-1},spine2={2.5,0,0},spine3={0,1.5,0.5},head={-1.5,0,0},armL={2,0,4},armR={2,0,4},foreL={-4,0,0},foreR={-6,0,0},footL={-1,0,0},footR={-19.5,0,0}}},
      {t=0.4, pose={thighL={8,0,0},thighR={-20,0,0},legL={14,0,0},legR={34,0,0},spine1={4,0,0},spine2={2,0,0},spine3={0,3,0},head={-1,0,0},armL={2,0,0},armR={2,0,0},footL={11.5,0,0},footR={-16.5,0,0}}},
      {t=0.6, pose={thighR={-20,0,0},thighL={14,0,0},legR={9,0,0},legL={16,0,0},spine1={4,0,1.5},spine2={2,0,0},spine3={0,6,-1},neck={0,-3,0},head={-2,-2,0},armL={2,0,-14},armR={2,0,-14},foreL={-6,0,0},foreR={-4,0,0},footL={1.5,0,0},footR={3,0,0}}},
      {t=0.8, pose={thighR={-4,0,0},thighL={-26,0,0},legR={9,0,0},legL={62,0,0},spine1={5,0,2},spine2={3,0,0},spine3={0,0,-1},head={-2,0,0},armL={2,0,-8},armR={2,0,-8},foreL={-6,0,0},foreR={-4,0,0},footL={0,0,0},footR={-4.5,0,0}}},
      {t=1, pose={thighR={8,0,0},thighL={-20,0,0},legR={14,0,0},legL={34,0,0},spine1={4,0,0},spine2={2,0,0},spine3={0,-3,0},head={-1,0,0},armL={2,0,0},armR={2,0,0},footL={-16.5,0,0},footR={11.5,0,0}}},
      {t=1.2, pose={thighL={-20,0,0},thighR={14,0,0},legL={4,0,0},legR={16,0,0},spine1={4,0,-1.5},spine2={2,0,0},spine3={0,-6,1},neck={0,3,0},head={-2,2,0},armL={2,0,14},armR={2,0,14},foreL={-4,0,0},foreR={-6,0,0},footL={8,0,0},footR={1.5,0,0}}},
    },
  },
  Attack = {
    duration = 1.6,
    loop = false,
    hitTime = 0.74,
    autoReturn = true,
    keys = {
      { t = 0, pose = { spine1 = { 1, 0, 1 }, spine2 = { 0.5, 0, 0 }, spine3 = { 0, 0, -0.5 }, neck = { -1, 0, 0 }, head = { -1, 0, 0 }, armL = { 2, 0, 4 }, armR = { 2, 0, -4 }, foreL = { -2, 0, 0 }, foreR = { -2, 0, 0 }, legL = { 2, 0, 0 }, legR = { 2, 0, 0 }, footL = { -1, 0, 0 }, footR = { -1, 0, 0 } } },
      { t = 0.18, pose = { spine1 = { 7, 0, 0 }, spine2 = { 4, 0, 0 }, spine3 = { 2, 0, 0 }, head = { -4, 0, 0 }, armL = { -4, 0, 16 }, armR = { -4, 0, -16 }, foreL = { -14, 0, 0 }, foreR = { -14, 0, 0 }, thighL = { -4, 0, 0 }, thighR = { -4, 0, 0 }, legL = { 10, 0, 0 }, legR = { 10, 0, 0 }, footL = { -5, 0, 0 }, footR = { -5, 0, 0 } } },
      { t = 0.5, pose = { spine1 = { -12, 0, 0 }, spine2 = { -8, 0, 0 }, spine3 = { -6, 0, 0 }, neck = { -4, 0, 0 }, head = { -12, 0, 0 }, armL = { 90, 0, 10 }, armR = { 90, 0, -10 }, foreL = { -40, 0, 0 }, foreR = { -40, 0, 0 }, thighL = { -4, 0, 0 }, thighR = { -4, 0, 0 }, legL = { 8, 0, 0 }, legR = { 8, 0, 0 }, footL = { -4, 0, 0 }, footR = { -4, 0, 0 } } },
      { t = 0.64, pose = { spine1 = { 8, 0, 0 }, spine2 = { 6, 0, 0 }, spine3 = { 2, 0, 0 }, armL = { 40, 0, -20 }, armR = { 40, 0, 20 }, foreL = { -6, 0, 0 }, foreR = { -6, 0, 0 }, thighL = { -2, 0, 0 }, thighR = { -2, 0, 0 }, legL = { 8, 0, 0 }, legR = { 8, 0, 0 }, footL = { -6, 0, 0 }, footR = { -6, 0, 0 } } },
      { t = 0.74, pose = { spine1 = { 24, 0, 0 }, spine2 = { 15, 0, 0 }, spine3 = { 9, 0, 0 }, neck = { 2, 0, 0 }, head = { 8, 0, 0 }, armL = { -6, 0, -88 }, armR = { -6, 0, 88 }, foreL = { 18, 0, 0 }, foreR = { 18, 0, 0 }, legL = { 6, 0, 0 }, legR = { 6, 0, 0 }, footL = { -1.5, 0, 0 }, footR = { -1.5, 0, 0 } } },
      { t = 0.86, pose = { spine1 = { 26, 0, 0 }, spine2 = { 16, 0, 0 }, spine3 = { 10, 0, 0 }, neck = { 3, 0, 0 }, head = { 9, 0, 0 }, armL = { -8, 0, -92 }, armR = { -8, 0, 92 }, foreL = { 20, 0, 0 }, foreR = { 20, 0, 0 }, legL = { 7, 0, 0 }, legR = { 7, 0, 0 }, footL = { -1, 0, 0 }, footR = { -1, 0, 0 } } },
      { t = 1.2, pose = { spine1 = { 6, 0, 0 }, spine2 = { 3, 0, 0 }, head = { 0, 0, 0 }, armL = { 20, 0, -15 }, armR = { 20, 0, 15 }, foreL = { 0, 0, 0 }, foreR = { 0, 0, 0 }, legL = { 6, 0, 0 }, legR = { 6, 0, 0 }, footL = { -2.5, 0, 0 }, footR = { -2.5, 0, 0 } } },
      { t = 1.6, pose = { spine1 = { 1, 0, 1 }, spine2 = { 0.5, 0, 0 }, spine3 = { 0, 0, -0.5 }, neck = { -1, 0, 0 }, head = { -1, 0, 0 }, armL = { 2, 0, 4 }, armR = { 2, 0, -4 }, foreL = { -2, 0, 0 }, foreR = { -2, 0, 0 }, legL = { 2, 0, 0 }, legR = { 2, 0, 0 }, footL = { -1, 0, 0 }, footR = { -1, 0, 0 } } },
    },
  },
  Hit = {
    duration = 0.7,
    loop = false,
    autoReturn = true,
    keys = {
      { t = 0, pose = { spine1 = { 1, 0, 1 }, spine2 = { 0.5, 0, 0 }, spine3 = { 0, 0, -0.5 }, neck = { -1, 0, 0 }, head = { -1, 0, 0 }, armL = { 2, 0, 4 }, armR = { 2, 0, -4 }, foreL = { -2, 0, 0 }, foreR = { -2, 0, 0 }, legL = { 2, 0, 0 }, legR = { 2, 0, 0 }, footL = { -1, 0, 0 }, footR = { -1, 0, 0 } } },
      { t = 0.08, pose = { spine1 = { -12, 0, 0 }, spine2 = { -9, 0, 0 }, spine3 = { -7, 0, 0 }, neck = { -6, 0, 0 }, head = { -20, 0, 0 }, armL = { 18, 0, 8 }, armR = { 18, 0, -8 }, foreL = { -6, 0, 0 }, foreR = { -6, 0, 0 }, thighL = { -2, 0, 0 }, thighR = { -2, 0, 0 }, legL = { 8, 0, 0 }, legR = { 8, 0, 0 }, footL = { -2.5, 0, 0 }, footR = { -2.5, 0, 0 } } },
      { t = 0.22, pose = { spine1 = { -18, 0, 0 }, spine2 = { -12, 0, 0 }, spine3 = { -9, 0, 0 }, neck = { -10, 0, 0 }, head = { -26, 0, 0 }, armL = { 28, 0, 14 }, armR = { 28, 0, -14 }, foreL = { -4, 0, 0 }, foreR = { -4, 0, 0 }, thighL = { -4, 0, 0 }, thighR = { -4, 0, 0 }, legL = { 12, 0, 0 }, legR = { 12, 0, 0 }, footL = { -4.5, 0, 0 }, footR = { -4.5, 0, 0 } } },
      { t = 0.42, pose = { spine1 = { 8, 0, 0 }, spine2 = { 5, 0, 0 }, spine3 = { 2, 0, 0 }, neck = { 2, 0, 0 }, head = { 6, 0, 0 }, armL = { 8, 0, 4 }, armR = { 8, 0, -4 }, foreL = { -2, 0, 0 }, foreR = { -2, 0, 0 }, legL = { 6, 0, 0 }, legR = { 6, 0, 0 }, footL = { -2.5, 0, 0 }, footR = { -2.5, 0, 0 } } },
      { t = 0.7, pose = { spine1 = { 1, 0, 1 }, spine2 = { 0.5, 0, 0 }, spine3 = { 0, 0, -0.5 }, neck = { -1, 0, 0 }, head = { -1, 0, 0 }, armL = { 2, 0, 4 }, armR = { 2, 0, -4 }, foreL = { -2, 0, 0 }, foreR = { -2, 0, 0 }, legL = { 2, 0, 0 }, legR = { 2, 0, 0 }, footL = { -1, 0, 0 }, footR = { -1, 0, 0 } } },
    },
  },
}

local bones = {}
local bonesFound = 0
local applied = {}
local fadeFrom = {}
local ready = false

local currentName = nil
local currentClip = nil
local clipTime = 0
local playing = false
local looping = false
local hitFired = false
local fadeLeft = 0
local fadeDuration = 0
local baseSpeed = 1
local onComplete = nil
local onHit = nil
local hitHandler = nil
local pendingPlay = nil
local autoReturnEnabled = true

local function copyPose(src, dst)
  for i = 1, #BONE_KEYS do
    local key = BONE_KEYS[i]
    local s = src[key]
    local d = dst[key]
    if s ~= nil then
      d[1] = s[1]
      d[2] = s[2]
      d[3] = s[3]
    else
      d[1] = 0
      d[2] = 0
      d[3] = 0
    end
  end
end

local function clearPose(dst)
  for i = 1, #BONE_KEYS do
    local d = dst[BONE_KEYS[i]]
    d[1] = 0
    d[2] = 0
    d[3] = 0
  end
end

local function sampleClip(clip, time, out)
  local keys = clip.keys
  local count = #keys
  clearPose(out)
  if count == 0 then return end

  local index = 1
  while index < count and time > keys[index + 1].t do
    index = index + 1
  end
  local first = keys[index]
  local second = keys[index + 1]
  if second == nil then second = first end

  local span = second.t - first.t
  local u = 0
  if span > 0.00001 then
    u = (time - first.t) / span
  end
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  local s = u * u * (3 - 2 * u)

  for i = 1, #BONE_KEYS do
    local key = BONE_KEYS[i]
    local a = first.pose[key]
    local b = second.pose[key]
    local ax, ay, az = 0, 0, 0
    local bx, by, bz = 0, 0, 0
    if a ~= nil then ax, ay, az = a[1], a[2], a[3] end
    if b ~= nil then bx, by, bz = b[1], b[2], b[3] end
    local target = out[key]
    target[1] = ax + (bx - ax) * s
    target[2] = ay + (by - ay) * s
    target[3] = az + (bz - az) * s
  end
end

local function applyPose(pose)
  for i = 1, #BONE_KEYS do
    local key = BONE_KEYS[i]
    local bone = bones[i]
    if bone ~= nil then
      local angle = pose[key]
      bone.transform.localRotation = bone.rest * Quaternion.Euler(angle[1], angle[2], angle[3])
    end
  end
end

local function finishClip()
  playing = false
  local callback = onComplete
  onComplete = nil
  onHit = nil
  if callback ~= nil then
    pcall(callback)
  end
  if autoReturnEnabled and currentName ~= nil and currentName ~= "Idle" then
    Play("Idle", { fade = 0.2 })
  end
end

local function startClip(name, opts)
  opts = opts or {}
  local clip = CLIPS[name]
  if clip == nil then
    logger:warnOnce("unknown-action-" .. tostring(name), "未知动作", name)
    return false
  end

  copyPose(applied, fadeFrom)
  fadeDuration = opts.fade or 0.18
  if fadeDuration < 0 then fadeDuration = 0 end
  fadeLeft = fadeDuration

  currentName = name
  currentClip = clip
  clipTime = 0
  playing = true
  looping = opts.loop
  if looping == nil then looping = clip.loop == true end
  hitFired = false
  onComplete = opts.onComplete
  onHit = opts.onHit
  autoReturnEnabled = opts.autoReturn
  if autoReturnEnabled == nil then autoReturnEnabled = clip.autoReturn == true end
  if opts.speed ~= nil and opts.speed > 0 then
    baseSpeed = opts.speed
  end
  return true
end

local workPose = {}
for i = 1, #BONE_KEYS do
  applied[BONE_KEYS[i]] = { 0, 0, 0 }
  fadeFrom[BONE_KEYS[i]] = { 0, 0, 0 }
  workPose[BONE_KEYS[i]] = { 0, 0, 0 }
end

-- 播放指定动作。opts: loop, speed, fade, onComplete, onHit。
function Play(name, opts)
  if name == nil or CLIPS[name] == nil then return false end
  if not ready then
    pendingPlay = { name = name, opts = opts }
    return true
  end
  return startClip(name, opts)
end

function Stop(fade)
  return Play("Idle", { fade = fade })
end

function Pause()
  playing = false
end

function Resume()
  if currentClip ~= nil then playing = true end
end

function SetSpeed(value)
  if value ~= nil and value > 0 then baseSpeed = value end
end

function GetAction()
  return currentName or "none"
end

function GetRigStatus()
  return bonesFound, #BONE_KEYS
end

function IsPlaying(name)
  if not playing then return false end
  if name == nil then return true end
  return currentName == name
end

function GetActionDuration(name)
  local clip = CLIPS[name]
  if clip == nil then return 0 end
  return clip.duration
end

function GetHitTime(name)
  local clip = CLIPS[name]
  if clip == nil or clip.hitTime == nil then return 0 end
  return clip.hitTime
end

function IsLooping(name)
  local clip = CLIPS[name]
  if clip == nil then return false end
  return clip.loop == true
end

function RegisterHitHandler(fn)
  hitHandler = fn
end

function ClearHitHandler()
  hitHandler = nil
end

function Start()
  if runtimeScope == nil then
    logger:warnOnce("scope-missing", "无法取得资源上下文", tostring(runtimeScopeReason))
    return
  end

  for i = 1, #BONE_KEYS do
    local key = BONE_KEYS[i]
    local transform, reason = runtimeScope:GetTransformByPath(BONE_PATHS[key])
    if transform == nil then
      logger:warnOnce("bone-missing-" .. key, "缺少骨骼", key, tostring(reason))
    else
      bones[i] = { transform = transform, rest = transform.localRotation }
      bonesFound = bonesFound + 1
    end
  end
  ready = true

  baseSpeed = PlaybackSpeed
  if baseSpeed == nil or baseSpeed <= 0 then baseSpeed = 1 end

  if pendingPlay ~= nil then
    local pending = pendingPlay
    pendingPlay = nil
    startClip(pending.name, pending.opts)
    return
  end

  local preview = PreviewAction or "none"
  if preview ~= "none" and CLIPS[preview] ~= nil then
    startClip(preview, { loop = PreviewLoop })
  elseif AutoIdle ~= false then
    startClip("Idle", { fade = 0 })
  end
end

function OnDisable()
  -- 组件停用时恢复绑定时的静止姿势，避免下次启用时骨骼停在旧动作上。
  if not ready then return end
  for i = 1, #BONE_KEYS do
    local bone = bones[i]
    if bone ~= nil then
      bone.transform.localRotation = bone.rest
    end
  end
end

function Update()
  if not ready or not playing or currentClip == nil then return end

  local dt = clock.deltaTime * baseSpeed
  if dt <= 0 then return end

  local previous = clipTime
  local nextTime = clipTime + dt
  local duration = currentClip.duration
  local finished = false
  local looped = false

  if looping then
    if nextTime >= duration then
      nextTime = nextTime % duration
      looped = true
      hitFired = false
    end
  elseif nextTime >= duration then
    nextTime = duration
    finished = true
  end

  clipTime = nextTime

  if currentClip.hitTime ~= nil and not hitFired and not finished and not looped then
    local hit = currentClip.hitTime
    if previous < hit and nextTime >= hit then
      hitFired = true
      if onHit ~= nil then
        pcall(onHit)
      end
      if hitHandler ~= nil then
        pcall(hitHandler, currentName)
      end
    end
  end

  sampleClip(currentClip, clipTime, workPose)
  if fadeLeft > 0 then
    local fadeRatio = 1
    if fadeDuration > 0.00001 then
      fadeRatio = 1 - (fadeLeft / fadeDuration)
    end
    if fadeRatio < 0 then fadeRatio = 0 elseif fadeRatio > 1 then fadeRatio = 1 end
    local smooth = fadeRatio * fadeRatio * (3 - 2 * fadeRatio)
    for i = 1, #BONE_KEYS do
      local key = BONE_KEYS[i]
      local from = fadeFrom[key]
      local target = workPose[key]
      target[1] = from[1] + (target[1] - from[1]) * smooth
      target[2] = from[2] + (target[2] - from[2]) * smooth
      target[3] = from[3] + (target[3] - from[3]) * smooth
    end
    fadeLeft = fadeLeft - dt
  end

  applyPose(workPose)
  copyPose(workPose, applied)

  if finished then
    finishClip()
  end
end


Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="Idle",walk="Walk",attack="Attack",hit="Hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.caster=function(root,height)
local Play,SetSpeed,GetAction,GetActionDuration,GetHitTime,GetRigStatus,IsReady,OnEnable,Start,Update,OnDisable,OnDestroy
local DefaultAction="Idle"
local FadeTime=0.18
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 裂隙蚀光使：逐骨骼关键帧驱动待机/行走/攻击/受击，并对外提供播放与查询接口

local UnityEngine = CS.UnityEngine
local Time = clock
local Vector3 = UnityEngine.Vector3
local Quaternion = UnityEngine.Quaternion
local RuntimeScope={from=function()return boundScope end}
local Logger = require("official.core.logger")

local runtimeScope, scopeReason = RuntimeScope.from(self)
local logger = Logger.create("caster-anim")

-- 只驱动这 22 根骨骼，骨骼编辑器附加的 twist 骨骼保持静止
local BONE_ORDER = {
  "root.x",
  "spine_01.x",
  "spine_02.x",
  "spine_03.x",
  "neck.x",
  "head.x",
  "shoulder.l",
  "arm_stretch.l",
  "forearm_stretch.l",
  "hand.l",
  "shoulder.r",
  "arm_stretch.r",
  "forearm_stretch.r",
  "hand.r",
  "thigh_stretch.l",
  "leg_stretch.l",
  "foot.l",
  "toes_01.l",
  "thigh_stretch.r",
  "leg_stretch.r",
  "foot.r",
  "toes_01.r",
}

local CLIP_DATA = {
  Idle = {
    duration = 2.4, loop = true, count = 29,
    bones = {
      ["root.x"] = {0,0.005,0.002,1,0,0.006,0.003,1,0,0.007,0.005,1,0,0.008,0.006,1,0,0.009,0.006,1,0,0.009,0.007,1,0,0.008,0.007,1,0,0.007,0.007,1,0,0.006,0.006,1,0,0.005,0.005,1,0,0.003,0.004,1,0,0.001,0.003,1,0,-0.001,0.002,1,0,-0.002,0,1,0,-0.004,-0.001,1,0,-0.006,-0.003,1,0,-0.007,-0.004,1,0,-0.008,-0.005,1,0,-0.009,-0.006,1,0,-0.009,-0.007,1,0,-0.009,-0.007,1,0,-0.008,-0.007,1,0,-0.007,-0.007,1,0,-0.006,-0.006,1,0,-0.004,-0.005,1,0,-0.002,-0.004,1,0,0,-0.002,1,0,0.001,-0.001,1,0,0.003,0.001,1},
      ["spine_01.x"] = {0.011,-0.001,0.002,1,0.012,0,0.003,1,0.013,0.001,0.004,1,0.013,0.001,0.004,1,0.014,0.002,0.005,1,0.014,0.002,0.005,1,0.014,0.003,0.005,1,0.013,0.003,0.005,1,0.013,0.003,0.005,1,0.012,0.003,0.004,1,0.011,0.002,0.004,1,0.009,0.002,0.003,1,0.008,0.001,0.002,1,0.007,0.001,0.001,1,0.006,0,0,1,0.004,-0.001,-0.001,1,0.003,-0.002,-0.002,1,0.003,-0.002,-0.003,1,0.002,-0.003,-0.003,1,0.002,-0.003,-0.004,1,0.002,-0.004,-0.004,1,0.002,-0.004,-0.004,1,0.003,-0.004,-0.004,1,0.003,-0.004,-0.003,1,0.004,-0.004,-0.003,1,0.006,-0.003,-0.002,1,0.007,-0.003,-0.001,1,0.008,-0.002,0,1,0.009,-0.002,0.001,1},
      ["spine_02.x"] = {0.005,0.003,0.002,1,0.005,0.004,0.003,1,0.006,0.006,0.003,1,0.006,0.007,0.003,1,0.006,0.007,0.003,1,0.005,0.007,0.002,1,0.005,0.007,0.002,1,0.004,0.007,0.002,1,0.003,0.006,0.001,1,0.002,0.005,0,1,0,0.004,0,1,-0.001,0.002,-0.001,1,-0.002,0.001,-0.001,1,-0.003,-0.001,-0.002,1,-0.004,-0.002,-0.002,1,-0.005,-0.004,-0.002,1,-0.006,-0.005,-0.003,1,-0.006,-0.006,-0.003,1,-0.006,-0.007,-0.003,1,-0.006,-0.007,-0.002,1,-0.005,-0.007,-0.002,1,-0.004,-0.007,-0.002,1,-0.003,-0.007,-0.001,1,-0.002,-0.006,-0.001,1,-0.001,-0.004,0,1,0,-0.003,0,1,0.002,-0.002,0.001,1,0.003,0,0.001,1,0.004,0.002,0.002,1},
      ["spine_03.x"] = {0.004,0.004,0.006,1,0.004,0.005,0.007,1,0.004,0.006,0.007,1,0.004,0.007,0.007,1,0.004,0.007,0.007,1,0.003,0.007,0.006,1,0.002,0.007,0.005,1,0.001,0.006,0.004,1,0.001,0.005,0.002,1,0,0.004,0.001,1,-0.001,0.003,-0.001,1,-0.002,0.001,-0.002,1,-0.003,0,-0.003,1,-0.004,-0.002,-0.005,1,-0.004,-0.004,-0.006,1,-0.004,-0.005,-0.006,1,-0.004,-0.006,-0.007,1,-0.004,-0.007,-0.007,1,-0.004,-0.007,-0.007,1,-0.003,-0.007,-0.006,1,-0.003,-0.007,-0.006,1,-0.002,-0.007,-0.004,1,-0.001,-0.006,-0.003,1,0,-0.005,-0.002,1,0.001,-0.003,0,1,0.002,-0.002,0.001,1,0.003,0,0.003,1,0.003,0.001,0.004,1,0.004,0.003,0.005,1},
      ["neck.x"] = {-0.001,0.008,0.001,1,-0.002,0.009,0.001,1,-0.003,0.009,0.001,1,-0.004,0.009,0,1,-0.004,0.008,0,1,-0.005,0.007,0,1,-0.005,0.006,0,1,-0.005,0.005,0,1,-0.005,0.003,0,1,-0.004,0.001,0,1,-0.004,-0.001,0,1,-0.003,-0.003,0,1,-0.002,-0.005,0,1,-0.001,-0.006,-0.001,1,0,-0.007,-0.001,1,0.001,-0.008,-0.001,1,0.002,-0.009,-0.001,1,0.003,-0.009,-0.001,1,0.004,-0.009,-0.001,1,0.004,-0.008,0,1,0.005,-0.007,0,1,0.005,-0.005,0,1,0.005,-0.004,0,1,0.005,-0.002,0,1,0.004,0,0,1,0.003,0.002,0,1,0.002,0.004,0,1,0.001,0.005,0.001,1,0,0.007,0.001,1},
      ["head.x"] = {-0.011,0.023,0.004,1,-0.014,0.022,0.006,1,-0.016,0.02,0.007,1,-0.017,0.017,0.008,1,-0.017,0.013,0.008,1,-0.017,0.008,0.008,1,-0.015,0.003,0.008,1,-0.013,-0.002,0.007,1,-0.011,-0.006,0.006,1,-0.008,-0.011,0.005,1,-0.004,-0.015,0.003,1,0,-0.019,0.002,1,0.003,-0.021,0,1,0.007,-0.023,-0.002,1,0.01,-0.023,-0.004,1,0.013,-0.022,-0.006,1,0.015,-0.021,-0.007,1,0.017,-0.018,-0.008,1,0.017,-0.014,-0.009,1,0.017,-0.01,-0.009,1,0.016,-0.006,-0.008,1,0.014,-0.001,-0.008,1,0.012,0.004,-0.007,1,0.009,0.009,-0.006,1,0.006,0.013,-0.004,1,0.002,0.017,-0.002,1,-0.002,0.02,-0.001,1,-0.005,0.022,0.001,1,-0.009,0.023,0.003,1},
      ["shoulder.l"] = {0.002,0.002,0.002,1,0.003,0.002,0.002,1,0.004,0.003,0.003,1,0.004,0.003,0.003,1,0.005,0.004,0.003,1,0.005,0.004,0.003,1,0.005,0.004,0.003,1,0.004,0.003,0.003,1,0.004,0.003,0.003,1,0.003,0.002,0.002,1,0.002,0.002,0.002,1,0.001,0.001,0.001,1,0,0,0,1,-0.001,-0.001,-0.001,1,-0.002,-0.001,-0.001,1,-0.003,-0.002,-0.002,1,-0.004,-0.003,-0.002,1,-0.004,-0.003,-0.003,1,-0.005,-0.004,-0.003,1,-0.005,-0.004,-0.003,1,-0.005,-0.004,-0.003,1,-0.005,-0.004,-0.003,1,-0.004,-0.003,-0.003,1,-0.003,-0.003,-0.002,1,-0.003,-0.002,-0.002,1,-0.002,-0.001,-0.001,1,-0.001,-0.001,0,1,0,0,0,1,0.001,0.001,0.001,1},
      ["arm_stretch.l"] = {0.008,0.005,0.003,1,0.011,0.007,0.002,1,0.014,0.008,0.002,1,0.016,0.009,0.001,1,0.017,0.01,0,1,0.018,0.01,-0.001,1,0.017,0.009,-0.001,1,0.016,0.008,-0.002,1,0.014,0.007,-0.003,1,0.012,0.005,-0.003,1,0.008,0.004,-0.003,1,0.005,0.002,-0.003,1,0.001,0,-0.003,1,-0.003,-0.002,-0.003,1,-0.006,-0.004,-0.003,1,-0.01,-0.006,-0.003,1,-0.013,-0.007,-0.002,1,-0.015,-0.008,-0.001,1,-0.017,-0.009,-0.001,1,-0.018,-0.009,0,1,-0.018,-0.009,0.001,1,-0.017,-0.009,0.002,1,-0.015,-0.007,0.002,1,-0.013,-0.006,0.003,1,-0.01,-0.004,0.003,1,-0.007,-0.003,0.003,1,-0.003,-0.001,0.003,1,0.001,0.001,0.003,1,0.005,0.003,0.003,1},
      ["forearm_stretch.l"] = {-0.004,-0.008,-0.007,1,-0.005,-0.009,-0.008,1,-0.005,-0.01,-0.009,1,-0.005,-0.01,-0.009,1,-0.005,-0.009,-0.008,1,-0.004,-0.008,-0.008,1,-0.004,-0.007,-0.007,1,-0.003,-0.006,-0.005,1,-0.002,-0.004,-0.003,1,-0.001,-0.002,-0.002,1,0,0,0,1,0.001,0.002,0.002,1,0.002,0.004,0.004,1,0.003,0.006,0.005,1,0.004,0.008,0.007,1,0.004,0.009,0.008,1,0.005,0.009,0.009,1,0.005,0.01,0.009,1,0.005,0.01,0.009,1,0.004,0.009,0.008,1,0.004,0.008,0.007,1,0.003,0.006,0.006,1,0.002,0.005,0.004,1,0.001,0.003,0.003,1,0,0.001,0.001,1,-0.001,-0.001,-0.001,1,-0.002,-0.003,-0.003,1,-0.003,-0.005,-0.005,1,-0.003,-0.007,-0.006,1},
      ["hand.l"] = {0.003,0.006,0.005,1,0.003,0.006,0.005,1,0.003,0.006,0.005,1,0.003,0.006,0.005,1,0.003,0.005,0.005,1,0.002,0.005,0.004,1,0.002,0.004,0.003,1,0.001,0.002,0.002,1,0.001,0.001,0.001,1,0,0,0,1,-0.001,-0.001,-0.001,1,-0.001,-0.003,-0.002,1,-0.002,-0.004,-0.003,1,-0.002,-0.005,-0.004,1,-0.003,-0.005,-0.005,1,-0.003,-0.006,-0.005,1,-0.003,-0.006,-0.005,1,-0.003,-0.006,-0.005,1,-0.003,-0.006,-0.005,1,-0.003,-0.005,-0.005,1,-0.002,-0.004,-0.004,1,-0.002,-0.003,-0.003,1,-0.001,-0.002,-0.002,1,0,-0.001,-0.001,1,0,0.001,0.001,1,0.001,0.002,0.002,1,0.002,0.003,0.003,1,0.002,0.004,0.004,1,0.003,0.005,0.005,1},
      ["shoulder.r"] = {0,0,0,1},
      ["arm_stretch.r"] = {0,0,0,1},
      ["forearm_stretch.r"] = {0,0,0,1},
      ["hand.r"] = {0.007,-0.014,0,1,0.01,-0.012,0.002,1,0.012,-0.011,0.003,1,0.014,-0.011,0.003,1,0.014,-0.011,0.003,1,0.014,-0.012,0.003,1,0.013,-0.014,0.002,1,0.011,-0.016,0.001,1,0.008,-0.018,0,1,0.005,-0.021,-0.002,1,0.002,-0.024,-0.003,1,-0.002,-0.028,-0.005,1,-0.006,-0.031,-0.007,0.999,-0.01,-0.034,-0.009,0.999,-0.013,-0.036,-0.011,0.999,-0.016,-0.038,-0.012,0.999,-0.019,-0.04,-0.013,0.999,-0.02,-0.041,-0.014,0.999,-0.021,-0.041,-0.014,0.999,-0.022,-0.04,-0.014,0.999,-0.021,-0.039,-0.014,0.999,-0.019,-0.037,-0.013,0.999,-0.017,-0.034,-0.012,0.999,-0.014,-0.031,-0.01,0.999,-0.011,-0.028,-0.009,1,-0.007,-0.025,-0.007,1,-0.004,-0.022,-0.005,1,0,-0.019,-0.003,1,0.004,-0.016,-0.001,1},
      ["thigh_stretch.l"] = {0,-0.005,-0.008,-1,0.011,-0.006,0.005,-1,0.011,-0.008,0.004,-1,0.012,-0.008,0.002,-1,0.012,-0.009,0.002,-1,0.012,-0.009,0.001,-1,0.012,-0.009,0.001,-1,0.012,-0.008,0.002,-1,0.011,-0.007,0.003,-1,0.01,-0.005,0.005,-1,0.01,-0.003,0.007,-1,0.009,-0.002,0.009,-1,0.008,0,0.011,-1,0.007,0.002,0.014,-1,0.006,0.004,0.016,-1,-0.013,0.006,-0.01,-1,-0.03,0.007,-0.033,-0.999,-0.038,0.008,-0.043,-0.998,-0.043,0.009,-0.05,-0.998,-0.047,0.009,-0.055,-0.997,-0.05,0.009,-0.059,-0.997,-0.051,0.009,-0.061,-0.997,-0.051,0.008,-0.063,-0.997,-0.05,0.006,-0.064,-0.997,-0.048,0.005,-0.063,-0.997,-0.045,0.003,-0.062,-0.997,-0.041,0.001,-0.058,-0.997,-0.035,-0.001,-0.053,-0.998,-0.026,-0.003,-0.043,-0.999},
      ["leg_stretch.l"] = {-0.004,0,-0.007,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,0.014,0,0.027,1,-0.018,-0.001,-0.036,0.999,-0.046,-0.001,-0.09,0.995,-0.059,-0.001,-0.115,0.992,-0.068,-0.001,-0.132,0.989,-0.074,-0.002,-0.144,0.987,-0.079,-0.002,-0.152,0.985,-0.081,-0.001,-0.157,0.984,-0.082,-0.001,-0.159,0.984,-0.081,-0.001,-0.158,0.984,-0.079,-0.001,-0.153,0.985,-0.075,-0.001,-0.145,0.987,-0.069,0,-0.133,0.989,-0.06,0,-0.116,0.991,-0.046,0,-0.09,0.995},
      ["foot.l"] = {0.002,0.001,0.002,1,-0.001,0.011,-0.014,1,-0.001,0.012,-0.014,1,0,0.012,-0.014,1,0,0.012,-0.014,1,0,0.012,-0.014,1,-0.001,0.012,-0.014,1,-0.001,0.012,-0.014,1,-0.001,0.011,-0.014,1,-0.002,0.01,-0.014,1,-0.002,0.009,-0.013,1,-0.003,0.008,-0.013,1,-0.003,0.007,-0.013,1,-0.004,0.006,-0.012,1,-0.004,0.005,-0.012,1,0.002,-0.014,0.018,1,0.007,-0.031,0.045,0.998,0.009,-0.039,0.057,0.998,0.011,-0.045,0.065,0.997,0.012,-0.049,0.071,0.996,0.013,-0.051,0.075,0.996,0.014,-0.052,0.078,0.996,0.014,-0.052,0.078,0.995,0.015,-0.051,0.077,0.996,0.015,-0.049,0.075,0.996,0.014,-0.045,0.07,0.996,0.014,-0.04,0.064,0.997,0.012,-0.034,0.056,0.998,0.01,-0.025,0.043,0.999},
      ["toes_01.l"] = {0,0,0,1},
      ["thigh_stretch.r"] = {0.001,-0.005,-0.008,-1,0,-0.006,-0.009,-1,0,-0.008,-0.01,-1,-0.001,-0.008,-0.011,-1,-0.001,-0.009,-0.011,-1,-0.001,-0.009,-0.012,-1,-0.001,-0.008,-0.011,-1,0,-0.008,-0.01,-1,0,-0.006,-0.009,-1,0.001,-0.005,-0.008,-1,0.002,-0.003,-0.006,-1,0.003,-0.002,-0.005,-1,0.004,0,-0.003,-1,0.005,0.002,-0.001,-1,0.002,0.004,0.004,-1,-0.032,0.006,0.033,-0.999,-0.05,0.007,0.048,-0.998,-0.059,0.008,0.057,-0.997,-0.065,0.009,0.062,-0.996,-0.069,0.009,0.066,-0.995,-0.072,0.009,0.067,-0.995,-0.073,0.009,0.068,-0.995,-0.073,0.008,0.067,-0.995,-0.072,0.006,0.064,-0.995,-0.069,0.005,0.06,-0.996,-0.065,0.003,0.054,-0.996,-0.058,0.001,0.046,-0.997,-0.046,-0.001,0.035,-0.998,-0.01,-0.003,0.003,-1},
      ["leg_stretch.r"] = {0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0.008,0,-0.007,1,0,0,0,1,-0.068,0,0.06,0.996,-0.103,-0.001,0.092,0.99,-0.122,0,0.109,0.987,-0.134,0,0.12,0.984,-0.142,0,0.127,0.982,-0.147,0,0.132,0.98,-0.149,0,0.133,0.98,-0.148,0,0.133,0.98,-0.145,0,0.129,0.981,-0.138,0.001,0.123,0.983,-0.127,0.001,0.114,0.985,-0.112,0.001,0.1,0.989,-0.087,0.001,0.078,0.993,-0.015,0,0.013,1},
      ["foot.r"] = {0.001,0.003,0.004,1,0.001,0.004,0.004,1,0.001,0.004,0.005,1,0.001,0.004,0.005,1,0.001,0.003,0.005,1,0.001,0.003,0.005,1,0.001,0.003,0.005,1,0.002,0.002,0.005,1,0.002,0.002,0.005,1,0.003,0.001,0.005,1,0.003,0,0.005,1,0.003,0,0.005,1,0.004,-0.001,0.005,1,0.004,-0.002,0.005,1,0.002,-0.003,0,1,-0.02,-0.007,-0.04,0.999,-0.031,-0.009,-0.062,0.998,-0.037,-0.01,-0.073,0.997,-0.041,-0.01,-0.081,0.996,-0.044,-0.01,-0.086,0.995,-0.046,-0.01,-0.089,0.995,-0.047,-0.01,-0.09,0.995,-0.047,-0.009,-0.09,0.995,-0.047,-0.008,-0.088,0.995,-0.045,-0.007,-0.084,0.995,-0.042,-0.006,-0.078,0.996,-0.037,-0.005,-0.068,0.997,-0.029,-0.003,-0.053,0.998,-0.006,0.001,-0.009,1},
      ["toes_01.r"] = {0,0,0,1},
    },
    rootOffset = {0.004,0,0,0.005,0.002,0,0.005,0.003,0,0.005,0.005,0,0.005,0.006,0,0.004,0.007,0,0.004,0.008,0,0.003,0.008,0,0.002,0.008,0,0.001,0.007,0,0,0.007,0,-0.001,0.006,0,-0.002,0.004,0,-0.003,0.003,0,-0.004,0.001,0,-0.004,-0.001,0,-0.005,-0.003,0,-0.005,-0.004,0,-0.005,-0.006,0,-0.005,-0.007,0,-0.004,-0.007,0,-0.003,-0.008,0,-0.002,-0.008,0,-0.001,-0.008,0,0,-0.007,0,0.001,-0.006,0,0.002,-0.005,0,0.003,-0.003,0,0.004,-0.002,0},
  },
  Walk = {
    duration = 1, loop = true, count = 18,
    bones = {
      ["root.x"] = {0.005,0,0,1,0.005,0.01,0.006,1,0.005,0.019,0.011,1,0.005,0.026,0.015,1,0.005,0.029,0.017,0.999,0.005,0.029,0.017,0.999,0.005,0.026,0.015,1,0.005,0.019,0.011,1,0.005,0.01,0.006,1,0.005,0,0,1,0.005,-0.01,-0.006,1,0.006,-0.019,-0.012,1,0.006,-0.025,-0.016,1,0.006,-0.029,-0.018,0.999,0.006,-0.029,-0.018,0.999,0.006,-0.025,-0.016,1,0.006,-0.019,-0.012,1,0.005,-0.01,-0.006,1},
      ["spine_01.x"] = {0.001,0,0,1,0.002,-0.006,-0.003,1,0.005,-0.012,-0.005,1,0.009,-0.016,-0.006,1,0.012,-0.019,-0.007,1,0.012,-0.019,-0.007,1,0.009,-0.016,-0.006,1,0.005,-0.012,-0.005,1,0.002,-0.006,-0.003,1,0.001,0,0,1,0.003,0.006,0.003,1,0.006,0.011,0.006,1,0.011,0.015,0.008,1,0.013,0.017,0.009,1,0.013,0.017,0.009,1,0.011,0.015,0.008,1,0.006,0.011,0.006,1,0.003,0.006,0.003,1},
      ["spine_02.x"] = {0.007,0,0,1,0.007,-0.005,-0.002,1,0.007,-0.009,-0.004,1,0.007,-0.012,-0.005,1,0.007,-0.014,-0.006,1,0.007,-0.014,-0.006,1,0.007,-0.012,-0.005,1,0.007,-0.009,-0.004,1,0.007,-0.005,-0.002,1,0.007,0,0,1,0.007,0.005,0.002,1,0.007,0.01,0.003,1,0.007,0.013,0.005,1,0.007,0.015,0.005,1,0.007,0.015,0.005,1,0.007,0.013,0.005,1,0.007,0.01,0.003,1,0.007,0.005,0.002,1},
      ["spine_03.x"] = {0.003,0,0,1,0.003,-0.003,-0.003,1,0.003,-0.006,-0.005,1,0.003,-0.008,-0.007,1,0.003,-0.009,-0.008,1,0.003,-0.009,-0.008,1,0.003,-0.008,-0.007,1,0.003,-0.006,-0.005,1,0.003,-0.003,-0.003,1,0.003,0,0,1,0.004,0.003,0.003,1,0.004,0.006,0.005,1,0.004,0.008,0.007,1,0.004,0.009,0.008,1,0.004,0.009,0.008,1,0.004,0.008,0.007,1,0.004,0.006,0.005,1,0.004,0.003,0.003,1},
      ["neck.x"] = {-0.007,0,0,1,-0.007,0.004,0,1,-0.007,0.007,0,1,-0.007,0.009,0,1,-0.007,0.01,0,1,-0.007,0.01,0,1,-0.007,0.009,0,1,-0.007,0.007,0,1,-0.007,0.004,0,1,-0.007,0,0,1,-0.007,-0.003,-0.001,1,-0.007,-0.006,-0.001,1,-0.007,-0.008,-0.001,1,-0.007,-0.009,-0.001,1,-0.007,-0.009,-0.001,1,-0.007,-0.008,-0.001,1,-0.007,-0.006,-0.001,1,-0.007,-0.003,-0.001,1},
      ["head.x"] = {-0.005,0,0,1,-0.006,0.005,-0.002,1,-0.009,0.009,-0.004,1,-0.012,0.012,-0.005,1,-0.014,0.014,-0.006,1,-0.014,0.014,-0.006,1,-0.012,0.012,-0.005,1,-0.009,0.009,-0.004,1,-0.006,0.005,-0.002,1,-0.005,0,0,1,-0.007,-0.004,0.001,1,-0.01,-0.008,0.003,1,-0.014,-0.011,0.004,1,-0.016,-0.012,0.004,1,-0.016,-0.012,0.004,1,-0.014,-0.011,0.004,1,-0.01,-0.008,0.003,1,-0.007,-0.004,0.001,1},
      ["shoulder.l"] = {0,0,0,1,-0.025,-0.019,-0.017,0.999,-0.047,-0.036,-0.032,0.998,-0.063,-0.049,-0.043,0.996,-0.071,-0.055,-0.049,0.995,-0.071,-0.055,-0.049,0.995,-0.063,-0.049,-0.043,0.996,-0.047,-0.036,-0.032,0.998,-0.025,-0.019,-0.017,0.999,0,0,0,1,0.025,0.019,0.017,0.999,0.047,0.036,0.032,0.998,0.063,0.049,0.043,0.996,0.071,0.055,0.049,0.995,0.071,0.055,0.049,0.995,0.063,0.049,0.043,0.996,0.047,0.036,0.032,0.998,0.025,0.019,0.017,0.999},
      ["arm_stretch.l"] = {-0.044,-0.022,0.003,0.999,-0.061,-0.034,-0.008,0.998,-0.073,-0.042,-0.016,0.996,-0.077,-0.045,-0.019,0.996,-0.074,-0.042,-0.016,0.996,-0.063,-0.035,-0.01,0.997,-0.047,-0.024,0.001,0.999,-0.026,-0.01,0.014,1,-0.004,0.006,0.028,1,0.017,0.02,0.042,0.999,0.034,0.032,0.053,0.998,0.046,0.04,0.06,0.996,0.05,0.043,0.063,0.996,0.047,0.04,0.061,0.996,0.036,0.033,0.054,0.997,0.019,0.022,0.044,0.999,-0.001,0.008,0.03,1,-0.023,-0.008,0.016,1},
      ["forearm_stretch.l"] = {-0.033,-0.065,-0.059,0.996,-0.037,-0.073,-0.066,0.994,-0.039,-0.077,-0.07,0.994,-0.039,-0.078,-0.071,0.994,-0.038,-0.076,-0.069,0.994,-0.035,-0.07,-0.064,0.995,-0.031,-0.061,-0.056,0.996,-0.026,-0.051,-0.047,0.997,-0.021,-0.041,-0.037,0.998,-0.016,-0.031,-0.028,0.999,-0.012,-0.024,-0.022,0.999,-0.01,-0.019,-0.018,1,-0.009,-0.018,-0.017,1,-0.01,-0.021,-0.019,1,-0.013,-0.027,-0.024,0.999,-0.018,-0.035,-0.032,0.999,-0.023,-0.045,-0.041,0.998,-0.028,-0.056,-0.051,0.997},
      ["hand.l"] = {0.009,0.017,0.016,1,0.011,0.022,0.02,0.999,0.012,0.024,0.022,0.999,0.012,0.023,0.021,0.999,0.01,0.02,0.018,1,0.007,0.014,0.012,1,0.003,0.006,0.005,1,-0.001,-0.002,-0.002,1,-0.005,-0.011,-0.01,1,-0.009,-0.017,-0.016,1,-0.011,-0.022,-0.02,0.999,-0.012,-0.024,-0.022,0.999,-0.012,-0.023,-0.021,0.999,-0.01,-0.02,-0.018,1,-0.007,-0.014,-0.012,1,-0.003,-0.006,-0.005,1,0.001,0.002,0.002,1,0.005,0.011,0.01,1},
      ["shoulder.r"] = {0,0,0,1,0.013,-0.005,-0.006,1,0.024,-0.01,-0.011,1,0.032,-0.014,-0.015,0.999,0.036,-0.016,-0.017,0.999,0.036,-0.016,-0.017,0.999,0.032,-0.014,-0.015,0.999,0.024,-0.01,-0.011,1,0.013,-0.005,-0.006,1,0,0,0,1,-0.013,0.005,0.006,1,-0.024,0.01,0.011,1,-0.032,0.014,0.015,0.999,-0.036,0.016,0.017,0.999,-0.036,0.016,0.017,0.999,-0.032,0.014,0.015,0.999,-0.024,0.01,0.011,1,-0.013,0.005,0.006,1},
      ["arm_stretch.r"] = {0,0,0,1,-0.005,0.006,0.004,1,-0.01,0.011,0.008,1,-0.013,0.015,0.01,1,-0.015,0.017,0.012,1,-0.015,0.017,0.012,1,-0.013,0.015,0.01,1,-0.01,0.011,0.008,1,-0.005,0.006,0.004,1,0,0,0,1,0.005,-0.006,-0.004,1,0.01,-0.011,-0.008,1,0.013,-0.015,-0.01,1,0.015,-0.017,-0.012,1,0.015,-0.017,-0.012,1,0.013,-0.015,-0.01,1,0.01,-0.011,-0.008,1,0.005,-0.006,-0.004,1},
      ["forearm_stretch.r"] = {-0.001,-0.008,-0.003,1,-0.002,-0.012,-0.004,1,-0.002,-0.015,-0.005,1,-0.002,-0.016,-0.006,1,-0.002,-0.016,-0.005,1,-0.002,-0.013,-0.004,1,-0.001,-0.009,-0.003,1,0,-0.003,-0.001,1,0,0.002,0.001,1,0.001,0.008,0.003,1,0.002,0.012,0.004,1,0.002,0.015,0.005,1,0.002,0.016,0.006,1,0.002,0.016,0.005,1,0.002,0.013,0.004,1,0.001,0.009,0.003,1,0,0.003,0.001,1,0,-0.002,-0.001,1},
      ["hand.r"] = {-0.003,-0.021,-0.005,1,-0.003,-0.015,-0.003,1,-0.003,-0.006,-0.002,1,-0.002,0.002,0,1,-0.002,0.008,0.001,1,-0.002,0.009,0.001,1,-0.002,0.006,0,1,-0.002,0,-0.001,1,-0.002,-0.007,-0.002,1,-0.002,-0.013,-0.003,1,-0.001,-0.016,-0.003,1,0,-0.017,-0.003,1,0.002,-0.017,-0.002,1,0.002,-0.018,-0.002,1,0.002,-0.019,-0.002,1,0.001,-0.021,-0.003,1,-0.001,-0.024,-0.004,1,-0.002,-0.024,-0.005,1},
      ["thigh_stretch.l"] = {0.038,0,-0.083,-0.996,0.021,-0.01,-0.095,-0.995,0.012,-0.019,-0.095,-0.995,0.01,-0.026,-0.082,-0.996,0.045,-0.029,-0.012,-0.998,0.026,-0.029,-0.014,-0.999,-0.011,-0.026,-0.037,-0.999,-0.05,-0.02,-0.056,-0.997,-0.083,-0.011,-0.066,-0.994,-0.121,0,-0.083,-0.989,-0.186,0.011,-0.14,-0.972,-0.149,0.021,-0.083,-0.985,-0.16,0.029,-0.119,-0.98,-0.148,0.032,-0.137,-0.979,-0.12,0.032,-0.141,-0.982,-0.079,0.028,-0.134,-0.987,-0.031,0.02,-0.116,-0.993,0.022,0.011,-0.081,-0.996},
      ["leg_stretch.l"] = {-0.112,0.028,-0.221,0.968,-0.113,0.023,-0.22,0.969,-0.1,0.018,-0.194,0.976,-0.075,0.011,-0.144,0.987,0.014,0.003,0.027,1,0.014,0.001,0.027,1,-0.014,-0.001,-0.028,1,-0.041,-0.005,-0.08,0.996,-0.058,-0.011,-0.115,0.992,-0.082,-0.019,-0.165,0.983,-0.148,-0.04,-0.302,0.941,-0.095,-0.028,-0.193,0.976,-0.146,-0.032,-0.292,0.945,-0.178,-0.025,-0.349,0.92,-0.194,-0.011,-0.375,0.907,-0.191,0.005,-0.369,0.91,-0.169,0.019,-0.329,0.929,-0.121,0.025,-0.237,0.964},
      ["foot.l"] = {0.083,-0.057,0.185,0.978,0.073,-0.055,0.168,0.981,0.061,-0.045,0.139,0.987,0.045,-0.029,0.099,0.994,0.017,0.022,0,1,0.005,0.019,-0.014,1,-0.003,-0.002,-0.002,1,-0.012,-0.024,0.009,1,-0.02,-0.04,0.018,0.999,-0.012,-0.048,0.069,0.996,0.011,-0.068,0.203,0.977,-0.059,-0.098,-0.005,0.993,-0.047,-0.142,0.03,0.988,-0.026,-0.165,0.064,0.984,0,-0.171,0.099,0.98,0.026,-0.159,0.131,0.978,0.048,-0.13,0.154,0.978,0.064,-0.078,0.155,0.983},
      ["toes_01.l"] = {0,0,0,1},
      ["thigh_stretch.r"] = {-0.151,-0.001,0.079,-0.985,-0.234,-0.012,0.12,-0.965,-0.176,-0.022,0.072,-0.981,-0.203,-0.029,0.095,-0.974,-0.201,-0.033,0.102,-0.974,-0.178,-0.033,0.099,-0.979,-0.137,-0.029,0.088,-0.986,-0.084,-0.021,0.072,-0.994,-0.024,-0.011,0.051,-0.998,-0.005,-0.001,0.053,-0.999,-0.02,0.01,0.068,-0.997,-0.025,0.019,0.074,-0.997,-0.021,0.026,0.07,-0.997,0.005,0.029,0.047,-0.998,0.023,0.028,0.023,-0.999,-0.032,0.025,0.05,-0.998,-0.073,0.019,0.063,-0.995,-0.099,0.01,0.062,-0.993},
      ["leg_stretch.r"] = {-0.157,0.012,0.143,0.977,-0.26,0.027,0.241,0.935,-0.162,0.017,0.149,0.975,-0.242,0.022,0.221,0.944,-0.291,0.021,0.263,0.919,-0.314,0.015,0.282,0.907,-0.31,0.005,0.277,0.909,-0.277,-0.004,0.249,0.928,-0.214,-0.01,0.193,0.957,-0.202,-0.013,0.183,0.962,-0.206,-0.012,0.185,0.961,-0.188,-0.01,0.169,0.968,-0.15,-0.007,0.135,0.979,-0.069,-0.004,0.062,0.996,0.001,-0.001,-0.001,1,-0.065,0,0.058,0.996,-0.101,0.002,0.091,0.991,-0.106,0.005,0.096,0.99},
      ["foot.r"] = {-0.062,-0.001,-0.067,0.996,-0.146,-0.041,-0.171,0.973,-0.023,0.068,0.001,0.997,-0.038,0.078,-0.046,0.995,-0.05,0.076,-0.09,0.992,-0.06,0.061,-0.132,0.988,-0.071,0.037,-0.166,0.983,-0.078,0.008,-0.186,0.979,-0.079,-0.025,-0.186,0.979,-0.093,-0.051,-0.21,0.972,-0.087,-0.047,-0.195,0.976,-0.073,-0.042,-0.166,0.983,-0.053,-0.035,-0.125,0.99,-0.02,-0.024,-0.059,0.998,0.007,-0.012,-0.001,1,-0.011,-0.005,-0.024,1,-0.02,0.005,-0.03,0.999,-0.023,0.014,-0.021,0.999},
      ["toes_01.r"] = {0,0,0,1},
    },
    rootOffset = {0,-0.018,0,0.005,-0.016,0,0.009,-0.01,0,0.012,-0.003,0,0.014,0.001,0,0.014,0.001,0,0.012,-0.003,0,0.009,-0.01,0,0.005,-0.016,0,0,-0.018,0,-0.005,-0.016,0,-0.009,-0.01,0,-0.012,-0.003,0,-0.014,0.001,0,-0.014,0.001,0,-0.012,-0.003,0,-0.009,-0.01,0,-0.005,-0.016,0},
  },
  Attack = {
    duration = 1.2, loop = false, count = 32,
    hitTime = 0.62, 
    bones = {
      ["root.x"] = {0,0,0,1,-0.001,-0.004,0,1,-0.002,-0.015,0,1,-0.004,-0.028,0,1,-0.005,-0.039,0,0.999,-0.006,-0.045,0.001,0.999,-0.007,-0.048,0.001,0.999,-0.009,-0.058,0.001,0.998,-0.012,-0.071,0.002,0.997,-0.015,-0.084,0.002,0.996,-0.017,-0.094,0.003,0.995,-0.018,-0.097,0.003,0.995,-0.018,-0.097,0.003,0.995,-0.018,-0.097,0.003,0.995,-0.004,-0.049,0,0.999,0.02,0.032,0,0.999,0.033,0.076,0.001,0.997,0.03,0.067,0.001,0.997,0.024,0.049,0,0.999,0.019,0.038,0,0.999,0.019,0.037,0,0.999,0.018,0.035,0,0.999,0.016,0.031,0,0.999,0.013,0.026,0,1,0.011,0.021,0,1,0.008,0.016,0,1,0.005,0.011,0,1,0.003,0.006,0,1,0.001,0.003,0,1,0,0,0,1,0,0,0,1,0,0,0,1},
      ["spine_01.x"] = {0,0,0,1,-0.001,-0.002,0,1,-0.004,-0.005,0,1,-0.008,-0.01,0,1,-0.011,-0.014,0.001,1,-0.012,-0.016,0.001,1,-0.014,-0.017,0.001,1,-0.018,-0.02,0.001,1,-0.023,-0.025,0.001,0.999,-0.029,-0.029,0.001,0.999,-0.033,-0.032,0.001,0.999,-0.034,-0.033,0.001,0.999,-0.034,-0.033,0.001,0.999,-0.034,-0.033,0.001,0.999,-0.01,-0.017,0.001,1,0.031,0.009,0.002,0.999,0.053,0.024,0.004,0.998,0.048,0.021,0.003,0.999,0.037,0.015,0.002,0.999,0.03,0.012,0.002,0.999,0.03,0.011,0.002,0.999,0.028,0.011,0.002,1,0.025,0.009,0.001,1,0.021,0.008,0.001,1,0.017,0.006,0.001,1,0.013,0.005,0.001,1,0.009,0.003,0,1,0.005,0.002,0,1,0.002,0.001,0,1,0,0,0,1,0,0,0,1,0,0,0,1},
      ["spine_02.x"] = {0,0,0,1,-0.001,-0.002,0,1,-0.003,-0.007,0.001,1,-0.006,-0.014,0.002,1,-0.008,-0.019,0.002,1,-0.009,-0.022,0.003,1,-0.01,-0.024,0.003,1,-0.013,-0.029,0.004,0.999,-0.018,-0.035,0.005,0.999,-0.022,-0.042,0.006,0.999,-0.025,-0.047,0.007,0.999,-0.026,-0.048,0.007,0.998,-0.026,-0.048,0.007,0.998,-0.026,-0.048,0.007,0.998,-0.006,-0.024,0.003,1,0.027,0.016,-0.002,1,0.045,0.038,-0.004,0.998,0.04,0.034,-0.003,0.999,0.031,0.025,-0.003,0.999,0.026,0.019,-0.002,0.999,0.025,0.019,-0.002,1,0.024,0.018,-0.002,1,0.021,0.016,-0.002,1,0.018,0.013,-0.002,1,0.014,0.011,-0.001,1,0.011,0.008,-0.001,1,0.007,0.005,-0.001,1,0.004,0.003,0,1,0.002,0.001,0,1,0,0,0,1,0,0,0,1,0,0,0,1},
      ["spine_03.x"] = {0,0,0,1,-0.001,-0.003,-0.001,1,-0.003,-0.009,-0.002,1,-0.005,-0.016,-0.004,1,-0.008,-0.023,-0.006,1,-0.009,-0.026,-0.007,1,-0.01,-0.028,-0.007,1,-0.013,-0.034,-0.008,0.999,-0.017,-0.042,-0.01,0.999,-0.021,-0.049,-0.012,0.998,-0.024,-0.055,-0.013,0.998,-0.025,-0.057,-0.014,0.998,-0.025,-0.057,-0.014,0.998,-0.024,-0.057,-0.014,0.998,-0.007,-0.029,-0.007,1,0.024,0.018,0.005,1,0.04,0.043,0.013,0.998,0.036,0.038,0.012,0.999,0.028,0.028,0.008,0.999,0.023,0.022,0.006,0.999,0.022,0.021,0.006,1,0.021,0.02,0.006,1,0.019,0.018,0.005,1,0.016,0.015,0.004,1,0.013,0.012,0.003,1,0.009,0.009,0.003,1,0.006,0.006,0.002,1,0.004,0.004,0.001,1,0.002,0.002,0,1,0,0,0,1,0,0,0,1,0,0,0,1},
      ["neck.x"] = {0,0,0,1,0.001,0.002,0,1,0.004,0.006,0.001,1,0.008,0.011,0.001,1,0.011,0.015,0.002,1,0.013,0.018,0.002,1,0.014,0.019,0.002,1,0.018,0.023,0.003,1,0.024,0.028,0.004,0.999,0.03,0.033,0.005,0.999,0.034,0.036,0.006,0.999,0.035,0.038,0.006,0.999,0.035,0.038,0.006,0.999,0.035,0.038,0.006,0.999,0.009,0.019,0.002,1,-0.033,-0.011,-0.002,0.999,-0.056,-0.028,-0.003,0.998,-0.051,-0.024,-0.003,0.998,-0.039,-0.018,-0.003,0.999,-0.032,-0.014,-0.002,0.999,-0.031,-0.013,-0.002,0.999,-0.029,-0.012,-0.002,0.999,-0.026,-0.011,-0.002,1,-0.022,-0.009,-0.002,1,-0.018,-0.008,-0.001,1,-0.013,-0.006,-0.001,1,-0.009,-0.004,-0.001,1,-0.005,-0.002,0,1,-0.002,-0.001,0,1,0,0,0,1,0,0,0,1,0,0,0,1},
      ["head.x"] = {0,0,0,1,-0.001,0.002,0,1,-0.004,0.008,0,1,-0.007,0.015,0.001,1,-0.01,0.021,0.001,1,-0.012,0.024,0.001,1,-0.013,0.026,0.001,1,-0.015,0.031,0.001,0.999,-0.018,0.038,0.001,0.999,-0.021,0.045,0.001,0.999,-0.023,0.051,0.002,0.998,-0.024,0.052,0.002,0.998,-0.024,0.052,0.002,0.998,-0.023,0.052,0.002,0.998,-0.008,0.026,0.001,1,0.019,-0.017,-0.001,1,0.033,-0.041,-0.003,0.999,0.029,-0.036,-0.002,0.999,0.021,-0.026,-0.002,0.999,0.017,-0.021,-0.001,1,0.016,-0.02,-0.001,1,0.015,-0.019,-0.001,1,0.013,-0.017,-0.001,1,0.011,-0.014,-0.001,1,0.009,-0.011,-0.001,1,0.007,-0.009,0,1,0.005,-0.006,0,1,0.003,-0.003,0,1,0.001,-0.001,0,1,0,0,0,1,0,0,0,1,0,0,0,1},
      ["shoulder.l"] = {0.012,0.009,0.008,1,0.013,0.01,0.009,1,0.015,0.012,0.01,1,0.018,0.014,0.012,1,0.02,0.016,0.014,1,0.021,0.016,0.015,1,0.022,0.017,0.015,0.999,0.025,0.02,0.017,0.999,0.029,0.023,0.02,0.999,0.034,0.026,0.023,0.999,0.037,0.029,0.025,0.999,0.038,0.029,0.026,0.999,0.038,0.029,0.026,0.999,0.038,0.029,0.026,0.999,0.019,0.015,0.013,1,-0.013,-0.01,-0.009,1,-0.03,-0.024,-0.021,0.999,-0.026,-0.02,-0.018,0.999,-0.017,-0.014,-0.012,1,-0.012,-0.009,-0.008,1,-0.012,-0.009,-0.008,1,-0.01,-0.008,-0.007,1,-0.008,-0.006,-0.005,1,-0.005,-0.004,-0.003,1,-0.001,-0.001,-0.001,1,0.002,0.002,0.001,1,0.005,0.004,0.004,1,0.008,0.006,0.006,1,0.01,0.008,0.007,1,0.012,0.009,0.008,1,0.012,0.009,0.008,1,0.012,0.009,0.008,1},
      ["arm_stretch.l"] = {0.025,0.018,0.016,0.999,0.03,0.02,0.012,0.999,0.041,0.023,0.001,0.999,0.054,0.028,-0.011,0.998,0.065,0.032,-0.023,0.997,0.071,0.034,-0.028,0.996,0.075,0.036,-0.031,0.996,0.086,0.041,-0.04,0.995,0.102,0.049,-0.052,0.992,0.117,0.057,-0.063,0.989,0.128,0.063,-0.072,0.987,0.131,0.065,-0.075,0.986,0.131,0.065,-0.075,0.986,0.131,0.064,-0.075,0.986,0.07,0.032,-0.036,0.996,-0.04,-0.013,0.026,0.999,-0.102,-0.031,0.058,0.993,-0.088,-0.027,0.053,0.994,-0.06,-0.018,0.042,0.997,-0.043,-0.012,0.035,0.998,-0.041,-0.011,0.034,0.998,-0.037,-0.01,0.033,0.999,-0.03,-0.007,0.031,0.999,-0.022,-0.003,0.029,0.999,-0.013,0.001,0.027,1,-0.003,0.005,0.024,1,0.006,0.009,0.021,1,0.014,0.013,0.019,1,0.02,0.016,0.017,1,0.024,0.018,0.016,0.999,0.025,0.018,0.016,0.999,0.025,0.018,0.016,0.999},
      ["forearm_stretch.l"] = {-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999,-0.056,-0.111,-0.101,0.987,-0.081,-0.162,-0.147,0.972,-0.075,-0.149,-0.136,0.977,-0.063,-0.124,-0.113,0.984,-0.055,-0.109,-0.099,0.988,-0.054,-0.107,-0.097,0.988,-0.052,-0.103,-0.093,0.989,-0.048,-0.095,-0.087,0.99,-0.044,-0.087,-0.079,0.992,-0.039,-0.077,-0.07,0.994,-0.033,-0.067,-0.06,0.995,-0.029,-0.057,-0.052,0.997,-0.024,-0.048,-0.044,0.998,-0.021,-0.041,-0.038,0.998,-0.019,-0.037,-0.034,0.999,-0.018,-0.036,-0.033,0.999,-0.018,-0.036,-0.033,0.999},
      ["hand.l"] = {0.006,0.012,0.011,1},
      ["shoulder.r"] = {0,0,0,1,-0.016,0.007,0.007,1,-0.054,0.023,0.025,0.998,-0.101,0.043,0.046,0.993,-0.141,0.061,0.064,0.986,-0.161,0.07,0.073,0.982,-0.173,0.075,0.078,0.979,-0.208,0.09,0.094,0.97,-0.254,0.11,0.115,0.954,-0.3,0.13,0.136,0.935,-0.334,0.144,0.152,0.919,-0.344,0.149,0.156,0.914,-0.345,0.149,0.156,0.913,-0.344,0.149,0.156,0.914,-0.198,0.086,0.09,0.972,0.053,-0.023,-0.024,0.998,0.192,-0.083,-0.087,0.974,0.169,-0.073,-0.077,0.98,0.129,-0.056,-0.059,0.988,0.104,-0.045,-0.047,0.992,0.1,-0.043,-0.045,0.993,0.096,-0.042,-0.044,0.994,0.083,-0.036,-0.038,0.995,0.073,-0.031,-0.033,0.996,0.058,-0.025,-0.026,0.998,0.042,-0.018,-0.019,0.999,0.03,-0.013,-0.014,0.999,0.015,-0.007,-0.007,1,0.008,-0.004,-0.004,1,0.001,0,0,1,0,0,0,1,0.001,0,0,1},
      ["arm_stretch.r"] = {0,0,0,1,-0.004,0.005,0.003,1,-0.014,0.016,0.011,1,-0.025,0.029,0.02,0.999,-0.036,0.04,0.028,0.998,-0.041,0.046,0.032,0.998,-0.043,0.049,0.034,0.997,-0.051,0.058,0.04,0.996,-0.061,0.07,0.048,0.995,-0.071,0.081,0.056,0.993,-0.079,0.09,0.062,0.991,-0.082,0.093,0.064,0.99,-0.082,0.093,0.064,0.99,-0.082,0.093,0.064,0.99,-0.101,0.115,0.08,0.985,-0.134,0.153,0.105,0.973,-0.152,0.173,0.119,0.966,-0.138,0.157,0.108,0.972,-0.11,0.125,0.086,0.982,-0.092,0.105,0.072,0.988,-0.09,0.102,0.071,0.988,-0.084,0.096,0.066,0.99,-0.075,0.085,0.059,0.992,-0.064,0.073,0.05,0.994,-0.051,0.058,0.04,0.996,-0.038,0.044,0.03,0.998,-0.026,0.03,0.02,0.999,-0.015,0.017,0.012,1,-0.006,0.007,0.005,1,-0.001,0.001,0.001,1,0,0,0,1,0,0,0,1},
      ["forearm_stretch.r"] = {0,0,0,1,0,-0.003,-0.001,1,-0.001,-0.011,-0.004,1,-0.003,-0.02,-0.007,1,-0.004,-0.028,-0.01,1,-0.004,-0.033,-0.011,0.999,-0.005,-0.035,-0.012,0.999,-0.005,-0.041,-0.014,0.999,-0.007,-0.049,-0.017,0.999,-0.008,-0.057,-0.02,0.998,-0.008,-0.063,-0.022,0.998,-0.009,-0.065,-0.023,0.998,-0.009,-0.065,-0.023,0.998,-0.009,-0.066,-0.023,0.998,-0.011,-0.084,-0.029,0.996,-0.015,-0.114,-0.04,0.993,-0.017,-0.13,-0.045,0.99,-0.016,-0.117,-0.04,0.992,-0.012,-0.09,-0.031,0.995,-0.01,-0.074,-0.026,0.997,-0.01,-0.072,-0.025,0.997,-0.009,-0.067,-0.023,0.997,-0.008,-0.06,-0.021,0.998,-0.007,-0.051,-0.018,0.999,-0.005,-0.041,-0.014,0.999,-0.004,-0.031,-0.011,0.999,-0.003,-0.021,-0.007,1,-0.002,-0.012,-0.004,1,-0.001,-0.005,-0.002,1,0,-0.001,0,1,0,0,0,1,0,0,0,1},
      ["hand.r"] = {-0.005,-0.033,-0.007,0.999,-0.007,-0.043,-0.01,0.999,-0.013,-0.067,-0.016,0.998,-0.025,-0.094,-0.024,0.995,-0.038,-0.117,-0.033,0.992,-0.047,-0.129,-0.038,0.99,-0.053,-0.14,-0.042,0.988,-0.072,-0.174,-0.055,0.981,-0.102,-0.219,-0.073,0.968,-0.135,-0.262,-0.092,0.951,-0.161,-0.293,-0.106,0.936,-0.17,-0.302,-0.111,0.931,-0.17,-0.302,-0.111,0.931,-0.17,-0.302,-0.111,0.931,-0.118,-0.248,-0.083,0.958,-0.178,-0.242,-0.104,0.948,-0.225,-0.142,-0.105,0.958,-0.211,-0.167,-0.104,0.958,-0.179,-0.211,-0.1,0.956,-0.16,-0.237,-0.097,0.953,-0.157,-0.236,-0.096,0.954,-0.146,-0.224,-0.089,0.96,-0.13,-0.21,-0.081,0.966,-0.108,-0.184,-0.069,0.975,-0.084,-0.155,-0.056,0.983,-0.061,-0.123,-0.042,0.99,-0.04,-0.09,-0.029,0.995,-0.024,-0.067,-0.02,0.997,-0.012,-0.045,-0.012,0.999,-0.007,-0.036,-0.008,0.999,-0.005,-0.033,-0.007,0.999,-0.005,-0.032,-0.007,0.999},
      ["thigh_stretch.l"] = {0,0,0,-1,-0.017,0.004,-0.024,-1,-0.033,0.014,-0.046,-0.998,-0.044,0.027,-0.061,-0.997,-0.052,0.038,-0.071,-0.995,-0.056,0.043,-0.075,-0.995,-0.057,0.047,-0.076,-0.994,-0.061,0.056,-0.078,-0.993,-0.067,0.069,-0.081,-0.992,-0.072,0.081,-0.083,-0.991,-0.076,0.091,-0.085,-0.989,-0.077,0.094,-0.086,-0.989,-0.077,0.094,-0.086,-0.989,-0.077,0.093,-0.086,-0.989,-0.063,0.048,-0.098,-0.992,-0.032,-0.03,-0.103,-0.994,-0.013,-0.073,-0.103,-0.992,-0.011,-0.064,-0.101,-0.993,-0.008,-0.047,-0.096,-0.994,-0.006,-0.036,-0.093,-0.995,-0.006,-0.036,-0.092,-0.995,-0.005,-0.033,-0.09,-0.995,-0.003,-0.03,-0.087,-0.996,-0.001,-0.025,-0.083,-0.996,0.002,-0.02,-0.078,-0.997,0.005,-0.015,-0.072,-0.997,0.008,-0.01,-0.066,-0.998,0.012,-0.006,-0.059,-0.998,0.016,-0.002,-0.052,-0.999,0.019,0,-0.047,-0.999,0.02,0,-0.046,-0.999,0.02,0,-0.046,-0.999},
      ["leg_stretch.l"] = {0,0,0,1,-0.027,0,-0.052,0.998,-0.051,0,-0.098,0.994,-0.066,0,-0.128,0.99,-0.076,0,-0.147,0.986,-0.081,0,-0.156,0.985,-0.081,0,-0.156,0.984,-0.081,0,-0.157,0.984,-0.082,-0.001,-0.158,0.984,-0.082,-0.001,-0.158,0.984,-0.082,-0.001,-0.158,0.984,-0.082,-0.001,-0.158,0.984,-0.082,-0.001,-0.158,0.984,-0.082,-0.001,-0.159,0.984,-0.108,0.001,-0.208,0.972,-0.132,0.006,-0.254,0.958,-0.14,0.009,-0.27,0.953,-0.136,0.01,-0.262,0.955,-0.128,0.011,-0.248,0.96,-0.122,0.012,-0.236,0.964,-0.121,0.012,-0.235,0.964,-0.119,0.012,-0.23,0.966,-0.115,0.012,-0.222,0.968,-0.109,0.013,-0.211,0.971,-0.103,0.013,-0.198,0.975,-0.095,0.013,-0.184,0.978,-0.087,0.012,-0.168,0.982,-0.078,0.012,-0.151,0.985,-0.069,0.012,-0.134,0.988,-0.063,0.011,-0.122,0.99,-0.061,0.011,-0.119,0.991,-0.061,0.011,-0.119,0.991},
      ["foot.l"] = {0,0,0,1,0.005,-0.016,0.025,1,0.01,-0.03,0.048,0.998,0.013,-0.04,0.063,0.997,0.016,-0.046,0.073,0.996,0.017,-0.049,0.078,0.996,0.016,-0.049,0.078,0.996,0.016,-0.049,0.078,0.996,0.015,-0.05,0.077,0.996,0.014,-0.051,0.077,0.996,0.014,-0.051,0.076,0.996,0.014,-0.051,0.076,0.996,0.014,-0.051,0.076,0.996,0.014,-0.051,0.076,0.996,0.025,-0.065,0.108,0.992,0.04,-0.078,0.144,0.986,0.047,-0.083,0.16,0.982,0.048,-0.079,0.158,0.983,0.05,-0.073,0.154,0.984,0.051,-0.069,0.151,0.985,0.051,-0.068,0.15,0.985,0.051,-0.066,0.148,0.985,0.051,-0.063,0.145,0.986,0.051,-0.06,0.141,0.987,0.051,-0.055,0.135,0.988,0.051,-0.05,0.129,0.989,0.05,-0.044,0.122,0.99,0.049,-0.039,0.115,0.991,0.048,-0.033,0.107,0.992,0.048,-0.029,0.102,0.993,0.047,-0.028,0.1,0.993,0.047,-0.028,0.1,0.993},
      ["toes_01.l"] = {0,0,0,1},
      ["thigh_stretch.r"] = {0,0,0,-1,-0.006,0.004,0.005,-1,-0.048,0.015,0.038,-0.998,-0.062,0.028,0.047,-0.997,-0.069,0.039,0.052,-0.995,-0.072,0.045,0.054,-0.995,-0.073,0.048,0.054,-0.995,-0.074,0.058,0.053,-0.994,-0.076,0.071,0.052,-0.993,-0.078,0.084,0.05,-0.992,-0.079,0.094,0.049,-0.991,-0.08,0.097,0.049,-0.991,-0.08,0.097,0.049,-0.991,-0.08,0.097,0.049,-0.991,-0.101,0.048,0.065,-0.992,-0.121,-0.034,0.082,-0.989,-0.121,-0.079,0.081,-0.986,-0.117,-0.069,0.078,-0.988,-0.106,-0.051,0.068,-0.991,-0.098,-0.04,0.062,-0.992,-0.097,-0.039,0.061,-0.993,-0.092,-0.037,0.056,-0.993,-0.087,-0.033,0.052,-0.994,-0.08,-0.028,0.047,-0.995,-0.072,-0.023,0.04,-0.996,-0.062,-0.017,0.032,-0.997,-0.051,-0.011,0.022,-0.998,-0.037,-0.007,0.011,-0.999,-0.029,-0.003,0.005,-1,-0.028,-0.001,0.005,-1,-0.028,0,0.004,-1,-0.028,0,0.004,-1},
      ["leg_stretch.r"] = {0,0,0,1,-0.015,0,0.013,1,-0.101,0,0.09,0.991,-0.133,0,0.119,0.984,-0.153,0,0.137,0.979,-0.161,0,0.144,0.976,-0.162,0,0.145,0.976,-0.166,-0.001,0.148,0.975,-0.17,-0.001,0.153,0.973,-0.175,-0.001,0.156,0.972,-0.178,-0.001,0.159,0.971,-0.179,-0.001,0.16,0.971,-0.179,-0.001,0.16,0.971,-0.179,-0.001,0.16,0.971,-0.185,0.003,0.166,0.969,-0.169,0.009,0.152,0.974,-0.138,0.011,0.126,0.982,-0.135,0.01,0.123,0.983,-0.123,0.008,0.112,0.986,-0.114,0.007,0.103,0.988,-0.112,0.007,0.101,0.989,-0.103,0.006,0.093,0.99,-0.095,0.005,0.086,0.992,-0.084,0.005,0.076,0.994,-0.07,0.004,0.063,0.996,-0.053,0.003,0.047,0.997,-0.032,0.002,0.029,0.999,-0.006,0.002,0.006,1,0.008,0.001,-0.007,1,0.008,0.001,-0.007,1,0.008,0.001,-0.007,1,0.008,0.001,-0.007,1},
      ["foot.r"] = {0,0,0,1,-0.005,-0.001,-0.01,1,-0.034,-0.007,-0.065,0.997,-0.046,-0.01,-0.088,0.995,-0.053,-0.012,-0.103,0.993,-0.056,-0.013,-0.109,0.992,-0.057,-0.013,-0.111,0.992,-0.059,-0.014,-0.114,0.992,-0.061,-0.015,-0.119,0.991,-0.063,-0.016,-0.124,0.99,-0.065,-0.017,-0.127,0.99,-0.065,-0.017,-0.128,0.989,-0.065,-0.017,-0.128,0.989,-0.065,-0.017,-0.128,0.989,-0.061,-0.005,-0.108,0.992,-0.045,0.018,-0.06,0.997,-0.031,0.031,-0.021,0.999,-0.03,0.029,-0.023,0.999,-0.028,0.024,-0.024,0.999,-0.026,0.021,-0.023,0.999,-0.025,0.021,-0.022,0.999,-0.023,0.021,-0.018,0.999,-0.02,0.02,-0.015,0.999,-0.017,0.019,-0.01,1,-0.013,0.018,-0.004,1,-0.008,0.018,0.004,1,-0.002,0.017,0.014,1,0.006,0.017,0.027,0.999,0.01,0.017,0.034,0.999,0.01,0.016,0.033,0.999,0.01,0.016,0.033,0.999,0.01,0.016,0.033,0.999},
      ["toes_01.r"] = {0,0,0,1},
    },
    rootOffset = {0,0,0,0,-0.001,-0.001,0,-0.003,-0.004,0,-0.005,-0.007,0,-0.007,-0.01,0,-0.008,-0.012,0,-0.008,-0.012,0,-0.008,-0.013,0,-0.009,-0.015,0,-0.01,-0.017,0,-0.01,-0.018,0,-0.01,-0.018,0,-0.01,-0.018,0,-0.01,-0.018,0,-0.015,0.001,0,-0.023,0.033,0,-0.028,0.05,0,-0.026,0.044,0,-0.021,0.033,0,-0.018,0.026,0,-0.018,0.025,0,-0.016,0.024,0,-0.015,0.021,0,-0.013,0.018,0,-0.01,0.015,0,-0.008,0.011,0,-0.005,0.007,0,-0.003,0.004,0,-0.001,0.002,0,0,0,0,0,0,0,0,0},
  },
  Hit = {
    duration = 0.6, loop = false, count = 13,
    bones = {
      ["root.x"] = {0,0,0,1,-0.048,-0.001,0.02,0.999,-0.056,-0.001,0.024,0.998,-0.051,-0.001,0.021,0.998,-0.042,-0.001,0.017,0.999,-0.028,-0.001,0.012,1,-0.021,-0.001,0.009,1,-0.019,-0.001,0.008,1,-0.014,-0.001,0.006,1,-0.007,0,0.003,1,-0.002,0,0.001,1,0,0,0,1,0,0,0,1},
      ["spine_01.x"] = {0,0,0,1,-0.053,0.022,-0.028,0.998,-0.062,0.026,-0.034,0.997,-0.055,0.023,-0.03,0.998,-0.045,0.019,-0.024,0.998,-0.03,0.013,-0.016,0.999,-0.023,0.01,-0.012,1,-0.02,0.009,-0.011,1,-0.015,0.007,-0.008,1,-0.008,0.004,-0.004,1,-0.002,0.001,-0.001,1,0,0,0,1,0,0,0,1},
      ["spine_02.x"] = {0,0,0,1,-0.044,0.024,-0.016,0.999,-0.052,0.028,-0.019,0.998,-0.046,0.026,-0.017,0.998,-0.038,0.021,-0.014,0.999,-0.025,0.014,-0.009,1,-0.019,0.011,-0.007,1,-0.017,0.01,-0.006,1,-0.012,0.007,-0.004,1,-0.007,0.004,-0.002,1,-0.002,0.001,-0.001,1,0,0,0,1,0,0,0,1},
      ["spine_03.x"] = {0,0,0,1,-0.035,0.031,-0.008,0.999,-0.041,0.036,-0.01,0.998,-0.037,0.033,-0.009,0.999,-0.03,0.027,-0.007,0.999,-0.02,0.018,-0.005,1,-0.015,0.014,-0.003,1,-0.013,0.012,-0.003,1,-0.01,0.009,-0.002,1,-0.005,0.005,-0.001,1,-0.002,0.001,0,1,0,0,0,1,0,0,0,1},
      ["neck.x"] = {0,0,0,1,-0.05,-0.025,-0.003,0.998,-0.059,-0.03,-0.004,0.998,-0.053,-0.027,-0.003,0.998,-0.043,-0.022,-0.003,0.999,-0.029,-0.015,-0.002,0.999,-0.022,-0.011,-0.002,1,-0.02,-0.01,-0.002,1,-0.014,-0.007,-0.001,1,-0.008,-0.004,-0.001,1,-0.002,-0.001,0,1,0,0,0,1,0,0,0,1},
      ["head.x"] = {0,0,0,1,-0.089,-0.051,0.024,0.994,-0.105,-0.06,0.029,0.992,-0.094,-0.054,0.026,0.994,-0.077,-0.045,0.02,0.996,-0.052,-0.03,0.013,0.998,-0.039,-0.023,0.009,0.999,-0.035,-0.021,0.008,0.999,-0.025,-0.015,0.006,1,-0.014,-0.008,0.003,1,-0.004,-0.002,0.001,1,0,0,0,1,0,0,0,1},
      ["shoulder.l"] = {0,0,0,1,-0.039,-0.03,-0.027,0.998,-0.045,-0.035,-0.031,0.998,-0.041,-0.032,-0.028,0.998,-0.033,-0.026,-0.023,0.999,-0.023,-0.018,-0.016,0.999,-0.017,-0.013,-0.012,1,-0.015,-0.012,-0.01,1,-0.011,-0.009,-0.008,1,-0.006,-0.005,-0.004,1,-0.002,-0.001,-0.001,1,0,0,0,1,0,0,0,1},
      ["arm_stretch.l"] = {0,0,0,1,0.016,0.025,0.068,0.997,0.019,0.029,0.08,0.996,0.017,0.026,0.072,0.997,0.013,0.022,0.059,0.998,0.009,0.015,0.039,0.999,0.007,0.012,0.03,0.999,0.006,0.01,0.027,1,0.004,0.008,0.019,1,0.002,0.004,0.01,1,0.001,0.001,0.003,1,0,0,0,1,0,0,0,1},
      ["forearm_stretch.l"] = {0,0,0,1,-0.034,-0.068,-0.062,0.995,-0.04,-0.08,-0.072,0.993,-0.036,-0.071,-0.065,0.995,-0.029,-0.059,-0.053,0.996,-0.02,-0.039,-0.036,0.998,-0.015,-0.03,-0.027,0.999,-0.013,-0.027,-0.024,0.999,-0.01,-0.019,-0.017,1,-0.005,-0.01,-0.009,1,-0.002,-0.003,-0.003,1,0,0,0,1,0,0,0,1},
      ["hand.l"] = {0,0,0,1,0.015,0.029,0.026,0.999,0.017,0.034,0.031,0.999,0.015,0.031,0.028,0.999,0.013,0.025,0.023,0.999,0.009,0.017,0.015,1,0.006,0.013,0.012,1,0.006,0.011,0.01,1,0.004,0.008,0.007,1,0.002,0.004,0.004,1,0.001,0.001,0.001,1,0,0,0,1,0,0,0,1},
      ["shoulder.r"] = {0,0,0,1,0.063,-0.028,0.002,0.998,0.074,-0.033,0.002,0.997,0.066,-0.03,0.002,0.997,0.054,-0.024,0.001,0.998,0.037,-0.016,0.001,0.999,0.028,-0.012,0.001,1,0.025,-0.011,0.001,1,0.018,-0.008,0,1,0.01,-0.004,0,1,0.003,-0.001,0,1,0,0,0,1,0,0,0,1},
      ["arm_stretch.r"] = {0,0,0,1,-0.025,0.028,0.019,0.999,-0.029,0.033,0.023,0.999,-0.026,0.029,0.02,0.999,-0.021,0.024,0.017,0.999,-0.014,0.016,0.011,1,-0.011,0.012,0.008,1,-0.01,0.011,0.008,1,-0.007,0.008,0.005,1,-0.004,0.004,0.003,1,-0.001,0.001,0.001,1,0,0,0,1,0,0,0,1},
      ["forearm_stretch.r"] = {0,0,0,1,-0.003,-0.026,-0.009,1,-0.004,-0.031,-0.011,0.999,-0.004,-0.028,-0.01,1,-0.003,-0.023,-0.008,1,-0.002,-0.015,-0.005,1,-0.002,-0.011,-0.004,1,-0.001,-0.01,-0.004,1,-0.001,-0.007,-0.003,1,-0.001,-0.004,-0.001,1,0,-0.001,0,1,0,0,0,1,0,0,0,1},
      ["hand.r"] = {-0.005,-0.033,-0.007,0.999,-0.085,-0.064,-0.041,0.993,-0.1,-0.069,-0.048,0.991,-0.089,-0.066,-0.043,0.993,-0.073,-0.06,-0.036,0.995,-0.049,-0.052,-0.026,0.997,-0.038,-0.047,-0.022,0.998,-0.034,-0.046,-0.02,0.998,-0.026,-0.042,-0.016,0.999,-0.016,-0.038,-0.012,0.999,-0.008,-0.034,-0.009,0.999,-0.005,-0.033,-0.007,0.999,-0.005,-0.033,-0.007,0.999},
      ["thigh_stretch.l"] = {0,0,0,-1,-0.075,-0.006,-0.076,-0.994,-0.084,-0.007,-0.083,-0.993,-0.078,-0.007,-0.078,-0.994,-0.067,-0.005,-0.07,-0.995,-0.051,-0.004,-0.055,-0.997,-0.042,-0.003,-0.047,-0.998,-0.039,-0.003,-0.044,-0.998,-0.031,-0.002,-0.036,-0.999,-0.019,-0.001,-0.024,-1,-0.003,0,-0.002,-1,0,0,0,-1,0,0,0,-1},
      ["leg_stretch.l"] = {0,0,0,1,-0.06,0.001,-0.115,0.992,-0.063,0.002,-0.122,0.99,-0.061,0.001,-0.117,0.991,-0.056,0.001,-0.108,0.993,-0.047,0.001,-0.091,0.995,-0.041,0,-0.08,0.996,-0.039,0,-0.076,0.996,-0.033,0,-0.064,0.997,-0.023,0,-0.044,0.999,-0.002,0,-0.003,1,0,0,0,1,0,0,0,1},
      ["foot.l"] = {0,0,0,1,0.016,-0.033,0.06,0.998,0.018,-0.035,0.064,0.997,0.016,-0.034,0.061,0.997,0.015,-0.031,0.056,0.998,0.012,-0.027,0.047,0.998,0.01,-0.023,0.04,0.999,0.009,-0.022,0.038,0.999,0.008,-0.019,0.032,0.999,0.005,-0.013,0.022,1,0,-0.001,0.002,1,0,0,0,1,0,0,0,1},
      ["toes_01.l"] = {0,0,0,1},
      ["thigh_stretch.r"] = {0,0,0,-1,-0.107,0.006,0.049,-0.993,-0.115,0.007,0.049,-0.992,-0.11,0.006,0.049,-0.993,-0.101,0.005,0.049,-0.994,-0.085,0.004,0.046,-0.995,-0.075,0.003,0.043,-0.996,-0.071,0.003,0.042,-0.997,-0.061,0.002,0.038,-0.997,-0.041,0.001,0.027,-0.999,-0.005,0,0.003,-1,0,0,0,-1,0,0,0,-1},
      ["leg_stretch.r"] = {0,0,0,1,-0.172,-0.003,0.154,0.973,-0.18,-0.003,0.161,0.97,-0.174,-0.003,0.156,0.972,-0.164,-0.002,0.147,0.975,-0.144,-0.001,0.128,0.981,-0.129,-0.001,0.115,0.985,-0.123,-0.001,0.11,0.986,-0.107,0,0.096,0.99,-0.074,0,0.067,0.995,-0.008,0,0.007,1,0,0,0,1,0,0,0,1},
      ["foot.r"] = {0,0,0,1,-0.067,-0.022,-0.136,0.988,-0.071,-0.024,-0.146,0.986,-0.068,-0.023,-0.139,0.988,-0.063,-0.02,-0.127,0.99,-0.053,-0.015,-0.105,0.993,-0.046,-0.012,-0.092,0.995,-0.044,-0.012,-0.087,0.995,-0.038,-0.009,-0.073,0.997,-0.025,-0.006,-0.05,0.998,-0.003,-0.001,-0.006,1,0,0,0,1,0,0,0,1},
      ["toes_01.r"] = {0,0,0,1},
    },
    rootOffset = {0,0,0,0,-0.006,-0.032,0,-0.008,-0.038,0,-0.007,-0.034,0,-0.006,-0.028,0,-0.004,-0.019,0,-0.003,-0.014,0,-0.003,-0.013,0,-0.002,-0.009,0,-0.001,-0.005,0,0,-0.001,0,0,0,0,0,0},
  },
}
local BONE_COUNT = #BONE_ORDER
local rig = {
  transforms = {},
  rest = {},
  restPos = {},
  found = 0,
  ready = false,
  attempted = false,
}
local state = {
  action = "Idle",
  time = 0,
  speed = 1,
  fading = false,
  fadeElapsed = 0,
  fadeDuration = 0,
  fromPose = {},
  fromRoot = { 0, 0, 0 },
  pose = {},
  rootOffset = { 0, 0, 0 },
  applied = {},
  appliedRoot = { 0, 0, 0 },
}

local rootTransform = nil

-- glTF 节点到 Unity 的旋转转换：(x, y, z, w) -> (x, -y, -z, w)
local function toUnityDelta(x, y, z, w)
  return x, -y, -z, w
end

local function qmul(ax, ay, az, aw, bx, by, bz, bw)
  return aw * bx + ax * bw + ay * bz - az * by,
         aw * by - ax * bz + ay * bw + az * bx,
         aw * bz + ax * by - ay * bx + az * bw,
         aw * bw - ax * bx - ay * by - az * bz
end

local function slerp(ax, ay, az, aw, bx, by, bz, bw, t)
  local dot = ax * bx + ay * by + az * bz + aw * bw
  if dot < 0 then
    bx, by, bz, bw = -bx, -by, -bz, -bw
    dot = -dot
  end
  if dot > 0.9995 then
    local x = ax + (bx - ax) * t
    local y = ay + (by - ay) * t
    local z = az + (bz - az) * t
    local w = aw + (bw - aw) * t
    local n = math.sqrt(x * x + y * y + z * z + w * w)
    if n < 1e-6 then
      return ax, ay, az, aw
    end
    return x / n, y / n, z / n, w / n
  end
  local theta = math.acos(dot)
  local sinTheta = math.sin(theta)
  local w1 = math.sin((1 - t) * theta) / sinTheta
  local w2 = math.sin(t * theta) / sinTheta
  return ax * w1 + bx * w2, ay * w1 + by * w2, az * w1 + bz * w2, aw * w1 + bw * w2
end

local function clamp01(v)
  if v < 0 then
    return 0
  end
  if v > 1 then
    return 1
  end
  return v
end

-- 在节点树中按名字查找骨骼，避免依赖 armature 节点名或层级路径
local function findByName(node, name, depth)
  if node == nil or depth > 12 then
    return nil
  end
  if node.name == name then
    return node
  end
  local count = node.childCount
  local i = 0
  while i < count do
    local child = node:GetChild(i)
    local found = findByName(child, name, depth + 1)
    if found ~= nil then
      return found
    end
    i = i + 1
  end
  return nil
end

local function resolveRootTransform()
  if runtimeScope ~= nil then
    local rootGo = runtimeScope:GetResourceRoot()
    if rootGo ~= nil then
      return rootGo.transform
    end
  end
  if self ~= nil and self.transform ~= nil then
    return self.transform
  end
  return nil
end

local function ensureRig()
  if rig.ready then
    return true
  end
  if rig.attempted then
    return false
  end
  rig.attempted = true
  local searchRoot = resolveRootTransform()
  if searchRoot == nil then
    logger:error("骨骼初始化失败：找不到资源根节点", tostring(scopeReason))
    return false
  end
  local missing = {}
  for i = 1, BONE_COUNT do
    local name = BONE_ORDER[i]
    local tr = findByName(searchRoot, name, 0)
    if tr == nil then
      missing[#missing + 1] = name
    else
      rig.transforms[i] = tr
      local q = tr.localRotation
      rig.rest[i] = { q.x, q.y, q.z, q.w }
      local p = tr.localPosition
      rig.restPos[i] = { p.x, p.y, p.z }
      rig.found = rig.found + 1
    end
  end
  rootTransform = rig.transforms[1]
  rig.ready = rig.found > 0
  if #missing > 0 then
    logger:error("骨骼缺失 " .. tostring(#missing) .. " 根：", table.concat(missing, ","))
  end
  logger:info("骨骼就绪 " .. tostring(rig.found) .. "/" .. tostring(BONE_COUNT))
  return rig.ready
end

local tmpQ = { 0, 0, 0, 1 }

local function boneSample(clip, name, i0, i1, a, out)
  local data = clip.bones[name]
  if data == nil then
    return nil
  end
  if #data == 4 then
    out[1], out[2], out[3], out[4] = data[1], data[2], data[3], data[4]
    return true
  end
  local b0 = i0 * 4
  local b1 = i1 * 4
  out[1], out[2], out[3], out[4] = slerp(
    data[b0 + 1], data[b0 + 2], data[b0 + 3], data[b0 + 4],
    data[b1 + 1], data[b1 + 2], data[b1 + 3], data[b1 + 4], a)
  return true
end

local function sampleClip(clip, t, pose, rootOffset)
  local n = clip.count
  local dur = clip.duration
  local i0, i1, a
  if clip.loop then
    local f = (t / dur) * n
    local base = math.floor(f)
    i0 = base % n
    i1 = (i0 + 1) % n
    a = f - base
  else
    local f = clamp01(t / dur) * (n - 1)
    i0 = math.floor(f)
    if i0 > n - 1 then
      i0 = n - 1
    end
    i1 = i0 + 1
    if i1 > n - 1 then
      i1 = n - 1
    end
    a = f - i0
  end
  for i = 1, BONE_COUNT do
    local name = BONE_ORDER[i]
    local base = (i - 1) * 4
    local ok = boneSample(clip, name, i0, i1, a, tmpQ)
    if ok then
      pose[base + 1], pose[base + 2], pose[base + 3], pose[base + 4] =
        tmpQ[1], tmpQ[2], tmpQ[3], tmpQ[4]
    else
      pose[base + 1], pose[base + 2], pose[base + 3], pose[base + 4] = 0, 0, 0, 1
    end
  end
  local off = clip.rootOffset
  local o = i0 * 3
  if off ~= nil and #off >= o + 3 then
    rootOffset[1] = off[o + 1]
    rootOffset[2] = off[o + 2]
    rootOffset[3] = off[o + 3]
  else
    rootOffset[1], rootOffset[2], rootOffset[3] = 0, 0, 0
  end
end

local function applyPose(pose, rootOffset)
  local total = BONE_COUNT * 4
  local applied = state.applied
  for i = 1, total do
    applied[i] = pose[i]
  end
  state.appliedRoot[1] = rootOffset[1]
  state.appliedRoot[2] = rootOffset[2]
  state.appliedRoot[3] = rootOffset[3]
  for i = 1, BONE_COUNT do
    local tr = rig.transforms[i]
    local rest = rig.rest[i]
    if tr ~= nil and rest ~= nil then
      local b = (i - 1) * 4
      local dx, dy, dz, dw = toUnityDelta(pose[b + 1], pose[b + 2], pose[b + 3], pose[b + 4])
      local x, y, z, w = qmul(rest[1], rest[2], rest[3], rest[4], dx, dy, dz, dw)
      local n = math.sqrt(x * x + y * y + z * z + w * w)
      if n > 1e-6 then
        tr.localRotation = Quaternion(x / n, y / n, z / n, w / n)
      end
    end
  end
  local base = rig.restPos[1]
  if rootTransform ~= nil and base ~= nil then
    rootTransform.localPosition = Vector3(
      base[1] - rootOffset[1],
      base[2] + rootOffset[2],
      base[3] + rootOffset[3])
  end
end

local function restoreRest()
  if not rig.ready then
    return
  end
  for i = 1, BONE_COUNT do
    local tr = rig.transforms[i]
    local r = rig.rest[i]
    if tr ~= nil and r ~= nil then
      tr.localRotation = Quaternion(r[1], r[2], r[3], r[4])
    end
  end
  local base = rig.restPos[1]
  if rootTransform ~= nil and base ~= nil then
    rootTransform.localPosition = Vector3(base[1], base[2], base[3])
  end
end

local function capturePose()
  state.fromPose = {}
  for i = 1, BONE_COUNT * 4 do
    state.fromPose[i] = state.applied[i]
  end
  state.fromRoot[1] = state.appliedRoot[1]
  state.fromRoot[2] = state.appliedRoot[2]
  state.fromRoot[3] = state.appliedRoot[3]
end

local function blendPose(target, targetRoot, alpha)
  local from = state.fromPose
  local out = {}
  for i = 1, BONE_COUNT do
    local b = (i - 1) * 4
    local a1, a2, a3, a4 = from[b + 1], from[b + 2], from[b + 3], from[b + 4]
    if a1 == nil then
      a1, a2, a3, a4 = 0, 0, 0, 1
    end
    local b1, b2, b3, b4 = target[b + 1], target[b + 2], target[b + 3], target[b + 4]
    local x, y, z, w = slerp(a1, a2, a3, a4, b1, b2, b3, b4, alpha)
    out[b + 1], out[b + 2], out[b + 3], out[b + 4] = x, y, z, w
  end
  local root = {
    state.fromRoot[1] + (targetRoot[1] - state.fromRoot[1]) * alpha,
    state.fromRoot[2] + (targetRoot[2] - state.fromRoot[2]) * alpha,
    state.fromRoot[3] + (targetRoot[3] - state.fromRoot[3]) * alpha,
  }
  return out, root
end

-- 对外接口 --------------------------------------------------------------

function Play(name, opts)
  if CLIP_DATA[name] == nil then
    logger:warn("未知动作", tostring(name))
    return false
  end
  if not ensureRig() then
    return false
  end
  if state.applied[1] ~= nil then
    capturePose()
    local fade = FadeTime
    if opts ~= nil and type(opts.fade) == "number" then
      fade = opts.fade
    end
    if state.action == name then
      fade = math.min(fade, 0.08)
    end
    state.fading = fade > 0.001
    state.fadeElapsed = 0
    state.fadeDuration = fade
  else
    state.fading = false
  end
  state.action = name
  state.time = 0
  if opts ~= nil and type(opts.speed) == "number" and opts.speed > 0 then
    state.speed = opts.speed
  end
  return true
end

function SetSpeed(value)
  if type(value) == "number" and value > 0 then
    state.speed = value
    return true
  end
  return false
end

function GetAction()
  return state.action
end

function GetActionDuration(name)
  local clip = CLIP_DATA[name or state.action]
  if clip == nil then
    return 0
  end
  return clip.duration
end

function GetHitTime(name)
  local clip = CLIP_DATA[name or "Attack"]
  if clip == nil or clip.hitTime == nil then
    return 0
  end
  return clip.hitTime
end

function GetRigStatus()
  return {
    ready = rig.ready,
    found = rig.found,
    total = BONE_COUNT,
    action = state.action,
    speed = state.speed,
  }
end

function IsReady()
  return rig.ready
end

function OnEnable()
  ensureRig()
  if rig.ready then
    local first = DefaultAction or "Idle"
    if CLIP_DATA[first] == nil then
      first = "Idle"
    end
    Play(first, { fade = 0 })
  end
end

function Start()
  ensureRig()
  if rig.ready then
    state.action = DefaultAction or "Idle"
    if CLIP_DATA[state.action] == nil then
      logger:warn("默认动作无效，回退到 Idle", tostring(state.action))
      state.action = "Idle"
    end
    state.time = 0
    state.pose = {}
    sampleClip(CLIP_DATA[state.action], 0, state.pose, state.rootOffset)
    applyPose(state.pose, state.rootOffset)
    logger:info("初始化完成，动作 " .. tostring(state.action))
  end
end

function Update()
  if not rig.ready then
    ensureRig()
    if not rig.ready then
      return
    end
  end
  local clip = CLIP_DATA[state.action]
  if clip == nil then
    return
  end
  local dt = clock.deltaTime * state.speed
  state.time = state.time + dt
  if clip.loop then
    if state.time >= clip.duration then
      state.time = state.time % clip.duration
    end
  elseif state.time >= clip.duration then
    state.time = clip.duration
    sampleClip(clip, state.time, state.pose, state.rootOffset)
    applyPose(state.pose, state.rootOffset)
    Play("Idle", { fade = 0.22 })
    return
  end
  sampleClip(clip, state.time, state.pose, state.rootOffset)
  if state.fading then
    state.fadeElapsed = state.fadeElapsed + clock.deltaTime
    local alpha = clamp01(state.fadeElapsed / math.max(state.fadeDuration, 0.0001))
    local blended, root = blendPose(state.pose, state.rootOffset, alpha)
    applyPose(blended, root)
    if alpha >= 1 then
      state.fading = false
    end
  else
    applyPose(state.pose, state.rootOffset)
  end
end

function OnDisable()
  restoreRest()
end

function OnDestroy()
  restoreRest()
end


Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="Idle",walk="Walk",attack="Attack",hit="Hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.guard=function(root,height)
local Play,SetSpeed,GetAction,GetActionDuration,GetHitTime,GetRigStatus,IsReady,IsPlaying,Start,Update,OnDisable,OnDestroy
local DefaultAction="Idle"
local PlaybackSpeed=1
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 裂隙铁卫统领的逐骨骼动画：Idle / Walk / Attack / Hit

local UnityEngine = CS.UnityEngine
local Vector3 = CS.UnityEngine.Vector3
local Quaternion = CS.UnityEngine.Quaternion
local Time = clock
local RuntimeScope={from=function()return boundScope end}
local Logger = require("official.core.logger")

local logger = Logger.create("guard-anim")
local runtimeScope, scopeReason = RuntimeScope.from(self)

-- 22 根骨骼的层级，节点路径由父链拼出，避免写死整串路径
local BONE_TREE = {
  { "root.x", "" },
  { "spine_01.x", "root.x" },
  { "spine_02.x", "spine_01.x" },
  { "spine_03.x", "spine_02.x" },
  { "neck.x", "spine_03.x" },
  { "head.x", "neck.x" },
  { "shoulder.l", "spine_03.x" },
  { "arm_stretch.l", "shoulder.l" },
  { "forearm_stretch.l", "arm_stretch.l" },
  { "hand.l", "forearm_stretch.l" },
  { "forearm_twist.l", "forearm_stretch.l" },
  { "arm_twist.l", "arm_stretch.l" },
  { "shoulder.r", "spine_03.x" },
  { "arm_stretch.r", "shoulder.r" },
  { "forearm_stretch.r", "arm_stretch.r" },
  { "hand.r", "forearm_stretch.r" },
  { "forearm_twist.r", "forearm_stretch.r" },
  { "arm_twist.r", "arm_stretch.r" },
  { "thigh_stretch.l", "root.x" },
  { "leg_stretch.l", "thigh_stretch.l" },
  { "foot.l", "leg_stretch.l" },
  { "toes_01.l", "foot.l" },
  { "leg_twist.l", "leg_stretch.l" },
  { "thigh_twist.l", "thigh_stretch.l" },
  { "thigh_stretch.r", "root.x" },
  { "leg_stretch.r", "thigh_stretch.r" },
  { "foot.r", "leg_stretch.r" },
  { "toes_01.r", "foot.r" },
  { "leg_twist.r", "leg_stretch.r" },
  { "thigh_twist.r", "thigh_stretch.r" },
}
local MODEL_PREFIX = "Armature/"

local BONE_PATH = {}
local BONE_NAMES = {}
for i = 1, #BONE_TREE do
  local entry = BONE_TREE[i]
  local name = entry[1]
  local parent = entry[2]
  BONE_NAMES[i] = name
  if parent == "" then
    BONE_PATH[name] = MODEL_PREFIX .. name
  else
    BONE_PATH[name] = BONE_PATH[parent] .. "/" .. name
  end
end

local MOVES = {
  Idle = {
    duration = 3, loop = true, hit = 0,
    t = {0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3},
    bones = {
      ["root.x"] = {0,-0.0037,-0.0024,1, 0.0013,-0.0077,-0.0049,1, 0.0022,-0.0095,-0.006,0.9999, 0.0026,-0.0089,-0.0056,0.9999, 0.0022,-0.0058,-0.0037,1, 0.0013,-0.0012,-0.0008,1, 0,0.0037,0.0024,1, -0.0013,0.0077,0.0049,1, -0.0023,0.0095,0.0061,0.9999, -0.0027,0.0088,0.0056,0.9999, -0.0023,0.0058,0.0037,1, -0.0013,0.0012,0.0008,1, 0,-0.0037,-0.0024,1},
      ["spine_01.x"] = {0,-0.0017,-0.0012,1, 0.0022,-0.0035,-0.0024,1, 0.0038,-0.0043,-0.003,1, 0.0044,-0.004,-0.0028,1, 0.0038,-0.0026,-0.0018,1, 0.0022,-0.0005,-0.0004,1, 0,0.0017,0.0012,1, -0.0022,0.0035,0.0024,1, -0.0038,0.0043,0.003,1, -0.0044,0.004,0.0028,1, -0.0038,0.0026,0.0019,1, -0.0022,0.0005,0.0004,1, 0,-0.0017,-0.0012,1},
      ["spine_02.x"] = {0,-0.0014,-0.001,1, 0.0039,-0.0028,-0.0021,1, 0.0068,-0.0035,-0.0026,1, 0.0078,-0.0032,-0.0024,1, 0.0068,-0.0021,-0.0016,1, 0.0039,-0.0004,-0.0003,1, 0,0.0014,0.001,1, -0.0039,0.0028,0.0021,1, -0.0068,0.0034,0.0026,1, -0.0079,0.0032,0.0024,1, -0.0068,0.0021,0.0016,1, -0.0039,0.0004,0.0003,1, 0,-0.0014,-0.001,1},
      ["spine_03.x"] = {0,0.0024,-0.0007,1, 0.0031,0.0049,-0.0014,1, 0.0053,0.0061,-0.0018,1, 0.0061,0.0056,-0.0016,1, 0.0053,0.0037,-0.0011,1, 0.0031,0.0008,-0.0002,1, 0,-0.0024,0.0007,1, -0.003,-0.0049,0.0014,1, -0.0053,-0.0061,0.0017,1, -0.0061,-0.0056,0.0016,1, -0.0053,-0.0037,0.001,1, -0.0031,-0.0008,0.0002,1, 0,0.0024,-0.0007,1},
      ["neck.x"] = {0,0.0014,0,1, -0.0035,0.0028,0,1, -0.006,0.0035,0,1, -0.007,0.0032,0,1, -0.006,0.0021,0,1, -0.0035,0.0004,0,1, 0,-0.0014,0,1, 0.0035,-0.0028,0,1, 0.006,-0.0035,0,1, 0.007,-0.0032,0,1, 0.006,-0.0021,0,1, 0.0035,-0.0004,0,1, 0,0.0014,0,1},
      ["head.x"] = {0,-0.0051,0,1, -0.0017,-0.0104,0,0.9999, -0.003,-0.013,0,0.9999, -0.0035,-0.0121,0,0.9999, -0.003,-0.0079,0,1, -0.0017,-0.0016,0,1, 0,0.0051,0,1, 0.0017,0.0104,0,0.9999, 0.003,0.013,0,0.9999, 0.0035,0.0121,0,0.9999, 0.003,0.0079,0,1, 0.0017,0.0016,0,1, 0,-0.0051,0,1},
      ["shoulder.l"] = {0,0,0.0034,1, 0.0031,0,0.007,1, 0.0053,0,0.0087,0.9999, 0.0061,0,0.008,0.9999, 0.0053,0,0.0053,1, 0.0031,0,0.0011,1, 0,0,-0.0034,1, -0.0031,0,-0.007,1, -0.0053,0,-0.0087,0.9999, -0.0061,0,-0.008,0.9999, -0.0053,0,-0.0053,1, -0.0031,0,-0.0011,1, 0,0,0.0034,1},
      ["arm_stretch.l"] = {0.0016,0.002,-0.0036,1, 0.004,0.0026,-0.0097,0.9999, 0.0053,0.0026,-0.0132,0.9999, 0.0051,0.0019,-0.0131,0.9999, 0.0036,0.0007,-0.0095,0.9999, 0.0012,-0.0007,-0.0034,1, -0.0016,-0.002,0.0036,1, -0.004,-0.0027,0.0097,0.9999, -0.0052,-0.0028,0.0131,0.9999, -0.0051,-0.0021,0.0131,0.9999, -0.0036,-0.0008,0.0095,0.9999, -0.0011,0.0007,0.0034,1, 0.0016,0.002,-0.0036,1},
      ["forearm_stretch.l"] = {0.0004,-0.0001,0.0013,1, -0.0011,0.0005,0.0033,1, -0.0024,0.0009,0.0044,1, -0.003,0.0011,0.0044,1, -0.0028,0.001,0.0032,1, -0.0018,0.0006,0.0011,1, -0.0004,0.0001,-0.0013,1, 0.0011,-0.0005,-0.0033,1, 0.0024,-0.0009,-0.0044,1, 0.003,-0.0011,-0.0044,1, 0.0028,-0.001,-0.0032,1, 0.0018,-0.0006,-0.0011,1, 0.0004,-0.0001,0.0013,1},
      ["forearm_twist.l"] = {-0.0042,-0.0036,-0.0044,1, -0.0174,-0.0033,-0.005,0.9998, -0.0258,-0.0021,-0.0041,0.9997, -0.0274,-0.0004,-0.0023,0.9996, -0.0216,0.0016,0.0001,0.9998, -0.01,0.003,0.0025,0.9999, 0.0042,0.0036,0.0044,1, 0.0174,0.0032,0.0053,0.9998, 0.0259,0.0018,0.0048,0.9997, 0.0274,0,0.0029,0.9996, 0.0216,-0.0018,0.0002,0.9998, 0.0101,-0.0031,-0.0025,0.9999, -0.0042,-0.0036,-0.0044,1},
      ["arm_twist.l"] = {-0.0014,-0.0046,-0.0038,1, -0.0154,-0.0084,-0.0069,0.9998, -0.0252,-0.0099,-0.008,0.9996, -0.0283,-0.0088,-0.007,0.9995, -0.0238,-0.0052,-0.0043,0.9997, -0.013,-0.0003,-0.0004,0.9999, 0.0014,0.0046,0.0039,1, 0.0154,0.0081,0.0072,0.9998, 0.0252,0.0094,0.0087,0.9996, 0.0283,0.0082,0.0078,0.9995, 0.0238,0.0049,0.0047,0.9997, 0.0129,0.0002,0.0004,0.9999, -0.0014,-0.0046,-0.0038,1},
      ["shoulder.r"] = {0,0,-0.0031,1, 0.0022,0,-0.0063,1, 0.0038,0,-0.0078,1, 0.0044,0,-0.0072,1, 0.0038,0,-0.0047,1, 0.0022,0,-0.001,1, 0,0,0.0031,1, -0.0022,0,0.0063,1, -0.0038,0,0.0078,1, -0.0044,0,0.0072,1, -0.0038,0,0.0047,1, -0.0022,0,0.001,1, 0,0,-0.0031,1},
      ["arm_stretch.r"] = {-0.0004,0.0002,0.002,1, -0.0004,0.0001,0.0038,1, -0.0003,-0.0001,0.0046,1, -0.0001,-0.0002,0.0042,1, 0.0002,-0.0002,0.0026,1, 0.0003,-0.0002,0.0003,1, 0.0004,-0.0002,-0.002,1, 0.0004,0,-0.0038,1, 0.0003,0.0001,-0.0046,1, 0.0001,0.0002,-0.0042,1, -0.0002,0.0003,-0.0026,1, -0.0003,0.0002,-0.0003,1, -0.0004,0.0002,0.002,1},
      ["forearm_stretch.r"] = {0,0,0.001,1, -0.0027,-0.0003,0.002,1, -0.0046,-0.0004,0.0024,1, -0.0053,-0.0004,0.0022,1, -0.0046,-0.0004,0.0014,1, -0.0026,-0.0002,0.0002,1, 0,0,-0.001,1, 0.0027,0.0003,-0.002,1, 0.0046,0.0004,-0.0024,1, 0.0053,0.0005,-0.0022,1, 0.0046,0.0004,-0.0014,1, 0.0026,0.0002,-0.0002,1, 0,0,0.001,1},
      ["forearm_twist.r"] = {0.0047,-0.0039,-0.0037,1, 0.0022,-0.0132,-0.0125,0.9998, -0.001,-0.0191,-0.018,0.9997, -0.0038,-0.0198,-0.0187,0.9996, -0.0056,-0.0152,-0.0144,0.9998, -0.0059,-0.0065,-0.0063,0.9999, -0.0047,0.0039,0.0037,1, -0.0023,0.0131,0.0128,0.9998, 0.0008,0.0187,0.0185,0.9997, 0.0036,0.0194,0.0193,0.9996, 0.0055,0.0149,0.0148,0.9998, 0.0059,0.0064,0.0063,0.9999, 0.0047,-0.0039,-0.0037,1},
      ["arm_twist.r"] = {0.0043,-0.0043,-0.0026,1, -0.0017,-0.0139,-0.0099,0.9999, -0.0073,-0.0198,-0.0144,0.9997, -0.0109,-0.0204,-0.0151,0.9996, -0.0116,-0.0154,-0.0119,0.9997, -0.0092,-0.0063,-0.0055,0.9999, -0.0043,0.0043,0.0026,1, 0.0017,0.0137,0.0102,0.9999, 0.0072,0.0193,0.0152,0.9997, 0.0108,0.0198,0.016,0.9996, 0.0115,0.0151,0.0124,0.9997, 0.0092,0.0063,0.0055,0.9999, 0.0043,-0.0043,-0.0026,1},
      ["thigh_stretch.l"] = {-0.0073,-0.0035,0.0021,1, -0.0169,-0.0066,-0.0048,0.9998, -0.0219,-0.008,-0.0098,0.9997, -0.0208,-0.0072,-0.008,0.9997, -0.014,-0.0044,-0.0019,0.9999, -0.0033,-0.0005,0.0055,1, 0.008,0.0035,0.0086,0.9999, 0.0179,0.0066,0.0171,0.9997, 0.0229,0.0079,0.021,0.9995, 0.0218,0.0071,0.0196,0.9995, 0.0149,0.0044,0.0132,0.9998, 0.0044,0.0005,0.0098,0.9999, -0.0073,-0.0035,0.0021,1},
      ["leg_stretch.l"] = {0.0062,0.0024,-0.0182,0.9998, 0.0059,0.0051,-0.0189,0.9998, 0.0044,0.0064,-0.0155,0.9998, 0.0048,0.006,-0.0165,0.9998, 0.0055,0.004,-0.0173,0.9998, 0.0053,0.0008,-0.015,0.9999, 0.0016,-0.0024,-0.0029,1, 0.0032,-0.0051,-0.0055,1, 0.0038,-0.0064,-0.0063,1, 0.0037,-0.006,-0.0063,1, 0.0028,-0.0039,-0.005,1, 0.0059,-0.0009,-0.0155,0.9999, 0.0062,0.0024,-0.0182,0.9998},
      ["foot.l"] = {0.0044,-0.0135,0.0084,0.9999, 0.0085,-0.0208,0.0094,0.9997, 0.0104,-0.0229,0.0083,0.9996, 0.0098,-0.0221,0.0085,0.9997, 0.0067,-0.017,0.0082,0.9998, 0.0018,-0.0079,0.0063,0.9999, -0.0038,0.0056,0.0004,1, -0.0079,0.0118,0.0008,0.9999, -0.01,0.0149,0.0008,0.9998, -0.0093,0.0137,0.001,0.9999, -0.0061,0.0087,0.0011,0.9999, -0.0009,-0.0036,0.0063,1, 0.0044,-0.0135,0.0084,0.9999},
      ["leg_twist.l"] = {-0.0003,0,0.0165,0.9999, 0.0032,0,0.0242,0.9997, 0.0057,0,0.0259,0.9996, 0.005,0,0.0251,0.9997, 0.002,0,0.0199,0.9998, -0.0018,0,0.0101,0.9999, -0.004,0,-0.0055,1, -0.0083,0,-0.0116,0.9999, -0.0104,0,-0.0147,0.9998, -0.0098,0,-0.0134,0.9999, -0.0067,0,-0.0083,0.9999, -0.0044,0,0.0058,1, -0.0003,0,0.0165,0.9999},
      ["thigh_twist.l"] = {0.0053,0,-0.0039,1, 0.0117,0,0.0011,0.9999, 0.0149,0,0.0054,0.9999, 0.0138,0,0.004,0.9999, 0.0089,0,-0.0007,1, 0.0015,0,-0.0059,1, -0.006,0,-0.0068,1, -0.0125,0,-0.0136,0.9998, -0.0156,0,-0.0168,0.9997, -0.0146,0,-0.0158,0.9998, -0.0097,0,-0.0107,0.9999, -0.0026,0,-0.0095,1, 0.0053,0,-0.0039,1},
      ["thigh_stretch.r"] = {0.0062,-0.0037,-0.0091,0.9999, 0.0112,-0.0077,-0.0195,0.9997, 0.0132,-0.0097,-0.0246,0.9996, 0.0116,-0.009,-0.0234,0.9996, 0.0068,-0.006,-0.0162,0.9998, 0.0003,-0.0013,-0.0042,1, -0.0061,0.0037,0.0099,0.9999, -0.0107,0.0077,0.0223,0.9997, -0.0124,0.0096,0.0288,0.9995, -0.0109,0.0089,0.0271,0.9995, -0.0065,0.0059,0.0179,0.9998, -0.0003,0.0013,0.0045,1, 0.0062,-0.0037,-0.0091,0.9999},
      ["leg_stretch.r"] = {0.0018,0.0019,0.0033,1, 0.0038,0.0039,0.007,1, 0.0047,0.0048,0.0088,0.9999, 0.0047,0.0044,0.0089,0.9999, 0.0036,0.0028,0.0071,1, 0.0012,0.0005,0.0025,1, -0.0025,-0.0019,-0.0049,1, -0.0062,-0.0037,-0.013,0.9999, -0.0084,-0.0044,-0.0178,0.9998, -0.008,-0.0041,-0.0169,0.9998, -0.0051,-0.0027,-0.0108,0.9999, -0.0014,-0.0005,-0.0031,1, 0.0018,0.0019,0.0033,1},
      ["foot.r"] = {-0.0023,-0.0054,-0.0019,1, -0.0047,-0.0108,-0.0036,0.9999, -0.0058,-0.0134,-0.0043,0.9999, -0.0053,-0.012,-0.0042,0.9999, -0.0033,-0.0072,-0.0031,1, -0.0006,-0.0009,-0.0008,1, 0.0023,0.0045,0.0025,1, 0.0045,0.0079,0.006,0.9999, 0.0054,0.009,0.008,0.9999, 0.005,0.0082,0.0074,0.9999, 0.0032,0.0054,0.0046,1, 0.0005,0.0007,0.0011,1, -0.0023,-0.0054,-0.0019,1},
      ["leg_twist.r"] = {-0.0038,0,0.0048,1, -0.0075,0,0.0097,0.9999, -0.0092,0,0.0121,0.9999, -0.0085,0,0.0108,0.9999, -0.0057,0,0.0063,1, -0.0012,0,0.0007,1, 0.0042,0,-0.0038,1, 0.0089,0,-0.0062,0.9999, 0.0113,0,-0.0068,0.9999, 0.0104,0,-0.0061,0.9999, 0.0066,0,-0.0042,1, 0.0013,0,-0.0004,1, -0.0038,0,0.0048,1},
      ["thigh_twist.r"] = {-0.0048,0,0.0071,1, -0.0095,0,0.0148,0.9998, -0.0117,0,0.0185,0.9998, -0.0106,0,0.0176,0.9998, -0.0068,0,0.0122,0.9999, -0.0011,0,0.003,1, 0.0048,0,-0.0078,1, 0.0093,0,-0.0174,0.9998, 0.0114,0,-0.0225,0.9997, 0.0104,0,-0.0211,0.9997, 0.0067,0,-0.0138,0.9999, 0.0011,0,-0.0033,1, -0.0048,0,0.0071,1},
    },
    pos = {-0.0043,-0.002,0, -0.0088,-0.0027,0, -0.0109,-0.0027,0, -0.0101,-0.0027,0, -0.0066,-0.0023,0, -0.0014,-0.0015,0, 0.0043,0.0001,0, 0.0088,0.0001,0, 0.0109,0.0002,0, 0.0101,0.0001,0, 0.0066,0.0001,0, 0.0014,-0.0012,0, -0.0043,-0.002,0},
  },
  Walk = {
    duration = 1.4, loop = true, hit = 0,
    t = {0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.1, 1.2, 1.3, 1.4},
    bones = {
      ["root.x"] = {0.0131,0.0314,-0.0004,0.9994, 0.0129,0.0284,0.0064,0.9995, 0.0128,0.0197,0.012,0.9997, 0.013,0.0072,0.0152,0.9998, 0.0132,-0.0068,0.0154,0.9998, 0.0133,-0.0194,0.0125,0.9996, 0.0133,-0.0282,0.0072,0.9995, 0.0131,-0.0314,0.0004,0.9994, 0.0129,-0.0284,-0.0064,0.9995, 0.0128,-0.0197,-0.012,0.9997, 0.013,-0.0072,-0.0152,0.9998, 0.0132,0.0068,-0.0154,0.9998, 0.0133,0.0194,-0.0125,0.9996, 0.0133,0.0282,-0.0072,0.9995, 0.0131,0.0314,-0.0004,0.9994},
      ["spine_01.x"] = {0.0052,-0.0105,0.0001,0.9999, 0.0052,-0.0094,-0.0022,0.9999, 0.0052,-0.0066,-0.0041,1, 0.0052,-0.0024,-0.0051,1, 0.0052,0.0023,-0.0051,1, 0.0053,0.0065,-0.0041,1, 0.0053,0.0094,-0.0023,0.9999, 0.0052,0.0105,-0.0001,0.9999, 0.0052,0.0094,0.0022,0.9999, 0.0052,0.0066,0.0041,1, 0.0052,0.0024,0.0051,1, 0.0052,-0.0023,0.0051,1, 0.0053,-0.0065,0.0041,1, 0.0053,-0.0094,0.0023,0.9999, 0.0052,-0.0105,0.0001,0.9999},
      ["spine_02.x"] = {0.0087,-0.0157,0.0001,0.9998, 0.0087,-0.0142,-0.0018,0.9999, 0.0087,-0.0098,-0.0033,0.9999, 0.0087,-0.0035,-0.0042,0.9999, 0.0087,0.0035,-0.0043,0.9999, 0.0088,0.0098,-0.0035,0.9999, 0.0088,0.0141,-0.002,0.9999, 0.0087,0.0157,-0.0001,0.9998, 0.0087,0.0142,0.0018,0.9999, 0.0087,0.0098,0.0033,0.9999, 0.0087,0.0035,0.0042,0.9999, 0.0087,-0.0035,0.0043,0.9999, 0.0088,-0.0098,0.0035,0.9999, 0.0088,-0.0141,0.002,0.9999, 0.0087,-0.0157,0.0001,0.9998},
      ["spine_03.x"] = {0.0052,-0.0192,0.0001,0.9998, 0.0052,-0.0173,-0.001,0.9998, 0.0052,-0.012,-0.002,0.9999, 0.0052,-0.0043,-0.0025,1, 0.0052,0.0043,-0.0026,1, 0.0053,0.012,-0.0021,0.9999, 0.0053,0.0173,-0.0012,0.9998, 0.0052,0.0192,-0.0001,0.9998, 0.0052,0.0173,0.001,0.9998, 0.0052,0.012,0.002,0.9999, 0.0052,0.0043,0.0025,1, 0.0052,-0.0043,0.0026,1, 0.0053,-0.012,0.0021,0.9999, 0.0053,-0.0173,0.0012,0.9998, 0.0052,-0.0192,0.0001,0.9998},
      ["neck.x"] = {0.0105,0.0122,-0.0001,0.9999, 0.0105,0.011,-0.0001,0.9999, 0.0105,0.0076,-0.0001,0.9999, 0.0105,0.0027,0,0.9999, 0.0105,-0.0027,0,0.9999, 0.0105,-0.0076,0.0001,0.9999, 0.0105,-0.011,0.0001,0.9999, 0.0105,-0.0122,0.0001,0.9999, 0.0105,-0.011,0.0001,0.9999, 0.0105,-0.0076,0.0001,0.9999, 0.0105,-0.0027,0,0.9999, 0.0105,0.0027,0,0.9999, 0.0105,0.0076,-0.0001,0.9999, 0.0105,0.011,-0.0001,0.9999, 0.0105,0.0122,-0.0001,0.9999},
      ["head.x"] = {-0.0087,0.0105,0.0001,0.9999, -0.0087,0.0094,0.0001,0.9999, -0.0087,0.0065,0.0001,0.9999, -0.0087,0.0023,0,1, -0.0087,-0.0023,0,1, -0.0087,-0.0065,-0.0001,0.9999, -0.0087,-0.0094,-0.0001,0.9999, -0.0087,-0.0105,-0.0001,0.9999, -0.0087,-0.0094,-0.0001,0.9999, -0.0087,-0.0065,-0.0001,0.9999, -0.0087,-0.0023,0,1, -0.0087,0.0023,0,1, -0.0087,0.0065,0.0001,0.9999, -0.0087,0.0094,0.0001,0.9999, -0.0087,0.0105,0.0001,0.9999},
      ["shoulder.l"] = {-0.0131,0,0,0.9999, -0.0118,-0.0001,0.0045,0.9999, -0.0082,-0.0001,0.0082,0.9999, -0.0029,0,0.0102,0.9999, 0.0029,0,0.0102,0.9999, 0.0082,0.0001,0.0082,0.9999, 0.0118,0.0001,0.0045,0.9999, 0.0131,0,0,0.9999, 0.0118,-0.0001,-0.0045,0.9999, 0.0082,-0.0001,-0.0082,0.9999, 0.0029,0,-0.0102,0.9999, -0.0029,0,-0.0102,0.9999, -0.0082,0.0001,-0.0082,0.9999, -0.0118,0.0001,-0.0045,0.9999, -0.0131,0,0,0.9999},
      ["arm_stretch.l"] = {0.0154,0.0058,0.0097,0.9998, 0.0159,0.0078,0.0027,0.9998, 0.0134,0.0083,-0.0049,0.9999, 0.0082,0.0072,-0.0114,0.9999, 0.0015,0.0046,-0.0157,0.9999, -0.0056,0.0012,-0.017,0.9998, -0.0116,-0.0025,-0.0148,0.9998, -0.0154,-0.0056,-0.0098,0.9998, -0.0161,-0.0077,-0.0028,0.9998, -0.0136,-0.0082,0.0048,0.9999, -0.0084,-0.0071,0.0114,0.9999, -0.0015,-0.0046,0.0157,0.9999, 0.0057,-0.0011,0.017,0.9998, 0.0117,0.0026,0.0148,0.9998, 0.0154,0.0058,0.0097,0.9998},
      ["forearm_stretch.l"] = {-0.0035,0.0026,0.0026,1, -0.0023,0.0022,0.0053,1, -0.0006,0.0013,0.0068,1, 0.0012,0.0001,0.0071,1, 0.0028,-0.0011,0.0059,1, 0.0038,-0.002,0.0035,1, 0.0041,-0.0026,0.0005,1, 0.0035,-0.0026,-0.0027,1, 0.0023,-0.0021,-0.0053,1, 0.0006,-0.0012,-0.0069,1, -0.0012,-0.0001,-0.0071,1, -0.0028,0.001,-0.0059,1, -0.0038,0.002,-0.0035,1, -0.0041,0.0025,-0.0005,1, -0.0035,0.0026,0.0026,1},
      ["hand.l"] = {-0.0044,0,0,1, -0.0039,0,0,1, -0.0027,0,0,1, -0.001,0,0,1, 0.001,0,0,1, 0.0027,0,0,1, 0.0039,0,0,1, 0.0044,0,0,1, 0.0039,0,0,1, 0.0027,0,0,1, 0.001,0,0,1, -0.001,0,0,1, -0.0027,0,0,1, -0.0039,0,0,1, -0.0044,0,0,1},
      ["forearm_twist.l"] = {-0.0312,-0.0008,0.0129,0.9994, -0.0309,0.0006,0.0143,0.9994, -0.0297,0.0048,0.015,0.9994, -0.0281,0.0109,0.0149,0.9994, -0.0263,0.0177,0.0141,0.9994, -0.0245,0.0238,0.0127,0.9993, -0.023,0.0279,0.0108,0.9993, -0.0223,0.0293,0.0089,0.9993, -0.0224,0.0277,0.0073,0.9993, -0.0234,0.0234,0.0064,0.9994, -0.0252,0.0174,0.0064,0.9995, -0.0274,0.0109,0.0074,0.9995, -0.0294,0.0049,0.009,0.9995, -0.0307,0.0008,0.011,0.9995, -0.0312,-0.0008,0.0129,0.9994},
      ["arm_twist.l"] = {-0.0367,-0.0093,0.0044,0.9993, -0.0367,-0.0081,0.0087,0.9993, -0.0358,-0.0043,0.0114,0.9993, -0.0343,0.0015,0.0121,0.9993, -0.0324,0.0079,0.0109,0.9994, -0.0302,0.0138,0.0078,0.9994, -0.0282,0.018,0.0034,0.9994, -0.0268,0.0195,-0.0014,0.9994, -0.0263,0.0183,-0.0058,0.9995, -0.027,0.0144,-0.0088,0.9995, -0.0288,0.0086,-0.0097,0.9995, -0.0313,0.0022,-0.0084,0.9995, -0.0338,-0.0036,-0.0051,0.9994, -0.0357,-0.0077,-0.0005,0.9993, -0.0367,-0.0093,0.0044,0.9993},
      ["shoulder.r"] = {0.0785,0,0,0.9969, 0.0707,-0.0005,-0.0076,0.9975, 0.0489,-0.0007,-0.0136,0.9987, 0.0175,-0.0003,-0.017,0.9997, -0.0175,0.0003,-0.017,0.9997, -0.0489,0.0007,-0.0136,0.9987, -0.0707,0.0005,-0.0076,0.9975, -0.0785,0,0,0.9969, -0.0707,-0.0005,0.0076,0.9975, -0.0489,-0.0007,0.0136,0.9987, -0.0175,-0.0003,0.017,0.9997, 0.0175,0.0003,0.017,0.9997, 0.0489,0.0007,0.0136,0.9987, 0.0707,0.0005,0.0076,0.9975, 0.0785,0,0,0.9969},
      ["arm_stretch.r"] = {-0.0423,-0.0103,-0.01,0.999, -0.0392,-0.0081,-0.0016,0.9992, -0.0283,-0.0047,0.0071,0.9996, -0.0118,-0.001,0.0145,0.9998, 0.0071,0.0026,0.0192,0.9998, 0.0246,0.0058,0.0201,0.9995, 0.0371,0.0083,0.0171,0.9991, 0.0423,0.0096,0.0107,0.999, 0.0391,0.009,0.0021,0.9992, 0.0282,0.0063,-0.0069,0.9996, 0.0117,0.0018,-0.0145,0.9998, -0.007,-0.0035,-0.0191,0.9998, -0.0244,-0.008,-0.0197,0.9995, -0.037,-0.0104,-0.0164,0.9991, -0.0423,-0.0103,-0.01,0.999},
      ["forearm_stretch.r"] = {-0.0086,-0.0022,-0.0012,1, -0.0078,-0.002,-0.0011,1, -0.0054,-0.0014,-0.0008,1, -0.0019,-0.0005,-0.0003,1, 0.0019,0.0005,0.0003,1, 0.0054,0.0014,0.0008,1, 0.0078,0.002,0.0012,1, 0.0086,0.0022,0.0013,1, 0.0078,0.002,0.0012,1, 0.0054,0.0014,0.0008,1, 0.0019,0.0005,0.0003,1, -0.0019,-0.0005,-0.0003,1, -0.0054,-0.0014,-0.0008,1, -0.0078,-0.002,-0.0011,1, -0.0086,-0.0022,-0.0012,1},
      ["hand.r"] = {-0.0262,0,0,0.9997, -0.0236,0,0,0.9997, -0.0163,0,0,0.9999, -0.0058,0,0,1, 0.0058,0,0,1, 0.0163,0,0,0.9999, 0.0236,0,0,0.9997, 0.0262,0,0,0.9997, 0.0236,0,0,0.9997, 0.0163,0,0,0.9999, 0.0058,0,0,1, -0.0058,0,0,1, -0.0163,0,0,0.9999, -0.0236,0,0,0.9997, -0.0262,0,0,0.9997},
      ["forearm_twist.r"] = {-0.0406,-0.0248,-0.0082,0.9988, -0.04,-0.0244,-0.0082,0.9989, -0.036,-0.0222,-0.01,0.9991, -0.0294,-0.0185,-0.0133,0.9993, -0.0217,-0.0141,-0.0173,0.9995, -0.0141,-0.0098,-0.0211,0.9996, -0.0082,-0.0063,-0.0241,0.9997, -0.0049,-0.0045,-0.0256,0.9996, -0.0052,-0.0048,-0.0256,0.9996, -0.009,-0.0072,-0.024,0.9996, -0.0157,-0.011,-0.0211,0.9996, -0.0238,-0.0156,-0.0174,0.9994, -0.0317,-0.02,-0.0135,0.9992, -0.0377,-0.0232,-0.0102,0.999, -0.0406,-0.0248,-0.0082,0.9988},
      ["arm_twist.r"] = {-0.0512,-0.0242,-0.0065,0.9984, -0.0496,-0.0236,-0.0064,0.9985, -0.0431,-0.0213,-0.0083,0.9988, -0.033,-0.0175,-0.0117,0.9992, -0.0212,-0.013,-0.0157,0.9996, -0.01,-0.0085,-0.0197,0.9997, -0.0015,-0.0051,-0.0227,0.9997, 0.0026,-0.0034,-0.0243,0.9997, 0.0014,-0.0039,-0.0244,0.9997, -0.0049,-0.0064,-0.0228,0.9997, -0.0151,-0.0104,-0.0199,0.9996, -0.0273,-0.0152,-0.016,0.9994, -0.0388,-0.0195,-0.012,0.999, -0.0473,-0.0227,-0.0085,0.9986, -0.0512,-0.0242,-0.0065,0.9984},
      ["thigh_stretch.l"] = {-0.0733,0.034,0.0009,0.9967, -0.0609,0.0312,-0.0132,0.9976, -0.0509,0.0235,0.0033,0.9984, -0.0453,0.0124,0.0135,0.9988, -0.0417,0,0.0156,0.999, -0.0373,-0.0114,0.0069,0.9992, -0.0295,-0.0199,-0.0154,0.9992, -0.0161,-0.0236,-0.0397,0.9988, 0.0075,-0.0195,0.034,0.9992, 0.0314,-0.009,0.1769,0.9837, 0.0187,0.0014,0.1924,0.9811, 0.011,0.0132,0.2321,0.9725, -0.0037,0.0233,0.2287,0.9732, -0.0291,0.0307,0.1769,0.9833, -0.0733,0.034,0.0009,0.9967},
      ["leg_stretch.l"] = {-0.0128,0.0306,0.0158,0.9993, -0.0209,0.0233,0.0428,0.9986, -0.0104,0.0201,0.0162,0.9996, -0.006,0.0165,0.0063,0.9998, -0.0075,0.0123,0.0128,0.9998, -0.015,0.0075,0.0362,0.9992, -0.0296,0.0022,0.0791,0.9964, -0.042,-0.003,0.1162,0.9923, 0.0216,-0.0148,-0.0495,0.9984, 0.1322,-0.0353,-0.3394,0.9306, 0.1422,-0.0206,-0.3753,0.9157, 0.1669,-0.0062,-0.4509,0.8768, 0.1612,0.0136,-0.446,0.8803, 0.1201,0.033,-0.3451,0.9303, -0.0128,0.0306,0.0158,0.9993},
      ["foot.l"] = {0.0459,-0.0306,-0.0522,0.9971, 0.0365,-0.0168,-0.0509,0.9979, 0.0302,-0.022,-0.032,0.9988, 0.0244,-0.0194,-0.0237,0.9992, 0.018,-0.0091,-0.0242,0.9995, 0.0103,0.0088,-0.0315,0.9994, 0.0004,0.0347,-0.0445,0.9984, -0.0112,0.0582,-0.0513,0.9969, 0.0126,-0.0091,0.0007,0.9999, 0.06,-0.1205,0.1027,0.9856, 0.0143,-0.1294,0.1513,0.9799, 0.0119,-0.166,0.1861,0.9683, 0.025,-0.1769,0.1734,0.9685, 0.0138,-0.146,0.1332,0.9802, 0.0459,-0.0306,-0.0522,0.9971},
      ["leg_twist.l"] = {0.075,0,0.0123,0.9971, 0.0648,0,-0.0011,0.9979, 0.048,0,0.0108,0.9988, 0.0375,0,0.0111,0.9992, 0.0315,0,0.0006,0.9995, 0.0279,0,-0.0199,0.9994, 0.0253,0,-0.0504,0.9984, 0.0175,0,-0.0764,0.9969, -0.0356,0,0.007,0.9993, -0.1063,0,0.159,0.9815, -0.0941,0,0.1835,0.9785, -0.0925,0,0.2319,0.9683, -0.0716,0,0.2383,0.9685, -0.0265,0,0.1928,0.9809, 0.075,0,0.0123,0.9971},
      ["thigh_twist.l"] = {0.0748,0,-0.0012,0.9972, 0.0619,0,0.0194,0.9979, 0.0497,0,0.0088,0.9987, 0.0396,0,0.0028,0.9992, 0.03,0,0.0024,0.9995, 0.0198,0,0.0097,0.9998, 0.0078,0,0.028,0.9996, -0.0075,0,0.0464,0.9989, -0.0327,0,-0.0339,0.9989, -0.0553,0,-0.1834,0.9815, -0.0361,0,-0.2042,0.9783, -0.0197,0,-0.2461,0.969, 0.0032,0,-0.2414,0.9704, 0.0335,0,-0.1848,0.9822, 0.0748,0,-0.0012,0.9972},
      ["thigh_stretch.r"] = {0.0025,0.0299,0.0163,0.9994, 0.0119,0.0257,-0.0499,0.9984, 0.0111,0.0143,-0.1836,0.9828, -0.0111,0.0016,-0.193,0.9811, -0.0314,-0.0125,-0.2295,0.9727, -0.0514,-0.0242,-0.2244,0.9728, -0.0719,-0.0314,-0.1775,0.981, -0.0886,-0.0322,-0.0002,0.9955, -0.0721,-0.0289,-0.0154,0.9969, -0.0584,-0.0201,-0.0265,0.9977, -0.0469,-0.0077,-0.0333,0.9983, -0.0366,0.006,-0.0343,0.9987, -0.026,0.0181,-0.0277,0.9991, -0.0135,0.0266,-0.0116,0.9995, 0.0025,0.0299,0.0163,0.9994},
      ["leg_stretch.r"] = {-0.0319,0.0041,-0.0752,0.9966, 0.0384,0.0154,0.0827,0.9957, 0.1655,0.036,0.3729,0.9123, 0.1743,0.0196,0.3969,0.901, 0.2044,0.0037,0.4702,0.8586, 0.1974,-0.0172,0.4581,0.8666, 0.1507,-0.0355,0.3568,0.9213, -0.0174,-0.0258,-0.029,0.9991, -0.0019,-0.0235,0.0051,0.9997, 0.0073,-0.0199,0.0245,0.9995, 0.011,-0.0155,0.0314,0.9993, 0.0093,-0.0107,0.0257,0.9996, 0.0021,-0.0055,0.0071,1, -0.011,-0.0003,-0.0253,0.9996, -0.0319,0.0041,-0.0752,0.9966},
      ["foot.r"] = {-0.0088,-0.0517,0.0271,0.9983, 0.0095,0.0259,-0.0159,0.9995, 0.0524,0.1676,-0.1104,0.9783, 0.015,0.1741,-0.1617,0.9713, 0.012,0.2176,-0.1953,0.9562, 0.0204,0.2238,-0.1736,0.9588, 0.0095,0.1811,-0.1311,0.9746, 0.0313,0.0228,0.0774,0.9963, 0.0265,0.0354,0.0482,0.9979, 0.0218,0.0393,0.0287,0.9986, 0.017,0.0354,0.0174,0.9991, 0.0119,0.0239,0.0129,0.9996, 0.006,0.0054,0.0137,0.9999, -0.0008,-0.0196,0.0183,0.9996, -0.0088,-0.0517,0.0271,0.9983},
      ["leg_twist.r"] = {0.0089,0,0.0584,0.9983, -0.0496,0,-0.0279,0.9984, -0.1341,0,-0.1962,0.9713, -0.1191,0,-0.2151,0.9693, -0.1202,0,-0.2668,0.9562, -0.0955,0,-0.2672,0.9589, -0.0425,0,-0.214,0.9759, 0.0865,0,-0.0023,0.9963, 0.0614,0,-0.0224,0.9979, 0.043,0,-0.0315,0.9986, 0.0302,0,-0.0305,0.9991, 0.0216,0,-0.0203,0.9996, 0.0158,0,-0.0017,0.9999, 0.0116,0,0.0242,0.9996, 0.0089,0,0.0584,0.9983},
      ["thigh_twist.r"] = {-0.0172,0,-0.0231,0.9996, -0.0306,0,0.0493,0.9983, -0.0327,0,0.1886,0.9815, -0.0081,0,0.2017,0.9794, 0.0167,0,0.2385,0.971, 0.0418,0,0.2304,0.9722, 0.0656,0,0.178,0.9818, 0.0798,0,-0.0061,0.9968, 0.0661,0,0.0034,0.9978, 0.0536,0,0.01,0.9985, 0.0417,0,0.0142,0.999, 0.0296,0,0.015,0.9994, 0.0163,0,0.0107,0.9998, 0.0009,0,-0.0009,1, -0.0172,0,-0.0231,0.9996},
    },
    pos = {-0.011,0.0006,0, -0.0137,0.0068,0, -0.0136,0.0078,0, -0.0109,0.0084,0, -0.006,0.0086,0, 0,0.0083,0, 0.0061,0.0092,0, 0.011,0.0068,0, 0.0137,0.0082,0, 0.0136,0.0087,0, 0.0109,0.0084,0, 0.006,0.0072,0, 0,0.0052,0, -0.0061,0.0019,0, -0.011,0.0006,0},
  },
  Attack = {
    duration = 1.5, loop = false, hit = 0.66,
    t = {0, 0.1, 0.2, 0.28, 0.32, 0.4, 0.46, 0.52, 0.58, 0.63, 0.66, 0.7, 0.76, 0.86, 0.96, 1.1, 1.24, 1.38, 1.5},
    bones = {
      ["root.x"] = {0,0,0,1, -0.001,-0.012,0,0.9999, -0.0028,-0.0344,-0.0001,0.9994, -0.0038,-0.0459,-0.0002,0.9989, -0.0038,-0.0464,-0.0002,0.9989, -0.0038,-0.0464,-0.0002,0.9989, -0.003,-0.0398,-0.0001,0.9992, 0.0002,-0.0127,0,0.9999, 0.0042,0.02,-0.0001,0.9998, 0.0065,0.0393,-0.0003,0.9992, 0.007,0.0432,-0.0003,0.999, 0.007,0.0432,-0.0003,0.999, 0.007,0.0432,-0.0003,0.999, 0.007,0.0432,-0.0003,0.999, 0.007,0.0432,-0.0003,0.999, 0.0065,0.04,-0.0003,0.9992, 0.0039,0.0243,-0.0001,0.9997, 0.0011,0.0067,0,1, 0,0,0,1},
      ["spine_01.x"] = {0,0,0,1, -0.0014,-0.0066,-0.0016,1, -0.0041,-0.0188,-0.0046,0.9998, -0.0055,-0.025,-0.0062,0.9997, -0.0055,-0.0253,-0.0063,0.9996, -0.0055,-0.0253,-0.0063,0.9996, -0.0033,-0.0217,-0.0055,0.9997, 0.0058,-0.007,-0.0025,1, 0.0167,0.0109,0.0008,0.9998, 0.0231,0.0215,0.0026,0.9995, 0.0243,0.0236,0.0029,0.9994, 0.0249,0.0236,0.0029,0.9994, 0.0265,0.0236,0.0029,0.9994, 0.0266,0.0236,0.0029,0.9994, 0.0266,0.0236,0.0029,0.9994, 0.0247,0.0219,0.0027,0.9995, 0.0153,0.0133,0.0018,0.9998, 0.0046,0.0037,0.0005,1, 0.0002,0,0,1},
      ["spine_02.x"] = {0,0,0,1, -0.0014,-0.0077,-0.0014,1, -0.0041,-0.0219,-0.0041,0.9997, -0.0055,-0.0292,-0.0055,0.9995, -0.0055,-0.0295,-0.0055,0.9995, -0.0055,-0.0295,-0.0055,0.9995, -0.0033,-0.0253,-0.0048,0.9997, 0.0058,-0.0081,-0.0022,0.9999, 0.0167,0.0127,0.0007,0.9998, 0.0231,0.0251,0.0021,0.9994, 0.0243,0.0276,0.0024,0.9993, 0.0249,0.0276,0.0024,0.9993, 0.0265,0.0276,0.0023,0.9993, 0.0266,0.0276,0.0023,0.9993, 0.0266,0.0276,0.0023,0.9993, 0.0247,0.0255,0.0022,0.9994, 0.0153,0.0155,0.0015,0.9998, 0.0046,0.0043,0.0005,1, 0.0002,0,0,1},
      ["spine_03.x"] = {0,0,0,1, -0.0012,-0.0077,-0.001,1, -0.0035,-0.0219,-0.0029,0.9998, -0.0047,-0.0292,-0.0039,0.9996, -0.0047,-0.0295,-0.004,0.9995, -0.0047,-0.0295,-0.004,0.9995, -0.0028,-0.0253,-0.0035,0.9997, 0.005,-0.0081,-0.0015,1, 0.0143,0.0127,0.0004,0.9998, 0.0198,0.0251,0.0014,0.9995, 0.0209,0.0275,0.0016,0.9994, 0.0214,0.0275,0.0016,0.9994, 0.0227,0.0275,0.0016,0.9994, 0.0228,0.0275,0.0016,0.9994, 0.0228,0.0275,0.0016,0.9994, 0.0212,0.0255,0.0015,0.9994, 0.0131,0.0155,0.001,0.9998, 0.0039,0.0043,0.0003,1, 0.0002,0,0,1},
      ["neck.x"] = {0,0,0,1, 0.001,0.0055,0,1, 0.0028,0.0156,0,0.9999, 0.0038,0.0208,-0.0001,0.9998, 0.0038,0.0211,-0.0001,0.9998, 0.0038,0.0211,-0.0001,0.9998, 0.0023,0.0181,0,0.9998, -0.0042,0.0058,0,1, -0.0119,-0.0091,-0.0001,0.9999, -0.0165,-0.0179,-0.0003,0.9997, -0.0174,-0.0196,-0.0003,0.9997, -0.0179,-0.0196,-0.0004,0.9996, -0.019,-0.0196,-0.0004,0.9996, -0.0191,-0.0196,-0.0004,0.9996, -0.0191,-0.0196,-0.0004,0.9996, -0.0177,-0.0182,-0.0003,0.9997, -0.0109,-0.011,-0.0001,0.9999, -0.0033,-0.0031,0,1, -0.0001,0,0,1},
      ["head.x"] = {0,0,0,1, 0.0014,0.0077,0,1, 0.004,0.0219,-0.0001,0.9998, 0.0053,0.0292,-0.0002,0.9996, 0.0054,0.0296,-0.0002,0.9995, 0.0054,0.0296,-0.0002,0.9995, 0.0051,0.0253,-0.0001,0.9997, 0.004,0.0081,0,1, 0.0027,-0.0127,0,0.9999, 0.0019,-0.025,0,0.9997, 0.0017,-0.0275,0,0.9996, 0.0012,-0.0275,0,0.9996, -0.0004,-0.0275,0,0.9996, -0.0005,-0.0275,0,0.9996, -0.0005,-0.0275,0,0.9996, -0.0005,-0.0254,0,0.9997, -0.0006,-0.0155,0,0.9999, -0.0005,-0.0043,0,1, -0.0002,0,0,1},
      ["shoulder.l"] = {0.0117,0,0.0323,0.9994, 0.0033,-0.0231,0.0378,0.999, -0.0118,-0.0662,0.0491,0.9965, -0.0192,-0.0884,0.0555,0.9944, -0.0196,-0.0896,0.0558,0.9942, -0.0196,-0.0896,0.0558,0.9942, -0.0231,-0.0734,0.0573,0.9954, -0.0378,-0.0071,0.0623,0.9973, -0.0568,0.0736,0.0659,0.9935, -0.0684,0.122,0.0667,0.9879, -0.0708,0.1316,0.0668,0.9865, -0.0709,0.1329,0.0667,0.9863, -0.0711,0.1363,0.0664,0.9859, -0.0711,0.1367,0.0664,0.9858, -0.0711,0.1367,0.0664,0.9858, -0.0645,0.1265,0.0646,0.9877, -0.0332,0.077,0.054,0.995, -0.0003,0.0221,0.0389,0.999, 0.0117,0.0005,0.0323,0.9994},
      ["arm_stretch.l"] = {-0.0514,0.015,0.0078,0.9985, -0.0731,0.0039,0.0237,0.997, -0.1107,-0.0152,0.0584,0.992, -0.1281,-0.0241,0.0787,0.9883, -0.1289,-0.0246,0.0797,0.9881, -0.1289,-0.0246,0.0797,0.9881, -0.1224,-0.015,0.079,0.9892, -0.0974,0.0231,0.0791,0.9918, -0.0709,0.0666,0.0846,0.9917, -0.0572,0.0906,0.09,0.9902, -0.0547,0.0951,0.0912,0.9898, -0.0538,0.0944,0.0911,0.9899, -0.0516,0.0926,0.0909,0.9902, -0.0514,0.0924,0.0909,0.9902, -0.0514,0.0924,0.0909,0.9902, -0.049,0.088,0.0842,0.9913, -0.0425,0.0626,0.0519,0.9958, -0.0463,0.0287,0.0189,0.9983, -0.051,0.0147,0.0077,0.9986},
      ["forearm_twist.l"] = {0.0445,-0.0158,-0.0539,0.9974, 0.0499,-0.018,-0.0704,0.9961, 0.0554,-0.0208,-0.1053,0.9927, 0.0557,-0.0214,-0.1251,0.9903, 0.0557,-0.0214,-0.1262,0.9902, 0.0557,-0.0214,-0.1262,0.9902, 0.0605,-0.023,-0.1259,0.9899, 0.0818,-0.0297,-0.1229,0.9886, 0.1105,-0.0387,-0.1144,0.9865, 0.1285,-0.0443,-0.1061,0.985, 0.1321,-0.0454,-0.1041,0.9847, 0.1306,-0.0449,-0.1037,0.985, 0.1267,-0.0436,-0.1026,0.9857, 0.1263,-0.0435,-0.1025,0.9857, 0.1263,-0.0435,-0.1025,0.9857, 0.118,-0.0407,-0.0999,0.9871, 0.0818,-0.0287,-0.084,0.9927, 0.0519,-0.0184,-0.0622,0.9965, 0.044,-0.0156,-0.0537,0.9975},
      ["arm_twist.l"] = {0.0614,0,-0.037,0.9974, 0.0719,0,-0.0509,0.9961, 0.0884,0,-0.0823,0.9927, 0.0949,0,-0.1011,0.9903, 0.0952,0,-0.1021,0.9902, 0.0952,0,-0.1021,0.9902, 0.0999,0,-0.1002,0.9899, 0.1203,0,-0.0906,0.9886, 0.1463,0,-0.0734,0.9865, 0.1617,0,-0.0597,0.985, 0.1647,0,-0.0566,0.9847, 0.1631,0,-0.0567,0.985, 0.1589,0,-0.0569,0.9857, 0.1584,0,-0.0569,0.9857, 0.1584,0,-0.0569,0.9857, 0.1493,0,-0.0572,0.9871, 0.1081,0,-0.0536,0.9927, 0.0714,0,-0.0425,0.9965, 0.0608,0,-0.0369,0.9975},
      ["shoulder.r"] = {-0.0796,0,-0.001,0.9968, -0.0172,-0.0304,-0.0157,0.9993, 0.1018,-0.0832,-0.0538,0.9899, 0.1596,-0.1076,-0.077,0.9783, 0.1625,-0.1088,-0.0782,0.9776, 0.1625,-0.1088,-0.0782,0.9776, 0.1156,-0.0965,-0.0785,0.9855, -0.07,-0.04,-0.0976,0.992, -0.2309,0.0303,-0.1577,0.9596, -0.2834,0.0673,-0.2067,0.934, -0.2903,0.074,-0.2171,0.929, -0.2905,0.0734,-0.2169,0.9291, -0.2909,0.0717,-0.2164,0.9292, -0.2909,0.0715,-0.2163,0.9292, -0.2909,0.0715,-0.2163,0.9292, -0.2779,0.0676,-0.2005,0.937, -0.2055,0.0449,-0.1194,0.9703, -0.1148,0.0132,-0.0315,0.9928, -0.0796,-0.0002,-0.001,0.9968},
      ["arm_stretch.r"] = {-0.0001,0.0102,-0.0001,0.9999, 0.0776,0.0076,-0.0227,0.9967, 0.4894,0.0194,-0.1392,0.8607, 0.6009,0.0315,-0.1743,0.7795, 0.6039,0.0322,-0.1754,0.7769, 0.6039,0.0322,-0.1754,0.7769, 0.5861,0.0367,-0.1792,0.7893, 0.2194,0.0399,-0.0865,0.971, -0.1553,-0.0036,0.0463,0.9868, -0.2143,-0.021,0.0517,0.9752, -0.2221,-0.0242,0.0506,0.9734, -0.2221,-0.0241,0.0508,0.9734, -0.2221,-0.0238,0.0515,0.9734, -0.2221,-0.0238,0.0515,0.9734, -0.2221,-0.0238,0.0515,0.9734, -0.2086,-0.0186,0.0505,0.9765, -0.1265,0.0027,0.0405,0.9911, -0.0297,0.0111,0.0141,0.9994, -0.0001,0.0101,-0.0001,0.9999},
      ["forearm_stretch.r"] = {0.0006,0.0045,-0.0004,1, -0.0019,-0.0037,0.0304,0.9995, 0.0522,0.0432,0.1261,0.9897, 0.0559,0.0732,0.134,0.9867, 0.0557,0.074,0.134,0.9866, 0.0557,0.074,0.134,0.9866, 0.0567,0.0689,0.1363,0.9866, 0.0575,0.0073,0.09,0.9943, 0.0894,0.0239,0.0077,0.9957, 0.1098,0.0333,0.01,0.9933, 0.1133,0.0342,0.012,0.9929, 0.1133,0.0341,0.0119,0.9929, 0.1132,0.0338,0.0115,0.9929, 0.1132,0.0337,0.0115,0.9929, 0.1132,0.0337,0.0115,0.9929, 0.1073,0.0315,0.0091,0.9937, 0.0674,0.0192,-0.0014,0.9975, 0.0162,0.0075,-0.0034,0.9998, 0.0006,0.0044,-0.0004,1},
      ["hand.r"] = {0,0,0,1, -0.002,0.0019,0.0399,0.9992, -0.1217,0.0858,0.1249,0.9809, -0.1318,0.1208,0.1237,0.9761, -0.1313,0.1217,0.1233,0.9761, -0.1313,0.1217,0.1233,0.9761, -0.1491,0.1192,0.1365,0.9721, -0.0204,0.0334,0.1482,0.9882, 0.1566,-0.0032,0.1091,0.9816, 0.1884,-0.0029,0.1369,0.9725, 0.1936,-0.0026,0.1449,0.9703, 0.1938,-0.0027,0.1446,0.9703, 0.1943,-0.0028,0.1438,0.9703, 0.1944,-0.0029,0.1437,0.9703, 0.1944,-0.0029,0.1437,0.9703, 0.183,-0.0029,0.1323,0.9742, 0.1159,-0.0024,0.0745,0.9905, 0.031,-0.0007,0.0173,0.9994, 0,0,0,1},
      ["forearm_twist.r"] = {0.0768,0,0.0159,0.9969, -0.0477,0,0.0135,0.9988, -0.596,0,0.0466,0.8016, -0.7368,0,0.0756,0.6719, -0.7408,0,0.0771,0.6672, -0.7408,0,0.0771,0.6672, -0.7032,0,0.0789,0.7066, -0.2304,0,0.086,0.9693, 0.2039,0,0.1225,0.9713, 0.2462,0,0.1642,0.9552, 0.2475,0,0.1723,0.9534, 0.2468,0,0.1709,0.9539, 0.245,0,0.1673,0.955, 0.2448,0,0.1669,0.9551, 0.2448,0,0.1669,0.9551, 0.2355,0,0.1549,0.9594, 0.1782,0,0.0943,0.9795, 0.1033,0,0.0337,0.9941, 0.0764,0,0.0156,0.997},
      ["arm_twist.r"] = {0.0781,0,0.0124,0.9969, -0.0482,0,0.0454,0.9978, -0.541,0,0.1928,0.8186, -0.6776,0,0.2434,0.694, -0.6817,0,0.2454,0.6893, -0.6817,0,0.2454,0.6893, -0.6418,0,0.2463,0.7263, -0.167,0,0.1807,0.9692, 0.2973,0,0.114,0.9479, 0.3609,0,0.1516,0.9202, 0.366,0,0.1611,0.9166, 0.3652,0,0.1596,0.9171, 0.3632,0,0.156,0.9186, 0.363,0,0.1556,0.9187, 0.363,0,0.1556,0.9187, 0.3476,0,0.143,0.9267, 0.2489,0,0.0804,0.9652, 0.1208,0,0.0252,0.9924, 0.0777,0,0.0121,0.9969},
      ["thigh_stretch.l"] = {0.0012,0,0.0163,0.9999, -0.0128,-0.0113,0.0033,0.9998, -0.0365,-0.0322,0.0079,0.9988, -0.0484,-0.0428,0.017,0.9978, -0.0488,-0.0432,0.0251,0.9976, -0.0488,-0.0432,0.0251,0.9976, -0.0385,-0.0369,0.0243,0.9983, 0.0043,-0.0112,0.0219,0.9997, 0.0569,0.0195,0.0188,0.998, 0.088,0.0375,0.0117,0.9953, 0.0943,0.041,0.0109,0.9946, 0.0946,0.041,0.0131,0.9946, 0.0953,0.0409,0.0187,0.9944, 0.0954,0.0409,0.0193,0.9944, 0.0954,0.0409,0.0193,0.9944, 0.0883,0.0379,0.0197,0.9952, 0.0536,0.0232,0.0199,0.9981, 0.015,0.0065,0.0099,0.9998, 0.0012,0,0.0174,0.9998},
      ["leg_stretch.l"] = {0.0119,-0.0002,-0.0322,0.9994, 0.0017,0.0038,-0.0068,1, 0.0037,0.0109,-0.0164,0.9998, 0.0095,0.0151,-0.0346,0.9992, 0.0154,0.0157,-0.0509,0.9985, 0.0154,0.0157,-0.0509,0.9985, 0.017,0.0119,-0.0529,0.9984, 0.0244,-0.0044,-0.0641,0.9976, 0.0336,-0.0256,-0.0779,0.9961, 0.0353,-0.0382,-0.0761,0.9957, 0.0361,-0.0408,-0.0769,0.9956, 0.0378,-0.0412,-0.0813,0.9951, 0.042,-0.0422,-0.0925,0.9939, 0.0424,-0.0423,-0.0937,0.9938, 0.0424,-0.0423,-0.0937,0.9938, 0.0406,-0.0388,-0.0902,0.9943, 0.0303,-0.0225,-0.0701,0.9968, 0.0116,-0.0057,-0.0282,0.9995, 0.0127,-0.0002,-0.0345,0.9993},
      ["foot.l"] = {0.001,-0.0121,0.0134,0.9998, 0.0058,-0.0084,-0.0008,0.9999, 0.0162,-0.0225,-0.0036,0.9996, 0.0219,-0.0345,0.0003,0.9992, 0.0226,-0.0408,0.0069,0.9989, 0.0226,-0.0408,0.0069,0.9989, 0.0177,-0.0382,0.0132,0.999, -0.0024,-0.028,0.04,0.9988, -0.0268,-0.0151,0.0722,0.9969, -0.0419,-0.0033,0.087,0.9953, -0.0448,-0.0013,0.0904,0.9949, -0.0447,-0.003,0.0923,0.9947, -0.0443,-0.0073,0.097,0.9943, -0.0443,-0.0077,0.0975,0.9942, -0.0443,-0.0077,0.0975,0.9942, -0.0409,-0.0085,0.0917,0.9949, -0.0244,-0.0109,0.062,0.9977, -0.0065,-0.0063,0.0208,0.9997, 0.001,-0.0129,0.0143,0.9998},
      ["leg_twist.l"] = {-0.0065,0,0.0168,0.9998, 0.0062,0,0.0082,0.9999, 0.0182,0,0.0213,0.9996, 0.0216,0,0.0347,0.9992, 0.0186,0,0.0433,0.9989, 0.0186,0,0.0433,0.9989, 0.0102,0,0.0429,0.999, -0.0248,0,0.0422,0.9988, -0.0672,0,0.0406,0.9969, -0.0904,0,0.034,0.9953, -0.0953,0,0.0332,0.9949, -0.0962,0,0.0356,0.9947, -0.0985,0,0.0415,0.9943, -0.0988,0,0.0421,0.9942, -0.0988,0,0.0421,0.9942, -0.0921,0,0.0408,0.9949, -0.059,0,0.0328,0.9977, -0.0181,0,0.0136,0.9997, -0.007,0,0.018,0.9998},
      ["thigh_twist.l"] = {-0.0012,0,-0.0163,0.9999, 0.0086,0,-0.0019,1, 0.0245,0,-0.0045,0.9997, 0.0321,0,-0.0128,0.9994, 0.032,0,-0.021,0.9993, 0.032,0,-0.021,0.9993, 0.0238,0,-0.0203,0.9995, -0.01,0,-0.02,0.9997, -0.0518,0,-0.022,0.9984, -0.0768,0,-0.0193,0.9969, -0.0818,0,-0.0194,0.9965, -0.082,0,-0.0217,0.9964, -0.0825,0,-0.0273,0.9962, -0.0826,0,-0.028,0.9962, -0.0826,0,-0.028,0.9962, -0.0764,0,-0.0275,0.9967, -0.0464,0,-0.0238,0.9986, -0.013,0,-0.0108,0.9999, -0.0012,0,-0.0174,0.9998},
      ["thigh_stretch.r"] = {-0.0012,0,-0.0175,0.9998, -0.0252,-0.0115,-0.1338,0.9906, -0.0567,-0.0326,-0.1499,0.9865, -0.0702,-0.0445,-0.0638,0.9945, -0.071,-0.0451,-0.0647,0.9944, -0.071,-0.0451,-0.0647,0.9944, -0.0663,-0.0387,-0.0657,0.9949, -0.047,-0.0126,-0.0709,0.9963, -0.0228,0.0189,-0.0788,0.9965, -0.0075,0.0374,-0.0808,0.996, -0.0044,0.0411,-0.0818,0.9958, -0.0046,0.041,-0.0839,0.9956, -0.0051,0.041,-0.0891,0.9952, -0.0051,0.041,-0.0897,0.9951, -0.0051,0.041,-0.0897,0.9951, -0.0069,0.0376,-0.1108,0.9931, -0.0101,0.0223,-0.1687,0.9854, -0.0068,0.0063,-0.1142,0.9934, -0.0013,0,-0.0187,0.9998},
      ["leg_stretch.r"] = {0.0162,0.0001,0.0373,0.9992, 0.1111,-0.0105,0.2594,0.9593, 0.102,-0.0338,0.2494,0.9624, 0.0152,-0.0311,0.0506,0.9981, 0.0153,-0.0315,0.0513,0.9981, 0.0153,-0.0315,0.0513,0.9981, 0.0204,-0.0295,0.0616,0.9975, 0.0409,-0.0197,0.1029,0.9937, 0.0638,-0.0043,0.1485,0.9868, 0.073,0.0065,0.1661,0.9834, 0.0752,0.0088,0.1705,0.9824, 0.0771,0.0089,0.1749,0.9815, 0.0819,0.0092,0.1859,0.9791, 0.0824,0.0093,0.1871,0.9788, 0.0824,0.0093,0.1871,0.9788, 0.1017,0.0099,0.2315,0.9674, 0.1535,0.0104,0.3512,0.9236, 0.1047,0.0034,0.2401,0.9651, 0.0173,0.0001,0.0398,0.9991},
      ["foot.r"] = {0.0009,0.0171,-0.0154,0.9997, 0.0136,0.1216,-0.0867,0.9887, 0.028,0.1212,-0.0394,0.9915, 0.0311,0.0343,0.0643,0.9969, 0.0315,0.0347,0.0652,0.9968, 0.0315,0.0347,0.0652,0.9968, 0.0291,0.0384,0.0534,0.9974, 0.0192,0.0529,0.0057,0.9984, 0.0073,0.0682,-0.0497,0.9964, 0.0001,0.0729,-0.0783,0.9943, -0.0013,0.0742,-0.0843,0.9937, -0.0012,0.0763,-0.0862,0.9934, -0.001,0.0813,-0.0908,0.9925, -0.001,0.0819,-0.0914,0.9924, -0.001,0.0819,-0.0914,0.9924, 0.0005,0.103,-0.1094,0.9886, 0.005,0.1612,-0.1574,0.9743, 0.0048,0.1101,-0.103,0.9886, 0.001,0.0183,-0.0165,0.9997},
      ["leg_twist.r"] = {-0.0095,0,-0.021,0.9997, -0.0444,0,-0.1433,0.9887, 0.0033,0,-0.1304,0.9915, 0.0773,0,-0.0171,0.9969, 0.0784,0,-0.0173,0.9968, 0.0784,0,-0.0173,0.9968, 0.0677,0,-0.0241,0.9974, 0.0246,0,-0.0509,0.9984, -0.026,0,-0.0806,0.9964, -0.0533,0,-0.0927,0.9943, -0.0589,0,-0.0957,0.9937, -0.0601,0,-0.0982,0.9934, -0.063,0,-0.1044,0.9925, -0.0633,0,-0.1051,0.9924, -0.0633,0,-0.1051,0.9924, -0.0741,0,-0.1307,0.9886, -0.1018,0,-0.201,0.9743, -0.065,0,-0.1361,0.9886, -0.0101,0,-0.0224,0.9997},
      ["thigh_twist.r"] = {0.0012,0,0.0175,0.9998, 0.029,0,0.1342,0.9905, 0.0683,0,0.1497,0.9864, 0.0817,0,0.0628,0.9947, 0.0827,0,0.0636,0.9945, 0.0827,0,0.0636,0.9945, 0.0762,0,0.0649,0.995, 0.0491,0,0.0706,0.9963, 0.0153,0,0.0768,0.9969, -0.0057,0,0.0767,0.997, -0.0099,0,0.0773,0.997, -0.0098,0,0.0793,0.9968, -0.0095,0,0.0846,0.9964, -0.0095,0,0.0852,0.9963, -0.0095,0,0.0852,0.9963, -0.0075,0,0.1067,0.9943, 0,0,0.1665,0.986, 0.0043,0,0.1136,0.9935, 0.0013,0,0.0187,0.9998},
    },
    pos = {0,-0.003,0, -0.0027,0.0001,0, -0.0078,0.0001,0, -0.0104,-0.0014,0, -0.0106,-0.0031,0, -0.0106,-0.0031,0, -0.0098,-0.0034,0.0021, -0.0066,-0.0061,0.0105, -0.0027,-0.0122,0.0207, -0.0005,-0.016,0.0268, 0,-0.0171,0.028, 0,-0.0176,0.028, 0,-0.019,0.028, 0,-0.0192,0.028, 0,-0.0192,0.028, 0,-0.0177,0.0259, 0,-0.0109,0.0157, 0,-0.0033,0.0044, 0,-0.0032,0},
  },
  Hit = {
    duration = 0.62, loop = false, hit = 0.1,
    t = {0, 0.05, 0.09, 0.14, 0.2, 0.26, 0.32, 0.4, 0.5, 0.62},
    bones = {
      ["root.x"] = {0,0,0,1, 0.0065,-0.0131,0.0001,0.9999, 0.0127,-0.0254,0.0003,0.9996, 0.0131,-0.0262,0.0003,0.9996, 0.0131,-0.0262,0.0003,0.9996, 0.0131,-0.0262,0.0003,0.9996, 0.0117,-0.0235,0.0003,0.9997, 0.0072,-0.0144,0.0001,0.9999, 0.0014,-0.0027,0,1, 0.0018,-0.0036,0,1},
      ["spine_01.x"] = {0,0,0,1, -0.0137,-0.0079,-0.0001,0.9999, -0.0267,-0.0153,-0.0004,0.9995, -0.0275,-0.0157,-0.0004,0.9995, -0.0275,-0.0157,-0.0004,0.9995, -0.0275,-0.0157,-0.0004,0.9995, -0.0217,-0.0141,-0.0003,0.9997, -0.0063,-0.0086,-0.0001,0.9999, -0.0029,-0.0016,0,1, -0.0037,-0.0021,0,1},
      ["spine_02.x"] = {0,0,0,1, -0.0138,-0.0104,-0.0067,0.9998, -0.027,-0.02,-0.0133,0.9993, -0.0278,-0.0206,-0.0137,0.9993, -0.0278,-0.0206,-0.0137,0.9993, -0.0278,-0.0206,-0.0137,0.9993, -0.0219,-0.0185,-0.0121,0.9995, -0.0064,-0.0115,-0.0073,0.9999, -0.0029,-0.0022,-0.0014,1, -0.0037,-0.0028,-0.0018,1},
      ["spine_03.x"] = {0,0,0,1, -0.0118,-0.0078,-0.0045,0.9999, -0.023,-0.0151,-0.0088,0.9996, -0.0237,-0.0155,-0.0091,0.9996, -0.0237,-0.0155,-0.0091,0.9996, -0.0237,-0.0155,-0.0091,0.9996, -0.0187,-0.0139,-0.0081,0.9997, -0.0055,-0.0086,-0.0048,0.9999, -0.0025,-0.0016,-0.0009,1, -0.0032,-0.0021,-0.0012,1},
      ["neck.x"] = {0,0,0,1, 0.0196,0.0105,-0.0002,0.9998, 0.0382,0.0203,-0.0008,0.9991, 0.0393,0.0209,-0.0008,0.999, 0.0393,0.0209,-0.0008,0.999, 0.0393,0.0209,-0.0008,0.999, 0.031,0.0188,-0.0006,0.9993, 0.0091,0.0115,-0.0001,0.9999, 0.0041,0.0022,0,1, 0.0053,0.0028,0,1},
      ["head.x"] = {0,0,0,1, 0.0236,0.0131,-0.0003,0.9996, 0.0458,0.0254,-0.0012,0.9986, 0.0471,0.0261,-0.0012,0.9985, 0.0471,0.0261,-0.0012,0.9985, 0.0471,0.0261,-0.0012,0.9985, 0.0372,0.0234,-0.0009,0.999, 0.0109,0.0144,-0.0002,0.9998, 0.0049,0.0027,0,1, 0.0064,0.0036,0,1},
      ["shoulder.l"] = {0.0117,0,0.0323,0.9994, -0.0278,-0.0478,0.0518,0.9971, -0.0642,-0.0917,0.0739,0.991, -0.0663,-0.0942,0.0753,0.9905, -0.0663,-0.0942,0.0753,0.9905, -0.0663,-0.0942,0.0753,0.9905, -0.0589,-0.0783,0.0698,0.9927, -0.0328,-0.0327,0.0534,0.9975, 0.0034,-0.01,0.036,0.9993, 0.0009,-0.0131,0.0372,0.9992},
      ["arm_stretch.l"] = {-0.0514,0.015,0.0078,0.9985, -0.1184,0.0325,0.0951,0.9879, -0.1692,0.0465,0.1912,0.9657, -0.1717,0.0473,0.1972,0.9641, -0.1717,0.0473,0.1972,0.9641, -0.1717,0.0473,0.1972,0.9641, -0.1587,0.0413,0.1737,0.971, -0.1123,0.0241,0.1013,0.9882, -0.066,0.0188,0.0245,0.9973, -0.0705,0.0199,0.0298,0.9969},
      ["forearm_twist.l"] = {0.0445,-0.0158,-0.0539,0.9974, 0.102,-0.0371,-0.1548,0.982, 0.1434,-0.0535,-0.2644,0.9522, 0.1453,-0.0543,-0.2712,0.9499, 0.1453,-0.0543,-0.2712,0.9499, 0.1453,-0.0543,-0.2712,0.9499, 0.1319,-0.0492,-0.2419,0.96, 0.0875,-0.0324,-0.154,0.9837, 0.0573,-0.0205,-0.0733,0.9955, 0.0611,-0.0219,-0.0794,0.9947},
      ["arm_twist.l"] = {0.0614,0,-0.037,0.9974, 0.1504,0,-0.1144,0.982, 0.2262,0,-0.2053,0.9522, 0.2303,0,-0.2112,0.9499, 0.2303,0,-0.2112,0.9499, 0.2303,0,-0.2112,0.9499, 0.2077,0,-0.1876,0.96, 0.1357,0,-0.1183,0.9837, 0.0802,0,-0.0513,0.9955, 0.086,0,-0.0559,0.9947},
      ["shoulder.r"] = {-0.0796,0,-0.001,0.9968, -0.1116,-0.0245,-0.0312,0.993, -0.1431,-0.0452,-0.059,0.9869, -0.145,-0.0463,-0.0606,0.9865, -0.145,-0.0463,-0.0606,0.9865, -0.145,-0.0463,-0.0606,0.9865, -0.1382,-0.045,-0.0541,0.9879, -0.1152,-0.0357,-0.0331,0.9921, -0.0861,-0.0053,-0.0073,0.9962, -0.0881,-0.0069,-0.0093,0.996},
      ["arm_stretch.r"] = {-0.0001,0.0102,-0.0001,0.9999, -0.0209,0.0158,0.0312,0.9992, -0.0381,0.0153,0.063,0.9972, -0.0391,0.015,0.065,0.997, -0.0391,0.015,0.065,0.997, -0.0391,0.015,0.065,0.997, -0.0355,0.0152,0.0578,0.9976, -0.0232,0.0137,0.0344,0.999, -0.0046,0.0118,0.0062,0.9999, -0.006,0.0123,0.0082,0.9999},
      ["forearm_twist.r"] = {0.0775,0.0044,0.0152,0.9969, 0.1675,0.0096,0.0319,0.9853, 0.2532,0.0148,0.0406,0.9664, 0.2583,0.0151,0.0409,0.9651, 0.2583,0.0151,0.0409,0.9651, 0.2583,0.0151,0.0409,0.9651, 0.2334,0.0137,0.035,0.9717, 0.1582,0.0095,0.0194,0.9872, 0.0961,0.0055,0.0193,0.9952, 0.1018,0.0058,0.0204,0.9946},
      ["arm_twist.r"] = {0.0781,0,0.0124,0.9969, 0.1688,0,0.0258,0.9853, 0.2549,0,0.0315,0.9664, 0.26,0,0.0316,0.9651, 0.26,0,0.0316,0.9651, 0.26,0,0.0316,0.9651, 0.2349,0,0.0265,0.9717, 0.159,0,0.0136,0.9872, 0.0969,0,0.0158,0.9952, 0.1026,0,0.0168,0.9946},
      ["thigh_stretch.l"] = {0.0012,0,0.0163,0.9999, -0.0417,-0.0084,0.0574,0.9974, -0.0831,-0.0157,0.0873,0.9926, -0.0856,-0.0162,0.0889,0.9922, -0.0856,-0.0162,0.0889,0.9922, -0.0856,-0.0162,0.0889,0.9922, -0.0764,-0.0146,0.0829,0.9935, -0.0461,-0.0092,0.0609,0.997, -0.0076,-0.0018,0.026,0.9996, -0.0104,-0.0023,0.0288,0.9995},
      ["leg_stretch.l"] = {0.0119,-0.0002,-0.0322,0.9994, 0.0341,0.0173,-0.1029,0.994, 0.0473,0.037,-0.1505,0.9868, 0.0479,0.0382,-0.1529,0.9863, 0.0479,0.0382,-0.1529,0.9863, 0.0479,0.0382,-0.1529,0.9863, 0.0456,0.0336,-0.1438,0.988, 0.0358,0.0193,-0.1087,0.9932, 0.0175,0.0031,-0.0494,0.9986, 0.0191,0.0042,-0.0543,0.9983},
      ["foot.l"] = {0.001,-0.0121,0.0134,0.9998, 0.024,-0.0554,0.0226,0.9979, 0.045,-0.089,0.0234,0.9947, 0.0462,-0.0908,0.0232,0.9945, 0.0462,-0.0908,0.0232,0.9945, 0.0462,-0.0908,0.0232,0.9945, 0.0416,-0.0839,0.0236,0.9953, 0.0262,-0.0592,0.023,0.9976, 0.0058,-0.022,0.0163,0.9996, 0.0073,-0.025,0.0171,0.9995},
      ["leg_twist.l"] = {-0.0065,0,0.0168,0.9998, 0.0112,0,0.0635,0.9979, 0.0317,0,0.0974,0.9947, 0.033,0,0.0992,0.9945, 0.033,0,0.0992,0.9945, 0.033,0,0.0992,0.9945, 0.0282,0,0.0924,0.9953, 0.0132,0,0.0674,0.9976, -0.0033,0,0.0278,0.9996, -0.0023,0,0.031,0.9995},
      ["thigh_twist.l"] = {-0.0012,0,-0.0163,0.9999, 0.03,0,-0.0549,0.998, 0.06,0,-0.0828,0.9948, 0.0618,0,-0.0843,0.9945, 0.0618,0,-0.0843,0.9945, 0.0618,0,-0.0843,0.9945, 0.0551,0,-0.0787,0.9954, 0.0332,0,-0.0582,0.9978, 0.0053,0,-0.0254,0.9997, 0.0072,0,-0.0281,0.9996},
      ["thigh_stretch.r"] = {-0.0012,0,-0.0175,0.9998, 0.0043,-0.014,-0.0544,0.9984, 0.0107,-0.0274,-0.0848,0.996, 0.0111,-0.0282,-0.0865,0.9958, 0.0111,-0.0282,-0.0865,0.9958, 0.0111,-0.0282,-0.0865,0.9958, 0.0096,-0.0253,-0.0801,0.9964, 0.0049,-0.0154,-0.0578,0.9982, -0.0002,-0.0029,-0.0258,0.9997, 0.0001,-0.0038,-0.0282,0.9996},
      ["leg_stretch.r"] = {0.0162,0.0001,0.0373,0.9992, 0.0445,0.0058,0.1005,0.9939, 0.0674,0.0125,0.1507,0.9862, 0.0686,0.013,0.1535,0.9857, 0.0686,0.013,0.1535,0.9857, 0.0686,0.013,0.1535,0.9857, 0.0639,0.0114,0.143,0.9876, 0.0471,0.0065,0.1061,0.9932, 0.0226,0.0012,0.0517,0.9984, 0.0245,0.0015,0.0559,0.9981},
      ["foot.r"] = {0.0009,0.0171,-0.0154,0.9997, -0.0024,0.0367,-0.0473,0.9982, -0.0058,0.0508,-0.0735,0.996, -0.006,0.0515,-0.075,0.9958, -0.006,0.0515,-0.075,0.9958, -0.006,0.0515,-0.075,0.9958, -0.0052,0.0487,-0.0695,0.9964, -0.0027,0.0384,-0.0502,0.998, 0.0003,0.0218,-0.0226,0.9995, 0.0001,0.0232,-0.0247,0.9994},
      ["leg_twist.r"] = {-0.0095,0,-0.021,0.9997, -0.0348,0,-0.0488,0.9982, -0.0564,0,-0.0696,0.996, -0.0576,0,-0.0707,0.9958, -0.0576,0,-0.0707,0.9958, -0.0576,0,-0.0707,0.9958, -0.053,0,-0.0665,0.9964, -0.0371,0,-0.0512,0.998, -0.0151,0,-0.0275,0.9995, -0.0167,0,-0.0294,0.9994},
      ["thigh_twist.r"] = {0.0012,0,0.0175,0.9998, -0.0081,0,0.0525,0.9986, -0.0174,0,0.0814,0.9965, -0.018,0,0.0831,0.9964, -0.018,0,0.0831,0.9964, -0.018,0,0.0831,0.9964, -0.0159,0,0.077,0.9969, -0.0091,0,0.0557,0.9984, -0.0007,0,0.0253,0.9997, -0.0012,0,0.0277,0.9996},
    },
    pos = {0,-0.003,0, -0.005,-0.0101,-0.011, -0.0097,-0.0173,-0.0214, -0.01,-0.0178,-0.022, -0.01,-0.0178,-0.022, -0.01,-0.0178,-0.022, -0.009,-0.0161,-0.0197, -0.0055,-0.0108,-0.0121, -0.001,-0.0044,-0.0023, -0.0014,-0.0049,-0.003},
  },
}

local IDENTITY = Quaternion(0, 0, 0, 1)

local bones = {}
local restRot = {}
local restRootPos = nil
local rootTransform = nil
local missingBones = {}
local boneFound = 0
local boneTotal = #BONE_NAMES
local ready = false
local readyReason = "not-started"

local currentName = nil
local currentMove = nil
local actionTime = 0
local speed = 1
local defaultSpeed = 1
local blendTotal = 0.18
local blendLeft = 0
local blendFrom = {}
local blendFromPos = nil
local holdAtEnd = false
local finishedNotified = false

local function smoothstep(v)
  if v <= 0 then return 0 end
  if v >= 1 then return 1 end
  return v * v * (3 - 2 * v)
end

local function findByName(transform, name, depth)
  if transform == nil or depth > 8 then return nil end
  if transform.name == name then return transform end
  local childCount = transform.childCount
  for i = 0, childCount - 1 do
    local hit = findByName(transform:GetChild(i), name, depth + 1)
    if hit ~= nil then return hit end
  end
  return nil
end

local initialized = false

local function collectBones()
  if runtimeScope == nil then
    readyReason = "scope-unavailable:" .. tostring(scopeReason)
    return
  end
  local rootGo = runtimeScope:GetResourceRoot()
  if rootGo == nil then
    readyReason = "resource-root-missing"
    return
  end
  rootTransform = rootGo.transform
  local usedFallback = false
  for i = 1, boneTotal do
    local name = BONE_NAMES[i]
    local tr, reason = runtimeScope:GetTransformByPath(BONE_PATH[name])
    if tr == nil then
      tr = findByName(rootTransform, name, 0)
      if tr ~= nil then usedFallback = true end
    end
    if tr ~= nil then
      bones[name] = tr
      restRot[name] = tr.localRotation
      boneFound = boneFound + 1
    else
      missingBones[#missingBones + 1] = name
      logger:warn("bone missing", name, tostring(reason))
    end
  end
  if bones["root.x"] ~= nil then restRootPos = bones["root.x"].localPosition end
  ready = boneFound == boneTotal and restRootPos ~= nil
  if ready then
    readyReason = usedFallback and "ready-fallback-search" or "ready"
  else
    readyReason = string.format("bone-missing %d/%d", boneFound, boneTotal)
  end
  logger:info("rig", readyReason)
end

local function buildCache(move)
  if move.cache ~= nil then return move.cache end
  local cache = {}
  for name, values in pairs(move.bones) do
    local list = {}
    local keyCount = #values / 4
    for k = 1, keyCount do
      local b = (k - 1) * 4
      list[k] = Quaternion(values[b + 1], values[b + 2], values[b + 3], values[b + 4])
    end
    cache[name] = list
  end
  move.cache = cache
  return cache
end

-- 采样动作在时间 t 的骨骼偏移（Unity 局部空间），返回 {骨骼名 -> Quaternion} 与髋部偏移
local function samplePose(move, t)
  local cache = buildCache(move)
  local times = move.t
  local count = #times
  local index = 1
  if t <= times[1] then
    index = 1
  elseif t >= times[count] then
    index = count - 1
  else
    for k = 1, count - 1 do
      if t < times[k + 1] then
        index = k
        break
      end
    end
  end
  local span = times[index + 1] - times[index]
  local u = 0
  if span > 0 then u = smoothstep((t - times[index]) / span) end
  local pose = {}
  for name, list in pairs(cache) do
    pose[name] = Quaternion.Slerp(list[index], list[index + 1], u)
  end
  local posTable = move.pos
  local a = (index - 1) * 3
  local b = index * 3
  local ox = posTable[a + 1] + (posTable[b + 1] - posTable[a + 1]) * u
  local oy = posTable[a + 2] + (posTable[b + 2] - posTable[a + 2]) * u
  local oz = posTable[a + 3] + (posTable[b + 3] - posTable[a + 3]) * u
  return pose, ox, oy, oz
end

local function applyPose(pose, ox, oy, oz, blend)
  for i = 1, boneTotal do
    local name = BONE_NAMES[i]
    local tr = bones[name]
    if tr ~= nil then
      local target = pose[name] or IDENTITY
      local targetWorld = restRot[name] * target
      if blend < 1 then
        local from = blendFrom[name]
        if from == nil then from = tr.localRotation end
        tr.localRotation = Quaternion.Slerp(from, targetWorld, blend)
      else
        tr.localRotation = targetWorld
      end
    end
  end
  local rootTr = bones["root.x"]
  if rootTr ~= nil and restRootPos ~= nil then
    local tx = restRootPos.x + ox
    local ty = restRootPos.y + oy
    local tz = restRootPos.z + oz
    if blend < 1 and blendFromPos ~= nil then
      tx = blendFromPos.x + (tx - blendFromPos.x) * blend
      ty = blendFromPos.y + (ty - blendFromPos.y) * blend
      tz = blendFromPos.z + (tz - blendFromPos.z) * blend
    end
    rootTr.localPosition = Vector3(tx, ty, tz)
  end
end

local function restoreRest()
  for i = 1, boneTotal do
    local name = BONE_NAMES[i]
    local tr = bones[name]
    if tr ~= nil and restRot[name] ~= nil then tr.localRotation = restRot[name] end
  end
  local rootTr = bones["root.x"]
  if rootTr ~= nil and restRootPos ~= nil then rootTr.localPosition = restRootPos end
  blendLeft = 0
  blendFrom = {}
end

local function ensureInit()
  if initialized then return ready end
  initialized = true
  if runtimeScope == nil then
    readyReason = "scope-unavailable:" .. tostring(scopeReason)
    logger:error("runtime scope unavailable", tostring(scopeReason))
    return false
  end
  collectBones()
  if type(PlaybackSpeed) == "number" and PlaybackSpeed > 0 then
    defaultSpeed = PlaybackSpeed
  end
  speed = defaultSpeed
  return ready
end

function Play(name, opts)
  if not ensureInit() then
    logger:warnOnce("play-not-ready", "rig not ready:", readyReason)
    return false
  end
  local move = MOVES[name]
  if move == nil then
    logger:warnOnce("play-unknown", "unknown action", tostring(name))
    return false
  end
  opts = opts or {}
  blendFrom = {}
  for i = 1, boneTotal do
    local boneName = BONE_NAMES[i]
    local tr = bones[boneName]
    if tr ~= nil then blendFrom[boneName] = tr.localRotation end
  end
  local rootTr = bones["root.x"]
  if rootTr ~= nil then blendFromPos = rootTr.localPosition end
  currentName = name
  currentMove = move
  actionTime = 0
  holdAtEnd = (opts.hold == true) or (opts.autoReturn == false)
  finishedNotified = false
  local blend = opts.blend
  if blend == nil then blend = 0.18 end
  if blend < 0.01 then blend = 0.01 end
  blendTotal = blend
  blendLeft = blend
  if opts.speed ~= nil then
    speed = opts.speed
  end
  if speed < 0 then speed = 0 end
  return true
end

function SetSpeed(value)
  if value == nil then return false end
  if value < 0 then value = 0 end
  speed = value
  return true
end

function GetAction()
  return currentName or ""
end

function GetActionDuration(name)
  local move = MOVES[name or currentName or ""]
  if move == nil then return 0 end
  return move.duration
end

function GetHitTime(name)
  local move = MOVES[name or currentName or ""]
  if move == nil then return 0 end
  return move.hit
end

function GetRigStatus()
  ensureInit()
  local missing = ""
  if #missingBones > 0 then missing = table.concat(missingBones, ",") end
  return readyReason, boneFound, boneTotal, missing
end

function IsReady()
  return ready
end

function IsPlaying(name)
  if currentName == nil then return false end
  if name ~= nil and name ~= currentName then return false end
  if currentMove ~= nil and currentMove.loop then return true end
  return not finishedNotified
end

function Start()
  if not ensureInit() then return end
  if ready then
    local defaultName = DefaultAction
    if type(defaultName) ~= "string" or MOVES[defaultName] == nil then defaultName = "Idle" end
    Play(defaultName, { blend = 0.01 })
  else
    logger:error("rig incomplete", readyReason)
  end
end

function Update()
  if not ensureInit() then return end
  if currentMove == nil then return end
  local dt = clock.deltaTime * speed
  if dt < 0 then dt = 0 end
  actionTime = actionTime + dt
  local duration = currentMove.duration
  if currentMove.loop then
    if duration > 0 and actionTime > duration then
      actionTime = actionTime - duration * math.floor(actionTime / duration)
    end
  elseif actionTime > duration then
    actionTime = duration
    if not finishedNotified then
      finishedNotified = true
      if not holdAtEnd and currentMove.autoReturn ~= false and currentName ~= "Idle" then
        Play("Idle", { blend = 0.22 })
        return
      end
    end
  end
  local pose, ox, oy, oz = samplePose(currentMove, actionTime)
  local blend = 1
  if blendLeft > 0 then
    blendLeft = blendLeft - clock.deltaTime
    if blendLeft > 0 then
      blend = smoothstep(1 - blendLeft / blendTotal)
    else
      blendLeft = 0
      blendFrom = {}
    end
  end
  applyPose(pose, ox, oy, oz, blend)
end

function OnDisable()
  restoreRest()
end

function OnDestroy()
  restoreRest()
end


Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="Idle",walk="Walk",attack="Attack",hit="Hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.runner=function(root,height)
local Play,Stop,SetSpeed,GetAction,GetRigStatus,GetActionDuration,GetHitTime,IsPlaying,RegisterHitHandler,ClearHitHandler,Start,Update,OnDisable,OnEnable
local PlaybackSpeed=1
local AutoIdle=true
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 裂隙疾爪动画版：待机、疾跑、前扑挥爪、受击四套逐骨骼关键帧

local UnityEngine = CS.UnityEngine
local Quaternion = CS.UnityEngine.Quaternion
local Vector3 = CS.UnityEngine.Vector3
local Time = clock
local RuntimeScope={from=function()return boundScope end}
local Logger = require("official.core.logger")

local logger = Logger.create("ms-runner-animation")
local runtimeScope, runtimeScopeReason = RuntimeScope.from(self)
if runtimeScope == nil then
  logger:warnOnce("scope-missing", "阶段=初始化", "原因=资源上下文缺失", tostring(runtimeScopeReason))
end

-- 骨骼路径全部来自 inspect_resource_nodes 的真实层级；只旋转骨骼，不移动任何节点。
local BONE_KEYS = {
  "hips", "spine1", "spine2", "spine3", "neck", "head",
  "shoulderL", "upperArmL", "foreArmL", "handL",
  "shoulderR", "upperArmR", "foreArmR", "handR",
  "thighL", "shinL", "footL", "toesL",
  "thighR", "shinR", "footR", "toesR",
}

local BONE_PATHS = {
  hips = "Armature/root.x",
  spine1 = "Armature/root.x/spine_01.x",
  spine2 = "Armature/root.x/spine_01.x/spine_02.x",
  spine3 = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x",
  neck = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x",
  head = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x/head.x",
  shoulderL = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l",
  upperArmL = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l",
  foreArmL = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l",
  handL = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l/hand.l",
  shoulderR = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r",
  upperArmR = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r",
  foreArmR = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r",
  handR = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r/hand.r",
  thighL = "Armature/root.x/thigh_stretch.l",
  shinL = "Armature/root.x/thigh_stretch.l/leg_stretch.l",
  footL = "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l",
  toesL = "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l/toes_01.l",
  thighR = "Armature/root.x/thigh_stretch.r",
  shinR = "Armature/root.x/thigh_stretch.r/leg_stretch.r",
  footR = "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r",
  toesR = "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r/toes_01.r",
}

-- 角度按角色前方 +Z、上方 +Y、左侧 +X 的语义轴记录；
-- 运行时把语义轴换算到每根骨骼父节点的静止坐标系，避免不同骨骼局部轴差异。
local CLIPS = {
  Idle = {
    duration = 3.2,
    loop = true,
    keys = {
      { t = 0.0, pose = { hips = {0, 0, 0}, spine1 = {1.5, 0, 0}, spine2 = {0.8, 0, 0}, spine3 = {0.5, 0, 0}, neck = {-1, 0, 0}, head = {-1, 0, 0}, shoulderL = {0, 0, 0}, upperArmL = {3, 0, 3}, foreArmL = {-6, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, 0, 0}, upperArmR = {3, 0, -3}, foreArmR = {-6, 0, 0}, handR = {0, 0, 0}, thighL = {0.7, 0, 0}, shinL = {2.6, 0, 0}, footL = {-3.3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.7, 0, 0}, shinR = {2.6, 0, 0}, footR = {-1.9, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.8, pose = { hips = {0, 2, 0}, spine1 = {2.5, 0, 0}, spine2 = {1.4, 0, 0}, spine3 = {0.8, 0, 0}, neck = {-1.5, 1.5, 0}, head = {-2, 3, 0}, shoulderL = {0, 0, 1}, upperArmL = {4.5, 0, 3}, foreArmL = {-7, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, 0, -1}, upperArmR = {4.5, 0, -3}, foreArmR = {-7, 0, 0}, handR = {0, 0, 0}, thighL = {0.8, 0, 0}, shinL = {2.8, 0, 0}, footL = {-3.6, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.8, 0, 0}, shinR = {2.8, 0, 0}, footR = {-2, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 1.6, pose = { hips = {0, 0, 0}, spine1 = {1.2, 0, 0}, spine2 = {0.8, 0, 0}, spine3 = {0.5, 0, 0}, neck = {-1.3, 0, 0}, head = {-1, 0, 0}, shoulderL = {0, 0, 0}, upperArmL = {3, 0, 3}, foreArmL = {-6, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, 0, 0}, upperArmR = {3, 0, -3}, foreArmR = {-6, 0, 0}, handR = {0, 0, 0}, thighL = {0.7, 0, 0}, shinL = {2.6, 0, 0}, footL = {-3.3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.7, 0, 0}, shinR = {2.6, 0, 0}, footR = {-1.9, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 2.4, pose = { hips = {0, -2, 0}, spine1 = {1.2, 0, 0}, spine2 = {0.6, 0, 0}, spine3 = {0.3, 0, 0}, neck = {-0.5, -1.5, 0}, head = {0, -4, 0}, shoulderL = {0, 0, -1}, upperArmL = {2, 0, 3}, foreArmL = {-5, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, 0, 1}, upperArmR = {2, 0, -3}, foreArmR = {-5, 0, 0}, handR = {0, 0, 0}, thighL = {0.6, 0, 0}, shinL = {2.4, 0, 0}, footL = {-3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.6, 0, 0}, shinR = {2.4, 0, 0}, footR = {-1.8, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 3.2, pose = { hips = {0, 0, 0}, spine1 = {1.5, 0, 0}, spine2 = {0.8, 0, 0}, spine3 = {0.5, 0, 0}, neck = {-1, 0, 0}, head = {-1, 0, 0}, shoulderL = {0, 0, 0}, upperArmL = {3, 0, 3}, foreArmL = {-6, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, 0, 0}, upperArmR = {3, 0, -3}, foreArmR = {-6, 0, 0}, handR = {0, 0, 0}, thighL = {0.7, 0, 0}, shinL = {2.6, 0, 0}, footL = {-3.3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.7, 0, 0}, shinR = {2.6, 0, 0}, footR = {-1.9, 0, 0}, toesR = {0, 0, 0}, } },
    },
  },
  Walk = {
    duration = 0.72,
    loop = true,
    keys = {
      { t = 0.0, pose = { hips = {0, 7, 0}, spine1 = {14, 0, 0}, spine2 = {6.3, -2.45, 0}, spine3 = {3.5, -7.35, 0}, neck = {-7, -2.4, 0}, head = {-5.6, -4.27, 0}, shoulderL = {0, 0, -2}, upperArmL = {44, 0, 3}, foreArmL = {-38, 0, 0}, handL = {-6, 0, 0}, shoulderR = {0, 0, 2}, upperArmR = {-44, 0, -3}, foreArmR = {-53, 0, 0}, handR = {-6, 0, 0}, thighL = {-40, 0, 0}, shinL = {10, 0, 0}, footL = {27, 0, 0}, toesL = {0, 0, 0}, thighR = {40, 0, 0}, shinR = {10, 0, 0}, footR = {-47, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.09, pose = { hips = {0, 4.95, 0}, spine1 = {14, 0, 0}, spine2 = {6.3, -1.73, 0}, spine3 = {3.5, -5.2, 0}, neck = {-7, -2.04, 0}, head = {-5.6, -4.13, 0}, shoulderL = {0, 0, -2}, upperArmL = {31.11, 0, 3}, foreArmL = {-38, 0, 0}, handL = {-6, 0, 0}, shoulderR = {0, 0, 2}, upperArmR = {-31.11, 0, -3}, foreArmR = {-48.61, 0, 0}, handR = {-6, 0, 0}, thighL = {-28.28, 0, 0}, shinL = {10, 0, 0}, footL = {16.16, 0, 0}, toesL = {4.24, 0, 0}, thighR = {28.28, 0, 0}, shinR = {53.84, 0, 0}, footR = {-41.11, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.18, pose = { hips = {0, 0, 0}, spine1 = {14, 0, 0}, spine2 = {6.3, 0, 0}, spine3 = {3.5, 0, 0}, neck = {-7, -0.49, 0}, head = {-5.6, -1.56, 0}, shoulderL = {0, 0, -2}, upperArmL = {0, 0, 3}, foreArmL = {-38, 0, 0}, handL = {-6, 0, 0}, shoulderR = {0, 0, 2}, upperArmR = {0, 0, -3}, foreArmR = {-38, 0, 0}, handR = {-6, 0, 0}, thighL = {0, 0, 0}, shinL = {10, 0, 0}, footL = {-10, 0, 0}, toesL = {6, 0, 0}, thighR = {0, 0, 0}, shinR = {72, 0, 0}, footR = {-25, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.27, pose = { hips = {0, -4.95, 0}, spine1 = {14, 0, 0}, spine2 = {6.3, 1.73, 0}, spine3 = {3.5, 5.2, 0}, neck = {-7, 1.35, 0}, head = {-5.6, 1.92, 0}, shoulderL = {0, 0, -2}, upperArmL = {-31.11, 0, 3}, foreArmL = {-48.61, 0, 0}, handL = {-6, 0, 0}, shoulderR = {0, 0, 2}, upperArmR = {31.11, 0, -3}, foreArmR = {-38, 0, 0}, handR = {-6, 0, 0}, thighL = {28.28, 0, 0}, shinL = {10, 0, 0}, footL = {-36.16, 0, 0}, toesL = {4.24, 0, 0}, thighR = {-28.28, 0, 0}, shinR = {53.84, 0, 0}, footR = {-25.78, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.36, pose = { hips = {0, -7, 0}, spine1 = {14, 0, 0}, spine2 = {6.3, 2.45, 0}, spine3 = {3.5, 7.35, 0}, neck = {-7, 2.4, 0}, head = {-5.6, 4.27, 0}, shoulderL = {0, 0, -2}, upperArmL = {-44, 0, 3}, foreArmL = {-53, 0, 0}, handL = {-6, 0, 0}, shoulderR = {0, 0, 2}, upperArmR = {44, 0, -3}, foreArmR = {-38, 0, 0}, handR = {-6, 0, 0}, thighL = {40, 0, 0}, shinL = {10, 0, 0}, footL = {-47, 0, 0}, toesL = {0, 0, 0}, thighR = {-40, 0, 0}, shinR = {10, 0, 0}, footR = {27, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.45, pose = { hips = {0, -4.95, 0}, spine1 = {14, 0, 0}, spine2 = {6.3, 1.73, 0}, spine3 = {3.5, 5.2, 0}, neck = {-7, 2.04, 0}, head = {-5.6, 4.13, 0}, shoulderL = {0, 0, -2}, upperArmL = {-31.11, 0, 3}, foreArmL = {-48.61, 0, 0}, handL = {-6, 0, 0}, shoulderR = {0, 0, 2}, upperArmR = {31.11, 0, -3}, foreArmR = {-38, 0, 0}, handR = {-6, 0, 0}, thighL = {28.28, 0, 0}, shinL = {53.84, 0, 0}, footL = {-41.11, 0, 0}, toesL = {0, 0, 0}, thighR = {-28.28, 0, 0}, shinR = {10, 0, 0}, footR = {16.16, 0, 0}, toesR = {4.24, 0, 0}, } },
      { t = 0.54, pose = { hips = {0, 0, 0}, spine1 = {14, 0, 0}, spine2 = {6.3, 0, 0}, spine3 = {3.5, 0, 0}, neck = {-7, 0.49, 0}, head = {-5.6, 1.56, 0}, shoulderL = {0, 0, -2}, upperArmL = {0, 0, 3}, foreArmL = {-38, 0, 0}, handL = {-6, 0, 0}, shoulderR = {0, 0, 2}, upperArmR = {0, 0, -3}, foreArmR = {-38, 0, 0}, handR = {-6, 0, 0}, thighL = {0, 0, 0}, shinL = {72, 0, 0}, footL = {-25, 0, 0}, toesL = {0, 0, 0}, thighR = {0, 0, 0}, shinR = {10, 0, 0}, footR = {-10, 0, 0}, toesR = {6, 0, 0}, } },
      { t = 0.63, pose = { hips = {0, 4.95, 0}, spine1 = {14, 0, 0}, spine2 = {6.3, -1.73, 0}, spine3 = {3.5, -5.2, 0}, neck = {-7, -1.35, 0}, head = {-5.6, -1.92, 0}, shoulderL = {0, 0, -2}, upperArmL = {31.11, 0, 3}, foreArmL = {-38, 0, 0}, handL = {-6, 0, 0}, shoulderR = {0, 0, 2}, upperArmR = {-31.11, 0, -3}, foreArmR = {-48.61, 0, 0}, handR = {-6, 0, 0}, thighL = {-28.28, 0, 0}, shinL = {53.84, 0, 0}, footL = {-25.78, 0, 0}, toesL = {0, 0, 0}, thighR = {28.28, 0, 0}, shinR = {10, 0, 0}, footR = {-36.16, 0, 0}, toesR = {4.24, 0, 0}, } },
      { t = 0.72, pose = { hips = {0, 7, 0}, spine1 = {14, 0, 0}, spine2 = {6.3, -2.45, 0}, spine3 = {3.5, -7.35, 0}, neck = {-7, -2.4, 0}, head = {-5.6, -4.27, 0}, shoulderL = {0, 0, -2}, upperArmL = {44, 0, 3}, foreArmL = {-38, 0, 0}, handL = {-6, 0, 0}, shoulderR = {0, 0, 2}, upperArmR = {-44, 0, -3}, foreArmR = {-53, 0, 0}, handR = {-6, 0, 0}, thighL = {-40, 0, 0}, shinL = {10, 0, 0}, footL = {27, 0, 0}, toesL = {0, 0, 0}, thighR = {40, 0, 0}, shinR = {10, 0, 0}, footR = {-47, 0, 0}, toesR = {0, 0, 0}, } },
    },
  },
  Attack = {
    duration = 1.05,
    loop = false,
    autoReturn = true,
    hitTime = 0.4,
    keys = {
      { t = 0.0, pose = { hips = {0, 0, 0}, spine1 = {1.5, 0, 0}, spine2 = {0.8, 0, 0}, spine3 = {0.5, 0, 0}, neck = {-1, 0, 0}, head = {-1, 0, 0}, shoulderL = {0, 0, 0}, upperArmL = {3, 0, 3}, foreArmL = {-6, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, 0, 0}, upperArmR = {3, 0, -3}, foreArmR = {-6, 0, 0}, handR = {0, 0, 0}, thighL = {0.7, 0, 0}, shinL = {2.6, 0, 0}, footL = {-3.3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.7, 0, 0}, shinR = {2.6, 0, 0}, footR = {-1.9, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.1, pose = { hips = {0, -3, 0}, spine1 = {-2.5, 0, 0}, spine2 = {-1.2, -1, 0}, spine3 = {-0.5, -4, 0}, neck = {1, 2, 0}, head = {2, 6, 0}, shoulderL = {0, 0, 0}, upperArmL = {-5, 0, 7}, foreArmL = {-16, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, -4, 0}, upperArmR = {31, -3, -11}, foreArmR = {-20, 0, -3}, handR = {-8, 0, 0}, thighL = {-3, 0, 0}, shinL = {8, 0, 0}, footL = {-5, 0, 0}, toesL = {0, 0, 0}, thighR = {3, 0, 0}, shinR = {9, 0, 0}, footR = {-12, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.26, pose = { hips = {0, -8, 0}, spine1 = {-7.5, 0, 0}, spine2 = {-5.2, -5, 0}, spine3 = {-2.5, -10, 0}, neck = {2, 4, 0}, head = {4, 10, 0}, shoulderL = {0, 0, 0}, upperArmL = {-3, 0, 7}, foreArmL = {-16, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, -6, 0}, upperArmR = {58, -6, -17}, foreArmR = {-30, 0, -6}, handR = {-18, 0, 0}, thighL = {-4, 0, 0}, shinL = {14, 0, 0}, footL = {-10, 0, 0}, toesL = {0, 0, 0}, thighR = {4, 0, 0}, shinR = {16, 0, 0}, footR = {-20, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.4, pose = { hips = {0, 6, 0}, spine1 = {9.5, 0, 0}, spine2 = {5.8, 9, 0}, spine3 = {3.5, 16, 0}, neck = {-6, -5, 0}, head = {-4, -9, 0}, shoulderL = {0, -4, 0}, upperArmL = {31, 0, -1}, foreArmL = {-14, 0, 0}, handL = {-6, 0, 0}, shoulderR = {0, 10, 0}, upperArmR = {-79, 6, 7}, foreArmR = {-40, 0, 4}, handR = {28, 0, 0}, thighL = {-6, 0, 0}, shinL = {8, 0, 0}, footL = {-2, 0, 0}, toesL = {0, 0, 0}, thighR = {12, 0, 0}, shinR = {10, 0, 0}, footR = {-22, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.52, pose = { hips = {0, 7, 0}, spine1 = {11.5, 0, 0}, spine2 = {6.8, 12, 0}, spine3 = {4.5, 20, 0}, neck = {-7, -6, 0}, head = {-5, -10, 0}, shoulderL = {0, -5, 0}, upperArmL = {38, 0, 1}, foreArmL = {-10, 0, 0}, handL = {-4, 0, 0}, shoulderR = {0, 12, 0}, upperArmR = {-95, 8, 13}, foreArmR = {-24, 0, 0}, handR = {12, 0, 0}, thighL = {-6, 0, 0}, shinL = {8, 0, 0}, footL = {-2, 0, 0}, toesL = {0, 0, 0}, thighR = {12, 0, 0}, shinR = {10, 0, 0}, footR = {-22, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.76, pose = { hips = {0, 2, 0}, spine1 = {4.5, 0, 0}, spine2 = {2.8, 4, 0}, spine3 = {1.5, 6, 0}, neck = {-3, -2, 0}, head = {-2, -3, 0}, shoulderL = {0, -1, 0}, upperArmL = {13, 0, 1}, foreArmL = {-12, 0, 0}, handL = {-2, 0, 0}, shoulderR = {0, 4, 0}, upperArmR = {-17, 2, 1}, foreArmR = {-16, 0, 0}, handR = {4, 0, 0}, thighL = {-2, 0, 0}, shinL = {5, 0, 0}, footL = {-3, 0, 0}, toesL = {0, 0, 0}, thighR = {4, 0, 0}, shinR = {6, 0, 0}, footR = {-10, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 1.05, pose = { hips = {0, 0, 0}, spine1 = {1.5, 0, 0}, spine2 = {0.8, 0, 0}, spine3 = {0.5, 0, 0}, neck = {-1, 0, 0}, head = {-1, 0, 0}, shoulderL = {0, 0, 0}, upperArmL = {3, 0, 3}, foreArmL = {-6, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, 0, 0}, upperArmR = {3, 0, -3}, foreArmR = {-6, 0, 0}, handR = {0, 0, 0}, thighL = {0.7, 0, 0}, shinL = {2.6, 0, 0}, footL = {-3.3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.7, 0, 0}, shinR = {2.6, 0, 0}, footR = {-1.9, 0, 0}, toesR = {0, 0, 0}, } },
    },
  },
  Hit = {
    duration = 0.55,
    loop = false,
    autoReturn = true,
    keys = {
      { t = 0.0, pose = { hips = {0, 0, 0}, spine1 = {1.5, 0, 0}, spine2 = {0.8, 0, 0}, spine3 = {0.5, 0, 0}, neck = {-1, 0, 0}, head = {-1, 0, 0}, shoulderL = {0, 0, 0}, upperArmL = {3, 0, 3}, foreArmL = {-6, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, 0, 0}, upperArmR = {3, 0, -3}, foreArmR = {-6, 0, 0}, handR = {0, 0, 0}, thighL = {0.7, 0, 0}, shinL = {2.6, 0, 0}, footL = {-3.3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.7, 0, 0}, shinR = {2.6, 0, 0}, footR = {-1.9, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.06, pose = { hips = {0, -4, 0}, spine1 = {-8.5, 0, 0}, spine2 = {-6.2, 3, 0}, spine3 = {-4.5, -4, 0}, neck = {5, 0, 0}, head = {13, -5, 0}, shoulderL = {0, 0, 3}, upperArmL = {21, 0, 9}, foreArmL = {-14, 0, 0}, handL = {4, 0, 0}, shoulderR = {0, 0, -3}, upperArmR = {21, 0, -9}, foreArmR = {-14, 0, 0}, handR = {4, 0, 0}, thighL = {0.7, 0, 0}, shinL = {2.6, 0, 0}, footL = {-3.3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.7, 0, 0}, shinR = {2.6, 0, 0}, footR = {-1.9, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.16, pose = { hips = {0, -6, 0}, spine1 = {-12.5, 0, 0}, spine2 = {-8.2, 5, 0}, spine3 = {-5.5, -6, 0}, neck = {7, 0, 0}, head = {17, -8, 0}, shoulderL = {0, 0, 4}, upperArmL = {27, 0, 11}, foreArmL = {-16, 0, 0}, handL = {6, 0, 0}, shoulderR = {0, 0, -4}, upperArmR = {27, 0, -11}, foreArmR = {-16, 0, 0}, handR = {6, 0, 0}, thighL = {0.7, 0, 0}, shinL = {2.6, 0, 0}, footL = {-3.3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.7, 0, 0}, shinR = {2.6, 0, 0}, footR = {-1.9, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.3, pose = { hips = {0, 2, 0}, spine1 = {5.5, 0, 0}, spine2 = {2.8, 2, 0}, spine3 = {1.5, 2, 0}, neck = {-3, 0, 0}, head = {-3, -2, 0}, shoulderL = {0, 0, 0}, upperArmL = {9, 0, 5}, foreArmL = {-13, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, 0, 0}, upperArmR = {9, 0, -5}, foreArmR = {-13, 0, 0}, handR = {0, 0, 0}, thighL = {0.7, 0, 0}, shinL = {2.6, 0, 0}, footL = {-3.3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.7, 0, 0}, shinR = {2.6, 0, 0}, footR = {-1.9, 0, 0}, toesR = {0, 0, 0}, } },
      { t = 0.55, pose = { hips = {0, 0, 0}, spine1 = {1.5, 0, 0}, spine2 = {0.8, 0, 0}, spine3 = {0.5, 0, 0}, neck = {-1, 0, 0}, head = {-1, 0, 0}, shoulderL = {0, 0, 0}, upperArmL = {3, 0, 3}, foreArmL = {-6, 0, 0}, handL = {0, 0, 0}, shoulderR = {0, 0, 0}, upperArmR = {3, 0, -3}, foreArmR = {-6, 0, 0}, handR = {0, 0, 0}, thighL = {0.7, 0, 0}, shinL = {2.6, 0, 0}, footL = {-3.3, 0, 0}, toesL = {0, 0, 0}, thighR = {-0.7, 0, 0}, shinR = {2.6, 0, 0}, footR = {-1.9, 0, 0}, toesR = {0, 0, 0}, } },
    },
  },
}

local bones = {}
local bonesFound = 0
local ready = false
local applied = {}
local fadeFrom = {}
local workPose = {}

local currentName = nil
local currentClip = nil
local clipTime = 0
local playing = false
local looping = false
local clipSpeed = 1
local globalSpeed = 1
local hitFired = false
local fadeLeft = 0
local fadeDuration = 0
local onComplete = nil
local onHit = nil
local hitHandler = nil
local pendingPlay = nil
local autoReturnEnabled = true

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function quatFromAxis(axis, degrees)
  if math.abs(degrees) < 0.0001 then return Quaternion(0, 0, 0, 1) end
  local half = degrees * math.pi / 360
  local sine = math.sin(half)
  return Quaternion(axis.x * sine, axis.y * sine, axis.z * sine, math.cos(half))
end

local function quatMul(a, b)
  local ax, ay, az, aw = a.x, a.y, a.z, a.w
  local bx, by, bz, bw = b.x, b.y, b.z, b.w
  return Quaternion(
    aw * bx + ax * bw + ay * bz - az * by,
    aw * by - ax * bz + ay * bw + az * bx,
    aw * bz + ax * by - ay * bx + az * bw,
    aw * bw - ax * bx - ay * by - az * bz
  )
end

local function rotateVector(q, v)
  local qx, qy, qz, qw = q.x, q.y, q.z, q.w
  local tx = 2 * (qy * v.z - qz * v.y)
  local ty = 2 * (qz * v.x - qx * v.z)
  local tz = 2 * (qx * v.y - qy * v.x)
  return Vector3(
    v.x + qw * tx + (qy * tz - qz * ty),
    v.y + qw * ty + (qz * tx - qx * tz),
    v.z + qw * tz + (qx * ty - qy * tx)
  )
end

local function clearPose(dst)
  for i = 1, #BONE_KEYS do
    local value = dst[BONE_KEYS[i]]
    value[1] = 0
    value[2] = 0
    value[3] = 0
  end
end

local function copyPose(src, dst)
  for i = 1, #BONE_KEYS do
    local key = BONE_KEYS[i]
    local from = src[key]
    local to = dst[key]
    to[1] = from[1]
    to[2] = from[2]
    to[3] = from[3]
  end
end

for i = 1, #BONE_KEYS do
  applied[BONE_KEYS[i]] = { 0, 0, 0 }
  fadeFrom[BONE_KEYS[i]] = { 0, 0, 0 }
  workPose[BONE_KEYS[i]] = { 0, 0, 0 }
end

local function sampleClip(clip, time, out)
  local keys = clip.keys
  local count = #keys
  clearPose(out)
  if count == 0 then return end

  local index = 1
  while index < count and time > keys[index + 1].t do
    index = index + 1
  end
  local first = keys[index]
  local second = keys[index + 1]
  if second == nil then second = first end

  local span = second.t - first.t
  local u = 0
  if span > 0.00001 then
    u = (time - first.t) / span
  end
  u = clamp(u, 0, 1)
  local smooth = u * u * (3 - 2 * u)

  for i = 1, #BONE_KEYS do
    local key = BONE_KEYS[i]
    local a = first.pose[key]
    local b = second.pose[key]
    local ax, ay, az = 0, 0, 0
    local bx, by, bz = 0, 0, 0
    if a ~= nil then ax, ay, az = a[1], a[2], a[3] end
    if b ~= nil then bx, by, bz = b[1], b[2], b[3] end
    local target = out[key]
    target[1] = ax + (bx - ax) * smooth
    target[2] = ay + (by - ay) * smooth
    target[3] = az + (bz - az) * smooth
  end
end

local function applyPose(pose)
  for i = 1, #BONE_KEYS do
    local bone = bones[i]
    if bone ~= nil then
      local angle = pose[BONE_KEYS[i]]
      local rotation = quatFromAxis(bone.axisX, angle[1])
      if math.abs(angle[2]) > 0.0001 then
        rotation = quatMul(quatFromAxis(bone.axisY, angle[2]), rotation)
      end
      if math.abs(angle[3]) > 0.0001 then
        rotation = quatMul(quatFromAxis(bone.axisZ, angle[3]), rotation)
      end
      bone.transform.localRotation = quatMul(rotation, bone.rest)
    end
  end
end

local function restoreRest()
  for i = 1, #BONE_KEYS do
    local bone = bones[i]
    if bone ~= nil then
      bone.transform.localRotation = bone.rest
    end
  end
end

local function callSafely(label, callback, ...)
  if callback == nil then return end
  local ok, failure = pcall(callback, ...)
  if not ok then
    logger:error("阶段=" .. label, "原因=" .. tostring(failure))
  end
end

local function finishClip()
  playing = false
  local completion = onComplete
  onComplete = nil
  onHit = nil
  callSafely("动作完成回调", completion)
  if autoReturnEnabled and currentName ~= nil and currentName ~= "Idle" then
    Play("Idle", { fade = 0.2 })
  end
end

local function startClip(name, opts)
  opts = opts or {}
  local clip = CLIPS[name]
  if clip == nil then
    logger:warnOnce("unknown-action", "阶段=播放", "原因=未知动作", tostring(name))
    return false
  end

  copyPose(applied, fadeFrom)
  fadeDuration = opts.fade or 0.18
  fadeDuration = clamp(fadeDuration, 0, 1)
  fadeLeft = fadeDuration

  currentName = name
  currentClip = clip
  clipTime = 0
  playing = true
  looping = opts.loop
  if looping == nil then looping = clip.loop == true end
  clipSpeed = opts.speed or 1
  if clipSpeed <= 0 then clipSpeed = 1 end
  hitFired = false
  onComplete = opts.onComplete
  onHit = opts.onHit
  autoReturnEnabled = opts.autoReturn
  if autoReturnEnabled == nil then autoReturnEnabled = clip.autoReturn == true end
  pendingPlay = nil
  return true
end

-- 播放动作。opts: loop, speed, fade, autoReturn, onComplete, onHit。
function Play(name, opts)
  if name == nil or CLIPS[name] == nil then
    logger:warnOnce("unknown-action", "阶段=播放", "原因=未知动作", tostring(name))
    return false
  end
  if not ready then
    pendingPlay = { name = name, opts = opts }
    return true
  end
  return startClip(name, opts)
end

function Stop(fade)
  return Play("Idle", { fade = fade })
end

-- 运行时调整全局播放倍率；1 为默认速度。
function SetSpeed(value)
  local speed = tonumber(value)
  if speed ~= nil and speed > 0 then
    globalSpeed = clamp(speed, 0.05, 8)
  end
  return globalSpeed
end

function GetAction()
  if currentName ~= nil then return currentName end
  if pendingPlay ~= nil then return pendingPlay.name end
  return "none"
end

function GetRigStatus()
  return bonesFound, #BONE_KEYS
end

function GetActionDuration(name)
  local clip = CLIPS[name or currentName]
  if clip == nil then return 0 end
  return clip.duration
end

function GetHitTime(name)
  local clip = CLIPS[name or currentName]
  if clip == nil or clip.hitTime == nil then return 0 end
  return clip.hitTime
end

function IsPlaying(name)
  if not playing then
    if not ready and pendingPlay ~= nil then
      if name == nil then return true end
      return pendingPlay.name == name
    end
    return false
  end
  if name == nil then return true end
  return currentName == name
end

function RegisterHitHandler(callback)
  hitHandler = callback
end

function ClearHitHandler()
  hitHandler = nil
end

local function setupBones()
  if runtimeScope == nil then return end

  local skeleton = runtimeScope:GetTransformByPath("Armature")
  if skeleton == nil then
    local rootObject = runtimeScope:GetResourceRoot()
    if rootObject ~= nil then skeleton = rootObject.transform end
  end
  if skeleton == nil then skeleton = self.transform end
  if skeleton == nil then
    logger:error("阶段=绑定骨骼", "原因=无法取得骨骼根节点")
    return
  end

  local axisWorldX = skeleton:TransformDirection(Vector3(1, 0, 0))
  local axisWorldY = skeleton:TransformDirection(Vector3(0, 1, 0))
  local axisWorldZ = skeleton:TransformDirection(Vector3(0, 0, 1))

  for i = 1, #BONE_KEYS do
    local key = BONE_KEYS[i]
    local boneTransform, reason = runtimeScope:GetTransformByPath(BONE_PATHS[key])
    if boneTransform == nil then
      logger:warnOnce("bone-missing-" .. key, "阶段=绑定骨骼", "原因=缺少骨骼", key, tostring(reason))
    else
      local parentRotation = Quaternion(0, 0, 0, 1)
      if boneTransform.parent ~= nil then
        parentRotation = boneTransform.parent.rotation
      end
      local inverseParent = Quaternion(-parentRotation.x, -parentRotation.y, -parentRotation.z, parentRotation.w)
      bones[i] = {
        transform = boneTransform,
        rest = boneTransform.localRotation,
        axisX = rotateVector(inverseParent, axisWorldX),
        axisY = rotateVector(inverseParent, axisWorldY),
        axisZ = rotateVector(inverseParent, axisWorldZ),
      }
      bonesFound = bonesFound + 1
    end
  end
  ready = true
  logger:info("阶段=绑定骨骼", "完成", tostring(bonesFound) .. "/" .. tostring(#BONE_KEYS))
  if bonesFound == 0 then
    logger:error("阶段=绑定骨骼", "原因=没有找到任何可驱动骨骼")
  end
end

function Start()
  if runtimeScope == nil then
    logger:error("阶段=初始化", "原因=资源上下文缺失", tostring(runtimeScopeReason))
    return
  end
  globalSpeed = clamp(PlaybackSpeed or 1, 0.05, 8)
  setupBones()
  if not ready or bonesFound == 0 then return end

  if pendingPlay ~= nil then
    local pending = pendingPlay
    startClip(pending.name, pending.opts)
    return
  end
  if AutoIdle ~= false then
    startClip("Idle", { fade = 0 })
  end
end

function Update()
  if not ready or not playing or currentClip == nil then return end

  local dt = clock.deltaTime * globalSpeed * clipSpeed
  if dt <= 0 then return end

  local previous = clipTime
  local nextTime = clipTime + dt
  local duration = currentClip.duration
  local finished = false
  local looped = false

  if looping then
    if nextTime >= duration then
      nextTime = nextTime % duration
      looped = true
      hitFired = false
    end
  elseif nextTime >= duration then
    nextTime = duration
    finished = true
  end

  clipTime = nextTime

  if currentClip.hitTime ~= nil and not hitFired and not finished and not looped then
    local hit = currentClip.hitTime
    if previous < hit and nextTime >= hit then
      hitFired = true
      callSafely("命中回调", onHit)
      callSafely("外部命中回调", hitHandler, currentName)
    end
  end

  sampleClip(currentClip, clipTime, workPose)
  if fadeLeft > 0 then
    local fadeRatio = 1
    if fadeDuration > 0.00001 then
      fadeRatio = 1 - (fadeLeft / fadeDuration)
    end
    fadeRatio = clamp(fadeRatio, 0, 1)
    local smooth = fadeRatio * fadeRatio * (3 - 2 * fadeRatio)
    for i = 1, #BONE_KEYS do
      local key = BONE_KEYS[i]
      local from = fadeFrom[key]
      local target = workPose[key]
      target[1] = from[1] + (target[1] - from[1]) * smooth
      target[2] = from[2] + (target[2] - from[2]) * smooth
      target[3] = from[3] + (target[3] - from[3]) * smooth
    end
    fadeLeft = fadeLeft - dt
  end

  applyPose(workPose)
  copyPose(workPose, applied)

  if finished then
    finishClip()
  end
end

function OnDisable()
  playing = false
  if not ready then return end
  restoreRest()
end

function OnEnable()
  if ready then
    startClip("Idle", { fade = 0 })
  end
end


Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="Idle",walk="Walk",attack="Attack",hit="Hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=Update
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))*.65 -- slower foot cadence only; route speed and combat timing unchanged
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

AnimatedFactories.child=function(root,height)
local Play,SetSpeed,GetAction,GetActionDuration,GetHitTime,GetRigStatus,Start,OnEnable,OnDisable,LateUpdate
local self={transform=root,gameObject=root.gameObject}
local clock={deltaTime=0}
local function lookup(path)
 local direct=root:Find(path); if direct then return direct end
 local name=path:match("[^/]+$")
 local function visit(t)
  if t.name==name then return t end
  for i=0,t.childCount-1 do local found=visit(t:GetChild(i));if found then return found end end
 end
 return visit(root)
end
local boundScope={GetTransformByPath=function(_,p)return lookup(p)end,
 GetResourceRoot=function()return root.gameObject end,
 GetGameObjectByPath=function(_,p)local t=lookup(p);return t and t.gameObject end}
-- 逐骨骼关键帧驱动裂团子体的待机、行走、攻击和受击

local UnityEngine = CS.UnityEngine
local Quaternion = UnityEngine.Quaternion
local Vector3 = UnityEngine.Vector3
local Time = UnityEngine.Time

local RuntimeScope={from=function()return boundScope end}
local Logger = require("official.core.logger")

local runtimeScope, scopeReason = RuntimeScope.from(self)
local logger = Logger.create("child-anim")

-- 骨骼路径来自 inspect_resource_nodes 对 topology/model.glb 的真实检查结果。
local BONE_DEFS = {
  { key = "root", path = "Armature/root.x" },
  { key = "spine1", path = "Armature/root.x/spine_01.x" },
  { key = "spine2", path = "Armature/root.x/spine_01.x/spine_02.x" },
  { key = "spine3", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x" },
  { key = "neck", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x" },
  { key = "head", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/neck.x/head.x" },
  { key = "shoulderL", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l" },
  { key = "armL", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l" },
  { key = "foreL", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l" },
  { key = "handL", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.l/arm_stretch.l/forearm_stretch.l/hand.l" },
  { key = "shoulderR", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r" },
  { key = "armR", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r" },
  { key = "foreR", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r" },
  { key = "handR", path = "Armature/root.x/spine_01.x/spine_02.x/spine_03.x/shoulder.r/arm_stretch.r/forearm_stretch.r/hand.r" },
  { key = "thighL", path = "Armature/root.x/thigh_stretch.l" },
  { key = "kneeL", path = "Armature/root.x/thigh_stretch.l/leg_stretch.l" },
  { key = "footL", path = "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l" },
  { key = "toeL", path = "Armature/root.x/thigh_stretch.l/leg_stretch.l/foot.l/toes_01.l" },
  { key = "thighR", path = "Armature/root.x/thigh_stretch.r" },
  { key = "kneeR", path = "Armature/root.x/thigh_stretch.r/leg_stretch.r" },
  { key = "footR", path = "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r" },
  { key = "toeR", path = "Armature/root.x/thigh_stretch.r/leg_stretch.r/foot.r/toes_01.r" },
}

local TOTAL_BONES = #BONE_DEFS

-- 基础站姿由真实关节轴向校准：大腿/膝盖绕局部 X，脚踝俯仰绕局部 Z。
local BASE = {
  spine1 = { 0, 0, 0 }, spine2 = { 0, 0, 0 }, spine3 = { 0, 0, 0 },
  neck = { 0, 0, 0 }, head = { 0, 0, 0 },
  armL = { -18, 0, 0 }, armR = { -18, 0, 0 },
  foreL = { 0, 0, 10 }, foreR = { 0, 0, -10 },
  thighL = { 0, 0, 0 }, thighR = { 0, 0, 0 },
  kneeL = { 6, 0, 0 }, kneeR = { 6, 0, 0 },
  footL = { 0, 0, 4 }, footR = { 0, 0, -4 },
}

local AXIS_X = Vector3.right
local AXIS_Y = Vector3.up
local AXIS_Z = Vector3.forward

local rig = {}
local applied = {}
local missing = {}
local foundCount = 0
local ready = false
local initialized = false
local skinned = false

local currentName = "idle"
local currentClip = nil
local currentTime = 0
local speed = 1
local transition = nil
local pendingReturn = false

local function copyPose(source)
  local out = {}
  for key, value in pairs(source) do
    out[key] = { value[1], value[2], value[3] }
  end
  return out
end

local function P(overrides)
  local out = copyPose(BASE)
  if overrides ~= nil then
    for key, value in pairs(overrides) do
      out[key] = { value[1], value[2], value[3] }
    end
  end
  return out
end

local function buildClip(duration, loop, hitTime, keys)
  local tracks = {}
  for key in pairs(BASE) do
    tracks[key] = {}
  end
  for index = 1, #keys do
    local time = keys[index][1]
    local pose = keys[index][2]
    for key in pairs(BASE) do
      local value = pose[key] or BASE[key]
      local track = tracks[key]
      track[#track + 1] = { time, value[1], value[2], value[3] }
    end
  end
  return { duration = duration, loop = loop, hitTime = hitTime, tracks = tracks }
end

local IDLE_KEYS = {
  { 0.0, P({}) },
  { 0.6, P({
    spine1 = { 1.0, 1.0, 1.2 }, spine2 = { 0.8, 0.5, 0.6 }, spine3 = { 0.5, 0, 0.3 },
    neck = { -0.3, 0.6, 0.4 }, head = { -0.8, 1.5, 1.0 },
    armL = { -15, 0, 0 }, armR = { -15, 0, 0 },
    foreL = { 0, 0, 13 }, foreR = { 0, 0, -13 },
  }) },
  { 1.2, P({}) },
  { 1.8, P({
    spine1 = { -0.6, -1.0, -1.2 }, spine2 = { -0.5, -0.5, -0.6 }, spine3 = { -0.3, 0, -0.3 },
    neck = { 0.2, -0.6, -0.4 }, head = { 0.5, -1.5, -1.0 },
    armL = { -21, 0, 0 }, armR = { -21, 0, 0 },
    foreL = { 0, 0, 7 }, foreR = { 0, 0, -7 },
  }) },
  { 2.4, P({}) },
}

local WALK_KEYS = {
  { 0.00, P({
    spine1 = { 4, -3, 2 }, spine2 = { 2, -2, -1 }, spine3 = { 1, 0, 1 },
    neck = { 0, 1, -0.5 }, head = { -1, 3, -1 },
    armL = { -8, 0, 0 }, armR = { -28, 0, 0 }, foreL = { 0, 0, 4 }, foreR = { 0, 0, -4 },
    thighL = { -12, 0, 0 }, kneeL = { 14, 0, 0 }, footL = { 0, 0, 2 },
    thighR = { 0, 0, 0 }, kneeR = { 36, 0, 0 }, footR = { 0, 0, -12 },
  }) },
  { 0.12, P({
    spine1 = { 5, 0, 1 }, spine2 = { 2, 0, 0 }, spine3 = { 1, 0, 0 },
    neck = { 0, 0, 0 }, head = { 0, 0, 0 },
    armL = { -20, 0, 0 }, armR = { -16, 0, 0 }, foreL = { 0, 0, 12 }, foreR = { 0, 0, -12 },
    thighL = { -4, 0, 0 }, kneeL = { 6, 0, 0 }, footL = { 0, 0, 2 },
    thighR = { -16, 0, 0 }, kneeR = { 30, 0, 0 }, footR = { 0, 0, -10 },
  }) },
  { 0.25, P({
    spine1 = { 4, 3, -2 }, spine2 = { 2, 2, 1 }, spine3 = { 1, 0, -1 },
    neck = { 0, -1, 0.5 }, head = { -1, -3, 1 },
    armL = { -30, 0, 0 }, armR = { -6, 0, 0 }, foreL = { 0, 0, 18 }, foreR = { 0, 0, -18 },
    thighL = { 12, 0, 0 }, kneeL = { 4, 0, 0 }, footL = { 0, 0, 7 },
    thighR = { -16, 0, 0 }, kneeR = { 18, 0, 0 }, footR = { 0, 0, -6 },
  }) },
  { 0.35, P({
    spine1 = { 5, 0, -1 }, spine2 = { 2, 0, 0 }, spine3 = { 1, 0, 0 },
    neck = { 0, 0, 0 }, head = { 0, 0, 0 },
    armL = { -22, 0, 0 }, armR = { -14, 0, 0 }, foreL = { 0, 0, 10 }, foreR = { 0, 0, -10 },
    thighL = { 16, 0, 0 }, kneeL = { 18, 0, 0 }, footL = { 0, 0, 14 },
    thighR = { -14, 0, 0 }, kneeR = { 16, 0, 0 }, footR = { 0, 0, -4 },
  }) },
  { 0.50, P({
    spine1 = { 4, -3, 2 }, spine2 = { 2, -2, -1 }, spine3 = { 1, 0, 1 },
    neck = { 0, 1, -0.5 }, head = { -1, 3, -1 },
    armL = { -12, 0, 0 }, armR = { -24, 0, 0 }, foreL = { 0, 0, 4 }, foreR = { 0, 0, -4 },
    thighL = { 0, 0, 0 }, kneeL = { 36, 0, 0 }, footL = { 0, 0, 12 },
    thighR = { -12, 0, 0 }, kneeR = { 14, 0, 0 }, footR = { 0, 0, -2 },
  }) },
  { 0.62, P({
    spine1 = { 5, 0, 1 }, spine2 = { 2, 0, 0 }, spine3 = { 1, 0, 0 },
    neck = { 0, 0, 0 }, head = { 0, 0, 0 },
    armL = { -22, 0, 0 }, armR = { -14, 0, 0 }, foreL = { 0, 0, 12 }, foreR = { 0, 0, -12 },
    thighL = { -16, 0, 0 }, kneeL = { 30, 0, 0 }, footL = { 0, 0, 10 },
    thighR = { -4, 0, 0 }, kneeR = { 6, 0, 0 }, footR = { 0, 0, -2 },
  }) },
  { 0.75, P({
    spine1 = { 4, 3, -2 }, spine2 = { 2, 2, 1 }, spine3 = { 1, 0, -1 },
    neck = { 0, -1, 0.5 }, head = { -1, -3, 1 },
    armL = { -30, 0, 0 }, armR = { -6, 0, 0 }, foreL = { 0, 0, 18 }, foreR = { 0, 0, -18 },
    thighL = { -16, 0, 0 }, kneeL = { 18, 0, 0 }, footL = { 0, 0, 6 },
    thighR = { 12, 0, 0 }, kneeR = { 4, 0, 0 }, footR = { 0, 0, -7 },
  }) },
  { 1.00, P({
    spine1 = { 4, -3, 2 }, spine2 = { 2, -2, -1 }, spine3 = { 1, 0, 1 },
    neck = { 0, 1, -0.5 }, head = { -1, 3, -1 },
    armL = { -8, 0, 0 }, armR = { -28, 0, 0 }, foreL = { 0, 0, 4 }, foreR = { 0, 0, -4 },
    thighL = { -12, 0, 0 }, kneeL = { 14, 0, 0 }, footL = { 0, 0, 2 },
    thighR = { 0, 0, 0 }, kneeR = { 36, 0, 0 }, footR = { 0, 0, -12 },
  }) },
}

local ATTACK_KEYS = {
  { 0.00, P({}) },
  { 0.12, P({
    spine1 = { -3, 7, 0 }, spine2 = { -3, 5, 0 }, spine3 = { -2, 3, 0 },
    neck = { -1, -2, 0 }, head = { -4, -5, 0 },
    armL = { -4, 0, 0 }, armR = { -4, 0, 0 }, foreL = { 0, 0, 20 }, foreR = { 0, 0, -20 },
    thighL = { -4, 0, 0 }, kneeL = { 10, 0, 0 }, footL = { 0, 0, 7 },
    thighR = { 2, 0, 0 }, kneeR = { 8, 0, 0 }, footR = { 0, 0, -6 },
  }) },
  { 0.26, P({
    spine1 = { -7, 10, 1 }, spine2 = { -5, 7, 0 }, spine3 = { -3, 4, 0 },
    neck = { -2, -3, 0 }, head = { -7, -7, 2 },
    armL = { 12, 0, 0 }, armR = { 12, 0, 0 }, foreL = { 0, 0, 26 }, foreR = { 0, 0, -26 },
    thighL = { -6, 0, 0 }, kneeL = { 14, 0, 0 }, footL = { 0, 0, 5.5 },
    thighR = { 4, 0, 0 }, kneeR = { 12, 0, 0 }, footR = { 0, 0, -8 },
  }) },
  { 0.34, P({
    spine1 = { 13, -6, -1 }, spine2 = { 8, -4, 0 }, spine3 = { 5, -2, 0 },
    neck = { 3, 2, 0 }, head = { 12, 4, -2 },
    armL = { -40, 0, 0 }, armR = { -40, 0, 0 }, foreL = { 0, 0, 20 }, foreR = { 0, 0, -20 },
    thighL = { -12, 0, 0 }, kneeL = { 16, 0, 0 }, footL = { 0, 0, 4 },
    thighR = { 10, 0, 0 }, kneeR = { 12, 0, 0 }, footR = { 0, 0, -8 },
  }) },
  { 0.42, P({
    spine1 = { 14, -5, 0 }, spine2 = { 9, -3, 0 }, spine3 = { 5, -2, 0 },
    neck = { 3, 1, 0 }, head = { 13, 3, 0 },
    armL = { -44, 0, 0 }, armR = { -44, 0, 0 }, foreL = { 0, 0, 24 }, foreR = { 0, 0, -24 },
    thighL = { -12, 0, 0 }, kneeL = { 16, 0, 0 }, footL = { 0, 0, 4 },
    thighR = { 10, 0, 0 }, kneeR = { 12, 0, 0 }, footR = { 0, 0, -8 },
  }) },
  { 0.58, P({
    spine1 = { 7, -2, 0 }, spine2 = { 4, -1, 0 }, spine3 = { 2, 0, 0 },
    neck = { 1, 0, 0 }, head = { 6, 1, 0 },
    armL = { -30, 0, 0 }, armR = { -30, 0, 0 }, foreL = { 0, 0, 14 }, foreR = { 0, 0, -14 },
    thighL = { -6, 0, 0 }, kneeL = { 10, 0, 0 }, footL = { 0, 0, 6 },
    thighR = { 6, 0, 0 }, kneeR = { 9, 0, 0 }, footR = { 0, 0, -7 },
  }) },
  { 0.74, P({
    spine1 = { 2, 0, 0 }, spine2 = { 1, 0, 0 }, head = { 2, 0, 0 },
    armL = { -22, 0, 0 }, armR = { -22, 0, 0 }, foreL = { 0, 0, 8 }, foreR = { 0, 0, -8 },
  }) },
  { 0.90, P({}) },
}

local HIT_KEYS = {
  { 0.00, P({}) },
  { 0.05, P({
    spine1 = { -7, -6, -3 }, spine2 = { -5, -4, -2 }, spine3 = { -3, -2, -1 },
    neck = { -2, 2, 1 }, head = { -8, 6, 4 },
    armL = { 16, 0, 0 }, armR = { 16, 0, 0 }, foreL = { 0, 0, 24 }, foreR = { 0, 0, -24 },
    thighL = { -6, 0, 0 }, kneeL = { 12, 0, 0 }, footL = { 0, 0, 6 },
    thighR = { 4, 0, 0 }, kneeR = { 10, 0, 0 }, footR = { 0, 0, -7 },
  }) },
  { 0.14, P({
    spine1 = { -12, -9, -4 }, spine2 = { -8, -6, -3 }, spine3 = { -4, -3, -2 },
    neck = { -3, 3, 2 }, head = { -13, 9, 6 },
    armL = { 20, 0, 0 }, armR = { 20, 0, 0 }, foreL = { 0, 0, 28 }, foreR = { 0, 0, -28 },
    thighL = { -10, 0, 0 }, kneeL = { 16, 0, 0 }, footL = { 0, 0, 4 },
    thighR = { 8, 0, 0 }, kneeR = { 14, 0, 0 }, footR = { 0, 0, -8 },
  }) },
  { 0.28, P({
    spine1 = { -4, -3, -1 }, spine2 = { -3, -2, -1 }, spine3 = { -1, 0, 0 },
    neck = { -1, 1, 0 }, head = { -5, 3, 2 },
    armL = { -6, 0, 0 }, armR = { -6, 0, 0 }, foreL = { 0, 0, 18 }, foreR = { 0, 0, -18 },
    thighL = { -4, 0, 0 }, kneeL = { 9, 0, 0 }, footL = { 0, 0, 5 },
    thighR = { 3, 0, 0 }, kneeR = { 8, 0, 0 }, footR = { 0, 0, -6 },
  }) },
  { 0.50, P({}) },
}

local CLIPS = {
  idle = buildClip(2.4, true, nil, IDLE_KEYS),
  walk = buildClip(0.64, true, nil, WALK_KEYS),
  attack = buildClip(0.9, false, 0.34, ATTACK_KEYS),
  hit = buildClip(0.5, false, nil, HIT_KEYS),
}

local function sampleTrack(keys, t)
  local count = #keys
  if count == 0 then return 0, 0, 0 end
  if t <= keys[1][1] then return keys[1][2], keys[1][3], keys[1][4] end
  if t >= keys[count][1] then return keys[count][2], keys[count][3], keys[count][4] end
  for index = 2, count do
    local second = keys[index]
    if t <= second[1] then
      local first = keys[index - 1]
      local span = second[1] - first[1]
      local u = 0
      if span > 0 then u = (t - first[1]) / span end
      u = u * u * (3 - 2 * u)
      local rx = first[2] + (second[2] - first[2]) * u
      local ry = first[3] + (second[3] - first[3]) * u
      local rz = first[4] + (second[4] - first[4]) * u
      return rx, ry, rz
    end
  end
  return keys[count][2], keys[count][3], keys[count][4]
end

local function offsetQuat(rx, ry, rz)
  local qx = Quaternion.AngleAxis(rx, AXIS_X)
  local qy = Quaternion.AngleAxis(ry, AXIS_Y)
  local qz = Quaternion.AngleAxis(rz, AXIS_Z)
  return qx * qy * qz
end

local function snapshotApplied()
  local snapshot = {}
  for key, entry in pairs(rig) do
    snapshot[key] = applied[key] or entry.rest
  end
  return snapshot
end

local function applyAction(name, fade)
  local clip = CLIPS[name]
  if clip == nil then return false end
  local from = nil
  if fade ~= nil and fade > 0 and initialized then
    from = snapshotApplied()
  end
  currentName = name
  currentClip = clip
  currentTime = 0
  pendingReturn = false
  if from ~= nil then
    transition = { from = from, elapsed = 0, duration = fade }
  else
    transition = nil
  end
  logger:info("action", name)
  return true
end

function Play(name, opts)
  if not ready then
    logger:warnOnce("not-ready", "Play ignored: rig not ready")
    return false
  end
  local clip = CLIPS[name]
  if clip == nil then
    logger:warnOnce("unknown-action", "unknown action", tostring(name))
    return false
  end
  local restart = false
  local fade = 0.16
  if opts ~= nil then
    if opts.restart == true then restart = true end
    if type(opts.fade) == "number" then fade = opts.fade end
  end
  if name == currentName and not restart then
    return true
  end
  return applyAction(name, fade)
end

function SetSpeed(value)
  if type(value) ~= "number" or value ~= value then
    return false
  end
  speed = math.max(0.1, math.min(4, value))
  return true
end

function GetAction()
  return currentName
end

function GetActionDuration(name)
  local clip = nil
  if name ~= nil then
    clip = CLIPS[name]
  else
    clip = currentClip
  end
  if clip == nil then return nil end
  return clip.duration / speed
end

function GetHitTime(name)
  local clip = nil
  if name ~= nil then
    clip = CLIPS[name]
  else
    clip = currentClip
  end
  if clip == nil or clip.hitTime == nil then return nil end
  return clip.hitTime / speed
end

function GetRigStatus()
  return {
    ready = ready,
    found = foundCount,
    total = TOTAL_BONES,
    missing = missing,
    skinned = skinned,
    action = currentName,
  }
end

function Start()
  if runtimeScope == nil then
    logger:error("scope-missing", tostring(scopeReason))
    return
  end

  for index = 1, TOTAL_BONES do
    local def = BONE_DEFS[index]
    local bone, reason = runtimeScope:GetTransformByPath(def.path)
    if bone == nil then
      missing[#missing + 1] = def.key
    else
      rig[def.key] = {
        t = bone,
        rest = bone.localRotation,
        restPos = bone.localPosition,
      }
      foundCount = foundCount + 1
    end
  end

  local meshTransform = runtimeScope:GetTransformByPath("Armature/model")
  if meshTransform ~= nil then
    local ok, component = pcall(function()
      return meshTransform.gameObject:GetComponent(typeof(UnityEngine.SkinnedMeshRenderer))
    end)
    skinned = ok and component ~= nil
  end

  ready = foundCount == TOTAL_BONES
  initialized = true

  if not ready then
    logger:error("rig-incomplete", foundCount .. "/" .. TOTAL_BONES, table.concat(missing, ","))
    return
  end

  for key, entry in pairs(rig) do
    applied[key] = entry.rest
  end

  logger:info("rig-ready", foundCount .. "/" .. TOTAL_BONES, "skinned=" .. tostring(skinned))
  applyAction("idle", 0)
end

function OnEnable()
  if initialized and ready then
    for key, entry in pairs(rig) do
      entry.t.localRotation = entry.rest
      applied[key] = entry.rest
    end
    applyAction("idle", 0)
  end
end

function OnDisable()
  if not initialized then return end
  for key, entry in pairs(rig) do
    entry.t.localRotation = entry.rest
    entry.t.localPosition = entry.restPos
    applied[key] = entry.rest
  end
  transition = nil
  pendingReturn = false
  currentTime = 0
end

function LateUpdate()
  if not ready or not initialized or currentClip == nil then return end

  local dt = clock.deltaTime
  currentTime = currentTime + dt * speed

  if currentClip.loop then
    if currentTime >= currentClip.duration then
      currentTime = currentTime % currentClip.duration
    end
  else
    if currentTime >= currentClip.duration then
      currentTime = currentClip.duration
      pendingReturn = true
    end
  end

  local alpha = 1
  if transition ~= nil then
    transition.elapsed = transition.elapsed + dt
    if transition.duration > 0 then
      alpha = math.min(1, transition.elapsed / transition.duration)
    end
    alpha = alpha * alpha * (3 - 2 * alpha)
  end

  for key, entry in pairs(rig) do
    local rx, ry, rz = 0, 0, 0
    local track = currentClip.tracks[key]
    if track ~= nil then
      rx, ry, rz = sampleTrack(track, currentTime)
    end
    local target = entry.rest * offsetQuat(rx, ry, rz)
    local final = target
    if transition ~= nil then
      local from = transition.from[key] or entry.rest
      final = Quaternion.Slerp(from, target, alpha)
    end
    entry.t.localRotation = final
    applied[key] = final
  end

  if transition ~= nil and alpha >= 1 then
    transition = nil
  end

  if pendingReturn then
    pendingReturn = false
    applyAction("idle", 0.18)
  end
end


Start()
if SetSpeed then SetSpeed(1) end
local status,a,b=GetRigStatus()
local valid=false
if type(status)=="table" then valid=status.ready==true and status.ok~=false
elseif type(status)=="boolean" then valid=status
elseif type(status)=="number" then valid=status==a and status>0
elseif type(status)=="string" then valid=type(a)=="number" and a==b and a>0 end
local names={idle="idle",walk="walk",attack="attack",hit="hit"}
local desired="idle"; local rate=1;local walkRate=1
local tick=LateUpdate
local function action()return tostring(GetAction()or""):lower()end
local function play(which,fade)
 return Play(names[which],{restart=true,fade=fade or .12,blend=fade or .12,autoReturn=true})
end
local function update(dt)
 clock.deltaTime=math.max(0,math.min(.1,dt or 0))*rate
 tick()
end
local controlled=false
local controlAge=0
local function locomote()
 if controlled then return end
 local active=action()
 if active~="attack" and active~="hit" then
  rate=desired=="walk"and walkRate or 1
  if active~=desired then play(desired,.16)end
 end
end
return {ready=valid,GetAction=GetAction,GetRigStatus=GetRigStatus,
 SetMotion=function(state,speed)
  desired=state=="idle"and"idle"or"walk"
  walkRate=math.max(.45,math.min(2.2,(speed or 0)/math.max(.3,height*.65)))
  locomote()
 end,
 Attack=function(age,windup)
  if not valid or controlled then return end
  local hit=tonumber(GetHitTime(names.attack))or .5
  if hit<=0 then hit=.5 end
  rate=hit/math.max(.12,windup or .5)
  play("attack",.06)
  local remaining=math.max(0,math.min(age or 0,(GetActionDuration(names.attack)or 1)/rate))
  while remaining>0 do local step=math.min(.05,remaining);update(step);remaining=remaining-step end
 end,
 Hit=function()
  local active=action()
  if active~="attack"and active~="hit"then rate=1.4;play("hit",.04)end
 end,
 Control=function(active)
  if active and not controlled then
   controlled=true;controlAge=0;rate=1.4;play("hit",.04)
  elseif not active and controlled then
   controlled=false;rate=desired=="walk"and walkRate or 1;play(desired,.12)
  end
 end,
 Update=function(dt)
  if controlled then
   local step=math.min(math.max(0,dt or 0),math.max(0,.12-controlAge))
   if step>0 then update(step);controlAge=controlAge+step end
  else update(dt);locomote()end
 end,
 Reset=function()
  if OnDisable then OnDisable()end
  controlled=false;controlAge=0
  desired="idle";rate=1;walkRate=1
  if SetSpeed then SetSpeed(1)end
  play("idle",0)
 end}

end

-- Skin renderer bounds include animation padding; use actual bind-pose vertices for feet and scale.
local sourceMeshBounds={}
local function exactSourceBounds(source,skins)
 local key=source:GetInstanceID();if sourceMeshBounds[key]then return sourceMeshBounds[key]end
 local lo=U.Vector3(math.huge,math.huge,math.huge);local hi=U.Vector3(-math.huge,-math.huge,-math.huge)
 local count=0
 for i=0,skins.Length-1 do
  local skin=skins[i];local baked=U.Mesh()
  local ok,err=pcall(function()
   skin:BakeMesh(baked)
   local vertices=baked.vertices
   for j=0,vertices.Length-1 do
    local v=source.transform:InverseTransformPoint(skin.transform:TransformPoint(vertices[j]))
    lo=U.Vector3(math.min(lo.x,v.x),math.min(lo.y,v.y),math.min(lo.z,v.z))
    hi=U.Vector3(math.max(hi.x,v.x),math.max(hi.y,v.y),math.max(hi.z,v.z));count=count+1
   end
  end)
  U.Object.Destroy(baked)
  if not ok then logger:warnOnce("skin-bounds-"..key,"脚底测量失败",tostring(err))end
 end
 if count==0 then return nil end
 local result={min=lo,max=hi,center=U.Vector3((lo.x+hi.x)*.5,(lo.y+hi.y)*.5,(lo.z+hi.z)*.5)}
 sourceMeshBounds[key]=result;return result
end
local function cloneRig(parent,kind)
 local spec=sources[kind]
 local source=U.GameObject.Find(spec and spec[1]or "")
 if not source then return nil end
 local skins=source:GetComponentsInChildren(typeof(U.SkinnedMeshRenderer),true)
 if skins.Length==0 then return nil end
 local go=U.GameObject("View_Enemy_"..kind.."_Rig");go.transform:SetParent(parent,false)
 local body=U.GameObject("RigBody");body.transform:SetParent(go.transform,false)
 local map={};local sourceRoot=source.transform
 local function copyTree(src,dst)
  map[src:GetInstanceID()]=dst
  for i=0,src.childCount-1 do
   local child=src:GetChild(i);local fresh=U.GameObject(child.name);local tr=fresh.transform
   tr:SetParent(dst,false);tr.localPosition=child.localPosition;tr.localRotation=child.localRotation;tr.localScale=child.localScale
   copyTree(child,tr)
  end
 end
 copyTree(sourceRoot,body.transform)
 local bounds=skins[0].bounds
 for i=1,skins.Length-1 do bounds:Encapsulate(skins[i].bounds)end
 for i=0,skins.Length-1 do
  local src=skins[i];local dst=map[src.transform:GetInstanceID()]
  local mesh=dst.gameObject:AddComponent(typeof(U.SkinnedMeshRenderer))
  mesh.sharedMesh=src.sharedMesh;mesh.sharedMaterials=src.sharedMaterials
  local bones=src.bones;local mapped=CS.System.Array.CreateInstance(typeof(U.Transform),bones.Length)
  for j=0,bones.Length-1 do mapped[j]=map[bones[j]:GetInstanceID()]end
  mesh.bones=mapped;mesh.rootBone=src.rootBone and map[src.rootBone:GetInstanceID()]or body.transform
  mesh.localBounds=src.localBounds;mesh.updateWhenOffscreen=true
 end
 local exact=exactSourceBounds(source,skins)
 local lo=exact and exact.min or sourceRoot:InverseTransformPoint(bounds.min)
 local hi=exact and exact.max or sourceRoot:InverseTransformPoint(bounds.max)
 local height=math.max(.01,math.abs(hi.y-lo.y));local scale=((sources[kind]and sources[kind][2])or 1.8)/height
 local c=exact and exact.center or sourceRoot:InverseTransformPoint(bounds.center)
 body.transform.localScale=U.Vector3(scale,scale,scale)
 body.transform.localPosition=U.Vector3(-c.x*scale,-(c.y-height*.5)*scale,-c.z*scale)
 local contacts={}
 local function bindContact(t)
  if t.name=="foot.l"or t.name=="foot.r"then
   local point=sourceRoot:InverseTransformPoint(t.position)
   local sole=t:InverseTransformPoint(sourceRoot:TransformPoint(U.Vector3(point.x,lo.y,point.z)))
   contacts[#contacts+1]={bone=map[t:GetInstanceID()],point=sole}
  end
  for j=0,t.childCount-1 do bindContact(t:GetChild(j))end
 end
 bindContact(sourceRoot)
 local baseBody=body.transform.localPosition
 local motion=AnimatedFactories[kind](body.transform,(sources[kind]and sources[kind][2])or 1.8)
 if not motion.ready then logger:warnOnce("animated-rig-"..kind,"动画骨骼未就绪",kind);U.Object.Destroy(go);return nil end
 motion.Ground=function()
  body.transform.localPosition=baseBody
  local lift=-math.huge
  for _,contact in ipairs(contacts)do
   local point=parent:InverseTransformPoint(contact.bone:TransformPoint(contact.point))
   lift=math.max(lift,ground(point.x,point.z)+.008-point.y)
  end
  if lift~=-math.huge then
   local limit=((sources[kind]and sources[kind][2])or 1.8)*.35
   lift=math.max(-limit,math.min(limit,lift))
   body.transform.localPosition=U.Vector3(baseBody.x,baseBody.y+lift,baseBody.z)
  end
 end
 logger:info("monster rig ready",kind,"bones",skins[0].bones.Length)
 return go,scale,motion
end

local function cloneRift(parent,kind)
 local source=riftMeshSource(kind);if not source or not source.sharedMesh then return nil end
 local sourceRenderer=source.gameObject:GetComponent(typeof(U.MeshRenderer));if not sourceRenderer then return nil end
 local go=U.GameObject("View_Enemy_basic_Rift")
 go.transform:SetParent(parent,false)
 local body=U.GameObject("Body");body.transform:SetParent(go.transform,false)
 body:AddComponent(typeof(U.MeshFilter)).sharedMesh=source.sharedMesh
 local renderer=body:AddComponent(typeof(U.MeshRenderer));renderer.sharedMaterials=sourceRenderer.sharedMaterials
 local bounds=source.sharedMesh.bounds;local height=(sources[kind] and sources[kind][2]) or 1.8;local scale=height/math.max(.01,bounds.size.y)
 body.transform.localScale=U.Vector3(scale,scale,scale)
 body.transform.localPosition=U.Vector3(-bounds.center.x*scale,-bounds.min.y*scale,-bounds.center.z*scale)
 return go,scale
end

local function acquire(kind,id)
  local bucket=V.pool[kind]
  local v=bucket and table.remove(bucket) or nil
  if v and not alive(v.go) then v=nil end
  if not v then
    local go,riftScale,rigMotion
    if kind=="basic"or sources[kind] then go,riftScale,rigMotion=cloneRig(V.root.transform,kind)end
    if not go and (kind=="basic" or sources[kind]) then go,riftScale=cloneRift(V.root.transform,kind)end
    if not go then go=clone("Enemy_"..kind,V.root.transform)end
    if not go then return nil end
    local t=go.transform
    v={go=go,kind=kind,body=find(t,"Body"),head=find(t,"Head"),pulse=find(t,"Body/Pulse"),limbs={},back=clone("HP_Back",V.root.transform),fill=clone("HP_Fill",V.root.transform),rootFx=clone("Status_Root",V.root.transform),burnFx=clone("Status_Burn",V.root.transform)}
    v.riftScale=riftScale;v.rigMotion=rigMotion
    v.bodyBase=v.body and xyz(v.body.localPosition) or {x=0,y=.6,z=0}
    v.headBase=v.head and xyz(v.head.localPosition) or {x=0,y=1,z=.2}
    local a=find(t,"HealthAnchor") v.barHeight=riftScale and (((sources[kind] and sources[kind][2]) or 1.8)+.25) or (a and a.localPosition.y or 1.4)
    for _,name in ipairs(LIMBS) do table.insert(v.limbs,find(t,name) or false) end
  end
  v.id=id v.dead=nil v.deathSound=nil v.lastCast=0 v.first=true v.lastAttack=-100 v.lastHit=-100 v.lastX=nil v.lastZ=nil v.movingUntil=-1 v.renderX=nil v.renderZ=nil v.renderAngle=nil v.gait=0
  if v.rigMotion then v.rigMotion.Reset()end
  v.go:SetActive(true)
  v.go.transform.localScale=U.Vector3(1,1,1)
  return v
end
local function clear()
  for _,v in pairs(V.units) do destroy(v.go) destroy(v.back) destroy(v.fill) destroy(v.rootFx) destroy(v.burnFx) end
  for _,bucket in pairs(V.pool) do for _,v in ipairs(bucket) do destroy(v.go) destroy(v.back) destroy(v.fill) destroy(v.rootFx) destroy(v.burnFx) end end
  V.units={} V.pool={} V.sounds={} V.retired={} V.primed=false V.soundAt=-1 V.soundCount=0
end
-- A local visual pose only: authoritative snapshot positions are never modified.
local function smoothPose(v,x,z,angle,dead,dt)
  local alpha=1-math.exp(-12*math.max(0,tonumber(dt) or 0))
  local fresh=v.renderX==nil or v.renderZ==nil
  local large=not fresh and (x-v.renderX)^2+(z-v.renderZ)^2>16
  if fresh or (large and not v.dead) then
    v.renderX=x v.renderZ=z v.renderAngle=angle
  elseif not dead then
    v.renderX=v.renderX+(x-v.renderX)*alpha
    v.renderZ=v.renderZ+(z-v.renderZ)*alpha
    local delta=(angle-(v.renderAngle or angle)+180)%360-180
    v.renderAngle=(v.renderAngle or angle)+delta*alpha
  end
  return v.renderX,v.renderZ,v.renderAngle or angle,alpha
end
local function updateUnit(v,e,t,dt)
  local x,z=tonumber(e.x) or 0,tonumber(e.z) or 0
  local angle=tonumber(e.angle) or 0
  local hp=tonumber(e.hp) or 0
  local deadAt=tonumber(e.deadAt) or 0
  local dying=v.dead~=nil or hp<=0 or (deadAt>0 and deadAt<=t)
  if v.lastX and ((x-v.lastX)^2+(z-v.lastZ)^2)>.00005 and not dying then v.movingUntil=t+.32 end
  v.lastX=x v.lastZ=z v.lastAngle=angle
  local oldX,oldZ=v.renderX,v.renderZ
  local alpha
  if (tonumber(e.rootUntil)or 0)>t then v.renderX=x;v.renderZ=z end
  x,z,angle,alpha=smoothPose(v,x,z,angle,dying,dt)
  local visualMoved=oldX~=nil and ((x-oldX)^2+(z-oldZ)^2)>.000001
  local rootTime=tonumber(e.rootUntil) or 0
  local walking=(visualMoved or t<v.movingUntil) and t>=rootTime and not dying
  v.gait=(v.gait or 0)+((walking and 1 or 0)-(v.gait or 0))*alpha
  local wave=math.sin(t*(e.type=="runner" and 19 or 10)+(tonumber(e.id) or #tostring(e.id))*.7)*v.gait
  local at=tonumber(e.attackAt) or -100
  if v.first then
    v.attackFloor=at v.hitFloor=tonumber(e.hitAt) or -100 v.lastAttack=at
    v.lastCast=type(e.cast)=="table" and (tonumber(e.cast.untilTime) or 0) or 0
    if (tonumber(e.hp) or 0)<=0 or e.deadAt then v.deathSound=true end
    v.first=false
  end
  local age=t-at
  local swing=(at>v.attackFloor and age>=0 and age<.55) and math.sin(age/.55*math.pi) or 0
  local hit=t-(tonumber(e.hitAt) or -100)
  local recoil=((tonumber(e.hitAt) or -100)>v.hitFloor and hit>=0 and hit<.18) and (1-hit/.18) or 0
  local hitAt=tonumber(e.hitAt)or -100
  if not dying and hitAt>math.max(v.lastHit or -100,v.hitFloor or -100)and hit>=0 and hit<.24 then
   -- Ordinary damage keeps locomotion; hit reactions belong to immobilizing control.
   v.lastHit=hitAt
  end
  if dying then v.dead=v.dead or (deadAt>0 and deadAt or t) end
  if at>v.lastAttack and age>=0 and age<.35 then
    play("attack-"..(e.type=="child" and "basic" or e.type),t,e.type=="boss",x,z)
    if v.rigMotion then v.rigMotion.Attack(age,type(e.cast)=="table" and ((tonumber(e.cast.untilTime) or at+.35)-at) or .35)end
    v.lastAttack=at
  end
  if type(e.cast)=="table" and e.type=="boss" then
    local untilTime=tonumber(e.cast.untilTime) or 0
    if untilTime>t and untilTime>v.lastCast then play("boss-warning",t,true,x,z) v.lastCast=untilTime end
  end
  if v.dead then
    if not v.deathSound and t-v.dead<.35 then play(e.type=="boss" and "boss-death" or ((e.type=="guard" or e.type=="caster") and "death-large" or "death-small"),t,e.type=="boss",x,z) v.deathSound=true end
    local a=math.max(0,math.min(1,(t-v.dead)/.75))
    v.go.transform.localPosition=U.Vector3(x,ground(x,z)+.04-a*.25,z)
    v.go.transform.localEulerAngles=U.Vector3(a*82,angle,a*15)
    local sc=1-a*.35 v.go.transform.localScale=U.Vector3(sc,sc,sc)
    for _,go in ipairs({v.back,v.fill,v.rootFx,v.burnFx}) do if alive(go) then go:SetActive(false) end end
    return a<1
  end
  v.deathSound=nil
  if v.rigMotion then
   local speed=oldX and math.sqrt((x-oldX)^2+(z-oldZ)^2)/math.max(.001,dt)or 0
   v.rigMotion.SetMotion(walking and (e.type=="runner"and"run"or"walk")or"idle",speed)
   v.rigMotion.Control(rootTime>t)
   v.rigMotion.Update(dt)
  end
  v.go.transform.localPosition=U.Vector3(x,ground(x,z)+.008,z)
  v.go.transform.localEulerAngles=U.Vector3(0,angle,0)
  if v.rigMotion and v.rigMotion.Ground then v.rigMotion.Ground()end
  if v.body and not v.rigMotion then v.body.localPosition=U.Vector3(v.bodyBase.x,v.bodyBase.y+math.abs(wave)*.035-swing*.05,v.bodyBase.z+swing*.11) v.body.localEulerAngles=U.Vector3(-swing*12+recoil*9,0,wave*2) end
  if v.riftScale and v.body and not v.rigMotion then
   local k=v.riftScale
   local breath=math.sin(t*2.6)*.009*(1-v.gait)
   v.body.localScale=U.Vector3(k*(1+swing*.05+recoil*.035),k*(1+breath-swing*.035-recoil*.025),k*(1+swing*.04))
   v.body.localPosition=U.Vector3(v.bodyBase.x,v.bodyBase.y+math.abs(wave)*.045,v.bodyBase.z+swing*.20-recoil*.07)
   v.body.localEulerAngles=U.Vector3(swing*16-recoil*10,0,wave*2.5)
  end
  if v.head then v.head.localPosition=U.Vector3(v.headBase.x,v.headBase.y+math.abs(wave)*.025,v.headBase.z) v.head.localEulerAngles=U.Vector3(-swing*17+recoil*14,math.sin(t*1.8)*2,0) end
  if v.pulse then local p=1+math.sin(t*4)*.06+swing*.18+recoil*.25 v.pulse.localScale=U.Vector3(p,p,p) end
  for i,limb in ipairs(v.limbs) do if limb then limb.localEulerAngles=U.Vector3(wave*((i==1 or i==4) and 19 or -19),0,swing*((i<3) and 12 or -3)) end end
  local ratio=math.max(0,math.min(1,hp/math.max(1,tonumber(e.maxHp) or hp)))
  local width=e.type=="boss" and 2.1 or ((e.type=="guard" or e.type=="caster") and 1.3 or (v.riftScale and 1.15 or .82))
  if alive(v.back) then v.back:SetActive(false) v.back.transform.localPosition=U.Vector3(x,ground(x,z)+v.barHeight+.08,z) v.back.transform.localScale=U.Vector3(width,1,1) end
  if alive(v.fill) then v.fill:SetActive(false) v.fill.transform.localPosition=U.Vector3(x-width*(1-ratio)*.5,ground(x,z)+v.barHeight+.12,z) v.fill.transform.localScale=U.Vector3(width*ratio,1,1) end
  if alive(v.rootFx) then v.rootFx:SetActive(false) end
  if alive(v.burnFx) then v.burnFx:SetActive(false) end
  return true
end
function Start()
  if not resourceRoot or not scope then logger:warnOnce("scope","敌人视觉未就绪",scopeReason) return end
  for _,kind in ipairs(KINDS) do local name="Enemy_"..kind local go=scope:FindGameObject("ModelRoot/"..name) V.templates[name]=go if alive(go) then go:SetActive(false) end end
  for _,name in ipairs({"HP_Back","HP_Fill","Status_Root","Status_Burn"}) do local go=scope:FindGameObject("ModelRoot/"..name) V.templates[name]=go if alive(go) then go:SetActive(false) end end
  local h=host()
  if h and type(h.RegisterResource)=="function" then V.entry=h.RegisterResource(resourceRoot,"module-foes",{tags={"foes","visual"},events={},options={resourceId="module-foes"}}) end
  V.started=true
end
function Update()
  if not V.started then return end
  local h=host() if not h then return end
  local s=h.GetRenderState() if type(s)~="table" then return end
  local arena=type(h.GetArenaRoot)=="function" and h.GetArenaRoot() or nil
  if not arena then return end
  if not alive(V.root) then V.root=U.GameObject("CrystalDefenseEnemyViews") V.root.transform:SetParent(arena,false) end
  if V.round~=s.round then clear() V.round=s.round end
  updateAudio(h,arena)
  local t=presentationTime(h,s) local current={}
  for id,e in pairs(s.enemies or {}) do
    local key=tostring(id) current[key]=true
    local v=V.units[key]
    if v and v.kind~=e.type then releaseUnit(v) V.units[key]=nil v=nil end
    if not v and not V.retired[key] then v=acquire(e.type or "basic",key) V.units[key]=v end
    if v then local keep=updateUnit(v,e,t,U.Time.deltaTime) if not keep then releaseUnit(v) V.units[key]=nil V.retired[key]=true end end
  end
  for key in pairs(V.retired) do if not current[key] then V.retired[key]=nil end end
  for key,v in pairs(V.units) do
    if not current[key] then
      v.dead=v.dead or t
      local keep=updateUnit(v,{id=key,type=v.kind,x=v.lastX or 0,z=v.lastZ or 0,hp=0,angle=v.lastAngle or 0},t,U.Time.deltaTime)
      if not keep then releaseUnit(v) V.units[key]=nil end
    end
  end
  V.primed=true
end
function DebugVisuals()
  local count=0 local pool=0 for _ in pairs(V.units) do count=count+1 end for _,b in pairs(V.pool) do pool=pool+#b end
  return {units=count,pooled=pool,round=V.round,started=V.started,volume=V.volume,audioReady=V.audioReady==true,riftSource=alive(V.riftSource)}
end
function OnDisable()
  clear() destroy(V.root) V.root=nil
  local h=host() if h and V.entry and type(h.UnregisterResource)=="function" then h.UnregisterResource(V.entry) end V.entry=nil
end
function OnDestroy() OnDisable() end