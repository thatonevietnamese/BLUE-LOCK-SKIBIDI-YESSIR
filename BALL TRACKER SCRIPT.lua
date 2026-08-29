-- ==========================================
-- BALL TRACKER SCRIPT (THÊM CHẾ ĐỘ LOBBY & INTERMISSION)
-- ==========================================
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- 1. TẠO UI (GIAO DIỆN)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BallTrackerUI"
ScreenGui.Parent = RunService:IsStudio() and LocalPlayer:WaitForChild("PlayerGui") or CoreGui

-- Kéo dài giao diện lên 320 để vừa chữ INTERMISSION=)
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 320, 0, 120)
MainFrame.Position = UDim2.new(0.5, -160, 0, 20)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.BorderSizePixel = 2
MainFrame.BorderColor3 = Color3.fromRGB(0, 170, 255)
MainFrame.Active = true
MainFrame.Draggable = true

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, 0, 0, 25)
Title.BackgroundTransparency = 1
Title.Text = "Ball Tracker"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold 
Title.TextSize = 16

-- Ô 1: Trạng thái bóng
local DisplayStatus = Instance.new("TextLabel", MainFrame)
DisplayStatus.Size = UDim2.new(0, 160, 0, 40)
DisplayStatus.Position = UDim2.new(0, 10, 0, 30)
DisplayStatus.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
DisplayStatus.TextColor3 = Color3.fromRGB(255, 50, 50)
DisplayStatus.Text = "Status: FALSE"
DisplayStatus.Font = Enum.Font.SourceSansBold
DisplayStatus.TextSize = 20

-- Ô 2: Ai cầm bóng (1 / 0)
local IndicatorBox = Instance.new("TextLabel", MainFrame)
IndicatorBox.Size = UDim2.new(0, 60, 0, 40)
IndicatorBox.Position = UDim2.new(0, 180, 0, 30)
IndicatorBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
IndicatorBox.TextColor3 = Color3.fromRGB(150, 150, 150)
IndicatorBox.Text = "-"
IndicatorBox.Font = Enum.Font.GothamBold
IndicatorBox.TextSize = 20

-- Ô 3: Đồng đội cầm bóng? (YES / NO)
local TeamBox = Instance.new("TextLabel", MainFrame)
TeamBox.Size = UDim2.new(0, 60, 0, 40)
TeamBox.Position = UDim2.new(0, 250, 0, 30)
TeamBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
TeamBox.TextColor3 = Color3.fromRGB(150, 150, 150)
TeamBox.Text = "-"
TeamBox.Font = Enum.Font.GothamBold
TeamBox.TextSize = 18

-- Ô nhập tốc độ quét
local FrequencyInput = Instance.new("TextBox", MainFrame)
FrequencyInput.Size = UDim2.new(1, -20, 0, 30)
FrequencyInput.Position = UDim2.new(0, 10, 0, 80)
FrequencyInput.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
FrequencyInput.TextColor3 = Color3.fromRGB(255, 255, 255)
FrequencyInput.Text = "0.5" 
FrequencyInput.PlaceholderText = "Nhập tần suất (giây)"
FrequencyInput.Font = Enum.Font.SourceSans
FrequencyInput.TextSize = 16

-- 2. LOGIC QUÉT
local scanFrequency = 0.5 

FrequencyInput.FocusLost:Connect(function()
    local num = tonumber(FrequencyInput.Text)
    if num and num >= 0.01 then
        scanFrequency = num
    else
        FrequencyInput.Text = tostring(scanFrequency)
    end
end)

-- Hàm kiểm tra trạng thái Lobby và Bóng
local function CheckBallOnPlayers()
    local playersInMatch = 0
    local localPlayerInMatch = false
    
    -- Bước 1: Quét xem có ai đang đá không (thuộc team Home hoặc Away)
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Team then
            local teamName = string.lower(player.Team.Name)
            if string.match(teamName, "home") or string.match(teamName, "away") then
                playersInMatch = playersInMatch + 1
                if player == LocalPlayer then
                    localPlayerInMatch = true
                end
            end
        end
    end
    
    -- Nếu không có ai trong đội Home/Away -> Tất cả đang ở Lobby (Nghỉ giải lao)
    if playersInMatch == 0 then
        return "INTERMISSION", "-", "-"
    end
    
    -- Nếu có người đang đá, nhưng bạn đang không ở team Home/Away (Bạn ở Lobby)
    if not localPlayerInMatch then
        return "NONE", "-", "-"
    end

    -- Bước 2: Quét tìm bóng (chỉ chạy khi bạn đang đá)
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Team then
            local teamName = string.lower(player.Team.Name)
            if string.match(teamName, "home") or string.match(teamName, "away") then
                local char = player.Character
                if char then
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") and string.lower(part.Name) == "ball" and part.Material == Enum.Material.Plastic then
                            
                            local isSameTeam = (player.Team == LocalPlayer.Team) and "YES" or "NO"
                            
                            if player == LocalPlayer then
                                return "TRUE", "1", "YES" -- Bản thân cầm
                            else
                                return "TRUE", "0", isSameTeam -- Người khác cầm
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Trận đấu đang diễn ra, bạn đang đá, nhưng không ai giữ bóng
    return "FALSE", "-", "-" 
end

-- 3. VÒNG LẶP CHẠY LIÊN TỤC
task.spawn(function()
    while task.wait(scanFrequency) do
        local status, holderIndicator, sameTeamStatus = CheckBallOnPlayers()
        
        -- Cập nhật Trạng thái (INTERMISSION / NONE / TRUE / FALSE)
        if status == "INTERMISSION" then
            DisplayStatus.Text = "INTERMISSION=)"
            DisplayStatus.TextColor3 = Color3.fromRGB(255, 215, 0) -- Màu vàng Gold
        elseif status == "NONE" then
            DisplayStatus.Text = "Status: NONE"
            DisplayStatus.TextColor3 = Color3.fromRGB(150, 150, 150) -- Màu xám
        elseif status == "TRUE" then
            DisplayStatus.Text = "Status: TRUE"
            DisplayStatus.TextColor3 = Color3.fromRGB(50, 255, 50) -- Màu xanh lá
        elseif status == "FALSE" then
            DisplayStatus.Text = "Status: FALSE"
            DisplayStatus.TextColor3 = Color3.fromRGB(255, 50, 50) -- Màu đỏ
        end
        
        -- Cập nhật ô số 1 / 0 / -
        IndicatorBox.Text = holderIndicator
        if holderIndicator == "1" then
            IndicatorBox.TextColor3 = Color3.fromRGB(0, 255, 255) 
        elseif holderIndicator == "0" then
            IndicatorBox.TextColor3 = Color3.fromRGB(255, 170, 0) 
        else
            IndicatorBox.TextColor3 = Color3.fromRGB(150, 150, 150) 
        end
        
        -- Cập nhật ô YES / NO / -
        TeamBox.Text = sameTeamStatus
        if sameTeamStatus == "YES" then
            TeamBox.TextColor3 = Color3.fromRGB(50, 255, 50) 
        elseif sameTeamStatus == "NO" then
            TeamBox.TextColor3 = Color3.fromRGB(255, 50, 50) 
        else
            TeamBox.TextColor3 = Color3.fromRGB(150, 150, 150) 
        end
    end
end)
