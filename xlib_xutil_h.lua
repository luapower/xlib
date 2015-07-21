
--X11/xutil.h

local ffi = require'ffi'

require'xlib_h'

ffi.cdef[[
enum {
	NoValue              = 0x0000,
	XValue               = 0x0001,
	YValue               = 0x0002,
	WidthValue           = 0x0004,
	HeightValue          = 0x0008,
	AllValues            = 0x000F,
	XNegative            = 0x0010,
	YNegative            = 0x0020,
};
typedef struct {
     long flags;
 int x, y;
 int width, height;
 int min_width, min_height;
 int max_width, max_height;
     int width_inc, height_inc;
 struct {
  int x;
  int y;
 } min_aspect, max_aspect;
 int base_width, base_height;
 int win_gravity;
} XSizeHints;
enum {
	USPosition           = (1 << 0),
	USSize               = (1 << 1),
	PPosition            = (1 << 2),
	PSize                = (1 << 3),
	PMinSize             = (1 << 4),
	PMaxSize             = (1 << 5),
	PResizeInc           = (1 << 6),
	PAspect              = (1 << 7),
	PBaseSize            = (1 << 8),
	PWinGravity          = (1 << 9),
	PAllHints            = (PPosition|PSize|PMinSize|PMaxSize|PResizeInc|PAspect),
};
typedef struct {
 long flags;
 int input;
 int initial_state;
 Pixmap icon_pixmap;
 Window icon_window;
 int icon_x, icon_y;
 Pixmap icon_mask;
 XID window_group;
} XWMHints;
enum {
	InputHint            = (1 << 0),
	StateHint            = (1 << 1),
	IconPixmapHint       = (1 << 2),
	IconWindowHint       = (1 << 3),
	IconPositionHint     = (1 << 4),
	IconMaskHint         = (1 << 5),
	WindowGroupHint      = (1 << 6),
	AllHints             = (InputHint|StateHint|IconPixmapHint|IconWindowHint| IconPositionHint|IconMaskHint|WindowGroupHint),
	XUrgencyHint         = (1 << 8),
	WithdrawnState       = 0,
	NormalState          = 1,
	IconicState          = 3,
	DontCareState        = 0,
	ZoomState            = 2,
	InactiveState        = 4,
};
typedef struct {
    unsigned char *value;
    Atom encoding;
    int format;
    unsigned long nitems;
} XTextProperty;
enum {
	XNoMemory            = -1,
	XLocaleNotSupported  = -2,
	XConverterNotFound   = -3,
};
typedef enum {
    XStringStyle,
    XCompoundTextStyle,
    XTextStyle,
    XStdICCTextStyle,
    XUTF8StringStyle
} XICCEncodingStyle;
typedef struct {
 int min_width, min_height;
 int max_width, max_height;
 int width_inc, height_inc;
} XIconSize;
typedef struct {
 char *res_name;
 char *res_class;
} XClassHint;
typedef struct _XComposeStatus {
    XPointer compose_ptr;
    int chars_matched;
} XComposeStatus;
typedef struct _XRegion *Region;
enum {
	RectangleOut         = 0,
	RectangleIn          = 1,
	RectanglePart        = 2,
};
typedef struct {
  Visual *visual;
  VisualID visualid;
  int screen;
  int depth;
  int class;
  unsigned long red_mask;
  unsigned long green_mask;
  unsigned long blue_mask;
  int colormap_size;
  int bits_per_rgb;
} XVisualInfo;
enum {
	VisualNoMask         = 0x0,
	VisualIDMask         = 0x1,
	VisualScreenMask     = 0x2,
	VisualDepthMask      = 0x4,
	VisualClassMask      = 0x8,
	VisualRedMaskMask    = 0x10,
	VisualGreenMaskMask  = 0x20,
	VisualBlueMaskMask   = 0x40,
	VisualColormapSizeMask = 0x80,
	VisualBitsPerRGBMask = 0x100,
	VisualAllMask        = 0x1FF,
};
typedef struct {
 Colormap colormap;
 unsigned long red_max;
 unsigned long red_mult;
 unsigned long green_max;
 unsigned long green_mult;
 unsigned long blue_max;
 unsigned long blue_mult;
 unsigned long base_pixel;
 VisualID visualid;
 XID killid;
} XStandardColormap;
enum {
	ReleaseByFreeingColormap = ((XID) 1),
	BitmapSuccess        = 0,
	BitmapOpenFailed     = 1,
	BitmapFileInvalid    = 2,
	BitmapNoMemory       = 3,
	XCSUCCESS            = 0,
	XCNOMEM              = 1,
	XCNOENT              = 2,
};
typedef int XContext;
XClassHint *XAllocClassHint (
    void
);
XIconSize *XAllocIconSize (
    void
);
XSizeHints *XAllocSizeHints (
    void
);
XStandardColormap *XAllocStandardColormap (
    void
);
XWMHints *XAllocWMHints (
    void
);
int XClipBox(
    Region ,
    XRectangle*
);
Region XCreateRegion(
    void
);
const char *XDefaultString (void);
int XDeleteContext(
    Display* ,
    XID ,
    XContext
);
int XDestroyRegion(
    Region
);
int XEmptyRegion(
    Region
);
int XEqualRegion(
    Region ,
    Region
);
int XFindContext(
    Display* ,
    XID ,
    XContext ,
    XPointer*
);
int XGetClassHint(
    Display* ,
    Window ,
    XClassHint*
);
int XGetIconSizes(
    Display* ,
    Window ,
    XIconSize** ,
    int*
);
int XGetNormalHints(
    Display* ,
    Window ,
    XSizeHints*
);
int XGetRGBColormaps(
    Display* ,
    Window ,
    XStandardColormap** ,
    int* ,
    Atom
);
int XGetSizeHints(
    Display* ,
    Window ,
    XSizeHints* ,
    Atom
);
int XGetStandardColormap(
    Display* ,
    Window ,
    XStandardColormap* ,
    Atom
);
int XGetTextProperty(
    Display* ,
    Window ,
    XTextProperty* ,
    Atom
);
XVisualInfo *XGetVisualInfo(
    Display* ,
    long ,
    XVisualInfo* ,
    int*
);
int XGetWMClientMachine(
    Display* ,
    Window ,
    XTextProperty*
);
XWMHints *XGetWMHints(
    Display* ,
    Window
);
int XGetWMIconName(
    Display* ,
    Window ,
    XTextProperty*
);
int XGetWMName(
    Display* ,
    Window ,
    XTextProperty*
);
int XGetWMNormalHints(
    Display* ,
    Window ,
    XSizeHints* ,
    long*
);
int XGetWMSizeHints(
    Display* ,
    Window ,
    XSizeHints* ,
    long* ,
    Atom
);
int XGetZoomHints(
    Display* ,
    Window ,
    XSizeHints*
);
int XIntersectRegion(
    Region ,
    Region ,
    Region
);
void XConvertCase(
    KeySym ,
    KeySym* ,
    KeySym*
);
int XLookupString(
    XKeyEvent* ,
    char* ,
    int ,
    KeySym* ,
    XComposeStatus*
);
int XMatchVisualInfo(
    Display* ,
    int ,
    int ,
    int ,
    XVisualInfo*
);
int XOffsetRegion(
    Region ,
    int ,
    int
);
int XPointInRegion(
    Region ,
    int ,
    int
);
Region XPolygonRegion(
    XPoint* ,
    int ,
    int
);
int XRectInRegion(
    Region ,
    int ,
    int ,
    unsigned int ,
    unsigned int
);
int XSaveContext(
    Display* ,
    XID ,
    XContext ,
    const char*
);
int XSetClassHint(
    Display* ,
    Window ,
    XClassHint*
);
int XSetIconSizes(
    Display* ,
    Window ,
    XIconSize* ,
    int
);
int XSetNormalHints(
    Display* ,
    Window ,
    XSizeHints*
);
void XSetRGBColormaps(
    Display* ,
    Window ,
    XStandardColormap* ,
    int ,
    Atom
);
int XSetSizeHints(
    Display* ,
    Window ,
    XSizeHints* ,
    Atom
);
int XSetStandardProperties(
    Display* ,
    Window ,
    const char* ,
    const char* ,
    Pixmap ,
    char** ,
    int ,
    XSizeHints*
);
void XSetTextProperty(
    Display* ,
    Window ,
    XTextProperty* ,
    Atom
);
void XSetWMClientMachine(
    Display* ,
    Window ,
    XTextProperty*
);
int XSetWMHints(
    Display* ,
    Window ,
    XWMHints*
);
void XSetWMIconName(
    Display* ,
    Window ,
    XTextProperty*
);
void XSetWMName(
    Display* ,
    Window ,
    XTextProperty*
);
void XSetWMNormalHints(
    Display* ,
    Window ,
    XSizeHints*
);
void XSetWMProperties(
    Display* ,
    Window ,
    XTextProperty* ,
    XTextProperty* ,
    char** ,
    int ,
    XSizeHints* ,
    XWMHints* ,
    XClassHint*
);
void XmbSetWMProperties(
    Display* ,
    Window ,
    const char* ,
    const char* ,
    char** ,
    int ,
    XSizeHints* ,
    XWMHints* ,
    XClassHint*
);
void Xutf8SetWMProperties(
    Display* ,
    Window ,
    const char* ,
    const char* ,
    char** ,
    int ,
    XSizeHints* ,
    XWMHints* ,
    XClassHint*
);
void XSetWMSizeHints(
    Display* ,
    Window ,
    XSizeHints* ,
    Atom
);
int XSetRegion(
    Display* ,
    GC ,
    Region
);
void XSetStandardColormap(
    Display* ,
    Window ,
    XStandardColormap* ,
    Atom
);
int XSetZoomHints(
    Display* ,
    Window ,
    XSizeHints*
);
int XShrinkRegion(
    Region ,
    int ,
    int
);
int XStringListToTextProperty(
    char** ,
    int ,
    XTextProperty*
);
int XSubtractRegion(
    Region ,
    Region ,
    Region
);
int XmbTextListToTextProperty(
    Display* display,
    char** list,
    int count,
    XICCEncodingStyle style,
    XTextProperty* text_prop_return
);
int XwcTextListToTextProperty(
    Display* display,
    wchar_t** list,
    int count,
    XICCEncodingStyle style,
    XTextProperty* text_prop_return
);
int Xutf8TextListToTextProperty(
    Display* display,
    char** list,
    int count,
    XICCEncodingStyle style,
    XTextProperty* text_prop_return
);
void XwcFreeStringList(
    wchar_t** list
);
int XTextPropertyToStringList(
    XTextProperty* ,
    char*** ,
    int*
);
int XmbTextPropertyToTextList(
    Display* display,
    const XTextProperty* text_prop,
    char*** list_return,
    int* count_return
);
int XwcTextPropertyToTextList(
    Display* display,
    const XTextProperty* text_prop,
    wchar_t*** list_return,
    int* count_return
);
int Xutf8TextPropertyToTextList(
    Display* display,
    const XTextProperty* text_prop,
    char*** list_return,
    int* count_return
);
int XUnionRectWithRegion(
    XRectangle* ,
    Region ,
    Region
);
int XUnionRegion(
    Region ,
    Region ,
    Region
);
int XWMGeometry(
    Display* ,
    int ,
    const char* ,
    const char* ,
    unsigned int ,
    XSizeHints* ,
    int* ,
    int* ,
    int* ,
    int* ,
    int*
);
int XXorRegion(
    Region ,
    Region ,
    Region
);
]]

--[[
#define XDestroyImage(ximage) ((*((ximage)->f.destroy_image))((ximage)))
#define XGetPixel(ximage,x,y) ((*((ximage)->f.get_pixel))((ximage), (x), (y)))
#define XPutPixel(ximage,x,y,pixel) ((*((ximage)->f.put_pixel))((ximage), (x), (y), (pixel)))
#define XSubImage(ximage,x,y,width,height) ((*((ximage)->f.sub_image))((ximage), (x), (y), (width), (height)))
#define XAddPixel(ximage,value) ((*((ximage)->f.add_pixel))((ximage), (value)))

#define IsKeypadKey(keysym) (((KeySym)(keysym) >= XK_KP_Space) && ((KeySym)(keysym) <= XK_KP_Equal))
#define IsPrivateKeypadKey(keysym) (((KeySym)(keysym) >= 0x11000000) && ((KeySym)(keysym) <= 0x1100FFFF))
#define IsCursorKey(keysym) (((KeySym)(keysym) >= XK_Home) && ((KeySym)(keysym) < XK_Select))
#define IsPFKey(keysym) (((KeySym)(keysym) >= XK_KP_F1) && ((KeySym)(keysym) <= XK_KP_F4))
#define IsFunctionKey(keysym) (((KeySym)(keysym) >= XK_F1) && ((KeySym)(keysym) <= XK_F35))
#define IsMiscFunctionKey(keysym) (((KeySym)(keysym) >= XK_Select) && ((KeySym)(keysym) <= XK_Break))
#define IsModifierKey(keysym) ((((KeySym)(keysym) >= XK_Shift_L) && ((KeySym)(keysym) <= XK_Hyper_R)) || (((KeySym)(keysym) >= XK_ISO_Lock) && ((KeySym)(keysym) <= XK_ISO_Last_Group_Lock)) || ((KeySym)(keysym) == XK_Mode_switch) || ((KeySym)(keysym) == XK_Num_Lock))

#define XUniqueContext() ((XContext) XrmUniqueQuark())
#define XStringToContext(string) ((XContext) XrmStringToQuark(string))
]]