
--Xlib-xcb binding.
--Written By Cosmin Apreutesei. Public Domain.

local ffi = require'ffi'

require'xlib_h'
require'xcb_h'

local C = ffi.abi'64bit' and ffi.load'/usr/lib/x86_64-linux-gnu/libX11-xcb.so.1' or ffi.load'X11-xcb'
local M = {C = C}

--X11/Xlib-xcb.h
ffi.cdef[[
xcb_connection_t *XGetXCBConnection(Display *dpy);
enum XEventQueueOwner { XlibOwnsEventQueue = 0, XCBOwnsEventQueue };
void XSetEventQueueOwner(Display *dpy, enum XEventQueueOwner owner);
]]

M.xcb_connection = C.XGetXCBConnection

function M.xlib_owns_queue(display)
	C.XSetEventQueueOwner(display, C.XlibOwnsEventQueue)
end

function M.xcb_owns_queue(display)
	C.XSetEventQueueOwner(display, C.XCBOwnsEventQueue)
end

return M
