---@diagnostic disable: undefined-global

VERBOSE = true
SCRIPT_SILENT_START = true

--[[
    CaseScript: A rewrite and compilation of features I like, which may or may not of already existed.
--]]

util.require_natives(1651208000)
util.keep_running()

local root = menu.my_root()
local hashes = setmetatable({}, {
    __index = function (self, key)
        self[key] = util.joaat(key)
    end
})

-- [[ Utility Functions ]] --
--- Debug logging, toggled by _G.VERBOSE.
local function log(m)
    if VERBOSE then
        util.toast(m, TOAST_ALL)
    end
end

--- Increments a session Player ID appropriately.
local function increment_pid(pid)
    if pid < 30 then
        return pid + 1
    else
        return 0
    end
end

--- Sents a text message to the user of PID.
local function send_text_message(pid, msg)
    if players.exists(pid) then
        local uname = players.get_name(pid)
        menu.trigger_commands("smstext" .. uname .. " " .. msg)
        menu.trigger_commands("smsrandomsender" .. uname)
        menu.trigger_commands("smssend" .. uname)
    end
end

--- Converts a vehicle hash into a human-readable label name.
local function label_from_vehicle_hash(vehhash)
    if vehhash ~= 0 then
        return HUD._GET_LABEL_TEXT(VEHICLE.GET_DISPLAY_NAME_FROM_VEHICLE_MODEL(vehhash))
    else
        error("'label_from_vehicle_hash': invalid vehicle hash of 0.")
    end
end

--- Performs ejection when a blacklisted vehicle is used.
-- This will attempt deletion if a vehicle handle can be grabbed, otherwise it'll perform a scripted vehicle kick.
-- This returns the player name of the user who had their blacklisted vehicle removed, for debug purposes.
local function blacklist_veh(ped, vehhash)
    local pid = NETWORK.NETWORK_GET_PLAYER_INDEX_FROM_PED(ped)
    local vehicle = players.get_vehicle_model(pid)
    local player_name = PLAYER.GET_PLAYER_NAME(pid)
    if vehicle ~= 0 and player_name ~= "**Invalid**" then -- [[ Perform if a vehicle & player was detected in Online. ]] --
        local handle = PED.GET_VEHICLE_PED_IS_IN(ped, false) -- [[ Try and get a handle. ]] --
        if handle ~= 0 and VEHICLE.IS_VEHICLE_MODEL(handle, vehhash) then -- [[ Got handle, is handle a blackisted vehicke? If so, delete the handle. ]] --
            entities.delete_by_handle(handle)
            return player_name
        elseif vehicle == vehhash then -- [[ No handle, compare blip data. If it matches, then send a scripted vehicle kick. ]] --
            menu.trigger_commands("vehkick" .. player_name)
            return player_name
        end
    end
end

-- [[ Categories ]] --
local session_actions = menu.list(root, "Session", {}, "Session Options")

-- [[ Feature: Vehicle Blacklisting ]] --
-- Vehicle Blacklisting will delete vehicles by handle instead of using a vehicle kick, because less menus will probably give an explicit warning.
do
    local ignore_likely_modders = false -- See below.
    local ignore_friends = false -- Used to excempt friends from the vehicle blacklist.
    local ignore_modders = false -- Used to exempt modders from the vehicle blacklist.
    local notify_users = false -- Used to notify users why their vehicle was deleted (the blacklist).
    local smart = false -- Used to determine whether or not to utilize smarter heuristics.
    local last = 0 -- Used to track the last player being monitored for a blacklisted vehicle. Incremented every tick.

    local cmds = { "vehblacklist", "vehicleblacklist", "vblacklist" }
    local help = "Blacklist certain vehicles from usage inside this lobby."
    local vehicle_blacklisting = menu.list(session_actions, "Vehicle Blacklisting", cmds, help)

    --- This callback is ran every tick by each blacklist function.
    -- This function does all of the work for each blacklist. It handles modder-excemptions, smarter detections, and vehicle deleting.
    -- It also uses the 'increment_pid' helper function to increment the PID each tick. That's plenty to check the whole lobby, instead of 30 checks per-tick.
    local function callback(vehhash, pid)
        if (ignore_modders == true and players.is_marked_as_modder(pid)) or
           (ignore_friends == true and string.find(players.get_tags_string(pid), "F", 1, true)) or
           (ignore_likely_modders == true and string.find(players.get_tags_string(pid), "-", 1, true))
        then -- [[ Ignore modders, likely-modders, or friends: If need be. ]] --
            return increment_pid(pid)
        end

        if players.exists(pid) then
            local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
            if smart ~= true then -- [[ Perform if they're merely inside a blacklisted vehicle. ]]
                if players.user() ~= pid then
                    local name = blacklist_veh(ped, vehhash) -- [[ Does nothing if 'ped' is not in a vehicle. Handles the rest. ]]
                    if name then
                        log(name .. " may've had their vehicle deleted, because it violated the vehicle blacklist.")
                        if notify_users then
                            send_text_message(pid, "Sorry, but your vehicle is currently blacklisted in this lobby. This message has a spoofed author.")
                        end
                    end
                end
            else -- [[ 'Smart' detections: If someone is killed by a player inside of a vehicle. ]] --
                if ENTITY.IS_ENTITY_DEAD(ped) then -- [[ Each tick, we check if the current PID was killed by someone inside a blacklisted vehicle. ]] --
                    local enemy = PED.GET_PED_SOURCE_OF_DEATH(ped)
                    local is_player = ENTITY.IS_ENTITY_A_PED(enemy) and PED.IS_PED_A_PLAYER(enemy)
                    if is_player and ped ~= enemy then -- [[ Only perform for players which have not died by suicide. ]] --
                        local name = blacklist_veh(enemy, vehhash) -- [[ Does nothing if 'enemy' ped is not in a vehicle. ]]
                        if name then
                            log(name .. " may've had their vehicle deleted, because it violated the smart vehicle blacklist.")
                            if notify_users then
                                send_text_message(pid, "Sorry, but your vehicle is currently blacklisted in this lobby. This message has a spoofed author.")
                            end
                        end
                    end
                end
            end
        end
        return increment_pid(pid)
    end
    menu.divider(vehicle_blacklisting, "Common Blacklists")

    --[[
        You'll see below how the 'callback' functions works with the blacklisting functions.
        In this perspective, the only thing 'callback' is doing is taking the current PID (last) & returning the incremented PID.
        In theory, this should be N times faster than the usual method of looping through a new player list each tick. Where N = player count.
    --]]

    --[[
        You're also gonna see the 'cmds' & 'help' locals being redefined very often.
        I figured this was a slightly-more readable way to declare long parameters.
        Generally, you can assume that the 'cmds' & 'help' directly above a Stand API call are only relevant for that API call.
    --]]

    cmds = { "blacklistlazer" }
    help = "Blacklists any users in this lobby from flying the Lazer. Players using blacklisted vehicles will be ejected."
    menu.toggle_loop(vehicle_blacklisting, "Lazer", cmds, help, function ()
        last = callback(hashes["lazer"], last)
    end)

    cmds = { "blacklisthydra" }
    help = "Blacklists any users in this lobby from flying the Hydra. Players using blacklisted vehicles will be ejected."
    menu.toggle_loop(vehicle_blacklisting, "Hydra", cmds, help, function ()
        last = callback(hashes["hydra"], last)
    end)

    cmds = { "blacklisttm02", "blacklistkhanjali" }
    help = "Blacklists any users in this lobby from driving the TM-02 Khanjali stealth tank. Players using blacklisted vehicles will be ejected."
    menu.toggle_loop(vehicle_blacklisting, "TM-02 Khanjali", cmds, help, function ()
        last = callback(hashes["khanjali"], last)
    end)

    cmds = { "blacklistopmk1", "blacklistoppressormk1", "blacklistmk1op", "blacklistmk1oppressor" }
    help = "Blacklists any users in this lobby from riding the Oppressor Mk I. Players using blacklisted vehicles will be ejected."
    menu.toggle_loop(vehicle_blacklisting, "Oppressor Mk I", cmds, help, function ()
        last = callback(hashes["oppressor"], last)
    end)

    cmds = { "blacklistopmk2", "blacklistoppressormk2", "blacklistmk2op", "blacklistmk2oppressor" }
    help = "Blacklists any users in this lobby from riding the Oppressor Mk II. Players using blacklisted vehicles will be ejected."
    menu.toggle_loop(vehicle_blacklisting, "Oppressor Mk II", cmds, help, function ()
        last = callback(hashes["oppressor2"], last)
    end)

    -- [[ Custom Vehicle Reactions ]] --
    menu.divider(vehicle_blacklisting, "Custom Blacklist")

    cmds = { "customblacklist", "customvehblacklist", "customvehicleblacklist" }
    help = "Custom vehicle blacklisting, but you must know the raw model name of the vehicle you wish to blacklist."
    local sect = menu.list(vehicle_blacklisting, "Custom Vehicle Blacklist", cmds, help)

    cmds = { "customblacklistmodel" }
    help = "Add a custom model to the vehicle blacklist. This is typically congruent to the model you type in the command bar to spawn a vehicle."
    menu.text_input(sect, "Enter Model", cmds, help, function (text, _)
        local custom = menu.list(sect, text)

        cmds = {}
        help = "Toggles blacklist activation for this vehicle."
        local loop = menu.toggle_loop(custom, "Enabled", cmds, help, function ()
            last = callback(hashes[text], last)
        end)

        cmds = { ("deleteblacklist%s"):format(text) }
        help = "Deletes the blacklist entry for this vehicle. This is different than toggling activation."
        menu.action(custom, "Delete", cmds, help, function ()
            menu.set_value(loop, false)
            menu.delete(loop)
            menu.delete(custom)
        end)
    end)

    -- [[ Other Options ]] --
    menu.divider(vehicle_blacklisting, "Other Options")

    cmds = { "smartblacklist" }
    help = "Only eject someone if their blacklisted vehicle is used while killing someone. This will only function well when the targets are within render distance, otherwise the game has no idea they're in a vehicle."
    menu.toggle(vehicle_blacklisting, "Smart Eject", cmds, help, function (toggle)
        smart = toggle
    end)

    cmds = {}
    help = "Excempts friends from the vehicle blacklist."
    menu.toggle(vehicle_blacklisting, "Ignore Friends", cmds, help, function (toggle)
        ignore_friends = toggle
    end)

    cmds = {}
    help = "Ignores modders that are using blacklisted vehicles. This avoids them detecting your blacklist and potentially seeking revenge."
    menu.toggle(vehicle_blacklisting, "Ignore Modders", cmds, help, function (toggle)
        ignore_modders = toggle
    end)

    cmds = {}
    help = "Ignores likely-modders that are using blacklisted vehicles. This avoids them detecting your blacklist and potentially seeking revenge. Keep in mind, this searches detection tags for a hyphen. If your tags are not the default, then this may not work."
    menu.toggle(vehicle_blacklisting, "Ignore Likely Modders", cmds, help, function (toggle)
        ignore_likely_modders = toggle
    end)

    cmds = {}
    help = "Notifies users of blacklisted vehicles why their vehicle was deleted with a text message. The sender is randomized, you will remain anonymous."
    menu.toggle(vehicle_blacklisting, "Provide User Notifications", cmds, help, function (toggle)
        notify_users = toggle
    end)
end

--- Generate player features.
players.on_join(function (pid)
    local cmds, help
    local player_root = menu.player_root(pid)
    local player_name = PLAYER.GET_PLAYER_NAME(pid)

    if player_name == "**Invalid**" then
        return
    else
        menu.divider(player_root, "CaseScript")
    end

    cmds = { "vehoptions" }
    help = ("Vehicle options for %s."):format(player_name)
    local vehicle_options = menu.list(player_root, "Vehicle Options", cmds, help)

    cmds = { "vehblacklist" }
    help = ("Vehicle blacklist configuration for %s."):format(player_name)
    local vehicle_blacklisting = menu.list(vehicle_options, "Blacklisting", cmds, help)

    -- [[ Copy Model ]] --
    cmds = { "copymodelveh" }
    help = ("Copies the model name of %s's current vehicle. Particularly useful for a session's vehicle blacklist."):format(player_name)
    menu.action(vehicle_options, "Copy Model", cmds, help, function ()
        local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        local veh = PED.GET_VEHICLE_PED_IS_IN(ped, false)
        if veh ~= 0 then
            util.copy_to_clipboard(VEHICLE.GET_DISPLAY_NAME_FROM_VEHICLE_MODEL(ENTITY.GET_ENTITY_MODEL(veh)):lower(), true)
        else
            util.toast(player_name .. " is not in a rendered vehicle.")
        end
    end)

    --- Temporary, per-user vehicle blacklisting of all vehicles.
    -- Different from 'disable vehicle driving' because it:
    --      1. Doesn't require an invite to halt.
    --      2. Deletes the user's vehicle.

    cmds = { "blacklistall" }
    help = ("Blacklists %s from controlling any vehicles."):format(player_name)
    menu.toggle_loop(vehicle_blacklisting, "All Vehicles", cmds, help, function ()
        blacklist_veh(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), players.get_vehicle_model(pid))
    end)

    -- [[ Temp blacklisting. ]] --
    local temp_blacklist_per_tick   -- [[ The tick handler for each specific blacklist. Needed to alter command help text.    ]] --
    local current_vehicle_name      -- [[ The label name of the current vehicle being blacklisted. Used in altered help text. ]] --
    local current_vehicle           -- [[ A hash of the current blacklisted vehicle, via 'players.get_vehicle_model(pid)'.    ]] --
    local current_user              -- [[ The ped of the current PID/user we're blacklisting upon.                            ]] --

    --- Temporary, per-user vehicle blacklisting of the victim's current vehicle, at the time of toggle.
    cmds = { "tempblacklist" }
    help = ("Temporarily adds %s's current vehicle to a vehicle blacklist which only affects them."):format(player_name)
    temp_blacklist_per_tick = menu.toggle_loop(vehicle_blacklisting, "Current Vehicle", cmds, help, function () -- [[ on tick ]] --
        current_user = current_user or PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
        current_vehicle = current_vehicle or players.get_vehicle_model(pid)
        if players.exists(pid) and current_vehicle ~= 0 then
            local name = blacklist_veh(current_user, current_vehicle) -- [[ This will do nothing in a vehicle mismatch. ]] --
            if name then
                log(name .. "may've had their vehicle deleted because of a temporary, per-user blacklist violation.")
            end
            if current_vehicle_name == nil then
                current_vehicle_name = label_from_vehicle_hash(current_vehicle)
                menu.set_help_text(temp_blacklist_per_tick, help .. "\n\nCurrent Vehicle: " .. current_vehicle_name)
            end
        end
    end, function () -- [[ on stop ]] --
        current_vehicle_name = nil
        current_vehicle = nil
        current_user = nil
        if players.exists(pid) then -- [[ 'temp_blacklist_per_tick' will not exist if the player has left the session. ]] --
            menu.set_help_text(temp_blacklist_per_tick, help) -- [[ Remove 'current vehicle' information once blacklisting halts. ]] --
        end
    end)

    menu.divider(vehicle_blacklisting, "Common Blacklists")

    cmds = {}
    help = ("Blacklists %s from using the Lazer."):format(player_name)
    menu.toggle_loop(vehicle_blacklisting, "Lazer", cmds, help, function ()
        blacklist_veh(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), hashes["lazer"])
    end)

    cmds = {}
    help = ("Blacklists %s from using the Hydra."):format(player_name)
    menu.toggle_loop(vehicle_blacklisting, "Hydra", cmds, help, function ()
        blacklist_veh(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), hashes["hydra"])
    end)

    cmds = {}
    help = ("Blacklists %s from using the TM-02 Khanjali."):format(player_name)
    menu.toggle_loop(vehicle_blacklisting, "TM-02 Khanjali", cmds, help, function ()
        blacklist_veh(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), hashes["khanjali"])
    end)

    cmds = {}
    help = ("Blacklists %s from using the Oppressor Mk I."):format(player_name)
    menu.toggle_loop(vehicle_blacklisting, "Oppressor Mk I", cmds, help, function ()
        blacklist_veh(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), hashes["oppressor"])
    end)

    cmds = {}
    help = ("Blacklists %s from using the Oppressor Mk II."):format(player_name)
    menu.toggle_loop(vehicle_blacklisting, "Oppressor Mk II", cmds, help, function ()
        blacklist_veh(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), hashes["oppressor2"])
    end)

    menu.divider(vehicle_blacklisting, "Custom Blacklist")

    cmds = { "customblacklist" }
    help = ("Blacklist %s from using any of these models which you specify."):format(player_name)
    local custom_blacklist = menu.list(vehicle_blacklisting, "Custom Vehicle Blacklisting", cmds, help)

    cmds = { "vehmodelblacklist" }
    help = ("Enter the model name of the vehicle you wish to blacklist %s from using."):format(player_name)
    menu.text_input(custom_blacklist, "Enter Model", cmds, help, function (text, _)
        local custom = menu.list(custom_blacklist, text)

        cmds = {}
        help = "Toggles blacklist activation for this vehicle."
        local loop = menu.toggle_loop(custom, "Enabled", cmds, help, function ()
            blacklist_veh(PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid), hashes[text])
        end)

        cmds = {}
        help = "Deletes the blacklist entry for this vehicle & user."
        menu.action(custom, "Delete", cmds, help, function ()
            if players.exists(pid) then
                menu.set_value(loop, false)
                menu.delete(loop)
                menu.delete(custom)
            end
        end)
    end)
end)

players.dispatch_on_join()