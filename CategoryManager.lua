-- v0.0.121: independent priority inputs, visual drag order, bulk Item ID entry.
-- v0.0.120: category management and a single verified item assignment receiver.
-- Drag rows to reorder. The editor drop tile NEVER performs a physical item
-- transaction: Core owns verified real-cursor return before assigning an ID.
local _,ns=...
ns.CategoryManager={}
local M=ns.CategoryManager
local page,callbacks,listPanel,editorPanel,sharePanel,status,createInput,editInput,itemInput
local rowPool,includePool,choicePool,itemPool={},{},{},{}
local itemsPage,itemPagePrev,itemPageNext,itemPageLabel=1,nil,nil,nil
local ITEMS_PAGE_SIZE=15
local resetButton,deleteButton,selector,choicePage= nil,nil,nil,1
local current,mode,confirmReset,confirmDelete,dropdown,dragged,dragTarget
local dragLine,dragWatch,dragGhost,ignoreClick
local shareInput,shareStatus,shareTitle,shareHint,shareHighlightButton,shareImportButton
local sharePrevious,shareExportID
local GOLD={.78,.64,.41}
local CYAN={.19,.74,1}
local MUTED={.62,.74,.82}
local function Registry() return ns.CategoryRegistry end
local function Label(parent,text,font,color)
  local f=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
  f:SetText(text or "")
  if color then f:SetTextColor(color[1],color[2],color[3]) end
  return f
end
local function Place(widget,parent,x,y)
  widget:ClearAllPoints()
  widget:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
end
local function Button(parent,w,text,fn)
  local b=CreateFrame("Button",nil,parent,"BackdropTemplate")
  b:SetSize(w,25)
  b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  local label=Label(b,text,"GameFontHighlightSmall",GOLD)
  label:SetPoint("CENTER",b,"CENTER",0,0)
  b.text=label
  b:SetScript("OnEnter",function(self)
    self:SetBackdropColor(.08,.20,.29,.96)
    self:SetBackdropBorderColor(.18,.70,1,.95)
  end)
  b:SetScript("OnLeave",function(self)
    self:SetBackdropColor(.025,.04,.055,.30)
    self:SetBackdropBorderColor(.40,.36,.31,.45)
  end)
  b:SetScript("OnClick",function(self) if fn then fn(self) end end)
  b:GetScript("OnLeave")(b)
  return b
end
local function EditBox(parent,w)
  local edit=CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
  edit:SetSize(w,25)
  edit:SetAutoFocus(false)
  return edit
end
local function Report(msg)
  if status and mode=="list" then status:SetText(msg or "") end
  if callbacks and callbacks.message and msg and msg~="" then callbacks.message(msg) end
end
local function CanEdit()
  if callbacks and callbacks.canEdit then
    local ok,why=callbacks.canEdit()
    if not ok then Report(why or "Finish the active inventory action first.");return false end
  end
  -- Category editor never consumes a real item cursor. Item-drop support is
  -- intentionally reserved for a separate versioned transaction-safe test.
  if GetCursorInfo then
    local ok,kind=pcall(GetCursorInfo)
    if not ok or (issecretvalue and issecretvalue(kind)) or kind~=nil then
      Report("Put down the held cursor item before editing category rules.")
      return false
    end
  end
  return true
end
local function Changed()
  if callbacks and callbacks.onChange then callbacks.onChange() end
  M.Refresh()
end
local function Alter(method,...)
  if not CanEdit() then return false end
  local r=Registry()
  if not r or not r[method] then return false end
  local ok,result=r[method](...)
  if not ok then Report(result or "Unable to update category");return false end
  confirmReset=false;confirmDelete=false
  if resetButton then resetButton.text:SetText("Reset default categories") end
  if deleteButton then deleteButton.text:SetText("Delete custom category") end
  Changed()
  return true,result
end
local function ScreenIndex()
  if not dragged or not GetCursorPosition or not UIParent then return nil end
  local rawX,rawY=GetCursorPosition()
  local scale=UIParent:GetEffectiveScale()
  if not rawX or not rawY or not scale or scale<=0 then return nil end
  local x,y=rawX/scale,rawY/scale
  local n=#Registry().All()
  if n==0 then return nil end
  local first,last=rowPool[1],rowPool[n]
  if not first or not first.select.GetTop or not last.select.GetBottom then return nil end
  local top,bottom=first.select:GetTop(),last.select:GetBottom()
  local left,right=first.select:GetLeft(),first.priority:GetRight()
  if not top or not bottom or not left or not right then return nil end
  if x<left-8 or x>right+8 or y>top+12 or y<bottom-12 then return nil end
  local insertion=1
  for i=1,n do
    local frame=rowPool[i].select
    local rowTop,rowBottom=frame:GetTop(),frame:GetBottom()
    if rowTop and rowBottom and y<(rowTop+rowBottom)/2 then
      insertion=i+1
    end
  end
  return insertion
end
local function UpdateDragLine()
  if not dragged or mode~="list" then dragLine:Hide();return end
  local idx=ScreenIndex()
  dragTarget=idx
  if not idx then dragLine:Hide();return end
  local n=#Registry().All()
  local target=rowPool[math.min(idx,n)]
  if not target then dragLine:Hide();return end
  dragLine:ClearAllPoints()
  if idx<=n then
    dragLine:SetPoint("TOPLEFT",target.select,"TOPLEFT",0,3)
  else
    dragLine:SetPoint("TOPLEFT",target.select,"BOTTOMLEFT",0,-3)
  end
  dragLine:Show()
end
local function MoveGhost()
  if not dragged or not dragGhost or not listPanel or not UIParent or not GetCursorPosition then return end
  local rawX,rawY=GetCursorPosition()
  local scale=UIParent:GetEffectiveScale()
  local x,y=rawX and scale and rawX/scale,rawY and scale and rawY/scale
  local left,top=listPanel:GetLeft(),listPanel:GetTop()
  if x and y and scale and scale>0 and left and top then
    dragGhost:ClearAllPoints()
    dragGhost:SetPoint("CENTER",listPanel,"TOPLEFT",x-left,y-top)
  end
end
local function StopDrag(commit)
  local id,insertion=dragged,dragTarget
  dragged=nil;dragTarget=nil
  if dragLine then dragLine:Hide() end
  if dragGhost then dragGhost:Hide() end
  if dragWatch then dragWatch:Hide() end
  if not commit or not id or not insertion then return end
  local from
  for i,def in ipairs(Registry().All()) do if def.id==id then from=i;break end end
  if not from then return end
  local position=insertion
  if from<insertion then position=insertion-1 end
  if position==from then return end
  ignoreClick=true
  if C_Timer and C_Timer.After then
    C_Timer.After(.1,function() ignoreClick=false end)
  end
  Alter("MoveTo",id,position)
end
local function StartDrag(button)
  if mode~="list" or dragged or not CanEdit() then return end
  if not button.categoryID then return end
  dragged=button.categoryID
  if dragGhost then
    dragGhost.text:SetText(Registry().Label(dragged) or dragged)
    dragGhost:Show()
  end
  dragWatch:Show()
  MoveGhost()
  UpdateDragLine()
end
local function OpenEditor(id)
  if dragged or ignoreClick or not Registry().IsKnown(id) then return end
  current=id;mode="editor";dropdown=false;choicePage=1;itemsPage=1;confirmDelete=false
  if createInput then createInput:ClearFocus() end
  listPanel:Hide();if sharePanel then sharePanel:Hide() end;editorPanel:Show()
  M.Refresh()
  if page and page.GetParent then
    local scroll=page:GetParent()
    if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
  end
end
local function BackToList()
  StopDrag(false)
  mode="list";dropdown=false;confirmDelete=false
  if editInput then editInput:ClearFocus() end
  if itemInput then itemInput:ClearFocus() end
  if shareInput then shareInput:ClearFocus() end
  editorPanel:Hide();if sharePanel then sharePanel:Hide() end;listPanel:Show()
  M.Refresh()
  if page and page.GetParent then
    local scroll=page:GetParent()
    if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
  end
end
local function MakeRow(index)
  local row={}
  row.select=Button(listPanel,253,"",function(self) OpenEditor(self.categoryID) end)
  row.select.text:ClearAllPoints()
  row.select.text:SetPoint("LEFT",row.select,"LEFT",8,0)
  row.select.text:SetWidth(234)
  if row.select.text.SetMaxLines then row.select.text:SetMaxLines(1) end
  row.select:RegisterForDrag("LeftButton")
  row.select:SetScript("OnDragStart",function(self) StartDrag(self) end)
  row.select:SetScript("OnDragStop",function()
    UpdateDragLine();StopDrag(true)
  end)
  row.show=Button(listPanel,65,"",function(self)
    if self.categoryID=="misc" then
      Report("Miscellaneous is the required item fallback.");return
    end
    Alter("SetShown",self.categoryID,not self.categoryShown)
  end)
  row.priority=EditBox(listPanel,73)
  row.priority:SetMaxLetters(2)
  row.priority:SetNumeric(true)
  row.priority:SetJustifyH("CENTER")
  row.priority:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
  row.priority:SetScript("OnEscapePressed",function(self)
    self:SetText(tostring(Registry().Priority(self.categoryID) or 0))
    self:ClearFocus()
  end)
  row.priority:SetScript("OnEditFocusLost",function(self)
    if not self.categoryID then return end
    local text=self:GetText()
    if text~=tostring(Registry().Priority(self.categoryID) or 0) then
      Alter("SetPriority",self.categoryID,text)
    end
    self:SetText(tostring(Registry().Priority(self.categoryID) or 0))
  end)
  rowPool[index]=row
  return row
end
local function RefreshList()
  if not listPanel then return end
  local defs=Registry().All()
  for i,def in ipairs(defs) do
    local row=rowPool[i] or MakeRow(i)
    local y=-196-(i-1)*34
    Place(row.select,listPanel,12,y)
    Place(row.show,listPanel,274,y)
    Place(row.priority,listPanel,357,y)
    for _,button in ipairs({row.select,row.show}) do
      button.categoryID=def.id;button.categoryShown=def.shown;button:Show()
    end
    row.priority.categoryID=def.id
    if not row.priority:HasFocus() then
      row.priority:SetText(tostring(def.priority or 0))
    end
    row.priority:Show()
    row.select.text:SetText("::  "..def.label)
    row.show.text:SetText(def.mandatory and "LOCKED" or (def.shown and "[X]" or "[ ]"))
  end
  for i=#defs+1,#rowPool do
    local row=rowPool[i]
    row.select:Hide();row.show:Hide();row.priority:Hide()
  end
  local y=-196-#defs*34-18
  Place(resetButton,listPanel,14,y)
  listPanel:SetHeight(math.abs(y)+94)
  page:SetHeight(listPanel:GetHeight())
end
local function ItemIcon(itemID)
  local texture
  if GetItemIcon then
    local ok,v=pcall(GetItemIcon,itemID)
    if ok then texture=v end
  end
  if not texture and C_Item and C_Item.GetItemIconByID then
    local ok,v=pcall(C_Item.GetItemIconByID,itemID)
    if ok then texture=v end
  end
  return texture or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local editorTitle,editorType,nameLabel,defaultButton,includesTitle,itemsTitle
local includeButton,prevChoices,nextChoices,addButton,addIDTitle,emptyNote
local dropSlot,dropHint,dropStatus,exportButton
local function IncludeRow(i)
  if includePool[i] then return includePool[i] end
  local row={}
  row.name=Label(editorPanel,"","GameFontHighlightSmall",MUTED)
  row.remove=Button(editorPanel,75,"Remove",function(self)
    Alter("SetIncluded",current,self.targetID,false)
  end)
  includePool[i]=row
  return row
end
local function ChoiceRow(i)
  if choicePool[i] then return choicePool[i] end
  local b=Button(editorPanel,420,"",function(self)
    if Alter("SetIncluded",current,self.targetID,true) then
      dropdown=false;choicePage=1;M.Refresh()
    end
  end)
  b.text:ClearAllPoints();b.text:SetPoint("LEFT",b,"LEFT",8,0)
  choicePool[i]=b
  return b
end
local function ItemRow(i)
  if itemPool[i] then return itemPool[i] end
  local row={}
  row.icon=editorPanel:CreateTexture(nil,"ARTWORK")
  row.icon:SetSize(31,31)
  row.text=Label(editorPanel,"","GameFontHighlightSmall",MUTED)
  row.remove=Button(editorPanel,75,"Remove",function(self)
    Alter("SetItem",current,self.itemID,false)
  end)
  itemPool[i]=row
  return row
end
local function RefreshEditor()
  if not editorPanel or mode~="editor" or not current then return end
  local r=Registry()
  if not r.IsKnown(current) then BackToList();return end
  local custom=r.IsCustom(current)
  editorTitle:SetText(r.Label(current) or "Category")
  editorType:SetText(custom and "CUSTOM CATEGORY" or "DEFAULT CATEGORY")
  if not editInput:HasFocus() then editInput:SetText(r.Label(current) or "") end
  defaultButton:SetShown(not custom)
  deleteButton:SetShown(custom)
  includesTitle:SetShown(custom)
  itemsTitle:SetShown(custom)
  includeButton:SetShown(custom)
  addIDTitle:SetShown(custom)
  itemInput:SetShown(custom)
  addButton:SetShown(custom)
  dropSlot:SetShown(custom)
  dropHint:SetShown(custom)
  dropStatus:SetShown(custom)
  if exportButton then exportButton:SetShown(custom) end
  if not custom then
    for _,row in ipairs(includePool) do row.name:Hide();row.remove:Hide() end
    for _,row in ipairs(itemPool) do row.icon:Hide();row.text:Hide();row.remove:Hide() end
    for _,choice in ipairs(choicePool) do choice:Hide() end
    prevChoices:Hide();nextChoices:Hide();emptyNote:Hide()
    if itemPageLabel then itemPageLabel:Hide();itemPagePrev:Hide();itemPageNext:Hide() end
    editorPanel:SetHeight(225);page:SetHeight(225)
    return
  end
  local y=-187
  Place(includesTitle,editorPanel,15,y);y=y-29
  local includes=r.Includes(current)
  for i,definition in ipairs(includes) do
    local row=IncludeRow(i)
    Place(row.name,editorPanel,21,y-5)
    row.name:SetText(definition.label)
    row.name:SetWidth(320)
    Place(row.remove,editorPanel,363,y)
    row.remove.targetID=definition.id
    row.name:Show();row.remove:Show();y=y-30
  end
  for i=#includes+1,#includePool do
    includePool[i].name:Hide();includePool[i].remove:Hide()
  end
  if #includes==0 then y=y-2 end
  Place(includeButton,editorPanel,20,y)
  includeButton.text:SetText(dropdown and "Select a category  ^" or "Add included category  v")
  y=y-32
  if dropdown then
    local choices={}
    for _,definition in ipairs(r.All()) do
      if definition.id~=current and not r.IncludesID(current,definition.id) then
        choices[#choices+1]=definition
      end
    end
    local maxPage=math.max(1,math.ceil(#choices/6))
    choicePage=math.min(choicePage,maxPage)
    for i=1,6 do
      local def=choices[(choicePage-1)*6+i]
      local button=ChoiceRow(i)
      if def then
        Place(button,editorPanel,22,y)
        button.targetID=def.id
        button.text:SetText("+  "..def.label)
        button:Show();y=y-28
      else button:Hide() end
    end
    Place(prevChoices,editorPanel,24,y);Place(nextChoices,editorPanel,143,y)
    prevChoices:SetShown(choicePage>1)
    nextChoices:SetShown(choicePage<maxPage)
    y=y-31
  else
    for _,button in ipairs(choicePool) do button:Hide() end
    prevChoices:Hide();nextChoices:Hide()
  end
  y=y-12
  Place(itemsTitle,editorPanel,15,y);y=y-31
  Place(dropSlot,editorPanel,24,y)
  Place(dropHint,editorPanel,75,y-3)
  Place(dropStatus,editorPanel,75,y-21)
  y=y-54
  Place(addIDTitle,editorPanel,21,y-3)
  Place(itemInput,editorPanel,114,y)
  Place(addButton,editorPanel,303,y)
  y=y-38
  local items=r.Items(current)
  local maxItemPage=math.max(1,math.ceil(#items/ITEMS_PAGE_SIZE))
  itemsPage=math.min(itemsPage,maxItemPage)
  local currentItems=0
  emptyNote:SetShown(#items==0)
  if #items==0 then Place(emptyNote,editorPanel,21,y);y=y-25 end
  for n=1,ITEMS_PAGE_SIZE do
    local itemID=items[(itemsPage-1)*ITEMS_PAGE_SIZE+n]
    if itemID then
    currentItems=n
    local row=ItemRow(n)
    Place(row.icon,editorPanel,22,y)
    row.icon:SetTexture(ItemIcon(itemID))
    Place(row.text,editorPanel,68,y-8)
    local itemName
    if GetItemInfo then
      local ok,result=pcall(GetItemInfo,itemID)
      if ok and not (issecretvalue and issecretvalue(result)) then itemName=result end
    end
    if type(itemName)~="string" or itemName=="" then
      itemName="Item ID: "..tostring(itemID)
    else itemName=itemName.."  ("..itemID..")" end
    row.text:SetText(itemName)
    row.text:SetWidth(280)
    Place(row.remove,editorPanel,363,y+3)
    row.remove.itemID=itemID
    row.icon:Show();row.text:Show();row.remove:Show()
    y=y-39
    end
  end
  for i=currentItems+1,#itemPool do
    itemPool[i].icon:Hide();itemPool[i].text:Hide();itemPool[i].remove:Hide()
  end
  if #items>0 then
    itemPageLabel:SetText("Items "..((itemsPage-1)*ITEMS_PAGE_SIZE+1).."-"..
      math.min(#items,itemsPage*ITEMS_PAGE_SIZE).." of "..#items)
    Place(itemPageLabel,editorPanel,23,y-5)
    Place(itemPagePrev,editorPanel,196,y)
    Place(itemPageNext,editorPanel,310,y)
    itemPageLabel:Show()
    itemPagePrev:SetShown(itemsPage>1)
    itemPageNext:SetShown(itemsPage<maxItemPage)
    y=y-37
  else
    itemPageLabel:Hide();itemPagePrev:Hide();itemPageNext:Hide()
  end
  editorPanel:SetHeight(math.max(350,math.abs(y)+45))
  page:SetHeight(editorPanel:GetHeight())
end
local function BuildSharingPanel()
  sharePanel=CreateFrame("Frame",nil,page)
  sharePanel:SetPoint("TOPLEFT",page,"TOPLEFT",0,0)
  sharePanel:SetSize(468,370);sharePanel:Hide()
  local importCategoryButton=Button(listPanel,142,"Import category",function()
    M.OpenShare(false)
  end)
  Place(importCategoryButton,listPanel,308,-8)
  exportButton=Button(editorPanel,170,"Export this category",function()
    if current and Registry().IsCustom(current) then M.OpenShare(true) end
  end)
  Place(exportButton,editorPanel,21,-149)
  -- Sharing is a separate nonsecure page. Clipboard transfer uses normal
  -- WoW EditBox keyboard shortcuts (Ctrl+C / Ctrl+V), never foreign cursors.
  local shareBack=Button(sharePanel,185,"< Back",function()
    if shareInput then shareInput:ClearFocus() end
    if sharePrevious=="editor" and shareExportID and
        Registry().IsKnown(shareExportID) then
      OpenEditor(shareExportID)
    else BackToList() end
  end)
  Place(shareBack,sharePanel,14,-8)
  shareTitle=Label(sharePanel,"","GameFontNormal",GOLD)
  Place(shareTitle,sharePanel,17,-54)
  shareHint=Label(sharePanel,"","GameFontHighlightSmall",MUTED)
  Place(shareHint,sharePanel,18,-91)
  local shareLabel=Label(sharePanel,"CATEGORY SHARING STRING","GameFontNormalSmall",GOLD)
  Place(shareLabel,sharePanel,17,-123)
  shareInput=EditBox(sharePanel,425)
  shareInput:SetMaxLetters(16000)
  Place(shareInput,sharePanel,22,-146)
  shareInput:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  shareHighlightButton=Button(sharePanel,180,"Select entire string",function()
    shareInput:SetFocus()
    shareInput:HighlightText(0,#shareInput:GetText())
    shareStatus:SetText("Press Ctrl+C to copy the selected sharing string.")
  end)
  Place(shareHighlightButton,sharePanel,20,-196)
  shareImportButton=Button(sharePanel,180,"Import category",function()
    if not CanEdit() then return end
    if not ns.CategorySharing then return end
    local ok,result=ns.CategorySharing.Import(shareInput:GetText())
    if not ok then
      shareStatus:SetText(result or "Import failed")
      return
    end
    shareStatus:SetText("Imported "..result.count.." custom categor"..
      (result.count==1 and "y" or "ies")..".")
    Changed()
    OpenEditor(result.id)
  end)
  Place(shareImportButton,sharePanel,20,-196)
  shareStatus=Label(sharePanel,"","GameFontHighlightSmall",CYAN)
  Place(shareStatus,sharePanel,20,-245)
  shareStatus:SetWidth(420)
end

function M.Initialize(container,opts)
  if page then return end
  page,callbacks,mode=container,opts or {},"list"
  listPanel=CreateFrame("Frame",nil,page)
  listPanel:SetPoint("TOPLEFT",page,"TOPLEFT",0,0)
  listPanel:SetSize(468,850)
  editorPanel=CreateFrame("Frame",nil,page)
  editorPanel:SetPoint("TOPLEFT",page,"TOPLEFT",0,0)
  editorPanel:SetSize(468,600);editorPanel:Hide()
  local listTitle=Label(listPanel,"MANAGE CATEGORIES","GameFontNormal",GOLD)
  Place(listTitle,listPanel,14,-10)
  Place(Label(listPanel,"Drag rows to change bag order. Priority controls which rules win.",
    "GameFontHighlightSmall",MUTED),listPanel,14,-36)
  Place(Label(listPanel,"Built-in priority 0; custom priority 1. Higher wins (0-99).",
    "GameFontHighlightSmall",MUTED),listPanel,14,-53)
  Place(Label(listPanel,"NEW CUSTOM CATEGORY","GameFontNormalSmall",GOLD),listPanel,14,-86)
  createInput=EditBox(listPanel,255);Place(createInput,listPanel,21,-109)
  createInput:SetMaxLetters(40)
  local create=Button(listPanel,142,"+ Add category",function()
    local ok,id=Alter("Create",createInput:GetText())
    if ok then createInput:SetText("");OpenEditor(id) end
  end)
  Place(create,listPanel,305,-109)
  createInput:SetScript("OnEnterPressed",function(self)
    local ok,id=Alter("Create",self:GetText())
    if ok then self:SetText("");self:ClearFocus();OpenEditor(id) end
  end)
  createInput:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  status=Label(listPanel,"Select a category to edit rules and Item IDs.","GameFontHighlightSmall",CYAN)
  Place(status,listPanel,15,-147)
  -- Independent header labels above their actual columns; no space padding.
  Place(Label(listPanel,"CATEGORY / DRAG ::","GameFontNormalSmall",GOLD),listPanel,15,-175)
  local showHeader=Label(listPanel,"SHOW","GameFontNormalSmall",GOLD)
  showHeader:SetPoint("CENTER",listPanel,"TOPLEFT",306.5,-184)
  local priorityHeader=Label(listPanel,"PRIORITY","GameFontNormalSmall",GOLD)
  priorityHeader:SetPoint("CENTER",listPanel,"TOPLEFT",393.5,-184)
  resetButton=Button(listPanel,215,"Reset default categories",function(self)
    if not confirmReset then
      confirmReset=true;self.text:SetText("Confirm reset defaults")
      Report("Reset built-in names, visibility, priorities and display order? Custom categories remain.")
    else Alter("ResetDefaults") end
  end)
  dragLine=listPanel:CreateTexture(nil,"OVERLAY")
  dragLine:SetSize(440,2)
  dragLine:SetColorTexture(.18,.74,1,.95)
  dragLine:Hide()
  -- A lightweight ghost visibly follows the cursor while the underlying
  -- category rows remain stable.  Never use StartMoving on a nested menu
  -- frame or interact with a real inventory cursor here.
  dragGhost=CreateFrame("Frame",nil,listPanel,"BackdropTemplate")
  dragGhost:SetSize(253,26)
  dragGhost:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  dragGhost:SetBackdropColor(.09,.20,.29,.92)
  dragGhost:SetBackdropBorderColor(.18,.74,1,1)
  dragGhost:SetFrameLevel(listPanel:GetFrameLevel()+12)
  dragGhost:EnableMouse(false)
  dragGhost.text=Label(dragGhost,"","GameFontHighlightSmall",GOLD)
  dragGhost.text:SetPoint("CENTER",dragGhost,"CENTER",0,0)
  dragGhost:Hide()
  dragWatch=CreateFrame("Frame",nil,listPanel)
  dragWatch:SetScript("OnUpdate",function()
    if not dragged or mode~="list" or (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then
      -- The source OnDragStop normally commits. The watcher is only a cleanup
      -- if combat, window hiding, or input loss interrupts the drag.
      if dragged and (mode~="list" or not listPanel:IsShown() or
          (IsMouseButtonDown and not IsMouseButtonDown("LeftButton"))) then
        StopDrag(false)
      end
      return
    end
    MoveGhost()
    UpdateDragLine()
  end)
  dragWatch:Hide()
  listPanel:SetScript("OnHide",function() StopDrag(false) end)

  local back=Button(editorPanel,180,"< Back to categories",BackToList)
  Place(back,editorPanel,14,-8)
  editorType=Label(editorPanel,"","GameFontHighlightSmall",MUTED)
  Place(editorType,editorPanel,20,-49)
  editorTitle=Label(editorPanel,"","GameFontNormal",GOLD)
  Place(editorTitle,editorPanel,160,-50)
  Place(Label(editorPanel,"NAME","GameFontNormalSmall",GOLD),editorPanel,15,-86)
  editInput=EditBox(editorPanel,213);Place(editInput,editorPanel,22,-107)
  editInput:SetMaxLetters(40)
  local saveName=Button(editorPanel,94,"Save name",function()
    if current then Alter("Rename",current,editInput:GetText()) end
  end)
  Place(saveName,editorPanel,251,-107)
  defaultButton=Button(editorPanel,100,"Default name",function()
    if current then Alter("ResetName",current) end
  end)
  Place(defaultButton,editorPanel,350,-107)
  editInput:SetScript("OnEnterPressed",function(self)
    if current then Alter("Rename",current,self:GetText()) end
    self:ClearFocus()
  end)
  editInput:SetScript("OnEscapePressed",function(self)
    self:ClearFocus();self:SetText(Registry().Label(current) or "")
  end)
  deleteButton=Button(editorPanel,175,"Delete custom category",function(self)
    if not current then return end
    if not confirmDelete then
      confirmDelete=true;self.text:SetText("Confirm delete category")
      Report("Confirm deletion of this custom category and its own assignments.")
    else
      if Alter("Remove",current) then current=nil;BackToList() end
    end
  end)
  Place(deleteButton,editorPanel,275,-70)
  includesTitle=Label(editorPanel,"INCLUDED CATEGORIES","GameFontNormalSmall",GOLD)
  includeButton=Button(editorPanel,253,"Add included category  v",function()
    dropdown=not dropdown;choicePage=1;M.Refresh()
  end)
  prevChoices=Button(editorPanel,108,"< Previous",function()
    choicePage=math.max(1,choicePage-1);M.Refresh()
  end)
  nextChoices=Button(editorPanel,108,"Next >",function()
    choicePage=choicePage+1;M.Refresh()
  end)
  itemsTitle=Label(editorPanel,"SPECIFIC ITEMS (PERMANENT ITEM IDs)","GameFontNormalSmall",GOLD)
  -- This is intentionally an addon-owned nonsecure button. It is not an
  -- inventory slot, and never calls PickupContainerItem/UseContainerItem.
  -- Only Core can return and verify its known real item cursor.
  dropSlot=CreateFrame("Button",nil,editorPanel,"BackdropTemplate")
  dropSlot:SetSize(39,39)
  dropSlot:RegisterForClicks("LeftButtonUp")
  if ns.SlotArt and ns.SlotArt.Apply then
    ns.SlotArt.Apply(dropSlot)
  else
    local texture=dropSlot:CreateTexture(nil,"BACKGROUND")
    texture:SetAllPoints(dropSlot)
    texture:SetTexture("Interface\\Buttons\\UI-Slot-Background")
  end
  dropSlot:SetScript("OnEnter",function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      GameTooltip:SetText("Assign an item to this category")
      GameTooltip:AddLine("Drag an item from Obsidian Bags into this slot. The item will remain in your inventory.",.74,.85,1,true)
      GameTooltip:Show()
    end
  end)
  dropSlot:SetScript("OnLeave",function(self)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
  end)
  dropHint=Label(editorPanel,"Drop inventory item here","GameFontHighlightSmall",MUTED)
  dropStatus=Label(editorPanel,"Drag an item or paste comma-separated IDs below.","GameFontHighlightSmall",CYAN)
  addIDTitle=Label(editorPanel,"ITEM ID(S)","GameFontHighlightSmall",MUTED)
  itemInput=EditBox(editorPanel,172);itemInput:SetMaxLetters(4096)
  local function AddIDs()
    if not current then return end
    local ok,stats=Alter("AddItemIDs",current,itemInput:GetText())
    if ok then
      itemInput:SetText("")
      if dropStatus then
        dropStatus:SetText("Added "..stats.added.." ID(s); "..stats.existing.." already assigned.")
      end
    end
  end
  addButton=Button(editorPanel,145,"+ Add Item IDs",AddIDs)
  itemInput:SetScript("OnEnterPressed",function(self)
    AddIDs();self:ClearFocus()
  end)
  itemInput:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
  emptyNote=Label(editorPanel,"No individual item IDs assigned yet.","GameFontHighlightSmall",MUTED)
  itemPageLabel=Label(editorPanel,"","GameFontHighlightSmall",MUTED)
  itemPagePrev=Button(editorPanel,106,"< Previous",function()
    itemsPage=math.max(1,itemsPage-1);M.Refresh()
  end)
  itemPageNext=Button(editorPanel,106,"Next >",function()
    itemsPage=itemsPage+1;M.Refresh()
  end)
  local function ReceiveDrop()
    if mode~="editor" or not current or not Registry().IsCustom(current) then return end
    -- Multiple mouse-up/receive callbacks may follow an already-successful
    -- return. An empty or unrelated cursor is not a second drop attempt.
    if not GetCursorInfo then return end
    local cursorOK,kind=pcall(GetCursorInfo)
    if not cursorOK or (issecretvalue and issecretvalue(kind)) or kind~="item" then return end
    if callbacks and callbacks.receiveItemDrop then
      local ok,reason=callbacks.receiveItemDrop(current)
      if not ok and reason and dropStatus then dropStatus:SetText(reason) end
    end
  end
  -- Accept the native drag event and mouse-release orderings. Core makes the
  -- real physical cursor return idempotent if more than one callback fires.
  dropSlot:SetScript("OnReceiveDrag",ReceiveDrop)
  dropSlot:SetScript("OnMouseUp",function(_,button)
    if button=="LeftButton" then ReceiveDrop() end
  end)
  dropSlot:SetScript("OnClick",function(_,button)
    if button=="LeftButton" then ReceiveDrop() end
  end)
  BuildSharingPanel()
  M.Refresh()
end
function M.OpenShare(isExport)
  if not sharePanel then return end
  sharePrevious=(isExport and "editor" or "list")
  shareExportID=isExport and current or nil
  local value=""
  if isExport then
    if not ns.CategorySharing then return end
    local ok,result=ns.CategorySharing.Export(current)
    if not ok then Report(result or "Unable to export category");return end
    value=result
  end
  StopDrag(false)
  mode="share"
  listPanel:Hide();editorPanel:Hide();sharePanel:Show()
  shareInput:SetText(value)
  shareInput:ClearFocus()
  shareTitle:SetText(isExport and "EXPORT CUSTOM CATEGORY" or "IMPORT CUSTOM CATEGORY")
  shareHint:SetText(isExport and "Select the full string, press Ctrl+C, and share it." or
    "Paste a VBLCAT2 or earlier VBLCAT1 string, then choose Import category.")
  shareHighlightButton:SetShown(isExport)
  shareImportButton:SetShown(not isExport)
  shareStatus:SetText(isExport and (tostring(#value).." characters. No inventory data or settings passwords are included.") or
    "Imports create new categories; existing categories are never overwritten.")
  page:SetHeight(370)
  local scroll=page and page:GetParent()
  if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
end
function M.Refresh()
  if not page or not Registry() then return end
  if mode=="editor" then RefreshEditor()
  elseif mode=="list" then RefreshList() end
end
function M.Show()
  if not page then return end
  confirmReset=false;confirmDelete=false;ignoreClick=false;dropdown=false
  if resetButton then resetButton.text:SetText("Reset default categories") end
  BackToList()
end

-- Called by Core on mouse release, even when the inventory window is
-- behind the settings frame. Geometry is expressed in UIParent coordinates.
function M.DropTargetAt(x,y)
  if mode~="editor" or not current or not Registry().IsCustom(current) or
     not page or not page:IsShown() or not editorPanel or
     not editorPanel:IsShown() or not dropSlot or not dropSlot:IsShown() then return nil end
  local l,r,t,b=dropSlot:GetLeft(),dropSlot:GetRight(),dropSlot:GetTop(),dropSlot:GetBottom()
  if not (l and r and t and b and x and y and x>=l and x<=r and y<=t and y>=b) then
    return nil
  end
  -- A scrolled-off item tile must never become an invisible drop target.
  local viewport=page:GetParent()
  if viewport and viewport~=UIParent then
    if not viewport:IsShown() then return nil end
    local vl,vr,vt,vb=viewport:GetLeft(),viewport:GetRight(),viewport:GetTop(),viewport:GetBottom()
    if vl and vr and vt and vb and not (x>=vl and x<=vr and y<=vt and y>=vb) then
      return nil
    end
  end
  return current
end

-- Called only AFTER Core has returned its tracked real cursor and verified
-- original bag, physical slot, item identity, variant, count, and GUID.
function M.CommitVerifiedItem(targetID,itemID)
  if targetID~=current or mode~="editor" or not page or not page:IsShown() or
      not Registry().IsCustom(targetID) or type(itemID)~="number" then
    return false,"The category editor changed before the item returned"
  end
  local ok,reason=Registry().SetItem(targetID,itemID,true)
  if not ok then return false,reason end
  if dropStatus then dropStatus:SetText("Assigned item "..tostring(itemID).." successfully.") end
  Changed()
  return true
end
