--========================================================--
--                 BALL CONTROLLER V3                     --
--  Modes 1-4 / Steal Ball / Sae Pass / Settings Panel   --
--========================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--========================================================--
-- CONFIG
--========================================================--

local BALL_NAME = "Ball"
local MIN_SPEED = 1
local MAX_SPEED = 1000
local DEFAULT_CONTROL_KEY = Enum.KeyCode.F
local DEFAULT_STEAL_DISTANCE = 3
local SAE_PASS_HEIGHT = 300
local SAE_PASS_SPEED = 260

local mode = 1
local controlKey = DEFAULT_CONTROL_KEY
local enabled = false
local anchorEnabled = true
local stealBallEnabled = false
local saePassEnabled = false
local changingControlKey = false
local leftMouseHeld = false
local minimized = false
local settingsOpen = false
local selectedTarget = nil
local saePassActive = false
local lastHolder = nil
local lastOwnershipState = nil
local lastControlPress = 0
local stealCooldown = 0

local modeSettings = {
    [1] = { speed = 60 },
    [2] = { speed = 60 },
    [3] = { speed = 60, height = 80, curve = 30 },
    [4] = { speed = 140 },
}

local keys = {W=false,A=false,S=false,D=false,Q=false,E=false}

--========================================================--
-- CHARACTER
--========================================================--

local character, humanoid, rootPart
local savedWalkSpeed, savedJumpPower, savedAutoRotate
local playerWasLocked = false

local function updateCharacter()
    character = player.Character
    if not character then
        humanoid, rootPart = nil, nil
        return false
    end

    humanoid = character:FindFirstChildOfClass("Humanoid")
    rootPart = character:FindFirstChild("HumanoidRootPart")
    return humanoid ~= nil and rootPart ~= nil
end

updateCharacter()

local function savePlayerState()
    if not humanoid then return end

    -- Không ghi đè state hợp lệ bằng WalkSpeed = 0 do chính lock vừa áp dụng.
    if savedWalkSpeed == nil and humanoid.WalkSpeed > 0 then
        savedWalkSpeed = humanoid.WalkSpeed
    end

    if savedJumpPower == nil then
        savedJumpPower = humanoid.JumpPower
    end

    if savedAutoRotate == nil then
        savedAutoRotate = humanoid.AutoRotate
    end
end

local function lockPlayer()
    if not updateCharacter() then return end
    savePlayerState()
    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.AutoRotate = false
    playerWasLocked = true
end

local function unlockPlayer()
    if not updateCharacter() then
        playerWasLocked = false
        savedWalkSpeed, savedJumpPower, savedAutoRotate = nil, nil, nil
        return
    end

    if playerWasLocked then
        if savedWalkSpeed ~= nil then humanoid.WalkSpeed = savedWalkSpeed end
        if savedJumpPower ~= nil then humanoid.JumpPower = savedJumpPower end
        if savedAutoRotate ~= nil then humanoid.AutoRotate = savedAutoRotate end
    end

    playerWasLocked = false
    savedWalkSpeed, savedJumpPower, savedAutoRotate = nil, nil, nil
end

-- Chỉ Mode 1/2 dùng Anchor. Nút Force Unanchor luôn thắng.
local function applyModeLock()
    if not updateCharacter() then return end

    if enabled and anchorEnabled and (mode == 1 or mode == 2) then
        savePlayerState()
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        humanoid.AutoRotate = false
        rootPart.Anchored = true
        playerWasLocked = true
    else
        if rootPart and rootPart.Anchored then
            rootPart.Anchored = false
        end
        unlockPlayer()
    end
end

local function forceUnanchor()
    updateCharacter()
    if rootPart then rootPart.Anchored = false end
    unlockPlayer()
    notify("ANCHOR", "Force Unanchor executed", 1.6)
end

--========================================================--
-- BALL / HOLDER HELPERS
--========================================================--

local function isMatchPlayer(plr)
    if not plr or not plr.Team then return false end
    local n = string.lower(plr.Team.Name)
    return string.find(n, "home", 1, true) ~= nil or string.find(n, "away", 1, true) ~= nil
end

local function findBall()
    if character then
        local ball = character:FindFirstChild(BALL_NAME, true)
        if ball and ball:IsA("BasePart") then return ball end
    end

    local playerModel = workspace:FindFirstChild(player.Name)
    if playerModel then
        local ball = playerModel:FindFirstChild(BALL_NAME, true)
        if ball and ball:IsA("BasePart") then return ball end
    end

    local directBall = workspace:FindFirstChild(BALL_NAME)
    if directBall then
        if directBall:IsA("BasePart") then return directBall end
        local p = directBall:FindFirstChildWhichIsA("BasePart", true)
        if p then return p end
    end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and string.lower(obj.Name) == string.lower(BALL_NAME) then
            return obj
        end
    end

    return nil
end

local function findBallHolder()
    for _, plr in ipairs(Players:GetPlayers()) do
        if isMatchPlayer(plr) and plr.Character then
            local ball = plr.Character:FindFirstChild(BALL_NAME, true)
            if ball and ball:IsA("BasePart") then
                return plr, ball
            end
            for _, obj in ipairs(plr.Character:GetDescendants()) do
                if obj:IsA("BasePart") and string.lower(obj.Name) == string.lower(BALL_NAME) then
                    return plr, obj
                end
            end
        end
    end
    return nil, nil
end

local function getBallState()
    local holder, heldBall = findBallHolder()
    local looseBall = findBall()

    if holder then
        return "HELD", holder, heldBall
    end

    if looseBall then
        return "FREE", nil, looseBall
    end

    return "MISSING", nil, nil
end

local function localHasBall()
    local holder = findBallHolder()
    return holder == player
end

local function getPlayerRoot(plr)
    if not plr or not plr.Character then return nil end
    return plr.Character:FindFirstChild("HumanoidRootPart")
end

local function sameTeam(plr)
    return plr and player.Team and plr.Team == player.Team
end

--========================================================--
-- NOTIFICATIONS
--========================================================--

local notificationHolder

local function notify(titleText, bodyText, duration)
    duration = duration or 2.2
    if not notificationHolder or not notificationHolder.Parent then return end

    local card = Instance.new("Frame")
    card.Size = UDim2.fromOffset(280, 58)
    card.AnchorPoint = Vector2.new(0.5, 0)
    card.Position = UDim2.new(0.5, 0, 0, -65)
    card.BackgroundColor3 = Color3.fromRGB(27,27,34)
    card.BorderSizePixel = 0
    card.Parent = notificationHolder

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,9)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(65,65,80)
    stroke.Transparency = 0.15
    stroke.Parent = card

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,-18,0,22)
    title.Position = UDim2.fromOffset(9,5)
    title.BackgroundTransparency = 1
    title.Text = tostring(titleText)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextColor3 = Color3.fromRGB(255,255,255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card

    local body = Instance.new("TextLabel")
    body.Size = UDim2.new(1,-18,0,25)
    body.Position = UDim2.fromOffset(9,27)
    body.BackgroundTransparency = 1
    body.Text = tostring(bodyText)
    body.Font = Enum.Font.Gotham
    body.TextSize = 11
    body.TextColor3 = Color3.fromRGB(175,175,185)
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.Parent = card

    local inTween = TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
        Position = UDim2.new(0.5,0,0,8)
    })
    inTween:Play()

    task.delay(duration, function()
        -- GUI/card có thể đã bị reset hoặc destroy trong lúc chờ.
        if not card or not card.Parent or not notificationHolder or not notificationHolder.Parent then
            return
        end

        local outTween = TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Position = UDim2.new(0.5,0,0,-65)
        })
        outTween:Play()

        -- Không dùng Completed:Wait(); tự dọn card sau thời gian tween.
        task.delay(0.22, function()
            if card and card.Parent then
                card:Destroy()
            end
        end)
    end)
end

--========================================================--
-- GUI HELPERS
--========================================================--

local gui = Instance.new("ScreenGui")
gui.Name = "BallController"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

local function stroke(parent, color, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(60,60,70)
    s.Transparency = transparency or 0.2
    s.Parent = parent
    return s
end

local function makeButton(parent, text, x, y, w, h)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w,h)
    b.Position = UDim2.fromOffset(x,y)
    b.BackgroundColor3 = Color3.fromRGB(43,43,51)
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.fromRGB(235,235,240)
    b.TextSize = 12
    b.Font = Enum.Font.GothamMedium
    b.AutoButtonColor = true
    b.Parent = parent
    corner(b,7)
    return b
end

local function makeLabel(parent, text, x, y, w, h, size)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromOffset(w,h)
    l.Position = UDim2.fromOffset(x,y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(205,205,215)
    l.TextSize = size or 12
    l.Font = Enum.Font.GothamMedium
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

local function makeBox(parent, value, x, y, w, h)
    local b = Instance.new("TextBox")
    b.Size = UDim2.fromOffset(w,h)
    b.Position = UDim2.fromOffset(x,y)
    b.BackgroundColor3 = Color3.fromRGB(40,40,47)
    b.BorderSizePixel = 0
    b.Text = tostring(value)
    b.TextColor3 = Color3.fromRGB(255,255,255)
    b.PlaceholderColor3 = Color3.fromRGB(130,130,140)
    b.TextSize = 12
    b.Font = Enum.Font.GothamMedium
    b.ClearTextOnFocus = false
    b.Parent = parent
    corner(b,7)
    return b
end

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(350,390)
main.Position = UDim2.new(0,25,0.5,-195)
main.BackgroundColor3 = Color3.fromRGB(24,24,29)
main.BorderSizePixel = 0
main.Parent = gui
corner(main,12)
stroke(main, Color3.fromRGB(60,60,70), 0.2)

local title = makeLabel(main, "⚽  BALL CONTROLLER V3", 10, 5, 260, 35, 18)
title.Font = Enum.Font.GothamBold

local minimizeButton = makeButton(main, "—", 312, 10, 28, 28)
minimizeButton.TextSize = 18

local statusLabel = makeLabel(main, "Status: OFF", 10, 42, 320, 22, 13)
local ballStatus = makeLabel(main, "BALL: SEARCHING...", 10, 64, 320, 22, 12)

local controlButton = makeButton(main, "CONTROL KEY: F", 10, 92, 160, 36)
local modeButton = makeButton(main, "MODE: 1", 180, 92, 160, 36)
local anchorButton = makeButton(main, "ANCHOR: ON", 10, 136, 160, 36)
local forceUnanchorButton = makeButton(main, "FORCE UNANCHOR", 180, 136, 160, 36)
local stealButton = makeButton(main, "STEAL BALL: OFF", 10, 180, 160, 36)
local saeButton = makeButton(main, "SAE PASS: OFF", 180, 180, 160, 36)
local settingsButton = makeButton(main, "⚙ SETTINGS", 10, 224, 160, 36)
local lockButton = makeButton(main, "LOCK PLAYER: OFF", 180, 224, 160, 36)

local info = makeLabel(main,
    "Control key = nhấn để kích hoạt thao tác control / mode 3-4.\n" ..
    "WASDEQ: điều khiển khi mode 1/2 đang active.\n" ..
    "Sae Pass: giữ chuột trái + Control Key để chọn / chuyền.",
    10, 270, 330, 88, 11)
info.TextWrapped = true
info.TextYAlignment = Enum.TextYAlignment.Top
info.TextColor3 = Color3.fromRGB(145,145,155)

local restoreButton = makeButton(gui, "⚽", 0, 0, 48, 48)
restoreButton.Visible = false
restoreButton.TextSize = 23
corner(restoreButton,24)
stroke(restoreButton, Color3.fromRGB(65,65,75), 0.1)

notificationHolder = Instance.new("Frame")
notificationHolder.Name = "Notifications"
notificationHolder.Size = UDim2.fromOffset(320,300)
notificationHolder.AnchorPoint = Vector2.new(0.5,0)
notificationHolder.Position = UDim2.new(0.5,0,0,0)
notificationHolder.BackgroundTransparency = 1
notificationHolder.Parent = gui

local notificationLayout = Instance.new("UIListLayout")
notificationLayout.Padding = UDim.new(0,7)
notificationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
notificationLayout.VerticalAlignment = Enum.VerticalAlignment.Top
notificationLayout.Parent = notificationHolder

--========================================================--
-- SETTINGS PANEL
--========================================================--

local settingsFrame = Instance.new("Frame")
settingsFrame.Name = "Settings"
settingsFrame.Size = UDim2.fromOffset(390,320)
settingsFrame.Position = UDim2.new(0,390,0.5,-160)
settingsFrame.BackgroundColor3 = Color3.fromRGB(22,22,27)
settingsFrame.BorderSizePixel = 0
settingsFrame.Visible = false
settingsFrame.Parent = gui
corner(settingsFrame,12)
stroke(settingsFrame, Color3.fromRGB(60,60,70), 0.15)

local settingsTitle = makeLabel(settingsFrame, "⚙ BALL SETTINGS", 12, 8, 270, 32, 17)
settingsTitle.Font = Enum.Font.GothamBold
local closeSettings = makeButton(settingsFrame, "X", 350, 8, 28, 28)

local tabs = {}
local tabNames = {"MODE 1", "MODE 2", "MODE 3", "MODE 4"}
for i, name in ipairs(tabNames) do
    tabs[i] = makeButton(settingsFrame, name, 10 + (i-1)*94, 48, 86, 30)
end

local settingsContent = Instance.new("Frame")
settingsContent.Size = UDim2.new(1,-20,1,-90)
settingsContent.Position = UDim2.fromOffset(10,88)
settingsContent.BackgroundTransparency = 1
settingsContent.Parent = settingsFrame

local speedLabels = {}
local speedBoxes = {}
local heightLabel = makeLabel(settingsContent, "HEIGHT", 10, 56, 100, 25, 12)
local curveLabel = makeLabel(settingsContent, "CURVE", 10, 106, 100, 25, 12)
local heightBox = makeBox(settingsContent, modeSettings[3].height, 120, 52, 220, 32)
local curveBox = makeBox(settingsContent, modeSettings[3].curve, 120, 102, 220, 32)
local settingsHint = makeLabel(settingsContent, "", 10, 160, 350, 60, 11)
settingsHint.TextWrapped = true
settingsHint.TextColor3 = Color3.fromRGB(145,145,155)

for i = 1,4 do
    speedLabels[i] = makeLabel(settingsContent, "SPEED", 10, 10, 100, 25, 12)
    speedBoxes[i] = makeBox(settingsContent, modeSettings[i].speed, 120, 6, 220, 32)
    speedLabels[i].Visible = false
    speedBoxes[i].Visible = false
end

heightLabel.Visible = false
curveLabel.Visible = false
heightBox.Visible = false
curveBox.Visible = false

local selectedSettingsTab = 1

local function parseSetting(box, oldValue, minValue, maxValue)
    local n = tonumber(box.Text)
    if not n then
        box.Text = tostring(oldValue)
        return oldValue
    end
    n = math.clamp(n, minValue, maxValue)
    box.Text = tostring(n)
    return n
end

local function refreshSettingsPanel()
    for i=1,4 do
        speedLabels[i].Visible = (selectedSettingsTab == i)
        speedBoxes[i].Visible = (selectedSettingsTab == i)
    end
    local mode3 = selectedSettingsTab == 3
    heightLabel.Visible = mode3
    curveLabel.Visible = mode3
    heightBox.Visible = mode3
    curveBox.Visible = mode3

    if selectedSettingsTab == 1 then
        settingsHint.Text = "Mode 1: tốc độ chuyển động ngang + dọc của bóng theo WASDEQ."
    elseif selectedSettingsTab == 2 then
        settingsHint.Text = "Mode 2: tốc độ bóng theo hướng camera."
    elseif selectedSettingsTab == 3 then
        settingsHint.Text = "Mode 3: HEIGHT = bóng bay thẳng đứng lên tại vị trí sút; CURVE = độ cong quỹ đạo."
    elseif selectedSettingsTab == 4 then
        settingsHint.Text = "Mode 4: velocity được truyền một lần, sau đó script không can thiệp bóng nữa."
    end
end

for i=1,4 do
    tabs[i].MouseButton1Click:Connect(function()
        selectedSettingsTab = i
        refreshSettingsPanel()
    end)
    speedBoxes[i].FocusLost:Connect(function()
        modeSettings[i].speed = parseSetting(speedBoxes[i], modeSettings[i].speed, MIN_SPEED, MAX_SPEED)
    end)
end

heightBox.FocusLost:Connect(function()
    modeSettings[3].height = parseSetting(heightBox, modeSettings[3].height, 0, 2000)
end)

curveBox.FocusLost:Connect(function()
    modeSettings[3].curve = parseSetting(curveBox, modeSettings[3].curve, -1000, 1000)
end)

--========================================================--
-- DRAG
--========================================================--

local function makeDraggable(object, handle)
    local dragging = false
    local dragStart
    local startPosition

    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        dragging = true
        dragStart = input.Position
        startPosition = object.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - dragStart
        object.Position = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
        )
    end)
end

makeDraggable(main, title)
makeDraggable(settingsFrame, settingsTitle)
makeDraggable(restoreButton, restoreButton)

--========================================================--
-- MINIMIZE / SETTINGS
--========================================================--

minimizeButton.MouseButton1Click:Connect(function()
    minimized = true
    restoreButton.Position = main.Position
    main.Visible = false
    settingsFrame.Visible = false
    restoreButton.Visible = true
end)

restoreButton.MouseButton1Click:Connect(function()
    minimized = false
    main.Visible = true
    restoreButton.Visible = false
end)

settingsButton.MouseButton1Click:Connect(function()
    settingsOpen = not settingsOpen
    settingsFrame.Visible = settingsOpen and not minimized
    refreshSettingsPanel()
end)

closeSettings.MouseButton1Click:Connect(function()
    settingsOpen = false
    settingsFrame.Visible = false
end)

--========================================================--
-- UI UPDATE
--========================================================--

local function modeName()
    if mode == 1 then return "MODE 1 [CAMERA WASDEQ]" end
    if mode == 2 then return "MODE 2 [CAMERA]" end
    if mode == 3 then return "MODE 3 [EXTREME CURVE]" end
    return "MODE 4 [RONALDO]"
end

local function updateUI()
    controlButton.Text = "CONTROL KEY: " .. controlKey.Name
    modeButton.Text = modeName()

    if enabled then
        statusLabel.Text = "Status: ACTIVE"
        statusLabel.TextColor3 = Color3.fromRGB(100,255,130)
    else
        statusLabel.Text = "Status: READY"
        statusLabel.TextColor3 = Color3.fromRGB(255,205,100)
    end

    anchorButton.Text = anchorEnabled and "ANCHOR: ON" or "ANCHOR: OFF"
    anchorButton.TextColor3 = anchorEnabled and Color3.fromRGB(100,255,130) or Color3.fromRGB(255,100,100)

    stealButton.Text = stealBallEnabled and "STEAL BALL: ON" or "STEAL BALL: OFF"
    stealButton.TextColor3 = stealBallEnabled and Color3.fromRGB(100,255,130) or Color3.fromRGB(255,100,100)

    saeButton.Text = saePassEnabled and "SAE PASS: ON" or "SAE PASS: OFF"
    saeButton.TextColor3 = saePassEnabled and Color3.fromRGB(100,255,130) or Color3.fromRGB(255,100,100)

    lockButton.Text = playerWasLocked and "LOCK PLAYER: ON" or "LOCK PLAYER: OFF"
    lockButton.TextColor3 = playerWasLocked and Color3.fromRGB(100,255,130) or Color3.fromRGB(255,100,100)
end

--========================================================--
-- CAMERA / TARGET
--========================================================--

local camera = workspace.CurrentCamera
local savedCameraType
local savedCameraSubject

local function saveCamera(ballSubject)
    camera = workspace.CurrentCamera
    if not camera then return end

    if savedCameraType == nil then
        savedCameraType = camera.CameraType
    end

    -- Chỉ lưu subject thật của player; tuyệt đối không lưu Ball làm subject gốc.
    local currentSubject = camera.CameraSubject
    if currentSubject and currentSubject ~= ballSubject then
        if savedCameraSubject == nil then
            savedCameraSubject = currentSubject
        end
    end
end

local function cameraToBall(ball)
    if not ball then return end
    camera = workspace.CurrentCamera
    if not camera then return end
    saveCamera(ball)
    camera.CameraType = Enum.CameraType.Custom
    camera.CameraSubject = ball
end

local function restoreCamera()
    camera = workspace.CurrentCamera
    if not camera then return end
    updateCharacter()
    camera.CameraType = savedCameraType or Enum.CameraType.Custom
    if humanoid then
        camera.CameraSubject = humanoid
    elseif savedCameraSubject then
        camera.CameraSubject = savedCameraSubject
    end
    savedCameraType, savedCameraSubject = nil, nil
end

--========================================================--
-- HIGHLIGHT / SAE PASS
--========================================================--

local targetHighlight

local function clearTarget()
    selectedTarget = nil
    saePassActive = false
    if targetHighlight then
        targetHighlight:Destroy()
        targetHighlight = nil
    end
end

local function highlightTarget(plr)
    if targetHighlight then targetHighlight:Destroy() end
    selectedTarget = plr
    saePassActive = plr ~= nil

    if not plr or not plr.Character then return end

    targetHighlight = Instance.new("Highlight")
    targetHighlight.Name = "SaePassTarget"
    targetHighlight.FillTransparency = 0.45
    targetHighlight.OutlineTransparency = 0
    targetHighlight.Adornee = plr.Character
    targetHighlight.Parent = plr.Character
    notify("SAE PASS TARGET", plr.Name, 1.8)
end

local function getClosestTeammateToMouse()
    camera = workspace.CurrentCamera
    if not camera then return nil end

    local mousePos = UserInputService:GetMouseLocation()
    local viewport = camera.ViewportSize
    local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    local best, bestDistance = nil, math.huge

    -- User asked for target nearest to mouse, while following camera aim.
    -- This uses screen-space mouse distance and only teammates.
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and sameTeam(plr) and plr.Character then
            local hrp = getPlayerRoot(plr)
            if hrp then
                local point, onScreen = camera:WorldToViewportPoint(hrp.Position)
                if onScreen and point.Z > 0 then
                    local d = (Vector2.new(point.X, point.Y) - mousePos).Magnitude
                    if d < bestDistance then
                        bestDistance = d
                        best = plr
                    end
                end
            end
        end
    end

    -- Fallback: nearest screen target around camera center.
    if not best then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player and sameTeam(plr) and plr.Character then
                local hrp = getPlayerRoot(plr)
                if hrp then
                    local point, onScreen = camera:WorldToViewportPoint(hrp.Position)
                    if onScreen and point.Z > 0 then
                        local d = (Vector2.new(point.X, point.Y) - center).Magnitude
                        if d < bestDistance then
                            bestDistance = d
                            best = plr
                        end
                    end
                end
            end
        end
    end

    return best
end

local function tryNetworkOwner(ball)
    if not ball or not ball:IsA("BasePart") then return nil end
    local ok, owner = pcall(function()
        return ball:GetNetworkOwner()
    end)
    if ok then return owner end
    return nil
end

local function updateOwnershipNotification(ball)
    if not ball then return end
    local owner = tryNetworkOwner(ball)
    if owner == player and lastOwnershipState ~= true then
        lastOwnershipState = true
        notify("PHYSICS CONTROL", "Ball network ownership = YOU", 2)
    elseif owner ~= player and owner ~= nil and lastOwnershipState ~= false then
        lastOwnershipState = false
        notify("PHYSICS CONTROL", "Ball network ownership changed", 1.4)
    end
end

--========================================================--
-- CONTROL / BALL KINEMATICS
--========================================================--

local function getFlatCameraDirections()
    camera = workspace.CurrentCamera
    if not camera then return Vector3.zAxis, Vector3.xAxis end

    local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
    local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)

    if forward.Magnitude > 0 then forward = forward.Unit end
    if right.Magnitude > 0 then right = right.Unit end
    return forward, right
end

local function getCameraDirection()
    camera = workspace.CurrentCamera
    if not camera then return Vector3.zAxis end
    local dir = camera.CFrame.LookVector
    if dir.Magnitude > 0 then dir = dir.Unit end
    return dir
end

local function controlMode1(ball)
    local forward, right = getFlatCameraDirections()
    local direction = Vector3.zero

    if keys.W then direction += forward end
    if keys.S then direction -= forward end
    if keys.D then direction += right end
    if keys.A then direction -= right end

    local velocity = ball.AssemblyLinearVelocity
    local horizontal = Vector3.zero
    if direction.Magnitude > 0 then
        horizontal = direction.Unit * modeSettings[1].speed
    end

    local vertical = velocity.Y
    if keys.E then
        vertical = modeSettings[1].speed
    elseif keys.Q then
        vertical = -modeSettings[1].speed
    end

    ball.AssemblyLinearVelocity = Vector3.new(horizontal.X, vertical, horizontal.Z)
end

local function controlMode2(ball)
    -- Mode 2: camera direction, không phụ thuộc trục X/Z cố định.
    local dir = getCameraDirection()
    ball.AssemblyLinearVelocity = dir * modeSettings[2].speed
end

local function makeCurvedVelocity(ball)
    camera = workspace.CurrentCamera
    local origin = ball.Position
    local direction = getCameraDirection()
    local height = modeSettings[3].height
    local curve = modeSettings[3].curve
    local speed = modeSettings[3].speed

    -- Điểm rơi nằm phía trước theo hướng camera. Height được dựng thẳng lên tại vị trí sút,
    -- không lấy height theo chiều camera.
    local horizontalDir = Vector3.new(direction.X, 0, direction.Z)
    if horizontalDir.Magnitude < 0.001 then
        horizontalDir = Vector3.new(0,0,-1)
    else
        horizontalDir = horizontalDir.Unit
    end

    local range = math.max(1, speed * 1.15)
    local target = origin + horizontalDir * range
    target += Vector3.new(0, height, 0)

    local toTarget = target - origin
    local distance = toTarget.Magnitude
    local base = toTarget.Unit * speed

    -- Curve tạo thành phần ngang vuông góc với hướng camera + một thành phần rơi/chống rơi.
    local side = Vector3.new(-horizontalDir.Z, 0, horizontalDir.X)
    local curveVector = side * curve
    return base + curveVector
end

local function performMode3Kick(ball)
    if not ball then return end
    local velocity = makeCurvedVelocity(ball)
    ball.AssemblyLinearVelocity = velocity
    notify("MODE 3", string.format("Height %.1f / Curve %.1f", modeSettings[3].height, modeSettings[3].curve), 1.8)
end

local function performMode4Kick(ball)
    if not ball then return end
    local direction = getCameraDirection()
    ball.AssemblyLinearVelocity = direction * modeSettings[4].speed
    -- Không có loop điều chỉnh sau cú này.
    notify("RONALDO MODE", "Velocity sent — no follow-up control", 1.8)
end

local function performControlAction()
    local state, holder, ball = getBallState()
    if not ball then
        notify("CONTROL", "Không tìm thấy bóng", 1.4)
        return
    end

    if mode == 1 then
        enabled = true
        applyModeLock()
        notify("CONTROL", "Mode 1 active", 1.2)
    elseif mode == 2 then
        enabled = true
        applyModeLock()
        cameraToBall(ball)
        notify("CONTROL", "Mode 2 active", 1.2)
    elseif mode == 3 then
        if localHasBall() then
            performMode3Kick(ball)
        else
            notify("MODE 3", "Cần đang cầm bóng", 1.4)
        end
    elseif mode == 4 then
        if localHasBall() then
            performMode4Kick(ball)
        else
            notify("MODE 4", "Cần đang cầm bóng", 1.4)
        end
    end
end

--========================================================--
-- STEAL BALL
--========================================================--

local function stealBallStep()
    if not stealBallEnabled then return end
    if not updateCharacter() or not rootPart then return end
    if localHasBall() then return end

    local state, holder, ball = getBallState()
    if state == "MISSING" then return end

    local targetRoot
    if holder and holder ~= player and not sameTeam(holder) then
        targetRoot = getPlayerRoot(holder)
    elseif not holder and ball then
        targetRoot = ball
    end

    if targetRoot then
        local destination = targetRoot.Position + Vector3.new(0, DEFAULT_STEAL_DISTANCE, 0)
        rootPart.CFrame = CFrame.new(destination)
        stealCooldown = 0
    end
end

--========================================================--
-- SAE PASS
--========================================================--

local function executeSaePass()
    if not saePassEnabled then return end
    if not selectedTarget or not getPlayerRoot(selectedTarget) then
        clearTarget()
        notify("SAE PASS", "Không còn target hợp lệ", 1.4)
        return
    end

    local state, holder, ball = getBallState()
    if not ball then return end

    -- Chỉ thực hiện cú Sae Pass khi local player thực sự đang giữ bóng.
    -- Đây chính là trường hợp holder == player; không được return ở đây.
    if holder ~= player then
        notify("SAE PASS", "Bạn phải đang cầm bóng để thực hiện Sae Pass", 1.4)
        return
    end

    local targetRoot = getPlayerRoot(selectedTarget)
    if not targetRoot then
        clearTarget()
        return
    end

    local startPosition = ball.Position
    saePassActive = true

    -- Giai đoạn 1: bóng đi thẳng đứng lên đúng ~300 studs tại vị trí sút.
    ball.CFrame = CFrame.new(startPosition + Vector3.new(0, SAE_PASS_HEIGHT, 0))
    ball.AssemblyLinearVelocity = Vector3.zero

    notify("SAE PASS", "Ball launched upward → " .. selectedTarget.Name, 1.5)

    -- Giai đoạn 2: sau khi lên cao, chuyển bóng tới đúng phía trên đầu target
    -- rồi để hệ thống Sae Pass tiếp tục điều khiển nó lao xuống target.
    task.delay(0.12, function()
        if not saePassActive or not selectedTarget or not ball or not ball.Parent then
            return
        end

        local currentTargetRoot = getPlayerRoot(selectedTarget)
        if not currentTargetRoot then
            clearTarget()
            return
        end

        local targetAbove = currentTargetRoot.Position + Vector3.new(0, SAE_PASS_HEIGHT, 0)
        ball.CFrame = CFrame.new(targetAbove)

        local desired = currentTargetRoot.Position + Vector3.new(0, 2.5, 0)
        local delta = desired - ball.Position
        if delta.Magnitude > 0 then
            ball.AssemblyLinearVelocity = delta.Unit * SAE_PASS_SPEED
        else
            ball.AssemblyLinearVelocity = Vector3.zero
        end
    end)
end

local function handleControlKeyPressed()
    local now = os.clock()
    if now - lastControlPress < 0.08 then return end
    lastControlPress = now

    if changingControlKey then return end

    if saePassEnabled and leftMouseHeld then
        if not selectedTarget then
            local target = getClosestTeammateToMouse()
            if target then
                highlightTarget(target)
            else
                notify("SAE PASS", "Không tìm thấy đồng đội", 1.4)
            end
        else
            executeSaePass()
        end
        return
    end

    performControlAction()
end

--========================================================--
-- BUTTON EVENTS
--========================================================--

controlButton.MouseButton1Click:Connect(function()
    changingControlKey = true
    controlButton.Text = "PRESS A KEY..."
    notify("CONTROL KEY", "Nhấn một phím mới (ESC = hủy)", 1.8)
end)

modeButton.MouseButton1Click:Connect(function()
    mode += 1
    if mode > 4 then mode = 1 end

    if mode == 3 or mode == 4 then
        -- Hai mode kick không cần anchor.
        if rootPart then rootPart.Anchored = false end
        unlockPlayer()
    end

    if enabled and mode == 2 then
        local ball = findBall()
        if ball then cameraToBall(ball) end
    elseif mode ~= 2 then
        restoreCamera()
    end

    applyModeLock()
    updateUI()
    notify("MODE", modeName(), 1.5)
end)

anchorButton.MouseButton1Click:Connect(function()
    anchorEnabled = not anchorEnabled
    if anchorEnabled then
        notify("ANCHOR", "Enabled — only Mode 1/2", 1.5)
    else
        notify("ANCHOR", "Disabled", 1.5)
    end
    applyModeLock()
    updateUI()
end)

forceUnanchorButton.MouseButton1Click:Connect(function()
    forceUnanchor()
    updateUI()
end)

stealButton.MouseButton1Click:Connect(function()
    stealBallEnabled = not stealBallEnabled
    notify("STEAL BALL", stealBallEnabled and "ON" or "OFF", 1.5)
    updateUI()
end)

saeButton.MouseButton1Click:Connect(function()
    saePassEnabled = not saePassEnabled
    if not saePassEnabled then clearTarget() end
    notify("SAE PASS", saePassEnabled and "ON" or "OFF", 1.5)
    updateUI()
end)

lockButton.MouseButton1Click:Connect(function()
    if playerWasLocked then
        forceUnanchor()
    else
        applyModeLock()
    end
    updateUI()
end)

--========================================================--
-- INPUT
--========================================================--

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        leftMouseHeld = true
        return
    end

    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

    if changingControlKey then
        if input.KeyCode == Enum.KeyCode.Escape then
            changingControlKey = false
            updateUI()
            return
        end
        if input.KeyCode ~= Enum.KeyCode.Unknown then
            controlKey = input.KeyCode
            changingControlKey = false
            updateUI()
            notify("CONTROL KEY", "Set to " .. controlKey.Name, 1.6)
        end
        return
    end

    -- Control key là ACTION key, không phải toggle enabled.
    if input.KeyCode == controlKey then
        handleControlKeyPressed()
        return
    end

    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.W then keys.W = true end
    if input.KeyCode == Enum.KeyCode.A then keys.A = true end
    if input.KeyCode == Enum.KeyCode.S then keys.S = true end
    if input.KeyCode == Enum.KeyCode.D then keys.D = true end
    if input.KeyCode == Enum.KeyCode.Q then keys.Q = true end
    if input.KeyCode == Enum.KeyCode.E then keys.E = true end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        leftMouseHeld = false
        return
    end

    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if input.KeyCode == Enum.KeyCode.W then keys.W = false end
    if input.KeyCode == Enum.KeyCode.A then keys.A = false end
    if input.KeyCode == Enum.KeyCode.S then keys.S = false end
    if input.KeyCode == Enum.KeyCode.D then keys.D = false end
    if input.KeyCode == Enum.KeyCode.Q then keys.Q = false end
    if input.KeyCode == Enum.KeyCode.E then keys.E = false end
end)

--========================================================--
-- HEARTBEAT
--========================================================--

RunService.Heartbeat:Connect(function(dt)
    updateCharacter()

    local state, holder, ball = getBallState()

    if state == "HELD" then
        ballStatus.Text = "BALL: HELD — " .. holder.Name
        if holder == player then
            ballStatus.TextColor3 = Color3.fromRGB(100,255,255)
        elseif sameTeam(holder) then
            ballStatus.TextColor3 = Color3.fromRGB(100,255,130)
        else
            ballStatus.TextColor3 = Color3.fromRGB(255,100,100)
        end
    elseif state == "FREE" then
        ballStatus.Text = "BALL: FREE"
        ballStatus.TextColor3 = Color3.fromRGB(255,215,100)
    else
        ballStatus.Text = "BALL: NOT FOUND"
        ballStatus.TextColor3 = Color3.fromRGB(255,100,100)
    end

    updateOwnershipNotification(ball)

    if holder ~= lastHolder then
        if holder == player and lastHolder ~= player then
            notify("BALL CONTROL", "Ball is now yours", 2)
        elseif lastHolder == player and holder ~= player then
            if selectedTarget == nil then
                notify("BALL CONTROL", "Ball left local player", 1.5)
            end
        end
        lastHolder = holder
    end

    if stealBallEnabled then
        stealCooldown += dt
        if stealCooldown >= 0.025 then
            stealBallStep()
            stealCooldown = 0
        end
    end

    -- Mode 1/2 are continuous control modes only while explicitly active.
    if enabled and ball then
        if mode == 1 then
            controlMode1(ball)
        elseif mode == 2 then
            controlMode2(ball)
        end
    end

    -- Sae Pass: bóng bay cao trước, sau đó hướng xuống target.
    if saePassActive and selectedTarget and ball then
        local targetRoot = getPlayerRoot(selectedTarget)
        if targetRoot and not localHasBall() then
            local desired = targetRoot.Position + Vector3.new(0, 2.5, 0)
            local delta = desired - ball.Position
            if delta.Magnitude > 6 then
                ball.AssemblyLinearVelocity = delta.Unit * SAE_PASS_SPEED
            else
                ball.AssemblyLinearVelocity = Vector3.zero
            end
        end
    end

    -- Highlight tắt nếu người khác nhận bóng hoặc target không còn hợp lệ.
    if saePassActive then
        if not selectedTarget or not selectedTarget.Parent then
            clearTarget()
        elseif holder and holder ~= player and holder == selectedTarget then
            clearTarget()
            notify("SAE PASS", "Target received the ball", 1.5)
        elseif holder and holder ~= player and holder ~= selectedTarget then
            clearTarget()
            notify("SAE PASS", "Another player received the ball", 1.5)
        end
    end

    if mode == 1 or mode == 2 then
        applyModeLock()
    else
        if rootPart and rootPart.Anchored then rootPart.Anchored = false end
    end
end)

--========================================================--
-- RESPAWN
--========================================================--

player.CharacterAdded:Connect(function()
    task.wait(0.5)
    updateCharacter()
    playerWasLocked = false
    savedWalkSpeed, savedJumpPower, savedAutoRotate = nil, nil, nil
    clearTarget()

    if enabled and (mode == 1 or mode == 2) and anchorEnabled then
        applyModeLock()
    else
        if rootPart then rootPart.Anchored = false end
        unlockPlayer()
    end

    updateUI()
end)

--========================================================--
-- INITIALIZE
--========================================================--

refreshSettingsPanel()
updateUI()
notify("BALL CONTROLLER", "V3 loaded", 1.8)
print("[Ball Controller V3] loaded")
