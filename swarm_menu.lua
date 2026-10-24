-- Helyi, kiserleti parositas es kozos munka inditasa.
local ui = require("ui")
local Session = require("swarm_session")
local WorkRegistry = require("work_registry")
local Store = require("state_store")
local Stations = require("station_registry")
local menu = {}

-- A hianyzo allapotmezo Lua-ban nil, amit az ui.menu alapbol engedelyezettnek
-- tekint. A felteteles menupontoknak mindig valodi boolean erteket adjunk.
local function available(value)
    return value and true or false
end

local function notice(lines, kind)
    ui.message("KOZOS MUNKA - KISERLETI", lines, kind)
    ui.waitForEnter()
end

local function activeSoloJob()
    local registry = WorkRegistry.load()
    if not registry or registry.status == "released"
        or registry.status == "completed" then return false end
    local state = require("state_store").read(registry.stateFile)
    return type(state) == "table" and state.active == true
end

local function joinWorker()
    if activeSoloJob() then
        notice("Aktiv feladat mellett nem lehet csatlakozni.", "error")
        return
    end
    local offers = Session.offers()
    if #offers == 0 then
        notice("Nincs friss, kezelohoz rendelt munkahirdetes.")
        return
    end
    local choices = {}
    for _, offer in ipairs(offers) do
        choices[#choices + 1] = {
            label = "Vezeto #" .. offer.leaderId .. " / " .. offer.jobId,
            value = offer,
        }
    end
    local offer = ui.menu("ELERHETO KOZOS MUNKAK", choices)
    if not offer then return end
    local slot = ui.integer("SORHELY", "Sorszam (jobbra)", 2, 2)
    if not slot then return end
    local checks = {
        "Azonos iranyba nezz, mint a vezeto.",
        "Jobbra allj " .. (slot - 1) .. " blokkra.",
        "Kozos start: " .. (slot - 1) .. ",0,0",
        "Ez csak regisztracio; nincs mozgas.",
        "Fuel: 1-es slot vagy mar feltoltve.",
    }
    if offer.workConfig and offer.workConfig.torchEnabled then
        checks[#checks + 1] = "Faklya: 2-es slot; lada a fuel lada folott."
    end
    if not ui.confirm("HELYI ELLENORZES", checks,
        "ENTER = jelentkezes") then return end
    local ok, reason = Session.join(offer, slot)
    notice(ok and "Jelentkezes mentve; kezelo ACK-ra var." or tostring(reason),
        ok and nil or "error")
end

menu.joinWorker = joinWorker

local function correctPose(state)
    local pose = state.pose or { x = 0, y = 0, z = 0, heading = 0 }
    local x = ui.integer("KOZOS POZICIO", "X", pose.x)
    if not x then return end
    local y = ui.integer("KOZOS POZICIO", "Y", pose.y)
    if not y then return end
    local z = ui.integer("KOZOS POZICIO", "Z", pose.z)
    if not z then return end
    local heading = ui.integer("KOZOS POZICIO", "Irany 0-3", pose.heading, 0, 3)
    if not heading then return end
    if not ui.confirm("HELYZET JAVITASA", {
        string.format("Mentett: %d,%d,%d h%d", pose.x, pose.y, pose.z, pose.heading),
        string.format("Valos: %d,%d,%d h%d", x, y, z, heading),
        "Koordinatori egyeztetesig nincs mozgas.",
    }, "ENTER = javitas mentese") then return end
    state.pose = { x = x, y = y, z = z, heading = heading }
    state.status = "needs_reconcile"
    local ok, reason = Session.update(state)
    notice(ok and "Helyzet mentve; egyeztetes szukseges." or tostring(reason),
        ok and nil or "error")
end

local function registerLocalStation(state)
    local slot = state.role == "leader" and 1 or state.slot
    local id = Stations.id(slot)
    if not ui.confirm("LEADOLADA ELLENORZESE", {
        "A turtle a sajat indulocellajan alljon.",
        "A lada kozvetlenul mogotte legyen.",
        id .. (slot == 1 and ": foallomas + ellatas"
            or ": csak lepakolas"),
        "A turtle helyben megfordul es megnezi.",
    }, "ENTER = lada ellenorzese") then return end
    state.stationCheckPending = true
    local saved, saveReason = Session.update(state)
    if not saved then
        notice("Nem mentheto az iranyellenorzes: " .. tostring(saveReason), "error")
        return
    end
    if not turtle.turnRight() or not turtle.turnRight() then
        notice("A fordulas nem sikerult; iranyt kezzel ellenorizd.", "error")
        return
    end
    local found, block = turtle.inspect()
    if not turtle.turnRight() or not turtle.turnRight() then
        notice("A visszafordulas nem sikerult; iranyt kezzel ellenorizd.", "error")
        return
    end
    state.stationCheckPending = false
    local restored, restoreReason = Session.update(state)
    if not restored then
        notice("Az irany visszaallitasa nem mentheto: "
            .. tostring(restoreReason), "error")
        return
    end
    if not found or not block or not Stations.isChest(block.name) then
        notice("Nem talalok ladat a sajat indulocella mogott.", "error")
        return
    end
    state.stationRegistration = {
        slot = slot, chestName = block.name,
        requestId = tostring(os.getComputerID()) .. "-station-"
            .. tostring(os.epoch("utc")),
    }
    state.stationRegistered = nil
    state.stationChestName = nil
    local ok, reason = Session.update(state)
    notice(ok and (id .. " ellenorizve; koordinatori ACK-ra var.")
        or tostring(reason), ok and nil or "error")
end

function menu.run()
    while true do
        local state = Session.load()
        local offers = Session.offers()
        local branch = Store.read("branch_miner_state.txt")
        local savedTrunk = type(branch) == "table" and branch.config
            and state and branch.config.swarmJobId == state.jobId
            and branch.config.swarmTrunkOnly == true
        local linkAlive = state and state.lastHeartbeatAt
            and os.epoch and os.epoch("utc") - state.lastHeartbeatAt <= 6000
        local choice = ui.menu("KOZOS MUNKA - KISERLETI", {
            { label = "Csatlakozas (seged)", value = "join",
                enabled = (not state or not state.active) and #offers > 0 },
            { label = "Foag asasa / folytatasa", value = "trunk",
                enabled = available(state and state.active and state.role == "leader"
                    and not state.stationCheckPending
                    and state.coordinatorId and linkAlive
                    and ((not savedTrunk and not activeSoloJob())
                        or (savedTrunk and branch.active))) },
            { label = "Allapot", value = "status" },
            { label = "Sajat leadolada regisztralasa", value = "station",
                enabled = available(state and state.active and not state.transit
                    and not state.stationCheckPending
                    and not state.stationRegistration
                    and (state.role == "worker"
                        and state.status == "registered_no_motion"
                        and not state.assignedBranch
                        or state.role == "leader" and not savedTrunk)) },
            { label = "Ladaellenorzes iranyanak tisztazasa", value = "station_fix",
                enabled = available(state and state.active and state.stationCheckPending) },
            { label = "Pozicio javitasa", value = "correct",
                enabled = available(state and state.active
                    and (state.role == "worker" or state.role == "leader"
                        and state.assignedBranch)
                    and state.status ~= "join_pending") },
            { label = "Seged kilepese", value = "leave",
                enabled = available(state and state.active and state.role == "worker"
                    and state.status == "registered_no_motion"
                    and not state.assignedBranch and not state.transit
                    and linkAlive) },
            { label = "Jelentkezes visszavonasa", value = "cancel_join",
                enabled = available(state and state.active and state.role == "worker"
                    and state.status == "join_pending" and linkAlive) },
            { label = "Elutasitott jelentkezes torlese", value = "reject_clear",
                enabled = available(state and state.active and state.role == "worker"
                    and state.status == "join_rejected") },
            { label = "Hirdetes lezarasa", value = "close",
                enabled = available(state and state.active and state.role == "leader"
                    and state.status ~= "close_pending"
                    and not (savedTrunk and branch.active)) },
            { label = "Vissza", value = "back" },
        })
        if not choice or choice == "back" then return
        elseif choice == "join" then joinWorker()
        elseif choice == "trunk" then
            if savedTrunk and branch.active then
                if ui.confirm("KOZOS FOAG FOLYTATASA", {
                    "A kesz agakra a segedek elindulhatnak.",
                    "Kezelo #" .. state.coordinatorId,
                    "Mentett haladas: " .. (branch.mainCompleted or 0)
                        .. "/" .. state.mainLength,
                }, "ENTER = folytatas") then
                    return { action = "resume_trunk" }
                end
            elseif ui.confirm("KOZOS FOAG INDULAS", {
                "A vezeto a foagat epiti.",
                "A kesz agakra a segedek elindulnak.",
                "Foag: " .. state.mainLength .. " blokk",
                "Kezelo #" .. state.coordinatorId,
            }, "ENTER = foag inditasa") then
                return { action = "start_trunk", session = state }
            end
        elseif choice == "station" then registerLocalStation(state)
        elseif choice == "station_fix" then
            if ui.confirm("IRANY HELYSZINI ELLENORZESE", {
                "Ellenorizd: a turtle a sajat indulocellan all.",
                "Ugyanabba a +Z iranyba nez, mint a vezeto indulaskor.",
                "Nem kovetkeztetunk automatikusan a mentett iranybol.",
            }, "ENTER = fizikai hely es irany igazolt") then
                state.stationCheckPending = false
                local ok, reason = Session.update(state)
                notice(ok and "Irany igazolva; a lada ujra ellenorizheto."
                    or tostring(reason), ok and nil or "error")
            end
        elseif choice == "correct" then correctPose(state)
        elseif choice == "leave" or choice == "cancel_join" then
            if ui.confirm("SEGED KILEP", {
                "Csak sajat sorhelyen, mozgas nelkul.",
                "A kezelo visszaigazolasaig foglalt marad.",
            }, "ENTER = kilepes kerese") then
                state.status = "leave_pending"
                state.leaveRequestId = tostring(os.getComputerID()) .. "-"
                    .. tostring(os.epoch("utc"))
                local ok, reason = Session.update(state)
                notice(ok and "Kilepesi keres mentve; ACK-ra var."
                    or tostring(reason), ok and nil or "error")
            end
        elseif choice == "reject_clear" then
            state.active, state.status = false, "join_rejected_cleared"
            local ok, reason = Session.update(state)
            notice(ok and "Elutasitott jelentkezes torolve."
                or tostring(reason), ok and nil or "error")
        elseif choice == "close" then
            if ui.confirm("HIRDETES LEZARASA",
                "A kezelo megvarja a segedek biztonsagos kilepeset.",
                "ENTER = lezaras") then
                if state.coordinatorId then
                    state.status = "close_pending"
                    state.closeRequestId = tostring(os.getComputerID()) .. "-"
                        .. tostring(os.epoch("utc"))
                else
                    state.active, state.status = false, "closed"
                end
                local ok, reason = Session.update(state)
                notice(ok and (state.active and "Lezarasi keres mentve; ACK-ra var."
                    or "Hirdetes lezarva.") or tostring(reason),
                    ok and nil or "error")
            end
        elseif choice == "status" then
            notice(state and {
                "ID: " .. state.jobId,
                "Szerep: " .. state.role .. ", sorszam: " .. state.slot,
                "Allapot: " .. state.status,
                "Kezelo: " .. tostring(state.coordinatorId or "nincs"),
                "Ag: " .. tostring(state.assignedBranch or "nincs"),
                "Lada: " .. (state.stationRegistered and "regisztralva"
                    or state.stationRegistration and "ACK-ra var" or "nincs"),
            } or { "Nincs helyi szinkronmunka.",
                "Lathato ajanlatok: " .. #offers })
        end
    end
end

return menu
