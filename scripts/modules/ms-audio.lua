---@id c1666e33-a431-42f2-9a23-0af81aba4e02
---@referenceName ms-audio.lua
---@assetRef eyJhc3NldElkIjoiMTE2MDg1NTgyMzQ2MjYiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvNzNkaW41emZhdHg0OGV2ci5nbGIiLCJyZWZlcmVuY2VOYW1lIjoibXMtYXVkaW8ubHVhIn0
-- 为二十二个 RuntimeAudio 空节点挂载 AudioSource，并用独立配方合成短促音色。
---@displayName 战斗音效节点
---@start
---@var MasterVolume:number=0.85
---@name 音效音量
---@desc 所有战斗音效的基础音量
---@group 音效
---@var EnableRuntimeAudio:boolean=true
---@name 启用运行时音效
---@desc 关闭后不再自动挂载与播放本模组的音效
---@group 音效
---@end

local Logger = require("official.core.logger")
local RuntimeScope = require("official.core.runtime_scope")

local UnityEngine = CS.UnityEngine
local AudioClip = CS.UnityEngine.AudioClip
local AudioSource = CS.UnityEngine.AudioSource

local logger = Logger.create("vfx-v2-audio")
local runtimeScope = RuntimeScope.from(self)

local AUDIO_ROOT = "晶界守卫 战斗表现素材V2/RuntimeAudio"
local SAMPLE_RATE = 22050

local SOUND_NAMES = {
  "v2-sword-swing",
  "v2-sword-hit",
  "v2-giant-awaken",
  "v2-giant-hit",
  "v2-bow-release",
  "v2-arrow-hit",
  "v2-leaf-charge",
  "v2-leaf-whoosh",
  "v2-leaf-hit",
  "v2-rain-fall",
  "v2-rain-hit",
  "v2-magic-shot",
  "v2-magic-hit",
  "v2-magic-burst",
  "v2-meteor-fall",
  "v2-meteor-impact",
  "v2-cannon-fire",
  "v2-cannon-explode",
  "v2-time-hit",
  "v2-wall-break",
  "v2-coin",
  "v2-dash",
}

local DURATIONS = {
  ["v2-sword-swing"] = 0.24,
  ["v2-sword-hit"] = 0.28,
  ["v2-giant-awaken"] = 0.95,
  ["v2-giant-hit"] = 0.5,
  ["v2-bow-release"] = 0.22,
  ["v2-arrow-hit"] = 0.2,
  ["v2-leaf-charge"] = 0.6,
  ["v2-leaf-whoosh"] = 0.26,
  ["v2-leaf-hit"] = 0.18,
  ["v2-rain-fall"] = 0.75,
  ["v2-rain-hit"] = 0.14,
  ["v2-magic-shot"] = 0.26,
  ["v2-magic-hit"] = 0.3,
  ["v2-magic-burst"] = 0.6,
  ["v2-meteor-fall"] = 0.95,
  ["v2-meteor-impact"] = 0.75,
  ["v2-cannon-fire"] = 0.45,
  ["v2-cannon-explode"] = 0.75,
  ["v2-time-hit"] = 0.32,
  ["v2-wall-break"] = 0.55,
  ["v2-coin"] = 0.38,
  ["v2-dash"] = 0.22,
}

local PEAKS = {
  ["v2-sword-swing"] = 0.82,
  ["v2-sword-hit"] = 0.92,
  ["v2-giant-awaken"] = 0.78,
  ["v2-giant-hit"] = 0.94,
  ["v2-bow-release"] = 0.82,
  ["v2-arrow-hit"] = 0.86,
  ["v2-leaf-charge"] = 0.7,
  ["v2-leaf-whoosh"] = 0.82,
  ["v2-leaf-hit"] = 0.78,
  ["v2-rain-fall"] = 0.5,
  ["v2-rain-hit"] = 0.62,
  ["v2-magic-shot"] = 0.84,
  ["v2-magic-hit"] = 0.88,
  ["v2-magic-burst"] = 0.94,
  ["v2-meteor-fall"] = 0.8,
  ["v2-meteor-impact"] = 0.96,
  ["v2-cannon-fire"] = 0.93,
  ["v2-cannon-explode"] = 0.96,
  ["v2-time-hit"] = 0.76,
  ["v2-wall-break"] = 0.92,
  ["v2-coin"] = 0.7,
  ["v2-dash"] = 0.82,
}

local SEEDS = {
  ["v2-sword-swing"] = 101,
  ["v2-sword-hit"] = 211,
  ["v2-giant-awaken"] = 307,
  ["v2-giant-hit"] = 401,
  ["v2-bow-release"] = 503,
  ["v2-arrow-hit"] = 601,
  ["v2-leaf-charge"] = 709,
  ["v2-leaf-whoosh"] = 809,
  ["v2-leaf-hit"] = 907,
  ["v2-rain-fall"] = 1009,
  ["v2-rain-hit"] = 1103,
  ["v2-magic-shot"] = 1201,
  ["v2-magic-hit"] = 1301,
  ["v2-magic-burst"] = 1409,
  ["v2-meteor-fall"] = 1511,
  ["v2-meteor-impact"] = 1601,
  ["v2-cannon-fire"] = 1709,
  ["v2-cannon-explode"] = 1801,
  ["v2-time-hit"] = 1907,
  ["v2-wall-break"] = 2003,
  ["v2-coin"] = 2101,
  ["v2-dash"] = 2203,
}

local sources = {}
local clips = {}
local ready = false
local audioRootTransform = nil
local rngState = 1

local function setSeed(seed)
  rngState = seed % 2147483647
  if rngState <= 0 then
    rngState = 1
  end
end

local function randomUnit()
  rngState = (rngState * 48271) % 2147483647
  return rngState / 2147483647
end

local function noise()
  return randomUnit() * 2 - 1
end

local function envelope(t, duration, attack, release)
  local attackTime = attack or 0.004
  local releaseTime = release or 0.04
  if attackTime <= 0 then
    attackTime = 0.0005
  end
  if releaseTime <= 0 then
    releaseTime = 0.005
  end
  if t < attackTime then
    return t / attackTime
  end
  if t > duration - releaseTime then
    local remain = duration - t
    if remain <= 0 then
      return 0
    end
    return remain / releaseTime
  end
  return 1
end

local function addNoise(samples, startTime, duration, gain, cutoffStart, cutoffEnd, attack, release, highpass)
  local count = #samples
  local startIndex = math.floor(startTime * SAMPLE_RATE) + 1
  local endIndex = math.min(count, math.floor((startTime + duration) * SAMPLE_RATE))
  local lowpass = 0
  local highpassState = 0
  local previous = 0
  for index = startIndex, endIndex do
    local t = (index - 1) / SAMPLE_RATE - startTime
    local ratio = t / duration
    local cutoff = cutoffStart + (cutoffEnd - cutoffStart) * ratio
    local alpha = 1 - math.exp(-2 * math.pi * cutoff / SAMPLE_RATE)
    local white = noise()
    local value
    if highpass then
      highpassState = alpha * (highpassState + white - previous)
      previous = white
      value = highpassState
    else
      lowpass = lowpass + alpha * (white - lowpass)
      value = lowpass
    end
    samples[index] = samples[index] + value * gain * envelope(t, duration, attack, release)
  end
end

local function addTone(samples, startTime, duration, frequencyStart, frequencyEnd, gain, attack, release, vibratoHz, vibratoAmount)
  local count = #samples
  local startIndex = math.floor(startTime * SAMPLE_RATE) + 1
  local endIndex = math.min(count, math.floor((startTime + duration) * SAMPLE_RATE))
  local phase = 0
  for index = startIndex, endIndex do
    local t = (index - 1) / SAMPLE_RATE - startTime
    local ratio = t / duration
    local frequency = frequencyStart + (frequencyEnd - frequencyStart) * ratio
    if vibratoHz ~= nil then
      frequency = frequency + math.sin(2 * math.pi * vibratoHz * t) * vibratoAmount
    end
    phase = phase + 2 * math.pi * frequency / SAMPLE_RATE
    local value = math.sin(phase) + 0.3 * math.sin(phase * 2) + 0.12 * math.sin(phase * 3)
    samples[index] = samples[index] + value * gain * envelope(t, duration, attack, release)
  end
end

local function addMetal(samples, startTime, duration, baseFrequency, gain, decay)
  local count = #samples
  local startIndex = math.floor(startTime * SAMPLE_RATE) + 1
  local endIndex = math.min(count, math.floor((startTime + duration) * SAMPLE_RATE))
  local ratios = { 1, 2.37, 3.41, 4.73, 6.11 }
  local phases = { 0, 0.7, 1.9, 3.1, 4.4 }
  for index = startIndex, endIndex do
    local t = (index - 1) / SAMPLE_RATE - startTime
    local value = 0
    for partial = 1, 5 do
      local frequency = baseFrequency * ratios[partial]
      local partialDecay = math.exp(-t * decay * (1 + (partial - 1) * 0.35))
      value = value + math.sin(2 * math.pi * frequency * t + phases[partial]) * partialDecay / (partial * 0.8 + 1)
    end
    if t < 0.012 then
      value = value + noise() * math.exp(-t * 120) * 0.8
    end
    samples[index] = samples[index] + value * gain * envelope(t, duration, 0.002, 0.035)
  end
end

local function addThump(samples, startTime, duration, frequencyStart, frequencyEnd, gain, decay)
  local count = #samples
  local startIndex = math.floor(startTime * SAMPLE_RATE) + 1
  local endIndex = math.min(count, math.floor((startTime + duration) * SAMPLE_RATE))
  local phase = 0
  for index = startIndex, endIndex do
    local t = (index - 1) / SAMPLE_RATE - startTime
    local frequency = frequencyEnd + (frequencyStart - frequencyEnd) * math.exp(-t * 6)
    phase = phase + 2 * math.pi * frequency / SAMPLE_RATE
    local value = math.sin(phase) * math.exp(-t * decay)
    if t < 0.008 then
      value = value + noise() * 0.5
    end
    samples[index] = samples[index] + value * gain * envelope(t, duration, 0.003, 0.05)
  end
end

local function addSparkle(samples, startTime, duration, count, frequencyMin, frequencyMax, gain)
  local total = #samples
  for _ = 1, count do
    local offset = startTime + randomUnit() * duration * 0.8
    local frequency = frequencyMin + randomUnit() * (frequencyMax - frequencyMin)
    local length = 0.03 + randomUnit() * 0.06
    local startIndex = math.floor(offset * SAMPLE_RATE) + 1
    local endIndex = math.min(total, math.floor((offset + length) * SAMPLE_RATE))
    for index = startIndex, endIndex do
      local t = (index - 1) / SAMPLE_RATE - offset
      local value = math.sin(2 * math.pi * frequency * t) * math.exp(-t * 70)
      samples[index] = samples[index] + value * gain
    end
  end
end

local function addCrackle(samples, startTime, duration, count, gain)
  local total = #samples
  for _ = 1, count do
    local offset = startTime + randomUnit() * duration
    local length = 0.008 + randomUnit() * 0.02
    local startIndex = math.floor(offset * SAMPLE_RATE) + 1
    local endIndex = math.min(total, math.floor((offset + length) * SAMPLE_RATE))
    local lowpass = 0
    for index = startIndex, endIndex do
      local t = (index - 1) / SAMPLE_RATE - offset
      local white = noise()
      lowpass = lowpass + 0.55 * (white - lowpass)
      samples[index] = samples[index] + lowpass * gain * math.exp(-t * 160)
    end
  end
end

local function normalize(samples, peak)
  local maximum = 0
  for index = 1, #samples do
    local value = math.abs(samples[index])
    if value > maximum then
      maximum = value
    end
  end
  if maximum <= 0 then
    return
  end
  local scale = peak / maximum
  for index = 1, #samples do
    samples[index] = samples[index] * scale
  end
end

local function buildSamples(name)
  local duration = DURATIONS[name] or 0.3
  local count = math.floor(SAMPLE_RATE * duration)
  local samples = {}
  for index = 1, count do
    samples[index] = 0
  end
  setSeed(SEEDS[name] or 12345)

  if name == "v2-sword-swing" then
    addNoise(samples, 0, 0.22, 1.0, 2600, 600, 0.003, 0.18, false)
    addNoise(samples, 0.01, 0.16, 0.35, 6000, 1400, 0.003, 0.14, true)
    addTone(samples, 0, 0.16, 500, 220, 0.12, 0.004, 0.12)
  elseif name == "v2-sword-hit" then
    addNoise(samples, 0, 0.05, 0.6, 5000, 1500, 0.001, 0.04, false)
    addMetal(samples, 0, 0.26, 620, 0.9, 18)
    addThump(samples, 0, 0.18, 150, 55, 0.7, 16)
  elseif name == "v2-giant-awaken" then
    addThump(samples, 0, 0.9, 70, 38, 0.8, 4)
    addNoise(samples, 0, 0.95, 0.35, 300, 120, 0.25, 0.4, false)
    addMetal(samples, 0.25, 0.75, 150, 0.25, 3)
    addTone(samples, 0.2, 0.7, 55, 90, 0.25, 0.2, 0.3)
  elseif name == "v2-giant-hit" then
    addThump(samples, 0, 0.4, 120, 40, 1.0, 10)
    addMetal(samples, 0, 0.38, 180, 0.5, 12)
    addNoise(samples, 0, 0.3, 0.45, 900, 180, 0.002, 0.2, false)
  elseif name == "v2-bow-release" then
    addTone(samples, 0, 0.18, 260, 90, 0.35, 0.002, 0.15)
    addNoise(samples, 0, 0.2, 0.5, 3500, 900, 0.002, 0.16, false)
    addTone(samples, 0, 0.1, 820, 320, 0.18, 0.002, 0.08)
  elseif name == "v2-arrow-hit" then
    addNoise(samples, 0, 0.16, 0.55, 3000, 500, 0.001, 0.13, false)
    addThump(samples, 0, 0.16, 220, 80, 0.6, 22)
    addMetal(samples, 0, 0.14, 420, 0.35, 25)
  elseif name == "v2-leaf-charge" then
    addTone(samples, 0, 0.55, 300, 950, 0.3, 0.08, 0.2)
    addNoise(samples, 0.05, 0.5, 0.25, 900, 2800, 0.06, 0.16, false)
    addSparkle(samples, 0, 0.5, 6, 1200, 3200, 0.25)
  elseif name == "v2-leaf-whoosh" then
    addNoise(samples, 0, 0.24, 0.7, 1800, 400, 0.002, 0.2, false)
    addNoise(samples, 0.01, 0.2, 0.25, 6000, 1800, 0.002, 0.16, true)
    addTone(samples, 0, 0.15, 600, 260, 0.12, 0.003, 0.12)
  elseif name == "v2-leaf-hit" then
    addNoise(samples, 0, 0.14, 0.55, 2200, 600, 0.001, 0.11, false)
    addThump(samples, 0, 0.14, 200, 90, 0.4, 24)
    addCrackle(samples, 0, 0.12, 3, 0.4)
  elseif name == "v2-rain-fall" then
    addNoise(samples, 0, 0.7, 0.35, 4000, 1200, 0.1, 0.3, false)
    addSparkle(samples, 0.05, 0.6, 10, 1800, 5200, 0.18)
    addNoise(samples, 0.1, 0.6, 0.15, 900, 2000, 0.08, 0.24, true)
  elseif name == "v2-rain-hit" then
    addNoise(samples, 0, 0.12, 0.6, 5000, 1800, 0.001, 0.1, false)
    addTone(samples, 0, 0.08, 1400, 900, 0.15, 0.001, 0.06)
    addSparkle(samples, 0, 0.1, 2, 2500, 4500, 0.2)
  elseif name == "v2-magic-shot" then
    addTone(samples, 0, 0.22, 500, 1500, 0.4, 0.002, 0.16)
    addSparkle(samples, 0, 0.22, 5, 1500, 5000, 0.3)
    addNoise(samples, 0, 0.18, 0.25, 3000, 6000, 0.002, 0.14, true)
  elseif name == "v2-magic-hit" then
    addMetal(samples, 0, 0.26, 760, 0.55, 20)
    addSparkle(samples, 0, 0.28, 8, 1800, 6000, 0.35)
    addNoise(samples, 0, 0.2, 0.3, 4000, 800, 0.001, 0.16, false)
  elseif name == "v2-magic-burst" then
    addThump(samples, 0, 0.5, 140, 50, 0.7, 8)
    addMetal(samples, 0, 0.5, 420, 0.45, 7)
    addSparkle(samples, 0.02, 0.55, 14, 1200, 6000, 0.35)
    addNoise(samples, 0, 0.6, 0.45, 2600, 300, 0.004, 0.4, false)
  elseif name == "v2-meteor-fall" then
    addNoise(samples, 0, 0.9, 0.65, 600, 100, 0.3, 0.35, false)
    addThump(samples, 0, 0.9, 55, 75, 0.35, 3)
    addCrackle(samples, 0.1, 0.7, 8, 0.25)
    addTone(samples, 0.1, 0.8, 45, 70, 0.3, 0.3, 0.3)
  elseif name == "v2-meteor-impact" then
    addThump(samples, 0, 0.7, 80, 28, 1.2, 6)
    addNoise(samples, 0, 0.65, 0.8, 1500, 90, 0.002, 0.4, false)
    addMetal(samples, 0, 0.6, 220, 0.5, 6)
    addCrackle(samples, 0.02, 0.48, 12, 0.5)
  elseif name == "v2-cannon-fire" then
    addThump(samples, 0, 0.38, 160, 45, 1.0, 10)
    addNoise(samples, 0, 0.4, 0.65, 2600, 220, 0.002, 0.3, false)
    addMetal(samples, 0, 0.3, 380, 0.3, 16)
  elseif name == "v2-cannon-explode" then
    addThump(samples, 0, 0.65, 70, 24, 1.2, 6)
    addNoise(samples, 0, 0.7, 0.85, 1400, 70, 0.002, 0.45, false)
    addCrackle(samples, 0.02, 0.53, 10, 0.45)
    addMetal(samples, 0, 0.5, 240, 0.4, 8)
  elseif name == "v2-time-hit" then
    addMetal(samples, 0, 0.3, 980, 0.5, 18)
    addSparkle(samples, 0, 0.3, 5, 2000, 7000, 0.35)
    addTone(samples, 0, 0.12, 1200, 800, 0.2, 0.001, 0.1)
    addNoise(samples, 0, 0.1, 0.2, 5000, 1500, 0.001, 0.08, false)
  elseif name == "v2-wall-break" then
    addCrackle(samples, 0, 0.45, 12, 0.6)
    addNoise(samples, 0, 0.5, 0.7, 1800, 250, 0.002, 0.35, false)
    addThump(samples, 0, 0.4, 110, 45, 0.7, 12)
    addMetal(samples, 0, 0.4, 300, 0.35, 10)
  elseif name == "v2-coin" then
    addTone(samples, 0, 0.3, 1180, 1180, 0.35, 0.002, 0.25)
    addTone(samples, 0.06, 0.28, 1760, 1760, 0.3, 0.002, 0.22)
    addSparkle(samples, 0, 0.25, 3, 2500, 6000, 0.2)
    addMetal(samples, 0, 0.2, 1600, 0.2, 30)
  elseif name == "v2-dash" then
    addNoise(samples, 0, 0.2, 0.7, 3000, 700, 0.002, 0.16, false)
    addNoise(samples, 0.01, 0.18, 0.25, 7000, 2200, 0.002, 0.14, true)
    addTone(samples, 0, 0.18, 450, 180, 0.25, 0.003, 0.14)
  end

  normalize(samples, PEAKS[name] or 0.85)
  return duration, samples
end

local function buildClip(name)
  local ok, clip = pcall(function()
    local duration, samples = buildSamples(name)
    local count = math.floor(SAMPLE_RATE * duration)
    if count <= 0 then
      return nil
    end
    local made,created=pcall(function()return AudioClip.Create(name,count,1,SAMPLE_RATE,false)end)
    if not made or not created then created=AudioClip.Create(name,count,1,SAMPLE_RATE,false,false)end
    if created == nil then
      return nil
    end
    local filled = nil
    local arrayOk, data = pcall(function()
      return CS.System.Array.CreateInstance(typeof(CS.System.Single), count)
    end)
    if arrayOk and data ~= nil then
      local arraySetOk, arrayFilled = pcall(function()
        for index = 1, count do
          data[index - 1] = samples[index]
        end
        return created:SetData(data, 0)
      end)
      if arraySetOk then
        filled = arrayFilled
      end
    end
    if filled == nil or filled == false then
      local tableSetOk, tableFilled = pcall(function()
        return created:SetData(samples, 0)
      end)
      if tableSetOk then
        filled = tableFilled
      end
    end
    if filled == nil or filled == false then
      return nil
    end
    if created.samples ~= count or created.channels ~= 1 or created.frequency ~= SAMPLE_RATE then
      return nil
    end
    if false then
      pcall(function()
        created:LoadAudioData()
      end)
      if false then
        logger:warnOnce("clip-not-ready-" .. name, "clip is generated but not reported ready", name)
      end
    end
    if created.length <= 0 then
      return nil
    end
    return created
  end)
  if not ok or clip == nil then
    logger:warnOnce("clip-build-" .. name, "failed to synthesize audio clip", name)
    return nil
  end
  return clip
end

local function ensureSource(name)
  local existing = sources[name]
  if existing ~= nil then
    return existing
  end
  if runtimeScope == nil then
    return nil
  end
  local transform = nil
  if audioRootTransform ~= nil then
    transform = audioRootTransform:Find(name)
  end
  if transform == nil then
    transform = runtimeScope:GetTransformByPath(AUDIO_ROOT .. "/" .. name)
  end
  if transform == nil then
    logger:warnOnce("node-missing", "RuntimeAudio node is missing", name)
    return nil
  end
  local gameObject = transform.gameObject
  local source = gameObject:GetComponent(typeof(AudioSource))
  if source == nil then
    local ok, added = pcall(function()
      return gameObject:AddComponent(typeof(AudioSource))
    end)
    if ok then
      source = added
    end
  end
  if source == nil then
    logger:warnOnce("source-missing", "AudioSource could not be created", name)
    return nil
  end
  source.playOnAwake = false
  source.loop = false
  source.spatialBlend = 0
  source.dopplerLevel = 0
  source.volume = MasterVolume
  source.mute = false
  source.priority = 128
  local clip = clips[name]
  if clip == nil then
    clip = buildClip(name)
    clips[name] = clip
  end
  if clip ~= nil then
    source.clip = clip
    if source.clip == nil then
      logger:warnOnce("clip-assign-" .. name, "AudioSource.clip assignment failed", name)
    end
  else
    logger:warnOnce("clip-nil-" .. name, "audio clip is unavailable", name)
  end
  sources[name] = source
  return source
end

local function ensureReady()
  if ready then
    return
  end
  ready = true
  if runtimeScope == nil then
    UnityEngine.Debug.LogError("VFX_AUDIO scope missing");logger:warnOnce("scope-missing", "audio script cannot resolve runtime scope")
    return
  end
  audioRootTransform = runtimeScope:GetTransformByPath(AUDIO_ROOT)
  if audioRootTransform == nil then
    UnityEngine.Debug.LogError("VFX_AUDIO root missing");logger:warnOnce("root-missing", "RuntimeAudio root is missing")
    return
  end
  local generated = 0
  for index = 1, #SOUND_NAMES do
    local source = ensureSource(SOUND_NAMES[index])
    if source ~= nil and source.clip ~= nil then
      generated = generated + 1
    end
  end
  UnityEngine.Debug.LogError("VFX_AUDIO clips="..generated.."/"..#SOUND_NAMES);logger:info("audio clips ready", generated, "/", #SOUND_NAMES)
end

function Start()
  -- Live combat uses the original audio bank. Keep this optional preview bank
  -- lazy so unused sample synthesis cannot stall the first gameplay frames.
end

function PlaySound(name, volumeScale)
  if not EnableRuntimeAudio then
    return false
  end
  ensureReady()
  local source = ensureSource(name)
  if source == nil or source.clip == nil then
    return false
  end
  source.volume = MasterVolume
  local scale = volumeScale
  if scale == nil then
    scale = 1
  end
  source:PlayOneShot(source.clip, scale)
  return true
end

function GetClip(name)
  ensureReady()
  local clip = clips[name]
  if clip == nil then
    clip = buildClip(name)
    clips[name] = clip
  end
  return clip
end

function GetAudioSource(name)
  ensureReady()
  return ensureSource(name)
end
-- Clips are generated once per module instance and released with that instance.
function OnDestroy()
  for _,source in pairs(sources)do
    pcall(function()source:Stop();source.clip=nil end)
  end
  for _,clip in pairs(clips)do
    if clip~=nil then UnityEngine.Object.Destroy(clip)end
  end
  sources={};clips={};ready=false;audioRootTransform=nil
end
