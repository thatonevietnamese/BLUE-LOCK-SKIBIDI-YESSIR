local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- [ CẤU HÌNH ] (Bạn có thể sửa ở đây)
-- ==========================================
local ENABLE_TRACKER = true -- Đổi thành false nếu muốn tắt chức năng này
local LOBBY_TEAM_NAME = "Lobby" -- Tên Team ở sảnh (có thể đổi thành "Spectator", "Waiting" tùy game)

local TRAJECTORY_TIME = 2
local STEP = 0.05
local BEAM_WIDTH = 0.3
local TRAJECTORY_COLOR = ColorSequence.new(Color3.fromRGB(255, 238, 0))
-- ==========================================

-- Chống lag/trùng lặp khi bạn bấm Execute nhiều lần
if Workspace:FindFirstChild("TrajectoryVisuals") then
    Workspace.TrajectoryVisuals:Destroy()
end
if _G.BallTrackerConnection then
    _G.BallTrackerConnection:Disconnect()
    _G.BallTrackerConnection = nil
end

pcall(function()
    LocalPlayer:WaitForChild("DataLoaded", 2)
end)

local Folder = Instance.new("Folder")
Folder.Name = "TrajectoryVisuals"
Folder.Parent = Workspace

local Attachments = {}
local Beams = {}

-- Hàm tính toán quỹ đạo
local function getTrajectoryPosition(position, velocity, time)
    local gravity = Vector3.new(0, -Workspace.Gravity, 0)
    return position + (velocity * time) + (gravity * 0.5 * time ^ 2)
end

-- Hàm tạo các đường beam
local function getOrCreateElements(index)
    if not Attachments[index] then
        local attachment = Instance.new("Attachment")
        attachment.Name = "TrajectoryAttachment_" .. index
        attachment.Parent = Workspace.Terrain
        Attachments[index] = attachment
    end

    if index > 1 and not Beams[index - 1] then
        local beam = Instance.new("Beam")
        beam.Name = "TrajectoryBeam_" .. (index - 1)
        beam.Color = TRAJECTORY_COLOR
        beam.Width0 = BEAM_WIDTH
        beam.Width1 = BEAM_WIDTH
        beam.FaceCamera = true
        beam.Transparency = NumberSequence.new(0)
        beam.Segments = 1
        beam.Attachment0 = Attachments[index - 1]
        beam.Attachment1 = Attachments[index]
        beam.Parent = Folder
        
        Beams[index - 1] = beam
    end

    Attachments[index].Visible = false
    
    if Beams[index - 1] then
        Beams[index - 1].Enabled = true
    end
end

-- Hàm giấu quỹ đạo khi ở sảnh hoặc khi tắt tracker
local function hideTrajectory()
    for _, beam in pairs(Beams) do
        if beam then
            beam.Enabled = false
        end
    end
end

-- Hàm cập nhật quỹ đạo
local function updateTrajectory(ball)
    if not ball or not ball:IsDescendantOf(Workspace) then
        hideTrajectory()
        return
    end

    local index = 1
    for time = 0, TRAJECTORY_TIME, STEP do
        getOrCreateElements(index)
        Attachments[index].WorldPosition = getTrajectoryPosition(
            ball.Position,
            ball.AssemblyLinearVelocity,
            time
        )
        index += 1
    end

    -- Xóa các đoạn thừa
    for i = index, #Attachments do
        if Attachments[i] then
            Attachments[i].WorldPosition = Vector3.new(0, -1000, 0)
        end
        if Beams[i - 1] then
            Beams[i - 1].Enabled = false
        end
    end
end

local function getBall()
    local ball = Workspace:FindFirstChild("Ball")
    if ball and ball:IsDescendantOf(Workspace) then
        return ball
    end
    return nil
end

-- Vòng lặp liên tục kiểm tra
_G.BallTrackerConnection = RunService.RenderStepped:Connect(function()
    
    -- 1. Nếu công tắc TẮT -> Giấu Tracker
    if not ENABLE_TRACKER then
        hideTrajectory()
        return
    end

    -- 2. Nếu đang ở team LOBBY -> Giấu Tracker (Tránh lỗi)
    if LocalPlayer.Team and LocalPlayer.Team.Name == LOBBY_TEAM_NAME then
        hideTrajectory()
        return
    end

    -- 3. Cập nhật Tracker nếu có bóng trên sân
    local ball = getBall()
    if ball then
        updateTrajectory(ball)
    else
        hideTrajectory()
    end
end)
