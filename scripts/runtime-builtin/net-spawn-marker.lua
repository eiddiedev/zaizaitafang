--- 保存网络模板 key，并清理生成实例的本地记录。
---@runtimeBuiltin NetSpawnMarker
---@id bba0be42-b2ed-452b-a9df-2f2b7f579dfd
---@referenceName runtime-builtin___NetSpawnTarget__.lua
---@start
---@var key:string=""
---@end

local Registry = require("official.core.spawn_registry")
local go = self.gameObject

function GetKey()
    return key
end

function OnNetDestroy()
    if go == nil then
        return
    end
    local record = Registry.get(go) or Registry.bind(go, Registry.Mode.Network)
    if record.mode == Registry.Mode.Network then
        record.destroying = true
    end
end

function OnDestroy()
    if go ~= nil then
        Registry.release(go)
        go = nil
    end
end
