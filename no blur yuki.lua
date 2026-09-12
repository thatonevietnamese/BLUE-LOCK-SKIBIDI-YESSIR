-- Services
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Danh sách chính xác các UI gây mực đen / mù màn hình
local TARGET_NAMES = {
    ["Blindness"] = true,
    ["ScreenEffectsGUI"] = true,
    ["BlackBars"] = true,
    ["FadeGUI"] = true,
    ["Vignette"] = true
}

-- Hàm xử lý vô hiệu hóa đích danh UI
local function disableTargetUI(object)
    if TARGET_NAMES[object.Name] then
        warn("[ANTI-INK FIXED] Đã vô hiệu hóa: " .. object:GetFullName())

        if object:IsA("ScreenGui") then
            object.Enabled = false
            object:GetPropertyChangedSignal("Enabled"):Connect(function()
                if object.Enabled then object.Enabled = false end
            end)
        elseif object:IsA("GuiObject") then
            object.Visible = false
            object.BackgroundTransparency = 1
            
            if object:IsA("ImageLabel") or object:IsA("ImageButton") then
                object.ImageTransparency = 1
                object:GetPropertyChangedSignal("ImageTransparency"):Connect(function()
                    if object.ImageTransparency < 1 then object.ImageTransparency = 1 end
                end)
            end

            object:GetPropertyChangedSignal("Visible"):Connect(function()
                if object.Visible then object.Visible = false end
            end)
        end
    end
end

-- 1. Quét và khóa các UI đích trong PlayerGui
for _, desc in ipairs(playerGui:GetDescendants()) do
    disableTargetUI(desc)
end
playerGui.DescendantAdded:Connect(disableTargetUI)

-- 2. Khóa toàn bộ Blur / ColorCorrection trong Lighting
local function disableLightingEffect(obj)
    if obj:IsA("BlurEffect") or obj:IsA("ColorCorrectionEffect") or obj:IsA("DepthOfFieldEffect") then
        obj.Enabled = false
        obj:GetPropertyChangedSignal("Enabled"):Connect(function()
            if obj.Enabled then obj.Enabled = false end
        end)
    end
end

for _, child in ipairs(Lighting:GetChildren()) do disableLightingEffect(child) end
Lighting.ChildAdded:Connect(disableLightingEffect)
