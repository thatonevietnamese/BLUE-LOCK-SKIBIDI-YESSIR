--//========================================================--
--//                 BALL CONTROLLER
--//              LOCK SYSTEM FIXED VERSION
--//========================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--========================================================--
-- CONFIG
--========================================================--

local BALL_NAME = "Ball"

local DEFAULT_SPEED = 60
local DEFAULT_HOTKEY = Enum.KeyCode.F

local MIN_SPEED = 1
local MAX_SPEED = 1000

--========================================================--
-- STATE
--========================================================--

local enabled = false
local mode = 1

local speed = DEFAULT_SPEED
local hotkey = DEFAULT_HOTKEY

local autoLock = true
local manualLock = false

local changingHotkey = false
local minimized = false

local keys = {
	W = false,
	A = false,
	S = false,
	D = false,
	Q = false,
	E = false
}

--========================================================--
-- CHARACTER
--========================================================--

local character = nil
local humanoid = nil
local rootPart = nil

-- Trạng thái trước khi SCRIPT lock
local savedWalkSpeed = nil
local savedJumpPower = nil
local savedAutoRotate = nil

local playerIsLocked = false

--========================================================--
-- UPDATE CHARACTER
--========================================================--

local function updateCharacter()

	character = player.Character

	if not character then

		humanoid = nil
		rootPart = nil

		return false
	end

	humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)

	rootPart =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	return humanoid ~= nil
		and rootPart ~= nil
end

updateCharacter()

--========================================================--
-- SAVE ORIGINAL HUMANOID STATE
--========================================================--

local function savePlayerState()

	if not humanoid then
		return
	end

	-- Chỉ lưu một lần mỗi lần lock
	if savedWalkSpeed == nil then

		savedWalkSpeed =
			humanoid.WalkSpeed
	end

	if savedJumpPower == nil then

		savedJumpPower =
			humanoid.JumpPower
	end

	if savedAutoRotate == nil then

		savedAutoRotate =
			humanoid.AutoRotate
	end
end

--========================================================--
-- LOCK PLAYER
--========================================================--

local function lockPlayer()

	if not updateCharacter() then
		return
	end

	-- Lưu state thật trước khi thay đổi
	savePlayerState()

	--====================================================--
	-- KHÔNG CÒN:
	-- rootPart.Anchored = true
	--
	-- Vì Anchor là nguyên nhân gây lỗi lock vị trí.
	--====================================================--

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false

	playerIsLocked = true
end

--========================================================--
-- UNLOCK PLAYER
--========================================================--

local function unlockPlayer()

	if not updateCharacter() then

		playerIsLocked = false

		savedWalkSpeed = nil
		savedJumpPower = nil
		savedAutoRotate = nil

		return
	end

	-- Chỉ restore khi SCRIPT đã từng lock
	if playerIsLocked then

		if savedWalkSpeed ~= nil then

			humanoid.WalkSpeed =
				savedWalkSpeed

		end

		if savedJumpPower ~= nil then

			humanoid.JumpPower =
				savedJumpPower

		end

		if savedAutoRotate ~= nil then

			humanoid.AutoRotate =
				savedAutoRotate

		end

	end

	playerIsLocked = false

	savedWalkSpeed = nil
	savedJumpPower = nil
	savedAutoRotate = nil
end

--========================================================--
-- FORCE UNLOCK
--========================================================--

local function forceUnlock()

	if not updateCharacter() then

		playerIsLocked = false

		savedWalkSpeed = nil
		savedJumpPower = nil
		savedAutoRotate = nil

		return
	end

	-- Nếu script đang lock thì restore state gốc
	if playerIsLocked then

		if savedWalkSpeed ~= nil then

			humanoid.WalkSpeed =
				savedWalkSpeed

		end

		if savedJumpPower ~= nil then

			humanoid.JumpPower =
				savedJumpPower

		end

		if savedAutoRotate ~= nil then

			humanoid.AutoRotate =
				savedAutoRotate

		end

	else

		-- Script không lock thì KHÔNG tự ý
		-- reset WalkSpeed/JumpPower của game.
		-- Chỉ chắc chắn AutoRotate không bị script này giữ.
	end

	playerIsLocked = false

	savedWalkSpeed = nil
	savedJumpPower = nil
	savedAutoRotate = nil
end

--========================================================--
-- UPDATE LOCK
--========================================================--

local function updateLock()

	-- Auto Lock chỉ có tác dụng khi Control ON.
	local shouldLock =
		(enabled and autoLock)
		or manualLock

	if shouldLock then

		lockPlayer()

	else

		unlockPlayer()

	end
end

--========================================================--
-- FIND BALL
--========================================================--

local function findBall()

	-- Ball bên trong character
	if character then

		local ball =
			character:FindFirstChild(
				BALL_NAME,
				true
			)

		if
			ball
			and ball:IsA("BasePart")
		then

			return ball
		end
	end

	-- Model player trong Workspace
	local playerModel =
		workspace:FindFirstChild(
			player.Name
		)

	if playerModel then

		local ball =
			playerModel:FindFirstChild(
				BALL_NAME,
				true
			)

		if
			ball
			and ball:IsA("BasePart")
		then

			return ball
		end
	end

	-- Ball trực tiếp trong Workspace
	local ball =
		workspace:FindFirstChild(
			BALL_NAME
		)

	if
		ball
		and ball:IsA("BasePart")
	then

		return ball
	end

	-- Fallback
	for _, obj in ipairs(
		workspace:GetDescendants()
	) do

		if
			obj:IsA("BasePart")
			and obj.Name == BALL_NAME
		then

			return obj
		end
	end

	return nil
end

--========================================================--
-- CAMERA
--========================================================--

local camera =
	workspace.CurrentCamera

local savedCameraType = nil
local savedCameraSubject = nil

local function saveCamera()

	savedCameraType =
		camera.CameraType

	savedCameraSubject =
		camera.CameraSubject
end

local function cameraToBall(ball)

	if not ball then
		return
	end

	if savedCameraType == nil then

		saveCamera()
	end

	camera.CameraType =
		Enum.CameraType.Custom

	camera.CameraSubject =
		ball
end

local function restoreCamera()

	updateCharacter()

	local hum = humanoid

	camera.CameraType =
		savedCameraType
		or Enum.CameraType.Custom

	if hum then

		camera.CameraSubject =
			hum

	elseif savedCameraSubject then

		camera.CameraSubject =
			savedCameraSubject

	end

	savedCameraType = nil
	savedCameraSubject = nil
end

--========================================================--
-- GUI
--========================================================--

local gui =
	Instance.new("ScreenGui")

gui.Name =
	"BallController"

gui.ResetOnSpawn =
	false

gui.IgnoreGuiInset =
	true

gui.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling

gui.Parent =
	playerGui

--========================================================--
-- MAIN
--========================================================--

local main =
	Instance.new("Frame")

main.Name =
	"Main"

main.Size =
	UDim2.fromOffset(
		330,
		330
	)

main.Position =
	UDim2.new(
		0,
		25,
		0.5,
		-165
	)

main.BackgroundColor3 =
	Color3.fromRGB(
		24,
		24,
		29
	)

main.BorderSizePixel = 0
main.Parent = gui

local mainCorner =
	Instance.new("UICorner")

mainCorner.CornerRadius =
	UDim.new(
		0,
		12
	)

mainCorner.Parent =
	main

local mainStroke =
	Instance.new("UIStroke")

mainStroke.Color =
	Color3.fromRGB(
		60,
		60,
		70
	)

mainStroke.Thickness = 1
mainStroke.Transparency = 0.2

mainStroke.Parent =
	main

--========================================================--
-- TITLE
--========================================================--

local title =
	Instance.new("TextLabel")

title.Size =
	UDim2.new(
		1,
		-55,
		0,
		40
	)

title.Position =
	UDim2.fromOffset(
		10,
		5
	)

title.BackgroundTransparency = 1

title.Text =
	"⚽  BALL CONTROLLER"

title.TextColor3 =
	Color3.fromRGB(
		255,
		255,
		255
	)

title.TextSize = 18
title.Font =
	Enum.Font.GothamBold

title.TextXAlignment =
	Enum.TextXAlignment.Left

title.Parent =
	main

--========================================================--
-- MINIMIZE
--========================================================--

local minimizeButton =
	Instance.new("TextButton")

minimizeButton.Name =
	"Minimize"

minimizeButton.Size =
	UDim2.fromOffset(
		28,
		28
	)

minimizeButton.Position =
	UDim2.new(
		1,
		-38,
		0,
		10
	)

minimizeButton.BackgroundColor3 =
	Color3.fromRGB(
		43,
		43,
		51
	)

minimizeButton.BorderSizePixel = 0

minimizeButton.Text =
	"—"

minimizeButton.TextColor3 =
	Color3.fromRGB(
		235,
		235,
		240
	)

minimizeButton.TextSize = 18
minimizeButton.Font =
	Enum.Font.GothamBold

minimizeButton.Parent =
	main

local minimizeCorner =
	Instance.new("UICorner")

minimizeCorner.CornerRadius =
	UDim.new(
		0,
		7
	)

minimizeCorner.Parent =
	minimizeButton

--========================================================--
-- STATUS
--========================================================--

local status =
	Instance.new("TextLabel")

status.Size =
	UDim2.new(
		1,
		-20,
		0,
		22
	)

status.Position =
	UDim2.fromOffset(
		10,
		42
	)

status.BackgroundTransparency = 1

status.Text =
	"Status: OFF"

status.TextColor3 =
	Color3.fromRGB(
		255,
		100,
		100
	)

status.TextSize = 13
status.Font =
	Enum.Font.GothamMedium

status.TextXAlignment =
	Enum.TextXAlignment.Left

status.Parent =
	main

--========================================================--
-- BUTTON CREATOR
--========================================================--

local function makeButton(
	text,
	x,
	y,
	width,
	height
)

	local button =
		Instance.new("TextButton")

	button.Size =
		UDim2.fromOffset(
			width,
			height
		)

	button.Position =
		UDim2.fromOffset(
			x,
			y
		)

	button.BackgroundColor3 =
		Color3.fromRGB(
			43,
			43,
			51
		)

	button.BorderSizePixel = 0

	button.Text =
		text

	button.TextColor3 =
		Color3.fromRGB(
			235,
			235,
			240
		)

	button.TextSize = 12

	button.Font =
		Enum.Font.GothamMedium

	button.Parent =
		main

	local corner =
		Instance.new("UICorner")

	corner.CornerRadius =
		UDim.new(
			0,
			7
		)

	corner.Parent =
		button

	return button
end

--========================================================--
-- CONTROL
--========================================================--

local controlButton =
	makeButton(
		"CONTROL: OFF",
		10,
		72,
		150,
		36
	)

--========================================================--
-- HOTKEY
--========================================================--

local hotkeyButton =
	makeButton(
		"HOTKEY: F",
		170,
		72,
		150,
		36
	)

--========================================================--
-- MODE
--========================================================--

local modeButton =
	makeButton(
		"MODE: 1 [WASD]",
		10,
		116,
		150,
		36
	)

--========================================================--
-- AUTO LOCK
--========================================================--

local autoLockButton =
	makeButton(
		"AUTO LOCK: ON",
		170,
		116,
		150,
		36
	)

--========================================================--
-- LOCK NOW
--========================================================--

local lockButton =
	makeButton(
		"LOCK NOW: OFF",
		10,
		160,
		150,
		36
	)

--========================================================--
-- BALL STATUS
--========================================================--

local ballStatus =
	Instance.new("TextLabel")

ballStatus.Size =
	UDim2.fromOffset(
		150,
		36
	)

ballStatus.Position =
	UDim2.fromOffset(
		170,
		160
	)

ballStatus.BackgroundTransparency =
	1

ballStatus.Text =
	"BALL: SEARCHING..."

ballStatus.TextColor3 =
	Color3.fromRGB(
		160,
		160,
		170
	)

ballStatus.TextSize = 11
ballStatus.Font =
	Enum.Font.Gotham

ballStatus.TextXAlignment =
	Enum.TextXAlignment.Center

ballStatus.TextYAlignment =
	Enum.TextYAlignment.Center

ballStatus.Parent =
	main

--========================================================--
-- SPEED
--========================================================--

local speedLabel =
	Instance.new("TextLabel")

speedLabel.Size =
	UDim2.fromOffset(
		90,
		30
	)

speedLabel.Position =
	UDim2.fromOffset(
		10,
		208
	)

speedLabel.BackgroundTransparency =
	1

speedLabel.Text =
	"SPEED"

speedLabel.TextColor3 =
	Color3.fromRGB(
		210,
		210,
		220
	)

speedLabel.TextSize = 12

speedLabel.Font =
	Enum.Font.GothamMedium

speedLabel.TextXAlignment =
	Enum.TextXAlignment.Left

speedLabel.Parent =
	main

local speedBox =
	Instance.new("TextBox")

speedBox.Size =
	UDim2.fromOffset(
		220,
		32
	)

speedBox.Position =
	UDim2.fromOffset(
		100,
		207
	)

speedBox.BackgroundColor3 =
	Color3.fromRGB(
		40,
		40,
		47
	)

speedBox.BorderSizePixel = 0

speedBox.Text =
	tostring(
		DEFAULT_SPEED
	)

speedBox.PlaceholderText =
	"Speed"

speedBox.TextColor3 =
	Color3.fromRGB(
		255,
		255,
		255
	)

speedBox.PlaceholderColor3 =
	Color3.fromRGB(
		130,
		130,
		140
	)

speedBox.TextSize = 13

speedBox.Font =
	Enum.Font.GothamMedium

speedBox.ClearTextOnFocus =
	false

speedBox.Parent =
	main

local speedCorner =
	Instance.new("UICorner")

speedCorner.CornerRadius =
	UDim.new(
		0,
		7
	)

speedCorner.Parent =
	speedBox

--========================================================--
-- INFO
--========================================================--

local info =
	Instance.new("TextLabel")

info.Size =
	UDim2.new(
		1,
		-20,
		0,
		60
	)

info.Position =
	UDim2.fromOffset(
		10,
		255
	)

info.BackgroundTransparency =
	1

info.Text =
	"Mode 1: WASD + Q/E\n"
	.. "Mode 2: Camera direction only\n"
	.. "Hotkey toggles controller"

info.TextColor3 =
	Color3.fromRGB(
		145,
		145,
		155
	)

info.TextSize = 11

info.Font =
	Enum.Font.Gotham

info.TextWrapped =
	true

info.TextXAlignment =
	Enum.TextXAlignment.Left

info.TextYAlignment =
	Enum.TextYAlignment.Top

info.Parent =
	main

--========================================================--
-- RESTORE BUTTON
--========================================================--

local restoreButton =
	Instance.new("TextButton")

restoreButton.Name =
	"Restore"

restoreButton.Size =
	UDim2.fromOffset(
		48,
		48
	)

restoreButton.Position =
	main.Position

restoreButton.BackgroundColor3 =
	Color3.fromRGB(
		30,
		30,
		36
	)

restoreButton.BorderSizePixel =
	0

restoreButton.Text =
	"⚽"

restoreButton.TextColor3 =
	Color3.fromRGB(
		255,
		255,
		255
	)

restoreButton.TextSize =
	23

restoreButton.Font =
	Enum.Font.GothamBold

restoreButton.Visible =
	false

restoreButton.Parent =
	gui

local restoreCorner =
	Instance.new("UICorner")

restoreCorner.CornerRadius =
	UDim.new(
		1,
		0
	)

restoreCorner.Parent =
	restoreButton

local restoreStroke =
	Instance.new("UIStroke")

restoreStroke.Color =
	Color3.fromRGB(
		65,
		65,
		75
	)

restoreStroke.Thickness = 1

restoreStroke.Parent =
	restoreButton

--========================================================--
-- DRAG
--========================================================--

local function makeDraggable(
	object,
	handle
)

	local dragging = false
	local dragStart
	local startPosition

	handle.InputBegan:Connect(
		function(input)

			if
				input.UserInputType
				~=
				Enum.UserInputType.MouseButton1
			then

				return
			end

			dragging =
				true

			dragStart =
				input.Position

			startPosition =
				object.Position

			input.Changed:Connect(
				function()

					if
						input.UserInputState
						==
						Enum.UserInputState.End
					then

						dragging =
							false
					end

				end
			)
		end
	)

	UserInputService.InputChanged:Connect(
		function(input)

			if not dragging then
				return
			end

			if
				input.UserInputType
				~=
				Enum.UserInputType.MouseMovement
			then

				return
			end

			local delta =
				input.Position
				- dragStart

			object.Position =
				UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset
						+ delta.X,

					startPosition.Y.Scale,
					startPosition.Y.Offset
						+ delta.Y
				)
		end
	)
end

makeDraggable(
	main,
	title
)

makeDraggable(
	restoreButton,
	restoreButton
)

--========================================================--
-- MINIMIZE
--========================================================--

minimizeButton.MouseButton1Click:Connect(
	function()

		minimized =
			true

		restoreButton.Position =
			main.Position

		main.Visible =
			false

		restoreButton.Visible =
			true
	end
)

restoreButton.MouseButton1Click:Connect(
	function()

		minimized =
			false

		main.Position =
			restoreButton.Position

		restoreButton.Visible =
			false

		main.Visible =
			true
	end
)

--========================================================--
-- UI UPDATE
--========================================================--

local function updateUI()

	if enabled then

		controlButton.Text =
			"CONTROL: ON"

		controlButton.TextColor3 =
			Color3.fromRGB(
				100,
				255,
				130
			)

		status.Text =
			"Status: ON"

		status.TextColor3 =
			Color3.fromRGB(
				100,
				255,
				130
			)

	else

		controlButton.Text =
			"CONTROL: OFF"

		controlButton.TextColor3 =
			Color3.fromRGB(
				255,
				100,
				100
			)

		status.Text =
			"Status: OFF"

		status.TextColor3 =
			Color3.fromRGB(
				255,
				100,
				100
			)
	end

	if mode == 1 then

		modeButton.Text =
			"MODE: 1 [WASD]"

	else

		modeButton.Text =
			"MODE: 2 [CAMERA]"
	end

	if autoLock then

		autoLockButton.Text =
			"AUTO LOCK: ON"

		autoLockButton.TextColor3 =
			Color3.fromRGB(
				100,
				255,
				130
			)

	else

		autoLockButton.Text =
			"AUTO LOCK: OFF"

		autoLockButton.TextColor3 =
			Color3.fromRGB(
				255,
				100,
				100
			)
	end

	if manualLock then

		lockButton.Text =
			"LOCK NOW: ON"

		lockButton.TextColor3 =
			Color3.fromRGB(
				100,
				255,
				130
			)

	else

		lockButton.Text =
			"LOCK NOW: OFF"

		lockButton.TextColor3 =
			Color3.fromRGB(
				255,
				100,
				100
			)
	end

	if changingHotkey then

		hotkeyButton.Text =
			"PRESS A KEY..."

	else

		hotkeyButton.Text =
			"HOTKEY: "
			.. hotkey.Name
	end
end

updateUI()

--========================================================--
-- ENABLE / DISABLE
--========================================================--

local function setEnabled(state)

	enabled =
		state

	updateCharacter()

	if enabled then

		-- Lock nếu AutoLock hoặc ManualLock
		updateLock()

		if mode == 2 then

			local ball =
				findBall()

			if ball then
				cameraToBall(ball)
			end
		end

	else

		-- Reset input
		keys.W = false
		keys.A = false
		keys.S = false
		keys.D = false
		keys.Q = false
		keys.E = false

		-- Khi tắt control,
		-- Manual Lock cũng phải tắt
		manualLock =
			false

		-- Thả lock của script
		forceUnlock()

		-- Trả camera
		restoreCamera()

		-- Dừng horizontal velocity của bóng
		local ball =
			findBall()

		if ball then

			local velocity =
				ball.AssemblyLinearVelocity

			ball.AssemblyLinearVelocity =
				Vector3.new(
					0,
					velocity.Y,
					0
				)
		end
	end

	updateUI()
end

--========================================================--
-- CONTROL BUTTON
--========================================================--

controlButton.MouseButton1Click:Connect(
	function()

		setEnabled(
			not enabled
		)
	end
)

--========================================================--
-- MODE
--========================================================--

modeButton.MouseButton1Click:Connect(
	function()

		mode += 1

		if mode > 2 then
			mode = 1
		end

		if enabled then

			if mode == 2 then

				local ball =
					findBall()

				if ball then
					cameraToBall(ball)
				end

			else

				restoreCamera()
			end
		end

		updateUI()
	end
)

--========================================================--
-- AUTO LOCK
--========================================================--

autoLockButton.MouseButton1Click:Connect(
	function()

		autoLock =
			not autoLock

		if autoLock then

			-- Bật AutoLock
			if enabled then
				lockPlayer()
			end

		else

			-- Tắt AutoLock
			-- Nếu ManualLock không bật
			-- thì thả ngay
			if not manualLock then
				forceUnlock()
			end
		end

		updateUI()
	end
)

--========================================================--
-- LOCK NOW
--========================================================--

lockButton.MouseButton1Click:Connect(
	function()

		manualLock =
			not manualLock

		if manualLock then

			lockPlayer()

		else

			-- AutoLock đang ON + Control ON
			-- thì vẫn phải lock
			if enabled and autoLock then

				lockPlayer()

			else

				forceUnlock()

			end
		end

		updateUI()
	end
)

--========================================================--
-- SPEED
--========================================================--

speedBox.FocusLost:Connect(
	function()

		local value =
			tonumber(
				speedBox.Text
			)

		if not value then

			speedBox.Text =
				tostring(speed)

			return
		end

		value =
			math.clamp(
				value,
				MIN_SPEED,
				MAX_SPEED
			)

		speed =
			value

		speedBox.Text =
			tostring(value)
	end
)

--========================================================--
-- HOTKEY
--========================================================--

hotkeyButton.MouseButton1Click:Connect(
	function()

		changingHotkey =
			true

		updateUI()
	end
)

--========================================================--
-- INPUT BEGAN
--========================================================--

UserInputService.InputBegan:Connect(
	function(
		input,
		gameProcessed
	)

		if
			input.UserInputType
			~=
			Enum.UserInputType.Keyboard
		then

			return
		end

		--====================================--
		-- ĐỔI HOTKEY
		--====================================--

		if changingHotkey then

			if
				input.KeyCode
				==
				Enum.KeyCode.Escape
			then

				changingHotkey =
					false

				updateUI()

				return
			end

			if
				input.KeyCode
				~=
				Enum.KeyCode.Unknown
			then

				hotkey =
					input.KeyCode

				changingHotkey =
					false

				updateUI()

				return
			end
		end

		--====================================--
		-- CONTROLLER HOTKEY
		--====================================--

		if
			input.KeyCode
			==
			hotkey
		then

			setEnabled(
				not enabled
			)

			return
		end

		if gameProcessed then
			return
		end

		--====================================--
		-- MOVEMENT KEYS
		--====================================--

		if
			input.KeyCode
			==
			Enum.KeyCode.W
		then

			keys.W = true

		elseif
			input.KeyCode
			==
			Enum.KeyCode.A
		then

			keys.A = true

		elseif
			input.KeyCode
			==
			Enum.KeyCode.S
		then

			keys.S = true

		elseif
			input.KeyCode
			==
			Enum.KeyCode.D
		then

			keys.D = true

		elseif
			input.KeyCode
			==
			Enum.KeyCode.Q
		then

			keys.Q = true

		elseif
			input.KeyCode
			==
			Enum.KeyCode.E
		then

			keys.E = true
		end
	end
)

--========================================================--
-- INPUT ENDED
--========================================================--

UserInputService.InputEnded:Connect(
	function(input)

		if
			input.UserInputType
			~=
			Enum.UserInputType.Keyboard
		then

			return
		end

		if
			input.KeyCode
			==
			Enum.KeyCode.W
		then

			keys.W = false

		elseif
			input.KeyCode
			==
			Enum.KeyCode.A
		then

			keys.A = false

		elseif
			input.KeyCode
			==
			Enum.KeyCode.S
		then

			keys.S = false

		elseif
			input.KeyCode
			==
			Enum.KeyCode.D
		then

			keys.D = false

		elseif
			input.KeyCode
			==
			Enum.KeyCode.Q
		then

			keys.Q = false

		elseif
			input.KeyCode
			==
			Enum.KeyCode.E
		then

			keys.E = false
		end
	end
)

--========================================================--
-- CAMERA DIRECTIONS
--========================================================--

local function getFlatDirections()

	local cf =
		camera.CFrame

	local forward =
		Vector3.new(
			cf.LookVector.X,
			0,
			cf.LookVector.Z
		)

	local right =
		Vector3.new(
			cf.RightVector.X,
			0,
			cf.RightVector.Z
		)

	if forward.Magnitude > 0 then

		forward =
			forward.Unit
	end

	if right.Magnitude > 0 then

		right =
			right.Unit
	end

	return forward, right
end

--========================================================--
-- MODE 1
--========================================================--

local function controlMode1(ball)

	local forward, right =
		getFlatDirections()

	local direction =
		Vector3.zero

	if keys.W then
		direction += forward
	end

	if keys.S then
		direction -= forward
	end

	if keys.D then
		direction += right
	end

	if keys.A then
		direction -= right
	end

	local velocity =
		ball.AssemblyLinearVelocity

	local horizontal =
		Vector3.zero

	if direction.Magnitude > 0 then

		horizontal =
			direction.Unit
			* speed
	end

	local vertical =
		velocity.Y

	if keys.E then

		vertical =
			speed

	elseif keys.Q then

		vertical =
			-speed

	end

	ball.AssemblyLinearVelocity =
		Vector3.new(
			horizontal.X,
			vertical,
			horizontal.Z
		)
end

--========================================================--
-- MODE 2
--========================================================--

local function controlMode2(ball)

	if
		camera.CameraSubject
		~= ball
	then

		cameraToBall(ball)
	end

	local direction =
		camera.CFrame.LookVector

	if direction.Magnitude > 0 then

		direction =
			direction.Unit
	end

	ball.AssemblyLinearVelocity =
		direction
		* speed
end

--========================================================--
-- BALL LOOP
--========================================================--

RunService.Heartbeat:Connect(
	function()

		local ball =
			findBall()

		if ball then

			ballStatus.Text =
				"BALL: FOUND"

			ballStatus.TextColor3 =
				Color3.fromRGB(
					100,
					255,
					130
				)

		else

			ballStatus.Text =
				"BALL: NOT FOUND"

			ballStatus.TextColor3 =
				Color3.fromRGB(
					255,
					100,
					100
				)
		end

		if not enabled then
			return
		end

		if not ball then
			return
		end

		if mode == 1 then

			controlMode1(
				ball
			)

		elseif mode == 2 then

			controlMode2(
				ball
			)
		end
	end
)

--========================================================--
-- CHARACTER RESPAWN
--========================================================--

player.CharacterAdded:Connect(
	function()

		task.wait(0.5)

		-- Character mới
		updateCharacter()

		-- Không mang state lock cũ sang character mới
		playerIsLocked = false

		savedWalkSpeed = nil
		savedJumpPower = nil
		savedAutoRotate = nil

		if enabled then

			if autoLock
				or manualLock
			then

				lockPlayer()

			else

				forceUnlock()

			end

			if mode == 2 then

				local ball =
					findBall()

				if ball then
					cameraToBall(ball)
				end
			end

		else

			forceUnlock()

		end

		updateUI()
	end
)

--========================================================--
-- CHARACTER REFERENCE SAFETY
--========================================================--

RunService.Heartbeat:Connect(
	function()

		if
			character
			~= player.Character
		then

			updateCharacter()

			-- Nếu character đổi mà
			-- script đang không lock,
			-- đảm bảo không mang reference cũ
			if not enabled then

				playerIsLocked =
					false

				savedWalkSpeed =
					nil

				savedJumpPower =
					nil

				savedAutoRotate =
					nil
			end
		end
	end
)

--========================================================--
-- INITIALIZE
--========================================================--

updateCharacter()
updateUI()

print(
	"[Ball Controller] Lock system rebuilt - no Anchored lock."
)
