--========================================================--
-- MORE MOD STANDALONE
-- Tách khỏi Ball Controller V4.5
-- - UI popup độc lập, kéo-thả PC + mobile hold
-- - Same version re-run: toggle UI only
-- - Different/old version re-run: cleanup bản cũ hoàn toàn rồi tạo bản mới
-- - Anti Blur / Screen Effects cleanup
-- - Ball Trajectory
-- - Cooldown / Awakening Tracker
-- - Display Character
--========================================================--

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")

local ENV = (getgenv and getgenv()) or _G
local KEY = "__BALL_CONTROLLER_MOREMOD_STANDALONE"
local VERSION = "3.0.0"

--========================================================--
-- CLEANUP CŨ
--========================================================--

--========================================================--
-- TOGGLE ON RE-RUN
-- Run #1: create/show
-- Run #2: hide UI (KHÔNG cleanup logic)
-- Run #3: show UI lại
-- Run #4: hide UI...
--========================================================--

do
    local old = ENV[KEY]
    if type(old) == "table" then
        if old.VERSION == VERSION and type(old.ToggleUI) == "function" then
            pcall(old.ToggleUI)
            return
        end

        -- Khác version / bản cũ: teardown hoàn toàn trước khi tạo bản mới.
        if type(old.Cleanup) == "function" then
            pcall(old.Cleanup)
        end

        if ENV[KEY] == old then
            ENV[KEY] = nil
        end
    end
end

local Connections = {}
local FeatureConnections = {}
local Runtime = {
    gui = nil,
    frame = nil,
    status = nil,
    buttons = {},
    destroyed = false,
    uiVisible = true,
}

local function disconnect(c)
    if c then
        pcall(function() c:Disconnect() end)
    end
end

local function disconnectList(list)
    for i = #list, 1, -1 do
        disconnect(list[i])
        list[i] = nil
    end
end

local function bind(signal, callback, list)
    local c = signal:Connect(callback)
    local target = list or Connections
    target[#target + 1] = c
    return c
end

local function safeDestroy(obj)
    if obj then
        pcall(function() obj:Destroy() end)
    end
end

--========================================================--
-- STATE
--========================================================--

local State = {
    antiShake = false,
    antiBlur = false,
    trajectory = false,
    cooldown = false,
}

local Traj = {
    enabled = false,
    time = 6,
    step = 0.03,
    width = 0.35,
    bounces = 4,
    elasticity = 0.75,
    smoothing = 0.25,
    sample = 0.06,
    minSpeed = 2,
    color = Color3.fromRGB(0, 255, 238),

    points = {},
    ball = nil,
    holder = nil,
    lastBall = nil,
    lastPos = nil,
    lastTime = 0,
    lastVel = 0,
    velocity = Vector3.zero,
    smooth = Vector3.zero,
    heldDir = Vector3.zero,
    heldSpeed = 0,

    attachments = {},
    beams = {},
    visualFolder = nil,
    ray = nil,
    filterDirty = true,
    filteredBall = nil,
    filteredCount = 0,
    filterTime = 0,
    forceRefresh = false,

    arrow0 = nil,
    arrow1 = nil,
    arrowBeam = nil,
}

Traj.ray = RaycastParams.new()
Traj.ray.FilterType = Enum.RaycastFilterType.Exclude
Traj.ray.RespectCanCollide = true

local MAX_VISIBLE_BARS = 10

local Cooldown = {
    enabled = false,
    gui = nil,
    status = nil,
    list = nil,
    bars = {},
    connections = {},
    messageConn = nil,
    layoutConn = nil,
    useMoveHookInstalled = false,
}

--========================================================--
-- UI HELPERS
--========================================================--

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = obj
end

local function stroke(obj)
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(65, 65, 80)
    s.Transparency = 0.15
    s.Parent = obj
end

local function label(parent, text, x, y, w, h, size)
    local l = Instance.new("TextLabel")
    l.Position = UDim2.fromOffset(x, y)
    l.Size = UDim2.fromOffset(w, h)
    l.BackgroundTransparency = 1
    l.Text = text
    l.Font = Enum.Font.Gotham
    l.TextSize = size or 12
    l.TextColor3 = Color3.new(1, 1, 1)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

local function button(parent, text, x, y, w, h)
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(x, y)
    b.Size = UDim2.fromOffset(w, h)
    b.BackgroundColor3 = Color3.fromRGB(40, 40, 47)
    b.BorderSizePixel = 0
    b.Text = text
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 11
    b.TextColor3 = Color3.new(1, 1, 1)
    b.AutoButtonColor = true
    b.Parent = parent
    corner(b, 7)
    return b
end

local function setStatus(text)
    if Runtime.status and Runtime.status.Parent then
        Runtime.status.Text = "STATUS: " .. tostring(text)
    end
end

--========================================================--
-- DRAG
-- PC: click-drag
-- Mobile: giữ 0.45s rồi kéo
--========================================================--

local function makeDraggable(object, handle)
    local dragging = false
    local pending = false
    local pressInput = nil
    local pressStart = nil
    local startPos = nil
    local changed = nil

    local HOLD_TIME = 0.45
    local MOVE_CANCEL = 12

    local function stop()
        pending = false
        dragging = false
        pressInput = nil
        pressStart = nil
        startPos = nil
        disconnect(changed)
        changed = nil
    end

    bind(handle.InputBegan, function(input)
        local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
        local isTouch = input.UserInputType == Enum.UserInputType.Touch
        if not isMouse and not isTouch then return end

        pending = false
        dragging = false
        pressInput = input
        pressStart = input.Position
        startPos = object.Position

        disconnect(changed)
        changed = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                stop()
            end
        end)

        if isMouse then
            dragging = true
            return
        end

        pending = true
        task.delay(HOLD_TIME, function()
            if not pending or pressInput ~= input or not pressStart then return end
            if (input.Position - pressStart).Magnitude > MOVE_CANCEL then
                stop()
                return
            end
            pending = false
            dragging = true
        end)
    end)

    bind(UIS.InputChanged, function(input)
        local isMove =
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch

        if not isMove then return end

        if pending and pressInput and pressStart then
            if (input.Position - pressStart).Magnitude > MOVE_CANCEL then
                stop()
            end
            return
        end

        if not dragging or not pressStart or not startPos or not object.Parent then
            return
        end

        local camera = workspace.CurrentCamera
        local view = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local delta = input.Position - pressStart

        local x = math.clamp(
            startPos.X.Offset + delta.X,
            0,
            math.max(0, view.X - object.AbsoluteSize.X)
        )

        local y = math.clamp(
            startPos.Y.Offset + delta.Y,
            0,
            math.max(0, view.Y - object.AbsoluteSize.Y)
        )

        object.Position = UDim2.fromOffset(x, y)
    end)
end

--========================================================--
-- ANTI SCREEN SHAKE
-- Dựa đúng các object đang có trong game:
-- ReplicatedStorage.Events:
--   CameraShakeEvent
--   CameraShakeRemote
--   CameraShakeRemoteSustained
--   CameraShakeRemoteSustainedBind
-- ReplicatedStorage.Modules:
--   CameraShaker
--   CameraShakeInstance
--   CameraShakePresets
-- PlayerScripts:
--   CameraShake
--
-- Khi ON: cache bản clone rồi xóa/stop các object local.
-- Đồng thời watcher sẽ xóa lại nếu game tạo chúng lần nữa.
-- Khi OFF: dừng watcher và khôi phục các object đã cache nếu còn thiếu.
--========================================================--

local CameraShakeNames = {
    CameraShakeEvent = true,
    CameraShakeRemote = true,
    CameraShakeRemoteSustained = true,
    CameraShakeRemoteSustainedBind = true,
    CameraShaker = true,
    CameraShakeInstance = true,
    CameraShakePresets = true,
}

local CameraShakeCache = {}
local CameraShakeWatcher = nil
local CameraShakePlayerWatcher = nil

local function cacheAndDestroyCameraShake(obj)
    if not obj or not obj.Parent or not CameraShakeNames[obj.Name] then
        return
    end

    if not CameraShakeCache[obj.Name] then
        local ok, clone = pcall(function()
            return obj:Clone()
        end)
        if ok and clone then
            CameraShakeCache[obj.Name] = clone
        end
    end

    pcall(function()
        obj:Destroy()
    end)
end

local function blockCameraShakeObject(obj)
    if obj and obj.Parent and CameraShakeNames[obj.Name] then
        cacheAndDestroyCameraShake(obj)
    end
end

local function restoreCameraShake()
    -- Restore ReplicatedStorage.Events / Modules.
    local events = ReplicatedStorage:FindFirstChild("Events")
    local modules = ReplicatedStorage:FindFirstChild("Modules")

    if events then
        for _, name in ipairs({
            "CameraShakeEvent",
            "CameraShakeRemote",
            "CameraShakeRemoteSustained",
            "CameraShakeRemoteSustainedBind",
        }) do
            if not events:FindFirstChild(name) and CameraShakeCache[name] then
                local ok, clone = pcall(function()
                    return CameraShakeCache[name]:Clone()
                end)
                if ok and clone then
                    clone.Parent = events
                end
            end
        end
    end

    if modules then
        for _, name in ipairs({
            "CameraShaker",
            "CameraShakeInstance",
            "CameraShakePresets",
        }) do
            if not modules:FindFirstChild(name) and CameraShakeCache[name] then
                local ok, clone = pcall(function()
                    return CameraShakeCache[name]:Clone()
                end)
                if ok and clone then
                    clone.Parent = modules
                end
            end
        end
    end

    -- Restore the live LocalScript under PlayerScripts.
    local playerScripts = LP:FindFirstChild("PlayerScripts")
    if playerScripts and not playerScripts:FindFirstChild("CameraShake") then
        local cached = CameraShakeCache.CameraShake
        if cached then
            local ok, clone = pcall(function()
                return cached:Clone()
            end)
            if ok and clone then
                clone.Parent = playerScripts
                if clone:IsA("LocalScript") then
                    clone.Disabled = false
                end
            end
        end
    end
end

local function antiShake(on)
    disconnect(CameraShakeWatcher)
    CameraShakeWatcher = nil
    disconnect(CameraShakePlayerWatcher)
    CameraShakePlayerWatcher = nil

    if not on then
        restoreCameraShake()
        setStatus("Anti Screen Shake OFF")
        return true
    end

    local events = ReplicatedStorage:FindFirstChild("Events")
    if events then
        for _, name in ipairs({
            "CameraShakeEvent",
            "CameraShakeRemote",
            "CameraShakeRemoteSustained",
            "CameraShakeRemoteSustainedBind",
        }) do
            cacheAndDestroyCameraShake(events:FindFirstChild(name))
        end
    end

    local modules = ReplicatedStorage:FindFirstChild("Modules")
    if modules then
        for _, name in ipairs({
            "CameraShaker",
            "CameraShakeInstance",
            "CameraShakePresets",
        }) do
            cacheAndDestroyCameraShake(modules:FindFirstChild(name))
        end
    end

    local playerScripts = LP:FindFirstChild("PlayerScripts")
    if playerScripts then
        local cameraShake = playerScripts:FindFirstChild("CameraShake")
        if cameraShake then
            cacheAndDestroyCameraShake(cameraShake)
        end
    end

    -- Block recreation inside ReplicatedStorage.
    CameraShakeWatcher = ReplicatedStorage.DescendantAdded:Connect(function(obj)
        if State.antiShake and obj and CameraShakeNames[obj.Name] then
            task.defer(function()
                if State.antiShake and obj.Parent then
                    cacheAndDestroyCameraShake(obj)
                end
            end)
        end
    end)

    -- Block the runtime PlayerScripts copy if the game recreates it.
    CameraShakePlayerWatcher = LP.ChildAdded:Connect(function(obj)
        if State.antiShake and obj.Name == "PlayerScripts" then
            task.defer(function()
                local scriptObj = obj:FindFirstChild("CameraShake")
                if scriptObj then
                    cacheAndDestroyCameraShake(scriptObj)
                end
            end)
        end
    end)

    setStatus("Anti Screen Shake ON")
    return true
end

--========================================================--
-- ANTI BLUR / SCREEN EFFECT CLEANUP
--========================================================--

local ScreenEffectNames = {
    Blindness = true,
    ScreenEffectsGUI = true,
    BlackBars = true,
}

local function removeScreenEffect(obj)
    if not obj or not obj.Parent then return end

    if obj.Parent == PlayerGui and ScreenEffectNames[obj.Name] then
        pcall(function()
            obj:Destroy()
        end)
    end
end

local function antiBlur(on)
    disconnect(FeatureConnections.antiBlur)
    FeatureConnections.antiBlur = nil

    if not on then
        setStatus("SCREEN EFFECT CLEANUP OFF")
        return true
    end

    for _, name in ipairs({"Blindness", "ScreenEffectsGUI", "BlackBars"}) do
        local obj = PlayerGui:FindFirstChild(name)
        if obj then
            safeDestroy(obj)
        end
    end

    FeatureConnections.antiBlur =
        PlayerGui.ChildAdded:Connect(removeScreenEffect)

    setStatus("SCREEN EFFECT CLEANUP ON")
    return true
end

--========================================================--
-- BALL FINDER
--========================================================--

local BALL_NAMES = {
    "Ball",
    "SoccerBall",
    "Football",
    "TPSBall",
    "TpsBall",
}

local function findBall()
    -- Ưu tiên các ball đang nằm trong character.
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if char then
            local b = char:FindFirstChild("Ball", true)
            if b and b:IsA("BasePart") then
                return b, player
            end
        end
    end

    for _, name in ipairs(BALL_NAMES) do
        local b = workspace:FindFirstChild(name, true)
        if b and b:IsA("BasePart") then
            return b, nil
        end
    end

    return nil, nil
end

local function getVisualFolder()
    local folder = workspace:FindFirstChild("TrajectoryVisuals")

    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "TrajectoryVisuals"
        folder.Parent = workspace
    end

    if Traj.visualFolder ~= folder then
        Traj.visualFolder = folder
        table.clear(Traj.attachments)
        table.clear(Traj.beams)

        if Traj.arrow0 and Traj.arrow0.Parent ~= folder then
            Traj.arrow0 = nil
        end
        if Traj.arrow1 and Traj.arrow1.Parent ~= folder then
            Traj.arrow1 = nil
        end
        if Traj.arrowBeam and Traj.arrowBeam.Parent ~= folder then
            Traj.arrowBeam = nil
        end

        Traj.filterDirty = true
    end

    return folder
end

local function clearTrajectory()
    for _, b in pairs(Traj.beams) do
        if b and b.Parent then
            b.Enabled = false
        end
    end

    for _, a in pairs(Traj.attachments) do
        if a and a.Parent then
            a.WorldPosition = Vector3.new(0, -10000, 0)
        end
    end

    if Traj.arrowBeam and Traj.arrowBeam.Parent then
        Traj.arrowBeam.Enabled = false
    end

    table.clear(Traj.points)

    Traj.ball = nil
    Traj.holder = nil
    Traj.lastBall = nil
    Traj.lastPos = nil
    Traj.lastTime = 0
    Traj.lastVel = 0
    Traj.velocity = Vector3.zero
    Traj.smooth = Vector3.zero
    Traj.heldDir = Vector3.zero
    Traj.heldSpeed = 0
    Traj.filteredBall = nil
    Traj.filteredCount = 0
    Traj.filterTime = 0
    Traj.filterDirty = true
end

local function unit(v)
    return v.Magnitude > 0.001 and v.Unit or Vector3.zero
end

local function holderDirection(player)
    local root =
        player
        and player.Character
        and player.Character:FindFirstChild("HumanoidRootPart")

    if not root then
        return Vector3.zero
    end

    return unit(Vector3.new(
        root.CFrame.LookVector.X,
        0,
        root.CFrame.LookVector.Z
    ))
end

local function updateMovement(ball, holder)
    local now = os.clock()

    if Traj.lastBall ~= ball then
        Traj.lastBall = ball
        Traj.lastPos = ball.Position
        Traj.lastTime = now
        Traj.lastVel = now
        Traj.velocity = Vector3.zero
        Traj.smooth = Vector3.zero
    end

    if holder then
        Traj.heldDir = holderDirection(holder)

        local root =
            holder.Character
            and holder.Character:FindFirstChild("HumanoidRootPart")

        local speed = 0
        if root then
            local av = root.AssemblyLinearVelocity
            speed = Vector3.new(av.X, 0, av.Z).Magnitude
        end

        if speed > 0 then
            Traj.heldSpeed = speed
        end

        Traj.smooth =
            Traj.heldDir * math.max(Traj.heldSpeed, 1)

        Traj.lastPos = ball.Position
        Traj.lastTime = now
        return
    end

    if not Traj.lastPos then
        Traj.lastPos = ball.Position
        Traj.lastTime = now
        Traj.velocity = ball.AssemblyLinearVelocity
        return
    end

    if now - Traj.lastVel < Traj.sample then
        return
    end

    local dt = now - Traj.lastTime
    if dt <= 0 then return end

    local v = (ball.Position - Traj.lastPos) / dt
    Traj.velocity = v

    local hv = Vector3.new(v.X, 0, v.Z)

    if hv.Magnitude > Traj.minSpeed then
        Traj.smooth = Traj.smooth:Lerp(hv, Traj.smoothing)
    else
        Traj.smooth =
            Traj.smooth:Lerp(Vector3.zero, Traj.smoothing)
    end

    Traj.lastPos = ball.Position
    Traj.lastTime = now
    Traj.lastVel = now
end

local function updateRayFilter(ball)
    local now = os.clock()
    local count = #Players:GetPlayers()

    if not Traj.filterDirty
        and Traj.filteredBall == ball
        and Traj.filteredCount == count
        and now - Traj.filterTime < 0.5
    then
        return
    end

    Traj.filterDirty = false
    Traj.filterTime = now
    Traj.filteredBall = ball
    Traj.filteredCount = count

    local list = {getVisualFolder(), ball}

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            list[#list + 1] = player.Character
        end
    end

    Traj.ray.FilterDescendantsInstances = list
end

local function predictTrajectory(ball, holder)
    table.clear(Traj.points)

    local velocity

    if holder then
        velocity =
            holderDirection(holder)
            * math.max(Traj.heldSpeed, 1)
    else
        velocity = Traj.velocity
        if velocity.Magnitude < 1.2 then
            velocity = ball.AssemblyLinearVelocity
        end
    end

    if velocity.Magnitude < 1.2 then
        return -1
    end

    local position = ball.Position
    local gravity = Vector3.new(0, -workspace.Gravity, 0)

    local total = 0
    local bounce = 0
    local firstBounce = -1

    table.insert(Traj.points, position)

    while total < Traj.time and bounce < Traj.bounces do
        local dt = Traj.step
        local nextPos =
            position
            + velocity * dt
            + 0.5 * gravity * (dt ^ 2)

        local delta = nextPos - position
        local hit = workspace:Raycast(position, delta, Traj.ray)

        if hit then
            bounce += 1
            table.insert(Traj.points, hit.Position)

            if bounce == 1 then
                firstBounce = #Traj.points
            end

            local fraction =
                delta.Magnitude > 0
                and (hit.Position - position).Magnitude / delta.Magnitude
                or 1

            local impactVelocity =
                velocity + gravity * (dt * fraction)

            velocity =
                (
                    impactVelocity
                    - 2 * impactVelocity:Dot(hit.Normal) * hit.Normal
                ) * Traj.elasticity

            position = hit.Position + hit.Normal * 0.08
            total += dt * fraction

            if velocity.Magnitude < 1.5 then
                break
            end
        else
            position = nextPos
            velocity += gravity * dt
            total += dt
            table.insert(Traj.points, position)
        end
    end

    -- Nếu chưa bounce, nối thêm điểm chạm mặt đất gần nhất.
    if bounce == 0 and #Traj.points > 0 then
        local hit = workspace:Raycast(
            Traj.points[#Traj.points],
            Vector3.new(0, -500, 0),
            Traj.ray
        )

        if hit then
            table.insert(Traj.points, hit.Position)
            firstBounce = #Traj.points
        end
    end

    return firstBounce
end

local function getBeam(index)
    local folder = getVisualFolder()

    local attachment = Traj.attachments[index]

    if not attachment or not attachment.Parent then
        attachment = Instance.new("Attachment")
        attachment.Name = "MoreModAtt_" .. index
        attachment.Parent = folder
        Traj.attachments[index] = attachment
    end

    if index > 1 then
        local beam = Traj.beams[index - 1]

        if not beam or not beam.Parent then
            beam = Instance.new("Beam")
            beam.Name = "MoreModBeam_" .. (index - 1)
            beam.Parent = folder
            Traj.beams[index - 1] = beam
        end

        beam.Attachment0 = Traj.attachments[index - 1]
        beam.Attachment1 = Traj.attachments[index]
        beam.Color = ColorSequence.new(Traj.color)
        beam.Width0 = Traj.width
        beam.Width1 = Traj.width
        beam.FaceCamera = true
        beam.Enabled = true
    end
end

local function renderTrajectory()
    if not Traj.enabled then
        return
    end

    if Traj.forceRefresh then
        Traj.lastBall = nil
        Traj.lastPos = nil
        Traj.lastTime = 0
        Traj.lastVel = 0
        Traj.filterDirty = true
        Traj.forceRefresh = false
    end

    local ball, holder = findBall()

    if not ball then
        clearTrajectory()
        return
    end

    if Traj.ball ~= ball then
        Traj.lastBall = nil
        Traj.lastPos = nil
        Traj.lastTime = 0
        Traj.lastVel = 0
        Traj.filterDirty = true
    end

    Traj.ball = ball
    Traj.holder = holder

    updateMovement(ball, holder)
    updateRayFilter(ball)

    local firstBounce = predictTrajectory(ball, holder)

    if #Traj.points < 2 then
        clearTrajectory()
        return
    end

    local maxIndex =
        firstBounce > 0 and firstBounce or #Traj.points

    local beamIndex = 1

    for i = 1, maxIndex do
        getBeam(beamIndex)
        Traj.attachments[beamIndex].WorldPosition = Traj.points[i]
        beamIndex += 1
    end

    for i = beamIndex, #Traj.attachments do
        local attachment = Traj.attachments[i]
        if attachment and attachment.Parent then
            attachment.WorldPosition = Vector3.new(0, -10000, 0)
        end

        local beam = Traj.beams[i - 1]
        if beam then
            beam.Enabled = false
        end
    end

    -- Direction arrow
    local folder = getVisualFolder()

    if not Traj.arrowBeam
        or not Traj.arrowBeam.Parent
        or not Traj.arrow0
        or not Traj.arrow0.Parent
        or not Traj.arrow1
        or not Traj.arrow1.Parent
    then
        Traj.arrow0 = Instance.new("Attachment")
        Traj.arrow1 = Instance.new("Attachment")
        Traj.arrowBeam = Instance.new("Beam")

        Traj.arrow0.Parent = folder
        Traj.arrow1.Parent = folder
        Traj.arrowBeam.Parent = folder

        Traj.arrowBeam.Attachment0 = Traj.arrow0
        Traj.arrowBeam.Attachment1 = Traj.arrow1
        Traj.arrowBeam.FaceCamera = true
    end

    local movement = Traj.smooth
    local horizontal = Vector3.new(movement.X, 0, movement.Z)

    if holder then
        horizontal =
            holderDirection(holder)
            * math.max(Traj.heldSpeed, Traj.minSpeed)
    end

    local speed = horizontal.Magnitude

    if speed < Traj.minSpeed then
        Traj.arrowBeam.Enabled = false
    else
        local direction = horizontal.Unit
        local length = math.clamp(speed * 0.12, 3, 90)

        Traj.arrow0.WorldPosition = ball.Position
        Traj.arrow1.WorldPosition =
            ball.Position + direction * length

        Traj.arrowBeam.Width0 = 0.55
        Traj.arrowBeam.Width1 = 0.30
        Traj.arrowBeam.Color =
            ColorSequence.new(Traj.color)
        Traj.arrowBeam.Enabled = true
    end
end

--========================================================--
-- COOLDOWN TRACKER
--========================================================--

local function destroyCooldownBar(entry)
    if not entry then return end

    safeDestroy(entry.label)
    safeDestroy(entry.card)
end

local function createCooldownBar(skillIdentifier, duration)
    if not Cooldown.enabled or not Cooldown.list then
        return
    end

    local skillName = "Unknown Skill"
    if typeof(skillIdentifier) == "Instance" then
        skillName = skillIdentifier.Name
    elseif typeof(skillIdentifier) == "string" or typeof(skillIdentifier) == "number" then
        skillName = "Move " .. tostring(skillIdentifier)
    elseif typeof(skillIdentifier) == "table" and skillIdentifier.Name then
        skillName = tostring(skillIdentifier.Name)
    end

    local cdTime = tonumber(duration)
    if not cdTime or cdTime <= 0 then
        return
    end

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -8, 0, 32)
    label.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    label.BorderSizePixel = 0
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.LayoutOrder = -math.floor(os.clock() * 1000000)
    label.Parent = Cooldown.list
    corner(label, 6)

    local entry = {label = label}
    table.insert(Cooldown.bars, 1, entry)

    if #Cooldown.bars > MAX_VISIBLE_BARS then
        local oldest = table.remove(Cooldown.bars, #Cooldown.bars)
        if oldest then
            destroyCooldownBar(oldest)
        end
    end

    task.spawn(function()
        local startTime = os.clock()

        while Cooldown.enabled and label.Parent do
            local remaining = cdTime - (os.clock() - startTime)
            if remaining <= 0 then
                break
            end

            label.Text = string.format("  ⏳ %s: %.1fs", skillName, remaining)
            task.wait(0.05)
        end

        destroyCooldownBar(entry)

        local idx = table.find(Cooldown.bars, entry)
        if idx then
            table.remove(Cooldown.bars, idx)
        end
    end)
end


local function findEventByNames(parent, names, classes)
    for _, name in ipairs(names) do
        local obj = parent:FindFirstChild(name, true)

        if obj then
            for _, className in ipairs(classes) do
                if obj:IsA(className) then
                    return obj
                end
            end
        end
    end

    return nil
end

local function disconnectCooldownEvents()
    disconnectList(Cooldown.connections)

    disconnect(Cooldown.messageConn)
    Cooldown.messageConn = nil
end

local function setupCooldownGui()
    if Cooldown.gui and Cooldown.gui.Parent then
        return
    end

    local sg = Instance.new("ScreenGui")
    sg.Name = "MasterCooldownTracker"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = PlayerGui
    Cooldown.gui = sg

    local status = Instance.new("TextLabel")
    status.Size = UDim2.fromOffset(250, 35)
    status.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    status.TextColor3 = Color3.fromRGB(255, 215, 0)
    status.Font = Enum.Font.GothamBold
    status.TextSize = 14
    status.Text = "Status: Normal"
    status.Visible = false
    status.Parent = sg
    corner(status, 8)
    Cooldown.status = status

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.fromOffset(230, 350)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = sg
    Cooldown.list = scroll

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 5)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll

    Cooldown.layoutConn = layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        if scroll.Parent then
            scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
        end
    end)
end

local function layoutCooldownGui()
    if not Cooldown.gui
        or not Cooldown.gui.Parent
        or not Cooldown.list
        or not Cooldown.status
    then
        return
    end

    local camera = workspace.CurrentCamera
    local vp =
        camera
        and camera.ViewportSize
        or Vector2.new(1280, 720)

    local width =
        math.min(240, math.max(190, vp.X - 24))

    local mobile = vp.X < 700

    Cooldown.list.Size =
        UDim2.fromOffset(
            width,
            math.max(160, math.min(380, vp.Y - 170))
        )

    Cooldown.list.AnchorPoint =
        Vector2.new(1, 0)

    Cooldown.list.Position =
        mobile
        and UDim2.new(1, -12, 0, 92)
        or UDim2.new(1, -20, 0.24, 0)

    Cooldown.status.Size =
        UDim2.fromOffset(width, 34)

    Cooldown.status.AnchorPoint =
        Vector2.new(1, 0)

    Cooldown.status.Position =
        mobile
        and UDim2.new(1, -12, 0, 52)
        or UDim2.new(1, -20, 0.05, 0)
end

local function setupCooldownEvents()
    disconnectCooldownEvents()

    if not Cooldown.enabled then
        return
    end

    setupCooldownGui()

    -- Source 1: ReplicatedStorage.Events.CooldownMove
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    local cooldownMove = eventsFolder and eventsFolder:FindFirstChild("CooldownMove")
    if cooldownMove and cooldownMove:IsA("RemoteEvent") then
        Cooldown.connections[#Cooldown.connections + 1] =
            cooldownMove.OnClientEvent:Connect(createCooldownBar)
    end

    -- Source 2: ReplicatedStorage.Events.UI
    local uiEvents = eventsFolder and eventsFolder:FindFirstChild("UI")
    if uiEvents then
        local cooldownBind = uiEvents:FindFirstChild("CooldownBind")
        local cooldownRemote = uiEvents:FindFirstChild("CooldownRemote")

        if cooldownBind and cooldownBind:IsA("BindableEvent") then
            Cooldown.connections[#Cooldown.connections + 1] =
                cooldownBind.Event:Connect(createCooldownBar)
        end

        if cooldownRemote and cooldownRemote:IsA("RemoteEvent") then
            Cooldown.connections[#Cooldown.connections + 1] =
                cooldownRemote.OnClientEvent:Connect(createCooldownBar)
        end
    end

    -- Fallback: other games/versions may place the same remotes elsewhere.
    local bindable = findEventByNames(
        ReplicatedStorage,
        {"CooldownBind", "CooldownEvent", "Cooldown"},
        {"BindableEvent"}
    )
    local remote = findEventByNames(
        ReplicatedStorage,
        {"CooldownRemote", "CooldownEvent", "Cooldown"},
        {"RemoteEvent"}
    )

    if bindable and not table.find(Cooldown.connections, bindable) then
        Cooldown.connections[#Cooldown.connections + 1] =
            bindable.Event:Connect(createCooldownBar)
    end
    if remote then
        Cooldown.connections[#Cooldown.connections + 1] =
            remote.OnClientEvent:Connect(createCooldownBar)
    end

    -- Awakening status.
    local messageRemote = findEventByNames(
        ReplicatedStorage,
        {"SendMessage", "Messages"},
        {"RemoteEvent"}
    )

    if messageRemote and messageRemote.Name == "SendMessage" then
        Cooldown.messageConn = messageRemote.OnClientEvent:Connect(function(message)
            if typeof(message) ~= "string" or not Cooldown.status then
                return
            end

            if string.find(message, "%[local player%] Received Awakening") then
                Cooldown.status.Text = "HAVE AWAKENING"
                Cooldown.status.Visible = true
            elseif string.find(message, "Giving Awakening In 5 Seconds%.%.%.") then
                Cooldown.status.Text = "Status: Normal"
                Cooldown.status.Visible = false
            end
        end)
    end

    -- Source 3: UseMove hook. Install only once, if the executor exposes
    -- hookmetamethod/getnamecallmethod. This observes the returned cooldown.
    local useMove = eventsFolder and eventsFolder:FindFirstChild("UseMove")
    if useMove and useMove:IsA("RemoteFunction")
        and not Cooldown.useMoveHookInstalled
        and type(hookmetamethod) == "function"
        and type(getnamecallmethod) == "function"
    then
        local oldNamecall
        local ok = pcall(function()
            oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                local args = {...}

                local result = table.pack(oldNamecall(self, ...))

                if self == useMove
                    and (method == "InvokeServer" or method == "invokeServer")
                then
                    local moveId = args[1]
                    local cooldownTime = result[1]
                    if cooldownTime then
                        createCooldownBar(moveId, cooldownTime)
                    end
                end

                return table.unpack(result, 1, result.n)
            end)
        end)

        if ok and oldNamecall then
            Cooldown.useMoveHookInstalled = true
        end
    end
end

local function setCooldown(on)
    Cooldown.enabled = on

    if on then
        setupCooldownEvents()
        setupCooldownGui()
        layoutCooldownGui()
        setStatus("Show CD ON")
    else
        disconnectCooldownEvents()

        for _, entry in ipairs(Cooldown.bars) do
            destroyCooldownBar(entry)
        end

        table.clear(Cooldown.bars)

        if Cooldown.status then
            Cooldown.status.Visible = false
        end

        setStatus("Show CD OFF")
    end

    return true
end

--========================================================--
-- DISPLAY CHARACTER
--========================================================--

local characterGui = nil
local characterList = nil

local function displayCharacter()
    if characterGui and characterGui.Parent then
        characterGui.Enabled = not characterGui.Enabled
        return
    end

    characterGui = Instance.new("ScreenGui")
    characterGui.Name = "MoreModCharacterDisplay"
    characterGui.ResetOnSpawn = false
    characterGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    characterGui.DisplayOrder = 101
    characterGui.Parent = PlayerGui

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(300, 320)
    panel.Position = UDim2.new(0.5, -150, 0.5, -160)
    panel.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
    panel.BorderSizePixel = 0
    panel.Parent = characterGui
    corner(panel, 10)
    stroke(panel)

    local header = label(panel, "CHARACTER DISPLAY", 12, 8, 220, 28, 15)
    header.Font = Enum.Font.GothamBold

    local closeCharacter = button(panel, "X", 260, 8, 28, 28)
    bind(closeCharacter.MouseButton1Click, function()
        if characterGui then
            characterGui.Enabled = false
        end
    end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(10, 48)
    scroll.Size = UDim2.new(1, -20, 1, -58)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = panel

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 5)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = scroll
    characterList = scroll

    bind(list:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        if scroll.Parent then
            scroll.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 8)
        end
    end)

    local function refresh()
        for _, child in ipairs(scroll:GetChildren()) do
            if child:IsA("TextLabel") then
                child:Destroy()
            end
        end

        local shown = 0
        for _, player in ipairs(Players:GetPlayers()) do
            local values = player:FindFirstChild("Values")
            local value = values and values:FindFirstChild("CharacterName")

            if value and value.Value ~= nil and tostring(value.Value) ~= "" then
                shown += 1

                local row = Instance.new("TextLabel")
                row.Size = UDim2.new(1, -4, 0, 28)
                row.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
                row.BorderSizePixel = 0
                row.TextColor3 = Color3.fromRGB(255, 255, 255)
                row.Font = Enum.Font.GothamBold
                row.TextSize = 12
                row.TextXAlignment = Enum.TextXAlignment.Left
                row.Text = string.format("  %s  →  %s", player.Name, tostring(value.Value))
                row.Parent = scroll
                corner(row, 6)
            end
        end

        if shown == 0 then
            local row = Instance.new("TextLabel")
            row.Size = UDim2.new(1, -4, 0, 28)
            row.BackgroundTransparency = 1
            row.TextColor3 = Color3.fromRGB(170, 170, 180)
            row.Font = Enum.Font.Gotham
            row.TextSize = 12
            row.Text = "  No CharacterName values found."
            row.Parent = scroll
        end

        setStatus(string.format("Character info found: %d", shown))
    end

    refresh()
end

--========================================================--
-- MAIN UI
--========================================================--

local gui = Instance.new("ScreenGui")
gui.Name = "BallControllerMoreMod"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100
gui:SetAttribute("MoreModVersion", VERSION)
gui.Parent = PlayerGui

Runtime.gui = gui

local frame = Instance.new("Frame")
frame.Name = "MoreModFrame"
frame.Size = UDim2.fromOffset(430, 370)
frame.Position = UDim2.fromOffset(390, 280)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
frame.BorderSizePixel = 0
frame.Parent = gui
corner(frame, 12)
stroke(frame)

Runtime.frame = frame

local scale = Instance.new("UIScale")
scale.Scale = 1
scale.Parent = frame

local title =
    label(
        frame,
        "MORE MOD",
        12,
        8,
        250,
        32,
        17
    )
title.Font = Enum.Font.GothamBold

local close =
    button(
        frame,
        "X",
        390,
        8,
        28,
        28
    )

local hint =
    label(
        frame,
        "Standalone popup • Visual / utility mods • Drag title to move",
        12,
        45,
        406,
        42,
        11
    )
hint.TextWrapped = true
hint.TextColor3 =
    Color3.fromRGB(175, 175, 185)

local antiShakeButton =
    button(
        frame,
        "ANTI SCREEN SHAKE: OFF",
        12,
        94,
        196,
        36
    )

local antiBlurButton =
    button(
        frame,
        "ANTI BLUR: OFF",
        222,
        94,
        196,
        36
    )

local trajectoryButton =
    button(
        frame,
        "BALL TRAJECTORY: OFF",
        12,
        138,
        196,
        36
    )

local characterButton =
    button(
        frame,
        "DISPLAY CHARACTER [ACTION]",
        222,
        138,
        196,
        36
    )

local refreshButton =
    button(
        frame,
        "REFRESH TRAJECTORY",
        12,
        182,
        196,
        36
    )

local cooldownButton =
    button(
        frame,
        "SHOW CD: OFF",
        222,
        182,
        196,
        36
    )

local status =
    label(
        frame,
        "STATUS: READY",
        12,
        314,
        406,
        22,
        11
    )

status.TextColor3 =
    Color3.fromRGB(150, 150, 160)

Runtime.status = status

Runtime.buttons = {
    antiShakeButton,
    antiBlurButton,
    trajectoryButton,
    characterButton,
    refreshButton,
    cooldownButton,
}

--========================================================--
-- BUTTON LOGIC
--========================================================--

bind(close.MouseButton1Click, function()
    if Runtime.destroyed then return end

    -- X = CHỈ ẨN POPUP.
    -- Không Cleanup, không disconnect connection, không tắt feature.
    Runtime.uiVisible = false
    if Runtime.gui and Runtime.gui.Parent then
        Runtime.gui.Enabled = false
    end
end)

bind(antiShakeButton.MouseButton1Click, function()
    local nextValue = not State.antiShake

    if antiShake(nextValue) then
        State.antiShake = nextValue
    end

    antiShakeButton.Text =
        "ANTI SCREEN SHAKE: "
        .. (State.antiShake and "ON" or "OFF")
end)

bind(antiBlurButton.MouseButton1Click, function()
    local nextValue = not State.antiBlur

    if antiBlur(nextValue) then
        State.antiBlur = nextValue
    end

    antiBlurButton.Text =
        "ANTI BLUR: "
        .. (State.antiBlur and "ON" or "OFF")
end)

bind(trajectoryButton.MouseButton1Click, function()
    State.trajectory = not State.trajectory
    Traj.enabled = State.trajectory

    if not Traj.enabled then
        clearTrajectory()
        setStatus("Trajectory OFF")
    else
        Traj.forceRefresh = true
        setStatus("Trajectory ON")
    end

    trajectoryButton.Text =
        "BALL TRAJECTORY: "
        .. (State.trajectory and "ON" or "OFF")
end)

bind(refreshButton.MouseButton1Click, function()
    if not Traj.enabled then
        setStatus("Trajectory is OFF")
        return
    end

    clearTrajectory()
    Traj.forceRefresh = true
    Traj.filterDirty = true

    setStatus("Trajectory refreshed")
end)

bind(cooldownButton.MouseButton1Click, function()
    State.cooldown = not State.cooldown

    setCooldown(State.cooldown)

    cooldownButton.Text =
        "SHOW CD: "
        .. (State.cooldown and "ON" or "OFF")
end)

bind(characterButton.MouseButton1Click, displayCharacter)

makeDraggable(frame, title)

--========================================================--
-- RUNTIME WATCHERS
--========================================================--

bind(RunService.RenderStepped, function()
    if Runtime.destroyed then return end

    if Traj.enabled then
        renderTrajectory()
    end
end)

bind(workspace.DescendantAdded, function(obj)
    if not Traj.enabled then return end

    local name = string.lower(obj.Name)

    if obj.Name == "TrajectoryVisuals"
        or name == "ball"
        or name == "soccerball"
        or name == "football"
        or name == "tpsball"
    then
        Traj.forceRefresh = true
        Traj.filterDirty = true
    end
end)

bind(workspace.DescendantRemoving, function(obj)
    if obj == Traj.ball
        or obj == Traj.visualFolder
        or obj == Traj.arrowBeam
        or obj == Traj.arrow0
        or obj == Traj.arrow1
    then
        clearTrajectory()
        Traj.forceRefresh = true
    end
end)

bind(LP.CharacterAdded, function()
    clearTrajectory()
    Traj.forceRefresh = true

    if Cooldown.enabled then
        task.defer(setupCooldownEvents)
    end
end)

bind(RunService.RenderStepped, function()
    if Cooldown.enabled then
        layoutCooldownGui()
    end
end)

--========================================================--
-- UI TOGGLE
-- Chỉ ẩn/hiện giao diện, KHÔNG dừng trajectory/cooldown/watchers.
--========================================================--

local function ToggleUI()
    if Runtime.destroyed or not Runtime.gui or not Runtime.gui.Parent then
        return false
    end

    Runtime.uiVisible = not Runtime.uiVisible
    Runtime.gui.Enabled = Runtime.uiVisible

    if Runtime.uiVisible then
        if State.cooldown then
            setStatus("Show CD ON")
        else
            setStatus("READY")
        end
    end

    return Runtime.uiVisible
end

--========================================================--
-- CLEANUP
--========================================================--

local function Cleanup()
    if Runtime.destroyed then
        -- vẫn tiếp tục cleanup để bảo đảm idempotent
    end

    Runtime.destroyed = true

    State.antiShake = false
    State.antiBlur = false
    State.trajectory = false
    State.cooldown = false

    Traj.enabled = false
    clearTrajectory()

    disconnect(FeatureConnections.antiBlur)
    FeatureConnections.antiBlur = nil

    disconnect(CameraShakeWatcher)
    CameraShakeWatcher = nil
    disconnect(CameraShakePlayerWatcher)
    CameraShakePlayerWatcher = nil

    -- Cleanup bản cũ phải tắt hẳn Anti Screen Shake và trả object về trạng thái bình thường.
    State.antiShake = false
    restoreCameraShake()

    disconnectCooldownEvents()

    for _, entry in ipairs(Cooldown.bars) do
        destroyCooldownBar(entry)
    end

    table.clear(Cooldown.bars)

    disconnect(Cooldown.layoutConn)
    Cooldown.layoutConn = nil

    disconnectList(Connections)

    safeDestroy(Cooldown.gui)
    Cooldown.gui = nil
    Cooldown.status = nil
    Cooldown.list = nil

    safeDestroy(characterGui)
    characterGui = nil
    characterList = nil

    safeDestroy(Runtime.gui)
    Runtime.gui = nil
    Runtime.frame = nil
    Runtime.status = nil

    -- Xóa các visual còn sót lại của riêng MoreMod.
    local folder = workspace:FindFirstChild("TrajectoryVisuals")
    if folder then
        for _, obj in ipairs(folder:GetChildren()) do
            if obj.Name:sub(1, 12) == "MoreModAtt_"
                or obj.Name:sub(1, 13) == "MoreModBeam_"
            then
                safeDestroy(obj)
            end
        end
    end

    if ENV[KEY]
        and ENV[KEY].Cleanup == Cleanup
    then
        ENV[KEY] = nil
    end
end

ENV[KEY] = {
    VERSION = VERSION,
    Cleanup = Cleanup,
    ToggleUI = ToggleUI,
    GUI = gui,
}

-- Không xóa GUI cũ ở đây:
-- cơ chế re-run đã xử lý bằng ToggleUI phía trên.

setStatus("READY")
print("[More Mod Standalone] loaded")
