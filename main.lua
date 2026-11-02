-- Pong in LÖVE 11.5
-- Part 1: window + paddles
-- Part 2: ball, wall/paddle collisions, custom serve + speed-up

local WINDOW_WIDTH = 800
local WINDOW_HEIGHT = 600
local MAX_BALL_SPEED = 700

local function resetBall(serving)
    ball.x = (WINDOW_WIDTH - ball.size) / 2
    ball.y = (WINDOW_HEIGHT - ball.size) / 2
    ball.speed = ball.baseSpeed

    local direction = love.math.random(2) == 1 and -1 or 1
    local angle = love.math.random() * math.pi / 3 - math.pi / 6 -- about -30..30 deg
    ball.dx = math.cos(angle) * ball.speed * direction
    ball.dy = math.sin(angle) * ball.speed

    waitingToServe = serving ~= false
end

function love.load()
    love.window.setTitle("Pong")
    love.window.setMode(WINDOW_WIDTH, WINDOW_HEIGHT)
    love.math.setRandomSeed(os.time())

    local paddleWidth = 18
    local paddleHeight = 110
    local paddleSpeed = 480
    local margin = 30

    -- Different color per paddle (custom change)
    player1 = {
        x = margin,
        y = (WINDOW_HEIGHT - paddleHeight) / 2,
        width = paddleWidth,
        height = paddleHeight,
        speed = paddleSpeed,
        color = {0.2, 0.75, 1.0}
    }

    player2 = {
        x = WINDOW_WIDTH - margin - paddleWidth,
        y = (WINDOW_HEIGHT - paddleHeight) / 2,
        width = paddleWidth,
        height = paddleHeight,
        speed = paddleSpeed,
        color = {1.0, 0.45, 0.35}
    }

    ball = {
        size = 14,
        x = 0,
        y = 0,
        dx = 0,
        dy = 0,
        baseSpeed = 320,
        speed = 320,
        speedBoost = 1.05, -- custom: speed up slightly after each paddle hit
        color = {1, 1, 1}
    }

    scores = { player1 = 0, player2 = 0 }
    waitingToServe = true
    resetBall(true)
end

local function clampPaddle(paddle)
    if paddle.y < 0 then
        paddle.y = 0
    elseif paddle.y + paddle.height > WINDOW_HEIGHT then
        paddle.y = WINDOW_HEIGHT - paddle.height
    end
end

-- AABB: true if two axis-aligned rectangles overlap
function checkCollision(a, b)
    return a.x < b.x + b.width
        and b.x < a.x + a.width
        and a.y < b.y + b.height
        and b.y < a.y + a.height
end

local function verticalOverlap(ballY, ballSize, paddle)
    return ballY < paddle.y + paddle.height and paddle.y < ballY + ballSize
end

local function reflectFromPaddle(paddle, goingRight)
    -- Bounce direction depends on which paddle was hit, not previous dx
    ball.speed = math.min(ball.speed * ball.speedBoost, MAX_BALL_SPEED)

    local paddleCenter = paddle.y + paddle.height / 2
    local ballCenter = ball.y + ball.size / 2
    local offset = (ballCenter - paddleCenter) / (paddle.height / 2)
    offset = math.max(-1, math.min(1, offset))

    local angle = offset * (math.pi / 4) -- up to 45 degrees
    local dir = goingRight and 1 or -1
    ball.dx = math.cos(angle) * ball.speed * dir
    ball.dy = math.sin(angle) * ball.speed

    -- Unstick: place ball just outside the paddle face
    if goingRight then
        ball.x = paddle.x + paddle.width
    else
        ball.x = paddle.x - ball.size
    end
end

-- Detect overlap OR tunneling (ball jumped past the paddle face in one frame)
local function tryHitPaddle(paddle, prevX, isLeft)
    local faceX
    if isLeft then
        faceX = paddle.x + paddle.width
        -- Only when moving left toward this paddle
        if ball.dx >= 0 then
            return
        end
        local crossed = prevX >= faceX and ball.x < faceX
        local overlaps = checkCollision({
            x = ball.x, y = ball.y, width = ball.size, height = ball.size
        }, paddle)
        if (crossed or overlaps) and verticalOverlap(ball.y, ball.size, paddle) then
            reflectFromPaddle(paddle, true)
        end
    else
        faceX = paddle.x
        if ball.dx <= 0 then
            return
        end
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

function love.update(dt)
    -- Left paddle: W / S
    if love.keyboard.isDown("w") then
        player1.y = player1.y - player1.speed * dt
    elseif love.keyboard.isDown("s") then
        player1.y = player1.y + player1.speed * dt
    end

    -- Right paddle: Up / Down arrows
    if love.keyboard.isDown("up") then
        player2.y = player2.y - player2.speed * dt
    elseif love.keyboard.isDown("down") then
        player2.y = player2.y + player2.speed * dt
    end

    clampPaddle(player1)
    clampPaddle(player2)

    if waitingToServe then
        return
    end

    local prevX = ball.x

    -- Move ball using velocity * dt (frame-rate independent)
    ball.x = ball.x + ball.dx * dt
    ball.y = ball.y + ball.dy * dt

    -- Bounce off top / bottom walls
    if ball.y <= 0 then
        ball.y = 0
        ball.dy = math.abs(ball.dy)
    elseif ball.y + ball.size >= WINDOW_HEIGHT then
        ball.y = WINDOW_HEIGHT - ball.size
        ball.dy = -math.abs(ball.dy)
    end

    tryHitPaddle(player1, prevX, true)
    tryHitPaddle(player2, prevX, false)

    -- Score if ball leaves left/right side
    if ball.x + ball.size < 0 then
        scores.player2 = scores.player2 + 1
        resetBall(true)
    elseif ball.x > WINDOW_WIDTH then
        scores.player1 = scores.player1 + 1
        resetBall(true)
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "space" and waitingToServe then
        -- Custom: Space serves the ball
        waitingToServe = false
    end
end

function love.draw()
    love.graphics.clear(0.08, 0.08, 0.12)

    -- Center dashed line
    love.graphics.setColor(0.35, 0.35, 0.4)
    for y = 0, WINDOW_HEIGHT, 28 do
        love.graphics.rectangle("fill", WINDOW_WIDTH / 2 - 2, y, 4, 16)
    end

    love.graphics.setColor(player1.color)
    love.graphics.rectangle("fill", player1.x, player1.y, player1.width, player1.height)

    love.graphics.setColor(player2.color)
    love.graphics.rectangle("fill", player2.x, player2.y, player2.width, player2.height)

    love.graphics.setColor(ball.color)
    love.graphics.rectangle("fill", ball.x, ball.y, ball.size, ball.size)

    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(tostring(scores.player1), 0, 20, WINDOW_WIDTH / 2 - 20, "right")
    love.graphics.printf(tostring(scores.player2), WINDOW_WIDTH / 2 + 20, 20, WINDOW_WIDTH / 2 - 20, "left")

    if waitingToServe then
        love.graphics.printf("Press SPACE to serve", 0, WINDOW_HEIGHT / 2 - 40, WINDOW_WIDTH, "center")
    end
end
