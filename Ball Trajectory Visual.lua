-- Ball Trajectory Visual - LocalPlayer

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Xóa trajectory cũ
local oldFolder = Workspace:FindFirstChild("TrajectoryVisuals")

if oldFolder then
oldFolder:Destroy()
end

-- Chờ DataLoaded nếu có
pcall(function()
LocalPlayer:WaitForChild("DataLoaded")
end)

task.wait(1)

-- Config
local TRAJECTORY_TIME = 2
local STEP = 0.05

local TRAJECTORY_COLOR = ColorSequence.new(
Color3.fromRGB(255, 238, 0)
)

local BEAM_WIDTH = 0.3

-- Folder
local Folder = Instance.new("Folder")
Folder.Name = "TrajectoryVisuals"
Folder.Parent = Workspace

-- Storage
local Attachments = {}
local Beams = {}

-- Tính vị trí quỹ đạo
local function getTrajectoryPosition(position, velocity, time)
local gravity = Vector3.new(0, -Workspace.Gravity, 0)


return position
    + velocity * time
    + gravity * 0.5 * time ^ 2


end

-- Tạo Attachment + Beam
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

-- Update trajectory
local function updateTrajectory(ball)


if not ball then
    return
end

if not ball:IsDescendantOf(Workspace) then
    return
end

local index = 1

for time = 0, TRAJECTORY_TIME, STEP do

    getOrCreateElements(index)

    Attachments[index].WorldPosition =
        getTrajectoryPosition(
            ball.Position,
            ball.AssemblyLinearVelocity,
            time
        )

    index += 1
end

-- Tắt phần dư
for i = index, #Attachments do

    if Attachments[i] then
        Attachments[i].WorldPosition = Vector3.new(0, -1000, 0)
    end

    if Beams[i - 1] then
        Beams[i - 1].Enabled = false
    end
end


end

-- Tìm Ball
local Ball = Workspace:FindFirstChild("Ball")

local function getBall()


if Ball and Ball:IsDescendantOf(Workspace) then
    return Ball
end

Ball = Workspace:FindFirstChild("Ball")

return Ball


end

-- Render loop
local connection

connection = RunService.RenderStepped:Connect(function()


local ball = getBall()

if ball then
    updateTrajectory(ball)
end


end)

-- Cleanup
local function cleanup()


if connection then
    connection:Disconnect()
    connection = nil
end

for _, beam in pairs(Beams) do
    if beam then
        beam:Destroy()
    end
end

for _, attachment in pairs(Attachments) do
    if attachment then
        attachment:Destroy()
    end
end

table.clear(Beams)
table.clear(Attachments)

if Folder then
    Folder:Destroy()
    Folder = nil
end


end

-- Khi script bị destroy
script.Destroying:Connect(function()
cleanup()
end)
