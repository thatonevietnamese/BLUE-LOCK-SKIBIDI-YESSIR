-- ==========================================
-- BALL TRACKER + HOLDER + TP TO BALL (V2 - ĐÃ SỬA LỖI TP)
-- ==========================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------
-- GUI
--------------------------------------------------

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BallTrackerUI"
ScreenGui.ResetOnSpawn = false
-- Hỗ trợ chạy trên Executor an toàn hơn
ScreenGui.Parent = RunService:IsStudio() and LocalPlayer:WaitForChild("PlayerGui") or CoreGui

--------------------------------------------------
-- MAIN FRAME
--------------------------------------------------

local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui
MainFrame.Size = UDim2.new(0, 360, 0, 180)
MainFrame.Position = UDim2.new(0.5, -180, 0, 20)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.BorderSizePixel = 2
MainFrame.BorderColor3 = Color3.fromRGB(0, 170, 255)
MainFrame.Active = true
MainFrame.Draggable = true

--------------------------------------------------
-- TITLE
--------------------------------------------------

local Title = Instance.new("TextLabel")
Title.Parent = MainFrame
Title.Size = UDim2.new(1, 0, 0, 25)
Title.BackgroundTransparency = 1
Title.Text = "Ball Tracker"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16

--------------------------------------------------
-- STATUS
--------------------------------------------------

local DisplayStatus = Instance.new("TextLabel")
DisplayStatus.Parent = MainFrame
DisplayStatus.Size = UDim2.new(0, 160, 0, 40)
DisplayStatus.Position = UDim2.new(0, 10, 0, 30)
DisplayStatus.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
DisplayStatus.TextColor3 = Color3.fromRGB(255, 50, 50)
DisplayStatus.Text = "Status: FALSE"
DisplayStatus.Font = Enum.Font.SourceSansBold
DisplayStatus.TextSize = 20

--------------------------------------------------
-- HOLDER INDICATOR
--------------------------------------------------

local IndicatorBox = Instance.new("TextLabel")
IndicatorBox.Parent = MainFrame
IndicatorBox.Size = UDim2.new(0, 60, 0, 40)
IndicatorBox.Position = UDim2.new(0, 180, 0, 30)
IndicatorBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
IndicatorBox.TextColor3 = Color3.fromRGB(150, 150, 150)
IndicatorBox.Text = "-"
IndicatorBox.Font = Enum.Font.GothamBold
IndicatorBox.TextSize = 20

--------------------------------------------------
-- TEAM BOX
--------------------------------------------------

local TeamBox = Instance.new("TextLabel")
TeamBox.Parent = MainFrame
TeamBox.Size = UDim2.new(0, 60, 0, 40)
TeamBox.Position = UDim2.new(0, 250, 0, 30)
TeamBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
TeamBox.TextColor3 = Color3.fromRGB(150, 150, 150)
TeamBox.Text = "-"
TeamBox.Font = Enum.Font.GothamBold
TeamBox.TextSize = 18

--------------------------------------------------
-- HOLDER NAME
--------------------------------------------------

local HolderNameBox = Instance.new("TextLabel")
HolderNameBox.Parent = MainFrame
HolderNameBox.Size = UDim2.new(1, -20, 0, 30)
HolderNameBox.Position = UDim2.new(0, 10, 0, 75)
HolderNameBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
HolderNameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
HolderNameBox.Text = "Holder: -"
HolderNameBox.Font = Enum.Font.GothamBold
HolderNameBox.TextSize = 16
HolderNameBox.TextXAlignment = Enum.TextXAlignment.Left

--------------------------------------------------
-- FREQUENCY
--------------------------------------------------

local FrequencyInput = Instance.new("TextBox")
FrequencyInput.Parent = MainFrame
FrequencyInput.Size = UDim2.new(0, 150, 0, 30)
FrequencyInput.Position = UDim2.new(0, 10, 0, 115)
FrequencyInput.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
FrequencyInput.TextColor3 = Color3.fromRGB(255, 255, 255)
FrequencyInput.Text = "0.5"
FrequencyInput.PlaceholderText = "Tần suất"
FrequencyInput.Font = Enum.Font.SourceSans
FrequencyInput.TextSize = 16
FrequencyInput.ClearTextOnFocus = false

--------------------------------------------------
-- TP BUTTON
--------------------------------------------------

local TPButton = Instance.new("TextButton")
TPButton.Parent = MainFrame
TPButton.Size = UDim2.new(0, 185, 0, 30)
TPButton.Position = UDim2.new(0, 165, 0, 115)
TPButton.BackgroundColor3 = Color3.fromRGB(40, 130, 220)
TPButton.TextColor3 = Color3.fromRGB(255, 255, 255)
TPButton.Text = "TP TO BALL"
TPButton.Font = Enum.Font.GothamBold
TPButton.TextSize = 15

--------------------------------------------------
-- SCAN FREQUENCY
--------------------------------------------------

local scanFrequency = 0.5

FrequencyInput.FocusLost:Connect(function()
	local num = tonumber(FrequencyInput.Text)
	if num and num >= 0.01 then
		scanFrequency = num
	else
		FrequencyInput.Text = tostring(scanFrequency)
	end
end)

--------------------------------------------------
-- TÌM BÓNG TRÊN SÂN
--------------------------------------------------
local function FindBall()
	local ball = workspace:FindFirstChild("Ball")
	if ball then
		if ball:IsA("BasePart") then return ball end
		local part = ball:FindFirstChildWhichIsA("BasePart", true)
		if part then return part end
	end

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and string.lower(obj.Name) == "ball" and obj.Material == Enum.Material.Plastic then
			return obj
		end
	end
	return nil
end

--------------------------------------------------
-- TÌM AI ĐANG CẦM BÓNG
--------------------------------------------------
local function FindBallHolder()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Team and (string.match(string.lower(player.Team.Name), "home") or string.match(string.lower(player.Team.Name), "away")) then
			local character = player.Character
			if character then
				for _, part in ipairs(character:GetDescendants()) do
					if part:IsA("BasePart") and string.lower(part.Name) == "ball" and part.Material == Enum.Material.Plastic then
						return player, part
					end
				end
			end
		end
	end
	return nil, nil
end

--------------------------------------------------
-- CHECK BALL LOGIC (CẬP NHẬT UI)
--------------------------------------------------
local function CheckBallOnPlayers()
	local playersInMatch = 0
	local localPlayerInMatch = false

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Team then
			local teamName = string.lower(player.Team.Name)
			if string.match(teamName, "home") or string.match(teamName, "away") then
				playersInMatch = playersInMatch + 1
				if player == LocalPlayer then localPlayerInMatch = true end
			end
		end
	end

	if playersInMatch == 0 then return "INTERMISSION", "-", "-", nil end
	if not localPlayerInMatch then return "NONE", "-", "-", nil end

	local holder = FindBallHolder()
	if holder then
		local isSameTeam = (holder.Team == LocalPlayer.Team) and "YES" or "NO"
		if holder == LocalPlayer then
			return "TRUE", "1", "YES", holder
		else
			return "TRUE", "0", isSameTeam, holder
		end
	end
	return "FALSE", "-", "-", nil
end

--------------------------------------------------
-- TP TO BALL (ĐÃ FIX LỖI 100%)
--------------------------------------------------
local function TeleportToBall()
	-- 1. Tìm quả bóng
	local ball = FindBall()
	
	-- 2. Nếu bóng không ở ngoài sân, kiểm tra xem có ai cầm không
	if not ball then
		local _, heldBall = FindBallHolder()
		if heldBall then ball = heldBall end
	end

	if not ball then
		warn("Ball Tracker: Không tìm thấy Bóng!")
		return
	end

	-- 3. Lấy Character của bản thân (Dùng thuộc tính chuẩn của Roblox)
	local myChar = LocalPlayer.Character
	if not myChar then
		warn("Ball Tracker: Không tìm thấy nhân vật của bạn!")
		return
	end

	-- 4. Thực hiện dịch chuyển chuẩn xác
	local targetCFrame = ball.CFrame * CFrame.new(0, 3, 0) -- Bay phía trên bóng 3 stud
	
	-- Ép vị trí bằng HumanoidRootPart thay vì PivotTo (tránh lỗi kẹt Model)
	local hrp = myChar:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = targetCFrame
	else
		-- Phương án dự phòng nếu game có cấu trúc character dị
		myChar:PivotTo(targetCFrame)
	end
end

TPButton.MouseButton1Click:Connect(TeleportToBall)

--------------------------------------------------
-- UPDATE UI
--------------------------------------------------
local function UpdateUI(status, holderIndicator, sameTeamStatus, holder)
	if status == "INTERMISSION" then
		DisplayStatus.Text = "INTERMISSION=)"
		DisplayStatus.TextColor3 = Color3.fromRGB(255, 215, 0)
	elseif status == "NONE" then
		DisplayStatus.Text = "Status: NONE"
		DisplayStatus.TextColor3 = Color3.fromRGB(150, 150, 150)
	elseif status == "TRUE" then
		DisplayStatus.Text = "Status: TRUE"
		DisplayStatus.TextColor3 = Color3.fromRGB(50, 255, 50)
	elseif status == "FALSE" then
		DisplayStatus.Text = "Status: FALSE"
		DisplayStatus.TextColor3 = Color3.fromRGB(255, 50, 50)
	end

	IndicatorBox.Text = holderIndicator
	if holderIndicator == "1" then IndicatorBox.TextColor3 = Color3.fromRGB(0, 255, 255)
	elseif holderIndicator == "0" then IndicatorBox.TextColor3 = Color3.fromRGB(255, 170, 0)
	else IndicatorBox.TextColor3 = Color3.fromRGB(150, 150, 150) end

	TeamBox.Text = sameTeamStatus
	if sameTeamStatus == "YES" then TeamBox.TextColor3 = Color3.fromRGB(50, 255, 50)
	elseif sameTeamStatus == "NO" then TeamBox.TextColor3 = Color3.fromRGB(255, 50, 50)
	else TeamBox.TextColor3 = Color3.fromRGB(150, 150, 150) end

	if holder then
		HolderNameBox.Text = "Holder: " .. holder.Name
		if holder == LocalPlayer then HolderNameBox.TextColor3 = Color3.fromRGB(0, 255, 255)
		elseif holder.Team == LocalPlayer.Team then HolderNameBox.TextColor3 = Color3.fromRGB(50, 255, 50)
		else HolderNameBox.TextColor3 = Color3.fromRGB(255, 80, 80) end
	elseif status == "FALSE" then
		HolderNameBox.Text = "Holder: BALL IS FREE"
		HolderNameBox.TextColor3 = Color3.fromRGB(255, 215, 0)
	else
		HolderNameBox.Text = "Holder: -"
		HolderNameBox.TextColor3 = Color3.fromRGB(150, 150, 150)
	end
end

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------
task.spawn(function()
	while ScreenGui.Parent do
		local status, holderIndicator, sameTeamStatus, holder = CheckBallOnPlayers()
		UpdateUI(status, holderIndicator, sameTeamStatus, holder)
		task.wait(scanFrequency)
	end
end)
