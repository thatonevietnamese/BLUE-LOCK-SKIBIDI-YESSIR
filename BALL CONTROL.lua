--========================================================--
-- BALL CONTROLLER V4.2
-- Refactored / register-limit safe / state cleanup fixed
--========================================================--

--// SERVICES
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM = game:GetService("VirtualInputManager")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")

--========================================================--
-- CONFIG
--========================================================--

local CFG = {
	BALL_NAME = "Ball",

	MIN_SPEED = 1,
	MAX_SPEED = 1000,

	DEFAULT_CONTROL_KEY = Enum.KeyCode.F,
	DEFAULT_STEAL_DISTANCE = 3,

	SAE_PASS_HEIGHT = 300,
	SAE_PASS_SPEED = 260,

	DEFAULT_TP_TIME = 1.5,

	GK_ROLE_NAMES = {
		"gk",
		"goalkeeper",
		"goal keeper",
		"keeper",
	},

	GK_TP_OFFSET = Vector3.new(0, 2.5, 0),
	TP_GOAL_OFFSET = Vector3.new(0, 3, 10),

	SHOOT_FORCE = 100,

	AUTO_STEAL_SCAN_INTERVAL = 0.08,
	BALL_CACHE_REBUILD_COOLDOWN = 0.04,

	ZOOM_MIN = 0.6,
	ZOOM_MAX = 1.6,
	ZOOM_STEP = 0.1,
}

local ModeSettings = {
	[1] = {speed = 60},
	[2] = {speed = 140},
}

--========================================================--
-- STATE
--========================================================--

local State = {
	mode = 1,
	controlKey = CFG.DEFAULT_CONTROL_KEY,

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

	tpDuration = CFG.DEFAULT_TP_TIME,
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
		E = false,
	},

	ronaldoAdvanceEnabled = false,
	ronaldoAdvanceTargetPosition = nil,
	ronaldoAdvanceTargetPart = nil,
	ronaldoAdvanceActive = false,
	ronaldoAdvanceBall = nil,
	ronaldoAdvanceTouchedConnection = nil,
	ronaldoAdvanceStartTime = 0,

	lastStealAction = 0,
	lastAutoGoalAttempt = 0,
}

local Tracker = {
	State = "UNKNOWN",
	Holder = nil,
	Ball = nil,

	LastRebuild = 0,
	RebuildQueued = false,
}

local Char = {
	character = nil,
	humanoid = nil,
	rootPart = nil,

	savedWalkSpeed = nil,
	savedJumpPower = nil,
	savedAutoRotate = nil,
	playerWasLocked = false,
}

local UI = {}

local Connections = {}
local CharacterConnections = {}
local PlayerConnections = {}

local API = {}

local camera = workspace.CurrentCamera

--========================================================--
-- ENV / GLOBAL STOP
--========================================================--

function API.GetEnvironment()
	local env

	pcall(function()
		env = getgenv()
	end)

	return env or _G
end

local GlobalEnv = API.GetEnvironment()

local oldStop = GlobalEnv.__BALL_CONTROLLER_V4_STOP

if oldStop then
	pcall(oldStop)
end

--========================================================--
-- GENERIC HELPERS
--========================================================--

function API.Disconnect(conn)
	if not conn then
		return
	end

	pcall(function()
		conn:Disconnect()
	end)
end

function API.Bind(signal, callback)
	local conn = signal:Connect(callback)
	Connections[#Connections + 1] = conn
	return conn
end

function API.BindLocal(list, signal, callback)
	local conn = signal:Connect(callback)
	list[#list + 1] = conn
	return conn
end

function API.DisconnectList(list)
	for i = 1, #list do
		API.Disconnect(list[i])
	end

	table.clear(list)
end

function API.Notify(titleText, bodyText, duration)
	if not UI.notificationHolder or not UI.notificationHolder.Parent then
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
		{
			Position = UDim2.new(0.5, 0, 0, 8),
		}
	):Play()

	task.delay(duration, function()
		if not card.Parent then
			return
		end

		TweenService:Create(
			card,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad),
			{
				Position = UDim2.new(0.5, 0, 0, -65),
			}
		):Play()

		task.delay(0.22, function()
			if card.Parent then
				card:Destroy()
			end
		end)
	end)
end

--========================================================--
-- CHARACTER
--========================================================--

function API.UpdateCharacter()
	Char.character = LP.Character

	if not Char.character then
		Char.humanoid = nil
		Char.rootPart = nil
		return false
	end

	Char.humanoid = Char.character:FindFirstChildOfClass("Humanoid")
	Char.rootPart = Char.character:FindFirstChild("HumanoidRootPart")

	return Char.humanoid ~= nil and Char.rootPart ~= nil
end

function API.SavePlayerState()
	if not Char.humanoid then
		return
	end

	if Char.savedWalkSpeed == nil then
		Char.savedWalkSpeed = Char.humanoid.WalkSpeed
	end

	if Char.savedJumpPower == nil then
		Char.savedJumpPower = Char.humanoid.JumpPower
	end

	if Char.savedAutoRotate == nil then
		Char.savedAutoRotate = Char.humanoid.AutoRotate
	end
end

function API.UnlockPlayer()
	if not API.UpdateCharacter() then
		Char.playerWasLocked = false
		Char.savedWalkSpeed = nil
		Char.savedJumpPower = nil
		Char.savedAutoRotate = nil
		return
	end

	if Char.playerWasLocked then
		if Char.savedWalkSpeed ~= nil then
			Char.humanoid.WalkSpeed = Char.savedWalkSpeed
		end

		if Char.savedJumpPower ~= nil then
			Char.humanoid.JumpPower = Char.savedJumpPower
		end

		if Char.savedAutoRotate ~= nil then
			Char.humanoid.AutoRotate = Char.savedAutoRotate
		end
	end

	Char.playerWasLocked = false
	Char.savedWalkSpeed = nil
	Char.savedJumpPower = nil
	Char.savedAutoRotate = nil
end

function API.ApplyModeLock()
	if not API.UpdateCharacter() then
		return
	end

	if State.forceUnanchorActive then
		Char.rootPart.Anchored = false
		API.UnlockPlayer()
		return
	end

	if State.enabled and State.anchorEnabled and State.mode == 1 then
		API.SavePlayerState()

		Char.humanoid.WalkSpeed = 0
		Char.humanoid.JumpPower = 0
		Char.humanoid.AutoRotate = false

		Char.rootPart.Anchored = true
		Char.playerWasLocked = true
	else
		Char.rootPart.Anchored = false
		API.UnlockPlayer()
	end
end

function API.ForceUnanchor()
	State.forceUnanchorActive = true

	API.UpdateCharacter()

	if Char.rootPart then
		Char.rootPart.Anchored = false
	end

	API.UnlockPlayer()
	API.Notify("ANCHOR", "Force Unanchor executed", 1.5)
end

--========================================================--
-- BALL TRACKER
--========================================================--

function API.IsMatchPlayer(plr)
	if not plr or not plr.Team then
		return false
	end

	local name = string.lower(plr.Team.Name)

	return string.find(name, "home", 1, true) ~= nil
		or string.find(name, "away", 1, true) ~= nil
end

function API.FindBallInCharacter(char)
	if not char then
		return nil
	end

	local ball = char:FindFirstChild(CFG.BALL_NAME, true)

	if ball and ball:IsA("BasePart") then
		return ball
	end

	return nil
end

function API.FindFreeBall()
	local direct = workspace:FindFirstChild(CFG.BALL_NAME)

	if direct and direct:IsA("BasePart") then
		return direct
	end

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and string.lower(obj.Name) == string.lower(CFG.BALL_NAME) then
			if not obj:IsDescendantOf(LP.Character or Instance.new("Folder")) then
				return obj
			end
		end
	end

	return nil
end

function API.RebuildBallCache(force)
	local now = os.clock()

	if not force and now - Tracker.LastRebuild < CFG.BALL_CACHE_REBUILD_COOLDOWN then
		return Tracker.State, Tracker.Holder, Tracker.Ball
	end

	Tracker.LastRebuild = now
	Tracker.RebuildQueued = false

	Tracker.State = "UNKNOWN"
	Tracker.Holder = nil
	Tracker.Ball = nil

	for _, plr in ipairs(Players:GetPlayers()) do
		if API.IsMatchPlayer(plr) then
			local ball = API.FindBallInCharacter(plr.Character)

			if ball then
				Tracker.State = "HELD"
				Tracker.Holder = plr
				Tracker.Ball = ball
				return Tracker.State, Tracker.Holder, Tracker.Ball
			end
		end
	end

	local freeBall = API.FindFreeBall()

	if freeBall then
		Tracker.State = "FREE"
		Tracker.Holder = nil
		Tracker.Ball = freeBall

		return Tracker.State, nil, freeBall
	end

	Tracker.State = "MISSING"
	return Tracker.State, nil, nil
end

function API.QueueBallCacheRebuild()
	if Tracker.RebuildQueued then
		return
	end

	Tracker.RebuildQueued = true

	task.defer(function()
		if Tracker.RebuildQueued then
			API.RebuildBallCache(false)
		end
	end)
end

function API.GetBallState()
	local state = Tracker.State
	local holder = Tracker.Holder
	local ball = Tracker.Ball

	if state == "HELD" then
		if not holder or not holder.Parent or not holder.Character then
			API.QueueBallCacheRebuild()
			return API.RebuildBallCache(false)
		end

		if not ball or not ball.Parent or not ball:IsDescendantOf(holder.Character) then
			API.QueueBallCacheRebuild()
			return API.RebuildBallCache(false)
		end

		return state, holder, ball
	end

	if state == "FREE" then
		if not ball or not ball.Parent then
			return API.RebuildBallCache(false)
		end

		return state, nil, ball
	end

	if state == "MISSING" then
		local free = API.FindFreeBall()

		if free then
			Tracker.State = "FREE"
			Tracker.Ball = free
			return "FREE", nil, free
		end
	end

	return API.RebuildBallCache(false)
end

function API.LocalHasBall()
	local state, holder = API.GetBallState()
	return state == "HELD" and holder == LP
end

function API.GetPlayerRoot(plr)
	if not plr or not plr.Character then
		return nil
	end

	return plr.Character:FindFirstChild("HumanoidRootPart")
end

function API.SameTeam(plr)
	return plr and LP.Team and plr.Team == LP.Team
end

function API.AttachCharacterTracking(plr, char)
	if not plr or not char then
		return
	end

	API.DisconnectList(CharacterConnections[plr] or {})

	local list = {}

	local initialBall = API.FindBallInCharacter(char)

	if initialBall then
		if not Tracker.Holder then
			Tracker.State = "HELD"
			Tracker.Holder = plr
			Tracker.Ball = initialBall
		elseif Tracker.Holder ~= plr then
			API.QueueBallCacheRebuild()
		end
	end

	API.BindLocal(list, char.DescendantAdded, function(obj)
		if obj.Name ~= CFG.BALL_NAME or not obj:IsA("BasePart") then
			return
		end

		if not Tracker.Holder then
			Tracker.State = "HELD"
			Tracker.Holder = plr
			Tracker.Ball = obj
		elseif Tracker.Holder ~= plr then
			API.QueueBallCacheRebuild()
		end
	end)

	API.BindLocal(list, char.DescendantRemoving, function(obj)
		if obj ~= Tracker.Ball then
			return
		end

		if Tracker.Holder == plr then
			Tracker.State = "UNKNOWN"
			Tracker.Holder = nil
			Tracker.Ball = nil
			API.QueueBallCacheRebuild()
		end
	end)

	API.BindLocal(list, char.AncestryChanged, function(_, parent)
		if parent == nil and Tracker.Holder == plr then
			Tracker.State = "UNKNOWN"
			Tracker.Holder = nil
			Tracker.Ball = nil
			API.QueueBallCacheRebuild()
		end
	end)

	CharacterConnections[plr] = list
end

function API.AttachPlayerTracking(plr)
	if not plr then
		return
	end

	API.DisconnectList(PlayerConnections[plr] or {})

	local list = {}

	if plr.Character then
		API.AttachCharacterTracking(plr, plr.Character)
	end

	API.BindLocal(list, plr.CharacterAdded, function(char)
		API.AttachCharacterTracking(plr, char)
		API.QueueBallCacheRebuild()
	end)

	API.BindLocal(list, plr.CharacterRemoving, function()
		if Tracker.Holder == plr then
			Tracker.State = "UNKNOWN"
			Tracker.Holder = nil
			Tracker.Ball = nil
		end

		API.DisconnectList(CharacterConnections[plr] or {})
		CharacterConnections[plr] = nil

		API.QueueBallCacheRebuild()
	end)

	PlayerConnections[plr] = list
end

function API.InitializeBallTracker()
	for _, plr in ipairs(Players:GetPlayers()) do
		API.AttachPlayerTracking(plr)
	end

	API.RebuildBallCache(true)
end

--========================================================--
-- REMOTE
--========================================================--

local ShootRemote = {
	remote = nil,
	ready = false,
	lastResolve = 0,
}

function API.ResolveShootRemote()
	local now = os.clock()

	if now - ShootRemote.lastResolve < 0.25 then
		return ShootRemote.remote
	end

	ShootRemote.lastResolve = now

	local events = ReplicatedStorage:FindFirstChild("Events")
	local remote = events and events:FindFirstChild("ShootBall")

	ShootRemote.remote = remote
	ShootRemote.ready = remote and remote:IsA("RemoteEvent") or false

	return remote
end

function API.FireShootRemote(direction, force, thirdArg)
	if not ShootRemote.ready or not ShootRemote.remote then
		API.ResolveShootRemote()
	end

	if not ShootRemote.ready or not ShootRemote.remote then
		API.Notify("SHOOT REMOTE", "Không tìm thấy Events.ShootBall", 1.5)
		return false
	end

	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.001 then
		return false
	end

	direction = direction.Unit
	force = math.clamp(
		tonumber(force) or CFG.MIN_SPEED,
		CFG.MIN_SPEED,
		CFG.MAX_SPEED
	)

	local ok = pcall(function()
		ShootRemote.remote:FireServer(
			direction,
			force,
			thirdArg == nil and false or thirdArg
		)
	end)

	return ok
end

API.ResolveShootRemote()

--========================================================--
-- CAMERA
--========================================================--

local CameraState = {
	savedType = nil,
	savedSubject = nil,
}

function API.SaveCamera(ballSubject)
	camera = workspace.CurrentCamera

	if not camera then
		return
	end

	if CameraState.savedType == nil then
		CameraState.savedType = camera.CameraType
	end

	if CameraState.savedSubject == nil and camera.CameraSubject ~= ballSubject then
		CameraState.savedSubject = camera.CameraSubject
	end
end

function API.CameraToBall(ball)
	if not ball then
		return
	end

	camera = workspace.CurrentCamera

	if not camera then
		return
	end

	API.SaveCamera(ball)

	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = ball
end

function API.RestoreCamera()
	camera = workspace.CurrentCamera

	if not camera then
		return
	end

	API.UpdateCharacter()

	camera.CameraType = CameraState.savedType or Enum.CameraType.Custom

	if Char.humanoid and Char.humanoid.Parent then
		camera.CameraSubject = Char.humanoid
	elseif CameraState.savedSubject and CameraState.savedSubject.Parent then
		camera.CameraSubject = CameraState.savedSubject
	end

	CameraState.savedType = nil
	CameraState.savedSubject = nil
end

--========================================================--
-- CHARACTER / ROLE
--========================================================--

function API.GetCharacterNameValue()
	local values = LP:FindFirstChild("Values")
	local obj = values and values:FindFirstChild("CharacterName")

	return obj and tostring(obj.Value) or ""
end

function API.LocalIsBarou()
	return string.lower(API.GetCharacterNameValue()) == "barou"
end

function API.GetRoleName()
	local role = LP:FindFirstChild("Role")

	if role and role.Value ~= nil then
		return string.lower(tostring(role.Value))
	end

	local values = LP:FindFirstChild("Values")
	local valuesRole = values and values:FindFirstChild("Role")

	if valuesRole and valuesRole.Value ~= nil then
		return string.lower(tostring(valuesRole.Value))
	end

	if Char.character then
		local charRole = Char.character:FindFirstChild("Role")

		if charRole and charRole.Value ~= nil then
			return string.lower(tostring(charRole.Value))
		end
	end

	return ""
end

function API.LocalIsGoalkeeper()
	local role = string.gsub(API.GetRoleName(), "%s+", " ")

	for _, name in ipairs(CFG.GK_ROLE_NAMES) do
		if role == name then
			return true
		end
	end

	return false
end

function API.IsHomeTeam()
	return LP.Team and string.lower(LP.Team.Name) == "home"
end

--========================================================--
-- GOALS
--========================================================--

function API.ResolveGoalHitbox(homeSide)
	local map = workspace:FindFirstChild("Map")

	if not map then
		return nil
	end

	local name = homeSide and "PlayerOneGoal" or "PlayerTwoGoal"
	local model = map:FindFirstChild(name)

	if not model then
		return nil
	end

	local score = model:FindFirstChild("ScoreHitbox")
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

function API.ResolveGoalArea(homeSide)
	local name = homeSide and "PlayerOneGoalArea" or "PlayerTwoGoalArea"
	local obj = workspace:FindFirstChild(name)

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

function API.ResolveOwnGoalPart()
	local home = API.IsHomeTeam()

	return API.ResolveGoalArea(home)
		or API.ResolveGoalHitbox(home)
end

function API.ResolveOpponentGoalHitbox()
	local home = API.IsHomeTeam()
	return API.ResolveGoalHitbox(not home)
end

function API.SendVirtualKey(keyCode)
	if not VIM then
		return false
	end

	local ok = pcall(function()
		VIM:SendKeyEvent(true, keyCode, false, game)
		VIM:SendKeyEvent(false, keyCode, false, game)
	end)

	return ok
end

function API.IsInsideGoalArea(position, goalPart)
	if not position or not goalPart then
		return false
	end

	return (position - goalPart.Position).Magnitude <= 18
end

--========================================================--
-- STEAL
--========================================================--

function API.FindBallTarget()
	local state = Tracker.State
	local holder = Tracker.Holder
	local ball = Tracker.Ball

	if state == "HELD" and holder then
		if holder == LP then
			return nil, nil
		end

		if API.LocalIsBarou() or not API.SameTeam(holder) then
			local root = API.GetPlayerRoot(holder)

			if root then
				return root, holder
			end
		end

		return nil, nil
	end

	if state == "FREE" and ball then
		return ball, nil
	end

	return nil, nil
end

function API.SpamStealStep(force)
	if not API.UpdateCharacter() or not Char.rootPart or not Char.rootPart.Parent then
		return
	end

	if API.LocalHasBall() then
		return
	end

	local now = os.clock()

	if not force and now - State.lastStealAction < CFG.AUTO_STEAL_SCAN_INTERVAL then
		return
	end

	local targetPart = API.FindBallTarget()

	if not targetPart or not targetPart.Parent then
		return
	end

	State.lastStealAction = now

	if API.LocalIsGoalkeeper() then
		local ownGoal = API.ResolveOwnGoalPart()

		if ownGoal then
			Char.rootPart.CFrame = CFrame.new(
				ownGoal.Position + CFG.GK_TP_OFFSET
			)

			API.SendVirtualKey(Enum.KeyCode.Q)
		end
	end

	if targetPart.Parent then
		Char.rootPart.CFrame = CFrame.new(
			targetPart.Position
				+ Vector3.new(0, CFG.DEFAULT_STEAL_DISTANCE, 0)
		)

		API.SendVirtualKey(Enum.KeyCode.E)
	end
end

--========================================================--
-- TP
--========================================================--

function API.CurrentBallTarget()
	local state, holder, ball = API.GetBallState()

	if state == "HELD" and holder and holder ~= LP then
		local targetRoot = API.GetPlayerRoot(holder)

		if targetRoot then
			return targetRoot, holder
		end
	end

	if state == "FREE" and ball and ball.Parent then
		return ball, nil
	end

	return nil, nil
end

function API.RestoreTemporaryTP(reason)
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

	if saved and API.UpdateCharacter() and Char.rootPart and Char.rootPart.Parent then
		Char.rootPart.CFrame = saved
	end

	if reason then
		API.Notify("TP RETURN", reason, 1.2)
	end
end

function API.PerformGKTPReturn()
	if not API.LocalIsGoalkeeper() or not API.UpdateCharacter() or not Char.rootPart then
		return false
	end

	local goalPart = API.ResolveOwnGoalPart()

	if not goalPart then
		API.Notify("GK RETURN", "Không tìm thấy GoalArea của đội", 1.5)
		return false
	end

	State.gkLastGoalPart = goalPart
	State.gkSpecialEnabled = true

	if not API.IsInsideGoalArea(Char.rootPart.Position, goalPart) then
		Char.rootPart.CFrame = CFrame.new(
			goalPart.Position + CFG.GK_TP_OFFSET
		)
	end

	task.wait(0.15)

	API.SendVirtualKey(Enum.KeyCode.Q)

	if not API.UpdateCharacter() or not Char.rootPart then
		State.gkSpecialEnabled = false
		State.gkLastGoalPart = nil
		return false
	end

	local targetRoot, holder = API.CurrentBallTarget()

	State.tpFollowTarget = holder
	State.tpFollowBall = holder and nil or targetRoot

	if targetRoot and targetRoot.Parent then
		Char.rootPart.CFrame = CFrame.new(
			targetRoot.Position
				+ Vector3.new(0, CFG.DEFAULT_STEAL_DISTANCE, 0)
		)

		API.Notify(
			"GK RETURN",
			holder
				and ("Q DIVE → TP → " .. holder.Name)
				or "Q DIVE → TP → FREE BALL",
			1.4
		)
	else
		API.Notify("GK RETURN", "Q DIVE → đang chờ bóng", 1.3)
	end

	return true
end

function API.StartTemporaryTP()
	if State.tpActive then
		API.RestoreTemporaryTP("Returned")
		return
	end

	if not API.UpdateCharacter() or not Char.rootPart then
		API.Notify("TP RETURN", "Không tìm thấy nhân vật", 1.2)
		return
	end

	State.tpReturnCFrame = Char.rootPart.CFrame

	if API.LocalIsGoalkeeper() then
		if API.PerformGKTPReturn() then
			State.tpActive = true
			State.tpStartedAt = os.clock()
		else
			State.tpReturnCFrame = nil
		end

		return
	end

	local state, holder, ball = API.GetBallState()

	local targetPosition
	local targetName

	if state == "HELD" and holder and holder ~= LP then
		local targetRoot = API.GetPlayerRoot(holder)

		if targetRoot then
			targetPosition =
				targetRoot.Position
				+ Vector3.new(0, CFG.DEFAULT_STEAL_DISTANCE, 0)

			targetName = holder.Name
		end
	elseif state == "FREE" and ball then
		targetPosition =
			ball.Position
			+ Vector3.new(0, CFG.DEFAULT_STEAL_DISTANCE, 0)

		targetName = "FREE BALL"
	end

	if not targetPosition then
		State.tpReturnCFrame = nil
		API.Notify("TP RETURN", "Không có bóng hợp lệ để TP", 1.3)
		return
	end

	State.tpActive = true
	State.tpStartedAt = os.clock()
	State.tpFollowTarget = state == "HELD" and holder or nil
	State.tpFollowBall = state == "FREE" and ball or nil

	Char.rootPart.CFrame = CFrame.new(targetPosition)

	API.Notify(
		"TP RETURN",
		string.format("TP → %s trong %.2fs", targetName, State.tpDuration),
		1.5
	)
end

function API.UpdateTPFollowTarget()
	if not State.tpActive then
		return
	end

	if not API.UpdateCharacter() or not Char.rootPart then
		return
	end

	if API.LocalHasBall() then
		API.RestoreTemporaryTP("Đã nhặt được bóng → quay về")
		return
	end

	local state, holder, ball = API.GetBallState()
	local targetRoot

	if state == "HELD" and holder and holder ~= LP then
		targetRoot = API.GetPlayerRoot(holder)

		State.tpFollowTarget = holder
		State.tpFollowBall = nil
	elseif state == "FREE" and ball then
		targetRoot = ball

		State.tpFollowTarget = nil
		State.tpFollowBall = ball
	else
		State.tpFollowTarget = nil
		State.tpFollowBall = nil
	end

	if targetRoot and targetRoot.Parent then
		Char.rootPart.CFrame = CFrame.new(
			targetRoot.Position
				+ Vector3.new(0, CFG.DEFAULT_STEAL_DISTANCE, 0)
		)
	end
end

function API.StartTPGoal()
	local goalPart = API.ResolveOpponentGoalHitbox()

	if not goalPart then
		API.Notify(
			"TP GOAL",
			"Không tìm thấy ScoreHitbox đối diện",
			1.3
		)
		return
	end

	local _, _, ball = API.GetBallState()

	if not ball or not ball.Parent or not ball:IsA("BasePart") then
		API.Notify("TP GOAL", "Không tìm thấy bóng hợp lệ", 1.2)
		return
	end

	ball.CFrame = goalPart.CFrame
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero

	State.tpGoalActive = true

	API.Notify(
		"TP GOAL",
		API.IsHomeTeam()
			and "BALL → PLAYER TWO GOAL"
			or "BALL → PLAYER ONE GOAL",
		1.3
	)
end

--========================================================--
-- SAE PASS
--========================================================--

function API.ClearSaeTarget()
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

function API.HighlightSaeTarget(plr)
	if State.targetHighlight then
		State.targetHighlight:Destroy()
		State.targetHighlight = nil
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

function API.GetClosestTeammateToMouse()
	camera = workspace.CurrentCamera

	if not camera then
		return nil
	end

	local mousePos = UIS:GetMouseLocation()

	local best
	local bestDist = math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and API.SameTeam(plr) and plr.Character then
			local hrp = API.GetPlayerRoot(plr)

			if hrp then
				local point, onScreen =
					camera:WorldToViewportPoint(hrp.Position)

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

function API.IsAnyPlayerHoldingBall()
	local state, holder = API.GetBallState()

	return state == "HELD" and holder ~= nil, holder
end

function API.StickBallToTarget(target)
	if not target or not target.Character then
		return
	end

	local targetRoot = API.GetPlayerRoot(target)
	local ball = State.saePassBall

	if not targetRoot then
		return
	end

	if not ball or not ball.Parent then
		local _, _, cached = API.GetBallState()
		ball = cached
		State.saePassBall = ball
	end

	if not ball or not ball.Parent then
		return
	end

	pcall(function()
		ball.AssemblyLinearVelocity = Vector3.zero
		ball.AssemblyAngularVelocity = Vector3.zero

		ball.CFrame =
			targetRoot.CFrame * CFrame.new(0, -1.5, -1)
	end)
end

function API.SelectSaePassTarget()
	if not State.saePassEnabled then
		return false
	end

	local target = API.GetClosestTeammateToMouse()

	if not target then
		API.Notify("SAE PASS", "Không tìm thấy đồng đội", 1.2)
		return false
	end

	local holding = API.LocalHasBall()

	API.HighlightSaeTarget(target)

	State.saePassTarget = target
	State.saePassActive = true
	State.saePassStage = holding and "WAIT_RELEASE" or "STICK"

	local _, _, ball = API.GetBallState()
	State.saePassBall = ball

	API.Notify(
		"SAE PASS",
		holding
			and ("Đã khóa " .. target.Name .. " — chờ nhả bóng")
			or ("Bóng sẽ dính vào " .. target.Name),
		1.4
	)

	return true
end

function API.UpdateSaePass()
	if not State.saePassEnabled then
		return
	end

	if not State.saePassActive or not State.saePassTarget then
		return
	end

	local target = State.saePassTarget

	if not target.Parent or not target.Character then
		API.ClearSaeTarget()
		return
	end

	if API.LocalHasBall() then
		State.saePassStage = "WAIT_RELEASE"
		return
	end

	local isHeld, holder = API.IsAnyPlayerHoldingBall()

	if isHeld then
		-- Target itself getting the ball = pass succeeded.
		if holder == target then
			API.Notify(
				"SAE PASS",
				"Đã chuyển bóng cho " .. target.Name,
				1.0
			)

			API.ClearSaeTarget()
			return
		end

		API.Notify(
			"SAE PASS",
			holder.Name .. " đã nhặt bóng",
			1.0
		)

		API.ClearSaeTarget()
		return
	end

	State.saePassStage = "STICK"
	API.StickBallToTarget(target)
end

--========================================================--
-- RONALDO ADVANCE
--========================================================--

function API.ClearRonaldoTarget()
	State.ronaldoAdvanceTargetPosition = nil
	State.ronaldoAdvanceTargetPart = nil
end

function API.ClearRonaldoTouchedConnection()
	local conn = State.ronaldoAdvanceTouchedConnection

	State.ronaldoAdvanceTouchedConnection = nil

	if conn then
		API.Disconnect(conn)
	end
end

function API.StopRonaldoAdvance()
	State.ronaldoAdvanceActive = false
	State.ronaldoAdvanceBall = nil
	State.ronaldoAdvanceStartTime = 0

	API.ClearRonaldoTouchedConnection()
	API.ClearRonaldoTarget()
end

function API.GetMouseWorldTarget()
	camera = workspace.CurrentCamera

	if not camera then
		return nil, nil
	end

	local mouse = UIS:GetMouseLocation()

	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		Char.character,
	}

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

function API.SelectRonaldoTarget()
	if State.mode ~= 2 or not State.ronaldoAdvanceEnabled then
		return false
	end

	if not API.LocalHasBall() then
		API.Notify(
			"RONALDO ADVANCE",
			"Cần đang cầm bóng",
			1.2
		)

		return false
	end

	local pos, part = API.GetMouseWorldTarget()

	if not pos then
		API.Notify(
			"RONALDO ADVANCE",
			"Không chọn được vị trí",
			1.2
		)

		return false
	end

	State.ronaldoAdvanceTargetPosition = pos
	State.ronaldoAdvanceTargetPart = part

	API.Notify(
		"RONALDO ADVANCE",
		"Đã chọn điểm bay",
		1.1
	)

	return true
end

function API.StartRonaldoAdvance()
	if not State.ronaldoAdvanceEnabled then
		API.Notify(
			"RONALDO ADVANCE",
			"Advance Mode đang OFF",
			1.1
		)

		return false
	end

	if not State.ronaldoAdvanceTargetPosition then
		API.Notify(
			"RONALDO ADVANCE",
			"Chuột phải để chọn điểm trước",
			1.2
		)

		return false
	end

	if not API.LocalHasBall() then
		API.ClearRonaldoTarget()

		API.Notify(
			"RONALDO ADVANCE",
			"Cần đang cầm bóng",
			1.2
		)

		return false
	end

	local _, _, ball = API.GetBallState()

	if not ball then
		return false
	end

	API.ClearRonaldoTouchedConnection()

	local delta =
		State.ronaldoAdvanceTargetPosition
		- ball.Position

	if delta.Magnitude < 0.1 then
		API.StopRonaldoAdvance()
		return false
	end

	local speed = math.clamp(
		ModeSettings[2].speed,
		CFG.MIN_SPEED,
		CFG.MAX_SPEED
	)

	if not API.FireShootRemote(delta.Unit, speed, false) then
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
				API.StopRonaldoAdvance()
				return
			end

			if os.clock() < State.ronaldoAdvanceStartTime then
				return
			end

			if not hit or not hit:IsA("BasePart") then
				return
			end

			if Char.character and hit:IsDescendantOf(Char.character) then
				return
			end

			API.StopRonaldoAdvance()
		end)

	API.Notify(
		"RONALDO ADVANCE",
		"Bắt đầu bay",
		0.9
	)

	return true
end

function API.UpdateRonaldoAdvance()
	if not State.ronaldoAdvanceActive then
		return
	end

	local ball = State.ronaldoAdvanceBall
	local target = State.ronaldoAdvanceTargetPosition

	if not ball or not ball.Parent or not target then
		API.StopRonaldoAdvance()
		return
	end

	if Tracker.Ball ~= ball then
		API.StopRonaldoAdvance()
		return
	end

	local state, holder = API.GetBallState()

	if state ~= "HELD" or holder ~= LP then
		API.StopRonaldoAdvance()
		return
	end

	local delta = target - ball.Position

	if delta.Magnitude <= 3 then
		ball.AssemblyLinearVelocity = Vector3.zero

		API.StopRonaldoAdvance()

		API.Notify(
			"RONALDO ADVANCE",
			"Đã tới điểm",
			0.9
		)

		return
	end

	local speed = math.clamp(
		ModeSettings[2].speed,
		CFG.MIN_SPEED,
		CFG.MAX_SPEED
	)

	ball.AssemblyLinearVelocity =
		delta.Unit * speed
end

--========================================================--
-- MODE 1 / CAMERA CONTROL
--========================================================--

function API.GetFlatCameraDirections()
	camera = workspace.CurrentCamera

	if not camera then
		return
			Vector3.new(0, 0, -1),
			Vector3.new(1, 0, 0)
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

function API.GetCameraDirection()
	camera = workspace.CurrentCamera

	if not camera then
		return Vector3.new(0, 0, -1)
	end

	local dir = camera.CFrame.LookVector

	return dir.Magnitude > 0
		and dir.Unit
		or Vector3.new(0, 0, -1)
end

function API.SetAdvanceMode(value)
	State.advanceMode = value == true

	State.advanceKeys = {
		W = false,
		A = false,
		S = false,
		D = false,
		Q = false,
		E = false,
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
			local ball = Tracker.Ball

			if ball then
				API.CameraToBall(ball)
			else
				API.RestoreCamera()
			end
		end
	end

	if UI.mode1AdvanceButton then
		UI.mode1AdvanceButton.Text =
			State.advanceMode and "ON" or "OFF"
	end
end

function API.UpdateAdvanceCamera(ball)
	if not State.advanceMode
		or not State.enabled
		or not ball
	then
		return false
	end

	camera = workspace.CurrentCamera

	if not camera then
		return false
	end

	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = ball

	local f, r = API.GetFlatCameraDirections()
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
		ModeSettings[1].speed,
		CFG.MIN_SPEED,
		CFG.MAX_SPEED
	)

	if move.Magnitude > 0 then
		ball.AssemblyLinearVelocity = move.Unit * speed
	else
		ball.AssemblyLinearVelocity = Vector3.zero
	end

	return true
end

function API.ControlMode1(ball)
	if not ball then
		return
	end

	ball.AssemblyLinearVelocity =
		API.GetCameraDirection()
		* math.clamp(
			ModeSettings[1].speed,
			CFG.MIN_SPEED,
			CFG.MAX_SPEED
		)
end

function API.PerformMode2Kick(ball)
	if not ball then
		return
	end

	local force = math.clamp(
		ModeSettings[2].speed,
		CFG.MIN_SPEED,
		CFG.MAX_SPEED
	)

	if API.FireShootRemote(
		API.GetCameraDirection(),
		force,
		false
	) then
		API.Notify(
			"RONALDO MODE",
			"ShootBall velocity sent",
			1.1
		)
	end
end

--========================================================--
-- AUTO GOAL
--========================================================--

function API.PerformAutoGoalStep()
	if State.autoGoalExecuting or not State.autoGoalEnabled then
		return
	end

	local now = os.clock()

	if now - State.lastAutoGoalAttempt < 0.08 then
		return
	end

	State.lastAutoGoalAttempt = now

	if not API.UpdateCharacter() or not Char.rootPart then
		return
	end

	local state, holder, ball = API.GetBallState()

	if state ~= "HELD"
		or holder ~= LP
		or not ball
		or not ball.Parent
	then
		return
	end

	local goal = API.ResolveOpponentGoalHitbox()

	if not goal or not goal.Parent then
		return
	end

	State.autoGoalExecuting = true
	State.autoGoalRunId += 1

	local runId = State.autoGoalRunId
	local originalRoot = Char.rootPart
	local savedCFrame = originalRoot.CFrame

	task.spawn(function()
		local ok, err = pcall(function()
			if runId ~= State.autoGoalRunId then
				return
			end

			if not State.autoGoalEnabled then
				return
			end

			if not originalRoot.Parent
				or not goal.Parent
			then
				return
			end

			originalRoot.CFrame = CFrame.new(
				goal.Position + CFG.TP_GOAL_OFFSET,
				goal.Position
			)

			task.wait(0.025)

			if runId ~= State.autoGoalRunId then
				return
			end

			if not State.autoGoalEnabled then
				return
			end

			if not goal.Parent or not originalRoot.Parent then
				return
			end

			local direction =
				goal.Position
				- originalRoot.Position

			if direction.Magnitude > 0.001 then
				API.FireShootRemote(
					direction.Unit,
					CFG.SHOOT_FORCE,
					false
				)
			end

			task.wait(0.025)

			if runId ~= State.autoGoalRunId then
				return
			end

			local _, _, currentBall =
				API.GetBallState()

			if currentBall
				and currentBall.Parent
				and currentBall:IsA("BasePart")
			then
				currentBall.CFrame = goal.CFrame
				currentBall.AssemblyLinearVelocity = Vector3.zero
				currentBall.AssemblyAngularVelocity = Vector3.zero
			end
		end)

		if not ok then
			warn(
				"[Ball Controller] Auto Goal error:",
				err
			)
		end

		if savedCFrame
			and originalRoot
			and originalRoot.Parent
		then
			originalRoot.CFrame = savedCFrame
		end

		if State.autoGoalRunId == runId then
			State.autoGoalExecuting = false
		end
	end)
end

--========================================================--
-- UI BUILD
--========================================================--

function API.Corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

function API.Stroke(parent, color, transparency)
	local s = Instance.new("UIStroke")

	s.Color =
		color
		or Color3.fromRGB(60, 60, 70)

	s.Transparency =
		transparency == nil
		and 0.2
		or transparency

	s.Parent = parent

	return s
end

function API.MakeButton(parent, text, x, y, w, h)
	local b = Instance.new("TextButton")

	b.Size = UDim2.fromOffset(w, h)
	b.Position = UDim2.fromOffset(x, y)

	b.BackgroundColor3 =
		Color3.fromRGB(43, 43, 51)

	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 =
		Color3.fromRGB(235, 235, 240)

	b.TextSize = 12
	b.Font = Enum.Font.GothamMedium
	b.Parent = parent

	API.Corner(b, 7)

	return b
end

function API.MakeLabel(parent, text, x, y, w, h, size)
	local l = Instance.new("TextLabel")

	l.Size = UDim2.fromOffset(w, h)
	l.Position = UDim2.fromOffset(x, y)

	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 =
		Color3.fromRGB(205, 205, 215)

	l.TextSize = size or 12
	l.Font = Enum.Font.GothamMedium
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent

	return l
end

function API.MakeBox(parent, value, x, y, w, h)
	local b = Instance.new("TextBox")

	b.Size = UDim2.fromOffset(w, h)
	b.Position = UDim2.fromOffset(x, y)

	b.BackgroundColor3 =
		Color3.fromRGB(40, 40, 47)

	b.BorderSizePixel = 0
	b.Text = tostring(value)

	b.TextColor3 =
		Color3.fromRGB(255, 255, 255)

	b.PlaceholderColor3 =
		Color3.fromRGB(130, 130, 140)

	b.TextSize = 12
	b.Font = Enum.Font.GothamMedium
	b.ClearTextOnFocus = false
	b.Parent = parent

	API.Corner(b, 7)

	return b
end

function API.ClampGuiPosition(frame)
	camera = workspace.CurrentCamera

	local viewport =
		camera and camera.ViewportSize
		or Vector2.new(1920, 1080)

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

function API.CenterMainUI()
	camera = workspace.CurrentCamera

	local viewport =
		camera and camera.ViewportSize
		or Vector2.new(1920, 1080)

	UI.main.Position = UDim2.fromOffset(
		math.max(
			0,
			(viewport.X - UI.main.AbsoluteSize.X) / 2
		),
		math.max(
			0,
			(viewport.Y - UI.main.AbsoluteSize.Y) / 2
		)
	)

	if State.settingsOpen then
		UI.settingsFrame.Position = UDim2.fromOffset(
			math.max(
				0,
				(viewport.X - UI.settingsFrame.AbsoluteSize.X) / 2
			),
			math.max(
				0,
				(viewport.Y - UI.settingsFrame.AbsoluteSize.Y) / 2
			)
		)
	end
end

function API.SetStatusMini(value)
	UI.statusMini = value

	UI.statusPanel.Size =
		value
		and UI.statusMiniSize
		or UI.statusExpandedSize

	UI.statusState.Visible = not value
	UI.statusOwner.Visible = not value
	UI.statusPlayer.Visible = not value

	UI.statusMin.Text =
		value and "+" or "—"

	task.defer(function()
		API.ClampGuiPosition(UI.statusPanel)
	end)
end

function API.SetUIScale(value)
	value = math.clamp(
		value,
		CFG.ZOOM_MIN,
		CFG.ZOOM_MAX
	)

	value =
		math.floor(value * 100 + 0.5) / 100

	if value == State.uiScale then
		return
	end

	State.uiScale = value

	UI.mainScale.Scale = value
	UI.settingsScale.Scale = value
	UI.statusScale.Scale = value

	task.defer(function()
		API.ClampGuiPosition(UI.main)
		API.ClampGuiPosition(UI.settingsFrame)
		API.ClampGuiPosition(UI.statusPanel)
		API.ClampGuiPosition(UI.restoreButton)
	end)

	API.Notify(
		"GIAO DIỆN",
		"Thu phóng: "
			.. math.floor(value * 100)
			.. "%",
		0.9
	)
end

function API.MakeDraggable(object, handle)
	local dragging = false
	local dragStart
	local startPosition
	local changedConnection

	API.Bind(handle.InputBegan, function(input)
		if input.UserInputType
			~= Enum.UserInputType.MouseButton1
		then
			return
		end

		dragging = true
		dragStart = input.Position
		startPosition = object.Position

		API.Disconnect(changedConnection)

		changedConnection =
			input.Changed:Connect(function()
				if input.UserInputState
					== Enum.UserInputState.End
				then
					dragging = false
					API.Disconnect(changedConnection)
					changedConnection = nil
				end
			end)
	end)

	API.Bind(UIS.InputChanged, function(input)
		if not dragging
			or input.UserInputType
				~= Enum.UserInputType.MouseMovement
		then
			return
		end

		local delta =
			input.Position - dragStart

		local x =
			startPosition.X.Offset + delta.X

		local y =
			startPosition.Y.Offset + delta.Y

		camera = workspace.CurrentCamera

		local viewport =
			camera and camera.ViewportSize
			or Vector2.new(1920, 1080)

		x = math.clamp(
			x,
			0,
			math.max(
				0,
				viewport.X - object.AbsoluteSize.X
			)
		)

		y = math.clamp(
			y,
			0,
			math.max(
				0,
				viewport.Y - object.AbsoluteSize.Y
			)
		)

		object.Position = UDim2.fromOffset(x, y)
	end)
end

function API.BuildUI()
	local gui = Instance.new("ScreenGui")

	gui.Name = "BallController"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior =
		Enum.ZIndexBehavior.Sibling

	gui.Parent = PlayerGui

	UI.gui = gui

	-- MAIN
	local main = Instance.new("Frame")

	main.Name = "Main"
	main.Size = UDim2.fromOffset(350, 445)
	main.Position =
		UDim2.new(0, 25, 0.5, -222)

	main.BackgroundColor3 =
		Color3.fromRGB(24, 24, 29)

	main.BorderSizePixel = 0
	main.Parent = gui

	UI.main = main

	API.Corner(main, 12)
	API.Stroke(
		main,
		Color3.fromRGB(60, 60, 70),
		0.2
	)

	UI.title = API.MakeLabel(
		main,
		"⚽ BALL CONTROLLER V4.2",
		10,
		5,
		215,
		35,
		18
	)

	UI.title.Font = Enum.Font.GothamBold

	UI.zoomOutButton = API.MakeButton(
		main,
		"-",
		228,
		10,
		26,
		28
	)

	UI.zoomOutButton.TextSize = 18

	UI.zoomInButton = API.MakeButton(
		main,
		"+",
		256,
		10,
		26,
		28
	)

	UI.zoomInButton.TextSize = 18

	UI.minimizeButton = API.MakeButton(
		main,
		"—",
		312,
		10,
		28,
		28
	)

	UI.minimizeButton.TextSize = 18

	UI.mainScale = Instance.new("UIScale")
	UI.mainScale.Scale = 1
	UI.mainScale.Parent = main

	UI.statusLabel = API.MakeLabel(
		main,
		"Status: READY",
		10,
		42,
		320,
		22,
		13
	)

	UI.ballStatus = API.MakeLabel(
		main,
		"BALL: SEARCHING...",
		10,
		64,
		320,
		22,
		12
	)

	UI.controlButton = API.MakeButton(
		main,
		"CONTROL KEY: F",
		10,
		92,
		160,
		36
	)

	UI.modeButton = API.MakeButton(
		main,
		"MODE: 1 [CAMERA]",
		180,
		92,
		160,
		36
	)

	UI.anchorButton = API.MakeButton(
		main,
		"ANCHOR: ON",
		10,
		136,
		160,
		36
	)

	UI.forceUnanchorButton = API.MakeButton(
		main,
		"FORCE UNANCHOR",
		180,
		136,
		160,
		36
	)

	UI.stealButton = API.MakeButton(
		main,
		"STEAL BALL: OFF",
		10,
		180,
		160,
		36
	)

	UI.saeButton = API.MakeButton(
		main,
		"SAE PASS: OFF",
		180,
		180,
		160,
		36
	)

	UI.settingsButton = API.MakeButton(
		main,
		"⚙ SETTINGS",
		10,
		224,
		160,
		36
	)

	UI.statusButton = API.MakeButton(
		main,
		"BALL STATUS: ON",
		180,
		224,
		160,
		36
	)

	UI.tpButton = API.MakeButton(
		main,
		"TP RETURN",
		10,
		268,
		150,
		36
	)

	UI.tpGoalButton = API.MakeButton(
		main,
		"TP GOAL",
		170,
		268,
		170,
		36
	)

	UI.tpTimeBox = API.MakeBox(
		main,
		State.tpDuration,
		250,
		310,
		90,
		36
	)

	UI.info = API.MakeLabel(
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

	UI.info.TextWrapped = true
	UI.info.TextYAlignment =
		Enum.TextYAlignment.Top

	UI.info.TextColor3 =
		Color3.fromRGB(145, 145, 155)

	-- RESTORE
	UI.restoreButton = API.MakeButton(
		gui,
		"⚽",
		0,
		0,
		48,
		48
	)

	UI.restoreButton.Visible = true
	UI.restoreButton.TextSize = 23

	API.Corner(UI.restoreButton, 24)

	API.Stroke(
		UI.restoreButton,
		Color3.fromRGB(65, 65, 75),
		0.1
	)

	-- NOTIFICATIONS
	UI.notificationHolder = Instance.new("Frame")

	UI.notificationHolder.Name =
		"Notifications"

	UI.notificationHolder.Size =
		UDim2.fromOffset(320, 300)

	UI.notificationHolder.AnchorPoint =
		Vector2.new(0.5, 0)

	UI.notificationHolder.Position =
		UDim2.new(0.5, 0, 0, 0)

	UI.notificationHolder.BackgroundTransparency = 1
	UI.notificationHolder.Parent = gui

	local layout = Instance.new("UIListLayout")

	layout.Padding = UDim.new(0, 7)
	layout.HorizontalAlignment =
		Enum.HorizontalAlignment.Center

	layout.VerticalAlignment =
		Enum.VerticalAlignment.Top

	layout.Parent = UI.notificationHolder

	-- STATUS PANEL
	UI.statusPanel = Instance.new("Frame")

	UI.statusPanel.Name =
		"BallStatusPanel"

	UI.statusPanel.Size =
		UDim2.fromOffset(245, 125)

	UI.statusPanel.Position =
		UDim2.new(0, 390, 0, 80)

	UI.statusPanel.BackgroundColor3 =
		Color3.fromRGB(22, 22, 27)

	UI.statusPanel.BorderSizePixel = 0
	UI.statusPanel.Parent = gui

	API.Corner(UI.statusPanel, 10)

	API.Stroke(
		UI.statusPanel,
		Color3.fromRGB(60, 60, 70),
		0.15
	)

	UI.statusScale = Instance.new("UIScale")
	UI.statusScale.Scale = 1
	UI.statusScale.Parent = UI.statusPanel

	UI.statusTitle = API.MakeLabel(
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

	UI.statusMin = API.MakeButton(
		UI.statusPanel,
		"—",
		180,
		6,
		25,
		23
	)

	UI.statusClose = API.MakeButton(
		UI.statusPanel,
		"×",
		210,
		6,
		25,
		23
	)

	UI.statusState = API.MakeLabel(
		UI.statusPanel,
		"STATUS: SEARCHING",
		10,
		35,
		220,
		22,
		12
	)

	UI.statusOwner = API.MakeLabel(
		UI.statusPanel,
		"OWNER: —",
		10,
		58,
		220,
		22,
		12
	)

	UI.statusPlayer = API.MakeLabel(
		UI.statusPanel,
		"CONTROL: OFF",
		10,
		81,
		220,
		22,
		12
	)

	UI.statusMini = false
	UI.statusExpandedSize =
		UDim2.fromOffset(245, 125)

	UI.statusMiniSize =
		UDim2.fromOffset(245, 34)

	-- SETTINGS
	UI.settingsFrame = Instance.new("Frame")

	UI.settingsFrame.Name = "Settings"
	UI.settingsFrame.Size = UDim2.fromOffset(490, 320)

	UI.settingsFrame.Position =
		UDim2.new(0, 390, 0.5, -160)

	UI.settingsFrame.BackgroundColor3 =
		Color3.fromRGB(22, 22, 27)

	UI.settingsFrame.BorderSizePixel = 0
	UI.settingsFrame.Visible = false
	UI.settingsFrame.Parent = gui

	API.Corner(UI.settingsFrame, 12)

	API.Stroke(
		UI.settingsFrame,
		Color3.fromRGB(60, 60, 70),
		0.15
	)

	UI.settingsTitle = API.MakeLabel(
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

	-- Fixed overlap from old V4.1:
	UI.settingsZoomOutButton =
		API.MakeButton(
			UI.settingsFrame,
			"-",
			378,
			8,
			26,
			28
		)

	UI.settingsZoomInButton =
		API.MakeButton(
			UI.settingsFrame,
			"+",
			406,
			8,
			26,
			28
		)

	UI.closeSettings =
		API.MakeButton(
			UI.settingsFrame,
			"X",
			454,
			8,
			28,
			28
		)

	UI.settingsScale = Instance.new("UIScale")
	UI.settingsScale.Scale = 1
	UI.settingsScale.Parent =
		UI.settingsFrame

	UI.tabs = {}

	local tabNames = {
		"GENERAL",
		"MODE 1",
		"MODE 2",
	}

	for i = 1, 3 do
		UI.tabs[i] = API.MakeButton(
			UI.settingsFrame,
			tabNames[i],
			10 + (i - 1) * 110,
			48,
			104,
			30
		)
	end

	UI.settingsContent = Instance.new("Frame")

	UI.settingsContent.Size =
		UDim2.new(1, -20, 1, -90)

	UI.settingsContent.Position =
		UDim2.fromOffset(10, 88)

	UI.settingsContent.BackgroundTransparency = 1
	UI.settingsContent.Parent =
		UI.settingsFrame

	local C = UI.settingsContent

	UI.generalTitle = API.MakeLabel(
		C,
		"GENERAL SETTINGS",
		10,
		8,
		220,
		24,
		13
	)

	UI.generalTitle.Font =
		Enum.Font.GothamBold

	UI.generalControlLabel = API.MakeLabel(
		C,
		"CONTROL KEY",
		10,
		38,
		110,
		25,
		12
	)

	UI.generalControlButton =
		API.MakeButton(
			C,
			"F",
			120,
			34,
			120,
			32
		)

	UI.generalAnchorLabel = API.MakeLabel(
		C,
		"ANCHOR",
		10,
		78,
		110,
		25,
		12
	)

	UI.generalAnchorButton =
		API.MakeButton(
			C,
			"ON",
			120,
			74,
			120,
			32
		)

	UI.generalAutoStealLabel =
		API.MakeLabel(
			C,
			"AUTO STEAL OFF",
			10,
			118,
			110,
			25,
			12
		)

	UI.generalAutoStealButton =
		API.MakeButton(
			C,
			"ON",
			120,
			114,
			120,
			32
		)

	UI.generalTPLabel =
		API.MakeLabel(
			C,
			"TP RETURN TIME",
			10,
			158,
			110,
			25,
			12
		)

	UI.generalTPBox =
		API.MakeBox(
			C,
			State.tpDuration,
			120,
			154,
			120,
			32
		)

	UI.generalAutoGoalLabel =
		API.MakeLabel(
			C,
			"AUTO GOAL",
			10,
			198,
			110,
			25,
			12
		)

	UI.generalAutoGoalButton =
		API.MakeButton(
			C,
			"OFF",
			120,
			194,
			120,
			32
		)

	UI.generalHint = API.MakeLabel(
		C,
		"Auto Goal tự cướp bóng và ghi bàn. TP Return/GK follow bóng đến khi local có bóng.",
		255,
		38,
		215,
		175,
		11
	)

	UI.generalHint.TextWrapped = true
	UI.generalHint.TextYAlignment =
		Enum.TextYAlignment.Top

	UI.generalHint.TextColor3 =
		Color3.fromRGB(145, 145, 155)

	-- MODE 1
	UI.mode1Label = API.MakeLabel(
		C,
		"SPEED",
		10,
		10,
		110,
		25,
		12
	)

	UI.mode1Box =
		API.MakeBox(
			C,
			ModeSettings[1].speed,
			120,
			6,
			220,
			32
		)

	UI.mode1Hint = API.MakeLabel(
		C,
		"Mode 1 điều khiển bóng theo camera.",
		10,
		70,
		440,
		60,
		11
	)

	UI.mode1Hint.TextWrapped = true
	UI.mode1Hint.TextColor3 =
		Color3.fromRGB(145, 145, 155)

	UI.mode1AdvanceLabel =
		API.MakeLabel(
			C,
			"ADVANCE MODE",
			10,
			120,
			110,
			25,
			12
		)

	UI.mode1AdvanceButton =
		API.MakeButton(
			C,
			"OFF",
			120,
			116,
			120,
			32
		)

	UI.mode1AdvanceHint =
		API.MakeLabel(
			C,
			"Camera bám bóng; WASD di chuyển, Q/E thay đổi độ cao.",
			10,
			160,
			440,
			55,
			11
		)

	UI.mode1AdvanceHint.TextWrapped = true
	UI.mode1AdvanceHint.TextColor3 =
		Color3.fromRGB(145, 145, 155)

	-- MODE 2
	UI.mode2Label = API.MakeLabel(
		C,
		"SPEED",
		10,
		10,
		110,
		25,
		12
	)

	UI.mode2Box =
		API.MakeBox(
			C,
			ModeSettings[2].speed,
			120,
			6,
			220,
			32
		)

	UI.mode2Hint = API.MakeLabel(
		C,
		"Mode 2 dùng ShootBall cho cú sút thường.",
		10,
		70,
		440,
		45,
		11
	)

	UI.mode2Hint.TextWrapped = true
	UI.mode2Hint.TextColor3 =
		Color3.fromRGB(145, 145, 155)

	UI.mode2AdvanceLabel =
		API.MakeLabel(
			C,
			"ADVANCE MODE",
			10,
			122,
			110,
			25,
			12
		)

	UI.mode2AdvanceButton =
		API.MakeButton(
			C,
			"OFF",
			120,
			118,
			120,
			32
		)

	UI.mode2AdvanceHint =
		API.MakeLabel(
			C,
			"RMB chọn điểm, F để bóng bay đến điểm đó.",
			10,
			160,
			440,
			55,
			11
		)

	UI.mode2AdvanceHint.TextWrapped = true
	UI.mode2AdvanceHint.TextColor3 =
		Color3.fromRGB(145, 145, 155)
end

--========================================================--
-- UI STATE
--========================================================--

local UiCache = {
	enabled = nil,
	mode = nil,
	controlKey = nil,
	steal = nil,
	sae = nil,
	anchor = nil,
	autoGoal = nil,

	ballState = nil,
	ballHolder = nil,
	settingsTab = 1,
}

function API.ModeName()
	return State.mode == 1
		and "MODE 1 [CAMERA]"
		or "MODE 2 [RONALDO]"
end

function API.SetGeneralControls()
	UI.generalControlButton.Text =
		State.controlKey.Name

	UI.generalAnchorButton.Text =
		State.anchorEnabled
		and "ON"
		or "OFF"

	UI.generalAutoStealButton.Text =
		State.autoStealOffOnGet
		and "ON"
		or "OFF"

	UI.generalTPBox.Text =
		tostring(State.tpDuration)

	UI.generalAutoGoalButton.Text =
		State.autoGoalEnabled
		and "ON"
		or "OFF"
end

function API.RefreshSettingsPanel()
	local tab = UiCache.settingsTab

	local general = tab == 1
	local mode1 = tab == 2
	local mode2 = tab == 3

	UI.generalTitle.Visible = general
	UI.generalControlLabel.Visible = general
	UI.generalControlButton.Visible = general
	UI.generalAnchorLabel.Visible = general
	UI.generalAnchorButton.Visible = general
	UI.generalAutoStealLabel.Visible = general
	UI.generalAutoStealButton.Visible = general
	UI.generalTPLabel.Visible = general
	UI.generalTPBox.Visible = general
	UI.generalAutoGoalLabel.Visible = general
	UI.generalAutoGoalButton.Visible = general
	UI.generalHint.Visible = general

	UI.mode1Label.Visible = mode1
	UI.mode1Box.Visible = mode1
	UI.mode1Hint.Visible = mode1
	UI.mode1AdvanceLabel.Visible = mode1
	UI.mode1AdvanceButton.Visible = mode1
	UI.mode1AdvanceHint.Visible = mode1

	UI.mode2Label.Visible = mode2
	UI.mode2Box.Visible = mode2
	UI.mode2Hint.Visible = mode2
	UI.mode2AdvanceLabel.Visible = mode2
	UI.mode2AdvanceButton.Visible = mode2
	UI.mode2AdvanceHint.Visible = mode2

	API.SetGeneralControls()

	UI.mode1AdvanceButton.Text =
		State.advanceMode and "ON" or "OFF"

	UI.mode2AdvanceButton.Text =
		State.ronaldoAdvanceEnabled
		and "ON"
		or "OFF"
end

function API.UpdateUI(force)
	local changed =
		force
		or State.enabled ~= UiCache.enabled
		or State.mode ~= UiCache.mode
		or State.controlKey ~= UiCache.controlKey
		or State.stealBallEnabled ~= UiCache.steal
		or State.saePassEnabled ~= UiCache.sae
		or State.anchorEnabled ~= UiCache.anchor
		or State.autoGoalEnabled ~= UiCache.autoGoal

	if not changed then
		return
	end

	UiCache.enabled = State.enabled
	UiCache.mode = State.mode
	UiCache.controlKey = State.controlKey
	UiCache.steal = State.stealBallEnabled
	UiCache.sae = State.saePassEnabled
	UiCache.anchor = State.anchorEnabled
	UiCache.autoGoal = State.autoGoalEnabled

	UI.controlButton.Text =
		"CONTROL KEY: "
		.. State.controlKey.Name

	UI.modeButton.Text = API.ModeName()

	UI.statusLabel.Text =
		State.enabled
		and "Status: ACTIVE"
		or "Status: READY"

	UI.statusLabel.TextColor3 =
		State.enabled
		and Color3.fromRGB(100, 255, 130)
		or Color3.fromRGB(255, 205, 100)

	UI.stealButton.Text =
		State.stealBallEnabled
		and "STEAL BALL: ON"
		or "STEAL BALL: OFF"

	UI.saeButton.Text =
		State.saePassEnabled
		and "SAE PASS: ON"
		or "SAE PASS: OFF"

	UI.anchorButton.Text =
		State.anchorEnabled
		and "ANCHOR: ON"
		or "ANCHOR: OFF"

	UI.generalAutoGoalButton.Text =
		State.autoGoalEnabled
		and "ON"
		or "OFF"
end

function API.UpdateBallStatus(state, holder)
	if state == "HELD" and holder then
		UI.ballStatus.Text =
			"BALL: HELD — "
			.. holder.Name

		UI.statusState.Text =
			"STATUS: HELD"

		UI.statusOwner.Text =
			"OWNER: "
			.. holder.Name

		UI.statusState.TextColor3 =
			holder == LP
			and Color3.fromRGB(100, 255, 255)
			or (
				API.SameTeam(holder)
				and Color3.fromRGB(100, 255, 130)
				or Color3.fromRGB(255, 100, 100)
			)

	elseif state == "FREE" then
		UI.ballStatus.Text = "BALL: FREE"

		UI.statusState.Text =
			"STATUS: FREE"

		UI.statusOwner.Text =
			"OWNER: NONE"

		UI.statusState.TextColor3 =
			Color3.fromRGB(255, 215, 100)
	else
		UI.ballStatus.Text =
			"BALL: NOT FOUND"

		UI.statusState.Text =
			"STATUS: NOT FOUND"

		UI.statusOwner.Text =
			"OWNER: —"

		UI.statusState.TextColor3 =
			Color3.fromRGB(255, 100, 100)
	end

	UI.statusPlayer.Text =
		"CONTROL: "
		.. (
			State.enabled
			and "ACTIVE"
			or "OFF"
		)

	UI.statusPlayer.TextColor3 =
		State.enabled
		and Color3.fromRGB(100, 255, 130)
		or Color3.fromRGB(180, 180, 190)
end

function API.RefreshBallStatusUI(state, holder)
	if state == UiCache.ballState
		and holder == UiCache.ballHolder
	then
		return
	end

	UiCache.ballState = state
	UiCache.ballHolder = holder

	API.UpdateBallStatus(state, holder)
end

--========================================================--
-- UI EVENTS
--========================================================--

function API.ConnectUI()
	API.MakeDraggable(UI.main, UI.title)
	API.MakeDraggable(UI.settingsFrame, UI.settingsTitle)

	UI.main.Active = true
	UI.settingsFrame.Active = true
	UI.statusPanel.Active = true

	API.Bind(UI.zoomOutButton.MouseButton1Click, function()
		API.SetUIScale(
			State.uiScale - CFG.ZOOM_STEP
		)
	end)

	API.Bind(UI.zoomInButton.MouseButton1Click, function()
		API.SetUIScale(
			State.uiScale + CFG.ZOOM_STEP
		)
	end)

	API.Bind(
		UI.settingsZoomOutButton.MouseButton1Click,
		function()
			API.SetUIScale(
				State.uiScale - CFG.ZOOM_STEP
			)
		end
	)

	API.Bind(
		UI.settingsZoomInButton.MouseButton1Click,
		function()
			API.SetUIScale(
				State.uiScale + CFG.ZOOM_STEP
			)
		end
	)

	API.Bind(UI.statusMin.MouseButton1Click, function()
		API.SetStatusMini(not UI.statusMini)
	end)

	API.Bind(UI.statusClose.MouseButton1Click, function()
		UI.statusPanel.Visible = false
		UI.statusButton.Text =
			"BALL STATUS: OFF"
	end)

	API.Bind(UI.minimizeButton.MouseButton1Click, function()
		State.minimized = true

		UI.restoreButton.Position =
			UI.main.Position

		API.ClampGuiPosition(
			UI.restoreButton
		)

		UI.main.Visible = false
		UI.settingsFrame.Visible = false
		UI.restoreButton.Visible = true
	end)

	API.Bind(UI.restoreButton.MouseButton1Click, function()
		State.minimized = false
		UI.main.Visible = true
		UI.restoreButton.Visible = true
	end)

	API.Bind(UI.restoreButton.MouseButton2Click, function()
		State.minimized = false
		UI.main.Visible = true
		UI.restoreButton.Visible = true

		if State.settingsOpen then
			UI.settingsFrame.Visible = true
		end

		task.defer(API.CenterMainUI)
	end)

	API.Bind(UI.settingsButton.MouseButton1Click, function()
		State.settingsOpen = not State.settingsOpen

		UI.settingsFrame.Visible =
			State.settingsOpen
			and not State.minimized

		API.RefreshSettingsPanel()
	end)

	API.Bind(UI.closeSettings.MouseButton1Click, function()
		State.settingsOpen = false
		UI.settingsFrame.Visible = false
	end)

	API.Bind(UI.statusButton.MouseButton1Click, function()
		UI.statusPanel.Visible =
			not UI.statusPanel.Visible

		UI.statusButton.Text =
			UI.statusPanel.Visible
			and "BALL STATUS: ON"
			or "BALL STATUS: OFF"
	end)

	API.Bind(UI.controlButton.MouseButton1Click, function()
		State.changingControlKey = true

		UI.controlButton.Text =
			"PRESS A KEY..."

		API.Notify(
			"CONTROL KEY",
			"Nhấn phím mới (ESC = hủy)",
			1.6
		)
	end)

	API.Bind(UI.forceUnanchorButton.MouseButton1Click, function()
		API.ForceUnanchor()
	end)

	API.Bind(UI.anchorButton.MouseButton1Click, function()
		State.anchorEnabled =
			not State.anchorEnabled

		State.forceUnanchorActive = false

		if State.anchorEnabled
			and State.enabled
			and State.mode == 1
		then
			API.ApplyModeLock()
		else
			API.UnlockPlayer()

			if Char.rootPart then
				Char.rootPart.Anchored = false
			end
		end

		API.UpdateUI(true)
	end)

	API.Bind(UI.stealButton.MouseButton1Click, function()
		State.stealBallEnabled =
			not State.stealBallEnabled

		if State.stealBallEnabled
			and State.autoGoalEnabled
		then
			State.stealBallEnabled = false

			API.Notify(
				"STEAL BALL",
				"Auto Goal đang ON",
				1.2
			)

			API.UpdateUI(true)
			return
		end

		if State.stealBallEnabled
			and State.autoStealOffOnGet
			and API.LocalHasBall()
		then
			State.stealBallEnabled = false

			API.Notify(
				"STEAL BALL",
				"Tắt ngay — bạn đã có bóng",
				1.3
			)

			API.UpdateUI(true)
			return
		end

		API.UpdateUI(true)

		API.Notify(
			"STEAL BALL",
			State.stealBallEnabled
				and "ON"
				or "OFF",
			1.3
		)
	end)

	API.Bind(UI.saeButton.MouseButton1Click, function()
		State.saePassEnabled =
			not State.saePassEnabled

		if not State.saePassEnabled then
			API.ClearSaeTarget()
		end

		API.UpdateUI(true)

		API.Notify(
			"SAE PASS",
			State.saePassEnabled
				and "ON"
				or "OFF",
			1.3
		)
	end)

	API.Bind(UI.tpButton.MouseButton1Click, function()
		API.StartTemporaryTP()
	end)

	API.Bind(UI.tpGoalButton.MouseButton1Click, function()
		API.StartTPGoal()
	end)

	API.Bind(UI.modeButton.MouseButton1Click, function()
		State.mode =
			State.mode == 1 and 2 or 1

		if State.mode ~= 1 and State.advanceMode then
			API.SetAdvanceMode(false)
		end

		API.StopRonaldoAdvance()

		State.enabled = false
		State.forceUnanchorActive = false

		if Char.rootPart then
			Char.rootPart.Anchored = false
		end

		API.UnlockPlayer()
		API.RestoreCamera()

		API.UpdateUI(true)

		API.Notify(
			"MODE",
			API.ModeName(),
			1.3
		)
	end)

	-- SETTINGS TABS
	for i = 1, 3 do
		local index = i

		API.Bind(
			UI.tabs[index].MouseButton1Click,
			function()
				UiCache.settingsTab = index
				API.RefreshSettingsPanel()
			end
		)
	end

	-- GENERAL
	API.Bind(
		UI.generalControlButton.MouseButton1Click,
		function()
			State.changingControlKey = true

			UI.generalControlButton.Text =
				"PRESS KEY"

			API.Notify(
				"CONTROL KEY",
				"Nhấn phím mới (ESC = hủy)",
				1.6
			)
		end
	)

	API.Bind(
		UI.generalAnchorButton.MouseButton1Click,
		function()
			State.anchorEnabled =
				not State.anchorEnabled

			State.forceUnanchorActive = false

			API.ApplyModeLock()
			API.SetGeneralControls()
			API.UpdateUI(true)
		end
	)

	API.Bind(
		UI.generalAutoStealButton.MouseButton1Click,
		function()
			State.autoStealOffOnGet =
				not State.autoStealOffOnGet

			API.SetGeneralControls()

			API.Notify(
				"AUTO STEAL",
				State.autoStealOffOnGet
					and "OFF ON GET: ON"
					or "OFF ON GET: OFF",
				1.1
			)
		end
	)

	API.Bind(
		UI.generalTPBox.FocusLost,
		function()
			local n =
				tonumber(UI.generalTPBox.Text)

			if not n then
				UI.generalTPBox.Text =
					tostring(State.tpDuration)
				return
			end

			State.tpDuration =
				math.clamp(n, 0.1, 60)

			UI.generalTPBox.Text =
				tostring(State.tpDuration)

			UI.tpTimeBox.Text =
				tostring(State.tpDuration)
		end
	)

	API.Bind(
		UI.generalAutoGoalButton.MouseButton1Click,
		function()
			State.autoGoalEnabled =
				not State.autoGoalEnabled

			State.autoGoalRunId += 1
			State.autoGoalExecuting = false

			if State.autoGoalEnabled then
				State.stealBallEnabled = false

				API.Notify(
					"AUTO GOAL",
					"ON — tự cướp bóng + tự ghi bàn",
					1.4
				)
			else
				API.Notify(
					"AUTO GOAL",
					"OFF",
					1.1
				)
			end

			API.SetGeneralControls()
			API.UpdateUI(true)
		end
	)

	API.Bind(
		UI.tpTimeBox.FocusLost,
		function()
			local n =
				tonumber(UI.tpTimeBox.Text)

			if not n then
				UI.tpTimeBox.Text =
					tostring(State.tpDuration)
				return
			end

			State.tpDuration =
				math.clamp(n, 0.1, 60)

			UI.tpTimeBox.Text =
				tostring(State.tpDuration)

			UI.generalTPBox.Text =
				tostring(State.tpDuration)
		end
	)

	-- MODE 1
	API.Bind(
		UI.mode1Box.FocusLost,
		function()
			local n =
				tonumber(UI.mode1Box.Text)

			if not n then
				UI.mode1Box.Text =
					tostring(ModeSettings[1].speed)
				return
			end

			ModeSettings[1].speed =
				math.clamp(
					n,
					CFG.MIN_SPEED,
					CFG.MAX_SPEED
				)

			UI.mode1Box.Text =
				tostring(ModeSettings[1].speed)
		end
	)

	API.Bind(
		UI.mode1AdvanceButton.MouseButton1Click,
		function()
			API.SetAdvanceMode(
				not State.advanceMode
			)

			API.Notify(
				"ADVANCE MODE",
				State.advanceMode
					and "ON"
					or "OFF",
				1.2
			)
		end
	)

	-- MODE 2
	API.Bind(
		UI.mode2Box.FocusLost,
		function()
			local n =
				tonumber(UI.mode2Box.Text)

			if not n then
				UI.mode2Box.Text =
					tostring(ModeSettings[2].speed)
				return
			end

			ModeSettings[2].speed =
				math.clamp(
					n,
					CFG.MIN_SPEED,
					CFG.MAX_SPEED
				)

			UI.mode2Box.Text =
				tostring(ModeSettings[2].speed)
		end
	)

	API.Bind(
		UI.mode2AdvanceButton.MouseButton1Click,
		function()
			State.ronaldoAdvanceEnabled =
				not State.ronaldoAdvanceEnabled

			if not State.ronaldoAdvanceEnabled then
				API.StopRonaldoAdvance()
			end

			API.RefreshSettingsPanel()

			API.Notify(
				"RONALDO ADVANCE",
				State.ronaldoAdvanceEnabled
					and "ON — RMB chọn điểm → F"
					or "OFF",
				1.3
			)
		end
	)

	-- ZOOM WHEEL
	API.Bind(UIS.InputChanged, function(input)
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
			API.SetUIScale(
				State.uiScale + CFG.ZOOM_STEP
			)
		elseif input.Position.Z < 0 then
			API.SetUIScale(
				State.uiScale - CFG.ZOOM_STEP
			)
		end
	end)

	-- STATUS DRAG
	local draggingStatus = false
	local dragStart
	local dragPosition

	API.Bind(UI.statusTitle.InputBegan, function(input)
		if input.UserInputType
			~= Enum.UserInputType.MouseButton1
		then
			return
		end

		draggingStatus = true
		dragStart = input.Position
		dragPosition = UI.statusPanel.Position

		local changed

		changed =
			input.Changed:Connect(function()
				if input.UserInputState
					== Enum.UserInputState.End
				then
					draggingStatus = false
					API.Disconnect(changed)
					changed = nil
				end
			end)
	end)

	API.Bind(UIS.InputChanged, function(input)
		if not draggingStatus
			or input.UserInputType
				~= Enum.UserInputType.MouseMovement
		then
			return
		end

		local delta =
			input.Position - dragStart

		camera = workspace.CurrentCamera

		local viewport =
			camera and camera.ViewportSize
			or Vector2.new(1920, 1080)

		local x =
			dragPosition.X.Offset + delta.X

		local y =
			dragPosition.Y.Offset + delta.Y

		x = math.clamp(
			x,
			0,
			math.max(
				0,
				viewport.X
					- UI.statusPanel.AbsoluteSize.X
			)
		)

		y = math.clamp(
			y,
			0,
			math.max(
				0,
				viewport.Y
					- UI.statusPanel.AbsoluteSize.Y
			)
		)

		UI.statusPanel.Position =
			UDim2.fromOffset(x, y)
	end)

	API.RefreshSettingsPanel()
end

--========================================================--
-- INPUT
--========================================================--

function API.HandleInputBegan(input, gameProcessed)
	-- Don't consume chat / Roblox UI input.
	if gameProcessed then
		return
	end

	if input.UserInputType
		== Enum.UserInputType.MouseButton1
	then
		State.leftMouseHeld = true
		return
	end

	if input.UserInputType
		== Enum.UserInputType.MouseButton2
	then
		State.rightMouseHeld = true

		if State.mode == 2
			and State.ronaldoAdvanceEnabled
			and API.LocalHasBall()
		then
			API.SelectRonaldoTarget()
		end

		return
	end

	if input.UserInputType
		~= Enum.UserInputType.Keyboard
	then
		return
	end

	if State.changingControlKey then
		if input.KeyCode
			== Enum.KeyCode.Escape
		then
			State.changingControlKey = false
			API.SetGeneralControls()
			API.UpdateUI(true)
			return
		end

		if input.KeyCode
			~= Enum.KeyCode.Unknown
		then
			State.controlKey = input.KeyCode
			State.changingControlKey = false

			API.SetGeneralControls()
			API.UpdateUI(true)

			API.Notify(
				"CONTROL KEY",
				"Set to "
					.. State.controlKey.Name,
				1.4
			)
		end

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

	if input.KeyCode
		~= State.controlKey
	then
		return
	end

	if State.saePassEnabled then
		API.SelectSaePassTarget()
		return
	end

	if State.mode == 2
		and State.ronaldoAdvanceEnabled
		and State.ronaldoAdvanceTargetPosition
	then
		API.StartRonaldoAdvance()
		return
	end

	local _, _, ball =
		API.GetBallState()

	if State.mode == 1 then
		State.enabled = not State.enabled

		if State.enabled then
			State.forceUnanchorActive = false

			if State.advanceMode then
				camera = workspace.CurrentCamera

				if camera then
					camera.CameraType =
						Enum.CameraType.Scriptable
				end
			elseif ball then
				API.CameraToBall(ball)
			end

			API.ApplyModeLock()

			API.Notify(
				"CONTROL",
				API.ModeName()
					.. " ACTIVE",
				1.1
			)
		else
			API.RestoreCamera()
			API.ApplyModeLock()

			API.Notify(
				"CONTROL",
				"OFF",
				1
			)
		end

		API.UpdateUI(true)
		return
	end

	if State.mode == 2 then
		if API.LocalHasBall() then
			API.PerformMode2Kick(ball)
		else
			API.Notify(
				"MODE 2",
				"Cần đang cầm bóng",
				1.2
			)
		end
	end
end

function API.HandleInputEnded(input)
	if input.UserInputType
		== Enum.UserInputType.MouseButton1
	then
		State.leftMouseHeld = false
		return
	end

	if input.UserInputType
		== Enum.UserInputType.MouseButton2
	then
		State.rightMouseHeld = false
		return
	end

	if input.UserInputType
		~= Enum.UserInputType.Keyboard
	then
		return
	end

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

--========================================================--
-- CLEANUP
--========================================================--

function API.ResetRuntimeState()
	State.enabled = false
	State.forceUnanchorActive = false

	State.stealBallEnabled = false

	State.autoGoalRunId += 1
	State.autoGoalExecuting = false

	State.tpActive = false
	State.tpReturnCFrame = nil
	State.tpGoalActive = false
	State.tpFollowTarget = nil
	State.tpFollowBall = nil

	State.gkSpecialEnabled = false
	State.gkLastGoalPart = nil

	State.advanceKeys = {
		W = false,
		A = false,
		S = false,
		D = false,
		Q = false,
		E = false,
	}

	API.ClearSaeTarget()
	API.StopRonaldoAdvance()
end

function API.StopController()
	-- Invalidate asynchronous tasks first.
	State.autoGoalRunId += 1
	State.autoGoalExecuting = false

	API.StopRonaldoAdvance()
	API.ClearSaeTarget()

	API.UnlockPlayer()
	API.RestoreCamera()

	State.enabled = false
	State.stealBallEnabled = false
	State.autoGoalEnabled = false
	State.tpActive = false

	for _, conn in ipairs(Connections) do
		API.Disconnect(conn)
	end

	table.clear(Connections)

	for plr, list in pairs(CharacterConnections) do
		API.DisconnectList(list)
		CharacterConnections[plr] = nil
	end

	for plr, list in pairs(PlayerConnections) do
		API.DisconnectList(list)
		PlayerConnections[plr] = nil
	end

	local gui = PlayerGui:FindFirstChild("BallController")

	if gui then
		gui:Destroy()
	end

	UI = {}
end

GlobalEnv.__BALL_CONTROLLER_V4_STOP =
	function()
		API.StopController()
	end

--========================================================--
-- INITIALIZE
--========================================================--

API.UpdateCharacter()

API.InitializeBallTracker()

API.BuildUI()
API.ConnectUI()

-- PLAYER TRACKING
API.Bind(Players.PlayerAdded, function(plr)
	API.AttachPlayerTracking(plr)
	API.QueueBallCacheRebuild()
end)

API.Bind(Players.PlayerRemoving, function(plr)
	if Tracker.Holder == plr then
		Tracker.State = "UNKNOWN"
		Tracker.Holder = nil
		Tracker.Ball = nil
	end

	API.DisconnectList(
		CharacterConnections[plr] or {}
	)

	CharacterConnections[plr] = nil

	API.DisconnectList(
		PlayerConnections[plr] or {}
	)

	PlayerConnections[plr] = nil

	API.QueueBallCacheRebuild()
end)

-- INPUT
API.Bind(
	UIS.InputBegan,
	function(input, gameProcessed)
		API.HandleInputBegan(
			input,
			gameProcessed
		)
	end
)

API.Bind(
	UIS.InputEnded,
	function(input)
		API.HandleInputEnded(input)
	end
)

-- CHARACTER
API.Bind(
	LP.CharacterAdded,
	function()
		task.wait(0.35)

		API.ResetRuntimeState()
		API.UpdateCharacter()

		Char.playerWasLocked = false
		Char.savedWalkSpeed = nil
		Char.savedJumpPower = nil
		Char.savedAutoRotate = nil

		UI.restoreButton.Visible = true

		API.QueueBallCacheRebuild()
		API.UpdateUI(true)
	end
)

-- CAMERA CHANGE
API.Bind(
	workspace:GetPropertyChangedSignal(
		"CurrentCamera"
	),
	function()
		camera = workspace.CurrentCamera

		task.defer(function()
			if UI.statusPanel then
				API.ClampGuiPosition(
					UI.statusPanel
				)
			end
		end)
	end
)

-- RENDER
API.Bind(
	RunService.RenderStepped,
	function()
		if State.saePassActive then
			API.UpdateSaePass()
		end
	end
)

-- HEARTBEAT
API.Bind(
	RunService.Heartbeat,
	function()
		API.UpdateCharacter()

		local state, holder, ball =
			API.GetBallState()

		API.RefreshBallStatusUI(
			state,
			holder
		)

		API.UpdateRonaldoAdvance()

		-- AUTO GOAL
		if State.autoGoalEnabled then
			if API.LocalHasBall() then
				API.PerformAutoGoalStep()
			else
				API.SpamStealStep(false)
			end

		-- MANUAL STEAL
		elseif State.stealBallEnabled then
			if State.autoStealOffOnGet
				and API.LocalHasBall()
			then
				State.stealBallEnabled = false

				API.UpdateUI(true)

				API.Notify(
					"STEAL BALL",
					"Tự động tắt — bạn đã có bóng",
					1.4
				)
			else
				API.SpamStealStep(false)
			end
		end

		-- TP
		if State.tpActive then
			if API.LocalHasBall() then
				API.RestoreTemporaryTP(
					"Đã nhặt được bóng → quay về"
				)
			else
				API.UpdateTPFollowTarget()

				if State.tpActive
					and os.clock()
						- State.tpStartedAt
						>= State.tpDuration
				then
					API.RestoreTemporaryTP(
						"TP timer expired"
					)
				end
			end
		end

		-- MODE 1
		if State.enabled
			and State.mode == 1
			and ball
		then
			if not API.UpdateAdvanceCamera(ball) then
				API.ControlMode1(ball)
			end
		end

		-- ANCHOR
		if State.mode == 1 then
			API.ApplyModeLock()
		elseif Char.rootPart
			and Char.rootPart.Anchored
		then
			Char.rootPart.Anchored = false
		end

		if UI.restoreButton then
			UI.restoreButton.Visible = true
		end
	end
)

-- FIRST UI STATE
API.RefreshSettingsPanel()
API.UpdateUI(true)
API.SetStatusMini(false)

if ShootRemote.ready then
	API.Notify(
		"SHOOT REMOTE",
		"ShootBall detected",
		1.5
	)
else
	API.Notify(
		"SHOOT REMOTE",
		"Events.ShootBall chưa tìm thấy",
		2
	)
end

if not VIM then
	API.Notify(
		"STEAL BALL",
		"VirtualInputManager không khả dụng — Auto Steal sẽ không gửi E",
		2
	)
end

API.Notify(
		"BALL CONTROLLER",
		"V4.2 loaded",
		1.5
)

print("[Ball Controller V4.2] loaded")
