-- v0.0.117: fixed-corner ornamental frame, presentation only.
-- Crop the existing licensed addon artwork rather than replacing it. Keeping
-- corner and edge thickness constant prevents vertically expanded panels from
-- turning their corner orbs into ellipses. Never captures mouse input.
local _, ns = ...
ns.FrameSlices = {}
local S = ns.FrameSlices

function S.Create(parent, texturePath)
  local artwork = {}
  local margin = 80
  local unit = margin / 512
  local parts = {
    -- name, left, right, top, bottom, horizontal anchoring, vertical anchoring
    {0,unit,0,unit, "TOPLEFT"},
    {1-unit,1,0,unit, "TOPRIGHT"},
    {0,unit,1-unit,1, "BOTTOMLEFT"},
    {1-unit,1,1-unit,1, "BOTTOMRIGHT"},
  }
  -- Each corner is its own immutable 80x80 pixel crop.
  for _,p in ipairs(parts) do
    local tile=parent:CreateTexture(nil,"BORDER",nil,4)
    tile:SetTexture(texturePath)
    tile:SetTexCoord(p[1],p[2],p[3],p[4])
    tile:SetSize(margin,margin)
    tile:SetPoint(p[5],parent,p[5],0,0)
    artwork[#artwork+1]=tile
  end
  local top=parent:CreateTexture(nil,"BORDER",nil,4)
  top:SetTexture(texturePath)
  top:SetTexCoord(unit,1-unit,0,unit)
  top:SetPoint("TOPLEFT",parent,"TOPLEFT",margin,0)
  top:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-margin,0)
  top:SetHeight(margin)
  artwork[#artwork+1]=top
  local bottom=parent:CreateTexture(nil,"BORDER",nil,4)
  bottom:SetTexture(texturePath)
  bottom:SetTexCoord(unit,1-unit,1-unit,1)
  bottom:SetPoint("BOTTOMLEFT",parent,"BOTTOMLEFT",margin,0)
  bottom:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",-margin,0)
  bottom:SetHeight(margin)
  artwork[#artwork+1]=bottom
  local left=parent:CreateTexture(nil,"BORDER",nil,4)
  left:SetTexture(texturePath)
  left:SetTexCoord(0,unit,unit,1-unit)
  left:SetPoint("TOPLEFT",parent,"TOPLEFT",0,-margin)
  left:SetPoint("BOTTOMLEFT",parent,"BOTTOMLEFT",0,margin)
  left:SetWidth(margin)
  artwork[#artwork+1]=left
  local right=parent:CreateTexture(nil,"BORDER",nil,4)
  right:SetTexture(texturePath)
  right:SetTexCoord(1-unit,1,unit,1-unit)
  right:SetPoint("TOPRIGHT",parent,"TOPRIGHT",0,-margin)
  right:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",0,margin)
  right:SetWidth(margin)
  artwork[#artwork+1]=right
  local object={parts=artwork}
  function object:SetShown(show)
    for _,tile in ipairs(self.parts) do tile:SetShown(show) end
  end
  return object
end
