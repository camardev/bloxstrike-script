-- CAMAR UNIVERSAL FPS (v4)
-- language: Luau | target: Roblox client via executor
-- v4 fixes: window drag (title.Active), minimize button, slider MouseButton1Down+GetMouseLocation,
--           wallhack skips character parts, Hooks toggle honesto em runtime, AutoHeal via Tool:Activate,
--           local load -> loadBtn, cleanup on re-execute

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local getgenv           = getgenv or function() return _G end
local hookmetamethod    = hookmetamethod
local checkcaller       = checkcaller or function() return false end
local getnamecallmethod = getnamecallmethod
local writefile, readfile, isfile = writefile, readfile, isfile
local Drawing           = Drawing or error("Drawing required (Synapse/Fluxus/Delta/Wave)")

if getgenv().CAMAR_FPS_CLEANUP then pcall(getgenv().CAMAR_FPS_CLEANUP) end

-- ═════════════════════════════════════════════════════════════════════════════
-- CONFIG
-- ═════════════════════════════════════════════════════════════════════════════
local Config = {
    Aimbot   = { Enabled=false, Key="MouseButton2", Smooth=0.18, FOV=140, WallCheck=true, TeamCheck=true, ShowFOV=true },
    ESP      = { Enabled=false, Boxes=true, Names=true, Health=true, Distance=true, Chams=false, TeamColor=true, Wallhack=false, BoxColor=Color3.fromRGB(255,90,20) },
    Combat   = { NoRecoil=false, NoSpread=false, RapidFire=false, RapidFireMult=2, Hooks=true },
    Movement = { Speed=16, Jump=50, Fly=false, FlySpeed=60, Noclip=false },
    Misc     = { Fullbright=false, RemoveEffects=false, AutoReload=false, AutoHeal=false },
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
    for s, vals in pairs(data) do
        if Config[s] and type(vals) == "table" then
            for k, v in pairs(vals) do
                if type(v) == type(Config[s][k]) then Config[s][k] = v end
            end
        end
    end
end
loadConfig()

-- ═════════════════════════════════════════════════════════════════════════════
-- CLEANUP TRACKING
-- ═════════════════════════════════════════════════════════════════════════════
local connections, drawingObjects = {}, {}
local function track(c) table.insert(connections, c); return c end
local function trackDraw(d) table.insert(drawingObjects, d); return d end

-- ═════════════════════════════════════════════════════════════════════════════
-- DRAWING
-- ═════════════════════════════════════════════════════════════════════════════
local fovCircle = trackDraw(Drawing.new("Circle"))
fovCircle.Thickness = 1.5
fovCircle.Filled    = false
fovCircle.Color     = Color3.fromRGB(255, 90, 20)
fovCircle.Visible   = false

local function newText(size)
    local t = trackDraw(Drawing.new("Text"))
    t.Size = size or 14
    t.Center = true
    t.Color = Color3.new(1, 1, 1)
    t.Visible = false
    pcall(function() t.Outline = true end)
    return t
end

-- ═════════════════════════════════════════════════════════════════════════════
-- ESP
-- ═════════════════════════════════════════════════════════════════════════════
local espObjects = {}

local function createESP(plr)
    if espObjects[plr] then return end
    local ok, box = pcall(function() return trackDraw(Drawing.new("Square")) end)
    if not ok or not box then return end
    box.Thickness = 1
    box.Filled    = false
    box.Visible   = false

    local hl = Instance.new("Highlight")
    hl.Enabled = false
    hl.FillTransparency    = 0.65
    hl.OutlineTransparency = 0
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop

    espObjects[plr] = {
        box = box, name = newText(14), health = newText(12), distance = newText(12), highlight = hl,
    }
end

local function removeESP(plr)
    local o = espObjects[plr]
    if not o then return end
    for _, d in ipairs({o.box, o.name, o.health, o.distance}) do
        pcall(function() d:Remove() end)
    end
    pcall(function() o.highlight:Destroy() end)
    espObjects[plr] = nil
end

local function updateESP()
    if not Config.ESP.Enabled then
        for p in pairs(espObjects) do removeESP(p) end
        return
    end
    local cam = workspace.CurrentCamera
    if not cam then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if not espObjects[plr] then createESP(plr) end
        local o = espObjects[plr]
        if not o or not o.box then continue end

        local char = plr.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")

        if not (hrp and head and hum and hum.Health > 0) then
            o.box.Visible, o.name.Visible, o.health.Visible, o.distance.Visible = false, false, false, false
            pcall(function() o.highlight.Enabled = false end)
            continue
        end

        local teamColor = plr.Team and plr.Team.TeamColor.Color or Config.ESP.BoxColor
        local baseColor = Config.ESP.TeamColor and teamColor or Config.ESP.BoxColor

        if Config.ESP.Chams then
            if o.highlight.Parent ~= char then pcall(function() o.highlight.Parent = char end) end
            pcall(function() o.highlight.Enabled = true end)
            pcall(function()
                o.highlight.FillColor = baseColor
                o.highlight.OutlineColor = Color3.new(1, 1, 1)
            end)
        else
            pcall(function() o.highlight.Enabled = false end)
        end

        local top = head.Position + Vector3.new(0, 0.5, 0)
        local bottom = hrp.Position - Vector3.new(0, 2.6, 0)
        local topPos, topOn = cam:WorldToViewportPoint(top)
        local botPos, botOn = cam:WorldToViewportPoint(bottom)

        if not (topOn and botOn) then
            o.box.Visible, o.name.Visible, o.health.Visible, o.distance.Visible = false, false, false, false
            continue
        end

        local height = math.abs(topPos.Y - botPos.Y)
        local width  = height * 0.55
        o.box.Size     = Vector2.new(width, height)
        o.box.Position = Vector2.new(topPos.X - width / 2, topPos.Y)
        o.box.Color    = baseColor
        o.box.Visible  = Config.ESP.Boxes

        o.name.Text     = plr.Name
        o.name.Position = Vector2.new(topPos.X, topPos.Y - 18)
        o.name.Visible  = Config.ESP.Names

        o.health.Text     = string.format("HP %d", math.floor(hum.Health))
        o.health.Position = Vector2.new(topPos.X, topPos.Y + height + 2)
        o.health.Color    = Color3.fromRGB(60, 220, 60)
        o.health.Visible  = Config.ESP.Health

        local dist = (cam.CFrame.Position - hrp.Position).Magnitude
        o.distance.Text     = string.format("[%d]", math.floor(dist))
        o.distance.Position = Vector2.new(topPos.X, topPos.Y + height + 16)
        o.distance.Visible  = Config.ESP.Distance
    end

    for plr in pairs(espObjects) do
        if not plr.Parent then removeESP(plr) end
    end
end

-- wallhack — pula partes de personagem
local wallhackParts, lastWallhack = {}, 0
local function isCharPart(part)
    local cur = part.Parent
    for _ = 1, 6 do
        if not cur then return false end
        if cur:IsA("Model") and cur:FindFirstChildOfClass("Humanoid") then return true end
        cur = cur.Parent
    end
    return false
end
local function updateWallhack()
    if not Config.ESP.Wallhack then return end
    if tick() - lastWallhack < 2 then
        for part in pairs(wallhackParts) do
            if part.Parent then pcall(function() part.LocalTransparencyModifier = 0.55 end)
            else wallhackParts[part] = nil end
        end
        return
    end
    lastWallhack = tick()
    wallhackParts = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Transparency < 1 and not isCharPart(obj) then
            wallhackParts[obj] = true
            pcall(function() obj.LocalTransparencyModifier = 0.55 end)
        end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- AIMBOT
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
    return workspace:Raycast(cam.CFrame.Position, targetPos - cam.CFrame.Position, params) == nil
end

local function getAimTarget()
    local cam = workspace.CurrentCamera
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
        local dist = (screenPos - center).Magnitude
        if dist > Config.Aimbot.FOV then continue end
        if Config.Aimbot.WallCheck and not hasLOS(char, head.Position) then continue end
        if dist < bestScore then
            best, bestScore = {plr=plr, pos=head.Position, char=char}, dist
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
    if hum then
        if hum.WalkSpeed ~= Config.Movement.Speed then hum.WalkSpeed = Config.Movement.Speed end
        if hum.UseJumpPower ~= true then hum.UseJumpPower = true end
        if hum.JumpPower ~= Config.Movement.Jump then hum.JumpPower = Config.Movement.Jump end
    end
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
-- UTILITIES
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
local function removeEffects()
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("PostEffect") or obj:IsA("Atmosphere") then
            pcall(function() obj.Enabled = false end)
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
            pcall(function() tool.Parent = char end)
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
-- HOOKS — instala sempre (se disponível), checa toggle em runtime
-- ═════════════════════════════════════════════════════════════════════════════
local RECOIL = { Recoil=true, CameraRecoil=true, RecoilCamera=true, Kickback=true }
local SPREAD = { Spread=true, BulletSpread=true, Dispersion=true }

local oldIndex, oldNamecall

if hookmetamethod and getnamecallmethod then
    -- __index
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

    -- __namecall
    local okNc, resNc = pcall(function()
        return hookmetamethod(game, "__namecall", function(self, ...)
            if not checkcaller() and Config.Combat.Hooks then
                local method = getnamecallmethod()
                if method == "Kick" and self == LocalPlayer then
                    return nil
                end
                if method == "FireServer" and Config.Combat.RapidFire then
                    local okC, cls = pcall(function() return self.ClassName end)
                    if okC and cls == "RemoteEvent" then
                        local okN, nm = pcall(function() return self.Name end)
                        if okN and type(nm) == "string" then
                            local l = nm:lower()
                            if l:find("fire") or l:find("shoot") or l:find("attack") or l:find("weapon") then
                                for _ = 1, Config.Combat.RapidFireMult do
                                    oldNamecall(self, ...)
                                end
                                return
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
-- GUI
-- ═════════════════════════════════════════════════════════════════════════════
local function buildGUI()
    local old = LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("CamarFPS")
    if old then old:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "CamarFPS"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.IgnoreGuiInset = false
    sg.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 520, 0, 440)
    main.Position = UDim2.new(0, 40, 0, 40)
    main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = sg
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 6)

    local title = Instance.new("Frame")
    title.Size = UDim2.new(1, 0, 0, 32)
    title.BackgroundColor3 = Color3.fromRGB(255, 90, 20)
    title.BorderSizePixel = 0
    title.Active = true
    title.Parent = main
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 6)

    local tText = Instance.new("TextLabel")
    tText.Size = UDim2.new(1, -95, 1, 0)
    tText.Position = UDim2.new(0, 12, 0, 0)
    tText.BackgroundTransparency = 1
    tText.Text = "CAMAR · FPS"
    tText.TextColor3 = Color3.new(1, 1, 1)
    tText.TextXAlignment = Enum.TextXAlignment.Left
    tText.Font = Enum.Font.GothamBold
    tText.TextSize = 14
    tText.Parent = title

    -- minimize button
    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 24, 0, 24)
    minBtn.Position = UDim2.new(1, -58, 0, 4)
    minBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
    minBtn.Text = "–"
    minBtn.TextColor3 = Color3.new(1, 1, 1)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 16
    minBtn.BorderSizePixel = 0
    minBtn.Parent = title
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

    -- close button
    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 24, 0, 24)
    close.Position = UDim2.new(1, -30, 0, 4)
    close.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
    close.Text = "×"
    close.TextColor3 = Color3.new(1, 1, 1)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 16
    close.BorderSizePixel = 0
    close.Parent = title
    Instance.new("UICorner", close).CornerRadius = UDim.new(0, 4)
    close.MouseButton1Click:Connect(function() main.Visible = false end)

    local tabs = Instance.new("Frame")
    tabs.Size = UDim2.new(0, 110, 1, -32)
    tabs.Position = UDim2.new(0, 0, 0, 32)
    tabs.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
    tabs.BorderSizePixel = 0
    tabs.Parent = main
    Instance.new("UIListLayout", tabs).Padding = UDim.new(0, 2)
    local tp = Instance.new("UIPadding", tabs)
    tp.PaddingTop, tp.PaddingLeft, tp.PaddingRight = UDim.new(0, 8), UDim.new(0, 6), UDim.new(0, 6)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -110, 1, -32)
    content.Position = UDim2.new(0, 110, 0, 32)
    content.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
    content.BorderSizePixel = 0
    content.Parent = main

    local pages = {}
    local function selectTab(n) for k, p in pairs(pages) do p.Visible = (k == n) end end

    local function newTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 28)
        btn.BackgroundColor3 = Color3.fromRGB(42, 42, 50)
        btn.Text = name
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 12
        btn.BorderSizePixel = 0
        btn.Parent = tabs
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.new(1, -20, 1, -20)
        page.Position = UDim2.new(0, 10, 0, 10)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 4
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.ScrollingDirection = Enum.ScrollingDirection.Y
        page.Parent = content
        Instance.new("UIListLayout", page).Padding = UDim.new(0, 6)

        pages[name] = page
        btn.MouseButton1Click:Connect(function() selectTab(name) end)
        return page
    end

    local function makeToggle(parent, label, tbl, key)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -10, 0, 28)
        row.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
        row.BorderSizePixel = 0
        row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -60, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = Color3.fromRGB(220, 220, 225)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.Parent = row

        local sw = Instance.new("TextButton")
        sw.Size = UDim2.new(0, 36, 0, 16)
        sw.Position = UDim2.new(1, -46, 0.5, -8)
        sw.BackgroundColor3 = tbl[key] and Color3.fromRGB(255, 90, 20) or Color3.fromRGB(60, 60, 68)
        sw.Text = ""
        sw.BorderSizePixel = 0
        sw.Parent = row
        Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 12, 0, 12)
        knob.Position = tbl[key] and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel = 0
        knob.Parent = sw
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        sw.MouseButton1Click:Connect(function()
            tbl[key] = not tbl[key]
            sw.BackgroundColor3 = tbl[key] and Color3.fromRGB(255, 90, 20) or Color3.fromRGB(60, 60, 68)
            knob.Position = tbl[key] and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
            saveConfig()
        end)
    end

    local function makeSlider(parent, label, tbl, key, mn, mx, isInt)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -10, 0, 42)
        row.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
        row.BorderSizePixel = 0
        row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -20, 0, 16)
        lbl.Position = UDim2.new(0, 10, 0, 2)
        lbl.BackgroundTransparency = 1
        lbl.Text = label .. "  (" .. tostring(tbl[key]) .. ")"
        lbl.TextColor3 = Color3.fromRGB(220, 220, 225)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.Parent = row

        local bar = Instance.new("TextButton")
        bar.Size = UDim2.new(1, -20, 0, 10)
        bar.Position = UDim2.new(0, 10, 1, -16)
        bar.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
        bar.Text = ""
        bar.AutoButtonColor = false
        bar.BorderSizePixel = 0
        bar.Parent = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame")
        local startRel = math.clamp((tbl[key] - mn) / (mx - mn), 0, 1)
        fill.Size = UDim2.new(startRel, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(255, 90, 20)
        fill.BorderSizePixel = 0
        fill.Parent = bar
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local sliderDrag = false
        local function setFromMouse()
            local mouseX = UserInputService:GetMouseLocation().X
            local rel = math.clamp((mouseX - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
            local val = mn + (mx - mn) * rel
            if isInt then val = math.floor(val + 0.5) end
            tbl[key] = val
            fill.Size = UDim2.new(rel, 0, 1, 0)
            lbl.Text = label .. "  (" .. tostring(val) .. ")"
        end

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

    local aim = newTab("Aimbot")
    makeToggle(aim, "Enabled",    Config.Aimbot, "Enabled")
    makeToggle(aim, "Wall Check", Config.Aimbot, "WallCheck")
    makeToggle(aim, "Team Check", Config.Aimbot, "TeamCheck")
    makeToggle(aim, "Show FOV",   Config.Aimbot, "ShowFOV")
    makeSlider(aim, "Smooth",     Config.Aimbot, "Smooth", 0.05, 1, false)
    makeSlider(aim, "FOV",        Config.Aimbot, "FOV",    20, 400, true)

    local esp = newTab("ESP")
    makeToggle(esp, "Enabled",    Config.ESP, "Enabled")
    makeToggle(esp, "Boxes",      Config.ESP, "Boxes")
    makeToggle(esp, "Names",      Config.ESP, "Names")
    makeToggle(esp, "Health",     Config.ESP, "Health")
    makeToggle(esp, "Distance",   Config.ESP, "Distance")
    makeToggle(esp, "Chams",      Config.ESP, "Chams")
    makeToggle(esp, "Team Color", Config.ESP, "TeamColor")
    makeToggle(esp, "Wallhack",   Config.ESP, "Wallhack")

    local combat = newTab("Combat")
    makeToggle(combat, "Hooks On",   Config.Combat, "Hooks")
    makeToggle(combat, "No Recoil",  Config.Combat, "NoRecoil")
    makeToggle(combat, "No Spread",  Config.Combat, "NoSpread")
    makeToggle(combat, "Rapid Fire", Config.Combat, "RapidFire")
    makeSlider(combat, "Rapid Mult", Config.Combat, "RapidFireMult", 1, 10, true)

    local mv = newTab("Movement")
    makeSlider(mv, "Speed",     Config.Movement, "Speed", 8, 200, true)
    makeSlider(mv, "Jump",      Config.Movement, "Jump",  50, 300, true)
    makeToggle(mv, "Fly",       Config.Movement, "Fly")
    makeSlider(mv, "Fly Speed", Config.Movement, "FlySpeed", 10, 300, true)
    makeToggle(mv, "Noclip",    Config.Movement, "Noclip")

    local misc = newTab("Misc")
    makeToggle(misc, "Fullbright",     Config.Misc, "Fullbright")
    makeToggle(misc, "Remove Effects", Config.Misc, "RemoveEffects")
    makeToggle(misc, "Auto Reload",    Config.Misc, "AutoReload")
    makeToggle(misc, "Auto Heal",      Config.Misc, "AutoHeal")

    local tpBox = Instance.new("TextBox")
    tpBox.Size = UDim2.new(1, -10, 0, 28)
    tpBox.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
    tpBox.PlaceholderText = "player name → teleport"
    tpBox.Text = ""
    tpBox.TextColor3 = Color3.new(1, 1, 1)
    tpBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
    tpBox.Font = Enum.Font.Gotham
    tpBox.TextSize = 12
    tpBox.BorderSizePixel = 0
    tpBox.Parent = misc
    Instance.new("UICorner", tpBox).CornerRadius = UDim.new(0, 4)
    tpBox.FocusLost:Connect(function()
        if tpBox.Text ~= "" then teleportTo(tpBox.Text) end
    end)

    local specBox = tpBox:Clone()
    specBox.PlaceholderText = "player name → spectate"
    specBox.Parent = misc
    specBox.FocusLost:Connect(function()
        if specBox.Text ~= "" then spectate(specBox.Text) end
    end)

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(1, -10, 0, 28)
    saveBtn.BackgroundColor3 = Color3.fromRGB(255, 90, 20)
    saveBtn.Text = "Save Config"
    saveBtn.TextColor3 = Color3.new(1, 1, 1)
    saveBtn.Font = Enum.Font.Gotham
    saveBtn.TextSize = 12
    saveBtn.BorderSizePixel = 0
    saveBtn.Parent = misc
    Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 4)
    saveBtn.MouseButton1Click:Connect(saveConfig)

    local loadBtn = saveBtn:Clone()
    loadBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
    loadBtn.Text = "Load Config"
    loadBtn.Parent = misc
    loadBtn.MouseButton1Click:Connect(function()
        loadConfig()
        applyFullbright()
    end)

    selectTab("Aimbot")

    -- window drag — title.Active = true garante captura
    local titleDrag = false
    local dragStartMouse, dragStartPos
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            titleDrag = true
            dragStartMouse = UserInputService:GetMouseLocation()
            dragStartPos = main.Position
        end
    end)
    track(UserInputService.InputChanged:Connect(function(input)
        if titleDrag and input.UserInputType == Enum.UserInputType.MouseMovement then
            local cur = UserInputService:GetMouseLocation()
            local dx = cur.X - dragStartMouse.X
            local dy = cur.Y - dragStartMouse.Y
            main.Position = UDim2.new(
                dragStartPos.X.Scale, dragStartPos.X.Offset + dx,
                dragStartPos.Y.Scale, dragStartPos.Y.Offset + dy
            )
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then titleDrag = false end
    end))

    -- minimize
    local minimized = false
    local fullSize = UDim2.new(0, 520, 0, 440)
    local minSize  = UDim2.new(0, 520, 0, 32)
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        main.Size = minimized and minSize or fullSize
        tabs.Visible = not minimized
        content.Visible = not minimized
        minBtn.Text = minimized and "□" or "–"
    end)

    -- RightShift toggle
    track(UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then main.Visible = not main.Visible end
    end))

    return sg
end

local okGui, guiErr = pcall(buildGUI)
if not okGui then warn("[Camar] GUI failed:", guiErr); print("[Camar] GUI failed:", guiErr) end

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

    fovCircle.Visible  = Config.Aimbot.Enabled and Config.Aimbot.ShowFOV
    fovCircle.Position = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    fovCircle.Radius   = Config.Aimbot.FOV

    updateESP()
    updateWallhack()
    updateFly()
    applyNoclip()
end))

track(RunService.Heartbeat:Connect(function()
    applyMovement()
    if Config.Misc.Fullbright then applyFullbright() end
    if tick() - lastMisc > 1 then
        lastMisc = tick()
        if Config.Misc.RemoveEffects then removeEffects() end
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
        applyFullbright()
        if flyBV then flyBV:Destroy(); flyBV = nil end
    end
end))

-- ═════════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ═════════════════════════════════════════════════════════════════════════════
getgenv().CAMAR_FPS_CLEANUP = function()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    for _, d in ipairs(drawingObjects) do pcall(function() d:Remove() end) end
    for _, o in pairs(espObjects) do
        pcall(function() o.box:Remove() end)
        pcall(function() o.name:Remove() end)
        pcall(function() o.health:Remove() end)
        pcall(function() o.distance:Remove() end)
        pcall(function() o.highlight:Destroy() end)
    end
    if flyBV then pcall(function() flyBV:Destroy() end) end
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local old = pg and pg:FindFirstChild("CamarFPS")
        if old then old:Destroy() end
    end)
end

print(string.format(
    "[Camar] v4 loaded. Drawing=%s · Hooks=%s. RightShift=GUI · RightShift+Q=panic",
    tostring(Drawing ~= nil),
    tostring(hookmetamethod ~= nil and getnamecallmethod ~= nil)
))