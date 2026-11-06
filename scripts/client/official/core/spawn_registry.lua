-- Internal records for instances created through Spawn. Keys do not keep GOs alive.
local Registry = {}
local records = setmetatable({}, { __mode = "k" })

Registry.Mode = { Local = "Local", Network = "Network" }

function Registry.isAlive(go)
    return go ~= nil and not go:Equals(nil)
end

function Registry.get(go)
    return records[go]
end

function Registry.bind(go, mode)
    local record = records[go]
    if record ~= nil then
        if record.mode ~= mode then
            error("spawn_instance_mode_mismatch", 2)
        end
        return record
    end
    record = { mode = mode, destroying = false }
    records[go] = record
    return record
end

function Registry.release(go)
    records[go] = nil
end

return Registry
