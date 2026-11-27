-- CAMAR UNIVERSAL FPS (v11)
-- language: Luau | target: Roblox client via executor
-- v11: NPC/bot tracking via workspace scan (0.5s cache), safe GUI parent
--      via gethui/CoreGui, culling-tolerant target loop, aimbot covers bots.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")
local HttpService       = game:GetService("HttpService")
local TweenService      = game:GetService("TweenService")
local GuiService        = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

local getgenv           = getgenv or function() return _G end
local hookmetamethod    = hookmetamethod
local checkcaller       = checkcaller or function() return false end
local getnamecallmethod = getnamecallmethod
local writefile, readfile, isfile = writefile, readfile, isfile
local Drawing = Drawing

if getgenv().CAMAR_FPS_CLEANUP then pcall(getgenv().CAMAR_FPS_CLEANUP) end

-- ═════════════════════════════════════════════════════════════════════════════
-- CONFIG
-- ═════════════════════════════════════════════════════════════════════════════
local Config = {
    Aimbot   = { Enabled=false, Key="MouseButton2", Smooth=0.18, FOV=140, WallCheck=true, TeamCheck=true, ShowFOV=true },
    ESP      = { Enabled=false, Boxes=true, Names=true, Health=true, Distance=true, Chams=false, TeamColor=true, Wallhack=false },
    Combat   = { NoRecoil=false, NoSpread=false, RapidFire=false, RapidFireMult=2, Hooks=true },
    Movement = { Speed=16, Jump=50, Fly=false, FlySpeed=60, Noclip=false },
    Misc     = { Fullbright=false, RemoveEffects=false, AutoReload=false, AutoHeal=false },
}
local ESP_COLOR = Color3.fromRGB(255, 90, 20)
local CONFIG_PATH = "camar_fps_config.json"

local function sanitize(t)
    local o = {}
    for k, v in pairs(t) do
        if type(v) == "table" then o[k] = sanitize(v)
        elseif type(v) == "number" or type(v) == "string" or type(v) == "boolean" then o[k] = v end
    end
    return o
end
local function saveConfig()
    if not writefile then return end
    local ok, data = pcall(function() return HttpService:JSONEncode(sanitize(Config)) end)
    if ok and data then pcall(writefile, CONFIG_PATH, data) end
end
local function loadConfig()
    if not (readfile and isfile and isfile(CONFIG_PATH)) then return end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_PATH)) end)
    if not ok or type(data) ~= "table" then return end
    for s, vals in pairs(data) do
        if Config[s] and type(vals) == "table" then
            for k, v in pairs(vals) do
                if Config[s][k] ~= nil and type(v) == type(Config[s][k]) then
                    Config[s][k] = v
                end
            end
        end
    end
end
loadConfig()

-- ═════════════════════════════════════════════════════════════════════════════
-- TRACKING
-- ═════════════════════════════════════════════════════════════════════════════
local connections, drawingObjects = {}, {}
local function track(c) table.insert(connections, c); return c end
local function trackDraw(d) if d then table.insert(drawingObjects, d) end; return d end

-- ═════════════════════════════════════════════════════════════════════════════
-- DRAWING PROBES
-- ═════════════════════════════════════════════════════════════════════════════
local function probeDrawing(kind)
    if not Drawing then return false end
    local ok, d = pcall(function() return Drawing.new(kind) end)
    if ok and d then pcall(function() d:Remove() end); return true end
    return false
end

local HAS_TEXT   = probeDrawing("Text")
local HAS_SQUARE = probeDrawing("Square")
local HAS_QUAD   = probeDrawing("Quad")
local HAS_CIRCLE = probeDrawing("Circle")

local function tryDrawing(kind)
    if not Drawing then return nil end
    local ok, d = pcall(function() return Drawing.new(kind) end)
    if ok and d then return d end
    return nil
end

-- ═════════════════════════════════════════════════════════════════════════════
-- FOV CIRCLE
-- ═════════════════════════════════════════════════════════════════════════════
local fovCircle = HAS_CIRCLE and tryDrawing("Circle") or nil
if fovCircle then
    trackDraw(fovCircle)
    fovCircle.Position  = Vector2.new(0, 0)
    fovCircle.Radius    = 0
    fovCircle.Thickness = 1.5
    fovCircle.Filled    = false
    fovCircle.Color     = ESP_COLOR
    fovCircle.Visible   = false
end

-- ═════════════════════════════════════════════════════════════════════════════
-- TARGET COLLECTION (players + bots, 0.5s bot scan cache)
-- ═════════════════════════════════════════════════════════════════════════════
local cached_bots = {}
local last_bot_scan = 0

local function is_bot_model(model)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
    return model:FindFirstChild("HumanoidRootPart") ~= nil
end

local function get_cached_bots()
    if tick() - last_bot_scan > 0.5 then
        last_bot_scan = tick()
        local fresh = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and is_bot_model(obj) then
                fresh[#fresh+1] = obj
            end
        end
        cached_bots = fresh
    end
    local alive = {}
    for _, obj in ipairs(cached_bots) do
        if obj.Parent and obj:FindFirstChild("HumanoidRootPart") then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                alive[#alive+1] = obj
            end
        end
    end
    return alive
end

local function collect_targets()
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                list[#list+1] = { kind = "player", obj = plr, char = plr.Character, name = plr.Name }
            end
        end
    end
    for _, obj in ipairs(get_cached_bots()) do
        local ok, name = pcall(function() return obj.Name end)
        list[#list+1] = { kind = "bot", obj = obj, char = obj, name = ok and name or "NPC" }
    end
    return list
end

-- ═════════════════════════════════════════════════════════════════════════════
-- ESP
-- ═════════════════════════════════════════════════════════════════════════════
local espObjects = {}

local function makeText(size)
    if not HAS_TEXT then return nil end
    local t = tryDrawing("Text")
    if not t then return nil end
    trackDraw(t)
    t.Size     = size or 14
    t.Center   = true
    t.Outline  = true
    t.Color    = Color3.new(1, 1, 1)
    t.Visible  = false
    t.Position = Vector2.new(0, 0)
    return t
end

local function createESP(key)
    if espObjects[key] then return end

    local box = nil
    if HAS_SQUARE then box = tryDrawing("Square") end
    if not box and HAS_QUAD then box = tryDrawing("Quad") end
    if box then
        trackDraw(box)
        box.Thickness = 1
        box.Filled    = false
        box.Visible   = false
        box.Position  = Vector2.new(0, 0)
        box.Size      = Vector2.new(1, 1)
        box.Color     = ESP_COLOR
    end

    local hl = Instance.new("Highlight")
    hl.Enabled             = false
    hl.FillTransparency    = 0.65
    hl.OutlineTransparency = 0
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor           = ESP_COLOR
    hl.OutlineColor        = Color3.new(1, 1, 1)

    espObjects[key] = {
        box       = box,
        name      = makeText(14),
        health    = makeText(12),
        distance  = makeText(12),
        highlight = hl,
    }
end

local function removeESP(key)
    local o = espObjects[key]
    if not o then return end
    for _, d in ipairs({o.box, o.name, o.health, o.distance}) do
        if d then pcall(function() d:Remove() end) end
    end
    if o.highlight then pcall(function() o.highlight:Destroy() end) end
    espObjects[key] = nil
end

local function hideOne(o)
    if o.box      then o.box.Visible      = false end
    if o.name     then o.name.Visible     = false end
    if o.health   then o.health.Visible   = false end
    if o.distance then o.distance.Visible = false end
    if o.highlight then o.highlight.Enabled = false end
end

local function updateESPForTarget(target, cam)
    if not target.char or not target.char.Parent then
        local o = espObjects[target.obj]
        if o then hideOne(o) end
        return
    end
    if not espObjects[target.obj] then createESP(target.obj) end
    local o = espObjects[target.obj]
    if not o then return end

    local char = target.char
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    local head = char:FindFirstChild("Head")
    local hum  = char:FindFirstChildOfClass("Humanoid")

    if not (hrp and head and hum) or hum.Health <= 0 then
        hideOne(o)
        return
    end

    local baseColor = ESP_COLOR
    if Config.ESP.TeamColor and target.kind == "player" then
        local team = target.obj.Team
        if team and team.TeamColor then
            baseColor = team.TeamColor.Color
        end
    end

    if o.highlight then
        if Config.ESP.Chams then
            if o.highlight.Parent ~= char then
                o.highlight.Parent = char
            end
            o.highlight.FillColor    = baseColor
            o.highlight.OutlineColor = Color3.new(1, 1, 1)
            o.highlight.Enabled      = true
        else
            o.highlight.Enabled = false
        end
    end

    local top    = head.Position + Vector3.new(0, 0.5, 0)
    local bottom = hrp.Position  - Vector3.new(0, 2.6, 0)
    local topPos = cam:WorldToViewportPoint(top)
    local botPos = cam:WorldToViewportPoint(bottom)

    if topPos.Z <= 0 or botPos.Z <= 0 then
        hideOne(o)
        return
    end

    local height = math.abs(topPos.Y - botPos.Y)
    local width  = height * 0.55
    if height < 2 then height = 2; width = 1 end

    if o.box then
        o.box.Size     = Vector2.new(width, height)
        o.box.Position = Vector2.new(topPos.X - width / 2, topPos.Y)
        o.box.Color    = baseColor
        o.box.Visible  = Config.ESP.Boxes == true
    end
    if o.name then
        o.name.Text     = target.name
        o.name.Position = Vector2.new(topPos.X, topPos.Y - 18)
        o.name.Color    = baseColor
        o.name.Visible  = Config.ESP.Names == true
    end
    if o.health then
        o.health.Text     = string.format("HP %d", math.floor(hum.Health))
        o.health.Position = Vector2.new(topPos.X, topPos.Y + height + 2)
        o.health.Color    = Color3.fromRGB(60, 220, 60)
        o.health.Visible  = Config.ESP.Health == true
    end
    if o.distance then
        o.distance.Text     = string.format("[%d]", math.floor((cam.CFrame.Position - hrp.Position).Magnitude))
        o.distance.Position = Vector2.new(topPos.X, topPos.Y + height + 16)
        o.distance.Visible  = Config.ESP.Distance == true
    end
end

local function updateESP()
    local cam = workspace.CurrentCamera
    if not cam then return end

    if not Config.ESP.Enabled then
        for _, o in pairs(espObjects) do hideOne(o) end
        return
    end

    local targets = collect_targets()
    local seen = {}
    for _, t in ipairs(targets) do
        seen[t.obj] = true
        local ok = pcall(updateESPForTarget, t, cam)
        if not ok then
            local o = espObjects[t.obj]
            if o then hideOne(o) end
        end
    end

    for obj in pairs(espObjects) do
        if not seen[obj] then removeESP(obj) end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- WALLHACK
-- ═════════════════════════════════════════════════════════════════════════════
local wallhackParts = {}
local lastWallhackScan = 0
local wallhackWasOn = false

local function clearWallhack()
    for part in pairs(wallhackParts) do
        if part and part.Parent then
            pcall(function() part.LocalTransparencyModifier = 0 end)
        end
    end
    wallhackParts = {}
end

local function rebuildWallhack()
    for part in pairs(wallhackParts) do
        if not part or not part.Parent then wallhackParts[part] = nil end
    end

    local skip = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char then
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("BasePart") then skip[d] = true end
            end
        end
    end

    local function underHumanoid(part)
        local cur = part.Parent
        for _ = 1, 12 do
            if not cur or cur == workspace then break end
            if cur:IsA("Model") and cur:FindFirstChildOfClass("Humanoid") then return true end
            if cur:IsA("Accessory") or cur:IsA("Tool") then return true end
            cur = cur.Parent
        end
        return false
    end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Transparency < 1
           and not skip[obj]
           and not underHumanoid(obj)
           and not wallhackParts[obj] then
            wallhackParts[obj] = true
            pcall(function() obj.LocalTransparencyModifier = 0.55 end)
        end
    end
end

local function updateWallhack()
    local on = Config.ESP.Wallhack
    if on ~= wallhackWasOn then
        wallhackWasOn = on
        if on then rebuildWallhack(); lastWallhackScan = tick()
        else clearWallhack() end
        return
    end
    if not on then return end
    if tick() - lastWallhackScan < 10 then return end
    lastWallhackScan = tick()
    rebuildWallhack()
end

-- ═════════════════════════════════════════════════════════════════════════════
-- AIMBOT (covers players and bots)
-- ═════════════════════════════════════════════════════════════════════════════
local function keyHeld()
    local k = Config.Aimbot.Key
    if k == "MouseButton1" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
    if k == "MouseButton2" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
    if k == "Always" then return true end
    local kc = Enum.KeyCode[k]
    if not kc then return false end
    return UserInputService:IsKeyDown(kc)
end

local function hasLOS(targetChar, targetPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local filter = {targetChar}
    if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
    params.FilterDescendantsInstances = filter
    local cam = workspace.CurrentCamera
    return workspace:Raycast(cam.CFrame.Position, targetPos - cam.CFrame.Position, params) == nil
end

local function getAimTarget()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local best, bestScore = nil, math.huge
    for _, t in ipairs(collect_targets()) do
        if t.kind == "player" and Config.Aimbot.TeamCheck
           and t.obj.Team and LocalPlayer.Team and t.obj.Team == LocalPlayer.Team then
            continue
        end
        if not t.char or not t.char.Parent then continue end
        local head = t.char:FindFirstChild("Head")
        local hum  = t.char:FindFirstChildOfClass("Humanoid")
        if not (head and hum and hum.Health > 0) then continue end
        local pos, onScreen = cam:WorldToViewportPoint(head.Position)
        if not onScreen or pos.Z < 0 then continue end
        local screenPos = Vector2.new(pos.X, pos.Y)
        local dist = (screenPos - center).Magnitude
        if dist > Config.Aimbot.FOV then continue end
        if Config.Aimbot.WallCheck and not hasLOS(t.char, head.Position) then continue end
        if dist < bestScore then
            best, bestScore = { pos = head.Position, char = t.char }, dist
        end
    end
    return best
end

-- ═════════════════════════════════════════════════════════════════════════════
-- MOVEMENT
-- ═════════════════════════════════════════════════════════════════════════════
local flyBV
local function applyMovement()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if hum.WalkSpeed ~= Config.Movement.Speed then hum.WalkSpeed = Config.Movement.Speed end
    if hum.UseJumpPower ~= true then hum.UseJumpPower = true end
    if hum.JumpPower ~= Config.Movement.Jump then hum.JumpPower = Config.Movement.Jump end
end
local function updateFly()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        if flyBV then flyBV:Destroy(); flyBV = nil end
        return
    end
    if Config.Movement.Fly then
        if not flyBV then
            flyBV = Instance.new("BodyVelocity")
            flyBV.MaxForce = Vector3.new(1e6, 1e6, 1e6)
            flyBV.Parent = hrp
        end
        local cam = workspace.CurrentCamera
        local move = Vector3.new()
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0) end
        if move.Magnitude > 0 then move = move.Unit * Config.Movement.FlySpeed end
        flyBV.Velocity = move
    elseif flyBV then
        flyBV:Destroy(); flyBV = nil
    end
end
local noclipState = {}
local function applyNoclip()
    local char = LocalPlayer.Character
    if Config.Movement.Noclip then
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                if noclipState[p] == nil then
                    noclipState[p] = p.CanCollide
                end
                pcall(function() p.CanCollide = false end)
            end
        end
    else
        if next(noclipState) then
            for p, orig in pairs(noclipState) do
                if p and p.Parent then
                    pcall(function() p.CanCollide = orig end)
                end
            end
            noclipState = {}
        end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- MISC UTILITIES
-- ═════════════════════════════════════════════════════════════════════════════
local lightingBackup = {
    Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
}
local function applyFullbright()
    if Config.Misc.Fullbright then
        Lighting.Brightness = 3
        Lighting.ClockTime = 12
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.FogEnd = 1e6
    else
        for k, v in pairs(lightingBackup) do pcall(function() Lighting[k] = v end) end
    end
end
local lastFullbrightState = nil
local function updateFullbright()
    if Config.Misc.Fullbright ~= lastFullbrightState then
        lastFullbrightState = Config.Misc.Fullbright
        applyFullbright()
    end
end

local removedEffects = {}
local function updateEffects()
    if Config.Misc.RemoveEffects then
        for _, obj in ipairs(Lighting:GetChildren()) do
            if (obj:IsA("PostEffect") or obj:IsA("Atmosphere")) and obj.Enabled then
                removedEffects[obj] = true
                pcall(function() obj.Enabled = false end)
            end
        end
    else
        if next(removedEffects) then
            for obj in pairs(removedEffects) do
                if obj and obj.Parent then
                    pcall(function() obj.Enabled = true end)
                end
            end
            removedEffects = {}
        end
    end
end

local function autoReload()
    if not Config.Misc.AutoReload then return end
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return end
    for _, v in ipairs(tool:GetDescendants()) do
        if v:IsA("RemoteEvent") and v.Name:lower():find("reload") then
            pcall(function() v:FireServer() end)
        end
    end
end
local function autoHeal()
    if not Config.Misc.AutoHeal then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hum and hum.Health < hum.MaxHealth) then return end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return end
    for _, tool in ipairs(bp:GetChildren()) do
        if tool:IsA("Tool") and (tool.Name:lower():find("heal") or tool.Name:lower():find("med")) then
            tool.Parent = char
            task.wait(0.1)
            pcall(function() tool:Activate() end)
            return
        end
    end
end
local function teleportTo(name)
    local target = Players:FindFirstChild(name)
    if not (target and target.Character) then return end
    local thrp = target.Character:FindFirstChild("HumanoidRootPart")
    local myhrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if thrp and myhrp then myhrp.CFrame = thrp.CFrame * CFrame.new(0, 3, 0) end
end
local function spectate(name)
    local target = Players:FindFirstChild(name)
    if target and target.Character then
        local hum = target.Character:FindFirstChildOfClass("Humanoid")
        if hum then workspace.CurrentCamera.CameraSubject = hum end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- HOOKS
-- ═════════════════════════════════════════════════════════════════════════════
local RECOIL = { Recoil=true, CameraRecoil=true, RecoilCamera=true, Kickback=true }
local SPREAD = { Spread=true, BulletSpread=true, Dispersion=true }

local oldIndex, oldNamecall

if hookmetamethod and getnamecallmethod then
    local okIdx, resIdx = pcall(function()
        return hookmetamethod(game, "__index", function(self, key)
            if not checkcaller() and Config.Combat.Hooks then
                if type(key) == "string" and (RECOIL[key] or SPREAD[key]) then
                    local wantR = RECOIL[key] and Config.Combat.NoRecoil
                    local wantS = SPREAD[key] and Config.Combat.NoSpread
                    if wantR or wantS then
                        local okN, nm = pcall(oldIndex, self, "Name")
                        if okN and type(nm) == "string" then
                            local l = nm:lower()
                            if l:find("weapon") or l:find("gun") or l:find("recoil") or l:find("spread") then
                                return 0
                            end
                        end
                    end
                end
            end
            return oldIndex(self, key)
        end)
    end)
    if okIdx then oldIndex = resIdx end

    local okNc, resNc = pcall(function()
        return hookmetamethod(game, "__namecall", function(self, ...)
            if not checkcaller() and Config.Combat.Hooks then
                local method = getnamecallmethod()
                if method == "Kick" and self == LocalPlayer then return nil end
                if method == "FireServer" and Config.Combat.RapidFire then
                    local okC, cls = pcall(function() return self.ClassName end)
                    if okC and cls == "RemoteEvent" then
                        local okN, nm = pcall(function() return self.Name end)
                        if okN and type(nm) == "string" then
                            local l = nm:lower()
                            if l:find("fire") or l:find("shoot") or l:find("attack") or l:find("weapon") then
                                local last
                                for _ = 1, Config.Combat.RapidFireMult do
                                    last = oldNamecall(self, ...)
                                end
                                return last
                            end
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
    end)
    if okNc then oldNamecall = resNc end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- UI HELPERS
-- ═════════════════════════════════════════════════════════════════════════════
local function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = parent
    return c
end
local function stroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(60, 60, 70)
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end
local function gradient(parent, c1, c2, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(1, c2),
    })
    g.Rotation = rot or 90
    g.Parent = parent
    return g
end

-- ═════════════════════════════════════════════════════════════════════════════
-- INTRO ANIMATION
-- ═════════════════════════════════════════════════════════════════════════════
local function playIntro(screenGui)
    local layer = Instance.new("Frame")
    layer.Size = UDim2.new(1, 0, 1, 0)
    layer.BackgroundTransparency = 1
    layer.BorderSizePixel = 0
    layer.ZIndex = 200
    layer.Parent = screenGui

    local shrimp = Instance.new("TextLabel")
    shrimp.Size = UDim2.new(0, 40, 0, 40)
    shrimp.Position = UDim2.new(0.5, -20, 0.5, -90)
    shrimp.BackgroundTransparency = 1
    shrimp.Text = "🦐"
    shrimp.TextSize = 40
    shrimp.Font = Enum.Font.SourceSansBold
    shrimp.TextColor3 = ESP_COLOR
    shrimp.TextTransparency = 1
    shrimp.ZIndex = 201
    shrimp.Parent = layer

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0, 400, 0, 60)
    title.Position = UDim2.new(0.5, -200, 0.5, -10)
    title.BackgroundTransparency = 1
    title.Text = "CAMAR"
    title.TextSize = 44
    title.Font = Enum.Font.GothamBlack
    title.TextColor3 = ESP_COLOR
    title.TextTransparency = 1
    title.ZIndex = 201
    title.Parent = layer

    local sub = Instance.new("TextLabel")
    sub.Size = UDim2.new(0, 400, 0, 20)
    sub.Position = UDim2.new(0.5, -200, 0.5, 48)
    sub.BackgroundTransparency = 1
    sub.Text = "operating"
    sub.TextSize = 13
    sub.Font = Enum.Font.Gotham
    sub.TextColor3 = Color3.fromRGB(180, 180, 190)
    sub.TextTransparency = 1
    sub.ZIndex = 201
    sub.Parent = layer

    TweenService:Create(shrimp, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, -45, 0.5, -115),
        Size = UDim2.new(0, 90, 0, 90),
        TextSize = 90,
        TextTransparency = 0,
    }):Play()
    task.wait(0.30)
    TweenService:Create(title, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()
    task.wait(0.25)
    TweenService:Create(sub, TweenInfo.new(0.35), {TextTransparency = 0}):Play()
    task.wait(1.0)

    local out = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    TweenService:Create(shrimp, out, {TextTransparency = 1, Position = UDim2.new(0.5, -45, 0.5, -160)}):Play()
    TweenService:Create(title, out, {TextTransparency = 1}):Play()
    TweenService:Create(sub, out, {TextTransparency = 1}):Play()
    task.wait(0.5)
    layer:Destroy()
end

-- ═════════════════════════════════════════════════════════════════════════════
-- GUI
-- ═════════════════════════════════════════════════════════════════════════════
local uiRefreshFns = {}
local function buildGUI()
    -- destrói instâncias antigas em qualquer container conhecido
    for _, container in ipairs({
        (gethui and select(2, pcall(gethui))) or nil,
        (select(2, pcall(function() return game:GetService("CoreGui") end))) or nil,
        LocalPlayer:FindFirstChild("PlayerGui"),
    }) do
        if container then
            local old = container:FindFirstChild("CamarFPS")
            if old then old:Destroy() end
        end
    end

    local sg = Instance.new("ScreenGui")
    sg.Name = "CamarFPS"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.IgnoreGuiInset = false
    sg.DisplayOrder = 10

    local parent_gui
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then parent_gui = hui end
    end
    if not parent_gui then
        local ok, cg = pcall(function() return game:GetService("CoreGui") end)
        if ok and cg then parent_gui = cg end
    end
    if not parent_gui then
        parent_gui = LocalPlayer:WaitForChild("PlayerGui")
    end
    sg.Parent = parent_gui

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 540, 0, 460)
    main.Position = UDim2.new(0, 40, 0, 40)
    main.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = sg
    corner(main, 8)
    stroke(main, Color3.fromRGB(45, 45, 55), 1)

    local mainGrad = gradient(main, Color3.fromRGB(24, 24, 30), Color3.fromRGB(16, 16, 22), 90)

    local title = Instance.new("Frame")
    title.Size = UDim2.new(1, 0, 0, 34)
    title.BackgroundColor3 = ESP_COLOR
    title.BorderSizePixel = 0
    title.Active = true
    title.Parent = main
    corner(title, 8)
    local titleGrad = gradient(title, Color3.fromRGB(255, 110, 40), Color3.fromRGB(210, 70, 10), 90)

    local titleMask = Instance.new("Frame")
    titleMask.Size = UDim2.new(1, 0, 0, 4)
    titleMask.Position = UDim2.new(0, 0, 1, -4)
    titleMask.BackgroundColor3 = Color3.fromRGB(210, 70, 10)
    titleMask.BorderSizePixel = 0
    titleMask.Parent = title
    titleMask.ZIndex = 0

    local tText = Instance.new("TextLabel")
    tText.Size = UDim2.new(1, -110, 1, 0)
    tText.Position = UDim2.new(0, 14, 0, 0)
    tText.BackgroundTransparency = 1
    tText.Text = "🦐  CAMAR"
    tText.TextColor3 = Color3.new(1, 1, 1)
    tText.TextXAlignment = Enum.TextXAlignment.Left
    tText.Font = Enum.Font.GothamBlack
    tText.TextSize = 15
    tText.Parent = title

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 24, 0, 24)
    minBtn.Position = UDim2.new(1, -62, 0, 5)
    minBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
    minBtn.Text = "–"
    minBtn.TextColor3 = Color3.new(1, 1, 1)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 16
    minBtn.BorderSizePixel = 0
    minBtn.AutoButtonColor = false
    minBtn.Parent = title
    corner(minBtn, 5)
    stroke(minBtn, Color3.fromRGB(120, 120, 130), 1)

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 24, 0, 24)
    close.Position = UDim2.new(1, -34, 0, 5)
    close.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    close.Text = "×"
    close.TextColor3 = Color3.new(1, 1, 1)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 16
    close.BorderSizePixel = 0
    close.AutoButtonColor = false
    close.Parent = title
    corner(close, 5)
    stroke(close, Color3.fromRGB(240, 80, 80), 1)

    local ball = Instance.new("TextButton")
    ball.Name = "CamarBall"
    ball.Size = UDim2.new(0, 56, 0, 56)
    ball.Position = UDim2.new(0, 40, 0, 40)
    ball.BackgroundColor3 = ESP_COLOR
    ball.Text = "🦐"
    ball.TextSize = 30
    ball.Font = Enum.Font.SourceSansBold
    ball.TextColor3 = Color3.new(1, 1, 1)
    ball.BorderSizePixel = 0
    ball.AutoButtonColor = false
    ball.Visible = false
    ball.ZIndex = 10
    ball.Active = true
    ball.Parent = sg
    corner(ball, 500)
    local ballStroke = stroke(ball, Color3.fromRGB(20, 20, 25), 2)
    gradient(ball, Color3.fromRGB(255, 120, 50), Color3.fromRGB(200, 60, 5), 135)

    local tabs = Instance.new("Frame")
    tabs.Size = UDim2.new(0, 118, 1, -34)
    tabs.Position = UDim2.new(0, 0, 0, 34)
    tabs.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    tabs.BorderSizePixel = 0
    tabs.Parent = main
    local tabsLayout = Instance.new("UIListLayout")
    tabsLayout.Padding = UDim.new(0, 4)
    tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabsLayout.Parent = tabs
    local tp = Instance.new("UIPadding")
    tp.PaddingTop = UDim.new(0, 10)
    tp.PaddingLeft = UDim.new(0, 8)
    tp.PaddingRight = UDim.new(0, 8)
    tp.Parent = tabs

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -118, 1, -34)
    content.Position = UDim2.new(0, 118, 0, 34)
    content.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
    content.BorderSizePixel = 0
    content.Parent = main

    local pages = {}
    local tabButtons = {}
    local function selectTab(n)
        for k, p in pairs(pages) do p.Visible = (k == n) end
        for k, b in pairs(tabButtons) do
            if k == n then
                TweenService:Create(b, TweenInfo.new(0.15), {BackgroundColor3 = ESP_COLOR}):Play()
            else
                TweenService:Create(b, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(36, 36, 44)}):Play()
            end
        end
    end

    local function newTab(name, order)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 32)
        btn.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
        btn.Text = name
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 12
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = false
        btn.LayoutOrder = order or 0
        btn.Parent = tabs
        corner(btn, 5)

        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.new(1, -20, 1, -20)
        page.Position = UDim2.new(0, 10, 0, 10)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 4
        page.ScrollBarImageColor3 = ESP_COLOR
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.ScrollingDirection = Enum.ScrollingDirection.Y
        page.Parent = content
        local ll = Instance.new("UIListLayout")
        ll.Padding = UDim.new(0, 6)
        ll.SortOrder = Enum.SortOrder.LayoutOrder
        ll.Parent = page

        pages[name] = page
        tabButtons[name] = btn
        btn.MouseButton1Click:Connect(function() selectTab(name) end)
        return page
    end

    local function makeToggle(parent, label, tbl, key, order)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -10, 0, 30)
        row.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
        row.BorderSizePixel = 0
        row.LayoutOrder = order or 0
        row.Parent = parent
        corner(row, 5)
        stroke(row, Color3.fromRGB(48, 48, 58), 1)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -64, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = Color3.fromRGB(215, 215, 222)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.Parent = row

        local sw = Instance.new("TextButton")
        sw.Size = UDim2.new(0, 38, 0, 18)
        sw.Position = UDim2.new(1, -48, 0.5, -9)
        sw.BackgroundColor3 = tbl[key] and ESP_COLOR or Color3.fromRGB(55, 55, 65)
        sw.Text = ""
        sw.BorderSizePixel = 0
        sw.AutoButtonColor = false
        sw.Parent = row
        corner(sw, 500)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.Position = tbl[key] and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel = 0
        knob.Parent = sw
        corner(knob, 500)

        local function refresh()
            local on = tbl[key]
            sw.BackgroundColor3 = on and ESP_COLOR or Color3.fromRGB(55, 55, 65)
            TweenService:Create(knob, TweenInfo.new(0.15), {
                Position = on and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
            }):Play()
        end
        uiRefreshFns[#uiRefreshFns+1] = refresh

        sw.MouseButton1Click:Connect(function()
            tbl[key] = not tbl[key]
            refresh()
            saveConfig()
        end)
    end

    local function makeSlider(parent, label, tbl, key, mn, mx, isInt, order)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -10, 0, 44)
        row.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
        row.BorderSizePixel = 0
        row.LayoutOrder = order or 0
        row.Parent = parent
        corner(row, 5)
        stroke(row, Color3.fromRGB(48, 48, 58), 1)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -20, 0, 16)
        lbl.Position = UDim2.new(0, 12, 0, 3)
        lbl.BackgroundTransparency = 1
        lbl.Text = label .. "  (" .. tostring(tbl[key]) .. ")"
        lbl.TextColor3 = Color3.fromRGB(215, 215, 222)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.Parent = row

        local bar = Instance.new("TextButton")
        bar.Size = UDim2.new(1, -24, 0, 8)
        bar.Position = UDim2.new(0, 12, 1, -16)
        bar.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
        bar.Text = ""
        bar.AutoButtonColor = false
        bar.BorderSizePixel = 0
        bar.Parent = row
        corner(bar, 500)

        local fill = Instance.new("Frame")
        local startRel = math.clamp((tbl[key] - mn) / (mx - mn), 0, 1)
        fill.Size = UDim2.new(startRel, 0, 1, 0)
        fill.BackgroundColor3 = ESP_COLOR
        fill.BorderSizePixel = 0
        fill.Parent = bar
        corner(fill, 500)

        local sliderDrag = false
        local function setFromMouse()
            local mxPos = UserInputService:GetMouseLocation().X
            local rel = math.clamp((mxPos - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
            local val = mn + (mx - mn) * rel
            if isInt then val = math.floor(val + 0.5) end
            tbl[key] = val
            fill.Size = UDim2.new(rel, 0, 1, 0)
            lbl.Text = label .. "  (" .. tostring(val) .. ")"
        end
        local function refresh()
            local rel = math.clamp((tbl[key] - mn) / (mx - mn), 0, 1)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            lbl.Text = label .. "  (" .. tostring(tbl[key]) .. ")"
        end
        uiRefreshFns[#uiRefreshFns+1] = refresh

        bar.MouseButton1Down:Connect(function()
            sliderDrag = true
            setFromMouse()
        end)
        track(UserInputService.InputChanged:Connect(function(input)
            if sliderDrag and input.UserInputType == Enum.UserInputType.MouseMovement then
                setFromMouse()
            end
        end))
        track(UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                if sliderDrag then saveConfig() end
                sliderDrag = false
            end
        end))
    end

    local aim = newTab("Aimbot", 1)
    makeToggle(aim, "Enabled",    Config.Aimbot, "Enabled",   1)
    makeToggle(aim, "Wall Check", Config.Aimbot, "WallCheck", 2)
    makeToggle(aim, "Team Check", Config.Aimbot, "TeamCheck", 3)
    makeToggle(aim, "Show FOV",   Config.Aimbot, "ShowFOV",   4)
    makeSlider(aim, "Smooth",     Config.Aimbot, "Smooth", 0.05, 1, false, 5)
    makeSlider(aim, "FOV",        Config.Aimbot, "FOV",    20, 400, true, 6)

    local esp = newTab("ESP", 2)
    makeToggle(esp, "Enabled",    Config.ESP, "Enabled",   1)
    makeToggle(esp, "Boxes",      Config.ESP, "Boxes",     2)
    makeToggle(esp, "Names",      Config.ESP, "Names",     3)
    makeToggle(esp, "Health",     Config.ESP, "Health",    4)
    makeToggle(esp, "Distance",   Config.ESP, "Distance",  5)
    makeToggle(esp, "Chams",      Config.ESP, "Chams",     6)
    makeToggle(esp, "Team Color", Config.ESP, "TeamColor", 7)
    makeToggle(esp, "Wallhack",   Config.ESP, "Wallhack",  8)

    local combat = newTab("Combat", 3)
    makeToggle(combat, "Hooks On",   Config.Combat, "Hooks",         1)
    makeToggle(combat, "No Recoil",  Config.Combat, "NoRecoil",      2)
    makeToggle(combat, "No Spread",  Config.Combat, "NoSpread",      3)
    makeToggle(combat, "Rapid Fire", Config.Combat, "RapidFire",     4)
    makeSlider(combat, "Rapid Mult", Config.Combat, "RapidFireMult", 1, 10, true, 5)

    local mv = newTab("Movement", 4)
    makeSlider(mv, "Speed",     Config.Movement, "Speed", 8, 200, true, 1)
    makeSlider(mv, "Jump",      Config.Movement, "Jump",  50, 300, true, 2)
    makeToggle(mv, "Fly",       Config.Movement, "Fly",       3)
    makeSlider(mv, "Fly Speed", Config.Movement, "FlySpeed", 10, 300, true, 4)
    makeToggle(mv, "Noclip",    Config.Movement, "Noclip",    5)

    local misc = newTab("Misc", 5)
    makeToggle(misc, "Fullbright",     Config.Misc, "Fullbright",     1)
    makeToggle(misc, "Remove Effects", Config.Misc, "RemoveEffects",  2)
    makeToggle(misc, "Auto Reload",    Config.Misc, "AutoReload",     3)
    makeToggle(misc, "Auto Heal",      Config.Misc, "AutoHeal",       4)

    local tpBox = Instance.new("TextBox")
    tpBox.Size = UDim2.new(1, -10, 0, 30)
    tpBox.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
    tpBox.PlaceholderText = "player name → teleport"
    tpBox.Text = ""
    tpBox.TextColor3 = Color3.new(1, 1, 1)
    tpBox.PlaceholderColor3 = Color3.fromRGB(140, 140, 150)
    tpBox.Font = Enum.Font.Gotham
    tpBox.TextSize = 12
    tpBox.BorderSizePixel = 0
    tpBox.LayoutOrder = 5
    tpBox.Parent = misc
    corner(tpBox, 5)
    stroke(tpBox, Color3.fromRGB(48, 48, 58), 1)
    tpBox.FocusLost:Connect(function()
        if tpBox.Text ~= "" then teleportTo(tpBox.Text) end
    end)

    local specBox = tpBox:Clone()
    specBox.PlaceholderText = "player name → spectate"
    specBox.LayoutOrder = 6
    specBox.Parent = misc
    specBox.FocusLost:Connect(function()
        if specBox.Text ~= "" then spectate(specBox.Text) end
    end)

    local function smallBtn(parent, text, color, order, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -10, 0, 30)
        b.BackgroundColor3 = color or Color3.fromRGB(55, 55, 65)
        b.Text = text
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 12
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.LayoutOrder = order or 0
        b.Parent = parent
        corner(b, 5)
        stroke(b, Color3.fromRGB(70, 70, 82), 1)
        b.MouseEnter:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = color == ESP_COLOR and Color3.fromRGB(255, 130, 60) or Color3.fromRGB(70, 70, 82)}):Play()
        end)
        b.MouseLeave:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = color or Color3.fromRGB(55, 55, 65)}):Play()
        end)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    smallBtn(misc, "Save Config", ESP_COLOR, 7, saveConfig)
    smallBtn(misc, "Load Config", nil, 8, function()
        loadConfig()
        updateFullbright()
        updateEffects()
        for _, fn in ipairs(uiRefreshFns) do pcall(fn) end
    end)
    smallBtn(misc, "Reset Position", nil, 9, function()
        main.Position = UDim2.new(0, 40, 0, 40)
        ball.Position = UDim2.new(0, 40, 0, 40)
    end)

    selectTab("Aimbot")

    local function showBall()
        ball.Position = main.Position
        ball.Visible = true
        main.Visible = false
    end

    local function restoreFromBall()
        main.Position = ball.Position
        main.Visible = true
        ball.Visible = false
    end

    minBtn.MouseButton1Click:Connect(showBall)
    close.MouseButton1Click:Connect(function() main.Visible = false end)

    local drag = { mode = nil, startX = 0, startY = 0, startPos = nil, moved = false, threshold = 5 }

    local function mouseXY()
        local p = UserInputService:GetMouseLocation()
        local inset = GuiService:GetGuiInset()
        return p.X - inset.X, p.Y - inset.Y
    end

    local function over(frame, x, y)
        if not frame or not frame.Visible then return false end
        local ap, sz = frame.AbsolutePosition, frame.AbsoluteSize
        return x >= ap.X and x <= ap.X + sz.X and y >= ap.Y and y <= ap.Y + sz.Y
    end

    track(UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
           and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local mx, my = mouseXY()
        if ball.Visible and over(ball, mx, my) then
            drag.mode = "ball"
            drag.startX, drag.startY = mx, my
            drag.startPos = ball.Position
            drag.moved = false
        elseif title.Visible and over(title, mx, my)
               and not over(minBtn, mx, my)
               and not over(close, mx, my) then
            drag.mode = "title"
            drag.startX, drag.startY = mx, my
            drag.startPos = main.Position
            drag.moved = false
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
           and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not drag.mode then return end
        local mx, my = mouseXY()
        local dx, dy = mx - drag.startX, my - drag.startY
        if not drag.moved then
            if math.abs(dx) > drag.threshold or math.abs(dy) > drag.threshold then
                drag.moved = true
            end
        end
        if drag.mode == "title" then
            main.Position = UDim2.new(0, drag.startPos.X.Offset + dx, 0, drag.startPos.Y.Offset + dy)
        elseif drag.mode == "ball" and drag.moved then
            ball.Position = UDim2.new(0, drag.startPos.X.Offset + dx, 0, drag.startPos.Y.Offset + dy)
        end
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
           and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if drag.mode == "ball" and not drag.moved then
            restoreFromBall()
        end
        drag.mode = nil
        drag.moved = false
    end))

    local lastVisible = "main"
    track(UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            if main.Visible then
                lastVisible = "main"
                main.Visible = false
            elseif ball.Visible then
                lastVisible = "ball"
                ball.Visible = false
            else
                if lastVisible == "ball" then
                    ball.Visible = true
                else
                    main.Visible = true
                end
            end
        end
    end))

    task.spawn(function() pcall(playIntro, sg) end)

    return sg
end

local okGui, guiErr = pcall(buildGUI)
if not okGui then
    warn("[Camar] GUI failed:", guiErr)
    print("[Camar] GUI failed:", tostring(guiErr))
end

-- ═════════════════════════════════════════════════════════════════════════════
-- LOOPS
-- ═════════════════════════════════════════════════════════════════════════════
local lastMisc = 0

track(RunService.RenderStepped:Connect(function()
    local cam = workspace.CurrentCamera
    if not cam then return end

    if Config.Aimbot.Enabled and keyHeld() then
        local target = getAimTarget()
        if target then
            local want = CFrame.lookAt(cam.CFrame.Position, target.pos)
            cam.CFrame = cam.CFrame:Lerp(want, math.clamp(Config.Aimbot.Smooth, 0.01, 1))
        end
    end

    if fovCircle then
        fovCircle.Visible  = Config.Aimbot.Enabled and Config.Aimbot.ShowFOV
        fovCircle.Position = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
        fovCircle.Radius   = Config.Aimbot.FOV
    end

    updateESP()
    updateFly()
    applyNoclip()
end))

track(RunService.Heartbeat:Connect(function()
    applyMovement()
    updateWallhack()
    updateFullbright()
    if tick() - lastMisc > 1 then
        lastMisc = tick()
        updateEffects()
        autoReload()
        autoHeal()
    end
end))

track(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Q and UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
        Config.Aimbot.Enabled   = false
        Config.ESP.Enabled      = false
        Config.Movement.Fly     = false
        Config.Movement.Noclip  = false
        Config.Combat.RapidFire = false
        Config.Combat.NoRecoil  = false
        Config.Combat.NoSpread  = false
        Config.ESP.Wallhack     = false
        Config.Misc.Fullbright  = false
        updateFullbright()
        if flyBV then flyBV:Destroy(); flyBV = nil end
    end
end))

-- ═════════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ═════════════════════════════════════════════════════════════════════════════
getgenv().CAMAR_FPS_CLEANUP = function()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    for _, d in ipairs(drawingObjects) do pcall(function() d:Remove() end) end
    for obj in pairs(espObjects) do removeESP(obj) end
    clearWallhack()
    if flyBV then pcall(function() flyBV:Destroy() end) end
    pcall(function()
        for p, orig in pairs(noclipState) do
            if p and p.Parent then pcall(function() p.CanCollide = orig end) end
        end
        noclipState = {}
    end)
    pcall(function()
        for obj in pairs(removedEffects) do
            if obj and obj.Parent then pcall(function() obj.Enabled = true end) end
        end
        removedEffects = {}
    end)
    pcall(function()
        local containers = {
            (gethui and select(2, pcall(gethui))) or nil,
            (select(2, pcall(function() return game:GetService("CoreGui") end))) or nil,
            LocalPlayer:FindFirstChild("PlayerGui"),
        }
        for _, c in ipairs(containers) do
            if c then
                local old = c:FindFirstChild("CamarFPS")
                if old then old:Destroy() end
            end
        end
    end)
    getgenv().CAMAR_FPS_CLEANUP = nil
end

print("[Camar] v11 loaded. RightShift=GUI · RightShift+Q=panic · 🦐=minimized")