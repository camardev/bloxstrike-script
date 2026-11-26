-- CAMAR UNIVERSAL FPS
-- language: Luau (Lua 5.1 + Roblox) | target: Roblox client via executor
-- requires: Drawing, hookmetamethod, getrawmetatable, checkcaller, getnamecallmethod
-- drop in any FPS place — auto-detects players and weapon tools

-- ═════════════════════════════════════════════════════════════════════════════
-- 0. SERVICES
-- ═════════════════════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local cloneref          = cloneref or function(o) return o end
local getgenv           = getgenv or function() return _G end
local getrawmetatable   = getrawmetatable
local setreadonly       = setreadonly
local hookfunction      = hookfunction
local hookmetamethod    = hookmetamethod
local checkcaller       = checkcaller or function() return false end
local getnamecallmethod = getnamecallmethod
local writefile         = writefile
local readfile          = readfile
local isfile            = isfile
local Drawing           = Drawing or error("Drawing required (Synapse / Scriptware / Fluxus / Delta)")

-- ═════════════════════════════════════════════════════════════════════════════
-- 1. CONFIG
-- ═════════════════════════════════════════════════════════════════════════════
local Config = {
    Aimbot = {
        Enabled     = false,
        Key         = "MouseButton2",
        Smooth      = 0.18,
        FOV         = 140,
        WallCheck   = true,
        TeamCheck   = true,
        ShowFOV     = true,
    },
    ESP = {
        Enabled   = false,
        Boxes     = true,
        Names     = true,
        Health    = true,
        Distance  = true,
        Chams     = false,
        TeamColor = true,
        BoxColor  = Color3.fromRGB(255, 90, 20),
    },
    Combat = {
        NoRecoil      = false,
        NoSpread      = false,
        RapidFire     = false,
        RapidFireMult = 2,
    },
    Movement = {
        Speed    = 16,
        Jump     = 50,
        Fly      = false,
        FlySpeed = 60,
        Noclip   = false,
    },
    Misc = {
        Fullbright    = false,
        RemoveEffects = false,
        AutoReload    = false,
        AutoHeal      = false,
    },
}

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
    for section, values in pairs(data) do
        if Config[section] and type(values) == "table" then
            for k, v in pairs(values) do
                if type(v) == type(Config[section][k]) then Config[section][k] = v end
            end
        end
    end
end

loadConfig()

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. DRAWING PRIMITIVES
-- ═════════════════════════════════════════════════════════════════════════════
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1.5
fovCircle.Filled    = false
fovCircle.NumSides  = 90
fovCircle.Color     = Color3.fromRGB(255, 90, 20)
fovCircle.Visible   = false

local function newText(size, center)
    local t = Drawing.new("Text")
    t.Size    = size or 14
    t.Center  = center ~= false
    t.Outline = true
    t.Color   = Color3.new(1, 1, 1)
    t.Visible = false
    return t
end

-- ═════════════════════════════════════════════════════════════════════════════
-- 3. ESP MODULE
-- ═════════════════════════════════════════════════════════════════════════════
local espObjects = {}

local function createESP(plr)
    if espObjects[plr] then return end
    local box = Drawing.new("Square")
    box.Thickness = 1
    box.Filled    = false
    box.Visible   = false

    local hl = Instance.new("Highlight")
    hl.Enabled              = false
    hl.FillTransparency     = 0.65
    hl.OutlineTransparency  = 0
    hl.DepthMode            = Enum.HighlightDepthMode.AlwaysOnTop

    espObjects[plr] = {
        box      = box,
        name     = newText(14, true),
        health   = newText(12, true),
        distance = newText(12, true),
        highlight = hl,
    }
end

local function removeESP(plr)
    local o = espObjects[plr]
    if not o then return end
    for _, d in pairs({o.box, o.name, o.health, o.distance}) do
        pcall(function() d:Remove() end)
    end
    pcall(function() o.highlight:Destroy() end)
    espObjects[plr] = nil
end

local function updateESP()
    if not Config.ESP.Enabled then
        for plr in pairs(espObjects) do removeESP(plr) end
        return
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if not espObjects[plr] then createESP(plr) end
        local o = espObjects[plr]

        local char = plr.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")

        if not (hrp and head and hum and hum.Health > 0) then
            o.box.Visible, o.name.Visible, o.health.Visible, o.distance.Visible = false, false, false, false
            o.highlight.Enabled = false
            continue
        end

        local teamColor = plr.Team and plr.Team.TeamColor.Color or Config.ESP.BoxColor
        local baseColor = Config.ESP.TeamColor and teamColor or Config.ESP.BoxColor

        -- chams
        if Config.ESP.Chams then
            if o.highlight.Parent ~= char then o.highlight.Parent = char end
            o.highlight.Enabled      = true
            o.highlight.FillColor    = baseColor
            o.highlight.OutlineColor = Color3.new(1, 1, 1)
        else
            o.highlight.Enabled = false
        end

        -- corners
        local top    = head.Position + Vector3.new(0, 0.5, 0)
        local bottom = hrp.Position  - Vector3.new(0, 2.6, 0)
        local topPos, topOn     = workspace.CurrentCamera:WorldToViewportPoint(top)
        local botPos, botOn     = workspace.CurrentCamera:WorldToViewportPoint(bottom)

        if not (topOn and botOn) then
            o.box.Visible, o.name.Visible, o.health.Visible, o.distance.Visible = false, false, false, false
            continue
        end

        local height = math.abs(topPos.Y - botPos.Y)
        local width  = height * 0.55
        local cx     = topPos.X - width / 2

        o.box.Size     = Vector2.new(width, height)
        o.box.Position = Vector2.new(cx, topPos.Y)
        o.box.Color    = baseColor
        o.box.Visible  = Config.ESP.Boxes

        o.name.Text     = plr.Name
        o.name.Position = Vector2.new(topPos.X, topPos.Y - 18)
        o.name.Color    = Color3.new(1, 1, 1)
        o.name.Visible  = Config.ESP.Names

        o.health.Text     = string.format("HP %d", math.floor(hum.Health))
        o.health.Position = Vector2.new(topPos.X, topPos.Y + height + 2)
        o.health.Color    = Color3.fromRGB(60, 220, 60)
        o.health.Visible  = Config.ESP.Health

        local dist = (workspace.CurrentCamera.CFrame.Position - hrp.Position).Magnitude
        o.distance.Text     = string.format("[%d]", math.floor(dist))
        o.distance.Position = Vector2.new(topPos.X, topPos.Y + height + 16)
        o.distance.Color    = Color3.fromRGB(220, 220, 220)
        o.distance.Visible  = Config.ESP.Distance
    end

    for plr in pairs(espObjects) do
        if not plr.Parent then removeESP(plr) end
    end
end

-- wall transparency — applied locally per-part
local function updateWallhack()
    if not Config.ESP.Enabled then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Transparency < 1 then
            pcall(function() obj.LocalTransparencyModifier = 0.55 end)
        end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- 4. AIMBOT MODULE
-- ═════════════════════════════════════════════════════════════════════════════
local function keyHeld()
    local k = Config.Aimbot.Key
    if k == "MouseButton1" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
    if k == "MouseButton2" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
    if k == "Always" then return true end
    local kc = Enum.KeyCode[k]
    return kc and UserInputService:IsKeyDown(kc) or false
end

local function hasLOS(targetChar, targetPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local filter = {targetChar}
    if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
    params.FilterDescendantsInstances = filter
    local cam = workspace.CurrentCamera
    local result = workspace:Raycast(cam.CFrame.Position, targetPos - cam.CFrame.Position, params)
    return result == nil
end

local function getAimTarget()
    local cam    = workspace.CurrentCamera
    local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local best, bestScore = nil, math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if Config.Aimbot.TeamCheck and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then continue end

        local char = plr.Character
        local head = char and char:FindFirstChild("Head")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not (head and hum and hum.Health > 0) then continue end

        local pos, onScreen = cam:WorldToViewportPoint(head.Position)
        if not onScreen then continue end

        local screenPos = Vector2.new(pos.X, pos.Y)
        local dist      = (screenPos - center).Magnitude
        if dist > Config.Aimbot.FOV then continue end

        if Config.Aimbot.WallCheck and not hasLOS(char, head.Position) then continue end

        if dist < bestScore then
            best, bestScore = {plr = plr, pos = head.Position, char = char}, dist
        end
    end
    return best
end

-- ═════════════════════════════════════════════════════════════════════════════
-- 5. MOVEMENT MODULE
-- ═════════════════════════════════════════════════════════════════════════════
local flyBV

local function applyMovement()
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed    = Config.Movement.Speed
        hum.JumpPower    = Config.Movement.Jump
        hum.UseJumpPower = true
    end
end

local function updateFly()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        if flyBV then flyBV:Destroy(); flyBV = nil end
        return
    end

    if Config.Movement.Fly then
        if not flyBV then
            flyBV = Instance.new("BodyVelocity")
            flyBV.MaxForce = Vector3.new(1e6, 1e6, 1e6)
            flyBV.Parent   = hrp
        end
        local cam   = workspace.CurrentCamera
        local move  = Vector3.new(0, 0, 0)
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

local function applyNoclip()
    if not Config.Movement.Noclip then return end
    local char = LocalPlayer.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
        end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- 6. UTILITIES
-- ═════════════════════════════════════════════════════════════════════════════
local lightingBackup = {
    Brightness     = Lighting.Brightness,
    Ambient        = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    ClockTime      = Lighting.ClockTime,
    FogEnd         = Lighting.FogEnd,
}

local function applyFullbright()
    if Config.Misc.Fullbright then
        Lighting.Brightness     = 3
        Lighting.ClockTime      = 12
        Lighting.Ambient        = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.FogEnd         = 1e6
    else
        for k, v in pairs(lightingBackup) do pcall(function() Lighting[k] = v end) end
    end
end

local function removeEffects()
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("PostEffect") or obj:IsA("Atmosphere") or obj:IsA("Sky") then
            pcall(function() obj.Enabled = false end)
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") then
            local p = obj.Parent and obj.Parent.Name:lower() or ""
            if p:find("smoke") or p:find("flash") or p:find("gas") then
                pcall(function() obj.Enabled = false end)
            end
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
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not (hum and hum.Health < hum.MaxHealth) then return end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return end
    for _, tool in ipairs(bp:GetChildren()) do
        if tool:IsA("Tool") and (tool.Name:lower():find("heal") or tool.Name:lower():find("med")) then
            pcall(function() tool.Parent = char end)
            task.wait(0.1)
            for _, v in ipairs(tool:GetDescendants()) do
                if v:IsA("RemoteEvent") then pcall(function() v:FireServer() end) end
            end
            return
        end
    end
end

local function teleportTo(name)
    local target = Players:FindFirstChild(name)
    if not (target and target.Character) then return end
    local thrp = target.Character:FindFirstChild("HumanoidRootPart")
    local myhrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if thrp and myhrp then
        myhrp.CFrame = thrp.CFrame * CFrame.new(0, 3, 0)
    end
end

local function spectate(name)
    local target = Players:FindFirstChild(name)
    if target and target.Character then
        local hum = target.Character:FindFirstChildOfClass("Humanoid")
        if hum then workspace.CurrentCamera.CameraSubject = hum end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- 7. HOOKS — No Recoil / No Spread / Rapid Fire / Kick Bypass
-- ═════════════════════════════════════════════════════════════════════════════
if getrawmetatable and hookmetamethod and setreadonly then
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", function(self, key)
        if not checkcaller() then
            local nm = self.Name and self.Name:lower() or ""
            local weaponish = self:IsA("Tool") or nm:find("weapon") or nm:find("gun") or self:IsA("ModuleScript")
            if weaponish then
                if (Config.Combat.NoRecoil and (key == "Recoil" or key == "CameraRecoil" or key == "RecoilCamera" or key == "Kickback"))
                    or (Config.Combat.NoSpread and (key == "Spread" or key == "BulletSpread" or key == "Dispersion")) then
                    return 0
                end
            end
        end
        return oldIndex(self, key)
    end)
end

if hookmetamethod and getnamecallmethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if not checkcaller() then
            -- kick bypass — swallow self-kick
            if method == "Kick" and self == LocalPlayer then
                return nil
            end
            -- rapid fire on FireServer for weapon remotes
            if Config.Combat.RapidFire and method == "FireServer" and type(self) == "userdata" and self:IsA("RemoteEvent") then
                local n = self.Name:lower()
                if n:find("fire") or n:find("shoot") or n:find("attack") or n:find("weapon") then
                    for _ = 1, Config.Combat.RapidFireMult do
                        pcall(oldNamecall, self, ...)
                    end
                    return
                end
            end
        end
        return oldNamecall(self, ...)
    end)
end

-- neutralize common report remotes
for _, remote in ipairs(game:GetDescendants()) do
    if remote:IsA("RemoteEvent") then
        local n = remote.Name:lower()
        if n:find("report") or n:find("vote_kick") or n:find("votekick") then
            pcall(function() remote:Destroy() end)
        end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- 8. GUI
-- ═════════════════════════════════════════════════════════════════════════════
local function buildGUI()
    local sg = Instance.new("ScreenGui")
    sg.Name = "CamarFPS"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local main = Instance.new("Frame")
    main.Size            = UDim2.new(0, 520, 0, 440)
    main.Position        = UDim2.new(0, 40, 0, 40)
    main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    main.BorderSizePixel = 0
    main.Active          = true
    main.Parent          = sg
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 6)

    -- title bar
    local title = Instance.new("Frame")
    title.Size            = UDim2.new(1, 0, 0, 32)
    title.BackgroundColor3 = Color3.fromRGB(255, 90, 20)
    title.BorderSizePixel = 0
    title.Parent          = main
    local tc = Instance.new("UICorner", title)
    tc.CornerRadius = UDim.new(0, 6)

    local tText = Instance.new("TextLabel")
    tText.Size = UDim2.new(1, -50, 1, 0)
    tText.Position = UDim2.new(0, 12, 0, 0)
    tText.BackgroundTransparency = 1
    tText.Text = "CAMAR · FPS"
    tText.TextColor3 = Color3.new(1, 1, 1)
    tText.TextXAlignment = Enum.TextXAlignment.Left
    tText.Font = Enum.Font.GothamBold
    tText.TextSize = 14
    tText.Parent = title

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 24, 0, 24)
    close.Position = UDi