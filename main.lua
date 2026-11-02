-- NEON PLASMA PONG — Love2D 11.5
-- Pseudo-3D + plasma FX + power-ups + heat combo + AI + dash + slow-mo
-- Controls:
--   P1: W/S move, LShift dash
--   P2: Up/Down move, RShift dash (or AI)
--   Space serve | Tab toggle AI | R restart match | Esc quit

local W, H = 1280, 720
local MAX_BALL_SPEED = 880
local WIN_SCORE = 7

local time = 0
local shake = { x = 0, y = 0, trauma = 0 }
local scorePop = { left = 0, right = 0 }
local flash = 0
local waitingToServe = true
local gameOver = false
local winner = nil
local aiEnabled = true
local timeScale = 1
local slowMo = 0
local heat = 0
local combo = 0
local comboText = { life = 0, text = "", x = 0, y = 0 }
local powerups = {}
local powerupTimer = 0
local banners = {}
local particles = {}
local trails = {}
local ambient = {}
local fonts = {}
local shaders = {}
local canvas
local sfx = {}

local POWER_DEFS = {
    grow = { label = "GROW", color = {0.3, 1.0, 0.55}, seconds = 6 },
    freeze = { label = "FREEZE", color = {0.55, 0.85, 1.0}, seconds = 2.2 },
    fire = { label = "FIREBALL", color = {1.0, 0.45, 0.15}, seconds = 5 },
    shield = { label = "SHIELD", color = {0.95, 0.85, 0.25}, seconds = 7 },
}

------------------------------------------------------------
-- Audio
------------------------------------------------------------
local function makeTone(freq, duration, kind)
    local rate = 44100
    local n = math.floor(rate * duration)
    local data = love.sound.newSoundData(n, rate, 16, 1)
    for i = 0, n - 1 do
        local t = i / rate
        local env = (1 - t / duration)
        env = env * env
        local sample
        if kind == "noise" then
            sample = (love.math.random() * 2 - 1) * env * 0.35
        elseif kind == "saw" then
            sample = (2 * ((t * freq) % 1) - 1) * env * 0.28
        else
            sample = math.sin(t * freq * math.pi * 2) * env * 0.4
        end
        data:setSample(i, sample)
    end
    return love.audio.newSource(data, "static")
end

local function playSfx(name, vol)
    if not sfx[name] then return end
    local clone = sfx[name]:clone()
    clone:setVolume(vol or 0.55)
    clone:play()
end

------------------------------------------------------------
-- FX helpers
------------------------------------------------------------
local function spawnBurst(x, y, color, count, speed)
    count = count or 24
    speed = speed or 220
    for _ = 1, count do
        local a = love.math.random() * math.pi * 2
        local s = speed * (0.35 + love.math.random() * 0.9)
        particles[#particles + 1] = {
            x = x, y = y,
            dx = math.cos(a) * s, dy = math.sin(a) * s,
            life = 0.35 + love.math.random() * 0.55, max = 0.9,
            size = 2 + love.math.random() * 5,
            color = { color[1], color[2], color[3] }, glow = true
        }
    end
end

local function spawnPlasmaRing(x, y, color)
    for i = 1, 40 do
        local a = (i / 40) * math.pi * 2
        particles[#particles + 1] = {
            x = x, y = y,
            dx = math.cos(a) * 300, dy = math.sin(a) * 300,
            life = 0.45, max = 0.45, size = 4,
            color = { color[1], color[2], color[3] }, glow = true
        }
    end
end

local function pushTrail(x, y, color, size)
    trails[#trails + 1] = {
        x = x, y = y, life = 0.35, max = 0.35,
        size = size or ball.size, color = color
    }
    if #trails > 56 then table.remove(trails, 1) end
end

local function addShake(amount)
    shake.trauma = math.min(1, shake.trauma + amount)
end

local function pushBanner(text, color)
    banners[#banners + 1] = {
        text = text, color = color or {1, 1, 1},
        life = 1.4, max = 1.4, y = H * 0.28
    }
end

local function showCombo(text)
    comboText.life = 1.0
    comboText.text = text
    comboText.x = W / 2
    comboText.y = H * 0.34
end

------------------------------------------------------------
-- Entities
------------------------------------------------------------
local function basePaddleHeight()
    return 130
end

local function resetPaddleStats(p)
    p.height = basePaddleHeight()
    p.frozen = 0
    p.shield = 0
    p.dash = 0
    p.dashCd = 0
    p.grow = 0
end

local function resetBall(serving)
    ball.x = (W - ball.size) / 2
    ball.y = (H - ball.size) / 2
    ball.speed = ball.baseSpeed
    ball.pulse = 0
    ball.spin = 0
    ball.fire = 0
    local direction = love.math.random(2) == 1 and -1 or 1
    local angle = love.math.random() * math.pi / 3 - math.pi / 6
    ball.dx = math.cos(angle) * ball.speed * direction
    ball.dy = math.sin(angle) * ball.speed
    waitingToServe = serving ~= false
end

local function resetMatch()
    scores = { player1 = 0, player2 = 0 }
    combo = 0
    heat = 0
    gameOver = false
    winner = nil
    powerups = {}
    powerupTimer = 3
    resetPaddleStats(player1)
    resetPaddleStats(player2)
    player1.y = (H - player1.height) / 2
    player2.y = (H - player2.height) / 2
    resetBall(true)
    pushBanner("MATCH START", {0.7, 0.95, 1.0})
end

function love.load()
    love.window.setTitle("NEON PLASMA PONG")
    love.window.setMode(W, H, { vsync = 1, msaa = 4, resizable = false })
    love.graphics.setDefaultFilter("linear", "linear")
    love.math.setRandomSeed(os.time())

    fonts.score = love.graphics.newFont(72)
    fonts.ui = love.graphics.newFont(22)
    fonts.title = love.graphics.newFont(48)
    fonts.small = love.graphics.newFont(16)
    fonts.banner = love.graphics.newFont(34)

    canvas = love.graphics.newCanvas(W, H)

    shaders.plasma = love.graphics.newShader([[
        extern number time;
        extern vec2 resolution;
        extern number heat;
        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
            vec2 p = (px / resolution) * 2.0 - 1.0;
            p.x *= resolution.x / resolution.y;
            float t = time * 0.35;
            float v = 0.0;
            v += sin((p.x + t) * 3.0);
            v += sin((p.y + t * 1.3) * 2.4);
            v += sin((p.x + p.y + t * 0.7) * 2.0);
            v += sin(length(p + vec2(sin(t), cos(t * 0.8))) * 4.0);
            v *= 0.25;
            vec3 c1 = vec3(0.02, 0.05, 0.12);
            vec3 c2 = vec3(0.05, 0.55, 0.85);
            vec3 c3 = vec3(0.95, 0.25, 0.35);
            vec3 c4 = vec3(1.0, 0.75, 0.2);
            vec3 col = mix(c1, c2, smoothstep(-0.4, 0.6, v));
            col = mix(col, c3, smoothstep(0.35, 0.95, v) * 0.45);
            col = mix(col, c4, heat * smoothstep(0.2, 1.0, v) * 0.55);
            float vignette = smoothstep(1.45, 0.25, length(p));
            col *= 0.55 + vignette * 0.55;
            return vec4(col, 1.0) * color;
        }
    ]])

    local paddleW, paddleSpeed, margin = 20, 520, 42
    player1 = {
        x = margin, y = (H - 130) / 2, width = paddleW, height = 130,
        speed = paddleSpeed, color = {0.15, 0.85, 1.0},
        glow = 0, tilt = 0, side = "left"
    }
    player2 = {
        x = W - margin - paddleW, y = (H - 130) / 2, width = paddleW, height = 130,
        speed = paddleSpeed, color = {1.0, 0.35, 0.42},
        glow = 0, tilt = 0, side = "right"
    }
    resetPaddleStats(player1)
    resetPaddleStats(player2)

    ball = {
        size = 16, x = 0, y = 0, dx = 0, dy = 0,
        baseSpeed = 360, speed = 360, speedBoost = 1.055,
        color = {1, 1, 1}, pulse = 0, spin = 0, fire = 0
    }
    scores = { player1 = 0, player2 = 0 }

    for i = 1, 70 do
        ambient[i] = {
            x = love.math.random() * W, y = love.math.random() * H,
            z = love.math.random(), s = 0.6 + love.math.random() * 2.2,
            a = love.math.random() * math.pi * 2
        }
    end

    sfx.hit = makeTone(520, 0.08, "saw")
    sfx.wall = makeTone(220, 0.06, "sine")
    sfx.score = makeTone(140, 0.28, "saw")
    sfx.serve = makeTone(660, 0.12, "sine")
    sfx.power = makeTone(880, 0.16, "sine")
    sfx.dash = makeTone(180, 0.07, "noise")
    sfx.win = makeTone(440, 0.4, "saw")

    resetBall(true)
    pushBanner("TAB = AI ON/OFF", {0.8, 0.9, 1.0})
end

------------------------------------------------------------
-- Collision / powerups
------------------------------------------------------------
function checkCollision(a, b)
    return a.x < b.x + b.width
        and b.x < a.x + a.width
        and a.y < b.y + b.height
        and b.y < a.y + a.height
end

local function verticalOverlap(ballY, ballSize, paddle)
    return ballY < paddle.y + paddle.height and paddle.y < ballY + ballSize
end

local function spawnPowerup()
    if #powerups >= 2 or gameOver or waitingToServe then return end
    local kinds = { "grow", "freeze", "fire", "shield" }
    local kind = kinds[love.math.random(#kinds)]
    powerups[#powerups + 1] = {
        kind = kind,
        x = W * (0.35 + love.math.random() * 0.3),
        y = 120 + love.math.random() * (H - 240),
        r = 18,
        bob = love.math.random() * math.pi * 2,
        life = 12,
        taken = false
    }
end

local function applyPowerup(kind, owner, enemy)
    local def = POWER_DEFS[kind]
    playSfx("power", 0.7)
    pushBanner(def.label .. "!", def.color)
    spawnPlasmaRing(ball.x + ball.size / 2, ball.y + ball.size / 2, def.color)
    addShake(0.25)

    if kind == "grow" then
        owner.grow = def.seconds
        owner.height = math.min(220, basePaddleHeight() * 1.55)
    elseif kind == "freeze" then
        enemy.frozen = def.seconds
        spawnBurst(enemy.x + enemy.width / 2, enemy.y + enemy.height / 2, def.color, 30, 200)
    elseif kind == "fire" then
        ball.fire = def.seconds
        ball.speed = math.min(MAX_BALL_SPEED, ball.speed * 1.35)
        local len = math.sqrt(ball.dx * ball.dx + ball.dy * ball.dy)
        if len > 0 then
            ball.dx = ball.dx / len * ball.speed
            ball.dy = ball.dy / len * ball.speed
        end
    elseif kind == "shield" then
        owner.shield = def.seconds
    end
end

local function ownerFromBallDir()
    -- Last hit side: if ball going right, left player hit last
    if ball.dx > 0 then return player1, player2 end
    return player2, player1
end

local function tryCollectPowerups()
    local ballRect = {
        x = ball.x, y = ball.y, width = ball.size, height = ball.size
    }
    for i = #powerups, 1, -1 do
        local p = powerups[i]
        local orb = { x = p.x - p.r, y = p.y - p.r, width = p.r * 2, height = p.r * 2 }
        if checkCollision(ballRect, orb) then
            local owner, enemy = ownerFromBallDir()
            applyPowerup(p.kind, owner, enemy)
            table.remove(powerups, i)
        end
    end
end

local function reflectFromPaddle(paddle, goingRight)
    ball.speed = math.min(ball.speed * ball.speedBoost, MAX_BALL_SPEED)
    if ball.fire > 0 then
        ball.speed = math.min(MAX_BALL_SPEED, ball.speed * 1.04)
    end

    local paddleCenter = paddle.y + paddle.height / 2
    local ballCenter = ball.y + ball.size / 2
    local offset = (ballCenter - paddleCenter) / (paddle.height / 2)
    offset = math.max(-1, math.min(1, offset))

    local angle = offset * (math.pi / 3.1)
    local dir = goingRight and 1 or -1
    ball.dx = math.cos(angle) * ball.speed * dir
    ball.dy = math.sin(angle) * ball.speed
    ball.spin = offset * 14
    ball.pulse = 1
    paddle.glow = 1
    paddle.tilt = offset * 0.35

    if goingRight then ball.x = paddle.x + paddle.width
    else ball.x = paddle.x - ball.size end

    combo = combo + 1
    heat = math.min(1, heat + 0.08 + combo * 0.01)
    if combo >= 3 then
        showCombo(combo .. " HIT COMBO")
    end
    if combo == 5 then pushBanner("HEATED!", {1.0, 0.7, 0.2}) end
    if combo == 8 then pushBanner("OVERDRIVE", {1.0, 0.4, 0.2}) end

    local cx = ball.x + ball.size / 2
    local cy = ball.y + ball.size / 2
    spawnBurst(cx, cy, paddle.color, 28 + math.floor(heat * 20), 300 + heat * 180)
    spawnPlasmaRing(cx, cy, paddle.color)
    addShake(0.28 + heat * 0.2)
    flash = 0.14
    playSfx("hit")
end

local function tryHitPaddle(paddle, prevX, isLeft)
    if isLeft then
        local faceX = paddle.x + paddle.width
        if ball.dx >= 0 then return end
        local crossed = prevX >= faceX and ball.x < faceX
        local overlaps = checkCollision({
            x = ball.x, y = ball.y, width = ball.size, height = ball.size
        }, paddle)
        if (crossed or overlaps) and verticalOverlap(ball.y, ball.size, paddle) then
            reflectFromPaddle(paddle, true)
        end
    else
        local faceX = paddle.x
        if ball.dx <= 0 then return end
        local ballRightPrev = prevX + ball.size
        local ballRight = ball.x + ball.size
        local crossed = ballRightPrev <= faceX and ballRight > faceX
        local overlaps = checkCollision({
            x = ball.x, y = ball.y, width = ball.size, height = ball.size
        }, paddle)
        if (crossed or overlaps) and verticalOverlap(ball.y, ball.size, paddle) then
            reflectFromPaddle(paddle, false)
        end
    end
end

local function clampPaddle(paddle)
    if paddle.y < 24 then paddle.y = 24 end
    if paddle.y + paddle.height > H - 24 then
        paddle.y = H - 24 - paddle.height
    end
end

local function tryDash(paddle, dir)
    if paddle.dashCd > 0 or paddle.frozen > 0 or dir == 0 then return end
    paddle.dash = 0.12
    paddle.dashCd = 0.85
    paddle.y = paddle.y + dir * 90
    clampPaddle(paddle)
    paddle.glow = 1
    spawnBurst(paddle.x + paddle.width / 2, paddle.y + paddle.height / 2, paddle.color, 18, 260)
    playSfx("dash", 0.4)
    addShake(0.12)
end

local function updateAI(dt)
    if not aiEnabled or player2.frozen > 0 then return end
    local target = ball.y + ball.size / 2 - player2.height / 2
    -- Predict a bit when ball comes toward AI
    if ball.dx > 0 and not waitingToServe then
        local t = (player2.x - (ball.x + ball.size)) / math.max(ball.dx, 1)
        target = ball.y + ball.dy * t * 0.85 + ball.size / 2 - player2.height / 2
    elseif waitingToServe then
        target = (H - player2.height) / 2
    end
    -- Imperfection scales inversely with heat (harder when heated)
    target = target + math.sin(time * 2.3) * (28 - heat * 16)
    local center = player2.y
    local diff = target - center
    local dir = 0
    if math.abs(diff) > 8 then
        dir = diff > 0 and 1 or -1
        player2.y = player2.y + dir * player2.speed * 0.92 * dt
        player2.tilt = dir * 0.12
    end
    -- Occasional dash to save
    if ball.dx > 0 and math.abs(diff) > 70 and player2.dashCd <= 0 and love.math.random() < 0.02 then
        tryDash(player2, dir ~= 0 and dir or 1)
    end
    clampPaddle(player2)
end

local function scorePoint(scoredBy)
    if scoredBy == 1 then
        scores.player1 = scores.player1 + 1
        scorePop.left = 1
        spawnBurst(W - 40, ball.y, player1.color, 55, 450)
    else
        scores.player2 = scores.player2 + 1
        scorePop.right = 1
        spawnBurst(40, ball.y, player2.color, 55, 450)
    end
    combo = 0
    heat = math.max(0, heat - 0.35)
    ball.fire = 0
    addShake(0.55)
    flash = 0.35
    slowMo = 0.55
    playSfx("score")

    if scores.player1 >= WIN_SCORE or scores.player2 >= WIN_SCORE then
        gameOver = true
        winner = scores.player1 >= WIN_SCORE and 1 or 2
        waitingToServe = true
        pushBanner(winner == 1 and "CYAN WINS" or "CRIMSON WINS",
            winner == 1 and player1.color or player2.color)
        playSfx("win", 0.7)
        spawnPlasmaRing(W / 2, H / 2, winner == 1 and player1.color or player2.color)
    else
        resetBall(true)
    end
end

------------------------------------------------------------
-- Update
------------------------------------------------------------
function love.update(dt)
    local rawDt = dt
    if slowMo > 0 then
        slowMo = math.max(0, slowMo - rawDt)
        timeScale = 0.35
    else
        timeScale = 1
    end
    dt = rawDt * timeScale
    time = time + dt

    shake.trauma = math.max(0, shake.trauma - rawDt * 1.6)
    local t = shake.trauma
    shake.x = (love.math.random() * 2 - 1) * t * t * 18
    shake.y = (love.math.random() * 2 - 1) * t * t * 18
    flash = math.max(0, flash - rawDt)
    scorePop.left = math.max(0, scorePop.left - rawDt * 2.2)
    scorePop.right = math.max(0, scorePop.right - rawDt * 2.2)
    comboText.life = math.max(0, comboText.life - rawDt)
    heat = math.max(0, heat - rawDt * 0.03)

    for _, p in ipairs({ player1, player2 }) do
        p.glow = math.max(0, p.glow - dt * 1.8)
        p.tilt = p.tilt + (0 - p.tilt) * math.min(1, dt * 8)
        p.dashCd = math.max(0, p.dashCd - rawDt)
        p.dash = math.max(0, p.dash - rawDt)
        p.frozen = math.max(0, p.frozen - dt)
        p.shield = math.max(0, p.shield - dt)
        if p.grow > 0 then
            p.grow = math.max(0, p.grow - dt)
            if p.grow <= 0 then p.height = basePaddleHeight() end
        end
    end
    ball.pulse = math.max(0, ball.pulse - dt * 2.5)
    ball.fire = math.max(0, ball.fire - dt)

    -- banners / particles / ambient
    for i = #banners, 1, -1 do
        banners[i].life = banners[i].life - rawDt
        banners[i].y = banners[i].y - rawDt * 18
        if banners[i].life <= 0 then table.remove(banners, i) end
    end
    for _, a in ipairs(ambient) do
        a.a = a.a + dt * (0.2 + a.z)
        a.y = a.y + math.sin(a.a) * dt * (8 + a.z * 20)
        a.x = a.x + math.cos(a.a * 0.7) * dt * (4 + a.z * 10)
        if a.x < -10 then a.x = W + 10 end
        if a.x > W + 10 then a.x = -10 end
        if a.y < -10 then a.y = H + 10 end
        if a.y > H + 10 then a.y = -10 end
    end
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - rawDt
        p.x = p.x + p.dx * dt
        p.y = p.y + p.dy * dt
        p.dx = p.dx * (1 - dt * 2.2)
        p.dy = p.dy * (1 - dt * 2.2) + 40 * dt
        if p.life <= 0 then table.remove(particles, i) end
    end
    for i = #trails, 1, -1 do
        trails[i].life = trails[i].life - rawDt
        if trails[i].life <= 0 then table.remove(trails, i) end
    end

    if gameOver then return end

    -- Player 1 input
    if player1.frozen <= 0 then
        local p1Dir = 0
        if love.keyboard.isScancodeDown("w") then p1Dir = -1
        elseif love.keyboard.isScancodeDown("s") then p1Dir = 1 end
        local boost = player1.dash > 0 and 2.2 or 1
        player1.y = player1.y + p1Dir * player1.speed * boost * dt
        if p1Dir ~= 0 then player1.tilt = p1Dir * 0.12 end
        if love.keyboard.isScancodeDown("lshift") then tryDash(player1, p1Dir ~= 0 and p1Dir or -1) end
    end
    clampPaddle(player1)

    -- Player 2 input or AI
    if not aiEnabled and player2.frozen <= 0 then
        local p2Dir = 0
        if love.keyboard.isScancodeDown("up") then p2Dir = -1
        elseif love.keyboard.isScancodeDown("down") then p2Dir = 1 end
        local boost = player2.dash > 0 and 2.2 or 1
        player2.y = player2.y + p2Dir * player2.speed * boost * dt
        if p2Dir ~= 0 then player2.tilt = p2Dir * 0.12 end
        if love.keyboard.isScancodeDown("rshift") then tryDash(player2, p2Dir ~= 0 and p2Dir or 1) end
        clampPaddle(player2)
    else
        updateAI(dt)
    end

    -- Powerup spawn timer
    powerupTimer = powerupTimer - dt
    if powerupTimer <= 0 then
        spawnPowerup()
        powerupTimer = 6 + love.math.random() * 5
    end
    for i = #powerups, 1, -1 do
        local p = powerups[i]
        p.bob = p.bob + dt * 3
        p.y = p.y + math.sin(p.bob) * dt * 18
        p.life = p.life - dt
        if p.life <= 0 then table.remove(powerups, i) end
    end

    if waitingToServe then return end

    local prevX = ball.x
    ball.x = ball.x + ball.dx * dt
    ball.y = ball.y + ball.dy * dt
    ball.spin = ball.spin + ball.dx * dt * 0.02

    local bx = ball.x + ball.size / 2
    local by = ball.y + ball.size / 2
    local speedFactor = math.min(1, ball.speed / MAX_BALL_SPEED)
    local trailColor = ball.fire > 0
        and {1.0, 0.45 + 0.3 * math.sin(time * 20), 0.1}
        or {0.4 + 0.6 * speedFactor, 0.7 - 0.3 * speedFactor, 1.0 - 0.4 * speedFactor}

    if love.math.random() < 0.75 then pushTrail(bx, by, trailColor) end
    if love.math.random() < 0.5 then
        particles[#particles + 1] = {
            x = bx, y = by,
            dx = -ball.dx * 0.05 + (love.math.random() - 0.5) * 40,
            dy = -ball.dy * 0.05 + (love.math.random() - 0.5) * 40,
            life = 0.2, max = 0.2, size = 2 + love.math.random() * 2,
            color = trailColor, glow = true
        }
    end

    if ball.y <= 24 then
        ball.y = 24
        ball.dy = math.abs(ball.dy)
        spawnBurst(bx, 28, {0.6, 0.9, 1.0}, 14, 160)
        addShake(0.12)
        playSfx("wall")
    elseif ball.y + ball.size >= H - 24 then
        ball.y = H - 24 - ball.size
        ball.dy = -math.abs(ball.dy)
        spawnBurst(bx, H - 28, {0.6, 0.9, 1.0}, 14, 160)
        addShake(0.12)
        playSfx("wall")
    end

    tryHitPaddle(player1, prevX, true)
    tryHitPaddle(player2, prevX, false)
    tryCollectPowerups()

    -- Shield edge save: if ball almost out and that side has shield, bounce
    if ball.x < 8 and player1.shield > 0 and ball.dx < 0 then
        ball.dx = math.abs(ball.dx)
        ball.x = 12
        player1.shield = 0
        pushBanner("SHIELD BREAK", POWER_DEFS.shield.color)
        spawnPlasmaRing(30, by, POWER_DEFS.shield.color)
        playSfx("power")
        addShake(0.3)
    elseif ball.x + ball.size > W - 8 and player2.shield > 0 and ball.dx > 0 then
        ball.dx = -math.abs(ball.dx)
        ball.x = W - 12 - ball.size
        player2.shield = 0
        pushBanner("SHIELD BREAK", POWER_DEFS.shield.color)
        spawnPlasmaRing(W - 30, by, POWER_DEFS.shield.color)
        playSfx("power")
        addShake(0.3)
    end

    if ball.x + ball.size < 0 then
        scorePoint(2)
    elseif ball.x > W then
        scorePoint(1)
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "tab" then
        aiEnabled = not aiEnabled
        pushBanner(aiEnabled and "AI ENABLED" or "2 PLAYER MODE", {0.85, 0.95, 1.0})
        playSfx("serve", 0.35)
    elseif key == "r" then
        resetMatch()
        playSfx("serve")
    elseif key == "space" and waitingToServe and not gameOver then
        waitingToServe = false
        ball.pulse = 1
        spawnPlasmaRing(ball.x + ball.size / 2, ball.y + ball.size / 2, {0.7, 0.95, 1.0})
        playSfx("serve")
    elseif key == "space" and gameOver then
        resetMatch()
    end
end

------------------------------------------------------------
-- Draw
------------------------------------------------------------
local function mix3(r1, g1, b1, r2, g2, b2, a)
    return r1 + (r2 - r1) * a, g1 + (g2 - g1) * a, b1 + (b2 - b1) * a
end

local function drawGlowRect(x, y, w, h, color, alpha, radius)
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.rectangle("fill", x, y, w, h, radius or 4, radius or 4)
end

local function drawPaddle3D(p)
    local frozenPulse = p.frozen > 0 and (0.4 + 0.3 * math.sin(time * 12)) or 0
    drawGlowRect(p.x - 10, p.y - 12, p.width + 20, p.height + 24, p.color, 0.12 + p.glow * 0.25, 12)
    drawGlowRect(p.x - 4, p.y - 4, p.width + 8, p.height + 8, p.color, 0.25 + p.glow * 0.35, 8)

    if p.shield > 0 then
        love.graphics.setColor(1, 0.9, 0.3, 0.25 + 0.15 * math.sin(time * 8))
        love.graphics.rectangle("line", p.x - 8, p.y - 10, p.width + 16, p.height + 20, 8, 8)
    end

    local skew = p.tilt * 10
    love.graphics.setColor(p.color[1] * 0.35, p.color[2] * 0.35, p.color[3] * 0.35, 0.9)
    love.graphics.polygon("fill",
        p.x + p.width, p.y,
        p.x + p.width + 8, p.y + 6 + skew,
        p.x + p.width + 8, p.y + p.height + 6 + skew,
        p.x + p.width, p.y + p.height
    )

    local strips = 10
    for i = 0, strips - 1 do
        local tt = i / (strips - 1)
        local shade = 0.55 + tt * 0.45 + math.sin(time * 6 + tt * 4) * 0.05
        local r, g, b = p.color[1] * shade, p.color[2] * shade, p.color[3] * shade
        if p.frozen > 0 then
            r, g, b = mix3(r, g, b, 0.6, 0.85, 1.0, frozenPulse)
        end
        love.graphics.setColor(r, g, b, 1)
        local sy = p.y + (p.height / strips) * i
        love.graphics.rectangle("fill", p.x, sy, p.width, p.height / strips + 1, 2, 2)
    end
    love.graphics.setColor(1, 1, 1, 0.45 + p.glow * 0.4)
    love.graphics.rectangle("fill", p.x + 3, p.y + 8, 3, p.height - 16, 2, 2)

    -- dash cooldown pip
    if p.dashCd > 0 then
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.rectangle("fill", p.x - 6, p.y + p.height + 8, p.width + 12, 4, 2, 2)
        love.graphics.setColor(p.color[1], p.color[2], p.color[3], 0.8)
        love.graphics.rectangle("fill", p.x - 6, p.y + p.height + 8, (p.width + 12) * (1 - p.dashCd / 0.85), 4, 2, 2)
    end
end

local function drawCourt()
    local floorTop = H * 0.22
    love.graphics.setColor(0.05, 0.12, 0.2, 0.55)
    love.graphics.polygon("fill",
        W * 0.08, H - 20, W * 0.92, H - 20,
        W * 0.72, floorTop, W * 0.28, floorTop
    )
    love.graphics.setLineWidth(1)
    for i = 0, 12 do
        local t = i / 12
        local y = floorTop + (H - 40 - floorTop) * (t * t)
        local u = (y - floorTop) / (H - 40 - floorTop)
        local left = W * (0.28 + (0.08 - 0.28) * u)
        local right = W * (0.72 + (0.92 - 0.72) * u)
        love.graphics.setColor(0.2, 0.75, 1.0, 0.08 + t * 0.12)
        love.graphics.line(left, y, right, y)
    end
    for i = 0, 10 do
        local t = i / 10
        local x0 = W * (0.28 + (0.72 - 0.28) * t)
        local x1 = W * (0.08 + (0.92 - 0.08) * t)
        love.graphics.setColor(0.95, 0.3, 0.45, 0.07)
        love.graphics.line(x0, floorTop, x1, H - 20)
    end

    love.graphics.setLineWidth(3)
    love.graphics.setColor(0.2, 0.85, 1.0, 0.55)
    love.graphics.line(28, 24, W - 28, 24)
    love.graphics.setColor(1.0, 0.35, 0.45, 0.55)
    love.graphics.line(28, H - 24, W - 28, H - 24)

    for i = 0, 16 do
        local y = 40 + i * 40
        local pulse = 0.35 + 0.25 * math.sin(time * 4 + i * 0.4)
        love.graphics.setColor(0.7, 0.85, 1.0, pulse * 0.35)
        love.graphics.rectangle("fill", W / 2 - 3, y, 6, 22, 3, 3)
    end
    love.graphics.setColor(0.15, 0.8, 1.0, 0.08 + 0.04 * math.sin(time * 3))
    love.graphics.rectangle("fill", 0, 0, 18, H)
    love.graphics.setColor(1.0, 0.3, 0.4, 0.08 + 0.04 * math.sin(time * 3 + 1))
    love.graphics.rectangle("fill", W - 18, 0, 18, H)
end

local function drawBall()
    local cx = ball.x + ball.size / 2
    local cy = ball.y + ball.size / 2
    local pulse = 1 + ball.pulse * 0.55 + math.sin(time * 10) * 0.05 + heat * 0.15
    local r = ball.size * 0.55 * pulse

    for _, tr in ipairs(trails) do
        local a = tr.life / tr.max
        love.graphics.setColor(tr.color[1], tr.color[2], tr.color[3], a * 0.35)
        love.graphics.circle("fill", tr.x, tr.y, tr.size * 0.35 * a)
    end

    if ball.fire > 0 then
        love.graphics.setColor(1.0, 0.35, 0.05, 0.22 + 0.1 * math.sin(time * 20))
        love.graphics.circle("fill", cx, cy, r * 3.8)
    end
    love.graphics.setColor(0.3, 0.85, 1.0, 0.12 + ball.pulse * 0.2 + heat * 0.1)
    love.graphics.circle("fill", cx, cy, r * 3.2)
    love.graphics.setColor(1.0, 0.4, 0.55, 0.14 + ball.pulse * 0.25)
    love.graphics.circle("fill", cx, cy, r * 2.2)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle("fill", cx, cy, r)
    love.graphics.setColor(0.4, 0.95, 1.0, 0.85)
    love.graphics.circle("fill", cx + math.cos(ball.spin) * r * 0.35, cy + math.sin(ball.spin) * r * 0.35, r * 0.35)
    love.graphics.setColor(1.0, 0.55, 0.35, 0.75)
    love.graphics.circle("fill", cx + math.cos(ball.spin + 2.1) * r * 0.28, cy + math.sin(ball.spin + 2.1) * r * 0.28, r * 0.22)
end

local function drawPowerups()
    for _, p in ipairs(powerups) do
        local def = POWER_DEFS[p.kind]
        local pulse = 1 + 0.12 * math.sin(p.bob * 2)
        love.graphics.setColor(def.color[1], def.color[2], def.color[3], 0.2)
        love.graphics.circle("fill", p.x, p.y, p.r * 2.2 * pulse)
        love.graphics.setColor(def.color[1], def.color[2], def.color[3], 0.85)
        love.graphics.circle("fill", p.x, p.y, p.r * pulse)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("fill", p.x - 3, p.y - 3, 4)
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(def.color[1], def.color[2], def.color[3], 0.9)
        love.graphics.printf(def.label, p.x - 40, p.y + p.r + 6, 80, "center")
    end
end

local function drawParticles()
    for _, p in ipairs(particles) do
        local a = math.max(0, p.life / (p.max or 0.5))
        love.graphics.setColor(p.color[1], p.color[2], p.color[3], a)
        love.graphics.circle("fill", p.x, p.y, p.size * a)
        if p.glow then
            love.graphics.setColor(p.color[1], p.color[2], p.color[3], a * 0.25)
            love.graphics.circle("fill", p.x, p.y, p.size * a * 2.4)
        end
    end
end

local function drawHeatBar()
    local bw, bh = 220, 10
    local x, y = (W - bw) / 2, 18
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", x, y, bw, bh, 4, 4)
    local c = {0.2 + heat * 0.8, 0.85 - heat * 0.5, 1.0 - heat * 0.7}
    love.graphics.setColor(c[1], c[2], c[3], 0.9)
    love.graphics.rectangle("fill", x, y, bw * heat, bh, 4, 4)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.printf("HEAT", x, y - 16, bw, "center")
end

local function drawUI()
    love.graphics.setFont(fonts.score)
    local ls = 1 + scorePop.left * 0.45
    local rs = 1 + scorePop.right * 0.45
    love.graphics.push()
    love.graphics.translate(W * 0.36, 86)
    love.graphics.scale(ls, ls)
    love.graphics.setColor(0.2, 0.9, 1.0, 0.9)
    love.graphics.printf(tostring(scores.player1), -80, -36, 160, "center")
    love.graphics.pop()
    love.graphics.push()
    love.graphics.translate(W * 0.64, 86)
    love.graphics.scale(rs, rs)
    love.graphics.setColor(1.0, 0.4, 0.45, 0.9)
    love.graphics.printf(tostring(scores.player2), -80, -36, 160, "center")
    love.graphics.pop()

    drawHeatBar()

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0.7, 0.85, 1.0, 0.5)
    love.graphics.print("W/S  ·  LShift dash", 40, H - 40)
    love.graphics.setColor(1.0, 0.55, 0.55, 0.5)
    if aiEnabled then
        love.graphics.printf("AI OPPONENT", W - 200, H - 40, 160, "right")
    else
        love.graphics.printf("↑/↓  ·  RShift dash", W - 240, H - 40, 200, "right")
    end
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.printf("TAB AI  ·  first to " .. WIN_SCORE, 0, H - 40, W, "center")

    if comboText.life > 0 then
        local a = math.min(1, comboText.life * 2)
        love.graphics.setFont(fonts.banner)
        love.graphics.setColor(1, 0.85, 0.3, a)
        love.graphics.printf(comboText.text, 0, comboText.y, W, "center")
    end

    for _, b in ipairs(banners) do
        local a = math.min(1, b.life * 2)
        love.graphics.setFont(fonts.banner)
        love.graphics.setColor(b.color[1], b.color[2], b.color[3], a)
        love.graphics.printf(b.text, 0, b.y, W, "center")
    end

    if waitingToServe and not gameOver then
        local pulse = 0.55 + 0.45 * math.sin(time * 4)
        love.graphics.setFont(fonts.title)
        love.graphics.setColor(1, 1, 1, 0.85 * pulse)
        love.graphics.printf("NEON PLASMA PONG", 0, H * 0.38, W, "center")
        love.graphics.setFont(fonts.ui)
        love.graphics.setColor(0.85, 0.95, 1.0, pulse)
        love.graphics.printf("PRESS  SPACE  TO  SERVE", 0, H * 0.48, W, "center")
    end

    if gameOver then
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle("fill", 0, 0, W, H)
        love.graphics.setFont(fonts.title)
        local col = winner == 1 and player1.color or player2.color
        love.graphics.setColor(col[1], col[2], col[3], 1)
        love.graphics.printf(winner == 1 and "CYAN WINS" or "CRIMSON WINS", 0, H * 0.38, W, "center")
        love.graphics.setFont(fonts.ui)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.printf("SPACE or R  ·  PLAY AGAIN", 0, H * 0.5, W, "center")
    end
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)

    shaders.plasma:send("time", time)
    shaders.plasma:send("resolution", { W, H })
    shaders.plasma:send("heat", heat)
    love.graphics.setShader(shaders.plasma)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setShader()

    for _, a in ipairs(ambient) do
        love.graphics.setColor(0.5, 0.85, 1.0, 0.08 + a.z * 0.2)
        love.graphics.circle("fill", a.x, a.y, a.s)
    end

    love.graphics.push()
    love.graphics.translate(shake.x, shake.y)
    drawCourt()
    drawPowerups()
    drawParticles()
    drawPaddle3D(player1)
    drawPaddle3D(player2)
    if not waitingToServe or combo > 0 then
        -- ball always visible
    end
    drawBall()
    drawUI()
    love.graphics.pop()

    if flash > 0 then
        love.graphics.setColor(1, 1, 1, flash * 0.35)
        love.graphics.rectangle("fill", 0, 0, W, H)
    end
    love.graphics.setCanvas()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 1, 1, 0.16 + heat * 0.1)
    love.graphics.draw(canvas, -2, 0, 0, 1.002, 1)
    love.graphics.draw(canvas, 2, 0, 0, 0.998, 1)
    love.graphics.draw(canvas, 0, -2, 0, 1, 1.002)
    love.graphics.draw(canvas, 0, 2, 0, 1, 0.998)
    love.graphics.setBlendMode("alpha")

    love.graphics.setColor(0, 0, 0, 0.08)
    for y = 0, H, 3 do
        love.graphics.rectangle("fill", 0, y, W, 1)
    end
end
