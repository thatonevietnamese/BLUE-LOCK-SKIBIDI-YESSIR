-- ==========================================
-- BALL TRACKER + TP SYSTEM
-- V7
-- CONTROL / SETTINGS
-- ==========================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- VIRTUAL INPUT
-- ==========================================

local VirtualInputManager = nil

pcall(function()
	VirtualInputManager = game:GetService("VirtualInputManager")
end)

-- ==========================================
-- CONFIG
-- ==========================================

local scanFrequency = 0.5

-- TP TO BALL dùng thời gian này
local ballTPTime = 3

-- TP TO HOLDER dùng thời gian này
local holderTPTime = 3

-- ==========================================
-- KEY CONFIG
-- ==========================================

local preKeys = {
	Q = {
		keyCode = Enum.KeyCode.Q,
		enabled = false,
		target = true,
		hotkey = Enum.KeyCode.Q,
		waitingHotkey = false
	},

	E = {
		keyCode = Enum.KeyCode.E,
		enabled = false,
		target = true,
		hotkey = Enum.KeyCode.E,
		waitingHotkey = false
	},

	One = {
		keyCode = Enum.KeyCode.One,
		enabled = false,
		target = true,
		hotkey = Enum.KeyCode.One,
		waitingHotkey = false
	},

	Two = {
		keyCode = Enum.KeyCode.Two,
		enabled = false,
		target = true,
		hotkey = Enum.KeyCode.Two,
		waitingHotkey = false
	},

	Three = {
		keyCode = Enum.KeyCode.Three,
		enabled = false,
		target = true,
		hotkey = Enum.KeyCode.Three,
		waitingHotkey = false
	},

	Four = {
		keyCode = Enum.KeyCode.Four,
		enabled = false,
		target = true,
		hotkey = Enum.KeyCode.Four,
		waitingHotkey = false
	},

	Five = {
		keyCode = Enum.KeyCode.Five,
		enabled = false,
		target = true,
		hotkey = Enum.KeyCode.Five,
		waitingHotkey = false
	},

	Six = {
		keyCode = Enum.KeyCode.Six,
		enabled = false,
		target = true,
		hotkey = Enum.KeyCode.Six,
		waitingHotkey = false
	}
}

local keyOrder = {
	"Q",
	"E",
	"One",
	"Two",
	"Three",
	"Four",
	"Five",
	"Six"
}

local keyDisplay = {
	Q = "Q",
	E = "E",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6"
}

-- ==========================================
-- TP BUTTON HOTKEYS
-- ==========================================

local tpHotkeys = {
	Ball = {
		key = Enum.KeyCode.F,
		waiting = false
	},

	Holder = {
		key = Enum.KeyCode.G,
		waiting = false
	},

	Continuous = {
		key = Enum.KeyCode.H,
		waiting = false
	}
}

-- ==========================================
-- TP STATE
-- ==========================================

local continuousRunning = false
local cancelRequested = false

local currentStatus = nil
local currentHolder = nil
local currentSameTeam = nil

-- ==========================================
-- GUI
-- ==========================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BallTrackerUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

ScreenGui.Parent =
	RunService:IsStudio()
	and LocalPlayer:WaitForChild("PlayerGui")
	or CoreGui

-- ==========================================
-- MAIN FRAME
-- ==========================================

local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui

MainFrame.Size = UDim2.fromOffset(440, 430)
MainFrame.Position = UDim2.new(0.5, -220, 0, 20)

MainFrame.BackgroundColor3 =
	Color3.fromRGB(28, 28, 33)

MainFrame.BorderSizePixel = 1
MainFrame.BorderColor3 =
	Color3.fromRGB(0, 170, 255)

MainFrame.Active = true
MainFrame.Draggable = true

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

-- ==========================================
-- TITLE
-- ==========================================

local Title = Instance.new("TextLabel")
Title.Parent = MainFrame

Title.Size = UDim2.new(1, -70, 0, 30)
Title.Position = UDim2.fromOffset(10, 3)

Title.BackgroundTransparency = 1
Title.Text = "⚽ Ball Tracker + TP"

Title.TextColor3 =
	Color3.fromRGB(255, 255, 255)

Title.Font = Enum.Font.GothamBold
Title.TextSize = 16

Title.TextXAlignment =
	Enum.TextXAlignment.Left

-- ==========================================
-- HIDE
-- ==========================================

local HideButton = Instance.new("TextButton")
HideButton.Parent = MainFrame

HideButton.Size = UDim2.fromOffset(28, 25)
HideButton.Position = UDim2.new(1, -35, 0, 5)

HideButton.BackgroundColor3 =
	Color3.fromRGB(55, 55, 60)

HideButton.BorderSizePixel = 0

HideButton.Text = "×"
HideButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

HideButton.Font = Enum.Font.GothamBold
HideButton.TextSize = 17

local HideCorner = Instance.new("UICorner")
HideCorner.CornerRadius = UDim.new(0, 6)
HideCorner.Parent = HideButton

-- ==========================================
-- SHOW BUTTON
-- ==========================================

local ShowButton = Instance.new("TextButton")
ShowButton.Parent = ScreenGui

ShowButton.Size = UDim2.fromOffset(48, 48)
ShowButton.Position = MainFrame.Position

ShowButton.BackgroundColor3 =
	Color3.fromRGB(28, 28, 33)

ShowButton.BorderSizePixel = 1
ShowButton.BorderColor3 =
	Color3.fromRGB(0, 170, 255)

ShowButton.Text = "⚽"
ShowButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

ShowButton.Font = Enum.Font.GothamBold
ShowButton.TextSize = 22

ShowButton.Visible = false

local ShowCorner = Instance.new("UICorner")
ShowCorner.CornerRadius = UDim.new(1, 0)
ShowCorner.Parent = ShowButton

-- ==========================================
-- TAB BUTTONS
-- ==========================================

local ControlTab = Instance.new("TextButton")
ControlTab.Parent = MainFrame

ControlTab.Size = UDim2.fromOffset(200, 30)
ControlTab.Position = UDim2.fromOffset(10, 38)

ControlTab.BackgroundColor3 =
	Color3.fromRGB(0, 130, 210)

ControlTab.BorderSizePixel = 0

ControlTab.Text = "CONTROL"

ControlTab.TextColor3 =
	Color3.fromRGB(255, 255, 255)

ControlTab.Font = Enum.Font.GothamBold
ControlTab.TextSize = 12

local SettingsTab = Instance.new("TextButton")
SettingsTab.Parent = MainFrame

SettingsTab.Size = UDim2.fromOffset(200, 30)
SettingsTab.Position = UDim2.fromOffset(220, 38)

SettingsTab.BackgroundColor3 =
	Color3.fromRGB(55, 55, 60)

SettingsTab.BorderSizePixel = 0

SettingsTab.Text = "SETTINGS"

SettingsTab.TextColor3 =
	Color3.fromRGB(255, 255, 255)

SettingsTab.Font = Enum.Font.GothamBold
SettingsTab.TextSize = 12

-- ==========================================
-- CONTROL PAGE
-- ==========================================

local ControlPage = Instance.new("Frame")
ControlPage.Parent = MainFrame

ControlPage.Size =
	UDim2.new(1, -20, 1, -80)

ControlPage.Position =
	UDim2.fromOffset(10, 75)

ControlPage.BackgroundTransparency = 1

-- ==========================================
-- STATUS
-- ==========================================

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Parent = ControlPage

StatusLabel.Size =
	UDim2.new(1, 0, 0, 30)

StatusLabel.BackgroundColor3 =
	Color3.fromRGB(20, 20, 24)

StatusLabel.Text =
	"Status: FALSE"

StatusLabel.TextColor3 =
	Color3.fromRGB(255, 80, 80)

StatusLabel.Font =
	Enum.Font.GothamBold

StatusLabel.TextSize = 15

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 6)
StatusCorner.Parent = StatusLabel

-- ==========================================
-- HOLDER
-- ==========================================

local HolderLabel = Instance.new("TextLabel")
HolderLabel.Parent = ControlPage

HolderLabel.Size =
	UDim2.new(1, 0, 0, 28)

HolderLabel.Position =
	UDim2.fromOffset(0, 35)

HolderLabel.BackgroundColor3 =
	Color3.fromRGB(20, 20, 24)

HolderLabel.Text =
	"Holder: -"

HolderLabel.TextColor3 =
	Color3.fromRGB(255, 255, 255)

HolderLabel.Font =
	Enum.Font.GothamBold

HolderLabel.TextSize = 12
HolderLabel.TextXAlignment =
	Enum.TextXAlignment.Left

local HolderCorner = Instance.new("UICorner")
HolderCorner.CornerRadius = UDim.new(0, 6)
HolderCorner.Parent = HolderLabel

-- ==========================================
-- BUTTON CREATOR
-- ==========================================

local function MakeButton(
	parent,
	text,
	x,
	y,
	width,
	height,
	color
)

	local button = Instance.new("TextButton")
	button.Parent = parent

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

	button.BackgroundColor3 = color
	button.BorderSizePixel = 0

	button.Text = text
	button.TextColor3 =
		Color3.fromRGB(
			255,
			255,
			255
		)

	button.Font =
		Enum.Font.GothamBold

	button.TextSize = 10

	local corner =
		Instance.new("UICorner")

	corner.CornerRadius =
		UDim.new(0, 6)

	corner.Parent =
		button

	return button
end

-- ==========================================
-- TP BUTTONS
-- ==========================================

local TPBallButton =
	MakeButton(
		ControlPage,
		"TP BALL [F]",
		0,
		70,
		125,
		32,
		Color3.fromRGB(
			40,
			125,
			220
		)
	)

local TPHolderButton =
	MakeButton(
		ControlPage,
		"TP HOLDER [G]",
		132,
		70,
		125,
		32,
		Color3.fromRGB(
			65,
			160,
			85
		)
	)

local ContinuousButton =
	MakeButton(
		ControlPage,
		"CONTINUOUS [H]",
		264,
		70,
		125,
		32,
		Color3.fromRGB(
			175,
			110,
			35
		)
	)

local CancelButton =
	MakeButton(
		ControlPage,
		"CANCEL TP",
		0,
		106,
		125,
		32,
		Color3.fromRGB(
			175,
			55,
			55
		)
	)

-- ==========================================
-- TP HOTKEY SETTINGS
-- ==========================================

local TPHotkeyTitle = Instance.new("TextLabel")
TPHotkeyTitle.Parent = ControlPage

TPHotkeyTitle.Size =
	UDim2.new(0, 250, 0, 22)

TPHotkeyTitle.Position =
	UDim2.fromOffset(135, 106)

TPHotkeyTitle.BackgroundTransparency = 1

TPHotkeyTitle.Text =
	"Click hotkey button to change"

TPHotkeyTitle.TextColor3 =
	Color3.fromRGB(
		150,
		150,
		160
	)

TPHotkeyTitle.Font =
	Enum.Font.Gotham

TPHotkeyTitle.TextSize = 10

TPHotkeyTitle.TextXAlignment =
	Enum.TextXAlignment.Left

-- ==========================================
-- PRE-KEY TITLE
-- ==========================================

local PreKeyTitle = Instance.new("TextLabel")
PreKeyTitle.Parent = ControlPage

PreKeyTitle.Size =
	UDim2.new(1, 0, 0, 22)

PreKeyTitle.Position =
	UDim2.fromOffset(0, 145)

PreKeyTitle.BackgroundTransparency = 1

PreKeyTitle.Text =
	"KEY     ENABLE       TARGET       HOTKEY"

PreKeyTitle.TextColor3 =
	Color3.fromRGB(
		0,
		200,
		255
	)

PreKeyTitle.Font =
	Enum.Font.GothamBold

PreKeyTitle.TextSize = 11

PreKeyTitle.TextXAlignment =
	Enum.TextXAlignment.Left

-- ==========================================
-- PRE-KEY ROWS
-- ==========================================

local keyRows = {}

for index, keyName in ipairs(keyOrder) do

	local data =
		preKeys[keyName]

	local display =
		keyDisplay[keyName]

	local row =
		Instance.new("Frame")

	row.Parent =
		ControlPage

	row.Size =
		UDim2.new(
			1,
			0,
			0,
			27
		)

	row.Position =
		UDim2.fromOffset(
			0,
			168 + (index - 1) * 30
		)

	row.BackgroundTransparency = 1

	-- KEY LABEL
	local keyLabel =
		Instance.new("TextLabel")

	keyLabel.Parent = row

	keyLabel.Size =
		UDim2.fromOffset(
			45,
			27
		)

	keyLabel.BackgroundColor3 =
		Color3.fromRGB(
			45,
			45,
			50
		)

	keyLabel.Text =
		display

	keyLabel.TextColor3 =
		Color3.fromRGB(
			255,
			255,
			255
		)

	keyLabel.Font =
		Enum.Font.GothamBold

	keyLabel.TextSize = 12

	local kc =
		Instance.new("UICorner")

	kc.CornerRadius =
		UDim.new(0, 5)

	kc.Parent =
		keyLabel

	-- ENABLE
	local enable =
		Instance.new("TextButton")

	enable.Parent = row

	enable.Size =
		UDim2.fromOffset(
			85,
			27
		)

	enable.Position =
		UDim2.fromOffset(
			50,
			0
		)

	enable.Font =
		Enum.Font.GothamBold

	enable.TextSize = 10

	enable.TextColor3 =
		Color3.fromRGB(
			255,
			255,
			255
		)

	local ec =
		Instance.new("UICorner")

	ec.CornerRadius =
		UDim.new(0, 5)

	ec.Parent =
		enable

	-- TARGET
	local target =
		Instance.new("TextButton")

	target.Parent = row

	target.Size =
		UDim2.fromOffset(
			80,
			27
		)

	target.Position =
		UDim2.fromOffset(
			140,
			0
		)

	target.Font =
		Enum.Font.GothamBold

	target.TextSize = 10

	target.TextColor3 =
		Color3.fromRGB(
			255,
			255,
			255
		)

	local tc =
		Instance.new("UICorner")

	tc.CornerRadius =
		UDim.new(0, 5)

	tc.Parent =
		target

	-- HOTKEY
	local hotkey =
		Instance.new("TextButton")

	hotkey.Parent = row

	hotkey.Size =
		UDim2.fromOffset(
			120,
			27
		)

	hotkey.Position =
		UDim2.fromOffset(
			225,
			0
		)

	hotkey.Font =
		Enum.Font.GothamBold

	hotkey.TextSize = 10

	hotkey.TextColor3 =
		Color3.fromRGB(
			255,
			255,
			255
		)

	local hc =
		Instance.new("UICorner")

	hc.CornerRadius =
		UDim.new(0, 5)

	hc.Parent =
		hotkey

	keyRows[keyName] = {
		enable = enable,
		target = target,
		hotkey = hotkey
	}
end

-- ==========================================
-- UPDATE PREKEY UI
-- ==========================================

local function UpdateKeyUI(keyName)

	local data =
		preKeys[keyName]

	local row =
		keyRows[keyName]

	if not row then
		return
	end

	-- ENABLE
	if data.enabled then

		row.enable.Text =
			"ON"

		row.enable.BackgroundColor3 =
			Color3.fromRGB(
				50,
				165,
				80
			)

	else

		row.enable.Text =
			"OFF"

		row.enable.BackgroundColor3 =
			Color3.fromRGB(
				70,
				70,
				75
			)

	end

	-- TARGET
	if data.target then

		row.target.Text =
			"TRUE / TEAM"

		row.target.BackgroundColor3 =
			Color3.fromRGB(
				50,
				130,
				200
			)

	else

		row.target.Text =
			"FALSE / OPP"

		row.target.BackgroundColor3 =
			Color3.fromRGB(
				170,
				65,
				60
			)

	end

	-- HOTKEY
	if data.waitingHotkey then

		row.hotkey.Text =
			"PRESS KEY..."

		row.hotkey.BackgroundColor3 =
			Color3.fromRGB(
				180,
				130,
				40
			)

	else

		row.hotkey.Text =
			"HOTKEY: "
			.. data.hotkey.Name

		row.hotkey.BackgroundColor3 =
			Color3.fromRGB(
				55,
				55,
				60
			)

	end
end

for _, keyName in ipairs(keyOrder) do

	UpdateKeyUI(keyName)

	local row =
		keyRows[keyName]

	row.enable.MouseButton1Click:Connect(
		function()

			preKeys[keyName].enabled =
				not preKeys[keyName].enabled

			UpdateKeyUI(keyName)

		end
	)

	row.target.MouseButton1Click:Connect(
		function()

			preKeys[keyName].target =
				not preKeys[keyName].target

			UpdateKeyUI(keyName)

		end
	)

	row.hotkey.MouseButton1Click:Connect(
		function()

			preKeys[keyName].waitingHotkey =
				true

			UpdateKeyUI(keyName)

		end
	)
end

-- ==========================================
-- SETTINGS PAGE
-- ==========================================

local SettingsPage = Instance.new("Frame")
SettingsPage.Parent = MainFrame

SettingsPage.Size =
	UDim2.new(1, -20, 1, -80)

SettingsPage.Position =
	UDim2.fromOffset(10, 75)

SettingsPage.BackgroundTransparency = 1
SettingsPage.Visible = false

-- ==========================================
-- SETTING CREATOR
-- ==========================================

local function MakeSetting(
	text,
	value,
	y
)

	local label =
		Instance.new("TextLabel")

	label.Parent =
		SettingsPage

	label.Size =
		UDim2.fromOffset(
			170,
			34
		)

	label.Position =
		UDim2.fromOffset(
			0,
			y
		)

	label.BackgroundTransparency = 1

	label.Text =
		text

	label.TextColor3 =
		Color3.fromRGB(
			220,
			220,
			225
		)

	label.Font =
		Enum.Font.GothamBold

	label.TextSize = 11

	label.TextXAlignment =
		Enum.TextXAlignment.Left

	local box =
		Instance.new("TextBox")

	box.Parent =
		SettingsPage

	box.Size =
		UDim2.fromOffset(
			220,
			34
		)

	box.Position =
		UDim2.fromOffset(
			175,
			y
		)

	box.BackgroundColor3 =
		Color3.fromRGB(
			45,
			45,
			50
		)

	box.BorderSizePixel = 0

	box.Text =
		tostring(value)

	box.TextColor3 =
		Color3.fromRGB(
			255,
			255,
			255
		)

	box.Font =
		Enum.Font.Gotham

	box.TextSize = 13

	box.ClearTextOnFocus = false

	local corner =
		Instance.new("UICorner")

	corner.CornerRadius =
		UDim.new(0, 6)

	corner.Parent =
		box

	return box
end

local ScanBox =
	MakeSetting(
		"SCAN FREQUENCY",
		scanFrequency,
		10
	)

local BallTimeBox =
	MakeSetting(
		"BALL TP TIME",
		ballTPTime,
		55
	)

local HolderTimeBox =
	MakeSetting(
		"HOLDER TP TIME",
		holderTPTime,
		100
	)

local SettingsInfo =
	Instance.new("TextLabel")

SettingsInfo.Parent =
	SettingsPage

SettingsInfo.Size =
	UDim2.new(
		1,
		0,
		0,
		120
	)

SettingsInfo.Position =
	UDim2.fromOffset(
		0,
		155
	)

SettingsInfo.BackgroundColor3 =
	Color3.fromRGB(
		20,
		20,
		24
	)

SettingsInfo.Text =
	"BALL TP TIME\n" ..
	"→ thời gian TP liên tục khi dùng TP TO BALL.\n\n" ..
	"HOLDER TP TIME\n" ..
	"→ thời gian TP liên tục khi dùng TP TO HOLDER.\n\n" ..
	"CONTINUOUS dùng cả hai mốc trên cho từng phase."

SettingsInfo.TextColor3 =
	Color3.fromRGB(
		170,
		170,
		180
	)

SettingsInfo.Font =
	Enum.Font.Gotham

SettingsInfo.TextSize = 11
SettingsInfo.TextWrapped = true

SettingsInfo.TextXAlignment =
	Enum.TextXAlignment.Left

SettingsInfo.TextYAlignment =
	Enum.TextYAlignment.Top

local sic =
	Instance.new("UICorner")

sic.CornerRadius =
	UDim.new(0, 6)

sic.Parent =
	SettingsInfo

-- ==========================================
-- SETTING EVENTS
-- ==========================================

ScanBox.FocusLost:Connect(function()

	local value =
		tonumber(ScanBox.Text)

	if value and value >= 0.01 then

		scanFrequency = value
		ScanBox.Text =
			tostring(value)

	else

		ScanBox.Text =
			tostring(scanFrequency)

	end
end)

BallTimeBox.FocusLost:Connect(function()

	local value =
		tonumber(BallTimeBox.Text)

	if value and value >= 0 then

		ballTPTime = value
		BallTimeBox.Text =
			tostring(value)

	else

		BallTimeBox.Text =
			tostring(ballTPTime)

	end
end)

HolderTimeBox.FocusLost:Connect(function()

	local value =
		tonumber(HolderTimeBox.Text)

	if value and value >= 0 then

		holderTPTime = value
		HolderTimeBox.Text =
			tostring(value)

	else

		HolderTimeBox.Text =
			tostring(holderTPTime)

	end
end)

-- ==========================================
-- TP HOTKEY BUTTON CREATOR
-- ==========================================

local function RefreshTPButtonText()

	if tpHotkeys.Ball.waiting then

		TPBallButton.Text =
			"TP BALL [PRESS KEY]"

	else

		TPBallButton.Text =
			"TP BALL ["
			.. tpHotkeys.Ball.key.Name
			.. "]"

	end

	if tpHotkeys.Holder.waiting then

		TPHolderButton.Text =
			"TP HOLDER [PRESS KEY]"

	else

		TPHolderButton.Text =
			"TP HOLDER ["
			.. tpHotkeys.Holder.key.Name
			.. "]"

	end

	if tpHotkeys.Continuous.waiting then

		ContinuousButton.Text =
			"CONTINUOUS [PRESS]"

	else

		ContinuousButton.Text =
			"CONTINUOUS ["
			.. tpHotkeys.Continuous.key.Name
			.. "]"

	end
end

RefreshTPButtonText()

-- Double click style:
-- right mouse changes hotkey
TPBallButton.MouseButton2Click:Connect(
	function()

		tpHotkeys.Ball.waiting = true
		RefreshTPButtonText()

	end
)

TPHolderButton.MouseButton2Click:Connect(
	function()

		tpHotkeys.Holder.waiting = true
		RefreshTPButtonText()

	end
)

ContinuousButton.MouseButton2Click:Connect(
	function()

		tpHotkeys.Continuous.waiting = true
		RefreshTPButtonText()

	end
)

-- ==========================================
-- TAB SWITCH
-- ==========================================

ControlTab.MouseButton1Click:Connect(
	function()

		ControlPage.Visible = true
		SettingsPage.Visible = false

		ControlTab.BackgroundColor3 =
			Color3.fromRGB(
				0,
				130,
				210
			)

		SettingsTab.BackgroundColor3 =
			Color3.fromRGB(
				55,
				55,
				60
			)

	end
)

SettingsTab.MouseButton1Click:Connect(
	function()

		ControlPage.Visible = false
		SettingsPage.Visible = true

		ControlTab.BackgroundColor3 =
			Color3.fromRGB(
				55,
				55,
				60
			)

		SettingsTab.BackgroundColor3 =
			Color3.fromRGB(
				0,
				130,
				210
			)

	end
)

-- ==========================================
-- FIND BALL
-- ==========================================

local function FindBall()

	local ball =
		workspace:FindFirstChild(
			"Ball"
		)

	if ball then

		if ball:IsA("BasePart") then
			return ball
		end

		local part =
			ball:FindFirstChildWhichIsA(
				"BasePart",
				true
			)

		if part then
			return part
		end
	end

	for _, object in ipairs(
		workspace:GetDescendants()
	) do

		if
			object:IsA("BasePart")
			and string.lower(
				object.Name
			) == "ball"
			and object.Material ==
				Enum.Material.Plastic
		then

			return object

		end
	end

	return nil
end

-- ==========================================
-- FIND HOLDER
-- ==========================================

local function FindBallHolder()

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		if
			player.Team
			and (
				string.match(
					string.lower(
						player.Team.Name
					),
					"home"
				)
				or

				string.match(
					string.lower(
						player.Team.Name
					),
					"away"
				)
			)
		then

			local character =
				player.Character

			if character then

				for _, part in ipairs(
					character:GetDescendants()
				) do

					if
						part:IsA("BasePart")
						and string.lower(
							part.Name
						) == "ball"
						and part.Material ==
							Enum.Material.Plastic
					then

						return player, part

					end
				end
			end
		end
	end

	return nil, nil
end

-- ==========================================
-- VIRTUAL KEY
-- ==========================================

local function PressVirtualKey(keyName)

	if not VirtualInputManager then
		return false
	end

	local data =
		preKeys[keyName]

	if not data then
		return false
	end

	local success =
		pcall(function()

			VirtualInputManager:SendKeyEvent(
				true,
				data.keyCode,
				false,
				game
			)

			VirtualInputManager:SendKeyEvent(
				false,
				data.keyCode,
				false,
				game
			)

		end)

	return success
end

-- ==========================================
-- PRE-KEYS FOR TARGET
-- ==========================================

local function RunPreKeysForTarget(
	isSameTeam
)

	local count = 0

	for _, keyName in ipairs(
		keyOrder
	) do

		local data =
			preKeys[keyName]

		if
			data.enabled
			and data.target ==
				isSameTeam
		then

			if PressVirtualKey(
				keyName
			) then

				count += 1

			end
		end
	end

	return count
end

-- ==========================================
-- TP ONCE TO BALL
-- ==========================================

local function TeleportToBallOnce()

	local ball =
		FindBall()

	if not ball then
		return false
	end

	local character =
		LocalPlayer.Character

	if not character then
		return false
	end

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root then
		return false
	end

	root.CFrame =
		ball.CFrame
		* CFrame.new(
			0,
			3,
			0
		)

	return true
end

-- ==========================================
-- TP ONCE TO HOLDER
-- ==========================================

local function TeleportToHolderOnce(
	holder
)

	if not holder then
		return false
	end

	local character =
		holder.Character

	if not character then
		return false
	end

	local targetRoot =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not targetRoot then
		return false
	end

	local myCharacter =
		LocalPlayer.Character

	if not myCharacter then
		return false
	end

	local myRoot =
		myCharacter:FindFirstChild(
			"HumanoidRootPart"
		)

	if not myRoot then
		return false
	end

	local isSameTeam =
		holder.Team ==
		LocalPlayer.Team

	local keyCount =
		RunPreKeysForTarget(
			isSameTeam
		)

	myRoot.CFrame =
		targetRoot.CFrame
		* CFrame.new(
			0,
			3,
			0
		)

	if keyCount > 0 then

		HolderLabel.Text =
			"Holder: "
			.. holder.Name
			.. " | Keys: "
			.. tostring(keyCount)

	end

	return true
end

-- ==========================================
-- TP TO BALL
-- ==========================================

local function StartTPToBall()

	if continuousRunning then
		return
	end

	continuousRunning = true
	cancelRequested = false

	StatusLabel.Text =
		"TP BALL: RUNNING"

	StatusLabel.TextColor3 =
		Color3.fromRGB(
			0,
			200,
			255
		)

	task.spawn(function()

		local startTime =
			os.clock()

		while
			not cancelRequested
			and os.clock()
				- startTime
				< ballTPTime
		do

			TeleportToBallOnce()

			RunService.Heartbeat:Wait()

		end

		continuousRunning = false

		if cancelRequested then

			StatusLabel.Text =
				"TP BALL: CANCELLED"

			StatusLabel.TextColor3 =
				Color3.fromRGB(
					255,
					80,
					80
				)

		else

			StatusLabel.Text =
				"TP BALL: DONE"

			StatusLabel.TextColor3 =
				Color3.fromRGB(
					50,
					255,
					100
				)

		end
	end)
end

-- ==========================================
-- TP TO HOLDER
-- ==========================================

local function StartTPToHolder()

	if continuousRunning then
		return
	end

	continuousRunning = true
	cancelRequested = false

	StatusLabel.Text =
		"TP HOLDER: RUNNING"

	StatusLabel.TextColor3 =
		Color3.fromRGB(
			100,
			255,
			130
		)

	task.spawn(function()

		local startTime =
			os.clock()

		while
			not cancelRequested
			and os.clock()
				- startTime
				< holderTPTime
		do

			local holder =
				FindBallHolder()

			if holder then

				currentHolder =
					holder

				currentSameTeam =
					holder.Team ==
					LocalPlayer.Team

				TeleportToHolderOnce(
					holder
				)

			end

			RunService.Heartbeat:Wait()

		end

		continuousRunning = false

		if cancelRequested then

			StatusLabel.Text =
				"TP HOLDER: CANCELLED"

			StatusLabel.TextColor3 =
				Color3.fromRGB(
					255,
					80,
					80
				)

		else

			StatusLabel.Text =
				"TP HOLDER: DONE"

			StatusLabel.TextColor3 =
				Color3.fromRGB(
					50,
					255,
					100
				)

		end
	end)
end

-- ==========================================
-- CONTINUOUS CHAIN
-- ==========================================

local function StartContinuous()

	if continuousRunning then
		return
	end

	continuousRunning = true
	cancelRequested = false

	task.spawn(function()

		-- ======================================
		-- BALL PHASE
		-- ======================================

		StatusLabel.Text =
			"CONTINUOUS: BALL"

		StatusLabel.TextColor3 =
			Color3.fromRGB(
				255,
				215,
				0
			)

		local ballStart =
			os.clock()

		local holderFound = false

		while
			not cancelRequested
			and os.clock()
				- ballStart
				< ballTPTime
		do

			local holder =
				FindBallHolder()

			if holder then

				holderFound = true
				break

			end

			TeleportToBallOnce()

			RunService.Heartbeat:Wait()

		end

		if cancelRequested then

			continuousRunning = false

			StatusLabel.Text =
				"CONTINUOUS: CANCELLED"

			StatusLabel.TextColor3 =
				Color3.fromRGB(
					255,
					80,
					80
				)

			return
		end

		if not holderFound then

			continuousRunning = false

			StatusLabel.Text =
				"CONTINUOUS: BALL TIMEOUT"

			StatusLabel.TextColor3 =
				Color3.fromRGB(
					255,
					120,
					50
				)

			return

		end

		-- ======================================
		-- HOLDER PHASE
		-- ======================================

		StatusLabel.Text =
			"CONTINUOUS: HOLDER"

		StatusLabel.TextColor3 =
			Color3.fromRGB(
				100,
				255,
				130
			)

		local holderStart =
			os.clock()

		while
			not cancelRequested
			and os.clock()
				- holderStart
				< holderTPTime
		do

			local holder =
				FindBallHolder()

			if holder then

				local isOpponent =
					holder.Team
					~=
					LocalPlayer.Team

				-- Continuous ưu tiên đối phương
				if isOpponent then

					TeleportToHolderOnce(
						holder
					)

					StatusLabel.Text =
						"CONTINUOUS → "
						.. holder.Name

				end
			end

			RunService.Heartbeat:Wait()

		end

		continuousRunning = false

		if cancelRequested then

			StatusLabel.Text =
				"CONTINUOUS: CANCELLED"

			StatusLabel.TextColor3 =
				Color3.fromRGB(
					255,
					80,
					80
				)

		else

			StatusLabel.Text =
				"CONTINUOUS: DONE"

			StatusLabel.TextColor3 =
				Color3.fromRGB(
					50,
					255,
					100
				)

		end

	end)
end

-- ==========================================
-- CANCEL
-- ==========================================

local function CancelTP()

	cancelRequested = true

	if continuousRunning then

		StatusLabel.Text =
			"TP: CANCELLING..."

		StatusLabel.TextColor3 =
			Color3.fromRGB(
				255,
				120,
				50
			)

	end
end

-- ==========================================
-- BUTTON EVENTS
-- ==========================================

TPBallButton.MouseButton1Click:Connect(
	StartTPToBall
)

TPHolderButton.MouseButton1Click:Connect(
	StartTPToHolder
)

ContinuousButton.MouseButton1Click:Connect(
	StartContinuous
)

CancelButton.MouseButton1Click:Connect(
	CancelTP
)

-- ==========================================
-- HIDE / SHOW
-- ==========================================

HideButton.MouseButton1Click:Connect(
	function()

		ShowButton.Position =
			MainFrame.Position

		MainFrame.Visible = false
		ShowButton.Visible = true

	end
)

ShowButton.MouseButton1Click:Connect(
	function()

		MainFrame.Position =
			ShowButton.Position

		ShowButton.Visible = false
		MainFrame.Visible = true

	end
)

-- ==========================================
-- SHOW BUTTON DRAG
-- ==========================================

local dragging = false
local dragStart
local dragPosition

ShowButton.InputBegan:Connect(
	function(input)

		if input.UserInputType ==
			Enum.UserInputType.MouseButton1
		then

			dragging = true

			dragStart =
				input.Position

			dragPosition =
				ShowButton.Position

			input.Changed:Connect(
				function()

					if
						input.UserInputState
						==
						Enum.UserInputState.End
					then

						dragging = false

					end
				end
			)
		end
	end
)

UserInputService.InputChanged:Connect(
	function(input)

		if not dragging then
			return
		end

		if input.UserInputType ==
			Enum.UserInputType.MouseMovement
		then

			local delta =
				input.Position
				- dragStart

			ShowButton.Position =
				UDim2.new(
					dragPosition.X.Scale,
					dragPosition.X.Offset
						+ delta.X,

					dragPosition.Y.Scale,
					dragPosition.Y.Offset
						+ delta.Y
				)
		end
	end
)

-- ==========================================
-- INPUT
-- ==========================================

UserInputService.InputBegan:Connect(
	function(input, gameProcessed)

		if input.UserInputType
			~= Enum.UserInputType.Keyboard
		then
			return
		end

		-- ======================================
		-- TP BUTTON HOTKEY ASSIGNMENT
		-- ======================================

		if tpHotkeys.Ball.waiting then

			if input.KeyCode ==
				Enum.KeyCode.Escape
			then

				tpHotkeys.Ball.waiting =
					false

				RefreshTPButtonText()

				return
			end

			if input.KeyCode
				~= Enum.KeyCode.Unknown
			then

				tpHotkeys.Ball.key =
					input.KeyCode

				tpHotkeys.Ball.waiting =
					false

				RefreshTPButtonText()

				return
			end
		end

		if tpHotkeys.Holder.waiting then

			if input.KeyCode ==
				Enum.KeyCode.Escape
			then

				tpHotkeys.Holder.waiting =
					false

				RefreshTPButtonText()

				return
			end

			if input.KeyCode
				~= Enum.KeyCode.Unknown
			then

				tpHotkeys.Holder.key =
					input.KeyCode

				tpHotkeys.Holder.waiting =
					false

				RefreshTPButtonText()

				return
			end
		end

		if tpHotkeys.Continuous.waiting then

			if input.KeyCode ==
				Enum.KeyCode.Escape
			then

				tpHotkeys.Continuous.waiting =
					false

				RefreshTPButtonText()

				return
			end

			if input.KeyCode
				~= Enum.KeyCode.Unknown
			then

				tpHotkeys.Continuous.key =
					input.KeyCode

				tpHotkeys.Continuous.waiting =
					false

				RefreshTPButtonText()

				return
			end
		end

		-- ======================================
		-- PREKEY HOTKEY ASSIGNMENT
		-- ======================================

		for _, keyName in ipairs(
			keyOrder
		) do

			local data =
				preKeys[keyName]

			if data.waitingHotkey then

				if input.KeyCode ==
					Enum.KeyCode.Escape
				then

					data.waitingHotkey =
						false

					UpdateKeyUI(
						keyName
					)

					return
				end

				if input.KeyCode
					~= Enum.KeyCode.Unknown
				then

					data.hotkey =
						input.KeyCode

					data.waitingHotkey =
						false

					UpdateKeyUI(
						keyName
					)

					return
				end
			end
		end

		if gameProcessed then
			return
		end

		-- ======================================
		-- TP HOTKEYS
		-- ======================================

		if input.KeyCode ==
			tpHotkeys.Ball.key
		then

			StartTPToBall()
			return

		end

		if input.KeyCode ==
			tpHotkeys.Holder.key
		then

			StartTPToHolder()
			return

		end

		if input.KeyCode ==
			tpHotkeys.Continuous.key
		then

			StartContinuous()
			return

		end

		-- ======================================
		-- PREKEY HOTKEYS
		-- ======================================

		for _, keyName in ipairs(
			keyOrder
		) do

			local data =
				preKeys[keyName]

			if input.KeyCode ==
				data.hotkey
			then

				data.enabled =
					not data.enabled

				UpdateKeyUI(
					keyName
				)

				return
			end
		end

	end
)

-- ==========================================
-- TRACKER
-- ==========================================

local function UpdateTracker()

	local playersInMatch = 0
	local localPlayerInMatch = false

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		if player.Team then

			local teamName =
				string.lower(
					player.Team.Name
				)

			if
				string.match(
					teamName,
					"home"
				)
				or
				string.match(
					teamName,
					"away"
				)
			then

				playersInMatch += 1

				if player == LocalPlayer then
					localPlayerInMatch = true
				end
			end
		end
	end

	if playersInMatch == 0 then

		currentStatus =
			"INTERMISSION"

		currentHolder = nil

		StatusLabel.Text =
			"INTERMISSION=)"

		StatusLabel.TextColor3 =
			Color3.fromRGB(
				255,
				215,
				0
			)

		HolderLabel.Text =
			"Holder: -"

		return
	end

	if not localPlayerInMatch then

		currentStatus = "NONE"
		currentHolder = nil

		StatusLabel.Text =
			"Status: NONE"

		StatusLabel.TextColor3 =
			Color3.fromRGB(
				150,
				150,
				150
			)

		HolderLabel.Text =
			"Holder: -"

		return
	end

	local holder =
		FindBallHolder()

	if holder then

		currentStatus =
			"TRUE"

		currentHolder =
			holder

		currentSameTeam =
			holder.Team ==
			LocalPlayer.Team

		-- Chỉ cập nhật status khi không
		-- có TP đang ghi đè text
		if not continuousRunning then

			StatusLabel.Text =
				"Status: TRUE"

			StatusLabel.TextColor3 =
				Color3.fromRGB(
					50,
					255,
					50
				)

		end

		if holder == LocalPlayer then

			HolderLabel.Text =
				"Holder: YOU | YES"

			HolderLabel.TextColor3 =
				Color3.fromRGB(
					0,
					255,
					255
				)

		elseif currentSameTeam then

			HolderLabel.Text =
				"Holder: "
				.. holder.Name
				.. " | YES"

			HolderLabel.TextColor3 =
				Color3.fromRGB(
					50,
					255,
					50
				)

		else

			HolderLabel.Text =
				"Holder: "
				.. holder.Name
				.. " | NO"

			HolderLabel.TextColor3 =
				Color3.fromRGB(
					255,
					80,
					80
				)

		end

	else

		currentStatus =
			"FALSE"

		currentHolder = nil

		if not continuousRunning then

			StatusLabel.Text =
				"Status: FALSE"

			StatusLabel.TextColor3 =
				Color3.fromRGB(
					255,
					50,
					50
				)

		end

		HolderLabel.Text =
			"Holder: BALL IS FREE"

		HolderLabel.TextColor3 =
			Color3.fromRGB(
				255,
				215,
				0
			)

	end
end

-- ==========================================
-- TRACKER LOOP
-- ==========================================

task.spawn(function()

	while ScreenGui.Parent do

		UpdateTracker()

		task.wait(
			scanFrequency
		)

	end

end)

-- ==========================================
-- INITIALIZE
-- ==========================================

for _, keyName in ipairs(
	keyOrder
) do

	UpdateKeyUI(keyName)

end

RefreshTPButtonText()

print(
	"[Ball Tracker V7] Loaded."
)
