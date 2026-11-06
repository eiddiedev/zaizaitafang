-- Runtime UI tween 动画 ModuleScript。
-- 每个 ui.lua 调用一次 Animation.create()，避免不同 UI 共享 tween 和节点缓存。

local UnityEngine = CS.UnityEngine
local CanvasGroupType = typeof(CS.UnityEngine.CanvasGroup)
local RectTransformType = typeof(CS.UnityEngine.RectTransform)
local Logger = require("official.core.logger")

local Animation = {}

function Animation.create(loggerTag)
    local animationLogger = Logger.create(loggerTag or "runtime-ui-animation")
    local Anim = {}

    local activeTweens = {}
    local origPositions = {}
    local origScales = {}

    local Ease = {
        linear = function(t) return t end,
        outQuad = function(t) return 1 - (1 - t) * (1 - t) end,
        outCubic = function(t)
            local u = 1 - t
            return 1 - u * u * u
        end,
        outBack = function(t)
            local c1, c3 = 1.70158, 2.70158
            local u = t - 1
            return 1 + c3 * u * u * u + c1 * u * u
        end,
    }

    -- 同一 (target, channel) 只保留一条 tween：注册前清掉旧的
    local function removeChannel(target, channel)
        if target == nil or channel == nil then
            return
        end
        local i = 1
        while i <= #activeTweens do
            local tw = activeTweens[i]
            if tw.target == target and tw.channel == channel then
                table.remove(activeTweens, i)
            else
                i = i + 1
            end
        end
    end

    local function addTween(tw)
        tw.elapsed = 0
        removeChannel(tw.target, tw.channel)
        activeTweens[#activeTweens + 1] = tw
    end

    -- 由 ui.lua 的 Update() 每帧调用；dt 传 unscaledDeltaTime（不受 timeScale / 暂停影响）
    function Anim.tick(dt)
        dt = dt or UnityEngine.Time.unscaledDeltaTime
        local i = 1
        while i <= #activeTweens do
            local tw = activeTweens[i]
            tw.elapsed = tw.elapsed + dt
            local finished = false   -- true => 移除该 tween
            local completed = false  -- true => 自然播完，触发 onComplete
            if tw.loopFn then
                local wait = tw.delay or 0
                if tw.elapsed >= wait then
                    local ok, ret = pcall(tw.loopFn, tw.elapsed - wait)
                    if not ok or ret == false then
                        finished = true   -- 显式 return false 或目标销毁 → 自止
                    end
                end
            else
                local t = (tw.elapsed - (tw.delay or 0)) / tw.duration
                if t >= 1 then
                    pcall(tw.apply, 1)    -- 强制落精确终态
                    finished = true
                    completed = true
                elseif t > 0 then
                    if not pcall(tw.apply, (tw.ease or Ease.outQuad)(t)) then
                        finished = true   -- 写属性抛错 = 目标已销毁，当帧回收
                    end
                end
            end
            if finished then
                table.remove(activeTweens, i)   -- 先移除再触发 onComplete，避免链式 addTween 与自身同通道冲突
                if completed and tw.onComplete then
                    pcall(tw.onComplete)
                end
            else
                i = i + 1
            end
        end
    end

    local function getCanvasGroup(go)
        local cg = go:GetComponent(CanvasGroupType)
        if cg == nil then
            cg = go:AddComponent(CanvasGroupType)
        end
        return cg
    end

    local function getOrigPos(go)
        local rec = origPositions[go]
        if rec == nil then
            local rect = go:GetComponent(RectTransformType)
            if rect == nil then
                return nil
            end
            local p = rect.anchoredPosition
            rec = { rect = rect, x = p.x, y = p.y }
            origPositions[go] = rec
        end
        return rec
    end

    local function getOrigScale(go)
        local rec = origScales[go]
        if rec == nil then
            local s = go.transform.localScale
            rec = { x = s.x, y = s.y, z = s.z }
            origScales[go] = rec
        end
        return rec
    end

    -- ===== 入场 =====

    function Anim.fadeIn(go, duration, delay)
        if go == nil then return end
        local cg = getCanvasGroup(go)
        cg.alpha = 0
        cg.blocksRaycasts = false   -- 延迟 / 淡入期间不接收点击
        addTween({
            target = go, channel = "alpha",
            duration = duration or 0.3, delay = delay, ease = Ease.outQuad,
            apply = function(v) cg.alpha = v end,
            onComplete = function()
                cg.alpha = 1
                cg.blocksRaycasts = true
            end,
        })
    end

    function Anim.slideIn(go, dx, dy, duration, delay)
        if go == nil then return end
        local rec = getOrigPos(go)
        if rec == nil then return end
        rec.rect.anchoredPosition = UnityEngine.Vector2(rec.x + dx, rec.y + dy)
        addTween({
            target = go, channel = "pos",
            duration = duration or 0.35, delay = delay, ease = Ease.outCubic,
            apply = function(v)
                rec.rect.anchoredPosition = UnityEngine.Vector2(rec.x + dx * (1 - v), rec.y + dy * (1 - v))
            end,
        })
    end

    function Anim.scaleIn(go, duration, delay)
        if go == nil then return end
        local tr = go.transform
        local cg = getCanvasGroup(go)
        local base = getOrigScale(go)
        cg.alpha = 0
        cg.blocksRaycasts = false
        tr.localScale = UnityEngine.Vector3(base.x * 0.7, base.y * 0.7, base.z)
        local d = duration or 0.3
        addTween({
            target = go, channel = "scale",
            duration = d, delay = delay, ease = Ease.outBack,
            apply = function(v)
                local k = 0.7 + 0.3 * v
                tr.localScale = UnityEngine.Vector3(base.x * k, base.y * k, base.z)
            end,
        })
        addTween({
            target = go, channel = "alpha",
            duration = d * 0.5, delay = delay, ease = Ease.outQuad,
            apply = function(v) cg.alpha = v end,
            onComplete = function()
                cg.alpha = 1
                cg.blocksRaycasts = true
            end,
        })
    end

    -- ===== 退场 =====

    function Anim.fadeOutThen(go, duration, onDone)
        if go == nil then
            if onDone then onDone() end   -- 节点缺失也走回调，业务时序不断
            return
        end
        local cg = getCanvasGroup(go)
        addTween({
            target = go, channel = "alpha",
            duration = duration or 0.2, ease = Ease.outQuad,
            apply = function(v) cg.alpha = 1 - v end,
            onComplete = function()
                cg.alpha = 1               -- 复位，下次显示从干净状态开始
                if onDone then onDone() end -- 播完才轮到 SetActive(false)
            end,
        })
    end

    -- ===== 反馈 =====

    function Anim.pop(go, amount)
        if go == nil then return end
        local tr = go.transform
        local base = getOrigScale(go)
        local k = amount or 0.12
        addTween({
            target = go, channel = "scale",
            duration = 0.1, ease = Ease.outQuad,
            apply = function(v)
                local s = 1 + k * v
                tr.localScale = UnityEngine.Vector3(base.x * s, base.y * s, base.z)
            end,
            onComplete = function()
                addTween({
                    target = go, channel = "scale",
                    duration = 0.18, ease = Ease.outBack,
                    apply = function(v)
                        local s = 1 + k * (1 - v)
                        tr.localScale = UnityEngine.Vector3(base.x * s, base.y * s, base.z)
                    end,
                })
            end,
        })
    end

    function Anim.shake(go)
        if go == nil then return end
        local rec = getOrigPos(go)
        if rec == nil then return end
        addTween({
            target = go, channel = "pos",
            duration = 0.4, ease = Ease.linear,
            apply = function(v)
                rec.rect.anchoredPosition = UnityEngine.Vector2(
                    rec.x + 8 * math.sin(v * math.pi * 6) * (1 - v),   -- 衰减正弦，v=1 严格回原位
                    rec.y)
            end,
        })
    end

    function Anim.flash(go)
        if go == nil then return end
        local cg = getCanvasGroup(go)
        addTween({
            target = go, channel = "alpha",
            duration = 0.5, ease = Ease.linear,
            apply = function(v) cg.alpha = 0.55 + 0.45 * math.cos(v * math.pi * 4) end,
            onComplete = function() cg.alpha = 1 end,
        })
    end

    -- ===== 循环强调（stopWhen 返回 true 时复位并自止）=====

    function Anim.pulseScale(go, stopWhen, period, amplitude, delay)
        if go == nil then return end
        local tr = go.transform
        local base = getOrigScale(go)
        period = period or 1.2
        amplitude = amplitude or 0.04
        addTween({
            target = go, channel = "scale", delay = delay,
            loopFn = function(s)
                if stopWhen and stopWhen() then
                    tr.localScale = UnityEngine.Vector3(base.x, base.y, base.z)
                    return false
                end
                local k = 1 + amplitude * math.sin(s / period * 2 * math.pi)
                tr.localScale = UnityEngine.Vector3(base.x * k, base.y * k, base.z)
            end,
        })
    end

    function Anim.breatheAlpha(go, stopWhen, period, delay)
        if go == nil then return end
        local cg = getCanvasGroup(go)
        period = period or 1.2
        addTween({
            target = go, channel = "alpha", delay = delay,
            loopFn = function(s)
                if stopWhen and stopWhen() then
                    cg.alpha = 1
                    return false
                end
                cg.alpha = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(s / period * 2 * math.pi))
            end,
        })
    end

    function Anim.spin(go, stopWhen, degPerSec)
        if go == nil then return end
        local tr = go.transform
        degPerSec = degPerSec or 360
        addTween({
            target = go, channel = "rotation",
            loopFn = function(s)
                if stopWhen and stopWhen() then
                    tr.localEulerAngles = UnityEngine.Vector3(0, 0, 0)
                    return false
                end
                tr.localEulerAngles = UnityEngine.Vector3(0, 0, -(s * degPerSec) % 360)
            end,
        })
    end

    -- ===== 入场配置表装配器（可选便捷入口）=====

    local entrancePresets = {
        fadeIn = function(go, e)
            Anim.fadeIn(go, e.duration, e.delay)
        end,
        scaleIn = function(go, e)
            Anim.scaleIn(go, e.duration, e.delay)
        end,
        slideInLeft = function(go, e)
            Anim.slideIn(go, e.dx or -120, e.dy or 0, e.duration, e.delay)
        end,
        slideInRight = function(go, e)
            Anim.slideIn(go, e.dx or 120, e.dy or 0, e.duration, e.delay)
        end,
        slideInTop = function(go, e)
            Anim.slideIn(go, e.dx or 0, e.dy or 120, e.duration, e.delay)
        end,
        slideInBottom = function(go, e)
            Anim.slideIn(go, e.dx or 0, e.dy or -120, e.duration, e.delay)
        end,
    }

    -- entries: { { node = "<data-u-name>", preset = "<预设名>", delay = 秒, duration = 秒, dx = 像素, dy = 像素 }, ... }
    -- resolve: function(nodeName) -> GameObject
    function Anim.playEntrance(entries, resolve)
        if entries == nil or resolve == nil then
            return
        end
        for _, e in ipairs(entries) do
            local go = resolve(e.node)
            if go == nil then
                animationLogger:warn("entrance node not found", e.node)
            else
                local play = entrancePresets[e.preset]
                if play == nil then
                    animationLogger:warn("unknown entrance preset", e.preset)
                else
                    play(go, e)
                end
            end
        end
    end

    function Anim.clearAll()
        activeTweens = {}
        origPositions = {}
        origScales = {}
    end

    return Anim
end

return Animation
