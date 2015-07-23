local pp   = require'pp'
local time = require'time'
local xlib = require'xlib'
local ffi = require'ffi'

local xlib = xlib.connect()
local C = xlib.C

local testatom = xlib.atom'TEST_ATOM'
assert(xlib.atom_name(testatom) == 'TEST_ATOM')

print'screens:'
for i,s in xlib.get_screens() do
	print('', i, s.width, s.height, s.root_depth)
end

local win = xlib.create_window{width = 500, height = 300}
xlib.map(win)

print'win props:'
for i,a in xlib.list_props(win) do
	print('', xlib.atom_name(a))
end

print'xsettings:'
for k,v in pairs(xlib.get_xsettings()) do
	print(string.format('\t%-24s %s', k, pp.format(v)))
end

--declare the X protocols that the window supports.
xlib.set_atom_map_prop(win, 'WM_PROTOCOLS', {
	WM_DELETE_WINDOW = true, --don't close the connection when a window is closed
	WM_TAKE_FOCUS = true,    --allow focusing the window programatically
	_NET_WM_PING = true,     --respond to ping events
})

xlib.set_netwm_ping_info(win)

--events
while true do
	local e = xlib.poll(true)
	print('event', e.type)
	if e.type == C.ClientMessage then
		local v = e.xclient.data.l[0]
		print('', 'xclient', xlib.atom_name(v))
		if v == xlib.atom'_NET_WM_PING' then
			print'pong!'
			xlib.pong(e)
		elseif v == xlib.atom'WM_DELETE_WINDOW' then
			print'close'
			xlib.destroy_window(win)
			break
		end
	end
end

xlib.disconnect()
