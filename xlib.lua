
--Xlib binding.
--Written by Cosmin Apreutesei. Public Domain.

local ffi  = require'ffi'
assert(ffi.os == 'Linux', 'platform not Linux')
local bit  = require'bit'
local glue = require'glue'
local X    = require'xlib_h'     --macro namespace
local C    = ffi.load'X11.so.6'  --Xlib core
local XC   = ffi.load'Xext.so.6' --Xlib core extensions
local M    = {C = C, XC = XC, X = X}
local print = print

--conversion helpers ---------------------------------------------------------

local function ptr(p, free) --NULL -> nil conversion and optional gc hooking.
	return p ~= nil and ffi.gc(p, free) or nil
end

--XIDs can't exceed 32bit so we convert them to Lua numbers on x64
--to be able to use them as table keys directly. Oh, and 0 -> nil.
local function xid(x)
	return x ~= 0 and tonumber(x) or nil
end

M.ptr = ptr
M.xid = xid

--masked C struct helpers ----------------------------------------------------

--Lua table -> masked C struct
local function maskedset(ct, t, masks)
	local mask = 0
	if t then
		for field, val in pairs(t) do
			local maskbit = masks[field]
			if maskbit then
				mask = bit.bor(mask, maskbit)
				ct[field] = val
			end
		end
	end
	return mask
end

--masked C struct -> Lua table
local function maskedget(ct, mask, masks)
	local t = {}
	for field, maskbit in pairs(masks) do
		if bit.band(mask, maskbit) ~= 0 then
			t[field] = ct[field]
		end
	end
	return t
end

--glibc cdefs for setting _NET_WM_PID and WM_CLIENT_MACHINE ------------------

ffi.cdef[[
int xlib_getpid() asm("getpid");
int xlib_gethostname(char *name, size_t len) asm("gethostname");
typedef struct {
	char sysname[65];
	char nodename[65];
	char release[65];
	char version[65];
	char machine[65];
	char __domainname[65];
} xlib_utsname;
int xlib_uname(xlib_utsname* buf) asm("uname");
]]

--glibc cdefs for waiting on a socket with a timeout -------------------------

ffi.cdef[[
typedef struct {
	int32_t bits[32];
} xlib_fd_set;
typedef struct {
    long int tv_sec;
    long int tv_usec;
} xlib_timeval;
int xlib_select(int, xlib_fd_set*, xlib_fd_set*, xlib_fd_set*, xlib_timeval*) asm("select");
]]
local function FD_ZERO(fds) ffi.fill(fds, ffi.sizeof(fds)) end
local function FDELT(d) return d / 32 end
local function FDMASK(d) return bit.lshift(1, d % 32) end
local function FD_ISSET(d, set) return bit.band(set.bits[FDELT(d)], FDMASK(d)) ~= 0 end
local function FD_SET(d, set)
	assert(d <= 1024)
	set.bits[FDELT(d)] = bit.bor(set.bits[FDELT(d)], FDMASK(d))
end

local timeval, fds
local function select_fd(fd, timeout) --returns true if fd has data, false if timed out
	timeval = timeval or ffi.new'xlib_timeval'
	timeval.tv_sec = timeout
	timeval.tv_usec = (timeout - timeval.tv_sec) * 10^6
	fds = fds or ffi.new'xlib_fd_set'
	FD_ZERO(fds)
	FD_SET(fd, fds)
	assert(C.xlib_select(fd + 1, fds, nil, nil, timeval) >= 0)
	return FD_ISSET(fd, fds)
end

--API ------------------------------------------------------------------------

function M.connect(...)

	local type, select, unpack, assert, error, ffi, bit, table, ipairs, require, pcall, tonumber, setmetatable, rawget, glue =
	      type, select, unpack, assert, error, ffi, bit, table, ipairs, require, pcall, tonumber, setmetatable, rawget, glue
	local cast = ffi.cast
	local free = glue.free

	local xlib = glue.update({}, M)
	setfenv(1, xlib)

	--connection --------------------------------------------------------------

	local c            --Display*
	local fd           --connection fd
	local screen_num   --default screen number
	local screen       --default Screen
	local cleanup = {} --disconnect handlers

	local errbuf
	local onerr = ffi.cast('XErrorHandler', function(c, e)
		local errbuf_sz = 256
		errbuf = errbuf or ffi.new('char[?]', errbuf_sz)
		C.XGetErrorText(c, e.error_code, errbuf, errbuf_sz)
		error(ffi.string(errbuf), 2)
	end)

	local function connect(displayname)

		c = assert(ptr(C.XOpenDisplay(displayname)))

		C.XSetErrorHandler(onerr)

		fd = C.XConnectionNumber(c)
		screen_num = C.XDefaultScreen(c)
		screen = C.XScreenOfDisplay(c, screen_num)

		xlib.display = c
		xlib.display_fd = fd
		xlib.screen = screen
		xlib.screen_number = screen_num
	end

	function synchronize(enable)
		C.XSynchronize(c, enable or false)
	end

	function flush()
		C.XFlush(c)
	end

	function sync(discard_events)
		C.XSync(c, discard_events or 0)
	end

	function disconnect()
		for i,clean in ipairs(cleanup) do
			clean()
		end
		C.XCloseDisplay(c)
		c = nil --prevent use after disconnect
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
	function has_extension(s)
		return extension_map()[s]
	end

	--events ------------------------------------------------------------------

	local e = ffi.new'XEvent'

	--poll or peek with or without blocking, returning an XEvent or nil.
	local function poll_func(XXEvent)
		return function(timeout)
			local n = tonumber(timeout)
			if n and n <= 0 then
				timeout = nil --negative timeout means do not block
			end
			if C.XPending(c) > 0 then
				XXEvent(c, e)
				C.XFilterEvent(e, 0) --add input method synthetic events
				return e
			end
			if timeout == true then
				XXEvent(c, e) --block indefinitely
				return e
			elseif timeout then
				if select_fd(fd, timeout) then --block with timeout
					XXEvent(c, e)
					return e
				end
			end
		end
	end
	poll = poll_func(C.XNextEvent)
	peek = poll_func(C.XPeekEvent)

	--poll or peek until a predicate is satisfied, returning true or nil on timeout.
	local function poll_until_func(poll)
		return function(func, timeout)
			while true do
				local e = poll(timeout)
				if not e then return end --timeout
				if func(e) then return true end --condition satisfied
			end
		end
	end
	poll_until = poll_until_func(poll)
	peek_until = poll_until_func(peek)

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

	local function list_decoder(ctype, decode_val)
		decode_val = decode_val or glue.pass
		local ptr_ctype = ffi.typeof('$*', ffi.typeof(ctype))
		return function(val, len)
			val = cast(ptr_ctype, val)
			local t = {}
			for i=1,len do
				t[i] = decode_val(val[i-1])
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

	local decode = list_decoder('Atom', tonumber)
	local function atom_map_index(t, name)
		return rawget(t, atom(name)) and true or false
	end
	function get_atom_map_prop(win, prop, key)
		local list = get_prop(win, prop, decode)
		if not list then return end
		--statically index the atoms
		local t = {}
		for i, atom in ipairs(list) do
			t[atom] = true
		end
		--dynamically index the atoms names
		setmetatable(t, {__index = atom_map_index})
		--sugar for key lookup
		if key then
			return t[key]
		else
			return t
		end
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

	local decode = list_decoder('Window', xid)
	function get_window_list_prop(win, prop)
		return get_prop(win, prop, decode)
	end

	local decode = list_decoder('long', tonumber)
	function get_int_list_prop(win, prop)
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
				e.xclient.data[datatype][i-1] = val_func(v)
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
		return net_supported_map()[s]
	end

	function get_net_wm_state(win, key)
		return get_atom_map_prop(win, '_NET_WM_STATE', key)
	end
	function set_net_wm_state(win, t) --before the window is mapped, use this.
		set_atom_map_prop(win, '_NET_WM_STATE', t)
	end
	function change_net_wm_state(win, set, atom1, atom2) --after a window is mapped, use this.
		local e = atom_list_event(win, '_NET_WM_STATE', set and 1 or 0, atom1, atom2)
		send_client_message_to_root(e)
	end

	local hints = ptr(C.XAllocWMHints(), C.XFree)
	local masks = {
		input = C.InputHint,
		initial_state = C.StateHint,
		icon_pixmap = C.IconPixmapHint,
		icon_x = C.IconWindowHint,
		icon_y = C.IconWindowHint,
		icon_mask = C.IconMaskHint,
		window_group = C.WindowGroupHint,
	}
	function get_wm_hints(win)
		local hints = ptr(C.XGetWMHints(c, win))
		if not hints then return end
		local t = maskedget(hints, hints.flags, masks)
		C.XFree(hints)
		return t
	end
	function set_wm_hints(win, t)
		hints.flags = maskedset(hints, t, masks)
		if hints.flags == 0 then return end
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
		return {val[0], val[1]} --ICCCM_WM_STATE_*, icon_window_id
	end
	function get_wm_state(win)
		local t = get_prop(win, 'WM_STATE', decode_wm_state)
		if t then return unpack(t) end
	end

	--use this to change WM_STATE after the window is mapped.
	--NOTE: this works with C.IconincState but not with C.NormalState.
	--To restore a minimized window, map it instead.
	function change_wm_state(win, state)
		local e = client_message_event(win, 'WM_CHANGE_STATE')
		e.xclient.data.l[0] = state
		send_client_message_to_root(e)
	end

	local winbuf = ffi.new'Window[1]'
	function get_transient_for(win)
		C.XGetTransientForHint(c, win, winbuf)
		return xid(winbuf[0])
	end
	function set_transient_for(win, for_win)
		C.XSetTransientForHint(c, win, for_win)
	end

	--NOTE: set all other window properties before requesting the frame extents.
	--NOTE: the property is not always set immediately so retry with a timeout.
	--NOTE: as usual, expect this to be implemented poorly in most WMs.
	function frame_extents_supported()
		return net_supported'_NET_REQUEST_FRAME_EXTENTS'
	end
	function request_frame_extents(win)
		local e = client_message_event(win, atom'_NET_REQUEST_FRAME_EXTENTS')
		send_client_message_to_root(e)
	end
	local function decode_extents(val)
		val = cast('long*', val)
		return {
			tonumber(val[0]), --left
			tonumber(val[2]), --top
			tonumber(val[1]), --right
			tonumber(val[3]), --bottom
		}
	end
	function get_frame_extents(win)
		local t = get_prop(win, '_NET_FRAME_EXTENTS', decode_extents)
		if t then return unpack(t) end
	end

	--NOTE: XMapWindow doesn't raise and doesn't activate the window.
	--NOTE: XMapWindow is async (wait for MapNotify to make it sync
	--but note that MapNotify is not sent if the window is hidden + minimized).
	function map(win)
		C.XMapWindow(c, win)
	end

	--NOTE: XWithdrawWindow should always be used instead of XUnmapWindow
	--because XUnmapWindow doesn't send the synthetic UnmapNotify required
	--per ICCCM, so it doesn't properly hide minimized windows.
	--NOTE: XWithdrawWindow is async (wait for UnmapNotify to make it sync
	--but note that UnmapNotify is not sent if the window was minimized).
	function withdraw(win)
		C.XWithdrawWindow(c, win, screen_num)
	end

	function get_net_active_window()
		return get_window_prop(screen.root, '_NET_ACTIVE_WINDOW')
	end
	function change_net_active_window(win, focused_win)
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

	do
		local xbuf = ffi.new'int[1]'
		local ybuf = ffi.new'int[1]'
		local winbuf = ffi.new'Window[1]'
		function translate_coords(src_win, dst_win, x, y)
			if C.XTranslateCoordinates(c, src_win, dst_win, x, y, xbuf, ybuf, winbuf) == 0 then
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

	--root window attributes --------------------------------------------------

	function get_net_workarea(screen1, desktop_num)
		local screen = screen1 or screen
		local t = get_int_list_prop(screen.root, '_NET_WORKAREA')
		if not t then return end
		local dt = {}
		for i=1,#t,4 do
			dt[#dt+1] = {unpack(t, i, i+3)}
		end
		return desktop_num and dt[desktop_num] or dt
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
	function set_net_wm_ping_info(win)
		set_cardinal_prop(win, '_NET_WM_PID', ffi.C.xlib_getpid())
		local name
		local buf = ffi.new'char[256]'
		if ffi.C.xlib_gethostname(buf, 256) == 0 then
			name = ffi.string(buf)
		else
			local utsname = ffi.new'xlib_utsname'
			if ffi.C.xlib_uname(utsname) == 0 then
				name = ffi.string(utsname.nodename)
			end
		end
		if name then
			set_string_prop(win, 'WM_CLIENT_MACHINE', name)
		end
	end

	--rendering ---------------------------------------------------------------

	--NOTE: XClearWindow() doesn't generate Expose events.
	function clear_area(win, x, y, w, h)
		assert(C.XClearArea(c, win, x, y, w, h, true) == 1)
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

	--Xinerama extension ------------------------------------------------------

	local XC
	function xinerama_screens()
		if not has_extension'XINERAMA' then return end
		XC = XC or ffi.load'Xinerama'
		if XC.XineramaIsActive(c) == 0 then return end
		local nbuf = ffi.new'int[1]'
		local screens = ptr(XC.XineramaQueryScreens(c, nbuf), C.XFree)
		return screens, nbuf[0]
	end

	--[[
	--input methods -----------------------------------------------------------

	function set_locale_modifiers(im)
		im = im or 'none' --XIM, SCIM, IBUS, etc.
		if os.setlocale'' then --set native locale
			if C.XSupportsLocale() ~= 0 then
				C.XSetLocaleModifiers('@im='..im)
			end
		end
	end

	function open_im(win)
		local im = ptr(C.XOpenIM(c, nil, nil, nil))
		if not im then return end

		local styles = ffi.new'XIMStyles *[1]'
		failed_arg = ptr(C.XGetIMValues(im, C.XNQueryInputStyle, styles, nil))
		if failed_arg then return end

		for i=0,styles.count_styles-1 do
		  print(string.format('style %d', styles.supported_styles[i])
		end
		local ic = ptr(C.XCreateIC(im,
			C.XNInputStyle,
			bit.bor(C.XIMPreeditNothing, C.XIMStatusNothing),
			C.XNClientWindow, self.win, nil)
		if not ic then return end
		C.XSetICFocus(ic)
	end

	--shm extension -----------------------------------------------------------

	function shm()
		if XC.XShmQueryVersion(c) == 0 then return end
		local ok = reply ~= nil and reply.shared_pixmaps ~= 0
		return lib
	end
	]]

	connect(...)

	return xlib
end

return M
