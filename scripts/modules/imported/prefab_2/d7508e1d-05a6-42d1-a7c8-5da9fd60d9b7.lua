---@id 0749d17f-ba8a-4ebc-a661-0b1ddab57fa9
---@referenceName pi-hero-weapon-rig.lua
-- 英雄武器与动作组件：把三件武器刚性挂到角色右手掌，并用人物上半身骨骼驱动攻击。
-- 只负责视觉、握持和动作；不处理伤害、输入、相机、移动或网络权威。
--
-- 已核对的官方接口（当前文档）：
--   actor:CalculatePalmTransform(isLeft) -> position, rotation   -- false 为右手
--   actor:PlayAnimation(clip, callback?, mask?)
--   actor:SetOverrideAnimation(key, clip, callback?)
--   actor:StopAnimation(mask?)
-- 当前 Lua 资源参数类型与文档没有提供玩家 Avatar 的 AnimationClip /
-- RuntimeAnimatorController 获取入口，也没有公开的动作剪辑名列表，因此这里不猜测
-- 动作名；攻击改为在 LateUpdate 中通过 GetBoneTransform 对右上臂、右前臂、右手和
-- 脊柱做程序化姿态。骨骼只在攻击期间被覆盖，待机与原生行走保持完整。
---@displayName 英雄武器与动作
---@start
---@var SwordGripShift:number=0
---@name 剑握柄前后微调
---@desc 沿掌心方向移动剑柄中心，负值向手腕内收（米）
---@group 握持校准
---@var SwordGripPitch:number=0
---@name 剑握持俯仰
---@desc 剑相对手掌坐标系的俯仰校准（度）
---@group 握持校准
---@var SwordGripYaw:number=0
---@name 剑握持偏航
---@desc 剑相对手掌坐标系的偏航校准（度）
---@group 握持校准
---@var SwordGripRoll:number=90
---@name 剑握持翻滚
---@desc 默认 90 度把剑刃转入拳头握持通道并朝前，避免待机时剑尖垂直穿地；按实际手骨可微调
---@group 握持校准
---@var CrossbowGripShift:number=0
---@name 弩握柄前后微调
---@desc 沿掌心方向移动弩柄中心，负值向手腕内收（米）
---@group 握持校准
---@var CrossbowGripPitch:number=0
---@name 弩握持俯仰
---@desc 弩相对手掌坐标系的俯仰校准（度）
---@group 握持校准
---@var CrossbowGripYaw:number=0
---@name 弩握持偏航
---@desc 弩相对手掌坐标系的偏航校准（度）
---@group 握持校准
---@var CrossbowGripRoll:number=0
---@name 弩握持翻滚
---@desc 弩相对手掌坐标系的翻滚校准（度）
---@group 握持校准
---@var StaffGripShift:number=0
---@name 法杖握柄前后微调
---@desc 沿掌心方向移动杖柄中心，负值向手腕内收（米）
---@group 握持校准
---@var StaffGripPitch:number=0
---@name 法杖握持俯仰
---@desc 法杖相对手掌坐标系的俯仰校准（度）
---@group 握持校准
---@var StaffGripYaw:number=0
---@name 法杖握持偏航
---@desc 法杖相对手掌坐标系的偏航校准（度）
---@group 握持校准
---@var StaffGripRoll:number=0
---@name 法杖握持翻滚
---@desc 法杖相对手掌坐标系的翻滚校准（度）
---@group 握持校准
---@var AttackSpeed:number=1
---@name 攻击速度倍率
---@desc 大于 1 更快，小于 1 更慢；动作时长按时间轴除以该值
---@group 动作
---@var TorsoTwistScale:number=1
---@name 躯干扭转强度
---@desc 攻击时胸腔跟随挥砍扭转的倍率
---@group 动作
---@var ShowSourceWeapons:boolean=false
---@name 保留展示武器
---@desc 启动时保留组件根节点上的三件原始展示模型
---@group 动作
---@end

local Logger = require("official.core.logger")
local RuntimeScope = require("official.core.runtime_scope")
local Spawn = require("official.core.spawn")

local UnityEngine = CS.UnityEngine
local Vector3 = UnityEngine.Vector3
local Quaternion = UnityEngine.Quaternion
local Matrix4x4 = UnityEngine.Matrix4x4
local Time = UnityEngine.Time
local HumanBodyBones = UnityEngine.HumanBodyBones
local Animator = UnityEngine.Animator
local Renderer = UnityEngine.Renderer

local logger = Logger.create("hero-weapon-rig")
local runtimeScope, runtimeScopeReason = RuntimeScope.from(self)
local resourceRoot = runtimeScope ~= nil and runtimeScope:GetResourceRoot() or nil

local RESOURCE_ID = "module-hero-weapons"
local RIG_TAG = "hero-weapon-rig"
local EVENT_EQUIP = "HeroWeapon.equip"
local EVENT_ATTACK = "HeroWeapon.attack"
local EVENT_UNEQUIP = "HeroWeapon.unequip"
local TIMELINE_SCRIPT_ID = "ms-hero-timeline.lua"
local DEFAULT_ATTACK_KIND = "attack"
local MAX_AIM_PITCH = math.rad(75)

local VALID_CLASSES = {
  melee = true,
  ranged = true,
  mage = true,
}

local VALID_ATTACKS = {
  dash = true,
  attack = true,
  skill1 = true,
  skill2 = true,
}

local WEAPON_DEFS = {
  melee = {
    sourcePath = "ModelRoot/HeroSword",
    gripPath = "ModelRoot/HeroSword/Grip",
  },
  ranged = {
    sourcePath = "ModelRoot/HeroCrossbow",
    gripPath = "ModelRoot/HeroCrossbow/Grip",
    flashPath = "MuzzleFlash",
  },
  mage = {
    sourcePath = "ModelRoot/HeroStaff",
    gripPath = "ModelRoot/HeroStaff/Grip",
    glowPath = "Head/CrystalGlow",
    flashPath = "Head/CastFlash",
  },
}

local equippedByActor = {}
local timelineScript = nil
local hostScript = nil
local resourceEntry = nil

-- 向量工具全部按分量重建，避免依赖运行时不一定暴露的运算符重载。
local function vAdd(a, b)
  return Vector3(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function vSub(a, b)
  return Vector3(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function vScale(a, scale)
  return Vector3(a.x * scale, a.y * scale, a.z * scale)
end

local function vDot(a, b)
  return a.x * b.x + a.y * b.y + a.z * b.z
end

local function vCross(a, b)
  return Vector3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x
  )
end

local function vLength(a)
  return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end

local function vNormalize(a)
  local length = vLength(a)
  if length < 1e-6 then return Vector3(0, 0, 1) end
  return Vector3(a.x / length, a.y / length, a.z / length)
end

local function vLerp(a, b, t)
  return Vector3(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.z + (b.z - a.z) * t
  )
end

-- 时间轴使用人物局部轴；绕人物 up 旋转 yaw 后再转世界向量。
local function rotateLocalYaw(value, yaw)
  local cosine = math.cos(yaw)
  local sine = math.sin(yaw)
  return {
    value[1] * cosine + value[3] * sine,
    value[2],
    -value[1] * sine + value[3] * cosine,
  }
end

local function clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function isActorAlive(actor)
  if actor == nil then return false end
  local ok, gameObject = pcall(function() return actor.gameObject end)
  return ok and gameObject ~= nil
end

local function actorRoot(actor)
  if not isActorAlive(actor) then return nil end
  return actor.gameObject.transform
end

local function getCalibration(className)
  if className == "melee" then
    return {
      shift = SwordGripShift,
      pitch = SwordGripPitch,
      yaw = SwordGripYaw,
      roll = SwordGripRoll,
    }
  elseif className == "ranged" then
    return {
      shift = CrossbowGripShift,
      pitch = CrossbowGripPitch,
      yaw = CrossbowGripYaw,
      roll = CrossbowGripRoll,
    }
  end
  return {
    shift = StaffGripShift,
    pitch = StaffGripPitch,
    yaw = StaffGripYaw,
    roll = StaffGripRoll,
  }
end

local function buildRig(actor)
  if not isActorAlive(actor) then return nil end

  local animator = actor.gameObject:GetComponentInChildren(typeof(Animator))
  if animator == nil then return nil end

  local ok, bones = pcall(function()
    return {
      upper = animator:GetBoneTransform(HumanBodyBones.RightUpperArm),
      lower = animator:GetBoneTransform(HumanBodyBones.RightLowerArm),
      hand = animator:GetBoneTransform(HumanBodyBones.RightHand),
      spine = animator:GetBoneTransform(HumanBodyBones.Spine),
    }
  end)
  if not ok then return nil end
  if bones.upper == nil or bones.lower == nil or bones.hand == nil then return nil end

  local upperLength = vLength(vSub(bones.lower.position, bones.upper.position))
  local lowerLength = vLength(vSub(bones.hand.position, bones.lower.position))
  if upperLength < 1e-4 or lowerLength < 1e-4 then return nil end

  bones.upperLength = upperLength
  bones.lowerLength = lowerLength
  bones.reach = upperLength + lowerLength
  return bones
end

local function ensureTimelineScript()
  if timelineScript ~= nil then return timelineScript end
  if runtimeScope == nil then return nil end
  timelineScript = runtimeScope:GetScript(TIMELINE_SCRIPT_ID)
  return timelineScript
end

local function enableCopyRenderers(gameObject)
  if gameObject == nil then return end
  local renderers = gameObject:GetComponentsInChildren(typeof(Renderer), true)
  if renderers == nil then return end
  for index = 0, renderers.Length - 1 do
    local renderer = renderers[index]
    if renderer ~= nil then renderer.enabled = true end
  end
end

local function hideSourceWeapons()
  if ShowSourceWeapons then return end
  for _, definition in pairs(WEAPON_DEFS) do
    if definition.sourceGo ~= nil then
      local renderers = definition.sourceGo:GetComponentsInChildren(typeof(Renderer), true)
      if renderers ~= nil then
        for index = 0, renderers.Length - 1 do
          local renderer = renderers[index]
          if renderer ~= nil then renderer.enabled = false end
        end
      end
    end
  end
end

local function setNodeActive(node, active)
  if node == nil or node.gameObject == nil then return end
  node.gameObject:SetActive(active)
end

local function setNodeScale(node, scale)
  if node == nil then return end
  node.localScale = Vector3(scale, scale, scale)
end

local function findNode(weapon, path)
  if weapon == nil or path == nil then return nil end
  return weapon.transform:Find(path)
end

local function restorePose(entry)
 if entry and entry.basePose then
  for bone,rotation in pairs(entry.basePose)do if bone then bone.localRotation=rotation end end
  entry.basePose=nil
 end
end
local function capturePose(entry)
 if not entry.rig then return end
 entry.basePose={}
 for _,key in ipairs({"upper","lower","hand","spine"})do
  local bone=entry.rig[key];if bone then entry.basePose[bone]=bone.localRotation end
 end
end
local function clearAttack(entry)
  if entry == nil then return end
  entry.attack = nil
  setNodeActive(entry.flashNode, false)
  setNodeScale(entry.glowNode, 0.001)
end

local function measureWeapon(weapon)
 local lo={math.huge,math.huge,math.huge};local hi={-math.huge,-math.huge,-math.huge}
 local meshes=weapon:GetComponentsInChildren(typeof(UnityEngine.MeshFilter),true)
 for i=0,meshes.Length-1 do
  local m=meshes[i]
  if m.sharedMesh then
   local b=m.sharedMesh.bounds;local mn=b.min;local mx=b.max
   for x=0,1 do for y=0,1 do for z=0,1 do
    local w=m.transform:TransformPoint(Vector3(x==0 and mn.x or mx.x,y==0 and mn.y or mx.y,z==0 and mn.z or mx.z))
    local q=weapon.transform:InverseTransformPoint(w);local v={q.x,q.y,q.z}
    for k=1,3 do lo[k]=math.min(lo[k],v[k]);hi[k]=math.max(hi[k],v[k])end
   end end end
  end
 end
 return math.max(.01,hi[1]-lo[1],hi[2]-lo[2],hi[3]-lo[3])
end
local function sizeWeapon(entry,parent)
 if not entry.localExtent then entry.localExtent=measureWeapon(entry.weapon)end
 local reach=entry.rig and entry.rig.reach or .7
 local length=entry.className=="mage"and clamp(reach*2.7,1.5,2.4)or(entry.className=="ranged"and clamp(reach*1.3,.7,1.2)or clamp(reach*1.8,1,1.7))
 local f=length*(entry.ultimateScale or 1)/entry.localExtent;local p=parent.lossyScale
 entry.weapon.transform.localScale=Vector3(f/math.max(.0001,math.abs(p.x)),f/math.max(.0001,math.abs(p.y)),f/math.max(.0001,math.abs(p.z)))
end
local function attachToHand(entry)
  if entry == nil or entry.weapon == nil or not isActorAlive(entry.actor) then return false end

  local palmOk, palmPosition, palmRotation = pcall(function()
    return entry.actor:CalculatePalmTransform(false)
  end)
  if not palmOk or palmPosition == nil or palmRotation == nil then
    logger:warnOnce("palm-transform", "CalculatePalmTransform failed; weapon cannot be attached")
    return false
  end

  local calibration = entry.calibration
  local calibrationRotation = Quaternion.Euler(calibration.pitch, calibration.yaw, calibration.roll)
  local calibrationMatrix = Matrix4x4.TRS(
    Vector3(-calibration.shift, 0, 0),
    calibrationRotation,
    Vector3.one
  )
  local gripMatrix = Matrix4x4.TRS(entry.gripPosition, entry.gripRotation, Vector3.one)
  local palmMatrix = Matrix4x4.TRS(palmPosition, palmRotation, Vector3.one)
  local palmToWeapon = calibrationMatrix * gripMatrix.inverse

  local hand = entry.rig ~= nil and entry.rig.hand or nil
  if hand ~= nil then
    entry.weapon.transform:SetParent(hand, false)
    sizeWeapon(entry,hand)
    local desired = palmMatrix * calibrationMatrix * gripMatrix.inverse
    entry.weapon.transform.rotation = desired.rotation
    local scaledGrip = entry.weapon.transform:TransformVector(entry.gripPosition)
    entry.weapon.transform.position = vSub(palmPosition, scaledGrip)
    entry.weaponLocalRotation = entry.weapon.transform.localRotation
    entry.mode = "bone"
  else
    local root = actorRoot(entry.actor)
    if root == nil then return false end
    local worldMatrix = palmMatrix * palmToWeapon
    entry.weapon.transform:SetParent(root, false)
    entry.weapon.transform.rotation = worldMatrix.rotation
    sizeWeapon(entry,root)
    entry.weapon.transform.position = vSub(palmPosition,entry.weapon.transform:TransformVector(entry.gripPosition))
    entry.palmToWeapon = palmToWeapon
    entry.weaponLocalRotation = nil
    entry.mode = "palm"
  end

  entry.flashNode = findNode(entry.weapon, entry.definition.flashPath)
  entry.glowNode = findNode(entry.weapon, entry.definition.glowPath)
  setNodeActive(entry.flashNode, false)
  setNodeScale(entry.glowNode, 0.001)
  return true
end

-- 人形骨架可能比脚本 Start 稍晚就绪；最多重试五次，成功后立刻从掌心降级模式切回手骨绑定。
local function tryBuildRig(entry, now)
  if entry == nil then return false end
  if entry.rig ~= nil then return true end
  if entry.rigRetryCount ~= nil and entry.rigRetryCount >= 5 then return false end
  if entry.nextRigRetry ~= nil and now < entry.nextRigRetry then return false end

  entry.rigRetryCount = (entry.rigRetryCount or 0) + 1
  entry.nextRigRetry = now + 1.0
  entry.rig = buildRig(entry.actor)
  if entry.rig ~= nil and entry.mode == "palm" then
    attachToHand(entry)
  end
  return entry.rig ~= nil
end

local function updatePalmAttachment(entry)
  if entry == nil or entry.weapon == nil or not isActorAlive(entry.actor) then return end
  local palmOk, palmPosition, palmRotation = pcall(function()
    return entry.actor:CalculatePalmTransform(false)
  end)
  if not palmOk or palmPosition == nil or palmRotation == nil then return end
  local palmMatrix = Matrix4x4.TRS(palmPosition, palmRotation, Vector3.one)
  local worldMatrix = palmMatrix * entry.palmToWeapon
  entry.weapon.transform.rotation = worldMatrix.rotation
  entry.weapon.transform.position = vSub(palmPosition,entry.weapon.transform:TransformVector(entry.gripPosition))
end

local function removeActorListener(entry)
  if entry == nil or entry.actor == nil or entry.actorLoadedListener == nil then return end
  pcall(function()
    entry.actor.onActorLoaded:RemoveListener(entry.actorLoadedListener)
  end)
  entry.actorLoadedListener = nil
end

local function unequipActorInternal(actor)
  if actor == nil then return false end
  local entry = equippedByActor[actor]
  if entry == nil then return true end

  equippedByActor[actor] = nil
  removeActorListener(entry)
  restorePose(entry)
  clearAttack(entry)

  if entry.weapon ~= nil then
    local ok, message = pcall(function()
      Spawn.destroy(entry.weapon)
    end)
    if not ok then
      logger:warnOnce("destroy-weapon", "failed to destroy equipped weapon", message)
    end
  end
  return true
end

local function equipActorInternal(actor, className)
  if not isActorAlive(actor) then return false end
  if type(className) ~= "string" or not VALID_CLASSES[className] then return false end

  local existing = equippedByActor[actor]
  if existing ~= nil then
    if existing.className == className then return true end
    unequipActorInternal(actor)
  end

  local definition = WEAPON_DEFS[className]
  if definition == nil or definition.sourcePath == nil then return false end
  if definition.gripPosition == nil or definition.gripRotation == nil then
    logger:warnOnce("grip-missing-" .. className, "grip socket is not available for " .. className)
    return false
  end

  local spawnOk, weapon = pcall(function()
    return Spawn.spawn(self, definition.sourcePath, { networked = false })
  end)
  if not spawnOk or weapon == nil then
    logger:warnOnce("spawn-failed-" .. className, "failed to spawn weapon source " .. className)
    return false
  end

  weapon:SetActive(true)
  enableCopyRenderers(weapon)
  local colliders=weapon:GetComponentsInChildren(typeof(UnityEngine.Collider),true)
  for i=0,colliders.Length-1 do colliders[i].enabled=false end

  local entry = {
    actor = actor,
    className = className,
    definition = definition,
    weapon = weapon,
    gripPosition = definition.gripPosition,
    gripRotation = definition.gripRotation,
    calibration = getCalibration(className),
    rig = buildRig(actor),
    mode = "bone",
  }

  equippedByActor[actor] = entry
  if not attachToHand(entry) then
    equippedByActor[actor] = nil
    pcall(function() Spawn.destroy(weapon) end)
    return false
  end

  if entry.rig ~= nil then
    entry.actorLoadedListener = function()
      -- 监听器绑定在这名 Actor 上，形象切换后重新建立手骨绑定。
      if not isActorAlive(actor) then return end
      local classNameForReload = className
      unequipActorInternal(actor)
      equipActorInternal(actor, classNameForReload)
    end
    pcall(function()
      actor.onActorLoaded:AddListener(entry.actorLoadedListener)
    end)
  end

  logger:info("equipped", className, "actor=" .. tostring(actor.actorID))
  return true
end

local function faceAttack(actor, root, direction)
 if root==nil or direction==nil then return end
 local horizontal=Vector3(direction.x,0,direction.z)
 if vLength(horizontal)<=.01 then return end
 local rotation=Quaternion.LookRotation(horizontal,Vector3.up)
 actor.rotation=rotation
 root.rotation=rotation
end

local function attackActorInternal(actor, className, attackKind, targetPosition)
  if not isActorAlive(actor) then return false end
  if type(className) ~= "string" or not VALID_CLASSES[className] then return false end

  local resolvedKind = attackKind or DEFAULT_ATTACK_KIND
  if type(resolvedKind) ~= "string" or not VALID_ATTACKS[resolvedKind] then return false end

  if not equipActorInternal(actor, className) then return false end
  local entry = equippedByActor[actor]
  if entry == nil or entry.className ~= className then return false end

  local script = ensureTimelineScript()
  if script == nil or type(script.GetTimeline) ~= "function" then
    logger:warnOnce("timeline-missing", "attack timeline helper is not available")
    return false
  end
  local timeline = script.GetTimeline(className, resolvedKind)
  if timeline == nil then
    logger:warnOnce("timeline-" .. className .. "-" .. resolvedKind, "timeline is not defined")
    return false
  end

  local root = actorRoot(actor)
  if root == nil then return false end

  local yawOffset = 0
  local aimWorld = nil
  local facingWorld = nil
  if targetPosition ~= nil and targetPosition.x ~= nil and targetPosition.z ~= nil then
    local delta = vSub(targetPosition, actor.position)
    local horizontal = Vector3(delta.x, 0, delta.z)
    if vLength(horizontal) > 0.01 then
      if resolvedKind~="dash"then
       facingWorld=vNormalize(horizontal)
       faceAttack(actor,root,facingWorld)
      end
      local forwardComponent = vDot(horizontal, root.forward)
      local rightComponent = vDot(horizontal, root.right)
      yawOffset = math.atan(rightComponent, forwardComponent)
    end
    if vLength(delta) > 0.01 then
      aimWorld = vNormalize(delta)
      local aimPitch = math.asin(clamp(aimWorld.y, -1, 1))
      if aimPitch > MAX_AIM_PITCH then
        aimWorld = vNormalize(vLerp(aimWorld, root.forward, 0.5))
      elseif aimPitch < -MAX_AIM_PITCH then
        aimWorld = vNormalize(vLerp(aimWorld, root.forward, 0.5))
      end
    end
  end

  if className == "melee" then
    yawOffset = clamp(yawOffset, -1.35, 1.35)
  end

  local duration = math.max(0.05, timeline.duration / math.max(0.2, AttackSpeed))
  entry.attack = {
    kind = resolvedKind,
    startTime = Time.time,
    duration = duration,
    yawOffset = yawOffset,
    aimWorld = aimWorld,
    facingWorld = facingWorld,
    timeline = timeline,
    sampleScript = script,
  }

  setNodeActive(entry.flashNode, false)
  setNodeScale(entry.glowNode, 0.001)
  return true
end

local function solveArm(rig, target, pole, weight)
  local upper = rig.upper
  local lower = rig.lower
  local hand = rig.hand
  local shoulder = upper.position

  local toTarget = vSub(target, shoulder)
  local distance = vLength(toTarget)
  local minimumReach = math.max(0.02, math.abs(rig.upperLength - rig.lowerLength) + 0.01)
  local maximumReach = (rig.upperLength + rig.lowerLength) * 0.995
  distance = clamp(distance, minimumReach, maximumReach)

  local direction = vNormalize(toTarget)
  local clampedTarget = vAdd(shoulder, vScale(direction, distance))
  local along = (rig.upperLength * rig.upperLength - rig.lowerLength * rig.lowerLength + distance * distance) / (2 * distance)
  local heightSquared = rig.upperLength * rig.upperLength - along * along
  local height = heightSquared > 0 and math.sqrt(heightSquared) or 0

  local perpendicular = vSub(pole, vScale(direction, vDot(pole, direction)))
  if vLength(perpendicular) < 1e-4 then
    perpendicular = vCross(direction, Vector3.up)
    if vLength(perpendicular) < 1e-4 then
      perpendicular = vCross(direction, Vector3.right)
    end
  end

  local elbow = vAdd(vAdd(shoulder, vScale(direction, along)), vScale(vNormalize(perpendicular), height))

  local upperCurrent = upper.rotation
  local lowerCurrentPosition = lower.position
  local upperDelta = Quaternion.FromToRotation(
    vSub(lowerCurrentPosition, shoulder),
    vSub(elbow, shoulder)
  )
  upper.rotation = Quaternion.Slerp(upperCurrent, upperDelta * upperCurrent, weight)

  local lowerCurrent = lower.rotation
  local handCurrentPosition = hand.position
  local lowerToTarget = vSub(clampedTarget, lower.position)
  if vLength(lowerToTarget) > 1e-4 then
    local lowerDelta = Quaternion.FromToRotation(
      vSub(handCurrentPosition, lower.position),
      lowerToTarget
    )
    lower.rotation = Quaternion.Slerp(lowerCurrent, lowerDelta * lowerCurrent, weight)
  end
end

-- Keep the arm in a readable holding pose while native locomotion drives the legs.
local function applyHoldingPose(entry)
 local rig=entry.rig;local root=actorRoot(entry.actor)
 if not rig or not root or not entry.weaponLocalRotation then return end
 local h,aim
 if entry.className=="mage"then h={.18,-.38,.48};aim={.08,.98,.16}
 elseif entry.className=="ranged"then h={-.08,-.18,.73};aim={0,-.08,1}
 else h={.22,-.5,.42};aim={.15,-.5,.85}end
 local shoulder=rig.upper.position
 local target=vAdd(shoulder,vAdd(vAdd(vScale(root.right,h[1]*rig.reach),vScale(root.up,h[2]*rig.reach)),vScale(root.forward,h[3]*rig.reach)))
 local pole=vAdd(vScale(root.right,.75),vScale(root.forward,-.3))
 solveArm(rig,target,pole,.85)
 local direction=vNormalize(vAdd(vAdd(vScale(root.right,aim[1]),vScale(root.up,aim[2])),vScale(root.forward,aim[3])))
 local desired=Quaternion.LookRotation(direction,root.up)*Quaternion.Inverse(entry.weaponLocalRotation)
 rig.hand.rotation=Quaternion.Slerp(rig.hand.rotation,desired,.9)
end

local function applyAttack(entry, now)
  local attack = entry.attack
  if attack == nil then return end

  local elapsed = now - attack.startTime
  local normalized = elapsed / attack.duration
  if normalized >= 1 then
    clearAttack(entry)
    return
  end

  local sample = attack.sampleScript.Sample(attack.timeline, normalized)
  if sample == nil then
    clearAttack(entry)
    return
  end

  -- 先确保骨架绑定，再刷新特效，避免降级模式切回手骨时把本帧特效重置掉。
  tryBuildRig(entry, now)

  setNodeActive(entry.flashNode, sample.flash == true)
  if sample.flash == true then
    setNodeScale(entry.flashNode, 1)
  end
  if entry.glowNode ~= nil then
    local glowScale = 0.001 + (sample.glow or 0) * 0.999
    entry.glowNode.localScale = Vector3(glowScale, glowScale, glowScale)
  end

  local weight = clamp(sample.weight or 0, 0, 1)
  if weight <= 0.001 then return end

  local root = actorRoot(entry.actor)
  if root == nil then
    clearAttack(entry)
    return
  end

  local rotatedAim = rotateLocalYaw(sample.aim, attack.yawOffset)
  local localAim = vNormalize(vAdd(
    vAdd(vScale(root.right, rotatedAim[1]), vScale(root.up, rotatedAim[2])),
    vScale(root.forward, rotatedAim[3])
  ))
  local aim = localAim
  if attack.aimWorld ~= nil and (sample.targetBlend or 0) > 0.001 then
    aim = vNormalize(vLerp(localAim, attack.aimWorld, sample.targetBlend))
  end

  if entry.rig == nil then
    -- 非人形骨架降级：不伪造手臂动作，只让武器跟随手掌并朝向目标。
    if entry.mode == "palm" then
      updatePalmAttachment(entry)
      local up = Vector3.up
      if math.abs(vDot(aim, up)) > 0.95 then up = root.forward end
      -- Keep the rigid palm attachment when humanoid bones are unavailable.
    end
    return
  end

  local rig = entry.rig
  if rig.spine ~= nil and math.abs(sample.spine) > 0.01 then
    local current = rig.spine.rotation
    local target = Quaternion.AngleAxis(sample.spine * TorsoTwistScale, root.up) * current
    rig.spine.rotation = Quaternion.Slerp(current, target, weight)
  end

  if rig.spine and math.abs(sample.lean or 0)>.01 then
    rig.spine.rotation=Quaternion.AngleAxis((sample.lean or 0)*weight,root.right)*rig.spine.rotation
  end
  local offset = rotateLocalYaw(sample.hand, attack.yawOffset)
  local shoulder = rig.upper.position
  local handTarget = vAdd(
    shoulder,
    vAdd(
      vAdd(vScale(root.right, offset[1] * rig.reach), vScale(root.up, offset[2] * rig.reach)),
      vScale(root.forward, offset[3] * rig.reach)
    )
  )

  local pole = vAdd(
    vAdd(vScale(root.right, 0.7), vScale(root.forward, -0.45)),
    vScale(root.up, 0.15)
  )
  solveArm(rig, handTarget, pole, weight)

  if entry.weaponLocalRotation == nil then return end
  local up = Vector3.up
  if math.abs(vDot(aim, up)) > 0.95 then up = root.forward end
  local targetWeaponRotation = Quaternion.LookRotation(aim, up)
  local desiredHandRotation = targetWeaponRotation * Quaternion.Inverse(entry.weaponLocalRotation)
  local currentHandRotation = rig.hand.rotation
  rig.hand.rotation = Quaternion.Slerp(currentHandRotation, desiredHandRotation, weight)
end

local function handleHostEvent(eventName, payload)
  if type(payload) ~= "table" then return false end
  if eventName == EVENT_EQUIP then
    return equipActorInternal(payload.actor, payload.className)
  elseif eventName == EVENT_ATTACK then
    return attackActorInternal(payload.actor, payload.className, payload.attackKind, payload.targetPosition)
  elseif eventName == EVENT_UNEQUIP then
    return unequipActorInternal(payload.actor)
  end
  return false
end

local function registerWithHost()
  if runtimeScope == nil or resourceRoot == nil then return end
  hostScript = runtimeScope:GetRuntimeHostScript("runtime-host.lua")
  if hostScript == nil then
    logger:info("runtime host unavailable; direct script API remains available")
    return
  end
  if type(hostScript.RegisterResource) ~= "function" then
    logger:warnOnce("host-api", "Runtime Host is missing RegisterResource")
    return
  end

  if type(hostScript.GetResources) == "function" then
    local existing = hostScript.GetResources({ tag = RIG_TAG })
    if existing ~= nil and #existing > 0 then
      logger:warnOnce("duplicate-rig", "only the first hero weapon rig instance handles the API")
      return
    end
  end

  resourceEntry = hostScript.RegisterResource(resourceRoot, RESOURCE_ID, {
    tags = { RIG_TAG },
    events = { EVENT_EQUIP, EVENT_ATTACK, EVENT_UNEQUIP },
    handler = handleHostEvent,
    options = { resourceId = RESOURCE_ID },
  })
end

function Start()
  if runtimeScope == nil or resourceRoot == nil then
    logger:warnOnce("scope", "resource scope unavailable", runtimeScopeReason)
    return
  end

  for className, definition in pairs(WEAPON_DEFS) do
    definition.sourceGo = runtimeScope:GetGameObjectByPath(definition.sourcePath)
    if definition.sourceGo == nil then
      logger:warnOnce("source-" .. className, "weapon source missing: " .. definition.sourcePath)
    end
    local grip = runtimeScope:GetTransformByPath(definition.gripPath)
    if grip ~= nil then
      definition.gripPosition = grip.localPosition
      definition.gripRotation = grip.localRotation
    else
      logger:warnOnce("grip-" .. className, "grip socket missing: " .. definition.gripPath)
    end
  end

  hideSourceWeapons()
  ensureTimelineScript()
  if timelineScript == nil then
    logger:warnOnce("timeline-start", "attack timeline helper is not ready")
  end
  registerWithHost()
end

function Update()
 for _,entry in pairs(equippedByActor)do restorePose(entry)end
end
function LateUpdate()
  if next(equippedByActor) == nil then return end
  local now = Time.time

  for actor, entry in pairs(equippedByActor) do
    if not isActorAlive(actor) then
      equippedByActor[actor] = nil
      if entry.weapon ~= nil then
        pcall(function() Spawn.destroy(entry.weapon) end)
      end
    else
      tryBuildRig(entry, now)
      local pos=entry.actor.position
      local last=entry.lastWalkPosition
      local moving=last and ((pos.x-last.x)^2+(pos.z-last.z)^2)>.000001
      entry.lastWalkPosition={x=pos.x,z=pos.z}
      -- Native locomotion can overwrite the turn later in Update. Reapply it
      -- before hand/spine posing in LateUpdate, on local and remote avatars.
      local attack=entry.attack
      if attack and now<attack.startTime+attack.duration then
       faceAttack(entry.actor,actorRoot(entry.actor),attack.facingWorld)
      end
      capturePose(entry)
      -- During locomotion the native animator owns the arm swing too.
      -- The weapon remains attached to the palm, without freezing a holding pose.
      if not moving or entry.attack~=nil then applyHoldingPose(entry)end
      if entry.attack ~= nil then applyAttack(entry, now)end
      if entry.mode == "palm" then updatePalmAttachment(entry)end
    end
  end
end

function OnDisable()
  local actors = {}
  for actor in pairs(equippedByActor) do
    table.insert(actors, actor)
  end
  for _, actor in ipairs(actors) do
    unequipActorInternal(actor)
  end

  if hostScript ~= nil and resourceEntry ~= nil and type(hostScript.UnregisterResource) == "function" then
    hostScript.UnregisterResource(resourceEntry)
  end
  resourceEntry = nil
end

function OnDestroy()
  OnDisable()
end

-- 供同资源脚本或外部宿主直接调用的公共接口。
function Equip(actor, className)
  return equipActorInternal(actor, className)
end

function Attack(actor, className, attackKind, targetPosition, duration, elapsed)
  local ok=attackActorInternal(actor, className, attackKind, targetPosition)
  local entry=equippedByActor[actor]
  if ok and entry and entry.attack then
    if duration then entry.attack.duration=math.max(.12,duration)end
    entry.attack.startTime=Time.time-math.max(0,elapsed or 0)
  end
  return ok
end
function SetUltimateScale(actor,scale)
 local e=equippedByActor[actor];if not e or not e.weapon then return end
 local nextScale=clamp(scale or 1,1,4)
 if e.ultimateScale==nextScale then return end
 e.ultimateScale=nextScale
 local parent=e.weapon.transform.parent
 if parent then sizeWeapon(e,parent)end
end
function GetWeapon(actor)
 local e=equippedByActor[actor];return e and e.weapon or nil
end
function GetMuzzle(actor)
 local e=equippedByActor[actor];if not e then return nil end
 return e.weapon.transform:Find(e.className=="mage" and "Tip" or (e.className=="ranged" and "Muzzle" or "Tip"))
end
function GetRigStatus(actor)
 local e=equippedByActor[actor];if not e then return "unequipped"end
 local sc=e.weapon.transform.lossyScale;local length=(e.localExtent or 0)*math.max(math.abs(sc.x),math.abs(sc.y),math.abs(sc.z))
 return e.className..":"..e.mode..":"..tostring(e.rig~=nil)..string.format(" length=%.2f",length)
end

function Unequip(actor)
  return unequipActorInternal(actor)
end

function GetEquippedClass(actor)
  local entry = equippedByActor[actor]
  if entry == nil then return nil end
  return entry.className
end
function CancelAttack(actor)
 local entry=equippedByActor[actor];if entry then restorePose(entry);clearAttack(entry)end
end
