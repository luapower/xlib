local pp   = require'pp'
local time = require'time'
local xlib = require'xlib'
local glx = require'glx'
require'gl11'
local ffi = require'ffi'

local xlib = xlib.connect()
local glx = glx.connect(xlib)
local gl = glx.C
local C = xlib.C

local testatom = xlib.atom'TEST_ATOM'
assert(xlib.atom_name(testatom) == 'TEST_ATOM')

print'screens:'
for i,s in xlib.get_screens() do
	print('', i, s.width, s.height, s.root_depth)
end

local glxctx
for fbconfig in glx.choose_rgb_fbconfigs() do
	glxctx = glx.create_context(fbconfig)
	break
end

local win = xlib.create_window{
	x = 300, y = 100,
	width = 500,
	height = 300,
	event_mask = bit.bor(
		C.ExposureMask,
		C.StructureNotifyMask,
		C.SubstructureNotifyMask
	),
}

xlib.set_wm_size_hints(win, {x = 0, y = 0})

print'win props:'
for i,a in xlib.list_props(win) do
	print('', xlib.atom_name(a))
end

print'root props:'
for i,a in xlib.list_props(xlib.screen.root) do
	print('', xlib.atom_name(a))
end

local t = xlib.get_net_workarea()
print'_NET_WORKAREA:'
for i=1,#t do
	print('', unpack(t[i]))
end

local t = {}
for atom in pairs(xlib.net_supported_map(win)) do
	t[#t+1] = xlib.atom_name(atom)
end
table.sort(t)
print('_NET_SUPPORTED: '..table.concat(t, ' '))

io.stdout:write'\n'

print'xsettings:'
for k,v in pairs(xlib.get_xsettings()) do
	print(string.format('\t%-24s %s', k, pp.format(v)))
end

print'xinerama screens:'
local screens, n = xlib.xinerama_screens()
for i=0,n-1 do
	local scr = screens[i]
	print(scr.screen_number, '', scr.x_org, scr.y_org, scr.width, scr.height)
end

--declare the X protocols that the window supports.
xlib.set_atom_map_prop(win, 'WM_PROTOCOLS', {
	WM_DELETE_WINDOW = true, --don't close the connection when a window is closed
	WM_TAKE_FOCUS = true,    --allow focusing the window programatically
	_NET_WM_PING = true,     --respond to ping events
})

--set required properties for _NET_WM_PING.
xlib.set_net_wm_ping_info(win)

--set motif hints before mapping the window.
local hints = ffi.new'PropMotifWmHints'
hints.flags = bit.bor(
	C.MWM_HINTS_FUNCTIONS,
	C.MWM_HINTS_DECORATIONS)
hints.functions = bit.bor(
	C.MWM_FUNC_RESIZE,
	C.MWM_FUNC_MOVE,
	C.MWM_FUNC_MINIMIZE,
	C.MWM_FUNC_MAXIMIZE,
	C.MWM_FUNC_CLOSE,
	0)
hints.decorations = bit.bor(
	C.MWM_DECOR_BORDER,
	C.MWM_DECOR_TITLE,
	C.MWM_DECOR_MENU,
	C.MWM_DECOR_RESIZEH,
	C.MWM_DECOR_MINIMIZE,
	C.MWM_DECOR_MAXIMIZE,
	0)
xlib.set_motif_wm_hints(win, hints)

--finally show the window
xlib.map(win)

local function gl_draw()
	gl.glClearColor(0.5, 0.5, 0.5, 0.5)
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)
end

--events
while true do
	local e = xlib.poll(1)
	if e then
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
		elseif e.type == C.Expose then
			glx.make_current(win, glxctx)
			gl_draw()
			glx.swap_buffers(win)
		end
	else
		print'tick'
	end
end

glx.destroy_context(glxctx)
xlib.disconnect()
