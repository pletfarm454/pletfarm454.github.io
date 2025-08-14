-- =======================
--  Game Hub + VIP (file + full validation)
--  VIP tabs + configurable binds + panic + ESP color picker + WIP note
--  by @plet_farmyt
-- =======================

if getgenv().LoadedUI then
    getgenv().LoadedUI:Destroy()
end

-- UI container + Rayfield
getgenv().LoadedUI = Instance.new("ScreenGui")
getgenv().LoadedUI.Parent = game:GetService("CoreGui")
getgenv().LoadedUI.Name = "LoadedUI_Rayfield"
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- Services
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local LocalPlayer       = Players.LocalPlayer

-- Config
local VIP_API_BASE        = "https://vip.pleyfarm11.workers.dev"
local VIP_FILE            = "vipkey.txt"
local CFG_FILE            = "plet_hub_config.json"   -- бинды + цвета ESP
local LEGACY_KEY          = "megvipmode"
local DISCORD_CONTACT     = "plet_farm"
local OFFLINE_CHECK_EVERY = 30

-- Base64
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function encB64(data)
    return ((data:gsub('.', function(x)
        local r,n='',x:byte()
        for i=8,1,-1 do r=r..(n%2^i-n%2^(i-1)>0 and '1' or '0') end
        return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(bits)
        if #bits<6 then return '' end
        local c=0; for i=1,6 do c=c+(bits:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end
local function decB64(data)
    data = tostring(data or ''):gsub('[^'..b..']=*','')
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
local function WriteFile(path, content) pcall(function() writefile(path, content) end) end
local function DeleteFile(path) pcall(function() if delfile then delfile(path) else writefile(path,'') end end) end

-- VIP store
local function SaveVIPRaw(raw) WriteFile(VIP_FILE, encB64(raw)) end
local function LoadVIPRaw()
    local enc = ReadFile(VIP_FILE)
    if not enc or enc=='' then return '' end
    return decB64(enc)
end
local function parseV2(raw)
    local p,k,e,u = string.match(raw or '', "^(v2)|([^|]+)|([^|]+)|([^|]+)$")
    if p=='v2' then return { key=k, expires=tonumber(e) or 0, userId=tonumber(u) or 0 } end
    return nil
end
local function now() return DateTime.now().UnixTimestamp end

-- Config (binds) store
local function LoadConfig()
    local ok,res = pcall(function() return readfile(CFG_FILE) end)
    if ok and res then
        local ok2, cfg = pcall(function() return HttpService:JSONDecode(res) end)
        if ok2 and type(cfg)=="table" then return cfg end
    end
    return {}
end
local function SaveConfig(cfg) pcall(function() writefile(CFG_FILE, HttpService:JSONEncode(cfg)) end) end
local Config = LoadConfig()
-- defaults
Config.trapKey  = (type(Config.trapKey )=="string" and #Config.trapKey >0) and Config.trapKey  or "T"
Config.pingKey  = (type(Config.pingKey )=="string" and #Config.pingKey >0) and Config.pingKey  or "P"
Config.coilKey  = (type(Config.coilKey )=="string" and #Config.coilKey >0) and Config.coilKey  or "C"
Config.panicKey = (type(Config.panicKey)=="string" and #Config.panicKey>0) and Config.panicKey or "L"

-- Color helpers for config
local function Color3ToHex(c)
    local function to255(x) return math.clamp(math.floor((x or 0)*255 + 0.5), 0, 255) end
    return string.format("#%02X%02X%02X", to255(c.R), to255(c.G), to255(c.B))
end
local function HexToColor3(hex)
    hex = tostring(hex or ""):gsub("#","")
    if #hex ~= 6 then return nil end
    local r = tonumber(hex:sub(1,2), 16)
    local g = tonumber(hex:sub(3,4), 16)
    local b = tonumber(hex:sub(5,6), 16)
    if not r or not g or not b then return nil end
    return Color3.fromRGB(r, g, b)
end

-- ESP color defaults in config
Config.espColors = (type(Config.espColors) == "table") and Config.espColors or {}
Config.espColors.puzzle   = (type(Config.espColors.puzzle) == "string"   and #Config.espColors.puzzle   > 0) and Config.espColors.puzzle   or "#FFFF00"
Config.espColors.npc      = (type(Config.espColors.npc) == "string"      and #Config.espColors.npc      > 0) and Config.espColors.npc      or "#FF0000"
Config.espColors.elevator = (type(Config.espColors.elevator) == "string" and #Config.espColors.elevator > 0) and Config.espColors.elevator or "#00FF00"
-- Optionally persist new color defaults if first run
-- SaveConfig(Config)

-- Online validation
local function validateKeyOnline(key)
    local ok, body = pcall(function()
        local url = string.format("%s/validate?key=%s&uid=%d", VIP_API_BASE, HttpService:UrlEncode(key), Players.LocalPlayer.UserId)
        return game:HttpGet(url)
    end)
    if not ok then return false, "Network" end
    local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok2 then return false, "JSON" end
    if data.ok then return true, data.entry end
    return false, data.reason or "Unknown"
end

-- VIP state
local vipAccess, isVIP = false, false
local function setVIP(v) vipAccess=v; isVIP=v end
local function SafeSetClipboard(t) pcall(function() setclipboard(t) end) end

-- Lazy getters
local function getEvents(timeout)
    local ev = ReplicatedStorage:FindFirstChild("Events")
    if ev then return ev end
    local ok,res = pcall(function() return ReplicatedStorage:WaitForChild("Events", timeout or 5) end)
    return ok and res or nil
end
local function getItemsEquiped(timeout)
    local ps = LocalPlayer:FindFirstChild("PlayerScripts") or (pcall(function() return LocalPlayer:WaitForChild("PlayerScripts", timeout or 5) end) and LocalPlayer:FindFirstChild("PlayerScripts"))
    if not ps then return nil end
    return ps:FindFirstChild("ItemsEquiped")
end

-- Validate file and apply VIP (strict)
local function validateFileAndApplyVIP()
    if not FileExists(VIP_FILE) then setVIP(false) return false end
    local raw = LoadVIPRaw()
    if raw=='' then DeleteFile(VIP_FILE) setVIP(false) return false end

    if raw==LEGACY_KEY then
        setVIP(true); return true
    end
    local v2 = parseV2(raw)
    if not v2 or not v2.key then DeleteFile(VIP_FILE) setVIP(false) return false end
    if v2.expires~=0 and now()>=v2.expires then DeleteFile(VIP_FILE) setVIP(false) return false end

    local ok, infoOrReason = validateKeyOnline(v2.key)
    if not ok then
        local r=infoOrReason
        if r=="Expired" or r=="NotFound" or r=="Revoked" or r=="WrongUser" then
            DeleteFile(VIP_FILE) setVIP(false) return false
        else
            setVIP(false) return false
        end
    end
    local info=infoOrReason
    local newExp=tonumber(info.expires or v2.expires or 0) or 0
    local newUid=tonumber(info.userId or v2.userId or 0) or 0
    SaveVIPRaw(("v2|%s|%d|%d"):format(v2.key, newExp, newUid))
    setVIP(true)
    return true
end

-- Offline expiry watcher
task.spawn(function()
    while true do
        task.wait(OFFLINE_CHECK_EVERY)
        if FileExists(VIP_FILE) then
            local raw = LoadVIPRaw()
            if raw=='' then DeleteFile(VIP_FILE) setVIP(false)
            elseif raw~=LEGACY_KEY then
                local v2=parseV2(raw)
                if not v2 or not v2.key then DeleteFile(VIP_FILE) setVIP(false)
                else if v2.expires~=0 and now()>=v2.expires then DeleteFile(VIP_FILE) setVIP(false) end end
            end
        else
            setVIP(false)
        end
    end
end)

-- Gameplay helpers
local function getCharacter() return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() end
local function getHumanoid() return getCharacter():WaitForChild("Humanoid") end
local function getHRP() return getCharacter():WaitForChild("HumanoidRootPart") end
local levelLoopRunning=false
local function unlockAllSuits()
    local ss = LocalPlayer:FindFirstChild("SuitSaves")
    if ss then for _,v in ipairs(ss:GetChildren()) do if v:IsA("BoolValue") then v.Value=true end end end
end
local function updateLevelLoop()
    while levelLoopRunning do
        local stats=LocalPlayer:FindFirstChild("STATS")
        if stats then local lvl=stats:FindFirstChild("Level"); if lvl and lvl:IsA("IntValue") then lvl.Value=999 end end
        task.wait(1)
    end
end

-- Items/Tools (VIP-only)
local function forceDelete(name)
    for _, c in ipairs({LocalPlayer.Backpack, LocalPlayer.Character}) do
        if c then for _, i in ipairs(c:GetChildren()) do if i:IsA("Tool") and i.Name==name then pcall(function() i:Destroy() end) end end end
    end
end
local function equipTool(name)
    local t=LocalPlayer.Backpack and LocalPlayer.Backpack:FindFirstChild(name)
    if t and LocalPlayer.Character then pcall(function() t.Parent=LocalPlayer.Character end) end
end
local function useTrapTool()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}) return end
    local evs=getEvents(); if not evs then return end
    forceDelete("TrapTool")
    local eq=getItemsEquiped(); if eq then local f=eq:FindFirstChild("Trap"); if f then f.Value=false end end
    local ev=evs:FindFirstChild("BearTrapEvent"); if ev then ev:FireServer(LocalPlayer) end
    task.wait(0.3) equipTool("TrapTool")
end
local function usePing()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}) return end
    local evs=getEvents(); if not evs then return end
    forceDelete("Ping")
    local eq=getItemsEquiped(); if eq then local f=eq:FindFirstChild("Ping"); if f then f.Value=false end end
    local ev=evs:FindFirstChild("pingEvent"); if ev then ev:FireServer() end
    task.wait(0.3) equipTool("Ping")
end
local function useSpeedCoilTool()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="VIP-only.", Duration=3}) return end
    local evs=getEvents(); if not evs then return end
    forceDelete("EnergyDrink")
    local eq=getItemsEquiped(); if eq then local f=eq:FindFirstChild("EnergyDrink"); if f then f.Value=false end end
    local ev=evs:FindFirstChild("SpeedCoilEvent"); if ev then ev:FireServer({LocalPlayer}) end
    task.wait(0.3) equipTool("EnergyDrink")
end
local function giveMedkit()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Items are VIP-only.", Duration=4}) return end
    local evs=getEvents(); if not evs then return end
    evs:WaitForChild("MedkitEvent"):FireServer({LocalPlayer})
end
local function giveSpeedCoil()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Items are VIP-only.", Duration=4}) return end
    local evs=getEvents(); if not evs then return end
    evs:WaitForChild("SpeedCoilEvent"):FireServer({LocalPlayer})
end
local function giveVest()
    if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Items are VIP-only.", Duration=4}) return end
    local evs=getEvents(); if not evs then return end
    evs:WaitForChild("VestEvent"):FireServer({LocalPlayer})
end

-- ESP (with color pickers)
local espEnabled=false
local beamFolder, espObjects = nil, {}
local puzzleColor   = HexToColor3(Config.espColors.puzzle)   or Color3.fromRGB(255,255,0)
local npcColor      = HexToColor3(Config.espColors.npc)      or Color3.fromRGB(255,0,0)
local elevatorColor = HexToColor3(Config.espColors.elevator) or Color3.fromRGB(0,255,0)

local function clearESP()
    if beamFolder then beamFolder:Destroy() end
    beamFolder=nil; espObjects={}
    RunService:UnbindFromRenderStep("ESPUpdate")
end
local function drawESP()
    clearESP()
    beamFolder=Instance.new("Folder",Workspace); beamFolder.Name="BeamESPFolder"
    local function add(part,color)
        local ad=Instance.new("BoxHandleAdornment"); ad.Adornee=part; ad.AlwaysOnTop=true; ad.ZIndex=10
        ad.Size=part.Size; ad.Transparency=0.5; ad.Color3=color; ad.Parent=beamFolder
        table.insert(espObjects,{part=part,box=ad})
    end
    local function addModel(m,color)
        local p=m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart"); if p then add(p,color) end
    end
    local puzzles=Workspace:FindFirstChild("Puzzle") and Workspace.Puzzle:FindFirstChild("Puzzles")
    if puzzles then for _,m in ipairs(puzzles:GetDescendants()) do if m:IsA("Model") then addModel(m,puzzleColor) end end end
    local npcs=Workspace:FindFirstChild("NPCS"); if npcs then for _,m in ipairs(npcs:GetChildren()) do if m:IsA("Model") then addModel(m,npcColor) end end end
    local elevators=Workspace:FindFirstChild("Elevators"); local level0=elevators and elevators:FindFirstChild("Level0Elevator")
    if level0 then for _,p in ipairs(level0:GetDescendants()) do if p:IsA("BasePart") then add(p,elevatorColor) end end end
    RunService:BindToRenderStep("ESPUpdate",301,function()
        for i=#espObjects,1,-1 do
            local o=espObjects[i]
            if o.part and o.part.Parent and o.box then o.box.Adornee=o.part; o.box.Size=o.part.Size else if o.box then o.box:Destroy() end table.remove(espObjects,i) end
        end
    end)
end
task.spawn(function() while true do if espEnabled then drawESP() else clearESP() end task.wait(1) end end)

-- Player loops
local speedLoopEnabled=false
local speedValue=16
local godmodeEnabled=false
local RunningTrapLoop=false
local RunningPingLoop=false

task.spawn(function()
    while true do
        if speedLoopEnabled then local h=getHumanoid(); if h then h.WalkSpeed=speedValue end end
        task.wait(0.2)
    end
end)
task.spawn(function()
    while true do
        if godmodeEnabled and vipAccess then
            local evs=getEvents(); if evs then evs:WaitForChild("VestEvent"):FireServer({LocalPlayer}) end
        end
        task.wait(0.7)
    end
end)

-- UI
local Window = Rayfield:CreateWindow({
    Name="Game Hub",
    LoadingTitle="Loading...",
    LoadingSubtitle="Made by @plet_farmyt",
    ConfigurationSaving={Enabled=false},
    KeySystem=false
})
local MainTab  = Window:CreateTab("Main", 4483362458)
local ItemsTab = Window:CreateTab("Items (VIP)", 4483362361)
local ESPTab   = Window:CreateTab("ESP", 4483362457)
local PlayerTab= Window:CreateTab("Player", 4483362006)
local VIPTab   = Window:CreateTab("VIP", 4483362458)
local KeybindsTab, ExploitsTab

-- Build VIP tabs on demand
local function createKeybindsTab()
    if KeybindsTab or not vipAccess then return end
    KeybindsTab = Window:CreateTab("Keybinds", 4483362706)
    local function show()
        KeybindsTab:CreateParagraph({
            Title="Current Binds",
            Content=("Trap: %s\nPing: %s\nCoil: %s\nPanic: %s"):format(Config.trapKey, Config.pingKey, Config.coilKey, Config.panicKey)
        })
    end
    show()
    KeybindsTab:CreateInput({ Name="Trap key",  PlaceholderText="Current: "..Config.trapKey,  RemoveTextAfterFocusLost=true, Callback=function(t) if t~='' then Config.trapKey=t:upper(); SaveConfig(Config); Rayfield:Notify({Title="Bind", Content="Trap = "..Config.trapKey, Duration=2}); show() end end })
    KeybindsTab:CreateInput({ Name="Ping key",  PlaceholderText="Current: "..Config.pingKey,  RemoveTextAfterFocusLost=true, Callback=function(t) if t~='' then Config.pingKey=t:upper(); SaveConfig(Config); Rayfield:Notify({Title="Bind", Content="Ping = "..Config.pingKey, Duration=2}); show() end end })
    KeybindsTab:CreateInput({ Name="Coil key",  PlaceholderText="Current: "..Config.coilKey,  RemoveTextAfterFocusLost=true, Callback=function(t) if t~='' then Config.coilKey=t:upper(); SaveConfig(Config); Rayfield:Notify({Title="Bind", Content="Coil = "..Config.coilKey, Duration=2}); show() end end })
    KeybindsTab:CreateInput({ Name="Panic key", PlaceholderText="Current: "..Config.panicKey, RemoveTextAfterFocusLost=true, Callback=function(t) if t~='' then Config.panicKey=t:upper(); SaveConfig(Config); Rayfield:Notify({Title="Bind", Content="Panic = "..Config.panicKey, Duration=2}); show() end end })
end
local function createExploitsTab()
    if ExploitsTab or not vipAccess then return end
    ExploitsTab = Window:CreateTab("Exploits", 4483362360)
    ExploitsTab:CreateToggle({
        Name="Trap Loop (VIP)", CurrentValue=false,
        Callback=function(v)
            if not vipAccess then return end
            RunningTrapLoop=v
            task.spawn(function()
                while RunningTrapLoop and vipAccess do
                    useTrapTool(); task.wait(0.25)
                end
            end)
        end
    })
    ExploitsTab:CreateToggle({
        Name="Ping Loop (VIP)", CurrentValue=false,
        Callback=function(v)
            if not vipAccess then return end
            RunningPingLoop=v
            task.spawn(function()
                while RunningPingLoop and vipAccess do
                    usePing(); task.wait(0.25)
                end
            end)
        end
    })
    ExploitsTab:CreateButton({ Name="Trap Once (VIP)",   Callback=function() if vipAccess then useTrapTool() end end })
    ExploitsTab:CreateButton({ Name="Ping Once (VIP)",   Callback=function() if vipAccess then usePing() end end })
    ExploitsTab:CreateButton({ Name="Coil Once (VIP)",   Callback=function() if vipAccess then useSpeedCoilTool() end end })
end
local function ensureVIPTabs()
    if vipAccess then createExploitsTab(); createKeybindsTab() end
end

-- Main
MainTab:CreateButton({ Name="Unlock All", Callback=function()
    unlockAllSuits(); levelLoopRunning=true; task.spawn(updateLevelLoop)
end })
-- W.I.P note
MainTab:CreateParagraph({
    Title = "Auto Farming",
    Content = "W.I.P (work in progress) — coming soon!"
})

-- Items
ItemsTab:CreateButton({ Name="Medkit (VIP)",     Callback=giveMedkit })
ItemsTab:CreateButton({ Name="Speed Coil (VIP)", Callback=giveSpeedCoil })
ItemsTab:CreateButton({ Name="Vest (VIP)",       Callback=giveVest })

-- ESP
ESPTab:CreateToggle({ Name="Enable ESP", CurrentValue=false, Callback=function(v) espEnabled=v end })
ESPTab:CreateParagraph({
    Title = "ESP Colors",
    Content = "Customize and they'll be saved to config."
})
ESPTab:CreateColorPicker({
    Name = "Puzzle Color",
    Color = puzzleColor,
    Callback = function(c)
        puzzleColor = c
        Config.espColors.puzzle = Color3ToHex(c)
        SaveConfig(Config)
        if espEnabled then drawESP() end
    end
})
ESPTab:CreateColorPicker({
    Name = "NPC Color",
    Color = npcColor,
    Callback = function(c)
        npcColor = c
        Config.espColors.npc = Color3ToHex(c)
        SaveConfig(Config)
        if espEnabled then drawESP() end
    end
})
ESPTab:CreateColorPicker({
    Name = "Elevator Color",
    Color = elevatorColor,
    Callback = function(c)
        elevatorColor = c
        Config.espColors.elevator = Color3ToHex(c)
        SaveConfig(Config)
        if espEnabled then drawESP() end
    end
})
ESPTab:CreateButton({
    Name = "Reset ESP Colors",
    Callback = function()
        puzzleColor   = Color3.fromRGB(255,255,0)
        npcColor      = Color3.fromRGB(255,0,0)
        elevatorColor = Color3.fromRGB(0,255,0)
        Config.espColors.puzzle   = "#FFFF00"
        Config.espColors.npc      = "#FF0000"
        Config.espColors.elevator = "#00FF00"
        SaveConfig(Config)
        if espEnabled then drawESP() end
        Rayfield:Notify({Title="ESP", Content="Colors reset to defaults.", Duration=3})
    end
})

-- Player
PlayerTab:CreateToggle({ Name="WalkSpeed Loop", CurrentValue=false, Callback=function(v) speedLoopEnabled=v end })
PlayerTab:CreateSlider({ Name="WalkSpeed", Range={16,80}, Increment=1, CurrentValue=16, Callback=function(v) speedValue=v end })
PlayerTab:CreateToggle({
    Name="Godmode (VIP)", CurrentValue=false,
    Callback=function(v)
        if not vipAccess then Rayfield:Notify({Title="VIP Only", Content="Godmode is VIP-only.", Duration=4}) return end
        godmodeEnabled=v
    end
})

-- VIP input
VIPTab:CreateInput({
    Name="Enter VIP Key",
    PlaceholderText="Enter VIP Key",
    RemoveTextAfterFocusLost=false,
    Callback=function(val)
        local key=(val or ''):gsub('%s+',''); if key=='' then return end
        if key==LEGACY_KEY then Rayfield:Notify({Title="VIP", Content="This key is deprecated and no longer accepted.", Duration=6}); return end
        local ok, infoOrReason = validateKeyOnline(key)
        if ok then
            local info=infoOrReason; local exp=tonumber(info.expires or 0) or 0; local uid=tonumber(info.userId or 0) or 0
            SaveVIPRaw(("v2|%s|%d|%d"):format(key, exp, uid))
            if validateFileAndApplyVIP() then Rayfield:Notify({Title="VIP", Content="VIP activated.", Duration=4}); ensureVIPTabs() else Rayfield:Notify({Title="VIP", Content="Failed to apply VIP from file.", Duration=6}) end
        else
            local r=infoOrReason; local msg="Invalid key."
            if r=="Expired" then msg="Key expired." elseif r=="WrongUser" then msg="Key is bound to another user." elseif r=="Revoked" then msg="Key revoked." elseif r=="Network" then msg="Network error while validating the key." end
            SafeSetClipboard(DISCORD_CONTACT)
            Rayfield:Notify({Title="VIP", Content=msg..". Discord copied: "..DISCORD_CONTACT, Duration=8})
        end
    end
})

-- Panic
local function Panic()
    -- мягко выключаем всё
    espEnabled=false; pcall(clearESP)
    speedLoopEnabled=false; godmodeEnabled=false
    RunningTrapLoop=false; RunningPingLoop=false
    Rayfield:Notify({ Title="Panic", Content="All features disabled.", Duration=4 })
end

-- Hotkeys (VIP)
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    local k=input.KeyCode.Name
    if k==Config.panicKey then
        Panic(); return
    end
    if not vipAccess then return end
    if k==Config.trapKey then useTrapTool()
    elseif k==Config.pingKey then usePing()
    elseif k==Config.coilKey then useSpeedCoilTool()
    end
end)

-- Remote control & broadcasts (расширенный)
local RELOAD_URL = "https://raw.githubusercontent.com/pletfarm454/scripts/refs/heads/main/script.lua"
local MaintenanceMode = false
local function DisableAllFeatures()
    espEnabled=false; pcall(clearESP)
    speedLoopEnabled=false; RunningTrapLoop=false; RunningPingLoop=false; godmodeEnabled=false
end
task.spawn(function()
    local function _now() return DateTime.now().UnixTimestamp end
    local lastTs=_now()
    while true do
        local url = string.format("%s/messages?since=%d&vip=%d", VIP_API_BASE, lastTs, (vipAccess and 1 or 0))
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok then
            local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
            if ok2 and data and data.ok then
                for _, msg in ipairs(data.messages or {}) do
                    local ts = tonumber(msg.createdAt or 0) or 0
                    if msg.type == "broadcast" then
                        local txt=tostring(msg.text or "")
                        if txt~="" then Rayfield:Notify({ Title=msg.vipOnly and "Broadcast (VIP)" or "Broadcast", Content=txt, Duration=8 }) end
                    elseif msg.type == "control" then
                        local action=tostring(msg.action or "")
                        if action=="disable_all" then
                            DisableAllFeatures()
                        elseif action=="reload" then
                            local u=tostring(msg.scriptUrl or RELOAD_URL)
                            pcall(function() loadstring(game:HttpGet(u))() end); return
                        elseif action=="maintenance_on" then
                            MaintenanceMode=true; DisableAllFeatures()
                        elseif action=="maintenance_off" then
                            MaintenanceMode=false
                        elseif action=="notify" then
                            local txt=tostring(msg.text or ""); if txt~="" then Rayfield:Notify({Title="Admin", Content=txt, Duration=8}) end
                        elseif action=="esp_on" then espEnabled=true
                        elseif action=="esp_off" then espEnabled=false; pcall(clearESP)
                        elseif action=="ws" then local v=tonumber(msg.value or speedValue) or 16; speedValue=v; local h=getHumanoid(); if h then h.WalkSpeed=v end
                        elseif action=="speedloop_on" then speedLoopEnabled=true
                        elseif action=="speedloop_off" then speedLoopEnabled=false
                        elseif action=="godmode_on" then if vipAccess then godmodeEnabled=true end
                        elseif action=="godmode_off" then godmodeEnabled=false
                        elseif action=="tool_once" then
                            local w=tostring(msg.tool or "")
                            if w=="trap" then useTrapTool() elseif w=="ping" then usePing() elseif w=="coil" then useSpeedCoilTool() end
                        elseif action=="set_bind" then
                            local bind=tostring(msg.bind or "")
                            local key=tostring(msg.key or ""):upper()
                            if key~="" and (#key<=2) then
                                if bind=="trap" then Config.trapKey=key
                                elseif bind=="ping" then Config.pingKey=key
                                elseif bind=="coil" then Config.coilKey=key end
                                SaveConfig(Config)
                                Rayfield:Notify({Title="Bind", Content=("Updated %s = %s"):format(bind, key), Duration=3})
                            end
                        elseif action=="set_panic" then
                            local key=tostring(msg.key or ""):upper()
                            if key~="" and (#key<=2) then Config.panicKey=key; SaveConfig(Config); Rayfield:Notify({Title="Bind", Content="Updated Panic = "..key, Duration=3}) end
                        elseif action=="vip_revalidate" then
                            if validateFileAndApplyVIP() then ensureVIPTabs() end
                        elseif action=="vip_delete_file" then
                            if FileExists(VIP_FILE) then DeleteFile(VIP_FILE) end; setVIP(false); DisableAllFeatures()
                        end
                    end
                    if ts>lastTs then lastTs=ts end
                end
            end
        end
        task.wait(8)
    end
end)

-- Final: validate file and show VIP tabs if ok
validateFileAndApplyVIP()
ensureVIPTabs()
