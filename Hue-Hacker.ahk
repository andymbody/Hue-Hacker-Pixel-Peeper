/*
	App:	Hue-Hacker Pixel-Peeper
	Author:	andymbody
	Date:	2026-06-28
	GitHub:	https://github.com/andymbody/Hue-Hacker-Pixel-Peeper
	Forum:	https://www.autohotkey.com/boards/viewtopic.php?f=83&t=140824
*/
#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode('Mouse', 'Screen'), CoordMode('Pixel', 'Screen')
gAppVers := '26-06-28.210'
AppIni()																						; initialize application
;################################################################################
AppClose() {
	gGui.GdiCleanup(), cfg.CancelSave(), cfg.SaveToDisk(), ExitApp()							; force save any pending config data, quit app
}
;################################################################################
AppIni() {
	global
	gInitialized := 0																			; disable hotkeys
		getScale()																				; grab dpi scaling from system
		getVirtualDimensions()																	; grab virtual display dimensions (for multi-display support)
		cfg := clsSettings()																	; grab setting from ini file
		guiSplashShow()																			; show animated splash screen
		DllCall('SetThreadDpiAwarenessContext', 'ptr', -4, 'ptr')								; needs to be before Gui ini
		gGui := clsGrid()																		; initialize grid gui using custom Gui class
		loadIcon()																				; load icon as Base64
		DllCall('RegisterShellHookWindow', 'Ptr', gGui.Hwnd)									; setup win hook
		OnMessage(DllCall('RegisterWindowMessage', 'Str', 'SHELLHOOK'), shellMessage)			; setup notification for active win changes
		OnMessage(0x0201, WM_LBUTTONDOWN)														; enable click/drag anywhere in HK or grid gui
		(cfg.Grab('ShowHKs')) && guiHKListShow()												; show shortcuts list (if enabled)
	gInitialized := 1																			; enable hotkeys
}
;################################################################################
; clsSettings - management for custom user settings and .ini operations
; provides much better performance than using standard ahk IniRead/Write
class clsSettings
{
	_svd			:= ObjBindMethod(this, 'SaveToDisk')										; required to use method with SetTimer
	_cache			:= Map()																	; settings Map
	_toDisk			:= 0																		; flag to signal that changes have not been saved to disk yet
	_iniFile		:= A_ScriptDir '\HueHacker.ini'												; ini file to write to
	;_iniFile		:= 'E:' '\HueHacker.ini'			; thumb-drive for testing				; ini file to write to
	;############################################################################
	__New() {																					; constructor
		this._getINI()
	}
	;############################################################################
	; add adjustable user settings here as needed
	_getDefVals() {																				; hard coded default values
		this._cache['SkinClr' ] := '202020'														; gui skin bkgd color
		this._cache['ShowHKs' ] := '1'															; whether to show HK list at startup
		this._cache['HKListX' ] := ''															; custom X position for HK list
		this._cache['HKListY' ] := ''															; custom Y position for HK list
		this._cache['RCSqCnt' ] := ''															; GRID  square count for grid single row/col (zoom factor)
		this._cache['RCPxCnt' ] := ''															; SCREEN pixel count for grid single row/col (win size)
		this._cache['GridLock'] := '0'															; whether grid gui is locked in static position
		this._cache['GridPosX'] := ''															; grid gui static position X
		this._cache['GridPosY'] := ''															; grid gui static position Y
	}
	;############################################################################
	CancelSave() {																				; prevents pending ini write
		SetTimer(this._svd, 0)																	; cancel pending ini writes
	}
	;############################################################################
	_getINI() {																					; get initial INI settings, from file if possible
		ws := ' `t`r`n'																			; trim options
		this._cache := Map(), this._cache.CaseSense := 0										; initialize map as case-insensitive
		this._getDefVals()																		; get default values
		if (!FileExist(this._iniFile) && FileExist(this._iniFile '.tmp'))						; if a temp file is found instead of the .ini file...
			FileMove(this._iniFile '.tmp', this._iniFile)										; ... recover from a failed swap
		if (!FileExist(this._iniFile))															; if ini file does not exist...
			return																				; ... default values will be used
		contents := FileRead(this._iniFile)														; read contents of ini file
		for ik, line in StrSplit(contents,'`n','`r') {											; get each line of file
			ss := StrSplit(line,'=',,2)															; get each setting and value
			if (ss.Length > 1)																	; [this check may not be needed]
				this._cache[Trim(ss[1],ws)] := Trim(ss[2],ws)									; add setting/val to map, trim first
		}
	}
	;############################################################################
	Grab(key) {															; Public				; returns value for setting, if available
		if (this._cache.Has(key))																; if key is found...
			return this._cache[key]																; ... return its value
		return ''																				; otherwise use empty string as return val
	}
	;############################################################################
	Save(key,val,toIni:=1) {											; Public				; saves setting to map, flags need to write to disk
		prevVal := ''																			; val to return if key has no previous value
		if (this._cache.Has(key))																; if key is found...
			prevVal := this._cache[key]															; ... record previous value
		if (prevVal != val) {																	; if new value does not match prev value...
			this._cache[key] := val																; ... save new val to map
			if (toIni) {																		; if setting should be written to ini file...
				this._toDisk := 1, SetTimer(this._svd, -3000)									; ... prep for delayed ini write
			} else {																			; otherwise...
				this._toDisk := 0, this.CancelSave()											; ... cancel/prevent ini write (will be done manually)
			}
		}
		return prevVal																			; return previous value to caller
	}
	;############################################################################
	_saveAtomic(srcStr) {																		; minimized corruptions during crashes
		tempFile := this._iniFile '.tmp'														; temp file path (add temp extension)
		try FileDelete(tempFile)								; just in case					; delete temp file if it exists (it should not)
		try {
			FileAppend(srcStr,tempFile,'UTF-8')													; write data to temp file
			FileMove(tempFile,this._iniFile,1)					; force overwrite				; rename temp file as .ini file
		}
	}
	;############################################################################
	SaveToDisk(force:=0) {																		; saves all settings to disk, if any have changed
		if (!force && !this._toDisk)															; if no settings have changed...
			return																				; ... no need to save to disk
		this._toDisk := 0																		; reset flag first to prevent double-dipping
		saveStr		 := ''																		; ini output str
		for key, val in this._cache																; for each setting in map...
			saveStr .= key '=' val '`r`n'														; ... add key/val to output str
		this._saveAtomic(saveStr)																; save data using reliable atomic method
	}
}
;################################################################################
; clsGrid - Main Tool Gui
;################################################################################
class clsGrid extends Gui
{
	OffsetX		:= 75, OffsetY := 75															; pixel distance between mouse and gui
	txtInfoH	:= 48																			; initial height of text display control
	txtStusH	:= 22																			; status bar text height
	DefPxCnt	:= 200								; screen pixels								; default PIXEL  count for grid single row/col
	DefSqCnt	:= 39								; grid squares								; default SQUARE count for grid single row/col
	RCSqMin		:= 3, RCSqMax := 43					; grid squares								; min/max square count for grid single row/col
	RCSqCnt		:= (cfg.Grab('RCSqCnt')) ?  (cfg.Grab('RCSqCnt')) : this.DefSqCnt				; GRID  square count for grid single row/col
	RCPxCnt		:= (cfg.Grab('RCPxCnt')) ?  (cfg.Grab('RCPxCnt')) : this.DefPxCnt				; SCREEN pixel count for grid single row/col
	RCPxScl		=> Round(scaled(this.RCPxCnt))													; SCREEN pixel count for grid single row/col (scaled)
	PxH			=> this.RCPxCnt + this.txtInfoH + this.txtStusH									; initial gui height
	PxW			:= this.RCPxCnt																	; initial gui width
	isActive	:= 0																			; whether tool is active/visible or not
	GridLock	:= 0																			; whether grid gui is locked in static pos
	txtInfo		:= ''																			; control to display color details
	textFrgd	:= ''																			; text font color
	textBkgd	:= ''																			; text bkgd color (hex format)
	clrInfo		:= unset																		; all color info
	BdrGap		:= 1																			; gui frame thickness
	txtW		=> this.PxW - (this.BdrGap * 2)													; width  for status bar text and info text
	txtStusY	=> this.RCPxCnt + this.txtInfoH - this.BdrGap									; height for status bar text
	winX		:= 0																			; gui X pos
	winY		:= 0																			; gui Y pos
	;############################################################################
	__New() {
		super.__new('+AlwaysOnTop -Caption +ToolWindow +E0x20')									; pass options to papa
		global ghGrid := this.hwnd																; use global var for performance reasons
		this._customIni()																		; custom ini for gui
	}
	;############################################################################
	_activeWinChanged() {																		; returns whether active window has changed
		static prevWin := ''																	; used for comparisons
		curWin := WinActive('A')																; get current active window
		if (curWin != prevWin) {																; if active win has changed...
			prevWin := curWin																	; ... save cur active win for comparison next visit
			return true																			; ... flag caller that win has changed
		}
		return false																			; active win has NOT changed
	}
	;############################################################################
	_customIni() {
		fontSize	:= (gScale = 1) ? 's7' : 's8'												; ensure text is limited to 3 lines
		this.SetFont(fontSize ' cWhite W600', 'Segoe UI')
		txtOpts		:= ' +border Background000000 center +multi '								; options for text control
		txtH		:= this.txtInfoH-this.BdrGap
		this.txtInfo:= this.Add('Text', Format(txtOpts ' x{} y{} w{} h{}'						; control to display color details
					, this.BdrGap, this.RCPxCnt, this.txtW, txtH))
		skinClr		:= cfg.Grab('SkinClr')
		txtOpts		:= ' 0x0200 -border Background' skinClr										; options for status bar text
		this.txtStus:= this.Add('Text', Format(txtOpts ' x{} y{} w{} h{}'						; status bar text control
					, this.BdrGap, this.txtStusY, this.txtW, this.txtStusH))
		this.GridLock:= cfg.Grab('GridLock')													; get cur setting for grid window lock
		this.winX	:= cfg.Grab('GridPosX'), this.winY := cfg.Grab('GridPosY')					; get cur setting for grid window x/y
		this.UpdateStatus()																		; update status bar (lock status)
		this._gdiIni()																			; grid canvas, for drawing
		this.GridUpdateCB := ObjBindMethod(this, 'UpdateGrid')									; required to use method for SetTimer
		OnMessage(0x02E0, WM_DPICHANGED)														; gui detects dpi scaling changes (must follow Gui ini)
		OnMessage(0x0014, guiPreventBkgdErase)													; prevent ugly flash when resizing gui
	}
	;############################################################################
	CopyToClip(hk) {																			; very basic copy of details to clipboard (for now)
		A_Clipboard := this._extractInfo(this.txtInfo.value, hk)								; put details in clipboard
		SoundBeep(1000,50), this.txtInfo.Opt('Background00FF00 c000000')						; audible/visual confirmation
		bClr := 'Background' this.textBkgd, fClr := ' c' this.textFrgd							; grab current font and bkgd colors
		SetTimer(() => this.txtInfo.Opt(bClr fClr), -150)										; reset font and bkgd colors
	}
	;############################################################################
	DrawCrossHairs(color, cStart, cEnd) {														; draws cross hairs to grid canvas
		global ghMGuiDC
		RCPxScl := this.RCPxScl
		hPen	:= DllCall('CreatePen', 'Int', 0, 'Int', 1, 'UInt', color, 'Ptr')
		hOldPen	:= DllCall('SelectObject', 'Ptr', ghMGuiDC, 'Ptr', hPen, 'Ptr')
		DllCall('MoveToEx', 'Ptr', ghMGuiDC, 'Int', 0, 'Int', cStart, 'Ptr', 0)
		DllCall('LineTo', 'Ptr', ghMGuiDC, 'Int', RCPxScl, 'Int', cStart)
		DllCall('MoveToEx', 'Ptr', ghMGuiDC, 'Int', 0, 'Int', cEnd, 'Ptr', 0)
		DllCall('LineTo', 'Ptr', ghMGuiDC, 'Int', RCPxScl, 'Int', cEnd)
		DllCall('MoveToEx', 'Ptr', ghMGuiDC, 'Int', cStart, 'Int', 0, 'Ptr', 0)
		DllCall('LineTo', 'Ptr', ghMGuiDC, 'Int', cStart, 'Int', RCPxScl)
		DllCall('MoveToEx', 'Ptr', ghMGuiDC, 'Int', cEnd, 'Int', 0, 'Ptr', 0)
		DllCall('LineTo', 'Ptr', ghMGuiDC, 'Int', cEnd, 'Int', RCPxScl)
		DllCall('SelectObject', 'Ptr', ghMGuiDC, 'Ptr', hOldPen)
		DllCall('DeleteObject', 'Ptr', hPen)
	}
	;############################################################################
	_extractInfo(info,key) {																	; used to extract particular details from full info
		if (key != '!h') 																		; if user did NOT press shortcut for HEX...
			return info																			; ... return ALL info
		line := StrSplit(info, '`n', '`r')														; get all lines from text
		return RegExReplace(line[3], '^.+(\w{2}):(\w{2}):(\w{2})$', '$1$2$3')					; return just hex color info
	}
	;############################################################################
	_gdiIni() {																					; ini drawing surfaces
		global ghGuiDC, ghMGuiDC, ghMemBM, ghOldBM												; global vars help improve performance
		ghGuiDC := 0, ghMGuiDC := 0, ghMemBM := 0, ghOldBM := 0									; ini
		this._gdiUpdate()																		; let _gdiUpdate handle the rest
	}
	;############################################################################
	_gdiUpdate() {                                                                              ; update canvas for grid
		global ghGuiDC, ghMGuiDC, ghMemBM, ghOldBM                                              ; global vars help improve performance
		RCPxScl := this.RCPxScl
		this.GdiCleanup()																		; cleanup previous allocations first
		; fresh sizing matrix
		ghGuiDC  := DllCall('GetDC', 'Ptr', ghGrid, 'Ptr')
		ghMGuiDC := DllCall('CreateCompatibleDC', 'Ptr', ghGuiDC, 'Ptr')
		ghMemBM  := DllCall('CreateCompatibleBitmap', 'Ptr', ghGuiDC
					, 'Int', RCPxScl, 'Int', RCPxScl, 'Ptr')
		ghOldBM  := DllCall('SelectObject', 'Ptr', ghMGuiDC, 'Ptr', ghMemBM, 'Ptr')
	}
	;############################################################################
	GdiCleanup() {																				; release gdi resources
		global ghGuiDC, ghMGuiDC, ghMemBM, ghOldBM												; global vars help improve update performance
		DllCall('SelectObject', 'Ptr', ghMGuiDC, 'Ptr', ghOldBM, 'Ptr')
		DllCall('DeleteObject', 'Ptr', ghMemBM)
		DllCall('DeleteDC', 'Ptr', ghMGuiDC)
		DllCall('ReleaseDC', 'Ptr', ghGrid, 'Ptr', ghGuiDC)
	}
	;############################################################################
	_getClrInfo(srcClr) {																		; splits targ color into rgb, calcs best colors for cross-hairs, text, frames
		c := clsGrid.Clr.RGBLH(srcClr)															; get rgb, luminance, hex values
		;ToolTip("lum := " c.L)																	; TEMP DEBUG
		txtFClr		:= (c.L > 145) ? '000000' : 'FFFFFF'										; set text frame and font color for best contrast
		xHairClr	:= 0x808080																	; cross-hairs are mid gray by default
		if (clsGrid.Clr.isMidGray(c.R,c.G,c.B))													; if target color is mid gray...
			xHairClr:= (c.L > 128) ? 0x000000 : 0xFFFFFF										; adj cross-hair color for best contrast
		this.clrInfo:= {Clr:c,xHairClr:xHairClr,txtFClr:txtFClr}								; save for later use
		return this.clrInfo
	}
	;############################################################################
	_getHeights() {																				; returns cur height and gui max height allowed
		padding	:= 10
		maxH	:= floor((gVD.vH/2)-(gGui.OffsetY/2)-padding)									; 2026-06-27, use virtual height instead of A_ScreenHeight
		curH	:= Round(scaled(gGui.PxH) + gGui.OffsetY)
		return	{curH:curH,maxH:maxH}
	}
	;############################################################################
	HideGUI() {																					; hide grid gui, disable updates
		this.IsActive := 0
		SetTimer(this.GridUpdateCB, 0)
		guiWinFade(this, 2, 750)
		this.Hide()
	}
	;############################################################################
	HL_CenterPx(cStart, cEnd) {																	; draws highlight box to center of grid canvas
		global ghMGuiDC
		; create white, black brushes
		hBrushW	:= DllCall('CreateSolidBrush', 'UInt', 0xFFFFFF, 'Ptr')
		hBrushB := DllCall('CreateSolidBrush', 'UInt', 0x000000, 'Ptr')
		; draw white square in center of grid
		rectW := Buffer(16, 0)
		NumPut('Int', cStart, 'Int', cStart, 'Int', cEnd + 1, 'Int', cEnd + 1, rectW)
		DllCall('FrameRect', 'Ptr', ghMGuiDC, 'Ptr', rectW, 'Ptr', hBrushW)
		; draw black square in center of grid
		rectB := Buffer(16, 0)
		NumPut('Int', cStart + 1, 'Int', cStart + 1, 'Int', cEnd, 'Int', cEnd, rectB)
		DllCall('FrameRect', 'Ptr', ghMGuiDC, 'Ptr', rectB, 'Ptr', hBrushB)
		; cleanup resources
		DllCall('DeleteObject', 'Ptr', hBrushW)
		DllCall('DeleteObject', 'Ptr', hBrushB)
	}
	;############################################################################
	HL_Frame() {																				; draws white and black frame around gui
		global ghMGuiDC
		WinGetClientPos(&x, &y, &w, &h, ghGrid)													; provides SCALED values for gui
		; create white, black brushes
		hBrushW	:= DllCall('CreateSolidBrush', 'UInt', 0xFFFFFF, 'Ptr')							; white brush
		hBrushB	:= DllCall('CreateSolidBrush', 'UInt', 0x000000, 'Ptr')							; black brush
		; draw white frame around entire gui
		hDC		:= DllCall('GetDC', 'Ptr', ghGrid, 'Ptr')										; get DC for full Gui
		rectW	:= Buffer(16, 0)																; rectangle struct
		NumPut('Int', 0, 'Int', 0, 'Int', w, 'Int', h, rectW)									; place coords in rect struct
		DllCall('FrameRect', 'Ptr', hDC, 'Ptr', rectW, 'Ptr', hBrushW)							; draw white frame to gui DC
		; draw white frame inside just grid area
		rectW	:= Buffer(16, 0)																; rectangle struct
		NumPut('Int', 0, 'Int', 0, 'Int', this.RCPxScl, 'Int', this.RCPxScl, rectW)				; place coords in rect struct
		DllCall('FrameRect', 'Ptr', ghMGuiDC, 'Ptr', rectW, 'Ptr', hBrushW)						; draw white frame around grid area
		; draw black frame inside white frame of grid area
		rectB := Buffer(16, 0)																	; rectangle struct
		NumPut('Int', 1, 'Int', 1, 'Int', this.RCPxScl-1, 'Int', this.RCPxScl-1, rectB)			; place coords in rect struct
		DllCall('FrameRect', 'Ptr', ghMGuiDC, 'Ptr', rectB, 'Ptr', hBrushB)						; draw black frame around grid area
		; cleanup resources
		DllCall('DeleteObject', 'Ptr', hBrushW)
		DllCall('DeleteObject', 'Ptr', hBrushB)
		DllCall('ReleaseDC', 'Ptr', ghGrid, 'Ptr', hDC)
	}
	;############################################################################
	_isSizeOk() {																				; helps prevent rapid flip-flop repositioning of gui
		h := this._getHeights()
		return	h.curH < h.maxH
	}
	;############################################################################
	NeedsUpdate() {																				; prevents grid updates if no change occurred
		static lastX := '', lastY := '', lastRCPxCnt := '', lastRCSqCnt := ''					; used for comparisons
		MouseGetPos(&mX, &mY)																	; get current mouse position
		if (lastX!=mX || lastY!=mY																; if mouse moved...
		|| lastRCPxCnt!=this.RCPxCnt															; ... OR grid win size changed...
		|| lastRCSqCnt!=this.RCSqCnt) {															; ... OR grid magnification changed...
			lastX:=mx,lastY:=mY,lastRCPxCnt:=this.RCPxCnt,lastRCSqCnt:=this.RCSqCnt				; ...	save values for comparison next visit
			return true																			; ...	notify caller that changes occurred
		}
		return false																			; otherwise, NO change occurred
	}
	;############################################################################
	Resize(delta) {																				; perform grid win resize operations
		h		:= this._getHeights()															; get cur grid height and max allowed
		newSz	:= (!this._isSizeOk()) ? this.DefPxCnt											; resize to default value if too-big
				: ((delta < 1 || h.curH + delta < h.maxH) ? this.RCPxCnt + delta : 0)			; prevent enlargement if at max size
		if (newSz < 100)																		; prevent text from clipping at edges of control
			return
		this.PxW := this.RCPxCnt := newSz														; set new width for grid win
		this._gdiUpdate(), this.Move(,,this.PxW,this.PxH)										; update win size/view for new dimensions
		tiW := this.txtW, tiH := this.txtInfoH - this.BdrGap									; set width/height for color info box
		this.txtInfo.Move(this.BdrGap, this.RCPxCnt, tiW, tiH)									; resize color info box
		this.txtStus.Move(this.BdrGap, this.txtStusY, tiW, this.txtStusH)						; resize status info box
		cfg.Save('RCPxCnt',this.RCPxCnt)														; save cur pixel COUNT for single row of grid
	}
	;############################################################################
	SavePos() {																					; ensures custom win pos is saved
		this.GetPos(&x,&y)																		; get cur win x/y
		this.winX := x, this.winY := y															; save locally
		cfg.Save('GridPosX',x), cfg.Save('GridPosY',y)											; save to cfg and ini
	}
	;############################################################################
	ShowGui() {																					; show grid gui, enable timer for updates
		this.IsActive := 1																		; flag as visible
		if (this.GridLock) {																	; if grid gui pos is locked/static...
			gX := this.winX, gY := this.winY													; ... use static x/y values
		} else {																				; otherwise...
			MouseGetPos(&mX,&mY), gX := mX+this.OffsetX, gY := mY+this.OffsetY					; ... set pos near mouse
		}
		this.UpdateGrid(1)	; force grid update while hidden									; softens abrupt painting
		this.Show(Format('hide x{} y{} w{} h{}', gX, gY, this.PxW, this.PxH))					; hide initially, for better animation effect
		guiWinFade(this, 1, 1000)																; animate entrance
		this.Show()																				; make it permanent
		SetTimer(this.GridUpdateCB, 50)															; enable normal grid updates
	}
	;############################################################################
	ToggleActive() {																			; toggles whether tool is activate or not
		if (this.IsActive ^= 1)																	; if IS active...
			this.ShowGui(), this.UpdateGrid(1)													; ... show, and force update
		else
			this.HideGui()																		; otherwise, hide grid gui
	}
	;############################################################################
	ToggleLock() {																				; toggles whether grid gui is locked at static position
		if (this.GridLock ^= 1)																	; if gridlock is enabled...
			this.SavePos()																		; ... save the cur x/y pos
		cfg.Save('GridLock', this.GridLock)														; save gridlock state
		this.UpdateStatus()																		; update status bar with current lock condition
		guiForceUpdate(1)																		; force a grid image update
		;ToolTip(cfg.Grab('GridLock') '`n' cfg.Grab('GridPosX') '`n' cfg.Grab('GridPosY'))
	}
	;############################################################################
	; 2026-06-27, UPDATED to support multi-display setups
	UpdateGrid(force:=0) {																		; updates grid using a timer, but can be forced as well
		global ghGuiDC, ghMGuiDC																; global vars improve performance
		if (!force && !this.NeedsUpdate())														; if no changes are detected...
			return																				; ... no need for update
		RCPxScl := this.RCPxScl, RCSqCnt := this.RCSqCnt										; use local vars
		MouseGetPos(&mX, &mY)																	; get current mouse position
		pxPerSqr	:= RCPxScl / RCSqCnt														; [pixels per grid square]
		halfGrid	:= Floor(RCSqCnt / 2)														; [number of GRID SQUARES on either side of center]
		cStart		:= Floor(halfGrid * pxPerSqr)												; [number of PIXELS on either side of center]
		cEnd		:= cStart + Ceil(pxPerSqr)													; include center square also
		; get src and dest coords, width, height for drawing
		; also need to make adjustments at screen edges
		srcX := mX - halfGrid, srcY := mY - halfGrid											; coords that will begin screen capture
		dstX := 0, dstY := 0, drawW := RCSqCnt, drawH := RCSqCnt
		if (srcX < gVD.vX) {
			dstX	:= Round(Abs(srcX - gVD.vX) * pxPerSqr)
			drawW	-= Abs(srcX - gVD.vX)
			srcX	:= gVD.vX
		}
		if (srcY < gVD.vY) {
			dstY	:= Round(Abs(srcY - gVD.vY) * pxPerSqr)
			drawH	-= Abs(srcY - gVD.vY)
			srcY	:= gVD.vY
		}
		if (srcX + drawW > gVD.vX + gVD.vW)
			drawW := (gVD.vX + gVD.vW) - srcX
		if (srcY + drawH > gVD.vY + gVD.vH)
			drawH := (gVD.vY + gVD.vH) - srcY
		; draw to grid canvas
		DllCall('BitBlt', 'Ptr', ghMGuiDC, 'Int', 0, 'Int', 0, 'Int', RCPxScl					; start with black grid canvas
			, 'Int', RCPxScl, 'Ptr', 0, 'Int', 0, 'Int', 0, 'UInt', 0x00000042)					; ... needed when capturing screen edges
		hScrnDC := DllCall('GetDC', 'Ptr', 0, 'Ptr')											; get screen device context
		DllCall('StretchBlt',																	; stretch screen image onto grid canvas
			'Ptr', ghMGuiDC,
			'Int', dstX, 'Int', dstY,
			'Int', Round(drawW * pxPerSqr),
			'Int', Round(drawH * pxPerSqr),
			'Ptr', hScrnDC,
			'Int', srcX,
			'Int', srcY,
			'Int', drawW, 'Int', drawH,
			'UInt', 0x00CC0020	)
		targClr	:= DllCall('GetPixel', 'Ptr', hScrnDC, 'Int', mX, 'Int', mY, 'UInt')			; get pixel color at mouse pointer
		clrs	:= this._getClrInfo(targClr)													; process/return color details
		this.UpdateInfoText(mX,mY,clrs)															; update text details
		this.DrawCrossHairs(clrs.xHairClr, cStart, cEnd)										; draw cross-hairs to grid canvas
		this.HL_CenterPx(cStart,cEnd)															; highlight center square
		this.HL_Frame()					; must be done after text update						; add contrast frame to grid gui
		DllCall('BitBlt','Ptr',ghGuiDC,'Int',0,'Int',0,'Int',RCPxScl							; transfer all updates to gui canvas
				,'Int',RCPxScl,'Ptr',ghMGuiDC,'Int',0,'Int',0,'UInt',0x00CC0020)
		DllCall('ReleaseDC', 'Ptr', 0, 'Ptr', hScrnDC)											; discard screen DC resource
		this.UpdateGridPos()																	; move gui relative to mouse position
	}
	;############################################################################
	; 2026-06-27, UPDATED to support multi-display setups
	UpdateGridPos() {																			; reposition grid gui relative to mouse pos
		static xDir := 0, yDir := 0
		if (this.GridLock)																		; if grid gui is locked in static pos...
			return																				; ... do not reposition it
		offsetX := this.OffsetX, offsetY := this.OffsetY										; use local vars
		if (!this._isSizeOk())																	; if grid gui is too big for auto-wrapping...
			this.Resize(0)																		; ... resize grid gui
		MouseGetPos(&mX, &mY)																	; get current mouse coords
		WinGetPos(&rX, &rY, &rW, &rH, ghGrid)													; get SCALED gui dimensions
		;########################################################################
		; x-axis
		if (xDir = 0) {
			; if moving R and win hits R edge, flip Gui to L of mouse pointer
			if (mX + offsetX + rW > gVD.vX + gVD.vW) {
				gX := mX - rW - offsetX, xDir := 1
			} else {
				gX := mX + offsetX
			}
		} else { ; xDir = 1
			; only flip back to R side of mouse when Gui reaches L edge
			if (mX - rW -offsetX < gVD.vX) {
				gX := mX + offsetX, xDir := 0
			} else {
				gX := mX - rW - offsetX
			}
		}
		;########################################################################
		; y-axis
		if (yDir = 0) {
			; if moving dn and win hits bot edge, flip Gui above mouse pointer
			if (mY + offsetY + rH > gVD.vY + gVD.vH) {
				gY := mY - rH - offsetY, yDir := 1
			} else {
				gY := mY + offsetY
			}
		} else { ; yDir = 1
			; only flip below mouse pointer when Gui reaches top edge
			if (mY - rH - offsetY < gVD.vY) {
				gY := mY + offsetY, yDir := 0
			} else {
				gY := mY - rH - offsetY
			}
		}
		;########################################################################
		; safety overrides to prev gui clipping under taskbars/edges
		if (gX < gVD.vX)
			gX := gVD.vX
		if (gY < gVD.vY)
			gY := gVD.vY
		if (gX + rW > gVD.vX + gVD.vW)
			gX := (gVD.vX + gVD.vW) - rW
		if (gY + rH > gVD.vY + gVD.vH)
			gY := (gVD.vY + gVD.vH) - rH

		WinMove(gX,gY,,,ghGrid)
	}
	;############################################################################
	UpdateStatus() {																			; update status bar text
		lock := '  ' . ((this.GridLock) ? '🔒' : '🔓')											; set lock icon
		this.txtStus.Value := lock
	}
	;############################################################################
	UpdateInfoText(x,y,clrs) {																	; updates text area of display
		R := clrs.Clr.R, G := clrs.Clr.G, B := clrs.Clr.B										; grab RGB
		this.textBkgd		:= clrs.Clr.H														; save text bkgd for later (hex color)
		this.textFrgd		:= clrs.txtFClr														; save text frgd for later
		xyStr				:= Format('XY {},{}', x, y)											; XY coords  of target pixel
		rgbStr				:= Format('RGB {},{},{}', R,G,B)									; RGB colors of target pixel
		hexStr				:= Format('{:02X}:{:02X}:{:02X}', R,G,B)							; add colon separators for hex values
		this.txtInfo.Value	:= xyStr '`n' rgbStr '`n' 'HEX ' hexStr								; update text control
		this.txtInfo.Opt('Background' this.textBkgd ' c' this.textFrgd)							; set font color and display target color
	}
	;############################################################################
	zoomIn() {																					; increase magnification
		if (this.RCSqCnt > this.RCSqMin) {
			this.RCSqCnt -= 2, cfg.Save('RCSqCnt',this.RCSqCnt)
		}
	}
	;############################################################################
	zoomOut() {																					; decrease magnification
		if (this.RCSqCnt < this.RCSqMax) {
			this.RCSqCnt += 2, cfg.Save('RCSqCnt',this.RCSqCnt)
		}
	}
	;############################################################################
	; CLR - organize extraction of color info
	class CLR
	{
		;########################################################################
		Static RGBLH(srcClr) {																	; extracts R,G,B components of srcClr
			R	:=  srcClr			& 0xFF														; extract red	 component
			G	:= (srcClr >> 8)	& 0xFF														; extract green	 component
			B	:= (srcClr >> 16)	& 0xFF														; extract blue	 component
			L	:= ((0.299 * R) + (0.587 * G) + (0.114 * B))									; calculate luminance value
			H	:= Format('{:02X}{:02X}{:02X}', R,G,B)											; hex colors of target pixel
			return {R:R,G:G,B:B,L:L,H:H}														; return extracted values, obj
		}
		;########################################################################
		Static IsMidGray(r,g,b) {																; returns whether rgb values are within mid gray range
			lv:=100, hv:=156																	; luminosity range considered medium gray
			return (r>=lv && r<=hv && g>=lv && g<=hv && b>=lv && b<=hv)
		}
	}
}
;################################################################################
; clsHKList - Shortcuts list
;################################################################################
class clsHKList extends Gui
{
	_chkHK	 := ''																				; will become checkbox control
	_keyList := [																				; shortcut list array
	'F8:Toggle Tool On/Off',
	'Alt + C:Copy ALL info to clipboard',
	'Alt + H:Copy HEX value to clipboard',
	'Alt + L:Lock tool win position (no follow)',
	'Alt + S:Show Shortcuts List (this)',
	'Escape:Close Shortcuts List (this)',
	'Arrow Keys:Fine-tune mouse position +/-1',
	'Alt + Arrow Keys:Fine-tune mouse position +/-10',
	'Shift + Arrows/Wheel:Resize window/view',
	'Ctrl  + Arrows/Wheel:Adjust magnification',
	'Ctrl  + Escape:Quit Tool']
	;############################################################################
	__New(winX:='',winY:='') {																	; constructor
		this._winX := winX																		; custom X pos for window
		this._winY := winY																		; custom Y pos for window
		this._iniHKGui()																		; initialize window and controls
		this.Title := 'HHHKLIST'																; used as detection flag for escape key
	}
	;############################################################################
	_evCtrl(ctrl,*) {																			; event handler for checkbox
		if (ctrl.name = 'chkHK')
			val := ctrl.Value, cfg.Save('ShowHKs',val)											; save check/unchecked setting
	}
	;############################################################################
	HideGui() {																					; hides shortcut list using animation
		this.SavePos()										; probably redundant				; save current window position
		guiWinFade(this, 2, 750)																; animate departure
		this.Hide()																				; make hide permanent
	}
	;############################################################################
	_iniHKGui() {
		super.__New('-Caption +ToolWindow +AlwaysOnTop +border')
		this.BackColor := cfg.Grab('SkinClr'), this.name := 'hkGui'
		fontName := 'Segoe UI', textColor := 'cE0E0E0', triggerClr := 'c6495ED'
		; list header
		t := 'Shortcuts for Hue-Hacker'
		this.SetFont('s12 w700 ' textColor, fontName)
		this.Add('Text', 'x20 y15 w210 h30', t)
		this.SetFont('s7 ' textColor, fontName)
		this._chkHK := this.Add('Checkbox','vchkHK x240 y25 w115 right','Show at launch')
		this._chkHK.value := cfg.Grab('ShowHKs')												; checkbox checked or not?
		this._chkHK.OnEvent('Click',this._evCtrl.Bind(this._chkHK))								; enable/disable showing HK list at launch
		this.Add('Text','x20 y48 w390 h2 Background333333')										; txt control used as divider line
		; add hk list
		cY := 60
		bkgd := '' ;' background000000 '
		for idx, kv in this._keyList {															; for each entry in shortcut list array...
			ss := StrSplit(kv,':'), key := ss[1], desc := ss[2]									; extract trigger and description
			cY += (A_Index>1) ? 20 : 0															; adjust Y pos for each line
			this.SetFont('s9 w600 ' triggerClr, 'Consolas')										; trigger font
			this.Add('Text', bkgd ' x20 y' cY ' w190 h19', '  ' key)							; trigger
			this.SetFont('s9 w400 ' textColor, fontName)										; desc font
			this.Add('Text', bkgd ' center x220 y' cY ' w190 h19', desc)						; desc
		}
		; show window with custom placement
		winX := this._winX, winY := this._winY													; get custom x/y
		winX := (winX!='') ? winX : cfg.Grab('HKListX')											; if custom x is empty, use value in ini file
		winY := (winY!='') ? winY : cfg.Grab('HKListY')											; if custom y is empty, use value in ini file
		this.width := 430, this.height := cY+Scaled(30)											; adj height dynamically depending on list len
		this.ShowGui(winX, winY)
	}
	;############################################################################
	SavePos() {																					; ensures custom win pos is saved
		this.GetPos(&x,&y), cfg.Save('HkListX',x), cfg.Save('HkListY',y)						; save cur win x/y pos
	}
	;############################################################################
	ShowGui(x:='',y:='') {																		; shows list using animation
		winX := (x='') ? '' : ' x' x															; use custom x pos is avail
		winY := (y='') ? '' : ' y' y															; use custom y pos is avail
		this.Show(Format(winX winY ' hide w{} h{}', this.width, this.height))					; hide gui initially, for better animation
		guiWinFade(this, 1, 750)																; animate entrance
		this.Show()																				; make it permanent
	}
}
;################################################################################
; clsSplash - animated splash screen
;################################################################################
class clsSplash extends Gui
{
	_pad	:= scaled(15)																		; gui edge padding
	_bxSz	:= scaled(50)																		; size of individual squares for cube
	_Sz		:= scaled(225)																		; general target size for splash screen
	_cbSz	=> this._bxSz*3																		; full cube size
	Width	=> this._Sz	  + (this._pad*2)														; final width  of splash screen
	Height	=> this.Width + (this._pad*2)				; longer for aesthetics					; final height of splash screen
	_ctrBx	=> { X1:this._pad+this._bxSz,														; center rectangle of cube
				 Y1:this._pad+this._bxSz,
				 X2:this._pad+this._bxSz*2,
				 Y2:this._pad+this._bxSz*2, }

	;############################################################################
	__New() {																					; constructor
		this._build(), this._showBriefly()
	}
	;############################################################################
	_build() {
		super.__New('-Caption +AlwaysOnTop +ToolWindow +Border')
		this.BackColor := cfg.Grab('SkinClr')
		; build cube using txt boxes
		pad := this._pad, bxSz := this._bxSz
		; colors for boxes
		cRed  := 'FF0000', cGrn	 := '00FF00', cBlue	:= '0000FF'
		cOrng := 'FF8000', cWhte := 'FFFFFF', cPrpl	:= '8800FF'
		cYelw := 'FFFF00', cMgta := 'FF00FF', cCyan	:= '00FFFF'
		; top row
		fmtStr := 'x{} y{} w{} h{} Background{}'												; common formatting for all txt boxes
		this.Add('Text', Format(fmtStr, pad,		pad,		bxSz, bxSz, cRed ))
		this.Add('Text', Format(fmtStr, pad+bxSz,	pad,		bxSz, bxSz, cGrn ))
		this.Add('Text', Format(fmtStr, pad+bxSz*2,	pad,		bxSz, bxSz, cBlue))
		; middle row
		this.Add('Text', Format(fmtStr, pad,		pad+bxSz,   bxSz, bxSz, cOrng))
		this.Add('Text', Format(fmtStr, pad+bxSz,	pad+bxSz,   bxSz, bxSz, cWhte))
		this.Add('Text', Format(fmtStr, pad+bxSz*2,	pad+bxSz,   bxSz, bxSz, cPrpl))
		; bottom row
		this.Add('Text', Format(fmtStr, pad,		pad+bxSz*2, bxSz, bxSz, cYelw))
		this.Add('Text', Format(fmtStr, pad+bxSz,	pad+bxSz*2, bxSz, bxSz, cMgta))
		this.Add('Text', Format(fmtStr, pad+bxSz*2,	pad+bxSz*2, bxSz, bxSz, cCyan))
		; add title text
		this.SetFont('s10 cWhite Bold', 'Segoe UI'), fmtStr := 'x{} y{} w{} right'
		this.Add('Text', Format(fmtStr, pad, pad+bxSz*3+10, bxSz*3), 'HUE-HACKER')
		this.SetFont('s8 c0X777777', 'Segoe UI')
		vers := StrReplace(gAppVers,'-')
		this.Add('Text', Format(fmtStr, pad, pad+bxSz*3+30, bxSz*3), vers)
	}
	;################################################################################
	_drawReticle() {																			; draw cross-hair on splash screen
		hwnd := this.hwnd
		hdc := DllCall('GetDC', 'Ptr', hwnd, 'Ptr')
		; grab gui dimensions
		rect := Buffer(16, 0)
		DllCall('GetClientRect', 'Ptr', hwnd, 'Ptr', rect)
		w := NumGet(rect, 8, 'Int'), h := NumGet(rect, 12, 'Int')
		; use double buffer to keep the cross-hair rendering instant
		hdcMem	:= DllCall('CreateCompatibleDC', 'Ptr', hdc, 'Ptr')
		hBitmap	:= DllCall('CreateCompatibleBitmap', 'Ptr', hdc, 'Int', w, 'Int', h, 'Ptr')
		oldBmp	:= DllCall('SelectObject', 'Ptr', hdcMem, 'Ptr', hBitmap, 'Ptr')
		; place the gui image into this buffer
		DllCall('BitBlt', 'Ptr', hdcMem, 'Int', 0, 'Int', 0, 'Int', w, 'Int', h
			, 'Ptr', hdc, 'Int', 0, 'Int', 0, 'UInt', 0x00CC0020)
		; high-contrast drawing pens for cross-hair
		hBlackPen := DllCall('CreatePen', 'Int', 0, 'Int', 4, 'UInt', 0x000000, 'Ptr')
		hWhitePen := DllCall('CreatePen', 'Int', 0, 'Int', 2, 'UInt', 0xFFFFFF, 'Ptr')
		; cross-hair position
		tX1	 := this._ctrBx.X1, tY1 := this._ctrBx.Y1
		tX2	 := this._ctrBx.X2, tY2 := this._ctrBx.Y2
		midX := tX1 + ((tX2 - tX1) / 2), midY := tY1 + ((tY2 - tY1) / 2), ext := 12				; cross hair centered on center square
		midX := scaled(midX), midY := scaled(midY), ext := scaled(ext)							; ensure cross-hair pos is adj for scaling
		midX *= .88, midY *= .88																; OPTIONAL - include dynamic offset
		; paint cross-hair over the cube
		Loop 2 {
			currentPen := (A_Index == 1) ? hBlackPen : hWhitePen
			oldObj := DllCall('SelectObject', 'Ptr', hdcMem, 'Ptr', currentPen, 'Ptr')
			DllCall('MoveToEx', 'Ptr', hdcMem, 'Int', midX - ext, 'Int', midY, 'Ptr', 0)
			DllCall('LineTo', 'Ptr', hdcMem, 'Int', midX - 2, 'Int', midY)
			DllCall('MoveToEx', 'Ptr', hdcMem, 'Int', midX + 2,'Int', midY, 'Ptr', 0)
			DllCall('LineTo', 'Ptr', hdcMem, 'Int', midX + ext, 'Int', midY)
			DllCall('MoveToEx', 'Ptr', hdcMem, 'Int', midX, 'Int', midY - ext, 'Ptr', 0)
			DllCall('LineTo', 'Ptr', hdcMem, 'Int', midX, 'Int', midY - 2)
			DllCall('MoveToEx', 'Ptr', hdcMem, 'Int', midX, 'Int', midY + 2,'Ptr', 0)
			DllCall('LineTo', 'Ptr', hdcMem, 'Int', midX, 'Int', midY + ext)
			DllCall('SelectObject', 'Ptr', hdcMem, 'Ptr', oldObj, 'Ptr')
		}
		; blast the combined images to screen in one shot
		DllCall('BitBlt', 'Ptr', hdc, 'Int', 0, 'Int', 0, 'Int', w, 'Int', h
			, 'Ptr', hdcMem, 'Int', 0, 'Int', 0, 'UInt', 0x00CC0020)
		; clean up
		DllCall('DeleteObject', 'Ptr', hBlackPen)
		DllCall('DeleteObject', 'Ptr', hWhitePen)
		DllCall('SelectObject', 'Ptr', hdcMem, 'Ptr', oldBmp, 'Ptr')
		DllCall('DeleteObject', 'Ptr', hBitmap)
		DllCall('DeleteDC', 'Ptr', hdcMem)
		DllCall('ReleaseDC', 'Ptr', hwnd, 'Ptr', hdc)
	}
	;############################################################################
	_showBriefly() {																			; shows splash briefly, using animation
		this.Show(Format('hide w{} h{}', this.width, this.height))								; hide gui initially, for better animation
		guiWinFade(this, 1, duration := 1000)													; animate entrance
		this._drawReticle(), sleep(1700)														; blast cross-hair on top
		guiWinFade(this, 2, duration := 1500)													; animate departure
		this.Destroy()																			; see ya!
	}
}
;#################################  FUNCTIONS  ##################################
;################################################################################
																	   getScale()				; compensates for screen scaling
;################################################################################
{
	global gScale
	if (!IsSet(gScale)) {																		; if scale has not been inspected yet...
		hDC := DllCall('GetDC', 'Ptr', 0, 'Ptr')
		dpi := DllCall('GetDeviceCaps', 'Ptr', hDC, 'Int', 88, 'Int')
		DllCall('ReleaseDC', 'Ptr', 0, 'Ptr', hDC)
		gScale := dpi / 96																		; ... save scale to global var
	}
	return gScale																				; return to caller, in case needed
}
;################################################################################
; 2026-06-27, ADDED to support multi-display setups
														   getVirtualDimensions()				; returns virtual display dimensions (for multi-display support)
;################################################################################
{
	global gVD
	if (!IsSet(gVD)) {
		vX	:= DllCall('GetSystemMetrics', 'Int', 76, 'Int') ; SM_XVIRTUALSCREEN
		vY	:= DllCall('GetSystemMetrics', 'Int', 77, 'Int') ; SM_YVIRTUALSCREEN
		vW	:= DllCall('GetSystemMetrics', 'Int', 78, 'Int') ; SM_CXVIRTUALSCREEN
		vH	:= DllCall('GetSystemMetrics', 'Int', 79, 'Int') ; SM_CYVIRTUALSCREEN
		gVD	:= {vX:vX,vY:vY,vW:vW,vH:vH}
	}
	return gVD
}
;################################################################################
														 guiForceUpdate(reset:=0)				; forces a grid update for 2 secs
;################################################################################
{
	static c := 0, maxC := 40	; 50 X 40 :=  2 secs
	start := 0
	if (reset)
		start := (c=0), c := 0																	; determine whether timer needs started
	if (!gGui.IsActive || ++c > maxC) {															; if grid gui is not visible, or max was exceeded...
		setTimer(%A_ThisFunc%, 0), c := 0														; ... disable timer
		return																					; ... then exit
	}
	gGui.UpdateGrid(1)																			; force an update to grid gui
	(start) && (setTimer(%A_ThisFunc%, 50))														; start timer for more visits, if needed
}
;################################################################################
																  guiHKListHide()
;################################################################################
{
	if (!WinExist('HHHKLIST') || !guiIsVisible(gHKGui))											; if shortcut list gui not found OR already hidden...
		return																					; ... don't attempt hide
	gHKGui.HideGui()																			; is visible... hide it
}
;################################################################################
																  guiHKListShow()				; shows shortcut list
;################################################################################
{
	if (!WinExist('HHHKLIST'))																	; if shortcut list gui not created yet...
		global gHKGui := clsHKList()															; ... create and show it
	else if (!guiIsVisible(gHKGui))																; if exists but not visible...
		gHKGui.ShowGui()																		; ... show it
}
;################################################################################
																guiIsVisible(obj)				; determines whether gui or control is visible
;################################################################################
{
	return ControlGetVisible(obj)
}
;################################################################################
								   guiPreventBkgdErase(wParam, lParam, msg, hwnd)				; prevent background erase (ugly flash)
;################################################################################
{
	if (hwnd = gGui.Hwnd)
		return 1																				; ... BUT ONLY return a value for grid gui!
	; return NOTHING, not even 0!																; ... otherwise it also affects child windows and ctrls
}
;################################################################################
																  guiSplashShow()				; shows splash screen using animation
;################################################################################
{
	clsSplash()
}
;################################################################################
											   guiWinFade(guiObj, mode, dur:=300)				; animates win entrance/departure
;################################################################################
{
	static AW_BLEND := 0x80000, AW_HIDE := 0x10000
	try
		hwnd := guiObj.hwnd																		; ensure gui is valid
	catch
		return
	flags := AW_BLEND																			; set the flag base to blend/fade
	if (mode=2 || InStr(mode,'out'))
		flags |= AW_HIDE																		; if fading out, add the hide flag
	return DllCall('AnimateWindow', 'Ptr',hwnd, 'Int',dur, 'UInt',flags, 'Int')
}
;################################################################################
																	   loadIcon()				; uses Base64 string as icon
;################################################################################
{
	hIcon := Base64ICO_to_HICON(appIco())
	try TraySetIcon("HICON:" hIcon)
	;try TraySetIcon('HueHacker.ico')															; set tray icon
	;SendMessage(0x0080, 0, hIcon, gGui.Hwnd) ; WM_SETICON (Small Icon)
    ;SendMessage(0x0080, 1, hIcon, gGui.Hwnd) ; WM_SETICON (Large Icon)
}
;################################################################################
																	scaled(value)				; applies scaling to passed setting
;################################################################################
{
	return value * getScale()
}
;################################################################################
										 WM_DPICHANGED(wParam, lParam, msg, hwnd)				; allows gui to detect dpi changes on the fly, and adj
;################################################################################
{
	if (hwnd != gGui.hwnd)
		return
	getScale()
	getVirtualDimensions()
	gGui.Resize(0)
	guiForceUpdate(1)
}
;################################################################################
										WM_LBUTTONDOWN(wParam, lParam, msg, hwnd)				; allows user to move HK gui if desired
;################################################################################
{
	if (WinGetTitle(hwnd) = 'HHHKLIST') {														; if user is moving HKList...
		PostMessage(0xA1,2,,,hwnd)																; ... allow click/move anywhere in window
		KeyWait("LButton")																		; ... wait for user to release left mouse button
		gHKGui.SavePos()																		; ... save new win pos
	}
	if (hwnd = gGui.Hwnd && gGui.GridLock) {													; if user is moving grid gui...
		PostMessage(0xA1,2,,,hwnd)																; ... allow click/move anywhere in window
		KeyWait("LButton")																		; ... wait for user to release left mouse button
		gGui.SavePos()																			; ... save new win pos
	}
}
;################################################################################
												  shellMessage(wParam, lParam, *)				; get notified when active window changes
;################################################################################
{
	if (!gGui.IsActive)
		return
	; 4 = HSHELL_WINDOWACTIVATED, 32772 = HSHELL_RUDELEVELTOPACTIVATED
	if (wParam = 4 || wParam = 32772) {															; if active window changed...
		guiForceUpdate(1)																		; ... force an update to grid gui
	}
}
;#################################  SHORTCUTS  ##################################
;################################################################################
#HotIf			(gInitialized && gGui.IsActive)													; hotkeys only work when tool is active
+Up::
+Right::
+WheelUp::			gGui.Resize(10)
+Down::
+Left::
+WheelDown::		gGui.Resize(-10)
^Up::
^WheelUp::			gGui.zoomIn()
^Down::
^WheelDown::		gGui.zoomOut()
~WheelUp::
~WheelDown::
~LButton::
~RButton::			guiForceUpdate(1)															; forces update for mouse clicks/scrolling
~Up::				MouseMove(0, -1,  0, 'R')
~Down::				MouseMove(0,  1,  0, 'R')
~Left::				MouseMove(-1, 0,  0, 'R')
~Right::			MouseMove(1,  0,  0, 'R')
!Up::				MouseMove(0, -10, 0, 'R')
!Down::				MouseMove(0,  10, 0, 'R')
!Left::				MouseMove(-10, 0, 0, 'R')
!Right::			MouseMove(10,  0, 0, 'R')
!h::
!c::				gGui.CopyToClip(A_ThisHotkey)
!l::				gGui.ToggleLock()
#HotIf			(gInitialized && !WinActive('HHHKLIST'))										; do not show HK list if currently displayed
!s::				guiHKListShow()
#HotIf			(gInitialized)																	; hotkeys that work whether tool is active or not
~Esc::				guiHKListHide()																; close HK list if open
^Esc::				AppClose()																	; quit app
F8::				gGui.ToggleActive()															; show/hide grid gui
#HotIf
;################################################################################
;################################################################################
; Base64 ICO to HICON Engine Function
Base64ICO_to_HICON(Base64ICO) {
	Local BLen		:= StrLen(Base64ICO)
	Local nBytes	:= Floor(StrLen(RTrim(Base64ICO, "=")) * 3 / 4)
	Local Bin		:= Buffer(nBytes)

	; decode Base64 string into binary memory buffer
	If (!DllCall("Crypt32\CryptStringToBinary", "Str", Base64ICO, "UInt", BLen
		, "UInt", 1, "Ptr", Bin, "UIntP", &nBytes, "Ptr", 0, "Ptr", 0))
		Return 0

	; find the offset where the raw icon bits actually begin inside the ICO container
	; an ICO file structure stores the image offset at byte position 18 (Directory Entry)
	Local icoOffset	:= NumGet(Bin, 18, "UInt")
	Local icoSize	:= NumGet(Bin, 14, "UInt")

	; create the HICON pointer using the exact data bits offset
	Local pBits		:= Bin.Ptr + icoOffset
	Return DllCall("CreateIconFromResourceEx", "Ptr", pBits, "UInt", icoSize
		, "Int", True, "UInt", 0x30000, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
}
;################################################################################
appIco() {
return  "AAABAAEAUlIAAAEAIAAQbQAAFgAAACgAAABSAAAApAAAAAEAIAAAAAAAEGkAAHQSAAB0EgAAAAAAAAAAAAAaGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//wAAAP8AAAD/AAAA/wAAAP//AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///////8AAAD/AAAA/wAAAP8AAAD/AAAA//8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP//AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8AAAD/AAAA/wAAAP8AAAD/AAAA////////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//AAAA/wAAAP8AAAD/AAAA/wAAAP//AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///////wAAAP8AAAD/AAAA/wAAAP8AAAD//wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP//AAAA//8A////AP///wD///8A////AP//AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA//8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD//wAAAP///////wD///8A////AP///wD//wAAAP8AAAD/AAAA/wAAAP8AAAD///////8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A//8AAAD/AAAA/wAAAP//AP///wD///8A//8AAAD/AAAA/wAAAP8AAAD/AAAA//8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP//AAAA/wAAAP8AAAD///////8A////////AAAA/wAAAP8AAAD/AAAA/wAAAP//AP///wD///8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD//wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD//wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP////////////////////////////////////////////////8AAAD/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP//////////////////////////////////////AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD//////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT//////////////////////////////////////wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD///////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP//////////////////////////////////////AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD//////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT//////////////////////////////////////wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD///////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP//////////////////////////////////////AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD//////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT//////////////////////////////////////wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD///////////////////////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/////////////////////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP//////////////////////////////////////AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD//////////////////////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT//////////////////////////////////////wAAAP8AAAD/AAAA/wAAAP8AAAD///////////////////////////////////////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/AAAA/wAAAP8AAAD/////////////////////////////////////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP//////////////////////////////////////AAAA/wAAAP8AAAD//////////////////////////////////////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT//////////////////////////////////////wAAAP8AAAD///////////////////////////////////////////////////////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/////////////////////////////////////////////////////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
}
