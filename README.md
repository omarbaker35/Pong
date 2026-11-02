# Pong (Love2D)

**Name:** Omar Baker  
**Class / Section:** [Your Class / Section]

## Description

A classic two-player Pong game built with [LÖVE](https://love2d.org/) 11.5 and Lua. Each player controls a paddle, the ball bounces off walls and paddles using AABB collision, and the first player to score more points wins the rally. Movement uses delta time (`dt`) so speed stays consistent across machines.

## How to run

1. Install [LÖVE](https://love2d.org/) for macOS (or use the official `.app` in Applications).
2. Open a terminal in this project folder.
3. Run:

```bash
love .
```

## Controls

| Action | Player 1 (left) | Player 2 (right) |
| --- | --- | --- |
| Move up | `W` | `Up` arrow |
| Move down | `S` | `Down` arrow |
| Dash | `Left Shift` | `Right Shift` |
| Serve / rematch | `Space` | `Space` |
| Toggle AI | `Tab` | `Tab` |
| Restart match | `R` | `R` |
| Quit | `Escape` | `Escape` |

## Own changes

1. **Different paddle colors** — left cyan plasma / right coral plasma.
2. **Space to serve** — the ball waits in the center until you press Space.
3. **Ball speed-up** — after each paddle hit, the ball gets about 5% faster.
4. **Neon Plasma visuals** — fake-3D court, plasma shader, trails, particles, shake, bloom, SFX.
5. **Power-ups** — GROW, FREEZE, FIREBALL, SHIELD orbs spawn mid-court.
6. **Heat / combo system** — rallies raise heat and show combo banners.
7. **AI opponent** — toggle with Tab (on by default).
8. **Dash** — short burst dodge with cooldown.
9. **Slow-mo goals + first to 7** victory screen.

## Screenshot

![Game screenshot](screenshots/pong.png)

*(Add a screenshot of the running game to `screenshots/pong.png`.)*

## Demo video

[Watch the short demo](demo/pong-demo.mp4)

*(Add a short demo video to `demo/pong-demo.mp4`.)*
