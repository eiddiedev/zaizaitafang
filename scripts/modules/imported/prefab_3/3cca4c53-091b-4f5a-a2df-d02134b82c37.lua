---@id 3cca4c53-091b-4f5a-a2df-d02134b82c37
---@referenceName runtime-host.lua
-- 多资源世界的 Runtime Host 骨架；按当前玩法补充确实需要的接口。
local Logger = require("official.core.logger")
local RuntimeScope = require("official.core.runtime_scope")
local hostLogger = Logger.create("runtime-host")

local hostReady = false
local registry = {}
local resources = {}
local resourceIdIndex = {}
local resourceTagIndex = {}
local resourceObjectIndex = {}
local statsVersion = 0

local function bumpVersion()
  statsVersion = statsVersion + 1
end

local function getBucket(component, group)
  registry[component] = registry[component] or {}
  registry[component][group] = registry[component][group] or {}
  return registry[component][group]
end

local function getResourceIdBucket(resourceId)
  if resourceId == nil then return {} end
  resourceIdIndex[resourceId] = resourceIdIndex[resourceId] or {}
  return resourceIdIndex[resourceId]
end

local function getResourceTagBucket(tag)
  if tag == nil then return {} end
  resourceTagIndex[tag] = resourceTagIndex[tag] or {}
  return resourceTagIndex[tag]
end

local function getResourceObjectBucket(gameObject)
  if gameObject == nil then return {} end
  resourceObjectIndex[gameObject] = resourceObjectIndex[gameObject] or {}
  return resourceObjectIndex[gameObject]
end

local function cloneShallowTable(source)
  local result = {}
  if type(source) ~= "table" then return result end

  for key, value in pairs(source) do
    result[key] = value
  end
  return result
end

local function cloneArray(source)
  local result = {}
  if type(source) ~= "table" then return result end

  for _, value in ipairs(source) do
    table.insert(result, value)
  end
  return result
end

local function normalizeStringList(values)
  local result = {}
  local seen = {}

  local function addValue(value)
    if value == nil then return end
    local normalized = tostring(value)
    if normalized == "" or seen[normalized] == true then return end
    seen[normalized] = true
    table.insert(result, normalized)
  end

  if type(values) == "string" then
    for value in string.gmatch(values, "[^,%s;]+") do
      addValue(value)
    end
    return result
  end

  if type(values) == "table" then
    for key, value in pairs(values) do
      if type(value) == "string" or type(value) == "number" then
        addValue(value)
      elseif type(key) == "string" and value == true then
        addValue(key)
      end
    end
  end

  return result
end

local function buildStringSet(values)
  local result = {}
  if type(values) ~= "table" then return result end

  for _, value in ipairs(values) do
    result[value] = true
  end
  return result
end

local function snapshotResourceEntry(entry)
  if entry == nil then return nil end

  return {
    gameObject = entry.gameObject,
    resourceId = entry.resourceId,
    options = cloneShallowTable(entry.options),
    removed = entry.removed == true,
    tags = cloneArray(entry.tags),
    events = cloneArray(entry.events),
  }
end

local function removeEntryFromArray(array, entry)
  if array == nil then return end

  for i = #array, 1, -1 do
    if array[i] == entry then
      table.remove(array, i)
    end
  end
end

local function removeResourceEntryFromIndexes(entry)
  if entry == nil then return end

  removeEntryFromArray(resourceIdIndex[entry.resourceId], entry)
  removeEntryFromArray(resourceObjectIndex[entry.gameObject], entry)

  if entry.tags ~= nil then
    for _, tag in ipairs(entry.tags) do
      removeEntryFromArray(resourceTagIndex[tag], entry)
    end
  end
end

local function indexResourceEntry(entry)
  if entry == nil then return end

  table.insert(getResourceIdBucket(entry.resourceId), entry)
  table.insert(getResourceObjectBucket(entry.gameObject), entry)

  if entry.tags ~= nil then
    for _, tag in ipairs(entry.tags) do
      table.insert(getResourceTagBucket(tag), entry)
    end
  end
end

local function cleanupResourceBucket(bucket)
  if bucket == nil then return {} end

  for i = #bucket, 1, -1 do
    local entry = bucket[i]
    if entry == nil or entry.removed == true or entry.gameObject == nil then
      table.remove(bucket, i)
    end
  end
  return bucket
end

local function findResourceEntry(gameObject, resourceId)
  for _, entry in ipairs(resources) do
    if entry ~= nil and entry.removed ~= true and entry.gameObject == gameObject and entry.resourceId == resourceId then
      return entry
    end
  end
  return nil
end

local function acceptsEvent(entry, eventName)
  if entry == nil or entry.eventSet == nil or eventName == nil then return false end
  return entry.eventSet[eventName] == true
end

local function addResourceEntry(result, seen, entry)
  if entry == nil or entry.removed == true or entry.gameObject == nil or seen[entry] == true then return end

  seen[entry] = true
  table.insert(result, entry)
end

local function collectBucketEntries(bucket, result, seen)
  cleanupResourceBucket(bucket)
  for _, entry in ipairs(bucket or {}) do
    addResourceEntry(result, seen, entry)
  end
end

local function collectGameObjectEntries(gameObject, result, seen)
  if gameObject == nil then return end

  local resourceRoot = RuntimeScope.resolveResourceRoot(gameObject)
  collectBucketEntries(resourceObjectIndex[resourceRoot], result, seen)
end

local function collectSelectorList(values, visitor)
  if values == nil then return end

  if type(values) == "table" then
    for _, value in ipairs(values) do
      visitor(value)
    end
    return
  end

  visitor(values)
end

local function collectTargetEntries(target)
  local result = {}
  local seen = {}

  if target == nil then return result end

  if type(target) ~= "table" then
    collectGameObjectEntries(target, result, seen)
    return result
  end

  collectSelectorList(target.id or target.resourceId, function(resourceId)
    collectBucketEntries(resourceIdIndex[tostring(resourceId)], result, seen)
  end)
  collectSelectorList(target.ids or target.resourceIds, function(resourceId)
    collectBucketEntries(resourceIdIndex[tostring(resourceId)], result, seen)
  end)
  collectSelectorList(target.tag, function(tag)
    collectBucketEntries(resourceTagIndex[tostring(tag)], result, seen)
  end)
  collectSelectorList(target.tags, function(tag)
    collectBucketEntries(resourceTagIndex[tostring(tag)], result, seen)
  end)

  if target.gameObject ~= nil then
    collectGameObjectEntries(target.gameObject, result, seen)
  end

  return result
end

local function warnEventFailure(eventName, context, message)
  local source = context ~= nil and context.sourceResourceId or nil
  hostLogger:warn(
    "event dispatch failed",
    "event=" .. tostring(eventName),
    "source=" .. tostring(source),
    "error=" .. tostring(message)
  )
end

function IsReady()
  return hostReady
end

function EnsureScene()
  return true
end

function RegisterResource(gameObject, resourceId, config)
  if gameObject == nil or resourceId == nil then return nil end

  local normalizedResourceId = tostring(resourceId)
  if normalizedResourceId == "" then return nil end

  config = config or {}
  local entry = findResourceEntry(gameObject, normalizedResourceId)
  if entry ~= nil then
    removeResourceEntryFromIndexes(entry)
  else
    entry = {
      gameObject = gameObject,
      resourceId = normalizedResourceId,
    }
    table.insert(resources, entry)
  end

  entry.tags = normalizeStringList(config.tags)
  entry.events = normalizeStringList(config.events)
  entry.eventSet = buildStringSet(entry.events)
  entry.handler = config.handler
  entry.options = config.options or entry.options or {}
  entry.removed = false

  indexResourceEntry(entry)
  return entry
end

function UnregisterResource(entry)
  if entry == nil or entry.removed == true then return end

  removeResourceEntryFromIndexes(entry)
  removeEntryFromArray(resources, entry)
  entry.removed = true
end

function GetResources(target)
  local snapshot = {}
  for _, entry in ipairs(collectTargetEntries(target)) do
    local item = snapshotResourceEntry(entry)
    if item ~= nil then
      table.insert(snapshot, item)
    end
  end
  return snapshot
end

function ForEachResource(target, visitor)
  if type(visitor) ~= "function" then return 0 end

  local count = 0
  for _, entry in ipairs(collectTargetEntries(target)) do
    local item = snapshotResourceEntry(entry)
    if item ~= nil then
      visitor(item)
      count = count + 1
    end
  end
  return count
end

function DispatchEvent(target, eventName, payload, context)
  if eventName == nil then return 0 end

  local count = 0
  for _, entry in ipairs(collectTargetEntries(target)) do
    if entry ~= nil and entry.removed ~= true and type(entry.handler) == "function" and acceptsEvent(entry, eventName) then
      local ok, result = pcall(entry.handler, eventName, payload or {}, context or {})
      if ok and result ~= false then
        count = count + 1
      elseif not ok then
        warnEventFailure(eventName, context, result)
      end
    end
  end
  return count
end

function Register(component, group, gameObject, initialState, options)
  if component == nil or group == nil or gameObject == nil then return nil end

  local bucket = getBucket(component, group)
  for _, entry in ipairs(bucket) do
    if entry ~= nil and entry.gameObject == gameObject then
      entry.state = initialState or entry.state or {}
      entry.options = options or entry.options or {}
      return entry
    end
  end

  local entry = {
    component = component,
    group = group,
    gameObject = gameObject,
    state = initialState or {},
    options = options or {},
  }
  table.insert(bucket, entry)
  bumpVersion()
  return entry
end

function UpdateRegistry(entry, patch)
  if entry == nil or entry.state == nil then return end
  if patch ~= nil then
    for key, value in pairs(patch) do
      entry.state[key] = value
    end
  end
  bumpVersion()
end

function Unregister(entry)
  if entry == nil then return end
  local bucket = getBucket(entry.component, entry.group)
  for i = #bucket, 1, -1 do
    if bucket[i] == entry then
      table.remove(bucket, i)
      bumpVersion()
      return
    end
  end
end

function GetStats(component, group)
  local bucket = getBucket(component, group)
  local total = 0
  local active = 0
  local collected = 0

  for _, entry in ipairs(bucket) do
    if entry ~= nil and entry.gameObject ~= nil then
      total = total + 1
      if entry.state == nil or entry.state.active ~= false then active = active + 1 end
      if entry.state ~= nil and entry.state.collected == true then collected = collected + 1 end
    end
  end

  return {
    total = total,
    active = active,
    collected = collected,
    allCollected = total > 0 and collected >= total,
    version = statsVersion,
  }
end

function ForEach(component, group, visitor)
  if visitor == nil then return end

  local bucket = getBucket(component, group)
  for _, entry in ipairs(bucket) do
    if entry ~= nil and entry.gameObject ~= nil then
      visitor(entry)
    end
  end
end

-- ---------------------------------------------------------------------------
-- 三职业仔仔职装组件接口（跨资源公共接口）
--
-- 参与资源：
--   module-classwear-outfits  读取 Actor 标签并渲染职装，事件接收方。
--   ui-classwear-preview      只通过本 Host 的 *Local 接口换装，不接触模组内部。
--
-- 状态约定（均存放在 Actor 标签上，随房间同步，所有端读到同一状态）：
--   jiejie_classwear_class   "" | "melee" | "ranged" | "mage"
--   jiejie_classwear_visible "1" | "0"；没有职业时不生效
--
-- 调用时机：Equip 立即写标签并派发 Classwear.refresh；没有收到事件的远端
-- 由模组按固定间隔读取标签自行收敛。重复 Equip 同类不会重复创建模型。
-- 返回 true 表示标签写入成功；false 表示 Actor 或 className 无效。
-- ---------------------------------------------------------------------------

local CLASS_TAG = "jiejie_classwear_class"
local VISIBLE_TAG = "jiejie_classwear_visible"
local OUTFIT_MODULE_ID = "module-classwear-outfits"
local OUTFIT_REFRESH_EVENT = "Classwear.refresh"
local VALID_CLASS = {
  melee = true,
  ranged = true,
  mage = true,
}

local function isObjectAlive(value)
  if value == nil then return false end
  local ok, referenceEquals = pcall(function()
    return CS.System.Object.ReferenceEquals(value, nil)
  end)
  if ok and referenceEquals == true then return false end
  return true
end

local function getLocalActor()
  local actor = CS.DouyinActorService.GetLocalActor()
  if isObjectAlive(actor) then return actor end

  local player = CS.DouyinPlayerService.GetLocalPlayer()
  if not isObjectAlive(player) then return nil end

  local fallback = player:GetActor()
  if isObjectAlive(fallback) then return fallback end
  return nil
end

local function readActorTag(actor, tagName)
  if not isObjectAlive(actor) then return "" end
  local ok, value = pcall(function()
    return actor:GetActorTag(tagName)
  end)
  if not ok or value == nil then return "" end
  return tostring(value)
end

local function writeActorTag(actor, tagName, tagValue)
  if not isObjectAlive(actor) then return false end
  local ok = pcall(function()
    actor:SetActorTag(tagName, tagValue or "")
  end)
  return ok
end

local function clearActorTag(actor, tagName)
  if not isObjectAlive(actor) then return false end
  local ok = pcall(function()
    actor:ClearActorTags(tagName)
  end)
  return ok
end

local function normalizeClass(className)
  if type(className) ~= "string" then return nil end
  if VALID_CLASS[className] ~= true then return nil end
  return className
end

local function isVisibleTagValue(value)
  return value ~= "0"
end

local function notifyOutfitModule(actor, className, visible)
  local actorId = ""
  if isObjectAlive(actor) then
    local ok, value = pcall(function()
      return actor.actorID
    end)
    if ok and value ~= nil then actorId = tostring(value) end
  end

  DispatchEvent({ id = OUTFIT_MODULE_ID }, OUTFIT_REFRESH_EVENT, {
    actorID = actorId,
    className = className or "",
    visible = visible == true,
  }, { sourceResourceId = "runtime-host" })
end

function GetClass(actor)
  return readActorTag(actor, CLASS_TAG)
end

function IsVisible(actor)
  if GetClass(actor) == "" then return false end
  return isVisibleTagValue(readActorTag(actor, VISIBLE_TAG))
end

function GetState(actor)
  local className = GetClass(actor)
  return {
    className = className,
    visible = className ~= "" and isVisibleTagValue(readActorTag(actor, VISIBLE_TAG)),
  }
end

function Equip(actor, className)
  local normalized = normalizeClass(className)
  if not isObjectAlive(actor) or normalized == nil then return false end

  local currentClass = readActorTag(actor, CLASS_TAG)
  if currentClass == normalized then
    -- 重复装备同类只恢复显示，不重建模型；死亡端的渲染兜底仍会隐藏。
    writeActorTag(actor, VISIBLE_TAG, "1")
    notifyOutfitModule(actor, normalized, true)
    return true
  end

  if not writeActorTag(actor, CLASS_TAG, normalized) then return false end
  writeActorTag(actor, VISIBLE_TAG, "1")
  notifyOutfitModule(actor, normalized, true)
  return true
end

function Unequip(actor)
  if not isObjectAlive(actor) then return false end

  clearActorTag(actor, CLASS_TAG)
  clearActorTag(actor, VISIBLE_TAG)
  notifyOutfitModule(actor, "", false)
  return true
end

function SetVisible(actor, visible)
  if not isObjectAlive(actor) then return false end

  local visibleValue = "0"
  if visible == true then visibleValue = "1" end
  writeActorTag(actor, VISIBLE_TAG, visibleValue)
  notifyOutfitModule(actor, readActorTag(actor, CLASS_TAG), visible == true)
  return true
end

function EquipLocal(className)
  return Equip(getLocalActor(), className)
end

function UnequipLocal()
  return Unequip(getLocalActor())
end

function SetLocalVisible(visible)
  return SetVisible(getLocalActor(), visible)
end

function GetLocalState()
  local actor = getLocalActor()
  if not isObjectAlive(actor) then
    return { className = "", visible = false, available = false }
  end
  local state = GetState(actor)
  state.available = true
  return state
end

function Start()
  hostReady = true
end