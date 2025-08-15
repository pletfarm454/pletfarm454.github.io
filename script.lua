-- =======================
--  Game Hub (stable) + VIP + fireAllEvents
--  - VIP таб первый, Exploits/Keybinds видны всем (действия VIP-гейт)
--  - AutoFarm Loop в Main вызывает fireAllEvents() с задержкой
--  - Change Lvl (VIP) в Exploits вызывает fireAllEvents() разово
--  - Стабильные FS-хелперы, корректная работа без файла ключа
--  - ESP событийная, онлайн-счётчик через Worker (/presence, /online)
--  - Quick Actions через Worker (/messages)
-- =======================

if not game:IsLoaded() then game.Loaded:Wait() end

-- Cleanup предыдущего запуска
pcall(function()
    if getgenv().PletMaid and getgenv().PletMaid.Cleanup then
        getgenv().PletMaid:Cleanup()
    end
end)
if getgenv().LoadedUI then pcall(function() getgenv().LoadedUI:Destroy() end) end
getgenv().PletRunId = (getgenv().PletRunId or 0) + 1
local RUN_ID = getgenv().PletRunId
local function Alive() return RUN_ID == (getgenv().PletRunId or RUN_ID) end

-- Maid
local Maid = { _list = {} }
function Maid:Give(x) table.insert(self._list, x); return x end
function Maid:Cleanup()
    for i = #self._list, 1, -1 do
        local t = self._list[i]
        if typeof(t) == "RBXScriptConnection" then pcall(function() t:Disconnect() end)
        elseif type(t) == "function" then pcall(t) end
        self._list[i] = nil
    end
end
getgenv().PletMaid = Maid

-- Services
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local LocalPlayer       = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- UI parent
local function getUiParent()
    if gethui then local ok, ui = pcall(gethui); if ok and ui then return ui end end
    return game:GetService("CoreGui")
end

-- UI container
getgenv().LoadedUI = Instance.new("ScreenGui")
getgenv().LoadedUI.Name = "LoadedUI_Rayfield"
getgenv().LoadedUI.ResetOnSpawn = false
getgenv().LoadedUI.IgnoreGuiInset = true
getgenv().LoadedUI.Parent = getUiParent()

-- Load Rayfield c fallback
local function loadRayfield()
    local urls = {
        "https://sirius.menu/rayfield",
        "https://raw.githubusercontent.com/shlexware/Rayfield/main/source"
    }
    for _, u in ipairs(urls) do
        local ok, lib = pcall(function() return loadstring(game:HttpGet(u))() end)
        if ok and type(lib) == "table" and lib.CreateWindow then return lib end
    end
    return nil
end
local Rayfield = loadRayfield()
if not Rayfield then
    warn("[Hub] Rayfield UI failed to load.")
    local lbl = Instance.new("TextLabel")
    lbl.Text = "Rayfield UI failed to load. Enable HTTP or try later."
    lbl.Size = UDim2.new(1,0,0,40)
    lbl.BackgroundTransparency = 0.3
    lbl.BackgroundColor3 = Color3.fromRGB(50,50,50)
    lbl.Parent = getgenv().LoadedUI
    return
end

-- Config
local VIP_API_BASE        = "https://vip.pleyfarm11.workers.dev"
local VIP_FILE            = "vipkey.txt"
local CFG_FILE            = "plet_hub_config.json"
local LEGACY_KEY          = "megvipmode"
local DISCORD_CONTACT     = "plet_farm"
local OFFLINE_CHECK_EVERY = 30
local PRESENCE_PING_EVERY = 30
local ONLINE_POLL_EVERY   = 15
local MSG_POLL_EVERY      = 3

-- Time
local function now()
    local ok, ts = pcall(function() return DateTime.now().UnixTimestamp end)
    return ok and ts or os.time()
end

-- Base64 (tight)
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function encB64(data)
    return ((data:gsub('.', function(x)
        local r,n='',x:byte(); for i=8,1,-1 do r=r..(n%2^i-n%2^(i-1)>0 and '1' or '0') end; return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(bits)
        if #bits<6 then return '' end
        local c=0; for i=1,6 do c=c+(bits:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end
local function decB64(data)
    data = tostring(data or ''):gsub('[^%w%+/%=]', '')
    return (data:gsub('.', function(x)
        if x=='=' then return '' end
        local r,f='',b:find(x)-1
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(bits)
        if #bits~=8 then return '' end
        local c=0; for i=1,8 do c=c+(bits:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

-- FS helpers (robust)
local function FileExists(path)
    if typeof(isfile) == "function" then
        local ok, v = pcall(isfile, path)
        if ok then return v and true or false end
    end
    if typeof(readfile) ~= "function" then return false end
    local ok, res = pcall(readfile, path)
    if not ok then return false end
    return type(res) == "string" and #res > 0
end
local function ReadFile(path)
    if typeof(readfile) ~= "function" then return nil end
    local ok, res = pcall(readfile, path)
    if ok and type(res) == "string" then return res end
    return nil
end
local function WriteFile(path, content)
    if typeof(writefile) ~= "function" then return end
    pcall(writefile, path, content or "")
end
local function DeleteFile(path)
    if typeof(delfile) == "function" then pcall(delfile, path) return end
    if typeof(isfile) == "function" and typeof(writefile) == "function" then
        local ok, v = pcall(isfile, path)
        if ok and v then pcall(writefile, path, "") end
    end
end

-- Config store
local function LoadConfig()
    local ok,res = pcall(function() return readfile(CFG_FILE) end)
    if ok and res then
        local ok2, cfg = pcall(function() return HttpService:JSONDecode(res) end)
        if ok2 and type(cfg)=="table" then return cfg end
    end
    return {}
end
local function SaveConfig(cfg)
    if typeof(writefile) == "function" then
        pcall(function() writefile(CFG_FILE, HttpService:JSONEncode(cfg)) end)
    end
end
local Config = LoadConfig()
Config.trapKey  = (type(Config.trapKey )=="string" and #Config.trapKey >0) and Config.trapKey  or "T"
Config.pingKey  = (type(Config.pingKey )=="string" and #Config.pingKey >0) and Config.pingKey  or "P"
Config.coilKey  = (type(Config.coilKey )=="string" and #Config.coilKey >0) and Config.coilKey  or "C"
Config.panicKey = (type(Config.panicKey)=="string" and #Config.panicKey>0) and Config.panicKey or "L"

-- Color helpers
local function Color3ToHex(c)
    local function to255(x) return math.clamp(math.floor((x or 0)*255 + 0.5), 0, 255) end
    return string.format("#%02X%02X%02X", to255(c.R), to255(c.G), to255(c.B))
end
local function HexToColor3(hex)
    hex = tostring(hex or ""):gsub("#","")
    if #hex ~= 6 then return nil end
    local r = tonumber(hex:sub(1,2),16)
    local g = tonumber(hex:sub(3,4),16)
    local b = tonumber(hex:sub(5,6),16)
    if not r or not g or not b then return nil end
    return Color3.fromRGB(r,g,b)
end
Config.espColors = (type(Config.espColors)=="table") and Config.espColors or {}
Config.espColors.puzzle   = (type(Config.espColors.puzzle)=="string"   and #Config.espColors.puzzle  >0) and Config.espColors.puzzle   or "#FFFF00"
Config.espColors.npc      = (type(Config.espColors.npc)=="string"      and #Config.espColors.npc     >0) and Config.espColors.npc      or "#FF0000"
Config.espColors.elevator = (type(Config.espColors.elevator)=="string" and #Config.espColors.elevator>0) and Config.espColors.elevator  or "#00FF00"

-- VIP
local function validateKeyOnline(key)
    local ok, body = pcall(function()
        local url = string.format("%s/validate?key=%s&uid=%d", VIP_API_BASE, HttpService:UrlEncode(key), Players.LocalPlayer.UserId)
        return game:HttpGet(url)
    end)
    if not ok then return false, "Network" end
    local ok2,data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok2 then return false, "JSON" end
    if data.ok then return true, data.entry end
    return false, data.reason or "Unknown"
end
local vipAccess, isVIP = false, false
local function setVIP(v) vipAccess=v; isVIP=v end
local function SaveVIPRaw(raw) WriteFile(VIP_FILE, encB64(raw)) end
local function LoadVIPRaw()
    if not FileExists(VIP_FILE) then return "" end
    local enc = ReadFile(VIP_FILE)
    if not enc or enc=="" then return "" end
    local ok, dec = pcall(decB64, enc)
    if ok and type(dec)=="string" then return dec end
    return ""
end
local function parseV2(raw)
    local p,k,e,u = string.match(raw or '', "^(v2)|([^|]+)|([^|]+)|([^|]+)$")
    if p=="v2" then return { key=k, expires=tonumber(e) or 0, userId=tonumber(u) or 0 } end
    return nil
end
local function SafeSetClipboard(t) pcall(function() setclipboard(t) end) end

local function validateFileAndApplyVIP()
    if not FileExists(VIP_FILE) then setVIP(false); return false end
    local raw = LoadVIPRaw()
    if raw=="" then DeleteFile(VIP_FILE); setVIP(false); return false end
    if raw==LEGACY_KEY then setVIP(true); return true end
    local v2 = parseV2(raw)
    if not v2 or not v2.key then DeleteFile(VIP_FILE); setVIP(false); return false end
    if v2.expires~=0 and now()>=v2.expires then DeleteFile(VIP_FILE); setVIP(false); return false end
    local ok, infoOrReason = validateKeyOnline(v2.key)
    if not ok then
        local r=infoOrReason
        if r=="Expired" or r=="NotFound" or r=="Revoked" or r=="WrongUser" then
            DeleteFile(VIP_FILE); setVIP(false); return false
        else
            setVIP(false); return false
        end
    end
    local info = infoOrReason
    local newExp = tonumber(info.expires or v2.expires or 0) or 0
    local newUid = tonumber(info.userId or v2.userId or 0) or 0
    SaveVIPRaw(("v2|%s|%d|%d"):format(v2.key, newExp, newUid))
    setVIP(true)
    return true
end

-- VIP offline watcher
task.spawn(function()
    local myId = RUN_ID
    while Alive() and myId==RUN_ID do
        task.wait(OFFLINE_CHECK_EVERY)
        if not Alive() then break end
        if FileExists(VIP_FILE) then
            local raw = LoadVIPRaw()
            if raw=="" then DeleteFile(VIP_FILE); setVIP(false)
            elseif raw~=LEGACY_KEY then
                local v2 = parseV2(raw)
                if not v2 or not v2.key then DeleteFile(VIP_FILE); setVIP(false)
                elseif v2.expires~=0 and now()>=v2.expires then DeleteFile(VIP_FILE); setVIP(false) end
            end
        else
            setVIP(false)
        end
    end
end)

-- Helpers
local function getCharacter() return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() end
local function getHumanoid() return getCharacter():FindFirstChildOfClass("Humanoid") or getCharacter():WaitForChild("Humanoid") end
local function waitChild(parent, name, timeout)
    timeout = timeout or 5
    local ok, obj = pcall(function() return parent:WaitForChild(name, timeout) end)
    if ok then return obj end
    return nil
end

-- ===== fireAllEvents (используется в AutoFarm/ChangeLvl) =====
local function fireAllEvents()
    local ev = waitChild(ReplicatedStorage, "Events", 5)
    pcall(function() local r=waitChild(ReplicatedStorage,"computerOff",3); if r then r:FireServer() end end)
    pcall(function() local r=ev and waitChild(ev,"GradeStuff",3);        if r then r:FireServer() end end)
    pcall(function() local r=ev and waitChild(ev,"LevelPickEvent",3);     if r then r:FireServer() end end)
    pcall(function() local r=ev and waitChild(ev,"LevelOpt1Picked",3);    if r then r:FireServer() end end)
    pcall(function() local r=waitChild(ReplicatedStorage,"OpenElevator",3); if r then r:FireServer() end end)
    pcall(function() local r=waitChild(ReplicatedStorage,"computerOn",3); if r then r:FireServer() end end)
end

-- Items/Tools (VIP-only)
local function getEvents() return ReplicatedStorage:FindFirstChild("Events") or waitChild(ReplicatedStorage,"Events",5) end
local function getItemsEquiped() local ps=LocalPlayer:FindFirstChild("PlayerScripts") or waitChild(LocalPlayer,"PlayerScripts",5); return ps and ps:FindFirstChild("ItemsEquiped") or nil end
local function forceDelete(name)
    for _, c in ipairs({LocalPlayer.Backpack, LocalPlayer.Character}) do
        if c then for _, i in ipairs(c:GetChildren()) do if i:IsA("Tool") and i.Name==name then pcall(function() i:Destroy() end) end end end
    end
end
local function equipTool(name)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local char = LocalPlayer.Character
    if not bp or not char then return end
    local tool = bp:FindFirstChild(name)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if tool and hum then pcall(function() hum:EquipTool(tool) end) end
end
local function useTrapTool()
    if not isVIP then Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}); return end
    local evs=getEvents(); if not evs then return end
    forceDelete("TrapTool")
    local eq=getItemsEquiped(); if eq then local f=eq:FindFirstChild("Trap"); if f then f.Value=false end end
    local ev=evs:FindFirstChild("BearTrapEvent"); if ev then ev:FireServer(LocalPlayer) end
    task.wait(0.25) equipTool("TrapTool")
end
local function usePing()
    if not isVIP then Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}); return end
    local evs=getEvents(); if not evs then return end
    forceDelete("Ping")
    local eq=getItemsEquiped(); if eq then local f=eq:FindFirstChild("Ping"); if f then f.Value=false end end
    local ev=evs:FindFirstChild("pingEvent"); if ev then ev:FireServer() end
    task.wait(0.25) equipTool("Ping")
end
local function useSpeedCoilTool()
    if not isVIP then Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}); return end
    local evs=getEvents(); if not evs then return end
    forceDelete("EnergyDrink")
    local eq=getItemsEquiped(); if eq then local f=eq:FindFirstChild("EnergyDrink"); if f then f.Value=false end end
    local ev=evs:FindFirstChild("SpeedCoilEvent"); if ev then ev:FireServer({LocalPlayer}) end
    task.wait(0.25) equipTool("EnergyDrink")
end
local function giveMedkit()
    if not isVIP then Rayfield:Notify({Title="VIP Only", Content="Items are VIP-only.", Duration=4}); return end
    local evs=getEvents(); if not evs then return end
    evs:WaitForChild("MedkitEvent"):FireServer({LocalPlayer})
end
local function giveSpeedCoil()
    if not isVIP then Rayfield:Notify({Title="VIP Only", Content="Items are VIP-only.", Duration=4}); return end
    local evs=getEvents(); if not evs then return end
    evs:WaitForChild("SpeedCoilEvent"):FireServer({LocalPlayer})
end
local function giveVest()
    if not isVIP then Rayfield:Notify({Title="VIP Only", Content="Items are VIP-only.", Duration=4}); return end
    local evs=getEvents(); if not evs then return end
    evs:WaitForChild("VestEvent"):FireServer({LocalPlayer})
end

-- ESP (event-driven)
local espEnabled=false
local beamFolder=nil
local espObjects = {} -- [BasePart] = BoxHandleAdornment
local watchers = {}   -- connections

local puzzleColor   = HexToColor3(Config.espColors.puzzle)   or Color3.fromRGB(255,255,0)
local npcColor      = HexToColor3(Config.espColors.npc)      or Color3.fromRGB(255,0,0)
local elevatorColor = HexToColor3(Config.espColors.elevator) or Color3.fromRGB(0,255,0)

local function cleanupWatchers()
    for _,c in ipairs(watchers) do pcall(function() c:Disconnect() end) end
    watchers = {}
end
local function clearESP()
    cleanupWatchers()
    for _, box in pairs(espObjects) do pcall(function() box:Destroy() end) end
    espObjects = {}
    if beamFolder then pcall(function() beamFolder:Destroy() end) end
    beamFolder=nil
    pcall(function() RunService:UnbindFromRenderStep("ESPUpdate") end)
end
local function addESPForPart(part, color)
    if not part or not part:IsA("BasePart") then return end
    if espObjects[part] then return end
    if not beamFolder then beamFolder=Instance.new("Folder"); beamFolder.Name="BeamESPFolder"; beamFolder.Parent=Workspace end
    local ad=Instance.new("BoxHandleAdornment")
    ad.Adornee=part; ad.AlwaysOnTop=true; ad.ZIndex=10; ad.Size=part.Size; ad.Transparency=0.5; ad.Color3=color; ad.Parent=beamFolder
    espObjects[part]=ad
    table.insert(watchers, part.AncestryChanged:Connect(function()
        if not part:IsDescendantOf(game) then
            local box=espObjects[part]; if box then pcall(function() box:Destroy() end) end
            espObjects[part]=nil
        end
    end))
end
local function addESPForModel(model, color)
    if not model or not model:IsA("Model") then return end
    local p = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if p then addESPForPart(p, color) end
end
local function drawESP()
    clearESP()
    if not espEnabled then return end
    beamFolder=Instance.new("Folder"); beamFolder.Name="BeamESPFolder"; beamFolder.Parent=Workspace

    local puzzles = Workspace:FindFirstChild("Puzzle") and Workspace.Puzzle:FindFirstChild("Puzzles")
    if puzzles then
        for _,m in ipairs(puzzles:GetDescendants()) do if m:IsA("Model") then addESPForModel(m, puzzleColor) end end
        table.insert(watchers, puzzles.DescendantAdded:Connect(function(inst)
            if not espEnabled then return end
            local mdl = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
            if mdl then addESPForModel(mdl, puzzleColor) end
        end))
    end

    local npcs = Workspace:FindFirstChild("NPCS")
    if npcs then
        for _,m in ipairs(npcs:GetChildren()) do if m:IsA("Model") then addESPForModel(m, npcColor) end end
        table.insert(watchers, npcs.ChildAdded:Connect(function(ch)
            if not espEnabled then return end
            if ch:IsA("Model") then addESPForModel(ch, npcColor) end
        end))
    end

    local elevators = Workspace:FindFirstChild("Elevators")
    local level0 = elevators and elevators:FindFirstChild("Level0Elevator")
    if level0 then
        for _,p in ipairs(level0:GetDescendants()) do if p:IsA("BasePart") then addESPForPart(p, elevatorColor) end end
        table.insert(watchers, level0.DescendantAdded:Connect(function(inst)
            if not espEnabled then return end
            if inst:IsA("BasePart") then addESPForPart(inst, elevatorColor) end
        end))
    end

    RunService:BindToRenderStep("ESPUpdate", 301, function()
        for part, box in pairs(espObjects) do
            if part and part.Parent and box and box.Parent then
                box.Adornee=part; box.Size=part.Size
            else
                if box then pcall(function() box:Destroy() end) end
                espObjects[part]=nil
            end
        end
    end)
end

-- Loops
local speedLoopEnabled=false
local speedValue=16
local godmodeEnabled=false
local RunningTrapLoop=false
local RunningPingLoop=false
local AutoFarmEnabled=false

task.spawn(function()
    local myId=RUN_ID
    while Alive() and myId==RUN_ID do
        if speedLoopEnabled then local h=getHumanoid(); if h then h.WalkSpeed=speedValue end end
        task.wait(0.2)
    end
end)
task.spawn(function()
    local myId=RUN_ID
    while Alive() and myId==RUN_ID do
        if godmodeEnabled and isVIP then local evs=getEvents(); if evs then evs:WaitForChild("VestEvent"):FireServer({LocalPlayer}) end end
        task.wait(0.7)
    end
end)

-- Window (VIP first)
local Window = Rayfield:CreateWindow({
    Name="Game Hub",
    LoadingTitle="Loading...",
    LoadingSubtitle="Made by @plet_farmyt",
    ConfigurationSaving={Enabled=false},
    KeySystem=false
})
local VIPTab      = Window:CreateTab("VIP", 4483362458)
local MainTab     = Window:CreateTab("Main", 4483362458)
local ItemsTab    = Window:CreateTab("Items (VIP)", 4483362361)
local ESPTab      = Window:CreateTab("ESP", 4483362457)
local PlayerTab   = Window:CreateTab("Player", 4483362006)
local KeybindsTab = Window:CreateTab("Keybinds", 4483362706)
local ExploitsTab = Window:CreateTab("Exploits", 4483362360)

-- Paragraph helper (онлайн)
_G.__plet_online_para = nil

-- Main
MainTab:CreateButton({
    Name="Unlock All",
    Callback=function()
        local ss = LocalPlayer:FindFirstChild("SuitSaves")
        if ss then for _,v in ipairs(ss:GetChildren()) do if v:IsA("BoolValue") then v.Value=true end end end
    end
})
_G.__plet_online_para = MainTab:CreateParagraph({ Title="Online", Content="VIP: 0 | Free: 0 | Total: 0" })
MainTab:CreateToggle({
    Name="AutoFarm Loop (Events)",
    CurrentValue=false,
    Callback=function(v)
        AutoFarmEnabled = v
        if v then
            task.spawn(function()
                local myId=RUN_ID
                while AutoFarmEnabled and Alive() and myId==RUN_ID do
                    fireAllEvents()
                    task.wait(0.5)
                end
            end)
        end
    end
})

-- Items
ItemsTab:CreateButton({ Name="Medkit (VIP)",     Callback=giveMedkit })
ItemsTab:CreateButton({ Name="Speed Coil (VIP)", Callback=giveSpeedCoil })
ItemsTab:CreateButton({ Name="Vest (VIP)",       Callback=giveVest })

-- ESP UI
ESPTab:CreateToggle({ Name="Enable ESP", CurrentValue=false, Callback=function(v) espEnabled=v; if v then drawESP() else clearESP() end end })
ESPTab:CreateParagraph({ Title="ESP Colors", Content="Customize and saved to config." })
ESPTab:CreateColorPicker({ Name="Puzzle Color", Color=puzzleColor, Callback=function(c) puzzleColor=c; Config.espColors.puzzle=Color3ToHex(c); SaveConfig(Config); if espEnabled then drawESP() end end })
ESPTab:CreateColorPicker({ Name="NPC Color", Color=npcColor, Callback=function(c) npcColor=c; Config.espColors.npc=Color3ToHex(c); SaveConfig(Config); if espEnabled then drawESP() end end })
ESPTab:CreateColorPicker({ Name="Elevator Color", Color=elevatorColor, Callback=function(c) elevatorColor=c; Config.espColors.elevator=Color3ToHex(c); SaveConfig(Config); if espEnabled then drawESP() end end })
ESPTab:CreateButton({ Name="Reset ESP Colors", Callback=function() puzzleColor=Color3.fromRGB(255,255,0); npcColor=Color3.fromRGB(255,0,0); elevatorColor=Color3.fromRGB(0,255,0); Config.espColors.puzzle="#FFFF00"; Config.espColors.npc="#FF0000"; Config.espColors.elevator="#00FF00"; SaveConfig(Config); if espEnabled then drawESP() end; Rayfield:Notify({Title="ESP", Content="Colors reset.", Duration=3}) end })

-- Player
PlayerTab:CreateToggle({ Name="WalkSpeed Loop", CurrentValue=false, Callback=function(v) speedLoopEnabled=v end })
PlayerTab:CreateSlider({ Name="WalkSpeed", Range={16,80}, Increment=1, CurrentValue=16, Callback=function(v) speedValue=v end })
PlayerTab:CreateToggle({ Name="Godmode (VIP)", CurrentValue=false, Callback=function(v) if not isVIP then Rayfield:Notify({Title="VIP Only", Content="Godmode is VIP-only.", Duration=3}) return end; godmodeEnabled=v end })

-- Keybinds
local bindsPara
local function refreshBinds()
    local text = ("Trap: %s\nPing: %s\nCoil: %s\nPanic: %s"):format(Config.trapKey, Config.pingKey, Config.coilKey, Config.panicKey)
    if bindsPara then pcall(function() bindsPara:Destroy() end) end
    bindsPara = KeybindsTab:CreateParagraph({ Title="Current Binds", Content=text })
end
refreshBinds()
KeybindsTab:CreateParagraph({ Title="Info", Content="Tab is visible for all; actions require VIP." })
KeybindsTab:CreateInput({ Name="Trap key", PlaceholderText="Current: "..Config.trapKey, RemoveTextAfterFocusLost=true, Callback=function(t) if t~='' then Config.trapKey=t:upper(); SaveConfig(Config); refreshBinds() end end })
KeybindsTab:CreateInput({ Name="Ping key", PlaceholderText="Current: "..Config.pingKey, RemoveTextAfterFocusLost=true, Callback=function(t) if t~='' then Config.pingKey=t:upper(); SaveConfig(Config); refreshBinds() end end })
KeybindsTab:CreateInput({ Name="Coil key", PlaceholderText="Current: "..Config.coilKey, RemoveTextAfterFocusLost=true, Callback=function(t) if t~='' then Config.coilKey=t:upper(); SaveConfig(Config); refreshBinds() end end })
KeybindsTab:CreateInput({ Name="Panic key", PlaceholderText="Current: "..Config.panicKey, RemoveTextAfterFocusLost=true, Callback=function(t) if t~='' then Config.panicKey=t:upper(); SaveConfig(Config); refreshBinds() end end })

-- Exploits
ExploitsTab:CreateParagraph({ Title="Info", Content="Visible for all; actions are VIP-only." })
ExploitsTab:CreateToggle({
    Name="Trap Loop (VIP)", CurrentValue=false,
    Callback=function(v)
        if not isVIP then Rayfield:Notify({Title="VIP Only", Content="Trap loop is VIP-only.", Duration=3}) return end
        RunningTrapLoop=v
        task.spawn(function()
            local myId=RUN_ID
            while RunningTrapLoop and isVIP and Alive() and myId==RUN_ID do
                useTrapTool()
                task.wait(0.25)
            end
        end)
    end
})
ExploitsTab:CreateToggle({
    Name="Ping Loop (VIP)", CurrentValue=false,
    Callback=function(v)
        if not isVIP then Rayfield:Notify({Title="VIP Only", Content="Ping loop is VIP-only.", Duration=3}) return end
        RunningPingLoop=v
        task.spawn(function()
            local myId=RUN_ID
            while RunningPingLoop and isVIP and Alive() and myId==RUN_ID do
                usePing()
                task.wait(0.25)
            end
        end)
    end
})
ExploitsTab:CreateButton({ Name="Trap Once (VIP)", Callback=function() if isVIP then useTrapTool() else Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}) end end })
ExploitsTab:CreateButton({ Name="Ping Once (VIP)", Callback=function() if isVIP then usePing() else Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}) end end })
ExploitsTab:CreateButton({ Name="Coil Once (VIP)", Callback=function() if isVIP then useSpeedCoilTool() else Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}) end end })
ExploitsTab:CreateButton({
    Name="Change Lvl (VIP)",
    Callback=function()
        if not isVIP then Rayfield:Notify({Title="VIP Only", Content="This action is VIP-only.", Duration=3}) return end
        fireAllEvents()
        Rayfield:Notify({Title="Level", Content="Change Lvl events triggered.", Duration=3})
    end
})

-- VIP tab: ввод ключа + удаление файла
VIPTab:CreateInput({
    Name="Enter VIP Key",
    PlaceholderText="Enter VIP Key",
    RemoveTextAfterFocusLost=false,
    Callback=function(val)
        local key=(val or ''):gsub('%s+',''):upper()
        if key=='' then return end
        if key==LEGACY_KEY then Rayfield:Notify({Title="VIP", Content="Legacy key not accepted.", Duration=5}); return end
        local httpOK, body = pcall(function()
            local url = string.format("%s/validate?key=%s&uid=%d", VIP_API_BASE, HttpService:UrlEncode(key), Players.LocalPlayer.UserId)
            return game:HttpGet(url)
        end)
        if not httpOK then Rayfield:Notify({Title="VIP", Content="Network error (HttpGet failed).", Duration=6}); return end
        local okJ, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not okJ then Rayfield:Notify({Title="VIP", Content="Server returned non-JSON.", Duration=6}); return end
        if data and data.ok then
            local exp=tonumber(data.entry and data.entry.expires or 0) or 0
            local uid=tonumber(data.entry and data.entry.userId or 0) or 0
            SaveVIPRaw(("v2|%s|%d|%d"):format(key, exp, uid))
            setVIP(true)
            Rayfield:Notify({Title="VIP", Content="VIP activated.", Duration=4})
        else
            local r = tostring(data and data.reason or "Unknown")
            local msg="Invalid key."
            if r=="Expired" then msg="Key expired." elseif r=="WrongUser" then msg="Key bound to another user." elseif r=="Revoked" then msg="Key revoked." elseif r=="NotFound" then msg="Key not found." end
            Rayfield:Notify({Title="VIP", Content=msg, Duration=6})
        end
    end
})
VIPTab:CreateButton({
    Name="Delete VIP file",
    Callback=function()
        if FileExists(VIP_FILE) then DeleteFile(VIP_FILE) end
        setVIP(false)
        Rayfield:Notify({Title="VIP", Content="VIP file deleted.", Duration=3})
    end
})

-- Panic
local function Panic()
    espEnabled=false; pcall(clearESP)
    speedLoopEnabled=false; godmodeEnabled=false
    RunningTrapLoop=false; RunningPingLoop=false
    AutoFarmEnabled=false
    Maid:Cleanup()
    Rayfield:Notify({Title="Panic", Content="All features disabled.", Duration=4})
end

-- Hotkeys
Maid:Give(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    local k=input.KeyCode.Name
    if k==Config.panicKey then Panic(); return end
    if not isVIP then return end
    if k==Config.trapKey then useTrapTool()
    elseif k==Config.pingKey then usePing()
    elseif k==Config.coilKey then useSpeedCoilTool()
    end
end))

-- Presence + Online
local function presencePingLoop()
    task.spawn(function()
        local myId=RUN_ID
        while Alive() and myId==RUN_ID do
            local url = string.format("%s/presence?uid=%d&vip=%d&place=%d&server=%s&name=%s&dname=%s",
                VIP_API_BASE,
                tonumber(LocalPlayer.UserId) or 0,
                (isVIP and 1 or 0),
                tonumber(game.PlaceId) or 0,
                HttpService:UrlEncode(tostring(game.JobId or "")),
                HttpService:UrlEncode(tostring(LocalPlayer.Name or "")),
                HttpService:UrlEncode(tostring(LocalPlayer.DisplayName or ""))
            )
            pcall(function() game:HttpGet(url) end)
            for i=1,PRESENCE_PING_EVERY do if not Alive() or myId~=RUN_ID then return end; task.wait(1) end
        end
    end)
end
local function onlinePollLoop()
    task.spawn(function()
        local myId=RUN_ID
        while Alive() and myId==RUN_ID do
            local ok, body = pcall(function() return game:HttpGet(VIP_API_BASE.."/online") end)
            if ok then
                local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
                if ok2 and data and data.ok then
                    local vipCount = tonumber(data.vip or 0) or 0
                    local total    = tonumber(data.total or 0) or 0
                    local free     = tonumber(data.free or 0) or (total - vipCount)
                    local content = string.format("VIP: %d | Free: %d | Total: %d", vipCount, free, total)
                    local para=_G.__plet_online_para
                    if para and para.Set then
                        pcall(function() para:Set({Title="Online", Content=content}) end)
                    else
                        _G.__plet_online_para = MainTab:CreateParagraph({ Title="Online", Content=content })
                    end
                end
            end
            for i=1,ONLINE_POLL_EVERY do if not Alive() or myId~=RUN_ID then return end; task.wait(1) end
        end
    end)
end

-- Messages (Quick Actions)
local seenMsg = {}
local lastSince = 0
local DEFAULT_RELOAD = "https://raw.githubusercontent.com/pletfarm454/scripts/main/script.lua"

local function applyControl(msg)
    local action = tostring(msg.action or "")
    local vipOnly = (msg.vipOnly == true)
    if vipOnly and not isVIP then return end

    if action == "disable_all" then
        Panic()
        return
    elseif action == "reload" then
        local url = tostring(msg.scriptUrl or DEFAULT_RELOAD)
        task.spawn(function()
            local ok, src = pcall(function() return game:HttpGet(url) end)
            if ok and type(src)=="string" then
                Panic()
                pcall(function() loadstring(src)() end)
            else
                Rayfield:Notify({Title="Reload", Content="Failed to reload script.", Duration=4})
            end
        end)
        return
    elseif action == "notify" then
        local title = tostring(msg.title or "Notice")
        local text  = tostring(msg.text or "")
        Rayfield:Notify({Title=title, Content=text, Duration=5})
        return
    elseif action == "ws" then
        local v = tonumber(msg.value) or 16
        speedValue = math.clamp(v, 8, 200)
        local h = getHumanoid()
        if h then pcall(function() h.WalkSpeed = speedValue end) end
        Rayfield:Notify({Title="WalkSpeed", Content=("Set to %d"):format(speedValue), Duration=3})
        return
    elseif action == "speedloop_on" then
        speedLoopEnabled = true
        Rayfield:Notify({Title="Speed Loop", Content="ON", Duration=3})
        return
    elseif action == "speedloop_off" then
        speedLoopEnabled = false
        Rayfield:Notify({Title="Speed Loop", Content="OFF", Duration=3})
        return
    elseif action == "godmode_on" then
        if isVIP then godmodeEnabled = true; Rayfield:Notify({Title="Godmode", Content="ON", Duration=3})
        else Rayfield:Notify({Title="VIP Only", Content="Godmode is VIP-only.", Duration=3}) end
        return
    elseif action == "godmode_off" then
        godmodeEnabled = false
        Rayfield:Notify({Title="Godmode", Content="OFF", Duration=3})
        return
    elseif action == "esp_on" then
        espEnabled = true; drawESP()
        Rayfield:Notify({Title="ESP", Content="ON", Duration=3})
        return
    elseif action == "esp_off" then
        espEnabled = false; clearESP()
        Rayfield:Notify({Title="ESP", Content="OFF", Duration=3})
        return
    elseif action == "tool_once" then
        local tool = tostring(msg.tool or "")
        if tool=="trap" then useTrapTool()
        elseif tool=="ping" then usePing()
        elseif tool=="coil" then useSpeedCoilTool()
        end
        return
    elseif action == "set_bind" then
        local bind = tostring(msg.bind or "")
        local key  = tostring(msg.keyname or msg.key or ""):upper()
        if key ~= "" then
            if bind=="trap" then Config.trapKey = key
            elseif bind=="ping" then Config.pingKey = key
            elseif bind=="coil" then Config.coilKey = key
            end
            SaveConfig(Config); refreshBinds()
            Rayfield:Notify({Title="Bind", Content=("Set %s -> %s"):format(bind, key), Duration=3})
        end
        return
    elseif action == "set_panic" then
        local key = tostring(msg.keyname or msg.key or ""):upper()
        if key ~= "" then
            Config.panicKey = key
            SaveConfig(Config); refreshBinds()
            Rayfield:Notify({Title="Panic", Content=("Set Panic -> %s"):format(key), Duration=3})
        end
        return
    elseif action == "vip_revalidate" then
        validateFileAndApplyVIP()
        Rayfield:Notify({Title="VIP", Content="Revalidated.", Duration=3})
        return
    elseif action == "vip_delete_file" then
        if FileExists(VIP_FILE) then DeleteFile(VIP_FILE) end
        setVIP(false)
        Rayfield:Notify({Title="VIP", Content="VIP file deleted.", Duration=3})
        return
    else
        -- неизвестное действие — просто игнор
        return
    end
end

local function applyMessage(msg)
    -- дедуп по id
    local id = tostring(msg.id or "")
    if id ~= "" then
        if seenMsg[id] then return end
        seenMsg[id] = true
    end

    if tostring(msg.type or "") == "broadcast" then
        local title = tostring(msg.title or "Broadcast")
        local text  = tostring(msg.text or "")
        Rayfield:Notify({Title=title, Content=text, Duration=5})
        return
    elseif tostring(msg.type or "") == "control" then
        applyControl(msg)
        return
    end
end

local function messagesPollLoop()
    task.spawn(function()
        local myId = RUN_ID
        while Alive() and myId == RUN_ID do
            local url = string.format("%s/messages?since=%d&vip=%d", VIP_API_BASE, math.max(0, lastSince - 1), (isVIP and 1 or 0))
            local ok, body = pcall(function() return game:HttpGet(url) end)
            if ok then
                local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
                if ok2 and data and data.ok and type(data.messages)=="table" then
                    for _, m in ipairs(data.messages) do
                        local ts = tonumber(m.createdAt or 0) or 0
                        if ts > lastSince then lastSince = ts end
                        applyMessage(m)
                    end
                end
            end
            for i=1,MSG_POLL_EVERY do if not Alive() or myId~=RUN_ID then return end; task.wait(1) end
        end
    end)
end

-- Start
validateFileAndApplyVIP()
presencePingLoop()
onlinePollLoop()
messagesPollLoop()
