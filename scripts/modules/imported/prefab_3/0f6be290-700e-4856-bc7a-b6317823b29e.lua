---@id 0f6be290-700e-4856-bc7a-b6317823b29e
---@referenceName ui.lua
-- Gameplay equips clothing automatically; no dressing-room controls.
local RuntimeScope=require("official.core.runtime_scope")
function Start()
 local scope=RuntimeScope.from(self)
 local root=scope and scope:GetResourceRoot()
 if root then root:SetActive(false)end
end
