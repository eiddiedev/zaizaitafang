--- 标记资源根节点并注册 Resource Scope，供资源内脚本查找根节点与初始子树，销毁时注销。
---@runtimeBuiltin RuntimeResourceRootBootstrap
---@id d6f83b17-d36c-4840-ae2a-b896be27b101
---@referenceName runtime-builtin_runtime-resource-root-bootstrap.lua
---@start
---@end

local RuntimeScope = require("official.core.runtime_scope")
local resourceRoot = self.gameObject
local scope = RuntimeScope.registerResourceRoot(resourceRoot)

function OnDestroy()
    if scope ~= nil then
        RuntimeScope.unregister(resourceRoot, scope)
        scope = nil
    end
end
