--========================================================--
-- BALL CONTROLLER V4.5 (FULL LOGIC & FIXED UI)
-- 
-- FIXES IN THIS VERSION:
-- • Repositioned UI Restore & F Action buttons to BOTTOM RIGHT corner
-- • Smooth touch dragging for Mobile (instant touch move)
-- • FORCE_MOBILE_UI variable placed at top of CFG for easy testing
-- • Mode 2 & Advance Mode completely hidden on Mobile UI
-- • Restored 100% full gameplay logic (Auto Goal, Special Steal, Sae Pass, Ronaldo Advance)
--========================================================--

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")

local CFG = {
    -- BIẾN TEST FORCE MOBILE UI BÊN NGOÀI
    FORCE_MOBILE_UI = true,

    BALL_NAME = "Ball",

    MIN_SPEED = 1,
    MAX_SPEED = 1000,

    CONTROL_KEY = Enum.KeyCode.F,

    STEAL_DISTANCE = 3,
    TP_TIME = 1.5,

    SHOOT_FORCE = 100,
    AUTO_GOAL_SHOOT_FORCE = 150,
    AUTO_GOAL_SHOOT_INTERVAL = 0.06,

    GK_ROLES = {
        gk = true,
        goalkeeper = true,
        ["goal keeper"] = true,
        keeper = true,
    },

    GK_OFFSET = Vector3.new(0, 2.5, 0),
    GOAL_OFFSET = Vector3.new(0, 3, 10),

    STEAL_INTERVAL = 0.08,
    SPECIAL_INTERVAL = 0.14,
    CACHE_INTERVAL = 0.04,

    ZOOM_MIN = 0.6,
    ZOOM_MAX = 1.6,
    ZOOM_STEP = 0.1,
}

local Mode = {
    [1] = { speed = 60 },
    [2] = { speed = 140 },
}

local State = {
    mode = 1,
    controlKey = CFG.CONTROL_KEY,
    enabled = false,
    anchor = true,
    forceUnanchor = false,
    steal = false,

    autoGoal = false,
    autoGoalBusy = false,
    autoGoalToken = 0,
    lastAutoGoal = 0,

    tpActive = false,
    tpStarted = 0,
    tpReturn = nil,
    tpGoalActive = false,
    tpDuration = CFG.TP_TIME,

    settingsTab = 1,

    -- SAE
    sae = false,
    saeActive = false,
    saeTarget = nil,
    saeBall = nil,
    saeStage = "IDLE",
    saeHighlight = nil,
    saeHighlightEnabled = true,
    saeTempActive = false,
    saeWasHoldingBall = false,

    -- Ronaldo
    ronaldo = false,
    ronaldoTarget = nil,
    ronaldoBall = nil,
    ronaldoActive = false,
    ronaldoTouch = nil,
    ronaldoStart = 0,
    ronaldoDirection = nil,

    -- Advance
    advance = false,

    keys = { W = false, A = false, S = false, D = false, Q = false, E = false },
    changingKey = false,
    minimized = false,
    settingsOpen = false,

    uiScale = 1,
    specialSelecting = false,
    responsiveScale = 1,
    forceMobileUI = CFG.FORCE_MOBILE_UI,

    autoGoalTarget = "AutoGoal",
    autoStealOffOnGet = true,

    leftMouseHeld = false,
    rightMouseHeld = false,
    lastSteal = 0,

    special = { active = false, target = nil, step = 1, nextAt = 0, startedAt = 0, character = "" },
}

local Tracker = { state = "UNKNOWN", holder = nil, ball = nil, last = 0, queued = false }
local Char = { model = nil, humanoid = nil, root = nil, locked = false, walk = nil, jump = nil, rotate = nil }
local CameraState = { type = nil, subject = nil }
local UI: any = { ready = false }

State.__uiStablePositions = {}
State.__dragConsumed = {}

local Connections = {}
local CharConnections = {}
local PlayerConnections = {}
local API: any = {}
local camera = workspace.CurrentCamera

--========================================================--
-- ENV / PERSISTENCE
--========================================================--

local CONFIG_FILE = "BallController_V4_5_Settings.json"
local Persist: any = { key = "__BALL_CONTROLLER_V4_5_CONFIG", data = {} }

local function safeDecodeJson(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local ok, result = pcall(function() return HttpService:JSONDecode(raw) end)
    return ok and type(result) == "table" and result or nil
end

local function loadPersistedConfig()
    local data = nil
    pcall(function()
        if type(isfile) == "function" and isfile(CONFIG_FILE) and type(readfile) == "function" then
            data = safeDecodeJson(readfile(CONFIG_FILE))
        end
    end)
    if not data and type(getgenv()[Persist.key]) == "table" then
        data = getgenv()[Persist.key]
    end
    Persist.data = type(data) == "table" and data or {}
end

local function savePersistedConfig()
    local data = Persist.data or {}
    getgenv()[Persist.key] = data
    pcall(function()
        if type(writefile) == "function" and HttpService then
            writefile(CONFIG_FILE, HttpService:JSONEncode(data))
        end
    end)
end

loadPersistedConfig()

do
    local c = Persist.data or {}
    if type(c.uiScale) == "number" then State.uiScale = math.clamp(c.uiScale, CFG.ZOOM_MIN, CFG.ZOOM_MAX) end
    if type(c.anchor) == "boolean" then State.anchor = c.anchor end
    if type(c.autoStealOffOnGet) == "boolean" then State.autoStealOffOnGet = c.autoStealOffOnGet end
    if type(c.saeHighlightEnabled) == "boolean" then State.saeHighlightEnabled = c.saeHighlightEnabled end
    if type(c.tpDuration) == "number" then State.tpDuration = math.clamp(c.tpDuration, 0.1, 60) end
    if c.autoGoalTarget == "AutoGoal" or c.autoGoalTarget == "ScoreHitbox" then State.autoGoalTarget = c.autoGoalTarget end
    if type(c.controlKey) == "string" and Enum.KeyCode[c.controlKey] then State.controlKey = Enum.KeyCode[c.controlKey] end
    if type(c.mode1Speed) == "number" then Mode[1].speed = math.clamp(c.mode1Speed, CFG.MIN_SPEED, CFG.MAX_SPEED) end
    if type(c.mode2Speed) == "number" then Mode[2].speed = math.clamp(c.mode2Speed, CFG.MIN_SPEED, CFG.MAX_SPEED) end
    if type(c.uiPositions) == "table" then
        for name, pos in pairs(c.uiPositions) do
            if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
                State.__uiStablePositions[name] = Vector2.new(pos.x, pos.y)
            end
        end
    end
end

local function saveConfig()
    Persist.data = Persist.data or {}
    Persist.data.uiScale = State.uiScale
    Persist.data.anchor = State.anchor
    Persist.data.autoStealOffOnGet = State.autoStealOffOnGet
    Persist.data.saeHighlightEnabled = State.saeHighlightEnabled
    Persist.data.tpDuration = State.tpDuration
    Persist.data.autoGoalTarget = State.autoGoalTarget
    Persist.data.controlKey = State.controlKey and State.controlKey.Name or nil
    Persist.data.mode1Speed = Mode[1].speed
    Persist.data.mode2Speed = Mode[2].speed
    savePersistedConfig()
end

local oldStop = getgenv().__BALL_CONTROLLER_V4_STOP
if oldStop then pcall(oldStop) end

function API.disconnect(conn)
    if conn then pcall(function() conn:Disconnect() end) end
end

function API.disconnectList(list)
    if not list then return end
    for i = 1, #list do API.disconnect(list[i]) end
    table.clear(list)
end

function API.bind(signal, callback)
    local conn = signal:Connect(callback)
    Connections[#Connections + 1] = conn
    return conn
end

function API.bindLocal(list, signal, callback)
    local conn = signal:Connect(callback)
    list[#list + 1] = conn
    return conn
end

--========================================================--
-- CHARACTER & CAMERA
--========================================================--

function API.updateCharacter()
    Char.model = LP.Character
    if not Char.model then
        Char.humanoid = nil
        Char.root = nil
        return false
    end
    Char.humanoid = Char.model:FindFirstChildOfClass("Humanoid")
    Char.root = Char.model:FindFirstChild("HumanoidRootPart")
    return Char.humanoid ~= nil and Char.root ~= nil
end

function API.lockPlayer()
    if not API.updateCharacter() then return end
    if not State.enabled or not State.anchor or State.mode ~= 1 or State.forceUnanchor then
        Char.root.Anchored = false
        API.unlockPlayer()
        return
    end
    if Char.walk == nil then
        Char.walk = Char.humanoid.WalkSpeed
        Char.jump = Char.humanoid.JumpPower
        Char.rotate = Char.humanoid.AutoRotate
    end
    Char.humanoid.WalkSpeed = 0
    Char.humanoid.JumpPower = 0
    Char.humanoid.AutoRotate = false
    Char.root.Anchored = true
    Char.locked = true
end

function API.unlockPlayer()
    API.updateCharacter()
    if not Char.humanoid then
        Char.locked = false
        Char.walk = nil; Char.jump = nil; Char.rotate = nil
        return
    end
    if Char.locked then
        if Char.walk ~= nil then Char.humanoid.WalkSpeed = Char.walk end
        if Char.jump ~= nil then Char.humanoid.JumpPower = Char.jump end
        if Char.rotate ~= nil then Char.humanoid.AutoRotate = Char.rotate end
    end
    if Char.root then Char.root.Anchored = false end
    Char.locked = false
    Char.walk = nil; Char.jump = nil; Char.rotate = nil
end

function API.forceUnanchor()
    State.forceUnanchor = true
    API.unlockPlayer()
    API.notify("ANCHOR", "Force Unanchor executed", 1.4)
end

function API.notify(titleText, bodyText, duration)
    if not UI.notificationHolder or not UI.notificationHolder.Parent then return end
    duration = duration or 2.2
    local card = Instance.new("Frame")
    card.Size = UDim2.fromOffset(280, 58)
    card.AnchorPoint = Vector2.new(0.5, 0)
    card.Position = UDim2.new(0.5, 0, 0, -65)
    card.BackgroundColor3 = Color3.fromRGB(27, 27, 34)
    card.BorderSizePixel = 0
    card.Parent = UI.notificationHolder

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 9)
    c.Parent = card

    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(65, 65, 80)
    s.Transparency = 0.15
    s.Parent = card

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -18, 0, 22)
    title.Position = UDim2.fromOffset(9, 5)
    title.BackgroundTransparency = 1
    title.Text = tostring(titleText)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextColor3 = Color3.new(1, 1, 1)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card

    local body = Instance.new("TextLabel")
    body.Size = UDim2.new(1, -18, 0, 25)
    body.Position = UDim2.fromOffset(9, 27)
    body.BackgroundTransparency = 1
    body.Text = tostring(bodyText)
    body.Font = Enum.Font.Gotham
    body.TextSize = 11
    body.TextColor3 = Color3.fromRGB(175, 175, 185)
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.Parent = card

    TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, 8) }):Play()
    task.delay(duration, function()
        if not card.Parent then return end
        TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, -65) }):Play()
        task.delay(0.22, function() if card.Parent then card:Destroy() end end)
    end)
end

--========================================================--
-- BALL TRACKER & REMOTE
do
    local function playerModel(plr)
        if not plr then return nil end
        return workspace:FindFirstChild(plr.Name)
    end

    local function ballInPlayerModel(plr)
        local model = playerModel(plr)
        if not model then return nil end
        local ball = model:FindFirstChild(CFG.BALL_NAME)
        return ball and ball:IsA("BasePart") and ball or nil
    end

    local function freeBall()
        local direct = workspace:FindFirstChild(CFG.BALL_NAME)
        return direct and direct:IsA("BasePart") and direct or nil
    end

    function API.rebuildBall(force)
        local now = os.clock()
        if not force and now - Tracker.last < CFG.CACHE_INTERVAL then
            return Tracker.state, Tracker.holder, Tracker.ball
        end

        Tracker.last = now
        Tracker.queued = false
        Tracker.state = "UNKNOWN"
        Tracker.holder = nil
        Tracker.ball = nil

        for _, plr in ipairs(Players:GetPlayers()) do
            local ball = ballInPlayerModel(plr)
            if ball then
                Tracker.state = "HELD"
                Tracker.holder = plr
                Tracker.ball = ball
                return "HELD", plr, ball
            end
        end

        local ball = freeBall()
        if ball then
            Tracker.state = "FREE"
            Tracker.ball = ball
            return "FREE", nil, ball
        end

        Tracker.state = "MISSING"
        return "MISSING", nil, nil
    end

    function API.queueBallRebuild()
        if Tracker.queued then return end
        Tracker.queued = true
        task.defer(function()
            if Tracker.queued then API.rebuildBall(false) end
        end)
    end

    function API.getBallState()
        local state, holder, ball = Tracker.state, Tracker.holder, Tracker.ball

        if state == "HELD" then
            local current = ballInPlayerModel(holder)
            if holder and holder.Parent and current then
                Tracker.ball = current
                return "HELD", holder, current
            end
            return API.rebuildBall(false)
        end

        if state == "FREE" then
            local direct = freeBall()
            if direct then
                Tracker.ball = direct
                return "FREE", nil, direct
            end
            return API.rebuildBall(false)
        end

        return API.rebuildBall(false)
    end

    function API.localHasBall()
        local directMine = ballInPlayerModel(LP)
        if directMine then
            Tracker.state = "HELD"
            Tracker.holder = LP
            Tracker.ball = directMine
            Tracker.last = os.clock()
            return true
        end

        local state, holder = API.getBallState()
        return state == "HELD" and holder == LP
    end

    function API.playerRoot(plr)
        if not plr or not plr.Character then return nil end
        return plr.Character:FindFirstChild("HumanoidRootPart")
    end

    function API.sameTeam(plr)
        return plr and LP.Team and plr.Team == LP.Team
    end

    function API.attachCharacter(plr, char)
        API.disconnectList(CharConnections[plr])
        local list = {}

        API.bindLocal(list, char.DescendantAdded, function(obj)
            if obj.Name == CFG.BALL_NAME and obj:IsA("BasePart") then
                API.queueBallRebuild()
            end
        end)

        API.bindLocal(list, char.DescendantRemoving, function(obj)
            if obj == Tracker.ball then API.queueBallRebuild() end
        end)

        API.bindLocal(list, char.AncestryChanged, function(_, parent)
            if parent == nil then API.queueBallRebuild() end
        end)

        CharConnections[plr] = list
    end

    function API.attachPlayer(plr)
        API.disconnectList(PlayerConnections[plr])
        local list = {}

        if plr.Character then
            API.attachCharacter(plr, plr.Character)
        end

        API.bindLocal(list, plr.CharacterAdded, function(char)
            API.attachCharacter(plr, char)
            API.queueBallRebuild()
        end)

        API.bindLocal(list, plr.CharacterRemoving, function()
            API.queueBallRebuild()
        end)

        PlayerConnections[plr] = list
    end
end

-- Shoot Remote
do
    local remote, remoteReady, lastResolve = nil, false, 0
    function API.resolveShootRemote(force)
        local now = os.clock()
        if not force and now - lastResolve < 0.25 then return remote end
        lastResolve = now
        local events = ReplicatedStorage:FindFirstChild("Events")
        remote = events and events:FindFirstChild("ShootBall")
        remoteReady = remote and remote:IsA("RemoteEvent") or false
        return remote
    end

    function API.fireShoot(direction, force, third)
        if not remoteReady or not remote then API.resolveShootRemote(true) end
        if not remoteReady or not remote then
            API.notify("SHOOT REMOTE", "Events.ShootBall was not found", 1.5)
            return false
        end
        if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.001 then return false end
        local shootForce = math.clamp(
            tonumber(force) or CFG.SHOOT_FORCE,
            CFG.MIN_SPEED,
            CFG.MAX_SPEED
        )

        return pcall(function()
            remote:FireServer(direction.Unit, shootForce, third or false)
        end)
    end
    API.resolveShootRemote(true)
end

-- Camera Control
do
    function API.saveCamera(subject)
        camera = workspace.CurrentCamera
        if not camera then return end
        if CameraState.type == nil then CameraState.type = camera.CameraType end
        if CameraState.subject == nil and camera.CameraSubject ~= subject then
            CameraState.subject = camera.CameraSubject
        end
    end

    function API.followBall(ball)
        if not ball then return end
        camera = workspace.CurrentCamera
        if not camera then return end
        API.saveCamera(ball)
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = ball
    end

    function API.restoreCamera()
        camera = workspace.CurrentCamera
        if not camera then return end
        API.updateCharacter()
        camera.CameraType = CameraState.type or Enum.CameraType.Custom
        if Char.humanoid and Char.humanoid.Parent then
            camera.CameraSubject = Char.humanoid
        elseif CameraState.subject and CameraState.subject.Parent then
            camera.CameraSubject = CameraState.subject
        end
        CameraState.type = nil; CameraState.subject = nil
    end

    function API.cameraDirection()
        camera = workspace.CurrentCamera
        if not camera then return Vector3.new(0, 0, -1) end
        local v = camera.CFrame.LookVector
        return v.Magnitude > 0 and v.Unit or Vector3.new(0, 0, -1)
    end

    function API.flatDirections()
        camera = workspace.CurrentCamera
        if not camera then return Vector3.new(0,0,-1), Vector3.new(1,0,0) end
        local f = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
        local r = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
        return f.Magnitude > 0 and f.Unit or Vector3.new(0,0,-1), r.Magnitude > 0 and r.Unit or Vector3.new(1,0,0)
    end
end

-- GOAL & ROLE HELPERS
do
    function API.characterName()
        local values = LP:FindFirstChild("Values")
        local obj = values and values:FindFirstChild("CharacterName")
        if not obj or obj.Value == nil then return "" end
        return string.lower(string.gsub(tostring(obj.Value), "%s+", ""))
    end

    function API.roleName()
        local role = LP:FindFirstChild("Role")
        if role and role.Value ~= nil then return string.lower(tostring(role.Value)) end
        local values = LP:FindFirstChild("Values")
        local obj = values and values:FindFirstChild("Role")
        if obj and obj.Value ~= nil then return string.lower(tostring(obj.Value)) end
        if Char.model then
            local obj2 = Char.model:FindFirstChild("Role")
            if obj2 and obj2.Value ~= nil then return string.lower(tostring(obj2.Value)) end
        end
        return ""
    end

    function API.isGK()
        local role = string.gsub(API.roleName(), "%s+", " ")
        return CFG.GK_ROLES[role] == true
    end

    function API.isHome()
        return LP.Team and string.lower(LP.Team.Name) == "home"
    end

    function API.goalHitbox(homeSide)
        local map = workspace:FindFirstChild("Map")
        if not map then return nil end
        local model = map:FindFirstChild(homeSide and "PlayerOneGoal" or "PlayerTwoGoal")
        if not model then return nil end
        local score = model:FindFirstChild("ScoreHitbox") or model:FindFirstChild("Score")
        if score and score:IsA("BasePart") then return score end
        local hitbox = model:FindFirstChild("ScoreHitbox", true)
        if hitbox and hitbox:IsA("BasePart") then return hitbox end
        return model:FindFirstChildWhichIsA("BasePart", true)
    end

    function API.goalArea(homeSide)
        local obj = workspace:FindFirstChild(homeSide and "PlayerOneGoalArea" or "PlayerTwoGoalArea")
        if not obj then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true) end
        return nil
    end

    function API.ownGoal()
        local home = API.isHome()
        return API.goalArea(home) or API.goalHitbox(home)
    end

    function API.autoGoalTarget(homeSide)
        local map = workspace:FindFirstChild("Map")
        if not map then return nil end
        local model = map:FindFirstChild(homeSide and "PlayerOneGoal" or "PlayerTwoGoal")
        if not model then return nil end
        local target = model:FindFirstChild("AutoGoal")
        if not target then return nil end
        if target:IsA("BasePart") or target:IsA("Attachment") then return target end
        if target:IsA("Model") then
            return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true) or target:FindFirstChildWhichIsA("Attachment", true)
        end
        return target:FindFirstChildWhichIsA("BasePart", true) or target:FindFirstChildWhichIsA("Attachment", true)
    end

    function API.goalPosition(goal)
        if not goal or not goal.Parent then return nil end
        if goal:IsA("BasePart") then return goal.Position end
        if goal:IsA("Attachment") then return goal.WorldPosition end
        if goal:IsA("Model") then
            local part = goal.PrimaryPart or goal:FindFirstChildWhichIsA("BasePart", true)
            return part and part.Position or nil
        end
        return nil
    end

    function API.selectedGoal(homeSide)
        local selected = State.autoGoalTarget == "ScoreHitbox" and "ScoreHitbox" or "AutoGoal"

        if selected == "ScoreHitbox" then
            return API.goalHitbox(homeSide) or API.autoGoalTarget(homeSide)
        end

        return API.autoGoalTarget(homeSide) or API.goalHitbox(homeSide)
    end

    function API.opponentGoal()
        return API.selectedGoal(not API.isHome())
    end

    function API.inGoal(pos, goal)
        local goalPos = API.goalPosition(goal)
        return pos and goalPos and (pos - goalPos).Magnitude <= 18
    end
end

--========================================================--
-- ABILITIES & SPECIAL STEAL LOGIC
--========================================================--

do
    local Abilities = {
        default = { canSlide = true, canSlideTeammate = false },
        barou = { canSlide = true, canSlideTeammate = true, special = { name = "BAROU 3", key = Enum.KeyCode.Three, mode = "OPPONENT", repeatHeld = true, interval = 0.14, offset = Vector3.new(0, 5.5, 0) } },
        shidou = { canSlide = true, canSlideTeammate = false, special = { name = "SHIDOU 3", key = Enum.KeyCode.Three, mode = "OPPONENT", repeatHeld = true, interval = 0.16, offset = Vector3.new(0, 5.5, 0) } },
        naoya = { canSlide = true, canSlideTeammate = false, special = { name = "NAOYA 2 -> 3", mode = "OPPONENT", interval = 0.16, offset = Vector3.new(0, 5.5, 0), steps = { { key = Enum.KeyCode.Two, waitPossession = true }, { key = Enum.KeyCode.Three, finish = true } } } },
        kaiser = { canSlide = true, canSlideTeammate = false, special = { name = "KAISER 3", key = Enum.KeyCode.Three, mode = "TEAMMATE", repeatHeld = true, interval = 0.16, offset = Vector3.new(0, 5.5, 0) } },
        gagamaru = { canSlide = true, canSlideTeammate = false, special = { name = "GAGAMARU 3", key = Enum.KeyCode.Three, mode = "OPPONENT", oneShot = true, interval = 0.18, offset = Vector3.new(0, 5.5, 0) } },
        ichigo = { canSlide = true, canSlideTeammate = false, special = { name = "ICHIGO 1", key = Enum.KeyCode.One, mode = "OPPONENT", oneShot = true, interval = 0.18, offset = Vector3.new(0, 5.5, 0) } },
        donlorenzo = { canSlide = true, canSlideTeammate = false, special = { name = "DON LORENZO 2", key = Enum.KeyCode.Two, mode = "OPPONENT", oneShot = true, interval = 0.18, offset = Vector3.new(0, 5.5, 0) } },
        chigiri = { canSlide = true, canSlideTeammate = false, special = { name = "CHIGIRI 1", key = Enum.KeyCode.One, mode = "OPPONENT", oneShot = true, interval = 0.16, offset = Vector3.new(0, 5.5, 0) } },
    }

    function API.ability()
        return Abilities[API.characterName()] or Abilities.default
    end

    function API.resetSpecial()
        State.special.active = false
        State.special.target = nil
        State.special.step = 1
        State.special.nextAt = 0
        State.special.startedAt = 0
        State.special.character = ""
    end

    local function targetForSpecial(special)
        local state, holder = API.getBallState()
        if state ~= "HELD" or not holder or holder == LP then return nil end
        local teammate = API.sameTeam(holder)
        local mode = special.mode or "OPPONENT"
        if mode == "OPPONENT" and teammate then return nil end
        if mode == "TEAMMATE" and not teammate then return nil end
        if mode == "ANY" and teammate and not special.allowTeammate then return nil end
        local root = API.playerRoot(holder)
        return root and root.Parent and holder or nil
    end

    local function specialStillValid(target)
        if not target or not target.Parent then return false end
        local state, holder = API.getBallState()
        return state == "HELD" and holder == target
    end

    local function tpUse(target, keyCode, offset)
        local root = API.playerRoot(target)
        if not root or not root.Parent then return false end
        if not API.updateCharacter() or not Char.root or not Char.root.Parent then return false end
        offset = typeof(offset) == "Vector3" and offset or Vector3.new(0, 5.5, 0)
        Char.root.CFrame = CFrame.new(root.Position + offset, root.Position)
        return API.sendKey(keyCode)
    end

    function API.specialSteal()
        local ability = API.ability()
        local special = ability.special

        if not special then
            API.resetSpecial()
            return false
        end

        local charName = API.characterName()
        if State.special.active and State.special.character ~= charName then
            API.resetSpecial()
        end

        local now = os.clock()

        if not State.special.active then
            local target = targetForSpecial(special)
            if not target then return false end

            State.special.active = true
            State.special.target = target
            State.special.step = 1
            State.special.nextAt = now
            State.special.startedAt = now
            State.special.character = charName
        elseif State.special.startedAt > 0 and now - State.special.startedAt > 0.9 then
            API.resetSpecial()
            return false
        end

        local target = State.special.target
        if not target or not target.Parent then
            API.resetSpecial()
            return false
        end

        local root = API.playerRoot(target)
        if not root then
            API.resetSpecial()
            return false
        end

        if special.steps then
            local step = special.steps[State.special.step]
            if not step then
                API.resetSpecial()
                return false
            end

            if step.waitPossession then
                if not API.localHasBall() then
                    if not specialStillValid(target) then
                        API.resetSpecial()
                        return false
                    end
                    return true
                end

                State.special.step += 1
                step = special.steps[State.special.step]

                if not step then
                    API.resetSpecial()
                    return true
                end
            end

            -- Cooldown window: let normal E fallback run instead of blocking Auto Steal.
            if now < State.special.nextAt then
                return false
            end

            if not specialStillValid(target) and not API.localHasBall() then
                API.resetSpecial()
                return false
            end

            local used = tpUse(target, step.key, step.offset or special.offset)
            if not used then
                API.resetSpecial()
                return false
            end

            State.special.nextAt = now + (step.interval or special.interval or CFG.SPECIAL_INTERVAL)

            if step.finish then
                API.resetSpecial()
            end

            return true
        end

        if now < State.special.nextAt then
            return false
        end

        if not special.oneShot and not specialStillValid(target) then
            API.resetSpecial()
            return false
        end

        local used = tpUse(target, special.key, special.offset)
        if not used then
            API.resetSpecial()
            return false
        end

        if special.oneShot then
            API.resetSpecial()
        else
            State.special.nextAt = now + (special.interval or CFG.SPECIAL_INTERVAL)
        end

        return true
    end

    function API.normalStealTarget()
        local ability = API.ability()
        if not ability.canSlide then return nil end

        API.rebuildBall(false)
        local state, holder, ball = Tracker.state, Tracker.holder, Tracker.ball
        if state == "HELD" and holder then
            if holder == LP then return nil end
            if API.sameTeam(holder) and not ability.canSlideTeammate then return nil end
            return API.playerRoot(holder)
        end
        if state == "FREE" and ball and ball.Parent then return ball end
        return nil
    end

    function API.sendKey(keyCode)
        if VirtualInputManager then
            local ok = pcall(function()
                VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
                task.delay(0.03, function()
                    pcall(function() VirtualInputManager:SendKeyEvent(false, keyCode, false, game) end)
                end)
            end)
            if ok then return true end
        end
        return false
    end

    local function tryWeldBall(ball)
        if not ball or not ball.Parent then return false end
        local event = ball:FindFirstChild("WeldBall")
        if event and event:IsA("RemoteEvent") then
            return pcall(function()
                event:FireServer()
            end)
        end
        return false
    end

    function API.stealStep()
        if not API.updateCharacter() or not Char.root or not Char.root.Parent then return end
        if API.localHasBall() then API.resetSpecial(); return end
        local now = os.clock()
        if now - State.lastSteal < CFG.STEAL_INTERVAL then return end

        if API.specialSteal() then State.lastSteal = now; return end

        local target = API.normalStealTarget()
        if not target or not target.Parent then return end

        State.lastSteal = now
        if API.isGK() then
            local goal = API.ownGoal()
            if goal then
                Char.root.CFrame = CFrame.new(goal.Position + CFG.GK_OFFSET)
                API.sendKey(Enum.KeyCode.Q)
            end
        end

        Char.root.CFrame = CFrame.new(target.Position + Vector3.new(0, CFG.STEAL_DISTANCE, 0))

        if target:IsA("BasePart") and target.Name == CFG.BALL_NAME then
            tryWeldBall(target)
        end

        API.sendKey(Enum.KeyCode.E)
    end
end

--========================================================--
-- BALL RELEASE & TELEPORT HELPERS
--========================================================--

do
    function API.waitBallReleased(ball, timeout)
        timeout = timeout or 0.75
        if not ball then return false end
        local deadline = os.clock() + timeout
        while os.clock() < deadline do
            if not ball.Parent then return false end
            API.rebuildBall(true)
            local state, holder, current = API.getBallState()
            local insideLocal = Char.model and ball:IsDescendantOf(Char.model)
            if not insideLocal and (current == ball or state == "FREE" or holder ~= LP) then
                return true
            end
            RunService.Heartbeat:Wait()
        end
        return false
    end

    function API.getBallAfterRelease(ball)
        if ball and ball.Parent and Char.model and not ball:IsDescendantOf(Char.model) then return ball end
        API.rebuildBall(true)
        local state, holder, current = API.getBallState()
        if current and current.Parent and (state ~= "HELD" or holder ~= LP) and (not Char.model or not current:IsDescendantOf(Char.model)) then
            return current
        end
        return nil
    end

    function API.waitForReleasedBall(ball, timeout)
        if not API.waitBallReleased(ball, timeout or 0.75) then return nil end
        RunService.Heartbeat:Wait()
        RunService.Heartbeat:Wait()
        return API.getBallAfterRelease(ball)
    end

    function API.teleportReleasedBall(ball, goal)
        if not goal or not goal.Parent then return false end
        local released = API.waitForReleasedBall(ball, 0.75)
        if not released or not released.Parent then return false end
        pcall(function()
            released.CFrame = goal.CFrame
            released.AssemblyLinearVelocity = Vector3.zero
            released.AssemblyAngularVelocity = Vector3.zero
        end)
        return true
    end
end

-- RONALDO & SAE ADVANCED
do
    function API.stopRonaldo()
        State.ronaldoActive = false; State.ronaldoBall = nil; State.ronaldoTarget = nil
    end

    function API.clearSAE()
        State.saeActive = false; State.saeTarget = nil; State.saeBall = nil; State.saeStage = "IDLE"
        if State.saeHighlight then State.saeHighlight:Destroy(); State.saeHighlight = nil end
    end

    function API.isMobileUI()
        if CFG.FORCE_MOBILE_UI or State.forceMobileUI then return true end
        return UIS.TouchEnabled and not UIS.KeyboardEnabled
    end
end

--========================================================--
-- TELEPORT & TP GOAL LOGIC
--========================================================--

do
    function API.restoreTP(reason)
        if not State.tpActive then return end
        local saved = State.tpReturn
        State.tpActive = false; State.tpReturn = nil; State.tpGoalActive = false
        if saved and API.updateCharacter() and Char.root and Char.root.Parent then
            Char.root.CFrame = saved
        end
        if reason then API.notify("TP RETURN", reason, 1.2) end
    end

    function API.startTP()
        if State.tpActive then API.restoreTP("Returned"); return end
        if not API.updateCharacter() or not Char.root then API.notify("TP RETURN", "Character not found", 1.2); return end

        State.tpReturn = Char.root.CFrame
        local state, holder, ball = API.getBallState()
        local pos, name = nil, nil

        if state == "HELD" and holder and holder ~= LP then
            local root = API.playerRoot(holder)
            if root then pos = root.Position + Vector3.new(0, CFG.STEAL_DISTANCE, 0); name = holder.Name end
        elseif state == "FREE" and ball then
            pos = ball.Position + Vector3.new(0, CFG.STEAL_DISTANCE, 0); name = "FREE BALL"
        end

        if not pos then State.tpReturn = nil; API.notify("TP RETURN", "No valid ball for TP", 1.2); return end

        State.tpActive = true
        State.tpStarted = os.clock()
        Char.root.CFrame = CFrame.new(pos)
        API.notify("TP RETURN", string.format("TP -> %s", name), 1.3)
    end

    function API.tpGoal()
        local goal = API.opponentGoal()
        local goalPos = API.goalPosition(goal)
        if not goal or not goalPos then API.notify("TP GOAL", "Opponent Goal not found", 1.2); return end

        local state, holder, ball = API.getBallState()
        if not ball or not ball.Parent then API.notify("TP GOAL", "Ball not found", 1.2); return end

        if state == "HELD" and holder == LP then
            local direction = goalPos - ball.Position
            if direction.Magnitude < 0.001 then return end
            if not API.fireShoot(direction.Unit, CFG.SHOOT_FORCE, false) then return end

            local released = API.waitForReleasedBall(ball, 0.8)
            if released and API.teleportReleasedBall(released, goal) then
                State.tpGoalActive = true
                API.notify("TP GOAL", "Shot registered -> ball TP to goal", 1.1)
            end
            return
        end

        if state == "FREE" then
            pcall(function()
                ball.CFrame = goal.CFrame
                ball.AssemblyLinearVelocity = Vector3.zero
            end)
            API.notify("TP GOAL", "Free ball -> goal", 1.1)
        end
    end
end

--========================================================--
-- DRAGGABLE ENGINE (SMOOTH TOUCH ON MOBILE)
--========================================================--

function API.makeDraggable(object, handle)
    if not object or not handle then return false end

    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    API.bind(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input
            dragStart = input.Position
            startPos = object.Position

            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if conn then conn:Disconnect() end
                end
            end)
        end
    end)

    API.bind(UIS.InputChanged, function(input)
        if not dragging or not dragStart or not startPos or not object.Parent then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement then
                camera = workspace.CurrentCamera
                local view = camera and camera.ViewportSize or Vector2.new(1920, 1080)
                local delta = input.Position - dragStart

                local x = math.clamp(startPos.X.Offset + delta.X, 0, math.max(0, view.X - object.AbsoluteSize.X))
                local y = math.clamp(startPos.Y.Offset + delta.Y, 0, math.max(0, view.Y - object.AbsoluteSize.Y))

                object.Position = UDim2.fromOffset(x, y)
                State.__dragConsumed[object] = true

                for name, obj in pairs(UI) do
                    if obj == object then
                        State.__uiStablePositions[name] = Vector2.new(x, y)
                        Persist.data.uiPositions = Persist.data.uiPositions or {}
                        Persist.data.uiPositions[name] = { x = x, y = y }
                        savePersistedConfig()
                        break
                    end
                end
            end
        end
    end)

    API.bind(UIS.InputEnded, function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            dragInput = nil
        end
    end)

    return true
end

--========================================================--
-- BUILD UI & BUTTON PLACEMENT
--========================================================--

do
    local function corner(parent, radius)
        local x = Instance.new("UICorner")
        x.CornerRadius = UDim.new(0, radius or 8)
        x.Parent = parent
    end

    local function button(parent, text, x, y, w, h)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(w, h)
        b.Position = UDim2.fromOffset(x, y)
        b.BackgroundColor3 = Color3.fromRGB(43, 43, 51)
        b.BorderSizePixel = 0
        b.Text = text
        b.TextColor3 = Color3.fromRGB(235, 235, 240)
        b.TextSize = 12
        b.Font = Enum.Font.GothamMedium
        b.Parent = parent
        corner(b, 7)
        return b
    end

    local function label(parent, text, x, y, w, h, size)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.fromOffset(w, h)
        l.Position = UDim2.fromOffset(x, y)
        l.BackgroundTransparency = 1
        l.Text = text
        l.TextColor3 = Color3.fromRGB(205, 205, 215)
        l.TextSize = size or 12
        l.Font = Enum.Font.GothamMedium
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = parent
        return l
    end

    local function box(parent, value, x, y, w, h)
        local b = Instance.new("TextBox")
        b.Size = UDim2.fromOffset(w, h)
        b.Position = UDim2.fromOffset(x, y)
        b.BackgroundColor3 = Color3.fromRGB(40, 40, 47)
        b.BorderSizePixel = 0
        b.Text = tostring(value)
        b.TextColor3 = Color3.new(1, 1, 1)
        b.TextSize = 12
        b.Font = Enum.Font.GothamMedium
        b.ClearTextOnFocus = false
        b.Parent = parent
        corner(b, 7)
        return b
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BallController"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = -100
    gui.Parent = PlayerGui
    UI.gui = gui

    -- MAIN FRAME
    UI.main = Instance.new("Frame")
    UI.main.Size = UDim2.fromOffset(350, 468)
    UI.main.Position = UDim2.fromOffset(25, 220)
    UI.main.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
    UI.main.BorderSizePixel = 0
    UI.main.ClipsDescendants = true
    UI.main.Parent = gui
    corner(UI.main, 12)

    UI.title = label(UI.main, "⚽ BALL CONTROLLER V4.5", 10, 5, 240, 35, 18)
    UI.title.Font = Enum.Font.GothamBold

    UI.zoomOut = button(UI.main, "-", 228, 10, 26, 28)
    UI.zoomIn = button(UI.main, "+", 256, 10, 26, 28)
    UI.minimize = button(UI.main, "—", 312, 10, 28, 28)

    UI.mainScale = Instance.new("UIScale")
    UI.mainScale.Parent = UI.main

    UI.status = label(UI.main, "Status: READY", 10, 42, 320, 22, 13)
    UI.ballStatus = label(UI.main, "BALL: SEARCHING...", 10, 64, 320, 22, 12)

    UI.control = button(UI.main, "CONTROL KEY: F", 10, 92, 160, 36)
    UI.mode = button(UI.main, "MODE: 1 [CAMERA]", 180, 92, 160, 36)
    UI.anchor = button(UI.main, "ANCHOR: ON", 10, 136, 160, 36)
    UI.force = button(UI.main, "FORCE UNANCHOR", 180, 136, 160, 36)
    UI.steal = button(UI.main, "STEAL BALL: OFF", 10, 180, 160, 36)
    UI.sae = button(UI.main, "SAE PASS: OFF", 180, 180, 160, 36)
    UI.settings = button(UI.main, "⚙ SETTINGS", 10, 224, 160, 36)
    UI.statusToggle = button(UI.main, "BALL STATUS: ON", 180, 224, 160, 36)
    UI.tp = button(UI.main, "TP RETURN", 10, 268, 150, 36)
    UI.tpGoal = button(UI.main, "TP GOAL", 170, 268, 170, 36)
    UI.tpTimeLabel = label(UI.main, "TP TIME (S):", 10, 310, 85, 36, 11)
    UI.tpTime = box(UI.main, State.tpDuration, 100, 310, 70, 36)
    UI.moreMod = button(UI.main, "MORE MODS", 180, 310, 160, 36)

    UI.info = label(UI.main, "Mobile: use F ACTION for camera control.\nSTEAL BALL / AUTO GOAL run automatically.", 10, 350, 330, 45, 11)
    UI.info.TextWrapped = true
    UI.manual = button(UI.main, "USER MANUAL", 10, 408, 330, 36)

    -- FLOATING BUTTONS (NÚT BẬT TẮT UI VÀ F ACTION ĐƯỢC ĐẶT Ở GÓC PHẢI DƯỚI CÙNG)
    UI.restore = button(gui, "⚽", 0, 0, 48, 48)
    UI.restore.TextSize = 23
    corner(UI.restore, 24)

    UI.actionF = button(gui, "F ACTION", 0, 0, 86, 42)
    UI.actionF.ZIndex = 20
    corner(UI.actionF, 10)

    UI.specialToggle = button(gui, "SPECIAL: OFF", 0, 0, 110, 42)
    UI.specialToggle.ZIndex = 20
    corner(UI.specialToggle, 10)

    UI.actionF.Visible = false
    UI.specialToggle.Visible = false

    -- NOTIFICATIONS
    UI.notificationHolder = Instance.new("Frame")
    UI.notificationHolder.Size = UDim2.fromOffset(320, 300)
    UI.notificationHolder.AnchorPoint = Vector2.new(0.5, 0)
    UI.notificationHolder.Position = UDim2.new(0.5, 0, 0, 0)
    UI.notificationHolder.BackgroundTransparency = 1
    UI.notificationHolder.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Parent = UI.notificationHolder

    -- STATUS PANEL
    UI.statusPanel = Instance.new("Frame")
    UI.statusPanel.Size = UDim2.fromOffset(245, 125)
    UI.statusPanel.Position = UDim2.fromOffset(390, 80)
    UI.statusPanel.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
    UI.statusPanel.BorderSizePixel = 0
    UI.statusPanel.Parent = gui
    corner(UI.statusPanel, 10)

    UI.statusScale = Instance.new("UIScale")
    UI.statusScale.Parent = UI.statusPanel
    UI.statusTitle = label(UI.statusPanel, "⚽ BALL STATUS", 10, 5, 170, 25, 14)
    UI.statusTitle.Font = Enum.Font.GothamBold
    UI.statusMin = button(UI.statusPanel, "—", 180, 6, 25, 23)
    UI.statusClose = button(UI.statusPanel, "×", 210, 6, 25, 23)
    UI.statusState = label(UI.statusPanel, "STATUS: SEARCHING", 10, 35, 220, 22, 12)
    UI.statusOwner = label(UI.statusPanel, "OWNER: —", 10, 58, 220, 22, 12)
    UI.statusPlayer = label(UI.statusPanel, "CONTROL: OFF", 10, 81, 220, 22, 12)

    -- SETTINGS FRAME
    UI.settingsFrame = Instance.new("Frame")
    UI.settingsFrame.Size = UDim2.fromOffset(490, 320)
    UI.settingsFrame.Position = UDim2.fromOffset(390, 240)
    UI.settingsFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
    UI.settingsFrame.BorderSizePixel = 0
    UI.settingsFrame.ClipsDescendants = true
    UI.settingsFrame.Visible = false
    UI.settingsFrame.Parent = gui
    corner(UI.settingsFrame, 12)

    UI.settingsScale = Instance.new("UIScale")
    UI.settingsScale.Parent = UI.settingsFrame

    UI.settingsTitle = label(UI.settingsFrame, "⚙ BALL SETTINGS", 12, 8, 270, 32, 17)
    UI.settingsTitle.Font = Enum.Font.GothamBold
    UI.settingsZoomOut = button(UI.settingsFrame, "-", 378, 8, 26, 28)
    UI.settingsZoomIn = button(UI.settingsFrame, "+", 406, 8, 26, 28)
    UI.closeSettings = button(UI.settingsFrame, "X", 454, 8, 28, 28)

    UI.tabs = {
        button(UI.settingsFrame, "GENERAL", 10, 48, 104, 30),
        button(UI.settingsFrame, "MODE 1", 120, 48, 104, 30),
        button(UI.settingsFrame, "MODE 2", 230, 48, 104, 30),
    }

    local content = Instance.new("ScrollingFrame")
    content.Size = UDim2.new(1, -20, 1, -90)
    content.Position = UDim2.fromOffset(10, 88)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = 3
    content.ScrollingEnabled = true
    content.ScrollingDirection = Enum.ScrollingDirection.Y
    content.CanvasSize = UDim2.fromOffset(0, 420)
    content.Parent = UI.settingsFrame
    UI.settingsContent = content

    -- GENERAL SETTINGS
    UI.general = {}
    UI.general.title = label(content, "GENERAL SETTINGS", 10, 8, 220, 24, 13)
    UI.general.title.Font = Enum.Font.GothamBold

    UI.general.keyLabel = label(content, "CONTROL KEY", 10, 40, 110, 25, 12)
    UI.general.key = button(content, "F", 145, 36, 95, 32)

    UI.general.anchorLabel = label(content, "ANCHOR", 10, 80, 110, 25, 12)
    UI.general.anchor = button(content, "ON", 145, 76, 95, 32)

    UI.general.autoStealLabel = label(content, "AUTO STEAL OFF", 10, 120, 125, 25, 11)
    UI.general.autoSteal = button(content, "ON", 145, 116, 95, 32)

    UI.general.tpLabel = label(content, "TP RETURN TIME", 10, 160, 125, 25, 11)
    UI.general.tp = box(content, State.tpDuration, 145, 156, 95, 32)

    UI.general.autoGoalLabel = label(content, "AUTO GOAL", 10, 200, 110, 25, 12)
    UI.general.autoGoal = button(content, "OFF", 145, 196, 95, 32)

    UI.general.goalTargetLabel = label(content, "GOAL TARGET", 10, 240, 110, 25, 11)
    UI.general.goalTarget = button(content, "AUTOGOAL", 145, 236, 95, 32)

    UI.general.saeHighlightLabel = label(content, "SAE HIGHLIGHT", 255, 40, 135, 25, 12)
    UI.general.saeHighlight = button(content, "ON", 380, 36, 100, 32)

    UI.general.hint = label(content, "Auto Goal: steal -> shoot -> TP.\nTarget: AutoGoal or ScoreHitbox.", 255, 90, 225, 90, 10)
    UI.general.hint.TextWrapped = true

    -- MODE 1
    UI.m1 = {}
    UI.m1.speedLabel = label(content, "SPEED", 10, 10, 110, 25, 12)
    UI.m1.speed = box(content, Mode[1].speed, 120, 6, 220, 32)
    UI.m1.advanceLabel = label(content, "ADVANCE MODE", 10, 120, 110, 25, 12)
    UI.m1.advance = button(content, "OFF", 120, 116, 120, 32)
    UI.m1.hint = label(content, "WASD moves the ball; Q/E changes height.", 10, 70, 440, 100, 11)
    UI.m1.hint.TextWrapped = true

    -- MODE 2
    UI.m2 = {}
    UI.m2.speedLabel = label(content, "SPEED", 10, 10, 110, 25, 12)
    UI.m2.speed = box(content, Mode[2].speed, 120, 6, 145, 32)
    UI.m2.advanceLabel = label(content, "RONALDO ADVANCE", 10, 122, 120, 25, 12)
    UI.m2.advance = button(content, "OFF", 140, 118, 120, 32)
    UI.m2.hint = label(content, "Ronaldo Advance: select point, press F to kick.", 10, 70, 460, 100, 11)
    UI.m2.hint.TextWrapped = true

    UI.manualFrame = Instance.new("Frame")
    UI.manualFrame.Size = UDim2.fromOffset(520, 430)
    UI.manualFrame.Position = UDim2.fromOffset(390, 180)
    UI.manualFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
    UI.manualFrame.BorderSizePixel = 0
    UI.manualFrame.Visible = false
    UI.manualFrame.ZIndex = 200
    UI.manualFrame.Parent = gui
    corner(UI.manualFrame, 12)

    UI.manualTitle = label(UI.manualFrame, "USER MANUAL", 12, 8, 330, 30, 17)
    UI.manualTitle.Font = Enum.Font.GothamBold
    UI.manualTitle.ZIndex = 201

    UI.manualClose = button(UI.manualFrame, "X", 480, 8, 28, 28)
    UI.manualClose.ZIndex = 201

    UI.manualScroll = Instance.new("ScrollingFrame")
    UI.manualScroll.Size = UDim2.new(1, -20, 1, -52)
    UI.manualScroll.Position = UDim2.fromOffset(10, 45)
    UI.manualScroll.BackgroundColor3 = Color3.fromRGB(27, 27, 33)
    UI.manualScroll.BackgroundTransparency = 0.1
    UI.manualScroll.BorderSizePixel = 0
    UI.manualScroll.ScrollBarThickness = 4
    UI.manualScroll.ScrollingEnabled = true
    UI.manualScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    UI.manualScroll.CanvasSize = UDim2.fromOffset(0, 900)
    UI.manualScroll.ZIndex = 200
    UI.manualScroll.Parent = UI.manualFrame
    corner(UI.manualScroll, 8)

    UI.manualContent = label(UI.manualScroll, "", 12, 10, 480, 850, 11)
    UI.manualContent.TextWrapped = true
    UI.manualContent.TextYAlignment = Enum.TextYAlignment.Top
    UI.manualContent.ZIndex = 201

    UI.manualContent.Text = [[
BALL CONTROLLER — MOBILE USER MANUAL

1. F ACTION
Tap F ACTION to toggle Mode 1 ball control.
While active, the camera follows the ball.

2. STEAL BALL
Tap STEAL BALL to enable or disable Auto Steal.
The script checks the current ball holder and uses the matching steal behavior.
Special steals can fall back to normal E steal when needed.

3. AUTO STEAL OFF ON GET
When ON, Auto Steal turns OFF as soon as your character is detected holding the ball.

4. AUTO GOAL
Enable AUTO GOAL to automatically:
- get or steal the ball
- shoot toward the selected goal
- move the released ball to the selected target
- continuously apply a 150 shot force while Auto Goal stays enabled

5. GOAL TARGET
In Settings > General, tap GOAL TARGET to switch between:
- AUTOGOAL
- SCOREHITBOX

This target is used by TP GOAL and AUTO GOAL.

6. TP RETURN
TP RETURN moves you toward the current ball or ball holder.

7. BALL STATUS
BALL STATUS shows:
- HELD BY a player
- FREE
- MISSING

8. SETTINGS
General:
- Control Key
- Anchor
- Auto Steal Off On Get
- TP Return Time
- Auto Goal
- Goal Target
- SAE Highlight

Mode 1:
- Ball control speed

Mobile mode keeps PC-only controls hidden.

9. UI
Tap the ⚽ button to restore the main panel.
Drag the title bar with touch to reposition the panel.
USER MANUAL opens this guide.

10. NOTES
ShootBall Max has been removed from the mobile build.
Auto Goal uses the selected goal target.
]]

    local function refreshManualCanvas()
        if not UI.manualScroll.Parent or not UI.manualContent.Parent then return end

        local width = math.max(180, UI.manualScroll.AbsoluteSize.X - 24)
        local ok, bounds = pcall(function()
            return TextService:GetTextSize(
                UI.manualContent.Text or "",
                UI.manualContent.TextSize,
                UI.manualContent.Font,
                Vector2.new(width, 100000)
            )
        end)

        local height = ok and bounds.Y or 900
        height = math.max(120, height + 18)

        UI.manualContent.Size = UDim2.fromOffset(width, height)
        UI.manualScroll.CanvasSize = UDim2.fromOffset(
            0,
            math.max(height + 12, UI.manualScroll.AbsoluteWindowSize.Y + 1)
        )
    end

    UI.manualRefresh = refreshManualCanvas

    UI.settingsReady = true
    UI.ready = true
end

--========================================================--
-- RESPONSIVE & LAYOUT CONTROLLER (BOTTOM RIGHT POSITIONING)
--========================================================--

function API.syncSettingsVisibility()
    if not UI.settingsReady then return end

    local mobile = API.isMobileUI()
    if mobile and State.settingsTab == 3 then
        State.settingsTab = 1
    end

    local activeTab = math.clamp(State.settingsTab or 1, 1, mobile and 2 or 3)
    State.settingsTab = activeTab

    if mobile then
        UI.tabs[3].Visible = false
        UI.tabs[1].Size = UDim2.fromOffset(160, 30)
        UI.tabs[1].Position = UDim2.fromOffset(10, 48)
        UI.tabs[2].Size = UDim2.fromOffset(160, 30)
        UI.tabs[2].Position = UDim2.fromOffset(180, 48)
    else
        UI.tabs[3].Visible = true
        UI.tabs[1].Size = UDim2.fromOffset(104, 30)
        UI.tabs[1].Position = UDim2.fromOffset(10, 48)
        UI.tabs[2].Size = UDim2.fromOffset(104, 30)
        UI.tabs[2].Position = UDim2.fromOffset(120, 48)
        UI.tabs[3].Size = UDim2.fromOffset(104, 30)
        UI.tabs[3].Position = UDim2.fromOffset(230, 48)
    end

    local generalVisible = (activeTab == 1)

    if mobile then
        UI.general.keyLabel.Position = UDim2.fromOffset(10, 40)
        UI.general.key.Position = UDim2.fromOffset(145, 36)
        UI.general.anchorLabel.Position = UDim2.fromOffset(10, 80)
        UI.general.anchor.Position = UDim2.fromOffset(145, 76)
        UI.general.autoStealLabel.Position = UDim2.fromOffset(10, 120)
        UI.general.autoSteal.Position = UDim2.fromOffset(145, 116)
        UI.general.tpLabel.Position = UDim2.fromOffset(10, 160)
        UI.general.tp.Position = UDim2.fromOffset(145, 156)
        UI.general.autoGoalLabel.Position = UDim2.fromOffset(10, 200)
        UI.general.autoGoal.Position = UDim2.fromOffset(145, 196)
        UI.general.goalTargetLabel.Position = UDim2.fromOffset(10, 240)
        UI.general.goalTarget.Position = UDim2.fromOffset(145, 236)
    end

    UI.general.title.Visible = generalVisible
    UI.general.keyLabel.Visible = generalVisible
    UI.general.key.Visible = generalVisible
    UI.general.anchorLabel.Visible = generalVisible
    UI.general.anchor.Visible = generalVisible
    UI.general.autoStealLabel.Visible = generalVisible
    UI.general.autoSteal.Visible = generalVisible
    UI.general.tpLabel.Visible = generalVisible
    UI.general.tp.Visible = generalVisible
    UI.general.autoGoalLabel.Visible = generalVisible
    UI.general.autoGoal.Visible = generalVisible
    UI.general.goalTargetLabel.Visible = generalVisible
    UI.general.goalTarget.Visible = generalVisible
    UI.general.saeHighlightLabel.Visible = generalVisible and not mobile
    UI.general.saeHighlight.Visible = generalVisible and not mobile
    UI.general.hint.Visible = generalVisible and not mobile

    local mode1Visible = (activeTab == 2)
    UI.m1.speedLabel.Visible = mode1Visible
    UI.m1.speed.Visible = mode1Visible
    UI.m1.advanceLabel.Visible = mode1Visible and not mobile
    UI.m1.advance.Visible = mode1Visible and not mobile
    UI.m1.hint.Visible = mode1Visible and not mobile

    local mode2Visible = (activeTab == 3) and not mobile
    for _, obj in pairs(UI.m2) do
        if typeof(obj) == "Instance" and obj:IsA("GuiObject") then
            obj.Visible = mode2Visible
        end
    end
end

function API.applyResponsiveUI()
    camera = workspace.CurrentCamera
    if not camera then return end
    local vp = camera.ViewportSize
    local mobile = API.isMobileUI()

    if mobile then
        UI.main.Size = UDim2.fromOffset(350, 468)
        UI.main.Position = UDim2.fromOffset(
            math.max(5, (vp.X - 350) / 2),
            math.max(15, (vp.Y - 468) / 2)
        )

        UI.statusPanel.Size = UDim2.fromOffset(245, 125)
        UI.statusPanel.Position = UDim2.fromOffset(
            math.max(10, (vp.X - 245) / 2),
            math.max(60, (vp.Y - 125) / 2)
        )
        UI.statusPanel.Visible = false

        local settingsWidth = math.min(340, math.max(300, vp.X - 20))
        local settingsHeight = math.min(390, math.max(330, vp.Y - 80))
        UI.settingsFrame.Size = UDim2.fromOffset(settingsWidth, settingsHeight)
        UI.settingsFrame.Position = UDim2.fromOffset(
            math.max(10, (vp.X - settingsWidth) / 2),
            math.max(50, (vp.Y - settingsHeight) / 2)
        )

        local manualWidth = math.min(340, math.max(300, vp.X - 20))
        local manualHeight = math.min(430, math.max(320, vp.Y - 90))
        UI.manualFrame.Size = UDim2.fromOffset(manualWidth, manualHeight)
        UI.manualFrame.Position = UDim2.fromOffset(
            math.max(10, (vp.X - manualWidth) / 2),
            math.max(40, (vp.Y - manualHeight) / 2)
        )
        UI.manualClose.Position = UDim2.new(1, -38, 0, 8)

        UI.settingsZoomOut.Position = UDim2.fromOffset(settingsWidth - 80, 8)
        UI.settingsZoomIn.Position = UDim2.fromOffset(settingsWidth - 52, 8)
        UI.closeSettings.Position = UDim2.fromOffset(settingsWidth - 30, 8)
        UI.settingsTitle.Size = UDim2.fromOffset(math.max(180, settingsWidth - 95), 32)

        if State.mode ~= 1 then
            State.mode = 1
            State.enabled = false
            API.unlockPlayer()
            API.restoreCamera()
        end
        State.sae = false
        State.ronaldo = false
        State.advance = false
    end

    UI.actionF.Visible = mobile
    UI.specialToggle.Visible = false
    UI.sae.Visible = not mobile

    -- ĐẶT CÁC NÚT VÀO GÓC PHẢI DƯỚI CÙNG (BOTTOM RIGHT CORNER)
    if not State.__uiStablePositions.restore then
        UI.restore.Position = UDim2.fromOffset(math.max(10, vp.X - 60), math.max(10, vp.Y - 65))
    end

    if not State.__uiStablePositions.actionF then
        UI.actionF.Position = UDim2.fromOffset(math.max(10, vp.X - 100), math.max(10, vp.Y - 118))
    end

    if not State.__uiStablePositions.specialToggle then
        UI.specialToggle.Position = UDim2.fromOffset(math.max(10, vp.X - 124), math.max(10, vp.Y - 168))
    end

    if UI.settingsReady then
        API.syncSettingsVisibility()
    end

    if UI.manualRefresh then
        task.defer(UI.manualRefresh)
    end
end

function API.updateSettings()
    if not UI.settingsReady then return end

    UI.general.key.Text = State.controlKey and State.controlKey.Name or "UNKNOWN"
    UI.general.anchor.Text = State.anchor and "ON" or "OFF"
    UI.general.autoSteal.Text = State.autoStealOffOnGet and "ON" or "OFF"
    UI.general.tp.Text = tostring(State.tpDuration)
    UI.general.autoGoal.Text = State.autoGoal and "ON" or "OFF"
    UI.general.goalTarget.Text = State.autoGoalTarget == "ScoreHitbox" and "SCOREHITBOX" or "AUTOGOAL"
    UI.general.saeHighlight.Text = State.saeHighlightEnabled and "ON" or "OFF"

    UI.m1.speed.Text = tostring(Mode[1].speed)
    UI.m1.advance.Text = State.advance and "ON" or "OFF"
    UI.m2.speed.Text = tostring(Mode[2].speed)
    UI.m2.advance.Text = State.ronaldo and "ON" or "OFF"

    for i = 1, 3 do
        local active = (i == State.settingsTab)
        UI.tabs[i].BackgroundColor3 = active and Color3.fromRGB(55, 75, 95) or Color3.fromRGB(40, 40, 47)
    end

    API.syncSettingsVisibility()
end

function API.updateUI()
    if not UI.ready then return end
    UI.control.Text = "CONTROL KEY: " .. (State.controlKey and State.controlKey.Name or "UNKNOWN")
    UI.mode.Text = State.mode == 1 and "MODE: 1 [CAMERA]" or "MODE: 2 [RONALDO]"
    UI.anchor.Text = "ANCHOR: " .. (State.anchor and "ON" or "OFF")
    UI.steal.Text = "STEAL BALL: " .. (State.steal and "ON" or "OFF")
    UI.sae.Text = "SAE PASS: " .. (State.sae and "ON" or "OFF")
    UI.statusToggle.Text = UI.statusPanel.Visible and "BALL STATUS: ON" or "BALL STATUS: OFF"
    UI.status.Text = State.enabled and "Status: ACTIVE" or (State.autoGoal and "Status: AUTO GOAL" or "Status: READY")
end

function API.scaleUI(value)
    value = math.clamp(
        math.floor((tonumber(value) or State.uiScale or 1) * 100 + 0.5) / 100,
        CFG.ZOOM_MIN,
        CFG.ZOOM_MAX
    )

    State.uiScale = value
    saveConfig()

    if UI.mainScale then UI.mainScale.Scale = value end
    if UI.settingsScale then UI.settingsScale.Scale = value end
    if UI.statusScale then UI.statusScale.Scale = value end

    task.defer(function()
        API.clampUI(UI.main)
        API.clampUI(UI.settingsFrame)
        API.clampUI(UI.statusPanel)
        API.clampUI(UI.manualFrame)
        API.clampUI(UI.restore)
        API.clampUI(UI.actionF)
    end)
end

--========================================================--
-- BINDINGS & DRAG IMPLEMENTATION
--========================================================--

API.makeDraggable(UI.main, UI.title)
API.makeDraggable(UI.settingsFrame, UI.settingsTitle)
API.makeDraggable(UI.statusPanel, UI.statusTitle)
API.makeDraggable(UI.actionF, UI.actionF)
API.makeDraggable(UI.restore, UI.restore)

API.bind(UI.zoomOut.MouseButton1Click, function()
    API.scaleUI(State.uiScale - CFG.ZOOM_STEP)
end)

API.bind(UI.zoomIn.MouseButton1Click, function()
    API.scaleUI(State.uiScale + CFG.ZOOM_STEP)
end)

API.bind(UI.settingsZoomOut.MouseButton1Click, function()
    API.scaleUI(State.uiScale - CFG.ZOOM_STEP)
end)

API.bind(UI.settingsZoomIn.MouseButton1Click, function()
    API.scaleUI(State.uiScale + CFG.ZOOM_STEP)
end)

API.bind(UI.force.MouseButton1Click, function()
    API.forceUnanchor()
    API.updateUI()
end)

API.bind(UI.minimize.MouseButton1Click, function()
    State.minimized = true
    UI.main.Visible = false
    UI.settingsFrame.Visible = false
    UI.manualFrame.Visible = false
    UI.statusPanel.Visible = false
    UI.restore.Visible = true
end)

API.bind(UI.restore.MouseButton1Click, function()
    State.minimized = false
    UI.main.Visible = true
    UI.restore.Visible = true
    UI.manualFrame.Visible = false
end)

API.bind(UI.statusToggle.MouseButton1Click, function()
    UI.statusPanel.Visible = not UI.statusPanel.Visible

    if API.isMobileUI() then
        UI.main.Visible = not UI.statusPanel.Visible and not State.minimized
    end

    API.updateUI()
end)

API.bind(UI.statusClose.MouseButton1Click, function()
    UI.statusPanel.Visible = false
    if API.isMobileUI() and not State.minimized then
        UI.main.Visible = true
    end
    API.updateUI()
end)

API.bind(UI.statusMin.MouseButton1Click, function()
    UI.statusPanel.Visible = false
    if API.isMobileUI() and not State.minimized then
        UI.main.Visible = true
    end
    API.updateUI()
end)

API.bind(UI.settings.MouseButton1Click, function()
    State.settingsOpen = not State.settingsOpen
    UI.settingsFrame.Visible = State.settingsOpen and not State.minimized
    UI.manualFrame.Visible = false
    if API.isMobileUI() then
        UI.main.Visible = not State.settingsOpen and not State.minimized
    end
    API.updateSettings()
end)

API.bind(UI.closeSettings.MouseButton1Click, function()
    State.settingsOpen = false
    UI.settingsFrame.Visible = false
    if API.isMobileUI() and not State.minimized then
        UI.main.Visible = true
    end
end)

API.bind(UI.manual.MouseButton1Click, function()
    UI.manualFrame.Visible = true
    State.settingsOpen = false
    UI.settingsFrame.Visible = false

    if API.isMobileUI() then
        UI.main.Visible = false
    end

    task.defer(function()
        if UI.manualRefresh then
            UI.manualRefresh()
        end
    end)
end)

API.bind(UI.manualClose.MouseButton1Click, function()
    UI.manualFrame.Visible = false
    if API.isMobileUI() and not State.minimized then
        UI.main.Visible = true
    end
end)


for i = 1, 3 do
    local index = i
    API.bind(UI.tabs[index].MouseButton1Click, function()
        State.settingsTab = index
        API.updateSettings()
    end)
end

API.bind(UI.anchor.MouseButton1Click, function()
    State.anchor = not State.anchor
    saveConfig()
    State.forceUnanchor = false
    API.unlockPlayer()
    API.lockPlayer()
    API.updateUI()
end)

API.bind(UI.general.anchor.MouseButton1Click, function()
    State.anchor = not State.anchor
    saveConfig()
    State.forceUnanchor = false
    API.unlockPlayer()
    API.lockPlayer()
    API.updateSettings()
end)

API.bind(UI.general.autoSteal.MouseButton1Click, function()
    State.autoStealOffOnGet = not State.autoStealOffOnGet

    if State.autoStealOffOnGet and State.steal and API.localHasBall() then
        State.steal = false
        API.resetSpecial()
    end

    saveConfig()
    API.updateUI()
    API.updateSettings()
end)

API.bind(UI.general.tp.FocusLost, function()
    local n = tonumber(UI.general.tp.Text)
    if n then
        State.tpDuration = math.clamp(n, 0.1, 60)
    end

    UI.general.tp.Text = tostring(State.tpDuration)
    saveConfig()
    API.updateSettings()
end)

API.bind(UI.general.goalTarget.MouseButton1Click, function()
    State.autoGoalTarget = State.autoGoalTarget == "AutoGoal" and "ScoreHitbox" or "AutoGoal"
    saveConfig()
    API.updateSettings()
end)


API.bind(UI.steal.MouseButton1Click, function()
    State.steal = not State.steal

    if State.steal and State.autoStealOffOnGet and API.localHasBall() then
        State.steal = false
        API.resetSpecial()
    end

    API.updateUI()
end)

API.bind(UI.general.autoGoal.MouseButton1Click, function()
    State.autoGoal = not State.autoGoal
    State.autoGoalToken += 1
    State.autoGoalBusy = false
    API.resetSpecial()

    if State.autoGoal then
        State.steal = false
    end

    API.updateUI()
    API.updateSettings()
end)

API.bind(UI.tp.MouseButton1Click, function() task.spawn(API.startTP) end)
API.bind(UI.tpTime.FocusLost, function()
    local n = tonumber(UI.tpTime.Text)
    if n then
        State.tpDuration = math.clamp(n, 0.1, 60)
    end

    UI.tpTime.Text = tostring(State.tpDuration)
    saveConfig()
    API.updateSettings()
end)

API.bind(UI.tpGoal.MouseButton1Click, function() task.spawn(API.tpGoal) end)

-- MORE MODS: load the external More Mods script
API.bind(UI.moreMod.MouseButton1Click, function()
    local MORE_MODS_URL = "https://raw.githubusercontent.com/thatonevietnamese/BLUE-LOCK-SKIBIDI-YESSIR/refs/heads/main/(LOADER)standard.lua"

    task.spawn(function()
        local ok, err = pcall(function()
            local source = game:HttpGet(MORE_MODS_URL)
            local fn = loadstring(source)
            if not fn then
                error("loadstring returned nil")
            end
            fn()
        end)

        if ok then
            API.notify("MORE MODS loaded successfully.", 2)
        else
            warn("[MORE MODS] Failed to load:", err)
            API.notify("MORE MODS failed to load. Check console.", 3)
        end
    end)
end)

API.bind(UI.actionF.MouseButton1Click, function()
    if State.mode == 1 then
        State.enabled = not State.enabled
        if State.enabled then
            State.forceUnanchor = false
            local _, _, ball = API.getBallState()
            if ball then API.followBall(ball) end
            API.lockPlayer()
        else
            API.restoreCamera()
            API.unlockPlayer()
        end
        API.updateUI()
    end
end)

--========================================================--
-- FULL GAMEPLAY HEARTBEAT LOOP (AUTO GOAL & BALL MOVE)
--========================================================--

API.bind(RunService.Heartbeat, function()
    API.updateCharacter()
    local state, holder, ball = API.getBallState()

    if UI.ballStatus then
        UI.ballStatus.Text = (state == "HELD" and holder) and ("BALL: HELD BY " .. holder.Name) or ("BALL: " .. state)
    end

    -- AUTO GOAL CORE LOOP
    if State.autoGoal then
        local now = os.clock()
        if now - State.lastAutoGoal >= 0.10 then
            State.lastAutoGoal = now
            if API.localHasBall() then
                API.resetSpecial()
                if not State.autoGoalBusy then
                    State.autoGoalBusy = true
                    State.autoGoalToken += 1
                    local token = State.autoGoalToken

                    task.spawn(function()
                        while State.autoGoal and token == State.autoGoalToken and API.updateCharacter() and Char.root do
                            if not API.localHasBall() then
                                API.stealStep()
                                task.wait(0.08)
                                continue
                            end

                            local goal = API.opponentGoal()
                            local goalPos = API.goalPosition(goal)
                            if not goal or not goalPos then
                                task.wait(0.08)
                                continue
                            end

                            API.rebuildBall(true)
                            local ballState, ballHolder, shotBall = API.getBallState()
                            if ballState ~= "HELD" or ballHolder ~= LP or not shotBall then
                                task.wait(0.04)
                                continue
                            end

                            local direction = goalPos - shotBall.Position
                            if direction.Magnitude <= 0.001 then
                                direction = goalPos - Char.root.Position
                            end

                            if direction.Magnitude <= 0.001 then
                                task.wait(0.05)
                                continue
                            end

                            direction = direction.Unit

                            if API.fireShoot(direction, CFG.AUTO_GOAL_SHOOT_FORCE, false) then
                                local released = API.waitForReleasedBall(shotBall, 0.8)

                                if released and released.Parent then
                                    while State.autoGoal
                                        and token == State.autoGoalToken
                                        and released.Parent do

                                        local currentGoal = API.opponentGoal()
                                        local currentGoalPos = API.goalPosition(currentGoal)
                                        if not currentGoal or not currentGoalPos then
                                            break
                                        end

                                        pcall(function()
                                            released.CFrame = currentGoal.CFrame
                                        end)

                                        API.fireShoot(
                                            direction,
                                            CFG.AUTO_GOAL_SHOOT_FORCE,
                                            false
                                        )

                                        pcall(function()
                                            released.AssemblyLinearVelocity =
                                                direction * CFG.AUTO_GOAL_SHOOT_FORCE
                                        end)

                                        task.wait(CFG.AUTO_GOAL_SHOOT_INTERVAL)
                                    end
                                end
                            end

                            task.wait(0.05)
                        end
                        if token == State.autoGoalToken then State.autoGoalBusy = false end
                    end)
                end
            else
                API.stealStep()
            end
        end
    elseif State.steal then
        if State.autoStealOffOnGet and API.localHasBall() then
            State.steal = false
            API.resetSpecial()
            API.updateUI()
            API.updateSettings()
        else
            API.stealStep()
        end
    end

    -- MODE 1 BALL CONTROL MOVEMENT
    if State.enabled and State.mode == 1 and ball then
        ball.AssemblyLinearVelocity = API.cameraDirection() * math.clamp(Mode[1].speed, CFG.MIN_SPEED, CFG.MAX_SPEED)
        camera = workspace.CurrentCamera
        if camera then
            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = ball
        end
    end

    if State.mode == 1 then API.lockPlayer() end
end)

function API.stopController()
    API.unlockPlayer()
    API.restoreCamera()
    for i = 1, #Connections do API.disconnect(Connections[i]) end
    table.clear(Connections)
    if PlayerGui:FindFirstChild("BallController") then PlayerGui.BallController:Destroy() end
end

getgenv().__BALL_CONTROLLER_V4_STOP = API.stopController

API.applyResponsiveUI()
API.updateUI()
API.updateSettings()
task.defer(function()
    if UI.manualRefresh then
        UI.manualRefresh()
    end
end)

print("[Ball Controller V4.5 Complete] Ready to run!")
