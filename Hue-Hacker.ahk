#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode("Mouse", "Screen"), CoordMode("Pixel", "Screen"), CoordMode("Tooltip", "Screen")
appVersion := '26-06-21.164'
iniSettings()
iniGui()
showHKList()
;################################################################################
iniSettings() {
	global
	gDefPxCnt		:= 200								; screen pixels						; default pixel  count for grid single row/col
	gDefSqCnt		:= 39								; grid squares						; default square count for grid single row/col
	gRCSqMin		:= 3, gRCSqMax := 43				; grid squares						; min/max square count for grid single row/col
	gINIFile		:= A_ScriptDir "\HueHacker.ini"											; local ini file (duh!)
	gRCSqCnt		:= IniRead(gINIFile, "Settings", "RCSqCount", gDefSqCnt)				; GRID  square count for grid single row/col
	gRCPxCnt		:= IniRead(gINIFile, "Settings", "RCPxCount", gDefPxCnt)				; SCREEN pixel count for grid single row/col
	gReloaded		:= IniRead(gINIFile, "Settings", "Reloaded"	, 0)						; flag for reloading
	gOffsetX		:= 75, gOffsetY := 75													; pixel distance between mouse and gui
	getScale()		, getLgclTextH(), getRCPxScl()											; set scale, text control height, scaled pixel count
	gWidth			:= gRCPxCnt, gHeight := gRCPxCnt + gLgclTextH							; set gui width and height
	gIsToolActive	:= 0																	; sets whether gui tool is displayed/active or not
}
;################################################################################
getScale() {																				; compensates for screen scaling
	hDC := DllCall("GetDC", "Ptr", 0, "Ptr")
	dpi := DllCall("gdi32\GetDeviceCaps", "Ptr", hDC, "Int", 88, "Int")
	DllCall("ReleaseDC", "Ptr", 0, "Ptr")
	global gScale := dpi / 96
	return gScale
}
;################################################################################
scaled(value) {																				; applies scaling to passed setting
	return value * gScale ;getScale()
}
;################################################################################
getLgclTextH() {																			; sets/returns default text control height (pixels)
	global gLgclTextH := 48
	return gLgclTextH
}
;################################################################################
getRCPxScl() {																				; SCREEN pixel count for grid row/col (scaled)
	global gRCPxScl := Round(gRCPxCnt * gScale)
	return gRCPxScl
}
;################################################################################
noBkgdErase(wParam, lParam, msg, hwnd) {													; prevent background erase (ugly flash)
	return !!(hwnd = gGui.Hwnd)
}
;################################################################################
showGui() {																					; show gui, enable timer for updates
	global gIsToolActive := 1
	MouseGetPos(&mX, &mY), gX := mX + gOffsetX, gY := mY + gOffsetY
	gGui.Show(Format("x{} y{} w{} h{}", gX, gY, gWidth, gHeight))
	SetTimer(updateGrid, 50)
}
;################################################################################
hideGUI() {																					; hide gui, disable updates
	global gIsToolActive := 0
	SetTimer(updateGrid, 0)
	gGui.Hide()
}
;################################################################################
toggleActive() {																			; toggles whether tool is activate or not
	global gIsToolActive
	if (gIsToolActive ^= 1)
		showGui()
	else
		hideGui()
}
;################################################################################
iniGui() {																					; initialize gui (once)
	global
	DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")								; needs to be before Gui ini
	gGui		:= Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")							; gui options
	fontSize	:= (gScale = 1) ? 's7' : 's8'												; ensure text is limited to 3 lines
	gGui.SetFont(fontSize ' cWhite W600', 'Segoe UI')
	txtOpts		:= 'Background000000 +border center +multi '								; options for text control
	gBdrGap		:= 1																		; to control frame drawing
	txtValues	:= gGui.Add("Text", Format(txtOpts "x{} y{} w{} h{}"						; text control to display color details
				, gBdrGap, gRCPxCnt, gWidth-gBdrGap*2, gLgclTextH-gBdrGap))
	iniGrid()																				; grid canvas, for drawing
	OnMessage(0x02E0, WM_DPICHANGED)														; gui detects dpi scaling changes (must follow Gui ini)
	OnMessage(0x0014, noBkgdErase)															; prevent ugly flash when resizing gui
}
;################################################################################
iniGrid() {
	global
	ghGuiDC	 := DllCall("GetDC", "Ptr", gGui.Hwnd, "Ptr")									; device context for Gui (grid)
	ghMGuiDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", ghGuiDC, "Ptr")					; device context for scratchpad
	ghMemBM	 := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", ghGuiDC						; canvas associated with gui window
				, "Int", gRCPxScl, "Int", gRCPxScl, "Ptr")
	ghOldBM	 := DllCall("gdi32\SelectObject", "Ptr", ghMGuiDC, "Ptr", ghMemBM, "Ptr")		; scratchpad canvas
}
;################################################################################
showHKList() {
	if (gReloaded) {																		; if script is being reloaded...
		IniWrite(0, gINIFile, "Settings", "Reloaded")										; ... reset flag
		showGui()																			; show gui, not HK list
		return
	}
	msg :=  "SHORTCUT`t`tFUNCTION`n`n"
		.	"[ F8 ]`t`t`tToggle Tool On/Off`n"
		.	"[ Alt + C ]`t`t`tCopy ALL info to clipboard`n"
		.	"[ Alt + H ]`t`t`tCopy HEX value to clipboard`n"
		.	"[ Alt + S ]`t`t`tShow Shortcuts list (this)`n"
		.	"[ Arrow Keys ]`t`tFine-tune mouse position`n"
		.	"[ Shift + Arrows/Wheel ]`tResize window/view`n"
		.	"[ Ctrl  + Arrows/Wheel ]`tAdjust magnification`n"
		.	"[ Ctrl  + Escape ]`t`tQuit Tool"
	MsgBox(msg, "Hue-Hacker " StrReplace(appVersion,'-'))
}
;################################################################################
; allows gui to detect dpi changes on the fly, which initiates a script reload
WM_DPICHANGED(wParam, lParam, msg, hwnd) {
	dpi := (wParam >> 16) & 0xFFFF															; wParam HIWORD - new Y-axis DPI
	IniWrite(1, gINIFile, "Settings", "Reloaded")											; flag to show Gui and not HK list during reload
	Reload()																				; reload script to use new scaling
}
;################################################################################
cleanup() {
	DllCall("gdi32\SelectObject", "Ptr", ghMGuiDC, "Ptr", ghOldBM, "Ptr")
	DllCall("gdi32\DeleteObject", "Ptr", ghMemBM)
	DllCall("gdi32\DeleteDC", "Ptr", ghMGuiDC)
	DllCall("ReleaseDC", "Ptr", gGui.Hwnd, "Ptr", ghGuiDC)
}
;################################################################################
; used to prevent updates to gui unless a change has occurred
hasUpdated() {																				; for change detection
	static lastX := '', lastY := '', lastRCPxCnt := '', lastRCSqCnt := ''
	MouseGetPos(&mX, &mY)																	; get current mouse position
	if (lastX=mX && lastY=mY && lastRCPxCnt=gRCPxCnt && lastRCSqCnt=gRCSqCnt)				; if NO change has occurred...
		return false																		; ...notify caller
	lastX:=mx,lastY:=mY,lastRCPxCnt:=gRCPxCnt,lastRCSqCnt:=gRCSqCnt							; save values for comparison next visit
	return true																				; change HAS occurred
}
;################################################################################
updateGrid() {																				; updates grid using a timer
	static c := 0
	;if (!hasUpdated()) {																	; if no changes are detected...
	;	return				; interferes with updates during scrolling (darn!)				; ... no need for update
	;}
	MouseGetPos(&mX, &mY)																	; get current mouse position
	getRCPxScl()																			; ensure gRCPxScl is updated
	pxPerSqr	:= gRCPxScl / gRCSqCnt														; pixels per grid square
	halfGrid	:= Floor(gRCSqCnt / 2)														; number of GRID SQUARES on either side of center
	cStart		:= Floor(halfGrid * pxPerSqr)												; number of PIXELS on either side of center
	cEnd		:= cStart + Ceil(pxPerSqr)													; include center square also

	; get src and dest coords, width, height for drawing
	; also need to make adjustments at screen edges
	srcX := mX - halfGrid, srcY := mY - halfGrid											; coords that will begin screen capture
	dstX := 0, dstY := 0, drawW := gRCSqCnt, drawH := gRCSqCnt
	if (srcX < 0)
		dstX := Round(Abs(srcX) * pxPerSqr), drawW -= Abs(srcX), srcX := 0
	if (srcY < 0)
		dstY := Round(Abs(srcY) * pxPerSqr), drawH -= Abs(srcY), srcY := 0
	maxW := DllCall("User32\GetSystemMetrics", "Int", 78, "Int")
	maxH := DllCall("User32\GetSystemMetrics", "Int", 79, "Int")
	if (srcX + drawW > maxW)
		drawW := maxW - srcX
	if (srcY + drawH > maxH)
		drawH := maxH - srcY

	; draw to grid canvas
	DllCall("gdi32\BitBlt", "Ptr", ghMGuiDC, "Int", 0, "Int", 0, "Int", gRCPxScl			; start with black grid canvas
		, "Int", gRCPxScl, "Ptr", 0, "Int", 0, "Int", 0, "UInt", 0x00000042)
	hScrnDC := DllCall("GetDC", "Ptr", 0, "Ptr")											; get screen device context
	DllCall("gdi32\StretchBlt",																; stretch screen image onto grid canvas
		"Ptr", ghMGuiDC,
		"Int", dstX, "Int", dstY,
		"Int", Round(drawW * pxPerSqr),
		"Int", Round(drawH * pxPerSqr),
		"Ptr", hScrnDC,
		"Int", srcX,
		"Int", srcY,
		"Int", drawW, "Int", drawH,
		"UInt", 0x00CC0020
	)
	targClr	:= DllCall("GetPixel", "Ptr", hScrnDC, "Int", mX, "Int", mY, "UInt")			; get pixel color at mouse pointer
	clrs	:= getColors(targClr)															; process/return color details
	updateText(mX,mY,clrs)																	; update text details
	drawCrossHairs(clrs.xHairClr, cStart, cEnd)												; draw cross-hairs to grid canvas
	HL_CtrPixel(cStart,cEnd)																; highlight center square
	HL_GuiFrame()					; must be done after text update						; add contrast frame to gui
	DllCall("gdi32\BitBlt", "Ptr", ghGuiDC, "Int", 0, "Int", 0, "Int", gRCPxScl, "Int"		; transfer all updates to Gui canvas
			, gRCPxScl, "Ptr", ghMGuiDC, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
	DllCall("ReleaseDC", "Ptr", 0, "Ptr", hScrnDC)											; discard screen DC resource
	updateGuiPos()																			; move gui relative to mouse position
}
;################################################################################
updateGuiPos() {																			; reposition gui relative to mouse pos

	static xDir := 0, yDir := 0
	if (!isSizeOk())																		; if gui is too big for auto-wrapping...
		resizeGui(0)																		; ... resize gui

	MouseGetPos(&mX, &mY)																	; get current mouse coords
	WinGetPos(&rX, &rY, &rW, &rH, gGui.Hwnd)												; get SCALED gui dimensions
	maxW := DllCall("User32\GetSystemMetrics", "Int", 78, "Int")							; get screen boundary - right
	maxH := DllCall("User32\GetSystemMetrics", "Int", 79, "Int")							; get screen boundary - bottom
	minX := DllCall("User32\GetSystemMetrics", "Int", 76, "Int")							; get screen boundary - left
	minY := DllCall("User32\GetSystemMetrics", "Int", 77, "Int")							; get screen boundary - top

	; most of this is to detect when gui is at screen ...
	; ... boundaries, preventing it from going off screen

	targX := mX + gOffsetX
	if (xDir = 0) {
		if (targX + rW > minX + maxW) {
			gX := mX - rW - gOffsetX, xDir := 1
		} else {
			gX := targX, xDir := 0
		}
	} else if (xDir = 1) {
		if (rX < minX + 1) {
			gX := targX, xDir := 0
		} else {
			gX := mX - rW - gOffsetX, xDir := 1
		}
	}

	targY := mY + gOffsetY
	if (yDir = 0) {
		if (targY + rH > minY + maxH) {
			gY := mY - rH - gOffsetY, yDir := 1
		} else {
			gY := targY, yDir := 0
		}
	} else if (yDir = 1) {
		if (rY < minY + 1) {
			gY := targY, yDir := 0
		} else {
			gY := mY - rH - gOffsetY, yDir := 1
		}
	}

	; prevent rare errors
	if (gX < minX)
		gX := minX
	if (gY < minY)
		gY := minY
	if (gX + rW > minX + maxW)
		gX := (minX + maxW) - rW
	if (gY + rH > minY + maxH)
		gY := (minY + maxH) - rH

	WinMove(gX, gY, , , gGui.Hwnd)
}
;################################################################################
resizeGui(delta) {
	global gRCPxCnt, gWidth, gHeight
	h		:= getHeights()
	NewSize	:= (!isSizeOk()) ? gDefPxCnt													; resize to default value if too-big
			: ((delta < 1 || h.curH + delta < h.maxH) ? gRCPxCnt + delta : 0)				; prevent enlargement if at max size
	if (NewSize < 100)																		; prevent text font from being clipped
		return
	getLgclTextH(), gWidth := gRCPxCnt := NewSize, gHeight := gRCPxCnt + gLgclTextH
	updateGridImage(), gGui.Move(,,gWidth,gHeight)
	txtValues.Move(gBdrGap, gRCPxCnt, gWidth - gBdrGap*2, gLgclTextH - gBdrGap)
	IniWrite(gRCPxCnt, gINIFile, "Settings", "RCPxCount")
}
;################################################################################
updateText(x,y,clrs) {																		; updates text area of display
	xyStr			:= Format("XY {},{}", x, y)												; XY coords  of target pixel
	rgbStr			:= Format("RGB {},{},{}", clrs.r, clrs.g, clrs.b)						; RGB colors of target pixel
	rawHex			:= Format("{:02X}{:02X}{:02X}", clrs.r, clrs.g, clrs.b)					; hex colors of target pixel
	hexStr			:= "HEX " rawHex														; hex string for display
	txtValues.Value	:= xyStr "`n" rgbStr "`n" hexStr										; update text control
	txtValues.Opt("Background" rawHex " c" clrs.txtFrmClr)									; set font color and display target color
}
;################################################################################
updateGridImage() {																			; update mem buffer for grid
	global ghGuiDC, ghMGuiDC, ghMemBM, ghOldBM
	gRCPxScl:= Round(scaled(gRCPxCnt))
	DllCall("ReleaseDC", "Ptr", gGui.Hwnd, "Ptr", ghGuiDC)
	ghGuiDC	:= DllCall("GetDC", "Ptr", gGui.Hwnd, "Ptr")
	DllCall("gdi32\SelectObject", "Ptr", ghMGuiDC, "Ptr", ghOldBM, "Ptr")
	DllCall("gdi32\DeleteObject", "Ptr", ghMemBM)
	ghMemBM := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", ghGuiDC
			, "Int", gRCPxScl, "Int", gRCPxScl, "Ptr")
	ghOldBM := DllCall("gdi32\SelectObject", "Ptr", ghMGuiDC, "Ptr", ghMemBM, "Ptr")
}
;################################################################################
; splits targ color into rgb, calcs best colors for cross-hairs, text, frames
getColors(targClr) {
	r			:=  targClr			& 0xFF													; extract red   component
	g			:= (targClr >> 8)	& 0xFF													; extract green component
	b			:= (targClr >> 16)	& 0xFF													; extract blue  component
	luminance	:= calcLum(r,g,b)															; calc luminance value
	txtFrmClr	:= (luminance > 150) ? "000000" : "FFFFFF"									; set text frame and font color for best contrast
	xHairClr	:= 0x808080																	; cross-hairs are mid gray by default
	if (isMidGray(r,g,b))																	; if target color is mid gray...
		xHairClr:= (luminance > 128) ? 0x000000 : 0xFFFFFF									; ... adj cross-hair color for best contrast
	return {r:r,g:g,b:b,xHairClr:xHairClr,txtFrmClr:txtFrmClr}								; return values in obj
}
;################################################################################
; returns whether rgb values are within mid gray range
isMidGray(r,g,b) {
	lv:=100, hv:=156																		; luminosity range considered medium gray
	return (r>=lv && r<=hv && g>=lv && g<=hv && b>=lv && b<=hv)
}
;################################################################################
calcLum(r,g,b) {																			; calculate general luminosity level of rgb
	return (0.299 * r) + (0.587 * g) + (0.114 * b)
}
;################################################################################
HL_GuiFrame() {																				; draws white and black frame around gui
	WinGetClientPos(&x, &y, &w, &h, gGui.Hwnd)												; provides SCALED values for gui
	; create white, black brushes
	hBrushW	:= DllCall("gdi32\CreateSolidBrush", "UInt", 0xFFFFFF, "Ptr")					; white brush
	hBrushB	:= DllCall("gdi32\CreateSolidBrush", "UInt", 0x000000, "Ptr")					; black brush
	; draw white frame around entire gui
	hDC		:= DllCall("GetDC", "Ptr", gGui.Hwnd, "Ptr")									; get DC for full Gui
	rectW	:= Buffer(16, 0)																; rectangle struct
	NumPut("Int", 0, "Int", 0, "Int", w, "Int", h, rectW)									; place coords in rect struct
	DllCall("FrameRect", "Ptr", hDC, "Ptr", rectW, "Ptr", hBrushW)							; draw white frame to gui DC
	; draw white frame inside just grid area
	rectW	:= Buffer(16, 0)																; rectangle struct
	NumPut("Int", 0, "Int", 0, "Int", gRCPxScl, "Int", gRCPxScl, rectW)						; place coords in rect struct
	DllCall("FrameRect", "Ptr", ghMGuiDC, "Ptr", rectW, "Ptr", hBrushW)						; draw white frame around grid area
	; draw black frame inside white frame of grid area
	rectB := Buffer(16, 0)																	; rectangle struct
	NumPut("Int", 1, "Int", 1, "Int", gRCPxScl-1, "Int", gRCPxScl-1, rectB)					; place coords in rect struct
	DllCall("user32\FrameRect", "Ptr", ghMGuiDC, "Ptr", rectB, "Ptr", hBrushB)				; draw black frame around grid area
	; cleanup resources
	DllCall("gdi32\DeleteObject", "Ptr", hBrushW)
	DllCall("gdi32\DeleteObject", "Ptr", hBrushB)
}
;################################################################################
HL_CtrPixel(cStart, cEnd) {																	; draws highlight box to center of grid canvas
	; create white, black brushes
	hBrushW	:= DllCall("gdi32\CreateSolidBrush", "UInt", 0xFFFFFF, "Ptr")
	hBrushB := DllCall("gdi32\CreateSolidBrush", "UInt", 0x000000, "Ptr")
	; draw white square in center of grid
	rectW := Buffer(16, 0)
	NumPut("Int", cStart, "Int", cStart, "Int", cEnd + 1, "Int", cEnd + 1, rectW)
	DllCall("user32\FrameRect", "Ptr", ghMGuiDC, "Ptr", rectW, "Ptr", hBrushW)
	;draw black square in center of grid
	rectB := Buffer(16, 0)
	NumPut("Int", cStart + 1, "Int", cStart + 1, "Int", cEnd, "Int", cEnd, rectB)
	DllCall("user32\FrameRect", "Ptr", ghMGuiDC, "Ptr", rectB, "Ptr", hBrushB)
	; cleanup resources
	DllCall("gdi32\DeleteObject", "Ptr", hBrushW)
	DllCall("gdi32\DeleteObject", "Ptr", hBrushB)
}
;################################################################################
drawCrossHairs(color, cStart, cEnd) {														; draws cross hairs to grid canvas
	hPen	:= DllCall("gdi32\CreatePen", "Int", 0, "Int", 1, "UInt", color, "Ptr")
	hOldPen	:= DllCall("gdi32\SelectObject", "Ptr", ghMGuiDC, "Ptr", hPen, "Ptr")
	DllCall("gdi32\MoveToEx", "Ptr", ghMGuiDC, "Int", 0, "Int", cStart, "Ptr", 0)
	DllCall("gdi32\LineTo", "Ptr", ghMGuiDC, "Int", gRCPxScl, "Int", cStart)
	DllCall("gdi32\MoveToEx", "Ptr", ghMGuiDC, "Int", 0, "Int", cEnd, "Ptr", 0)
	DllCall("gdi32\LineTo", "Ptr", ghMGuiDC, "Int", gRCPxScl, "Int", cEnd)
	DllCall("gdi32\MoveToEx", "Ptr", ghMGuiDC, "Int", cStart, "Int", 0, "Ptr", 0)
	DllCall("gdi32\LineTo", "Ptr", ghMGuiDC, "Int", cStart, "Int", gRCPxScl)
	DllCall("gdi32\MoveToEx", "Ptr", ghMGuiDC, "Int", cEnd, "Int", 0, "Ptr", 0)
	DllCall("gdi32\LineTo", "Ptr", ghMGuiDC, "Int", cEnd, "Int", gRCPxScl)
	DllCall("gdi32\SelectObject", "Ptr", ghMGuiDC, "Ptr", hOldPen)
	DllCall("gdi32\DeleteObject", "Ptr", hPen)
}
;################################################################################
isSizeOk() {																				; helps prevent flip-flop repositioning of gui
	h := getHeights()
	return	h.curH < h.maxH
}
;################################################################################
getHeights() {																				; returns cur height of gui max height allowed
	padding	:= 0
	maxH	:= floor((A_ScreenHeight/2)-(gOffsetY/2)-padding)
	curH	:= Round(scaled(gHeight) + gOffsetY)
	return	{curH:curH,maxH:maxH}
}
;################################################################################
zoomIn() {																					; increases magnification
	global gRCSqCnt
	if (gRCSqCnt > gRCSqMin)
		gRCSqCnt -= 2, IniWrite(gRCSqCnt, gINIFile, "Settings", "RCSqCount")
}
;################################################################################
zoomOut() {																					; decreases magnification
	global gRCSqCnt
	if (gRCSqCnt < gRCSqMax)
		gRCSqCnt += 2, IniWrite(gRCSqCnt, gINIFile, "Settings", "RCSqCount")
}
;################################################################################
copyToClip(hk) {																			; very basic copy of details to clipboard
	A_Clipboard := extractInfo(txtValues.value, hk)
	SoundBeep(1000,50), txtValues.Opt("Background00FF00 c000000")
	SetTimer(() => txtValues.Opt("Background000000 cFFFFFF"), -150)
}
;################################################################################
extractInfo(info,key) {																		; used to extract particular details from full info
	line := StrSplit(info, '`n', '`r')
	if (key = '!h')
		return RegExReplace(line[3], '.+(\w{2}):(\w{2}):(\w{2})$', '$1$2$3')
	return info
}
;################################################################################
#HotIf			gIsToolActive																; hotkeys only work when tool is active
+Up::
+Right::
+WheelUp::		resizeGui(10)
+Down::
+Left::
+WheelDown::	resizeGui(-10)
^Up::
^WheelUp::		zoomIn()
^Down::
^WheelDown::	zoomOut()
Up::			MouseMove(0, -1, 0, "R")
Down::			MouseMove(0, 1, 0, "R")
Left::			MouseMove(-1, 0, 0, "R")
Right::			MouseMove(1, 0, 0, "R")
!h::
!c::			copyToClip(A_ThisHotkey)
#HotIf																						; hotkeys work whether tool is active or not
^Esc::			cleanup(),ExitApp()
F8::			toggleActive()
#HotIf			(!WinActive("ahk_class #32770"))											; do not show HK list if currently displayed
!s::			showHKList()
#HotIf