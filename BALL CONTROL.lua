--========================================================--
--                 BALL CONTROLLER V3                     --
--  Modes 2 & 4 / Steal Ball / Sae Pass / Ball Status UI   --
--========================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

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
local DEFAULT_TP_TIME = 1.5
local STEAL_SLIDE_INTERVAL = 0.12
local STEAL_SLIDE_DISTANCE = 12
local STEAL_TARGET_SCAN_INTERVAL = 0.08
local STEAL_UNSAFE_ATTRIBUTE_NAMES = {"Invincible","Ragdoll","Dancing","Cutscene","Stunned","Dangai","IchigoCounter"}
local STEAL_UNSAFE_ANIMATION_WORDS = {"counter","awakening","special","ultimate","skill","parry","block"}
local GK_ROLE_NAMES = {"gk", "goalkeeper", "goal keeper", "keeper"}
local GK_TP_OFFSET = Vector3.new(0, 2.5, 0)
local GK_DIVE_DELAY = 0.30
local GK_GOAL_RADIUS = 18
local GK_DIVE_COOLDOWN = 1.0
local GK_SPECIAL_DURATION = 0.35

local modeSettings = {
    [1] = { speed = 60 },
    [2] = { speed = 140 },
}

--========================================================--
-- STATE
-- Keep runtime state in one table to avoid Luau's 200-local-register limit.
local State = {
    mode = 1,
    controlKey = DEFAULT_CONTROL_KEY,
    enabled = false,
    anchorEnabled = true,
    forceUnanchorActive = false,
    stealBallEnabled = false,
    saePassEnabled = false,
    changingControlKey = false,
    leftMouseHeld = false,
    rightMouseHeld = false,
    minimized = false,
    settingsOpen = false,
    autoStealOffOnGet = true,

    selectedTarget = nil,
    saePassActive = false,
    saePassStage = "IDLE",
    saePassBall = nil,
    saePassTarget = nil,
    saePassTopY = nil,
    saePassPassSpeed = SAE_PASS_SPEED,
    saePassStartTime = 0,

    lastHolder = nil,
    lastOwnershipState = nil,
    stealCooldown = 0,
    stealSlideCooldown = 0,
    stealScanCooldown = 0,
    stealLastTarget = nil,

    gkSpecialEnabled = false,
    gkLastGoalPart = nil,
    gkDiveReadyAt = 0,
    gkSpecialReturnAt = 0,

    tpDuration = DEFAULT_TP_TIME,
    tpActive = false,
    tpStartedAt = 0,
    tpReturnCFrame = nil,
    tpGoalActive = false,
    tpFollowTarget = nil,
    tpFollowBall = nil,
    advanceMode = false,
    advanceKeys = {W=false,A=false,S=false,D=false,Q=false,E=false},
    advanceCameraOffset = Vector3.new(0, 7, 14),
}

-- NOTIFICATIONS
--========================================================--

local notificationHolder
local notify

notify = function(titleText, bodyText, duration)
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

    TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
        Position = UDim2.new(0.5,0,0,8)
    }):Play()

    task.delay(duration, function()
        if not card.Parent then return end
        TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Position = UDim2.new(0.5,0,0,-65)
        }):Play()
        task.delay(0.22, function()
            if card.Parent then card:Destroy() end
        end)
    end)
end

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
    if savedWalkSpeed == nil and humanoid.WalkSpeed > 0 then savedWalkSpeed = humanoid.WalkSpeed end
    if savedJumpPower == nil then savedJumpPower = humanoid.JumpPower end
    if savedAutoRotate == nil then savedAutoRotate = humanoid.AutoRotate end
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
        savedWalkSpeed, savedJumpPower, savedAutoRotate = nil,nil,nil
        return
    end
    if playerWasLocked then
        if savedWalkSpeed ~= nil then humanoid.WalkSpeed = savedWalkSpeed end
        if savedJumpPower ~= nil then humanoid.JumpPower = savedJumpPower end
        if savedAutoRotate ~= nil then humanoid.AutoRotate = savedAutoRotate end
    end
    playerWasLocked = false
    savedWalkSpeed, savedJumpPower, savedAutoRotate = nil,nil,nil
end

local function applyModeLock()
    if not updateCharacter() then return end
    if State.forceUnanchorActive then
        rootPart.Anchored = false
        unlockPlayer()
        return
    end
    if State.enabled and State.anchorEnabled and State.mode == 1 then
        savePlayerState()
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        humanoid.AutoRotate = false
        rootPart.Anchored = true
        playerWasLocked = true
    else
        rootPart.Anchored = false
        unlockPlayer()
    end
end

local function forceUnanchor()
    State.forceUnanchorActive = true
    updateCharacter()
    if rootPart then rootPart.Anchored = false end
    unlockPlayer()
    notify("ANCHOR", "Force Unanchor executed", 1.5)
end

--========================================================--
-- BALL HELPERS
--========================================================--

local playerBallCache = {}
local cacheScanAt = {}
local CACHE_INTERVAL = 0.12

local function isMatchPlayer(plr)
    if not plr or not plr.Team then return false end
    local n = string.lower(plr.Team.Name)
    return string.find(n,"home",1,true) ~= nil or string.find(n,"away",1,true) ~= nil
end

local function scanCharacterForBall(plr, force)
    if not plr or not plr.Character then return nil end
    local now = os.clock()
    if not force and cacheScanAt[plr] and now - cacheScanAt[plr] < CACHE_INTERVAL then
        local cached = playerBallCache[plr]
        if cached and cached.Parent then return cached end
        if cached == false then return nil end
    end

    local found = plr.Character:FindFirstChild(BALL_NAME, true)
    if found and found:IsA("BasePart") then
        playerBallCache[plr] = found
        cacheScanAt[plr] = now
        return found
    end

    playerBallCache[plr] = false
    cacheScanAt[plr] = now
    return nil
end

local function findBallHolder()
    -- Chỉ quét model Character của người chơi.
    for _,plr in ipairs(Players:GetPlayers()) do
        if isMatchPlayer(plr) then
            local ball = scanCharacterForBall(plr, false)
            if ball then return plr, ball end
        end
    end
    return nil,nil
end

local function findFreeBall()
    -- Ưu tiên ball vừa thấy trong character / Workspace trực tiếp.
    local direct = workspace:FindFirstChild(BALL_NAME)
    if direct and direct:IsA("BasePart") then return direct end

    -- Chỉ fallback quét Workspace khi trạng thái trước đó là missing/free
    -- và không có ball trong player models.
    for _,obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("BasePart") and string.lower(obj.Name) == string.lower(BALL_NAME) then
            return obj
        end
    end
    return nil
end

local function findBall()
    local holder,heldBall = findBallHolder()
    if heldBall then return heldBall end
    return findFreeBall()
end

local function getBallState()
    local holder,heldBall = findBallHolder()
    if holder then return "HELD",holder,heldBall end
    local freeBall = findFreeBall()
    if freeBall then return "FREE",nil,freeBall end
    return "MISSING",nil,nil
end

local function localHasBall()
    -- Local player là trường hợp quan trọng nhất cho Steal Ball.
    -- Force refresh riêng Character của local player để không bị cache cũ
    -- làm Steal Ball tiếp tục chạy sau khi vừa nhặt bóng.
    local ball = scanCharacterForBall(player, true)
    return ball ~= nil
end

local function getPlayerRoot(plr)
    if not plr or not plr.Character then return nil end
    return plr.Character:FindFirstChild("HumanoidRootPart")
end

local function sameTeam(plr)
    return plr and player.Team and plr.Team == player.Team
end

--========================================================--
-- SHOOT REMOTE
--========================================================--

local shootBallRemote
local shootRemoteReady = false

local function resolveShootRemotes()
    local ok,remote = pcall(function()
        local events = ReplicatedStorage:FindFirstChild("Events")
        return events and events:FindFirstChild("ShootBall")
    end)
    shootBallRemote = ok and remote or nil
    shootRemoteReady = shootBallRemote ~= nil and shootBallRemote:IsA("RemoteEvent")
    return shootBallRemote
end

resolveShootRemotes()

local function fireShootRemote(direction,force,thirdArg)
    if not shootRemoteReady or not shootBallRemote then resolveShootRemotes() end
    if not shootRemoteReady or not shootBallRemote then
        notify("SHOOT REMOTE","Không tìm thấy Events.ShootBall",1.5)
        return false
    end
    if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.001 then return false end
    direction = direction.Unit
    force = math.clamp(tonumber(force) or MIN_SPEED,MIN_SPEED,MAX_SPEED)
    return pcall(function()
        shootBallRemote:FireServer(direction,force,thirdArg == nil and false or thirdArg)
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

local function corner(parent,radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,radius or 8)
    c.Parent = parent
    return c
end

local function stroke(parent,color,transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(60,60,70)
    s.Transparency = transparency or 0.2
    s.Parent = parent
    return s
end

local function makeButton(parent,text,x,y,w,h)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w,h)
    b.Position = UDim2.fromOffset(x,y)
    b.BackgroundColor3 = Color3.fromRGB(43,43,51)
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.fromRGB(235,235,240)
    b.TextSize = 12
    b.Font = Enum.Font.GothamMedium
    b.Parent = parent
    corner(b,7)
    return b
end

local function makeLabel(parent,text,x,y,w,h,size)
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

local function makeBox(parent,value,x,y,w,h)
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
main.Size = UDim2.fromOffset(350,445)
main.Position = UDim2.new(0,25,0.5,-222)
main.BackgroundColor3 = Color3.fromRGB(24,24,29)
main.BorderSizePixel = 0
main.Parent = gui
corner(main,12)
stroke(main,Color3.fromRGB(60,60,70),0.2)

local title = makeLabel(main,"⚽  BALL CONTROLLER V3",10,5,260,35,18)
title.Font = Enum.Font.GothamBold
local minimizeButton = makeButton(main,"—",312,10,28,28)
minimizeButton.TextSize = 18
local statusLabel = makeLabel(main,"Status: READY",10,42,320,22,13)
local ballStatus = makeLabel(main,"BALL: SEARCHING...",10,64,320,22,12)

local controlButton = makeButton(main,"CONTROL KEY: F",10,92,160,36)
local modeButton = makeButton(main,"MODE: 1 [CAMERA]",180,92,160,36)
local anchorButton = makeButton(main,"ANCHOR: ON",10,136,160,36)
local forceUnanchorButton = makeButton(main,"FORCE UNANCHOR",180,136,160,36)
local stealButton = makeButton(main,"STEAL BALL: OFF",10,180,160,36)
local saeButton = makeButton(main,"SAE PASS: OFF",180,180,160,36)
local settingsButton = makeButton(main,"⚙ SETTINGS",10,224,160,36)
local statusButton = makeButton(main,"BALL STATUS: ON",180,224,160,36)
local tpButton = makeButton(main,"TP RETURN",10,268,150,36)
local tpGoalButton = makeButton(main,"TP GOAL",170,268,170,36)
local tpTimeBox = makeBox(main,State.tpDuration,250,310,90,36)

local info = makeLabel(main,
    "F = action theo mode.\n"..
    "Mode 1: bật/tắt control; bóng chạy theo camera.\n"..
    "Mode 2: F để sút một lần theo camera.\n"..
    "SAE Pass Mode 1 = rise + chase; Mode 2 = direct hold.\n"..
    "GK: TP RETURN → GoalArea + Q dive → tự bám người cầm bóng.\n"..
    "Barou: Steal Ball không quan tâm đồng đội.",
    10,350,330,70,11)
info.TextWrapped = true
info.TextYAlignment = Enum.TextYAlignment.Top
info.TextColor3 = Color3.fromRGB(145,145,155)

local restoreButton = makeButton(gui,"⚽",0,0,48,48)
restoreButton.Visible = false
restoreButton.TextSize = 23
corner(restoreButton,24)
stroke(restoreButton,Color3.fromRGB(65,65,75),0.1)

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
-- BALL STATUS FLOATING UI
--========================================================--

local statusPanel = Instance.new("Frame")
statusPanel.Name = "BallStatusPanel"
statusPanel.Size = UDim2.fromOffset(245,125)
statusPanel.Position = UDim2.new(0,390,0,80)
statusPanel.BackgroundColor3 = Color3.fromRGB(22,22,27)
statusPanel.BorderSizePixel = 0
statusPanel.Parent = gui
corner(statusPanel,10)
stroke(statusPanel,Color3.fromRGB(60,60,70),0.15)

local statusTitle = makeLabel(statusPanel,"⚽ BALL STATUS",10,5,170,25,14)
statusTitle.Font = Enum.Font.GothamBold
local statusMin = makeButton(statusPanel,"—",180,6,25,23)
local statusClose = makeButton(statusPanel,"×",210,6,25,23)
local statusState = makeLabel(statusPanel,"STATUS: SEARCHING",10,35,220,22,12)
local statusOwner = makeLabel(statusPanel,"OWNER: —",10,58,220,22,12)
local statusPlayer = makeLabel(statusPanel,"CONTROL: OFF",10,81,220,22,12)
local statusMini = false
local statusExpandedSize = UDim2.fromOffset(245,125)
local statusMiniSize = UDim2.fromOffset(245,34)

local function clampGuiPosition(frame)
    local viewport = camera and camera.ViewportSize or Vector2.new(1920,1080)
    local size = frame.AbsoluteSize
    local x = math.clamp(frame.AbsolutePosition.X,0,math.max(0,viewport.X-size.X))
    local y = math.clamp(frame.AbsolutePosition.Y,0,math.max(0,viewport.Y-size.Y))
    frame.Position = UDim2.fromOffset(x,y)
end

local function setStatusMini(value)
    statusMini = value
    statusPanel.Size = value and statusMiniSize or statusExpandedSize
    statusState.Visible = not value
    statusOwner.Visible = not value
    statusPlayer.Visible = not value
    statusMin.Text = value and "+" or "—"
    task.defer(function() clampGuiPosition(statusPanel) end)
end

statusMin.MouseButton1Click:Connect(function() setStatusMini(not statusMini) end)
statusClose.MouseButton1Click:Connect(function()
    statusPanel.Visible = false
    statusButton.Text = "BALL STATUS: OFF"
end)

local draggingStatus = false
local dragStartStatus
local dragStartPositionStatus
statusTitle.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    draggingStatus = true
    dragStartStatus = input.Position
    dragStartPositionStatus = statusPanel.Position
    input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then draggingStatus = false end
    end)
end)
UserInputService.InputChanged:Connect(function(input)
    if not draggingStatus or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = input.Position - dragStartStatus
    local x = dragStartPositionStatus.X.Offset + delta.X
    local y = dragStartPositionStatus.Y.Offset + delta.Y
    local viewport = camera and camera.ViewportSize or Vector2.new(1920,1080)
    x = math.clamp(x,0,math.max(0,viewport.X-statusPanel.AbsoluteSize.X))
    y = math.clamp(y,0,math.max(0,viewport.Y-statusPanel.AbsoluteSize.Y))
    statusPanel.Position = UDim2.fromOffset(x,y)
end)


--========================================================--
-- SETTINGS PANEL
--========================================================--

local settingsFrame = Instance.new("Frame")
settingsFrame.Name = "Settings"
settingsFrame.Size = UDim2.fromOffset(490,320)
settingsFrame.Position = UDim2.new(0,390,0.5,-160)
settingsFrame.BackgroundColor3 = Color3.fromRGB(22,22,27)
settingsFrame.BorderSizePixel = 0
settingsFrame.Visible = false
settingsFrame.Parent = gui
corner(settingsFrame,12)
stroke(settingsFrame,Color3.fromRGB(60,60,70),0.15)

local settingsTitle = makeLabel(settingsFrame,"⚙ BALL SETTINGS",12,8,270,32,17)
settingsTitle.Font = Enum.Font.GothamBold
local closeSettings = makeButton(settingsFrame,"X",480,8,28,28)

local tabs = {}
local tabNames = {"GENERAL","MODE 1","MODE 2"}
for i,name in ipairs(tabNames) do
    tabs[i] = makeButton(settingsFrame,name,10+(i-1)*110,48,104,30)
end

local settingsContent = Instance.new("Frame")
settingsContent.Size = UDim2.new(1,-20,1,-90)
settingsContent.Position = UDim2.fromOffset(10,88)
settingsContent.BackgroundTransparency = 1
settingsContent.Parent = settingsFrame

-- GENERAL TAB
local generalTitle = makeLabel(settingsContent,"GENERAL SETTINGS",10,8,220,24,13)
generalTitle.Font = Enum.Font.GothamBold
local generalControlLabel = makeLabel(settingsContent,"CONTROL KEY",10,38,110,25,12)
local generalControlButton = makeButton(settingsContent,"F",120,34,120,32)
local generalAnchorLabel = makeLabel(settingsContent,"ANCHOR",10,78,110,25,12)
local generalAnchorButton = makeButton(settingsContent,"ON",120,74,120,32)
local generalAutoStealLabel = makeLabel(settingsContent,"AUTO STEAL OFF",10,118,110,25,12)
local generalAutoStealButton = makeButton(settingsContent,"ON",120,114,120,32)
local generalTPLabel = makeLabel(settingsContent,"TP RETURN TIME",10,158,110,25,12)
local generalTPBox = makeBox(settingsContent,State.tpDuration,120,154,120,32)
local generalHint = makeLabel(settingsContent,"General: các thiết lập dùng chung. Nếu Role = GK, TP RETURN sẽ về GoalArea của đội và tự mô phỏng Q (dive). CharacterName = Barou sẽ cho phép Steal Ball đuổi cả đồng đội.",10,205,440,55,11)
generalHint.TextWrapped=true
generalHint.TextColor3=Color3.fromRGB(145,145,155)

local mode1Label = makeLabel(settingsContent,"SPEED",10,10,110,25,12)
local mode1Box = makeBox(settingsContent,modeSettings[1].speed,120,6,220,32)
local mode1Hint = makeLabel(settingsContent,"Mode 1: bóng chạy liên tục theo hướng camera khi control đang ACTIVE.",10,70,440,80,11)
mode1Hint.TextWrapped=true
mode1Hint.TextColor3=Color3.fromRGB(145,145,155)
local mode1AdvanceLabel = makeLabel(settingsContent,"ADVANCE MODE",10,120,110,25,12)
local mode1AdvanceButton = makeButton(settingsContent,"OFF",120,116,120,32)
local mode1AdvanceHint = makeLabel(settingsContent,"Advance Mode: camera bám trực tiếp vào bóng; WASD cho bóng đi theo hướng camera, Q/E tăng giảm độ cao theo trục Y.",10,160,440,55,11)
mode1AdvanceHint.TextWrapped=true
mode1AdvanceHint.TextColor3=Color3.fromRGB(145,145,155)

local mode2Label = makeLabel(settingsContent,"SPEED",10,10,110,25,12)
local mode2Box = makeBox(settingsContent,modeSettings[2].speed,120,6,220,32)
local mode2Hint = makeLabel(settingsContent,"Mode 2: dùng Events.ShootBall một lần; script không loop ép velocity sau cú sút.",10,70,440,80,11)
mode2Hint.TextWrapped=true
mode2Hint.TextColor3=Color3.fromRGB(145,145,155)

local selectedSettingsTab = 1

local function parseSetting(box,oldValue,minValue,maxValue)
    local n = tonumber(box.Text)
    if not n then box.Text=tostring(oldValue); return oldValue end
    n=math.clamp(n,minValue,maxValue)
    box.Text=tostring(n)
    return n
end

local function setGeneralControls()
    generalControlButton.Text=State.controlKey.Name
    generalAnchorButton.Text=State.anchorEnabled and "ON" or "OFF"
    generalAutoStealButton.Text=State.autoStealOffOnGet and "ON" or "OFF"
    generalTPBox.Text=tostring(State.tpDuration)
end

local function refreshSettingsPanel()
    local general=selectedSettingsTab==1
    local mode1=selectedSettingsTab==2
    local mode2=selectedSettingsTab==3

    generalTitle.Visible=general
    generalControlLabel.Visible=general
    generalControlButton.Visible=general
    generalAnchorLabel.Visible=general
    generalAnchorButton.Visible=general
    generalAutoStealLabel.Visible=general
    generalAutoStealButton.Visible=general
    generalTPLabel.Visible=general
    generalTPBox.Visible=general
    generalHint.Visible=general

    mode1Label.Visible=mode1
    mode1Box.Visible=mode1
    mode1Hint.Visible=mode1
    mode1AdvanceLabel.Visible=mode1
    mode1AdvanceButton.Visible=mode1
    mode1AdvanceHint.Visible=mode1
    mode2Label.Visible=mode2
    mode2Box.Visible=mode2
    mode2Hint.Visible=mode2

    setGeneralControls()
    mode1AdvanceButton.Text=State.advanceMode and "ON" or "OFF"
end

for i=1,3 do
    tabs[i].MouseButton1Click:Connect(function()
        selectedSettingsTab=i
        refreshSettingsPanel()
    end)
end

generalControlButton.MouseButton1Click:Connect(function()
    State.changingControlKey=true
    generalControlButton.Text="PRESS KEY"
    notify("CONTROL KEY","Nhấn phím mới (ESC = hủy)",1.6)
end)

generalAnchorButton.MouseButton1Click:Connect(function()
    State.anchorEnabled=not State.anchorEnabled
    State.forceUnanchorActive=false
    anchorButton.Text=State.anchorEnabled and "ANCHOR: ON" or "ANCHOR: OFF"
    if State.anchorEnabled and State.enabled and State.mode==1 then
        applyModeLock()
    else
        unlockPlayer()
        if rootPart then rootPart.Anchored=false end
    end
    setGeneralControls()
end)

generalAutoStealButton.MouseButton1Click:Connect(function()
    State.autoStealOffOnGet=not State.autoStealOffOnGet
    setGeneralControls()
    notify("AUTO STEAL",State.autoStealOffOnGet and "OFF ON GET: ON" or "OFF ON GET: OFF",1.1)
end)

generalTPBox.FocusLost:Connect(function()
    local value=tonumber(generalTPBox.Text)
    if not value then generalTPBox.Text=tostring(State.tpDuration); return end
    State.tpDuration=math.clamp(value,0.1,60)
    generalTPBox.Text=tostring(State.tpDuration)
    tpTimeBox.Text=tostring(State.tpDuration)
end)

mode1Box.FocusLost:Connect(function()
    modeSettings[1].speed=parseSetting(mode1Box,modeSettings[1].speed,MIN_SPEED,MAX_SPEED)
end)

local function setAdvanceMode(value)
    State.advanceMode=value and true or false
    mode1AdvanceButton.Text=State.advanceMode and "ON" or "OFF"
    State.advanceKeys={W=false,A=false,S=false,D=false,Q=false,E=false}
    if State.advanceMode then
        State.advanceCameraOffset=Vector3.new(0,7,14)
        if State.mode==1 and State.enabled then
            camera=workspace.CurrentCamera
            if camera then camera.CameraType=Enum.CameraType.Scriptable end
        end
    else
        State.advanceCameraOffset=Vector3.new(0,7,14)
        if State.mode==1 and State.enabled then
            local ball=findBall()
            if ball then cameraToBall(ball) else restoreCamera() end
        end
    end
end

mode1AdvanceButton.MouseButton1Click:Connect(function()
    setAdvanceMode(not State.advanceMode)
    notify("ADVANCE MODE",State.advanceMode and "ON" or "OFF",1.2)
end)

mode2Box.FocusLost:Connect(function()
    modeSettings[2].speed=parseSetting(mode2Box,modeSettings[2].speed,MIN_SPEED,MAX_SPEED)
end)

tpTimeBox.FocusLost:Connect(function()
    local value=tonumber(tpTimeBox.Text)
    if not value then tpTimeBox.Text=tostring(State.tpDuration); return end
    State.tpDuration=math.clamp(value,0.1,60)
    tpTimeBox.Text=tostring(State.tpDuration)
    generalTPBox.Text=tostring(State.tpDuration)
end)

-- DRAG MAIN / SETTINGS
--========================================================--

local function makeDraggable(object,handle,clampToScreen)
    local dragging=false
    local dragStart,startPosition
    handle.InputBegan:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        dragging=true; dragStart=input.Position; startPosition=object.Position
        input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then dragging=false end
        end)
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging or input.UserInputType~=Enum.UserInputType.MouseMovement then return end
        local delta=input.Position-dragStart
        local x=startPosition.X.Offset+delta.X
        local y=startPosition.Y.Offset+delta.Y
        if clampToScreen then
            local viewport=camera.ViewportSize
            x=math.clamp(x,0,math.max(0,viewport.X-object.AbsoluteSize.X))
            y=math.clamp(y,0,math.max(0,viewport.Y-object.AbsoluteSize.Y))
        end
        object.Position=UDim2.new(startPosition.X.Scale,x,startPosition.Y.Scale,y)
    end)
end

makeDraggable(main,title,true)
makeDraggable(settingsFrame,settingsTitle,true)
makeDraggable(restoreButton,restoreButton,true)

--========================================================--
-- CAMERA
--========================================================--

local savedCameraType
local savedCameraSubject

local function saveCamera(ballSubject)
    camera=workspace.CurrentCamera
    if not camera then return end
    if savedCameraType==nil then savedCameraType=camera.CameraType end
    if camera.CameraSubject and camera.CameraSubject~=ballSubject and savedCameraSubject==nil then
        savedCameraSubject=camera.CameraSubject
    end
end

local function cameraToBall(ball)
    if not ball then return end
    camera=workspace.CurrentCamera
    if not camera then return end
    saveCamera(ball)
    camera.CameraType=Enum.CameraType.Custom
    camera.CameraSubject=ball
end

local function restoreCamera()
    camera=workspace.CurrentCamera
    if not camera then return end
    updateCharacter()
    camera.CameraType=savedCameraType or Enum.CameraType.Custom
    camera.CameraSubject=humanoid or savedCameraSubject
    savedCameraType=nil
    savedCameraSubject=nil
end

--========================================================--
-- DIRECTIONS
--========================================================--

local function getFlatCameraDirections()
    camera=workspace.CurrentCamera
    if not camera then return Vector3.new(0,0,-1),Vector3.new(1,0,0) end
    local f=Vector3.new(camera.CFrame.LookVector.X,0,camera.CFrame.LookVector.Z)
    local r=Vector3.new(camera.CFrame.RightVector.X,0,camera.CFrame.RightVector.Z)
    if f.Magnitude>0 then f=f.Unit end
    if r.Magnitude>0 then r=r.Unit end
    return f,r
end

local function getCameraDirection()
    camera=workspace.CurrentCamera
    if not camera then return Vector3.new(0,0,-1) end
    local d=camera.CFrame.LookVector
    return d.Magnitude>0 and d.Unit or Vector3.new(0,0,-1)
end

--========================================================--
-- ADVANCE MODE CAMERA
--========================================================--

local function updateAdvanceCamera(ball,dt)
    if not State.advanceMode or not State.enabled or not ball then return false end
    camera=workspace.CurrentCamera
    if not camera then return false end

    -- Advance Mode = Mode 1 cũ nhưng camera bám trực tiếp vào bóng.
    -- WASD: di chuyển theo hướng camera (mặt phẳng XZ).
    -- Q/E: tăng/giảm độ cao theo đúng trục Y.
    camera.CameraType=Enum.CameraType.Custom
    camera.CameraSubject=ball

    local f,r=getFlatCameraDirections()
    local move=Vector3.zero

    if State.advanceKeys.W then move+=f end
    if State.advanceKeys.S then move-=f end
    if State.advanceKeys.D then move+=r end
    if State.advanceKeys.A then move-=r end
    if State.advanceKeys.E then move+=Vector3.new(0,1,0) end
    if State.advanceKeys.Q then move-=Vector3.new(0,1,0) end

    local speed=math.clamp(modeSettings[1].speed,MIN_SPEED,MAX_SPEED)
    if move.Magnitude>0 then
        ball.AssemblyLinearVelocity=move.Unit*speed
    else
        -- Không nhấn phím: giữ bóng tại độ cao hiện tại thay vì để rơi.
        ball.AssemblyLinearVelocity=Vector3.zero
    end

    return true
end

--========================================================--
-- MODE 1
--========================================================--

local function controlMode1(ball)
    if not ball then return end
    local dir=getCameraDirection()
    ball.AssemblyLinearVelocity=dir*math.clamp(modeSettings[1].speed,MIN_SPEED,MAX_SPEED)
end

-- MODE 2 (RONALDO / OLD MODE 4 BEHAVIOR)
--========================================================--

local function performMode4Kick(ball)
    if not ball then return end
    local direction=getCameraDirection()
    local force=math.clamp(modeSettings[2].speed,MIN_SPEED,MAX_SPEED)

    -- Mode 2 must let the game's ShootBall remote perform the release.
    -- Directly forcing AssemblyLinearVelocity here can leave a held/welded
    -- ball visually attached to the player instead of being released.
    if fireShootRemote(direction,force,false) then
        notify("RONALDO MODE","ShootBall velocity sent",1.4)
    end
end

--========================================================--
-- SAE PASS
-- Hold LMB + F = select target.
-- Release LMB = launch to selected target.
-- Press F again while target is selected = launch immediately.
--========================================================--

local targetHighlight

local function clearTarget()
    State.selectedTarget=nil
    State.saePassActive=false
    State.saePassStage="IDLE"
    State.saePassBall=nil
    State.saePassTarget=nil
    if targetHighlight then targetHighlight:Destroy(); targetHighlight=nil end
end

local function highlightTarget(plr)
    if targetHighlight then targetHighlight:Destroy() end
    State.selectedTarget=plr
    if not plr or not plr.Character then return end
    targetHighlight=Instance.new("Highlight")
    targetHighlight.Name="SaePassTarget"
    targetHighlight.FillTransparency=0.45
    targetHighlight.OutlineTransparency=0
    targetHighlight.Adornee=plr.Character
    targetHighlight.Parent=plr.Character
    notify("SAE PASS TARGET",plr.Name,1.4)
end

local function getClosestTeammateToMouse()
    camera=workspace.CurrentCamera
    if not camera then return nil end
    local mouse=UserInputService:GetMouseLocation()
    local best,bestDistance=nil,math.huge
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr~=player and sameTeam(plr) and plr.Character then
            local hrp=getPlayerRoot(plr)
            if hrp then
                local point,onScreen=camera:WorldToViewportPoint(hrp.Position)
                if onScreen and point.Z>0 then
                    local d=(Vector2.new(point.X,point.Y)-mouse).Magnitude
                    if d<bestDistance then bestDistance=d; best=plr end
                end
            end
        end
    end
    return best
end

local function startSaePass(ball,target)
    if not ball or not target then return false end
    if not localHasBall() then
        clearTarget()
        notify("SAE PASS","Cần đang cầm bóng",1.2)
        return false
    end

    local targetRoot=getPlayerRoot(target)
    if not targetRoot then return false end

    State.saePassActive=true
    State.saePassBall=ball
    State.saePassTarget=target
    State.saePassPassSpeed=math.clamp(
        (State.mode==1 and modeSettings[1].speed or modeSettings[2].speed),
        MIN_SPEED,
        MAX_SPEED
    )
    State.saePassStartTime=os.clock()

    if State.mode==2 then
        -- SAE PASS MODE 2: direct move/hold at the receiver until they actually receive it.
        State.saePassStage="DIRECT"
        ball.CFrame=CFrame.new(targetRoot.Position+Vector3.new(0,2.5,0))
        ball.AssemblyLinearVelocity=Vector3.zero
        notify("SAE PASS","MODE 2 DIRECT → "..target.Name,1.3)
    else
        -- SAE PASS MODE 1: rise first, then continuously steer toward the moving receiver.
        State.saePassStage="RISING"
        local riseForce=math.clamp(SAE_PASS_SPEED*0.32,MIN_SPEED,MAX_SPEED)
        fireShootRemote(Vector3.new(0,1,0),riseForce,false)
        State.saePassTopY=ball.Position.Y+math.min(SAE_PASS_HEIGHT,90)
        notify("SAE PASS","MODE 1 RISING → "..target.Name,1.3)
    end

    if targetHighlight then targetHighlight.FillTransparency=0.85 end
    return true
end

local function updateSaePass()
    if not State.saePassActive then return end
    local ball=State.saePassBall
    local target=State.saePassTarget
    if not ball or not ball.Parent or not target or not target.Parent then
        clearTarget()
        return
    end

    local targetRoot=getPlayerRoot(target)
    if not targetRoot then
        clearTarget()
        return
    end

    -- IMPORTANT: do not clear merely because localHasBall() is still true on the
    -- first frames. The server may release the ball a few frames after the remote.
    -- We keep the pass state alive until the target actually receives it.

    if State.saePassStage=="DIRECT" then
        if not localHasBall() then
            ball.CFrame=CFrame.new(targetRoot.Position+Vector3.new(0,2.5,0))
            ball.AssemblyLinearVelocity=Vector3.zero
        end
        return
    end

    if State.saePassStage=="RISING" then
        if ball.Position.Y<State.saePassTopY then
            ball.AssemblyLinearVelocity=Vector3.new(0,math.max(90,State.saePassPassSpeed*0.45),0)
            return
        end
        State.saePassStage="TRAVEL"
    end

    if State.saePassStage=="TRAVEL" then
        local targetPos=targetRoot.Position+Vector3.new(0,2.5,0)
        local delta=targetPos-ball.Position
        local distance=delta.Magnitude
        if distance<=10 then
            local slowSpeed=math.clamp(distance*4,20,State.saePassPassSpeed)
            ball.AssemblyLinearVelocity=(distance>0.05 and delta.Unit or Vector3.zero)*slowSpeed
        else
            ball.AssemblyLinearVelocity=delta.Unit*State.saePassPassSpeed
        end
    end
end

local function selectSaePassTarget()
    local state,holder=getBallState()
    if holder~=player or state~="HELD" then
        notify("SAE PASS","Cần đang cầm bóng",1.2)
        return false
    end

    local target=getClosestTeammateToMouse()
    if not target then
        notify("SAE PASS","Không tìm thấy đồng đội",1.3)
        return false
    end

    highlightTarget(target)
    return true
end

local function launchSelectedSaePass()
    if not State.selectedTarget then
        notify("SAE PASS","Giữ chuột trái + F để chọn target",1.3)
        return false
    end

    local _,_,ball=getBallState()
    if not ball then
        clearTarget()
        notify("SAE PASS","Không tìm thấy bóng",1.2)
        return false
    end

    return startSaePass(ball,State.selectedTarget)
end

--========================================================--
-- GK HELPERS
--========================================================--

local function getCharacterNameValue()
    local values=player:FindFirstChild("Values")
    local valueObj=values and values:FindFirstChild("CharacterName")
    if valueObj and valueObj.Value ~= nil then
        return tostring(valueObj.Value)
    end
    return ""
end

local function localIsBarou()
    return string.lower(getCharacterNameValue()) == "barou"
end

local function getRoleName()
    local roleObj=player:FindFirstChild("Role")
    if roleObj and roleObj.Value ~= nil then
        return string.lower(tostring(roleObj.Value))
    end

    local values=player:FindFirstChild("Values")
    local valuesRole=values and values:FindFirstChild("Role")
    if valuesRole and valuesRole.Value ~= nil then
        return string.lower(tostring(valuesRole.Value))
    end

    if character then
        local charRole=character:FindFirstChild("Role")
        if charRole and charRole.Value ~= nil then
            return string.lower(tostring(charRole.Value))
        end
    end

    return ""
end

local function localIsGoalkeeper()
    local role=string.gsub(getRoleName(),"%s+"," ")
    for _,name in ipairs(GK_ROLE_NAMES) do
        if role == name then
            return true
        end
    end
    return false
end

local function getTeamIsHome()
    return player.Team and string.lower(player.Team.Name)=="home"
end

local function resolveGoalHitboxForTeam(homeSide)
    local map=workspace:FindFirstChild("Map")
    if not map then return nil end

    local goalName=homeSide and "PlayerOneGoal" or "PlayerTwoGoal"
    local goalModel=map:FindFirstChild(goalName)
    if not goalModel then return nil end

    local score=goalModel:FindFirstChild("ScoreHitbox") or goalModel:FindFirstChild("Score")
    if score and score:IsA("BasePart") then
        return score
    end

    local hitbox=goalModel:FindFirstChild("ScoreHitbox",true)
    if hitbox and hitbox:IsA("BasePart") then
        return hitbox
    end

    local firstPart=goalModel:FindFirstChildWhichIsA("BasePart",true)
    return firstPart
end

local function resolveGoalAreaForTeam(homeSide)
    local goalName=homeSide and "PlayerOneGoalArea" or "PlayerTwoGoalArea"
    local goal=workspace:FindFirstChild(goalName)
    if not goal then return nil end
    if goal:IsA("BasePart") then return goal end
    if goal:IsA("Model") then
        if goal.PrimaryPart then return goal.PrimaryPart end
        return goal:FindFirstChildWhichIsA("BasePart",true)
    end
    return nil
end

local function resolveOwnGoalPart()
    local isHome=getTeamIsHome()
    return resolveGoalAreaForTeam(isHome) or resolveGoalHitboxForTeam(isHome)
end

local function resolveOpponentGoalHitbox()
    local isHome=getTeamIsHome()
    return resolveGoalHitboxForTeam(not isHome)
end

local function sendVirtualKey(keyCode)
    if not VirtualInputManager then return false end
    return pcall(function()
        VirtualInputManager:SendKeyEvent(true,keyCode,false,game)
        task.wait()
        VirtualInputManager:SendKeyEvent(false,keyCode,false,game)
    end)
end

local function isInsideGoalArea(position, goalPart)
    if not position or not goalPart then return false end
    return (position-goalPart.Position).Magnitude <= GK_GOAL_RADIUS
end

local function getCurrentBallTarget()
    local state,holder,ball=getBallState()

    if state=="HELD" and holder and holder~=player then
        local targetRoot=getPlayerRoot(holder)
        if targetRoot then
            return targetRoot,holder
        end
    end

    if state=="FREE" and ball and ball.Parent then
        return ball,nil
    end

    return nil,nil
end

local function getGKDiveCooldownRemaining()
    return math.max(0, (State.gkDiveReadyAt or 0)-os.clock())
end

local function performGKTPReturn()
    if not localIsGoalkeeper() or not updateCharacter() or not rootPart then
        return false
    end

    local goalPart=resolveOwnGoalPart()
    if not goalPart then
        notify("GK RETURN","Không tìm thấy GoalArea của đội",1.5)
        return false
    end

    -- GK flow is intentionally independent from Steal Ball/target safety checks.
    -- Only the dive cooldown is respected.
    local cooldown=getGKDiveCooldownRemaining()
    if cooldown>0 then
        notify("GK RETURN",string.format("Dive đang hồi %.1fs",cooldown),1.0)
        return false
    end

    State.gkLastGoalPart=goalPart
    State.gkSpecialEnabled=true

    -- Nếu đang ngoài khu GK thì đưa vào trước. Nếu đã ở trong thì giữ nguyên vị trí.
    if not isInsideGoalArea(rootPart.Position,goalPart) then
        rootPart.CFrame=CFrame.new(goalPart.Position+GK_TP_OFFSET)
        task.wait(GK_DIVE_DELAY)
    else
        task.wait(GK_DIVE_DELAY)
    end

    -- Chỉ giả lập Q, không kiểm tra target/dạng skill/ragdoll của đối thủ.
    sendVirtualKey(Enum.KeyCode.Q)
    State.gkDiveReadyAt=os.clock()+GK_DIVE_COOLDOWN
    State.gkSpecialReturnAt=os.clock()+GK_SPECIAL_DURATION

    -- Sau Q: nếu có người giữ bóng thì TP tới người đó.
    -- Nếu bóng đang free thì TP trực tiếp tới bóng. Không phụ thuộc team.
    local targetRoot,holder=getCurrentBallTarget()
    State.tpFollowTarget=holder
    State.tpFollowBall=(holder and nil or targetRoot)
    if targetRoot then
        rootPart.CFrame=CFrame.new(targetRoot.Position+Vector3.new(0,DEFAULT_STEAL_DISTANCE,0))
        notify("GK RETURN",holder and ("Q DIVE → TP → "..holder.Name) or "Q DIVE → TP → FREE BALL",1.4)
    else
        notify("GK RETURN","Q DIVE → đang chờ bóng",1.3)
    end

    return true
end

--========================================================--
-- STEAL BALL / AUTO SLIDE
--========================================================--

local function getBoolAttributeOrChild(model,name)
    if not model then return false end
    local ok,value=pcall(function() return model:GetAttribute(name) end)
    if ok and value==true then return true end
    return model:FindFirstChild(name) ~= nil
end

local function hasUnsafeAnimation(targetCharacter)
    local targetHumanoid=targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid then return false end
    local animator=targetHumanoid:FindFirstChildOfClass("Animator")
    if not animator then return false end

    for _,track in ipairs(animator:GetPlayingAnimationTracks()) do
        local name=string.lower(tostring(track.Name or ""))
        if track.Animation then
            name=name.." "..string.lower(tostring(track.Animation.Name or ""))
        end
        for _,word in ipairs(STEAL_UNSAFE_ANIMATION_WORDS) do
            if string.find(name,word,1,true) then
                return true
            end
        end
    end
    return false
end

local function targetLooksUnsafe(plr)
    if not plr or plr==player or not plr.Character then return true end
    local char=plr.Character
    for _,name in ipairs(STEAL_UNSAFE_ATTRIBUTE_NAMES) do
        if getBoolAttributeOrChild(char,name) then return true end
    end
    return hasUnsafeAnimation(char)
end

local function localSlideLooksUnsafe()
    if not character then return true end
    for _,name in ipairs({"Ragdoll","Dancing","Cutscene","Stunned"}) do
        if getBoolAttributeOrChild(character,name) then return true end
    end
    return false
end

local function sendVirtualE()
    if not VirtualInputManager then return false end
    return pcall(function()
        VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.E,false,game)
        VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.E,false,game)
    end)
end

local function findStealTarget()
    local state,holder,ball=getBallState()
    if state=="HELD" and holder and holder~=player then
        -- Barou: ignore team ownership and still chase / spam E.
        -- Normal characters: only chase an opposing holder.
        local allowed=localIsBarou() or not sameTeam(holder)
        if allowed then
            if targetLooksUnsafe(holder) then return nil,nil end
            return holder,getPlayerRoot(holder)
        end
    end
    if state=="FREE" and ball then
        return nil,ball
    end
    return nil,nil
end

local function stealBallStep(dt)
    if not State.stealBallEnabled or not updateCharacter() or not rootPart or localHasBall() then return end
    if localSlideLooksUnsafe() then return end

    State.stealSlideCooldown += dt
    State.stealScanCooldown += dt

    local target,targetRoot
    if State.stealLastTarget and State.stealScanCooldown < STEAL_TARGET_SCAN_INTERVAL then
        target=State.stealLastTarget
        if targetLooksUnsafe(target) then
            target=nil
        else
            targetRoot=getPlayerRoot(target)
        end
    end

    if State.stealScanCooldown >= STEAL_TARGET_SCAN_INTERVAL or not targetRoot then
        State.stealScanCooldown=0
        target,targetRoot=findStealTarget()
        State.stealLastTarget=target
    end

    if not targetRoot then return end

    rootPart.CFrame=CFrame.new(targetRoot.Position+Vector3.new(0,DEFAULT_STEAL_DISTANCE,0))

    if State.stealSlideCooldown >= STEAL_SLIDE_INTERVAL then
        State.stealSlideCooldown=0
        local distance=(targetRoot.Position-rootPart.Position).Magnitude
        if distance <= STEAL_SLIDE_DISTANCE and (not target or not targetLooksUnsafe(target)) then
            sendVirtualE()
        end
    end
end

--========================================================--
-- TP GOAL
-- Home -> PlayerTwoGoal.ScoreHitbox
-- Away -> PlayerOneGoal.ScoreHitbox
--========================================================--

local function startTPGoal()
    if not updateCharacter() or not rootPart then
        notify("TP GOAL","Không tìm thấy nhân vật",1.2)
        return
    end

    local goalPart=resolveOpponentGoalHitbox()
    if not goalPart then
        notify("TP GOAL","Không tìm thấy ScoreHitbox đối diện",1.3)
        return
    end

    rootPart.CFrame=CFrame.new(goalPart.Position+GK_TP_OFFSET)
    State.tpGoalActive=true
    notify("TP GOAL",getTeamIsHome() and "HOME → PLAYER TWO GOAL" or "AWAY → PLAYER ONE GOAL",1.3)
end

--========================================================--
-- TP RETURN
--========================================================--

local function restoreTemporaryTP(reason)
    if not State.tpActive then return end
    local saved=State.tpReturnCFrame
    State.tpActive=false
    State.tpReturnCFrame=nil
    State.tpGoalActive=false
    State.tpFollowTarget=nil
    State.tpFollowBall=nil
    State.gkSpecialEnabled=false
    State.gkSpecialReturnAt=0
    State.gkLastGoalPart=nil
    if saved and updateCharacter() and rootPart then rootPart.CFrame=saved end
    if reason then notify("TP RETURN",reason,1.2) end
end

local function startTemporaryTP()
    if State.tpActive then
        State.gkSpecialEnabled=false
        State.gkLastGoalPart=nil
        restoreTemporaryTP("Returned")
        return
    end
    if not updateCharacter() or not rootPart then
        notify("TP RETURN","Không tìm thấy nhân vật",1.2)
        return
    end

    -- GK: ONLY run the dedicated GK flow. Do not merge with Steal Ball / E / target filtering.
    if localIsGoalkeeper() then
        local savedBeforeGK=rootPart.CFrame
        if performGKTPReturn() then
            State.tpReturnCFrame=savedBeforeGK
            State.tpActive=true
            State.tpStartedAt=os.clock()
            return
        end
        return
    end

    local state,holder,ball=getBallState()
    local targetPosition,targetName

    if state=="HELD" and holder and holder~=player and (localIsBarou() or not sameTeam(holder)) then
        local targetRoot=getPlayerRoot(holder)
        if targetRoot then
            targetPosition=targetRoot.Position+Vector3.new(0,DEFAULT_STEAL_DISTANCE,0)
            targetName=holder.Name
        end
    elseif state=="FREE" and ball then
        targetPosition=ball.Position+Vector3.new(0,DEFAULT_STEAL_DISTANCE,0)
        targetName="FREE BALL"
    end

    if not targetPosition then
        notify("TP RETURN","Không có bóng hợp lệ để TP",1.3)
        return
    end

    State.tpReturnCFrame=rootPart.CFrame
    State.tpGoalActive=false
    State.tpActive=true
    State.tpStartedAt=os.clock()
    State.tpFollowTarget=(state=="HELD" and holder) or nil
    State.tpFollowBall=(state=="FREE" and ball) or nil
    rootPart.CFrame=CFrame.new(targetPosition)
    notify("TP RETURN",string.format("TP → %s trong %.2fs",targetName,State.tpDuration),1.5)
end

--========================================================--
-- UI UPDATE
--========================================================--

local function modeName()
    if State.mode==1 then return "MODE 1 [CAMERA]" end
    return "MODE 2 [RONALDO]"
end

local function updateUI()
    controlButton.Text="CONTROL KEY: "..State.controlKey.Name
    modeButton.Text=modeName()
    statusLabel.Text=State.enabled and "Status: ACTIVE" or "Status: READY"
    statusLabel.TextColor3=State.enabled and Color3.fromRGB(100,255,130) or Color3.fromRGB(255,205,100)
    stealButton.Text=State.stealBallEnabled and "STEAL BALL: ON" or "STEAL BALL: OFF"
    saeButton.Text=State.saePassEnabled and "SAE PASS: ON" or "SAE PASS: OFF"
end

local function updateBallStatusUI(state,holder,ball)
    if state=="HELD" then
        ballStatus.Text="BALL: HELD — "..holder.Name
        statusState.Text="STATUS: HELD"
        statusOwner.Text="OWNER: "..holder.Name
        statusPlayer.Text="CONTROL: "..(State.enabled and "ACTIVE" or "OFF")
        statusState.TextColor3=holder==player and Color3.fromRGB(100,255,255) or (sameTeam(holder) and Color3.fromRGB(100,255,130) or Color3.fromRGB(255,100,100))
    elseif state=="FREE" then
        ballStatus.Text="BALL: FREE"
        statusState.Text="STATUS: FREE"
        statusOwner.Text="OWNER: NONE"
        statusPlayer.Text="CONTROL: "..(State.enabled and "ACTIVE" or "OFF")
        statusState.TextColor3=Color3.fromRGB(255,215,100)
    else
        ballStatus.Text="BALL: NOT FOUND"
        statusState.Text="STATUS: NOT FOUND"
        statusOwner.Text="OWNER: —"
        statusPlayer.Text="CONTROL: "..(State.enabled and "ACTIVE" or "OFF")
        statusState.TextColor3=Color3.fromRGB(255,100,100)
    end
    statusPlayer.TextColor3=State.enabled and Color3.fromRGB(100,255,130) or Color3.fromRGB(180,180,190)
end
--========================================================--
-- BUTTONS
--========================================================--

minimizeButton.MouseButton1Click:Connect(function()
    State.minimized=true
    restoreButton.Position=main.Position
    clampGuiPosition(restoreButton)
    main.Visible=false
    settingsFrame.Visible=false
    restoreButton.Visible=true
end)
restoreButton.MouseButton1Click:Connect(function()
    State.minimized=false
    main.Visible=true
    restoreButton.Visible=false
end)
settingsButton.MouseButton1Click:Connect(function()
    State.settingsOpen=not State.settingsOpen
    settingsFrame.Visible=State.settingsOpen and not State.minimized
    refreshSettingsPanel()
end)
closeSettings.MouseButton1Click:Connect(function() State.settingsOpen=false; settingsFrame.Visible=false end)

controlButton.MouseButton1Click:Connect(function()
    State.changingControlKey=true
    controlButton.Text="PRESS A KEY..."
    notify("CONTROL KEY","Nhấn phím mới (ESC = hủy)",1.6)
end)

modeButton.MouseButton1Click:Connect(function()
    State.mode=(State.mode==1) and 2 or 1
    if State.mode~=1 and State.advanceMode then setAdvanceMode(false) end
    State.enabled=false
    State.forceUnanchorActive=false
    if rootPart then rootPart.Anchored=false end
    unlockPlayer()
    restoreCamera()
    if State.mode==1 then
        local ball=findBall()
        if ball then
            if State.advanceMode then
                camera=workspace.CurrentCamera
                camera.CameraType=Enum.CameraType.Scriptable
            else
                cameraToBall(ball)
            end
        end
    end
    updateUI()
    notify("MODE",modeName(),1.3)
end)

stealButton.MouseButton1Click:Connect(function()
    State.stealBallEnabled = not State.stealBallEnabled
    if not State.stealBallEnabled then
        State.stealLastTarget=nil
        State.stealSlideCooldown=0
        State.stealScanCooldown=0
    end

    -- Nếu vừa bật nhưng đang cầm bóng và đang chọn AUTO OFF,
    -- tắt ngay thay vì để nút hiển thị ON sai trạng thái.
    if State.stealBallEnabled and State.autoStealOffOnGet and localHasBall() then
        State.stealBallEnabled = false
        State.stealLastTarget=nil
        State.stealSlideCooldown=0
        State.stealScanCooldown=0
        updateUI()
        notify("STEAL BALL", "Tắt ngay — bạn đã có bóng", 1.3)
        return
    end

    updateUI()
    notify("STEAL BALL", State.stealBallEnabled and "ON" or "OFF", 1.3)
end)

saeButton.MouseButton1Click:Connect(function()
    State.saePassEnabled=not State.saePassEnabled
    if not State.saePassEnabled then clearTarget() end
    updateUI()
    notify("SAE PASS",State.saePassEnabled and "ON" or "OFF",1.3)
end)

tpButton.MouseButton1Click:Connect(startTemporaryTP)
tpGoalButton.MouseButton1Click:Connect(startTPGoal)

--========================================================--
-- RESTORED LEGACY UI BUTTONS
--========================================================--

anchorButton.MouseButton1Click:Connect(function()
    State.anchorEnabled = not State.anchorEnabled
    State.forceUnanchorActive = false
    anchorButton.Text = State.anchorEnabled and "ANCHOR: ON" or "ANCHOR: OFF"
    if not State.anchorEnabled then
        unlockPlayer()
    elseif State.enabled and State.mode == 1 then
        applyModeLock()
    end
end)

forceUnanchorButton.MouseButton1Click:Connect(function()
    forceUnanchor()
end)

--========================================================--
-- BALL STATUS BUTTON
--========================================================--

statusButton.MouseButton1Click:Connect(function()
    statusPanel.Visible = not statusPanel.Visible
    statusButton.Text = statusPanel.Visible and "BALL STATUS: ON" or "BALL STATUS: OFF"
end)

--========================================================--
-- INPUT
--========================================================--

UserInputService.InputBegan:Connect(function(input,gameProcessed)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then
        State.leftMouseHeld=true
        return
    end

    if input.UserInputType==Enum.UserInputType.MouseButton2 then
        State.rightMouseHeld=true
        return
    end

    if input.UserInputType~=Enum.UserInputType.Keyboard then return end

    if State.advanceMode and State.mode==1 then
        if input.KeyCode==Enum.KeyCode.W then State.advanceKeys.W=true; return end
        if input.KeyCode==Enum.KeyCode.A then State.advanceKeys.A=true; return end
        if input.KeyCode==Enum.KeyCode.S then State.advanceKeys.S=true; return end
        if input.KeyCode==Enum.KeyCode.D then State.advanceKeys.D=true; return end
        if input.KeyCode==Enum.KeyCode.Q then State.advanceKeys.Q=true; return end
        if input.KeyCode==Enum.KeyCode.E then State.advanceKeys.E=true; return end
    end

    if State.changingControlKey then
        if input.KeyCode==Enum.KeyCode.Escape then
            State.changingControlKey=false
            setGeneralControls()
            updateUI()
            return
        end
        if input.KeyCode~=Enum.KeyCode.Unknown then
            State.controlKey=input.KeyCode
            State.changingControlKey=false
            setGeneralControls()
            updateUI()
            notify("CONTROL KEY","Set to "..State.controlKey.Name,1.4)
        end
        return
    end

    if input.KeyCode==State.controlKey then
        -- SAE PASS: hold LMB + F to select a teammate; F again can launch immediately.
        if State.saePassEnabled and State.leftMouseHeld then
            if not State.selectedTarget then
                selectSaePassTarget()
            else
                launchSelectedSaePass()
            end
            return
        end

        -- If a target was selected and LMB is no longer held, pressing F launches it.
        if State.saePassEnabled and State.selectedTarget then
            launchSelectedSaePass()
            return
        end

        local _,_,ball=getBallState()

        if State.mode==1 then
            State.enabled=not State.enabled
            if State.enabled then
                State.forceUnanchorActive=false
                if State.advanceMode then
                    camera=workspace.CurrentCamera
                    if camera then camera.CameraType=Enum.CameraType.Scriptable end
                elseif ball then
                    cameraToBall(ball)
                end
                applyModeLock()
                notify("CONTROL",modeName().." ACTIVE",1.1)
            else
                restoreCamera()
                applyModeLock()
                notify("CONTROL","OFF",1.0)
            end
            updateUI()
            return
        end

        if State.mode==2 then
            if localHasBall() then
                performMode4Kick(ball)
            else
                notify("MODE 2","Cần đang cầm bóng",1.2)
            end
            return
        end
    end

    if gameProcessed then return end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then
        State.leftMouseHeld=false
        if State.saePassEnabled and State.selectedTarget and not State.saePassActive then
            launchSelectedSaePass()
        end
    elseif input.UserInputType==Enum.UserInputType.MouseButton2 then
        State.rightMouseHeld=false
    elseif input.UserInputType==Enum.UserInputType.Keyboard then
        if input.KeyCode==Enum.KeyCode.W then State.advanceKeys.W=false end
        if input.KeyCode==Enum.KeyCode.A then State.advanceKeys.A=false end
        if input.KeyCode==Enum.KeyCode.S then State.advanceKeys.S=false end
        if input.KeyCode==Enum.KeyCode.D then State.advanceKeys.D=false end
        if input.KeyCode==Enum.KeyCode.Q then State.advanceKeys.Q=false end
        if input.KeyCode==Enum.KeyCode.E then State.advanceKeys.E=false end
    end
end)

--========================================================--
-- TP FOLLOW
--========================================================--

local function updateTPFollowTarget()
    if not State.tpActive or not updateCharacter() or not rootPart then return end

    local state,holder,ball=getBallState()
    local targetRoot=nil
    if state=="HELD" and holder and holder~=player then
        targetRoot=getPlayerRoot(holder)
        if targetRoot then
            State.tpFollowTarget=holder
            State.tpFollowBall=nil
        end
    elseif state=="FREE" and ball then
        targetRoot=ball
        State.tpFollowTarget=nil
        State.tpFollowBall=ball
    end

    if targetRoot then
        rootPart.CFrame=CFrame.new(targetRoot.Position+Vector3.new(0,DEFAULT_STEAL_DISTANCE,0))
    end
end

--========================================================--
-- HEARTBEAT
--========================================================--

RunService.Heartbeat:Connect(function(dt)
    updateCharacter()

    local state,holder,ball=getBallState()
    updateBallStatusUI(state,holder,ball)

    if State.saePassActive and holder and holder==State.saePassTarget then
        clearTarget()
        notify("SAE PASS","Target received the ball",1.2)
    elseif State.saePassActive and holder and holder~=player and holder~=State.saePassTarget then
        clearTarget()
        notify("SAE PASS","Another player received the ball",1.1)
    end

    if State.stealBallEnabled then
        if State.autoStealOffOnGet and localHasBall() then
            State.stealBallEnabled=false
            State.stealLastTarget=nil
            State.stealSlideCooldown=0
            notify("STEAL BALL","Tự động tắt — bạn đã có bóng",1.4)
        else
            stealBallStep(dt)
        end
    end

    if State.tpActive then
        updateTPFollowTarget()
        if State.gkSpecialEnabled then
            if os.clock()>=State.gkSpecialReturnAt then
                restoreTemporaryTP("GK special returned")
            end
        elseif os.clock()-State.tpStartedAt>=State.tpDuration then
            restoreTemporaryTP("TP timer expired")
        end
    end

    if State.enabled and State.mode==1 and ball then
        if not updateAdvanceCamera(ball,dt) then
            controlMode1(ball)
        end
    end

    if State.mode==1 then
        applyModeLock()
    elseif rootPart and rootPart.Anchored then
        rootPart.Anchored=false
    end

    updateUI()
end)

--========================================================--
-- RESPAWN / VIEWPORT
--========================================================--

player.CharacterAdded:Connect(function()
    task.wait(0.5)
    updateCharacter()
    playerBallCache[player]=nil
    cacheScanAt[player]=nil
    playerWasLocked=false
    savedWalkSpeed,savedJumpPower,savedAutoRotate=nil,nil,nil
    clearTarget()
    State.tpActive=false
    State.tpReturnCFrame=nil
    State.gkSpecialEnabled=false
    State.gkSpecialReturnAt=0
    State.gkLastGoalPart=nil
    State.tpFollowTarget=nil
    State.tpFollowBall=nil
    State.advanceKeys={W=false,A=false,S=false,D=false,Q=false,E=false}
    State.advanceCameraOffset=Vector3.new(0,7,14)
    State.forceUnanchorActive=false
    if State.enabled and State.mode==1 and State.anchorEnabled then applyModeLock() else unlockPlayer() end
    updateUI()
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    camera=workspace.CurrentCamera
    task.defer(function()
        clampGuiPosition(statusPanel)
    end)
end)

--========================================================--
-- INITIALIZE
--========================================================--

refreshSettingsPanel()
updateUI()
setStatusMini(false)

if shootRemoteReady then
    notify("SHOOT REMOTE","ShootBall detected",1.5)
else
    notify("SHOOT REMOTE","Events.ShootBall chưa tìm thấy",2)
end
if not VirtualInputManager then
    notify("STEAL BALL","VirtualInputManager không khả dụng — Auto Slide sẽ không gửi E",2)
end
notify("BALL CONTROLLER","V3 loaded",1.5)
print("[Ball Controller V3] loaded")
