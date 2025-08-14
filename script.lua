-- =======================
--  Game Hub + VIP System (EN)
--  VIP online check + legacy handling + VIP-only Items
--  Remove VIP tabs on expiry (reload) + clipboard on invalid key
--  Unlock All is VIP-only
--  by @plet_farmyt
-- =======================

-- Destroy previous UI if exists
if getgenv().LoadedUI then
    getgenv().LoadedUI:Destroy()
end

-- Create base UI container
getgenv().LoadedUI = Instance.new("ScreenGui")
getgenv().LoadedUI.Parent = game:GetService("CoreGui")
getgenv().LoadedUI.Name = "LoadedUI_Rayfield"

-- Load Rayfield
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- Services
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local LocalPlayer       = Players.LocalPlayer
local camera            = Workspace.CurrentCamera

-- ================ Config ================
local LEGACY_KEY      = "megvipmode"  -- accepted only if already saved locally
local VIP_API_BASE    = "https://YOUR-WORKER-NAME.workers.dev" -- TODO: set your Worker URL
local RELOAD_URL      = "https://raw.githubusercontent.com/pletfarm454/scripts/refs/heads/main/script.lua"
local DISCORD_CONTACT = "plet_farm"

-- ================ Base64 utils ================
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function encodeBase64(data)
    return ((data:gsub('.', function(x)
        local r,bits='',x:byte()
        for i=8,1,-1 do r=r..(bits%2^i-bits%2^(i-1)>0 and '1' or '0') end
        return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end
local function decodeBase64(data)
    data = string.gsub(data, '[^'..b..']=*', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',b:find(x)-1
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

-- ================ VIP local storage ================
local VIP_FILE = "vipkey.txt"
local function SaveVIP(raw)
    pcall(function() writefile(VIP_FILE, encodeBase64(raw)) end)
end
local function LoadVIP()
    local ok, res = pcall(function() return readfile(VIP_FILE) end)
    if ok and res then return decodeBase64(res) end
    return ""
end

-- ================ Utility ================
local function SafeSetClipboard(text)
    pcall(function() setclipboard(text) end)
end
local function unixTime()
    return DateTime.now().UnixTimestamp
end
local function parseV2Saved(raw)
    local prefix, key, expStr, uidStr = string.match(raw or "", "^(v2)|([^|]+)|([^|]+)|([^|]+)$")
    if prefix == "v2" then
        return { key = key, expires = tonumber(expStr) or 0, userId = tonumber(uidStr) or 0 }
    end
    return nil
end
local function validateKeyOnline(key)
    local ok, body = pcall(function()
        local url = string.format("%s/validate?key=%s&uid=%d",
            VIP_API_BASE,
            HttpService:UrlEncode(key),
            Players.LocalPlayer.UserId
        )
        return game:HttpGet(url)
    end)
    if not ok then return false, "Network" end
    local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok2 then return false, "JSON" end
    if data.ok then
        return true, data.entry
    else
        return false, data.reason or "Unknown"
    end
end

-- ================ Initial VIP status ================
local isVIP, vipAccess = false, false
do
    local savedRaw = LoadVIP()
    local savedV2  = parseV2Saved(savedRaw)
    if savedRaw == LEGACY_KEY then
        isVIP, vipAccess = true, true
    elseif savedV2 then
        if savedV2.expires == 0 or unixTime() < savedV2.expires then
            isVIP, vipAccess = true, true
        end
    end
end

-- ================ World/Player handles ================
local player       = LocalPlayer
local events       = ReplicatedStorage:WaitForChild("Events")
local itemsEquiped = player:WaitForChild("PlayerScripts"):WaitForChild("ItemsEquiped")

-- ================ Feature state ================
local RunningTrapLoop  = false
local RunningPingLoop  = false
local speedValue       = 16
local speedLoopEnabled = false
local godmodeEnabled   = false
local levelLoopRunning = false
local espEnabled       = false
local MaintenanceMode  = false

local puzzleColor   = Color3.fromRGB(255, 255, 0)
local npcColor      = Color3.fromRGB(255, 0, 0)
local elevatorColor = Color3.fromRGB(0, 255, 0)

-- Keybinds
local trapToolKey  = "T"
local pingKey      = "P"
local speedCoilKey = "C"

-- ================ Character helpers ================
local function getPuzzleFolder()
    local puzzles = Workspace:FindFirstChild("Puzzle") and Workspace.Puzzle:FindFirstChild("Puzzles")
    if puzzles and #puzzles:GetChildren() == 1 and puzzles:FindFirstChild("ElevatorStuff") then
        local party = Workspace:FindFirstChild("Party")
        if party then return party end
    end
    return puzzles
end
local function getCharacter() return player.Character or player.CharacterAdded:Wait() end
local function getHumanoid() return getCharacter():WaitForChild("Humanoid") end
local function getHRP() return getCharacter():WaitForChild("HumanoidRootPart") end

-- ================ Features ================
local function unlockAllSuits()
    local suitSaves = player:FindFirstChild("SuitSaves")
    if suitSaves then
        for _, v in ipairs(suitSaves:GetChildren()) do
            if v:IsA("BoolValue") then v.Value = true end
        end
    end
end
local function updateLevelLoop()
    while levelLoopRunning do
        local stats = player:FindFirstChild("STATS")
        if stats then
            local level = stats:FindFirstChild("Level")
            if level and level:IsA("IntValue") then level.Value = 999 end
        end
        task.wait(1)
    end
end
local function teleportFaceToCFrame(targetCFrame)
    local hrp = getHRP(); if not hrp then return end
    local pos = targetCFrame.Position + Vector3.new(0, 3, 0)
    hrp.CFrame = CFrame.new(pos, targetCFrame.Position)
end
local function teleportToElevatorFloorFace()
    local elevator = Workspace:FindFirstChild("Elevators") and Workspace.Elevators:FindFirstChild("Level0Elevator")
    if not elevator then return end
    local floorPart = elevator:FindFirstChild("Floor")
    if not floorPart or not floorPart:IsA("BasePart") then return end
    teleportFaceToCFrame(floorPart.CFrame)
end
local function teleportToModel(model)
    if not model or not model:IsA("Model") then return end
    local pivot = model:GetPivot()
    local forward = pivot.LookVector
    local targetPos = pivot.Position - forward * 4 + Vector3.new(0, 3, 0)
    getHRP().CFrame = CFrame.new(targetPos, pivot.Position)
    camera.CameraType = Enum.CameraType.Custom
    camera.CameraSubject = getHumanoid()
end
local function simulateHoldPrompt(prompt, duration)
    if prompt and prompt:IsA("ProximityPrompt") then
        prompt:InputHoldBegin()
        task.wait(duration or 3.5)
        prompt:InputHoldEnd()
    end
end
local function findPromptInModel(model)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then return desc end
    end
    return nil
end
local function handleAllPuzzlePrompts()
    local puzzlesFolder = getPuzzleFolder()
    if not puzzlesFolder then return end
    for _, model in ipairs(puzzlesFolder:GetDescendants()) do
        if model:IsA("Model") then
            local pivot = model:GetPivot()
            teleportFaceToCFrame(pivot)
            task.wait(1)
            local prompt = findPromptInModel(model)
            if prompt then simulateHoldPrompt(prompt, 6); task.wait(1.5) end
        end
    end
end
local function teleportToFirstPuzzle()
    local puzzlesFolder = getPuzzleFolder()
    if not puzzlesFolder then return end
    for _, item in ipairs(puzzlesFolder:GetDescendants()) do
        if item:IsA("Model") then teleportToModel(item); break end
    end
end

-- ================ ESP ================
local beamFolder
local espObjects = {}
local function clearESP()
    if beamFolder then beamFolder:Destroy() end
    beamFolder = nil
    espObjects = {}
    RunService:UnbindFromRenderStep("ESPUpdate")
end
local function createESPBox(part, color)
    local adorn = Instance.new("BoxHandleAdornment")
    adorn.Adornee = part
    adorn.AlwaysOnTop = true
    adorn.ZIndex = 10
    adorn.Size = part.Size
    adorn.Transparency = 0.5
    adorn.Color3 = color or Color3.new(1,1,1)
    adorn.Parent = beamFolder
    return adorn
end
local function drawESP()
    clearESP()
    beamFolder = Instance.new("Folder", Workspace)
    beamFolder.Name = "BeamESPFolder"

    local function addESP(part, typ)
        local color = (typ == "Puzzle" and puzzleColor)
                   or (typ == "NPC" and npcColor)
                   or (typ == "Elevator" and elevatorColor)
                   or Color3.new(1,1,1)
        local box = createESPBox(part, color)
        if box then table.insert(espObjects, {part = part, box = box, type = typ}) end
    end

    local puzzlesFolder = getPuzzleFolder()
    if puzzlesFolder then
        for _, model in ipairs(puzzlesFolder:GetDescendants()) do
            if model:IsA("Model") then
                local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                if part then addESP(part, "Puzzle") end
            end
        end
    end

    local npcs = Workspace:FindFirstChild("NPCS")
    if npcs then
        for _, model in ipairs(npcs:GetChildren()) do
            if model:IsA("Model") then
                local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                if part then addESP(part, "NPC") end
            end
        end
    end

    local elevators = Workspace:FindFirstChild("Elevators")
    if elevators then
        local level0 = elevators:FindFirstChild("Level0Elevator")
        if level0 then
            for _, part in ipairs(level0:GetDescendants()) do
                if part:IsA("BasePart") then addESP(part, "Elevator") end
            end
        end
    end

    RunService:BindToRenderStep("ESPUpdate", 301, function()
        for i = #espObjects, 1, -1 do
            local obj = espObjects[i]
            local part, box = obj.part, obj.box
            if part and part.Parent and box then
                box.Adornee = part
                box.Size = part.Size
            else
                if box then box:Destroy() end
                table.remove(espObjects, i)
            end
        end
    end)
end
task.spawn(function()
    while true do
        if espEnabled then drawESP() else clearESP() end
        task.wait(1)
    end
end)

-- ================ Inventory/Items ================
local function forceDelete(name)
    for _, container in ipairs({player.Backpack, player.Character}) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") and item.Name == name then pcall(function() item:Destroy() end) end
            end
        end
    end
end
local function equipTool(name)
    local tool = player.Backpack:FindFirstChild(name)
    if tool and player.Character then pcall(function() tool.Parent = player.Character end) end
end

-- VIP actions (tools)
local function useTrapTool()
    if not vipAccess or MaintenanceMode then return end
    forceDelete("TrapTool")
    local trapFlag = itemsEquiped:FindFirstChild("Trap")
    if trapFlag then trapFlag.Value = false end
    local event = events:FindFirstChild("BearTrapEvent")
    if event then event:FireServer(player) end
    task.wait(0.3)
    equipTool("TrapTool")
end
local function usePing()
    if not vipAccess or MaintenanceMode then return end
    forceDelete("Ping")
    local pingFlag = itemsEquiped:FindFirstChild("Ping")
    if pingFlag then pingFlag.Value = false end
    local event = events:FindFirstChild("pingEvent")
    if event then event:FireServer() end
    task.wait(0.3)
    equipTool("Ping")
end
local function useSpeedCoil()
    if not vipAccess or MaintenanceMode then return end
    forceDelete("EnergyDrink")
    local drinkFlag = itemsEquiped:FindFirstChild("EnergyDrink")
    if drinkFlag then drinkFlag.Value = false end
    local event = events:FindFirstChild("SpeedCoilEvent")
    if event then event:FireServer({player}) end
    task.wait(0.3)
    equipTool("EnergyDrink")
end

-- Disable everything locally
local function DisableAllFeatures()
    espEnabled = false; clearESP()
    speedLoopEnabled = false
    RunningTrapLoop = false
    RunningPingLoop = false
    godmodeEnabled  = false
    pcall(function()
        if Rayfield and Rayfield.Flags then
            if Rayfield.Flags.GodmodeToggle then Rayfield.Flags.GodmodeToggle:Set(false) end
            if Rayfield.Flags.TrapLoop then Rayfield.Flags.TrapLoop:Set(false) end
            if Rayfield.Flags.PingLoop then Rayfield.Flags.PingLoop:Set(false) end
        end
    end)
end

-- Reload script to rebuild UI (used to remove VIP tabs cleanly)
local function RebuildWithoutVIP()
    DisableAllFeatures()
    pcall(function() loadstring(game:HttpGet(RELOAD_URL))() end)
end

-- ================ VIP saved key online check on start ================
local function validateSavedKeyOnlineIfAny()
    local raw = LoadVIP()
    if raw == "" then return end
    if raw == LEGACY_KEY then
        isVIP, vipAccess = true, true
        return
    end
    local v2 = parseV2Saved(raw)
    if not v2 or not v2.key then return end
    local ok, info = validateKeyOnline(v2.key)
    if ok then
        local newExp = tonumber(info.expires or v2.expires or 0) or 0
        local newUid = tonumber(info.userId or v2.userId or 0) or 0
        SaveVIP(("v2|%s|%d|%d"):format(v2.key, newExp, newUid))
        isVIP, vipAccess = true, true
    else
        isVIP, vipAccess = false, false
    end
end

-- ================ UI =================
local Window = Rayfield:CreateWindow({
    Name = "Game Hub",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "Made by @plet_farmyt",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local MainTab     = Window:CreateTab("Main", 4483362458)
local ItemsTab    = Window:CreateTab("Items", 4483362361)
local ESPTab      = Window:CreateTab("ESP", 4483362457)
local PlayerTab   = Window:CreateTab("Player", 4483362006)
local EmoteTab    = Window:CreateTab("Emote", 4483363000)
local SettingsTab = Window:CreateTab("Settings", 4483362706)
local VIPTab      = Window:CreateTab("VIP", 4483362458)

-- Forward declarations for VIP tabs
local KeybindsTab, ExploitsTab
local function createKeybindsTab() end
local function createExploitsTab() end

-- Main
MainTab:CreateButton({ Name = "Unlock All", Callback = function()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Unlock All is VIP-only.", Duration=4}); return end
    if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end
    unlockAllSuits()
    levelLoopRunning = true
    task.spawn(updateLevelLoop)
end })
MainTab:CreateButton({ Name = "Level Complete", Callback = function()
    if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end
    task.spawn(function() handleAllPuzzlePrompts(); task.wait(1); teleportToElevatorFloorFace() end)
end })
MainTab:CreateButton({ Name = "Teleport to Puzzle", Callback = function()
    if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end
    teleportToFirstPuzzle()
end })
MainTab:CreateButton({ Name = "Teleport to Elevator Floor", Callback = function()
    if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end
    teleportToElevatorFloorFace()
end })

-- Items (VIP-only)
ItemsTab:CreateButton({
    Name = "Medkit",
    Callback = function()
        if not vipAccess then Rayfield:Notify({ Title="VIP Only", Content="Items are VIP-only.", Duration=4 }); return end
        if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end
        events:WaitForChild("MedkitEvent"):FireServer({player})
    end
})
ItemsTab:CreateButton({
    Name = "Speed Coil",
    Callback = function()
        if not vipAccess then Rayfield:Notify({ Title="VIP Only", Content="Items are VIP-only.", Duration=4 }); return end
        if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end
        events:WaitForChild("SpeedCoilEvent"):FireServer({player})
    end
})
ItemsTab:CreateButton({
    Name = "Vest",
    Callback = function()
        if not vipAccess then Rayfield:Notify({ Title="VIP Only", Content="Items are VIP-only.", Duration=4 }); return end
        if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end
        events:WaitForChild("VestEvent"):FireServer({player})
    end
})

-- ESP
ESPTab:CreateToggle({
    Name = "Enable ESP",
    CurrentValue = false,
    Callback = function(state)
        if MaintenanceMode then
            Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4})
            espEnabled = false; clearESP(); return
        end
        espEnabled = state
    end,
})
ESPTab:CreateColorPicker({ Name = "Puzzle ESP Color",   Color = puzzleColor,   Callback = function(c) puzzleColor = c end })
ESPTab:CreateColorPicker({ Name = "NPC ESP Color",      Color = npcColor,      Callback = function(c) npcColor = c end })
ESPTab:CreateColorPicker({ Name = "Elevator ESP Color", Color = elevatorColor, Callback = function(c) elevatorColor = c end })

-- Player
PlayerTab:CreateToggle({
    Name = "WalkSpeed Loop", CurrentValue = false,
    Callback = function(state)
        if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); speedLoopEnabled=false; return end
        speedLoopEnabled = state
    end,
})
PlayerTab:CreateSlider({
    Name = "WalkSpeed", Range = {16, 80}, Increment = 1, CurrentValue = 16,
    Callback = function(val) speedValue = val end,
})
PlayerTab:CreateToggle({
    Name = "Godmode (VIP)",
    CurrentValue = false,
    Flag = "GodmodeToggle",
    Callback = function(state)
        if not vipAccess then
            Rayfield:Notify({ Title = "VIP Only", Content = "Godmode is VIP-only.", Duration = 4 })
            pcall(function() if Rayfield.Flags.GodmodeToggle then Rayfield.Flags.GodmodeToggle:Set(false) end end)
            return
        end
        if MaintenanceMode then
            Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4})
            pcall(function() if Rayfield.Flags.GodmodeToggle then Rayfield.Flags.GodmodeToggle:Set(false) end end)
            return
        end
        godmodeEnabled = state
    end,
})

-- Emote
EmoteTab:CreateButton({
    Name = "Show Emote Page 3",
    Callback = function()
        if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end
        local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
        local emoteGui = playerGui:FindFirstChild("Emoteui")
        if emoteGui then
            local container3 = emoteGui:FindFirstChild("container3")
            if container3 then container3.Visible = true else warn("container3 not found in Emoteui") end
        else warn("Emoteui not found in PlayerGui") end
    end,
})

-- Settings
SettingsTab:CreateParagraph({ Title = "Info", Content = "Script made by @plet_farmyt" })

-- Keybinds (VIP)
local function createKeybindsTab()
    if KeybindsTab then return end
    KeybindsTab = Window:CreateTab("Keybinds", 4483362706)
    local function refreshParagraph()
        KeybindsTab:CreateParagraph({
            Title = "Current Keybinds",
            Content = "TrapTool: " .. trapToolKey .. "\nPing: " .. pingKey .. "\nSpeed Coil: " .. speedCoilKey
        })
    end
    refreshParagraph()
    KeybindsTab:CreateInput({
        Name = "TrapTool Key", PlaceholderText = "Current: " .. trapToolKey, RemoveTextAfterFocusLost = true,
        Callback = function(Text) if Text ~= "" then trapToolKey = Text:upper(); Rayfield:Notify({ Title="Keybind", Content="TrapTool key set to "..trapToolKey, Duration=2 }); refreshParagraph() end end,
    })
    KeybindsTab:CreateInput({
        Name = "Ping Key", PlaceholderText = "Current: " .. pingKey, RemoveTextAfterFocusLost = true,
        Callback = function(Text) if Text ~= "" then pingKey = Text:upper(); Rayfield:Notify({ Title="Keybind", Content="Ping key set to "..pingKey, Duration=2 }); refreshParagraph() end end,
    })
    KeybindsTab:CreateInput({
        Name = "Speed Coil Key", PlaceholderText = "Current: " .. speedCoilKey, RemoveTextAfterFocusLost = true,
        Callback = function(Text) if Text ~= "" then speedCoilKey = Text:upper(); Rayfield:Notify({ Title="Keybind", Content="Speed Coil key set to "..speedCoilKey, Duration=2 }); refreshParagraph() end end,
    })
end

-- Exploits (VIP)
local function createExploitsTab()
    if ExploitsTab then return end
    ExploitsTab = Window:CreateTab("Exploits", 4483362360)

    ExploitsTab:CreateToggle({
        Name = "Trap Loop", CurrentValue = false, Flag = "TrapLoop",
        Callback = function(Value)
            if not vipAccess then
                Rayfield:Notify({ Title = "VIP Only", Content = "VIP-only.", Duration = 3 })
                pcall(function() if Rayfield.Flags.TrapLoop then Rayfield.Flags.TrapLoop:Set(false) end end)
                return
            end
            if MaintenanceMode then
                Rayfield:Notify({ Title="Maintenance", Content="Disabled during maintenance.", Duration=4 })
                pcall(function() if Rayfield.Flags.TrapLoop then Rayfield.Flags.TrapLoop:Set(false) end end)
                return
            end
            RunningTrapLoop = Value
            task.spawn(function()
                while RunningTrapLoop and vipAccess do
                    forceDelete("TrapTool")
                    local trapFlag = itemsEquiped:FindFirstChild("Trap"); if trapFlag then trapFlag.Value = false end
                    local event = events:FindFirstChild("BearTrapEvent"); if event then event:FireServer(player) end
                    local timeout, ticked = 1.5, 0
                    while RunningTrapLoop and not player.Backpack:FindFirstChild("TrapTool") and ticked < timeout do
                        task.wait(0.05); ticked = ticked + 0.05
                    end
                    equipTool("TrapTool")
                    task.wait(0.25)
                end
            end)
        end
    })
    ExploitsTab:CreateButton({ Name = "TrapTool Once", Callback = function() if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end useTrapTool() end })

    ExploitsTab:CreateToggle({
        Name = "Ping Loop", CurrentValue = false, Flag = "PingLoop",
        Callback = function(Value)
            if not vipAccess then
                Rayfield:Notify({ Title = "VIP Only", Content = "VIP-only.", Duration = 3 })
                pcall(function() if Rayfield.Flags.PingLoop then Rayfield.Flags.PingLoop:Set(false) end end)
                return
            end
            if MaintenanceMode then
                Rayfield:Notify({ Title="Maintenance", Content="Disabled during maintenance.", Duration=4 })
                pcall(function() if Rayfield.Flags.PingLoop then Rayfield.Flags.PingLoop:Set(false) end end)
                return
            end
            RunningPingLoop = Value
            task.spawn(function()
                while RunningPingLoop and vipAccess do
                    forceDelete("Ping")
                    local pingFlag = itemsEquiped:FindFirstChild("Ping"); if pingFlag then pingFlag.Value = false end
                    local event = events:FindFirstChild("pingEvent"); if event then event:FireServer() end
                    local timeout, ticked = 1.5, 0
                    while RunningPingLoop and not player.Backpack:FindFirstChild("Ping") and ticked < timeout do
                        task.wait(0.05); ticked = ticked + 0.05
                    end
                    equipTool("Ping")
                    task.wait(0.25)
                end
            end)
        end
    })
    ExploitsTab:CreateButton({ Name = "Ping Once",       Callback = function() if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end usePing() end })
    ExploitsTab:CreateButton({ Name = "Speed Coil Once", Callback = function() if MaintenanceMode then Rayfield:Notify({Title="Maintenance", Content="Disabled during maintenance.", Duration=4}); return end useSpeedCoil() end })
end

-- VIP input
VIPTab:CreateInput({
    Name = "Enter VIP Key",
    PlaceholderText = "Enter VIP Key",
    RemoveTextAfterFocusLost = false,
    Callback = function(Value)
        local key = (Value or ""):gsub("%s+", "")
        if key == "" then return end

        if key == LEGACY_KEY then
            Rayfield:Notify({ Title = "VIP", Content = "This key is deprecated and no longer accepted.", Duration = 6 })
            return
        end

        local ok, info = validateKeyOnline(key)
        if ok then
            local exp = tonumber(info.expires or 0) or 0
            local uid = tonumber(info.userId or 0) or 0
            SaveVIP(("v2|%s|%d|%d"):format(key, exp, uid))
            isVIP, vipAccess = true, true
            Rayfield:Notify({ Title = "VIP", Content = "VIP activated.", Duration = 4 })
            createExploitsTab()
            createKeybindsTab()
        else
            local reason = info
            local msg = "Invalid key."
            if reason == "Expired" then msg = "Key expired."
            elseif reason == "WrongUser" then msg = "Key is bound to another user."
            elseif reason == "Revoked" then msg = "Key revoked."
            elseif reason == "Network" then msg = "Network error while validating the key."
            end
            SafeSetClipboard(DISCORD_CONTACT)
            Rayfield:Notify({
                Title = "VIP",
                Content = msg .. " Discord name copied to clipboard. Contact: " .. DISCORD_CONTACT,
                Duration = 8
            })
        end
    end
})

-- If VIP already (from saved key) after online recheck
task.spawn(function()
    local was = vipAccess
    validateSavedKeyOnlineIfAny()
    if vipAccess and not was then
        createExploitsTab()
        createKeybindsTab()
    end
end)

-- ================ Guards / Pollers ================
-- VIP expiry + periodic online validation
task.spawn(function()
    local lastOnlineCheck = 0
    while true do
        local raw = LoadVIP()
        local v2  = parseV2Saved(raw)
        local now = unixTime()
        local stillVIP = false
        if raw == LEGACY_KEY then
            stillVIP = true
        elseif v2 then
            stillVIP = (v2.expires == 0 or now < v2.expires)
        end

        -- periodic online check for v2 (every 120s)
        if v2 and v2.key and (now - lastOnlineCheck) >= 120 then
            lastOnlineCheck = now
            local ok, info = validateKeyOnline(v2.key)
            if ok then
                local newExp = tonumber(info.expires or v2.expires or 0) or 0
                local newUid = tonumber(info.userId or v2.userId or 0) or 0
                if newExp ~= (v2.expires or 0) or newUid ~= (v2.userId or 0) then
                    SaveVIP(("v2|%s|%d|%d"):format(v2.key, newExp, newUid))
                end
                stillVIP = (newExp == 0 or now < newExp)
            else
                stillVIP = false
            end
        end

        if vipAccess ~= stillVIP then
            vipAccess = stillVIP
            isVIP = stillVIP
            if not vipAccess then
                RebuildWithoutVIP()
                return
            end
        end
        task.wait(15)
    end
end)

-- Broadcast + silent remote control (disable_all/reload/maintenance)
task.spawn(function()
    local lastTs = unixTime()
    while true do
        local url = string.format("%s/messages?since=%d&vip=%d", VIP_API_BASE, lastTs, vipAccess and 1 or 0)
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok then
            local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
            if ok2 and data and data.ok then
                for _, msg in ipairs(data.messages or {}) do
                    local createdAt = tonumber(msg.createdAt or 0) or 0
                    if msg.type == "control" then
                        local action = tostring(msg.action or "")
                        if action == "disable_all" then
                            DisableAllFeatures()
                        elseif action == "reload" then
                            local sUrl = tostring(msg.scriptUrl or RELOAD_URL)
                            pcall(function() loadstring(game:HttpGet(sUrl))() end)
                            return
                        elseif action == "maintenance_on" then
                            MaintenanceMode = true
                            DisableAllFeatures()
                        elseif action == "maintenance_off" then
                            MaintenanceMode = false
                        end
                    else
                        local ct = tostring(msg.text or "")
                        if ct ~= "" then
                            Rayfield:Notify({ Title = msg.vipOnly and "Broadcast (VIP)" or "Broadcast", Content = ct, Duration = 8 })
                        end
                    end
                    if createdAt > lastTs then lastTs = createdAt end
                end
            end
        end
        task.wait(10)
    end
end)

-- ================ Background loops ================
task.spawn(function()
    while true do
        if speedLoopEnabled and not MaintenanceMode then
            local hum = getHumanoid(); if hum then hum.WalkSpeed = speedValue end
        end
        task.wait(0.2)
    end
end)
task.spawn(function()
    while true do
        if godmodeEnabled and vipAccess and not MaintenanceMode then
            events:WaitForChild("VestEvent"):FireServer({player})
        end
        task.wait(0.7)
    end
end)

-- ================ Keybinds (VIP only) ================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or not vipAccess or MaintenanceMode then return end
    local keyPressed = input.KeyCode.Name
    if keyPressed == trapToolKey then
        useTrapTool()
    elseif keyPressed == pingKey then
        usePing()
    elseif keyPressed == speedCoilKey then
        useSpeedCoil()
    end
end)
