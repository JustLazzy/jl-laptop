local QBCore = exports['qb-core']:GetCoreObject()
local crateCount = 0
crates = {} -- Table which stores crate netIDs with its contents ( shop items )

local function AddItems(stash, Items)
    local items = {}

    for k, v in pairs(Items) do
        local itemInfo = QBCore.Shared.Items[k:lower()]
        items[#items+1] = {
            name = itemInfo["name"],
            amount = tonumber(v),
            info = "",
            label = itemInfo["label"],
            description = itemInfo["description"] ~= nil and itemInfo["description"] or "",
            weight = itemInfo["weight"],
            type = itemInfo["type"],
            unique = itemInfo["unique"],
            useable = itemInfo["useable"],
            image = itemInfo["image"],
            slot = #items+1,
        }
    end

    MySQL.Async.insert('INSERT INTO stashitems (stash, items) VALUES (:stash, :items) ON DUPLICATE KEY UPDATE items = :items', {
        ['stash'] = stash,
        ['items'] = json.encode(items)
    })
end

local function HasStashItems(stashId)
	local result = MySQL.Sync.fetchScalar('SELECT items FROM stashitems WHERE stash = ?', {stashId})
	if not result then return end
    local stashItems = json.decode(result)
    if not stashItems then return end

    return true, #stashItems
end

local function boxDeletionTimer(netID)
    Wait(60 * 1000 * 60) -- 1 hour ( i think )
    DeleteObject(NetworkGetEntityFromNetworkId(netID))
    crates[netID] = nil
end

local function createCrate(items)
    local crateObj = CreateObject(`prop_lev_crate_01`, Config.DarkWeb.CrateSpawn.x, Config.DarkWeb.CrateSpawn.y, Config.DarkWeb.CrateSpawn.z, true, false)
    while not DoesEntityExist(crateObj) do
        Wait(50)
    end
    if DoesEntityExist(crateObj) then
        local netID = NetworkGetNetworkIdFromEntity(crateObj)
        TriggerClientEvent('darkweb:client:cratedrop', -1, netID)
        AddItems("DarkWebCrate_"..crateCount + 1, items)
        crates[netID] = {
            ['id'] = crateCount + 1,
            ['isOpened'] = false
        }
        TriggerClientEvent('jl-laptop:client:updateCrates', -1, crates)
        boxDeletionTimer(netID)
    end
end

QBCore.Functions.CreateCallback('jl-laptop:server:checkout', function(source, cb, data)
    local src = source
    local appLabel = 'Bennys'
    if data.app == 'darkweb' then
        appLabel = 'DarkWeb'
    end

    local Player = QBCore.Functions.GetPlayer(src)
    if not HasAppAccess(src, data['app']) then return cb("full") end
    local Saved = data['cart']
    local Shop = {
        totalBank = 0,
        totalGNE = 0,
        totalCrypto = 0,
        items = {}
    }
    if Saved then
        for _, v in pairs(Saved) do
            Shop.items[Config[appLabel].Items[v.name].name] = v.quantity
            if Config[appLabel].Items[v.name].type == "bank" then
                Shop.totalBank = Shop.totalBank + (Config[appLabel].Items[v.name].price * v.quantity)
            elseif Config[appLabel].Items[v.name].type == "crypto" then
                Shop.totalCrypto = Shop.totalCrypto + (Config[appLabel].Items[v.name].price * v.quantity)
            else
                Shop.totalGNE = Shop.totalGNE + (Config[appLabel].Items[v.name].price * v.quantity)
            end
        end

        print(json.encode(Saved))
        local hasItem, amount = HasStashItems(appLabel.."Shop_"..Player.PlayerData.citizenid)
        if hasItem and amount > 0 then return cb("full") end
        local checks = 0
        local bank = false
        local crypto = false
        if Shop.totalBank > 0 then
            checks = checks + 1
            if Player.PlayerData.money.bank >= Shop.totalBank then
                checks = checks - 1
                bank = true
            else
                return cb("bank")
            end
        end

        if Shop.totalCrypto > 0 then
            checks = checks + 1
            if Player.PlayerData.money.crypto >= Shop.totalCrypto then
                checks = checks - 1
                crypto = true
            else
                return cb("crypto")
            end
        end

        if checks == 0 then
            if bank then Player.Functions.RemoveMoney("bank", Shop.totalBank) end
            if crypto then Player.Functions.RemoveMoney("crypto", Shop.totalCrypto) end
            if data['app'] == 'darkweb' then
                createCrate(Shop.items)
            else
                AddItems("BennyShop_"..Player.PlayerData.citizenid, Shop.items)
            end
            cb("done")
        end
    end
end)

-- For dev environment
AddEventHandler('onResourceStop', function(resource)
   if resource == GetCurrentResourceName() then
    for box, _ in pairs(crates) do
        DeleteEntity(NetworkGetEntityFromNetworkId(box))
    end
   end
end)
