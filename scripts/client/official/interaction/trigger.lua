local BoxCollider = CS.UnityEngine.BoxCollider
local Vector3 = CS.UnityEngine.Vector3

local Trigger = {}

Trigger.Reason = {
    InvalidTarget = "trigger-invalid-target",
    QueryFailed = "trigger-query-failed",
    NotFound = "trigger-not-found",
    Ambiguous = "trigger-ambiguous",
    InvalidScale = "trigger-invalid-scale",
    ScaleFailed = "trigger-scale-failed",
}

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

    local transform
    ok, transform = pcall(function()
        return value.transform
    end)
    if ok and transform ~= nil then
        return value
    end
    return nil
end

function Trigger.findBoxCollider(value)
    local gameObject = resolveGameObject(value)
    if gameObject == nil then
        return nil, Trigger.Reason.InvalidTarget
    end

    local ok, collider, reason = pcall(function()
        local colliders = gameObject:GetComponents(typeof(BoxCollider))
        local found = nil
        if colliders ~= nil then
            for index = 0, colliders.Length - 1 do
                local candidate = colliders[index]
                if candidate ~= nil and candidate.isTrigger == true then
                    if found ~= nil then
                        return nil, Trigger.Reason.Ambiguous
                    end
                    found = candidate
                end
            end
        end

        if found == nil then
            return nil, Trigger.Reason.NotFound
        end
        return found
    end)
    if not ok then
        return nil, Trigger.Reason.QueryFailed
    end
    return collider, reason
end

function Trigger.applyRangeScale(value, scale)
    if type(scale) ~= "number" or scale ~= scale or scale == math.huge or scale == -math.huge then
        return nil, Trigger.Reason.InvalidScale
    end

    local collider, reason = Trigger.findBoxCollider(value)
    if collider == nil then
        return nil, reason
    end

    local ok = pcall(function()
        local size = collider.size
        collider.size = Vector3(
            size.x * scale,
            size.y * scale,
            size.z * scale
        )
    end)
    if not ok then
        return nil, Trigger.Reason.ScaleFailed
    end
    return collider
end

return Trigger
