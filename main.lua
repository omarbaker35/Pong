-- Pong in LÖVE 11.5
-- Task 1: window + paddles

function love.load()
    love.window.setTitle("Pong")
    love.window.setMode(800, 600)

    local paddleWidth = 15
    local paddleHeight = 100
    local paddleSpeed = 400
    local margin = 30

    player1 = {
        x = margin,
        y = (love.graphics.getHeight() - paddleHeight) / 2,
        width = paddleWidth,
        height = paddleHeight,
        speed = paddleSpeed,
        color = {0.2, 0.75, 1.0}
    }

    player2 = {
        x = love.graphics.getWidth() - margin - paddleWidth,
        y = (love.graphics.getHeight() - paddleHeight) / 2,
        width = paddleWidth,
        height = paddleHeight,
        speed = paddleSpeed,
        color = {1.0, 0.45, 0.35}
    }
end

local function clampPaddle(paddle)
    if paddle.y < 0 then
        paddle.y = 0
    elseif paddle.y + paddle.height > love.graphics.getHeight() then
        paddle.y = love.graphics.getHeight() - paddle.height
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
end

function love.draw()
    love.graphics.clear(0.08, 0.08, 0.12)

    love.graphics.setColor(player1.color)
    love.graphics.rectangle("fill", player1.x, player1.y, player1.width, player1.height)

    love.graphics.setColor(player2.color)
    love.graphics.rectangle("fill", player2.x, player2.y, player2.width, player2.height)

    love.graphics.setColor(1, 1, 1)
end
