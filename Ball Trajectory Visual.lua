local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- [ CẤU HÌNH MẶC ĐỊNH ]
-- ==========================================
local Config = {
    MasterEnabled = true,          -- Bật/Tắt toàn bộ Tracker
    ShowBounceVisuals = true,      -- Bật/Tắt hiển thị quỹ đạo nẩy bóng
    MinBounceRender = 2,           -- Chỉ render vị trí nẩy từ lần thứ 2 trở đi (1 = tất cả, 2 = từ lần nẩy 2)
    ShowLandingTimer = true,       -- Bật/Tắt ô vị trí rơi & đếm thời gian
    
    TrajectoryTime = 3.5,          -- Thời gian quét tối đa (giây)
    TimeStep = 0.04,               -- Độ mịn của đường vẽ
    BeamWidth = 0.35,              -- Độ rộng đường quỹ đạo
    MaxBounces = 4,                -- Số lần va chạm nẩy tối đa
    Elasticity = 0.8,              -- Hệ số nẩy của bóng (động năng)
    
    CurrentColor = Color3.fromRGB(255, 238, 0), -- Màu mặc định (Vàng)
    LobbyTeamName = "Lobby"
}

-- ==========================================
-- [ DỌN DẸP DỮ LIỆU CŨ (CLEANUP) ]
-- ==========================================
local GuiParent = (gethui and gethui()) or pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")

if GuiParent:FindFirstChild("BallTrackerUI") then GuiParent.BallTrackerUI:Destroy() end
if Workspace:FindFirstChild("TrajectoryVisuals") then Workspace.TrajectoryVisuals:Destroy() end
if _G.BallTrackerConnection then _G.BallTrackerConnection:Disconnect(); _G.BallTrackerConnection = nil end

local Folder = Instance.new("Folder")
Folder.Name = "TrajectoryVisuals"
Folder.Parent = Workspace

-- Quản lý Object Pool để tối ưu hiệu năng
local AttachmentsPool = {}
local BeamsPool = {}
local MarkersPool = {}

-- ==========================================
-- [ HÀM TÍNH TOÁN QUỸ ĐẠO & NẨY BÓNG ]
-- ==========================================
local function predictTrajectoryWithBounces(startPos, initialVel)
    local points = {}
    local impactPoints = {} -- Lưu { position, time, bounceIndex }
    
    local currentPos = startPos
    local currentVel = initialVel
    local gravity = Vector3.new(0, -Workspace.Gravity, 0)
    local totalTime = 0
    local dt = Config.TimeStep
    local bounceCount = 0
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    local ignoreList = {Folder}
    local ball = Workspace:FindFirstChild("Ball")
    if ball then table.insert(ignoreList, ball) end
    if LocalPlayer.Character then table.insert(ignoreList, LocalPlayer.Character) end
    raycastParams.FilterDescendantsInstances = ignoreList

    table.insert(points, currentPos)

    while totalTime < Config.TrajectoryTime and bounceCount < Config.MaxBounces do
        local nextPos = currentPos + currentVel * dt + 0.5 * gravity * (dt ^ 2)
        local rayResult = Workspace:Raycast(currentPos, nextPos - currentPos, raycastParams)
        
        if rayResult then
            bounceCount = bounceCount + 1
            local hitPos = rayResult.Position
            local hitNormal = rayResult.Normal
            
            local dist = (hitPos - currentPos).Magnitude
            local stepDist = (nextPos - currentPos).Magnitude
            local fraction = stepDist > 0 and (dist / stepDist) or 1
            local hitTime = totalTime + (dt * fraction)
            
            table.insert(points, hitPos)
            table.insert(impactPoints, {
                position = hitPos,
                time = hitTime,
                bounceIndex = bounceCount
            })

            -- Tính toán động năng sau va chạm (Phản xạ vận tốc)
            local velAtImpact = currentVel + gravity * (dt * fraction)
            local reflectVel = velAtImpact - 2 * velAtImpact:Dot(hitNormal) * hitNormal
            
            currentVel = reflectVel * Config.Elasticity
            currentPos = hitPos + hitNormal * 0.05 -- Tránh kẹt Raycast tại mặt phẳng
            totalTime = hitTime
        else
            currentPos = nextPos
            currentVel = currentVel + gravity * dt
            totalTime = totalTime + dt
            table.insert(points, currentPos)
        end
    end

    return points, impactPoints
end

-- ==========================================
-- [ HỆ THỐNG RENDER VISUALS ]
-- ==========================================
local function getOrCreateBeam(index)
    if not AttachmentsPool[index] then
        local att = Instance.new("Attachment")
        att.Name = "Att_" .. index
        att.Parent = Workspace.Terrain
        AttachmentsPool[index] = att
    end

    if index > 1 and not BeamsPool[index - 1] then
        local beam = Instance.new("Beam")
        beam.Name = "Beam_" .. (index - 1)
        beam.Width0 = Config.BeamWidth
        beam.Width1 = Config.BeamWidth
        beam.FaceCamera = true
        beam.Attachment0 = AttachmentsPool[index - 1]
        beam.Attachment1 = AttachmentsPool[index]
        beam.Parent = Folder
        BeamsPool[index - 1] = beam
    end

    if BeamsPool[index - 1] then
        BeamsPool[index - 1].Color = ColorSequence.new(Config.CurrentColor)
        BeamsPool[index - 1].Enabled = true
    end
end

local function getOrCreateMarker(index)
    if not MarkersPool[index] then
        local part = Instance.new("Part")
        part.Name = "ImpactMarker_" .. index
        part.Size = Vector3.new(2, 0.2, 2)
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.Parent = Folder

        local box = Instance.new("SelectionBox")
        box.Name = "Outline"
        box.Adornee = part
        box.LineThickness = 0.05
        box.Parent = part

        local bgui = Instance.new("BillboardGui")
        bgui.Name = "TimerGui"
        bgui.Size = UDim2.new(0, 100, 0, 40)
        bgui.StudsOffset = Vector3.new(0, 2.5, 0)
        bgui.AlwaysOnTop = true
        bgui.Parent = part

        local txt = Instance.new("TextLabel")
        txt.Name = "TimeTxt"
        txt.Size = UDim2.new(1, 0, 1, 0)
        txt.BackgroundTransparency = 1
        txt.Font = Enum.Font.GothamBold
        txt.TextSize = 16
        txt.TextColor3 = Color3.fromRGB(255, 255, 255)
        txt.TextStrokeTransparency = 0
        txt.Parent = bgui

        MarkersPool[index] = {Part = part, Box = box, Gui = bgui, Text = txt}
    end
    
    local item = MarkersPool[index]
    item.Part.Color = Config.CurrentColor
    item.Box.Color3 = Config.CurrentColor
    item.Part.Transparency = 0.3
    item.Part.Parent = Folder
    return item
end

local function hideAllVisuals()
    for _, beam in pairs(BeamsPool) do beam.Enabled = false end
    for _, m in pairs(MarkersPool) do m.Part.Transparency = 1; m.Gui.Enabled = false; m.Box.Adornee = nil end
end

-- ==========================================
-- [ GIAO DIỆN NGUỜI DÙNG (GUI MENU) ]
-- ==========================================
local ScreenGui = Instance.new("ScreenGui", GuiParent)
ScreenGui.Name = "BallTrackerUI"
ScreenGui.ResetOnSpawn = false

-- Nút Bật/Tắt Menu nhanh
local ToggleMenuBtn = Instance.new("TextButton", ScreenGui)
ToggleMenuBtn.Size = UDim2.new(0, 110, 0, 35)
ToggleMenuBtn.Position = UDim2.new(0.01, 0, 0.2, 0)
ToggleMenuBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
ToggleMenuBtn.Text = "⚡ Tracker Menu"
ToggleMenuBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleMenuBtn.Font = Enum.Font.GothamBold
ToggleMenuBtn.TextSize = 12
Instance.new("UICorner", ToggleMenuBtn).CornerRadius = UDim.new(0, 8)
local ToggleStroke = Instance.new("UIStroke", ToggleMenuBtn)
ToggleStroke.Color = Color3.fromRGB(255, 238, 0)
ToggleStroke.Thickness = 1.5

-- Khung Menu Chính
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 320, 0, 340)
MainFrame.Position = UDim2.new(0.08, 0, 0.2, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 0
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

-- Thêm tính năng kéo thả Menu (Draggable)
local dragging, dragStart, startPos
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = MainFrame.Position
    end
end)
MainFrame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

ToggleMenuBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Tiêu đề Menu
local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, 0, 0, 40)
Title.BackgroundTransparency = 1
Title.Text = "⚽ Ball Trajectory Controls"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14

local Layout = Instance.new("UIListLayout", MainFrame)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Padding = UDim.new(0, 8)
Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
Title.LayoutOrder = 0

-- Hàm tạo Nút Bật/Tắt (Toggle Switch)
local function createToggleButton(text, defaultState, onClick)
    local btn = Instance.new("TextButton", MainFrame)
    btn.Size = UDim2.new(0.9, 0, 0, 36)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    
    local state = defaultState
    local function updateVisual()
        if state then
            btn.BackgroundColor3 = Color3.fromRGB(46, 125, 50)
            btn.Text = text .. ": BẬT 🟢"
        else
            btn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
            btn.Text = text .. ": TẮT 🔴"
        end
    end
    
    btn.MouseButton1Click:Connect(function()
        state = not state
        updateVisual()
        onClick(state)
    end)
    
    updateVisual()
    return btn
end

-- Tạo các nút công tắc
createToggleButton("Tracker Tổng", Config.MasterEnabled, function(st) Config.MasterEnabled = st end)

local bounceBtn = createToggleButton("Quỹ Đạo Nẩy (Bounce)", Config.ShowBounceVisuals, function(st) Config.ShowBounceVisuals = st end)

local minBounceBtn = Instance.new("TextButton", MainFrame)
minBounceBtn.Size = UDim2.new(0.9, 0, 0, 32)
minBounceBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
minBounceBtn.Font = Enum.Font.GothamBold
minBounceBtn.TextSize = 11
minBounceBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
minBounceBtn.Text = "Chế độ Nẩy: Từ lần 2 trở đi 🎯"
Instance.new("UICorner", minBounceBtn).CornerRadius = UDim.new(0, 6)

minBounceBtn.MouseButton1Click:Connect(function()
    if Config.MinBounceRender == 2 then
        Config.MinBounceRender = 1
        minBounceBtn.Text = "Chế độ Nẩy: Hiển thị TẤT CẢ 🌐"
    else
        Config.MinBounceRender = 2
        minBounceBtn.Text = "Chế độ Nẩy: Từ lần 2 trở đi 🎯"
    end
end)

createToggleButton("Ô Đếm Thời Gian Rơi (ETA)", Config.ShowLandingTimer, function(st) Config.ShowLandingTimer = st end)

-- BẢNG MÀU SẮC (COLOR PALETTE)
local PaletteLabel = Instance.new("TextLabel", MainFrame)
PaletteLabel.Size = UDim2.new(0.9, 0, 0, 20)
PaletteLabel.BackgroundTransparency = 1
PaletteLabel.Text = "🎨 Bảng Màu Giao Diện:"
PaletteLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
PaletteLabel.Font = Enum.Font.GothamBold
PaletteLabel.TextSize = 11
PaletteLabel.TextXAlignment = Enum.TextXAlignment.Left

local PaletteFrame = Instance.new("Frame", MainFrame)
PaletteFrame.Size = UDim2.new(0.9, 0, 0, 35)
PaletteFrame.BackgroundTransparency = 1
local PaletteLayout = Instance.new("UIGridLayout", PaletteFrame)
PaletteLayout.CellSize = UDim2.new(0, 38, 0, 32)
PaletteLayout.CellPadding = UDim2.new(0, 8, 0, 0)

local ColorsList = {
    Color3.fromRGB(255, 238, 0), -- Vàng
    Color3.fromRGB(0, 255, 255), -- Cyan Neon
    Color3.fromRGB(0, 255, 128), -- Lá Neon
    Color3.fromRGB(255, 60, 60),  -- Đỏ
    Color3.fromRGB(220, 80, 255),-- Tím Hồng
    Color3.fromRGB(255, 255, 255)-- Trắng
}

for _, color in ipairs(ColorsList) do
    local cBtn = Instance.new("TextButton", PaletteFrame)
    cBtn.BackgroundColor3 = color
    cBtn.Text = ""
    Instance.new("UICorner", cBtn).CornerRadius = UDim.new(0, 6)
    cBtn.MouseButton1Click:Connect(function()
        Config.CurrentColor = color
        ToggleStroke.Color = color
    end)
end

-- ==========================================
-- [ VÒNG LẶP CẬP NHẬT (RENDERSTEPPED) ]
-- ==========================================
_G.BallTrackerConnection = RunService.RenderStepped:Connect(function()
    -- 1. Kiểm tra tính năng Master & Team Sảnh
    if not Config.MasterEnabled or (LocalPlayer.Team and LocalPlayer.Team.Name == Config.LobbyTeamName) then
        hideAllVisuals()
        return
    end

    local ball = Workspace:FindFirstChild("Ball")
    if not ball or not ball:IsDescendantOf(Workspace) then
        hideAllVisuals()
        return
    end

    -- 2. Tính toán quỹ đạo đường đi & vị trí va chạm
    local points, impacts = predictTrajectoryWithBounces(ball.Position, ball.AssemblyLinearVelocity)

    -- 3. Render Đường Quỹ Đạo (Beams)
    local beamIndex = 1
    for i = 1, #points do
        -- Nếu tắt tính năng nẩy, chỉ render đoạn quỹ đạo đầu tiên (trước khi va chạm lần 1)
        if not Config.ShowBounceVisuals and #impacts > 0 and i > 2 then
            local firstImpactTime = impacts[1].time / Config.TimeStep
            if i > math.ceil(firstImpactTime) then break end
        end

        getOrCreateBeam(beamIndex)
        AttachmentsPool[beamIndex].WorldPosition = points[i]
        beamIndex = beamIndex + 1
    end

    -- Ẩn các Beam thừa
    for i = beamIndex, #AttachmentsPool do
        if AttachmentsPool[i] then AttachmentsPool[i].WorldPosition = Vector3.new(0, -1000, 0) end
        if BeamsPool[i - 1] then BeamsPool[i - 1].Enabled = false end
    end

    -- 4. Render Ô Vị Trí Rơi & Đồng Hồ Đếm Ngược (ETA Timer)
    local markerIdx = 1
    for _, impact in ipairs(impacts) do
        -- Lọc vị trí nẩy (Ví dụ: Chỉ render từ lần nẩy thứ 2 trở đi theo yêu cầu)
        if impact.bounceIndex >= Config.MinBounceRender then
            if Config.ShowLandingTimer then
                local marker = getOrCreateMarker(markerIdx)
                marker.Part.Position = impact.position
                marker.Box.Adornee = marker.Part
                marker.Gui.Enabled = true
                marker.Text.Text = string.format("⏱️ %.2fs", impact.time)
                markerIdx = markerIdx + 1
            end
        end
    end

    -- Ẩn các Marker thừa
    for i = markerIdx, #MarkersPool do
        MarkersPool[i].Part.Transparency = 1
        MarkersPool[i].Gui.Enabled = false
        MarkersPool[i].Box.Adornee = nil
    end
end)
