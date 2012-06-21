#!/usr/bin/env usb-lua
local B = require'binary'
local D = require'util'
local T = require'thread'
local Object = require'oo'
local S = require'sepack'
local NXPisp = require'nxpisp'

local repl = require'repl'.start(0)

if #arg < 1 then
  print(string.format([[
  Usage: %s <file-name>
]], arg[0]))
  os.exit(2)
end

local isp
local sepack
local image

local function main ()
  isp:start()
  D.green'Found chip:'(isp.part.name)
  local imgfile = assert(io.open(arg[1], 'rb', "unable to open input file: " .. arg[1]))
  image = imgfile:read('*a')
  repl.ns.image = image
  isp:burn(0, image)
  --isp:run (B.dec32LE (image, 5) - 1)
  --local out = io.open('dump.bin', 'wb')
  --out:write (isp:read_memory(0, 2047))
  --out:close()
  isp:stop()
end

local options = {
  product = "SEPACK-NXP",
  verbose = 1,
  serial = nil,
}
function options.callback (s)
  isp = NXPisp:new(s)
  isp.verbose = 1
  repl.agent:handle(s:mbox'uart', function (data)
    D.green'«'(D.unq(B.bin2hex(data)))
  end)
  repl.ns.isp = isp
  repl.ns.s = s
  repl.execute(main)
end

S.open (options)
