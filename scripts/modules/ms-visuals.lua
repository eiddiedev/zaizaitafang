---@id 8d07aa40-95b3-4d4a-8797-752a05c0893f
---@referenceName ms-visuals.lua
---@assetRef eyJhc3NldElkIjoiMTE2MDg1NTgyMzQ2MjYiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvNzNkaW41emZhdHg0OGV2ci5nbGIiLCJyZWZlcmVuY2VOYW1lIjoibXMtdmlzdWFscy5sdWEifQ
-- 在 Unity 运行时修正透明/加色材质，并公开给外部克隆节点复用。
---@displayName 战斗表现渲染配置
---@start
---@var UseAdditiveGlow:boolean=true
---@name 加色光效
---@desc 关闭后光效面片改用普通透明混合
---@group 渲染
---@var DisableShadows:boolean=true
---@name 关闭阴影
---@desc 关闭本素材包渲染器的投射与接收阴影
---@group 渲染
---@end

local Logger = require("official.core.logger")
local RuntimeScope = require("official.core.runtime_scope")

local UnityEngine = CS.UnityEngine

local logger = Logger.create("vfx-v2-visuals")
local runtimeScope = RuntimeScope.from(self)

local MODEL_ROOT = "晶界守卫 战斗表现素材V2"
local NODE_NAMES = {
  "V2_Arrow",
  "V2_LeafArrow",
  "V2_Cannonball",
  "V2_Meteor",
  "V2_Spark",
  "V2_Smoke",
  "V2_Flame",
  "V2_Rune",
  "V2_Orb",
  "V2_Leaf",
  "V2_Slash",
  "V2_MagicHit",
  "V2_Streak",
}

local function materialKey(value)
  if value == nil then
    return ""
  end
  return string.lower(tostring(value))
end

local function classifyMaterial(materialName, rendererName)
  local key = materialKey(materialName) .. " " .. materialKey(rendererName)
  if string.find(key, "flamecore", 1, true) ~= nil then
    return "additive"
  end
  if string.find(key, "flameouter", 1, true) ~= nil then
    return "alpha"
  end
  if string.find(key, "vfx_atlas_slash", 1, true) ~= nil then
    return "additive"
  end
  if string.find(key, "vfx_atlas_magichit", 1, true) ~= nil then
    return "additive"
  end
  if string.find(key, "vfx_atlas_streak", 1, true) ~= nil then
    return "additive"
  end
  if string.find(key, "vfx_atlas_leaf", 1, true) ~= nil then
    return "alpha"
  end
  if string.find(key, "vfx_atlas_orb", 1, true) ~= nil then
    return "additive"
  end
  if string.find(key, "vfx_atlas_flame", 1, true) ~= nil then
    return "additive"
  end
  if string.find(key, "spark", 1, true) ~= nil then
    return "additive"
  end
  if string.find(key, "smoke", 1, true) ~= nil then
    return "alpha"
  end
  if string.find(key, "rune", 1, true) ~= nil then
    return "additive"
  end
  if string.find(key, "orbshell", 1, true) ~= nil then
    return "additive"
  end
  if string.find(key, "halo", 1, true) ~= nil then
    return "additive"
  end
  if string.find(key, "vfx_atlas_", 1, true) ~= nil then
    return "alpha"
  end
  return nil
end

local function ensureTexture(material)
  local texture = nil
  if material:HasProperty("_BaseMap") then
    texture = material:GetTexture("_BaseMap")
  end
  if texture == nil then
    texture = material.mainTexture
  end
  if texture == nil and material:HasProperty("_MainTex") then
    texture = material:GetTexture("_MainTex")
  end
  if texture == nil then
    return false
  end
  if material:HasProperty("_BaseMap") then
    material:SetTexture("_BaseMap", texture)
  end
  if material:HasProperty("_MainTex") then
    material:SetTexture("_MainTex", texture)
  end
  material.mainTexture = texture
  return true
end

local function ensureBaseAlpha(material)
  if material:HasProperty("_BaseColor") then
    local color = material:GetColor("_BaseColor")
    if color.a <= 0.001 then
      material:SetColor("_BaseColor", UnityEngine.Color(color.r, color.g, color.b, 1))
    end
  elseif material:HasProperty("_Color") then
    local color = material:GetColor("_Color")
    if color.a <= 0.001 then
      material:SetColor("_Color", UnityEngine.Color(color.r, color.g, color.b, 1))
    end
  end
end

local function intendedAlpha(materialName)
  local key = materialKey(materialName)
  if string.find(key, "orbshell", 1, true) ~= nil then
    return 0.3
  end
  if string.find(key, "smoke", 1, true) ~= nil then
    return 0.82
  end
  if string.find(key, "flameouter", 1, true) ~= nil then
    return 0.95
  end
  if string.find(key, "flamecore", 1, true) ~= nil then
    return 0.65
  end
  if string.find(key, "halo", 1, true) ~= nil then
    return 0.92
  end
  return nil
end

local function applyIntendedAlpha(material, alpha)
  if alpha == nil then
    return
  end
  if material:HasProperty("_BaseColor") then
    local color = material:GetColor("_BaseColor")
    material:SetColor("_BaseColor", UnityEngine.Color(color.r, color.g, color.b, alpha))
  elseif material:HasProperty("_Color") then
    local color = material:GetColor("_Color")
    material:SetColor("_Color", UnityEngine.Color(color.r, color.g, color.b, alpha))
  end
end

local function configureTransparent(material, additive)
  if material == nil then
    return
  end
  local configurable = material:HasProperty("_Surface")
    or material:HasProperty("_SrcBlend")
    or material:HasProperty("_DstBlend")
  if not configurable then
    logger:warnOnce("shader-not-configurable", "transparent shader has no blend properties", material.name)
    return
  end
  local needsTexture = string.find(materialKey(material.name), "orbshell", 1, true) == nil
  if needsTexture and not ensureTexture(material) then
    logger:warnOnce("texture-missing", "transparent material has no texture", material.name)
  end
  ensureBaseAlpha(material)
  applyIntendedAlpha(material, intendedAlpha(material.name))
  if material:HasProperty("_Surface") then
    material:SetFloat("_Surface", 1)
  end
  if material:HasProperty("_Blend") then
    material:SetFloat("_Blend", additive and 2 or 0)
  end
  if material:HasProperty("_SrcBlend") then
    material:SetFloat("_SrcBlend", 5)
  end
  if material:HasProperty("_DstBlend") then
    material:SetFloat("_DstBlend", additive and 1 or 10)
  end
  if material:HasProperty("_ZWrite") then
    material:SetFloat("_ZWrite", 0)
  end
  if material:HasProperty("_Cull") then
    local shellOnly = string.find(materialKey(material.name), "orbshell", 1, true) ~= nil
    material:SetFloat("_Cull", shellOnly and 2 or 0)
  end
  if material:HasProperty("_AlphaClip") then
    material:SetFloat("_AlphaClip", 0)
  end
  material.renderQueue = additive and 3001 or 3000
  material:SetOverrideTag("RenderType", "Transparent")
  material:EnableKeyword("_SURFACE_TYPE_TRANSPARENT")
  material:DisableKeyword("_ALPHATEST_ON")
  if additive then
    material:DisableKeyword("_ALPHABLEND_ON")
    material:DisableKeyword("_ALPHAPREMULTIPLY_ON")
  else
    material:EnableKeyword("_ALPHABLEND_ON")
    material:DisableKeyword("_ALPHAPREMULTIPLY_ON")
  end
  if DisableShadows then
    material:SetShaderPassEnabled("ShadowCaster", false)
  end
end

local function configureShadows(renderer, material)
  if not DisableShadows then
    return
  end
  renderer.receiveShadows = false
  if material ~= nil then
    material:SetShaderPassEnabled("ShadowCaster", false)
  end
  pcall(function()
    renderer.shadowCastingMode = CS.UnityEngine.Rendering.ShadowCastingMode.Off
  end)
end

function ConfigureRenderers(go)
  if go == nil then
    return 0
  end
  local gameObject = go
  if go.gameObject ~= nil then
    gameObject = go.gameObject
  end
  local renderers = gameObject:GetComponentsInChildren(typeof(UnityEngine.Renderer), true)
  if renderers == nil then
    return 0
  end
  local configured = 0
  for index = 0, renderers.Length - 1 do
    local renderer = renderers[index]
    if renderer ~= nil then
      local material = renderer.material
      if material ~= nil then
        local mode = classifyMaterial(material.name, renderer.gameObject.name)
        if mode ~= nil then
          local additive = mode == "additive" and UseAdditiveGlow
          configureTransparent(material, additive)
        end
        configureShadows(renderer, material)
        configured = configured + 1
      end
    end
  end
  return configured
end

function Start()
  if runtimeScope == nil then
    logger:warnOnce("scope-missing", "render configuration cannot resolve runtime scope")
    return
  end
  local configured = 0
  for index = 1, #NODE_NAMES do
    local transform = runtimeScope:GetTransformByPath(MODEL_ROOT .. "/" .. NODE_NAMES[index])
    if transform ~= nil then
      configured = configured + ConfigureRenderers(transform.gameObject)
    else
      logger:warnOnce("node-missing", "render node is missing", NODE_NAMES[index])
    end
  end
  logger:info("renderers configured", configured)
end