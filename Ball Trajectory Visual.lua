local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local GuiParent = LocalPlayer:WaitForChild("PlayerGui")

-- ==========================================
-- [ CONFIGURATION ]
-- ==========================================
local Config = {
    MasterEnabled = true,

    DrawTrajectory = true,
    DrawAllBounces = false,

    TrajectoryTime = 6.0,
    TimeStep = 0.03,
    BeamWidth = 0.35,
    MaxBounces = 4,
    Elasticity = 0.75,

    ShowDirectionArrow = true,
    MinArrowSpeed = 2,
    ArrowScale = 0.12,
    MinArrowLength = 3,
    MaxArrowLength = 90,
    ArrowWidth = 0.55,

    SpeedSmoothing = 0.25,
    VelocitySampleInterval = 0.06,

    CurrentColor = Color3.fromRGB(0, 255, 238)
}

-- ==========================================
-- [ STATE & CACHE ]
-- ==========================================

local cachedPoints = {}

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.RespectCanCollide = true

local cachedBall = nil
local lastBallCheck = 0
local BALL_SCAN_INTERVAL = 0.15

local cachedHolder = nil
local cachedHeldBall = nil
local lastHolderCheck = 0
local HOLDER_SCAN_INTERVAL = 0.10

local lastObservedPosition = nil
local lastObservedTime = 0

local estimatedVelocity = Vector3.zero
local smoothedHorizontalVelocity = Vector3.zero

local lastVelocitySampleTime = 0

local heldDirection = Vector3.zero
local heldSpeed = 0

local currentHolder = nil
local previousHolder = nil

local isInLobby = false

-- ==========================================
-- [ RAYCAST FILTER CACHE ]
-- ==========================================

local lastFilterUpdate = 0
local FILTER_UPDATE_INTERVAL = 0.50
local filterDirty = true
local lastFilteredBall = nil
local lastFilteredPlayerCount = 0

-- ==========================================
-- [ GUI CLEANUP ]
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

-- ==========================================
-- [ VISUAL POOLS ]
-- ==========================================

local AttachmentsPool = {}
local BeamsPool = {}

local ArrowAttachment0 = nil
local ArrowAttachment1 = nil
local ArrowBeam = nil

-- ==========================================
-- [ RESET MOVEMENT CACHE ]
-- ==========================================

local function resetMovementCache()
    lastObservedPosition = nil
    lastObservedTime = 0

    estimatedVelocity = Vector3.zero
    smoothedHorizontalVelocity = Vector3.zero

    lastVelocitySampleTime = 0

    heldDirection = Vector3.zero
    heldSpeed = 0

    currentHolder = nil
    previousHolder = nil

    cachedHolder = nil
    cachedHeldBall = nil
    lastHolderCheck = 0
end

-- ==========================================
-- [ CLEAR VISUALS ]
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

    if ArrowBeam and ArrowBeam.Parent then
        ArrowBeam.Enabled = false
    end

    if ArrowAttachment0 and ArrowAttachment0.Parent then
        ArrowAttachment0.WorldPosition = Vector3.new(0, -10000, 0)
    end

    if ArrowAttachment1 and ArrowAttachment1.Parent then
        ArrowAttachment1.WorldPosition = Vector3.new(0, -10000, 0)
    end

    table.clear(cachedPoints)

    cachedBall = nil
    lastBallCheck = 0

    resetMovementCache()
end

-- ==========================================
-- [ LOBBY CHECK ]
-- ==========================================

local function isLobbyTeam()
    local team = LocalPlayer.Team

    if not team then
        return false
    end

    return string.lower(team.Name) == "lobby"
end

-- ==========================================
-- [ FIND ACTIVE BALL ]
-- ==========================================

local function getActiveBall()
    if cachedBall
        and cachedBall.Parent
        and cachedBall:IsA("BasePart")
        and cachedBall:IsDescendantOf(Workspace)
    then
        return cachedBall
    end

    local now = os.clock()

    if now - lastBallCheck < BALL_SCAN_INTERVAL then
        return nil
    end

    lastBallCheck = now
    cachedBall = nil

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
-- [ FIND BALL HOLDER ]
-- ==========================================

local function scanBallHolder()
    local possibleNames = {
        "Ball",
        "SoccerBall",
        "Football",
        "TPSBall",
        "TpsBall"
    }

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character

        if character then
            local tool = character:FindFirstChildOfClass("Tool")

            if tool then
                local handle = tool:FindFirstChild("Handle")
                if handle and handle:IsA("BasePart") then
                    return player, handle
                end

                local toolBall = tool:FindFirstChild("Ball")
                if toolBall and toolBall:IsA("BasePart") then
                    return player, toolBall
                end
            end

            for _, name in ipairs(possibleNames) do
                local alternateBall = character:FindFirstChild(name)

                if alternateBall and alternateBall:IsA("BasePart") then
                    return player, alternateBall
                end
            end
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character

        if character then
            for _, name in ipairs(possibleNames) do
                local nestedBall = character:FindFirstChild(name, true)

                if nestedBall and nestedBall:IsA("BasePart") then
                    return player, nestedBall
                end
            end
        end
    end

    return nil, nil
end

local function findBallHolder()
    local now = os.clock()

    if cachedHolder
        and cachedHolder.Parent == Players
        and cachedHolder.Character
        and cachedHeldBall
        and cachedHeldBall.Parent
        and cachedHeldBall:IsA("BasePart")
    then
        if now - lastHolderCheck < HOLDER_SCAN_INTERVAL then
            return cachedHolder, cachedHeldBall
        end
    elseif now - lastHolderCheck < HOLDER_SCAN_INTERVAL then
        return nil, nil
    end

    lastHolderCheck = now

    local holder, heldBall = scanBallHolder()

    cachedHolder = holder
    cachedHeldBall = heldBall

    return holder, heldBall
end

-- ==========================================
-- [ SAFE UNIT ]
-- ==========================================

local function safeUnit(vector)
    if vector.Magnitude <= 0.001 then
        return Vector3.zero
    end

    return vector.Unit
end

-- ==========================================
-- [ HOLDER DIRECTION ]
-- ==========================================

local function getHolderDirection(holder)
    if not holder then
        return Vector3.zero
    end

    local character = holder.Character

    if not character then
        return Vector3.zero
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")

    if not hrp then
        return Vector3.zero
    end

    local look = Vector3.new(
        hrp.CFrame.LookVector.X,
        0,
        hrp.CFrame.LookVector.Z
    )

    return safeUnit(look)
end

-- ==========================================
-- [ MOVEMENT ESTIMATION ]
-- ==========================================

local function updateMovementEstimate(ball, holder)
    local now = os.clock()
    local currentPos = ball.Position

    if holder then
        local direction = getHolderDirection(holder)

        if direction.Magnitude > 0 then
            heldDirection = direction
        end

        local character = holder.Character

        if character then
            local hrp = character:FindFirstChild("HumanoidRootPart")

            if hrp then
                local holderVelocity = hrp.AssemblyLinearVelocity

                local horizontalSpeed = Vector3.new(
                    holderVelocity.X,
                    0,
                    holderVelocity.Z
                ).Magnitude

                if horizontalSpeed > 0 then
                    heldSpeed = horizontalSpeed
                end
            end
        end

        smoothedHorizontalVelocity =
            heldDirection * math.max(heldSpeed, 1)

        previousHolder = holder

        lastObservedPosition = currentPos
        lastObservedTime = now

        return
    end

    if not lastObservedPosition then
        lastObservedPosition = currentPos
        lastObservedTime = now
        return
    end

    if now - lastVelocitySampleTime < Config.VelocitySampleInterval then
        return
    end

    local dt = now - lastObservedTime

    if dt <= 0 then
        return
    end

    local displacement = currentPos - lastObservedPosition
    local measuredVelocity = displacement / dt

    estimatedVelocity = measuredVelocity

    local horizontalVelocity = Vector3.new(
        measuredVelocity.X,
        0,
        measuredVelocity.Z
    )

    if horizontalVelocity.Magnitude > Config.MinArrowSpeed then
        smoothedHorizontalVelocity =
            smoothedHorizontalVelocity:Lerp(
                horizontalVelocity,
                Config.SpeedSmoothing
            )
    else
        smoothedHorizontalVelocity =
            smoothedHorizontalVelocity:Lerp(
                Vector3.zero,
                Config.SpeedSmoothing
            )
    end

    lastObservedPosition = currentPos
    lastObservedTime = now
    lastVelocitySampleTime = now
end

-- ==========================================
-- [ CURRENT HORIZONTAL VELOCITY ]
-- ==========================================

local function getCurrentHorizontalVelocity()
    return smoothedHorizontalVelocity
end

-- ==========================================
-- [ RAYCAST FILTER ]
-- ==========================================

local function markRaycastFilterDirty()
    filterDirty = true
end

local function updateRaycastFilter(ball)
    local now = os.clock()
    local playerCount = #Players:GetPlayers()

    local forceUpdate =
        filterDirty
        or ball ~= lastFilteredBall
        or playerCount ~= lastFilteredPlayerCount

    if not forceUpdate
        and now - lastFilterUpdate < FILTER_UPDATE_INTERVAL
    then
        return
    end

    lastFilterUpdate = now
    lastFilteredBall = ball
    lastFilteredPlayerCount = playerCount
    filterDirty = false

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
-- [ TRAJECTORY PREDICTION ]
-- ==========================================

local function predictTrajectory(ball)
    table.clear(cachedPoints)

    local firstImpactIndex = -1

    local holder = currentHolder
    local initialVelocity = Vector3.zero

    if holder then
        local direction = getHolderDirection(holder)

        if direction.Magnitude > 0 then
            initialVelocity =
                direction * math.max(heldSpeed, 1)
        end
    else
        initialVelocity = estimatedVelocity
    end

    if initialVelocity.Magnitude < 1.2 then
        return cachedPoints, firstImpactIndex
    end

    local currentPos = ball.Position

    local gravityValue = Workspace.Gravity
    local gravity = Vector3.new(0, -gravityValue, 0)

    local totalTime = 0
    local stepDt = Config.TimeStep
    local bounceCount = 0
    local currentVel = initialVelocity

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
-- [ GET / CREATE TRAJECTORY BEAM ]
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
        attachment.Parent = targetFolder

        AttachmentsPool[index] = attachment
    end

    if index > 1 and not BeamsPool[index - 1] then
        local beam = Instance.new("Beam")

        beam.Name = "Beam_" .. tostring(index - 1)
        beam.Parent = targetFolder
        BeamsPool[index - 1] = beam
    end

    local beam = BeamsPool[index - 1]

    if beam then
        beam.Attachment0 = AttachmentsPool[index - 1]
        beam.Attachment1 = AttachmentsPool[index]

        beam.Color = ColorSequence.new(Config.CurrentColor)
        beam.Width0 = Config.BeamWidth
        beam.Width1 = Config.BeamWidth
        beam.FaceCamera = true
        beam.Enabled = true

        if beam.Parent ~= targetFolder then
            beam.Parent = targetFolder
        end
    end
end

-- ==========================================
-- [ CREATE DIRECTION ARROW ]
-- ==========================================

local function createArrow()
    local folder = getVisualFolder()

    if not ArrowAttachment0 then
        ArrowAttachment0 = Instance.new("Attachment")
        ArrowAttachment0.Name = "DirectionArrow_Start"
        ArrowAttachment0.Parent = folder
    end

    if not ArrowAttachment1 then
        ArrowAttachment1 = Instance.new("Attachment")
        ArrowAttachment1.Name = "DirectionArrow_End"
        ArrowAttachment1.Parent = folder
    end

    if not ArrowBeam then
        ArrowBeam = Instance.new("Beam")

        ArrowBeam.Name = "DirectionArrow"
        ArrowBeam.Attachment0 = ArrowAttachment0
        ArrowBeam.Attachment1 = ArrowAttachment1
        ArrowBeam.FaceCamera = true

        ArrowBeam.Width0 = Config.ArrowWidth
        ArrowBeam.Width1 = Config.ArrowWidth * 0.55

        ArrowBeam.Color = ColorSequence.new(Config.CurrentColor)
        ArrowBeam.Transparency = NumberSequence.new(0)

        ArrowBeam.Parent = folder
    else
        ArrowBeam.Attachment0 = ArrowAttachment0
        ArrowBeam.Attachment1 = ArrowAttachment1

        if ArrowBeam.Parent ~= folder then
            ArrowBeam.Parent = folder
        end
    end
end

createArrow()

-- ==========================================
-- [ RENDER DIRECTION ARROW ]
-- ==========================================

local function renderDirectionArrow(ball)
    if not Config.ShowDirectionArrow then
        if ArrowBeam then
            ArrowBeam.Enabled = false
        end

        return
    end

    createArrow()

    local movement = getCurrentHorizontalVelocity()

    local horizontal = Vector3.new(
        movement.X,
        0,
        movement.Z
    )

    local speed = horizontal.Magnitude
    local holder = currentHolder

    if holder then
        local direction = getHolderDirection(holder)

        if direction.Magnitude > 0 then
            horizontal =
                direction
                * math.max(
                    heldSpeed,
                    Config.MinArrowSpeed
                )

            speed =
                math.max(
                    heldSpeed,
                    Config.MinArrowSpeed
                )
        end
    end

    if speed < Config.MinArrowSpeed
        or horizontal.Magnitude < 0.001
    then
        ArrowBeam.Enabled = false
        return
    end

    local direction = horizontal.Unit

    local arrowLength =
        math.clamp(
            speed * Config.ArrowScale,
            Config.MinArrowLength,
            Config.MaxArrowLength
        )

    local startPosition = ball.Position

    local endPosition =
        startPosition
        + direction * arrowLength

    ArrowAttachment0.WorldPosition = startPosition
    ArrowAttachment1.WorldPosition = endPosition

    ArrowBeam.Width0 = Config.ArrowWidth
    ArrowBeam.Width1 = Config.ArrowWidth * 0.55
    ArrowBeam.Color = ColorSequence.new(Config.CurrentColor)
    ArrowBeam.Enabled = true
end

-- ==========================================
-- [ RENDER TRAJECTORY ]
-- ==========================================

local function renderTrajectory(ball)
    if not Config.DrawTrajectory then
        for _, beam in pairs(BeamsPool) do
            if beam and beam.Parent then
                beam.Enabled = false
            end
        end

        return
    end

    updateRaycastFilter(ball)

    local points, firstImpactIndex =
        predictTrajectory(ball)

    if #points == 0 then
        for _, beam in pairs(BeamsPool) do
            if beam and beam.Parent then
                beam.Enabled = false
            end
        end

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

            local attachment = AttachmentsPool[beamIndex]

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
-- [ MAIN RENDER LOOP ]
-- ==========================================

local function renderLoop()
    if isInLobby then
        clearAndHideAll()
        return
    end

    if not Config.MasterEnabled then
        clearAndHideAll()
        return
    end

    local ball = getActiveBall()
    local holder, heldBall = findBallHolder()

    currentHolder = holder

    if not ball then
        if heldBall then
            ball = heldBall
            cachedBall = ball
        else
            clearAndHideAll()
            return
        end
    end

    if previousHolder and not holder then
        estimatedVelocity = smoothedHorizontalVelocity
    end

    updateMovementEstimate(ball, holder)

    renderDirectionArrow(ball)
    renderTrajectory(ball)
end

-- ==========================================
-- [ PLAYER EVENTS ]
-- ==========================================

local playerConnections = {}

local function trackCharacter(player)
    if not player then
        return
    end

    local oldConnection = playerConnections[player]

    if oldConnection then
        oldConnection:Disconnect()
        playerConnections[player] = nil
    end

    playerConnections[player] =
        player.CharacterAdded:Connect(function()
            markRaycastFilterDirty()
            cachedHolder = nil
            cachedHeldBall = nil
            lastHolderCheck = 0
        end)
end

for _, player in ipairs(Players:GetPlayers()) do
    trackCharacter(player)
end

Players.PlayerAdded:Connect(function(player)
    markRaycastFilterDirty()
    trackCharacter(player)
end)

Players.PlayerRemoving:Connect(function(player)
    markRaycastFilterDirty()

    cachedHolder = nil
    cachedHeldBall = nil
    lastHolderCheck = 0

    local connection = playerConnections[player]

    if connection then
        connection:Disconnect()
        playerConnections[player] = nil
    end
end)

-- ==========================================
-- [ TEAM CHANGE ]
-- ==========================================

_G.BallTrackerTeamConnection =
    LocalPlayer:GetPropertyChangedSignal("Team")
        :Connect(function()
            isInLobby = isLobbyTeam()

            clearAndHideAll()

            markRaycastFilterDirty()
        end)

-- ==========================================
-- [ INITIAL STATE ]
-- ==========================================

isInLobby = isLobbyTeam()

if isInLobby then
    clearAndHideAll()
end

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
ToggleMenuBtn.Size = UDim2.new(0, 120, 0, 35)
ToggleMenuBtn.Position = UDim2.new(0.01, 0, 0.18, 0)

ToggleMenuBtn.BackgroundColor3 =
    Color3.fromRGB(25, 25, 30)

ToggleMenuBtn.Text = "⚡ Tracker Menu"
ToggleMenuBtn.TextColor3 =
    Color3.fromRGB(255, 255, 255)

ToggleMenuBtn.Font = Enum.Font.GothamBold
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
MainFrame.Size = UDim2.new(0, 310, 0, 360)
MainFrame.Position = UDim2.new(0.08, 0, 0.18, 0)

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

UserInputService.InputEnded:Connect(function(input)
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

    local delta = input.Position - dragStart

    MainFrame.Position =
        UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
end)

ToggleMenuBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- ==========================================
-- [ TITLE ]
-- ==========================================

local Title = Instance.new("TextLabel")

Title.Parent = MainFrame
Title.Size = UDim2.new(1, 0, 0, 38)
Title.BackgroundTransparency = 1

Title.Text = "⚽ Ball Trajectory Manager"

Title.TextColor3 =
    Color3.fromRGB(255, 255, 255)

Title.Font = Enum.Font.GothamBold
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
-- [ GENERIC TOGGLE ]
-- ==========================================

local function createToggle(text, defaultState, callback)
    local button = Instance.new("TextButton")

    button.Parent = MainFrame
    button.Size = UDim2.new(0.92, 0, 0, 34)

    button.Font = Enum.Font.GothamBold
    button.TextSize = 11
    button.TextColor3 = Color3.fromRGB(255, 255, 255)

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button

    local state = defaultState

    local function updateVisual()
        if state then
            button.BackgroundColor3 =
                Color3.fromRGB(40, 140, 60)

            button.Text = text .. ": BẬT 🟢"
        else
            button.BackgroundColor3 =
                Color3.fromRGB(160, 45, 45)

            button.Text = text .. ": TẮT 🔴"
        end
    end

    button.MouseButton1Click:Connect(function()
        state = not state

        updateVisual()
        callback(state)
    end)

    updateVisual()

    return button
end

-- ==========================================
-- [ MASTER TOGGLE ]
-- ==========================================

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
-- [ DIRECTION ARROW TOGGLE ]
-- ==========================================

createToggle(
    "Mũi Tên Hướng",
    Config.ShowDirectionArrow,
    function(state)
        Config.ShowDirectionArrow = state

        if not state and ArrowBeam then
            ArrowBeam.Enabled = false
        end
    end
)

-- ==========================================
-- [ TRAJECTORY TOGGLE ]
-- ==========================================

createToggle(
    "Quỹ Đạo",
    Config.DrawTrajectory,
    function(state)
        Config.DrawTrajectory = state
    end
)

-- ==========================================
-- [ BOUNCE MODE ]
-- ==========================================

local bounceModeBtn = Instance.new("TextButton")

bounceModeBtn.Parent = MainFrame
bounceModeBtn.Size = UDim2.new(0.92, 0, 0, 32)

bounceModeBtn.BackgroundColor3 =
    Color3.fromRGB(40, 40, 50)

bounceModeBtn.Font = Enum.Font.GothamBold
bounceModeBtn.TextSize = 11
bounceModeBtn.TextColor3 =
    Color3.fromRGB(220, 220, 220)

local BounceCorner = Instance.new("UICorner")
BounceCorner.CornerRadius = UDim.new(0, 6)
BounceCorner.Parent = bounceModeBtn

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
    Config.DrawAllBounces = not Config.DrawAllBounces

    updateBounceText()

    clearAndHideAll()
end)

-- ==========================================
-- [ CLEAR ]
-- ==========================================

local ClearTrackerBtn = Instance.new("TextButton")

ClearTrackerBtn.Parent = MainFrame
ClearTrackerBtn.Size = UDim2.new(0.92, 0, 0, 34)

ClearTrackerBtn.BackgroundColor3 =
    Color3.fromRGB(120, 70, 40)

ClearTrackerBtn.Font = Enum.Font.GothamBold
ClearTrackerBtn.TextSize = 11
ClearTrackerBtn.TextColor3 =
    Color3.fromRGB(255, 255, 255)

ClearTrackerBtn.Text =
    "🧹 HỦY TẤT CẢ TRACKER TẠM THỜI"

local ClearTrackerCorner = Instance.new("UICorner")
ClearTrackerCorner.CornerRadius = UDim.new(0, 6)
ClearTrackerCorner.Parent = ClearTrackerBtn

ClearTrackerBtn.MouseButton1Click:Connect(function()
    clearAndHideAll()
end)

-- ==========================================
-- [ ARROW INFO ]
-- ==========================================

local ArrowInfo = Instance.new("TextLabel")

ArrowInfo.Parent = MainFrame
ArrowInfo.Size = UDim2.new(0.92, 0, 0, 42)
ArrowInfo.BackgroundTransparency = 1

ArrowInfo.Text =
    "Mũi tên = hướng X/Z\n"
    .. "Độ dài = tốc độ ước lượng"

ArrowInfo.TextColor3 =
    Color3.fromRGB(170, 170, 180)

ArrowInfo.Font = Enum.Font.Gotham
ArrowInfo.TextSize = 10
ArrowInfo.TextXAlignment = Enum.TextXAlignment.Left
ArrowInfo.TextYAlignment = Enum.TextYAlignment.Top

-- ==========================================
-- [ COLOR LABEL ]
-- ==========================================

local PaletteLabel = Instance.new("TextLabel")

PaletteLabel.Parent = MainFrame
PaletteLabel.Size = UDim2.new(0.92, 0, 0, 18)
PaletteLabel.BackgroundTransparency = 1

PaletteLabel.Text = "🎨 Chọn Màu Giao Diện:"

PaletteLabel.TextColor3 =
    Color3.fromRGB(180, 180, 180)

PaletteLabel.Font = Enum.Font.GothamBold
PaletteLabel.TextSize = 11
PaletteLabel.TextXAlignment = Enum.TextXAlignment.Left

-- ==========================================
-- [ PALETTE ]
-- ==========================================

local PaletteFrame = Instance.new("Frame")

PaletteFrame.Parent = MainFrame
PaletteFrame.Size = UDim2.new(0.92, 0, 0, 32)
PaletteFrame.BackgroundTransparency = 1

local PaletteLayout = Instance.new("UIGridLayout")

PaletteLayout.Parent = PaletteFrame
PaletteLayout.CellSize = UDim2.new(0, 38, 0, 30)
PaletteLayout.CellPadding = UDim2.new(0, 7, 0, 0)

local ColorsList = {
    Color3.fromRGB(0, 255, 238),
    Color3.fromRGB(255, 238, 0),
    Color3.fromRGB(0, 255, 100),
    Color3.fromRGB(255, 50, 80),
    Color3.fromRGB(200, 70, 255),
    Color3.fromRGB(255, 255, 255)
}

for _, color in ipairs(ColorsList) do
    local colorButton = Instance.new("TextButton")

    colorButton.Parent = PaletteFrame
    colorButton.BackgroundColor3 = color
    colorButton.Text = ""

    local colorCorner = Instance.new("UICorner")
    colorCorner.CornerRadius = UDim.new(0, 5)
    colorCorner.Parent = colorButton

    colorButton.MouseButton1Click:Connect(function()
        Config.CurrentColor = color

        ToggleStroke.Color = color

        if ArrowBeam then
            ArrowBeam.Color =
                ColorSequence.new(color)
        end

        for _, beam in pairs(BeamsPool) do
            if beam and beam.Parent then
                beam.Color =
                    ColorSequence.new(color)
            end
        end
    end)
end

-- ==========================================
-- [ INITIAL FILTER STATE ]
-- ==========================================

markRaycastFilterDirty()

-- ==========================================
-- [ MAIN CONNECTION ]
-- ==========================================

_G.BallTrackerConnection =
    RunService.RenderStepped:Connect(renderLoop)

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

    for player, connection in pairs(playerConnections) do
        if connection then
            connection:Disconnect()
        end

        playerConnections[player] = nil
    end

    if ArrowBeam then
        ArrowBeam.Enabled = false
    end
end)
