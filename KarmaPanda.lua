-- KarmaPanda ASTD: corrected runtime and local Auto Execute installer.
-- Keeps the same checked runtime after teleport; installs in the executor workspace.
local source = [======[if not game:IsLoaded() then game.Loaded:Wait() end
local _waitStart = tick()
repeat task.wait(0.5) until game.GameId == 1720936166 or game.PlaceId == 4996049426 or tick() - _waitStart > 15
if game.GameId ~= 1720936166 and game.PlaceId ~= 4996049426 then return end
local _kpEnv = getgenv()
local _kpSessionId = tostring(game.JobId) .. ":" .. tostring(os.clock())
if _kpEnv.KP_Runtime and _kpEnv.KP_Runtime.cleanup then
    pcall(_kpEnv.KP_Runtime.cleanup)
end
_kpEnv.KP_Runtime = {
    session = _kpSessionId,
    connections = {},
    suppressMacroUnits = setmetatable({}, {__mode = "k"}),
    suppressNextSummonNames = {}
}
-- Reset auto-execute flag so re-execution re-queues correctly
_kpEnv.loaded = false
_G.KarmaPandaLoaded = true
-- Session-owned workers: re-execution cancels every task created by this file.
local KP = _kpEnv.KP_Runtime
KP.alive = true
KP.tasks = {}
KP.contexts = setmetatable({}, {__mode = "k"})
KP.features = {}
KP.errors = {}
local nativeTask = task
local task = setmetatable({}, {__index = nativeTask})
function KP.Report(label, err)
    local message = tostring(err)
    local key = label .. ":" .. message
    if tick() - (KP.errors[key] or -math.huge) >= 10 then
        -- Bound diagnostic memory; errors must not become a second leak.
        if KP.errorCount and KP.errorCount >= 32 then KP.errors = {}; KP.errorCount = 0 end
        KP.errors[key] = tick()
        KP.errorCount = (KP.errorCount or 0) + 1
        warn("[KarmaPanda:X] " .. label .. ": " .. message)
    end
end
function KP.Schedule(kind, delay, fn, ...)
    local args = table.pack(...)
    local context = KP.contexts[coroutine.running()]
    local thread = coroutine.create(function()
        local running = coroutine.running()
        if not KP.ContextAlive(context) then KP.tasks[running] = nil; KP.contexts[running] = nil; return end
        KP.contexts[running] = context
        local ok, err = pcall(fn, table.unpack(args, 1, args.n))
        KP.tasks[running] = nil
        KP.contexts[running] = nil
        if not ok and KP.alive then KP.Report("Worker", err) end
    end)
    KP.tasks[thread] = context or true
    if kind == "delay" then nativeTask.delay(delay, thread)
    elseif kind == "defer" then nativeTask.defer(thread)
    else nativeTask.spawn(thread) end
    return thread
end
function task.spawn(fn, ...) return KP.Schedule("spawn", 0, fn, ...) end
function task.defer(fn, ...) return KP.Schedule("defer", 0, fn, ...) end
function task.delay(seconds, fn, ...) return KP.Schedule("delay", seconds, fn, ...) end
function task.cancel(thread)
    if not thread then return end
    local ok, err = pcall(nativeTask.cancel, thread)
    if ok or coroutine.status(thread) == "dead" then
        KP.tasks[thread], KP.contexts[thread] = nil, nil
    elseif KP.alive then KP.Report("Task cancellation", err) end
end
function KP.CancelContext(context)
    if not context then return end
    context.cancelled = true
    local current = coroutine.running()
    for thread, owner in pairs(KP.tasks) do
        if owner == context and thread ~= current then
            pcall(nativeTask.cancel, thread)
            KP.tasks[thread] = nil
            KP.contexts[thread] = nil
        end
    end
    for conn in pairs(context.connections or {}) do
        pcall(function() conn:Disconnect() end)
        KP.connections[conn] = nil
    end
    context.connections = {}
end
function KP.ContextAlive(context)
    return KP.alive and _kpEnv.KP_Runtime == KP and (not context or not context.cancelled)
end
function KP.TrackContextConnection(conn, context)
    context = context or KP.contexts[coroutine.running()]
    if not conn then return nil end
    if not KP.ContextAlive(context) then pcall(function() conn:Disconnect() end); return conn end
    if context then
        context.connections = context.connections or {}
        context.connections[conn] = true
    else
        KP.connections[conn] = true
    end
    return conn
end
function KP.WithContext(context, fn, ...)
    local current = coroutine.running()
    local previous = KP.contexts[current]
    KP.contexts[current] = context
    local results = table.pack(pcall(fn, ...))
    KP.contexts[current] = previous
    if not results[1] then error(results[2], 0) end
    return table.unpack(results, 2, results.n)
end
function KP.Disconnect(conn)
    if not conn then return end
    pcall(function() conn:Disconnect() end)
    KP.connections[conn] = nil
    for _, context in pairs(KP.features) do
        if context.connections then context.connections[conn] = nil end
    end
    if KP.playback and KP.playback.connections then KP.playback.connections[conn] = nil end
    if KP.recording and KP.recording.connections then KP.recording.connections[conn] = nil end
end

local benchmark_time = os.clock()


local ShowNotify = function() end
-- Helper Functions
local function Split(s, delimiter)
    local result = {}
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

local function StringToCFrame(input)
    return CFrame.new(unpack(game:GetService("HttpService"):JSONDecode("[" ..
                                                                           input ..
                                                                           "]")))
end

local function ShallowCopy(original)
    local copy = {}
    for key, value in pairs(original) do copy[key] = value end
    return copy
end

local function DeepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then v = DeepCopy(v) end
        copy[k] = v
    end
    return copy
end

local function TableLength(t)
    local n = 0

    for _ in pairs(t) do n = n + 1 end

    return n
end

local function TableConcat(t1, t2)
    for i = 1, #t2 do t1[#t1 + 1] = t2[i] end
    return t1
end

local function get_keys(t)
    local keys = {}
    for key, _ in pairs(t) do table.insert(keys, key) end
    return keys
end

local ShinyUnitAliases = {
    ["toji revived"] = "toji",
    ["wormji revived"] = "wormji"
}

local function NormalizeUnitVariantName(unitName)
    local normalized = tostring(unitName or ""):lower()
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    normalized = ShinyUnitAliases[normalized] or normalized
    normalized = normalized:gsub("%s*shiny%s*$", "")
    local compact = normalized:gsub("[%s%p_]+", "")
    if compact == "tojirevived" or compact == "toji" then return "toji" end
    if compact == "wormjirevived" or compact == "wormji" then return "wormji" end
    return ShinyUnitAliases[normalized] or normalized
end

local function UnitVariantNamesMatch(leftName, rightName)
    if not leftName or not rightName then return false end
    return NormalizeUnitVariantName(leftName) == NormalizeUnitVariantName(rightName)
end

local function FindUnitVariantInList(unitNames, targetName)
    for index, unitName in ipairs(unitNames or {}) do
        if UnitVariantNamesMatch(unitName, targetName) then
            return index, unitName
        end
    end
    return nil, nil
end

local postfixes = {
    ["n"] = 10 ^ (-6),
    ["m"] = 10 ^ (-3),
    ["k"] = 10 ^ 3,
    ["M"] = 10 ^ 6,
    ["G"] = 10 ^ 9
}

local function convert(n)
    local postfix = n:sub(-1)
    if postfixes[postfix] then
        return tonumber(n:sub(1, -2)) * postfixes[postfix]
    elseif tonumber(n) then
        return tonumber(n)
    else
        error("invalid postfix")
    end
end

-- https://devforum.roblox.com/t/comparing-color-values/1017439/2
local function CompareColor3(base, toCompare)
    local base_colors = {base.R, base.G, base.B} -- table to hold the original color3s
    local comp_colors = {toCompare.R, toCompare.G, toCompare.B} -- table to 

    local verdict = {} -- table to hold whether other not each of them were the same

    for index, col in ipairs(comp_colors) do -- uses an "ipairs" loop instead of "pairs" loop because this is numerical
        if base_colors[index] == col then -- checks if the index of the base_colors table is the same
            table.insert(verdict, true) -- add 1 true value to the verdict table
        else
            table.insert(verdict, false) -- add 1 false value to the verdict table
        end
    end

    if table.find(verdict, false) then -- if one of them is false then it isn't the same
        return false -- returns false
    else
        return true -- returns true
    end
end

local version = "3.1"
local Settings
local Macros = {}
local RefreshMacroLeaderDropdown = function() end


benchmark_time = os.clock()

local function ScriptAlive()
    return KP.alive and _kpEnv.KP_Runtime == KP
end

local function TrackConnection(conn)
    if conn then
        if KP.alive then KP.connections[conn] = true else pcall(function() conn:Disconnect() end) end
    end
    return conn
end

function KP_MarkMacroSuppressedUnit(unit, seconds)
    if unit and _kpEnv.KP_Runtime and _kpEnv.KP_Runtime.suppressMacroUnits then
        _kpEnv.KP_Runtime.suppressMacroUnits[unit] = tick() + (seconds or 12)
    end
end

function KP_IsMacroSuppressedUnit(unit)
    if not unit or not _kpEnv.KP_Runtime or not _kpEnv.KP_Runtime.suppressMacroUnits then
        return false
    end
    local expires = _kpEnv.KP_Runtime.suppressMacroUnits[unit]
    if expires and tick() <= expires then return true end
    _kpEnv.KP_Runtime.suppressMacroUnits[unit] = nil
    return false
end

function KP_SuppressNextSummonName(unitName, seconds)
    if unitName and unitName ~= "" and _kpEnv.KP_Runtime and _kpEnv.KP_Runtime.suppressNextSummonNames then
        _kpEnv.KP_Runtime.suppressNextSummonNames[NormalizeUnitVariantName(unitName)] =
            tick() + (seconds or 12)
    end
end

function KP_ConsumeSuppressedSummonName(unitName)
    if not unitName or not _kpEnv.KP_Runtime or not _kpEnv.KP_Runtime.suppressNextSummonNames then
        return false
    end
    local key = NormalizeUnitVariantName(unitName)
    local expires = _kpEnv.KP_Runtime.suppressNextSummonNames[key]
    if expires and tick() <= expires then
        _kpEnv.KP_Runtime.suppressNextSummonNames[key] = nil
        return true
    end
    _kpEnv.KP_Runtime.suppressNextSummonNames[key] = nil
    return false
end

function KP_SuppressNextMultiAbility(seconds)
    if _kpEnv.KP_Runtime then
        _kpEnv.KP_Runtime.suppressMacroMultiAbilityUntil = tick() + (seconds or 3)
    end
end

function KP_IsMultiAbilitySuppressed()
    return _kpEnv.KP_Runtime and _kpEnv.KP_Runtime.suppressMacroMultiAbilityUntil and
        tick() <= _kpEnv.KP_Runtime.suppressMacroMultiAbilityUntil
end

KP.cleanup = function()
    if not KP.alive then return end
    if KP.flushMacros then pcall(KP.flushMacros) end
    KP.alive = false
    for thread in pairs(KP.tasks) do
        if thread ~= coroutine.running() then pcall(nativeTask.cancel, thread) end
    end
    KP.tasks = {}
    if KP.stopRecording then pcall(KP.stopRecording) end
    if KP.playback then KP.CancelContext(KP.playback) end
    for _, context in pairs(KP.features) do KP.CancelContext(context) end
    for conn in pairs(KP.connections) do pcall(function() conn:Disconnect() end) end
    KP.connections = {}
    for _, name in ipairs({"restoreMap", "restoreSimplifiedEnemies", "restoreDestroyedVisuals", "restoreFPS", "restoreAnonymous", "restoreRendering", "restorePriorityHook", "cleanupAutoPlacement"}) do
        if KP[name] then pcall(KP[name]) end
    end
    if KP.ui then pcall(function() KP.ui:Destroy() end) end
    if KP.enemyOverlayFolder then pcall(function() KP.enemyOverlayFolder:Destroy() end) end
end

if not isfolder("KarmaPanda") then makefolder("KarmaPanda") end

if not isfolder("KarmaPanda/ASTD") then makefolder("KarmaPanda/ASTD") end

if not isfolder("KarmaPanda/ASTD/Settings") then
    makefolder("KarmaPanda/ASTD/Settings")
end
KP.runtimeSourcePath = "KarmaPanda/ASTD/runtime.lua"
if type(_kpEnv.KP_InstallSource) == "string" then
    writefile(KP.runtimeSourcePath, _kpEnv.KP_InstallSource)
end
local SettingsFile = "KarmaPanda/ASTD/Settings/" ..
                         game.Players.LocalPlayer.UserId .. ".json"

local InfiniteMapTable = {
    ["-1"] = "Regular [1]",
    ["-1.7"] = "Regular [2]",
    ["-1.1"] = "Category",
    ["-1.3"] = "Air",
    ["-1.8"] = "Solo",
    ["-1.9"] = "Random Unit",
    ["-1.5"] = "Double Path",
    ["-97"] = "Gauntlet",
    ["-98"] = "Training",
    ["-99"] = "Farm"
}

local AdventureMapTable = {
    ["-12"] = "Android Raid",
    ["-13"] = "String Raid",
    ["-14"] = "Bizarre Raid",
    ["-1003"] = "Sijin Raid",
    ["-1004"] = "Spirit Raid",
    ["-1111"] = "Marine HQ",
    ["-1112"] = "Kai Planet",
    ["-1113"] = "Hell",
    ["-1114"] = "Machi Planet",
    ["-1115"] = "Shadow Island",
    ["-1116"] = "Fighter Raid",
    ["-1117"] = "Candy Raid",
    ["-1118"] = "Demon Mark Raid",
    ["-1121"] = "Soul Raid",
    ["-1122"] = "Sun Raid",
    ["-1125"] = "Meteor Raid",
    ["-1127"] = "Berserker Raid",
    ["-1128"] = "Venom Raid",
    ["-1129"] = "Dueled Raid",
    ["-1132"] = "Hunt on Blacksmith",
    ["-1133"] = "Mythical Freedom",
    ["-1134"] = "Bizzare Prison",
    ["-1136"] = "Six Eyes Raid",
    ["-1138"] = "Girlzone",
    ["-1139"] = "Purezone",
    ["-1140"] = "Brutezone",
    ["-1142"] = "TOP1",
    ["-1143"] = "TOP2",
    ["-1144"] = "TOP3",
    ["-1145"] = "TOP4",
    ["-1146"] = "TOP5",
    ["-1147"] = "Spiritzone",
    ["-1148"] = "TOP6",
    ["-1149"] = "Siblingzone",
    ["-1150"] = "Enuma Raid",
    ["-1152"] = "Legendaryzone",
    ["-1153"] = "Snipe Raid",
    ["-1154"] = "Prodigyzone",
    ["-1155"] = "Demon Raid M2",
    ["-1156"] = "Divine Raid",
    ["-1159"] = "Unwordly Beings",
    ["-1160"] = "Youth",
    ["-1161"] = "Captains",
    ["-1162"] = "Crystal Cavern Raid",
    ["-1163"] = "Malevolent Raid",
    ["-1164"] = "Darkness Raid",
    ["-1165"] = "Purple Planet Raid",
    ["-1166"] = "Earth Tournament Memory Raid",
    ["-1167"] = "Ocean Memory Raid",
    ["-1168"] = "Demon Memory Raid",
    ["-1169"] = "Depraved Demon Zone",
    ["-1170"] = "World Competition Raid",
    ["-1171"] = "Wraith Labyrinth Raid",
    ["-1172"] = "Cosmic Raid",
    ["-1173"] = "Nagoya Airport Raid",
    ["-1450"] = "Random Boss Rush",
    ["-1451"] = "Random Boss Rush 2",
    ["-1506"] = "Path Raid"
}

local function GetMapsFromTable(T)
    local maps = {}
    for _, v in pairs(T) do table.insert(maps, v) end
    return maps
end

local DefaultSettings = {
    version = version,
    auto_buff = false,
    auto_buff_units = {
        ["Erwin"] = {
            ["Mode"] = "Box",
            ["Checks"] = {"attack"},
            ["Ability Type"] = "Normal",
            ["Time"] = 13
        },
        ["Brook6"] = {
            ["Mode"] = "Box",
            ["Checks"] = {"attack", "range"},
            ["Ability Type"] = "Normal",
            ["Time"] = 13
        },
        ["Kisuke6"] = {
            ["Mode"] = "Pair",
            ["Checks"] = {"attack", "range"},
            ["Ability Type"] = "Multiple",
            ["Ability Name"] = "Buff Ability",
            ["Time"] = 13
        },
        ["Merlin6"] = {
            ["Time"] = 13,
            ["Checks"] = {"attack", "range"},
            ["Mode"] = "Box",
            ["Ability Type"] = "Normal"
        },
        ["Hoshino"] = {
            ["Time"] = 15,
            ["Checks"] = {""},
            ["Mode"] = "Spam",
            ["Delay"] = 0,
            ["Ability Type"] = "Normal"
        },
        ["Metal Cooler"] = {
            ["Time"] = 21,
            ["Checks"] = {""},
            ["Mode"] = "Spam",
            ["Delay"] = 0.5,
            ["Ability Type"] = "Normal"
        },
        ["Leafa6"] = {
            ["Mode"] = "Pair",
            ["Checks"] = {"attack", "range"},
            ["Ability Type"] = "Normal",
            ["Time"] = 30
        }
    },
    auto_vote_extreme = false,
    auto_skip_wave_spam = false,
    auto_2x = true,
    auto_3x = false,
    macro_profile = "Default Profile",
    macro_leader_unit = "",
    macro_record = false,
    macro_playback = false,
    macro_record_time_offset = 0,
    macro_money_tracking = false,
    macro_playback_time_offset = 0,
    macro_magnitude = 1,
    macro_playback_search_attempts = 60,
    macro_playback_search_delay = 0.1,
    macro_auto_adjust_placement = false,
    macro_summon = true,
    macro_sell = true,
    macro_upgrade = true,
    macro_ability = true,
    macro_auto_ability = true,
    macro_priority = true,
    macro_skipwave = true,
    macro_autoskipwave = true,
    macro_speedchange = true,
    macro_ability_blacklist = {
        "Erwin", "Brook6", "Kisuke6", "Merlin6",
        "Hoshino", "Metal Cooler"
    },
    auto_cycle_timestop = false,
    auto_cycle_timestop_unit = "Gojo7",
    auto_killua = false,
    auto_killua_wish = "Money",
    auto_target_ability = false,
    auto_target_enemy_type = "Cloner",
    auto_target_hp_percent = 10,
    auto_target_enemy_count = 0,
    auto_target_ability_delay = 0,
    auto_target_ability_unit = "",
    auto_target_ability_multi = false,
    auto_target_ability_multi_slot = 1,
    macro_timer_version = "Version 1",
    action_queue_remote_fire_delay = 0.25,
    action_queue_remote_on_fail = true,
    action_queue_remote_on_fail_delay = 1,
    action_queue_remote_on_fail_delay_loop = 0.5,
    auto_join_game = false,
    auto_join_tower = false,
    auto_join_delay = 5,
    auto_join_mode = "Infinite",
    auto_join_story_level = 0,
    auto_join_infinite_level = "-1.7",
    auto_join_trial_level = 1,
    auto_join_raid_level = 1,
    auto_join_challenge_level = 1,
    auto_join_bout_level = 1,
    auto_join_adventure_level = "-1133",
    auto_join_w3_level = 1,
    advanced_join_settings = false,
    smart_join_auto_exp = false,
    smart_join_exp_active = false,
    smart_join_exp_tickets_remaining = 0,
    auto_evolve_exp = false,
    auto_skip_gui = true,
    webhook_url = "",
    webhook_discord_id = "",
    webhook_user_name = false,
    webhook_color = "B41E1E",
    webhook_ping_user = false,
    webhook_ping_on_lose = false,
    webhook_end_game = true,
    webhook_exp_evolve = false,
    disable_3d_rendering = false,
    auto_execute = false,
    auto_battle = false,
    auto_battle_gems = 1500,
    auto_replay = false,
    auto_next_story = false,
    auto_story_target = 0,
    fps_boost = false,
    delete_enemies = false,
    delete_map = false,
    show_enemy_overlay = false,
    destroy_mode = false,
    fps_limit = "60",
    auto_upgrade = false,
    auto_upgrade_money = 100,
    auto_upgrade_wave_stop = 100,
    auto_upgrade_sell = false,
    auto_upgrade_wave = 0,
    auto_upgrade_level = 10,
    auto_upgrade_wave_sell = 100,
    anonymous_mode = false,
    anonymous_mode_name = "KarmaPanda",
    close_on_injection = false,
    lock_ui = false,
    auto_upgrade_targets = {},
    ui_scale = 0.95,
    ui_scale_initialized = false,
    ui_scale_safe_reset_once = false,
    auto_place_maps = {},
    auto_place_zone_version = 2,
    auto_place_upgrade = true,
    auto_place_upgrade_level = 23,
    auto_place_ready = false,
    auto_place = false,
    auto_place_auto_zones = true,
    auto_place_show_zones = true,
    auto_place_interval = 1,
    auto_place_reserve = 0,
    auto_place_spacing = 4,
    auto_place_size = 48,
    auto_place_transparency = 0.75,
    auto_place_map = "",
    auto_place_zones = {},
    auto_place_units = {},
    macro_keybinds = true,
    mobile_toggle = true
}

function KP.ValidateAutoPlacement(result, legacy)
    local function number(value,low,high,label)
        assert(type(value)=="number" and value==value and math.abs(value)<math.huge,"Invalid "..label)
        return math.clamp(value,low,high)
    end
    result.auto_place_interval=number(result.auto_place_interval,0,5,"placement interval")
    result.auto_place_reserve=number(result.auto_place_reserve,0,10000,"placement reserve")
    result.auto_place_spacing=number(result.auto_place_spacing,0,20,"placement spacing")
    result.auto_place_size=number(result.auto_place_size,8,100,"zone size")
    if legacy and result.auto_place_size==24 then result.auto_place_size=48 end
    result.auto_place_transparency=number(result.auto_place_transparency,.25,.95,"zone transparency")
    result.auto_place_upgrade_level=math.floor(number(result.auto_place_upgrade_level,1,23,"upgrade level"))
    local count=0
    for name,config in pairs(result.auto_place_units) do
        count=count+1
        assert(count<=100 and type(name)=="string" and #name<=150 and type(config)=="table","Invalid placement unit")
        assert(type(config.enabled)=="boolean","Invalid placement unit toggle")
        config.priority=math.floor(number(config.priority,0,100,"unit priority"))
        config.upgradeCap=math.floor(number(config.upgradeCap==nil and math.min(20,result.auto_place_upgrade_level) or config.upgradeCap,0,20,"unit upgrade cap"))
        config.limit=math.floor(number(config.limit,1,8,"unit count"))
        if config.zones==nil then
            local old=math.floor(number(config.zone or 0,0,8,"old unit zone"))
            config.zones=old>0 and {math.min(4,old)} or {1,2}
        end
        assert(type(config.zones)=="table","Invalid unit zones")
        local seen,n={},0
        for index,zone in pairs(config.zones) do
            assert(type(index)=="number" and index%1==0 and index>=1 and index<=4,"Invalid zone selection")
            assert(type(zone)=="number" and zone%1==0 and zone>=1 and zone<=4 and not seen[zone],"Invalid zone selection")
            n=n+1;seen[zone]=true
        end
        assert(n==#config.zones,"Sparse zone selection")
        config.zone=nil;config.surface="Auto"
    end
    local function zones(list,old)
        assert(type(list)=="table","Invalid zones")
        local clean,count={},0
        for index,zone in pairs(list) do
            assert(type(index)=="number" and index%1==0 and index>=1 and index<=(old and 8 or 4) and type(zone)=="table","Invalid zone")
            count=count+1
            for _,key in ipairs({"x","y","z"})do zone[key]=number(zone[key],-1000000,1000000,"coordinate")end
            zone.size=number(zone.size,8,100,"zone size")
            assert(type(zone.enabled)=="boolean","Invalid zone toggle")
            if zone.placed==nil then zone.placed=true end
            if zone.manual==nil then zone.manual=true end
            assert(type(zone.placed)=="boolean" and type(zone.manual)=="boolean","Invalid zone state")
            if index<=4 then clean[index]=zone end
        end
        assert(count==#list,"Sparse zones")
        return clean
    end
    result.auto_place_zones=zones(result.auto_place_zones,legacy)
    count=0
    for key,list in pairs(result.auto_place_maps)do
        count=count+1;assert(count<=1000 and type(key)=="string" and #key<250,"Invalid map zones")
        result.auto_place_maps[key]=zones(list,false)
    end
    return result
end

function KP.ValidateSettings(value)
    assert(type(value) == "table", "Settings must be an object")
    local result = DeepCopy(DefaultSettings)
    local function finite(value, default, label)
        local number = value == nil and default or tonumber(value)
        assert(number and number == number and math.abs(number) < math.huge, "Invalid " .. label)
        return number
    end
    local function stringList(list, label)
        for index, entry in pairs(list) do
            assert(type(index) == "number" and index >= 1 and index % 1 == 0 and type(entry) == "string", "Invalid " .. label)
        end
    end
    for key, v in pairs(value) do
        local default = DefaultSettings[key]
        if default ~= nil then
            if type(default) == "number" then
                v = tonumber(v)
                assert(v and v == v and math.abs(v) < math.huge, "Invalid number: " .. key)
            else
                assert(type(v) == type(default), "Invalid setting type: " .. key)
            end
            result[key] = type(v) == "table" and DeepCopy(v) or v
        end
    end
    for name, unit in pairs(result.auto_buff_units) do
        assert(type(name) == "string" and type(unit) == "table", "Invalid auto ability unit")
        assert(table.find({"Box", "Pair", "Cycle", "Spam"}, unit.Mode), "Invalid ability mode")
        assert(type(unit.Checks) == "table", "Invalid ability checks")
        stringList(unit.Checks, "ability checks")
        assert(unit["Ability Type"] == nil or unit["Ability Type"] == "Normal" or unit["Ability Type"] == "Multiple", "Invalid ability type")
        assert(unit["Ability Name"] == nil or type(unit["Ability Name"]) == "string", "Invalid ability name")
        unit.Time = math.max(0, finite(unit.Time, 13, "ability time"))
        unit.Delay = math.max(0, finite(unit.Delay, 0, "ability delay"))
        unit["Cycle Units"] = math.max(1, math.floor(finite(unit["Cycle Units"], 8, "cycle units")))
    end
    stringList(result.macro_ability_blacklist, "ability blacklist")
    stringList(result.auto_upgrade_targets, "upgrade targets")
    for _, key in ipairs({"macro_playback_search_attempts", "macro_playback_search_delay", "action_queue_remote_fire_delay", "action_queue_remote_on_fail_delay", "action_queue_remote_on_fail_delay_loop", "macro_magnitude", "auto_join_delay", "auto_battle_gems"}) do
        result[key] = math.max(0, result[key])
    end
    result.macro_playback_search_attempts = math.min(120, math.floor(result.macro_playback_search_attempts))
    result.ui_scale = math.clamp(result.ui_scale, 0.5, 1.5)
    if result.auto_3x then result.auto_2x = false end
    result.destroy_mode = false
    return KP.ValidateAutoPlacement(result, value.auto_place_zone_version == nil)
end
do
    local exists = isfile and isfile(SettingsFile)
    local ok, result = pcall(function()
        return KP.ValidateSettings(game:GetService("HttpService"):JSONDecode(readfile(SettingsFile)))
    end)
    if ok then
        Settings = result
    else
        if exists then
            local backedUp, backupError = pcall(function()
                writefile(SettingsFile .. ".invalid-" .. tostring(os.time()) .. ".bak", readfile(SettingsFile))
            end)
            assert(backedUp, "Cannot preserve invalid settings: " .. tostring(backupError))
            KP.Report("Settings recovered; original backed up", result)
        end
        Settings = DeepCopy(DefaultSettings)
    end
end

local IndividualMacroDefaultSettings = {
    ["Macro"] = {},
    ["Units"] = {},
    ["Map"] = {},
    ["Settings"] = {}
}

local MacroDefaultSettings = {
    ["Default Profile"] = DeepCopy(IndividualMacroDefaultSettings)
}

local folder_name = "KarmaPanda/ASTD/" .. game.Players.LocalPlayer.UserId

if not isfolder(folder_name) then makefolder(folder_name) end

local MacroProfileList = {}
local function GetMacroProfilePath(profile_name)
    return folder_name .. "/" .. profile_name .. ".json"
end

local function ExtractMacroProfileName(file)
    local normalized = tostring(file or ""):gsub("\\", "/")
    return normalized:match("([^/]+)%.json$")
end

local function RefreshMacroProfileList()
    local names = {}
    local seen = {}
    for _, file in pairs(listfiles(folder_name)) do
        local profile_name = ExtractMacroProfileName(file)
        if profile_name and not seen[profile_name] then
            seen[profile_name] = true
            table.insert(names, profile_name)
        end
    end
    table.sort(names)
    MacroProfileList = names
    return MacroProfileList
end

local function EnsureMacroProfileShape(profile)
    assert(type(profile) == "table", "Macro profile must be a table")
    for _, key in ipairs({"Macro", "Units", "Map", "Settings"}) do
        if profile[key] == nil then profile[key] = {} end
        assert(type(profile[key]) == "table", "Invalid macro field: " .. key)
    end
    return profile
end

local function MacroProfileHasUnit(profile, unitName)
    if not profile or type(profile["Units"]) ~= "table" or not unitName or unitName == "" then
        return false
    end
    for savedName in pairs(profile["Units"]) do
        if UnitVariantNamesMatch(savedName, unitName) then return true end
    end
    return false
end

local function MacroProfileCanUseLeader(profile, unitName)
    if not unitName or unitName == "" then return false end
    if not profile or type(profile["Units"]) ~= "table" then return false end
    return true
end

local function IsTaggedLeaderUnitName(unitName)
    local text = tostring(unitName or ""):lower()
    return text:find("[leader]", 1, true) ~= nil or
        text:find("(leader)", 1, true) ~= nil or
        text:find("{leader}", 1, true) ~= nil
end

local function InferLeaderUnitFromProfile(profile)
    if not profile or type(profile["Units"]) ~= "table" then return "" end
    local units = get_keys(profile["Units"])
    table.sort(units)
    for _, unitName in ipairs(units) do
        if IsTaggedLeaderUnitName(unitName) then
            return unitName
        end
    end
    return ""
end

local function GetMacroProfileLeaderUnit(profile, fallbackLeader)
    if not profile then return "" end
    EnsureMacroProfileShape(profile)
    local profileSettings = profile["Settings"]
    local savedLeader = profileSettings["LeaderUnit"] or profileSettings["macro_leader_unit"] or
        profileSettings["leader_unit"] or profile["LeaderUnit"] or profile["macro_leader_unit"]
    savedLeader = tostring(savedLeader or "")
    if savedLeader ~= "" and MacroProfileCanUseLeader(profile, savedLeader) then
        profileSettings["LeaderUnit"] = savedLeader
        return savedLeader
    end

    local inferredLeader = InferLeaderUnitFromProfile(profile)
    if inferredLeader ~= "" then
        profileSettings["LeaderUnit"] = inferredLeader
        return inferredLeader
    end

    fallbackLeader = tostring(fallbackLeader or "")
    if fallbackLeader ~= "" and MacroProfileCanUseLeader(profile, fallbackLeader) then
        profileSettings["LeaderUnit"] = fallbackLeader
        return fallbackLeader
    end

    profileSettings["LeaderUnit"] = ""
    return ""
end

local function SetMacroProfileLeaderUnit(profile, leaderUnit)
    if not profile then return "" end
    EnsureMacroProfileShape(profile)
    leaderUnit = tostring(leaderUnit or "")
    if leaderUnit ~= "" and not MacroProfileCanUseLeader(profile, leaderUnit) then
        leaderUnit = ""
    end
    profile["Settings"]["LeaderUnit"] = leaderUnit
    Settings.macro_leader_unit = leaderUnit
    return leaderUnit
end

KP.profileErrors = {}
KP.dirtyProfiles = {}
function KP.ValidProfileName(name)
    return type(name) == "string" and #name > 0 and #name <= 100 and
        not name:find('[<>:"/\\|?*%c]') and name ~= "." and name ~= ".." and
        not name:match("[%.%s]$")
end
function KP.FindProfileName(name)
    if type(name) ~= "string" then return nil end
    local folded = name:lower()
    for _, existing in ipairs(MacroProfileList) do
        if existing:lower() == folded then return existing end
    end
    return nil
end
function KP.ValidateProfile(profile)
    EnsureMacroProfileShape(profile)
    local function finite(value, label)
        local number = tonumber(value)
        assert(number and number == number and math.abs(number) < math.huge, "Invalid " .. label)
        return number
    end
    local function array(value, label)
        local count = 0
        for key in pairs(value) do
            assert(type(key) == "number" and key >= 1 and key % 1 == 0, "Invalid " .. label .. " index")
            count = count + 1
        end
        for index = 1, count do assert(value[index] ~= nil, "Missing " .. label .. " entry") end
    end
    array(profile.Macro, "macro")
    for name, placements in pairs(profile.Units) do
        assert(type(name) == "string" and type(placements) == "table", "Invalid unit placements")
        array(placements, "placement")
        for _, placement in ipairs(placements) do
            assert(type(placement) == "table" and type(placement.Position) == "string", "Invalid placement")
            StringToCFrame(placement.Position)
            placement.Rotation = finite(placement.Rotation, "placement rotation")
        end
    end
    for _, action in ipairs(profile.Macro) do
        assert(type(action) == "table" and type(action.Time) == "number" and action.Time == action.Time and math.abs(action.Time) < math.huge, "Invalid action time")
        assert(type(action.Remote) == "table" and type(action.Remote[1]) == "string", "Invalid action remote")
        assert(action.Parameter == nil or type(action.Parameter) == "table", "Invalid action parameters")
        for _, key in ipairs({"Wave", "EnemyCount"}) do
            if action[key] ~= nil then action[key] = finite(action[key], key) end
        end
        local parameter = action.Parameter
        if parameter then
            for _, key in ipairs({"Level", "Speed", "Wave"}) do
                if parameter[key] ~= nil then parameter[key] = finite(parameter[key], key) end
            end
            if parameter.Priority ~= nil then
                assert(type(parameter.Priority) == "string" or type(parameter.Priority) == "number" or type(parameter.Priority) == "boolean", "Invalid priority")
            end
            assert(parameter.PriorityField == nil or type(parameter.PriorityField) == "string", "Invalid priority field")
        end
        if action.Target then
            local t = action.Target
            assert(type(t) == "table" and profile.Units[t.Name] and profile.Units[t.Name][t.Index], "Missing action placement")
        end
    end
    if profile.Map.SpawnLocation ~= nil then StringToCFrame(profile.Map.SpawnLocation) end
    return profile
end
local function LoadMacroProfile(profile_name)
    if not KP.ValidProfileName(profile_name) then return nil end
    if KP.profileErrors[profile_name] then return nil end
    local ok, result = pcall(function()
        local content = game:GetService("HttpService"):JSONDecode(readfile(GetMacroProfilePath(profile_name)))
        assert(type(content) == "table", "Invalid macro file")
        local profile = content[profile_name]
        if not profile and content.Macro and content.Units then profile = content end
        if not profile then
            local only
            for _, value in pairs(content) do
                assert(not only, "Ambiguous macro file")
                only = value
            end
            profile = only
        end
        return KP.ValidateProfile(profile)
    end)
    if not ok then
        KP.profileErrors[profile_name] = tostring(result)
        KP.Report("Cannot load macro " .. profile_name .. "; file preserved", result)
        return nil
    end
    GetMacroProfileLeaderUnit(result)
    rawset(Macros, profile_name, result)
    return result
end

local function FocusMacroProfile(profile_name)
    if not profile_name or profile_name == "" then return nil end
    local profile = rawget(Macros, profile_name) or LoadMacroProfile(profile_name)
    if profile then
        Settings.macro_leader_unit = GetMacroProfileLeaderUnit(profile)
    end
    -- Keep loaded profiles until cleanup: active recordings/playback own their profile.
    return profile
end

local function GetActiveMacroProfile()
    return FocusMacroProfile(Settings.macro_profile)
end

setmetatable(Macros, {
    __index = function(t, key)
        if type(key) ~= "string" or key == "" then return nil end
        return LoadMacroProfile(key)
    end
})

if #listfiles(folder_name) == 0 then
    writefile(GetMacroProfilePath("Default Profile"),
              game:GetService("HttpService"):JSONEncode(MacroDefaultSettings))
end

RefreshMacroProfileList()
if #MacroProfileList == 0 then
    writefile(GetMacroProfilePath("Default Profile"),
              game:GetService("HttpService"):JSONEncode(MacroDefaultSettings))
    RefreshMacroProfileList()
end

if not table.find(MacroProfileList, Settings.macro_profile) then
    Settings.macro_profile = MacroProfileList[1]
end

FocusMacroProfile(Settings.macro_profile)

local function SaveMacroProfile(profile_name)
    local profile = rawget(Macros, profile_name)
    if not profile or KP.profileErrors[profile_name] then return false end
    assert(KP.ValidProfileName(profile_name), "Invalid macro file name")
    -- All explicit edits remain pending after a failed write, including new profiles and offsets.
    KP.dirtyProfiles[profile_name] = true
    local ok, err = pcall(function()
        EnsureMacroProfileShape(profile)
        GetMacroProfileLeaderUnit(profile)
        writefile(GetMacroProfilePath(profile_name), game:GetService("HttpService"):JSONEncode({[profile_name] = profile}))
    end)
    if not ok then KP.Report("Macro save failed", err); return false end
    KP.dirtyProfiles[profile_name] = nil
    return true
end

function KP.flushMacros()
    for name in pairs(KP.dirtyProfiles) do SaveMacroProfile(name) end
end
function KP.MarkMacroDirty(name)
    KP.dirtyProfiles[name] = true
    if KP.savePending then return end
    KP.savePending = true
    -- Checkpoint at most once per second, detached from recording cancellation.
    local thread = coroutine.running()
    local context = KP.contexts[thread]
    KP.contexts[thread] = nil
    task.delay(1, function()
        KP.savePending = false
        if ScriptAlive() then KP.flushMacros() end
    end)
    KP.contexts[thread] = context
end
function Save()
    local ok, err = pcall(function()
        writefile(SettingsFile, game:GetService("HttpService"):JSONEncode(Settings))
    end)
    if not ok then KP.Report("Settings save failed", err) end
    -- Explicit edits still flush the selected profile. Recording uses checkpoints.
    if Settings.macro_profile then SaveMacroProfile(Settings.macro_profile) end
end
for k, v in pairs(DefaultSettings) do
    if Settings[k] == nil then Settings[k] = type(v) == "table" and DeepCopy(v) or v end
end

local removedDefaultAbilityUnits = {
    "Merlin", "Rayleigh", "Six Eyes Gojo", "Gojo7", "Satorou Gojou", "Satorou Gojo"
}
for _, unitName in pairs(removedDefaultAbilityUnits) do
    if Settings.auto_buff_units and Settings.auto_buff_units[unitName] then
        Settings.auto_buff_units[unitName] = nil
    end
end
if Settings.macro_ability_blacklist then
    for _, unitName in pairs(removedDefaultAbilityUnits) do
        local index = table.find(Settings.macro_ability_blacklist, unitName)
        while index do
            table.remove(Settings.macro_ability_blacklist, index)
            index = table.find(Settings.macro_ability_blacklist, unitName)
        end
    end
end

-- Migrate old orange webhook color to crimson red
if Settings.webhook_color == "FF8700" then
    Settings.webhook_color = "B41E1E"
end
if Settings.fps_limit == nil or Settings.fps_limit == "" or (tonumber(Settings.fps_limit) and tonumber(Settings.fps_limit) < 15) then
    Settings.fps_limit = "60"
end
if Settings.anonymous_mode_name == nil or Settings.anonymous_mode_name == "" or Settings.anonymous_mode_name == "Anonymous" then
    Settings.anonymous_mode_name = "KarmaPanda"
end
if Settings.auto_target_enemy_type == "BOSS" then
    Settings.auto_target_enemy_type = "Boss"
end
if Settings.auto_target_ability_multi_name ~= nil then
    Settings.auto_target_ability_multi_name = nil
end
if Settings.auto_3x and Settings.auto_2x then
    Settings.auto_2x = false
end
if Settings.destroy_mode then
    Settings.destroy_mode = false
end
if Settings.ui_scale_initialized == nil then
    Settings.ui_scale_initialized = false
end
if Settings.ui_scale_safe_reset_once == nil then
    Settings.ui_scale_safe_reset_once = false
end
Settings.smart_macros = nil
Settings.smart_macro_bindings = nil
Settings.smart_join_exp_profile = nil
Settings.smart_join_exp_tickets_remaining =
    math.max(0, tonumber(Settings.smart_join_exp_tickets_remaining) or 0)
if not Settings.advanced_join_settings then
    Settings.smart_join_exp_active = false
    Settings.smart_join_exp_tickets_remaining = 0
end

Settings.version = version
Save()
print("[KarmaPanda:X] Filesystem Loaded: " .. os.clock() - benchmark_time)
benchmark_time = os.clock()

-- Game Helper Variables
local Player = game.Players.LocalPlayer
local GUI = Player.PlayerGui
local Mouse = Player:GetMouse()

-- Game Helper Functions
local function get_world()
    local worlds = {
        ["14657361824"] = -2, -- team event
        ["5552815761"] = -1, -- time chamber
        ["11574204578"] = 0,
        ["4996049426"] = 1,
        ["7785334488"] = 2
        -- ["11886211138"] = 3
    }
    return worlds[tostring(game.PlaceId)]
end

local function get_game_speed()
    local speed = game:GetService("ReplicatedStorage"):FindFirstChild("SpeedUP")
    return speed and speed.Value or nil
end

local function Delay(seconds, condition)
    local elapsed, previous = 0, tick()
    while elapsed < math.max(0, tonumber(seconds) or 0) and ScriptAlive() do
        if type(condition) == "function" and not condition() then return false end
        if condition == false then return false end
        task.wait(0.05)
        local now = tick()
        elapsed = elapsed + (now - previous) * (get_game_speed() or 1)
        previous = now
    end
    return ScriptAlive()
end

local function get_units()
    local units = {}
    local folder = workspace:FindFirstChild("Unit")
    if not folder then return units end
    for _, unit in ipairs(folder:GetChildren()) do
        local owner = unit:FindFirstChild("Owner")
        if owner and tostring(owner.Value) == Player.Name then table.insert(units, unit) end
    end
    return units
end

local CachedStats, OrbsV2Client, DataFolderClient

if get_world() ~= -1 and get_world() ~= -2 then
    CachedStats = require(Player.Backpack:WaitForChild("Framework")
                              :WaitForChild("CachedStats"))
    OrbsV2Client = require(game:GetService("ReplicatedStorage"):WaitForChild(
                               "Framework"):WaitForChild("OrbsV2Client"))
    DataFolderClient =
        require(game.ReplicatedStorage.Framework.DataFolderClient)
end

local function get_all_units()
    local units = {}

    if get_world() ~= -1 and get_world() ~= -2 then
        for k, v in pairs(
                        game:GetService("ReplicatedStorage").Unit:GetChildren()) do
            if v.Name ~= "PackageLink" then
                table.insert(units, v.Name)
            end
        end
    end

    return units
end

local function get_stat(unit_name) return CachedStats.getstat(unit_name) end

local function get_unit_from_gui(unit_name)
    local UnitGUI = GUI:FindFirstChild("HUD"):FindFirstChild("BottomFrame")
                        :FindFirstChild("Unit")

    for _, v in pairs(UnitGUI:GetChildren()) do
        if v.ClassName == "Frame" then
            local u = v:FindFirstChild("Unit")
            if u and UnitVariantNamesMatch(u.Value, unit_name) then return v end
        end
    end

    return nil
end

local function get_loadout_units()
    local names = {}
    local seen = {}
    pcall(function()
        local UnitGUI = GUI:FindFirstChild("HUD"):FindFirstChild("BottomFrame")
                            :FindFirstChild("Unit")
        if UnitGUI then
            for _, v in pairs(UnitGUI:GetChildren()) do
                if v.ClassName == "Frame" then
                    local u = v:FindFirstChild("Unit")
                    if u and u.Value and u.Value ~= "" and not seen[u.Value] then
                        table.insert(names, u.Value)
                        seen[u.Value] = true
                    end
                end
            end
        end
    end)
    return names
end

local function ResolveEquippedUnitName(unitName)
    local loadoutUnits = get_loadout_units()
    for _, equippedName in ipairs(loadoutUnits) do
        if equippedName == unitName then return equippedName end
    end
    for _, equippedName in ipairs(loadoutUnits) do
        if UnitVariantNamesMatch(equippedName, unitName) then return equippedName end
    end
    return unitName
end

local function get_summon_cost(unit_name)
    local cost = get_stat(unit_name)["Cost"]
    local discount = 0
    local unit = get_unit_from_gui(unit_name)

    if unit == nil then
        local orb = OrbsV2Client.GetAssignedOrbForUnit(unit_name)

        if orb ~= nil then
            local orb_stats = CachedStats.getOrbStat(orb)

            if orb_stats ~= nil then
                if orb_stats["InitialCost"] ~= nil then
                    discount = orb_stats["InitialCost"]
                end
                if orb_stats["InitialPercentageCost"] ~= nil then
                    cost = cost * orb_stats["InitialPercentageCost"]
                end
            end
        end

        return cost - discount
    else
        local image_label = unit:FindFirstChild("ImageLabel")

        if image_label ~= nil then
            local text_label = image_label:FindFirstChild("TextLabel")

            if text_label ~= nil then cost = convert(text_label.Text) end
        end

        return cost
    end
end

local function get_upgrade_cost(unit_name, level)
    local unit = get_stat(unit_name)

    if unit ~= nil then
        local upgrades = unit["Upgrade"]

        if upgrades[level] == nil then
            return 0
        else
            local cost = upgrades[level]["Cost"]
            local unit = get_unit_from_gui(unit_name)

            if unit ~= nil then
                local id = unit:FindFirstChild("ID")

                if id ~= nil then
                    local orb = OrbsV2Client.GetAssignedOrbForUnit(id.Value)
                    if orb ~= nil then
                        local orb_stats = CachedStats.getOrbStat(orb)

                        if orb_stats ~= nil then
                            if orb_stats["InitialPercentageCost"] ~= nil then
                                cost = cost * orb_stats["InitialPercentageCost"]
                            end
                        end
                    end
                end
            end

            return cost
        end
    else
        return 0 -- cannot find unit with get_stat
    end
end

local function get_max_upgrade_level(unit_name)
    return #get_stat(unit_name)["Upgrade"]
end

local function get_money()
    local money = Player:FindFirstChild("Money")
    return money and tonumber(money.Value) or 0
end

local function get_wave()
    local WaveValue = game:GetService("ReplicatedStorage"):FindFirstChild(
                          "WaveValue")
    local wave = 0
    if WaveValue ~= nil then wave = WaveValue.Value end
    return wave
end

KP.enemies = {list = {}, indices = {}, folder = nil, connections = {}}
function KP.BindEnemies()
    local index = KP.enemies
    local folder = workspace:FindFirstChild("Enemies")
    if folder == index.folder then return index end
    for _, conn in ipairs(index.connections) do KP.Disconnect(conn) end
    for _, enemy in ipairs(index.list) do if KP.releaseEnemy then KP.releaseEnemy(enemy) end end
    index.connections, index.list, index.indices = {}, {}, {}
    index.folder = folder
    local function added(enemy)
        if index.indices[enemy] then return end
        table.insert(index.list, enemy)
        index.indices[enemy] = #index.list
    end
    local function removed(enemy)
        local i = index.indices[enemy]
        if not i then return end
        local last = index.list[#index.list]
        index.list[i] = last
        index.indices[last] = i
        index.list[#index.list] = nil
        index.indices[enemy] = nil
        if KP.releaseEnemy then KP.releaseEnemy(enemy) end
    end
    if folder then
        table.insert(index.connections, TrackConnection(folder.ChildAdded:Connect(added)))
        table.insert(index.connections, TrackConnection(folder.ChildRemoved:Connect(removed)))
        for _, enemy in ipairs(folder:GetChildren()) do added(enemy) end
    end
    return index
end
local function get_enemy_count() return #KP.BindEnemies().list end
TrackConnection(workspace.ChildAdded:Connect(function(child)
    if child.Name == "Enemies" then
        KP.BindEnemies()
        if KP.syncEnemyVisuals then KP.syncEnemyVisuals() end
    end
end))
TrackConnection(workspace.ChildRemoved:Connect(function(child)
    if child == KP.enemies.folder then
        KP.BindEnemies()
        if KP.syncEnemyVisuals then KP.syncEnemyVisuals() end
    end
end))
KP.BindEnemies()

local function get_gems()
    if DataFolderClient ~= nil then
        return DataFolderClient.Get("Gems")
    else
        return nil
    end
end

local function get_gold()
    if DataFolderClient ~= nil then
        return DataFolderClient.Get("Gold")
    else
        return nil
    end
end

local function get_stardust()
    if DataFolderClient ~= nil then
        return DataFolderClient.Get("StardustStone")
    else
        return nil
    end
end

local function get_gauntlet_amount()
    local amount = nil
    pcall(function()
        local hud = GUI and GUI:FindFirstChild("HUD")
        local shop = hud and hud:FindFirstChild("GauntletShop")
        local bg = shop and shop:FindFirstChild("BG")
        local amountFrame = bg and bg:FindFirstChild("Amount")
        local label = amountFrame and amountFrame:FindFirstChild("TextLabel")
        if label and tostring(label.Text or "") ~= "" then
            amount = tostring(label.Text)
        end
    end)
    return amount
end

local function get_level()
    if DataFolderClient ~= nil then
        return DataFolderClient.Get("Level")
    else
        return nil
    end
end

local function get_battle_pass_tier()
    local bp_tier = "nil"

    pcall(function()
        bp_tier = GUI.TowerPassRewards.Main.Page.Main.Top.CurrentTierBox.Tier
                      .Text
    end)

    return bp_tier
end

local function is_lobby()
    local lobby = game.ReplicatedStorage:FindFirstChild("Lobby")
    if lobby then return lobby.Value == true end
    return get_world() ~= nil
end

local function get_number_missions()
    if get_world() ~= -1 and get_world() ~= -2 then
        return #game.ReplicatedStorage.Remotes.Server:InvokeServer("Mission")
    else
        return 204
    end
end

local function GetInventory()
    return game.ReplicatedStorage.Remotes.Server:InvokeServer("Data", "Units")
end

local function GetStorageItemCounts()
    local counts = {}
    local ready = false
    pcall(function()
        local hud = GUI and GUI:FindFirstChild("HUD")
        local storageMenu = hud and hud:FindFirstChild("StorageMenu")
        local page = storageMenu and storageMenu:FindFirstChild("Page")
        local main = page and page:FindFirstChild("Main")
        local bottom = main and main:FindFirstChild("Bottom")
        local items = bottom and bottom:FindFirstChild("Items")
        if not items then return end
        ready = true

        for _, card in ipairs(items:GetChildren()) do
            if card:IsA("GuiObject") and not string.find(string.lower(card.Name), "template", 1, true) then
                local itemName = tostring(card:GetAttribute("Name") or card.Name or "")
                local amountLabel = card:FindFirstChild("Amount", true)
                local amountText = amountLabel and tostring(amountLabel.Text or "") or ""
                local amount = tonumber((amountText:gsub(",", ""):match("%d+"))) or 1
                if itemName ~= "" and amount > 0 then
                    counts[itemName] = math.max(counts[itemName] or 0, amount)
                end
            end
        end
    end)
    return counts, ready
end

function KP_FormatRewardList(items)
    local text = table.concat(items, ", ")
    if #text > 1000 then text = string.sub(text, 1, 997) .. "..." end
    return text
end

local function UnequipUnit(unitName)
    game:GetService("ReplicatedStorage").Remotes.Input:FireServer("Unequip", {Stats = unitName})
    task.wait(0.3)
end

local function EquipUnit(unitID, unitLevel, unitName)
    local statsJson = game:GetService("HttpService"):JSONEncode({
        ID = unitID,
        Level = unitLevel,
        Name = unitName
    })
    game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer("Equip", {Stats = statsJson})
    task.wait(0.2)
    game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer("Data", "CurrentEquipSlot")
    task.wait(0.1)
    game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer("Data", "Unit_Equip")
    task.wait(0.2)
end

local function GetCurrentEquippedUnits()
    local equipped = {}
    pcall(function()
        local equipData = game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer("Data", "Unit_Equip")
        if equipData then
            for _, v in pairs(equipData) do
                if v.Name then
                    table.insert(equipped, v.Name)
                end
            end
        end
    end)
    return equipped
end

local function GetCurrentLeaderUnit()
    local leader = ""
    pcall(function()
        local hud = Player:FindFirstChild("PlayerGui") and Player.PlayerGui:FindFirstChild("HUD")
        local bottom = hud and hud:FindFirstChild("BottomFrame")
        local unitFrame = bottom and bottom:FindFirstChild("Unit")
        local slotOne = unitFrame and unitFrame:FindFirstChild("One")
        local unitValue = slotOne and slotOne:FindFirstChild("Unit")
        if unitValue and unitValue:IsA("StringValue") and tostring(unitValue.Value or "") ~= "" then
            leader = tostring(unitValue.Value)
        end
    end)
    if leader ~= "" then return leader end

    pcall(function()
        local equipData = game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer("Data", "Unit_Equip")
        if type(equipData) ~= "table" then return end

        if type(equipData[1]) == "table" and equipData[1].Name then
            leader = tostring(equipData[1].Name)
            return
        end

        local bestSlot = math.huge
        for slot, unitData in pairs(equipData) do
            local slotNumber = tonumber(slot)
            if slotNumber and slotNumber < bestSlot and type(unitData) == "table" and unitData.Name then
                bestSlot = slotNumber
                leader = tostring(unitData.Name)
            end
        end
    end)
    return leader
end

local function EquipMacroUnits()
    local profile = GetActiveMacroProfile()
    if not profile or not profile["Units"] then
        ShowNotify("Auto Equip", "No units found in the selected macro profile.")
        return
    end
    local leaderUnit = GetMacroProfileLeaderUnit(profile)

    local macroUnits = get_keys(profile["Units"])
    if #macroUnits == 0 then
        if leaderUnit ~= "" then
            table.insert(macroUnits, leaderUnit)
        else
            ShowNotify("Auto Equip", "No units found in the selected macro profile.")
            return
        end
    end
    table.sort(macroUnits)
    if leaderUnit ~= "" and not FindUnitVariantInList(macroUnits, leaderUnit) then
        table.insert(macroUnits, 1, leaderUnit)
    end

    -- Get player inventory
    local inventory = GetInventory()
    if not inventory then
        ShowNotify("Auto Equip", "Could not read inventory.")
        return
    end

    -- Build lookup: find the best (highest level) version of each needed unit
    local bestUnits = {}  -- unitName -> {ID, Level, Name}
    for _, macroName in ipairs(macroUnits) do
        for _, item in pairs(inventory) do
            if UnitVariantNamesMatch(macroName, item.Name) then
                if not bestUnits[macroName] or
                    (item.Level or 0) > (bestUnits[macroName].Level or 0) then
                    bestUnits[macroName] = {
                        ID = item.ID,
                        Level = item.Level or 1,
                        Name = item.Name
                    }
                end
            end
        end
    end

    -- Check for missing units
    local missing = {}
    for _, name in pairs(macroUnits) do
        if not bestUnits[name] then
            table.insert(missing, name)
        end
    end

    if #missing > 0 then
        ShowNotify("Missing Units", "You do not have: ")
        -- Still equip the ones we do have
    end

    -- Unequip all current units first
    local currentEquipped = GetCurrentEquippedUnits()
    for _, name in pairs(currentEquipped) do
        UnequipUnit(name)
    end
    task.wait(0.5)

    if leaderUnit and leaderUnit ~= "" then
        local leaderIndex = FindUnitVariantInList(macroUnits, leaderUnit)
        if leaderIndex and leaderIndex > 1 then
            table.remove(macroUnits, leaderIndex)
            table.insert(macroUnits, 1, leaderUnit)
        end
    end

    -- Equip macro units
    local equipped = {}
    for _, name in pairs(macroUnits) do
        if bestUnits[name] then
            local unit = bestUnits[name]
            EquipUnit(unit.ID, unit.Level, unit.Name)
            table.insert(equipped, name)
        end
    end

    if #equipped > 0 then
        ShowNotify("Auto Equip", "Equipped ")
    end
end

local function get_game_status()
    local status = GUI.HUD:WaitForChild("MissionEnd"):WaitForChild("BG")
                       :WaitForChild("Status"):WaitForChild("Status")

    return status.Text
end

local function get_stage()
    local stage = "N/A"
    pcall(function()
        local smv = game:GetService("ReplicatedStorage"):FindFirstChild("STORYMODE_VALUE")
        if smv then
            local val = tonumber(smv.Value) or 0

            -- Tower floors: -100001 = floor 1, -100050 = floor 50, -100100 = floor 100
            if val <= -100001 then
                local floor = math.abs(val) - 100000
                stage = "Tower Floor " .. tostring(floor)

            -- Story mode: positive numbers are story levels
            elseif val > 0 then
                stage = tostring(val) .. " - Story"

            -- Infinite mode maps
            elseif InfiniteMapTable[tostring(val)] then
                stage = InfiniteMapTable[tostring(val)] .. " - Infinite"

            -- Adventure / Raid maps
            elseif AdventureMapTable[tostring(val)] then
                stage = AdventureMapTable[tostring(val)] .. " - Adventure"

            -- Check with decimal keys (e.g. "-1.7")
            else
                -- Try matching against infinite map keys with decimals
                local found = false
                for k, v in pairs(InfiniteMapTable) do
                    if tonumber(k) == val then
                        stage = v .. " - Infinite"
                        found = true
                        break
                    end
                end
                if not found then
                    for k, v in pairs(AdventureMapTable) do
                        if tonumber(k) == val then
                            stage = v .. " - Adventure"
                            found = true
                            break
                        end
                    end
                end
                if not found then
                    stage = tostring(val)
                end
            end
        end
    end)
    return stage
end

local function get_world_teleporter()
    if 1 == get_world() then
        return game:GetService("Workspace").Queue["W2 PERM"].World2.Script115
    elseif 2 == get_world() then
        return game:GetService("Workspace").Script115
    end
end

_kpEnv.KP_SmartJoin = {}

function _kpEnv.KP_SmartJoin.GetTicketCount()
    local count = nil
    pcall(function()
        local hud = GUI:FindFirstChild("HUD")
        local bottom = hud and hud:FindFirstChild("BottomFrame")
        local currencies = bottom and bottom:FindFirstChild("CurrencyList")
        local tickets = currencies and currencies:FindFirstChild("Tickets")
        local frame = tickets and tickets:FindFirstChild("Frame")
        if not frame then return end

        count = 0
        for _, child in ipairs(frame:GetChildren()) do
            if child:IsA("GuiObject") and child.Visible and tonumber(child.Name) then
                count = count + 1
            end
        end
    end)
    return count
end

function _kpEnv.KP_SmartJoin.WaitForTicketCount(timeout, active)
    local deadline = tick() + (tonumber(timeout) or 5)
    repeat
        if not ScriptAlive() or (active and not active()) then return nil end
        local count = _kpEnv.KP_SmartJoin.GetTicketCount()
        if count ~= nil then return count end
        task.wait(0.2)
    until tick() >= deadline or not ScriptAlive() or (active and not active())
    return nil
end

function _kpEnv.KP_SmartJoin.EnterEXP(active)
    local function allowed() return ScriptAlive() and (not active or active()) end
    local character = Player.Character
    while not character and allowed() do task.wait(0.1); character = Player.Character end
    if not character or not allowed() then return false end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    local queue = workspace:FindFirstChild("Queue")
    local expFolder
    local building
    if queue then
        for _, child in ipairs(queue:GetChildren()) do
            if child.Name:lower():find("ticket and exp", 1, true) then
                local candidate = child:FindFirstChild("NEW EXP BUILDING MODE")
                if candidate then
                    expFolder = child
                    building = candidate
                    break
                end
            end
        end
    end
    building = building or (expFolder and expFolder:FindFirstChild("NEW EXP BUILDING MODE"))
    local trigger = building and building:FindFirstChild("Script834")
    if building and (not trigger or not trigger:IsA("BasePart")) then
        for _, desc in ipairs(building:GetDescendants()) do
            if desc:IsA("BasePart") and desc:FindFirstChildOfClass("TouchTransmitter") then
                trigger = desc
                break
            end
        end
    end

    root.CFrame = CFrame.new(
        -101.703415, 96.977684, -1514.18945,
        0, 0, 1,
        0, 1, 0,
        -1, 0, 0
    )
    task.wait(0.15)
    if not allowed() then return false end

    if trigger and trigger:IsA("BasePart") and firetouchinterest then
        firetouchinterest(root, trigger, 0)
        task.wait()
        firetouchinterest(root, trigger, 1)
    end
    return true
end

function _kpEnv.KP_SmartJoin.ControlsGameEnd()
    if not Settings.auto_join_game or not Settings.advanced_join_settings then return false end
    return Settings.smart_join_exp_active == true
end

function SmartJoinEndRouter()
    local runtime = _kpEnv.KP_Runtime
    if runtime.smartJoinEndRunning then return end
    runtime.smartJoinEndRunning = true

    local endGui = GUI.HUD:WaitForChild("MissionEnd")
    repeat task.wait(0.1) until not ScriptAlive() or endGui.Visible
    if not ScriptAlive() or not _kpEnv.KP_SmartJoin.ControlsGameEnd() then
        runtime.smartJoinEndRunning = false
        return
    end

    task.wait(1)
    local actions = endGui:WaitForChild("BG"):WaitForChild("Actions")
    local actionName = "Replay"

    if Settings.smart_join_exp_active then
        local tickets = _kpEnv.KP_SmartJoin.WaitForTicketCount(4)
        local remaining = math.max(0, tonumber(Settings.smart_join_exp_tickets_remaining) or
            tonumber(tickets) or 0)
        if remaining > 0 then remaining = remaining - 1 end
        if tickets ~= nil then remaining = math.min(remaining, tickets) end
        Settings.smart_join_exp_tickets_remaining = remaining
        if remaining <= 0 then
            Settings.smart_join_exp_active = false
            actionName = "Return"
        end
        Save()
    end

    local action = actions:FindFirstChild(actionName)
    if not action or not action.Visible then
        action = actions:FindFirstChild("Return")
    end
    if action then
        for _ = 1, 3 do
            if not ScriptAlive() or not endGui.Visible then break end
            pcall(function() firesignal(action.Activated) end)
            task.wait(1)
        end
    end

    runtime.smartJoinEndRunning = false
end

function KP.HasBuff(unit, name)
    local head = unit and unit:FindFirstChild("Head")
    local gui = head and head:FindFirstChild("EffectBBGUI")
    local frame = gui and gui:FindFirstChild("Frame")
    local icon = frame and frame:FindFirstChild(name)
    return icon ~= nil and icon.Visible == true
end
local function CheckAttackBuff(units)
    if #units == 0 then return false end
    for _, unit in ipairs(units) do if not KP.HasBuff(unit, "AttackImage") then return false end end
    return true
end
local function CheckRangeBuff(units)
    if #units == 0 then return false end
    for _, unit in ipairs(units) do if not KP.HasBuff(unit, "RangeImage") then return false end end
    return true
end
local function CheckStun(unit) return KP.HasBuff(unit, "StunImage") end

local function HideSummonGUI()
    while GUI:WaitForChild("HUD"):FindFirstChild("SUMMONGUI") ~= nil do
        local vim = game:GetService('VirtualInputManager')
        vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait()
        vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        task.wait(0.25)
    end
end

local StartTime = tick()
local TimeOffset = 0
local _lastTick = 0
local _timerReady = false
local AUTO_EXECUTE_LOADER = [==[
if not game:IsLoaded() then game.Loaded:Wait() end
local player = game:GetService("Players").LocalPlayer
if not player then return end
local ok, settings = pcall(function()
    return game:GetService("HttpService"):JSONDecode(readfile("KarmaPanda/ASTD/Settings/" .. player.UserId .. ".json"))
end)
if ok and type(settings) == "table" and settings.auto_execute then
    local loaded, err = pcall(function()
        local source = readfile("KarmaPanda/ASTD/runtime.lua")
        local fn, compileError = loadstring(source, "KarmaPanda ASTD")
        assert(fn, compileError)
        fn()
    end)
    if not loaded then warn("[KarmaPanda:X] Auto Execute: " .. tostring(err)) end
end
]==]
local AutoExecuteBound = false
local AutoExecuteQueued = false

local _resolvedQueueOnTeleport
do
    local function tryResolve()
        if type(queue_on_teleport) == "function" then return queue_on_teleport end
        if type(queueonteleport) == "function" then return queueonteleport end
        if syn and type(syn) == "table" and type(syn.queue_on_teleport) == "function" then return syn.queue_on_teleport end
        if fluxus and type(fluxus) == "table" and type(fluxus.queue_on_teleport) == "function" then return fluxus.queue_on_teleport end
        if getgenv and type(getgenv()) == "table" then
            local g = getgenv()
            if type(g.queue_on_teleport) == "function" then return g.queue_on_teleport end
            if type(g.queueonteleport) == "function" then return g.queueonteleport end
        end
        return nil
    end
    _resolvedQueueOnTeleport = tryResolve()
end

local function ElapsedTime()
    local wave = get_wave()
    if wave > 0 and _timerReady then
        return (tick() - StartTime) + TimeOffset
    end
    return 0
end

local function CalculateTimeOffset()
    task.spawn(function()
        while ScriptAlive() do
            TimeOffset = 0
            _lastTick = 0
            _timerReady = false
            repeat task.wait() until not ScriptAlive() or
                (get_game_speed() ~= nil and get_wave() > 0)
            if not ScriptAlive() then break end

            StartTime = tick()
            _lastTick = tick()
            _timerReady = true

            while ScriptAlive() and get_wave() > 0 do
                local now = tick()
                local dt = now - _lastTick
                _lastTick = now
                local speed = get_game_speed()
                TimeOffset = TimeOffset + (dt * ((tonumber(speed) or 1) - 1))
                task.wait(0.015)
            end
        end
    end)
end

local function GetQueueOnTeleport()
    if type(_resolvedQueueOnTeleport) == "function" then
        return _resolvedQueueOnTeleport
    end
    if type(queue_on_teleport) == "function" then
        _resolvedQueueOnTeleport = queue_on_teleport
    elseif type(queueonteleport) == "function" then
        _resolvedQueueOnTeleport = queueonteleport
    end
    return _resolvedQueueOnTeleport
end

local function QueueAutoExecute(force)
    local queueTeleport = GetQueueOnTeleport()
    if not queueTeleport then return false end
    if not isfile(KP.runtimeSourcePath) then
        KP.Report("Auto Execute", "Local runtime is missing. Run the complete updated script once to install it.")
        return false
    end
    if not force and _kpEnv.KP_AutoExecuteQueuedJobId == game.JobId then
        AutoExecuteQueued = true
        return true
    end

    local success = pcall(queueTeleport, AUTO_EXECUTE_LOADER)
    if success then
        AutoExecuteQueued = true
        _kpEnv.KP_AutoExecuteQueuedJobId = game.JobId
    end
    return success
end

local function BindAutoExecute()
    if AutoExecuteBound then return end
    AutoExecuteBound = true
    TrackConnection(game:GetService("Players").LocalPlayer.OnTeleport:Connect(function()
        KP.flushMacros()
        AutoExecuteQueued = false
        if Settings and Settings.auto_execute then
            task.defer(function() QueueAutoExecute(false) end)
        end
    end))
end

local function SendWebhook(fields, force_ping)
    local webhookUrl = tostring(Settings.webhook_url or "")
    if webhookUrl == "" or not webhookUrl:match("^https?://") then return false end

    local status, error_message = pcall(function()
        local request = request or http_request or (http and http.request) or
                            (syn and syn.request)
        if type(request) ~= "function" then return false end

        local content = {}

        if Settings.webhook_user_name then
            table.insert(content, {
                ["name"] = "Username",
                ["value"] = "||" .. Player.Name .. "||"
            })
        end

        content = TableConcat(content, fields)

        local ping_message = ""

        local should_ping = Settings.webhook_ping_user or (force_ping and Settings.webhook_ping_on_lose)
        if Settings.webhook_discord_id ~= "" and should_ping then
            ping_message = "<@" .. Settings.webhook_discord_id .. ">"
        end

        request({
            Url = webhookUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = game:GetService("HttpService"):JSONEncode({
                ["content"] = ping_message,
                ["embeds"] = {
                    {
                        ["author"] = {
                            ["name"] = "KarmaPanda",
                            ["url"] = "https://discord.gg/UDrvUguuNU",
                            -- If this doesn't show, right-click image on imgur -> Copy Image Address and paste here
                            ["icon_url"] = "https://i.imgur.com/54Etjtw.png"
                        },
                        ["title"] = "discord.gg/UDrvUguuNU",
                        ["url"] = "https://discord.gg/UDrvUguuNU",
                        ["type"] = "rich",
                        ["color"] = tonumber(Settings.webhook_color, 16),
                        ["fields"] = content
                    }
                }
            })
        })
    end)

    if not status then return false end
end

-- https://www.lua.org/pil/11.4.html
Queue = {}
function Queue.new() return {first = 0, last = -1} end
function Queue.pushleft(list, value)
    local first = list.first - 1
    list.first = first
    list[first] = value
end
function Queue.pushright(list, value)
    local last = list.last + 1
    list.last = last
    list[last] = value
end
function Queue.popleft(list)
    local first = list.first
    if first > list.last then error("list is empty") end
    local value = list[first]
    list[first] = nil -- to allow garbage collection
    list.first = first + 1
    return value
end
function Queue.popright(list)
    local last = list.last
    if list.first > last then error("list is empty") end
    local value = list[last]
    list[last] = nil -- to allow garbage collection
    list.last = last - 1
    return value
end
function Queue.length(list) return (list.last - list.first) + 1 end

-- Action Queue
local Action_Queue = Queue.new()
local Upgrade_Counter = 0

local function ActionQueueHelper()
    while ScriptAlive() do
        local item = Queue.length(Action_Queue) > 0 and Queue.popleft(Action_Queue) or nil
        if item then
            if not item.Cancelled and KP.ContextAlive(item.Context) and (not item.ShouldContinue or item.ShouldContinue()) then
                KP.queueInFlight = item
                item.Started = true
                local ok, err = pcall(function()
                    if tostring(item.Method) == "Input" then
                        game.ReplicatedStorage.Remotes.Input:FireServer(table.unpack(item.Args, 1, item.Args.n or #item.Args))
                    elseif tostring(item.Method) == "Server" then
                        game.ReplicatedStorage.Remotes.Server:InvokeServer(table.unpack(item.Args, 1, item.Args.n or #item.Args))
                    end
                end)
                item.Done, item.Success = true, ok
                KP.queueInFlight = nil
                if not ok then KP.Report("Action " .. tostring(item.Args[1]), err) end
                task.wait(math.max(0, tonumber(Settings.action_queue_remote_fire_delay) or 0.25))
            else item.Done, item.Cancelled = true, true end
        else task.wait(0.03) end
    end
end
local function StartActionQueue()
    if KP.queueRunning then return end
    KP.queueRunning = true
    local ok, err = pcall(ActionQueueHelper)
    KP.queueRunning = false
    if not ok then KP.Report("Action queue", err) end
end
local function AddToQueue(remote_method, remote_args)
    local context = KP.contexts[coroutine.running()]
    if not KP.ContextAlive(context) then return false end
    if Queue.length(Action_Queue) >= 256 then
        KP.Report("Action queue", "Queue full; request rejected instead of accumulating indefinitely")
        return false
    end
    local item = {Method = remote_method, Args = remote_args, Context = context}
    Queue.pushright(Action_Queue, item)
    return true, item
end
function KP.DiscardQueued(context)
    local kept = Queue.new()
    while Queue.length(Action_Queue) > 0 do
        local item = Queue.popleft(Action_Queue)
        if item.Context ~= context then Queue.pushright(kept, item) else item.Done, item.Cancelled = true, true end
    end
    Action_Queue = kept
end

_kpEnv.KP_Runtime.macroPlacement = {base = {}, hill = {}, restrictions = {}, nextRefresh = 0}
MacroPlacement = _kpEnv.KP_Runtime.macroPlacement

function MacroPlacement.PointInPartXZ(part, position, margin)
    if not part or not part.Parent then return false end
    local localPos = part.CFrame:PointToObjectSpace(position)
    local half = part.Size * 0.5
    margin = margin or 0
    return math.abs(localPos.X) <= half.X + margin and math.abs(localPos.Z) <= half.Z + margin
end

function MacroPlacement.ClampPointToPart(part, position, pad)
    local localPos = part.CFrame:PointToObjectSpace(position)
    local half = part.Size * 0.5
    pad = pad or 0.35
    local xLimit = math.max(0, half.X - pad)
    local zLimit = math.max(0, half.Z - pad)
    local x = math.clamp(localPos.X, -xLimit, xLimit)
    local z = math.clamp(localPos.Z, -zLimit, zLimit)
    return part.CFrame:PointToWorldSpace(Vector3.new(x, localPos.Y, z))
end

function MacroPlacement.DistanceToPartEdgeXZ(part, position)
    if not part or not part.Parent then return 0 end
    local localPos = part.CFrame:PointToObjectSpace(position)
    local half = part.Size * 0.5
    return math.min(half.X - math.abs(localPos.X), half.Z - math.abs(localPos.Z))
end

function MacroPlacement.AddRestriction(list, instance)
    if not instance then return end
    if instance:IsA("BasePart") then
        table.insert(list, instance)
        return
    end
    for _, desc in ipairs(instance:GetDescendants()) do
        if desc:IsA("BasePart") then
            table.insert(list, desc)
        end
    end
end

function MacroPlacement.Refresh()
    local now = tick()
    if now < (MacroPlacement.nextRefresh or 0) and
        (#MacroPlacement.base > 0 or #MacroPlacement.hill > 0) then
        return
    end
    MacroPlacement.nextRefresh = now + 2
    MacroPlacement.base = {}
    MacroPlacement.hill = {}
    MacroPlacement.restrictions = {}

    local placeable = workspace:FindFirstChild("Placeable")
    if placeable then
        for _, desc in ipairs(placeable:GetDescendants()) do
            if desc:IsA("BasePart") then
                local kind = nil
                local cur = desc
                while cur and cur ~= placeable do
                    local name = string.lower(tostring(cur.Name))
                    if name:find("hill", 1, true) or name:find("air", 1, true) then
                        kind = "hill"
                        break
                    elseif name:find("base", 1, true) then
                        kind = "base"
                    end
                    cur = cur.Parent
                end
                if kind == "hill" then
                    table.insert(MacroPlacement.hill, desc)
                elseif kind == "base" then
                    table.insert(MacroPlacement.base, desc)
                end
            end
        end
    end

    pcall(function()
        local CollectionService = game:GetService("CollectionService")
        for _, inst in ipairs(CollectionService:GetTagged("Restriction")) do
            MacroPlacement.AddRestriction(MacroPlacement.restrictions, inst)
        end
    end)

    local camera = workspace:FindFirstChild("Camera") or workspace.CurrentCamera
    if camera then
        for _, desc in ipairs(camera:GetDescendants()) do
            local name = string.lower(tostring(desc.Name))
            if name:find("restriction", 1, true) then
                MacroPlacement.AddRestriction(MacroPlacement.restrictions, desc)
            end
        end
    end
end

function MacroPlacement.IsRestricted(position)
    for _, part in ipairs(MacroPlacement.restrictions or {}) do
        if MacroPlacement.PointInPartXZ(part, position, 0.25) then
            return true
        end
    end
    return false
end

function MacroPlacement.IsOccupied(position)
    local units = workspace:FindFirstChild("Unit")
    if not units then return false end
    for _, unit in ipairs(units:GetChildren()) do
        local hrp = unit:FindFirstChild("HumanoidRootPart")
        if hrp then
            local delta = hrp.Position - position
            if math.abs(delta.Y) <= 14 then
                local footprint = hrp:FindFirstChild("Part1")
                if footprint and footprint:IsA("BasePart") then
                    if MacroPlacement.PointInPartXZ(footprint, position, 0.55) then
                        return true
                    end
                elseif Vector3.new(delta.X, 0, delta.Z).Magnitude <= 1.25 then
                    return true
                end
            end
        end
    end
    return false
end

function MacroPlacement.IsNearFailedPosition(position, failedPositions)
    for _, failed in ipairs(failedPositions or {}) do
        local delta = position - failed
        if math.abs(delta.Y) <= 14 and Vector3.new(delta.X, 0, delta.Z).Magnitude <= 1.25 then
            return true
        end
    end
    return false
end

function MacroPlacement.IsAllowedOnPart(part, position)
    return MacroPlacement.PointInPartXZ(part, position, 0.05) and
        not MacroPlacement.IsRestricted(position) and
        not MacroPlacement.IsOccupied(position)
end

function MacroPlacement.GetNearestDistance(parts, position)
    local best = math.huge
    for _, part in ipairs(parts or {}) do
        local point = MacroPlacement.ClampPointToPart(part, position)
        local delta = point - position
        local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
        if distance < best then best = distance end
    end
    return best
end

function MacroPlacement.GetKind(unitName, position)
    MacroPlacement.Refresh()
    for _, part in ipairs(MacroPlacement.hill) do
        if MacroPlacement.PointInPartXZ(part, position, 0.05) then return "hill" end
    end
    for _, part in ipairs(MacroPlacement.base) do
        if MacroPlacement.PointInPartXZ(part, position, 0.05) then return "base" end
    end

    local statKind = nil
    pcall(function()
        local stat = get_stat(unitName)
        for key, value in pairs(stat or {}) do
            local keyText = string.lower(tostring(key))
            local valueText = string.lower(tostring(value))
            if keyText:find("place", 1, true) then
                if valueText == "hill" or valueText == "air" or valueText == "hybrid" then
                    statKind = "hill"
                    break
                elseif valueText == "ground" or valueText == "base" then
                    statKind = "base"
                    break
                end
            end
        end
    end)
    if statKind then return statKind end

    local baseDistance = MacroPlacement.GetNearestDistance(MacroPlacement.base, position)
    local hillDistance = MacroPlacement.GetNearestDistance(MacroPlacement.hill, position)
    if hillDistance < baseDistance then return "hill" end
    return "base"
end

function MacroPlacement.ResolveCFrame(unitName, cframe, forceMove, failedPositions)
    if type(cframe) == "string" then cframe = StringToCFrame(cframe) end
    if typeof(cframe) ~= "CFrame" then return cframe, false end

    local position = cframe.Position
    local kind = MacroPlacement.GetKind(unitName, position)
    local parts = kind == "hill" and MacroPlacement.hill or MacroPlacement.base
    if #parts == 0 then return cframe, false end

    for _, part in ipairs(parts) do
        if MacroPlacement.IsAllowedOnPart(part, position) and
            not MacroPlacement.IsNearFailedPosition(position, failedPositions) and
            not forceMove then
            return cframe, false
        end
    end

    local bestPoint = nil
    local bestScore = math.huge
    local offsets = forceMove and {0, 2.5, -2.5, 5, -5, 7.5, -7.5} or {0, 2.5, -2.5, 5, -5}

    for _, part in ipairs(parts) do
        local clamped = MacroPlacement.ClampPointToPart(part, position)
        local localClamped = part.CFrame:PointToObjectSpace(clamped)
        for _, ox in ipairs(offsets) do
            for _, oz in ipairs(offsets) do
                if not forceMove or ox ~= 0 or oz ~= 0 then
                    local candidate = part.CFrame:PointToWorldSpace(Vector3.new(
                        localClamped.X + ox,
                        localClamped.Y,
                        localClamped.Z + oz
                    ))
                    candidate = MacroPlacement.ClampPointToPart(part, candidate)
                    if MacroPlacement.IsAllowedOnPart(part, candidate) and
                        not MacroPlacement.IsNearFailedPosition(candidate, failedPositions) then
                        local delta = candidate - position
                        local score = Vector3.new(delta.X, 0, delta.Z).Magnitude
                        if score < bestScore then
                            bestScore = score
                            bestPoint = candidate
                        end
                    end
                end
            end
        end
    end

    if not bestPoint then return cframe, false end
    return CFrame.new(bestPoint) * (cframe - cframe.Position), true
end

local function SummonUnit(rotation, cframe, unit_name, correctPlaybackPlacement, placementOptions)
    local context = KP.contexts[coroutine.running()]
    local function active()
        return KP.ContextAlive(context) and not (KP.MissionEnded and KP.MissionEnded())
    end
    local status, resultUnit, resultCFrame, resultPlacedAt = pcall(function()
        if type(cframe) == "string" then cframe = StringToCFrame(cframe) end
        local summonName = ResolveEquippedUnitName(unit_name)
        placementOptions = type(placementOptions) == "table" and placementOptions or {}
        local activeCFrame = cframe
        local corrected = false
        local failedPositions = {}
        if correctPlaybackPlacement then
            activeCFrame, corrected = MacroPlacement.ResolveCFrame(summonName, activeCFrame, false, failedPositions)
        end
        local correctionAttempts = corrected and 1 or 0

        local summonedUnit = nil
        local summonedCFrame = nil
        local summonedAt = nil
        local unitFolder = workspace:FindFirstChild("Unit")
        while active() and not unitFolder do task.wait(0.05); unitFolder = workspace:FindFirstChild("Unit") end
        if not active() or not unitFolder then return nil, nil, nil end
        local knownUnits = correctPlaybackPlacement and setmetatable({}, {__mode = "k"}) or nil

        local function CheckUnitExist(unit)
            if knownUnits and knownUnits[unit] then return false end
            local owner = unit:FindFirstChild("Owner")
            local hrp = unit:FindFirstChild("HumanoidRootPart")

            if owner ~= nil and hrp ~= nil then
                local magnitude =
                    (activeCFrame.Position - hrp.CFrame.Position).magnitude

                local maxMagnitude = Settings.macro_magnitude
                if correctPlaybackPlacement then
                    maxMagnitude = math.max(2.5, tonumber(maxMagnitude) or 1)
                end

                if tostring(owner.Value) == Player.Name and
                    UnitVariantNamesMatch(unit.Name, unit_name) and
                    magnitude <= maxMagnitude then
                    summonedUnit = unit
                    summonedCFrame = hrp.CFrame
                    summonedAt = summonedAt or ElapsedTime()
                    return true
                end
            end

            return false
        end

        local function QueueSummon()
            AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input, {
                [1] = "Summon",
                [2] = {
                    ["Rotation"] = rotation,
                    ["cframe"] = activeCFrame,
                    ["Unit"] = summonName
                }
            })
        end

        local function ScanExistingUnits()
            for _, unit in pairs(unitFolder:GetChildren()) do
                if CheckUnitExist(unit) then return true end
            end
            return false
        end

        if Settings.macro_money_tracking then
            while active() and get_money() < get_summon_cost(summonName) do task.wait(0.05) end
        end
        if not active() then return nil, nil, nil end
        if knownUnits then
            for _, unit in pairs(unitFolder:GetChildren()) do
                knownUnits[unit] = true
            end
        end

        local summoned = false
        local connection = game:GetService("Workspace").Unit.ChildAdded:Connect(
                               function(unit)
                if CheckUnitExist(unit) then summoned = true end
            end)

        KP.TrackContextConnection(connection)
        QueueSummon()

        if correctPlaybackPlacement then
            local firstRetryDelay = corrected and 0.25 or
                math.min(tonumber(Settings.action_queue_remote_on_fail_delay) or 1, 0.5)
            local retryDelay = math.min(tonumber(Settings.action_queue_remote_on_fail_delay_loop) or 0.5, 0.35)
            local nextRetry = tick() + firstRetryDelay
            local deadlineSeconds = placementOptions.deadlineSeconds or math.max(2, math.min(8,
                (Settings.macro_playback_search_attempts or 60) *
                (Settings.macro_playback_search_delay or 0.1)))
            local maxCorrectionAttempts = placementOptions.maxCorrectionAttempts
            if maxCorrectionAttempts == nil then maxCorrectionAttempts = 2 end
            local retryOnFail = placementOptions.retryOnFail ~= false
            local deadline = tick() + deadlineSeconds
            while not summoned and active() and Settings.macro_playback and tick() < deadline do
                if Queue.length(Action_Queue) == 0 then
                    summoned = ScanExistingUnits()
                    if retryOnFail and not summoned and Settings.action_queue_remote_on_fail and tick() >= nextRetry then
                        table.insert(failedPositions, activeCFrame.Position)
                        if correctionAttempts < maxCorrectionAttempts then
                            local newCFrame, didCorrect = MacroPlacement.ResolveCFrame(summonName, activeCFrame, true, failedPositions)
                            if didCorrect then
                                activeCFrame = newCFrame
                                corrected = true
                                correctionAttempts = correctionAttempts + 1
                            end
                        end
                        QueueSummon()
                        nextRetry = tick() + retryDelay
                    end
                end
                task.wait(0.03)
            end
            KP.Disconnect(connection)
            return summonedUnit, summonedCFrame or activeCFrame, summonedAt
        elseif Settings.action_queue_remote_on_fail then
            task.spawn(function()
                task.wait(Settings.action_queue_remote_on_fail_delay)
                local retryCount = 0
                local maxRetries = placementOptions.maxDirectRetries
                if maxRetries ~= nil then maxRetries = math.max(0, tonumber(maxRetries) or 0) end
                local stopWithPlayback = placementOptions.stopWhenPlaybackStops == true
                while not summoned and active() and (not stopWithPlayback or Settings.macro_playback) do
                    if Queue.length(Action_Queue) == 0 then
                        summoned = ScanExistingUnits()
                        if not summoned then
                            if maxRetries ~= nil then
                                retryCount = retryCount + 1
                                if retryCount > maxRetries then break end
                            end
                            QueueSummon()
                        end
                    end
                    task.wait(Settings.action_queue_remote_on_fail_delay_loop)
                end
                KP.Disconnect(connection)
            end)
        else
            KP.Disconnect(connection)
        end
        return nil, activeCFrame, nil
    end)

    if not status then
        KP.Report("Summon", resultUnit)
        return nil, nil, nil
    end
    return resultUnit, resultCFrame, resultPlacedAt
end

local function UpgradeUnit(unit, upgrade_level)
    if not unit or not unit.Parent then return end
    local context = KP.contexts[coroutine.running()]
    local function active()
        return KP.ContextAlive(context) and not (KP.MissionEnded and KP.MissionEnded())
    end
    KP.upgradeWorkers = KP.upgradeWorkers or setmetatable({}, {__mode = "k"})
    local goal = math.min(tonumber(upgrade_level) or 0, get_max_upgrade_level(unit.Name))
    local tag = unit:FindFirstChild("UpgradeTag")
    if not tag or tag.Value >= goal then return end
    if Settings.macro_money_tracking then
        while active() and unit.Parent and tag.Parent and tag.Value < goal do
            local total = 0
            for level = tag.Value + 1, goal do total = total + get_upgrade_cost(unit.Name, level) end
            if get_money() >= total then break end
            task.wait(0.05)
        end
        if not active() or not unit.Parent or not tag.Parent then return end
    end
    local pending = KP.upgradeWorkers[unit]
    if pending and pending.context == context and not pending.done then pending.goal = math.max(pending.goal, goal); return end
    local worker = {goal = goal, context = context}
    KP.upgradeWorkers[unit] = worker
    task.spawn(function()
        local attempts, deadline = 0, tick() + 90
        while active() and unit.Parent and tag.Parent and tag.Value < worker.goal and tick() < deadline do
            if not Settings.macro_money_tracking or get_money() >= get_upgrade_cost(unit.Name, tag.Value + 1) then
                local old = tag.Value
                local ok, err = pcall(function() game.ReplicatedStorage.Remotes.Server:InvokeServer("Upgrade", unit) end)
                if not ok then KP.Report("Upgrade", err) end
                attempts = tag.Value > old and 0 or attempts + 1
                if (not Settings.action_queue_remote_on_fail and attempts > 0) or attempts >= math.max(1, Settings.macro_playback_search_attempts) then break end
                task.wait(tag.Value > old and 0.03 or math.max(0.1, Settings.action_queue_remote_on_fail_delay_loop))
            else task.wait(0.05) end
        end
        worker.done = true
        if KP.upgradeWorkers[unit] == worker then KP.upgradeWorkers[unit] = nil end
    end)
end

local function UseAbilityUnit(unit, ability_string, onDispatch, shouldContinue)
    if not unit then return end
    local context = KP.contexts[coroutine.running()]
    local function active() return KP.ContextAlive(context) and (not shouldContinue or shouldContinue()) end
    task.spawn(function()
        local special = unit:FindFirstChild("SpecialMove")
        local enabled = special and special:FindFirstChild("Special_Enabled2")
        if not enabled then return end
        local deadline = tick() + 90
        while unit.Parent and enabled.Parent and active() and (CheckStun(unit) or enabled.Value) and tick() < deadline do task.wait(0.03) end
        if not unit.Parent or not enabled.Parent or not active() or tick() >= deadline then return end
        local used = false
        local conn = KP.TrackContextConnection(enabled:GetPropertyChangedSignal("Value"):Connect(function()
            if enabled.Value then used = true end
        end), context)
        local retries = Settings.action_queue_remote_on_fail and math.max(1, Settings.macro_playback_search_attempts) or 1
        local notified = false
        for attempt = 1, retries do
            if not active() or not unit.Parent or used or tick() >= deadline then break end
            local accepted, request = AddToQueue(game.ReplicatedStorage.Remotes.Input, {"UseSpecialMove", unit, ability_string or ""})
            if accepted then
                if request and shouldContinue then request.ShouldContinue = active end
                -- Queue congestion is not a failed cast. Wait for this request's dispatch.
                while request and not request.Done and active() and unit.Parent and tick() < deadline do task.wait(0.03) end
                if not active() or not unit.Parent then
                    if request and not request.Done then request.Cancelled = true end
                    break
                end
                if request and not request.Done then request.Cancelled = true; break end
                if request and request.Cancelled then break end
                if onDispatch and not notified and (not request or request.Success) then
                    notified = true
                    local ok, err = pcall(onDispatch)
                    if not ok then KP.Report("Ability selection", err) end
                end
            end
            task.wait(math.max(0.05, attempt == 1 and Settings.action_queue_remote_on_fail_delay or Settings.action_queue_remote_on_fail_delay_loop))
            if enabled.Value then break end
        end
        KP.Disconnect(conn)
    end)
end

local function UseMultipleAbilitiesGUI(ability_name, shouldContinue)
    task.spawn(function()
        local function active() return ScriptAlive() and (not shouldContinue or shouldContinue()) end
        local function waitChild(parent, name)
            local deadline = tick() + 10
            while parent and active() and tick() < deadline do
                local child = parent:FindFirstChild(name)
                if child then return child end
                task.wait(0.05)
            end
        end
        local gui = waitChild(GUI, "MultipleAbilities")
        if not gui then return end
        local frame = waitChild(gui, "Frame")
        if not frame then return end
        local attempts = 0
        repeat task.wait(0.1); attempts = attempts + 1 until not active() or #frame:GetChildren() > 1 or attempts > 50
        task.wait(0.1)
        if not active() then return end
        for k, v in pairs(frame:GetChildren()) do
            if v.Name == "ImageButton" then
                local text = v:FindFirstChild("TextLabel")
                if text and text.Text == ability_name then
                    firesignal(v.Activated)
                    break
                end
            end
        end
    end)
end

local function UseKilluaWishesGUI(ability_name)
    task.spawn(function()
        local gui = GUI:WaitForChild("KilluaWishes", 10)
        if not gui then return end
        local Options = gui:WaitForChild("TextBackground"):WaitForChild(
                            "OptionsContainer")
        for k, v in pairs(Options:GetChildren()) do
            if v.Name == "Option" then
                if v.Text == ability_name then

                    -- TODO: Fix firesignal MouseButton1Click
                    pcall(function()
                        firesignal(v.MouseButton1Click)
                    end)
                    gui:Destroy()
                    break
                end
            end
        end
    end)
end

local function UseMultipleAbilitiesUnit(unit, ability_string, ability_name, shouldContinue)
    -- TODO: Add check to make sure that unit is leveled for ability
    UseAbilityUnit(unit, ability_string, function() UseMultipleAbilitiesGUI(ability_name, shouldContinue) end, shouldContinue)
end

local function ActivateAutoAbilityUnit(unit, ability_string, toggled)
    AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input,
               {[1] = "AutoToggle", [2] = unit, [3] = toggled})
    if toggled then UseAbilityUnit(unit, ability_string) end
end

KP.priorityNames = {"PriorityAttack", "Priority", "PriorityValue", "TargetPriority", "AttackPriority", "Targeting"}
function KP.ReadPriority(unit, preferred)
    if not unit then return nil end
    local function read(name)
        local value = unit:FindFirstChild(name, true)
        if value and value:IsA("ValueBase") then return value.Value, name, value end
        local attribute = unit:GetAttribute(name)
        if attribute ~= nil then return attribute, name, nil end
        return nil
    end
    if preferred then
        local value, name, object = read(preferred)
        if value ~= nil then return value, name, object end
    end
    for _, name in ipairs(KP.priorityNames) do
        local value, key, object = read(name)
        if value ~= nil then return value, key, object end
    end
    return nil
end
local function ChangePriorityUnit(unit, parameter)
    if not unit or not unit.Parent then return end
    local context = KP.contexts[coroutine.running()]
    local desired = parameter and parameter.Priority
    if desired == nil then
        -- Older files contain a relative cycle rather than an absolute priority.
        AddToQueue(game.ReplicatedStorage.Remotes.Input, {"ChangePriority", unit})
        return
    end
    do
        local seen = {}
        for _ = 1, 16 do
            if not KP.ContextAlive(context) or not unit.Parent then return end
            local value = KP.ReadPriority(unit, parameter.PriorityField)
            if value == nil then
                KP.Report("Priority playback", "Recorded priority field is unavailable on " .. unit.Name)
                return
            end
            if tostring(value) == tostring(desired) then return end
            if seen[tostring(value)] then break end
            seen[tostring(value)] = true
            local accepted, request = AddToQueue(game.ReplicatedStorage.Remotes.Input, {"ChangePriority", unit})
            if not accepted then return end
            -- A congested queue is not an unchanged priority response: time the response after dispatch.
            local dispatchDeadline = tick() + 90
            while request and not request.Done and KP.ContextAlive(context) and unit.Parent and
                not (KP.MissionEnded and KP.MissionEnded()) and tick() < dispatchDeadline do task.wait(0.03) end
            if not KP.ContextAlive(context) or not unit.Parent or (KP.MissionEnded and KP.MissionEnded()) then
                if request and not request.Done then request.Cancelled = true end
                return
            end
            if request and (not request.Done or request.Cancelled or not request.Success) then
                if not request.Done then request.Cancelled = true end
                KP.Report("Priority playback", "Priority request failed or did not dispatch before the timeout")
                return
            end
            local deadline = tick() + 3
            repeat
                task.wait(0.03)
                if not KP.ContextAlive(context) or not unit.Parent then return end
            until KP.ReadPriority(unit, parameter.PriorityField) ~= value or tick() >= deadline
        end
        KP.Report("Priority playback", "Could not reach priority " .. tostring(desired) .. " on " .. unit.Name)
    end
end

local function SellUnit(unit)
    AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input,
               {[1] = "Sell", [2] = unit})
end

local function SkipWave(wave)
    local context = KP.contexts[coroutine.running()]
    wave = tonumber(wave) or get_wave()
    task.spawn(function()
        while KP.ContextAlive(context) and not KP.MissionEnded() and get_wave() <= wave do
            local hud = GUI and GUI:FindFirstChild("HUD")
            local vote = hud and hud:FindFirstChild("NextWaveVote")
            if get_wave() == wave and vote and vote.Visible then
                AddToQueue(game.ReplicatedStorage.Remotes.Input, {"VoteWaveConfirm"})
                task.wait(1)
            else task.wait(0.05) end
        end
    end)
end
local function AutoSkipWaveToggle(wave, status)
    task.spawn(function()
        repeat task.wait() until get_wave() >= wave

        local CategoryName = GUI:WaitForChild("HUD"):WaitForChild("Setting")
                                 :WaitForChild("Page"):WaitForChild("Main")
                                 :WaitForChild("Scroll"):WaitForChild(
                                     "SettingV2"):WaitForChild("AutoSkip")
                                 :WaitForChild("Options"):WaitForChild("Toggle")
                                 :WaitForChild("CategoryName")

        if CategoryName.Text ~= status then
            AddToQueue(game:GetService("ReplicatedStorage").Remotes.Input,
                       {[1] = "AutoSkipWaves_CHANGE"})
        end
    end)
end

local record_connections = {}
local CurrentStep = nil
local MacroPlaybackRunning = false
local MacroTargetCache = {}
_kpEnv.KP_Runtime.macroTargetPositionCache = {}

function KP_GetMacroTargetCacheKey(Target)
    if not Target then return nil end
    return tostring(Target["Name"]) .. ":" .. tostring(Target["Index"])
end

-- TODO: pcall this
local function GetUnitIndex(unit)
    if (KP.recordProfile or Macros[Settings.macro_profile])["Units"][unit.Name] == nil then
        (KP.recordProfile or Macros[Settings.macro_profile])["Units"][unit.Name] = {}
    end
    if IsTaggedLeaderUnitName(unit.Name) then
        SetMacroProfileLeaderUnit((KP.recordProfile or Macros[Settings.macro_profile]), unit.Name)
    end

    local index = nil
    local exists = false

    for i, v in ipairs((KP.recordProfile or Macros[Settings.macro_profile])["Units"][unit.Name]) do
        local hrp = unit:FindFirstChild("HumanoidRootPart")

        if hrp ~= nil then
            local magnitude = (StringToCFrame(v["Position"]).Position -
                                  hrp.CFrame.Position).magnitude

            if magnitude <= Settings.macro_magnitude then
                exists = true
                index = i
                break
            end
        end
    end

    if index == nil then
        -- TODO: Find new rotation variable if needed.
        local rotation = 0

        --[[if getrenv()["_G"] ~= nil then
            rotation = getrenv()["_G"].RotateUnitPlacementValue
        end

        if rotation == nil then rotation = 0 end]] --

        table.insert((KP.recordProfile or Macros[Settings.macro_profile])["Units"][unit.Name], {
            ["Rotation"] = rotation,
            ["Position"] = tostring(unit.HumanoidRootPart.CFrame)
        })
        index = #(KP.recordProfile or Macros[Settings.macro_profile])["Units"][unit.Name]
    end

    if KP.recordProfileName then KP.MarkMacroDirty(KP.recordProfileName) end
    return index
end

-- TODO: pcall this
local function GetUnitByTargetInfo(Target, profile)
    local unit_name = Target["Name"]
    local index = Target["Index"]

    profile = profile or (KP.playback and KP.playback.profile) or GetActiveMacroProfile()
    local placements = profile and profile.Units[unit_name]
    local unit_info = placements and placements[index]
    if not unit_info then return nil, nil, nil end
    local rotation = unit_info["Rotation"] -- only used for summons
    local cacheKey = KP_GetMacroTargetCacheKey(Target)
    local cframe = _kpEnv.KP_Runtime.macroTargetPositionCache[cacheKey] or StringToCFrame(unit_info["Position"]) -- used for identifying unit

    local function IsMatchingUnit(unit)
        if unit == nil or unit.Parent == nil then return false end
        if not UnitVariantNamesMatch(unit.Name, unit_name) then return false end

        local owner = unit:FindFirstChild("Owner")
        local hrp = unit:FindFirstChild("HumanoidRootPart")
        if owner == nil or hrp == nil then return false end
        if tostring(owner.Value) ~= Player.Name then return false end

        local magnitude = (cframe.Position - hrp.CFrame.Position).Magnitude
        return magnitude <= Settings.macro_magnitude
    end

    local cachedUnit = MacroTargetCache[cacheKey]
    if IsMatchingUnit(cachedUnit) then return cachedUnit, cframe, rotation end

    local unit = nil

    for _, v in pairs(game:GetService("Workspace").Unit:GetChildren()) do
        if IsMatchingUnit(v) then
            unit = v
            MacroTargetCache[cacheKey] = v
            break
        end
    end

    return unit, cframe, rotation
end

local function MacroRecordElapsedTime()
    return ElapsedTime() + Settings.macro_record_time_offset
end

local _lastMacroAction = nil
local _lastMacroTime = 0
function KP.SameAction(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not KP.SameAction(value, right[key]) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function InsertToMacro(action)
    if not ScriptAlive() or not Settings.macro_record or not KP.recordProfile then return end
    local now = tick()
    if _lastMacroAction and now - _lastMacroTime < 0.1 and
        KP.SameAction(action.Remote, _lastMacroAction.Remote) and
        KP.SameAction(action.Target, _lastMacroAction.Target) and
        KP.SameAction(action.Parameter, _lastMacroAction.Parameter) then return end
    _lastMacroAction, _lastMacroTime = action, now
    action.Wave = get_wave()
    action.EnemyCount = get_enemy_count()
    table.insert(KP.recordProfile.Macro, action)
    KP.MarkMacroDirty(KP.recordProfileName)
    CurrentStep = #KP.recordProfile.Macro
end

local function HookUpgrade(unit, index)
    local upgrade_level = unit:WaitForChild("UpgradeTag", 60)

    if upgrade_level ~= nil then
        return upgrade_level:GetPropertyChangedSignal("Value"):Connect(
                   function()
                if KP_IsMacroSuppressedUnit(unit) then return end
                if Settings.macro_record and Settings.macro_upgrade then
                    InsertToMacro({
                        ["Time"] = MacroRecordElapsedTime(),
                        ["Target"] = {["Name"] = unit.Name, ["Index"] = index},
                        ["Remote"] = {[1] = "Upgrade", [2] = "Target"},
                        ["Parameter"] = {["Level"] = upgrade_level.Value}
                    })
                end
            end)
    else
        return nil
    end
end

local function HookAbility(unit, index)
    local special_move = unit:WaitForChild("SpecialMove", 15)

    if special_move ~= nil then
        local ability_2 = special_move:WaitForChild("Special_Enabled2", 15)

        if ability_2 == nil then return nil end

        local ability_1 = special_move:WaitForChild("Special_Enabled", 1)
        local ability_string = ""

        if ability_1 ~= nil then
            local special_enabled_string =
                ability_1:WaitForChild("Special_Enabled_String", 1)

            if special_enabled_string ~= nil then
                ability_string = special_enabled_string.Value
            end
        end

        return ability_2.ChildAdded:Connect(function(c)
            local status, err = pcall(function()
                if special_move:GetAttribute("Auto") then return end
                if KP_IsMacroSuppressedUnit(unit) then return end

                if Settings.macro_record and Settings.macro_ability and
                    table.find(Settings.macro_ability_blacklist, unit.Name) ==
                    nil then
                    if c.Name == "SpecialStart" then
                        InsertToMacro({
                            ["Time"] = MacroRecordElapsedTime(),
                            ["Target"] = {
                                ["Name"] = unit.Name,
                                ["Index"] = index
                            },
                            ["Remote"] = {
                                [1] = "UseSpecialMove",
                                [2] = "Target",
                                [3] = ability_string
                            }
                        })
                    end
                end
            end)

            if not status then return end
        end)
    end

    return nil
end

local function HookAutoAbility(unit, index)
    local special_move = unit:WaitForChild("SpecialMove", 15)

    if special_move ~= nil then
        local special_enabled = special_move:WaitForChild("Special_Enabled", 1)
        local ability_string = ""

        if special_enabled ~= nil then
            local special_enabled_string =
                special_enabled:WaitForChild("Special_Enabled_String", 1)

            if special_enabled_string ~= nil then
                ability_string = special_enabled_string.Value
            end
        end

        return special_move:GetAttributeChangedSignal("Auto"):Connect(function()
            if KP_IsMacroSuppressedUnit(unit) then return end
            if Settings.macro_record and Settings.macro_auto_ability then
                InsertToMacro({
                    ["Time"] = MacroRecordElapsedTime(),
                    ["Target"] = {["Name"] = unit.Name, ["Index"] = index},
                    ["Remote"] = {
                        [1] = "AutoToggle",
                        [2] = "Target",
                        [3] = special_move:GetAttribute("Auto")
                    },
                    ["Parameter"] = {["Ability String"] = ability_string}
                })
            end
        end)
    end

    return nil
end

local function RecordPriorityChange(unit, index, value, field)
    if not ScriptAlive() or not Settings.macro_record or not Settings.macro_priority or not KP.recording then return end
    if not unit or not unit.Parent then return end
    local owner = unit:FindFirstChild("Owner")
    if not owner or tostring(owner.Value) ~= Player.Name then return end
    if value == nil then value, field = KP.ReadPriority(unit) end
    KP.recording.priorityLast = KP.recording.priorityLast or setmetatable({}, {__mode = "k"})
    local last = KP.recording.priorityLast[unit]
    if value ~= nil and last and last.value == value and last.field == field then return end
    KP.recording.priorityLast[unit] = {value = value, field = field}
    InsertToMacro({
        Time = MacroRecordElapsedTime(),
        Target = {Name = unit.Name, Index = index},
        Remote = {"ChangePriority", "Target"},
        Parameter = value ~= nil and {Priority = value, PriorityField = field} or nil
    })
end
local function HookPriority(unit, index)
    local connections, hooked = {}, {}
    local recording = KP.recording
    local function changed()
        if KP.recording ~= recording or not KP.ContextAlive(recording) then return end
        local value, field = KP.ReadPriority(unit)
        RecordPriorityChange(unit, index, value, field)
    end
    local function attach(value)
        if not value or hooked[value] or not table.find(KP.priorityNames, value.Name) or not value:IsA("ValueBase") then return end
        hooked[value] = true
        table.insert(connections, value:GetPropertyChangedSignal("Value"):Connect(changed))
    end
    for _, name in ipairs(KP.priorityNames) do
        attach(unit:FindFirstChild(name, true))
        table.insert(connections, unit:GetAttributeChangedSignal(name):Connect(changed))
    end
    table.insert(connections, unit.DescendantAdded:Connect(attach))
    return {Disconnect = function()
        for _, conn in ipairs(connections) do conn:Disconnect() end
        connections, hooked = {}, {}
    end}
end

local function HookNextWave()
    local HUD = GUI:WaitForChild("HUD", 15)

    if HUD ~= nil then
        local next_wave_gui = HUD:WaitForChild("NextWaveVote", 15)

        if next_wave_gui == nil then return nil end

        local yes_button = next_wave_gui:WaitForChild("YesButton", 15)

        if yes_button ~= nil then
            return yes_button.MouseButton1Click:Connect(function()
                if Settings.macro_record and Settings.macro_skipwave then
                    InsertToMacro({
                        ["Time"] = MacroRecordElapsedTime(),
                        ["Remote"] = {[1] = "VoteWaveConfirm"},
                        ["Parameter"] = {["Wave"] = get_wave()}
                    })
                end
            end)
        end
    end

    return nil
end

local function HookAutoSkipWave()
    local Toggle = GUI:WaitForChild("HUD"):WaitForChild("Setting"):WaitForChild(
                       "Page"):WaitForChild("Main"):WaitForChild("Scroll")
                       :WaitForChild("SettingV2"):WaitForChild("AutoSkip")
                       :WaitForChild("Options"):WaitForChild("Toggle")
    local CategoryName = Toggle:WaitForChild("CategoryName")
    local Button = Toggle:WaitForChild("TextButton")

    if Button ~= nil then
        return Button.MouseButton1Click:Connect(function()
            if Settings.macro_record and Settings.macro_autoskipwave then
                InsertToMacro({
                    ["Time"] = MacroRecordElapsedTime(),
                    ["Remote"] = {[1] = "AutoSkipWaves_CHANGE"},
                    ["Parameter"] = {
                        ["Wave"] = get_wave(),
                        ["Status"] = CategoryName.Text
                    }
                })
            end
        end)
    else
        return nil
    end
end

local function HookMultipleAbilitiesGUI()
    local recording = KP.recording
    local function Hook(c)
        if c.Name == "MultipleAbilities" then
            local Frame = c:WaitForChild("Frame")

            local deadline = tick() + 10
            repeat task.wait(0.05) until not Frame.Parent or #Frame:GetChildren() > 1 or tick() >= deadline
            if not Frame.Parent or KP.recording ~= recording then return end

            for k, v in pairs(Frame:GetChildren()) do
                if v.Name == "ImageButton" then
                    local connection = v.MouseButton1Click:Connect(function()
                        local text = v:WaitForChild("TextLabel")
                        if Settings.macro_record and Settings.macro_ability and not KP_IsMultiAbilitySuppressed() then
                            InsertToMacro({
                                ["Time"] = MacroRecordElapsedTime(),
                                ["Remote"] = {[1] = "MultipleAbilities"},
                                ["Parameter"] = {["Ability Name"] = text.Text}
                            })
                        end
                    end)
                    KP.TrackRecordConnection(connection, recording)
                end
            end
        end
        if c.Name == "KilluaWishes" then
            local Options = c:WaitForChild("TextBackground"):WaitForChild(
                                "OptionsContainer")
            for k, v in pairs(Options:GetChildren()) do
                if v.Name == "Option" then
                    local connection = v.MouseButton1Click:Connect(function()
                        if Settings.macro_record and Settings.macro_ability and not KP_IsMultiAbilitySuppressed() then
                            InsertToMacro({
                                ["Time"] = MacroRecordElapsedTime(),
                                ["Remote"] = {[1] = "KilluaWishes"},
                                ["Parameter"] = {["Ability Name"] = v.Text}
                            })
                        end
                    end)
                    KP.TrackRecordConnection(connection, recording)
                end
            end
        end
    end

    for _, v in pairs(GUI:GetChildren()) do
        Hook(v) -- ensures all previous multiple abilities guis are found
    end

    return GUI.ChildAdded:Connect(function(c)
        if KP.recording == recording and KP.ContextAlive(recording) then
            KP.WithContext(recording, function() task.spawn(Hook, c) end)
        end
    end)
end

local function HookSpeedChanges()
    return
        game:GetService("ReplicatedStorage"):WaitForChild("SpeedUP").Changed:Connect(
            function(v)
                if Settings.macro_record and Settings.macro_speedchange then
                    InsertToMacro({
                        ["Time"] = MacroRecordElapsedTime(),
                        ["Remote"] = {[1] = "SpeedChange"},
                        ["Parameter"] = {["Speed"] = v}
                    })
                end
            end)
end

function KP.TrackRecordConnection(conn, recording)
    recording = recording or KP.recording
    if not conn then return nil end
    if recording and recording == KP.recording and KP.ContextAlive(recording) then
        recording.connections[conn] = true
    else pcall(function() conn:Disconnect() end) end
    return conn
end
local function AddHooks(unit, index)
    local recording = KP.recording
    if not recording or recording.units[unit] then return end
    recording.units[unit] = true
    -- Priority must attach immediately; units without abilities can otherwise block it for 30 seconds.
    KP.TrackRecordConnection(HookPriority(unit, index), recording)
    for _, hook in ipairs({HookUpgrade, HookAbility, HookAutoAbility}) do
        task.spawn(function()
            KP.TrackRecordConnection(hook(unit, index), recording)
        end)
    end
end
local function IsPlayerUnitInstance(value)
    if typeof(value) ~= "Instance" then return false end
    local owner = value:FindFirstChild("Owner")
    return owner ~= nil and tostring(owner.Value) == Player.Name
end
local function GetPriorityRemoteUnit(args)
    for i = 2, args.n or #args do
        if IsPlayerUnitInstance(args[i]) then return args[i] end
        if type(args[i]) == "table" then
            for _, key in ipairs({"Unit", "unit", "Target", "target", 1, 2}) do
                if IsPlayerUnitInstance(args[i][key]) then return args[i][key] end
            end
        end
    end
end
-- Observation is the primary path. The optional hook supports old ASTD unit layouts.
do
    local ok, err = pcall(function()
        if type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function" or type(newcclosure) ~= "function" or type(getnamecallmethod) ~= "function" then return end
        local mt = getrawmetatable(game)
        local original = mt.__namecall
        local hook
        hook = newcclosure(function(self, ...)
            if ScriptAlive() and KP.recording and Settings.macro_record and Settings.macro_priority then
                local success, method = pcall(getnamecallmethod)
                if success and (method == "FireServer" or method == "InvokeServer") then
                    local args = table.pack(...)
                    if args[1] == "ChangePriority" then
                        local recording = KP.recording
                        task.delay(0.2, function()
                            if KP.recording ~= recording or not KP.ContextAlive(recording) then return end
                            local unit = GetPriorityRemoteUnit(args)
                            if unit then RecordPriorityChange(unit, GetUnitIndex(unit)) end
                        end)
                    end
                end
            end
            return original(self, ...)
        end)
        setreadonly(mt, false)
        mt.__namecall = hook
        setreadonly(mt, true)
        KP.restorePriorityHook = function()
            if mt.__namecall == hook then
                setreadonly(mt, false)
                mt.__namecall = original
                setreadonly(mt, true)
            end
        end
    end)
    if not ok then KP.Report("Priority hook unavailable; using replicated priority", err) end
end

function StopMacroRecord()
    local recording = KP.recording
    KP.recording = nil
    Settings.macro_record = false
    if recording then KP.CancelContext(recording) end
    KP.flushMacros()
    KP.recordProfile, KP.recordProfileName = nil, nil
    record_connections = {}
    _lastMacroAction, _lastMacroTime = nil, 0
    if KP.UIRefs and KP.UIRefs.macro_record then KP.UIRefs.macro_record.refresh(false) end
end
KP.stopRecording = StopMacroRecord
function StartMacroRecord()
    if not ScriptAlive() or is_lobby() or KP.recording then return end
    if KP.playback then StopMacroPlayback() end
    local profile = GetActiveMacroProfile()
    if not profile then
        Settings.macro_record = false
        ShowNotify("Macro", "Cannot record: selected profile could not be loaded. Original file preserved.")
        return
    end
    Settings.macro_record = true
    local recording = {connections = {}, units = setmetatable({}, {__mode = "k"})}
    KP.recording, KP.recordProfile, KP.recordProfileName = recording, profile, Settings.macro_profile
    _lastMacroAction, _lastMacroTime = nil, 0
    local running, previous = coroutine.running(), KP.contexts[coroutine.running()]
    local previousOwner = KP.tasks[running]
    KP.contexts[running], KP.tasks[running] = recording, recording
    local units = workspace:WaitForChild("Unit", 30)
    if KP.recording ~= recording or not KP.ContextAlive(recording) then
        KP.contexts[running], KP.tasks[running] = previous, previousOwner
        return
    end
    if not units then
        StopMacroRecord(); KP.Report("Recording", "Unit folder did not load")
        KP.contexts[running], KP.tasks[running] = previous, previousOwner
        return
    end
    local function attach(unit, summon)
        task.spawn(function()
            local owner = unit:WaitForChild("Owner", 5)
            local root = unit:WaitForChild("HumanoidRootPart", 5)
            if KP.recording ~= recording or not owner or not root or tostring(owner.Value) ~= Player.Name then return end
            local index = GetUnitIndex(unit)
            local suppressed = summon and KP_ConsumeSuppressedSummonName(unit.Name)
            if suppressed then KP_MarkMacroSuppressedUnit(unit, 30) end
            if summon and Settings.macro_summon and not suppressed then
                InsertToMacro({Time = MacroRecordElapsedTime(), Target = {Name = unit.Name, Index = index}, Remote = {"Summon", "Target"}})
            end
            AddHooks(unit, index)
        end)
    end
    KP.TrackRecordConnection(units.ChildAdded:Connect(function(unit)
        local thread = coroutine.running()
        KP.contexts[thread] = recording
        attach(unit, true)
        KP.contexts[thread] = nil
    end), recording)
    KP.TrackRecordConnection(units.ChildRemoved:Connect(function(unit)
        if KP.recording ~= recording or not Settings.macro_record or not Settings.macro_sell then return end
        local owner = unit:FindFirstChild("Owner")
        if owner and tostring(owner.Value) == Player.Name and not KP_IsMacroSuppressedUnit(unit) then
            local root = unit:FindFirstChild("HumanoidRootPart")
            if root then InsertToMacro({Time = MacroRecordElapsedTime(), Target = {Name = unit.Name, Index = GetUnitIndex(unit)}, Remote = {"Sell", "Target"}}) end
        end
    end), recording)
    for _, unit in ipairs(get_units()) do attach(unit, false) end
    for _, hook in ipairs({HookNextWave, HookMultipleAbilitiesGUI, HookAutoSkipWave, HookSpeedChanges}) do
        task.spawn(function() KP.TrackRecordConnection(hook(), recording) end)
    end
    task.spawn(function()
        local leader = GetCurrentLeaderUnit()
        if KP.recording == recording and leader ~= "" then
            SetMacroProfileLeaderUnit(profile, leader)
            KP.MarkMacroDirty(KP.recordProfileName)
        end
    end)
    KP.contexts[running] = previous
    KP.tasks[running] = previousOwner
    ShowNotify("Macro Recording", "Started recording.")
end
function KP.SetMacroRecording(enabled)
    if enabled and KP.playback then StopMacroPlayback() end
    Settings.macro_record = enabled
    if enabled then StartMacroRecord() else StopMacroRecord() end
    if KP.UIRefs and KP.UIRefs.macro_record then KP.UIRefs.macro_record.refresh(Settings.macro_record) end
    Save()
end

function KP.MissionEnded()
    local hud = GUI and GUI:FindFirstChild("HUD")
    local ending = hud and hud:FindFirstChild("MissionEnd")
    return ending ~= nil and ending.Visible == true
end
function StopMacroPlayback()
    local run = KP.playback
    KP.playback = nil
    Settings.macro_playback = false
    if run then KP.CancelContext(run); KP.DiscardQueued(run) end
    CurrentStep, MacroPlaybackRunning = nil, false
    MacroTargetCache = {}
    KP.macroPlacementTimingAdjustment = 0
    if KP.UIRefs and KP.UIRefs.macro_playback then KP.UIRefs.macro_playback.refresh(false) end
end
function StartMacroPlayback()
    if not ScriptAlive() or is_lobby() or KP.playback then return end
    local selected = GetActiveMacroProfile()
    if not selected or #selected.Macro == 0 then
        Settings.macro_playback = false
        if KP.UIRefs and KP.UIRefs.macro_playback then KP.UIRefs.macro_playback.refresh(false) end
        Save()
        ShowNotify("Macro", "Selected macro is empty or could not be loaded. Check the output for details.")
        return
    end
    if KP.recording then StopMacroRecord() end
    -- Pin both instructions and target positions for this run; UI selection cannot mix profiles.
    local run = {profile = DeepCopy(selected), profileName = Settings.macro_profile, connections = {}}
    KP.playback, Settings.macro_playback, MacroPlaybackRunning = run, true, true
    MacroTargetCache, KP.macroTargetPositionCache = {}, {}
    KP.macroPlacementTimingAdjustment = 0
    local thread = coroutine.running()
    local previous = KP.contexts[thread]
    KP.contexts[thread], KP.tasks[thread] = run, run
    local function alive() return KP.ContextAlive(run) and KP.playback == run and Settings.macro_playback and not KP.MissionEnded() end
    local ok, err = pcall(function()
        -- Stable ordering preserves consecutive actions recorded at the same time.
        local order = {}
        for index, action in ipairs(run.profile.Macro) do order[action] = index end
        table.sort(run.profile.Macro, function(a, b)
            if a.Time == b.Time then return order[a] < order[b] end
            return a.Time < b.Time
        end)
        local startIndex = math.clamp(KP.nextMacroStep or 1, 1, #run.profile.Macro)
        local rebase = KP.rebaseMacroTime
        KP.nextMacroStep, KP.rebaseMacroTime = nil, nil
        local timeShift = rebase and (ElapsedTime() - run.profile.Macro[startIndex].Time) or -Settings.macro_playback_time_offset
        local adjustment = 0
        for step = startIndex, #run.profile.Macro do
            if not alive() then break end
            CurrentStep, run.step = step, step
            local action = run.profile.Macro[step]
            local remote, parameter = action.Remote, action.Parameter or {}
            local placement = remote[1] == "Summon" and Settings.macro_summon and Settings.macro_auto_adjust_placement
            local targetTime = action.Time + timeShift - (placement and adjustment or 0)
            while alive() and ElapsedTime() < targetTime do
                task.wait(math.min(0.05, math.max(0.001, targetTime - ElapsedTime())))
            end
            if not alive() then break end
            if action.Wave and action.Wave > 0 then
                while alive() and get_wave() < action.Wave do task.wait(0.05) end
            end
            if not alive() then break end
            if action.EnemyCount and (remote[1] == "UseSpecialMove" or remote[1] == "Sell") then
                local deadline = tick() + 10
                while alive() and get_enemy_count() < action.EnemyCount - 2 and tick() < deadline do task.wait(0.1) end
            end
            if not alive() then break end
            if not action.Target then
                if remote[1] == "VoteWaveConfirm" and Settings.macro_skipwave then SkipWave(parameter.Wave)
                elseif remote[1] == "AutoSkipWaves_CHANGE" and Settings.macro_autoskipwave then AutoSkipWaveToggle(parameter.Wave, parameter.Status)
                elseif remote[1] == "MultipleAbilities" and Settings.macro_ability then UseMultipleAbilitiesGUI(parameter["Ability Name"])
                elseif remote[1] == "KilluaWishes" and Settings.macro_ability then UseKilluaWishesGUI(parameter["Ability Name"])
                elseif remote[1] == "SpeedChange" and Settings.macro_speedchange then ChangeSpeed(parameter.Speed) end
            else
                local unit, position, rotation = GetUnitByTargetInfo(action.Target, run.profile)
                if not unit and position and rotation then
                    if remote[1] == "Summon" and Settings.macro_summon then
                        local summoned, placedPosition, placedAt = SummonUnit(rotation, position, action.Target.Name, placement, {
                            stopWhenPlaybackStops = true, maxDirectRetries = Settings.macro_playback_search_attempts
                        })
                        local key = KP_GetMacroTargetCacheKey(action.Target)
                        if key and placedPosition then KP.macroTargetPositionCache[key] = placedPosition end
                        if key and summoned then MacroTargetCache[key] = summoned; unit = summoned end
                        if placement and placedAt then
                            adjustment = math.clamp(adjustment + placedAt - (action.Time + timeShift), -0.5, 0.5)
                            KP.macroPlacementTimingAdjustment = adjustment
                        end
                    elseif remote[1] ~= "Summon" then
                        for _ = 1, Settings.macro_playback_search_attempts do
                            if not alive() or unit then break end
                            task.wait(Settings.macro_playback_search_delay)
                            unit, position, rotation = GetUnitByTargetInfo(action.Target, run.profile)
                        end
                    end
                end
                if alive() and unit then
                    if remote[1] == "Upgrade" and Settings.macro_upgrade then UpgradeUnit(unit, parameter.Level)
                    elseif remote[1] == "UseSpecialMove" and Settings.macro_ability and not table.find(Settings.macro_ability_blacklist, unit.Name) then UseAbilityUnit(unit, remote[3])
                    elseif remote[1] == "AutoToggle" and Settings.macro_auto_ability then ActivateAutoAbilityUnit(unit, parameter["Ability String"], remote[3])
                    elseif remote[1] == "ChangePriority" and Settings.macro_priority then ChangePriorityUnit(unit, parameter)
                    elseif remote[1] == "Sell" and Settings.macro_sell then SellUnit(unit) end
                elseif alive() and remote[1] ~= "Summon" then
                    KP.Report("Macro step " .. step, "Target unit unavailable; skipped " .. remote[1])
                end
            end
            task.wait()
        end
        -- Retain cancellation ownership until asynchronous step workers and the queue finish.
        while alive() do
            local pending = (KP.queueInFlight and KP.queueInFlight.Context == run) or
                (KP.requestedSpeed and KP.requestedSpeed.context == run) or false
            for i = Action_Queue.first, Action_Queue.last do
                if Action_Queue[i] and Action_Queue[i].Context == run then pending = true; break end
            end
            for child, owner in pairs(KP.tasks) do if owner == run and child ~= thread then pending = true; break end end
            if not pending then break end
            task.wait(0.1)
        end
    end)
    KP.CancelContext(run)
    KP.DiscardQueued(run)
    KP.contexts[thread] = previous
    if KP.playback == run then
        KP.playback = nil
        CurrentStep, MacroPlaybackRunning = nil, false
        KP.macroPlacementTimingAdjustment = 0
        if not ok then
            Settings.macro_playback = false
            if KP.UIRefs and KP.UIRefs.macro_playback then KP.UIRefs.macro_playback.refresh(false) end
            KP.Report("Macro step " .. tostring(run.step), err)
            ShowNotify("Macro stopped", "Step " .. tostring(run.step) .. " failed. See output for the error.")
        elseif KP.MissionEnded() then ShowNotify("Macro", "Mission ended; remaining macro steps cancelled.")
        else ShowNotify("Macro", "Playback finished.") end
    end
end
function KP.SetMacroPlayback(enabled)
    if enabled and KP.recording then StopMacroRecord() end
    Settings.macro_playback = enabled
    if enabled then task.spawn(StartMacroPlayback) else StopMacroPlayback() end
    if KP.UIRefs and KP.UIRefs.macro_playback then KP.UIRefs.macro_playback.refresh(Settings.macro_playback) end
    Save()
end
function KP.SeekMacro(delta)
    local run = KP.playback
    local profile = run and run.profile or GetActiveMacroProfile()
    if not profile or #profile.Macro == 0 then return end
    local target = delta == 0 and 1 or math.clamp((CurrentStep or 1) + delta, 1, #profile.Macro)
    if run then
        local profileName = run.profileName
        StopMacroPlayback()
        Settings.macro_profile = profileName
    end
    KP.nextMacroStep, KP.rebaseMacroTime, CurrentStep = target, true, target
    if run then KP.SetMacroPlayback(true) end
end

function AutoVoteExtreme()
    repeat task.wait() until GUI.HUD.ModeVoteFrame.Visible

    repeat
        game:GetService("ReplicatedStorage").Remotes.Input:FireServer(unpack({
            [1] = "VoteGameMode",
            [2] = "Extreme"
        }))
        task.wait(1)
    until not GUI.HUD.ModeVoteFrame.Visible
end

function AutoSkipWaveSpam()
    while ScriptAlive() and Settings.auto_skip_wave_spam do
        pcall(function()
            local waveSkipVote = game:GetService("ReplicatedStorage"):FindFirstChild("WaveSkipVote")
            if waveSkipVote and waveSkipVote.Value == 0 then
                if GUI.HUD:FindFirstChild("NextWaveVote") and GUI.HUD.NextWaveVote.Visible then
                    game:GetService("ReplicatedStorage").Remotes.Input:FireServer("VoteWaveConfirm")
                end
            end
        end)
        task.wait(0.1)
    end
end

function AutoBattle()
    local warned, sent = false, false
    while ScriptAlive() and Settings.auto_battle do
        local ok, err = pcall(function()
            local hud = GUI:FindFirstChild("HUD")
            local fastForward = hud and hud:FindFirstChild("FastForward")
            local autoplay = fastForward and fastForward:FindFirstChild("Autoplay")
            local remotes = game.ReplicatedStorage:FindFirstChild("Remotes")
            local input = remotes and remotes:FindFirstChild("Input")
            if not autoplay or not autoplay.Visible or not input then return end
            local gems = tonumber(get_gems())
            if gems == nil then return end -- replicated currency can arrive after the UI
            if gems < (tonumber(Settings.auto_battle_gems) or 1500) then
                if not warned then ShowNotify("Auto Battle", "Waiting for " .. tostring(Settings.auto_battle_gems) .. " gems."); warned = true end
                return
            end
            if not sent then
                -- Do not repeatedly purchase on an unverified UI heuristic.
                input:FireServer("BuyAutoBattle")
                sent = true
                KP.autoBattleRequested = true
                ShowNotify("Auto Battle", "Activation requested. Waiting for the game to update.")
            end
        end)
        if not ok then KP.Report("Auto Battle", err) end
        if sent then
            local deadline = tick() + 10
            repeat
                task.wait(0.5)
                local hud = GUI:FindFirstChild("HUD")
                local fastForward = hud and hud:FindFirstChild("FastForward")
                local autoplay = fastForward and fastForward:FindFirstChild("Autoplay")
                if autoplay and not autoplay.Visible then
                    ShowNotify("Auto Battle", "Purchase control closed after activation request.")
                    return
                end
            until not ScriptAlive() or not Settings.auto_battle or tick() >= deadline
            if ScriptAlive() and Settings.auto_battle then
                ShowNotify("Auto Battle", "Activation could not be confirmed. Check the game control before retrying.")
            end
            return
        end
        task.wait(1)
    end
end

local function ManualUpgrade() -- added for pc
    if GUI.HUD.UpgradeV2.Actions.Upgrade.Visible then
        firesignal(GUI.HUD.UpgradeV2.Actions.Upgrade.MouseButton1Click)
    end
end

local function ManualSell() -- added for pc
    if GUI.HUD.UpgradeV2.Actions.Sell.Visible then
        firesignal(GUI.HUD.UpgradeV2.Actions.Sell.MouseButton1Click)
    end
end

function ChangeSpeed(speed)
    speed = tonumber(speed)
    if not speed or speed < 1 or speed > 3 then return end
    -- Explicit automatic speed takes priority over recorded speed steps.
    if Settings.auto_3x or Settings.auto_2x then return end
    KP.requestedSpeed = {value = speed, context = KP.contexts[coroutine.running()], deadline = tick() + 30}
    task.spawn(AutoChangeSpeed)
end
function AutoChangeSpeed()
    if KP.autoChangeSpeedRunning then return end
    KP.autoChangeSpeedRunning = true
    -- This controller is shared by automatic settings and macro requests.
    -- A cancelled macro must not kill it and leave the running flag stuck.
    local thread = coroutine.running()
    KP.contexts[thread], KP.tasks[thread] = nil, true
    local lastFire, failures = -math.huge, 0
    local ok, err = pcall(function()
        while ScriptAlive() do
            local request = KP.requestedSpeed
            if request and (not KP.ContextAlive(request.context) or tick() >= request.deadline) then KP.requestedSpeed = nil; request = nil end
            if request and (Settings.auto_3x or Settings.auto_2x) then KP.requestedSpeed = nil; request = nil end
            local target = Settings.auto_3x and 3 or Settings.auto_2x and 2 or request and request.value
            if not target then break end
            local speed = tonumber(get_game_speed())
            local remotes = game.ReplicatedStorage:FindFirstChild("Remotes")
            local input = remotes and remotes:FindFirstChild("Input")
            if speed == target then
                failures = 0
                if request and not (Settings.auto_2x or Settings.auto_3x) then KP.requestedSpeed = nil end
            elseif speed and input and tick() - lastFire >= 1 then
                local fired, fireError = pcall(function() input:FireServer("SpeedChange", speed < target) end)
                lastFire = tick()
                failures = failures + 1
                if not fired then KP.Report("Speed control", fireError) end
                if failures == 10 then ShowNotify("Auto speed", "Still waiting for " .. target .. "x. The game has not accepted the speed change.") end
            end
            task.wait(0.25)
        end
    end)
    KP.autoChangeSpeedRunning = false
    if not ok and ScriptAlive() then
        KP.Report("Speed control", err)
        task.delay(2, AutoChangeSpeed)
    end
end

function OnGameEnd()
    if not is_lobby() then
        local end_gui = GUI.HUD:WaitForChild("MissionEnd")

        repeat task.wait() until end_gui.Visible
        task.wait(1)

        if Settings.webhook_end_game then
            local webhook_args = {}
            local bg = end_gui:FindFirstChild("BG")

            if bg ~= nil then
                if bg:FindFirstChild("Times") ~= nil then
                    local GameTimeElapsed = Split(
                                                Split(bg:FindFirstChild("Times").Text,
                                                      '\n')[2], "seconds")[1]
                    local time_elapsed = tostring(
                                             math.round(tonumber(GameTimeElapsed) or ElapsedTime()))

                    table.insert(webhook_args, {
                        ["name"] = "Game Time Elapsed",
                        ["value"] = ":timer: " .. time_elapsed,
                        ["inline"] = true
                    })
                end
            end

            table.insert(webhook_args, {
                ["name"] = "Time Elapsed (1x)",
                ["value"] = ":timer: " ..
                    tostring(math.round(ElapsedTime() - TimeOffset)),
                ["inline"] = true
            })

            table.insert(webhook_args, {
                ["name"] = "Macro Time Elapsed",
                ["value"] = ":timer: " .. tostring(math.round(ElapsedTime())),
                ["inline"] = true
            })

            local GameStatus = ""
            pcall(function()
                local statusLabel = GUI.HUD:FindFirstChild("MissionEnd")
                    :FindFirstChild("BG"):FindFirstChild("Status"):FindFirstChild("Status")
                repeat task.wait(0.2) until statusLabel.Text ~= "" or not end_gui.Visible
                GameStatus = statusLabel.Text
            end)

            local GameStatusEmoji = ""
            if GameStatus == "Success!" then
                GameStatusEmoji = ":green_square: "
            elseif GameStatus == "Failed!" then
                GameStatusEmoji = ":red_square: "
            end

            table.insert(webhook_args, {
                ["name"] = "Status",
                ["value"] = GameStatusEmoji .. GameStatus,
                ["inline"] = true
            })

            table.insert(webhook_args, {
                ["name"] = "Stage / Floor",
                ["value"] = ":stadium: " .. get_stage(),
                ["inline"] = true
            })

            table.insert(webhook_args, {
                ["name"] = "Waves",
                ["value"] = ":ocean: " .. get_wave(),
                ["inline"] = true
            })

            table.insert(webhook_args, {
                ["name"] = "Current Level",
                ["value"] = ":star2: " .. tostring(get_level() or "N/A"),
                ["inline"] = true
            })

            table.insert(webhook_args, {
                ["name"] = "Current Gems",
                ["value"] = ":gem: " .. tostring(get_gems() or "N/A"),
                ["inline"] = true
            })

            table.insert(webhook_args, {
                ["name"] = "Current Gold",
                ["value"] = ":coin: " .. tostring(get_gold() or "N/A"),
                ["inline"] = true
            })

            table.insert(webhook_args, {
                ["name"] = "Current Stardust",
                ["value"] = ":star: " .. tostring(get_stardust() or "N/A"),
                ["inline"] = true
            })

            table.insert(webhook_args, {
                ["name"] = "Gauntlet Tokens",
                ["value"] = ":coin: " .. tostring(get_gauntlet_amount() or "N/A"),
                ["inline"] = true
            })

            table.insert(webhook_args, {
                ["name"] = "Battle Pass Tier",
                ["value"] = ":signal_strength: " .. get_battle_pass_tier(),
                ["inline"] = true
            })

            pcall(function()
                if _G.KP_PreGame then
                    local curGems = get_gems() or 0
                    local curGold = get_gold() or 0
                    local curStardust = get_stardust() or 0

                    local gemDiff = curGems - (_G.KP_PreGame.gems or 0)
                    local goldDiff = curGold - (_G.KP_PreGame.gold or 0)
                    local stardustDiff = curStardust - (_G.KP_PreGame.stardust or 0)

                    local gainText = ""
                    if gemDiff ~= 0 then gainText = gainText .. ":gem: " .. (gemDiff > 0 and "+" or "") .. tostring(gemDiff) .. " Gems  " end
                    if goldDiff ~= 0 then gainText = gainText .. ":coin: " .. (goldDiff > 0 and "+" or "") .. tostring(goldDiff) .. " Gold  " end
                    if stardustDiff ~= 0 then gainText = gainText .. ":star: " .. (stardustDiff > 0 and "+" or "") .. tostring(stardustDiff) .. " Stardust" end

                    if gainText ~= "" then
                        table.insert(webhook_args, {
                            ["name"] = "Rewards Gained",
                            ["value"] = gainText,
                            ["inline"] = false
                        })
                    end
                end
            end)

            pcall(function()
                if _G.KP_PreGameUnits then
                    task.wait(1)
                    local postGameUnits = {}
                    local inv = GetInventory()
                    if inv then
                        for _, item in pairs(inv) do
                            postGameUnits[tostring(item.ID)] = item.Name
                        end
                    end

                    local newUnits = {}
                    for id, name in pairs(postGameUnits) do
                        if not _G.KP_PreGameUnits[id] then
                            table.insert(newUnits, name)
                        end
                    end

                    if #newUnits > 0 then
                        table.insert(webhook_args, {
                            ["name"] = "Units Obtained (" .. tostring(#newUnits) .. ")",
                            ["value"] = ":new: " .. KP_FormatRewardList(newUnits),
                            ["inline"] = false
                        })
                    end
                end
            end)

            pcall(function()
                if _G.KP_PreGameItems then
                    local postGameItems, itemsReady = GetStorageItemCounts()
                    local itemGains = {}
                    local totalGained = 0

                    local function CalculateItemGains()
                        itemGains = {}
                        totalGained = 0
                        if itemsReady then
                            for name, amount in pairs(postGameItems) do
                                local gained = amount - (_G.KP_PreGameItems[name] or 0)
                                if gained > 0 then
                                    totalGained = totalGained + gained
                                    table.insert(itemGains, {
                                        name = name,
                                        gained = gained,
                                        total = amount
                                    })
                                end
                            end
                        end
                    end

                    CalculateItemGains()
                    if totalGained == 0 then
                        task.wait(1)
                        postGameItems, itemsReady = GetStorageItemCounts()
                        CalculateItemGains()
                    end

                    if #itemGains > 0 then
                        table.sort(itemGains, function(a, b) return a.name < b.name end)
                        local lines = {}
                        for _, item in ipairs(itemGains) do
                            table.insert(lines, "+" .. tostring(item.gained) .. " " .. item.name ..
                                " (Total: " .. tostring(item.total) .. ")")
                        end
                        table.insert(webhook_args, {
                            ["name"] = "Items Obtained (" .. tostring(totalGained) .. ")",
                            ["value"] = KP_FormatRewardList(lines),
                            ["inline"] = false
                        })
                    end
                end
            end)

            local failed = (GameStatus == "Failed!")
            SendWebhook(webhook_args, failed)
        end
    end
end

-- webhookbanner removed (external script was spamming "Banner" to logs)

-- Shared original values keep independently toggled visual options reversible.
KP.visualOriginals = setmetatable({}, {__mode = "k"})
function KP.CaptureVisual(obj, properties)
    local original = KP.visualOriginals[obj]
    if not original then original = {}; KP.visualOriginals[obj] = original end
    for _, property in ipairs(properties) do
        if original[property] == nil then original[property] = obj[property] end
    end
    return original
end
function KP.RestoreVisual(obj, state)
    if not obj then return end
    for property, original in pairs(state) do
        local value = original
        local owned = false
        if KP.alive then
            if Settings.fps_boost and KP.fpsRefs[obj] then
                if property == "Material" then value, owned = Enum.Material.SmoothPlastic, true
                elseif property == "CastShadow" or property == "Enabled" then value, owned = false, true
                elseif property == "Transparency" and (obj:IsA("Texture") or obj:IsA("Decal")) then value, owned = 1, true end
            end
            if Settings.delete_map and KP.mapRefs and KP.mapRefs[obj] then
                if property == "Transparency" then value, owned = 1, true elseif property == "Enabled" then value, owned = false, true end
            end
            local visuals = KP.enemyVisuals
            if visuals and visuals.enabled and visuals.folder and visuals.folder.Parent == workspace and obj:IsDescendantOf(visuals.folder) then
                if property == "Transparency" then
                    value = (obj.Name == "HumanoidRootPart" or obj.Name == "HoverPart") and 0.25 or 1
                    owned = true
                elseif property == "CanCollide" or property == "CastShadow" or property == "Enabled" then value, owned = false, true
                elseif property == "Material" and (obj.Name == "HumanoidRootPart" or obj.Name == "HoverPart") then value, owned = Enum.Material.SmoothPlastic, true end
            end
            if KP.manualRefs and KP.manualRefs[obj] then
                if property == "Transparency" or property == "LocalTransparencyModifier" then value, owned = 1, true
                elseif property == "CastShadow" or property == "Enabled" then value, owned = false, true end
            end
        end
        obj[property] = value
        -- Release each property's baseline as soon as its last visual owner lets go.
        -- Mutate the shared table so other options cannot later restore stale fields.
        if not owned then state[property] = nil end
    end
    if KP.visualOriginals[obj] == state and next(state) == nil then KP.visualOriginals[obj] = nil end
end
KP.fpsRefs = setmetatable({}, {__mode = "k"})
function KP.ApplyFPSObject(obj)
    if KP.AutoPlacement and KP.AutoPlacement.folder and obj:IsDescendantOf(KP.AutoPlacement.folder) then return end
    if KP.fpsRefs[obj] then return end
    local state
    if obj:IsA("BasePart") then
        state = KP.CaptureVisual(obj, {"Material", "CastShadow"})
        obj.Material, obj.CastShadow = Enum.Material.SmoothPlastic, false
    elseif obj:IsA("Decal") or obj:IsA("Texture") then
        state = KP.CaptureVisual(obj, {"Transparency"})
        obj.Transparency = 1
    elseif obj:IsA("PostEffect") or obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Smoke") or obj:IsA("Sparkles") or obj:IsA("Fire") then
        state = KP.CaptureVisual(obj, {"Enabled"})
        obj.Enabled = false
    end
    if state then KP.fpsRefs[obj] = state end
end
KP.restoreFPS = function()
    KP.fpsGeneration = (KP.fpsGeneration or 0) + 1
    if KP.fpsConnection then KP.Disconnect(KP.fpsConnection); KP.fpsConnection = nil end
    if KP.fpsLightingConnection then KP.Disconnect(KP.fpsLightingConnection); KP.fpsLightingConnection = nil end
    for obj, state in pairs(KP.fpsRefs) do
        KP.fpsRefs[obj] = nil
        if obj.Parent then pcall(KP.RestoreVisual, obj, state) end
    end
    if KP.fpsLighting then
        local lighting = game:GetService("Lighting")
        lighting.GlobalShadows, lighting.FogEnd = KP.fpsLighting.GlobalShadows, KP.fpsLighting.FogEnd
        KP.fpsLighting = nil
    end
end
function FpsBoost()
    if KP.fpsConnection or not Settings.fps_boost then return end
    KP.fpsGeneration = (KP.fpsGeneration or 0) + 1
    local generation = KP.fpsGeneration
    local lighting = game:GetService("Lighting")
    KP.fpsLighting = {GlobalShadows = lighting.GlobalShadows, FogEnd = lighting.FogEnd}
    lighting.GlobalShadows, lighting.FogEnd = false, 9e9
    local function apply(obj)
        if ScriptAlive() and Settings.fps_boost and generation == KP.fpsGeneration then
            local ok, err = pcall(KP.ApplyFPSObject, obj)
            if not ok then KP.Report("Performance mode", err) end
        end
    end
    KP.fpsConnection = TrackConnection(workspace.DescendantAdded:Connect(apply))
    KP.fpsLightingConnection = TrackConnection(lighting.ChildAdded:Connect(apply))
    for _, effect in ipairs(lighting:GetChildren()) do apply(effect) end
    local stack = {workspace}
    local processed = 0
    while #stack > 0 and ScriptAlive() and Settings.fps_boost and generation == KP.fpsGeneration do
        local obj = table.remove(stack)
        apply(obj)
        for _, child in ipairs(obj:GetChildren()) do table.insert(stack, child) end
        processed = processed + 1
        if processed % 128 == 0 then task.wait() end
    end
end

local function ApplyFPSLimit(value, notify)
    local fps = tonumber(value or Settings.fps_limit)
    if not fps or fps <= 0 then return false end
    fps = math.floor(math.clamp(fps, 15, 1000))
    Settings.fps_limit = tostring(fps)
    Save()
    if setfpscap then
        local ok = pcall(function() setfpscap(fps) end)
        if notify then
            ShowNotify("FPS Limit", ok and ("Set to " .. tostring(fps) .. " FPS.") or "Could not apply FPS cap.")
        end
        return ok
    end
    if notify then ShowNotify("FPS Limit", "Executor does not support setfpscap.") end
    return false
end

local SimplifyRefs = setmetatable({}, {__mode = "k"})

KP.enemyVisuals = {enabled = false, folder = nil, connections = {}, queue = {}, queued = {}, head = 1, tail = 0}
KP.enemyVisualOwners = setmetatable({}, {__mode = "k"})
local function RestoreSimplified(enemy)
    local refs = SimplifyRefs[enemy]
    if not refs then return end
    for obj, state in pairs(refs) do
        if KP.enemyVisualOwners[obj] == enemy then
            KP.enemyVisualOwners[obj] = nil
            pcall(function()
                KP.RestoreVisual(obj, state)
            end)
        end
    end
    SimplifyRefs[enemy] = nil
end
function KP.releaseEnemy(enemy)
    RestoreSimplified(enemy)
    if KP.targetAbilityHandled then KP.targetAbilityHandled[enemy] = nil end
    if KP.enemyStatusCache then KP.enemyStatusCache[enemy] = nil end
    if KP.valueCache then KP.valueCache[enemy] = nil end
    if KP.statusNodes then KP.statusNodes[enemy] = nil end
    if KP.enemyOverlayRefs then
        local overlay = KP.enemyOverlayRefs[enemy]
        if overlay then overlay:Destroy(); KP.enemyOverlayRefs[enemy] = nil end
    end
end
function KP.SimplifyPart(enemy, obj)
    local previous = KP.enemyVisualOwners[obj]
    if previous and previous ~= enemy then
        local oldRefs = SimplifyRefs[previous]
        if oldRefs then oldRefs[obj] = nil end
    end
    local refs = SimplifyRefs[enemy]
    if not refs then refs = setmetatable({}, {__mode = "k"}); SimplifyRefs[enemy] = refs end
    if refs[obj] then return end
    if obj:IsA("BasePart") then
        refs[obj] = KP.CaptureVisual(obj, {"Transparency", "CanCollide", "CastShadow", "Material"})
        if obj.Name == "HumanoidRootPart" or obj.Name == "HoverPart" then
            obj.Transparency = 0.25
            obj.Material = Enum.Material.SmoothPlastic
        else obj.Transparency = 1 end
        obj.CastShadow = false
        obj.CanCollide = false
    elseif obj:IsA("Decal") or obj:IsA("Texture") then
        refs[obj] = KP.CaptureVisual(obj, {"Transparency"})
        obj.Transparency = 1
    elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Smoke") or obj:IsA("Sparkles") or obj:IsA("Fire") then
        refs[obj] = KP.CaptureVisual(obj, {"Enabled"})
        obj.Enabled = false
    end
    if refs[obj] then KP.enemyVisualOwners[obj] = enemy end
end
-- DescendantRemoving fires before Parent changes. Defer one shared, bounded queue
-- so restoration sees the destination, including transfers between live enemies.
function KP.QueueEnemyVisualRemoval(obj)
    if not KP.enemyVisualOwners[obj] then return end
    local removals = KP.enemyVisualRemovals
    if not removals then removals = {queue = {}, queued = {}, head = 1, tail = 0}; KP.enemyVisualRemovals = removals end
    if removals.queued[obj] then return end
    removals.tail = removals.tail + 1
    removals.queue[removals.tail], removals.queued[obj] = obj, true
    if removals.worker then return end
    removals.worker = true
    KP.WithContext(nil, function()
        task.defer(function()
            while ScriptAlive() and removals.head <= removals.tail do
                local processed, started = 0, os.clock()
                repeat
                    local item = removals.queue[removals.head]
                    removals.queue[removals.head], removals.queued[item] = nil, nil
                    removals.head = removals.head + 1
                    local owner = KP.enemyVisualOwners[item]
                    if owner then
                        local current = item
                        local folder = KP.enemyVisuals.folder
                        if not (KP.enemyVisuals.enabled and folder and item:IsDescendantOf(folder)) then current = nil
                        else while current.Parent and current.Parent ~= folder do current = current.Parent end end
                        if current ~= owner then
                            local refs = SimplifyRefs[owner]
                            local original = refs and refs[item]
                            if refs then refs[item] = nil end
                            KP.enemyVisualOwners[item] = nil
                            if current then
                                local ok, err = pcall(KP.SimplifyPart, current, item)
                                if not ok then KP.Report("Enemy visual transfer", err) end
                            elseif original then
                                local ok, err = pcall(KP.RestoreVisual, item, original)
                                if not ok then KP.Report("Enemy visual restore", err) end
                            end
                        end
                    end
                    processed = processed + 1
                until removals.head > removals.tail or processed >= 128 or os.clock() - started >= 0.002
                if removals.head <= removals.tail then task.wait() end
            end
            removals.queue, removals.queued, removals.head, removals.tail, removals.worker = {}, {}, 1, 0, false
        end)
    end)
end
function KP.QueueEnemyVisual(obj)
    local state = KP.enemyVisuals
    if not state.enabled or state.queued[obj] then return end
    state.tail = state.tail + 1
    state.queue[state.tail] = obj
    state.queued[obj] = true
    if state.worker then return end
    state.worker = true
    -- Shared worker must not inherit the lifetime of either visual toggle.
    local running = coroutine.running()
    local owner = KP.contexts[running]
    KP.contexts[running] = nil
    task.defer(function()
        while ScriptAlive() and state.enabled and state.head <= state.tail do
            local started, processed = os.clock(), 0
            repeat
                local item = state.queue[state.head]
                state.queue[state.head] = nil
                state.head = state.head + 1
                state.queued[item] = nil
                local folder = state.folder
                if item.Parent and folder and item:IsDescendantOf(folder) then
                    local enemy = item
                    while enemy.Parent and enemy.Parent ~= folder do enemy = enemy.Parent end
                    if enemy.Parent == folder then
                        local ok, err = pcall(KP.SimplifyPart, enemy, item)
                        if not ok then KP.Report("Enemy visuals", err) end
                        for _, child in ipairs(item:GetChildren()) do
                            if not state.queued[child] and not (SimplifyRefs[enemy] and SimplifyRefs[enemy][child]) then
                                state.tail = state.tail + 1
                                state.queue[state.tail] = child
                                state.queued[child] = true
                            end
                        end
                    end
                end
                processed = processed + 1
            until state.head > state.tail or processed >= 128 or os.clock() - started >= 0.002
            if state.head <= state.tail then task.wait() end
        end
        state.queue, state.queued, state.head, state.tail = {}, {}, 1, 0
        state.worker = false
    end)
    KP.contexts[running] = owner
end
local function ApplySimplifyEnemies()
    local state = KP.enemyVisuals
    local enabled = Settings.delete_enemies or Settings.delete_map
    local folder = KP.BindEnemies().folder
    if state.enabled == enabled and state.folder == folder then return end
    for _, conn in ipairs(state.connections) do KP.Disconnect(conn) end
    state.connections = {}
    state.enabled, state.folder = enabled, folder
    if not enabled then
        state.queue, state.queued, state.head, state.tail = {}, {}, 1, 0
        for enemy in pairs(SimplifyRefs) do RestoreSimplified(enemy) end
        return
    end
    if folder then
        table.insert(state.connections, TrackConnection(folder.DescendantAdded:Connect(KP.QueueEnemyVisual)))
        table.insert(state.connections, TrackConnection(folder.DescendantRemoving:Connect(KP.QueueEnemyVisualRemoval)))
        for _, enemy in ipairs(KP.BindEnemies().list) do KP.QueueEnemyVisual(enemy) end
    end
end
KP.syncEnemyVisuals = ApplySimplifyEnemies
KP.restoreSimplifiedEnemies = function()
    KP.enemyVisuals.enabled = false
    for enemy in pairs(SimplifyRefs) do RestoreSimplified(enemy) end
end
function DeleteEnemies() ApplySimplifyEnemies() end

MapVisualRefs = setmetatable({}, {__mode = "k"})
KP.mapRefs = MapVisualRefs
_mapHideConn = nil
_mapDeleteApplied = false
RestoreMap = nil
DeleteMap = nil

do
    local currentRun
    local protectedWords = {
        "enemies", "unit", "queue", "terrain", "camera", "players",
        "floor", "baseplate", "ground", "path", "road", "track",
        "humanoidrootpart", "head", "torso", "upperarm", "lowerarm",
        "upperleg", "lowerleg", "hand", "foot"
    }
    local function active(run)
        return currentRun == run and not run.cancelled and ScriptAlive() and Settings.delete_map
    end
    local function isMapVisual(obj)
        return obj:IsA("BasePart") or obj:IsA("Decal") or obj:IsA("Texture") or
            obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or
            obj:IsA("Smoke") or obj:IsA("Sparkles") or obj:IsA("Fire")
    end
    local function isProtectedMapObj(obj)
        if KP.AutoPlacement and KP.AutoPlacement.folder and obj:IsDescendantOf(KP.AutoPlacement.folder) then return true end
        local enemies = workspace:FindFirstChild("Enemies")
        if enemies and (obj == enemies or obj:IsDescendantOf(enemies)) then return true end
        local name = string.lower(obj.Name or "")
        for _, word in ipairs(protectedWords) do
            if string.find(name, word, 1, true) then return true end
        end
        local units = workspace:FindFirstChild("Unit")
        if units and obj:IsDescendantOf(units) then return true end
        for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
            if player.Character and obj:IsDescendantOf(player.Character) then return true end
        end
        return false
    end
    local function hideMapObj(run, obj)
        if not active(run) or not obj:IsDescendantOf(workspace) or not isMapVisual(obj) or isProtectedMapObj(obj) or MapVisualRefs[obj] then return end
        if obj:IsA("BasePart") or obj:IsA("Decal") or obj:IsA("Texture") then
            MapVisualRefs[obj] = {kind = "T", v = KP.CaptureVisual(obj, {"Transparency"}).Transparency}
            obj.Transparency = 1
        else
            MapVisualRefs[obj] = {kind = "E", v = KP.CaptureVisual(obj, {"Enabled"}).Enabled}
            obj.Enabled = false
        end
    end
    local function queueMapObj(run, obj)
        -- Reject enemies before creating delayed work. One worker handles all map additions.
        if not active(run) or not isMapVisual(obj) or isProtectedMapObj(obj) or MapVisualRefs[obj] or run.queued[obj] then return end
        run.tail = run.tail + 1
        run.queue[run.tail], run.queued[obj] = obj, true
        if run.worker then return end
        KP.WithContext(nil, function()
            run.worker = task.delay(0.1, function()
                while active(run) and run.head <= run.tail do
                    local started, processed = os.clock(), 0
                    repeat
                        local item = run.queue[run.head]
                        run.queue[run.head], run.queued[item] = nil, nil
                        run.head = run.head + 1
                        local ok, err = pcall(hideMapObj, run, item)
                        if not ok then KP.Report("Hide Map", err) end
                        processed = processed + 1
                    until not active(run) or run.head > run.tail or processed >= 128 or os.clock() - started >= 0.002
                    if active(run) and run.head <= run.tail then task.wait() end
                end
                run.queue, run.queued, run.head, run.tail, run.worker = {}, {}, 1, 0, nil
            end)
        end)
    end
    RestoreMap = function()
        local run = currentRun
        currentRun = nil
        _mapDeleteApplied = false
        if run then
            run.cancelled = true
            if run.worker then task.cancel(run.worker); run.worker = nil end
            run.queue, run.queued = {}, {}
        end
        if _mapHideConn then KP.Disconnect(_mapHideConn); _mapHideConn = nil end
        for obj in pairs(MapVisualRefs) do
            MapVisualRefs[obj] = nil
            if obj.Parent then pcall(KP.RestoreVisual, obj, KP.visualOriginals[obj] or {}) end
        end
        if not Settings.delete_enemies then pcall(ApplySimplifyEnemies) end
    end
    DeleteMap = function()
        if not ScriptAlive() then return end
        if is_lobby() then
            Settings.delete_map = false
            Save()
            RestoreMap()
            return
        end
        if not Settings.delete_map then RestoreMap(); return end
        if currentRun and active(currentRun) then return end
        local run = {queue = {}, queued = {}, head = 1, tail = 0}
        currentRun, _mapDeleteApplied = run, true
        if _mapHideConn then KP.Disconnect(_mapHideConn) end
        _mapHideConn = TrackConnection(workspace.DescendantAdded:Connect(function(obj) queueMapObj(run, obj) end))
        pcall(ApplySimplifyEnemies)
        local root = workspace:FindFirstChild("Map") or workspace
        for index, obj in ipairs(root:GetDescendants()) do
            if not active(run) then return end
            local ok, err = pcall(hideMapObj, run, obj)
            if not ok then KP.Report("Hide Map", err) end
            if index % 128 == 0 then task.wait() end
        end
    end
    KP.restoreMap = RestoreMap
end

local DestroyVisualRefs = setmetatable({}, {__mode = "k"})
KP.manualRefs = DestroyVisualRefs
local DestroyProtectedKeywords = {"floor", "baseplate", "ground", "path", "road", "track", "terrain"}

local function IsDestroyProtected(instance)
    if not instance or instance == workspace or instance == workspace.Terrain then return true, "world root" end
    if Player.Character and instance:IsDescendantOf(Player.Character) then return true, "your character" end
    local current = instance
    while current and current ~= workspace do
        local name = string.lower(tostring(current.Name or ""))
        for _, keyword in ipairs(DestroyProtectedKeywords) do
            if string.find(name, keyword, 1, true) then return true, keyword end
        end
        current = current.Parent
    end
    local part = instance:IsA("BasePart") and instance or instance:FindFirstAncestorWhichIsA("BasePart")
    if part and part.Size.Y <= 2 and part.Size.X >= 8 and part.Size.Z >= 8 then return true, "floor-sized part" end
    return false
end

local function RememberDestroyedVisual(instance, state)
    if DestroyVisualRefs[instance] then return false end
    local properties = {}
    for property in pairs(state) do if property ~= "kind" then table.insert(properties, property) end end
    local original = KP.CaptureVisual(instance, properties)
    for _, property in ipairs(properties) do state[property] = original[property] end
    DestroyVisualRefs[instance] = state
    return true
end

local function HideVisualInstance(instance)
    if instance:IsA("BasePart") then
        if RememberDestroyedVisual(instance, {
            kind = "BasePart",
            Transparency = instance.Transparency,
            LocalTransparencyModifier = instance.LocalTransparencyModifier,
            CastShadow = instance.CastShadow
        }) then
            pcall(function() instance.LocalTransparencyModifier = 1 end)
            pcall(function() instance.Transparency = 1 end)
            pcall(function() instance.CastShadow = false end)
            return 1
        end
    elseif instance:IsA("Decal") or instance:IsA("Texture") then
        if RememberDestroyedVisual(instance, {kind = "Transparency", Transparency = instance.Transparency}) then
            instance.Transparency = 1
            return 1
        end
    elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam")
        or instance:IsA("Smoke") or instance:IsA("Sparkles") or instance:IsA("Fire")
        or instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") or instance:IsA("Highlight") then
        if RememberDestroyedVisual(instance, {kind = "Enabled", Enabled = instance.Enabled}) then
            instance.Enabled = false
            return 1
        end
    end
    return 0
end

local function HideVisualObject(root)
    local changed = HideVisualInstance(root)
    for _, desc in ipairs(root:GetDescendants()) do
        changed = changed + HideVisualInstance(desc)
    end
    return changed
end

function RestoreDestroyedVisuals()
    local count = 0
    for instance, state in pairs(DestroyVisualRefs) do
        count = count + 1
        if instance and instance.Parent then
            pcall(function()
                DestroyVisualRefs[instance] = nil
                KP.RestoreVisual(instance, KP.visualOriginals[instance] or {})
            end)
        end
        DestroyVisualRefs[instance] = nil
    end
    return count
end

function TryDestroyClickedVisual()
    local target = Mouse and Mouse.Target
    if not target then ShowNotify("Destroy Mode", "No object under cursor."); return end
    local protected, reason = IsDestroyProtected(target)
    if protected then ShowNotify("Destroy Mode", "Protected: " .. tostring(reason)); return end
    local changed = HideVisualObject(target)
    if changed > 0 then
        ShowNotify("Destroy Mode", "Hidden: " .. tostring(target.Name))
    else
        ShowNotify("Destroy Mode", "Nothing visual to hide.")
    end
end

_kpEnv.KP_Runtime.restoreDestroyedVisuals = RestoreDestroyedVisuals

local linkport = ""
local linkport2 = ""

local function importMacro(url)
    url = tostring(url or "")
    if not url:match("^https?://") then ShowNotify("Import", "Enter an HTTP or HTTPS URL."); return false end
    if not url:find("/raw/", 1, true) then
        url = url:gsub("hst%.sh/([^/]+)$", "hst.sh/raw/%1")
        url = url:gsub("hastebin%.com/([^/]+)$", "hastebin.com/raw/%1")
    end
    local ok, imported = pcall(function()
        local decoded = game:GetService("HttpService"):JSONDecode(game:HttpGet(url))
        assert(type(decoded) == "table", "Expected an object of macro profiles")
        local profiles, foldedNames = {}, {}
        for name, value in pairs(decoded) do
            assert(KP.ValidProfileName(name), "Invalid profile name")
            local existing = KP.FindProfileName(name)
            assert(not existing or existing == name, "Profile name differs only in letter case from " .. tostring(existing))
            local folded = name:lower()
            assert(not foldedNames[folded], "Import contains profile names differing only in letter case")
            foldedNames[folded] = true
            profiles[name] = KP.ValidateProfile(value)
        end
        assert(next(profiles), "No profiles found")
        return profiles
    end)
    if not ok then KP.Report("Macro import", imported); ShowNotify("Import error", "Invalid macro; existing files preserved."); return false end
    if KP.recording or KP.playback then ShowNotify("Import", "Stop recording/playback before importing profiles."); return false end
    local names = {}
    for name, profile in pairs(imported) do
        local file = GetMacroProfilePath(name)
        local success, err = pcall(function()
            if isfile(file) then writefile(file .. ".before-import.bak", readfile(file)) end
            writefile(file, game:GetService("HttpService"):JSONEncode({[name] = profile}))
        end)
        if not success then KP.Report("Macro import write", err); ShowNotify("Import error", "Could not save " .. name .. "."); return false end
        KP.profileErrors[name] = nil
        rawset(Macros, name, profile)
        table.insert(names, name)
    end
    RefreshMacroProfileList()
    FocusMacroProfile(Settings.macro_profile)
    RefreshMacroLeaderDropdown()
    ShowNotify("Macro imported", table.concat(names, ", "))
    return true
end
local function importSettings(url)
    url = tostring(url or "")
    if not url:match("^https?://") then ShowNotify("Import", "Enter an HTTP or HTTPS URL."); return false end
    local ok, imported = pcall(function()
        return KP.ValidateSettings(game:GetService("HttpService"):JSONDecode(game:HttpGet(url)))
    end)
    if not ok then KP.Report("Settings import", imported); ShowNotify("Import error", "Invalid settings; current settings preserved."); return false end
    local backedUp, err = pcall(function()
        if isfile(SettingsFile) then writefile(SettingsFile .. ".before-import.bak", readfile(SettingsFile)) end
    end)
    if not backedUp then KP.Report("Settings backup", err); return false end
    KP.ApplySettings(imported)
    ShowNotify("Settings imported", "Validated settings applied.")
    return true
end

function AutoReplay()
    local end_gui = GUI.HUD:WaitForChild("MissionEnd")

    repeat task.wait() until end_gui.Visible

    local replay_button = end_gui:WaitForChild("BG"):WaitForChild("Actions")
                              :WaitForChild("Replay")
    local next_button = end_gui:WaitForChild("BG"):WaitForChild("Actions")
                            :WaitForChild("Next")

    while ScriptAlive() and Settings.auto_replay and
        not _kpEnv.KP_SmartJoin.ControlsGameEnd() do
        if Settings.auto_next_story and next_button.Visible then break end

        if replay_button.Visible then firesignal(replay_button.Activated) end
        task.wait(1)
    end
end

function AutoNextStory()
    local end_gui = GUI.HUD:WaitForChild("MissionEnd")

    repeat task.wait() until end_gui.Visible

    local next_button = end_gui:WaitForChild("BG"):WaitForChild("Actions")
                            :WaitForChild("Next")

    while ScriptAlive() and Settings.auto_next_story do
        local target = tonumber(Settings.auto_story_target) or 0
        if target > 0 then
            local current = 0
            pcall(function()
                local smv = game:GetService("ReplicatedStorage"):FindFirstChild("STORYMODE_VALUE")
                if smv then current = tonumber(smv.Value) or 0 end
            end)
            if current >= target then
                Settings.auto_next_story = false
                ShowNotify("Auto Story", "Reached target level " .. target .. ". Stopping.")
                break
            end
        end
        if next_button.Visible then firesignal(next_button.Activated) end
        task.wait(1)
    end
end

function AutoUpgrade()
    local startWave = tonumber(Settings.auto_upgrade_wave) or 0
    if startWave > 0 then
        repeat task.wait(1) until not ScriptAlive() or tonumber(get_wave()) >= startWave or not Settings.auto_upgrade
    end

    while ScriptAlive() and Settings.auto_upgrade do
        local wave = tonumber(get_wave()) or 0
        local stopWave = tonumber(Settings.auto_upgrade_wave_stop) or 999
        local minMoney = tonumber(Settings.auto_upgrade_money) or 0

        if stopWave > 0 and wave > 0 and wave >= stopWave then
            Settings.auto_upgrade = false
            break
        end

        if tonumber(get_money()) >= minMoney then
            local targets = Settings.auto_upgrade_targets
            local targetLevel = tonumber(Settings.auto_upgrade_level) or 10

            for _, unit in ipairs(get_units()) do
                if not Settings.auto_upgrade then break end
                if targets and #targets > 0 and not KP_UnitMatchesAnyTarget(unit.Name, targets) then continue end

                local upgradeTag = unit:FindFirstChild("UpgradeTag")
                local currentLevel = upgradeTag and upgradeTag.Value or 0
                local maxLevel = 0
                pcall(function() maxLevel = get_max_upgrade_level(unit.Name) end)
                local goalLevel = maxLevel > 0 and math.min(targetLevel, maxLevel) or targetLevel
                if currentLevel < goalLevel then
                    KP_MarkMacroSuppressedUnit(unit, 2)
                    local ok = pcall(function()
                        game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer("Upgrade", unit)
                    end)
                    if not ok then
                        pcall(function()
                            AddToQueue(game:GetService("ReplicatedStorage").Remotes.Server, {[1] = "Upgrade", [2] = unit})
                        end)
                    end
                    task.wait(0.05)
                end
            end
        end

        task.wait(0.3)
    end
end

function AutoSell()
    -- Wait until the game actually starts
    repeat task.wait(1) until not ScriptAlive() or not Settings.auto_upgrade_sell or tonumber(get_wave()) > 0

    -- Wait for the target sell wave
    local sellWave = tonumber(Settings.auto_upgrade_wave_sell) or 1
    repeat task.wait(1) until not ScriptAlive() or tonumber(get_wave()) >= sellWave or not Settings.auto_upgrade_sell

    if not ScriptAlive() or not Settings.auto_upgrade_sell then return end

    local function TrySellUnit(unit)
        task.spawn(function()
            local has_sold = false
            local attempts = 0
            local conn = KP.TrackContextConnection(workspace.Unit.ChildRemoved:Connect(function(x)
                if unit == x then has_sold = true end
            end))
            repeat
                if not has_sold then
                    game:GetService("ReplicatedStorage").Remotes.Input:FireServer("Sell", unit)
                end
                attempts = attempts + 1
                task.wait(0.6)
            until has_sold or attempts >= 3
            KP.Disconnect(conn)
        end)
    end

    while ScriptAlive() and Settings.auto_upgrade_sell do
        local units = get_units()
        if #units == 0 then break end
        for _, unit in ipairs(units) do
            if not Settings.auto_upgrade_sell then break end
            TrySellUnit(unit)
            task.wait(0.6)
        end
        task.wait(1)
    end
end

local function AutoBuffHelper(Units, unit, checks, ability_type, ability_name, active)
    for _, check in pairs(checks) do
        if check == "attack" then
            repeat task.wait() until not active() or not CheckAttackBuff(Units)
        elseif check == "range" then
            repeat task.wait() until not active() or not CheckRangeBuff(Units)
        end
        if not active() then return false end
    end
    if not active() then return false end
    if ability_type == "Multiple" then
        UseMultipleAbilitiesUnit(unit, "", ability_name, active)
    else
        UseAbilityUnit(unit, "", nil, active)
    end
    return true
end

function KP_GetAbilityString(unit)
    local abilityString = ""
    pcall(function()
        local special = unit:FindFirstChild("SpecialMove")
        local enabled = special and special:FindFirstChild("Special_Enabled")
        local value = enabled and enabled:FindFirstChild("Special_Enabled_String")
        if value then abilityString = value.Value end
    end)
    return abilityString
end

function KP_AbilityReady(unit)
    local ready = false
    pcall(function()
        local special = unit:FindFirstChild("SpecialMove")
        local enabled2 = special and special:FindFirstChild("Special_Enabled2")
        if enabled2 and enabled2:IsA("BoolValue") then
            ready = not enabled2.Value
            return
        end
        local enabled = special and special:FindFirstChild("Special_Enabled")
        if enabled and enabled:IsA("BoolValue") then
            ready = enabled.Value
            return
        end
        ready = special ~= nil
    end)
    return ready
end

function KP_ClickMultiAbilityByName(abilityName, searchDelay)
    local desired = KP_NormalizeText(abilityName)
    if desired == "" then return false end
    local delay = tonumber(searchDelay) or 0.1
    local gui = nil
    for _ = 1, 30 do
        gui = GUI:FindFirstChild("MultipleAbilities")
        if gui then break end
        task.wait(delay)
    end
    if not gui then return false end
    local frame = gui:FindFirstChild("Frame")
    if not frame then return false end
    for _ = 1, 10 do
        for _, child in pairs(frame:GetChildren()) do
            if child:IsA("ImageButton") or child:IsA("TextButton") then
                local textLabel = child:FindFirstChild("TextLabel")
                local text = textLabel and textLabel.Text or (child:IsA("TextButton") and child.Text or "")
                if KP_NormalizeText(text) == desired then
                    KP_SuppressNextMultiAbility(3)
                    pcall(function() firesignal(child.Activated) end)
                    pcall(function() firesignal(child.MouseButton1Click) end)
                    return true
                end
            end
        end
        task.wait(delay)
    end
    return false
end

function KP_UseMultipleAbilityBySlot(slot, searchDelay)
    slot = tonumber(slot) or 1
    local delay = tonumber(searchDelay) or 0.1
    local gui = nil
    for _ = 1, 30 do
        gui = GUI:FindFirstChild("MultipleAbilities")
        if gui then break end
        task.wait(delay)
    end
    if not gui then return false end
    local frame = gui:FindFirstChild("Frame")
    if not frame then return false end
    for _ = 1, 10 do
        local buttons = {}
        for _, child in pairs(frame:GetChildren()) do
            if child:IsA("ImageButton") or child:IsA("TextButton") then
                table.insert(buttons, child)
            end
        end
        if #buttons > 0 then
            table.sort(buttons, function(a, b)
                local ax, bx = a.AbsolutePosition.X, b.AbsolutePosition.X
                if math.abs(ax - bx) < 2 then return a.AbsolutePosition.Y < b.AbsolutePosition.Y end
                return ax < bx
            end)
            local target = buttons[slot]
            if target then
                KP_SuppressNextMultiAbility(3)
                pcall(function() firesignal(target.Activated) end)
                pcall(function() firesignal(target.MouseButton1Click) end)
                return true
            end
        end
        task.wait(delay)
    end
    return false
end

function KP_FireScriptAbility(unit, abilityString)
    if not unit then return end
    KP_MarkMacroSuppressedUnit(unit, 30)
    local final = abilityString
    if final == nil then final = KP_GetAbilityString(unit) end
    local ok = pcall(function()
        game:GetService("ReplicatedStorage").Remotes.Input:FireServer("UseSpecialMove", unit, final)
    end)
    return ok
end

function KP_UseScriptAbility(unit, abilityString, multi, popupDelay)
    if not unit then return false end
    KP_MarkMacroSuppressedUnit(unit, 30)
    if multi then
        local delay = tonumber(popupDelay)
        if delay == nil then delay = 0.1 end
        local ok = KP_FireScriptAbility(unit, "")
        if not ok then ok = KP_FireScriptAbility(unit, abilityString or KP_GetAbilityString(unit)) end
        if not ok then return false end
        if delay > 0 then task.wait(delay) end
        if type(multi) == "string" then
            return KP_ClickMultiAbilityByName(multi, delay) or KP_UseMultipleAbilityBySlot(1, delay)
        end
        return KP_UseMultipleAbilityBySlot(multi, delay)
    else
        return KP_FireScriptAbility(unit, abilityString or KP_GetAbilityString(unit))
    end
end

function KP_ClickGuiObject(guiObject, clickDelay)
    if not guiObject then return false end
    local delay = tonumber(clickDelay) or 0.08
    local clicked = false
    pcall(function()
        firesignal(guiObject.MouseButton1Down)
        clicked = true
    end)
    if delay > 0 then task.wait(delay) end
    pcall(function()
        firesignal(guiObject.MouseButton1Up)
        clicked = true
    end)
    if delay > 0 then task.wait(delay) end
    pcall(function()
        firesignal(guiObject.MouseButton1Click)
        clicked = true
    end)
    if delay > 0 then task.wait(delay) end
    pcall(function()
        firesignal(guiObject.Activated)
        clicked = true
    end)
    return clicked
end

function KP_ClickKilluaWish(wishName)
    wishName = tostring(wishName or "Money")
    local desired = KP_NormalizeText(wishName)
    local gui = nil
    for _ = 1, 30 do
        gui = GUI:FindFirstChild("KilluaWishes")
        if gui then break end
        task.wait(0.03)
    end
    if not gui then return false end

    local background = gui:FindFirstChild("TextBackground")
    local options = background and background:FindFirstChild("OptionsContainer")
    if not options then return false end

    for _ = 1, 10 do
        for _, option in pairs(options:GetChildren()) do
            if option.Name == "Option" and (option:IsA("TextButton") or option:IsA("ImageButton")) then
                local text = option:IsA("TextButton") and option.Text or ""
                local textLabel = option:FindFirstChildWhichIsA("TextLabel", true)
                if text == "" and textLabel then text = textLabel.Text end
                if KP_NormalizeText(text) == desired then
                    KP_SuppressNextMultiAbility(3)
                    KP_ClickGuiObject(option)
                    for _ = 1, 12 do
                        if not gui.Parent or GUI:FindFirstChild("ChatGuiHandler") then break end
                        task.wait(0.1)
                    end
                    return true
                end
            end
        end
        task.wait(0.03)
    end
    return false
end

function KP_CloseKilluaWishPopup()
    task.wait(1)
    for _ = 1, 25 do
        local chatGui = GUI:FindFirstChild("ChatGuiHandler")
        if chatGui then
            for _, obj in pairs(chatGui:GetDescendants()) do
                if obj:IsA("TextButton") or obj:IsA("ImageButton") then
                    local text = obj:IsA("TextButton") and obj.Text or ""
                    local textLabel = obj:FindFirstChildWhichIsA("TextLabel", true)
                    if text == "" and textLabel then text = textLabel.Text end
                    local normalized = KP_NormalizeText(text)
                    if obj.Visible and (obj.Name == "Option" or normalized == "close" or normalized == "kay") then
                        KP_ClickGuiObject(obj)
                        return true
                    end
                end
            end
        end
        task.wait(0.05)
    end
    return false
end

function KP_NormalizeText(value)
    return tostring(value or ""):lower():gsub("%s+", "")
end

function KP_NormalizeUnitName(name)
    return tostring(name or ""):lower():gsub("[%s%p_]+", "")
end

function KP_DoesNameMatchKeywords(name, keywords)
    local normalized = KP_NormalizeUnitName(name)
    for _, keyword in pairs(keywords or {}) do
        local key = KP_NormalizeUnitName(keyword)
        if key ~= "" and string.find(normalized, key, 1, true) then
            return true
        end
    end
    return false
end

local KP_AbilityProfiles = {
    {id = "Gojo", kind = "timestop", keywords = {"gojo", "gojo7", "sixeyesgojo", "satorougojou", "satorougojo", "mysteriousxfinal", "gojofinal"}},
    {id = "Tsuku", kind = "timestop", keywords = {"madara", "legendaryleaderpath", "legendaryleader"}},
    {id = "Yomi", kind = "rewind", keywords = {"madara", "legendaryleaderpath", "legendaryleader"}},
    {id = "Gyro", kind = "support", keywords = {"gyro", "spinmaster"}},
    {id = "Aizen", kind = "rewind", keywords = {"aizen", "eyezenfinal", "eyezenhogii", "eyezen"}},
    {id = "Diavolo", kind = "rewind", keywords = {"diavolo", "devil"}},
    {id = "LuffyGun", kind = "nuke", keywords = {"luffy5", "ruffy5thform", "ruffy5"}},
    {id = "Killua", kind = "wish", keywords = {"killua", "killua6", "killer", "killers"}},
    {id = "Katakuri", kind = "slow", keywords = {"katakuri", "mochiawakening", "mochiinjured", "mochi"}}
}

function KP_GetSelectedUnitKeywords(selectedName)
    local keywords = {selectedName}
    local seen = {[KP_NormalizeUnitName(selectedName)] = true}
    for _, profile in pairs(KP_AbilityProfiles) do
        if KP_DoesNameMatchKeywords(selectedName, profile.keywords) then
            for _, keyword in pairs(profile.keywords) do
                local key = KP_NormalizeUnitName(keyword)
                if key ~= "" and not seen[key] then
                    seen[key] = true
                    table.insert(keywords, keyword)
                end
            end
        end
    end
    return keywords
end

function KP_UnitNameMatchesSelection(unitName, selectedName)
    if not unitName or not selectedName or selectedName == "" then return false end
    if UnitVariantNamesMatch(unitName, selectedName) then return true end
    if unitName == selectedName then return true end
    local unitNorm = KP_NormalizeUnitName(unitName)
    local selectedNorm = KP_NormalizeUnitName(selectedName)
    if unitNorm == selectedNorm then return true end
    if selectedNorm ~= "" and string.find(unitNorm, selectedNorm, 1, true) then return true end
    if unitNorm ~= "" and string.find(selectedNorm, unitNorm, 1, true) then return true end
    return KP_DoesNameMatchKeywords(unitName, KP_GetSelectedUnitKeywords(selectedName))
end

function KP_UnitMatchesAnyTarget(unitName, targets)
    if not targets or #targets == 0 then return true end
    for _, target in pairs(targets) do
        if KP_UnitNameMatchesSelection(unitName, target) then return true end
    end
    return false
end

KP.valueCache = setmetatable({}, {__mode = "k"})
KP.statusNodes = setmetatable({}, {__mode = "k"})
function KP.BindEnemyQueries()
    local folder = KP.BindEnemies().folder
    if KP.queryFolder == folder then return end
    for _, conn in ipairs(KP.queryConnections or {}) do KP.Disconnect(conn) end
    KP.queryConnections, KP.queryFolder = {}, folder
    KP.valueCache, KP.statusNodes = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
    if not folder then return end
    local function invalidate(desc)
        local current = desc
        while current and current ~= folder do
            KP.valueCache[current] = nil
            KP.statusNodes[current] = nil
            if KP.enemyStatusCache then KP.enemyStatusCache[current] = nil end
            current = current.Parent
        end
    end
    for _, signal in ipairs({folder.DescendantAdded, folder.DescendantRemoving}) do
        table.insert(KP.queryConnections, TrackConnection(signal:Connect(invalidate)))
    end
end
function KP_GetValueObject(root, valueName)
    if not root then return nil end
    KP.BindEnemyQueries()
    local cache = KP.valueCache[root]
    if not cache then cache = {}; KP.valueCache[root] = cache end
    local value = cache[valueName]
    if value == false then return nil end
    if value and value.Parent and value:IsDescendantOf(root) then return value end
    value = root:FindFirstChild(valueName, true)
    if value and value:IsA("ValueBase") then cache[valueName] = value; return value end
    cache[valueName] = false
    return nil
end

function KP_ReadNumberValue(root, valueName)
    local value = KP_GetValueObject(root, valueName)
    if value then return tonumber(value.Value) end
    return nil
end

function KP_GetEnemyStatusText(enemy)
    KP.BindEnemyQueries()
    KP.enemyStatusCache = KP.enemyStatusCache or setmetatable({}, {__mode = "k"})
    local cached = KP.enemyStatusCache[enemy]
    if cached and tick() - cached.time < 0.025 then return cached.text end
    local nodes = KP.statusNodes[enemy]
    if not nodes then
        nodes = enemy:GetDescendants()
        KP.statusNodes[enemy] = nodes
    end
    local parts = {}
    for _, desc in ipairs(nodes) do
        if desc.Parent then
            if desc:IsA("ValueBase") then
                if not desc:IsA("BoolValue") or desc.Value then
                    table.insert(parts, desc.Name)
                    table.insert(parts, tostring(desc.Value))
                end
            elseif (desc:IsA("ImageLabel") or desc:IsA("ImageButton")) and desc.Visible then
                table.insert(parts, desc.Name)
                table.insert(parts, tostring(desc.Image))
            elseif (desc:IsA("TextLabel") or desc:IsA("TextButton")) and desc.Visible then
                table.insert(parts, desc.Name)
                table.insert(parts, tostring(desc.Text))
            end
        end
    end
    local text = KP_NormalizeText(table.concat(parts, " "))
    KP.enemyStatusCache[enemy] = {time = tick(), text = text}
    return text
end

function KP_GetEnemyHpPercent(enemy)
    local hp = KP_ReadNumberValue(enemy, "HP") or KP_ReadNumberValue(enemy, "Health")
    local maxHp = KP_ReadNumberValue(enemy, "MAXHP") or KP_ReadNumberValue(enemy, "MaxHP") or
                      KP_ReadNumberValue(enemy, "MaxHealth")
    if hp and maxHp and maxHp > 0 then return (hp / maxHp) * 100 end
    return 101
end

function KP_GetEnemyPath(enemy)
    return KP_ReadNumberValue(enemy, "PathNumber") or KP_ReadNumberValue(enemy, "Path") or 0
end

function KP_GetFrontEnemy(filterFn)
    local bestEnemy = nil
    local bestPath = -math.huge
    pcall(function()
        local folder = workspace:FindFirstChild("Enemies")
        if not folder then return end
        for _, enemy in ipairs(KP.BindEnemies().list) do
            if (not filterFn or filterFn(enemy)) then
                local hp = KP_ReadNumberValue(enemy, "HP") or KP_ReadNumberValue(enemy, "Health")
                if hp == nil or hp > 0 then
                    local path = KP_GetEnemyPath(enemy)
                    if path > bestPath then
                        bestPath = path
                        bestEnemy = enemy
                    end
                end
            end
        end
    end)
    return bestEnemy
end

function KP_IsEnemyTimeStopped(enemy)
    local status = KP_GetEnemyStatusText(enemy)
    return status:find("domaininfinity", 1, true) ~= nil or
        status:find("domain_infinity", 1, true) ~= nil or
        status:find("longtimestop", 1, true) ~= nil or
        status:find("timestop", 1, true) ~= nil or
        status:find("timestopimage", 1, true) ~= nil or
        status:find("minidomain", 1, true) ~= nil or
        status:find("domain", 1, true) ~= nil or
        status:find("timefreeze", 1, true) ~= nil or
        status:find("freezeeffect", 1, true) ~= nil or
        status:find("stuneffect", 1, true) ~= nil
end

function KP_EnemyHasSenality(enemy)
    local status = KP_GetEnemyStatusText(enemy)
    return status:find("senality", 1, true) ~= nil or status:find("senility", 1, true) ~= nil
end

function KP_TargetEnemyMatches(enemy, targetType)
    local text = KP_GetEnemyStatusText(enemy) .. " " .. KP_NormalizeText(enemy.Name)
    targetType = KP_NormalizeText(targetType)
    if targetType == "boss" then
        return text:find("boss", 1, true) ~= nil
    elseif targetType == "decelerate" then
        return text:find("decelerate", 1, true) ~= nil or text:find("slow", 1, true) ~= nil
    elseif targetType == "cloner" then
        return text:find("cloner", 1, true) ~= nil or text:find("clone", 1, true) ~= nil
    end
    return false
end

function KP_FindPlacedUnit(unitName)
    local selected = nil
    if not unitName or unitName == "" then return nil end
    for _, unit in pairs(get_units()) do
        if KP_UnitNameMatchesSelection(unit.Name, unitName) and KP_AbilityReady(unit) then
            selected = unit
            break
        end
    end
    return selected
end

function KP_FindNewUnit(unitName, cframe, before)
    local closest = nil
    local closestDistance = math.huge
    for _, unit in pairs(get_units()) do
        if KP_UnitNameMatchesSelection(unit.Name, unitName) and not before[unit] then
            local hrp = unit:FindFirstChild("HumanoidRootPart")
            if hrp then
                local distance = (cframe.Position - hrp.CFrame.Position).Magnitude
                if distance < closestDistance then
                    closest = unit
                    closestDistance = distance
                end
            end
        end
    end
    return closest
end

function KP_SummonScriptUnit(unitName, cframe, rotation, correctPlacement, placementOptions)
    if type(cframe) == "string" then cframe = StringToCFrame(cframe) end
    placementOptions = type(placementOptions) == "table" and placementOptions or {}
    local before = {}
    for _, unit in pairs(get_units()) do before[unit] = true end
    KP_SuppressNextSummonName(unitName, 20)
    local summonedUnit = SummonUnit(rotation or 0, cframe, unitName, correctPlacement == true, placementOptions)
    if summonedUnit then
        KP_MarkMacroSuppressedUnit(summonedUnit, 60)
        return summonedUnit
    end
    local start = tick()
    local timeout = placementOptions.postConfirmTimeout or 6
    repeat
        local unit = KP_FindNewUnit(unitName, cframe, before)
        if unit then
            KP_MarkMacroSuppressedUnit(unit, 60)
            return unit
        end
        task.wait(0.05)
    until tick() - start > timeout or not ScriptAlive()
    return nil
end

function KP_UpgradeScriptUnit(unit, level)
    if not unit then return end
    KP_MarkMacroSuppressedUnit(unit, 60)
    UpgradeUnit(unit, level)
end

function KP_WaitUnitUpgrade(unit, level, timeout)
    local start = tick()
    repeat
        local current = 0
        pcall(function()
            local tag = unit and unit:FindFirstChild("UpgradeTag")
            if tag then current = tonumber(tag.Value) or 0 end
        end)
        if current >= level then return true end
        task.wait(0.1)
    until tick() - start > (timeout or 5) or not ScriptAlive()
    return false
end

function KP_GetUnitUpgradeLevel(unit)
    if not unit then return 0 end
    local current = 0
    pcall(function()
        local tag = unit:FindFirstChild("UpgradeTag")
        if tag then current = tonumber(tag.Value) or 0 end
    end)
    return current
end

function KP_UpgradeScriptUnitFast(unit, targetLevel, maxAttempts)
    targetLevel = tonumber(targetLevel) or 0
    maxAttempts = tonumber(maxAttempts) or (targetLevel + 8)
    if not unit then return false end
    KP_MarkMacroSuppressedUnit(unit, 60)
    for _ = 1, maxAttempts do
        if not unit or not unit.Parent then return false end
        if KP_GetUnitUpgradeLevel(unit) >= targetLevel then
            return true
        end
        local ok = pcall(function()
            game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer("Upgrade", unit)
        end)
        if not ok then
            return false
        end
        task.wait(0.06)
    end
    return KP_GetUnitUpgradeLevel(unit) >= targetLevel
end

function KP_SellScriptUnit(unit)
    if not unit then return end
    KP_MarkMacroSuppressedUnit(unit, 60)
    SellUnit(unit)
end

function KP_BurstSellScriptUnit(unit, attempts, delay)
    if not unit then return 0 end
    local sent = 0
    attempts = tonumber(attempts) or 3
    delay = tonumber(delay) or 0.015
    KP_MarkMacroSuppressedUnit(unit, 60)
    for _ = 1, attempts do
        if not unit or not unit.Parent then break end
        pcall(function() SellUnit(unit) end)
        sent = sent + 1
        if delay > 0 then task.wait(delay) end
    end
    return sent
end

function KP_AutoCycleTimestop()
    if _kpEnv.KP_Runtime.autoCycleTimestopRunning then return end
    _kpEnv.KP_Runtime.autoCycleTimestopRunning = true
    local lastFrontEnemy = nil
    local lastFire = 0
    local lastGameFire = ElapsedTime()
    while ScriptAlive() and Settings.auto_cycle_timestop do
        if Settings.auto_cycle_timestop then
            local frontEnemy = KP_GetFrontEnemy()
            if frontEnemy ~= lastFrontEnemy then
                lastFrontEnemy = frontEnemy
            end
            local nowGame = ElapsedTime()
            if nowGame <= 0 or lastGameFire > nowGame then
                lastGameFire = nowGame
            end
            local stopped = frontEnemy and KP_IsEnemyTimeStopped(frontEnemy) or false
            if frontEnemy and not stopped and tick() - lastFire > 0.18 then
                local unit = KP_FindPlacedUnit(Settings.auto_cycle_timestop_unit or "Gojo7")
                if unit then
                    KP_UseScriptAbility(unit, KP_GetAbilityString(unit))
                    lastFire = tick()
                    lastGameFire = nowGame
                    task.wait(0.03)
                else
                    lastFire = tick()
                end
            end
        else
            lastFrontEnemy = nil
        end
        task.wait(0.015)
    end
    _kpEnv.KP_Runtime.autoCycleTimestopRunning = false
end

function KP_AutoKillua()
    if _kpEnv.KP_Runtime.autoKilluaRunning then return end
    _kpEnv.KP_Runtime.autoKilluaRunning = true
    _kpEnv.KP_Runtime.killuaWishLocks = _kpEnv.KP_Runtime.killuaWishLocks or setmetatable({}, {__mode = "k"})

    while ScriptAlive() and Settings.auto_killua do
        local now = tick()
        local locks = _kpEnv.KP_Runtime.killuaWishLocks
        for _, unit in pairs(get_units()) do
            if not Settings.auto_killua then break end
            if KP_UnitNameMatchesSelection(unit.Name, "Killua6") and KP_AbilityReady(unit) and
                (not locks[unit] or now >= locks[unit]) then
                locks[unit] = now + 4
                KP_UseScriptAbility(unit, KP_GetAbilityString(unit))
                if KP_ClickKilluaWish(Settings.auto_killua_wish or "Money") then
                    task.spawn(KP_CloseKilluaWishPopup)
                end
                task.wait(0.75)
            end
        end
        task.wait(0.2)
    end

    _kpEnv.KP_Runtime.autoKilluaRunning = false
end

function KP_AutoTargetAbility()
    if _kpEnv.KP_Runtime.autoTargetAbilityRunning then return end
    _kpEnv.KP_Runtime.autoTargetAbilityRunning = true
    local lastUse = 0
    _kpEnv.KP_Runtime.targetAbilityHandled = _kpEnv.KP_Runtime.targetAbilityHandled or setmetatable({}, {__mode = "k"})
    while ScriptAlive() and Settings.auto_target_ability do
        if Settings.auto_target_ability and tick() - lastUse > 1 then
            local handled = _kpEnv.KP_Runtime.targetAbilityHandled
            local enemyCountGate = tonumber(Settings.auto_target_enemy_count) or 0
            local enemyCount = get_enemy_count()
            local enemy = KP_GetFrontEnemy(function(e)
                return not handled[e] and
                    KP_TargetEnemyMatches(e, Settings.auto_target_enemy_type) and
                    (enemyCountGate <= 0 or enemyCount <= enemyCountGate) and
                    KP_GetEnemyHpPercent(e) <= (tonumber(Settings.auto_target_hp_percent) or 10)
            end)
            if enemy then
                local delay = math.max(0, tonumber(Settings.auto_target_ability_delay) or 0)
                local readyAt = tick() + delay
                while ScriptAlive() and Settings.auto_target_ability and tick() < readyAt do
                    task.wait(0.05)
                end
                if ScriptAlive() and Settings.auto_target_ability and enemy.Parent and
                    KP_TargetEnemyMatches(enemy, Settings.auto_target_enemy_type) and
                    (enemyCountGate <= 0 or get_enemy_count() <= enemyCountGate) and
                    KP_GetEnemyHpPercent(enemy) <= (tonumber(Settings.auto_target_hp_percent) or 10) then
                    local unit = KP_FindPlacedUnit(Settings.auto_target_ability_unit)
                    if unit and KP_AbilityReady(unit) then
                        local dispatched = false
                        for attempt = 1, 2 do
                            local attemptUnit = attempt == 1 and unit or KP_FindPlacedUnit(Settings.auto_target_ability_unit)
                            if attemptUnit and KP_AbilityReady(attemptUnit) then
                                local sent = KP_UseScriptAbility(attemptUnit, KP_GetAbilityString(attemptUnit),
                                                    Settings.auto_target_ability_multi and (tonumber(Settings.auto_target_ability_multi_slot) or 1) or nil)
                                dispatched = dispatched or sent
                            end
                            if attempt == 1 then task.wait(0.2) end
                        end
                        handled[enemy] = dispatched or nil
                        lastUse = tick()
                    end
                end
            end
        end
        task.wait(0.15)
    end
    _kpEnv.KP_Runtime.autoTargetAbilityRunning = false
end

function AutoBuff()
    for k, v in pairs(Settings.auto_buff_units) do
        task.spawn(function()
            local context = KP.contexts[coroutine.running()]
            local function active()
                return KP.ContextAlive(context) and Settings.auto_buff and Settings.auto_buff_units[k] == v
            end
            while active() do
                local Units = {}
                for _, unit in pairs(get_units()) do
                    local special = unit:FindFirstChild("SpecialMove")
                    if unit.Name == k and special and special:IsA("ValueBase") and special.Value ~= "" then table.insert(Units, unit) end
                end
                local checks, ability_type, ability_name, time = v.Checks, v["Ability Type"], v["Ability Name"], v.Time
                local function use(group, unit)
                    return AutoBuffHelper(group, unit, checks, ability_type, ability_name, active)
                end
                if v.Mode == "Box" then
                    local Units2 = {}
                    if #Units > 4 and #Units < 8 then
                        repeat
                            task.wait(1)
                            if not active() then return end
                            table.remove(Units, #Units)
                        until #Units == 4
                    end
                    if #Units == 8 then
                        for _ = 1, 4 do table.insert(Units2, Units[1]); table.remove(Units, 1) end
                    end
                    if #Units == 4 or #Units2 == 4 then
                        for i = 1, 4 do
                            if not active() then return end
                            if #Units == 4 and not use(Units, Units[i]) then return end
                            if #Units2 == 4 and not use(Units2, Units2[i]) then return end
                            if not Delay(time, active) then return end
                        end
                    end
                elseif v.Mode == "Pair" then
                    if #Units >= 2 then
                        for i, unit in ipairs(Units) do
                            if i % 2 ~= 0 and not use(Units, unit) then return end
                        end
                        if not Delay(time, active) then return end
                        for i, unit in ipairs(Units) do
                            if i % 2 == 0 and not use(Units, unit) then return end
                        end
                        if not Delay(time, active) then return end
                    end
                elseif v.Mode == "Spam" then
                    for _, unit in ipairs(Units) do if not use(Units, unit) then return end end
                    if not Delay(time, active) then return end
                elseif v.Mode == "Cycle" then
                    local cycle_units = v["Cycle Units"] or 8
                    if #Units >= cycle_units then
                        for _, unit in ipairs(Units) do
                            if not use(Units, unit) then return end
                            if not Delay(time, active) then return end
                        end
                    end
                end
                if v.Delay ~= nil and not Delay(v.Delay, active) then return end
                task.wait()
            end
        end)
    end
end

local isEvolvingEXP = false

function AutoEvolveEXP()
    local function GetInventory()
        local units = game.ReplicatedStorage.Remotes.Server:InvokeServer("Data",
                                                                         "Units")
        return units
    end

    local function CountEXP()
        local inventory = GetInventory()
        local exp1 = 0
        local exp2 = 0
        local exp3 = 0
        local exp4 = 0

        for _, v in pairs(inventory) do
            if v.Name == "EXP IV" then exp4 = exp4 + 1 end

            if v.Name == "EXP III" then exp3 = exp3 + 1 end

            if v.Name == "EXP II" then exp2 = exp2 + 1 end

            if v.Name == "EXP I" then exp1 = exp1 + 1 end
        end

        return exp1, exp2, exp3, exp4
    end

    local function GetEXPUnitID(name)
        local inventory = GetInventory()

        for _, v in pairs(inventory) do
            if v.Name == name then return v.ID end
        end

        return nil
    end

    local function EvolveHelper(unit_name)
        local unit_id = GetEXPUnitID(unit_name)

        if unit_id ~= nil then
            local args = {[1] = "UpgradeUnit", [2] = unit_name, [3] = unit_id}
            game:GetService("ReplicatedStorage").Remotes.Input:FireServer(
                unpack(args))
            task.wait(0.25)
        end

        return CountEXP()
    end

    local exp1, exp2, exp3, exp4 = CountEXP()

    if exp3 >= 3 or exp2 >= 3 or exp1 >= 2 then
        isEvolvingEXP = true
        local unchanged = 0
        while ScriptAlive() and Settings.auto_evolve_exp and (exp3 >= 3 or exp2 >= 3 or exp1 >= 2) do
            local previous = {exp1, exp2, exp3, exp4}
            if exp3 >= 3 then
                exp1, exp2, exp3, exp4 = EvolveHelper("EXP III")
            end

            if exp2 >= 3 then
                exp1, exp2, exp3, exp4 = EvolveHelper("EXP II")
            end

            if exp3 >= 3 or exp2 >= 3 then
                isEvolvingEXP = true
            elseif exp1 >= 2 then
                exp1, exp2, exp3, exp4 = EvolveHelper("EXP I")
            else
                break
            end
            if exp1 == previous[1] and exp2 == previous[2] and exp3 == previous[3] and exp4 == previous[4] then
                unchanged = unchanged + 1
                if unchanged >= 10 then KP.Report("EXP evolution", "Inventory did not change after repeated attempts; stopped."); break end
            else unchanged = 0 end
            task.wait(0.5)
        end
        if Settings.webhook_exp_evolve then
            SendWebhook({
                {["name"] = "EXP IV", ["value"] = exp4, ["inline"] = true},
                {["name"] = "EXP III", ["value"] = exp3, ["inline"] = true},
                {["name"] = "EXP II", ["value"] = exp2, ["inline"] = true},
                {["name"] = "EXP I", ["value"] = exp1, ["inline"] = true}
            })
        end
    end

    HideSummonGUI()
    isEvolvingEXP = false
end

function AutoTower()
    local player = game:GetService("Players").LocalPlayer
    local towerteleporter = workspace.Queue.InteractionsV2:FindFirstChild("Script633")
    if not towerteleporter then return end

    firetouchinterest(player.Character.HumanoidRootPart, towerteleporter, 0)
    task.wait()
    firetouchinterest(player.Character.HumanoidRootPart, towerteleporter, 1)
    task.wait(1.5)

    local tls = player.PlayerGui:FindFirstChild("HUD")
    if tls then tls = tls:FindFirstChild("TowerLevelSelector") end
    if not tls then task.wait(1) end
    if not tls then tls = player.PlayerGui:FindFirstChild("HUD") and player.PlayerGui.HUD:FindFirstChild("TowerLevelSelector") end

    if tls then
        local highest = nil
        local highestNum = 0
        for _, child in pairs(tls:GetDescendants()) do
            if child:IsA("TextButton") and child.Visible then
                local num = tonumber(child.Name)
                if num and num > highestNum then
                    highestNum = num
                    highest = child
                end
            end
        end
        if highest then
            pcall(function() firesignal(highest.Activated) end)
            task.wait(0.3)
            pcall(function() firesignal(highest.MouseButton1Click) end)
            task.wait(0.3)
            pcall(function() fireclick(highest) end)
            task.wait(0.5)
        end
    end

    game:GetService("ReplicatedStorage").Remotes.Input:FireServer(towerteleporter.Name .. "Start")
end

function AutoJoinGame()
    local runtime = _kpEnv.KP_Runtime
    runtime.autoJoinToken = (runtime.autoJoinToken or 0) + 1
    local autoJoinToken = runtime.autoJoinToken

    local function AutoJoinActive()
        return ScriptAlive() and Settings.auto_join_game and
            _kpEnv.KP_Runtime and _kpEnv.KP_Runtime.autoJoinToken == autoJoinToken
    end

    local function WaitForAutoJoin(seconds)
        local deadline = tick() + math.max(0, tonumber(seconds) or 0)
        while AutoJoinActive() and tick() < deadline do
            task.wait(math.min(0.05, math.max(0, deadline - tick())))
        end
        return AutoJoinActive()
    end

    local function NormalizeStoryText(value)
        return tostring(value or ""):lower():gsub("<.->", ""):gsub("[%s%p_]+", "")
    end

    local function IsGuiObjectVisible(obj)
        local cur = obj
        while cur and cur ~= Player.PlayerGui do
            if cur:IsA("GuiObject") and not cur.Visible then return false end
            cur = cur.Parent
        end
        return true
    end

    local function GetGuiObjectText(obj)
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            return tostring(obj.Text or "")
        end
        local label = obj:FindFirstChildWhichIsA("TextLabel", true)
        if label then return tostring(label.Text or "") end
        return ""
    end

    local function GetDesiredStoryLevel(highestAvailable)
        local selected = math.floor(tonumber(Settings.auto_story_target) or 0)
        local maxStory = math.floor(tonumber(get_number_missions()) or 210)
        highestAvailable = math.floor(tonumber(highestAvailable) or 0)
        local unlocked = 0
        pcall(function()
            local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
            local server = remotes and remotes:FindFirstChild("Server")
            if server and server:IsA("RemoteFunction") then
                unlocked = tonumber(server:InvokeServer("Data", "StoryLevel")) or unlocked
            end
        end)
        if unlocked <= 0 and DataFolderClient ~= nil then
            pcall(function() unlocked = tonumber(DataFolderClient.Get("StoryLevel")) or unlocked end)
        end
        local highestUnlocked = unlocked > 0 and unlocked or highestAvailable
        if selected <= 0 or selected >= maxStory then
            return highestUnlocked
        end
        if highestUnlocked > 0 then
            return math.min(selected, highestUnlocked)
        end
        return selected
    end

    local function GetGuiStoryLevelNumber(obj)
        local values = {
            tostring(obj.Name or ""),
            GetGuiObjectText(obj)
        }
        local parent = obj.Parent
        for _ = 1, 3 do
            if not parent then break end
            table.insert(values, tostring(parent.Name or ""))
            table.insert(values, GetGuiObjectText(parent))
            parent = parent.Parent
        end

        for _, value in ipairs(values) do
            local text = tostring(value or "")
            local exact = tonumber(text)
            if exact then return exact end
            local prefixed = text:match("^_?(%d+)$")
            if prefixed then return tonumber(prefixed) end
            local titled = text:match("^(%d+)%s*[%-%./:]")
            if titled then return tonumber(titled) end
        end
        return nil
    end

    local function IsStorySelectorObject(obj)
        local cur = obj
        while cur and cur ~= Player.PlayerGui do
            local name = NormalizeStoryText(cur.Name)
            if name:find("storymodechooser", 1, true) or
                name:find("missionchooser", 1, true) or
                name:find("towerlevelselector", 1, true) then
                return true
            end
            cur = cur.Parent
        end
        return false
    end

    local function SelectStoryTargetFromGui(desired)
        desired = math.floor(tonumber(desired) or GetDesiredStoryLevel(0))
        if desired <= 0 then return false end

        local missionNumber = math.max(1, math.ceil(desired / 6))
        local stageNumber = ((desired - 1) % 6) + 1

        local function ClickGuiTarget(root)
            if not root then return false end
            if root:IsA("TextButton") or root:IsA("ImageButton") then
                return KP_ClickGuiObject(root, 0.03)
            end
            local namedClick = root:FindFirstChild("MissionClick", true)
            if namedClick and (namedClick:IsA("TextButton") or namedClick:IsA("ImageButton")) then
                return KP_ClickGuiObject(namedClick, 0.03)
            end
            local button = root:FindFirstChildWhichIsA("TextButton", true) or
                root:FindFirstChildWhichIsA("ImageButton", true)
            if button then return KP_ClickGuiObject(button, 0.03) end
            local cur = root.Parent
            for _ = 1, 3 do
                if not cur or cur == Player.PlayerGui then break end
                if cur:IsA("TextButton") or cur:IsA("ImageButton") then
                    return KP_ClickGuiObject(cur, 0.03)
                end
                cur = cur.Parent
            end
            return false
        end

        local function FindMissionCard()
            local bestCard = nil
            local bestMission = 0
            for _, obj in ipairs(Player.PlayerGui:GetDescendants()) do
                if obj:IsA("GuiObject") and IsGuiObjectVisible(obj) and IsStorySelectorObject(obj) and
                    obj:FindFirstChild("MissionTitle", true) then
                    local number = tonumber(tostring(obj.Name):match("^_?(%d+)$"))
                    if number then
                        if number == missionNumber then return obj end
                        if number <= missionNumber and number > bestMission then
                            bestMission = number
                            bestCard = obj
                        end
                    end
                end
            end
            return bestCard
        end

        local function IsInsideMissionCard(obj)
            local cur = obj
            while cur and cur ~= Player.PlayerGui do
                if cur:IsA("GuiObject") and tonumber(tostring(cur.Name):match("^_?(%d+)$")) and
                    cur:FindFirstChild("MissionTitle", true) then
                    return true
                end
                cur = cur.Parent
            end
            return false
        end

        local function GetExactStageNumber(obj)
            local values = {
                tostring(obj.Name or ""),
                GetGuiObjectText(obj)
            }
            local parent = obj.Parent
            for _ = 1, 2 do
                if not parent or parent == Player.PlayerGui then break end
                table.insert(values, tostring(parent.Name or ""))
                table.insert(values, GetGuiObjectText(parent))
                parent = parent.Parent
            end

            for _, value in ipairs(values) do
                local text = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
                local exact = text:match("^_?(%d+)$")
                if exact then return tonumber(exact) end
            end
            return nil
        end

        local function FindStageButton()
            local fallback = nil
            for _, obj in ipairs(Player.PlayerGui:GetDescendants()) do
                if obj:IsA("GuiObject") and
                    IsGuiObjectVisible(obj) and IsStorySelectorObject(obj) and
                    not IsInsideMissionCard(obj) then
                    local text = NormalizeStoryText(GetGuiObjectText(obj))
                    if not text:find("start", 1, true) and not text:find("return", 1, true) then
                        local number = GetExactStageNumber(obj)
                        if number == stageNumber then return obj end
                        if number == 1 then fallback = fallback or obj end
                    end
                end
            end
            return fallback
        end

        if not AutoJoinActive() then return false end
        local missionClicked = ClickGuiTarget(FindMissionCard())
        task.wait(0.15)
        if not AutoJoinActive() then return false end
        local stageClicked = ClickGuiTarget(FindStageButton())
        return missionClicked or stageClicked
    end

    local function FindStoryStartButton()
        for _, obj in ipairs(Player.PlayerGui:GetDescendants()) do
            if (obj:IsA("TextButton") or obj:IsA("ImageButton")) and IsGuiObjectVisible(obj) and IsStorySelectorObject(obj) then
                local text = NormalizeStoryText(GetGuiObjectText(obj))
                if text == "start" or text:find("start", 1, true) then
                    return obj
                end
            end
        end
        return nil
    end

    local occupiedTeleporters = setmetatable({}, {__mode = "k"})

    local function IsTeleporterEmpty(teleporter)
        if not teleporter or not teleporter.Parent then return true end
        local surfaceGui = teleporter:FindFirstChildWhichIsA("SurfaceGui")
        local label = surfaceGui and surfaceGui:FindFirstChildWhichIsA("TextLabel", true)
        return label and NormalizeStoryText(label.Text) == "empty" or false
    end

    local function PlayerLeftTeleporter(teleporter)
        if not teleporter or not teleporter.Parent then return true end
        local empty = IsTeleporterEmpty(teleporter)
        if not empty then occupiedTeleporters[teleporter] = true end
        return occupiedTeleporters[teleporter] and empty or false
    end

    local function WaitForStorySelector(teleporter, timeout)
        local deadline = tick() + (tonumber(timeout) or 8)
        while AutoJoinActive() and tick() < deadline do
            if PlayerLeftTeleporter(teleporter) then return nil end
            local startButton = FindStoryStartButton()
            if startButton then return startButton end
            task.wait(0.1)
        end
        return nil
    end

    local function FireStoryStart(teleporter)
        if not AutoJoinActive() or not teleporter or PlayerLeftTeleporter(teleporter) then return false end
        local inputRemote = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
                                :WaitForChild("Input")
        if not AutoJoinActive() or PlayerLeftTeleporter(teleporter) then return false end
        local ok = pcall(function()
            inputRemote:FireServer(unpack({[1] = teleporter.Name .. "Start"}))
        end)
        return ok
    end

    local function SetStoryLevelRemote(teleporter, storyLevel)
        if not AutoJoinActive() or not teleporter then return false end
        storyLevel = math.floor(tonumber(storyLevel) or GetDesiredStoryLevel(0))
        if storyLevel <= 0 then return false end
        Settings.auto_join_story_level = tostring(storyLevel)
        local inputRemote = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
                                :WaitForChild("Input")
        if not AutoJoinActive() or not teleporter.Parent then return false end
        return pcall(function()
            inputRemote:FireServer(teleporter.Name .. "Level", tostring(storyLevel), false)
        end)
    end

    local function TryStartStoryFromGui(teleporter, timeout)
        local startButton = WaitForStorySelector(teleporter, timeout)
        if not startButton then return false end
        local desired = GetDesiredStoryLevel(0)
        if not AutoJoinActive() then return false end
        SetStoryLevelRemote(teleporter, desired)
        SelectStoryTargetFromGui(desired)
        if not WaitForAutoJoin(0.15) then return false end
        SetStoryLevelRemote(teleporter, desired)
        if not WaitForAutoJoin(0.1) then return false end
        startButton = FindStoryStartButton() or startButton
        local clicked = KP_ClickGuiObject(startButton)
        if clicked and teleporter then
            if not WaitForAutoJoin(1) then return false end
            FireStoryStart(teleporter)
        end
        return clicked
    end

    local function GetCurrentStoryProgressFromData()
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local server = remotes and remotes:FindFirstChild("Server")
        if server and server:IsA("RemoteFunction") then
            local ok, value = pcall(function()
                return server:InvokeServer("Data", "StoryLevel")
            end)
            value = ok and tonumber(value) or nil
            if value then return value end
        end

        if DataFolderClient ~= nil then
            local ok, value = pcall(function() return DataFolderClient.Get("StoryLevel") end)
            value = ok and tonumber(value) or nil
            if value then return value end
        end

        return 0
    end

    local function GetCurrentStoryProgress()
        return GetCurrentStoryProgressFromData()
    end

    local function ShouldMoveStoryToWorld2()
        local currentStory = GetCurrentStoryProgress()
        return currentStory >= 126, currentStory
    end

    local function UseTeleporter(teleporter)
        if AutoJoinActive() and teleporter ~= nil then
            firetouchinterest(Player.Character.HumanoidRootPart, teleporter, 0)
            task.wait()
            if not AutoJoinActive() then
                pcall(firetouchinterest, Player.Character.HumanoidRootPart, teleporter, 1)
                return false
            end
            firetouchinterest(Player.Character.HumanoidRootPart, teleporter, 1)
            local active = WaitForAutoJoin(1)
            if active then PlayerLeftTeleporter(teleporter) end
            return active
        end
        return false
    end

    local function QuickStartTeleporter(teleporter, keepQueuePosition)
        if not AutoJoinActive() or teleporter == nil or PlayerLeftTeleporter(teleporter) then return end
        if get_world() == 2 or keepQueuePosition then
            if not WaitForAutoJoin(2) or PlayerLeftTeleporter(teleporter) then return end
            FireStoryStart(teleporter)
        else
            -- W1: SpawnLocation move is required for the server to accept the Start remote.
            if not WaitForAutoJoin(1) then return end
            Player.Character.HumanoidRootPart.CFrame =
                game:GetService("Workspace").SpawnLocation.CFrame
            if not WaitForAutoJoin(1) or PlayerLeftTeleporter(teleporter) then return end
            FireStoryStart(teleporter)
        end
    end

    if Settings.auto_evolve_exp then
        repeat task.wait(0.1) until not AutoJoinActive() or not isEvolvingEXP or
            not Settings.auto_evolve_exp
    end

    if not AutoJoinActive() then return end

    if not WaitForAutoJoin(Settings.auto_join_delay) then return end

    if Settings.advanced_join_settings then
        if Settings.smart_join_auto_exp then
            local tickets = _kpEnv.KP_SmartJoin.WaitForTicketCount(5, AutoJoinActive)
            if not AutoJoinActive() then return end
            if tickets and tickets > 0 then
                if not Settings.smart_join_exp_active then
                    Settings.smart_join_exp_active = true
                    Settings.smart_join_exp_tickets_remaining = tickets
                    Save()
                end
                if get_world() == 2 then
                    UseTeleporter(get_world_teleporter())
                elseif get_world() == 1 then
                    _kpEnv.KP_SmartJoin.EnterEXP(AutoJoinActive)
                end
                return
            elseif tickets ~= nil and Settings.smart_join_exp_active then
                Settings.smart_join_exp_active = false
                Settings.smart_join_exp_tickets_remaining = 0
                Save()
                if get_world() == 1 and Settings.auto_join_mode == "Adventure" then
                    UseTeleporter(get_world_teleporter())
                    return
                end
            end
        elseif Settings.smart_join_exp_active then
            Settings.smart_join_exp_active = false
            Settings.smart_join_exp_tickets_remaining = 0
            Save()
        end
    end

    local args = {}
    local teleporter = nil

    -- TODO: Add server hopper on teleport failed.

    -- Story mode: W1 uses Queue.InteractionsV2 (Script170 etc.)
    -- W2 uses Workspace.Joinables "StoryMode" teleporter.
    if Settings.auto_join_mode == "Story" then
        if get_world() == 1 then
            local StoryTeleporterNames = {
                "Script170", "Script158", "Script395", "Script408", "Script523",
                "Script539", "Script573", "Script600", "Script624", "Script958"
            }
            local moveWorld2, currentStory = ShouldMoveStoryToWorld2()
            if moveWorld2 then
                ShowNotify("Auto Join", "Story " .. tostring(currentStory) .. " reached. Moving to World 2.")
                UseTeleporter(get_world_teleporter())
                return
            end
            local function FindStorySlotW1()
                while AutoJoinActive() do
                    local iv2 = (workspace:FindFirstChild("Queue") and workspace.Queue:FindFirstChild("InteractionsV2"))
                    if iv2 then
                        for _, v in pairs(iv2:GetChildren()) do
                            if table.find(StoryTeleporterNames, v.Name) ~= nil and
                                v.ClassName == "Part" and
                                IsTeleporterEmpty(v) then
                                return v
                            end
                        end
                    end
                    task.wait()
                end
                return nil
            end
            local slot = FindStorySlotW1()
            if not slot then return end
            if not UseTeleporter(slot) then return end
            if not WaitForAutoJoin(0.5) or PlayerLeftTeleporter(slot) then return end
            moveWorld2, currentStory = ShouldMoveStoryToWorld2()
            if moveWorld2 then
                ShowNotify("Auto Join", "Story " .. tostring(currentStory) .. " reached. Moving to World 2.")
                UseTeleporter(get_world_teleporter())
                return
            end
            if TryStartStoryFromGui(slot, 8) then return end
            if not AutoJoinActive() or PlayerLeftTeleporter(slot) then return end
            QuickStartTeleporter(slot, true)
        elseif get_world() == 2 then
            repeat task.wait() until not AutoJoinActive() or #game:GetService("Workspace"):GetChildren() > 0
            if not AutoJoinActive() then return end
            local currentStory = GetCurrentStoryProgress()
            if currentStory > 0 and currentStory <= 126 then
                ShowNotify("Auto Join", "Story " .. tostring(currentStory) .. " is still World 1. Staying in World 2.")
                return
            end
            local function FindStorySlotW2()
                while AutoJoinActive() do
                    local joinables = game:GetService("Workspace"):FindFirstChild("Joinables")
                    if joinables then
                        for _, v in pairs(joinables:GetChildren()) do
                            if v.Name == "StoryMode" and v.ClassName == "Part" and
                                IsTeleporterEmpty(v) then
                                return v
                            end
                        end
                    end
                    -- Fallback: try InteractionsV2 if it exists in W2
                    local iv2 = (workspace:FindFirstChild("Queue") and workspace.Queue:FindFirstChild("InteractionsV2"))
                    if iv2 then
                        local StoryTeleporterNames = {
                            "Script170", "Script158", "Script395", "Script408", "Script523",
                            "Script539", "Script573", "Script600", "Script624", "Script958"
                        }
                        for _, v in pairs(iv2:GetChildren()) do
                            if table.find(StoryTeleporterNames, v.Name) ~= nil and
                                v.ClassName == "Part" and
                                IsTeleporterEmpty(v) then
                                return v
                            end
                        end
                    end
                    task.wait()
                end
                return nil
            end
            local slot = FindStorySlotW2()
            if not slot then return end
            if not UseTeleporter(slot) then return end
            if not WaitForAutoJoin(0.5) or PlayerLeftTeleporter(slot) then return end
            currentStory = GetCurrentStoryProgress()
            if currentStory > 0 and currentStory <= 126 then
                ShowNotify("Auto Join", "Story " .. tostring(currentStory) .. " is still World 1. Staying in World 2.")
                return
            end
            if TryStartStoryFromGui(slot, 8) then return end
            if not AutoJoinActive() or PlayerLeftTeleporter(slot) then return end
            QuickStartTeleporter(slot, true)
        end
        return
    end

    if get_world() == 1 then
        -- TODO: Teleport to teleporter location if no teleporters loaded.
        local function FindTeleporter(Teleporters)
            local Found = false

            while not Found and AutoJoinActive() do
                for _, v in pairs(Teleporters()) do
                    if v.ClassName == "Part" and
                        IsTeleporterEmpty(v) then
                        Found = true
                        return v
                    end
                end

                task.wait()
            end

            return nil
        end
        local function GetStoryTeleporters()
            local Teleporters = {}
            local TeleporterNames = {
                "Script170", "Script158", "Script395", "Script408", "Script523",
                "Script539", "Script573", "Script600", "Script624", "Script958"
            }

            local queue = workspace:FindFirstChild("Queue")
            local interactions = queue and queue:FindFirstChild("InteractionsV2")
            for _, v in pairs(interactions and interactions:GetChildren() or {}) do
                if table.find(TeleporterNames, v.Name) ~= nil then
                    table.insert(Teleporters, v)
                end
            end

            return Teleporters
        end
        local function GetInfiniteTeleporters()
            local Teleporters = {}
            local TeleporterNames = {
                "Script209", "Script222", "Script381", "Script405", "Script448",
                "Script58", "Script647", "Script716"
            }

            local queue = workspace:FindFirstChild("Queue")
            local interactions = queue and queue:FindFirstChild("InteractionsV2")
            for _, v in pairs(interactions and interactions:GetChildren() or {}) do
                if table.find(TeleporterNames, v.Name) ~= nil then
                    table.insert(Teleporters, v)
                end
            end

            return Teleporters
        end
        local function SetStoryMap(teleporter)
            if teleporter ~= nil then
                Settings.auto_join_story_level = tostring(GetDesiredStoryLevel(GetCurrentStoryProgress()))
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(
                    teleporter.Name .. "Level",
                    tostring(Settings.auto_join_story_level),
                    false)
            end
        end
        local function SetInfiniteMap(teleporter)
            if AutoJoinActive() and teleporter ~= nil and teleporter.Parent then
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(
                    teleporter.Name .. "Level",
                    Settings.auto_join_infinite_level,
                    false)
            end
        end
        local function TeleportToWorld2()
            UseTeleporter(get_world_teleporter())
        end
        if Settings.auto_join_mode == "Infinite" then
            if InfiniteMapTable[Settings.auto_join_infinite_level] == "Gauntlet" or
                InfiniteMapTable[Settings.auto_join_infinite_level] ==
                "Training" then
                TeleportToWorld2()
                return
            end
            teleporter = FindTeleporter(GetInfiniteTeleporters)
            if not UseTeleporter(teleporter) then return end
            SetInfiniteMap(teleporter)
        elseif Settings.auto_join_mode == "Adventure" then
            TeleportToWorld2()
            return
        elseif Settings.auto_join_mode == "Time Chamber" then
            UseTeleporter(game:GetService("Workspace").Queue.Interactions
                              .Script548)
        elseif Settings.auto_join_mode == "Team Event" then
            for _, v in pairs(game:GetService("Workspace").Queue:GetChildren()) do
                if v.Name == "Model" and v:FindFirstChild("PortalPart") ~= nil then
                    UseTeleporter(v:FindFirstChild("PortalPart"))
                    break
                end
            end
        elseif Settings.auto_join_mode == "Bakugan Event" then
            UseTeleporter(game:GetService("Workspace").Queue.BakuganEventArea
                              .Script412)
        end
        QuickStartTeleporter(teleporter)
    elseif get_world() == 2 then
        local function FindTeleporter(Teleporters, Mode)
            local Found = false

            while not Found and AutoJoinActive() do
                for _, v in pairs(Teleporters()) do
                    if (Mode == nil or v.Name == Mode) and v.ClassName == "Part" and
                        IsTeleporterEmpty(v) then
                        Found = true
                        return v
                    end
                end

                task.wait()
            end

            return nil
        end
        local function SetInfiniteMap(teleporter)
            if AutoJoinActive() and teleporter ~= nil and teleporter.Parent then
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(
                    "InfiniteModeLevel",
                    Settings.auto_join_infinite_level,
                    false)
            end
        end
        local function SetAdventureMap(teleporter)
            if AutoJoinActive() and teleporter ~= nil and teleporter.Parent then
                game:GetService("ReplicatedStorage").Remotes.Input:FireServer(
                    "AdventureModeLevel",
                    Settings.auto_join_adventure_level,
                    false)
            end
        end
        local function TeleportToWorld1()
            UseTeleporter(get_world_teleporter())
        end
        local teleporter = nil
        if Settings.auto_join_mode == "Infinite" then
            if InfiniteMapTable[Settings.auto_join_infinite_level] == "Farm" then
                TeleportToWorld1()
                return
            end
            repeat task.wait(0.1) until not AutoJoinActive() or (workspace:FindFirstChild("Joinables") and #workspace.Joinables:GetChildren() > 0)
            if not AutoJoinActive() then return end
            teleporter = FindTeleporter(
                             function()
                                 local joinables = workspace:FindFirstChild("Joinables")
                                 return joinables and joinables:GetChildren() or {}
                             end,
                             "InfiniteMode")
            if not UseTeleporter(teleporter) then return end
            SetInfiniteMap(teleporter)
        elseif Settings.auto_join_mode == "Adventure" then
            repeat task.wait(0.1) until not AutoJoinActive() or (workspace:FindFirstChild("Joinables") and #workspace.Joinables:GetChildren() > 0)
            if not AutoJoinActive() then return end
            teleporter = FindTeleporter(
                             function()
                                 local joinables = workspace:FindFirstChild("Joinables")
                                 return joinables and joinables:GetChildren() or {}
                             end,
                             "AdventureMode")
            if not UseTeleporter(teleporter) then return end
            SetAdventureMap(teleporter)
        elseif Settings.auto_join_mode == "Time Chamber" then
            TeleportToWorld1()
            return
        elseif Settings.auto_join_mode == "Team Event" then
            TeleportToWorld1()
            return
        elseif Settings.auto_join_mode == "Bakugan Event" then
            TeleportToWorld1()
            return
        end
        QuickStartTeleporter(teleporter)
        --[[elseif get_world() == -2 then -- team event map (reaper's base)
        for _, v in pairs(game:GetService("Workspace"):GetChildren()) do
            if v.Name == "Model" and v:FindFirstChild("Meshes/senkaimon2 (1)") ~=
                nil then
                Player.Character.HumanoidRootPart.CFrame = v:FindFirstChild(
                                                               "Meshes/senkaimon2 (1)").CFrame
                break
            end
        end]] --
    end
end

function AutoSkipGUI()
    local SummonGUI = GUI:WaitForChild("Summon")

    while ScriptAlive() and Settings.auto_skip_gui do
        local status, err = pcall(function()
            -- TODO: Stop when other things are opened.
            if SummonGUI:FindFirstChild('Skip').Visible then
                game:GetService('VirtualUser'):ClickButton1(Vector2.new(
                                                                workspace.CurrentCamera
                                                                    .ViewportSize
                                                                    .X / 2,
                                                                workspace.CurrentCamera
                                                                    .ViewportSize
                                                                    .Y / 2))
            end
        end)

        task.wait(0.2)
    end
end

local function AnonMode()
    local player = game.Players.LocalPlayer
    local runtime = _kpEnv.KP_Runtime
    runtime.anonRefs = runtime.anonRefs or setmetatable({}, {__mode = "k"})
    runtime.restoreAnonymous = function()
        for obj, state in pairs(runtime.anonRefs) do
            if obj.Parent then pcall(function() for property, value in pairs(state) do obj[property] = value end end) end
        end
        runtime.anonRefs = setmetatable({}, {__mode = "k"})
    end

    local function ApplyAnonName(rootOnly)
        local anonName = tostring(Settings.anonymous_mode_name or "KarmaPanda")
        if anonName == "" then anonName = "KarmaPanda" end
        local realName = tostring(player.Name or "")
        local displayName = tostring(player.DisplayName or "")

        local function IsPlayerName(text)
            text = tostring(text or "")
            return text == realName or (displayName ~= "" and text == displayName)
        end

        local function RenameObject(obj)
            if (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) and
                (IsPlayerName(obj.Text) or runtime.anonRefs[obj]) then
                runtime.anonRefs[obj] = runtime.anonRefs[obj] or {Text = obj.Text, TextColor3 = obj.TextColor3}
                obj.Text = anonName
                pcall(function() obj.TextColor3 = Color3.fromRGB(180, 30, 30) end)
            end
        end

        local function RenameText(root)
            if not root then return end
            pcall(function() RenameObject(root) end)
            for _, desc in ipairs(root:GetDescendants()) do
                pcall(function() RenameObject(desc) end)
            end
        end

        pcall(function()
            local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                runtime.anonRefs[humanoid] = runtime.anonRefs[humanoid] or {DisplayName = humanoid.DisplayName}
                humanoid.DisplayName = anonName
            end
        end)

        if rootOnly then
            RenameText(rootOnly)
            return
        end

        pcall(function() RenameText(game:GetService("CoreGui"):FindFirstChild("PlayerList")) end)
        pcall(function() RenameText(player:FindFirstChild("PlayerGui")) end)

        pcall(function()
            local roots = {player.Character}
            local camera = workspace.CurrentCamera or workspace:FindFirstChild("Camera")
            if camera then
                table.insert(roots, camera:FindFirstChild(realName))
                if displayName ~= "" then table.insert(roots, camera:FindFirstChild(displayName)) end
            end
            table.insert(roots, workspace:FindFirstChild("PlayerCharacters"))
            for _, root in ipairs(roots) do RenameText(root) end
        end)
    end

    ApplyAnonName()
    if runtime.anonymousModeHooksReady then return end
    runtime.anonymousModeHooksReady = true

    TrackConnection(player.CharacterAdded:Connect(function()
        if Settings.anonymous_mode then task.defer(ApplyAnonName) end
    end))

    local function WatchDescendants(root)
        if root then
            TrackConnection(root.DescendantAdded:Connect(function(desc)
                if Settings.anonymous_mode then task.defer(ApplyAnonName, desc) end
            end))
        end
    end

    WatchDescendants(player:FindFirstChild("PlayerGui"))
    pcall(function() WatchDescendants(game:GetService("CoreGui"):FindFirstChild("PlayerList")) end)
    pcall(function() WatchDescendants(workspace.CurrentCamera or workspace:FindFirstChild("Camera")) end)
    WatchDescendants(workspace:FindFirstChild("PlayerCharacters"))
end

-- All toggle-started workers share a lifetime with their children and connections.
-- Zone placement is separate from macro playback. No enemy polling or per-frame workers.
do
local AP = {team = {}, revision = 0, status = "Stopped", failures = {}, blocked = {}, nextScan = 0}
KP.AutoPlacement = AP
function AP.MapKey()
    local stage = game.ReplicatedStorage:FindFirstChild("STORYMODE_VALUE")
    if stage and tonumber(stage.Value) then return tostring(game.PlaceId) .. ":" .. tostring(stage.Value) end
    return tostring(game.PlaceId) .. ":session:" .. tostring(game.JobId)
end
function AP.Zones()
    Settings.auto_place_maps=Settings.auto_place_maps or {}
    local key=AP.MapKey()
    local zones=Settings.auto_place_maps[key]
    if not zones then
        zones={}
        if Settings.auto_place_map==key then
            for index,old in ipairs(Settings.auto_place_zones or {}) do
                if index<=4 then zones[index]=DeepCopy(old);zones[index].placed=old.placed~=false;zones[index].manual=old.manual~=false end
            end
        end
        Settings.auto_place_maps[key]=zones
    end
    for index=1,4 do
        if not zones[index] then zones[index]={x=0,y=0,z=0,size=Settings.auto_place_size,enabled=index==1,placed=false,manual=false} end
    end
    Settings.auto_place_map,Settings.auto_place_zones=key,zones
    return zones
end
function AP.NeedsZones()
    local zones=AP.Zones()
    for _,zone in ipairs(zones) do if zone.enabled and not zone.placed and not zone.manual then return true end end
    return false
end
function AP.UnitDataLimit(name)
    local ok,stats=pcall(get_stat,name)
    if ok and type(stats)=="table" then
        for _,key in ipairs({"MaxPlacement","MaxPlacements","MaxUnits","PlacementLimit","MaxUnitCount"}) do
            local n=tonumber(stats[key])
            if n and n==n and n>=1 and n<math.huge then return math.clamp(math.floor(n),1,8) end
        end
    end
end
function AP.MaxAllowed(name)
    if AP.IsFarm(name) then return 1 end
    return AP.UnitDataLimit(name) or 8
end
function AP.MaxCount(name,config) return math.min(config.limit,AP.MaxAllowed(name)) end
function AP.RefreshTeam()
    AP.team = get_loadout_units()
    for index, name in ipairs(AP.team) do
        if not Settings.auto_place_units[name] then
            Settings.auto_place_units[name] = {enabled = true, priority = AP.IsFarm(name) and 100 or math.max(10, 20-index), limit = AP.IsFarm(name) and 1 or (AP.UnitDataLimit(name) or 1), zones = {1,2,3,4}, surface = "Auto"}
        end
        local config=Settings.auto_place_units[name]
        if config.upgradeCap==nil then config.upgradeCap=math.min(20,Settings.auto_place_upgrade_level or 20) end
        config.limit=AP.MaxCount(name,config)
        if not config.zones then config.zones=config.zone and config.zone>0 and {math.min(4,config.zone)} or {1,2};config.zone=nil end
        config.surface="Auto"
    end
    return AP.team
end
function AP.IsFarm(name)
    local text=tostring(name):lower()
    if text:find("speedwagon",1,true) or text:find("bulma",1,true) or text:find("farm",1,true) then return true end
    local ok,stats=pcall(get_stat,name)
    if ok and type(stats)=="table" then
        for _,key in ipairs({"Income","MoneyPerWave","CashPerWave","FarmIncome"}) do
            if tonumber(stats[key]) and tonumber(stats[key])>0 then return true end
        end
    end
    return false
end
function AP.Setup()
    AP.RefreshTeam()
    if not Settings.auto_place_ready and #AP.team>0 then
        for _,name in ipairs(AP.team) do
            local config=Settings.auto_place_units[name]
            config.enabled=true
            if AP.IsFarm(name) then config.priority=100;config.limit=1 end
        end
        Settings.auto_place_auto_zones=true
        Settings.auto_place_ready=true
        Save()
        if AP.RefreshUI then AP.RefreshUI() end
    end
end
function AP.Changed()
    AP.revision = AP.revision + 1
    AP.failures, AP.blocked = {}, {}
    AP.Render()
    if AP.RefreshUI then AP.RefreshUI() end
end
function AP.Render()
    if AP.folder then AP.folder:Destroy(); AP.folder = nil end
    if not ScriptAlive() or is_lobby() or not Settings.auto_place_show_zones then return end
    local zones = AP.Zones()
    if #zones == 0 then return end
    AP.folder = Instance.new("Folder")
    AP.folder.Name = "KP_PlacementZones"
    AP.folder.Parent = workspace.CurrentCamera or workspace
    for index, zone in ipairs(zones) do
        if zone.enabled and zone.placed then
            local part = Instance.new("Part")
            part.Name = "Zone " .. index
            part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
            part.CastShadow = false
            part.Color = Color3.fromRGB(180, 30, 30)
            part.Material = Enum.Material.SmoothPlastic
            part.Transparency = Settings.auto_place_transparency
            part.Shape = Enum.PartType.Cylinder
            part.Size = Vector3.new(0.12, zone.size, zone.size)
            part.CFrame = CFrame.new(zone.x, zone.y + 0.15, zone.z) * CFrame.Angles(0,0,math.pi/2)
            part.Parent = AP.folder
        end
    end
end
function AP.SetZone(index, position)
    if is_lobby() then ShowNotify("Auto Placement", "Place zones inside a match."); return false end
    local zones = AP.Zones()
    index=math.clamp(math.floor(index),1,4)
    local size=zones[index].size
    zones[index] = {x=position.X,y=position.Y,z=position.Z,size=size,enabled=true,placed=true,manual=true}
    AP.Changed(); Save()
    return true
end
function AP.ArmZone(index)
    if is_lobby() then ShowNotify("Auto Placement", "Place zones inside a match."); return end
    if AP.pickConnection then KP.Disconnect(AP.pickConnection) end
    local inputService = game:GetService("UserInputService")
    AP.pickConnection = TrackConnection(inputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.Escape then KP.Disconnect(AP.pickConnection); AP.pickConnection = nil; return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        local point = input.Position
        if input.UserInputType == Enum.UserInputType.MouseButton1 then point = inputService:GetMouseLocation() end
        local ray = camera:ScreenPointToRay(point.X, point.Y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ignore = {}
        for _, object in pairs({workspace:FindFirstChild("Enemies"), workspace:FindFirstChild("Unit"), AP.folder, Player.Character}) do
            if object then table.insert(ignore, object) end
        end
        params.FilterDescendantsInstances = ignore
        local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
        if not hit then ShowNotify("Auto Placement", "No map surface hit. Click or tap the map again."); return end
        KP.Disconnect(AP.pickConnection); AP.pickConnection = nil
        AP.SetZone(index, hit.Position)
        ShowNotify("Auto Placement", "Zone placed. Adjust its size below.")
    end))
    ShowNotify("Auto Placement", "Click or tap the map to place the zone. Esc cancels.")
end
function AP.DetectRoutes()
    -- Examine only named path containers; never scan the enemy hierarchy.
    local roots, seen = {}, {}
    local names = {paths=true,path=true,pathway=true,pathways=true,waypoints=true,nodes=true,routes=true}
    local parents = {workspace}
    local map = workspace:FindFirstChild("Map")
    if map then table.insert(parents, map) end
    for _, parent in ipairs(parents) do
        for _, child in ipairs(parent:GetChildren()) do
            local name=child.Name:lower()
            if names[name] or name:match("^pathway%d+$") or name:match("^path%d+$") or name:match("^route%d+$") then table.insert(roots, child) end
        end
    end
    local groups, ends, queue, head = {}, {}, table.clone(roots), 1
    local function position(node)
        if node:IsA("BasePart") then return node.Position end
        if node:IsA("Attachment") then return node.WorldPosition end
        if node:IsA("Vector3Value") then return node.Value end
        if node:IsA("CFrameValue") then return node.Value.Position end
    end
    while head <= #queue and head <= 4096 and ScriptAlive() do
        local node = queue[head]; head = head + 1
        if not seen[node] then
            seen[node] = true
            local point = position(node)
            if point then
                local name = node.Name:lower():gsub("[%s_%-]", "")
                local group = groups[node.Parent] or {count=0,nodes={}}; groups[node.Parent] = group
                if name == "end" or name == "endpoint" or name == "finish" or name == "goal" then group.explicit = point end
                if name == "start" or name == "entrance" or name == "spawn" then group.start = point end
                local index = tonumber(node.Name) or tonumber(name:match("^waypoint(%d+)$")) or tonumber(name:match("^node(%d+)$"))
                if index then
                    group.count = group.count + 1
                    table.insert(group.nodes,{index=index,point=point})
                    if not group.index or index > group.index then group.index, group.point = index, point end
                end
            end
            if #queue < 8192 then for _, child in ipairs(node:GetChildren()) do table.insert(queue, child) end end
        end
        if head % 128 == 0 then task.wait() end
    end
    for _,group in pairs(groups) do
        table.sort(group.nodes,function(a,b)return a.index<b.index end)
        local nodes=group.nodes
        local finish=group.explicit or (#nodes>=2 and nodes[#nodes].point)
        local start=group.start or (#nodes>=2 and nodes[1].point)
        if finish and start then table.insert(ends,{finish=finish,start=start,
            beforeEnd=#nodes>=2 and nodes[#nodes-1].point or start,
            afterStart=#nodes>=2 and nodes[2].point or finish}) end
    end
    table.sort(ends,function(a,b)
        if a.finish.X~=b.finish.X then return a.finish.X<b.finish.X end
        if a.finish.Z~=b.finish.Z then return a.finish.Z<b.finish.Z end
        if a.start.X~=b.start.X then return a.start.X<b.start.X end
        return a.start.Z<b.start.Z
    end)
    return ends
end
function AP.DetectEnds()
    local result={};for _,route in ipairs(AP.DetectRoutes())do table.insert(result,route.finish)end;return result
end
function AP.AutoZones()
    if is_lobby() or not AP.NeedsZones() then return false end
    if AP.detecting and coroutine.status(AP.detecting)~="dead" then return false end
    AP.detecting=coroutine.running()
    local revision,map=AP.revision,AP.MapKey()
    local ok,routes=pcall(AP.DetectRoutes)
    AP.detecting=false
    if not ok then KP.Report("Lane detection",routes);return false end
    if not ScriptAlive() or revision~=AP.revision or map~=AP.MapKey() then return false end
    local zones,changed=AP.Zones(),false
    local function inset(endpoint,toward)
        local delta=Vector3.new(toward.X-endpoint.X,0,toward.Z-endpoint.Z)
        if delta.Magnitude<0.01 then return endpoint end
        return endpoint+delta*(math.min(6,delta.Magnitude/2)/delta.Magnitude)
    end
    local route=routes[1]
    MacroPlacement.Refresh()
    local entrances={}
    for _,lane in ipairs(routes) do
        local point=inset(lane.start,lane.afterStart)
        local duplicate=false
        for _,entry in ipairs(entrances) do if (lane.start-entry.start).Magnitude<4 then duplicate=true;break end end
        if not duplicate then table.insert(entrances,{start=lane.start,point=point}) end
    end
    local function taken(point)
        for _,zone in ipairs(zones) do
            if zone.placed and AP.Contains(zone,point) then return true end
        end
        return false
    end
    for index=1,4 do
        local zone=zones[index]
        if zone.enabled and not zone.placed and not zone.manual then
            local point
            if route then
                if index==1 then point=inset(route.finish,route.beforeEnd)
                else
                    for _,entry in ipairs(entrances) do if not taken(entry.point) then point=entry.point;break end end
                end
            elseif index==1 then
                local root=Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
                if root then point=root.Position end
            end
            if point then
                point=AP.Project(point,"Ground") or point
                zone.x,zone.y,zone.z=point.X,point.Y,point.Z
                zone.placed=true;changed=true
            end
        end
    end
    if changed then AP.status=route and "Zones ready" or "Starter zone ready";AP.Changed();Save() end
    return changed
end
function AP.Surface(name, config)
    local ok, stats = pcall(get_stat, name)
    if ok and type(stats) == "table" then
        if stats.Hill == true or stats.Air == true or stats.HillUnit == true then return "Hill" end
        if stats.Hybrid == true then return "Hybrid" end
        for key, value in pairs(stats) do
            if tostring(key):lower():find("place",1,true) or key=="Type" or key=="UnitType" then
                value = tostring(value):lower()
                if value == "hybrid" then return "Hybrid" end
                if value == "hill" or value == "air" then return "Hill" end
                if value == "ground" or value == "base" then return "Ground" end
            end
        end
    end
    return "Ground" -- Ground is the initial probe; the server still confirms every placement.
end
function AP.Contains(zone, point)
    local dx,dz=point.X-zone.x,point.Z-zone.z
    return dx*dx+dz*dz <= (zone.size/2)^2
end
function AP.Candidates(zone)
    local points = {Vector3.new(zone.x,zone.y,zone.z)}
    local step = math.max(Settings.auto_place_spacing, zone.size/8)
    for ring = 1, 4 do
        for x = -ring, ring do
            for z = -ring, ring do
                if math.abs(x) == ring or math.abs(z) == ring then
                    local point = Vector3.new(zone.x+x*step,zone.y,zone.z+z*step)
                    if AP.Contains(zone,point) then table.insert(points,point) end
                end
            end
        end
    end
    return points
end
function AP.Project(point, surface)
    local parts = {}
    if surface ~= "Hill" then for _, part in ipairs(MacroPlacement.base) do table.insert(parts,part) end end
    if surface ~= "Ground" then for _, part in ipairs(MacroPlacement.hill) do table.insert(parts,part) end end
    if #parts == 0 then
        local placeable=workspace:FindFirstChild("Placeable")
        if placeable then
            if AP.surfaceFolder~=placeable or tick()>=(AP.surfaceRefresh or 0) then
                AP.surfaceFolder,AP.surfaceRefresh,AP.surfaceParts=placeable,tick()+5,{}
                local objects=placeable:GetDescendants()
                if placeable:IsA("BasePart") then table.insert(objects,placeable) end
                for _,part in ipairs(objects) do
                    if part:IsA("BasePart") then
                        local node,kind=part,"Ground"
                        while node and node~=placeable do
                            local name=node.Name:lower()
                            if name:find("hill",1,true) or name:find("air",1,true) then kind="Hill";break end
                            node=node.Parent
                        end
                        table.insert(AP.surfaceParts,{part=part,kind=kind})
                    end
                end
            end
            for _,entry in ipairs(AP.surfaceParts) do
                if entry.part.Parent and (surface=="Hybrid" or surface==entry.kind) then table.insert(parts,entry.part) end
            end
        end
    end
    if #parts==0 and workspace:FindFirstChild("Placeable") then return nil end
    local params = RaycastParams.new()
    params.FilterType = #parts>0 and Enum.RaycastFilterType.Include or Enum.RaycastFilterType.Exclude
    local ignore={}
    for _,obj in pairs({workspace:FindFirstChild("Enemies"),workspace:FindFirstChild("Unit"),Player.Character,AP.folder}) do if obj then table.insert(ignore,obj) end end
    params.FilterDescendantsInstances = #parts>0 and parts or ignore
    local hit = workspace:Raycast(point+Vector3.new(0,80,0),Vector3.new(0,-160,0),params)
    if hit and hit.Normal.Y > 0.65 and not MacroPlacement.IsRestricted(hit.Position) then return hit.Position end
    -- Some game placement meshes are deliberately not queryable. Their top plane
    -- is still usable as a candidate, with acceptance checked after the summon.
    for _,part in ipairs(parts) do
        local p=part.CFrame:PointToObjectSpace(point)
        if math.abs(p.X)<=part.Size.X/2 and math.abs(p.Z)<=part.Size.Z/2 then
            local top=part.CFrame:PointToWorldSpace(Vector3.new(p.X,part.Size.Y/2,p.Z))
            if math.abs(top.Y-point.Y)<=80 and not MacroPlacement.IsRestricted(top) then return top end
        end
    end
end
function AP.Free(point, units)
    for _, unit in ipairs(units) do
        local root = unit:FindFirstChild("HumanoidRootPart")
        if root then
            local delta = root.Position-point
            if math.abs(delta.Y) < 14 then
                local footprint = root:FindFirstChild("Part1")
                if footprint and footprint:IsA("BasePart") and MacroPlacement.PointInPartXZ(footprint,point,0.55) then return false end
                if Vector3.new(delta.X,0,delta.Z).Magnitude < Settings.auto_place_spacing then return false end
            end
        end
    end
    return true
end
function AP.Active(context, revision)
    return KP.ContextAlive(context) and Settings.auto_place and not is_lobby() and
        not KP.MissionEnded() and not Settings.macro_record and not Settings.macro_playback and
        (not revision or revision == AP.revision)
end
function AP.TryPlace(context)
    if not AP.Active(context) then return false end
    local zones = AP.Zones()
    AP.savingFor=0
    local folder = workspace:FindFirstChild("Unit")
    if not folder then AP.status = "Waiting for units to load."; return false end
    local units, counts, before = folder:GetChildren(), {}, {}
    for _, unit in ipairs(units) do
        before[unit] = true
        local owner = unit:FindFirstChild("Owner")
        if owner and tostring(owner.Value) == Player.Name then counts[NormalizeUnitVariantName(unit.Name)] = (counts[NormalizeUnitVariantName(unit.Name)] or 0)+1 end
    end
    local ordered = {}
    for _, name in ipairs(AP.team) do
        local config = Settings.auto_place_units[name]
        if config and config.enabled and (counts[NormalizeUnitVariantName(name)] or 0) < AP.MaxCount(name,config) then
            table.insert(ordered,{name=name,config=config})
        end
    end
    table.sort(ordered,function(a,b) if a.config.priority == b.config.priority then return a.name < b.name end; return a.config.priority > b.config.priority end)
    if #ordered == 0 then AP.status = "Waiting: enable team units or raise their count limits."; return false end
    MacroPlacement.Refresh()
    local revision, map = AP.revision, AP.MapKey()
    local probes = 0
    for _, entry in ipairs(ordered) do
        local name, config = entry.name, entry.config
        local surface = AP.Surface(name,config)
        local ok, cost = pcall(get_summon_cost,name)
        local validCost=ok and type(cost)=="number" and cost==cost and cost>=0 and cost<math.huge
        if validCost and (counts[NormalizeUnitVariantName(name)] or 0)>0 and get_money()-Settings.auto_place_reserve<cost then
            AP.status="Checking lower priorities while another "..name.." is unaffordable"
            continue
        end
        if validCost then AP.savingFor=cost end
        if tick() < (AP.blocked[name] or 0) then AP.status="Waiting to retry "..name;return false end
        if not surface then AP.status = name .. ": choose Ground, Hill or Hybrid (type unavailable)."
        elseif not ok or type(cost) ~= "number" or cost ~= cost or cost < 0 or cost == math.huge then AP.status = name .. ": waiting for cost data."
        elseif get_money()-Settings.auto_place_reserve < cost then
            AP.savingFor=cost
            AP.status = "Saving for " .. name .. " (highest eligible priority)."; return false
        else
            local failures = AP.failures[name] or {}; AP.failures[name] = failures
            for _,target in ipairs(AP.OrderZones(name,config,units)) do
                local index,zone=target.index,target.zone
                if zone.enabled and zone.placed then
                    for candidateIndex, candidate in ipairs(AP.Candidates(zone)) do
                        if not AP.Active(context,revision) or map ~= AP.MapKey() then return false end
                        local key = tostring(index)..":"..candidateIndex
                        local point
                        if tick() >= (failures[key] or 0) then point = AP.Project(candidate,surface) end
                        probes = probes + 1
                        if point and AP.Contains(zone,point) and AP.Free(point,units) then
                            local remotes = game.ReplicatedStorage:FindFirstChild("Remotes")
                            local input = remotes and remotes:FindFirstChild("Input")
                            if not input then AP.status = "Waiting for summon remote."; return false end
                            local accepted, request = AddToQueue(input,{"Summon",{Rotation=0,cframe=CFrame.new(point),Unit=name}})
                            if not accepted then AP.status = "Waiting for action queue."; return false end
                            request.ShouldContinue = function()
                                if not (AP.Active(context,revision) and AP.MapKey() == map and Settings.auto_place_units[name] == config and config.enabled and
                                    table.find(get_loadout_units(),name) ~= nil and get_money()-Settings.auto_place_reserve >= cost) then return false end
                                local current, ownCount = folder:GetChildren(), 0
                                for _, unit in ipairs(current) do
                                    local owner=unit:FindFirstChild("Owner")
                                    if owner and tostring(owner.Value)==Player.Name and UnitVariantNamesMatch(unit.Name,name) then ownCount=ownCount+1 end
                                end
                                for _,higherName in ipairs(get_loadout_units()) do
                                    local higher=Settings.auto_place_units[higherName]
                                    if higher and higher.enabled and higher.priority>config.priority then
                                        local higherCount=0
                                        for _,unit in ipairs(current) do
                                            local owner=unit:FindFirstChild("Owner")
                                            if owner and tostring(owner.Value)==Player.Name and UnitVariantNamesMatch(unit.Name,higherName) then higherCount=higherCount+1 end
                                        end
                                        if higherCount<AP.MaxCount(higherName,higher) then
                                            if higherCount==0 then return false end
                                            local priced,higherCost=pcall(get_summon_cost,higherName)
                                            if not priced or type(higherCost)~="number" or higherCost~=higherCost or higherCost<0 or higherCost==math.huge or get_money()-Settings.auto_place_reserve>=higherCost then return false end
                                        end
                                    end
                                end
                                return ownCount < AP.MaxCount(name,config) and table.find(config.zones,index)~=nil and AP.Free(point,current)
                            end
                            AP.status = "Placing " .. name .. " in zone " .. index
                            local deadline = tick()+15
                            while not request.Done and AP.Active(context,revision) and tick()<deadline do task.wait(0.05) end
                            if not request.Done then request.Cancelled=true; return false end
                            if request.Cancelled or not request.Success then return false end
                            deadline = tick()+2.5
                            repeat
                                for _, unit in ipairs(folder:GetChildren()) do
                                    local owner = unit:FindFirstChild("Owner")
                                    if not before[unit] and owner and tostring(owner.Value)==Player.Name and UnitVariantNamesMatch(unit.Name,name) then
                                        AP.assignments=AP.assignments or setmetatable({},{__mode="k"});AP.assignments[unit]=index
                                        AP.savingFor=0
                                        AP.status = "Placed " .. name; return true
                                    end
                                end
                                task.wait(0.1)
                            until not AP.Active(context,revision) or tick()>=deadline
                            failures[key] = tick()+30
                            AP.status = "Placement unconfirmed; trying another point inside the zone."
                            return false
                        end
                        if probes % 16 == 0 then task.wait() end
                    end
                end
            end
            AP.blocked[name] = tick()+5
            AP.status = name .. ": no free allowed surface in its zones. Resize or move a zone."
        end
        return false
    end
    return false
end
function AP.OrderZones(name,config,units)
    local selected={}
    for _,index in ipairs(config.zones or {}) do
        local zone=AP.Zones()[index]
        if zone and zone.enabled and zone.placed then table.insert(selected,{index=index,zone=zone,count=0}) end
    end
    for _,unit in ipairs(units) do
        local owner=unit:FindFirstChild("Owner")
        local root=unit:FindFirstChild("HumanoidRootPart")
        if owner and tostring(owner.Value)==Player.Name and root and UnitVariantNamesMatch(unit.Name,name) then
            local best,distance
            local assigned=AP.assignments and AP.assignments[unit]
            for _,target in ipairs(selected) do
                if target.index==assigned then best=target;break end
                if AP.Contains(target.zone,root.Position) then
                    local delta=root.Position-Vector3.new(target.zone.x,target.zone.y,target.zone.z)
                    if not distance or delta.Magnitude<distance then best,distance=target,delta.Magnitude end
                end
            end
            if best then best.count=best.count+1 end
        end
    end
    table.sort(selected,function(a,b)if a.count==b.count then return a.index<b.index end;return a.count<b.count end)
    return selected
end
function AP.UpgradeCap(name)
    local config=Settings.auto_place_units[name]
    return config and config.upgradeCap or math.min(20,Settings.auto_place_upgrade_level or 20)
end
function AP.TryUpgrade(context)
    if not Settings.auto_place_upgrade or Settings.auto_upgrade or not AP.Active(context) then return false end
    local units=get_units()
    table.sort(units,function(a,b)
        local ac,bc=Settings.auto_place_units[a.Name],Settings.auto_place_units[b.Name]
        local ap,bp=ac and ac.priority or 0,bc and bc.priority or 0
        if ap~=bp then return ap>bp end
        return a.Name<b.Name
    end)
    if #units==0 then return false end
    AP.upgradeAfter=AP.upgradeAfter or setmetatable({},{__mode="k"})
    for _,unit in ipairs(units) do
        local tag=unit:FindFirstChild("UpgradeTag")
        local ok,limit=pcall(get_max_upgrade_level,unit.Name)
        limit=tonumber(limit)
        if tag and ok and limit and limit==limit and limit<math.huge and tag.Value<math.min(limit,AP.UpgradeCap(unit.Name)) and tick()>=(AP.upgradeAfter[unit] or 0) then
            local priced,cost=pcall(get_upgrade_cost,unit.Name,tag.Value+1)
            local reserve=Settings.auto_place_reserve+(AP.savingFor or 0)
            if priced and type(cost)=="number" and cost==cost and cost>=0 and cost<math.huge and get_money()-reserve>=cost then
                local remotes=game.ReplicatedStorage:FindFirstChild("Remotes")
                local remote=remotes and remotes:FindFirstChild("Server")
                if not remote then return false end
                local level,revision,map=tag.Value,AP.revision,AP.MapKey()
                local accepted,request=AddToQueue(remote,{"Upgrade",unit})
                if not accepted then return false end
                request.ShouldContinue=function()
                    local owner=unit:FindFirstChild("Owner")
                    return AP.Active(context,revision) and AP.MapKey()==map and owner and tostring(owner.Value)==Player.Name and Settings.auto_place_upgrade and not Settings.auto_upgrade and
                        unit.Parent~=nil and tag.Parent~=nil and tag.Value==level and
                        level<AP.UpgradeCap(unit.Name) and get_money()-Settings.auto_place_reserve-(AP.savingFor or 0)>=cost
                end
                AP.status="Upgrading "..unit.Name
                local deadline=tick()+15
                while not request.Done and AP.Active(context,revision) and tick()<deadline do task.wait(0.05) end
                if not request.Done then request.Cancelled=true;return false end
                if not request.Cancelled and request.Success then
                    deadline=tick()+1
                    while AP.Active(context,revision) and tag.Parent and tag.Value==level and tick()<deadline do task.wait(0.05) end
                end
                AP.upgradeAfter[unit]=tick()+(tag.Value>level and 0.1 or 2)
                return tag.Value>level
            end
        end
    end
    return false
end
function AP.Run()
    local context = KP.contexts[coroutine.running()]
    local map
    while KP.ContextAlive(context) and Settings.auto_place and not is_lobby() and not KP.MissionEnded() do
        if map ~= AP.MapKey() then map = AP.MapKey(); AP.Changed() end
        AP.Setup()
        if Settings.macro_record or Settings.macro_playback then AP.status = "Paused while macro recording/playback is enabled."
        else
            if AP.NeedsZones() and tick()>=AP.nextScan then AP.nextScan=tick()+10; AP.AutoZones() end
            AP.TryPlace(context)
            AP.TryUpgrade(context)
        end
        task.wait(math.max(0.05,Settings.auto_place_interval))
    end
    AP.status = "Stopped"
end
KP.cleanupAutoPlacement = function()
    if AP.pickConnection then KP.Disconnect(AP.pickConnection); AP.pickConnection=nil end
    if AP.folder then AP.folder:Destroy(); AP.folder=nil end
end
end

function KP.StopFeature(key)
    local context = KP.features[key]
    if context then
        KP.features[key] = nil
        KP.CancelContext(context)
        KP.DiscardQueued(context)
    end
    if key == "auto_cycle_timestop" then KP.autoCycleTimestopRunning = false
    elseif key == "auto_killua" then KP.autoKilluaRunning = false
    elseif key == "auto_target_ability" then KP.autoTargetAbilityRunning = false
    elseif key == "auto_evolve_exp" then isEvolvingEXP = false end
end
function KP.WrapFeature(key, fn)
    return function(...)
        if not ScriptAlive() or not Settings[key] or KP.features[key] then return end
        local context = {connections = {}}
        KP.features[key] = context
        local running = coroutine.running()
        local previous = KP.contexts[running]
        local previousOwner = KP.tasks[running]
        KP.contexts[running], KP.tasks[running] = context, context
        local ok, err = pcall(fn, ...)
        if ok then
            -- Some entry points launch child workers and return immediately (Auto Buff).
            -- Keep their context until those workers finish; completed features can restart.
            while KP.ContextAlive(context) and Settings[key] do
                local pending = KP.queueInFlight and KP.queueInFlight.Context == context or false
                for index = Action_Queue.first, Action_Queue.last do
                    if Action_Queue[index] and Action_Queue[index].Context == context then pending = true; break end
                end
                for child, owner in pairs(KP.tasks) do
                    if child ~= running and owner == context then pending = true; break end
                end
                if not pending then break end
                task.wait(0.1)
            end
            if KP.features[key] == context then KP.StopFeature(key) end
        end
        KP.contexts[running] = previous
        KP.tasks[running] = previousOwner
        if not ok then
            KP.Report(key, err)
            KP.StopFeature(key)
            if Settings[key] and ScriptAlive() then
                KP.contexts[running] = nil
                task.delay(2, function() if KP.startFeatures[key] then task.spawn(KP.startFeatures[key]) end end)
                KP.contexts[running] = previous
            end
        end
    end
end
KP.AutoPlacement.Run = KP.WrapFeature("auto_place", KP.AutoPlacement.Run)
AutoBuff = KP.WrapFeature("auto_buff", AutoBuff)
AutoBattle = KP.WrapFeature("auto_battle", AutoBattle)
AutoUpgrade = KP.WrapFeature("auto_upgrade", AutoUpgrade)
AutoSell = KP.WrapFeature("auto_upgrade_sell", AutoSell)
AutoVoteExtreme = KP.WrapFeature("auto_vote_extreme", AutoVoteExtreme)
AutoSkipWaveSpam = KP.WrapFeature("auto_skip_wave_spam", AutoSkipWaveSpam)
AutoReplay = KP.WrapFeature("auto_replay", AutoReplay)
AutoNextStory = KP.WrapFeature("auto_next_story", AutoNextStory)
AutoEvolveEXP = KP.WrapFeature("auto_evolve_exp", AutoEvolveEXP)
AutoTower = KP.WrapFeature("auto_join_tower", AutoTower)
AutoSkipGUI = KP.WrapFeature("auto_skip_gui", AutoSkipGUI)
KP_AutoCycleTimestop = KP.WrapFeature("auto_cycle_timestop", KP_AutoCycleTimestop)
KP_AutoKillua = KP.WrapFeature("auto_killua", KP_AutoKillua)
KP_AutoTargetAbility = KP.WrapFeature("auto_target_ability", KP_AutoTargetAbility)
KP.startFeatures = {
    auto_place = KP.AutoPlacement.Run,
    auto_buff = AutoBuff, auto_battle = AutoBattle, auto_upgrade = AutoUpgrade,
    auto_upgrade_sell = AutoSell, auto_vote_extreme = AutoVoteExtreme,
    auto_skip_wave_spam = AutoSkipWaveSpam, auto_replay = AutoReplay,
    auto_next_story = AutoNextStory, auto_cycle_timestop = KP_AutoCycleTimestop,
    auto_killua = KP_AutoKillua, auto_target_ability = KP_AutoTargetAbility,
    auto_evolve_exp = AutoEvolveEXP, auto_join_tower = AutoTower, auto_skip_gui = AutoSkipGUI
}
function KP.ApplySettings(imported)
    StopMacroRecord()
    StopMacroPlayback()
    for key in pairs(KP.startFeatures) do KP.StopFeature(key) end
    KP.autoJoinToken = (KP.autoJoinToken or 0) + 1
    Settings = KP.ValidateSettings(imported)
    KP.AutoPlacement.Changed()
    if not table.find(MacroProfileList, Settings.macro_profile) then Settings.macro_profile = MacroProfileList[1] end
    FocusMacroProfile(Settings.macro_profile)
    for _, name in ipairs({"restoreFPS", "restoreAnonymous"}) do if KP[name] then pcall(KP[name]) end end
    if not Settings.delete_map then pcall(RestoreMap) end
    ApplySimplifyEnemies()
    if Settings.delete_map and not is_lobby() then task.spawn(DeleteMap) end
    if Settings.fps_boost then task.spawn(FpsBoost) end
    if Settings.anonymous_mode then task.spawn(AnonMode) end
    if KP.applyRendering then KP.applyRendering(Settings.disable_3d_rendering) end
    ApplyFPSLimit(Settings.fps_limit, false)
    for key, fn in pairs(KP.startFeatures) do
        local lobbyOnly = key == "auto_evolve_exp" or key == "auto_join_tower"
        if Settings[key] and (key == "auto_skip_gui" or lobbyOnly == is_lobby()) then task.spawn(fn) end
    end
    if Settings.auto_join_game and is_lobby() then task.spawn(AutoJoinGame) end
    if (Settings.auto_2x or Settings.auto_3x) and not is_lobby() then task.spawn(AutoChangeSpeed) end
    if Settings.macro_record then task.spawn(StartMacroRecord)
    elseif Settings.macro_playback then task.spawn(StartMacroPlayback) end
    if KP.refreshSettingsUI then KP.refreshSettingsUI() end
    Save()
end
if get_world() ~= -1 and get_world() ~= -2 then
    local lobbyFlag = game.ReplicatedStorage:WaitForChild("Lobby", 30)
    if not lobbyFlag then error("ASTD Lobby state did not load. Please re-execute after loading.") end
    local loading = GUI:FindFirstChild("LoadingScreen")
    local loadingFrame = loading and loading:FindFirstChild("Frame")
    while loadingFrame and loadingFrame.Parent and loadingFrame.Visible and ScriptAlive() do task.wait(0.1) end

    if not is_lobby() then

        pcall(function()
            _G.KP_PreGame = {
                gems = get_gems() or 0,
                gold = get_gold() or 0,
                stardust = get_stardust() or 0
            }
        end)
        pcall(function()
            _G.KP_PreGameUnits = {}
            local inv = GetInventory()
            if inv then
                for _, item in pairs(inv) do
                    _G.KP_PreGameUnits[tostring(item.ID)] = item.Name
                end
            end
        end)
        pcall(function()
            local itemCounts, itemsReady = GetStorageItemCounts()
            if itemsReady and next(itemCounts) == nil then
                task.wait(1)
                itemCounts, itemsReady = GetStorageItemCounts()
            end
            _G.KP_PreGameItems = itemsReady and itemCounts or nil
        end)
        CalculateTimeOffset()
        task.spawn(StartActionQueue)
        if Settings.auto_place then task.spawn(KP.AutoPlacement.Run) end
        if Settings.auto_buff then task.spawn(AutoBuff) end
        if Settings.auto_cycle_timestop then task.spawn(KP_AutoCycleTimestop) end
        if Settings.auto_killua then task.spawn(KP_AutoKillua) end
        if Settings.auto_target_ability then task.spawn(KP_AutoTargetAbility) end
        if Settings.auto_skip_wave_spam then task.spawn(AutoSkipWaveSpam) end
        if Settings.auto_vote_extreme then task.spawn(AutoVoteExtreme) end
        if Settings.auto_2x or Settings.auto_3x then
            task.spawn(AutoChangeSpeed)
        end
        if Settings.auto_battle then task.spawn(AutoBattle) end
        if _kpEnv.KP_SmartJoin.ControlsGameEnd() then
            task.spawn(SmartJoinEndRouter)
        elseif Settings.auto_replay then
            task.spawn(AutoReplay)
        end
        if Settings.auto_next_story then task.spawn(AutoNextStory) end
        if Settings.macro_record then task.spawn(StartMacroRecord) end
        if Settings.macro_playback then task.spawn(StartMacroPlayback) end
        if Settings.auto_upgrade then task.spawn(AutoUpgrade) end
        if Settings.auto_upgrade_sell then task.spawn(AutoSell) end
        task.spawn(OnGameEnd)
    else
        if Settings.auto_evolve_exp then task.spawn(AutoEvolveEXP) end
        task.wait(1)
        if Settings.auto_join_game then task.spawn(AutoJoinGame) end
        if Settings.auto_join_tower then task.spawn(AutoTower) end
        -- webhookbanner removed
    end

    if Settings.auto_skip_gui then task.spawn(AutoSkipGUI) end
    if Settings.fps_boost then task.spawn(FpsBoost) end
    if tonumber(Settings.fps_limit) then task.defer(ApplyFPSLimit, Settings.fps_limit, false) end
    if Settings.delete_enemies then task.spawn(DeleteEnemies) end
    if Settings.delete_map and is_lobby() then
        Settings.delete_map = false
        Save()
    end
    if Settings.delete_map and not is_lobby() then task.spawn(DeleteMap) end
    if Settings.anonymous_mode then task.spawn(AnonMode) end
end

if get_world() == -2 and Settings.auto_join_game then task.spawn(AutoJoinGame) end

-- Tasks that run regardless if its in lobby or in game.
-- Anti-AFK: unconditional, no toggle
local _VirtualUser = game:GetService("VirtualUser")
TrackConnection(game.Players.LocalPlayer.Idled:Connect(function()
    _VirtualUser:CaptureController()
    _VirtualUser:ClickButton2(Vector2.new())
end))

print("[KarmaPanda:X] Functions Loaded: " .. os.clock() - benchmark_time)
benchmark_time = os.clock()




function KP.BuildUI()
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local darkOverlay

local Colors = {
    bg = Color3.fromRGB(14, 14, 14),
    bg2 = Color3.fromRGB(19, 19, 19),
    card = Color3.fromRGB(26, 26, 26),
    cardHover = Color3.fromRGB(31, 31, 31),
    input = Color3.fromRGB(21, 21, 21),
    border = Color3.fromRGB(42, 42, 42),
    borderLight = Color3.fromRGB(51, 51, 51),
    text = Color3.fromRGB(216, 216, 216),
    text2 = Color3.fromRGB(153, 153, 153),
    text3 = Color3.fromRGB(85, 85, 85),
    accent = Color3.fromRGB(180, 30, 30),
    accentLight = Color3.fromRGB(212, 42, 42),
    accentDark = Color3.fromRGB(122, 20, 20),
    toggleOff = Color3.fromRGB(68, 68, 68),
    toggleOffStroke = Color3.fromRGB(85, 85, 85),
    white = Color3.fromRGB(255, 255, 255),
    danger = Color3.fromRGB(255, 107, 107),
}

pcall(function()
    for _, g in pairs(game:GetService("CoreGui"):GetChildren()) do
        if g.Name == "KarmaPandaUI" then g:Destroy() end
    end
end)
pcall(function()
    for _, g in pairs(Player.PlayerGui:GetChildren()) do
        if g.Name == "KarmaPandaUI" then g:Destroy() end
    end
end)

local ScreenGui = Instance.new("ScreenGui")
KP.ui = ScreenGui
KP.uiRefresh = {}
ScreenGui.Name = "KarmaPandaUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
if not ScreenGui.Parent then ScreenGui.Parent = Player.PlayerGui end

_kpEnv.KP_Runtime.enemyOverlayFolder = Instance.new("Folder")
_kpEnv.KP_Runtime.enemyOverlayFolder.Name = "EnemyOverlay"
_kpEnv.KP_Runtime.enemyOverlayFolder.Parent = ScreenGui
_kpEnv.KP_Runtime.enemyOverlayRefs = {}

function KP_GetOverlayEnemies()
    local folder = workspace:FindFirstChild("Enemies")
    return folder and KP.BindEnemies().list or {}
end

function KP_GetOverlayValue(instance, name)
    local child = instance and instance:FindFirstChild(name)
    if child and child:IsA("ValueBase") then return child.Value end
    local humanoid = instance and instance:FindFirstChild("Humanoid")
    child = humanoid and humanoid:FindFirstChild(name)
    if child and child:IsA("ValueBase") then return child.Value end
    return nil
end

function KP_RemoveEnemyOverlay(enemy)
    local refs = _kpEnv.KP_Runtime.enemyOverlayRefs
    local overlay = refs and refs[enemy]
    if overlay then pcall(function() overlay:Destroy() end); refs[enemy] = nil end
end

function KP_RenderEnemyOverlay()
    local refs = _kpEnv.KP_Runtime.enemyOverlayRefs
    if not refs then return end
    local live = {}
    for _, enemy in ipairs(KP_GetOverlayEnemies()) do live[enemy] = true end
    for enemy, _ in pairs(refs) do
        if not live[enemy] or not Settings.show_enemy_overlay then KP_RemoveEnemyOverlay(enemy) end
    end
    if not Settings.show_enemy_overlay then return end

    for _, enemy in ipairs(KP_GetOverlayEnemies()) do
        local adornee = enemy:FindFirstChild("Head") or enemy:FindFirstChild("HumanoidRootPart")
        if adornee then
            local overlay = refs[enemy]
            local text
            if not overlay or not overlay.Parent then
                overlay = Instance.new("BillboardGui")
                overlay.Name = "EnemyBB"
                overlay.Size = UDim2.new(0, 90, 0, 28)
                overlay.StudsOffset = Vector3.new(0, 3, 0)
                overlay.AlwaysOnTop = true
                overlay.MaxDistance = 450
                overlay.Parent = _kpEnv.KP_Runtime.enemyOverlayFolder

                text = Instance.new("TextLabel")
                text.Name = "Info"
                text.Size = UDim2.new(1, 0, 1, 0)
                text.BackgroundTransparency = 1
                text.Font = Enum.Font.GothamBlack
                text.TextSize = 12
                text.TextStrokeTransparency = 0.25
                text.TextStrokeColor3 = Color3.new(0, 0, 0)
                text.TextColor3 = Color3.fromRGB(255, 78, 78)
                text.TextWrapped = true
                text.Parent = overlay
                refs[enemy] = overlay
            else
                text = overlay:FindFirstChild("Info")
            end

            overlay.Adornee = adornee
            if text then
                local hp = tonumber(KP_GetOverlayValue(enemy, "HP") or 0) or 0
                local speed = tonumber(KP_GetOverlayValue(enemy, "SpeedValue") or 0) or 0
                text.Text = string.format("Hp : %s\nSpeed : %s", math.floor(hp + 0.5), math.floor(speed * 100) / 100)
            end
        end
    end
end

local NotifyFrame = Instance.new("Frame")
NotifyFrame.Name = "Notify"
NotifyFrame.Size = UDim2.new(0, 200, 0, 50)
NotifyFrame.Position = UDim2.new(1, 10, 0, 20)
NotifyFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
NotifyFrame.BackgroundTransparency = 0.05
NotifyFrame.BorderSizePixel = 0
NotifyFrame.Visible = false
NotifyFrame.ZIndex = 100
NotifyFrame.Parent = ScreenGui
Instance.new("UICorner", NotifyFrame).CornerRadius = UDim.new(0, 6)
do
local ns = Instance.new("UIStroke", NotifyFrame)
ns.Color = Colors.accentDark
ns.Thickness = 1
local na = Instance.new("Frame", NotifyFrame)
na.Size = UDim2.new(0, 3, 1, 0)
na.BackgroundColor3 = Colors.accent
na.BorderSizePixel = 0
na.ZIndex = 101
Instance.new("UICorner", na).CornerRadius = UDim.new(0, 6)
local NotifyTitle = Instance.new("TextLabel", NotifyFrame)
NotifyTitle.Font = Enum.Font.GothamBold
NotifyTitle.TextSize = 11
NotifyTitle.TextColor3 = Colors.accentLight
NotifyTitle.TextXAlignment = Enum.TextXAlignment.Left
NotifyTitle.BackgroundTransparency = 1
NotifyTitle.Position = UDim2.new(0, 12, 0, 7)
NotifyTitle.Size = UDim2.new(1, -20, 0, 14)
NotifyTitle.ZIndex = 101
local NotifyBody = Instance.new("TextLabel", NotifyFrame)
NotifyBody.Font = Enum.Font.Gotham
NotifyBody.TextSize = 10
NotifyBody.TextColor3 = Colors.text2
NotifyBody.TextXAlignment = Enum.TextXAlignment.Left
NotifyBody.TextWrapped = true
NotifyBody.BackgroundTransparency = 1
NotifyBody.Position = UDim2.new(0, 12, 0, 23)
NotifyBody.Size = UDim2.new(1, -20, 0, 22)
NotifyBody.ZIndex = 101

local notifyHideThread = nil
ShowNotify = function(title, body)
    NotifyTitle.Text = tostring(title)
    NotifyBody.Text = tostring(body)
    NotifyFrame.Visible = true
    NotifyFrame.Position = UDim2.new(1, 10, 0, 20)
    TweenService:Create(NotifyFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(1, -210, 0, 20)
    }):Play()
    if notifyHideThread then task.cancel(notifyHideThread) end
    KP.WithContext(nil, function()
    notifyHideThread = task.delay(2.5, function()
        local t = TweenService:Create(NotifyFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(1, 10, 0, 20)
        })
        t:Play()
        task.wait(0.2)
        NotifyFrame.Visible = false
    end)
    end)
end
end

local MainFrame = Instance.new("Frame")
MainFrame.Name = "Main"
MainFrame.Size = UDim2.new(0, 460, 0, 520)
MainFrame.Position = UDim2.new(0.5, -230, 0.5, -260)
MainFrame.BackgroundColor3 = Colors.bg
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Visible = true
MainFrame.ZIndex = 2
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
do
local ms = Instance.new("UIStroke", MainFrame)
ms.Color = Colors.border
ms.Thickness = 1
end

pcall(function()
    local cam = workspace.CurrentCamera
    if not cam then cam = workspace:WaitForChild("Camera", 5) end
    if not cam then return end
    local vp = cam.ViewportSize
    if vp.X < 10 then task.wait(1); vp = cam.ViewportSize end
    local uiScale = Instance.new("UIScale")
    local scaleX = (vp.X - 20) / 460
    local scaleY = (vp.Y - 20) / 520
    local autoScale = math.min(scaleX, scaleY)
    autoScale = math.clamp(autoScale, 0.35, 1)
    local savedScale = Settings.ui_scale or 0.95
    if not Settings.ui_scale_safe_reset_once then
        savedScale = math.min(savedScale, autoScale)
        Settings.ui_scale = savedScale
        Settings.ui_scale_initialized = true
        Settings.ui_scale_safe_reset_once = true
        Save()
    end
    local finalScale = math.min(Settings.ui_scale or savedScale, autoScale)
    uiScale.Scale = finalScale
    uiScale.Parent = MainFrame
    if autoScale < 0.85 then
        MainFrame.Position = UDim2.new(0.5, -230, 0, 10)
    end
    print("[KarmaPanda:X] Viewport:", vp.X, "x", vp.Y, "Scale:", finalScale)
end)

local uiVisible = true

local function SpawnLeafIn(container, z)
    local leaf = Instance.new("TextLabel")
    leaf.Text = "\xF0\x9F\x8D\x81"
    leaf.Font = Enum.Font.SourceSans
    leaf.TextSize = math.random(14, 24)
    leaf.TextColor3 = Color3.fromRGB(math.random(140, 212), math.random(20, 42), math.random(20, 42))
    leaf.BackgroundTransparency = 1
    leaf.Size = UDim2.new(0, 20, 0, 20)
    leaf.Position = UDim2.new(math.random(5, 90) / 100, 0, -0.05, 0)
    leaf.Rotation = math.random(0, 360)
    leaf.TextTransparency = 0
    leaf.ZIndex = z or 2
    leaf.Parent = container
    local dur = math.random(60, 120) / 10
    TweenService:Create(leaf, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
        Position = UDim2.new(leaf.Position.X.Scale + (math.random(-15, 15) / 100), 0, 1.1, 0),
        Rotation = leaf.Rotation + math.random(360, 720),
        TextTransparency = 0.4,
    }):Play()
    task.delay(dur, function() if leaf and leaf.Parent then leaf:Destroy() end end)
end

MainFrame.Visible = not Settings.close_on_injection
local LeafContainer = Instance.new("Frame", MainFrame)
LeafContainer.Name = "LeafContainer"
LeafContainer.Size = UDim2.new(1, 0, 1, 0)
LeafContainer.BackgroundTransparency = 1
LeafContainer.ClipsDescendants = true
LeafContainer.ZIndex = 2

task.spawn(function()
    while ScriptAlive() and ScreenGui.Parent do
        if MainFrame.Visible and ScreenGui.Enabled then SpawnLeafIn(LeafContainer, 2) end
        task.wait(math.random(15, 30) / 10)
    end
end)

local Header = Instance.new("Frame", MainFrame)
Header.Size = UDim2.new(1, 0, 0, 50)
Header.BackgroundColor3 = Colors.bg2
Header.BackgroundTransparency = 0.2
Header.BorderSizePixel = 0
Header.ZIndex = 5
do
local hBorder = Instance.new("Frame", Header)
hBorder.Size = UDim2.new(1, 0, 0, 1)
hBorder.Position = UDim2.new(0, 0, 1, -1)
hBorder.BackgroundColor3 = Colors.border
hBorder.BorderSizePixel = 0
hBorder.ZIndex = 5
end

do
local titleLbl = Instance.new("TextLabel", Header)
titleLbl.Text = "KarmaPanda:X"
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 18
titleLbl.TextColor3 = Colors.white
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.BackgroundTransparency = 1
titleLbl.Position = UDim2.new(0, 16, 0, 13)
titleLbl.Size = UDim2.new(0.62, 0, 0, 24)
titleLbl.ZIndex = 6

local verLbl = Instance.new("TextLabel", Header)
verLbl.Text = "script by blob | v" .. version
verLbl.Font = Enum.Font.Gotham
verLbl.TextSize = 10
verLbl.TextColor3 = Colors.accentLight
verLbl.TextXAlignment = Enum.TextXAlignment.Right
verLbl.BackgroundTransparency = 1
verLbl.Position = UDim2.new(0.62, 0, 0, 17)
verLbl.Size = UDim2.new(0.38, -16, 0, 16)
verLbl.ZIndex = 6
end

local TabBar = Instance.new("Frame", MainFrame)
TabBar.Size = UDim2.new(1, 0, 0, 30)
TabBar.Position = UDim2.new(0, 0, 0, 50)
TabBar.BackgroundColor3 = Colors.bg2
TabBar.BackgroundTransparency = 0.2
TabBar.BorderSizePixel = 0
TabBar.ClipsDescendants = true
TabBar.ZIndex = 5
do
local tbBorder = Instance.new("Frame", TabBar)
tbBorder.Size = UDim2.new(1, 0, 0, 1)
tbBorder.Position = UDim2.new(0, 0, 1, -1)
tbBorder.BackgroundColor3 = Colors.border
tbBorder.BorderSizePixel = 0
tbBorder.ZIndex = 6
end

local ContentHolder = Instance.new("Frame", MainFrame)
ContentHolder.Size = UDim2.new(1, 0, 1, -80)
ContentHolder.Position = UDim2.new(0, 0, 0, 80)
ContentHolder.BackgroundTransparency = 1
ContentHolder.ZIndex = 3

local _activeTooltip = nil
local _activeTooltipText = nil
local TabPages = {}
local CurrentTab = nil
local _tabXOffset = 0
local TAB_COUNT = 6

local function CreateTab(name, order)
    local tabW = math.floor(460 / TAB_COUNT)
    local xPos = _tabXOffset
    _tabXOffset = _tabXOffset + tabW
    local btn = Instance.new("TextButton", TabBar)
    btn.Name = "Tab_" .. name
    btn.Text = name
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.TextColor3 = Colors.text2
    btn.BackgroundTransparency = 1
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Size = UDim2.new(0, tabW, 0, 29)
    btn.Position = UDim2.new(0, xPos, 0, 0)
    btn.ZIndex = 7
    local indicator = Instance.new("Frame", btn)
    indicator.Size = UDim2.new(1, 0, 0, 2)
    indicator.Position = UDim2.new(0, 0, 1, -2)
    indicator.BackgroundColor3 = Colors.accent
    indicator.BackgroundTransparency = 1
    indicator.BorderSizePixel = 0
    indicator.ZIndex = 8
    local page = Instance.new("ScrollingFrame", ContentHolder)
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundColor3 = Colors.bg
    page.BackgroundTransparency = 0.3
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = Colors.border
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.Visible = false
    page.ZIndex = 3
    local pp = Instance.new("UIPadding", page)
    pp.PaddingTop = UDim.new(0, 12)
    pp.PaddingBottom = UDim.new(0, 12)
    pp.PaddingLeft = UDim.new(0, 14)
    pp.PaddingRight = UDim.new(0, 14)
    Instance.new("UIListLayout", page).Padding = UDim.new(0, 5)
    page:FindFirstChildOfClass("UIListLayout").SortOrder = Enum.SortOrder.LayoutOrder
    TabPages[name] = {btn = btn, page = page, indicator = indicator, loaded = false, loader = nil}
    btn.MouseButton1Click:Connect(function()
        if CurrentTab == name and TabPages[name].loaded then return end
        for _, d in pairs(TabPages) do
            d.page.Visible = false
            d.btn.TextColor3 = Colors.text2
            d.indicator.BackgroundTransparency = 1
        end
        page.Visible = true
        btn.TextColor3 = Colors.white
        indicator.BackgroundTransparency = 0
        CurrentTab = name
        page.CanvasPosition = Vector2.new(0, 0)
        if _activeTooltip and _activeTooltip.Parent then _activeTooltip:Destroy(); _activeTooltip = nil; _activeTooltipText = nil end
        if not TabPages[name].loaded and TabPages[name].loader then
            TabPages[name].loaded = true
            TabPages[name].loader()
            task.defer(function()
                pcall(function()
                    if KP_ApplyCollapsedSections then KP_ApplyCollapsedSections(page) end
                end)
            end)
        end
    end)
    return page
end

local elementOrder = 0
local function nextOrder() elementOrder = elementOrder + 1 return elementOrder end

local SectionVisibility = {}
pcall(function()
    if not isfile("KarmaPanda/ASTD/Settings/section_visibility.json") and isfile("KarmaPanda/ASTD/section_visibility.json") then
        writefile("KarmaPanda/ASTD/Settings/section_visibility.json", readfile("KarmaPanda/ASTD/section_visibility.json"))
        pcall(function() delfile("KarmaPanda/ASTD/section_visibility.json") end)
    end
    if isfile("KarmaPanda/ASTD/Settings/section_visibility.json") then
        SectionVisibility = game:GetService("HttpService"):JSONDecode(readfile("KarmaPanda/ASTD/Settings/section_visibility.json"))
    end
end)
local function SaveSectionVisibility()
    pcall(function() writefile("KarmaPanda/ASTD/Settings/section_visibility.json", game:GetService("HttpService"):JSONEncode(SectionVisibility)) end)
end

local DefaultCollapsedSections = {
    ["Import / export"] = true,
    ["Recording options"] = true,
    ["Playback options"] = true,
    ["Action queue"] = true,
    ["Macro options"] = true,
    ["Offset settings"] = true,
    ["Add New Ability Unit"] = true,
    ["Automation"] = true
}
if SectionVisibility.__macroDefaultsCollapsedV1 ~= true then
    for title in pairs(DefaultCollapsedSections) do
        SectionVisibility[title] = false
    end
    SectionVisibility.__macroDefaultsCollapsedV1 = true
    SectionVisibility.__pendingDefaultsSave = true
else
    for title in pairs(DefaultCollapsedSections) do
        if SectionVisibility[title] == nil then
            SectionVisibility[title] = false
            SectionVisibility.__pendingDefaultsSave = true
        end
    end
end
if SectionVisibility.__pendingDefaultsSave then
    SectionVisibility.__pendingDefaultsSave = nil
    SaveSectionVisibility()
end
if SectionVisibility.__advancedDefaultsCollapsedV2 ~= true then
    SectionVisibility["Add New Ability Unit"] = false
    SectionVisibility.__advancedDefaultsCollapsedV2 = true
    SaveSectionVisibility()
end

local function CreateSection(parent, title)
    local sectionOrder = nextOrder()
    local isCollapsed = title ~= "Smart Ability" and SectionVisibility[title] == false
    local hf = Instance.new("Frame", parent)
    hf.Name = "SectionHeader_" .. title
    hf.Size = UDim2.new(1, 0, 0, 18)
    hf.BackgroundTransparency = 1
    hf.LayoutOrder = sectionOrder
    hf.ZIndex = 4
    local lbl = Instance.new("TextLabel", hf)
    lbl.Text = title == "Smart Ability" and "SMART  ABILITY" or string.upper(title)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 10
    lbl.TextColor3 = Colors.accentLight
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 1, 0, 4)
    lbl.Size = UDim2.new(1, -24, 0, 14)
    lbl.ZIndex = 5
    local arr = Instance.new("TextLabel", hf)
    arr.Text = title == "Smart Ability" and "" or (isCollapsed and ">" or "v")
    arr.Font = Enum.Font.GothamBold
    arr.TextSize = 10
    arr.TextColor3 = Colors.accentLight
    arr.TextXAlignment = Enum.TextXAlignment.Right
    arr.BackgroundTransparency = 1
    arr.Position = UDim2.new(1, -18, 0, 4)
    arr.Size = UDim2.new(0, 14, 0, 14)
    arr.ZIndex = 5
    local hitBtn = Instance.new("TextButton", hf)
    hitBtn.Text = ""
    hitBtn.Size = UDim2.new(1, 0, 1, 0)
    hitBtn.BackgroundTransparency = 1
    hitBtn.ZIndex = 6
    if title == "Smart Ability" then hitBtn.Visible=false;SectionVisibility[title]=true end
    local collapsed = isCollapsed
    hitBtn.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        arr.Text = collapsed and ">" or "v"
        SectionVisibility[title] = not collapsed
        SaveSectionVisibility()
        for _, child in pairs(parent:GetChildren()) do
            if child ~= hf and not child:IsA("UIListLayout") and not child:IsA("UIPadding") and child.LayoutOrder > sectionOrder then
                local nextSec = 999999
                for _, o in pairs(parent:GetChildren()) do
                    if o ~= hf and o.Name and o.Name:find("SectionHeader_") and o.LayoutOrder > sectionOrder then
                        nextSec = math.min(nextSec, o.LayoutOrder)
                    end
                end
                if child.LayoutOrder < nextSec then child.Visible = not collapsed end
            end
        end
    end)
    return sectionOrder
end

local function CreateHeader(parent, title, subtitle)
    local hdr = Instance.new("Frame", parent)
    hdr.Size = UDim2.new(1, 0, 0, 0)
    hdr.AutomaticSize = Enum.AutomaticSize.Y
    hdr.BackgroundColor3 = Color3.fromRGB(17, 11, 11)
    hdr.BackgroundTransparency = 0.3
    hdr.BorderSizePixel = 0
    hdr.LayoutOrder = nextOrder()
    hdr.ZIndex = 4
    Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 6)
    local hs = Instance.new("UIStroke", hdr)
    hs.Color = Color3.fromRGB(80, 20, 20)
    hs.Thickness = 1
    local accentBar = Instance.new("Frame", hdr)
    accentBar.Size = UDim2.new(0, 3, 1, 0)
    accentBar.BackgroundColor3 = Colors.accent
    accentBar.BorderSizePixel = 0
    accentBar.ZIndex = 5
    Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, 2)
    local ht = Instance.new("TextLabel", hdr)
    ht.Text = title
    ht.Font = Enum.Font.GothamBold
    ht.TextSize = 13
    ht.TextColor3 = Colors.white
    ht.TextXAlignment = Enum.TextXAlignment.Left
    ht.BackgroundTransparency = 1
    ht.Position = UDim2.new(0, 14, 0, 8)
    ht.Size = UDim2.new(1, -20, 0, 16)
    ht.ZIndex = 5
    if subtitle then
        local hst = Instance.new("TextLabel", hdr)
        hst.Text = subtitle
        hst.Font = Enum.Font.Gotham
        hst.TextSize = 10
        hst.TextColor3 = Colors.text3
        hst.TextXAlignment = Enum.TextXAlignment.Left
        hst.TextWrapped = true
        hst.BackgroundTransparency = 1
        hst.Position = UDim2.new(0, 14, 0, 26)
        hst.Size = UDim2.new(1, -20, 0, 0)
        hst.AutomaticSize = Enum.AutomaticSize.Y
        hst.ZIndex = 5
    end
    Instance.new("UIPadding", hdr).PaddingBottom = UDim.new(0, subtitle and 10 or 8)
    return hdr
end

local function CreateDivider(parent)
    local div = Instance.new("Frame", parent)
    div.Size = UDim2.new(1, -20, 0, 1)
    div.Position = UDim2.new(0, 10, 0, 0)
    div.BackgroundColor3 = Colors.border
    div.BackgroundTransparency = 0.5
    div.BorderSizePixel = 0
    div.LayoutOrder = nextOrder()
    div.ZIndex = 4
    local spacer = Instance.new("Frame", parent)
    spacer.Size = UDim2.new(1, 0, 0, 6)
    spacer.BackgroundTransparency = 1
    spacer.LayoutOrder = nextOrder()
    return div
end

local function DismissTooltip()
    if _activeTooltip and _activeTooltip.Parent then
        _activeTooltip:Destroy()
    end
    _activeTooltip = nil
    _activeTooltipText = nil
end

local function ShowTooltipAfter(parent, infoText)
    DismissTooltip()
    local tip = Instance.new("Frame", parent.Parent)
    tip.Size = UDim2.new(1, 0, 0, 0)
    tip.AutomaticSize = Enum.AutomaticSize.Y
    tip.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    tip.BorderSizePixel = 0
    tip.LayoutOrder = parent.LayoutOrder
    tip.ZIndex = 10
    Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 6)
    local ts = Instance.new("UIStroke", tip)
    ts.Color = Colors.accent
    ts.Thickness = 1
    local tl = Instance.new("TextLabel", tip)
    tl.Text = infoText
    tl.Font = Enum.Font.Gotham
    tl.TextSize = 10
    tl.TextColor3 = Colors.text2
    tl.TextXAlignment = Enum.TextXAlignment.Left
    tl.TextWrapped = true
    tl.BackgroundTransparency = 1
    tl.Size = UDim2.new(1, -16, 0, 0)
    tl.AutomaticSize = Enum.AutomaticSize.Y
    tl.Position = UDim2.new(0, 8, 0, 6)
    tl.ZIndex = 11
    Instance.new("UIPadding", tip).PaddingBottom = UDim.new(0, 8)
    _activeTooltip = tip
    _activeTooltipText = infoText
    task.delay(4, function()
        if _activeTooltipText == infoText then DismissTooltip() end
    end)
end

local function AddInfoIcon(parent, infoText, yPos)
    if not infoText then return end
    local labelObj = nil
    for _, child in pairs(parent:GetChildren()) do
        if child:IsA("TextButton") then
            for _, sub in pairs(child:GetChildren()) do
                if sub:IsA("TextLabel") and sub.Font == Enum.Font.GothamMedium then
                    labelObj = sub
                    break
                end
            end
        end
        if not labelObj and child:IsA("TextLabel") and child.Font == Enum.Font.GothamMedium then
            labelObj = child
        end
        if labelObj then break end
    end
    if labelObj then
        labelObj.RichText = true
        labelObj.Text = labelObj.Text .. ' <font color="#d42a2a">\xE2\x93\x98</font>'
    end
    local hitBtn = Instance.new("TextButton", parent)
    hitBtn.Text = ""
    hitBtn.BackgroundTransparency = 1
    hitBtn.Size = labelObj and labelObj.Size or UDim2.new(0.6, 0, 0, 16)
    hitBtn.Position = labelObj and labelObj.Position or UDim2.new(0, 10, 0, 3)
    hitBtn.ZIndex = 10
    hitBtn.MouseButton1Click:Connect(function()
        if _activeTooltipText == infoText then
            DismissTooltip()
            return
        end
        ShowTooltipAfter(parent, infoText)
    end)
end

function CreateCard(parent)
    local card = Instance.new("Frame", parent)
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = Colors.card
    card.BackgroundTransparency = 0.3
    card.BorderSizePixel = 0
    card.LayoutOrder = nextOrder()
    card.ZIndex = 4
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
    local s = Instance.new("UIStroke", card)
    s.Color = Colors.border
    s.Transparency = 0.2
    s.Thickness = 1
    return card
end

_kpEnv.KP_Runtime.UIRefs = {}
UIRefs = _kpEnv.KP_Runtime.UIRefs

local function CreateToggle(parent, label, sublabel, settingKey, defaultOn, callback, binding)
    local function read() if binding then return binding.get() end; return Settings[settingKey] end
    local function write(value) if binding then binding.set(value) else Settings[settingKey]=value end end
    local card = CreateCard(parent)
    card.Size = UDim2.new(1, 0, 0, sublabel and 38 or 30)
    card.AutomaticSize = Enum.AutomaticSize.None
    local btn = Instance.new("TextButton", card)
    btn.Text = ""
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.ZIndex = 5
    local l = Instance.new("TextLabel", btn)
    l.Text = label
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 12
    l.TextColor3 = Colors.text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.BackgroundTransparency = 1
    l.Position = UDim2.new(0, 10, 0, sublabel and 5 or 0)
    l.Size = UDim2.new(1, -54, 0, sublabel and 16 or 30)
    l.ZIndex = 6
    if sublabel then
        local sub = Instance.new("TextLabel", btn)
        sub.Text = sublabel
        sub.Font = Enum.Font.Gotham
        sub.TextSize = 9
        sub.TextColor3 = Colors.text3
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.BackgroundTransparency = 1
        sub.Position = UDim2.new(0, 10, 0, 21)
        sub.Size = UDim2.new(1, -54, 0, 12)
        sub.ZIndex = 6
    end
    local isOn = read()
    if isOn == nil then isOn = defaultOn or false end
    local tBg = Instance.new("Frame", btn)
    tBg.Size = UDim2.new(0, 32, 0, 16)
    tBg.Position = UDim2.new(1, -42, 0.5, -8)
    tBg.BackgroundColor3 = isOn and Colors.accent or Colors.toggleOff
    tBg.BorderSizePixel = 0
    tBg.ZIndex = 6
    Instance.new("UICorner", tBg).CornerRadius = UDim.new(1, 0)
    local tS = Instance.new("UIStroke", tBg)
    tS.Color = isOn and Colors.accentLight or Colors.toggleOffStroke
    tS.Thickness = 1
    local knob = Instance.new("Frame", tBg)
    knob.Size = UDim2.new(0, 10, 0, 10)
    knob.Position = isOn and UDim2.new(1, -13, 0.5, -5) or UDim2.new(0, 3, 0.5, -5)
    knob.BackgroundColor3 = Colors.white
    knob.BorderSizePixel = 0
    knob.ZIndex = 7
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local function SetVisual(on)
        local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
        TweenService:Create(tBg, ti, {BackgroundColor3 = on and Colors.accent or Colors.toggleOff}):Play()
        TweenService:Create(tS, ti, {Color = on and Colors.accentLight or Colors.toggleOffStroke}):Play()
        TweenService:Create(knob, ti, {Position = on and UDim2.new(1, -13, 0.5, -5) or UDim2.new(0, 3, 0.5, -5)}):Play()
    end

    btn.MouseButton1Click:Connect(function()
        isOn = not read()
        write(isOn)
        if not isOn and settingKey then KP.StopFeature(settingKey) end
        Save()
        SetVisual(isOn)
        ShowNotify(label, isOn and "Enabled." or "Disabled.")
        if callback then callback(isOn) end
    end)

    if settingKey then UIRefs[settingKey] = {
        setVisual = SetVisual, getValue = function() return read() == true end,
        refresh = function(v) isOn = v; SetVisual(v) end,
        setValue = function(v)
            isOn = v; write(v)
            if not v and settingKey then KP.StopFeature(settingKey) end
            Save(); SetVisual(v)
        end
    } end
    return card, SetVisual
end

function CreateButton(parent, label, isAccent, isDanger, callback)
    local b = Instance.new("TextButton", parent)
    b.Text = label
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 11
    b.TextColor3 = isDanger and Colors.danger or (isAccent and Colors.white or Colors.text)
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.BackgroundColor3 = isAccent and Colors.accentDark or Colors.card
    b.BackgroundTransparency = 0.3
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Size = UDim2.new(1, 0, 0, 28)
    b.LayoutOrder = nextOrder()
    b.ZIndex = 4
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local s = Instance.new("UIStroke", b)
    s.Color = isDanger and Color3.fromRGB(74, 26, 26) or (isAccent and Colors.accent or Colors.border)
    s.Transparency = 0.2
    s.Thickness = 1
    Instance.new("UIPadding", b).PaddingLeft = UDim.new(0, 10)
    b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.1), {BackgroundTransparency = 0.15}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.1), {BackgroundTransparency = 0.3}):Play() end)
    if callback then b.MouseButton1Click:Connect(callback) end
    return b
end

function CreateSlider(parent, label, min, max, step, settingKey, default, callback)
    local card = CreateCard(parent)
    card.Size = UDim2.new(1, 0, 0, 38)
    card.AutomaticSize = Enum.AutomaticSize.None
    local l = Instance.new("TextLabel", card)
    l.Text = label
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 12
    l.TextColor3 = Colors.text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.BackgroundTransparency = 1
    l.Position = UDim2.new(0, 10, 0, 3)
    l.Size = UDim2.new(0.7, 0, 0, 16)
    l.ZIndex = 5
    local currentVal = Settings[settingKey]
    if currentVal == nil then currentVal = default end
    local function fmtVal(v)
        if step >= 1 then return tostring(math.floor(v))
        elseif step >= 0.1 then return string.format("%.1f", v)
        else return string.format("%.2f", v) end
    end
    local vl = Instance.new("TextLabel", card)
    vl.Font = Enum.Font.GothamBold
    vl.TextSize = 11
    vl.TextColor3 = Colors.accentLight
    vl.TextXAlignment = Enum.TextXAlignment.Right
    vl.BackgroundTransparency = 1
    vl.Position = UDim2.new(0.7, 0, 0, 3)
    vl.Size = UDim2.new(0.3, -10, 0, 16)
    vl.ZIndex = 5
    vl.Text = fmtVal(currentVal)
    local track = Instance.new("Frame", card)
    track.Size = UDim2.new(1, -20, 0, 3)
    track.Position = UDim2.new(0, 10, 0, 25)
    track.BackgroundColor3 = Colors.border
    track.BorderSizePixel = 0
    track.ZIndex = 5
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
    local fill = Instance.new("Frame", track)
    fill.Size = UDim2.new((currentVal - min) / math.max(0.0001, max - min), 0, 1, 0)
    fill.BackgroundColor3 = Colors.accent
    fill.BorderSizePixel = 0
    fill.ZIndex = 6
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
    local kb = Instance.new("Frame", track)
    kb.Size = UDim2.new(0, 14, 0, 14)
    kb.Position = UDim2.new((currentVal - min) / math.max(0.0001, max - min), -7, 0.5, -7)
    kb.BackgroundColor3 = Colors.accent
    kb.BorderSizePixel = 0
    kb.ZIndex = 7
    Instance.new("UICorner", kb).CornerRadius = UDim.new(1, 0)
    local ks = Instance.new("UIStroke", kb)
    ks.Color = Colors.accentLight
    ks.Thickness = 2
    local dragging = false
    local ib = Instance.new("TextButton", card)
    ib.Text = ""
    ib.Size = UDim2.new(1, 0, 0, 20)
    ib.Position = UDim2.new(0, 0, 0, 18)
    ib.BackgroundTransparency = 1
    ib.ZIndex = 8
    ib.MouseButton1Down:Connect(function() dragging = true end)
    TrackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then dragging = false; if settingKey then Settings[settingKey] = currentVal; Save() end; if callback then callback(currentVal) end end
        end
    end))
    TrackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local pct = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            currentVal = math.clamp(math.floor((min + (max - min) * pct) / step + 0.5) * step, min, max)
            local norm = (currentVal - min) / math.max(0.0001, max - min)
            fill.Size = UDim2.new(norm, 0, 1, 0)
            kb.Position = UDim2.new(norm, -7, 0.5, -7)
            vl.Text = fmtVal(currentVal)
        end
    end))
    local function refresh(v, newMax)
        if newMax then max=math.max(min,newMax) end
            currentVal = math.clamp(tonumber(v) or default, min, max)
            local norm = (currentVal - min) / math.max(0.0001, max - min)
            fill.Size = UDim2.new(norm, 0, 1, 0)
            kb.Position = UDim2.new(norm, -7, 0.5, -7)
            vl.Text = fmtVal(currentVal)
    end
    if settingKey then UIRefs[settingKey] = {refresh=refresh} end
    return card, refresh
end

function CreateDropdown(parent, label, options, settingKey, default, callback, displaySettingKey, displayValue)
    local card = CreateCard(parent)
    local optH = 26
    local headerH = 30
    card.Size = UDim2.new(1, 0, 0, headerH)
    card.AutomaticSize = Enum.AutomaticSize.None
    card.ClipsDescendants = true
    local currentVal = Settings[settingKey]
    if currentVal == nil then currentVal = default end
    local l = Instance.new("TextLabel", card)
    l.Text = label
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 12
    l.TextColor3 = Colors.text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.BackgroundTransparency = 1
    l.Position = UDim2.new(0, 10, 0, 0)
    l.Size = UDim2.new(0.55, 0, 0, headerH)
    l.ZIndex = 5
    local sel = Instance.new("TextLabel", card)
    sel.Text = currentVal or ""
    sel.Font = Enum.Font.GothamMedium
    sel.TextSize = 10
    sel.TextColor3 = Colors.accentLight
    sel.TextXAlignment = Enum.TextXAlignment.Right
    sel.BackgroundTransparency = 1
    sel.Position = UDim2.new(0.45, 0, 0, 0)
    sel.Size = UDim2.new(0.55, -32, 0, headerH)
    sel.ZIndex = 5
    local arrow = Instance.new("TextLabel", card)
    arrow.Text = "v"
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 12
    arrow.TextColor3 = Colors.text3
    arrow.BackgroundTransparency = 1
    arrow.Position = UDim2.new(1, -22, 0, 0)
    arrow.Size = UDim2.new(0, 16, 0, headerH)
    arrow.ZIndex = 5
    local sep = Instance.new("Frame", card)
    sep.Size = UDim2.new(1, -16, 0, 1)
    sep.Position = UDim2.new(0, 8, 0, headerH)
    sep.BackgroundColor3 = Colors.border
    sep.BackgroundTransparency = 0.5
    sep.BorderSizePixel = 0
    sep.ZIndex = 5
    local expanded = false
    local openCallback
    local rawOptH = #options * (optH + 2)
    local maxOptH = math.min(rawOptH, 200)
    local searchH = #options > 15 and 24 or 0
    local totalH = headerH + 1 + 6 + searchH + maxOptH + 6
    local searchBox
    if #options > 15 then
        searchBox = Instance.new("TextBox", card)
        searchBox.PlaceholderText = "Search..."
        searchBox.PlaceholderColor3 = Colors.text3
        searchBox.Text = ""
        searchBox.Font = Enum.Font.Gotham
        searchBox.TextSize = 10
        searchBox.TextColor3 = Colors.text
        searchBox.TextXAlignment = Enum.TextXAlignment.Left
        searchBox.BackgroundColor3 = Colors.input
        searchBox.BackgroundTransparency = 0.1
        searchBox.BorderSizePixel = 0
        searchBox.ClearTextOnFocus = false
        searchBox.Position = UDim2.new(0, 6, 0, headerH + 4)
        searchBox.Size = UDim2.new(1, -12, 0, 20)
        searchBox.ZIndex = 7
        Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 4)
        Instance.new("UIPadding", searchBox).PaddingLeft = UDim.new(0, 6)
    end
    local oc = Instance.new("ScrollingFrame", card)
    oc.Size = UDim2.new(1, -12, 0, maxOptH)
    oc.Position = UDim2.new(0, 6, 0, headerH + 7 + searchH)
    oc.BackgroundTransparency = 1
    oc.BorderSizePixel = 0
    oc.ScrollBarThickness = rawOptH > maxOptH and 3 or 0
    oc.ScrollBarImageColor3 = Colors.border
    oc.CanvasSize = UDim2.new(0, 0, 0, rawOptH)
    oc.AutomaticCanvasSize = Enum.AutomaticSize.None
    oc.ScrollingEnabled = true
    oc.ZIndex = 6
    local ol = Instance.new("UIListLayout", oc)
    ol.Padding = UDim.new(0, 2)
    for i, opt in ipairs(options) do
        local isSel = (opt == currentVal)
        local ob = Instance.new("TextButton", oc)
        ob.Text = ""
        ob.BackgroundColor3 = isSel and Colors.accentDark or Colors.input
        ob.BackgroundTransparency = isSel and 0.4 or 0.2
        ob.BorderSizePixel = 0
        ob.AutoButtonColor = false
        ob.Size = UDim2.new(1, 0, 0, optH)
        ob.LayoutOrder = i
        ob.ZIndex = 7
        Instance.new("UICorner", ob).CornerRadius = UDim.new(0, 5)
        local os = Instance.new("UIStroke", ob)
        os.Color = isSel and Colors.accent or Colors.border
        os.Transparency = isSel and 0.4 or 0.7
        os.Thickness = 1
        local dot = Instance.new("Frame", ob)
        dot.Size = UDim2.new(0, 6, 0, 6)
        dot.Position = UDim2.new(0, 8, 0.5, -3)
        dot.BackgroundColor3 = isSel and Colors.accentLight or Colors.text3
        dot.BackgroundTransparency = isSel and 0 or 0.5
        dot.BorderSizePixel = 0
        dot.ZIndex = 8
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
        local ol2 = Instance.new("TextLabel", ob)
        ol2.Text = opt
        ol2.Font = Enum.Font.Gotham
        ol2.TextSize = 11
        ol2.TextColor3 = isSel and Colors.white or Colors.text2
        ol2.TextXAlignment = Enum.TextXAlignment.Left
        ol2.BackgroundTransparency = 1
        ol2.Position = UDim2.new(0, 22, 0, 0)
        ol2.Size = UDim2.new(1, -28, 1, 0)
        ol2.ZIndex = 8
        ob.MouseButton1Click:Connect(function()
            currentVal = opt
            sel.Text = opt
            if settingKey then Settings[settingKey] = opt; Save() end
            for _, c in pairs(oc:GetChildren()) do
                if c:IsA("TextButton") then
                    c.BackgroundColor3 = Colors.input
                    c.BackgroundTransparency = 0.2
                    local cs = c:FindFirstChildOfClass("UIStroke")
                    if cs then cs.Color = Colors.border; cs.Transparency = 0.7 end
                    for _, ch in pairs(c:GetChildren()) do
                        if ch:IsA("Frame") and ch.Size == UDim2.new(0, 6, 0, 6) then
                            ch.BackgroundColor3 = Colors.text3; ch.BackgroundTransparency = 0.5
                        end
                        if ch:IsA("TextLabel") then ch.TextColor3 = Colors.text2 end
                    end
                end
            end
            ob.BackgroundColor3 = Colors.accentDark
            ob.BackgroundTransparency = 0.4
            os.Color = Colors.accent
            os.Transparency = 0.4
            dot.BackgroundColor3 = Colors.accentLight
            dot.BackgroundTransparency = 0
            ol2.TextColor3 = Colors.white
            if callback then callback(opt) end
            expanded = false
            TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = UDim2.new(1, 0, 0, headerH)
            }):Play()
            TweenService:Create(arrow, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Rotation = 0}):Play()
        end)
    end
    if searchBox then
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            local query = searchBox.Text:lower()
            local visCount = 0
            for _, c in pairs(oc:GetChildren()) do
                if c:IsA("TextButton") then
                    local tl = c:FindFirstChildWhichIsA("TextLabel")
                    if tl then
                        local match = query == "" or tl.Text:lower():find(query, 1, true)
                        c.Visible = match and true or false
                        if c.Visible then visCount = visCount + 1 end
                    end
                end
            end
            local filteredH = math.min(visCount * (optH + 2), 200)
            oc.CanvasSize = UDim2.new(0, 0, 0, visCount * (optH + 2))
            oc.Size = UDim2.new(1, -12, 0, filteredH)
            totalH = headerH + 1 + 6 + searchH + filteredH + 6
            if expanded then
                card.Size = UDim2.new(1, 0, 0, totalH)
            end
        end)
    end
    local hb = Instance.new("TextButton", card)
    hb.Text = ""
    hb.Size = UDim2.new(1, 0, 0, headerH)
    hb.BackgroundTransparency = 1
    hb.ZIndex = 8
    hb.MouseButton1Click:Connect(function()
        if not expanded and openCallback then
            pcall(openCallback)
        end
        expanded = not expanded
        TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = expanded and UDim2.new(1, 0, 0, totalH) or UDim2.new(1, 0, 0, headerH)
        }):Play()
        TweenService:Create(arrow, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Rotation = expanded and 180 or 0}):Play()
    end)
    local function rebuildOptions(newOptions, newSelected)
        for _, child in pairs(oc:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        currentVal = newSelected or currentVal
        sel.Text = currentVal or ""
        local newRawH = #newOptions * (optH + 2)
        local newMaxH = math.min(newRawH, 200)
        totalH = headerH + 1 + 6 + searchH + newMaxH + 6
        oc.Size = UDim2.new(1, -12, 0, newMaxH)
        oc.CanvasSize = UDim2.new(0, 0, 0, newRawH)
        oc.ScrollBarThickness = newRawH > newMaxH and 3 or 0
        for i, opt in ipairs(newOptions) do
            local isSel = (opt == currentVal)
            local ob = Instance.new("TextButton", oc)
            ob.Text = ""
            ob.BackgroundColor3 = isSel and Colors.accentDark or Colors.input
            ob.BackgroundTransparency = isSel and 0.4 or 0.2
            ob.BorderSizePixel = 0
            ob.AutoButtonColor = false
            ob.Size = UDim2.new(1, 0, 0, optH)
            ob.LayoutOrder = i
            ob.ZIndex = 7
            Instance.new("UICorner", ob).CornerRadius = UDim.new(0, 5)
            local os2 = Instance.new("UIStroke", ob)
            os2.Color = isSel and Colors.accent or Colors.border
            os2.Transparency = isSel and 0.4 or 0.7
            os2.Thickness = 1
            local dot = Instance.new("Frame", ob)
            dot.Size = UDim2.new(0, 6, 0, 6)
            dot.Position = UDim2.new(0, 8, 0.5, -3)
            dot.BackgroundColor3 = isSel and Colors.accentLight or Colors.text3
            dot.BackgroundTransparency = isSel and 0 or 0.5
            dot.BorderSizePixel = 0
            dot.ZIndex = 8
            Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
            local ol2 = Instance.new("TextLabel", ob)
            ol2.Text = opt
            ol2.Font = Enum.Font.Gotham
            ol2.TextSize = 11
            ol2.TextColor3 = isSel and Colors.white or Colors.text2
            ol2.TextXAlignment = Enum.TextXAlignment.Left
            ol2.BackgroundTransparency = 1
            ol2.Position = UDim2.new(0, 22, 0, 0)
            ol2.Size = UDim2.new(1, -28, 1, 0)
            ol2.ZIndex = 8
            ob.MouseButton1Click:Connect(function()
                sel.Text = opt
                if settingKey then Settings[settingKey] = opt; Save() end
                currentVal = opt
                for _, c in pairs(oc:GetChildren()) do
                    if c:IsA("TextButton") then
                        c.BackgroundColor3 = Colors.input; c.BackgroundTransparency = 0.2
                        local cs = c:FindFirstChildOfClass("UIStroke")
                        if cs then cs.Color = Colors.border; cs.Transparency = 0.7 end
                        for _, ch in pairs(c:GetChildren()) do
                            if ch:IsA("Frame") and ch.Size == UDim2.new(0, 6, 0, 6) then ch.BackgroundColor3 = Colors.text3; ch.BackgroundTransparency = 0.5 end
                            if ch:IsA("TextLabel") then ch.TextColor3 = Colors.text2 end
                        end
                    end
                end
                ob.BackgroundColor3 = Colors.accentDark; ob.BackgroundTransparency = 0.4
                os2.Color = Colors.accent; os2.Transparency = 0.4
                dot.BackgroundColor3 = Colors.accentLight; dot.BackgroundTransparency = 0
                ol2.TextColor3 = Colors.white
                if callback then callback(opt) end
                expanded = false
                TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    Size = UDim2.new(1, 0, 0, headerH)
                }):Play()
                TweenService:Create(arrow, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Rotation = 0}):Play()
            end)
        end
    end
    local function setOpenCallback(callbackFn)
        openCallback = callbackFn
    end
    if settingKey then UIRefs[settingKey] = {refresh = function(v) currentVal = v; rebuildOptions(options, v) end}
    elseif displaySettingKey then UIRefs[displaySettingKey] = {refresh = function(v) rebuildOptions(options, displayValue(v)) end} end
    return card, sel, rebuildOptions, setOpenCallback
end

function CreateInput(parent, label, placeholder, settingKey, cb)
    local card = CreateCard(parent)
    card.Size = UDim2.new(1, 0, 0, 42)
    card.AutomaticSize = Enum.AutomaticSize.None
    local l = Instance.new("TextLabel", card)
    l.Text = label
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 12
    l.TextColor3 = Colors.text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.BackgroundTransparency = 1
    l.Position = UDim2.new(0, 10, 0, 2)
    l.Size = UDim2.new(1, -20, 0, 16)
    l.ZIndex = 5
    local box = Instance.new("TextBox", card)
    box.PlaceholderText = placeholder or ""
    box.PlaceholderColor3 = Colors.text3
    box.Text = settingKey and (Settings[settingKey] or "") or ""
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    box.TextColor3 = Colors.text
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.BackgroundColor3 = Colors.input
    box.BackgroundTransparency = 0.1
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.Position = UDim2.new(0, 8, 0, 20)
    box.Size = UDim2.new(1, -16, 0, 18)
    box.ZIndex = 5
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
    local bs = Instance.new("UIStroke", box)
    bs.Color = Colors.border
    bs.Thickness = 1
    Instance.new("UIPadding", box).PaddingLeft = UDim.new(0, 6)
    box.Focused:Connect(function() bs.Color = Colors.accent end)
    box.FocusLost:Connect(function(enterPressed)
        bs.Color = Colors.border
        if settingKey then Settings[settingKey] = box.Text; Save() end
        if cb then cb(box.Text, enterPressed) end
    end)
    if settingKey then UIRefs[settingKey] = {refresh = function(v) box.Text = tostring(v or "") end} end
    return card, box
end

function CreateParagraph(parent, title, content)
    local pg = Instance.new("Frame", parent)
    pg.Size = UDim2.new(1, 0, 0, 0)
    pg.AutomaticSize = Enum.AutomaticSize.Y
    pg.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
    pg.BackgroundTransparency = 0.1
    pg.BorderSizePixel = 0
    pg.LayoutOrder = nextOrder()
    pg.ZIndex = 4
    Instance.new("UICorner", pg).CornerRadius = UDim.new(0, 6)
    local ab = Instance.new("Frame", pg)
    ab.Size = UDim2.new(0, 2, 1, 0)
    ab.BackgroundColor3 = Colors.accent
    ab.BorderSizePixel = 0
    ab.ZIndex = 5
    if title and title ~= "" then
        local t = Instance.new("TextLabel", pg)
        t.Text = title
        t.Font = Enum.Font.GothamBold
        t.TextSize = 11
        t.TextColor3 = Colors.text
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.TextWrapped = true
        t.BackgroundTransparency = 1
        t.Position = UDim2.new(0, 12, 0, 6)
        t.Size = UDim2.new(1, -20, 0, 0)
        t.AutomaticSize = Enum.AutomaticSize.Y
        t.ZIndex = 5
    end
    local c = Instance.new("TextLabel", pg)
    c.Text = content
    c.Font = Enum.Font.Gotham
    c.TextSize = 10
    c.TextColor3 = Colors.text2
    c.TextXAlignment = Enum.TextXAlignment.Left
    c.TextWrapped = true
    c.BackgroundTransparency = 1
    c.Position = UDim2.new(0, 12, 0, (title and title ~= "") and 20 or 6)
    c.Size = UDim2.new(1, -20, 0, 0)
    c.AutomaticSize = Enum.AutomaticSize.Y
    c.ZIndex = 5
    Instance.new("UIPadding", pg).PaddingBottom = UDim.new(0, 8)
    return pg, c
end

function CreateStatusBox(parent, text)
    local box = Instance.new("TextLabel", parent)
    box.Text = text
    box.Font = Enum.Font.Code
    box.TextSize = 10
    box.TextColor3 = Colors.text2
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextWrapped = true
    box.RichText = true
    box.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
    box.BackgroundTransparency = 0.1
    box.BorderSizePixel = 0
    box.Size = UDim2.new(1, 0, 0, 0)
    box.AutomaticSize = Enum.AutomaticSize.Y
    box.LayoutOrder = nextOrder()
    box.ZIndex = 4
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    local s = Instance.new("UIStroke", box)
    s.Color = Colors.border
    s.Transparency = 0.2
    s.Thickness = 1
    local p = Instance.new("UIPadding", box)
    p.PaddingTop = UDim.new(0, 7)
    p.PaddingBottom = UDim.new(0, 7)
    p.PaddingLeft = UDim.new(0, 10)
    p.PaddingRight = UDim.new(0, 10)
    return box
end

function CreateButtonRow(parent, labels, callbacks)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, 0, 0, 28)
    row.BackgroundTransparency = 1
    row.LayoutOrder = nextOrder()
    row.ZIndex = 4
    local layout = Instance.new("UIListLayout", row)
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 4)
    for i, l in ipairs(labels) do
        local b = Instance.new("TextButton", row)
        b.Text = l
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 11
        b.TextColor3 = Colors.text
        b.BackgroundColor3 = Colors.card
        b.BackgroundTransparency = 0.3
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.Size = UDim2.new(1 / #labels, -(4 * (#labels - 1)) / #labels, 1, 0)
        b.LayoutOrder = i
        b.ZIndex = 5
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        local s = Instance.new("UIStroke", b)
        s.Color = Colors.border
        s.Transparency = 0.2
        s.Thickness = 1
        if callbacks and callbacks[i] then b.MouseButton1Click:Connect(callbacks[i]) end
    end
end


CreateTab("Main", 1)
CreateTab("Macro", 2)
CreateTab("Lobby", 3)
CreateTab("Webhooks", 4)
CreateTab("Advanced", 5)
CreateTab("Settings", 6)

TabPages["Main"].loader = function()
local mainPage = TabPages["Main"].page
elementOrder = 0
CreateButton(mainPage, "Discord Invite", true, false, function()
    pcall(function() setclipboard("https://discord.gg/UDrvUguuNU") end)
    ShowNotify("Discord", "Invite link copied.")
end)
CreateSection(mainPage, "Gameplay Scripts")
CreateToggle(mainPage, "Auto Ability", nil, "auto_buff", true, function(v) if not is_lobby() and v then task.spawn(AutoBuff) end end)
CreateToggle(mainPage, "Auto Battle", nil, "auto_battle", false, function(v) if not is_lobby() and v then task.spawn(AutoBattle) end end)
CreateToggle(mainPage, "Auto Sell", nil, "auto_upgrade_sell", false, function(v) if not is_lobby() and v then task.spawn(AutoSell) end end)
CreateToggle(mainPage, "Auto Upgrade", nil, "auto_upgrade", false, function(v) if not is_lobby() and v then task.spawn(AutoUpgrade) end end)
CreateSlider(mainPage, "Upgrade Level", 1, 23, 1, "auto_upgrade_level", Settings.auto_upgrade_level or 10)

;(function()
local loadoutUnits = get_loadout_units()
local upgradeCard, ugOC, ugSel, ugArrow, ugExpanded, totalUgH

local function getTargetDisplay()
    local t = Settings.auto_upgrade_targets or {}
    if #t == 0 then return "None"
    elseif #t > 3 then return #t .. " selected"
    else return table.concat(t, ", ") end
end

local function rebuildUpgradeTargets(units)
    if ugOC then
        for _, child in pairs(ugOC:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
    end
    local cleaned = {}
    local currentTargets = Settings.auto_upgrade_targets or {}
    for _, name in ipairs(currentTargets) do
        if table.find(units, name) then table.insert(cleaned, name) end
    end
    if #cleaned ~= #currentTargets then
        Settings.auto_upgrade_targets = cleaned
        Save()
    end
    if ugOC then
        ugOC.Size = UDim2.new(1, -12, 0, #units * 28)
        totalUgH = 30 + 1 + 6 + (#units * 28) + 6
        for i, uName in ipairs(units) do
            local isSel = table.find(cleaned, uName) ~= nil
            local ob = Instance.new("TextButton", ugOC)
            ob.Text = ""
            ob.BackgroundColor3 = isSel and Colors.accentDark or Colors.input
            ob.BackgroundTransparency = isSel and 0.4 or 0.2
            ob.BorderSizePixel = 0
            ob.AutoButtonColor = false
            ob.Size = UDim2.new(1, 0, 0, 26)
            ob.LayoutOrder = i
            ob.ZIndex = 7
            Instance.new("UICorner", ob).CornerRadius = UDim.new(0, 5)
            local os2 = Instance.new("UIStroke", ob)
            os2.Color = isSel and Colors.accent or Colors.border
            os2.Transparency = isSel and 0.4 or 0.7
            os2.Thickness = 1
            local dot = Instance.new("Frame", ob)
            dot.Size = UDim2.new(0, 6, 0, 6)
            dot.Position = UDim2.new(0, 8, 0.5, -3)
            dot.BackgroundColor3 = isSel and Colors.accentLight or Colors.text3
            dot.BackgroundTransparency = isSel and 0 or 0.5
            dot.BorderSizePixel = 0
            dot.ZIndex = 8
            Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
            local ol2 = Instance.new("TextLabel", ob)
            ol2.Text = uName
            ol2.Font = Enum.Font.Gotham
            ol2.TextSize = 11
            ol2.TextColor3 = isSel and Colors.white or Colors.text2
            ol2.TextXAlignment = Enum.TextXAlignment.Left
            ol2.BackgroundTransparency = 1
            ol2.Position = UDim2.new(0, 22, 0, 0)
            ol2.Size = UDim2.new(1, -28, 1, 0)
            ol2.ZIndex = 8
            ob.MouseButton1Click:Connect(function()
                if not Settings.auto_upgrade_targets then Settings.auto_upgrade_targets = {} end
                local t = Settings.auto_upgrade_targets
                local idx = table.find(t, uName)
                if idx then
                    table.remove(t, idx)
                    ob.BackgroundColor3 = Colors.input; ob.BackgroundTransparency = 0.2
                    os2.Color = Colors.border; os2.Transparency = 0.7
                    dot.BackgroundColor3 = Colors.text3; dot.BackgroundTransparency = 0.5
                    ol2.TextColor3 = Colors.text2
                else
                    table.insert(t, uName)
                    ob.BackgroundColor3 = Colors.accentDark; ob.BackgroundTransparency = 0.4
                    os2.Color = Colors.accent; os2.Transparency = 0.4
                    dot.BackgroundColor3 = Colors.accentLight; dot.BackgroundTransparency = 0
                    ol2.TextColor3 = Colors.white
                end
                Save()
                ugSel.Text = getTargetDisplay()
            end)
        end
    end
    if ugSel then ugSel.Text = getTargetDisplay() end
end

if #loadoutUnits > 0 then
    local currentTargets = Settings.auto_upgrade_targets or {}
    if #currentTargets == 0 then
        for _, name in ipairs(loadoutUnits) do
            table.insert(currentTargets, name)
        end
        Settings.auto_upgrade_targets = currentTargets
        Save()
    end
    local cleaned = {}
    for _, name in ipairs(currentTargets) do
        if table.find(loadoutUnits, name) then
            table.insert(cleaned, name)
        end
    end
    if #cleaned ~= #currentTargets then
        Settings.auto_upgrade_targets = cleaned
        Save()
    end
    upgradeCard = CreateCard(mainPage)
    upgradeCard.Size = UDim2.new(1, 0, 0, 30)
    upgradeCard.AutomaticSize = Enum.AutomaticSize.None
    upgradeCard.ClipsDescendants = true

    local ugLbl = Instance.new("TextLabel", upgradeCard)
    ugLbl.Text = "Upgrade Targets"
    ugLbl.Font = Enum.Font.GothamMedium
    ugLbl.TextSize = 12
    ugLbl.TextColor3 = Colors.text
    ugLbl.TextXAlignment = Enum.TextXAlignment.Left
    ugLbl.BackgroundTransparency = 1
    ugLbl.Position = UDim2.new(0, 10, 0, 0)
    ugLbl.Size = UDim2.new(0.5, 0, 0, 30)
    ugLbl.ZIndex = 5

    ugSel = Instance.new("TextLabel", upgradeCard)
    ugSel.Text = getTargetDisplay()
    ugSel.Font = Enum.Font.GothamMedium
    ugSel.TextSize = 10
    ugSel.TextColor3 = Colors.accentLight
    ugSel.TextXAlignment = Enum.TextXAlignment.Right
    ugSel.BackgroundTransparency = 1
    ugSel.Position = UDim2.new(0.5, 0, 0, 0)
    ugSel.Size = UDim2.new(0.5, -32, 0, 30)
    ugSel.ZIndex = 5

    ugArrow = Instance.new("TextLabel", upgradeCard)
    ugArrow.Text = "v"
    ugArrow.Font = Enum.Font.GothamBold
    ugArrow.TextSize = 12
    ugArrow.TextColor3 = Colors.text3
    ugArrow.BackgroundTransparency = 1
    ugArrow.Position = UDim2.new(1, -22, 0, 0)
    ugArrow.Size = UDim2.new(0, 16, 0, 30)
    ugArrow.ZIndex = 5

    local ugSep = Instance.new("Frame", upgradeCard)
    ugSep.Size = UDim2.new(1, -16, 0, 1)
    ugSep.Position = UDim2.new(0, 8, 0, 30)
    ugSep.BackgroundColor3 = Colors.border
    ugSep.BackgroundTransparency = 0.5
    ugSep.BorderSizePixel = 0
    ugSep.ZIndex = 5

    ugOC = Instance.new("Frame", upgradeCard)
    ugOC.Size = UDim2.new(1, -12, 0, #loadoutUnits * 28)
    ugOC.Position = UDim2.new(0, 6, 0, 37)
    ugOC.BackgroundTransparency = 1
    ugOC.ZIndex = 6
    Instance.new("UIListLayout", ugOC).Padding = UDim.new(0, 2)

    totalUgH = 30 + 1 + 6 + (#loadoutUnits * 28) + 6

    rebuildUpgradeTargets(loadoutUnits)

    ugExpanded = false
    local ugHitBtn = Instance.new("TextButton", upgradeCard)
    ugHitBtn.Text = ""
    ugHitBtn.Size = UDim2.new(1, 0, 0, 30)
    ugHitBtn.BackgroundTransparency = 1
    ugHitBtn.ZIndex = 8
    ugHitBtn.MouseButton1Click:Connect(function()
        ugExpanded = not ugExpanded
        TweenService:Create(upgradeCard, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = ugExpanded and UDim2.new(1, 0, 0, totalUgH) or UDim2.new(1, 0, 0, 30)
        }):Play()
        TweenService:Create(ugArrow, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Rotation = ugExpanded and 180 or 0}):Play()
    end)

    task.spawn(function()
        local lastUnits = table.concat(loadoutUnits, ",")
        while ScriptAlive() and ScreenGui.Parent and upgradeCard.Parent do
            task.wait(3)
            if not ScriptAlive() or not ScreenGui.Parent or not upgradeCard.Parent then break end
            local newUnits = get_loadout_units()
            local newKey = table.concat(newUnits, ",")
            if newKey ~= lastUnits and #newUnits > 0 then
                lastUnits = newKey
                loadoutUnits = newUnits
                rebuildUpgradeTargets(newUnits)
                if ugExpanded then
                    upgradeCard.Size = UDim2.new(1, 0, 0, totalUgH)
                end
            end
        end
    end)
end
end)()

CreateSection(mainPage, "GUI Scripts")
CreateToggle(mainPage, "Auto Vote Extreme", nil, "auto_vote_extreme", false, function(v) if not is_lobby() and v then task.spawn(AutoVoteExtreme) end end)
CreateToggle(mainPage, "Auto Skip Wave", nil, "auto_skip_wave_spam", false, function(v) if not is_lobby() and v then task.spawn(AutoSkipWaveSpam) end end)
CreateToggle(mainPage, "Auto 2x Speed", nil, "auto_2x", false, function(v)
    if v then
        Settings.auto_3x = false; Save()
        if UIRefs["auto_3x"] then UIRefs["auto_3x"].setValue(false) end
    end
    if not is_lobby() then task.spawn(AutoChangeSpeed) end
end)
CreateToggle(mainPage, "Auto 3x Speed", nil, "auto_3x", false, function(v)
    if v then
        Settings.auto_2x = false; Save()
        if UIRefs["auto_2x"] then UIRefs["auto_2x"].setValue(false) end
    end
    if not is_lobby() then task.spawn(AutoChangeSpeed) end
end)

CreateSection(mainPage, "Game End Scripts")
CreateToggle(mainPage, "Auto Replay", nil, "auto_replay", false, function(v)
    if not is_lobby() and v and not _kpEnv.KP_SmartJoin.ControlsGameEnd() then
        task.spawn(AutoReplay)
    end
end)
CreateToggle(mainPage, "Auto Next Story", nil, "auto_next_story", false, function(v) if not is_lobby() and v then task.spawn(AutoNextStory) end end)

end
TabPages["Macro"].loader = function()
local macroPage = TabPages["Macro"].page
elementOrder = 0
CreateSection(macroPage, "Macros")
local profileDropdown, profileSel, rebuildProfileDropdown, setProfileDropdownOpen = CreateDropdown(macroPage, "Selected profile", MacroProfileList, "macro_profile", Settings.macro_profile, function(opt)
    FocusMacroProfile(opt)
    RefreshMacroLeaderDropdown()
end)
setProfileDropdownOpen(function()
    RefreshMacroProfileList()
    if not table.find(MacroProfileList, Settings.macro_profile) then
        Settings.macro_profile = MacroProfileList[1] or "Default Profile"
    end
    FocusMacroProfile(Settings.macro_profile)
    Save()
    rebuildProfileDropdown(MacroProfileList, Settings.macro_profile)
    RefreshMacroLeaderDropdown()
end)
local macroInfoPg, macroInfoLbl = CreateParagraph(macroPage, "Profile info", "Loading...")
task.spawn(function()
    while ScriptAlive() and macroInfoLbl and macroInfoLbl.Parent do
        pcall(function()
            if not MainFrame.Visible or not macroPage.Visible then return end
            if Macros[Settings.macro_profile] and Macros[Settings.macro_profile]["Macro"] then
                local profile = Macros[Settings.macro_profile]
                local leader = GetMacroProfileLeaderUnit(profile)
                if leader == "" then leader = "None" end
                macroInfoLbl.Text = "Steps: " .. #profile["Macro"] .. " | Leader: " .. leader .. " | Units: " .. table.concat(get_keys(profile["Units"] or {}), ", ")
            end
        end)
        task.wait(1)
    end
end)



CreateSection(macroPage, "Controls")
CreateToggle(macroPage, "Record macro", "Keybind: R", "macro_record", false, function(v)
    KP.SetMacroRecording(v)
end)
CreateToggle(macroPage, "Playback macro", "Keybind: P", "macro_playback", false, function(v)
    KP.SetMacroPlayback(v)
end)
local macroStatus = CreateStatusBox(macroPage, 'Current Step: <font color="#d42a2a">idle</font>\nTarget: <font color="#d42a2a">--</font>\nTime: <font color="#d42a2a">0.0</font>\nGame Elapsed Time: <font color="#d42a2a">0.0</font>\nAction: <font color="#d42a2a">--</font>\nParameters: <font color="#d42a2a">--</font>')
task.spawn(function()
    while ScriptAlive() and macroStatus and macroStatus.Parent do
        pcall(function()
            if not MainFrame.Visible or not macroPage.Visible then return end
            if CurrentStep then
                local cs = ((KP.playback and KP.playback.profile) or GetActiveMacroProfile())["Macro"][CurrentStep]
                if cs then
                    local tgt = cs["Target"] and (cs["Target"]["Name"] .. "[" .. cs["Target"]["Index"] .. "]") or "--"
                    local action = cs["Remote"] and cs["Remote"][1] or "--"
                    local params = "--"
                    if cs["Parameter"] then
                        local parts = {}
                        for k, v in pairs(cs["Parameter"]) do
                            table.insert(parts, tostring(k) .. ": " .. tostring(v))
                        end
                        if #parts > 0 then params = table.concat(parts, "; ") end
                    end
                    local waveInfo = cs["Wave"] and tostring(cs["Wave"]) or "--"
                    local ecRec = cs["EnemyCount"] and tostring(cs["EnemyCount"]) or "--"
                    macroStatus.Text = string.format('Step: <font color="#d42a2a">%s</font> | Target: <font color="#d42a2a">%s</font>\nTime: <font color="#d42a2a">%.1f</font> | Wave: <font color="#d42a2a">%s</font> | Enemies: <font color="#d42a2a">%s</font>\nNow: <font color="#d42a2a">%.1f</font> | Wave: <font color="#d42a2a">%s</font> | Enemies: <font color="#d42a2a">%s</font>\nAction: <font color="#d42a2a">%s</font>\n%s', tostring(CurrentStep), tgt, cs["Time"] or 0, waveInfo, ecRec, ElapsedTime(), tostring(get_wave()), tostring(get_enemy_count()), action, params)
                else
                    macroStatus.Text = string.format('Current Step: <font color="#d42a2a">%s</font> (error)\nGame Elapsed Time: <font color="#d42a2a">%.1f</font>', tostring(CurrentStep), ElapsedTime())
                end
            else
                macroStatus.Text = string.format('Current Step: <font color="#d42a2a">idle</font>\nGame Elapsed Time: <font color="#d42a2a">%.1f</font>', ElapsedTime())
            end
        end)
        task.wait(0.3)
    end
end)
CreateButtonRow(macroPage, {"Prev", "Next", "Reset"}, {
    function() KP.SeekMacro(-1) end,
    function() KP.SeekMacro(1) end,
    function() KP.SeekMacro(0) end,
})

CreateSection(macroPage, "Profile management")
local _newProfileName = ""
CreateInput(macroPage, "New profile name", "Default Profile", nil, function(t) _newProfileName = t end)
CreateButton(macroPage, "Create new profile", true, false, function()
    if not KP.ValidProfileName(_newProfileName) or string.match(_newProfileName, '[^%w%s]') then ShowNotify("Macro", "Invalid name. Use 1-100 letters, numbers or spaces; no trailing spaces."); return end
    if KP.FindProfileName(_newProfileName) or isfile(GetMacroProfilePath(_newProfileName)) then ShowNotify("Macro", "Already exists (profile names ignore letter case).") return end
    rawset(Macros, _newProfileName, DeepCopy(IndividualMacroDefaultSettings))
    Settings.macro_profile = _newProfileName
    table.insert(MacroProfileList, _newProfileName)
    table.sort(MacroProfileList)
    Save()
    if KP.dirtyProfiles[_newProfileName] then
        ShowNotify("Macro", "Profile save failed; the profile is kept in memory with its save pending. Check the output.")
    else ShowNotify("Macro", "Profile created.") end
    rebuildProfileDropdown(MacroProfileList, Settings.macro_profile)
    RefreshMacroLeaderDropdown()
end)
local _confirmAction = nil
CreateButton(macroPage, "Delete profile", false, false, function()
    if #MacroProfileList <= 1 then ShowNotify("Macro", "Can't delete last profile."); return end
    _confirmAction = {kind = "delete", profile = Settings.macro_profile}
    ShowNotify("Confirm", "Press Confirm Action to delete " .. _confirmAction.profile .. ".")
end)
CreateButton(macroPage, "Clear macro data", false, false, function()
    _confirmAction = {kind = "clear", profile = Settings.macro_profile}
    ShowNotify("Confirm", "Press Confirm Action to clear " .. _confirmAction.profile .. ".")
end)
CreateButton(macroPage, "Confirm action", true, false, function()
    if KP.recording or KP.playback then ShowNotify("Macro", "Stop recording/playback before deleting or clearing profiles."); return end
    local pending = _confirmAction
    if not pending then ShowNotify("Macro", "No pending action."); return end
    if pending.profile ~= Settings.macro_profile then
        _confirmAction = nil
        ShowNotify("Macro", "Selected profile changed. Confirmation cancelled; no files changed.")
        return
    end
    if pending.kind == "delete" then
        if #MacroProfileList <= 1 then _confirmAction = nil; ShowNotify("Macro", "Can't delete last profile."); return end
        local rp = pending.profile
        local deleted, err = pcall(function() delfile(GetMacroProfilePath(rp)) end)
        if not deleted then KP.Report("Delete profile", err); ShowNotify("Macro", "Could not delete the file; profile retained."); return end
        KP.profileErrors[rp], KP.dirtyProfiles[rp] = nil, nil
        rawset(Macros, rp, nil)
        local index = table.find(MacroProfileList, rp)
        if index then table.remove(MacroProfileList, index) end
        Settings.macro_profile = MacroProfileList[1]
        Save()
        ShowNotify("Macro", rp .. " deleted.")
        rebuildProfileDropdown(MacroProfileList, Settings.macro_profile)
        RefreshMacroLeaderDropdown()
    elseif pending.kind == "clear" then
        local name = pending.profile
        local file = GetMacroProfilePath(name)
        local backedUp, err = pcall(function()
            if isfile(file) then writefile(file .. ".before-clear.bak", readfile(file)) end
        end)
        if not backedUp then KP.Report("Clear profile backup", err); return end
        KP.profileErrors[name] = nil
        rawset(Macros, name, DeepCopy(IndividualMacroDefaultSettings))
        KP.dirtyProfiles[name] = true
        CurrentStep = nil
        if SaveMacroProfile(name) then ShowNotify("Macro", "Data cleared. Previous file backed up.")
        else ShowNotify("Macro", "Clear could not be saved. Previous file backed up; save remains pending.") end
    end
    _confirmAction = nil
end)

CreateSection(macroPage, "Import / export")
local _importMacroURL = ""
local _importSettingsURL = ""
CreateInput(macroPage, "Import macro URL", "Paste link here", nil, function(t) _importMacroURL = t end)
CreateInput(macroPage, "Import settings URL", "Paste link here", nil, function(t) _importSettingsURL = t end)
RefreshMacroLeaderDropdown = function()
    local profile = GetActiveMacroProfile()
    if profile then
        GetMacroProfileLeaderUnit(profile)
    end
end
RefreshMacroLeaderDropdown()
CreateButton(macroPage, "Import start", true, false, function()
    if _importMacroURL ~= "" then importMacro(_importMacroURL) end
    if _importSettingsURL ~= "" then importSettings(_importSettingsURL) end
end)
CreateButton(macroPage, "Equip macro units", false, false, function() task.spawn(EquipMacroUnits) end)
CreateButton(macroPage, "Export macro to link", false, false, function()
    task.spawn(function()
        local profile = GetActiveMacroProfile()
        if not profile then ShowNotify("Export", "No profile.") return end
        GetMacroProfileLeaderUnit(profile)
        SaveMacroProfile(Settings.macro_profile)
        ShowNotify("Export", "Uploading...")
        local exportData = {}
        exportData[Settings.macro_profile] = profile
        local json = game:GetService("HttpService"):JSONEncode(exportData)
        local function tryUpload(data)
            local request = request or http_request or (http and http.request) or (syn and syn.request)
            if not request then return nil end
            -- Try hst.sh
            local ok, res = pcall(function()
                local r = request({Url = "https://hst.sh/documents", Method = "POST", Headers = {["Content-Type"] = "text/plain"}, Body = data})
                if r and r.Body then
                    local d = game:GetService("HttpService"):JSONDecode(r.Body)
                    if d and d.key then return "https://hst.sh/raw/" .. d.key end
                end
            end)
            if ok and res then return res end
            -- Try dpaste
            ok, res = pcall(function()
                local r = request({Url = "https://dpaste.com/api/", Method = "POST",
                    Headers = {["Content-Type"] = "application/x-www-form-urlencoded"},
                    Body = "content=" .. game:GetService("HttpService"):UrlEncode(data) .. "&expiry_days=30"})
                if r and r.Body then
                    local url = r.Body:gsub("%s+", "")
                    if url:find("dpaste.com") then return url .. ".txt" end
                end
            end)
            if ok and res then return res end
            return nil
        end
        local link = tryUpload(json)
        if link then
            pcall(function() setclipboard(link) end)
            ShowNotify("Export", "Link copied to clipboard!")
        else
            pcall(function() setclipboard(json) end)
            ShowNotify("Export", "Upload failed. JSON copied — paste to pastebin.com manually.")
        end
    end)
end)
CreateButton(macroPage, "Export settings to link", false, false, function()
    task.spawn(function()
        ShowNotify("Export", "Uploading settings...")
        local json = game:GetService("HttpService"):JSONEncode(Settings)
        local function tryUpload(data)
            local request = request or http_request or (http and http.request) or (syn and syn.request)
            if not request then return nil end
            local ok, res = pcall(function()
                local r = request({Url = "https://hst.sh/documents", Method = "POST", Headers = {["Content-Type"] = "text/plain"}, Body = data})
                if r and r.Body then
                    local d = game:GetService("HttpService"):JSONDecode(r.Body)
                    if d and d.key then return "https://hst.sh/raw/" .. d.key end
                end
            end)
            if ok and res then return res end
            ok, res = pcall(function()
                local r = request({Url = "https://dpaste.com/api/", Method = "POST",
                    Headers = {["Content-Type"] = "application/x-www-form-urlencoded"},
                    Body = "content=" .. game:GetService("HttpService"):UrlEncode(data) .. "&expiry_days=30"})
                if r and r.Body then
                    local url = r.Body:gsub("%s+", "")
                    if url:find("dpaste.com") then return url .. ".txt" end
                end
            end)
            if ok and res then return res end
            return nil
        end
        local link = tryUpload(json)
        if link then
            pcall(function() setclipboard(link) end)
            ShowNotify("Export", "Settings link copied!")
        else
            pcall(function() setclipboard(json) end)
            ShowNotify("Export", "Upload failed. JSON copied.")
        end
    end)
end)

CreateSection(macroPage, "Recording options")
AddInfoIcon(CreateSlider(macroPage, "Record time offset", -10, 10, 0.1, "macro_record_time_offset", 0), "Shifts recording times. Higher = faster recording, lower = slower recording.", 8)

CreateSection(macroPage, "Playback options")
AddInfoIcon(CreateToggle(macroPage, "Money tracking", nil, "macro_money_tracking", false), "Waits until you have enough money before executing each action.", 8)
AddInfoIcon(CreateToggle(macroPage, "Auto-adjust placements", nil, "macro_auto_adjust_placement", false), "Use this if you're having trouble with placements.", 8)
AddInfoIcon(CreateSlider(macroPage, "Playback time offset", -10, 10, 0.1, "macro_playback_time_offset", 0), "Adjusts all playback actions. Positive = fire earlier, Negative = fire later.", 8)
AddInfoIcon(CreateSlider(macroPage, "Magnitude", 0, 2, 0.01, "macro_magnitude", 1), "How close a unit must be to its recorded position to be recognized. Increase if units aren't being found.", 8)
AddInfoIcon(CreateSlider(macroPage, "Search attempts", 0, 120, 1, "macro_playback_search_attempts", 60), "How many times the script tries to find a unit before skipping the action.", 8)
AddInfoIcon(CreateSlider(macroPage, "Search delay", 0, 1, 0.01, "macro_playback_search_delay", 1), "Delay between each search attempt when looking for a unit.", 8)

CreateSection(macroPage, "Action queue")
AddInfoIcon(CreateSlider(macroPage, "Step delay", 0, 1, 0.01, "action_queue_remote_fire_delay", 0.25), "Time between each step. Lower = faster fire rate but it'll prolly mess up or sum.", 8)
AddInfoIcon(CreateToggle(macroPage, "Retry failed steps", nil, "action_queue_remote_on_fail", true), "Automatically retries steps that fail (unit didn't summon, upgrade didn't apply).", 8)
AddInfoIcon(CreateSlider(macroPage, "Retry delay", 0, 1, 0.01, "action_queue_remote_on_fail_delay", 1), "How long to wait before the first retry attempt.", 8)
AddInfoIcon(CreateSlider(macroPage, "Retry loop delay", 0, 1, 0.01, "action_queue_remote_on_fail_delay_loop", 0.5), "Delay between each retry attempt in the loop.", 8)

CreateSection(macroPage, "Macro options")
CreateToggle(macroPage, "Summon unit", nil, "macro_summon", true)
CreateToggle(macroPage, "Sell unit", nil, "macro_sell", true)
CreateToggle(macroPage, "Upgrade unit", nil, "macro_upgrade", true)
CreateToggle(macroPage, "Priority", nil, "macro_priority", true)
CreateToggle(macroPage, "Unit ability", nil, "macro_ability", true)
CreateToggle(macroPage, "Unit auto ability", nil, "macro_auto_ability", true)
CreateToggle(macroPage, "Skip wave", nil, "macro_skipwave", true)
CreateToggle(macroPage, "Auto skip wave", nil, "macro_autoskipwave", true)
CreateToggle(macroPage, "Speed change", nil, "macro_speedchange", true)

if not is_lobby() then
    CreateSection(macroPage, "Offset settings")
    CreateParagraph(macroPage, "", "Recalculates unit positions if the map changed. Save spawn position first, then update placements. Changes are permanent.")
    CreateButton(macroPage, "Save current spawn position", true, false, function()
        Macros[Settings.macro_profile]["Map"] = {
            ["SpawnLocation"] = tostring(game:GetService("Workspace").SpawnLocation.CFrame)
        }
        Save()
        ShowNotify("Macro", "Spawn position saved to profile.")
    end)
    CreateButton(macroPage, "Update placement locations", false, false, function()
        if KP.recording or KP.playback then ShowNotify("Macro", "Stop recording/playback before moving placements."); return end
        local profile = GetActiveMacroProfile()
        local spawn = workspace:FindFirstChild("SpawnLocation")
        local saved = profile and profile.Map and profile.Map.SpawnLocation
        if not spawn or not saved then ShowNotify("Macro", "Save a reference spawn position first."); return end
        local ok, updated = pcall(function()
            local copy = DeepCopy(profile)
            local offset = spawn.CFrame * StringToCFrame(saved):Inverse()
            for _, placements in pairs(copy.Units) do
                for _, placement in ipairs(placements) do
                    placement.Position = tostring(offset * StringToCFrame(placement.Position))
                end
            end
            copy.Map.SpawnLocation = tostring(spawn.CFrame)
            return copy
        end)
        if not ok then KP.Report("Placement offset", updated); ShowNotify("Macro", "Invalid placement data; no changes applied."); return end
        local file = GetMacroProfilePath(Settings.macro_profile)
        local backedUp, err = pcall(function() writefile(file .. ".before-offset.bak", readfile(file)) end)
        if not backedUp then KP.Report("Placement backup", err); return end
        rawset(Macros, Settings.macro_profile, updated)
        KP.macroTargetPositionCache, MacroTargetCache = {}, {}
        if SaveMacroProfile(Settings.macro_profile) then ShowNotify("Macro", "Placement locations updated. Previous file backed up.")
        else ShowNotify("Macro", "Placement save failed; changes remain pending. Previous file backed up.") end
    end)
end

end
TabPages["Lobby"].loader = function()
local lobbyPage = TabPages["Lobby"].page
elementOrder = 0
CreateSection(lobbyPage, "Lobby scripts")
CreateToggle(lobbyPage, "Auto join game", nil, "auto_join_game", false, function(v)
    if v and is_lobby() then
        task.spawn(AutoJoinGame)
    elseif _kpEnv.KP_Runtime then
        _kpEnv.KP_Runtime.autoJoinToken = (_kpEnv.KP_Runtime.autoJoinToken or 0) + 1
    end
end)
CreateToggle(lobbyPage, "Auto join tower", nil, "auto_join_tower", false, function(v) if v and is_lobby() then task.spawn(AutoTower) end end)
CreateToggle(lobbyPage, "Auto evolve EXP", nil, "auto_evolve_exp", true, function(v) if v and is_lobby() then task.spawn(AutoEvolveEXP) end end)
CreateToggle(lobbyPage, "Auto click popup", nil, "auto_skip_gui", true, function(v) if v then task.spawn(AutoSkipGUI) end end)

CreateSection(lobbyPage, "Auto join settings")

local infiniteMaps = GetMapsFromTable(InfiniteMapTable)
table.sort(infiniteMaps)
local adventureMaps = GetMapsFromTable(AdventureMapTable)
table.sort(adventureMaps, function(a, b)
    local aTop = a:match("^TOP(%d+)$")
    local bTop = b:match("^TOP(%d+)$")
    if aTop and bTop then return tonumber(aTop) < tonumber(bTop) end
    if aTop then return false end
    if bTop then return true end
    return a < b
end)

CreateDropdown(lobbyPage, "Mode", {"Story", "Infinite", "Adventure"}, "auto_join_mode", Settings.auto_join_mode)

local infDefault = InfiniteMapTable[Settings.auto_join_infinite_level] or "Regular [2]"
CreateDropdown(lobbyPage, "Infinite map", infiniteMaps, nil, infDefault, function(opt)
    for k, v in pairs(InfiniteMapTable) do if v == opt then Settings.auto_join_infinite_level = k; Save(); break end end
end, "auto_join_infinite_level", function(v) return InfiniteMapTable[tostring(v)] or infDefault end)

local advDefault = AdventureMapTable[Settings.auto_join_adventure_level] or "Mythical Freedom"
CreateDropdown(lobbyPage, "Adventure map", adventureMaps, nil, advDefault, function(opt)
    for k, v in pairs(AdventureMapTable) do if v == opt then Settings.auto_join_adventure_level = k; Save(); break end end
end, "auto_join_adventure_level", function(v) return AdventureMapTable[tostring(v)] or advDefault end)
CreateSlider(lobbyPage, "Story target", 0, get_number_missions(), 1, "auto_story_target", Settings.auto_story_target or 0)
CreateSlider(lobbyPage, "Delay (sec)", 0, 60, 1, "auto_join_delay", Settings.auto_join_delay)

CreateSection(lobbyPage, "Advanced Joining")
local advancedJoinCards = {}
local function SetAdvancedJoinCardsVisible(visible)
    for _, card in ipairs(advancedJoinCards) do card.Visible = visible end
    if not visible and Settings.smart_join_exp_active then
        Settings.smart_join_exp_active = false
        Settings.smart_join_exp_tickets_remaining = 0
        Save()
    end
end

CreateToggle(lobbyPage, "Advanced Joining",
    "EXP ticket priority; macro selection stays manual",
    "advanced_join_settings", false, SetAdvancedJoinCardsVisible)

table.insert(KP.uiRefresh, function() SetAdvancedJoinCardsVisible(Settings.advanced_join_settings) end)
local autoExpCard = CreateToggle(lobbyPage, "Auto Join EXP",
    "EXP tickets take priority; select a compatible macro manually",
    "smart_join_auto_exp", false, function(enabled)
        if not enabled then
            Settings.smart_join_exp_active = false
            Settings.smart_join_exp_tickets_remaining = 0
            Save()
        end
    end)
table.insert(advancedJoinCards, autoExpCard)



SetAdvancedJoinCardsVisible(Settings.advanced_join_settings == true)

end
TabPages["Webhooks"].loader = function()
local webhooksPage = TabPages["Webhooks"].page
elementOrder = 0
CreateSection(webhooksPage, "Settings")
CreateInput(webhooksPage, "Webhook URL", "https://discord.com/api/webhooks/...", "webhook_url")
CreateInput(webhooksPage, "Discord ID", "Your Discord User ID", "webhook_discord_id")
CreateButton(webhooksPage, "Test webhook", true, false, function()
    SendWebhook({{["name"] = "Webhook Test", ["value"] = "Sent successfully!"}})
    ShowNotify("Webhook", "Test sent!")
end)
CreateSection(webhooksPage, "Toggles")
CreateToggle(webhooksPage, "Show username", nil, "webhook_user_name", true)
CreateToggle(webhooksPage, "Ping user", nil, "webhook_ping_user", false)
CreateToggle(webhooksPage, "Ping only on lose", nil, "webhook_ping_on_lose", false)
CreateToggle(webhooksPage, "Webhook on game end", nil, "webhook_end_game", false)
CreateToggle(webhooksPage, "Webhook after EXP evolve", nil, "webhook_exp_evolve", false)

end
TabPages["Advanced"].loader = function()
local advancedPage = TabPages["Advanced"].page
elementOrder = 0

CreateHeader(advancedPage, "Auto Ability", "Configure which units automatically use their buff or timestop abilities during gameplay.")

local buffUnitList = get_keys(Settings.auto_buff_units)
table.sort(buffUnitList)

if #buffUnitList > 0 then
    local buffInfoBox = CreateStatusBox(advancedPage, "Tap a unit to see its config.")
    local buffDropdownCard, buffDropdownSel
    buffDropdownCard, buffDropdownSel = CreateDropdown(advancedPage, "Your units", buffUnitList, nil, buffUnitList[1], function(opt)
        if Settings.auto_buff_units[opt] then
            local u = Settings.auto_buff_units[opt]
            local checks = type(u["Checks"]) == "table" and table.concat(u["Checks"], ", ") or tostring(u["Checks"])
            if checks == "" then checks = "none" end
            buffInfoBox.Text = string.format('<font color="#d42a2a">%s</font>  %s mode, %ss cooldown\nChecks: %s | Ability: %s', opt, tostring(u["Mode"]), tostring(u["Time"]), checks, tostring(u["Ability Type"]))
        end
    end)
    pcall(function()
        local u = Settings.auto_buff_units[buffUnitList[1]]
        if u then
            local checks = type(u["Checks"]) == "table" and table.concat(u["Checks"], ", ") or tostring(u["Checks"])
            if checks == "" then checks = "none" end
            buffInfoBox.Text = string.format('<font color="#d42a2a">%s</font>  %s mode, %ss cooldown\nChecks: %s | Ability: %s', buffUnitList[1], tostring(u["Mode"]), tostring(u["Time"]), checks, tostring(u["Ability Type"]))
        end
    end)
    CreateButton(advancedPage, "Remove selected unit", false, true, function()
        if not buffDropdownSel then ShowNotify("Ability", "No units configured.") return end
        local sel = buffDropdownSel.Text
        if sel and Settings.auto_buff_units[sel] then
            Settings.auto_buff_units[sel] = nil
            Save()
            ShowNotify("Ability", sel .. " removed.")
            buffInfoBox.Text = "Removed. Re-execute to refresh."
        else
            ShowNotify("Ability", "Nothing to remove.")
        end
    end)
    CreateButton(advancedPage, "Reset buff list to default", false, true, function()
        Settings.auto_buff_units = DeepCopy(DefaultSettings.auto_buff_units)
        Save()
        ShowNotify("Ability", "Buff list reset to default. Re-execute to refresh.")
        buffInfoBox.Text = "Reset to default. Re-execute to refresh."
    end)
else
    CreateParagraph(advancedPage, "", "No ability units configured yet. Add one below or import settings.")
end

local UnitList = get_loadout_units()
table.sort(UnitList)
if (Settings.auto_target_ability_unit == nil or Settings.auto_target_ability_unit == "") and #UnitList > 0 then
    Settings.auto_target_ability_unit = UnitList[1]
    Save()
end

CreateSection(advancedPage, "Add New Ability Unit")
local _addBuffUnit = UnitList[1] or "None"
local _addBuffMode = "Box"
local _addBuffChecks = {}
local _addBuffAbilityName = nil
local _addBuffTime = 13
local _addBuffCycleUnits = 8
local _addBuffDelay = 0
if #UnitList > 0 then
    CreateDropdown(advancedPage, "Unit", UnitList, nil, UnitList[1], function(opt) _addBuffUnit = opt end)
end
CreateDropdown(advancedPage, "Mode", {"Box", "Pair", "Cycle", "Spam"}, nil, "Box", function(opt) _addBuffMode = opt end)
AddInfoIcon(CreateDropdown(advancedPage, "Checks", {"Attack + Range", "Attack only", "Range only", "None"}, nil, "None", function(opt)
    if opt == "Attack + Range" then _addBuffChecks = {"attack", "range"}
    elseif opt == "Attack only" then _addBuffChecks = {"attack"}
    elseif opt == "Range only" then _addBuffChecks = {"range"}
    else _addBuffChecks = {} end
end), "What to check before re-buffing. Waits for the buff to fade before reapplying.", 8)
CreateInput(advancedPage, "Multi ability name", "Leave empty if normal", nil, function(t) _addBuffAbilityName = (t ~= "" and t or nil) end)
CreateInput(advancedPage, "Cooldown (sec)", "13", nil, function(t) _addBuffTime = tonumber(t) or 13 end)
CreateButton(advancedPage, "Add unit", true, false, function()
    if _addBuffUnit == "None" or _addBuffUnit == nil then ShowNotify("Ability", "Select a unit first.") return end
    if Settings.auto_buff_units[_addBuffUnit] then ShowNotify("Ability", _addBuffUnit .. " is already configured.") return end
    local abilityType = _addBuffAbilityName and "Multiple" or "Normal"
    Settings.auto_buff_units[_addBuffUnit] = {
        ["Mode"] = _addBuffMode,
        ["Checks"] = _addBuffChecks,
        ["Ability Type"] = abilityType,
        ["Ability Name"] = _addBuffAbilityName,
        ["Time"] = _addBuffTime,
        ["Cycle Units"] = _addBuffCycleUnits,
        ["Delay"] = _addBuffDelay
    }
    Save()
    ShowNotify("Ability", _addBuffUnit .. " added. Re-execute to see it in the list.")
end)

CreateSection(advancedPage, "Cycle Timestop")
CreateToggle(advancedPage, "Cycle Timestop", "Cycles through already placed timestop units", "auto_cycle_timestop", false, function(v)
    if v and not is_lobby() then task.spawn(KP_AutoCycleTimestop) end
end)
if #UnitList > 0 then
    CreateDropdown(advancedPage, "Timestop Unit", UnitList, "auto_cycle_timestop_unit", Settings.auto_cycle_timestop_unit or "Gojo7")
else
    CreateInput(advancedPage, "Timestop Unit", "Gojo7", "auto_cycle_timestop_unit")
end

CreateSection(advancedPage, "Auto Killua")
CreateToggle(advancedPage, "Auto Killua", nil, "auto_killua", false, function(v)
    if v and not is_lobby() then task.spawn(KP_AutoKillua) end
end)
CreateDropdown(advancedPage, "Wish", {"Money", "Death", "Healing"}, "auto_killua_wish", Settings.auto_killua_wish or "Money")

CreateSection(advancedPage, "Smart Ability")
local smartAbilityCards = {}
local targetMultiSlotCard
local function AddSmartAbilityCard(card)
    table.insert(smartAbilityCards, card)
    return card
end
local function SetSmartAbilitySettingsVisible(enabled)
    for _, card in ipairs(smartAbilityCards) do
        card.Visible = enabled
    end
    if targetMultiSlotCard then
        targetMultiSlotCard.Visible = enabled and Settings.auto_target_ability_multi == true
    end
end
CreateToggle(advancedPage, "Smart Ability", "Uses the unit's ability when enemy is below the hp%. Yuhr Listen", "auto_target_ability", false, function(v)
    SetSmartAbilitySettingsVisible(v)
    if v and not is_lobby() then task.spawn(KP_AutoTargetAbility) end
end)
AddSmartAbilityCard(CreateDropdown(advancedPage, "Enemy Type", {"Cloner", "Decelerate", "Boss"}, "auto_target_enemy_type", Settings.auto_target_enemy_type or "Cloner"))
AddSmartAbilityCard(CreateSlider(advancedPage, "Trigger HP %", 0, 100, 1, "auto_target_hp_percent", Settings.auto_target_hp_percent or 10))
AddSmartAbilityCard(CreateSlider(advancedPage, "Enemy Count", 0, 10, 1, "auto_target_enemy_count", Settings.auto_target_enemy_count or 0))
AddSmartAbilityCard(CreateSlider(advancedPage, "Smart Ability Delay", 0, 10, 0.1, "auto_target_ability_delay", Settings.auto_target_ability_delay or 0))
if #UnitList > 0 then
    AddSmartAbilityCard(CreateDropdown(advancedPage, "Ability Unit", UnitList, "auto_target_ability_unit", Settings.auto_target_ability_unit or UnitList[1]))
else
    AddSmartAbilityCard(CreateInput(advancedPage, "Ability Unit", "Unit name", "auto_target_ability_unit"))
end
AddSmartAbilityCard(CreateToggle(advancedPage, "Multi Ability", nil, "auto_target_ability_multi", false, function(v)
    if targetMultiSlotCard then
        targetMultiSlotCard.Visible = Settings.auto_target_ability == true and v
    end
end))
targetMultiSlotCard = CreateDropdown(advancedPage, "Multi Ability", {"Slot 1", "Slot 2"}, nil,
    "Slot " .. tostring(Settings.auto_target_ability_multi_slot or 1), function(opt)
        Settings.auto_target_ability_multi_slot = opt == "Slot 2" and 2 or 1
        Save()
    end, "auto_target_ability_multi_slot", function(v) return "Slot " .. tostring(v or 1) end)
SetSmartAbilitySettingsVisible(Settings.auto_target_ability == true)
table.insert(KP.uiRefresh, function() SetSmartAbilitySettingsVisible(Settings.auto_target_ability == true) end)

CreateDivider(advancedPage)

CreateSection(advancedPage, "Automation")
do
local AP=KP.AutoPlacement
local function group(title,parent)
    parent=parent or advancedPage
    local holder=CreateCard(parent)
    holder.Name="AutomationGroup_"..title
    holder.BackgroundTransparency=1
    local layout=Instance.new("UIListLayout",holder)
    layout.Padding=UDim.new(0,5);layout.SortOrder=Enum.SortOrder.LayoutOrder
    local body=Instance.new("Frame",holder)
    body.Name="Content";body.BackgroundTransparency=1;body.Size=UDim2.new(1,0,0,0)
    body.AutomaticSize=Enum.AutomaticSize.Y;body.LayoutOrder=100000;body.Visible=false
    local content=Instance.new("UIListLayout",body)
    content.SortOrder=Enum.SortOrder.LayoutOrder;content.Padding=UDim.new(0,5)
    CreateToggle(holder,title,nil,nil,false,function(v)body.Visible=v end,{get=function()return body.Visible end,set=function(v)body.Visible=v end})
    return body
end
local function slider(parent,label,value,low,high,step,callback)
    local _,refresh=CreateSlider(parent,label,low,high,step,nil,value,function(v)callback(v);Save()end)
    return refresh
end
local status=CreateStatusBox(advancedPage,Settings.auto_place and AP.status or "Stopped")
CreateToggle(advancedPage,"Auto Placement",nil,"auto_place",false,function(enabled)
    if enabled then AP.Setup();AP.Changed();if not is_lobby() then task.spawn(AP.Run) end else AP.status="Stopped" end
    status.Text=enabled and AP.status or "Stopped"
end)
local team=group("Team Priorities")
AP.RefreshTeam()
local selectedUnit=AP.team[1]
local options=#AP.team>0 and AP.team or {"No equipped units"}
local _,_,rebuildUnits=CreateDropdown(team,"Unit",options,nil,options[1],function(name)
    selectedUnit=name;if AP.RefreshUI then AP.RefreshUI() end
end)
local function config()return selectedUnit and Settings.auto_place_units[selectedUnit]end
local function edit(key,value)
    local unit=config();if unit then unit[key]=value;AP.Changed() end
end
local _,refreshUnit=CreateToggle(team,"Place Unit",nil,nil,true,nil,{get=function()return config() and config().enabled or false end,set=function(v)edit("enabled",v);Save()end})
local selector=CreateCard(team)
selector.Name="PlacementZoneSelector";selector.Size=UDim2.new(1,0,0,59);selector.AutomaticSize=Enum.AutomaticSize.None
local label=Instance.new("TextLabel",selector)
label.Text="Zone Number";label.Font=Enum.Font.GothamMedium;label.TextSize=12;label.TextColor3=Colors.text
label.BackgroundTransparency=1;label.Position=UDim2.new(0,10,0,3);label.Size=UDim2.new(1,-20,0,18)
label.TextXAlignment=Enum.TextXAlignment.Left;label.ZIndex=5
local zoneButtons={}
for index=1,4 do
    local button=Instance.new("TextButton",selector)
    button.Name="SelectZone"..index;button.Text="Zone "..index;button.Font=Enum.Font.GothamMedium;button.TextSize=10
    button.Size=UDim2.new(.25,-8,0,24);button.Position=UDim2.new((index-1)/4,5,0,27)
    button.BorderSizePixel=0;button.AutoButtonColor=false;button.ZIndex=6
    Instance.new("UICorner",button).CornerRadius=UDim.new(0,5)
    zoneButtons[index]=button
    button.MouseButton1Click:Connect(function()
        local unit=config();if not unit then return end
        local chosen=table.clone(unit.zones);local at=table.find(chosen,index)
        if at then table.remove(chosen,at) else table.insert(chosen,index);table.sort(chosen) end
        edit("zones",chosen);Save()
    end)
end
local priority=slider(team,"Unit Priority | Higher First",1,0,100,1,function(v)edit("priority",v)end)
local count=slider(team,"Max Units",1,1,8,1,function(v)edit("limit",math.min(v,AP.MaxAllowed(selectedUnit)))end)
local upgradeCap=slider(team,"Upgrade Cap",20,0,20,1,function(v)edit("upgradeCap",v)end)
CreateButton(team,"Refresh Current Team",false,false,function()AP.RefreshTeam();AP.RefreshUI()end)
local zones=group("Placement Zones")
local selectedZone=1
CreateDropdown(zones,"Selected Zone",{"Zone 1","Zone 2","Zone 3","Zone 4"},nil,"Zone 1",function(option)
    selectedZone=tonumber(option:match("%d+")) or 1;if AP.RefreshUI then AP.RefreshUI() end
end)
local _,refreshZone=CreateToggle(zones,"Zone Enabled",nil,nil,true,nil,{get=function()return AP.Zones()[selectedZone].enabled end,set=function(v)
    AP.Zones()[selectedZone].enabled=v;AP.nextScan=0;AP.Changed();Save()
end})
CreateToggle(zones,"Show Zones",nil,"auto_place_show_zones",true,function()AP.Render()end)
CreateButton(zones,"Place / Move Selected Zone",true,false,function()AP.ArmZone(selectedZone)end)
local size=slider(zones,"Zone Size",Settings.auto_place_size,8,100,1,function(v)
    AP.Zones()[selectedZone].size=v;Settings.auto_place_size=v;AP.Changed()
end)
local opacity=slider(zones,"Zone Transparency",Settings.auto_place_transparency,.25,.95,.05,function(v)Settings.auto_place_transparency=v;AP.Render()end)
local tuning=group("Placement Tuning")
local reserve=slider(tuning,"Money Reserve",Settings.auto_place_reserve,0,10000,1,function(v)Settings.auto_place_reserve=v end)
local interval=slider(tuning,"Action Interval",Settings.auto_place_interval,0,5,.05,function(v)Settings.auto_place_interval=v end)
local spacing=slider(tuning,"Unit Spacing",Settings.auto_place_spacing,0,20,.5,function(v)Settings.auto_place_spacing=v;AP.Changed()end)
CreateToggle(tuning,"Auto Upgrade",nil,"auto_place_upgrade",true)
local thresholds=group("Other Automation",tuning)
AddInfoIcon(CreateSlider(thresholds, "Battle gems", 0, 10000, 50, "auto_battle_gems", 2700), "Minimum gems needed before Auto Battle activates.", 8)
AddInfoIcon(CreateSlider(thresholds, "Upgrade min money", 0, 10000, 50, "auto_upgrade_money", 100), "Auto Upgrade only fires when in-game money is at or above this.", 8)
AddInfoIcon(CreateSlider(thresholds, "Upgrade start wave", 0, 200, 1, "auto_upgrade_wave", 0), "Auto Upgrade begins at this wave. 0 = start immediately.", 8)
AddInfoIcon(CreateSlider(thresholds, "Upgrade stop wave", 0, 200, 1, "auto_upgrade_wave_stop", 100), "Auto Upgrade stops at this wave.", 8)
CreateSlider(thresholds, "Sell at wave", 0, 200, 1, "auto_upgrade_wave_sell", 100)
function AP.RefreshUI()
    if not table.find(AP.team,selectedUnit) then selectedUnit=AP.team[1] end
    rebuildUnits(#AP.team>0 and AP.team or {"No equipped units"},selectedUnit or "No equipped units")
    local unit=config()
    refreshUnit(unit and unit.enabled or false)
    if unit then priority(unit.priority);count(AP.MaxCount(selectedUnit,unit),AP.MaxAllowed(selectedUnit));upgradeCap(unit.upgradeCap) end
    for index,button in ipairs(zoneButtons)do
        local on=unit and table.find(unit.zones,index)~=nil
        button.BackgroundColor3=on and Colors.accentDark or Colors.input
        button.TextColor3=on and Colors.white or Colors.text2
    end
    local zone=AP.Zones()[selectedZone]
    refreshZone(zone.enabled);size(zone.size);opacity(Settings.auto_place_transparency)
    reserve(Settings.auto_place_reserve);interval(Settings.auto_place_interval);spacing(Settings.auto_place_spacing)
end
AP.RefreshUI();AP.Render();table.insert(KP.uiRefresh,AP.RefreshUI)
task.spawn(function()
    local lastTeam=table.concat(AP.team,"|")
    while ScriptAlive() and advancedPage.Parent do
        if advancedPage.Visible and MainFrame.Visible then
            AP.RefreshTeam();local current=table.concat(AP.team,"|")
            if current~=lastTeam then lastTeam=current;AP.RefreshUI() end
            status.Text=Settings.auto_place and AP.status or "Stopped"
        end
        task.wait(1)
    end
end)
end
end

TabPages["Settings"].loader = function()
local miscPage = TabPages["Settings"].page
elementOrder = 0

local uiScaleObj = MainFrame:FindFirstChildOfClass("UIScale")
if not uiScaleObj then
    uiScaleObj = Instance.new("UIScale")
    uiScaleObj.Parent = MainFrame
end
uiScaleObj.Scale = Settings.ui_scale or 0.95

CreateSection(miscPage, "UI")
CreateSlider(miscPage, "UI Scale", 0.5, 1.5, 0.05, "ui_scale", Settings.ui_scale or 0.95)
CreateToggle(miscPage, "Auto Execute", nil, "auto_execute", false, function(v)
    if v then
        BindAutoExecute()
        local ok = GetQueueOnTeleport() ~= nil
        if not ok then
            ShowNotify("Auto Execute", "Executor does not support queue_on_teleport.")
            ShowNotify("Auto Execute", "Try: Delta, Fluxus, Synapse X, or KRNL.")
        else
            ShowNotify("Auto Execute", "Will re-execute after next teleport.")
        end
    else
        _kpEnv.KP_AutoExecuteQueuedJobId = nil
    end
end)
CreateToggle(miscPage, "Enemy Overlay", "Enemy HP and speed", "show_enemy_overlay", false, function(v)
    if not v then
        for enemy, _ in pairs(_kpEnv.KP_Runtime.enemyOverlayRefs or {}) do KP_RemoveEnemyOverlay(enemy) end
    end
end)
CreateToggle(miscPage, "Close UI On Execution", "K or Left Ctrl to reopen", "close_on_injection", false)

CreateToggle(miscPage, "Mobile Toggle Button", nil, "mobile_toggle", true, function(v)
    if v then
        createMobileToggle()
    else
        for _, g in pairs(ScreenGui:GetChildren()) do
            if g.Name == "MobileToggle" then g:Destroy() end
        end
    end
end)
CreateToggle(miscPage, "Lock UI Position", nil, "lock_ui", false)

CreateSection(miscPage, "Visual")
CreateToggle(miscPage, "Performance Mode", nil, "fps_boost", false, function(v) if v then task.spawn(FpsBoost) else KP.restoreFPS() end end)
CreateToggle(miscPage, "Destroy Enemies", nil, "delete_enemies", false, function(v)
    if v then task.spawn(DeleteEnemies) else pcall(ApplySimplifyEnemies) end
end)
CreateToggle(miscPage, "Hide Map", nil, "delete_map", false, function(v)
    if v then
        if is_lobby() then
            Settings.delete_map = false
            Save()
            if UIRefs["delete_map"] then UIRefs["delete_map"].setValue(false) end
            ShowNotify("Hide Map", "Disabled in lobby.")
            return
        end
        task.spawn(DeleteMap)
    else
        pcall(RestoreMap)
    end
end)
CreateToggle(miscPage, "Disable 3D Rendering", nil, "disable_3d_rendering", false, function(v)
    KP.applyRendering(v)
end)
CreateToggle(miscPage, "Anonymous Mode", nil, "anonymous_mode", false, function(v) if v then pcall(AnonMode) elseif KP.restoreAnonymous then KP.restoreAnonymous() end end)
CreateInput(miscPage, "Display Name", "KarmaPanda", "anonymous_mode_name", function(t)
    if Settings.anonymous_mode then pcall(AnonMode) end
end)
local _, fpsLimitBox = CreateInput(miscPage, "FPS Limit", "60", nil, function(t, enterPressed)
    if not enterPressed then return end
    if t == "" then
        Settings.fps_limit = "60"
        Save()
        ApplyFPSLimit(60, true)
        return
    end
    ApplyFPSLimit(t, true)
end)
fpsLimitBox.Text = tostring(Settings.fps_limit or "60")

if get_world() ~= -1 and get_world() ~= -2 then
CreateSection(miscPage, "World Teleports")
    if get_world() == 1 then
        CreateButton(miscPage, "Teleport to World 2", false, false, function()
            pcall(function()
                firetouchinterest(Player.Character.HumanoidRootPart, get_world_teleporter(), 0)
                task.wait()
                firetouchinterest(Player.Character.HumanoidRootPart, get_world_teleporter(), 1)
            end)
        end)
    elseif get_world() == 2 then
        CreateButton(miscPage, "Teleport to World 1", false, false, function()
            pcall(function()
                firetouchinterest(Player.Character.HumanoidRootPart, get_world_teleporter(), 0)
                task.wait()
                firetouchinterest(Player.Character.HumanoidRootPart, get_world_teleporter(), 1)
            end)
        end)
    end
    CreateButton(miscPage, "Teleport to Lobby", false, false, function()
        pcall(function()
            game:GetService("TeleportService"):Teleport(4996049426, Player)
        end)
    end)
end

CreateSection(miscPage, "Reset")
CreateButton(miscPage, "Reset settings to default", false, true, function()
    KP.ApplySettings(DeepCopy(DefaultSettings))
    ShowNotify("Reset", "Settings restored to defaults.")
end)

CreateSection(miscPage, "Hotkeys")
CreateToggle(miscPage, "UI Keybinds", "R = Record | P = Playback", "macro_keybinds", true)

task.spawn(function()
    while ScriptAlive() and MainFrame and MainFrame.Parent do
        pcall(function()
            local target = Settings.ui_scale or 0.95
            if uiScaleObj.Scale ~= target then
                uiScaleObj.Scale = target
            end
        end)
        task.wait(0.2)
    end
end)

end
function KP.refreshSettingsUI()
    for key, ref in pairs(UIRefs) do if ref.refresh then pcall(ref.refresh, Settings[key]) end end
    for _, refresh in ipairs(KP.uiRefresh) do pcall(refresh) end
    local scale = MainFrame:FindFirstChildOfClass("UIScale")
    if scale then scale.Scale = Settings.ui_scale end
    if Settings.mobile_toggle then createMobileToggle() else
        for _, child in ipairs(ScreenGui:GetChildren()) do if child.Name == "MobileToggle" then child:Destroy() end end
    end
end
TabPages["Main"].btn.TextColor3 = Colors.white
TabPages["Main"].indicator.BackgroundTransparency = 0
TabPages["Main"].page.Visible = true
CurrentTab = "Main"

function KP_ApplyCollapsedSections(page)
    local children = page:GetChildren()
    local headers = {}
    for _, c in pairs(children) do
        if c.Name and c.Name:find("SectionHeader_") then table.insert(headers, c) end
    end
    table.sort(headers, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
    for idx, h in ipairs(headers) do
        local sk = h.Name:gsub("SectionHeader_", "")
        if SectionVisibility[sk] == false then
            local nextOrd = 999999
            if headers[idx + 1] then nextOrd = headers[idx + 1].LayoutOrder end
            for _, c in pairs(children) do
                if c ~= h and not c:IsA("UIListLayout") and not c:IsA("UIPadding") and c.LayoutOrder > h.LayoutOrder and c.LayoutOrder < nextOrd then
                    c.Visible = false
                end
            end
        end
    end
end
KP_ApplyCollapsedSections(TabPages["Main"].page)
KP_ApplyCollapsedSections(TabPages["Macro"].page)
KP_ApplyCollapsedSections(TabPages["Lobby"].page)
KP_ApplyCollapsedSections(TabPages["Webhooks"].page)
KP_ApplyCollapsedSections(TabPages["Advanced"].page)
KP_ApplyCollapsedSections(TabPages["Settings"].page)

function KP_EnsureCurrentTabLoaded()
    local data = CurrentTab and TabPages[CurrentTab]
    if data and not data.loaded and data.loader then
        data.loaded = true
        data.loader()
        task.defer(function()
            pcall(function() KP_ApplyCollapsedSections(data.page) end)
        end)
    end
end

if not Settings.close_on_injection then
    KP_EnsureCurrentTabLoaded()
end

KP_UIDragging = false
KP_UIDragStart = nil
KP_UIStartPos = nil
TrackConnection(Header.InputBegan:Connect(function(input)
    if Settings.lock_ui then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        KP_UIDragging = true; KP_UIDragStart = input.Position; KP_UIStartPos = MainFrame.Position
    end
end))
TrackConnection(Header.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        KP_UIDragging = false
    end
end))
TrackConnection(UserInputService.InputChanged:Connect(function(input)
    if KP_UIDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - KP_UIDragStart
        MainFrame.Position = UDim2.new(KP_UIStartPos.X.Scale, KP_UIStartPos.X.Offset + delta.X, KP_UIStartPos.Y.Scale, KP_UIStartPos.Y.Offset + delta.Y)
    end
end))

TrackConnection(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.K or input.KeyCode == Enum.KeyCode.LeftControl then
        uiVisible = not uiVisible
        MainFrame.Visible = uiVisible
        if uiVisible then KP_EnsureCurrentTabLoaded() end
    elseif input.KeyCode == Enum.KeyCode.R and Settings.macro_keybinds then
        KP.SetMacroRecording(not Settings.macro_record)
    elseif input.KeyCode == Enum.KeyCode.P and Settings.macro_keybinds then
        KP.SetMacroPlayback(not Settings.macro_playback)
    elseif input.KeyCode == Enum.KeyCode.E then
        pcall(ManualUpgrade)
    elseif input.KeyCode == Enum.KeyCode.Q then
        pcall(ManualSell)
    end
end))

if Settings.close_on_injection then
    MainFrame.Visible = false
    uiVisible = false
    task.delay(2, function() ShowNotify("UI Hidden", "Press K or Left Ctrl to reopen.") end)
end

darkOverlay = Instance.new("Frame", ScreenGui)
darkOverlay.Size = UDim2.new(1, 0, 1, 0)
darkOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
darkOverlay.BorderSizePixel = 0
darkOverlay.ZIndex = 1
darkOverlay.Visible = false
function KP.applyRendering(disabled)
    local ok, err = pcall(function() game:GetService("RunService"):Set3dRenderingEnabled(not disabled) end)
    if not ok then
        Settings.disable_3d_rendering = false
        KP.Report("3D rendering control unavailable", err)
        if KP.UIRefs.disable_3d_rendering then KP.UIRefs.disable_3d_rendering.refresh(false) end
        disabled = false
    end
    darkOverlay.Visible = disabled
    darkOverlay.BackgroundTransparency = disabled and 0 or 1
    return ok
end
KP.restoreRendering = function()
    pcall(function() game:GetService("RunService"):Set3dRenderingEnabled(true) end)
end
KP.applyRendering(Settings.disable_3d_rendering)

function createMobileToggle()
    for _, conn in ipairs(KP.mobileConnections or {}) do KP.Disconnect(conn) end
    KP.mobileConnections = {}
    local function MobileConnection(conn)
        table.insert(KP.mobileConnections, TrackConnection(conn))
        return conn
    end
    for _, g in pairs(ScreenGui:GetChildren()) do
        if g.Name == "MobileToggle" then g:Destroy() end
    end
    local tb = Instance.new("TextButton")
    tb.Name = "MobileToggle"
    tb.Text = "KP"
    tb.Font = Enum.Font.GothamBlack
    tb.TextSize = 16
    tb.TextColor3 = Colors.accentLight
    tb.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    tb.BackgroundTransparency = 0.4
    tb.BorderSizePixel = 0
    tb.AutoButtonColor = false
    tb.Size = UDim2.new(0, 36, 0, 36)
    tb.Position = UDim2.new(0, 8, 1, -48)
    tb.ZIndex = 90
    tb.Parent = ScreenGui
    Instance.new("UICorner", tb).CornerRadius = UDim.new(1, 0)
    local tbs = Instance.new("UIStroke", tb)
    tbs.Color = Colors.border
    tbs.Thickness = 1
    local isDragging = false
    local dragStart, btnStart, btnDragInput
    local hasMoved = false
    MobileConnection(tb.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            hasMoved = false
            dragStart = input.Position
            btnStart = tb.Position
            btnDragInput = input
        end
    end))
    MobileConnection(tb.InputEnded:Connect(function(input)
        if input == btnDragInput then
            isDragging = false
            btnDragInput = nil
            if not hasMoved then
                uiVisible = not uiVisible
                MainFrame.Visible = uiVisible
                if uiVisible then KP_EnsureCurrentTabLoaded() end
            end
        end
    end))
    MobileConnection(UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input == btnDragInput or (btnDragInput and btnDragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 5 then hasMoved = true end
            tb.Position = UDim2.new(btnStart.X.Scale, btnStart.X.Offset + delta.X, btnStart.Y.Scale, btnStart.Y.Offset + delta.Y)
        end
    end))
end
if Settings.mobile_toggle then createMobileToggle() end

task.spawn(function()
    local lastOverlay = 0
    while ScriptAlive() and ScreenGui.Parent do
        local now = tick()
        if now - lastOverlay >= 0.35 then
            local refs = _kpEnv.KP_Runtime and _kpEnv.KP_Runtime.enemyOverlayRefs
            if Settings.show_enemy_overlay or (refs and next(refs) ~= nil) then
                pcall(KP_RenderEnemyOverlay)
            end
            lastOverlay = now
        end
        task.wait(0.1)
    end
end)

BindAutoExecute()

print("[KarmaPanda:X] Custom UI loaded: " .. os.clock() - benchmark_time)
ShowNotify("KarmaPanda:X", "Loaded successfully.")
end
KP.BuildUI()
]======]
local shared = getgenv()
local fn, compileError = loadstring(source, "KarmaPanda ASTD")
assert(fn, compileError)
shared.KP_InstallSource = source
local ok, result = pcall(fn)
shared.KP_InstallSource = nil
if not ok then error(result, 0) end
