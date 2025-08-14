-- =======================
--  Game Hub + VIP (file + full validation)
--  VIP-only Items & Unlock All
--  VIP tabs (Exploits/Keybinds) auto-create when VIP active
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

-- UI lib
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- Services
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local LocalPlayer       = Players.LocalPlayer

-- ===================== Config =====================
local VIP_API_BASE        = "https://vip.pleyfarm11.workers.dev" -- твой сайт
local VIP_FILE            = "vipkey.txt"
local LEGACY_KEY          = "megvipmode" -- legacy допускается только если уже в файле
local DISCORD_CONTACT     = "plet_farm"
local OFFLINE_CHECK_EVERY = 30 -- сек: оффлайн-проверка истечения срока из файла
-- ==================================================

-- Base64 utils
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function encodeBase64(data)
    return ((data:gsub('.', function(x)
        local r,bits='',x:byte()
        for i=8,1,-1 do r=r..(bits%2^i-bits%2^(i-1)>0 and '1' or '0') end
        return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0; for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end
local function decodeBase64(data)
    data = (data or ""):gsub('[^'..b..']=*', '')
    return (data:gsub('.', function(x)
        if x=='=' then return '' end
        local r,f='',b:find(x)-1
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x~=8 then return '' end
        local c=0; for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

-- FS helpers
local function FileExists(path)
    local ok,_ = pcall(function() return readfile(path) end)
    return ok
end
local function ReadFile(path)
    local ok,res = pcall(function() return readfile(path) end)
    if ok and res then return res end
    return nil
end
local function WriteFile(path, content)
    pcall(function() writefile(path, content) end)
end
local function DeleteFile(path)
    pcall(function()
        if delfile then delfile(path) else writefile(path,"") end
    end)
end

-- VIP store helpers
local function SaveVIPRaw(raw) WriteFile(VIP_FILE, encodeBase64(raw)) end
local function LoadVIPRaw()
    local enc = ReadFile(VIP_FILE)
    if not enc or enc=="" then return "" end
    return decodeBase64(enc)
end
local function parseV2(raw)
    local p,k,e,u = string.match(raw or "", "^(v2)|([^|]+)|([^|]+)|([^|]+)$")
    if p=="v2" then return { key=k, expires=tonumber(e) or 0, userId=tonumber(u) or 0 } end
    return nil
end
local function now() return DateTime.now().UnixTimestamp end

-- Online validation
local function validateKeyOnline(key)
    local ok, body = pcall(function()
        local url = string.format("%s/validate?key=%s&uid=%d", VIP_API_BASE, HttpService:UrlEncode(key), Players.LocalPlayer.UserId)
        return game:HttpGet(url)
    end)
    if not ok then return false, "Network" end
    local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok2 then return false, "JSON" end
    if data.ok then return true, data.entry else return false, data.reason or "Unknown" end
end

-- VIP state
local vipAccess, isVIP = false, false
local function setVIP(v)
    vipAccess = v; isVIP = v
end

local function SafeSetClipboard(text) pcall(function() setclipboard(text) end) end

-- ============ VIP tabs (create on demand) ============
local KeybindsTab, ExploitsTab
local function createKeybindsTab()
    if KeybindsTab then return end
    if not vipAccess then return end
    KeybindsTab = Window:CreateTab("Keybinds", 4483362706)
    KeybindsTab:CreateParagraph({
        Title = "Current Keybinds",
        Content = "TrapTool: T\nPing: P\nSpeed Coil: C"
    })
end
local function createExploitsTab()
    if ExploitsTab then return end
    if not vipAccess then return end
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
    ExploitsTab:CreateButton({ Name = "TrapTool Once (VIP)",     Callback = function() if vipAccess then useTrapTool() end end })
    ExploitsTab:CreateButton({ Name = "Ping Once (VIP)",         Callback = function() if vipAccess then usePing() end end })
    ExploitsTab:CreateButton({ Name = "Speed Coil Once (VIP)",   Callback = function() if vipAccess then useSpeedCoilTool() end end })
end
local function ensureVIPTabs()
    if vipAccess then
        createExploitsTab()
        createKeybindsTab()
    end
end

-- Полная проверка файла: включаем VIP и создаём вкладки только при успехе
local function validateFileAndApplyVIP()
    if not FileExists(VIP_FILE) then setVIP(false) return false end
    local raw = LoadVIPRaw()
    if raw == "" then DeleteFile(VIP_FILE) setVIP(false) return false end

    if raw == LEGACY_KEY then
        setVIP(true)
        ensureVIPTabs()
        return true
    end

    local v2 = parseV2(raw)
    if not v2 or not v2.key then
        DeleteFile(VIP_FILE) setVIP(false) return false
    end

    if v2.expires ~= 0 and now() >= v2.expires then
        DeleteFile(VIP_FILE) setVIP(false) return false
    end

    local ok, infoOrReason = validateKeyOnline(v2.key)
    if not ok then
        local reason = infoOrReason
        if reason=="Expired" or reason=="NotFound" or reason=="Revoked" or reason=="WrongUser" then
            DeleteFile(VIP_FILE) setVIP(false) return false
        else
            -- Network/JSON: VIP не включаем, т.к. нужна полная проверка
            setVIP(false) return false
        end
    end

    local info = infoOrReason
    local newExp = tonumber(info.expires or v2.expires or 0) or 0
    local newUid = tonumber(info.userId or v2.userId or 0) or 0
    SaveVIPRaw(("v2|%s|%d|%d"):format(v2.key, newExp, newUid))
    setVIP(true)
    ensureVIPTabs()
    return true
end

-- Старт: строго валидируем файл, создаём VIP‑вкладки при успехе
validateFileAndApplyVIP()

-- Оффлайн-сторож (удаляет файл при наступлении expires)
task.spawn(function()
    while true do
        task.wait(OFFLINE_CHECK_EVERY)
        if FileExists(VIP_FILE) then
            local raw = LoadVIPRaw()
            if raw == "" then DeleteFile(VIP_FILE) setVIP(false)
            elseif raw ~= LEGACY_KEY then
                local v2 = parseV2(raw)
                if not v2 or not v2.key then DeleteFile(VIP_FILE) setVIP(false)
                else
                    if v2.expires ~= 0 and now() >= v2.expires then
                        DeleteFile(VIP_FILE) setVIP(false)
                    end
                end
            end
        else
            setVIP(false)
        end
    end
end)

-- ====== Gameplay/Features ======
local events = ReplicatedStorage:WaitForChild("Events")
local function getCharacter() return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() end
local function getHumanoid() return getCharacter():WaitForChild("Humanoid") end
local function getHRP() return getCharacter():WaitForChild("HumanoidRootPart") end

local levelLoopRunning = false
local function unlockAllSuits()
    local suitSaves = LocalPlayer:FindFirstChild("SuitSaves")
    if suitSaves then
        for _, v in ipairs(suitSaves:GetChildren()) do
            if v:IsA("BoolValue") then v.Value = true end
        end
    end
end
local function updateLevelLoop()
    while levelLoopRunning do
        local stats = LocalPlayer:FindFirstChild("STATS")
        if stats then
            local level = stats:FindFirstChild("Level")
            if level and level:IsA("IntValue") then level.Value = 999 end
        end
        task.wait(1)
    end
end

-- Teleports/Puzzles (сокращённо)
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
    local targetPos = pivot.Position - pivot.LookVector * 4 + Vector3.new(0,3,0)
    getHRP().CFrame = CFrame.new(targetPos, pivot.Position)
end
local function handleAllPuzzlePrompts()
    local folder = getPuzzleFolder()
    if not folder then return end
    for _, m in ipairs(folder:GetDescendants()) do
        if m:IsA("Model") then
            local pivot = m:GetPivot()
            teleportFaceToCFrame(pivot)
            task.wait(1)
            for _, d in ipairs(m:GetDescendants()) do
                if d:IsA("ProximityPrompt") then
                    d:InputHoldBegin()
                    task.wait(6)
                    d:InputHoldEnd()
                    break
                end
            end
            task.wait(1.5)
        end
    end
end
local function teleportToFirstPuzzle()
    local folder = getPuzzleFolder()
    if not folder then return end
    for _, item in ipairs(folder:GetDescendants()) do
        if item:IsA("Model") then teleportToModel(item); break end
    end
end

-- ESP
local beamFolder, espObjects = nil, {}
local puzzleColor   = Color3.fromRGB(255,255,0)
local npcColor      = Color3.fromRGB(255,0,0)
local elevatorColor = Color3.fromRGB(0,255,0)
local espEnabled    = false
local function clearESP()
    if beamFolder then beamFolder:Destroy() end
    beamFolder=nil; espObjects={}
    RunService:UnbindFromRenderStep("ESPUpdate")
end
local function createESPBox(part, color)
    local adorn = Instance.new("BoxHandleAdornment")
    adorn.Adornee = part; adorn.AlwaysOnTop = true; adorn.ZIndex = 10
    adorn.Size = part.Size; adorn.Transparency = 0.5; adorn.Color3 = color or Color3.new(1,1,1)
    adorn.Parent = beamFolder
    return adorn
end
local function drawESP()
    clearESP()
    beamFolder = Instance.new("Folder", Workspace); beamFolder.Name = "BeamESPFolder"
    local function addESP(part, typ)
        local color = (typ=="Puzzle" and puzzleColor) or (typ=="NPC" and npcColor) or (typ=="Elevator" and elevatorColor) or Color3.new(1,1,1)
        local box = createESPBox(part, color)
        if box then table.insert(espObjects, {part=part, box=box}) end
    end
    local folder = getPuzzleFolder()
    if folder then
        for _, m in ipairs(folder:GetDescendants()) do
            if m:IsA("Model") then
                local p = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                if p then addESP(p, "Puzzle") end
            end
        end
    end
    local npcs = Workspace:FindFirstChild("NPCS")
    if npcs then
        for _, m in ipairs(npcs:GetChildren()) do
            if m:IsA("Model") then
                local p = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                if p then addESP(p, "NPC") end
            end
        end
    end
    local elevators=Workspace:FindFirstChild("Elevators")
    local level0 = elevators and elevators:FindFirstChild("Level0Elevator")
    if level0 then
        for _, p in ipairs(level0:GetDescendants()) do
            if p:IsA("BasePart") then addESP(p, "Elevator") end
        end
    end
    RunService:BindToRenderStep("ESPUpdate", 301, function()
        for i=#espObjects,1,-1 do
            local o=espObjects[i]
            if o.part and o.part.Parent and o.box then
                o.box.Adornee=o.part; o.box.Size=o.part.Size
            else
                if o.box then o.box:Destroy() end
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

-- Items & Tools (VIP-only)
local itemsEquiped = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ItemsEquiped")
local function forceDelete(name)
    for _, c in ipairs({LocalPlayer.Backpack, LocalPlayer.Character}) do
        if c then for _, i in ipairs(c:GetChildren()) do if i:IsA("Tool") and i.Name==name then pcall(function() i:Destroy() end) end end end
    end
end
local function equipTool(name)
    local t = LocalPlayer.Backpack:FindFirstChild(name)
    if t and LocalPlayer.Character then pcall(function() t.Parent = LocalPlayer.Character end) end
end
local function useTrapTool()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}); return end
    forceDelete("TrapTool")
    local f = itemsEquiped:FindFirstChild("Trap"); if f then f.Value = false end
    local ev = ReplicatedStorage.Events:FindFirstChild("BearTrapEvent"); if ev then ev:FireServer(LocalPlayer) end
    task.wait(0.3) equipTool("TrapTool")
end
local function usePing()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}); return end
    forceDelete("Ping")
    local f = itemsEquiped:FindFirstChild("Ping"); if f then f.Value = false end
    local ev = ReplicatedStorage.Events:FindFirstChild("pingEvent"); if ev then ev:FireServer() end
    task.wait(0.3) equipTool("Ping")
end
local function useSpeedCoilTool()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}); return end
    forceDelete("EnergyDrink")
    local f = itemsEquiped:FindFirstChild("EnergyDrink"); if f then f.Value = false end
    local ev = ReplicatedStorage.Events:FindFirstChild("SpeedCoilEvent"); if ev then ev:FireServer({LocalPlayer}) end
    task.wait(0.3) equipTool("EnergyDrink")
end

-- Player toggles
local speedLoopEnabled=false; local speedValue=16; local godmodeEnabled=false
task.spawn(function()
    while true do
        if speedLoopEnabled then
            local hum=getHumanoid(); if hum then hum.WalkSpeed=speedValue end
        end
        task.wait(0.2)
    end
end)
task.spawn(function()
    while true do
        if godmodeEnabled and vipAccess then
            ReplicatedStorage:WaitForChild("Events"):WaitForChild("VestEvent"):FireServer({LocalPlayer})
        end
        task.wait(0.7)
    end
end)

-- UI
local Window = Rayfield:CreateWindow({
    Name = "Game Hub",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "Made by @plet_farmyt",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})
local MainTab   = Window:CreateTab("Main", 4483362458)
local ItemsTab  = Window:CreateTab("Items (VIP)", 4483362361)
local ESPTab    = Window:CreateTab("ESP", 4483362457)
local PlayerTab = Window:CreateTab("Player", 4483362006)
local VIPTab    = Window:CreateTab("VIP", 4483362458)

MainTab:CreateButton({ Name="Unlock All (VIP)", Callback=function()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Unlock All is VIP-only.", Duration=4}); return end
    unlockAllSuits(); levelLoopRunning=true; task.spawn(updateLevelLoop)
end })
MainTab:CreateButton({ Name="Level Complete", Callback=function() task.spawn(function() handleAllPuzzlePrompts(); task.wait(1); teleportToElevatorFloorFace() end) end })
MainTab:CreateButton({ Name="Teleport to Puzzle", Callback=teleportToFirstPuzzle })
MainTab:CreateButton({ Name="Teleport to Elevator Floor", Callback=teleportToElevatorFloorFace })

ItemsTab:CreateButton({ Name="Medkit (VIP)",     Callback=giveMedkit })
ItemsTab:CreateButton({ Name="Speed Coil (VIP)", Callback=giveSpeedCoil })
ItemsTab:CreateButton({ Name="Vest (VIP)",       Callback=giveVest })

ESPTab:CreateToggle({ Name="Enable ESP", CurrentValue=false, Callback=function(v) espEnabled=v end })
PlayerTab:CreateToggle({ Name="WalkSpeed Loop", CurrentValue=false, Callback=function(v) speedLoopEnabled=v end })
PlayerTab:CreateSlider({ Name="WalkSpeed", Range={16,80}, Increment=1, CurrentValue=16, Callback=function(v) speedValue=v end })
PlayerTab:CreateToggle({
    Name="Godmode (VIP)", CurrentValue=false,
    Callback=function(v)
        if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Godmode is VIP-only.", Duration=4}); return end
        godmodeEnabled=v
    end
})

-- VIP input
VIPTab:CreateInput({
    Name="Enter VIP Key",
    PlaceholderText="Enter VIP Key",
    RemoveTextAfterFocusLost=false,
    Callback=function(val)
        local key=(val or ""):gsub("%s+","")
        if key=="" then return end
        if key==LEGACY_KEY then
            Rayfield:Notify({ Title="VIP", Content="This key is deprecated and no longer accepted.", Duration=6 })
            return
        end
        local ok, infoOrReason = validateKeyOnline(key)
        if ok then
            local info=infoOrReason
            local exp=tonumber(info.expires or 0) or 0
            local uid=tonumber(info.userId or 0) or 0
            SaveVIPRaw(("v2|%s|%d|%d"):format(key, exp, uid))
            if validateFileAndApplyVIP() then
                Rayfield:Notify({ Title="VIP", Content="VIP activated.", Duration=4 })
            else
                Rayfield:Notify({ Title="VIP", Content="Failed to apply VIP from file.", Duration=6 })
            end
        else
            local reason=infoOrReason
            local msg="Invalid key."
            if reason=="Expired" then msg="Key expired."
            elseif reason=="WrongUser" then msg="Key is bound to another user."
            elseif reason=="Revoked" then msg="Key revoked."
            elseif reason=="Network" then msg="Network error while validating the key."
            end
            SafeSetClipboard(DISCORD_CONTACT)
            Rayfield:Notify({ Title="VIP", Content=msg..". Discord copied: "..DISCORD_CONTACT, Duration=8 })
        end
    end
})

-- Tool hotkeys (VIP-only)
UserInputService.InputBegan:Connect(function(input, gp)
    if gp or not vipAccess then return end
    local n=input.KeyCode.Name
    if n=="T" then useTrapTool()
    elseif n=="P" then usePing()
    elseif n=="C" then useSpeedCoilTool()
    end
end)

-- Если на старте VIP активен — сразу создаём вкладки
ensureVIPTabs()
