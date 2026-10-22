-- 5 x 3 grid. Mouse and keyboard navigation; inventory state stays server-owned.
InventoryBackpackDialog = {}
local M = Class(InventoryBackpackDialog, DialogElement)
function InventoryBackpackDialog.new(target, mt)
    local self = DialogElement.new(target, mt or M)
    self.backpack = nil
    self.items = {}
    self.selectedIndex = 1
    self.gridPage = 1
    self.enterIsHeld = false
    return self
end
function InventoryBackpackDialog:setBackpack(bp) self.backpack=bp end
function InventoryBackpackDialog:onOpen()
    InventoryBackpackDialog:superClass().onOpen(self)
    self.enterIsHeld = false
    self.gridPage = 1
    self:rebuildItems()
end
function InventoryBackpackDialog:onClose()
    InventoryBackpackDialog:superClass().onClose(self)
end
-- Safe UTF-8 handling for Russian shop labels (Lua string.sub is byte-based).
local function chars(s)
    local result={}
    for c in tostring(s or ""):gmatch("[\0-\127\194-\244][\128-\191]*") do result[#result+1]=c end
    return result
end
local function readableValues(details)
    local values={}
    for line in tostring(details or ""):gmatch("[^\r\n]+") do
        local value=line:match(":%s*(.+)$") or line
        if value~="" then values[#values+1]=value end
    end
    return table.concat(values,"   \\   ")
end
function InventoryBackpackDialog:rebuildItems()
    local previous=self.items[self.selectedIndex]
    local previousKey=previous and previous.key
    self.items={}
    local groups={}
    if self.backpack then
        for i=1,20 do
            local s=self.backpack.slots[i]
            if s then
                -- The key is derived from the actual live object on pickup.
                -- Do not merge objects if their full signature is unavailable.
                local key=s.groupKey or ("unidentified:"..tostring(i))
                local group=groups[key]
                if not group then
                    group={key=key,slots={},baseName=s.baseName or s.name or "Предмет",details=s.configDetails or "",image=s.image}
                    groups[key]=group
                    self.items[#self.items+1]=group
                end
                group.slots[#group.slots+1]=i
            end
        end
    end
    self.selectedIndex=math.max(1,math.min(self.selectedIndex,#self.items))
    if previousKey then
        for i,item in ipairs(self.items) do
            if item.key==previousKey then self.selectedIndex=i;break end
        end
    end
    self.gridPage=self.selectedIndex>15 and 2 or 1
    self.scrollElapsed=0
    self.scrollOffset=0
    self:refresh()
end
function InventoryBackpackDialog:refreshDetailScroll()
    if not self.detailText then return end
    local item=self.items[self.selectedIndex]
    if not item then
        self.detailText:setText("Наведитесь на расходник и нажмите Y")
        return
    end
    local full=readableValues(item.details)
    if full=="" or full=="Без дополнительных конфигураций" then
        self.detailText:setText("Без дополнительных конфигураций")
        return
    end
    -- A two-row rolling text window. Nothing is shortened with ellipses:
    -- every original character appears as the window moves.
    local letters=chars(full)
    local width=63
    if #letters<=width then
        self.detailText:setText(full)
    elseif #letters<=width*2 then
        self.detailText:setText(table.concat(letters,"",1,width).."\n"..table.concat(letters,"",width+1))
    else
        local offset=(self.scrollOffset or 0) % #letters
        local doubled={}
        for i=1,width*2 do
            doubled[i]=letters[((offset+i-1)%#letters)+1]
        end
        self.detailText:setText(table.concat(doubled,"",1,width).."\n"..table.concat(doubled,"",width+1))
    end
end
function InventoryBackpackDialog:update(dt)
    InventoryBackpackDialog:superClass().update(self,dt)
    if self.isOpen then
        self.scrollElapsed=(self.scrollElapsed or 0)+(dt or 0)
        if self.scrollElapsed>=180 then
            self.scrollElapsed=self.scrollElapsed%180
            self.scrollOffset=(self.scrollOffset or 0)+1
            self:refreshDetailScroll()
        end
    end
end
-- Fifteen visible slots; old saves containing more than fifteen distinct
-- groups use a temporary second recovery page. No saved object is discarded.
function InventoryBackpackDialog:refresh()
    local n=#self.items
    if n<16 then self.gridPage=1 end
    local first=(self.gridPage==2 and n>15) and 16 or 1
    if n>0 then
        if self.selectedIndex<first or self.selectedIndex>math.min(first+14,n) then
            self.selectedIndex=first
        end
    end
    for v=1,15 do
        local actual=first+v-1
        local item=self.items[actual]
        local btn=self.slotButton and self.slotButton[v]
        if btn then
            btn.inventoryIndex=item and actual or nil
            btn:setDisabled(item==nil)
            btn:setSelected(item~=nil and actual==self.selectedIndex)
        end
        local bg=self.slotBackground and self.slotBackground[v]
        if bg then bg:setVisible(item~=nil) end
        local empty=self.slotEmptyBackground and self.slotEmptyBackground[v]
        if empty then empty:setVisible(item==nil) end
        local icon=self.slotIcon and self.slotIcon[v]
        if icon then
            local filename=item and item.image
            icon:setVisible(filename~=nil and filename~="")
            if filename and filename~="" then icon:setImageFilename(filename) end
        end
        local count=self.slotCount and self.slotCount[v]
        if count then
            local quantity=item and #item.slots or 0
            count:setText(quantity>1 and ("x"..tostring(quantity)) or "")
        end
    end
    local overflow=self.overflowButton
    if overflow then
        overflow:setVisible(n>15)
        if n>15 then
            overflow:setText(self.gridPage==1
                and ("ЕЩЁ "..tostring(n-15).." ПРЕДМЕТОВ  >")
                or "<  НАЗАД К ПЕРВЫМ 15")
        end
    end
    local selected=self.items[self.selectedIndex]
    if self.detailTitle then
        self.detailTitle:setText(selected and selected.baseName or "РЮКЗАК ПУСТ")
    end
    self.scrollElapsed=0
    self.scrollOffset=0
    self:refreshDetailScroll()
    local used=0
    for _,item in ipairs(self.items) do used=used+#item.slots end
    if self.carouselPositionText then
        self.carouselPositionText:setText(string.format("%d / 15",used))
    end
    if self.actionButton then self.actionButton:setDisabled(selected==nil) end
    if self.titleIcon then self.titleIcon:setVisible(false) end
end
function InventoryBackpackDialog:onClickSlot(button)
    if button and button.inventoryIndex then
        self.selectedIndex=button.inventoryIndex
        self:refresh()
    end
end
function InventoryBackpackDialog:onFocusSlot(button)
    -- Native GIANTS UI focus navigation is supported as a fallback for arrows.
    if button and button.inventoryIndex and self.selectedIndex~=button.inventoryIndex then
        self.selectedIndex=button.inventoryIndex
        self:refresh()
    end
end
function InventoryBackpackDialog:onClickOverflow()
    if #self.items<=15 then return end
    self.gridPage=self.gridPage==1 and 2 or 1
    self.selectedIndex=self.gridPage==2 and 16 or 1
    self:refresh()
end
-- Navigation stays inside the current row/column, moving five positions
-- vertically. There is no wrap from right edge to the next row.
function InventoryBackpackDialog:moveSelection(direction)
    local n=#self.items
    if n<1 then return end
    local first=(self.gridPage==2 and n>15) and 16 or 1
    local current=math.max(first,math.min(self.selectedIndex,math.min(first+14,n)))
    local relative=current-first
    local col=relative%5
    local row=math.floor(relative/5)
    local target=current
    if direction=="left" and col>0 then
        target=current-1
    elseif direction=="right" and col<4 then
        target=current+1
    elseif direction=="up" then
        if row>0 then target=current-5
        elseif self.gridPage==2 and n>15 then
            self.gridPage=1
            target=11+col
        end
    elseif direction=="down" then
        if row<2 then target=current+5
        elseif self.gridPage==1 and n>15 then
            self.gridPage=2
            target=16+col
        end
    end
    local maxIndex=math.min((self.gridPage==2 and 30 or 15),n)
    local minIndex=self.gridPage==2 and 16 or 1
    if target>maxIndex then
        -- The next row exists, but the exact column is empty: choose its last item.
        local nextRow=first+(row+1)*5
        if direction=="down" and nextRow<=maxIndex then target=maxIndex
        else target=current end
    end
    target=math.max(minIndex,math.min(target,maxIndex))
    if target~=self.selectedIndex then self.selectedIndex=target end
    self:refresh()
end
function InventoryBackpackDialog:onClickAction()
    local item=self.items[self.selectedIndex]
    if self.backpack and item then
        self.backpack.selected=item.slots[1]
        self.backpack:drop()
        self:rebuildItems()
    end
end
function InventoryBackpackDialog:onCloseButton()
    self:close()
end
-- Native dialog back handling (ESC / gamepad back).
function InventoryBackpackDialog:onClickBack(forceBack, usedMenuButton)
    self:close()
    return true
end
-- While a modal GUI is open, gameplay PB_OPEN action may be suppressed.
-- Handle the same I key directly in the dialog.
function InventoryBackpackDialog:keyEvent(unicode, sym, modifier, isDown, eventUsed)
    if self.isOpen and Input~=nil then
        if sym==Input.KEY_i and isDown then
            self:close()
            return true
        end
        local enter=(sym==Input.KEY_return or sym==Input.KEY_KP_enter)
        if enter then
            if isDown and not self.enterIsHeld then
                self.enterIsHeld=true
                self:onClickAction()
            elseif not isDown then
                self.enterIsHeld=false
            end
            -- Also consume key-up so GUI focus can't activate another button.
            return true
        end
        if isDown then
            if sym==Input.KEY_left then self:moveSelection("left"); return true end
            if sym==Input.KEY_right then self:moveSelection("right"); return true end
            if sym==Input.KEY_up then self:moveSelection("up"); return true end
            if sym==Input.KEY_down then self:moveSelection("down"); return true end
        end
    end
    return InventoryBackpackDialog:superClass().keyEvent(self,unicode,sym,modifier,isDown,eventUsed)
end
