local Emitter = require('core').Emitter
local childprocess = require('childprocess')
local fs = require('fs')
local setTimeout = require('timer').setTimeout

local Traceroute = require('../lib/traceroute').Traceroute
local utils = require('../lib/utils')

local exports = {}

-- Mock childprocess
function getEmitter(filePath)
  local data = fs.readFileSync(filePath)

  function get()
    local emitter = Emitter:extend()

    local split = utils.split(data, '[^\n]+')
    local util = require('utils')

    emitter.stdout = Emitter:new()
    emitter.stderr = Emitter:new()

    setTimeout(500, function()
      for index, line in ipairs(split) do
        emitter.stdout:emit('data', line .. '\n')
      end

      emitter:emit('exit', 0)
    end)

    return emitter
  end

  return get
end

exports.getEmitter = getEmitter

exports['test_parsing_dont_resolve_ips'] = function(test, asserts)
  local hopCount = 0

  local tr = Traceroute:new('www.arnes.si', {resolveIps = false})
  Traceroute._spawn = exports.getEmitter('./tests/fixtures/output_without_hostnames.txt')
  tr:traceroute()

  tr:on('hop', function(hop)
    hopCount = hopCount + 1

    if hopCount == 1 then
      asserts.equals(hop['ip'], '192.168.1.1')
      asserts.dequals(hop['rtts'], {0.496, 0.925, 1.138})
    end
  end)

  tr:on('end', function()
    asserts.equals(hopCount, 22)
    test.done()
  end)
end

exports['test_parsing_resolve_ips'] = function(test, asserts)
  local hopCount = 0

  local tr = Traceroute:new('www.arnes.si', {resolveIps = true})
  Traceroute._spawn = exports.getEmitter('./tests/fixtures/normal_output.txt')
  tr:traceroute()

  tr:on('hop', function(hop)
    hopCount = hopCount + 1

    if hopCount == 3 then
      asserts.equals(hop['host'], 'te-4-1-ur01.sffolsom.ca.sfba.comcast.net')
      asserts.equals(hop['ip'], '68.85.100.121')
      asserts.dequals(hop['rtts'], {16.848, 16.929, nil})
    end
  end)

  tr:on('end', function()
    asserts.equals(hopCount, 22)
    test.done()
  end)
end

return exports
