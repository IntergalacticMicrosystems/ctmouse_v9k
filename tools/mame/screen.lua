-- MAME victor9k autoboot script: runs a command file (env V9K_CMDS) against the
-- emulated machine. One command per line, '#' starts a comment:
--   wait <sec>                  emulated seconds
--   waittext <text>             until the text screen contains <text> (60 s limit)
--   waitidle [sec]              until keyboard queue empty and screen unchanged for sec (1.0)
--   type <text>                 natural keyboard; \n = RETURN, \t = TAB, \\ = backslash
--   screen <file|->             text dump (25x80 from CRTC R12:R13)
--   screenraw <file|->          all 2048 text words in hex, 32 per line
--   mem <addr> <len> <file>     binary dump of the program space (hex numbers)
--   peek <addr> <len>           hex bytes to stdout
--   poke <addr> <byte>...       write bytes
--   regs                        CPU registers to stdout
--   items <devtag>              a device's save-state items (first element), e.g. items :11a
--   watchw <addr> <len>         log every CPU write in the range (PC, data) to stdout;
--                               as the first command it is armed before the boot ROM runs
--   snap                        PNG of the screen into $V9K_RUN/snap/victor9k/NNNN.png (works with -video none)
--   unwatch                     remove all watchw taps
--   print <text> / exit
-- Addresses are linear (segment*16+offset), e.g. F0000 = F000:0000, 104 = INT 41h vector.
local cmdfile = os.getenv("V9K_CMDS")
local m = manager.machine
local cpu = m.devices[":8l"]
local sp = cpu.spaces["program"]
local crtc = m.devices[":11a"]
local taps = {}

local function log(...) print("[v9k]", ...) io.stdout:flush() end
local function now() return m.time:as_double() end
local function hex(s) return tonumber(s, 16) end

local function disp_start()
	return emu.item(crtc.items["0/m_disp_start_addr"]):read(0) & 0x7ff
end

-- Victor console font: cell = ASCII + 100 (64h); bits 15-11 are attributes
local function screen_lines()
	local start, lines = disp_start(), {}
	for row = 0, 24 do
		local t = {}
		for col = 0, 79 do
			local w = sp:read_u16(0xf0000 + ((start + row * 80 + col) & 0x7ff) * 2)
			local c = (w & 0x7ff) - 100
			t[#t + 1] = (c >= 32 and c < 127) and string.char(c) or (c == -100 and " " or ".")
		end
		lines[#lines + 1] = (table.concat(t):gsub("%s+$", ""))
	end
	return lines
end
local function screen_text() return table.concat(screen_lines(), "\n") end

local function out(file, s)
	if file == "-" or file == nil then print(s) io.stdout:flush() return end
	local f = assert(io.open(file, "wb")) f:write(s) f:close()
	log("wrote " .. file .. " (" .. #s .. " bytes)")
end

local function wait_until(pred, limit)
	local t0 = now()
	while not pred() do
		if limit and now() - t0 > limit then return false end
		coroutine.yield()
	end
	return true
end

local cmds = {}
function cmds.wait(a) local t = now() + tonumber(a) wait_until(function() return now() >= t end) end
function cmds.waittext(a)
	if not wait_until(function() return screen_text():find(a, 1, true) end, 60) then
		log("TIMEOUT waiting for: " .. a)
	end
end
function cmds.waitidle(a)
	local need, last, since = tonumber(a) or 1.0, nil, now()
	wait_until(function()
		local s = screen_text()
		if s ~= last or not m.natkeyboard.empty then last, since = s, now() end
		return now() - since >= need
	end, 120)
end
function cmds.type(a)
	a = a:gsub("\\(.)", { n = "\r", t = "\t", ["\\"] = "\\" })
	m.natkeyboard:post(a)
	wait_until(function() return m.natkeyboard.empty end, 120)
end
function cmds.screen(a) out(a, screen_text() .. "\n") end
function cmds.screenraw(a)
	local t = {}
	for i = 0, 2047 do
		t[#t + 1] = string.format("%04x", sp:read_u16(0xf0000 + i * 2))
		t[#t + 1] = (i % 32 == 31) and "\n" or " "
	end
	out(a, string.format("start=%03x\n", disp_start()) .. table.concat(t))
end
function cmds.mem(a)
	local addr, len, file = a:match("(%x+)%s+(%x+)%s+(%S+)")
	local t = {}
	for i = 0, hex(len) - 1 do t[#t + 1] = string.char(sp:read_u8(hex(addr) + i)) end
	out(file, table.concat(t))
end
function cmds.peek(a)
	local addr, len = a:match("(%x+)%s+(%x+)")
	local t = {}
	for i = 0, hex(len) - 1 do t[#t + 1] = string.format("%02x", sp:read_u8(hex(addr) + i)) end
	log(string.format("%05x:", hex(addr)) .. " " .. table.concat(t, " "))
end
function cmds.poke(a)
	local addr, rest = a:match("(%x+)%s+(.*)")
	addr = hex(addr)
	for b in rest:gmatch("%x+") do sp:write_u8(addr, hex(b)) addr = addr + 1 end
end
function cmds.regs()
	local t = {}
	for _, r in ipairs({ "AX", "BX", "CX", "DX", "SI", "DI", "BP", "SP", "CS", "DS", "ES", "SS", "IP", "F" }) do
		if cpu.state[r] then t[#t + 1] = r .. "=" .. string.format("%04x", cpu.state[r].value) end
	end
	log(table.concat(t, " "))
end
function cmds.watchw(a)
	local addr, len = a:match("(%x+)%s+(%x+)")
	local lo = hex(addr)
	local hi = lo + hex(len) - 1
	taps[#taps + 1] = sp:install_write_tap(lo, hi, "watchw" .. #taps, function(offset, data, mask)
		local v, o = data, offset
		if mask == 0xff00 then v, o = data >> 8, offset + 1 elseif mask == 0x00ff then v = data & 0xff end
		if o >= lo and o <= hi then
			log(string.format("W %05x=%02x pc=%04x:%04x t=%.3f", o, v, cpu.state["CS"].value, cpu.state["IP"].value, now()))
		end
	end)
end
function cmds.snap() m.video:snapshot() log("snapshot saved to the snap directory") end
function cmds.unwatch() for _, t in ipairs(taps) do t:remove() end taps = {} end
function cmds.items(a)
	local d = m.devices[a]
	if not d then log("no device " .. a) return end
	local t = {}
	for k, i in pairs(d.items) do t[#t + 1] = k end
	table.sort(t)
	for _, k in ipairs(t) do
		local it = emu.item(d.items[k])
		log(string.format("%s %s = %x%s", a, k, it:read(0), it.count > 1 and (" [" .. it.count .. "]") or ""))
	end
end
function cmds.print(a) log(a) end
function cmds.exit() log(string.format("exit at t=%.1f", now())) m:exit() coroutine.yield() end

local function run()
	if not cmdfile then log("V9K_CMDS not set; idle") return end
	for line in io.lines(cmdfile) do
		local cmd, arg = line:match("^%s*(%S+)%s?(.-)%s*$")
		if cmd and cmd:sub(1, 1) ~= "#" then
			local f = cmds[cmd]
			if f then f(arg) else log("unknown command: " .. cmd) end
		end
	end
	log("end of " .. cmdfile)
end

local co = coroutine.create(run)
emu.register_periodic(function()
	if coroutine.status(co) == "suspended" then
		local ok, err = coroutine.resume(co)
		if not ok then log("ERROR " .. tostring(err)) m:exit() end
	end
end)
