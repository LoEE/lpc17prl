local uu = require'uuenc'

local e3 = uu.encode3

assert(e3("ABC") == "04)#")
assert(e3("012ABC345", 4) == "04)#")
assert(e3('\0', 1, 0xff) == "`/__")

local el = uu.encode_line

assert(el("ABCDEFGHIJ") == "*04)#1$5&1TA)2@``")
assert(el(string.rep(string.char(128), 100), 1, 45) == "M@(\"`@(\"`@(\"`@(\"`@(\"`@(\"`@(\"`@(\"`@(\"`@(\"`@(\"`@(\"`@(\"`@(\"`@(\"`")

os.exit(0)
