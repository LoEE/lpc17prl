local D = require'util'
local T = require'thread'
local B = require'binary'
local Object = require'oo'
local uu = require'uuenc'
local buffer = require'buffer'


local NXPisp = Object:inherit{
  cclk = 12000,
  verbose = 1,
  read_timeout = 5,
  use_maxbaud = true,
  use_bootpin = true,
  endl = '\r\n',
}

function NXPisp.init (self, sepack)
  self.sepack = sepack
  self.uart = sepack.channels.uart
  self.gpio = sepack.channels.gpio
  self.readbuf = buffer.new()
  self.gpio:alias('IO7', 'NXP_BOOT2')
  self.gpio:alias('IO5', 'NXP_BOOT3')
  self.gpio:seq():
    input'NXP_RESET':
    input'NXP_BOOT':
    input'NXP_BOOT2':
    input'NXP_BOOT3':
    peripheral'RXD':
    input'TXD':
    run()
end


--
-- Physical layer
--
function NXPisp.connect (self)
  do
    local seq = self.gpio:seq():
      output'NXP_RESET':
      lo'NXP_RESET'
    if self.use_bootpin then
      seq:
        output'NXP_BOOT':
        lo'NXP_BOOT':
        output'NXP_BOOT2':
        lo'NXP_BOOT2':
        output'NXP_BOOT3':
        lo'NXP_BOOT3'
    end
    seq:
      hi'LED':
      delay(1):
      peripheral'RXD':
      peripheral('TXD', 'pull-none'):
      run()
  end
  self.uart:setup(115200)
  self.uart:settimeout('tx', 9)
  if self.verbose > 0 then D.blue'÷ connected'() end
end

function NXPisp.disconnect (self)
  self.gpio:seq():
    float'NXP_BOOT':
    float'NXP_BOOT2':
    float'NXP_BOOT3':
    input'TXD':
    lo'LED':
    delay(10):
    float'NXP_RESET':
    run()
  if self.verbose > 0 then D.blue'÷ disconnected'() end
end

function NXPisp.reset (self, bootloader)
  if self.verbose > 0 then D.blue('÷ reset, running '..(bootloader and 'bootloader' or 'user code'))() end
  if bootloader then
    self.gpio:seq():
      lo'NXP_RESET':
      delay(20):
      write('NXP_BOOT', false):
      write('NXP_BOOT2', false):
      write('NXP_BOOT3', false):
      delay(20):
      hi'NXP_RESET':
      delay(20):
      run()
  else
    self.gpio:seq():
      lo'NXP_RESET':
      delay(20):
      write('NXP_BOOT', true):
      write('NXP_BOOT2', true):
      write('NXP_BOOT3', true):
      delay(20):
      float('NXP_BOOT'):
      float('NXP_BOOT2'):
      float('NXP_BOOT3'):
      input('TXD'):
      delay(10):
      hi'NXP_RESET':
      run()
  end
end


--
-- Line based protocol
--
function NXPisp.wr (self, data)
  if self.verbose > 1 then D.blue'»'(data) end
  self.uart:write(data)
end

function NXPisp.rd (self)
  local data = self.uart.inbox:recv()
  if self.verbose > 1 then D.cyan'«'(data) end
  return data
end


function NXPisp.wrln (self, data)
  data = tostring(data)
  self:wr(data .. self.endl)
  local r = self:rdln(self.endl)
  if r ~= data then
    error(string.format('invalid command echo: %q', r), 0)
  end
end

function NXPisp.rdln (self, ending)
  ending = ending or '\r\n'
  local uart = self.uart.inbox
  while true do
    local line = self.readbuf:readuntil(ending, #ending)
    if line then
      local rest = self.readbuf:read()
      if rest then uart:putback(rest) end
      if self.verbose > 1 then D.cyan'«'(line .. ending) end
      return line
    end
    T.recv{
      [uart] = function (d) self.readbuf:write (d) end,
      [T.Timeout:new(self.read_timeout)] = function ()
        error (string.format('read timeout after: %q', self.readbuf:peek() or ''), 0)
      end,
    }
  end
end

function NXPisp.expect (self, ex, err)
  local d = self:rdln()
  local s,e = string.find(d, ex)
  if s ~= 1 or e ~= #d then
    local msg = string.format('got %q, expected %q', d, ex)
    if err then msg = err..': '..msg end
    error(msg, 0)
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
        error(string.format('invalid uuencoded data echo: %q', r), 0)
      end
    end
    self:wrln(tostring(sum))
    self:expect('OK', string.format("checksum error while writing %d bytes", be-bs+1))
  end
end

function NXPisp.uurecv (self, s, e)
  local data = {}
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
    if sum ~= rsum then error (string.format ('invalid data checksum: %d (expected: %d)', rsum, sum), 0) end
    self:wrln('OK')
    data[#data+1] = b
  end
  return table.concat(data)
end


--
-- binary data transmision
--
function NXPisp.binsend (self, data, s, e)
  if self.part.uuencode then
    self:uusend(data, s, e)
  else
    for bs,be in B.allslices (s, e, NXPisp.uu_block_size) do
      local block = string.sub(data, bs, be)
      self:wr(block)
      local reply = self:rd()
      if reply ~= block then
        error (string.format ('invalid binary echo: %q', reply), 0)
      end
    end
  end
end

function NXPisp.binrecv (self, s, e)
  if self.part.uuencode then
    return self:uurecv(s, e)
  else
    local n = e-s+1
    local data = {}
    while n > 0 do
      local block = self:rd()
      data[#data+1] = block
      n = n - #block
    end
    return table.concat(data)
  end
end

--
-- ISP bootloader commands
--
function NXPisp.synchronize (self)
  self:wr'?'
  self:expect'.*Synchronized'
  self:wr'Synchronized\r\n'
  local sync = self:rdln()
  if sync == 'Synchronized\rOK' then
    self.endl = '\r'
  elseif sync == 'Synchronized' then
    self:expect'OK'
  end
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
    error ('isp error: ' .. status, 0)
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

function NXPisp.prepare_region (self, s, e)
  s = self.part:addr2sector(s)
  e = self.part:addr2sector(e)
  if e == 0 then e = 1 end -- workaround for a silicon/ROM bug (it is impossible to erase only sector 0)
  self:cmd(string.format("P %d %d", s, e))
end

function NXPisp.erase_region (self, s, e)
  self:prepare_region(s, e)
  s = self.part:addr2sector(s)
  e = self.part:addr2sector(e)
  if e == 0 then e = 1 end -- workaround for a silicon/ROM bug (it is impossible to erase only sector 0)
  self:cmd(string.format("E %d %d", s, e))
end

function NXPisp.blank_check_region (self, s, e)
  s = self.part:addr2sector(s)
  e = self.part:addr2sector(e)
  local status = self:cmd(string.format("I %d %d", s, e), true)
  if status == 'CMD_SUCCESS' then
    return true
  elseif status == 'SECTOR_NOT_BLANK' then
    local addr = tonumber(self:rdln())
    local val  = tonumber(self:rdln())
    return nil, addr, val
  else
    error ('isp error: ' .. status, 0)
  end
end

function NXPisp.write_to_ram (self, dest, data, s, e)
  s = s or 1
  if not e or e > #data then e = #data end
  if dest % 4 ~= 0 then error("address not divisible by 4", 2) end
  local len = e+1 - s
  if len % 4 ~= 0 then error("length not divisible by 4", 2) end
  self:cmd(string.format("W %d %d", dest, len))
  self:binsend(data, s, e)
end

function NXPisp.copy_ram_to_flash (self, dest, s, e)
  if dest % 256 ~= 0 then error("destination address not divisible by 256", 2) end
  if s % 4 ~= 0 then error("source address not divisible by 4", 2) end
  local len = e+1 - s
  if len ~= 256 and len ~= 512 and len ~= 1024 and len ~= 4096 then
    error("length is not 256, 512, 1024 or 4096", 2)
  end
  self:prepare_region(dest, dest+len-1)
  self:cmd(string.format("C %d %d %d", dest, s, len))
end

function NXPisp.run (self, addr)
  self:cmd(string.format("G %d T", addr))
end

function NXPisp.read_memory (self, s, e)
  local origlen = e+1 - s
  local eoff = -(e+1) % 4
  local e = e+eoff
  local len = e+1 - s
  self:cmd(string.format("R %d %d", s, len))
  return self:binrecv(s, e):sub(1, origlen)
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
  local path = os.program_path .. '/native-code/' ..  self.part.family .. '/' .. name .. '.bin'
  local f, err = io.open (path, 'rb')
  if not f then error(path..": unable to load native code: "..err, 0) end
  local code = f:read('*a')
  f:close()
  if self.verbose > 1 then D.blue'÷ running code:'(D.unq(string.format('%s (%d bytes loaded at 0x%08x)', name, #code, temp_addr))) end
  if self.verbose > 2 then D.cyan''(D.hex(code)) end
  self:write_to_ram (temp_addr, code)
  self:run (temp_addr)
end

function NXPisp.disable_boot_memory_map (self)
  self:run_code'map_normal'
end

function NXPisp.set_max_baudrate (self)
  self:run_code'baud_max'
  self.uart:setup(750000)
end

function NXPisp.read_flash (self)
  return self:read_memory(0, self.part.flash * 1024 - 1)
end

function NXPisp.blank_check (self)
  return self:blank_check_region(0, self.part.flash * 1024 - 1)
end

function NXPisp.erase (self)
  self:erase_region(0, self.part.flash * 1024 - 1)
end

local function statusbar(i, max, suffix)
  io.stderr:write("\r"..D.color'blue'.."["..string.rep(".", i)..string.rep(" ", max - i).."]"..(suffix or '')) io.stderr:flush()
end

function NXPisp.burn (self, dest, image)
  local len = #image
  if dest + len > self.part.flash * 1024 then
    error(string.format ("image to large for this device (%d bytes)", dest+len), 0)
  end
  if not self.noerase then
    self:erase_region(0, dest + len - 1)
  end
  local last_sector = self.part:addr2sector(dest + len)
  statusbar(0, last_sector + 1)
  for sector=1,last_sector do self:write_sector (image, sector) statusbar(sector - 1, last_sector + 1) end
  self:write_sector (image, 0) statusbar(last_sector + 1, last_sector + 1, "\n")
end

function NXPisp.start (self, clean)
  self:connect()
  local ok, err
  for i=1,10 do
    self:reset(true)
    self.read_timeout = .2
    ok, err = T.pcall(function () self:synchronize() end)
    if ok then break end
    if self.verbose > 0 then D.red('synchronization failed: '..err)() end
  end
  self.read_timeout = nil
  if not ok then error('synchronization failed: giving up after 10 retries', 0) end
  local part_id = self:read_part_id()
  local part = self.devices[part_id]
  if not part then
    error("unknown part id: " .. part_id, 0)
  end
  if self.verbose > 0 then D.green('Found '..part.name..' with '..part.flash .. 'kB flash and '..part.ram..'kB RAM in '..part.package)() end
  self.part = part
  self:unlock()
  if clean then self:erase() end 
  self:disable_boot_memory_map()
  if self.use_maxbaud then self:set_max_baudrate() end
end

function NXPisp.stop (self)
  self:reset(false)
  self:disconnect()
end

return NXPisp
