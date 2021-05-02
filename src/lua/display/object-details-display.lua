selectedObject = -1

function hideObjectDetails()
  display.objectDetails.enabled = false
  selectedObject = -1
end

function displayObjectDetails()

  local m = input.getmouse()

  local minY = 9

  if (m.Left and m.X >= 0 and m.Y >= 0) then
    for j,obj in ipairs(objects) do
      if (obj.isAlive()) then
        if (m.X >= obj.getRelativeX() - obj.getXHitbox() and m.X <= obj.getRelativeX() + obj.getXHitbox()) then
          if (m.Y > minY and m.Y >= obj.getRelativeY() - obj.topHitbox() and m.Y <= obj.getRelativeY() + obj.bottomHitbox()) then
            display.objectDetails.enabled = true
            selectedObject = j
          end
        end
      end
    end
  end

  if (selectedObject >= 0) then
    local obj = objects[selectedObject]
    if (obj.isAlive()) then

      local nextDetailY = 35

      local function drawDetail(detail)
        draw.text(0, nextDetailY, detail)
        nextDetailY = nextDetailY + 10
      end

      drawDetail('Object ' .. selectedObject - 2)
      drawDetail('Base ' .. string.format('0x%x', obj.getBase()):upper())
      drawDetail('HP ' .. obj.getHp())
      drawDetail('Position ' .. obj.getX() .. ', ' .. obj.getY())
      drawDetail('X HB Loc ' .. string.format('0x%x', obj.getValue(0x28, 2)):upper())
      drawDetail('2E (?) Loc ' .. string.format('0x%x', obj.getValue(0x2E, 2)):upper())

      draw.box(obj.getRelativeX() - obj.getXHitbox(), obj.getRelativeY() - obj.topHitbox(), obj.getXHitbox() * 2, obj.topHitbox() + obj.bottomHitbox(), draw.color.green)
      draw.text(obj.getRelativeX() - 4, obj.getRelativeY() - obj.topHitbox() - 6, selectedObject - 2)
      draw.pixel(obj.getRelativeX(), obj.getRelativeY(), draw.color.green)
    else
      hideObjectDetails()
    end
  end
end