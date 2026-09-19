--// WeldBall Auto Pickup
--// PC + Mobile
--// Draggable UI
--// Auto refresh after character reset
--// Clean connections / no duplicate loops

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

--==================================================
-- CONFIG
--==================================================

local Config = {
    DefaultHotkey = Enum.KeyCode.F,
    FireDelay = 0.05,

    UIWidth = 230,
    PCHeight = 130,
    MobileHeight = 100,

    StartPosition = UDim2.new(0.5, -115, 0.5, -65),
}

--==================================================
-- DEVICE
--==================================================

local IsMobile =
    UserInputService.TouchEnabled
    and not UserInputService.KeyboardEnabled

--==================================================
-- STATE
--==================================================

local Enabled = false
local Hotkey = Config.DefaultHotkey

local Gui
local Frame
local ToggleButton
local HotkeyButton

local SavedPosition = Config.StartPosition

local GuiConnections = {}
local CharacterConnection = nil
local PickupThread = nil

local WaitingForHotkey = false

--==================================================
-- CONNECTION MANAGEMENT
--==================================================

local function DisconnectGuiConnections()
    for _, connection in ipairs(GuiConnections) do
        if connection then
            connection:Disconnect()
        end
    end

    table.clear(GuiConnections)
end

--==================================================
-- FIND WELD EVENT
--==================================================

local function GetWeldBall()
    local Ball = workspace:FindFirstChild("Ball")

    if not Ball then
        return nil
    end

    local Event = Ball:FindFirstChild("WeldBall")

    if Event and Event:IsA("RemoteEvent") then
        return Event
    end

    return nil
end

--==================================================
-- PICKUP LOOP
--==================================================

local function StartPickupLoop()

    if PickupThread then
        return
    end

    PickupThread = task.spawn(function()

        while Enabled do

            local Event = GetWeldBall()

            if Event then
                pcall(function()
                    Event:FireServer()
                end)
            end

            task.wait(Config.FireDelay)
        end

        PickupThread = nil
    end)
end

local function SetEnabled(Value)

    Enabled = Value

    if ToggleButton then
        ToggleButton.Text =
            Enabled
            and "AUTO PICKUP: ON"
            or "AUTO PICKUP: OFF"
    end

    if Enabled then
        StartPickupLoop()
    end
end

local function Toggle()
    SetEnabled(not Enabled)
end

--==================================================
-- DRAGGABLE UI
--==================================================

local function MakeDraggable(Target)

    local Dragging = false
    local DragStart
    local StartPosition

    local function Update(Input)

        local Delta =
            Input.Position - DragStart

        Target.Position = UDim2.new(
            StartPosition.X.Scale,
            StartPosition.X.Offset + Delta.X,

            StartPosition.Y.Scale,
            StartPosition.Y.Offset + Delta.Y
        )

        SavedPosition = Target.Position
    end

    table.insert(
        GuiConnections,

        Target.InputBegan:Connect(function(Input)

            if Input.UserInputType == Enum.UserInputType.MouseButton1
                or Input.UserInputType == Enum.UserInputType.Touch then

                Dragging = true
                DragStart = Input.Position
                StartPosition = Target.Position

                local ChangedConnection

                ChangedConnection =
                    Input.Changed:Connect(function()

                        if Input.UserInputState ==
                            Enum.UserInputState.End then

                            Dragging = false

                            if ChangedConnection then
                                ChangedConnection:Disconnect()
                            end
                        end
                    end)
            end
        end)
    )

    table.insert(
        GuiConnections,

        UserInputService.InputChanged:Connect(function(Input)

            if not Dragging then
                return
            end

            if Input.UserInputType ==
                Enum.UserInputType.MouseMovement
                or Input.UserInputType ==
                Enum.UserInputType.Touch then

                Update(Input)
            end
        end)
    )
end

--==================================================
-- DESTROY GUI ONLY
--==================================================

local function DestroyGUI()

    DisconnectGuiConnections()

    WaitingForHotkey = false

    if Frame then
        SavedPosition = Frame.Position
    end

    if Gui then
        Gui:Destroy()
    end

    Gui = nil
    Frame = nil
    ToggleButton = nil
    HotkeyButton = nil
end

--==================================================
-- UNLOAD SCRIPT COMPLETELY
--==================================================

local function UnloadScript()
    SetEnabled(false)

    if CharacterConnection then
        CharacterConnection:Disconnect()
        CharacterConnection = nil
    end

    DestroyGUI()
end

--==================================================
-- CREATE GUI
--==================================================

local function CreateGUI()

    -- Remove old UI only.
    -- CharacterAdded connection is NOT touched.
    DestroyGUI()

    --==============================================
    -- SCREEN GUI
    --==============================================

    Gui = Instance.new("ScreenGui")
    Gui.Name = "WeldBallAutoPickup"
    Gui.ResetOnSpawn = false
    Gui.IgnoreGuiInset = true
    Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    --==============================================
    -- MAIN FRAME
    --==============================================

    Frame = Instance.new("Frame")
    Frame.Name = "Main"

    Frame.Size = UDim2.fromOffset(
        Config.UIWidth,

        IsMobile
            and Config.MobileHeight
            or Config.PCHeight
    )

    Frame.Position = SavedPosition

    Frame.BackgroundColor3 =
        Color3.fromRGB(25, 25, 25)

    Frame.BorderSizePixel = 0
    Frame.Active = true
    Frame.Parent = Gui

    local FrameCorner =
        Instance.new("UICorner")

    FrameCorner.CornerRadius =
        UDim.new(0, 10)

    FrameCorner.Parent = Frame

    --==============================================
    -- TITLE / DRAG AREA
    --==============================================

    local Title = Instance.new("TextLabel")

    Title.Name = "Title"
    Title.Size = UDim2.new(1, -45, 0, 25)
    Title.Position = UDim2.fromOffset(10, 5)

    Title.BackgroundTransparency = 1

    Title.Text = "⚽ WeldBall Auto Pickup"
    Title.TextColor3 = Color3.new(1, 1, 1)
    Title.TextSize = 14
    Title.Font = Enum.Font.GothamBold

    Title.TextXAlignment =
        Enum.TextXAlignment.Left

    Title.Parent = Frame

    --==============================================
    -- CLOSE / UNLOAD BUTTON
    --==============================================

    local CloseButton = Instance.new("TextButton")

    CloseButton.Name = "Close"
    CloseButton.Size = UDim2.fromOffset(20, 20)
    CloseButton.Position = UDim2.new(1, -25, 0, 7)

    CloseButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    CloseButton.BorderSizePixel = 0

    CloseButton.Text = "X"
    CloseButton.TextColor3 = Color3.new(1, 1, 1)
    CloseButton.TextSize = 12
    CloseButton.Font = Enum.Font.GothamBold

    CloseButton.Parent = Frame

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 5)
    CloseCorner.Parent = CloseButton

    table.insert(
        GuiConnections,
        CloseButton.MouseButton1Click:Connect(UnloadScript)
    )

    --==============================================
    -- TOGGLE BUTTON
    --==============================================

    ToggleButton = Instance.new("TextButton")

    ToggleButton.Name = "Toggle"

    ToggleButton.Size =
        UDim2.new(1, -20, 0, 42)

    ToggleButton.Position =
        UDim2.fromOffset(
            10,
            IsMobile and 42 or 35
        )

    ToggleButton.BackgroundColor3 =
        Color3.fromRGB(45, 45, 45)

    ToggleButton.BorderSizePixel = 0

    ToggleButton.TextColor3 =
        Color3.new(1, 1, 1)

    ToggleButton.TextSize = 15
    ToggleButton.Font = Enum.Font.GothamBold

    ToggleButton.Text =
        Enabled
        and "AUTO PICKUP: ON"
        or "AUTO PICKUP: OFF"

    ToggleButton.Parent = Frame

    local ToggleCorner =
        Instance.new("UICorner")

    ToggleCorner.CornerRadius =
        UDim.new(0, 8)

    ToggleCorner.Parent =
        ToggleButton

    table.insert(
        GuiConnections,

        ToggleButton.MouseButton1Click:Connect(
            Toggle
        )
    )

    --==============================================
    -- MOBILE
    --==============================================

    if IsMobile then

        -- No keyboard setting on mobile.
        HotkeyButton = nil

    else

        --==========================================
        -- HOTKEY BUTTON
        --==========================================

        HotkeyButton = Instance.new("TextButton")

        HotkeyButton.Name = "Hotkey"

        HotkeyButton.Size =
            UDim2.new(1, -20, 0, 35)

        HotkeyButton.Position =
            UDim2.fromOffset(10, 82)

        HotkeyButton.BackgroundColor3 =
            Color3.fromRGB(35, 35, 35)

        HotkeyButton.BorderSizePixel = 0

        HotkeyButton.TextColor3 =
            Color3.new(1, 1, 1)

        HotkeyButton.TextSize = 13
        HotkeyButton.Font = Enum.Font.Gotham

        HotkeyButton.Text =
            "Hotkey: " .. Hotkey.Name

        HotkeyButton.Parent = Frame

        local HotkeyCorner =
            Instance.new("UICorner")

        HotkeyCorner.CornerRadius =
            UDim.new(0, 8)

        HotkeyCorner.Parent =
            HotkeyButton

        --==========================================
        -- CHANGE HOTKEY
        --==========================================

        table.insert(
            GuiConnections,

            HotkeyButton.MouseButton1Click:Connect(
                function()

                    if WaitingForHotkey then
                        return
                    end

                    WaitingForHotkey = true

                    HotkeyButton.Text =
                        "Press a key..."

                    task.delay(5, function()

                        if not WaitingForHotkey then
                            return
                        end

                        WaitingForHotkey = false

                        if HotkeyButton then
                            HotkeyButton.Text =
                                "Hotkey: "
                                .. Hotkey.Name
                        end
                    end)
                end
            )
        )

        --==========================================
        -- KEYBOARD
        --==========================================

        table.insert(
            GuiConnections,

            UserInputService.InputBegan:Connect(
                function(Input, Processed)

                    if Processed then
                        return
                    end

                    if Input.UserInputType ~=
                        Enum.UserInputType.Keyboard then
                        return
                    end

                    -- Changing hotkey
                    if WaitingForHotkey then

                        Hotkey =
                            Input.KeyCode

                        WaitingForHotkey =
                            false

                        if HotkeyButton then
                            HotkeyButton.Text =
                                "Hotkey: "
                                .. Hotkey.Name
                        end

                        return
                    end

                    -- Normal toggle
                    if Input.KeyCode == Hotkey then
                        Toggle()
                    end
                end
            )
        )
    end

    --==============================================
    -- DRAG
    --==============================================

    MakeDraggable(Frame)
end

--==================================================
-- CHARACTER RESET
--==================================================

CharacterConnection =
    LocalPlayer.CharacterAdded:Connect(
        function()

            -- Wait for PlayerGui / character
            task.wait(0.5)

            -- Keep current Enabled state.
            -- CreateGUI reads the existing state.
            CreateGUI()

            -- Restart loop if it was ON.
            if Enabled then
                StartPickupLoop()
            end
        end
    )

--==================================================
-- INITIALIZE
--==================================================

CreateGUI()
