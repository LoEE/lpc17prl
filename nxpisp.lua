local D = require'util'
local T = require'thread'
local B = require'binary'
local Object = require'oo'
local uu = require'uuenc'
local buffer = require'buffer'


local NXPisp = Object:inherit{
  uart = 'uart1',
  cclk = 12000,
  verbose = 0,
}

local LEDG  = 0x12
local LEDY  = 0x1a
local RESET = 0x09
local BOOT  = 0x0a
local TxD   = 0x17
local RxD   = 0x16

function NXPisp.init (self, sepack)
  self.sepack = sepack
  self.readbuf = buffer.new()
end


--
-- Physical layer
--
function NXPisp.gpio (self, data)
  return string.byte(self.sepack:xchg('gpio', data), 1, -1)
end

function NXPisp.setup_uart (self, ...)
  self.sepack:setup_uart (self.uart, ...)
end

function NXPisp.connect (self)
  D.blue'÷ connect'()
  local reset, boot = self:gpio{
    'O', RESET, '0', RESET,
    'O', BOOT,  '0', BOOT,
    '1', LEDY, '1', LEDG,
    'd', 0,
    'I', RESET, 'r', RESET, 'O', RESET,
    'I', BOOT, 'r', BOOT, 'O', BOOT,
    'P', TxD, 'P', RxD,
  }
  assert (reset == 0, 'could not force RESET to 0')
  assert (boot == 0, 'could not force BOOT to 0')
  self:setup_uart(115200)
end

function NXPisp.disconnect (self)
  D.blue'÷ disconnect'()
  self:gpio{
    'S', 'z', 'I', BOOT, 'd', 10, 'I', RESET,
    'S', 'u', 'I', TxD,
    '0', LEDY
  }
end

function NXPisp.reset (self, bootloader)
  D.blue('÷ reset, run '..(bootloader and 'bootloader' or 'user code'))()
  if bootloader then bootloader = '0' else bootloader = '1' end
  local reset1, boot, reset2 = self:gpio{
    '0', RESET, 'd', 20,
    'I', RESET, 'r', RESET, 'O', RESET,
    bootloader, BOOT, 'd', 20,
    'I', BOOT, 'r', BOOT, 'O', BOOT,
    '1', RESET, 'd', 1, 
    'I', RESET, 'r', RESET, 'O', RESET,
  }
  assert (reset1 == 0, 'could not force RESET to 0')
  assert (tostring(boot) == bootloader, 'could not force BOOT to '..bootloader)
  assert (reset2 == 1, 'could not force RESET to 1')
end


--
-- Line based protocol
--
function NXPisp.wr (self, data)
  if (self.verbose > 0) then D.blue'»'(data) end
  self.sepack:write(self.uart, data)
end

function NXPisp.wrln (self, data)
  data = tostring(data)
  self:wr(data .. '\r')
  local r = self:rdln'\r'
  if r ~= data then
    error(string.format('invalid command echo: %q', r), 2)
  end
end

function NXPisp.rdln (self, ending)
  ending = ending or '\r\n'
  local uart1 = self.sepack:mbox(self.uart)
  while true do
    local line = self.readbuf:readuntil(ending, #ending)
    if line then
      local rest = self.readbuf:read()
      if rest then uart1:putback(rest) end
      if self.verbose > 0 then D.cyan'«'(line .. ending) end
      return line
    end
    T.recv{
      [uart1] = function (d) self.readbuf:write (d) end,
      [T.Timeout:new(2)] = function () error ('read timeout', 5) end,
    }
  end
end

function NXPisp.expect (self, ex, err)
  local d = self:rdln()
  if d ~= ex then
    msg = string.format('got %q, expected %q', d, ex)
    if err then msg = err .. ': ' .. msg end
    error(msg, 2)
  end
end


--
-- uuencoded binary data transfer protocol
--
NXPisp.uu_line_size = 45
NXPisp.uu_block_size = 20 * NXPisp.uu_line_size

function NXPisp.uuchecksum (self, data, s, e)
  s = s or 1
  if not e or e > #data then e = #data end
  local sum = 0
  for i=s,e do
    sum = sum + string.byte (data, i, i)
  end
  return sum
end

function NXPisp.uusend (self, data, s, e)
  for bs,be in B.allslices (s, e, NXPisp.uu_block_size) do
    local sum = 0
    local lines = {}
    for ls,le in B.allslices (bs, be, NXPisp.uu_line_size) do
      local line = uu.encode_line(data, ls, le, 0xff)
      self:wr(line .. '\r')
      lines[#lines+1] = line
      sum = sum + self:uuchecksum (data, ls, le)
    end
    for i,line in ipairs(lines) do
      local r = self:rdln'\r'
      if line ~= r then
        error(string.format('invalid uuencoded data echo: %q', r), 2)
      end
    end
    self:wrln(tostring(sum))
    self:expect('OK', string.format("checksum error while writing %d bytes", be-bs+1))
  end
end

function NXPisp.uurecv (self, s, e)
  data = {}
  for bs,be in B.allslices (s, e, NXPisp.uu_block_size) do
    local sum = 0
    local lines = {}
    for ls,le in B.allslices (bs, be, NXPisp.uu_line_size) do
      lines[#lines+1] = self:rdln()
    end
    local b = {}
    for i,line in ipairs(lines) do
      b[#b+1] = uu.decode_line (line)
    end
    b = table.concat(b)
    local sum = self:uuchecksum (b)
    local rsum = tonumber(self:rdln())
    if sum ~= rsum then error (string.format ('invalid data checksum: %d (expected: %d)', rsum, sum), 1) end
    self:wrln('OK')
    data[#data+1] = b
  end
  return table.concat(data)
end


--
-- ISP bootloader commands
--
function NXPisp.synchronize (self)
  self:wr'?'
  self:expect'Synchronized'
  self:wrln'Synchronized'
  self:expect'OK'
  self:wrln(self.cclk)
  self:expect'OK'
end

NXPisp.status_codes = {
  [0] = "CMD_SUCCESS", "INVALID_COMMAND", "SRC_ADDR_ERROR", "DST_ADDR_ERROR",
  "SRC_ADDR_NOT_MAPPED", "DST_ADDR_NOT_MAPPED", "COUNT_ERROR", "INVALID_SECTOR",
  "SECTOR_NOT_BLANK", "SECTOR_NOT_PREPARED_FOR_WRITE_OPERATION", "COMPARE_ERROR",
  "BUSY", "PARAM_ERROR", "ADDR_ERROR", "ADDR_NOT_MAPPED", "CMD_LOCKED", "INVALID_CODE",
  "INVALID_BAUD_RATE", "INVALID_STOP_BIT", "CODE_READ_PROTECTION_ENABLED",
}

NXPisp.devices = require'devices'

function NXPisp.read_status (self, dont_panic)
  local code = tonumber(self:rdln())
  local status = self.status_codes[code] or ('unknown-status-code-' .. code)
  if not dont_panic and status ~= 'CMD_SUCCESS' then
    error ('isp error: ' .. status, 2)
  end
  return status
end

function NXPisp.cmd (self, cmd, dont_panic)
  self:wrln(cmd)
  return self:read_status(dont_panic)
end



function NXPisp.read_part_id (self)
  self:cmd'J'
  return tonumber(self:rdln())
end

function NXPisp.read_boot_code_version (self)
  self:cmd'K'
  local major = self:rdln()
  local minor = self:rdln()
  return string.format ("%s.%s", major, minor)
end

function NXPisp.read_uid (self)
  self:cmd'N'
  local r = {}
  for i=1,4 do
    r[5 - i] = string.format("%08x", tonumber(self:rdln()))
  end
  return table.concat (r, ':')
end

function NXPisp.unlock (self)
  self:cmd'U 23130'
end

function NXPisp.prepare_sectors (self, s, e)
  s = self.part:addr2sector(s)
  e = self.part:addr2sector(e)
  if e == 0 then e = 1 end -- workaround for a silicon/ROM bug (it is impossible to erase only sector 0)
  self:cmd(string.format("P %d %d", s, e))
end

function NXPisp.erase_sectors (self, s, e)
  self:prepare_sectors(s, e)
  s = self.part:addr2sector(s)
  e = self.part:addr2sector(e)
  if e == 0 then e = 1 end -- workaround for a silicon/ROM bug (it is impossible to erase only sector 0)
  self:cmd(string.format("E %d %d", s, e))
end

function NXPisp.sector_blank_check (self, first, last)
  local status = self:cmd(string.format("I %d %d", first, last), true)
  if status == 'CMD_SUCCESS' then
    return true
  elseif status == 'SECTOR_NOT_BLANK' then
    local addr = tonumber(self:rdln())
    local val  = tonumber(self:rdln())
    D(string.format('found a non-blank value: %02x at: %08x', addr, val))()
    return false
  else
    error ('isp error: ' .. status, 2)
  end
end

function NXPisp.write_to_ram (self, dest, data, s, e)
  s = s or 1
  if not e or e > #data then e = #data end
  if dest % 4 ~= 0 then error("address not divisible by 4", 2) end
  local len = e+1 - s
  if len % 4 ~= 0 then error("length not divisible by 4", 2) end
  self:cmd(string.format("W %d %d", dest, len))
  self:uusend(data, s, e)
end

function NXPisp.copy_ram_to_flash (self, dest, s, e)
  if dest % 256 ~= 0 then error("destination address not divisible by 256", 2) end
  if s % 4 ~= 0 then error("source address not divisible by 4", 2) end
  local len = e+1 - s
  if len ~= 256 and len ~= 512 and len ~= 1024 and len ~= 4096 then
    error("length is not 256, 512, 1024 or 4096", 2)
  end
  self:prepare_sectors(dest, len)
  self:cmd(string.format("C %d %d %d", dest, s, len))
end

function NXPisp.run (self, addr)
  self:cmd(string.format("G %d T", addr))
end

function NXPisp.read_memory (self, s, e)
  if s % 4 ~= 0 then error("start address not divisible by 4", 2) end
  local len = e+1 - s
  if len % 4 ~= 0 then error("length not divisible by 4", 2) end
  self:cmd(string.format("R %d %d", s, len))
  return self:uurecv (s, e)
end

local function block_empty (block)
  return string.match (block, "^\255*$") ~= nil
end

function NXPisp.write_sector (self, image, sector)
  local s = self.part:sector_start_addr (sector)
  local e = s + self.part:sector_size (sector) - 1
  local bsize = 4096
  if self.part:free_ram_size () < bsize then bsize = 1024 end
  local freeram = self.part:free_ram_start()
  for bs,be in B.allslices (s, e, bsize) do
    local block = string.sub(image, bs+1, be+1)
    if #block % 4 ~= 0 then block = block .. string.rep('\0', 4 - #block % 4) end
    if not block_empty(block) then
      D('.','nonl')()
      self:write_to_ram (freeram, block)
      self:copy_ram_to_flash (bs, freeram, freeram+bsize-1)
    end
  end
end


--
-- High-level API
--
function NXPisp.run_code (self, name)
  local temp_addr = self.part:free_ram_start()
  local code = assert(io.open (_G.program_path .. 'native-code/' ..  self.part.family .. '/' .. name .. '.bin', 'rb'), "unable to load native code: " .. name):read('*a')
  self:write_to_ram (temp_addr, code)
  self:run (temp_addr)
end

function NXPisp.disable_boot_memory_map (self)
  self:run_code'map_boot'
end

function NXPisp.set_max_baudrate (self)
  self:run_code'baud_max'
  self:setup_uart(250000)
end

function NXPisp.burn (self, dest, image)
  local len = #image
  if dest + len > self.part.flash * 1024 then
    error(string.format ("image to large for this device (%d bytes)", dest+len), 2)
  end
  local last_sector = self.part:addr2sector(dest + len)
  self:erase_sectors(0, last_sector)
  ---[[
  for sector=1,last_sector do self:write_sector (image, sector) end
  self:write_sector (image, 0)
  D''()
  --]]
end

function NXPisp.start (self)
  self:connect()
  local ok, err
  for i=1,10 do
    self:reset(true)
    ok, err = T.pcall(function () self:synchronize() end)
    if ok then break end
  end
  if not ok then error (err) end
  local part_id = self:read_part_id()
  self.part = self.devices[part_id]
  if not self.part then
    error("unknown part id: " .. part_id)
  end
  self:unlock()
  self:disable_boot_memory_map()
  self:set_max_baudrate()
end

function NXPisp.stop (self)
  self:reset(false)
  self:disconnect()
end

return NXPisp
