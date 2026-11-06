local NodeLookup = require("official.core.node_lookup")

local RuntimeScope = {}

RuntimeScope.Reason = {
    InvalidRoot = "runtime-resource-scope-invalid-root",
    Unavailable = "runtime-resource-scope-unavailable",
    InvalidScriptId = "runtime-script-invalid-id",
    ScriptNotReady = "runtime-script-not-ready",
    ScriptQueryFailed = "runtime-script-query-failed",
    RuntimeHostUnbound = "runtime-host-unbound",
    RuntimeHostScriptNotReady = "runtime-host-script-not-ready",
    RuntimeHostScriptQueryFailed = "runtime-host-script-query-failed",
}

local Scope = {}
Scope.__index = Scope

local RUNTIME_HOST_ROOT_BOOTSTRAP_REFERENCE_NAME = "runtime-builtin/runtime-host-root-bootstrap.lua"
local RUNTIME_RESOURCE_ROOT_BOOTSTRAP_REFERENCE_NAME = "runtime-builtin/runtime-resource-root-bootstrap.lua"

local scopeByGameObject = setmetatable({}, { __mode = "k" })
local scopeByResourceRoot = setmetatable({}, { __mode = "k" })

local function resolveGameObject(value)
    if value == nil then
        return nil
    end

    local ok, gameObject = pcall(function()
        return value.gameObject
    end)
    if ok and gameObject ~= nil then
        return gameObject
    end
    return value
end

local function resolveTransform(value)
    local gameObject = resolveGameObject(value)
    if gameObject == nil then
        return nil
    end

    local ok, transform = pcall(function()
        return gameObject.transform
    end)
    if ok and transform ~= nil then
        return transform
    end

    ok, transform = pcall(function()
        return value.transform
    end)
    if ok then
        return transform
    end
    return nil
end

local function bindGameObject(scope, gameObject)
    if gameObject == nil then
        return
    end

    local previousScope = scopeByGameObject[gameObject]
    if previousScope ~= nil and previousScope ~= scope then
        previousScope.members[gameObject] = nil
    end
    scopeByGameObject[gameObject] = scope
    scope.members[gameObject] = true
end

local function normalizeScriptId(scriptId)
    if type(scriptId) ~= "string" or scriptId == "" then
        return nil
    end
    local runtimeScriptId = string.gsub(scriptId, "/", "_")
    return runtimeScriptId
end

local function hasBuiltinMarker(gameObject, referenceName)
    local runtimeScriptId = normalizeScriptId(referenceName)
    if runtimeScriptId == nil then
        return false
    end

    local ok, component = pcall(function()
        return gameObject:GetDouyinScript(runtimeScriptId)
    end)
    return ok and component ~= nil
end

local function isNestedScopeRoot(scope, gameObject)
    if gameObject == scope.resourceRoot then
        return false
    end
    return hasBuiltinMarker(gameObject, RUNTIME_RESOURCE_ROOT_BOOTSTRAP_REFERENCE_NAME)
        or hasBuiltinMarker(gameObject, RUNTIME_HOST_ROOT_BOOTSTRAP_REFERENCE_NAME)
end

local function collectSubtreeGameObjects(scope, root, stopAtScopeBoundaries)
    local rootTransform = resolveTransform(root)
    if rootTransform == nil then
        return nil
    end

    local gameObjects = {}
    local pending = { rootTransform }
    while #pending > 0 do
        local transform = table.remove(pending)
        local gameObject = resolveGameObject(transform)
        if gameObject == nil then
            return nil
        end

        if not stopAtScopeBoundaries or not isNestedScopeRoot(scope, gameObject) then
            gameObjects[#gameObjects + 1] = gameObject

            local ok, childCount = pcall(function()
                return transform.childCount
            end)
            if not ok or type(childCount) ~= "number" then
                return nil
            end
            for index = 0, childCount - 1 do
                local childOk, child = pcall(function()
                    return transform:GetChild(index)
                end)
                if not childOk or child == nil then
                    return nil
                end
                pending[#pending + 1] = child
            end
        end
    end
    return gameObjects
end

local function bindSubtree(scope, root, stopAtScopeBoundaries)
    local gameObjects = collectSubtreeGameObjects(scope, root, stopAtScopeBoundaries)
    if gameObjects == nil then
        return false
    end
    for _, gameObject in ipairs(gameObjects) do
        bindGameObject(scope, gameObject)
    end
    return true
end

local function findNearestMarker(value, referenceName)
    local transform = resolveTransform(value)
    while transform ~= nil do
        local gameObject = transform.gameObject
        if hasBuiltinMarker(gameObject, referenceName) then
            return gameObject
        end
        transform = transform.parent
    end
    return nil
end

local function findNearestScopeRoot(value)
    local transform = resolveTransform(value)
    while transform ~= nil do
        local gameObject = transform.gameObject
        if hasBuiltinMarker(gameObject, RUNTIME_RESOURCE_ROOT_BOOTSTRAP_REFERENCE_NAME) then
            return gameObject, false
        end
        if hasBuiltinMarker(gameObject, RUNTIME_HOST_ROOT_BOOTSTRAP_REFERENCE_NAME) then
            return gameObject, true
        end
        transform = transform.parent
    end
    return nil, false
end

local function queryScript(root, scriptId, queryFailedReason, notReadyReason)
    if root == nil then
        return nil, RuntimeScope.Reason.InvalidRoot
    end

    local runtimeScriptId = normalizeScriptId(scriptId)
    if runtimeScriptId == nil then
        return nil, RuntimeScope.Reason.InvalidScriptId
    end

    local ok, script = pcall(function()
        local component = root:GetDouyinScript(runtimeScriptId)
        return component ~= nil and component.script or nil
    end)
    if not ok then
        return nil, queryFailedReason
    end
    if script == nil then
        return nil, notReadyReason
    end
    return script
end

local function createDirectScope(resourceRoot, runtimeHostRoot, isRuntimeHostRoot)
    local existingScope = scopeByResourceRoot[resourceRoot]
    if existingScope ~= nil
        and existingScope.runtimeHostRoot == runtimeHostRoot
        and existingScope.isRuntimeHostRoot == isRuntimeHostRoot then
        bindGameObject(existingScope, resourceRoot)
        return existingScope
    end

    local nodeIndex = NodeLookup.createIndex(resourceRoot)
    if nodeIndex == nil then
        return nil, RuntimeScope.Reason.InvalidRoot
    end

    RuntimeScope.unregister(resourceRoot)
    local scope = setmetatable({
        isRuntimeHostRoot = isRuntimeHostRoot,
        resourceRoot = resourceRoot,
        runtimeHostRoot = runtimeHostRoot,
        nodeIndex = nodeIndex,
        members = setmetatable({}, { __mode = "k" }),
    }, Scope)
    if isRuntimeHostRoot then
        bindGameObject(scope, resourceRoot)
    elseif not bindSubtree(scope, resourceRoot, true) then
        scope.nodeIndex = nil
        return nil, RuntimeScope.Reason.InvalidRoot
    end
    scopeByResourceRoot[resourceRoot] = scope
    return scope
end

function Scope:GetResourceRoot()
    return self.resourceRoot
end

function Scope:GetRuntimeHostRoot()
    if self.runtimeHostRoot ~= nil then
        return self.runtimeHostRoot
    end
    return nil, RuntimeScope.Reason.RuntimeHostUnbound
end

function Scope:GetScript(scriptId)
    if self.nodeIndex == nil then
        return nil, RuntimeScope.Reason.InvalidRoot
    end
    local runtimeScriptId = normalizeScriptId(scriptId)
    if runtimeScriptId == nil then
        return nil, RuntimeScope.Reason.InvalidScriptId
    end

    -- Membership survives reparenting and excludes nested resource scopes.
    -- Each script ID has at most one binding within the scope.
    local matchedObject = nil
    local queryFailed = false
    for gameObject in pairs(self.members) do
        if scopeByGameObject[gameObject] == self then
            local ok, component = pcall(function()
                return gameObject:GetDouyinScript(runtimeScriptId)
            end)
            if not ok then
                queryFailed = true
            elseif component ~= nil then
                matchedObject = gameObject
            end
        end
    end
    if queryFailed then
        return nil, RuntimeScope.Reason.ScriptQueryFailed
    end

    -- Do not cache absence or script tables: a later call may observe readiness.
    if matchedObject == nil then
        return nil, RuntimeScope.Reason.ScriptNotReady
    end
    return queryScript(matchedObject, scriptId, RuntimeScope.Reason.ScriptQueryFailed, RuntimeScope.Reason.ScriptNotReady)
end

function Scope:GetTransformByPath(nodePath)
    return NodeLookup.getIndexedTransformByPath(self.nodeIndex, nodePath)
end

function Scope:GetGameObjectByPath(nodePath)
    return NodeLookup.getIndexedGameObjectByPath(self.nodeIndex, nodePath)
end

-- Compatibility aliases for existing scripts.
Scope.FindTransform = Scope.GetTransformByPath
Scope.FindGameObject = Scope.GetGameObjectByPath

function Scope:GetRuntimeHostScript(scriptId)
    local runtimeHostRoot, reason = self:GetRuntimeHostRoot()
    if runtimeHostRoot == nil then
        return nil, reason
    end

    return queryScript(
        runtimeHostRoot,
        scriptId or "runtime-host.lua",
        RuntimeScope.Reason.RuntimeHostScriptQueryFailed,
        RuntimeScope.Reason.RuntimeHostScriptNotReady
    )
end

function RuntimeScope.registerHostRoot(resourceRoot)
    local rootGameObject = resolveGameObject(resourceRoot)
    if rootGameObject == nil or resolveTransform(rootGameObject) == nil then
        return nil, RuntimeScope.Reason.InvalidRoot
    end
    return createDirectScope(rootGameObject, rootGameObject, true)
end

function RuntimeScope.registerResourceRoot(resourceRoot)
    local rootGameObject = resolveGameObject(resourceRoot)
    local rootTransform = resolveTransform(rootGameObject)
    if rootGameObject == nil or rootTransform == nil then
        return nil, RuntimeScope.Reason.InvalidRoot
    end

    local runtimeHostRoot = findNearestMarker(rootTransform.parent, RUNTIME_HOST_ROOT_BOOTSTRAP_REFERENCE_NAME)
    return createDirectScope(rootGameObject, runtimeHostRoot, false)
end

function RuntimeScope.unregister(resourceRoot, expectedScope)
    local rootGameObject = resolveGameObject(resourceRoot)
    local scope = rootGameObject ~= nil and scopeByResourceRoot[rootGameObject] or nil
    if scope == nil or (expectedScope ~= nil and scope ~= expectedScope) then
        return false
    end

    for gameObject in pairs(scope.members) do
        if scopeByGameObject[gameObject] == scope then
            scopeByGameObject[gameObject] = nil
        end
    end
    scope.nodeIndex = nil
    scope.members = setmetatable({}, { __mode = "k" })
    scopeByResourceRoot[rootGameObject] = nil
    return true
end

function RuntimeScope.discover(value)
    local gameObject = resolveGameObject(value)
    if gameObject == nil then
        return nil, RuntimeScope.Reason.Unavailable
    end

    local resourceRoot, isRuntimeHostRoot = findNearestScopeRoot(gameObject)
    local scope = nil
    if isRuntimeHostRoot then
        scope = RuntimeScope.registerHostRoot(resourceRoot)
    elseif resourceRoot ~= nil then
        scope = RuntimeScope.registerResourceRoot(resourceRoot)
    end

    if scope == nil then
        return nil, RuntimeScope.Reason.Unavailable
    end
    bindGameObject(scope, gameObject)
    return scope
end

function RuntimeScope.from(value)
    local gameObject = resolveGameObject(value)
    local scope = gameObject ~= nil and scopeByGameObject[gameObject] or nil
    if scope ~= nil then
        return scope
    end
    return RuntimeScope.discover(gameObject)
end

function RuntimeScope.resolveResourceRoot(value)
    local scope, reason = RuntimeScope.from(value)
    if scope == nil then
        return nil, reason
    end
    return scope:GetResourceRoot()
end

function RuntimeScope.bindGameObject(scope, value)
    local gameObject = resolveGameObject(value)
    if scope == nil or scope.resourceRoot == nil or gameObject == nil then
        return false, RuntimeScope.Reason.InvalidRoot
    end
    bindGameObject(scope, gameObject)
    return true
end

function RuntimeScope.bindSubtree(scope, value)
    if scope == nil or scope.resourceRoot == nil or not bindSubtree(scope, value) then
        return false, RuntimeScope.Reason.InvalidRoot
    end
    return true
end

return RuntimeScope
