-- Helyi, kiserleti parositas es kozos munka inditasa.
local ui = require("ui")
local Session = require("swarm_session")
local WorkRegistry = require("work_registry")
local Store = require("state_store")
local menu = {}

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

local function openLeader()
    if activeSoloJob() then
        notice("Aktiv egyturtle-os feladat mellett nem nyithato kozos munka.", "error")
        return
    end
    local mainLength = ui.integer("KOZOS MUNKA", "Foag hossza", 64, 1)
    if not mainLength then return end
    local branchLength = ui.integer("KOZOS MUNKA", "Oldalag hossza", 16, 1)
    if not branchLength then return end
    local branchSpacing = ui.integer("KOZOS MUNKA", "Agkoz", 3, 1)
    if not branchSpacing then return end
    local mode = ui.choice("ALAGUT MAGASSAGA", { "1x2", "1x3" }, 1)
    if not mode then return end
    if not ui.confirm("KOZOS MUNKA - TESZT", {
        "Ez meg csak hirdetes es parositas.",
        "Az asast kulon inditod a menuben.",
        "Vezeto: 1-es sorszam, lada mogotte.",
        "Foag: " .. mainLength .. ", oldal: " .. branchLength,
        "Agkoz: " .. branchSpacing,
    }, "ENTER = munka hirdetese") then return end
    local ok, reason, state = Session.openLeader({
        mainLength = mainLength, branchLength = branchLength,
        branchSpacing = branchSpacing, tunnelMode = mode,
    })
    notice(ok and { "Munka: " .. state.jobId,
        "A kezelo eszkozon kezzel fogadd el.", "A turtle helyben varakozik." }
        or tostring(reason), ok and nil or "error")
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
    if not ui.confirm("HELYI ELLENORZES", {
        "Azonos iranyba nezz, mint a vezeto.",
        "Jobbra allj " .. (slot - 1) .. " blokkra.",
        "Kozos start: " .. (slot - 1) .. ",0,0",
        "Ez csak regisztracio; nincs mozgas.",
    }, "ENTER = jelentkezes") then return end
    local ok, reason = Session.join(offer, slot)
    notice(ok and "Jelentkezes mentve; kezelo ACK-ra var." or tostring(reason),
        ok and nil or "error")
end

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
            { label = "Munka hirdetese (vezeto)", value = "open",
                enabled = not state or not state.active },
            { label = "Csatlakozas (seged)", value = "join",
                enabled = (not state or not state.active) and #offers > 0 },
            { label = "Foag asasa / folytatasa", value = "trunk",
                enabled = state and state.active and state.role == "leader"
                    and state.coordinatorId and linkAlive
                    and ((not savedTrunk and not activeSoloJob())
                        or (savedTrunk and branch.active)) },
            { label = "Kiosztott oldalagat asasa", value = "worker",
                enabled = state and state.active and state.role == "worker"
                    and state.assignedBranch and not state.transit
                    and linkAlive
                    and (state.status == "assigned_no_motion"
                        or state.status == "at_branch") },
            { label = "Allapot", value = "status" },
            { label = "Pozicio javitasa", value = "correct",
                enabled = state and state.active and state.role == "worker"
                    and state.status ~= "join_pending" },
            { label = "Seged kilepese", value = "leave",
                enabled = state and state.active and state.role == "worker"
                    and state.status == "registered_no_motion"
                    and not state.assignedBranch and not state.transit
                    and linkAlive },
            { label = "Jelentkezes visszavonasa", value = "cancel_join",
                enabled = state and state.active and state.role == "worker"
                    and state.status == "join_pending" and linkAlive },
            { label = "Elutasitott jelentkezes torlese", value = "reject_clear",
                enabled = state and state.active and state.role == "worker"
                    and state.status == "join_rejected" },
            { label = "Hirdetes lezarasa", value = "close",
                enabled = state and state.active and state.role == "leader"
                    and state.status ~= "close_pending"
                    and not (savedTrunk and branch.active) },
            { label = "Vissza", value = "back" },
        })
        if not choice or choice == "back" then return
        elseif choice == "open" then openLeader()
        elseif choice == "join" then joinWorker()
        elseif choice == "trunk" then
            if savedTrunk and branch.active then
                if ui.confirm("KOZOS FOAG FOLYTATASA", {
                    "A segedek tovabbra sem mozognak.",
                    "Kezelo #" .. state.coordinatorId,
                    "Mentett haladas: " .. (branch.mainCompleted or 0)
                        .. "/" .. state.mainLength,
                }, "ENTER = folytatas") then
                    return { action = "resume_trunk" }
                end
            elseif ui.confirm("KOZOS FOAG INDULAS", {
                "Csak a vezeto turtle as.",
                "A segedek varakoznak.",
                "Foag: " .. state.mainLength .. " blokk",
                "Kezelo #" .. state.coordinatorId,
            }, "ENTER = foag inditasa") then
                return { action = "start_trunk", session = state }
            end
        elseif choice == "worker" then
            if ui.confirm("SEGED OLDALAG - KISERLETI", {
                "Ag: " .. state.assignedBranch,
                "Csak 1x2/1x3; nincs erc/faklya.",
                "Folyoso es dokk: kezelo foglalja.",
                "Kapcsolatvesztesnel helyben megall.",
            }, "ENTER = seged inditasa") then
                return { action = "start_worker" }
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
                "Meg nincs kozos banyaszat/mozgasi jog.",
            } or { "Nincs helyi szinkronmunka.",
                "Lathato ajanlatok: " .. #offers })
        end
    end
end

return menu
