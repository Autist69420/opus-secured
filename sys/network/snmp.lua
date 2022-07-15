local Event  = require('event')
local GPS    = require('gps')
local Socket = require('socket')
local Util   = require('util')

-- move this into gps api
local gpsRequested
local gpsLastPoint
local gpsLastRequestTime

local function snmpConnection(socket)

  while true do
    local msg = socket:read()
    if not msg then
      break
    end

    if msg.type == 'reboot' then
      os.reboot()  

    elseif msg.type == 'shutdown' then
      os.shutdown()

    elseif msg.type == 'ping' then
      socket:write('pong')

    elseif msg.type == 'script' then
      local fn, msg = loadstring(msg.args, 'script')
      if fn then
        multishell.openTab({
          fn = fn,
          env = getfenv(1),
          title = 'script',
        })
      else
        printError(msg)
      end

    elseif msg.type == 'scriptEx' then
      local s, m = pcall(function()
        local env = setmetatable(Util.shallowCopy(getfenv(1)), { __index = _G })
        local fn, m = load(msg.args, 'script', nil, env)
        if not fn then
          error(m)
        end
        return { fn() }
      end)
      if s then
        socket:write(m)
      else
        socket:write({ s, m })
      end

    elseif msg.type == 'gps' then
      if gpsRequested then
        repeat
          os.sleep(0)
        until not gpsRequested
      end

      if gpsLastPoint and os.clock() - gpsLastRequestTime < .5 then
        socket:write(gpsLastPoint)
      else

        gpsRequested = true
        local pt = GPS.getPoint(2)
        if pt then
          socket:write(pt)
        else
          print('snmp: Unable to get GPS point')
        end
        gpsRequested = false
        gpsLastPoint = pt
        if pt then
          gpsLastRequestTime = os.clock()
        end
      end

    elseif msg.type == 'info' then
      local info = {
        id = os.getComputerID(),
        label = os.getComputerLabel(),
        uptime = math.floor(os.clock()),
      }
      if turtle then
        info.fuel = turtle.getFuelLevel()
        info.status = turtle.status
      end
      socket:write(info)
    end
  end
end

Event.addRoutine(function()

  print('snmp: listening on port 161')

  while true do
    local socket = Socket.server(161)

    Event.addRoutine(function()
      print('snmp: connection from ' .. socket.dhost)
      snmpConnection(socket)
      print('snmp: closing connection to ' .. socket.dhost)
    end)
  end
end)

device.wireless_modem.open(999)
print('discovery: listening on port 999')

Event.on('modem_message', function(e, s, sport, id, info, distance)

  if sport == 999 and tonumber(id) and type(info) == 'table' then
    if not network[id] then
      network[id] = { }
    end
    Util.merge(network[id], info)
    network[id].distance = distance
    network[id].timestamp = os.clock()

    if not network[id].active then
      network[id].active = true
      os.queueEvent('network_attach', network[id])
    end
  end
end)

local info = {
  id = os.getComputerID()
}
local infoTimer = os.clock()

local function sendInfo()

  if os.clock() - infoTimer >= 1 then -- don't flood
    infoTimer = os.clock()
    info.label = "REDACTED"
    info.uptime = -913
    if turtle then
      info.fuel = turtle.getFuelLevel()
      info.status = turtle.status
      info.point = turtle.point
      info.inventory = turtle.getInventory()
      info.slotIndex = turtle.getSelectedSlot()
    end
    device.wireless_modem.transmit(999, os.getComputerID(), info)
  end
end

-- every 10 seconds, send out this computer's info
Event.onInterval(10, function()
  sendInfo()
  for _,c in pairs(_G.network) do
    local elapsed = os.clock()-c.timestamp
    if c.active and elapsed > 15 then
      c.active = false
      os.queueEvent('network_detach', c)
    end
  end
end)

Event.on('turtle_response', function()
  if turtle.status ~= info.status or
     turtle.fuel ~= info.fuel then
    sendInfo()
  end
end)
