-- KarmaPanda:X integrated UI. Original gameplay runtime with the new interface.
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

local version = "4.0"
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
    for _, name in ipairs({"restoreMap", "restoreSimplifiedEnemies", "restoreDestroyedVisuals", "restoreFPS", "restoreAnonymous", "restoreNameColor", "flushMapStats", "restoreLevelSpoof", "restoreRendering", "restorePriorityHook", "cleanupAutoPlacement"}) do
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
    auto_place_zone_defaults = {false,false,false,false},
    auto_place_map_custom = {},
    level_spoofer = false,
    visual_level = "169",
    macro_check_wave = false,
    auto_place_zone_version = 2,
    auto_place_upgrade = true,
    auto_place_upgrade_level = 23,
    auto_place_ready = false,
    auto_place = false,
    auto_place_auto_zones = true,
    auto_place_show_zones = true,
    auto_place_interval = 0.35,
    auto_place_reserve = 0,
    auto_place_spacing = 4,
    auto_place_size = 48,
    auto_place_transparency = 0.75,
    auto_place_map = "",
    auto_place_zones = {},
    auto_place_units = {},
    macro_keybinds = true,
    mobile_toggle = true,
    ui_accent="B41E1E", ui_opacity=.96, ui_theme="Crimson", ui_toggle_key="K", ui_state={}
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
            if zone.entranceX~=nil or zone.entranceZ~=nil then
                zone.entranceX=number(zone.entranceX,-1000000,1000000,"entrance coordinate")
                zone.entranceZ=number(zone.entranceZ,-1000000,1000000,"entrance coordinate")
            end
            if index<=4 then clean[index]=zone end
        end
        assert(count==#list,"Sparse zones")
        return clean
    end
    for index=1,4 do
        assert(type(result.auto_place_zone_defaults[index])=="boolean","Invalid default zone toggle")
    end
    for key,custom in pairs(result.auto_place_map_custom) do
        assert(type(key)=="string" and #key<250 and type(custom)=="boolean","Invalid map override")
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
    result.ui_accent=result.ui_accent:gsub("#",""):upper()
    if not result.ui_accent:match("^%x%x%x%x%x%x$") then result.ui_accent=DefaultSettings.ui_accent end
    result.ui_opacity=math.clamp(result.ui_opacity,.6,1)
    local state=result.ui_state
    local clean={collapsed={},tabs={},team={}}
    for _,field in ipairs({"page","width","height","x","y","mobileX","mobileY"})do
        local n=tonumber(state[field]);if n and n==n and math.abs(n)<100000 then clean[field]=n end
    end
    clean.hidden=state.hidden==true
    for k,v in pairs(type(state.collapsed)=="table" and state.collapsed or {})do if type(k)=="string" and #k<250 and type(v)=="boolean" then clean.collapsed[k]=v end end
    for k,v in pairs(type(state.tabs)=="table" and state.tabs or {})do local n=tonumber(v);if n and n>=1 and n<=20 and n%1==0 then clean.tabs[tostring(k)]=n end end
    for i=1,2 do local name=type(state.team)=="table" and state.team[i];if type(name)=="string" and #name<200 then clean.team[i]=name end end
    result.ui_state=clean
    if result.ui_toggle_key~="K" and result.ui_toggle_key~="Right Control" then result.ui_toggle_key="K" end
    result.auto_place_reserve=0
    if result.auto_3x then result.auto_2x = false end
    result.destroy_mode = false
    if value.auto_place_zone_defaults == nil then
        for key in pairs(result.auto_place_maps) do result.auto_place_map_custom[key]=true end
    end
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
Settings.advanced_join_settings = nil
if not Settings.smart_join_auto_exp then
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
        ShowNotify("Auto Equip", "This macro has no saved units.")
        return
    end
    local leaderUnit = GetMacroProfileLeaderUnit(profile)

    local macroUnits = get_keys(profile["Units"])
    if #macroUnits == 0 then
        if leaderUnit ~= "" then
            table.insert(macroUnits, leaderUnit)
        else
            ShowNotify("Auto Equip", "This macro has no saved units.")
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
        ShowNotify("Auto Equip", "Couldn't load your inventory.")
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
    while not root and character == Player.Character and allowed() do
        task.wait(0.1);root = character:FindFirstChild("HumanoidRootPart")
    end
    if not root or character ~= Player.Character or not allowed() then return false end

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
    if not Settings.smart_join_auto_exp then return false end
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
        ShowNotify("Macro", "Couldn't load this profile. Recording hasn't started, and your file hasn't changed.")
        return
    end
    profile.Map = profile.Map or {}
    -- Old profiles have only a spawn transform; don't guess their map.
    if #profile.Macro == 0 then
        profile.Map.Name = get_stage()
        profile.Map.PlaceId = game.PlaceId
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
        ShowNotify("Macro", "This macro is empty or couldn't load. Check the console.")
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
            if Settings.macro_check_wave and tonumber(action.Wave) and tonumber(action.Wave)>0 then
                local pausedAt=ElapsedTime()
                run.waitingForWave=tonumber(action.Wave)
                while alive() and Settings.macro_check_wave and (tonumber(get_wave()) or 0)<run.waitingForWave do task.wait(0.05) end
                timeShift=timeShift+math.max(0,ElapsedTime()-pausedAt)
                run.waitingForWave=nil
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
            ShowNotify("Macro stopped", "Step " .. tostring(run.step) .. " failed. Check the console.")
        elseif KP.MissionEnded() then ShowNotify("Macro", "Match ended. Macro stopped.")
        else ShowNotify("Macro", "Macro finished.") end
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
                ShowNotify("Auto Battle", "Turning on Auto Battle…")
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
                ShowNotify("Auto Battle", "Couldn't confirm Auto Battle is on. Check it in-game before retrying.")
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
                if failures == 10 then ShowNotify("Auto speed", "The game hasn't switched to " .. target .. "x yet.") end
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
                    value = 1
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
function KP.IsAvatarEffect(obj)
    if not (obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or
        obj:IsA("Smoke") or obj:IsA("Sparkles") or obj:IsA("Fire")) then return false end
    local character
    for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
        if player.Character and obj:IsDescendantOf(player.Character) then character=player.Character;break end
    end
    if not character then return false end
    local node=obj.Parent
    while node and node~=character do
        -- Pets/shoulder units use nested models. Avatar accessories and body
        -- attachments are allowed, but unit rigs inside them are not.
        if node:IsA("Model") or node:FindFirstChildOfClass("Humanoid") or
            node:FindFirstChild("Owner") or node:FindFirstChild("UpgradeTag") then return false end
        node=node.Parent
    end
    return node==character
end

function KP.ApplyFPSObject(obj)
    if KP.AutoPlacement and KP.AutoPlacement.folder and obj:IsDescendantOf(KP.AutoPlacement.folder) then return end
    if KP.fpsRefs[obj] then return end
    if KP.IsAvatarEffect(obj) then return end
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
            obj.Transparency = 1
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
    local enabled = Settings.delete_enemies
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
        ShowNotify("Destroy Mode", "Nothing to hide here.")
    end
end

_kpEnv.KP_Runtime.restoreDestroyedVisuals = RestoreDestroyedVisuals

local linkport = ""
local linkport2 = ""

local function importMacro(url)
    url = tostring(url or "")
    if not url:match("^https?://") then ShowNotify("Import", "Enter a link starting with http:// or https://."); return false end
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
    if not ok then KP.Report("Macro import", imported); ShowNotify("Import error", "Couldn't import this macro. Your files haven't changed."); return false end
    if KP.recording or KP.playback then ShowNotify("Import", "Stop the macro before importing a profile."); return false end
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
    if not url:match("^https?://") then ShowNotify("Import", "Enter a link starting with http:// or https://."); return false end
    local ok, imported = pcall(function()
        return KP.ValidateSettings(game:GetService("HttpService"):JSONDecode(game:HttpGet(url)))
    end)
    if not ok then KP.Report("Settings import", imported); ShowNotify("Import error", "Couldn't import these settings. Yours haven't changed."); return false end
    local backedUp, err = pcall(function()
        if isfile(SettingsFile) then writefile(SettingsFile .. ".before-import.bak", readfile(SettingsFile)) end
    end)
    if not backedUp then KP.Report("Settings backup", err); return false end
    KP.ApplySettings(imported)
    ShowNotify("Settings imported", "Settings imported.")
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

function KP.CanAutoUpgrade(unit,level)
    local ap=KP.AutoPlacement
    if not Settings.auto_place or Settings.macro_record or Settings.macro_playback or not ap then return true end
    local folder=workspace:FindFirstChild("Unit")
    if not folder then return false end
    local reserve=ap.PriorityReserve({priority=-math.huge},folder:GetChildren())
    local ok,cost=pcall(get_upgrade_cost,unit.Name,level+1)
    return ok and type(cost)=="number" and cost==cost and cost>=0 and cost<math.huge and
        get_money()-Settings.auto_place_reserve-cost>=reserve
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
                if currentLevel < goalLevel and KP.CanAutoUpgrade(unit,currentLevel) then
                    KP_MarkMacroSuppressedUnit(unit, 2)
                    local ok = pcall(function()
                        game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer("Upgrade", unit)
                    end)
                    if not ok then
                        pcall(function()
                            local accepted,request=AddToQueue(game:GetService("ReplicatedStorage").Remotes.Server, {[1] = "Upgrade", [2] = unit})
                            if accepted then request.ShouldContinue=function()
                                return Settings.auto_upgrade and unit.Parent~=nil and KP.CanAutoUpgrade(unit,currentLevel)
                            end end
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
        local slot=type(ability_name)=="string" and tonumber(ability_name:match("^@slot:(%d+)$"))
        if slot then UseAbilityUnit(unit,"",function()if active() then KP_UseMultipleAbilityBySlot(slot,.1) end end,active)
        else UseMultipleAbilitiesUnit(unit, "", ability_name, active) end
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
        return ScriptAlive() and (Settings.auto_join_game or Settings.smart_join_auto_exp) and
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

    do
        if Settings.smart_join_auto_exp then
            local tickets
            repeat
                tickets = _kpEnv.KP_SmartJoin.WaitForTicketCount(5, function()
                    return AutoJoinActive() and Settings.smart_join_auto_exp
                end)
                if not AutoJoinActive() or not Settings.smart_join_auto_exp then return end
                if tickets == nil then task.wait(0.2) end
            until tickets ~= nil
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
                if Settings.auto_join_game and get_world() == 1 and Settings.auto_join_mode == "Adventure" then
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

    if not Settings.auto_join_game then return end
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

do
    local refs=setmetatable({}, {__mode="k"})
    function KP.restoreLevelSpoof()
        for label,state in pairs(refs) do
            if label.Parent and label.Text==state.shown then label.Text=state.original end
            refs[label]=nil
        end
    end
    function KP.ApplyLevelSpoof()
        if not Settings.level_spoofer then KP.restoreLevelSpoof();return end
        local number=tonumber(Settings.visual_level)
        if not number or number~=number or math.abs(number)==math.huge then return end
        local level=tostring(math.clamp(math.floor(number),0,999999999))
        local character=Player.Character
        if not character then return end
        local roots={character}
        local camera=workspace.CurrentCamera
        local characters=workspace:FindFirstChild("PlayerCharacters")
        for _,container in ipairs({camera or false,characters or false}) do
            if container then
                local own=container:FindFirstChild(Player.Name)
                if own and own~=character then table.insert(roots,own) end
            end
        end
        for _,root in ipairs(roots) do
            for _,label in ipairs(root:GetDescendants()) do
                if label:IsA("TextLabel") or label:IsA("TextButton") then
                    local billboard=label:FindFirstAncestorOfClass("BillboardGui")
                    if billboard then
                        local adornee=billboard.Adornee
                        local owned=adornee and (adornee==character or adornee.Parent==character or adornee==root or adornee.Parent==root)
                        if not adornee then
                            -- Reject unit nameplates nested inside the character.
                            local node=billboard.Parent;owned=true
                            while node and node~=root do
                                if node:IsA("Model") then owned=false;break end
                                node=node.Parent
                            end
                        end
                        if owned then
                            local state=refs[label]
                            local original=(state and label.Text==state.shown) and state.original or label.Text
                            local shown,n=original:gsub("([Ll][Vv]%.?%s*)%d+",function(prefix)return prefix..level end)
                            if n==0 then shown,n=original:gsub("([Ll]evel%s*:?%s*)%d+",function(prefix)return prefix..level end) end
                            if n==0 and label.Name:lower():find("level",1,true) and original:match("^%s*%d+%s*$") then shown,n=level,1 end
                            if n>0 then
                                refs[label]={original=original,shown=shown}
                                if label.Text~=shown then label.Text=shown end
                            end
                        end
                    end
                end
            end
        end
    end
    task.spawn(function()
        while ScriptAlive() do
            if Settings.level_spoofer or next(refs) then
                local ok,err=pcall(KP.ApplyLevelSpoof)
                if not ok then KP.Report("Level spoofer",err) end
            end
            task.wait(1)
        end
    end)
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
                pcall(function() obj.TextColor3 = KP.zoneColor or Color3.fromRGB(180, 30, 30) end)
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
    if is_lobby() then return "lobby:defaults" end
    local stage = game.ReplicatedStorage:FindFirstChild("STORYMODE_VALUE")
    if stage and tonumber(stage.Value) then return tostring(game.PlaceId) .. ":" .. tostring(stage.Value) end
    return tostring(game.PlaceId) .. ":session:" .. tostring(game.JobId)
end
function AP.Zones()
    Settings.auto_place_maps=Settings.auto_place_maps or {}
    Settings.auto_place_zone_defaults=Settings.auto_place_zone_defaults or {false,false,false,false}
    Settings.auto_place_map_custom=Settings.auto_place_map_custom or {}
    local defaults=Settings.auto_place_zone_defaults
    if is_lobby() then
        AP.lobbyZones=AP.lobbyZones or {}
        for index=1,4 do
            local zone=AP.lobbyZones[index] or {x=0,y=0,z=0,size=Settings.auto_place_size,placed=false,manual=false}
            zone.enabled=defaults[index];AP.lobbyZones[index]=zone
        end
        return AP.lobbyZones
    end
    local key=AP.MapKey()
    local zones=Settings.auto_place_maps[key]
    if not zones then
        zones={}
        if Settings.auto_place_map==key and #(Settings.auto_place_zones or {})>0 then
            for index,old in ipairs(Settings.auto_place_zones) do
                if index<=4 then zones[index]=DeepCopy(old);zones[index].placed=old.placed~=false;zones[index].manual=old.manual~=false end
            end
            Settings.auto_place_map_custom[key]=true
        end
        Settings.auto_place_maps[key]=zones
    end
    for index=1,4 do
        if not zones[index] then zones[index]={x=0,y=0,z=0,size=Settings.auto_place_size,enabled=defaults[index],placed=false,manual=false} end
        if not Settings.auto_place_map_custom[key] then zones[index].enabled=defaults[index] end
    end
    Settings.auto_place_map,Settings.auto_place_zones=key,zones
    return zones
end
function AP.SetEnabled(index,value)
    local zones=AP.Zones()
    if is_lobby() then Settings.auto_place_zone_defaults[index]=value
    else Settings.auto_place_map_custom[AP.MapKey()]=true end
    zones[index].enabled=value
    AP.nextScan=0;AP.Changed();Save()
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
    if text:find("speedwagon",1,true) or text:find("bulma",1,true) or text:find("farm",1,true) or text:find("idol",1,true) then return true end
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
    AP.nextScan = 0
    AP.failures, AP.blocked, AP.searchCursor, AP.zoneRetry = {}, {}, {}, {}
    AP.savingFor=0
    AP.Render()
    if AP.RefreshUI then AP.RefreshUI() end
end
function AP.RepairAutoZones(zones)
    local accepted,changed={},false
    for _,zone in ipairs(zones) do
        if zone.manual and zone.placed then table.insert(accepted,zone) end
    end
    for _,zone in ipairs(zones) do
        if zone.placed and not zone.manual then
            local conflict=false
            for _,other in ipairs(accepted) do
                local dx,dz=zone.x-other.x,zone.z-other.z
                local sameEntrance=zone.entranceX and other.entranceX and
                    (zone.entranceX-other.entranceX)^2+(zone.entranceZ-other.entranceZ)^2<16
                if sameEntrance or dx*dx+dz*dz<((zone.size+other.size)/2+1)^2 then conflict=true;break end
            end
            if conflict then
                zone.placed=false;zone.entranceX=nil;zone.entranceZ=nil;changed=true
            else table.insert(accepted,zone) end
        end
    end
    return changed
end
function AP.Render()
    if AP.folder then AP.folder:Destroy(); AP.folder = nil end
    if not ScriptAlive() or is_lobby() then return end
    local zones = AP.Zones()
    if AP.RepairAutoZones(zones) then AP.nextScan=0;Save() end
    if not Settings.auto_place_show_zones then return end
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
            part.Color = KP.zoneColor or Color3.fromRGB(180, 30, 30)
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
    if is_lobby() then ShowNotify("Auto Placement", "Join a match to place zones."); return false end
    local zones = AP.Zones()
    index=math.clamp(math.floor(index),1,4)
    Settings.auto_place_map_custom[AP.MapKey()]=true
    local size=zones[index].size
    zones[index] = {x=position.X,y=position.Y,z=position.Z,size=size,enabled=true,placed=true,manual=true}
    AP.Changed(); Save()
    return true
end
function AP.ArmZone(index)
    if is_lobby() then ShowNotify("Auto Placement", "Join a match to place zones."); return end
    if AP.pickConnection then
        KP.Disconnect(AP.pickConnection);AP.pickConnection=nil
        if AP.RefreshUI then AP.RefreshUI() end
        ShowNotify("Auto Placement", "Zone placement cancelled.");return
    end
    local mapKey=AP.MapKey()
    local inputService = game:GetService("UserInputService")
    AP.pickConnection = TrackConnection(inputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.Escape or AP.MapKey()~=mapKey then
            KP.Disconnect(AP.pickConnection);AP.pickConnection=nil
            if AP.RefreshUI then AP.RefreshUI() end
            return
        end
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
        if not hit then ShowNotify("Auto Placement", "Couldn't place the zone here. Try another spot."); return end
        KP.Disconnect(AP.pickConnection); AP.pickConnection = nil
        AP.SetZone(index, hit.Position)
        ShowNotify("Auto Placement", "Zone placed. Use Zone Size to resize it.")
    end))
    if AP.RefreshUI then AP.RefreshUI() end
    ShowNotify("Auto Placement", "Tap the map to place. Tap Cancel Zone Placement or press Esc to cancel.")
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
    -- Path folders may be nested inside the map rather than direct children.
    for _,container in ipairs(workspace:GetChildren())do
        local n=container.Name:lower()
        if n=="map"or n=="mapmodel"or n=="level"then
            for _,node in ipairs(container:GetDescendants())do
                local name=node.Name:lower()
                if names[name]or name:match("^pathway%d+$")or name:match("^path%d+$")or name:match("^route%d+$")then table.insert(roots,node)end
            end
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
    if is_lobby() then return false end
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
    local function overlaps(zone,point,other)
        local dx,dz=point.X-other.x,point.Z-other.z
        return dx*dx+dz*dz < ((zone.size+other.size)/2+1)^2
    end
    local entrances={}
    for _,lane in ipairs(routes) do
        local point=inset(lane.start,lane.afterStart)
        local duplicate=false
        for _,entry in ipairs(entrances) do
            if (lane.start.X-entry.start.X)^2+(lane.start.Z-entry.start.Z)^2<16 then duplicate=true;break end
        end
        if not duplicate then table.insert(entrances,{start=lane.start,point=point}) end
    end
    -- Recover entrance ownership for saved automatic zones made before tracking.
    for index,zone in ipairs(zones) do
        if index>1 and zone.placed and not zone.manual and not zone.entranceX then
            local nearest,distance
            for _,entry in ipairs(entrances) do
                local projected=AP.Project(entry.point,"Ground") or entry.point
                local d=(projected.X-zone.x)^2+(projected.Z-zone.z)^2
                if not distance or d<distance then nearest,distance=entry,d end
            end
            if nearest and distance<=16 then
                zone.entranceX,zone.entranceZ=nearest.start.X,nearest.start.Z;changed=true
            end
        end
    end
    if AP.RepairAutoZones(zones) then changed=true end
    local function entranceTaken(entry,candidate)
        for _,zone in ipairs(zones) do
            if zone~=candidate and zone.placed and zone.entranceX and
                (zone.entranceX-entry.start.X)^2+(zone.entranceZ-entry.start.Z)^2<16 then return true end
        end
        return false
    end
    local function taken(point, candidate)
        for _,zone in ipairs(zones) do
            if zone~=candidate and zone.placed and overlaps(candidate,point,zone) then return true end
        end
        return false
    end
    for index=1,4 do
        local zone=zones[index]
        if zone.enabled and not zone.placed and not zone.manual then
            local point,entrance
            if route then
                if index==1 then point=inset(route.finish,route.beforeEnd)
                else
                    for _,entry in ipairs(entrances) do
                        local projected=AP.Project(entry.point,"Ground") or entry.point
                        if not entranceTaken(entry,zone) and not taken(projected,zone) then point,entrance=projected,entry;break end
                    end
                end
            elseif index==1 then
                local root=Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
                if root then point=root.Position end
            end
            if point then
                if not entrance then point=AP.Project(point,"Ground") or point end
                if not taken(point,zone) then
                    zone.x,zone.y,zone.z=point.X,point.Y,point.Z
                    zone.entranceX=entrance and entrance.start.X or nil
                    zone.entranceZ=entrance and entrance.start.Z or nil
                    zone.placed=true;changed=true
                end
            end
        end
    end
    if changed then AP.status=route and "Zones ready" or "Starter zone ready";AP.Changed();Save() end
    AP.zoneAuditRevision=AP.revision
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
function AP.PriorityReserve(config,units)
    local reserve=0
    for _,name in ipairs(get_loadout_units())do
        local higher=Settings.auto_place_units[name]
        if higher and higher.enabled and higher.priority>config.priority and #AP.OrderZones(name,higher,units)>0 then
            local count=0
            for _,unit in ipairs(units)do
                local owner=unit:FindFirstChild("Owner")
                if owner and tostring(owner.Value)==Player.Name and UnitVariantNamesMatch(unit.Name,name)then count=count+1 end
            end
            if count<AP.MaxCount(name,higher)then
                local ok,cost=pcall(get_summon_cost,name)
                if not ok or type(cost)~="number" or cost~=cost or cost<0 or cost==math.huge then return math.huge end
                reserve=math.max(reserve,cost)
            end
        end
    end
    return reserve
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
        if config and config.enabled and #AP.OrderZones(name,config,units)>0 and (counts[NormalizeUnitVariantName(name)] or 0) < AP.MaxCount(name,config) then
            table.insert(ordered,{name=name,config=config})
        end
    end
    table.sort(ordered,function(a,b) if a.config.priority == b.config.priority then return a.name < b.name end; return a.config.priority > b.config.priority end)
    if #ordered == 0 then AP.status = AP.routeStatus or "Waiting"; return false end
    MacroPlacement.Refresh()
    local revision, map = AP.revision, AP.MapKey()
    local probes = 0
    for _, entry in ipairs(ordered) do
        local name, config = entry.name, entry.config
        local surface = AP.Surface(name,config)
        local ok, cost = pcall(get_summon_cost,name)
        local validCost=ok and type(cost)=="number" and cost==cost and cost>=0 and cost<math.huge
        if validCost and (counts[NormalizeUnitVariantName(name)] or 0)>0 and get_money()-Settings.auto_place_reserve<cost then
            AP.status="Can't afford another "..name..". Checking other units."
            continue
        end
        if validCost then AP.savingFor=math.max(AP.savingFor,cost) end
        if tick() < (AP.blocked[name] or 0) then AP.status="Waiting to retry "..name;continue end
        local priorityReserve=AP.PriorityReserve(config,units)
        if validCost and priorityReserve>0 and get_money()-Settings.auto_place_reserve-cost<priorityReserve then
            AP.savingFor=math.max(AP.savingFor,priorityReserve)
            AP.status="Holding cash for higher-priority placement."
            return false
        end
        if not surface then AP.status = name .. ": choose Ground, Hill or Hybrid (type unavailable)."
        elseif not ok or type(cost) ~= "number" or cost ~= cost or cost < 0 or cost == math.huge then AP.status = "Waiting for " .. name .. "'s price."
        elseif get_money()-Settings.auto_place_reserve < cost then
            AP.savingFor=cost
            AP.status = "Saving for " .. name; return false
        else
            local failures = AP.failures[name] or {}; AP.failures[name] = failures
            for _,target in ipairs(AP.OrderZones(name,config,units)) do
                local index,zone=target.index,target.zone
                if zone.enabled and zone.placed then
                    for _,probe in ipairs(AP.SearchCandidates(name,index,zone,surface))do
                        local candidateIndex,candidate=probe.index,probe.point
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
                            if not accepted then AP.status = "Waiting to send the next action."; return false end
                            request.ShouldContinue = function()
                                if not (AP.Active(context,revision) and AP.MapKey() == map and Settings.auto_place_units[name] == config and config.enabled and
                                    table.find(get_loadout_units(),name) ~= nil and get_money()-Settings.auto_place_reserve >= cost) then return false end
                                local current, ownCount = folder:GetChildren(), 0
                                local reserved=AP.PriorityReserve(config,current)
                                if reserved>0 and get_money()-Settings.auto_place_reserve-cost<reserved then return false end
                                for _, unit in ipairs(current) do
                                    local owner=unit:FindFirstChild("Owner")
                                    if owner and tostring(owner.Value)==Player.Name and UnitVariantNamesMatch(unit.Name,name) then ownCount=ownCount+1 end
                                end
                                for _,higherName in ipairs(get_loadout_units()) do
                                    local higher=Settings.auto_place_units[higherName]
                                    if higher and higher.enabled and higher.priority>config.priority and tick()>=(AP.blocked[higherName] or 0) and #AP.OrderZones(higherName,higher,current)>0 then
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
                                        AP.savingFor=AP.PriorityReserve(config,folder:GetChildren())
                                        AP.status = "Placed " .. name; return true
                                    end
                                end
                                task.wait(0.1)
                            until not AP.Active(context,revision) or tick()>=deadline
                            if not AP.Active(context,revision) or AP.MapKey()~=map then return false end
                            failures[key] = tick()+8
                            AP.searchCursor[name][index]=probe.nextIndex
                            AP.zoneRetry=AP.zoneRetry or {};AP.zoneRetry[name]=AP.zoneRetry[name]or {};AP.zoneRetry[name][index]=tick()+8
                            AP.blocked[name]=tick()+math.max(1,Settings.auto_place_interval)
                            AP.status = "Trying another spot in the zone."
                            return false
                        end
                        if probes % 16 == 0 then task.wait() end
                    end
                end
            end
            AP.blocked[name] = tick()+math.max(.25,Settings.auto_place_interval)
            AP.status = "No valid spot found for " .. name .. ". Checking other units."
            -- Keep cash reserved while this eligible unit searches for another spot.
        end
        continue
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
    table.sort(selected,function(a,b)
        local retry=AP.zoneRetry and AP.zoneRetry[name]or {}
        local blockedA=tick()<(retry[a.index]or 0);local blockedB=tick()<(retry[b.index]or 0)
        if blockedA~=blockedB then return not blockedA end
        if a.count==b.count then return a.index<b.index end
        return a.count<b.count
    end)
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
-- BEGIN PLACEMENT REPAIR 20260924
function AP.DetectRoutes()
    local function clean(name)return tostring(name):lower():gsub("[%s_%-]","")end
    local function pathName(name)
        name=clean(name)
        return name:match("^paths?%d*$")or name:match("^pathways?%d*$")or name:match("^waypoints?%d*$")or name:match("^nodes?%d*$")or name:match("^routes?%d*$")or name:match("^lanes?%d*$")
    end
    local function indexOf(name)
        local n=clean(name)
        return tonumber(n)or tonumber(n:match("^waypoint(%d+)$"))or tonumber(n:match("^node(%d+)$"))or tonumber(n:match("^point(%d+)$"))or tonumber(n:match("^checkpoint(%d+)$"))
    end
    local function endpoint(name)
        local n=clean(name)
        if n=="start"or n=="startpoint"or n=="entrance"or n=="spawn"or n=="enemystart"then return "start"end
        if n=="end"or n=="endpoint"or n=="finish"or n=="goal"then return "finish"end
    end
    local function position(node)
        if node:IsA("BasePart")then return node.Position end
        if node:IsA("Attachment")then return node.WorldPosition end
        if node:IsA("Vector3Value")then return node.Value end
        if node:IsA("CFrameValue")then return node.Value.Position end
        if node:IsA("Model")then
            for _,child in ipairs(node:GetChildren())do if indexOf(child.Name)or endpoint(child.Name)then return nil end end
            local part=node.PrimaryPart or node:FindFirstChildWhichIsA("BasePart",true)
            if part then return part.Position end
        end
    end
    local roots,queue,seen={},{workspace},{}
    local blocked={enemies=true,unit=true,units=true,playercharacters=true,camera=true,terrain=true,placeable=true,kpplacementzones=true}
    local head=1
    while head<=#queue and head<=4096 do
        local node=queue[head];head=head+1
        if not seen[node]then
            seen[node]=true
            if pathName(node.Name)then table.insert(roots,node)
            elseif not blocked[clean(node.Name)]and node~=Player.Character then
                for _,child in ipairs(node:GetChildren())do
                    if child:IsA("Folder")or child:IsA("Model")or pathName(child.Name)then queue[#queue+1]=child end
                end
            end
        end
        if head%128==0 then task.wait()end
    end
    local groups={};queue=table.clone(roots);seen={};head=1
    while head<=#queue and head<=8192 do
        local node=queue[head];head=head+1
        if not seen[node]then
            seen[node]=true
            local index,kind=indexOf(node.Name),endpoint(node.Name)
            local point=(index or kind)and position(node)
            if point then
                local group=groups[node.Parent]or {nodes={}};groups[node.Parent]=group
                if kind then group[kind]=point else group.nodes[#group.nodes+1]={index=index,point=point}end
            end
            -- A numbered model represents one waypoint, not another lane.
            if not(point and node:IsA("Model"))then
                for _,child in ipairs(node:GetChildren())do queue[#queue+1]=child end
            end
        end
        if head%128==0 then task.wait()end
    end
    local routes={}
    for parent,group in pairs(groups)do
        table.sort(group.nodes,function(a,b)return a.index<b.index end)
        local nodes=group.nodes
        local start=group.start or (#nodes>=2 and nodes[1].point)
        local finish=group.finish or (#nodes>=2 and nodes[#nodes].point)
        -- Explicit endpoints establish direction even when node numbers run backwards.
        if #nodes>=2 and (group.start or group.finish)then
            local target=group.start or group.finish
            local first=(nodes[1].point-target).Magnitude;local last=(nodes[#nodes].point-target).Magnitude
            if group.start and last<first or not group.start and first<last then
                local reversed={};for i=#nodes,1,-1 do reversed[#reversed+1]=nodes[i]end;nodes=reversed
                start=group.start or nodes[1].point;finish=group.finish or nodes[#nodes].point
            end
        end
        if start and finish and (start-finish).Magnitude>.1 then
            routes[#routes+1]={start=start,finish=finish,afterStart=#nodes>=2 and nodes[2].point or finish,beforeEnd=#nodes>=2 and nodes[#nodes-1].point or start}
        end
    end
    table.sort(routes,function(a,b)
        if a.finish.X~=b.finish.X then return a.finish.X<b.finish.X end
        if a.finish.Z~=b.finish.Z then return a.finish.Z<b.finish.Z end
        if a.start.X~=b.start.X then return a.start.X<b.start.X end
        return a.start.Z<b.start.Z
    end)
    AP.routeStatus=#routes==0 and (#roots==0 and "Waiting for map path folders."or "Map paths found; waiting for entrance waypoints.")or nil
    return routes
end

local zonesBeforeRepair=AP.Zones
function AP.Zones()
    local key=AP.MapKey()
    local saved=Settings.auto_place_maps and Settings.auto_place_maps["lobby:defaults"]
    local existed=Settings.auto_place_maps and Settings.auto_place_maps[key]
    if is_lobby()and saved then AP.lobbyZones=saved end
    local zones=zonesBeforeRepair()
    if is_lobby()then Settings.auto_place_maps["lobby:defaults"]=zones
    elseif not existed and saved then
        for index,zone in ipairs(zones)do if not zone.manual and saved[index]then zone.size=saved[index].size end end
    end
    return zones
end
function AP.RepairAutoZones(zones)
    local occupied,changed={},false
    for _,zone in ipairs(zones)do if zone.enabled and zone.manual and zone.placed then table.insert(occupied,zone)end end
    for _,zone in ipairs(zones)do
        if zone.enabled and zone.placed and not zone.manual then
            local duplicate=false
            for _,other in ipairs(occupied)do
                local sameEntrance=zone.entranceX and other.entranceX and (zone.entranceX-other.entranceX)^2+(zone.entranceZ-other.entranceZ)^2<16
                if sameEntrance or (zone.x-other.x)^2+(zone.z-other.z)^2<16 then duplicate=true;break end
            end
            if duplicate then zone.placed=false;zone.entranceX=nil;zone.entranceZ=nil;changed=true
            else table.insert(occupied,zone)end
        end
    end
    return changed
end
function AP.AutoZones()
    if is_lobby()then return false end
    if AP.detecting and coroutine.status(AP.detecting)~="dead"then return false end
    AP.detecting=coroutine.running()
    local revision,map=AP.revision,AP.MapKey()
    local ok,routes=pcall(AP.DetectRoutes);AP.detecting=false
    if not ok then KP.Report("Lane detection",routes);return false end
    if not ScriptAlive()or revision~=AP.revision or map~=AP.MapKey()then return false end
    if #routes==0 then AP.status="Waiting for map entrances.";return false end
    MacroPlacement.Refresh()
    local function inset(point,toward)
        local d=Vector3.new(toward.X-point.X,0,toward.Z-point.Z)
        return d.Magnitude>.01 and point+d*(math.min(6,d.Magnitude/2)/d.Magnitude)or point
    end
    local function distance(a,b)return (a.X-b.X)^2+(a.Z-b.Z)^2 end
    local finish=inset(routes[1].finish,routes[1].beforeEnd)
    local entrances={}
    for _,route in ipairs(routes)do
        local duplicate=false
        for _,entry in ipairs(entrances)do if distance(entry.start,route.start)<16 then duplicate=true;break end end
        if not duplicate then table.insert(entrances,{start=route.start,point=inset(route.start,route.afterStart)})end
    end
    table.sort(entrances,function(a,b)
        local da,db=distance(a.start,finish),distance(b.start,finish)
        if da~=db then return da<db end
        if a.start.X~=b.start.X then return a.start.X<b.start.X end
        return a.start.Z<b.start.Z
    end)
    local zones=AP.Zones();local occupied,used={},{}
    for _,zone in ipairs(zones)do
        if zone.enabled and zone.manual and zone.placed then table.insert(occupied,Vector3.new(zone.x,zone.y,zone.z))end
    end
    local function free(point)
        for _,other in ipairs(occupied)do if distance(point,other)<16 then return false end end
        return true
    end
    local changed=false
    for index,zone in ipairs(zones)do
        if not zone.manual then
            local point,entry
            if zone.enabled then
                if index==1 then
                    local projected=AP.Project(finish,"Hybrid")or finish
                    if free(projected)then point=projected end
                else
                    for i,candidate in ipairs(entrances)do
                        local projected=AP.Project(candidate.point,"Hybrid")or candidate.point
                        if not used[i]and free(projected)then point,entry=projected,candidate;used[i]=true;break end
                    end
                end
            end
            local placed=point~=nil
            if zone.placed~=placed or placed and (math.abs(zone.x-point.X)>.01 or math.abs(zone.y-point.Y)>.01 or math.abs(zone.z-point.Z)>.01)then changed=true end
            zone.placed=placed
            zone.entranceX=entry and entry.start.X or nil;zone.entranceZ=entry and entry.start.Z or nil
            if placed then zone.x,zone.y,zone.z=point.X,point.Y,point.Z;table.insert(occupied,point)end
        end
    end
    if changed then AP.status="Zones ready";AP.Changed();Save()end
    AP.zoneAuditRevision=AP.revision
    return changed
end

function AP.Surface(name,config)
    local ok,stats=pcall(get_stat,name)
    if ok and type(stats)=="table"then
        if stats.Hybrid==true then return "Hybrid"end
        for key,value in pairs(stats)do
            local k=tostring(key):lower()
            if k:find("place",1,true)or k=="type"or k=="unittype"then
                local v=tostring(value):lower()
                if v=="hybrid"then return "Hybrid"end
                if v=="ground"or v=="base"then return "Ground"end
                if v=="hill"or v=="air"then return "Hill"end
            end
        end
        if stats.Hill==true or stats.Air==true or stats.HillUnit==true then return "Hill"end
    end
    -- Unknown placement type must search both surfaces; the server validates it.
    return "Hybrid"
end
function AP.PlacementParts(surface)
    local root=workspace:FindFirstChild("Placeable")
    if AP.partsRoot==root and AP.partsCache and tick()<(AP.partsExpires or 0)and AP.partsCache[surface]then
        local valid=true
        for _,part in ipairs(AP.partsCache[surface])do if not part.Parent then valid=false;break end end
        if valid then return AP.partsCache[surface]end
        AP.partsExpires=0
    end
    if AP.partsRoot~=root or tick()>=(AP.partsExpires or 0)then AP.partsRoot=root;AP.partsCache={};AP.partsExpires=tick()+1 end
    local result,seen={},{}
    local function add(part,kind)
        if part and part.Parent and not seen[part]and (surface=="Hybrid"or surface==kind)then seen[part]=true;table.insert(result,part)end
    end
    for _,part in ipairs(MacroPlacement.base)do add(part,"Ground")end
    for _,part in ipairs(MacroPlacement.hill)do add(part,"Hill")end
    if root then
        local all=root:GetDescendants();if root:IsA("BasePart")then table.insert(all,root)end
        for _,part in ipairs(all)do if part:IsA("BasePart")then
            local node,kind=part,"Ground"
            while node and node~=root do
                local name=node.Name:lower()
                if name:find("hill",1,true)or name:find("air",1,true)then kind="Hill";break end
                node=node.Parent
            end
            add(part,kind)
        end end
    end
    AP.partsCache=AP.partsCache or {};AP.partsCache[surface]=result
    return result
end
function AP.Candidates(zone,surface)
    local points,seen={},{}
    local center=Vector3.new(zone.x,zone.y,zone.z)
    local function add(p)
        if not AP.Contains(zone,p)then return end
        local key=math.floor(p.X*4)..":"..math.floor(p.Y*4)..":"..math.floor(p.Z*4)
        if not seen[key]then seen[key]=true;table.insert(points,p)end
    end
    -- Probe actual surface footprints first, including small raised platforms.
    for _,part in ipairs(AP.PlacementParts(surface or "Hybrid"))do
        local localPoint=part.CFrame:PointToObjectSpace(center)
        local x=math.max(0,part.Size.X/2-.4);local z=math.max(0,part.Size.Z/2-.4)
        local nearX,nearZ=math.clamp(localPoint.X,-x,x),math.clamp(localPoint.Z,-z,z)
        for _,p in ipairs({{nearX,nearZ},{0,0},{-x,-z},{-x,z},{x,-z},{x,z}})do
            add(part.CFrame:PointToWorldSpace(Vector3.new(p[1],part.Size.Y/2,p[2])))
        end
    end
    add(center)
    local step=math.max(2,math.min(4,Settings.auto_place_spacing))
    for ring=1,math.ceil(zone.size/2/step)do
        for x=-ring,ring do for z=-ring,ring do
            if math.abs(x)==ring or math.abs(z)==ring then add(center+Vector3.new(x*step,0,z*step))end
        end end
    end
    return points
end
function AP.Project(point,surface)
    local parts=AP.PlacementParts(surface)
    local function restricted(p)
        for _,part in ipairs(MacroPlacement.restrictions or {})do
            if part.Parent then
                local localPoint=part.CFrame:PointToObjectSpace(p)
                if math.abs(localPoint.Y)<=part.Size.Y/2+2 and MacroPlacement.PointInPartXZ(part,p,.25)then return true end
            end
        end
        return false
    end
    if #parts==0 and workspace:FindFirstChild("Placeable")then return nil end
    local params=RaycastParams.new()
    params.FilterType=#parts>0 and Enum.RaycastFilterType.Include or Enum.RaycastFilterType.Exclude
    local ignore={}
    for _,obj in pairs({workspace:FindFirstChild("Enemies"),workspace:FindFirstChild("Unit"),Player.Character,AP.folder})do if obj then table.insert(ignore,obj)end end
    params.FilterDescendantsInstances=#parts>0 and parts or ignore
    local hit=workspace:Raycast(point+Vector3.new(0,80,0),Vector3.new(0,-160,0),params)
    if hit and hit.Normal.Y>.65 and not restricted(hit.Position)then return hit.Position end
    local best,distance
    for _,part in ipairs(parts)do
        local p=part.CFrame:PointToObjectSpace(point)
        if math.abs(p.X)<=part.Size.X/2 and math.abs(p.Z)<=part.Size.Z/2 then
            local top=part.CFrame:PointToWorldSpace(Vector3.new(p.X,part.Size.Y/2,p.Z))
            local d=math.abs(top.Y-point.Y)
            if d<=80 and not restricted(top)and (not distance or d<distance)then best,distance=top,d end
        end
    end
    return best
end

function AP.SearchCandidates(name,index,zone,surface)
    local points=AP.Candidates(zone,surface)
    AP.searchCursor=AP.searchCursor or {};AP.searchCursor[name]=AP.searchCursor[name]or {}
    local start=math.clamp(AP.searchCursor[name][index]or 1,1,math.max(1,#points))
    local result={}
    for offset=0,#points-1 do
        local i=(start+offset-1)%#points+1
        result[#result+1]={index=i,point=points[i],nextIndex=i%#points+1}
    end
    return result
end

-- Discover late-loading lanes and rebuild previews even when placement is off.
task.spawn(function()
    while ScriptAlive()do
        if not is_lobby()and (Settings.auto_place_show_zones or Settings.auto_place)then
            local map=AP.MapKey()
            if map~=AP.previewMap then
                AP.previewMap=map;AP.previewScan=0
                AP.partsCache=nil;AP.partsExpires=0
                AP.Changed()
            end
            if tick()>=(AP.previewScan or 0)then
                AP.previewScan=tick()+2
                if AP.NeedsZones()or AP.zoneAuditRevision~=AP.revision or AP.routeScanMap~=map then AP.AutoZones();AP.routeScanMap=map end
                local parent=workspace.CurrentCamera or workspace
                if Settings.auto_place_show_zones and (not AP.folder or AP.folder.Parent~=parent)then AP.Render()end
            end
        end
        task.wait(.5)
    end
end)

-- END PLACEMENT REPAIR 20260924
function AP.Run()
    local context = KP.contexts[coroutine.running()]
    local map
    while KP.ContextAlive(context) and Settings.auto_place and not is_lobby() and not KP.MissionEnded() do
        if map ~= AP.MapKey() then map = AP.MapKey(); AP.Changed() end
        AP.Setup()
        if Settings.macro_record or Settings.macro_playback then AP.status = "Paused while macro recording/playback is enabled."
        else
            if (AP.NeedsZones() or AP.zoneAuditRevision~=AP.revision) and tick()>=AP.nextScan then AP.nextScan=tick()+10; AP.AutoZones() end
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
do
    local originalJoin=AutoJoinGame
    AutoJoinGame=function(...)
        local run={};KP.joinRun=run
        local ok,err=pcall(originalJoin,...)
        if KP.joinRun==run then KP.joinRun=nil end
        if not ok then error(err,0) end
    end
end
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
    if (Settings.auto_join_game or Settings.smart_join_auto_exp) and is_lobby() then task.spawn(AutoJoinGame) end
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
        if Settings.auto_join_game or Settings.smart_join_auto_exp then task.spawn(AutoJoinGame) end
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

if get_world() == -2 and (Settings.auto_join_game or Settings.smart_join_auto_exp) then task.spawn(AutoJoinGame) end

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


-- Runs inside the original runtime's lexical scope; no second gameplay runtime.
local Bridge={items={},actions={},fields={},pages=nil}
KP.Interface=Bridge
local AP=KP.AutoPlacement
local function copy(value) return type(value)=="table" and DeepCopy(value) or value end
local function inform(message) ShowNotify("KarmaPanda:X",message) end
local function changed() if Bridge.refresh then Bridge.refresh() end end
function Bridge.SaveUI(field,value)
    Settings.ui_state=Settings.ui_state or {}
    if type(field)=="table" then for key,v in pairs(field)do Settings.ui_state[key]=copy(v)end
    else Settings.ui_state[field]=copy(value) end
    local ok,err=pcall(function()writefile(SettingsFile,game:GetService("HttpService"):JSONEncode(Settings))end)
    if not ok then KP.Report("Settings save failed",err)end
end
local nameColors=setmetatable({},{__mode="k"})
function Bridge.RefreshNameColor()
    if KP.nameTintStopped or not KP.zoneColor then return end
    local function tint(obj)
        if not obj:IsA("TextLabel") then return end
        local text=obj.Text
        if text~=Player.Name and text~=Player.DisplayName and not (Settings.anonymous_mode and text==Settings.anonymous_mode_name) then return end
        if not nameColors[obj] then
            nameColors[obj]=(KP.anonRefs and KP.anonRefs[obj] and KP.anonRefs[obj].TextColor3) or obj.TextColor3
            TrackConnection(obj:GetPropertyChangedSignal("TextColor3"):Connect(function()
                if KP.alive and not KP.nameTintStopped and obj.Parent and obj.TextColor3~=KP.zoneColor then obj.TextColor3=KP.zoneColor end
            end))
        end
        obj.TextColor3=KP.zoneColor
    end
    local function visit(root)if root then tint(root);for _,obj in ipairs(root:GetDescendants())do tint(obj)end end end
    visit(Player.Character)
    for _,container in pairs({workspace.CurrentCamera,workspace:FindFirstChild("PlayerCharacters")})do
        if container then visit(container:FindFirstChild(Player.Name));visit(container:FindFirstChild(Player.DisplayName)) end
    end
    for obj in pairs(nameColors)do if obj.Parent then obj.TextColor3=KP.zoneColor end end
end
KP.restoreNameColor=function()
    KP.nameTintStopped=true
    for obj,color in pairs(nameColors)do if obj.Parent then obj.TextColor3=color end end
end

function Bridge.Configure(pages)
    Bridge.pages=pages
    table.insert(pages[3].tabs[1].cards[1].items,3,{type="note",label="Idle",macroStatus=true})
    table.insert(pages[2].tabs[1].cards[1].items,1,{type="note",label="Stopped",placementStatus=true})
    table.insert(pages[6].tabs[1].cards[1].items,3,{type="note",label="",buffInfo=true})
    for _,page in ipairs(pages) do for _,tab in ipairs(page.tabs) do for _,card in ipairs(tab.cards) do
        local zone=page.name=="Automation" and tonumber(card.title:match("^Zone (%d+)$"))
        for _,item in ipairs(card.items) do
            item.scope=page.name.."/"..tab.name.."/"..card.title
            item.zone=zone
            item.zoneAction=zone and item.type=="button"
            local key=Bridge.keys[item.label]
            if item.label=="Auto Upgrade" then key=card.title=="Placement Tuning" and "auto_place_upgrade" or "auto_upgrade" end
            if item.label=="Auto Skip Wave" then key=page.name=="Macro" and "macro_autoskipwave" or "auto_skip_wave_spam" end
            if item.label=="Mode" and page.name=="Ability" then key=nil end
            if item.id=="smartMulti" then key="auto_target_ability_multi" end
            if item.visibleWhenId=="smartMulti" then key="auto_target_ability_multi_slot" end
            if item.teamOptions then item.teamOptions=nil;item.liveTeam=true end
            if item.type=="button" or item.type=="note" or item.zone then key=nil end
            item.settingKey=key
            if key=="auto_story_target" then local ok,count=pcall(get_number_missions);item.max=ok and count or 204 end
            if key=="fps_limit" then item.max=1000;item.step=1 end
            if key=="auto_upgrade_money" then item.step=50 end
            if key=="smart_join_auto_exp" then item.desc="If you're ever in lobby with tickets, you'll teleport to tickets instead of ur map" end
            if key=="auto_upgrade_targets" then item.emptyLabel="All Units" end
            if key=="ui_scale" or key=="ui_opacity" then item.factor=100 end
            if key=="auto_join_infinite_level" then item.mapTable=InfiniteMapTable end
            if key=="auto_join_adventure_level" then item.mapTable=AdventureMapTable end
            if item.label=="Your Units" then item.liveTeam=nil;item.buffList=true end
            if item.label=="Profile" then item.profiles=true end
            if card.title=="Add Ability Unit" or item.type=="input" and not key then Bridge.fields[item.label]=item end
            if item.type=="note" and card.title=="Macro Library" and not item.macroStatus then item.profileInfo=true end
            Bridge.items[#Bridge.items+1]=item
        end
    end end end
    AP.RefreshTeam()
    for _,item in ipairs(Bridge.items) do Bridge.Read(item) end
end

function Bridge.Read(item)
    if item.unitName then
        local config=Settings.auto_place_units[item.unitName]
        if config then
            local field=({["Place Unit"]="enabled",["Placement Zones"]="zones",["Unit Priority"]="priority",["Max Units"]="limit",["Upgrade Cap"]="upgradeCap"})[item.label]
            item.value=copy(config[field])
            if field=="zones" then item.value={};for _,n in ipairs(config.zones or {}) do item.value[#item.value+1]=tostring(n) end end
            if field=="limit" then item.max=AP.MaxAllowed(item.unitName);item.value=AP.MaxCount(item.unitName,config) end
        end
    elseif item.zone then
        local zone=AP.Zones()[item.zone]
        if zone then
            if item.zoneAction then item.label=AP.pickConnection and "Cancel Zone Placement" or "Place / Move Zone"
            elseif item.label=="Zone Enabled" then item.value=zone.enabled
            elseif item.label=="Position" then item.value=zone.manual and "Manual" or "Automatic"
            elseif item.label=="Zone Size" then item.value=zone.size
            elseif item.label=="Transparency" then item.value=Settings.auto_place_transparency*100 end
        end
    elseif item.settingKey then
        local value=Settings[item.settingKey]
        if value~=nil then
            if item.factor then value=value*item.factor end
            if item.settingKey=="auto_target_ability_multi_slot" then value="Slot "..tostring(value) end
            if item.mapTable then
                item.options={};for _,name in pairs(item.mapTable) do table.insert(item.options,name) end;table.sort(item.options)
                value=item.mapTable[tostring(value)] or item.options[1]
            end
            if item.type=="slider" then value=tonumber(value) or item.min end
            item.value=copy(value)
        end
    end
    if item.profiles then item.options=table.clone(MacroProfileList) end
    if item.liveTeam then
        item.options=get_loadout_units();table.sort(item.options)
        if item.settingKey=="auto_upgrade_targets" and #item.options>0 then
            local kept={}
            for _,name in ipairs(item.value or {})do if table.find(item.options,name)then kept[#kept+1]=name end end
            if #kept~=#(item.value or {})then item.value=kept;Settings.auto_upgrade_targets=copy(kept);Save()end
        end
    end
    if item.buffList then item.options=get_keys(Settings.auto_buff_units or {});table.sort(item.options) end
    if (item.liveTeam or item.buffList) and item.type=="select" then
        if #item.options==0 then item.options={"None"} end
        if not table.find(item.options,item.value) then
            if item.settingKey and type(item.value)=="string" and item.value~="" and item.value~="None" then
                table.insert(item.options,1,item.value)
            else
                item.value=item.options[1]
                if item.settingKey and item.value~="None" then Settings[item.settingKey]=item.value;Save() end
            end
        end
    end
    if item.profileInfo then
        local p=GetActiveMacroProfile()
        item.label=p and ("Map: "..tostring(p.Map and p.Map.Name or "Not Recorded").." · "..tostring(#p.Macro).." Steps\nLeader: "..tostring(GetMacroProfileLeaderUnit(p) or "None").." · Units: "..table.concat(get_keys(p.Units or {}),", ")) or "No Profile Loaded"
    end
    if item.buffInfo then
        local selected;for _,v in ipairs(Bridge.items)do if v.buffList then selected=v.value;break end end
        local config=selected and Settings.auto_buff_units[selected]
        if config then
            local checks=table.concat(config.Checks or {},", ")
            local ability=config["Ability Type"] or "Normal"
            if config["Ability Name"] then ability=ability.." · "..config["Ability Name"]:gsub("@slot:","Slot ") end
            item.label=tostring(config.Mode).." · "..tostring(config.Time).."s Cooldown\nChecks: "..(checks~="" and checks or "None").." · "..ability
        else item.label="No Ability Units Added" end
    end
    if item.placementStatus then item.label=Settings.auto_place and AP.status or "Stopped" end
    if item.macroStatus then
        local profile=(KP.playback and KP.playback.profile) or GetActiveMacroProfile()
        local step=profile and profile.Macro and profile.Macro[CurrentStep]
        item.label=(KP.recording and "Recording" or KP.playback and "Playback" or "Idle").." · Step "..tostring(CurrentStep or 0).." / "..tostring(profile and #profile.Macro or 0)
        if step then
            local params={};for k,v in pairs(step.Parameter or {})do params[#params+1]=tostring(k)..": "..tostring(v)end;table.sort(params)
            local target=step.Target and tostring(step.Target.Name or "—") or "—"
            if step.Target and step.Target.Index~=nil then target=target.."["..tostring(step.Target.Index).."]" end
            item.label=item.label.."\n"..tostring(step.Remote and step.Remote[1] or "—").." · "..target
                ..string.format("\nRecorded: %.1fs · Wave %s · Enemies %s",tonumber(step.Time) or 0,tostring(step.Wave or "—"),tostring(step.EnemyCount or "—"))
            if #params>0 then item.label=item.label.."\n"..table.concat(params,"; ") end
        end
        item.label=item.label..string.format("\nNow: %.1fs · Wave %s · Enemies %s",ElapsedTime(),tostring(get_wave()),tostring(get_enemy_count()))
    end
    return item.value
end

function Bridge.Write(item,value)
    if item.unitName then
        local config=Settings.auto_place_units[item.unitName];if not config then return end
        local field=({["Place Unit"]="enabled",["Placement Zones"]="zones",["Unit Priority"]="priority",["Max Units"]="limit",["Upgrade Cap"]="upgradeCap"})[item.label]
        if field=="zones" then local nums={};for _,n in ipairs(value) do nums[#nums+1]=tonumber(n) end;value=nums end
        if field=="limit" then value=math.min(value,AP.MaxAllowed(item.unitName)) end
        config[field]=copy(value);AP.Changed();Save();changed();return
    end
    if item.zone then
        local zone=AP.Zones()[item.zone];if not zone then return end
        if item.label=="Zone Enabled" then AP.SetEnabled(item.zone,value)
        elseif item.label=="Zone Size" then zone.size=value;if not is_lobby() then Settings.auto_place_map_custom[AP.MapKey()]=true end;AP.Changed()
        elseif item.label=="Transparency" then Settings.auto_place_transparency=value/100;AP.Render()
        elseif item.label=="Position" then
            if value=="Manual" then AP.ArmZone(item.zone)
            else zone.manual=false;zone.placed=false;AP.Changed();AP.AutoZones();AP.Render() end
        end
        Save();changed();return
    end
    local key=item.settingKey
    if not key then item.value=value;return end
    if item.factor then value=value/item.factor end
    if key=="ui_accent" then value=tostring(value):gsub("#",""):upper();assert(value:match("^%x%x%x%x%x%x$"),"Invalid accent") end
    if item.mapTable then for id,name in pairs(item.mapTable) do if name==value then value=id;break end end end
    if key=="auto_target_ability_multi_slot" then value=tonumber(tostring(value):match("%d+")) or 1 end
    if key=="macro_record" then KP.SetMacroRecording(value);changed();return end
    if key=="macro_playback" then KP.SetMacroPlayback(value);changed();return end
    if key=="macro_profile" then
        if KP.recording or KP.playback then inform("Stop the macro before switching profiles.");changed();return end
        FocusMacroProfile(value)
    end
    Settings[key]=copy(value)
    if value==false then KP.StopFeature(key) end
    if key=="auto_2x" or key=="auto_3x" then
        if value then Settings[key=="auto_2x" and "auto_3x" or "auto_2x"]=false end
        if not is_lobby() then task.spawn(AutoChangeSpeed) end
    elseif key=="auto_place" then AP.Setup();AP.Changed()
    elseif key=="auto_place_show_zones" then AP.Render()
    elseif key=="auto_place_spacing" then AP.Changed()
    elseif key=="fps_boost" then if value then task.spawn(FpsBoost) elseif KP.restoreFPS then KP.restoreFPS() end
    elseif key=="delete_enemies" then ApplySimplifyEnemies()
    elseif key=="delete_map" then
        if value and is_lobby() then Settings[key]=false;inform("Hide Map is unavailable in the lobby.")
        elseif value then task.spawn(DeleteMap) else RestoreMap() end
    elseif key=="disable_3d_rendering" then KP.applyRendering(value)
    elseif key=="fps_limit" then ApplyFPSLimit(value,true)
    elseif key=="level_spoofer" or key=="visual_level" then KP.ApplyLevelSpoof()
    elseif key=="anonymous_mode" or key=="anonymous_mode_name" then
        if Settings.anonymous_mode then AnonMode() elseif KP.restoreAnonymous then KP.restoreAnonymous() end
    elseif key=="auto_execute" then
        if value then
            BindAutoExecute()
            inform(GetQueueOnTeleport() and "Will re-execute after the next teleport." or "Executor does not support queue_on_teleport.")
        else _kpEnv.KP_AutoExecuteQueuedJobId=nil end
    elseif key=="auto_join_game" or key=="smart_join_auto_exp" then
        if key=="smart_join_auto_exp" and not value then Settings.smart_join_exp_active=false;Settings.smart_join_exp_tickets_remaining=0 end
        KP.autoJoinToken=(KP.autoJoinToken or 0)+1
        if is_lobby() and (Settings.auto_join_game or Settings.smart_join_auto_exp) then task.spawn(AutoJoinGame) end
    end
    local start=KP.startFeatures[key]
    if start and value then
        local lobbyOnly=key=="auto_evolve_exp" or key=="auto_join_tower"
        if key=="auto_skip_gui" or lobbyOnly==is_lobby() then task.spawn(start) end
    end
    Save();changed()
end

function Bridge.Action(item)
    if item.zoneAction or item.zone and item.label=="Place / Move Zone" then AP.ArmZone(item.zone);return true end
    local action=Bridge.actions[item.label]
    if not action then return false end
    action();changed();return true
end
function Bridge.DefaultZones()
    local list={};for i=1,4 do if Settings.auto_place_zone_defaults[i] then list[#list+1]=tostring(i) end end
    return #list>0 and table.concat(list," - ") or "None"
end
function Bridge.Theme(color,hex)
    KP.zoneColor=color;Settings.ui_accent=hex;AP.Render()
    if Settings.anonymous_mode then AnonMode() end
    Bridge.RefreshNameColor();Save()
end
function Bridge.Initial() return Settings end
function Bridge.Status() return KP.recording and "Recording" or KP.playback and "Playback" or "Idle" end
function Bridge.Key(input)
    if input.KeyCode==Enum.KeyCode.E then pcall(ManualUpgrade)
    elseif input.KeyCode==Enum.KeyCode.Q then pcall(ManualSell) end
    if Settings.macro_keybinds then
        if input.KeyCode==Enum.KeyCode.R then KP.SetMacroRecording(not Settings.macro_record);changed()
        elseif input.KeyCode==Enum.KeyCode.P then KP.SetMacroPlayback(not Settings.macro_playback);changed() end
    end
end
Bridge.actions["Refresh Current Team"]=function()AP.RefreshTeam()end
Bridge.actions["Play Macro"]=function()KP.SetMacroPlayback(true)end
Bridge.actions["Stop Macro"]=function()KP.SetMacroPlayback(false);KP.SetMacroRecording(false)end
Bridge.actions["Previous Step"]=function()KP.SeekMacro(-1)end
Bridge.actions["Next Step"]=function()KP.SeekMacro(1)end
Bridge.actions["Reset Playback"]=function()KP.SeekMacro(0)end
Bridge.actions["Equip Macro Units"]=function()task.spawn(EquipMacroUnits)end
Bridge.actions["Reset Settings To Default"]=function()KP.ApplySettings(DeepCopy(DefaultSettings));inform("Settings reset.")end
Bridge.actions["Lobby"]=function()game:GetService("TeleportService"):Teleport(4996049426,Player)end
for _,entry in ipairs({{"World 1",1},{"World 2",2}}) do Bridge.actions[entry[1]]=function()
    if get_world()==entry[2] then inform("Already in "..entry[1]..".");return end
    local root=Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not root or not is_lobby() then inform("Join the lobby to change worlds.");return end
    firetouchinterest(root,get_world_teleporter(),0);task.wait();firetouchinterest(root,get_world_teleporter(),1)
end end
Bridge.actions["Remove Selected Unit"]=function()
    local item;for _,v in ipairs(Bridge.items)do if v.buffList then item=v;break end end
    if item and Settings.auto_buff_units[item.value] then Settings.auto_buff_units[item.value]=nil;Save() end
end
Bridge.actions["Reset Buff List To Default"]=function()Settings.auto_buff_units=DeepCopy(DefaultSettings.auto_buff_units);Save()end
Bridge.actions["Add Unit"]=function()
    local function field(name,default)local item=Bridge.fields[name];return item and item.value or default end
    local name=field("Unit","None")
    if name=="None" then inform("Select a unit first.");return end
    if Settings.auto_buff_units[name] then inform("This unit is already added.");return end
    local checks=field("Checks","None"):lower()
    local list={};if checks:find("attack",1,true)then list[#list+1]="attack" end;if checks:find("range",1,true)then list[#list+1]="range" end
    local multi=field("Has Multi Ability",false)
    Settings.auto_buff_units[name]={["Mode"]=field("Mode","Box"),["Checks"]=list,["Ability Type"]=multi and "Multiple" or "Normal",
        ["Ability Name"]=multi and ("@slot:"..(field("Multi Ability Slot","Slot 1"):match("%d+") or "1")) or nil,
        ["Time"]=math.clamp(tonumber(field("Cooldown (Sec)",13)) or 13,0,3600),["Cycle Units"]=8,["Delay"]=0}
    Save();inform(name.." added.")
end

Bridge.keys={["Auto Ability"]="auto_buff",
["Auto Battle"]="auto_battle",
["Auto Sell"]="auto_upgrade_sell",
["Auto Upgrade"]="auto_place_upgrade",
["Auto Vote Extreme"]="auto_vote_extreme",
["Auto Skip Wave"]="macro_autoskipwave",
["Auto 2x Speed"]="auto_2x",
["Auto 3x Speed"]="auto_3x",
["Auto Replay"]="auto_replay",
["Auto Next Story"]="auto_next_story",
["Record Macro"]="macro_record",
["Playback Macro"]="macro_playback",
["Check Wave"]="macro_check_wave",
["Money Tracking"]="macro_money_tracking",
["Auto-Adjust Placements"]="macro_auto_adjust_placement",
["Retry Failed Steps"]="action_queue_remote_on_fail",
["Summon Unit"]="macro_summon",
["Sell Unit"]="macro_sell",
["Upgrade Unit"]="macro_upgrade",
["Priority"]="macro_priority",
["Unit Ability"]="macro_ability",
["Unit Auto Ability"]="macro_auto_ability",
["Skip Wave"]="macro_skipwave",
["Speed Change"]="macro_speedchange",
["Auto Join Game"]="auto_join_game",
["Auto Join Tower"]="auto_join_tower",
["Auto Evolve EXP"]="auto_evolve_exp",
["Auto Click Popup"]="auto_skip_gui",
["Auto Join EXP"]="smart_join_auto_exp",
["Show Username"]="webhook_user_name",
["Ping User"]="webhook_ping_user",
["Ping Only On Lose"]="webhook_ping_on_lose",
["Webhook On Game End"]="webhook_end_game",
["Webhook After EXP Evolve"]="webhook_exp_evolve",
["Cycle Timestop"]="auto_cycle_timestop",
["Auto Killua"]="auto_killua",
["Smart Ability"]="auto_target_ability",
["Multi Ability"]="auto_target_ability_multi",
["Auto Placement"]="auto_place",
["Show Zones"]="auto_place_show_zones",
["Auto Execute"]="auto_execute",
["Enemy Overlay"]="show_enemy_overlay",
["Close UI On Execution"]="close_on_injection",
["Mobile Toggle Button"]="mobile_toggle",
["Lock UI Position"]="lock_ui",
["Level Spoofer"]="level_spoofer",
["Performance Mode"]="fps_boost",
["Hide Enemies"]="delete_enemies",
["Hide Map"]="delete_map",
["Disable 3D Rendering"]="disable_3d_rendering",
["Anonymous Mode"]="anonymous_mode",
["UI Keybinds"]="macro_keybinds",
["Upgrade Level"]="auto_upgrade_level",
["Record Time Offset"]="macro_record_time_offset",
["Playback Time Offset"]="macro_playback_time_offset",
["Magnitude"]="macro_magnitude",
["Search Attempts"]="macro_playback_search_attempts",
["Search Delay"]="macro_playback_search_delay",
["Step Delay"]="action_queue_remote_fire_delay",
["Retry Delay"]="action_queue_remote_on_fail_delay",
["Retry Loop Delay"]="action_queue_remote_on_fail_delay_loop",
["Story Target"]="auto_story_target",
["Delay (Sec)"]="auto_join_delay",
["Trigger HP %"]="auto_target_hp_percent",
["Enemy Count"]="auto_target_enemy_count",
["Smart Ability Delay"]="auto_target_ability_delay",
["Battle Gems"]="auto_battle_gems",
["Upgrade Min Money"]="auto_upgrade_money",
["Upgrade Start Wave"]="auto_upgrade_wave",
["Upgrade Stop Wave"]="auto_upgrade_wave_stop",
["Sell At Wave"]="auto_upgrade_wave_sell",
["UI Scale"]="ui_scale",
["Webhook URL"]="webhook_url",
["Discord ID"]="webhook_discord_id",
["Timestop Unit"]="auto_cycle_timestop_unit",
["Ability Unit"]="auto_target_ability_unit",
["Display Level"]="visual_level",
["Display Name"]="anonymous_mode_name",
["Selected Profile"]="macro_profile",
["Mode"]="auto_join_mode",
["Wish"]="auto_killua_wish",
["Enemy Type"]="auto_target_enemy_type",
["Profile"]="macro_profile",
["Upgrade Targets"]="auto_upgrade_targets",
["Action Interval"]="auto_place_interval",
["Unit Spacing"]="auto_place_spacing",
["Upgrade Minimum Money"]="auto_upgrade_money",
["Infinite Map"]="auto_join_infinite_level",
["Adventure Map"]="auto_join_adventure_level",
["FPS Limit"]="fps_limit",
["Window Opacity"]="ui_opacity",
["Accent Color"]="ui_accent",
["Theme Preset"]="ui_theme",
["Toggle Key"]="ui_toggle_key"}
local _newProfileName,_importMacroURL,_importSettingsURL="","",""
local _confirmAction
local function rebuildProfileDropdown() RefreshMacroProfileList();changed() end
function Bridge.Open(item)
    if item.profiles then RefreshMacroProfileList() end
    Bridge.Read(item)
end
RefreshMacroLeaderDropdown=function()local p=GetActiveMacroProfile();if p then GetMacroProfileLeaderUnit(p)end end

Bridge.actions["Create New Profile"]=function()
_newProfileName=Bridge.fields["New Profile Name"].value or ""
_importMacroURL=Bridge.fields["Import Macro URL"].value or ""
_importSettingsURL=Bridge.fields["Import Settings URL"].value or ""
    if not KP.ValidProfileName(_newProfileName) or string.match(_newProfileName, '[^%w%s]') then ShowNotify("Macro", "Invalid name. Use 1-100 letters, numbers or spaces; no trailing spaces."); return end
    if KP.FindProfileName(_newProfileName) or isfile(GetMacroProfilePath(_newProfileName)) then ShowNotify("Macro", "A profile with this name already exists.") return end
    rawset(Macros, _newProfileName, DeepCopy(IndividualMacroDefaultSettings))
    Settings.macro_profile = _newProfileName
    table.insert(MacroProfileList, _newProfileName)
    table.sort(MacroProfileList)
    Save()
    if KP.dirtyProfiles[_newProfileName] then
        ShowNotify("Macro", "Couldn't save the profile. It's still loaded, but isn't saved. Check the console.")
    else ShowNotify("Macro", "Profile created.") end
    rebuildProfileDropdown(MacroProfileList, Settings.macro_profile)
    RefreshMacroLeaderDropdown()

end

Bridge.actions["Delete Profile"]=function()
_newProfileName=Bridge.fields["New Profile Name"].value or ""
_importMacroURL=Bridge.fields["Import Macro URL"].value or ""
_importSettingsURL=Bridge.fields["Import Settings URL"].value or ""
    if #MacroProfileList <= 1 then ShowNotify("Macro", "You need to keep at least one profile."); return end
    _confirmAction = {kind = "delete", profile = Settings.macro_profile}
    ShowNotify("Confirm", "Press Confirm Action to delete " .. _confirmAction.profile .. ".")

end

Bridge.actions["Clear Macro Data"]=function()
_newProfileName=Bridge.fields["New Profile Name"].value or ""
_importMacroURL=Bridge.fields["Import Macro URL"].value or ""
_importSettingsURL=Bridge.fields["Import Settings URL"].value or ""
    _confirmAction = {kind = "clear", profile = Settings.macro_profile}
    ShowNotify("Confirm", "Press Confirm Action to clear " .. _confirmAction.profile .. ".")

end

Bridge.actions["Confirm Action"]=function()
_newProfileName=Bridge.fields["New Profile Name"].value or ""
_importMacroURL=Bridge.fields["Import Macro URL"].value or ""
_importSettingsURL=Bridge.fields["Import Settings URL"].value or ""
    if KP.recording or KP.playback then ShowNotify("Macro", "Stop the macro before deleting or clearing profiles."); return end
    local pending = _confirmAction
    if not pending then ShowNotify("Macro", "No pending action."); return end
    if pending.profile ~= Settings.macro_profile then
        _confirmAction = nil
        ShowNotify("Macro", "You switched profiles. Nothing was changed.")
        return
    end
    if pending.kind == "delete" then
        if #MacroProfileList <= 1 then _confirmAction = nil; ShowNotify("Macro", "You need to keep at least one profile."); return end
        local rp = pending.profile
        local deleted, err = pcall(function() delfile(GetMacroProfilePath(rp)) end)
        if not deleted then KP.Report("Delete profile", err); ShowNotify("Macro", "Couldn't delete the profile."); return end
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
        if SaveMacroProfile(name) then ShowNotify("Macro", "Macro cleared. A backup was saved.")
        else ShowNotify("Macro", "Couldn't save the cleared macro. A backup was saved, but the changes are still unsaved.") end
    end
    _confirmAction = nil

end

Bridge.actions["Import Start"]=function()
_newProfileName=Bridge.fields["New Profile Name"].value or ""
_importMacroURL=Bridge.fields["Import Macro URL"].value or ""
_importSettingsURL=Bridge.fields["Import Settings URL"].value or ""
    if _importMacroURL ~= "" then importMacro(_importMacroURL) end
    if _importSettingsURL ~= "" then importSettings(_importSettingsURL) end

end

Bridge.actions["Export Macro To Link"]=function()
_newProfileName=Bridge.fields["New Profile Name"].value or ""
_importMacroURL=Bridge.fields["Import Macro URL"].value or ""
_importSettingsURL=Bridge.fields["Import Settings URL"].value or ""
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

end

function KP.ShareableSettings()
    local shared=DeepCopy(Settings)
    shared.webhook_url=""
    shared.webhook_discord_id=""
    shared.webhook_ping_user=false
    shared.webhook_ping_on_lose=false
    return shared
end
Bridge.actions["Export Settings To Link"]=function()
_newProfileName=Bridge.fields["New Profile Name"].value or ""
_importMacroURL=Bridge.fields["Import Macro URL"].value or ""
_importSettingsURL=Bridge.fields["Import Settings URL"].value or ""
    task.spawn(function()
        ShowNotify("Export", "Uploading settings...")
        local json = game:GetService("HttpService"):JSONEncode(KP.ShareableSettings())
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

end

Bridge.actions["Save Current Spawn Position"]=function()
_newProfileName=Bridge.fields["New Profile Name"].value or ""
_importMacroURL=Bridge.fields["Import Macro URL"].value or ""
_importSettingsURL=Bridge.fields["Import Settings URL"].value or ""
        local profile = Macros[Settings.macro_profile]
        profile.Map = profile.Map or {}
        profile.Map.SpawnLocation = tostring(game:GetService("Workspace").SpawnLocation.CFrame)
        Save()
        ShowNotify("Macro", "Spawn position saved.")

end

Bridge.actions["Update Placement Locations"]=function()
_newProfileName=Bridge.fields["New Profile Name"].value or ""
_importMacroURL=Bridge.fields["Import Macro URL"].value or ""
_importSettingsURL=Bridge.fields["Import Settings URL"].value or ""
        if KP.recording or KP.playback then ShowNotify("Macro", "Stop recording/playback before moving placements."); return end
        local profile = GetActiveMacroProfile()
        local spawn = workspace:FindFirstChild("SpawnLocation")
        local saved = profile and profile.Map and profile.Map.SpawnLocation
        if not spawn or not saved then ShowNotify("Macro", "Save the spawn position first."); return end
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
        if not ok then KP.Report("Placement offset", updated); ShowNotify("Macro", "Couldn't read the saved placements. Nothing changed."); return end
        local file = GetMacroProfilePath(Settings.macro_profile)
        local backedUp, err = pcall(function() writefile(file .. ".before-offset.bak", readfile(file)) end)
        if not backedUp then KP.Report("Placement backup", err); return end
        rawset(Macros, Settings.macro_profile, updated)
        KP.macroTargetPositionCache, MacroTargetCache = {}, {}
        if SaveMacroProfile(Settings.macro_profile) then ShowNotify("Macro", "Placement locations updated. Previous file backed up.")
        else ShowNotify("Macro", "Placement save failed; changes remain pending. Previous file backed up.") end

end

Bridge.actions["Test Webhook"]=function()
_newProfileName=Bridge.fields["New Profile Name"].value or ""
_importMacroURL=Bridge.fields["Import Macro URL"].value or ""
_importSettingsURL=Bridge.fields["Import Settings URL"].value or ""
    SendWebhook({{["name"] = "Webhook Test", ["value"] = "Sent successfully!"}})
    ShowNotify("Webhook", "Test sent!")

end
function Bridge.Attach(gui,refresh,notify)
    KP.ui=gui;Bridge.refresh=refresh;ShowNotify=function(title,body)notify(tostring(title)..": "..tostring(body or ""))end
    KP.refreshSettingsUI=refresh;AP.RefreshUI=refresh;KP.UIRefs={}
    for _,item in ipairs(Bridge.items) do if item.settingKey then KP.UIRefs[item.settingKey]={refresh=refresh,setValue=function(v)Bridge.Write(item,v)end} end end
    KP.enemyOverlayFolder=Instance.new("Folder");KP.enemyOverlayFolder.Name="EnemyOverlay";KP.enemyOverlayFolder.Parent=gui;KP.enemyOverlayRefs={}
    local backdrop=Instance.new("Frame");backdrop.Name="RenderingBackdrop";backdrop.Size=UDim2.fromScale(1,1);backdrop.BackgroundColor3=Color3.new(0,0,0);backdrop.BorderSizePixel=0;backdrop.ZIndex=0;backdrop.Visible=false;backdrop.Parent=gui
    KP.applyRendering=function(disabled)
        local ok,err=pcall(function()game:GetService("RunService"):Set3dRenderingEnabled(not disabled)end)
        if not ok then Settings.disable_3d_rendering=false;KP.Report("3D rendering",err)end
        backdrop.Visible=ok and disabled
        return ok
    end
    KP.restoreRendering=function()pcall(function()game:GetService("RunService"):Set3dRenderingEnabled(true)end)end
    KP.applyRendering(Settings.disable_3d_rendering)
    task.spawn(function()while ScriptAlive() and gui.Parent do pcall(KP_RenderEnemyOverlay);task.wait(.35)end end)
    BindAutoExecute()
end

-- User-approved ability editing, confirmations, activity status and map totals.
local configureBase=Bridge.Configure
function Bridge.Configure(pages)
    local ability=pages[6].tabs[1]
    table.insert(ability.cards[1].items,3,{type="button",label="Edit Selected Unit"})
    table.insert(ability.cards[2].items,1,{type="note",label="New Ability Unit",editStatus=true})
    table.insert(ability.cards[2].items,{type="button",label="Save Unit Changes",accent=true})
    for _,card in ipairs(pages[3].tabs[3].cards)do
        for i=#card.items,1,-1 do if card.items[i].label=="Confirm Action" then table.remove(card.items,i)end end
    end
    configureBase(pages)
end
local readBase=Bridge.Read
function Bridge.Read(item)
    local previous=item.value
    local value=readBase(item)
    if item==Bridge.fields.Unit and Bridge.editUnit and previous==Bridge.editUnit then
        if not table.find(item.options,previous)then table.insert(item.options,previous)end
        item.value=previous;value=previous
    end
    if item.editStatus then item.label=Bridge.editUnit and ("Editing: "..Bridge.editUnit) or "New Ability Unit" end
    return value
end
Bridge.actions["Edit Selected Unit"]=function()
    local selected;for _,item in ipairs(Bridge.items)do if item.buffList then selected=item.value;break end end
    local config=selected and Settings.auto_buff_units[selected]
    if not config then inform("Select an ability unit first.");return end
    Bridge.editUnit=selected
    local f=Bridge.fields
    f.Unit.value=selected;f.Mode.value=config.Mode;f["Cooldown (Sec)"].value=tostring(config.Time)
    local attack=table.find(config.Checks or {},"attack");local range=table.find(config.Checks or {},"range")
    f.Checks.value=attack and (range and "Attack + Range" or "Attack Only") or (range and "Range Only" or "None")
    f["Has Multi Ability"].value=config["Ability Type"]=="Multiple"
    local slot=config["Ability Name"] and config["Ability Name"]:match("^@slot:(%d+)$")
    f["Multi Ability Slot"].options={"Slot 1","Slot 2"}
    f["Multi Ability Slot"].value="Slot "..(slot or "1")
    if f["Has Multi Ability"].value and not slot then
        table.insert(f["Multi Ability Slot"].options,"Saved Ability")
        f["Multi Ability Slot"].value="Saved Ability"
    end
end
Bridge.actions["Save Unit Changes"]=function()
    local name=Bridge.editUnit;local old=name and Settings.auto_buff_units[name]
    if not old then inform("Select an existing unit and press Edit Selected Unit first.");return end
    if Bridge.fields.Unit.value~=name then inform("Select "..name.." to save its changes, or use Add Unit for a new unit.");return end
    local f=Bridge.fields;local cooldown=tonumber(f["Cooldown (Sec)"].value)
    if not cooldown or cooldown~=cooldown or cooldown<0 or cooldown>3600 then inform("Enter a cooldown between 0 and 3600 seconds.");return end
    local config=DeepCopy(old);config.Mode=f.Mode.value;config.Time=cooldown;config.Checks={}
    if f.Checks.value:lower():find("attack",1,true)then table.insert(config.Checks,"attack")end
    if f.Checks.value:lower():find("range",1,true)then table.insert(config.Checks,"range")end
    config["Ability Type"]=f["Has Multi Ability"].value and "Multiple" or "Normal"
    if config["Ability Type"]=="Normal" then config["Ability Name"]=nil
    elseif f["Multi Ability Slot"].value~="Saved Ability" then config["Ability Name"]="@slot:"..(f["Multi Ability Slot"].value:match("%d+") or "1")end
    local running=Settings.auto_buff
    KP.StopFeature("auto_buff");Settings.auto_buff_units[name]=config;Save()
    if running and not is_lobby() then task.spawn(KP.startFeatures.auto_buff)end
    inform(name.." updated.")
end
local addUnit=Bridge.actions["Add Unit"]
Bridge.actions["Add Unit"]=function()
    local f=Bridge.fields
    if f["Has Multi Ability"].value and f["Multi Ability Slot"].value=="Saved Ability" then inform("Choose an ability slot for the new unit.");return end
    local text=tostring(f["Cooldown (Sec)"].value or "")
    local cooldown=text=="" and 13 or tonumber(text)
    if not cooldown or cooldown~=cooldown or cooldown<0 or cooldown>3600 then inform("Enter a cooldown between 0 and 3600 seconds.");return end
    addUnit()
end
-- AutoBuff creates its workers from a snapshot of the configured unit list.
-- Restart after successful mutations so additions and resets take effect now.
for _,label in ipairs({"Add Unit","Remove Selected Unit","Reset Buff List To Default"})do
    local action=Bridge.actions[label]
    Bridge.actions[label]=function()
        local before={};for name,config in pairs(Settings.auto_buff_units)do before[name]=config end
        action()
        local changedList=false
        for name,config in pairs(before)do if Settings.auto_buff_units[name]~=config then changedList=true;break end end
        if not changedList then
            for name,config in pairs(Settings.auto_buff_units)do if before[name]~=config then changedList=true;break end end
        end
        if changedList then
            KP.StopFeature("auto_buff")
            if Settings.auto_buff and not is_lobby()then task.spawn(KP.startFeatures.auto_buff)end
        end
    end
end
local confirmOriginal=Bridge.actions["Confirm Action"]
Bridge.actions["Confirm Action"]=nil
for _,spec in ipairs({{"Delete Profile","delete","Delete"},{"Clear Macro Data","clear","Clear"}})do
    Bridge.actions[spec[1]]=function()
        local profile=Settings.macro_profile
        if not profile or not GetActiveMacroProfile()then inform("No profile loaded.");return end
        Bridge.Confirm(spec[1],spec[3].." "..profile.."?",spec[3],function()
            _confirmAction={kind=spec[2],profile=profile};confirmOriginal();changed()
        end)
    end
end
local resetSettings=Bridge.actions["Reset Settings To Default"]
Bridge.actions["Reset Settings To Default"]=function()
    Bridge.Confirm("Reset All Settings","Reset gameplay settings and saved UI preferences to their defaults?","Reset",resetSettings)
end
function Bridge.Status()
    if KP.recording then return "Recording" elseif KP.playback then return "Playback" end
    if KP.joinRun and is_lobby() and (Settings.auto_join_game or Settings.smart_join_auto_exp)then return "Joining" end
    local names={{"auto_place","Auto Placing"},{"auto_upgrade","Auto Upgrading"},{"auto_battle","Auto Battle"},{"auto_join_tower","Joining Tower"},{"auto_evolve_exp","Evolving EXP"},{"auto_target_ability","Smart Ability"},{"auto_cycle_timestop","Timestop"},{"auto_buff","Auto Ability"},{"auto_killua","Auto Killua"},{"auto_replay","Auto Replay"},{"auto_next_story","Next Story"},{"auto_skip_wave_spam","Auto Skip"},{"auto_upgrade_sell","Auto Sell"},{"auto_vote_extreme","Auto Vote"}}
    local labels={}
    for _,entry in ipairs(names)do if Settings[entry[1]] and KP.features[entry[1]] then labels[#labels+1]=entry[2]end end
    return #labels>0 and (labels[1]..(#labels>1 and " +"..tostring(#labels-1) or "")) or "Idle"
end

local statsPath="KarmaPanda/ASTD/MapStats_"..tostring(Player.UserId)..".json"
local totals={key=nil,seconds=0,replays=0}
pcall(function()
    if not isfile(statsPath) then return end
    local value=game:GetService("HttpService"):JSONDecode(readfile(statsPath))
    if type(value)~="table" or type(value.key)~="string" or #value.key>128 then return end
    for _,key in ipairs({"seconds","replays"})do local n=tonumber(value[key]);if not n or n<0 or n~=n or n==math.huge then return end;value[key]=n end
    totals={key=value.key,seconds=value.seconds,replays=math.floor(value.replays)}
end)
local lastTick=os.clock();local lastSave=lastTick;local wasActive=false
local executionMapChecked=false
local function persistTotals()
    lastSave=os.clock()
    local ok,err=pcall(function()writefile(statsPath,game:GetService("HttpService"):JSONEncode(totals))end)
    if not ok then KP.Report("Map stats save failed",err)end
end
function Bridge.MapSnapshot()
    local now=os.clock();local delta=math.max(0,now-lastTick);lastTick=now
    if wasActive then totals.seconds=totals.seconds+delta end
    local stage=game:GetService("ReplicatedStorage"):FindFirstChild("STORYMODE_VALUE")
    local value=stage and tonumber(stage.Value)
    wasActive=not is_lobby() and value~=nil and value~=0
    if wasActive then
        local key=tostring(game.PlaceId)..":"..tostring(value)
        if totals.key~=key then
            totals={key=key,seconds=0,replays=0};executionMapChecked=true;persistTotals()
        elseif not executionMapChecked then
            executionMapChecked=true;totals.replays=totals.replays+1;persistTotals()
        end
    end
    if now-lastSave>=10 then persistTotals()end
    return totals
end
KP.flushMapStats=function()Bridge.MapSnapshot();persistTotals()end
local attachBase=Bridge.Attach
function Bridge.Attach(...)
    attachBase(...)
    TrackConnection(Player.OnTeleport:Connect(KP.flushMapStats))
    task.spawn(function()while ScriptAlive() do Bridge.MapSnapshot();task.wait(1)end end)
end

local function buildInterface(Bridge)
--[[
    KarmaPanda  -  All Star Tower Defense interface
    Layout: top bar with search, private sidebar navigation,
    two-column collapsible cards, and a live status footer.

    Run on the Roblox client (executor, or a LocalScript in StarterPlayerScripts).
    Integrated gameplay controls use the original runtime. Theme, search, session timer,
    team editor, window drag/resize a nd the Discord copy button are live UI features.

    Editing:
      * CONFIG below holds branding and the default accent.
      * Pages holds every tab, card and control. Control types:
          toggle, slider, select, multi, input, color, button, note, account, session
      * Any control can take  desc = "..."  to show an info icon with a tooltip.
        Descriptions are optional; controls without one show no help icon.
      * Icons use local vector shapes so they render without external assets.
]]

local CONFIG = {
    GuiName  = "KarmaPandaUI",
    Brand    = "KARMAPANDA:X",
    Badge    = "v4.0 - script by blob",
    Invite   = "https://discord.gg/UDrvUguuNU",
    Accent   = "B41E1E",
    Width    = 940,
    Height   = 520,
}

local PRESETS = {Crimson = "B41E1E", Amethyst = "8B5CF6", Ocean = "338EDB", Emerald = "37B583", Amber = "D89832"}

local Pages = {{name = "Home", icon = "⌂", tabs = {{name = "", cards = {{title = "Quick Controls", icon = "◇", items = {{type = "toggle", label = "Auto Vote Extreme", value = false, sharedId = "quick0"},
                            {type = "toggle", label = "Auto Skip Wave", value = false, sharedId = "quick1"},
                            {type = "toggle", label = "Auto Placement", value = false, sharedId = "placement"},
                            {type = "toggle", label = "Auto Replay", value = false, sharedId = "quick4"},
                            {type = "toggle", label = "Auto Ability", value = true, sharedId = "quick5"}}, homeColumn = 1},
                    {title = "Player", icon = "◇", items = {{type = "player", label = "Player"}}, homeColumn = 2, noIcon = true},
                    {title = "Auto Upgrade", icon = "◇", items = {{type = "toggle", label = "Auto Upgrade", value = false, sharedId = "upgrade0"},
                            {type = "slider", label = "Upgrade Level", value = 10, min = 1, max = 23, step = 1, suffix = "", sharedId = "upgrade1"},
                            {type = "multi", label = "Upgrade Targets", value = {}, options = {}, teamOptions = true, sharedId = "upgrade2"}}, homeColumn = 2},
                    {title = "Map Information", icon = "◇", items = {{type = "session", label = "Map Information"}}, homeColumn = 1},
                    {title = "Discord", icon = "◇", items = {{type = "discord", label = "Copy Discord Invite"}}, homeColumn = 2}}}}},
    {name = "Automation", icon = "◇", tabs = {{name = "Main", cards = {{title = "Auto Placement", icon = "◇", items = {{type = "toggle", label = "Auto Placement", value = false, sharedId = "placement"},
                            {type = "button", label = "Refresh Current Team", accent = false}}},
                    {title = "Placement Tuning", icon = "◇", items = {{type = "slider", label = "Action Interval", value = 0.35, min = 0, max = 5, step = 0.05, suffix = " s"},
                            {type = "slider", label = "Unit Spacing", value = 4, min = 0, max = 20, step = 0.5, suffix = " st"},
                            {type = "toggle", label = "Auto Upgrade", value = true}}},
                    {title = "Units", icon = "◇", items = {}, type = "team"},
                    {title = "Other Automation", icon = "◇", items = {{type = "slider", label = "Battle Gems", value = 2700, min = 0, max = 10000, step = 50, suffix = ""},
                            {type = "slider", label = "Upgrade Minimum Money", value = 100, min = 0, max = 10000, step = 100, suffix = ""},
                            {type = "slider", label = "Upgrade Start Wave", value = 0, min = 0, max = 200, step = 1, suffix = ""},
                            {type = "slider", label = "Upgrade Stop Wave", value = 100, min = 0, max = 200, step = 1, suffix = ""},
                            {type = "slider", label = "Sell At Wave", value = 100, min = 0, max = 200, step = 1, suffix = ""}}}}},
            {name = "Zones", cards = {{title = "Placement Zones", icon = "◇", items = {{type = "toggle", label = "Show Zones", value = true}}},
                    {title = "Zone 1", icon = "◇", items = {{type = "toggle", label = "Zone Enabled", value = true},
                            {type = "slider", label = "Zone Size", value = 48, min = 8, max = 100, step = 1, suffix = " st"},
                            {type = "slider", label = "Transparency", value = 75, min = 25, max = 95, step = 5, suffix = "%"},
                            {type = "button", label = "Place / Move Zone", accent = false}}},
                    {title = "Zone 2", icon = "◇", items = {{type = "toggle", label = "Zone Enabled", value = false},
                            {type = "slider", label = "Zone Size", value = 48, min = 8, max = 100, step = 1, suffix = " st"},
                            {type = "slider", label = "Transparency", value = 75, min = 25, max = 95, step = 5, suffix = "%"},
                            {type = "button", label = "Place / Move Zone", accent = false}}},
                    {title = "Zone 3", icon = "◇", items = {{type = "toggle", label = "Zone Enabled", value = false},
                            {type = "slider", label = "Zone Size", value = 48, min = 8, max = 100, step = 1, suffix = " st"},
                            {type = "slider", label = "Transparency", value = 75, min = 25, max = 95, step = 5, suffix = "%"},
                            {type = "button", label = "Place / Move Zone", accent = false}}},
                    {title = "Zone 4", icon = "◇", items = {{type = "toggle", label = "Zone Enabled", value = false},
                            {type = "slider", label = "Zone Size", value = 48, min = 8, max = 100, step = 1, suffix = " st"},
                            {type = "slider", label = "Transparency", value = 75, min = 25, max = 95, step = 5, suffix = "%"},
                            {type = "button", label = "Place / Move Zone", accent = false}}}}}}},
    {name = "Macro", icon = "◎", tabs = {{name = "Macro Library", cards = {{title = "Macro Library", icon = "◇", items = {{type = "select", label = "Profile", options = {"None"}, value = "None"},
                            {type = "note", label = "No Profile Loaded"},
                            {type = "toggle", label = "Playback Macro", value = false},
                            {type = "toggle", label = "Record Macro", value = false},
                            {type = "button", label = "Play Macro", accent = true},
                            {type = "button", label = "Stop Macro", accent = false},
                            {type = "button", label = "Previous Step", accent = false},
                            {type = "button", label = "Next Step", accent = false},
                            {type = "button", label = "Reset Playback", accent = false}}}}},
            {name = "Macro Settings", cards = {{title = "Playback Options", icon = "◇", items = {{type = "toggle", label = "Check Wave", value = false},
                            {type = "toggle", label = "Money Tracking", value = false},
                            {type = "toggle", label = "Auto-Adjust Placements", value = false},
                            {type = "slider", label = "Playback Time Offset", value = 0, min = -10, max = 10, step = 0.1, suffix = " s"},
                            {type = "slider", label = "Magnitude", value = 1, min = 0, max = 2, step = 0.01, suffix = ""},
                            {type = "slider", label = "Search Attempts", value = 60, min = 0, max = 120, step = 1, suffix = ""},
                            {type = "slider", label = "Search Delay", value = 0.1, min = 0, max = 1, step = 0.01, suffix = " s"}}},
                    {title = "Action Queue", icon = "◇", items = {{type = "slider", label = "Step Delay", value = 0.25, min = 0, max = 1, step = 0.01, suffix = " s"},
                            {type = "toggle", label = "Retry Failed Steps", value = true},
                            {type = "slider", label = "Retry Delay", value = 1, min = 0, max = 1, step = 0.01, suffix = " s"},
                            {type = "slider", label = "Retry Loop Delay", value = 0.5, min = 0, max = 1, step = 0.01, suffix = " s"}}},
                    {title = "Recording Options", icon = "◇", items = {{type = "slider", label = "Record Time Offset", value = 0, min = -10, max = 10, step = 0.1, suffix = " s"}}},
                    {title = "Macro Options", icon = "◇", items = {{type = "toggle", label = "Summon Unit", value = true},
                            {type = "toggle", label = "Sell Unit", value = true},
                            {type = "toggle", label = "Upgrade Unit", value = true},
                            {type = "toggle", label = "Priority", value = true},
                            {type = "toggle", label = "Unit Ability", value = true},
                            {type = "toggle", label = "Unit Auto Ability", value = true},
                            {type = "toggle", label = "Skip Wave", value = true},
                            {type = "toggle", label = "Auto Skip Wave", value = true},
                            {type = "toggle", label = "Speed Change", value = true}}},
                    {title = "Placement Offsets", icon = "◇", items = {{type = "button", label = "Save Current Spawn Position", accent = false},
                            {type = "button", label = "Update Placement Locations", accent = false}}}}},
            {name = "Profiles", cards = {{title = "Profile Management", icon = "◇", items = {{type = "input", label = "New Profile Name", placeholder = "Profile name"},
                            {type = "button", label = "Create New Profile", accent = true},
                            {type = "button", label = "Delete Profile", accent = false},
                            {type = "button", label = "Clear Macro Data", accent = false},
                            {type = "button", label = "Confirm Action", accent = true}}},
                    {title = "Import & Export", icon = "◇", items = {{type = "input", label = "Import Macro URL", placeholder = "https://…"},
                            {type = "input", label = "Import Settings URL", placeholder = "https://…"},
                            {type = "button", label = "Import Start", accent = true},
                            {type = "button", label = "Equip Macro Units", accent = false},
                            {type = "button", label = "Export Macro To Link", accent = false},
                            {type = "button", label = "Export Settings To Link", accent = false}}}}}}},
    {name = "Play", icon = "▷", tabs = {{name = "Lobby", cards = {{title = "Auto Join", icon = "◇", items = {{type = "toggle", label = "Auto Join Game", value = false},
                            {type = "toggle", label = "Auto Join Tower", value = false},
                            {type = "select", label = "Mode", options = {"Story",
                                    "Infinite",
                                    "Adventure"}, value = "Story"},
                            {type = "select", label = "Infinite Map", options = {"None"}, value = "None"},
                            {type = "select", label = "Adventure Map", options = {"None"}, value = "None"},
                            {type = "slider", label = "Story Target", value = 0, min = 0, max = 100, step = 1, suffix = ""},
                            {type = "slider", label = "Delay (Sec)", value = 0, min = 0, max = 60, step = 1, suffix = ""}}},
                    {title = "Lobby Helpers", icon = "◇", items = {{type = "toggle", label = "Auto Join EXP", value = false},
                            {type = "toggle", label = "Auto Evolve EXP", value = true},
                            {type = "toggle", label = "Auto Click Popup", value = true}}},
                    {title = "World Teleports", icon = "◇", items = {{type = "button", label = "World 1", accent = false},
                            {type = "button", label = "World 2", accent = false},
                            {type = "button", label = "Lobby", accent = false}}}}},
            {name = "Match", cards = {{title = "Match Flow", icon = "◇", items = {{type = "toggle", label = "Auto Battle", value = false},
                            {type = "toggle", label = "Auto Vote Extreme", value = false, sharedId = "quick0"},
                            {type = "toggle", label = "Auto Skip Wave", value = false, sharedId = "quick1"},
                            {type = "toggle", label = "Auto 2x Speed", value = false, sharedId = "quick2"},
                            {type = "toggle", label = "Auto 3x Speed", value = false, sharedId = "quick3"},
                            {type = "toggle", label = "Auto Replay", value = false, sharedId = "quick4"},
                            {type = "toggle", label = "Auto Next Story", value = false},
                            {type = "toggle", label = "Auto Sell", value = false}}},
                    {title = "Auto Upgrade", icon = "◇", items = {{type = "toggle", label = "Auto Upgrade", value = false, sharedId = "upgrade0"},
                            {type = "slider", label = "Upgrade Level", value = 10, min = 1, max = 23, step = 1, suffix = "", sharedId = "upgrade1"},
                            {type = "multi", label = "Upgrade Targets", value = {}, options = {}, teamOptions = true, sharedId = "upgrade2"}}}}}}},
    {name = "Webhooks", icon = "♧", tabs = {{name = "", cards = {{title = "Connection", icon = "◇", items = {{type = "input", label = "Webhook URL", placeholder = "https://…"},
                            {type = "input", label = "Discord ID", placeholder = "Discord ID"},
                            {type = "button", label = "Test Webhook", accent = false}}},
                    {title = "Notifications", icon = "◇", items = {{type = "toggle", label = "Show Username", value = true},
                            {type = "toggle", label = "Ping User", value = false},
                            {type = "toggle", label = "Ping Only On Lose", value = false},
                            {type = "toggle", label = "Webhook On Game End", value = false},
                            {type = "toggle", label = "Webhook After EXP Evolve", value = false}}}}}}},
    {name = "Ability", icon = "✦", tabs = {{name = "Auto Ability", cards = {{title = "Auto Ability", icon = "◇", items = {{type = "toggle", label = "Auto Ability", value = true, sharedId = "quick5"},
                            {type = "select", label = "Your Units", options = {"None"}, value = "None", teamOptions = true},
                            {type = "button", label = "Remove Selected Unit", accent = false},
                            {type = "button", label = "Reset Buff List To Default", accent = false}}},
                    {title = "Add Ability Unit", icon = "◇", items = {{type = "select", label = "Unit", options = {"None"}, value = "None", teamOptions = true},
                            {type = "select", label = "Mode", options = {"Box",
                                    "Pair",
                                    "Cycle",
                                    "Spam"}, value = "Box"},
                            {type = "select", label = "Checks", options = {"Attack + Range",
                                    "Attack Only",
                                    "Range Only",
                                    "None"}, value = "Attack + Range"},
                            {type = "toggle", label = "Has Multi Ability", value = false, id = "addMulti"},
                            {type = "select", label = "Multi Ability Slot", options = {"Slot 1", "Slot 2"}, value = "Slot 1", visibleWhenId = "addMulti"},
                            {type = "input", label = "Cooldown (Sec)", placeholder = "13"},
                            {type = "button", label = "Add Unit", accent = true}}},
                    {title = "Time Stop Cycle", icon = "◇", items = {{type = "toggle", label = "Cycle Timestop", value = false},
                            {type = "select", label = "Timestop Unit", options = {"None"}, value = "None", teamOptions = true}}},
                    {title = "Auto Killua", icon = "◇", items = {{type = "toggle", label = "Auto Killua", value = false},
                            {type = "select", label = "Wish", options = {"Money",
                                    "Death",
                                    "Healing"}, value = "Money"}}}}},
            {name = "Smart Ability", cards = {{title = "Smart Ability", icon = "◇", items = {{type = "toggle", label = "Smart Ability", value = false},
                            {type = "select", label = "Ability Unit", options = {"None"}, value = "None", teamOptions = true},
                            {type = "slider", label = "Smart Ability Delay", value = 0, min = 0, max = 10, step = 0.1, suffix = " s"},
                            {type = "toggle", label = "Has Multi Ability", value = false, id = "smartMulti"},
                            {type = "select", label = "Multi Ability Slot", options = {"Slot 1", "Slot 2"}, value = "Slot 1", visibleWhenId = "smartMulti"}}},
                    {title = "Target Rules", icon = "◇", items = {{type = "select", label = "Enemy Type", options = {"Cloner",
                                    "Decelerate",
                                    "Boss"}, value = "Cloner"},
                            {type = "slider", label = "Trigger HP %", value = 10, min = 0, max = 100, step = 1, suffix = "%"},
                            {type = "slider", label = "Enemy Count", value = 0, min = 0, max = 10, step = 1, suffix = ""}}}}}}},
    {name = "Tools", icon = "⊞", tabs = {{name = "", cards = {{title = "Performance", icon = "◇", items = {{type = "toggle", label = "Performance Mode", value = false},
                            {type = "toggle", label = "Hide Enemies", value = false},
                            {type = "toggle", label = "Hide Map", value = false},
                            {type = "toggle", label = "Disable 3D Rendering", value = false},
                            {type = "slider", label = "FPS Limit", value = 60, min = 15, max = 240, step = 5, suffix = ""}}},
                    {title = "Visuals", icon = "◇", items = {{type = "toggle", label = "Enemy Overlay", value = false},
                            {type = "toggle", label = "Level Spoofer", value = false},
                            {type = "input", label = "Display Level", placeholder = "Level", visibleWhen = "Level Spoofer"},
                            {type = "toggle", label = "Anonymous Mode", value = false},
                            {type = "input", label = "Display Name", placeholder = "Name", visibleWhen = "Anonymous Mode"}}}}}}},
    {name = "Settings", icon = "⚙", tabs = {{name = "", cards = {{title = "Appearance", icon = "◇", items = {{type = "slider", label = "UI Scale", value = 100, min = 50, max = 150, step = 5, suffix = "%"},
                            {type = "slider", label = "Window Opacity", value = 96, min = 60, max = 100, step = 1, suffix = "%"},
                            {type = "color", label = "Accent Color", value = "#B41E1E"},
                            {type = "select", label = "Theme Preset", options = {"Crimson",
                                    "Amethyst",
                                    "Ocean",
                                    "Emerald",
                                    "Amber"}, value = "Crimson"},
                            {type = "button", label = "Reset Appearance", accent = false}}},
                    {title = "Window", icon = "◇", items = {{type = "toggle", label = "Close UI On Execution", value = false},
                            {type = "toggle", label = "Mobile Toggle Button", value = true},
                            {type = "toggle", label = "Lock UI Position", value = false},
                            {type = "select", label = "Toggle Key", options = {"K",
                                    "Right Control"}, value = "K"},
                            {type = "toggle", label = "UI Keybinds", value = true},
                            {type = "toggle", label = "Auto Execute", value = false},
                            {type = "button", label = "Reset UI Position", accent = false},
                            {type = "button", label = "Reset Settings To Default", accent = false}}},
                    {title = "About", icon = "◇", items = {{type = "credits", label = "script by blob · base by KarmaPanda"}}}}}}}}

-- Home shortcuts and their full pages reference the same setting objects.
do
    local shared={}
    for _,page in ipairs(Pages) do for _,tab in ipairs(page.tabs) do for _,card in ipairs(tab.cards) do for i,item in ipairs(card.items) do
        if item.sharedId then
            if shared[item.sharedId] then card.items[i]=shared[item.sharedId] else shared[item.sharedId]=item end
        end
    end end end end
end

local conditionSettings={}
for _,page in ipairs(Pages) do for _,tab in ipairs(page.tabs) do for _,card in ipairs(tab.cards) do for _,item in ipairs(card.items) do
    if item.id then conditionSettings[item.id]=item end
end end end end

-- Set an uploaded Roblox image asset here when using a Studio LocalScript.
Bridge.Configure(Pages)
CONFIG.Accent=Bridge.Initial().ui_accent or CONFIG.Accent
local LOGO_ASSET = ""
local LogoBytes = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\001\095\000\000\001\095\008\002\000\000\000\102\215\088\214\000\000\016\000\073\068\065\084\120\001\236\221\007\188\093\213\117\039\254\083\238\125\239\073\244\014\166\072\162\119\033\176\013\184\018\220\018\059\025\151\241\056\030\079\156\073\038\159\036\206\127\038\205\246\036\142\227\196\078\226\113\002\216\184\097\154\011\193\116\227\142\011\054\006\219\020\129\049\077\002\001\002\004\136\034\122\081\127\229\222\115\254\223\123\151\056\092\191\166\247\158\218\147\120\215\063\182\214\217\103\237\181\215\090\123\237\181\203\017\056\043\039\193\175\104\255\154\205\230\192\192\064\127\127\255\234\213\171\151\047\095\190\116\233\210\103\158\121\230\169\023\126\079\063\253\244\179\207\062\187\108\217\178\149\043\087\246\245\245\013\012\012\224\215\110\018\168\063\165\194\022\226\001\225\036\168\132\086\111\111\175\072\123\242\201\039\239\191\255\254\219\110\187\237\231\063\255\249\055\191\249\205\179\207\062\251\211\159\254\244\219\223\254\246\158\158\158\180\253\203\243\188\253\103\154\101\025\026\178\044\075\218\063\245\030\187\186\186\166\079\159\190\253\246\219\031\113\196\017\239\125\239\123\255\253\223\255\253\135\063\252\033\129\139\023\047\022\215\207\063\255\188\056\023\237\098\094\167\141\070\131\002\048\121\188\153\181\109\217\148\069\248\194\168\000\007\153\249\252\181\106\213\042\142\003\057\130\019\159\123\238\185\007\030\120\224\218\107\175\189\234\170\171\238\185\231\030\111\113\242\035\148\101\185\041\181\159\234\123\075\241\128\064\002\017\037\014\205\085\113\104\029\018\129\098\207\202\004\136\027\110\184\097\238\220\185\114\007\163\205\127\165\116\128\208\048\208\089\067\142\105\047\086\005\240\237\183\223\254\131\031\252\224\252\243\207\255\074\251\247\189\239\125\239\151\191\252\037\081\079\060\241\132\104\215\151\030\241\003\005\128\052\162\054\057\054\101\118\224\002\142\000\078\049\219\249\136\223\121\115\197\138\021\050\183\193\048\036\242\055\072\013\087\094\121\229\089\103\157\037\121\095\124\241\197\119\222\121\167\097\227\208\144\160\220\228\126\156\082\096\011\240\128\064\018\141\226\074\028\070\106\048\177\237\088\133\162\152\188\251\238\187\191\251\221\239\090\243\089\042\041\040\049\075\013\008\208\054\160\038\096\239\000\056\061\098\032\097\193\130\005\223\249\206\119\078\059\237\180\143\125\236\099\159\251\220\231\046\185\228\018\009\226\222\123\239\181\067\017\234\034\095\215\230\002\177\033\074\169\225\038\196\166\201\014\204\006\094\000\121\065\138\149\026\036\081\030\172\242\130\097\128\069\139\022\253\228\039\063\057\233\164\147\062\251\217\207\254\226\023\191\184\249\230\155\207\061\247\220\011\046\184\128\163\013\033\111\146\000\164\109\066\039\078\117\189\185\123\064\252\136\034\051\083\068\069\040\090\126\164\006\103\091\243\086\076\074\013\063\250\209\143\048\176\212\108\071\224\215\010\017\053\202\064\212\163\189\013\160\229\136\000\026\196\185\072\150\107\062\249\201\079\158\124\242\201\142\045\054\023\086\065\041\201\092\160\003\177\080\053\215\100\147\096\019\100\135\176\153\241\192\017\049\024\252\229\016\033\073\027\012\110\122\248\225\135\141\199\213\087\095\205\113\231\157\119\158\003\133\061\024\223\201\032\143\063\254\120\084\122\139\038\193\120\064\136\221\036\078\156\234\116\179\246\128\200\017\063\032\150\034\026\035\053\216\053\136\070\075\186\173\171\149\073\004\226\052\201\101\007\246\042\001\049\044\226\021\254\000\030\053\016\205\245\037\146\005\188\099\242\101\151\093\246\141\111\124\195\154\231\220\161\023\251\008\201\136\026\102\007\054\168\036\016\178\145\177\081\179\003\059\089\027\136\045\003\031\153\243\049\024\082\067\228\005\046\155\063\127\062\151\157\122\234\169\078\104\198\134\083\184\181\222\254\113\049\054\219\135\051\206\056\067\130\144\221\109\034\194\149\228\003\230\041\076\121\096\140\030\016\048\017\144\082\067\127\199\141\184\104\020\090\022\045\043\208\183\191\253\237\251\238\187\143\064\039\005\225\135\016\141\136\040\061\014\130\087\160\146\112\037\032\002\104\173\200\081\006\143\078\023\046\092\040\218\255\173\253\179\161\112\109\249\208\067\015\201\029\094\209\077\108\087\109\053\223\152\216\120\217\033\044\012\107\153\045\059\070\106\144\041\037\105\035\033\055\131\059\133\159\254\244\167\046\023\108\189\240\132\047\184\146\067\163\109\212\144\112\253\245\215\127\253\235\095\087\026\066\067\203\137\024\162\151\224\153\042\167\060\048\186\007\068\075\196\076\181\086\137\165\042\032\133\229\035\143\060\098\223\106\053\010\057\248\193\172\022\144\208\089\169\030\162\070\137\134\138\019\225\177\019\209\047\206\078\088\023\207\057\231\156\083\078\057\229\091\223\250\022\154\038\226\124\019\006\246\198\200\014\225\020\238\128\106\024\108\025\024\031\025\218\254\077\178\188\235\174\187\076\117\155\043\215\185\082\181\013\005\199\117\142\129\230\160\018\200\212\252\154\107\174\145\032\052\113\067\193\143\222\130\087\128\103\010\083\030\024\197\003\130\036\096\105\017\060\157\107\149\188\096\185\122\236\177\199\124\203\188\233\166\155\204\207\144\083\069\151\134\157\180\199\096\136\210\099\192\099\016\131\074\109\189\010\072\028\001\143\118\193\015\062\248\160\124\116\225\133\023\094\116\209\069\110\220\164\039\107\164\089\163\073\096\144\168\206\071\018\214\047\054\120\118\008\237\249\023\140\001\083\099\024\108\156\140\129\089\045\049\027\006\155\171\239\127\255\251\103\158\121\166\169\238\054\136\145\092\102\191\032\059\032\248\069\115\162\212\071\137\000\227\234\003\242\071\063\250\081\105\066\162\113\068\196\134\025\015\096\152\194\148\007\134\245\128\240\000\161\098\226\137\162\136\073\129\039\038\229\005\203\149\176\188\241\198\027\173\088\216\068\096\037\196\163\086\021\060\086\175\016\030\043\012\125\084\003\024\148\021\060\006\058\107\092\186\157\126\250\233\142\026\166\131\004\065\049\137\035\098\091\057\008\161\076\008\081\086\114\214\157\216\176\217\129\174\064\123\246\072\013\044\052\129\173\249\172\053\006\082\131\067\157\107\005\155\005\095\122\028\183\012\021\147\034\041\032\058\065\078\231\099\039\253\240\195\015\127\233\075\095\114\165\236\096\162\023\066\244\136\031\058\217\166\232\041\015\132\007\004\006\008\018\161\034\096\034\053\088\174\034\044\037\008\043\141\131\237\188\121\243\068\172\245\009\036\136\064\037\033\136\013\090\218\080\011\236\175\125\237\107\148\161\018\101\044\174\114\025\181\043\152\089\192\150\000\187\096\125\105\181\161\178\003\021\033\052\102\137\049\096\091\164\006\118\202\205\102\242\146\037\075\124\200\177\125\146\026\124\161\116\228\099\149\212\016\195\160\244\072\136\114\116\240\206\175\126\245\171\047\124\225\011\118\031\247\221\119\159\094\244\168\107\109\097\244\182\083\111\095\106\030\016\018\032\060\004\137\153\038\044\059\015\185\018\132\248\188\229\150\091\108\028\226\108\027\001\089\037\136\141\233\046\234\153\032\103\159\125\246\133\023\094\120\237\181\215\218\098\139\237\128\140\006\148\151\047\228\181\071\031\125\212\244\097\023\172\071\013\055\072\118\160\034\024\000\144\023\024\192\036\218\115\189\045\131\061\155\188\096\215\112\239\189\247\058\092\253\236\103\063\099\030\147\164\003\099\160\137\217\174\084\067\008\168\007\143\035\033\222\218\004\218\137\073\016\182\018\182\039\250\037\004\072\024\169\225\084\253\102\234\129\137\169\045\018\064\072\128\212\032\066\076\048\097\041\090\100\004\091\006\193\137\054\033\077\069\169\161\086\171\073\013\154\116\118\023\193\214\089\179\225\232\232\139\038\178\131\028\033\097\217\110\155\068\230\011\061\037\053\202\155\089\102\019\133\133\189\137\198\180\065\010\175\139\122\235\063\059\080\014\104\105\146\027\000\026\051\131\133\172\226\125\187\006\231\040\051\217\105\194\199\027\057\015\027\003\194\017\026\034\002\036\120\244\106\020\224\148\080\012\161\129\196\172\023\126\060\239\188\243\124\016\229\065\169\151\016\240\010\070\145\051\245\106\203\246\128\209\015\008\054\016\150\086\093\243\074\192\136\147\200\011\038\158\064\181\135\189\238\186\235\084\114\136\038\081\086\033\020\132\202\141\000\177\029\136\190\126\253\235\095\159\123\238\185\142\207\018\129\203\136\043\174\184\066\058\160\103\152\224\027\159\131\185\071\214\081\027\162\213\058\150\235\057\059\080\011\056\145\150\049\006\060\206\000\185\089\094\176\107\088\188\120\177\169\235\032\112\217\101\151\249\102\131\205\244\054\183\057\162\211\018\066\212\128\074\180\114\036\224\129\072\016\120\200\252\202\087\190\114\233\165\151\222\112\195\013\198\155\014\186\000\066\000\195\020\094\106\030\048\238\032\006\192\130\033\036\108\025\034\044\173\088\085\106\176\153\181\107\240\189\000\193\069\130\074\024\035\054\045\204\014\160\012\133\175\188\242\202\211\078\059\077\142\048\119\172\130\110\226\205\041\155\136\251\239\191\095\190\240\232\180\206\064\106\179\023\214\093\243\245\153\029\040\068\051\136\109\155\244\204\036\218\075\013\118\013\082\003\099\228\102\095\025\024\099\079\065\123\102\003\162\019\228\064\056\069\061\026\016\035\193\091\157\146\035\071\224\145\140\108\031\032\178\169\104\160\143\200\192\003\152\001\219\020\182\120\015\024\104\048\232\032\000\132\028\136\073\027\114\203\108\228\005\049\137\176\143\048\181\164\006\103\123\110\017\075\026\066\208\017\138\074\240\074\229\070\064\244\174\035\157\090\062\065\215\246\011\087\095\125\181\227\179\210\169\252\242\203\047\119\117\234\206\082\144\047\090\180\200\020\147\029\088\202\094\205\065\243\117\193\122\203\014\084\161\019\208\143\174\210\179\089\026\099\096\013\167\055\239\095\127\253\245\014\020\110\098\025\128\159\181\074\096\000\090\089\209\030\209\001\245\035\001\131\030\043\120\212\208\163\222\125\169\150\101\231\206\157\107\248\229\041\097\017\057\034\186\198\057\146\204\169\250\177\123\096\050\115\026\098\016\012\032\038\005\128\048\144\023\058\151\043\161\232\144\107\130\137\019\059\118\007\120\077\204\070\081\020\008\003\209\065\068\057\232\049\042\055\068\073\025\098\117\087\017\108\017\192\001\011\173\003\197\057\231\156\035\169\049\208\163\141\185\169\135\198\128\083\043\032\097\194\088\063\217\129\018\180\001\051\144\126\050\113\103\106\176\085\003\169\225\155\223\252\166\015\185\216\168\203\102\037\068\091\037\186\130\183\106\160\170\025\137\192\067\032\119\000\090\067\163\139\217\166\209\189\198\087\191\250\085\253\186\221\144\158\132\133\016\193\134\063\128\031\231\020\182\060\015\024\217\128\225\054\091\140\187\005\067\106\136\229\074\048\008\009\135\080\199\207\111\127\251\219\182\153\190\154\073\019\252\032\126\160\034\034\078\148\033\077\253\198\132\078\117\167\164\000\160\233\022\064\179\235\193\007\031\148\212\238\188\243\078\143\140\178\137\080\050\211\004\052\019\163\137\087\019\198\186\102\007\170\003\061\128\186\134\129\102\244\139\097\176\107\144\023\164\100\031\038\156\154\036\239\074\081\173\192\163\082\091\064\120\068\004\060\006\084\142\017\248\163\109\240\163\109\085\062\243\153\207\024\126\078\180\043\163\021\029\228\047\065\227\045\254\064\240\079\149\091\134\007\098\076\141\175\081\174\098\210\114\085\157\112\077\033\251\112\107\149\212\176\112\225\066\017\219\105\184\134\036\040\033\008\114\208\001\053\208\201\191\065\105\157\014\237\125\168\002\082\134\074\055\151\054\065\238\245\030\120\224\129\048\074\037\076\088\195\117\202\014\209\049\003\160\026\006\169\193\186\237\162\065\106\144\023\238\187\239\062\083\084\146\118\186\011\254\009\235\058\174\134\252\005\086\012\009\245\252\243\207\183\137\000\209\064\019\009\075\022\163\112\248\157\086\048\046\225\083\204\147\214\003\134\018\004\036\024\098\003\237\162\161\074\013\142\183\070\255\142\059\238\112\177\119\203\045\183\200\023\150\010\156\204\017\045\074\109\003\232\201\128\209\149\137\109\050\061\067\121\073\065\202\251\218\215\190\038\077\176\075\120\107\238\237\132\049\241\236\016\029\243\044\037\168\098\024\164\171\072\013\018\065\164\134\184\077\117\005\096\120\168\024\054\032\054\002\244\197\119\160\047\219\072\183\056\167\159\126\250\199\062\246\177\175\127\253\235\190\027\243\163\131\134\125\004\229\153\192\022\192\185\153\098\074\237\078\015\024\074\099\026\169\161\138\073\203\149\045\003\216\053\124\235\091\223\242\213\076\208\070\171\008\021\101\060\110\046\037\133\065\132\003\157\209\066\090\108\251\234\105\007\097\198\057\092\112\133\087\019\198\004\179\131\094\193\024\152\093\067\135\065\106\112\023\104\227\224\171\108\028\231\232\071\123\229\070\003\245\064\167\225\187\232\087\242\242\197\228\083\159\250\212\231\063\255\249\234\139\006\019\024\130\025\130\109\170\220\076\061\096\004\013\165\001\173\098\210\036\169\118\178\022\045\203\213\037\151\092\226\050\050\012\020\030\129\104\168\050\030\017\147\028\149\158\052\007\143\241\193\206\070\073\066\116\031\193\070\052\111\120\059\097\091\198\145\029\116\211\009\029\143\052\012\050\180\197\217\114\237\014\210\222\158\114\180\143\182\232\141\000\221\005\116\138\240\053\040\114\004\157\093\061\248\172\237\107\208\153\103\158\249\131\031\252\192\077\047\039\202\178\094\097\134\141\160\222\084\023\027\194\003\198\206\032\130\209\180\047\048\073\044\006\134\219\174\193\090\005\014\185\238\191\204\028\111\205\165\008\009\154\104\168\012\116\210\081\051\105\075\170\050\086\073\067\065\142\240\024\144\026\156\155\216\238\081\061\224\153\000\214\158\029\136\238\132\254\036\133\000\047\219\156\119\014\131\093\131\115\157\236\096\215\096\147\131\153\078\084\087\110\100\232\020\066\115\132\222\149\085\154\144\179\124\209\248\231\127\254\103\009\194\122\194\004\171\013\109\131\031\243\020\054\047\015\196\192\041\141\163\176\052\160\146\190\233\097\191\032\059\008\072\059\089\031\038\220\216\177\171\094\175\203\014\136\128\086\008\225\001\136\120\068\076\102\080\050\064\201\080\091\244\086\180\035\134\173\177\195\190\121\138\077\253\196\176\246\236\064\174\014\244\013\058\131\024\000\125\071\106\168\054\111\049\012\062\013\216\189\059\221\105\008\050\052\048\064\009\106\054\002\040\028\208\163\174\105\174\083\116\064\141\071\016\058\231\158\123\174\059\075\223\132\196\147\053\007\103\052\244\118\002\152\106\178\073\060\016\067\102\236\068\038\072\253\157\169\193\138\101\039\123\249\229\151\187\146\164\158\209\023\195\198\058\090\041\213\084\016\033\104\108\147\031\244\164\045\080\149\237\241\168\244\200\058\009\194\012\101\029\168\153\024\214\146\029\136\006\125\003\159\114\189\196\172\087\222\215\189\019\157\091\095\115\076\094\176\115\123\236\177\199\108\219\174\187\238\058\091\119\137\131\066\161\107\039\129\222\056\160\048\232\043\244\071\000\154\074\028\170\244\200\034\185\204\061\165\004\113\211\077\055\089\106\184\085\043\108\128\097\010\147\223\003\070\010\140\154\209\020\159\002\175\010\078\097\041\056\037\005\031\170\124\167\016\183\198\029\130\095\089\089\135\014\068\013\158\032\054\211\210\036\053\025\237\226\197\115\167\093\227\053\103\045\217\129\184\144\174\027\174\231\223\042\049\115\250\226\197\139\105\096\012\164\103\155\055\010\249\120\233\192\163\213\176\032\106\216\250\013\084\169\187\065\016\064\194\072\119\085\130\064\075\112\118\016\032\128\196\022\051\241\068\067\111\167\048\249\061\096\176\012\153\129\019\159\246\128\213\102\086\106\176\134\221\122\235\173\246\134\172\048\231\001\179\018\212\004\212\116\034\042\039\127\025\058\087\122\198\163\082\141\217\234\036\101\169\118\243\130\086\009\234\199\139\181\100\007\066\065\007\192\245\038\143\254\120\220\078\193\141\163\047\171\102\148\052\225\081\121\237\181\215\058\195\119\106\160\045\024\057\064\064\231\219\141\064\071\191\058\210\053\186\130\071\241\017\240\150\093\046\074\190\241\141\111\184\164\068\071\018\193\003\222\078\097\210\122\192\000\197\152\070\106\176\116\137\079\123\064\025\223\162\101\019\113\239\189\247\010\081\099\106\061\136\187\006\077\152\099\232\149\067\225\109\096\232\171\073\088\019\170\014\042\233\041\128\101\070\174\224\022\052\006\149\019\192\104\217\129\080\224\125\029\216\171\112\049\119\075\013\092\111\167\224\102\193\053\207\149\087\094\137\150\029\204\043\023\033\050\247\032\037\072\168\048\232\213\134\123\028\069\114\167\050\034\070\148\040\241\051\225\210\075\047\189\240\194\011\037\056\065\198\106\156\234\167\048\105\061\096\128\002\150\046\211\064\124\154\015\145\026\132\168\029\132\235\006\155\089\219\091\038\024\104\204\136\045\012\140\010\116\218\165\198\090\206\009\034\217\228\237\124\053\046\122\180\236\064\144\110\042\215\155\249\145\026\076\036\240\216\211\211\035\035\184\104\184\234\170\171\156\219\113\106\098\024\148\147\022\212\131\065\234\069\130\224\205\139\047\190\248\199\063\254\241\035\143\060\034\218\036\008\224\129\065\204\083\143\147\199\003\006\072\244\027\044\169\065\064\202\008\238\194\044\155\134\210\214\122\238\220\185\190\237\209\214\136\027\071\204\074\052\168\220\226\225\188\207\027\156\019\134\079\192\222\017\179\003\063\018\010\188\031\027\135\072\204\092\175\087\025\026\120\025\083\239\218\000\000\016\000\073\068\065\084\025\253\171\095\253\202\230\205\120\152\099\048\001\037\054\126\019\154\235\148\141\081\034\162\134\117\241\047\101\116\186\213\091\108\083\152\084\030\048\040\130\019\068\191\248\180\072\074\013\098\082\028\026\068\153\194\213\184\237\045\157\099\100\113\006\237\081\091\240\184\069\130\129\097\151\185\233\120\197\063\140\133\168\028\087\057\124\118\032\043\032\053\144\110\151\194\221\085\118\224\125\195\224\014\050\222\122\052\054\054\014\212\130\113\117\191\201\153\153\073\007\165\188\022\202\223\115\207\061\206\023\055\222\120\163\019\019\163\068\149\183\128\109\010\147\196\003\134\035\096\128\034\053\008\078\027\091\057\093\118\016\177\078\019\243\218\255\205\088\010\199\176\118\018\218\122\220\226\033\057\010\102\147\087\012\051\118\002\086\015\159\029\066\022\161\049\255\099\219\198\251\146\130\097\144\011\100\004\055\162\234\113\154\087\238\123\148\152\105\080\013\070\146\036\222\078\054\208\016\042\173\130\166\188\026\086\212\106\053\132\221\208\041\167\156\050\127\254\124\150\050\138\031\176\129\087\083\152\036\030\048\040\134\070\118\016\253\150\174\106\227\032\062\165\245\107\174\185\198\029\089\168\138\211\216\009\075\080\131\086\066\060\034\182\048\084\006\186\118\177\129\138\024\174\042\199\101\236\240\217\129\044\224\125\105\088\110\150\005\056\221\000\072\016\210\179\175\021\087\095\125\181\236\224\045\023\155\090\081\034\198\213\247\166\098\166\045\208\054\128\166\009\123\003\042\153\108\239\112\201\037\151\184\241\102\099\132\023\158\041\076\006\015\024\166\024\017\067\099\164\068\191\224\140\200\180\122\201\020\206\185\247\221\119\159\183\161\173\241\005\116\180\210\220\099\005\245\091\024\194\052\070\241\076\092\177\155\200\172\006\149\227\194\240\217\129\008\178\008\229\226\200\205\050\177\001\112\140\225\119\159\042\172\171\070\002\015\085\148\160\009\090\025\052\098\179\064\167\206\052\023\064\081\195\246\203\046\187\236\251\223\255\190\133\072\008\170\007\012\155\133\081\091\182\146\070\001\236\026\004\167\117\043\034\083\052\058\083\088\192\196\167\051\133\087\156\096\040\229\122\037\120\212\010\016\047\029\248\122\096\206\242\018\119\009\096\224\001\024\163\007\134\201\014\026\003\065\102\136\137\065\180\036\100\012\184\094\169\198\014\188\146\142\019\091\032\042\213\004\049\057\203\008\148\176\142\218\008\008\157\149\224\017\015\048\246\039\063\249\201\047\126\241\011\145\039\218\188\010\076\078\187\094\034\090\197\016\024\056\225\030\235\086\181\113\176\122\025\050\235\150\052\193\027\070\048\082\131\001\005\013\085\130\122\052\116\086\170\223\146\192\198\048\199\204\181\199\119\015\192\093\156\198\100\096\123\032\120\146\145\255\024\038\059\096\214\152\020\018\065\058\144\032\108\216\184\094\103\106\188\194\003\216\000\001\008\245\074\244\036\007\037\059\017\218\070\013\154\103\001\193\028\171\208\217\103\159\125\235\173\183\050\063\012\175\216\048\108\049\008\163\134\045\039\149\141\161\161\113\049\022\082\131\104\140\212\032\125\203\008\050\184\141\180\171\056\211\064\094\160\121\240\035\006\097\164\250\065\108\155\245\099\120\128\127\022\044\088\224\227\133\041\108\034\115\017\231\112\032\112\194\090\013\028\062\059\104\022\237\013\003\137\228\146\014\104\066\163\099\060\131\224\021\012\170\156\108\143\035\105\024\245\145\023\042\157\153\239\134\242\130\011\046\112\187\099\235\228\145\091\170\183\091\000\193\234\000\187\064\232\084\240\232\085\148\147\199\082\250\208\080\028\202\014\082\182\232\183\101\144\029\004\231\195\015\063\108\176\196\042\109\099\028\233\015\030\059\049\180\166\243\237\022\067\135\007\184\197\045\161\189\131\165\029\028\052\158\120\226\009\089\149\027\249\001\070\183\119\196\236\160\165\097\000\035\193\227\096\060\148\228\070\199\163\203\221\076\223\178\154\129\064\255\202\204\043\175\188\210\017\195\005\004\015\120\005\216\048\076\102\208\048\064\219\161\136\087\081\198\091\003\045\247\085\099\141\240\008\241\086\137\121\211\218\075\129\080\131\086\226\080\136\011\119\121\193\053\185\196\045\083\184\066\022\253\161\036\230\088\195\016\081\243\082\043\195\112\030\227\031\110\145\067\031\123\236\177\235\174\187\238\162\139\046\242\200\135\024\002\163\120\102\196\236\160\141\198\164\131\208\137\112\065\168\015\191\035\182\096\072\013\016\006\218\152\185\136\253\209\143\126\132\024\163\091\163\225\120\075\014\015\240\121\005\062\175\104\068\048\084\229\208\046\170\087\152\181\005\058\027\190\010\030\065\125\000\109\178\129\117\198\148\003\179\206\106\195\088\179\078\061\006\162\002\132\015\237\113\227\212\232\026\040\195\016\105\090\058\160\158\160\023\253\232\135\030\122\072\118\240\214\168\001\149\148\128\216\108\176\158\020\101\053\132\048\190\090\178\100\137\155\218\133\011\023\094\127\253\245\095\251\218\215\206\060\243\076\223\227\248\141\175\140\041\151\066\048\015\045\215\146\029\180\036\066\024\033\148\104\087\146\085\223\067\197\109\025\053\012\172\016\022\137\188\047\126\241\139\191\254\245\175\077\158\202\173\241\106\189\148\220\027\224\225\240\179\082\071\070\055\074\004\004\173\244\054\208\073\107\027\168\094\105\098\034\197\180\055\133\076\123\037\176\066\101\005\143\042\237\210\065\220\056\195\223\117\215\093\140\189\237\182\219\030\125\244\081\149\132\144\025\194\067\207\245\098\245\216\133\068\167\020\096\047\101\040\076\043\217\193\222\001\193\046\055\068\210\068\008\140\177\011\250\037\091\114\002\219\185\203\078\193\039\094\025\225\219\223\254\246\207\126\246\179\007\030\120\224\187\223\253\174\145\229\067\254\228\088\108\035\097\237\217\065\123\032\008\066\202\150\189\119\096\029\207\050\150\213\104\240\136\182\049\179\131\112\199\099\057\141\183\042\195\033\019\040\181\173\016\210\148\001\035\170\011\115\192\236\053\132\230\109\039\212\004\188\005\108\128\095\034\080\066\016\042\189\141\134\230\015\152\075\230\143\239\091\096\254\123\084\009\008\048\205\188\181\101\240\086\060\093\117\213\085\159\251\220\231\190\240\133\047\008\041\043\015\054\002\073\150\035\160\210\124\002\134\079\172\073\244\088\121\070\058\160\146\068\070\115\175\028\250\220\204\123\075\184\241\002\004\061\249\019\241\082\003\171\249\004\194\015\006\110\238\220\185\151\092\114\201\077\055\221\164\146\055\174\185\230\026\023\052\198\218\128\086\204\234\135\098\180\236\048\148\091\141\169\162\124\233\160\178\087\240\253\248\199\063\190\244\210\075\221\235\112\043\071\007\038\224\138\104\168\052\054\017\196\132\003\177\198\210\012\143\137\109\002\024\194\071\030\121\068\190\183\134\063\254\248\227\118\251\106\204\109\147\217\220\048\073\064\010\080\002\002\130\080\154\057\128\019\191\086\228\136\146\031\254\240\135\223\107\255\110\184\225\006\211\222\037\255\226\197\139\189\146\251\008\055\205\148\234\029\163\174\190\250\106\246\138\170\111\124\227\027\063\255\249\207\239\188\243\078\233\131\110\244\164\051\132\254\202\065\152\128\067\070\111\018\242\195\087\020\144\028\195\058\166\161\217\104\227\192\099\216\098\062\132\052\143\065\188\004\075\190\010\171\069\047\063\008\000\087\182\220\165\210\222\095\044\009\003\227\107\208\133\092\197\236\237\032\140\059\059\104\175\063\229\022\137\240\038\003\017\012\068\000\034\096\186\186\158\180\229\054\051\077\146\081\220\026\252\195\150\004\006\052\055\199\200\017\241\032\190\197\186\233\173\023\208\133\065\149\017\132\190\129\148\236\125\088\181\115\113\005\237\163\157\165\210\120\059\082\090\231\177\153\210\001\143\177\248\043\193\163\009\015\226\192\103\151\147\078\058\233\111\254\230\111\254\249\159\255\217\041\201\017\212\190\192\089\244\230\155\111\190\229\150\091\076\126\002\117\231\000\239\238\202\049\149\242\066\071\167\167\158\122\234\191\252\203\191\200\023\250\213\139\032\163\167\087\052\015\019\088\001\104\096\090\148\008\018\214\011\136\002\221\241\146\236\025\046\226\031\121\129\026\180\186\231\158\123\116\100\200\100\007\156\161\000\090\141\250\113\099\139\104\192\015\097\135\116\192\021\065\087\132\147\133\011\008\161\037\210\194\093\021\127\112\070\057\238\236\064\022\068\227\045\172\140\096\234\116\019\154\177\202\202\082\203\236\133\023\094\104\189\021\172\094\065\231\219\138\109\116\066\019\032\065\112\139\120\147\077\196\139\117\139\179\153\108\182\131\213\030\204\112\083\247\252\243\207\255\242\151\191\124\214\089\103\041\191\250\213\175\158\115\206\057\231\158\123\238\127\254\231\127\250\212\106\047\099\043\240\131\031\252\224\178\203\046\051\129\175\184\226\010\169\196\190\192\172\150\071\076\117\059\029\176\029\240\202\030\132\098\022\094\245\215\094\123\237\055\191\249\077\162\128\124\123\004\018\236\017\008\081\154\132\056\043\152\129\250\058\229\148\083\220\120\207\157\059\151\098\116\150\206\000\039\019\024\002\044\002\062\145\044\024\008\149\132\009\019\132\064\200\212\145\126\233\207\087\160\119\126\099\148\174\201\055\124\056\001\051\032\064\253\075\019\108\239\004\231\064\212\112\008\079\090\045\220\071\072\247\104\245\042\135\098\124\217\129\020\035\193\245\067\005\109\097\053\044\133\078\163\056\023\068\167\105\102\117\181\118\153\009\120\160\147\109\173\052\126\048\127\052\055\048\004\010\113\210\164\006\171\119\076\108\179\023\204\106\115\064\190\087\111\239\096\218\095\126\249\229\230\240\183\190\245\173\139\047\190\216\148\150\041\078\063\253\244\207\124\230\051\054\002\223\255\254\247\165\009\023\078\128\054\201\067\079\171\132\032\064\155\243\230\085\168\167\223\232\206\150\001\131\221\208\047\127\249\075\041\198\110\066\023\174\096\105\136\147\189\074\048\232\018\004\177\159\253\236\103\207\059\239\188\095\252\226\023\247\223\127\191\013\170\125\004\229\043\088\136\128\069\172\019\036\064\014\144\176\046\032\033\124\037\019\017\206\010\189\240\024\173\100\061\206\009\225\216\244\024\244\084\201\003\028\002\131\124\082\061\242\164\017\180\252\024\044\108\248\135\098\196\236\016\013\148\021\052\038\218\056\017\135\222\242\016\150\178\043\136\040\061\006\076\021\064\155\090\178\131\121\037\070\057\100\016\027\134\081\016\204\090\137\108\114\140\016\033\230\152\185\042\139\147\233\046\240\223\254\237\223\156\095\236\237\237\035\084\078\159\062\125\198\140\025\033\083\195\170\149\134\090\225\113\028\176\077\176\023\048\195\093\074\059\082\186\061\181\193\145\059\078\059\237\180\207\127\254\243\050\008\129\022\252\016\050\108\073\049\202\152\114\228\087\012\042\043\058\008\071\021\194\255\225\031\254\065\154\112\185\037\133\017\075\127\144\200\060\218\085\081\041\228\208\086\168\016\002\209\124\188\165\134\016\114\120\204\102\065\106\208\081\064\086\146\248\212\132\088\156\129\234\049\136\169\050\220\018\101\167\055\044\060\042\185\087\009\157\175\130\030\062\059\004\171\050\128\053\068\040\209\047\077\084\174\096\190\236\096\033\053\013\132\108\103\189\087\163\032\056\249\080\043\147\080\112\155\225\230\149\115\132\089\167\052\169\076\117\235\161\013\130\073\104\250\249\178\040\101\168\143\196\052\138\240\097\095\233\069\091\146\205\171\097\025\214\090\169\223\078\004\063\037\237\077\206\062\251\108\123\022\121\199\037\136\044\230\204\101\123\114\242\201\039\075\070\161\179\165\094\118\096\047\132\237\209\124\172\101\155\079\091\066\120\140\052\249\139\211\164\003\016\217\252\111\245\179\092\181\025\167\138\113\123\128\235\056\150\135\141\206\176\141\135\207\014\088\053\008\104\108\120\148\016\255\249\003\111\095\130\224\013\086\011\074\165\184\180\015\055\117\197\043\183\120\005\234\071\130\183\128\019\012\137\073\171\161\016\151\026\172\189\166\150\067\132\061\158\105\076\002\030\139\176\203\066\031\011\192\197\033\134\152\162\122\071\040\093\053\001\026\127\032\104\165\183\074\136\250\245\085\018\072\178\000\080\146\105\219\066\067\217\193\229\214\149\087\094\233\126\203\153\136\182\142\060\110\049\157\062\092\124\056\125\072\127\226\079\252\000\015\128\182\099\007\126\208\150\016\217\033\082\131\141\003\239\201\119\014\059\234\199\046\109\138\115\144\007\132\034\007\114\047\039\015\122\021\143\131\179\003\062\016\160\157\208\222\163\114\218\180\105\162\036\090\190\212\074\134\087\096\187\024\245\001\089\154\224\098\030\083\051\058\056\016\012\134\212\032\178\165\006\171\186\057\086\101\007\219\007\203\047\039\147\163\035\037\177\210\135\133\026\155\071\233\192\204\244\042\064\026\006\245\129\160\149\016\053\216\052\001\132\134\016\245\019\043\137\213\099\168\071\020\153\228\168\241\189\192\093\233\167\063\253\233\175\124\229\043\046\044\084\122\229\092\227\124\228\131\168\111\037\166\052\147\121\073\091\252\064\020\182\181\002\027\104\165\045\009\156\070\020\191\201\056\050\005\207\219\056\132\016\061\006\049\085\142\203\003\162\017\070\025\145\023\179\131\145\008\224\142\033\049\042\026\003\002\212\215\235\117\179\002\219\184\148\216\050\152\089\013\156\016\230\152\219\206\249\150\175\240\140\087\016\175\006\149\234\181\002\156\162\220\186\039\196\053\055\231\165\006\243\199\237\113\092\028\184\029\244\086\172\003\033\085\067\109\131\086\086\051\019\003\152\252\221\221\221\238\038\186\186\186\060\002\158\010\209\208\163\250\144\137\152\024\008\009\068\115\052\130\050\008\121\077\094\144\038\088\068\031\245\172\112\141\042\071\248\176\226\066\196\101\132\185\109\074\139\037\161\005\157\138\225\031\009\132\099\214\074\091\050\101\007\225\039\059\240\164\212\096\075\021\013\177\005\049\085\174\213\003\157\097\192\177\016\222\139\114\080\243\053\217\193\059\048\102\096\060\120\095\051\161\092\193\035\006\003\035\154\189\029\036\229\037\242\200\003\016\198\114\130\211\181\029\181\229\157\115\248\045\234\007\149\248\003\248\057\211\036\225\067\077\076\036\169\001\124\144\187\234\170\171\124\152\116\146\055\193\176\153\096\134\048\096\250\005\065\108\200\065\168\065\035\064\094\216\111\191\253\094\249\202\087\190\246\181\175\125\197\043\094\113\192\001\007\236\177\199\030\059\238\184\163\093\158\182\216\066\049\037\224\159\008\126\179\013\153\160\142\124\007\013\185\137\194\030\201\087\175\210\163\210\227\252\249\243\093\178\158\116\210\073\076\091\208\254\247\136\229\068\030\096\163\024\003\060\160\149\230\131\160\018\188\197\198\111\145\029\100\085\208\092\141\236\192\237\131\090\077\061\142\203\003\060\009\252\012\195\054\108\101\007\239\192\072\000\110\078\143\193\136\108\173\132\024\084\217\090\100\099\035\075\140\042\095\106\096\181\208\007\078\016\169\046\228\108\113\057\135\003\003\149\067\226\081\137\051\188\138\077\106\048\067\220\047\184\101\224\076\033\062\119\238\092\027\016\171\162\134\196\154\111\074\244\080\232\090\165\217\066\032\177\224\081\118\216\127\255\253\247\221\119\223\189\247\222\091\142\056\241\196\019\095\243\154\215\028\123\236\177\007\030\120\224\118\219\109\071\026\158\064\240\007\061\129\082\239\001\114\032\104\154\152\168\164\233\008\104\174\038\222\202\017\234\061\074\160\238\041\125\061\113\127\201\082\230\011\039\001\166\033\183\096\024\100\145\086\129\120\133\071\064\114\029\023\005\052\148\085\197\033\054\106\040\167\048\118\015\024\157\138\153\135\185\183\179\166\122\021\068\043\059\160\112\000\214\024\009\227\039\244\133\178\141\156\205\130\177\049\156\100\121\052\186\056\053\121\169\065\032\006\042\243\057\068\232\091\033\185\011\029\245\074\116\064\220\003\175\010\104\060\092\202\123\082\131\224\142\236\224\108\226\155\156\183\248\009\231\082\252\104\132\071\147\077\009\030\129\228\040\017\128\006\060\219\108\179\141\028\097\054\234\072\091\244\158\123\238\121\220\113\199\253\206\239\252\206\091\222\242\150\019\078\056\065\190\056\248\224\131\183\223\126\251\234\244\161\225\032\120\101\199\177\251\238\187\247\244\244\116\190\210\081\160\170\164\079\064\125\104\139\008\232\061\016\143\216\016\166\180\028\234\018\215\023\086\112\025\193\099\110\088\120\067\092\129\144\163\121\136\210\092\147\010\042\189\229\031\108\228\128\086\030\125\214\017\138\084\210\133\114\010\227\242\064\229\052\110\231\094\222\030\169\249\139\217\193\072\128\044\096\036\034\047\008\101\163\248\189\239\125\207\018\039\010\197\159\250\074\220\040\066\071\234\108\115\175\015\183\050\028\194\022\231\109\223\029\057\138\235\084\010\238\128\071\224\125\161\204\165\085\106\136\003\133\212\192\147\174\244\109\028\188\034\150\123\001\161\009\016\133\014\068\071\074\149\132\035\148\104\111\209\152\061\154\216\014\020\059\237\180\211\014\059\236\032\011\088\198\245\235\112\177\243\206\059\207\152\049\195\113\227\136\035\142\056\250\232\163\143\057\230\024\196\204\153\051\119\217\101\151\109\183\221\086\030\193\073\136\212\112\216\097\135\217\122\028\121\228\145\071\031\125\180\163\010\081\091\109\181\149\183\180\194\000\122\004\004\068\215\030\193\035\032\168\161\236\132\250\224\068\176\215\037\174\236\240\169\079\125\234\235\095\255\186\111\159\011\023\046\116\225\234\206\130\079\076\123\081\071\103\230\240\027\144\166\244\040\222\194\129\028\148\164\165\081\000\000\016\000\073\068\065\084\021\169\065\094\112\004\195\076\236\020\198\235\129\106\068\052\228\067\227\213\089\163\178\019\173\236\128\003\012\006\110\035\097\012\012\128\049\003\011\157\079\083\063\251\217\207\124\189\123\248\225\135\133\181\198\163\136\243\118\075\005\023\005\058\013\228\043\187\101\142\018\199\028\088\197\116\120\082\196\071\076\243\167\012\130\045\118\013\118\197\174\027\126\241\139\095\224\231\076\105\151\100\180\210\035\249\104\037\032\064\061\036\158\135\064\167\250\218\109\183\221\236\023\246\122\225\135\006\051\092\166\144\002\204\112\153\194\209\195\014\194\062\194\134\194\001\228\248\227\143\151\017\240\232\017\155\196\033\191\032\102\205\154\229\010\227\245\175\127\189\076\065\236\176\091\009\042\129\134\036\211\136\110\016\143\074\240\088\001\067\039\172\055\223\255\254\247\029\052\062\255\249\207\159\127\254\249\238\092\056\144\091\036\008\224\046\078\019\132\192\046\165\071\149\016\111\217\203\147\252\073\001\098\245\021\058\160\167\048\070\015\024\154\224\228\085\223\025\132\095\060\014\045\215\100\007\190\230\119\227\161\129\052\047\124\229\005\209\172\052\001\172\114\174\211\237\162\095\202\217\097\168\239\212\072\010\182\205\238\228\133\172\085\014\248\048\098\090\052\243\036\007\058\154\153\000\022\073\222\003\156\220\123\227\141\055\154\039\017\220\074\048\102\070\065\073\044\024\014\194\213\160\183\222\122\107\235\185\181\221\189\163\189\064\204\216\224\052\121\116\180\195\014\059\152\219\050\130\252\032\011\004\208\047\107\255\188\050\207\205\124\013\205\037\059\005\244\174\187\238\234\194\226\077\111\122\211\059\222\241\014\185\192\163\183\174\042\188\197\131\086\115\200\033\135\200\026\250\181\227\032\211\043\202\084\160\027\084\143\161\015\067\002\085\253\032\130\139\184\194\133\174\028\017\127\159\234\130\011\046\248\206\119\190\035\077\056\100\197\010\196\111\140\018\120\074\064\128\074\193\073\026\007\114\014\066\071\202\041\140\203\003\049\076\209\068\240\120\228\070\101\212\012\042\179\120\097\152\197\162\145\211\192\072\008\095\169\001\012\073\196\132\074\129\238\045\089\068\068\137\120\009\130\199\160\050\156\175\100\079\211\062\028\040\053\008\098\238\018\196\060\102\243\044\171\218\075\155\015\086\072\192\127\195\013\055\216\087\147\032\109\243\036\231\163\093\254\187\065\048\207\237\249\077\078\073\221\043\012\022\127\179\116\246\236\217\086\126\235\185\011\005\203\190\195\130\217\107\243\111\116\244\139\199\097\065\010\112\113\032\023\200\009\050\005\236\179\207\062\102\117\192\163\124\161\149\212\128\089\150\113\115\121\208\065\007\185\194\036\092\037\006\032\065\142\000\167\021\108\068\233\235\240\195\015\215\181\028\065\032\013\237\068\170\067\007\087\000\253\163\164\115\005\149\163\064\026\117\161\123\221\117\215\157\121\230\153\031\254\240\135\125\221\144\032\044\066\190\239\058\175\121\037\137\184\184\229\049\158\180\089\224\082\241\169\023\049\025\098\117\228\017\226\113\170\028\175\007\248\083\184\070\248\013\219\118\240\222\193\252\055\012\006\067\016\027\006\141\137\168\090\026\015\011\075\245\248\082\038\184\034\204\055\057\133\047\047\241\021\239\073\013\252\038\177\010\107\041\195\253\153\253\243\079\127\250\211\155\111\190\025\027\158\037\075\150\220\114\203\045\150\068\051\159\132\162\040\172\132\074\243\208\150\254\109\237\159\020\096\074\155\249\082\134\009\121\212\081\071\185\065\144\047\052\049\189\095\245\170\087\253\241\031\255\241\007\062\240\129\223\250\173\223\146\080\140\023\101\204\103\051\220\148\198\137\071\166\144\038\128\088\115\094\094\032\016\042\034\104\143\120\208\081\122\012\104\165\070\166\032\144\014\250\213\209\161\135\030\106\175\241\219\191\253\219\182\048\222\202\017\244\015\196\020\101\005\160\003\241\106\080\073\085\033\004\136\206\087\146\130\028\122\234\169\167\126\230\051\159\057\235\172\179\206\059\239\188\203\046\187\076\238\224\046\073\086\052\138\073\150\006\162\161\094\016\081\034\166\048\022\015\112\059\004\167\160\149\163\013\089\060\014\045\091\217\065\045\023\139\081\220\226\091\224\198\024\120\068\120\133\001\140\040\032\170\026\244\075\017\191\105\051\191\137\096\177\203\117\220\133\016\205\242\130\117\207\198\193\189\163\015\019\150\065\132\107\057\215\055\082\131\052\193\135\006\073\025\099\195\177\054\008\238\011\237\002\156\035\028\254\223\250\214\183\254\143\255\241\063\124\119\120\221\235\094\103\170\171\055\063\189\050\039\053\180\116\075\001\120\062\248\193\015\190\251\221\239\182\137\144\164\072\051\141\237\059\112\090\225\171\052\097\146\155\204\038\060\200\020\067\033\059\120\005\094\069\118\080\019\132\026\109\245\037\077\072\079\140\213\181\183\018\019\196\190\195\054\132\122\225\021\058\176\072\025\143\067\075\202\083\146\189\001\052\096\019\117\206\104\014\023\174\099\190\245\173\111\157\113\198\025\231\156\115\142\047\029\030\111\187\237\054\215\144\210\174\182\092\202\183\248\043\168\172\232\041\098\092\030\048\193\185\093\105\188\096\104\219\214\201\194\011\035\042\188\240\201\037\162\092\027\131\161\210\026\024\109\140\065\012\103\060\042\213\040\095\082\224\040\096\056\032\194\118\094\114\131\096\254\115\154\236\096\149\227\052\143\130\216\105\226\250\235\175\199\128\083\232\251\250\227\176\173\210\035\103\146\016\175\208\246\240\110\001\204\124\211\076\105\182\123\235\202\208\117\131\105\105\078\218\071\128\249\025\115\201\232\000\057\082\128\105\108\200\108\197\227\095\214\160\131\161\052\135\137\114\072\145\038\200\193\166\011\147\092\162\145\044\148\001\053\080\189\082\233\173\116\032\083\016\011\018\065\064\154\080\073\148\212\099\055\161\011\187\021\058\207\153\051\199\103\014\071\015\169\077\242\210\047\115\248\135\110\195\194\171\000\003\131\033\030\163\140\026\166\073\160\182\093\206\026\095\254\242\151\125\233\184\250\234\171\029\223\220\074\168\244\042\216\162\236\108\024\053\083\229\040\030\168\220\142\199\100\231\106\209\133\030\022\173\189\131\024\013\024\114\009\194\238\087\180\001\162\026\009\066\131\135\020\195\175\084\163\124\009\066\056\134\213\225\007\110\145\023\036\005\190\082\070\106\112\172\176\119\176\107\016\211\152\113\242\173\145\000\131\225\145\016\014\004\111\077\099\039\127\115\210\076\054\229\204\061\050\177\145\102\039\178\098\197\114\146\087\173\092\185\090\055\043\087\058\182\120\092\186\244\249\167\158\122\242\177\199\150\184\016\125\224\129\251\239\185\199\061\198\221\011\239\190\251\238\187\238\146\134\164\009\060\122\148\077\228\026\243\217\161\131\112\048\189\065\178\000\132\212\163\178\130\071\149\145\044\034\077\208\074\082\144\026\034\071\200\023\160\070\061\085\237\083\168\170\116\055\097\043\225\084\228\076\132\033\236\098\218\080\224\167\152\210\043\101\000\013\124\194\051\128\240\088\129\201\204\116\037\097\243\037\017\011\075\012\021\155\190\160\098\158\034\070\242\000\167\005\184\046\120\086\174\092\137\150\208\195\129\081\198\171\040\095\220\059\008\071\195\038\059\200\040\006\192\163\081\089\186\116\105\240\041\053\134\032\148\083\168\060\096\042\218\044\240\021\200\011\104\057\194\151\096\001\045\029\024\018\156\085\137\000\053\225\076\132\013\194\009\039\156\096\078\154\111\134\074\094\094\177\124\185\067\184\043\253\179\237\176\079\251\210\025\095\250\210\105\095\250\210\151\078\059\237\244\211\078\251\226\023\191\248\133\047\124\225\212\083\063\123\242\201\167\252\219\191\125\242\099\031\251\216\223\255\253\071\062\248\193\015\253\229\095\254\213\159\127\224\003\127\244\199\127\252\135\127\248\135\023\094\112\190\028\097\019\046\185\024\083\017\096\223\097\063\098\043\033\083\040\043\084\143\008\080\079\007\169\068\154\000\042\085\187\009\233\064\082\048\243\065\166\080\074\025\042\101\025\252\228\235\072\169\230\229\047\127\249\027\223\248\070\027\010\041\131\004\149\108\172\192\234\064\212\116\210\106\120\006\040\012\241\168\004\062\225\085\064\072\040\106\002\131\154\071\229\084\057\138\007\184\183\122\043\060\196\039\031\086\053\131\136\214\222\193\107\030\015\024\099\009\066\009\082\139\193\024\212\032\152\149\131\234\055\193\227\038\234\178\178\061\008\037\071\057\071\184\110\000\217\129\211\031\125\244\209\159\255\252\231\242\044\029\141\007\030\225\110\037\087\162\185\090\009\222\090\120\125\053\180\069\055\045\109\034\188\146\089\030\126\232\097\027\133\157\107\211\118\221\122\231\221\183\219\109\143\237\118\219\107\187\221\246\222\105\175\089\187\204\120\231\014\123\188\099\199\061\254\096\215\189\255\215\030\051\255\096\183\125\254\215\203\102\254\229\062\251\253\205\062\251\127\120\198\254\031\219\255\192\215\078\159\214\251\252\243\103\158\117\182\036\113\229\085\087\249\146\026\251\008\099\170\107\019\213\086\002\116\004\008\160\000\032\002\234\029\016\100\010\250\152\246\114\068\236\038\034\077\216\080\200\017\032\053\068\142\216\107\175\189\208\146\130\052\161\109\008\113\147\042\059\184\188\116\226\192\160\158\165\001\222\000\052\243\017\180\082\006\084\050\031\188\130\168\196\000\104\111\043\120\091\161\170\156\034\070\247\064\229\049\030\014\078\155\000\017\043\054\226\113\104\185\038\059\104\169\141\253\066\005\053\154\065\180\049\060\128\086\175\124\041\131\007\128\007\162\068\240\178\093\003\071\131\185\109\043\225\034\205\210\205\165\156\134\077\137\013\016\017\235\042\061\194\107\094\243\154\087\191\250\213\102\160\217\104\246\114\184\230\216\188\250\251\253\103\222\182\234\217\155\155\043\111\110\172\128\027\087\060\061\247\249\037\103\045\125\226\172\103\031\059\245\201\135\079\122\236\193\047\062\241\208\231\151\060\120\210\067\139\078\122\232\190\127\095\124\223\191\220\119\207\187\247\221\175\055\073\166\037\009\053\078\250\143\255\248\247\079\254\191\059\239\186\243\161\135\030\122\234\169\167\236\004\009\039\217\246\068\158\010\160\193\093\006\032\084\210\193\209\198\036\055\165\059\211\132\211\007\037\237\005\220\083\200\020\210\001\072\019\038\127\064\142\240\168\082\066\033\205\234\034\150\100\025\031\098\093\172\186\191\244\138\081\012\231\022\064\115\005\080\009\013\094\161\001\173\004\053\224\017\027\032\042\168\135\234\113\138\024\163\007\056\013\042\230\136\010\053\080\085\086\196\154\147\133\119\096\204\192\160\070\105\128\017\021\235\020\049\146\007\120\140\175\108\025\108\028\172\249\243\230\205\147\029\248\083\124\139\105\101\052\084\131\136\071\180\217\184\239\190\251\058\171\031\120\224\129\230\158\157\191\153\169\222\102\175\089\022\056\119\170\213\167\023\197\054\043\086\108\187\114\229\054\043\087\110\221\215\187\213\192\128\154\233\237\249\047\005\116\039\073\061\073\106\073\146\181\145\038\137\225\212\112\117\146\052\147\164\127\217\178\171\175\185\250\047\062\240\023\167\159\113\134\203\060\087\122\054\056\182\057\084\213\011\053\232\102\026\043\059\161\006\232\070\153\216\083\072\019\116\051\207\157\059\236\038\168\106\155\032\077\200\017\182\018\032\041\072\013\032\077\040\065\165\028\001\248\163\109\236\038\228\008\031\056\100\025\242\233\192\111\002\012\065\001\106\007\060\066\208\085\073\219\138\158\034\214\163\007\004\155\053\099\168\195\163\011\113\213\034\188\142\113\082\066\012\027\162\245\174\253\079\012\015\054\104\087\076\021\107\060\192\075\220\229\193\154\047\019\219\068\204\159\063\031\161\038\192\117\156\022\008\090\019\175\044\194\062\073\250\144\105\190\217\056\088\174\045\218\230\009\158\060\139\113\073\123\146\164\043\105\165\000\089\000\001\050\130\074\037\168\204\101\132\054\082\018\147\164\039\139\063\201\072\027\181\172\171\150\021\203\150\093\124\209\069\127\244\254\063\188\246\218\107\228\008\071\158\072\097\145\035\218\141\094\044\090\205\210\148\014\032\071\040\077\099\027\138\145\210\132\121\046\077\048\068\058\144\035\064\106\000\105\002\108\022\212\072\034\246\032\132\200\047\178\161\004\225\010\086\147\232\149\043\120\038\250\069\196\035\002\084\082\064\137\230\097\175\162\201\084\185\030\061\192\171\192\195\048\084\108\166\202\139\010\193\170\172\128\033\016\060\104\003\006\136\053\120\105\255\193\045\246\011\142\247\150\101\132\239\006\104\149\188\162\012\055\162\003\106\004\058\218\108\057\254\248\227\109\185\077\030\211\070\106\000\203\181\217\104\074\152\153\120\114\019\053\073\204\255\097\097\228\162\030\145\038\073\096\121\163\145\180\127\030\155\205\178\183\081\244\230\105\061\207\158\121\254\185\143\127\252\019\159\248\248\199\239\184\227\142\007\030\120\192\169\071\022\179\110\012\155\035\008\072\219\063\154\000\101\128\098\116\030\148\038\036\053\187\003\123\004\105\194\134\130\045\145\017\036\133\200\017\065\040\165\003\057\130\028\130\217\123\196\017\071\048\223\181\037\129\124\098\249\010\183\120\171\071\160\003\215\121\165\006\016\106\166\176\222\061\016\158\015\247\070\217\217\133\208\106\061\122\081\033\070\037\030\091\239\218\255\012\122\108\215\077\021\107\060\224\246\241\158\123\238\185\235\174\187\126\245\171\095\221\124\243\205\028\040\160\193\235\240\155\112\143\199\152\003\054\219\111\126\243\155\127\231\119\126\103\230\204\153\166\074\228\005\169\193\228\009\088\190\181\077\146\212\240\152\231\067\161\030\058\235\147\246\111\101\195\145\002\085\022\237\142\081\003\141\098\160\104\157\083\086\046\091\118\221\220\185\031\248\192\007\190\113\241\197\247\222\123\239\067\015\061\228\019\128\211\144\075\019\090\097\199\060\044\210\246\143\009\161\091\149\038\076\108\135\014\115\158\009\210\132\029\144\052\033\071\216\077\084\105\066\142\008\200\026\224\149\227\009\243\193\230\194\117\172\107\151\089\179\102\105\075\184\222\067\013\029\006\029\143\232\041\108\032\015\200\014\177\066\012\235\106\049\246\098\191\056\042\168\053\072\128\000\245\157\180\071\149\083\008\015\240\140\201\118\237\181\215\046\088\176\192\153\194\068\002\149\074\064\004\056\013\052\217\111\191\253\222\249\206\119\186\174\051\085\034\053\088\150\113\154\033\208\102\198\053\017\100\169\140\049\164\097\217\170\137\180\097\203\240\133\211\078\251\171\255\239\255\251\229\213\191\140\131\070\092\070\136\146\162\157\068\090\172\035\252\147\190\240\163\036\109\233\012\078\067\076\136\052\193\156\072\019\177\149\176\095\112\226\144\020\236\029\228\008\233\000\001\042\037\017\013\201\067\219\068\248\008\042\113\068\183\212\144\173\208\222\042\061\114\090\208\030\167\176\238\030\232\116\038\087\243\240\072\050\095\204\014\198\000\006\241\085\130\016\048\232\237\212\099\229\001\219\007\121\193\007\096\238\174\028\085\249\211\000\168\087\226\255\173\223\250\045\011\120\124\194\180\132\090\129\205\049\011\178\041\167\161\089\007\101\123\062\215\210\225\166\058\017\035\163\181\073\248\205\183\105\154\146\076\102\085\077\236\253\015\061\244\047\159\248\151\147\079\058\201\126\039\254\102\132\172\049\202\065\163\106\139\032\016\008\084\146\012\148\183\241\097\072\164\009\091\009\105\034\078\028\178\064\149\035\164\009\057\002\036\008\180\122\251\014\110\225\037\169\193\135\027\105\194\197\004\081\122\081\025\064\131\190\148\083\088\007\015\012\223\148\255\097\248\119\073\242\098\118\008\014\067\018\132\210\144\000\002\130\136\210\227\020\006\121\032\060\163\052\091\188\226\198\010\030\229\005\143\166\205\043\095\249\202\119\191\251\221\110\034\077\030\115\195\140\050\025\204\174\152\108\081\018\002\090\213\146\118\146\064\173\027\072\211\251\026\025\105\210\040\203\084\185\108\197\079\175\184\226\079\255\244\079\207\057\231\028\155\008\123\159\049\030\052\214\200\073\146\180\253\163\051\176\026\164\057\022\065\108\037\216\203\076\199\013\091\009\243\223\054\065\082\000\009\002\228\008\080\041\069\242\015\097\062\103\028\217\254\097\038\036\105\255\042\205\049\180\043\214\244\027\244\084\185\094\060\080\057\121\144\180\223\200\014\006\000\130\003\097\212\149\213\035\017\030\059\043\227\213\084\201\051\192\015\074\129\014\008\143\220\005\065\123\148\020\222\255\254\247\251\126\105\105\053\115\076\033\187\107\051\042\092\218\089\070\147\129\114\130\217\065\167\186\011\016\021\007\203\120\140\178\076\210\085\073\145\038\233\242\165\075\191\250\213\175\254\217\159\252\201\013\191\250\213\162\069\139\150\044\089\226\139\134\235\213\177\028\052\066\148\082\119\064\255\128\100\039\229\153\222\012\004\073\048\142\027\210\132\173\132\043\009\025\065\142\144\026\000\225\081\037\159\016\037\197\056\118\217\071\240\018\090\077\005\093\012\011\157\170\175\216\166\136\209\061\192\087\129\096\235\164\163\166\179\124\049\059\224\139\023\065\136\170\032\162\210\099\192\099\103\189\199\041\132\007\184\005\208\028\133\000\132\076\161\198\173\219\239\254\238\239\190\239\125\239\019\244\104\051\193\130\105\254\072\013\230\064\196\055\254\010\154\064\087\230\163\132\063\199\129\162\012\230\052\254\136\146\124\008\122\205\118\164\157\119\202\164\245\215\042\106\073\250\232\227\143\127\244\031\254\225\051\039\159\236\131\139\131\198\147\079\062\089\221\086\174\105\053\182\063\232\076\223\066\140\000\000\016\000\073\068\065\084\175\035\200\219\063\105\066\250\099\166\028\033\027\142\148\035\236\035\228\008\009\066\238\144\074\120\076\067\251\008\057\194\183\079\173\194\141\234\105\161\139\128\074\132\190\148\234\167\048\097\015\140\226\192\023\179\003\233\248\032\008\037\215\043\003\006\003\161\004\068\176\033\166\016\030\224\144\010\081\163\228\043\129\110\109\124\195\027\222\240\123\191\247\123\135\030\122\168\245\083\184\155\003\230\140\212\224\045\039\107\168\196\143\008\104\232\113\220\185\065\155\118\090\040\091\179\222\195\026\148\237\223\154\135\033\127\052\018\007\141\116\197\178\101\063\250\201\079\254\228\079\254\228\226\011\047\122\224\254\214\039\079\009\194\101\074\204\201\033\141\070\171\008\019\148\237\020\145\051\051\114\132\091\009\134\051\095\126\228\007\199\007\025\129\115\164\006\155\008\064\168\113\012\177\245\208\022\003\143\029\126\248\225\142\039\036\016\200\014\029\035\148\129\078\058\106\038\125\185\233\021\228\070\008\061\016\016\244\208\114\077\118\224\229\010\034\053\104\177\011\209\038\106\208\100\001\098\010\149\007\194\099\225\150\112\148\073\005\024\132\251\059\223\249\206\183\188\229\045\022\067\179\194\220\136\093\131\009\096\218\004\179\018\167\178\019\173\026\255\140\019\195\038\020\138\001\225\033\044\180\013\058\074\111\139\052\077\210\196\221\228\023\191\116\218\255\250\239\127\112\211\175\127\253\212\083\079\173\090\181\106\232\169\036\154\172\181\076\219\063\125\005\004\146\025\046\039\086\057\194\156\151\035\220\077\130\028\033\059\004\228\008\143\246\017\252\067\001\014\060\241\196\019\015\056\224\000\114\116\202\171\128\144\062\148\110\212\226\017\061\133\049\122\192\112\087\156\104\168\030\007\017\195\100\007\028\070\194\224\026\075\240\056\133\209\061\016\254\229\049\064\071\188\090\039\221\065\058\077\216\033\207\156\057\083\184\155\015\042\077\015\169\193\108\193\028\126\174\132\171\001\143\069\123\241\159\192\189\067\051\089\115\180\032\100\016\040\054\168\230\055\030\157\053\218\077\187\178\250\179\207\062\249\193\015\125\104\241\226\197\203\150\045\179\125\088\075\195\223\144\050\204\003\139\152\025\096\245\160\028\033\099\242\140\004\033\011\072\010\018\132\236\000\104\123\007\201\084\239\210\132\203\202\019\078\056\193\025\132\052\238\149\020\212\163\003\195\244\058\085\053\102\015\140\226\195\086\118\136\215\074\002\099\020\149\104\003\233\196\136\000\131\161\156\194\176\030\008\231\112\026\031\162\149\002\250\152\099\142\121\215\187\222\037\065\136\117\139\164\064\175\082\131\183\152\001\103\037\048\104\037\068\101\163\061\093\131\030\099\089\127\225\175\096\007\063\081\122\009\186\042\205\046\074\086\143\131\136\254\098\160\153\229\238\038\031\124\224\254\245\146\029\066\126\104\066\025\144\035\228\071\011\143\068\105\039\229\022\070\142\216\105\167\157\164\003\057\130\187\002\018\004\168\212\214\038\002\125\196\017\071\196\039\079\053\172\032\217\014\002\060\162\167\048\070\015\116\186\203\016\136\198\145\026\190\152\029\012\091\128\187\131\048\126\157\217\065\072\145\027\024\073\220\075\182\158\115\216\030\251\112\129\254\182\183\189\045\254\042\164\224\246\104\215\224\090\206\072\072\184\006\035\220\203\147\154\116\162\170\073\091\127\073\050\153\192\222\097\171\124\216\179\069\103\039\107\167\251\219\119\155\125\253\253\230\228\184\062\094\172\085\052\003\195\118\049\038\071\240\006\159\072\016\242\166\236\041\135\242\149\125\132\068\032\065\196\062\002\173\198\091\187\024\174\059\246\216\099\109\034\034\044\237\032\064\154\008\231\175\181\247\223\100\152\122\106\121\192\118\076\118\054\046\208\122\254\205\127\050\181\021\140\153\193\139\146\199\249\093\203\223\228\079\048\015\170\153\122\228\001\238\146\026\164\000\225\251\158\247\188\199\081\249\224\131\015\230\122\017\047\178\069\191\105\096\193\020\223\060\012\163\187\177\040\090\127\179\113\002\217\097\218\154\189\003\141\090\160\149\065\108\081\227\251\167\181\105\233\091\181\186\175\175\143\081\132\140\175\245\218\184\217\014\194\012\228\008\110\225\028\046\226\061\105\148\199\164\084\025\193\062\066\106\144\038\148\104\251\011\073\097\245\234\213\232\087\189\234\085\246\017\106\088\039\065\172\119\013\215\102\193\022\242\158\219\185\151\255\013\007\147\162\068\084\120\113\239\224\157\168\053\090\049\102\030\141\132\150\021\171\026\240\104\048\000\241\082\003\243\135\069\229\007\167\137\119\188\227\029\046\026\246\223\127\127\065\044\208\007\165\006\205\057\089\089\053\233\036\042\175\230\089\107\011\048\202\037\066\103\171\078\186\059\107\013\104\050\242\237\131\222\065\147\145\116\240\042\154\055\250\007\076\060\211\175\093\179\158\011\189\007\242\246\079\210\020\105\130\085\142\176\032\201\017\054\017\114\004\031\074\013\034\088\137\150\050\100\144\149\043\087\242\170\155\136\195\014\059\076\171\161\154\133\228\161\245\083\053\060\032\198\000\001\060\204\225\225\046\165\154\065\120\113\239\096\152\196\013\068\130\240\104\221\192\173\070\089\129\104\168\030\095\058\004\247\085\096\117\056\065\009\030\057\218\055\075\167\009\007\099\065\236\166\205\202\038\208\109\155\029\208\004\049\175\242\036\016\130\127\036\144\006\216\048\180\190\034\248\099\060\168\037\233\040\236\209\053\249\120\208\128\024\138\214\206\033\073\154\141\070\112\070\057\148\109\221\107\040\000\140\005\254\113\208\000\027\004\033\107\254\203\173\220\200\153\082\131\004\001\008\143\234\241\203\017\136\215\191\254\245\054\104\149\038\164\129\183\081\086\245\083\068\229\001\158\169\104\089\088\136\074\205\042\161\170\175\136\214\082\227\005\135\130\140\096\144\170\210\210\225\149\199\138\123\195\005\074\213\197\164\037\184\034\080\105\024\222\016\199\078\019\111\127\251\219\095\247\186\215\029\120\224\129\150\056\049\061\040\053\240\033\247\014\106\094\201\009\034\164\005\029\043\118\255\218\254\181\168\096\238\044\107\213\067\058\076\154\240\093\130\228\232\072\009\021\123\039\145\183\111\061\154\205\086\118\024\137\167\147\127\221\232\036\077\083\206\009\008\063\153\084\062\149\085\005\174\240\181\137\224\079\073\065\106\008\160\085\074\034\116\227\252\087\188\226\021\071\029\117\148\061\005\053\212\068\073\038\144\233\113\010\035\121\128\063\057\144\151\248\106\088\158\193\217\065\028\027\033\037\104\035\151\043\171\150\188\015\106\160\170\124\137\016\012\015\176\029\194\106\254\017\154\191\255\251\191\255\218\215\190\246\160\131\014\018\199\022\052\030\023\172\194\215\091\177\206\147\049\000\085\171\104\059\168\236\124\107\014\123\059\129\236\048\045\091\147\020\252\209\041\144\052\106\228\121\107\184\209\192\022\037\030\200\243\060\203\094\124\213\051\109\186\087\003\003\125\120\000\189\017\064\013\200\219\063\078\227\058\057\194\038\066\142\144\106\057\214\238\076\230\021\208\001\057\130\171\169\167\149\033\112\203\163\009\061\213\240\158\018\237\021\032\166\048\172\007\108\199\004\170\161\135\097\025\050\238\011\224\128\246\232\228\018\004\112\177\093\071\056\125\216\198\047\169\074\222\008\008\062\096\059\231\190\245\173\111\125\203\091\222\178\215\094\123\161\069\173\032\182\220\241\120\149\026\184\020\194\195\154\140\004\012\094\041\003\058\242\056\145\091\201\084\090\208\052\033\001\090\212\011\255\184\233\044\219\127\141\034\042\012\180\193\069\151\237\095\154\174\105\152\036\105\127\095\095\226\100\081\180\095\180\011\143\027\001\105\251\199\093\064\061\129\007\157\155\008\025\001\248\153\183\101\010\180\196\129\211\041\195\007\142\087\190\242\149\042\067\079\090\007\065\100\016\083\101\120\160\242\012\039\243\164\112\069\240\082\032\120\170\114\205\138\225\029\038\142\150\020\004\141\018\077\144\044\046\208\189\141\006\008\108\104\175\148\047\065\048\028\172\105\179\103\207\118\209\224\219\196\161\135\030\042\076\229\005\145\106\161\019\205\022\061\126\227\067\190\002\078\131\181\250\010\015\004\127\100\159\190\246\151\197\181\054\236\100\168\199\157\065\103\213\011\116\251\088\241\226\107\125\049\036\094\234\174\217\108\125\037\209\123\146\150\003\205\001\245\003\003\141\065\063\095\055\215\010\077\136\034\176\018\078\212\184\064\049\016\126\148\225\070\009\098\218\180\105\028\110\071\198\195\177\131\144\005\068\054\240\188\026\174\214\047\250\232\163\143\158\057\115\166\038\122\015\053\198\213\245\075\138\153\111\165\084\103\052\222\227\106\062\031\106\254\224\236\128\207\192\000\002\100\010\003\227\081\075\030\039\002\208\047\077\240\064\024\062\103\206\156\247\190\247\189\190\077\136\069\121\193\022\087\014\142\045\067\164\006\030\227\061\190\130\104\178\214\018\103\133\162\189\200\175\088\243\031\122\090\107\211\023\025\186\094\036\215\066\153\078\016\022\181\251\109\237\029\060\214\242\090\150\181\190\152\172\094\181\124\233\210\165\207\062\251\236\211\079\063\253\084\251\135\128\054\057\076\241\228\147\079\170\197\240\220\115\207\045\095\190\220\007\047\169\100\098\105\034\244\201\218\191\060\207\197\049\175\074\187\146\047\063\243\054\159\075\016\032\065\040\061\074\028\250\018\171\062\118\206\152\049\035\140\103\078\016\083\101\229\001\190\013\218\212\230\061\107\191\236\080\085\198\171\170\092\115\178\104\015\068\171\048\024\160\129\018\052\051\030\030\171\006\047\113\143\011\196\119\189\235\093\014\020\242\066\236\111\101\095\046\138\212\096\213\226\116\126\003\174\131\202\111\163\019\193\169\052\006\202\178\189\107\232\111\175\231\163\055\028\244\182\053\173\007\085\141\225\081\143\250\197\104\112\205\177\052\073\209\069\179\092\178\100\201\131\015\062\184\104\209\162\251\218\191\123\071\254\221\115\207\061\094\226\090\180\104\209\003\015\060\240\200\035\143\060\249\228\147\210\196\186\252\125\042\090\001\079\130\004\193\183\177\137\224\237\072\016\054\011\226\091\118\000\059\008\155\011\249\078\086\242\177\083\142\144\041\090\086\140\255\102\087\171\045\030\146\194\113\199\029\199\111\017\174\070\159\171\135\090\221\218\059\120\017\192\100\036\228\130\040\061\218\158\241\178\177\137\150\162\007\130\126\169\149\124\034\004\223\240\134\055\184\104\240\109\066\092\202\020\150\044\011\154\101\205\226\198\075\157\190\230\210\113\185\008\127\005\078\238\118\242\127\241\028\048\086\073\173\225\028\043\239\026\062\163\156\166\153\129\142\103\179\169\089\052\200\121\244\225\071\158\120\226\137\123\022\222\051\255\182\121\183\222\122\203\109\183\222\058\127\222\188\219\110\185\229\214\155\111\190\249\166\155\002\183\220\124\243\173\055\223\114\203\175\111\186\229\166\155\225\166\027\127\253\235\095\221\120\227\013\191\154\063\111\254\194\133\011\023\047\094\076\194\178\101\203\122\123\123\205\091\070\069\023\099\047\195\033\052\004\097\201\195\252\044\178\249\156\231\249\223\136\200\017\162\028\208\178\134\038\253\253\253\007\028\112\192\225\135\031\046\095\104\056\246\238\094\010\156\049\010\179\102\205\250\237\223\254\109\062\228\213\081\092\036\012\090\062\225\083\192\023\208\198\100\080\170\084\162\049\161\137\134\160\149\091\030\216\024\024\106\154\136\180\101\112\209\016\129\088\109\025\170\212\192\075\188\055\082\243\161\002\007\213\068\195\040\045\224\237\093\192\184\211\067\252\255\089\012\146\060\210\099\244\149\102\105\045\207\147\180\181\095\200\211\052\075\214\252\215\231\126\250\243\159\127\250\211\159\254\167\127\254\167\015\126\248\067\127\253\215\127\243\087\127\253\215\127\249\087\127\245\215\127\251\183\127\251\161\015\125\232\195\031\014\124\240\067\031\250\219\015\125\240\131\255\247\195\031\122\001\030\255\207\095\253\229\007\254\226\003\255\252\161\191\191\244\027\223\184\239\190\251\030\125\244\081\155\008\075\186\004\193\174\145\148\025\165\062\109\255\248\086\040\218\065\072\016\124\110\179\102\019\097\020\036\005\035\018\144\041\164\012\012\142\054\118\118\054\017\214\182\144\172\121\133\182\188\150\189\241\106\011\043\089\199\210\048\042\104\165\199\040\017\224\240\117\216\097\135\113\099\021\180\042\135\226\197\236\064\034\224\054\006\085\105\080\249\026\170\150\157\125\084\149\091\018\193\192\010\097\023\111\028\113\196\017\046\026\094\243\154\215\236\189\247\222\002\081\080\090\151\004\168\117\076\188\090\211\240\064\052\140\086\227\042\053\196\175\076\211\086\225\222\193\192\172\110\174\249\207\207\123\053\070\140\253\222\129\064\061\201\245\069\179\232\235\239\243\145\099\231\109\183\111\150\173\011\143\183\239\184\219\095\236\053\235\207\246\218\239\031\247\061\248\163\051\015\248\199\089\007\254\227\190\135\252\237\140\003\254\102\159\003\062\190\223\161\255\186\255\161\255\239\128\195\079\058\232\136\147\015\058\252\130\035\103\031\113\240\033\061\245\174\238\090\189\150\036\245\036\237\202\242\237\166\109\213\211\040\239\092\112\251\041\159\254\244\251\255\251\127\191\246\186\107\031\122\232\161\103\158\121\198\041\099\221\019\132\016\229\237\238\238\110\158\055\243\141\130\253\130\140\032\047\024\023\064\024\029\060\250\082\239\067\134\187\055\198\022\069\081\186\152\069\189\052\096\112\043\112\026\136\207\048\093\086\157\061\123\054\095\057\169\153\236\094\005\103\188\237\044\051\015\222\041\049\001\017\096\135\172\025\216\164\025\134\200\014\156\139\019\048\163\149\091\036\024\024\008\235\184\226\136\035\142\240\121\226\181\175\125\237\062\251\236\035\224\132\163\125\132\188\203\045\162\144\151\248\013\058\091\069\219\113\149\209\060\228\052\027\205\052\201\026\107\086\241\100\236\191\124\012\019\064\071\033\176\112\138\072\164\133\214\014\197\074\186\245\178\231\063\178\223\254\143\029\124\200\119\159\127\234\180\071\030\248\210\035\139\062\121\255\221\255\239\193\123\063\249\192\061\159\188\255\174\083\023\223\251\217\135\238\253\196\162\059\255\233\190\059\063\122\239\029\127\183\240\246\255\187\240\142\247\221\113\123\179\150\245\014\244\167\245\188\172\231\069\045\043\242\116\197\234\085\207\247\247\014\212\243\093\182\221\174\185\116\245\063\126\244\031\207\253\202\215\034\065\088\108\028\097\038\022\060\212\006\254\001\062\231\121\193\109\020\036\008\059\100\227\034\047\084\144\032\228\142\190\190\190\152\009\062\057\107\021\086\079\172\247\104\187\025\149\149\175\232\140\054\169\195\003\092\119\212\081\071\217\056\152\215\124\168\018\048\096\027\138\086\118\080\235\053\224\003\130\192\172\136\210\024\160\241\004\182\108\231\086\214\033\128\201\135\028\114\200\123\222\243\030\159\202\228\090\033\040\016\183\217\102\027\065\025\169\129\139\120\140\235\000\243\186\131\028\208\117\150\228\105\218\154\183\227\146\057\074\062\033\022\134\074\075\037\134\036\113\203\255\149\163\143\254\247\069\247\237\126\247\093\073\059\107\012\229\028\090\243\023\123\238\121\231\029\011\106\105\214\232\031\168\103\181\105\093\061\062\121\228\093\245\102\082\216\134\172\024\024\072\166\077\155\222\087\191\232\155\223\248\210\023\079\115\085\233\136\225\014\098\194\009\130\002\105\251\199\231\060\047\184\141\130\040\151\172\141\139\172\029\167\140\200\017\049\088\118\016\006\203\124\144\047\120\053\018\162\230\064\018\129\091\030\194\076\037\176\142\201\128\230\118\143\008\095\220\156\044\184\174\086\171\113\227\040\126\024\156\029\052\144\011\160\147\032\136\220\000\233\065\108\169\037\087\242\035\051\133\157\059\200\247\189\239\125\018\173\176\019\094\022\034\169\065\061\135\008\077\158\141\032\027\197\191\099\247\018\033\021\040\048\045\159\214\108\109\243\199\046\160\197\153\181\167\122\139\026\242\015\139\064\117\148\136\052\203\068\071\173\172\207\076\146\175\207\057\250\013\183\220\162\114\236\056\255\200\035\047\127\248\225\238\044\111\148\069\163\217\044\138\178\127\160\063\190\098\022\205\130\045\069\089\172\236\235\093\094\244\078\047\187\047\255\233\079\046\189\232\146\199\030\123\204\087\082\075\122\049\230\004\052\084\031\146\129\231\249\223\040\024\011\035\098\092\140\142\049\146\020\100\007\169\092\137\086\047\031\097\056\254\248\227\247\219\111\063\173\152\175\119\229\080\201\091\094\013\075\249\010\016\130\202\188\118\166\224\010\241\236\116\102\142\243\161\183\048\172\237\107\178\131\119\028\135\053\064\010\191\043\053\035\215\038\013\003\084\062\085\239\113\011\003\163\032\108\204\243\060\254\237\009\087\223\214\037\176\131\021\106\118\082\220\202\051\220\021\208\100\221\253\016\066\148\001\002\243\052\235\031\255\020\202\075\077\199\140\180\232\073\122\246\076\006\062\126\228\236\215\222\058\190\212\240\204\001\007\252\211\252\249\139\147\164\079\010\075\211\122\087\189\076\202\102\089\138\022\081\200\051\101\089\246\247\245\245\055\123\251\139\254\229\125\043\166\015\100\231\093\116\193\245\215\206\245\165\115\197\138\021\150\116\012\099\086\116\048\099\120\073\047\096\044\140\136\113\049\058\198\072\130\016\250\080\037\008\123\010\039\026\060\046\041\157\013\181\213\053\061\007\011\221\082\158\025\008\172\097\038\112\145\071\132\026\039\172\223\105\255\063\176\073\169\252\102\178\123\005\094\013\139\053\217\001\007\016\164\129\102\145\026\148\149\019\088\166\000\000\016\000\073\068\065\084\042\101\122\126\183\061\067\019\129\039\008\244\022\006\030\004\070\113\194\009\039\156\240\223\254\219\127\219\127\255\253\229\005\225\037\236\164\072\033\200\039\050\046\039\192\250\245\003\105\064\044\208\161\172\101\253\205\034\233\248\215\031\084\174\021\181\017\018\010\201\048\168\121\061\205\087\052\087\158\184\231\140\063\154\063\111\208\171\181\062\254\233\115\207\061\216\098\106\073\109\253\083\036\146\066\179\209\224\028\046\242\198\035\067\208\093\061\093\141\164\088\153\244\214\250\026\255\254\169\079\186\128\120\246\217\103\077\087\012\216\038\012\157\130\046\064\196\154\252\070\199\024\197\041\195\174\065\130\008\200\023\070\080\062\050\172\199\028\115\140\004\049\225\078\055\151\134\060\083\169\042\015\114\117\004\182\051\133\141\131\233\204\093\156\198\033\188\087\113\014\037\090\217\129\044\192\007\070\023\180\212\222\208\034\250\251\251\057\157\187\163\049\078\008\122\139\044\037\130\223\253\221\223\149\026\246\221\119\095\169\001\212\072\142\145\110\057\135\151\120\000\214\175\249\004\146\028\032\057\207\178\249\121\119\153\142\124\084\192\052\004\035\221\074\010\142\212\215\202\172\053\220\209\200\083\089\228\206\020\159\031\223\126\163\213\250\218\057\115\110\125\250\233\188\125\047\146\165\173\227\201\064\099\064\020\234\002\220\115\042\243\204\215\085\234\167\121\235\244\082\107\148\165\015\167\253\207\175\254\236\041\167\062\254\248\227\203\218\255\197\074\077\090\226\214\225\031\029\101\237\159\113\017\174\145\032\140\151\081\147\020\028\046\002\104\089\067\036\227\117\133\036\233\155\024\124\178\014\061\111\054\077\153\009\028\101\023\252\250\215\191\222\135\094\231\044\190\226\049\222\080\015\035\025\243\098\184\096\229\050\208\076\099\136\004\161\177\028\081\101\135\145\004\109\025\245\108\063\238\184\227\100\135\089\179\102\137\048\144\104\121\051\092\193\057\188\196\033\176\033\236\037\022\116\001\181\090\189\244\209\162\230\067\225\056\186\170\023\035\222\075\010\145\023\004\181\050\078\045\173\015\020\253\039\207\158\179\245\067\015\189\080\063\182\063\179\236\079\231\205\123\040\073\155\038\252\111\222\155\242\015\253\251\250\251\221\059\184\135\048\249\077\200\213\171\086\023\101\051\175\119\021\121\182\195\046\059\223\118\199\188\249\243\230\199\007\078\107\218\216\186\028\141\075\143\208\246\088\077\208\074\016\082\121\149\032\098\251\032\071\072\016\070\211\070\088\048\187\072\082\051\154\208\045\226\029\183\064\152\194\039\206\020\007\031\124\176\120\174\130\185\122\027\060\067\203\053\217\001\031\084\046\230\101\075\037\016\196\155\134\089\118\064\107\143\086\098\006\196\134\199\006\236\129\009\129\232\131\249\062\091\190\237\109\111\115\163\043\146\220\114\217\052\113\043\195\057\196\091\232\228\143\086\235\171\036\153\040\101\160\076\074\027\114\139\175\202\177\163\054\194\095\190\038\179\044\093\010\144\215\074\013\022\246\129\162\239\216\158\029\254\235\194\187\198\046\060\056\255\243\208\195\238\046\138\188\222\078\091\118\032\245\172\244\194\022\034\207\147\044\077\210\036\203\115\247\145\136\052\207\068\139\123\074\187\250\070\127\127\163\040\151\015\172\174\245\229\095\061\227\107\079\061\245\212\242\229\203\229\014\012\201\058\255\088\007\070\071\122\018\174\226\086\066\143\004\225\076\033\017\136\094\105\066\130\048\166\244\049\160\047\127\249\203\119\223\125\247\232\089\219\138\064\067\060\078\230\146\146\129\080\018\029\132\178\044\091\003\162\006\184\215\163\140\233\164\236\030\205\093\012\090\048\115\020\119\097\000\077\070\066\214\249\066\027\224\095\238\227\226\000\090\142\183\049\227\104\178\116\214\217\100\115\167\249\040\044\146\083\229\005\031\047\015\058\232\160\237\219\191\206\212\192\045\192\124\216\064\038\135\026\074\208\151\189\058\221\198\219\151\221\124\103\147\044\075\137\138\154\182\230\237\184\201\210\122\218\227\076\113\202\033\251\102\189\189\241\118\140\101\223\110\187\253\203\029\183\247\100\185\111\018\154\100\101\154\039\078\051\082\089\146\038\062\099\022\253\062\109\214\106\105\154\082\094\032\033\176\037\101\034\034\245\221\232\047\182\217\102\250\237\247\204\191\125\254\029\190\110\174\251\237\067\075\120\251\031\029\129\078\217\171\047\161\107\026\008\090\089\094\220\074\013\001\009\194\176\174\092\185\210\091\071\012\183\116\090\113\056\025\136\000\122\179\000\109\217\011\136\078\133\227\081\025\118\097\176\230\189\251\221\239\222\123\239\189\217\110\058\027\151\090\123\140\240\116\054\028\074\103\081\133\015\008\210\076\227\202\191\156\200\209\186\081\207\209\074\252\145\144\084\162\055\059\048\179\066\165\188\144\114\095\245\246\183\191\253\128\003\014\016\076\044\229\071\235\015\063\240\006\183\000\102\013\149\027\014\092\010\220\043\029\215\204\059\039\248\090\123\137\030\115\151\249\111\158\044\060\017\168\053\253\215\040\159\230\105\146\246\054\087\029\190\195\238\175\189\245\102\175\198\133\127\156\062\221\101\100\067\034\104\040\146\102\089\248\136\153\018\081\150\205\102\179\108\022\173\253\073\089\138\147\162\081\020\003\013\157\082\160\213\123\150\201\005\253\003\253\043\251\087\109\149\109\247\205\139\191\237\112\177\238\031\047\244\092\065\095\160\047\048\112\226\214\008\074\016\082\189\049\149\029\236\032\064\130\048\190\142\024\222\090\009\148\033\065\219\032\054\139\146\087\041\204\082\064\000\162\130\071\086\008\036\037\243\223\244\166\055\029\120\224\129\092\193\088\158\049\058\024\048\043\049\140\130\053\217\001\007\086\013\180\052\031\136\224\092\169\129\056\165\124\131\065\162\181\192\034\104\166\220\124\017\150\042\025\034\166\025\123\226\137\039\254\254\239\255\190\187\006\174\132\072\013\172\230\010\062\001\204\176\065\077\166\140\225\012\232\168\044\139\102\179\081\102\047\014\144\202\181\034\031\124\178\040\203\178\117\019\241\162\242\069\145\021\153\141\195\201\251\236\190\086\105\131\024\150\028\114\232\183\030\120\160\158\102\069\074\106\075\044\006\249\160\044\169\153\233\162\181\133\072\018\068\146\056\095\100\040\068\060\054\006\006\242\090\090\155\094\107\038\201\118\219\078\191\243\222\059\030\091\242\152\187\201\222\222\222\066\014\195\183\062\160\047\048\094\096\088\141\160\000\054\043\182\223\126\123\025\065\130\128\072\016\014\140\018\132\202\087\190\242\149\219\111\191\189\206\169\193\016\068\148\136\201\015\170\086\160\109\216\174\100\075\179\029\009\051\103\206\252\179\063\251\179\057\115\230\008\105\038\115\136\144\054\199\249\007\255\090\145\085\028\132\130\102\026\243\172\236\192\179\036\042\209\069\081\112\107\117\084\171\090\109\118\004\111\210\153\165\065\112\214\107\094\243\154\119\189\235\093\118\013\078\170\192\143\018\034\015\120\197\027\128\089\147\141\003\090\025\090\101\146\182\086\230\178\094\031\087\191\089\059\038\058\155\180\015\161\073\163\209\032\054\077\178\173\166\109\211\072\006\222\054\099\223\067\230\221\150\140\243\247\135\075\150\060\156\164\069\154\056\041\116\054\037\217\035\157\109\193\248\013\161\070\169\178\066\209\206\032\069\163\217\223\132\222\229\203\150\206\189\250\250\231\159\127\222\134\130\110\021\219\186\019\006\011\140\026\080\198\124\152\054\109\090\036\008\059\008\049\044\065\216\062\128\129\182\121\145\026\142\060\242\072\143\186\166\051\032\038\063\216\072\085\041\032\092\141\006\106\171\143\026\132\212\240\206\119\190\083\120\075\130\140\229\007\014\049\187\189\010\224\031\029\047\102\007\124\218\024\096\237\249\020\136\147\029\064\130\224\107\111\121\022\027\080\197\035\098\115\004\247\001\019\040\239\048\230\046\215\039\046\121\001\042\039\074\013\012\012\171\177\109\004\208\039\160\047\068\146\164\125\189\253\069\109\124\039\139\172\189\225\079\134\252\216\146\036\169\251\194\044\175\219\056\252\091\205\020\079\198\245\251\238\081\115\022\045\125\190\167\187\071\118\224\189\170\109\091\085\071\160\214\246\033\042\205\118\081\043\120\056\211\091\062\244\040\174\148\189\171\092\167\020\125\003\171\187\211\174\235\175\189\081\118\112\005\224\154\016\091\180\093\047\101\218\254\233\023\204\007\107\155\000\142\004\033\011\128\048\150\038\036\011\169\129\086\106\076\164\232\154\038\090\005\061\153\075\038\082\021\040\073\097\064\024\151\000\218\252\117\143\230\050\146\165\108\231\001\174\016\213\056\181\005\060\107\197\139\217\065\003\208\088\118\032\133\079\013\048\161\198\024\212\024\072\110\117\190\088\171\208\201\207\192\137\140\181\104\188\255\253\239\063\226\136\035\228\005\129\194\076\038\135\019\189\229\010\229\198\183\037\134\220\177\062\031\040\125\099\024\151\002\062\018\172\225\079\147\078\229\203\036\203\210\188\086\148\203\086\060\253\119\135\031\181\195\162\069\107\216\198\246\199\210\089\251\254\237\109\183\062\146\102\043\251\251\146\166\235\197\225\155\153\105\082\131\126\001\001\146\002\086\143\182\241\205\070\179\222\149\117\117\213\155\105\190\245\214\219\205\191\231\182\167\158\124\202\234\221\239\011\232\250\059\092\232\014\244\008\070\016\132\174\096\182\200\057\023\027\101\185\000\204\025\176\168\154\069\189\189\189\178\195\171\094\245\042\145\175\045\255\107\011\232\201\143\078\061\105\110\008\232\108\035\252\135\127\248\135\046\035\077\088\177\109\022\051\147\031\012\007\135\116\054\193\060\010\094\204\014\152\052\003\034\008\034\206\084\225\083\115\070\009\094\113\159\025\197\203\152\169\162\220\076\193\150\125\247\221\087\114\125\197\043\094\017\107\008\003\217\187\201\083\067\248\147\122\169\227\125\081\148\121\030\053\099\044\095\204\014\101\066\008\115\148\073\146\038\137\244\080\154\215\179\146\252\143\158\121\194\227\216\065\135\183\062\253\236\083\121\079\189\171\150\038\195\228\171\084\109\233\058\178\008\153\105\251\039\029\152\117\162\168\112\211\033\036\051\159\083\074\103\146\188\150\101\121\109\160\144\253\138\197\015\044\150\029\112\226\137\182\235\177\108\107\145\102\089\022\241\060\040\065\072\013\114\004\024\125\147\071\134\114\235\180\223\126\251\213\106\181\178\164\231\122\084\100\131\136\010\037\217\024\210\061\066\146\036\070\252\208\067\015\117\160\112\019\185\231\158\123\074\013\230\047\219\213\051\013\127\032\090\173\181\252\141\236\128\091\227\240\038\113\102\139\057\067\186\157\137\140\128\224\068\014\229\089\156\155\053\248\235\205\111\126\179\212\192\028\030\100\038\099\153\044\045\242\064\102\161\077\211\077\104\096\107\164\203\178\072\154\182\236\227\083\163\176\241\127\177\069\172\036\230\036\228\105\173\145\052\254\245\200\217\211\030\123\236\069\142\049\080\159\216\247\224\185\203\159\047\210\180\119\096\032\077\211\188\086\083\118\182\043\010\041\195\060\084\237\186\178\180\101\040\203\214\065\003\097\230\011\074\097\083\020\133\076\161\149\154\174\122\221\053\068\154\100\243\231\047\176\033\149\068\112\038\027\224\215\082\040\165\088\022\033\109\208\013\180\096\182\101\144\020\132\049\032\108\040\140\251\170\085\171\204\043\039\077\138\208\031\016\147\022\212\003\234\041\003\104\144\224\220\175\031\119\220\113\118\013\236\050\109\005\054\207\027\005\081\013\124\130\109\140\248\141\236\160\037\016\193\155\166\010\111\074\171\058\008\200\014\094\025\105\167\116\046\030\099\007\147\144\077\064\184\107\056\254\248\227\093\178\242\160\136\225\065\246\242\096\152\175\220\228\106\167\121\086\036\069\179\054\190\123\135\212\103\197\182\234\097\066\105\022\150\073\154\213\028\043\250\027\003\135\230\211\126\255\145\007\218\239\199\090\220\049\123\206\215\239\093\176\195\086\059\173\110\244\146\102\146\151\069\145\165\085\234\076\211\180\150\038\093\089\218\149\231\173\127\017\075\164\166\105\043\071\224\212\135\244\020\177\228\177\040\154\094\249\232\217\219\219\143\216\174\107\251\069\247\062\232\086\082\190\144\029\052\196\191\222\161\035\200\178\223\072\016\226\217\184\091\024\042\088\033\104\040\000\014\062\248\096\185\099\168\026\132\192\208\250\009\215\144\006\227\106\222\201\095\209\252\006\228\080\219\094\248\127\254\207\255\121\212\081\071\201\122\076\051\073\005\182\212\032\247\101\237\095\213\010\255\088\144\013\098\210\030\140\040\137\145\029\076\030\221\112\159\146\091\141\183\217\229\096\163\187\170\173\038\080\061\078\030\130\086\208\169\015\163\100\086\217\097\198\140\025\140\146\242\214\209\131\157\194\215\133\166\103\005\190\045\237\196\147\178\153\143\239\100\033\059\132\014\118\199\086\205\122\087\183\050\207\204\224\124\070\082\124\225\200\067\235\207\062\023\012\099\041\027\219\109\247\142\121\183\063\145\212\007\210\094\126\075\147\084\043\211\187\040\253\153\164\041\221\236\195\027\101\210\223\116\213\056\208\159\148\073\045\083\233\020\035\129\180\066\139\069\088\179\246\079\228\164\089\218\221\085\107\054\125\064\113\007\209\253\232\067\075\086\173\094\029\123\135\008\113\204\235\029\105\251\071\005\147\191\171\171\139\033\006\221\208\075\016\034\057\038\018\090\120\219\200\136\240\217\179\103\163\053\162\137\114\016\084\174\059\058\101\014\149\054\236\219\168\012\230\160\149\225\052\083\117\183\221\118\123\221\235\094\039\170\015\059\236\048\070\201\020\076\176\180\051\214\091\182\067\180\029\087\217\026\194\206\006\186\132\060\207\195\149\102\014\087\234\137\055\001\193\191\146\189\067\154\061\024\078\109\149\250\086\086\080\185\201\065\025\090\005\208\149\062\039\156\112\194\091\222\242\150\125\246\217\135\019\133\002\003\215\037\185\086\098\215\011\065\079\224\252\102\179\153\119\229\141\164\089\100\131\007\104\244\142\220\059\188\240\031\143\043\147\050\029\048\115\147\050\043\026\253\205\222\057\187\236\241\134\113\254\245\167\015\108\179\253\162\164\081\235\238\234\093\237\076\145\219\206\232\061\203\106\073\154\230\169\188\032\119\101\175\123\221\009\190\153\057\163\189\250\085\175\158\214\053\189\081\052\245\091\203\186\186\243\053\138\248\036\097\191\041\156\234\245\174\178\040\139\162\145\229\012\027\040\242\198\242\213\075\087\174\088\225\045\123\035\208\201\223\016\072\219\063\193\064\013\001\108\206\196\154\103\022\009\003\203\044\160\069\056\101\028\215\237\207\067\013\090\105\170\097\148\121\158\163\227\213\232\229\088\222\134\076\229\032\116\182\237\124\165\222\035\005\148\069\081\208\077\013\028\123\236\177\127\254\231\127\046\053\068\084\051\196\060\173\082\067\158\183\116\214\004\048\143\011\195\004\031\041\208\233\071\179\136\227\228\087\165\100\225\109\158\231\082\236\174\187\238\170\051\090\002\098\018\034\020\163\048\221\088\100\223\248\214\183\190\245\240\195\015\119\166\096\212\100\075\013\006\158\099\001\081\171\215\172\208\014\244\052\031\059\170\047\160\121\094\119\215\080\150\205\214\141\097\081\155\153\036\159\223\117\199\177\203\193\121\245\156\099\174\124\100\241\182\245\173\007\178\102\150\215\250\251\250\090\251\145\036\079\147\162\059\239\078\146\172\171\171\231\029\239\248\221\122\061\055\217\044\080\207\062\247\236\190\007\204\050\181\202\164\200\179\124\160\245\095\175\229\248\053\032\144\255\027\146\071\179\172\213\234\082\076\150\166\141\164\127\213\170\213\210\199\134\206\014\122\095\163\071\154\214\106\053\009\194\208\139\100\241\108\046\073\016\213\014\130\033\171\086\173\058\228\144\067\220\190\103\089\107\118\008\033\109\209\074\114\214\029\033\135\088\032\045\030\131\064\003\186\130\199\170\107\252\080\180\127\024\104\046\041\059\077\188\241\141\111\020\216\022\108\243\081\037\163\214\075\106\208\069\203\126\127\116\130\066\064\039\126\236\238\238\014\063\202\070\178\131\190\149\186\119\092\164\001\133\056\090\091\010\043\181\002\196\100\000\063\086\008\125\100\214\119\188\227\029\007\030\120\032\043\164\006\250\071\088\179\116\050\168\077\007\154\240\185\000\149\032\234\245\174\213\073\163\145\215\066\249\049\150\105\089\182\254\127\172\112\183\015\255\101\049\080\075\179\129\100\224\093\251\030\186\247\130\005\170\199\136\230\054\219\252\207\091\111\126\044\169\173\042\250\123\251\250\250\251\219\255\158\101\154\167\121\038\098\242\164\075\242\121\239\123\223\107\201\021\160\224\172\123\208\065\007\241\167\120\216\101\167\157\086\247\175\044\202\070\205\177\072\134\075\018\225\097\191\073\076\146\080\048\045\154\069\158\219\122\036\105\146\173\090\181\186\209\104\108\132\236\144\036\073\120\152\147\121\152\158\017\216\130\089\060\072\016\001\225\141\193\151\020\230\216\174\027\142\178\044\233\159\036\046\136\091\068\208\030\199\014\253\006\162\009\026\081\150\163\073\195\003\216\002\232\178\253\171\030\233\111\203\240\246\183\191\221\106\119\216\097\135\081\149\254\012\049\079\171\192\022\069\108\209\022\162\225\120\075\099\061\076\019\226\128\116\126\052\228\250\051\157\056\078\247\148\064\200\187\246\096\086\096\009\034\218\083\030\191\086\241\184\201\075\154\000\239\080\204\136\050\193\231\095\014\021\208\108\241\200\046\214\209\025\015\078\216\180\058\083\003\232\035\034\149\093\117\151\124\073\145\142\079\041\123\141\104\081\052\091\135\010\083\057\111\255\135\225\254\174\052\245\246\124\000\000\016\000\073\068\065\084\107\205\231\198\049\138\059\107\159\125\030\076\146\172\158\021\105\051\109\207\240\052\205\146\076\114\072\157\026\086\014\060\255\170\087\189\126\151\093\118\154\051\103\206\203\095\254\114\217\225\152\099\142\177\035\179\033\023\033\051\247\221\055\227\205\246\095\183\230\225\170\199\254\126\187\143\166\237\140\026\239\109\049\192\198\193\232\128\097\082\191\161\161\095\078\006\138\089\249\132\129\072\022\207\212\022\024\032\188\077\176\080\230\232\163\143\246\150\074\030\067\067\132\199\241\066\043\208\074\239\080\017\065\199\043\149\008\064\068\061\002\244\043\117\066\188\082\195\201\062\088\254\239\255\253\191\223\240\134\055\188\236\101\047\219\107\175\189\164\006\154\051\033\002\155\093\114\135\016\098\038\081\160\213\196\048\098\118\032\026\068\170\158\056\081\199\085\150\165\007\240\175\161\157\057\115\166\212\133\166\061\076\076\137\013\212\042\252\066\043\038\216\128\249\132\185\199\030\123\024\123\103\206\201\150\026\194\003\028\014\198\021\210\044\085\025\051\019\049\070\052\187\187\219\115\057\073\179\220\220\235\201\235\171\203\222\247\237\119\232\110\119\223\061\070\009\216\086\237\181\215\041\011\022\116\039\105\127\090\212\234\181\140\042\169\059\210\102\179\209\058\046\052\203\172\167\103\171\227\142\063\198\110\214\014\028\124\008\020\003\096\189\117\215\235\110\239\149\175\124\101\081\054\179\052\109\150\069\082\038\105\218\178\037\175\185\204\202\091\123\154\164\040\203\184\081\113\067\041\254\199\151\185\104\056\118\012\203\153\166\041\063\011\090\019\073\048\072\001\017\219\230\152\236\032\089\120\180\059\022\054\044\242\182\044\203\102\179\169\028\086\218\216\043\073\128\150\193\069\129\024\022\069\199\015\003\225\180\165\036\199\074\193\194\216\057\066\218\146\139\077\061\169\193\010\077\109\058\155\161\230\169\192\166\182\248\097\160\134\064\194\132\049\124\118\008\113\058\144\029\042\039\234\158\018\242\002\109\056\017\097\111\070\149\035\142\056\194\172\211\164\209\104\176\103\029\021\034\103\125\129\159\013\042\105\060\107\003\166\140\212\016\106\051\141\129\180\005\060\155\028\212\000\042\001\034\201\090\067\211\154\085\227\209\044\045\215\236\054\138\230\128\246\069\035\153\153\036\031\105\172\076\198\243\251\072\094\179\113\104\154\219\003\205\162\089\164\185\111\150\210\148\177\045\179\180\214\215\088\241\174\119\190\107\215\093\118\221\119\223\125\029\214\092\052\088\193\016\214\052\095\178\132\172\165\172\183\175\143\009\252\223\024\024\144\095\004\107\146\038\105\235\191\251\144\038\101\110\162\153\028\181\172\150\036\185\140\065\053\162\149\027\007\105\251\199\201\121\158\087\177\045\029\068\108\011\108\064\155\105\118\199\166\031\163\066\049\074\182\155\166\241\056\246\114\098\173\066\190\182\252\233\142\207\085\186\045\131\210\033\206\134\093\037\236\178\203\046\180\021\213\082\024\133\037\059\022\049\013\052\132\016\050\225\082\008\013\223\150\232\128\089\036\005\200\073\052\160\135\164\032\059\184\197\161\022\218\043\095\164\172\021\114\004\065\002\130\019\017\155\028\212\000\106\072\010\239\110\255\203\237\148\103\066\149\026\194\058\037\158\201\006\090\101\089\062\001\173\172\211\229\011\205\242\036\239\045\007\062\051\123\206\054\139\023\191\080\183\246\063\031\058\236\176\203\022\063\216\147\185\175\176\192\166\073\033\221\148\121\189\150\103\245\090\210\213\104\244\239\188\227\174\007\030\188\063\175\090\181\004\128\101\077\092\154\093\130\213\092\242\037\075\125\179\217\060\242\240\035\172\182\194\003\109\251\208\211\221\093\207\107\121\154\151\101\170\006\178\156\129\246\058\093\140\133\181\107\182\254\056\116\007\089\150\085\177\205\004\225\033\041\136\106\225\173\068\155\108\226\089\118\144\001\049\071\056\077\064\139\104\024\037\057\038\048\183\040\059\081\205\047\189\243\161\059\081\095\130\078\060\241\196\063\108\255\108\123\169\033\023\152\119\148\145\142\093\064\162\249\223\154\045\170\053\039\147\057\228\003\235\096\002\170\014\106\146\013\122\238\124\212\129\158\128\025\060\197\131\084\225\053\006\064\232\074\063\012\156\104\159\105\027\102\238\133\023\058\229\108\004\154\170\016\029\085\132\071\142\123\211\155\222\196\209\198\155\242\212\027\228\068\060\147\010\148\007\042\229\089\107\104\074\019\203\195\120\016\217\033\077\178\129\178\241\091\219\237\248\206\059\239\072\198\243\251\192\146\199\030\197\095\175\217\238\151\069\217\104\152\227\133\033\174\037\121\061\239\170\117\231\239\121\239\123\118\223\109\055\187\069\067\207\159\121\251\039\060\204\046\033\161\094\118\240\106\199\157\118\034\038\079\125\099\045\006\026\003\045\057\069\105\043\210\221\093\171\119\213\189\178\131\072\147\012\077\056\132\213\201\198\250\233\046\096\070\009\009\134\008\021\057\078\120\011\021\096\130\199\070\163\129\205\161\073\061\213\202\178\229\093\053\001\053\001\143\065\140\084\234\130\103\156\008\094\245\170\087\041\173\255\202\010\142\012\214\087\175\092\141\217\029\056\062\028\119\220\113\018\132\122\139\174\125\153\140\032\243\146\192\183\178\176\188\064\067\234\209\217\172\228\124\242\141\067\184\113\173\202\140\164\228\208\250\086\008\014\173\237\172\209\165\142\235\245\058\037\044\020\130\128\167\232\039\065\040\005\004\069\241\052\155\077\038\201\112\157\109\041\234\021\068\165\199\138\064\007\170\154\032\038\080\146\031\032\048\008\037\057\212\230\098\090\081\082\106\008\063\050\196\091\192\140\103\082\033\084\082\130\059\242\182\110\227\220\199\166\045\254\246\160\230\206\020\167\206\154\145\014\172\249\136\209\150\182\150\226\234\057\071\223\245\220\179\091\111\179\213\128\019\069\209\078\010\185\131\064\099\160\191\055\079\147\222\230\170\189\247\222\111\247\221\119\021\169\134\094\104\154\090\105\218\238\049\115\025\209\195\201\130\193\043\129\219\219\215\219\147\215\250\250\122\241\116\117\119\089\063\220\082\053\026\206\042\197\046\059\239\178\237\054\219\246\174\094\185\237\086\219\245\244\116\099\216\036\195\145\166\169\126\065\072\136\237\065\009\066\118\016\231\162\189\175\175\143\165\214\106\190\147\029\064\147\000\009\042\131\086\198\163\154\161\032\033\066\081\162\049\225\209\018\068\064\142\144\005\230\204\153\163\018\220\227\056\157\217\154\057\062\032\132\174\116\032\059\068\106\224\091\030\166\024\015\155\140\116\166\057\253\133\122\040\048\138\014\067\181\090\107\077\059\144\070\230\210\025\232\216\016\202\079\054\048\116\162\025\223\209\187\002\141\233\183\106\213\042\151\037\022\106\190\008\145\092\025\205\073\080\083\061\170\172\160\030\173\092\023\144\044\254\200\209\145\210\035\105\146\174\079\152\118\052\162\182\074\013\244\196\227\237\100\003\181\169\164\004\068\150\229\202\174\198\056\230\054\126\048\089\123\018\087\146\003\179\119\222\235\168\219\110\085\051\070\148\121\254\129\249\243\151\036\233\170\070\163\104\052\243\220\041\160\164\076\107\185\044\202\102\179\232\238\169\255\215\255\250\123\188\106\005\019\160\226\050\203\214\196\015\054\017\034\088\185\218\043\147\202\071\193\189\247\222\199\198\195\006\164\158\183\150\150\154\211\073\150\053\006\026\171\125\197\108\014\020\101\182\243\078\059\116\249\054\083\175\235\139\132\049\234\185\030\217\116\010\172\048\193\152\035\072\232\047\188\153\032\194\001\237\149\004\225\067\056\068\215\101\217\114\009\090\091\165\071\177\167\068\143\004\111\201\033\077\023\150\085\019\199\060\087\074\058\021\060\130\078\049\056\092\072\016\092\237\016\033\047\224\193\111\150\121\075\136\249\101\038\130\041\201\117\244\167\073\096\036\005\038\086\191\102\116\071\105\028\189\042\013\063\109\068\064\036\008\186\050\006\228\054\037\237\041\234\190\090\206\147\014\089\197\221\196\114\156\082\115\168\008\116\032\106\148\220\167\028\047\042\033\154\067\052\215\035\154\067\127\251\183\127\091\050\230\077\010\115\165\225\097\066\229\202\096\158\084\037\115\066\031\068\094\107\013\077\145\181\114\068\084\142\177\212\032\079\106\054\014\159\223\189\245\159\060\026\099\043\108\103\031\124\200\093\205\134\124\208\183\218\157\162\011\135\130\175\026\069\051\075\210\122\214\213\087\246\191\234\248\087\139\078\193\042\124\069\057\103\210\083\195\000\102\030\086\047\118\195\225\089\087\205\171\214\112\036\101\173\214\162\211\052\169\117\213\086\173\092\217\223\215\183\170\119\096\143\061\247\080\047\168\242\060\079\211\020\243\198\071\218\222\065\080\128\242\034\150\254\018\196\246\219\183\254\091\082\140\221\126\251\237\101\058\074\122\107\217\103\026\126\022\133\158\104\016\108\021\162\126\104\233\011\200\163\143\062\074\136\093\000\152\252\096\242\043\161\034\208\128\193\244\225\103\051\011\204\044\014\167\140\072\166\155\009\040\152\169\074\103\062\015\080\099\104\167\235\094\147\141\069\132\190\067\009\230\025\075\030\228\038\186\118\038\008\179\081\142\224\074\137\150\109\246\243\210\004\225\028\215\104\052\016\132\004\212\240\111\211\098\084\020\106\072\246\118\098\208\028\072\211\060\228\132\088\143\199\030\123\172\075\029\026\082\149\067\169\077\121\204\001\012\107\005\061\129\240\065\080\025\088\171\132\009\048\132\122\202\044\205\053\111\190\176\056\163\199\136\109\179\158\229\073\223\219\102\028\056\227\142\113\220\056\248\138\249\031\011\238\152\158\228\141\180\181\048\114\038\029\196\095\154\248\051\025\040\250\183\158\182\205\049\047\063\218\174\065\176\138\081\254\196\211\169\018\190\152\069\002\023\120\059\075\090\209\085\175\215\156\041\092\093\147\086\111\253\106\185\077\068\154\055\202\222\067\015\063\072\044\005\179\230\157\210\198\078\151\035\252\198\040\065\191\001\202\051\202\196\019\048\012\148\023\076\072\241\131\016\213\076\160\187\239\050\120\072\022\018\209\109\180\029\228\010\012\131\096\082\060\240\192\003\253\253\253\166\137\217\225\104\006\178\128\092\016\004\026\100\004\030\150\017\176\153\077\145\020\040\064\031\090\009\099\234\113\023\085\057\019\162\247\065\125\173\199\199\214\248\141\069\028\061\184\000\248\136\131\012\042\117\233\205\125\204\096\079\088\133\086\207\119\108\240\025\252\213\175\126\181\239\094\248\099\210\086\014\037\135\192\232\055\042\131\158\088\073\020\068\091\210\016\148\057\225\132\019\164\100\026\082\149\050\212\198\211\217\047\182\145\064\072\128\033\064\121\009\014\016\021\212\003\182\145\132\076\172\158\146\208\110\219\154\165\233\011\155\216\118\205\218\139\250\242\229\219\022\189\054\014\039\021\171\135\229\030\169\242\227\245\046\095\049\203\122\205\065\000\015\211\064\076\023\190\061\182\174\064\202\060\203\185\081\152\218\023\024\080\161\137\173\019\212\006\245\098\023\016\054\004\024\006\006\026\073\090\022\069\081\171\213\187\186\122\202\102\153\165\089\158\217\074\052\095\182\231\238\162\069\196\215\106\053\109\049\143\017\220\014\100\026\142\040\017\157\080\009\120\096\173\050\117\045\048\160\094\175\083\198\036\164\149\197\079\240\072\016\128\086\111\110\187\122\183\225\039\144\088\064\068\091\196\232\160\204\243\207\063\207\159\018\141\244\106\190\128\040\085\006\034\029\152\062\050\002\152\086\122\215\111\056\092\012\083\128\255\057\170\237\216\092\191\129\209\251\093\199\183\099\205\014\209\013\015\082\078\112\080\148\198\084\231\059\198\176\138\121\172\005\214\170\193\169\201\158\123\238\233\186\197\215\090\214\106\197\030\062\005\068\000\205\113\056\061\042\199\011\205\161\106\027\052\005\222\218\254\151\041\196\177\145\166\106\248\052\084\026\099\023\180\002\001\103\209\016\022\096\104\237\015\003\042\189\194\016\208\239\024\197\142\206\022\134\040\033\201\082\204\246\249\202\177\035\091\181\234\135\179\143\250\209\236\057\091\061\252\240\216\091\061\125\224\129\223\124\224\254\060\073\123\027\253\085\171\052\205\210\180\150\101\053\009\170\039\171\047\093\249\252\189\011\239\169\222\142\066\180\148\111\191\110\229\133\036\041\074\159\045\216\210\250\079\094\170\105\081\190\147\246\149\251\238\125\240\142\059\238\096\140\012\144\160\106\183\088\123\193\213\001\254\007\041\219\208\128\209\177\061\001\132\209\081\239\045\004\243\218\229\038\009\181\069\136\080\161\143\216\238\076\016\038\170\089\141\129\088\219\007\111\209\036\039\073\171\021\058\025\219\207\197\028\075\205\121\211\193\028\169\224\017\076\037\029\121\171\047\051\139\103\116\020\073\065\218\210\144\122\001\061\194\216\250\092\039\174\113\100\135\080\040\244\163\046\039\154\123\156\200\036\118\074\016\166\229\238\187\239\094\237\142\024\028\038\185\134\181\146\187\029\228\122\062\053\163\120\089\009\030\067\032\225\048\001\083\180\034\004\066\154\030\221\053\248\044\036\091\241\047\231\082\085\191\122\193\009\107\237\034\068\145\070\201\008\059\025\193\125\138\107\182\231\158\123\238\241\199\031\127\250\233\167\013\179\040\244\086\252\225\012\104\184\086\225\107\101\168\052\012\098\002\039\139\067\231\221\118\200\188\113\092\070\082\233\111\150\047\183\113\176\160\039\185\110\205\223\214\191\083\080\150\009\167\229\185\008\073\027\073\115\155\124\218\143\046\255\241\178\165\203\184\034\012\031\106\175\026\174\224\183\112\075\061\183\065\072\178\164\108\054\026\121\158\247\247\247\054\154\253\101\217\040\138\100\089\223\170\195\142\108\029\043\196\143\049\242\150\026\163\131\112\032\159\112\093\128\033\232\237\237\053\058\134\131\086\128\240\008\052\148\035\112\226\007\013\071\023\222\050\059\077\179\044\019\042\002\070\108\011\030\083\212\092\021\222\001\170\018\107\198\138\103\156\004\146\172\012\225\106\008\241\056\010\030\122\232\033\033\100\214\144\044\005\116\066\013\249\058\005\093\240\009\208\132\062\156\003\228\195\090\187\024\165\247\009\188\050\246\227\104\021\202\209\018\168\206\137\044\097\024\039\070\130\216\189\253\147\032\000\041\101\176\153\079\049\059\098\248\156\235\194\210\065\203\062\034\122\229\217\010\081\179\142\165\212\254\198\055\190\209\113\078\191\134\129\134\186\166\045\205\097\116\225\161\137\033\007\177\069\109\193\039\230\150\047\095\190\116\233\082\059\195\037\075\150\252\228\039\063\249\222\247\190\119\253\245\215\063\252\240\195\210\004\006\108\157\081\072\200\232\189\140\244\182\082\047\136\040\093\204\140\196\191\190\234\023\204\158\125\221\099\143\117\167\121\094\175\119\213\186\136\213\053\148\101\001\038\097\154\150\003\069\209\072\202\021\203\151\127\246\211\159\101\245\178\101\203\204\204\082\254\192\253\002\060\242\067\248\205\091\097\189\228\145\071\187\210\186\228\208\186\103\072\109\131\236\025\146\102\163\185\205\244\237\138\036\057\114\246\225\086\075\147\065\048\232\238\005\049\195\255\073\056\144\095\013\141\020\032\023\072\217\148\049\052\240\212\083\079\057\219\223\126\251\237\243\230\205\083\222\125\247\221\166\034\125\052\001\205\097\120\233\237\090\058\004\104\046\108\076\078\186\153\192\082\003\061\149\104\017\197\033\062\052\186\059\016\084\218\145\172\028\035\168\244\196\019\079\132\112\162\204\029\064\128\238\192\043\222\160\000\200\008\160\023\008\197\198\216\203\122\100\027\095\118\208\113\040\074\099\048\241\024\195\054\083\145\239\108\022\226\076\037\053\000\015\042\229\008\137\131\217\152\173\231\007\028\112\128\239\189\230\176\038\036\144\102\204\042\144\063\094\104\171\073\148\188\233\166\131\124\009\139\086\209\105\244\130\103\116\144\000\226\015\076\120\241\045\248\034\047\060\251\236\179\207\060\243\140\089\113\223\125\247\157\122\234\169\031\253\232\071\063\241\137\079\124\247\187\223\189\229\150\091\030\121\228\017\233\067\142\136\040\212\150\016\024\189\175\036\073\134\101\224\141\023\049\044\199\006\168\252\163\133\011\031\079\050\153\128\009\003\253\214\246\146\199\218\253\148\069\209\076\090\219\008\155\136\188\183\217\063\061\157\254\192\195\015\204\187\117\030\087\112\014\254\078\075\205\019\053\092\097\198\122\187\221\182\219\062\187\114\089\119\215\180\174\238\233\073\146\039\101\094\171\117\117\119\247\036\101\182\108\229\234\217\173\255\072\252\142\166\156\025\040\048\088\221\238\113\152\066\023\036\007\204\076\227\162\011\062\215\139\188\096\254\083\198\134\238\209\071\031\093\180\104\209\175\127\253\235\203\047\191\252\172\179\206\250\200\071\062\242\225\015\127\248\214\091\111\165\137\209\140\230\068\193\048\125\188\080\069\013\096\190\201\041\120\076\093\081\042\176\045\126\084\005\113\133\023\131\141\176\071\052\201\033\083\009\106\070\129\212\032\162\068\041\176\090\047\157\080\009\132\071\073\147\192\040\002\055\244\171\113\103\135\080\136\222\204\000\230\177\083\218\011\063\202\178\114\129\044\032\041\072\013\145\032\016\030\037\014\204\002\072\105\111\102\031\225\142\071\219\074\096\016\019\046\249\052\174\057\244\078\025\163\075\184\074\074\210\022\070\146\108\080\141\113\192\244\022\076\017\127\006\210\138\244\204\051\207\088\148\196\159\082\180\073\007\086\045\075\211\127\254\231\127\126\246\179\159\061\251\236\179\175\188\242\074\251\008\081\040\112\053\015\057\100\194\072\061\174\181\158\182\121\123\091\062\129\147\197\090\133\119\103\006\009\165\000\000\016\000\073\068\065\084\050\124\103\246\081\079\247\246\102\089\062\144\020\161\060\143\097\120\065\121\127\202\027\202\214\062\161\153\053\211\222\230\073\255\113\178\040\055\045\121\137\177\152\001\135\169\171\198\164\093\186\116\041\215\045\123\126\169\250\129\178\225\032\209\213\221\035\049\052\139\214\191\134\051\109\250\182\075\087\060\121\220\241\199\236\176\227\014\038\152\025\040\030\216\139\121\040\136\005\189\208\205\184\240\048\231\075\013\085\094\048\040\156\111\043\247\205\111\126\243\204\051\207\252\202\087\190\114\233\165\151\254\236\103\063\147\038\110\184\225\134\159\254\244\167\139\023\047\166\149\134\212\035\007\008\132\161\125\069\013\077\178\145\207\023\210\132\208\034\068\060\219\159\070\019\210\002\241\056\074\073\019\219\079\101\240\068\095\186\067\116\034\222\078\134\114\130\217\129\234\097\015\219\140\174\029\132\217\104\164\249\206\144\219\068\056\083\152\165\242\130\004\017\224\080\149\252\139\063\028\100\050\059\104\168\036\109\221\065\254\123\222\243\030\031\074\036\251\065\027\007\170\142\036\063\198\213\120\015\141\063\091\006\235\146\153\032\053\220\127\255\253\191\252\229\047\133\157\032\035\074\164\222\123\239\189\087\095\125\181\136\252\194\023\190\240\157\239\124\231\230\155\111\022\166\230\134\244\071\026\132\100\204\099\007\061\129\075\149\121\222\026\154\102\154\142\189\249\120\057\139\173\183\254\187\121\183\061\158\102\171\210\198\244\173\167\075\166\036\208\028\040\111\052\141\148\026\160\069\150\101\189\069\163\094\239\121\238\249\231\046\251\222\015\076\203\048\022\039\006\165\025\168\134\211\228\083\185\242\166\027\111\172\059\147\216\148\036\090\165\101\057\144\022\005\099\086\247\246\239\184\253\094\179\102\237\109\220\005\131\117\133\100\018\134\130\076\160\076\012\141\152\033\054\242\130\046\012\138\253\194\131\015\062\248\171\095\253\234\123\223\251\222\215\190\246\053\187\134\121\243\230\057\092\120\139\089\030\185\236\178\203\036\011\057\221\056\106\027\067\067\026\177\048\180\071\053\233\011\063\182\011\105\234\217\221\136\040\170\010\108\037\154\194\210\159\232\181\016\106\050\146\040\175\006\129\045\212\019\039\116\027\123\171\065\066\054\230\099\043\004\039\220\095\120\146\179\064\108\201\017\166\101\120\211\038\194\102\065\004\184\170\148\035\076\093\144\047\084\122\197\239\198\015\034\113\080\096\194\206\210\016\072\056\252\240\195\095\247\186\215\145\079\007\242\141\046\173\066\067\111\135\066\043\048\096\096\206\155\240\244\137\117\201\150\065\148\011\041\169\065\105\167\240\245\175\127\253\203\095\254\242\029\119\220\065\032\201\121\222\186\190\035\211\148\184\241\198\027\063\245\169\079\253\221\223\253\221\185\231\158\043\088\073\032\074\008\018\075\062\096\027\011\072\198\166\004\068\146\154\074\246\245\045\114\003\253\115\214\140\153\247\037\073\045\205\117\083\175\117\213\106\181\052\077\153\006\092\023\038\168\209\123\219\022\167\140\116\117\057\176\251\078\187\253\240\178\031\062\250\200\163\182\015\162\028\027\027\057\208\244\227\055\089\227\201\039\159\236\238\234\090\209\215\091\207\187\114\231\137\188\222\215\219\095\052\138\158\174\250\244\238\233\043\087\047\253\047\111\127\139\153\102\164\172\037\194\070\095\186\024\004\050\065\191\036\247\247\247\247\246\246\146\031\169\193\136\072\013\230\152\140\124\198\025\103\156\126\250\233\115\231\206\197\016\018\040\028\240\040\167\123\251\175\255\250\175\050\187\084\162\185\241\162\048\177\064\062\096\027\004\205\169\004\028\034\144\132\083\132\180\212\032\116\149\212\166\149\122\033\039\125\104\078\142\086\128\030\029\246\158\243\231\207\103\203\040\010\140\046\097\099\190\205\214\177\051\030\001\174\004\222\148\032\248\203\178\195\131\252\200\155\130\000\228\005\144\044\164\091\149\018\048\143\139\012\077\120\118\194\058\084\109\093\121\030\127\252\241\058\210\047\005\066\050\149\232\054\172\112\013\161\217\108\138\021\193\039\104\004\186\165\207\174\088\208\139\063\033\254\216\099\143\089\139\126\248\195\031\254\224\007\063\088\176\096\001\006\077\192\184\146\073\184\018\072\240\074\006\185\232\162\139\062\255\249\207\219\080\200\041\100\170\199\137\031\176\141\005\180\125\017\089\107\104\026\237\114\044\109\039\192\051\247\153\103\180\234\047\139\164\072\092\186\178\066\239\161\182\208\231\019\250\203\020\042\025\219\178\162\108\052\203\102\111\099\213\227\079\044\057\253\180\179\152\025\243\205\084\049\057\185\142\211\236\156\121\239\154\095\252\178\043\205\007\202\164\049\080\166\069\158\037\053\119\146\069\153\044\095\222\251\178\061\102\237\183\255\062\022\012\097\032\078\004\064\050\228\167\047\093\003\201\060\073\184\156\043\245\068\202\150\128\238\186\235\046\007\186\111\127\251\219\246\005\150\113\252\033\131\170\232\128\026\004\013\029\049\190\244\165\047\073\238\223\255\254\247\229\008\118\141\101\019\145\181\207\023\212\147\032\196\170\027\007\241\028\064\003\033\086\062\241\172\035\208\151\114\088\208\042\224\045\047\201\089\092\221\108\054\071\105\130\115\050\160\021\130\235\174\071\024\207\161\130\137\067\171\028\193\137\028\042\014\156\053\248\081\137\142\212\096\014\123\043\002\204\201\117\084\064\191\039\158\120\226\177\199\030\171\047\097\173\119\058\168\012\173\134\010\055\042\160\107\035\020\193\039\151\011\035\241\103\083\026\235\146\048\186\237\182\219\108\089\165\134\123\238\185\007\103\037\071\067\240\024\242\163\035\053\190\087\157\119\222\121\159\249\204\103\174\186\234\042\077\216\165\149\122\125\001\254\177\032\100\042\131\121\131\158\044\078\222\097\251\153\173\110\210\234\095\004\173\180\021\190\222\132\026\097\096\120\181\175\119\245\170\149\043\183\237\218\250\182\219\111\094\176\224\078\238\050\111\205\094\198\162\165\006\126\107\246\055\158\095\177\060\171\213\090\210\218\255\100\121\150\167\034\109\218\170\129\231\222\241\142\183\088\039\192\096\153\120\209\133\190\042\240\085\192\244\139\209\033\220\164\138\172\173\023\093\152\240\110\133\023\046\092\216\104\052\052\036\036\128\174\016\053\074\114\092\067\124\241\139\095\180\001\180\137\112\181\108\136\233\060\202\232\104\021\176\204\080\082\172\086\009\194\174\135\230\022\033\012\036\184\158\020\207\085\167\107\037\184\139\218\108\105\057\166\109\231\090\155\108\066\006\099\182\126\122\231\172\064\222\254\013\114\171\068\016\224\086\142\230\110\209\134\054\252\171\086\173\162\129\182\202\137\129\156\099\142\057\198\201\133\100\099\041\053\080\097\088\129\237\225\040\013\140\113\021\052\122\023\037\006\172\010\062\171\159\189\159\157\130\243\234\197\023\095\236\148\072\037\211\131\076\037\153\160\134\028\066\148\104\080\233\045\160\109\119\109\101\157\120\023\047\094\108\153\210\081\112\086\204\120\070\002\057\094\041\033\203\082\180\047\127\202\013\132\061\238\186\235\191\204\220\183\191\108\232\073\143\073\226\207\196\207\208\180\031\019\086\243\036\205\065\218\157\190\213\086\106\152\185\114\096\245\202\101\171\078\253\204\169\182\087\214\243\231\159\127\094\137\230\186\149\171\086\254\236\231\087\118\167\245\102\150\230\093\181\090\221\109\195\064\163\057\224\148\177\098\229\234\131\015\060\106\183\221\119\113\156\180\084\216\056\228\121\030\029\233\052\160\035\224\049\211\222\000\073\082\145\026\200\183\101\176\043\209\203\229\151\095\238\187\178\129\211\132\050\048\072\136\199\168\012\162\086\107\157\152\048\059\003\126\242\147\159\252\220\231\062\119\221\117\215\017\104\244\245\162\047\208\041\224\169\160\045\144\163\185\160\098\190\048\019\195\114\129\236\160\244\168\137\237\067\231\245\100\213\188\147\192\022\080\073\109\123\007\105\084\239\250\085\051\153\177\222\178\067\024\201\161\192\167\006\030\196\025\207\202\005\156\027\064\171\081\207\233\226\195\240\243\087\180\157\088\105\144\222\240\134\055\204\154\053\075\106\032\060\036\211\033\208\041\051\070\200\116\005\145\103\234\074\076\246\165\017\220\130\079\228\249\042\038\134\126\252\227\031\187\235\178\076\137\158\144\211\057\144\106\024\008\132\163\001\081\129\088\071\098\167\012\183\232\118\031\186\208\157\230\209\123\197\054\148\008\057\202\053\104\207\213\070\186\102\198\014\229\095\047\053\039\245\174\106\111\031\018\189\101\089\194\040\253\085\129\203\124\230\080\030\056\170\175\183\183\171\171\102\067\220\159\052\106\089\247\226\135\030\188\230\234\107\005\186\165\088\041\053\048\252\209\251\031\212\042\235\234\078\109\123\178\098\192\209\034\041\146\178\089\020\089\189\187\241\123\111\127\243\094\237\255\014\162\009\038\012\116\151\116\252\194\069\250\034\129\014\002\163\051\053\024\014\112\049\236\150\129\086\152\211\148\178\073\154\182\074\098\210\023\126\104\192\080\193\027\052\153\052\116\133\236\148\241\163\031\253\200\094\143\124\149\122\004\012\160\097\005\173\104\040\080\045\117\066\075\000\071\118\144\026\232\143\246\150\170\051\103\206\244\022\115\213\112\040\225\045\168\199\207\081\182\063\034\031\173\071\080\063\057\177\158\179\067\024\201\017\192\119\032\071\132\127\185\056\160\198\091\037\102\091\044\195\147\036\009\122\002\032\199\071\138\183\189\237\109\118\170\006\047\082\131\078\193\171\078\129\198\000\004\129\185\170\071\145\103\222\138\248\072\013\182\012\082\131\157\130\139\006\169\193\237\035\030\066\040\172\212\016\042\105\036\007\188\170\042\131\080\031\132\221\163\143\157\014\038\119\223\125\183\142\116\170\107\066\032\024\134\045\053\015\180\222\182\247\014\045\098\067\254\211\243\248\227\159\057\106\206\012\093\148\073\225\098\000\225\067\003\045\091\095\048\219\127\213\065\077\210\154\129\069\081\152\147\003\003\141\070\209\108\077\199\172\152\158\111\117\230\089\103\060\252\200\035\238\098\193\094\073\206\253\213\173\183\108\085\171\247\023\003\196\021\253\101\082\214\234\245\100\235\233\091\061\183\124\217\177\199\190\118\199\029\119\136\171\126\011\131\168\096\108\242\194\175\221\231\139\219\058\003\100\234\026\032\017\034\041\060\241\196\019\150\220\107\174\185\070\118\080\207\243\160\169\086\202\078\132\076\245\157\192\032\222\000\161\185\187\161\147\079\062\249\252\243\207\191\229\150\091\008\215\215\176\003\068\084\128\170\066\075\128\081\091\082\144\026\036\008\132\154\149\043\087\090\159\246\217\103\031\012\132\143\002\162\188\165\149\238\228\083\106\068\118\080\057\105\177\065\178\067\088\203\029\021\212\004\141\224\032\165\071\158\053\246\066\042\030\213\032\198\130\138\211\176\185\055\062\240\192\003\141\144\181\200\100\022\001\017\055\157\114\244\008\226\091\016\232\206\240\152\177\046\026\244\110\179\042\053\216\056\200\008\223\250\214\183\156\008\212\068\091\252\198\079\019\109\245\168\012\196\091\180\074\052\054\052\066\191\106\002\030\157\086\196\159\092\099\141\050\175\200\009\206\096\198\048\020\209\054\202\120\219\076\090\051\049\232\013\084\190\235\182\091\247\218\122\027\090\101\105\218\250\187\013\137\011\196\053\157\134\038\097\151\146\002\028\018\068\145\054\203\052\097\227\005\231\093\036\021\250\190\043\059\220\117\251\029\024\154\101\082\052\006\006\146\070\150\214\186\187\234\121\086\043\202\174\105\061\091\189\254\245\199\218\132\059\000\154\093\006\043\228\144\089\129\127\192\000\113\151\001\170\082\131\209\049\040\174\250\127\254\243\159\099\192\079\049\010\035\160\147\064\087\192\163\011\165\026\037\104\171\004\173\172\222\231\156\115\142\028\225\038\194\010\097\049\024\105\128\008\017\102\064\103\217\065\164\201\011\178\003\160\037\008\013\157\149\122\122\122\136\029\138\232\142\014\016\052\030\022\137\061\190\082\009\106\038\039\054\096\118\008\131\025\015\104\099\195\143\060\162\004\078\151\029\036\081\053\222\174\021\149\103\059\057\109\028\094\241\138\087\184\040\050\072\093\118\189\237\019\038\078\168\216\244\174\107\208\145\032\136\212\032\172\013\143\152\051\078\178\131\053\228\138\043\174\112\016\080\143\077\219\144\160\045\090\025\064\003\154\052\064\012\005\134\000\057\036\095\114\201\037\182\178\118\016\118\146\209\036\222\014\045\163\071\037\207\040\001\207\064\186\102\162\162\055\028\206\155\057\195\249\034\245\075\146\060\123\241\046\128\038\121\251\106\128\153\122\111\123\184\238\243\103\154\165\121\150\246\053\086\119\165\221\215\205\189\250\137\039\158\148\029\180\094\176\240\238\173\187\123\250\147\034\205\178\060\171\037\073\179\104\054\210\114\235\103\151\062\243\059\111\061\209\157\180\089\164\052\088\196\018\088\129\124\206\129\106\128\164\006\147\214\237\128\049\082\074\064\055\221\116\147\074\156\058\082\142\130\078\177\021\027\225\065\199\091\057\200\126\068\186\249\234\087\191\026\167\012\129\209\104\052\006\177\233\043\032\059\048\095\010\136\004\033\053\200\113\074\009\130\040\031\227\124\133\009\201\202\104\130\232\132\222\171\071\185\073\228\107\168\187\170\114\018\018\027\060\059\176\153\011\248\029\184\003\068\128\236\192\215\198\067\130\008\175\041\001\243\040\008\167\043\131\179\094\175\191\250\213\175\222\127\255\253\069\155\097\051\126\144\101\191\097\017\078\189\043\163\095\083\084\132\073\001\002\078\216\137\015\165\175\098\174\009\236\029\058\187\214\100\164\071\175\002\033\057\216\212\196\035\002\162\082\233\227\197\089\103\157\101\063\236\180\105\073\196\003\157\012\120\042\048\173\066\235\223\223\078\146\090\018\127\086\044\107\039\230\029\117\212\023\015\061\108\237\124\029\028\051\239\184\227\109\051\102\054\139\214\214\033\077\210\120\227\015\122\026\041\080\067\177\032\090\101\089\182\078\024\105\209\204\154\022\249\031\255\248\114\046\189\099\254\060\067\236\251\104\089\022\165\067\073\146\102\121\238\062\112\160\145\236\180\227\110\179\103\031\230\198\097\215\093\119\181\240\026\250\206\097\042\203\178\104\255\090\205\251\091\127\181\193\024\073\013\210\183\097\178\003\183\249\050\141\165\090\106\064\089\182\248\017\129\178\253\011\186\179\108\087\183\010\149\109\241\107\110\120\085\169\009\168\255\197\047\126\225\022\057\182\120\250\018\039\042\241\064\240\164\237\159\116\038\186\104\046\216\100\004\086\064\100\007\113\136\069\028\186\106\237\108\018\244\176\101\028\196\076\132\065\125\013\203\188\009\043\179\065\125\175\223\071\046\102\063\024\120\126\231\014\051\004\016\058\066\040\129\115\113\034\070\001\006\108\162\074\137\077\105\048\014\062\248\096\105\091\106\048\066\006\079\101\000\003\104\162\107\101\116\045\053\024\126\007\010\049\039\041\072\013\206\156\194\206\055\075\225\136\095\219\074\190\199\241\066\071\195\054\209\203\185\231\158\235\154\083\047\012\199\022\024\150\089\037\053\002\232\129\100\220\217\225\244\039\159\057\245\206\005\215\204\121\133\230\099\199\073\069\211\246\001\191\137\205\105\109\034\065\080\021\013\008\143\003\003\253\073\146\102\089\046\071\164\073\090\038\173\255\106\195\162\069\247\206\253\197\047\022\221\187\168\171\171\071\138\073\036\025\175\027\173\091\135\105\245\173\087\247\063\253\095\222\254\022\131\229\076\225\123\182\193\050\211\146\023\126\196\006\068\008\231\088\048\098\140\100\007\099\036\233\184\015\242\133\216\144\189\208\098\189\253\153\182\127\196\201\059\167\157\118\218\005\023\092\096\073\167\000\077\088\026\090\121\011\109\198\084\128\201\014\244\183\125\112\005\046\059\064\036\008\252\054\176\174\198\049\067\180\141\086\030\043\066\189\071\112\010\115\201\165\021\084\149\234\039\027\054\096\118\096\054\176\095\168\192\192\192\128\116\192\251\074\149\130\128\143\194\029\225\062\101\060\142\082\018\008\024\108\080\125\170\216\111\191\253\140\144\001\051\114\098\142\004\240\022\176\233\069\169\223\042\236\068\155\056\139\211\132\107\118\095\182\124\027\147\038\112\106\082\181\069\175\047\144\073\001\059\136\011\047\188\208\087\119\185\105\104\240\085\125\097\174\016\105\193\092\172\222\142\145\216\109\250\180\071\146\228\143\111\253\117\255\206\059\143\177\009\182\173\030\126\248\159\142\056\082\130\168\039\153\255\169\233\004\055\134\139\084\162\185\026\248\188\104\202\004\069\045\207\233\217\072\146\162\217\132\036\077\177\101\105\082\054\138\103\087\046\221\111\214\193\051\102\236\109\227\032\143\091\117\229\241\052\109\049\224\001\210\072\174\194\195\078\068\014\149\026\012\147\210\120\221\112\195\013\062\036\241\033\230\013\004\035\098\049\255\218\215\190\038\065\184\221\208\169\026\090\209\013\116\154\166\105\214\254\049\057\018\068\100\135\072\013\104\047\105\238\110\082\052\162\163\149\134\001\205\003\241\168\196\236\146\085\217\217\139\250\201\134\013\152\029\152\202\077\236\143\177\055\069\065\106\144\032\120\208\154\096\072\240\004\184\047\136\145\074\012\033\077\137\231\160\131\014\058\241\196\019\045\071\238\138\004\156\097\195\000\094\001\158\128\168\210\169\030\197\156\081\023\115\086\036\107\133\004\113\237\181\215\186\017\176\161\192\175\033\068\019\165\154\245\008\146\073\179\131\061\227\140\051\238\187\239\062\030\224\144\161\189\004\155\018\240\183\022\230\214\031\227\030\160\021\003\253\246\208\139\146\228\019\219\237\210\018\126\005\181\101\000\000\016\000\073\068\065\084\048\230\127\254\215\237\243\167\213\186\122\155\003\182\004\026\189\056\131\061\180\081\233\076\067\217\193\200\170\110\217\210\158\060\020\046\202\166\145\245\214\189\068\045\055\038\211\242\122\249\187\255\229\045\174\027\140\148\213\213\096\097\208\042\080\182\127\228\196\048\153\045\134\073\082\048\076\096\164\092\025\154\174\152\181\034\022\177\126\161\127\098\217\162\020\018\167\156\114\138\051\166\100\068\013\042\081\012\003\068\167\120\112\202\014\172\136\237\131\100\039\029\200\017\030\197\152\114\223\125\247\245\054\248\007\149\154\067\085\041\254\173\079\090\233\165\170\156\108\196\184\131\111\188\006\048\094\038\230\107\048\049\184\195\116\037\196\092\173\252\142\008\168\031\022\130\195\192\116\058\087\118\056\224\128\003\012\140\193\016\134\241\054\024\066\084\213\175\030\237\083\044\218\206\177\054\249\098\078\121\229\149\087\222\120\227\141\250\210\132\112\077\148\104\053\235\023\036\019\075\061\250\184\224\144\143\124\114\231\016\143\094\065\103\119\056\227\177\034\172\201\081\051\246\178\167\214\250\191\162\216\038\235\185\104\209\093\207\238\127\192\216\027\226\252\230\097\135\216\062\100\237\211\076\187\080\183\006\084\002\015\028\069\127\163\041\047\120\108\161\044\025\024\155\029\118\165\089\218\085\239\202\179\174\149\125\203\014\062\232\168\093\118\217\217\198\097\231\157\119\054\121\140\084\154\174\073\059\108\015\144\038\036\164\105\195\036\042\034\059\200\020\086\087\247\196\008\093\004\039\098\125\033\109\255\216\066\115\176\192\168\032\220\071\104\023\201\113\073\196\064\230\068\215\222\098\006\204\018\132\237\170\045\067\164\006\057\002\205\058\204\182\015\094\145\083\065\195\144\224\173\074\143\128\096\166\029\165\176\084\031\012\042\199\138\141\197\183\001\179\003\155\089\014\134\031\164\134\128\026\126\151\158\059\109\196\220\249\056\148\198\000\081\111\045\058\226\136\035\172\069\174\136\140\107\196\092\056\029\015\068\023\034\088\106\112\241\105\012\034\053\088\031\164\006\121\193\151\115\129\168\137\193\014\153\074\143\128\088\239\016\085\100\218\179\092\124\241\197\214\067\182\211\141\146\084\085\223\009\010\004\162\178\145\172\153\075\241\056\150\178\150\182\198\180\172\167\139\147\228\239\087\141\047\189\028\058\111\222\027\246\218\187\153\036\121\091\200\011\221\165\065\240\021\067\140\157\209\012\205\061\130\026\182\224\081\166\105\222\085\235\206\243\060\075\187\123\122\186\126\231\109\111\240\021\115\183\221\118\115\195\111\218\100\191\121\103\140\159\040\174\136\097\226\022\131\098\215\032\035\088\090\029\196\212\068\071\132\111\008\208\039\077\083\093\040\035\138\124\074\112\190\240\109\219\189\128\132\069\067\208\053\030\037\254\060\207\101\007\107\146\216\147\020\164\006\057\066\137\022\222\104\055\175\056\071\130\142\192\091\102\186\138\178\086\241\094\008\087\057\217\208\138\164\013\164\019\155\121\214\240\131\197\001\184\015\016\102\172\128\136\126\195\089\065\015\091\098\032\170\114\162\177\057\254\248\227\221\056\200\214\006\201\160\026\048\060\218\098\083\234\020\115\021\115\145\026\012\134\145\208\175\152\115\013\137\065\019\013\241\003\090\185\225\064\049\129\069\190\160\255\233\079\127\186\096\193\002\113\079\079\245\160\190\002\077\160\122\116\070\168\232\049\018\113\046\104\166\197\014\061\219\252\108\201\226\185\115\094\062\198\134\193\246\197\178\176\125\040\202\194\099\150\102\161\076\040\207\105\180\141\026\111\131\080\131\246\170\122\108\052\154\026\174\236\123\230\232\163\143\223\105\199\029\164\114\087\146\006\139\183\131\007\191\086\204\135\070\163\033\030\204\195\216\056\072\226\060\227\209\055\230\234\224\089\181\210\112\125\129\002\021\168\065\127\146\197\146\210\250\113\242\201\039\255\240\135\063\148\205\005\140\183\160\030\104\194\021\012\017\132\146\029\163\228\133\000\154\064\156\206\080\194\018\013\248\181\010\084\116\016\226\255\246\219\111\215\005\182\064\176\077\170\114\067\101\135\048\152\179\064\004\152\171\242\002\143\040\249\215\226\032\002\056\130\167\060\002\194\227\072\240\022\079\188\229\122\217\097\207\061\247\068\012\221\056\024\102\061\234\078\095\122\137\152\147\026\236\026\068\158\189\189\236\016\114\148\161\100\037\092\067\053\234\215\047\200\132\170\151\235\175\191\254\210\075\047\181\070\113\139\122\024\182\187\168\143\077\254\176\012\035\085\078\203\115\175\210\034\073\187\147\199\210\218\251\111\189\105\096\167\214\255\105\157\202\177\096\218\163\143\158\052\123\246\140\036\177\097\040\146\210\098\159\215\146\174\174\058\255\083\009\146\036\065\051\007\093\121\076\141\057\227\085\089\054\027\205\190\149\171\123\123\122\166\189\241\141\175\053\076\214\082\043\170\233\132\007\067\064\091\048\088\082\067\140\148\036\110\227\096\140\140\154\147\191\099\005\078\077\000\129\089\185\222\065\127\058\016\030\132\050\186\019\063\206\023\018\132\021\005\141\007\176\001\195\089\090\175\215\133\159\237\131\164\032\059\048\080\137\198\188\203\046\173\127\145\036\084\197\015\154\016\171\084\233\017\016\056\221\059\176\215\140\208\111\084\170\159\084\216\080\217\033\140\100\182\057\000\124\033\014\056\002\056\215\161\043\178\067\176\173\181\228\089\254\197\102\072\142\058\234\168\195\014\059\204\078\021\077\084\212\115\174\190\192\040\234\168\010\056\029\089\010\064\228\057\230\093\126\249\229\086\111\210\136\002\252\160\045\084\132\250\245\014\194\201\140\126\229\169\111\127\251\219\243\230\205\179\072\210\086\215\224\237\032\004\115\223\160\218\049\060\110\093\107\141\105\127\179\209\219\232\159\214\061\253\254\214\245\228\056\062\094\232\225\061\243\230\237\212\051\205\189\195\180\090\119\209\044\161\175\175\191\040\138\080\137\182\001\156\157\096\075\060\166\105\094\148\253\239\126\247\127\051\091\076\021\035\101\022\025\169\120\171\140\230\004\010\012\131\037\018\036\113\217\193\096\089\171\165\114\223\146\076\075\156\006\055\058\069\111\008\084\154\080\038\080\245\114\199\029\119\124\229\043\095\185\250\234\171\005\143\160\165\042\003\241\104\066\037\230\180\018\068\119\055\027\229\133\128\195\133\230\116\158\057\115\038\006\052\096\006\068\064\115\064\147\038\053\008\006\230\019\174\018\212\079\042\180\034\105\067\040\196\084\174\004\150\075\013\252\027\016\013\252\194\227\008\253\114\028\030\064\143\004\162\170\087\078\176\175\126\245\171\093\113\245\244\244\216\007\198\024\096\032\083\071\100\070\094\016\100\210\129\104\211\017\024\006\199\200\159\255\252\231\038\036\081\198\079\169\085\064\239\128\086\185\222\193\192\144\073\062\004\109\038\152\000\084\226\153\232\186\122\085\017\089\218\026\154\194\028\141\054\099\046\187\211\020\111\105\130\246\054\006\242\098\251\218\214\023\222\191\240\233\003\015\084\057\118\092\124\224\001\206\023\188\170\255\178\076\104\165\172\154\167\105\106\110\084\143\136\176\066\125\146\164\069\091\233\090\045\223\118\219\109\077\155\024\169\246\171\036\126\109\105\101\140\151\168\048\088\198\133\079\148\070\208\174\193\153\066\215\209\036\152\163\225\250\045\073\030\036\080\077\081\020\042\035\066\030\122\232\161\115\207\061\215\071\019\026\154\195\084\173\198\139\110\194\207\250\036\241\069\130\144\026\016\106\112\050\092\078\196\067\160\146\064\068\000\029\240\200\088\217\129\112\098\163\114\178\149\173\016\220\016\058\049\030\140\049\048\158\035\056\023\060\042\237\171\213\232\023\143\018\042\002\061\008\252\107\204\064\253\172\089\179\230\204\153\035\230\068\167\225\137\087\017\103\145\023\170\085\072\070\144\023\158\126\250\105\057\002\220\126\063\250\232\163\122\151\080\180\034\106\227\032\236\210\035\232\049\074\030\144\170\168\100\023\077\165\224\241\054\224\017\138\246\116\108\133\106\212\142\185\044\147\086\118\200\179\172\209\044\122\251\123\203\174\226\193\214\245\100\239\152\005\180\024\247\159\063\255\205\123\239\215\250\151\169\218\210\146\118\073\171\228\133\031\067\032\102\209\011\117\173\036\146\164\122\047\212\124\243\155\151\114\117\052\137\082\037\160\161\040\138\024\053\115\041\134\076\054\071\040\239\187\239\062\012\193\217\108\054\209\105\251\167\102\099\066\159\244\185\249\230\155\047\187\236\178\059\239\188\083\196\210\205\076\022\183\052\167\021\219\005\161\116\032\041\064\028\046\036\011\074\042\171\143\023\056\003\004\006\060\226\009\072\064\207\060\243\076\152\217\089\031\111\055\121\185\065\178\003\059\129\205\032\053\000\159\154\018\008\017\195\197\038\173\087\097\060\151\005\049\074\073\026\024\015\159\042\108\219\170\229\040\130\140\100\065\070\172\245\071\034\176\053\229\116\065\230\219\161\071\043\146\049\054\192\152\245\078\200\040\029\109\160\087\085\167\097\172\146\122\182\015\241\229\140\098\172\139\174\017\128\182\096\043\123\219\057\002\049\118\244\100\173\049\109\020\014\002\089\179\209\232\237\091\189\067\173\231\170\071\030\154\119\212\156\177\011\193\249\165\101\079\031\144\079\079\146\146\182\169\041\015\106\219\160\176\001\069\134\170\136\014\180\082\131\071\083\235\252\175\093\096\068\100\064\227\174\137\074\208\004\076\048\149\006\206\091\003\103\140\112\170\089\188\120\177\081\195\022\192\137\072\211\142\190\061\111\020\164\105\171\083\234\185\195\062\239\188\243\174\186\234\042\081\228\174\212\137\067\244\210\159\022\134\213\125\138\104\148\029\032\182\015\030\211\052\117\225\162\006\015\019\000\001\234\001\081\129\189\142\186\156\003\216\160\122\053\025\136\086\036\109\032\061\024\044\005\240\163\072\002\161\160\052\063\133\130\056\168\058\229\047\168\030\135\018\225\050\013\109\025\124\170\144\164\013\137\071\156\228\019\043\053\136\069\169\061\246\011\238\129\023\046\092\056\119\238\092\139\179\139\031\180\113\053\204\248\117\068\026\197\208\027\013\058\141\190\116\013\241\136\184\235\174\187\104\200\027\244\241\024\168\056\131\104\148\241\231\056\202\158\246\144\182\164\037\173\137\218\223\044\251\138\198\195\073\242\007\183\047\040\235\245\177\011\170\045\093\250\179\067\091\231\139\188\172\145\150\038\105\108\214\042\009\042\033\204\169\042\147\050\201\178\214\181\104\150\228\243\238\186\237\190\251\238\151\160\013\144\145\194\028\096\175\071\193\160\190\074\013\182\126\106\204\022\053\164\017\155\101\153\018\060\174\005\027\230\053\005\152\108\243\239\158\232\164\147\078\250\200\071\062\242\137\079\124\226\179\159\253\172\123\101\145\038\176\233\134\193\246\193\102\065\106\008\160\213\075\013\008\122\049\089\089\097\208\035\057\194\213\116\224\144\065\175\170\038\155\144\104\135\210\250\238\159\157\034\000\152\013\038\112\000\045\002\164\094\012\250\228\068\168\104\053\163\000\231\193\007\031\236\227\185\193\048\036\056\057\148\088\211\222\004\019\130\196\026\072\135\121\087\205\223\255\254\247\109\221\193\231\195\107\175\189\214\024\232\133\132\128\182\027\019\186\014\012\234\212\045\233\143\126\244\035\106\139\051\012\131\222\154\141\106\154\237\047\139\136\177\035\079\082\204\181\154\169\213\218\127\228\245\090\179\150\213\146\244\142\102\255\041\251\030\224\213\216\177\207\237\243\254\253\168\099\246\074\006\146\036\043\075\227\089\116\182\229\076\143\229\144\221\013\062\055\250\089\150\047\095\182\242\228\147\063\109\079\110\116\076\126\245\193\207\094\097\096\236\058\179\131\183\142\126\208\041\048\186\208\106\227\067\215\064\025\065\107\095\099\071\035\155\223\120\227\141\063\254\241\143\221\086\094\116\209\069\018\153\008\204\178\204\249\194\126\065\058\144\029\148\160\222\002\182\253\246\219\135\218\228\096\035\042\224\017\226\149\213\203\102\068\000\051\063\106\038\085\185\254\179\067\184\128\181\124\004\226\000\004\007\120\101\145\023\046\225\130\240\145\074\136\154\081\074\091\134\215\190\246\181\062\158\027\140\240\181\097\035\147\064\193\103\142\201\193\124\125\197\021\087\156\121\230\153\215\092\115\141\203\045\153\098\193\130\005\042\137\213\023\068\071\008\053\027\013\058\229\013\229\160\030\197\132\252\037\200\248\135\163\048\064\007\079\107\219\048\048\100\238\117\048\012\079\214\211\180\245\162\052\155\091\127\234\186\217\044\250\146\114\090\146\159\177\240\206\241\094\079\190\247\182\155\015\223\213\247\205\034\075\115\034\203\017\244\073\219\191\086\127\173\127\202\162\108\150\105\233\075\232\115\207\061\117\221\053\115\141\142\097\010\051\139\162\096\108\140\157\109\002\039\040\141\163\210\220\051\148\045\001\029\255\148\237\095\071\197\070\037\105\043\216\242\060\143\094\105\078\225\159\253\236\103\031\255\248\199\221\071\056\195\170\183\086\089\177\236\020\228\005\064\104\194\192\189\246\218\203\035\006\224\030\037\083\148\104\064\128\013\175\175\236\014\194\248\245\021\012\234\039\009\214\127\118\096\024\035\153\202\149\108\006\097\097\248\173\021\234\165\097\043\057\158\078\168\135\206\154\161\180\239\020\179\103\207\222\097\135\029\012\134\183\132\147\041\164\008\116\175\099\215\032\004\157\228\141\156\183\096\068\001\001\006\195\128\041\067\171\181\246\165\201\250\130\078\065\143\080\201\172\104\202\075\094\074\203\041\221\042\134\022\209\158\227\003\237\251\255\214\227\056\255\105\052\215\172\243\069\179\104\052\027\090\215\186\235\174\039\063\180\124\124\215\147\026\126\171\088\053\051\241\145\178\233\212\208\222\151\168\075\194\168\022\053\220\063\205\070\163\217\028\024\072\122\251\087\014\156\118\250\105\214\003\131\110\188\026\013\245\094\012\008\006\027\007\251\062\035\104\190\053\155\077\201\221\045\076\163\209\032\217\096\145\090\121\009\001\106\054\014\040\000\209\023\066\215\134\134\074\032\162\148\094\137\234\011\047\188\208\233\149\194\106\236\020\058\183\015\104\049\047\086\015\056\160\181\089\211\028\136\010\016\008\104\114\192\189\131\236\192\015\120\212\131\202\073\130\013\146\029\216\198\084\142\227\068\110\018\010\128\230\071\233\214\050\130\001\056\034\128\174\080\121\173\170\065\112\247\033\135\028\034\025\075\210\132\168\033\077\180\009\044\097\039\059\016\043\004\109\025\158\120\226\009\111\043\033\152\043\090\253\208\238\084\110\100\208\039\160\095\046\178\177\164\051\119\121\164\158\018\048\196\034\093\038\237\036\161\106\204\104\029\039\018\135\255\084\139\052\075\019\178\146\052\203\179\254\172\185\077\182\213\213\143\061\116\247\236\217\094\141\029\093\079\063\117\245\097\135\249\192\089\106\083\038\169\114\008\104\014\201\224\250\178\171\167\107\217\210\101\103\159\126\182\209\177\078\070\024\196\216\073\013\034\193\008\034\012\165\189\158\080\233\020\210\073\167\237\223\096\241\027\236\185\234\026\017\208\085\091\133\052\034\074\229\221\119\223\253\147\159\252\196\178\132\150\053\170\004\097\191\096\251\160\070\125\245\159\132\065\087\018\016\241\136\128\101\203\150\217\063\114\130\024\232\172\247\106\147\099\253\103\007\022\178\211\106\032\244\193\144\139\009\080\041\044\076\099\196\080\179\195\245\202\240\126\048\120\012\194\013\240\145\071\030\233\051\178\099\133\074\194\009\228\080\158\181\023\141\236\176\112\225\066\105\024\127\072\008\053\148\106\000\001\008\168\008\244\134\134\190\128\206\080\245\213\073\187\006\247\121\159\103\024\021\012\241\086\043\143\205\246\205\034\098\236\232\074\091\099\218\154\195\173\127\131\160\221\046\077\248\188\049\080\052\107\013\219\135\063\190\119\081\187\118\028\197\222\011\230\159\052\123\142\004\081\181\009\245\170\199\097\136\052\201\243\154\209\223\185\123\187\235\126\117\221\125\247\046\050\076\210\065\111\251\023\027\007\143\178\131\161\148\059\172\159\201\011\063\194\193\083\148\028\002\030\055\014\116\218\137\170\083\149\220\168\172\148\185\253\246\219\111\190\249\102\182\200\005\034\211\026\038\047\068\118\176\140\177\011\237\068\140\095\043\168\068\033\170\071\227\206\246\145\230\005\206\077\136\086\036\173\223\238\153\205\137\108\238\076\013\066\066\165\249\108\007\021\221\113\217\080\152\216\160\030\079\148\008\240\245\120\214\172\089\006\192\091\242\205\037\002\197\150\236\096\239\000\150\095\231\055\227\129\057\128\173\019\122\135\170\038\120\054\090\089\245\139\160\006\032\162\119\159\090\093\079\242\012\143\169\100\117\096\205\222\161\012\174\113\148\121\235\000\096\133\151\031\108\035\074\127\164\073\010\205\070\115\085\127\095\045\173\061\190\106\197\069\071\030\053\014\137\109\214\247\204\187\117\214\118\059\032\211\052\035\014\177\022\208\060\077\250\139\129\021\003\043\250\150\245\158\114\210\103\156\161\204\001\163\102\058\001\034\032\078\076\015\007\195\016\200\009\208\073\123\236\244\088\188\218\160\101\244\168\211\170\023\116\192\048\033\162\222\106\228\230\200\158\072\088\010\078\025\065\130\144\017\228\008\052\078\245\187\239\190\187\109\005\254\074\038\194\099\005\009\212\231\109\030\064\144\060\232\109\197\182\073\136\245\156\029\216\006\140\004\163\110\026\179\217\076\086\202\175\230\000\084\118\226\132\120\028\068\164\237\095\188\082\250\090\113\224\129\007\242\187\106\146\073\139\240\146\029\140\013\218\145\117\209\162\069\186\195\012\164\001\098\146\131\057\076\007\226\243\143\000\000\016\000\073\068\065\084\184\233\166\155\204\028\238\010\109\133\148\250\052\109\061\077\224\218\193\231\009\045\027\069\033\075\164\105\075\074\043\073\068\178\073\019\155\145\037\073\254\209\249\183\173\216\103\031\108\227\194\183\118\222\209\246\129\196\016\054\180\173\105\064\121\245\198\026\081\052\155\101\217\116\177\186\117\207\214\079\060\189\196\245\164\036\110\188\172\016\145\023\148\166\144\199\216\061\105\184\121\129\045\238\185\124\203\096\005\147\153\047\059\072\013\128\112\065\038\071\200\014\202\081\236\050\238\182\189\190\137\152\038\098\091\220\194\040\252\027\243\213\122\206\014\161\058\035\217\012\166\171\153\108\073\007\175\068\131\074\004\112\193\032\168\004\109\149\105\042\008\219\127\247\046\073\248\125\230\204\153\238\120\120\220\043\035\065\154\144\178\041\053\060\210\141\046\056\087\095\222\166\105\170\036\089\185\185\064\112\216\160\058\034\081\059\077\091\250\167\173\067\129\197\055\233\051\201\199\105\070\061\041\147\118\147\060\039\166\229\195\150\160\036\241\144\167\089\146\022\181\044\117\190\248\235\070\050\222\223\014\139\022\125\240\176\195\247\046\139\044\077\163\109\069\196\163\161\097\002\058\006\049\073\082\025\170\153\164\141\122\163\214\095\158\121\246\025\022\091\183\143\246\122\034\193\008\042\141\221\189\247\222\043\069\038\155\201\047\109\255\066\089\102\202\119\215\095\127\189\067\147\108\040\029\008\081\136\236\032\041\008\093\199\097\068\240\015\091\114\090\108\169\004\048\058\028\056\044\231\198\175\204\214\111\151\108\227\050\144\005\088\107\026\007\004\129\021\158\043\017\122\228\097\037\084\004\090\091\064\112\180\122\066\208\054\108\046\029\118\218\105\039\132\074\012\196\202\178\164\137\045\009\130\124\011\175\189\003\102\208\214\144\000\102\143\147\028\204\161\161\216\186\237\182\219\204\144\048\153\230\080\180\255\166\195\234\098\205\167\007\108\099\068\097\078\038\073\045\203\205\224\204\063\154\149\037\129\254\052\087\243\036\237\075\026\091\229\245\171\150\060\116\207\145\227\187\158\036\225\047\023\220\081\207\124\191\040\211\118\047\219\110\187\077\119\119\151\250\064\021\220\236\130\168\148\145\026\101\163\054\173\123\217\210\149\023\124\253\066\131\101\050\072\235\203\150\045\051\142\136\121\243\230\025\077\204\107\148\068\077\110\208\051\016\106\210\223\185\128\189\178\067\231\246\161\187\187\027\067\189\094\087\137\024\009\026\026\119\062\145\046\197\246\072\108\155\164\062\091\191\189\134\169\162\004\036\002\048\123\065\178\048\153\057\081\205\072\061\070\219\065\111\165\225\099\143\061\086\130\224\101\067\194\143\036\136\042\174\036\080\073\178\219\099\019\076\067\012\074\114\130\064\111\022\048\067\174\187\238\186\071\031\125\148\045\161\060\253\099\250\077\224\139\102\222\182\185\044\147\102\081\214\242\122\150\166\042\136\133\102\089\052\253\145\036\125\237\237\195\255\121\224\081\175\198\139\075\142\060\194\249\162\158\214\178\044\239\027\232\109\054\007\070\146\160\231\060\207\203\162\177\114\197\170\085\125\043\119\221\110\251\235\110\184\246\254\251\031\112\007\105\251\096\236\210\052\141\173\068\209\078\130\030\071\018\053\217\234\059\085\093\176\096\129\179\161\137\157\101\153\004\033\041\216\062\000\130\093\091\109\181\213\142\059\238\184\086\253\141\190\141\149\141\176\038\237\033\090\107\139\141\193\176\062\179\003\171\128\121\082\003\103\065\204\100\165\040\081\138\009\175\152\133\077\025\224\232\064\060\122\069\130\082\165\026\087\190\115\230\204\217\121\231\157\073\080\105\254\144\099\169\089\177\098\133\240\210\133\212\099\075\018\098\053\193\163\057\104\187\185\128\069\014\023\174\166\100\061\250\179\002\194\004\147\124\188\086\052\095\104\160\045\119\185\116\120\161\194\114\159\170\116\151\209\108\012\108\085\239\185\119\249\211\191\156\115\116\245\118\140\196\156\219\110\123\213\238\123\244\151\003\181\172\222\106\146\182\178\143\089\097\110\120\076\095\248\037\054\042\137\083\161\055\242\072\154\020\041\051\155\171\139\075\046\184\196\087\064\075\037\099\169\135\208\010\180\083\078\126\024\032\160\103\165\176\228\110\235\167\228\001\107\152\157\130\188\032\059\128\176\196\044\122\241\143\014\011\167\203\105\123\097\227\174\009\140\206\191\113\222\174\207\236\016\026\051\207\168\155\183\162\193\212\005\052\175\133\229\193\163\228\092\232\244\130\071\080\067\002\032\176\185\110\216\107\175\189\236\032\226\021\201\162\074\138\133\021\043\086\224\049\042\008\156\024\012\015\032\064\205\166\199\024\052\008\085\217\101\131\106\033\101\120\052\010\226\169\190\009\252\023\030\090\002\210\180\172\213\242\194\181\067\235\201\044\205\123\122\186\211\044\203\243\090\090\038\221\181\174\129\090\242\116\087\247\159\223\122\203\192\120\254\219\048\109\097\201\151\166\079\179\125\144\098\026\125\142\024\173\205\010\109\141\069\188\205\178\023\131\106\096\160\145\036\105\087\189\107\090\207\244\070\153\108\053\125\155\251\030\088\116\231\029\119\185\100\049\130\086\011\038\039\073\018\078\168\036\036\147\248\023\170\082\016\001\008\112\171\234\246\068\168\179\093\168\071\118\080\090\210\172\100\074\059\136\138\025\127\133\170\210\010\039\065\112\099\036\148\138\097\211\018\047\014\228\186\235\097\116\195\060\177\014\156\005\038\179\236\160\100\255\040\093\084\110\194\083\209\210\240\065\007\029\180\247\222\123\247\180\255\111\200\008\151\113\136\226\113\027\007\225\165\023\003\163\023\173\128\002\218\002\122\179\195\013\055\220\112\203\045\183\048\240\005\043\090\022\164\073\218\250\099\060\255\052\147\214\045\100\179\044\154\205\162\040\204\094\254\176\101\040\077\212\052\132\101\105\233\127\141\214\127\063\122\097\146\252\235\014\227\251\111\195\208\101\251\251\239\255\219\195\014\111\038\077\113\223\040\116\151\021\069\065\109\175\148\069\209\162\109\082\074\087\039\101\146\101\245\052\205\086\173\238\203\051\023\162\170\107\253\141\001\195\087\150\165\035\070\100\007\013\065\141\114\051\066\154\134\067\019\135\130\043\174\184\066\178\235\204\014\130\086\130\040\138\098\235\173\183\118\052\246\106\020\211\236\161\108\030\185\005\063\063\192\040\204\027\237\213\122\203\014\236\001\182\073\126\038\173\025\043\208\205\228\032\220\011\064\101\085\154\174\113\171\026\173\148\105\251\135\224\068\049\231\009\237\050\242\144\067\014\177\125\176\061\245\072\108\200\148\023\096\096\096\192\126\068\118\208\169\183\128\208\187\050\100\170\153\228\096\102\128\158\190\200\058\190\178\008\013\069\107\214\037\211\242\113\015\080\052\072\147\086\070\032\135\043\002\060\211\070\195\171\254\166\050\105\150\201\142\221\219\157\127\223\194\007\015\063\028\231\184\240\151\247\044\060\052\175\245\245\247\103\101\153\101\068\182\090\167\105\171\212\157\063\178\140\034\105\153\020\069\209\250\191\251\107\022\122\204\151\175\236\125\217\030\047\155\054\173\219\056\166\105\106\074\024\071\204\155\029\216\200\048\037\043\040\111\247\250\203\095\254\082\142\240\040\122\173\106\145\026\016\066\215\233\120\143\061\246\240\010\231\080\068\189\153\242\192\003\015\088\065\205\023\098\135\178\109\146\026\067\184\222\250\101\085\059\254\090\127\145\222\212\101\039\155\149\252\197\125\054\147\085\079\056\003\081\019\052\055\129\154\120\068\200\014\047\123\217\203\036\096\161\166\082\118\032\205\198\065\072\041\249\157\055\173\063\198\009\051\134\065\080\057\201\081\041\076\079\030\115\189\202\028\238\242\232\149\178\043\111\237\219\017\099\071\154\164\045\102\043\122\251\207\022\237\014\192\154\029\020\186\040\179\050\233\047\138\052\079\139\124\224\225\036\255\192\195\079\189\240\114\172\127\166\003\003\167\207\062\114\070\082\116\039\089\082\054\237\087\236\168\179\108\141\182\198\049\208\221\221\213\108\182\254\015\189\122\186\235\069\179\062\144\013\204\062\234\016\166\097\022\027\174\226\004\140\046\131\089\137\158\228\160\252\032\080\216\216\057\023\152\222\136\044\107\253\091\155\221\221\221\018\004\176\020\255\118\219\109\167\030\103\039\194\094\111\085\138\109\095\229\005\128\147\050\159\168\004\245\155\022\235\039\059\176\004\204\082\224\032\043\131\105\108\248\001\205\065\043\087\174\052\159\071\049\085\067\111\195\131\188\131\134\025\051\102\236\190\251\238\085\037\081\004\146\067\026\026\124\200\212\157\174\049\007\208\129\120\092\083\078\226\063\104\043\074\194\070\219\108\199\087\089\143\190\225\144\034\041\208\227\066\052\040\219\169\033\207\219\127\036\137\046\032\073\218\068\107\169\079\245\219\108\138\201\129\029\123\182\090\184\244\137\107\230\028\147\140\243\247\250\091\110\217\127\187\029\086\021\003\121\086\211\148\192\208\153\045\250\066\103\254\200\037\162\164\104\020\245\172\190\180\111\233\204\025\251\118\117\009\135\214\117\038\099\171\237\036\070\018\054\107\176\215\213\242\211\079\063\205\015\070\208\174\065\130\000\214\154\011\121\158\187\059\027\201\192\048\223\242\121\199\029\119\240\073\179\217\036\036\048\082\147\141\083\191\174\217\033\108\080\242\014\171\204\088\224\014\211\056\160\210\163\143\219\136\177\152\068\084\197\182\207\062\251\248\026\020\190\019\200\036\147\105\227\000\146\002\153\080\049\111\142\004\211\204\037\064\208\159\117\014\074\044\229\004\080\051\129\047\154\165\117\060\113\239\216\254\091\081\165\116\064\140\203\073\242\074\189\248\035\203\179\052\075\243\204\154\159\037\105\054\144\245\063\149\117\253\159\219\023\052\183\217\166\197\058\158\127\190\186\247\158\173\235\201\034\077\019\039\140\178\061\241\221\050\180\082\143\142\138\178\100\081\154\218\163\100\003\003\105\087\087\207\017\071\030\236\016\110\170\152\060\006\049\105\255\048\096\070\034\148\155\047\022\047\094\044\229\177\066\118\144\020\216\008\008\083\195\152\058\095\120\213\105\029\171\065\037\135\068\189\155\011\071\075\177\141\095\043\111\003\241\118\227\151\217\186\116\025\170\051\003\216\195\042\137\064\064\088\222\141\061\032\060\154\195\204\198\051\082\095\028\004\164\117\242\112\153\175\021\182\100\124\173\094\114\169\178\003\153\068\201\178\210\045\098\051\005\147\129\242\012\007\004\187\108\080\249\077\125\212\148\165\234\137\192\112\104\086\020\173\140\128\128\172\253\067\148\069\153\020\101\087\173\094\171\213\147\180\086\148\185\133\125\126\163\247\212\061\199\253\119\171\247\185\227\142\183\207\220\175\040\007\182\238\153\094\203\242\162\040\116\066\121\179\194\240\021\058\042\211\174\060\243\185\100\105\239\178\151\031\115\140\181\212\102\219\171\090\173\102\011\029\054\182\084\066\149\019\053\085\251\201\001\039\011\195\199\020\006\074\010\140\229\007\037\135\040\101\007\086\211\212\035\032\006\161\040\010\205\133\180\073\100\042\009\120\053\048\136\109\099\062\174\083\118\160\040\095\000\075\132\035\171\196\183\109\191\091\006\041\016\033\059\168\116\249\228\017\243\176\078\081\015\094\145\003\104\240\184\237\182\219\238\176\195\014\246\099\124\205\071\252\069\020\129\160\023\143\046\129\076\036\204\155\053\152\028\096\005\055\154\051\188\103\142\121\132\053\007\003\212\056\208\106\036\058\077\255\050\073\011\083\052\073\248\147\027\003\054\014\158\141\151\151\181\180\150\021\221\207\055\086\038\073\114\250\221\011\158\060\232\096\196\184\112\210\234\021\182\015\141\166\047\032\249\064\163\097\140\052\055\013\090\168\215\114\150\052\211\190\129\100\219\173\119\218\111\191\189\205\016\243\036\207\115\195\039\036\138\162\192\012\225\001\037\122\243\133\141\131\195\133\152\012\111\027\002\217\065\201\007\114\162\117\206\227\176\214\133\225\074\217\193\237\131\000\144\035\044\168\066\093\072\168\135\097\027\110\232\202\117\202\014\148\006\006\024\108\097\097\210\202\008\108\019\226\166\046\243\012\063\006\113\096\217\103\073\150\141\181\059\062\117\166\080\138\036\013\059\187\224\050\210\116\100\048\116\234\237\102\010\158\225\031\202\139\030\064\000\075\025\197\234\162\044\204\242\023\166\143\055\227\067\205\082\158\039\137\143\006\164\164\254\073\164\003\195\148\170\242\165\179\045\188\043\169\173\090\221\088\054\240\252\236\163\142\121\197\049\175\092\156\166\127\250\212\178\100\156\191\238\039\158\056\105\246\236\221\006\086\039\077\178\147\036\213\081\179\127\160\245\023\040\179\044\173\215\178\173\167\111\187\162\119\249\107\095\247\202\233\091\077\247\217\159\165\032\072\140\096\152\159\166\041\123\085\114\072\178\057\255\228\133\005\011\022\184\041\103\008\139\228\071\233\032\098\024\205\118\229\032\251\088\013\248\213\043\185\229\158\123\238\113\155\070\142\207\219\050\069\120\201\043\012\027\031\099\157\174\131\052\163\110\192\000\071\216\085\169\193\057\066\230\179\203\186\249\230\155\229\066\135\049\087\211\120\072\208\068\057\044\006\189\154\062\125\250\225\135\031\238\131\005\047\123\101\206\136\108\211\070\106\000\053\104\039\011\196\176\210\054\211\074\230\176\084\238\051\097\090\096\070\058\238\001\138\006\171\125\108\236\107\072\014\178\068\220\058\164\038\111\150\102\089\222\085\239\238\201\186\187\202\233\207\172\092\218\179\245\086\111\124\227\027\159\127\238\233\197\015\063\184\207\158\251\206\127\118\201\181\115\198\247\255\172\071\199\247\204\155\183\219\180\109\122\027\171\186\210\188\158\235\048\079\154\069\179\209\250\144\145\037\089\239\064\186\207\158\251\191\108\207\221\182\223\126\123\075\104\154\166\108\052\013\098\028\053\103\181\114\011\128\185\096\062\139\121\006\138\091\121\065\058\136\146\141\066\218\190\105\144\153\234\065\101\150\101\060\035\200\175\187\238\186\011\046\184\224\156\115\206\249\225\015\127\232\138\218\066\075\044\158\000\206\141\137\136\165\241\245\072\081\013\066\105\211\158\073\082\131\193\182\071\096\140\212\000\079\061\245\212\175\127\253\235\031\252\224\007\115\231\206\093\178\100\009\127\069\019\229\080\016\216\009\012\182\097\115\230\204\217\109\183\221\184\076\071\122\145\014\244\002\008\174\012\002\231\022\006\126\096\114\171\076\146\154\255\149\227\182\175\171\221\098\160\217\036\167\094\171\231\089\174\172\215\091\255\093\233\164\204\179\164\054\189\190\077\239\064\185\058\093\249\186\215\191\241\245\191\117\172\056\158\053\107\022\087\239\190\215\046\182\015\127\126\219\252\009\252\237\201\175\030\184\239\140\036\233\074\167\213\210\060\079\018\137\040\079\242\102\127\035\077\166\245\022\171\094\127\226\113\082\131\163\098\189\094\167\149\096\048\124\146\096\210\254\149\237\031\210\043\229\102\013\118\185\087\182\137\096\005\199\178\087\130\000\198\102\089\022\217\129\185\222\134\177\104\136\071\053\120\124\182\248\202\087\190\242\141\111\124\227\138\043\174\240\121\219\180\018\252\166\000\224\004\204\027\013\217\120\123\162\031\132\174\244\142\212\192\029\082\067\236\026\028\040\100\007\012\156\034\014\000\143\038\140\239\236\203\099\160\179\178\162\069\146\144\149\110\213\016\165\035\254\229\122\144\029\184\204\177\130\076\111\055\107\132\007\024\194\070\134\120\020\031\252\166\166\209\104\118\039\249\064\081\253\107\019\222\143\009\211\218\215\123\089\210\250\251\203\181\188\198\249\181\090\061\203\235\170\173\237\073\035\127\126\245\051\251\204\216\251\191\191\239\125\251\206\218\235\160\131\014\058\234\168\163\014\061\244\208\025\051\102\172\092\177\226\229\199\188\242\206\178\255\179\059\237\053\166\158\058\152\014\155\055\239\045\123\207\092\209\092\145\166\073\150\166\101\146\021\105\090\175\247\172\234\235\061\228\160\035\118\220\113\251\157\119\222\217\104\154\048\044\141\144\080\050\051\073\146\052\077\147\045\229\039\056\029\010\236\032\024\020\067\041\065\128\232\101\172\131\134\250\010\105\218\050\092\125\212\132\103\148\241\200\087\141\134\251\156\166\182\141\070\067\061\096\134\096\216\096\229\139\130\179\023\201\049\083\244\003\163\075\105\170\155\171\078\071\146\130\025\107\203\128\176\111\228\145\090\173\022\034\049\007\049\180\172\094\113\101\154\182\156\021\060\046\029\172\102\033\129\083\132\056\191\075\013\160\083\105\072\134\174\218\070\147\205\186\012\091\210\052\021\064\192\100\230\244\037\003\141\178\064\140\011\156\206\143\211\187\187\204\209\001\065\149\212\201\040\007\250\167\167\091\247\054\203\102\109\245\155\222\252\230\099\143\059\122\143\221\119\063\230\152\099\094\254\242\151\219\163\057\196\237\191\255\254\206\113\043\086\046\219\174\123\199\051\238\153\247\248\193\007\143\171\083\204\167\150\013\215\147\073\217\232\170\119\021\173\175\170\229\244\250\246\221\061\061\175\063\241\248\221\119\223\221\005\115\028\043\152\086\065\043\096\053\032\182\000\136\079\217\033\054\203\166\183\000\174\038\002\002\058\109\172\172\054\250\225\019\068\197\224\173\153\037\242\045\189\166\149\115\052\225\216\042\134\141\064\140\059\059\048\000\170\212\096\210\210\222\198\129\246\108\112\025\233\112\193\042\060\180\055\231\149\236\084\002\034\128\198\000\008\060\156\008\008\143\128\103\151\093\118\137\015\227\120\164\003\062\146\134\120\007\048\232\241\233\167\159\070\108\238\096\029\019\216\171\004\132\205\103\100\007\175\106\201\180\009\038\218\031\041\000\000\016\000\073\068\065\084\252\077\106\071\136\036\073\138\188\043\201\242\162\217\215\085\031\216\110\218\244\090\115\122\127\222\187\255\126\251\253\193\031\188\127\214\204\153\071\183\127\179\103\207\182\107\176\125\056\224\128\003\246\243\069\097\239\189\109\217\142\058\238\072\231\139\015\061\189\138\144\113\097\250\035\143\252\227\225\071\236\058\224\206\179\203\237\067\079\045\127\126\213\178\215\188\250\213\219\111\183\109\140\102\189\222\058\086\144\201\076\051\071\137\238\004\147\059\031\055\071\218\236\053\017\196\063\235\196\051\051\005\054\024\083\035\011\097\020\075\001\141\077\137\006\068\039\132\186\032\119\199\185\104\209\162\075\047\189\244\154\107\174\177\040\154\011\157\060\027\154\030\119\118\160\016\075\120\129\162\102\044\071\152\171\178\003\075\220\199\220\120\227\141\174\033\197\129\221\132\041\141\019\127\184\064\201\095\106\000\173\030\184\207\087\046\065\201\125\085\037\039\238\177\199\030\178\131\026\204\058\034\074\026\002\052\095\219\155\232\218\091\032\147\156\205\023\012\004\134\048\065\201\058\222\083\035\255\078\203\187\086\053\155\073\054\190\049\234\106\253\125\134\132\127\006\154\101\119\173\107\215\233\059\061\177\116\105\179\167\246\206\119\189\243\216\255\159\189\059\129\210\171\044\243\069\255\125\053\101\038\140\033\016\008\024\072\032\012\033\019\144\016\194\060\009\042\008\078\221\173\119\029\151\109\123\187\251\222\238\123\238\185\125\078\175\118\221\118\217\109\183\067\179\108\219\001\181\029\064\005\007\016\069\065\100\082\102\008\040\050\009\004\136\065\080\230\073\192\204\169\170\243\171\250\195\235\182\170\082\169\084\170\042\085\069\215\250\243\250\236\103\063\239\243\062\211\251\236\119\239\015\117\209\188\221\119\223\077\103\208\023\102\207\158\237\221\109\218\180\105\142\012\123\238\185\231\222\157\127\211\166\077\123\246\217\103\230\204\154\123\203\115\143\093\178\133\255\211\213\236\255\243\095\222\251\134\237\118\092\189\110\085\157\209\013\019\090\198\182\028\122\216\193\082\233\036\152\215\010\014\114\173\086\171\201\059\184\068\227\040\039\200\037\206\200\005\095\212\170\007\164\066\229\133\108\006\114\170\170\253\108\129\217\071\040\114\223\032\046\188\240\194\207\126\246\179\223\250\214\183\028\201\237\017\213\110\137\062\106\216\122\177\045\171\060\150\005\106\087\020\108\087\221\129\027\186\003\194\165\223\099\110\189\245\214\251\239\191\127\229\202\149\056\236\147\114\064\244\008\014\171\030\069\057\110\220\184\034\166\152\166\079\159\046\154\166\040\026\107\209\028\088\084\220\095\120\225\005\102\184\059\202\096\195\108\223\249\097\095\017\240\186\214\084\127\197\079\131\091\248\171\230\196\245\029\255\165\239\177\173\173\227\155\198\180\181\078\124\106\213\043\007\029\124\200\187\222\249\150\169\187\078\213\023\202\123\132\152\239\180\211\078\250\178\238\044\224\122\132\079\015\194\238\133\110\204\246\205\143\213\155\255\249\238\187\087\206\217\226\255\241\168\255\185\207\222\237\181\245\205\077\227\095\090\189\254\228\019\079\230\142\131\131\111\204\178\201\187\164\216\168\089\084\051\158\108\226\143\142\132\122\197\246\116\084\186\242\168\059\104\013\008\222\137\131\177\143\062\218\083\126\212\116\106\248\225\015\127\168\224\037\072\012\251\062\189\143\171\244\046\182\101\221\033\186\228\146\231\118\169\007\148\022\160\059\056\243\216\183\234\204\235\165\151\139\235\175\191\126\197\138\021\238\146\175\250\099\034\078\021\028\222\163\243\079\173\136\096\110\233\023\062\098\229\210\066\052\083\149\238\032\232\154\168\222\028\073\099\119\157\152\035\011\092\000\054\043\035\027\213\168\164\184\063\110\220\152\213\235\090\127\115\224\129\047\204\156\249\212\236\217\079\204\158\189\098\206\156\123\231\206\133\095\204\157\119\235\188\121\183\204\155\127\235\188\249\203\230\205\191\173\147\190\101\222\130\021\115\014\249\097\227\152\241\045\019\026\091\118\124\121\205\203\227\038\055\191\253\029\103\205\159\119\128\147\129\214\224\200\176\255\254\251\235\002\083\166\076\209\023\004\223\142\181\156\103\154\128\203\131\091\198\141\027\054\030\113\248\226\187\234\141\255\247\067\207\254\251\126\007\125\114\191\057\255\177\255\033\159\159\061\247\083\251\031\114\246\126\135\124\122\255\014\224\156\061\107\142\203\079\204\154\243\047\251\030\244\255\191\225\192\255\185\247\254\255\223\094\251\127\227\137\023\182\027\179\211\250\117\141\059\110\191\211\220\005\251\233\065\052\211\239\049\096\045\078\169\007\206\226\104\016\104\094\007\085\058\156\145\059\122\185\120\246\217\103\213\045\151\133\215\200\059\005\172\200\093\162\227\154\056\132\232\113\244\102\097\043\217\092\102\201\157\243\029\177\222\167\016\024\088\244\191\059\120\184\241\223\190\229\134\151\011\109\066\238\053\136\216\103\087\019\008\157\145\099\032\052\065\152\138\070\001\233\139\162\022\142\209\071\044\095\176\076\039\111\212\134\044\100\021\241\181\109\172\008\196\128\000\032\070\040\132\130\253\016\251\005\208\142\005\155\007\214\183\214\174\088\245\236\244\251\238\219\233\225\135\119\123\224\129\105\015\060\048\243\158\123\230\220\117\023\044\184\235\206\035\238\188\115\201\157\191\056\226\206\095\044\190\243\023\139\058\233\037\119\222\049\243\158\187\255\226\190\123\086\175\111\088\213\250\202\145\071\030\245\166\055\159\180\235\148\041\106\203\145\225\192\003\015\244\113\065\168\117\112\059\083\036\045\199\000\163\044\104\022\194\174\059\120\221\080\136\047\190\242\252\148\029\102\092\190\246\165\255\247\193\095\254\143\007\239\253\239\203\031\252\127\030\088\241\063\150\063\244\191\030\092\222\049\046\095\249\191\150\175\252\224\067\043\062\248\224\138\015\062\244\240\135\086\172\252\248\035\143\126\238\215\207\124\230\209\167\126\240\204\154\122\251\184\090\243\203\127\250\238\055\089\154\078\199\007\217\180\156\077\098\045\163\132\074\183\007\169\075\142\023\247\209\163\003\126\179\243\099\164\042\229\044\112\214\168\122\121\087\188\022\121\142\003\102\239\104\107\243\251\079\093\172\250\034\220\187\170\045\189\219\159\238\144\053\216\106\235\218\183\162\096\235\122\170\235\017\062\022\112\035\002\025\137\001\218\008\008\113\049\006\118\130\090\084\178\170\039\028\163\179\168\242\069\144\183\132\098\178\068\064\030\097\081\119\071\048\054\097\186\026\226\160\155\078\016\030\239\139\142\062\124\193\220\185\139\023\030\125\228\225\199\028\121\232\210\035\230\047\089\122\216\209\071\030\118\212\146\195\150\046\057\236\168\035\014\093\186\120\033\184\060\134\192\081\139\142\061\230\200\227\143\059\234\196\227\143\062\233\132\099\143\248\179\063\125\199\126\251\237\227\115\163\214\048\103\206\028\159\030\167\079\159\190\075\231\183\094\075\088\168\154\005\151\054\176\174\161\083\207\152\049\195\239\023\198\253\014\222\253\148\055\030\123\242\137\111\060\249\164\147\079\058\233\184\227\078\058\234\196\147\143\061\233\228\227\079\056\249\216\163\079\062\242\184\083\150\030\119\242\209\199\158\124\020\254\241\039\045\061\250\132\197\139\142\155\119\228\113\011\142\060\113\238\105\103\029\245\127\253\245\255\185\247\222\211\245\154\041\083\166\040\009\221\199\018\010\067\150\001\161\226\049\171\054\240\090\186\141\163\000\206\014\192\059\158\242\055\224\050\007\117\097\204\062\250\072\003\073\083\228\197\116\244\016\099\203\186\067\204\205\200\085\096\052\216\195\090\163\083\144\034\144\245\248\032\010\004\130\112\186\143\132\157\060\109\134\008\071\064\061\137\008\085\230\082\174\023\232\008\129\075\061\008\029\201\081\048\010\102\192\023\101\228\200\192\071\237\210\187\192\248\137\099\119\153\186\211\248\201\077\045\019\026\198\108\215\050\110\135\177\045\147\154\198\076\106\030\059\169\101\236\164\230\113\219\181\140\159\012\136\166\177\029\252\166\150\241\141\099\039\054\079\222\105\226\244\055\076\155\182\199\052\125\161\028\025\202\051\220\115\204\114\214\170\002\007\223\210\218\135\117\189\125\248\141\211\033\098\252\184\150\150\177\077\205\045\077\045\099\026\155\199\052\142\025\211\052\102\108\243\216\113\045\227\199\143\029\055\126\236\132\137\227\039\077\154\048\121\242\118\219\111\063\121\167\157\118\156\050\101\151\169\083\119\221\099\207\061\044\173\049\232\071\250\190\142\051\110\220\056\126\065\115\115\179\017\146\217\098\128\213\193\165\116\027\071\046\226\005\251\189\104\219\014\019\038\076\080\213\252\005\046\163\065\193\071\172\047\206\070\070\135\117\238\163\132\230\033\198\150\117\007\198\241\173\010\028\080\208\026\132\151\011\206\079\158\060\025\039\136\100\161\067\240\025\208\130\053\102\204\024\242\122\001\231\009\099\130\102\049\105\210\036\119\209\212\058\059\104\016\005\014\041\150\115\043\074\016\035\023\092\224\053\079\017\188\064\076\156\056\209\081\220\022\085\016\182\247\097\157\127\135\031\126\120\231\127\110\114\056\252\240\014\129\195\059\255\022\045\090\228\063\023\046\092\232\043\195\172\089\179\108\209\157\118\218\137\090\169\081\163\086\233\017\150\206\241\193\119\007\063\103\088\154\158\035\094\251\091\188\120\241\107\100\199\127\046\121\237\239\200\206\191\165\149\063\119\088\121\240\193\007\059\125\232\251\118\136\117\037\151\126\171\055\055\191\218\032\164\085\222\113\024\019\223\017\066\097\028\005\080\162\190\142\113\057\224\102\137\000\162\234\038\026\122\119\089\103\215\106\133\139\100\208\187\252\000\222\221\226\238\096\237\152\152\145\255\136\140\182\177\010\243\252\033\003\178\238\022\162\160\092\186\133\105\150\210\241\108\001\004\014\208\160\089\122\179\112\087\023\160\051\112\094\048\043\175\048\106\139\228\232\131\032\232\140\002\104\075\031\112\192\001\011\022\044\176\069\237\204\094\096\179\150\187\132\245\133\067\015\061\116\238\220\185\118\184\135\191\194\082\085\194\219\165\040\187\135\078\106\020\049\073\173\196\059\136\233\148\104\049\182\122\119\224\087\193\078\208\080\064\075\098\185\214\096\105\077\095\247\183\052\205\198\230\230\142\214\208\220\220\049\090\142\167\150\235\110\201\040\224\168\088\095\037\061\044\185\169\140\185\111\004\065\064\111\145\131\102\169\007\073\108\238\252\183\069\040\220\162\233\091\041\188\197\221\129\125\192\104\126\002\135\033\004\062\031\100\061\054\217\204\085\096\018\048\086\097\174\013\047\154\154\066\248\094\177\020\040\062\097\211\211\032\028\028\200\104\010\014\108\128\025\225\173\029\135\193\124\190\240\043\134\216\045\162\231\236\224\169\235\025\238\253\223\033\223\102\235\005\182\113\021\228\205\114\244\216\109\183\221\168\210\100\101\068\178\162\191\247\145\024\097\079\123\241\247\106\163\185\248\108\225\244\081\224\178\011\124\230\012\180\003\132\209\210\050\200\126\167\149\180\006\106\065\066\065\251\179\004\040\024\206\090\043\038\073\116\136\145\062\042\090\046\200\169\015\147\142\015\252\226\059\103\141\128\224\123\100\136\133\032\131\222\020\236\139\156\163\205\165\097\083\098\131\196\223\226\238\016\059\024\202\092\249\006\014\203\058\130\183\158\240\082\238\110\196\140\152\128\128\004\194\037\184\052\005\238\184\227\142\251\239\191\223\150\160\007\095\093\162\041\039\032\202\118\142\190\016\160\125\116\000\132\187\163\000\252\173\122\097\071\121\080\120\228\034\236\109\180\039\176\125\222\059\068\044\002\132\119\221\117\087\179\188\237\211\144\205\217\101\137\234\114\221\105\137\147\017\251\150\013\049\192\057\142\078\064\000\229\129\253\095\160\155\000\121\144\059\213\076\131\108\074\034\133\128\000\028\202\083\042\018\202\048\194\238\118\055\099\164\115\212\185\175\146\191\249\205\111\212\042\095\120\202\077\163\032\000\034\076\004\160\123\129\192\202\166\233\001\121\232\069\126\096\111\245\167\059\176\047\182\074\182\148\203\119\129\135\124\232\098\037\225\160\112\016\056\070\211\005\075\139\125\229\149\087\148\163\075\080\232\250\075\004\068\185\052\008\029\129\114\031\062\157\053\240\077\031\029\136\167\241\197\238\178\247\060\240\133\069\024\061\055\108\051\151\189\131\076\129\041\154\130\164\208\080\213\028\253\125\025\205\002\211\229\130\030\102\116\001\102\064\000\072\022\164\042\140\052\064\150\067\016\032\009\153\104\116\075\030\181\048\006\163\071\025\212\167\015\147\079\060\241\132\145\107\034\032\038\128\047\059\056\001\126\136\094\070\173\095\023\022\064\160\161\047\083\122\209\182\165\183\182\184\059\176\015\024\202\220\228\059\213\195\109\151\150\119\169\154\017\221\097\034\224\011\147\145\018\133\162\068\200\163\113\204\021\011\021\227\146\036\049\221\001\180\006\079\027\221\065\073\025\241\009\143\002\112\132\155\016\095\060\040\242\134\201\253\112\070\250\200\053\190\004\202\067\186\051\042\030\199\076\151\250\090\241\081\052\010\061\018\009\246\003\203\141\170\052\181\234\018\196\001\188\020\171\109\004\014\040\108\146\136\094\160\030\192\190\016\067\019\161\023\225\001\191\181\197\221\129\005\076\004\009\102\113\146\205\122\153\006\119\249\239\044\228\046\026\122\244\063\076\035\061\029\221\097\252\120\135\076\211\181\009\205\210\044\154\141\194\007\090\067\160\158\068\028\109\162\187\163\012\098\232\076\206\041\049\009\208\035\026\241\194\040\155\234\068\073\024\185\105\148\107\124\173\065\181\140\104\031\055\101\188\186\205\243\178\090\171\074\087\016\202\020\183\160\092\246\072\248\136\227\052\045\104\194\005\061\202\012\030\179\161\127\170\025\010\210\012\050\205\122\064\112\222\232\025\040\052\069\179\016\116\065\110\137\032\037\222\035\192\059\115\218\132\112\080\133\095\100\196\148\036\040\050\250\093\230\214\168\025\005\135\047\222\173\196\033\110\114\063\192\031\233\144\181\064\238\084\075\025\213\137\135\129\177\056\200\229\066\143\116\066\078\245\062\187\000\193\023\174\129\056\160\131\240\067\247\050\250\214\227\193\041\104\213\185\189\200\015\236\173\254\119\007\230\050\090\190\065\142\109\105\035\154\219\246\185\075\134\138\008\032\002\183\130\092\218\009\052\016\086\037\222\183\019\077\225\112\153\089\132\201\064\058\130\253\163\239\056\179\101\250\072\031\249\040\134\197\011\113\000\113\195\132\194\031\209\004\031\129\059\160\054\164\059\069\130\198\177\121\248\059\162\029\172\026\207\083\040\028\231\092\167\221\114\217\015\066\184\196\071\172\016\194\069\057\244\067\079\191\167\244\167\059\196\196\152\203\110\214\075\057\240\196\104\051\219\231\104\054\069\018\209\035\220\037\230\129\169\029\104\010\115\230\204\241\147\152\047\115\152\110\153\162\059\000\133\070\112\010\165\025\225\214\232\003\199\253\052\096\195\036\176\137\192\040\112\147\035\192\041\080\042\041\024\163\060\114\086\234\139\143\196\010\061\010\008\221\193\147\140\155\197\151\042\141\201\095\064\108\010\054\130\013\005\066\071\018\054\037\057\072\252\063\238\014\125\094\132\161\032\199\032\229\028\040\016\002\094\065\085\025\225\042\114\203\092\098\074\196\051\211\043\119\254\197\030\052\133\132\233\209\023\186\064\184\051\119\020\140\028\132\226\136\099\145\238\160\003\166\020\010\127\020\016\178\201\041\233\150\217\002\028\180\118\063\010\028\140\011\201\038\103\093\166\110\157\121\049\003\076\183\240\017\128\046\112\025\084\057\226\227\176\108\095\216\032\002\229\086\100\134\114\236\127\119\096\125\192\116\176\207\211\032\252\184\160\196\129\027\098\033\052\196\084\134\017\007\248\009\033\076\228\188\227\131\042\113\118\088\186\116\169\135\009\102\004\204\165\161\010\225\054\113\212\128\131\016\119\124\142\245\122\085\124\015\115\116\140\178\041\251\129\074\224\163\209\037\223\149\077\124\068\067\232\017\058\114\147\229\197\011\181\106\047\148\075\183\108\010\239\026\133\131\008\220\010\170\151\162\228\123\228\158\123\238\105\119\160\133\043\250\035\057\052\099\063\187\003\227\216\202\098\105\134\244\005\153\070\184\101\195\235\121\008\222\102\036\140\232\014\124\194\206\011\066\224\201\185\215\094\123\033\168\005\194\166\067\008\163\054\033\226\136\209\132\056\040\014\206\014\090\036\034\024\053\062\114\071\054\003\165\162\208\003\014\174\089\179\006\135\000\026\018\010\196\232\128\214\000\124\041\126\113\220\235\006\078\065\110\037\056\133\025\194\014\058\248\224\142\255\101\045\179\074\136\114\107\200\198\254\119\007\038\050\090\118\089\015\250\066\186\003\026\095\161\019\000\254\103\087\035\092\002\002\016\032\046\036\117\004\071\006\061\066\068\040\137\006\119\129\100\023\096\006\086\009\049\114\199\226\130\048\122\176\184\004\049\225\017\194\056\210\017\047\140\192\071\144\220\128\155\121\079\196\116\119\164\123\026\251\057\002\161\149\061\066\245\102\068\120\182\233\023\008\156\034\022\218\037\160\033\002\059\236\176\195\204\153\051\237\011\129\130\114\183\086\035\050\068\232\127\119\096\046\163\065\118\075\107\176\183\025\174\065\242\202\161\000\013\036\069\138\207\008\151\005\046\077\039\070\024\108\015\211\169\162\208\045\098\166\100\012\017\218\056\106\080\252\226\117\034\032\032\124\135\081\227\035\095\128\095\032\179\105\013\070\052\031\141\037\008\196\112\070\013\184\019\215\050\242\075\119\208\016\115\105\036\016\184\005\161\141\104\101\029\221\140\000\000\016\000\073\068\065\084\080\015\078\211\226\003\097\102\116\107\200\208\207\238\192\080\168\230\091\125\103\111\075\252\186\117\235\028\004\252\078\075\128\039\036\141\061\130\231\186\131\190\096\204\116\156\204\138\188\032\022\002\159\242\092\142\166\145\095\078\079\194\037\014\028\236\037\092\035\212\107\030\241\081\102\121\007\074\197\008\220\177\007\164\030\001\196\140\163\006\028\228\178\002\134\060\029\029\028\160\056\200\095\040\151\093\008\159\036\125\135\018\028\161\131\094\036\187\076\028\192\203\126\118\135\088\192\098\118\011\129\064\128\172\007\194\225\125\193\209\136\064\145\068\224\023\142\075\180\185\154\002\100\034\037\056\116\186\005\145\049\002\038\144\068\007\180\133\024\233\035\151\189\082\233\014\219\182\020\006\041\140\242\040\113\001\079\165\088\174\229\017\097\069\221\129\239\238\162\071\077\066\249\194\107\062\242\148\083\105\013\008\173\033\052\001\192\049\002\034\048\203\101\160\030\032\037\129\015\225\015\229\184\181\221\129\209\129\004\203\061\032\056\032\247\083\166\076\113\011\205\243\066\184\044\192\036\015\226\072\030\204\005\124\032\086\070\132\176\254\254\247\191\127\229\149\087\240\001\167\192\229\072\068\236\103\185\008\248\036\009\137\000\206\232\003\103\185\201\065\176\103\050\098\074\253\212\169\083\141\035\208\229\030\076\086\234\224\006\215\060\032\121\170\110\003\076\240\210\093\004\066\096\034\000\001\033\076\244\131\133\238\128\160\010\220\026\122\244\179\059\196\135\234\024\211\185\017\184\229\177\128\014\191\199\081\035\072\197\132\032\140\048\246\008\026\180\134\223\253\238\119\010\011\061\058\192\083\142\120\062\248\225\106\242\228\201\162\033\002\056\163\012\220\228\023\239\064\185\003\151\141\082\233\113\234\237\026\061\202\092\230\014\175\237\130\180\006\035\223\005\225\229\151\095\246\245\033\119\141\004\202\024\121\151\160\093\058\082\137\015\166\075\098\128\024\098\244\179\059\176\146\195\192\085\118\035\032\132\017\004\194\045\098\128\054\006\017\011\141\047\100\128\008\196\162\011\240\011\071\037\249\168\035\100\152\150\160\196\008\136\017\013\015\153\221\119\223\221\071\135\226\041\098\068\123\084\053\062\190\072\025\200\053\200\160\118\016\072\168\079\084\104\083\070\116\042\227\038\047\010\124\125\003\005\111\035\024\109\120\183\060\225\170\110\162\193\220\128\064\032\086\230\250\197\087\205\155\075\038\200\221\033\027\251\211\029\138\161\220\006\009\094\255\218\159\091\170\220\059\133\030\249\200\035\143\184\228\054\103\120\011\136\046\112\183\192\045\116\070\068\129\137\224\050\085\133\166\182\042\134\030\137\224\005\176\220\033\203\243\019\109\231\240\142\167\152\163\009\060\226\023\036\131\246\137\118\144\227\131\091\010\134\227\163\195\095\238\196\017\206\174\090\181\202\246\182\065\000\147\191\171\087\175\182\231\037\186\136\225\119\129\091\230\018\187\227\142\059\174\190\250\234\101\203\150\061\241\196\019\122\132\089\093\036\135\224\178\063\221\129\089\108\229\179\174\198\110\221\129\051\094\168\140\110\233\011\183\221\118\027\199\086\172\088\065\012\199\200\097\110\163\187\163\240\171\004\026\204\042\080\064\170\202\183\125\156\162\132\076\161\071\034\033\050\204\118\134\244\146\105\195\112\109\164\123\196\157\238\224\020\200\032\007\171\013\130\203\248\210\170\063\118\159\213\103\206\176\016\076\042\139\041\090\158\118\192\065\027\036\059\197\248\210\075\047\117\017\227\062\152\133\015\008\151\224\105\171\047\124\226\019\159\056\247\220\115\151\047\095\158\157\021\001\050\067\134\254\119\135\046\173\065\095\212\041\159\122\234\169\219\111\191\253\193\007\031\116\201\135\248\099\036\108\228\054\102\021\225\100\012\191\208\136\064\073\005\010\075\208\069\028\159\048\133\081\139\030\209\208\242\124\153\051\114\147\107\048\162\221\233\209\120\078\129\012\130\012\234\008\001\097\094\251\230\130\024\077\208\239\116\124\163\166\160\065\216\222\030\159\078\019\197\071\165\091\232\016\234\089\040\068\009\097\196\244\026\114\211\077\055\093\127\253\245\154\005\121\124\204\161\068\127\186\003\043\161\234\182\190\016\096\250\101\001\077\128\135\016\135\249\006\125\116\204\172\130\060\112\202\232\021\093\131\160\179\143\170\134\191\024\095\102\205\154\229\187\131\074\138\215\195\223\230\254\089\200\083\121\212\029\032\013\194\136\105\231\232\014\210\218\063\181\195\106\150\178\103\015\055\253\156\239\109\145\167\090\003\200\172\238\224\088\237\046\218\072\018\016\016\078\008\052\160\129\128\221\244\194\011\047\120\214\102\251\224\224\015\025\250\211\029\098\028\067\185\013\178\203\115\029\001\182\219\110\187\189\247\222\059\002\113\082\250\129\112\152\125\028\205\053\043\016\107\064\155\171\059\228\025\139\030\029\176\049\116\007\095\230\084\018\055\071\135\083\093\188\144\077\144\065\035\031\121\170\047\020\120\051\149\083\191\222\117\153\053\226\046\021\057\048\155\131\059\239\188\179\189\096\075\123\094\218\035\188\054\218\038\238\086\017\121\097\129\240\011\145\075\045\102\143\061\246\016\034\170\034\028\254\208\140\253\236\014\012\005\022\243\025\156\124\210\035\016\130\018\211\009\128\232\016\227\179\226\128\220\202\232\110\144\203\234\072\030\196\212\148\050\018\118\028\213\032\112\170\194\035\154\118\106\080\001\252\226\020\103\121\013\035\211\163\222\172\230\020\240\017\210\023\184\012\054\018\175\157\155\160\183\249\035\234\030\007\117\007\222\041\254\192\022\000\005\204\015\035\032\004\196\024\090\088\196\001\077\222\136\031\168\118\033\194\129\112\134\114\236\103\119\096\034\115\003\254\240\092\143\208\032\124\119\017\026\174\018\000\124\050\008\064\000\098\179\016\053\016\044\160\010\004\200\232\082\196\117\031\244\102\149\140\020\129\125\247\221\119\199\029\119\228\026\167\120\013\035\197\242\045\178\147\095\124\004\110\130\034\145\202\140\046\157\029\156\158\182\072\225\112\022\230\154\042\229\172\250\183\047\060\249\209\008\207\206\152\045\026\128\054\002\002\066\152\002\046\003\071\075\047\041\234\063\151\067\060\246\191\059\196\153\152\107\219\115\201\168\065\224\228\057\224\018\077\012\208\004\000\167\000\063\040\028\004\078\070\132\152\042\029\161\009\208\152\233\166\100\192\037\032\134\063\216\009\221\237\244\034\166\002\184\198\089\232\081\166\251\172\145\200\225\026\007\121\042\155\250\002\216\069\198\240\071\083\119\080\162\062\163\120\106\022\240\209\183\131\236\014\185\115\089\069\118\135\017\220\173\194\011\151\099\136\040\117\191\085\021\027\036\186\063\221\033\142\049\008\145\017\001\028\208\032\085\128\223\114\240\003\076\008\157\145\036\160\073\114\219\136\174\194\093\192\087\073\001\177\148\020\085\080\132\209\080\046\135\033\017\071\140\192\035\064\020\059\249\053\101\202\020\221\001\225\086\225\143\086\130\143\018\042\149\192\229\116\007\206\122\186\230\137\130\006\098\162\212\005\248\035\005\059\237\180\147\095\169\253\066\225\113\104\071\024\157\026\028\171\141\092\168\250\229\082\001\003\025\064\224\064\033\156\170\068\038\083\240\135\024\253\233\014\076\100\110\082\104\012\100\029\193\067\089\231\018\001\098\065\113\053\151\101\036\079\184\042\089\189\229\046\157\041\035\163\074\050\138\175\174\012\069\114\164\016\130\000\156\229\151\049\102\123\096\250\221\203\243\129\107\225\151\091\017\232\215\056\076\039\113\141\143\192\089\121\151\080\079\017\035\218\067\085\139\204\054\232\209\122\115\123\228\015\079\166\156\238\178\203\046\246\130\214\000\078\016\058\197\243\207\063\175\122\025\092\124\081\015\046\141\085\224\084\033\044\170\093\208\170\204\033\163\251\217\029\098\159\221\011\146\013\008\224\185\124\075\179\148\071\166\203\072\000\071\056\140\208\163\219\100\192\045\160\147\114\058\041\004\177\214\122\188\212\153\091\148\160\135\051\098\167\081\185\176\147\107\128\224\157\067\035\240\142\143\046\195\119\107\244\129\107\065\018\042\149\090\003\040\125\180\179\003\194\035\087\028\248\046\086\198\160\208\166\135\051\252\071\031\146\236\106\190\232\011\042\214\232\215\010\191\077\034\098\060\095\128\107\128\008\179\199\209\025\068\100\082\027\036\161\071\177\065\098\246\179\059\176\146\197\032\217\129\028\011\007\218\200\037\099\044\230\127\080\189\012\077\073\224\018\097\044\112\025\229\244\208\012\182\016\208\047\088\190\211\084\037\011\061\012\009\190\179\138\059\044\231\145\203\244\008\076\111\167\062\073\242\133\143\110\001\049\252\081\012\062\138\003\036\161\233\014\210\234\210\173\156\161\184\223\061\014\226\006\110\141\008\232\014\092\099\176\118\000\092\227\178\227\067\140\087\000\090\006\031\001\135\152\113\083\208\049\053\026\026\034\188\041\177\065\226\247\167\059\196\080\035\176\155\231\178\107\084\229\070\222\122\188\227\244\197\098\026\054\037\086\052\083\165\128\052\005\035\249\053\107\214\232\062\232\077\077\028\134\124\102\007\042\003\132\136\145\206\159\139\023\047\246\114\033\110\156\197\025\221\072\004\120\202\095\233\003\091\008\146\089\187\200\015\251\078\157\093\130\096\022\078\034\134\024\230\096\173\114\213\247\237\127\224\148\145\167\070\111\079\140\071\107\130\014\191\036\001\167\023\216\077\130\067\161\160\017\134\094\132\007\227\086\127\186\003\059\024\010\140\046\224\131\172\243\071\032\208\008\098\085\144\047\008\191\203\101\152\025\221\162\153\018\058\105\019\083\101\004\008\167\080\028\031\243\200\016\030\198\117\195\186\090\140\212\017\160\152\026\066\119\152\061\123\182\244\115\147\179\036\161\099\206\232\253\135\131\060\229\175\180\074\165\132\114\223\008\202\038\207\073\222\039\086\137\146\041\128\057\204\017\035\185\182\235\174\187\242\145\059\188\000\102\171\216\167\159\126\090\167\064\079\157\058\117\225\194\133\126\168\066\187\203\071\194\232\030\033\056\062\085\016\035\019\253\061\138\013\030\179\159\221\129\065\204\101\180\112\200\052\032\002\039\040\187\087\251\140\012\049\064\011\004\032\170\112\011\170\028\052\014\020\229\041\035\005\020\088\069\235\221\107\175\189\186\107\051\119\184\129\035\192\042\214\066\104\151\188\083\040\062\058\008\020\143\092\150\091\238\142\074\112\016\056\171\090\084\072\210\202\125\176\013\108\030\167\066\039\041\002\197\125\242\133\030\017\004\167\014\056\224\128\108\126\233\182\177\153\237\215\138\071\030\121\004\045\221\243\231\207\063\252\240\195\223\240\134\055\240\151\128\187\189\064\160\040\052\138\003\244\034\057\072\183\250\217\029\216\026\040\107\224\000\072\185\081\215\228\018\196\226\136\133\238\062\010\089\143\049\202\044\133\066\033\181\250\130\002\002\132\075\043\010\180\187\221\021\014\067\014\095\088\197\077\008\109\244\106\186\223\126\251\025\237\013\142\240\008\147\216\232\006\031\121\202\095\105\085\033\018\090\032\173\042\199\087\024\175\141\009\002\225\016\070\179\140\195\025\146\203\060\239\212\007\031\124\176\180\162\195\225\236\139\047\190\232\236\128\227\051\147\091\207\062\251\044\247\117\007\028\136\024\162\011\184\047\068\162\161\230\041\113\009\093\100\006\251\178\159\221\129\089\108\149\179\140\008\014\243\193\200\037\064\144\225\057\032\136\005\046\001\007\180\006\049\042\151\056\085\144\143\090\117\067\161\024\165\146\092\154\101\196\169\202\135\054\011\066\015\135\049\062\050\009\216\227\210\200\175\125\246\217\103\230\204\153\121\084\186\204\093\183\094\015\224\175\242\072\006\229\084\127\052\202\038\142\205\227\181\188\004\033\181\033\056\065\225\111\115\130\061\177\001\017\228\210\119\019\111\022\049\027\199\142\144\098\093\015\007\237\103\206\199\031\127\124\249\242\229\126\191\112\215\068\163\091\008\064\027\003\180\040\009\075\186\067\097\226\015\037\182\170\059\048\154\015\220\150\108\163\236\026\193\102\054\198\013\206\067\232\046\163\077\238\083\077\054\076\151\091\046\139\114\106\149\142\072\041\035\064\011\055\166\052\088\151\100\129\041\065\225\116\018\195\098\168\026\038\104\007\029\116\208\244\233\211\005\138\011\098\085\189\059\044\204\029\052\035\120\202\095\094\203\032\247\101\083\078\037\023\132\197\179\215\169\176\044\174\114\192\101\070\196\112\006\143\102\205\154\165\044\083\210\060\229\032\131\159\122\234\041\174\205\157\059\215\027\177\183\039\053\255\242\203\047\243\154\128\187\128\000\068\021\180\009\005\080\098\122\245\214\144\209\253\239\014\076\228\018\187\037\219\200\025\132\172\007\178\078\032\168\166\214\020\040\124\251\060\161\012\167\140\100\032\010\105\006\010\021\080\096\057\119\119\223\125\119\033\046\083\016\152\198\097\136\068\160\152\103\015\236\191\255\254\078\209\252\226\099\220\025\134\102\015\184\073\034\000\252\229\053\223\213\125\018\042\143\008\076\129\018\022\068\117\105\204\160\202\220\230\052\071\032\102\048\015\225\171\170\166\207\023\180\091\188\080\180\079\062\249\164\243\194\180\105\211\014\059\236\048\076\119\121\170\071\168\001\151\145\044\132\203\002\098\190\095\208\073\143\136\021\254\080\018\091\219\029\152\014\058\130\081\190\141\092\117\201\183\226\006\142\240\065\225\132\168\114\170\116\238\154\005\226\066\173\040\003\157\130\011\104\061\069\039\070\019\038\067\018\017\116\087\021\254\054\025\025\006\093\150\246\064\216\115\207\061\157\057\005\074\196\186\220\029\221\151\162\001\082\038\173\186\131\084\074\098\224\114\237\218\181\014\231\050\075\070\030\005\135\228\048\012\008\219\088\200\054\068\049\207\169\193\239\080\152\192\242\036\247\137\039\158\240\157\222\055\038\073\199\087\195\248\080\102\033\138\018\068\128\169\125\232\014\162\097\161\002\252\161\068\255\187\067\177\152\207\137\005\159\165\028\223\043\131\247\165\046\110\224\119\225\184\044\177\064\119\135\041\052\003\181\213\050\018\098\221\097\242\228\201\158\051\153\069\018\104\171\094\134\030\062\099\204\099\188\131\131\074\226\145\136\241\078\000\025\063\124\236\028\108\075\056\203\107\208\014\004\065\107\176\007\140\034\163\114\196\196\039\125\156\193\054\099\064\244\243\165\232\097\246\148\041\083\100\153\107\114\202\059\191\071\222\119\223\125\054\249\130\005\011\240\249\200\095\014\154\069\192\104\110\070\068\023\216\065\078\199\081\069\006\186\008\012\193\101\063\187\003\091\129\135\001\031\128\219\070\124\079\128\004\002\029\031\016\245\122\199\144\203\190\140\029\210\245\058\253\212\234\014\098\173\122\168\085\055\070\011\129\100\016\136\054\242\018\000\008\076\099\248\219\118\100\015\176\193\008\008\191\197\250\077\075\107\227\017\023\134\143\169\108\027\002\200\011\112\060\105\181\091\164\085\078\003\180\040\237\177\199\030\142\015\140\241\012\048\146\055\014\019\048\038\096\015\083\165\015\001\060\210\029\152\205\047\180\228\194\011\047\188\224\007\139\165\075\151\242\072\013\243\014\211\093\179\040\049\011\010\129\014\194\081\228\062\208\146\012\114\107\136\199\126\118\135\088\201\013\166\243\086\068\056\159\209\229\134\013\027\140\030\236\004\072\010\162\049\192\129\208\155\029\073\210\015\148\139\044\008\089\202\200\090\094\222\124\004\006\098\150\128\162\016\013\229\114\219\018\204\227\066\177\193\047\094\094\065\061\025\184\032\074\238\150\091\175\019\130\203\192\119\105\181\091\146\083\007\105\004\184\037\056\186\167\104\072\034\032\134\027\088\021\048\012\033\149\083\167\078\213\247\185\019\112\205\055\181\231\158\123\142\047\135\028\114\136\210\005\173\016\031\016\246\136\137\166\003\151\209\128\040\165\066\167\152\024\113\240\129\228\016\163\255\221\129\185\192\244\032\201\230\012\231\181\124\099\018\092\245\135\255\065\149\185\089\154\230\168\021\095\173\065\001\101\116\010\069\075\009\001\106\233\097\143\113\024\034\134\009\148\167\129\111\215\222\078\185\192\041\150\187\005\195\208\230\065\053\137\203\124\023\001\251\068\090\229\209\078\000\004\190\204\122\075\119\151\013\201\044\098\184\033\134\041\117\134\249\132\228\128\224\211\163\214\192\035\064\120\122\241\232\140\051\206\192\231\011\166\017\248\072\126\245\234\213\153\107\122\084\137\009\186\064\133\232\044\130\163\108\186\220\042\050\131\077\244\191\059\176\140\209\032\157\124\214\014\050\186\228\143\081\020\220\037\022\008\065\065\056\125\025\163\138\102\225\022\095\058\069\092\224\064\224\196\215\217\001\159\042\202\045\007\008\192\025\038\096\012\059\141\066\116\224\129\007\206\152\049\131\023\220\017\034\222\049\120\152\216\057\100\102\112\025\248\094\077\171\132\218\051\146\043\050\094\215\125\171\247\218\200\036\113\011\208\195\001\049\134\253\140\009\141\096\234\162\069\139\028\150\213\100\032\197\060\058\224\128\003\142\059\238\056\132\018\149\125\254\074\058\031\113\188\125\155\110\174\081\121\032\232\004\151\224\082\052\192\020\076\151\067\134\234\066\091\213\029\040\098\186\052\243\025\120\034\004\128\230\161\231\036\001\032\096\196\049\130\041\070\192\241\148\072\104\092\118\007\073\048\157\066\069\035\196\130\046\184\162\038\190\032\196\104\200\092\194\016\218\088\165\093\014\042\172\005\101\009\116\016\014\079\017\056\202\197\193\129\035\098\197\041\028\252\215\033\056\014\034\032\014\162\145\180\074\168\084\026\101\092\150\189\198\039\050\162\071\056\116\151\113\083\225\155\180\086\000\000\016\000\073\068\065\084\252\046\098\003\126\201\164\170\078\029\127\223\125\247\101\051\227\249\098\228\008\102\062\063\235\023\054\005\079\249\197\096\116\117\110\023\085\185\036\070\155\137\202\030\093\149\031\074\186\255\221\129\209\192\225\128\243\220\054\130\172\219\246\178\142\238\197\025\125\193\187\153\049\017\217\148\164\085\040\164\138\066\241\018\125\129\003\057\176\180\089\210\128\070\108\091\048\166\160\088\194\120\052\007\017\211\167\079\095\188\120\177\231\140\148\115\135\083\152\064\224\117\008\142\139\128\154\017\013\105\149\065\059\074\090\001\199\241\193\023\123\028\098\213\224\184\044\016\237\234\173\033\163\139\001\089\209\207\079\135\030\122\168\131\003\023\002\046\176\028\199\203\181\114\229\014\055\051\203\020\197\096\119\032\122\001\215\028\138\041\017\162\076\052\246\034\063\072\183\250\223\029\024\196\098\224\009\031\050\138\130\186\007\123\094\008\016\196\208\070\146\128\016\029\035\224\235\014\229\018\167\059\076\001\250\169\018\229\148\145\232\123\037\051\074\134\085\148\017\152\027\085\228\003\156\161\065\089\046\132\080\032\044\109\012\208\090\219\252\249\243\243\132\017\037\030\149\091\238\190\222\192\119\081\002\113\168\166\213\126\000\059\074\119\016\177\125\246\217\199\093\105\037\095\096\022\152\136\179\077\226\102\093\006\024\179\250\188\121\243\028\009\083\141\010\050\068\070\142\240\034\233\054\037\242\220\081\249\161\141\046\163\010\225\050\048\101\199\029\119\084\237\102\065\004\114\107\040\199\173\234\014\012\101\058\072\149\221\203\165\016\070\076\121\021\026\050\192\243\128\159\128\003\056\194\100\068\247\002\242\064\039\253\020\138\184\208\131\050\002\183\240\253\164\076\003\085\081\136\233\114\200\096\093\176\028\175\045\029\027\092\162\141\185\181\223\126\251\029\117\212\081\222\182\132\133\193\220\033\236\238\235\025\226\147\178\145\086\059\161\228\084\090\101\089\223\247\114\033\098\066\036\134\065\161\005\025\048\041\001\252\161\065\089\203\210\086\148\202\035\142\056\034\167\087\046\048\187\010\126\073\055\031\165\187\076\100\182\135\162\185\001\062\085\224\050\035\098\242\228\201\126\028\085\033\064\000\103\155\096\171\186\003\187\129\003\192\127\016\172\196\002\173\143\138\078\047\094\009\147\071\132\177\023\153\220\138\126\202\041\020\253\148\081\142\015\056\191\251\221\239\028\195\252\164\068\172\196\055\019\135\108\180\046\088\078\064\016\128\014\112\088\238\157\194\039\073\150\163\005\135\169\248\016\153\215\225\200\119\016\007\209\144\068\105\085\048\250\130\180\026\209\182\016\098\143\061\246\232\049\056\034\012\061\222\026\002\166\165\193\206\151\083\096\051\251\117\007\142\064\008\119\187\231\218\044\224\090\143\070\186\021\126\014\014\137\143\017\194\031\226\113\171\186\003\091\217\013\114\012\210\012\186\003\184\037\076\162\131\000\050\001\186\064\095\208\029\060\034\194\041\161\201\101\025\051\049\250\041\020\122\153\080\055\032\043\070\011\185\059\123\246\108\249\048\011\109\132\077\041\116\107\096\097\069\176\028\095\140\130\224\210\018\028\004\209\240\106\170\134\124\135\103\060\035\009\112\138\192\235\028\130\000\226\003\146\168\035\232\158\018\042\173\032\134\202\195\103\026\225\018\085\177\034\156\017\129\009\008\192\028\074\048\006\172\232\153\116\252\241\199\075\174\130\148\089\144\092\037\090\192\047\070\114\132\145\166\004\038\170\010\099\129\187\080\046\017\130\096\046\102\128\179\077\176\181\221\129\209\028\224\191\040\240\071\092\140\104\251\004\045\094\238\146\001\161\049\086\065\198\143\014\213\127\045\164\122\183\011\077\015\181\162\159\050\018\062\071\047\053\132\080\082\235\214\173\243\171\178\108\153\101\161\046\209\199\028\084\088\145\126\065\176\174\199\002\032\024\028\190\128\168\161\089\179\102\169\033\246\243\002\220\005\179\094\231\016\052\209\080\042\210\042\062\082\041\167\032\173\154\133\238\160\165\122\177\047\081\018\052\177\085\057\130\044\188\166\187\133\048\014\025\044\007\150\243\066\225\072\232\235\163\058\151\089\137\174\130\095\204\003\054\019\054\165\128\253\056\001\102\023\194\101\226\064\091\230\226\108\019\012\100\119\016\008\017\225\018\160\065\190\113\138\099\037\016\225\136\145\093\109\116\217\229\022\078\021\098\004\084\129\052\072\134\210\081\064\105\016\138\041\021\051\115\230\076\097\069\211\006\166\084\149\012\030\109\173\162\156\239\236\097\070\086\023\004\086\029\123\236\177\158\048\054\128\109\064\192\045\040\083\094\183\132\032\004\098\034\050\210\042\110\210\042\128\050\011\034\166\066\124\155\212\247\069\082\160\200\043\042\098\046\019\246\140\110\013\018\054\165\086\219\058\236\176\195\188\248\048\070\077\114\001\088\085\192\084\200\116\070\022\224\164\230\017\065\110\133\206\168\227\248\224\066\097\209\016\254\016\143\091\213\029\152\014\037\028\156\177\123\051\034\064\034\093\198\037\146\136\106\032\208\194\228\033\128\191\089\152\014\180\201\132\050\210\029\082\067\126\052\066\040\041\103\016\053\228\059\086\084\081\030\098\104\070\045\137\047\214\146\087\031\032\125\004\097\173\075\017\088\184\112\033\171\024\169\214\217\047\092\248\204\051\005\204\170\002\039\032\016\016\030\254\136\169\177\220\088\245\008\141\003\145\049\118\113\071\064\148\138\238\032\062\194\037\149\250\002\136\024\218\116\242\126\235\145\116\115\233\177\045\247\220\115\079\119\093\186\107\076\168\137\013\001\044\151\085\230\206\157\123\200\033\135\048\131\097\106\082\102\153\193\023\064\004\145\052\133\217\101\068\048\059\183\136\133\048\086\105\085\164\233\080\005\248\064\096\232\177\085\221\129\185\236\014\184\033\199\098\100\012\132\064\178\113\136\117\129\041\225\104\013\118\181\216\229\178\151\209\020\160\153\066\201\160\089\248\228\070\119\000\197\132\079\149\050\242\166\074\178\170\202\101\021\076\117\089\021\232\145\038\211\029\085\201\220\045\028\151\206\153\111\123\219\219\014\063\252\112\246\112\223\173\163\143\062\250\212\083\079\205\071\038\027\128\253\196\212\007\151\009\196\125\102\059\066\023\184\196\007\002\001\097\083\128\194\225\003\246\000\219\098\100\070\102\115\132\011\198\000\013\185\075\216\148\032\142\136\070\032\125\226\099\167\073\171\166\032\128\001\142\185\206\240\187\237\182\155\041\052\120\048\028\116\208\065\111\125\235\091\061\186\165\018\147\066\099\244\132\192\207\165\017\167\011\048\161\011\179\122\233\046\084\057\161\195\052\050\230\141\111\124\163\079\093\076\101\182\180\090\017\220\034\153\145\085\001\155\011\248\002\002\066\172\010\083\032\028\218\252\006\167\065\020\133\225\015\253\184\181\221\129\197\188\226\006\032\056\038\205\070\016\005\219\024\200\008\147\145\064\198\016\104\005\228\232\072\050\002\056\189\192\044\160\153\078\069\163\074\116\007\053\164\059\128\170\082\154\186\198\156\057\115\236\070\122\162\211\148\042\098\167\187\253\067\085\021\013\089\130\078\231\064\175\199\167\159\126\250\113\199\029\167\098\214\172\089\067\146\085\222\041\166\079\159\206\084\054\179\028\211\020\181\162\062\056\238\179\011\201\085\171\086\253\254\247\191\127\229\181\063\244\234\213\171\241\221\037\006\252\018\162\192\092\026\002\006\012\037\178\168\145\013\049\198\200\054\144\071\214\194\234\206\191\085\175\253\241\005\137\023\119\072\154\011\148\064\049\094\000\005\199\054\203\241\033\105\021\082\001\004\021\101\138\243\151\228\154\066\021\166\079\057\167\157\118\154\007\120\118\017\062\008\047\085\070\200\101\008\244\022\193\172\160\199\089\030\063\090\131\050\099\006\131\075\102\171\194\241\206\200\114\035\136\085\104\065\016\168\008\227\035\172\021\179\209\160\126\028\142\140\098\226\022\096\110\019\012\076\119\224\000\247\056\019\072\039\130\063\133\064\071\198\136\078\080\004\075\233\131\192\021\038\098\083\048\023\104\166\086\086\108\057\017\212\029\148\017\072\149\170\082\166\146\231\109\176\040\097\024\152\008\033\220\138\001\136\094\064\166\059\040\097\000\080\229\110\166\091\218\143\222\007\031\124\176\157\240\232\163\143\222\122\235\173\191\254\245\175\089\168\053\168\105\070\042\235\212\016\121\206\114\153\157\074\132\188\253\243\242\203\047\063\247\220\115\079\117\254\061\251\236\179\232\023\095\124\209\207\180\238\130\205\064\018\076\049\081\109\001\037\162\007\108\000\106\007\009\148\131\133\002\235\090\029\088\194\030\086\129\205\015\076\229\136\022\103\124\169\243\143\023\207\087\254\240\077\049\151\042\058\139\193\066\026\072\171\040\165\239\075\043\008\044\232\251\027\054\108\240\218\056\127\254\124\097\023\167\135\031\126\088\132\095\120\225\005\223\116\052\101\149\064\091\116\082\066\006\029\224\083\110\172\162\220\170\050\171\052\001\151\244\072\052\032\168\165\039\124\111\142\039\158\120\034\123\152\202\224\008\144\033\096\022\068\204\008\156\077\208\140\016\061\194\069\172\032\019\009\135\163\223\241\189\104\014\115\155\140\091\219\029\056\022\136\142\048\005\066\128\080\010\118\072\050\023\223\138\255\033\140\138\073\248\000\029\153\222\199\172\069\191\216\201\141\186\017\071\005\164\059\000\194\186\234\117\198\140\025\182\101\084\209\108\086\104\163\075\203\033\182\006\210\012\052\072\164\183\137\019\078\056\001\161\088\065\119\184\231\158\123\216\224\165\212\081\194\017\145\145\172\101\152\016\089\221\246\016\025\123\062\219\073\023\120\252\241\199\175\184\226\138\011\046\184\224\187\223\253\238\247\190\247\189\031\252\224\007\151\093\118\217\149\087\094\249\243\159\255\252\161\135\030\122\240\193\007\237\132\103\158\121\198\238\082\085\038\058\116\208\096\127\082\197\012\224\017\080\014\172\218\122\208\003\116\002\253\096\057\139\090\154\107\108\096\009\251\211\218\024\198\011\224\254\019\079\060\177\114\229\074\187\119\249\242\229\215\095\127\253\165\151\094\250\195\031\254\240\146\075\046\225\026\092\117\213\085\143\060\242\136\185\212\210\015\197\084\193\017\034\199\007\105\085\051\130\038\179\114\010\210\170\239\171\165\253\247\223\223\067\149\025\043\086\172\016\103\157\231\233\167\159\038\224\245\109\193\130\005\100\168\101\167\145\230\106\210\203\042\091\074\080\018\080\008\166\171\043\199\022\231\065\077\159\169\012\086\141\140\119\171\010\194\049\003\033\122\032\089\160\018\208\066\087\021\174\210\084\237\188\243\206\092\022\013\116\086\175\010\012\037\189\181\221\033\182\022\055\016\009\022\223\196\066\070\005\049\050\194\004\161\203\168\059\072\182\120\185\021\148\091\061\018\009\086\086\017\104\207\100\250\133\210\230\244\054\097\068\147\145\024\031\186\011\077\115\209\134\134\114\217\157\048\029\054\197\055\151\114\163\178\080\142\138\210\179\075\029\099\090\157\097\119\222\121\167\221\194\024\143\023\191\098\186\037\008\076\021\016\058\137\009\139\061\102\135\016\243\116\117\082\248\213\175\126\117\222\121\231\125\225\011\095\248\207\255\252\207\207\127\254\243\159\251\220\231\062\251\217\207\126\230\051\159\249\220\231\062\119\254\249\231\255\232\071\063\186\233\166\155\238\186\235\174\199\030\123\204\099\211\150\048\203\179\217\206\180\075\237\085\251\001\196\016\232\015\088\008\086\236\011\072\006\153\075\015\176\019\104\102\045\088\139\205\202\090\202\088\174\023\000\099\216\175\115\217\165\240\219\223\254\246\254\251\239\215\212\174\185\230\154\111\127\251\219\095\253\234\087\255\253\223\255\253\035\031\249\200\063\255\243\063\127\252\227\031\071\127\232\067\031\210\248\052\017\073\183\086\177\077\192\065\244\020\143\088\037\173\066\039\131\054\191\192\026\221\194\023\109\189\195\138\002\162\131\136\179\008\184\037\212\206\110\138\129\158\104\070\064\252\202\066\046\033\116\095\198\204\205\040\032\230\178\071\199\247\153\153\061\140\097\170\165\241\131\046\058\077\100\137\137\025\005\019\077\070\024\001\017\152\075\018\114\169\078\248\069\057\034\156\109\056\014\064\119\224\094\032\187\129\144\133\176\133\032\238\241\031\072\230\050\163\212\202\180\154\019\193\112\054\059\210\064\185\216\209\108\227\009\165\093\042\109\106\072\173\024\093\082\162\175\123\170\043\023\180\172\152\005\136\190\047\100\098\021\140\119\105\140\006\207\177\063\249\147\063\057\224\128\003\048\153\161\092\118\223\125\119\187\069\213\018\120\251\219\223\190\116\233\082\150\072\179\187\009\136\185\012\176\223\236\052\123\219\238\178\181\108\120\219\254\055\191\249\013\142\109\227\205\226\201\039\159\116\088\112\106\184\229\150\091\060\117\191\245\173\111\125\233\075\095\250\244\167\063\173\095\056\095\120\020\123\002\219\129\158\159\066\103\150\232\081\040\146\246\176\093\071\191\085\010\024\003\150\238\014\124\032\153\017\161\130\077\167\132\042\160\086\029\131\142\000\090\018\232\077\236\100\121\236\212\013\053\175\159\252\228\039\151\095\126\249\055\191\249\205\115\207\061\151\193\023\095\124\049\035\239\190\251\110\238\104\037\230\114\214\177\130\205\156\226\047\155\197\141\073\198\002\009\146\086\177\018\049\045\064\244\164\085\096\229\020\016\118\163\128\251\232\203\206\007\030\120\128\097\142\102\158\180\042\001\045\254\014\113\121\169\164\153\083\070\058\139\254\190\019\038\018\054\023\208\084\185\084\105\039\159\124\178\180\250\036\137\086\096\076\101\176\106\116\183\071\152\040\170\192\224\140\180\073\153\216\070\158\126\040\052\130\054\110\210\140\000\156\109\136\001\232\014\177\158\039\144\096\133\064\023\207\035\211\125\084\139\106\069\193\117\191\181\041\014\157\096\009\017\084\070\182\159\022\160\140\020\144\238\224\231\046\132\194\114\215\007\008\207\118\143\032\041\145\027\163\137\176\041\205\189\240\051\139\006\050\170\208\071\169\083\078\057\069\033\102\105\075\076\155\054\141\049\183\223\126\187\220\251\006\225\172\171\106\221\085\067\106\055\161\048\157\025\042\195\174\203\134\177\199\060\114\053\008\028\149\036\026\065\246\167\173\104\007\058\089\232\056\078\233\090\131\211\132\078\225\177\236\005\068\155\248\233\079\127\122\199\029\119\120\245\112\092\039\105\007\218\036\084\129\102\065\073\016\157\010\180\010\076\151\070\096\018\152\002\052\216\186\192\066\096\003\181\018\196\084\219\251\225\135\031\102\143\157\201\211\155\111\190\089\083\240\006\116\233\165\151\178\205\193\135\097\055\222\120\035\107\217\163\115\081\101\009\094\003\199\025\099\021\141\143\169\110\097\010\102\129\008\007\018\103\123\136\091\026\132\166\016\072\043\142\072\202\169\095\166\088\200\119\017\150\005\073\183\093\057\034\005\238\250\045\195\071\001\154\045\033\170\136\045\005\075\076\201\024\013\202\204\087\036\223\065\045\167\186\152\199\072\153\085\135\196\128\124\021\089\154\215\166\011\002\130\121\070\080\033\066\081\021\014\109\010\130\128\044\152\018\157\070\192\223\038\024\152\238\192\001\072\164\228\015\066\011\013\196\049\002\144\016\032\000\223\165\199\139\090\033\134\198\233\035\076\183\138\244\040\008\069\035\097\106\072\119\000\181\098\148\078\197\237\053\213\207\078\116\082\110\137\088\229\114\139\096\045\200\148\093\119\221\053\155\095\235\081\034\186\146\214\096\117\213\233\099\164\103\163\239\100\239\120\199\059\212\144\194\101\131\026\082\238\089\151\013\178\014\054\009\151\061\084\109\060\176\153\249\018\253\036\011\202\162\185\101\186\189\234\232\238\220\238\077\196\089\253\031\254\225\031\254\241\031\255\241\236\179\207\118\092\191\247\222\123\109\060\123\152\066\098\074\208\254\001\011\209\223\035\220\130\200\144\023\046\038\129\233\148\056\032\060\255\252\243\020\074\144\173\238\173\065\027\210\020\116\037\047\065\255\241\031\255\241\209\143\126\212\248\157\239\124\231\218\107\175\117\210\209\065\184\022\083\051\114\010\184\195\017\008\083\208\208\114\001\060\010\051\035\062\144\023\177\146\086\225\149\089\173\193\136\054\093\219\181\075\101\089\147\226\178\070\128\099\148\116\006\208\233\171\147\164\019\174\170\069\187\005\008\171\000\098\083\112\023\220\101\164\145\049\190\034\057\152\248\232\032\215\210\138\195\072\166\070\140\076\021\086\041\176\219\161\180\006\022\202\126\212\154\018\177\040\065\227\016\022\124\185\064\135\143\216\086\024\176\238\032\082\144\106\048\022\020\199\056\095\080\152\194\164\254\196\066\080\114\183\220\234\133\016\053\200\114\026\132\138\177\021\085\131\002\082\052\106\197\168\086\164\080\027\118\248\244\048\145\075\250\173\066\173\185\198\190\195\068\118\146\095\178\100\201\159\254\233\159\030\124\240\193\074\196\114\096\093\125\193\114\054\149\199\059\075\020\046\001\171\167\134\152\039\020\089\145\030\080\031\106\133\097\118\166\089\246\045\229\064\127\001\177\032\028\158\066\232\050\154\098\003\059\189\107\022\062\079\228\131\197\215\191\254\117\187\215\055\206\219\110\187\205\142\181\121\188\179\056\155\216\240\214\170\066\204\093\226\131\114\004\218\116\001\194\158\237\030\254\218\205\178\101\203\232\113\066\185\240\194\011\191\209\249\231\203\226\143\127\252\099\061\194\167\071\026\216\080\236\169\018\252\005\046\016\048\230\022\014\066\082\068\047\233\112\217\005\100\120\042\098\226\070\082\223\023\097\113\214\133\065\126\205\021\112\045\216\167\065\154\111\184\225\006\242\142\250\044\167\107\162\000\000\016\000\073\068\065\084\186\131\126\109\020\118\177\037\035\089\222\254\232\039\006\136\045\133\076\177\159\025\158\007\103\158\121\166\151\026\006\176\199\018\204\227\130\165\025\012\221\053\091\209\092\080\114\001\109\152\082\175\059\032\186\079\009\199\045\185\144\148\200\135\185\173\198\001\232\014\162\083\032\094\162\038\187\128\201\043\113\052\110\010\194\167\022\237\019\017\068\111\074\172\059\159\114\200\114\158\207\182\165\180\073\158\135\140\189\170\065\040\020\091\148\025\162\236\032\234\101\213\165\208\103\021\115\131\170\230\042\007\093\110\089\197\067\195\219\132\215\078\191\102\161\173\162\076\213\046\040\068\198\219\069\070\189\227\164\147\078\178\052\099\152\196\119\209\160\010\104\179\058\048\128\073\170\068\017\131\090\097\164\037\008\000\129\000\029\152\011\004\000\001\225\103\180\168\199\190\070\224\144\239\133\255\019\159\248\196\063\253\211\063\105\022\026\004\104\028\096\123\255\236\103\063\179\225\237\124\167\027\095\010\092\218\225\062\094\160\189\041\072\129\159\000\180\003\094\044\091\182\204\167\001\187\238\186\235\174\243\065\084\187\241\053\209\097\225\162\139\046\210\254\238\187\239\062\239\023\233\104\049\128\061\192\133\128\145\144\091\113\196\072\000\194\148\035\137\016\156\092\118\025\137\001\013\226\102\091\218\135\034\089\186\003\002\048\197\092\156\165\195\207\061\222\047\104\211\026\192\201\206\168\143\224\168\138\131\014\058\200\198\198\164\179\203\066\189\095\178\089\096\201\080\117\204\049\199\188\249\205\111\158\051\103\142\162\146\116\171\211\044\179\140\164\022\136\117\129\233\032\209\148\100\148\113\192\196\017\189\034\095\157\142\006\183\158\127\254\121\157\090\097\144\119\185\013\177\181\221\033\254\024\033\245\097\020\059\217\069\136\136\060\021\247\200\136\041\032\194\228\191\179\131\215\048\068\016\126\095\070\074\128\054\203\089\197\070\085\073\041\062\251\083\046\141\010\081\145\201\135\045\045\193\076\162\217\066\038\086\065\073\046\011\145\075\194\048\109\218\052\039\130\179\206\058\139\018\106\045\097\033\203\041\148\172\235\215\059\155\077\025\189\229\045\111\033\172\118\221\178\046\195\232\137\078\122\208\070\096\128\162\001\061\130\109\056\244\024\193\045\032\009\153\136\040\124\183\000\167\094\175\099\118\135\226\243\228\241\142\227\213\227\147\159\252\164\223\011\062\246\177\143\057\086\216\222\070\159\006\124\056\212\068\190\242\149\175\224\248\077\193\247\011\112\044\032\031\120\079\209\095\062\245\169\079\125\237\107\095\243\077\065\251\160\176\251\066\056\204\136\133\070\151\001\038\160\217\105\068\131\176\027\195\209\187\069\079\121\184\219\035\072\002\157\100\196\080\036\197\211\182\212\023\140\230\002\166\044\188\237\109\111\147\083\077\208\091\143\092\235\002\129\006\033\077\230\138\134\110\238\165\128\112\247\181\172\018\184\021\194\136\134\152\170\011\104\046\082\239\061\133\066\171\075\058\181\210\202\188\034\076\190\059\104\000\041\102\131\044\219\008\064\204\044\143\004\004\160\003\146\185\164\022\225\097\105\138\185\238\186\220\134\216\218\238\192\116\062\000\199\020\129\140\138\029\136\172\075\078\058\245\217\048\232\072\026\065\056\000\033\004\014\168\014\180\026\004\026\019\240\251\136\234\186\054\088\202\200\131\093\083\080\046\160\080\208\138\073\196\149\215\155\222\244\038\135\082\202\173\005\008\102\007\084\185\012\220\002\150\168\182\183\190\245\173\239\121\207\123\252\144\070\143\018\161\060\085\098\185\020\138\054\239\251\188\031\192\223\255\254\247\027\021\016\228\022\175\041\143\206\140\086\001\076\064\128\090\241\148\240\157\130\066\050\056\129\213\115\073\018\225\018\016\185\139\232\017\100\082\142\212\114\217\055\005\205\215\201\194\113\192\183\009\239\005\070\071\000\237\067\059\051\162\113\252\196\224\152\224\167\135\123\238\185\199\078\051\203\092\026\036\069\077\039\020\061\046\135\105\069\035\032\002\116\140\044\035\062\037\248\210\225\121\110\123\115\042\119\049\187\195\045\002\169\037\145\020\079\083\064\228\141\046\037\020\095\180\255\230\111\254\198\232\188\163\210\164\091\190\166\118\254\033\092\146\228\139\170\176\201\029\030\041\204\090\236\201\018\070\040\105\194\143\128\209\091\201\007\062\240\001\191\061\249\173\084\222\029\034\232\177\168\218\142\188\137\064\178\011\040\001\254\130\092\008\160\145\121\070\115\141\002\155\041\153\078\184\016\166\184\165\018\244\080\035\122\219\098\000\186\003\007\184\151\144\073\128\016\104\013\137\163\160\200\144\131\061\038\049\016\011\064\020\216\027\222\141\243\162\085\152\125\036\172\011\165\146\004\084\245\232\002\246\176\248\170\197\064\161\224\211\169\170\084\167\122\034\099\150\100\020\099\232\033\128\003\008\146\196\188\220\030\117\212\081\190\035\232\113\020\082\171\064\121\100\033\062\130\083\189\019\056\225\119\189\235\093\220\180\010\058\190\039\032\212\002\133\096\069\052\126\137\146\176\184\180\009\173\197\084\050\064\198\024\100\010\078\177\051\252\050\186\085\100\066\148\091\133\160\223\110\215\133\125\056\244\018\225\213\064\071\019\112\163\200\107\007\008\223\032\108\164\082\184\101\110\239\068\172\050\042\122\113\131\034\207\176\128\085\248\100\132\203\241\202\211\158\215\152\238\022\225\046\132\091\129\064\153\037\158\162\106\115\130\008\027\093\074\001\190\094\255\023\127\241\023\034\207\029\169\145\104\125\161\179\063\076\069\008\041\097\202\173\232\251\180\207\079\152\116\226\048\201\018\008\064\048\015\208\210\033\209\062\049\120\115\089\180\104\145\174\237\210\209\131\030\139\050\198\244\024\111\022\249\077\129\054\049\001\221\193\046\200\072\185\056\075\071\151\089\081\197\036\179\172\117\198\025\103\056\165\090\043\252\046\194\067\121\057\000\221\129\015\226\005\114\000\188\146\057\144\060\016\032\014\227\243\138\255\198\128\060\066\056\004\078\117\042\092\109\194\037\224\247\029\086\007\218\164\205\042\214\085\064\058\125\030\245\234\067\065\128\186\241\004\096\012\201\249\243\231\031\120\224\129\138\201\042\076\010\208\144\213\233\241\232\240\182\185\120\241\098\245\145\185\105\013\170\196\018\124\036\099\069\223\243\089\238\136\235\209\228\150\002\202\093\183\044\196\048\160\022\016\056\248\038\154\078\140\176\070\099\196\119\201\084\098\012\096\015\002\019\204\194\049\162\049\193\101\004\208\224\086\128\198\119\023\049\128\040\202\187\235\204\090\004\066\068\128\157\229\146\061\152\004\066\040\003\095\010\253\030\044\002\196\192\045\002\061\194\173\008\016\086\069\226\035\086\050\027\008\181\075\076\056\244\208\067\181\102\111\016\244\203\145\044\139\164\140\167\071\160\165\143\152\061\185\215\094\123\029\121\228\145\004\178\098\172\066\035\000\001\122\129\022\230\087\039\069\098\162\042\162\214\114\210\196\018\233\099\088\064\184\071\112\159\054\149\006\106\091\107\176\052\160\141\074\157\128\137\148\024\003\242\016\122\238\220\185\222\097\045\029\247\195\220\086\227\000\116\135\152\206\025\173\081\004\147\075\249\016\080\163\199\145\224\074\091\196\018\154\208\009\016\142\223\252\029\128\197\177\196\040\002\125\028\233\009\172\110\227\089\087\013\165\065\136\178\250\080\043\129\220\019\000\063\122\041\002\079\030\052\003\172\043\151\070\043\122\015\082\028\190\047\170\015\045\220\169\129\018\037\162\155\112\132\071\028\044\152\049\099\070\090\003\153\212\171\091\106\072\052\128\085\020\002\034\016\034\119\201\208\067\158\157\128\086\058\142\015\158\111\132\129\073\070\064\176\202\210\158\102\142\199\204\198\004\124\010\179\004\026\199\101\129\203\033\128\229\044\205\060\163\152\179\208\246\227\157\203\032\002\092\099\140\000\122\129\183\135\121\077\070\028\048\055\011\014\130\180\138\152\037\204\149\130\000\013\066\039\056\082\038\077\034\041\233\042\205\254\151\238\116\007\035\026\199\045\005\070\143\048\046\092\184\208\092\150\023\176\132\146\019\079\060\241\125\239\123\159\095\046\125\104\224\139\156\050\155\090\194\234\132\025\140\001\126\145\223\020\248\078\173\114\226\184\021\003\125\033\151\206\110\136\204\037\137\160\045\004\218\138\071\031\125\244\190\251\238\203\047\033\218\236\090\166\012\042\006\166\059\240\144\051\178\046\136\018\192\055\001\005\132\072\113\050\079\140\077\121\162\053\036\106\132\161\004\107\083\242\221\249\012\176\138\081\010\065\037\073\170\130\072\173\104\016\170\036\080\043\202\075\134\220\085\004\158\249\182\028\049\151\030\020\202\215\151\112\141\067\095\176\093\077\196\116\139\182\184\195\187\226\035\061\126\046\117\254\052\018\224\172\187\130\032\020\140\233\098\036\219\048\221\098\030\049\218\076\241\130\003\234\027\211\244\005\011\022\008\020\049\017\008\068\003\232\084\253\234\230\184\227\142\099\021\201\040\167\019\017\073\132\075\064\012\037\088\043\176\014\005\094\193\216\198\024\171\027\001\193\120\004\031\089\110\215\009\190\232\113\071\028\054\107\042\001\160\159\176\248\008\026\199\019\055\145\007\089\006\124\076\025\196\065\008\166\045\045\107\118\154\229\216\022\072\037\062\099\040\241\157\210\091\134\180\050\140\216\062\251\236\227\187\146\164\031\123\236\177\094\060\157\022\101\193\131\132\128\028\089\130\205\012\096\009\048\137\095\155\002\253\192\107\080\099\090\131\190\224\001\137\096\167\047\208\014\155\110\117\159\078\045\023\124\023\083\144\022\181\226\102\215\234\174\100\192\057\003\208\029\056\006\156\145\117\065\020\005\009\144\039\016\089\180\120\201\150\180\085\173\023\035\252\112\188\140\121\025\022\068\029\055\156\126\140\177\193\200\006\193\181\180\040\075\176\165\085\064\181\080\148\139\075\134\169\000\007\004\041\081\187\246\222\169\167\158\234\032\224\217\226\174\041\030\056\018\070\003\061\124\225\023\181\128\000\250\149\035\167\084\024\026\048\069\000\132\130\025\208\197\011\156\082\232\020\082\107\174\146\005\171\040\038\151\094\203\141\038\138\015\032\192\203\139\175\003\150\246\124\083\199\154\017\166\232\085\195\229\146\060\032\220\029\108\240\037\011\241\226\244\211\079\255\111\255\237\191\105\172\028\183\025\194\039\192\024\102\008\136\222\225\053\222\038\228\166\236\224\144\036\000\004\122\001\129\192\020\019\165\012\132\078\228\141\098\238\018\068\038\144\002\124\038\089\072\222\229\087\083\144\077\025\015\208\194\107\162\070\044\233\094\052\252\080\237\211\163\195\188\046\239\188\032\233\166\152\075\003\061\036\233\180\052\131\129\049\189\088\091\110\113\092\054\065\083\240\190\012\008\115\125\125\087\228\196\208\162\148\145\048\142\194\240\172\242\100\242\024\224\011\127\113\008\128\187\219\010\003\208\029\152\206\007\016\062\094\241\077\194\064\158\064\124\021\177\088\075\012\201\030\161\161\250\236\236\183\107\001\021\044\129\235\081\108\179\204\216\080\053\067\025\169\006\155\060\133\162\068\060\022\002\105\000\002\110\169\108\207\019\175\124\050\228\120\175\053\096\218\180\230\018\224\011\167\148\008\032\000\007\120\231\046\160\083\067\220\103\067\208\221\090\252\098\155\176\232\044\194\194\054\181\104\057\181\168\140\044\173\100\157\092\072\138\131\104\208\163\182\116\135\007\031\124\080\160\116\082\022\250\144\078\131\091\098\107\164\025\016\003\014\054\064\119\181\152\086\244\189\246\204\051\207\180\243\237\168\252\155\139\248\017\014\161\035\252\217\159\253\153\083\003\131\121\202\102\209\219\162\186\183\138\080\024\197\022\196\025\004\060\064\083\136\015\037\059\086\145\020\225\181\162\192\178\077\237\201\117\128\118\075\180\217\230\109\136\097\154\130\128\235\185\002\043\254\102\201\011\013\244\068\057\003\128\013\113\173\151\145\215\082\038\041\042\089\214\036\052\064\251\232\235\013\218\093\211\169\002\068\129\213\069\073\247\183\110\156\074\148\138\192\054\033\006\166\059\048\157\183\252\073\134\100\206\206\001\174\010\177\187\226\037\043\004\208\034\104\012\204\066\008\220\109\183\221\182\124\249\114\165\079\146\000\224\111\017\034\076\033\200\165\181\164\150\037\108\176\201\165\060\133\082\026\132\076\056\067\026\025\230\003\132\035\165\047\145\234\195\211\195\118\085\031\010\136\241\073\149\226\043\160\022\147\230\000\013\185\107\093\096\064\140\169\142\152\224\046\073\242\052\211\111\149\024\198\054\235\226\008\133\213\029\016\212\174\000\018\054\139\030\145\185\246\218\107\031\123\236\049\171\043\053\175\166\062\172\234\095\020\186\219\035\050\177\199\091\091\201\180\040\251\189\145\137\152\056\123\049\148\190\203\047\191\252\209\071\031\165\217\186\140\100\155\168\190\229\045\111\241\050\239\128\102\139\114\007\159\071\166\144\001\194\125\001\073\043\026\205\077\129\009\096\016\133\152\110\081\075\012\129\041\053\201\059\051\196\211\158\103\064\186\131\140\203\059\142\024\234\014\226\140\163\042\148\001\073\233\080\045\230\210\064\015\109\116\090\026\054\107\170\162\005\251\095\013\203\081\250\130\195\002\224\251\205\200\015\043\148\160\141\093\020\178\196\177\081\001\100\221\248\066\006\008\111\043\012\076\119\224\003\112\009\196\084\230\056\169\026\002\201\019\160\228\073\184\185\074\088\208\001\029\248\105\208\231\092\047\102\034\155\240\133\223\143\145\114\160\060\198\196\018\143\011\006\216\132\202\066\041\056\062\168\009\085\002\008\151\152\010\136\064\169\015\027\128\047\012\166\042\160\208\037\240\136\090\224\041\025\151\152\145\177\116\047\054\187\027\037\038\210\031\171\020\037\171\128\001\070\211\105\214\032\242\139\073\137\134\039\207\138\021\043\152\007\074\208\211\134\140\008\019\112\009\148\131\233\016\099\140\056\070\064\224\247\008\183\010\072\130\203\072\162\131\194\193\103\158\115\150\126\170\226\087\174\092\121\227\141\055\094\117\213\085\190\028\185\005\236\241\064\246\059\194\095\255\245\095\123\139\022\088\014\150\186\023\040\170\128\100\223\065\062\102\036\122\002\046\236\128\000\076\002\016\025\035\166\187\034\108\159\107\193\012\016\088\251\095\131\144\107\073\007\004\224\224\187\043\170\042\132\157\066\042\059\166\083\075\021\181\208\071\083\249\174\128\029\028\192\075\150\178\015\076\087\219\250\005\130\012\032\168\013\129\102\131\199\003\131\045\205\248\254\069\137\158\129\197\192\116\007\054\113\213\040\160\028\019\089\005\196\085\129\150\030\180\091\046\061\109\056\143\238\014\197\253\208\067\015\121\049\067\008\025\116\151\233\059\135\049\032\181\032\214\236\177\058\075\060\022\020\129\052\216\135\242\161\112\001\225\018\083\013\169\036\059\150\217\108\054\139\047\052\020\208\201\193\040\052\022\096\146\113\183\119\011\009\004\212\154\203\036\181\104\069\235\090\061\102\024\089\232\022\056\238\158\114\202\041\126\088\245\214\163\133\177\071\136\238\186\235\046\214\114\068\169\169\105\047\207\182\034\133\150\078\208\178\068\185\068\004\248\033\054\053\018\128\220\069\000\154\078\004\032\092\130\079\143\199\031\127\188\214\192\114\033\101\185\158\117\251\237\183\203\172\091\062\049\188\251\221\239\246\050\079\128\253\246\030\035\019\082\002\188\078\160\040\164\106\139\096\010\152\014\002\094\224\178\128\000\228\082\076\068\076\024\025\041\092\162\170\245\011\157\008\075\058\195\140\104\246\139\191\187\113\135\188\089\177\147\030\218\160\143\118\010\017\040\224\180\006\009\074\107\208\038\180\012\111\133\014\134\085\085\132\203\165\074\080\117\009\017\203\045\154\213\139\192\054\033\006\172\059\176\158\063\114\198\055\241\181\187\004\154\195\070\112\041\064\114\131\032\089\226\034\010\128\003\119\223\125\183\007\145\035\153\248\018\000\204\126\131\090\096\018\020\147\020\138\052\168\003\213\160\086\130\212\135\231\006\190\187\044\076\146\076\004\074\128\025\070\151\001\055\129\090\099\056\070\002\064\178\023\016\136\164\250\019\037\145\177\115\044\205\018\187\072\189\006\170\086\201\186\203\024\173\193\231\116\031\077\125\046\245\196\115\058\053\209\171\178\137\171\087\175\022\097\175\024\248\044\161\220\210\070\016\189\132\017\141\185\089\016\011\138\100\046\233\129\048\249\107\083\217\255\086\020\040\091\142\025\012\038\201\126\191\002\248\217\194\055\008\163\067\178\163\013\166\056\019\019\246\132\148\145\113\063\010\183\116\180\080\001\061\005\133\089\037\220\181\156\088\137\161\040\049\088\126\217\195\170\002\065\198\193\119\055\209\038\207\077\115\033\218\250\104\164\040\129\034\215\026\212\176\142\144\238\224\200\128\137\118\182\210\044\104\043\106\037\200\101\096\138\021\085\005\048\027\029\254\182\029\007\172\059\196\231\134\134\006\190\241\080\053\008\183\172\004\050\036\118\070\161\231\048\186\132\198\068\028\208\026\030\121\228\017\017\020\077\002\056\091\015\202\065\172\089\037\241\192\042\197\106\107\169\090\080\025\070\151\234\131\121\192\114\194\166\128\185\192\012\099\001\062\084\101\092\230\046\201\190\128\060\036\074\226\195\000\053\170\073\233\158\054\155\227\046\216\135\233\017\076\194\247\253\239\180\211\078\251\203\191\252\203\247\190\247\189\062\142\104\040\186\137\042\087\139\194\229\171\170\023\087\177\021\055\129\053\022\051\024\102\045\151\085\166\203\130\008\024\009\152\027\062\026\129\105\196\180\004\194\254\247\137\209\215\004\171\179\013\216\108\244\101\225\125\171\254\062\084\000\000\016\000\073\068\065\084\239\123\159\081\083\096\057\038\047\216\108\239\009\175\104\139\185\200\051\143\194\128\182\126\035\026\186\143\085\133\185\203\113\016\103\171\179\129\037\018\045\218\172\010\092\202\187\020\008\178\188\179\048\105\205\244\170\194\190\208\130\038\080\050\098\171\107\007\042\089\107\000\115\093\250\225\009\001\148\027\001\001\008\120\254\249\231\035\201\096\204\000\127\219\098\192\186\067\220\224\149\248\138\178\124\008\119\082\098\148\000\183\228\064\097\021\073\132\128\026\003\159\030\238\191\255\126\111\215\130\139\015\225\111\229\104\093\017\015\138\097\044\097\146\114\049\002\011\113\024\076\128\036\023\204\130\046\075\227\244\136\046\098\189\095\070\067\086\081\184\022\101\128\050\021\025\251\202\166\178\181\180\006\219\204\136\198\177\003\115\233\089\237\067\160\166\064\088\119\000\085\078\009\184\181\112\225\066\026\172\158\208\089\194\090\046\131\048\067\119\031\221\133\046\252\194\177\010\229\199\030\123\172\111\120\014\005\012\099\018\219\044\007\186\021\166\215\010\119\141\012\102\152\126\103\031\138\176\216\050\079\096\025\211\197\164\046\203\013\236\165\229\192\138\032\161\041\072\089\022\237\002\182\225\072\001\243\200\128\041\193\150\026\035\086\160\147\170\094\189\032\173\193\225\014\129\227\039\039\052\157\148\027\073\002\162\128\073\044\017\040\214\070\166\220\218\134\196\064\118\007\094\129\016\139\053\063\121\043\250\220\078\137\224\243\092\149\187\197\097\052\097\049\002\004\014\060\252\240\195\222\047\188\158\233\193\248\128\057\032\176\004\088\148\025\016\011\089\162\104\140\128\025\144\033\009\003\178\110\143\074\040\007\011\089\145\001\002\037\068\246\146\061\111\179\217\090\217\123\054\161\029\008\046\049\237\058\119\067\135\192\001\180\032\083\232\253\194\017\131\054\139\038\116\150\192\087\178\185\196\239\014\183\034\064\050\242\069\198\045\180\206\165\053\188\169\243\191\192\022\099\216\128\000\004\035\051\134\096\039\123\180\006\179\056\197\024\177\021\109\154\193\018\020\014\037\172\008\226\108\117\035\099\064\204\001\001\177\205\045\098\065\063\204\019\040\080\180\026\001\164\059\104\007\090\131\163\132\115\129\199\094\212\090\130\100\021\012\144\122\071\063\071\045\086\177\147\012\068\126\219\142\003\217\029\120\194\043\016\107\113\231\106\233\014\202\023\237\101\076\037\121\202\145\020\074\049\138\048\121\028\240\139\221\013\055\220\224\215\187\220\037\128\057\080\176\086\032\001\129\117\003\151\008\099\004\006\106\197\094\244\100\033\043\090\087\172\060\190\132\200\118\082\040\182\150\013\102\155\129\112\025\001\071\245\024\029\028\092\130\091\217\159\105\016\078\200\138\082\127\057\245\212\083\061\204\045\109\207\067\022\202\136\217\035\196\153\000\099\114\215\037\152\235\210\114\167\159\126\186\047\163\094\094\124\025\181\046\048\003\024\080\192\006\192\100\164\131\006\099\248\194\041\053\192\065\154\233\007\010\135\030\214\005\054\004\236\041\008\199\072\000\250\109\155\112\129\070\000\138\092\083\208\026\000\065\173\227\176\223\227\008\208\111\196\001\116\160\059\188\243\157\239\244\163\175\078\138\174\222\138\192\160\140\125\083\058\192\221\193\162\220\019\125\126\042\014\014\107\010\010\037\229\034\052\004\212\153\157\064\044\151\008\192\135\223\253\238\119\186\131\175\015\026\240\096\052\008\075\004\086\236\130\240\135\114\140\001\074\051\225\178\145\018\043\079\093\027\076\143\176\211\002\052\216\249\248\070\076\155\214\086\180\033\237\207\140\046\117\022\113\163\199\163\222\143\249\130\111\135\011\099\095\156\098\012\049\025\049\197\136\150\062\191\059\156\121\230\153\062\136\210\230\096\098\009\235\090\061\096\146\075\040\151\204\075\162\045\205\012\093\047\222\081\014\116\014\044\216\217\029\189\044\193\134\238\232\069\190\143\183\098\131\056\067\090\131\047\008\206\191\186\131\091\056\079\061\245\148\091\150\238\174\080\136\244\005\063\241\228\076\077\038\232\046\185\077\056\003\220\029\226\155\154\208\029\120\174\194\052\002\021\019\040\026\081\083\223\126\218\068\139\029\159\083\142\166\132\126\244\209\071\239\188\243\078\159\112\180\225\008\224\143\086\036\092\070\238\235\017\118\148\136\165\071\136\152\221\094\160\101\084\097\031\102\115\218\177\165\065\228\169\174\065\080\149\127\047\024\033\188\144\072\090\104\083\145\036\016\049\068\100\052\241\183\188\229\045\126\046\113\018\177\138\022\032\113\236\041\102\160\003\198\032\024\012\140\231\002\071\044\205\041\176\040\068\231\128\140\044\172\130\217\065\149\057\032\011\245\093\137\165\237\127\145\119\124\115\094\208\023\192\119\052\028\063\085\040\102\170\132\002\016\132\141\129\158\235\055\105\135\050\219\193\150\017\180\240\135\201\056\192\221\129\087\074\001\248\169\059\240\057\221\033\037\165\122\112\196\081\229\161\009\139\148\144\145\007\004\142\187\055\222\120\163\227\131\238\080\178\142\063\168\096\070\065\022\205\088\152\131\186\122\124\231\062\040\017\091\203\006\179\205\064\244\156\188\000\001\225\032\068\207\134\180\093\237\091\077\065\131\008\208\246\042\227\213\168\007\254\188\121\243\136\197\011\171\080\046\047\136\130\248\229\146\140\089\070\028\137\091\188\120\113\254\091\170\212\058\029\232\068\244\088\052\150\072\098\177\132\049\224\018\147\217\140\183\004\071\002\154\041\028\064\196\066\163\058\097\176\049\064\023\184\011\003\184\104\047\170\044\148\117\149\171\099\130\176\235\011\030\129\090\131\019\132\238\176\124\249\114\063\066\211\080\002\034\038\102\225\128\056\047\093\186\084\108\197\077\118\200\184\139\063\076\048\240\221\129\099\060\084\034\138\140\207\234\070\245\164\059\024\085\152\032\226\056\062\008\007\097\145\034\143\016\026\035\252\226\023\191\088\182\108\153\248\074\188\187\056\131\007\250\011\164\217\138\198\042\202\221\193\179\033\154\005\065\004\064\232\068\070\244\108\054\200\174\067\008\102\025\049\197\080\060\245\002\187\087\143\200\251\069\070\151\180\177\220\047\008\011\022\044\208\050\232\228\148\133\240\171\176\028\224\016\206\093\115\189\074\156\116\210\073\058\056\154\114\173\193\066\250\130\069\139\001\136\042\216\198\096\171\000\133\064\039\133\131\001\142\004\054\164\237\007\042\202\152\109\137\118\055\238\012\198\234\093\116\090\008\098\137\131\131\142\144\214\192\024\161\240\061\210\089\216\221\068\195\008\209\032\197\126\232\057\234\168\163\100\071\096\019\189\196\173\200\068\114\027\142\003\223\029\248\006\252\228\191\162\209\029\020\150\242\082\199\128\080\085\130\232\076\165\236\120\046\118\210\105\138\040\027\193\039\156\219\110\187\237\241\199\031\215\137\221\002\183\072\110\037\040\041\160\051\008\039\116\070\246\004\165\083\068\198\184\149\006\244\101\058\247\003\001\084\094\098\152\017\001\104\064\008\172\048\106\016\186\173\039\143\099\191\157\172\206\060\234\053\008\112\041\218\028\065\251\012\225\210\234\182\016\167\016\124\009\178\022\078\064\219\137\039\158\232\187\166\223\062\244\005\106\041\145\050\011\169\096\043\090\154\001\061\130\193\208\069\097\212\014\212\024\155\141\188\224\011\232\005\246\100\070\005\227\055\047\027\210\165\021\137\025\007\021\150\000\101\195\030\139\042\087\133\093\186\003\195\216\195\072\054\136\024\025\146\104\083\140\002\235\197\237\013\111\120\131\221\033\182\018\074\102\080\163\103\209\045\197\192\119\007\022\196\073\222\242\089\073\169\045\101\167\200\212\049\008\135\072\185\117\224\129\007\186\075\222\165\144\101\150\075\053\237\248\112\249\229\151\251\216\139\118\011\240\183\006\209\096\148\033\203\025\187\192\066\032\151\070\153\006\117\198\128\087\094\121\005\211\196\173\089\125\075\231\038\020\025\109\185\046\016\088\240\180\017\195\052\095\165\102\039\235\014\122\129\006\017\232\008\162\205\120\047\032\071\117\254\239\223\217\219\028\225\056\123\040\055\186\076\052\208\210\241\231\127\254\231\071\030\121\164\099\157\143\100\020\082\043\107\150\144\038\203\049\195\186\198\046\160\042\160\100\080\193\090\198\075\016\167\192\246\203\134\244\160\246\110\127\197\021\087\124\255\251\223\215\035\048\073\014\170\037\081\110\021\096\143\106\177\040\051\028\120\021\140\145\157\191\250\213\175\030\120\224\001\002\009\142\017\141\111\148\056\239\020\039\156\112\130\159\129\019\094\169\017\091\050\209\060\076\198\065\236\014\106\136\195\002\193\255\210\029\074\193\249\121\194\211\201\225\074\217\137\023\136\072\137\142\207\188\023\092\112\129\095\137\021\065\002\026\001\050\253\006\013\081\101\148\081\154\147\084\069\134\232\194\145\236\095\255\250\215\055\223\124\051\027\188\055\154\002\052\244\123\245\129\154\040\068\065\009\175\039\143\254\107\027\235\002\066\170\071\164\059\232\020\104\124\085\107\245\089\179\102\217\246\132\077\119\025\112\010\033\059\179\103\207\062\227\140\051\014\059\236\048\095\043\148\172\099\157\076\233\227\228\101\080\237\090\014\204\005\083\134\030\130\015\012\150\041\249\146\032\126\121\080\027\109\072\175\247\231\157\119\222\245\215\095\079\128\109\036\141\131\010\075\128\222\202\030\037\228\212\192\018\125\129\049\046\025\166\114\208\009\026\201\196\013\193\170\253\247\223\255\228\147\079\246\131\180\196\137\176\045\032\194\004\002\002\195\004\131\210\029\248\198\079\113\225\051\207\249\175\065\040\083\143\050\053\007\104\076\145\114\178\066\147\151\084\151\102\129\075\017\127\236\177\199\238\187\239\190\231\158\123\078\041\184\021\184\213\063\152\158\037\104\214\023\050\170\048\207\028\144\075\025\013\048\101\218\040\211\119\223\125\183\095\088\009\040\002\026\250\183\244\096\204\018\037\016\097\176\123\005\211\078\022\201\210\032\180\006\061\194\168\065\104\025\132\121\237\083\130\186\212\178\249\034\026\049\140\006\239\017\239\125\239\123\015\057\228\016\199\013\194\090\003\085\041\092\202\201\147\161\001\050\101\155\140\108\134\036\078\166\228\072\214\192\014\084\036\250\184\039\074\254\085\110\054\111\177\133\091\056\129\037\032\134\236\081\159\170\069\107\096\201\203\157\127\204\251\205\111\126\227\161\066\107\196\082\063\228\113\096\201\146\037\007\028\112\128\032\219\023\057\151\137\109\130\236\238\240\193\032\118\007\014\131\006\033\091\202\087\181\009\071\160\148\093\010\150\218\213\032\018\142\196\017\109\150\081\208\175\190\250\234\123\238\185\071\029\036\184\152\253\003\205\153\072\143\116\130\116\006\146\122\239\189\247\222\116\211\077\062\118\088\008\240\049\193\020\013\226\178\203\046\211\167\076\161\004\048\135\009\068\009\108\093\208\130\021\153\144\010\175\006\225\165\064\096\117\135\002\028\049\039\227\004\113\236\177\199\226\243\130\059\196\156\111\253\222\238\200\160\149\232\014\166\083\066\088\202\036\142\242\084\173\181\076\217\086\096\042\036\125\246\158\052\233\011\178\099\067\026\189\222\255\240\135\063\196\223\107\175\189\248\056\052\166\170\094\246\232\185\041\024\102\048\070\115\096\155\199\201\157\119\222\153\238\192\024\001\044\113\243\128\020\112\103\052\025\145\047\065\182\065\018\228\034\051\124\136\193\234\014\241\080\092\120\206\127\081\208\038\133\067\217\057\199\130\075\241\021\065\159\039\213\037\121\151\160\008\204\002\156\159\255\252\231\087\093\117\149\247\127\157\034\183\220\197\239\007\076\164\065\058\237\115\218\146\081\021\134\246\216\249\215\127\253\087\175\136\082\171\041\000\062\168\051\134\169\060\047\144\152\038\082\002\253\088\125\144\166\168\060\016\043\040\013\066\108\157\206\060\255\109\117\246\239\090\249\083\145\118\190\167\150\103\151\215\007\080\169\167\156\114\138\071\046\097\119\077\036\032\077\124\167\144\090\176\004\012\146\011\125\081\043\230\032\125\082\032\095\186\128\116\072\080\096\043\250\134\253\203\095\254\146\253\188\080\111\125\209\185\053\050\049\166\216\163\150\088\146\214\160\071\232\014\106\198\217\129\181\226\038\128\128\048\203\168\011\123\131\211\197\108\004\065\214\127\237\014\252\096\107\172\026\140\185\131\216\029\226\176\208\240\031\196\066\071\008\212\031\002\071\052\017\126\150\175\250\038\142\185\020\119\137\215\134\069\095\172\229\163\220\138\192\022\141\230\210\064\143\242\162\153\078\069\134\096\225\035\143\060\114\206\057\231\120\081\196\041\032\111\167\185\092\185\114\165\147\133\137\056\091\180\226\208\008\139\051\023\064\144\085\155\120\170\060\251\188\218\032\188\226\234\005\070\253\194\254\159\063\127\190\015\144\239\123\223\251\142\063\254\120\245\138\105\107\153\226\150\233\148\012\159\214\144\024\074\156\206\238\065\045\119\182\159\164\168\028\027\018\097\043\254\228\039\063\033\102\203\113\065\052\208\131\007\053\016\168\007\173\074\253\040\036\150\120\206\249\148\198\060\047\056\010\137\001\044\073\171\034\207\126\016\088\111\118\051\103\206\020\109\197\239\146\128\196\001\097\083\134\027\006\177\059\112\149\207\192\121\133\171\224\132\035\135\008\099\162\131\016\101\049\037\070\030\010\129\022\086\129\254\198\055\190\225\193\046\019\226\139\003\110\245\003\038\210\144\229\084\088\146\138\176\139\116\129\043\175\188\242\146\075\046\209\005\112\164\092\217\025\077\097\207\237\183\223\254\208\067\015\109\189\001\253\176\185\143\083\024\009\226\172\218\196\089\084\053\008\135\088\174\249\142\224\245\193\001\066\119\240\075\132\081\047\192\081\163\062\055\216\081\090\006\049\251\202\020\019\229\072\178\168\002\058\251\104\192\128\137\117\083\036\005\178\006\018\039\005\178\035\113\090\131\017\109\079\222\120\227\141\014\119\154\154\095\001\246\220\115\079\010\006\213\236\216\195\024\173\074\133\048\067\107\112\234\100\009\123\208\222\133\159\125\246\217\152\017\097\198\187\004\151\036\201\032\132\087\156\229\011\225\214\240\196\224\118\007\062\075\021\136\002\040\092\077\001\084\097\070\021\252\219\223\254\246\142\059\238\032\083\132\011\141\163\113\252\248\199\063\246\001\194\251\005\090\160\069\022\220\234\007\076\151\087\160\202\254\087\100\082\165\053\236\179\207\062\022\245\245\225\103\063\251\089\074\080\166\009\016\099\161\143\163\191\248\197\047\212\129\199\023\013\253\088\119\008\166\176\031\148\154\056\219\225\194\235\128\230\044\224\059\130\243\182\142\160\011\232\014\211\058\255\244\136\092\186\165\053\240\145\176\164\152\104\058\037\084\193\016\152\189\217\037\228\026\068\094\094\164\067\094\036\002\228\206\078\243\216\240\217\136\018\110\250\069\086\043\100\060\048\030\240\007\022\044\001\053\080\045\033\102\056\053\000\066\037\251\074\101\081\171\071\146\176\203\152\164\161\044\091\182\236\011\095\248\130\138\066\023\062\097\244\048\196\160\119\007\062\115\030\148\157\102\169\065\040\193\000\045\130\222\208\108\081\065\140\012\014\152\085\133\238\096\223\042\014\089\033\073\000\170\002\189\211\052\071\192\044\144\024\165\182\118\237\218\020\025\195\236\016\079\206\039\159\124\210\103\014\141\063\119\085\164\039\146\130\243\102\171\059\056\049\050\192\244\032\010\135\213\200\077\224\014\136\112\181\065\240\194\121\193\009\066\083\000\132\075\173\193\166\210\065\134\127\107\144\119\073\209\175\147\050\005\131\246\083\133\019\223\227\143\063\046\011\218\095\142\235\217\135\226\128\057\176\144\119\181\007\234\071\037\164\079\057\050\232\011\042\132\121\079\060\241\132\086\165\109\117\089\151\073\128\073\003\155\175\185\230\026\077\141\071\131\097\164\085\006\016\131\222\029\132\000\068\039\080\184\154\130\218\245\164\082\148\182\165\231\182\212\098\138\157\013\041\250\145\143\147\104\132\211\218\005\023\092\224\120\111\075\071\006\179\127\176\010\200\141\004\171\176\228\210\230\209\029\048\189\068\220\117\215\093\110\089\008\108\030\230\089\200\183\015\159\072\021\037\025\022\210\000\248\195\013\194\005\009\181\144\138\179\032\115\205\233\064\168\237\031\029\001\016\046\049\157\155\008\232\035\132\051\203\116\024\014\126\137\048\136\182\152\203\072\118\163\020\000\026\199\151\072\201\178\045\061\117\180\060\173\028\161\192\056\050\224\246\179\036\096\140\238\192\000\149\227\176\160\059\104\013\104\143\022\143\016\028\075\011\032\032\128\049\038\154\101\116\233\212\230\055\035\239\116\194\206\212\034\230\214\048\196\160\119\135\226\179\048\009\135\042\084\178\202\081\046\141\238\238\189\247\222\126\105\247\002\236\050\017\020\050\194\025\067\168\000\175\151\095\253\234\087\189\097\202\141\138\129\008\211\208\023\208\070\044\163\137\090\012\061\042\076\131\048\218\036\172\034\000\190\116\200\055\166\238\192\096\039\113\119\159\126\250\105\159\190\140\044\145\105\171\007\084\129\089\195\010\220\020\055\072\180\133\090\131\224\133\143\011\005\046\049\221\226\056\049\194\096\034\116\248\050\060\254\017\228\106\166\108\066\173\001\100\237\215\191\254\181\086\030\051\057\162\191\243\066\190\122\244\066\142\122\068\166\111\118\204\092\198\072\189\178\081\024\012\096\070\078\013\058\130\075\103\091\079\047\170\024\080\053\067\060\077\199\007\070\158\126\250\233\127\247\119\127\119\248\225\135\139\063\073\204\225\140\033\234\014\098\004\090\187\020\234\002\026\167\232\056\211\058\065\136\014\098\225\194\133\139\022\045\242\052\115\041\007\032\167\093\198\167\000\000\016\000\073\068\065\084\118\162\108\022\096\202\132\223\180\175\191\254\122\221\218\093\169\018\116\112\171\143\160\039\032\111\034\013\244\232\002\210\204\036\134\225\227\044\095\190\220\167\144\020\129\145\109\078\016\008\175\148\186\131\058\080\028\102\145\084\184\064\085\096\250\240\001\079\005\016\196\208\254\023\103\141\000\108\036\016\127\052\166\091\004\136\129\041\195\199\126\033\149\032\016\103\029\217\179\218\059\133\125\008\008\151\142\114\026\068\012\086\075\126\023\215\248\120\001\085\071\162\039\163\100\021\208\028\166\049\074\054\053\018\000\242\230\050\070\246\025\192\012\117\168\038\125\198\054\058\053\060\252\240\195\196\044\205\000\170\208\198\204\066\059\029\159\117\214\089\127\251\183\127\123\234\169\167\078\159\062\093\240\133\157\048\016\027\182\024\138\238\032\004\032\028\186\131\125\040\052\210\169\017\216\117\057\223\098\138\187\151\097\135\136\253\246\219\079\249\010\043\008\171\081\236\076\055\250\034\224\103\005\077\090\062\200\187\069\000\220\234\011\040\169\194\068\249\182\237\149\026\130\121\148\208\169\005\248\196\144\138\084\001\196\052\008\183\048\189\224\248\230\004\207\060\243\140\091\010\197\068\083\128\024\016\027\062\136\179\138\021\120\167\017\104\007\066\029\184\148\014\124\119\035\057\124\044\023\201\064\150\037\066\156\179\033\237\073\208\154\253\002\237\013\095\238\098\179\175\173\126\130\225\011\071\194\049\070\131\081\118\064\166\128\066\064\224\128\187\001\249\094\064\134\176\229\088\226\241\224\008\035\251\014\152\160\120\124\068\184\238\186\235\088\088\052\144\071\155\098\084\234\179\102\205\058\229\148\083\188\080\120\004\106\013\056\049\085\228\009\084\109\118\057\172\048\020\221\129\195\066\032\022\202\081\081\166\059\232\244\222\126\157\181\242\121\012\083\029\232\023\243\230\205\019\077\083\004\087\034\141\104\209\004\132\214\224\253\194\135\076\037\146\187\050\001\110\245\014\006\000\027\002\052\152\168\080\168\130\076\199\145\111\150\088\014\083\250\141\057\086\096\122\185\240\073\233\214\091\111\245\186\235\029\199\093\181\130\079\009\059\205\133\232\217\162\209\044\216\162\041\125\020\230\099\252\229\014\160\141\016\194\024\001\099\031\021\014\153\152\128\136\170\020\139\191\032\219\144\142\120\246\164\209\227\218\110\196\097\076\044\247\067\166\135\051\121\179\048\141\128\144\020\192\183\177\165\041\064\003\181\182\058\253\145\036\220\035\220\165\001\050\069\109\048\128\025\082\239\071\052\134\061\250\232\163\119\223\125\183\037\076\143\049\132\017\098\139\163\170\231\207\159\239\212\176\116\233\082\111\208\170\221\169\205\022\080\081\178\064\096\152\099\136\186\131\040\136\151\136\136\139\144\105\159\233\014\090\003\072\173\079\101\090\131\187\034\238\027\196\146\037\075\136\153\085\144\136\075\170\045\122\254\249\231\063\248\224\131\146\045\043\146\033\133\080\036\055\069\208\000\204\000\150\160\073\102\122\056\046\129\042\031\150\149\078\160\128\220\013\095\111\242\113\244\155\223\252\230\121\231\157\247\165\047\125\073\159\242\166\227\075\053\171\232\001\115\129\112\239\032\003\228\033\046\032\010\220\130\087\053\012\196\127\240\052\224\072\065\056\198\129\088\225\143\116\048\030\138\059\085\007\241\225\143\164\187\093\016\000\211\069\094\138\101\193\099\057\123\210\193\193\046\149\122\199\120\049\055\053\246\163\221\210\053\220\181\156\233\064\131\145\018\076\122\200\080\021\056\006\222\124\243\205\126\159\178\195\201\000\085\221\129\079\009\208\096\122\105\013\022\002\151\244\220\114\203\045\222\067\073\102\122\236\201\162\042\252\204\051\207\124\199\059\222\113\192\001\007\248\122\165\194\029\066\085\181\238\160\252\036\130\048\100\226\240\028\135\168\059\136\002\056\059\216\255\206\183\222\029\196\110\199\029\119\020\050\173\193\059\005\160\053\008\050\226\238\211\174\099\152\247\014\081\147\030\064\208\096\212\062\190\252\229\047\127\227\027\223\240\218\073\082\053\184\043\061\224\110\239\160\001\170\137\049\011\036\076\083\047\115\189\056\120\191\176\016\253\010\203\018\185\165\004\029\035\111\184\225\006\095\064\206\061\247\220\015\127\248\195\103\159\125\182\075\245\161\236\098\070\036\055\053\090\139\024\208\105\084\070\085\132\137\079\012\054\165\100\216\242\217\204\120\136\035\221\093\011\159\000\201\094\188\032\064\210\158\020\085\173\193\049\065\228\095\122\233\037\163\103\181\131\155\187\166\075\037\032\156\227\110\186\233\038\223\173\061\198\109\120\041\163\001\098\064\054\182\084\082\005\222\079\047\187\236\178\015\126\240\131\186\188\166\179\041\075\240\105\000\102\068\003\051\216\224\212\160\053\160\085\200\181\215\094\171\085\145\081\081\204\128\216\099\084\204\167\157\118\218\241\199\031\159\242\118\169\224\061\020\021\191\055\059\069\110\010\049\083\134\051\134\162\059\136\002\008\007\232\014\217\138\250\168\094\224\172\149\240\025\065\016\117\004\189\067\046\029\023\253\240\147\216\073\128\108\161\105\160\074\182\156\240\047\190\248\098\191\117\075\158\187\064\000\200\244\002\115\105\040\112\105\138\082\067\200\156\049\115\021\141\034\211\029\020\001\075\020\089\248\221\071\191\116\106\016\154\133\227\006\049\102\000\157\221\037\113\240\129\000\016\230\005\216\000\001\026\184\195\030\002\036\193\172\145\002\214\002\203\217\207\011\190\064\092\051\162\109\090\094\019\000\146\208\221\053\076\119\129\036\121\019\237\103\077\193\182\052\186\212\157\029\214\076\148\068\249\034\137\094\185\114\229\247\191\255\253\047\126\241\139\206\116\062\016\202\154\233\108\000\083\100\144\018\057\013\212\204\143\126\244\163\021\043\086\028\116\208\065\138\144\006\139\002\061\005\046\241\129\006\102\208\064\039\027\210\026\088\162\060\244\035\173\193\020\102\024\139\061\102\105\001\135\030\122\232\009\039\156\080\206\197\170\218\090\158\064\110\105\013\096\086\096\238\176\197\080\116\007\206\039\016\034\232\076\165\059\104\159\034\037\094\026\132\192\105\010\037\142\014\020\186\172\240\201\135\006\225\131\147\134\066\067\021\146\231\215\035\199\135\203\047\191\092\178\229\079\074\000\031\170\146\133\142\001\101\100\009\184\036\160\154\141\076\098\027\002\060\094\060\142\240\149\005\133\008\076\032\015\101\034\090\007\081\175\206\017\121\019\086\076\228\003\242\085\096\178\016\104\179\085\074\213\114\083\213\026\045\202\041\191\225\107\052\100\072\154\002\085\037\195\150\102\039\131\193\182\148\014\014\010\093\246\036\215\056\232\016\238\059\162\039\191\136\017\003\083\160\139\071\056\192\125\074\132\040\026\108\075\223\161\233\116\070\179\033\221\146\130\076\036\140\192\113\220\243\053\234\234\171\175\190\232\162\139\208\056\114\097\010\051\172\200\006\091\026\004\089\205\120\029\080\102\186\131\210\138\006\074\002\151\192\060\136\134\076\103\131\035\131\166\064\149\004\253\244\167\063\245\027\022\253\153\085\070\115\209\251\238\187\175\111\144\083\167\078\085\219\022\082\228\074\221\051\079\107\176\162\218\102\063\168\031\194\195\025\067\212\029\132\064\044\192\014\132\210\032\132\076\236\004\209\033\002\180\009\035\142\039\185\058\035\233\011\165\152\154\046\238\128\008\208\062\092\127\229\043\095\241\246\232\140\167\146\164\019\240\033\050\155\026\153\033\055\128\032\108\022\184\132\076\081\205\154\142\126\033\151\110\117\020\065\173\070\184\214\249\071\044\096\030\002\079\201\150\167\150\202\166\019\179\010\028\122\140\156\082\184\172\045\117\175\230\236\028\219\198\067\239\138\043\174\112\012\113\060\086\145\036\051\197\172\170\170\097\072\179\048\166\178\217\142\138\119\182\162\029\229\097\107\075\123\080\243\206\121\222\055\035\052\223\069\041\083\204\045\030\161\001\159\030\081\178\177\109\069\185\160\007\033\080\126\197\116\073\062\185\032\140\014\194\033\099\021\075\008\160\233\070\107\177\036\160\068\135\242\090\138\239\189\213\231\173\164\047\026\140\020\002\003\128\035\242\078\137\089\122\019\205\090\003\061\146\229\220\186\108\217\050\002\166\128\041\016\194\008\206\188\126\122\083\198\165\053\120\022\042\039\101\159\214\192\090\032\057\204\049\116\221\065\032\068\004\164\004\132\073\176\124\164\017\056\157\085\040\211\035\018\080\199\007\013\194\020\132\041\008\009\075\014\092\002\014\248\244\240\173\111\125\203\166\242\076\080\079\100\128\024\184\219\005\102\117\007\073\149\010\132\221\053\006\180\057\182\248\001\069\125\043\014\076\119\001\097\138\017\109\045\035\071\092\122\197\240\145\242\201\039\159\084\217\248\100\000\031\016\129\091\074\202\230\081\157\234\140\102\005\167\218\252\080\234\059\235\039\062\241\009\095\058\191\246\181\175\121\250\221\119\223\125\196\162\135\134\225\140\184\102\228\157\160\049\059\027\050\222\121\140\059\129\243\235\095\254\229\095\184\246\169\079\125\074\251\043\221\220\172\226\026\058\168\234\177\051\005\138\066\009\018\091\045\091\076\076\049\002\121\241\079\143\070\040\042\183\008\139\167\037\016\166\235\038\160\191\208\227\104\246\131\031\252\000\159\152\015\091\170\014\081\064\027\080\107\173\056\034\077\230\202\190\214\224\188\064\003\027\156\026\156\239\204\178\162\165\141\144\075\211\017\064\121\030\114\150\240\252\083\228\074\221\147\134\060\035\201\003\177\225\143\033\237\014\009\135\208\128\048\009\150\168\057\026\164\065\104\004\233\017\026\132\078\225\082\184\141\118\105\038\186\148\060\163\233\230\026\117\119\191\047\122\225\212\206\021\162\075\169\141\012\177\204\234\050\154\005\085\038\121\179\186\200\227\004\026\144\018\033\031\001\115\067\224\004\185\084\136\151\092\114\137\039\036\194\068\058\203\093\002\046\049\211\026\084\167\098\181\121\020\156\034\246\098\226\003\138\159\066\252\032\098\045\199\099\122\046\188\240\066\143\092\238\152\104\058\068\219\240\028\025\025\239\024\204\059\187\040\219\073\203\094\190\124\057\119\244\059\059\150\107\126\107\208\205\053\008\180\104\152\200\053\136\095\008\122\116\007\122\236\204\168\018\043\015\112\041\112\064\195\039\019\225\234\168\150\092\074\141\145\078\199\201\251\239\191\159\025\096\058\152\238\107\197\165\151\094\234\203\037\013\182\238\204\153\051\109\218\084\145\089\128\111\046\003\186\180\006\029\156\035\052\200\136\183\018\245\198\048\242\089\206\008\230\154\136\073\243\219\222\246\182\035\142\056\066\221\166\053\040\111\069\238\017\194\072\146\001\201\017\129\109\208\029\196\069\140\004\043\208\083\029\186\004\209\097\065\064\133\085\107\000\157\002\083\010\103\207\158\237\253\194\165\040\155\040\019\070\160\039\112\092\252\194\023\190\224\157\179\143\013\034\179\050\166\032\164\086\081\210\028\038\229\046\061\192\237\088\143\011\052\126\238\178\057\180\075\098\070\115\113\064\185\251\136\237\001\165\136\169\005\119\241\141\104\119\241\021\189\058\243\056\210\026\088\011\204\086\115\234\152\036\133\160\113\124\231\059\223\241\140\082\151\148\155\075\131\187\195\016\012\099\030\116\241\142\229\206\068\066\161\053\056\059\216\111\140\231\154\081\131\248\248\199\063\110\151\010\130\089\230\082\018\160\133\154\112\057\128\008\139\189\141\227\113\173\161\152\014\209\131\128\076\052\162\011\156\227\188\157\009\163\037\128\018\180\111\013\183\221\118\155\120\170\168\249\243\231\079\159\062\093\225\037\155\038\090\026\220\101\146\213\165\041\179\164\009\216\224\053\086\115\161\057\107\177\001\001\069\003\194\123\177\223\041\222\249\206\119\206\152\049\067\037\091\072\197\102\021\119\193\044\107\141\032\108\155\238\144\000\009\150\144\129\008\106\016\162\169\065\232\014\026\129\227\131\054\188\221\118\219\145\193\089\188\120\241\201\039\159\124\200\033\135\180\180\180\152\043\139\144\220\152\142\227\009\252\245\175\127\253\187\223\253\174\044\042\038\069\038\217\004\192\221\077\193\093\032\073\222\214\053\022\073\037\162\059\040\074\133\130\201\012\035\144\015\109\086\224\018\220\002\091\093\009\230\248\064\178\128\102\086\209\233\150\122\245\104\245\056\082\118\126\117\247\046\109\034\112\164\060\202\236\046\239\026\054\146\098\181\074\244\144\025\110\136\097\188\099\103\241\142\241\188\003\063\061\058\076\197\102\222\033\018\040\123\213\079\012\054\176\152\023\239\016\114\026\061\098\238\249\172\141\218\150\226\102\116\112\192\140\134\040\065\007\038\066\044\009\135\037\062\042\107\235\044\177\150\137\046\117\091\027\158\000\075\124\143\244\021\028\065\021\152\075\131\165\217\227\156\098\105\043\154\040\065\160\131\171\046\153\149\014\211\201\155\136\040\048\023\173\086\223\243\158\247\156\121\230\153\123\236\177\135\050\086\204\074\090\097\019\006\179\200\140\056\108\203\238\032\088\162\038\118\224\232\165\209\138\169\200\106\007\233\014\154\177\075\123\070\137\016\152\054\109\218\097\135\029\038\181\222\068\100\212\116\035\013\004\228\213\195\225\156\115\206\249\222\247\190\167\020\036\088\201\074\027\144\001\194\065\023\058\151\042\067\089\016\142\140\081\133\249\157\044\189\198\165\085\024\137\000\180\017\050\023\129\003\004\060\048\175\188\242\074\101\164\034\105\011\020\061\099\088\200\042\021\175\059\168\090\245\231\164\250\227\031\255\216\148\104\048\022\133\166\056\182\040\104\146\124\199\007\002\195\010\076\002\166\198\059\046\199\059\189\207\062\228\151\175\250\236\103\179\200\128\016\129\075\179\028\040\156\152\236\189\120\039\080\152\244\072\132\200\071\021\037\020\010\154\179\161\173\078\134\018\136\018\122\010\204\069\103\116\023\225\043\175\179\134\029\046\218\104\145\180\201\201\128\210\058\224\128\003\212\152\178\137\048\023\172\043\065\106\192\138\082\195\005\182\153\034\071\188\096\170\078\071\160\203\234\076\098\179\022\112\224\129\007\190\253\237\111\247\066\177\235\174\187\058\246\250\214\160\053\168\088\242\096\021\235\142\068\108\227\238\144\144\009\159\084\137\178\087\009\145\149\057\041\212\026\166\188\246\231\052\033\229\132\181\124\199\066\013\066\232\093\098\130\233\114\224\242\177\199\030\243\043\198\183\191\253\109\047\240\042\076\229\201\031\144\009\200\064\232\140\238\042\014\137\039\239\086\001\166\090\129\194\177\010\218\044\099\119\048\000\240\189\241\058\078\251\160\160\110\040\007\149\199\018\170\028\028\084\158\122\085\124\224\108\162\004\077\041\154\009\151\075\132\126\167\071\216\030\248\214\005\204\097\002\198\004\220\044\222\217\090\188\211\017\120\234\067\131\045\205\218\226\093\008\028\016\013\135\038\063\046\144\020\106\014\210\035\080\018\225\022\166\214\032\086\058\133\239\005\014\032\214\050\075\132\171\074\112\000\007\016\128\000\132\190\224\019\038\123\192\015\037\206\041\152\193\222\123\239\237\075\150\007\012\109\056\086\183\174\133\020\000\225\216\239\224\035\131\236\191\225\134\027\100\083\057\145\164\025\016\140\009\129\070\236\191\255\254\111\122\211\155\142\063\254\120\063\097\122\161\080\192\090\131\098\086\210\089\130\216\008\197\182\239\014\226\043\136\096\195\011\171\180\009\177\118\224\205\066\047\016\113\208\146\053\010\093\153\140\044\250\185\232\141\111\124\163\052\008\186\194\050\022\040\038\031\249\124\036\247\061\140\164\194\085\118\100\064\082\203\136\080\022\070\064\168\015\069\073\009\099\140\036\141\085\224\144\052\214\218\219\091\055\110\108\107\104\168\141\031\095\155\056\177\214\210\130\217\222\214\086\132\021\150\019\129\231\149\066\183\052\205\144\226\083\244\042\094\225\042\125\079\054\069\159\089\124\175\034\054\184\229\121\069\149\062\066\143\085\112\186\000\179\128\121\065\225\032\186\200\247\114\073\056\136\146\234\024\190\177\203\116\028\161\099\027\079\069\079\023\179\181\056\136\182\175\120\103\179\101\010\201\040\228\166\061\019\007\237\222\219\111\191\157\119\226\067\009\072\150\185\244\152\040\068\008\183\068\082\220\104\048\203\040\254\084\117\016\081\093\235\248\165\217\045\168\213\058\232\090\173\099\164\214\051\223\139\161\190\224\173\132\124\004\148\214\190\251\238\235\193\163\144\106\181\026\085\150\144\029\107\089\209\044\173\205\145\001\116\046\111\019\090\024\147\072\178\028\040\001\151\038\070\231\146\037\075\222\245\174\119\045\092\184\208\239\020\158\106\244\123\194\057\005\211\095\149\055\101\036\162\191\221\097\160\125\021\074\001\133\052\008\111\113\142\015\186\131\190\160\059\000\194\165\174\161\043\043\023\189\195\103\008\050\012\081\163\073\149\204\033\228\213\143\139\062\067\056\145\218\132\122\132\202\147\206\002\050\161\077\132\204\082\037\084\109\010\166\128\187\237\181\090\123\189\190\195\132\009\115\118\217\101\222\046\187\076\157\052\169\214\208\128\153\170\037\064\143\055\011\117\111\171\040\119\151\198\082\127\054\015\227\093\106\094\074\144\188\213\001\193\036\198\024\093\138\134\081\189\122\238\121\187\033\143\207\000\032\009\136\000\223\172\030\065\192\093\035\249\222\065\006\008\211\147\081\196\160\092\098\018\128\232\065\000\038\025\014\050\047\187\139\193\188\227\047\239\108\051\050\188\048\005\017\152\018\014\166\173\232\199\005\143\101\205\133\018\035\072\086\090\131\209\165\094\239\253\142\176\089\098\066\009\013\237\141\141\227\199\141\155\177\195\014\083\182\219\174\214\220\220\209\119\227\186\144\000\000\016\000\073\068\065\084\152\219\059\050\064\128\024\097\096\143\195\139\183\188\235\174\187\142\085\056\129\018\210\029\060\129\092\210\198\084\155\223\090\146\197\096\157\221\011\145\019\168\012\154\232\224\192\072\146\058\026\068\191\089\128\169\197\188\249\205\111\062\235\172\179\156\100\021\167\071\151\162\165\089\119\080\162\017\038\054\162\049\044\186\131\164\006\186\131\200\138\175\115\129\078\108\243\235\002\078\013\186\003\200\129\236\074\131\028\168\066\151\014\117\196\036\064\194\228\195\116\160\074\213\234\014\031\254\240\135\037\216\051\074\249\042\053\037\168\220\193\093\099\129\126\100\081\101\071\079\047\160\214\221\118\167\134\150\150\133\147\038\189\127\210\164\063\159\056\241\240\206\227\067\173\177\145\001\064\000\016\190\077\170\176\172\171\254\020\043\131\149\169\238\192\018\027\222\035\145\036\080\107\105\198\152\229\050\035\095\240\093\154\229\085\069\237\018\032\134\003\100\192\037\240\133\095\116\066\150\051\042\122\252\076\033\009\102\245\008\183\040\009\200\087\085\209\067\039\096\186\021\025\242\064\149\017\211\045\098\113\208\030\227\032\121\175\075\054\024\025\224\005\095\016\001\037\102\133\214\008\180\111\031\252\050\203\196\232\225\050\142\064\209\236\201\159\253\153\041\122\064\091\123\251\152\150\150\003\118\220\241\173\059\239\124\220\142\059\078\158\056\209\018\152\004\016\016\130\097\244\155\203\170\048\025\236\150\250\081\072\056\044\177\034\025\107\057\205\165\053\232\014\250\145\154\241\179\171\159\039\200\147\100\127\230\162\113\076\052\106\022\075\151\046\245\066\161\215\040\081\053\169\053\040\090\181\164\002\221\053\139\060\016\030\185\024\022\221\033\225\019\074\049\181\081\029\204\052\136\241\227\199\059\167\137\187\232\075\170\030\161\029\128\158\141\073\192\044\223\135\143\062\250\232\208\073\027\013\032\157\074\205\167\175\047\127\249\203\023\092\112\129\223\168\149\172\106\179\109\212\141\157\099\004\004\072\167\066\065\080\200\006\064\244\008\106\027\234\245\233\219\111\127\084\123\251\137\079\063\125\204\139\047\030\218\214\182\253\164\073\245\206\238\096\074\153\235\236\224\247\008\165\201\012\037\168\059\160\021\034\130\025\094\025\148\035\249\152\026\203\185\230\151\048\190\219\063\056\081\101\171\240\066\201\098\090\189\128\000\014\119\032\075\144\012\044\193\089\013\037\078\145\132\076\180\098\021\097\186\075\149\104\144\239\162\138\205\158\165\222\192\233\036\064\018\204\050\130\136\097\114\135\131\036\003\246\056\056\232\200\022\226\066\132\229\206\135\064\207\088\251\007\007\220\034\096\138\054\234\116\096\093\176\010\023\068\009\068\198\210\062\048\091\133\176\041\078\103\078\109\181\134\134\055\076\156\248\198\049\099\206\120\229\149\255\099\195\134\183\077\152\176\163\087\060\199\055\006\117\190\223\069\152\124\001\014\088\014\166\079\159\238\021\128\191\236\100\182\030\148\214\096\045\031\032\089\238\251\165\207\061\046\173\075\062\048\157\122\028\254\226\208\240\254\247\191\255\168\163\142\210\104\020\167\106\244\136\226\154\058\148\062\229\196\120\083\128\240\136\198\112\233\014\066\009\194\010\226\043\202\098\045\226\219\109\183\157\183\009\135\136\052\008\035\104\016\152\218\135\028\075\140\111\197\050\164\026\100\221\168\115\211\064\155\075\095\245\062\253\233\079\159\119\222\121\126\096\087\133\014\243\106\066\065\155\008\246\131\148\019\179\151\092\110\062\145\013\013\059\143\029\123\252\216\177\199\172\093\187\199\243\207\239\254\204\051\007\109\216\112\208\132\009\227\155\155\061\214\076\183\040\251\017\054\255\245\215\095\239\140\096\003\040\122\099\096\045\054\224\091\151\048\048\216\168\200\022\044\088\112\248\225\135\251\250\061\097\194\004\181\136\079\015\066\163\241\174\196\060\115\093\006\166\227\112\132\114\059\074\149\131\071\159\035\137\018\215\013\129\191\074\159\143\153\066\091\021\244\131\091\212\070\149\200\208\070\143\104\120\234\106\010\084\121\144\058\099\251\136\096\243\088\142\176\041\038\034\216\064\121\217\213\028\116\203\198\054\139\100\214\034\233\119\040\125\065\142\188\162\123\210\134\095\070\154\189\002\152\101\105\142\032\128\090\218\240\017\036\019\082\202\235\013\013\019\039\076\056\162\185\249\196\181\107\023\060\247\220\017\047\189\116\086\123\251\146\137\019\039\077\152\032\254\004\128\060\008\169\089\160\024\208\056\128\096\128\071\142\077\110\045\110\138\015\055\189\221\056\232\177\196\239\172\190\053\240\061\194\166\035\002\254\082\142\179\231\158\123\122\161\224\142\143\095\026\186\194\083\162\074\081\185\122\176\089\142\140\133\032\019\183\233\184\181\139\015\151\238\192\015\001\013\132\024\052\008\231\052\065\159\056\113\162\004\072\131\030\161\047\120\016\025\109\167\052\008\133\232\043\244\156\057\115\104\144\063\064\200\016\013\070\180\242\245\139\212\071\062\242\017\061\194\081\086\245\043\068\192\087\124\054\006\026\083\250\009\155\174\160\017\221\129\095\031\059\118\175\009\019\078\090\191\126\246\250\245\227\218\218\038\108\220\056\117\227\198\249\013\013\059\052\054\146\087\160\070\046\100\093\159\060\060\133\236\088\229\014\150\080\145\138\094\045\090\037\146\116\034\180\003\077\065\213\174\091\183\110\246\236\217\158\111\152\145\097\021\013\246\185\185\076\197\004\219\082\125\115\220\126\166\080\149\043\104\077\199\138\030\125\031\251\216\199\254\123\231\223\167\062\245\041\027\204\186\132\205\130\044\071\057\002\112\232\119\215\186\130\016\085\054\012\085\062\043\122\170\255\219\191\253\219\135\062\244\161\191\255\251\191\063\251\236\179\245\008\011\017\054\133\001\128\102\131\048\178\045\192\180\205\168\178\132\056\088\002\033\107\118\017\157\140\172\254\191\034\186\005\248\094\067\044\013\162\100\004\154\069\073\079\036\032\152\129\240\142\111\108\060\096\187\237\150\180\182\206\122\233\165\150\182\182\073\171\086\205\125\233\165\083\090\090\014\154\052\169\214\212\068\216\231\097\078\089\058\217\071\184\100\048\075\040\177\135\061\237\041\023\055\190\232\224\090\131\145\205\215\092\115\077\126\155\032\073\143\137\001\026\135\018\004\120\020\249\208\112\228\145\071\042\194\084\160\172\081\171\074\149\107\089\212\092\194\163\000\195\168\059\036\154\034\011\114\009\077\077\077\105\016\246\143\052\104\007\082\002\057\062\032\100\075\074\020\244\180\105\211\252\210\105\162\082\128\146\078\119\049\213\238\067\015\061\116\209\069\023\249\024\161\083\168\060\133\168\136\085\182\141\161\166\029\221\017\049\096\147\099\189\190\247\216\177\039\052\053\205\095\181\106\187\181\107\005\174\185\173\109\250\218\181\199\174\089\179\119\083\083\125\204\152\142\163\111\231\231\049\043\082\226\116\234\155\034\205\246\039\040\122\075\056\114\123\211\086\112\004\140\236\084\091\044\159\057\115\166\205\111\179\113\121\214\172\089\124\039\000\084\049\207\151\115\031\222\089\171\178\033\146\156\082\226\182\156\246\097\045\141\224\007\063\248\129\023\102\159\250\236\109\135\136\011\047\188\240\139\095\252\034\127\117\013\083\044\087\133\165\005\138\054\139\218\045\204\019\070\170\204\245\083\235\101\151\093\246\181\175\125\205\131\212\092\091\136\035\122\043\205\222\089\168\098\146\145\059\076\018\070\150\000\166\187\126\041\192\100\185\181\140\090\003\239\060\084\221\037\163\173\031\124\240\193\248\005\166\075\013\071\220\149\020\129\098\012\120\167\176\068\196\152\218\161\173\161\097\151\150\150\083\091\090\022\109\220\184\195\154\053\141\109\109\013\237\237\083\214\172\089\186\122\245\009\013\013\187\238\176\067\067\083\147\014\034\098\096\162\041\128\008\148\144\047\005\070\158\090\142\169\078\067\150\118\196\211\082\153\205\253\172\104\122\021\148\000\037\078\013\090\131\111\225\222\044\056\194\053\053\073\161\214\192\065\149\038\107\153\072\120\116\064\145\015\071\071\068\089\172\003\161\215\035\028\080\115\136\144\021\125\033\013\002\157\006\161\202\029\095\157\027\009\043\122\072\070\233\177\223\048\017\074\223\015\132\014\017\223\248\198\055\060\141\149\002\025\217\085\229\158\096\202\087\032\136\025\123\064\067\067\227\152\049\135\183\180\156\212\218\186\219\170\085\205\027\054\068\102\199\053\107\022\190\242\202\161\205\205\059\078\156\232\151\052\010\033\183\236\058\219\204\131\081\197\131\109\096\069\235\218\108\017\136\164\106\243\123\152\218\210\038\024\067\204\115\201\241\129\205\196\098\143\143\115\246\167\178\230\038\037\052\255\254\247\191\183\151\020\052\203\041\084\229\156\242\059\174\195\145\189\212\208\208\145\086\170\028\149\063\249\201\079\122\236\219\012\028\116\203\162\128\000\218\168\178\021\163\074\124\064\163\033\127\206\057\231\044\091\182\204\020\170\128\164\115\208\071\063\250\209\031\253\232\071\030\182\034\006\230\106\004\044\001\107\081\171\237\090\072\240\089\014\156\210\011\102\206\156\057\102\204\024\105\178\139\220\210\044\228\142\078\002\192\012\141\012\236\088\081\098\137\081\107\208\164\220\229\062\181\102\025\199\142\027\119\208\184\113\199\174\095\063\109\237\090\007\007\119\161\222\218\186\215\203\047\031\189\126\253\146\009\019\118\024\055\078\010\048\129\090\083\000\029\056\123\122\113\195\209\079\005\077\215\246\185\087\003\213\004\181\006\246\091\139\193\049\012\013\038\146\055\202\133\199\207\009\039\156\224\229\072\106\148\159\007\149\106\148\050\071\006\119\051\209\020\032\063\106\208\081\070\195\214\025\177\150\045\176\195\165\161\052\008\185\209\023\036\041\045\092\229\113\097\195\134\013\062\125\097\162\037\053\245\097\196\087\229\084\129\091\056\222\228\029\034\124\026\116\139\164\066\081\127\110\017\232\017\110\249\024\054\105\252\248\089\141\141\051\218\218\198\214\235\029\156\206\127\090\090\091\039\175\095\127\088\115\243\097\099\199\250\117\077\117\230\112\235\166\133\212\186\007\148\093\173\226\109\066\180\179\131\091\060\050\130\170\082\178\241\066\249\042\056\165\230\046\071\056\075\032\134\041\104\251\159\030\123\210\134\084\202\104\219\201\086\212\026\216\239\045\064\095\032\015\166\003\205\070\151\190\113\112\214\200\089\038\005\237\237\237\046\163\045\170\236\121\218\180\027\193\185\234\170\171\068\204\092\032\105\140\042\231\136\243\207\063\255\151\191\252\037\191\152\193\035\150\128\238\160\103\025\237\058\194\001\003\188\015\058\007\113\074\130\000\161\161\024\189\061\233\020\196\162\150\119\218\168\165\121\036\080\236\241\229\194\072\160\094\255\067\168\189\211\205\031\059\118\207\087\094\025\183\102\141\091\129\242\029\191\126\253\222\235\215\047\105\111\223\213\241\173\217\121\174\077\208\184\073\128\254\122\253\085\013\010\134\061\012\176\156\131\152\115\214\183\191\253\109\004\049\168\119\254\153\021\127\017\152\144\075\009\242\243\132\111\013\142\015\010\044\190\164\053\040\075\171\064\167\130\087\215\050\241\143\049\082\175\132\119\088\155\158\160\139\126\105\016\030\176\210\163\065\200\083\032\241\106\078\173\075\152\071\147\109\198\037\121\173\002\135\042\035\168\099\143\116\199\230\107\175\189\214\215\074\027\143\100\238\034\000\029\016\070\024\091\026\027\167\077\152\048\067\047\088\181\170\177\181\021\039\080\014\227\055\110\156\219\218\186\160\177\113\210\184\113\029\063\094\188\122\195\157\154\050\245\195\152\199\032\194\110\180\175\108\194\220\055\178\118\209\162\069\094\197\025\207\017\094\040\095\219\198\206\156\049\099\198\094\123\237\069\038\224\154\013\099\115\218\051\118\163\209\046\162\202\126\214\110\180\006\094\216\171\132\005\138\193\197\005\151\246\131\023\019\191\252\051\195\030\086\247\096\009\246\184\069\027\085\054\012\085\246\054\011\189\129\219\165\148\152\155\017\001\104\211\173\229\229\069\175\049\081\024\129\049\104\014\122\123\119\118\096\067\192\187\227\143\063\222\167\059\233\224\157\145\155\146\104\093\221\097\247\221\119\039\198\078\163\213\157\140\024\096\093\119\093\210\099\045\043\186\219\001\071\161\177\099\023\052\055\031\221\218\058\117\245\234\230\074\252\221\245\099\242\084\013\122\195\134\125\090\090\154\058\255\107\056\152\127\152\235\162\086\211\170\196\048\221\089\251\187\226\138\043\068\076\064\048\221\119\183\042\031\154\071\162\228\046\107\223\254\246\183\031\122\232\161\146\226\212\035\071\028\209\187\245\005\173\156\112\130\067\114\244\097\184\119\007\017\151\000\144\003\181\037\031\018\147\006\161\224\148\157\190\110\068\123\009\084\172\104\079\099\089\052\197\092\064\128\066\004\004\061\128\111\087\056\091\122\122\040\071\151\001\153\016\036\255\064\212\235\147\155\155\231\052\054\238\185\126\253\248\213\171\235\157\031\023\114\215\232\237\087\201\238\191\097\195\190\227\199\055\053\055\227\064\221\063\157\240\084\244\187\137\013\233\121\107\123\171\254\078\118\199\224\061\232\148\083\078\097\042\240\034\046\216\084\234\146\025\251\236\179\015\079\059\228\106\029\031\052\028\248\153\106\003\211\243\210\075\047\121\210\234\014\008\221\193\079\158\078\016\069\210\092\203\081\130\019\079\237\180\139\047\190\216\011\182\014\194\000\069\111\180\049\060\255\237\109\123\082\004\140\084\017\115\200\055\081\156\205\021\004\008\097\196\007\159\036\120\100\105\115\065\204\173\104\009\158\178\138\064\096\255\251\205\207\129\156\107\146\162\155\219\087\060\178\186\023\013\015\097\010\077\036\204\146\244\062\052\179\189\221\048\015\109\105\035\025\031\020\118\155\052\105\097\091\219\193\171\086\141\105\109\045\177\117\055\104\222\184\113\239\053\107\246\171\215\119\113\130\235\100\153\107\098\128\097\045\106\047\189\244\082\239\017\023\094\120\161\115\086\089\066\107\032\016\152\005\161\205\181\255\217\121\210\073\039\105\226\146\037\077\092\040\173\065\053\082\011\101\074\038\142\166\113\004\116\007\225\150\000\144\009\085\043\103\138\076\131\144\042\059\202\035\087\241\041\065\132\018\084\241\187\237\182\155\126\079\216\068\057\054\209\008\008\076\035\126\070\068\001\001\192\039\131\137\046\240\061\092\119\152\215\222\190\087\091\091\083\123\123\151\234\212\044\198\174\090\053\109\253\250\089\205\205\147\243\227\069\123\187\013\077\021\216\060\094\097\188\201\123\128\219\066\069\185\037\024\009\106\142\253\140\231\011\143\248\197\065\091\008\211\214\034\022\240\203\163\207\158\212\029\236\100\251\025\016\054\170\145\140\181\140\237\237\029\111\054\237\157\127\122\004\166\034\198\119\086\114\080\178\255\233\177\049\108\072\004\219\204\181\165\169\210\056\060\252\109\033\194\140\204\092\052\075\200\035\048\109\036\124\179\028\136\116\043\150\128\075\171\233\041\186\021\177\002\103\031\091\139\023\113\141\119\218\183\222\199\036\171\227\163\233\044\242\190\173\120\069\098\103\108\232\224\211\219\249\175\048\076\110\106\154\219\220\188\239\134\013\099\187\181\230\014\177\090\173\113\227\198\113\107\215\206\172\215\029\031\036\203\107\096\248\070\203\001\179\053\050\001\164\156\214\240\141\012\112\183\010\119\009\027\221\085\072\078\013\190\010\033\120\033\059\090\131\195\157\004\137\106\153\075\114\180\098\100\116\007\209\047\041\148\024\233\025\055\110\156\084\121\197\080\118\090\003\040\056\192\087\007\014\129\062\080\123\070\153\040\217\070\064\128\196\131\203\130\104\046\151\238\006\225\152\210\060\110\220\140\113\227\014\093\187\214\009\182\030\238\031\143\099\054\110\156\177\126\253\049\181\218\222\094\125\155\058\126\090\115\159\090\035\085\182\141\211\172\039\191\007\035\014\184\229\091\157\178\219\117\215\093\117\052\224\136\226\003\221\129\217\036\017\188\032\028\216\081\246\143\195\176\253\108\051\131\094\227\004\238\248\227\005\129\066\136\164\081\100\236\061\075\219\219\070\028\211\217\160\067\153\072\030\188\014\008\148\118\067\161\214\160\113\248\193\223\186\244\168\123\132\166\192\119\115\105\040\180\075\076\170\124\201\211\026\076\055\087\127\209\001\041\116\055\208\023\022\047\094\044\029\092\131\226\029\171\164\207\020\028\191\067\055\118\054\083\043\154\149\151\026\205\078\223\113\025\166\223\032\124\202\153\210\220\124\068\075\203\172\141\027\125\098\232\049\254\013\109\109\110\205\217\184\113\094\173\214\228\053\164\243\180\021\013\025\217\044\002\107\215\174\021\016\202\057\008\089\157\119\238\002\151\193\037\001\056\240\192\003\223\250\214\183\122\081\205\103\200\164\038\173\193\068\211\105\006\146\163\024\013\035\200\055\201\144\021\080\097\182\144\070\096\027\168\051\125\093\119\240\016\054\002\166\186\119\020\156\059\119\174\210\212\074\008\155\098\034\103\213\065\042\128\182\042\220\010\220\013\220\085\154\152\219\143\027\055\179\185\121\198\186\117\099\215\175\119\217\029\074\118\151\013\027\022\173\095\191\223\216\177\077\019\038\152\213\081\214\157\114\022\005\139\166\242\104\198\102\140\215\031\239\014\140\087\118\030\170\108\006\029\129\083\074\080\253\145\244\227\069\135\013\038\212\168\172\059\186\251\152\111\051\219\225\070\143\065\028\061\162\086\235\184\091\235\252\051\215\206\244\059\136\023\126\231\044\074\172\219\121\167\102\051\251\221\193\235\189\083\131\157\236\153\111\111\131\088\217\252\126\103\213\122\072\090\209\044\096\182\232\009\146\169\131\166\000\000\016\000\073\068\065\084\163\022\134\230\002\016\000\015\225\027\110\184\129\013\230\050\192\193\193\075\019\126\129\198\055\111\222\060\174\113\138\119\008\035\239\116\007\185\032\198\065\189\079\106\208\086\004\045\067\095\240\138\196\054\151\086\228\149\187\190\025\236\218\216\120\112\091\219\148\214\086\159\024\058\056\221\254\017\255\177\109\109\123\173\095\063\115\195\134\137\205\029\047\119\236\167\004\138\044\133\022\005\132\187\248\008\035\167\000\199\165\136\009\160\231\141\206\149\023\138\061\246\216\195\037\251\025\239\022\129\104\160\025\076\031\221\024\073\221\065\038\164\068\022\065\158\212\153\106\147\057\069\156\006\097\059\129\054\225\169\069\088\227\063\249\228\147\143\061\246\088\047\192\126\090\147\102\211\241\065\053\004\225\160\049\001\129\003\161\189\032\032\166\214\106\190\161\249\026\094\235\060\232\226\116\135\223\056\247\092\181\106\118\083\211\190\147\038\053\118\222\166\170\000\227\015\058\107\053\187\194\097\085\107\080\115\092\008\208\128\230\151\246\225\089\071\140\155\230\130\010\182\027\087\172\088\097\147\059\140\216\219\094\158\189\011\184\085\213\172\041\028\115\204\049\106\090\235\049\010\020\129\140\158\240\249\020\103\174\093\077\015\232\014\182\183\131\131\099\008\073\170\216\156\134\050\117\234\212\227\142\059\206\207\120\032\164\248\016\085\186\137\047\005\222\002\076\033\172\079\177\150\133\046\129\018\237\073\147\226\078\192\041\132\078\097\180\199\120\071\131\148\185\036\079\173\041\136\046\192\239\224\052\053\237\208\214\182\207\239\127\063\102\019\173\185\067\198\063\237\237\045\107\214\236\220\218\186\227\164\073\226\139\017\083\089\245\170\030\172\154\134\083\199\183\028\166\091\140\071\212\058\255\182\223\126\123\231\205\063\249\147\063\249\192\007\062\240\087\127\245\087\026\156\008\048\082\129\177\147\217\114\241\186\106\013\162\050\194\186\003\139\065\130\065\182\228\076\229\121\046\217\249\078\013\090\131\007\157\164\026\213\162\220\075\173\078\033\241\094\131\023\044\088\224\203\179\109\067\158\146\042\148\136\138\129\194\252\003\221\212\052\165\177\113\247\246\118\047\183\229\068\080\196\010\209\212\218\058\105\245\234\131\090\091\053\136\070\143\175\186\231\089\071\045\210\012\172\173\215\059\056\145\103\146\055\011\091\142\253\085\056\056\000\014\215\156\129\237\034\214\106\022\153\133\227\245\196\019\158\095\058\069\057\204\215\235\117\133\078\198\207\031\206\195\196\108\126\151\135\029\118\152\231\051\034\192\247\091\131\215\019\205\069\095\000\173\193\131\154\176\239\154\212\018\163\042\214\138\164\173\098\244\048\103\143\095\031\028\176\009\184\107\004\231\151\155\111\190\217\123\205\202\149\043\181\137\194\103\057\051\120\039\047\124\001\211\141\001\166\203\150\022\027\121\013\155\181\072\242\153\219\101\227\249\124\018\254\110\019\038\028\216\210\178\135\159\042\094\251\119\076\172\222\035\124\122\216\165\086\219\111\252\248\073\226\223\249\114\065\003\116\017\198\001\171\011\163\091\042\199\239\199\058\224\105\167\157\166\169\009\160\203\253\247\223\223\241\065\154\210\193\217\204\206\046\022\154\059\234\049\242\186\131\010\006\251\077\182\236\031\153\211\218\117\001\105\150\078\005\173\059\248\096\174\242\244\008\141\192\045\050\132\149\166\199\169\010\240\045\208\148\146\090\181\130\166\051\064\003\186\227\224\224\037\182\165\101\098\099\227\142\190\071\174\095\111\023\186\181\041\120\251\221\115\221\186\055\180\182\054\251\114\222\249\223\203\162\004\200\091\002\016\192\018\182\121\180\178\205\062\001\149\103\212\005\216\105\023\025\113\136\153\171\059\016\051\043\176\135\253\166\232\021\029\108\236\048\163\153\251\030\245\034\096\162\206\136\201\095\181\078\033\058\146\182\132\045\237\037\066\115\001\013\194\193\129\078\007\001\015\127\203\001\073\170\124\053\016\043\199\013\151\026\132\112\137\155\049\170\034\230\059\197\229\151\095\238\131\171\055\002\098\097\178\214\075\147\078\205\011\030\241\011\016\046\089\018\180\180\116\252\143\098\120\149\096\045\121\115\131\104\064\035\178\080\067\099\227\252\177\099\231\180\180\140\219\176\161\227\236\230\222\038\160\245\142\105\111\159\236\195\100\189\190\083\221\149\115\094\027\037\245\122\199\097\193\036\180\081\004\052\133\208\110\237\180\211\078\158\025\094\034\252\120\228\085\072\097\104\130\234\071\021\009\130\214\032\134\044\079\058\148\156\041\064\207\235\004\035\175\059\072\140\012\129\108\233\014\050\039\127\010\087\046\157\003\229\085\118\117\007\031\252\213\183\209\086\004\157\066\155\048\197\116\059\211\241\219\033\028\173\092\212\010\109\224\018\092\066\007\225\031\221\161\185\121\124\115\243\246\141\141\045\181\090\071\209\213\054\249\231\173\120\183\246\246\061\106\181\142\103\087\253\085\217\122\189\043\193\096\022\050\198\182\129\184\128\040\091\136\059\046\109\114\182\217\231\232\044\089\175\215\109\105\123\114\217\178\101\246\179\195\057\142\091\172\085\196\246\164\135\182\032\216\153\070\074\108\120\199\147\131\014\058\136\000\177\192\116\031\020\233\001\103\007\240\213\032\183\136\217\057\104\079\078\047\098\214\021\079\199\046\177\245\050\034\134\248\238\022\144\183\132\163\135\022\131\233\210\104\183\219\099\182\150\233\060\229\093\136\120\199\042\064\227\051\158\119\044\055\203\092\206\026\209\065\199\049\173\169\169\109\236\216\125\054\110\060\104\245\234\166\077\191\211\069\222\168\148\199\181\182\238\226\247\139\078\225\014\013\181\154\085\036\029\040\183\004\212\058\255\196\234\157\239\124\231\187\223\253\110\125\080\181\112\211\008\234\068\000\057\206\017\182\177\150\023\114\065\003\085\208\057\251\245\050\008\233\136\116\085\158\064\206\212\153\252\201\162\092\218\114\234\210\150\144\099\213\044\217\026\004\232\017\104\123\210\179\066\105\170\105\249\086\196\118\020\097\122\148\014\084\003\081\046\155\060\139\106\181\157\106\181\166\090\237\213\141\094\235\249\207\221\241\235\214\237\189\113\227\062\214\232\252\215\114\162\132\254\234\004\182\205\153\051\071\241\049\155\025\236\207\232\210\070\050\149\047\070\124\251\223\045\146\069\131\125\104\063\251\178\104\079\070\057\205\100\060\000\125\091\225\187\178\086\220\008\179\240\193\062\087\250\196\002\077\193\043\073\094\046\236\121\239\026\249\120\145\187\022\018\150\037\075\150\008\148\089\090\173\145\042\119\215\174\093\235\022\190\152\187\036\105\044\040\151\082\224\117\070\067\225\011\023\128\013\070\222\113\138\107\128\112\215\020\154\129\018\190\064\217\186\104\204\122\083\211\078\227\199\239\211\214\230\068\038\182\056\155\197\152\182\182\073\173\173\099\094\147\179\004\107\141\097\080\203\024\245\224\217\112\234\169\167\202\130\055\032\214\122\137\080\045\202\131\191\028\140\203\092\096\039\179\077\137\146\162\039\218\094\015\099\195\200\117\082\182\064\230\020\159\106\083\118\050\170\058\101\087\142\109\123\251\080\202\245\133\002\151\152\246\143\041\246\158\227\131\018\073\129\150\210\076\064\084\082\007\209\222\062\190\173\109\135\013\027\198\111\216\224\104\176\217\026\109\094\189\122\234\218\181\251\053\055\239\088\121\245\101\036\085\020\002\194\023\016\111\182\206\216\108\072\229\025\193\101\188\224\072\234\146\188\185\054\188\026\053\209\037\103\001\211\037\132\227\164\224\001\168\196\249\165\190\141\233\014\150\240\243\132\231\179\013\064\063\249\224\153\103\158\241\025\146\251\190\068\248\024\233\155\098\248\070\075\251\136\235\140\064\009\085\098\040\146\066\138\239\069\198\168\215\080\104\093\194\204\160\150\109\044\071\227\128\187\086\039\233\086\001\001\098\085\239\208\238\114\083\202\204\042\160\057\192\105\105\108\220\187\165\101\151\230\102\239\023\155\141\124\173\214\209\187\029\049\052\008\154\107\013\013\244\196\042\153\133\090\231\159\002\240\137\225\140\051\206\240\206\229\153\161\041\168\013\076\206\114\089\168\021\143\122\240\164\097\091\140\076\192\163\170\083\199\235\104\024\193\221\065\150\228\012\228\079\065\200\165\162\148\087\005\170\160\213\168\202\086\223\018\175\035\168\131\000\141\233\174\244\123\144\146\084\241\102\209\166\158\232\161\016\157\177\086\175\143\173\215\199\213\106\099\219\187\254\075\080\100\186\099\076\107\235\148\141\027\125\152\244\035\092\245\046\109\148\135\227\076\171\034\089\107\045\150\187\101\068\103\255\224\051\140\035\008\124\119\217\031\243\076\119\105\132\066\104\001\094\152\061\003\057\171\190\065\137\243\142\095\102\081\171\011\104\070\086\052\043\112\244\184\253\246\219\125\080\124\240\193\007\253\054\089\118\014\003\244\017\209\176\034\136\082\180\233\062\246\048\123\156\053\048\129\030\238\176\001\016\046\003\026\108\045\180\117\117\004\035\001\094\160\193\093\160\135\131\070\098\218\019\205\136\128\112\136\140\019\235\245\189\107\181\157\215\175\175\065\123\094\020\114\103\147\163\150\224\147\134\021\117\135\142\207\070\157\179\088\008\148\091\235\232\163\143\246\099\004\191\020\131\152\164\047\240\072\244\244\005\158\042\158\004\159\169\236\167\202\068\216\228\146\163\250\198\200\238\014\082\035\115\032\139\114\041\163\202\078\118\109\012\101\106\135\072\185\221\034\253\160\226\181\006\064\184\196\055\069\131\064\123\146\040\157\212\016\157\085\120\179\104\169\213\122\255\030\089\123\237\175\177\086\219\190\173\109\239\246\246\157\235\117\157\229\053\054\178\142\174\215\235\054\134\138\100\027\059\217\012\152\110\033\024\099\011\225\147\049\242\005\211\121\094\189\050\149\012\068\024\081\192\120\047\002\190\164\144\001\125\001\120\205\119\065\016\010\175\081\046\125\108\043\083\232\244\245\225\234\171\175\246\253\194\027\074\225\219\033\071\028\113\132\131\055\130\170\032\218\024\076\149\239\136\062\076\216\084\204\043\179\074\115\193\033\195\030\246\199\120\214\022\196\059\124\115\001\193\059\071\027\124\050\230\006\152\165\034\199\055\052\076\169\215\039\105\013\144\219\155\027\157\239\094\237\014\141\082\081\243\089\146\121\210\106\158\048\242\110\209\162\069\041\128\140\218\004\055\197\071\184\248\168\213\050\030\036\130\097\140\097\027\152\254\250\068\201\197\008\118\095\254\064\046\065\082\085\158\004\171\084\219\067\077\072\188\103\130\034\080\244\106\087\107\000\101\225\050\101\161\122\060\051\093\010\129\234\055\210\134\137\128\134\122\221\121\181\214\214\086\239\124\016\225\244\014\159\214\183\095\183\110\060\161\166\038\093\129\158\082\160\108\099\009\195\016\096\021\082\001\026\048\065\105\006\220\049\157\000\023\140\224\146\088\008\035\120\006\058\056\112\135\102\098\129\066\007\253\078\028\076\209\014\184\079\056\115\141\030\218\118\038\096\090\197\008\084\057\056\144\020\150\128\078\160\083\024\005\147\054\190\016\208\050\200\163\041\071\024\209\008\219\094\132\077\145\002\151\005\086\180\010\196\175\140\046\051\203\037\001\194\244\032\252\198\032\110\128\104\110\106\178\225\251\024\121\026\180\132\230\246\118\074\058\206\014\117\243\252\048\170\069\116\156\059\132\200\193\065\027\213\023\024\233\146\023\220\020\040\222\233\011\242\194\065\150\075\001\080\018\080\251\186\197\104\232\014\146\151\068\042\056\144\090\080\115\138\085\190\037\094\250\021\129\106\080\217\186\128\202\080\031\104\028\165\175\035\248\218\231\189\157\140\122\085\163\020\006\158\248\002\164\064\059\142\169\097\109\110\108\246\114\177\110\221\014\190\059\076\116\052\166\160\163\206\153\103\158\209\018\030\206\172\178\016\088\026\066\024\033\171\147\012\188\023\176\141\205\166\067\152\136\064\065\051\219\097\196\134\180\123\181\131\128\191\128\038\096\138\055\002\002\056\104\019\045\081\022\202\165\017\180\200\089\179\102\217\048\036\205\053\022\048\027\135\054\098\034\102\131\033\128\170\050\034\008\232\188\036\163\159\107\128\014\008\144\103\003\072\147\075\174\089\066\154\112\092\254\017\234\117\173\097\066\115\243\152\122\189\169\086\235\136\099\173\079\127\085\201\066\219\243\078\079\222\233\164\094\210\065\064\056\037\104\202\067\058\216\160\102\088\021\176\007\250\180\222\168\022\082\252\163\202\063\073\133\228\088\190\245\008\149\033\253\138\064\213\042\008\213\175\056\160\116\007\037\226\204\172\172\109\143\196\034\069\028\218\232\025\100\236\035\180\146\237\055\110\156\220\210\082\159\216\241\191\007\099\022\099\152\132\000\187\221\115\219\195\220\138\206\252\136\078\172\069\219\042\016\129\108\039\102\152\066\222\037\002\138\030\052\104\052\062\172\042\116\222\217\153\220\052\130\075\224\023\090\221\211\224\150\055\002\209\048\139\090\038\161\033\151\212\138\146\214\032\008\182\171\089\065\148\136\027\085\070\151\066\074\184\116\043\170\104\040\096\167\118\192\005\142\240\139\083\016\002\007\237\022\016\003\115\169\098\152\177\104\192\132\092\250\226\179\189\143\062\245\186\144\134\211\151\177\173\094\239\104\229\237\127\248\047\194\153\197\041\039\044\222\201\187\112\185\228\017\031\173\046\008\156\002\049\129\122\189\180\020\243\094\239\024\109\221\161\228\179\254\218\159\148\203\189\077\162\020\212\132\202\080\031\233\017\070\116\234\094\149\216\108\101\186\089\104\071\082\232\248\255\182\113\209\055\116\124\024\107\107\107\108\104\232\248\175\003\213\059\074\173\222\249\071\161\093\234\247\130\235\175\191\254\222\123\239\245\057\208\059\191\167\122\070\004\248\093\064\215\112\224\183\163\108\039\006\219\180\166\060\240\192\003\089\220\222\179\121\232\203\229\062\157\127\156\226\029\112\001\204\002\165\015\008\026\184\079\222\003\063\068\052\024\003\183\216\102\231\120\186\022\085\102\005\052\208\019\160\105\176\201\137\153\021\152\011\049\137\047\126\034\245\035\200\203\047\191\204\023\030\225\024\209\080\092\163\065\143\224\139\224\099\186\212\044\104\163\007\225\077\000\013\099\107\181\237\090\091\199\010\166\139\190\065\178\090\235\175\117\135\206\041\124\244\159\206\059\126\042\210\212\100\159\241\220\225\139\088\113\007\234\175\253\145\252\047\084\035\048\106\187\067\156\148\119\053\023\040\119\053\225\001\168\029\056\068\168\024\213\105\068\043\023\069\140\175\122\050\049\085\133\110\173\213\160\227\061\214\069\031\224\160\225\237\087\107\176\104\196\169\082\244\161\109\251\107\175\189\246\203\095\254\242\133\023\094\120\217\101\151\221\124\243\205\015\062\248\160\223\023\181\128\023\094\120\225\197\023\095\244\149\244\249\231\159\247\179\130\238\128\182\217\180\134\252\203\136\052\208\003\020\162\193\211\094\071\227\020\055\093\026\003\021\207\217\192\030\096\009\239\188\076\233\032\196\010\232\001\151\100\124\218\116\184\048\145\048\078\128\006\119\169\050\130\203\151\094\122\201\006\067\071\134\006\176\174\075\091\221\151\206\075\046\185\228\170\171\174\226\218\221\119\223\237\023\211\167\159\126\090\191\120\225\133\023\184\163\107\176\132\006\158\026\221\122\232\161\135\052\077\211\129\134\087\081\239\232\170\013\109\109\099\218\219\183\232\181\066\107\216\080\171\233\017\190\019\081\213\065\248\143\090\077\090\185\111\148\125\225\018\007\142\196\217\122\231\095\167\212\127\013\093\035\048\202\187\067\220\085\000\170\001\084\185\226\080\034\105\004\250\130\138\065\235\014\041\113\239\165\169\123\151\153\219\218\222\190\177\094\175\005\097\109\110\244\089\172\212\037\089\170\108\105\068\189\094\055\218\018\215\093\119\221\231\063\255\249\207\125\238\115\054\210\077\055\221\244\203\095\254\114\197\138\021\143\062\250\168\054\241\100\231\223\195\015\063\076\230\226\139\047\190\227\142\059\236\043\179\234\175\253\209\006\225\056\251\040\116\151\054\152\167\049\032\060\147\045\135\249\218\140\142\069\117\037\155\129\251\038\130\187\005\046\069\198\059\057\199\205\165\036\160\010\112\104\035\083\180\153\072\143\117\049\209\001\154\000\073\063\148\126\241\139\095\060\251\236\179\207\063\255\252\043\175\188\210\143\035\203\151\047\255\213\175\126\245\216\099\143\241\076\155\224\254\019\079\060\129\195\181\159\254\244\167\060\165\193\092\160\164\011\218\178\213\187\112\055\125\185\161\094\095\091\175\111\244\090\209\102\170\055\140\087\243\032\080\114\205\065\150\027\249\011\061\174\184\105\221\175\199\059\175\139\238\032\177\074\065\065\128\226\080\034\218\129\007\160\190\144\238\160\095\232\026\077\077\077\062\070\164\238\077\233\064\123\123\091\123\187\154\243\114\241\106\161\117\112\123\251\071\107\112\214\104\109\111\135\200\217\051\136\246\246\118\004\051\208\096\215\121\174\094\115\205\053\095\255\250\215\063\243\153\207\124\250\211\159\254\236\103\063\107\095\157\119\222\121\023\093\116\145\243\133\035\131\087\012\146\005\140\135\162\129\035\020\058\150\003\073\071\119\240\244\070\235\005\142\030\054\185\085\218\109\021\123\140\061\173\158\172\029\157\130\066\019\003\116\224\169\110\034\013\070\074\016\128\160\138\126\218\116\138\168\114\062\207\148\140\244\132\207\048\192\180\174\163\208\045\183\220\162\187\105\130\092\251\204\103\062\115\206\057\231\124\233\075\095\226\157\067\147\174\225\088\241\252\243\207\211\073\222\044\026\002\151\029\232\220\219\029\029\153\229\029\215\125\250\071\130\090\027\026\214\053\097\066\088\247\000\000\016\000\073\068\065\084\054\182\154\222\230\251\195\171\206\154\236\224\032\221\022\018\052\093\018\001\248\255\133\222\035\240\122\233\014\137\130\154\080\028\186\003\104\007\233\017\234\070\119\064\187\229\116\237\146\048\073\035\056\169\174\173\213\054\054\116\254\159\101\186\222\028\180\134\085\013\013\107\054\108\104\093\183\206\195\043\226\180\065\161\067\216\117\158\165\078\013\119\222\121\231\173\183\222\234\016\097\071\253\252\231\063\247\176\245\042\097\103\070\204\068\008\093\029\109\039\146\247\221\119\095\142\030\030\206\142\030\038\210\233\012\239\133\159\006\075\104\016\156\213\242\236\088\091\189\170\161\208\246\179\039\249\013\055\220\112\219\109\183\209\233\117\070\231\242\101\132\042\175\000\026\007\085\230\090\081\112\140\030\248\212\118\177\202\101\064\173\109\239\197\129\134\251\238\187\207\187\006\215\040\055\230\223\194\098\039\157\100\072\154\082\070\068\119\252\097\139\119\191\215\141\179\161\177\113\109\083\147\020\136\124\052\019\065\120\005\155\054\109\154\140\167\189\226\224\255\023\054\027\129\215\081\119\080\019\129\046\144\013\163\035\128\214\000\074\071\197\251\012\225\064\033\106\036\141\176\174\189\125\077\173\006\030\077\046\055\011\143\175\223\053\055\191\178\126\125\251\170\085\237\157\207\109\170\186\020\037\014\027\000\209\139\066\119\129\018\032\102\004\004\166\209\238\186\241\198\027\191\255\253\239\255\228\039\063\177\003\181\152\123\238\185\039\123\219\246\211\011\244\008\207\127\239\249\158\210\248\030\215\104\019\187\131\042\251\246\220\115\207\245\132\255\206\119\190\227\165\230\103\063\251\153\119\132\149\043\087\230\117\128\006\013\194\104\183\095\113\197\021\238\154\194\012\160\141\085\128\008\056\203\053\079\233\220\013\179\058\226\003\177\034\227\018\170\050\161\197\028\066\111\118\036\185\190\161\225\119\026\068\253\143\090\138\142\230\131\171\095\043\036\157\097\245\250\031\221\221\172\218\215\179\192\235\168\059\072\115\189\094\087\148\074\068\093\122\156\254\111\246\238\253\201\170\042\187\003\248\057\125\111\191\104\129\030\203\007\076\065\137\060\148\022\069\068\005\005\196\007\148\010\034\242\080\249\197\242\015\115\162\149\050\101\076\242\067\204\099\028\051\073\106\202\202\140\085\038\153\212\024\227\084\057\051\198\113\036\042\130\052\077\063\239\243\220\124\238\093\221\135\075\055\253\000\157\169\025\250\118\125\123\247\058\123\175\189\206\222\107\175\245\061\251\236\035\051\024\033\103\007\130\077\178\250\096\007\050\125\168\036\201\072\154\142\038\137\247\139\100\009\063\181\066\097\164\167\103\172\086\075\038\039\243\039\088\036\143\187\067\098\183\236\122\006\106\064\101\128\012\033\043\201\064\008\117\130\241\071\141\082\186\218\107\188\243\206\059\111\190\249\166\147\078\120\229\149\087\148\242\252\141\055\222\176\177\127\251\237\183\189\164\072\102\059\020\212\192\008\011\058\050\002\004\151\057\108\055\108\010\028\040\234\203\002\059\175\190\250\234\107\175\189\230\146\041\103\168\088\195\215\022\187\137\188\011\011\224\146\229\118\240\030\170\213\228\046\064\033\135\074\112\073\159\014\129\130\154\040\009\121\238\150\187\186\038\187\187\189\014\209\089\020\168\193\002\141\166\233\111\011\133\225\150\054\251\254\090\101\159\099\172\041\193\226\230\119\209\212\193\162\030\088\094\236\192\029\226\079\136\228\004\129\020\108\028\148\160\213\035\113\237\218\181\030\050\017\091\210\091\004\015\055\026\103\211\180\146\166\205\147\046\074\243\067\140\142\023\010\159\247\246\126\099\215\128\032\146\196\237\128\017\144\051\016\150\009\144\204\048\005\033\160\021\114\153\078\251\037\025\180\154\066\152\181\069\183\083\112\072\241\193\007\031\120\047\240\165\192\030\030\008\182\003\146\217\107\130\125\068\188\023\232\056\031\088\211\228\077\132\178\239\008\058\234\110\111\018\166\188\119\120\127\057\125\250\180\205\008\053\119\143\097\144\163\035\033\031\170\166\128\154\128\214\028\154\084\042\003\100\158\225\118\096\010\114\205\114\154\142\057\071\072\211\230\155\066\094\059\191\224\157\194\074\125\060\057\121\177\237\191\188\182\184\219\182\109\115\238\128\026\044\122\187\253\249\045\117\090\166\061\176\236\216\033\230\045\190\133\011\022\200\183\015\216\001\196\168\072\242\229\034\212\154\031\198\042\149\209\122\125\024\059\020\139\139\178\131\175\027\195\133\194\111\210\244\092\218\122\004\226\136\100\154\032\146\239\226\071\070\073\039\150\210\180\105\063\077\167\203\052\109\010\234\231\034\077\083\051\053\095\002\080\008\035\236\016\092\066\212\211\105\207\031\149\001\010\057\212\080\211\113\110\247\092\231\218\004\102\065\095\012\171\132\090\150\149\106\181\106\163\225\128\209\229\194\112\024\092\234\235\187\144\036\231\070\070\106\045\118\104\180\156\239\212\121\104\104\200\154\206\114\194\194\214\058\173\225\129\229\200\014\066\092\026\008\023\187\077\064\010\158\048\064\224\020\175\169\235\214\173\035\076\163\086\027\206\178\179\093\093\073\161\144\042\167\107\175\252\103\114\197\138\175\122\123\063\042\151\191\158\249\159\057\139\024\101\115\251\246\237\207\062\251\236\243\207\063\127\234\212\169\023\095\124\241\133\023\094\080\206\133\122\058\039\078\156\056\126\252\248\177\099\199\158\123\238\185\103\158\121\230\161\135\030\114\092\106\168\113\087\153\233\121\027\114\094\154\084\142\188\050\132\024\003\057\023\200\237\080\015\204\002\129\029\137\170\132\080\035\168\129\252\146\064\147\062\016\092\154\163\195\191\003\007\014\024\179\121\157\058\117\074\009\167\090\063\004\083\003\179\059\121\242\100\062\193\163\071\143\114\139\242\254\251\239\183\040\097\138\053\187\054\150\171\216\218\159\230\245\034\191\056\165\212\223\127\174\183\119\140\231\179\075\052\190\122\245\234\059\239\188\211\113\018\227\198\111\034\139\024\234\052\183\121\224\143\130\029\218\198\243\123\023\197\007\008\020\236\000\082\206\246\001\053\000\118\176\155\144\120\206\183\005\211\244\080\026\141\051\089\246\127\073\098\227\154\021\010\211\149\243\252\169\246\245\125\217\211\243\219\082\201\169\036\021\055\018\238\238\229\043\160\232\223\186\117\235\250\245\235\189\185\040\157\147\041\103\001\043\185\053\224\002\106\094\152\237\098\244\141\172\219\191\127\255\150\045\091\052\137\117\035\151\053\140\187\139\114\022\084\230\208\100\070\185\114\212\027\152\009\006\012\207\101\212\083\038\040\233\007\200\237\053\046\163\094\037\240\152\017\222\126\251\237\015\063\252\240\147\079\062\249\192\003\015\108\220\184\113\195\134\013\038\002\102\103\154\004\032\007\200\038\184\102\205\026\207\115\039\133\158\237\252\207\148\249\186\052\036\114\140\039\171\213\154\123\135\036\185\148\235\218\174\004\212\224\067\230\103\189\189\191\046\020\202\245\122\115\199\055\163\230\046\110\103\156\060\022\051\013\227\051\237\157\191\011\121\096\217\177\003\103\136\015\016\043\184\000\059\008\029\212\000\004\151\222\189\133\236\202\149\043\105\006\206\212\235\167\179\108\184\171\203\139\067\212\204\087\054\186\186\188\042\079\120\118\181\182\181\238\066\083\092\122\130\137\126\161\239\120\076\110\179\191\000\060\132\169\025\143\180\209\151\017\233\173\140\036\196\017\247\221\119\159\156\100\249\026\096\202\006\160\251\173\183\222\106\072\064\184\241\198\027\205\253\106\173\025\228\230\205\155\031\121\228\145\035\071\142\160\134\029\059\118\224\002\150\217\207\103\071\039\151\185\052\100\019\116\059\083\115\199\074\165\226\044\195\231\021\187\004\105\108\202\042\077\214\222\161\158\101\165\044\171\020\010\222\044\228\191\250\249\224\059\209\068\119\247\071\089\246\049\043\216\097\070\143\195\177\131\049\088\086\178\021\159\105\233\252\093\146\007\150\035\059\112\140\248\019\046\032\110\068\164\096\021\178\145\144\082\081\189\231\118\132\047\205\250\228\228\167\229\242\047\006\006\046\244\245\233\187\000\124\224\152\072\146\201\057\026\236\123\048\074\069\009\016\143\208\249\074\009\006\030\176\001\059\005\048\024\195\243\220\054\036\068\035\039\031\125\244\209\019\039\078\060\254\248\227\182\036\187\118\237\242\218\130\059\060\180\111\155\249\025\026\026\122\112\230\103\239\222\189\052\015\029\058\164\139\029\062\180\111\239\143\183\126\078\158\060\105\135\079\109\207\158\061\059\119\238\188\235\174\187\236\002\140\193\221\013\091\105\192\042\189\227\184\221\254\253\251\189\011\188\252\242\203\094\034\144\002\005\140\096\130\244\221\159\230\194\160\198\032\086\066\037\122\161\012\254\145\186\156\035\147\057\207\076\149\014\035\203\073\226\027\080\163\176\200\150\205\158\110\170\175\239\179\052\253\020\053\160\102\157\091\176\237\226\007\165\085\102\223\082\066\171\165\083\044\201\003\203\145\029\132\008\008\023\201\230\089\042\116\068\039\106\008\168\068\016\194\055\034\181\233\197\169\169\047\038\039\223\239\233\249\093\079\143\144\157\239\057\102\003\092\105\052\166\026\013\028\017\241\221\236\219\250\117\023\249\035\139\036\000\072\143\249\016\173\178\171\093\193\096\192\099\016\053\024\054\227\158\195\106\188\104\120\233\128\221\187\119\031\062\124\216\003\252\224\193\131\074\068\224\145\126\247\221\119\123\151\145\210\014\237\065\158\108\218\180\137\101\057\041\033\077\179\053\052\199\041\005\212\099\251\128\149\040\032\005\092\195\206\083\079\061\229\016\001\158\120\162\249\255\106\241\244\211\079\239\219\183\239\158\123\238\065\007\232\003\220\029\109\073\114\035\001\035\103\092\217\062\242\185\050\005\202\092\225\229\194\072\220\215\092\184\218\120\184\136\096\084\038\168\228\198\177\052\245\066\215\040\022\093\046\128\090\177\120\166\175\239\243\070\099\184\117\030\153\107\154\139\233\155\029\186\231\055\139\158\055\117\132\165\120\224\050\118\088\074\135\235\067\071\160\128\160\145\183\057\059\008\035\052\001\230\056\043\082\039\107\181\095\149\074\103\036\127\177\232\120\156\194\044\160\012\245\062\209\151\124\221\152\105\139\040\119\023\054\025\140\092\146\078\011\064\206\004\228\143\044\146\075\144\231\024\057\016\207\067\102\007\007\007\101\020\065\194\123\014\099\144\000\025\226\070\106\232\099\022\099\144\138\074\189\212\068\114\170\015\011\246\080\248\145\002\063\024\051\065\119\099\144\243\136\195\024\098\252\100\053\006\169\123\012\146\014\144\085\130\094\011\131\029\067\210\029\053\184\187\241\184\047\118\000\107\049\227\188\164\146\101\190\065\076\160\006\072\231\253\040\067\127\188\088\252\188\187\251\203\122\189\090\246\025\244\146\166\161\186\023\179\166\019\236\144\166\151\090\117\236\096\097\015\044\083\118\224\148\052\245\009\162\075\220\136\200\072\012\089\001\050\205\222\065\212\218\036\083\011\076\214\235\191\174\086\127\215\221\093\094\177\002\011\068\229\172\018\065\212\236\132\211\052\107\029\058\104\013\118\016\151\210\079\066\074\087\249\032\045\023\133\204\145\063\032\205\228\155\220\011\082\144\162\050\019\066\080\026\036\208\145\099\198\236\046\074\178\142\094\052\192\027\007\005\121\002\132\188\047\033\007\227\076\069\073\141\096\132\216\129\029\008\155\074\195\096\144\145\208\065\007\224\214\238\101\168\096\216\160\239\162\224\007\006\013\213\093\194\231\022\034\192\111\129\082\163\113\174\209\184\104\153\010\133\005\114\186\158\166\095\247\244\252\188\088\060\093\042\101\149\138\101\141\238\214\212\038\200\168\060\000\044\001\228\077\161\208\041\023\245\192\050\101\007\129\002\194\209\131\069\244\136\036\143\047\097\026\016\073\147\147\147\146\065\236\082\227\068\007\245\195\229\178\035\241\211\003\003\021\143\050\085\087\066\029\031\160\006\104\107\117\023\236\224\070\172\129\124\187\034\242\038\057\003\146\039\103\019\041\231\025\040\015\013\073\066\202\094\137\045\159\101\233\044\168\143\026\002\133\040\009\160\151\238\202\064\187\076\045\016\153\031\022\218\101\053\044\004\116\055\006\131\009\082\064\004\145\234\006\108\216\249\212\242\233\228\053\033\228\245\004\251\029\158\225\121\254\231\031\174\230\249\220\115\053\236\080\173\094\168\213\056\031\243\230\245\237\130\003\203\177\190\190\095\246\244\252\172\094\063\095\042\037\117\092\209\100\018\006\189\004\249\150\233\046\214\215\018\048\222\222\177\035\047\197\003\203\148\029\184\070\184\128\184\017\061\182\015\182\012\194\084\176\034\008\130\052\039\200\016\058\148\029\161\087\039\039\063\206\178\015\187\187\167\010\133\043\006\171\074\187\134\134\083\049\104\035\008\022\122\123\123\209\013\179\011\192\237\114\024\006\136\108\025\037\235\218\105\034\210\082\126\074\239\128\116\109\135\202\104\085\082\006\105\140\092\162\036\004\092\130\086\160\009\058\066\110\042\151\009\090\129\166\046\158\198\128\020\140\202\216\048\130\113\130\001\027\127\148\004\184\226\100\103\213\115\059\231\240\063\118\064\013\150\163\233\237\214\047\079\094\172\213\038\125\213\168\086\057\182\085\055\187\168\166\233\023\171\086\253\162\080\248\240\226\069\251\059\209\140\074\040\025\161\179\088\165\197\101\153\089\171\000\154\254\228\241\007\156\000\127\254\001\239\246\071\118\043\225\034\110\004\144\000\021\166\162\089\236\138\111\130\074\193\106\091\174\108\142\058\203\026\213\234\071\083\083\255\092\171\253\166\191\127\170\167\167\089\057\231\215\155\133\099\203\168\110\062\194\090\082\220\002\221\008\083\102\149\011\128\002\200\150\246\033\121\198\230\052\033\039\109\037\036\167\208\007\169\030\101\008\237\050\181\000\101\240\132\159\011\245\001\154\250\006\152\002\068\160\204\161\137\102\088\064\010\198\147\051\002\119\241\158\049\131\193\195\124\019\212\020\058\074\112\025\224\034\126\086\003\045\159\181\138\044\043\085\171\227\141\198\104\154\054\210\220\157\173\166\086\081\239\234\026\239\235\251\089\095\223\187\089\054\054\054\150\213\106\008\154\159\053\034\050\095\108\012\152\125\150\033\077\175\096\129\102\007\011\120\096\249\178\067\218\250\017\055\066\083\012\201\070\081\142\029\000\065\008\247\114\185\044\013\060\027\041\134\007\207\077\076\188\055\062\254\126\127\255\217\129\001\123\218\168\204\075\161\153\117\117\053\235\219\054\014\090\117\015\203\110\228\118\139\034\212\148\080\044\022\037\140\193\132\005\052\033\039\101\166\081\025\027\166\128\200\216\188\084\003\090\129\090\040\043\003\186\007\242\075\058\064\025\116\012\176\070\136\146\160\009\168\233\165\059\023\129\033\025\024\215\025\164\161\194\162\083\227\010\200\053\009\057\056\042\203\050\166\040\144\155\200\178\180\090\029\043\020\190\233\235\187\034\059\076\118\119\127\050\048\240\110\189\142\181\189\083\216\223\089\002\029\013\195\166\207\187\146\117\100\016\046\217\212\220\193\146\061\176\124\217\129\139\004\013\008\080\033\030\236\032\158\064\232\131\179\073\113\102\167\045\188\040\083\075\106\181\111\042\149\031\167\233\135\189\189\227\253\253\077\034\208\048\003\161\233\173\183\025\199\216\033\203\092\070\011\227\018\140\065\247\130\168\092\184\164\006\238\014\238\011\198\144\211\132\180\052\072\064\022\032\093\115\184\084\223\014\247\165\031\144\204\033\040\067\214\010\244\163\036\048\181\106\213\170\246\146\077\008\133\232\168\175\073\025\082\012\207\080\115\044\058\175\092\065\023\221\129\000\158\249\163\163\163\089\150\177\060\173\147\101\028\126\177\175\239\194\138\021\182\009\211\149\109\127\190\238\239\255\183\021\043\254\199\059\219\248\184\141\065\161\107\058\152\013\213\183\204\213\171\087\199\056\243\091\180\117\237\136\075\242\192\180\067\151\164\123\061\042\009\029\185\039\034\065\048\009\044\025\002\210\064\054\214\106\181\205\155\055\219\084\079\079\189\209\152\040\151\223\155\152\248\167\098\241\087\171\087\079\245\246\230\239\017\077\046\104\253\107\194\140\170\176\086\206\128\029\015\097\054\229\192\076\221\082\255\234\002\006\009\198\009\114\210\080\217\004\140\102\204\115\161\094\043\132\166\082\175\000\011\001\151\004\165\086\208\005\114\083\166\031\136\026\077\097\141\166\094\001\067\002\195\131\165\206\039\073\040\207\066\024\193\014\241\111\204\221\043\137\031\036\091\171\125\085\044\158\241\030\151\074\255\168\109\150\088\120\228\134\027\126\218\223\255\086\181\250\191\019\019\073\181\026\118\155\109\073\178\123\247\110\175\021\028\030\163\013\251\209\244\093\150\203\192\214\178\102\135\180\245\035\122\132\187\232\023\151\082\162\157\032\108\031\004\153\099\057\145\224\177\038\066\005\241\232\197\139\239\086\171\063\236\239\183\173\045\117\119\107\010\216\053\056\036\171\138\105\072\018\202\204\039\073\034\070\061\141\025\119\025\080\121\181\136\142\202\024\173\001\075\108\229\124\200\091\233\007\244\157\133\168\087\206\103\164\189\062\012\082\134\176\115\181\083\104\215\207\045\132\160\228\088\222\102\156\187\114\077\156\251\069\189\126\166\117\160\208\094\057\210\215\247\095\055\222\248\175\105\250\254\240\176\179\137\104\138\147\075\203\247\196\019\079\056\048\226\112\166\076\129\241\080\232\148\087\235\129\174\171\237\112\253\233\139\030\049\036\146\196\147\071\165\240\194\008\246\210\074\193\090\042\149\156\204\169\055\113\193\170\076\178\236\211\209\209\191\159\152\248\199\027\110\248\001\106\096\036\000\000\006\098\073\068\065\084\108\112\112\178\245\129\147\031\211\174\174\041\072\146\070\125\250\031\002\137\120\250\140\051\197\184\027\129\154\239\010\172\205\135\107\184\197\124\166\162\254\026\012\206\215\133\065\077\202\089\224\040\171\192\231\090\003\028\254\197\196\196\215\147\147\085\220\028\085\073\050\054\048\240\203\193\193\191\074\146\119\075\165\070\165\130\133\163\011\118\176\076\059\118\236\216\182\109\155\215\010\014\103\016\226\046\051\189\059\127\175\194\003\162\250\042\180\175\063\213\008\029\049\004\182\015\194\043\216\065\062\019\068\024\118\016\106\027\054\108\160\096\250\002\177\043\077\203\083\083\255\061\050\242\086\173\246\086\127\255\135\223\251\222\249\129\129\230\063\022\074\146\106\177\088\042\020\226\132\140\114\192\083\215\222\129\113\247\138\154\078\153\187\130\000\028\162\228\097\094\226\097\151\057\070\075\165\097\231\195\197\098\197\139\091\161\112\110\096\224\223\111\184\225\111\010\133\191\027\031\255\114\124\060\109\052\010\093\022\196\223\134\083\073\135\068\135\014\029\178\215\179\142\136\134\231\217\097\089\217\193\053\120\096\185\179\003\151\069\244\136\036\241\132\014\250\251\251\081\131\189\003\032\008\113\166\201\078\085\224\134\114\087\161\032\030\147\074\229\131\243\231\095\175\213\222\092\189\250\063\007\007\071\251\251\157\156\149\011\133\082\215\204\255\062\109\234\169\166\071\243\205\130\205\066\161\144\166\211\053\205\218\101\255\155\094\254\195\031\042\120\169\171\235\242\152\204\050\094\189\048\048\080\238\233\185\208\219\251\222\077\055\253\121\111\239\235\227\227\195\023\047\090\002\250\169\239\157\173\087\057\022\134\134\134\236\029\086\174\092\105\177\172\166\214\217\214\040\117\176\100\015\092\190\018\075\238\118\157\041\138\033\145\036\158\068\149\076\070\010\065\016\074\151\149\074\197\151\115\052\097\214\118\184\130\152\126\083\046\151\063\025\030\254\225\240\240\015\042\149\215\087\173\250\241\173\183\126\212\211\243\117\173\249\223\246\105\165\166\004\102\145\014\138\201\107\084\046\103\240\195\044\240\167\026\037\016\046\115\078\189\126\182\167\231\063\110\190\249\167\223\255\254\095\174\090\245\131\114\249\039\035\035\099\227\227\089\189\222\228\232\196\123\094\230\071\023\027\135\061\123\246\216\056\088\062\235\104\065\153\010\104\237\224\026\060\208\097\135\036\002\072\041\158\034\147\133\023\094\176\119\000\066\181\234\168\177\177\101\203\022\076\225\040\161\025\139\105\042\052\155\219\217\082\233\211\225\225\191\029\031\255\179\070\227\245\066\225\039\083\083\159\143\141\121\091\102\045\022\067\184\019\124\116\083\147\067\077\007\060\144\059\132\016\151\150\032\060\022\151\074\217\255\105\150\253\067\154\254\117\119\247\095\052\026\063\026\025\057\051\058\234\075\103\129\094\161\048\189\028\073\226\221\237\216\177\099\187\118\237\178\113\192\197\214\177\221\084\211\078\231\247\234\061\208\097\135\105\159\009\080\241\228\153\035\182\176\000\094\000\161\134\029\000\065\056\122\240\116\162\141\029\064\092\022\138\069\093\146\052\077\074\165\079\206\158\253\151\047\191\252\249\087\095\157\023\187\169\003\202\046\010\148\237\056\028\197\015\015\015\167\051\063\042\151\051\184\193\244\149\179\032\217\213\240\167\146\002\016\154\104\052\078\143\142\254\232\244\233\183\078\159\254\240\252\249\164\092\214\068\153\243\181\114\050\168\241\225\249\177\199\030\187\229\150\091\172\157\069\100\135\014\005\208\218\193\181\121\160\195\014\077\191\137\033\193\004\162\202\099\071\074\011\178\096\007\004\065\104\042\037\201\109\183\221\070\071\056\130\046\074\245\054\017\206\195\170\245\250\084\185\092\169\250\091\015\238\136\086\214\236\068\244\162\015\244\175\091\044\121\098\252\016\224\150\000\183\171\033\115\151\087\176\118\075\142\106\106\213\234\132\159\169\169\074\173\198\213\090\195\183\074\174\118\137\184\143\030\061\138\187\173\026\114\015\035\172\105\234\224\219\120\160\195\014\151\188\039\064\133\169\039\143\008\147\210\120\193\126\213\007\011\165\203\241\241\113\167\015\142\039\133\175\184\212\077\025\093\148\046\115\168\143\168\085\195\218\205\055\223\204\194\044\029\077\203\025\188\145\131\207\201\081\114\151\220\014\207\112\099\083\176\017\075\081\068\083\244\043\231\033\245\253\194\150\204\151\227\214\059\197\225\195\135\247\238\221\203\201\216\129\005\011\068\033\160\075\007\215\236\129\014\059\076\187\046\130\073\140\130\008\019\103\024\001\065\096\007\016\121\032\112\125\075\199\029\250\200\127\093\034\082\149\106\174\008\166\006\007\007\089\163\067\031\174\168\182\172\042\057\033\007\111\243\076\148\042\037\054\057\188\129\029\002\046\053\041\003\020\128\255\181\234\235\172\097\223\190\125\055\221\116\147\023\064\075\019\022\212\135\114\167\252\054\030\232\176\195\037\239\009\065\016\094\082\218\203\133\104\011\118\144\222\128\029\060\174\132\221\206\157\059\215\172\089\163\155\075\165\024\085\234\168\156\139\117\235\214\221\123\239\189\131\131\131\020\096\174\194\178\173\225\073\073\030\037\159\147\249\179\245\095\054\020\231\243\009\007\130\214\160\006\092\224\035\197\241\227\199\055\110\220\104\177\080\176\026\166\216\164\006\052\059\248\054\030\232\176\195\037\239\137\039\016\166\034\012\065\228\123\135\239\181\126\226\223\074\208\022\133\014\032\028\070\080\022\208\016\004\161\105\046\188\137\220\113\199\029\088\038\066\118\174\194\119\095\243\167\096\145\235\128\079\128\195\003\114\222\199\029\242\021\103\064\031\052\081\003\068\176\105\211\038\039\145\067\067\067\220\107\081\212\088\056\221\169\001\205\014\190\165\007\058\236\112\153\003\069\021\008\050\161\022\219\007\091\006\228\224\196\001\059\000\089\032\218\011\108\221\186\021\131\004\053\008\214\249\008\194\203\072\196\235\101\183\089\246\023\156\140\023\128\115\128\195\149\113\201\099\225\030\151\004\142\229\094\002\144\129\207\041\219\145\029\057\114\228\193\007\031\180\040\177\113\208\145\029\150\129\114\007\223\222\003\029\118\184\204\135\002\011\196\165\056\067\016\182\015\216\001\023\008\065\111\182\016\052\161\030\077\236\216\177\099\237\218\181\226\245\050\019\151\095\096\016\081\203\032\092\222\178\076\175\184\055\007\159\240\115\128\151\228\060\153\199\194\053\028\075\051\228\040\213\000\118\182\101\120\233\165\151\014\030\060\184\126\253\122\027\007\203\097\177\244\101\016\102\245\138\190\157\242\026\060\208\097\135\217\078\019\091\032\082\197\171\237\131\200\067\016\184\000\047\248\250\000\004\124\225\205\194\233\131\029\132\214\060\160\103\219\074\018\081\011\172\177\009\115\021\150\103\013\087\072\099\110\001\089\205\213\001\190\034\132\079\016\065\008\074\050\104\066\208\219\183\111\063\112\224\128\023\010\011\193\249\054\014\122\049\194\020\179\148\059\248\174\060\240\255\000\000\000\255\255\204\191\243\197\000\000\000\006\073\068\065\084\003\000\163\236\117\045\094\211\037\135\000\000\000\000\073\069\078\068\174\066\096\130"
if LOGO_ASSET=="" and type(writefile)=="function" and (type(getcustomasset)=="function" or type(getsynasset)=="function") then
    local ok,asset=pcall(function()
        local file="KarmaPanda_UI_Prototype_Logo.png"
        writefile(file,LogoBytes)
        return (getcustomasset or getsynasset)(file)
    end)
    if ok then LOGO_ASSET=asset end
end
LogoBytes=nil
local LEAF_ASSET=""
if type(writefile)=="function" and (type(getcustomasset)=="function" or type(getsynasset)=="function")then
    local ok,asset=pcall(function()
        local file="KarmaPanda_Leaf_Image_v1.png"
        writefile(file,"\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\000\001\115\082\071\066\000\174\206\028\233\000\000\000\004\103\065\077\065\000\000\177\143\011\252\097\005\000\000\000\009\112\072\089\115\000\000\014\195\000\000\014\195\001\199\111\168\100\000\000\013\182\073\068\065\084\120\094\237\093\009\140\100\069\025\094\081\020\084\208\229\084\001\021\081\017\229\088\020\076\072\240\032\034\016\005\018\015\212\120\031\001\162\006\013\070\068\193\096\016\185\004\015\016\081\092\084\080\131\010\011\202\041\017\093\046\009\002\011\171\184\092\043\184\113\101\089\247\000\123\142\158\238\247\234\255\254\050\095\117\213\155\234\154\215\061\061\051\221\179\051\240\190\236\159\238\233\087\085\175\234\255\235\253\085\255\081\111\023\044\168\080\161\066\133\010\021\042\084\168\080\161\066\133\010\021\042\204\035\172\091\183\238\037\233\111\021\102\009\171\086\173\218\162\209\104\156\101\173\221\044\189\086\097\022\208\104\052\118\053\198\060\049\050\050\178\067\122\173\194\044\192\024\115\164\181\214\026\099\222\145\094\171\048\011\000\240\109\010\032\207\243\147\211\107\021\102\001\034\114\043\005\032\034\055\164\215\042\012\024\214\218\133\034\242\063\039\000\035\079\172\094\189\122\203\180\076\133\001\034\207\243\183\146\249\086\173\085\085\155\101\217\190\105\153\010\003\132\136\124\153\252\135\064\189\026\250\076\090\166\194\000\160\170\207\091\182\108\217\230\198\152\095\121\198\059\001\024\099\126\096\173\221\124\197\138\021\207\077\235\084\232\035\084\117\023\017\185\022\192\163\084\061\020\128\255\092\041\034\087\013\013\013\109\155\214\169\208\071\088\107\095\231\116\127\107\241\085\010\032\060\005\196\216\216\216\203\211\058\021\250\008\099\204\219\157\238\007\220\236\047\004\224\069\144\231\249\126\105\157\010\125\128\181\214\233\118\099\204\187\130\238\143\137\002\241\002\056\208\151\223\060\109\163\194\012\080\171\213\022\114\225\005\240\155\160\251\083\226\239\000\126\105\140\249\153\170\086\118\065\191\033\070\030\043\155\253\109\170\168\117\125\121\090\183\066\031\064\151\067\047\002\000\112\121\090\183\194\052\097\173\125\214\154\053\107\158\207\239\000\190\091\008\032\218\001\197\127\251\235\167\248\186\047\100\253\180\205\010\083\000\025\104\140\057\031\192\153\134\002\208\014\002\240\196\117\192\192\156\014\224\092\099\112\246\130\005\011\042\001\204\020\034\242\089\206\108\045\182\158\102\002\227\099\106\109\072\157\160\062\156\182\085\097\026\104\052\026\175\006\096\038\211\255\177\000\068\164\062\058\058\090\197\139\103\002\107\237\179\195\126\094\068\110\159\138\000\000\184\024\001\227\198\085\204\120\154\176\214\062\199\228\230\215\034\242\117\000\151\164\251\127\148\048\159\228\237\129\011\000\156\074\155\128\130\076\219\174\208\035\000\156\237\102\126\135\069\183\019\065\090\166\177\136\156\152\182\089\097\010\080\213\253\162\069\117\002\163\039\080\180\029\133\008\154\205\230\107\210\054\231\029\054\110\220\184\117\250\219\108\128\251\120\126\138\200\061\169\000\038\168\159\228\009\241\235\192\077\172\191\118\237\218\023\164\109\207\006\054\108\216\176\085\250\219\180\048\052\052\116\064\115\172\121\113\179\217\124\109\122\109\144\016\145\079\002\248\173\136\092\147\234\255\201\200\173\003\130\043\084\117\137\049\230\125\105\219\131\068\179\217\220\189\217\204\023\215\106\181\055\165\215\166\141\060\119\014\046\206\170\239\055\026\141\087\166\215\007\001\085\125\069\161\126\122\089\003\226\050\198\020\246\192\200\200\200\142\105\219\131\000\019\197\084\245\060\103\012\026\115\094\122\125\070\224\142\004\192\253\254\209\174\001\056\205\090\251\162\044\203\246\094\183\110\157\083\021\131\000\004\215\181\169\031\050\217\036\042\168\131\112\088\207\024\115\089\218\102\191\160\170\091\053\155\205\215\091\107\095\076\075\029\034\195\190\175\247\166\101\251\130\044\203\246\002\144\021\179\082\228\049\017\089\011\224\047\170\058\144\089\102\140\057\204\011\125\162\010\234\192\120\146\182\098\245\140\015\236\159\182\217\015\168\234\203\000\252\021\130\127\139\200\191\002\079\000\212\085\117\247\180\124\223\032\034\095\240\055\042\030\113\255\055\099\178\031\053\198\156\158\214\153\014\184\000\139\200\007\056\024\017\121\148\247\232\198\240\148\092\121\145\229\170\186\155\049\230\253\214\218\045\210\123\076\007\198\152\051\069\228\035\000\086\037\227\119\159\034\114\076\090\167\239\016\145\235\221\077\005\109\003\142\058\243\163\180\206\084\065\227\073\068\254\164\170\077\017\025\074\025\060\025\113\130\136\200\083\170\106\000\044\233\135\053\204\096\079\060\206\248\126\254\239\043\211\058\003\001\119\067\000\054\164\059\019\171\252\215\146\133\136\124\131\051\207\024\115\073\090\063\070\055\119\177\181\118\081\217\096\123\037\214\163\032\026\141\198\110\105\219\189\194\024\195\008\219\161\220\124\248\246\220\024\227\251\248\205\201\090\110\026\210\250\003\065\150\101\071\181\049\038\081\013\145\016\158\244\159\159\099\189\178\125\049\005\208\077\008\048\160\043\161\093\000\061\170\034\207\176\115\210\054\039\003\055\023\252\020\145\019\252\189\055\004\230\167\247\136\238\067\163\239\240\180\173\129\128\012\011\046\002\055\027\082\134\152\113\033\240\169\000\212\024\099\014\023\145\091\084\117\239\178\246\082\033\248\228\171\195\085\148\250\182\153\206\186\201\168\101\007\200\176\170\030\233\023\242\054\021\148\222\047\032\207\243\003\068\100\041\109\135\048\062\247\137\146\251\071\227\228\019\223\169\205\129\033\207\229\036\175\099\039\048\032\038\223\193\224\078\094\198\125\185\170\238\026\218\137\005\016\190\123\033\127\047\212\141\007\157\182\223\133\220\142\141\204\009\109\199\253\143\225\247\240\059\002\120\216\215\017\255\153\182\089\244\131\227\086\213\076\068\190\148\182\055\043\016\145\175\249\199\175\107\071\249\025\202\249\065\221\015\193\138\224\106\032\098\198\007\070\049\179\001\192\106\087\103\106\140\143\239\073\134\058\111\104\039\001\232\240\240\246\000\030\017\145\251\146\126\078\104\211\145\183\069\162\173\238\166\017\000\029\101\000\238\238\042\004\223\217\148\049\190\206\025\124\026\172\181\046\230\155\010\129\186\088\068\062\161\080\233\218\126\201\111\044\015\032\087\213\247\170\234\214\105\219\188\031\013\072\085\037\243\047\010\125\042\109\175\132\002\243\001\220\185\073\051\179\025\048\097\252\149\017\171\120\091\218\141\104\197\250\181\099\216\219\015\095\077\218\012\079\192\007\001\060\078\021\052\174\230\058\133\035\219\127\103\121\008\050\005\030\087\213\067\227\118\003\104\179\064\245\097\049\210\232\040\224\018\114\109\043\050\000\223\162\135\032\110\115\214\193\089\100\128\115\092\167\038\089\011\028\069\051\172\152\117\034\079\133\164\218\120\134\210\120\010\086\166\049\100\112\039\230\147\146\107\166\112\073\047\143\085\080\036\092\090\178\163\081\031\074\218\044\039\133\114\172\160\000\067\198\198\038\003\213\007\012\078\005\048\194\129\148\237\138\038\184\142\073\137\032\000\156\101\140\249\161\170\058\215\065\096\148\136\184\045\239\164\194\077\239\233\245\184\049\230\160\184\061\085\061\008\000\179\044\046\236\200\248\046\106\040\008\076\085\159\228\147\219\047\011\123\198\080\085\006\206\047\165\032\038\101\086\066\078\117\133\025\011\253\073\104\147\091\071\183\016\011\110\233\200\172\152\082\161\138\092\206\243\004\241\022\148\041\236\197\068\233\082\191\140\188\251\165\006\197\098\166\201\023\131\159\043\104\054\155\123\000\184\183\116\112\221\168\125\063\093\207\243\252\205\028\032\025\071\075\084\085\255\083\246\020\149\253\022\147\066\031\133\193\098\175\122\094\197\167\129\170\163\016\192\036\012\079\169\101\211\224\142\102\083\231\094\148\141\122\214\024\156\019\030\209\158\102\108\009\121\230\172\003\112\013\219\021\145\015\185\217\092\178\072\150\010\192\051\053\082\065\239\100\059\016\220\172\170\206\162\157\080\167\007\010\099\242\110\135\083\231\108\160\159\091\050\000\139\233\027\233\170\138\058\205\190\066\021\065\025\089\098\155\128\184\056\196\132\178\093\200\151\191\061\244\041\048\048\045\215\011\249\013\198\127\233\100\084\213\055\164\099\158\115\168\215\235\220\097\060\226\024\041\019\103\110\071\074\117\184\193\055\169\134\172\216\163\180\181\241\152\088\167\132\188\013\224\220\031\046\181\197\152\243\102\192\124\039\056\063\158\249\145\232\165\170\059\112\135\000\224\159\197\204\235\052\227\059\144\023\222\114\000\055\002\184\002\226\188\141\061\049\145\249\163\060\067\198\044\105\017\249\179\139\039\132\156\210\041\080\232\059\128\007\068\244\120\107\237\118\233\088\231\052\152\149\166\170\239\161\059\160\023\230\165\058\061\048\192\009\176\164\252\100\052\229\250\209\036\241\186\254\001\085\229\137\156\077\107\108\205\004\034\242\197\176\243\232\153\017\017\077\073\133\181\213\107\255\156\010\133\190\082\141\205\251\243\199\170\186\147\079\047\185\026\112\241\211\009\003\158\049\197\234\109\138\170\174\140\024\110\100\058\011\179\171\071\071\071\095\154\142\105\222\002\006\063\015\179\107\058\251\240\129\144\239\003\247\248\209\204\191\032\237\251\188\135\223\141\028\166\170\023\250\005\114\180\080\015\221\004\209\237\218\036\228\218\015\245\211\207\182\114\206\113\055\170\208\007\085\245\059\214\090\030\133\221\044\246\029\205\075\116\234\188\247\243\255\177\120\026\202\162\077\051\161\018\038\151\253\086\068\237\090\179\158\231\207\218\022\219\212\125\061\239\016\119\060\241\114\110\038\034\199\001\248\003\013\054\017\105\164\204\233\198\184\041\083\135\054\032\082\167\187\091\085\175\022\145\099\163\254\149\246\123\222\033\030\080\167\217\164\170\219\002\184\173\152\138\211\176\025\038\165\168\189\248\062\000\152\094\227\002\240\001\105\095\203\250\060\111\208\235\000\084\244\104\085\253\005\000\026\077\079\141\159\005\235\070\221\098\003\229\212\010\212\163\166\208\155\172\181\151\136\200\167\210\190\196\232\165\239\243\010\033\244\072\168\234\158\252\108\052\116\183\154\173\045\012\215\021\234\220\006\206\249\214\199\039\129\204\103\000\157\209\187\225\225\097\103\209\050\028\201\096\060\191\103\089\182\079\212\207\129\229\186\206\058\104\190\211\152\161\139\025\192\079\153\071\202\224\139\136\011\071\222\046\034\127\131\096\012\192\085\220\127\003\134\142\188\235\001\072\175\033\078\071\046\098\086\242\251\184\051\141\097\071\218\034\191\135\200\026\064\249\061\131\224\110\102\106\180\158\060\061\091\085\239\001\112\113\158\231\111\081\117\079\230\038\057\027\049\099\048\111\072\085\127\199\067\018\145\110\119\169\030\147\065\140\140\137\017\140\051\119\034\083\123\166\241\186\180\106\093\106\204\100\096\249\240\029\000\211\035\057\033\250\146\243\058\080\136\200\241\000\150\138\200\157\100\098\060\032\175\002\122\208\237\173\140\131\014\076\156\156\186\148\045\139\041\148\145\247\003\181\009\066\068\070\068\228\110\085\189\057\207\243\207\167\099\159\117\240\245\049\170\186\051\243\038\249\106\000\206\116\170\146\208\097\215\233\148\025\233\223\189\094\155\009\165\006\088\124\159\094\239\233\099\020\197\184\090\219\215\155\252\041\204\067\199\198\198\118\097\232\051\229\209\064\081\171\213\014\051\198\184\179\187\073\231\166\053\192\248\239\216\129\214\173\237\048\075\139\153\093\180\051\126\058\102\066\189\105\080\186\022\197\109\251\246\151\142\142\142\030\146\242\104\224\160\069\203\003\016\034\114\018\068\092\224\188\128\239\038\051\252\210\001\181\015\046\250\158\060\246\004\196\069\162\214\066\112\031\019\173\066\080\198\089\177\045\031\191\091\087\130\111\041\090\112\239\096\020\043\036\214\006\196\247\233\133\034\071\110\027\168\106\085\245\196\044\203\222\184\114\229\202\217\157\253\101\224\139\083\243\060\063\069\068\190\034\034\015\177\147\034\082\228\221\076\005\016\121\008\173\244\197\037\062\171\109\017\128\226\093\065\158\129\244\114\095\013\065\206\151\248\113\221\112\194\025\015\105\254\131\239\151\083\213\109\000\092\199\012\062\190\216\047\189\087\047\128\136\075\185\017\145\191\171\234\009\062\037\115\238\190\145\203\199\096\023\229\249\216\129\140\102\185\078\027\089\006\224\062\017\185\205\057\191\000\154\255\027\001\220\010\145\043\025\253\082\213\079\251\132\220\133\195\195\195\219\179\045\107\236\193\170\186\212\051\192\205\074\199\020\224\090\102\206\241\187\049\230\221\108\215\149\113\231\199\090\121\131\080\220\152\231\249\219\216\014\005\233\211\016\207\087\213\099\025\098\004\112\037\128\187\068\100\061\223\069\228\005\123\027\207\194\241\181\200\156\076\000\046\203\053\223\063\211\108\159\044\203\156\237\050\047\017\252\234\092\184\051\205\246\226\247\232\253\110\011\099\035\045\064\085\247\161\231\180\096\190\159\221\010\221\168\170\251\134\164\045\166\155\104\107\223\254\084\033\132\034\150\171\043\084\117\143\180\109\030\172\163\027\130\126\041\190\133\151\191\101\089\182\168\094\175\239\228\239\237\038\192\051\022\180\070\195\057\172\096\100\249\196\040\010\227\099\044\195\180\112\255\247\199\221\223\185\028\211\082\025\237\071\167\156\250\090\051\046\224\167\149\123\097\016\240\238\106\030\206\198\120\104\209\171\021\152\051\066\078\014\140\097\126\014\023\224\227\248\183\063\074\123\110\241\196\248\069\158\139\005\015\124\199\105\132\079\059\063\079\063\193\064\056\119\060\033\147\033\074\013\225\113\216\109\066\057\070\174\220\239\198\156\022\126\227\158\028\128\123\181\065\188\171\082\056\027\229\096\150\169\024\223\005\116\148\021\103\203\226\005\021\178\062\048\063\048\208\207\106\174\001\063\142\127\247\121\073\110\061\008\219\086\255\084\060\017\028\109\149\016\074\192\173\157\183\170\093\018\022\221\210\158\137\119\114\209\077\203\071\255\129\195\021\190\126\193\084\238\196\184\109\012\234\200\219\007\244\007\241\173\235\124\017\084\037\128\020\060\084\029\135\009\061\243\239\010\187\037\034\048\142\159\034\242\160\103\176\075\065\012\191\135\050\198\152\067\130\058\138\218\051\245\122\125\231\080\190\066\132\060\207\079\142\024\197\252\251\171\082\043\051\018\000\143\047\173\119\101\197\189\208\213\197\115\211\197\149\006\034\196\185\183\221\255\182\065\108\178\067\117\115\025\052\114\060\227\087\139\200\018\190\104\073\181\253\191\037\137\153\171\170\060\044\030\078\050\142\132\119\085\164\002\240\101\183\164\085\204\192\059\128\053\172\019\159\210\124\198\131\199\124\178\204\208\002\189\168\086\171\021\187\156\110\048\198\028\017\102\180\103\104\079\111\077\183\195\118\059\099\204\165\089\150\221\048\235\030\204\185\138\145\145\145\061\135\134\134\142\072\127\239\006\017\057\218\169\041\099\104\021\111\108\054\155\071\166\101\186\161\094\175\031\177\126\104\253\172\190\128\234\105\005\062\053\222\133\065\151\002\105\110\156\213\170\080\161\066\133\010\021\042\084\168\080\161\066\133\010\115\027\255\007\166\141\027\187\229\025\021\201\000\000\000\000\073\069\078\068\174\066\096\130")
        return (getcustomasset or getsynasset)(file)
    end)
    if ok and type(asset)=="string" then LEAF_ASSET=asset end
end

local ABOUT_ASSET=""
if type(writefile)=="function" and (type(getcustomasset)=="function" or type(getsynasset)=="function")then
    local ok,asset=pcall(function()
        local file="KarmaPanda_About_Credit.png"
        writefile(file,"\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\128\000\000\000\122\008\006\000\000\000\119\055\091\180\000\000\000\001\115\082\071\066\000\174\206\028\233\000\000\000\004\103\065\077\065\000\000\177\143\011\252\097\005\000\000\000\009\112\072\089\115\000\000\014\195\000\000\014\195\001\199\111\168\100\000\000\153\211\073\068\065\084\120\094\228\253\005\116\021\214\214\046\012\243\190\239\057\167\197\226\238\238\238\238\030\034\004\009\033\129\016\060\009\004\098\196\221\125\199\093\136\065\130\187\006\119\040\045\085\218\066\075\129\186\183\072\041\242\252\099\206\157\077\129\246\156\247\124\247\222\239\142\251\253\119\141\177\198\206\222\217\009\100\207\185\166\060\243\153\115\077\145\085\150\141\080\082\087\018\232\026\105\011\180\141\180\005\146\074\210\002\049\089\113\129\184\188\164\064\086\083\094\160\098\166\041\208\180\212\019\024\056\152\009\044\061\029\248\107\021\035\117\129\166\153\182\064\205\076\083\160\100\164\046\144\214\085\016\104\091\235\009\076\092\045\005\218\214\006\002\005\003\053\126\174\109\171\045\048\112\209\021\216\005\056\008\116\109\181\005\051\212\102\008\164\181\229\005\146\106\210\002\073\089\113\129\182\158\186\064\083\079\093\160\109\160\046\008\008\241\019\204\158\031\038\240\246\115\023\248\006\121\242\163\139\187\131\192\221\211\069\016\016\230\039\040\168\044\021\252\114\239\129\224\251\031\127\020\060\122\244\088\240\237\247\223\011\030\062\124\036\248\242\219\175\249\181\167\207\158\009\158\189\178\031\061\126\044\248\241\167\095\004\015\031\061\022\220\187\119\079\240\197\215\095\011\134\119\236\016\148\055\181\009\134\119\237\021\116\111\222\034\216\188\107\183\224\167\123\247\254\244\179\255\183\236\041\051\037\103\246\200\170\200\064\067\079\029\250\022\250\208\053\211\133\154\174\026\148\052\020\161\110\170\005\029\059\067\104\088\234\066\219\214\016\038\238\054\176\240\178\135\181\175\019\044\060\108\096\232\104\010\117\075\029\072\104\072\067\193\064\005\122\118\198\252\154\154\153\022\020\141\084\161\101\167\005\051\111\051\216\007\216\097\109\230\042\004\204\243\133\140\174\044\052\045\117\160\107\174\139\217\145\161\152\029\053\011\129\225\222\240\013\242\066\116\092\020\022\045\091\136\240\121\033\008\153\019\004\087\079\039\248\006\120\033\040\220\015\181\205\117\184\252\214\085\252\240\203\175\184\243\229\023\184\247\240\033\030\062\250\013\039\207\157\198\233\011\231\240\087\235\254\111\015\249\241\217\011\175\029\061\123\022\125\091\182\225\131\091\183\049\184\115\015\198\247\031\196\147\151\222\241\127\215\154\034\046\047\046\144\082\144\130\132\156\004\196\101\197\161\166\171\010\029\099\109\168\233\168\066\073\091\009\114\234\242\080\049\080\131\156\142\018\148\141\053\160\109\099\000\035\039\115\168\153\105\067\193\080\021\138\070\106\080\050\082\135\140\182\002\164\052\228\032\175\171\012\045\115\029\104\152\233\192\196\197\020\038\110\198\080\210\149\071\122\238\058\148\086\023\192\208\070\015\202\250\042\176\112\052\199\146\132\040\100\020\039\097\117\202\018\216\187\088\193\201\195\030\249\229\185\008\014\015\064\096\152\031\108\029\173\224\232\098\007\159\000\047\020\085\020\225\232\201\227\168\104\108\192\209\083\167\240\240\183\071\056\120\244\048\182\239\217\129\143\063\185\137\223\127\255\253\037\049\254\254\248\049\238\124\254\057\222\122\231\109\028\061\113\012\055\111\221\194\221\047\062\199\206\003\251\080\215\222\142\193\045\091\209\062\052\130\145\221\123\113\231\139\047\095\248\201\255\187\214\020\113\050\247\050\098\152\041\061\019\244\072\074\160\160\174\000\025\101\025\076\151\156\142\233\082\211\033\173\042\003\105\053\089\022\178\138\169\022\084\077\181\160\102\174\205\143\090\086\250\252\040\166\034\001\025\077\121\168\024\170\067\073\079\133\149\192\035\212\029\009\169\043\096\106\099\012\107\071\115\132\069\006\193\220\214\020\202\090\074\208\053\213\130\247\044\023\044\079\138\065\114\118\002\066\231\005\194\039\200\029\011\022\207\197\252\152\185\008\008\241\133\187\183\011\108\029\173\225\233\227\138\181\169\107\112\225\234\085\028\152\056\130\045\059\183\227\247\199\079\240\219\163\071\248\252\203\047\240\235\189\123\175\254\093\248\246\251\239\113\235\246\103\216\115\112\031\078\157\063\131\239\190\255\030\019\039\079\160\166\165\017\213\173\173\104\236\233\069\099\111\031\198\246\238\195\167\119\238\226\241\227\199\175\254\138\255\043\214\020\242\247\114\170\114\144\087\087\128\188\154\060\100\085\100\033\038\035\006\049\105\049\204\144\156\142\153\082\051\032\161\032\009\005\013\069\072\107\200\065\078\087\009\178\058\138\080\208\087\134\188\174\018\020\013\084\161\101\169\007\089\045\121\072\169\203\064\221\068\011\010\058\202\080\051\209\128\131\159\003\070\182\012\033\183\036\019\122\038\218\208\055\213\134\145\185\062\052\245\053\160\099\170\009\207\096\103\204\095\028\142\217\081\193\136\089\049\031\075\019\098\048\047\038\012\062\065\158\240\246\119\135\135\143\011\236\156\108\224\226\233\136\246\158\118\062\197\223\124\247\061\046\092\190\136\029\123\119\225\235\111\191\125\254\135\060\123\246\012\015\031\062\196\211\103\207\240\229\215\095\225\200\137\009\092\186\122\005\019\039\143\227\157\015\222\197\190\195\007\208\059\180\017\029\253\189\168\104\106\065\255\248\022\108\220\186\021\231\174\188\129\239\126\252\017\031\222\248\024\143\126\255\253\165\015\231\255\159\215\147\039\079\248\113\138\188\154\188\128\078\060\157\124\009\058\253\106\242\108\001\216\037\144\085\144\021\231\045\171\042\011\057\077\005\136\041\136\099\186\236\012\076\147\155\129\233\242\051\033\169\034\005\005\045\069\118\019\178\218\010\236\002\148\012\084\089\057\028\124\028\081\082\085\136\168\197\243\225\031\234\003\103\079\007\232\024\106\065\203\064\003\230\246\198\008\093\016\128\168\165\115\224\230\231\136\069\171\230\097\209\202\005\088\190\102\049\102\069\004\192\209\205\030\222\001\158\112\118\119\100\075\144\083\148\131\230\206\054\140\110\219\130\125\071\014\225\192\145\131\248\236\206\109\022\060\045\058\193\095\124\253\021\190\252\250\107\124\114\235\083\092\188\122\005\183\238\220\198\055\223\125\135\239\127\252\017\231\046\093\192\190\195\007\049\190\107\007\114\202\043\081\213\214\142\051\087\174\224\151\123\191\242\207\255\244\203\047\127\082\128\091\159\221\194\185\127\018\095\252\127\125\061\125\250\148\031\167\072\202\075\010\100\148\100\048\083\106\038\166\137\079\229\211\175\164\169\196\214\128\020\066\082\094\018\020\035\200\169\201\067\151\130\068\115\061\040\107\171\064\082\065\018\051\020\102\066\076\089\002\146\106\210\144\084\151\129\028\089\005\003\085\142\015\116\108\012\096\236\104\010\207\000\055\088\218\154\097\078\212\108\044\079\088\134\089\179\003\161\103\172\003\067\051\061\024\091\026\192\193\221\026\254\017\222\136\089\057\015\097\011\002\177\120\229\066\196\175\091\001\103\119\007\184\122\057\195\213\195\009\238\094\206\072\203\078\195\193\137\035\088\159\189\001\109\125\221\184\125\247\014\222\124\231\026\063\190\104\190\127\249\245\087\060\252\237\055\086\132\051\023\206\177\021\184\112\229\018\206\094\060\207\143\035\091\198\080\214\208\128\241\061\123\240\225\205\155\047\124\036\127\094\020\087\144\069\161\211\114\240\240\065\228\228\229\032\058\102\033\066\195\066\017\022\030\138\085\241\171\208\213\211\133\031\126\252\225\213\031\253\255\204\154\050\067\114\154\128\078\187\164\156\004\199\001\228\247\197\164\103\178\224\037\100\133\086\128\020\065\076\086\012\082\138\082\080\055\208\128\161\157\049\076\236\077\161\101\161\011\101\003\085\168\024\170\065\213\072\157\227\001\109\107\003\024\059\091\192\220\221\150\179\007\067\059\035\216\123\216\194\193\205\022\158\254\238\112\112\183\231\000\083\089\083\009\042\154\202\048\182\212\135\139\191\061\066\022\250\035\114\105\056\086\174\095\140\240\005\193\112\116\181\131\147\155\061\043\000\237\132\245\241\108\246\123\071\135\241\241\039\159\240\127\254\179\187\119\056\016\252\253\119\161\002\144\224\031\063\022\154\054\114\023\059\247\237\194\177\083\039\240\211\047\191\178\240\247\031\057\128\225\045\099\168\105\109\097\225\127\253\237\055\248\241\167\159\094\250\064\094\093\003\027\007\096\109\099\141\255\250\219\127\097\202\148\041\248\175\255\250\047\252\253\239\127\199\223\254\246\055\126\078\091\075\091\019\067\035\067\175\254\232\255\209\075\100\057\133\065\160\172\024\155\124\082\002\018\254\116\137\105\252\040\046\035\206\129\225\012\137\105\252\026\041\007\041\137\178\142\010\012\109\141\161\111\099\008\117\019\077\104\154\105\195\200\193\004\154\150\186\080\053\209\132\153\187\013\108\253\156\225\021\225\007\083\023\075\232\089\027\192\220\217\002\070\118\198\252\126\025\117\089\072\042\074\194\202\193\018\254\033\190\008\093\232\143\057\113\129\072\072\143\195\138\117\139\016\182\048\016\158\126\174\176\113\176\130\203\164\011\088\145\184\012\227\219\183\032\191\162\004\123\014\029\224\255\060\157\252\043\111\093\101\193\083\212\255\243\047\191\240\227\079\191\252\140\051\023\207\225\240\177\035\056\121\246\052\062\187\115\007\251\143\028\196\149\055\223\192\208\248\024\170\219\058\048\178\115\023\014\030\155\192\249\203\023\113\253\227\015\159\155\068\209\250\236\246\103\240\245\247\101\001\147\192\037\036\036\032\041\041\201\091\074\074\010\210\210\210\188\101\100\100\048\117\234\084\126\095\110\126\238\075\191\227\255\228\245\092\001\166\137\079\019\076\147\152\198\130\037\005\144\085\150\097\101\160\231\051\164\102\176\075\016\041\000\189\143\148\064\092\094\002\242\026\010\080\210\081\134\172\134\060\111\101\138\001\116\020\032\174\042\009\117\011\029\232\059\154\033\048\050\024\158\033\094\208\181\214\135\174\149\062\052\056\064\084\130\180\186\044\164\149\164\097\098\105\004\223\032\079\120\205\114\069\104\180\031\226\211\150\096\222\146\016\172\203\092\137\005\177\243\096\109\103\193\167\223\195\219\021\209\075\022\032\118\245\018\036\101\166\098\124\231\014\124\253\221\119\160\191\129\124\252\163\073\011\032\242\225\087\223\190\134\177\029\091\056\003\120\227\218\155\236\255\143\028\159\224\108\097\100\203\056\202\027\155\209\212\215\135\202\230\102\028\058\113\002\095\124\245\037\110\124\250\135\059\120\251\157\183\161\169\173\201\066\149\144\144\100\225\063\223\047\040\001\109\250\154\020\065\074\074\146\223\159\149\147\245\252\247\252\159\186\200\165\081\006\069\135\101\138\152\244\012\001\153\120\218\116\218\041\253\163\064\144\128\032\097\054\032\116\011\083\197\094\199\235\051\094\227\061\077\114\026\043\129\172\138\028\091\003\021\029\021\040\106\043\067\070\075\030\146\234\210\144\212\144\133\130\190\042\148\201\026\184\089\195\209\223\021\150\110\086\112\241\119\129\177\131\041\020\008\095\080\149\101\055\096\101\111\001\055\095\023\172\092\023\139\228\156\213\008\095\024\136\149\235\226\016\062\063\148\221\128\163\171\061\092\221\029\017\187\124\017\026\059\154\208\222\223\203\230\252\189\235\239\227\251\073\223\251\248\201\019\060\121\250\020\247\031\060\224\175\041\162\159\056\117\028\099\219\183\224\212\185\211\120\235\221\183\113\249\205\055\112\112\226\048\134\199\055\161\170\181\013\117\157\093\104\232\238\065\203\198\033\252\244\235\061\124\243\237\055\248\246\251\239\240\205\183\223\066\223\064\095\040\124\073\073\136\137\139\099\166\184\024\063\138\044\128\104\139\075\072\240\022\089\004\122\141\126\142\226\130\255\211\023\089\188\159\238\221\163\032\080\092\064\169\031\005\130\116\242\149\052\148\016\020\022\128\133\177\081\016\151\019\135\004\097\004\082\051\240\250\204\215\240\218\180\127\060\087\130\025\020\027\040\072\113\218\072\041\164\170\190\026\180\204\116\056\083\144\209\144\131\154\145\006\116\172\013\096\237\227\132\160\005\161\008\158\063\011\126\161\062\240\011\243\130\173\187\053\052\244\212\160\174\163\010\099\075\035\206\014\050\010\146\145\154\151\136\196\244\165\028\003\216\059\219\192\221\199\005\014\172\004\118\136\089\186\016\053\077\181\168\108\168\065\107\079\007\167\122\039\206\156\196\213\183\223\194\233\243\103\177\107\255\030\006\132\072\009\062\248\232\067\028\056\122\008\091\118\110\101\164\144\092\195\161\099\071\208\208\042\064\231\064\031\011\191\178\165\013\013\061\189\056\123\245\077\220\253\242\043\118\035\063\254\242\011\226\019\227\159\011\159\004\047\218\175\042\000\009\158\094\163\071\145\021\160\061\099\198\012\072\074\075\226\230\039\255\058\192\252\127\115\145\121\167\224\245\191\091\063\223\187\047\068\002\233\212\043\170\043\064\081\067\017\198\150\134\072\206\088\143\197\203\023\097\154\216\107\207\205\063\041\192\084\177\169\236\006\040\091\160\215\164\228\164\032\163\044\203\138\035\163\034\011\021\093\021\040\105\041\241\086\209\085\133\138\158\042\180\045\245\224\024\224\010\239\048\111\120\250\185\097\197\218\197\088\182\054\006\038\086\006\176\180\055\199\134\220\052\204\137\010\135\189\167\021\230\046\009\198\242\245\209\136\088\024\204\190\223\205\203\025\078\238\014\012\006\145\002\100\020\100\032\179\048\019\133\149\197\236\187\233\180\118\111\236\065\094\089\062\214\101\172\195\208\216\008\043\001\041\197\007\031\093\199\251\031\093\231\175\143\159\057\133\218\230\122\148\215\085\163\184\182\022\101\130\038\118\003\021\205\045\216\118\224\032\174\188\243\046\127\096\036\052\009\073\009\136\137\137\177\080\201\228\255\149\005\016\009\159\054\189\231\069\119\064\143\164\064\209\139\099\094\253\188\255\183\045\202\132\104\255\179\069\135\135\064\178\143\239\220\197\020\089\037\105\129\180\162\020\187\000\074\247\180\012\052\177\052\062\142\077\243\107\211\254\011\175\077\251\187\240\212\207\124\141\093\001\129\067\036\112\009\121\073\136\075\139\067\082\065\010\146\138\210\252\072\175\073\202\075\008\127\151\162\020\099\007\106\006\234\048\178\055\129\163\175\019\066\230\006\099\109\122\060\022\175\088\008\027\071\115\184\251\056\035\097\253\106\132\069\006\035\056\210\007\221\163\181\040\111\204\066\104\148\063\172\157\044\096\231\104\205\245\000\107\123\075\068\198\204\067\110\113\014\086\037\173\064\067\091\035\054\109\029\195\251\031\125\136\119\222\127\023\013\173\013\200\204\207\128\160\077\032\132\126\079\078\096\239\161\125\056\117\238\012\163\128\003\035\131\200\047\043\066\065\101\037\138\235\026\080\080\085\131\162\234\058\148\053\182\160\121\096\016\227\251\133\065\101\122\070\058\254\227\063\254\227\185\057\039\043\064\002\022\041\128\200\228\139\132\207\167\127\082\240\047\110\082\160\215\167\189\142\119\223\123\247\213\207\254\127\203\034\220\131\098\163\191\090\164\232\020\011\061\122\244\008\239\221\188\137\041\178\042\178\236\002\104\147\034\200\169\200\194\216\194\016\106\090\202\016\147\156\142\105\116\234\197\094\231\088\128\130\066\086\002\169\025\028\036\138\201\204\132\056\165\139\138\210\236\014\088\041\040\117\036\252\064\065\010\210\042\050\108\005\116\204\117\097\238\096\134\160\136\064\068\047\141\196\156\152\112\056\122\216\192\039\208\003\030\126\046\008\152\237\133\165\107\163\080\084\151\142\168\021\179\225\059\219\013\033\145\254\176\119\177\134\189\147\013\163\129\190\129\222\088\155\154\136\168\037\145\012\002\189\249\246\053\222\180\232\121\073\085\009\170\026\170\048\113\226\024\070\198\055\161\189\175\011\221\027\123\217\239\239\059\180\015\085\130\058\148\055\181\160\164\174\001\185\101\229\040\021\052\161\185\127\000\093\155\054\099\112\199\110\220\254\252\046\180\117\180\049\115\230\204\151\252\251\171\230\254\165\211\063\121\226\069\130\023\005\138\146\147\001\097\210\250\164\087\063\255\255\045\139\064\045\130\194\069\104\223\139\075\020\047\209\058\125\233\146\016\008\034\225\083\064\070\000\016\005\128\211\041\200\147\158\009\121\021\057\033\038\064\080\048\213\007\020\101\033\037\047\197\175\083\138\072\056\129\188\154\002\228\084\228\032\061\009\038\145\114\208\115\121\117\121\200\168\201\066\065\067\001\170\122\106\208\054\215\133\174\133\030\012\108\013\096\226\108\008\107\119\011\248\132\122\032\120\158\031\150\037\069\035\110\109\020\150\172\137\068\224\060\138\017\204\225\021\236\010\191\080\047\142\005\168\032\020\062\047\020\233\185\105\136\094\026\133\174\126\097\144\037\242\114\223\253\240\003\159\246\019\103\078\161\189\183\029\077\157\002\244\014\247\096\231\190\157\012\000\109\221\181\013\117\205\013\168\106\105\069\105\067\035\242\043\171\216\252\055\246\246\163\109\104\004\219\143\028\197\232\216\102\188\246\143\127\176\064\069\166\095\100\246\095\020\050\237\153\098\098\152\041\246\135\255\255\147\002\072\074\098\250\244\233\080\081\085\193\183\223\253\001\087\255\239\090\247\238\223\199\167\159\125\134\135\015\127\123\245\091\207\023\101\062\035\059\119\008\045\000\009\157\010\052\042\218\202\048\181\050\102\004\078\093\087\029\242\170\242\028\000\242\137\150\151\132\130\138\002\228\148\229\160\160\034\015\021\013\101\168\107\171\065\075\087\131\221\134\166\158\006\148\053\149\217\141\072\043\074\115\096\072\010\064\155\042\138\090\084\007\176\051\129\166\185\022\020\012\228\096\236\100\004\091\031\027\184\004\057\192\041\208\022\033\209\126\216\080\180\006\243\227\194\224\022\224\008\239\089\110\240\013\245\128\179\167\029\167\130\126\065\066\011\176\116\245\018\054\247\239\093\255\128\131\061\209\250\252\171\047\241\238\007\239\227\195\027\055\112\242\220\073\140\110\027\230\074\033\225\001\029\189\157\040\171\041\071\113\077\045\187\128\210\122\001\042\091\218\081\221\209\141\234\206\094\028\185\120\005\113\203\151\225\111\255\245\095\207\205\191\184\184\004\196\197\197\255\036\124\086\008\105\041\022\048\041\136\048\003\248\035\011\120\113\147\021\024\024\028\120\233\131\255\223\177\030\060\252\141\063\027\074\139\233\180\255\244\243\207\207\143\011\165\126\095\125\243\013\110\124\114\019\219\014\028\192\020\053\093\021\129\146\166\034\020\212\229\161\097\160\193\081\247\170\181\043\161\111\166\015\121\021\121\022\062\153\123\081\240\071\153\129\172\154\156\176\076\172\167\010\045\035\045\062\241\098\082\051\032\171\044\011\185\201\160\144\190\150\085\146\230\088\064\074\065\018\202\090\202\048\180\054\132\190\181\033\052\076\052\097\228\100\010\099\023\019\216\120\091\033\096\158\055\022\039\068\098\246\162\089\088\151\019\143\240\232\096\044\142\095\128\057\209\161\112\245\115\132\147\151\061\102\205\009\192\154\212\004\036\103\172\067\070\126\006\239\254\225\001\246\117\084\020\162\063\138\148\226\236\165\115\056\113\246\036\006\055\015\096\255\145\125\056\114\226\008\167\132\130\182\070\020\086\085\179\011\040\107\108\230\044\160\190\111\008\117\125\067\120\243\131\235\112\117\115\197\235\083\095\099\097\074\073\073\067\086\086\150\077\249\139\002\037\133\120\253\181\215\225\225\229\014\059\007\059\252\227\031\255\120\030\253\255\149\162\252\231\127\254\039\034\230\070\188\042\159\255\215\023\089\128\143\110\222\120\142\143\252\240\227\143\108\250\105\081\182\115\247\203\047\113\246\226\057\236\056\120\064\088\012\082\212\016\086\002\213\245\212\096\237\096\009\043\007\011\040\107\043\179\091\160\012\129\131\060\069\105\204\148\021\227\024\064\130\048\000\053\057\040\235\170\064\205\080\131\177\000\050\249\210\084\066\150\158\129\025\050\051\032\169\068\193\161\036\228\212\229\160\160\169\008\077\003\077\174\001\080\060\064\238\064\223\214\008\170\102\234\208\182\213\132\071\168\011\252\231\121\195\043\220\013\011\087\205\067\192\092\111\044\092\062\023\139\087\069\195\061\200\005\054\238\150\240\156\229\130\021\073\113\028\052\174\223\176\142\179\130\149\073\043\176\231\192\094\060\248\237\055\108\220\052\132\228\172\100\244\141\244\096\219\222\045\024\221\058\140\109\187\183\178\018\236\216\183\019\245\045\013\108\001\138\106\235\081\084\083\135\210\134\038\212\245\014\162\182\111\024\003\091\183\051\156\059\083\124\026\164\101\072\120\082\208\210\210\132\147\171\035\102\206\156\193\104\031\165\119\070\038\134\080\086\081\130\153\185\025\006\071\134\048\109\218\052\161\069\144\146\126\009\041\020\109\250\025\121\005\121\124\249\229\255\026\190\001\009\081\132\224\253\171\117\231\139\207\025\012\163\147\079\002\167\160\079\020\015\208\207\031\063\125\146\003\230\158\145\033\097\012\032\167\034\003\121\002\102\180\148\161\111\162\011\061\019\029\232\153\234\194\200\194\240\143\040\095\145\078\179\052\071\249\083\103\190\142\127\076\251\059\007\129\084\038\166\148\079\203\068\155\017\063\066\251\148\116\085\032\171\041\207\037\098\034\127\016\252\171\109\162\013\107\071\075\161\194\232\169\050\183\064\078\079\009\186\118\058\048\113\053\130\177\179\001\060\195\220\016\028\229\015\255\185\094\136\140\155\141\021\235\099\225\232\109\007\107\119\075\056\251\219\035\102\249\002\196\174\092\132\184\085\177\072\076\073\064\081\101\017\154\058\154\056\038\088\182\102\057\086\167\172\066\115\151\000\155\182\013\163\127\164\015\219\118\111\195\158\131\187\081\217\080\129\242\186\010\148\212\214\033\183\188\028\197\181\013\040\107\104\068\077\087\031\026\007\055\035\183\178\010\146\146\226\144\148\158\009\041\089\242\239\051\096\100\106\132\172\220\044\134\121\229\100\101\249\209\219\215\007\177\075\099\217\180\031\058\122\008\065\033\193\012\019\203\200\252\217\252\139\054\101\021\091\182\109\121\085\070\255\067\139\010\092\127\197\125\120\117\125\244\201\077\028\059\123\006\215\111\220\192\253\007\015\217\236\211\034\005\162\010\233\214\093\219\049\048\178\081\168\000\210\178\146\002\089\005\105\200\043\201\064\069\075\025\038\022\070\208\054\208\132\133\173\025\108\156\172\057\184\035\193\147\041\167\160\079\074\086\018\051\037\103\096\134\132\048\067\032\108\128\220\004\101\016\244\030\057\053\057\168\235\171\067\223\202\000\102\206\230\048\180\055\102\128\136\234\005\078\190\078\048\182\055\225\077\032\145\140\174\034\124\034\188\144\086\144\132\136\197\161\008\089\024\136\176\152\032\204\141\011\131\071\176\019\098\086\205\099\183\096\233\102\001\191\008\111\204\095\020\129\232\184\005\088\024\023\137\132\228\213\012\012\213\052\214\034\102\217\066\204\139\153\131\037\171\023\163\164\166\024\173\221\045\024\024\033\023\112\128\093\064\093\115\045\202\106\203\081\222\032\096\011\064\056\000\237\170\214\014\078\003\087\173\091\143\215\167\189\006\041\138\117\100\196\240\143\105\255\005\011\027\051\236\063\116\000\010\138\242\016\023\023\195\140\233\051\248\228\239\222\183\135\011\067\149\213\149\248\224\195\235\080\085\087\129\129\145\001\204\173\204\249\061\127\086\128\041\072\088\147\240\170\140\254\135\022\165\189\183\191\248\252\249\115\242\239\047\090\004\074\241\200\021\146\255\063\116\226\056\142\158\057\195\022\224\206\023\095\224\218\007\031\048\252\251\195\079\063\225\220\229\075\140\153\052\247\116\097\138\164\180\164\064\086\078\026\050\114\082\080\086\087\132\185\141\041\087\235\012\205\244\097\231\098\043\036\138\168\043\048\118\047\041\043\001\105\089\041\204\148\152\142\153\226\051\032\038\033\006\113\041\113\072\201\072\065\098\146\064\050\093\092\088\072\162\242\177\182\153\014\011\219\212\193\012\234\134\026\140\014\026\217\027\195\196\201\028\022\030\182\080\053\211\134\153\187\005\098\215\068\033\108\097\000\252\034\060\017\022\021\008\247\000\039\152\058\026\034\056\210\031\126\179\061\097\238\098\202\236\162\200\037\115\048\055\122\054\162\098\231\051\086\065\052\177\222\193\062\100\022\100\034\061\039\021\025\249\027\208\059\212\131\221\007\118\161\163\191\003\157\253\029\216\125\096\055\026\219\155\080\209\080\139\194\154\090\142\001\042\155\091\121\087\181\182\163\117\112\004\139\086\172\192\107\175\079\250\115\025\105\076\157\249\026\044\109\205\113\247\203\047\224\233\237\009\117\077\117\142\009\020\149\020\240\225\199\031\193\218\214\026\169\233\169\252\161\151\085\150\033\056\044\024\177\113\177\236\006\200\026\136\098\002\218\175\191\254\058\172\108\172\254\167\025\071\116\242\175\092\187\134\047\190\254\026\015\127\123\200\001\030\089\132\023\021\128\124\255\027\111\095\099\016\236\141\183\223\070\247\166\205\184\246\193\117\236\061\113\010\091\014\028\226\108\137\126\126\243\238\221\104\235\233\128\160\189\017\083\020\212\020\004\178\138\050\144\145\151\002\089\002\003\083\061\088\216\153\067\067\071\013\154\122\234\028\027\080\054\064\065\157\130\170\060\196\164\102\010\021\064\098\006\196\196\197\032\041\037\001\069\069\005\040\040\042\048\000\036\067\138\066\216\128\188\036\199\005\170\186\170\208\048\212\224\071\042\030\201\107\043\066\223\218\000\150\158\054\208\176\036\222\160\025\092\067\108\225\025\226\004\091\119\011\216\123\088\193\043\196\021\193\145\126\112\009\116\128\181\187\057\236\125\108\096\199\037\227\032\172\092\187\012\235\050\214\114\064\056\048\186\017\103\046\156\069\181\160\026\133\021\069\216\188\125\051\011\124\219\158\173\232\029\234\230\116\112\120\124\136\209\194\226\154\202\231\254\159\205\127\123\023\170\218\058\209\058\052\138\176\168\121\248\199\235\127\099\129\041\042\042\194\214\201\006\030\222\110\120\240\219\067\100\231\230\032\044\034\012\094\062\094\028\244\157\062\123\006\251\014\236\131\175\159\015\147\082\015\030\057\132\200\133\243\089\017\044\173\044\033\033\033\014\121\121\185\231\193\033\041\133\184\132\056\222\123\255\189\151\004\250\207\022\097\244\196\067\016\021\182\072\192\180\191\248\234\043\220\254\252\115\124\255\211\079\248\252\171\175\240\229\055\223\176\159\255\237\209\031\169\030\249\252\075\111\190\137\203\111\189\137\043\215\222\066\223\216\024\182\031\158\192\248\193\035\056\124\230\044\126\254\245\087\188\247\209\199\216\126\224\000\054\110\030\068\255\232\000\166\152\056\153\011\140\172\141\160\169\163\014\029\003\045\102\225\016\252\074\193\032\017\057\100\021\165\025\027\144\087\149\227\168\158\168\098\226\146\116\242\103\050\108\042\037\045\201\194\167\096\135\220\194\076\233\025\108\045\196\229\036\024\003\160\147\079\113\130\134\174\058\204\108\077\097\098\107\002\119\127\103\088\056\155\064\217\064\017\154\198\170\112\241\183\131\123\000\069\251\182\008\140\240\134\139\191\003\220\066\156\017\180\192\031\094\179\221\225\020\104\015\159\217\158\136\136\013\193\188\197\017\088\181\110\057\150\037\196\162\111\168\015\199\078\029\071\107\087\043\131\064\187\246\239\230\250\000\041\064\107\079\051\234\090\106\209\209\223\142\182\158\054\148\212\084\112\254\079\040\096\069\083\043\043\064\069\115\027\090\135\054\193\047\044\024\127\127\253\191\248\239\081\081\081\070\220\178\037\112\112\182\195\206\061\059\049\188\105\024\177\075\022\163\163\171\131\125\255\198\161\141\252\097\039\167\037\035\191\040\031\075\087\044\069\078\126\014\106\234\171\057\062\208\208\086\103\043\032\043\043\243\092\009\040\014\024\221\188\233\185\160\254\187\069\194\167\250\005\005\110\164\016\180\233\249\103\119\239\050\127\145\204\060\213\047\014\156\058\205\156\008\209\162\140\232\220\229\203\056\118\250\004\127\022\195\227\163\076\124\025\221\181\007\007\078\156\196\151\223\124\139\107\031\124\136\179\228\002\198\135\176\105\251\008\166\200\107\043\008\136\010\174\103\172\011\109\067\045\152\089\025\067\075\079\131\201\024\196\223\083\080\149\003\101\009\196\027\148\033\063\047\039\204\131\169\252\073\062\078\090\070\010\114\242\050\144\145\149\018\198\007\147\101\101\138\007\168\062\064\204\098\013\035\077\168\105\171\050\180\059\119\065\004\022\046\153\207\052\048\121\021\089\086\060\087\047\039\184\251\186\194\197\199\001\065\115\125\097\233\108\006\059\063\107\232\059\234\192\202\219\002\038\110\134\112\008\176\069\248\162\032\132\068\005\032\098\081\048\086\037\199\162\180\166\024\071\078\028\229\124\191\170\161\146\097\223\253\071\246\099\112\108\035\106\154\043\120\055\119\053\161\107\160\007\053\205\013\040\172\174\069\110\121\005\138\106\235\152\023\088\211\209\141\246\177\237\112\243\243\198\212\233\175\067\070\090\154\079\239\202\248\021\088\177\106\197\115\186\088\069\117\005\062\186\241\017\244\013\245\145\182\033\141\095\059\117\230\020\098\098\099\160\166\174\134\208\240\080\156\056\125\130\021\038\098\094\004\007\145\114\114\178\207\149\128\020\135\096\230\127\103\061\121\242\020\191\061\250\029\031\124\252\017\067\186\164\004\180\031\060\124\128\243\111\188\129\109\007\015\098\239\241\019\120\243\189\247\176\251\216\073\188\243\225\135\207\221\000\041\003\125\030\227\059\182\098\116\235\102\140\110\029\195\230\237\091\208\059\050\128\254\077\067\056\127\229\018\174\092\123\019\059\246\238\068\071\095\059\026\059\005\084\011\016\066\193\036\124\002\116\040\245\083\211\082\101\037\048\052\213\099\005\160\045\130\138\165\229\068\149\047\041\161\240\229\100\248\067\147\147\023\254\193\084\031\096\087\160\040\205\169\164\162\150\018\167\140\242\106\114\080\082\085\096\078\160\157\139\021\012\204\116\033\045\047\193\248\129\190\185\062\188\130\220\097\234\100\004\231\032\071\056\006\216\193\041\208\001\046\193\078\240\159\231\003\099\087\003\216\007\153\099\246\018\063\132\045\008\066\100\092\056\214\102\046\071\099\071\061\014\031\059\138\150\174\022\244\012\118\096\251\222\049\108\221\051\130\253\019\219\113\224\216\014\052\117\082\001\168\028\125\195\003\168\107\109\070\126\101\053\178\203\138\145\085\082\036\116\003\029\093\104\027\029\135\131\155\011\254\062\237\111\156\247\147\021\056\050\113\004\013\077\002\236\061\184\143\247\177\147\199\025\209\027\025\029\102\042\024\045\034\160\158\060\115\018\226\082\098\080\215\082\199\007\031\126\192\065\217\236\185\179\049\099\198\116\086\000\218\100\013\040\083\032\037\161\069\016\237\143\012\204\252\245\122\240\240\033\023\114\174\189\247\030\115\030\200\108\211\201\190\251\197\023\216\126\232\008\070\247\236\099\193\239\059\121\026\167\175\092\197\039\183\255\224\069\126\116\243\099\028\061\121\020\163\091\054\163\127\116\008\189\195\027\209\051\216\135\238\141\221\104\234\104\068\117\099\053\199\072\244\053\225\034\045\221\045\152\162\160\174\032\032\008\152\242\125\034\107\082\244\079\174\192\204\210\152\107\002\036\124\037\053\121\040\170\041\064\134\080\062\202\004\164\037\033\041\045\033\012\010\057\118\144\129\130\146\002\155\079\101\117\037\033\240\163\169\196\149\069\109\099\109\142\001\116\076\116\160\107\168\013\069\053\121\152\090\027\065\067\079\149\223\167\097\160\014\075\039\115\056\250\216\195\194\221\004\218\182\026\176\244\182\128\177\139\001\028\002\236\096\226\102\004\115\079\051\216\005\154\097\078\092\000\194\162\130\176\098\125\012\214\100\044\067\067\123\053\182\238\222\130\178\186\066\108\223\183\009\007\038\182\097\231\193\017\028\057\181\021\163\059\218\081\211\092\134\106\065\013\043\064\101\099\019\178\075\075\145\093\090\194\110\128\130\192\234\182\078\180\012\111\130\155\175\015\140\173\076\088\121\229\228\228\176\123\239\030\084\215\087\035\108\118\024\060\125\060\209\220\214\140\095\126\253\133\063\228\142\238\014\220\155\076\197\072\041\086\038\174\196\178\213\075\241\224\193\003\220\127\112\031\198\166\198\144\150\150\129\130\130\060\043\000\029\022\194\011\076\076\141\241\227\207\063\225\147\207\062\099\222\193\063\091\036\108\162\188\157\190\124\005\239\125\244\017\222\253\240\035\220\186\123\151\255\173\177\125\007\081\215\055\136\142\077\091\048\118\224\008\054\239\063\140\139\111\189\205\063\071\202\119\241\234\101\062\249\221\131\125\028\228\117\244\118\049\062\210\061\208\205\110\112\067\065\026\146\050\018\081\221\088\137\202\134\074\142\003\088\001\068\141\032\170\218\042\172\000\026\250\234\208\053\166\238\029\061\232\089\234\067\211\064\003\250\070\058\092\187\055\178\052\130\190\181\017\012\236\077\097\104\103\010\053\125\117\054\247\074\042\138\208\209\211\134\161\169\062\228\148\228\096\108\110\200\041\037\097\009\186\166\058\176\117\182\130\141\131\037\012\204\244\096\231\106\013\039\111\091\168\026\170\048\103\208\200\222\008\122\246\058\176\015\176\133\145\179\001\140\092\012\097\233\101\014\029\091\013\232\057\104\193\204\195\024\086\190\070\152\183\034\016\243\151\132\099\225\138\057\088\182\110\033\138\107\179\208\049\208\136\193\241\014\236\216\063\136\193\045\173\104\237\175\068\243\064\049\234\058\242\208\055\218\134\226\154\082\212\052\009\208\216\217\142\130\170\074\100\149\148\032\175\162\146\227\001\042\009\055\246\111\132\079\200\044\228\148\149\192\196\220\132\221\090\075\123\011\046\092\186\128\218\250\090\072\072\138\051\242\247\219\111\194\096\139\078\219\239\143\255\096\015\191\253\238\219\184\244\198\037\254\122\251\206\237\152\242\159\255\001\121\005\010\138\229\217\050\018\136\068\008\162\140\172\012\174\189\251\014\071\238\148\138\253\051\056\231\227\079\063\197\201\139\151\176\125\226\036\014\159\061\143\051\151\175\224\210\219\239\178\034\244\111\219\137\193\157\123\209\191\099\015\186\198\183\163\111\251\110\236\057\126\074\072\135\127\250\020\251\143\030\196\208\248\038\012\109\030\097\183\215\210\221\206\202\095\223\082\143\234\198\042\244\012\117\160\190\189\026\149\130\114\020\087\231\161\181\079\128\041\042\186\106\002\077\035\077\006\126\168\061\140\020\129\130\062\138\228\165\213\100\056\117\035\069\032\032\071\207\206\008\006\142\102\048\118\179\134\177\171\053\076\093\173\216\196\203\041\201\066\085\067\021\218\250\090\208\208\209\128\186\166\026\084\053\084\160\169\163\001\085\077\085\168\235\170\177\066\089\216\152\194\210\193\028\198\182\198\048\178\053\224\109\108\111\012\061\043\125\232\217\235\194\202\219\028\190\115\125\224\022\234\006\215\016\087\088\184\155\193\200\094\015\134\118\250\208\181\087\135\215\092\007\006\136\034\162\103\097\225\202\008\196\167\198\033\179\056\025\237\003\117\104\232\044\193\218\204\165\216\080\028\143\242\230\084\244\108\170\065\115\119\053\050\139\114\080\092\093\142\150\158\078\148\212\213\035\175\162\010\197\148\013\212\214\161\164\094\128\250\174\030\068\044\140\068\083\119\007\002\102\005\113\222\190\105\108\051\222\121\247\029\140\111\031\135\146\170\018\220\189\221\158\091\128\127\182\072\000\254\129\126\088\184\104\033\156\093\156\025\059\032\011\064\238\032\062\113\053\052\180\052\176\125\231\014\252\114\239\030\110\221\033\038\243\036\052\059\041\060\209\122\231\250\117\028\062\123\014\091\143\028\199\142\099\167\216\018\156\185\242\006\142\095\184\132\205\251\015\162\109\116\012\195\123\014\160\123\203\014\244\110\219\133\237\071\143\243\239\124\252\248\119\238\125\032\018\076\075\087\027\023\191\136\000\067\169\094\107\087\027\003\102\219\246\140\065\208\209\128\172\162\012\100\151\108\064\107\095\003\166\040\233\169\008\212\012\213\057\080\163\173\164\165\204\037\097\034\135\168\027\105\114\218\070\060\062\234\248\145\213\085\132\138\137\144\233\067\204\031\082\018\073\057\113\126\063\009\090\091\079\139\149\064\085\083\025\242\202\114\144\083\148\225\077\238\064\075\095\019\026\186\106\208\049\210\230\216\128\122\009\020\116\020\161\106\164\006\093\027\029\104\089\105\067\203\090\027\022\158\150\240\153\227\003\215\016\055\216\120\217\192\220\218\024\102\150\134\048\182\213\133\251\044\082\128\112\132\046\008\196\130\165\179\145\152\030\135\117\217\043\176\124\093\020\178\203\214\033\037\111\053\018\055\044\069\073\253\006\244\140\214\161\168\058\027\057\037\121\200\041\201\231\024\160\180\190\129\133\079\138\064\001\033\089\128\134\238\094\172\073\093\135\141\155\134\017\022\017\206\001\091\078\110\014\011\131\252\250\234\164\213\140\052\254\085\105\245\197\117\245\173\055\081\219\080\203\104\155\141\173\053\196\102\206\100\005\248\251\063\254\134\246\158\078\164\164\165\048\095\240\155\239\191\199\123\031\126\200\113\000\165\123\020\221\019\070\064\032\014\129\054\111\188\243\014\246\159\058\131\177\067\019\216\121\236\036\007\126\199\047\092\196\145\051\103\177\229\208\081\108\218\119\000\173\131\067\232\221\178\029\189\091\119\098\235\161\163\184\249\217\109\102\055\019\184\211\218\221\198\224\152\160\189\009\237\189\029\028\031\117\015\244\160\190\181\001\013\109\245\104\234\108\068\117\083\037\146\054\172\065\165\160\002\083\212\140\052\005\068\239\038\074\023\041\002\017\056\020\117\148\056\103\087\055\210\096\070\047\177\122\008\201\163\222\064\085\099\013\206\227\025\251\151\151\132\044\005\134\010\082\080\080\086\128\134\150\058\012\077\013\024\067\160\000\079\094\073\150\183\178\134\034\180\244\169\090\168\196\092\067\178\052\202\058\202\144\084\149\098\184\088\201\064\025\138\006\202\080\054\082\135\186\165\022\204\061\045\225\022\234\014\091\047\027\088\218\152\114\102\098\102\099\008\123\079\075\068\175\140\096\246\112\122\225\026\212\182\022\161\176\122\003\150\174\093\128\140\226\053\040\170\217\128\186\246\034\008\186\139\049\048\222\136\166\174\058\164\231\103\162\176\162\132\185\132\116\226\041\016\036\048\168\176\170\134\021\160\150\232\097\130\058\236\060\184\031\225\115\035\240\095\255\245\159\112\116\114\124\046\216\219\119\111\227\167\159\255\053\117\156\022\009\143\214\087\095\127\005\053\117\085\206\146\072\001\094\123\253\239\168\174\175\195\145\227\199\144\184\046\145\115\248\091\183\111\115\057\150\132\079\062\159\153\204\063\255\204\076\157\043\111\191\141\061\039\207\096\243\129\035\216\057\113\018\199\046\092\194\206\137\227\216\113\100\002\059\014\031\197\230\061\123\209\059\054\134\238\177\173\104\223\180\005\163\251\014\226\226\091\215\240\222\199\031\163\123\100\004\067\091\183\160\123\120\035\004\237\205\168\111\174\067\091\119\059\058\251\186\208\222\215\002\065\071\037\042\026\138\081\084\149\139\074\065\009\242\043\115\048\133\218\188\117\109\013\161\110\172\009\101\125\085\126\084\210\167\206\030\101\168\026\170\115\171\023\021\110\204\092\045\097\096\111\012\121\045\069\206\008\100\149\100\088\248\028\024\202\075\066\078\081\022\170\106\170\028\011\040\076\086\007\037\100\102\242\247\233\189\042\090\074\208\051\209\125\142\041\080\213\144\092\012\051\132\213\229\216\194\208\191\097\228\076\192\144\027\060\195\220\097\229\110\001\019\091\035\182\002\246\174\086\240\008\116\194\130\229\017\136\092\030\142\248\244\056\172\207\089\141\228\220\085\088\147\185\020\057\229\235\177\231\200\024\014\157\216\134\134\174\034\236\062\050\132\045\187\135\144\083\154\131\129\209\065\012\108\030\065\094\121\041\114\203\202\144\087\081\193\150\064\132\006\118\012\110\196\174\195\135\048\059\114\030\019\066\166\078\155\134\242\202\138\087\101\252\111\173\115\231\207\049\039\080\078\094\142\099\128\169\211\094\071\101\093\045\110\124\246\025\170\004\181\120\239\195\235\120\243\157\119\240\238\245\015\240\229\087\095\177\002\060\126\250\140\035\126\074\253\046\092\125\019\059\038\078\098\100\239\065\086\132\189\167\206\098\203\225\009\236\154\056\142\003\071\015\098\215\129\125\232\031\031\071\219\208\040\106\123\007\209\190\105\043\182\030\158\192\238\137\099\252\119\084\053\055\163\092\208\136\010\065\045\106\155\106\208\214\211\142\174\129\110\212\183\214\096\219\222\081\244\012\183\034\187\052\025\213\045\069\104\031\016\096\138\130\166\130\064\081\087\153\131\061\106\242\160\222\063\162\120\043\026\168\065\201\088\131\155\065\021\168\249\195\068\003\026\230\218\080\212\081\134\132\130\004\164\228\037\133\194\087\016\090\001\037\053\069\198\197\229\149\200\244\075\067\102\242\251\226\004\012\049\151\064\014\006\038\122\176\119\177\097\206\001\089\001\082\006\025\021\025\200\168\203\065\205\088\003\154\166\218\220\087\224\028\228\138\057\075\066\097\239\099\011\067\091\067\088\187\088\194\205\215\025\193\243\253\185\090\072\245\130\200\101\097\088\184\106\014\159\254\184\053\145\072\202\094\129\178\134\028\116\108\172\099\243\063\178\163\025\091\246\118\163\099\163\000\069\085\069\168\018\084\035\183\036\031\185\101\197\200\041\043\069\121\099\011\004\061\189\168\235\236\102\118\240\240\142\029\008\157\027\001\049\177\153\012\108\073\203\074\163\127\099\255\159\076\063\019\046\095\233\033\120\113\245\244\245\096\218\140\105\252\059\152\055\048\099\058\004\109\173\248\228\206\029\156\056\119\150\145\186\055\223\125\135\055\069\251\036\244\095\239\221\103\100\143\094\163\019\191\227\216\073\108\218\127\008\251\078\157\197\174\019\167\049\178\103\031\014\157\062\141\147\103\079\096\207\193\189\104\233\237\065\125\079\031\026\006\070\208\052\180\009\195\059\119\099\124\231\086\038\204\082\247\116\107\127\063\042\026\234\208\220\217\204\193\096\103\127\023\054\239\024\198\129\227\099\232\223\220\132\226\186\076\244\111\110\067\077\091\033\053\134\136\009\164\148\164\160\064\062\093\069\010\082\026\178\220\215\071\125\126\172\000\198\154\220\020\058\077\094\216\011\168\160\075\174\065\019\038\086\070\092\222\149\125\110\001\100\184\150\064\169\158\138\134\018\007\128\134\038\250\080\086\087\128\146\154\002\187\002\082\008\083\075\099\110\248\032\101\032\148\145\064\035\226\022\088\185\088\195\059\196\027\097\011\195\016\048\207\031\225\049\193\008\137\010\130\161\189\009\187\029\234\043\112\015\118\131\189\143\029\028\252\109\225\030\230\196\012\162\180\130\068\054\255\020\011\036\164\199\162\161\179\020\163\059\218\176\227\096\055\198\246\180\099\116\123\055\178\139\179\080\094\091\129\220\210\066\228\148\022\035\175\188\002\101\130\102\212\119\247\176\002\052\247\245\097\100\199\118\204\158\055\007\211\166\078\101\166\143\095\128\031\118\238\217\133\239\191\255\254\037\001\147\066\144\239\254\103\043\118\233\098\134\200\073\001\172\237\172\089\009\250\006\007\241\193\141\143\241\222\071\031\178\255\127\227\218\091\184\248\198\027\044\252\119\175\095\199\167\183\063\195\245\143\063\102\020\111\231\177\083\028\000\142\031\058\138\221\039\078\099\219\145\227\216\188\119\031\179\154\247\031\217\139\029\123\183\163\109\160\031\213\157\061\168\237\221\136\154\158\001\244\141\109\193\248\206\049\212\114\201\187\018\089\165\133\040\168\040\102\223\223\210\217\138\250\022\001\070\182\012\096\199\129\065\108\063\048\128\225\109\237\216\121\112\019\198\247\246\011\059\131\008\003\160\045\038\047\206\012\030\106\007\167\038\080\009\057\113\072\201\137\011\155\068\165\103\048\025\068\073\091\025\154\134\154\208\055\213\131\129\185\062\140\044\013\121\235\155\234\114\237\064\077\075\005\006\198\186\076\044\033\033\083\058\072\194\039\011\160\168\034\015\081\221\129\112\005\057\101\025\072\077\054\163\080\041\090\219\068\007\182\158\246\112\244\117\128\107\160\035\172\061\109\184\148\172\103\099\008\011\234\054\242\182\133\133\171\005\156\002\028\224\051\199\003\129\145\062\088\149\186\024\009\233\075\016\155\048\031\169\249\171\209\220\091\137\029\007\251\176\243\112\015\186\070\043\209\185\081\192\110\032\167\036\023\249\229\037\200\043\047\099\078\032\185\129\170\150\054\006\131\004\221\221\024\218\177\029\179\034\102\195\197\205\025\234\026\234\092\000\250\119\124\255\139\139\050\007\117\045\053\134\197\009\084\170\174\171\230\182\178\173\059\118\048\176\243\246\007\239\179\192\041\176\059\115\233\034\222\124\231\109\014\250\168\141\141\112\125\082\000\058\241\155\014\028\198\232\222\131\216\125\252\052\187\131\141\091\199\177\235\192\078\236\058\176\003\227\187\070\208\177\177\015\149\173\029\168\110\239\066\227\192\048\054\110\219\142\145\173\195\168\107\109\064\114\238\006\164\230\103\161\165\167\003\157\125\221\108\001\106\155\107\033\232\172\194\150\189\125\056\112\108\051\054\237\236\194\200\246\078\236\059\062\054\073\009\099\074\184\130\144\206\069\233\159\162\052\055\133\076\035\038\176\216\235\016\151\154\001\025\005\225\235\220\007\064\176\176\178\052\055\131\080\123\024\245\010\018\230\079\229\100\242\237\212\241\227\233\235\006\035\051\003\222\068\027\035\004\145\132\077\010\162\173\175\009\089\121\105\097\028\161\036\205\138\064\091\081\083\145\007\075\088\123\218\194\204\213\024\242\122\138\048\114\048\229\077\129\168\142\165\030\076\157\204\096\238\106\006\239\008\079\196\173\093\136\213\105\075\144\184\033\014\203\215\047\068\106\126\060\026\186\074\209\210\095\138\190\241\074\212\117\229\160\123\184\025\077\157\045\216\080\152\137\220\242\082\014\254\008\003\032\037\160\146\112\099\111\047\090\251\251\048\180\125\043\230\071\047\064\094\081\030\108\236\108\240\183\191\255\013\169\233\066\216\247\175\022\089\002\170\190\209\208\009\081\065\038\175\048\015\211\103\078\135\138\154\010\043\192\193\195\135\016\183\044\014\219\247\236\226\244\142\020\128\204\252\169\139\151\112\236\252\005\092\120\227\013\028\061\123\014\023\222\124\019\087\175\189\133\211\023\047\177\005\216\180\255\048\186\183\108\199\142\137\019\216\115\226\020\198\119\239\192\161\099\007\177\109\207\022\012\108\238\065\239\232\000\187\173\242\230\054\244\108\221\137\254\045\091\208\218\067\065\094\011\050\138\242\049\178\125\007\134\183\108\070\115\087\029\250\070\219\209\177\177\030\227\187\251\176\247\232\008\182\031\232\067\231\080\037\058\135\234\176\113\107\155\208\002\208\073\167\232\156\082\063\242\233\036\108\018\022\157\252\153\068\016\037\186\023\209\188\149\101\120\115\212\175\169\000\121\003\021\040\025\171\243\132\144\153\074\226\236\203\137\253\099\110\109\010\015\095\087\182\000\058\134\218\208\055\214\101\104\153\145\064\085\121\078\019\245\140\116\160\170\174\204\253\008\068\073\163\204\065\203\080\019\042\006\170\208\180\208\134\186\153\058\116\173\245\096\225\106\197\074\070\113\136\178\161\026\052\204\180\161\107\171\015\027\031\043\172\088\191\008\041\249\137\156\250\037\110\088\194\169\032\041\193\234\244\040\084\182\110\064\067\087\033\134\182\116\160\161\173\014\105\185\233\194\211\095\046\044\010\009\107\002\245\108\254\187\134\054\098\211\142\109\072\074\073\226\002\083\112\104\016\100\228\100\184\220\189\255\224\254\151\004\079\040\030\117\036\083\020\255\205\119\223\178\018\208\250\238\135\239\145\083\144\003\105\057\041\068\045\138\130\153\165\025\078\159\063\199\194\063\122\226\056\174\190\243\014\046\094\189\202\194\063\114\238\002\014\159\187\128\137\243\023\177\255\244\057\236\059\117\006\199\040\213\059\123\030\091\014\031\099\037\024\218\189\015\227\135\038\024\246\061\124\124\130\121\013\164\000\067\227\125\232\223\052\136\154\182\014\102\057\183\012\142\160\186\181\005\085\130\042\212\183\053\161\164\174\010\027\199\070\081\086\087\138\214\190\026\108\221\055\192\000\217\214\189\253\216\117\104\008\067\219\154\209\049\088\141\225\109\173\024\220\218\138\041\210\010\146\220\026\070\065\029\157\096\018\008\089\001\058\229\084\172\145\164\198\081\106\025\083\144\098\214\176\042\209\191\040\138\087\147\135\026\103\012\042\028\023\204\148\019\131\152\162\004\164\084\100\024\248\177\115\178\134\185\181\009\159\118\082\132\168\197\011\224\031\236\003\061\067\109\182\006\218\250\026\204\247\167\212\144\058\132\168\012\109\104\105\000\013\099\117\238\052\086\054\084\135\162\158\010\199\035\010\244\168\167\204\065\042\053\160\154\186\091\194\045\216\005\075\214\044\064\244\170\185\152\187\100\022\187\128\164\172\101\216\080\148\136\245\121\075\209\058\080\134\134\206\034\070\006\203\027\010\081\223\042\064\102\113\062\051\130\072\248\034\005\168\105\039\222\064\015\070\182\108\102\222\192\246\189\187\016\179\036\006\254\065\126\048\179\048\099\136\155\202\191\162\069\069\025\226\212\191\184\168\061\252\246\221\187\168\019\212\035\120\118\048\026\154\005\136\142\093\136\115\034\051\255\246\053\156\191\124\009\167\047\158\199\161\051\103\113\224\244\089\028\060\123\030\135\206\093\192\190\211\231\024\245\219\127\230\060\014\158\189\128\205\007\014\099\251\196\009\006\123\070\247\031\226\231\135\079\076\224\224\196\001\108\223\187\005\099\187\134\209\061\216\203\238\075\212\221\084\209\216\140\220\178\066\084\055\213\033\175\162\024\025\005\027\080\041\040\197\248\046\082\236\110\228\085\038\163\174\189\004\035\219\123\208\183\169\009\130\206\114\012\109\109\193\158\137\077\152\162\164\174\032\208\208\087\131\148\188\004\087\251\072\032\100\005\168\124\075\185\059\071\251\116\250\105\043\073\179\082\016\100\076\086\128\130\059\098\015\169\083\222\175\032\133\169\018\083\153\015\200\035\096\140\008\249\051\131\181\189\005\055\153\080\111\223\220\232\008\086\012\051\043\019\142\013\200\058\016\070\064\138\071\086\129\122\012\117\045\116\097\227\065\253\132\206\048\113\182\128\162\190\010\183\159\019\014\161\109\169\011\099\039\051\056\004\056\033\052\058\016\043\146\023\097\193\242\112\204\137\013\102\104\056\191\042\025\205\253\197\232\024\170\196\232\206\054\116\014\087\163\161\179\024\003\155\059\152\019\144\150\079\110\128\252\127\037\147\067\136\033\076\085\193\198\174\014\116\015\013\176\018\108\217\179\027\153\121\217\088\190\106\057\098\151\197\114\020\079\105\093\113\089\009\238\221\255\051\029\139\016\194\247\063\188\142\123\015\030\160\119\099\031\210\179\211\184\139\185\170\174\138\135\090\093\124\227\050\155\250\011\111\092\198\196\233\019\216\055\113\020\039\206\159\103\184\247\208\089\161\002\140\031\058\134\061\039\206\176\053\032\129\083\110\223\179\149\144\190\157\232\223\186\013\135\142\031\097\106\219\192\230\046\140\110\031\068\207\112\031\170\091\219\248\255\159\095\073\138\092\139\236\146\060\148\212\086\160\186\089\000\065\071\035\250\134\123\081\219\090\194\167\191\177\187\020\057\101\235\025\049\165\044\105\096\172\013\003\099\045\024\222\222\041\140\001\104\100\011\157\106\202\221\197\039\115\119\050\209\164\000\036\028\074\215\072\248\100\025\040\189\035\247\064\086\131\050\000\010\238\052\117\213\249\164\083\005\112\166\188\024\007\146\148\033\144\043\176\178\051\103\129\083\144\232\029\236\129\184\213\177\240\246\247\224\129\017\186\006\218\092\016\162\224\145\020\128\200\166\210\170\210\080\210\085\230\056\192\206\215\145\205\191\042\245\025\090\233\067\223\206\008\054\190\246\140\020\206\089\018\130\217\139\130\049\127\105\040\230\197\205\194\154\140\056\116\012\085\163\107\180\002\013\061\121\232\026\169\065\219\064\021\090\251\171\049\180\181\011\165\181\069\200\041\045\098\005\160\098\016\225\000\180\073\001\026\186\186\208\061\060\136\141\099\155\049\180\101\028\205\157\237\072\207\076\199\208\216\048\108\029\108\216\156\019\206\049\127\225\124\092\122\227\050\023\102\168\030\064\147\072\174\094\123\147\251\017\169\132\187\115\239\046\070\013\079\158\061\133\195\199\143\050\061\253\212\185\019\056\119\249\002\206\093\190\136\221\007\246\097\231\193\131\056\116\234\052\019\052\246\157\060\197\039\159\162\126\018\254\246\163\039\088\001\134\118\239\103\144\167\190\127\024\157\155\198\120\048\198\190\195\187\152\235\056\188\101\000\131\227\131\104\233\239\231\191\163\176\186\006\133\053\085\072\205\219\128\220\242\034\020\215\084\160\186\177\006\093\003\157\040\174\205\198\224\120\059\159\250\188\202\084\148\011\242\208\220\083\137\209\237\061\232\026\018\160\103\180\009\083\102\136\079\019\208\009\039\193\019\165\075\052\023\136\124\178\138\166\018\087\239\040\064\035\005\016\109\082\004\226\206\081\026\167\172\166\008\117\109\085\246\239\068\034\161\088\130\027\077\180\148\153\093\236\234\233\204\065\161\157\179\053\252\067\124\152\213\235\224\098\203\150\192\214\193\138\173\009\041\019\041\001\021\165\200\146\016\180\076\196\082\162\148\217\187\219\193\200\198\024\006\182\134\048\119\177\228\094\002\226\007\250\132\123\193\055\204\011\179\022\004\096\254\210\048\044\073\152\207\109\101\059\014\246\163\119\172\006\245\093\185\104\238\043\101\037\104\238\169\097\174\096\094\105\001\114\074\011\249\067\035\225\083\073\184\186\189\147\179\128\238\145\033\244\111\222\132\206\161\065\244\111\026\101\183\176\247\240\065\228\022\229\033\036\124\022\210\178\210\224\230\233\130\155\183\062\101\178\197\209\019\019\204\189\035\020\239\241\147\167\204\197\063\127\249\002\198\182\143\227\218\251\239\225\202\091\111\226\240\177\131\056\122\242\008\078\095\056\131\139\087\223\192\174\003\123\177\117\223\062\028\057\125\026\019\231\206\113\190\047\004\122\142\243\227\190\083\231\048\186\239\016\058\199\182\178\240\171\187\007\208\216\063\136\157\007\246\242\239\218\188\125\019\122\135\187\209\214\215\129\234\214\118\182\100\132\102\022\214\084\114\219\124\082\102\026\050\138\114\144\091\150\207\089\079\121\125\049\054\142\183\114\196\095\084\075\010\146\194\138\064\238\160\165\183\026\253\099\045\152\242\186\216\107\002\049\201\105\028\237\207\016\127\157\219\193\136\211\071\074\032\038\061\003\146\084\219\159\004\123\200\252\147\066\016\204\075\004\074\138\226\169\252\075\202\066\010\064\125\124\154\012\003\075\049\197\156\192\030\194\011\072\065\168\074\104\231\108\203\172\099\081\122\072\022\130\042\134\244\092\219\080\019\145\177\179\057\107\160\120\128\106\006\022\118\102\208\053\210\134\161\133\001\211\201\077\237\077\097\229\102\198\003\037\194\099\102\193\055\220\139\121\131\243\151\206\070\212\242\008\196\167\197\162\185\167\002\189\155\107\209\179\169\154\123\013\187\134\235\033\232\172\064\105\077\041\082\243\050\216\010\020\215\016\043\168\069\072\010\105\239\068\099\079\015\011\190\103\116\004\109\131\003\060\133\100\100\219\086\158\071\180\115\255\030\044\090\186\008\093\027\251\056\200\163\069\164\141\239\127\248\001\079\158\010\187\112\169\028\255\219\111\143\112\243\211\079\176\109\207\118\246\251\167\047\156\197\193\163\135\112\104\226\016\206\094\162\241\052\151\177\251\192\094\140\239\222\197\236\156\147\151\046\099\252\240\049\206\245\105\143\031\060\138\173\135\143\097\096\199\110\180\142\142\115\191\066\117\087\031\106\186\251\177\117\255\062\166\183\111\217\181\009\253\035\253\232\232\163\238\230\086\086\100\170\098\230\148\021\098\125\118\058\226\211\214\035\187\164\000\101\245\085\104\234\108\070\094\105\014\250\055\183\112\000\088\213\156\143\180\130\004\148\212\101\161\107\080\128\238\225\070\012\111\239\194\148\215\166\253\093\048\067\098\042\071\251\066\005\152\054\137\241\075\051\071\144\106\253\114\074\194\077\110\130\130\068\030\036\069\065\226\228\028\001\138\023\072\001\104\176\147\134\182\042\231\249\132\012\210\235\020\083\080\106\168\111\162\135\224\240\064\182\006\228\090\168\236\076\148\051\018\062\177\143\172\156\204\176\116\077\052\143\146\243\009\242\096\011\065\221\193\164\000\084\161\036\151\066\010\097\237\106\129\240\152\192\201\086\178\005\008\137\242\199\220\184\080\068\173\136\192\170\148\024\212\182\023\098\096\188\025\245\157\069\092\023\040\173\207\070\097\117\014\007\070\116\042\138\042\075\080\084\083\195\001\020\213\001\170\219\059\208\210\223\135\142\161\141\104\031\028\064\251\198\129\073\119\176\009\131\227\155\176\121\199\054\158\041\208\181\177\159\059\146\069\228\011\074\003\169\241\226\254\195\135\147\095\255\206\074\065\083\073\232\180\095\126\235\010\011\255\200\241\195\056\117\254\036\142\159\057\198\035\107\182\236\217\133\045\251\247\099\247\241\147\028\241\239\061\121\006\039\056\253\059\137\209\189\007\208\179\101\059\090\071\198\208\208\063\140\154\030\033\208\067\032\213\225\227\135\176\105\251\016\051\121\058\251\058\209\057\056\128\202\230\054\100\151\022\033\171\036\015\169\249\217\136\079\091\135\140\226\092\180\246\245\162\170\145\200\048\165\024\217\214\139\198\238\114\148\053\100\035\041\107\057\042\026\243\208\051\210\196\241\192\248\158\001\161\002\076\159\020\060\167\124\210\051\160\160\044\199\166\157\128\027\005\037\057\126\078\190\158\082\064\081\160\168\161\171\202\102\094\069\091\133\079\058\085\251\200\215\203\043\203\066\089\077\129\003\064\074\255\076\136\015\096\164\205\010\066\167\155\078\062\065\193\110\222\052\002\206\026\218\006\090\176\117\178\070\224\092\031\158\014\050\103\081\008\115\006\173\236\044\056\086\160\247\170\105\171\192\192\068\023\166\150\070\176\114\050\101\006\113\244\170\057\088\177\062\026\097\049\001\152\189\056\024\139\018\230\035\191\042\021\067\091\091\033\232\046\065\105\067\038\074\234\041\232\075\070\078\105\006\210\243\055\160\174\165\158\201\163\020\056\081\000\069\117\000\145\002\144\005\232\026\030\098\005\232\216\216\143\190\145\161\073\037\216\204\065\216\230\109\099\248\234\155\175\095\009\001\105\076\205\019\118\003\164\012\196\228\249\232\198\199\200\200\205\224\128\144\216\057\007\142\030\192\137\179\199\112\248\248\097\158\113\180\251\208\001\110\201\162\058\062\165\125\135\207\093\196\081\074\011\079\147\021\056\130\141\187\246\162\125\116\028\130\141\035\168\238\217\136\150\225\205\024\024\031\199\222\067\187\208\053\216\136\238\193\054\102\060\087\053\213\162\168\186\138\021\032\167\172\024\105\005\057\136\079\093\199\067\180\136\245\068\150\174\178\161\012\195\091\187\209\051\210\128\202\166\060\020\084\167\179\249\111\238\169\194\198\241\014\236\157\024\167\024\096\134\128\104\077\018\082\212\024\033\193\194\086\084\085\096\065\082\175\000\153\123\105\234\255\039\055\160\036\205\172\095\114\003\170\218\202\080\213\082\097\174\031\153\120\085\077\021\022\046\013\126\162\192\209\210\206\156\003\073\035\115\003\030\245\070\238\129\008\033\036\116\058\241\238\062\052\003\200\146\131\071\178\006\065\243\124\017\017\027\132\249\075\194\096\231\098\205\010\228\023\236\205\028\002\081\140\065\001\165\147\159\053\034\087\006\097\238\050\127\172\078\091\140\121\113\020\004\134\032\038\062\002\235\115\086\240\169\111\234\041\067\062\251\186\082\054\255\089\197\105\200\043\205\067\089\109\005\146\115\082\217\108\082\069\144\020\128\144\064\002\131\058\134\134\208\049\060\140\214\141\100\005\250\209\051\052\128\190\209\097\012\142\109\066\110\081\046\206\156\063\243\170\236\159\047\178\009\084\006\254\229\215\123\092\230\013\152\229\143\249\011\231\241\020\179\011\087\046\224\240\049\154\104\186\147\021\128\050\129\189\135\015\225\224\169\211\184\252\214\091\156\018\238\156\056\129\003\167\207\112\016\056\176\099\015\211\212\026\006\132\049\064\199\166\113\140\237\164\014\167\221\024\217\058\196\100\087\218\005\021\249\040\172\042\103\225\231\150\151\097\067\081\222\164\002\100\096\125\078\038\018\211\214\162\160\114\003\006\183\180\099\096\115\051\170\091\010\081\209\152\207\174\128\148\097\096\172\021\135\079\237\196\020\049\113\049\129\144\195\046\028\120\164\173\171\005\061\067\029\086\002\130\129\037\101\102\178\018\112\229\143\082\069\042\236\168\202\177\144\009\213\035\048\071\133\000\029\085\005\054\249\196\045\164\110\096\106\014\033\075\065\157\196\100\230\093\060\156\088\168\034\166\144\135\143\043\079\254\160\012\130\044\069\088\084\000\034\151\133\114\091\184\135\191\011\028\156\109\017\048\203\151\173\003\165\153\068\083\051\054\055\128\123\176\029\086\102\204\065\098\078\020\150\038\069\098\209\234\185\220\090\030\159\182\024\107\050\150\178\021\200\044\089\139\244\194\004\020\215\102\162\186\185\008\073\153\043\081\221\088\129\156\146\028\036\103\167\160\184\166\010\101\245\212\031\208\204\065\032\229\210\237\195\035\104\025\232\071\219\164\002\180\247\247\096\203\174\237\040\175\169\192\236\121\097\175\202\252\047\023\041\194\199\055\111\114\240\076\172\034\114\015\180\126\254\229\103\124\124\243\006\247\227\209\092\227\189\071\014\099\207\209\163\056\251\198\085\108\057\120\004\035\187\247\225\224\153\243\140\250\081\000\072\046\128\168\095\164\000\189\227\091\113\228\196\097\028\062\190\023\219\246\142\163\163\175\003\237\125\173\104\239\109\069\089\093\021\178\074\010\177\161\048\007\041\185\153\072\072\091\207\123\113\194\042\228\087\022\243\233\223\121\112\024\109\253\053\012\150\229\150\167\161\076\144\203\245\146\161\045\237\216\055\177\005\083\196\197\197\005\084\176\144\158\084\000\098\243\016\123\069\073\073\129\079\062\005\123\148\022\050\058\040\043\038\172\243\147\117\160\072\157\043\128\202\080\162\174\097\234\032\082\144\100\225\083\249\216\216\193\012\022\078\230\176\115\181\098\051\078\038\157\205\190\179\045\187\002\154\253\067\049\003\185\008\109\061\077\110\005\015\154\239\013\191\112\119\216\185\089\193\201\205\001\129\033\126\076\081\039\043\067\174\130\088\202\086\174\038\136\074\008\068\102\229\082\164\020\044\099\043\064\190\141\202\194\004\002\081\190\075\196\144\220\138\020\100\151\173\071\065\085\058\074\235\115\080\086\087\140\092\038\135\228\162\184\186\002\021\141\141\168\109\035\122\120\007\004\061\061\232\024\030\066\235\198\141\168\239\238\070\125\071\027\014\028\061\204\227\101\083\210\147\177\034\126\249\171\178\254\203\069\196\014\018\060\089\171\079\063\187\133\103\127\065\252\034\014\000\141\180\217\178\123\039\118\031\057\130\161\109\219\048\176\117\027\199\004\155\246\029\068\235\200\102\182\000\148\005\212\246\013\097\096\235\086\236\059\178\147\139\055\131\099\003\104\235\110\067\231\064\007\183\191\151\084\147\169\167\224\046\139\077\255\234\212\117\088\158\188\022\203\214\037\162\177\171\030\221\195\013\016\116\149\163\170\185\000\009\169\075\177\052\097\017\178\074\214\179\021\104\223\088\139\190\205\205\152\034\038\041\206\022\128\041\222\210\210\092\197\226\114\040\181\061\203\011\005\047\071\166\159\234\250\004\006\077\230\254\170\090\202\172\000\138\042\010\080\211\084\121\030\035\208\244\048\026\029\171\105\161\011\075\087\011\068\044\012\097\046\033\009\156\122\014\104\000\052\089\000\178\004\052\012\146\170\131\148\069\080\247\175\087\176\051\214\103\175\130\189\187\053\108\236\045\049\043\044\016\046\158\078\092\093\020\033\138\198\118\122\240\158\103\135\229\027\066\145\089\190\018\203\214\069\097\222\210\089\140\002\022\084\167\161\166\053\031\197\117\025\136\079\095\130\013\133\137\172\253\141\093\085\200\042\222\128\206\254\078\228\150\230\033\175\172\016\101\181\149\168\107\107\069\109\043\149\133\123\056\008\172\239\234\068\239\166\081\188\245\238\059\044\044\018\223\226\165\139\177\046\101\029\063\039\001\255\085\121\152\130\063\138\015\104\238\032\089\185\252\226\252\231\223\251\171\069\252\066\162\111\081\144\217\183\105\019\167\159\219\014\029\097\248\151\072\170\100\001\168\210\071\229\222\225\029\219\113\096\098\039\246\030\217\130\158\193\046\166\121\053\182\055\162\190\181\142\051\027\074\249\054\020\102\035\057\103\003\150\174\075\196\162\132\021\072\043\072\193\230\157\221\232\221\212\192\135\128\092\099\118\113\026\079\103\073\203\095\131\218\182\018\148\212\103\161\180\033\139\044\128\208\005\136\166\093\017\181\091\196\102\149\098\214\047\177\127\009\014\158\201\167\156\144\059\114\001\084\250\037\161\168\168\043\241\215\020\015\112\087\016\229\241\218\147\163\230\173\244\097\108\107\200\164\082\114\013\020\197\083\238\079\180\049\026\252\064\031\022\009\149\234\004\222\001\030\008\008\245\229\190\063\071\055\059\158\011\068\022\192\195\215\141\017\071\130\151\041\019\048\117\050\128\223\002\007\036\230\070\098\093\078\028\022\044\011\135\071\176\051\022\175\158\199\166\191\172\033\011\117\029\069\028\240\164\021\196\163\165\175\010\213\205\197\200\175\200\064\207\080\039\087\006\105\166\080\073\117\025\170\026\235\132\131\163\123\123\209\212\215\139\163\167\079\061\103\252\210\250\253\201\099\164\110\072\197\156\249\017\108\198\073\200\084\252\161\057\132\162\069\076\158\239\038\089\190\059\118\237\096\218\059\165\131\196\245\251\087\235\238\231\119\209\055\058\132\206\209\049\116\142\108\194\166\093\187\049\182\255\016\090\135\055\177\005\168\235\221\136\218\238\126\108\217\179\007\007\039\246\098\203\158\081\180\116\183\162\174\169\158\231\029\016\171\055\187\036\151\079\127\074\094\038\214\100\164\098\009\041\064\252\114\052\119\213\099\231\161\141\024\219\211\129\161\173\109\200\044\089\135\213\041\203\176\062\051\017\107\051\136\055\145\203\220\137\220\170\020\076\145\148\148\020\080\223\027\181\048\145\208\255\224\179\203\064\082\070\028\098\082\211\057\061\156\074\115\130\166\255\131\081\064\082\004\058\241\148\041\208\038\002\008\165\141\164\000\092\044\082\145\129\172\150\002\172\061\237\096\225\100\001\025\085\002\118\148\153\011\072\061\119\246\206\182\108\005\116\013\117\096\110\101\194\254\157\154\067\230\044\012\231\201\096\150\118\102\028\044\082\022\224\027\228\205\113\128\165\061\053\171\090\194\210\197\024\126\145\014\136\207\138\068\068\108\032\060\131\093\096\237\106\006\143\032\103\038\135\164\228\175\226\081\051\233\133\137\088\157\182\136\115\224\230\158\106\212\180\148\162\189\175\025\229\117\101\040\170\044\070\121\109\037\106\154\027\081\219\222\129\202\150\022\076\156\249\115\144\071\085\190\061\251\118\195\204\210\244\037\129\018\005\156\022\209\188\069\240\048\021\135\040\158\041\171\044\229\172\224\201\211\127\205\033\036\075\050\182\123\055\026\007\071\217\236\143\236\222\131\241\003\135\209\054\178\153\105\223\052\187\160\161\143\152\206\155\049\176\185\029\227\187\040\005\236\068\077\099\013\011\159\218\225\210\011\050\145\144\190\030\107\055\164\096\101\074\018\226\214\037\034\062\045\025\027\242\211\208\177\177\022\027\183\054\176\021\160\160\143\040\116\101\245\249\092\044\043\168\218\128\154\214\034\084\052\229\097\138\172\172\172\128\056\236\116\250\101\164\133\167\095\212\213\194\013\159\226\066\128\136\026\038\167\206\248\135\016\047\144\156\038\084\002\101\057\022\060\065\200\004\032\081\061\129\008\030\212\017\068\211\064\245\237\012\096\239\227\008\115\071\051\030\014\161\107\172\205\233\028\009\151\178\004\017\024\068\221\065\222\065\110\088\016\055\155\135\070\090\059\153\195\197\219\158\045\000\041\005\013\141\116\244\176\229\226\146\079\152\043\220\194\172\017\022\235\131\160\121\222\112\244\178\129\171\175\003\108\220\204\017\056\215\139\099\130\204\146\036\254\067\247\028\025\197\230\157\061\028\012\150\214\229\162\180\182\144\063\184\226\170\018\148\084\151\160\190\173\133\199\198\116\015\015\113\231\236\171\139\132\078\179\008\029\093\029\208\213\211\249\210\247\200\188\083\019\007\173\095\126\249\005\126\065\062\156\006\127\253\205\055\248\245\047\106\006\127\181\078\093\186\140\250\254\033\054\249\131\219\119\114\048\216\058\188\153\083\063\194\000\154\007\071\209\183\121\016\071\078\236\197\174\253\059\208\051\216\203\077\030\021\117\229\200\042\206\070\102\081\046\003\064\107\054\036\099\217\250\053\088\186\046\001\203\147\147\016\179\050\022\217\101\073\024\222\222\192\069\049\074\135\169\143\162\184\038\011\057\101\201\124\056\218\007\200\074\140\098\138\188\188\080\001\120\050\134\140\020\100\100\133\125\109\020\024\146\080\069\010\032\082\002\030\024\037\053\157\003\065\106\019\163\064\081\196\246\153\073\221\193\052\102\086\070\056\122\150\136\166\084\191\167\094\063\026\013\175\109\162\193\102\156\208\064\114\001\046\030\142\172\000\148\077\088\059\153\097\217\218\104\078\003\141\173\245\089\168\241\041\043\177\036\062\006\139\086\044\132\131\155\013\076\044\013\096\235\105\142\224\104\015\132\046\242\129\177\173\030\191\047\044\114\022\188\067\221\176\108\093\052\114\202\215\049\036\076\248\247\158\035\155\056\048\076\202\090\193\021\193\138\134\082\046\155\022\086\022\177\011\032\166\112\069\083\019\206\095\185\252\146\096\068\190\155\030\031\061\254\029\131\195\131\172\232\052\065\244\213\117\237\157\107\240\009\240\102\212\116\226\248\196\191\061\196\129\214\167\183\111\067\048\048\204\200\095\231\166\113\116\111\030\071\235\240\040\026\055\142\160\178\189\007\157\163\227\232\031\237\199\254\163\187\176\231\240\078\108\220\180\017\093\253\221\060\220\097\067\065\006\010\043\203\080\088\045\132\129\227\146\018\176\050\053\009\171\082\147\017\183\102\041\186\071\170\176\121\079\051\010\235\146\025\004\034\194\044\129\064\043\147\023\097\069\114\012\138\235\178\048\182\167\031\083\100\021\036\005\036\076\130\124\201\188\019\010\072\145\063\113\000\068\232\160\104\211\220\064\018\062\157\126\010\014\009\064\034\020\145\062\028\010\212\008\033\036\014\001\253\030\234\040\086\211\083\067\064\132\047\052\044\212\032\165\033\009\005\029\057\232\154\104\193\208\092\159\083\064\154\254\069\152\000\165\129\054\078\230\240\009\117\099\051\190\096\121\040\108\189\205\144\156\187\026\193\243\124\049\039\038\004\022\182\166\092\046\182\116\049\129\115\136\037\226\179\231\035\037\039\001\137\105\171\016\151\176\008\041\185\241\072\043\076\224\032\080\208\085\204\038\144\254\112\106\033\075\206\094\203\045\098\187\015\238\230\154\000\013\150\168\168\175\065\093\075\019\090\122\187\095\186\119\224\199\159\126\124\126\178\105\017\184\067\141\028\049\075\162\025\143\040\041\047\198\208\232\016\054\014\111\196\186\148\181\156\013\081\076\180\105\124\019\030\063\125\202\252\252\127\182\200\162\188\056\156\154\090\190\187\054\111\225\019\223\062\178\025\205\027\007\033\232\237\231\147\095\213\209\141\174\077\099\232\222\216\135\045\187\198\176\231\208\014\116\015\118\163\070\080\139\082\198\051\210\184\240\083\092\091\205\016\112\236\218\120\044\095\159\136\213\169\235\145\081\148\142\137\179\219\176\101\095\007\026\123\138\209\187\073\192\053\017\202\142\034\022\005\033\171\100\029\234\219\075\209\212\091\137\041\178\242\210\002\138\242\133\152\191\020\019\054\072\200\036\108\058\237\044\100\241\169\172\000\084\047\160\153\129\211\197\167\066\130\038\133\202\136\241\207\145\005\160\220\151\016\059\250\121\250\154\073\032\134\154\008\140\240\065\244\138\072\056\248\216\064\211\084\029\010\218\242\140\251\059\185\011\179\002\111\127\079\104\234\169\193\202\209\020\011\086\132\098\109\254\002\140\238\174\197\214\003\109\072\041\092\142\197\241\243\224\023\238\001\061\051\093\166\160\057\122\217\194\119\190\051\162\215\004\096\205\134\021\088\155\154\128\165\137\049\072\047\160\147\190\156\139\030\196\017\092\150\180\000\115\099\137\039\016\133\228\172\117\220\015\215\210\213\140\204\034\162\137\023\160\162\174\010\245\045\141\024\220\060\242\018\199\143\110\032\121\181\222\047\154\187\087\094\085\198\110\075\117\146\195\064\124\134\053\235\215\224\202\213\043\220\074\046\234\030\250\171\197\195\025\126\252\145\051\133\023\023\245\251\009\006\134\208\062\186\025\173\131\195\104\217\056\140\246\209\049\084\181\119\163\117\104\004\189\195\003\216\119\120\031\151\131\169\185\163\162\190\018\217\197\121\194\170\095\083\003\114\203\139\177\038\035\133\083\191\037\107\227\177\056\113\037\082\114\019\177\231\200\048\106\218\243\144\095\149\134\188\202\020\228\148\039\243\097\088\150\020\197\001\050\125\078\165\130\044\033\033\132\170\125\116\162\117\012\052\025\182\101\202\182\200\164\207\156\202\179\115\072\017\120\094\240\076\161\018\252\099\234\223\089\065\200\074\016\246\079\069\033\050\237\180\137\035\064\166\222\200\084\159\021\129\230\253\249\004\123\192\051\192\025\150\014\038\080\211\085\225\168\222\203\207\157\039\146\145\112\173\221\204\017\017\231\143\208\037\238\088\157\057\015\037\130\245\136\137\159\141\133\203\231\032\044\050\016\198\214\134\060\089\148\048\002\143\080\071\204\089\225\005\007\031\043\142\017\018\211\087\032\187\044\133\021\128\248\129\100\246\041\043\088\176\036\002\177\171\098\144\154\147\130\210\218\082\086\128\129\209\001\014\004\075\171\075\080\089\095\133\205\219\198\095\050\217\084\234\253\254\135\239\095\098\254\062\125\246\148\153\064\247\030\220\103\054\208\229\055\046\227\173\183\175\241\044\030\018\044\249\124\081\095\192\063\091\148\045\252\240\211\143\140\003\188\184\232\062\003\065\119\039\058\070\070\209\183\101\043\055\127\012\236\220\131\170\142\030\190\211\104\096\243\048\019\062\123\006\123\080\090\083\134\230\206\086\118\093\213\077\002\148\212\148\035\187\052\031\107\051\083\145\144\158\204\024\192\162\120\234\150\090\143\157\135\134\208\061\082\207\153\017\017\064\218\006\234\158\199\070\052\141\173\178\041\031\035\059\186\132\172\096\050\223\068\226\036\129\016\104\035\044\240\016\250\166\205\016\047\141\133\035\235\064\193\031\079\012\023\159\202\241\000\005\127\100\061\200\133\208\247\009\006\038\005\098\026\152\137\046\119\023\083\101\207\200\076\159\095\167\006\015\010\240\052\245\213\161\099\036\004\127\252\034\124\160\107\167\007\035\023\125\204\093\030\136\249\171\002\097\031\100\002\019\039\093\056\251\217\193\063\220\019\190\193\094\048\178\050\228\171\102\044\236\077\096\239\109\137\005\241\129\088\157\022\195\083\198\087\167\046\066\114\238\074\036\101\047\199\250\236\021\204\017\092\028\063\031\011\098\231\242\076\161\212\172\020\100\023\103\098\207\161\093\060\054\142\044\064\113\021\197\001\165\216\119\232\101\202\023\013\141\038\043\240\087\081\252\163\223\133\019\182\069\234\066\066\255\239\210\061\209\250\246\187\239\024\088\122\085\001\110\124\114\003\205\061\157\104\031\026\068\251\144\176\254\079\109\095\148\001\244\142\082\143\095\047\087\246\168\171\135\248\253\125\195\027\209\216\217\134\188\242\098\228\151\023\161\168\186\146\133\079\049\192\170\212\117\088\149\146\200\060\128\253\199\054\099\096\076\128\170\150\092\230\000\016\047\130\080\082\042\009\103\020\173\101\124\100\215\225\081\076\145\036\090\184\156\056\035\114\052\203\151\020\128\078\062\009\151\200\162\154\070\090\208\053\209\097\210\039\013\140\164\118\048\017\047\144\202\193\060\097\076\069\150\113\002\194\013\104\118\032\041\000\009\221\194\198\004\102\086\134\140\249\083\005\144\124\037\117\028\083\202\103\098\071\003\035\137\219\103\006\027\063\051\088\251\154\194\041\216\026\250\206\234\152\021\227\005\247\016\123\232\218\169\067\215\082\019\006\116\011\217\228\052\050\083\186\128\194\211\026\225\075\060\145\081\190\012\113\107\022\032\102\213\092\044\073\156\143\152\085\115\248\145\162\092\170\005\036\166\047\227\137\034\241\235\087\035\179\032\003\251\142\110\227\230\138\236\226\108\148\084\021\243\236\192\243\151\046\060\023\006\157\122\186\134\134\234\250\255\138\251\255\063\178\136\054\246\021\143\119\121\217\082\080\071\113\223\166\081\180\012\014\113\203\023\229\254\053\221\003\028\003\052\117\119\161\173\183\011\173\221\237\216\178\115\011\115\013\200\018\080\107\119\126\121\233\228\208\139\050\172\203\222\032\020\126\234\122\044\138\095\194\053\255\077\187\090\209\050\080\132\238\017\033\043\170\123\184\030\245\157\197\088\159\189\018\203\215\069\099\125\206\042\228\085\166\009\131\064\009\233\025\152\206\131\161\167\098\166\132\112\052\044\157\112\154\242\065\052\112\209\036\112\154\011\072\229\096\034\113\016\085\140\020\133\122\003\073\025\068\193\035\129\054\154\186\026\188\141\045\012\088\001\076\173\012\049\055\106\014\102\207\015\099\248\119\193\226\249\028\181\207\137\155\005\247\080\023\024\185\024\240\012\000\207\217\046\088\153\186\008\107\179\151\033\173\120\005\231\250\113\235\231\193\216\094\031\218\070\090\060\102\198\192\092\015\150\142\166\008\138\114\069\102\101\028\214\231\199\033\110\109\036\043\194\188\037\161\012\012\081\127\064\069\163\016\243\166\018\243\138\181\075\145\095\158\135\142\141\013\092\080\041\172\040\100\005\032\023\064\213\059\209\122\252\228\049\142\159\062\129\115\023\207\191\036\164\255\217\069\049\005\181\125\253\085\053\241\231\095\126\098\066\106\235\224\032\026\251\006\080\049\057\191\104\203\158\157\056\124\108\031\182\238\222\140\193\177\126\028\061\121\024\245\109\117\200\045\201\070\117\067\053\242\203\011\081\092\083\198\150\128\128\160\181\025\105\088\147\145\134\184\053\203\209\051\220\200\212\248\206\145\010\244\141\213\115\053\144\010\100\149\205\121\124\250\151\174\093\136\180\252\004\172\205\090\038\180\000\020\244\145\224\249\113\146\028\194\065\160\248\052\225\125\065\026\010\060\218\077\195\088\147\123\007\245\204\245\153\240\193\052\114\170\018\078\210\186\041\022\160\012\129\208\065\074\237\184\128\099\097\000\125\099\109\190\006\142\102\251\049\251\152\006\072\025\105\194\216\198\016\166\014\198\144\215\145\135\188\161\044\252\230\122\112\215\010\093\028\065\001\225\172\069\030\152\183\034\008\179\034\003\184\032\068\136\033\197\020\070\150\250\240\158\227\128\220\186\101\200\175\139\071\086\197\042\238\014\078\072\091\138\192\121\062\152\191\100\054\018\211\086\032\046\062\006\209\203\022\096\217\154\037\200\040\164\116\136\176\128\034\174\164\149\214\008\099\128\207\095\152\186\069\235\234\181\171\248\242\235\255\053\115\253\068\139\126\031\141\173\127\213\093\080\080\072\089\199\201\243\231\024\142\110\232\037\005\104\067\089\099\019\142\157\062\136\239\126\252\000\031\222\058\141\083\023\014\096\226\244\126\102\004\019\195\153\218\189\201\125\165\230\165\051\023\048\045\063\011\201\185\025\088\179\033\021\107\051\018\048\190\167\023\155\118\118\096\211\174\118\012\109\037\110\068\033\042\155\115\024\016\034\087\176\058\101\049\170\154\242\209\187\185\145\106\001\051\216\002\136\075\077\231\188\127\038\221\030\050\073\016\161\201\160\060\026\094\106\058\183\131\081\099\008\205\006\020\013\149\166\083\073\179\004\104\178\008\005\117\138\202\242\012\014\017\050\040\079\110\066\094\130\179\002\074\159\168\037\044\050\102\046\019\068\169\104\068\238\128\148\069\090\129\026\067\164\033\173\034\005\021\067\069\088\184\026\195\208\086\007\054\094\102\208\176\080\129\166\009\141\144\113\126\222\077\068\219\202\193\012\014\254\230\072\042\092\128\186\238\052\044\079\011\071\212\170\016\044\138\159\139\240\152\032\132\204\011\198\188\232\057\108\105\022\045\143\193\178\196\056\036\101\036\032\167\052\029\057\165\089\168\105\170\065\081\069\033\055\078\094\255\232\067\054\195\180\040\024\188\117\251\214\159\240\254\255\217\069\048\242\185\139\047\223\062\070\177\000\101\023\020\116\246\080\051\103\095\063\106\187\251\080\221\222\206\087\218\084\054\213\114\221\158\186\156\182\237\239\197\200\246\014\244\109\106\065\075\111\029\106\155\041\131\105\016\118\062\083\049\040\063\011\107\054\164\096\085\202\058\100\149\164\098\255\177\081\244\110\170\067\109\071\014\090\007\074\081\209\156\133\242\166\108\198\070\250\055\053\099\085\202\098\006\130\134\183\183\147\002\076\019\008\133\079\130\159\100\005\177\053\152\193\194\127\109\250\063\120\083\228\079\052\049\050\251\228\030\104\028\028\149\122\137\016\162\174\167\206\213\058\198\002\148\229\158\247\021\008\185\004\146\156\038\082\005\144\010\065\243\022\206\129\153\141\041\115\011\040\253\163\002\147\056\161\136\050\226\144\083\151\129\154\169\050\148\012\021\160\097\166\010\117\083\021\104\026\168\195\196\220\144\127\158\170\108\116\219\152\173\147\021\156\253\109\048\119\165\023\230\199\123\035\050\193\023\113\235\230\177\127\139\088\028\140\208\249\193\076\058\157\031\051\135\103\008\046\139\095\138\053\041\009\072\206\094\143\250\182\122\158\150\081\080\150\143\230\078\042\217\062\096\024\151\186\128\232\132\222\124\225\234\152\255\085\139\020\139\170\131\162\069\232\226\207\196\038\254\224\061\052\117\146\175\030\224\094\191\154\206\110\230\039\212\180\181\161\174\085\128\174\129\086\110\224\236\025\110\198\129\137\029\124\122\027\187\202\209\208\081\201\205\158\025\133\153\040\174\042\069\102\097\046\146\050\083\176\050\121\013\054\020\164\096\223\196\038\012\140\215\163\178\053\011\085\045\057\220\003\072\176\047\213\073\040\255\079\220\032\068\005\147\243\086\017\033\228\117\001\003\062\147\167\158\079\191\072\001\196\132\010\064\117\000\186\056\130\132\074\120\063\177\127\137\060\074\160\015\153\127\010\004\137\031\064\117\001\002\133\040\032\164\223\069\040\033\177\138\152\073\044\043\206\067\035\060\125\221\057\035\032\102\017\165\155\164\008\196\057\032\024\089\081\075\001\250\022\058\208\049\211\132\182\153\038\052\076\212\160\162\067\152\130\016\061\036\151\066\220\066\034\134\056\251\216\099\222\010\127\044\073\014\067\098\078\052\150\038\207\099\082\200\194\021\115\017\054\111\022\102\071\134\241\240\200\168\216\072\158\044\186\054\109\013\114\075\115\185\138\070\061\243\101\181\101\040\171\041\067\122\118\058\190\163\008\253\135\239\113\233\234\101\110\239\254\127\099\081\075\056\053\146\080\234\072\153\196\213\183\174\050\142\080\086\087\141\190\205\155\152\136\210\060\176\017\130\222\062\212\118\180\161\190\077\128\142\254\022\102\001\239\058\064\253\000\003\028\217\159\123\227\000\058\007\009\223\207\103\174\067\073\109\062\082\114\146\177\161\032\011\233\121\025\136\079\094\141\166\238\010\180\015\086\160\166\181\128\203\193\117\109\037\104\233\171\070\110\069\050\167\129\212\094\191\058\053\150\001\033\086\000\017\210\071\086\128\054\041\003\041\000\157\120\017\008\068\200\032\145\069\069\005\031\033\105\148\004\039\108\034\033\028\128\232\099\020\012\018\173\140\149\073\082\168\052\164\004\204\043\160\081\243\074\212\112\034\199\119\006\113\087\016\113\012\169\221\156\250\003\117\105\174\144\001\002\066\125\016\028\017\008\003\083\029\030\039\067\049\004\165\147\100\001\012\076\244\249\131\115\244\176\195\194\021\225\088\151\179\028\011\086\134\098\206\178\000\118\003\243\023\071\032\100\206\044\204\094\016\134\200\069\115\177\104\089\052\150\039\044\069\210\134\181\076\151\038\044\157\082\042\074\003\009\082\053\183\054\135\187\167\059\231\249\111\191\247\054\155\235\127\182\232\036\115\222\127\239\030\111\154\203\079\126\252\095\053\139\138\022\185\022\042\030\017\102\064\087\204\081\039\053\149\210\091\123\059\185\224\067\125\009\212\222\221\212\075\209\127\039\026\059\154\121\168\067\109\075\053\090\122\107\177\247\200\054\028\056\190\025\059\014\245\098\120\123\027\119\249\236\157\024\065\207\104\013\106\219\010\144\085\154\134\245\089\073\088\185\102\037\210\242\146\144\083\177\142\083\064\138\141\074\234\050\081\092\155\129\180\194\068\100\148\172\229\110\106\234\170\098\082\168\184\244\012\070\002\073\208\034\011\192\138\064\110\097\210\053\008\183\240\249\076\126\093\168\028\228\014\008\013\100\198\048\129\071\147\061\003\132\014\242\117\051\226\175\063\135\151\137\070\078\029\196\228\014\200\247\019\117\092\077\095\200\028\038\062\033\013\140\208\048\213\128\103\144\027\060\253\093\248\150\176\192\048\127\038\136\218\058\089\194\196\210\016\006\166\186\076\051\163\120\128\168\229\115\098\102\241\148\016\170\255\019\007\048\189\104\013\022\196\205\065\200\156\096\182\000\243\023\205\065\220\170\197\088\181\118\005\207\022\038\078\224\232\214\077\028\003\020\087\021\162\182\169\022\046\030\046\124\187\135\169\133\041\207\004\252\087\056\190\104\138\007\241\000\069\099\090\041\093\252\087\063\035\090\239\125\240\030\082\054\164\192\195\203\131\187\135\169\242\170\173\167\205\247\031\013\109\029\197\192\230\001\086\130\206\141\093\232\027\233\196\224\088\015\054\110\238\066\099\103\053\134\183\244\098\226\244\030\140\237\105\193\225\051\067\024\219\219\140\130\186\245\104\232\201\065\255\022\178\032\117\044\236\228\220\120\038\125\212\183\151\096\251\129\110\108\220\210\128\250\174\060\020\215\110\096\240\103\067\241\090\020\212\164\035\062\117\009\226\018\022\162\168\134\248\000\146\051\004\004\225\138\132\255\162\037\120\073\248\188\133\095\179\053\152\028\000\065\024\002\011\120\018\074\166\108\128\042\130\116\213\012\253\046\081\035\009\089\000\082\000\178\018\138\147\099\231\084\041\173\156\188\164\130\111\022\177\212\131\145\141\033\244\076\117\248\162\073\050\221\212\072\018\062\063\132\171\136\228\058\040\008\036\064\201\217\205\001\193\115\125\049\127\073\040\234\218\139\153\018\190\096\249\108\068\044\158\133\240\005\033\124\193\004\089\000\250\249\196\228\120\036\103\174\099\102\112\118\113\014\159\126\026\158\064\129\148\141\189\053\084\212\085\240\183\215\254\134\204\236\204\087\229\246\151\075\052\188\145\210\059\098\003\255\059\010\064\181\131\255\252\219\127\240\040\090\037\101\037\046\184\209\080\201\246\254\046\012\111\027\197\232\246\081\140\239\026\199\225\019\187\113\233\237\189\184\248\206\040\174\221\024\197\197\119\251\240\193\103\219\112\253\206\024\110\124\185\029\063\062\058\138\029\071\171\177\253\080\003\246\157\172\195\133\119\123\024\058\167\248\064\208\085\194\104\104\101\107\058\038\046\180\097\199\225\090\148\183\172\195\186\252\069\200\042\079\224\209\057\025\037\107\016\187\122\001\095\216\221\057\088\047\116\001\186\070\090\066\179\205\065\032\197\000\162\088\224\069\225\191\098\017\164\166\051\081\068\200\020\162\102\017\137\231\164\081\138\017\036\100\197\248\061\220\254\173\040\205\181\114\017\098\072\000\146\002\205\013\212\084\226\086\115\034\139\208\020\114\162\147\209\228\113\154\048\074\169\162\207\044\119\196\037\068\035\122\217\124\038\147\112\015\161\137\030\151\133\137\099\072\247\017\211\069\147\203\146\022\098\225\138\008\204\093\018\138\057\177\033\136\088\024\202\025\192\146\073\223\079\055\141\036\165\173\193\250\140\117\072\201\077\227\194\016\161\106\020\003\024\155\026\241\032\168\153\226\051\145\148\044\188\226\229\159\009\148\176\126\054\255\247\239\011\093\192\207\063\115\177\136\006\060\240\220\000\066\009\159\009\153\068\124\229\236\211\167\066\180\240\209\035\228\020\228\242\196\049\101\021\101\030\033\071\035\100\168\005\189\099\160\027\035\219\136\125\060\128\225\173\125\216\117\104\020\135\078\141\224\226\187\035\248\246\193\046\060\192\097\252\142\019\248\245\233\062\252\242\120\047\126\126\188\015\231\222\110\193\241\043\013\120\247\086\047\190\248\121\059\250\183\081\074\087\131\205\123\154\080\217\146\129\218\206\116\156\186\042\192\241\203\117\216\118\184\002\219\015\087\161\125\036\015\157\035\053\040\109\200\192\162\085\115\249\118\182\238\077\053\152\162\196\179\130\009\247\167\046\096\097\249\151\021\128\031\201\029\188\168\000\194\186\255\139\074\064\039\156\078\182\168\161\148\208\067\186\124\130\002\067\162\141\025\083\123\184\158\198\115\218\024\089\012\009\138\248\149\133\211\201\233\061\196\044\162\206\036\138\003\008\100\162\212\210\192\066\007\126\097\238\008\154\227\013\239\096\087\056\121\218\115\150\065\191\139\152\194\116\171\088\080\184\063\226\086\199\096\241\234\072\038\132\046\077\090\136\185\177\161\156\251\211\077\163\073\233\107\145\093\152\197\200\089\090\118\042\043\001\145\040\138\170\138\121\180\044\221\051\164\163\175\195\013\160\018\082\018\152\051\127\046\015\102\036\102\047\249\119\209\229\138\036\076\033\245\091\120\003\007\009\088\036\104\122\078\213\067\142\007\126\250\233\121\124\064\085\191\023\047\179\008\014\013\230\211\175\168\164\200\067\053\073\001\212\052\212\208\059\212\139\177\093\212\127\176\025\091\247\140\097\251\190\205\024\223\061\136\129\177\102\236\061\214\142\055\174\015\224\238\015\219\241\229\047\219\240\249\079\091\240\253\195\189\184\243\195\054\092\185\222\129\131\231\075\112\224\124\049\218\071\082\081\211\153\142\246\225\066\228\215\038\034\175\118\021\078\093\109\199\217\107\045\184\248\094\015\134\118\150\160\164\041\017\093\035\213\140\007\208\129\161\207\107\116\079\035\166\168\105\170\008\232\244\210\201\127\241\132\011\003\067\114\009\147\089\193\100\154\248\060\070\152\220\066\008\088\156\173\001\095\061\167\169\200\152\000\069\236\228\090\168\073\148\112\000\081\058\040\164\154\011\149\133\177\003\117\005\070\019\233\210\074\106\052\161\027\072\140\172\013\097\237\102\001\143\096\023\216\121\091\193\059\204\013\182\174\150\060\109\148\044\009\113\008\232\030\161\128\016\063\078\243\098\087\069\099\069\082\044\150\036\044\196\130\165\243\176\100\213\034\172\076\090\142\245\153\235\176\122\221\042\172\073\075\196\218\244\181\072\205\078\070\106\110\042\151\131\105\180\108\065\089\001\212\052\201\050\209\028\100\025\152\088\152\048\171\247\135\031\127\018\078\244\252\233\039\014\242\136\221\075\163\216\104\246\062\009\155\218\192\072\025\030\061\126\204\175\209\251\072\113\072\240\196\015\164\169\220\116\165\221\157\187\159\227\235\111\190\197\197\043\151\217\223\019\215\146\021\064\142\024\088\226\172\000\215\222\125\011\119\062\255\024\055\111\189\139\047\190\250\024\119\191\248\008\031\221\124\015\111\092\187\130\083\231\143\225\232\169\003\184\252\246\110\092\253\112\035\174\094\223\140\155\095\237\198\055\247\247\226\167\223\143\224\203\159\119\225\235\095\246\225\139\031\014\096\255\201\102\108\222\211\128\193\237\021\104\232\205\192\209\115\061\216\057\081\138\173\135\138\209\050\152\137\242\214\181\024\217\081\143\186\206\060\174\010\210\048\141\125\039\039\131\064\138\196\185\254\255\130\112\069\229\095\161\069\160\242\175\240\251\127\142\017\166\115\214\064\166\157\059\135\040\037\228\177\112\026\236\010\040\075\224\174\034\069\089\198\008\136\066\206\004\146\201\006\019\058\241\020\003\208\251\200\122\168\234\168\010\047\160\048\215\129\163\159\029\236\124\172\097\229\101\006\051\071\035\040\105\041\112\015\033\213\045\136\085\228\027\228\197\232\226\156\232\112\068\198\206\229\027\201\162\151\046\064\220\234\069\136\079\093\137\248\148\120\172\072\090\129\021\107\151\113\022\144\150\155\134\212\220\052\102\007\147\027\072\206\072\134\034\013\181\082\149\231\255\003\013\186\238\238\239\225\070\079\234\251\167\083\077\081\059\125\125\239\254\003\006\111\072\001\132\001\160\208\045\144\117\032\037\161\066\015\185\003\026\004\073\194\167\211\079\067\160\232\119\208\152\022\234\176\082\086\086\022\014\214\150\147\229\225\145\106\026\234\248\234\155\079\137\117\064\229\034\154\050\048\249\072\099\105\132\180\051\250\119\158\062\125\140\071\143\239\226\254\195\079\112\247\235\203\184\243\237\073\252\112\255\034\158\226\061\060\193\219\120\006\194\046\238\226\025\238\226\209\147\143\240\219\227\143\113\239\225\117\252\240\203\053\060\248\253\026\222\251\100\027\246\159\108\193\133\183\135\113\226\114\031\050\074\086\098\093\110\044\062\184\189\157\198\197\203\191\020\004\190\108\001\254\072\015\255\090\001\132\194\167\215\184\125\140\088\193\060\001\076\216\065\196\244\176\201\190\066\206\020\104\084\140\178\060\148\084\233\142\034\186\133\076\216\108\074\031\062\041\014\197\004\052\080\146\122\001\053\077\180\096\225\106\142\128\185\190\240\137\112\135\170\190\010\020\053\021\184\146\072\029\066\212\055\064\173\099\148\230\069\197\205\199\156\152\048\204\143\141\224\189\036\126\017\086\039\047\199\210\196\056\036\166\039\034\171\048\019\013\029\085\060\092\154\176\000\162\131\149\213\150\034\062\105\053\100\229\100\120\170\039\157\076\098\065\057\056\059\112\003\040\009\142\132\072\194\165\147\077\190\156\186\128\073\001\200\231\147\095\167\110\032\082\022\250\062\089\012\122\047\253\012\153\124\026\239\254\213\215\223\224\163\155\055\209\063\216\015\053\013\085\014\254\104\124\012\089\000\073\009\009\040\171\042\225\246\231\196\064\254\010\079\158\125\134\039\207\062\193\147\103\183\240\244\217\093\060\123\246\057\158\225\197\017\053\164\036\004\081\019\159\224\091\060\195\215\120\250\236\043\060\125\246\005\063\062\163\013\194\048\168\222\064\239\161\071\082\168\175\112\251\171\147\120\231\198\056\062\251\110\007\091\143\202\142\053\088\145\017\134\015\191\028\194\020\053\109\021\001\005\092\047\010\246\085\038\208\171\251\185\002\076\214\014\232\145\231\005\202\075\009\227\132\201\230\082\006\138\094\232\042\022\013\158\038\120\152\166\145\144\207\023\178\135\228\120\166\000\013\159\032\139\064\117\006\106\006\117\246\115\128\103\136\027\236\060\044\097\106\067\229\096\053\152\217\024\049\153\132\210\064\082\000\202\020\232\054\209\149\235\151\033\050\110\014\230\045\009\199\252\184\217\088\184\108\062\226\083\086\115\051\072\077\019\117\008\211\232\248\070\180\246\054\240\216\020\106\159\094\155\146\196\163\092\040\040\163\123\002\232\154\183\025\098\051\144\176\054\129\205\056\157\106\058\205\034\243\254\240\183\071\076\249\034\139\240\148\079\230\051\086\002\082\014\114\027\034\243\079\086\128\124\063\205\247\111\108\107\068\111\127\143\112\132\222\164\249\103\005\144\148\128\162\178\018\110\126\118\138\166\011\225\225\211\243\184\255\228\036\239\007\079\207\225\209\211\055\240\248\217\117\060\123\070\252\066\010\040\127\157\220\063\225\233\179\111\038\133\079\074\032\250\250\213\253\229\164\114\144\210\144\050\124\136\095\159\028\198\215\247\182\097\116\111\062\098\211\188\241\230\039\173\084\013\148\230\114\240\076\201\063\078\255\139\010\064\110\064\200\010\154\012\010\039\241\001\097\134\064\194\167\116\080\136\005\208\105\039\225\051\153\100\082\017\216\045\208\045\099\100\025\168\187\152\046\145\208\036\065\171\114\176\072\175\211\101\020\052\120\146\202\189\154\198\154\048\160\217\128\238\054\240\154\237\139\208\168\089\008\158\023\008\067\091\003\024\218\024\192\194\209\132\083\068\079\031\055\120\007\122\048\218\183\046\115\029\146\179\147\177\104\069\020\011\062\122\229\124\196\038\046\192\186\236\213\200\040\074\069\073\109\046\243\225\058\055\054\097\108\039\181\124\181\096\219\190\045\200\046\200\134\184\164\056\043\000\109\186\016\138\198\195\009\154\004\184\112\249\034\222\251\224\125\124\122\235\022\099\246\036\220\207\191\252\146\041\223\052\149\155\202\198\132\234\209\100\144\027\159\126\194\067\034\232\107\086\154\239\190\227\041\230\004\228\228\149\228\097\211\248\102\062\249\034\255\047\084\000\073\086\128\027\183\142\082\009\010\191\062\153\192\047\079\142\076\238\195\248\229\201\033\220\127\114\010\079\158\221\038\071\051\025\116\062\193\211\103\223\226\233\179\207\241\228\217\199\147\251\083\182\028\079\113\019\079\241\041\158\241\254\140\221\129\208\074\144\130\220\195\179\103\063\226\225\211\139\248\242\215\157\120\239\214\102\100\086\047\198\149\027\141\194\114\048\165\128\047\251\245\063\098\000\033\238\047\114\003\194\128\143\002\063\033\037\108\038\003\060\194\084\111\210\204\211\213\113\074\050\028\212\145\018\112\039\049\093\034\073\051\006\038\047\168\164\138\158\153\181\009\119\012\243\072\026\005\186\097\068\002\082\202\210\194\137\165\070\026\060\047\208\136\058\139\124\157\120\090\136\169\163\041\156\124\029\224\224\099\015\027\087\235\201\070\019\015\206\245\087\037\173\228\200\159\246\146\085\139\177\124\093\044\086\165\198\033\057\055\001\025\197\105\200\175\204\068\185\032\023\077\093\213\024\221\217\201\013\164\195\091\123\225\027\236\203\227\225\073\248\242\242\242\080\082\086\102\133\168\107\168\099\116\239\212\249\179\056\121\238\012\223\071\072\119\018\147\240\105\211\085\050\084\063\160\251\119\063\187\067\243\130\190\194\245\143\063\226\121\001\052\013\156\174\175\163\171\234\232\066\235\075\087\223\192\142\221\059\032\037\051\121\177\134\156\028\111\086\000\021\069\220\184\053\001\224\013\220\123\058\129\095\159\028\123\097\079\176\002\176\021\224\152\224\087\060\195\023\248\253\217\155\108\045\126\254\253\032\126\254\125\063\238\061\057\130\159\030\237\195\119\015\118\227\155\123\123\240\213\175\187\241\245\175\123\240\221\253\131\184\247\251\121\086\144\103\207\168\010\249\008\207\240\057\126\123\122\005\015\030\191\129\059\095\094\198\163\167\111\099\138\182\158\058\035\129\204\007\120\209\013\076\250\118\017\047\144\021\128\004\047\051\083\136\001\144\224\137\072\074\023\070\077\182\147\083\021\144\002\061\178\010\100\005\008\028\018\014\146\164\206\034\097\115\041\015\154\162\193\018\026\074\172\004\068\064\033\023\068\029\069\218\230\058\160\193\213\052\055\144\046\159\162\065\212\052\026\134\110\034\211\183\214\231\109\238\100\138\192\217\254\240\011\246\097\086\113\196\130\112\014\252\102\199\132\240\201\095\158\180\004\105\249\235\081\084\157\135\220\242\108\020\085\231\163\172\174\064\216\023\208\095\135\206\161\042\244\140\214\227\224\137\045\240\014\112\135\056\041\000\009\070\094\014\074\042\202\172\016\203\086\044\099\175\075\230\159\132\249\206\251\239\241\149\244\116\178\233\062\062\186\186\158\132\077\138\113\253\163\143\248\123\239\095\255\000\231\046\093\224\219\075\105\044\012\189\239\194\149\043\184\113\235\099\236\220\051\198\163\245\149\148\021\133\119\043\200\201\066\138\045\128\050\110\222\058\133\039\056\135\031\127\059\196\130\125\244\148\004\115\133\093\192\239\180\159\093\197\079\191\029\199\055\191\030\198\183\247\014\227\231\223\143\224\199\071\251\240\227\163\061\248\230\254\054\220\254\097\028\031\125\217\139\171\055\090\176\239\116\049\118\076\020\098\236\096\022\206\190\043\192\237\031\199\112\239\201\004\187\148\007\079\206\227\215\223\079\226\215\223\143\225\193\211\211\052\009\153\099\138\041\042\154\074\002\057\229\063\020\224\185\105\039\094\192\164\002\208\235\100\037\168\055\144\252\186\072\001\184\119\240\149\064\143\132\043\130\131\105\179\192\185\181\108\114\174\048\215\010\102\114\165\145\092\004\081\207\168\192\067\060\003\021\125\085\022\056\221\050\202\152\002\005\134\186\042\048\176\054\132\215\044\111\004\206\011\132\139\191\011\172\156\045\017\060\039\136\179\000\170\025\172\203\076\196\226\132\249\136\092\030\134\101\235\098\184\009\178\190\163\012\141\221\021\092\024\033\159\223\059\210\198\013\022\212\020\217\183\185\030\167\046\111\065\066\242\018\076\157\049\085\120\231\145\002\089\000\037\158\007\068\144\237\139\139\154\063\168\035\136\074\199\068\032\161\083\079\126\158\076\062\141\137\161\071\178\012\111\188\245\038\015\131\160\214\050\186\215\152\020\224\194\213\179\104\235\169\133\140\130\052\143\209\021\041\000\181\222\201\043\040\226\227\079\078\226\049\078\225\238\079\091\241\237\253\125\120\240\244\020\030\062\061\139\223\113\025\143\113\005\079\112\005\095\253\178\019\055\190\026\194\157\031\183\227\214\247\227\184\245\221\024\126\252\109\047\126\122\116\004\223\223\063\134\239\238\029\198\039\095\109\195\161\179\002\140\029\040\192\161\243\213\184\253\253\086\252\242\248\024\238\061\057\198\202\242\237\131\077\248\252\215\014\124\241\107\015\190\190\063\138\031\126\219\001\224\138\048\006\032\225\138\124\062\157\124\081\054\032\122\141\000\034\202\243\089\001\200\231\147\050\016\004\060\137\243\255\033\124\041\182\002\004\012\081\092\192\243\134\068\227\101\184\250\071\095\203\176\098\080\053\145\082\063\206\020\020\165\160\160\166\192\215\206\211\196\114\186\065\132\175\179\213\086\230\251\005\104\016\165\087\128\007\095\025\055\107\110\016\204\156\076\225\226\227\140\176\185\179\216\026\172\203\094\133\172\178\068\068\199\135\099\117\090\044\207\013\166\218\064\093\103\001\154\122\075\208\063\214\136\145\237\093\024\225\009\162\027\185\168\178\117\095\047\116\077\052\033\037\043\197\130\167\000\080\069\077\021\114\010\178\040\169\040\121\073\001\094\092\084\202\037\102\015\005\132\228\239\073\232\039\207\158\230\203\024\233\026\057\186\174\158\166\130\221\249\252\115\124\116\243\019\028\061\125\008\089\069\041\252\153\136\020\128\058\177\164\036\169\015\067\026\087\223\217\131\199\207\046\225\251\007\019\184\255\244\004\126\195\113\252\250\244\040\110\124\181\009\055\190\028\197\015\015\015\227\033\078\177\139\184\247\244\024\155\249\027\095\015\227\193\147\051\120\242\236\003\060\003\249\255\143\240\004\215\240\004\111\226\119\092\196\099\156\231\159\121\244\140\044\201\021\220\123\114\002\191\060\062\140\095\031\079\224\222\147\147\248\229\247\195\248\225\183\093\000\038\048\197\221\215\085\064\055\133\147\079\127\049\216\019\109\062\249\052\049\116\242\078\061\209\233\023\117\012\191\040\252\231\074\160\036\195\215\206\016\063\144\058\123\073\240\034\168\152\128\034\122\046\116\019\194\001\081\060\067\208\072\007\250\102\122\220\071\072\232\032\145\078\040\062\160\030\002\114\019\212\073\020\017\025\142\089\017\193\048\178\054\128\185\157\025\220\253\092\225\031\234\139\212\188\068\084\180\100\033\181\096\021\114\043\105\014\078\010\211\161\075\005\153\076\132\168\235\200\071\235\064\057\218\006\075\208\063\094\135\131\039\071\240\198\187\135\097\231\104\003\041\105\105\168\170\171\114\071\180\166\054\013\176\148\225\014\095\209\034\204\255\215\123\212\027\240\035\190\254\230\107\038\140\222\186\243\025\174\240\004\176\043\120\255\195\015\024\008\162\076\128\074\202\148\251\019\034\072\129\225\167\183\062\195\196\153\067\200\044\072\225\235\246\228\021\133\003\164\185\237\142\238\021\148\146\066\239\104\021\206\188\213\143\061\019\221\056\123\117\004\087\063\028\198\217\183\186\177\235\088\041\198\015\020\224\192\153\042\220\248\114\004\095\252\188\013\063\252\182\031\015\112\156\131\196\223\158\157\103\247\240\232\217\027\044\104\250\250\241\179\055\241\248\217\085\252\254\244\042\126\123\122\105\210\141\008\191\038\247\242\251\211\055\133\251\217\155\248\237\233\069\106\107\193\020\039\087\007\001\081\184\233\084\146\002\136\148\064\088\244\153\206\167\094\084\207\023\022\129\008\223\167\094\000\161\047\127\085\248\034\043\032\010\006\137\026\070\074\064\204\098\190\126\134\007\082\042\176\050\144\018\144\169\167\082\047\207\029\166\050\051\005\151\147\077\042\020\027\136\198\201\208\192\041\115\027\019\120\250\187\195\212\218\152\153\069\206\030\142\240\009\246\194\146\248\133\220\020\066\213\174\013\069\107\145\093\190\022\185\149\235\081\034\200\120\190\235\187\243\208\178\177\008\237\067\165\216\113\168\019\155\118\116\008\065\032\005\069\078\209\072\001\040\047\119\241\112\198\187\031\188\199\002\039\097\127\241\213\023\252\072\038\158\034\125\186\245\227\198\167\159\178\208\009\016\034\032\136\082\068\178\006\047\222\234\073\074\064\023\089\031\057\181\031\057\037\169\144\150\149\100\048\076\104\001\100\216\002\076\159\049\003\141\157\133\056\119\173\007\219\015\213\160\119\172\024\237\195\057\232\024\161\255\107\038\004\125\233\104\236\079\198\254\051\165\120\255\246\000\046\190\223\196\143\164\016\031\127\053\196\208\240\151\191\014\225\235\251\195\028\016\254\246\236\028\126\125\114\002\015\158\156\197\131\167\103\240\240\233\005\182\000\194\020\243\052\111\225\215\103\240\243\163\195\116\223\009\166\200\043\201\010\200\188\139\078\188\168\044\076\193\030\009\156\125\061\221\003\072\036\015\009\097\189\128\020\130\114\121\018\050\009\092\104\013\164\132\166\156\091\198\036\038\097\227\105\252\243\207\003\070\114\025\147\028\066\054\241\154\074\044\120\026\252\064\148\114\042\008\145\002\136\038\145\019\193\132\020\128\250\012\220\125\221\016\016\234\015\007\055\059\238\030\246\240\115\227\217\001\190\179\188\049\127\241\092\172\072\142\197\202\212\088\036\101\175\068\097\109\042\202\155\050\080\042\200\064\121\115\038\074\027\051\081\211\145\131\198\222\124\180\108\044\196\216\190\022\068\175\152\141\025\098\051\057\242\167\244\140\092\000\161\117\011\098\022\008\047\102\124\244\136\065\031\202\249\111\222\018\010\159\056\003\162\066\017\157\120\170\239\019\250\247\207\046\133\164\056\097\235\222\017\084\053\229\113\043\061\091\000\005\057\200\202\200\240\060\006\186\129\052\175\116\045\110\125\125\004\087\063\236\197\196\165\090\108\059\082\130\222\045\057\104\026\072\067\085\251\090\084\117\196\099\096\215\090\116\111\095\137\130\182\096\244\238\088\142\109\199\087\098\231\233\229\056\112\105\021\014\189\177\012\231\174\175\197\249\235\169\184\254\101\013\238\252\212\129\111\030\142\224\219\135\035\248\230\193\048\190\125\184\153\031\191\188\223\141\111\030\014\225\235\007\003\248\242\126\023\062\191\215\132\223\049\130\041\210\242\146\002\142\236\095\041\007\147\075\032\005\096\114\200\011\223\035\005\160\025\001\060\027\128\230\007\078\006\118\100\226\069\149\065\225\207\010\203\198\212\251\079\117\001\170\227\019\179\135\004\074\053\000\035\011\003\054\251\068\041\167\050\047\213\001\072\248\116\047\033\221\059\200\003\036\053\149\133\051\008\013\052\017\058\119\022\114\138\115\048\039\042\130\045\128\157\171\013\028\221\029\224\029\232\137\249\209\115\177\060\041\014\203\214\199\032\097\067\028\050\075\215\162\172\041\147\021\128\132\079\238\161\101\099\049\004\189\249\104\030\040\064\239\120\021\076\236\244\033\043\039\039\172\206\041\042\242\163\140\156\052\210\050\211\184\017\132\078\052\181\112\147\037\032\033\211\034\225\019\097\132\186\123\232\181\255\142\059\120\255\254\125\156\184\056\142\061\071\250\152\042\047\167\032\199\001\167\232\058\185\127\188\246\058\010\042\018\112\238\221\038\156\188\090\135\171\031\119\112\145\231\196\149\070\028\062\095\139\045\007\243\177\121\127\014\142\093\169\192\254\243\217\024\060\176\016\059\079\199\225\216\181\229\184\242\105\034\046\127\146\128\055\110\173\197\245\111\210\113\250\253\149\184\250\217\026\220\254\053\015\119\239\023\225\206\253\018\124\246\075\014\063\191\125\175\024\119\038\095\187\125\175\000\119\238\229\224\206\131\066\220\071\045\166\232\025\233\114\026\040\058\253\207\083\193\073\166\048\013\140\166\046\032\166\133\077\022\140\072\097\120\250\055\221\040\058\153\226\137\054\067\198\034\011\066\099\230\008\233\227\121\067\178\092\017\036\115\079\229\095\234\053\160\081\112\228\243\185\022\192\141\039\211\249\030\098\066\009\169\173\140\098\003\082\024\207\000\055\196\174\140\198\242\053\075\153\216\065\001\033\221\060\230\224\102\015\175\032\079\204\093\056\027\011\151\046\192\242\245\139\216\013\016\243\037\183\050\025\197\013\027\080\213\154\131\230\254\034\116\012\151\161\109\168\004\093\155\202\209\212\091\196\083\073\149\084\132\193\031\009\159\220\000\125\221\220\222\194\066\022\221\220\041\090\084\013\164\180\080\052\027\248\223\089\191\220\251\030\079\113\013\099\059\107\049\083\074\156\255\061\069\037\165\231\110\096\250\180\025\240\244\119\196\149\143\186\049\113\169\002\123\079\021\096\215\241\002\108\220\158\133\209\061\185\024\216\181\014\003\123\018\113\240\124\033\206\188\083\132\137\183\086\225\196\059\241\184\116\035\025\215\191\217\128\111\030\151\225\214\079\233\184\249\067\038\062\254\126\003\110\252\144\193\194\253\252\065\030\190\120\088\136\047\030\022\225\243\007\133\248\252\097\049\238\222\207\199\157\123\089\184\123\063\015\183\127\201\192\237\095\114\240\016\245\152\162\169\167\046\032\074\150\072\224\207\017\063\081\042\040\246\058\043\000\183\130\205\124\237\249\247\120\112\212\036\217\131\039\136\062\031\035\067\177\130\080\073\196\101\133\019\069\069\041\033\087\001\085\228\056\038\160\180\143\110\028\055\178\051\129\161\173\049\003\071\211\037\168\207\064\130\163\127\186\093\036\110\229\018\230\197\085\055\021\195\051\208\149\091\196\169\082\104\102\099\194\035\230\028\092\237\225\051\203\011\017\081\225\092\245\139\092\058\135\059\095\137\239\158\090\144\128\204\210\036\228\085\165\160\188\041\019\173\027\075\209\061\090\137\145\157\002\020\214\173\199\063\036\104\018\250\116\158\090\078\056\061\009\159\170\115\231\046\188\204\222\125\117\081\061\128\044\000\149\138\255\153\233\023\173\159\127\037\024\246\109\092\126\107\007\180\245\169\026\072\104\160\018\195\206\004\006\077\155\054\029\110\222\246\156\198\221\249\097\028\239\125\214\143\115\239\008\112\240\108\025\014\156\045\195\174\227\133\024\222\155\130\142\045\113\232\217\190\002\253\123\150\163\099\219\098\180\109\137\198\192\190\104\140\031\095\130\222\221\081\104\221\050\015\221\059\023\160\103\119\020\134\015\197\096\215\217\165\056\243\065\060\222\251\034\021\031\125\155\134\207\126\201\198\059\159\039\227\250\087\235\112\243\135\012\092\187\179\014\087\062\073\196\087\143\242\133\179\130\101\020\037\159\215\250\057\245\123\165\040\244\218\180\127\060\183\002\140\253\079\090\008\017\016\036\156\039\056\057\074\086\097\178\030\064\241\003\041\200\036\032\036\004\144\040\133\156\041\036\139\170\043\064\221\064\157\089\064\242\154\194\233\162\004\011\207\148\154\201\063\071\147\054\104\192\244\154\212\213\088\184\116\014\043\128\141\051\077\030\117\226\172\128\134\070\056\121\056\194\047\196\027\161\115\067\144\146\147\196\233\031\077\005\089\159\183\130\111\015\043\168\073\225\012\128\174\144\169\237\200\067\199\072\009\118\030\238\068\124\218\034\204\137\154\139\130\162\002\120\250\122\178\233\039\255\028\062\055\252\047\091\194\094\092\020\001\208\224\008\178\016\196\036\166\105\033\020\043\080\076\032\122\228\056\225\025\165\140\183\241\012\111\226\199\123\023\089\105\101\229\233\002\106\161\021\032\220\225\031\175\189\134\136\200\000\000\111\225\033\078\226\167\223\247\227\238\079\155\113\231\199\033\220\248\166\011\239\223\238\194\091\055\219\177\247\116\054\134\015\172\194\198\221\137\232\220\178\010\141\035\177\040\239\153\143\226\206\112\228\183\205\194\134\250\000\100\010\130\145\084\022\128\244\218\096\164\215\006\032\191\053\024\141\155\230\161\119\119\012\054\031\093\137\161\003\113\024\058\184\004\163\135\086\096\243\145\149\024\155\088\142\011\055\215\011\045\000\249\241\023\005\046\250\250\015\005\248\059\254\254\186\080\001\132\105\224\076\198\005\158\227\000\147\010\064\155\136\159\124\183\176\140\056\155\115\178\000\116\186\041\064\020\006\146\020\100\010\153\066\052\052\146\170\127\084\035\224\123\136\148\101\248\103\200\010\112\151\177\186\018\180\013\053\016\026\025\000\223\016\079\158\016\066\099\101\136\018\070\083\070\092\188\156\225\061\203\139\227\003\186\066\046\191\054\009\197\130\245\040\105\090\143\234\142\013\016\244\230\161\180\105\029\007\126\163\187\170\048\188\171\016\099\251\075\176\117\247\208\115\129\018\203\039\049\041\145\105\238\035\099\035\047\009\251\223\089\034\094\032\241\004\073\001\136\238\045\106\043\187\253\249\071\120\244\228\034\126\252\229\060\102\069\120\067\070\078\150\081\071\138\061\168\054\064\010\016\021\051\027\207\112\077\008\253\062\157\096\128\231\135\071\187\240\205\253\049\220\249\113\024\119\127\026\197\165\235\117\056\112\062\011\231\223\173\195\185\119\026\112\248\098\062\118\158\200\194\192\238\068\052\109\090\136\218\193\249\104\030\141\067\081\107\036\242\091\102\163\164\115\030\010\218\194\080\217\055\151\149\164\168\035\012\185\045\033\200\109\014\065\089\207\108\126\158\211\052\011\109\219\023\098\138\145\153\158\128\218\157\069\254\095\148\002\190\106\001\072\001\104\068\012\051\125\039\065\033\225\137\127\021\008\146\021\042\128\180\216\228\181\114\194\235\097\041\250\127\158\109\136\072\165\100\037\232\146\105\085\121\024\152\234\051\067\072\196\052\166\012\064\073\077\009\190\179\093\145\144\021\013\103\047\007\024\153\026\008\251\014\205\013\120\046\177\139\151\011\199\000\179\034\130\016\179\050\018\105\069\171\145\095\151\200\247\006\086\182\165\065\208\155\059\153\250\229\160\127\107\022\198\015\228\096\235\161\002\124\249\205\221\151\132\072\230\060\124\110\024\174\127\116\253\165\215\255\221\069\193\032\185\006\209\093\128\162\245\201\103\031\224\231\223\078\114\181\175\189\175\008\127\127\237\053\014\004\053\052\053\048\109\218\084\076\153\242\031\200\204\093\141\103\120\139\211\187\031\127\059\136\031\126\059\136\055\062\108\195\055\247\118\226\033\142\225\187\007\123\113\229\035\001\046\094\175\193\055\015\040\237\027\193\205\239\075\112\251\231\122\124\250\093\023\046\127\088\133\227\087\203\113\230\090\035\014\093\040\192\192\222\056\062\245\195\007\023\163\119\119\052\218\183\046\068\231\142\040\052\110\138\132\096\056\026\101\061\017\040\237\142\064\070\067\032\202\251\195\009\008\114\017\208\248\053\098\241\254\049\047\120\018\247\151\158\137\025\018\127\040\000\061\146\002\136\080\193\023\005\079\138\160\168\034\199\119\007\138\075\080\095\192\116\200\076\142\142\163\224\142\148\128\007\081\083\122\072\212\051\122\046\053\003\211\169\209\068\156\126\167\176\110\064\138\067\214\066\090\065\026\254\017\030\168\235\075\064\207\214\116\056\121\218\066\077\147\102\018\235\008\155\076\028\172\225\233\239\001\191\080\031\204\139\142\064\204\234\072\172\076\137\065\110\085\018\042\090\055\160\178\053\013\181\093\153\028\245\015\109\167\121\003\149\232\026\075\193\182\003\237\060\235\247\213\069\053\251\127\135\222\253\087\139\172\000\005\137\100\077\136\039\072\037\099\190\001\252\215\159\241\227\125\138\041\206\161\184\038\001\230\086\214\056\127\241\060\095\069\215\217\221\137\215\167\078\069\090\230\010\000\239\226\237\079\123\241\238\173\030\006\124\232\148\031\187\082\133\015\238\244\225\203\095\199\112\248\082\001\142\092\042\198\247\143\198\241\205\195\001\092\255\058\003\159\252\080\132\239\030\109\196\023\191\246\226\238\047\093\184\245\125\055\110\126\219\142\143\190\174\194\219\119\211\241\222\151\105\120\231\139\116\092\187\155\138\015\191\205\192\197\027\107\177\253\244\034\108\158\088\196\241\067\199\182\069\024\058\180\018\083\012\204\245\004\090\006\234\108\206\069\022\128\205\059\229\254\084\215\127\033\019\160\038\017\145\239\103\046\160\188\012\111\121\005\089\006\057\008\072\209\051\212\133\152\004\041\206\052\246\233\020\003\240\073\151\165\129\083\066\042\249\031\130\159\202\237\230\116\234\153\067\064\233\227\164\187\160\000\114\081\066\024\134\247\101\035\189\114\062\115\002\104\150\144\186\142\058\044\236\077\225\021\228\010\107\071\011\184\249\185\033\124\065\040\098\019\098\144\200\131\034\083\080\212\144\140\242\150\013\168\237\204\070\219\080\049\054\110\171\195\248\222\070\180\143\164\227\196\005\130\064\095\094\055\063\185\137\139\151\009\025\251\159\095\084\054\166\252\159\134\071\127\255\195\079\248\226\187\243\120\140\147\040\169\073\193\155\215\094\030\049\147\145\149\141\149\137\243\001\188\137\011\239\181\224\246\247\091\112\247\199\173\184\118\179\007\019\151\043\112\250\090\017\062\253\174\003\155\015\175\197\059\183\090\241\237\111\003\248\226\065\051\167\125\183\127\169\198\157\095\026\025\223\255\242\094\039\238\254\220\129\059\063\119\224\171\007\237\188\191\124\088\141\175\030\085\226\171\071\194\116\240\214\207\089\248\240\155\084\188\255\213\122\188\241\233\026\236\060\027\139\051\031\038\010\041\097\018\178\051\153\198\165\174\173\194\150\128\209\063\190\242\077\136\005\144\018\008\219\195\254\049\121\013\156\004\099\001\084\212\144\151\039\191\038\172\117\083\154\067\102\154\130\170\025\018\211\133\132\015\121\009\174\009\080\190\047\188\124\074\216\005\068\248\000\143\150\155\028\068\193\217\130\156\004\167\125\196\080\154\033\057\003\115\162\003\081\223\187\129\155\068\201\026\088\057\155\194\055\194\025\065\209\174\088\153\186\000\206\062\118\112\241\118\196\172\057\193\136\094\022\137\204\146\245\060\032\178\168\062\021\197\130\084\084\181\103\160\109\144\082\192\082\116\111\170\068\203\198\028\188\255\241\155\047\009\129\022\221\002\078\237\219\255\051\139\130\063\234\252\161\058\193\237\207\239\114\186\248\224\193\035\124\249\253\037\062\217\059\015\110\124\245\071\240\193\007\031\033\061\111\025\222\185\181\017\007\207\149\225\246\247\099\248\224\206\000\246\159\041\099\115\126\241\195\124\092\187\157\131\093\103\151\227\252\245\028\220\252\190\008\055\126\200\197\165\027\107\112\243\135\002\124\240\117\058\238\222\171\195\023\247\058\113\251\231\022\220\254\089\128\207\239\053\224\243\251\077\248\244\167\034\188\243\121\010\062\253\113\003\110\124\151\140\015\191\094\207\251\163\111\083\241\209\055\105\056\118\109\041\110\252\180\129\128\032\113\238\013\036\147\207\194\144\152\250\156\238\077\008\030\091\001\201\105\236\255\105\139\020\128\123\000\072\001\008\220\080\018\146\029\041\159\166\219\067\137\254\044\038\041\198\131\147\072\224\050\242\210\028\213\011\111\010\147\101\005\032\160\135\000\032\002\133\072\248\084\060\034\133\160\161\146\132\019\080\245\076\199\088\011\222\225\142\112\244\179\068\088\116\000\102\045\244\194\178\204\032\204\090\226\004\223\185\206\008\156\227\141\224\185\254\092\017\140\092\060\007\153\069\041\040\170\205\064\089\099\038\202\026\051\024\253\107\232\206\067\125\119\046\106\058\178\208\051\042\096\019\253\226\162\198\208\011\151\255\152\017\240\255\116\177\255\159\164\137\211\000\009\010\004\041\030\032\151\064\235\189\027\103\176\247\100\037\206\094\057\248\234\143\226\193\131\223\209\212\157\139\145\125\105\056\124\161\002\159\125\183\025\199\175\086\161\127\215\026\108\057\182\022\087\111\081\202\150\142\177\099\011\112\248\202\122\092\249\100\061\142\191\189\012\199\222\094\142\247\190\088\135\143\191\219\128\219\247\040\191\047\197\157\251\180\009\236\041\198\157\007\197\184\249\099\014\054\079\132\226\240\213\024\220\248\046\005\159\124\159\204\041\224\157\123\121\248\240\155\245\056\120\037\010\095\253\158\035\164\133\019\118\079\000\014\205\005\020\062\010\021\064\148\230\145\217\167\230\208\023\021\128\045\192\011\167\095\153\042\106\106\148\075\171\242\101\075\052\119\144\175\153\167\162\135\164\036\212\232\018\105\029\085\190\032\138\130\062\170\039\016\039\144\089\065\100\029\100\196\024\026\166\127\151\047\165\154\188\097\212\200\066\031\254\017\238\136\078\012\129\231\028\027\120\207\177\071\200\130\000\184\250\057\032\116\129\063\022\173\136\068\228\226\121\060\042\102\077\250\042\100\149\174\067\223\230\070\238\140\165\142\153\178\166\012\052\116\231\163\119\172\028\091\247\014\253\137\243\255\241\141\143\255\135\026\066\169\006\064\130\038\193\147\239\167\000\144\148\235\213\113\115\031\221\186\128\237\071\074\112\249\045\162\126\189\188\008\072\060\122\118\016\187\079\020\098\235\145\060\062\249\251\206\020\160\121\211\098\180\142\071\099\215\217\037\184\122\043\013\135\174\036\099\235\241\085\056\116\101\057\070\143\132\227\248\219\075\249\244\191\117\059\025\183\126\201\197\039\063\164\225\238\003\066\251\104\023\226\238\253\092\220\252\126\003\182\158\012\199\214\147\179\241\241\183\201\248\252\126\030\062\127\080\128\155\223\167\224\253\047\215\226\216\181\088\252\138\114\186\059\088\069\160\162\175\004\113\057\049\024\089\235\065\067\087\133\173\000\079\008\165\146\046\183\142\207\192\180\201\217\064\052\085\092\070\150\132\047\195\136\022\157\126\058\249\036\124\170\170\145\069\160\214\039\089\057\105\190\065\075\066\090\056\133\156\225\098\026\059\075\083\181\038\009\161\244\026\069\252\156\077\080\025\121\146\035\200\183\134\016\177\084\073\006\014\030\182\060\070\062\124\169\007\022\038\004\195\055\196\011\243\022\206\131\163\187\045\188\130\220\088\025\102\047\012\101\098\200\218\013\241\200\042\077\070\137\032\025\037\077\107\048\188\163\158\051\129\193\109\117\152\184\216\134\247\062\254\051\200\115\229\205\055\254\229\112\167\191\090\084\004\018\005\122\036\116\046\012\253\019\088\248\253\143\223\192\216\190\034\092\251\128\178\129\151\023\001\073\183\190\058\138\003\103\075\112\240\092\057\246\157\041\070\235\104\060\170\123\151\162\172\103\046\118\156\092\135\189\231\018\080\059\020\129\190\061\139\049\120\096\001\122\247\004\099\239\133\072\092\189\181\006\135\222\088\136\027\223\167\227\227\239\210\241\249\195\050\134\125\239\252\154\142\059\247\178\241\201\015\233\056\241\238\074\092\188\145\128\187\247\132\223\191\115\175\016\119\126\205\192\167\063\101\226\194\071\171\112\015\133\152\098\226\162\039\048\116\214\129\150\165\006\044\061\140\033\167\034\141\153\226\083\057\014\160\124\095\212\010\054\109\230\084\086\000\058\205\084\204\016\250\127\082\000\069\040\171\042\179\240\009\078\165\090\055\229\184\164\008\194\054\049\097\240\071\039\156\186\133\024\056\162\187\002\137\023\032\039\193\191\147\134\079\009\093\133\240\078\034\190\151\128\172\128\170\060\052\244\212\224\226\103\203\022\032\126\067\012\124\103\121\242\248\121\186\130\198\039\196\147\239\017\014\139\010\102\005\072\218\144\128\130\234\012\084\180\164\163\109\168\008\067\219\171\049\186\187\006\131\219\043\049\184\189\010\095\127\251\114\250\071\144\047\145\060\254\157\197\141\161\191\009\001\032\090\036\060\098\001\255\119\215\202\191\251\225\091\104\236\079\193\229\107\196\253\123\121\221\191\255\000\111\125\184\013\123\079\150\096\219\145\092\028\189\088\133\250\158\020\164\148\044\070\126\211\060\108\063\158\137\161\125\107\032\024\137\070\251\182\069\216\116\036\014\077\155\195\176\231\252\082\076\188\181\004\135\222\136\225\128\240\250\215\105\124\194\111\124\159\134\247\191\088\139\047\031\022\226\214\079\153\024\063\030\138\163\111\045\194\167\063\166\225\147\031\051\217\002\144\002\220\249\117\003\222\190\179\014\063\033\027\083\140\028\116\005\218\182\106\080\053\086\130\182\165\006\019\056\009\019\224\092\159\187\120\132\129\219\095\043\000\033\091\147\022\128\048\117\117\101\230\190\145\066\208\035\013\126\032\097\083\250\199\204\162\201\150\114\058\229\034\128\136\006\075\210\102\130\008\179\139\132\060\000\138\017\008\027\032\216\216\194\222\024\033\209\190\112\015\113\129\163\151\003\044\028\204\097\237\108\197\003\040\035\098\067\016\027\031\141\232\184\133\088\151\185\006\089\101\201\168\104\202\070\235\096\049\058\071\010\177\113\123\033\186\054\101\243\077\089\143\031\191\156\254\081\199\046\013\104\248\103\075\148\222\145\153\039\129\139\252\058\119\254\252\252\211\243\231\255\106\125\254\229\109\212\119\039\227\228\133\061\175\126\139\173\199\192\150\010\244\140\101\099\120\087\030\182\031\045\198\134\242\088\228\214\174\068\102\117\012\154\070\150\163\110\099\052\010\219\195\208\183\107\053\250\247\044\067\065\091\016\146\042\029\081\216\225\139\129\189\145\056\250\214\050\134\118\063\252\038\005\151\110\196\227\196\059\075\241\245\111\089\120\251\078\002\250\247\121\225\224\149\104\156\251\112\053\222\252\108\013\110\126\159\134\207\126\074\197\155\183\226\113\224\242\066\124\242\203\122\076\081\050\145\023\024\058\106\067\081\079\030\022\046\068\212\212\102\060\128\129\030\110\234\020\099\019\062\109\230\052\206\002\136\070\253\146\002\040\010\169\084\164\004\138\106\138\144\161\014\096\121\121\161\171\096\244\079\072\014\229\024\130\102\012\078\182\158\147\240\201\252\211\035\165\128\164\024\028\092\082\092\160\070\192\144\030\115\006\149\052\148\224\236\239\000\255\057\158\008\089\024\200\179\133\230\046\009\135\147\159\003\252\035\124\016\181\108\030\022\175\140\230\254\000\234\000\170\104\044\067\081\109\038\114\171\214\161\111\188\020\231\223\238\065\077\087\002\014\030\255\115\250\071\220\190\087\077\055\097\001\084\233\035\179\078\002\162\185\192\047\022\134\168\014\064\169\222\191\187\008\046\166\097\077\019\103\254\172\000\052\139\128\248\009\141\125\027\208\060\144\129\198\129\052\164\151\197\034\175\118\037\242\234\086\032\167\062\018\073\101\062\216\080\031\136\134\161\069\104\222\028\131\188\150\089\088\145\239\132\053\229\046\200\104\116\066\211\152\055\014\092\142\198\129\203\049\216\116\116\054\246\095\142\194\119\191\103\226\218\237\068\140\031\015\193\238\115\243\112\241\227\004\156\253\096\021\227\255\148\001\156\124\119\009\122\247\122\226\195\239\214\096\138\188\158\172\064\199\086\029\058\214\026\048\119\050\130\142\145\006\207\004\038\223\207\230\152\130\065\025\041\230\203\019\020\252\170\005\080\080\146\103\190\059\197\000\010\042\010\028\237\211\032\008\018\042\077\021\035\159\079\024\192\223\095\255\027\099\009\052\098\142\210\066\017\125\156\152\063\212\080\074\095\083\170\072\110\131\136\035\058\166\058\208\183\050\096\150\176\255\060\095\004\045\240\135\075\160\019\034\151\133\035\163\120\029\060\195\220\048\123\113\008\098\086\207\199\124\154\007\184\114\017\226\083\086\033\179\104\003\138\170\011\208\208\089\198\046\224\196\229\078\054\171\183\063\127\057\208\035\090\055\177\122\095\092\036\104\226\254\017\237\139\130\185\023\003\070\130\119\137\241\035\042\013\255\187\139\002\069\186\166\245\232\233\151\199\209\209\186\126\227\061\008\122\242\081\217\070\208\117\018\010\234\227\177\190\032\006\169\037\139\145\093\189\148\241\143\182\077\137\200\106\012\066\069\239\092\212\015\047\196\250\042\031\148\116\070\032\181\214\013\089\205\142\168\030\244\065\113\143\029\202\250\236\144\211\102\137\254\125\190\184\254\117\042\222\251\098\013\042\006\204\209\178\213\009\199\223\142\195\214\019\097\184\118\039\009\151\110\036\096\223\133\185\104\028\179\195\197\079\150\098\138\130\158\188\064\219\070\029\214\030\102\144\215\146\129\130\186\156\112\066\152\212\116\014\206\184\241\083\070\026\051\197\102\078\186\000\137\231\010\064\089\000\041\001\041\000\117\186\042\107\208\205\033\138\028\248\081\155\149\024\089\015\005\073\076\157\012\032\069\087\210\081\092\192\167\095\086\156\079\059\093\010\069\138\066\233\033\109\117\029\021\088\185\091\067\082\093\006\134\118\070\112\014\112\132\075\176\011\060\195\061\096\239\103\199\029\192\145\203\103\035\108\081\048\098\226\231\097\193\178\057\136\089\030\133\132\148\085\088\159\153\132\186\230\058\190\042\110\112\091\053\182\029\042\199\158\137\046\230\214\139\022\005\112\215\222\253\243\220\223\127\181\232\158\064\209\044\161\127\181\072\105\184\089\244\231\159\153\087\064\207\251\070\219\112\248\248\129\087\223\138\243\111\028\067\211\064\054\154\055\102\162\190\103\061\138\027\087\035\169\032\010\217\085\203\145\095\191\002\249\077\081\200\107\014\199\134\006\127\198\244\179\026\003\017\095\226\138\212\106\031\044\206\050\071\108\182\005\214\085\185\032\058\195\000\243\146\245\144\092\099\131\198\205\054\056\241\206\018\092\255\042\005\165\125\230\040\235\055\199\248\137\112\236\058\027\142\139\031\199\227\216\181\101\232\217\237\129\154\033\083\236\185\020\138\041\098\210\051\004\100\254\053\173\085\033\038\075\213\058\049\006\131\040\019\224\084\141\074\188\210\066\011\240\106\012\032\220\050\028\008\106\234\104\050\007\144\026\045\103\074\010\145\062\049\041\097\135\016\065\200\196\002\038\115\207\172\098\058\253\212\058\070\204\034\117\033\061\076\052\121\132\203\193\154\074\176\241\180\129\154\145\058\140\237\141\097\239\231\000\231\096\103\068\175\154\143\128\072\063\004\047\240\195\130\021\115\048\127\089\056\119\004\175\078\091\138\005\203\230\098\109\070\034\214\101\174\069\067\107\003\122\135\219\177\105\119\035\198\246\214\226\250\205\043\047\125\240\020\252\125\248\241\191\023\252\209\162\217\065\162\011\162\255\106\145\117\160\147\078\150\067\212\050\046\202\044\132\010\208\129\003\019\127\118\001\212\010\222\208\155\130\190\045\249\104\027\222\192\012\160\226\198\068\228\212\172\064\070\101\044\210\170\230\032\071\048\023\025\245\193\200\105\014\068\070\067\000\214\020\007\032\032\214\004\254\177\038\240\141\049\070\068\188\021\002\151\233\034\116\181\033\214\085\057\097\125\157\038\155\247\067\087\098\080\212\109\142\193\003\254\024\216\239\135\205\019\179\112\234\189\149\056\242\230\018\052\143\219\162\122\200\020\141\219\108\048\101\154\216\235\002\073\121\049\200\106\201\066\076\070\104\246\121\246\175\186\018\131\064\244\092\082\074\226\159\042\000\245\214\145\207\039\011\160\169\039\108\008\125\157\166\138\079\210\190\233\212\019\138\040\122\046\164\149\207\224\078\095\166\125\107\042\049\021\140\008\026\180\169\031\128\152\192\038\014\166\208\181\214\135\133\187\021\156\131\092\248\182\240\133\171\230\035\036\058\152\175\141\157\179\036\020\065\145\126\136\090\057\007\171\232\058\148\164\056\172\203\094\135\180\188\020\084\054\084\160\119\184\021\227\123\219\049\186\163\251\079\040\223\221\047\238\226\179\087\204\255\191\090\132\242\145\203\160\230\080\178\002\036\108\218\036\104\250\093\052\005\148\190\247\234\016\072\209\218\178\123\020\187\015\110\123\233\053\106\043\163\075\029\005\125\153\104\222\152\133\154\206\181\040\168\095\137\156\234\149\200\170\090\142\117\133\011\177\038\127\046\214\150\004\033\165\050\136\227\128\132\098\079\044\221\016\128\176\056\119\056\133\154\193\055\210\001\065\139\156\016\182\194\006\139\051\236\176\036\219\006\115\147\053\144\088\110\136\198\049\039\036\085\235\162\126\147\003\218\182\059\160\105\220\005\103\222\095\129\157\103\231\066\048\102\143\188\118\035\052\111\119\016\066\193\084\252\033\193\144\143\159\046\054\149\047\142\034\198\044\005\124\180\169\089\098\166\056\013\147\156\198\046\128\088\173\210\050\082\060\227\070\223\092\027\186\198\090\208\208\086\227\225\144\020\004\146\002\048\116\060\157\192\163\215\216\002\008\167\140\009\111\038\037\152\088\076\094\028\242\058\074\208\052\213\134\156\150\002\052\076\181\161\105\174\195\055\132\155\056\153\195\200\217\004\006\142\134\176\247\119\132\083\144\011\220\067\061\048\111\105\004\092\130\221\048\059\054\132\099\002\234\254\089\186\046\154\045\192\202\212\101\088\147\145\128\140\162\012\228\149\229\241\088\149\157\135\187\049\113\250\192\243\078\094\209\122\255\250\251\248\245\255\161\047\167\019\077\150\131\054\165\126\164\000\060\033\228\209\035\198\005\104\083\027\249\171\072\035\173\157\251\183\098\231\254\151\021\224\231\159\127\070\219\064\037\143\121\161\118\238\138\182\053\200\170\092\142\236\170\021\072\042\088\128\149\153\225\088\158\030\134\132\252\016\036\020\250\099\117\161\023\150\103\251\032\104\145\029\188\231\219\194\038\192\004\065\049\046\240\154\111\129\176\165\046\136\090\239\132\217\107\012\176\170\216\010\043\139\117\145\084\173\135\236\086\003\126\044\237\051\067\114\157\033\182\157\140\064\211\184\029\210\027\141\144\080\102\137\234\097\063\161\002\016\200\035\098\253\208\054\052\049\128\174\129\014\251\125\058\241\018\018\146\152\041\046\198\000\143\004\033\123\018\146\220\230\109\237\097\132\224\088\123\088\007\232\065\085\143\248\123\026\092\014\166\218\058\009\156\004\047\218\020\007\208\140\065\097\177\071\026\018\042\082\144\213\081\128\186\153\022\204\220\172\161\106\170\005\125\123\019\152\186\089\195\214\207\025\166\238\022\048\247\176\132\207\028\111\248\068\120\099\086\212\044\068\175\138\068\072\116\016\022\037\068\098\078\092\040\207\196\137\079\143\195\154\204\229\072\202\138\071\102\113\038\143\131\167\206\223\158\097\186\028\185\025\215\063\126\239\165\015\158\204\057\077\232\250\031\093\148\053\080\128\040\170\252\081\224\200\227\098\126\127\196\236\097\194\006\094\093\135\143\239\199\129\137\189\047\189\246\201\103\055\081\217\146\137\170\246\020\084\181\039\163\170\125\003\054\148\174\064\122\201\010\036\228\204\099\005\088\154\022\130\184\212\096\068\175\243\197\226\020\063\196\172\243\071\096\180\035\156\195\044\096\230\165\015\167\016\115\120\206\181\065\096\140\019\044\253\053\048\107\133\001\086\020\218\160\188\223\021\185\237\070\072\105\208\197\218\106\029\172\046\211\194\154\074\003\052\142\059\163\184\199\024\233\002\083\142\031\226\242\205\049\229\181\025\175\009\254\049\237\015\225\147\176\140\045\140\161\161\173\001\049\049\049\086\000\049\113\241\231\155\148\065\092\130\038\124\200\194\196\067\019\126\139\204\225\026\097\004\053\061\021\168\107\169\179\002\188\054\067\056\091\080\052\095\144\158\083\117\144\139\065\050\098\092\003\208\182\208\133\166\181\062\244\236\077\096\238\097\011\099\023\075\024\058\091\176\002\088\121\219\195\206\223\001\214\062\182\112\011\113\071\112\084\016\252\231\005\096\225\202\057\088\182\062\026\025\197\107\089\001\200\252\047\091\191\008\043\083\151\032\163\136\134\032\167\033\191\034\143\167\128\214\183\149\099\120\107\015\095\247\254\226\186\254\225\117\116\245\082\080\248\239\045\074\011\137\024\074\069\158\047\190\254\138\153\193\100\238\105\172\236\179\103\079\249\251\244\156\218\198\254\010\020\034\142\065\126\089\030\046\189\241\114\181\241\226\213\243\040\172\075\066\073\099\018\242\234\018\080\212\176\014\233\197\043\177\038\107\009\226\051\035\145\092\020\131\117\005\081\088\146\050\011\179\151\123\034\098\185\007\230\175\246\135\219\108\043\216\007\153\194\054\208\148\239\077\008\141\245\068\240\098\103\024\122\040\194\118\150\010\252\150\106\034\083\016\128\037\057\102\136\206\212\192\234\050\178\006\038\136\201\048\194\170\018\003\164\055\234\096\125\173\009\098\050\141\177\188\216\002\083\166\137\079\019\016\072\067\172\031\082\004\009\105\009\102\221\200\043\202\051\158\255\135\002\144\005\016\062\210\020\080\186\243\071\211\068\021\022\030\250\048\113\210\097\156\159\186\126\169\240\067\109\226\036\104\018\062\193\191\244\061\017\232\067\233\030\245\005\146\185\055\243\176\133\165\183\003\159\120\075\047\123\088\120\218\195\210\211\030\214\062\014\112\015\117\135\119\132\055\156\131\093\225\025\230\133\176\152\048\190\034\118\193\202\089\072\200\140\070\124\122\044\147\064\201\005\036\102\174\192\134\162\036\164\021\172\197\134\194\052\020\084\228\161\162\177\016\103\046\254\025\126\061\122\124\130\239\056\220\187\255\229\019\041\090\004\248\016\045\156\154\065\238\124\126\151\079\053\229\253\175\114\005\232\228\211\101\081\148\026\190\170\100\180\200\042\052\183\053\115\013\132\216\203\244\187\094\092\251\142\236\230\097\205\133\213\027\144\087\077\230\127\037\082\010\150\035\049\035\022\203\146\035\144\092\184\024\105\101\139\144\084\016\137\200\120\095\132\196\058\035\098\153\055\092\066\173\096\225\099\000\183\112\091\184\207\182\133\093\144\033\236\131\245\097\225\167\001\051\095\069\216\207\086\068\084\138\037\130\087\234\032\096\153\006\230\037\235\035\054\199\008\179\215\232\035\038\195\020\025\077\150\088\093\098\129\192\021\218\088\066\022\064\065\083\065\064\052\108\170\203\211\137\165\180\143\204\063\009\095\180\201\252\083\016\056\099\166\048\014\032\002\136\182\190\006\116\013\181\056\239\167\128\078\089\083\081\120\163\024\081\197\041\154\159\236\001\084\032\190\159\170\156\176\060\172\036\003\117\125\053\190\083\072\197\072\003\102\238\054\124\226\173\125\236\097\233\109\011\199\064\023\152\123\218\192\200\197\028\102\030\228\010\236\249\053\183\080\079\184\133\122\033\052\058\024\177\073\225\088\153\017\134\196\172\024\108\040\094\131\013\037\241\072\047\089\134\210\230\100\020\212\037\034\191\122\061\119\003\087\054\022\227\206\231\212\090\253\242\106\108\109\226\169\230\042\026\202\104\104\108\248\019\007\080\068\250\036\174\223\139\164\079\010\240\068\179\127\200\204\211\243\087\065\036\209\162\107\100\104\038\016\165\195\052\023\145\174\159\167\059\008\094\092\099\059\055\034\167\140\020\032\019\249\181\107\081\034\072\065\086\217\090\036\110\136\197\202\244\121\088\150\022\202\049\000\185\130\152\164\032\248\045\176\135\207\124\123\088\251\027\193\057\212\028\062\243\029\225\031\229\002\207\121\022\240\152\107\006\135\016\029\056\205\214\129\117\176\050\236\194\020\225\018\169\136\176\068\093\204\079\054\070\192\114\045\204\090\173\141\037\217\086\140\031\172\175\118\198\252\245\198\008\078\080\195\020\117\098\005\171\043\112\132\062\085\108\042\151\108\181\116\052\089\216\051\197\132\167\126\134\248\012\038\052\018\209\131\105\222\124\121\180\176\090\167\107\166\203\194\087\082\023\094\036\077\155\126\031\009\157\122\253\136\244\169\160\163\004\105\101\105\190\070\134\026\063\117\044\244\096\236\108\001\003\186\076\202\201\012\102\238\086\066\179\239\231\004\083\119\043\222\038\174\230\048\117\179\228\160\207\061\204\027\206\179\188\224\057\219\027\065\011\061\248\036\208\020\241\181\153\203\248\212\036\228\204\101\228\172\184\041\017\229\173\041\194\171\227\218\202\241\227\207\127\248\099\058\145\116\010\131\066\130\160\168\076\119\029\170\241\223\229\235\239\139\195\071\014\255\073\017\008\043\160\011\160\104\196\059\077\250\230\011\035\238\223\231\215\255\217\162\187\006\170\106\171\248\158\005\042\103\019\059\138\134\100\206\010\011\158\164\147\010\023\165\134\189\163\173\124\139\007\013\112\204\175\078\097\183\070\179\252\086\165\198\032\062\061\026\075\146\067\176\036\057\024\177\201\179\048\111\165\047\002\162\156\224\031\229\004\247\008\171\201\109\009\151\217\070\240\152\175\135\176\213\038\240\093\164\015\207\040\093\056\207\081\135\085\144\002\124\098\244\016\149\108\141\136\181\070\152\147\100\132\160\149\218\008\089\173\131\217\107\244\016\151\107\137\240\053\122\008\073\212\196\020\093\019\109\001\157\090\138\206\233\212\042\107\042\115\027\023\229\240\175\207\156\202\021\057\018\056\153\109\029\067\029\232\090\232\065\217\064\013\242\090\010\220\205\171\109\166\205\132\078\002\124\248\066\007\071\115\152\185\152\195\209\223\009\102\206\230\048\116\048\229\062\127\018\182\132\170\020\020\244\085\088\232\250\116\115\136\185\054\180\109\012\161\099\103\012\083\055\043\152\185\091\179\208\201\002\088\121\219\194\206\223\137\045\131\157\191\051\188\035\124\225\030\230\133\128\249\126\152\189\104\022\230\045\013\199\226\196\072\196\167\047\070\082\094\012\050\043\151\032\163\034\014\069\117\169\168\104\204\065\121\099\046\190\249\238\143\235\089\232\067\255\228\214\039\176\117\176\229\172\134\120\121\234\026\234\220\013\076\117\011\095\127\031\180\119\182\227\163\143\063\122\254\051\255\238\162\033\144\149\053\149\060\108\146\014\142\170\154\010\103\082\090\186\090\144\148\145\064\094\097\222\075\239\039\160\168\190\189\156\005\223\220\095\204\109\107\201\121\194\139\046\104\212\253\170\180\040\196\174\015\070\076\018\093\160\225\135\240\056\031\004\071\123\034\048\218\009\174\225\230\240\143\114\064\192\066\007\216\004\234\194\125\174\017\130\151\088\193\059\202\024\142\225\026\240\139\054\135\119\148\041\252\022\025\099\246\106\107\004\046\215\065\104\188\062\252\226\052\017\177\198\008\115\215\025\033\044\081\015\222\177\170\008\079\210\197\020\109\035\077\182\000\116\250\053\244\053\160\161\167\193\190\218\204\206\136\039\117\233\091\027\240\192\038\053\067\013\088\121\218\067\211\082\015\234\022\218\144\210\144\129\129\141\001\012\109\141\132\247\004\170\201\193\200\218\008\222\097\222\048\115\053\131\133\187\057\044\060\172\161\101\099\004\029\091\099\024\185\088\065\207\222\020\202\038\154\208\181\051\230\173\102\174\195\010\064\177\000\009\220\204\067\168\004\038\174\086\176\240\178\133\107\136\007\167\128\086\222\014\240\156\237\139\192\005\001\008\152\239\143\144\133\065\136\094\061\143\047\142\142\223\176\020\233\197\171\177\038\055\010\137\089\209\072\201\139\071\078\121\010\138\106\050\240\213\055\127\158\251\251\238\123\239\194\192\072\159\199\194\145\002\168\169\171\113\033\075\070\086\134\121\012\004\104\133\132\135\160\172\162\012\019\199\142\226\243\047\190\224\204\225\069\011\065\049\194\141\155\055\176\113\104\035\034\230\069\240\192\071\041\089\073\102\068\209\239\227\223\171\161\198\221\198\083\167\079\197\145\137\035\047\253\031\168\000\085\082\151\141\162\250\117\104\232\077\067\093\119\010\223\130\186\038\115\041\086\167\080\092\051\031\049\137\097\152\191\202\031\097\075\188\017\190\196\007\179\151\248\097\246\050\015\132\044\033\179\111\006\175\249\230\008\136\118\128\239\066\043\004\046\178\067\064\140\029\007\227\179\098\029\017\016\099\003\135\112\117\120\044\084\135\103\140\026\230\037\153\194\035\074\013\206\243\021\176\056\211\010\110\081\138\112\143\086\132\239\050\085\076\209\052\211\022\168\026\107\064\086\083\158\123\241\009\127\087\210\149\135\153\147\048\208\176\244\049\133\158\189\033\012\157\173\096\234\106\003\025\109\005\168\091\104\241\233\085\055\211\134\137\155\053\063\234\218\024\194\194\211\022\214\222\118\048\112\052\128\133\039\153\119\083\232\218\153\064\213\076\155\133\111\225\229\008\067\103\058\225\086\176\244\114\228\159\053\116\050\135\133\167\029\172\124\108\224\024\228\004\099\023\011\104\241\239\178\131\141\175\019\251\127\115\015\250\154\098\001\111\248\205\243\067\016\113\000\022\207\194\226\196\005\200\175\076\227\070\144\196\140\056\190\050\038\189\104\045\210\010\018\121\070\192\095\041\000\173\247\222\127\143\253\050\101\051\162\142\032\017\167\129\103\004\072\073\098\218\244\105\108\041\116\116\117\096\239\104\007\047\095\047\118\031\129\193\001\112\118\117\230\078\226\025\051\167\243\123\169\020\078\110\147\076\062\053\153\082\057\156\006\079\078\249\143\041\152\059\127\238\159\080\196\027\159\124\140\234\214\092\052\246\231\160\174\123\061\106\186\082\080\222\146\138\196\140\024\044\093\055\007\011\086\132\049\234\025\181\122\022\034\150\250\034\052\214\027\161\177\030\240\152\107\142\200\068\015\044\078\243\064\096\156\001\130\098\173\017\184\200\006\126\081\054\176\246\215\129\153\183\058\060\231\090\194\042\064\003\206\017\058\240\092\168\003\159\197\058\088\158\231\008\247\005\234\240\088\160\141\117\021\062\176\010\145\128\239\018\013\204\089\111\136\041\146\234\210\002\121\003\021\054\205\058\214\006\048\176\051\129\178\145\018\180\172\213\160\231\168\005\045\027\117\168\153\107\194\220\211\129\021\064\193\080\141\079\174\129\147\037\020\012\213\161\101\109\000\067\071\115\104\089\025\064\207\193\012\038\174\150\176\241\177\071\106\126\018\252\230\250\243\123\073\160\180\117\237\077\217\220\011\223\103\013\035\103\075\104\088\234\065\195\082\023\022\158\150\048\243\160\120\128\044\128\053\212\045\245\096\230\110\011\231\096\119\078\019\205\061\028\096\227\235\202\174\128\170\130\129\243\253\016\185\124\014\007\082\107\179\086\096\125\238\042\228\150\211\213\240\169\072\045\088\131\194\170\092\124\251\253\063\047\245\082\171\183\187\151\059\102\204\152\193\189\129\194\142\029\033\181\141\148\128\054\189\046\071\237\220\147\247\040\082\077\068\070\142\136\176\242\204\239\087\081\081\126\094\009\165\147\079\003\039\167\205\152\006\125\067\125\196\044\142\065\113\105\241\243\091\070\095\092\087\175\093\065\093\071\030\026\251\051\080\214\156\140\204\178\068\164\022\172\100\011\182\174\048\010\139\147\066\177\112\117\024\022\174\241\071\228\234\000\132\044\246\070\120\156\039\194\150\057\035\114\157\045\146\042\188\177\182\194\019\179\150\090\194\038\072\013\174\115\116\225\024\174\009\247\249\006\112\153\109\008\115\063\085\014\008\157\034\212\225\060\087\013\238\081\106\008\094\174\131\148\242\096\044\207\117\129\087\140\058\252\098\117\017\184\204\152\170\129\042\002\121\067\021\168\091\232\114\078\174\108\172\193\167\092\217\088\025\090\214\186\080\050\086\135\146\145\058\159\066\058\197\154\214\006\176\240\178\231\192\204\049\192\021\182\126\046\176\246\113\098\225\170\154\233\064\217\068\011\054\190\142\152\029\027\014\077\075\029\144\114\009\133\172\007\057\061\021\006\124\104\139\169\074\066\209\072\013\026\086\122\080\050\214\128\186\165\006\012\157\141\224\024\232\006\027\031\039\200\027\168\066\223\222\020\118\254\046\188\157\131\061\225\024\232\001\215\080\047\254\183\073\017\214\231\172\065\066\250\074\172\076\137\069\070\113\018\138\106\178\145\093\154\137\248\244\085\200\046\201\230\192\237\159\173\015\062\252\000\153\249\025\240\246\247\102\033\211\228\078\017\201\069\052\052\234\143\045\156\032\034\226\061\138\020\229\121\151\143\162\002\167\199\186\006\186\040\175\042\255\211\045\036\175\174\253\071\246\163\160\134\178\150\181\156\006\082\075\251\154\204\101\072\045\092\142\130\134\213\072\204\142\226\233\231\164\000\011\227\103\193\127\190\059\230\173\242\193\234\156\112\044\088\111\139\089\171\116\025\249\243\089\104\014\231\057\090\240\094\164\129\168\052\115\068\167\219\192\055\218\004\118\179\180\097\234\163\004\219\016\021\216\134\168\194\038\068\009\115\146\012\177\044\215\014\097\009\006\008\079\052\066\224\082\003\088\006\170\096\138\138\137\186\064\193\080\040\024\050\199\042\004\205\234\043\067\221\066\007\202\198\234\016\087\147\132\162\161\026\251\113\242\219\218\214\186\112\013\241\134\207\028\127\004\069\006\193\053\212\135\191\167\105\109\008\053\115\061\072\107\043\176\176\165\180\228\032\169\041\205\174\066\078\079\009\210\218\242\144\214\146\135\140\142\034\148\140\052\248\107\082\044\082\060\013\075\125\200\234\041\065\203\070\023\166\238\214\012\010\081\108\032\076\017\029\097\239\239\006\143\048\031\120\132\251\192\037\196\019\174\033\158\240\008\243\066\220\218\024\044\091\047\108\011\079\205\079\064\102\201\006\100\151\210\189\056\105\200\043\203\229\102\206\191\090\061\003\061\060\071\184\166\177\022\053\077\181\072\088\031\015\107\091\075\190\061\149\006\056\210\252\030\145\050\136\020\066\244\181\112\011\059\124\228\229\021\024\025\165\170\040\165\125\159\222\162\161\143\255\253\106\104\165\043\220\214\114\022\144\095\153\193\052\054\114\099\107\050\098\177\046\063\006\203\147\035\017\183\118\001\007\130\171\055\044\068\216\162\064\204\094\230\137\240\229\142\240\136\212\131\095\052\165\126\150\112\141\048\198\236\149\246\240\142\209\226\083\062\059\209\016\062\209\070\140\010\090\250\107\194\033\084\019\214\065\042\240\093\164\199\190\159\002\065\183\249\154\112\091\160\001\159\024\202\026\140\136\016\162\046\208\180\209\135\158\157\009\172\125\172\097\230\097\010\045\107\253\201\019\171\012\041\077\089\104\219\024\065\223\145\148\067\003\022\094\038\028\180\209\041\052\112\048\133\142\141\017\095\023\079\193\158\067\160\027\071\251\242\006\138\048\116\208\133\150\181\014\052\173\244\033\173\045\135\153\042\018\152\169\036\206\191\143\021\065\091\129\191\071\074\165\099\107\004\009\077\057\104\089\232\064\201\072\141\149\194\196\205\138\021\146\178\003\107\111\071\216\248\056\051\096\068\153\192\236\069\033\152\023\023\142\200\229\017\088\184\122\046\035\130\171\211\150\033\189\128\062\208\124\148\215\087\034\175\060\015\231\047\253\153\003\072\233\096\089\117\025\154\058\154\209\217\215\133\150\174\086\190\071\128\172\001\221\050\226\229\239\201\254\156\070\185\178\050\072\073\178\098\080\001\076\070\070\120\173\046\223\172\046\037\201\099\229\092\061\092\144\149\159\133\182\222\246\063\165\146\127\181\040\085\036\183\149\085\154\196\087\187\231\087\146\005\072\226\077\055\121\068\175\010\199\220\165\129\152\029\231\139\229\027\066\177\040\041\004\161\139\124\049\107\145\059\252\022\090\195\125\174\049\124\035\109\225\024\098\010\251\096\099\056\133\154\194\057\220\004\246\033\186\112\008\211\132\085\160\010\076\188\085\096\225\171\009\051\095\021\056\134\107\097\105\182\011\023\139\108\066\084\096\228\161\008\183\121\186\240\095\100\134\089\075\237\049\069\211\218\064\160\101\107\004\109\091\125\184\205\182\131\077\128\033\244\029\117\161\101\165\003\085\083\077\136\171\074\177\144\041\104\035\139\096\230\065\041\154\035\028\003\221\057\090\151\213\081\018\010\211\218\000\250\246\198\048\112\180\128\158\163\046\220\194\108\097\233\097\201\110\069\074\075\022\211\228\103\064\076\069\146\045\132\164\134\012\111\003\071\115\118\031\178\250\114\112\009\116\224\009\224\052\042\078\089\095\005\150\030\214\176\240\176\229\184\068\207\214\024\198\046\214\048\247\176\135\141\175\051\188\102\251\096\246\226\080\204\093\018\198\227\225\231\045\013\067\124\218\074\100\022\111\064\073\077\017\138\171\203\145\095\158\143\154\166\202\063\181\115\147\002\012\143\141\160\179\191\011\221\027\123\049\048\186\145\239\014\162\018\114\070\065\006\154\187\090\208\063\050\128\152\184\104\152\091\153\065\071\079\011\154\218\026\204\122\166\075\030\116\244\180\249\054\113\186\214\062\053\043\021\237\125\029\232\031\030\064\102\126\038\255\014\034\148\252\171\117\234\220\041\206\084\178\074\215\243\181\238\217\165\169\072\043\092\195\193\107\098\198\114\044\092\053\007\011\086\007\098\105\106\008\086\102\134\033\114\181\031\188\230\056\194\127\129\016\003\112\155\109\013\143\008\027\216\006\152\192\218\215\028\118\001\150\176\015\182\128\093\160\041\044\124\116\097\234\173\194\049\128\137\151\050\043\128\133\159\010\091\008\239\069\090\112\153\109\000\067\023\085\086\034\191\104\075\216\134\104\099\138\182\173\137\192\204\211\030\134\078\134\176\014\208\133\243\108\061\134\022\205\061\245\097\230\110\010\105\045\057\168\024\107\048\076\075\001\032\089\006\018\154\153\187\029\007\128\026\086\250\028\232\169\153\105\097\186\226\076\200\235\171\064\217\132\098\010\021\024\187\024\243\115\041\077\057\188\046\061\021\154\148\247\091\027\064\074\075\001\050\090\010\208\177\054\132\172\182\050\140\156\052\081\218\148\002\079\031\119\072\201\075\065\070\089\154\039\133\090\186\089\195\196\209\028\022\238\118\048\118\033\128\200\134\099\014\151\089\238\012\017\139\210\065\042\014\037\102\172\224\059\115\233\228\231\150\210\157\000\133\072\203\079\198\241\211\199\095\149\001\058\251\058\249\010\214\029\123\119\242\093\124\219\247\236\192\193\137\131\216\185\127\055\014\031\063\130\203\111\093\197\233\011\103\176\101\215\086\228\150\228\242\200\249\229\009\203\120\188\124\082\234\026\164\100\038\243\180\113\082\032\026\059\223\063\178\145\045\074\085\067\053\058\122\059\094\253\231\254\088\207\192\237\238\116\181\109\078\121\026\178\203\082\185\153\133\078\063\041\069\082\246\010\044\089\019\137\165\041\179\177\190\104\033\043\192\172\088\023\184\207\182\135\111\164\035\236\103\153\194\041\212\028\190\243\029\225\018\102\013\075\031\099\088\120\027\194\038\208\008\086\126\186\048\246\208\132\145\187\050\012\220\148\096\236\161\005\083\111\053\088\005\168\195\061\082\023\030\081\026\112\159\103\000\075\111\061\104\218\042\192\210\095\013\250\030\242\152\162\107\103\038\048\118\179\134\165\151\025\251\014\050\033\142\161\006\176\246\051\133\190\163\001\251\111\202\221\013\156\044\160\109\107\044\204\227\237\205\160\231\096\206\207\041\128\083\051\211\134\130\129\050\094\151\124\029\211\165\167\099\134\178\056\196\213\164\032\175\175\196\177\133\130\129\010\102\042\138\193\198\219\024\182\126\102\252\094\082\038\123\127\087\072\169\200\066\199\086\013\243\151\007\195\194\198\156\219\195\137\036\098\096\161\015\109\051\029\225\157\133\228\018\092\173\025\058\166\172\192\101\150\007\187\130\240\069\179\176\052\105\017\086\164\044\230\076\128\004\158\158\159\198\001\032\089\128\140\194\012\084\053\086\050\188\251\226\106\239\105\071\086\097\022\014\078\028\192\209\147\019\056\125\254\012\223\040\122\242\220\041\156\058\119\026\067\099\195\124\171\200\224\166\065\140\237\216\194\202\146\152\156\128\140\220\013\200\041\204\193\200\150\081\244\013\015\096\104\108\132\045\200\192\200\032\063\111\239\237\192\224\232\224\075\255\214\139\139\070\204\101\022\167\114\247\082\122\033\221\224\145\196\143\036\252\117\057\171\184\181\109\081\194\092\204\093\225\135\005\241\194\188\159\112\128\224\104\031\004\045\116\135\207\124\007\184\133\091\115\013\192\037\148\082\063\067\024\123\041\193\196\075\009\090\014\050\208\117\086\128\129\155\034\116\029\084\161\102\174\012\003\023\013\216\005\235\194\043\210\012\110\243\180\224\056\091\003\014\193\198\048\114\085\099\087\096\236\173\132\041\218\118\038\002\029\123\019\152\184\026\194\204\091\019\218\246\138\208\119\210\098\151\064\041\027\159\110\115\093\144\155\016\010\221\132\031\041\035\208\119\052\131\153\135\061\076\221\109\161\107\107\004\025\029\005\076\149\153\014\057\029\037\062\249\020\000\082\036\047\171\173\000\053\051\021\216\004\232\193\218\087\015\074\070\010\208\179\053\132\166\169\014\196\021\036\160\100\160\194\019\065\181\205\245\120\056\132\165\131\057\204\236\076\160\105\066\028\001\093\040\027\168\114\170\105\239\239\194\213\065\167\032\033\060\076\010\176\154\121\000\052\254\060\017\005\149\249\108\001\178\138\115\144\085\146\203\151\069\210\062\251\202\149\109\155\182\108\098\005\056\118\234\056\206\095\185\136\051\023\206\226\204\133\115\044\124\026\247\182\231\208\126\190\083\144\046\156\138\142\139\226\189\114\205\010\030\047\223\053\208\131\173\187\182\178\098\236\218\191\027\157\003\093\200\046\202\070\093\115\061\042\234\171\112\120\130\134\047\253\245\162\152\099\077\122\002\054\020\165\034\057\039\001\169\249\107\088\001\146\115\086\179\255\095\146\024\133\168\149\225\152\191\034\008\179\151\122\035\032\202\021\017\075\102\033\106\085\004\252\035\221\224\028\098\003\251\032\115\152\123\145\041\215\194\188\120\119\068\036\154\194\043\074\015\177\233\110\240\090\096\000\109\071\089\104\218\042\065\201\072\200\242\178\244\211\133\117\128\006\002\023\091\113\198\224\028\110\136\176\101\046\028\036\026\122\168\096\138\174\131\153\064\219\206\152\209\061\085\051\210\028\117\062\177\148\227\147\095\215\176\208\099\032\135\034\118\074\009\085\076\180\216\023\147\041\182\245\117\130\049\159\076\091\024\057\083\253\222\014\102\110\086\048\119\183\134\182\141\001\052\045\117\161\109\163\011\057\093\121\040\232\203\195\038\192\024\090\086\170\080\048\080\132\137\139\005\212\012\052\032\174\036\009\045\011\061\216\007\184\114\080\105\230\100\006\215\000\103\168\026\105\192\192\222\148\107\006\234\102\058\252\255\176\242\034\064\200\017\238\161\158\240\159\239\143\152\248\072\044\094\019\197\021\193\204\146\100\148\212\230\161\176\042\007\185\229\089\188\203\235\139\081\219\082\129\218\230\026\188\127\253\250\243\226\206\217\243\103\120\222\208\190\195\007\249\066\071\082\016\026\240\120\226\236\073\156\058\119\134\205\255\193\137\067\044\212\194\242\066\120\249\123\192\127\150\047\214\164\036\162\181\187\013\195\099\116\161\243\086\236\059\188\159\239\033\034\055\209\214\211\193\150\226\226\149\063\055\153\082\209\136\006\074\230\020\101\243\245\117\105\121\105\156\169\036\101\174\226\113\182\052\230\046\167\034\009\043\210\230\097\121\202\002\068\196\005\098\222\242\032\132\044\242\133\071\168\043\220\195\156\048\043\198\027\086\190\198\112\012\182\132\141\191\041\244\157\181\224\016\106\192\017\190\127\172\062\098\051\173\145\084\233\001\187\089\090\080\183\082\130\146\049\101\091\242\208\115\212\128\137\167\026\156\103\235\195\046\068\147\083\068\011\063\085\024\123\042\065\223\077\073\024\004\234\058\152\112\068\110\224\104\202\145\055\069\225\100\218\045\060\236\160\111\103\204\010\032\165\033\139\025\074\226\152\169\034\206\025\001\005\133\004\209\026\058\081\081\199\028\234\132\012\154\107\064\211\074\019\038\110\006\048\247\048\101\068\080\221\066\021\074\006\074\144\084\147\128\150\141\026\228\245\101\161\108\162\198\193\161\180\186\028\036\085\100\152\021\228\060\139\240\004\091\216\251\219\193\109\150\011\167\130\174\179\188\056\059\033\043\068\096\145\173\143\035\167\133\017\139\195\216\244\207\095\054\155\253\063\017\066\050\139\083\176\062\039\001\217\101\105\200\045\207\064\065\101\038\074\235\010\080\209\080\136\226\234\124\244\013\247\241\213\109\180\168\070\191\034\113\057\007\130\071\078\028\198\196\169\099\056\114\226\255\215\213\149\054\053\153\102\081\127\194\244\040\075\194\146\253\205\246\102\037\121\019\200\070\002\033\064\100\081\150\065\112\001\212\008\202\190\136\008\018\016\068\016\025\065\091\025\183\070\092\144\069\084\090\108\219\013\219\110\167\166\218\154\158\169\154\143\061\031\230\039\204\079\056\083\247\050\078\213\116\170\222\079\169\084\170\242\228\222\123\238\185\231\185\103\155\015\148\202\001\101\005\042\013\100\042\069\222\002\085\117\251\080\182\191\020\237\189\237\220\053\060\222\088\197\234\211\117\060\127\185\201\000\240\238\253\111\184\004\080\134\248\173\212\140\102\016\164\020\122\253\254\053\038\046\077\048\158\056\217\077\075\172\207\160\047\217\197\106\038\122\070\102\058\176\184\145\068\255\068\051\202\234\163\040\059\088\136\138\067\197\040\172\010\163\168\054\130\154\163\229\144\074\108\008\087\121\225\046\182\064\231\085\034\055\110\131\049\036\135\181\048\003\098\116\055\060\149\114\008\121\025\144\155\211\033\051\202\145\097\078\135\045\162\135\059\046\192\030\203\134\035\166\096\128\104\143\081\153\215\067\157\151\130\093\153\086\205\156\064\195\153\092\043\079\225\136\131\183\133\061\080\216\005\228\149\134\016\040\047\128\204\168\192\110\085\026\035\126\058\012\061\029\058\203\182\108\252\007\048\211\240\166\072\015\049\164\064\182\035\013\098\072\007\149\051\011\074\071\022\126\151\253\021\012\030\029\140\185\058\152\124\002\180\146\002\042\231\014\024\164\210\160\016\213\208\186\012\016\131\022\088\066\102\088\195\102\088\066\014\136\126\039\252\241\048\180\046\035\003\079\106\021\041\245\007\203\131\136\215\149\032\209\213\136\067\173\117\216\127\100\047\139\066\250\199\090\056\165\158\025\239\193\224\068\063\146\211\103\048\116\225\052\206\077\210\100\112\010\127\188\049\131\183\031\222\178\116\139\070\179\059\064\238\018\182\190\127\129\247\031\183\241\237\171\045\108\189\126\137\023\223\111\113\105\120\245\238\053\046\205\205\160\111\168\143\093\200\202\171\226\152\154\157\194\194\157\063\225\249\119\155\120\188\177\130\187\015\022\057\131\108\255\244\001\079\095\060\103\107\247\127\255\070\127\072\186\002\090\044\125\251\222\142\233\051\185\149\012\140\012\096\100\050\137\179\227\228\249\123\002\039\122\143\242\080\107\120\038\129\147\103\105\229\109\037\170\154\074\081\113\184\152\229\239\241\003\133\040\174\203\135\059\102\133\189\208\008\115\080\007\131\079\013\075\088\128\144\167\132\224\147\195\024\078\135\054\055\021\123\180\187\145\162\075\065\170\064\060\075\042\004\175\002\098\036\011\134\016\225\131\116\232\131\169\200\041\081\177\198\064\240\101\098\215\087\170\180\185\076\171\154\209\060\069\062\245\241\244\099\019\171\231\136\072\220\242\201\076\010\040\157\006\152\252\057\176\132\036\126\143\034\222\093\228\096\254\222\081\096\071\176\202\132\202\227\030\198\017\166\160\026\186\092\057\226\071\188\080\187\210\097\203\055\194\023\151\096\244\233\160\118\101\193\150\111\133\061\223\005\099\174\005\174\152\019\206\168\005\142\002\043\172\097\019\012\121\002\103\020\018\136\068\042\162\156\250\149\118\029\244\094\011\034\251\138\080\113\048\142\250\019\053\028\017\213\071\042\016\171\013\096\104\246\000\062\252\117\026\139\079\134\209\147\076\160\111\180\029\003\227\093\108\035\055\112\190\155\253\130\047\094\153\192\195\181\251\060\235\167\168\188\060\127\025\179\095\095\193\202\198\010\222\127\124\143\015\159\062\098\251\199\237\157\232\126\182\142\007\043\015\119\136\162\249\025\246\029\164\050\048\056\060\136\229\039\043\088\123\246\004\143\214\150\025\244\125\250\249\047\120\249\230\021\030\173\175\096\101\099\237\127\235\097\190\220\041\032\013\225\231\095\062\179\215\239\228\236\069\094\102\213\127\174\031\189\067\189\220\118\246\012\118\033\209\221\132\227\093\245\060\004\162\117\183\052\229\252\067\162\146\015\062\127\191\132\112\149\007\209\154\000\252\101\018\131\115\115\080\224\071\159\167\129\224\213\129\110\118\041\221\169\208\072\196\219\252\030\123\180\123\144\162\221\195\037\064\045\017\072\084\064\031\144\065\229\217\003\189\095\014\075\088\139\156\152\001\006\191\006\187\118\107\210\231\118\107\211\152\123\215\121\068\070\218\158\152\143\219\046\066\254\036\211\082\210\149\049\099\022\244\094\138\122\039\052\004\224\114\148\044\077\178\071\040\213\083\154\209\034\090\111\135\084\042\194\028\018\032\070\178\081\218\036\034\191\218\002\181\148\193\145\173\149\148\208\072\074\184\139\092\144\138\073\218\100\071\078\076\128\024\206\130\084\098\229\026\231\042\114\113\207\079\072\095\204\179\035\077\144\067\102\204\100\194\136\048\192\190\198\018\052\117\087\050\034\174\060\092\140\134\246\018\172\189\063\133\207\191\158\197\234\155\126\156\158\108\228\118\106\224\124\023\134\046\012\224\236\068\031\198\046\141\098\116\058\137\235\119\230\241\203\127\245\128\155\047\191\197\149\235\243\184\183\124\159\091\063\138\228\119\063\188\099\095\193\165\199\015\177\188\190\202\045\222\141\059\011\168\174\175\226\245\244\093\253\157\092\002\168\117\092\123\182\206\160\238\249\214\038\046\095\157\197\232\197\049\222\051\064\047\082\009\211\130\233\047\042\162\229\245\101\052\181\054\098\048\121\134\075\064\091\239\041\116\014\116\224\100\119\043\090\200\214\166\187\025\205\157\245\056\214\117\016\245\045\085\104\236\168\227\251\014\053\199\246\162\250\088\049\194\251\037\148\212\022\034\086\027\102\012\064\232\222\028\212\194\232\039\138\093\205\216\045\083\076\227\178\064\007\159\042\164\032\211\034\131\194\033\131\222\159\005\083\080\001\141\039\019\106\119\038\004\175\018\166\128\014\134\060\053\196\160\017\187\178\109\154\185\108\135\142\083\059\161\126\150\105\069\188\060\236\017\131\018\108\249\057\076\050\080\075\072\007\099\205\247\066\225\208\066\233\204\128\037\172\129\201\111\226\057\128\024\210\194\025\019\032\149\090\224\040\020\185\012\216\163\148\166\116\176\228\027\160\207\211\066\231\085\193\028\052\032\167\208\129\096\133\023\166\128\018\135\058\075\081\223\022\133\175\220\142\188\050\039\092\081\250\126\002\122\005\156\137\210\244\025\200\048\041\144\109\081\033\167\200\134\230\211\081\244\078\239\101\036\091\155\040\198\248\141\195\184\187\217\138\133\039\077\088\088\109\193\240\204\113\180\244\029\070\095\178\013\231\038\073\036\058\130\228\212\048\206\207\140\097\116\106\004\055\023\111\114\148\018\014\160\131\155\187\113\021\079\054\055\240\233\231\063\227\205\246\027\038\137\030\173\061\198\179\173\077\174\237\100\043\083\219\080\131\068\251\113\180\116\036\216\118\102\124\106\028\215\111\047\096\225\238\077\044\061\190\207\153\128\252\135\190\080\193\228\022\066\247\006\137\020\250\248\211\071\244\015\245\241\103\041\163\208\158\195\086\054\178\106\195\137\206\004\142\118\037\144\232\061\198\081\159\232\057\132\206\161\004\131\218\227\061\013\104\234\041\231\167\184\142\186\129\114\206\014\149\205\033\020\214\185\096\045\160\172\077\037\057\147\015\219\232\211\064\229\164\161\094\010\100\134\084\100\090\210\161\245\202\160\015\200\161\150\100\080\185\050\025\131\105\221\042\232\189\090\008\146\154\203\241\046\181\075\119\199\016\016\161\116\234\160\150\140\208\121\169\014\187\161\243\090\096\160\148\079\051\250\136\009\182\002\007\156\081\063\244\062\007\050\044\042\164\027\051\160\243\106\097\014\218\097\244\219\225\136\058\145\019\019\033\197\109\240\196\115\096\010\232\097\141\024\032\230\235\097\047\180\065\200\213\192\028\050\192\089\068\204\149\132\112\181\031\142\168\128\130\003\118\132\107\109\008\084\057\224\045\183\193\081\184\051\046\246\149\021\192\020\112\066\012\058\096\014\056\096\244\155\016\061\224\067\067\087\004\039\199\226\104\031\173\065\069\115\016\173\035\229\104\073\150\226\212\249\189\152\095\234\197\229\091\003\056\125\254\020\063\099\179\103\048\253\245\004\110\061\184\142\107\119\103\049\125\237\002\219\200\209\197\078\122\017\008\036\026\120\237\217\042\126\253\215\063\241\183\127\252\029\223\189\125\133\251\043\015\176\242\116\021\087\111\094\099\242\135\216\190\228\228\008\250\135\123\240\096\125\009\091\175\183\112\111\249\030\191\079\135\255\205\163\197\255\035\128\238\061\090\194\226\195\069\070\253\100\122\121\244\100\051\198\103\198\113\107\233\054\215\253\171\183\230\113\097\118\002\109\003\109\104\031\236\064\219\096\011\018\125\135\144\232\107\064\251\112\035\090\006\026\208\145\172\071\247\133\058\116\079\028\224\037\089\013\109\021\136\053\228\162\186\149\166\128\030\014\054\165\075\206\081\046\023\211\224\138\089\057\163\202\076\169\028\156\042\087\006\244\129\044\168\189\233\080\056\211\161\113\103\065\235\081\066\229\206\134\198\173\132\214\163\226\105\239\127\000\142\105\169\093\220\130\045\173\000\000\000\000\073\069\078\068\174\066\096\130")
        return (getcustomasset or getsynasset)(file)
    end)
    if ok then ABOUT_ASSET=asset end
end

------------------------------------------------------------------------
-- Services and state
------------------------------------------------------------------------
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

for _,page in ipairs(Pages) do
    if page.name=="Settings" then
        for _,data in ipairs(page.tabs[1].cards) do
            
        end
    end
end

local player = Players.LocalPlayer
assert(player, "Run the KarmaPanda UI on the client")
local parent = player:WaitForChild("PlayerGui")
local prototype=parent:FindFirstChild("KarmaPanda_UI_Prototype")
if prototype then prototype:Destroy() end
local old = parent:FindFirstChild(CONFIG.GuiName)
local closeOnExecution = Bridge.Initial().close_on_injection==true
if old then old:Destroy() end

local ui = {scale = 1, opacity = .96, locked = false, mobile = true, key = "K", reduceMotion = false,
    w = CONFIG.Width, h = CONFIG.Height}
ui.scale=Bridge.Initial().ui_scale or 1;ui.opacity=Bridge.Initial().ui_opacity or .96;ui.locked=Bridge.Initial().lock_ui;ui.mobile=Bridge.Initial().mobile_toggle;ui.key=Bridge.Initial().ui_toggle_key or "K"

local render, selectPage, update, applyTheme, fit, layout, visible, paintNav
local showTip, hideTip, clearLeaves, notify, onButton, requestRender, setStatus
local activePage, activeTabs = 1, {}
local function restoreNavigation()
    local state=Bridge.Initial().ui_state or {}
    activePage=math.clamp(math.floor(tonumber(state.page) or 1),1,#Pages)
    activeTabs={}
    for i,page in ipairs(Pages)do activeTabs[i]=math.clamp(math.floor(tonumber((state.tabs or {})[tostring(i)]) or 1),1,#page.tabs) end
end
local function saveNavigation()
    local tabs={};for i,v in pairs(activeTabs)do tabs[tostring(i)]=v end
    Bridge.SaveUI({tabs=tabs,page=activePage})
end
restoreNavigation()
local saveWindowState
local pendingFit=false
local activeSlider, dragInput, dragStart, dragPosition, dragging, resizing
local pendingRender, ready = false, false
local sessionStarted = os.clock()
local sessionLabels = {}
local homeLabels={}
local lastFPS,lastPing,lastMemory=0,0,0
local leafEnabled = true
local statusText = "Idle"
local compact, columnCount, tabsBelow = false, 2, false
local lastQuery = ""
local connections = {}

------------------------------------------------------------------------
-- Theme
------------------------------------------------------------------------
local F = {regular = Enum.Font.Gotham, medium = Enum.Font.GothamMedium, bold = Enum.Font.GothamBold, mono = Enum.Font.RobotoMono}

local C = {
    bg       = Color3.fromRGB(15, 15, 18),
    panel    = Color3.fromRGB(19, 18, 22),
    panelHi  = Color3.fromRGB(30, 30, 35),
    field    = Color3.fromRGB(14, 13, 17),
    fieldHi  = Color3.fromRGB(30, 25, 30),
    line     = Color3.fromRGB(64, 61, 67),
    lineSoft = Color3.fromRGB(45, 43, 48),
    text     = Color3.fromRGB(241, 239, 242),
    sub      = Color3.fromRGB(185, 181, 190),
    dim      = Color3.fromRGB(145, 140, 151),
    knob     = Color3.fromRGB(157, 150, 162),
    good     = Color3.fromRGB(74, 222, 128),
    white    = Color3.new(1, 1, 1),
}

local function setAccent(hex)
    local rgb = {tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)}
    C.accent = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
    C.onAccent = (C.accent.R*.299+C.accent.G*.587+C.accent.B*.114)>.7 and C.bg or C.white
    C.accentHi = C.accent:Lerp(C.white, .38)
    C.accentDeep = C.accent:Lerp(Color3.new(0, 0, 0), .32)
    C.accentLine = C.accent:Lerp(C.bg, .42)
    C.accentSoft = C.accent:Lerp(C.bg, .83)
    return rgb
end
local accentRGB = setAccent(CONFIG.Accent)

-- Objects register the palette key they use, so a theme change can repaint them.
local themed = {}
local function bind(obj, prop, key)
    obj[prop] = C[key]
    themed[#themed + 1] = {obj, prop, key}
    return obj
end
local function bindSeq(obj, a, b)
    obj.Color = ColorSequence.new(C[a], C[b])
    themed[#themed + 1] = {obj, "Color", {a, b}}
    return obj
end
local function pruneThemed()
    local keep = {}
    for _, ref in ipairs(themed) do if ref[1].Parent then keep[#keep + 1] = ref end end
    themed = keep
end
local function repaint()
    pruneThemed()
    for _, ref in ipairs(themed) do
        local obj, prop, key = ref[1], ref[2], ref[3]
        if type(key) == "table" then obj[prop] = ColorSequence.new(C[key[1]], C[key[2]]) else obj[prop] = C[key] end
    end
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function make(class, props, at)
    local obj = Instance.new(class)
    if props then for k, v in pairs(props) do obj[k] = v end end
    if at then obj.Parent = at end
    return obj
end
local function corner(obj, r) return make("UICorner", {CornerRadius = UDim.new(0, r or 6)}, obj) end
local function stroke(obj, key, transparency)
    local s = make("UIStroke", {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Transparency = transparency or 0}, obj)
    return bind(s, "Color", key or "line")
end
local function padding(obj, l, r, t, b)
    return make("UIPadding", {PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
        PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0)}, obj)
end
local function vlist(obj, gap)
    return make("UIListLayout", {Padding = UDim.new(0, gap or 0), SortOrder = Enum.SortOrder.LayoutOrder}, obj)
end
local function hlist(obj, gap)
    return make("UIListLayout", {Padding = UDim.new(0, gap or 0), SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center}, obj)
end
local function label(at, str, size, colorKey, font, props)
    local l = make("TextLabel", {BackgroundTransparency = 1, BorderSizePixel = 0, Text = str or "", TextSize = size or 12,
        Font = font or F.regular, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, (size or 12) + 6)}, at)
    bind(l, "TextColor3", colorKey or "text")
    if props then for k, v in pairs(props) do l[k] = v end end
    return l
end
local function tween(obj, t, props)
    if ui.reduceMotion then for k, v in pairs(props) do obj[k] = v end return end
    TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end
-- Shared hover treatment. It changes paint only, so hit targets never shift.
local function polish(obj, edge, active, baseKey, filled)
    local hovered=false
    -- Use the control's own outline so padding cannot offset a second highlight.
    local outline=edge or stroke(obj,"lineSoft",1)
    local restingTransparency=outline.Transparency
    local function paint()
        if not obj.Parent then return end
        local on=active and active() or false
        tween(outline,.16,{Color=on and C.accent or hovered and C.accentLine or C.lineSoft,
            Transparency=on and .15 or hovered and .35 or restingTransparency})
        if filled then tween(obj,.16,{BackgroundColor3=on and C.accentDeep or hovered and C.fieldHi or C[baseKey or "field"]}) end
    end
    obj.MouseEnter:Connect(function()hovered=true;paint()end)
    obj.MouseLeave:Connect(function()hovered=false;paint()end)
    paint()
    return paint
end

local function glyph(at,g,size,colorKey)
    if type(g)=="string" and g:find("^rbx") then
        local image=make("ImageLabel",{BackgroundTransparency=1,Image=g,Size=UDim2.fromOffset(size,size),ScaleType=Enum.ScaleType.Fit},at)
        return bind(image,"ImageColor3",colorKey)
    end
    local icon=make("Frame",{Name="LineIcon",BackgroundTransparency=1,Size=UDim2.fromOffset(size+4,size+4)},at)
    local function line(x,y,u,v)
        local dx,dy=(u-x)*size,(v-y)*size
        local part=make("Frame",{Name="Ink",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(2+(x+u)*size/2,2+(y+v)*size/2),
            Size=UDim2.fromOffset(math.sqrt(dx*dx+dy*dy),1.25),Rotation=math.deg(math.atan2(dy,dx)),BorderSizePixel=0},icon)
        bind(part,"BackgroundColor3",colorKey)
    end
    local function circle(x,y,radius)
        local ring=make("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(2+(x-radius)*size,2+(y-radius)*size),Size=UDim2.fromOffset(radius*size*2,radius*size*2)},icon)
        corner(ring,99);stroke(ring,colorKey).Thickness=1.25
    end
    if g=="⌂" then line(.1,.45,.5,.1);line(.5,.1,.9,.45);line(.23,.35,.23,.88);line(.77,.35,.77,.88);line(.23,.88,.77,.88)
    elseif g=="▷" then line(.23,.13,.85,.5);line(.85,.5,.23,.87);line(.23,.87,.23,.13)
    elseif g=="≋" or g=="⊞" then for i=1,3 do local y=i*.25;line(.12,y,.88,y);circle(i%2==0 and .65 or .35,y,.09)end
    elseif g=="◎" or g=="◉" then circle(.5,.5,.36);circle(.5,.5,.12)
    elseif g=="◷" or g=="↻" or g=="◌" then circle(.5,.5,.37);line(.5,.5,.5,.23);line(.5,.5,.74,.63)
    elseif g=="♧" then circle(.5,.22,.13);circle(.2,.77,.13);circle(.8,.77,.13);line(.44,.35,.25,.64);line(.56,.35,.75,.64);line(.34,.77,.66,.77)
    elseif g=="⚙" then circle(.5,.5,.24);for i=0,7 do local t=i*math.pi/4;line(.5+math.cos(t)*.29,.5+math.sin(t)*.29,.5+math.cos(t)*.44,.5+math.sin(t)*.44)end
    elseif g=="ϟ" then line(.65,.05,.25,.55);line(.25,.55,.65,.45);line(.65,.45,.35,.95)
    else line(.5,.08,.88,.5);line(.88,.5,.5,.92);line(.5,.92,.12,.5);line(.12,.5,.5,.08)end
    return icon
end
local function tint(obj,color)
    if obj:IsA("ImageLabel") then obj.ImageColor3=color
    elseif obj:IsA("Frame") then
        for _,part in ipairs(obj:GetDescendants())do
            if part:IsA("UIStroke") then part.Color=color elseif part.Name=="Ink" then part.BackgroundColor3=color end
        end
    else obj.TextColor3=color end
end
local function chevron(at, colorKey)
    return label(at, "›", 16, colorKey or "sub", F.bold, {Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(.5, .5),
        TextXAlignment = Enum.TextXAlignment.Center, Rotation = 90})
end
local function logoMark(at, textSize)
    if LOGO_ASSET ~= "" then
        return make("ImageLabel", {BackgroundTransparency = 1, Image = LOGO_ASSET, AnchorPoint = Vector2.new(.5, .5),
            Position = UDim2.fromScale(.5, .5), Size = UDim2.new(1, -6, 1, -6), ScaleType = Enum.ScaleType.Fit}, at)
    end
    return label(at, "KP", textSize, "accentHi", F.bold, {Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center})
end
local function decimals(step)
    local d = tostring(step):match("%.(%d+)$")
    return d and #d or 0
end
local function fmtNumber(v, step)
    local d = decimals(step or 1)
    if d == 0 then
        local s = tostring(math.floor(v + .5))
        local sign, digits = s:match("^(-?)(%d+)$")
        if digits and #digits > 3 then
            digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
            s = sign .. digits
        end
        return s
    end
    local s = string.format("%." .. d .. "f", v)
    s = s:gsub("(%.%d-)0+$", "%1")
    s = s:gsub("%.$", ".0")
    return s
end
local function suffixOf(item)
    local raw = item.suffix or ""
    local trimmed = raw:gsub("^%s+", "")
    if trimmed == "s" or trimmed == "%" then return trimmed end
    return raw
end
local function sliderText(item)
    local suffix = suffixOf(item)
    if item.value == 0 and item.min == 0 and suffix == "" then return "Off" end
    return fmtNumber(item.value, item.step) .. suffix
end
local function describe(item) return nil end
local function pageIndex(name)
    for i, p in ipairs(Pages) do if p.name == name then return i end end
    return 1
end
local function findSetting(name)
    for _,page in ipairs(Pages)do
        for _,tab in ipairs(page.tabs)do
            local sections=tab.subtabs or {tab}
            for _,section in ipairs(sections)do
                for _,data in ipairs(section.cards or {})do
                    for _,item in ipairs(data.items)do if item.label==name then return item end end
                end
            end
        end
    end
end
local function setSetting(name, value)
    local item = findSetting(name)
    if item then item.value = value end
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local gui = make("ScreenGui", {Name = CONFIG.GuiName, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 90,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, parent)
local root = make("Frame", {Name = "Window", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
    Size = UDim2.fromOffset(ui.w, ui.h), BorderSizePixel = 0, ClipsDescendants = true}, gui)
bind(root, "BackgroundColor3", "bg"); corner(root, 10); stroke(root, "line")
-- Keep text and panel contrast consistent across the window.
local scale = make("UIScale", {Scale = 1}, root)

local leafLayer = make("Frame", {Name = "FallingLeaves", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    ClipsDescendants = true, ZIndex = 0}, root)

-- Top bar ---------------------------------------------------------------
local top = make("Frame", {Name = "TopBar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44)}, root)
local logoBox = make("Frame", {Name = "Logo", Position = UDim2.fromOffset(10, 7), Size = UDim2.fromOffset(30, 30), BorderSizePixel = 0}, top)
bind(logoBox, "BackgroundColor3", "accentSoft"); corner(logoBox, 8); stroke(logoBox, "accentLine")
logoMark(logoBox, 14)
local brand = label(top, string.upper(CONFIG.Brand), 13, "text", F.bold, {Position = UDim2.fromOffset(49, 12), Size = UDim2.fromOffset(170, 20)})

local cluster = make("Frame", {Name = "Controls", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0),
    Size = UDim2.new(0, 520, 1, 0), BackgroundTransparency = 1}, top)
hlist(cluster, 6).HorizontalAlignment = Enum.HorizontalAlignment.Right
local badge = label(cluster, CONFIG.Badge, 10, "accentHi", F.mono, {AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24),
    BackgroundTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1})
bind(badge, "BackgroundColor3", "accentSoft"); corner(badge, 4); stroke(badge, "accentLine"); padding(badge, 10, 10, 0, 0)

local searchBox = make("Frame", {Name = "Search", Size = UDim2.fromOffset(190, 30), BorderSizePixel = 0, LayoutOrder = 2}, cluster)
bind(searchBox, "BackgroundColor3", "field"); corner(searchBox, 6)
local searchStroke = stroke(searchBox, "line")
local magnifier = make("Frame", {BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 10, .5, 0),
    Size = UDim2.fromOffset(14, 14)}, searchBox)
local ring = make("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.fromOffset(9, 9)}, magnifier)
corner(ring, 99); stroke(ring, "sub").Thickness = 1.5
bind(make("Frame", {BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(11, 11),
    Size = UDim2.fromOffset(5, 2), Rotation = 45}, magnifier), "BackgroundColor3", "sub")
local search = make("TextBox", {Text = "", PlaceholderText = "Search", ClearTextOnFocus = false, Font = F.regular, TextSize = 12,
    BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true,
    Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -62, 1, 0)}, searchBox)
bind(search, "TextColor3", "text"); bind(search, "PlaceholderColor3", "dim")
local slashKey = label(searchBox, "/", 10, "sub", F.mono, {AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -6, .5, 0),
    Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center})
bind(slashKey, "BackgroundColor3", "panel"); corner(slashKey, 4); stroke(slashKey, "line")
search.Focused:Connect(function() tween(searchStroke, .15, {Color = C.accentLine}) end)
search.FocusLost:Connect(function() tween(searchStroke, .15, {Color = C.line}) end)
do
 local shine=polish(searchBox,searchStroke,function()return UIS:GetFocusedTextBox()==search end,"field",false)
 search.Focused:Connect(shine);search.FocusLost:Connect(shine)
end

local function chromeButton(txt, order)
    local b = make("TextButton", {Text = txt, AutoButtonColor = false, Font = F.medium, TextSize = 15, Size = UDim2.fromOffset(28, 28),
        BorderSizePixel = 0, LayoutOrder = order}, cluster)
    bind(b, "BackgroundColor3", "field"); bind(b, "TextColor3", "sub"); corner(b, 6); stroke(b, "line")
    b.MouseEnter:Connect(function() tween(b, .12, {BackgroundColor3 = C.fieldHi, TextColor3 = C.text}) end)
    b.MouseLeave:Connect(function() tween(b, .15, {BackgroundColor3 = C.field, TextColor3 = C.sub}) end)
    polish(b,nil,nil,"field",true)
    return b
end
local minimize = chromeButton("–", 3)

local rule = make("Frame", {Name = "Rule", Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0}, root)
bind(rule, "BackgroundColor3", "accent")
rule.BackgroundTransparency=.5

-- Sidebar ---------------------------------------------------------------
local sidebar = make("Frame", {Name = "Sidebar", Position = UDim2.fromOffset(0, 45), Size = UDim2.new(0, 150, 1, -65), BorderSizePixel=0, BackgroundTransparency=0}, root)
bind(sidebar,"BackgroundColor3","panelHi")
local nav = make("ScrollingFrame", {Name = "Nav", Position = UDim2.fromOffset(7, 10), Size = UDim2.new(1, -15, 1, -18), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 0, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), CanvasPosition=Vector2.new(0,0)}, sidebar)
vlist(nav, 4)

-- Footer ----------------------------------------------------------------
local footer = make("Frame", {Name = "Footer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1}, root)
bind(make("Frame", {Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0}, footer), "BackgroundColor3", "lineSoft")
local dot = make("Frame", {AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 12, .5, 0), Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0}, footer)
bind(dot, "BackgroundColor3", "good"); corner(dot, 99)
local statusLabel = label(footer, "IDLE", 10, "sub", F.mono, {Position = UDim2.fromOffset(24, 1), Size = UDim2.new(.55, -24, 1, 0),
    TextTruncate = Enum.TextTruncate.AtEnd})
local metrics = label(footer, "", 10, "sub", F.mono, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -26, 0, 1),
    Size = UDim2.new(.45, -26, 1, 0), TextXAlignment = Enum.TextXAlignment.Right})
local grip = make("TextButton", {Name = "Resize", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -4, 1, -3), Size = UDim2.fromOffset(14, 14)}, footer)
bind(make("Frame", {BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(10, 1), Rotation = -45}, grip),
    "BackgroundColor3", "dim")
bind(make("Frame", {BorderSizePixel = 0, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(11, 11), Size = UDim2.fromOffset(5, 1), Rotation = -45}, grip),
    "BackgroundColor3", "dim")

-- Content ---------------------------------------------------------------
local content = make("Frame", {Name = "Content", Position = UDim2.fromOffset(162, 59), Size = UDim2.new(1, -172, 1, -65), BackgroundTransparency = 1}, root)
local texture=make("Frame",{Name="ContentTexture",BorderSizePixel=0,BackgroundColor3=C.bg,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ClipsDescendants=true,ZIndex=0},content)

local heading = label(content, "", 16, "text", F.bold, {Position = UDim2.fromOffset(6, 8), Size = UDim2.new(1, -12, 0, 24), TextTruncate=Enum.TextTruncate.AtEnd})
local tabsBar = make("ScrollingFrame", {CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.X, ScrollingDirection=Enum.ScrollingDirection.X, ScrollBarThickness=2, Name = "Tabs", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 13), Size = UDim2.fromOffset(0, 32),
    AutomaticSize = Enum.AutomaticSize.None, BorderSizePixel = 0, Visible = false}, content)
tabsBar.BackgroundTransparency=1; padding(tabsBar,2,2,2,2);hlist(tabsBar,4)
local scroll = make("ScrollingFrame", {Name = "Cards", Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
    ScrollingDirection = Enum.ScrollingDirection.Y}, content)
bind(scroll, "ScrollBarImageColor3", "accentLine")
local stack = make("Frame", {Name = "Stack", Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, scroll)
vlist(stack, 6); padding(stack, 6, 0, 3, 12)
local empty = label(content, "", 12, "sub", F.regular, {Position = UDim2.fromOffset(2, 60), Size = UDim2.new(1, -4, 0, 20), Visible = false})

-- Overlay: dropdown menus, tooltip, toast ---------------------------------
local overlay = make("Frame", {Name = "Overlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 40}, root)
local tip = make("Frame", {Name = "Tooltip", Visible = false, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), BorderSizePixel = 0, ZIndex = 30}, overlay)
bind(tip, "BackgroundColor3", "panelHi"); corner(tip, 5); stroke(tip, "line"); padding(tip, 8, 8, 5, 5)
local tipText = label(tip, "", 10, "sub", F.regular, {AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new()})

local toast = make("Frame", {Name = "Toast", AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -30), Size = UDim2.fromOffset(0, 36),
    AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, Visible = false, ZIndex = 50}, overlay)
bind(toast, "BackgroundColor3", "panelHi"); corner(toast, 7); stroke(toast, "accentLine"); padding(toast, 16, 16, 0, 0)
local toastText = label(toast, "", 11, "text", F.medium, {AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0)})

local reopen = make("TextButton",{Name="Reopen",Text="KP",TextSize=16,Font=F.bold,AutoButtonColor=false,Visible=true,Position=UDim2.new(0,8,1,-56),Size=UDim2.fromOffset(44,44),BorderSizePixel=0,BackgroundTransparency=.4,BackgroundColor3=Color3.new(0,0,0),ZIndex=90},gui)
bind(reopen,"TextColor3","accent");corner(reopen,99);stroke(reopen,"lineSoft")

local function localPos(obj)
    local s = scale.Scale
    return (obj.AbsolutePosition - root.AbsolutePosition) / s, obj.AbsoluteSize / s
end

showTip = function(anchor, str)
    if not str or str == "" then return end
    tipText.Text = str
    local p, sz = localPos(anchor)
    if p.X > root.AbsoluteSize.X / scale.Scale - 240 then
        tip.AnchorPoint = Vector2.new(1, 0); tip.Position = UDim2.fromOffset(p.X - 6, p.Y - 4)
    else
        tip.AnchorPoint = Vector2.new(0, 0); tip.Position = UDim2.fromOffset(p.X + sz.X + 6, p.Y - 4)
    end
    tip.Visible = true
end
hideTip = function() tip.Visible = false end

local toastId = 0
notify = function(message)
    toastId = toastId + 1
    local id = toastId
    toastText.Text = message
    toast.Visible = true
    toast.Position = UDim2.new(.5, 0, 1, -22)
    tween(toast, .2, {Position = UDim2.new(.5, 0, 1, -30)})
    task.delay(2.6, function() if gui.Parent and id == toastId then toast.Visible = false end end)
end

local openMenu
local function closeMenu()
    if not openMenu then return end
    local m = openMenu
    openMenu = nil
    m.shield:Destroy(); m.frame:Destroy()
    if m.onClose then m.onClose() end
end
local confirmation
local function closeConfirmation()
    if confirmation then confirmation:Destroy();confirmation=nil end
end
Bridge.Confirm=function(title,message,action,callback)
    closeMenu();hideTip();closeConfirmation()
    confirmation=make("TextButton",{Name="ConfirmationDialog",Text="",AutoButtonColor=false,Active=true,Size=UDim2.fromScale(1,1),BackgroundColor3=C.bg,BackgroundTransparency=.2,BorderSizePixel=0,ZIndex=90},overlay)
    local panel=make("Frame",{Name="Prompt",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.new(1,-32,0,168),BorderSizePixel=0,ZIndex=2},confirmation)
    make("UISizeConstraint",{MaxSize=Vector2.new(390,168)},panel)
    bind(panel,"BackgroundColor3","panel");corner(panel,6);stroke(panel,"accentLine")
    label(panel,title,13,"text",F.bold,{Position=UDim2.fromOffset(12,10),Size=UDim2.new(1,-24,0,24),TextWrapped=true})
    label(panel,message,11,"sub",F.regular,{Position=UDim2.fromOffset(12,39),Size=UDim2.new(1,-24,0,75),TextWrapped=true})
    local cancel=make("TextButton",{Name="Cancel",Text="Cancel",Font=F.medium,TextSize=11,AutoButtonColor=false,Position=UDim2.new(0,12,1,-40),Size=UDim2.new(.5,-18,0,27),BorderSizePixel=0},panel)
    bind(cancel,"BackgroundColor3","field");bind(cancel,"TextColor3","text");corner(cancel,5);polish(cancel,stroke(cancel,"line"),nil,"field",true)
    local confirm=make("TextButton",{Name="Confirm",Text=action,Font=F.bold,TextSize=11,AutoButtonColor=false,Position=UDim2.new(.5,6,1,-40),Size=UDim2.new(.5,-18,0,27),BorderSizePixel=0},panel)
    bind(confirm,"BackgroundColor3","accentDeep");bind(confirm,"TextColor3","onAccent");corner(confirm,5);polish(confirm,stroke(confirm,"accentLine"),nil,"accentDeep",true)
    cancel.Activated:Connect(closeConfirmation)
    confirm.Activated:Connect(function()
        closeConfirmation()
        task.spawn(function()local ok,err=pcall(callback);if not ok then warn(err);notify("Action failed. Check the console.")end end)
    end)
end
local function openDropdown(anchor, options, isSelected, onPick, multi)
    closeMenu(); hideTip()
    local p, sz = localPos(anchor)
    local rowH, n = UIS.TouchEnabled and 36 or 28, #options
    local shown = math.min(n, 7)
    local h = shown * rowH + math.max(0, shown - 1) * 2 + 8
    local width=math.min(math.max(sz.X,150),root.Size.X.Offset-16)
    local x=math.clamp(p.X,8,math.max(8,root.Size.X.Offset-width-8))
    h=math.min(h,math.max(36,root.Size.Y.Offset-80))
    local y = p.Y + sz.Y + 4
    if y + h > root.AbsoluteSize.Y / scale.Scale - 26 and p.Y - h - 4 > 60 then y = p.Y - h - 4 end
    y=math.clamp(y,8,math.max(8,root.Size.Y.Offset-h-8))
    local shield = make("TextButton", {Name = "MenuShield", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), ZIndex = 10}, overlay)
    local menu = make("ScrollingFrame", {Name = "Menu", Position = UDim2.fromOffset(x, y - 4), Size = UDim2.fromOffset(width, h),
        BorderSizePixel = 0, ScrollBarThickness = n*rowH > h-8 and 3 or 0, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 11}, overlay)
    bind(menu, "BackgroundColor3", "panelHi"); bind(menu, "ScrollBarImageColor3", "accentLine")
    corner(menu, 6); stroke(menu, "line"); padding(menu, 4, 4, 4, 4); vlist(menu, 2)
    tween(menu, .12, {Position = UDim2.fromOffset(x, y)})
    for i, opt in ipairs(options) do
        local b = make("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rowH),
            BorderSizePixel = 0, LayoutOrder = i}, menu)
        bind(b, "BackgroundColor3", "fieldHi"); corner(b, 4)
        local t = label(b, tostring(opt), 11, "text", F.regular, {Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -34, 1, 0),
            TextTruncate = Enum.TextTruncate.AtEnd})
        local mark = label(b, "✓", 11, "accentHi", F.bold, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0),
            Size = UDim2.fromOffset(14, rowH), TextXAlignment = Enum.TextXAlignment.Center})
        local function paint()
            local on = isSelected(opt)
            mark.Visible = on
            t.TextColor3 = on and C.accentHi or C.text
        end
        paint()
        b.MouseEnter:Connect(function() b.BackgroundTransparency = .35 end)
        b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
        polish(b,nil,function()return isSelected(opt) end)
        b.Activated:Connect(function()
            onPick(opt)
            if multi then paint() else closeMenu() end
        end)
    end
    shield.Activated:Connect(closeMenu)
    openMenu = {frame = menu, shield = shield}
    return openMenu
end

------------------------------------------------------------------------
-- Team editor (reads the unit bar from the game HUD)
------------------------------------------------------------------------
local savedTeam=Bridge.Initial().ui_state.team or {}
local teamNames, teamSelection, unitConfig = {}, {savedTeam[1] or "Empty",savedTeam[2] or "Empty"}, {}
local function refreshTeam()
    AP.RefreshTeam()
    local names, seen = {}, {}
    local hud = parent:FindFirstChild("HUD")
    local bottom = hud and hud:FindFirstChild("BottomFrame")
    local units = bottom and bottom:FindFirstChild("Unit")
    if units then
        local slots = units:GetChildren()
        table.sort(slots, function(a, b) return a.Name < b.Name end)
        for _, slot in ipairs(slots) do
            local unit = slot:FindFirstChild("Unit")
            if slot:IsA("Frame") and unit and unit:IsA("ValueBase") and type(unit.Value) == "string" and unit.Value ~= "" and not seen[unit.Value] then
                seen[unit.Value] = true
                table.insert(names, unit.Value)
            end
        end
    end
    local changed = table.concat(names, "|") ~= table.concat(teamNames, "|")
    teamNames = names
    for i = 1, 2 do
        if teamSelection[i] ~= "Empty" and not seen[teamSelection[i]] then teamSelection[i] = "Empty" end
        if teamSelection[i] == "Empty" and (changed or #names>=2) then
            for _, name in ipairs(names) do if name ~= teamSelection[3 - i] then teamSelection[i] = name; break end end
        end
    end
    return changed
end
local function teamCard(index)
    local name = teamSelection[index]
    local options = {}
    for _, candidate in ipairs(teamNames) do if candidate ~= teamSelection[3 - index] then table.insert(options, candidate) end end
    if #teamNames < 2 then table.insert(options, "Empty") end
    local items = {{type = "select", label = "Unit", options = options, value = name, teamPanel = index}}
    if name ~= "Empty" then
        if not unitConfig[name] then
            unitConfig[name] = {
                {type = "toggle", label = "Place Unit", value = true},
                {type = "multi", label = "Placement Zones", options = {"1", "2", "3", "4"}, value = {"1"}},
                {type = "slider", label = "Unit Priority", value = 50, min = 0, max = 100, step = 1},
                {type = "slider", label = "Max Units", value = 1, min = 1, max = 8, step = 1},
                {type = "slider", label = "Upgrade Cap", value = 20, min = 0, max = 20, step = 1},
            }
        end
        for _, item in ipairs(unitConfig[name]) do item.unitName=name;Bridge.Read(item);table.insert(items, item) end
    end
    return {title = name == "Empty" and "Pick A Unit" or name, icon = "◇", items = items}
end

------------------------------------------------------------------------
-- Controls
------------------------------------------------------------------------
local function infoIcon(at, str)
    local b = make("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(12, 12), LayoutOrder = 2}, at)
    corner(b, 99); stroke(b, "dim")
    label(b, "i", 8, "dim", F.bold, {Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center})
    b.MouseEnter:Connect(function() showTip(b, str) end)
    b.MouseLeave:Connect(hideTip)
    return b
end

-- Row with the hover accent bar on the card's inner edge.
local function row(body, h, order)
    local r = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h), LayoutOrder = order}, body)
    local bar = make("Frame", {BorderSizePixel = 0, AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, -9, .5, 0),
        Size = UDim2.new(0, 2, 1, -12), BackgroundTransparency = 1}, r)
    bind(bar, "BackgroundColor3", "accent"); corner(bar, 2)
    r.MouseEnter:Connect(function() tween(bar, .12, {BackgroundTransparency = 0}) end)
    r.MouseLeave:Connect(function() tween(bar, .2, {BackgroundTransparency = 1}) end)
    return r
end
local function caption(r, item, size)
    local box = make("Frame", {BackgroundTransparency = 1, Size = size}, r)
    local desc = describe(item)
    label(box, item.label, 11, "text", F.regular, {Size=UDim2.new(1,desc and -20 or 0,1,0), TextTruncate=Enum.TextTruncate.AtEnd})
    if desc then
        local help=make("Frame",{BackgroundTransparency=1,Position=UDim2.new(1,-18,0,0),Size=UDim2.new(0,18,1,0)},box)
        local title=box:FindFirstChildOfClass("TextLabel")
        local function positionHelp()
            local width=title.TextBounds and title.TextBounds.X or 0
            help.Position=UDim2.fromOffset(math.min(width+4,math.max(0,box.AbsoluteSize.X-18)),0)
        end
        title:GetPropertyChangedSignal("TextBounds"):Connect(positionHelp);box:GetPropertyChangedSignal("AbsoluteSize"):Connect(positionHelp)
        positionHelp();infoIcon(help,desc)
    end
    return box
end

local function toggleControl(r, item)
    caption(r, item, UDim2.new(1, -56, 1, 0))
    local sw = make("TextButton", {Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, 0, .5, 0),
        Size = UDim2.fromOffset(40, 22), BorderSizePixel = 0, BackgroundColor3 = C.white}, r)
    corner(sw, 7)
    local st = make("UIStroke", {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1}, sw)
    local grad = make("UIGradient", {}, sw)
    local knob = make("Frame", {AnchorPoint = Vector2.new(0, .5), Size = UDim2.fromOffset(14, 14), BorderSizePixel = 0}, sw)
    corner(knob, 5)
    local check = make("TextLabel", {BackgroundTransparency = 1, Text = "✓", Font = F.bold, TextSize = 11, Size = UDim2.fromScale(1, 1)}, knob)
    local shine=polish(sw,st,function()return item.value==true end)
    local function paint(animate)
        shine()
        local on = item.value == true
        grad.Color = on and ColorSequence.new(C.accentDeep, C.accent) or ColorSequence.new(C.field, C.field)
        st.Color = on and C.accentHi or C.line
        st.Transparency = on and .45 or 0
        check.TextColor3 = C.accent
        check.Visible = on
        local goal = {Position = UDim2.new(0, on and 22 or 4, .5, 0), BackgroundColor3 = on and C.white or C.knob}
        if animate then tween(knob, .16, goal) else knob.Position = goal.Position; knob.BackgroundColor3 = goal.BackgroundColor3 end
    end
    paint(false)
    sw.Activated:Connect(function() update(item, not item.value); paint(true) end)
end

local function sliderControl(r, item)
    caption(r, item, UDim2.new(1, -90, 0, 22))
    local pill = make("Frame", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0}, r)
    bind(pill, "BackgroundColor3", "field"); corner(pill, 4); padding(pill, 6, 6, 0, 0)
    local valueText = label(pill, "", 10, "sub", F.mono, {AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0)})
    local hit = make("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 20),
        Size = UDim2.new(1, 0, 0, 20)}, r)
    local track = make("Frame", {AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.new(1, 0, 0, 3), BorderSizePixel = 0}, hit)
    bind(track, "BackgroundColor3", "line"); corner(track, 2)
    local fill = make("Frame", {Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, BackgroundColor3 = C.white}, track)
    corner(fill, 2); bindSeq(make("UIGradient", {}, fill), "accentDeep", "accent")
    local thumb = make("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(10, 10),
        BorderSizePixel = 0, BackgroundColor3 = C.white}, track)
    corner(thumb,99);local thumbEdge=stroke(thumb,"accentLine")
    hit.MouseEnter:Connect(function()tween(thumbEdge,.12,{Color=C.accentHi})end)
    hit.MouseLeave:Connect(function()tween(thumbEdge,.16,{Color=C.accentLine})end)
    local function paint()
        local pct = (item.value - item.min) / math.max(1e-9, item.max - item.min)
        fill.Size = UDim2.fromScale(pct, 1)
        thumb.Position = UDim2.fromScale(pct, .5)
        valueText.Text = sliderText(item)
    end
    local dragLeft,dragWidth
    local function set(x)
        if not hit.Parent then return end
        local pct = math.clamp((x - (dragLeft or hit.AbsolutePosition.X)) / math.max(1, dragWidth or hit.AbsoluteSize.X), 0, 1)
        local v = math.floor((item.min + pct * (item.max - item.min)) / item.step + .5) * item.step
        v = math.clamp(v, item.min, item.max)
        local d = decimals(item.step)
        if d > 0 then v = tonumber(string.format("%." .. d .. "f", v)) end
        if v ~= item.value then update(item, v) end
        paint()
    end
    local function release()
        scroll.ScrollingEnabled=true
        if thumb.Parent then tween(thumb, .12, {Size = UDim2.fromOffset(12, 12)}) end
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if activeSlider then return end
            scroll.ScrollingEnabled=false
            dragLeft,dragWidth=hit.AbsolutePosition.X,hit.AbsoluteSize.X
            activeSlider = {set = set, input = i, release = release}
            tween(thumb, .1, {Size = UDim2.fromOffset(15, 15)})
            set(i.Position.X)
        end
    end)
    paint()
end

local function selectControl(r, item, multi)
    if item.teamOptions then
        item.options=table.clone(teamNames)
        if not multi then
            if #item.options==0 then item.options={"None"} end
            if not table.find(item.options,item.value) then item.value=item.options[1] end
        else
            local kept={};for _,name in ipairs(item.value) do if table.find(item.options,name) then kept[#kept+1]=name end end
            item.value=kept
        end
    end
    caption(r, item, UDim2.new(.5, -8, 1, 0))
    local dd = make("TextButton", {Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, 0, .5, 0),
        Size = UDim2.new(.5, 0, 0, 24), BorderSizePixel = 0}, r)
    bind(dd, "BackgroundColor3", "field"); corner(dd, 5)
    local st = stroke(dd, "line")
    local valueText = label(dd, "", 11, "text", F.regular, {Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -32, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd})
    local chev = chevron(dd, "sub")
    chev.Position = UDim2.new(1, -13, .5, 0)
    local function show()
        if multi then
            valueText.Text = #item.value > 0 and table.concat(item.value, ", ") or item.emptyLabel or "None"
        else
            valueText.Text = tostring(item.value)
        end
    end
    show()
    local isOpen = false
    local shine=polish(dd,st,function()return isOpen end,"field",true)
    dd.MouseEnter:Connect(function() tween(st, .12, {Color = C.accentLine}) end)
    dd.MouseLeave:Connect(function() if not isOpen then tween(st, .15, {Color = C.line}) end end)
    dd.Activated:Connect(function()
        Bridge.Open(item)
        local menu = openDropdown(dd, item.options,
            function(opt)
                if multi then return table.find(item.value, opt) ~= nil end
                return opt == item.value
            end,
            function(opt)
                if multi then
                    local at = table.find(item.value, opt)
                    if at then table.remove(item.value, at) else table.insert(item.value, opt) end
                    local ordered = {}
                    for _, o in ipairs(item.options) do if table.find(item.value, o) then ordered[#ordered + 1] = o end end
                    for k = #item.value, 1, -1 do item.value[k] = nil end
                    for k, o in ipairs(ordered) do item.value[k] = o end
                    update(item, item.value)
                else
                    update(item, opt)
                end
                if dd.Parent then show() end
            end, multi)
        isOpen = true;shine()
        chev.Rotation = -90
        st.Color = C.accentLine
        menu.onClose = function()
            isOpen = false;shine()
            if chev.Parent then chev.Rotation = 90; st.Color = C.line end
        end
    end)
end

local function normalizeHex(value)
    local hex=tostring(value):gsub("^%s*#?",""):gsub("%s*$","")
    if #hex==3 and hex:match("^%x+$") then hex=hex:gsub(".",function(c)return c..c end) end
    if #hex==6 and hex:match("^%x+$") then return hex:upper() end
end
local function colorControl(r,item)
    caption(r,item,UDim2.new(.5,-8,1,0))
    local swatch=make("TextButton",{Name="AccentPicker",Text="",AutoButtonColor=false,Size=UDim2.new(.5,0,0,24),
        Position=UDim2.new(1,0,.5,0),AnchorPoint=Vector2.new(1,.5),BorderSizePixel=0},r)
    bind(swatch,"BackgroundColor3","field");corner(swatch,4)
    polish(swatch,stroke(swatch,"lineSoft"),nil,"field",true)
    local chip=make("Frame",{Name="ColorPreview",Position=UDim2.fromOffset(7,5),Size=UDim2.fromOffset(14,14),BackgroundColor3=C.accent,BorderSizePixel=0},swatch)
    corner(chip,3)
    label(swatch,item.value,10,"text",F.mono,{Position=UDim2.fromOffset(29,0),Size=UDim2.new(1,-33,1,0)})
    swatch.Activated:Connect(function()
        closeMenu();hideTip()
        local hue,saturation,value=C.accent:ToHSV()
        local shield=make("TextButton",{Name="PickerShield",Text="",BackgroundTransparency=.55,BackgroundColor3=C.bg,Size=UDim2.fromScale(1,1),ZIndex=10},overlay)
        local panel=make("Frame",{Name="ColorPicker",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),
            Size=UDim2.fromOffset(math.min(280,root.Size.X.Offset-20),258),BorderSizePixel=0,ZIndex=11},overlay)
        bind(panel,"BackgroundColor3","panelHi");corner(panel,6);stroke(panel,"accentLine")
        label(panel,"Accent Color",12,"text",F.bold,{Position=UDim2.fromOffset(10,5),Size=UDim2.new(1,-20,0,24)})
        local sv=make("TextButton",{Name="SaturationValue",Text="",AutoButtonColor=false,Position=UDim2.fromOffset(10,34),Size=UDim2.new(1,-20,0,133),BorderSizePixel=0},panel)
        corner(sv,3)
        local white=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=C.white,BorderSizePixel=0},sv)
        make("UIGradient",{Transparency=NumberSequence.new(0,1)},white)
        local black=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0},sv)
        make("UIGradient",{Rotation=90,Transparency=NumberSequence.new(1,0)},black)
        local cursor=make("Frame",{Name="SVCursor",Size=UDim2.fromOffset(8,8),AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1},sv)
        corner(cursor,99);stroke(cursor,"white").Thickness=2
        local hueBar=make("TextButton",{Name="Hue",Text="",AutoButtonColor=false,Position=UDim2.fromOffset(10,178),Size=UDim2.new(1,-20,0,14),BackgroundColor3=C.white,BorderSizePixel=0},panel)
        local stops={};for i=0,6 do stops[#stops+1]=ColorSequenceKeypoint.new(i/6,Color3.fromHSV(i/6,1,1)) end
        make("UIGradient",{Color=ColorSequence.new(stops)},hueBar);corner(hueBar,3)
        local hueCursor=make("Frame",{Name="HueCursor",AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(3,18),Position=UDim2.fromScale(hue,.5),BackgroundColor3=C.white,BorderSizePixel=0},hueBar)
        local preview=make("Frame",{Name="CurrentColor",Position=UDim2.fromOffset(10,208),Size=UDim2.fromOffset(30,30),BorderSizePixel=0},panel);corner(preview,4)
        local hex=make("TextBox",{Name="Hex",Position=UDim2.fromOffset(47,208),Size=UDim2.new(1,-130,0,30),Text="",ClearTextOnFocus=false,Font=F.mono,TextSize=11,BorderSizePixel=0},panel)
        bind(hex,"BackgroundColor3","field");bind(hex,"TextColor3","text");corner(hex,4);local edge=stroke(hex,"lineSoft")
        local apply=make("TextButton",{Name="ApplyColor",Text="Apply",AutoButtonColor=false,Position=UDim2.new(1,-73,0,208),Size=UDim2.fromOffset(63,30),Font=F.medium,TextSize=11,BorderSizePixel=0},panel)
        bind(apply,"BackgroundColor3","accentDeep");bind(apply,"TextColor3","onAccent");corner(apply,4);polish(apply,stroke(apply,"accentLine"),function()return true end)
        local chosen
        local function paint()
            chosen=Color3.fromHSV(hue,saturation,value)
            sv.BackgroundColor3=Color3.fromHSV(hue,1,1)
            cursor.Position=UDim2.fromScale(saturation,1-value);hueCursor.Position=UDim2.fromScale(hue,.5)
            preview.BackgroundColor3=chosen
            hex.Text=string.format("#%02X%02X%02X",math.floor(chosen.R*255+.5),math.floor(chosen.G*255+.5),math.floor(chosen.B*255+.5))
        end
        local function acceptHex()
            local valid=normalizeHex(hex.Text)
            if valid then hue,saturation,value=Color3.fromRGB(tonumber(valid:sub(1,2),16),tonumber(valid:sub(3,4),16),tonumber(valid:sub(5,6),16)):ToHSV() end
            paint()
        end
        hex.Focused:Connect(function()tween(edge,.12,{Color=C.accent})end)
        hex.FocusLost:Connect(function()acceptHex();tween(edge,.12,{Color=C.lineSoft})end)
        local function drag(target,set)
            target.InputBegan:Connect(function(input)
                if activeSlider or not (input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch) then return end
                scroll.ScrollingEnabled=false
                activeSlider={input=input,owner=panel,set=set,release=function()scroll.ScrollingEnabled=true end}
                set(input.Position.X,input.Position.Y)
            end)
        end
        drag(sv,function(x,y)
            if not sv.Parent then return end
            saturation=math.clamp((x-sv.AbsolutePosition.X)/math.max(1,sv.AbsoluteSize.X),0,1)
            value=1-math.clamp((y-sv.AbsolutePosition.Y)/math.max(1,sv.AbsoluteSize.Y),0,1);paint()
        end)
        drag(hueBar,function(x)
            if not hueBar.Parent then return end
            hue=math.clamp((x-hueBar.AbsolutePosition.X)/math.max(1,hueBar.AbsoluteSize.X),0,1);paint()
        end)
        openMenu={frame=panel,shield=shield,onClose=function()
            if activeSlider and activeSlider.owner==panel then activeSlider.release();activeSlider=nil end
        end}
        shield.Activated:Connect(closeMenu)
        apply.Activated:Connect(function()acceptHex();local selected=hex.Text;closeMenu();update(item,selected)end)
        paint()
    end)
end


local function inputControl(r, item)
    caption(r, item, UDim2.new(.5, -8, 1, 0))
    local box = make("Frame", {AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, 0, .5, 0), Size = UDim2.new(.5, 0, 0, 24), BorderSizePixel = 0}, r)
    bind(box, "BackgroundColor3", "field"); corner(box, 5)
    local st = stroke(box, "line")
    local left, swatch = 9, nil
    if item.type == "color" then
        swatch = make("Frame", {AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 8, .5, 0), Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0}, box)
        corner(swatch, 3); stroke(swatch, "line")
        left = 28
    end
    local initial = item.value or (item.label == "Invite" and CONFIG.Invite or "")
    local tb = make("TextBox", {Text = tostring(initial), PlaceholderText = item.placeholder or ("#" .. CONFIG.Accent), ClearTextOnFocus = false,
        Font = F.regular, TextSize = 11, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true,
        Position = UDim2.fromOffset(left, 0), Size = UDim2.new(1, -left - 8, 1, 0)}, box)
    bind(tb, "TextColor3", "text"); bind(tb, "PlaceholderColor3", "dim")
    local function paintSwatch()
        if not swatch then return end
        local hex = tb.Text:gsub("#", "")
        if #hex == 6 and hex:match("^%x+$") then
            swatch.BackgroundColor3 = Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
        end
    end
    paintSwatch()
    local focused=false
    local shine=polish(box,st,function()return focused end,"field",false)
    tb.Focused:Connect(function() focused=true;shine();tween(st,.12,{Color=C.accent}) end)
    tb.FocusLost:Connect(function()
        focused=false;shine()
        tween(st, .15, {Color = C.line})
        paintSwatch()
        update(item, tb.Text)
    end)
end

local function buttonFlow(body, order)
    local flow = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order}, body)
    vlist(flow,4)
    padding(flow,0,0,3,3)
    return flow
end
local function buttonControl(flow, item, order)
    local b = make("TextButton", {Text = item.label, AutoButtonColor = false, Font = F.bold, TextSize = 11, AutomaticSize = Enum.AutomaticSize.None,
        Size = UDim2.new(1,0,0,27), BorderSizePixel = 0, LayoutOrder = order}, flow)
    padding(b, 14, 14, 0, 0); corner(b, 6)
    local st
    if item.accent then
        bind(b,"BackgroundColor3","accentDeep");bind(b,"TextColor3","onAccent");st=stroke(b,"accentLine")
    else
        bind(b, "BackgroundColor3", "field"); bind(b, "TextColor3", "text"); st = stroke(b, "line")
    end
    b.MouseEnter:Connect(function()
        tween(st, .12, {Color = item.accent and C.accent or C.accentLine})
        tween(b, .12, {BackgroundColor3 = item.accent and C.accentDeep:Lerp(C.accent, .2) or C.fieldHi})
    end)
    b.MouseLeave:Connect(function()
        tween(st, .15, {Color = item.accent and C.accentLine or C.line})
        tween(b, .15, {BackgroundColor3 = item.accent and C.accentDeep or C.field})
    end)
    polish(b,st,function()return item.accent==true end,item.accent and "accentDeep" or "field",true)
    b.Activated:Connect(function() onButton(item) end)
end

local function creditsControl(body,order)
    local holder=make("Frame",{Name="AboutCredits",BackgroundTransparency=1,Size=UDim2.new(1,0,0,48),LayoutOrder=order},body)
    label(holder,"script by blob",10,"text",F.medium,{Name="ScriptCredit",Size=UDim2.new(.5,-26,1,0),TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Right})
    local picture=make("ImageLabel",{Name="CreditImage",BackgroundTransparency=1,Image=ABOUT_ASSET,ScaleType=Enum.ScaleType.Fit,
        AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(40,40)},holder)
    corner(picture,4)
    label(holder,"base by KarmaPanda",10,"text",F.medium,{Name="BaseCredit",Position=UDim2.new(.5,26,0,0),Size=UDim2.new(.5,-26,1,0),TextWrapped=true})
end

local function noteControl(body, item, order)
    local holder = make("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order}, body)
    vlist(holder, 2); padding(holder, 0, 0, 3, 3)
    if false then
        label(holder, item.label, 12, "text", F.regular, {LayoutOrder = 1})
        label(holder, item.desc, 10, "dim", F.regular, {AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), TextWrapped = true, LayoutOrder = 2})
    else
        local text=label(holder, item.label, 11, "sub", F.regular, {AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), TextWrapped = true, LayoutOrder = 1})
        if item.macroStatus or item.placementStatus or item.profileInfo or item.buffInfo or item.editStatus then item.liveLabel=text end
    end
end

local function sessionClock()
    local total = math.floor(os.clock() - sessionStarted)
    return string.format("%02d:%02d:%02d", math.floor(total / 3600), math.floor(total / 60) % 60, total % 60), total
end
local function playerControl(body,order)
    local macro=findSetting("Profile")
    local enabled={}
    for _,zone in ipairs(Pages[2].tabs[2].cards) do
        for _,item in ipairs(zone.items) do if item.label=="Zone Enabled" and item.value then enabled[#enabled+1]=zone.title:match("%d+") end end
    end
    local entries={{"Username",player.Name},{"Display Name",player.DisplayName or player.Name},
        {"Equipped Units",tostring(#teamNames)},{"Macro Profile",macro and macro.value or "None"},
        {"Default Zones",Bridge.DefaultZones()}}
    local holder=make("Frame",{Name="PlayerDetails",Size=UDim2.new(1,0,0,#entries*25),BackgroundTransparency=1,LayoutOrder=order},body)
    for i,entry in ipairs(entries)do
        local r=make("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(0,(i-1)*25),Size=UDim2.new(1,0,0,25)},holder)
        label(r,entry[1],10,"sub",F.regular,{Size=UDim2.new(.4,0,1,0)})
        local valueLabel=label(r,tostring(entry[2]),11,i<=2 and "accent" or "text",F.medium,{Position=UDim2.fromScale(.4,0),Size=UDim2.new(.6,0,1,0),TextXAlignment=Enum.TextXAlignment.Right,TextTruncate=Enum.TextTruncate.AtEnd})
        if i<=2 then
            -- The main script's anonymous mode also recolors matching labels.
            -- Preserve its substituted text while keeping this UI's accent.
            valueLabel:GetPropertyChangedSignal("TextColor3"):Connect(function()
                if valueLabel.TextColor3~=C.accent then valueLabel.TextColor3=C.accent end
            end)
        end
    end
end
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
local function refreshMapInfo()
    local stats=Bridge.MapSnapshot()
    local seconds=math.floor(stats.seconds)
    local duration=string.format("%02d:%02d:%02d",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
    if homeLabels.map and homeLabels.map.Parent then homeLabels.map.Text=is_lobby() and "Lobby" or get_stage() end
    if homeLabels.mapTime and homeLabels.mapTime.Parent then homeLabels.mapTime.Text=duration end
    if homeLabels.retries and homeLabels.retries.Parent then homeLabels.retries.Text=tostring(stats.replays) end
end
local function sessionControl(body,order)
    local holder=make("Frame",{Name="MapMetrics",BackgroundTransparency=1,Size=UDim2.new(1,0,0,110),LayoutOrder=order},body)
    homeLabels.map=label(holder,"Waiting For Map",14,"text",F.bold,{Size=UDim2.new(1,-8,0,40),Position=UDim2.fromOffset(4,0),TextXAlignment=Enum.TextXAlignment.Center,TextWrapped=true})
    for i,entry in ipairs({{"REPLAYS","retries"},{"TIME ON MAP","mapTime"}}) do
        local tile=make("Frame",{Name="Metric_"..entry[2],Position=UDim2.new((i-1)*.5,(i-1)*3,0,45),Size=UDim2.new(.5,-3,0,59),BorderSizePixel=0,BackgroundTransparency=.15},holder)
        bind(tile,"BackgroundColor3","field");corner(tile,4);stroke(tile,"lineSoft",.2)
        label(tile,entry[1],9,"sub",F.medium,{Position=UDim2.fromOffset(9,5),Size=UDim2.new(1,-18,0,15)})
        homeLabels[entry[2]]=label(tile,"—",16,"text",F.bold,{Position=UDim2.fromOffset(9,25),Size=UDim2.new(1,-18,0,24)})
    end
    refreshMapInfo()
end
local function discordControl(body,order)
    local holder=make("Frame",{Name="DiscordUtility",Size=UDim2.new(1,0,0,30),BackgroundTransparency=1,LayoutOrder=order},body)
    local button=make("TextButton",{Name="Copy Discord Invite",Text="Copy Discord Invite",TextSize=11,Font=F.medium,AutoButtonColor=false,
        Size=UDim2.new(0,155,0,27),BorderSizePixel=0},holder)
    bind(button,"BackgroundColor3","field");bind(button,"TextColor3","text");corner(button,4)
    polish(button,stroke(button,"lineSoft"),nil,"field",true)
    button.Activated:Connect(function()onButton({label="Copy Discord Invite"})end)
end

local function buildItems(body, items)
    local flow
    for order, item in ipairs(items) do
        Bridge.Read(item)
        if item.visibleWhenId and not conditionSettings[item.visibleWhenId].value then continue end
        if item.visibleWhen then
            local setting=findSetting(item.visibleWhen)
            if not setting or not setting.value then continue end
        end
        if item.type == "button" then
            if not flow then flow = buttonFlow(body, order) end
            buttonControl(flow, item, order)
        else
            flow = nil
            if item.type=="player" then playerControl(body,order)
            elseif item.type=="discord" then discordControl(body,order)
            elseif item.type == "session" then sessionControl(body, order)
            elseif item.type == "credits" then creditsControl(body,order)
            elseif item.type == "note" then noteControl(body, item, order)
            elseif item.type == "toggle" then toggleControl(row(body, 28, order), item)
            elseif item.type == "slider" then sliderControl(row(body, 42, order), item)
            elseif item.type == "select" then selectControl(row(body, 28, order), item, false)
            elseif item.type == "multi" then selectControl(row(body, 28, order), item, true)
            elseif item.type == "color" then colorControl(row(body,32,order),item)
            elseif item.type == "input" then inputControl(row(body,28,order),item)
            end
        end
    end
end

------------------------------------------------------------------------
-- Cards and page layout
------------------------------------------------------------------------
local collapsed = DeepCopy(Bridge.Initial().ui_state.collapsed or {})
local function card(at, data, key, order)
    local isAccount = data.items[1] ~= nil and data.items[1].type == "account"
    local frame = make("Frame", {Name = data.title, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0}, at)
    bind(frame,"BackgroundColor3","panel");frame.BackgroundTransparency=.12;corner(frame,5)
    make("UIGradient",{Rotation=105,Color=ColorSequence.new(C.white,Color3.fromRGB(228,225,231))},frame)
    local st = stroke(frame, "lineSoft")
    vlist(frame, 0)
    local body = make("Frame", {Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 2}, frame)
    padding(body,8,8,isAccount and 5 or 1,4);vlist(body,1)
    if not isAccount then
        local header = make("TextButton", {Name = "Header", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1}, frame)
        local tintBand=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundTransparency=.93,BorderSizePixel=0},header)
        bind(tintBand,"BackgroundColor3","accent")
        make("UIGradient",{Rotation=25,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)})},tintBand)
        polish(header,nil,nil)
        data.noIcon=true
        label(header, data.title, 12, "text", F.bold, {Position = UDim2.fromOffset(data.noIcon and 11 or 32, 0), Size = UDim2.new(1, data.noIcon and -40 or -62, 1, 0),
            TextTruncate = Enum.TextTruncate.AtEnd})
        if data.badge then
            local tag=label(header,data.badge,8,"sub",F.mono,{Position=UDim2.new(1,-85,0,8),Size=UDim2.fromOffset(52,15),TextXAlignment=Enum.TextXAlignment.Center,BackgroundTransparency=.1})
            bind(tag,"BackgroundColor3","field");corner(tag,3)
        end
        local chev = chevron(header, "sub")
        chev.Position = UDim2.new(1, -18, .5, 0)
        local divider = make("Frame", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, 0), Size = UDim2.new(1, -24, 0, 1), BorderSizePixel = 0}, header)
        bind(divider, "BackgroundColor3", "lineSoft")
        local function apply(animate)
            local closed = collapsed[key] == true
            body.Visible = not closed
            divider.Visible = not closed
            if animate then tween(chev, .15, {Rotation = closed and 0 or 90}) else chev.Rotation = closed and 0 or 90 end
        end
        apply(false)
        header.Activated:Connect(function()
            collapsed[key] = not collapsed[key]
            Bridge.SaveUI("collapsed",collapsed)
            closeMenu()
            apply(true)
            requestRender()
        end)
        header.MouseEnter:Connect(function() tween(chev, .12, {TextColor3 = C.text}) end)
        header.MouseLeave:Connect(function() tween(chev, .12, {TextColor3 = C.sub}) end)
    end
    frame.MouseEnter:Connect(function() tween(st, .15, {Color = C.accentLine}) end)
    frame.MouseLeave:Connect(function() tween(st, .2, {Color = C.lineSoft}) end)
    buildItems(body, data.items)
    return frame
end

local ROW_HEIGHT = {credits=48,welcome=82,player=125,discord=30,toggle=29,select=29,multi=29,input=29,color=29,slider=43,note=22,account=66,session=110}
local function estimate(data, key)
    if collapsed[key] then return 30 end
    local isAccount = data.items[1] ~= nil and data.items[1].type == "account"
    local h, buttons = isAccount and 11 or 36, 0
    for _, item in ipairs(data.items) do
        if item.type == "button" then
            buttons = buttons + 1
        else
            if buttons > 0 then h = h + buttons * 31; buttons = 0 end
            h = h + (ROW_HEIGHT[item.type] or 34)
        end
    end
    if buttons > 0 then h = h + buttons * 31 end
    return h
end

-- A block is a set of independent columns (masonry); full-width items start a new block.
local function newBlock(order)
    local frame = make("Frame", {Name = "Columns", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order}, stack)
    local block = {cols = {}, h = {}, n = 0}
    for i = 1, columnCount do
        local props = {BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0)}
        if columnCount > 1 then
            props.Position = UDim2.new((i - 1) / columnCount, i > 1 and 5 or 0, 0, 0)
            props.Size = UDim2.new(1 / columnCount, -5, 0, 0)
        end
        local col = make("Frame", props, frame)
        vlist(col, 6)
        block.cols[i], block.h[i] = col, 0
    end
    return block
end
local function place(block, data, key, column)
    local best = column
    if not best then
        best = 1
        for i = 2, #block.cols do if block.h[i] < block.h[best] - 4 then best = i end end
    end
    best = math.min(best, #block.cols)
    block.n = block.n + 1
    card(block.cols[best], data, key, block.n)
    block.h[best] = block.h[best] + estimate(data, key) + 6
end

local function tabCards(tab)
    if not tab.subtabs then return tab.cards end
    local merged = {}
    for _, section in ipairs(tab.subtabs) do
        for _, data in ipairs(section.cards) do merged[#merged + 1] = data end
    end
    return merged
end
local function haystack(data)
    local parts = {data.title}
    for _, item in ipairs(data.items) do
        parts[#parts + 1] = item.label
        if type(item.options) == "table" then for _, o in ipairs(item.options) do parts[#parts + 1] = tostring(o) end end
    end
    if data.type == "team" then
        parts[#parts + 1] = table.concat(teamNames, " ")
        parts[#parts + 1] = "place unit placement zones unit priority max units upgrade cap"
    end
    return table.concat(parts, " "):lower()
end
local function normalizedQuery()
    return (search.Text:gsub("^%s+", ""):gsub("%s+$", "")):lower()
end

local function applyLayoutOffsets()
    tabsBar.AnchorPoint=Vector2.new(0,0)
    tabsBar.Position=UDim2.fromOffset(6,40)
    tabsBar.Size=UDim2.new(1,-14,0,27)
    local topY=tabsBar.Visible and 73 or 43
    scroll.Position=UDim2.fromOffset(0,topY)
    scroll.Size=UDim2.new(1,0,1,-topY)
    empty.Position=UDim2.fromOffset(2,topY+6)
end

local function buildTabs(page, selected)
    tabsBar.Visible = #page.tabs > 1
    if not tabsBar.Visible then return end
    for i, t in ipairs(page.tabs) do
        local on = i == selected
        local b = make("TextButton", {Text = "", AutoButtonColor = false, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
            BorderSizePixel = 0, BackgroundColor3 = C.white, BackgroundTransparency = on and 0 or 1, LayoutOrder = i}, tabsBar)
        corner(b, 5); padding(b, 9, 9, 0, 0)
        if on then bindSeq(make("UIGradient", {}, b), "accent", "accentDeep") end
        local l = label(b, t.name, 11, on and "onAccent" or "sub", on and F.bold or F.medium, {AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0)})
        if not on then
            b.MouseEnter:Connect(function() tween(l, .12, {TextColor3 = C.text}) end)
            b.MouseLeave:Connect(function() tween(l, .15, {TextColor3 = C.sub}) end)
        end
        polish(b,nil,function()return on end)
        b.Activated:Connect(function()
            if activeTabs[activePage] ~= i then
                activeTabs[activePage] = i
                saveNavigation()
                scroll.CanvasPosition = Vector2.new(0, 0)
                render()
            end
        end)
    end
end

render = function()
    pendingRender = false
    if activeSlider then activeSlider.release();activeSlider=nil end
    closeMenu(); hideTip()
    refreshTeam()
    local previous = scroll.CanvasPosition
    sessionLabels = {};homeLabels={}
    for _, child in ipairs(stack:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
    for _, child in ipairs(tabsBar:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
    pruneThemed()

    local query = normalizedQuery()
    lastQuery = query
    local order, found, block = 0, 0, nil
    local function nextOrder() order = order + 1; return order end
    local function emit(data, key, zonesPage)
        if data.type == "team" then
            local pair=newBlock(nextOrder())
            place(pair,teamCard(1),"team:1",1);place(pair,teamCard(2),"team:2",2)
            block=nil
        elseif zonesPage and data.title == "Placement Zones" then
            block = nil
            card(stack, data, key, nextOrder())
        elseif data.title=="Other Automation" or data.title=="Placement Offsets" then
            block=nil;card(stack,data,key,nextOrder())
        elseif zonesPage and data.title:match("^Zone %d$") then
            local index=tonumber(data.title:match("%d"))
            if index%2==1 or not block then block=newBlock(nextOrder()) end
            place(block,data,key,(index-1)%2+1)
        else
            if not block then block=newBlock(nextOrder()) end
            place(block,data,key,data.homeColumn)
        end
    end

    if query == "" then
        local page = Pages[activePage]
        local ti = activeTabs[activePage] or 1
        local tab = page.tabs[ti]
        heading.Text = tab.name ~= "" and (page.name .. " / " .. tab.name) or page.name
        buildTabs(page, ti)
        local zonesPage = page.name == "Automation" and tab.name == "Zones"
        for _, data in ipairs(tabCards(tab)) do
            found = found + 1
            emit(data, page.name .. "/" .. tab.name .. "/" .. data.title, zonesPage)
        end
        empty.Text = "Nothing on this page yet."
    else
        heading.Text = "Results"
        tabsBar.Visible = false
        for pi, p in ipairs(Pages) do
            for ti, tab in ipairs(p.tabs) do
                local started = false
                local zonesPage = p.name == "Automation" and tab.name == "Zones"
                for _, data in ipairs(tabCards(tab)) do
                    if haystack(data):find(query, 1, true) then
                        if not started then
                            started = true
                            block = nil
                            local jump = make("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
                                Size = UDim2.new(1, 0, 0, 18), LayoutOrder = nextOrder()}, stack)
                            local l = label(jump, tab.name ~= "" and (p.name .. "  /  " .. tab.name .. "   ›") or (p.name .. "   ›"), 11, "sub", F.medium,
                                {Size = UDim2.fromScale(1, 1)})
                            jump.MouseEnter:Connect(function() l.TextColor3 = C.accentHi end)
                            jump.MouseLeave:Connect(function() l.TextColor3 = C.sub end)
                            jump.Activated:Connect(function() activeTabs[pi] = ti; selectPage(pi) end)
                        end
                        found = found + 1
                        emit(data, p.name .. "/" .. tab.name .. "/" .. data.title, zonesPage)
                    end
                end
            end
        end
        empty.Text = "No controls match \"" .. query .. "\"."
    end
    empty.Visible = found == 0
    applyLayoutOffsets()
    scroll.CanvasPosition = previous
    setStatus()
end

requestRender = function()
    if not ready then return end
    if activeSlider then pendingRender = true else render() end
end

setStatus = function()
    statusText=Bridge.Status()
    local where = "SEARCH"
    if lastQuery == "" then
        local page = Pages[activePage]
        local tab = page.tabs[activeTabs[activePage] or 1]
        where = tab.name ~= "" and (page.name .. " / " .. tab.name) or page.name
    end
    dot.BackgroundColor3=statusText=="Recording" and Color3.fromRGB(230,65,65) or statusText=="Playback" and Color3.fromRGB(242,158,56) or Color3.fromRGB(74,222,128)
    statusLabel.Text = string.upper(statusText .. "  ·  " .. (compact and Pages[activePage].name or where))

end

------------------------------------------------------------------------
-- Behaviour
------------------------------------------------------------------------
update = function(item, value)
    if item.teamPanel then
        if value == "Empty" and #teamNames >= 2 then return end
        if value ~= "Empty" and (value == teamSelection[3 - item.teamPanel] or not table.find(teamNames, value)) then return end
        teamSelection[item.teamPanel] = value
        Bridge.SaveUI("team",teamSelection)
        render()
        return
    end
    local ok,err=pcall(Bridge.Write,item,value)
    if not ok then notify("Couldn't update "..item.label..". Check the console.");warn(err);return end
    item.value = value
    local name = item.label
    if value and (name=="Playback Macro" or name=="Record Macro") then
        local other=findSetting(name=="Playback Macro" and "Record Macro" or "Playback Macro")
        if other then other.value=false end
        requestRender()
    end
    if item.id then requestRender() end
    if value and (item.sharedId=="quick2" or item.sharedId=="quick3") then
        local other=findSetting(item.sharedId=="quick2" and "Auto 3x Speed" or "Auto 2x Speed")
        if other then other.value=false end
        requestRender()
    end
    if name=="Level Spoofer" or name=="Anonymous Mode" then requestRender() end
    if name == "UI Scale" then
        ui.scale = value / 100
        if fit then fit() end
    elseif name == "Window Opacity" then
        ui.opacity = value / 100
        root.BackgroundTransparency = 1 - ui.opacity
    elseif name == "Lock UI Position" then
        ui.locked = value
        dragging = false
    elseif name == "Mobile Toggle Button" then
        ui.mobile = value
        reopen.Visible = value or (not root.Visible)
    elseif name == "Toggle Key" then
        ui.key = value
    elseif name == "Close UI On Execution" then
        gui:SetAttribute("CloseOnExecution", value)
    elseif name == "Reduce Motion" then
        ui.reduceMotion = value
        if value then clearLeaves() end
    elseif name == "Animated Leaves" then
        leafEnabled = value
        if not value then clearLeaves() end
    elseif name == "Theme Preset" then
        if PRESETS[value] then applyTheme(PRESETS[value]) end
    elseif name == "Accent Color" then
        local hex=normalizeHex(value)
        if hex then applyTheme(hex) else item.value=string.format("#%02X%02X%02X",table.unpack(accentRGB));requestRender() end
    elseif name == "Red" or name == "Green" or name == "Blue" then
        accentRGB[({Red = 1, Green = 2, Blue = 3})[name]] = value
        applyTheme(string.format("%02X%02X%02X", accentRGB[1], accentRGB[2], accentRGB[3]))
    end
    local record=findSetting("Record Macro")
    local playback=findSetting("Playback Macro")
    statusText=record and record.value and "Recording" or playback and playback.value and "Playback" or "Idle"
    setStatus()
end

applyTheme = function(hex)
    hex = string.upper(hex)
    accentRGB = setAccent(hex)
    repaint()
    gui:SetAttribute("ZoneColor",C.accent)
    Bridge.Theme(C.accent,hex)
    setSetting("Accent Color", "#" .. hex)
    for index, channel in ipairs({"Red", "Green", "Blue"}) do setSetting(channel, accentRGB[index]) end
    paintNav()
    requestRender()
end

onButton = function(item)
    if Bridge.actions[item.label] or item.zone then
        task.spawn(function()local ok,err=pcall(Bridge.Action,item);if not ok then warn(err);notify("Action failed. Check the console.")end end)
        return
    end
    local name = item.label
    if name == "Copy Discord Invite" then
        local ok=type(setclipboard)=="function" and pcall(setclipboard,CONFIG.Invite)
        notify(ok and "Discord invite copied." or "Clipboard unavailable in this executor.")
    elseif name == "Refresh Current Team" then
        refreshTeam()
        render()
    elseif name == "Reset UI Position" then
        root.Position = UDim2.fromScale(.5, .5)
        saveWindowState()
    elseif name == "Reset Appearance" then
        ui.scale, ui.opacity, ui.reduceMotion, leafEnabled = 1, .96, false, true
        local defaults = {["UI Scale"] = 100, ["Window Opacity"] = 96, ["Theme Preset"] = "Crimson",
            ["Accent Color"] = "#" .. DefaultSettings.ui_accent, ["Animated Leaves"] = true, ["Reduce Motion"] = false}
        for key, value in pairs(defaults) do local item=findSetting(key);if item then Bridge.Write(item,value);setSetting(key,value)end end
        root.BackgroundTransparency = 1 - ui.opacity
        if fit then fit() end
        applyTheme(DefaultSettings.ui_accent)
    elseif name == "Explore Automation" then
        selectPage(pageIndex("Automation"))
    elseif name == "Open Macro Library" then
        selectPage(pageIndex("Macro"))
    elseif name == "Restore Preview Defaults" then
        notify("Re-run the script to restore its defaults.")
    else
        notify("Not connected yet")
    end
end

-- Navigation --------------------------------------------------------------
local navItems = {}
local selectionViewport=make("Frame",{Name="SelectionViewport",BackgroundTransparency=1,ClipsDescendants=true,Position=nav.Position,Size=nav.Size,ZIndex=0},sidebar)
local selection=make("Frame",{Name="Selection",BackgroundColor3=C.accentDeep,BackgroundTransparency=.12,BorderSizePixel=0,Position=UDim2.fromOffset(0,0),Size=UDim2.new(1,0,0,28)},selectionViewport)
corner(selection,6);local selectionEdge=stroke(selection,"accent",.35)
local selectionGradient=make("UIGradient",{},selection)
local selectionTween
local function moveSelection(animate)
    local height=compact and 42 or 28
    local position=UDim2.fromOffset(0,(activePage-1)*(height+4)-nav.CanvasPosition.Y)
    if selectionTween then selectionTween:Cancel();selectionTween=nil end
    selection.Size=UDim2.new(1,0,0,height)
    if animate and not ui.reduceMotion then
        selectionTween=TweenService:Create(selection,TweenInfo.new(.23,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=position})
        selectionTween:Play()
    else selection.Position=position end
end
nav:GetPropertyChangedSignal("CanvasPosition"):Connect(function()moveSelection(false)end)
paintNav = function()
    selection.BackgroundColor3=Color3.new(1,1,1)
    selectionGradient.Color=ColorSequence.new(C.accent,C.accentDeep)
    selectionEdge.Color=C.accent
    local selectedText=(C.accent.R*.299+C.accent.G*.587+C.accent.B*.114)>.7 and C.bg or C.white
    for i, n in ipairs(navItems) do
        local on = i == activePage
        n.button.BackgroundColor3 = on and C.white or C.field
        n.button.BackgroundTransparency = 1
        n.grad.Enabled = false
        n.grad.Color = ColorSequence.new(C.accent, C.accentDeep)
        n.stroke.Color = C.accentHi
        n.stroke.Transparency = 1

        n.label.TextColor3 = on and selectedText or C.sub
        n.label.Font = on and F.bold or F.medium
        if n.shine then n.shine() end
    end
end
for i, p in ipairs(Pages) do
    local b = make("TextButton", {Name = p.name, Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 32), BorderSizePixel = 0,
        BackgroundColor3 = C.white, BackgroundTransparency = 1, LayoutOrder = i}, nav)
    corner(b, 6)
    local grad = make("UIGradient", {Enabled = false}, b)
    local st = make("UIStroke", {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Transparency = 1}, b)

    local l = label(b, p.name, 12, "sub", F.medium, {Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -42, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd})
    navItems[i] = {button = b, grad = grad, stroke = st, label = l}
    b.MouseEnter:Connect(function()
        if i ~= activePage then
            b.BackgroundColor3 = C.field
            tween(b, .12, {BackgroundTransparency = .2})
            tint(ic, C.text); l.TextColor3 = C.text
        end
    end)
    b.MouseLeave:Connect(function()
        hideTip()
        if i ~= activePage then
            tween(b, .15, {BackgroundTransparency = 1})
            tint(ic, C.sub); l.TextColor3 = C.sub
        end
    end)
    b.ClipsDescendants=true
    b.Activated:Connect(function() selectPage(i) end)
end

selectPage = function(index)
    activePage = index
    saveNavigation()
    lastQuery = ""
    search.Text = ""
    scroll.CanvasPosition = Vector2.new(0, 0)
    paintNav()
    moveSelection(true)
    render()
end

search:GetPropertyChangedSignal("Text"):Connect(function()
    if normalizedQuery() ~= lastQuery then
        scroll.CanvasPosition = Vector2.new(0, 0)
        requestRender()
    end
end)

visible = function(show)
    if activeSlider then activeSlider.release() end
    root.Visible = show
    Bridge.SaveUI("hidden",not show)
    reopen.Visible = ui.mobile or not show
    activeSlider, dragging, resizing = nil, false, nil
    if pendingFit then fit();saveWindowState() end
    closeMenu(); hideTip()
end
minimize.Activated:Connect(function() visible(false) end)
local mobileDrag,mobileStart,mobileOrigin,mobileMoved
reopen.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        mobileDrag=input;mobileStart=input.Position;mobileOrigin=reopen.AbsolutePosition;mobileMoved=false
    end
end)
table.insert(connections,UIS.InputChanged:Connect(function(input)
    if not mobileDrag then return end
    if input~=mobileDrag and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local dx,dy=input.Position.X-mobileStart.X,input.Position.Y-mobileStart.Y
    if math.abs(dx)+math.abs(dy)>6 then mobileMoved=true end
    if mobileMoved and workspace.CurrentCamera then
        local vp=workspace.CurrentCamera.ViewportSize
        reopen.Position=UDim2.fromOffset(math.clamp(mobileOrigin.X+dx,0,math.max(0,vp.X-44)),math.clamp(mobileOrigin.Y+dy,0,math.max(0,vp.Y-44)))
    end
end))
table.insert(connections,UIS.InputEnded:Connect(function(input)
    if input==mobileDrag then
        if mobileMoved and workspace.CurrentCamera then
            local vp=workspace.CurrentCamera.ViewportSize
            Bridge.SaveUI({mobileX=reopen.Position.X.Offset/math.max(1,vp.X),mobileY=reopen.Position.Y.Offset/math.max(1,vp.Y)})
        end
        mobileDrag=nil
    end
end))
table.insert(connections,UIS.WindowFocusReleased:Connect(function()mobileDrag=nil end))
reopen.Activated:Connect(function()
    if mobileMoved then mobileMoved=false;return end
    visible(not root.Visible)
end)
scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function() closeMenu(); hideTip() end)

-- Window drag (top bar, left of the controls) and resize (footer grip) ----
local function isPress(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
top.InputBegan:Connect(function(i)
    if not isPress(i) or ui.locked then return end
    local limit = (badge.Visible and badge or searchBox).AbsolutePosition.X - 6
    if i.Position.X < limit then
        dragging, dragInput, dragStart, dragPosition = true, i, i.Position, root.Position
        closeMenu()
    end
end)
grip.InputBegan:Connect(function(i)
    if not isPress(i) or ui.locked then return end
    resizing = {input = i, start = i.Position, w = root.Size.X.Offset, h = root.Size.Y.Offset, s = scale.Scale,
        topLeft = root.AbsolutePosition, position = root.Position}
    closeMenu()
end)

table.insert(connections, UIS.InputChanged:Connect(function(i)
    local mouse = i.UserInputType == Enum.UserInputType.MouseMovement
    if activeSlider and (i == activeSlider.input or mouse and activeSlider.input.UserInputType == Enum.UserInputType.MouseButton1) then
        activeSlider.set(i.Position.X,i.Position.Y)
    end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local vp = camera.ViewportSize
    if dragging and (i == dragInput or mouse and dragInput.UserInputType == Enum.UserInputType.MouseButton1) then
        local delta = i.Position - dragStart
        local halfX, halfY = root.AbsoluteSize.X / 2, root.AbsoluteSize.Y / 2
        local x = math.clamp(vp.X * dragPosition.X.Scale + dragPosition.X.Offset + delta.X, halfX, math.max(halfX, vp.X - halfX))
        local y = math.clamp(vp.Y * dragPosition.Y.Scale + dragPosition.Y.Offset + delta.Y, halfY, math.max(halfY, vp.Y - halfY))
        root.Position = UDim2.fromOffset(x, y)
    end
    if resizing and (i == resizing.input or mouse and resizing.input.UserInputType == Enum.UserInputType.MouseButton1) then
        local s = resizing.s
        local delta = i.Position - resizing.start
        local w = math.clamp(resizing.w + delta.X / s, math.min(420,resizing.w), math.max(resizing.w, (vp.X - 8 - resizing.topLeft.X) / s))
        local h = math.clamp(resizing.h + delta.Y / s, math.min(380,resizing.h), math.max(resizing.h, (vp.Y - 8 - resizing.topLeft.Y) / s))
        ui.w, ui.h = w, h
        root.Size = UDim2.fromOffset(w, h)
        root.Position = UDim2.new(resizing.position.X.Scale,resizing.position.X.Offset+(w-resizing.w)*s*root.AnchorPoint.X,
            resizing.position.Y.Scale,resizing.position.Y.Offset+(h-resizing.h)*s*root.AnchorPoint.Y)
        layout()
    end
end))
table.insert(connections, UIS.InputEnded:Connect(function(i)
    if (dragging or resizing) and (i==dragInput or resizing and i==resizing.input or i.UserInputType==Enum.UserInputType.MouseButton1) then saveWindowState() end
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i == dragInput then dragging = false end
    if resizing and (i == resizing.input or i.UserInputType == Enum.UserInputType.MouseButton1) then resizing = nil end
    if activeSlider and (i == activeSlider.input or (i.UserInputType == Enum.UserInputType.MouseButton1 and activeSlider.input.UserInputType == Enum.UserInputType.MouseButton1)) then
        local released = activeSlider
        activeSlider = nil
        released.release()
        if pendingRender then render() end
    end
    if not activeSlider and not dragging and not resizing then
        if pendingFit then fit();saveWindowState() end
        if pendingRender then render() end
    end
end))
table.insert(connections, UIS.WindowFocusReleased:Connect(function()
    if activeSlider then activeSlider.release();activeSlider=nil end
    if dragging or resizing then saveWindowState() end
    dragging,resizing=false,nil
    if pendingFit then fit();saveWindowState() end
    if pendingRender then render() end
end))

table.insert(connections, UIS.InputBegan:Connect(function(i, processed)
    if confirmation then if i.KeyCode==Enum.KeyCode.Escape then closeConfirmation() end;return end
    if UIS:GetFocusedTextBox() then return end
    if i.KeyCode == Enum.KeyCode.Slash and root.Visible then
        local before = search.Text
        task.defer(function() search:CaptureFocus() end)
        task.delay(.05, function() if search.Text == before .. "/" then search.Text = before end end)
        return
    end
    if processed then return end
    Bridge.Key(i)
    local key = ui.key == "Right Control" and Enum.KeyCode.RightControl or Enum.KeyCode.K
    if i.KeyCode == key or i.KeyCode==Enum.KeyCode.LeftControl then visible(not root.Visible) end
end))

-- Falling leaves: at most twenty lightweight, noninteractive shapes. Nothing spawns while hidden.
local leaves = {}
clearLeaves = function()
    local oldLeaves = leaves
    leaves = {}
    for _, entry in ipairs(oldLeaves) do entry.tween:Cancel(); entry.object:Destroy() end
end
task.spawn(function()
    while gui.Parent do
        if root.Visible and leafEnabled and not ui.reduceMotion then
            if #leaves < 20 then
                local size=math.random(18,28)
                local startX=math.random(5,95)/100
                local endX=math.clamp(startX+math.random(-15,15)/100,0,1)
                local leaf = make("ImageLabel", {
                    Name="Leaf",Image=LEAF_ASSET,ScaleType=Enum.ScaleType.Fit,ImageColor3=C.accent,
                    BackgroundTransparency=1,Size=UDim2.fromOffset(size,size),
                    AnchorPoint=Vector2.new(.5,.5),
                    Position=UDim2.new(startX,32-64*startX,0,math.ceil(size/math.sqrt(2))),Rotation=math.random(0,360),ImageTransparency=.35,ZIndex=2
                },leafLayer)
                bind(leaf,"ImageColor3","accent")
                local duration=math.random(60,120)/10
                local tw=TweenService:Create(leaf,TweenInfo.new(duration,Enum.EasingStyle.Linear),{
                    Position=UDim2.new(endX,32-64*endX,1,-32),
                    Rotation=leaf.Rotation+math.random(360,720),ImageTransparency=1
                })
                local entry = {object = leaf, tween = tw}
                table.insert(leaves, entry)
                tw.Completed:Connect(function()
                    local at = table.find(leaves, entry)
                    if at then table.remove(leaves, at) end
                    leaf:Destroy()
                end)
                tw:Play()
            end
        else
            clearLeaves()
        end
        task.wait(math.random(45,80)/100)
    end
end)
root:GetPropertyChangedSignal("Visible"):Connect(function() if not root.Visible then clearLeaves() end end)

-- Session clock, footer metrics and team refresh ---------------------------
local frames = 0
table.insert(connections, RunService.Heartbeat:Connect(function() frames = frames + 1 end))
local function ping()
    local ok, value = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    if ok and type(value) == "number" then return math.floor(value + .5) end
    local ok2, seconds = pcall(function() return player:GetNetworkPing() end)
    if ok2 and type(seconds) == "number" then return math.floor(seconds * 1000 + .5) end
    return 0
end
local function refreshMetrics(fps)
    local clock, total = sessionClock()
    lastFPS,lastPing=fps,ping()
    local ok,memory=pcall(function()return Stats:GetTotalMemoryUsageMb()end)
    lastMemory=ok and type(memory)=="number" and math.floor(memory+.5) or 0
    if homeLabels.memory and homeLabels.memory.Parent then homeLabels.memory.Text=lastMemory>0 and tostring(lastMemory).." MB" or "—" end
    if homeLabels.fps and homeLabels.fps.Parent then homeLabels.fps.Text=tostring(fps) end
    if homeLabels.ping and homeLabels.ping.Parent then homeLabels.ping.Text=tostring(lastPing).." ms" end
    for _, t in ipairs(sessionLabels) do if t.Parent then t.Text = clock end end
    local parts = {}
    parts[#parts + 1] = fps .. " fps"
    parts[#parts + 1] = lastPing .. " ms"
    parts[#parts + 1] = string.format("%dh %02dm", math.floor(total / 3600), math.floor(total / 60) % 60)
    metrics.Text = table.concat(parts, "  ·  ")
end
task.spawn(function()
    local last = os.clock()
    while gui.Parent do
        task.wait(1)
        local now = os.clock()
        local fps = math.floor(frames / math.max(now - last, .001) + .5)
        frames, last = 0, now
        Bridge.RefreshNameColor()
        if root.Visible then
            refreshMetrics(fps)
            local dirty=false
            for _,item in ipairs(Bridge.items) do
                local before=type(item.value)=="table" and table.concat(item.value,"|") or item.value
                Bridge.Read(item)
                local after=type(item.value)=="table" and table.concat(item.value,"|") or item.value
                if before~=after then dirty=true end
                if item.liveLabel and item.liveLabel.Parent then item.liveLabel.Text=item.label end
            end
            if dirty then Bridge.needsRefresh=true end
            if Bridge.needsRefresh and not activeSlider and not openMenu and not UIS:GetFocusedTextBox() then Bridge.needsRefresh=false;requestRender() end
            setStatus()
            refreshMapInfo()
            if refreshTeam() then requestRender() end
        end
    end
end)

-- Responsive layout -------------------------------------------------------
layout = function()
    local w = root.Size.X.Offset
    compact = w < 760
    metrics.TextSize=compact and 8 or 9;statusLabel.TextSize=compact and 8 or 9
    local sideW = compact and 68 or 132
    sidebar.Size = UDim2.new(0, sideW, 1, -65)
    content.Position = UDim2.fromOffset(sideW + 10, 45)
    content.Size = UDim2.new(1, -(sideW + 20), 1, -65)
    for _, n in ipairs(navItems) do
        n.label.Visible = true
        n.button.Size=UDim2.new(1,0,0,compact and 42 or 28)

        n.label.Position=compact and UDim2.fromOffset(0,0) or UDim2.fromOffset(12,0)
        n.label.Size=compact and UDim2.fromScale(1,1) or UDim2.new(1,-24,1,0)
        n.label.TextSize=compact and 9 or 12
        n.label.TextXAlignment=compact and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
    end
    moveSelection(false)
    brand.Visible = w >= 470
    badge.Visible = w >= 820
    searchBox.Size = UDim2.fromOffset(w >= 620 and 190 or 140, 30)
    search.PlaceholderText = w >= 620 and "Search" or "Search"
    local contentW = w - sideW - 22
    local cols = contentW >= 600 and 2 or 1
    local below = contentW < 600
    if cols ~= columnCount or below ~= tabsBelow then
        columnCount, tabsBelow = cols, below
        requestRender()
    end
end

saveWindowState=function()
    local camera=workspace.CurrentCamera;if not camera then return end
    local vp=camera.ViewportSize
    Bridge.SaveUI({width=ui.w,height=ui.h,x=root.Position.X.Scale+root.Position.X.Offset/math.max(1,vp.X),y=root.Position.Y.Scale+root.Position.Y.Offset/math.max(1,vp.Y)})
end
ui.w=math.clamp(tonumber(Bridge.Initial().ui_state.width) or ui.w,360,3000)
ui.h=math.clamp(tonumber(Bridge.Initial().ui_state.height) or ui.h,360,2000)
fit = function()
    if activeSlider or dragging or resizing then pendingFit=true;return end
    pendingFit=false
    local camera = workspace.CurrentCamera
    if not camera then return end
    local vp = camera.ViewportSize
    local w = math.clamp(ui.w, 360, math.max(360, (vp.X - 24) / ui.scale))
    local h = math.clamp(ui.h, 360, math.max(360, (vp.Y - 24) / ui.scale))
    root.Size = UDim2.fromOffset(w, h)
    scale.Scale = math.min(ui.scale, (vp.X - 24) / w, (vp.Y - 24) / h)
    local state=Bridge.Initial().ui_state
    local halfW=w*scale.Scale/2;local halfH=h*scale.Scale/2
    local x=math.clamp((tonumber(state.x) or .5)*vp.X,halfW+8,math.max(halfW+8,vp.X-halfW-8))
    local y=math.clamp((tonumber(state.y) or .5)*vp.Y,halfH+8,math.max(halfH+8,vp.Y-halfH-8))
    root.Position = UDim2.fromOffset(x,y)
    if state.mobileX and state.mobileY then
        reopen.Position=UDim2.fromOffset(math.clamp(state.mobileX*vp.X,0,math.max(0,vp.X-44)),math.clamp(state.mobileY*vp.Y,0,math.max(0,vp.Y-44)))
    end
    layout()
end
local cameraConnection
local function watchCamera()
    if cameraConnection then cameraConnection:Disconnect() end
    if workspace.CurrentCamera then
        cameraConnection = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
    end
    fit()
end
table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera))

gui.Destroying:Connect(function()
    for _, conn in ipairs(connections) do conn:Disconnect() end
    if cameraConnection then cameraConnection:Disconnect() end
    activeSlider, dragging, resizing = nil, false, nil
    clearLeaves()
end)

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
setSetting("Close UI On Execution", closeOnExecution)
gui:SetAttribute("CloseOnExecution", closeOnExecution)
root.BackgroundTransparency = 1 - ui.opacity
gui:SetAttribute("ZoneColor",C.accent)
refreshTeam()
watchCamera()
ready = true
local bridgePending=false
local persistedState=Bridge.Initial().ui_state
local function syncBridge()
    if bridgePending then return end
    bridgePending=true
    task.defer(function()
        bridgePending=false
        if not gui.Parent then return end
        if persistedState~=Bridge.Initial().ui_state then
            persistedState=Bridge.Initial().ui_state
            collapsed=DeepCopy(persistedState.collapsed or {})
            restoreNavigation();paintNav();moveSelection(false)
            teamSelection={(persistedState.team or {})[1] or "Empty",(persistedState.team or {})[2] or "Empty"}
            root.Visible=not persistedState.hidden and not Settings.close_on_injection
            ui.w=persistedState.width or CONFIG.Width;ui.h=persistedState.height or CONFIG.Height
            fit()
        end
        for _,item in ipairs(Bridge.items)do Bridge.Read(item)end
        local scaleChanged=ui.scale~=Settings.ui_scale
        ui.scale=Settings.ui_scale;ui.opacity=Settings.ui_opacity;ui.mobile=Settings.mobile_toggle;ui.locked=Settings.lock_ui;ui.key=Settings.ui_toggle_key
        root.BackgroundTransparency=1-ui.opacity;reopen.Visible=ui.mobile or not root.Visible
        if scaleChanged then fit() end
        local color=findSetting("Accent Color")
        if color and tostring(color.value):gsub("#","")~=string.format("%02X%02X%02X",math.round(C.accent.R*255),math.round(C.accent.G*255),math.round(C.accent.B*255)) then applyTheme(Settings.ui_accent) end
        if activeSlider or openMenu or UIS:GetFocusedTextBox() then Bridge.needsRefresh=true else requestRender() end
    end)
end
Bridge.Attach(gui,syncBridge,notify)
KP.zoneColor=C.accent;AP.Render()
if Settings.anonymous_mode then AnonMode() end
Bridge.RefreshNameColor()
selectPage(activePage)
refreshMetrics(0)
visible(not closeOnExecution and not Bridge.Initial().ui_state.hidden)

end
buildInterface(Bridge)
end
KP.BuildUI()
]======]
local shared=getgenv()
local fn,err=loadstring(source,"KarmaPanda:X")
assert(fn,err)
shared.KP_InstallSource=source
local ok,result=pcall(fn)
shared.KP_InstallSource=nil
if not ok then error(result,0)end
