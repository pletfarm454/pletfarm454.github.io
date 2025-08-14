-- =======================
--  Game Hub + VIP (simplified, file-driven)
--  by @plet_farmyt
-- =======================

-- Destroy previous UI if exists
if getgenv().LoadedUI then
    getgenv().LoadedUI:Destroy()
end

-- UI container
getgenv().LoadedUI = Instance.new("ScreenGui")
getgenv().LoadedUI.Parent = game:GetService("CoreGui")
getgenv().LoadedUI.Name = "LoadedUI_Rayfield"

-- Lib
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

-- ===================== Config =====================
local VIP_API_BASE       = "https://vip.pleyfarm11.workers.dev" -- твой сайт
local LEGACY_KEY         = "megvipmode" -- принимается только если уже сохранен (в файле)
local VIP_FILE           = "vipkey.txt"
local DISCORD_CONTACT    = "plet_farm"
local OFFLINE_CHECK_EVERY= 30 -- сек, офлайн-проверка истечения срока (удаление файла)

-- ===================== Base64 utils =====================
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

-- ===================== FS helpers =====================
local function FileExists(path)
    local ok, _ = pcall(function() return readfile(path) end)
    return ok
end
local function ReadFile(path)
    local ok, res = pcall(function() return readfile(path) end)
    if ok and res then return res end
    return nil
end
local function WriteFile(path, content)
    pcall(function() writefile(path, content) end)
end
local function DeleteFile(path)
    pcall(function()
        if delfile then delfile(path) else writefile(path, "") end
    end)
end

-- ===================== VIP store =====================
-- Формат сохраняемого файла: "v2|<key>|<expires>|<userId>" или просто "megvipmode"
local function SaveVIPRaw(raw) WriteFile(VIP_FILE, encodeBase64(raw)) end
local function LoadVIPRaw()
    local enc = ReadFile(VIP_FILE)
    if not enc or enc == "" then return "" end
    return decodeBase64(enc)
end

local function parseV2(raw)
    local prefix, key, expStr, uidStr = string.match(raw or "", "^(v2)|([^|]+)|([^|]+)|([^|]+)$")
    if prefix == "v2" then
        return { key = key, expires = tonumber(expStr) or 0, userId = tonumber(uidStr) or 0 }
    end
    return nil
end

local function unixTime()
    return DateTime.now().UnixTimestamp
end

-- ===================== VIP logic (file-driven) =====================
local isVIP, vipAccess = false, false

local function SafeSetClipboard(text)
    pcall(function() setclipboard(text) end)
end

-- Онлайн проверка введенного ключа
local function validateKeyOnline(key)
    local ok, body = pcall(function()
        local url = string.format("%s/validate?key=%s&uid=%d",
            VIP_API_BASE, HttpService:UrlEncode(key), Players.LocalPlayer.UserId)
        return game:HttpGet(url)
    end)
    if not ok then return false, "Network" end
    local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok2 then return false, "JSON" end
    if data.ok then return true, data.entry else return false, data.reason or "Unknown" end
end

-- Применение статуса VIP (вкл/выкл) без перезапуска
local function DisableAllFeatures()
    -- здесь аккуратно выключаем все циклы/ESP/тогглы
    pcall(function() RunService:UnbindFromRenderStep("ESPUpdate") end)
    -- сброс глобальных флагов далее, когда они будут определены
end

local function applyVIPState(active)
    if active == vipAccess then return end
    vipAccess = active
    isVIP = active
    if not active then
        DisableAllFeatures()
        Rayfield:Notify({ Title = "VIP", Content = "VIP disabled.", Duration = 4 })
    else
        Rayfield:Notify({ Title = "VIP", Content = "VIP enabled.", Duration = 4 })
        -- вкладки Exploits / Keybinds будут созданы там, где мы их проверяем (если не существуют)
    end
end

-- На старте: читаем файл, если истек — удаляем, если валиден — включаем VIP.
local function initVIPFromFile()
    if not FileExists(VIP_FILE) then
        applyVIPState(false)
        return
    end
    local raw = LoadVIPRaw()
    if raw == "" then
        DeleteFile(VIP_FILE)
        applyVIPState(false)
        return
    end
    if raw == LEGACY_KEY then
        applyVIPState(true)
        return
    end
    local v2 = parseV2(raw)
    if not v2 or not v2.key then
        DeleteFile(VIP_FILE)
        applyVIPState(false)
        return
    end
    local now = unixTime()
    if v2.expires ~= 0 and now >= v2.expires then
        DeleteFile(VIP_FILE)
        applyVIPState(false)
        return
    end
    applyVIPState(true)
end

-- Офлайн-сторож: раз в OFFLINE_CHECK_EVERY секунд смотрит, не истек ли срок (по файлу)
task.spawn(function()
    while true do
        task.wait(OFFLINE_CHECK_EVERY)
        if FileExists(VIP_FILE) then
            local raw = LoadVIPRaw()
            if raw == "" then
                DeleteFile(VIP_FILE)
                applyVIPState(false)
            elseif raw == LEGACY_KEY then
                applyVIPState(true)
            else
                local v2 = parseV2(raw)
                if not v2 or not v2.key then
                    DeleteFile(VIP_FILE)
                    applyVIPState(false)
                else
                    local now = unixTime()
                    if v2.expires ~= 0 and now >= v2.expires then
                        DeleteFile(VIP_FILE)
                        applyVIPState(false)
                    else
                        applyVIPState(true)
                    end
                end
            end
        else
            applyVIPState(false)
        end
    end
end)

-- ===================== Gameplay/Features =====================
local player       = LocalPlayer
local events       = ReplicatedStorage:WaitForChild("Events")
local function getCharacter() return player.Character or player.CharacterAdded:Wait() end
local function getHumanoid()  return getCharacter():WaitForChild("Humanoid") end
local function getHRP()       return getCharacter():WaitForChild("HumanoidRootPart") end

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

-- Teleports & puzzles (как раньше)
local function getPuzzleFolder()
    local puzzles = Workspace:FindFirstChild("Puzzle") and Workspace.Puzzle:FindFirstChild("Puzzles")
    if puzzles and #puzzles:GetChildren() == 1 and puzzles:FindFirstChild("ElevatorStuff") then
        local party = Workspace:FindFirstChild("Party")
        if party then return party end
    end
    return puzzles
end
local function teleportFaceToCFrame(cf)
    local hrp = getHRP(); if not hrp then return end
    local pos = cf.Position + Vector3.new(0, 3, 0)
    hrp.CFrame = CFrame.new(pos, cf.Position)
end
local function teleportToElevatorFloorFace()
    local elevators = Workspace:FindFirstChild("Elevators")
    local elevator  = elevators and elevators:FindFirstChild("Level0Elevator")
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
local function findPromptInModel(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("ProximityPrompt") then return d end
    end
    return nil
end
local function simulateHoldPrompt(prompt, duration)
    if prompt and prompt:IsA("ProximityPrompt") then
        prompt:InputHoldBegin()
        task.wait(duration or 3.5)
        prompt:InputHoldEnd()
    end
end
local function handleAllPuzzlePrompts()
    local folder = getPuzzleFolder()
    if not folder then return end
    for _, m in ipairs(folder:GetDescendants()) do
        if m:IsA("Model") then
            local pivot = m:GetPivot()
            teleportFaceToCFrame(pivot)
            task.wait(1)
            local prompt = findPromptInModel(m)
            if prompt then
                simulateHoldPrompt(prompt, 6)
                task.wait(1.5)
            end
        end
    end
end
local function teleportToFirstPuzzle()
    local folder = getPuzzleFolder()
    if not folder then return end
    for _, item in ipairs(folder:GetDescendants()) do
        if item:IsA("Model") then
            teleportToModel(item)
            break
        end
    end
end

-- ESP
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
    beamFolder = Instance.new("Folder", Workspace); beamFolder.Name = "BeamESPFolder"
    local function addESP(part, typ)
        local color = (typ == "Puzzle" and puzzleColor) or (typ == "NPC" and npcColor) or (typ == "Elevator" and elevatorColor) or Color3.new(1,1,1)
        local box = createESPBox(part, color)
        if box then table.insert(espObjects, {part=part, box=box, type=typ}) end
    end
    local folder = getPuzzleFolder()
    if folder then
        for _, m in ipairs(folder:GetDescendants()) do
            if m:IsA("Model") then
                local part = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                if part then addESP(part, "Puzzle") end
            end
        end
    end
    local npcs = Workspace:FindFirstChild("NPCS")
    if npcs then
        for _, m in ipairs(npcs:GetChildren()) do
            if m:IsA("Model") then
                local part = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                if part then addESP(part, "NPC") end
            end
        end
    end
    local elevators = Workspace:FindFirstChild("Elevators")
    local level0 = elevators and elevators:FindFirstChild("Level0Elevator")
    if level0 then
        for _, part in ipairs(level0:GetDescendants()) do
            if part:IsA("BasePart") then addESP(part, "Elevator") end
        end
    end
    RunService:BindToRenderStep("ESPUpdate", 301, function()
        for i=#espObjects,1,-1 do
            local obj = espObjects[i]
            if obj.part and obj.part.Parent and obj.box then
                obj.box.Adornee = obj.part
                obj.box.Size = obj.part.Size
            else
                if obj.box then obj.box:Destroy() end
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

-- Tools/Items (VIP only)
local function forceDelete(name)
    for _, container in ipairs({player.Backpack, player.Character}) do
        if container then
            for _, itm in ipairs(container:GetChildren()) do
                if itm:IsA("Tool") and itm.Name == name then pcall(function() itm:Destroy() end) end
            end
        end
    end
end
local function equipTool(name)
    local tool = player.Backpack:FindFirstChild(name)
    if tool and player.Character then pcall(function() tool.Parent = player.Character end) end
end

local itemsEquiped = player:WaitForChild("PlayerScripts"):WaitForChild("ItemsEquiped")
local function useTrapTool()
    if not vipAccess or MaintenanceMode then return end
    forceDelete("TrapTool")
    local f = itemsEquiped:FindFirstChild("Trap"); if f then f.Value = false end
    local ev = ReplicatedStorage.Events:FindFirstChild("BearTrapEvent"); if ev then ev:FireServer(player) end
    task.wait(0.3); equipTool("TrapTool")
end
local function usePing()
    if not vipAccess or MaintenanceMode then return end
    forceDelete("Ping")
    local f = itemsEquiped:FindFirstChild("Ping"); if f then f.Value = false end
    local ev = ReplicatedStorage.Events:FindFirstChild("pingEvent"); if ev then ev:FireServer() end
    task.wait(0.3); equipTool("Ping")
end
local function useSpeedCoil()
    if not vipAccess or MaintenanceMode then return end
    forceDelete("EnergyDrink")
    local f = itemsEquiped:FindFirstChild("EnergyDrink"); if f then f.Value = false end
    local ev = ReplicatedStorage.Events:FindFirstChild("SpeedCoilEvent"); if ev then ev:FireServer({player}) end
    task.wait(0.3); equipTool("EnergyDrink")
end

-- ===================== UI =====================
local Window = Rayfield:CreateWindow({
    Name = "Game Hub",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "Made by @plet_farmyt",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local MainTab     = Window:CreateTab("Main", 4483362458)
local ItemsTab    = Window:CreateTab("Items (VIP)", 4483362361)
local ESPTab      = Window:CreateTab("ESP", 4483362457)
local PlayerTab   = Window:CreateTab("Player", 4483362006)
local EmoteTab    = Window:CreateTab("Emote", 4483363000)
local SettingsTab = Window:CreateTab("Settings", 4483362706)
local VIPTab      = Window:CreateTab("VIP", 4483362458)

local KeybindsTab, ExploitsTab
local function createKeybindsTab()
    if KeybindsTab or not vipAccess then return end
    KeybindsTab = Window:CreateTab("Keybinds", 4483362706)
    KeybindsTab:CreateParagraph({
        Title = "Current Keybinds",
        Content = "TrapTool: T\nPing: P\nSpeed Coil: C"
    })
end
local function createExploitsTab()
    if ExploitsTab or not vipAccess then return end
    ExploitsTab = Window:CreateTab("Exploits", 4483362360)
    ExploitsTab:CreateToggle({
        Name = "Trap Loop (VIP)",
        CurrentValue = false,
        Callback = function(v)
            if not vipAccess then return end
            RunningTrapLoop = v
            task.spawn(function()
                while RunningTrapLoop and vipAccess do
                    useTrapTool()
                    task.wait(0.25)
                end
            end)
        end
    })
    ExploitsTab:CreateToggle({
        Name = "Ping Loop (VIP)",
        CurrentValue = false,
        Callback = function(v)
            if not vipAccess then return end
            RunningPingLoop = v
            task.spawn(function()
                while RunningPingLoop and vipAccess do
                    usePing()
                    task.wait(0.25)
                end
            end)
        end
    })
    ExploitsTab:CreateButton({ Name = "TrapTool Once (VIP)", Callback = function() if vipAccess then useTrapTool() end end })
    ExploitsTab:CreateButton({ Name = "Ping Once (VIP)",     Callback = function() if vipAccess then usePing() end end })
    ExploitsTab:CreateButton({ Name = "Speed Coil Once (VIP)", Callback = function() if vipAccess then useSpeedCoil() end end })
end

-- Main
MainTab:CreateButton({ Name = "Unlock All (VIP)", Callback = function()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Unlock All is VIP-only.", Duration=4}); return end
    unlockAllSuits(); levelLoopRunning = true; task.spawn(updateLevelLoop)
end })
MainTab:CreateButton({ Name = "Level Complete", Callback = function()
    task.spawn(function() handleAllPuzzlePrompts(); task.wait(1); teleportToElevatorFloorFace() end)
end })
MainTab:CreateButton({ Name = "Teleport to Puzzle",          Callback = teleportToFirstPuzzle })
MainTab:CreateButton({ Name = "Teleport to Elevator Floor",  Callback = teleportToElevatorFloorFace })

-- Items (VIP-only)
ItemsTab:CreateButton({
    Name = "Medkit (VIP)",
    Callback = function()
        if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Items are VIP-only.", Duration=4}); return end
        ReplicatedStorage:WaitForChild("Events"):WaitForChild("MedkitEvent"):FireServer({LocalPlayer})
    end
})
ItemsTab:CreateButton({
    Name = "Speed Coil (VIP)",
    Callback = function()
        if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Items are VIP-only.", Duration=4}); return end
        ReplicatedStorage:WaitForChild("Events"):WaitForChild("SpeedCoilEvent"):FireServer({LocalPlayer})
    end
})
ItemsTab:CreateButton({
    Name = "Vest (VIP)",
    Callback = function()
        if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Items are VIP-only.", Duration=4}); return end
        ReplicatedStorage:WaitForChild("Events"):WaitForChild("VestEvent"):FireServer({LocalPlayer})
    end
})

-- ESP
ESPTab:CreateToggle({
    Name = "Enable ESP",
    CurrentValue = false,
    Callback = function(st) espEnabled = st end
})
ESPTab:CreateColorPicker({ Name="Puzzle ESP Color",   Color=puzzleColor,   Callback=function(c) puzzleColor=c end })
ESPTab:CreateColorPicker({ Name="NPC ESP Color",      Color=npcColor,      Callback=function(c) npcColor=c end })
ESPTab:CreateColorPicker({ Name="Elevator ESP Color", Color=elevatorColor, Callback=function(c) elevatorColor=c end })

-- Player
PlayerTab:CreateToggle({
    Name = "WalkSpeed Loop",
    CurrentValue = false,
    Callback = function(st) speedLoopEnabled = st end
})
PlayerTab:CreateSlider({
    Name = "WalkSpeed",
    Range = {16, 80},
    Increment = 1,
    CurrentValue = 16,
    Callback = function(v) speedValue = v end
})
PlayerTab:CreateToggle({
    Name = "Godmode (VIP)",
    CurrentValue = false,
    Callback = function(st)
        if not vipAccess then
            Rayfield:Notify({Title="VIP Only", Content="Godmode is VIP-only.", Duration=4})
            return
        end
        godmodeEnabled = st
    end
})

-- Emote
EmoteTab:CreateButton({
    Name = "Show Emote Page 3",
    Callback = function()
        local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
        local emoteGui  = playerGui:FindFirstChild("Emoteui")
        if emoteGui then
            local container3 = emoteGui:FindFirstChild("container3")
            if container3 then container3.Visible = true else warn("container3 not found in Emoteui") end
        else warn("Emoteui not found in PlayerGui") end
    end
})

-- Settings
SettingsTab:CreateParagraph({ Title="Info", Content="Script made by @plet_farmyt" })

-- VIP input
VIPTab:CreateInput({
    Name = "Enter VIP Key",
    PlaceholderText = "Enter VIP Key",
    RemoveTextAfterFocusLost = false,
    Callback = function(value)
        local key = (value or ""):gsub("%s+", "")
        if key == "" then return end
        if key == LEGACY_KEY then
            Rayfield:Notify({ Title = "VIP", Content = "This key is deprecated and no longer accepted.", Duration = 6 })
            return
        end
        local ok, info = validateKeyOnline(key)
        if ok then
            local exp = tonumber(info.expires or 0) or 0
            local uid = tonumber(info.userId or 0) or 0
            -- Сохраняем ТОЛЬКО если валиден
            SaveVIPRaw(("v2|%s|%d|%d"):format(key, exp, uid))
            applyVIPState(true)
            createExploitsTab()
            createKeybindsTab()
            Rayfield:Notify({ Title = "VIP", Content = "VIP activated.", Duration = 4 })
        else
            local reason = info
            local msg = "Invalid key."
            if reason == "Expired" then msg = "Key expired."
            elseif reason == "WrongUser" then msg = "Key is bound to another user."
            elseif reason == "Revoked" then msg = "Key revoked."
            elseif reason == "Network" then msg = "Network error while validating the key."
            end
            -- НЕ сохраняем файл при неверном ключе
            SafeSetClipboard(DISCORD_CONTACT)
            Rayfield:Notify({
                Title = "VIP",
                Content = msg .. " Discord copied to clipboard: " .. DISCORD_CONTACT,
                Duration = 8
            })
        end
    end
})

-- ===================== Loops =====================
-- WalkSpeed
task.spawn(function()
    while true do
        if speedLoopEnabled then
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = speedValue end
        end
        task.wait(0.2)
    end
end)

-- Godmode
task.spawn(function()
    while true do
        if godmodeEnabled and vipAccess then
            ReplicatedStorage:WaitForChild("Events"):WaitForChild("VestEvent"):FireServer({LocalPlayer})
        end
        task.wait(0.7)
    end
end)

-- Keybinds (VIP only)
UserInputService.InputBegan:Connect(function(input, gp)
    if gp or not vipAccess then return end
    local name = input.KeyCode.Name
    if name == "T" then useTrapTool()
    elseif name == "P" then usePing()
    elseif name == "C" then useSpeedCoil()
    end
end)

-- Старт: применяем VIP из файла и, если нужно, создаем вкладки
initVIPFromFile()
if vipAccess then
    createExploitsTab()
    createKeybindsTab()
end
