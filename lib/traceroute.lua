local Emitter = require('core').Emitter
local Error = require('core').Error
local table = require('table')
local childprocess = require('childprocess')
local net = require('net')

local LineEmitter = require('line-emitter').LineEmitter

local split = require('./utils').split

local exports = {}

local Traceroute = Emitter:extend()

function Traceroute:initialize(target, options)
  options = options and options or {}
  self._target = target
  self._options = options
  self._packetLen = options['packetLen'] and options['packetLen'] or 60
  self._maxTtl = options['maxTtl'] and options['maxTtl'] or 30
  self._waitTime = options['waitTime'] and options['waitTime'] or 5

  if net.isIPv4(target) == 4 then
    self._addressType = 'ipv4'
  elseif net.isIPv6(target) == 6 then
    self._addressType = 'ipv6'
  end
end

-- Return an EventEmitter instance which emits 'hop' events for every hop
function Traceroute:traceroute()
  process.nextTick(function()
    local emitter = self:_run(self._target)

    emitter:on('end', function()
      self:emit('end')
    end)

    emitter:on('hop', function(hop)
      self:emit('hop', hop)
    end)

    emitter:on('error', function(err)
      self:emit('error', err)
    end)
  end)
end

function Traceroute:_spawn(cmd, args)
  local child = childprocess.spawn('traceroute', args)
  return child
end

function Traceroute:_run(target)
  local args = {}

  if self._addressType == 'ipv4' then
    table.insert(args, '-4')
  else
    table.insert(args, '-6')
  end

  table.insert(args, '-n')
  table.insert(args, '-m')
  table.insert(args, self._maxTtl)
  table.insert(args, '-w')
  table.insert(args, self._waitTime)
  table.insert(args, target)
  table.insert(args, self._packetLen)

  local child = self:_spawn('traceroute', args)
  local lineEmitter = LineEmitter:new()
  local emitter = Emitter:new()
  local stderrBuffer = ''

  lineEmitter:on('data', function(line)
    local hops = self:_parseLine(line)
    local hop

    if not hops then
      return
    end

    for i=1, #hops do
      hop = hops[i]
      emitter:emit('hop', hop)
    end
  end)

  child.stdout:on('data', function(chunk)
    lineEmitter:write(chunk)
  end)

  child.stderr:on('data', function(chunk)
    stderrBuffer = stderrBuffer .. chunk
  end)

  child:on('exit', function(code)
    local err

    if code == 0 then
      process.nextTick(function()
        emitter:emit('end')
      end)
    else
      err = Error:new('Error: ' .. stderrBuffer)

      process.nextTick(function()
        emitter:emit('error', err)
      end)
    end
  end)

  return emitter
end

function Traceroute:_parseLine(line)
  local result, host, ip, hopsStart, hopNumber, splitLine, value, dotCount,
        lastIndex, item, i;

  result = {}
  item = {}
  hopsStart = 2

  -- Skip first line
  if line:find('traceroute to') or not line then
    return false
  end

  -- for now just ignore those
  line = line:gsub('[!XHNP]', '')

  local splitLine = split(line, '[^%s]+')

  hopNumber = tonumber(splitLine[1])


  i = hopsStart -- hops start at index 2
  while i < #splitLine do
    value = splitLine[i]
    dotCount = #split(value, '[^%.]+')

    if (self:_isAddress(value, self._addressType)) or (value == '*' and i == hopsStart) then
      if i > hopsStart then
        -- Insert old item
        table.insert(result, item)
      end

      item = {}
      item['ip'] = value
      item['number'] = hopNumber
      item['rtts'] = {}
    elseif value ~= 'ms' then
      value = tonumber(value)
      table.insert(item['rtts'], value)
    end

    i = i + 1
  end

  table.insert(result, item)

  return result
end

function Traceroute:_isAddress(value, family)
  local dotCount

  if family == 'ipv4' then
    dotCount = #split(value, '[^%.]+')
    return dotCount == 4
  elseif family == 'ipv6' then
    return value:find(':')
  else
    error('Invalid family: ' .. family)
  end
end

exports.Traceroute = Traceroute
return exports
