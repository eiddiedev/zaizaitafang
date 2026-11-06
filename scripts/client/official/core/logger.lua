local UnityDebug = CS.UnityEngine.Debug

local Logger = {}
local LoggerInstance = {}
LoggerInstance.__index = LoggerInstance

local function normalizeTag(tag)
    if tag == nil or tag == "" then
        return "worldplay"
    end
    return tostring(tag)
end

local function formatMessage(tag, ...)
    local parts = { "[" .. tag .. "]" }
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        parts[#parts + 1] = tostring(value)
    end
    return table.concat(parts, " ")
end

function LoggerInstance:info(...)
    UnityDebug.Log(formatMessage(self.tag, ...))
end

function LoggerInstance:warn(...)
    UnityDebug.LogWarning(formatMessage(self.tag, ...))
end

function LoggerInstance:error(...)
    UnityDebug.LogError(formatMessage(self.tag, ...))
end

function LoggerInstance:warnOnce(key, ...)
    if key == nil then
        self:warn(...)
        return true
    end

    local normalizedKey = tostring(key)
    if self.warnedKeys[normalizedKey] == true then
        return false
    end
    self.warnedKeys[normalizedKey] = true
    self:warn(...)
    return true
end

function Logger.create(tag)
    return setmetatable({
        tag = normalizeTag(tag),
        warnedKeys = {},
    }, LoggerInstance)
end

return Logger
