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

    TrajectoryTime = 6.0,
    TimeStep = 0.03,
    BeamWidth = 0.35,
    MaxBounces = 4,
    Elasticity = 0.75,

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

local lastBallPos = nil
local lastBallTime = 0
local calculatedVelocity = Vector3.zero

-- Trạng thái Lobby
local isInLobby = false

-- ==========================================
-- [ QUẢN LÝ GUI / CONNECTION CŨ ]
-- ==========================================
local GuiParent =
    (gethui and gethui())
    or (pcall(function()
        return game:GetService("CoreGui")
    end) and game:GetService("CoreGui"))
    or LocalPlayer:WaitForChild("PlayerGui")

if GuiParent:FindFirstChild("BallTrackerUI") then
    GuiParent.BallTrackerUI:Destroy()
end

if _G.BallTrackerConnection then
    _G.BallTrackerConnection:Disconnect()
    _G.BallTrackerConnection = nil
end

if _G.BallTrackerTeamConnection then
    _G.BallTrackerTeamConnection:Disconnect()
    _G.BallTrackerTeamConnection = nil
end

-- ==========================================
-- [ VISUAL FOLDER ]
-- ==========================================
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

-- ==========================================
-- [ CLEAR TOÀN BỘ TRAJECTORY ]
-- ==========================================
local function clearAndHideAll()
    -- Tắt toàn bộ beam
    for _, beam in pairs(BeamsPool) do
        if beam and beam.Parent then
            beam.Enabled = false
        end
    end

    -- Đưa attachment xuống rất sâu để tránh còn thấy visual
    for _, attachment in pairs(AttachmentsPool) do
        if attachment and attachment.Parent then
            attachment.WorldPosition = Vector3.new(0, -10000, 0)
        end
    end

    table.clear(cachedPoints)

    cachedBall = nil
    lastBallCheck = 0

    lastBallPos = nil
    lastBallTime = 0
    calculatedVelocity = Vector3.zero
end

-- ==========================================
-- [ KIỂM TRA LOBBY ]
-- ==========================================
local function isLobbyTeam()
    local team = LocalPlayer.Team

    if not team then
        return false
    end

    return team.Name:lower() == "lobby"
end

local function updateLobbyState()
    local lobby = isLobbyTeam()

    if lobby ~= isInLobby then
        isInLobby = lobby

        if isInLobby then
            clearAndHideAll()
        else
            -- Khi rời Lobby thì reset hoàn toàn tracker
            clearAndHideAll()
        end
    end

    return isInLobby
end

-- ==========================================
-- [ LOGIC TÌM BÓNG ]
-- ==========================================
local function getActiveBall()
    if cachedBall
        and cachedBall.Parent
        and cachedBall:IsDescendantOf(Workspace)
        and cachedBall:IsA("BasePart")
    then
        return cachedBall
    end

    cachedBall = nil

    local now = os.clock()

    if now - lastBallCheck < 0.3 then
        return nil
    end

    lastBallCheck = now

    local possibleNames = {
        "Ball",
        "SoccerBall",
        "Football",
        "TPSBall",
        "TpsBall"
    }

    for _, name in ipairs(possibleNames) do
        local b = Workspace:FindFirstChild(name, true)

        if b
            and b:IsA("BasePart")
            and b:IsDescendantOf(Workspace)
        then
            cachedBall = b
            return b
        end
    end

    return nil
end

-- ==========================================
-- [ TRÍCH XUẤT VẬN TỐC ]
-- ==========================================
local function getEffectiveVelocity(ball)
    local now = os.clock()
    local currentPos = ball.Position

    -- 1. Tự tính vận tốc từ vị trí thực tế
    if lastBallPos and (now - lastBallTime) > 0 then
        local realDt = now - lastBallTime

        if realDt < 0.2 then
            calculatedVelocity = (currentPos - lastBallPos) / realDt
        end
    end

    lastBallPos = currentPos
    lastBallTime = now

    -- 2. AssemblyLinearVelocity
    local physVel = ball.AssemblyLinearVelocity

    if physVel and physVel.Magnitude > 1.5 then
        return physVel
    end

    -- 3. BodyVelocity
    local bv = ball:FindFirstChildOfClass("BodyVelocity")

    if bv and bv.Velocity.Magnitude > 1.5 then
        return bv.Velocity
    end

    -- 4. LinearVelocity
    local lv = ball:FindFirstChildOfClass("LinearVelocity")

    if lv and lv.VectorVelocity.Magnitude > 1.5 then
        return lv.VectorVelocity
    end

    -- 5. Velocity tự tính
    if calculatedVelocity.Magnitude > 1.5 then
        return calculatedVelocity
    end

    return Vector3.zero
end

-- ==========================================
-- [ CẬP NHẬT RAYCAST FILTER ]
-- ==========================================
local function updateRaycastFilter(ball)
    local ignoreList = {
        getVisualFolder(),
        ball
    }

    -- Ignore player characters
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(ignoreList, player.Character)
        end
    end

    -- Ignore model chứa ball
    if ball.Parent and ball.Parent:IsA("Model") then
        table.insert(ignoreList, ball.Parent)
    end

    raycastParams.FilterDescendantsInstances = ignoreList
end

-- ==========================================
-- [ THUẬT TOÁN DỰ ĐOÁN QUỸ ĐẠO ]
-- ==========================================
local function predictTrajectory(ball)
    table.clear(cachedPoints)

    local firstImpactIndex = -1
    local currentVel = getEffectiveVelocity(ball)

    if currentVel.Magnitude < 1.2 then
        return cachedPoints, firstImpactIndex
    end

    local currentPos = ball.Position

    local gravityVal =
        Workspace.Gravity > 0
        and Workspace.Gravity
        or 196.2

    local gravity = Vector3.new(0, -gravityVal, 0)

    local totalTime = 0
    local stepDt = Config.TimeStep
    local bounceCount = 0

    table.insert(cachedPoints, currentPos)

    while totalTime < Config.TrajectoryTime
        and bounceCount < Config.MaxBounces
    do
        local nextPos =
            currentPos
            + (currentVel * stepDt)
            + (0.5 * gravity * (stepDt ^ 2))

        local dir = nextPos - currentPos

        local rayResult =
            Workspace:Raycast(
                currentPos,
                dir,
                raycastParams
            )

        if rayResult then
            bounceCount += 1

            local hitPos = rayResult.Position
            local hitNormal = rayResult.Normal

            local stepDist = dir.Magnitude
            local actualDist = (hitPos - currentPos).Magnitude

            local fraction =
                stepDist > 0
                and (actualDist / stepDist)
                or 1

            table.insert(cachedPoints, hitPos)

            if bounceCount == 1 then
                firstImpactIndex = #cachedPoints
            end

            local velAtImpact =
                currentVel
                + (gravity * (stepDt * fraction))

            currentVel =
                (
                    velAtImpact
                    - (
                        2
                        * velAtImpact:Dot(hitNormal)
                        * hitNormal
                    )
                )
                * Config.Elasticity

            currentPos =
                hitPos
                + (hitNormal * 0.08)

            totalTime =
                totalTime
                + (stepDt * fraction)

            if currentVel.Magnitude < 1.5 then
                break
            end
        else
            currentPos = nextPos

            currentVel =
                currentVel
                + (gravity * stepDt)

            totalTime =
                totalTime
                + stepDt

            table.insert(cachedPoints, currentPos)
        end
    end

    -- ==========================================
    -- [ RAY XUỐNG ĐẤT ]
    -- ==========================================
    if bounceCount == 0 and #cachedPoints > 0 then
        local lastPoint = cachedPoints[#cachedPoints]

        local downRay =
            Workspace:Raycast(
                lastPoint,
                Vector3.new(0, -500, 0),
                raycastParams
            )

        if downRay then
            table.insert(cachedPoints, downRay.Position)
            firstImpactIndex = #cachedPoints
        end
    end

    return cachedPoints, firstImpactIndex
end

-- ==========================================
-- [ OBJECT POOLING ]
-- ==========================================
local function getOrCreateBeam(index)
    local targetFolder = getVisualFolder()

    if AttachmentsPool[index]
        and not AttachmentsPool[index].Parent
    then
        AttachmentsPool[index] = nil
    end

    if index > 1
        and BeamsPool[index - 1]
        and not BeamsPool[index - 1].Parent
    then
        BeamsPool[index - 1] = nil
    end

    -- Tạo Attachment
    if not AttachmentsPool[index] then
        local att = Instance.new("Attachment")
        att.Name = "Att_" .. index
        att.Parent = Workspace.Terrain

        AttachmentsPool[index] = att
    end

    -- Tạo Beam
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

    -- Update beam
    if BeamsPool[index - 1] then
        local beam = BeamsPool[index - 1]

        beam.Color =
            ColorSequence.new(Config.CurrentColor)

        beam.Width0 = Config.BeamWidth
        beam.Width1 = Config.BeamWidth

        beam.Enabled = true
    end
end

-- ==========================================
-- [ RENDER LOOP ]
-- ==========================================
local function renderLoop()
    -- Lobby => không render gì
    if updateLobbyState() then
        clearAndHideAll()
        return
    end

    -- Master OFF
    if not Config.MasterEnabled then
        clearAndHideAll()
        return
    end

    -- Tìm bóng
    local ball = getActiveBall()

    if not ball then
        clearAndHideAll()
        return
    end

    -- Raycast filter
    updateRaycastFilter(ball)

    -- Dự đoán quỹ đạo
    local points, firstImpactIdx =
        predictTrajectory(ball)

    if #points == 0 then
        clearAndHideAll()
        return
    end

    -- ==========================================
    -- [ RENDER BEAMS ]
    -- ==========================================
    local beamIdx = 1

    local maxPointIdx

    if Config.DrawAllBounces then
        maxPointIdx = #points
    else
        if firstImpactIdx > 0 then
            maxPointIdx = firstImpactIdx
        else
            maxPointIdx = #points
        end
    end

    for i = 1, maxPointIdx do
        if points[i] then
            getOrCreateBeam(beamIdx)

            if AttachmentsPool[beamIdx] then
                AttachmentsPool[beamIdx].WorldPosition =
                    points[i]
            end

            beamIdx += 1
        end
    end

    -- ==========================================
    -- [ HIDE BEAM DƯ ]
    -- ==========================================
    for i = beamIdx, #AttachmentsPool do
        if AttachmentsPool[i]
            and AttachmentsPool[i].Parent
        then
            AttachmentsPool[i].WorldPosition =
                Vector3.new(0, -10000, 0)
        end

        if BeamsPool[i - 1]
            and BeamsPool[i - 1].Parent
        then
            BeamsPool[i - 1].Enabled = false
        end
    end
end

-- ==========================================
-- [ TEAM CHANGE - CLEAN NGAY LẬP TỨC ]
-- ==========================================
_G.BallTrackerTeamConnection =
    LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()

        local nowLobby = isLobbyTeam()

        if nowLobby then
            isInLobby = true
            clearAndHideAll()
        else
            isInLobby = false
            clearAndHideAll()
        end
    end)

-- Đồng bộ trạng thái ban đầu
isInLobby = isLobbyTeam()

if isInLobby then
    clearAndHideAll()
end

-- ==========================================
-- [ START RENDER ]
-- ==========================================
_G.BallTrackerConnection =
    RunService.RenderStepped:Connect(renderLoop)

-- ==========================================
-- [ GIAO DIỆN NGƯỜI DÙNG ]
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BallTrackerUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

-- ==========================================
-- [ MENU BUTTON ]
-- ==========================================
local ToggleMenuBtn = Instance.new("TextButton")
ToggleMenuBtn.Parent = ScreenGui

ToggleMenuBtn.Size =
    UDim2.new(0, 120, 0, 35)

ToggleMenuBtn.Position =
    UDim2.new(0.01, 0, 0.18, 0)

ToggleMenuBtn.BackgroundColor3 =
    Color3.fromRGB(25, 25, 30)

ToggleMenuBtn.Text = "⚡ Tracker Menu"

ToggleMenuBtn.TextColor3 =
    Color3.fromRGB(255, 255, 255)

ToggleMenuBtn.Font =
    Enum.Font.GothamBold

ToggleMenuBtn.TextSize = 12

Instance.new("UICorner", ToggleMenuBtn)
    .CornerRadius = UDim.new(0, 8)

local ToggleStroke =
    Instance.new("UIStroke", ToggleMenuBtn)

ToggleStroke.Color =
    Config.CurrentColor

ToggleStroke.Thickness = 1.5

-- ==========================================
-- [ MAIN FRAME ]
-- ==========================================
local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui

MainFrame.Size =
    UDim2.new(0, 310, 0, 260)

MainFrame.Position =
    UDim2.new(0.08, 0, 0.18, 0)

MainFrame.BackgroundColor3 =
    Color3.fromRGB(20, 20, 25)

MainFrame.BorderSizePixel = 0

MainFrame.Visible = false

Instance.new("UICorner", MainFrame)
    .CornerRadius = UDim.new(0, 10)

-- ==========================================
-- [ DRAG SYSTEM ]
-- ==========================================
local dragging = false
local dragStart
local startPos

MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
    end
end)

MainFrame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging
        and (
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        )
    then
        local delta =
            input.Position - dragStart

        MainFrame.Position =
            UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
    end
end)

ToggleMenuBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- ==========================================
-- [ TITLE ]
-- ==========================================
local Title = Instance.new("TextLabel")
Title.Parent = MainFrame

Title.Size =
    UDim2.new(1, 0, 0, 38)

Title.BackgroundTransparency = 1

Title.Text = "⚽ Ball Trajectory Manager"

Title.TextColor3 =
    Color3.fromRGB(255, 255, 255)

Title.Font =
    Enum.Font.GothamBold

Title.TextSize = 13

-- ==========================================
-- [ LAYOUT ]
-- ==========================================
local Layout =
    Instance.new("UIListLayout")

Layout.Parent = MainFrame

Layout.SortOrder =
    Enum.SortOrder.LayoutOrder

Layout.Padding =
    UDim.new(0, 7)

Layout.HorizontalAlignment =
    Enum.HorizontalAlignment.Center

-- ==========================================
-- [ TOGGLE CREATOR ]
-- ==========================================
local function createToggle(text, defaultState, onClick)
    local btn = Instance.new("TextButton")

    btn.Parent = MainFrame

    btn.Size =
        UDim2.new(0.92, 0, 0, 34)

    btn.Font =
        Enum.Font.GothamBold

    btn.TextSize = 11

    btn.TextColor3 =
        Color3.fromRGB(255, 255, 255)

    Instance.new("UICorner", btn)
        .CornerRadius = UDim.new(0, 6)

    local state = defaultState

    local function updateVisual()
        if state then
            btn.BackgroundColor3 =
                Color3.fromRGB(40, 140, 60)

            btn.Text =
                text .. ": BẬT 🟢"
        else
            btn.BackgroundColor3 =
                Color3.fromRGB(160, 45, 45)

            btn.Text =
                text .. ": TẮT 🔴"
        end
    end

    btn.MouseButton1Click:Connect(function()
        state = not state

        updateVisual()

        onClick(state)

        -- Tắt thì clear luôn
        if not state then
            clearAndHideAll()
        end
    end)

    updateVisual()

    return btn
end

createToggle(
    "Công Tắc Tracker Tổng",
    Config.MasterEnabled,
    function(st)
        Config.MasterEnabled = st

        if not st then
            clearAndHideAll()
        end
    end
)

-- ==========================================
-- [ BOUNCE MODE ]
-- ==========================================
local bounceModeBtn = Instance.new("TextButton")
bounceModeBtn.Parent = MainFrame

bounceModeBtn.Size =
    UDim2.new(0.92, 0, 0, 32)

bounceModeBtn.BackgroundColor3 =
    Color3.fromRGB(40, 40, 50)

bounceModeBtn.Font =
    Enum.Font.GothamBold

bounceModeBtn.TextSize = 11

bounceModeBtn.TextColor3 =
    Color3.fromRGB(220, 220, 220)

bounceModeBtn.Text =
    Config.DrawAllBounces
    and "Quỹ Đạo: VẼ TẤT CẢ CÁC ĐIỂM 🌐"
    or "Quỹ Đạo: CHỈ ĐIỂM RƠI ĐẦU 🎯"

Instance.new("UICorner", bounceModeBtn)
    .CornerRadius = UDim.new(0, 6)

bounceModeBtn.MouseButton1Click:Connect(function()
    Config.DrawAllBounces =
        not Config.DrawAllBounces

    if Config.DrawAllBounces then
        bounceModeBtn.Text =
            "Quỹ Đạo: VẼ TẤT CẢ CÁC ĐIỂM 🌐"
    else
        bounceModeBtn.Text =
            "Quỹ Đạo: CHỈ ĐIỂM RƠI ĐẦU 🎯"
    end

    clearAndHideAll()
end)

-- ==========================================
-- [ COLOR LABEL ]
-- ==========================================
local PaletteLabel = Instance.new("TextLabel")
PaletteLabel.Parent = MainFrame

PaletteLabel.Size =
    UDim2.new(0.92, 0, 0, 18)

PaletteLabel.BackgroundTransparency = 1

PaletteLabel.Text =
    "🎨 Chọn Màu Giao Diện:"

PaletteLabel.TextColor3 =
    Color3.fromRGB(180, 180, 180)

PaletteLabel.Font =
    Enum.Font.GothamBold

PaletteLabel.TextSize = 11

PaletteLabel.TextXAlignment =
    Enum.TextXAlignment.Left

-- ==========================================
-- [ COLOR PALETTE ]
-- ==========================================
local PaletteFrame = Instance.new("Frame")
PaletteFrame.Parent = MainFrame

PaletteFrame.Size =
    UDim2.new(0.92, 0, 0, 32)

PaletteFrame.BackgroundTransparency = 1

local PaletteLayout =
    Instance.new("UIGridLayout")

PaletteLayout.Parent = PaletteFrame

PaletteLayout.CellSize =
    UDim2.new(0, 38, 0, 30)

PaletteLayout.CellPadding =
    UDim2.new(0, 7, 0, 0)

local ColorsList = {
    Color3.fromRGB(0, 255, 238),
    Color3.fromRGB(255, 238, 0),
    Color3.fromRGB(0, 255, 100),
    Color3.fromRGB(255, 50, 80),
    Color3.fromRGB(200, 70, 255),
    Color3.fromRGB(255, 255, 255)
}

for _, color in ipairs(ColorsList) do
    local cBtn = Instance.new("TextButton")

    cBtn.Parent = PaletteFrame

    cBtn.BackgroundColor3 = color

    cBtn.Text = ""

    Instance.new("UICorner", cBtn)
        .CornerRadius = UDim.new(0, 5)

    cBtn.MouseButton1Click:Connect(function()
        Config.CurrentColor = color

        ToggleStroke.Color = color

        -- Đổi màu toàn bộ beam đang tồn tại
        for _, beam in pairs(BeamsPool) do
            if beam and beam.Parent then
                beam.Color =
                    ColorSequence.new(color)
            end
        end
    end)
end

-- ==========================================
-- [ CLEANUP KHI GUI BỊ DESTROY ]
-- ==========================================
ScreenGui.Destroying:Connect(function()
    if _G.BallTrackerConnection then
        _G.BallTrackerConnection:Disconnect()
        _G.BallTrackerConnection = nil
    end

    if _G.BallTrackerTeamConnection then
        _G.BallTrackerTeamConnection:Disconnect()
        _G.BallTrackerTeamConnection = nil
    end
end)
```
