local Collider = CS.UnityEngine.Collider
local Vector3 = CS.UnityEngine.Vector3

local Containment = {}

Containment.Reason = {
    InvalidOptions = "containment-invalid-options",
    InvalidSubject = "containment-invalid-subject",
    InvalidContainer = "containment-invalid-container",
    InvalidInset = "containment-invalid-inset",
    InvalidEpsilon = "containment-invalid-epsilon",
    QueryFailed = "containment-query-failed",
    NoSubjectCollider = "containment-no-subject-collider",
    NoContainerCollider = "containment-no-container-collider",
    CollapsedContainer = "containment-collapsed-container",
    EvaluationFailed = "containment-evaluation-failed",
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

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

    ok, transform = pcall(function()
        local _ = value.childCount
        return value
    end)
    if ok then
        return transform
    end
    return nil
end

local function readInset(value)
    if value == nil then
        return { x = 0, y = 0, z = 0 }
    end
    if isFiniteNumber(value) and value >= 0 then
        return { x = value, y = value, z = value }
    end

    local ok, x, y, z = pcall(function()
        return value.x, value.y, value.z
    end)
    if not ok
        or not isFiniteNumber(x) or x < 0
        or not isFiniteNumber(y) or y < 0
        or not isFiniteNumber(z) or z < 0 then
        return nil
    end
    return { x = x, y = y, z = z }
end

local function queryColliders(rootTransform, includeInactive)
    local gameObject = rootTransform.gameObject
    local colliders = gameObject:GetComponentsInChildren(typeof(Collider), includeInactive)
    local result = {}
    if colliders ~= nil then
        for index = 0, colliders.Length - 1 do
            local collider = colliders[index]
            if collider ~= nil then
                result[#result + 1] = collider
            end
        end
    end
    return result
end

local function includeCollider(collider, excluded)
    return (excluded == nil or excluded[collider] ~= true)
        and collider.enabled == true
        and collider.isTrigger ~= true
end

local function appendPoint(bounds, point)
    if not isFiniteNumber(point.x)
        or not isFiniteNumber(point.y)
        or not isFiniteNumber(point.z) then
        error("containment point is not finite")
    end

    if bounds.empty then
        bounds.minX, bounds.maxX = point.x, point.x
        bounds.minY, bounds.maxY = point.y, point.y
        bounds.minZ, bounds.maxZ = point.z, point.z
        bounds.empty = false
        return
    end

    bounds.minX = math.min(bounds.minX, point.x)
    bounds.maxX = math.max(bounds.maxX, point.x)
    bounds.minY = math.min(bounds.minY, point.y)
    bounds.maxY = math.max(bounds.maxY, point.y)
    bounds.minZ = math.min(bounds.minZ, point.z)
    bounds.maxZ = math.max(bounds.maxZ, point.z)
end

local function appendLocalBoundsCorners(bounds, center, size, sourceTransform, referenceTransform)
    local halfX = size.x * 0.5
    local halfY = size.y * 0.5
    local halfZ = size.z * 0.5

    for xSign = -1, 1, 2 do
        for ySign = -1, 1, 2 do
            for zSign = -1, 1, 2 do
                local sourcePoint = Vector3(
                    center.x + halfX * xSign,
                    center.y + halfY * ySign,
                    center.z + halfZ * zSign
                )
                local worldPoint = sourceTransform:TransformPoint(sourcePoint)
                appendPoint(bounds, referenceTransform:InverseTransformPoint(worldPoint))
            end
        end
    end
end

local function appendWorldBoundsCorners(bounds, worldBounds, referenceTransform)
    local min = worldBounds.min
    local max = worldBounds.max
    for xIndex = 0, 1 do
        for yIndex = 0, 1 do
            for zIndex = 0, 1 do
                local worldPoint = Vector3(
                    xIndex == 0 and min.x or max.x,
                    yIndex == 0 and min.y or max.y,
                    zIndex == 0 and min.z or max.z
                )
                appendPoint(bounds, referenceTransform:InverseTransformPoint(worldPoint))
            end
        end
    end
end

local function appendColliderCorners(bounds, collider, referenceTransform)
    local localBoundsOk, center, size = pcall(function()
        return collider.center, collider.size
    end)
    if localBoundsOk and center ~= nil and size ~= nil then
        appendLocalBoundsCorners(bounds, center, size, collider.transform, referenceTransform)
        return
    end

    local meshBoundsOk, meshCenter, meshSize = pcall(function()
        local mesh = collider.sharedMesh
        if mesh == nil then return nil, nil end
        return mesh.bounds.center, mesh.bounds.size
    end)
    if meshBoundsOk and meshCenter ~= nil and meshSize ~= nil then
        appendLocalBoundsCorners(bounds, meshCenter, meshSize, collider.transform, referenceTransform)
        return
    end

    appendWorldBoundsCorners(bounds, collider.bounds, referenceTransform)
end

local function collectBounds(colliders, excluded, referenceTransform, missingReason)
    local bounds = { empty = true }
    local colliderCount = 0
    for _, collider in ipairs(colliders) do
        if includeCollider(collider, excluded) then
            appendColliderCorners(bounds, collider, referenceTransform)
            colliderCount = colliderCount + 1
        end
    end
    if colliderCount == 0 then
        return nil, missingReason
    end
    return bounds
end

local function toPublicBounds(bounds)
    return {
        min = Vector3(bounds.minX, bounds.minY, bounds.minZ),
        max = Vector3(bounds.maxX, bounds.maxY, bounds.maxZ),
    }
end

local function findOutside(subject, container)
    if subject.minX < container.minX then
        return "x", "min", container.minX - subject.minX
    end
    if subject.maxX > container.maxX then
        return "x", "max", subject.maxX - container.maxX
    end
    if subject.minY < container.minY then
        return "y", "min", container.minY - subject.minY
    end
    if subject.maxY > container.maxY then
        return "y", "max", subject.maxY - container.maxY
    end
    if subject.minZ < container.minZ then
        return "z", "min", container.minZ - subject.minZ
    end
    if subject.maxZ > container.maxZ then
        return "z", "max", subject.maxZ - container.maxZ
    end
    return nil
end

local function evaluate(checker)
    local subjectBounds, subjectReason = collectBounds(
        checker.subjectColliders,
        nil,
        checker.containerTransform,
        Containment.Reason.NoSubjectCollider
    )
    if subjectBounds == nil then
        return nil, subjectReason
    end

    local containerBounds, containerReason = collectBounds(
        checker.containerColliders,
        checker.subjectColliderSet,
        checker.containerTransform,
        Containment.Reason.NoContainerCollider
    )
    if containerBounds == nil then
        return nil, containerReason
    end

    local minInset = checker.containerMinInset
    local maxInset = checker.containerMaxInset
    local epsilon = checker.epsilon
    local effectiveContainer = {
        minX = containerBounds.minX + minInset.x - epsilon,
        maxX = containerBounds.maxX - maxInset.x + epsilon,
        minY = containerBounds.minY + minInset.y - epsilon,
        maxY = containerBounds.maxY - maxInset.y + epsilon,
        minZ = containerBounds.minZ + minInset.z - epsilon,
        maxZ = containerBounds.maxZ - maxInset.z + epsilon,
    }
    if effectiveContainer.minX >= effectiveContainer.maxX
        or effectiveContainer.minY >= effectiveContainer.maxY
        or effectiveContainer.minZ >= effectiveContainer.maxZ then
        return nil, Containment.Reason.CollapsedContainer
    end

    local outsideAxis, outsideSide, outsideDistance = findOutside(subjectBounds, effectiveContainer)
    local details = {
        subjectBounds = toPublicBounds(subjectBounds),
        containerBounds = toPublicBounds(containerBounds),
        effectiveContainerBounds = toPublicBounds(effectiveContainer),
        outsideAxis = outsideAxis,
        outsideSide = outsideSide,
        outsideDistance = outsideDistance,
    }
    return outsideAxis == nil, details
end

local Checker = {}
Checker.__index = Checker

function Checker:check()
    local ok, contained, details = pcall(evaluate, self)
    if not ok then
        return nil, Containment.Reason.EvaluationFailed
    end
    return contained, details
end

function Containment.create(options)
    if type(options) ~= "table" then
        return nil, Containment.Reason.InvalidOptions
    end
    if options.includeInactive ~= nil and type(options.includeInactive) ~= "boolean" then
        return nil, Containment.Reason.InvalidOptions
    end

    local subjectTransform = resolveTransform(options.subjectRoot)
    if subjectTransform == nil then
        return nil, Containment.Reason.InvalidSubject
    end
    local containerTransform = resolveTransform(options.containerRoot)
    if containerTransform == nil then
        return nil, Containment.Reason.InvalidContainer
    end

    local containerInset = readInset(options.containerInset)
    if containerInset == nil then
        return nil, Containment.Reason.InvalidInset
    end
    local containerMinInset = options.containerMinInset == nil
        and containerInset
        or readInset(options.containerMinInset)
    local containerMaxInset = options.containerMaxInset == nil
        and containerInset
        or readInset(options.containerMaxInset)
    if containerMinInset == nil or containerMaxInset == nil then
        return nil, Containment.Reason.InvalidInset
    end
    local epsilon = options.epsilon
    if epsilon == nil then
        epsilon = 0.001
    end
    if not isFiniteNumber(epsilon) or epsilon < 0 then
        return nil, Containment.Reason.InvalidEpsilon
    end

    local ok, subjectColliders, containerColliders = pcall(function()
        return queryColliders(subjectTransform, options.includeInactive == true),
            queryColliders(containerTransform, options.includeInactive == true)
    end)
    if not ok then
        return nil, Containment.Reason.QueryFailed
    end

    local subjectColliderSet = {}
    for _, collider in ipairs(subjectColliders) do
        subjectColliderSet[collider] = true
    end

    return setmetatable({
        containerTransform = containerTransform,
        subjectColliders = subjectColliders,
        subjectColliderSet = subjectColliderSet,
        containerColliders = containerColliders,
        containerMinInset = containerMinInset,
        containerMaxInset = containerMaxInset,
        epsilon = epsilon,
    }, Checker)
end

return Containment
