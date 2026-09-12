--========================================================--
--                 BALL CONTROLLER V3                     --
--  Modes 1-5 / Steal Ball / Sae Pass / Ball Status UI   --
--========================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local MODE5_RELEASE_TIME = 0.12
local MODE3_MIN_DURATION = 0.35
local MODE3_MAX_DURATION = 4
local ENDPOINT_RAY_DISTANCE = 1000

local modeSettings = {
    [1] = { speed = 60 },
    [2] = { speed = 60 },
    [3] = { speed = 60, curve = 30, angle = 0 },
    [4] = { speed = 140 },
    [5] = { speed = 140, height = 180 },
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

    mode3Active = false,
    mode3Ball = nil,
    mode3Start = nil,
    mode3Control = nil,
    mode3End = nil,
    mode3EndSelected = false,
    mode3StartTime = 0,
    mode3Duration = 1,

    mode5Stage = "IDLE",
    mode5Ball = nil,
    mode5TopY = nil,
    mode5RiseSpeed = 0,
    mode5ReleaseStarted = 0,
    mode5End = nil,
    mode5EndSelected = false,

    tpDuration = DEFAULT_TP_TIME,
    tpActive = false,
    tpStartedAt = 0,
    tpReturnCFrame = nil,

    keys = {W=false,A=false,S=false,D=false,Q=false,E=false},
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
    if State.enabled and State.anchorEnabled and (State.mode == 1 or State.mode == 2) then
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
local modeButton = makeButton(main,"MODE: 1",180,92,160,36)
local anchorButton = makeButton(main,"ANCHOR: ON",10,136,160,36)
local forceUnanchorButton = makeButton(main,"FORCE UNANCHOR",180,136,160,36)
local stealButton = makeButton(main,"STEAL BALL: OFF",10,180,160,36)
local saeButton = makeButton(main,"SAE PASS: OFF",180,180,160,36)
local settingsButton = makeButton(main,"⚙ SETTINGS",10,224,160,36)
local statusButton = makeButton(main,"BALL STATUS: ON",180,224,160,36)
local tpButton = makeButton(main,"TP RETURN",10,268,230,36)
local tpTimeBox = makeBox(main,State.tpDuration,250,268,90,36)

local info = makeLabel(main,
    "F = action / toggle theo State.mode.\n"..
    "Mode 1/2: WASDEQ khi control active.\n"..
    "Mode 3/5: giữ chuột trái + bấm chuột phải để chọn END.\n"..
    "Sae Pass: RMB + F để chọn; LMB + F để hủy.",
    10,315,330,90,11)
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
local tabNames = {"MODE 1","MODE 2","MODE 3","MODE 4","MODE 5"}
for i,name in ipairs(tabNames) do
    tabs[i] = makeButton(settingsFrame,name,10+(i-1)*78,48,72,30)
end

local settingsContent = Instance.new("Frame")
settingsContent.Size = UDim2.new(1,-20,1,-90)
settingsContent.Position = UDim2.fromOffset(10,88)
settingsContent.BackgroundTransparency = 1
settingsContent.Parent = settingsFrame

local speedLabels,speedBoxes = {},{}
for i=1,5 do
    speedLabels[i] = makeLabel(settingsContent,"SPEED",10,10,110,25,12)
    speedBoxes[i] = makeBox(settingsContent,modeSettings[i].speed,120,6,220,32)
    speedLabels[i].Visible = false
    speedBoxes[i].Visible = false
end

local curveLabel = makeLabel(settingsContent,"CURVE",10,56,100,25,12)
local curveBox = makeBox(settingsContent,modeSettings[3].curve,120,52,220,32)
local angleLabel = makeLabel(settingsContent,"ANGLE",10,102,100,25,12)
local angleBox = makeBox(settingsContent,modeSettings[3].angle,120,98,220,32)
local mode5HeightLabel = makeLabel(settingsContent,"HEIGHT / FORCE",10,56,110,25,12)
local mode5HeightBox = makeBox(settingsContent,modeSettings[5].height,120,52,220,32)
local settingsHint = makeLabel(settingsContent,"",10,160,440,80,11)
settingsHint.TextWrapped = true
settingsHint.TextColor3 = Color3.fromRGB(145,145,155)

curveLabel.Visible=false
curveBox.Visible=false
angleLabel.Visible=false
angleBox.Visible=false
mode5HeightLabel.Visible=false
mode5HeightBox.Visible=false
local selectedSettingsTab = 1

local function parseSetting(box,oldValue,minValue,maxValue)
    local n = tonumber(box.Text)
    if not n then box.Text=tostring(oldValue); return oldValue end
    n = math.clamp(n,minValue,maxValue)
    box.Text=tostring(n)
    return n
end

local function refreshSettingsPanel()
    for i=1,5 do
        speedLabels[i].Visible = selectedSettingsTab == i
        speedBoxes[i].Visible = selectedSettingsTab == i
    end
    local m3 = selectedSettingsTab == 3
    local m5 = selectedSettingsTab == 5
    curveLabel.Visible=m3; curveBox.Visible=m3
    angleLabel.Visible=m3; angleBox.Visible=m3
    mode5HeightLabel.Visible=m5; mode5HeightBox.Visible=m5
    if selectedSettingsTab==1 then
        settingsHint.Text="Mode 1: WASDEQ điều khiển liên tục; khi không Q/E, Y của bóng được giữ ổn định."
    elseif selectedSettingsTab==2 then
        settingsHint.Text="Mode 2: bóng chạy theo hướng camera khi control active."
    elseif selectedSettingsTab==3 then
        settingsHint.Text="Mode 3: giữ chuột trái + bấm chuột phải để chọn END. CURVE điều chỉnh độ cong của cung tròn; ANGLE xoay mặt phẳng 2D của cung trong thế giới 3D. Bấm F để bay tới END."
    elseif selectedSettingsTab==4 then
        settingsHint.Text="Mode 4: giữ nguyên cơ chế hiện tại — truyền velocity một lần và không loop chỉnh bóng."
    elseif selectedSettingsTab==5 then
        settingsHint.Text="Mode 5: F lần 1 release ngắn → bay thẳng lên HEIGHT/FORCE → treo; chọn END rồi F để phóng theo SPEED."
    end
end
for i=1,5 do
    tabs[i].MouseButton1Click:Connect(function()
        selectedSettingsTab=i
        refreshSettingsPanel()
    end)
    if i <= 5 then
        speedBoxes[i].FocusLost:Connect(function()
            modeSettings[i].speed=parseSetting(speedBoxes[i],modeSettings[i].speed,MIN_SPEED,MAX_SPEED)
        end)
    end
end

curveBox.FocusLost:Connect(function() modeSettings[3].curve=parseSetting(curveBox,modeSettings[3].curve,-1000,1000) end)
angleBox.FocusLost:Connect(function() modeSettings[3].angle=parseSetting(angleBox,modeSettings[3].angle,-180,180) end)
mode5HeightBox.FocusLost:Connect(function() modeSettings[5].height=parseSetting(mode5HeightBox,modeSettings[5].height,MIN_SPEED,MAX_SPEED) end)

--========================================================--
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
-- MODE 1 / 2
--========================================================--

local function controlMode1(ball)
    local forward,right=getFlatCameraDirections()
    local direction=Vector3.zero
    if State.keys.W then direction+=forward end
    if State.keys.S then direction-=forward end
    if State.keys.D then direction+=right end
    if State.keys.A then direction-=right end
    local horizontal=Vector3.zero
    if direction.Magnitude>0 then horizontal=direction.Unit*modeSettings[1].speed end
    local vertical=0
    if State.keys.E then vertical=modeSettings[1].speed elseif State.keys.Q then vertical=-modeSettings[1].speed end
    ball.AssemblyLinearVelocity=Vector3.new(horizontal.X,vertical,horizontal.Z)
end

local function controlMode2(ball)
    local dir=getCameraDirection()
    ball.AssemblyLinearVelocity=dir*modeSettings[2].speed
end

--========================================================--
-- ENDPOINT PICKER
-- Hold LMB + press RMB to select the 3D point under mouse.
--========================================================--

local endpointMarker
local selectedEndPoint = nil

local function getMouseWorldPoint()
    camera=workspace.CurrentCamera
    if not camera then return nil end
    local mouse=UserInputService:GetMouseLocation()
    local ray=camera:ViewportPointToRay(mouse.X,mouse.Y)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local ignore={}
    if player.Character then table.insert(ignore,player.Character) end
    if State.mode3Ball then table.insert(ignore,State.mode3Ball) end
    if State.mode5Ball then table.insert(ignore,State.mode5Ball) end
    params.FilterDescendantsInstances=ignore
    local result=workspace:Raycast(ray.Origin,ray.Direction*ENDPOINT_RAY_DISTANCE,params)
    if result then return result.Position end
    return ray.Origin+ray.Direction*math.min(300,ENDPOINT_RAY_DISTANCE)
end

local function showEndpoint(point)
    selectedEndPoint=point
    if not endpointMarker then
        endpointMarker=Instance.new("Part")
        endpointMarker.Name="BallController_EndPoint"
        endpointMarker.Shape=Enum.PartType.Ball
        endpointMarker.Size=Vector3.new(1.4,1.4,1.4)
        endpointMarker.Material=Enum.Material.Neon
        endpointMarker.Color=Color3.fromRGB(255,210,70)
        endpointMarker.Anchored=true
        endpointMarker.CanCollide=false
        endpointMarker.CanTouch=false
        endpointMarker.CanQuery=false
        endpointMarker.Transparency=0.1
        endpointMarker.Parent=workspace
    end
    endpointMarker.Position=point+Vector3.new(0,0.7,0)
    endpointMarker.Transparency=0.1
    notify("END POINT",string.format("%.1f, %.1f, %.1f",point.X,point.Y,point.Z),1.1)
end

local function clearEndpoint()
    selectedEndPoint=nil
    State.mode3EndSelected=false
    State.mode5End=nil
    State.mode5EndSelected=false
    if endpointMarker then
        endpointMarker.Transparency=1
    end
end

local function pickEndpoint()
    local point=getMouseWorldPoint()
    if not point then
        notify("END POINT","Không lấy được vị trí chuột",1.1)
        return false
    end
    showEndpoint(point)
    if State.mode==3 then
        State.mode3End=point
        State.mode3EndSelected=true
    elseif State.mode==5 and State.mode5Stage=="WAITING" then
        State.mode5End=point
        State.mode5EndSelected=true
    end
    return true
end

--========================================================--
-- MODE 3: REAL CURVED PATH
--========================================================--

local function bezier2(a,b,c,t)
    local u=1-t
    return a*(u*u)+b*(2*u*t)+c*(t*t)
end

local function bezierTangent(a,b,c,t)
    return (b-a)*(2*(1-t))+(c-b)*(2*t)
end

local function getMode3ArcData(startPos,endPos,curve,angleDeg)
    local chord=endPos-startPos
    local distance=chord.Magnitude
    if distance<0.001 then return nil end

    local forward=chord.Unit

    -- Base perpendicular vector: prefer world-up projected onto the
    -- plane perpendicular to Start -> End. If the chord is vertical,
    -- use a horizontal reference instead.
    local up=Vector3.new(0,1,0)
    local planeUp=up-forward*up:Dot(forward)
    if planeUp.Magnitude<0.001 then
        local ref=Vector3.new(1,0,0)
        planeUp=ref-forward*ref:Dot(forward)
    end
    planeUp=planeUp.Unit

    -- ANGLE rotates the 2D flight plane around the Start -> End axis.
    local angle=math.rad(angleDeg or 0)
    local side=forward:Cross(planeUp)
    if side.Magnitude<0.001 then
        side=Vector3.new(0,0,1)
    else
        side=side.Unit
    end

    local arcNormal=planeUp*math.cos(angle)+side*math.sin(angle)
    if arcNormal.Magnitude<0.001 then
        arcNormal=planeUp
    else
        arcNormal=arcNormal.Unit
    end

    -- The circular arc lives in the plane spanned by forward + arcNormal.
    -- CURVE is the signed sagitta (maximum distance from the chord).
    local sag=tonumber(curve) or 0
    if math.abs(sag)<0.001 then
        return {
            straight=true,
            startPos=startPos,
            endPos=endPos,
            distance=distance,
        }
    end

    local maxSag=math.max(0.05,distance*0.49)
    sag=math.clamp(sag,-maxSag,maxSag)

    local absSag=math.abs(sag)
    local signSag=sag>=0 and 1 or -1

    -- Radius from chord length + sagitta:
    -- R = d^2/(8h) + h/2
    local radius=(distance*distance)/(8*absSag)+(absSag*0.5)
    local halfChord=distance*0.5
    local centerOffset=radius-absSag

    local midpoint=startPos+chord*0.5
    local center=midpoint-arcNormal*(centerOffset*signSag)

    local startRadius=startPos-center
    local endRadius=endPos-center
    local r=radius

    -- Build the rotation direction in the 2D arc plane.
    local radialStart=startRadius.Unit
    local radialEnd=endRadius.Unit
    local cross3=radialStart:Cross(radialEnd)
    local theta=math.acos(math.clamp(radialStart:Dot(radialEnd),-1,1))

    -- Choose the shorter arc. For our clamped sag this is the intended arc.
    local rotationAxis=forward:Cross(arcNormal)
    if rotationAxis.Magnitude<0.001 then
        rotationAxis=Vector3.new(0,1,0)
    else
        rotationAxis=rotationAxis.Unit
    end
    if cross3:Dot(rotationAxis)<0 then
        theta=-theta
    end

    return {
        straight=false,
        startPos=startPos,
        endPos=endPos,
        center=center,
        radius=r,
        radialStart=radialStart,
        rotationAxis=rotationAxis,
        theta=theta,
        distance=distance,
    }
end

local function pointOnMode3Arc(data,t)
    t=math.clamp(t,0,1)

    if data.straight then
        return data.startPos:Lerp(data.endPos,t)
    end

    local rotation=CFrame.fromAxisAngle(data.rotationAxis,data.theta*t)
    local radial=rotation:VectorToWorldSpace(data.radialStart)
    return data.center+radial*data.radius
end

local function tangentOnMode3Arc(data,t)
    t=math.clamp(t,0,1)

    if data.straight then
        local d=data.endPos-data.startPos
        return d.Magnitude>0.001 and d.Unit or Vector3.zero
    end

    local rotation=CFrame.fromAxisAngle(data.rotationAxis,data.theta*t)
    local radial=rotation:VectorToWorldSpace(data.radialStart)
    local tangent=data.rotationAxis:Cross(radial)

    if data.theta<0 then tangent=-tangent end
    return tangent.Magnitude>0.001 and tangent.Unit or Vector3.zero
end

local function startMode3(ball)
    if not ball or not localHasBall() then
        notify("MODE 3","Cần đang cầm bóng",1.3)
        return
    end

    if not State.mode3EndSelected or not State.mode3End then
        notify("MODE 3","Giữ chuột trái + bấm chuột phải để chọn END",1.5)
        return
    end

    local speed=math.clamp(modeSettings[3].speed,MIN_SPEED,MAX_SPEED)
    local startPos=ball.Position
    local endPos=State.mode3End
    local distance=(endPos-startPos).Magnitude

    if distance<1 then
        notify("MODE 3","END quá gần",1.1)
        return
    end

    local arc=getMode3ArcData(
        startPos,
        endPos,
        modeSettings[3].curve,
        modeSettings[3].angle
    )

    if not arc then
        notify("MODE 3","Không tạo được quỹ đạo",1.2)
        return
    end

    State.mode3Start=startPos
    State.mode3Control=arc
    State.mode3End=endPos
    State.mode3Ball=ball
    State.mode3StartTime=os.clock()
    State.mode3Duration=math.clamp(distance/speed,MODE3_MIN_DURATION,MODE3_MAX_DURATION)
    State.mode3Active=true

    fireShootRemote((endPos-startPos).Unit,math.min(speed,MAX_SPEED),false)

    notify(
        "MODE 3",
        string.format(
            "ARC → END | CURVE %.1f | ANGLE %.1f°",
            modeSettings[3].curve,
            modeSettings[3].angle
        ),
        1.6
    )
end

local function updateMode3()
    if not State.mode3Active then return end

    local ball=State.mode3Ball
    local arc=State.mode3Control

    if not ball or not ball.Parent or not arc then
        State.mode3Active=false
        return
    end

    local t=math.clamp(
        (os.clock()-State.mode3StartTime)/State.mode3Duration,
        0,
        1
    )

    local pos=pointOnMode3Arc(arc,t)
    local tangent=tangentOnMode3Arc(arc,t)

    if tangent.Magnitude>0 then
        ball.CFrame=CFrame.lookAt(pos,pos+tangent)
        ball.AssemblyLinearVelocity=tangent*math.max(modeSettings[3].speed,MIN_SPEED)
    else
        ball.CFrame=CFrame.new(pos)
        ball.AssemblyLinearVelocity=Vector3.zero
    end

    if t>=1 then
        ball.CFrame=CFrame.lookAt(State.mode3End,State.mode3End+tangent)
        ball.AssemblyLinearVelocity=tangent*math.max(modeSettings[3].speed,MIN_SPEED)
        State.mode3Active=false
        State.mode3Ball=nil
        State.mode3Control=nil
        clearEndpoint()
    end
end

--========================================================--
-- MODE 4 (UNCHANGED WORKING BEHAVIOR)
--========================================================--

local function performMode4Kick(ball)
    if not ball then return end
    local direction=getCameraDirection()
    local force=math.clamp(modeSettings[4].speed,MIN_SPEED,MAX_SPEED)
    ball.AssemblyLinearVelocity=direction*force
    notify("RONALDO MODE",string.format("Velocity %.1f",force),1.3)
end

--========================================================--
-- MODE 5
--========================================================--

local function resetMode5()
    State.mode5Stage="IDLE"
    State.mode5Ball=nil
    State.mode5TopY=nil
    State.mode5RiseSpeed=0
    State.mode5ReleaseStarted=0
    State.mode5End=nil
    State.mode5EndSelected=false
    State.mode5TravelStarted=0
end

local function startMode5(ball)
    if not ball or not localHasBall() then
        notify("MODE 5","Cần đang cầm bóng",1.3)
        return
    end
    local force=math.clamp(modeSettings[5].height,MIN_SPEED,MAX_SPEED)
    local forward,_=getFlatCameraDirections()
    local releaseSpeed=math.max(force*0.35,15)

    fireShootRemote(forward,releaseSpeed,false)

    State.mode5Stage="RELEASING"
    State.mode5Ball=ball
    State.mode5RiseSpeed=force
    State.mode5ReleaseStarted=os.clock()
    notify("MODE 5",string.format("Release → UP %.1f",force),1.3)
end

local function updateMode5()
    if State.mode5Stage=="IDLE" then return end
    local ball=State.mode5Ball
    if not ball or not ball.Parent then resetMode5(); return end

    if State.mode5Stage=="RELEASING" then
        if os.clock()-State.mode5ReleaseStarted<MODE5_RELEASE_TIME then
            local forward,_=getFlatCameraDirections()
            ball.AssemblyLinearVelocity=forward*math.max(State.mode5RiseSpeed*0.25,10)
            return
        end
        State.mode5TopY=ball.Position.Y+State.mode5RiseSpeed
        State.mode5Stage="RISING"
    end

    if State.mode5Stage=="RISING" then
        if ball.Position.Y<State.mode5TopY then
            ball.AssemblyLinearVelocity=Vector3.new(0,State.mode5RiseSpeed,0)
            return
        end
        ball.CFrame=CFrame.new(ball.Position.X,State.mode5TopY,ball.Position.Z)
        ball.AssemblyLinearVelocity=Vector3.zero
        State.mode5Stage="WAITING"
        notify("MODE 5",string.format("READY %.1f → F để launch",modeSettings[5].height),1.5)
        return
    end

    if State.mode5Stage=="WAITING" then
        ball.CFrame=CFrame.new(ball.Position.X,State.mode5TopY,ball.Position.Z)
        ball.AssemblyLinearVelocity=Vector3.zero
        return
    end

    if State.mode5Stage=="TRAVEL" then
        local endPos=State.mode5End
        if not endPos then resetMode5(); return end
        local delta=endPos-ball.Position
        local distance=delta.Magnitude
        if distance<=1.5 then
            ball.CFrame=CFrame.new(endPos)
            ball.AssemblyLinearVelocity=Vector3.zero
            notify("MODE 5","Đã tới END",1.1)
            resetMode5()
            selectedEndPoint=nil
            return
        end
        local speed=math.clamp(modeSettings[5].speed,MIN_SPEED,MAX_SPEED)
        ball.CFrame=CFrame.new(ball.Position,ball.Position+delta.Unit)
        ball.AssemblyLinearVelocity=delta.Unit*speed
    end
end

local function launchMode5()
    if State.mode5Stage~="WAITING" then return end
    if not State.mode5EndSelected or not State.mode5End then
        notify("MODE 5","Giữ chuột trái + bấm chuột phải để chọn END",1.5)
        return
    end
    local ball=State.mode5Ball
    if not ball or not ball.Parent then resetMode5(); return end
    local delta=State.mode5End-ball.Position
    if delta.Magnitude<1 then
        notify("MODE 5","END quá gần",1.1)
        return
    end
    State.mode5Stage="TRAVEL"
    State.mode5TravelStarted=os.clock()
    ball.AssemblyLinearVelocity=delta.Unit*math.clamp(modeSettings[5].speed,MIN_SPEED,MAX_SPEED)
    notify("MODE 5",string.format("CONTROL → END | SPEED %.1f",math.clamp(modeSettings[5].speed,MIN_SPEED,MAX_SPEED)),1.4)
    if endpointMarker then endpointMarker.Transparency=1 end
    selectedEndPoint=nil
end

local function performMode5Action(ball)
    if State.mode5Stage=="WAITING" then launchMode5(); return end
    if State.mode5Stage=="RISING" or State.mode5Stage=="RELEASING" then
        notify("MODE 5","Ball đang bay lên",0.8)
        return
    end
    startMode5(ball)
end

--========================================================--
-- SAE PASS
-- RMB + F: select target / start pass. LMB + F: cancel.
-- Mode 1: short rise then travel toward target.
-- Mode 2: direct instant teleport of ball to target, then hold there
-- until target actually receives the ball.
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
    if not ball or not target then return end
    local targetRoot=getPlayerRoot(target)
    if not targetRoot then return end

    State.saePassActive=true
    State.saePassBall=ball
    State.saePassTarget=target
    State.saePassPassSpeed=math.clamp(modeSettings[3].speed,MIN_SPEED,MAX_SPEED)
    State.saePassStartTime=os.clock()

    if State.mode==2 then
        -- Mode 2: instant move to the target and keep the ball there until received.
        State.saePassStage="DIRECT"
        ball.CFrame=CFrame.new(targetRoot.Position+Vector3.new(0,2.5,0))
        ball.AssemblyLinearVelocity=Vector3.zero
        notify("SAE PASS","DIRECT → "..target.Name,1.4)
        return
    end

    -- Mode 1: short rise, then curve/steer toward target.
    State.saePassStage="RISING"
    local force=math.clamp(SAE_PASS_SPEED*0.32,MIN_SPEED,MAX_SPEED)
    fireShootRemote(Vector3.new(0,1,0),force,false)
    State.saePassTopY=ball.Position.Y+math.min(SAE_PASS_HEIGHT,90)
    notify("SAE PASS","RISING → "..target.Name,1.4)
end

local function updateSaePass()
    if not State.saePassActive then return end
    local ball=State.saePassBall
    local target=State.saePassTarget
    if not ball or not ball.Parent or not target or not target.Parent then clearTarget(); return end
    local targetRoot=getPlayerRoot(target)
    if not targetRoot then clearTarget(); return end

    if State.saePassStage=="DIRECT" then
        -- Do not release the ball until the target actually receives it.
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
            -- Within 10 studs: slow down and fly toward the player instead of teleporting.
            local slowSpeed=math.clamp(distance*4,20,State.saePassPassSpeed)
            ball.AssemblyLinearVelocity=(distance>0.05 and delta.Unit or Vector3.zero)*slowSpeed
        else
            ball.AssemblyLinearVelocity=delta.Unit*State.saePassPassSpeed
        end
    end
end

local function handleSaeInput()
    if not State.saePassEnabled then return false end
    if State.rightMouseHeld then
        local state,holder,ball=getBallState()
        if holder~=player then
            notify("SAE PASS","Cần đang cầm bóng",1.2)
            return true
        end
        if not State.selectedTarget then
            local target=getClosestTeammateToMouse()
            if target then
                highlightTarget(target)
                notify("SAE PASS","F để bắt đầu pass → "..target.Name,1.5)
            else
                notify("SAE PASS","Không tìm thấy đồng đội",1.3)
            end
        else
            startSaePass(ball,State.selectedTarget)
        end
        return true
    end
    if State.leftMouseHeld then
        clearTarget()
        notify("SAE PASS","Cancelled",1.1)
        return true
    end
    return false
end

--========================================================--
-- STEAL BALL
--========================================================--

local function stealBallStep()
    if not State.stealBallEnabled or not updateCharacter() or not rootPart or localHasBall() then return end
    local state,holder,ball=getBallState()
    if state=="MISSING" then return end
    local targetRoot
    if holder and holder~=player and not sameTeam(holder) then targetRoot=getPlayerRoot(holder)
    elseif not holder and ball then targetRoot=ball end
    if targetRoot then rootPart.CFrame=CFrame.new(targetRoot.Position+Vector3.new(0,DEFAULT_STEAL_DISTANCE,0)) end
end

--========================================================--
-- TP RETURN
--========================================================--

local function restoreTemporaryTP(reason)
    if not State.tpActive then return end
    local saved=State.tpReturnCFrame
    State.tpActive=false
    State.tpReturnCFrame=nil
    if saved and updateCharacter() and rootPart then rootPart.CFrame=saved end
    if reason then notify("TP RETURN",reason,1.2) end
end

local function startTemporaryTP()
    if State.tpActive then restoreTemporaryTP("Returned"); return end
    if not updateCharacter() or not rootPart then notify("TP RETURN","Không tìm thấy nhân vật",1.2); return end

    local state,holder,ball=getBallState()
    local targetPosition,targetName

    if state=="HELD" and holder and holder~=player and not sameTeam(holder) then
        local targetRoot=getPlayerRoot(holder)
        if targetRoot then targetPosition=targetRoot.Position+Vector3.new(0,DEFAULT_STEAL_DISTANCE,0); targetName=holder.Name end
    elseif state=="FREE" and ball then
        targetPosition=ball.Position+Vector3.new(0,DEFAULT_STEAL_DISTANCE,0)
        targetName="FREE BALL"
    end

    if not targetPosition then notify("TP RETURN","Không có bóng hợp lệ để TP",1.3); return end

    State.tpReturnCFrame=rootPart.CFrame
    State.tpActive=true
    State.tpStartedAt=os.clock()
    rootPart.CFrame=CFrame.new(targetPosition)
    notify("TP RETURN",string.format("TP → %s trong %.2fs",targetName,State.tpDuration),1.5)
end

--========================================================--
-- UI UPDATE
--========================================================--

local function modeName()
    if State.mode==1 then return "MODE 1 [CAMERA WASDEQ]" end
    if State.mode==2 then return "MODE 2 [CAMERA]" end
    if State.mode==3 then return "MODE 3 [CURVED ARC]" end
    if State.mode==4 then return "MODE 4 [RONALDO]" end
    return "MODE 5 [SKY WAIT]"
end

local function updateUI()
    controlButton.Text="CONTROL KEY: "..State.controlKey.Name
    modeButton.Text=modeName()..(State.mode==5 and State.mode5Stage=="WAITING" and " [READY]" or "")
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
    State.mode = State.mode + 1
    if State.mode > 5 then State.mode = 1 end
    resetMode5()
    State.mode3Active=false
    clearEndpoint()
    if State.mode~=1 and State.mode~=2 then
        State.enabled=false
        if rootPart then rootPart.Anchored=false end
        unlockPlayer()
        restoreCamera()
    end
    if State.mode==2 and State.enabled then
        local ball=findBall(); if ball then cameraToBall(ball) end
    elseif State.mode~=2 then restoreCamera() end
    applyModeLock()
    updateUI()
    notify("MODE",modeName(),1.3)
end)


stealButton.MouseButton1Click:Connect(function()
    State.stealBallEnabled = not State.stealBallEnabled

    -- Nếu vừa bật nhưng đang cầm bóng và đang chọn AUTO OFF,
    -- tắt ngay thay vì để nút hiển thị ON sai trạng thái.
    if State.stealBallEnabled and State.autoStealOffOnGet and localHasBall() then
        State.stealBallEnabled = false
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

tpTimeBox.FocusLost:Connect(function()
    local value=tonumber(tpTimeBox.Text)
    if not value then tpTimeBox.Text=tostring(State.tpDuration); return end
    State.tpDuration=math.clamp(value,0.1,60)
    tpTimeBox.Text=tostring(State.tpDuration)
end)
tpButton.MouseButton1Click:Connect(startTemporaryTP)

--========================================================--
-- RESTORED LEGACY UI BUTTONS
--========================================================--

anchorButton.MouseButton1Click:Connect(function()
    State.anchorEnabled = not State.anchorEnabled
    State.forceUnanchorActive = false
    anchorButton.Text = State.anchorEnabled and "ANCHOR: ON" or "ANCHOR: OFF"
    if not State.anchorEnabled then
        unlockPlayer()
    elseif State.enabled and (State.mode == 1 or State.mode == 2) then
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
    if input.UserInputType==Enum.UserInputType.MouseButton1 then State.leftMouseHeld=true; return end
    if input.UserInputType==Enum.UserInputType.MouseButton2 then
        State.rightMouseHeld=true
        if State.leftMouseHeld and (State.mode==3 or (State.mode==5 and State.mode5Stage=="WAITING")) then
            pickEndpoint()
        end
        return
    end
    if input.UserInputType~=Enum.UserInputType.Keyboard then return end

    if State.changingControlKey then
        if input.KeyCode==Enum.KeyCode.Escape then
            State.changingControlKey=false
            updateUI()
            return
        end
        if input.KeyCode~=Enum.KeyCode.Unknown then
            State.controlKey=input.KeyCode
            State.changingControlKey=false
            updateUI()
            notify("CONTROL KEY","Set to "..State.controlKey.Name,1.4)
        end
        return
    end

    if input.KeyCode==State.controlKey then
        -- Endpoint selection/launch takes priority for Mode 3/5 when both mouse buttons are held.
        if State.leftMouseHeld and State.rightMouseHeld and (State.mode==3 or (State.mode==5 and State.mode5Stage=="WAITING")) then
            local _,_,endpointBall=getBallState()
            if State.mode==3 then
                startMode3(endpointBall)
            else
                performMode5Action(endpointBall)
            end
            return
        end

        -- Sae Pass owns F only when endpoint selection is not active.
        if State.saePassEnabled and (State.rightMouseHeld or State.leftMouseHeld) then
            if handleSaeInput() then return end
        end

        local state,holder,ball=getBallState()
        if State.mode==1 or State.mode==2 then
            State.enabled=not State.enabled
            if State.enabled then
                State.forceUnanchorActive=false
                applyModeLock()
                if State.mode==2 and ball then cameraToBall(ball) end
                notify("CONTROL",modeName().." ACTIVE",1.1)
            else
                for k in pairs(State.keys) do State.keys[k]=false end
                restoreCamera()
                applyModeLock()
                notify("CONTROL","OFF",1.0)
            end
            updateUI()
            return
        elseif State.mode==3 then
            if State.saePassEnabled and State.rightMouseHeld then return end
            startMode3(ball)
            return
        elseif State.mode==4 then
            if localHasBall() then performMode4Kick(ball) else notify("MODE 4","Cần đang cầm bóng",1.2) end
            return
        elseif State.mode==5 then
            performMode5Action(ball)
            updateUI()
            return
        end
    end

    if gameProcessed then return end
    if input.KeyCode==Enum.KeyCode.W then State.keys.W=true end
    if input.KeyCode==Enum.KeyCode.A then State.keys.A=true end
    if input.KeyCode==Enum.KeyCode.S then State.keys.S=true end
    if input.KeyCode==Enum.KeyCode.D then State.keys.D=true end
    if input.KeyCode==Enum.KeyCode.Q then State.keys.Q=true end
    if input.KeyCode==Enum.KeyCode.E then State.keys.E=true end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then State.leftMouseHeld=false; return end
    if input.UserInputType==Enum.UserInputType.MouseButton2 then State.rightMouseHeld=false; return end
    if input.UserInputType~=Enum.UserInputType.Keyboard then return end
    if input.KeyCode==Enum.KeyCode.W then State.keys.W=false end
    if input.KeyCode==Enum.KeyCode.A then State.keys.A=false end
    if input.KeyCode==Enum.KeyCode.S then State.keys.S=false end
    if input.KeyCode==Enum.KeyCode.D then State.keys.D=false end
    if input.KeyCode==Enum.KeyCode.Q then State.keys.Q=false end
    if input.KeyCode==Enum.KeyCode.E then State.keys.E=false end
end)

--========================================================--
-- HEARTBEAT
--========================================================--

RunService.Heartbeat:Connect(function(dt)
    updateCharacter()
    updateMode3()
    updateMode5()
    updateSaePass()

    local state,holder,ball=getBallState()
    updateBallStatusUI(state,holder,ball)

    -- Auto OFF được kiểm tra độc lập với lastHolder để không phụ thuộc cache.
    if State.stealBallEnabled and State.autoStealOffOnGet and localHasBall() then
        State.stealBallEnabled = false
        notify("STEAL BALL", "Tự động tắt — bạn đã có bóng", 1.4)
    end

    if holder~=State.lastHolder then
        if holder==player and State.lastHolder~=player then
            notify("BALL CONTROL","Ball is now yours",1.5)
        elseif State.lastHolder==player and holder~=player and not State.saePassActive then
            notify("BALL CONTROL","Ball left local player",1.2)
        end
        State.lastHolder=holder
    end

    if State.tpActive then
        if state=="HELD" and holder==player then
            restoreTemporaryTP("Ball is yours")
        elseif os.clock()-State.tpStartedAt>=State.tpDuration then
            restoreTemporaryTP("TP timer expired")
        end
    end

    if State.stealBallEnabled then
        if State.autoStealOffOnGet and localHasBall() then
            State.stealBallEnabled = false
        else
            State.stealCooldown += dt
            if State.stealCooldown >= 0.025 then
                stealBallStep()
                State.stealCooldown = 0
            end
        end
    end

    if State.enabled and ball then
        if State.mode==1 then controlMode1(ball)
        elseif State.mode==2 then controlMode2(ball) end
    end

    if State.saePassActive and holder and holder~=player and holder==State.saePassTarget then
        clearTarget()
        notify("SAE PASS","Target received the ball",1.3)
    elseif State.saePassActive and holder and holder~=player and holder~=State.saePassTarget then
        clearTarget()
        notify("SAE PASS","Another player received the ball",1.3)
    end

    if State.mode==1 or State.mode==2 then
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
    resetMode5()
    State.mode3Active=false
    clearEndpoint()
    State.tpActive=false
    State.tpReturnCFrame=nil
    State.forceUnanchorActive=false
    if State.enabled and (State.mode==1 or State.mode==2) and State.anchorEnabled then applyModeLock() else unlockPlayer() end
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
notify("BALL CONTROLLER","V3 loaded",1.5)
print("[Ball Controller V3] loaded")
