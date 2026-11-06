---@id caf525f4-7a92-4cd8-be90-6b34095c6478
---@referenceName pi-preview.lua
---@assetRef eyJhc3NldElkIjoiMTE2MDg1NTgyMzQ2MjYiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvNzNkaW41emZhdHg0OGV2ci5nbGIiLCJyZWZlcmVuY2VOYW1lIjoicGktcHJldmlldy5sdWEifQ
-- 为战斗表现素材包提供靠近后按需播放一次的预览入口。
---@displayName 战斗表现预览入口
---@start
---@var TriggerRangeScale:number=1
---@name 触发范围倍率
---@desc 基于初始触发范围等比放大
---@group 交互
---@end

local Logger = require("official.core.logger")
local Trigger = require("official.interaction.trigger")
local RuntimeScope = require("official.core.runtime_scope")

local logger = Logger.create("vfx-v2-preview")
local runtimeScope = RuntimeScope.from(self)
local previewButton = nil

Trigger.applyRangeScale(self, TriggerRangeScale)

local function setButtonLabel(button, text)
  if button == nil then
    return
  end
  local label = button:GetComponentInChildren(typeof(CS.UnityEngine.UI.Text), true)
  if label ~= nil then
    label.text = text
  end
end

local function removeButton()
  if previewButton == nil then
    return
  end
  self:RemoveInteractorButton(previewButton)
  previewButton = nil
end

function OnActorTriggerEnter(actor)
  if actor == nil or not actor.isLocal then
    return
  end
  self:EnableInteraction()
end

function OnActorTriggerExit(actor)
  if actor == nil or not actor.isLocal then
    return
  end
  self:DisableInteraction()
end

function OnFocus(handType)
  previewButton = self:AddInteractorButton()
  if previewButton == nil then
    logger:warnOnce("preview-button-missing", "interactor button is unavailable")
    return
  end
  setButtonLabel(previewButton, "播放预览")
end

function OnLostFocus(handType)
  removeButton()
end

function OnInteractorButtonClick(index)
  if index ~= 1 then
    return
  end
  if runtimeScope == nil then
    logger:warnOnce("preview-scope-missing", "preview script cannot resolve runtime scope")
    return
  end
  local preview = runtimeScope:GetScript("ms-preview.lua")
  if preview == nil or type(preview.PlayPreview) ~= "function" then
    logger:warnOnce("preview-script-missing", "preview choreography is unavailable")
    return
  end
  preview.PlayPreview()
end

function OnDisable()
  removeButton()
end