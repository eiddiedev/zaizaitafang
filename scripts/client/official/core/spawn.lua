local RuntimeScope = require("official.core.runtime_scope")
local Registry = require("official.core.spawn_registry")
local UnityObject = CS.UnityEngine.Object
local Spawn = {}

Spawn.Lifetime = { Room = "Room", Actor = "Actor" }
local MARKER = "runtime-builtin___NetSpawnTarget__.lua"
local allowedOptions = { networked = true, lifetime = true, actor = true, position = true, rotation = true }

local function validateOptions(options, onSpawn)
    if type(options) ~= "table" or type(options.networked) ~= "boolean" then
        error("spawn_networked_boolean_required", 3)
    end
    for name in pairs(options) do
        if not allowedOptions[name] then
            error("spawn_unknown_option: " .. tostring(name), 3)
        end
    end
    if onSpawn ~= nil and type(onSpawn) ~= "function" then
        error("spawn_invalid_callback", 3)
    end
    if options.rotation ~= nil and options.position == nil then
        error("spawn_rotation_requires_position", 3)
    end
    if not options.networked then
        if options.lifetime ~= nil or options.actor ~= nil then
            error("spawn_local_network_options", 3)
        end
    elseif options.lifetime == Spawn.Lifetime.Actor then
        if options.actor == nil then
            error("spawn_actor_required", 3)
        end
    elseif options.lifetime ~= Spawn.Lifetime.Room then
        error("spawn_network_lifetime_required", 3)
    elseif options.actor ~= nil then
        error("spawn_room_actor_not_allowed", 3)
    end
end

local function resolveSource(context, path)
    if type(path) ~= "string" then
        error("spawn_source_path_required", 3)
    end
    local scope, reason = RuntimeScope.from(context)
    if scope == nil then
        error(reason or "spawn_resource_unavailable", 3)
    end
    local source, lookupReason = scope:GetGameObjectByPath(path)
    if source == nil then
        error(lookupReason or "spawn_source_missing", 3)
    end
    return source, scope
end

local function prepareNetwork(source, options)
    if DouyinNetService == nil or not DouyinNetService.isNetworkSettled then
        error("spawn_network_not_ready", 3)
    end
    local marker = source:GetDouyinScript(MARKER)
    if marker == nil or marker.script == nil then
        error("spawn_source_not_registered", 3)
    end
    local key = marker.script.GetKey()
    if type(key) ~= "string" or key == "" then
        error("spawn_source_not_registered", 3)
    end
    if options.lifetime == Spawn.Lifetime.Actor then
        local actor = options.actor
        if actor.gameObject == nil or not Registry.isAlive(actor.gameObject)
            or type(actor.NetSpawn) ~= "function" then
            error("spawn_invalid_actor", 3)
        end
    elseif DouyinObjectService == nil or type(DouyinObjectService.NetSpawn) ~= "function" then
        error("spawn_network_service_unavailable", 3)
    end
    return key
end

local function networkSpawn(key, options, callback)
    -- Use the documented overloads; never retry with another signature.
    local actor = options.actor
    if options.lifetime == Spawn.Lifetime.Actor then
        if options.rotation ~= nil then
            return actor:NetSpawn(key, options.position, options.rotation, callback)
        elseif options.position ~= nil then
            return actor:NetSpawn(key, options.position, callback)
        end
        return actor:NetSpawn(key, callback)
    end
    if options.rotation ~= nil then
        return DouyinObjectService.NetSpawn(key, options.position, options.rotation, callback)
    elseif options.position ~= nil then
        return DouyinObjectService.NetSpawn(key, options.position, callback)
    end
    return DouyinObjectService.NetSpawn(key, callback)
end

--- Copy a resource-local source. Only the native GameObject is returned.
function Spawn.spawn(context, sourcePath, options, onSpawn)
    validateOptions(options, onSpawn)
    local source, scope = resolveSource(context, sourcePath)
    if not Registry.isAlive(source) then
        error("spawn_source_destroyed", 2)
    end
    local function register(obj, mode)
        if not Registry.isAlive(obj) then
            return
        end
        Registry.bind(obj, mode)
        -- A cloned resource bootstrap establishes its own Scope. Ordinary
        -- subtrees reuse the source Scope through the existing binding API.
        if RuntimeScope.from(obj) == nil then
            RuntimeScope.bindSubtree(scope, obj)
        end
    end
    if not options.networked then
        local obj
        if options.position ~= nil then
            obj = UnityObject.Instantiate(source, options.position, options.rotation or source.transform.rotation)
        else
            obj = UnityObject.Instantiate(source)
        end
        register(obj, Registry.Mode.Local)
        if Registry.isAlive(obj) and onSpawn ~= nil then
            onSpawn(obj)
        end
        return obj
    end

    local key = prepareNetwork(source, options)
    local callbackDelivered = false
    local callbackObject
    local returnedObject
    local returned = false
    local function initialize(obj)
        if callbackDelivered then
            if obj ~= callbackObject then
                error("spawn_callback_object_mismatch")
            end
            return
        end
        if returned and obj ~= returnedObject then
            error("spawn_callback_object_mismatch")
        end
        callbackDelivered = true
        callbackObject = obj
        register(obj, Registry.Mode.Network)
        if onSpawn ~= nil then
            onSpawn(obj)
        end
    end
    -- Deliberately discard the SDK's second return value (network instance ID).
    local obj = networkSpawn(key, options, initialize)
    returnedObject = obj
    returned = true
    if callbackDelivered and obj ~= callbackObject then
        error("spawn_callback_object_mismatch", 2)
    end
    register(obj, Registry.Mode.Network)
    return obj
end

--- Request destruction using the tracked mode; this is not a completion signal.
function Spawn.destroy(go)
    if go == nil then
        return
    end
    if not Registry.isAlive(go) then
        Registry.release(go)
        return
    end
    local record = Registry.get(go)
    if record ~= nil and record.destroying then
        return
    end
    if record ~= nil and record.mode == Registry.Mode.Local then
        UnityObject.Destroy(go)
        record.destroying = true
        return
    end
    local marker = go:GetDouyinScript(MARKER)
    if marker == nil then
        error("spawn_unknown_instance", 2)
    end
    if DouyinNetService == nil or not DouyinNetService.isNetworkSettled then
        error("spawn_network_not_ready", 2)
    end
    if not marker:IsSpawned() then
        error("spawn_instance_not_ready", 2)
    end
    if not marker:HasOwnership() then
        error("spawn_ownership_required", 2)
    end
    -- The platform decides whether to accept the request. A void return must
    -- not prevent a later retry if the object is still alive.
    Registry.bind(go, Registry.Mode.Network)
    DouyinObjectService.NetDestroy(go, false)
end

return Spawn
