-- InventoryBackPack for Multiplayer -- persistent per-savegame bags.
-- The vanilla vehicles.xml retains the REAL objects and all mod-added specializations.
-- This file stores ONLY owner/slot/unique vehicle id; it does not clone or respawn items.
local PB = PlayerBackpack
local ROOT = 'inventoryBackPack'
local FILE = 'InventoryBackPack.xml'

local function activeServer()
    return g_server ~= nil and g_currentMission ~= nil and g_currentMission.missionInfo ~= nil
end

local function getSavePath()
    if not activeServer() then return nil end
    local info=g_currentMission.missionInfo
    local dir=info.savegameDirectory
    if (dir==nil or dir=='') and info.savegameIndex~=nil and getUserProfileAppPath~=nil then
        dir=string.format('%ssavegame%d',getUserProfileAppPath(),tonumber(info.savegameIndex) or 1)
    end
    if type(dir)~='string' or dir=='' then return nil end
    return dir..'/'..FILE
end

function PB:getPersistentObjectId(obj)
    if obj==nil then return nil end
    local uid=nil
    if type(obj.getUniqueId)=="function" then
        uid=obj:getUniqueId()
    end
    uid=uid or obj.uniqueId
    if type(uid)~='string' or uid=='' then return nil end
    -- Only objects maintained in vehicleSystem can be reliably reconstructed.
    local vs=g_currentMission and g_currentMission.vehicleSystem
    if vs==nil or vs.getVehicleByUniqueId==nil or vs:getVehicleByUniqueId(uid)~=obj then
        return nil
    end
    return uid
end

local function sortedKeys(tbl)
    local out={}
    for k in pairs(tbl or {}) do out[#out+1]=k end
    table.sort(out,function(a,b) return tostring(a)<tostring(b) end)
    return out
end

local function writeRecord(xml,key,uid,idx,rec)
    local id=rec.uniqueId
    if id==nil and rec.object~=nil then id=PB:getPersistentObjectId(rec.object) end
    if id==nil or id=='' then return false end
    setXMLString(xml,key..'#playerId',tostring(uid))
    setXMLInt(xml,key..'#slot',idx)
    setXMLString(xml,key..'#objectId',id)
    setXMLInt(xml,key..'#rigidType',tonumber(rec.oldType) or -1)
    setXMLFloat(xml,key..'#x',tonumber(rec.x) or 0)
    setXMLFloat(xml,key..'#y',tonumber(rec.y) or 0)
    setXMLFloat(xml,key..'#z',tonumber(rec.z) or 0)
    for _,field in ipairs({'name','baseName','configDetails','groupKey','xmlFilename'}) do
        setXMLString(xml,key..'#'..field,tostring(rec[field] or ''))
    end
    local configs=rec.configSelections or {}
    local cidx=0
    for _,confName in ipairs(sortedKeys(configs)) do
        local ckey=key..string.format('.config(%d)',cidx)
        setXMLString(xml,ckey..'#key',tostring(confName))
        setXMLString(xml,ckey..'#value',tostring(configs[confName]))
        cidx=cidx+1
    end
    for i,ft in ipairs(rec.fillTypes or {}) do
        setXMLInt(xml,key..string.format('.fill(%d)#type',i-1),tonumber(ft) or 0)
    end
    return true
end

function PB:savePersistedBags()
    local path=getSavePath()
    if path==nil then
        print('[InventoryBackPack] WARNING: save path not available; inventory metadata NOT SAVED')
        return false
    end
    local xml=createXMLFile('inventoryBackPackSave',path,ROOT)
    if xml==nil or xml==0 then
        print('[InventoryBackPack] ERROR: could not create savegame metadata '..path)
        return false
    end
    setXMLInt(xml,ROOT..'#version',1)
    local index=0
    local known={}
    for _,uid in ipairs(sortedKeys(self.serverBags)) do
        local bag=self.serverBags[uid]
        for slot=1,20 do
            if bag[slot]~=nil then
                known[uid..'|'..slot]=true
                if writeRecord(xml,ROOT..string.format('.item(%d)',index),uid,slot,bag[slot]) then
                    index=index+1
                else
                    print('[InventoryBackPack] WARNING: could not save item in '..tostring(uid)..' slot '..slot)
                end
            end
        end
    end
    -- Records whose vanilla objects have not finished loading are kept, not lost.
    for _,uid in ipairs(sortedKeys(self.pendingBagRecords)) do
        for slot=1,20 do
            local rec=self.pendingBagRecords[uid][slot]
            if rec and not known[uid..'|'..slot] then
                if writeRecord(xml,ROOT..string.format('.item(%d)',index),uid,slot,rec) then index=index+1 end
            end
        end
    end
    saveXMLFile(xml)
    delete(xml)
    return true
end

local function readRecord(xml,key)
    local uid=getXMLString(xml,key..'#playerId')
    local slot=getXMLInt(xml,key..'#slot')
    local id=getXMLString(xml,key..'#objectId')
    if uid==nil or uid=='' or id==nil or id=='' or slot==nil or slot<1 or slot>20 then return nil,nil,nil end
    local rec={uniqueId=id,oldType=getXMLInt(xml,key..'#rigidType'),
        x=getXMLFloat(xml,key..'#x'),y=getXMLFloat(xml,key..'#y'),z=getXMLFloat(xml,key..'#z'),
        configSelections={},fillTypes={}}
    for _,field in ipairs({'name','baseName','configDetails','groupKey','xmlFilename'}) do
        rec[field]=getXMLString(xml,key..'#'..field) or ''
    end
    for j=0,49 do
        local ckey=key..string.format('.config(%d)',j)
        local ck=getXMLString(xml,ckey..'#key')
        if ck==nil then break end
        rec.configSelections[ck]=getXMLString(xml,ckey..'#value') or ''
    end
    for j=0,15 do
        local f=getXMLInt(xml,key..string.format('.fill(%d)#type',j))
        if f==nil then break end
        rec.fillTypes[#rec.fillTypes+1]=f
    end
    return uid,slot,rec
end

function PB:loadPersistedBags()
    if self.persistenceLoaded or not activeServer() then return end
    local path=getSavePath()
    if path==nil then return end
    -- Missing file is normal for a new map or an upgrade from pre-save releases.
    self.persistenceLoaded=true
    self.pendingBagRecords=self.pendingBagRecords or {}
    if not fileExists(path) then
        return
    end
    local xml=loadXMLFile('inventoryBackPackLoad',path)
    if xml==nil or xml==0 then
        print('[InventoryBackPack] ERROR: inventory metadata unreadable: '..path)
        return
    end
    local count=0
    for i=0,10000 do
        local key=ROOT..string.format('.item(%d)',i)
        if not hasXMLProperty(xml,key) then break end
        local uid,slot,rec=readRecord(xml,key)
        if uid and slot and rec then
            self.pendingBagRecords[uid]=self.pendingBagRecords[uid] or {}
            self.pendingBagRecords[uid][slot]=rec
            count=count+1
        end
    end
    delete(xml)
end

function PB:restorePersistedBags()
    if not activeServer() or self.pendingBagRecords==nil then return end
    local vs=g_currentMission.vehicleSystem
    if vs==nil or vs.getVehicleByUniqueId==nil then return end
    for uid,items in pairs(self.pendingBagRecords) do
        for slot,rec in pairs(items) do
            local obj=vs:getVehicleByUniqueId(rec.uniqueId)
            if obj~=nil and obj.rootNode~=nil and entityExists(obj.rootNode) then
                -- Upgrade protection: older versions mistakenly allowed whole
                -- vehicles into backpacks. Do NOT hide them again on restart.
                -- Restore the original world position and remove the bad record.
                if self.isSafePortableObject~=nil and not self.isSafePortableObject(obj) then
                    local wx,wy,wz=getWorldTranslation(obj.rootNode)
                    local ox,oy,oz=rec.x or wx,rec.y or wy,rec.z or wz
                    self:serverSetObjectState(obj,false,ox,oy,oz,rec.oldType)
                    items[slot]=nil
                else
                local bag=self:getBag(uid)
                if bag[slot]==nil and self.objectOwners[obj]==nil then
                    rec.object=obj
                    rec.node=obj.rootNode
                    rec.xmlFilename=obj.configFileName or rec.xmlFilename
                    if rec.oldType==nil or rec.oldType<0 then
                        rec.oldType=getRigidBodyType(obj.rootNode)
                    end
                    if rec.oldType~=nil then
                        -- Never spawn a second object: reclaim the existing vanilla object.
                        local x,y,z=getWorldTranslation(obj.rootNode)
                        rec.x=rec.x or x
                        rec.y=rec.y or y
                        rec.z=rec.z or z
                        if self:serverSetObjectState(obj,true,rec.x,self.PARKED_Y-slot*4,rec.z,rec.oldType) then
                            bag[slot]=rec
                            self.objectOwners[obj]=uid
                            items[slot]=nil
                        end
                    end
                end
                end
            end
        end
        if next(items)==nil then self.pendingBagRecords[uid]=nil end
    end
end

function PB:prepareObjectsForVanillaSave()
    self.vanillaSavePositions={}
    for _,bag in pairs(self.serverBags or {}) do
        for slot,s in pairs(bag) do
            if s.node and entityExists(s.node) then
                local x,y,z=getWorldTranslation(s.node)
                self.vanillaSavePositions[#self.vanillaSavePositions+1]={node=s.node,x=x,y=y,z=z,slot=slot}
                -- Keep kinematic + invisible, but save their last VALID world position
                -- in FS25's vehicles.xml (not the temporary 5000 m holding area).
                setWorldTranslation(s.node,s.x or x,s.y or y,s.z or z)
            end
        end
    end
end

function PB:reparkObjectsAfterVanillaSave()
    for _,entry in ipairs(self.vanillaSavePositions or {}) do
        if entityExists(entry.node) then
            setWorldTranslation(entry.node,entry.x,entry.y,entry.z)
        end
    end
    self.vanillaSavePositions=nil
end

function PB:installPersistenceHooks()
    if PB.persistenceHooksInstalled then return end
    if VehicleSystem==nil or VehicleSystem.save==nil then
        print('[InventoryBackPack] ERROR: VehicleSystem.save unavailable; persistence hook disabled')
        return
    end
    local originalSave=VehicleSystem.save
    VehicleSystem.save=function(vehicleSystem,xmlFilename,usedModNames)
        local bp=PlayerBackpack
        if bp==nil or not activeServer() or vehicleSystem~=g_currentMission.vehicleSystem then
            return originalSave(vehicleSystem,xmlFilename,usedModNames)
        end
        -- Bind metadata write to the very same save operation as vehicles.xml.
        bp:prepareObjectsForVanillaSave()
        originalSave(vehicleSystem,xmlFilename,usedModNames)
        bp:reparkObjectsAfterVanillaSave()
        bp:savePersistedBags()
    end
    PB.persistenceHooksInstalled=true
end
