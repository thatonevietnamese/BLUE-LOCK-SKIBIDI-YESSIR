--========================================================--
-- BALL CONTROLLER V4.5
-- Robust UI bootstrap / scoped / cleanup-safe
--========================================================--

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local VirtualInputManager = game:GetService("VirtualInputManager")

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
    [1] = {speed = 60},
    [2] = {speed = 140},
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

    ronaldo = false,
    ronaldoTarget = nil,
    ronaldoBall = nil,
    ronaldoActive = false,
    ronaldoTouch = nil,
    ronaldoStart = 0,
    ronaldoDirection = nil,

    advance = false,
    keys = {W=false,A=false,S=false,D=false,Q=false,E=false},

    changingKey = false,
    minimized = false,
    settingsOpen = false,
    uiScale = 1,
    moreModOpen = false,
    moreMods = {antiShake=false, antiBlur=false, trajectory=false, autoJoin=false, cooldownTracker=false},

    autoStealOffOnGet = true,

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

local UI = {
    ready = false,
}

local Connections = {}
local CharConnections = {}
local PlayerConnections = {}

local API = {}

local camera = workspace.CurrentCamera

--========================================================--
-- ENV / GENERIC
--========================================================--

local function getEnv()
    local env
    pcall(function()
        env = getgenv()
    end)
    return env or _G
end

local Env = getEnv()

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

        Char.humanoid = Char.model:FindFirstChildOfClass("Humanoid")
        Char.root = Char.model:FindFirstChild("HumanoidRootPart")

        return Char.humanoid ~= nil and Char.root ~= nil
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
            Char.walk, Char.jump, Char.rotate = nil, nil, nil
            return
        end

        if Char.locked then
            if Char.walk ~= nil then
                Char.humanoid.WalkSpeed = Char.walk
            end
            if Char.jump ~= nil then
                Char.humanoid.JumpPower = Char.jump
            end
            if Char.rotate ~= nil then
                Char.humanoid.AutoRotate = Char.rotate
            end
        end

        if Char.root then
            Char.root.Anchored = false
        end

        Char.locked = false
        Char.walk, Char.jump, Char.rotate = nil, nil, nil
    end

    function API.forceUnanchor()
        State.forceUnanchor = true
        API.unlockPlayer()
        API.notify("ANCHOR", "Force Unanchor executed", 1.4)
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
    title.TextColor3 = Color3.new(1,1,1)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card

    local body = Instance.new("TextLabel")
    body.Size = UDim2.new(1, -18, 0, 25)
    body.Position = UDim2.fromOffset(9, 27)
    body.BackgroundTransparency = 1
    body.Text = tostring(bodyText)
    body.Font = Enum.Font.Gotham
    body.TextSize = 11
    body.TextColor3 = Color3.fromRGB(175,175,185)
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.Parent = card

    TweenService:Create(
        card,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad),
        {Position = UDim2.new(0.5,0,0,8)}
    ):Play()

    task.delay(duration, function()
        if not card.Parent then
            return
        end

        TweenService:Create(
            card,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad),
            {Position = UDim2.new(0.5,0,0,-65)}
        ):Play()

        task.delay(0.22, function()
            if card.Parent then
                card:Destroy()
            end
        end)
    end)
end

--========================================================--
-- BALL TRACKER
--========================================================--

do
    local function matchPlayer(plr)
        if not plr or not plr.Team then
            return false
        end

        local n = string.lower(plr.Team.Name)
        return string.find(n, "home", 1, true) ~= nil
            or string.find(n, "away", 1, true) ~= nil
    end

    local function ballInCharacter(char)
        if not char then
            return nil
        end

        local ball = char:FindFirstChild(CFG.BALL_NAME, true)
        return ball and ball:IsA("BasePart") and ball or nil
    end

    local function freeBall()
        local direct = workspace:FindFirstChild(CFG.BALL_NAME)
        if direct and direct:IsA("BasePart") then
            return direct
        end

        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart")
                and string.lower(obj.Name) == string.lower(CFG.BALL_NAME)
            then
                if not Char.model or not obj:IsDescendantOf(Char.model) then
                    return obj
                end
            end
        end

        return nil
    end

    function API.rebuildBall(force)
        local now = os.clock()

        if not force
            and now - Tracker.last < CFG.CACHE_INTERVAL
        then
            return Tracker.state, Tracker.holder, Tracker.ball
        end

        Tracker.last = now
        Tracker.queued = false
        Tracker.state = "UNKNOWN"
        Tracker.holder = nil
        Tracker.ball = nil

        for _, plr in ipairs(Players:GetPlayers()) do
            if matchPlayer(plr) then
                local ball = ballInCharacter(plr.Character)
                if ball then
                    Tracker.state = "HELD"
                    Tracker.holder = plr
                    Tracker.ball = ball
                    return "HELD", plr, ball
                end
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
        local state, holder, ball =
            Tracker.state,
            Tracker.holder,
            Tracker.ball

        if state == "HELD" then
            if not holder or not holder.Parent or not holder.Character then
                return API.rebuildBall(false)
            end

            if not ball or not ball.Parent
                or not ball:IsDescendantOf(holder.Character)
            then
                return API.rebuildBall(false)
            end

            return state, holder, ball
        end

        if state == "FREE" then
            if ball and ball.Parent then
                return state, nil, ball
            end
            return API.rebuildBall(false)
        end

        if state == "MISSING" then
            return API.rebuildBall(false)
        end

        return API.rebuildBall(false)
    end

    function API.localHasBall()
        local state, holder = API.getBallState()
        return state == "HELD" and holder == LP
    end

    function API.playerRoot(plr)
        if not plr or not plr.Character then
            return nil
        end

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
            if obj == Tracker.ball then
                API.queueBallRebuild()
            end
        end)

        API.bindLocal(list, char.AncestryChanged, function(_, parent)
            if parent == nil then
                API.queueBallRebuild()
            end
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

--========================================================--
-- REMOTE
--========================================================--

do
    local remote
    local remoteReady = false
    local lastResolve = 0

    function API.resolveShootRemote(force)
        local now = os.clock()

        if not force and now - lastResolve < 0.25 then
            return remote
        end

        lastResolve = now

        local events = ReplicatedStorage:FindFirstChild("Events")
        remote = events and events:FindFirstChild("ShootBall")
        remoteReady = remote and remote:IsA("RemoteEvent") or false

        return remote
    end

    function API.fireShoot(direction, force, third)
        if not remoteReady or not remote then
            API.resolveShootRemote(true)
        end

        if not remoteReady or not remote then
            API.notify("SHOOT REMOTE", "Events.ShootBall chưa tìm thấy", 1.5)
            return false
        end

        if typeof(direction) ~= "Vector3"
            or direction.Magnitude < 0.001
        then
            return false
        end

        local ok = pcall(function()
            remote:FireServer(
                direction.Unit,
                math.clamp(
                    tonumber(force) or CFG.MIN_SPEED,
                    CFG.MIN_SPEED,
                    CFG.MAX_SPEED
                ),
                third == nil and false or third
            )
        end)

        return ok
    end

    API.resolveShootRemote(true)
end

--========================================================--
-- CAMERA
--========================================================--

do
    function API.saveCamera(subject)
        camera = workspace.CurrentCamera
        if not camera then
            return
        end

        if CameraState.type == nil then
            CameraState.type = camera.CameraType
        end

        if CameraState.subject == nil
            and camera.CameraSubject ~= subject
        then
            CameraState.subject = camera.CameraSubject
        end
    end

    function API.followBall(ball)
        if not ball then
            return
        end

        camera = workspace.CurrentCamera
        if not camera then
            return
        end

        API.saveCamera(ball)
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = ball
    end

    function API.restoreCamera()
        camera = workspace.CurrentCamera
        if not camera then
            return
        end

        API.updateCharacter()

        camera.CameraType = CameraState.type or Enum.CameraType.Custom

        if Char.humanoid and Char.humanoid.Parent then
            camera.CameraSubject = Char.humanoid
        elseif CameraState.subject and CameraState.subject.Parent then
            camera.CameraSubject = CameraState.subject
        end

        CameraState.type = nil
        CameraState.subject = nil
    end

    function API.cameraDirection()
        camera = workspace.CurrentCamera
        if not camera then
            return Vector3.new(0,0,-1)
        end

        local v = camera.CFrame.LookVector
        return v.Magnitude > 0 and v.Unit or Vector3.new(0,0,-1)
    end

    function API.flatDirections()
        camera = workspace.CurrentCamera
        if not camera then
            return Vector3.new(0,0,-1), Vector3.new(1,0,0)
        end

        local f = Vector3.new(
            camera.CFrame.LookVector.X, 0,
            camera.CFrame.LookVector.Z
        )

        local r = Vector3.new(
            camera.CFrame.RightVector.X, 0,
            camera.CFrame.RightVector.Z
        )

        if f.Magnitude > 0 then
            f = f.Unit
        end

        if r.Magnitude > 0 then
            r = r.Unit
        end

        return f, r
    end
end

--========================================================--
-- GOAL / ROLE
--========================================================--

do
    function API.characterName()
        local values = LP:FindFirstChild("Values")
        local obj = values and values:FindFirstChild("CharacterName")

        if not obj or obj.Value == nil then
            return ""
        end

        return string.lower(
            string.gsub(tostring(obj.Value), "%s+", "")
        )
    end

    function API.roleName()
        local role = LP:FindFirstChild("Role")
        if role and role.Value ~= nil then
            return string.lower(tostring(role.Value))
        end

        local values = LP:FindFirstChild("Values")
        local obj = values and values:FindFirstChild("Role")

        if obj and obj.Value ~= nil then
            return string.lower(tostring(obj.Value))
        end

        if Char.model then
            local obj2 = Char.model:FindFirstChild("Role")
            if obj2 and obj2.Value ~= nil then
                return string.lower(tostring(obj2.Value))
            end
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
        if not map then
            return nil
        end

        local model = map:FindFirstChild(
            homeSide and "PlayerOneGoal" or "PlayerTwoGoal"
        )

        if not model then
            return nil
        end

        local score =
            model:FindFirstChild("ScoreHitbox")
            or model:FindFirstChild("Score")

        if score and score:IsA("BasePart") then
            return score
        end

        local hitbox = model:FindFirstChild("ScoreHitbox", true)
        if hitbox and hitbox:IsA("BasePart") then
            return hitbox
        end

        return model:FindFirstChildWhichIsA("BasePart", true)
    end

    function API.goalArea(homeSide)
        local obj = workspace:FindFirstChild(
            homeSide and "PlayerOneGoalArea"
                or "PlayerTwoGoalArea"
        )

        if not obj then
            return nil
        end

        if obj:IsA("BasePart") then
            return obj
        end

        if obj:IsA("Model") then
            return obj.PrimaryPart
                or obj:FindFirstChildWhichIsA("BasePart", true)
        end

        return nil
    end

    function API.ownGoal()
        local home = API.isHome()
        return API.goalArea(home) or API.goalHitbox(home)
    end

    function API.opponentGoal()
        return API.goalHitbox(not API.isHome())
    end

    function API.inGoal(pos, goal)
        return pos and goal
            and (pos - goal.Position).Magnitude <= 18
    end
end

--========================================================--
-- ABILITIES / SPECIAL STEAL
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
                offset = Vector3.new(0,5.5,0),
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
                offset = Vector3.new(0,5.5,0),
            },
        },

        naoya = {
            canSlide = true,
            canSlideTeammate = false,
            special = {
                name = "NAOYA 2 -> 3",
                mode = "OPPONENT",
                interval = 0.16,
                offset = Vector3.new(0,5.5,0),
                steps = {
                    {key = Enum.KeyCode.Two, waitPossession = true},
                    {key = Enum.KeyCode.Three, finish = true},
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
                offset = Vector3.new(0,5.5,0),
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
                offset = Vector3.new(0,5.5,0),
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
                offset = Vector3.new(0,5.5,0),
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
                offset = Vector3.new(0,5.5,0),
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
                offset = Vector3.new(0,5.5,0),
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
                offset = Vector3.new(0,5.5,0),
            },
        },
    }

    function API.ability()
        return Abilities[API.characterName()] or Abilities.default
    end

    function API.resetSpecial()
        State.special.active = false
        State.special.target = nil
        State.special.step = 1
        State.special.nextAt = 0
        State.special.character = ""
    end

    local function targetForSpecial(special)
        local state, holder = API.getBallState()
        if state ~= "HELD" or not holder or holder == LP then
            return nil
        end

        local teammate = API.sameTeam(holder)
        local mode = special.mode or "OPPONENT"

        if mode == "OPPONENT" and teammate then
            return nil
        end

        if mode == "TEAMMATE" and not teammate then
            return nil
        end

        if mode == "ANY"
            and teammate
            and not special.allowTeammate
        then
            return nil
        end

        local root = API.playerRoot(holder)
        return root and root.Parent and holder or nil
    end

    local function specialStillValid(target)
        if not target or not target.Parent then
            return false
        end

        local state, holder = API.getBallState()
        return state == "HELD" and holder == target
    end

    local function tpUse(target, keyCode, offset)
        local root = API.playerRoot(target)
        if not root or not root.Parent then
            return false
        end

        if not API.updateCharacter()
            or not Char.root
            or not Char.root.Parent
        then
            return false
        end

        offset = offset or Vector3.new(0,5.5,0)

        Char.root.CFrame = CFrame.new(
            root.Position + offset,
            root.Position
        )

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

        if State.special.active
            and State.special.character ~= charName
        then
            API.resetSpecial()
        end

        local now = os.clock()

        if not State.special.active then
            local target = targetForSpecial(special)

            if not target then
                return false
            end

            State.special.active = true
            State.special.target = target
            State.special.step = 1
            State.special.nextAt = now
            State.special.character = charName
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

            if now < State.special.nextAt then
                return true
            end

            if not specialStillValid(target)
                and not API.localHasBall()
            then
                API.resetSpecial()
                return false
            end

            local used = tpUse(
                target,
                step.key,
                step.offset or special.offset
            )

            if not used then
                API.resetSpecial()
                return false
            end

            State.special.nextAt =
                now + (step.interval or special.interval or CFG.SPECIAL_INTERVAL)

            if step.finish then
                API.resetSpecial()
            end

            return true
        end

        if now < State.special.nextAt then
            return true
        end

        if not special.oneShot
            and not specialStillValid(target)
        then
            API.resetSpecial()
            return false
        end

        local used = tpUse(
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
                now + (special.interval or CFG.SPECIAL_INTERVAL)
        end

        return true
    end

    function API.normalStealTarget()
        local ability = API.ability()
        if not ability.canSlide then
            return nil
        end

        local state = Tracker.state
        local holder = Tracker.holder
        local ball = Tracker.ball

        if state == "HELD" and holder then
            if holder == LP then
                return nil
            end

            if API.sameTeam(holder)
                and not ability.canSlideTeammate
            then
                return nil
            end

            return API.playerRoot(holder)
        end

        if state == "FREE" and ball and ball.Parent then
            return ball
        end

        return nil
    end

    function API.sendKey(keyCode)
        if not VirtualInputManager then
            return false
        end

        local ok = pcall(function()
            VirtualInputManager:SendKeyEvent(
                true,
                keyCode,
                false,
                game
            )

            task.delay(0.03, function()
                pcall(function()
                    VirtualInputManager:SendKeyEvent(
                        false,
                        keyCode,
                        false,
                        game
                    )
                end)
            end)
        end)

        return ok
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

        local now = os.clock()

        if now - State.lastSteal < CFG.STEAL_INTERVAL then
            return
        end

        if API.specialSteal() then
            State.lastSteal = now
            return
        end

        local target = API.normalStealTarget()

        if not target or not target.Parent then
            return
        end

        State.lastSteal = now

        if API.isGK() then
            local goal = API.ownGoal()
            if goal then
                Char.root.CFrame = CFrame.new(
                    goal.Position + CFG.GK_OFFSET
                )
                API.sendKey(Enum.KeyCode.Q)
            end
        end

        Char.root.CFrame = CFrame.new(
            target.Position + Vector3.new(
                0,
                CFG.STEAL_DISTANCE,
                0
            )
        )

        API.sendKey(Enum.KeyCode.E)
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

        local saved = State.tpReturn

        State.tpActive = false
        State.tpReturn = nil
        State.tpGoalActive = false

        if saved
            and API.updateCharacter()
            and Char.root
            and Char.root.Parent
        then
            Char.root.CFrame = saved
        end

        if reason then
            API.notify("TP RETURN", reason, 1.2)
        end
    end

    local function currentBallTarget()
        local state, holder, ball = API.getBallState()

        if state == "HELD"
            and holder
            and holder ~= LP
        then
            return API.playerRoot(holder), holder
        end

        if state == "FREE" and ball and ball.Parent then
            return ball, nil
        end

        return nil, nil
    end

    function API.startTP()
        if State.tpActive then
            API.restoreTP("Returned")
            return
        end

        if not API.updateCharacter() or not Char.root then
            API.notify("TP RETURN", "Không tìm thấy nhân vật", 1.2)
            return
        end

        State.tpReturn = Char.root.CFrame

        if API.isGK() then
            local goal = API.ownGoal()
            if goal then
                if not API.inGoal(Char.root.Position, goal) then
                    Char.root.CFrame = CFrame.new(goal.Position + CFG.GK_OFFSET)
                end

                task.wait(0.15)
                API.sendKey(Enum.KeyCode.Q)

                local root = select(1, currentBallTarget())
                if root and root.Parent then
                    Char.root.CFrame = CFrame.new(
                        root.Position + Vector3.new(0, CFG.STEAL_DISTANCE, 0)
                    )
                end

                State.tpActive = true
                State.tpStarted = os.clock()
                API.notify("GK RETURN", "Q -> TP -> follow ball", 1.2)
                return
            end
        end

        local state, holder, ball = API.getBallState()
        local pos
        local name

        if state == "HELD" and holder and holder ~= LP then
            local root = API.playerRoot(holder)
            if root then
                pos = root.Position + Vector3.new(0, CFG.STEAL_DISTANCE, 0)
                name = holder.Name
            end
        elseif state == "FREE" and ball then
            pos = ball.Position + Vector3.new(0, CFG.STEAL_DISTANCE, 0)
            name = "FREE BALL"
        end

        if not pos then
            State.tpReturn = nil
            API.notify("TP RETURN", "Không có bóng hợp lệ để TP", 1.2)
            return
        end

        State.tpActive = true
        State.tpStarted = os.clock()
        Char.root.CFrame = CFrame.new(pos)

        API.notify(
            "TP RETURN",
            string.format("TP -> %s trong %.2fs", name, State.tpDuration),
            1.3
        )
    end

    function API.updateTP()
        if not State.tpActive then
            return
        end

        if not API.updateCharacter() or not Char.root then
            return
        end

        if API.localHasBall() then
            API.restoreTP("Đã nhặt bóng -> quay về")
            return
        end

        local root = select(1, currentBallTarget())

        if root and root.Parent then
            Char.root.CFrame = CFrame.new(
                root.Position + Vector3.new(0, CFG.STEAL_DISTANCE, 0)
            )
        end

        if os.clock() - State.tpStarted >= State.tpDuration then
            API.restoreTP("TP timer expired")
        end
    end

    function API.tpGoal()
        local goal = API.opponentGoal()
        if not goal then
            API.notify("TP GOAL", "Không tìm thấy ScoreHitbox đối diện", 1.2)
            return
        end

        local state, holder, ball = API.getBallState()
        if not ball then
            API.notify("TP GOAL", "Không tìm thấy bóng", 1.2)
            return
        end

        -- Nếu đang cầm bóng: đưa PLAYER ra trước goal rồi thực sự sút.
        if state == "HELD" and holder == LP then
            if not API.updateCharacter() or not Char.root then
                return
            end

            local saved = Char.root.CFrame
            Char.root.CFrame = CFrame.new(
                goal.Position + CFG.GOAL_OFFSET,
                goal.Position
            )

            task.wait(0.025)

            local direction = goal.Position - Char.root.Position
            if direction.Magnitude > 0.001 then
                API.fireShoot(direction.Unit, CFG.SHOOT_FORCE, false)
            end

            task.wait(0.025)
            Char.root.CFrame = saved

            -- Một số game giữ ownership thêm vài frame; nếu bóng đã free thì
            -- có thể hoàn tất bằng TP bóng như cơ chế TP GOAL cũ.
            local s2, _, b2 = API.getBallState()
            if s2 == "FREE" and b2 and b2.Parent then
                pcall(function()
                    b2.CFrame = goal.CFrame
                    b2.AssemblyLinearVelocity = Vector3.zero
                    b2.AssemblyAngularVelocity = Vector3.zero
                end)
            end

            State.tpGoalActive = true
            API.notify("TP GOAL", "Sút -> goal", 1.1)
            return
        end

        -- Không cầm bóng: giữ đúng TP GOAL cũ, đưa ball thẳng tới goal.
        pcall(function()
            ball.CFrame = goal.CFrame
            ball.AssemblyLinearVelocity = Vector3.zero
            ball.AssemblyAngularVelocity = Vector3.zero
        end)

        State.tpGoalActive = true
        API.notify("TP GOAL", "Bóng -> đối diện", 1.1)
    end
end

--========================================================--
-- BALL RELEASE / SHOT HELPERS
--========================================================--
do
    function API.waitBallReleased(ball, timeout)
        timeout = timeout or 0.20
        local deadline = os.clock() + timeout

        while os.clock() < deadline do
            if not ball or not ball.Parent then
                return false
            end

            if not Char.model
                or not ball:IsDescendantOf(Char.model)
            then
                return true
            end

            RunService.Heartbeat:Wait()
        end

        return ball
            and ball.Parent
            and (
                not Char.model
                or not ball:IsDescendantOf(Char.model)
            )
    end

    function API.getBallAfterRelease(ball)
        if ball and ball.Parent
            and Char.model
            and not ball:IsDescendantOf(Char.model)
        then
            return ball
        end

        local _, _, current = API.getBallState()
        if current and current.Parent
            and (
                not Char.model
                or not current:IsDescendantOf(Char.model)
            )
        then
            return current
        end

        return nil
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

        API.disconnect(State.ronaldoTouch)
        State.ronaldoTouch = nil
    end

    function API.mouseTarget()
        camera = workspace.CurrentCamera
        if not camera then
            return nil
        end

        local m = UIS:GetMouseLocation()
        local ray = camera:ViewportPointToRay(m.X, m.Y)

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {Char.model}

        local result = workspace:Raycast(
            ray.Origin,
            ray.Direction * 1000,
            params
        )

        return result and result.Position or nil
    end

    function API.selectRonaldo()
        if State.mode ~= 2 or not State.ronaldo then
            return
        end

        if not API.localHasBall() then
            API.notify("RONALDO ADVANCE", "Cần đang cầm bóng", 1.1)
            return
        end

        local pos = API.mouseTarget()
        if not pos then
            API.notify("RONALDO ADVANCE", "Không chọn được vị trí", 1.1)
            return
        end

        State.ronaldoTarget = pos
        State.ronaldoDirection = nil
        API.notify("RONALDO ADVANCE", "Đã chọn hướng", 0.9)
    end

    function API.startRonaldo()
        if not State.ronaldo
            or not State.ronaldoTarget
        then
            return
        end

        if not API.localHasBall() then
            API.stopRonaldo()
            API.notify("RONALDO ADVANCE", "Cần đang cầm bóng", 1.1)
            return
        end

        local _, _, ball = API.getBallState()
        if not ball then
            return
        end

        local delta = State.ronaldoTarget - ball.Position
        if delta.Magnitude < 0.1 then
            API.stopRonaldo()
            return
        end

        -- Lock the selected point into a direction vector.
        State.ronaldoDirection = delta.Unit

        -- 1. Shoot first so the ball is released from the character.
        if not API.fireShoot(
            delta.Unit,
            Mode[2].speed,
            false
        ) then
            return
        end

        -- 2. Wait until the ball is no longer held by the character.
        if not API.waitBallReleased(ball, 0.20) then
            API.stopRonaldo()
            return
        end

        local releasedBall = API.getBallAfterRelease(ball)
        if not releasedBall then
            -- The game may replace the held ball instance on release.
            local _, _, current = API.getBallState()
            releasedBall = current
        end
        if not releasedBall or not releasedBall.Parent then
            API.stopRonaldo()
            return
        end

        API.disconnect(State.ronaldoTouch)

        -- 3. Only now start Advance velocity control.
        State.ronaldoActive = true
        State.ronaldoBall = releasedBall
        State.ronaldoStart = os.clock() + 0.02

        -- Do not stop on Touched: Advance is supposed to keep controlling
        -- the ball until it reaches the user-selected point.
        State.ronaldoTouch = nil
    end

    function API.updateRonaldo()
        if not State.ronaldoActive then
            return
        end

        local ball = State.ronaldoBall
        local target = State.ronaldoTarget

        if not ball or not ball.Parent or not target then
            API.stopRonaldo()
            return
        end

        -- Ball must already be released. While it is still held, wait rather
        -- than cancelling the Advance state.
        if Char.model and ball:IsDescendantOf(Char.model) then
            return
        end

        -- The selected point defines a DIRECTION, not a destination.
        -- Keep the same direction continuously after the ball reaches/passes
        -- the clicked point instead of stopping there.
        local direction = State.ronaldoDirection
        if not direction or direction.Magnitude < 0.001 then
            direction = target - ball.Position
            if direction.Magnitude < 0.001 then
                return
            end
            State.ronaldoDirection = direction.Unit
        end

        local speed = math.clamp(Mode[2].speed, CFG.MIN_SPEED, CFG.MAX_SPEED)
        ball.AssemblyLinearVelocity = direction.Unit * speed
    end
end

--========================================================--
-- SAE
--========================================================--

do
    function API.clearSAE()
        State.saeActive = false
        State.saeTarget = nil
        State.saeBall = nil
        State.saeStage = "IDLE"

        if State.saeHighlight then
            State.saeHighlight:Destroy()
            State.saeHighlight = nil
        end
    end

    local function closestTeammate()
        camera = workspace.CurrentCamera
        if not camera then
            return nil
        end

        local mouse = UIS:GetMouseLocation()
        local best, distBest = nil, math.huge

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP
                and API.sameTeam(plr)
                and plr.Character
            then
                local root = API.playerRoot(plr)
                if root then
                    local point, visible =
                        camera:WorldToViewportPoint(root.Position)

                    if visible and point.Z > 0 then
                        local d = (
                            Vector2.new(point.X, point.Y)
                            - mouse
                        ).Magnitude

                        if d < distBest then
                            distBest = d
                            best = plr
                        end
                    end
                end
            end
        end

        return best
    end

    function API.selectSAE()
        if not State.sae then
            return
        end

        local target = closestTeammate()
        if not target then
            API.notify("SAE PASS", "Không tìm thấy đồng đội", 1.1)
            return
        end

        if State.saeHighlight then
            State.saeHighlight:Destroy()
        end

        local hl = Instance.new("Highlight")
        hl.Name = "SaePassTarget"
        hl.FillColor = Color3.fromRGB(0,255,120)
        hl.FillTransparency = 0.4
        hl.OutlineColor = Color3.new(1,1,1)
        hl.Adornee = target.Character
        hl.Parent = target.Character

        State.saeHighlight = hl
        State.saeTarget = target
        State.saeActive = true
        State.saeStage = API.localHasBall() and "WAIT_RELEASE" or "STICK"

        local _, _, ball = API.getBallState()
        State.saeBall = ball

        API.notify(
            "SAE PASS",
            API.localHasBall()
                and ("Đã khóa "..target.Name.." - chờ nhả bóng")
                or ("Bóng sẽ dính vào "..target.Name),
            1.2
        )
    end

    function API.updateSAE()
        if not State.sae or not State.saeActive or not State.saeTarget then
            return
        end

        local target = State.saeTarget

        if not target.Parent or not target.Character then
            API.clearSAE()
            return
        end

        if API.localHasBall() then
            State.saeStage = "WAIT_RELEASE"
            return
        end

        local state, holder = API.getBallState()

        if state == "HELD" and holder then
            if holder == target then
                API.notify("SAE PASS", "Pass thành công", 0.8)
            end

            API.clearSAE()
            return
        end

        local root = API.playerRoot(target)
        if not root then
            return
        end

        local ball = State.saeBall

        if not ball or not ball.Parent then
            local _, _, current = API.getBallState()
            ball = current
            State.saeBall = current
        end

        if not ball then
            return
        end

        State.saeStage = "STICK"

        pcall(function()
            ball.AssemblyLinearVelocity = Vector3.zero
            ball.AssemblyAngularVelocity = Vector3.zero
            ball.CFrame = root.CFrame * CFrame.new(0,-1.5,-1)
        end)
    end
end

--========================================================--
-- UI
--========================================================--

do
    local function corner(parent, radius)
        local x = Instance.new("UICorner")
        x.CornerRadius = UDim.new(0, radius or 8)
        x.Parent = parent
    end

    local function button(parent, text, x, y, w, h)
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

    local function label(parent, text, x, y, w, h, size)
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

    local function box(parent, value, x, y, w, h)
        local b = Instance.new("TextBox")
        b.Size = UDim2.fromOffset(w,h)
        b.Position = UDim2.fromOffset(x,y)
        b.BackgroundColor3 = Color3.fromRGB(40,40,47)
        b.BorderSizePixel = 0
        b.Text = tostring(value)
        b.TextColor3 = Color3.new(1,1,1)
        b.TextSize = 12
        b.Font = Enum.Font.GothamMedium
        b.ClearTextOnFocus = false
        b.Parent = parent
        corner(b,7)
        return b
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BallController"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = PlayerGui

    UI.gui = gui

    -- Main
    UI.main = Instance.new("Frame")
    UI.main.Size = UDim2.fromOffset(350,445)
    UI.main.Position = UDim2.fromOffset(25,220)
    UI.main.BackgroundColor3 = Color3.fromRGB(24,24,29)
    UI.main.BorderSizePixel = 0
    UI.main.Parent = gui
    corner(UI.main,12)

    UI.title = label(UI.main,"⚽ BALL CONTROLLER V4.5",10,5,240,35,18)
    UI.title.Font = Enum.Font.GothamBold

    UI.zoomOut = button(UI.main,"-",228,10,26,28)
    UI.zoomOut.TextSize = 18

    UI.zoomIn = button(UI.main,"+",256,10,26,28)
    UI.zoomIn.TextSize = 18

    UI.minimize = button(UI.main,"—",312,10,28,28)
    UI.minimize.TextSize = 18

    UI.mainScale = Instance.new("UIScale")
    UI.mainScale.Parent = UI.main

    UI.status = label(UI.main,"Status: READY",10,42,320,22,13)
    UI.ballStatus = label(UI.main,"BALL: SEARCHING...",10,64,320,22,12)

    UI.control = button(UI.main,"CONTROL KEY: F",10,92,160,36)
    UI.mode = button(UI.main,"MODE: 1 [CAMERA]",180,92,160,36)
    UI.anchor = button(UI.main,"ANCHOR: ON",10,136,160,36)
    UI.force = button(UI.main,"FORCE UNANCHOR",180,136,160,36)
    UI.steal = button(UI.main,"STEAL BALL: OFF",10,180,160,36)
    UI.sae = button(UI.main,"SAE PASS: OFF",180,180,160,36)
    UI.settings = button(UI.main,"⚙ SETTINGS",10,224,160,36)
    UI.statusToggle = button(UI.main,"BALL STATUS: ON",180,224,160,36)
    UI.tp = button(UI.main,"TP RETURN",10,268,150,36)
    UI.tpGoal = button(UI.main,"TP GOAL",170,268,170,36)
    UI.moreMod = button(UI.main,"MORE MOD",10,310,160,36)
    UI.tpTime = box(UI.main,State.tpDuration,180,310,160,36)

    UI.info = label(
        UI.main,
        "F = action theo mode.\n"
        .. "Mode 1: camera control.\n"
        .. "Mode 2: Ronaldo kick.\n"
        .. "RMB logo = center UI.\n"
        .. "TP Return/GK = follow bóng.",
        10,350,330,75,11
    )
    UI.info.TextWrapped = true
    UI.info.TextYAlignment = Enum.TextYAlignment.Top
    UI.info.TextColor3 = Color3.fromRGB(145,145,155)

    -- Restore button
    UI.restore = button(gui,"⚽",18,78,48,48)
    UI.restore.TextSize = 23
    corner(UI.restore,24)

    -- Notification holder
    UI.notificationHolder = Instance.new("Frame")
    UI.notificationHolder.Size = UDim2.fromOffset(320,300)
    UI.notificationHolder.AnchorPoint = Vector2.new(0.5,0)
    UI.notificationHolder.Position = UDim2.new(0.5,0,0,0)
    UI.notificationHolder.BackgroundTransparency = 1
    UI.notificationHolder.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0,7)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Top
    layout.Parent = UI.notificationHolder

    -- Status
    UI.statusPanel = Instance.new("Frame")
    UI.statusPanel.Size = UDim2.fromOffset(245,125)
    UI.statusPanel.Position = UDim2.fromOffset(390,80)
    UI.statusPanel.BackgroundColor3 = Color3.fromRGB(22,22,27)
    UI.statusPanel.BorderSizePixel = 0
    UI.statusPanel.Parent = gui
    corner(UI.statusPanel,10)

    UI.statusScale = Instance.new("UIScale")
    UI.statusScale.Parent = UI.statusPanel

    UI.statusTitle = label(UI.statusPanel,"⚽ BALL STATUS",10,5,170,25,14)
    UI.statusTitle.Font = Enum.Font.GothamBold
    UI.statusMin = button(UI.statusPanel,"—",180,6,25,23)
    UI.statusClose = button(UI.statusPanel,"×",210,6,25,23)
    UI.statusState = label(UI.statusPanel,"STATUS: SEARCHING",10,35,220,22,12)
    UI.statusOwner = label(UI.statusPanel,"OWNER: —",10,58,220,22,12)
    UI.statusPlayer = label(UI.statusPanel,"CONTROL: OFF",10,81,220,22,12)

    UI.statusMini = false
    UI.statusFull = UDim2.fromOffset(245,125)
    UI.statusSmall = UDim2.fromOffset(245,34)

    -- More Mod
    UI.moreModFrame = Instance.new("Frame")
    UI.moreModFrame.Size = UDim2.fromOffset(430,370)
    UI.moreModFrame.Position = UDim2.fromOffset(390,280)
    UI.moreModFrame.BackgroundColor3 = Color3.fromRGB(22,22,27)
    UI.moreModFrame.BorderSizePixel = 0
    UI.moreModFrame.Visible = false
    UI.moreModFrame.Parent = gui
    corner(UI.moreModFrame,12)
    UI.moreModScale = Instance.new("UIScale")
    UI.moreModScale.Parent = UI.moreModFrame
    UI.moreModTitle = label(UI.moreModFrame,"MORE MOD",12,8,250,32,17)
    UI.moreModTitle.Font = Enum.Font.GothamBold
    UI.moreModClose = button(UI.moreModFrame,"X",390,8,28,28)
    UI.moreModHint = label(UI.moreModFrame,"Visual / utility mods. Không đụng Auto Goal / Steal / SAE / Ronaldo.",12,45,406,42,11)
    UI.moreModHint.TextWrapped = true
    UI.moreModAntiShake = button(UI.moreModFrame,"ANTI SCREEN SHAKE: OFF",12,94,196,36)
    UI.moreModAntiBlur = button(UI.moreModFrame,"ANTI BLUR: OFF",222,94,196,36)
    UI.moreModTrajectory = button(UI.moreModFrame,"BALL TRAJECTORY: OFF",12,138,196,36)
    UI.moreModCharacter = button(UI.moreModFrame,"DISPLAY CHARACTER [ACTION]",222,138,196,36)
    UI.moreModTrajectoryReset = button(UI.moreModFrame,"REFRESH TRAJECTORY",12,182,196,36)
    UI.moreModAutoJoin = button(UI.moreModFrame,"AUTO JOIN TEAM: OFF",222,182,196,36)
    UI.moreModCooldown = button(UI.moreModFrame,"COOLDOWN TRACKER: OFF",12,226,196,36)
    UI.moreModStatus = label(UI.moreModFrame,"STATUS: READY",12,274,406,22,11)
    UI.moreModStatus.TextColor3 = Color3.fromRGB(150,150,160)

    -- Settings
    UI.settingsFrame = Instance.new("Frame")
    UI.settingsFrame.Size = UDim2.fromOffset(490,320)
    UI.settingsFrame.Position = UDim2.fromOffset(390,240)
    UI.settingsFrame.BackgroundColor3 = Color3.fromRGB(22,22,27)
    UI.settingsFrame.BorderSizePixel = 0
    UI.settingsFrame.Visible = false
    UI.settingsFrame.Parent = gui
    corner(UI.settingsFrame,12)

    UI.settingsScale = Instance.new("UIScale")
    UI.settingsScale.Parent = UI.settingsFrame

    UI.settingsTitle = label(UI.settingsFrame,"⚙ BALL SETTINGS",12,8,270,32,17)
    UI.settingsTitle.Font = Enum.Font.GothamBold

    -- fixed, non-overlapping
    UI.settingsZoomOut = button(UI.settingsFrame,"-",378,8,26,28)
    UI.settingsZoomIn = button(UI.settingsFrame,"+",406,8,26,28)
    UI.closeSettings = button(UI.settingsFrame,"X",454,8,28,28)

    UI.tabs = {
        button(UI.settingsFrame,"GENERAL",10,48,104,30),
        button(UI.settingsFrame,"MODE 1",120,48,104,30),
        button(UI.settingsFrame,"MODE 2",230,48,104,30),
    }

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1,-20,1,-90)
    content.Position = UDim2.fromOffset(10,88)
    content.BackgroundTransparency = 1
    content.Parent = UI.settingsFrame

    UI.general = {}

    UI.general.title = label(content,"GENERAL SETTINGS",10,8,220,24,13)
    UI.general.title.Font = Enum.Font.GothamBold
    UI.general.keyLabel = label(content,"CONTROL KEY",10,38,110,25,12)
    UI.general.key = button(content,"F",120,34,120,32)
    UI.general.anchorLabel = label(content,"ANCHOR",10,78,110,25,12)
    UI.general.anchor = button(content,"ON",120,74,120,32)
    UI.general.autoStealLabel = label(content,"AUTO STEAL OFF",10,118,110,25,12)
    UI.general.autoSteal = button(content,"ON",120,114,120,32)
    UI.general.tpLabel = label(content,"TP RETURN TIME",10,158,110,25,12)
    UI.general.tp = box(content,State.tpDuration,120,154,120,32)
    UI.general.autoGoalLabel = label(content,"AUTO GOAL",10,198,110,25,12)
    UI.general.autoGoal = button(content,"OFF",120,194,120,32)

    UI.general.hint = label(
        content,
        "Auto Goal tự cướp bóng và ghi bàn. TP Return/GK follow bóng.",
        255,38,215,175,11
    )
    UI.general.hint.TextWrapped = true
    UI.general.hint.TextYAlignment = Enum.TextYAlignment.Top

    UI.m1 = {}
    UI.m1.speedLabel = label(content,"SPEED",10,10,110,25,12)
    UI.m1.speed = box(content,Mode[1].speed,120,6,220,32)
    UI.m1.advanceLabel = label(content,"ADVANCE MODE",10,120,110,25,12)
    UI.m1.advance = button(content,"OFF",120,116,120,32)
    UI.m1.hint = label(content,"WASD di chuyển bóng; Q/E đổi độ cao.",10,70,440,100,11)
    UI.m1.hint.TextWrapped = true

    UI.m2 = {}
    UI.m2.speedLabel = label(content,"SPEED",10,10,110,25,12)
    UI.m2.speed = box(content,Mode[2].speed,120,6,220,32)
    UI.m2.advanceLabel = label(content,"RONALDO ADVANCE",10,122,120,25,12)
    UI.m2.advance = button(content,"OFF",140,118,120,32)
    UI.m2.hint = label(content,"RMB chọn điểm, F để sút bóng tới điểm đó.",10,70,440,100,11)
    UI.m2.hint.TextWrapped = true

    UI.settingsReady = true
end

--========================================================--
-- UI FUNCTIONS
--========================================================--

do
    local tab = 1
    local cache = {}

    local function must(name, value)
        if value == nil then
            error("Ball Controller UI init failed: " .. name)
        end
    end

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
            {"moreModFrame", UI.moreModFrame},
            {"moreModTitle", UI.moreModTitle},
            {"moreModClose", UI.moreModClose},
            {"moreModAntiShake", UI.moreModAntiShake},
            {"moreModAntiBlur", UI.moreModAntiBlur},
            {"moreModTrajectory", UI.moreModTrajectory},
            {"moreModCharacter", UI.moreModCharacter},
            {"moreModTrajectoryReset", UI.moreModTrajectoryReset},
            {"moreModAutoJoin", UI.moreModAutoJoin},
            {"moreModCooldown", UI.moreModCooldown},

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
        }

        for i = 1, #required do
            must(required[i][1], required[i][2])
        end

        UI.ready = true
        return true
    end

    function API.clampUI(frame)
        camera = workspace.CurrentCamera
        if not camera or not frame or not frame.Parent then
            return
        end

        local viewport = camera.ViewportSize
        local size = frame.AbsoluteSize

        local x = math.clamp(
            frame.AbsolutePosition.X,
            0,
            math.max(0, viewport.X - size.X)
        )

        local y = math.clamp(
            frame.AbsolutePosition.Y,
            0,
            math.max(0, viewport.Y - size.Y)
        )

        frame.Position = UDim2.fromOffset(x,y)
    end

    function API.scaleUI(value)
        value = math.clamp(
            math.floor(value * 100 + 0.5) / 100,
            CFG.ZOOM_MIN,
            CFG.ZOOM_MAX
        )

        State.uiScale = value

        UI.mainScale.Scale = value
        UI.settingsScale.Scale = value
        UI.statusScale.Scale = value
        if UI.moreModScale then UI.moreModScale.Scale = value end

        task.defer(function()
            API.clampUI(UI.main)
            API.clampUI(UI.settingsFrame)
            API.clampUI(UI.statusPanel)
            API.clampUI(UI.moreModFrame)
        end)
    end

    function API.centerUI()
        camera = workspace.CurrentCamera
        if not camera then
            return
        end

        local view = camera.ViewportSize

        UI.main.Position = UDim2.fromOffset(
            math.max(0, (view.X - UI.main.AbsoluteSize.X)/2),
            math.max(0, (view.Y - UI.main.AbsoluteSize.Y)/2)
        )

        if State.settingsOpen and UI.settingsFrame.Visible then
            API.clampUI(UI.settingsFrame)
        end
        if State.moreModOpen and UI.moreModFrame.Visible then
            API.clampUI(UI.moreModFrame)
        end
    end

    function API.statusMini(value)
        UI.statusMini = value
        UI.statusPanel.Size =
            value and UI.statusSmall or UI.statusFull

        UI.statusState.Visible = not value
        UI.statusOwner.Visible = not value
        UI.statusPlayer.Visible = not value

        UI.statusMin.Text = value and "+" or "—"
        task.defer(function()
            API.clampUI(UI.statusPanel)
        end)
    end

    function API.updateSettings()
        UI.general.key.Text = State.controlKey.Name
        UI.general.anchor.Text = State.anchor and "ON" or "OFF"
        UI.general.autoSteal.Text =
            State.autoStealOffOnGet and "ON" or "OFF"
        UI.general.autoGoal.Text =
            State.autoGoal and "ON" or "OFF"
        UI.general.tp.Text = tostring(State.tpDuration)
        UI.m1.speed.Text = tostring(Mode[1].speed)
        UI.m1.advance.Text = State.advance and "ON" or "OFF"
        UI.m2.speed.Text = tostring(Mode[2].speed)
        UI.m2.advance.Text = State.ronaldo and "ON" or "OFF"

        local tab = State.settingsTab
        local general = tab == 1
        local m1 = tab == 2
        local m2 = tab == 3

        local function visible(obj, value)
            obj.Visible = value
        end

        for _, key in ipairs({
            "title","keyLabel","key","anchorLabel","anchor",
            "autoStealLabel","autoSteal","tpLabel","tp",
            "autoGoalLabel","autoGoal","hint"
        }) do
            visible(UI.general[key], general)
        end

        for _, key in ipairs({
            "speedLabel","speed","advanceLabel","advance","hint"
        }) do
            visible(UI.m1[key], m1)
            visible(UI.m2[key], m2)
        end

        for i = 1, 3 do
            UI.tabs[i].TextColor3 = (i == tab)
                and Color3.fromRGB(100,255,255)
                or Color3.fromRGB(235,235,240)
        end
    end

    function API.updateUI(force)
        if not force
            and cache.enabled == State.enabled
            and cache.mode == State.mode
            and cache.key == State.controlKey
            and cache.steal == State.steal
            and cache.sae == State.sae
            and cache.anchor == State.anchor
            and cache.autoGoal == State.autoGoal
        then
            return
        end

        cache.enabled = State.enabled
        cache.mode = State.mode
        cache.key = State.controlKey
        cache.steal = State.steal
        cache.sae = State.sae
        cache.anchor = State.anchor
        cache.autoGoal = State.autoGoal

        UI.control.Text = "CONTROL KEY: " .. State.controlKey.Name
        UI.mode.Text = State.mode == 1 and "MODE: 1 [CAMERA]" or "MODE: 2 [RONALDO]"
        UI.status.Text = State.enabled and "Status: ACTIVE" or "Status: READY"

        UI.status.TextColor3 =
            State.enabled
            and Color3.fromRGB(100,255,130)
            or Color3.fromRGB(255,205,100)

        UI.steal.Text = State.steal and "STEAL BALL: ON" or "STEAL BALL: OFF"
        UI.sae.Text = State.sae and "SAE PASS: ON" or "SAE PASS: OFF"
        UI.anchor.Text = State.anchor and "ANCHOR: ON" or "ANCHOR: OFF"
        UI.moreModAntiShake.Text = "ANTI SCREEN SHAKE: "..(State.moreMods.antiShake and "ON" or "OFF")
        UI.moreModAntiBlur.Text = "ANTI BLUR: "..(State.moreMods.antiBlur and "ON" or "OFF")
        UI.moreModTrajectory.Text = "BALL TRAJECTORY: "..(State.moreMods.trajectory and "ON" or "OFF")
        UI.moreModAutoJoin.Text = "AUTO JOIN TEAM: "..(State.moreMods.autoJoin and "ON" or "OFF")
        UI.moreModCooldown.Text = "COOLDOWN TRACKER: "..(State.moreMods.cooldownTracker and "ON" or "OFF")

        API.updateSettings()
    end

    function API.updateBallUI(state, holder)
        if state == "HELD" and holder then
            UI.ballStatus.Text = "BALL: HELD - " .. holder.Name
            UI.statusState.Text = "STATUS: HELD"
            UI.statusOwner.Text = "OWNER: " .. holder.Name

            UI.statusState.TextColor3 =
                holder == LP
                and Color3.fromRGB(100,255,255)
                or (
                    API.sameTeam(holder)
                    and Color3.fromRGB(100,255,130)
                    or Color3.fromRGB(255,100,100)
                )
        elseif state == "FREE" then
            UI.ballStatus.Text = "BALL: FREE"
            UI.statusState.Text = "STATUS: FREE"
            UI.statusOwner.Text = "OWNER: NONE"
            UI.statusState.TextColor3 = Color3.fromRGB(255,215,100)
        else
            UI.ballStatus.Text = "BALL: NOT FOUND"
            UI.statusState.Text = "STATUS: NOT FOUND"
            UI.statusOwner.Text = "OWNER: —"
            UI.statusState.TextColor3 = Color3.fromRGB(255,100,100)
        end

        UI.statusPlayer.Text = "CONTROL: " .. (State.enabled and "ACTIVE" or "OFF")
        UI.statusPlayer.TextColor3 =
            State.enabled
            and Color3.fromRGB(100,255,130)
            or Color3.fromRGB(180,180,190)
    end

    function API.makeDraggable(object, handle)
        local dragging = false
        local startMouse = nil
        local startObject = nil
        local changed = nil

        API.bind(handle.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end

            dragging = true
            startMouse = input.Position
            startObject = object.AbsolutePosition

            API.disconnect(changed)

            changed = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    API.disconnect(changed)
                    changed = nil
                end
            end)
        end)

        API.bind(UIS.InputChanged, function(input)
            if not dragging
                or input.UserInputType ~= Enum.UserInputType.MouseMovement
            then
                return
            end

            camera = workspace.CurrentCamera
            local view = camera and camera.ViewportSize or Vector2.new(1920,1080)

            local delta = input.Position - startMouse
            local x = math.clamp(
                startObject.X + delta.X,
                0,
                math.max(0, view.X - object.AbsoluteSize.X)
            )
            local y = math.clamp(
                startObject.Y + delta.Y,
                0,
                math.max(0, view.Y - object.AbsoluteSize.Y)
            )

            object.Position = UDim2.fromOffset(x,y)
        end)
    end
end

--========================================================--
-- MORE MODS
--========================================================--

do
    local M = {moreConnections={}, blurCache={}, blurConnections={}, charConnections={}, charSetup={}}
    local Traj = {
        enabled=false, time=6, step=0.03, width=0.35, bounces=4, elasticity=0.75,
        showArrow=true, minSpeed=2, arrowScale=0.12, minArrow=3, maxArrow=90, arrowWidth=0.55,
        smoothing=0.25, sample=0.06, color=Color3.fromRGB(0,255,238), points={},
        ball=nil, lastBall=nil, lastBallCheck=0, holder=nil, heldBall=nil, lastHolderCheck=0,
        lastPos=nil, lastTime=0, velocity=Vector3.zero, smooth=Vector3.zero, heldDir=Vector3.zero,
        heldSpeed=0, lastVel=0, filteredBall=nil, filteredCount=0, filterTime=0, filterDirty=true,
        attachments={}, beams={}, arrow0=nil, arrow1=nil, arrowBeam=nil, ray=nil, forceRefresh=false
    }
    Traj.ray=RaycastParams.new(); Traj.ray.FilterType=Enum.RaycastFilterType.Exclude; Traj.ray.RespectCanCollide=true

    local function dcon(c) if c then pcall(function() c:Disconnect() end) end end
    local function setStatus(t) if UI.moreModStatus then UI.moreModStatus.Text="STATUS: "..t end end
    local function addc(sig,fn) local c=sig:Connect(fn); M.moreConnections[#M.moreConnections+1]=c; return c end

    -- Anti-shake
    function M.antiShake(on)
        local ok,mod=pcall(function() return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CameraShaker")) end)
        if not ok or not mod then setStatus("CameraShaker not found"); return false end
        if not M.shakeOriginals then M.shakeOriginals={Update=mod.Update,Shake=mod.Shake,ShakeOnce=mod.ShakeOnce,StartShake=mod.StartShake,ShakeSustain=mod.ShakeSustain} end
        if on then
            mod.Update=function(self,dt) if self._camShakeInstances then table.clear(self._camShakeInstances) end; if self._removeInstances then table.clear(self._removeInstances) end; return CFrame.new() end
            mod.Shake=function() end; mod.ShakeOnce=function() end; mod.StartShake=function() end; mod.ShakeSustain=function() end
            setStatus("Anti Screen Shake ON")
        else
            local o=M.shakeOriginals; if o then mod.Update=o.Update; mod.Shake=o.Shake; mod.ShakeOnce=o.ShakeOnce; mod.StartShake=o.StartShake; mod.ShakeSustain=o.ShakeSustain end
            setStatus("Anti Screen Shake OFF")
        end
        return true
    end

    -- Anti-blur
    local targetNames={Blindness=true,ScreenEffectsGUI=true,BlackBars=true,FadeGUI=true,Vignette=true}
    local function rememberUI(o)
        if M.blurCache[o] then return end
        if o:IsA("ScreenGui") then M.blurCache[o]={kind="sg",enabled=o.Enabled}
        elseif o:IsA("GuiObject") then M.blurCache[o]={kind="gui",visible=o.Visible,bg=o.BackgroundTransparency,image=(o:IsA("ImageLabel") or o:IsA("ImageButton")) and o.ImageTransparency or nil} end
    end
    local function killUI(o)
        if not targetNames[o.Name] then return end; rememberUI(o)
        local e=M.blurCache[o]; if not e then return end
        if e.kind=="sg" then o.Enabled=false else o.Visible=false; o.BackgroundTransparency=1; if e.image~=nil then o.ImageTransparency=1 end end
    end
    local function killEffect(o)
        if not (o:IsA("BlurEffect") or o:IsA("ColorCorrectionEffect") or o:IsA("DepthOfFieldEffect")) then return end
        if not M.blurCache[o] then M.blurCache[o]={kind="fx",enabled=o.Enabled} end
        o.Enabled=false
    end
    function M.antiBlur(on)
        for _,c in ipairs(M.blurConnections) do dcon(c) end; table.clear(M.blurConnections)
        if on then
            for _,o in ipairs(PlayerGui:GetDescendants()) do killUI(o) end
            for _,o in ipairs(Lighting:GetChildren()) do killEffect(o) end
            M.blurConnections[#M.blurConnections+1]=PlayerGui.DescendantAdded:Connect(killUI)
            M.blurConnections[#M.blurConnections+1]=Lighting.ChildAdded:Connect(killEffect)
            setStatus("Anti Blur ON")
        else
            for o,e in pairs(M.blurCache) do if o and o.Parent then pcall(function()
                if e.kind=="sg" then o.Enabled=e.enabled elseif e.kind=="gui" then o.Visible=e.visible; o.BackgroundTransparency=e.bg; if e.image~=nil then o.ImageTransparency=e.image end elseif e.kind=="fx" then o.Enabled=e.enabled end
            end) end end
            table.clear(M.blurCache); setStatus("Anti Blur OFF")
        end
        return true
    end

    local function getVisualFolder()
        local folder=workspace:FindFirstChild("TrajectoryVisuals")
        if not folder then
            folder=Instance.new("Folder")
            folder.Name="TrajectoryVisuals"
            folder.Parent=workspace
        end
        return folder
    end

    local function clearTraj()
        for _,b in pairs(Traj.beams) do if b and b.Parent then b.Enabled=false end end
        for _,a in pairs(Traj.attachments) do if a and a.Parent then a.WorldPosition=Vector3.new(0,-10000,0) end end
        if Traj.arrowBeam and Traj.arrowBeam.Parent then Traj.arrowBeam.Enabled=false end
        table.clear(Traj.points); Traj.lastBall=nil; Traj.lastPos=nil; Traj.velocity=Vector3.zero; Traj.smooth=Vector3.zero; Traj.holder=nil; Traj.heldBall=nil; Traj.lastHolderCheck=0; Traj.lastBallCheck=0; Traj.filterDirty=true
    end
    local function getBall()
        local state, holder, ball = API.getBallState()
        if state == "HELD" and ball and ball.Parent then
            Traj.ball = ball
            Traj.holder = holder
            Traj.heldBall = ball
            return ball
        elseif state == "FREE" and ball and ball.Parent then
            Traj.ball = ball
            Traj.holder = nil
            Traj.heldBall = nil
            return ball
        end
        if Traj.ball and Traj.ball.Parent and Traj.ball:IsA("BasePart") then return Traj.ball end
        local now=os.clock()
        if now-Traj.lastBallCheck<0.05 then return nil end
        Traj.lastBallCheck=now
        for _,n in ipairs({"Ball","SoccerBall","Football","TPSBall","TpsBall"}) do
            local b=workspace:FindFirstChild(n,true)
            if b and b:IsA("BasePart") then Traj.ball=b; return b end
        end
        return nil
    end
    local function getHolder()
        local state, holder, ball = API.getBallState()
        if state == "HELD" and holder and ball and ball.Parent then
            Traj.holder=holder; Traj.heldBall=ball
            return holder,ball
        end
        return nil,nil
    end
    local function unit(v) return v.Magnitude>0.001 and v.Unit or Vector3.zero end
    local function hDir(p) local r=p and p.Character and p.Character:FindFirstChild("HumanoidRootPart"); if not r then return Vector3.zero end; return unit(Vector3.new(r.CFrame.LookVector.X,0,r.CFrame.LookVector.Z)) end
    local function updateMove(b,h)
        local now=os.clock(); if Traj.lastBall~=b then Traj.lastBall=b; Traj.lastPos=b.Position; Traj.lastTime=now; Traj.velocity=Vector3.zero; Traj.smooth=Vector3.zero; end
        if h then
            Traj.heldDir=hDir(h); local r=h.Character and h.Character:FindFirstChild("HumanoidRootPart"); local sp=r and Vector3.new(r.AssemblyLinearVelocity.X,0,r.AssemblyLinearVelocity.Z).Magnitude or 0; if sp>0 then Traj.heldSpeed=sp end; Traj.smooth=Traj.heldDir*math.max(Traj.heldSpeed,1); Traj.lastPos=b.Position; Traj.lastTime=now; return
        end
        if not Traj.lastPos then
            Traj.lastPos=b.Position; Traj.lastTime=now
            local av=b.AssemblyLinearVelocity
            if av.Magnitude>0.001 then
                Traj.velocity=av
                local hv=Vector3.new(av.X,0,av.Z)
                Traj.smooth=hv
            end
            return
        end
        if now-Traj.lastVel<Traj.sample then return end
        local dt=now-Traj.lastTime; if dt<=0 then return end; local v=(b.Position-Traj.lastPos)/dt; Traj.velocity=v; local hv=Vector3.new(v.X,0,v.Z); if hv.Magnitude>Traj.minSpeed then Traj.smooth=Traj.smooth:Lerp(hv,Traj.smoothing) else Traj.smooth=Traj.smooth:Lerp(Vector3.zero,Traj.smoothing) end; Traj.lastPos=b.Position; Traj.lastTime=now; Traj.lastVel=now
    end
    local function updateFilter(b)
        local now=os.clock(); local cnt=#Players:GetPlayers(); if not Traj.filterDirty and b==Traj.filteredBall and cnt==Traj.filteredCount and now-Traj.filterTime<0.5 then return end
        Traj.filterDirty=false; Traj.filterTime=now; Traj.filteredBall=b; Traj.filteredCount=cnt; local list={getVisualFolder(),b}; for _,p in ipairs(Players:GetPlayers()) do if p.Character then list[#list+1]=p.Character end end; Traj.ray.FilterDescendantsInstances=list
    end
    local function predict(b)
        table.clear(Traj.points); local h=Traj.holder; local v=h and (hDir(h)*math.max(Traj.heldSpeed,1)) or Traj.velocity; if (not h) and v.Magnitude<1.2 and b and b:IsA("BasePart") then v=b.AssemblyLinearVelocity end; if v.Magnitude<1.2 then return -1 end
        local pos=b.Position; local g=Vector3.new(0,-workspace.Gravity,0); local total=0; local bounce=0; local first=-1; table.insert(Traj.points,pos)
        while total<Traj.time and bounce<Traj.bounces do
            local dt=Traj.step; local nxt=pos+v*dt+0.5*g*(dt^2); local delta=nxt-pos; local hit=workspace:Raycast(pos,delta,Traj.ray)
            if hit then bounce+=1; table.insert(Traj.points,hit.Position); if bounce==1 then first=#Traj.points end; local frac=delta.Magnitude>0 and (hit.Position-pos).Magnitude/delta.Magnitude or 1; local iv=v+g*(dt*frac); v=(iv-2*iv:Dot(hit.Normal)*hit.Normal)*Traj.elasticity; pos=hit.Position+hit.Normal*0.08; total+=dt*frac; if v.Magnitude<1.5 then break end else pos=nxt; v+=g*dt; total+=dt; table.insert(Traj.points,pos) end
        end
        if bounce==0 and #Traj.points>0 then local d=workspace:Raycast(Traj.points[#Traj.points],Vector3.new(0,-500,0),Traj.ray); if d then table.insert(Traj.points,d.Position); first=#Traj.points end end
        return first
    end
    local function beam(i)
        local folder=getVisualFolder(); if not Traj.attachments[i] then local a=Instance.new("Attachment"); a.Name="MoreModAtt_"..i; a.Parent=folder; Traj.attachments[i]=a end; if i>1 and not Traj.beams[i-1] then local b=Instance.new("Beam"); b.Name="MoreModBeam_"..(i-1); b.Parent=folder; Traj.beams[i-1]=b end; local bm=Traj.beams[i-1]; if bm then bm.Attachment0=Traj.attachments[i-1]; bm.Attachment1=Traj.attachments[i]; bm.Color=ColorSequence.new(Traj.color); bm.Width0=Traj.width; bm.Width1=Traj.width; bm.FaceCamera=true; bm.Enabled=true end
    end
    local function renderTraj()
        if not Traj.enabled then clearTraj(); return end; if Traj.forceRefresh then Traj.lastBallCheck=0; Traj.lastHolderCheck=0; Traj.lastBall=nil; Traj.lastPos=nil; Traj.lastTime=0; Traj.lastVel=0; Traj.filterDirty=true; Traj.forceRefresh=false end; local b=getBall(); local h,hb=getHolder(); Traj.holder=h; if not b then b=hb; Traj.ball=b end; if not b then clearTraj(); return end; updateMove(b,h); updateFilter(b); local first=predict(b); if #Traj.points==0 then clearTraj(); return end; local maxI=first>0 and first or #Traj.points; if maxI < 2 then clearTraj(); return end; local bi=1; for i=1,maxI do beam(bi); Traj.attachments[bi].WorldPosition=Traj.points[i]; bi+=1 end; for i=bi,#Traj.attachments do Traj.attachments[i].WorldPosition=Vector3.new(0,-10000,0); local x=Traj.beams[i-1]; if x then x.Enabled=false end end
        if not Traj.showArrow then if Traj.arrowBeam then Traj.arrowBeam.Enabled=false end; return end
        if not Traj.arrowBeam then local f=getVisualFolder(); Traj.arrow0=Instance.new("Attachment"); Traj.arrow1=Instance.new("Attachment"); Traj.arrowBeam=Instance.new("Beam"); Traj.arrow0.Parent=f; Traj.arrow1.Parent=f; Traj.arrowBeam.Parent=f; Traj.arrowBeam.Attachment0=Traj.arrow0; Traj.arrowBeam.Attachment1=Traj.arrow1; Traj.arrowBeam.FaceCamera=true end
        local mv=Traj.smooth; local hv=Vector3.new(mv.X,0,mv.Z); local sp=hv.Magnitude; if h then hv=hDir(h)*math.max(Traj.heldSpeed,Traj.minSpeed); sp=math.max(Traj.heldSpeed,Traj.minSpeed) end
        if sp<Traj.minSpeed then Traj.arrowBeam.Enabled=false else local dir=hv.Unit; local len=math.clamp(sp*Traj.arrowScale,Traj.minArrow,Traj.maxArrow); Traj.arrow0.WorldPosition=b.Position; Traj.arrow1.WorldPosition=b.Position+dir*len; Traj.arrowBeam.Width0=Traj.arrowWidth; Traj.arrowBeam.Width1=Traj.arrowWidth*0.55; Traj.arrowBeam.Color=ColorSequence.new(Traj.color); Traj.arrowBeam.Enabled=true end
    end

    -- Cooldown / Awakening Tracker
    local CooldownTracker = {
        enabled=false,
        bars={},
        gui=nil,
        status=nil,
        list=nil,
        hookInstalled=false,
        useMove=nil,
        messageConn=nil,
        cooldownConnections={},
    }

    local function destroyCooldownBar(entry)
        if not entry then return end
        if entry.label and entry.label.Parent then entry.label:Destroy() end
        if entry.card and entry.card.Parent then entry.card:Destroy() end
    end

    local function createCooldownBar(skillIdentifier, duration)
        if not CooldownTracker.enabled then return end
        local skillName = "Unknown Skill"
        if typeof(skillIdentifier)=="Instance" then
            skillName = skillIdentifier.Name
        elseif typeof(skillIdentifier)=="string" or typeof(skillIdentifier)=="number" then
            skillName = tostring(skillIdentifier)
        elseif typeof(skillIdentifier)=="table" and skillIdentifier.Name then
            skillName = tostring(skillIdentifier.Name)
        end
        local cdTime = tonumber(duration)
        if not cdTime or cdTime <= 0 then return end

        local label = Instance.new("TextLabel")
        label.Size=UDim2.new(1,0,0,30)
        label.BackgroundColor3=Color3.fromRGB(25,25,25)
        label.BorderSizePixel=0
        label.TextColor3=Color3.fromRGB(255,255,255)
        label.Font=Enum.Font.GothamBold
        label.TextSize=12
        label.TextXAlignment=Enum.TextXAlignment.Left
        label.Parent=CooldownTracker.list
        corner(label,6)

        local entry={label=label}
        CooldownTracker.bars[#CooldownTracker.bars+1]=entry
        task.spawn(function()
            local start=os.clock()
            while CooldownTracker.enabled and label.Parent do
                local remaining=cdTime-(os.clock()-start)
                if remaining<=0 then break end
                label.Text=string.format("  ⏳ %s: %.1fs",skillName,remaining)
                task.wait(0.05)
            end
            destroyCooldownBar(entry)
            for i,v in ipairs(CooldownTracker.bars) do
                if v==entry then table.remove(CooldownTracker.bars,i); break end
            end
        end)
    end

    local function setupCooldownTrackerGui()
        if CooldownTracker.gui and CooldownTracker.gui.Parent then return end
        local sg=Instance.new("ScreenGui")
        sg.Name="BallControllerCooldownTracker"
        sg.ResetOnSpawn=false
        sg.Parent=PlayerGui
        CooldownTracker.gui=sg

        local status=Instance.new("TextLabel")
        status.Size=UDim2.fromOffset(250,35)
        status.Position=UDim2.new(0.5,-125,0.05,0)
        status.BackgroundColor3=Color3.fromRGB(20,20,20)
        status.TextColor3=Color3.fromRGB(255,215,0)
        status.Font=Enum.Font.GothamBold
        status.TextSize=14
        status.Text="Status: Normal"
        status.Visible=false
        status.Parent=sg
        corner(status,8)
        CooldownTracker.status=status

        local list=Instance.new("Frame")
        list.Size=UDim2.fromOffset(240,400)
        list.Position=UDim2.new(0.78,0,0.28,0)
        list.BackgroundTransparency=1
        list.Parent=sg
        local lay=Instance.new("UIListLayout")
        lay.Padding=UDim.new(0,6)
        lay.SortOrder=Enum.SortOrder.LayoutOrder
        lay.Parent=list
        CooldownTracker.list=list
    end

    local function disconnectCooldownEvents()
        for _,c in ipairs(CooldownTracker.cooldownConnections) do dcon(c) end
        table.clear(CooldownTracker.cooldownConnections)
        dcon(CooldownTracker.messageConn)
        CooldownTracker.messageConn=nil
    end

    local function setupCooldownEvents()
        disconnectCooldownEvents()
        if not CooldownTracker.enabled then return end
        setupCooldownTrackerGui()
        local events=ReplicatedStorage:FindFirstChild("Events")
        local ui=events and events:FindFirstChild("UI")
        local cb=ui and ui:FindFirstChild("CooldownBind")
        local cr=ui and ui:FindFirstChild("CooldownRemote")
        if cb and cb:IsA("BindableEvent") then CooldownTracker.cooldownConnections[#CooldownTracker.cooldownConnections+1]=cb.Event:Connect(createCooldownBar) end
        if cr and cr:IsA("RemoteEvent") then CooldownTracker.cooldownConnections[#CooldownTracker.cooldownConnections+1]=cr.OnClientEvent:Connect(createCooldownBar) end

        local messages=events and events:FindFirstChild("Messages")
        local me=messages and messages:FindFirstChild("SendMessage")
        if me and me:IsA("RemoteEvent") then
            CooldownTracker.messageConn=me.OnClientEvent:Connect(function(msgText, displayTime)
                if typeof(msgText)~="string" or not CooldownTracker.status then return end
                if string.find(msgText,"%[local player%] Received Awakening") then
                    CooldownTracker.status.Text="⚡ HAVE AWK ⚡"
                    CooldownTracker.status.TextColor3=Color3.fromRGB(255,215,0)
                    CooldownTracker.status.Visible=true
                elseif string.find(msgText,"Giving Awakening In 5 Seconds%.%.%.") then
                    CooldownTracker.status.Text="Status: Normal"
                    CooldownTracker.status.Visible=false
                end
            end)
        end
    end

    local function installUseMoveHook()
        if CooldownTracker.hookInstalled then return end
        if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then return end
        local events=ReplicatedStorage:FindFirstChild("Events")
        local useMove=events and events:FindFirstChild("UseMove")
        if not useMove or not useMove:IsA("RemoteFunction") then return end
        CooldownTracker.useMove=useMove
        local oldNamecall
        oldNamecall=hookmetamethod(game,"__namecall",function(self,...)
            local method=getnamecallmethod()
            local args={...}
            local result={oldNamecall(self,...)}
            if CooldownTracker.enabled and self==CooldownTracker.useMove and (method=="InvokeServer" or method=="invokeServer") then
                local cooldownTime=result[1]
                if cooldownTime then createCooldownBar("Move "..tostring(args[1]),cooldownTime) end
            end
            return table.unpack(result)
        end)
        CooldownTracker.hookInstalled=true
    end

    function M.cooldownTracker(on)
        CooldownTracker.enabled=on
        if on then
            setupCooldownEvents()
            installUseMoveHook()
            setupCooldownTrackerGui()
            setStatus("Cooldown Tracker ON")
        else
            disconnectCooldownEvents()
            for _,e in ipairs(CooldownTracker.bars) do destroyCooldownBar(e) end
            table.clear(CooldownTracker.bars)
            if CooldownTracker.status then CooldownTracker.status.Visible=false end
            setStatus("Cooldown Tracker OFF")
        end
        return true
    end

    -- Auto Join Team
    local AutoJoin = {enabled=false, team="Home", role="CF", conn=nil, gui=nil}
    local function resolveJoinEvent()
        local events = ReplicatedStorage:FindFirstChild("Events")
        local gameFolder = events and events:FindFirstChild("Game")
        local ev = gameFolder and gameFolder:FindFirstChild("JoinGame")
        if ev and ev:IsA("RemoteEvent") then return ev end
        return ReplicatedStorage:FindFirstChild("JoinTeam", true)
            or ReplicatedStorage:FindFirstChild("ChangeTeam", true)
            or ReplicatedStorage:FindFirstChild("SelectTeam", true)
    end
    local function roleValue(plr)
        local a = plr:GetAttribute("Role")
        if a ~= nil then return tostring(a) end
        local o = plr:FindFirstChild("Role")
        if o and o.Value ~= nil then return tostring(o.Value) end
        return ""
    end
    local function roleAvailable(team, role)
        for _,plr in ipairs(Players:GetPlayers()) do
            local t = plr.Team and plr.Team.Name or ""
            if t == team and roleValue(plr) == role then return false end
        end
        return true
    end
    local function sendJoin()
        local ev = resolveJoinEvent()
        if ev and ev:IsA("RemoteEvent") then
            pcall(function() ev:FireServer(AutoJoin.team, AutoJoin.role) end)
            return true
        end
        return false
    end
    function M.autoJoin(on)
        if AutoJoin.conn then dcon(AutoJoin.conn); AutoJoin.conn=nil end
        AutoJoin.enabled=on
        if on then
            sendJoin()
            AutoJoin.conn=addc(RunService.Heartbeat,function()
                if not AutoJoin.enabled then return end
                if roleAvailable(AutoJoin.team,AutoJoin.role) then sendJoin() end
            end)
            setStatus("Auto Join ON ("..AutoJoin.team.." / "..AutoJoin.role..")")
        else
            setStatus("Auto Join OFF")
        end
        return true
    end

    -- Character display action
    local function setupCharacter(player)
        local ls=player:FindFirstChild("leaderstats") or Instance.new("Folder"); ls.Name="leaderstats"; ls.Parent=player
        local disp=ls:FindFirstChild("Character") or Instance.new("StringValue"); disp.Name="Character"; if disp.Parent~=ls then disp.Parent=ls end; disp.Value=disp.Value~="" and disp.Value or "Chưa chọn"
        local values=player:FindFirstChild("Values")
        if not values then
            local key="values:"..player.UserId
            if not M.charSetup[key] then
                M.charSetup[key]=true
                M.charConnections[#M.charConnections+1]=player.ChildAdded:Connect(function(child)
                    if child.Name=="Values" then setupCharacter(player) end
                end)
            end
            return
        end
        local v=values:FindFirstChild("CharacterName")
        if not (v and v:IsA("ValueBase")) then return end
        disp.Value=tostring(v.Value)
        if not M.charSetup[v] then
            M.charSetup[v]=true
            M.charConnections[#M.charConnections+1]=v:GetPropertyChangedSignal("Value"):Connect(function()
                if disp.Parent then disp.Value=tostring(v.Value) end
            end)
        end
    end
    function M.displayCharacter()
        for _,p in ipairs(Players:GetPlayers()) do task.spawn(setupCharacter,p) end
        if not M.playerAdded then M.playerAdded=true; M.charConnections[#M.charConnections+1]=Players.PlayerAdded:Connect(function(p) task.spawn(setupCharacter,p) end) end
        setStatus("Character display refreshed")
    end
    function M.cleanup()
        if State.moreMods.antiShake then M.antiShake(false) end; if State.moreMods.antiBlur then M.antiBlur(false) end; if State.moreMods.autoJoin then M.autoJoin(false) end; if State.moreMods.cooldownTracker then M.cooldownTracker(false) end; State.moreMods.antiShake=false; State.moreMods.antiBlur=false; State.moreMods.autoJoin=false; State.moreMods.cooldownTracker=false; Traj.enabled=false; State.moreMods.trajectory=false; clearTraj(); for _,c in ipairs(M.charConnections) do dcon(c) end; table.clear(M.charConnections); for _,c in ipairs(M.blurConnections) do dcon(c) end; table.clear(M.blurConnections); for _,c in ipairs(M.moreConnections) do dcon(c) end; table.clear(M.moreConnections)
    end

    API.bind(RunService.RenderStepped,renderTraj)
    API.bind(UI.moreMod.MouseButton1Click,function() State.moreModOpen=not State.moreModOpen; UI.moreModFrame.Visible=State.moreModOpen and not State.minimized end)
    API.bind(UI.moreModClose.MouseButton1Click,function() State.moreModOpen=false; UI.moreModFrame.Visible=false end)
    API.makeDraggable(UI.moreModFrame,UI.moreModTitle)
    API.bind(UI.moreModAntiShake.MouseButton1Click,function() local x=not State.moreMods.antiShake; if M.antiShake(x) then State.moreMods.antiShake=x end; API.updateUI(true) end)
    API.bind(UI.moreModAntiBlur.MouseButton1Click,function() local x=not State.moreMods.antiBlur; if M.antiBlur(x) then State.moreMods.antiBlur=x end; API.updateUI(true) end)
    API.bind(UI.moreModTrajectory.MouseButton1Click,function() State.moreMods.trajectory=not State.moreMods.trajectory; Traj.enabled=State.moreMods.trajectory; if not Traj.enabled then clearTraj() end; API.updateUI(true) end)
    API.bind(UI.moreModTrajectoryReset.MouseButton1Click,function()
        if not Traj.enabled then
            setStatus("Trajectory is OFF")
            return
        end
        clearTraj()
        Traj.forceRefresh=true
        Traj.filterDirty=true
        task.defer(function()
            if Traj.enabled then
                renderTraj()
            end
        end)
        setStatus("Trajectory refreshed")
    end)
    API.bind(UI.moreModAutoJoin.MouseButton1Click,function() local x=not State.moreMods.autoJoin; if M.autoJoin(x) then State.moreMods.autoJoin=x end; API.updateUI(true) end)
    API.bind(UI.moreModCharacter.MouseButton1Click,M.displayCharacter)
    Env.__BALL_CONTROLLER_V4_MOREMOD_CLEANUP=M.cleanup
end

--========================================================--
-- UI EVENTS
--========================================================--

do
    -- verify BEFORE any MouseButton1Click access
    API.verifyUI()

    API.makeDraggable(UI.main, UI.title)
    API.makeDraggable(UI.settingsFrame, UI.settingsTitle)
    API.makeDraggable(UI.statusPanel, UI.statusTitle)

    -- Zoom
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

    API.bind(UIS.InputChanged, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseWheel then
            return
        end

        local ctrl =
            UIS:IsKeyDown(Enum.KeyCode.LeftControl)
            or UIS:IsKeyDown(Enum.KeyCode.RightControl)

        if not ctrl then
            return
        end

        if input.Position.Z > 0 then
            API.scaleUI(State.uiScale + CFG.ZOOM_STEP)
        elseif input.Position.Z < 0 then
            API.scaleUI(State.uiScale - CFG.ZOOM_STEP)
        end
    end)

    -- Minimize / restore
    API.bind(UI.minimize.MouseButton1Click, function()
        State.minimized = true
        UI.main.Visible = false
        UI.settingsFrame.Visible = false
        UI.moreModFrame.Visible = false
        UI.restore.Visible = true
    end)

    API.bind(UI.restore.MouseButton1Click, function()
        State.minimized = false
        UI.main.Visible = true
        UI.restore.Visible = true
    end)

    API.bind(UI.restore.MouseButton2Click, function()
        State.minimized = false
        UI.main.Visible = true
        UI.restore.Visible = true

        if State.settingsOpen then
            UI.settingsFrame.Visible = true
        end
        if State.moreModOpen then
            UI.moreModFrame.Visible = true
        end

        task.defer(API.centerUI)
    end)

    -- Status
    API.bind(UI.statusMin.MouseButton1Click, function()
        API.statusMini(not UI.statusMini)
    end)

    API.bind(UI.statusClose.MouseButton1Click, function()
        UI.statusPanel.Visible = false
        UI.statusToggle.Text = "BALL STATUS: OFF"
    end)

    API.bind(UI.statusToggle.MouseButton1Click, function()
        UI.statusPanel.Visible = not UI.statusPanel.Visible
        UI.statusToggle.Text =
            UI.statusPanel.Visible and "BALL STATUS: ON" or "BALL STATUS: OFF"
    end)

    -- Settings
    API.bind(UI.settings.MouseButton1Click, function()
        State.settingsOpen = not State.settingsOpen
        UI.settingsFrame.Visible = State.settingsOpen and not State.minimized
        API.updateSettings()
    end)

    API.bind(UI.closeSettings.MouseButton1Click, function()
        State.settingsOpen = false
        UI.settingsFrame.Visible = false
    end)

    for i = 1, 3 do
        local index = i
        API.bind(UI.tabs[index].MouseButton1Click, function()
            State.settingsTab = index
            API.updateSettings()
        end)
    end

    -- Control key
    local function startKeyChange()
        State.changingKey = true
        API.notify("CONTROL KEY", "Nhấn phím mới (ESC = hủy)", 1.5)
    end

    API.bind(UI.control.MouseButton1Click, startKeyChange)
    API.bind(UI.general.key.MouseButton1Click, startKeyChange)

    -- Anchor
    local function toggleAnchor()
        State.anchor = not State.anchor
        State.forceUnanchor = false
        API.unlockPlayer()
        API.lockPlayer()
        API.updateUI(true)
    end

    API.bind(UI.anchor.MouseButton1Click, toggleAnchor)
    API.bind(UI.general.anchor.MouseButton1Click, toggleAnchor)

    API.bind(UI.force.MouseButton1Click, API.forceUnanchor)

    -- Mode
    API.bind(UI.mode.MouseButton1Click, function()
        State.mode = State.mode == 1 and 2 or 1
        State.enabled = false
        State.forceUnanchor = false

        API.unlockPlayer()
        API.restoreCamera()
        API.stopRonaldo()
        API.resetSpecial()

        if State.mode ~= 1 and State.advance then
            State.advance = false
        end

        API.updateUI(true)
        API.notify("MODE", State.mode == 1 and "MODE 1 [CAMERA]" or "MODE 2 [RONALDO]", 1.1)
    end)

    -- Steal
    API.bind(UI.steal.MouseButton1Click, function()
        if State.autoGoal then
            State.steal = false
            API.notify("STEAL BALL", "Auto Goal đang ON", 1.1)
        else
            State.steal = not State.steal

            if State.steal
                and State.autoStealOffOnGet
                and API.localHasBall()
            then
                State.steal = false
            end
        end

        if not State.steal then
            API.resetSpecial()
        end

        API.updateUI(true)
    end)

    -- SAE
    API.bind(UI.sae.MouseButton1Click, function()
        State.sae = not State.sae

        if not State.sae then
            API.clearSAE()
        end

        API.updateUI(true)
    end)

    -- TP
    API.bind(UI.tp.MouseButton1Click, API.startTP)
    API.bind(UI.tpGoal.MouseButton1Click, API.tpGoal)

    -- TP setting
    local function parseTP(boxObj, sync)
        local value = tonumber(boxObj.Text)
        if not value then
            boxObj.Text = tostring(State.tpDuration)
            return
        end

        State.tpDuration = math.clamp(value, 0.1, 60)
        UI.tpTime.Text = tostring(State.tpDuration)
        UI.general.tp.Text = tostring(State.tpDuration)

        if sync then
            sync.Text = tostring(State.tpDuration)
        end
    end

    API.bind(UI.tpTime.FocusLost, function()
        parseTP(UI.tpTime, UI.general.tp)
    end)

    API.bind(UI.general.tp.FocusLost, function()
        parseTP(UI.general.tp, UI.tpTime)
    end)

    -- Auto steal setting
    API.bind(UI.general.autoSteal.MouseButton1Click, function()
        State.autoStealOffOnGet = not State.autoStealOffOnGet
        API.updateSettings()
    end)

    -- Auto Goal setting
    API.bind(UI.general.autoGoal.MouseButton1Click, function()
        State.autoGoal = not State.autoGoal
        State.autoGoalToken += 1
        State.autoGoalBusy = false

        if State.autoGoal then
            State.steal = false
            API.notify("AUTO GOAL", "ON", 1.0)
        else
            API.notify("AUTO GOAL", "OFF", 1.0)
        end

        API.resetSpecial()
        API.updateUI(true)
    end)

    -- Speed setting
    local function parseSpeed(boxObj, modeIndex)
        local value = tonumber(boxObj.Text)
        if not value then
            boxObj.Text = tostring(Mode[modeIndex].speed)
            return
        end

        Mode[modeIndex].speed =
            math.clamp(value, CFG.MIN_SPEED, CFG.MAX_SPEED)

        boxObj.Text = tostring(Mode[modeIndex].speed)
    end

    API.bind(UI.m1.speed.FocusLost, function()
        parseSpeed(UI.m1.speed, 1)
    end)

    API.bind(UI.m2.speed.FocusLost, function()
        parseSpeed(UI.m2.speed, 2)
    end)

    -- Mode 1 advance
    API.bind(UI.m1.advance.MouseButton1Click, function()
        State.advance = not State.advance
        State.keys = {W=false,A=false,S=false,D=false,Q=false,E=false}

        if State.advance and State.mode == 1 and State.enabled then
            camera = workspace.CurrentCamera
            if camera then
                camera.CameraType = Enum.CameraType.Scriptable
            end
        elseif not State.advance and State.mode == 1 and State.enabled then
            local _, _, ball = API.getBallState()
            if ball then
                API.followBall(ball)
            else
                API.restoreCamera()
            end
        end

        API.updateSettings()
    end)

    -- Ronaldo
    API.bind(UI.m2.advance.MouseButton1Click, function()
        State.ronaldo = not State.ronaldo

        if not State.ronaldo then
            API.stopRonaldo()
        end

        API.updateSettings()
    end)

end

--========================================================--
-- INPUT
--========================================================--

do
    local function setKey(key, value)
        if key == Enum.KeyCode.W then State.keys.W = value end
        if key == Enum.KeyCode.A then State.keys.A = value end
        if key == Enum.KeyCode.S then State.keys.S = value end
        if key == Enum.KeyCode.D then State.keys.D = value end
        if key == Enum.KeyCode.Q then State.keys.Q = value end
        if key == Enum.KeyCode.E then State.keys.E = value end
    end

    API.bind(UIS.InputBegan, function(input, processed)
        if processed then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            State.leftMouseHeld = true
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            State.rightMouseHeld = true

            if State.mode == 2
                and State.ronaldo
                and API.localHasBall()
            then
                API.selectRonaldo()
            end

            return
        end

        if input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end

        if State.changingKey then
            if input.KeyCode == Enum.KeyCode.Escape then
                State.changingKey = false
                API.updateSettings()
                return
            end

            if input.KeyCode ~= Enum.KeyCode.Unknown then
                State.controlKey = input.KeyCode
                State.changingKey = false
                API.updateUI(true)
            end

            return
        end

        if State.advance and State.mode == 1 then
            if input.KeyCode == Enum.KeyCode.W
                or input.KeyCode == Enum.KeyCode.A
                or input.KeyCode == Enum.KeyCode.S
                or input.KeyCode == Enum.KeyCode.D
                or input.KeyCode == Enum.KeyCode.Q
                or input.KeyCode == Enum.KeyCode.E
            then
                setKey(input.KeyCode,true)
                return
            end
        end

        if input.KeyCode ~= State.controlKey then
            return
        end

        if State.sae then
            API.selectSAE()
            return
        end

        if State.mode == 2
            and State.ronaldo
            and State.ronaldoTarget
        then
            API.startRonaldo()
            return
        end

        if State.mode == 1 then
            State.enabled = not State.enabled

            if State.enabled then
                State.forceUnanchor = false

                local _, _, ball = API.getBallState()

                if State.advance then
                    camera = workspace.CurrentCamera
                    if camera then
                        camera.CameraType = Enum.CameraType.Scriptable
                    end
                elseif ball then
                    API.followBall(ball)
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
            local _, holder, ball = API.getBallState()

            if holder == LP and ball then
                API.fireShoot(
                    API.cameraDirection(),
                    Mode[2].speed,
                    false
                )
            else
                API.notify("MODE 2", "Cần đang cầm bóng", 1.0)
            end
        end
    end)

    API.bind(UIS.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            State.leftMouseHeld = false
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            State.rightMouseHeld = false
        elseif input.UserInputType == Enum.UserInputType.Keyboard then
            setKey(input.KeyCode,false)
        end
    end)
end

--========================================================--
-- PLAYER EVENTS
--========================================================--

API.bind(Players.PlayerAdded, function(plr)
    API.attachPlayer(plr)
    API.queueBallRebuild()
end)

API.bind(Players.PlayerRemoving, function(plr)
    API.disconnectList(CharConnections[plr])
    API.disconnectList(PlayerConnections[plr])
    CharConnections[plr] = nil
    PlayerConnections[plr] = nil
    API.queueBallRebuild()
end)

for _, plr in ipairs(Players:GetPlayers()) do
    API.attachPlayer(plr)
end

API.rebuildBall(true)

API.bind(LP.CharacterAdded, function()
    task.wait(0.35)

    State.autoGoalToken += 1
    State.autoGoalBusy = false

    API.stopRonaldo()
    API.clearSAE()
    API.resetSpecial()

    State.enabled = false
    State.steal = false
    State.tpActive = false
    State.tpReturn = nil
    State.tpGoalActive = false
    State.forceUnanchor = false

    State.keys = {W=false,A=false,S=false,D=false,Q=false,E=false}

    Char.walk, Char.jump, Char.rotate = nil, nil, nil
    Char.locked = false

    API.updateCharacter()
    API.queueBallRebuild()
    API.updateUI(true)
end)

API.bind(
    workspace:GetPropertyChangedSignal("CurrentCamera"),
    function()
        camera = workspace.CurrentCamera

        task.defer(function()
            if UI.main then API.clampUI(UI.main) end
            if UI.settingsFrame then API.clampUI(UI.settingsFrame) end
            if UI.statusPanel then API.clampUI(UI.statusPanel) end
        end)
    end
)

--========================================================--
-- HEARTBEAT / RENDER
--========================================================--

API.bind(RunService.RenderStepped, function()
    if State.saeActive then
        API.updateSAE()
    end
end)

API.bind(RunService.Heartbeat, function()
    API.updateCharacter()

    local state, holder, ball = API.getBallState()

    API.updateBallUI(state, holder)
    API.updateRonaldo()

    if State.autoGoal then
        local now = os.clock()

        if now - State.lastAutoGoal >= 0.10 then
            State.lastAutoGoal = now

            if API.localHasBall() then
                API.resetSpecial()

                local goal = API.opponentGoal()
                if goal and not State.autoGoalBusy then
                    State.autoGoalBusy = true
                    State.autoGoalToken += 1

                    local token = State.autoGoalToken
                    local root = Char.root

                    if root and root.Parent then
                        local saved = root.CFrame

                        task.spawn(function()
                            local ok = pcall(function()
                                if token ~= State.autoGoalToken or not State.autoGoal then
                                    return
                                end

                                -- Exact reference flow: player -> goal offset
                                root.CFrame = CFrame.new(
                                    goal.Position + CFG.GOAL_OFFSET,
                                    goal.Position
                                )

                                task.wait(0.02)

                                if token ~= State.autoGoalToken or not State.autoGoal then
                                    return
                                end

                                local direction = goal.Position - root.Position
                                if direction.Magnitude > 0.001 then
                                    if not API.fireShoot(
                                        direction.Unit,
                                        CFG.SHOOT_FORCE,
                                        false
                                    ) then
                                        return
                                    end
                                end

                                -- Wait until ShootBall has actually released the ball
                                -- before touching its CFrame/velocity.
                                local _, _, shotBall = API.getBallState()
                                local released = shotBall and API.waitBallReleased(shotBall, 0.20) or false
                                if not released then
                                    return
                                end

                                task.wait(0.02)

                                if token ~= State.autoGoalToken or not State.autoGoal then
                                    return
                                end

                                -- Resolve the ball again after release, then finish the
                                -- same reference flow by moving only the FREE ball.
                                local state2, _, ball2 = API.getBallState()
                                if state2 == "FREE" and ball2 and ball2.Parent then
                                    ball2.CFrame = goal.CFrame
                                    ball2.AssemblyLinearVelocity = Vector3.zero
                                    ball2.AssemblyAngularVelocity = Vector3.zero
                                end
                            end)

                            if not ok then
                                warn("[Ball Controller] Auto Goal task failed")
                            end

                            if root and root.Parent then
                                root.CFrame = saved
                            end

                            if token == State.autoGoalToken then
                                State.autoGoalBusy = false
                            end
                        end)
                    else
                        State.autoGoalBusy = false
                    end

                end

            else
                -- No ball: always keep using V4.5's full steal engine.
                -- This includes FREE ball targets and character-specific specials.
                API.stealStep()
            end
        end
    elseif State.steal then
        if State.autoStealOffOnGet and API.localHasBall() then
            State.steal = false
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

    if State.enabled and State.mode == 1 and ball then
        if State.advance then
            local f, r = API.flatDirections()
            local move = Vector3.zero

            if State.keys.W then move += f end
            if State.keys.S then move -= f end
            if State.keys.D then move += r end
            if State.keys.A then move -= r end
            if State.keys.E then move += Vector3.new(0,1,0) end
            if State.keys.Q then move -= Vector3.new(0,1,0) end

            if move.Magnitude > 0 then
                ball.AssemblyLinearVelocity =
                    move.Unit * math.clamp(
                        Mode[1].speed,
                        CFG.MIN_SPEED,
                        CFG.MAX_SPEED
                    )
            else
                ball.AssemblyLinearVelocity = Vector3.zero
            end

            camera = workspace.CurrentCamera
            if camera then
                camera.CameraType = Enum.CameraType.Custom
                camera.CameraSubject = ball
            end
        else
            ball.AssemblyLinearVelocity =
                API.cameraDirection()
                * math.clamp(
                    Mode[1].speed,
                    CFG.MIN_SPEED,
                    CFG.MAX_SPEED
                )

            camera = workspace.CurrentCamera
            if camera then
                camera.CameraType = Enum.CameraType.Custom
                camera.CameraSubject = ball
            end
        end
    end

    if State.mode == 1 then
        API.lockPlayer()
    elseif Char.root then
        Char.root.Anchored = false
    end

    UI.restore.Visible = true
end)

--========================================================--
-- STOP
--========================================================--

function API.stopController()
    if Env.__BALL_CONTROLLER_V4_MOREMOD_CLEANUP then pcall(Env.__BALL_CONTROLLER_V4_MOREMOD_CLEANUP); Env.__BALL_CONTROLLER_V4_MOREMOD_CLEANUP=nil end
    State.autoGoalToken += 1
    State.autoGoalBusy = false

    State.enabled = false
    State.steal = false
    State.autoGoal = false
    State.tpActive = false
    State.tpReturn = nil
    State.tpGoalActive = false

    API.stopRonaldo()
    API.clearSAE()
    API.resetSpecial()
    API.unlockPlayer()
    API.restoreCamera()

    for i = 1, #Connections do
        API.disconnect(Connections[i])
    end
    table.clear(Connections)

    for plr, list in pairs(CharConnections) do
        API.disconnectList(list)
        CharConnections[plr] = nil
    end

    for plr, list in pairs(PlayerConnections) do
        API.disconnectList(list)
        PlayerConnections[plr] = nil
    end

    local existing = PlayerGui:FindFirstChild("BallController")
    if existing then
        existing:Destroy()
    end

    UI = {ready = false}
end

Env.__BALL_CONTROLLER_V4_STOP = API.stopController

--========================================================--
-- INITIAL UI STATE
--========================================================--

API.updateCharacter()
API.scaleUI(State.uiScale)
API.updateUI(true)
State.settingsTab = 1
API.updateSettings()
API.statusMini(false)

UI.restore.Visible = true
UI.moreModFrame.Visible = false

if API.resolveShootRemote(true) then
    API.notify("SHOOT REMOTE", "ShootBall detected", 1.4)
else
    API.notify("SHOOT REMOTE", "Events.ShootBall chưa tìm thấy", 1.8)
end

if not VirtualInputManager then
    API.notify(
        "STEAL BALL",
        "VirtualInputManager không khả dụng",
        1.8
    )
end

API.notify("BALL CONTROLLER", "V4.5 loaded - GUI ready", 1.4)

print("[Ball Controller V4.5] loaded")
