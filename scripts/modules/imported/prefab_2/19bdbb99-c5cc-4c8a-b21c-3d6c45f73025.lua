---@id c655f3ea-1549-4550-8cc5-eafc323e2d00
---@referenceName ms-hero-timeline.lua
-- 英雄武器攻击时间轴：只提供每一帧的握持目标、武器朝向、躯干扭转和特效窗口。
-- 这些数值使用“肩到手的距离比例”与人物局部轴表达，不依赖具体骨架尺寸。
-- 动作时长单位为秒；t 为 0..1 的归一化时间。
---@displayName 英雄武器动作时间轴

local TIMELINES={
melee={
attack={duration=0.52,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.16,hand={0.6,0.35,-0.28},aim={0.75,0.6,-0.15},spine=26,weight=1,target=0,lean=-9},
{t=0.205,hand={0.65,0.15,0.22},aim={0.85,0.1,0.55},spine=18,weight=1,target=0,lean=0},
{t=0.23,hand={0.05,-0.08,0.9},aim={0.05,-0.12,1},spine=-16,weight=1,target=0,lean=0},
{t=0.31,hand={-0.5,-0.25,0.3},aim={-0.85,-0.35,0.2},spine=-32,weight=1,target=0,lean=0},
{t=0.42,hand={0.1,-0.15,0.45},aim={0.2,-0.2,1},spine=-8,weight=0.5,target=0,lean=0},
{t=0.52,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
},
skill2={duration=0.365,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.12,hand={0.5,-0.25,-0.15},aim={1,0,-0.2},spine=-38,weight=1,target=0,lean=16},
{t=0.18,hand={0.75,-0.1,0.3},aim={1,0,0.35},spine=-15,weight=1,target=0,lean=10},
{t=0.22,hand={0.1,-0.1,0.9},aim={0.1,0,1},spine=36,weight=1,target=0,lean=0},
{t=0.28,hand={-0.55,-0.1,0.2},aim={-1,0,0.2},spine=65,weight=1,target=0,lean=0},
{t=0.365,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
},
skill1={duration=0.35,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.08,hand={0.2,0.15,0.45},aim={0,0.7,0.7},spine=8,weight=1,target=0,lean=-5},
{t=0.2,hand={0.15,0.65,0.22},aim={0,1,0.1},spine=0,weight=1,target=0,lean=0},
{t=0.28,hand={0.15,0.7,0.15},aim={0,1,0},spine=0,weight=1,target=0,lean=0},
{t=0.35,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
},
dash={duration=0.3,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.065,hand={0.1,-0.28,0.35},aim={0,-0.4,1},spine=0,weight=1,target=0,lean=22},
{t=0.085,hand={0.25,-0.25,-0.2},aim={0,-0.3,-1},spine=0,weight=1,target=0,lean=16},
{t=0.22,hand={0.25,-0.25,-0.1},aim={0,-0.3,-1},spine=0,weight=1,target=0,lean=10},
{t=0.3,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
},
},
ranged={
attack={duration=0.365,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.1,hand={0.2,0.13,0.65},aim={0,0,1},spine=10,weight=1,target=1,lean=0},
{t=0.175,hand={0.22,0.16,0.68},aim={0,0,1},spine=13,weight=1,target=1,lean=0},
{t=0.2,hand={0.18,0.1,0.49},aim={0,0.08,1},spine=3,weight=1,target=1,lean=0},
{t=0.26,hand={0.2,0.12,0.63},aim={0,0,1},spine=6,weight=1,target=1,lean=0},
{t=0.365,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
flash={start=0.18,duration=0.05},
},
skill2={duration=0.5,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.1,hand={0.24,0.15,0.55},aim={0,0,1},spine=15,weight=1,target=1,lean=-5},
{t=0.19,hand={0.25,0.16,0.66},aim={0,0,1},spine=21,weight=1,target=1,lean=0},
{t=0.22,hand={0.15,0.05,0.43},aim={0,0.08,1},spine=-5,weight=1,target=1,lean=0},
{t=0.34,hand={0.2,0.1,0.6},aim={0,0,1},spine=2,weight=1,target=1,lean=0},
{t=0.5,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
flash={start=0.2,duration=0.07},
},
skill1={duration=0.9,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.17,hand={0.25,0.35,0.55},aim={0,0.6,0.7},spine=10,weight=1,target=0,lean=0},
{t=0.38,hand={0.2,0.55,0.6},aim={0,0.9,0.35},spine=2,weight=1,target=0,lean=-10},
{t=0.5,hand={0.15,0.4,0.4},aim={0,0.8,0.5},spine=-7,weight=1,target=0,lean=0},
{t=0.65,hand={0.2,0.25,0.5},aim={0,0.6,0.7},spine=0,weight=0.6,target=0,lean=0},
{t=0.9,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
flash={start=0.38,duration=0.08},
},
dash={duration=0.3,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.065,hand={0.1,-0.28,0.35},aim={0,-0.4,1},spine=0,weight=1,target=0,lean=22},
{t=0.085,hand={0.25,-0.25,-0.2},aim={0,-0.3,-1},spine=0,weight=1,target=0,lean=16},
{t=0.22,hand={0.25,-0.25,-0.1},aim={0,-0.3,-1},spine=0,weight=1,target=0,lean=10},
{t=0.3,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
},
},
mage={
attack={duration=0.4,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.1,hand={0.25,0.35,0.3},aim={0,1,0.2},spine=8,weight=1,target=0,lean=-5},
{t=0.22,hand={0.2,0.45,0.4},aim={0,0.9,0.35},spine=5,weight=1,target=0,lean=0},
{t=0.28,hand={0.15,0.1,0.85},aim={0,0,1},spine=-12,weight=1,target=1,lean=0},
{t=0.32,hand={0.15,0.08,0.75},aim={0,0.1,1},spine=-8,weight=1,target=1,lean=0},
{t=0.4,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
flash={start=0.28,duration=0.06},
glow={start=0.02,duration=0.26},
},
skill2={duration=0.6,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.16,hand={0.2,0.55,0.2},aim={0,1,0},spine=12,weight=1,target=0,lean=-10},
{t=0.34,hand={0.15,0.65,0.1},aim={0,1,0},spine=10,weight=1,target=0,lean=0},
{t=0.4,hand={0.15,0.4,0.55},aim={0,0.6,0.8},spine=0,weight=1,target=0,lean=0},
{t=0.48,hand={0.1,-0.1,0.9},aim={0,-0.3,1},spine=-20,weight=1,target=1,lean=8},
{t=0.6,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
flash={start=0.48,duration=0.06},
glow={start=0.02,duration=0.45999999999999996},
},
skill1={duration=0.9,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.2,hand={0.2,0.4,0.25},aim={0,1,0.1},spine=12,weight=1,target=0,lean=-9},
{t=0.5,hand={0.1,0.75,0.1},aim={0,1,0},spine=0,weight=1,target=0,lean=-12},
{t=0.68,hand={0.2,0.05,0.85},aim={0,0.1,1},spine=-18,weight=1,target=1,lean=10},
{t=0.9,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
flash={start=0.65,duration=0.12},
glow={start=0.02,duration=0.63},
},
dash={duration=0.3,keys={
{t=0,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
{t=0.065,hand={0.1,-0.28,0.35},aim={0,-0.4,1},spine=0,weight=1,target=0,lean=22},
{t=0.085,hand={0.25,-0.25,-0.2},aim={0,-0.3,-1},spine=0,weight=1,target=0,lean=16},
{t=0.22,hand={0.25,-0.25,-0.1},aim={0,-0.3,-1},spine=0,weight=1,target=0,lean=10},
{t=0.3,hand={0.25,-0.2,0.35},aim={0,0,1},spine=0,weight=0,target=0,lean=0},
},
glow={start=0.02,duration=0.06},
},
},
}
local function clamp01(value)
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

local function smoothstep(value)
  local t = clamp01(value)
  return t * t * (3 - 2 * t)
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function lerpVec(a, b, t)
  return {
    lerp(a[1], b[1], t),
    lerp(a[2], b[2], t),
    lerp(a[3], b[3], t),
  }
end

local function normalizeVec(value)
  local x = value[1]
  local y = value[2]
  local z = value[3]
  local length = math.sqrt(x * x + y * y + z * z)
  if length < 1e-6 then
    return { 0, 0, 1 }
  end
  return { x / length, y / length, z / length }
end

local function effectProgress(effect, t)
  if effect == nil then return 0 end
  local start = effect.start or 0
  local duration = effect.duration or 0
  if duration <= 0 or t < start or t > start + duration then return 0 end
  return clamp01((t - start) / duration)
end

local function buildSample(timeline, t, hand, aim, spine, weight, targetBlend, lean)
  local glowPhase = effectProgress(timeline.glow, t)
  local glow = 0
  if glowPhase > 0 and glowPhase < 1 then
    glow = math.sin(math.pi * glowPhase)
  elseif glowPhase >= 1 then
    glow = 0
  end
  return {
    hand = hand,
    aim = aim,
    spine = spine,
    lean = lean or 0,
    weight = weight,
    targetBlend = targetBlend,
    glow = glow,
    flash = effectProgress(timeline.flash, t) > 0,
  }
end

function GetTimeline(className, attackKind)
  local classTable = TIMELINES[className]
  if classTable == nil then return nil end
  return classTable[attackKind]
end

function Sample(timeline, t)
  if timeline == nil or timeline.keys == nil or #timeline.keys == 0 then return nil end

  local keys = timeline.keys
  local value = clamp01(t) * timeline.duration
  local first = keys[1]
  local last = keys[#keys]

  if value <= first.t then
    return buildSample(timeline, value, first.hand, normalizeVec(first.aim), first.spine, first.weight, first.target or 0,first.lean or 0)
  end
  if value >= last.t then
    return buildSample(timeline, value, last.hand, normalizeVec(last.aim), last.spine, last.weight, last.target or 0,last.lean or 0)
  end

  for index = 1, #keys - 1 do
    local a = keys[index]
    local b = keys[index + 1]
    if value >= a.t and value <= b.t then
      local span = math.max(1e-5, b.t - a.t)
      local u = smoothstep((value - a.t) / span)
      return buildSample(
        timeline,
        value,
        lerpVec(a.hand, b.hand, u),
        normalizeVec(lerpVec(a.aim, b.aim, u)),
        lerp(a.spine, b.spine, u),
        lerp(a.weight, b.weight, u),
        lerp(a.target or 0, b.target or 0, u),
        lerp(a.lean or 0,b.lean or 0,u)
      )
    end
  end

  return buildSample(timeline, value, last.hand, normalizeVec(last.aim), last.spine, last.weight, last.target or 0,last.lean or 0)
end