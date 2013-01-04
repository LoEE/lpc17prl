local Object = require'oo'

local NXPpart = Object:inherit{}

function NXPpart.bootloader_ram (self)
  if self.family == 'lpc13xx' or self.family == 'lpc122x' then
    return 0x260
  elseif self.family == 'lpc17xx' then
    return 0x200
  else
    error ('unknown bootloader ram size for device: ' .. self.name)
  end
end

function NXPpart.free_ram_start (self)
  return 0x10000000 + self:bootloader_ram()
end

function NXPpart.free_ram_size (self)
  -- stack = 256, IAP = 32
  return self.main_ram * 1024 - self:bootloader_ram() - 256 - 32
end

function NXPpart.sector_size (self, s)
  if s < 16 or self.family == 'lpc122x' then
    return 4*1024
  else
    return 32*1024
  end
end

function NXPpart.sector_start_addr (self, s)
  if s < 16 or self.family == 'lpc122x' then
    return s * 4*1024
  else
    return 16 * 4*1024 + (s - 16) * 32*1024
  end
end

function NXPpart.addr2sector (self, addr)
  local sector = math.floor(addr / 4 / 1024)
  if sector < 16 or self.family == 'lpc122x' then
    return sector
  else
    return math.floor ((sector - 16) / 8) + 16
  end
end

local devices = {}

local function add_part (id, family, name, package, flash, ram)
  local main_ram
  if ram == 4 or ram == 8 or ram == 16 then
    main_ram = ram
  elseif ram == 32 or ram == 64 then
    main_ram = ram / 2
  end
  devices[id] = NXPpart:inherit{
    name = name,
    family = family,
    package = package,
    flash = flash,
    ram = ram,
    main_ram = main_ram,
  }
end

-- FIXME: package cannot be determined solely from part-id

-- LPC13xx
add_part (0x2C42502B, 'lpc13xx', 'LPC1311', 'HVQFN33', 8, 4)
add_part (0x1816902B, 'lpc13xx', 'LPC1311/01', 'HVQFN33', 8, 4)
add_part (0x2C40102B, 'lpc13xx', 'LPC1313', 'HVQFN33', 32, 8)
add_part (0x2C40102B, 'lpc13xx', 'LPC1313', 'LQFP48', 32, 8)
add_part (0x1830102B, 'lpc13xx', 'LPC1313/01', 'HVQFN33', 32, 8)
add_part (0x1830102B, 'lpc13xx', 'LPC1313/01', 'LQFP48', 32, 8)
add_part (0x3D01402B, 'lpc13xx', 'LPC1342', 'HVQFN33', 16, 4)
add_part (0x3D00002B, 'lpc13xx', 'LPC1343', 'HVQFN33', 32, 8)
add_part (0x3D00002B, 'lpc13xx', 'LPC1343', 'LQFP48', 32, 8)
-- LPC17xx
add_part (0x26113F37, 'lpc17xx', 'LPC1769', 'LQFP100', 512, 64)
add_part (0x26013F37, 'lpc17xx', 'LPC1768', 'LQFP100', 512, 64)
add_part (0x26013F37, 'lpc17xx', 'LPC1768', 'TFBGA100', 512, 64)
add_part (0x26012837, 'lpc17xx', 'LPC1767', 'LQFP100', 512, 64)
add_part (0x26013F33, 'lpc17xx', 'LPC1766', 'LQFP100', 256, 64)
add_part (0x26013733, 'lpc17xx', 'LPC1765', 'LQFP100', 256, 64)
add_part (0x26011922, 'lpc17xx', 'LPC1764', 'LQFP100', 128, 32)
add_part (0x25113737, 'lpc17xx', 'LPC1759', 'LQFP80', 512, 64)
add_part (0x25013F37, 'lpc17xx', 'LPC1758', 'LQFP80', 512, 64)
add_part (0x25011723, 'lpc17xx', 'LPC1756', 'LQFP80', 256, 32)
add_part (0x25011722, 'lpc17xx', 'LPC1754', 'LQFP80', 128, 32)
add_part (0x25001121, 'lpc17xx', 'LPC1752', 'LQFP80', 64, 16)
add_part (0x25001118, 'lpc17xx', 'LPC1751', 'LQFP80', 32, 8)
add_part (0x25001110, 'lpc17xx', 'LPC1751', 'LQFP80', 32, 8)
-- LPC12xx
add_part (0x3670002B, 'lpc122x', 'LPC12D27-301', 'LQFP100', 128, 8)
add_part (0x3670002B, 'lpc122x', 'LPC1227-301',  'LQFP64',  128, 8)
add_part (0x3670002B, 'lpc122x', 'LPC1227-301',  'LQFP48',  128, 8)
add_part (0x3660002B, 'lpc122x', 'LPC1226-301',  'LQFP64',  96,  8)
add_part (0x3660002B, 'lpc122x', 'LPC1226-301',  'LQFP48',  96,  8)
add_part (0x3652002B, 'lpc122x', 'LPC1225-321',  'LQFP64',  80,  8)
add_part (0x3650002B, 'lpc122x', 'LPC1225-301',  'LQFP64',  64,  8)
add_part (0x3652002B, 'lpc122x', 'LPC1225-321',  'LQFP48',  80,  8)
add_part (0x3650002B, 'lpc122x', 'LPC1225-301',  'LQFP48',  64,  8)
add_part (0x3642C02B, 'lpc122x', 'LPC1224-121',  'LQFP64',  48,  4)
add_part (0x3640C02B, 'lpc122x', 'LPC1224-101',  'LQFP64',  32,  4)
add_part (0x3642C02B, 'lpc122x', 'LPC1224-121',  'LQFP48',  48,  4)
add_part (0x3640C02B, 'lpc122x', 'LPC1224-101',  'LQFP48',  32,  4)


return devices
