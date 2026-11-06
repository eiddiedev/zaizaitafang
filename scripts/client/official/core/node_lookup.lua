local NodeLookup = {}

NodeLookup.Reason = {
    InvalidRoot = "node-lookup-invalid-root",
    InvalidPath = "node-lookup-invalid-path",
    NotFound = "node-lookup-not-found",
}

local function resolveTransform(value)
    if value == nil then
        return nil
    end

    local ok, transform = pcall(function()
        return value.transform
    end)
    if ok and transform ~= nil then
        return transform
    end

    ok, transform = pcall(function()
        return value.gameObject.transform
    end)
    if ok and transform ~= nil then
        return transform
    end

    local childCount
    ok, childCount = pcall(function()
        return value.childCount
    end)
    if ok and childCount ~= nil then
        return value
    end
    return nil
end

local function resolveGameObject(transform)
    if transform == nil then
        return nil
    end

    local ok, gameObject = pcall(function()
        return transform.gameObject
    end)
    if ok then
        return gameObject
    end
    return nil
end

local function isValidPathSegment(segment)
    if type(segment) ~= "string" or segment == "" or segment == "." or segment == ".." then
        return false
    end
    if segment:find("/", 1, true) ~= nil or segment:find("\\", 1, true) ~= nil then
        return false
    end
    for index = 1, #segment do
        local byte = segment:byte(index)
        if byte <= 31 or byte == 127 then
            return false
        end
    end
    return true
end

local function getTransformName(transform)
    if transform == nil then
        return nil
    end
    local ok, name = pcall(function()
        return transform.name
    end)
    if ok and isValidPathSegment(name) then
        return name
    end
    return nil
end

local function isValidNodePath(path)
    if type(path) ~= "string" then
        return false
    end
    if path == "" then
        return true
    end
    if path:sub(1, 1) == "/" or path:sub(-1) == "/" then
        return false
    end
    if path:find("//", 1, true) ~= nil then
        return false
    end

    for segment in path:gmatch("[^/]+") do
        if not isValidPathSegment(segment) then
            return false
        end
    end
    return true
end

-- Accept one leading slash. When an exact lookup misses, retry once without
-- the GLB root segment so inspected full paths survive Runtime root renames.
local function stripOneLeadingSlash(path)
    if type(path) ~= "string" then
        return path
    end
    if path:sub(1, 1) == "/" then
        return path:sub(2)
    end
    return path
end

local function stripGlbRootSegment(path)
    local separatorIndex = path:find("/", 1, true)
    if separatorIndex == nil then
        return nil
    end
    return path:sub(separatorIndex + 1)
end

local function normalizeNodePath(nodePath)
    local normalizedPath = stripOneLeadingSlash(nodePath)
    if not isValidNodePath(normalizedPath) then
        return nil
    end
    return normalizedPath
end

local function findIndexedValue(valueByPath, normalizedPath, initialRootName)
    local value = valueByPath[normalizedPath]
    if value ~= nil then
        return value
    end

    -- Exact child paths win over root aliases, including after a root rename.
    local root = valueByPath[""]
    if normalizedPath == initialRootName or normalizedPath == getTransformName(resolveTransform(root)) then
        return root
    end

    local rootRelativePath = stripGlbRootSegment(normalizedPath)
    if rootRelativePath == nil then
        return nil
    end
    return valueByPath[rootRelativePath]
end

local function tryFindTransform(rootTransform, path)
    local ok, transform = pcall(function()
        return rootTransform:Find(path)
    end)
    if not ok then
        return nil, NodeLookup.Reason.InvalidRoot
    end
    return transform
end

function NodeLookup.createIndex(root)
    local rootTransform = resolveTransform(root)
    local rootGameObject = resolveGameObject(rootTransform)
    if rootTransform == nil or rootGameObject == nil then
        return nil, NodeLookup.Reason.InvalidRoot
    end

    local index = {
        transformByPath = { [""] = rootTransform },
        gameObjectByPath = { [""] = rootGameObject },
        initialRootName = getTransformName(rootTransform),
    }
    local pending = { { path = "", transform = rootTransform } }

    while #pending > 0 do
        local current = table.remove(pending)
        local ok, childCount = pcall(function()
            return current.transform.childCount
        end)
        if not ok or type(childCount) ~= "number" then
            return nil, NodeLookup.Reason.InvalidRoot
        end

        for childIndex = 0, childCount - 1 do
            local childOk, child = pcall(function()
                return current.transform:GetChild(childIndex)
            end)
            if not childOk or child == nil then
                return nil, NodeLookup.Reason.InvalidRoot
            end

            local nameOk, childName = pcall(function()
                return child.name
            end)
            if not nameOk then
                return nil, NodeLookup.Reason.InvalidRoot
            end

            if isValidPathSegment(childName) then
                local childPath = current.path == "" and childName or current.path .. "/" .. childName
                if index.transformByPath[childPath] == nil then
                    local childGameObject = resolveGameObject(child)
                    if childGameObject == nil then
                        return nil, NodeLookup.Reason.InvalidRoot
                    end
                    index.transformByPath[childPath] = child
                    index.gameObjectByPath[childPath] = childGameObject
                    pending[#pending + 1] = { path = childPath, transform = child }
                end
            end
        end
    end

    return index
end

function NodeLookup.getTransformByPath(root, nodePath)
    local rootTransform = resolveTransform(root)
    if rootTransform == nil then
        return nil, NodeLookup.Reason.InvalidRoot
    end

    local normalizedPath = normalizeNodePath(nodePath)
    if normalizedPath == nil then
        return nil, NodeLookup.Reason.InvalidPath
    end
    if normalizedPath == "" then
        return rootTransform
    end

    local transform, reason = tryFindTransform(rootTransform, normalizedPath)
    if reason ~= nil then
        return nil, reason
    end
    if transform ~= nil then
        return transform
    end

    if normalizedPath == getTransformName(rootTransform) then
        return rootTransform
    end

    local rootRelativePath = stripGlbRootSegment(normalizedPath)
    if rootRelativePath == nil then
        return nil, NodeLookup.Reason.NotFound
    end

    transform, reason = tryFindTransform(rootTransform, rootRelativePath)
    if reason ~= nil then
        return nil, reason
    end
    if transform == nil then
        return nil, NodeLookup.Reason.NotFound
    end
    return transform
end

function NodeLookup.getIndexedTransformByPath(index, nodePath)
    if type(index) ~= "table" or type(index.transformByPath) ~= "table" then
        return nil, NodeLookup.Reason.InvalidRoot
    end

    local normalizedPath = normalizeNodePath(nodePath)
    if normalizedPath == nil then
        return nil, NodeLookup.Reason.InvalidPath
    end

    local transform = findIndexedValue(index.transformByPath, normalizedPath, index.initialRootName)
    if transform == nil or resolveGameObject(transform) == nil then
        return nil, NodeLookup.Reason.NotFound
    end
    return transform
end

function NodeLookup.getGameObjectByPath(root, nodePath)
    local transform, reason = NodeLookup.getTransformByPath(root, nodePath)
    if transform == nil then
        return nil, reason
    end
    local ok, gameObject = pcall(function()
        return transform.gameObject
    end)
    if not ok or gameObject == nil then
        return nil, NodeLookup.Reason.InvalidRoot
    end
    return gameObject
end

function NodeLookup.getIndexedGameObjectByPath(index, nodePath)
    if type(index) ~= "table" or type(index.gameObjectByPath) ~= "table" then
        return nil, NodeLookup.Reason.InvalidRoot
    end

    local normalizedPath = normalizeNodePath(nodePath)
    if normalizedPath == nil then
        return nil, NodeLookup.Reason.InvalidPath
    end

    local gameObject = findIndexedValue(index.gameObjectByPath, normalizedPath, index.initialRootName)
    if gameObject == nil or resolveTransform(gameObject) == nil then
        return nil, NodeLookup.Reason.NotFound
    end
    return gameObject
end

-- Compatibility aliases for existing scripts.
NodeLookup.findTransform = NodeLookup.getTransformByPath
NodeLookup.findGameObject = NodeLookup.getGameObjectByPath
NodeLookup.findIndexedTransform = NodeLookup.getIndexedTransformByPath
NodeLookup.findIndexedGameObject = NodeLookup.getIndexedGameObjectByPath

return NodeLookup
