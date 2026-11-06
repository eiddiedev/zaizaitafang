---@id ca6bf303-ad80-48c1-8fc4-e0f00150e79d
---@referenceName ui.lua
---@assetRef eyJhc3NldElkIjoibWl4LWNyeXN0YWwtZGVmZW5zZTpoYW1sZXQtdWdjL2FpZ2NfZWRpdG9yL2Rldi91bml0eS9NUzR3TGpBQkFBQUFpWGVTbVJUZzVIekJKb1pRTkE0OEh1eXBoeWkxME4zNmk4QjJpenpZSjNZL21peC1wYXJ0LTJfX3VwbG9hZF9raDhqYjR0eS5nbGIiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvbWl4LXBhcnQtMl9fdXBsb2FkX2toOGpiNHR5LmdsYiIsInJlZmVyZW5jZU5hbWUiOiJ1aS5sdWEifQ
-- 本地音频服务经 Host 公开接口分发，不访问其他资源节点。
---@displayName 四境音乐服务
local U=CS.UnityEngine
local Scope=require("official.core.runtime_scope")
local scope=Scope.from(self)
local root=scope and scope:GetResourceRoot()or nil
local bank="world"
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
 if registered or not scope then return end
 local h=scope:GetRuntimeHostScript("runtime-host.lua")
 if h and type(h.RegisterAudioBank)=="function"then h.RegisterAudioBank(bank,{Play=Play,Loop=Loop});registered=true end
end
function OnDestroy()
 if scope then local h=scope:GetRuntimeHostScript("runtime-host.lua");if h and type(h.RemoveAudioBank)=="function"then h.RemoveAudioBank(bank)end end
 if root then local t=root.transform:Find("RuntimeAudio");if t then local all=t:GetComponentsInChildren(typeof(U.AudioSource),true);for i=0,all.Length-1 do all[i]:Stop()end end end
end