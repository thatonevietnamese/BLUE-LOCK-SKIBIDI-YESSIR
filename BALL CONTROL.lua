local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local BALL_NAME = "Ball"
local MIN_SPEED = 1
local MAX_SPEED = 1000
local DEFAULT_CONTROL_KEY = Enum.KeyCode.F
local DEFAULT_STEAL_DISTANCE = 3
local SAE_PASS_HEIGHT = 300
local SAE_PASS_SPEED = 260
local DEFAULT_TP_TIME = 1.5
local GK_ROLE_NAMES = {"gk", "goalkeeper", "goal keeper", "keeper"}
local GK_TP_OFFSET = Vector3.new(0, 2.5, 0)
local TP_GOAL_OFFSET = Vector3.new(0, 3, 10)
local SHOOT_FORCE = 100

local AUTO_STEAL_SCAN_INTERVAL = 0.08
local BALL_CACHE_REBUILD_COOLDOWN = 0.04

local modeSettings = {
	[1] = {speed = 60},
	[2] = {speed = 140},
}

local State = {
	mode = 1,
	controlKey = DEFAULT_CONTROL_KEY,

	enabled = false,
	anchorEnabled = true,
	forceUnanchorActive = false,

	stealBallEnabled = false,
	autoGoalEnabled = false,
	autoGoalExecuting = false,
	autoGoalRunId = 0,

	saePassEnabled = false,
	selectedTarget = nil,
	targetHighlight = nil,
	saePassActive = false,
	saePassStage = "IDLE",
	saePassBall = nil,
	saePassTarget = nil,

	changingControlKey = false,
	leftMouseHeld = false,
	rightMouseHeld = false,

	minimized = false,
	settingsOpen = false,
	uiScale = 1,

	autoStealOffOnGet = true,

	tpDuration = DEFAULT_TP_TIME,
	tpActive = false,
	tpStartedAt = 0,
	tpReturnCFrame = nil,
	tpGoalActive = false,
	tpFollowTarget = nil,
	tpFollowBall = nil,

	gkSpecialEnabled = false,
	gkLastGoalPart = nil,

	advanceMode = false,
	advanceKeys = {
		W = false,
		A = false,
		S = false,
		D = false,
		Q = false,
		E = false
	},

	ronaldoAdvanceEnabled = false,
	ronaldoAdvanceTargetPosition = nil,
	ronaldoAdvanceTargetPart = nil,
	ronaldoAdvanceActive = false,
	ronaldoAdvanceBall = nil,
	ronaldoAdvanceTouchedConnection = nil,
	ronaldoAdvanceStartTime = 0,
}

local Connections = {}
local CharacterConnections = {}
local PlayerConnections = {}

local BallTracker = {
	State = "UNKNOWN",
	Holder = nil,
	Ball = nil,
	LastRebuild = 0,
	RebuildQueued = false,
}

local notificationHolder
local notify

-- CLEANUP

local function DisconnectConnection(connection)
	if connection then
		pcall(function()
			connection:Disconnect()
		end)
	end
end

local function DisconnectCharacterConnections(plr)
	local list = CharacterConnections[plr]

	if list then
		for _, connection in ipairs(list) do
			DisconnectConnection(connection)
		end
	end

	CharacterConnections[plr] = nil
end

local function DisconnectPlayerConnections(plr)
	local list = PlayerConnections[plr]

	if list then
		for _, connection in ipairs(list) do
			DisconnectConnection(connection)
		end
	end

	PlayerConnections[plr] = nil
end

local function Bind(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(Connections, connection)
	return connection
end

local function GetEnvironment()
	local env

	pcall(function()
		env = getgenv()
	end)

	return env or _G
end

local GlobalEnv = GetEnvironment()
local oldStop = GlobalEnv.__BALL_CONTROLLER_V4_STOP

if oldStop then
	pcall(oldStop)
end

local function StopController()
	for _, connection in ipairs(Connections) do
		DisconnectConnection(connection)
	end

	table.clear(Connections)

	for plr, _ in pairs(CharacterConnections) do
		DisconnectCharacterConnections(plr)
	end

	for plr, _ in pairs(PlayerConnections) do
		DisconnectPlayerConnections(plr)
	end

	local oldGui = playerGui:FindFirstChild("BallController")

	if oldGui then
		oldGui:Destroy()
	end
end

GlobalEnv.__BALL_CONTROLLER_V4_STOP = StopController

-- NOTIFICATION

notify = function(titleText, bodyText, duration)
	duration = duration or 2.2

	if not notificationHolder or not notificationHolder.Parent then
		return
	end

	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(280, 58)
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, -65)
	card.BackgroundColor3 = Color3.fromRGB(27, 27, 34)
	card.BorderSizePixel = 0
	card.Parent = notificationHolder


	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 9)
	uiCorner.Parent = card

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = Color3.fromRGB(65, 65, 80)
	uiStroke.Transparency = 0.15
	uiStroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -18, 0, 22)
	title.Position = UDim2.fromOffset(9, 5)
	title.BackgroundTransparency = 1
	title.Text = tostring(titleText)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
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

	TweenService:Create(
		card,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad),
		{Position = UDim2.new(0.5, 0, 0, 8)}
	):Play()

	task.delay(duration, function()
		if not card.Parent then
			return
		end

		TweenService:Create(
			card,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad),
			{Position = UDim2.new(0.5, 0, 0, -65)}
		):Play()

		task.delay(0.22, function()
			if card.Parent then
				card:Destroy()
			end
		end)
	end)
end

-- CHARACTER

local character
local humanoid
local rootPart

local savedWalkSpeed
local savedJumpPower
local savedAutoRotate
local playerWasLocked = false

local function updateCharacter()
	character = player.Character

	if not character then
		humanoid = nil
		rootPart = nil
		return false
	end

	humanoid = character:FindFirstChildOfClass("Humanoid")
	rootPart = character:FindFirstChild("HumanoidRootPart")

	return humanoid ~= nil and rootPart ~= nil
end

updateCharacter()

local function savePlayerState()
	if not humanoid then
		return
	end

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

local function unlockPlayer()
	if not updateCharacter() then
		playerWasLocked = false
		savedWalkSpeed = nil
		savedJumpPower = nil
		savedAutoRotate = nil
		return
	end

	if playerWasLocked then
		if savedWalkSpeed ~= nil then
			humanoid.WalkSpeed = savedWalkSpeed
		end

		if savedJumpPower ~= nil then
			humanoid.JumpPower = savedJumpPower
		end

		if savedAutoRotate ~= nil then
			humanoid.AutoRotate = savedAutoRotate
		end
	end

	playerWasLocked = false
	savedWalkSpeed = nil
	savedJumpPower = nil
	savedAutoRotate = nil
end

local function applyModeLock()
	if not updateCharacter() then
		return
	end

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

	if rootPart then
		rootPart.Anchored = false
	end

	unlockPlayer()

	notify("ANCHOR", "Force Unanchor executed", 1.5)
end

-- BALL CACHE

local function isMatchPlayer(plr)
	if not plr or not plr.Team then
		return false
	end

	local teamName = string.lower(plr.Team.Name)

	return string.find(teamName, "home", 1, true) ~= nil
		or string.find(teamName, "away", 1, true) ~= nil
end

local function findBallInCharacter(char)
	if not char then
		return nil
	end

	local found = char:FindFirstChild(BALL_NAME, true)

	if found and found:IsA("BasePart") then
		return found
	end

	return nil
end

local function findFreeBall()
	local direct = workspace:FindFirstChild(BALL_NAME)

	if direct and direct:IsA("BasePart") then
		return direct
	end

	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("BasePart") and string.lower(obj.Name) == string.lower(BALL_NAME) then
			return obj
		end
	end

	return nil
end

local function RebuildBallCache(force)
	local now = os.clock()

	if not force and now - BallTracker.LastRebuild < BALL_CACHE_REBUILD_COOLDOWN then
		return BallTracker.State, BallTracker.Holder, BallTracker.Ball
	end

	BallTracker.LastRebuild = now
	BallTracker.RebuildQueued = false
	BallTracker.State = "UNKNOWN"
	BallTracker.Holder = nil
	BallTracker.Ball = nil

	for _, plr in ipairs(Players:GetPlayers()) do
		if isMatchPlayer(plr) then
			local char = plr.Character
			local ball = findBallInCharacter(char)

			if ball then
				BallTracker.State = "HELD"
				BallTracker.Holder = plr
				BallTracker.Ball = ball
				return "HELD", plr, ball
			end
		end
	end

	local freeBall = findFreeBall()

	if freeBall then
		BallTracker.State = "FREE"
		BallTracker.Holder = nil
		BallTracker.Ball = freeBall
		return "FREE", nil, freeBall
	end

	BallTracker.State = "MISSING"
	BallTracker.Holder = nil
	BallTracker.Ball = nil

	return "MISSING", nil, nil
end

local function QueueBallCacheRebuild()
	if BallTracker.RebuildQueued then
		return
	end

	BallTracker.RebuildQueued = true

	task.defer(function()
		if BallTracker.RebuildQueued then
			RebuildBallCache(false)
		end
	end)
end

local function GetCachedBallState()
	local state = BallTracker.State
	local holder = BallTracker.Holder
	local ball = BallTracker.Ball

	if state == "HELD" then
		if not holder or not holder.Parent or not holder.Character then
			QueueBallCacheRebuild()
			return RebuildBallCache(false)
		end

		if not ball or not ball.Parent or not ball:IsDescendantOf(holder.Character) then
			QueueBallCacheRebuild()
			return RebuildBallCache(false)
		end

		return state, holder, ball
	end

	if state == "FREE" then
		if not ball or not ball.Parent then
			local freeBall = findFreeBall()

			if freeBall then
				BallTracker.State = "FREE"
				BallTracker.Ball = freeBall
				return "FREE", nil, freeBall
			end

			QueueBallCacheRebuild()
			return RebuildBallCache(false)
		end

		return "FREE", nil, ball
	end

	if state == "MISSING" then
		local freeBall = findFreeBall()

		if freeBall then
			BallTracker.State = "FREE"
			BallTracker.Ball = freeBall
			return "FREE", nil, freeBall
		end
	end

	return RebuildBallCache(false)
end

local function getBallState()
	return GetCachedBallState()
end

local function localHasBall()
	local state, holder = GetCachedBallState()
	return state == "HELD" and holder == player
end

local function getPlayerRoot(plr)
	if not plr or not plr.Character then
		return nil
	end

	return plr.Character:FindFirstChild("HumanoidRootPart")
end

local function sameTeam(plr)
	return plr and player.Team and plr.Team == player.Team
end

local function attachCharacterBallTracking(plr, char)
	if not plr or not char then
		return
	end

	DisconnectCharacterConnections(plr)

	local list = {}

	local function addConnection(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(list, connection)
	end

	local initialBall = findBallInCharacter(char)

	if initialBall then
		if not BallTracker.Holder then
			BallTracker.State = "HELD"
			BallTracker.Holder = plr
			BallTracker.Ball = initialBall
		elseif BallTracker.Holder ~= plr then
			QueueBallCacheRebuild()
		end
	end

	addConnection(char.DescendantAdded, function(descendant)
		if descendant.Name ~= BALL_NAME or not descendant:IsA("BasePart") then
			return
		end

		if not BallTracker.Holder then
			BallTracker.State = "HELD"
			BallTracker.Holder = plr
			BallTracker.Ball = descendant
			return
		end

		if BallTracker.Holder ~= plr then
			QueueBallCacheRebuild()
		end
	end)

	addConnection(char.DescendantRemoving, function(descendant)
		if descendant ~= BallTracker.Ball then
			return
		end

		if BallTracker.Holder == plr then
			BallTracker.State = "UNKNOWN"
			BallTracker.Holder = nil
			BallTracker.Ball = nil
			QueueBallCacheRebuild()
		end
	end)

	addConnection(char.AncestryChanged, function(_, parent)
		if parent == nil then
			if BallTracker.Holder == plr then
				BallTracker.State = "UNKNOWN"
				BallTracker.Holder = nil
				BallTracker.Ball = nil
				QueueBallCacheRebuild()
			end
		end
	end)

	CharacterConnections[plr] = list
end

local function attachPlayerTracking(plr)
	if not plr then
		return
	end

	DisconnectPlayerConnections(plr)

	local list = {}

	local function addConnection(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(list, connection)
	end

	if plr.Character then
		attachCharacterBallTracking(plr, plr.Character)
	end

	addConnection(plr.CharacterAdded, function(char)
		attachCharacterBallTracking(plr, char)
		QueueBallCacheRebuild()
	end)

	addConnection(plr.CharacterRemoving, function(char)
		if BallTracker.Holder == plr then
			BallTracker.State = "UNKNOWN"
			BallTracker.Holder = nil
			BallTracker.Ball = nil
		end

		DisconnectCharacterConnections(plr)
		QueueBallCacheRebuild()
	end)

	PlayerConnections[plr] = list
end

local function initializeBallTracker()
	for _, plr in ipairs(Players:GetPlayers()) do
		attachPlayerTracking(plr)
	end

	RebuildBallCache(true)
end

Bind(Players.PlayerAdded, function(plr)
	attachPlayerTracking(plr)
	QueueBallCacheRebuild()
end)

Bind(Players.PlayerRemoving, function(plr)
	if BallTracker.Holder == plr then
		BallTracker.State = "UNKNOWN"
		BallTracker.Holder = nil
		BallTracker.Ball = nil
	end

	DisconnectCharacterConnections(plr)
	DisconnectPlayerConnections(plr)

	QueueBallCacheRebuild()
end)

initializeBallTracker()

-- REMOTE

local shootBallRemote
local shootRemoteReady = false

local function resolveShootRemotes()
	local ok, remote = pcall(function()
		local events = ReplicatedStorage:FindFirstChild("Events")
		return events and events:FindFirstChild("ShootBall")
	end)

	shootBallRemote = ok and remote or nil
	shootRemoteReady = shootBallRemote ~= nil and shootBallRemote:IsA("RemoteEvent")

	return shootBallRemote
end

resolveShootRemotes()

local function fireShootRemote(direction, force, thirdArg)
	if not shootRemoteReady or not shootBallRemote then
		resolveShootRemotes()
	end

	if not shootRemoteReady or not shootBallRemote then
		notify("SHOOT REMOTE", "Không tìm thấy Events.ShootBall", 1.5)
		return false
	end

	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.001 then
		return false
	end

	direction = direction.Unit
	force = math.clamp(tonumber(force) or MIN_SPEED, MIN_SPEED, MAX_SPEED)

	return pcall(function()
		shootBallRemote:FireServer(
			direction,
			force,
			thirdArg == nil and false or thirdArg
		)
	end)
end

-- GUI HELPERS

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function stroke(parent, color, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(60, 60, 70)
	s.Transparency = transparency or 0.2
	s.Parent = parent
	return s
end

local function makeButton(parent, text, x, y, w, h)
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

local function makeLabel(parent, text, x, y, w, h, size)
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

local function makeBox(parent, value, x, y, w, h)
	local b = Instance.new("TextBox")
	b.Size = UDim2.fromOffset(w, h)
	b.Position = UDim2.fromOffset(x, y)
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 47)
	b.BorderSizePixel = 0
	b.Text = tostring(value)
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.PlaceholderColor3 = Color3.fromRGB(130, 130, 140)
	b.TextSize = 12
	b.Font = Enum.Font.GothamMedium
	b.ClearTextOnFocus = false
	b.Parent = parent
	corner(b, 7)
	return b
end

-- MAIN UI

local gui = Instance.new("ScreenGui")
gui.Name = "BallController"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(350, 445)
main.Position = UDim2.new(0, 25, 0.5, -222)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
main.BorderSizePixel = 0
main.Parent = gui

corner(main, 12)
stroke(main, Color3.fromRGB(60, 60, 70), 0.2)

local title = makeLabel(main, "⚽ BALL CONTROLLER V4.1", 10, 5, 215, 35, 18)
title.Font = Enum.Font.GothamBold

local zoomOutButton = makeButton(main, "-", 228, 10, 26, 28)
zoomOutButton.TextSize = 18

local zoomInButton = makeButton(main, "+", 256, 10, 26, 28)
zoomInButton.TextSize = 18

local minimizeButton = makeButton(main, "—", 312, 10, 28, 28)
minimizeButton.TextSize = 18

local mainScale = Instance.new("UIScale")
mainScale.Scale = 1
mainScale.Parent = main

local statusLabel = makeLabel(main, "Status: READY", 10, 42, 320, 22, 13)
local ballStatus = makeLabel(main, "BALL: SEARCHING...", 10, 64, 320, 22, 12)

local controlButton = makeButton(main, "CONTROL KEY: F", 10, 92, 160, 36)
local modeButton = makeButton(main, "MODE: 1 [CAMERA]", 180, 92, 160, 36)
local anchorButton = makeButton(main, "ANCHOR: ON", 10, 136, 160, 36)
local forceUnanchorButton = makeButton(main, "FORCE UNANCHOR", 180, 136, 160, 36)
local stealButton = makeButton(main, "STEAL BALL: OFF", 10, 180, 160, 36)
local saeButton = makeButton(main, "SAE PASS: OFF", 180, 180, 160, 36)
local settingsButton = makeButton(main, "⚙ SETTINGS", 10, 224, 160, 36)
local statusButton = makeButton(main, "BALL STATUS: ON", 180, 224, 160, 36)
local tpButton = makeButton(main, "TP RETURN", 10, 268, 150, 36)
local tpGoalButton = makeButton(main, "TP GOAL", 170, 268, 170, 36)
local tpTimeBox = makeBox(main, State.tpDuration, 250, 310, 90, 36)

local info = makeLabel(
	main,
	"F = action theo mode.\n"
		.. "Mode 1: control bóng theo camera.\n"
		.. "Mode 2: Ronaldo kick / Advance.\n"
		.. "RMB logo = center UI.\n"
		.. "TP Return/GK = follow bóng.",
	10,
	350,
	330,
	75,
	11
)

info.TextWrapped = true
info.TextYAlignment = Enum.TextYAlignment.Top
info.TextColor3 = Color3.fromRGB(145, 145, 155)

local restoreButton = makeButton(gui, "⚽", 0, 0, 48, 48)
restoreButton.Visible = true
restoreButton.TextSize = 23
corner(restoreButton, 24)
stroke(restoreButton, Color3.fromRGB(65, 65, 75), 0.1)

notificationHolder = Instance.new("Frame")
notificationHolder.Name = "Notifications"
notificationHolder.Size = UDim2.fromOffset(320, 300)
notificationHolder.AnchorPoint = Vector2.new(0.5, 0)
notificationHolder.Position = UDim2.new(0.5, 0, 0, 0)
notificationHolder.BackgroundTransparency = 1
notificationHolder.Parent = gui

local notificationLayout = Instance.new("UIListLayout")
notificationLayout.Padding = UDim.new(0, 7)
notificationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
notificationLayout.VerticalAlignment = Enum.VerticalAlignment.Top
notificationLayout.Parent = notificationHolder

-- STATUS UI

local statusPanel = Instance.new("Frame")
statusPanel.Name = "BallStatusPanel"
statusPanel.Size = UDim2.fromOffset(245, 125)
statusPanel.Position = UDim2.new(0, 390, 0, 80)
statusPanel.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
statusPanel.BorderSizePixel = 0
statusPanel.Parent = gui

corner(statusPanel, 10)
stroke(statusPanel, Color3.fromRGB(60, 60, 70), 0.15)

local statusScale = Instance.new("UIScale")
statusScale.Scale = 1
statusScale.Parent = statusPanel

local statusTitle = makeLabel(statusPanel, "⚽ BALL STATUS", 10, 5, 170, 25, 14)
statusTitle.Font = Enum.Font.GothamBold

local statusMin = makeButton(statusPanel, "—", 180, 6, 25, 23)
local statusClose = makeButton(statusPanel, "×", 210, 6, 25, 23)
local statusState = makeLabel(statusPanel, "STATUS: SEARCHING", 10, 35, 220, 22, 12)
local statusOwner = makeLabel(statusPanel, "OWNER: —", 10, 58, 220, 22, 12)
local statusPlayer = makeLabel(statusPanel, "CONTROL: OFF", 10, 81, 220, 22, 12)

local statusMini = false
local statusExpandedSize = UDim2.fromOffset(245, 125)
local statusMiniSize = UDim2.fromOffset(245, 34)

local function clampGuiPosition(frame)
	camera = workspace.CurrentCamera

	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
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

	frame.Position = UDim2.fromOffset(x, y)
end

local function setStatusMini(value)
	statusMini = value
	statusPanel.Size = value and statusMiniSize or statusExpandedSize

	statusState.Visible = not value
	statusOwner.Visible = not value
	statusPlayer.Visible = not value

	statusMin.Text = value and "+" or "—"

	task.defer(function()
		clampGuiPosition(statusPanel)
	end)
end

Bind(statusMin.MouseButton1Click, function()
	setStatusMini(not statusMini)
end)

Bind(statusClose.MouseButton1Click, function()
	statusPanel.Visible = false
	statusButton.Text = "BALL STATUS: OFF"
end)

local draggingStatus = false
local dragStartStatus
local dragStartPositionStatus

Bind(statusTitle.InputBegan, function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	draggingStatus = true
	dragStartStatus = input.Position
	dragStartPositionStatus = statusPanel.Position

	local changedConnection
	changedConnection = input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End then
			draggingStatus = false
			DisconnectConnection(changedConnection)
			changedConnection = nil
		end
	end)
end)

Bind(UserInputService.InputChanged, function(input)
	if not draggingStatus or input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end

	local delta = input.Position - dragStartStatus

	local x = dragStartPositionStatus.X.Offset + delta.X
	local y = dragStartPositionStatus.Y.Offset + delta.Y

	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

	x = math.clamp(
		x,
		0,
		math.max(0, viewport.X - statusPanel.AbsoluteSize.X)
	)

	y = math.clamp(
		y,
		0,
		math.max(0, viewport.Y - statusPanel.AbsoluteSize.Y)
	)

	statusPanel.Position = UDim2.fromOffset(x, y)
end)

-- SETTINGS

local settingsFrame = Instance.new("Frame")
settingsFrame.Name = "Settings"
settingsFrame.Size = UDim2.fromOffset(490, 320)
settingsFrame.Position = UDim2.new(0, 390, 0.5, -160)
settingsFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
settingsFrame.BorderSizePixel = 0
settingsFrame.Visible = false
settingsFrame.Parent = gui

corner(settingsFrame, 12)
stroke(settingsFrame, Color3.fromRGB(60, 60, 70), 0.15)

local settingsTitle = makeLabel(settingsFrame, "⚙ BALL SETTINGS", 12, 8, 270, 32, 17)
settingsTitle.Font = Enum.Font.GothamBold

local settingsZoomOutButton = makeButton(settingsFrame, "-", 412, 8, 26, 28)
local settingsZoomInButton = makeButton(settingsFrame, "+", 440, 8, 26, 28)
local closeSettings = makeButton(settingsFrame, "X", 454, 8, 28, 28)

local settingsScale = Instance.new("UIScale")
settingsScale.Scale = 1
settingsScale.Parent = settingsFrame

local tabs = {}
local tabNames = {"GENERAL", "MODE 1", "MODE 2"}

for i, name in ipairs(tabNames) do
	tabs[i] = makeButton(
		settingsFrame,
		name,
		10 + (i - 1) * 110,
		48,
		104,
		30
	)
end

local settingsContent = Instance.new("Frame")
settingsContent.Size = UDim2.new(1, -20, 1, -90)
settingsContent.Position = UDim2.fromOffset(10, 88)
settingsContent.BackgroundTransparency = 1
settingsContent.Parent = settingsFrame

local generalTitle = makeLabel(settingsContent, "GENERAL SETTINGS", 10, 8, 220, 24, 13)
generalTitle.Font = Enum.Font.GothamBold

local generalControlLabel = makeLabel(settingsContent, "CONTROL KEY", 10, 38, 110, 25, 12)
local generalControlButton = makeButton(settingsContent, "F", 120, 34, 120, 32)

local generalAnchorLabel = makeLabel(settingsContent, "ANCHOR", 10, 78, 110, 25, 12)
local generalAnchorButton = makeButton(settingsContent, "ON", 120, 74, 120, 32)

local generalAutoStealLabel = makeLabel(settingsContent, "AUTO STEAL OFF", 10, 118, 110, 25, 12)
local generalAutoStealButton = makeButton(settingsContent, "ON", 120, 114, 120, 32)

local generalTPLabel = makeLabel(settingsContent, "TP RETURN TIME", 10, 158, 110, 25, 12)
local generalTPBox = makeBox(settingsContent, State.tpDuration, 120, 154, 120, 32)

local generalAutoGoalLabel = makeLabel(settingsContent, "AUTO GOAL", 10, 198, 110, 25, 12)
local generalAutoGoalButton = makeButton(settingsContent, "OFF", 120, 194, 120, 32)

local generalHint = makeLabel(
	settingsContent,
	"Auto Goal tự cướp bóng và ghi bàn. TP Return/GK follow bóng đến khi local có bóng.",
	255,
	38,
	215,
	175,
	11
)

generalHint.TextWrapped = true
generalHint.TextYAlignment = Enum.TextYAlignment.Top
generalHint.TextColor3 = Color3.fromRGB(145, 145, 155)

local mode1Label = makeLabel(settingsContent, "SPEED", 10, 10, 110, 25, 12)
local mode1Box = makeBox(settingsContent, modeSettings[1].speed, 120, 6, 220, 32)

local mode1Hint = makeLabel(
	settingsContent,
	"Mode 1 điều khiển bóng theo camera.",
	10,
	70,
	440,
	60,
	11
)

mode1Hint.TextWrapped = true
mode1Hint.TextColor3 = Color3.fromRGB(145, 145, 155)

local mode1AdvanceLabel = makeLabel(settingsContent, "ADVANCE MODE", 10, 120, 110, 25, 12)
local mode1AdvanceButton = makeButton(settingsContent, "OFF", 120, 116, 120, 32)

local mode1AdvanceHint = makeLabel(
	settingsContent,
	"Camera bám bóng; WASD di chuyển, Q/E thay đổi độ cao.",
	10,
	160,
	440,
	55,
	11
)

mode1AdvanceHint.TextWrapped = true
mode1AdvanceHint.TextColor3 = Color3.fromRGB(145, 145, 155)

local mode2Label = makeLabel(settingsContent, "SPEED", 10, 10, 110, 25, 12)
local mode2Box = makeBox(settingsContent, modeSettings[2].speed, 120, 6, 220, 32)

local mode2Hint = makeLabel(
	settingsContent,
	"Mode 2 dùng ShootBall cho cú sút thường.",
	10,
	70,
	440,
	45,
	11
)

mode2Hint.TextWrapped = true
mode2Hint.TextColor3 = Color3.fromRGB(145, 145, 155)

local mode2AdvanceLabel = makeLabel(settingsContent, "ADVANCE MODE", 10, 122, 110, 25, 12)
local mode2AdvanceButton = makeButton(settingsContent, "OFF", 120, 118, 120, 32)

local mode2AdvanceHint = makeLabel(
	settingsContent,
	"RMB chọn điểm, F để bóng bay đến điểm đó.",
	10,
	160,
	440,
	55,
	11
)

mode2AdvanceHint.TextWrapped = true
mode2AdvanceHint.TextColor3 = Color3.fromRGB(145, 145, 155)

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

local function setGeneralControls()
	generalControlButton.Text = State.controlKey.Name
	generalAnchorButton.Text = State.anchorEnabled and "ON" or "OFF"
	generalAutoStealButton.Text = State.autoStealOffOnGet and "ON" or "OFF"
	generalTPBox.Text = tostring(State.tpDuration)
	generalAutoGoalButton.Text = State.autoGoalEnabled and "ON" or "OFF"
end

local function refreshSettingsPanel()
	local general = selectedSettingsTab == 1
	local mode1 = selectedSettingsTab == 2
	local mode2 = selectedSettingsTab == 3

	generalTitle.Visible = general
	generalControlLabel.Visible = general
	generalControlButton.Visible = general
	generalAnchorLabel.Visible = general
	generalAnchorButton.Visible = general
	generalAutoStealLabel.Visible = general
	generalAutoStealButton.Visible = general
	generalTPLabel.Visible = general
	generalTPBox.Visible = general
	generalAutoGoalLabel.Visible = general
	generalAutoGoalButton.Visible = general
	generalHint.Visible = general

	mode1Label.Visible = mode1
	mode1Box.Visible = mode1
	mode1Hint.Visible = mode1
	mode1AdvanceLabel.Visible = mode1
	mode1AdvanceButton.Visible = mode1
	mode1AdvanceHint.Visible = mode1

	mode2Label.Visible = mode2
	mode2Box.Visible = mode2
	mode2Hint.Visible = mode2
	mode2AdvanceLabel.Visible = mode2
	mode2AdvanceButton.Visible = mode2
	mode2AdvanceHint.Visible = mode2

	setGeneralControls()

	mode1AdvanceButton.Text = State.advanceMode and "ON" or "OFF"
	mode2AdvanceButton.Text = State.ronaldoAdvanceEnabled and "ON" or "OFF"
end

for i = 1, 3 do
	Bind(tabs[i].MouseButton1Click, function()
		selectedSettingsTab = i
		refreshSettingsPanel()
	end)
end

Bind(generalControlButton.MouseButton1Click, function()
	State.changingControlKey = true
	generalControlButton.Text = "PRESS KEY"
	notify("CONTROL KEY", "Nhấn phím mới (ESC = hủy)", 1.6)
end)

Bind(generalAnchorButton.MouseButton1Click, function()
	State.anchorEnabled = not State.anchorEnabled
	State.forceUnanchorActive = false

	if State.anchorEnabled and State.enabled and State.mode == 1 then
		applyModeLock()
	else
		unlockPlayer()

		if rootPart then
			rootPart.Anchored = false
		end
	end

	setGeneralControls()
end)

Bind(generalAutoStealButton.MouseButton1Click, function()
	State.autoStealOffOnGet = not State.autoStealOffOnGet

	setGeneralControls()

	notify(
		"AUTO STEAL",
		State.autoStealOffOnGet and "OFF ON GET: ON" or "OFF ON GET: OFF",
		1.1
	)
end)

Bind(generalTPBox.FocusLost, function()
	local value = tonumber(generalTPBox.Text)

	if not value then
		generalTPBox.Text = tostring(State.tpDuration)
		return
	end

	State.tpDuration = math.clamp(value, 0.1, 60)

	generalTPBox.Text = tostring(State.tpDuration)
	tpTimeBox.Text = tostring(State.tpDuration)
end)

Bind(generalAutoGoalButton.MouseButton1Click, function()
	State.autoGoalEnabled = not State.autoGoalEnabled

	if State.autoGoalEnabled then
		State.autoGoalRunId += 1
		State.autoGoalExecuting = false
		State.stealBallEnabled = false

		notify(
			"AUTO GOAL",
			"ON — tự cướp bóng + tự ghi bàn",
			1.4
		)
	else
		State.autoGoalRunId += 1
		State.autoGoalExecuting = false
		notify("AUTO GOAL", "OFF", 1.1)
	end

	setGeneralControls()
	updateUI()
end)

Bind(mode1Box.FocusLost, function()
	modeSettings[1].speed = parseSetting(
		mode1Box,
		modeSettings[1].speed,
		MIN_SPEED,
		MAX_SPEED
	)
end)

local savedCameraType
local savedCameraSubject

local function saveCamera(ballSubject)
	camera = workspace.CurrentCamera

	if not camera then
		return
	end

	if savedCameraType == nil then
		savedCameraType = camera.CameraType
	end

	if
		camera.CameraSubject
		and camera.CameraSubject ~= ballSubject
		and savedCameraSubject == nil
	then
		savedCameraSubject = camera.CameraSubject
	end
end

local function cameraToBall(ball)
	if not ball then
		return
	end

	camera = workspace.CurrentCamera

	if not camera then
		return
	end

	saveCamera(ball)

	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = ball
end

local function restoreCamera()
	camera = workspace.CurrentCamera

	if not camera then
		return
	end

	updateCharacter()

	camera.CameraType = savedCameraType or Enum.CameraType.Custom
	camera.CameraSubject = humanoid or savedCameraSubject

	savedCameraType = nil
	savedCameraSubject = nil
end

local function setAdvanceMode(value)
	State.advanceMode = value and true or false

	State.advanceKeys = {
		W = false,
		A = false,
		S = false,
		D = false,
		Q = false,
		E = false
	}

	if State.advanceMode then
		if State.mode == 1 and State.enabled then
			camera = workspace.CurrentCamera

			if camera then
				camera.CameraType = Enum.CameraType.Scriptable
			end
		end
	else
		if State.mode == 1 and State.enabled then
			local ball = BallTracker.Ball

			if ball then
				cameraToBall(ball)
			else
				restoreCamera()
			end
		end
	end

	mode1AdvanceButton.Text = State.advanceMode and "ON" or "OFF"
end

Bind(mode1AdvanceButton.MouseButton1Click, function()
	setAdvanceMode(not State.advanceMode)

	notify(
		"ADVANCE MODE",
		State.advanceMode and "ON" or "OFF",
		1.2
	)
end)

Bind(mode2Box.FocusLost, function()
	modeSettings[2].speed = parseSetting(
		mode2Box,
		modeSettings[2].speed,
		MIN_SPEED,
		MAX_SPEED
	)
end)

Bind(tpTimeBox.FocusLost, function()
	local value = tonumber(tpTimeBox.Text)

	if not value then
		tpTimeBox.Text = tostring(State.tpDuration)
		return
	end

	State.tpDuration = math.clamp(value, 0.1, 60)

	tpTimeBox.Text = tostring(State.tpDuration)
	generalTPBox.Text = tostring(State.tpDuration)
end)

-- RONALDO ADVANCE

local function clearRonaldoAdvanceTarget()
	State.ronaldoAdvanceTargetPosition = nil
	State.ronaldoAdvanceTargetPart = nil
end

local function clearRonaldoTouchedConnection()
	local connection = State.ronaldoAdvanceTouchedConnection

	State.ronaldoAdvanceTouchedConnection = nil

	if connection then
		DisconnectConnection(connection)
	end
end

local function stopRonaldoAdvance()
	State.ronaldoAdvanceActive = false
	State.ronaldoAdvanceBall = nil
	State.ronaldoAdvanceStartTime = 0

	clearRonaldoTouchedConnection()
	clearRonaldoAdvanceTarget()
end

local function getMouseWorldTarget()
	camera = workspace.CurrentCamera

	if not camera then
		return nil, nil
	end

	local mousePosition = UserInputService:GetMouseLocation()

	local ray = camera:ViewportPointToRay(
		mousePosition.X,
		mousePosition.Y
	)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}

	local result = workspace:Raycast(
		ray.Origin,
		ray.Direction * 1000,
		params
	)

	if result then
		return result.Position, result.Instance
	end

	return nil, nil
end

local function selectRonaldoAdvanceTarget()
	if State.mode ~= 2 or not State.ronaldoAdvanceEnabled then
		return false
	end

	if not localHasBall() then
		notify("RONALDO ADVANCE", "Cần đang cầm bóng", 1.2)
		return false
	end

	local position, hitPart = getMouseWorldTarget()

	if not position then
		notify("RONALDO ADVANCE", "Không chọn được vị trí", 1.2)
		return false
	end

	State.ronaldoAdvanceTargetPosition = position
	State.ronaldoAdvanceTargetPart = hitPart

	notify("RONALDO ADVANCE", "Đã chọn điểm bay", 1.1)

	return true
end

local function startRonaldoAdvance()
	if not State.ronaldoAdvanceEnabled then
		notify("RONALDO ADVANCE", "Advance Mode đang OFF", 1.1)
		return false
	end

	if not State.ronaldoAdvanceTargetPosition then
		notify("RONALDO ADVANCE", "Chuột phải để chọn điểm trước", 1.2)
		return false
	end

	if not localHasBall() then
		clearRonaldoAdvanceTarget()
		notify("RONALDO ADVANCE", "Cần đang cầm bóng", 1.2)
		return false
	end

	local _, _, ball = getBallState()

	if not ball then
		return false
	end

	clearRonaldoTouchedConnection()

	local delta = State.ronaldoAdvanceTargetPosition - ball.Position

	if delta.Magnitude < 0.1 then
		stopRonaldoAdvance()
		return false
	end

	local speed = math.clamp(
		modeSettings[2].speed,
		MIN_SPEED,
		MAX_SPEED
	)

	if not fireShootRemote(delta.Unit, speed, false) then
		return false
	end

	State.ronaldoAdvanceActive = true
	State.ronaldoAdvanceBall = ball
	State.ronaldoAdvanceStartTime = os.clock() + 0.06

	local trackedBall = ball

	State.ronaldoAdvanceTouchedConnection =
		trackedBall.Touched:Connect(function(hit)
			if not State.ronaldoAdvanceActive then
				return
			end

			if State.ronaldoAdvanceBall ~= trackedBall then
				stopRonaldoAdvance()
				return
			end

			if os.clock() < State.ronaldoAdvanceStartTime then
				return
			end

			if not hit or not hit:IsA("BasePart") then
				return
			end

			if character and hit:IsDescendantOf(character) then
				return
			end

			stopRonaldoAdvance()
		end)

	notify("RONALDO ADVANCE", "Bắt đầu bay", 0.9)

	return true
end

local function updateRonaldoAdvance()
	if not State.ronaldoAdvanceActive then
		return
	end

	local ball = State.ronaldoAdvanceBall
	local target = State.ronaldoAdvanceTargetPosition

	if
		not ball
		or not ball.Parent
		or not target
	then
		stopRonaldoAdvance()
		return
	end

	if BallTracker.Ball ~= ball then
		stopRonaldoAdvance()
		return
	end

	local state, holder = getBallState()

	if state ~= "HELD" or holder ~= player then
		stopRonaldoAdvance()
		return
	end

	local delta = target - ball.Position

	if delta.Magnitude <= 3 then
		ball.AssemblyLinearVelocity = Vector3.zero
		stopRonaldoAdvance()
		notify("RONALDO ADVANCE", "Đã tới điểm", 0.9)
		return
	end

	local speed = math.clamp(
		modeSettings[2].speed,
		MIN_SPEED,
		MAX_SPEED
	)

	ball.AssemblyLinearVelocity = delta.Unit * speed
end

Bind(mode2AdvanceButton.MouseButton1Click, function()
	State.ronaldoAdvanceEnabled = not State.ronaldoAdvanceEnabled

	if not State.ronaldoAdvanceEnabled then
		stopRonaldoAdvance()
	end

	refreshSettingsPanel()

	notify(
		"RONALDO ADVANCE",
		State.ronaldoAdvanceEnabled and "ON — RMB chọn điểm → F" or "OFF",
		1.3
	)
end)

-- CAMERA

local function getFlatCameraDirections()
	camera = workspace.CurrentCamera

	if not camera then
		return Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)
	end

	local f = Vector3.new(
		camera.CFrame.LookVector.X,
		0,
		camera.CFrame.LookVector.Z
	)

	local r = Vector3.new(
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

	return f, r
end

local function getCameraDirection()
	camera = workspace.CurrentCamera

	if not camera then
		return Vector3.new(0, 0, -1)
	end

	local d = camera.CFrame.LookVector

	return d.Magnitude > 0 and d.Unit or Vector3.new(0, 0, -1)
end

local function updateAdvanceCamera(ball)
	if not State.advanceMode or not State.enabled or not ball then
		return false
	end

	camera = workspace.CurrentCamera

	if not camera then
		return false
	end

	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = ball

	local f, r = getFlatCameraDirections()
	local move = Vector3.zero

	if State.advanceKeys.W then
		move += f
	end

	if State.advanceKeys.S then
		move -= f
	end

	if State.advanceKeys.D then
		move += r
	end

	if State.advanceKeys.A then
		move -= r
	end

	if State.advanceKeys.E then
		move += Vector3.new(0, 1, 0)
	end

	if State.advanceKeys.Q then
		move -= Vector3.new(0, 1, 0)
	end

	local speed = math.clamp(
		modeSettings[1].speed,
		MIN_SPEED,
		MAX_SPEED
	)

	if move.Magnitude > 0 then
		ball.AssemblyLinearVelocity = move.Unit * speed
	else
		ball.AssemblyLinearVelocity = Vector3.zero
	end

	return true
end

local function controlMode1(ball)
	if not ball then
		return
	end

	ball.AssemblyLinearVelocity =
		getCameraDirection()
		* math.clamp(
			modeSettings[1].speed,
			MIN_SPEED,
			MAX_SPEED
		)
end

local function performMode4Kick(ball)
	if not ball then
		return
	end

	local force = math.clamp(
		modeSettings[2].speed,
		MIN_SPEED,
		MAX_SPEED
	)

	if fireShootRemote(getCameraDirection(), force, false) then
		notify("RONALDO MODE", "ShootBall velocity sent", 1.4)
	end
end

-- CHARACTER / ROLE

local function getCharacterNameValue()
	local values = player:FindFirstChild("Values")
	local valueObj = values and values:FindFirstChild("CharacterName")

	if valueObj and valueObj.Value ~= nil then
		return tostring(valueObj.Value)
	end

	return ""
end

local function localIsBarou()
	return string.lower(getCharacterNameValue()) == "barou"
end

local function getRoleName()
	local roleObj = player:FindFirstChild("Role")

	if roleObj and roleObj.Value ~= nil then
		return string.lower(tostring(roleObj.Value))
	end

	local values = player:FindFirstChild("Values")
	local valuesRole = values and values:FindFirstChild("Role")

	if valuesRole and valuesRole.Value ~= nil then
		return string.lower(tostring(valuesRole.Value))
	end

	if character then
		local charRole = character:FindFirstChild("Role")

		if charRole and charRole.Value ~= nil then
			return string.lower(tostring(charRole.Value))
		end
	end

	return ""
end

local function localIsGoalkeeper()
	local role = string.gsub(getRoleName(), "%s+", " ")

	for _, name in ipairs(GK_ROLE_NAMES) do
		if role == name then
			return true
		end
	end

	return false
end

local function getTeamIsHome()
	return player.Team and string.lower(player.Team.Name) == "home"
end

-- GOALS

local function resolveGoalHitboxForTeam(homeSide)
	local map = workspace:FindFirstChild("Map")

	if not map then
		return nil
	end

	local goalName = homeSide and "PlayerOneGoal" or "PlayerTwoGoal"
	local goalModel = map:FindFirstChild(goalName)

	if not goalModel then
		return nil
	end

	local score =
		goalModel:FindFirstChild("ScoreHitbox")
		or goalModel:FindFirstChild("Score")

	if score and score:IsA("BasePart") then
		return score
	end

	local hitbox = goalModel:FindFirstChild("ScoreHitbox", true)

	if hitbox and hitbox:IsA("BasePart") then
		return hitbox
	end

	return goalModel:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveGoalAreaForTeam(homeSide)
	local goalName = homeSide and "PlayerOneGoalArea" or "PlayerTwoGoalArea"
	local goal = workspace:FindFirstChild(goalName)

	if not goal then
		return nil
	end

	if goal:IsA("BasePart") then
		return goal
	end

	if goal:IsA("Model") then
		if goal.PrimaryPart then
			return goal.PrimaryPart
		end

		return goal:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function resolveOwnGoalPart()
	local isHome = getTeamIsHome()

	return resolveGoalAreaForTeam(isHome)
		or resolveGoalHitboxForTeam(isHome)
end

local function resolveOpponentGoalHitbox()
	local isHome = getTeamIsHome()
	return resolveGoalHitboxForTeam(not isHome)
end

local function sendVirtualKey(keyCode)
	if not VirtualInputManager then
		return false
	end

	return pcall(function()
		VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
		task.wait()
		VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
	end)
end

local function isInsideGoalArea(position, goalPart)
	if not position or not goalPart then
		return false
	end

	return (position - goalPart.Position).Magnitude <= 18
end

local function getCurrentBallTarget()
	local state, holder, ball = getBallState()

	if state == "HELD" and holder and holder ~= player then
		local targetRoot = getPlayerRoot(holder)

		if targetRoot then
			return targetRoot, holder
		end
	end

	if state == "FREE" and ball and ball.Parent then
		return ball, nil
	end

	return nil, nil
end

local function performGKTPReturn()
	if not localIsGoalkeeper() or not updateCharacter() or not rootPart then
		return false
	end

	local goalPart = resolveOwnGoalPart()

	if not goalPart then
		notify("GK RETURN", "Không tìm thấy GoalArea của đội", 1.5)
		return false
	end

	State.gkLastGoalPart = goalPart
	State.gkSpecialEnabled = true

	if not isInsideGoalArea(rootPart.Position, goalPart) then
		rootPart.CFrame = CFrame.new(goalPart.Position + GK_TP_OFFSET)
	end

	task.wait(0.30)
	sendVirtualKey(Enum.KeyCode.Q)

	if not updateCharacter() or not rootPart or not rootPart.Parent then
		State.gkSpecialEnabled = false
		State.gkLastGoalPart = nil
		return false
	end

	local currentRoot = rootPart
	local targetRoot, holder = getCurrentBallTarget()

	State.tpFollowTarget = holder
	State.tpFollowBall = holder and nil or targetRoot

	if targetRoot and targetRoot.Parent then
		currentRoot.CFrame = CFrame.new(
			targetRoot.Position + Vector3.new(0, DEFAULT_STEAL_DISTANCE, 0)
		)

		notify(
			"GK RETURN",
			holder and ("Q DIVE → TP → " .. holder.Name) or "Q DIVE → TP → FREE BALL",
			1.4
		)
	else
		notify("GK RETURN", "Q DIVE → đang chờ bóng", 1.3)
	end

	return true
end

-- STEAL

local function findBallTarget()
	local holder = BallTracker.Holder
	local ball = BallTracker.Ball
	local state = BallTracker.State

	if state == "HELD" and holder then
		if holder == player then
			return nil, nil
		end

		if localIsBarou() or not sameTeam(holder) then
			local targetRoot = getPlayerRoot(holder)

			if targetRoot then
				return targetRoot, holder
			end
		end

		return nil, nil
	end

	if state == "FREE" and ball then
		return ball, nil
	end

	return nil, nil
end

local function spamStealStep()
	if not updateCharacter() or not rootPart or not rootPart.Parent or localHasBall() then
		return
	end

	local currentRoot = rootPart
	local targetPart = findBallTarget()

	if not targetPart or not targetPart.Parent then
		return
	end

	if localIsGoalkeeper() then
		local ownGoal = resolveOwnGoalPart()

		if ownGoal then
			currentRoot.CFrame = CFrame.new(
				ownGoal.Position + GK_TP_OFFSET
			)

			sendVirtualKey(Enum.KeyCode.Q)
		end
	end

	currentRoot.CFrame = CFrame.new(
		targetPart.Position + Vector3.new(0, DEFAULT_STEAL_DISTANCE, 0)
	)

	sendVirtualKey(Enum.KeyCode.E)
end

-- TP

local function startTPGoal()
	local goalPart = resolveOpponentGoalHitbox()

	if not goalPart then
		notify("TP GOAL", "Không tìm thấy ScoreHitbox đối diện", 1.3)
		return
	end

	local _, _, ball = getBallState()

	if not ball or not ball.Parent or not ball:IsA("BasePart") then
		notify("TP GOAL", "Không tìm thấy bóng hợp lệ", 1.2)
		return
	end

	ball.CFrame = goalPart.CFrame
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero

	State.tpGoalActive = true

	notify(
		"TP GOAL",
		getTeamIsHome() and "BALL → PLAYER TWO GOAL" or "BALL → PLAYER ONE GOAL",
		1.3
	)
end

local function restoreTemporaryTP(reason)
	if not State.tpActive then
		return
	end

	local saved = State.tpReturnCFrame

	State.tpActive = false
	State.tpReturnCFrame = nil
	State.tpGoalActive = false
	State.tpFollowTarget = nil
	State.tpFollowBall = nil
	State.gkSpecialEnabled = false
	State.gkLastGoalPart = nil

	if saved and updateCharacter() and rootPart and rootPart.Parent then
		rootPart.CFrame = saved
	end

	if reason then
		notify("TP RETURN", reason, 1.2)
	end
end

local function startTemporaryTP()
	if State.tpActive then
		restoreTemporaryTP("Returned")
		return
	end

	if not updateCharacter() or not rootPart then
		notify("TP RETURN", "Không tìm thấy nhân vật", 1.2)
		return
	end

	State.tpReturnCFrame = rootPart.CFrame

	if localIsGoalkeeper() then
		if performGKTPReturn() then
			State.tpActive = true
			State.tpStartedAt = os.clock()
			return
		end

		State.tpReturnCFrame = nil
		return
	end

	local state, holder, ball = getBallState()

	local targetPosition
	local targetName

	if state == "HELD" and holder and holder ~= player then
		local targetRoot = getPlayerRoot(holder)

		if targetRoot then
			targetPosition =
				targetRoot.Position
				+ Vector3.new(0, DEFAULT_STEAL_DISTANCE, 0)

			targetName = holder.Name
		end
	elseif state == "FREE" and ball then
		targetPosition =
			ball.Position
			+ Vector3.new(0, DEFAULT_STEAL_DISTANCE, 0)

		targetName = "FREE BALL"
	end

	if not targetPosition then
		State.tpReturnCFrame = nil
		notify("TP RETURN", "Không có bóng hợp lệ để TP", 1.3)
		return
	end

	State.tpActive = true
	State.tpStartedAt = os.clock()
	State.tpFollowTarget = state == "HELD" and holder or nil
	State.tpFollowBall = state == "FREE" and ball or nil

	rootPart.CFrame = CFrame.new(targetPosition)

	notify(
		"TP RETURN",
		string.format("TP → %s trong %.2fs", targetName, State.tpDuration),
		1.5
	)
end

local function updateTPFollowTarget()
	if not State.tpActive or not updateCharacter() or not rootPart then
		return
	end

	if localHasBall() then
		restoreTemporaryTP("Đã nhặt được bóng → quay về")
		return
	end

	local state, holder, ball = getBallState()
	local targetRoot

	if state == "HELD" and holder and holder ~= player then
		targetRoot = getPlayerRoot(holder)
		State.tpFollowTarget = holder
		State.tpFollowBall = nil
	elseif state == "FREE" and ball then
		targetRoot = ball
		State.tpFollowTarget = nil
		State.tpFollowBall = ball
	end

	if targetRoot and targetRoot.Parent then
		rootPart.CFrame = CFrame.new(
			targetRoot.Position + Vector3.new(0, DEFAULT_STEAL_DISTANCE, 0)
		)
	elseif state ~= "HELD" and state ~= "FREE" then
		State.tpFollowTarget = nil
		State.tpFollowBall = nil
	end
end

-- SAE PASS

local function clearSaeTarget()
	State.selectedTarget = nil
	State.saePassActive = false
	State.saePassStage = "IDLE"
	State.saePassBall = nil
	State.saePassTarget = nil

	if State.targetHighlight then
		State.targetHighlight:Destroy()
		State.targetHighlight = nil
	end
end

local function highlightSaeTarget(plr)
	if State.targetHighlight then
		State.targetHighlight:Destroy()
	end

	State.selectedTarget = plr

	if not plr or not plr.Character then
		return
	end

	local hl = Instance.new("Highlight")
	hl.Name = "SaePassTarget"
	hl.FillColor = Color3.fromRGB(0, 255, 120)
	hl.FillTransparency = 0.4
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.OutlineTransparency = 0
	hl.Adornee = plr.Character
	hl.Parent = plr.Character

	State.targetHighlight = hl
end

local function getClosestTeammateToMouse()
	camera = workspace.CurrentCamera

	if not camera then
		return nil
	end

	local mousePos = UserInputService:GetMouseLocation()
	local best
	local bestDist = math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player and sameTeam(plr) and plr.Character then
			local hrp = getPlayerRoot(plr)

			if hrp then
				local point, onScreen = camera:WorldToViewportPoint(hrp.Position)

				if onScreen and point.Z > 0 then
					local dist = (
						Vector2.new(point.X, point.Y) - mousePos
					).Magnitude

					if dist < bestDist then
						bestDist = dist
						best = plr
					end
				end
			end
		end
	end

	return best
end

local function isAnyPlayerHoldingBall()
	local state, holder = getBallState()

	if state == "HELD" and holder then
		return true, holder
	end

	return false, nil
end

local function stickBallToTarget(target)
	if not target or not target.Character then
		return
	end

	local targetRoot = getPlayerRoot(target)
	local ball = State.saePassBall

	if
		not targetRoot
		or not ball
		or not ball.Parent
	then
		local _, _, cachedBall = getBallState()
		ball = cachedBall
		State.saePassBall = ball
	end

	if not targetRoot or not ball then
		return
	end

	pcall(function()
		ball.AssemblyLinearVelocity = Vector3.zero
		ball.AssemblyAngularVelocity = Vector3.zero
		ball.CFrame = targetRoot.CFrame * CFrame.new(0, -1.5, -1)
	end)
end

local function selectSaePassTarget()
	if not State.saePassEnabled then
		return false
	end

	local target = getClosestTeammateToMouse()

	if not target then
		notify("SAE PASS", "Không tìm thấy đồng đội", 1.2)
		return false
	end

	local holding = localHasBall()

	highlightSaeTarget(target)

	State.saePassTarget = target
	State.saePassActive = true
	State.saePassStage = holding and "WAIT_RELEASE" or "STICK"

	local _, _, ball = getBallState()
	State.saePassBall = ball

	if holding then
		notify(
			"SAE PASS",
			"Đã khóa " .. target.Name .. " — chờ nhả bóng",
			1.4
		)
	else
		notify(
			"SAE PASS",
			"Bóng sẽ dính vào " .. target.Name,
			1.4
		)
	end

	return true
end

local function updateSaePass()
	if not State.saePassEnabled then
		return
	end

	if not State.saePassActive or not State.saePassTarget then
		return
	end

	local target = State.saePassTarget

	if not target.Parent or not target.Character then
		clearSaeTarget()
		return
	end

	if localHasBall() then
		State.saePassStage = "WAIT_RELEASE"
		return
	end

	local isHeld, holder = isAnyPlayerHoldingBall()

	if isHeld then
		notify(
			"SAE PASS",
			holder.Name .. " đã nhặt bóng",
			1.0
		)

		clearSaeTarget()
		return
	end

	State.saePassStage = "STICK"

	stickBallToTarget(target)
end

-- UI

local function performAutoGoalStep()
	if State.autoGoalExecuting or not State.autoGoalEnabled then
		return
	end

	if not updateCharacter() or not rootPart or not rootPart.Parent then
		return
	end

	local state, holder, ball = getBallState()
	if state ~= "HELD" or holder ~= player or not ball or not ball.Parent then
		return
	end

	local goalHitbox = resolveOpponentGoalHitbox()
	if not goalHitbox or not goalHitbox.Parent then
		return
	end

	State.autoGoalExecuting = true
	State.autoGoalRunId += 1
	local runId = State.autoGoalRunId

	task.spawn(function()
		local originalRoot = rootPart
		local savedCFrame = originalRoot and originalRoot.CFrame

		local ok, err = pcall(function()
			if not originalRoot or not originalRoot.Parent or not State.autoGoalEnabled then
				return
			end

			originalRoot.CFrame = CFrame.new(
				goalHitbox.Position + TP_GOAL_OFFSET,
				goalHitbox.Position
			)

			task.wait(0.02)

			if not goalHitbox.Parent or not originalRoot.Parent then
				return
			end

			local direction = goalHitbox.Position - originalRoot.Position
			if direction.Magnitude > 0.001 then
				fireShootRemote(direction.Unit, SHOOT_FORCE, false)
			end

			task.wait(0.02)

			local _, _, currentBall = getBallState()
			if currentBall and currentBall.Parent and currentBall:IsA("BasePart") then
				currentBall.CFrame = goalHitbox.CFrame
				currentBall.AssemblyLinearVelocity = Vector3.zero
				currentBall.AssemblyAngularVelocity = Vector3.zero
			end
		end)

		if not ok then
			warn("[Ball Controller] Auto Goal error: " .. tostring(err))
		end

		if savedCFrame and originalRoot and originalRoot.Parent then
			originalRoot.CFrame = savedCFrame
		end

		if State.autoGoalRunId == runId then
			State.autoGoalExecuting = false
		end
	end)
end

local function modeName()
	return State.mode == 1
		and "MODE 1 [CAMERA]"
		or "MODE 2 [RONALDO]"
end

local lastUiEnabled
local lastUiMode
local lastUiControlKey
local lastUiSteal
local lastUiSae
local lastUiAnchor
local lastUiAutoGoal

local function updateUI(force)
	local changed =
		force
		or State.enabled ~= lastUiEnabled
		or State.mode ~= lastUiMode
		or State.controlKey ~= lastUiControlKey
		or State.stealBallEnabled ~= lastUiSteal
		or State.saePassEnabled ~= lastUiSae
		or State.anchorEnabled ~= lastUiAnchor
		or State.autoGoalEnabled ~= lastUiAutoGoal

	if not changed then
		return
	end

	lastUiEnabled = State.enabled
	lastUiMode = State.mode
	lastUiControlKey = State.controlKey
	lastUiSteal = State.stealBallEnabled
	lastUiSae = State.saePassEnabled
	lastUiAnchor = State.anchorEnabled
	lastUiAutoGoal = State.autoGoalEnabled

	controlButton.Text = "CONTROL KEY: " .. State.controlKey.Name
	modeButton.Text = modeName()

	statusLabel.Text =
		State.enabled
		and "Status: ACTIVE"
		or "Status: READY"

	statusLabel.TextColor3 =
		State.enabled
		and Color3.fromRGB(100, 255, 130)
		or Color3.fromRGB(255, 205, 100)

	stealButton.Text =
		State.stealBallEnabled
		and "STEAL BALL: ON"
		or "STEAL BALL: OFF"

	saeButton.Text =
		State.saePassEnabled
		and "SAE PASS: ON"
		or "SAE PASS: OFF"

	anchorButton.Text =
		State.anchorEnabled
		and "ANCHOR: ON"
		or "ANCHOR: OFF"

	generalAutoGoalButton.Text =
		State.autoGoalEnabled
		and "ON"
		or "OFF"
end

local lastBallUIState
local lastBallUIHolder

local function updateBallStatusUI(state, holder)
	if state == "HELD" then
		ballStatus.Text = "BALL: HELD — " .. holder.Name
		statusState.Text = "STATUS: HELD"
		statusOwner.Text = "OWNER: " .. holder.Name
		statusPlayer.Text =
			"CONTROL: "
			.. (State.enabled and "ACTIVE" or "OFF")

		statusState.TextColor3 =
			holder == player
			and Color3.fromRGB(100, 255, 255)
			or (
				sameTeam(holder)
				and Color3.fromRGB(100, 255, 130)
				or Color3.fromRGB(255, 100, 100)
			)
	elseif state == "FREE" then
		ballStatus.Text = "BALL: FREE"
		statusState.Text = "STATUS: FREE"
		statusOwner.Text = "OWNER: NONE"
		statusPlayer.Text =
			"CONTROL: "
			.. (State.enabled and "ACTIVE" or "OFF")
		statusState.TextColor3 = Color3.fromRGB(255, 215, 100)
	else
		ballStatus.Text = "BALL: NOT FOUND"
		statusState.Text = "STATUS: NOT FOUND"
		statusOwner.Text = "OWNER: —"
		statusPlayer.Text =
			"CONTROL: "
			.. (State.enabled and "ACTIVE" or "OFF")
		statusState.TextColor3 = Color3.fromRGB(255, 100, 100)
	end

	statusPlayer.TextColor3 =
		State.enabled
		and Color3.fromRGB(100, 255, 130)
		or Color3.fromRGB(180, 180, 190)
end

local function refreshBallStatusUI(state, holder)
	if state == lastBallUIState and holder == lastBallUIHolder then
		return
	end

	lastBallUIState = state
	lastBallUIHolder = holder

	updateBallStatusUI(state, holder)
end

local function centerMainUI()
	camera = workspace.CurrentCamera

	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

	main.Position = UDim2.fromOffset(
		math.max(0, (viewport.X - main.AbsoluteSize.X) / 2),
		math.max(0, (viewport.Y - main.AbsoluteSize.Y) / 2)
	)

	if State.settingsOpen then
		settingsFrame.Position = UDim2.fromOffset(
			math.max(0, (viewport.X - settingsFrame.AbsoluteSize.X) / 2),
			math.max(0, (viewport.Y - settingsFrame.AbsoluteSize.Y) / 2)
		)
	end
end

-- DRAG

local function makeDraggable(object, handle)
	local dragging = false
	local dragStart
	local startPosition
	local changedConnection

	Bind(handle.InputBegan, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		dragging = true
		dragStart = input.Position
		startPosition = object.Position

		DisconnectConnection(changedConnection)

		changedConnection = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				DisconnectConnection(changedConnection)
				changedConnection = nil
			end
		end)
	end)

	Bind(UserInputService.InputChanged, function(input)
		if not dragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local delta = input.Position - dragStart

		local x = startPosition.X.Offset + delta.X
		local y = startPosition.Y.Offset + delta.Y

		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

		x = math.clamp(
			x,
			0,
			math.max(0, viewport.X - object.AbsoluteSize.X)
		)

		y = math.clamp(
			y,
			0,
			math.max(0, viewport.Y - object.AbsoluteSize.Y)
		)

		object.Position = UDim2.new(
			startPosition.X.Scale,
			x,
			startPosition.Y.Scale,
			y
		)
	end)
end

makeDraggable(main, title)
makeDraggable(settingsFrame, settingsTitle)

-- ZOOM

local ZOOM_MIN = 0.6
local ZOOM_MAX = 1.6
local ZOOM_STEP = 0.1

local function setUIScale(value)
	value = math.clamp(value, ZOOM_MIN, ZOOM_MAX)
	value = math.floor(value * 100 + 0.5) / 100

	if value == State.uiScale then
		return
	end

	State.uiScale = value

	mainScale.Scale = value
	settingsScale.Scale = value
	statusScale.Scale = value

	task.defer(function()
		clampGuiPosition(main)
		clampGuiPosition(settingsFrame)
		clampGuiPosition(statusPanel)
		clampGuiPosition(restoreButton)
	end)

	notify(
		"GIAO DIỆN",
		"Thu phóng: " .. math.floor(value * 100) .. "%",
		0.9
	)
end

Bind(zoomOutButton.MouseButton1Click, function()
	setUIScale(State.uiScale - ZOOM_STEP)
end)

Bind(zoomInButton.MouseButton1Click, function()
	setUIScale(State.uiScale + ZOOM_STEP)
end)

Bind(settingsZoomOutButton.MouseButton1Click, function()
	setUIScale(State.uiScale - ZOOM_STEP)
end)

Bind(settingsZoomInButton.MouseButton1Click, function()
	setUIScale(State.uiScale + ZOOM_STEP)
end)

main.Active = true
settingsFrame.Active = true
statusPanel.Active = true

local function handleZoomWheel(input)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end

	local ctrlHeld =
		UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

	if not ctrlHeld then
		return
	end

	if input.Position.Z > 0 then
		setUIScale(State.uiScale + ZOOM_STEP)
	elseif input.Position.Z < 0 then
		setUIScale(State.uiScale - ZOOM_STEP)
	end
end

Bind(main.InputChanged, handleZoomWheel)
Bind(settingsFrame.InputChanged, handleZoomWheel)
Bind(statusPanel.InputChanged, handleZoomWheel)

-- BUTTONS

Bind(minimizeButton.MouseButton1Click, function()
	State.minimized = true

	restoreButton.Position = main.Position
	clampGuiPosition(restoreButton)

	main.Visible = false
	settingsFrame.Visible = false
	restoreButton.Visible = true
end)

Bind(restoreButton.MouseButton1Click, function()
	State.minimized = false
	main.Visible = true
	restoreButton.Visible = true
end)

Bind(restoreButton.MouseButton2Click, function()
	State.minimized = false

	main.Visible = true
	restoreButton.Visible = true

	if State.settingsOpen then
		settingsFrame.Visible = true
	end

	task.defer(centerMainUI)
end)

Bind(settingsButton.MouseButton1Click, function()
	State.settingsOpen = not State.settingsOpen

	settingsFrame.Visible =
		State.settingsOpen
		and not State.minimized

	refreshSettingsPanel()
end)

Bind(closeSettings.MouseButton1Click, function()
	State.settingsOpen = false
	settingsFrame.Visible = false
end)

Bind(controlButton.MouseButton1Click, function()
	State.changingControlKey = true
	controlButton.Text = "PRESS A KEY..."
	notify("CONTROL KEY", "Nhấn phím mới (ESC = hủy)", 1.6)
end)

Bind(modeButton.MouseButton1Click, function()
	State.mode = State.mode == 1 and 2 or 1

	if State.mode ~= 1 and State.advanceMode then
		setAdvanceMode(false)
	end

	stopRonaldoAdvance()

	State.enabled = false
	State.forceUnanchorActive = false

	if rootPart then
		rootPart.Anchored = false
	end

	unlockPlayer()
	restoreCamera()

	if State.mode == 1 then
		local ball = BallTracker.Ball

		if ball then
			if State.advanceMode then
				camera = workspace.CurrentCamera

				if camera then
					camera.CameraType = Enum.CameraType.Scriptable
				end
			else
				cameraToBall(ball)
			end
		end
	end

	updateUI(true)
	notify("MODE", modeName(), 1.3)
end)

Bind(stealButton.MouseButton1Click, function()
	State.stealBallEnabled = not State.stealBallEnabled

	if State.stealBallEnabled and State.autoGoalEnabled then
		State.stealBallEnabled = false

		notify("STEAL BALL", "Auto Goal đang ON", 1.2)

		updateUI(true)
		return
	end

	if State.stealBallEnabled
		and State.autoStealOffOnGet
		and localHasBall()
	then
		State.stealBallEnabled = false

		notify(
			"STEAL BALL",
			"Tắt ngay — bạn đã có bóng",
			1.3
		)

		updateUI(true)
		return
	end

	updateUI(true)

	notify(
		"STEAL BALL",
		State.stealBallEnabled and "ON" or "OFF",
		1.3
	)
end)

Bind(saeButton.MouseButton1Click, function()
	State.saePassEnabled = not State.saePassEnabled

	if not State.saePassEnabled then
		clearSaeTarget()
	end

	updateUI(true)

	notify(
		"SAE PASS",
		State.saePassEnabled and "ON" or "OFF",
		1.3
	)
end)

Bind(tpButton.MouseButton1Click, startTemporaryTP)
Bind(tpGoalButton.MouseButton1Click, startTPGoal)

Bind(anchorButton.MouseButton1Click, function()
	State.anchorEnabled = not State.anchorEnabled
	State.forceUnanchorActive = false

	if not State.anchorEnabled then
		unlockPlayer()
	elseif State.enabled and State.mode == 1 then
		applyModeLock()
	end

	updateUI(true)
end)

Bind(forceUnanchorButton.MouseButton1Click, forceUnanchor)

Bind(statusButton.MouseButton1Click, function()
	statusPanel.Visible = not statusPanel.Visible

	statusButton.Text =
		statusPanel.Visible
		and "BALL STATUS: ON"
		or "BALL STATUS: OFF"
end)

-- INPUT

Bind(UserInputService.InputBegan, function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		State.leftMouseHeld = true
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		State.rightMouseHeld = true

		if
			State.mode == 2
			and State.ronaldoAdvanceEnabled
			and localHasBall()
		then
			selectRonaldoAdvanceTarget()
		end

		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if State.advanceMode and State.mode == 1 then
		if input.KeyCode == Enum.KeyCode.W then
			State.advanceKeys.W = true
			return
		end

		if input.KeyCode == Enum.KeyCode.A then
			State.advanceKeys.A = true
			return
		end

		if input.KeyCode == Enum.KeyCode.S then
			State.advanceKeys.S = true
			return
		end

		if input.KeyCode == Enum.KeyCode.D then
			State.advanceKeys.D = true
			return
		end

		if input.KeyCode == Enum.KeyCode.Q then
			State.advanceKeys.Q = true
			return
		end

		if input.KeyCode == Enum.KeyCode.E then
			State.advanceKeys.E = true
			return
		end
	end

	if State.changingControlKey then
		if input.KeyCode == Enum.KeyCode.Escape then
			State.changingControlKey = false
			setGeneralControls()
			updateUI(true)
			return
		end

		if input.KeyCode ~= Enum.KeyCode.Unknown then
			State.controlKey = input.KeyCode
			State.changingControlKey = false

			setGeneralControls()
			updateUI(true)

			notify(
				"CONTROL KEY",
				"Set to " .. State.controlKey.Name,
				1.4
			)
		end

		return
	end

	if input.KeyCode == State.controlKey then
		if State.saePassEnabled then
			selectSaePassTarget()
			return
		end

		if
			State.mode == 2
			and State.ronaldoAdvanceEnabled
			and State.ronaldoAdvanceTargetPosition
		then
			startRonaldoAdvance()
			return
		end

		local _, _, ball = getBallState()

		if State.mode == 1 then
			State.enabled = not State.enabled

			if State.enabled then
				State.forceUnanchorActive = false

				if State.advanceMode then
					camera = workspace.CurrentCamera

					if camera then
						camera.CameraType = Enum.CameraType.Scriptable
					end
				elseif ball then
					cameraToBall(ball)
				end

				applyModeLock()

				notify(
					"CONTROL",
					modeName() .. " ACTIVE",
					1.1
				)
			else
				restoreCamera()
				applyModeLock()

				notify("CONTROL", "OFF", 1.0)
			end

			updateUI(true)
			return
		end

		if State.mode == 2 then
			if localHasBall() then
				performMode4Kick(ball)
			else
				notify("MODE 2", "Cần đang cầm bóng", 1.2)
			end

			return
		end
	end

	if gameProcessed then
		return
	end
end)

Bind(UserInputService.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		State.leftMouseHeld = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		State.rightMouseHeld = false
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.W then
			State.advanceKeys.W = false
		elseif input.KeyCode == Enum.KeyCode.A then
			State.advanceKeys.A = false
		elseif input.KeyCode == Enum.KeyCode.S then
			State.advanceKeys.S = false
		elseif input.KeyCode == Enum.KeyCode.D then
			State.advanceKeys.D = false
		elseif input.KeyCode == Enum.KeyCode.Q then
			State.advanceKeys.Q = false
		elseif input.KeyCode == Enum.KeyCode.E then
			State.advanceKeys.E = false
		end
	end
end)

-- LOOP

Bind(RunService.RenderStepped, function()
	if State.saePassActive then
		updateSaePass()
	end
end)

Bind(RunService.Heartbeat, function()
	updateCharacter()

	local state, holder, ball = getBallState()

	refreshBallStatusUI(state, holder)

	updateRonaldoAdvance()

	if State.autoGoalEnabled then
		if localHasBall() then
			performAutoGoalStep()
		else
			spamStealStep()
		end
	elseif State.stealBallEnabled then
		if State.autoStealOffOnGet and localHasBall() then
			State.stealBallEnabled = false

			updateUI(true)

			notify(
				"STEAL BALL",
				"Tự động tắt — bạn đã có bóng",
				1.4
			)
		else
			spamStealStep()
		end
	end

	if State.tpActive then
		if localHasBall() then
			restoreTemporaryTP("Đã nhặt được bóng → quay về")
		else
			updateTPFollowTarget()

			if
				State.tpActive
				and os.clock() - State.tpStartedAt >= State.tpDuration
			then
				restoreTemporaryTP("TP timer expired")
			end
		end
	end

	if State.enabled and State.mode == 1 and ball then
		if not updateAdvanceCamera(ball) then
			controlMode1(ball)
		end
	end

	if State.mode == 1 then
		applyModeLock()
	elseif rootPart and rootPart.Anchored then
		rootPart.Anchored = false
	end

	restoreButton.Visible = true
end)

Bind(player.CharacterAdded, function()
	task.wait(0.5)

	updateCharacter()

	State.enabled = false
	State.forceUnanchorActive = false
	State.autoGoalRunId += 1
	State.autoGoalExecuting = false
	State.stealBallEnabled = false
	State.tpActive = false
	State.tpReturnCFrame = nil
	State.tpGoalActive = false
	State.tpFollowTarget = nil
	State.tpFollowBall = nil
	State.gkSpecialEnabled = false
	State.gkLastGoalPart = nil

	clearSaeTarget()
	stopRonaldoAdvance()

	State.advanceKeys = {
		W = false,
		A = false,
		S = false,
		D = false,
		Q = false,
		E = false
	}

	playerWasLocked = false
	savedWalkSpeed = nil
	savedJumpPower = nil
	savedAutoRotate = nil

	restoreButton.Visible = true

	QueueBallCacheRebuild()
	updateUI(true)
end)

Bind(
	workspace:GetPropertyChangedSignal("CurrentCamera"),
	function()
		camera = workspace.CurrentCamera

		task.defer(function()
			clampGuiPosition(statusPanel)
		end)
	end
)

refreshSettingsPanel()
updateUI(true)
setStatusMini(false)

restoreButton.Visible = true

if shootRemoteReady then
	notify("SHOOT REMOTE", "ShootBall detected", 1.5)
else
	notify("SHOOT REMOTE", "Events.ShootBall chưa tìm thấy", 2)
end

if not VirtualInputManager then
	notify(
		"STEAL BALL",
		"VirtualInputManager không khả dụng — Auto Steal sẽ không gửi E",
		2
	)
end

notify("BALL CONTROLLER", "V4.1 loaded", 1.5)

print("[Ball Controller V4.1] loaded")
