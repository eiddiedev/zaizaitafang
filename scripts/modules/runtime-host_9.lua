---@id 964153e6-4611-4f70-9d53-d29ebf5bf52c
---@referenceName runtime-host.lua
---@assetRef eyJhc3NldElkIjoibWl4LWNyeXN0YWwtZGVmZW5zZTpoYW1sZXQtdWdjL2FpZ2NfZWRpdG9yL2Rldi91bml0eS9NUzR3TGpBQkFBQUFpWGVTbVJUZzVIekJKb1pRTkE0OEh1eXBoeWkxME4zNmk4QjJpenpZSjNZL21peC1wYXJ0LTBfX3VwbG9hZF9qeTQyZGQzeC5nbGIiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvbWl4LXBhcnQtMF9fdXBsb2FkX2p5NDJkZDN4LmdsYiIsInJlZmVyZW5jZU5hbWUiOiJydW50aW1lLWhvc3QubHVhIn0
-- 多资源世界的 Runtime Host 骨架；按当前玩法补充确实需要的接口。
---@displayName 晶界守卫主控
---@start
---@var BattleSpeed:number=1
---@name 战斗时间倍率
---@desc 默认1，调试整局时可提高，所有玩家共享主权方设置。
---@varSync SnapshotFrames:Dictionary<int,string>
---@varSync SnapshotCommit:string
---@end
local Logger = require("official.core.logger")
local RuntimeScope = require("official.core.runtime_scope")
local hostLogger = Logger.create("runtime-host")
local runtimeScope,runtimeScopeReason=RuntimeScope.from(self)
local U=CS.UnityEngine
local Game={state=nil,config=nil,sim=nil,codec=nil,layout=nil,ready=false,net=false,revision=0,applied=0,owner=false,authorityReady=false,acc=0,publishAt=0,rosterAt=0,pending={},seq=0,localId=nil,localActor=nil,lastTeleport=nil,lastMotion=nil,placed=false,cameraApplied=false,inputAt=0,lookAt=-100,looking=false,settings={volume=.8,shake=false,camera="top"},error=nil}

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

function Start()
  hostReady = true
  InitializeGame()
end

function InitializeGame()
 if Game.ready then return true end
 if not runtimeScope then Game.error=runtimeScopeReason;return false end
 local config=runtimeScope:GetScript("helpers/config.lua")
 Game.sim=runtimeScope:GetScript("helpers/simulation.lua");Game.codec=runtimeScope:GetScript("helpers/codec.lua");Game.layout=runtimeScope:GetScript("helpers/layout.lua")
 if not config or not Game.sim or not Game.codec or not Game.layout then Game.error="玩法脚本尚未就绪";return false end
 local o=Game.layout.GetNativeOrigin()
 Game.originalRootPosition=self.transform.position
 self.transform.position=U.Vector3(o.x,o.y,o.z)
 local ui=self.transform:Find("ui-game")
 if ui then ui.gameObject:SetActive(true) end
 local oldWorld=self.transform:Find("四境守卫完整战场")
 if oldWorld then
  for _,name in ipairs({"Foundation","ThemeForest","ThemeSnow","ThemeDesert","ThemeNight","Core"})do
   local n=oldWorld:Find(name);if n then n.gameObject:SetActive(false) end
  end
 end
 Game.config=config.GetConfig();Game.sim.Configure(Game.config,Game.layout);Game.state=Game.sim.NewState(93119);Game.ready=true
 Game.onLookStart=function()Game.looking=true end
 Game.onLookEnd=function()Game.looking=false;Game.lookAt=U.Time.time end
 Game.onMoveStart=function()Game.moveX=0;Game.moveZ=0 end
 Game.onMovePerform=function(vec)if not Game.sendingWalk then Game.moveX=vec.x;Game.moveZ=vec.y end end
 Game.onMoveCancel=function()Game.moveX=0;Game.moveZ=0 end
 CS.DouyinInputService.onMoveInputStart:AddListener(Game.onMoveStart)
 CS.DouyinInputService.onMoveInputPerform:AddListener(Game.onMovePerform)
 CS.DouyinInputService.onMoveInputCancel:AddListener(Game.onMoveCancel)
 pcall(function()CS.DouyinInputService.onLookInputStart:AddListener(Game.onLookStart);CS.DouyinInputService.onLookInputPerform:AddListener(Game.onLookStart);CS.DouyinInputService.onLookInputCancel:AddListener(Game.onLookEnd)end)
 hostLogger:info("晶界守卫玩法初始化完成")
 return true
end

local function localIdentity()
 local p=CS.DouyinPlayerService.GetLocalPlayer();if not p then return nil end
 local open=p.playerOpenID;local stable=open~=nil and tostring(open)~="";local id=stable and tostring(open)or("session:"..tostring(p.playerID))
 Game.localId=id;Game.localActor=p:GetActor();return id,p,stable
end
-- Persistent per-world scores. Failure never fabricates ranks or overwrites a higher record.
local Rank={rows={},status="尚未读取",best=0,myRank=nil,busy=false,nextAt=0,saved=-1,request=0}
local function rankService(name)
 -- DataService is a Lua SDK facade, not a C# static type.
 if name=="DouyinDataService" then return DouyinDataService end
 if name=="DouyinRankService" then return CS.DouyinRankService end
end
local function rankProfileScope(id)
 local a,b=5381,52711
 for i=1,#id do local c=string.byte(id,i);a=(a*131+c)%4294967296;b=(b*137+c)%4294967296 end
 return string.format("p%08x%08x",a,b)
end
local function refreshRanking(force)
 if Rank.busy or (not force and U.Time.time<Rank.nextAt)then return end
 local id,player,stable=localIdentity();if not id or not stable then Rank.status="正式登录后可读取排行榜";return end
 local state=Game.state;local member=state.players[id]
 local completed=math.max(0,math.floor(tonumber(state.completedWaves)or(state.result and state.result.waves)or 0))
 -- A player joining in progress must complete at least one wave before submitting.
 local score=member and not member.spectator and completed>=(member.eligibleFrom or 1)and completed or 0
 local ds=rankService("DouyinDataService")
 if not ds or type(DATASTORE)~="function"then Rank.status="当前预览未开放排行榜存储，请在发布环境验证";Rank.nextAt=U.Time.time+30;return end
 Rank.busy=true;Rank.status="正在同步排行榜…";Rank.nextAt=U.Time.time+30;Rank.request=Rank.request+1
 local token=Rank.request;Rank.startedAt=U.Time.time
 local function check(code,value)if code~=0 then error("数据接口返回 "..tostring(code).." / "..tostring(value))end;return value end
 local launched,launchErr=pcall(function()DATASTORE(function()
  local ok,err=pcall(function()
   local code,store=ds.GetOrderedDataStore("CDWavesV1","forest");check(code,store)
   local pc,profile=ds.GetDataStore("CDProfileV1",rankProfileScope(id));check(pc,profile)
   local oc,owner=profile:GetData("owner");check(oc,owner)
   if owner~=nil and owner~="" and owner~=id then error("成绩归属校验失败")end
   local best
   if score>0 then
    check(profile:SetData("owner",id))
    local uc,value=store:UpdateData(id,function(old)return math.max(tonumber(old)or 0,score)end);best=tonumber(check(uc,value))or score
    Rank.saved=math.max(Rank.saved,score)
    local nc=profile:SetData("name",member and member.name or "仔仔");check(nc)
    local bc=profile:SetData("bestWave",best);check(bc)
    local native=rankService("DouyinRankService")
    if native and best>(Rank.nativeSubmitted or -1)then
     pcall(function()native.SetRankData(best,"",function(success)if success then Rank.nativeSubmitted=best end end)end)
    end
   else
    local bc,value=profile:GetData("bestWave");check(bc);best=tonumber(value)or 0
   end
   local gc,pages=store:GetSortedData(false,50);check(gc,pages)
   local all={};local finished=false
   for page=1,100 do
    local rc,values=pages:GetCurrentPage();check(rc,values)
    for key,entry in pairs(values or {})do
     local entryKey=type(entry)=="table"and(entry.key or entry.Key)or nil
     local value=type(entry)=="table"and(entry.value or entry.Value)or entry
     local uid=tostring(entryKey or key)
     if tonumber(value)then all[#all+1]={id=uid,score=tonumber(value)}end
    end
    if pages.isFinished or #all==0 then finished=true;break end
    if not pages:AdvanceToNextPage()then finished=true;break end
   end
   table.sort(all,function(a,b)if a.score==b.score then return a.id<b.id end;return a.score>b.score end)
   local myRank=nil;local rows={};local previous,position
   for index,row in ipairs(all)do
    if previous~=row.score then position=index;previous=row.score end
    row.rank=position
    if row.id==id then myRank=position;best=math.max(best,row.score)end
    if index<=8 then
     local name="守卫仔仔"
     if row.id==id then name=member and member.name or "我"else
      local nc,np=ds.GetDataStore("CDProfileV1",rankProfileScope(row.id))
      if nc==0 then local vc,n=np:GetData("name");if vc==0 and type(n)=="string"then name=n end end
     end
     row.name=name;rows[#rows+1]=row
    end
   end
   if token==Rank.request then
    Rank.rows=rows;Rank.best=best;Rank.myRank=myRank;Rank.complete=finished;Rank.loaded=true
    Rank.status=#rows==0 and "暂无纪录，成为第一位守卫吧"or "按最高完成波次排名 · 同波次并列"
   end
  end)
  if token==Rank.request then Rank.busy=false;if not ok then Rank.status=string.find(tostring(err),"DataStore not open",1,true) and "当前环境未开放成绩存储"or"排行榜暂不可用，请稍后刷新";hostLogger:warnOnce("ranking-data",tostring(err))end end
 end)end)
 if not launched then Rank.busy=false;Rank.status="排行榜连接失败，请稍后刷新";hostLogger:warnOnce("ranking-launch",tostring(launchErr))end
end
function RefreshLeaderboard()refreshRanking(true)end
local function updateRanking()
 if Rank.busy and U.Time.time-(Rank.startedAt or 0)>20 then Rank.request=Rank.request+1;Rank.busy=false;Rank.status="排行榜连接超时，请刷新重试";Rank.nextAt=U.Time.time+30 end
 local s=Game.state
 local key=tostring(s.round)..":"..tostring(s.phase)
 if key~=Rank.phase then Rank.phase=key;if s.phase=="RANKING"or s.phase=="MAIN_CLEAR"or s.phase=="RESULT"then refreshRanking(true)end end
 if (s.completedWaves or 0)>Rank.saved and U.Time.time>=Rank.nextAt then refreshRanking(false)end
end

local function snapshotState()
 -- Map geometry is deterministic. Keep the authority's live tables intact.
 local packet={};for k,v in pairs(Game.state)do if k~="candidates"and k~="layout"then packet[k]=v end end
 local layout=Game.state.layout
 if layout then packet.layout={theme=layout.theme,seed=layout.seed,hash=layout.hash}end
 return packet
end
local function restoreMaps(decoded)
 -- Codec numbers round-trip through decimal text. Canonical integers keep
 -- seed-derived layout hashes identical across Lua integer/float subtypes.
 if type(decoded.seed)~="number"or decoded.seed%1~=0 then return false end
 decoded.seed=math.floor(decoded.seed)
 if decoded.layout then
  local descriptor=decoded.layout
  if type(descriptor)~="table"or type(descriptor.seed)~="number"or type(descriptor.theme)~="string"or type(descriptor.hash)~="string"then return false end
  local themeKnown=false;for _,theme in ipairs(Game.config.themes)do if descriptor.theme==theme then themeKnown=true;break end end
  if not themeKnown then return false end
  if descriptor.seed%1~=0 then return false end
  local layout=Game.layout.Generate(descriptor.theme,math.floor(descriptor.seed))
  if layout.hash~=descriptor.hash or not Game.layout.Validate(layout)then return false end
  decoded.layout=layout
 end
 decoded.candidates={}
 return true
end
local function readSnapshot(force)
 if not Game.net or not Game.ready then return false end
 local manifest=SnapshotCommit:GetValue();if not manifest or manifest==""then return false end
 local rev,bank,count,hash=string.match(manifest,"^(%d+):(%d+):(%d+):(%d+)$");rev,bank,count,hash=tonumber(rev),tonumber(bank),tonumber(count),tonumber(hash)
 if not rev or count>100 or count<1 then return false end
 if not force and rev<=Game.applied then return true end
 local pieces={};for i=1,count do local key=bank*1000+i;if not SnapshotFrames:ContainsKey(key)then return false end;local v=SnapshotFrames:GetValue(key);if type(v)~="string"then return false end;local prefix,payload=string.match(v,"^(%d+)|(.*)$");if tonumber(prefix)~=rev then return false end;pieces[i]=payload end
 local packet=table.concat(pieces);if Game.codec.Hash(packet)~=hash then return false end
 local decoded,reason=Game.codec.Decode(packet);if not decoded or type(decoded)~="table"or decoded.version~=Game.config.version or type(decoded.players)~="table"then Game.error=reason or"快照版本不一致";return false end
 local restored,valid=pcall(restoreMaps,decoded);if not restored or not valid then Game.error="地图快照校验失败";return false end
 Game.state=decoded;Game.applied=rev;Game.revision=math.max(Game.revision,rev);Game.receivedAt=U.Time.time;return true
end
local function publish()
 if not Game.net or not Game.authorityReady or not self:HasOwnership()then return end
 local raw=Game.codec.Encode(snapshotState());Game.revision=Game.revision+1;local rev=Game.revision;local bank=rev%2;local pos,i=1,0
 while pos<=#raw do local last=math.min(#raw,pos+4499);while last<#raw and string.byte(raw,last+1)>=128 and string.byte(raw,last+1)<=191 do last=last-1 end
  i=i+1;SnapshotFrames:SetValue(bank*1000+i,tostring(rev).."|"..string.sub(raw,pos,last));pos=last+1
 end
 SnapshotCommit:SetValue(rev..":"..bank..":"..i..":"..Game.codec.Hash(raw));Game.applied=rev;Game.packetBytes=#raw;Game.publishAt=U.Time.time+.25
end
local function takeOwnership()
 if Game.authorityReady then return true end
 local manifest=SnapshotCommit:GetValue()
 if manifest and manifest~=""then
  -- A new owner may already hold an older complete revision. Never publish it
  -- over a newer commit whose independent dictionary chunks are still arriving.
  if not readSnapshot(true)then return false end
 elseif Game.applied~=0 then return false end
 Game.authorityReady=true;Game.acc=0;Game.publishAt=0;return true
end
function OnNetSpawned()
 InitializeGame();Game.net=true;Game.authorityReady=false
 SnapshotFrames:OnValueChange(function()if not self:HasOwnership()then readSnapshot(false)end end)
 SnapshotCommit:OnValueChange(function()if not self:HasOwnership()then readSnapshot(false)end end)
 readSnapshot(true)
end
function OnNetDestroy()Game.net=false;Game.owner=false;Game.authorityReady=false end
function OnOwnershipRequest(senderId)return false end
function OnOwnershipTransferred()
 if not Game.net or not Game.ready then return end
 Game.authorityReady=false;Game.acc=0
 if self:HasOwnership()then takeOwnership()end
 Game.owner=self:HasOwnership()
end
local function collectRoster()
 local result={};local players=CS.DouyinPlayerService.GetPlayers();if not players then return result end
 for i=0,players.Length-1 do local p=players[i];local actor=p:GetActor()
  if actor then local open=p.playerOpenID;local stable=open~=nil and tostring(open)~="";local id=stable and tostring(open)or("session:"..tostring(p.playerID));local pos=self.transform:InverseTransformPoint(actor.position)
   local direction=self.transform:InverseTransformDirection(actor.gameObject.transform.forward)
   result[#result+1]={id=id,name=tostring(p.playerName or"仔仔"),stable=stable,x=pos.x,z=pos.z,fx=direction.x,fz=direction.z,angle=math.deg(math.atan(direction.x,direction.z))}
  end
 end;return result
end
function ReceiveGameCommand(id,seq,packet)
 if not Game.net or not Game.ready or not Game.authorityReady or not self:HasOwnership()then return end
 if type(id)~="string"or type(seq)~="number"or seq%1~=0 or seq<1 or type(packet)~="string"or #packet>2048 then return end
 local S=Game.state;local p=S.players[id];if not p or not p.online then return end
 local old=S.acks[id];if old and seq<=old.seq then Game.publishAt=0;return end
 local a=Game.codec.Decode(packet);if not a then return end
 local ok,reason
 if a.round~=S.round then ok,reason=false,"赛局已切换，请重试"
 else ok,reason=Game.sim.Action(S,id,a)end
 S.acks[id]={seq=seq,ok=ok==true,reason=reason or"",at=S.t};if reason then p.message=reason;p.messageAt=S.t end
 Game.publishAt=0
end
function SubmitGameAction(payload)
 if not InitializeGame()or type(payload)~="table"then return {ok=false,reason="玩法载入中"}end
 if payload.kind=="settings"then
  if payload.volume~=nil then Game.settings.volume=math.max(0,math.min(1,tonumber(payload.volume)or .8))end
  if payload.shake~=nil then Game.settings.shake=payload.shake==true end;return {ok=true}
 elseif payload.kind=="camera"then Game.settings.camera=Game.settings.camera=="top"and"third"or"top";Game.cameraApplied=false;return {ok=true}end
 if not Game.net or not CS.DouyinNetService.isNetworkSettled then return {ok=false,reason="正在同步房间"}end
 local id=localIdentity();if not id or not Game.state.players[id]then return {ok=false,reason="正在接入仔仔"}end
 local ack=Game.state.acks[id];Game.seq=math.max(Game.seq,ack and ack.seq or 0)+1
 local a={};for k,v in pairs(payload)do if type(v)=="number"or type(v)=="boolean"or type(v)=="string"then a[k]=v end end;a.round=Game.state.round
 if not a.slot then a.slot=Game.state.players[id].selectedSlot end
 local packet=Game.codec.Encode(a)
 if self:HasOwnership()and Game.authorityReady and #Game.pending==0 then ReceiveGameCommand(id,Game.seq,packet);local answer=Game.state.acks[id];return {ok=answer and answer.ok or false,reason=answer and answer.reason or"同步中"}end
 -- Serial command delivery: retries reuse a sequence; later commands wait for the receipt.
 Game.pending[#Game.pending+1]={id=id,seq=Game.seq,packet=packet,last=-100,created=U.Time.time};return {ok=true,reason="操作已提交"}
end
local function retryCommands()
 local q=Game.pending[1];if not q then return end
 local ack=Game.state.acks[q.id]
 if ack and ack.seq>=q.seq then table.remove(Game.pending,1);return end
 if U.Time.time-q.created>12 then Game.error="操作等待同步，请稍后重试";Game.pending={};return end
 if self:HasOwnership()then
  if not Game.authorityReady then return end
  ReceiveGameCommand(q.id,q.seq,q.packet)
  ack=Game.state.acks[q.id];if ack and ack.seq>=q.seq then table.remove(Game.pending,1)end
 elseif U.Time.time-q.last>.65 then q.last=U.Time.time;self:SendMessageToOwner("ReceiveGameCommand",q.id,q.seq,q.packet)end
end
local audioBanks={}
function RegisterAudioBank(id,bank)if id=="world"or id=="foes"then audioBanks[id]=bank end end
function RemoveAudioBank(id)audioBanks[id]=nil end
function PlayAudioBank(id,name,volume)local bank=audioBanks[id];return bank and bank.Play(name,volume)or false end
function LoopAudioBank(id,name,on)local bank=audioBanks[id];return bank and bank.Loop(name,on)or nil end
function GetPresentationTime()
 if not Game.state then return 0 end
 return Game.state.t+(Game.owner and math.min(.05,Game.acc)or math.min(.25,math.max(0,U.Time.time-(Game.receivedAt or U.Time.time))))
end
function GetRenderState()return Game.ready and Game.state or nil end
function GetArenaRoot()return self.transform end
function GetConfig()return Game.config end
function GroundY(x,z)return Game.layout and Game.layout.GroundY(x,z) or 0 end
function TowerY(id)return Game.layout and Game.layout.TowerY(id) or 0 end
local function groundPoint(x,z,offset)
 return self.transform:TransformPoint(U.Vector3(x,GroundY(x,z)+(offset or .08),z))
end
function GetLocalSettings()return Game.settings end
local function towerBenefit(current,nextCfg)
 if not nextCfg then return "已达最高阶"end
 local parts={}
 local function percent(value)
  local n=math.floor(math.abs(value)*1000+.5)/10
  return string.format("%g%%",n)
 end
 local function add(key,label,inverse)
  local a,b=current[key],nextCfg[key]
  if not b or a==b then return end
  if not a or a<=0 then parts[#parts+1]="新增"..label;return end
  local gain=inverse and (a/b-1)or(b/a-1)
  parts[#parts+1]=label..(gain>=0 and "提升 "or "降低 ")..percent(gain)
 end
 add("damage","伤害");add("interval","攻击速度",true);add("range","攻击距离")
 add("radius","爆炸范围");add("hp","晶壁耐久");add("duration","持续时间")
 add("income","金币产出");add("cap","每波收益上限");add("slow","减速效果")
 return table.concat(parts," · ")
end
function GetGameView()
 if not Game.ready then return nil end
 local S,C=Game.state,Game.config;local id=Game.localId or localIdentity();local p=id and S.players[id];if not p then return nil end
 local sale=S.saleVote;local slot=(sale and sale.requester~=id and sale.expires>S.t)and sale.slot or (p.selectedSlot or 1);local t=S.towers[slot];local tower=nil
 if t then
  local nextCfg=t.tier<3 and C.towers[t.type][t.tier+1]or nil;local owner=S.players[t.owner]
  local current=C.towers[t.type][t.tier<4 and t.tier or t.branch]
  local benefit=nextCfg and ("下一阶："..towerBenefit(current,nextCfg))or(t.tier==3 and ("A："..C.branchDescriptions[t.type][1].."\n".."B："..C.branchDescriptions[t.type][2])or C.branchDescriptions[t.type][t.branch=="a"and 1 or 2])
  tower={type=t.type,tier=t.tier,branch=t.branch,name=t.tier==4 and C.branches[t.type][t.branch=="a"and 1 or 2]or C.names[t.type],description=C.descriptions[t.type],nextBenefit=benefit,nextCost=nextCfg and nextCfg.cost,branchACost=C.towers[t.type].a.cost,branchBCost=C.towers[t.type].b.cost,canUpgrade=t.tier<4 and not p.spectator,canSell=not p.spectator,sellLabel=sale and sale.slot==slot and (sale.requester==id and "等待队友确认"or "确认拆除")or "拆除",sellWaiting=sale and sale.slot==slot and sale.requester==id,ownerName=owner and owner.name or"离线仔仔",invested=t.invested}
 end
 local cooldowns={};for k,v in pairs(p.cooldowns or {})do cooldowns[k]=math.max(0,v-S.t)end
 local votes={forest=0,snow=0,desert=0,night=0};local players={}
 for _,other in pairs(S.players)do if other.online then players[#players+1]={id=other.id,name=other.name,hp=other.hp,maxHp=other.maxHp,loadout=other.loadout};local vote=S.votes[other.id];if vote then votes[vote]=votes[vote]+1 end end end
 local reviveTarget=nil;for _,other in pairs(S.players)do if other.online and other.hp<=0 and other.id~=id and (other.x-p.x)^2+(other.z-p.z)^2<7.29 then reviveTarget=other.id;break end end
 local result=S.result and {won=S.result.won,outcome=S.result.won and"victory"or"defeat",description="守过 "..S.result.waves.." 波 · 晶核 "..S.core.."/20 · 本局伤害 "..math.floor(p.contribution.damage),wavesCleared=S.result.waves}or nil
 local quota=Game.sim.GetBuildQuota(S,id)
 local readyCount,readyTotal=0,0
 for _,member in pairs(S.players)do if member.online and not member.spectator then readyTotal=readyTotal+1;if member.ready then readyCount=readyCount+1 end end end
 local introductions={};for _,kind in ipairs(C.introductions[S.wave+1]or{})do local entry=C.bestiary[kind];introductions[#introductions+1]={kind=kind,name=entry.name,asset=entry.asset,trait=entry.trait,detail=entry.detail,tip=entry.tip}end
 return {leaderboard=Rank,endless=S.endless==true,completedWaves=S.completedWaves or 0,isReady=p.ready==true,readyCount=readyCount,readyTotal=readyTotal,round=S.round,maxWaves=#C.waves,introductions=introductions,phase=S.phase,theme=S.theme,wave=S.wave,phaseLeft=math.max(0,S.deadline-S.t),coreHp=S.core,coreMax=C.core,gold=Game.sim.GetAvailableGold(S,id),hp=p.hp,maxHp=p.maxHp,loadout=p.loadout,selectedSlot=slot,tower=tower,canBuild=not t and S.layout~=nil and quota.allowed,buildQuota=quota,respawnLeft=p.hp<=0 and math.max(0,(p.downUntil or S.t)-S.t)or 0,respawnPaused=S.phase~="WAVE_ACTIVE",growthPoints=p.growthPoints,cooldowns=cooldowns,votes=votes,candidates=S.candidates,message=Game.error or p.message or"镜头跟随仔仔，拖拽查看，松手回位；J攻击 K/L技能 Shift闪避",result=result,players=players,teamFunds=S.teamFunds,economyQuote=S.economyQuote,saleVote=S.saleVote,slotCount=S.layout and #S.layout.slots or 8,anyTowerSlot=true,localPlayerId=id,effects=S.effects,settings=Game.settings,reviveTarget=reviveTarget,reviveProgress=p.revive and math.min(1,(S.t-p.revive.t0)/2)or 0}
end

-- Square authored terrain: crop to fill the viewport and pan only within its footprint.
local function cameraFrame(aspect)
 local sine=math.sin(math.rad(65))
 local b=Game.layout.GetCameraBounds()
 local size=math.min(30/math.max(.1,aspect),19.5*sine)
 size=math.min(size,math.max(5,size*(Game.zoom or 1)))
 return size,size*aspect,size/sine
end
function SetCameraUiBlocked(value)Game.cameraUiBlocked=value==true end
function SetMapPointerGuard(callback)Game.pointerGuard=callback end
function GetTowerTapSerial()return Game.towerTapSerial or 0 end
local function pickTower(x,y,camera)
 if not Game.state.layout then return end
 local best,dist=nil,math.huge
 for _,s in ipairs(Game.state.layout.slots)do
  local p=camera:WorldToScreenPoint(groundPoint(s.x,s.z,TowerY(s.id)-GroundY(s.x,s.z)))
  local radius
  if camera.orthographic~=false then radius=math.max(24,camera.pixelHeight/camera.orthographicSize*.55)
  else radius=math.max(24,math.min(camera.pixelHeight*.12,camera.pixelHeight*.55/(math.max(.01,p.z)*math.tan(math.rad(camera.fieldOfView*.5)))))end
  local q=(p.x-x)^2+(p.y-y)^2
  if p.z>=camera.nearClipPlane and p.z<=camera.farClipPlane and q<radius*radius and q<dist then best,dist=s.id,q end
 end
 if best then SubmitGameAction({kind="selectSlot",slot=best});Game.towerTapSerial=(Game.towerTapSerial or 0)+1 end
end
-- Same tier/branch configuration used by simulation targeting. Non-attacking
-- structures deliberately have no attack radius even if their config has a utility range.
function GetSelectedTowerRange()
 if not Game.ready then return nil end
 local p=Game.localId and Game.state.players[Game.localId]
 local t=p and Game.state.towers[p.selectedSlot]
 if not t or t.type=="economy" or t.type=="barrier" then return nil end
 local cfg=Game.config.towers[t.type][t.tier==4 and t.branch or t.tier]
 local camera=CS.DouyinCameraService.GetCamera()
 if not cfg or not camera then return nil end
 local points={}
 for i=0,96 do
  local a=i*2*math.pi/96;local x,z=t.x+math.cos(a)*cfg.range,t.z+math.sin(a)*cfg.range
  points[#points+1]=camera:WorldToViewportPoint(groundPoint(x,z,.07))
 end
 return {radius=cfg.range,points=points}
end
function GetSelectedTowerViewport()
 local id=Game.localId;local p=id and Game.state.players[id]
 local s=p and Game.state.layout and Game.state.layout.slots[p.selectedSlot]
 local camera=CS.DouyinCameraService.GetCamera()
 if not s or not camera then return nil end
 return camera:WorldToViewportPoint(groundPoint(s.x,s.z,TowerY(s.id)-GroundY(s.x,s.z)))
end
local function canPanAt(x,y,camera)
 if Game.pointerGuard and Game.pointerGuard(x,y) then return false end
 if Game.cameraUiBlocked then return false end
 local r=camera.pixelRect
 local nx,ny=(x-r.x)/math.max(1,r.width),(y-r.y)/math.max(1,r.height)
 if nx<0 or nx>1 or ny<.16 or ny>.86 then return false end
 -- Reserve the native movement stick, attack buttons and footer controls.
 if ny<.43 and (nx<.30 or nx>.70)then return false end
 return true
end
local function canTapAt(x,y,camera)
 if Game.cameraUiBlocked or (Game.pointerGuard and Game.pointerGuard(x,y,true))then return false end
 local r=camera.pixelRect
 return x>=r.x and x<=r.x+r.width and y>=r.y+r.height*.16 and y<=r.y+r.height*.86
end
local function releaseCameraDrag()
 local d=Game.panDrag
 if d and d.active and d.canPan~=false then
  Game.panX=Game.renderPanX or Game.panX;Game.panZ=Game.renderPanZ or Game.panZ
  Game.panReturnAt=U.Time.time+.12
 end
 Game.panDrag=nil
end
local function updateCameraDrag(camera)
 if U.Input.touchCount>1 or Game.cameraUiBlocked then releaseCameraDrag();return end
 local input=U.Input
 local x,y,down,ended,identity,canceled
 if input.touchCount>0 then
  for i=0,input.touchCount-1 do
   local t=input.GetTouch(i)
   if (Game.panDrag and Game.panDrag.id==t.fingerId)or(not Game.panDrag and t.phase==U.TouchPhase.Began and canTapAt(t.position.x,t.position.y,camera))then
    x,y,identity=t.position.x,t.position.y,t.fingerId
    down=t.phase==U.TouchPhase.Began
    canceled=t.phase==U.TouchPhase.Canceled
    ended=t.phase==U.TouchPhase.Ended or canceled
    break
   end
  end
 else
  if Game.panDrag and Game.panDrag.id~=-1 then releaseCameraDrag();return end
  local p=input.mousePosition;x,y,identity=p.x,p.y,-1
  down=input.GetMouseButtonDown(0);ended=not input.GetMouseButton(0)
 end
 if not x then releaseCameraDrag();return end
 if down and canTapAt(x,y,camera)then Game.panDrag={x=x,y=y,sx=x,sy=y,id=identity,active=false,canPan=canPanAt(x,y,camera)} end
 local d=Game.panDrag
 if d and d.id==identity then
  if ended then
   if not d.active and not canceled then pickTower(x,y,camera)end
   releaseCameraDrag();return
  end
  if not d.active and (x-d.sx)^2+(y-d.sy)^2>36 then d.active=true end
  if d.active and d.canPan~=false and Game.settings.camera=="top" then
   local perPixel=2*camera.orthographicSize/math.max(1,camera.pixelHeight)
   Game.panX=(Game.panX or 32)-(x-d.x)*perPixel
   Game.panZ=(Game.panZ or 34)-(y-d.y)*perPixel/math.sin(math.rad(65))
  end
  d.x,d.y=x,y
 end
end

local function setCamera()
 local top=Game.settings.camera=="top";Game.cameraTargetDistance=top and 6 or 5.5;Game.cameraTargetPitch=top and 65 or 18
 local camera=CS.DouyinCameraService.GetCamera()
 if camera then
  if not Game.savedProjection then Game.savedProjection={orthographic=camera.orthographic,size=camera.orthographicSize,near=camera.nearClipPlane}end
  -- Orthographic tactical view keeps lanes readable; SDK remains in charge of the camera transform.
  -- A negative near plane includes the lower viewport even when this SDK caps its follow distance.
  camera.orthographic=top;camera.nearClipPlane=top and -40 or math.max(.01,Game.savedProjection.near)
  if top then
   local aspect=math.max(.1,camera.pixelWidth/math.max(1,camera.pixelHeight))
   local input=U.Input
   if not Game.cameraUiBlocked then
    local scroll=input.mouseScrollDelta.y
    if math.abs(scroll)>.001 then Game.zoom=math.max(.3,math.min(1,(Game.zoom or 1)*math.exp(-scroll*.08)))end
    if input.touchCount==2 then
     local a,b=input.GetTouch(0),input.GetTouch(1)
     local dx,dy=a.position.x-b.position.x,a.position.y-b.position.y
     local distance=math.sqrt(dx*dx+dy*dy)
     local r=camera.pixelRect
     local function central(t)
      local nx,ny=(t.position.x-r.x)/r.width,(t.position.y-r.y)/r.height
      return nx>=.30 and nx<=.70 and ny>=.23 and ny<=.78 and canPanAt(t.position.x,t.position.y,camera)
     end
     local pair=tostring(a.fingerId)..":"..tostring(b.fingerId)
     if Game.pinchPair~=pair then Game.pinchPair=pair;Game.pinchAllowed=central(a)and central(b);Game.pinchDistance=nil end
     if not central(a)or not central(b)then Game.pinchAllowed=false end
     if Game.pinchAllowed then
      if Game.pinchDistance and distance>10 then Game.zoom=math.max(.3,math.min(1,(Game.zoom or 1)*Game.pinchDistance/distance))end
      Game.pinchDistance=distance
     else Game.pinchDistance=nil end
     releaseCameraDrag()
    else Game.pinchDistance=nil;Game.pinchPair=nil;Game.pinchAllowed=false end
   else Game.pinchDistance=nil;Game.pinchPair=nil;Game.pinchAllowed=false end
   local size,hx,hz=cameraFrame(aspect)
   local b=Game.layout.GetCameraBounds()
   camera.orthographicSize=size
   local a=Game.localActor and Game.localActor.position
   local targetX=math.max(b.minX+hx,math.min(b.maxX-hx,a and a.x or b.centreX))
   local targetZ=math.max(b.minZ+hz,math.min(b.maxZ-hz,a and a.z or b.centreZ))
   Game.panX=math.max(b.minX+hx,math.min(b.maxX-hx,Game.panX or targetX))
   Game.panZ=math.max(b.minZ+hz,math.min(b.maxZ-hz,Game.panZ or targetZ))
   updateCameraDrag(camera)
   if not Game.panDrag and U.Time.time>=(Game.panReturnAt or 0) then
    local ease=1-math.exp(-2.2*math.min(.1,U.Time.deltaTime))
    Game.panX=Game.panX+(targetX-Game.panX)*ease
    Game.panZ=Game.panZ+(targetZ-Game.panZ)*ease
   end
   Game.panX=math.max(b.minX+hx,math.min(b.maxX-hx,Game.panX))
   Game.panZ=math.max(b.minZ+hz,math.min(b.maxZ-hz,Game.panZ))
  else updateCameraDrag(camera) end
 end
 if not Game.cameraApplied then Game.cameraDistance=Game.cameraDistance or 6;Game.cameraPitch=Game.cameraPitch or 18;Game.cameraTransition=1;Game.cameraApplied=true end
end

local function updateLocalPlayer()
 local id=localIdentity();local actor=Game.localActor;if not actor or not id then return end
 local p=Game.state.players[id];if not p then return end
 local actionTime=GetPresentationTime()
 if p.actionKind and p.hp>0 and actionTime>=(p.actionAt or 0) and actionTime<(p.actionUntil or 0) and (Game.heroFacingSeq~=p.actionSeq or Game.heroFacingRound~=Game.state.round)then
  local dx,dz=(p.actionX or p.x+(p.fx or 0))-p.x,(p.actionZ or p.z+(p.fz or 1))-p.z
  if dx*dx+dz*dz>.001 then actor.rotation=U.Quaternion.LookRotation(self.transform:TransformDirection(U.Vector3(dx,0,dz)))end
  Game.heroFacingSeq=p.actionSeq;Game.heroFacingRound=Game.state.round
 end
 if not Game.savedActor then Game.savedActor={speed=actor.speed,scale=actor.scale};Game.savedPitch=CS.DouyinCameraService.GetPitch();Game.savedYaw=CS.DouyinCameraService.GetYaw()end
 local desiredSpeed=Game.config.hero[p.loadout].speed
 if Game.walkSpeed~=desiredSpeed then actor.speed=desiredSpeed;Game.walkSpeed=desiredSpeed end
 -- Cloud mobile previews may run in a Linux player, so isMobilePlatform alone
 -- must never select the desktop displacement workaround.
 if U.Input.touchCount>0 then Game.touchClient=true end
 local platform=U.Application.platform
 local desktop=not Game.touchClient and not U.Application.isMobilePlatform and
  (platform==U.RuntimePlatform.OSXPlayer or platform==U.RuntimePlatform.OSXEditor or
   platform==U.RuntimePlatform.WindowsPlayer or platform==U.RuntimePlatform.WindowsEditor)
 local immobile=p.hp<=0 or desktop
 if Game.immobile~=immobile then Game.immobile=immobile;actor:Immobilize(immobile)end
 if not Game.nativeWalkReady then
  Game.nativeWalkReady=true;actor.scale=2.8;Game.savedCanFly=actor:CanFly()
  if actor:IsFlying() then actor:StopFly() end
  actor:DisableFly(true)
 end
 if p.teleport and Game.lastTeleport~=p.teleport.id then local target=groundPoint(p.teleport.x,p.teleport.z);if p.teleport.kind=="blink"then actor:Teleport(target)else actor:Teleport(target,U.Quaternion.Euler(0,180,0));Game.yawUntil=U.Time.time+2.5 end;Game.lastTeleport=p.teleport.id end
 local bounds=Game.layout.GetBounds();local spawn=Game.layout.GetSpawn()
 if not Game.placed and not p.teleport then actor:Teleport(groundPoint(spawn.x,spawn.z),U.Quaternion.Euler(0,180,0));Game.placed=true;Game.yawUntil=U.Time.time+2.5 end
 if p.hp>0 and p.motion and Game.lastMotion~=p.motion.id and GetPresentationTime()<=p.motion.ends+.5 then
  local m=p.motion;local f=Game.sim.MotionProgress(m,GetPresentationTime());local pos=groundPoint(math.max(bounds.minX,math.min(bounds.maxX,m.sx+(m.ex-m.sx)*f)),math.max(bounds.minZ,math.min(bounds.maxZ,m.sz+(m.ez-m.sz)*f)));actor:Teleport(pos)
  if m.kind=="attackApproach"then
   local dx,dz=m.ex-m.sx,m.ez-m.sz
   if dx*dx+dz*dz>.001 then actor.rotation=U.Quaternion.LookRotation(U.Vector3(dx,0,dz))end
  end
  if f>=.99 then Game.lastMotion=m.id end
 end
 local localPos=self.transform:InverseTransformPoint(actor.position)
 if localPos.y< -10 or math.abs(localPos.x)>36 or math.abs(localPos.z)>36 then actor:Teleport(groundPoint(spawn.x,spawn.z));localPos=self.transform:InverseTransformPoint(actor.position)end
 -- Keyed local ult cues share the same bounded hurt-shake envelope, never sum amplitudes.
 if Game.ultCueRound~=Game.state.round then Game.lastUltCue=0;Game.ultCueRound=Game.state.round end
 for _,cue in ipairs(Game.state.effects or {})do
  if cue.ultKey and tostring(cue.owner)==tostring(id)then
   local key=tonumber(cue.ultKey)or 0
   if key>(Game.lastUltCue or 0)then
    Game.lastUltCue=key
    local age=GetPresentationTime()-(cue.t0 or 0)
    if age>=0 and age<.3 and not(Game.shakeUntil and U.Time.time<Game.shakeUntil)then Game.shakeUntil=U.Time.time+.16 end
   end
  end
 end
 if p.hitAt and Game.lastHitAt~=p.hitAt then
  if GetPresentationTime()-p.hitAt<.3 then Game.shakeUntil=U.Time.time+.16 end;Game.lastHitAt=p.hitAt
 end
 setCamera()
 local input=U.Input
 local mx,mz=Game.moveX or 0,Game.moveZ or 0
 local kx=(input.GetKey(U.KeyCode.D)and 1 or 0)-(input.GetKey(U.KeyCode.A)and 1 or 0)
 local kz=(input.GetKey(U.KeyCode.W)and 1 or 0)-(input.GetKey(U.KeyCode.S)and 1 or 0)
 if kx~=0 or kz~=0 then mx,mz=kx,kz end
 local n=math.sqrt(mx*mx+mz*mz)
 if n>.01 then Game.lastInput=string.format("k %.1f %.1f evt %.1f %.1f",kx,kz,Game.moveX or 0,Game.moveZ or 0)end
 -- Formal desktop preview reports correct joystick events but applies a stale native movement basis.
 -- Own desktop displacement once; mobile keeps the native locomotion implementation.
 if desktop and p.hp>0 and n>.05 and not(p.motion and Game.state.t<p.motion.ends)then
  if n>1 then mx,mz=mx/n,mz/n end
  local c=CS.DouyinCameraService.GetCamera()
  if c then
   local r,f=c.transform.right,c.transform.forward
   local rn=math.max(.001,math.sqrt(r.x*r.x+r.z*r.z));local fn=math.max(.001,math.sqrt(f.x*f.x+f.z*f.z))
   local dx,dz=r.x/rn*mx+f.x/fn*mz,r.z/rn*mx+f.z/fn*mz
   local dt=math.min(.05,U.Time.deltaTime);local old=actor.position
   local controller=actor.gameObject:GetComponentInChildren(typeof(U.CharacterController))
   Game.desktopController=controller and "CC"or"position"
   if controller and controller.enabled then
    controller:Move(U.Vector3(dx*desiredSpeed*dt,-2*dt,dz*desiredSpeed*dt))
   else
    local target=self.transform:InverseTransformPoint(U.Vector3(old.x+dx*desiredSpeed*dt,old.y,old.z+dz*desiredSpeed*dt))
    actor.position=groundPoint(math.max(bounds.minX,math.min(bounds.maxX,target.x)),math.max(bounds.minZ,math.min(bounds.maxZ,target.z)))
   end
   actor.rotation=U.Quaternion.LookRotation(U.Vector3(dx,0,dz))
  end
 end
 -- Clamp only when the actor actually leaves the playable terrain; never rewrite height each frame.
 if localPos.x<bounds.minX or localPos.x>bounds.maxX or localPos.z<bounds.minZ or localPos.z>bounds.maxZ then
  actor:Teleport(groundPoint(math.max(bounds.minX,math.min(bounds.maxX,localPos.x)),math.max(bounds.minZ,math.min(bounds.maxZ,localPos.z))))
 end
 if input.GetKeyDown("j")then SubmitGameAction({kind="attackHold",value=true})end
 if input.GetKeyUp("j")then SubmitGameAction({kind="attackHold",value=false})end
 if input.GetKeyDown("k")then SubmitGameAction({kind="skill1"})end
 if input.GetKeyDown("l")then SubmitGameAction({kind="skill2"})end
 if input.GetKeyDown("left shift")then SubmitGameAction({kind="dash"})end
 if input.GetKeyDown("r")then SubmitGameAction({kind="revive"})end
 if input.GetKeyDown("v")then SubmitGameAction({kind="camera"})end
 if input.GetKeyDown("e")and Game.state.layout then
  local nearest,d=p.selectedSlot,math.huge;for i,s in ipairs(Game.state.layout.slots)do local q=(s.x-localPos.x)^2+(s.z-localPos.z)^2;if q<d then nearest=i;d=q end end;SubmitGameAction({kind="selectSlot",slot=nearest})
 end
end
function Update()
 if not InitializeGame()then return end
 if not Game.net or not CS.DouyinNetService.isNetworkSettled then return end
 local owner=self:HasOwnership()
 if owner then
  if not Game.owner then Game.owner=true;Game.authorityReady=false end
  if not takeOwnership()then return end
  Game.sim.SetRoster(Game.state,collectRoster())
  retryCommands()
  Game.acc=Game.acc+math.min(.1,U.Time.deltaTime)*math.max(.1,BattleSpeed or 1)
  local steps=0;while Game.acc>=.05 and steps<20 do Game.sim.Step(Game.state,.05);Game.acc=Game.acc-.05;steps=steps+1 end
  if U.Time.time>=Game.publishAt then local ok,err=pcall(publish);if not ok then Game.error="网络状态写入失败";hostLogger:warnOnce("publish",err)end end
 else Game.owner=false;Game.authorityReady=false;readSnapshot(false);retryCommands()end
 updateLocalPlayer()
 updateRanking()
end
function LateUpdate()
 if not Game.localActor or not Game.cameraApplied then return end
 if Game.settings.camera~="top" and Game.cameraTransition and Game.cameraTransition>0 then
  local f=math.min(1,U.Time.deltaTime*6);Game.cameraDistance=Game.cameraDistance+(Game.cameraTargetDistance-Game.cameraDistance)*f;Game.cameraPitch=Game.cameraPitch+(Game.cameraTargetPitch-Game.cameraPitch)*f
  CS.DouyinCameraService.SetDistance(Game.cameraDistance);CS.DouyinCameraService.SetPitch(Game.cameraPitch);CS.DouyinCameraService.SetOffset(U.Vector3(0,.65,0));Game.cameraTransition=Game.cameraTransition-U.Time.deltaTime
 end
 if Game.settings.camera~="top" and ((Game.yawUntil or 0)>U.Time.time and not Game.looking and U.Time.time-Game.lookAt>.5) then
  local yaw=CS.DouyinCameraService.GetYaw();if yaw then local diff=U.Mathf.DeltaAngle(yaw,Game.settings.camera=="top" and 0 or 180);local step=math.max(-180*U.Time.deltaTime,math.min(180*U.Time.deltaTime,diff));CS.DouyinCameraService.SetYaw(yaw+step)end
 end
 -- Reaffirm supported follow parameters after yaw; never write the camera transform.
 CS.DouyinCameraService.SetDistance(Game.settings.camera=="top" and 6 or (Game.cameraDistance or Game.cameraTargetDistance or 6))
 local shake=0
 if Game.shakeUntil and U.Time.time<Game.shakeUntil and not Game.panDrag then
  local age=.16-(Game.shakeUntil-U.Time.time)
  shake=math.sin(age*math.pi/.16)*.045
 end
 if Game.settings.camera=="top" then
  -- Cancel the avatar follow displacement through the supported target offset.
  -- Terrain-bounded pan centre; dragging never rotates the tactical view.
  local bnd=Game.layout.GetCameraBounds()
  local a=Game.localActor.position
  local tx,tz=Game.panX or bnd.centreX,Game.panZ or bnd.centreZ
  Game.renderPanX=Game.renderPanX or tx;Game.renderPanZ=Game.renderPanZ or tz
  if Game.panDrag and Game.panDrag.active then
   local dt=math.min(.05,U.Time.deltaTime);local alpha=1-math.exp(-18*dt)
   local dx,dz=(tx-Game.renderPanX)*alpha,(tz-Game.renderPanZ)*alpha
   local length=math.sqrt(dx*dx+dz*dz);local maxStep=28*dt
   if length>maxStep then dx=dx*maxStep/length;dz=dz*maxStep/length end
   Game.renderPanX=Game.renderPanX+dx;Game.renderPanZ=Game.renderPanZ+dz
  else Game.renderPanX=tx;Game.renderPanZ=tz end
  local centre=U.Vector3(Game.renderPanX,bnd.focusY,Game.renderPanZ)
  CS.DouyinCameraService.SetYaw(0)
  CS.DouyinCameraService.SetPitch(65)
  local camera=CS.DouyinCameraService.GetCamera()
  if camera then
   -- SDK follows a character anchor above the feet. Measure that fixed projection bias
   -- once after the view settles, so the lower boundary reaches the crystal correctly.
   Game.calibrateAt=Game.calibrateAt or (U.Time.time+.8)
   if not Game.cameraBias and U.Time.time>Game.calibrateAt and Game.lastCameraCentre and not Game.panDrag and not Game.looking and math.abs(Game.moveX or 0)+math.abs(Game.moveZ or 0)<.01 then
    local ray=camera:ViewportPointToRay(U.Vector3(.5,.5,0))
    if math.abs(ray.direction.y)>.1 then
     local t=(bnd.focusY-ray.origin.y)/ray.direction.y
     local hit=U.Vector3(ray.origin.x+ray.direction.x*t,ray.origin.y+ray.direction.y*t,ray.origin.z+ray.direction.z*t)
     Game.cameraBias={x=math.max(-2,math.min(2,Game.lastCameraCentre.x-hit.x)),z=math.max(-2,math.min(2,Game.lastCameraCentre.z-hit.z))}
    end
   end
   local b=Game.cameraBias or {x=0,z=-.65}
   local dy,dz=centre.y-a.y,centre.z+b.z-a.z
   local sn,cs=math.sin(math.rad(65)),math.cos(math.rad(65))
   local offset=U.Vector3(centre.x+b.x-a.x,cs*dy+sn*dz,-sn*dy+cs*dz)
   CS.DouyinCameraService.SetOffset(offset+U.Vector3(0,shake,0))
   Game.lastCameraCentre={x=centre.x+b.x,z=centre.z+b.z}
  end
 else
  CS.DouyinCameraService.SetOffset(U.Vector3(0,.65,0))
 end
end

function OnApplicationFocus(focus)if not focus then Game.moveX=0;Game.moveZ=0;Game.walking=false;pcall(function()if Game.localActor then Game.localActor:StopMove()end end);SubmitGameAction({kind="attackHold",value=false})end end
function OnDestroy()
 if Game.originalRootPosition then self.transform.position=Game.originalRootPosition end
 Game.net=false
 if Game.onMoveStart then CS.DouyinInputService.onMoveInputStart:RemoveListener(Game.onMoveStart)end
 if Game.onMovePerform then CS.DouyinInputService.onMoveInputPerform:RemoveListener(Game.onMovePerform)end
 if Game.onMoveCancel then CS.DouyinInputService.onMoveInputCancel:RemoveListener(Game.onMoveCancel)end
 pcall(function()local camera=CS.DouyinCameraService.GetCamera();local saved=Game.savedProjection;if camera and saved then camera.orthographic=saved.orthographic;camera.orthographicSize=saved.size;camera.nearClipPlane=saved.near end end)
 pcall(function()if Game.localActor then Game.localActor:StopMove();Game.localActor:Immobilize(false);if Game.savedCanFly then Game.localActor:EnableFly(true) end;if Game.savedActor then Game.localActor.speed=Game.savedActor.speed;Game.localActor.scale=Game.savedActor.scale end end end)
 pcall(function()CS.DouyinInputService.onLookInputStart:RemoveListener(Game.onLookStart);CS.DouyinInputService.onLookInputPerform:RemoveListener(Game.onLookStart);CS.DouyinInputService.onLookInputCancel:RemoveListener(Game.onLookEnd)end)
 pcall(function()CS.DouyinCameraService.SetDistance(4);CS.DouyinCameraService.SetPitch(Game.savedPitch or 0);CS.DouyinCameraService.SetOffset(U.Vector3(0,0,0));if Game.savedYaw then CS.DouyinCameraService.SetYaw(Game.savedYaw)end end)
end
function DebugCamera()
 local actor=CS.DouyinActorService.GetLocalActor();local camera=CS.DouyinCameraService.GetCamera();local p=actor and self.transform:InverseTransformPoint(actor.position);return {mode=Game.settings.camera,actor=p and {x=p.x,y=p.y,z=p.z},camera=camera and {x=camera.transform.position.x,y=camera.transform.position.y,z=camera.transform.position.z},rootY=self.transform.position.y,pitch=CS.DouyinCameraService.GetPitch()}
end
function DebugDump()
 local S=Game.state;local enemies=0;for _,e in pairs(S and S.enemies or {})do if e.hp>0 then enemies=enemies+1 end end
 return {ready=Game.ready,net=Game.net,owner=Game.owner,authorityReady=Game.authorityReady,phase=S and S.phase,wave=S and S.wave,round=S and S.round,core=S and S.core,t=S and S.t,enemies=enemies,queued=S and #S.spawnQueue,revision=Game.applied,packetBytes=Game.packetBytes,localId=Game.localId,error=Game.error,view=GetGameView()}
end
function DebugGame(kind,arg)
 if not Game.ready or not Game.net or not self:HasOwnership()then return false end
 Game.sim.Debug(Game.state,kind,arg);Game.publishAt=0;return DebugDump()
end
function DebugAct(a)return SubmitGameAction(a)end

function GetLocalPlayerId()return Game.localId end
