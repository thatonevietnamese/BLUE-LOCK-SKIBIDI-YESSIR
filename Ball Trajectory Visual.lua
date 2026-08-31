local Players = game.Players
local Workspace = game.Workspace
local RunService = game.RunService
local UserInputService = game.UserInputService

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
-- [ BIẾN & CACHE ]
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

local isInLobby = false

-- ==========================================
-- [ GUI PARENT ]
-- ==========================================
local GuiParent = LocalPlayer:WaitForChild("PlayerGui")

-- ==========================================
-- [ DỌN SCRIPT CŨ ]
-- ==========================================
local oldGui = GuiParent:FindFirstChild("BallTrackerUI")

if oldGui then
    oldGui:Destroy()
end

if _G.BallTrackerConnection then
    pcall(function()
        _G.BallTrackerConnection:Disconnect()
    end)

    _G.BallTrackerConnection = nil
end

if _G.BallTrackerTeamConnection then
    pcall(function()
        _G.BallTrackerTeamConnection:Disconnect()
    end)

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
    for _, beam in pairs(BeamsPool) do
        if beam and beam.Parent then
            beam.Enabled = false
        end
    end

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
-- [ KIỂM TRA TEAM ]
-- ==========================================
local function isLobbyTeam()
    local team = LocalPlayer.Team

    if not team then
        return false
    end

    return string.lower(team.Name) == "lobby"
end

-- ==========================================
-- [ TÌM BÓNG ]
-- ==========================================
local function getActiveBall()
    if cachedBall
        and cachedBall.Parent
        and cachedBall:IsA("BasePart")
        and cachedBall:IsDescendantOf(Workspace)
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
        local ball = Workspace:FindFirstChild(name, true)

        if ball
            and ball:IsA("BasePart")
            and ball:IsDescendantOf(Workspace)
        then
            cachedBall = ball
            return ball
        end
    end

    return nil
end

-- ==========================================
-- [ LẤY VẬN TỐC ]
-- ==========================================
local function getEffectiveVelocity(ball)
    local now = os.clock()
    local currentPos = ball.Position

    if lastBallPos and lastBallTime > 0 then
        local realDt = now - lastBallTime

        if realDt > 0 and realDt < 0.2 then
            calculatedVelocity = (currentPos - lastBallPos) / realDt
        end
    end

    lastBallPos = currentPos
    lastBallTime = now

    local physVel = ball.AssemblyLinearVelocity

    if physVel and physVel.Magnitude > 1.5 then
        return physVel
    end

    local bv = ball:FindFirstChildOfClass("BodyVelocity")

    if bv and bv.Velocity.Magnitude > 1.5 then
        return bv.Velocity
    end

    local lv = ball:FindFirstChildOfClass("LinearVelocity")

    if lv and lv.VectorVelocity.Magnitude > 1.5 then
        return lv.VectorVelocity
    end

    if calculatedVelocity.Magnitude > 1.5 then
        return calculatedVelocity
    end

    return Vector3.zero
end

-- ==========================================
-- [ RAYCAST FILTER ]
-- ==========================================
local function updateRaycastFilter(ball)
    local ignoreList = {
        getVisualFolder(),
        ball
    }

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
-- [ DỰ ĐOÁN QUỸ ĐẠO ]
-- ==========================================
local function predictTrajectory(ball)
    table.clear(cachedPoints)

    local firstImpactIndex = -1
    local currentVel = getEffectiveVelocity(ball)

    if currentVel.Magnitude < 1.2 then
        return cachedPoints, firstImpactIndex
    end

    local currentPos = ball.Position

    local gravityValue =
        Workspace.Gravity > 0
        and Workspace.Gravity
        or 196.2

    local gravity = Vector3.new(0, -gravityValue, 0)

    local totalTime = 0
    local stepDt = Config.TimeStep
    local bounceCount = 0

    table.insert(cachedPoints, currentPos)

    while totalTime < Config.TrajectoryTime
        and bounceCount < Config.MaxBounces
    do
        local nextPos =
            currentPos
            + currentVel * stepDt
            + 0.5 * gravity * (stepDt ^ 2)

        local direction = nextPos - currentPos

        local rayResult =
            Workspace:Raycast(
                currentPos,
                direction,
                raycastParams
            )

        if rayResult then
            bounceCount += 1

            local hitPos = rayResult.Position
            local hitNormal = rayResult.Normal

            local stepDistance = direction.Magnitude
            local actualDistance = (hitPos - currentPos).Magnitude

            local fraction =
                stepDistance > 0
                and actualDistance / stepDistance
                or 1

            table.insert(cachedPoints, hitPos)

            if bounceCount == 1 then
                firstImpactIndex = #cachedPoints
            end

            local velocityAtImpact =
                currentVel
                + gravity * (stepDt * fraction)

            currentVel =
                (
                    velocityAtImpact
                    - 2
                    * velocityAtImpact:Dot(hitNormal)
                    * hitNormal
                )
                * Config.Elasticity

            currentPos =
                hitPos
                + hitNormal * 0.08

            totalTime += stepDt * fraction

            if currentVel.Magnitude < 1.5 then
                break
            end
        else
            currentPos = nextPos

            currentVel =
                currentVel
                + gravity * stepDt

            totalTime += stepDt

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
-- [ TẠO BEAM ]
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

    if not AttachmentsPool[index] then
        local attachment = Instance.new("Attachment")
        attachment.Name = "Att_" .. tostring(index)
        attachment.Parent = Workspace.Terrain

        AttachmentsPool[index] = attachment
    end

    if index > 1 and not BeamsPool[index - 1] then
        local beam = Instance.new("Beam")

        beam.Name = "Beam_" .. tostring(index - 1)

        beam.Width0 = Config.BeamWidth
        beam.Width1 = Config.BeamWidth

        beam.FaceCamera = true

        beam.Attachment0 = AttachmentsPool[index - 1]
        beam.Attachment1 = AttachmentsPool[index]

        beam.Parent = targetFolder

        BeamsPool[index - 1] = beam
    end

    local beam = BeamsPool[index - 1]

    if beam then
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
    -- Vào Lobby = ẩn toàn bộ
    if isInLobby then
        clearAndHideAll()
        return
    end

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

    local points, firstImpactIndex =
        predictTrajectory(ball)

    if #points == 0 then
        clearAndHideAll()
        return
    end

    local maxPointIndex

    if Config.DrawAllBounces then
        maxPointIndex = #points
    elseif firstImpactIndex > 0 then
        maxPointIndex = firstImpactIndex
    else
        maxPointIndex = #points
    end

    local beamIndex = 1

    for i = 1, maxPointIndex do
        local point = points[i]

        if point then
            getOrCreateBeam(beamIndex)

            local attachment =
                AttachmentsPool[beamIndex]

            if attachment then
                attachment.WorldPosition = point
            end

            beamIndex += 1
        end
    end

    for i = beamIndex, #AttachmentsPool do
        local attachment = AttachmentsPool[i]

        if attachment and attachment.Parent then
            attachment.WorldPosition =
                Vector3.new(0, -10000, 0)
        end

        local beam = BeamsPool[i - 1]

        if beam and beam.Parent then
            beam.Enabled = false
        end
    end
end

-- ==========================================
-- [ TEAM CHANGE ]
-- ==========================================
_G.BallTrackerTeamConnection =
    LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
        isInLobby = isLobbyTeam()

        -- Đổi team là clear ngay
        clearAndHideAll()
    end)

-- ==========================================
-- [ TRẠNG THÁI BAN ĐẦU ]
-- ==========================================
isInLobby = isLobbyTeam()

if isInLobby then
    clearAndHideAll()
end

-- ==========================================
-- [ START ]
-- ==========================================
_G.BallTrackerConnection =
    RunService.RenderStepped:Connect(renderLoop)

-- ==========================================
-- [ GUI ]
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

ToggleMenuBtn.Text =
    "⚡ Tracker Menu"

ToggleMenuBtn.TextColor3 =
    Color3.fromRGB(255, 255, 255)

ToggleMenuBtn.Font =
    Enum.Font.GothamBold

ToggleMenuBtn.TextSize = 12

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 8)
ToggleCorner.Parent = ToggleMenuBtn

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Config.CurrentColor
ToggleStroke.Thickness = 1.5
ToggleStroke.Parent = ToggleMenuBtn

-- ==========================================
-- [ MAIN FRAME ]
-- ==========================================
local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui

MainFrame.Size =
    UDim2.new(0, 310, 0, 315)

MainFrame.Position =
    UDim2.new(0.08, 0, 0.18, 0)

MainFrame.BackgroundColor3 =
    Color3.fromRGB(20, 20, 25)

MainFrame.BorderSizePixel = 0
MainFrame.Visible = false

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

-- ==========================================
-- [ DRAG ]
-- ==========================================
local dragging = false
local dragStart = nil
local startPos = nil

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
    if not dragging then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch
    then
        return
    end

    local delta =
        input.Position - dragStart

    MainFrame.Position =
        UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
end)

ToggleMenuBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible =
        not MainFrame.Visible
end)

-- ==========================================
-- [ TITLE ]
-- ==========================================
local Title = Instance.new("TextLabel")
Title.Parent = MainFrame

Title.Size =
    UDim2.new(1, 0, 0, 38)

Title.BackgroundTransparency = 1

Title.Text =
    "⚽ Ball Trajectory Manager"

Title.TextColor3 =
    Color3.fromRGB(255, 255, 255)

Title.Font =
    Enum.Font.GothamBold

Title.TextSize = 13

-- ==========================================
-- [ LAYOUT ]
-- ==========================================
local Layout = Instance.new("UIListLayout")

Layout.Parent = MainFrame
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Padding = UDim.new(0, 7)
Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- ==========================================
-- [ TOGGLE ]
-- ==========================================
local function createToggle(text, defaultState, callback)
    local button = Instance.new("TextButton")
    button.Parent = MainFrame

    button.Size =
        UDim2.new(0.92, 0, 0, 34)

    button.Font =
        Enum.Font.GothamBold

    button.TextSize = 11

    button.TextColor3 =
        Color3.fromRGB(255, 255, 255)

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button

    local state = defaultState

    local function updateVisual()
        if state then
            button.BackgroundColor3 =
                Color3.fromRGB(40, 140, 60)

            button.Text =
                text .. ": BẬT 🟢"
        else
            button.BackgroundColor3 =
                Color3.fromRGB(160, 45, 45)

            button.Text =
                text .. ": TẮT 🔴"
        end
    end

    button.MouseButton1Click:Connect(function()
        state = not state

        updateVisual()
        callback(state)

        if not state then
            clearAndHideAll()
        end
    end)

    updateVisual()

    return button
end

createToggle(
    "Công Tắc Tracker Tổng",
    Config.MasterEnabled,
    function(state)
        Config.MasterEnabled = state

        if not state then
            clearAndHideAll()
        end
    end
)

-- ==========================================
-- [ BOUNCE MODE ]
-- ==========================================
local bounceModeBtn =
    Instance.new("TextButton")

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

local BounceCorner =
    Instance.new("UICorner")

BounceCorner.CornerRadius =
    UDim.new(0, 6)

BounceCorner.Parent =
    bounceModeBtn

local function updateBounceText()
    if Config.DrawAllBounces then
        bounceModeBtn.Text =
            "Quỹ Đạo: VẼ TẤT CẢ CÁC ĐIỂM 🌐"
    else
        bounceModeBtn.Text =
            "Quỹ Đạo: CHỈ ĐIỂM RƠI ĐẦU 🎯"
    end
end

updateBounceText()

bounceModeBtn.MouseButton1Click:Connect(function()
    Config.DrawAllBounces =
        not Config.DrawAllBounces

    updateBounceText()
    clearAndHideAll()
end)

-- ==========================================
-- [ NÚT HỦY TRACKER TẠM THỜI ]
-- ==========================================
local ClearTrackerBtn =
    Instance.new("TextButton")

ClearTrackerBtn.Parent = MainFrame

ClearTrackerBtn.Size =
    UDim2.new(0.92, 0, 0, 34)

ClearTrackerBtn.BackgroundColor3 =
    Color3.fromRGB(120, 70, 40)

ClearTrackerBtn.Font =
    Enum.Font.GothamBold

ClearTrackerBtn.TextSize = 11

ClearTrackerBtn.TextColor3 =
    Color3.fromRGB(255, 255, 255)

ClearTrackerBtn.Text =
    "🧹 HỦY TẤT CẢ TRACKER TẠM THỜI"

local ClearTrackerCorner =
    Instance.new("UICorner")

ClearTrackerCorner.CornerRadius =
    UDim.new(0, 6)

ClearTrackerCorner.Parent =
    ClearTrackerBtn

ClearTrackerBtn.MouseButton1Click:Connect(function()
    -- Chỉ cleanup visual hiện tại.
    -- Không disconnect RenderStepped.
    -- Tracker vẫn tiếp tục chạy bình thường.
    clearAndHideAll()
end)

-- ==========================================
-- [ COLOR LABEL ]
-- ==========================================
local PaletteLabel =
    Instance.new("TextLabel")

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
-- [ PALETTE ]
-- ==========================================
local PaletteFrame =
    Instance.new("Frame")

PaletteFrame.Parent = MainFrame

PaletteFrame.Size =
    UDim2.new(0.92, 0, 0, 32)

PaletteFrame.BackgroundTransparency = 1

local PaletteLayout =
    Instance.new("UIGridLayout")

PaletteLayout.Parent =
    PaletteFrame

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
    local colorButton =
        Instance.new("TextButton")

    colorButton.Parent =
        PaletteFrame

    colorButton.BackgroundColor3 =
        color

    colorButton.Text = ""

    local colorCorner =
        Instance.new("UICorner")

    colorCorner.CornerRadius =
        UDim.new(0, 5)

    colorCorner.Parent =
        colorButton

    colorButton.MouseButton1Click:Connect(function()
        Config.CurrentColor = color

        ToggleStroke.Color = color

        for _, beam in pairs(BeamsPool) do
            if beam and beam.Parent then
                beam.Color =
                    ColorSequence.new(color)
            end
        end
    end)
end

-- ==========================================
-- [ CLEANUP ]
-- ==========================================
ScreenGui.Destroying:Connect(function()
    if _G.BallTrackerConnection then
        pcall(function()
            _G.BallTrackerConnection:Disconnect()
        end)

        _G.BallTrackerConnection = nil
    end

    if _G.BallTrackerTeamConnection then
        pcall(function()
            _G.BallTrackerTeamConnection:Disconnect()
        end)

        _G.BallTrackerTeamConnection = nil
    end
end)
