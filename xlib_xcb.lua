
--X11/Xlib-xcb.h

local ffi = require'ffi'

require'xlib_h'
require'xcb_h'

local C = ffi.abi'64bit' and ffi.load'/usr/lib/x86_64-linux-gnu/libX11-xcb.so.1' or ffi.load'X11-xcb'

ffi.cdef[[
xcb_connection_t *XGetXCBConnection(Display *dpy);
enum XEventQueueOwner { XlibOwnsEventQueue = 0, XCBOwnsEventQueue };
void XSetEventQueueOwner(Display *dpy, enum XEventQueueOwner owner);
]]

return C
