---@id bcb04299-a888-425f-ab67-a43f667ed9c8
---@referenceName ms-preview.lua
---@assetRef eyJhc3NldElkIjoiMTE2MDg1NTgyMzQ2MjYiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvNzNkaW41emZhdHg0OGV2ci5nbGIiLCJyZWZlcmVuY2VOYW1lIjoibXMtcHJldmlldy5sdWEifQ
-- 按一次按钮播放一段短促的战斗表现预览，不自动循环。
---@displayName 战斗表现预览编排
---@start
---@var PreviewVolume:number=0.7
---@name 预览音量
---@desc 预览音效的相对音量
---@group 预览
---@end

local Logger = require("official.core.logger")
local RuntimeScope = require("official.core.runtime_scope")

local UnityEngine = CS.UnityEngine
local Time = CS.UnityEngine.Time

local logger = Logger.create("vfx-v2-choreography")
local runtimeScope = RuntimeScope.from(self)

local MODEL_ROOT = "晶界守卫 战斗表现素材V2"
local PREVIEW_DURATION = 2.15
local NODE_NAMES = {
  "V2_Arrow",
  "V2_LeafArrow",
  "V2_Cannonball",
  "V2_Meteor",
  "V2_Spark",
  "V2_Smoke",
  "V2_Flame",
  "V2_Rune",
  "V2_Orb",
  "V2_Leaf",
}

local groups = {}
local base = {}
local audioScript = nil
local playing = false
local startTime = 0
local cueIndex = 1

local CUES = {
  { time = 0.00, name = "v2-bow-release" },
  { time = 0.30, name = "v2-arrow-hit" },
  { time = 0.42, name = "v2-cannon-fire" },
  { time = 0.55, name = "v2-meteor-fall" },
  { time = 0.90, name = "v2-cannon-explode" },
  { time = 0.95, name = "v2-magic-burst" },
  { time = 1.05, name = "v2-meteor-impact" },
  { time = 1.20, name = "v2-leaf-whoosh" },
}

local function clamp01(value)
  if value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
end

local function easeOutCubic(value)
  local inverse = 1 - value
  return 1 - inverse * inverse * inverse
end

local function easeInCubic(value)
  return value * value * value
end

local function easeInOut(value)
  if value < 0.5 then
    return 4 * value * value * value
  end
  local inverse = -2 * value + 2
  return 1 - inverse * inverse * inverse * 0.5
end

local function captureNode(name)
  if runtimeScope == nil then
    return
  end
  local transform = runtimeScope:GetTransformByPath(MODEL_ROOT .. "/" .. name)
  if transform == nil then
    return
  end
  local position = transform.localPosition
  local rotation = transform.localEulerAngles
  local scale = transform.localScale
  groups[name] = transform
  base[name] = {
    px = position.x,
    py = position.y,
    pz = position.z,
    rx = rotation.x,
    ry = rotation.y,
    rz = rotation.z,
    sx = scale.x,
    sy = scale.y,
    sz = scale.z,
  }
end

local function resetAll()
  for index = 1, #NODE_NAMES do
    local name = NODE_NAMES[index]
    local transform = groups[name]
    local origin = base[name]
    if transform ~= nil and origin ~= nil then
      transform.localPosition = UnityEngine.Vector3(origin.px, origin.py, origin.pz)
      transform.localEulerAngles = UnityEngine.Vector3(origin.rx, origin.ry, origin.rz)
      transform.localScale = UnityEngine.Vector3(origin.sx, origin.sy, origin.sz)
    end
  end
end

local function setNode(name, px, py, pz, rx, ry, rz, sx, sy, sz)
  local transform = groups[name]
  if transform == nil then
    return
  end
  transform.localPosition = UnityEngine.Vector3(px, py, pz)
  transform.localEulerAngles = UnityEngine.Vector3(rx, ry, rz)
  transform.localScale = UnityEngine.Vector3(sx, sy, sz)
end

local function playCue(name)
  if audioScript == nil and runtimeScope ~= nil then
    audioScript = runtimeScope:GetScript("ms-audio.lua")
  end
  if audioScript == nil or type(audioScript.PlaySound) ~= "function" then
    return
  end
  audioScript.PlaySound(name, PreviewVolume)
end

function Start()
  if runtimeScope == nil then
    logger:warnOnce("scope-missing", "preview choreography cannot resolve runtime scope")
    return
  end
  for index = 1, #NODE_NAMES do
    captureNode(NODE_NAMES[index])
  end
  if groups["V2_Arrow"] == nil then
    logger:warnOnce("nodes-missing", "preview nodes are incomplete")
  end
  audioScript = runtimeScope:GetScript("ms-audio.lua")
end

function PlayPreview()
  if playing or groups["V2_Arrow"] == nil then
    return
  end
  resetAll()
  playing = true
  startTime = Time.time
  cueIndex = 1
end

function Update()
  if not playing then
    return
  end
  local elapsed = Time.time - startTime

  while cueIndex <= #CUES and elapsed >= CUES[cueIndex].time do
    playCue(CUES[cueIndex].name)
    cueIndex = cueIndex + 1
  end

  if elapsed >= PREVIEW_DURATION then
    resetAll()
    playing = false
    return
  end

  local origin = base["V2_Arrow"]
  if origin ~= nil and elapsed <= 0.85 then
    local u = clamp01(elapsed / 0.85)
    local distance = 1.55 * easeOutCubic(u)
    local baseYRad = math.rad(origin.ry)
    local dx = math.sin(baseYRad) * distance
    local dz = math.cos(baseYRad) * distance
    local dy = 0.12 * math.sin(math.pi * u)
    setNode("V2_Arrow", origin.px + dx, origin.py + dy, origin.pz + dz, origin.rx, origin.ry, origin.rz, 1, 1, 1)
  end

  origin = base["V2_LeafArrow"]
  if origin ~= nil and elapsed >= 0.12 and elapsed <= 0.95 then
    local u = clamp01((elapsed - 0.12) / 0.83)
    local distance = 1.4 * easeOutCubic(u)
    local baseYRad = math.rad(origin.ry)
    local dx = math.sin(baseYRad) * distance
    local dz = math.cos(baseYRad) * distance
    local dy = 0.18 * math.sin(math.pi * u)
    setNode("V2_LeafArrow", origin.px + dx, origin.py + dy, origin.pz + dz, origin.rx, origin.ry, origin.rz, 1, 1, 1)
  end

  origin = base["V2_Cannonball"]
  if origin ~= nil and elapsed >= 0.05 and elapsed <= 0.95 then
    local u = clamp01((elapsed - 0.05) / 0.9)
    local distance = 1.2 * easeInOut(u)
    local dy = 0.05 * math.sin(math.pi * u)
    local spin = 720 * u
    setNode("V2_Cannonball", origin.px, origin.py + dy, origin.pz + distance, origin.rx + spin, origin.ry, origin.rz, 1, 1, 1)
  end

  origin = base["V2_Meteor"]
  if origin ~= nil and elapsed >= 0.35 and elapsed <= 1.15 then
    local u = clamp01((elapsed - 0.35) / 0.8)
    local drop = 2.0 * (1 - easeInCubic(u))
    local spin = 1.2 * u
    local bump = 1 + 0.08 * math.sin(math.pi * u)
    setNode("V2_Meteor", origin.px, origin.py + drop, origin.pz, origin.rx, origin.ry + 90 * u, origin.rz, bump, bump, bump)
  end

  origin = base["V2_Spark"]
  if origin ~= nil and elapsed >= 0.5 and elapsed <= 0.9 then
    local u = clamp01((elapsed - 0.5) / 0.4)
    local pulse = 0.12 + 1.35 * math.sin(math.pi * u)
    if pulse < 0.05 then
      pulse = 0.05
    end
    setNode("V2_Spark", origin.px, origin.py, origin.pz, origin.rx, origin.ry, origin.rz + 45 * u, pulse, pulse, pulse)
  end

  origin = base["V2_Smoke"]
  if origin ~= nil and elapsed >= 0.55 and elapsed <= 1.55 then
    local u = clamp01((elapsed - 0.55) / 1.0)
    local size = 0.35 + 0.95 * easeOutCubic(u)
    setNode("V2_Smoke", origin.px, origin.py + 0.28 * u, origin.pz, origin.rx, origin.ry + 18 * u, origin.rz + 14 * u, size, size, size)
  end

  origin = base["V2_Flame"]
  if origin ~= nil and elapsed >= 0.6 and elapsed <= 1.7 then
    local flicker = 1 + 0.1 * math.sin(elapsed * 38) + 0.05 * math.sin(elapsed * 61)
    setNode("V2_Flame", origin.px, origin.py + 0.05 * math.sin(elapsed * 7), origin.pz, origin.rx, origin.ry, origin.rz + 3 * math.sin(elapsed * 20), flicker, flicker, flicker)
  end

  origin = base["V2_Rune"]
  if origin ~= nil and elapsed >= 0.65 and elapsed <= 1.6 then
    local u = clamp01((elapsed - 0.65) / 0.95)
    local size = 0.55 + 0.67 * easeOutCubic(u)
    setNode("V2_Rune", origin.px, origin.py, origin.pz, origin.rx, origin.ry + 140 * u, origin.rz, size, size, size)
  end

  origin = base["V2_Orb"]
  if origin ~= nil and elapsed >= 0.75 and elapsed <= 1.85 then
    local u = clamp01((elapsed - 0.75) / 1.1)
    local lift = 0.28 * math.sin(math.pi * u)
    local size = 1 + 0.14 * math.sin(math.pi * u)
    setNode("V2_Orb", origin.px, origin.py + lift, origin.pz, origin.rx, origin.ry + 30 * u, origin.rz, size, size, size)
  end

  origin = base["V2_Leaf"]
  if origin ~= nil and elapsed >= 0.85 and elapsed <= 1.95 then
    local u = clamp01((elapsed - 0.85) / 1.1)
    local angle = u * math.pi * 3.2
    local radius = 0.22 * u
    local dx = math.cos(angle) * radius
    local dz = math.sin(angle) * radius
    local dy = 0.38 * math.sin(math.pi * u)
    setNode("V2_Leaf", origin.px + dx, origin.py + dy, origin.pz + dz, origin.rx, origin.ry + u * 360, origin.rz + u * 720, 1, 1, 1)
  end
end

function OnDisable()
  if playing then
    resetAll()
    playing = false
  end
end