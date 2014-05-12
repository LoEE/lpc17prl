#!/usr/bin/env thb
local B = require'binary'
local D = require'util' D.prepend_timestamps = false D.prepend_thread_names = false
local T = require'thread'
local Object = require'oo'
local NXPisp = require'nxpisp'

local repl = require'repl'

local usage_str = string.format([=[
Usage:
  %s [-vqi] [-O[no-]<option>[=<value>]] [-W|-R|-V <file-name>] [-P|-T|-E|-B|-I|-h]
]=], arg[0])

local help_str = [=[
Flags:
  -v  Verbose (increase verbosity)
  -q  Quiet (decrease verbosity)
  -i  Interactive (do not quit after programming)
  -c  Clean (erase whole flash to disable CRP)

Modes:
  with <file-name>:
  -W  Write flash (default)
  -R  Read flash
  -V  Verify
  without <file-name>:
  -P  Probe for chip ID (default without -i)
  -T  Terminal (default for -i)
  -E  Erase
  -B  Blank check
  -I  Enter ISP mode (use with -i)
  -h  Show this message

Options (<> mark the default):
  hex/<no-hex>
    Output bytes received in interactive mode as hexadecimal numbers.
  baudrate=115200
    The baudrate to switch to after executing user code.
  serial=""
    Sepack serial number (will open the first available sepack
    if empty).
  product="SEPACK-NXP"
    Sepack product name.
  <verify>/no-verify
    Perform verification after programming (only significant with -W).
  <maxbaud>/no-maxbaud
    Switch to 750k baud during ISP.
  <bootpin>/no-bootpin
    Toggle the BOOT pin while resetting to enter ISP mode (otherwise
    BOOT is left in high-Z).
]=]

local all_args = {unpack(arg)}
local function usage()
  D.abort(1, usage_str .. '\nGot: '..D.repr(all_args))
end

local function help()
  D.abort(1, usage_str .. '\n' .. help_str)
end

local opts = {
  verbose = 1,
  interactive = false,
  maxbaud = true,
  hex = false,
  verify = true,
  bootpin = true,
  mode = nil,
  baudrate = 115200,
  serial = "",
  product = "SEPACK-NXP",
}

function parsekeyopt(s)
  local v = true
  local vali = string.find(s, '=', 1, plain)
  if string.startswith(s, 'no-') then
    if vali then
      D.abort(a..': boolean options do not take excplicit values')
    end
    v = false
    s = string.sub(s, 4)
  else
    if vali then
      v = string.sub(s, vali + 1)
      s = string.sub(s, 1, vali - 1)
      v = tonumber(v) or v
    end
  end
  return s, v
end

do
  for o, a in os.getopt(arg, 'qvcihWRVPTEBIO:') do
    if o == 'q' then opts.verbose = opts.verbose - 1
    elseif o == 'v' then opts.verbose = opts.verbose + 1
    elseif o == 'i' then opts.interactive = true
    elseif o == 'c' then opts.clean = true
    elseif o == 'W' then opts.mode = 'write'
    elseif o == 'R' then opts.mode = 'read'
    elseif o == 'V' then opts.mode = 'verify'
    elseif o == 'P' then opts.mode = 'probe'
    elseif o == 'T' then opts.mode = 'terminal'
    elseif o == 'E' then opts.fullerase = true
    elseif o == 'B' then opts.mode = 'blank-check'
    elseif o == 'I' then opts.mode = 'isp'
    elseif o == 'h' then help()
    elseif o == 'O' then
      local a, v = parsekeyopt(a)
      if opts[a] ~= nil then
        if type(opts[a]) ~= type(v) then
          D.abort(1, 'invalid argument type for '..a..' (expected a '..type(opts[a])..'; got '..type(v)..')', 0)
        end
        opts[a] = v
      else
        D.abort(1, 'unknown flag: '..a, 0)
      end
    elseif o == '?' then
      usage()
    end
  end
end

if #arg > 1 then usage() end

opts.fname = arg[1]

if opts.interactive and not opts.fname and not opts.mode then
  opts.mode = 'terminal'
end

if opts.fname and not opts.mode then
  opts.mode = 'write'
end

if not opts.mode then
  opts.mode = 'probe'
end

if opts.verbose > 3 then
  D.blue'opts:'(opts)
end

if opts.mode == 'write' or opts.mode == 'verify' then
  if not opts.fname then
    D.abort(1, "error: no file name given")
  end
  local f, err = io.open(opts.fname, 'rb')
  if not f then D.abort(2, "cannot open input file: "..opts.fname..": "..err) end
  opts.image = f:read('*a')
  f:close()
  repl.ns.image = opts.image
end

if opts.mode == 'read' then
  if not opts.fname then
    opts.fout = io.stdout
  else
    local f, err = io.open(opts.fname, 'wb')
    if not f then D.abort(2, "cannot open output file: "..opts.fname..": "..err) end
    opts.fout = f
  end
end


local uart_handler
if opts.hex then
  function uart_handler (data) D.green'«'(D.unq(B.bin2hex(data))) end
else
  function uart_handler (data) D.green'«'(data) end
end


local isp, sepack

local function verify()
  local image = opts.image
  local data = isp:read_memory(0, #image-1)
  repl.ns.data = data
  if data ~= image then
    local s = 1
    local diffs = 0
    while s < #data and diffs < 10 do
      local e = s
      while e <= #data and string.byte(data, e) ~= string.byte(image, e) do e = e+1 end
      if e > s then
        e = e - 1
        if opts.verbose > 0 then
          local len = e-s+1
          if len > 8 then
            D.red(string.format('%d bytes, starting from 0x%08x:', len, s-1))()
            D.red'  '(D.hex(string.sub(data, s, e)))
            D.red('differ from expected:')()
            D.red'  '(D.hex(string.sub(image, s, e)))
          else
            D.red(string.format('%d bytes, starting from 0x%08x:', len, s-1))(
              B.bin2hex(string.sub(data, s, e)), D.unq'differ from expected:', B.bin2hex(string.sub(image, s, e)))
          end
        end
        diffs = diffs + 1
      end
      s = e + 1
    end
    if diffs > 0 then
      if opts.verbose > 0 then D.red'Verification failed!'() end
      if not opts.interactive then os.exit(3) end
    end
  end
  if opts.verbose > 0 then D.green('Verification succeded!')() end
end

local function blank_check()
  local blank, addr, value = isp:blank_check()
  if not blank then
    if opts.verbose > 0 then D.red(string.format('blank check failed at 0x%08x: 0x%08x', addr, value))() end
    if not opts.interactive then os.exit(3) end
  else
    if opts.verbose > 0 then D.green'Chip is blank!'() end
  end
end


local function main ()
  isp.use_maxbaud = opts.maxbaud
  isp.use_bootpin = opts.bootpin
  isp.verbose = opts.verbose

  if opts.mode ~= 'terminal' then
    isp:start(opts.clean)
    
    if opts.fullerase then
      isp:erase()
      isp.noerase = true
    end

    if opts.mode == 'write' then
      isp:burn(0, opts.image)
      if opts.verify then verify() end
    elseif opts.mode == 'probe' then
      -- nothing
    elseif opts.mode == 'read' then
      local data = isp:read_flash()
      repl.ns.data = data
      opts.fout:write(data)
    elseif opts.mode == 'verify' then
      verify()
    elseif opts.mode == 'blank-check' then
      blank_check()
    end

    if opts.interactive then
      isp.uart:setup(opts.baudrate)
    end

    if opts.mode ~= 'isp' then
      isp:stop()
    end
  end

  if opts.interactive then
    isp.uart:setup(opts.baudrate)
    repl.start(0)
  else
    os.exit(0)
  end
end

local ExtProc = require'extproc'
local Sepack = require'sepack'

if opts.serial == "" then opts.serial = nil end
local extproc_log, sepack_log
if opts.verbose > 2 then
  sepack_log = log:sub'sepack'
  if opts.verbose > 3 then extproc_log = sepack_log:sub'ext' end
end
repl.execute(function ()
  sepack = Sepack:new(ExtProc:newUsb(opts.product, opts.serial, extproc_log), sepack_log)
  sepack.verbose = opts.verbose - 1
  while true do
    local status = sepack.connected:recv()
    if status == true then
      break
    elseif status == false then
      local msg = {opts.product}
      if opts.serial then
        msg[#msg+1] = D.unq("with serial number")
        msg[#msg+1] = opts.serial
      end
      msg[#msg+1] = D.unq('not found')
      D.red'÷'(unpack(msg))
    end
  end
  _G.sepack = sepack
  isp = NXPisp:new(sepack)
  isp.verbose = opts.verbose
  _G.isp = isp
  repl.agent:handle(sepack.channels.uart.inbox, uart_handler)
  local ok, err = T.pcall(main)
  if not ok then D.red'error:'(D.unq(err)) os.exit(2) end
end)
require'loop'.run()
