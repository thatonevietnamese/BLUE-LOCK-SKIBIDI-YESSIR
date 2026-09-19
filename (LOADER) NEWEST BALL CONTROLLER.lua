--========================================================--
-- BALL CONTROLLER V4.5 - PC ONLY
--========================================================--

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")

local CFG = {
    BALL_NAME = "Ball",

    MIN_SPEED = 1,
    MAX_SPEED = 1000,

    CONTROL_KEY = Enum.KeyCode.F,

    STEAL_DISTANCE = 3,
    TP_TIME = 1.5,

    SHOOT_FORCE = 100,
    SHOOT_FORCE_MIN = 100,
    SHOOT_FORCE_MAX = 1000,

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
    [1] = {
        speed = 60,
    },

    [2] = {
        speed = 140,
    },
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

    sae = false,
    saeActive = false,
    saeTarget = nil,
    saeBall = nil,
    saeStage = "IDLE",
    saeHighlight = nil,
    saeHighlightEnabled = true,
    saeTempActive = false,
    saeWasHoldingBall = false,

    ronaldo = false,
    ronaldoTarget = nil,
    ronaldoBall = nil,
    ronaldoActive = false,
    ronaldoTouch = nil,
    ronaldoStart = 0,
    ronaldoDirection = nil,

    advance = false,

    keys = {
        W = false,
        A = false,
        S = false,
        D = false,
        Q = false,
        E = false,
    },

    changingKey = false,
    minimized = false,
    settingsOpen = false,

    uiScale = 1,
    responsiveScale = 1,

    shootMaxVelocity = CFG.SHOOT_FORCE,
    shootVelocityLimitEnabled = false,

    autoStealOffOnGet = true,

    leftMouseHeld = false,
    rightMouseHeld = false,

    specialSelecting = false,

    lastSteal = 0,

    special = {
        active = false,
        target = nil,
        step = 1,
        nextAt = 0,
        character = "",
    },
}

local Tracker = {
    state = "UNKNOWN",
    holder = nil,
    ball = nil,
    last = 0,
    queued = false,
}

local Char = {
    model = nil,
    humanoid = nil,
    root = nil,

    locked = false,

    walk = nil,
    jump = nil,
    rotate = nil,
}

local CameraState = {
    type = nil,
    subject = nil,
}

local UI: any = {
    ready = false,
}

State.__uiStablePositions = {}
State.__dragConsumed = {}

local Connections = {}
local CharConnections = {}
local PlayerConnections = {}

local API: any = {}

local camera = workspace.CurrentCamera

--========================================================--
-- ENV
--========================================================--

local function getEnv()
    local env

    pcall(function()
        env = getgenv()
    end)

    return env or _G
end

local Env = getEnv()

--========================================================--
-- CONFIG
--========================================================--

local CONFIG_FILE = "BallController_V4_5_Settings.json"

local Persist: any = {
    key = "__BALL_CONTROLLER_V4_5_CONFIG",
    data = {},
}

local function safeDecodeJson(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end

    local ok, result = pcall(function()
        if HttpService and HttpService.JSONDecode then
            return HttpService:JSONDecode(raw)
        end
    end)

    return ok
        and type(result) == "table"
        and result
        or nil
end

local function loadPersistedConfig()
    local data

    pcall(function()
        if type(isfile) == "function"
            and isfile(CONFIG_FILE)
            and type(readfile) == "function"
        then
            data = safeDecodeJson(readfile(CONFIG_FILE))
        end
    end)

    if not data and type(Env[Persist.key]) == "table" then
        data = Env[Persist.key]
    end

    Persist.data = type(data) == "table" and data or {}
end

local function savePersistedConfig()
    local data = Persist.data or {}

    Env[Persist.key] = data

    pcall(function()
        if type(writefile) == "function"
            and HttpService
            and HttpService.JSONEncode
        then
            writefile(
                CONFIG_FILE,
                HttpService:JSONEncode(data)
            )
        end
    end)
end

loadPersistedConfig()

do
    local c = Persist.data or {}

    if type(c.uiScale) == "number" then
        State.uiScale = math.clamp(
            c.uiScale,
            CFG.ZOOM_MIN,
            CFG.ZOOM_MAX
        )
    end

    if type(c.anchor) == "boolean" then
        State.anchor = c.anchor
    end

    if type(c.autoStealOffOnGet) == "boolean" then
        State.autoStealOffOnGet =
            c.autoStealOffOnGet
    end

    if type(c.saeHighlightEnabled) == "boolean" then
        State.saeHighlightEnabled =
            c.saeHighlightEnabled
    end

    if type(c.tpDuration) == "number" then
        State.tpDuration = math.clamp(
            c.tpDuration,
            0.1,
            60
        )
    end

    if type(c.shootMaxVelocity) == "number" then
        State.shootMaxVelocity = math.clamp(
            c.shootMaxVelocity,
            CFG.SHOOT_FORCE_MIN,
            CFG.SHOOT_FORCE_MAX
        )
    end

    if type(c.shootVelocityLimitEnabled) == "boolean" then
        State.shootVelocityLimitEnabled =
            c.shootVelocityLimitEnabled
    end

    if type(c.controlKey) == "string"
        and Enum.KeyCode[c.controlKey]
    then
        State.controlKey =
            Enum.KeyCode[c.controlKey]
    end

    if type(c.mode1Speed) == "number" then
        Mode[1].speed = math.clamp(
            c.mode1Speed,
            CFG.MIN_SPEED,
            CFG.MAX_SPEED
        )
    end

    if type(c.mode2Speed) == "number" then
        Mode[2].speed = math.clamp(
            c.mode2Speed,
            CFG.MIN_SPEED,
            CFG.MAX_SPEED
        )
    end

    if type(c.uiPositions) == "table" then
        for name, pos in pairs(c.uiPositions) do
            if type(pos) == "table"
                and type(pos.x) == "number"
                and type(pos.y) == "number"
            then
                State.__uiStablePositions[name] =
                    Vector2.new(
                        pos.x,
                        pos.y
                    )
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

    Persist.data.shootMaxVelocity =
        math.clamp(
            tonumber(State.shootMaxVelocity)
                or CFG.SHOOT_FORCE_MIN,
            CFG.SHOOT_FORCE_MIN,
            CFG.SHOOT_FORCE_MAX
        )

    Persist.data.shootVelocityLimitEnabled =
        State.shootVelocityLimitEnabled

    Persist.data.controlKey =
        State.controlKey
        and State.controlKey.Name
        or nil

    Persist.data.mode1Speed =
        Mode[1].speed

    Persist.data.mode2Speed =
        Mode[2].speed

    Persist.data.uiPositions =
        Persist.data.uiPositions
        or {}

    savePersistedConfig()
end

local oldStop = Env.__BALL_CONTROLLER_V4_STOP

if oldStop then
    pcall(oldStop)
end

function API.disconnect(conn)
    if conn then
        pcall(function()
            conn:Disconnect()
        end)
    end
end

function API.disconnectList(list)
    if not list then
        return
    end

    for i = 1, #list do
        API.disconnect(list[i])
    end

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
-- CHARACTER
--========================================================--

do
    function API.updateCharacter()
        Char.model = LP.Character

        if not Char.model then
            Char.humanoid = nil
            Char.root = nil
            return false
        end

        Char.humanoid =
            Char.model:FindFirstChildOfClass(
                "Humanoid"
            )

        Char.root =
            Char.model:FindFirstChild(
                "HumanoidRootPart"
            )

        return
            Char.humanoid ~= nil
            and Char.root ~= nil
    end

    function API.lockPlayer()
        if not API.updateCharacter() then
            return
        end

        if not State.enabled
            or not State.anchor
            or State.mode ~= 1
            or State.forceUnanchor
        then
            Char.root.Anchored = false
            API.unlockPlayer()
            return
        end

        if Char.walk == nil then
            Char.walk =
                Char.humanoid.WalkSpeed

            Char.jump =
                Char.humanoid.JumpPower

            Char.rotate =
                Char.humanoid.AutoRotate
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
            Char.walk = nil
            Char.jump = nil
            Char.rotate = nil
            return
        end

        if Char.locked then
            if Char.walk ~= nil then
                Char.humanoid.WalkSpeed =
                    Char.walk
            end

            if Char.jump ~= nil then
                Char.humanoid.JumpPower =
                    Char.jump
            end

            if Char.rotate ~= nil then
                Char.humanoid.AutoRotate =
                    Char.rotate
            end
        end

        if Char.root then
            Char.root.Anchored = false
        end

        Char.locked = false
        Char.walk = nil
        Char.jump = nil
        Char.rotate = nil
    end

    function API.forceUnanchor()
        State.forceUnanchor = true

        API.unlockPlayer()

        API.notify(
            "ANCHOR",
            "Force Unanchor executed",
            1.4
        )
    end
end

--========================================================--
-- NOTIFY
--========================================================--

function API.notify(titleText, bodyText, duration)
    if not UI.notificationHolder
        or not UI.notificationHolder.Parent
    then
        return
    end

    duration = duration or 2.2

    local card = Instance.new("Frame")

    card.Size =
        UDim2.fromOffset(
            280,
            58
        )

    card.AnchorPoint =
        Vector2.new(0.5, 0)

    card.Position =
        UDim2.new(
            0.5,
            0,
            0,
            -65
        )

    card.BackgroundColor3 =
        Color3.fromRGB(
            27,
            27,
            34
        )

    card.BorderSizePixel = 0
    card.Parent =
        UI.notificationHolder

    local c =
        Instance.new("UICorner")

    c.CornerRadius =
        UDim.new(0, 9)

    c.Parent = card

    local s =
        Instance.new("UIStroke")

    s.Color =
        Color3.fromRGB(
            65,
            65,
            80
        )

    s.Transparency = 0.15
    s.Parent = card

    local title =
        Instance.new("TextLabel")

    title.Size =
        UDim2.new(
            1,
            -18,
            0,
            22
        )

    title.Position =
        UDim2.fromOffset(
            9,
            5
        )

    title.BackgroundTransparency = 1
    title.Text = tostring(titleText)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13

    title.TextColor3 =
        Color3.new(
            1,
            1,
            1
        )

    title.TextXAlignment =
        Enum.TextXAlignment.Left

    title.Parent = card

    local body =
        Instance.new("TextLabel")

    body.Size =
        UDim2.new(
            1,
            -18,
            0,
            25
        )

    body.Position =
        UDim2.fromOffset(
            9,
            27
        )

    body.BackgroundTransparency = 1
    body.Text =
        tostring(bodyText)

    body.Font = Enum.Font.Gotham
    body.TextSize = 11

    body.TextColor3 =
        Color3.fromRGB(
            175,
            175,
            185
        )

    body.TextXAlignment =
        Enum.TextXAlignment.Left

    body.Parent = card

    TweenService:Create(
        card,
        TweenInfo.new(
            0.18,
            Enum.EasingStyle.Quad
        ),
        {
            Position =
                UDim2.new(
                    0.5,
                    0,
                    0,
                    8
                ),
        }
    ):Play()

    task.delay(
        duration,
        function()
            if not card.Parent then
                return
            end

            TweenService:Create(
                card,
                TweenInfo.new(
                    0.18,
                    Enum.EasingStyle.Quad
                ),
                {
                    Position =
                        UDim2.new(
                            0.5,
                            0,
                            0,
                            -65
                        ),
                }
            ):Play()

            task.delay(
                0.22,
                function()
                    if card.Parent then
                        card:Destroy()
                    end
                end
            )
        end
    )
end

--========================================================--
-- BALL TRACKER
--========================================================--

do
    local function ballInCharacter(char)
        if not char then
            return nil
        end

        local ball =
            char:FindFirstChild(
                CFG.BALL_NAME,
                true
            )

        return
            ball
            and ball:IsA("BasePart")
            and ball
            or nil
    end

    local function freeBall()
        local direct =
            workspace:FindFirstChild(
                CFG.BALL_NAME
            )

        if direct
            and direct:IsA("BasePart")
        then
            return direct
        end

        for _, obj in ipairs(
            workspace:GetDescendants()
        ) do
            if obj:IsA("BasePart")
                and string.lower(obj.Name)
                    == string.lower(CFG.BALL_NAME)
            then
                if not Char.model
                    or not obj:IsDescendantOf(
                        Char.model
                    )
                then
                    return obj
                end
            end
        end

        return nil
    end

    function API.rebuildBall(force)
        local now = os.clock()

        if not force
            and now - Tracker.last
                < CFG.CACHE_INTERVAL
        then
            return
                Tracker.state,
                Tracker.holder,
                Tracker.ball
        end

        Tracker.last = now
        Tracker.queued = false

        Tracker.state = "UNKNOWN"
        Tracker.holder = nil
        Tracker.ball = nil

        for _, plr in ipairs(
            Players:GetPlayers()
        ) do
            if plr.Character then
                local ball =
                    ballInCharacter(
                        plr.Character
                    )

                if ball then
                    Tracker.state =
                        "HELD"

                    Tracker.holder =
                        plr

                    Tracker.ball =
                        ball

                    return
                        "HELD",
                        plr,
                        ball
                end
            end
        end

        local ball =
            freeBall()

        if ball then
            Tracker.state =
                "FREE"

            Tracker.ball =
                ball

            return
                "FREE",
                nil,
                ball
        end

        Tracker.state =
            "MISSING"

        return
            "MISSING",
            nil,
            nil
    end

    function API.queueBallRebuild()
        if Tracker.queued then
            return
        end

        Tracker.queued = true

        task.defer(function()
            if Tracker.queued then
                API.rebuildBall(false)
            end
        end)
    end

    function API.getBallState()
        local state =
            Tracker.state

        local holder =
            Tracker.holder

        local ball =
            Tracker.ball

        if state == "HELD" then
            if not holder
                or not holder.Parent
                or not holder.Character
            then
                return
                    API.rebuildBall(false)
            end

            if not ball
                or not ball.Parent
                or not ball:IsDescendantOf(
                    holder.Character
                )
            then
                return
                    API.rebuildBall(false)
            end

            return
                state,
                holder,
                ball
        end

        if state == "FREE" then
            if ball
                and ball.Parent
            then
                return
                    state,
                    nil,
                    ball
            end

            return
                API.rebuildBall(false)
        end

        return
            API.rebuildBall(false)
    end

    function API.localHasBall()
        local state,
            holder =
            API.getBallState()

        return
            state == "HELD"
            and holder == LP
    end

    function API.playerRoot(plr)
        if not plr
            or not plr.Character
        then
            return nil
        end

        return
            plr.Character:FindFirstChild(
                "HumanoidRootPart"
            )
    end

    function API.sameTeam(plr)
        return
            plr
            and LP.Team
            and plr.Team == LP.Team
    end

    function API.attachCharacter(
        plr,
        char
    )
        API.disconnectList(
            CharConnections[plr]
        )

        local list = {}

        API.bindLocal(
            list,
            char.DescendantAdded,
            function(obj)
                if obj.Name
                        == CFG.BALL_NAME
                    and obj:IsA("BasePart")
                then
                    API.queueBallRebuild()
                end
            end
        )

        API.bindLocal(
            list,
            char.DescendantRemoving,
            function(obj)
                if obj == Tracker.ball then
                    API.queueBallRebuild()
                end
            end
        )

        API.bindLocal(
            list,
            char.AncestryChanged,
            function(_, parent)
                if parent == nil then
                    API.queueBallRebuild()
                end
            end
        )

        CharConnections[plr] =
            list
    end

    function API.attachPlayer(plr)
        API.disconnectList(
            PlayerConnections[plr]
        )

        local list = {}

        if plr.Character then
            API.attachCharacter(
                plr,
                plr.Character
            )
        end

        API.bindLocal(
            list,
            plr.CharacterAdded,
            function(char)
                API.attachCharacter(
                    plr,
                    char
                )

                API.queueBallRebuild()
            end
        )

        API.bindLocal(
            list,
            plr.CharacterRemoving,
            function()
                API.queueBallRebuild()
            end
        )

        PlayerConnections[plr] =
            list
    end
end

--========================================================--
-- REMOTE
--========================================================--

do
    local remote
    local remoteReady = false
    local lastResolve = 0

    function API.resolveShootRemote(force)
        local now =
            os.clock()

        if not force
            and now - lastResolve
                < 0.25
        then
            return remote
        end

        lastResolve = now

        local events =
            ReplicatedStorage:FindFirstChild(
                "Events"
            )

        remote =
            events
            and events:FindFirstChild(
                "ShootBall"
            )

        remoteReady =
            remote
            and remote:IsA("RemoteEvent")
            or false

        return remote
    end

    function API.fireShoot(
        direction,
        force,
        third
    )
        if not remoteReady
            or not remote
        then
            API.resolveShootRemote(true)
        end

        if not remoteReady
            or not remote
        then
            API.notify(
                "SHOOT REMOTE",
                "Events.ShootBall was not found",
                1.5
            )

            return false
        end

        if typeof(direction)
                ~= "Vector3"
            or direction.Magnitude
                < 0.001
        then
            return false
        end

        local gameForce =
            math.clamp(
                tonumber(force)
                    or CFG.SHOOT_FORCE,
                CFG.MIN_SPEED,
                CFG.MAX_SPEED
            )

        local shootForce =
            gameForce

        if State.shootVelocityLimitEnabled then
            local maxSetting =
                math.clamp(
                    tonumber(
                        State.shootMaxVelocity
                    )
                    or CFG.SHOOT_FORCE_MIN,
                    CFG.SHOOT_FORCE_MIN,
                    CFG.SHOOT_FORCE_MAX
                )

            local bonus =
                math.max(
                    0,
                    maxSetting
                        - CFG.SHOOT_FORCE_MIN
                )

            shootForce =
                math.clamp(
                    gameForce + bonus,
                    CFG.MIN_SPEED,
                    CFG.MAX_SPEED
                )
        end

        local thirdValue =
            third ~= nil
            and third
            or false

        return pcall(function()
            remote:FireServer(
                direction.Unit,
                shootForce,
                thirdValue
            )
        end)
    end

    API.resolveShootRemote(true)
end

--========================================================--
-- CAMERA
--========================================================--

do
    function API.saveCamera(subject)
        camera =
            workspace.CurrentCamera

        if not camera then
            return
        end

        if CameraState.type == nil then
            CameraState.type =
                camera.CameraType
        end

        if CameraState.subject == nil
            and camera.CameraSubject
                ~= subject
        then
            CameraState.subject =
                camera.CameraSubject
        end
    end

    function API.followBall(ball)
        if not ball then
            return
        end

        camera =
            workspace.CurrentCamera

        if not camera then
            return
        end

        API.saveCamera(ball)

        camera.CameraType =
            Enum.CameraType.Custom

        camera.CameraSubject =
            ball
    end

    function API.restoreCamera()
        camera =
            workspace.CurrentCamera

        if not camera then
            return
        end

        API.updateCharacter()

        camera.CameraType =
            CameraState.type
            or Enum.CameraType.Custom

        if Char.humanoid
            and Char.humanoid.Parent
        then
            camera.CameraSubject =
                Char.humanoid
        elseif CameraState.subject
            and CameraState.subject.Parent
        then
            camera.CameraSubject =
                CameraState.subject
        end

        CameraState.type = nil
        CameraState.subject = nil
    end

    function API.cameraDirection()
        camera =
            workspace.CurrentCamera

        if not camera then
            return
                Vector3.new(
                    0,
                    0,
                    -1
                )
        end

        local v =
            camera.CFrame.LookVector

        return
            v.Magnitude > 0
            and v.Unit
            or Vector3.new(
                0,
                0,
                -1
            )
    end

    function API.flatDirections()
        camera =
            workspace.CurrentCamera

        if not camera then
            return
                Vector3.new(
                    0,
                    0,
                    -1
                ),
                Vector3.new(
                    1,
                    0,
                    0
                )
        end

        local f =
            Vector3.new(
                camera.CFrame.LookVector.X,
                0,
                camera.CFrame.LookVector.Z
            )

        local r =
            Vector3.new(
                camera.CFrame.RightVector.X,
                0,
                camera.CFrame.RightVector.Z
            )

        if f.Magnitude > 0 then
            f = f.Unit
        end

        if r.Magnitude > 0 then
            r = r.Unit
        end

        return
            f,
            r
    end
end

--========================================================--
-- GOAL / ROLE
--========================================================--

do
    function API.characterName()
        local values =
            LP:FindFirstChild("Values")

        local obj =
            values
            and values:FindFirstChild(
                "CharacterName"
            )

        if not obj
            or obj.Value == nil
        then
            return ""
        end

        local normalized =
            string.gsub(
                tostring(obj.Value),
                "%s+",
                ""
            )

        return string.lower(
            normalized
        )
    end

    function API.roleName()
        local role =
            LP:FindFirstChild("Role")

        if role
            and role.Value ~= nil
        then
            return string.lower(
                tostring(role.Value)
            )
        end

        local values =
            LP:FindFirstChild("Values")

        local obj =
            values
            and values:FindFirstChild("Role")

        if obj
            and obj.Value ~= nil
        then
            return string.lower(
                tostring(obj.Value)
            )
        end

        if Char.model then
            local obj2 =
                Char.model:FindFirstChild(
                    "Role"
                )

            if obj2
                and obj2.Value ~= nil
            then
                return string.lower(
                    tostring(obj2.Value)
                )
            end
        end

        return ""
    end

    function API.isGK()
        local role =
            string.gsub(
                API.roleName(),
                "%s+",
                " "
            )

        return
            CFG.GK_ROLES[role] == true
    end

    function API.isHome()
        return
            LP.Team
            and string.lower(
                LP.Team.Name
            ) == "home"
    end

    function API.goalHitbox(homeSide)
        local map =
            workspace:FindFirstChild(
                "Map"
            )

        if not map then
            return nil
        end

        local model =
            map:FindFirstChild(
                homeSide
                    and "PlayerOneGoal"
                    or "PlayerTwoGoal"
            )

        if not model then
            return nil
        end

        local score =
            model:FindFirstChild(
                "ScoreHitbox"
            )
            or model:FindFirstChild(
                "Score"
            )

        if score
            and score:IsA("BasePart")
        then
            return score
        end

        local hitbox =
            model:FindFirstChild(
                "ScoreHitbox",
                true
            )

        if hitbox
            and hitbox:IsA("BasePart")
        then
            return hitbox
        end

        return
            model:FindFirstChildWhichIsA(
                "BasePart",
                true
            )
    end

    function API.goalArea(homeSide)
        local obj =
            workspace:FindFirstChild(
                homeSide
                    and "PlayerOneGoalArea"
                    or "PlayerTwoGoalArea"
            )

        if not obj then
            return nil
        end

        if obj:IsA("BasePart") then
            return obj
        end

        if obj:IsA("Model") then
            return
                obj.PrimaryPart
                or obj:FindFirstChildWhichIsA(
                    "BasePart",
                    true
                )
        end

        return nil
    end

    function API.ownGoal()
        local home =
            API.isHome()

        return
            API.goalArea(home)
            or API.goalHitbox(home)
    end

    function API.autoGoalTarget(homeSide)
        local map =
            workspace:FindFirstChild(
                "Map"
            )

        if not map then
            return nil
        end

        local model =
            map:FindFirstChild(
                homeSide
                    and "PlayerOneGoal"
                    or "PlayerTwoGoal"
            )

        if not model then
            return nil
        end

        local target =
            model:FindFirstChild(
                "AutoGoal"
            )

        if not target then
            return nil
        end

        if target:IsA("BasePart")
            or target:IsA("Attachment")
        then
            return target
        end

        if target:IsA("Model") then
            return
                target.PrimaryPart
                or target:FindFirstChildWhichIsA(
                    "BasePart",
                    true
                )
                or target:FindFirstChildWhichIsA(
                    "Attachment",
                    true
                )
        end

        return
            target:FindFirstChildWhichIsA(
                "BasePart",
                true
            )
            or target:FindFirstChildWhichIsA(
                "Attachment",
                true
            )
    end

    function API.goalPosition(goal)
        if not goal
            or not goal.Parent
        then
            return nil
        end

        if goal:IsA("BasePart") then
            return goal.Position
        end

        if goal:IsA("Attachment") then
            return goal.WorldPosition
        end

        if goal:IsA("Model") then
            local part =
                goal.PrimaryPart
                or goal:FindFirstChildWhichIsA(
                    "BasePart",
                    true
                )

            return
                part
                and part.Position
                or nil
        end

        return nil
    end

    function API.opponentGoal()
        return
            API.autoGoalTarget(
                not API.isHome()
            )
    end

    function API.inGoal(pos, goal)
        local goalPos =
            API.goalPosition(goal)

        return
            pos
            and goalPos
            and (
                pos - goalPos
            ).Magnitude <= 18
    end
end

--========================================================--
-- ABILITIES
--========================================================--

do
    local Abilities = {
        default = {
            canSlide = true,
            canSlideTeammate = false,
        },

        barou = {
            canSlide = true,
            canSlideTeammate = true,

            special = {
                name = "BAROU 3",
                key = Enum.KeyCode.Three,
                mode = "OPPONENT",
                repeatHeld = true,
                interval = 0.14,
                offset = Vector3.new(0, 5.5, 0),
            },
        },

        shidou = {
            canSlide = true,
            canSlideTeammate = false,

            special = {
                name = "SHIDOU 3",
                key = Enum.KeyCode.Three,
                mode = "OPPONENT",
                repeatHeld = true,
                interval = 0.16,
                offset = Vector3.new(0, 5.5, 0),
            },
        },

        naoya = {
            canSlide = true,
            canSlideTeammate = false,

            special = {
                name = "NAOYA 2 -> 3",
                mode = "OPPONENT",
                interval = 0.16,
                offset = Vector3.new(0, 5.5, 0),

                steps = {
                    {
                        key = Enum.KeyCode.Two,
                        waitPossession = true,
                    },

                    {
                        key = Enum.KeyCode.Three,
                        finish = true,
                    },
                },
            },
        },

        kaiser = {
            canSlide = true,
            canSlideTeammate = false,

            special = {
                name = "KAISER 3",
                key = Enum.KeyCode.Three,
                mode = "ANY",
                allowTeammate = true,
                repeatHeld = true,
                interval = 0.16,
                offset = Vector3.new(0, 5.5, 0),
            },
        },

        gagamaru = {
            canSlide = true,
            canSlideTeammate = false,

            special = {
                name = "GAGAMARU 3",
                key = Enum.KeyCode.Three,
                mode = "OPPONENT",
                oneShot = true,
                interval = 0.18,
                offset = Vector3.new(0, 5.5, 0),
            },
        },

        ichigo = {
            canSlide = true,
            canSlideTeammate = false,

            special = {
                name = "ICHIGO 1",
                key = Enum.KeyCode.One,
                mode = "OPPONENT",
                oneShot = true,
                interval = 0.18,
                offset = Vector3.new(0, 5.5, 0),
            },
        },

        donlorenzo = {
            canSlide = true,
            canSlideTeammate = false,

            special = {
                name = "DON LORENZO 2",
                key = Enum.KeyCode.Two,
                mode = "OPPONENT",
                oneShot = true,
                interval = 0.18,
                offset = Vector3.new(0, 5.5, 0),
            },
        },

        chigiri = {
            canSlide = true,
            canSlideTeammate = false,

            special = {
                name = "CHIGIRI 1",
                key = Enum.KeyCode.One,
                mode = "OPPONENT",
                oneShot = true,
                interval = 0.16,
                offset = Vector3.new(0, 5.5, 0),
            },
        },

        chirigi = {
            canSlide = true,
            canSlideTeammate = false,

            special = {
                name = "CHIGIRI 1",
                key = Enum.KeyCode.One,
                mode = "OPPONENT",
                oneShot = true,
                interval = 0.16,
                offset = Vector3.new(0, 5.5, 0),
            },
        },
    }

    function API.ability()
        return
            Abilities[API.characterName()]
            or Abilities.default
    end

    function API.resetSpecial()
        State.special.active = false
        State.special.target = nil
        State.special.step = 1
        State.special.nextAt = 0
        State.special.character = ""
    end

    local function targetForSpecial(special)
        local state, holder =
            API.getBallState()

        if state ~= "HELD"
            or not holder
            or holder == LP
        then
            return nil
        end

        local teammate =
            API.sameTeam(holder)

        local mode =
            special.mode
            or "OPPONENT"

        if mode == "OPPONENT"
            and teammate
        then
            return nil
        end

        if mode == "TEAMMATE"
            and not teammate
        then
            return nil
        end

        if mode == "ANY"
            and teammate
            and not special.allowTeammate
        then
            return nil
        end

        local root =
            API.playerRoot(holder)

        return
            root
            and root.Parent
            and holder
            or nil
    end

    local function specialStillValid(target)
        if not target
            or not target.Parent
        then
            return false
        end

        local state, holder =
            API.getBallState()

        return
            state == "HELD"
            and holder == target
    end

    local function tpUse(
        target,
        keyCode,
        offset
    )
        local root =
            API.playerRoot(target)

        if not root
            or not root.Parent
        then
            return false
        end

        if not API.updateCharacter()
            or not Char.root
            or not Char.root.Parent
        then
            return false
        end

        offset =
            typeof(offset) == "Vector3"
            and offset
            or Vector3.new(
                0,
                5.5,
                0
            )

        Char.root.CFrame =
            CFrame.new(
                root.Position + offset,
                root.Position
            )

        return
            API.sendKey(keyCode)
    end

    function API.specialSteal()
        local ability =
            API.ability()

        local special =
            ability.special

        if not special then
            API.resetSpecial()
            return false
        end

        local charName =
            API.characterName()

        if State.special.active
            and State.special.character
                ~= charName
        then
            API.resetSpecial()
        end

        local now =
            os.clock()

        if not State.special.active then
            local target =
                targetForSpecial(
                    special
                )

            if not target then
                return false
            end

            State.special.active = true
            State.special.target = target
            State.special.step = 1
            State.special.nextAt = now
            State.special.character = charName
        end

        local target =
            State.special.target

        if not target
            or not target.Parent
        then
            API.resetSpecial()
            return false
        end

        local root =
            API.playerRoot(target)

        if not root then
            API.resetSpecial()
            return false
        end

        if special.steps then
            local step =
                special.steps[
                    State.special.step
                ]

            if not step then
                API.resetSpecial()
                return false
            end

            if step.waitPossession then
                if not API.localHasBall() then
                    if not specialStillValid(
                        target
                    ) then
                        API.resetSpecial()
                        return false
                    end

                    return true
                end

                State.special.step += 1

                step =
                    special.steps[
                        State.special.step
                    ]

                if not step then
                    API.resetSpecial()
                    return true
                end
            end

            if now <
                State.special.nextAt
            then
                return true
            end

            if not specialStillValid(
                target
            )
                and not API.localHasBall()
            then
                API.resetSpecial()
                return false
            end

            local used =
                tpUse(
                    target,
                    step.key,
                    step.offset
                        or special.offset
                )

            if not used then
                API.resetSpecial()
                return false
            end

            State.special.nextAt =
                now
                + (
                    step.interval
                    or special.interval
                    or CFG.SPECIAL_INTERVAL
                )

            if step.finish then
                API.resetSpecial()
            end

            return true
        end

        if now <
            State.special.nextAt
        then
            return true
        end

        if not special.oneShot
            and not specialStillValid(
                target
            )
        then
            API.resetSpecial()
            return false
        end

        local used =
            tpUse(
                target,
                special.key,
                special.offset
            )

        if not used then
            API.resetSpecial()
            return false
        end

        if special.oneShot then
            API.resetSpecial()
        else
            State.special.nextAt =
                now
                + (
                    special.interval
                    or CFG.SPECIAL_INTERVAL
                )
        end

        return true
    end

    function API.normalStealTarget()
        local ability =
            API.ability()

        if not ability.canSlide then
            return nil
        end

        local state =
            Tracker.state

        local holder =
            Tracker.holder

        local ball =
            Tracker.ball

        if state == "HELD"
            and holder
        then
            if holder == LP then
                return nil
            end

            if API.sameTeam(holder)
                and not ability.canSlideTeammate
            then
                return nil
            end

            return
                API.playerRoot(holder)
        end

        if state == "FREE"
            and ball
            and ball.Parent
        then
            return ball
        end

        return nil
    end

    function API.sendKey(keyCode)
        if VirtualInputManager then
            local ok =
                pcall(function()
                    VirtualInputManager:SendKeyEvent(
                        true,
                        keyCode,
                        false,
                        game
                    )

                    task.delay(
                        0.03,
                        function()
                            pcall(function()
                                VirtualInputManager:SendKeyEvent(
                                    false,
                                    keyCode,
                                    false,
                                    game
                                )
                            end)
                        end
                    )
                end)

            if ok then
                return true
            end
        end

        local vk = ({
            [Enum.KeyCode.E] = 0x45,
            [Enum.KeyCode.Q] = 0x51,
            [Enum.KeyCode.F] = 0x46,
        })[keyCode]

        if vk
            and type(keypress) == "function"
        then
            local ok =
                pcall(function()
                    keypress(vk)
                end)

            if ok then
                task.delay(
                    0.03,
                    function()
                        if type(keyrelease)
                            == "function"
                        then
                            pcall(function()
                                keyrelease(vk)
                            end)
                        end
                    end
                )

                return true
            end
        end

        return false
    end

    function API.stealStep()
        if not API.updateCharacter()
            or not Char.root
            or not Char.root.Parent
        then
            return
        end

        if API.localHasBall() then
            API.resetSpecial()
            return
        end

        local now =
            os.clock()

        if now - State.lastSteal
            < CFG.STEAL_INTERVAL
        then
            return
        end

        if API.specialSteal() then
            State.lastSteal = now
            return
        end

        local target =
            API.normalStealTarget()

        if not target
            or not target.Parent
        then
            return
        end

        State.lastSteal = now

        if API.isGK() then
            local goal =
                API.ownGoal()

            if goal then
                Char.root.CFrame =
                    CFrame.new(
                        goal.Position
                            + CFG.GK_OFFSET
                    )

                API.sendKey(
                    Enum.KeyCode.Q
                )
            end
        end

        Char.root.CFrame =
            CFrame.new(
                target.Position
                    + Vector3.new(
                        0,
                        CFG.STEAL_DISTANCE,
                        0
                    )
            )

        API.sendKey(
            Enum.KeyCode.E
        )
    end
end

--========================================================--
-- RELEASE HELPERS
--========================================================--

do
    function API.waitBallReleased(
        ball,
        timeout
    )
        timeout =
            timeout
            or 0.75

        if not ball then
            return false
        end

        local deadline =
            os.clock()
            + timeout

        while os.clock()
            < deadline
        do
            if not ball.Parent then
                return false
            end

            API.rebuildBall(true)

            local state,
                holder,
                current =
                API.getBallState()

            local insideLocal =
                Char.model
                and ball:IsDescendantOf(
                    Char.model
                )

            if not insideLocal
                and (
                    current == ball
                    or state == "FREE"
                    or holder ~= LP
                )
            then
                return true
            end

            RunService.Heartbeat:Wait()
        end

        API.rebuildBall(true)

        local state,
            holder,
            current =
            API.getBallState()

        if ball
            and ball.Parent
            and Char.model
            and not ball:IsDescendantOf(
                Char.model
            )
        then
            return true
        end

        if current == ball
            and state ~= "HELD"
        then
            return true
        end

        if holder ~= LP
            and current == ball
        then
            return true
        end

        return false
    end

    function API.getBallAfterRelease(ball)
        if ball
            and ball.Parent
            and Char.model
            and not ball:IsDescendantOf(
                Char.model
            )
        then
            return ball
        end

        API.rebuildBall(true)

        local state,
            holder,
            current =
            API.getBallState()

        if current
            and current.Parent
            and (
                state ~= "HELD"
                or holder ~= LP
            )
            and (
                not Char.model
                or not current:IsDescendantOf(
                    Char.model
                )
            )
        then
            return current
        end

        return nil
    end

    function API.waitForReleasedBall(
        ball,
        timeout
    )
        if not API.waitBallReleased(
            ball,
            timeout
                or 0.75
        )
        then
            return nil
        end

        RunService.Heartbeat:Wait()
        RunService.Heartbeat:Wait()

        return
            API.getBallAfterRelease(
                ball
            )
    end

    function API.teleportReleasedBall(
        ball,
        goal
    )
        if not goal
            or not goal.Parent
        then
            return false
        end

        local released =
            API.waitForReleasedBall(
                ball,
                0.75
            )

        if not released
            or not released.Parent
        then
            return false
        end

        local goalPos =
            API.goalPosition(goal)

        if not goalPos then
            return false
        end

        API.rebuildBall(true)

        local state,
            holder,
            current =
            API.getBallState()

        if current
            and current.Parent
            and not (
                state == "HELD"
                and holder == LP
            )
            and (
                not Char.model
                or not current:IsDescendantOf(
                    Char.model
                )
            )
        then
            released = current
        end

        if not released
            or not released.Parent
        then
            return false
        end

        pcall(function()
            released.CFrame =
                goal.CFrame

            released.AssemblyLinearVelocity =
                Vector3.zero

            released.AssemblyAngularVelocity =
                Vector3.zero
        end)

        return true
    end
end

--========================================================--
-- RONALDO
--========================================================--

do
    function API.stopRonaldo()
        State.ronaldoActive = false
        State.ronaldoBall = nil
        State.ronaldoTarget = nil
        State.ronaldoStart = 0
        State.ronaldoDirection = nil

        API.disconnect(
            State.ronaldoTouch
        )

        State.ronaldoTouch = nil
    end

    function API.mouseTarget()
        camera =
            workspace.CurrentCamera

        if not camera then
            return nil
        end

        local m =
            UIS:GetMouseLocation()

        local ray =
            camera:ViewportPointToRay(
                m.X,
                m.Y
            )

        local params =
            RaycastParams.new()

        params.FilterType =
            Enum.RaycastFilterType.Exclude

        params.FilterDescendantsInstances =
            {
                Char.model
            }

        local result =
            workspace:Raycast(
                ray.Origin,
                ray.Direction * 1000,
                params
            )

        return
            result
            and result.Position
            or nil
    end

    function API.selectRonaldo()
        if State.mode ~= 2
            or not State.ronaldo
        then
            return
        end

        if not API.localHasBall() then
            API.notify(
                "RONALDO ADVANCE",
                "You must be holding the ball",
                1.1
            )

            return
        end

        local pos =
            API.mouseTarget()

        if not pos then
            API.notify(
                "RONALDO ADVANCE",
                "Could not select a position",
                1.1
            )

            return
        end

        State.ronaldoTarget =
            pos

        State.ronaldoDirection =
            nil

        API.notify(
            "RONALDO ADVANCE",
            "Direction selected",
            0.9
        )
    end

    function API.startRonaldo()
        if not State.ronaldo
            or not State.ronaldoTarget
        then
            return
        end

        if not API.localHasBall() then
            API.stopRonaldo()

            API.notify(
                "RONALDO ADVANCE",
                "You must be holding the ball",
                1.1
            )

            return
        end

        local _, _, ball =
            API.getBallState()

        if not ball then
            return
        end

        local delta =
            State.ronaldoTarget
            - ball.Position

        if delta.Magnitude
            < 0.1
        then
            API.stopRonaldo()
            return
        end

        State.ronaldoDirection =
            delta.Unit

        if not API.fireShoot(
            delta.Unit,
            Mode[2].speed,
            false
        )
        then
            return
        end

        if not API.waitBallReleased(
            ball,
            0.20
        )
        then
            API.stopRonaldo()
            return
        end

        local releasedBall =
            API.getBallAfterRelease(
                ball
            )

        if not releasedBall then
            local _, _, current =
                API.getBallState()

            releasedBall =
                current
        end

        if not releasedBall
            or not releasedBall.Parent
        then
            API.stopRonaldo()
            return
        end

        API.disconnect(
            State.ronaldoTouch
        )

        State.ronaldoActive = true
        State.ronaldoBall = releasedBall
        State.ronaldoStart =
            os.clock() + 0.02

        State.ronaldoTouch = nil
    end

    function API.updateRonaldo()
        if not State.ronaldoActive then
            return
        end

        local ball =
            State.ronaldoBall

        local target =
            State.ronaldoTarget

        if not ball
            or not ball.Parent
            or not target
        then
            API.stopRonaldo()
            return
        end

        if Char.model
            and ball:IsDescendantOf(
                Char.model
            )
        then
            return
        end

        local direction =
            State.ronaldoDirection

        if not direction
            or direction.Magnitude
                < 0.001
        then
            direction =
                target - ball.Position

            if direction.Magnitude
                < 0.001
            then
                return
            end

            State.ronaldoDirection =
                direction.Unit
        end

        local speed =
            math.clamp(
                Mode[2].speed,
                CFG.MIN_SPEED,
                CFG.MAX_SPEED
            )

        ball.AssemblyLinearVelocity =
            direction.Unit * speed
    end
end

--========================================================--
-- SAE PASS
--========================================================--

do
    function API.clearSAE()
        State.saeActive = false
        State.saeTarget = nil
        State.saeBall = nil
        State.saeStage = "IDLE"
        State.saeTempActive = false
        State.saeWasHoldingBall = false

        if State.saeHighlight then
            State.saeHighlight:Destroy()
            State.saeHighlight = nil
        end
    end

    function API.highlightSAETarget(target)
        if State.saeHighlight then
            State.saeHighlight:Destroy()
            State.saeHighlight = nil
        end

        if not State.saeHighlightEnabled
            or not target
            or not target.Character
        then
            return
        end

        local hl =
            Instance.new("Highlight")

        hl.Name =
            "SaePassTarget"

        hl.FillColor =
            Color3.fromRGB(
                0,
                255,
                120
            )

        hl.FillTransparency =
            0.4

        hl.OutlineColor =
            Color3.new(
                1,
                1,
                1
            )

        hl.OutlineTransparency = 0

        hl.Adornee =
            target.Character

        hl.Parent =
            target.Character

        State.saeHighlight =
            hl
    end

    function API.setSAETarget(target)
        if not State.sae
            or not target
            or target == LP
            or not API.sameTeam(target)
        then
            return false
        end

        if not target.Character
            or not API.playerRoot(target)
        then
            return false
        end

        if State.saeStage == "FLYING"
            and State.saeBall
            and State.saeBall.Parent
        then
            local oldTarget =
                State.saeTarget

            State.saeTarget =
                target

            State.saeActive = true
            State.specialSelecting = false

            API.highlightSAETarget(
                target
            )

            API.notify(
                "SAE PASS",
                "Target changed: "
                    .. tostring(
                        oldTarget
                            and oldTarget.Name
                            or "?"
                    )
                    .. " -> "
                    .. target.Name,
                1.0
            )

            return true
        end

        local state,
            holder,
            ball =
            API.getBallState()

        if state ~= "HELD"
            or holder ~= LP
            or not ball
        then
            API.notify(
                "SAE PASS",
                "You must still own the ball",
                0.9
            )

            return false
        end

        State.saeTarget =
            target

        State.saeBall =
            ball

        State.saeActive =
            true

        State.saeStage =
            "WAIT_RELEASE"

        State.saeWasHoldingBall =
            true

        State.specialSelecting =
            false

        API.highlightSAETarget(
            target
        )

        API.notify(
            "SAE PASS",
            "Target: "
                .. target.Name
                .. " - release ball to pass",
            1.0
        )

        return true
    end

    function API.selectSAE()
        if not State.sae then
            return
        end

        camera =
            workspace.CurrentCamera

        if not camera then
            return
        end

        local mouse =
            UIS:GetMouseLocation()

        local best,
            bestDist =
            nil,
            math.huge

        for _, plr in ipairs(
            Players:GetPlayers()
        ) do
            if plr ~= LP
                and API.sameTeam(plr)
                and plr.Character
            then
                local root =
                    API.playerRoot(plr)

                if root then
                    local point,
                        visible =
                        camera:WorldToViewportPoint(
                            root.Position
                        )

                    if visible
                        and point.Z > 0
                    then
                        local d =
                            (
                                Vector2.new(
                                    point.X,
                                    point.Y
                                )
                                - mouse
                            ).Magnitude

                        if d < bestDist then
                            best =
                                plr

                            bestDist =
                                d
                        end
                    end
                end
            end
        end

        if best
            and bestDist <= 220
        then
            API.highlightSAETarget(
                best
            )
        end

        State.specialSelecting =
            true

        API.notify(
            "SAE PASS",
            "RMB to select/change teammate",
            1.0
        )
    end

    function API.updateSAE()
        if not State.sae then
            API.clearSAE()
            return
        end

        local target =
            State.saeTarget

        if not target then
            return
        end

        if not target.Parent
            or not target.Character
            or not API.playerRoot(target)
        then
            API.clearSAE()
            return
        end

        if State.saeHighlightEnabled then
            if not State.saeHighlight
                or not State.saeHighlight.Parent
                or State.saeHighlight.Adornee
                    ~= target.Character
            then
                API.highlightSAETarget(
                    target
                )
            end
        elseif State.saeHighlight then
            State.saeHighlight:Destroy()
            State.saeHighlight = nil
        end

        if State.saeStage ==
            "WAIT_RELEASE"
        then
            if API.localHasBall() then
                State.saeWasHoldingBall =
                    true

                return
            end

            API.rebuildBall(true)

            local state,
                holder,
                current =
                API.getBallState()

            local candidate =
                State.saeBall

            if current
                and current.Parent
                and (
                    current
                    == State.saeBall
                    or not Char.model
                    or not current:IsDescendantOf(
                        Char.model
                    )
                )
            then
                candidate =
                    current
            end

            if candidate
                and candidate.Parent
                and (
                    not Char.model
                    or not candidate:IsDescendantOf(
                        Char.model
                    )
                )
                and (
                    state == "FREE"
                    or (
                        state == "HELD"
                        and holder
                        and holder ~= LP
                    )
                    or current == candidate
                )
            then
                State.saeBall =
                    candidate

                State.saeStage =
                    "FLYING"

                State.saeWasHoldingBall =
                    false

                API.notify(
                    "SAE PASS",
                    "Ball released -> flying to "
                        .. target.Name,
                    0.8
                )
            end

            return
        end

        if State.saeStage
            ~= "FLYING"
        then
            return
        end

        local ball =
            State.saeBall

        if not ball
            or not ball.Parent
        then
            API.rebuildBall(true)

            local _, _, current =
                API.getBallState()

            if current
                and current.Parent
                and (
                    not Char.model
                    or not current:IsDescendantOf(
                        Char.model
                    )
                )
            then
                ball =
                    current

                State.saeBall =
                    current
            else
                API.clearSAE()
                return
            end
        end

        local state,
            holder,
            currentBall =
            API.getBallState()

        if state == "HELD" then
            if holder == target then
                API.notify(
                    "SAE PASS",
                    "Ball reached "
                        .. target.Name,
                    0.7
                )
            end

            API.clearSAE()
            return
        end

        if currentBall
            and currentBall.Parent
            and (
                not Char.model
                or not currentBall:IsDescendantOf(
                    Char.model
                )
            )
        then
            ball =
                currentBall

            State.saeBall =
                currentBall
        end

        local targetRoot =
            API.playerRoot(target)

        if not targetRoot
            or not targetRoot.Parent
        then
            API.clearSAE()
            return
        end

        local speed =
            math.clamp(
                Mode[1].speed,
                CFG.MIN_SPEED,
                CFG.MAX_SPEED
            )

        local delta =
            targetRoot.Position
            - ball.Position

        if delta.Magnitude <= 2.5 then
            ball.AssemblyLinearVelocity =
                Vector3.zero

            API.rebuildBall(false)

            return
        end

        ball.AssemblyLinearVelocity =
            delta.Unit * speed
    end
end

--========================================================--
-- TP
--========================================================--

do
    function API.restoreTP(reason)
        if not State.tpActive then
            return
        end

        local saved =
            State.tpReturn

        State.tpActive = false
        State.tpReturn = nil
        State.tpGoalActive = false

        if saved
            and API.updateCharacter()
            and Char.root
            and Char.root.Parent
        then
            Char.root.CFrame =
                saved
        end

        if reason then
            API.notify(
                "TP RETURN",
                reason,
                1.2
            )
        end
    end

    local function currentBallTarget()
        local state,
            holder,
            ball =
            API.getBallState()

        if state == "HELD"
            and holder
            and holder ~= LP
        then
            return
                API.playerRoot(holder),
                holder
        end

        if state == "FREE"
            and ball
            and ball.Parent
        then
            return
                ball,
                nil
        end

        return
            nil,
            nil
    end

    function API.startTP()
        if State.tpActive then
            API.restoreTP("Returned")
            return
        end

        if not API.updateCharacter()
            or not Char.root
        then
            API.notify(
                "TP RETURN",
                "Character not found",
                1.2
            )

            return
        end

        State.tpReturn =
            Char.root.CFrame

        if API.isGK() then
            local goal =
                API.ownGoal()

            if goal then
                if not API.inGoal(
                    Char.root.Position,
                    goal
                )
                then
                    Char.root.CFrame =
                        CFrame.new(
                            goal.Position
                                + CFG.GK_OFFSET
                        )
                end

                task.wait(0.15)

                API.sendKey(
                    Enum.KeyCode.Q
                )

                local root =
                    select(
                        1,
                        currentBallTarget()
                    )

                if root
                    and root.Parent
                then
                    Char.root.CFrame =
                        CFrame.new(
                            root.Position
                                + Vector3.new(
                                    0,
                                    CFG.STEAL_DISTANCE,
                                    0
                                )
                        )
                end

                State.tpActive =
                    true

                State.tpStarted =
                    os.clock()

                API.notify(
                    "GK RETURN",
                    "Q -> TP -> follow ball",
                    1.2
                )

                return
            end
        end

        local state,
            holder,
            ball =
            API.getBallState()

        local pos
        local name

        if state == "HELD"
            and holder
            and holder ~= LP
        then
            local root =
                API.playerRoot(holder)

            if root then
                pos =
                    root.Position
                    + Vector3.new(
                        0,
                        CFG.STEAL_DISTANCE,
                        0
                    )

                name =
                    holder.Name
            end

        elseif state == "FREE"
            and ball
        then
            pos =
                ball.Position
                + Vector3.new(
                    0,
                    CFG.STEAL_DISTANCE,
                    0
                )

            name =
                "FREE BALL"
        end

        if not pos then
            State.tpReturn =
                nil

            API.notify(
                "TP RETURN",
                "No valid ball for TP",
                1.2
            )

            return
        end

        State.tpActive = true
        State.tpStarted =
            os.clock()

        Char.root.CFrame =
            CFrame.new(pos)

        API.notify(
            "TP RETURN",
            string.format(
                "TP -> %s trong %.2fs",
                name,
                State.tpDuration
            ),
            1.3
        )
    end

    function API.updateTP()
        if not State.tpActive then
            return
        end

        if not API.updateCharacter()
            or not Char.root
        then
            return
        end

        if API.localHasBall() then
            API.restoreTP(
                "Ball obtained -> returning"
            )

            return
        end

        local root =
            select(
                1,
                currentBallTarget()
            )

        if root
            and root.Parent
        then
            Char.root.CFrame =
                CFrame.new(
                    root.Position
                        + Vector3.new(
                            0,
                            CFG.STEAL_DISTANCE,
                            0
                        )
                )
        end

        if os.clock()
                - State.tpStarted
            >= State.tpDuration
        then
            API.restoreTP(
                "TP timer expired"
            )
        end
    end

    function API.tpGoal()
        local goal =
            API.opponentGoal()

        if not goal then
            API.notify(
                "TP GOAL",
                "Opponent AutoGoal not found",
                1.2
            )

            return
        end

        local goalPos =
            API.goalPosition(
                goal
            )

        if not goalPos then
            API.notify(
                "TP GOAL",
                "Goal position not found",
                1.2
            )

            return
        end

        local state,
            holder,
            ball =
            API.getBallState()

        if not ball
            or not ball.Parent
        then
            API.notify(
                "TP GOAL",
                "Ball not found",
                1.2
            )

            return
        end

        if state == "HELD"
            and holder == LP
        then
            local direction =
                goalPos
                - ball.Position

            if direction.Magnitude
                < 0.001
            then
                API.notify(
                    "TP GOAL",
                    "Invalid shoot direction",
                    1.0
                )

                return
            end

            local fired =
                API.fireShoot(
                    direction.Unit,
                    CFG.SHOOT_FORCE,
                    false
                )

            if not fired then
                API.notify(
                    "TP GOAL",
                    "ShootBall failed",
                    1.2
                )

                return
            end

            local released =
                API.waitForReleasedBall(
                    ball,
                    0.8
                )

            if not released then
                API.notify(
                    "TP GOAL",
                    "Server did not release the ball",
                    1.2
                )

                return
            end

            local success =
                API.teleportReleasedBall(
                    released,
                    goal
                )

            if success then
                State.tpGoalActive =
                    true

                API.notify(
                    "TP GOAL",
                    "Shot registered -> ball TP to goal",
                    1.1
                )
            else
                API.notify(
                    "TP GOAL",
                    "Ball released but TP failed",
                    1.2
                )
            end

            return
        end

        if state == "FREE"
            and ball
            and ball.Parent
        then
            local success =
                pcall(function()
                    ball.CFrame =
                        goal.CFrame

                    ball.AssemblyLinearVelocity =
                        Vector3.zero

                    ball.AssemblyAngularVelocity =
                        Vector3.zero
                end)

            if success then
                State.tpGoalActive =
                    true

                API.notify(
                    "TP GOAL",
                    "Free ball -> goal",
                    1.1
                )
            end

            return
        end

        API.notify(
            "TP GOAL",
            "Ball is not available",
            1.1
        )
    end
end

--========================================================--
-- UI
--========================================================--

do
    local function corner(
        parent,
        radius
    )
        local c =
            Instance.new("UICorner")

        c.CornerRadius =
            UDim.new(
                0,
                radius or 8
            )

        c.Parent = parent
    end

    local function button(
        parent,
        text,
        x,
        y,
        w,
        h
    )
        local b =
            Instance.new("TextButton")

        b.Size =
            UDim2.fromOffset(
                w,
                h
            )

        b.Position =
            UDim2.fromOffset(
                x,
                y
            )

        b.BackgroundColor3 =
            Color3.fromRGB(
                43,
                43,
                51
            )

        b.BorderSizePixel = 0
        b.Text = text

        b.TextColor3 =
            Color3.fromRGB(
                235,
                235,
                240
            )

        b.TextSize = 12
        b.Font =
            Enum.Font.GothamMedium

        b.Parent = parent

        corner(
            b,
            7
        )

        return b
    end

    local function label(
        parent,
        text,
        x,
        y,
        w,
        h,
        size
    )
        local l =
            Instance.new("TextLabel")

        l.Size =
            UDim2.fromOffset(
                w,
                h
            )

        l.Position =
            UDim2.fromOffset(
                x,
                y
            )

        l.BackgroundTransparency = 1
        l.Text = text

        l.TextColor3 =
            Color3.fromRGB(
                205,
                205,
                215
            )

        l.TextSize =
            size or 12

        l.Font =
            Enum.Font.GothamMedium

        l.TextXAlignment =
            Enum.TextXAlignment.Left

        l.Parent = parent

        return l
    end

    local function box(
        parent,
        value,
        x,
        y,
        w,
        h
    )
        local b =
            Instance.new("TextBox")

        b.Size =
            UDim2.fromOffset(
                w,
                h
            )

        b.Position =
            UDim2.fromOffset(
                x,
                y
            )

        b.BackgroundColor3 =
            Color3.fromRGB(
                40,
                40,
                47
            )

        b.BorderSizePixel = 0
        b.Text =
            tostring(value)

        b.TextColor3 =
            Color3.new(
                1,
                1,
                1
            )

        b.TextSize = 12
        b.Font =
            Enum.Font.GothamMedium

        b.ClearTextOnFocus = false

        b.Parent = parent

        corner(
            b,
            7
        )

        return b
    end

    local gui =
        Instance.new("ScreenGui")

    gui.Name =
        "BallController"

    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true

    gui.ZIndexBehavior =
        Enum.ZIndexBehavior.Sibling

    gui.DisplayOrder = -100
    gui.Enabled = true

    gui.Parent =
        PlayerGui

    UI.gui = gui

    UI.main =
        Instance.new("Frame")

    UI.main.Size =
        UDim2.fromOffset(
            350,
            445
        )

    UI.main.Position =
        UDim2.fromOffset(
            25,
            220
        )

    UI.main.BackgroundColor3 =
        Color3.fromRGB(
            24,
            24,
            29
        )

    UI.main.BorderSizePixel = 0
    UI.main.ClipsDescendants = true

    UI.main.Parent =
        gui

    corner(
        UI.main,
        12
    )

    UI.title =
        label(
            UI.main,
            "⚽ BALL CONTROLLER V4.5",
            10,
            5,
            240,
            35,
            18
        )

    UI.title.Font =
        Enum.Font.GothamBold

    UI.zoomOut =
        button(
            UI.main,
            "-",
            228,
            10,
            26,
            28
        )

    UI.zoomOut.TextSize = 18

    UI.zoomIn =
        button(
            UI.main,
            "+",
            256,
            10,
            26,
            28
        )

    UI.zoomIn.TextSize = 18

    UI.minimize =
        button(
            UI.main,
            "—",
            312,
            10,
            28,
            28
        )

    UI.minimize.TextSize = 18

    UI.mainScale =
        Instance.new("UIScale")

    UI.mainScale.Parent =
        UI.main

    UI.status =
        label(
            UI.main,
            "Status: READY",
            10,
            42,
            320,
            22,
            13
        )

    UI.ballStatus =
        label(
            UI.main,
            "BALL: SEARCHING...",
            10,
            64,
            320,
            22,
            12
        )

    UI.control =
        button(
            UI.main,
            "CONTROL KEY: F",
            10,
            92,
            160,
            36
        )

    UI.mode =
        button(
            UI.main,
            "MODE: 1 [CAMERA]",
            180,
            92,
            160,
            36
        )

    UI.anchor =
        button(
            UI.main,
            "ANCHOR: ON",
            10,
            136,
            160,
            36
        )

    UI.force =
        button(
            UI.main,
            "FORCE UNANCHOR",
            180,
            136,
            160,
            36
        )

    UI.steal =
        button(
            UI.main,
            "STEAL BALL: OFF",
            10,
            180,
            160,
            36
        )

    UI.sae =
        button(
            UI.main,
            "SAE PASS: OFF",
            180,
            180,
            160,
            36
        )

    UI.settings =
        button(
            UI.main,
            "⚙ SETTINGS",
            10,
            224,
            160,
            36
        )

    UI.statusToggle =
        button(
            UI.main,
            "BALL STATUS: ON",
            180,
            224,
            160,
            36
        )

    UI.tp =
        button(
            UI.main,
            "TP RETURN",
            10,
            268,
            150,
            36
        )

    UI.tpGoal =
        button(
            UI.main,
            "TP GOAL",
            170,
            268,
            170,
            36
        )

    UI.tpTimeLabel =
        label(
            UI.main,
            "TP TIME (S):",
            10,
            310,
            85,
            36,
            11
        )

    UI.tpTime =
        box(
            UI.main,
            State.tpDuration,
            100,
            310,
            70,
            36
        )

    UI.moreMod =
        button(
            UI.main,
            "MORE MODS",
            180,
            310,
            160,
            36
        )

    UI.info =
        label(
            UI.main,
            "F = action theo mode.\n"
                .. "Mode 1: camera control.\n"
                .. "Mode 2: Ronaldo kick.\n"
                .. "RMB logo = center UI.\n"
                .. "TP Return/GK = follow the ball.",
            10,
            350,
            330,
            75,
            11
        )

    UI.info.TextWrapped = true

    UI.info.TextYAlignment =
        Enum.TextYAlignment.Top

    UI.info.TextColor3 =
        Color3.fromRGB(
            145,
            145,
            155
        )

    UI.restore =
        button(
            gui,
            "⚽",
            18,
            78,
            48,
            48
        )

    UI.restore.TextSize =
        23

    corner(
        UI.restore,
        24
    )

    UI.actionF =
        button(
            gui,
            "F ACTION",
            18,
            136,
            86,
            42
        )

    UI.actionF.TextSize =
        11

    UI.actionF.ZIndex =
        20

    corner(
        UI.actionF,
        10
    )

    UI.specialToggle =
        button(
            gui,
            "SPECIAL: OFF",
            18,
            184,
            110,
            42
        )

    UI.specialToggle.TextSize =
        10

    UI.specialToggle.ZIndex =
        20

    corner(
        UI.specialToggle,
        10
    )

    UI.actionF.Visible =
        false

    UI.specialToggle.Visible =
        false

    UI.notificationHolder =
        Instance.new("Frame")

    UI.notificationHolder.Size =
        UDim2.fromOffset(
            320,
            300
        )

    UI.notificationHolder.AnchorPoint =
        Vector2.new(
            0.5,
            0
        )

    UI.notificationHolder.Position =
        UDim2.new(
            0.5,
            0,
            0,
            0
        )

    UI.notificationHolder.BackgroundTransparency =
        1

    UI.notificationHolder.Parent =
        gui

    local notificationLayout =
        Instance.new("UIListLayout")

    notificationLayout.Padding =
        UDim.new(
            0,
            7
        )

    notificationLayout.HorizontalAlignment =
        Enum.HorizontalAlignment.Center

    notificationLayout.VerticalAlignment =
        Enum.VerticalAlignment.Top

    notificationLayout.Parent =
        UI.notificationHolder

    UI.statusPanel =
        Instance.new("Frame")

    UI.statusPanel.Size =
        UDim2.fromOffset(
            245,
            125
        )

    UI.statusPanel.Position =
        UDim2.fromOffset(
            390,
            80
        )

    UI.statusPanel.BackgroundColor3 =
        Color3.fromRGB(
            22,
            22,
            27
        )

    UI.statusPanel.BorderSizePixel = 0
    UI.statusPanel.ClipsDescendants = true

    UI.statusPanel.Parent =
        gui

    corner(
        UI.statusPanel,
        10
    )

    UI.statusScale =
        Instance.new("UIScale")

    UI.statusScale.Parent =
        UI.statusPanel

    UI.statusTitle =
        label(
            UI.statusPanel,
            "⚽ BALL STATUS",
            10,
            5,
            170,
            25,
            14
        )

    UI.statusTitle.Font =
        Enum.Font.GothamBold

    UI.statusMin =
        button(
            UI.statusPanel,
            "—",
            180,
            6,
            25,
            23
        )

    UI.statusClose =
        button(
            UI.statusPanel,
            "×",
            210,
            6,
            25,
            23
        )

    UI.statusState =
        label(
            UI.statusPanel,
            "STATUS: SEARCHING",
            10,
            35,
            220,
            22,
            12
        )

    UI.statusOwner =
        label(
            UI.statusPanel,
            "OWNER: —",
            10,
            58,
            220,
            22,
            12
        )

    UI.statusPlayer =
        label(
            UI.statusPanel,
            "CONTROL: OFF",
            10,
            81,
            220,
            22,
            12
        )

    UI.statusMini = false

    UI.statusFull =
        UDim2.fromOffset(
            245,
            125
        )

    UI.statusSmall =
        UDim2.fromOffset(
            245,
            34
        )

    UI.settingsFrame =
        Instance.new("Frame")

    UI.settingsFrame.Size =
        UDim2.fromOffset(
            490,
            320
        )

    UI.settingsFrame.Position =
        State.__uiStablePositions.settingsFrame
            and UDim2.fromOffset(
                State.__uiStablePositions.settingsFrame.X,
                State.__uiStablePositions.settingsFrame.Y
            )
            or UDim2.fromOffset(
                390,
                240
            )

    UI.settingsFrame.BackgroundColor3 =
        Color3.fromRGB(
            22,
            22,
            27
        )

    UI.settingsFrame.BorderSizePixel = 0
    UI.settingsFrame.ClipsDescendants = true
    UI.settingsFrame.Visible = false
    UI.settingsFrame.Parent = gui

    corner(
        UI.settingsFrame,
        12
    )

    UI.settingsScale =
        Instance.new("UIScale")

    UI.settingsScale.Parent =
        UI.settingsFrame

    UI.settingsTitle =
        label(
            UI.settingsFrame,
            "⚙ BALL SETTINGS",
            12,
            8,
            270,
            32,
            17
        )

    UI.settingsTitle.Font =
        Enum.Font.GothamBold

    UI.settingsZoomOut =
        button(
            UI.settingsFrame,
            "-",
            378,
            8,
            26,
            28
        )

    UI.settingsZoomIn =
        button(
            UI.settingsFrame,
            "+",
            406,
            8,
            26,
            28
        )

    UI.closeSettings =
        button(
            UI.settingsFrame,
            "X",
            454,
            8,
            28,
            28
        )

    UI.tabs = {
        button(
            UI.settingsFrame,
            "GENERAL",
            10,
            48,
            104,
            30
        ),

        button(
            UI.settingsFrame,
            "MODE 1",
            120,
            48,
            104,
            30
        ),

        button(
            UI.settingsFrame,
            "MODE 2",
            230,
            48,
            104,
            30
        ),
    }

    local content =
        Instance.new("ScrollingFrame")

    content.Size =
        UDim2.new(
            1,
            -20,
            1,
            -90
        )

    content.Position =
        UDim2.fromOffset(
            10,
            88
        )

    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = 3
    content.ScrollBarImageTransparency = 0.35
    content.ScrollingDirection =
        Enum.ScrollingDirection.Y

    content.ScrollingEnabled = false

    content.CanvasPosition =
        Vector2.zero

    content.CanvasSize =
        UDim2.fromOffset(
            0,
            330
        )

    content.Parent =
        UI.settingsFrame

    UI.settingsContent =
        content

    UI.general = {}

    UI.general.title =
        label(
            content,
            "GENERAL SETTINGS",
            10,
            8,
            220,
            24,
            13
        )

    UI.general.title.Font =
        Enum.Font.GothamBold

    UI.general.keyLabel =
        label(
            content,
            "CONTROL KEY",
            10,
            48,
            110,
            25,
            12
        )

    UI.general.key =
        button(
            content,
            "F",
            145,
            44,
            95,
            32
        )

    UI.general.anchorLabel =
        label(
            content,
            "ANCHOR",
            10,
            88,
            110,
            25,
            12
        )

    UI.general.anchor =
        button(
            content,
            "ON",
            145,
            84,
            95,
            32
        )

    UI.general.autoStealLabel =
        label(
            content,
            "AUTO STEAL OFF",
            10,
            128,
            125,
            25,
            11
        )

    UI.general.autoSteal =
        button(
            content,
            "ON",
            145,
            124,
            95,
            32
        )

    UI.general.tpLabel =
        label(
            content,
            "TP RETURN TIME",
            10,
            168,
            125,
            25,
            11
        )

    UI.general.tp =
        box(
            content,
            State.tpDuration,
            145,
            164,
            95,
            32
        )

    UI.general.autoGoalLabel =
        label(
            content,
            "AUTO GOAL",
            10,
            208,
            110,
            25,
            12
        )

    UI.general.autoGoal =
        button(
            content,
            "OFF",
            145,
            204,
            95,
            32
        )

    UI.general.saeHighlightLabel =
        label(
            content,
            "SAE HIGHLIGHT",
            255,
            88,
            135,
            25,
            12
        )

    UI.general.saeHighlight =
        button(
            content,
            "ON",
            380,
            84,
            100,
            32
        )

    UI.general.shootVelocityLabel =
        label(
            content,
            "SHOOT FORCE MAX",
            255,
            128,
            135,
            25,
            11
        )

    UI.general.shootVelocityLabel.TextWrapped =
        true

    UI.general.shootVelocity =
        box(
            content,
            State.shootMaxVelocity,
            380,
            124,
            100,
            32
        )

    UI.general.shootVelocityToggle =
        button(
            content,
            "OFF",
            380,
            162,
            100,
            28
        )

    UI.general.hint =
        label(
            content,
            "Auto Goal: steal -> shoot -> TP to AutoGoal.\n"
                .. "Shoot Force Max ON: game force + (Max - 100).\n"
                .. "Minimum Shoot Force Max: 100.",
            255,
            200,
            225,
            80,
            10
        )

    UI.general.hint.TextWrapped =
        true

    UI.general.hint.TextYAlignment =
        Enum.TextYAlignment.Top

    UI.m1 = {}

    UI.m1.speedLabel =
        label(
            content,
            "SPEED",
            10,
            10,
            110,
            25,
            12
        )

    UI.m1.speed =
        box(
            content,
            Mode[1].speed,
            120,
            6,
            220,
            32
        )

    UI.m1.advanceLabel =
        label(
            content,
            "ADVANCE MODE",
            10,
            120,
            110,
            25,
            12
        )

    UI.m1.advance =
        button(
            content,
            "OFF",
            120,
            116,
            120,
            32
        )

    UI.m1.hint =
        label(
            content,
            "WASD moves the ball; Q/E changes height.",
            10,
            70,
            440,
            100,
            11
        )

    UI.m1.hint.TextWrapped = true

    UI.m2 = {}

    UI.m2.speedLabel =
        label(
            content,
            "SPEED",
            10,
            10,
            110,
            25,
            12
        )

    UI.m2.speed =
        box(
            content,
            Mode[2].speed,
            120,
            6,
            145,
            32
        )

    UI.m2.advanceLabel =
        label(
            content,
            "RONALDO ADVANCE",
            10,
            122,
            120,
            25,
            12
        )

    UI.m2.advance =
        button(
            content,
            "OFF",
            140,
            118,
            120,
            32
        )

    UI.m2.hint =
        label(
            content,
            "Ronaldo Advance: RMB selects a field point, then F kicks.",
            10,
            70,
            460,
            100,
            11
        )

    UI.m2.hint.TextWrapped = true

    UI.settingsReady = true
end

--========================================================--
-- UI LOGIC
--========================================================--

do
    function API.verifyUI()
        local required = {
            {"main", UI.main},
            {"title", UI.title},
            {"control", UI.control},
            {"mode", UI.mode},
            {"anchor", UI.anchor},
            {"force", UI.force},
            {"steal", UI.steal},
            {"sae", UI.sae},
            {"settings", UI.settings},
            {"statusToggle", UI.statusToggle},
            {"tp", UI.tp},
            {"tpGoal", UI.tpGoal},
            {"moreMod", UI.moreMod},
            {"restore", UI.restore},
            {"actionF", UI.actionF},
            {"specialToggle", UI.specialToggle},
            {"settingsFrame", UI.settingsFrame},
            {"settingsTitle", UI.settingsTitle},
            {"settingsZoomOut", UI.settingsZoomOut},
            {"settingsZoomIn", UI.settingsZoomIn},
            {"closeSettings", UI.closeSettings},
            {"m1.advance", UI.m1.advance},
            {"m2.advance", UI.m2.advance},
            {"general.key", UI.general.key},
            {"general.anchor", UI.general.anchor},
            {"general.autoSteal", UI.general.autoSteal},
            {"general.autoGoal", UI.general.autoGoal},
            {"general.shootVelocity", UI.general.shootVelocity},
            {"general.shootVelocityToggle", UI.general.shootVelocityToggle},
        }

        for i = 1, #required do
            if required[i][2] == nil then
                error(
                    "Ball Controller UI init failed: "
                        .. required[i][1]
                )
            end
        end

        UI.ready = true
        return true
    end

    function API.clampUI(frame)
        camera =
            workspace.CurrentCamera

        if not camera
            or not frame
            or not frame.Parent
        then
            return
        end

        local viewport =
            camera.ViewportSize

        local size =
            frame.AbsoluteSize

        local x =
            math.clamp(
                frame.AbsolutePosition.X,
                0,
                math.max(
                    0,
                    viewport.X - size.X
                )
            )

        local y =
            math.clamp(
                frame.AbsolutePosition.Y,
                0,
                math.max(
                    0,
                    viewport.Y - size.Y
                )
            )

        frame.Position =
            UDim2.fromOffset(
                x,
                y
            )
    end

    function API.applySavedUIPositions()
        for name, pos in pairs(
            State.__uiStablePositions
        ) do
            local obj =
                UI[name]

            if obj
                and typeof(obj)
                    == "Instance"
                and obj:IsA("GuiObject")
                and typeof(pos)
                    == "Vector2"
            then
                obj.Position =
                    UDim2.fromOffset(
                        pos.X,
                        pos.Y
                    )
            end
        end
    end

    function API.scaleUI(value)
        value =
            math.clamp(
                math.floor(
                    value * 100
                        + 0.5
                ) / 100,
                CFG.ZOOM_MIN,
                CFG.ZOOM_MAX
            )

        State.uiScale =
            value

        saveConfig()

        local effective =
            value
            * (State.responsiveScale or 1)

        UI.mainScale.Scale =
            effective

        UI.settingsScale.Scale =
            effective

        UI.statusScale.Scale =
            effective

        task.defer(function()
            API.clampUI(UI.main)
            API.clampUI(UI.settingsFrame)
            API.clampUI(UI.statusPanel)
            API.clampUI(UI.restore)
            API.clampUI(UI.actionF)
            API.clampUI(UI.specialToggle)
        end)
    end

    function API.centerUI()
        camera =
            workspace.CurrentCamera

        if not camera then
            return
        end

        local view =
            camera.ViewportSize

        if State.__uiStablePositions.main then
            local p =
                State.__uiStablePositions.main

            UI.main.Position =
                UDim2.fromOffset(
                    p.X,
                    p.Y
                )
        else
            UI.main.Position =
                UDim2.fromOffset(
                    math.max(
                        0,
                        (
                            view.X
                            - UI.main.AbsoluteSize.X
                        ) / 2
                    ),
                    math.max(
                        0,
                        (
                            view.Y
                            - UI.main.AbsoluteSize.Y
                        ) / 2
                    )
                )
        end

        if State.settingsOpen
            and UI.settingsFrame.Visible
        then
            API.clampUI(
                UI.settingsFrame
            )
        end
    end

    function API.statusMini(value)
        UI.statusMini =
            value

        UI.statusPanel.Size =
            value
            and UI.statusSmall
            or UI.statusFull

        UI.statusState.Visible =
            not value

        UI.statusOwner.Visible =
            not value

        UI.statusPlayer.Visible =
            not value

        UI.statusMin.Text =
            value
            and "+"
            or "—"

        task.defer(function()
            API.clampUI(
                UI.statusPanel
            )
        end)
    end

    function API.syncSettingsVisibility()
        if not UI.settingsReady then
            return
        end

        local activeTab =
            math.clamp(
                State.settingsTab
                    or 1,
                1,
                3
            )

        State.settingsTab =
            activeTab

        local generalVisible =
            activeTab == 1

        local mode1Visible =
            activeTab == 2

        local mode2Visible =
            activeTab == 3

        for _, obj in pairs(
            UI.general
        ) do
            if typeof(obj)
                    == "Instance"
                and obj:IsA(
                    "GuiObject"
                )
            then
                obj.Visible =
                    generalVisible
            end
        end

        for _, obj in pairs(
            UI.m1
        ) do
            if typeof(obj)
                    == "Instance"
                and obj:IsA(
                    "GuiObject"
                )
            then
                obj.Visible =
                    mode1Visible
            end
        end

        for _, obj in pairs(
            UI.m2
        ) do
            if typeof(obj)
                    == "Instance"
                and obj:IsA(
                    "GuiObject"
                )
            then
                obj.Visible =
                    mode2Visible
            end
        end

        for i = 1, 3 do
            UI.tabs[i].BackgroundColor3 =
                i == activeTab
                and Color3.fromRGB(
                    55,
                    75,
                    95
                )
                or Color3.fromRGB(
                    40,
                    40,
                    47
                )
        end
    end

    function API.applyResponsiveUI()
        camera =
            workspace.CurrentCamera

        if not camera then
            return
        end

        local vp =
            camera.ViewportSize

        local widthFactor =
            vp.X / 1440

        local heightFactor =
            vp.Y / 900

        local scale =
            math.min(
                widthFactor,
                heightFactor
            )

        State.responsiveScale =
            math.clamp(
                scale,
                0.82,
                1.08
            )

        local effective =
            State.uiScale
            * State.responsiveScale

        UI.mainScale.Scale =
            effective

        UI.settingsScale.Scale =
            effective

        UI.statusScale.Scale =
            effective

        UI.notificationHolder.Size =
            UDim2.fromOffset(
                math.min(
                    320,
                    math.max(
                        260,
                        vp.X - 20
                    )
                ),
                300
            )

        UI.main.Size =
            UDim2.fromOffset(
                350,
                445
            )

        UI.title.Size =
            UDim2.fromOffset(
                240,
                35
            )

        UI.title.TextSize = 18

        UI.zoomOut.Position =
            UDim2.fromOffset(
                228,
                10
            )

        UI.zoomIn.Position =
            UDim2.fromOffset(
                256,
                10
            )

        UI.minimize.Position =
            UDim2.fromOffset(
                312,
                10
            )

        UI.control.Size =
            UDim2.fromOffset(
                160,
                36
            )

        UI.mode.Size =
            UDim2.fromOffset(
                160,
                36
            )

        UI.mode.Position =
            UDim2.fromOffset(
                180,
                92
            )

        UI.anchor.Size =
            UDim2.fromOffset(
                160,
                36
            )

        UI.force.Size =
            UDim2.fromOffset(
                160,
                36
            )

        UI.force.Position =
            UDim2.fromOffset(
                180,
                136
            )

        UI.steal.Size =
            UDim2.fromOffset(
                160,
                36
            )

        UI.sae.Size =
            UDim2.fromOffset(
                160,
                36
            )

        UI.sae.Position =
            UDim2.fromOffset(
                180,
                180
            )

        UI.settings.Size =
            UDim2.fromOffset(
                160,
                36
            )

        UI.statusToggle.Size =
            UDim2.fromOffset(
                160,
                36
            )

        UI.statusToggle.Position =
            UDim2.fromOffset(
                180,
                224
            )

        UI.tp.Size =
            UDim2.fromOffset(
                150,
                36
            )

        UI.tpGoal.Size =
            UDim2.fromOffset(
                170,
                36
            )

        UI.tpGoal.Position =
            UDim2.fromOffset(
                170,
                268
            )

        UI.tpTimeLabel.Position =
            UDim2.fromOffset(
                10,
                310
            )

        UI.tpTime.Position =
            UDim2.fromOffset(
                100,
                310
            )

        UI.moreMod.Position =
            UDim2.fromOffset(
                180,
                310
            )

        UI.info.Position =
            UDim2.fromOffset(
                10,
                350
            )

        UI.info.Size =
            UDim2.fromOffset(
                330,
                75
            )

        UI.info.TextSize =
            11

        UI.restore.Size =
            UDim2.fromOffset(
                48,
                48
            )

        UI.restore.Position =
            UDim2.fromOffset(
                18,
                78
            )

        UI.actionF.Visible =
            false

        UI.specialToggle.Visible =
            false

        UI.settingsFrame.Size =
            UDim2.fromOffset(
                490,
                320
            )

        UI.settingsZoomOut.Position =
            UDim2.fromOffset(
                378,
                8
            )

        UI.settingsZoomIn.Position =
            UDim2.fromOffset(
                406,
                8
            )

        UI.closeSettings.Position =
            UDim2.fromOffset(
                454,
                8
            )

        if UI.settingsContent then
            UI.settingsContent.ScrollingEnabled =
                false

            UI.settingsContent.CanvasPosition =
                Vector2.zero

            UI.settingsContent.CanvasSize =
                UDim2.fromOffset(
                    0,
                    330
                )
        end

        UI.tabs[1].Size =
            UDim2.fromOffset(
                104,
                30
            )

        UI.tabs[2].Size =
            UDim2.fromOffset(
                104,
                30
            )

        UI.tabs[2].Position =
            UDim2.fromOffset(
                120,
                48
            )

        UI.tabs[3].Size =
            UDim2.fromOffset(
                104,
                30
            )

        UI.tabs[3].Position =
            UDim2.fromOffset(
                230,
                48
            )

        UI.general.title.Position =
            UDim2.fromOffset(
                10,
                8
            )

        UI.general.keyLabel.Position =
            UDim2.fromOffset(
                10,
                48
            )

        UI.general.key.Position =
            UDim2.fromOffset(
                145,
                44
            )

        UI.general.anchorLabel.Position =
            UDim2.fromOffset(
                10,
                88
            )

        UI.general.anchor.Position =
            UDim2.fromOffset(
                145,
                84
            )

        UI.general.autoStealLabel.Position =
            UDim2.fromOffset(
                10,
                128
            )

        UI.general.autoSteal.Position =
            UDim2.fromOffset(
                145,
                124
            )

        UI.general.tpLabel.Position =
            UDim2.fromOffset(
                10,
                168
            )

        UI.general.tp.Position =
            UDim2.fromOffset(
                145,
                164
            )

        UI.general.autoGoalLabel.Position =
            UDim2.fromOffset(
                10,
                208
            )

        UI.general.autoGoal.Position =
            UDim2.fromOffset(
                145,
                204
            )

        UI.general.saeHighlightLabel.Position =
            UDim2.fromOffset(
                255,
                88
            )

        UI.general.saeHighlight.Position =
            UDim2.fromOffset(
                380,
                84
            )

        UI.general.shootVelocityLabel.Position =
            UDim2.fromOffset(
                255,
                128
            )

        UI.general.shootVelocity.Position =
            UDim2.fromOffset(
                380,
                124
            )

        UI.general.shootVelocityToggle.Position =
            UDim2.fromOffset(
                380,
                162
            )

        UI.general.hint.Position =
            UDim2.fromOffset(
                255,
                200
            )

        UI.general.hint.Size =
            UDim2.fromOffset(
                225,
                80
            )

        UI.m1.speedLabel.Position =
            UDim2.fromOffset(
                10,
                10
            )

        UI.m1.speed.Position =
            UDim2.fromOffset(
                120,
                6
            )

        UI.m1.advanceLabel.Position =
            UDim2.fromOffset(
                10,
                120
            )

        UI.m1.advance.Position =
            UDim2.fromOffset(
                120,
                116
            )

        UI.m1.hint.Position =
            UDim2.fromOffset(
                10,
                70
            )

        UI.m1.hint.Size =
            UDim2.fromOffset(
                440,
                100
            )

        UI.m2.speedLabel.Position =
            UDim2.fromOffset(
                10,
                10
            )

        UI.m2.speed.Position =
            UDim2.fromOffset(
                120,
                6
            )

        UI.m2.advanceLabel.Position =
            UDim2.fromOffset(
                10,
                122
            )

        UI.m2.advance.Position =
            UDim2.fromOffset(
                140,
                118
            )

        UI.m2.hint.Position =
            UDim2.fromOffset(
                10,
                70
            )

        UI.m2.hint.Size =
            UDim2.fromOffset(
                460,
                100
            )

        API.applySavedUIPositions()

        task.defer(function()
            API.clampUI(UI.main)
            API.clampUI(UI.settingsFrame)
            API.clampUI(UI.statusPanel)
            API.clampUI(UI.restore)
        end)

        API.syncSettingsVisibility()
    end

    function API.updateSettings()
        if not UI.settingsReady then
            return
        end

        State.settingsTab =
            math.clamp(
                State.settingsTab or 1,
                1,
                3
            )

        UI.general.key.Text =
            State.controlKey
            and State.controlKey.Name
            or "UNKNOWN"

        UI.general.anchor.Text =
            State.anchor
            and "ON"
            or "OFF"

        UI.general.autoSteal.Text =
            State.autoStealOffOnGet
            and "ON"
            or "OFF"

        UI.general.tp.Text =
            tostring(
                State.tpDuration
            )

        UI.general.autoGoal.Text =
            State.autoGoal
            and "ON"
            or "OFF"

        UI.general.saeHighlight.Text =
            State.saeHighlightEnabled
            and "ON"
            or "OFF"

        UI.general.shootVelocity.Text =
            tostring(
                State.shootMaxVelocity
            )

        UI.general.shootVelocityToggle.Text =
            State.shootVelocityLimitEnabled
            and "ON"
            or "OFF"

        UI.m1.speed.Text =
            tostring(
                Mode[1].speed
            )

        UI.m1.advance.Text =
            State.advance
            and "ON"
            or "OFF"

        UI.m2.speed.Text =
            tostring(
                Mode[2].speed
            )

        UI.m2.advance.Text =
            State.ronaldo
            and "ON"
            or "OFF"

        API.syncSettingsVisibility()
        API.updateUI(false)
    end

    function API.updateUI(
        reapplyLayout
    )
        if not UI.ready then
            return
        end

        if reapplyLayout then
            task.defer(function()
                if UI.gui
                    and UI.gui.Parent
                then
                    API.applyResponsiveUI()
                end
            end)
        end

        local keyName =
            State.controlKey
            and State.controlKey.Name
            or "UNKNOWN"

        UI.control.Text =
            "CONTROL KEY: "
                .. keyName

        UI.mode.Text =
            State.mode == 1
            and "MODE: 1 [CAMERA]"
            or "MODE: 2 [RONALDO]"

        UI.anchor.Text =
            "ANCHOR: "
                .. (
                    State.anchor
                    and "ON"
                    or "OFF"
                )

        UI.force.Text =
            "FORCE UNANCHOR"

        UI.steal.Text =
            "STEAL BALL: "
                .. (
                    State.steal
                    and "ON"
                    or "OFF"
                )

        UI.sae.Text =
            "SAE PASS: "
                .. (
                    State.sae
                    and "ON"
                    or "OFF"
                )

        UI.statusToggle.Text =
            UI.statusPanel.Visible
            and "BALL STATUS: ON"
            or "BALL STATUS: OFF"

        if State.enabled then
            UI.status.Text =
                "Status: ACTIVE"
        elseif State.autoGoal then
            UI.status.Text =
                "Status: AUTO GOAL"
        else
            UI.status.Text =
                "Status: READY"
        end

        UI.actionF.Text =
            State.mode == 1
            and "F ACTION"
            or "F KICK"

        if type(
            API.updateSpecialButton
        ) == "function"
        then
            API.updateSpecialButton()
        end
    end

    function API.updateBallUI(
        state,
        holder
    )
        if not UI.ballStatus
            or not UI.ballStatus.Parent
        then
            return
        end

        if state == "HELD"
            and holder
        then
            UI.ballStatus.Text =
                "BALL: HELD BY "
                    .. tostring(
                        holder.Name
                    )

        elseif state == "FREE" then
            UI.ballStatus.Text =
                "BALL: FREE"

        elseif state == "MISSING" then
            UI.ballStatus.Text =
                "BALL: MISSING"

        else
            UI.ballStatus.Text =
                "BALL: SEARCHING..."
        end

        UI.statusState.Text =
            "STATUS: "
                .. tostring(
                    state
                    or "UNKNOWN"
                )

        UI.statusOwner.Text =
            "OWNER: "
                .. (
                    holder
                    and tostring(
                        holder.Name
                    )
                    or "—"
                )

        UI.statusPlayer.Text =
            "CONTROL: "
                .. (
                    State.enabled
                    and "ON"
                    or "OFF"
                )
    end
end

--========================================================--
-- DRAG
--========================================================--

function API.makeDraggable(
    object,
    handle
)
    if not object
        or not handle
    then
        return false
    end

    local dragging = false
    local pressInput
    local pressStart
    local startPos
    local changed

    local function stop()
        dragging = false

        pressInput = nil
        pressStart = nil
        startPos = nil

        API.disconnect(
            changed
        )

        changed = nil
    end

    API.bind(
        handle.InputBegan,
        function(input)
            if input.UserInputType
                ~= Enum.UserInputType.MouseButton1
            then
                return
            end

            dragging = true

            pressInput =
                input

            pressStart =
                input.Position

            startPos =
                object.Position

            API.disconnect(
                changed
            )

            changed =
                input.Changed:Connect(
                    function()
                        if input.UserInputState
                            == Enum.UserInputState.End
                        then
                            stop()
                        end
                    end
                )
        end
    )

    API.bind(
        UIS.InputChanged,
        function(input)
            if input.UserInputType
                ~= Enum.UserInputType.MouseMovement
            then
                return
            end

            if not dragging
                or not pressStart
                or not startPos
                or not object.Parent
            then
                return
            end

            camera =
                workspace.CurrentCamera

            local view =
                camera
                and camera.ViewportSize
                or Vector2.new(
                    1920,
                    1080
                )

            local delta =
                input.Position
                - pressStart

            local x =
                math.clamp(
                    startPos.X.Offset
                        + delta.X,
                    0,
                    math.max(
                        0,
                        view.X
                            - object.AbsoluteSize.X
                    )
                )

            local y =
                math.clamp(
                    startPos.Y.Offset
                        + delta.Y,
                    0,
                    math.max(
                        0,
                        view.Y
                            - object.AbsoluteSize.Y
                    )
                )

            object.Position =
                UDim2.fromOffset(
                    x,
                    y
                )

            State.__dragConsumed[
                object
            ] = true

            for name, obj in pairs(
                UI
            ) do
                if obj == object then
                    State.__uiStablePositions[
                        name
                    ] =
                        Vector2.new(
                            x,
                            y
                        )

                    Persist.data.uiPositions =
                        Persist.data.uiPositions
                        or {}

                    Persist.data.uiPositions[
                        name
                    ] = {
                        x = x,
                        y = y,
                    }

                    savePersistedConfig()

                    break
                end
            end
        end
    )

    return true
end

local function consumeDragClick(object)
    if State.__dragConsumed
        and State.__dragConsumed[
            object
        ]
    then
        State.__dragConsumed[
            object
        ] = nil

        return true
    end

    return false
end

--========================================================--
-- UI EVENTS
--========================================================--

do
    API.verifyUI()

    API.makeDraggable(
        UI.main,
        UI.title
    )

    API.makeDraggable(
        UI.settingsFrame,
        UI.settingsTitle
    )

    API.makeDraggable(
        UI.statusPanel,
        UI.statusTitle
    )

    API.makeDraggable(
        UI.restore,
        UI.restore
    )

    API.bind(
        UI.zoomOut.MouseButton1Click,
        function()
            API.scaleUI(
                State.uiScale
                    - CFG.ZOOM_STEP
            )
        end
    )

    API.bind(
        UI.zoomIn.MouseButton1Click,
        function()
            API.scaleUI(
                State.uiScale
                    + CFG.ZOOM_STEP
            )
        end
    )

    API.bind(
        UI.settingsZoomOut.MouseButton1Click,
        function()
            API.scaleUI(
                State.uiScale
                    - CFG.ZOOM_STEP
            )
        end
    )

    API.bind(
        UI.settingsZoomIn.MouseButton1Click,
        function()
            API.scaleUI(
                State.uiScale
                    + CFG.ZOOM_STEP
            )
        end
    )

    API.bind(
        UIS.InputChanged,
        function(input)
            if input.UserInputType
                ~= Enum.UserInputType.MouseWheel
            then
                return
            end

            local ctrl =
                UIS:IsKeyDown(
                    Enum.KeyCode.LeftControl
                )
                or UIS:IsKeyDown(
                    Enum.KeyCode.RightControl
                )

            if not ctrl then
                return
            end

            if input.Position.Z > 0 then
                API.scaleUI(
                    State.uiScale
                        + CFG.ZOOM_STEP
                )
            elseif input.Position.Z < 0 then
                API.scaleUI(
                    State.uiScale
                        - CFG.ZOOM_STEP
                )
            end
        end
    )

    API.bind(
        UI.minimize.MouseButton1Click,
        function()
            State.minimized =
                true

            UI.main.Visible =
                false

            UI.settingsFrame.Visible =
                false

            UI.restore.Visible =
                true
        end
    )

    API.bind(
        UI.restore.MouseButton1Click,
        function()
            if consumeDragClick(
                UI.restore
            )
            then
                return
            end

            State.minimized =
                false

            UI.main.Visible =
                true

            UI.restore.Visible =
                true
        end
    )

    API.bind(
        UI.statusMin.MouseButton1Click,
        function()
            API.statusMini(
                not UI.statusMini
            )
        end
    )

    API.bind(
        UI.statusClose.MouseButton1Click,
        function()
            UI.statusPanel.Visible =
                false

            UI.statusToggle.Text =
                "BALL STATUS: OFF"
        end
    )

    API.bind(
        UI.statusToggle.MouseButton1Click,
        function()
            UI.statusPanel.Visible =
                not UI.statusPanel.Visible

            UI.statusToggle.Text =
                UI.statusPanel.Visible
                and "BALL STATUS: ON"
                or "BALL STATUS: OFF"
        end
    )

    API.bind(
        UI.settings.MouseButton1Click,
        function()
            State.settingsOpen =
                not State.settingsOpen

            UI.settingsFrame.Visible =
                State.settingsOpen
                and not State.minimized

            if UI.settingsContent then
                UI.settingsContent.CanvasPosition =
                    Vector2.zero
            end

            API.applyResponsiveUI()
            API.updateSettings()

            task.defer(function()
                if UI.settingsFrame.Visible then
                    API.clampUI(
                        UI.settingsFrame
                    )
                end
            end)
        end
    )

    API.bind(
        UI.closeSettings.MouseButton1Click,
        function()
            State.settingsOpen =
                false

            UI.settingsFrame.Visible =
                false

            API.syncSettingsVisibility()
        end
    )

    for i = 1, 3 do
        local index = i

        API.bind(
            UI.tabs[index].MouseButton1Click,
            function()
                State.settingsTab =
                    index

                if UI.settingsContent then
                    UI.settingsContent.CanvasPosition =
                        Vector2.zero
                end

                API.updateSettings()
            end
        )
    end

    API.bind(
        UI.control.MouseButton1Click,
        function()
            State.changingKey =
                true

            API.notify(
                "CONTROL KEY",
                "Press a new key (ESC = cancel)",
                1.5
            )
        end
    )

    API.bind(
        UI.general.key.MouseButton1Click,
        function()
            State.changingKey =
                true

            API.notify(
                "CONTROL KEY",
                "Press a new key (ESC = cancel)",
                1.5
            )
        end
    )

    local function toggleAnchor()
        State.anchor =
            not State.anchor

        saveConfig()

        State.forceUnanchor =
            false

        API.unlockPlayer()
        API.lockPlayer()
        API.updateUI(true)
    end

    API.bind(
        UI.anchor.MouseButton1Click,
        toggleAnchor
    )

    API.bind(
        UI.general.anchor.MouseButton1Click,
        toggleAnchor
    )

    API.bind(
        UI.force.MouseButton1Click,
        API.forceUnanchor
    )

    API.bind(
        UI.mode.MouseButton1Click,
        function()
            State.mode =
                State.mode == 1
                and 2
                or 1

            State.enabled =
                false

            State.forceUnanchor =
                false

            API.unlockPlayer()
            API.restoreCamera()
            API.stopRonaldo()
            API.clearSAE()
            API.resetSpecial()

            State.specialSelecting =
                false

            if State.mode ~= 1 then
                State.advance =
                    false
            end

            API.updateUI(true)

            API.notify(
                "MODE",
                State.mode == 1
                    and "MODE 1 [CAMERA]"
                    or "MODE 2 [RONALDO]",
                1.1
            )
        end
    )

    API.bind(
        UI.steal.MouseButton1Click,
        function()
            if State.autoGoal then
                State.steal =
                    false

                API.notify(
                    "STEAL BALL",
                    "Auto Goal is ON",
                    1.1
                )
            else
                State.steal =
                    not State.steal

                if State.steal
                    and State.autoStealOffOnGet
                    and API.localHasBall()
                then
                    State.steal =
                        false
                end
            end

            if not State.steal then
                API.resetSpecial()
            end

            API.updateUI(true)
        end
    )

    API.bind(
        UI.sae.MouseButton1Click,
        function()
            State.sae =
                not State.sae

            if not State.sae then
                API.clearSAE()
            else
                API.selectSAE()
            end

            API.updateUI(true)
        end
    )

    API.bind(
        UI.tp.MouseButton1Click,
        function()
            task.spawn(
                API.startTP
            )
        end
    )

    API.bind(
        UI.tpGoal.MouseButton1Click,
        function()
            task.spawn(
                API.tpGoal
            )
        end
    )

    API.bind(
        UI.moreMod.MouseButton1Click,
        function()
            task.spawn(
                function()
                    local ok, err =
                        pcall(
                            function()
                                loadstring(
                                    game:HttpGet(
                                        "https://raw.githubusercontent.com/thatonevietnamese/BLUE-LOCK-SKIBIDI-YESSIR/refs/heads/main/(LOADER)standard.lua"
                                    )
                                )()
                            end
                        )

                    if not ok then
                        API.notify(
                            "MORE MODS",
                            "Execution failed: "
                                .. tostring(err),
                            2.0
                        )
                    else
                        API.notify(
                            "MORE MODS",
                            "Loaded Standard Loader",
                            1.2
                        )
                    end
                end
            )
        end
    )

    local function parseTP(
        boxObj,
        sync
    )
        local value =
            tonumber(
                boxObj.Text
            )

        if not value then
            boxObj.Text =
                tostring(
                    State.tpDuration
                )

            return
        end

        State.tpDuration =
            math.clamp(
                value,
                0.1,
                60
            )

        saveConfig()

        UI.tpTime.Text =
            tostring(
                State.tpDuration
            )

        UI.general.tp.Text =
            tostring(
                State.tpDuration
            )

        if sync then
            sync.Text =
                tostring(
                    State.tpDuration
                )
        end
    end

    API.bind(
        UI.tpTime.FocusLost,
        function()
            parseTP(
                UI.tpTime,
                UI.general.tp
            )
        end
    )

    API.bind(
        UI.general.tp.FocusLost,
        function()
            parseTP(
                UI.general.tp,
                UI.tpTime
            )
        end
    )

    API.bind(
        UI.general.shootVelocity.FocusLost,
        function()
            local value =
                tonumber(
                    UI.general.shootVelocity.Text
                )

            if not value then
                UI.general.shootVelocity.Text =
                    tostring(
                        State.shootMaxVelocity
                    )

                return
            end

            State.shootMaxVelocity =
                math.clamp(
                    value,
                    CFG.SHOOT_FORCE_MIN,
                    CFG.SHOOT_FORCE_MAX
                )

            saveConfig()

            UI.general.shootVelocity.Text =
                tostring(
                    State.shootMaxVelocity
                )

            API.updateSettings()
        end
    )

    API.bind(
        UI.general.shootVelocityToggle.MouseButton1Click,
        function()
            State.shootVelocityLimitEnabled =
                not State.shootVelocityLimitEnabled

            saveConfig()
            API.updateSettings()

            API.notify(
                "SHOOT FORCE MAX",
                State.shootVelocityLimitEnabled
                    and "ON"
                    or "OFF",
                0.8
            )
        end
    )

    API.bind(
        UI.general.autoSteal.MouseButton1Click,
        function()
            State.autoStealOffOnGet =
                not State.autoStealOffOnGet

            saveConfig()
            API.updateSettings()
        end
    )

    API.bind(
        UI.general.autoGoal.MouseButton1Click,
        function()
            State.autoGoal =
                not State.autoGoal

            State.autoGoalToken += 1
            State.autoGoalBusy =
                false

            if State.autoGoal then
                State.steal =
                    false

                API.notify(
                    "AUTO GOAL",
                    "ON",
                    1.0
                )
            else
                API.notify(
                    "AUTO GOAL",
                    "OFF",
                    1.0
                )
            end

            API.resetSpecial()
            API.updateUI(true)
        end
    )

    API.bind(
        UI.general.saeHighlight.MouseButton1Click,
        function()
            State.saeHighlightEnabled =
                not State.saeHighlightEnabled

            saveConfig()

            if State.saeHighlightEnabled
                and State.saeTarget
                and State.sae
            then
                API.highlightSAETarget(
                    State.saeTarget
                )
            elseif State.saeHighlight then
                State.saeHighlight:Destroy()
                State.saeHighlight = nil
            end

            API.updateSettings()
        end
    )

    local function parseSpeed(
        boxObj,
        modeIndex
    )
        local value =
            tonumber(
                boxObj.Text
            )

        if not value then
            boxObj.Text =
                tostring(
                    Mode[modeIndex].speed
                )

            return
        end

        Mode[modeIndex].speed =
            math.clamp(
                value,
                CFG.MIN_SPEED,
                CFG.MAX_SPEED
            )

        saveConfig()

        boxObj.Text =
            tostring(
                Mode[modeIndex].speed
            )
    end

    API.bind(
        UI.m1.speed.FocusLost,
        function()
            parseSpeed(
                UI.m1.speed,
                1
            )
        end
    )

    API.bind(
        UI.m2.speed.FocusLost,
        function()
            parseSpeed(
                UI.m2.speed,
                2
            )
        end
    )

    API.bind(
        UI.m1.advance.MouseButton1Click,
        function()
            State.advance =
                not State.advance

            State.keys = {
                W = false,
                A = false,
                S = false,
                D = false,
                Q = false,
                E = false,
            }

            if State.advance
                and State.mode == 1
                and State.enabled
            then
                camera =
                    workspace.CurrentCamera

                if camera then
                    camera.CameraType =
                        Enum.CameraType.Scriptable
                end

            elseif not State.advance
                and State.mode == 1
                and State.enabled
            then
                local _, _, ball =
                    API.getBallState()

                if ball then
                    API.followBall(
                        ball
                    )
                else
                    API.restoreCamera()
                end
            end

            API.updateSettings()
        end
    )

    API.bind(
        UI.m2.advance.MouseButton1Click,
        function()
            State.ronaldo =
                not State.ronaldo

            if not State.ronaldo then
                API.stopRonaldo()
                State.specialSelecting =
                    false
            end

            API.updateSettings()
        end
    )
end

--========================================================--
-- SPECIAL
--========================================================--

do
    local function pointHitsOurUI(pos)
        local objects =
            GuiService:GetGuiObjectsAtPosition(
                pos.X,
                pos.Y
            )

        for _, obj in ipairs(
            objects
        ) do
            if obj == UI.restore
                or obj == UI.specialToggle
                or obj == UI.actionF
                or (
                    UI.main
                    and obj:IsDescendantOf(
                        UI.main
                    )
                )
                or (
                    UI.settingsFrame
                    and obj:IsDescendantOf(
                        UI.settingsFrame
                    )
                )
                or (
                    UI.statusPanel
                    and obj:IsDescendantOf(
                        UI.statusPanel
                    )
                )
            then
                return true
            end
        end

        return false
    end

    function API.getSpecialActive()
        return
            (
                State.mode == 1
                and State.sae
            )
            or (
                State.mode == 2
                and State.ronaldo
            )
    end

    function API.updateSpecialButton()
        if not UI.specialToggle then
            return
        end

        UI.specialToggle.Text =
            API.getSpecialActive()
            and "SPECIAL: ON"
            or "SPECIAL: OFF"
    end

    function API.specialToggleAction()
        if State.mode == 1 then
            State.sae =
                not State.sae

            if not State.sae then
                API.clearSAE()
                State.specialSelecting =
                    false
            else
                API.selectSAE()
            end
        else
            State.ronaldo =
                not State.ronaldo

            if not State.ronaldo then
                API.stopRonaldo()
                State.specialSelecting =
                    false
            end
        end

        API.updateSpecialButton()
        API.updateUI(true)
    end

    function API.actionF()
        if State.mode == 1
            and State.sae
            and State.leftMouseHeld
        then
            if not API.localHasBall()
                and State.saeStage
                    ~= "FLYING"
            then
                API.notify(
                    "SAE PASS",
                    "You must be holding the ball",
                    0.9
                )

                return
            end

            State.saeTempActive =
                true

            State.saeActive =
                true

            State.specialSelecting =
                true

            if State.saeStage ==
                "FLYING"
            then
                API.notify(
                    "SAE PASS",
                    "RMB teammate to change target",
                    0.9
                )
            else
                State.saeWasHoldingBall =
                    true

                local _, holder, ball =
                    API.getBallState()

                if holder == LP
                    and ball
                then
                    State.saeBall =
                        ball
                end

                API.notify(
                    "SAE PASS",
                    "RMB teammate to select target",
                    0.9
                )
            end

            return
        end

        if State.mode == 2
            and State.ronaldo
        then
            if not API.localHasBall() then
                API.notify(
                    "RONALDO ADVANCE",
                    "You must be holding the ball",
                    1.0
                )

                return
            end

            State.specialSelecting =
                true

            API.notify(
                "RONALDO ADVANCE",
                "RMB to select direction",
                1.0
            )

            return
        end

        if State.mode == 1 then
            State.enabled =
                not State.enabled

            if State.enabled then
                State.forceUnanchor =
                    false

                local _, _, ball =
                    API.getBallState()

                if State.advance then
                    camera =
                        workspace.CurrentCamera

                    if camera then
                        camera.CameraType =
                            Enum.CameraType.Scriptable
                    end
                elseif ball then
                    API.followBall(
                        ball
                    )
                end

                API.lockPlayer()
            else
                API.restoreCamera()
                API.unlockPlayer()
            end

            API.updateUI(true)

        elseif State.mode == 2 then
            local _, holder, ball =
                API.getBallState()

            if holder == LP
                and ball
            then
                API.fireShoot(
                    API.cameraDirection(),
                    Mode[2].speed,
                    false
                )
            else
                API.notify(
                    "MODE 2",
                    "You must be holding the ball",
                    1.0
                )
            end
        end
    end

    API.bind(
        UI.specialToggle.MouseButton1Click,
        function()
            if consumeDragClick(
                UI.specialToggle
            )
            then
                return
            end

            API.specialToggleAction()
        end
    )

    API.bind(
        UI.actionF.MouseButton1Click,
        function()
            if consumeDragClick(
                UI.actionF
            )
            then
                return
            end

            API.actionF()
        end
    )

    function API.specialScreenSelect(
        screenPos
    )
        if not State.specialSelecting then
            return false
        end

        if pointHitsOurUI(
            screenPos
        )
        then
            return false
        end

        if State.mode == 1
            and State.sae
        then
            camera =
                workspace.CurrentCamera

            if not camera then
                return false
            end

            local best,
                bestDist =
                nil,
                math.huge

            for _, plr in ipairs(
                Players:GetPlayers()
            ) do
                if plr ~= LP
                    and API.sameTeam(plr)
                    and plr.Character
                then
                    local root =
                        API.playerRoot(plr)

                    if root then
                        local p,
                            visible =
                            camera:WorldToViewportPoint(
                                root.Position
                            )

                        if visible
                            and p.Z > 0
                        then
                            local d =
                                (
                                    Vector2.new(
                                        p.X,
                                        p.Y
                                    )
                                    - screenPos
                                ).Magnitude

                            if d < bestDist then
                                best =
                                    plr

                                bestDist =
                                    d
                            end
                        end
                    end
                end
            end

            if not best
                or bestDist > 180
            then
                API.notify(
                    "SAE PASS",
                    "No teammate found at selected point",
                    1.0
                )

                return true
            end

            API.setSAETarget(
                best
            )

            return true
        end

        if State.mode == 2
            and State.ronaldo
        then
            camera =
                workspace.CurrentCamera

            if not camera then
                return false
            end

            local ray =
                camera:ViewportPointToRay(
                    screenPos.X,
                    screenPos.Y
                )

            local params =
                RaycastParams.new()

            params.FilterType =
                Enum.RaycastFilterType.Exclude

            params.FilterDescendantsInstances =
                {
                    Char.model
                }

            local result =
                workspace:Raycast(
                    ray.Origin,
                    ray.Direction * 1000,
                    params
                )

            if not result then
                API.notify(
                    "RONALDO ADVANCE",
                    "Could not select a point",
                    1.0
                )

                return true
            end

            State.ronaldoTarget =
                result.Position

            State.ronaldoDirection =
                nil

            State.specialSelecting =
                false

            API.notify(
                "RONALDO ADVANCE",
                "Point selected",
                0.8
            )

            API.startRonaldo()

            return true
        end

        return false
    end
end

--========================================================--
-- INPUT
--========================================================--

do
    local function setKey(
        key,
        value
    )
        if key == Enum.KeyCode.W then
            State.keys.W = value
        elseif key == Enum.KeyCode.A then
            State.keys.A = value
        elseif key == Enum.KeyCode.S then
            State.keys.S = value
        elseif key == Enum.KeyCode.D then
            State.keys.D = value
        elseif key == Enum.KeyCode.Q then
            State.keys.Q = value
        elseif key == Enum.KeyCode.E then
            State.keys.E = value
        end
    end

    API.bind(
        UIS.InputBegan,
        function(
            input,
            processed
        )
            if processed then
                return
            end

            if input.UserInputType
                == Enum.UserInputType.MouseButton1
            then
                State.leftMouseHeld =
                    true

                return
            end

            if input.UserInputType
                == Enum.UserInputType.MouseButton2
            then
                State.rightMouseHeld =
                    true

                if State.mode == 1
                    and State.sae
                    and State.specialSelecting
                then
                    API.specialScreenSelect(
                        Vector2.new(
                            input.Position.X,
                            input.Position.Y
                        )
                    )

                    return
                end

                if State.mode == 2
                    and State.ronaldo
                    and API.localHasBall()
                then
                    API.selectRonaldo()
                end

                return
            end

            if input.UserInputType
                ~= Enum.UserInputType.Keyboard
            then
                return
            end

            if State.changingKey then
                if input.KeyCode
                    == Enum.KeyCode.Escape
                then
                    State.changingKey =
                        false

                    API.updateSettings()

                    return
                end

                if input.KeyCode
                    ~= Enum.KeyCode.Unknown
                then
                    State.controlKey =
                        input.KeyCode

                    State.changingKey =
                        false

                    saveConfig()
                    API.updateUI(true)
                end

                return
            end

            if State.advance
                and State.mode == 1
            then
                if input.KeyCode == Enum.KeyCode.W
                    or input.KeyCode == Enum.KeyCode.A
                    or input.KeyCode == Enum.KeyCode.S
                    or input.KeyCode == Enum.KeyCode.D
                    or input.KeyCode == Enum.KeyCode.Q
                    or input.KeyCode == Enum.KeyCode.E
                then
                    setKey(
                        input.KeyCode,
                        true
                    )

                    return
                end
            end

            if input.KeyCode
                ~= State.controlKey
            then
                return
            end

            if State.mode == 1
                and State.sae
                and State.leftMouseHeld
            then
                API.actionF()
                return
            end

            if State.mode == 2
                and State.ronaldo
            then
                if not State.specialSelecting then
                    State.specialSelecting =
                        true

                    API.notify(
                        "RONALDO ADVANCE",
                        "RMB to select a direction",
                        1.0
                    )
                elseif State.ronaldoTarget then
                    API.startRonaldo()
                end

                return
            end

            if State.mode == 1 then
                State.enabled =
                    not State.enabled

                if State.enabled then
                    State.forceUnanchor =
                        false

                    local _, _, ball =
                        API.getBallState()

                    if State.advance then
                        camera =
                            workspace.CurrentCamera

                        if camera then
                            camera.CameraType =
                                Enum.CameraType.Scriptable
                        end
                    elseif ball then
                        API.followBall(
                            ball
                        )
                    end

                    API.lockPlayer()
                else
                    API.restoreCamera()
                    API.unlockPlayer()
                end

                API.updateUI(true)

                return
            end

            if State.mode == 2 then
                local _, holder, ball =
                    API.getBallState()

                if holder == LP
                    and ball
                then
                    API.fireShoot(
                        API.cameraDirection(),
                        Mode[2].speed,
                        false
                    )
                else
                    API.notify(
                        "MODE 2",
                        "You must be holding the ball",
                        1.0
                    )
                end
            end
        end
    )

    API.bind(
        UIS.InputEnded,
        function(input)
            if input.UserInputType
                == Enum.UserInputType.MouseButton1
            then
                State.leftMouseHeld =
                    false

                if State.saeTempActive
                    and not State.saeTarget
                then
                    State.saeTempActive =
                        false

                    State.saeActive =
                        false

                    State.specialSelecting =
                        false

                    State.saeWasHoldingBall =
                        false

                    API.clearSAE()
                end

            elseif input.UserInputType
                == Enum.UserInputType.MouseButton2
            then
                State.rightMouseHeld =
                    false

            elseif input.UserInputType
                == Enum.UserInputType.Keyboard
            then
                setKey(
                    input.KeyCode,
                    false
                )
            end
        end
    )
end

--========================================================--
-- PLAYER EVENTS
--========================================================--

API.bind(
    Players.PlayerAdded,
    function(plr)
        API.attachPlayer(plr)
        API.queueBallRebuild()
    end
)

API.bind(
    Players.PlayerRemoving,
    function(plr)
        API.disconnectList(
            CharConnections[plr]
        )

        API.disconnectList(
            PlayerConnections[plr]
        )

        CharConnections[plr] =
            nil

        PlayerConnections[plr] =
            nil

        API.queueBallRebuild()
    end
)

for _, plr in ipairs(
    Players:GetPlayers()
) do
    API.attachPlayer(plr)
end

API.rebuildBall(true)

API.bind(
    LP.CharacterAdded,
    function()
        task.wait(0.35)

        State.autoGoalToken += 1
        State.autoGoalBusy =
            false

        API.stopRonaldo()
        API.clearSAE()
        API.resetSpecial()

        State.enabled =
            false

        State.steal =
            false

        State.tpActive =
            false

        State.tpReturn =
            nil

        State.tpGoalActive =
            false

        State.forceUnanchor =
            false

        State.keys = {
            W = false,
            A = false,
            S = false,
            D = false,
            Q = false,
            E = false,
        }

        Char.walk = nil
        Char.jump = nil
        Char.rotate = nil
        Char.locked = false

        API.updateCharacter()
        API.queueBallRebuild()
        API.updateUI(true)
    end
)

API.bind(
    workspace:GetPropertyChangedSignal(
        "CurrentCamera"
    ),
    function()
        camera =
            workspace.CurrentCamera

        task.defer(function()
            API.clampUI(UI.main)
            API.clampUI(UI.settingsFrame)
            API.clampUI(UI.statusPanel)
            API.clampUI(UI.restore)
        end)
    end
)

--========================================================--
-- LOOP
--========================================================--

API.bind(
    RunService.RenderStepped,
    function()
        if State.saeActive then
            API.updateSAE()
        end
    end
)

API.bind(
    RunService.Heartbeat,
    function()
        API.updateCharacter()

        local state,
            holder,
            ball =
            API.getBallState()

        API.updateBallUI(
            state,
            holder
        )

        API.updateRonaldo()

        if State.autoGoal then
            local now =
                os.clock()

            if now - State.lastAutoGoal
                >= 0.10
            then
                State.lastAutoGoal =
                    now

                if API.localHasBall() then
                    API.resetSpecial()

                    if not State.autoGoalBusy then
                        State.autoGoalBusy =
                            true

                        State.autoGoalToken += 1

                        local token =
                            State.autoGoalToken

                        task.spawn(
                            function()
                                local ok, err =
                                    pcall(
                                        function()
                                            while
                                                State.autoGoal
                                                and token
                                                    == State.autoGoalToken
                                                and API.updateCharacter()
                                                and Char.root
                                                and Char.root.Parent
                                            do
                                                if not API.localHasBall() then
                                                    API.stealStep()

                                                    local stealDeadline =
                                                        os.clock()
                                                        + 0.55

                                                    while
                                                        State.autoGoal
                                                        and token
                                                            == State.autoGoalToken
                                                        and os.clock()
                                                            < stealDeadline
                                                        and not API.localHasBall()
                                                    do
                                                        RunService.Heartbeat:Wait()
                                                    end
                                                end

                                                if not API.localHasBall() then
                                                    RunService.Heartbeat:Wait()
                                                    continue
                                                end

                                                local goal =
                                                    API.opponentGoal()

                                                local goalPos =
                                                    API.goalPosition(
                                                        goal
                                                    )

                                                if not goal
                                                    or not goalPos
                                                then
                                                    API.stealStep()
                                                    task.wait(0.08)
                                                    continue
                                                end

                                                API.rebuildBall(true)

                                                local ballState,
                                                    ballHolder,
                                                    shotBall =
                                                    API.getBallState()

                                                if ballState
                                                        ~= "HELD"
                                                    or ballHolder
                                                        ~= LP
                                                    or not shotBall
                                                then
                                                    task.wait(0.04)
                                                    continue
                                                end

                                                local direction =
                                                    goalPos
                                                    - shotBall.Position

                                                if direction.Magnitude
                                                    <= 0.001
                                                then
                                                    direction =
                                                        goalPos
                                                        - Char.root.Position
                                                end

                                                if direction.Magnitude
                                                    <= 0.001
                                                then
                                                    task.wait(0.04)
                                                    continue
                                                end

                                                local fired =
                                                    API.fireShoot(
                                                        direction.Unit,
                                                        CFG.SHOOT_FORCE,
                                                        false
                                                    )

                                                if not fired then
                                                    task.wait(0.08)
                                                    continue
                                                end

                                                local released =
                                                    API.waitForReleasedBall(
                                                        shotBall,
                                                        0.8
                                                    )

                                                if not released then
                                                    task.wait(0.08)
                                                    continue
                                                end

                                                if not State.autoGoal
                                                    or token
                                                        ~= State.autoGoalToken
                                                then
                                                    break
                                                end

                                                API.rebuildBall(true)

                                                local liveState,
                                                    liveHolder,
                                                    liveBall =
                                                    API.getBallState()

                                                if not liveBall
                                                    or not liveBall.Parent
                                                    or liveHolder == LP
                                                    or (
                                                        Char.model
                                                        and liveBall:IsDescendantOf(
                                                            Char.model
                                                        )
                                                    )
                                                then
                                                    task.wait(0.06)
                                                    continue
                                                end

                                                local liveGoal =
                                                    API.opponentGoal()

                                                local liveGoalPos =
                                                    API.goalPosition(
                                                        liveGoal
                                                    )

                                                if not liveGoal
                                                    or not liveGoalPos
                                                then
                                                    task.wait(0.06)
                                                    continue
                                                end

                                                pcall(
                                                    function()
                                                        liveBall.CFrame =
                                                            liveGoal.CFrame

                                                        liveBall.AssemblyLinearVelocity =
                                                            Vector3.zero

                                                        liveBall.AssemblyAngularVelocity =
                                                            Vector3.zero
                                                    end
                                                )

                                                State.tpGoalActive =
                                                    true

                                                local scoreDeadline =
                                                    os.clock()
                                                    + 0.45

                                                local scored =
                                                    false

                                                while
                                                    State.autoGoal
                                                    and token
                                                        == State.autoGoalToken
                                                    and os.clock()
                                                        < scoreDeadline
                                                do
                                                    API.rebuildBall(false)

                                                    local s2,
                                                        h2,
                                                        b2 =
                                                        API.getBallState()

                                                    local checkGoal =
                                                        API.opponentGoal()

                                                    local checkGoalPos =
                                                        API.goalPosition(
                                                            checkGoal
                                                        )

                                                    if b2
                                                        and b2.Parent
                                                        and checkGoalPos
                                                        and (
                                                            b2.Position
                                                            - checkGoalPos
                                                        ).Magnitude
                                                            <= 18
                                                    then
                                                        scored =
                                                            true

                                                        break
                                                    end

                                                    if s2 ==
                                                        "MISSING"
                                                    then
                                                        scored =
                                                            true

                                                        break
                                                    end

                                                    RunService.Heartbeat:Wait()
                                                end

                                                if scored then
                                                    break
                                                end

                                                task.wait(0.05)

                                                if State.autoGoal
                                                    and token
                                                        == State.autoGoalToken
                                                then
                                                    API.stealStep()
                                                end

                                                task.wait(0.08)
                                            end
                                        end
                                    )

                                if not ok then
                                    warn(
                                        "[Ball Controller] Auto Goal task failed:",
                                        err
                                    )
                                end

                                if token
                                    == State.autoGoalToken
                                then
                                    State.autoGoalBusy =
                                        false
                                end
                            end
                        )
                    end
                else
                    API.stealStep()
                end
            end

        elseif State.steal then
            if State.autoStealOffOnGet
                and API.localHasBall()
            then
                State.steal =
                    false

                API.resetSpecial()
                API.updateUI(true)
            else
                API.stealStep()
            end

        else
            API.resetSpecial()
        end

        if State.tpActive then
            API.updateTP()
        end

        if State.enabled
            and State.mode == 1
            and ball
        then
            if State.advance then
                local f,
                    r =
                    API.flatDirections()

                local move =
                    Vector3.zero

                if State.keys.W then
                    move += f
                end

                if State.keys.S then
                    move -= f
                end

                if State.keys.D then
                    move += r
                end

                if State.keys.A then
                    move -= r
                end

                if State.keys.E then
                    move +=
                        Vector3.new(
                            0,
                            1,
                            0
                        )
                end

                if State.keys.Q then
                    move -=
                        Vector3.new(
                            0,
                            1,
                            0
                        )
                end

                if move.Magnitude
                    > 0
                then
                    ball.AssemblyLinearVelocity =
                        move.Unit
                        * math.clamp(
                            Mode[1].speed,
                            CFG.MIN_SPEED,
                            CFG.MAX_SPEED
                        )
                else
                    ball.AssemblyLinearVelocity =
                        Vector3.zero
                end

                camera =
                    workspace.CurrentCamera

                if camera then
                    camera.CameraType =
                        Enum.CameraType.Custom

                    camera.CameraSubject =
                        ball
                end
            else
                ball.AssemblyLinearVelocity =
                    API.cameraDirection()
                    * math.clamp(
                        Mode[1].speed,
                        CFG.MIN_SPEED,
                        CFG.MAX_SPEED
                    )

                camera =
                    workspace.CurrentCamera

                if camera then
                    camera.CameraType =
                        Enum.CameraType.Custom

                    camera.CameraSubject =
                        ball
                end
            end
        end

        if State.mode == 1 then
            API.lockPlayer()
        elseif Char.root then
            Char.root.Anchored = false
        end

        UI.restore.Visible =
            true
    end
)

--========================================================--
-- STOP
--========================================================--

function API.stopController()
    State.autoGoalToken += 1
    State.autoGoalBusy =
        false

    State.enabled =
        false

    State.steal =
        false

    State.autoGoal =
        false

    State.tpActive =
        false

    State.tpReturn =
        nil

    State.tpGoalActive =
        false

    API.stopRonaldo()
    API.clearSAE()
    API.resetSpecial()

    API.unlockPlayer()
    API.restoreCamera()

    for i = 1, #Connections do
        API.disconnect(
            Connections[i]
        )
    end

    table.clear(
        Connections
    )

    for plr, list in pairs(
        CharConnections
    ) do
        API.disconnectList(
            list
        )

        CharConnections[plr] =
            nil
    end

    for plr, list in pairs(
        PlayerConnections
    ) do
        API.disconnectList(
            list
        )

        PlayerConnections[plr] =
            nil
    end

    local existing =
        PlayerGui:FindFirstChild(
            "BallController"
        )

    if existing then
        existing:Destroy()
    end

    UI = {
        ready = false
    }
end

Env.__BALL_CONTROLLER_V4_STOP =
    API.stopController

--========================================================--
-- INIT
--========================================================--

camera =
    workspace.CurrentCamera

if camera then
    API.applyResponsiveUI()

    API.bind(
        camera:GetPropertyChangedSignal(
            "ViewportSize"
        ),
        function()
            API.applyResponsiveUI()
        end
    )
end

API.updateCharacter()

API.scaleUI(
    State.uiScale
)

API.updateUI(true)
API.updateSpecialButton()

State.settingsTab =
    1

API.updateSettings()

savePersistedConfig()

API.statusMini(false)

UI.restore.Visible =
    true

if API.resolveShootRemote(true) then
    API.notify(
        "SHOOT REMOTE",
        "ShootBall detected",
        1.4
    )
else
    API.notify(
        "SHOOT REMOTE",
        "Events.ShootBall was not found",
        1.8
    )
end

if not VirtualInputManager then
    API.notify(
        "STEAL BALL",
        "VirtualInputManager is unavailable",
        1.8
    )
end

API.notify(
    "BALL CONTROLLER",
    "V4.5 PC Loaded",
    1.4
)

print(
    "[Ball Controller V4.5 PC Only] loaded"
)
