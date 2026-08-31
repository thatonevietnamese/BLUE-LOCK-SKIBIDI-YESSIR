local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- [ CẤU HÌNH HỆ THỐNG ]
-- ==========================================
local Config = {
    MasterEnabled = true,
    DrawAllBounces = false,
    
    TrajectoryTime = 6.0,    -- Thời gian dự đoán tối đa (giây)
    TimeStep = 0.03,         -- Độ mịn vạch vẽ
    BeamWidth = 0.35,        
    MaxBounces = 4,          
    Elasticity = 0.75,       -- Độ nảy bóng (0.75 = 75%)
    
    CurrentColor = Color3.fromRGB(0, 255, 238)
}

-- ==========================================
-- [ KHỞI TẠO BIẾN & CACHE ]
-- ==========================================
local cachedPoints = {}

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.RespectCanCollide = true 

local cachedBall = nil
local lastBallCheck = 0

-- Biến theo dõi vị trí thực tế để tự tính vận tốc
local lastBallPos = nil
local lastBallTime = 0
local calculatedVelocity = Vector3.zero

-- ==========================================
-- [ QUẢN LÝ THƯ MỤC & POOLING ]
-- ==========================================
local GuiParent = (gethui and gethui()) or (pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui")) or LocalPlayer:WaitForChild("PlayerGui")

if GuiParent:FindFirstChild("BallTrackerUI") then GuiParent.BallTrackerUI:Destroy() end
if _G.BallTrackerConnection then _G.BallTrackerConnection:Disconnect(); _G.BallTrackerConnection = nil end

local function getVisualFolder()
    local folder = Workspace:FindFirstChild("TrajectoryVisuals")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "TrajectoryVisuals"
        folder.Parent = Workspace
    end
    return folder
end

local AttachmentsPool = {}
local BeamsPool = {}

local function clearAndHideAll()
    for _, beam in pairs(BeamsPool) do
        if beam and beam.Parent then beam.Enabled = false end
    end
end

-- ==========================================
-- [ LOGIC TÌM BÓNG & TRÍCH XUẤT VẬN TỐC ]
-- ==========================================
local function getActiveBall()
    if cachedBall and cachedBall.Parent and cachedBall:IsDescendantOf(Workspace) then
        return cachedBall
    end
    
    cachedBall = nil 
    local now = os.clock()
    if now - lastBallCheck < 0.3 then return nil end 
    lastBallCheck = now
    
    local possibleNames = {"Ball", "SoccerBall", "Football", "TPSBall", "TpsBall"}
    for _, name in ipairs(possibleNames) do
        local b = Workspace:FindFirstChild(name, true)
        if b and b:IsA("BasePart") and b:IsDescendantOf(Workspace) then
            cachedBall = b
            return b
        end
    end
    return nil
end

local function getEffectiveVelocity(ball)
    local now = os.clock()
    local currentPos = ball.Position
    
    -- 1. Tự tính vận tốc thực qua biến thiên vị trí
    if lastBallPos and (now - lastBallTime) > 0 then
        local realDt = now - lastBallTime
        if realDt < 0.2 then
            calculatedVelocity = (currentPos - lastBallPos) / realDt
        end
    end
    lastBallPos = currentPos
    lastBallTime = now

    -- 2. Đọc AssemblyLinearVelocity gốc
    local physVel = ball.AssemblyLinearVelocity
    if physVel and physVel.Magnitude > 1.5 then
        return physVel
    end

    -- 3. Đọc từ BodyVelocity / LinearVelocity
    local bv = ball:FindFirstChildOfClass("BodyVelocity")
    if bv and bv.Velocity.Magnitude > 1.5 then
        return bv.Velocity
    end
    
    local lv = ball:FindFirstChildOfClass("LinearVelocity")
    if lv and lv.VectorVelocity.Magnitude > 1.5 then
        return lv.VectorVelocity
    end

    -- 4. Trả về vận tốc tự tính
    if calculatedVelocity.Magnitude > 1.5 then
        return calculatedVelocity
    end

    return Vector3.zero
end

-- ==========================================
-- [ CẬP NHẬT BỘ LỌC VA CHẠM ]
-- ==========================================
local function updateRaycastFilter(ball)
    local ignoreList = {getVisualFolder(), ball}
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(ignoreList, player.Character)
        end
    end
    
    if ball.Parent and ball.Parent:IsA("Model") then 
        table.insert(ignoreList, ball.Parent) 
    end
    
    raycastParams.FilterDescendantsInstances = ignoreList
end

-- ==========================================
-- [ THUẬT TOÁN DỰ ĐOÁN QUỸ ĐẠO BẢO TOÀN ]
-- ==========================================
local function predictTrajectory(ball)
    table.clear(cachedPoints)
    local firstImpactIndex = -1
    
    local currentVel = getEffectiveVelocity(ball)
    
    if currentVel.Magnitude < 1.2 then 
        return cachedPoints, firstImpactIndex 
    end
    
    local currentPos = ball.Position
    local gravityVal = Workspace.Gravity > 0 and Workspace.Gravity or 196.2
    local gravity = Vector3.new(0, -gravityVal, 0)
    
    local totalTime = 0
    local stepDt = Config.TimeStep
    local bounceCount = 0
    
    table.insert(cachedPoints, currentPos)

    while totalTime < Config.TrajectoryTime and bounceCount < Config.MaxBounces do
        local nextPos = currentPos + (currentVel * stepDt) + (0.5 * gravity * (stepDt ^ 2))
        local dir = nextPos - currentPos
        
        local rayResult = Workspace:Raycast(currentPos, dir, raycastParams)
        
        if rayResult then
            bounceCount = bounceCount + 1
            local hitPos = rayResult.Position
            local hitNormal = rayResult.Normal
            
            local stepDist = dir.Magnitude
            local actualDist = (hitPos - currentPos).Magnitude
            local fraction = stepDist > 0 and (actualDist / stepDist) or 1
            
            table.insert(cachedPoints, hitPos)
            if bounceCount == 1 then 
                firstImpactIndex = #cachedPoints 
            end
            
            local velAtImpact = currentVel + (gravity * (stepDt * fraction))
            currentVel = (velAtImpact - (2 * velAtImpact:Dot(hitNormal) * hitNormal)) * Config.Elasticity
            
            currentPos = hitPos + (hitNormal * 0.08)
            totalTime = totalTime + (stepDt * fraction)
            
            if currentVel.Magnitude < 1.5 then break end
        else
            currentPos = nextPos
            currentVel = currentVel + (gravity * stepDt)
            totalTime = totalTime + stepDt
            table.insert(cachedPoints, currentPos)
        end
    end

    -- Bổ sung: Rọi tia thẳng xuống đất làm điểm cuối cho đường Beam nếu bóng đang lơ lửng
    if bounceCount == 0 and #cachedPoints > 0 then
        local lastPoint = cachedPoints[#cachedPoints]
        local downRay = Workspace:Raycast(lastPoint, Vector3.new(0, -500, 0), raycastParams)
        
        if downRay then
            table.insert(cachedPoints, downRay.Position)
            firstImpactIndex = #cachedPoints
        end
    end

    return cachedPoints, firstImpactIndex
end

-- ==========================================
-- [ OBJECT POOLING VISUALS ]
-- ==========================================
local function getOrCreateBeam(index)
    local targetFolder = getVisualFolder()
    
    if AttachmentsPool[index] and not AttachmentsPool[index].Parent then AttachmentsPool[index] = nil end
    if index > 1 and BeamsPool[index - 1] and not BeamsPool[index - 1].Parent then BeamsPool[index - 1] = nil end

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
        beam.Parent = targetFolder
        BeamsPool[index - 1] = beam
    end

    if BeamsPool[index - 1] then
        BeamsPool[index - 1].Color = ColorSequence.new(Config.CurrentColor)
        BeamsPool[index - 1].Enabled = true
    end
end

-- ==========================================
-- [ RENDER LOOP ]
-- ==========================================
local function renderLoop()
    if not Config.MasterEnabled then 
        clearAndHideAll()
        return 
    end

    local ball = getActiveBall()
    if not ball then 
        clearAndHideAll()
        return 
    end

    updateRaycastFilter(ball)
    
    local points, firstImpactIdx = predictTrajectory(ball)
    if #points == 0 then clearAndHideAll(); return end

    -- Render Beams
    local beamIdx = 1
    local maxPointIdx = Config.DrawAllBounces and #points or (firstImpactIdx > 0 and firstImpactIdx or #points)

    for i = 1, maxPointIdx do
        if points[i] then
            getOrCreateBeam(beamIdx)
            if AttachmentsPool[beamIdx] then AttachmentsPool[beamIdx].WorldPosition = points[i] end
            beamIdx = beamIdx + 1
        end
    end

    for i = beamIdx, #AttachmentsPool do
        if AttachmentsPool[i] and AttachmentsPool[i].Parent then AttachmentsPool[i].WorldPosition = Vector3.new(0, -1000, 0) end
        if BeamsPool[i - 1] and BeamsPool[i - 1].Parent then BeamsPool[i - 1].Enabled = false end
    end
end

_G.BallTrackerConnection = RunService.RenderStepped:Connect(renderLoop)

-- ==========================================
-- [ GIAO DIỆN NGƯỜI DÙNG (UI) ]
-- ==========================================
local ScreenGui = Instance.new("ScreenGui", GuiParent)
ScreenGui.Name = "BallTrackerUI"
ScreenGui.ResetOnSpawn = false

local ToggleMenuBtn = Instance.new("TextButton", ScreenGui)
ToggleMenuBtn.Size = UDim2.new(0, 120, 0, 35)
ToggleMenuBtn.Position = UDim2.new(0.01, 0, 0.18, 0)
ToggleMenuBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
ToggleMenuBtn.Text = "⚡ Tracker Menu"
ToggleMenuBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleMenuBtn.Font = Enum.Font.GothamBold
ToggleMenuBtn.TextSize = 12
Instance.new("UICorner", ToggleMenuBtn).CornerRadius = UDim.new(0, 8)
local ToggleStroke = Instance.new("UIStroke", ToggleMenuBtn)
ToggleStroke.Color = Config.CurrentColor
ToggleStroke.Thickness = 1.5

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 310, 0, 260)
MainFrame.Position = UDim2.new(0.08, 0, 0.18, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
MainFrame.BorderSizePixel = 0
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
MainFrame.Visible = false

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

ToggleMenuBtn.MouseButton1Click:Connect(function() MainFrame.Visible = not MainFrame.Visible end)

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, 0, 0, 38)
Title.BackgroundTransparency = 1
Title.Text = "⚽ Ball Trajectory Manager"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13

local Layout = Instance.new("UIListLayout", MainFrame)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Padding = UDim.new(0, 7)
Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local function createToggle(text, defaultState, onClick)
    local btn = Instance.new("TextButton", MainFrame)
    btn.Size = UDim2.new(0.92, 0, 0, 34)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    
    local state = defaultState
    local function updateVisual()
        if state then
            btn.BackgroundColor3 = Color3.fromRGB(40, 140, 60)
            btn.Text = text .. ": BẬT 🟢"
        else
            btn.BackgroundColor3 = Color3.fromRGB(160, 45, 45)
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

createToggle("Công Tắc Tracker Tổng", Config.MasterEnabled, function(st) Config.MasterEnabled = st end)

local bounceModeBtn = Instance.new("TextButton", MainFrame)
bounceModeBtn.Size = UDim2.new(0.92, 0, 0, 32)
bounceModeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
bounceModeBtn.Font = Enum.Font.GothamBold
bounceModeBtn.TextSize = 11
bounceModeBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
bounceModeBtn.Text = Config.DrawAllBounces and "Quỹ Đạo: VẼ TẤT CẢ CÁC ĐIỂM 🌐" or "Quỹ Đạo: CHỈ ĐIỂM RƠI ĐẦU 🎯"
Instance.new("UICorner", bounceModeBtn).CornerRadius = UDim.new(0, 6)

bounceModeBtn.MouseButton1Click:Connect(function()
    Config.DrawAllBounces = not Config.DrawAllBounces
    if Config.DrawAllBounces then
        bounceModeBtn.Text = "Quỹ Đạo: VẼ TẤT CẢ CÁC ĐIỂM 🌐"
    else
        bounceModeBtn.Text = "Quỹ Đạo: CHỈ ĐIỂM RƠI ĐẦU 🎯"
    end
    clearAndHideAll()
end)

local PaletteLabel = Instance.new("TextLabel", MainFrame)
PaletteLabel.Size = UDim2.new(0.92, 0, 0, 18)
PaletteLabel.BackgroundTransparency = 1
PaletteLabel.Text = "🎨 Chọn Màu Giao Diện:"
PaletteLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
PaletteLabel.Font = Enum.Font.GothamBold
PaletteLabel.TextSize = 11
PaletteLabel.TextXAlignment = Enum.TextXAlignment.Left

local PaletteFrame = Instance.new("Frame", MainFrame)
PaletteFrame.Size = UDim2.new(0.92, 0, 0, 32)
PaletteFrame.BackgroundTransparency = 1
local PaletteLayout = Instance.new("UIGridLayout", PaletteFrame)
PaletteLayout.CellSize = UDim2.new(0, 38, 0, 30)
PaletteLayout.CellPadding = UDim2.new(0, 7, 0, 0)

local ColorsList = {
    Color3.fromRGB(0, 255, 238), Color3.fromRGB(255, 238, 0), Color3.fromRGB(0, 255, 100),
    Color3.fromRGB(255, 50, 80), Color3.fromRGB(200, 70, 255), Color3.fromRGB(255, 255, 255)
}

for _, color in ipairs(ColorsList) do
    local cBtn = Instance.new("TextButton", PaletteFrame)
    cBtn.BackgroundColor3 = color
    cBtn.Text = ""
    Instance.new("UICorner", cBtn).CornerRadius = UDim.new(0, 5)
    cBtn.MouseButton1Click:Connect(function() Config.CurrentColor = color; ToggleStroke.Color = color end)
end
