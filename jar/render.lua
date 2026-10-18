-- From chrischaps/Fishbowl @ b0624e4 (fx/render.lua)
-- Render helpers: shaders, canvases and the shared object-lighting pass.
-- Terrarium: no water, so the caustics are gone. Depth of field blurs two layers:
-- the far scape at the back of the jar, and the room the jar stands in.

local C = require("jar.config")
local Tank = require("jar.tank")

local Render = {}

local shaders = {}
local canvases = {}
local white, blob
local currentLight
local objectHaze = -1

local function loadShader(name)
    local ok, result = pcall(love.graphics.newShader, "shaders/" .. name .. ".glsl")
    if not ok then
        print("[Terrarium] shader error in " .. name .. ": " .. tostring(result))
        return nil
    end
    return result
end

-- A soft radial falloff used for glows, shadows and motes
local function makeBlob(size)
    local data = love.image.newImageData(size, size)
    local r = size / 2
    data:mapPixel(function(x, y)
        local dx, dy = (x + 0.5 - r) / r, (y + 0.5 - r) / r
        local d = math.sqrt(dx * dx + dy * dy)
        local a = math.max(0, 1 - d)
        a = a * a * (3 - 2 * a)
        return 1, 1, 1, a
    end)
    local img = love.graphics.newImage(data)
    img:setFilter("linear", "linear")
    return img
end

function Render.init()
    for _, name in ipairs({ "object", "blur", "haze", "composite" }) do
        shaders[name] = loadShader(name)
    end

    local w, h = C.W, C.H
    local hdr = { format = "rgba16f" }
    canvases.scene = love.graphics.newCanvas(w, h, hdr)
    -- Terrarium: one full-size layer and a half-size ping-pong pair per soft layer
    for _, name in ipairs({ "far", "room" }) do
        canvases[name] = love.graphics.newCanvas(w, h, hdr)
        canvases[name .. "A"] = love.graphics.newCanvas(w / 2, h / 2, hdr)
        canvases[name .. "B"] = love.graphics.newCanvas(w / 2, h / 2, hdr)
    end
    for _, c in pairs(canvases) do c:setFilter("linear", "linear") end

    local px = love.image.newImageData(1, 1)
    px:setPixel(0, 0, 1, 1, 1, 1)
    white = love.graphics.newImage(px)
    blob = makeBlob(64)
end

function Render.shader(name) return shaders[name] end
function Render.canvas(name) return canvases[name] end
function Render.white() return white end
function Render.blob() return blob end

--- Draw a full-rect quad with uv 0..1 (for shader passes)
function Render.quad(x, y, w, h)
    love.graphics.draw(white, x or 0, y or 0, 0, w or C.W, h or C.H)
end

--- Draw the soft blob centered at x, y with radii rx, ry
function Render.drawBlob(x, y, rx, ry, angle)
    love.graphics.draw(blob, x, y, angle or 0, rx / 32, (ry or rx) / 32, 32, 32)
end

--- Configure the object shader for this frame from the light
function Render.beginObjects(light)
    currentLight = light
    local sh = shaders.object
    if not sh then return end
    sh:send("ambient", light.ambient)
    sh:send("fog", light.fog)
    objectHaze = -1
end

--- Bind the object shader for something at depth d
function Render.useObject(d)
    local sh = shaders.object
    if not sh then
        love.graphics.setShader()
        return
    end
    love.graphics.setShader(sh)
    local h = Tank.haze(d) * currentLight.haze
    if math.abs(h - objectHaze) > 0.004 then
        sh:send("haze", h)
        objectHaze = h
    end
end

--- Blur a soft layer at half resolution (depth of field). Spread is in texels.
-- Terrarium: generalised from blurFar so the room can be blurred too.
function Render.blur(name, spread)
    local blur = shaders.blur
    local src, a, b = canvases[name], canvases[name .. "A"], canvases[name .. "B"]
    if not blur then return src, 1 end
    spread = spread or 1
    love.graphics.push("all")
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setCanvas(a)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setShader(blur)
    blur:send("dir", { 1.5 * spread / C.W, 0 })
    love.graphics.draw(src, 0, 0, 0, 0.5, 0.5)

    love.graphics.setCanvas(b)
    love.graphics.clear(0, 0, 0, 0)
    blur:send("dir", { 0, 1.8 * spread / C.H })
    love.graphics.draw(a)

    love.graphics.setCanvas(a)
    love.graphics.clear(0, 0, 0, 0)
    blur:send("dir", { 1.2 * spread / C.W, 0 })
    love.graphics.draw(b)

    love.graphics.pop()
    return a, 2
end

--- Draw a blurred layer back over the scene, hazed toward the fog
function Render.drawSoft(name, spread, haze, fog)
    local soft, scale = Render.blur(name, spread)
    love.graphics.push("all")
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    local hz = shaders.haze
    if hz then
        love.graphics.setShader(hz)
        hz:send("fog", fog or C.LIGHT.fog)
        hz:send("haze", haze or 0)
    end
    love.graphics.draw(soft, 0, 0, 0, scale, scale)
    love.graphics.pop()
end

return Render
