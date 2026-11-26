-- language: Lua, file: bloxstrike_hub.lua, target: Roblox BloxStrike
-- executor: Delta / Xeno / Wave / Synapse (high sUNC)

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- ============================================================
-- 1. ESTADO GLOBAL (toggles do cheat)
-- ============================================================
getgenv().BS = {
    -- Combat
    Aimbot          = false,
    AimbotKey       = Enum.KeyCode.E,
    AimbotFOV       = 120,
    AimbotSmooth    = 0.25,
    AimbotPart      = "Head",
    AimbotTeamCheck = true,
    AimbotWallCheck = true,

    SilentAim       = false,
    SilentPart      = "Head",
    SilentFOV       = 150,
    SilentWallbang  = false,
    SilentTeamCheck = true,

    Triggerbot      = false,
    TriggerDelay    = 0.01,

    -- Visuals
    ESP             = false,
    ESPBox          = true,
    ESPName         = true,
    ESPHealth       = true,
    ESPDistance     = true,
    ESPTracer       = false,

    -- Misc
    HitboxExpander  = false,
    HitboxSize      = 7,
    NoRecoil        = false,
    NoSpread        = false,
    Wallbang        = false,
    FireRate        = false,
}

-- ============================================================
-- 2. UTILITÁRIOS
-- ============================================================
local function is_enemy(player)
    if player == LocalPlayer then return false end
    if not getgenv().BS.AimbotTeamCheck and not getgenv().BS.SilentTeamCheck then
        return true
    end
    local my_team = LocalPlayer.Team
    local their_team = player.Team
    if not my_team or not their_team then return true end
    return my_team ~= their_team
end

local function get_character(player)
    local char = player.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return char, hum
end

local function get_part(char, part_name)
    return char:FindFirstChild(part_name) or char:FindFirstChild("Head")
end

local function is_visible(part)
    if not getgenv().BS.AimbotWallCheck then return true end
    local origin = Camera.CFrame.Position
    local dir = (part.Position - origin).Unit * (part.Position - origin).Magnitude
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    local hit = Workspace:Raycast(origin, dir, params)
    return hit == nil or hit.Instance:IsDescendantOf(part.Parent)
end

-- ============================================================
-- 3. SILENT AIM (hook no __namecall para Raycast)
-- ============================================================
local silent_target = nil
local silent_hooked = false

local function setup_silent_aim()
    if silent_hooked then return end
    silent_hooked = true

    local mt = getrawmetatable(game)
    local old_namecall = mt.__namecall
    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if not getgenv().BS.SilentAim then
            return old_namecall(self, ...)
        end

        if method == "Raycast" and self == Workspace and silent_target
           and silent_target.Parent and not checkcaller() then
            local origin = args[1]
            local direction = args[2]
            if typeof(direction) == "Vector3" then
                local new_dir = (silent_target.Position - origin).Unit * direction.Magnitude
                return old_namecall(self, origin, new_dir, select(3, ...))
            end
        end

        return old_namecall(self, ...)
    end)

    setreadonly(mt, true)
end

local function update_silent_target()
    silent_target = nil
    if not getgenv().BS.SilentAim then return end

    local best_dist = getgenv().BS.SilentFOV
    local mouse_pos = UserInputService:GetMouseLocation()

    for _, player in ipairs(Players:GetPlayers()) do
        if not is_enemy(player) then continue end
        local char = get_character(player)
        if not char then continue end
        local part = get_part(char, getgenv().BS.SilentPart)
        if not part then continue end

        if getgenv().BS.SilentWallbang == false and not is_visible(part) then
            continue
        end

        local screen_pos, on_screen = Camera:WorldToViewportPoint(part.Position)
        if on_screen then
            local dist = (Vector2.new(screen_pos.X, screen_pos.Y) - mouse_pos).Magnitude
            if dist < best_dist then
                best_dist = dist
                silent_target = part
            end
        end
    end
end

-- ============================================================
-- 4. AIMBOT (camera lock)
-- ============================================================
local aimbot_target = nil

local function update_aimbot()
    aimbot_target = nil
    if not getgenv().BS.Aimbot then return end
    if not UserInputService:IsKeyDown(getgenv().BS.AimbotKey) then return end

    local best_dist = getgenv().BS.AimbotFOV
    local mouse_pos = UserInputService:GetMouseLocation()

    for _, player in ipairs(Players:GetPlayers()) do
        if not is_enemy(player) then continue end
        local char = get_character(player)
        if not char then continue end
        local part = get_part(char, getgenv().BS.AimbotPart)
        if not part then continue end

        if not is_visible(part) then continue end

        local screen_pos, on_screen = Camera:WorldToViewportPoint(part.Position)
        if on_screen then
            local dist = (Vector2.new(screen_pos.X, screen_pos.Y) - mouse_pos).Magnitude
            if dist < best_dist then
                best_dist = dist
                aimbot_target = part
            end
        end
    end
end

local function apply_aimbot()
    if not aimbot_target then return end
    local target_pos = aimbot_target.Position
    local current_cf = Camera.CFrame
    local target_cf = CFrame.new(current_cf.Position, target_pos)
    Camera.CFrame = current_cf:Lerp(target_cf, getgenv().BS.AimbotSmooth)
end

-- ============================================================
-- 5. TRIGGERBOT
-- ============================================================
local last_trigger = 0

local function run_triggerbot()
    if not getgenv().BS.Triggerbot then return end
    if tick() - last_trigger < getgenv().BS.TriggerDelay then return end

    local mouse_pos = UserInputService:GetMouseLocation()
    for _, player in ipairs(Players:GetPlayers()) do
        if not is_enemy(player) then continue end
        local char = get_character(player)
        if not char then continue end
        local part = get_part(char, "Head")
        if not part then continue end

        local screen_pos, on_screen = Camera:WorldToViewportPoint(part.Position)
        if on_screen then
            local dist = (Vector2.new(screen_pos.X, screen_pos.Y) - mouse_pos).Magnitude
            if dist < 25 then
                -- Dispara via VirtualInputManager (contorna bloqueios de mouse)
                local vim = game:GetService("VirtualInputManager")
                vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                task.wait(0.05)
                vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                last_trigger = tick()
                break
            end
        end
    end
end

-- ============================================================
-- 6. ESP (desenho no Viewport)
-- ============================================================
local esp_folder = Instance.new("Folder", Workspace)
esp_folder.Name = "BS_ESP"

local function create_esp(player)
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local box = Drawing.new("Square")
    box.Thickness = 1
    box.Filled = false
    box.Color = Color3.fromRGB(255, 50, 50)
    box.Visible = false

    local name = Drawing.new("Text")
    name.Size = 14
    name.Center = true
    name.Outline = true
    name.Color = Color3.fromRGB(255, 255, 255)
    name.Visible = false

    local health = Drawing.new("Text")
    health.Size = 12
    health.Center = false
    health.Outline = true
    health.Color = Color3.fromRGB(0, 255, 0)
    health.Visible = false

    local dist_text = Drawing.new("Text")
    dist_text.Size = 12
    dist_text.Center = false
    dist_text.Outline = true
    dist_text.Color = Color3.fromRGB(200, 200, 200)
    dist_text.Visible = false

    local tracer = Drawing.new("Line")
    tracer.Thickness = 1
    tracer.Color = Color3.fromRGB(255, 255, 255)
    tracer.Visible = false

    local data = {box=box, name=name, health=health, dist=dist_text, tracer=tracer, hum=hum}
    player:SetAttribute("BS_ESP_Data", data) -- armazena na instância (não ideal, mas funciona)

    -- Loop de atualização por player
    task.spawn(function()
        while player.Parent and char.Parent do
            if not getgenv().BS.ESP then
                box.Visible = false; name.Visible = false; health.Visible = false
                dist_text.Visible = false; tracer.Visible = false
                RunService.RenderStepped:Wait()
                continue
            end

            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp or hum.Health <= 0 then
                box.Visible = false; name.Visible = false; health.Visible = false
                dist_text.Visible = false; tracer.Visible = false
                RunService.RenderStepped:Wait()
                continue
            end

            local pos, on_screen = Camera:WorldToViewportPoint(hrp.Position)
            if on_screen then
                local head = char:FindFirstChild("Head")
                local head_pos = head and Camera:WorldToViewportPoint(head.Position)
                local height = 0
                if head_pos and head_pos.Z > 0 then
                    height = math.abs(pos.Y - head_pos.Y) * 1.2
                else
                    height = 60
                end
                local width = height / 2

                if getgenv().BS.ESPBox then
                    box.Size = Vector2.new(width, height)
                    box.Position = Vector2.new(pos.X - width/2, pos.Y - height/2)
                    box.Visible = true
                else
                    box.Visible = false
                end

                if getgenv().BS.ESPName then
                    name.Text = player.Name
                    name.Position = Vector2.new(pos.X, pos.Y - height/2 - 16)
                    name.Visible = true
                else
                    name.Visible = false
                end

                if getgenv().BS.ESPHealth then
                    health.Text = "HP: " .. math.floor(hum.Health)
                    health.Position = Vector2.new(pos.X + width/2 + 4, pos.Y - height/2)
                    health.Visible = true
                else
                    health.Visible = false
                end

                if getgenv().ESPDistance then
                    local d = (Camera.CFrame.Position - hrp.Position).Magnitude
                    dist_text.Text = math.floor(d) .. "m"
                    dist_text.Position = Vector2.new(pos.X + width/2 + 4, pos.Y)
                    dist_text.Visible = true
                else
                    dist_text.Visible = false
                end

                if getgenv().ESPTracer then
                    local screen_size = Camera.ViewportSize
                    tracer.From = Vector2.new(screen_size.X/2, screen_size.Y)
                    tracer.To = Vector2.new(pos.X, pos.Y)
                    tracer.Visible = true
                else
                    tracer.Visible = false
                end
            else
                box.Visible = false; name.Visible = false; health.Visible = false
                dist_text.Visible = false; tracer.Visible = false
            end

            RunService.RenderStepped:Wait()
        end

        -- Cleanup
        box:Remove(); name:Remove(); health:Remove(); dist_text:Remove(); tracer:Remove()
    end)
end

Players.PlayerAdded:Connect(create_esp)
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then create_esp(p) end
end

-- ============================================================
-- 7. HITBOX EXPANDER
-- ============================================================
local function apply_hitbox()
    for _, player in ipairs(Players:GetPlayers()) do
        if not is_enemy(player) then continue end
        local char = player.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        if getgenv().BS.HitboxExpander then
            hrp.Size = Vector3.new(
                getgenv().BS.HitboxSize,
                getgenv().BS.HitboxSize,
                getgenv().BS.HitboxSize
            )
            hrp.Transparency = 0.5
            hrp.CanCollide = false
        else
            hrp.Size = Vector3.new(2, 2, 1)
            hrp.Transparency = 1
            hrp.CanCollide = true
        end
    end
end

-- ============================================================
-- 8. NO RECOIL / NO SPREAD (hook em propriedades de arma)
-- ============================================================
local function apply_weapon_mods()
    if not getgenv().BS.NoRecoil and not getgenv().BS.NoSpread then return end

    local weapon = Camera:FindFirstChildOfClass("Model")
    if not weapon then return end

    for _, v in ipairs(weapon:GetDescendants()) do
        if v:IsA("NumberValue") or v:IsA("Vector3Value") then
            local n = v.Name:lower()
            if getgenv().BS.NoRecoil and (n:find("recoil") or n:find("kick")) then
                pcall(function() v.Value = 0 end)
            end
            if getgenv().BS.NoSpread and (n:find("spread") or n:find("deviation")) then
                pcall(function() v.Value = 0 end)
            end
        end
    end
end

-- ============================================================
-- 9. LOOP PRINCIPAL
-- ============================================================
setup_silent_aim()

RunService.RenderStepped:Connect(function()
    update_silent_target()
    update_aimbot()
    apply_aimbot()
    run_triggerbot()
    apply_hitbox()
    apply_weapon_mods()
end)

-- ============================================================
-- 10. UI SIMPLES (Rayfield)
-- ============================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "BloxStrike Hub",
    LoadingTitle = "Carregando...",
    LoadingSubtitle = "por Zyon",
    ConfigurationSaving = {Enabled = false},
})

local CombatTab = Window:CreateTab("Combat", nil)
local VisualsTab = Window:CreateTab("Visuals", nil)
local MiscTab = Window:CreateTab("Misc", nil)

-- Combat
CombatTab:CreateToggle({
    Name = "Aimbot (segure E)",
    CurrentValue = false,
    Flag = "Aimbot",
    Callback = function(v) getgenv().BS.Aimbot = v end,
})
CombatTab:CreateSlider({
    Name = "Aimbot FOV",
    Range = {10, 500},
    Increment = 10,
    Suffix = "px",
    CurrentValue = 120,
    Flag = "AimbotFOV",
    Callback = function(v) getgenv().BS.AimbotFOV = v end,
})
CombatTab:CreateSlider({
    Name = "Aimbot Smooth",
    Range = {0.05, 1},
    Increment = 0.05,
    Suffix = "",
    CurrentValue = 0.25,
    Flag = "AimbotSmooth",
    Callback = function(v) getgenv().BS.AimbotSmooth = v end,
})
CombatTab:CreateToggle({
    Name = "Silent Aim",
    CurrentValue = false,
    Flag = "SilentAim",
    Callback = function(v) getgenv().BS.SilentAim = v end,
})
CombatTab:CreateSlider({
    Name = "Silent FOV",
    Range = {10, 500},
    Increment = 10,
    Suffix = "px",
    CurrentValue = 150,
    Flag = "SilentFOV",
    Callback = function(v) getgenv().BS.SilentFOV = v end,
})
CombatTab:CreateToggle({
    Name = "Triggerbot",
    CurrentValue = false,
    Flag = "Triggerbot",
    Callback = function(v) getgenv().BS.Triggerbot = v end,
})

-- Visuals
VisualsTab:CreateToggle({
    Name = "ESP",
    CurrentValue = false,
    Flag = "ESP",
    Callback = function(v) getgenv().BS.ESP = v end,
})
VisualsTab:CreateToggle({
    Name = "ESP Box",
    CurrentValue = true,
    Flag = "ESPBox",
    Callback = function(v) getgenv().BS.ESPBox = v end,
})
VisualsTab:CreateToggle({
    Name = "ESP Nome",
    CurrentValue = true,
    Flag = "ESPName",
    Callback = function(v) getgenv().BS.ESPName = v end,
})
VisualsTab:CreateToggle({
    Name = "ESP Vida",
    CurrentValue = true,
    Flag = "ESPHealth",
    Callback = function(v) getgenv().BS.ESPHealth = v end,
})
VisualsTab:CreateToggle({
    Name = "ESP Distância",
    CurrentValue = true,
    Flag = "ESPDistance",
    Callback = function(v) getgenv().BS.ESPDistance = v end,
})
VisualsTab:CreateToggle({
    Name = "ESP Tracer",
    CurrentValue = false,
    Flag = "ESPTracer",
    Callback = function(v) getgenv().BS.ESPTracer = v end,
})

-- Misc
MiscTab:CreateToggle({
    Name = "Hitbox Expander",
    CurrentValue = false,
    Flag = "HitboxExpander",
    Callback = function(v) getgenv().BS.HitboxExpander = v end,
})
MiscTab:CreateSlider({
    Name = "Hitbox Tamanho",
    Range = {2, 20},
    Increment = 1,
    Suffix = "",
    CurrentValue = 7,
    Flag = "HitboxSize",
    Callback = function(v) getgenv().BS.HitboxSize = v end,
})
MiscTab:CreateToggle({
    Name = "No Recoil",
    CurrentValue = false,
    Flag = "NoRecoil",
    Callback = function(v) getgenv().BS.NoRecoil = v end,
})
MiscTab:CreateToggle({
    Name = "No Spread",
    CurrentValue = false,
    Flag = "NoSpread",
    Callback = function(v) getgenv().BS.NoSpread = v end,
})
MiscTab:CreateToggle({
    Name = "Wallbang (Silent)",
    CurrentValue = false,
    Flag = "Wallbang",
    Callback = function(v) getgenv().BS.SilentWallbang = v end,
})

Rayfield:LoadConfiguration()