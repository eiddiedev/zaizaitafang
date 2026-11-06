--- 标记 Runtime Host 根节点并注册 Host Scope，销毁时注销。
---@runtimeBuiltin RuntimeHostRootBootstrap
---@id 4e52264d-30cc-4856-a932-b33d30380a3a
---@referenceName runtime-builtin_runtime-host-root-bootstrap.lua
---@start
---@end

local RuntimeScope = require("official.core.runtime_scope")
local resourceRoot = self.gameObject
local scope = RuntimeScope.registerHostRoot(resourceRoot)

function OnDestroy()
    if scope ~= nil then
        RuntimeScope.unregister(resourceRoot, scope)
        scope = nil
    end
end
