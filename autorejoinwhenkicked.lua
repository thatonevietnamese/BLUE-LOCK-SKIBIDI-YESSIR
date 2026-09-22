-- Roblox Auto Rejoin Script
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")

-- Bỏ qua màn hình báo lỗi của Roblox và bấm Rejoin
CoreGui.RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
    if child.Name == "ErrorPrompt" then
        task.wait(1) -- Chờ 1 giây để tránh bị spam teleport
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end
end)

print("Auto Rejoin đã bật! Bạn sẽ tự động vào lại khi bị văng game.")
