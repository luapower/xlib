
--Xlib binding.
--Written by Cosmin Apreutesei. Public Domain.

local ffi  = require'ffi'
local glue = require'glue'
local X  = require'xlib_h'     --macro namespace
local C  = ffi.load'X11.so.6'  --Xlib core
local XC = ffi.load'Xext.so.6' --Xlib core extensions
local M  = {C = C, XC = XC, X = X}
local print = print

--for setting _NET_WM_PID and WM_CLIENT_MACHINE.
--NOTE: these are for Linux/GLIBC and OSX only!
ffi.cdef[[
int getpid();
int gethostname(char *name, size_t len);
typedef struct {
	char sysname[65];
	char nodename[65];
	char release[65];
	char version[65];
	char machine[65];
	char __domainname[65];
} _x_utsname;
int uname(_x_utsname* buf);
]]

local function ptr(p, free) --NULL -> nil conversion and optional gc hooking.
	return p ~= nil and ffi.gc(p, free) or nil
end

--XIDs can't exceed 32bit so we convert them to Lua numbers on x64
--to be able to use them as table keys directly. Oh, and 0 -> nil.
local function xid(x)
	return x ~= 0 and tonumber(x) or nil
end

--set dt[k] = t[k] for each masked k and return the combined mask of set fields.
local function maskedset(dt, t, masks)
	local mask = 0
	if t then
		for field, val in pairs(t) do
			local maskbit = masks[field]
			if maskbit then
				mask = bit.bor(mask, maskbit)
				dt[field] = val
			end
		end
	end
	return mask
end

local function maskedget(t, mask, masks)
	local dt = {}
	for field, maskbit in pairs(masks) do
		if bit.band(mask, maskbit) ~= 0 then
			dt[field] = t[field]
		end
	end
	return dt
end

M.ptr = ptr
M.xid = xid

function M.connect(...)

	local type, select, unpack, assert, error, ffi, bit, table, ipairs, require, pcall, tonumber, glue =
	      type, select, unpack, assert, error, ffi, bit, table, ipairs, require, pcall, tonumber, glue
	local cast = ffi.cast
	local free = glue.free

	local xlib = glue.update({}, M)
	setfenv(1, xlib)

	--connection --------------------------------------------------------------

	local c            --Display*
	local screen       --default Screen
	local cleanup = {} --disconnect handlers

	local function connect(displayname)
		c = C.XOpenDisplay(displayname)
		assert(c ~= nil)
		C.XSynchronize(c, true)
		screen = C.XScreenOfDisplay(c, C.XDefaultScreen(c))

		xlib.display = c
		xlib.screen = screen
	end

	function flush()
		C.XFlush(c)
	end

	function disconnect()
		for i,clean in ipairs(cleanup) do
			clean()
		end
		C.XCloseDisplay(c)
		c, screen, xlib.display, xlib.screen = nil --prevent use after disconnect
	end

	--server ------------------------------------------------------------------

	--load the list of supported server extensions into a hash
	local nbuf = ffi.new'int[1]'
	extension_map = glue.memoize(function()
		local a = C.XListExtensions(c, nbuf)
		local n = nbuf[0]
		local t = {}
		for i=0,n-1 do
			local ext = ffi.string(a[i])
			t[ext] = true
		end
		C.XFreeExtensionList(a)
		return t
	end)

	--check if the server has a specific extension
	function extension(s)
		return extension_map()[s]
	end

	--events ------------------------------------------------------------------

	local e = ffi.new'XEvent'

	--poll without blocking or wait for the next event
	function poll(block)
		if not block and C.XPending(c) == 0 then
			return
		end
		C.XNextEvent(c, e)
		return e
	end

	--peek without blocking
	function peek()
		if C.XPending(c) == 0 then
			return
		end
		C.XPeekEvent(c, e)
		return e
	end

	--atoms -------------------------------------------------------------------

	local atom_map = {}    --{name = atom}
	local atom_revmap = {} --{atom = name}

	local mem_atom = glue.memoize(function(s)
		local atom = tonumber(C.XInternAtom(c, s, false))
		atom_revmap[atom] = s
		return atom
	end, atom_map)

	--lookup/intern an atom
	function atom(s)
		if type(s) ~= 'string' then return s end --pass through
		return mem_atom(s)
	end

	--atom reverse lookup
	atom_name = glue.memoize(function(atom)
		local p = C.XGetAtomName(c, atom)
		if p == nil then return end
		local s = ffi.string(p)
		C.XFree(p)
		atom_map[s] = atom
		return s
	end, atom_revmap)

	--given a map {atom -> true} return the map {atom_name -> atom}
	function atom_names(t)
		local dt = {}
		for atom in pairs(t) do
			local name = atom_name(atom)
			if name then
				dt[name] = atom
			end
		end
		return dt
	end

	--screens -----------------------------------------------------------------

	function get_screens()
		local n = C.XScreenCount(c)
		local i = -1
		return function()
			i = i + 1
			if i >= n then return end
			return i, C.XScreenOfDisplay(c, i)
		end
	end

	--window attributes -------------------------------------------------------

	local abuf = ffi.new'XSetWindowAttributes'
	local masks = {
		background_pixmap = C.CWBackPixmap,
		background_pixel = C.CWBackPixel,
		border_pixmap = C.CWBorderPixmap,
		border_pixel = C.CWBorderPixel,
		bit_gravity = C.CWBitGravity,
		win_gravity = C.CWWinGravity,
		backing_store = C.CWBackingStore,
		backing_planes = C.CWBackingPlanes,
		backing_pixel = C.CWBackingPixel,
		save_under = C.CWSaveUnder,
		event_mask = C.CWEventMask,
		do_not_propagate_mask = C.CWDontPropagate,
		override_redirect = C.CWOverrideRedirect,
		colormap = C.CWColormap,
		cursor = C.CWCursor,
	}
	local function attr_buf(t) --attrs_t -> mask, attrs
		return maskedset(abuf, t, masks), abuf
	end

	--constructors and destructors --------------------------------------------

	--NOTE: WMs ignore t.x and t.y unless create_window() is followed
	--by set_wm_size_hints(win, {x = 0, y = 0}). Mental hospital-grade stuff.
	function create_window(t)
		local mask, attrs = attr_buf(t)
		return assert(xid(C.XCreateWindow(c,
			t.parent or screen.root,
			t.x or 0,
			t.y or 0,
			t.width,
			t.height,
			t.border_width or 0, --ignored
			t.depth or C.CopyFromParent,
			t.class or C.CopyFromParent,
			t.visual or nil, --means C.CopyFromParent
			mask, attrs)))
	end
	function destroy_window(win)
		C.XDestroyWindow(c, win)
	end

	function create_colormap(win, visual, alloc)
		return assert(xid(C.XCreateColormap(c, win, visual, alloc and C.AllocAll or C.AllocNone)))
	end
	function free_colormap(cmap)
		C.XFreeColormap(c, cmap)
	end

	function create_pixmap(win, w, h, depth)
		return assert(xid(C.XCreatePixmap(c, win, w, h, depth)))
	end
	function free_pixmap(pix)
		C.XFreePixmap(c, pix)
	end

	function create_gc(win, mask, values)
		return assert(ptr(C.XCreateGC(c, win, mask or 0, values)))
	end
	function free_gc(gc)
		C.XFreeGC(c, gc)
	end

	local image = ffi.new'XImage'
	function put_image(gc, data, size, w, h, depth, pix, dx, dy, left_pad)
		image.width = w
		image.height = h
		image.format = C.ZPixmap
		image.data = data
		image.bitmap_unit = 8
		image.byte_order = C.LSBFirst
		image.bitmap_bit_order = C.LSBFirst
		image.depth = depth
		image.bytes_per_line = w * 4
		image.bits_per_pixel = 32
		image.red_mask   = 0xff
		image.green_mask = 0xff
		image.blue_mask  = 0xff
		C.XInitImage(image)
		C.XPutImage(c, pix, gc, image, 0, 0, dx or 0, dy or 0, w, h)
	end

	function copy_area(gc, src, sx, sy, w, h, dst, dx, dy)
		C.XCopyArea(c, src, dst, gc, sx or 0, sy or 0, w, h, dx or 0, dy or 0)
	end

	--window properties -------------------------------------------------------

	local nbuf = ffi.new'int[1]'
	function list_props(win)
		local a = ptr(C.XListProperties(c, win, nbuf), C.XFree)
		local n = nbuf[0]
		local i = -1
		return function()
			i = i + 1
			if i >= n then
				if a then
					ffi.gc(a, nil)
					C.XFree(a)
				end
				return
			end
			return i+1, a[i]
		end
	end

	function delete_prop(win, prop)
		C.XDeleteProperty(c, win, atom(prop))
	end

	function set_prop(win, prop, type, val, sz, format)
		C.XChangeProperty(c, win, atom(prop), atom(type), format or 32,
			C.PropModeReplace, ffi.cast('const unsigned char*', val), sz)
	end

	local reply_type = ffi.new'Atom[1]'
	local reply_format = ffi.new'int[1]'
	local nitems = ffi.new'unsigned long[1]'
	local bytes_after = ffi.new'unsigned long[1]'
	local data_ptr = ffi.new'unsigned char*[1]'
	function get_prop(win, prop, decode)
		local ret = C.XGetWindowProperty(c, win, atom(prop), 0, 2^22, false,
			C.AnyPropertyType, reply_type, reply_format, nitems, bytes_after, data_ptr)
		if ret == C.BadAtom or reply_type[0] == 0 then --property missing
			return
		end
		assert(ret == 0)
		if bytes_after[0] ~= 0 then
			C.XFree(data_ptr[0])
			error('property value truncated', 2)
		end
		local data = data_ptr[0]
		local n = tonumber(nitems[0])
		local ok, ret = pcall(decode, data, n, reply_format[0], reply_type[0])
		C.XFree(data)
		if not ok then
			error(ret, 2)
		end
		return ret
	end

	function set_string_prop(win, prop, val)
		set_prop(win, prop, C.XA_STRING, val, #val, 8)
	end

	local function decode(data, n, bits)
		assert(bits == 8, 'invalid format')
		return ffi.string(data, n)
	end
	function get_string_prop(win, prop)
		return get_prop(win, prop, decode)
	end

	local function list_encoder(ctype, encode_val)
		encode_val = encode_val or glue.pass
		local arr_ctype = ffi.typeof('$[?]', ffi.typeof(ctype))
		return function(t)
			local n = #t
			local a = ffi.new(arr_ctype, n)
			for i = 1,n do
				a[i-1] = encode_val(t[i])
			end
			return a,n
		end
	end

	local function list_decoder(ctype)
		local ptr_ctype = ffi.typeof('$*', ffi.typeof(ctype))
		return function(val, len)
			val = cast(ptr_ctype, val)
			local t = {}
			for i=1,len do
				t[i] = val[i-1]
			end
			return t
		end
	end

	local atombuf = ffi.new'Atom[1]'
	function set_atom_prop(win, prop, val)
		atombuf[0] = atom(val)
		set_prop(win, prop, C.XA_ATOM, atombuf)
	end

	local atom_list = list_encoder('Atom', atom)
	function set_atom_map_prop(win, prop, t)
		local atoms, n = atom_list(glue.keys(t))
		if n == 0 then
			delete_prop(win, prop)
		else
			set_prop(win, prop, C.XA_ATOM, atoms, n)
		end
	end

	local decode = list_decoder'Atom'
	function get_atom_map_prop(win, prop)
		return get_prop(win, prop, decode)
	end

	local nbuf = ffi.new'int[1]'
	function set_cardinal_prop(win, prop, val)
		nbuf[0] = val
		set_prop(win, prop, C.XA_CARDINAL, nbuf, 1)
	end

	local function decode_window(val, len)
		if len == 0 then return end
		return cast('Window*', val)[0]
	end
	function get_window_prop(win, prop)
		return get_prop(win, prop, decode_window)
	end

	local winbuf = ffi.new'Window[1]'
	function set_window_prop(win, prop, target_win)
		winbuf[0] = target_win
		set_prop(win, prop, C.XA_WINDOW, winbuf, 1)
	end

	local decode = list_decoder'Window'
	function get_window_list_prop(win, prop)
		return get_prop(win, prop, decode)
	end

	--client message events ---------------------------------------------------

	local function client_message_event(win, type, format)
		local e = ffi.new'XEvent'
		e.type = C.ClientMessage
		e.xclient.format = format or 32
		e.xclient.window = win
		e.xclient.message_type = atom(type)
		return e
	end

	local function list_event(win, type, datatype, val_func, ...)
		local e = client_message_event(win, type)
		for i = 1,5 do
			local v = select(i, ...)
			if v then
				e.data[datatype][i-1] = val_func(v)
			end
		end
		return e
	end

	function int32_list_event(win, type, ...)
		return list_event(win, type, 'l', glue.pass, ...)
	end

	function atom_list_event(win, type, ...)
		return list_event(win, type, 'l', atom, ...)
	end

	function send_client_message(win, e, propagate, mask)
		C.XSendEvent(c, win, propagate or false, mask or 0, e)
	end

	function send_client_message_to_root(e)
		local mask = bit.bor(
			C.SubstructureNotifyMask,
			C.SubstructureRedirectMask)
		send_client_message(screen.root, e, false, mask)
	end

	--window attributes -------------------------------------------------------

	local attrs = ffi.new'XWindowAttributes'
	function get_attrs(win)
		assert(C.XGetWindowAttributes(c, win, attrs) == 1)
		return attrs
	end

	function set_attrs(win, t)
		local mask, attrs = attr_buf(t)
		if mask == 0 then return end --nothing to set
		assert(C.XChangeWindowAttributes(c, win, mask, attrs) == 0)
	end

	local rbuf = ffi.new'Window[1]'
	local xbuf = ffi.new'int[1]'
	local ybuf = ffi.new'int[1]'
	local wbuf = ffi.new'unsigned int[1]'
	local hbuf = ffi.new'unsigned int[1]'
	local bbuf = ffi.new'unsigned int[1]'
	local dbuf = ffi.new'unsigned int[1]'
	function get_geometry(win) --returns x, y, w, h, border_width, depth, root
		assert(C.XGetGeometry(c, win, rbuf, xbuf, ybuf, wbuf, hbuf, bbuf, dbuf) == 1)
		return xbuf[0], ybuf[0], wbuf[0], hbuf[0], bbuf[0], dbuf[0], xid(rbuf[0])
	end

	local cbuf = ffi.new'XWindowChanges'
	local masks = {
		x = C.CWX,
		y = C.CWY,
		width = C.CWWidth,
		height = C.CWHeight,
		border_width = C.CWBorderWidth,
		stack_mode = C.CWStackMode,
		sibling = C.CWSibling,
	}
	function config(win, t)
		local mask = maskedset(cbuf, t, masks)
		if mask == 0 then return end --nothing to set
		C.XConfigureWindow(c, win, mask, cbuf)
	end

	function raise(win) C.XRaiseWindow(c, win) end
	function lower(win) C.XLowerWindow(c, win) end

	net_supported_map = glue.memoize(function()
		return get_atom_map_prop(screen.root, '_NET_SUPPORTED')
	end)
	function net_supported(s)
		return net_supported_map()[atom(s)]
	end

	function get_netwm_states(win)
		return get_atom_map_prop(win, '_NET_WM_STATE')
	end
	function set_netwm_states(win, t) --before the window is mapped, use this.
		set_atom_map_prop(win, '_NET_WM_STATE', t)
	end
	function change_netwm_states(win, set, atom1, atom2) --after a window is mapped, use this.
		local e = atom_list_event(win, '_NET_WM_STATE', set and 1 or 0, atom1, atom2)
		send_client_message_to_root(e)
	end

	function get_wm_hints(win)
		return ptr(C.XGetWMHints(c, win), C.XFree)
	end
	function set_wm_hints(win, hints)
		C.XSetWMHints(c, win, hints)
	end

	local hints = ptr(C.XAllocSizeHints(), C.XFree)
	local masks = {
		x = C.PPosition,
		y = C.PPosition,
		width = C.PSize,
		height = C.PSize,
		min_width  = C.PMinSize,
		min_height = C.PMinSize,
		max_width  = C.PMaxSize,
		max_height = C.PMaxSize,
	}
	function set_wm_size_hints(win, t, prop)
		hints.flags = maskedset(hints, t, masks)
		if hints.flags == 0 then return end
		prop = atom(prop or 'WM_NORMAL_HINTS')
		C.XSetWMSizeHints(c, win, hints, prop)
	end
	local mask = ffi.new'long[1]'
	function get_wm_size_hints(win, prop)
		prop = atom(prop or 'WM_NORMAL_HINTS')
		if C.XGetWMSizeHints(c, win, hints, mask, prop) == 0 then return end
		return maskedget(hints, mask[0], masks)
	end

	local function decode_motif_wm_hints(val, len)
		return ffi.new('PropMotifWmHints', cast('PropMotifWmHints*', val)[0])
	end
	function get_motif_wm_hints(win)
		get_prop(win, '_MOTIF_WM_HINTS', decode_motif_wm_hints)
	end
	function set_motif_wm_hints(win, hints)
		set_prop(win, '_MOTIF_WM_HINTS', '_MOTIF_WM_HINTS', hints,
			C.MOTIF_WM_HINTS_ELEMENTS)
	end

	local function decode_wm_state(val, len)
		assert(len >= 2)
		val = ffi.cast('int32_t*', val)
		return val[0], val[1] --XCB_ICCCM_WM_STATE_*, icon_window_id
	end
	function get_wm_state(win)
		return get_prop(win, 'WM_STATE', decode_wm_state)
	end

	local winbuf = ffi.new'Window[1]'
	function get_transient_for(win)
		C.XGetTransientForHint(c, win, winbuf)
		return xid(winbuf[0])
	end
	function set_transient_for(win, for_win)
		C.XSetTransientForHint(c, win, for_win)
	end

	--request filling up the frame_extents property before the window is mapped.
	function request_frame_extents(win)
		local e = client_message_event(win, atom'_NET_REQUEST_FRAME_EXTENTS')
		send_client_message_to_root(e)
	end
	local function decode_extents(val)
		val = cast('int32_t*', val)
		return val[0], val[2], val[1], val[3] --left, top, right, bottom
	end
	function frame_extents(win)
		if not net_supported'_NET_REQUEST_FRAME_EXTENTS' then
			return 0, 0, 0, 0
		end
		return get_prop(win, '_NET_FRAME_EXTENTS', decode_extents)
	end

	function map_raised(win)
		C.XMapRaised(c, win)
	end

	--NOTE: XMapWindow doesn't raise and doesn't activate the window.
	--NOTE: XMapWindow is async (wait for MapNotify).
	function map(win)
		C.XMapWindow(c, win)
	end

	--NOTE: XUnMapWindow is async (wait for UnmapNotify).
	function unmap(win)
		C.XUnmapWindow(c, win)
	end

	function get_net_active_window()
		return get_window_prop(screen.root, '_NET_ACTIVE_WINDOW')
	end

	function net_active_window_supported()
		return net_supported'_NET_ACTIVE_WINDOW'
	end

	function set_net_active_window(win, focused_win)
		local e = int32_list_event(win, '_NET_ACTIVE_WINDOW',
			1, --message comes from an app
			0, --timestamp
			focused_win or C.None)
		send_client_message_to_root(e)
	end

	local winbuf = ffi.new'Window[1]'
	local fstate = ffi.new'int[1]'
	function get_input_focus()
		C.XGetInputFocus(c, winbuf, fstate)
		return xid(winbuf[0]), fstate[0]
	end

	function set_input_focus(win, fstate)
		C.XSetInputFocus(c, win, fstate or C.RevertToNone, C.CurrentTime)
	end

	function minimize(win)
		local e = client_message_event(win, 'WM_CHANGE_STATE')
		e.data.l[0] = C.IconicState
		send_client_message_to_root(e)
	end

	do
		local xbuf = ffi.new'int[1]'
		local ybuf = ffi.new'int[1]'
		local winbuf = ffi.new'Window[1]'
		function translate_coords(src_win, dst_win, x, y)
			if C.XTranslateCoordinates(c, src_win, dst_win, x, y, xbuf, ybuf) == 0 then
				return --windows are on different screens
			end
			return xbuf[0], ybuf[0], xid(winbuf[0])
		end
	end

	function get_title(win)
		return get_string_prop(win, C.XA_WM_NAME)
	end
	function set_title(win, title)
		set_string_prop(win, C.XA_WM_NAME, title)
		set_string_prop(win, C.XA_WM_ICON_NAME, title)
	end

	--selections --------------------------------------------------------------

	function get_selection_owner(sel)
		return xid(C.XGetSelectionOwner(c, atom(sel)))
	end

	--xsettings extension -----------------------------------------------------

	function get_xsettings_window(screen0)
		local snum = C.XScreenNumberOfScreen(screen0 or screen)
		return get_selection_owner('_XSETTINGS_S'..snum)
	end

	function set_xsettings_change_notify()
		local win = get_xsettings_window()
		if not win then return end
		set_attrs(win, {event_mask = mask})
	end

	function get_xsettings()
		local xsettings = require'xlib_xsettings'
		local win = get_xsettings_window()
		if not win then return end
		return get_prop(win, '_XSETTINGS_SETTINGS', xsettings.decode)
	end

	--cursors -----------------------------------------------------------------

	local ctx
	function load_cursor(name)
		if not ctx then
			local xcursor = require'xlib_xcursor'
			ctx = xcursor.context(c, screen)
			table.insert(cleanup, function() ctx:free() end)
		end
		return ctx:load(name)
	end

	function set_cursor(win, cursor)
		set_attrs(win, {cursor = cursor})
	end

	local bcur
	function blank_cursor()
		if not bcur then
			bcur = gen_id()
			local pix = gen_id()
			C.xcb_create_pixmap(c, 1, pix, screen.root, 1, 1)
			C.xcb_create_cursor(c, bcur, pix, pix, 0, 0, 0, 0, 0, 0, 0, 0)
			C.xcb_free_pixmap(c, pix)
		end
		return bcur
	end

	--_NET_WM_PING protocol helpers -------------------------------------------

	--respond to a _NET_WM_PING event
	function pong(e)
		local reply = ffi.new('XEvent', ffi.cast('XEvent*', e)[0])
		reply.type = C.ClientMessage
		reply.xclient.window = screen.root
		send_client_message_to_root(reply) --pong!
	end

	--set _NET_WM_PID and WM_CLIENT_MACHINE as needed by the protocol
	function set_netwm_ping_info(win)
		set_cardinal_prop(win, '_NET_WM_PID', ffi.C.getpid())
		local name
		local buf = ffi.new'char[256]'
		if ffi.C.gethostname(buf, 256) == 0 then
			name = ffi.string(buf)
		else
			local utsname = ffi.new'_x_utsname'
			if ffi.C.uname(utsname) == 0 then
				name = ffi.string(utsname.nodename)
			end
		end
		if name then
			set_string_prop(win, 'WM_CLIENT_MACHINE', name)
		end
	end

	--shm extension -----------------------------------------------------------

	function shm()
		if XC.XShmQueryVersion(c) == 0 then return end
		local ok = reply ~= nil and reply.shared_pixmaps ~= 0
		return lib
	end

	connect(...)

	return xlib
end

return M
