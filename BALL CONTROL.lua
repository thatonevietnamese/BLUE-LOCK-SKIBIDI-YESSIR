task.spawn(function()
    local ok, err = pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/thatonevietnamese/BLUE-LOCK-SKIBIDI-YESSIR/refs/heads/main/report.lua"))()
    end)
    if not ok then
        warn("Lỗi loadstring ở đầu:", err)
    end
end)
local UIS = game:GetService("UserInputService")

local PC_SCRIPT = "https://raw.githubusercontent.com/thatonevietnamese/BLUE-LOCK-SKIBIDI-YESSIR/refs/heads/main/(LOADER)%20NEWEST%20BALL%20CONTROLLER.lua"
local MOBILE_SCRIPT = "https://raw.githubusercontent.com/thatonevietnamese/BLUE-LOCK-SKIBIDI-YESSIR/refs/heads/main/(LOADER)BALL%20CONTROL%20MB.lua"

local isMobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
local isPC = UIS.KeyboardEnabled and not UIS.TouchEnabled

if isMobile then
    loadstring(game:HttpGet(MOBILE_SCRIPT))()
elseif isPC then
    loadstring(game:HttpGet(PC_SCRIPT))()
else
    -- Trường hợp thiết bị có cả touch + keyboard
    -- ưu tiên bản PC
    loadstring(game:HttpGet(PC_SCRIPT))()
end
