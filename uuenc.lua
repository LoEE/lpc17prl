local D = require'util'
local bit = require'bit32'

local codes = "`!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"

local byte = string.byte
local sub = string.sub

local function encode3 (str, start, padding)
  start = start or 1
  padding = padding or 0x00
  local n = (byte(str, start) or padding) * 65536 + (byte(str, start+1) or padding) * 256 + (byte(str, start+2) or padding)
  return string.char(
    byte(codes, bit32.extract (n, 18, 6) + 1),
    byte(codes, bit32.extract (n, 12, 6) + 1),
    byte(codes, bit32.extract (n,  6, 6) + 1),
    byte(codes, bit32.extract (n,  0, 6) + 1))
end

local function decode1 (b)
  b = b - 32
  if b < 0 or b > 64 then error(string.format('invalid input character in position %d: %d', i, b + 32), 2) end
  if b == 64 then b = 0 end
  return b
end

local function decode3 (str, start)
  start = start or 1
  local n = 0
  for i=start,start+3 do
    n = n * 64 + decode1 (string.byte(str, i, i))
  end
  return string.char(
    bit32.extract(n, 16, 8),
    bit32.extract(n,  8, 8),
    bit32.extract(n,  0, 8))
end

local function encode_line (str, s, e, padding)
  s = s or 1
  if not e or e > #str then e = #str end
  local len = e - s + 1
  local o = { sub(codes, len + 1, len + 1) }
  for i=s,e,3 do
    o[#o+1] = encode3 (str, i, padding)
  end
  return table.concat (o)
end

local function decode_line (str)
  local len = decode1(string.byte(str, 1, 1)) 
  o = {}
  for i=2,#str,4 do
    o[#o+1] = decode3 (str, i)
  end
  o = table.concat (o)
  return o:sub(1,len)
end

return {
  encode3 = encode3,
  decode3 = decode3,
  encode_line = encode_line,
  decode_line = decode_line,
}
