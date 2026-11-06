---@id ceb8e7bd-62c8-4c71-bd8e-e897756cd361
---@referenceName ui.lua
---@assetRef eyJhc3NldElkIjoibWl4LWNyeXN0YWwtZGVmZW5zZTpoYW1sZXQtdWdjL2FpZ2NfZWRpdG9yL2Rldi91bml0eS9NUzR3TGpBQkFBQUFpWGVTbVJUZzVIekJKb1pRTkE0OEh1eXBoeWkxME4zNmk4QjJpenpZSjNZL21peC1wYXJ0LTFfX3VwbG9hZF9pcGdidDRpeS5nbGIiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvbWl4LXBhcnQtMV9fdXBsb2FkX2lwZ2J0NGl5LmdsYiIsInJlZmVyZW5jZU5hbWUiOiJ1aS5sdWEifQ
-- 本地音频服务经 Host 公开接口分发，不访问其他资源节点。
---@displayName 敌群音频服务
local U=CS.UnityEngine
local Scope=require("official.core.runtime_scope")
local scope=Scope.from(self)
local root=scope and scope:GetResourceRoot()or nil
local bank="foes"
local registered=false
local function source(name)
 local node=root and root.transform:Find("RuntimeAudio/"..name)
 return node and node:GetComponent(typeof(U.AudioSource))or nil
end
function Play(name,volume)
 local s=source(name);if not s then return false end
 local parent=root.transform:Find("RuntimeAudio"):GetComponent(typeof(U.AudioSource))
 parent.volume=math.max(0,math.min(1,volume or 1));parent:PlayOneShot(s.clip,1);return true
end
function Loop(name,on)
 local s=source(name);if not s then return nil end
 s.loop=true;s.spatialBlend=0;s.dopplerLevel=0;s.priority=16
 if on and not s.isPlaying then s.enabled=true;s:Play()elseif not on then s:Stop()end;return s
end
function Update()
 if not scope then return end
 local h=scope:GetRuntimeHostScript("runtime-host.lua")
 if not registered and h and type(h.RegisterAudioBank)=="function"then h.RegisterAudioBank(bank,{Play=Play,Loop=Loop});registered=true end
 if h and type(h.GetLocalSettings)=="function" and root then
  local node=root.transform:Find("RuntimeAudio");local hub=node and node:GetComponent(typeof(U.AudioSource))
  if hub then hub.volume=h.GetLocalSettings().volume end
 end
end
function OnDestroy()
 if scope then local h=scope:GetRuntimeHostScript("runtime-host.lua");if h and type(h.RemoveAudioBank)=="function"then h.RemoveAudioBank(bank)end end
 if root then local t=root.transform:Find("RuntimeAudio");if t then local all=t:GetComponentsInChildren(typeof(U.AudioSource),true);for i=0,all.Length-1 do all[i]:Stop()end end end
end