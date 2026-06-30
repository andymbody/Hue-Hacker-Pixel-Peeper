/*
	App:	Hue-Hacker Pixel-Peeper
	Author:	andymbody
	Date:	2026-06-30
	GitHub:	https://github.com/andymbody/Hue-Hacker-Pixel-Peeper
	Forum:	https://www.autohotkey.com/boards/viewtopic.php?f=83&t=140824
*/
#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode('Mouse', 'Screen'), CoordMode('Pixel', 'Screen'), CoordMode('Tooltip', 'Screen')
gAppVers := '26-06-30.105'
AppIni()																						; initialize application
;################################################################################
AppClose() {
	gLoup.GdiCleanup(), cfg.CancelSave(), cfg.SaveToDisk(), ExitApp()							; force save any pending config data, quit app
}
;################################################################################
AppIni() {
	global
	gInitialized := 0																			; disable hotkeys
		getDisplayInfo()																		; get display details
		cfg := clsSettings()																	; grab setting from ini file
		guiSplashShow()																			; show animated splash screen
		DllCall('SetThreadDpiAwarenessContext', 'ptr', -4, 'ptr')								; needs to be before loupe gui ini
		gLoup := clsLoupe()																		; initialize loupe gui using custom gui class
		loadIcon()																				; load icon as Base64
		DllCall('RegisterShellHookWindow', 'Ptr', gLoup.Hwnd)									; setup win hook
		OnMessage(DllCall('RegisterWindowMessage','Str','SHELLHOOK'),shellMsg)					; setup notification for active win changes
		OnMessage(0x0201, WM_LBUTTONDOWN)														; enable click/drag anywhere in HK or loupe gui
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
	;_iniFile		:= 'D:' '\HueHacker.ini'			; thumb-drive for testing				; ini file to write to
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
		this._cache['RCSqCnt' ] := ''															; LOUPE  square count for loupe single row/col (zoom factor)
		this._cache['RCPxCnt' ] := ''															; SCREEN pixel  count for loupe single row/col (win size)
		this._cache['LoupLock'] := '0'															; whether loupe gui is locked in static position
		this._cache['LoupPosX'] := ''															; loupe gui static position X
		this._cache['LoupPosY'] := ''															; loupe gui static position Y
	}
	;############################################################################
	CancelSave() {														; Public				; prevents pending ini write
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
; clsLoupe - Main loupe tool gui
;################################################################################
class clsLoupe extends Gui
{
	OffsetX		:= 75, OffsetY := 75															; pixel distance between mouse and loupe gui
	txtInfoH	:= 48																			; initial height of text display control
	txtStusH	:= 22																			; status bar text height
	DefPxCnt	:= 200								; screen pixels								; default PIXEL  count for loupe single row/col
	DefSqCnt	:= 39								; loupe squares								; default SQUARE count for loupe single row/col
	RCSqMin		:= 3, RCSqMax := 43					; loupe squares								; min/max square count for loupe single row/col
	RCSqCnt		:= (cfg.Grab('RCSqCnt')) ? (cfg.Grab('RCSqCnt')) : this.DefSqCnt				; LOUPE   square count for loupe single row/col
	RCPxCnt		:= (cfg.Grab('RCPxCnt')) ? (cfg.Grab('RCPxCnt')) : this.DefPxCnt				; SCREEN  pixel  count for loupe single row/col
	RCPxScl		=> Round(scaled(this.RCPxCnt))													; SCREEN  pixel  count for loupe single row/col (scaled)
	PxH			=> this.RCPxCnt + this.txtInfoH + this.txtStusH									; initial loupe gui height
	PxW			:= this.RCPxCnt																	; initial loupe gui width
	isActive	:= 0																			; whether tool is active/visible or not
	LoupLock	:= 0																			; whether loupe gui is locked in static pos
	txtInfo		:= ''																			; control to display color details
	textFrgd	:= ''																			; text font color
	textBkgd	:= ''																			; text bkgd color (hex format)
	clrInfo		:= unset																		; all color info
	BdrGap		:= 1																			; loupe gui frame thickness
	txtW		=> this.PxW - (this.BdrGap * 2)													; width  for status bar text and info text
	txtStusY	=> this.RCPxCnt + this.txtInfoH - this.BdrGap									; height for status bar text
	winX		:= 0																			; loupe gui X pos
	winY		:= 0																			; loupe gui Y pos
	;############################################################################
	__New() {
		super.__new('+AlwaysOnTop -Caption +ToolWindow +E0x20')									; pass options to papa
		global ghLoup := this.hwnd																; use global var for performance reasons
		this._customIni()																		; custom ini for loupe gui
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
		this.LoupLock:= cfg.Grab('LoupLock')													; get cur setting for loupe window lock
		this.winX	:= cfg.Grab('LoupPosX'), this.winY := cfg.Grab('LoupPosY')					; get cur setting for loupe window x/y
		this._updateStatus()																	; update status bar (lock status)
		this._gdiIni()																			; loupe canvas, for drawing
		this.LoupUpdateCB := ObjBindMethod(this, 'UpdateLoup')									; required to use method for SetTimer
		OnMessage(0x02E0, WM_DPICHANGED)														; loupe gui detects dpi scaling changes (must follow gui ini)
		OnMessage(0x0014, guiPreventBkgdErase)													; prevent ugly flash when resizing loupe gui
	}
	;############################################################################
	CopyToClip(hk) {																			; very basic copy of details to clipboard (for now)
		A_Clipboard := this._extractInfo(this.txtInfo.value, hk)								; put details in clipboard
		SoundBeep(1000,50), this.txtInfo.Opt('Background00FF00 c000000')						; audible/visual confirmation
		bClr := 'Background' this.textBkgd, fClr := ' c' this.textFrgd							; grab current font and bkgd colors
		SetTimer(() => this.txtInfo.Opt(bClr fClr), -150)										; reset font and bkgd colors
	}
	;############################################################################
	_drawCrossHairs(color, cStart, cEnd) {														; draws cross hairs to loupe canvas
		global ghMLoupDC
		RCPxScl := this.RCPxScl
		hPen	:= DllCall('CreatePen', 'Int',0, 'Int', 1, 'UInt',color, 'Ptr')
		hOldPen	:= DllCall('SelectObject', 'Ptr', ghMLoupDC, 'Ptr', hPen, 'Ptr')
		DllCall('MoveToEx', 'Ptr', ghMLoupDC, 'Int', 0, 'Int', cStart, 'Ptr', 0)
		DllCall('LineTo', 'Ptr', ghMLoupDC, 'Int', RCPxScl, 'Int', cStart)
		DllCall('MoveToEx', 'Ptr', ghMLoupDC, 'Int', 0, 'Int', cEnd, 'Ptr', 0)
		DllCall('LineTo', 'Ptr', ghMLoupDC, 'Int', RCPxScl, 'Int', cEnd)
		DllCall('MoveToEx', 'Ptr', ghMLoupDC, 'Int', cStart, 'Int', 0, 'Ptr', 0)
		DllCall('LineTo', 'Ptr', ghMLoupDC, 'Int', cStart, 'Int', RCPxScl)
		DllCall('MoveToEx', 'Ptr', ghMLoupDC, 'Int', cEnd, 'Int', 0, 'Ptr', 0)
		DllCall('LineTo', 'Ptr', ghMLoupDC, 'Int', cEnd, 'Int', RCPxScl)
		DllCall('SelectObject', 'Ptr', ghMLoupDC, 'Ptr', hOldPen)
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
		global ghLoupDC, ghMLoupDC, ghMemBM, ghOldBM											; global vars help improve performance
		ghLoupDC := 0, ghMLoupDC := 0, ghMemBM := 0, ghOldBM := 0								; ini
		this._gdiUpdate()																		; let _gdiUpdate handle the rest
	}
	;############################################################################
	_gdiUpdate() {																				; update canvas for loupe
		global ghLoupDC, ghMLoupDC, ghMemBM, ghOldBM											; global vars help improve performance
		RCPxScl := this.RCPxScl																	; use local var
		this.GdiCleanup()																		; cleanup previous allocations first
		; fresh sizing matrix
		ghLoupDC := DllCall('GetDC', 'Ptr', ghLoup, 'Ptr')
		ghMLoupDC:= DllCall('CreateCompatibleDC', 'Ptr', ghLoupDC, 'Ptr')
		ghMemBM	 := DllCall('CreateCompatibleBitmap', 'Ptr', ghLoupDC
					, 'Int', RCPxScl, 'Int', RCPxScl, 'Ptr')
		ghOldBM	 := DllCall('SelectObject','Ptr',ghMLoupDC, 'Ptr',ghMemBM,'Ptr')
	}
	;############################################################################
	GdiCleanup() {																				; release gdi resources
		global ghLoupDC, ghMLoupDC, ghMemBM, ghOldBM											; global vars help improve update performance
		DllCall('SelectObject', 'Ptr', ghMLoupDC, 'Ptr', ghOldBM, 'Ptr')
		DllCall('DeleteObject', 'Ptr', ghMemBM)
		DllCall('DeleteDC', 'Ptr', ghMLoupDC)
		DllCall('ReleaseDC', 'Ptr', ghLoup, 'Ptr', ghLoupDC)
	}
	;############################################################################
	_getClrInfo(srcClr) {																		; splits targ color into rgb, calcs best colors for cross-hairs, text, frames
		c := clsLoupe.Clr.RGBLH(srcClr)															; get rgb, luminance, hex values
		;ToolTip("lum := " c.L)																	; TEMP DEBUG
		txtFClr		:= (c.L > 145) ? '000000' : 'FFFFFF'										; set text frame and font color for best contrast
		xHairClr	:= 0x808080																	; cross-hairs are mid gray by default
		if (clsLoupe.Clr.isMidGray(c.R,c.G,c.B))												; if target color is mid gray...
			xHairClr:= (c.L > 128) ? 0x000000 : 0xFFFFFF										; adj cross-hair color for best contrast
		this.clrInfo:= {Clr:c,xHairClr:xHairClr,txtFClr:txtFClr}								; save for later use
		return this.clrInfo
	}
	;############################################################################
	_getHeights() {																				; returns loupe gui cur height and max height allowed
		MouseGetPos(&mx,&my)
		mon		:= clsMonitor.hostDisplay(mx,my), maxY := mon.aB								; get maxY for monitor where mouse is
		padding	:= 0 ;10																		; just in case
		;maxH	:= floor((maxY/2)-(gLoup.OffsetY/2)-padding)									; 2026-06-27, use virtual height instead of A_ScreenHeight
		maxH	:= floor(maxY/2)																; 2026-06-29, use monitor working area
		curH	:= Round(scaled(gLoup.PxH) + gLoup.OffsetY)										; includes the mouse/win offset as part calculated height !
		return	{curH:curH,maxH:maxH}															; return height details
	}
	;############################################################################
	_hideGUI() {																				; hide loupe gui, disable updates
		this.IsActive := 0
		SetTimer(this.LoupUpdateCB, 0)
		guiWinFade(this, 2, 750)
		this.Hide()
	}
	;############################################################################
	_hlCenterPx(cStart, cEnd) {																	; draws highlight box to center of loupe canvas
		global ghMLoupDC
		; create white, black brushes
		hBrushW	:= DllCall('CreateSolidBrush', 'UInt', 0xFFFFFF, 'Ptr')
		hBrushB := DllCall('CreateSolidBrush', 'UInt', 0x000000, 'Ptr')
		; draw white square in center of loupe
		rectW := Buffer(16, 0)
		NumPut('Int',cStart, 'Int',cStart, 'Int',cEnd+1, 'Int',cEnd+1, rectW)
		DllCall('FrameRect', 'Ptr', ghMLoupDC, 'Ptr', rectW, 'Ptr', hBrushW)
		; draw black square in center of loupe
		rectB := Buffer(16, 0)
		NumPut('Int',cStart+1, 'Int',cStart+1, 'Int',cEnd, 'Int',cEnd, rectB)
		DllCall('FrameRect', 'Ptr', ghMLoupDC, 'Ptr', rectB, 'Ptr', hBrushB)
		; cleanup resources
		DllCall('DeleteObject', 'Ptr', hBrushW)
		DllCall('DeleteObject', 'Ptr', hBrushB)
	}
	;############################################################################
	_hlFrame() {																				; draws white and black frame around loupe gui
		global ghMLoupDC
		RCPxScl := this.RCPxScl																	; use local var
		WinGetClientPos(&x, &y, &w, &h, ghLoup)													; provides SCALED values for loupe gui
		; create white, black brushes
		hBrushW	:= DllCall('CreateSolidBrush', 'UInt', 0xFFFFFF, 'Ptr')							; white brush
		hBrushB	:= DllCall('CreateSolidBrush', 'UInt', 0x000000, 'Ptr')							; black brush
		; draw white frame around entire gui
		hDC		:= DllCall('GetDC', 'Ptr', ghLoup, 'Ptr')										; get DC for full loupe gui
		rectW	:= Buffer(16, 0)																; rectangle struct
		NumPut('Int', 0, 'Int', 0, 'Int', w, 'Int', h, rectW)									; place coords in rect struct
		DllCall('FrameRect', 'Ptr', hDC, 'Ptr', rectW, 'Ptr', hBrushW)							; draw white frame to loupe gui DC
		; draw white frame inside just loupe area
		rectW	:= Buffer(16, 0)																; rectangle struct
		NumPut('Int',0, 'Int',0, 'Int',RCPxScl, 'Int',RCPxScl, rectW)							; place coords in rect struct
		DllCall('FrameRect', 'Ptr', ghMLoupDC, 'Ptr', rectW, 'Ptr', hBrushW)					; draw white frame around loupe area
		; draw black frame inside white frame of loupe area
		rectB := Buffer(16, 0)																	; rectangle struct
		NumPut('Int',1, 'Int',1, 'Int',RCPxScl-1, 'Int',RCPxScl-1, rectB)						; place coords in rect struct
		DllCall('FrameRect', 'Ptr', ghMLoupDC, 'Ptr', rectB, 'Ptr', hBrushB)					; draw black frame around loupe area
		; cleanup resources
		DllCall('DeleteObject', 'Ptr', hBrushW)
		DllCall('DeleteObject', 'Ptr', hBrushB)
		DllCall('ReleaseDC', 'Ptr', ghLoup, 'Ptr', hDC)
	}
	;############################################################################
	_isSizeOk() {																				; helps prevent rapid flip-flop repositioning of loupe gui
		h := this._getHeights()
		return	h.curH <= h.maxH
	}
	;############################################################################
	_needsUpdate() {																			; prevents loupe updates if no change occurred
		static lastX := '', lastY := '', lastRCPxCnt := '', lastRCSqCnt := ''					; used for comparisons
		RCPxCnt := this.RCPxCnt, RCSqCnt := this.RCSqCnt										; use local vars
		MouseGetPos(&mX, &mY)																	; get current mouse position
		if (lastX!=mX || lastY!=mY																; if mouse moved...
		|| lastRCPxCnt!=RCPxCnt																	; ... OR loupe win size changed...
		|| lastRCSqCnt!=RCSqCnt) {																; ... OR loupe magnification changed...
			lastX:=mx, lastY:=mY, lastRCPxCnt:=RCPxCnt, lastRCSqCnt:=RCSqCnt					; ...	save values for comparison next visit
			return true																			; ...	notify caller that changes occurred
		}
		return false																			; otherwise, NO change occurred
	}
	;############################################################################
	Resize(delta) {																				; perform loupe win resize operations
		h		:= this._getHeights()															; get cur loupe height and max allowed
		newVal	:= Round(scaled(this.PxH + delta) + this.OffsetY)								; new value for height, if allowed
		newSz	:= (!this._isSizeOk()) ? this.DefPxCnt											; if size already too big, resize to default val
				: ((delta < 1 || newVal <= h.maxH) ? this.RCPxCnt+delta : 0)					; determine whether new size is ok or not
		if (newSz < 100)																		; prevent text from clipping at edges of control
			return
		this.PxW := this.RCPxCnt := newSz														; set new width for loupe win
		this._gdiUpdate(), this.Move(,,this.PxW,this.PxH)										; update win size/view for new dimensions
		tiW := this.txtW, tiH := this.txtInfoH - this.BdrGap									; set width/height for color info box
		this.txtInfo.Move(this.BdrGap, this.RCPxCnt, tiW, tiH)									; resize color info box
		this.txtStus.Move(this.BdrGap, this.txtStusY, tiW, this.txtStusH)						; resize status info box
		cfg.Save('RCPxCnt',this.RCPxCnt)														; save cur pixel COUNT for single row of loupe
	}
	;############################################################################
	SavePos() {																					; ensures custom win pos is saved
		this.GetPos(&x,&y)																		; get cur win x/y
		this.winX := x, this.winY := y															; save locally
		cfg.Save('LoupPosX',x), cfg.Save('LoupPosY',y)											; save to cfg and ini
	}
	;############################################################################
	_showGui() {																				; show loupe gui, enable timer for updates
		this.IsActive := 1																		; flag as visible
		if (this.LoupLock) {																	; if loupe gui pos is locked/static...
			gX := this.winX, gY := this.winY													; ... use static x/y values
		} else {																				; otherwise...
			MouseGetPos(&mX,&mY), gX := mX+this.OffsetX, gY := mY+this.OffsetY					; ... set pos near mouse
			this.winX := gX, this.winY := gY													; update local properties
		}
		this.UpdateLoup(1)	; force loupe update while hidden									; softens abrupt painting
		this.Show(Format('hide x{} y{} w{} h{}', gX, gY, this.PxW, this.PxH))					; hide initially, for better animation effect
		guiWinFade(this, 1, 1000)																; animate entrance
		this.Show()																				; make it permanent
		SetTimer(this.LoupUpdateCB, 16)															; enable normal loupe updates
	}
	;############################################################################
	ToggleActive() {																			; toggles whether tool is activate or not
		if (this.IsActive ^= 1)																	; if IS active...
			this._showGui(), this.UpdateLoup(1)													; ... show, and force update
		else
			this._hideGui()																		; otherwise, hide loupe gui
	}
	;############################################################################
	ToggleLock() {																				; toggles whether loupe gui is locked at static position
		if (this.LoupLock ^= 1)																	; if LoupLock is enabled...
			this.SavePos()																		; ... save the cur x/y pos
		cfg.Save('LoupLock', this.LoupLock)														; save LoupLock state
		this._updateStatus()																	; update status bar with current lock condition
		guiForceLoupeUpdate(500)																; force a loupe image update
	}
	;############################################################################
	; 2026-06-29, UPDATED to support multi-display setups
	UpdateLoup(force:=0) {																		; updates loupe using a timer, but can be forced as well
		global ghLoupDC, ghMLoupDC																; global vars improve performance
		static sUpdating := 0																	; might help with performance
		if (sUpdating)																			; if already updating...
			return																				; ... may help performance
		if (!force && !this._needsUpdate())	{													; if no changes are detected...
			sUpdating := 0																		; ... reset
			return																				; ... no need for update
		}
		sUpdating := 1																			; flag as updating
		RCPxScl := this.RCPxScl, RCSqCnt := this.RCSqCnt										; use local vars
		MouseGetPos(&mX, &mY)																	; get current mouse position
		pxPerSqr	:= RCPxScl / RCSqCnt														; [pixels per loupe square]
		halfLoup	:= Floor(RCSqCnt / 2)														; [number of LOUPE SQUARES on either side of center]
		cStart		:= Floor(halfLoup * pxPerSqr)												; [number of PIXELS on either side of center]
		cEnd		:= cStart + Ceil(pxPerSqr)													; include center square also
		; get src and dest coords, width, height for drawing
		; also need to make adjustments at screen edges
		srcX := mX - halfLoup, srcY := mY - halfLoup											; coords that will begin screen capture
		dstX := 0, dstY := 0, drawW := RCSqCnt, drawH := RCSqCnt
		; get min/max dimensions from monitor where mouse is
		mon := clsMonitor.hostDisplay(mX,mY)													; get details of display where mouse is
		minX := mon.bL	; gVD.vX																; get left-edge  of monitor BOUND area
		maxX := mon.bR	; gVD.vW																; get right-edge of monitor BOUND area
		minY := mon.bT	; gVD.vY																; get top-edge	 of monitor BOUND area
		maxY := mon.bB	; gVD.vH																; get bot-edge	 of monitor BOUND area
		if (srcX < minX) {
			drawW	:= Abs(srcX	- minX)
			dstX	:= Round(drawW * pxPerSqr)
			srcX	:= minX
		}
		if (srcY < minY) {
			drawH	:= Abs(srcY - minY)
			dstY	:= Round(drawH * pxPerSqr)
			srcY	:= minY
		}
		if (srcX + drawW > maxX)
			drawW := maxX - srcX
		if (srcY + drawH > maxY)
			drawH := maxY - srcY
		; draw to loupe canvas
		DllCall('BitBlt', 'Ptr', ghMLoupDC, 'Int', 0, 'Int', 0, 'Int', RCPxScl					; start with black loupe canvas
			, 'Int', RCPxScl, 'Ptr', 0, 'Int', 0, 'Int', 0, 'UInt', 0x00000042)					; ... needed when capturing screen edges
		hScrnDC := DllCall('GetDC', 'Ptr', 0, 'Ptr')											; get screen device context
		DllCall('StretchBlt',																	; stretch screen image onto loupe canvas
			'Ptr', ghMLoupDC,
			'Int', dstX, 'Int', dstY,
			'Int', Round(drawW * pxPerSqr),
			'Int', Round(drawH * pxPerSqr),
			'Ptr', hScrnDC,
			'Int', srcX,
			'Int', srcY,
			'Int', drawW, 'Int', drawH,
			'UInt', 0x00CC0020	)
		targClr	:= DllCall('GetPixel','Ptr',hScrnDC, 'Int',mX, 'Int',mY,'UInt')					; get pixel color at mouse pointer
		clrs	:= this._getClrInfo(targClr)													; process/return color details
		this._updateInfoText(mX,mY,clrs)														; update text details
		this._drawCrossHairs(clrs.xHairClr, cStart, cEnd)										; draw cross-hairs to loupe canvas
		this._hlCenterPx(cStart,cEnd)															; highlight center square
		this._hlFrame()					; must be done after text update						; add contrast frame to loupe gui
		DllCall('BitBlt','Ptr',ghLoupDC,'Int',0,'Int',0,'Int',RCPxScl							; transfer all updates to loupe gui canvas
				,'Int',RCPxScl,'Ptr',ghMLoupDC,'Int',0,'Int',0,'UInt',0x00CC0020)
		DllCall('ReleaseDC', 'Ptr', 0, 'Ptr', hScrnDC)											; discard screen DC resource
		this._updateLoupPos()																	; move loupe gui relative to mouse position
		sUpdating := 0																			; reset
	}
	;############################################################################
	; 2026-06-29, UPDATED to support multi-display setups
	_updateLoupPos() {																			; reposition loupe gui relative to mouse pos
		static xDir := 0, yDir := 0, sUpdating := 0
		if (this.LoupLock) {																	; if loupe gui is locked in static pos...
			sUpdating := 0																		; ... ensure reset
			return																				; ... do not reposition it
		}
		if (sUpdating)																			; if already updating...
			return																				; ... may help with performance
		if (!this._isSizeOk()) {																; if loupe gui is too big for auto-wrapping...
			sUpdating := 0
			this.Resize(0)																		; ... resize loupe gui
		}
		sUpdating := 1																			; flag as updating
		offsetX := this.OffsetX, offsetY := this.OffsetY										; use local vars
		MouseGetPos(&mX, &mY)																	; get current mouse coords
		WinGetPos(&rX, &rY, &rW, &rH, ghLoup)													; get SCALED loupe gui dimensions
		; get details of monitor where mouse is
		mon := clsMonitor.hostDisplay(mX,mY)													; get details of display where mouse is
		minX := mon.aL	; gVD.vX																; get left-edge  of monitor ACTIVE area
		maxX := mon.aR	; gVD.vW																; get right-edge of monitor ACTIVE area
		minY := mon.aT	; gVD.vY																; get top-edge	 of monitor ACTIVE area
		maxY := mon.aB	; gVD.vH																; get bot-edge	 of monitor ACTIVE area
		;########################################################################
		; x-axis
		if (xDir = 0) {
			; if moving R and win hits R edge, flip loupe to L of mouse pointer
			if (mX + offsetX + rW > maxX) {														; if loupe-win hits right-edge
				gX := mX - rW - offsetX, xDir := 1												; ... flip loupe-win to left of mouse pointer
			} else {																			; otherwise...
				gX := mX + offsetX																; ... keep moving right, no change to mouse/win orientation
			}
		} else { ; xDir = 1
			; only flip back to R side of mouse when loupe reaches L edge
			if (mX - rW -offsetX < minX) {														; if loupe-win hits left-edge
				gX := mX + offsetX, xDir := 0													; ... flip loupe-win to right of mouse pointer
			} else {																			; otherwise...
				gX := mX - rW - offsetX															; ... keep moving left, no change to mouse/win orientation
			}
		}
		;########################################################################
		; y-axis
		if (yDir = 0) {
			; if moving dn and win hits bot edge, flip loupe above mouse pointer
			if (mY + offsetY + rH > maxY) {														; if loupe-win hits bot-edge
				gY := mY - rH - offsetY, yDir := 1												; ... flip loupe-win above mouse pointer
			} else {																			; otherwise...
				gY := mY + offsetY																; ... keep moving down, no change to mouse/win orientation
			}
		} else { ; yDir = 1
			; only flip below mouse pointer when loupe reaches top edge
			if (mY - rH - offsetY < minY) {														; if loupe-win hits top-edge
				gY := mY + offsetY, yDir := 0													; ... flip loupe-win below mouse pointer
			} else {																			; otherwise...
				gY := mY - rH - offsetY															; ... keep moving up, no change to mouse/win orientation
			}
		}
		;########################################################################
		; safety overrides to prev loupe clipping under taskbars/edges
		mon := clsMonitor.hostDisplay(gX,gY)													; get updated monitor details for loupe-win new location
		minX := mon.aL																			; get left-edge  of monitor ACTIVE area
		maxX := mon.aR																			; get right-edge of monitor ACTIVE area
		minY := mon.aT																			; get top-edge	 of monitor ACTIVE area
		maxY := mon.aB																			; get bot-edge	 of monitor ACTIVE area
		if (gX < minX)																			; if loupe-win left-edge is to left of monitor left-edge...
			gX := minX																			; ... place loupe-win left-edge at monitor left-edge
		if (gY < minY)																			; if loupe-win top-edge is above monitor top-edge...
			gY := minY																			; ... place loupe-win top-edge at monitor top-edge
		if (gX + rW > maxX)																		; if loupe-win right-edge is past monitor right-edge...
			gX := maxX - rW																		; ... place loupe-win at monitor right-edge
		if (gY + rH > maxY)																		; if loupe-win bottom-edge is below monitor bottom-edge...
			gY := (maxY) - rH																	; ... place loupe-win at monitor bottom-edge

		WinMove(gX,gY,,,ghLoup)																	; loupe-win final destination
		sUpdating := 0																			; reset
	}
	;############################################################################
	_updateStatus() {																			; update status bar text
		lock := '  ' . ((this.LoupLock) ? '🔒' : '🔓')											; set lock icon
		this.txtStus.Value := lock
	}
	;############################################################################
	_updateInfoText(x,y,clrs) {																	; updates text area of display
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
	ZoomIn() {																					; increase magnification
		if (this.RCSqCnt > this.RCSqMin) {
			this.RCSqCnt -= 2, cfg.Save('RCSqCnt',this.RCSqCnt)
		}
	}
	;############################################################################
	ZoomOut() {																					; decrease magnification
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
	'F8:Toggle loupe tool on/off',
	'Alt + C:Copy All info to clipboard',
	'Alt + H:Copy Hex value to clipboard',
	'Alt + L:Lock loupe at current position',
	'Alt + S:Show shortcuts list (this)',
	'Escape:Close shortcuts list (this)',
	'Arrow Keys:Adjust mouse pos +/-   1',
	'Alt + Arrow Keys:Adjust mouse pos +/- 10',
	'Shift + Arrows/Wheel:Resize loupe window',
	'Ctrl  + Arrows/Wheel:Adjust loupe magnification',
	'Ctrl  + Escape:Quit App']
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
		this._chkHK := this.Add('Checkbox', Format('vchkHK right x{} y{} w{}'
								, 240, 25, 115), 'Show at launch')
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
	_pad	:= scaled(15)																		; splash gui edge padding
	_bxSz	:= scaled(40)																		; size of individual squares for cube
	_Sz		:= scaled(175)																		; general target size for splash screen
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
		this.Add('Text',Format(fmtStr,pad,		 pad,		bxSz, bxSz, cRed ))
		this.Add('Text',Format(fmtStr,pad+bxSz,	 pad,		bxSz, bxSz, cGrn ))
		this.Add('Text',Format(fmtStr,pad+bxSz*2,pad,		bxSz, bxSz, cBlue))
		; middle row
		this.Add('Text',Format(fmtStr,pad,		 pad+bxSz,	bxSz, bxSz, cOrng))
		this.Add('Text',Format(fmtStr,pad+bxSz,  pad+bxSz,	bxSz, bxSz, cWhte))
		this.Add('Text',Format(fmtStr,pad+bxSz*2,pad+bxSz,	bxSz, bxSz, cPrpl))
		; bottom row
		this.Add('Text',Format(fmtStr,pad,		 pad+bxSz*2,bxSz, bxSz, cYelw))
		this.Add('Text',Format(fmtStr,pad+bxSz,  pad+bxSz*2,bxSz, bxSz, cMgta))
		this.Add('Text',Format(fmtStr,pad+bxSz*2,pad+bxSz*2,bxSz, bxSz, cCyan))
		; add title text
		this.SetFont('s10 cWhite Bold','Segoe UI'),fmtStr:='x{} y{} w{} right'
		this.Add('Text',Format(fmtStr, pad, pad+bxSz*3+10,bxSz*3),'HUE-HACKER')
		this.SetFont('s8 c0X777777', 'Segoe UI')
		vers := StrReplace(gAppVers,'-')
		this.Add('Text', Format(fmtStr, pad, pad+bxSz*3+30, bxSz*3), vers)
	}
	;############################################################################
	_drawReticle() {																			; draw cross-hair on splash screen
		hwnd := this.hwnd
		hdc := DllCall('GetDC', 'Ptr', hwnd, 'Ptr')
		; grab splash gui dimensions
		rect := Buffer(16, 0)
		DllCall('GetClientRect', 'Ptr', hwnd, 'Ptr', rect)
		w := NumGet(rect, 8, 'Int'), h := NumGet(rect, 12, 'Int')
		; use double buffer to keep the cross-hair rendering instant
		hdcMem:= DllCall('CreateCompatibleDC', 'Ptr', hdc, 'Ptr')
		hBmp  := DllCall('CreateCompatibleBitmap','Ptr',hdc,'Int',w,'Int',h,'Ptr')
		oldBmp:= DllCall('SelectObject', 'Ptr', hdcMem, 'Ptr', hBmp, 'Ptr')
		; place the gui image into this buffer
		DllCall('BitBlt', 'Ptr', hdcMem, 'Int', 0, 'Int', 0, 'Int', w, 'Int', h
			, 'Ptr', hdc, 'Int', 0, 'Int', 0, 'UInt', 0x00CC0020)
		; high-contrast drawing pens for cross-hair
		hBlackPen := DllCall('CreatePen','Int',0,'Int',4,'UInt',0x000000,'Ptr')
		hWhitePen := DllCall('CreatePen','Int',0,'Int',2,'UInt',0xFFFFFF,'Ptr')
		; cross-hair position
		tX1	 := this._ctrBx.X1, tY1 := this._ctrBx.Y1
		tX2	 := this._ctrBx.X2, tY2 := this._ctrBx.Y2
		midX := tX1+((tX2 - tX1) / 2), midY := tY1+((tY2 - tY1) / 2), ext := 12					; cross hair centered on center square
		midX := scaled(midX), midY := scaled(midY), ext := scaled(ext)							; ensure cross-hair pos is adj for scaling
		midX *= .88, midY *= .88																; OPTIONAL - include dynamic offset
		; paint cross-hair over the cube
		Loop 2 {
			currentPen := (A_Index == 1) ? hBlackPen : hWhitePen
			oldObj := DllCall('SelectObject','Ptr',hdcMem,'Ptr',currentPen,'Ptr')
			DllCall('MoveToEx','Ptr',hdcMem, 'Int',midX-ext,'Int',midY,'Ptr',0)
			DllCall('LineTo', 'Ptr', hdcMem, 'Int', midX - 2, 'Int', midY)
			DllCall('MoveToEx','Ptr',hdcMem, 'Int', midX + 2,'Int',midY,'Ptr',0)
			DllCall('LineTo', 'Ptr', hdcMem, 'Int', midX + ext, 'Int', midY)
			DllCall('MoveToEx','Ptr',hdcMem, 'Int', midX,'Int',midY-ext,'Ptr',0)
			DllCall('LineTo', 'Ptr', hdcMem, 'Int', midX,'Int',midY-2)
			DllCall('MoveToEx','Ptr',hdcMem, 'Int', midX,'Int',midY+2,'Ptr',0)
			DllCall('LineTo', 'Ptr', hdcMem, 'Int', midX,'Int',midY+ext)
			DllCall('SelectObject', 'Ptr', hdcMem, 'Ptr', oldObj, 'Ptr')
		}
		; blast the combined images to screen in one shot
		DllCall('BitBlt', 'Ptr', hdc, 'Int', 0, 'Int', 0, 'Int', w, 'Int', h
			, 'Ptr', hdcMem, 'Int', 0, 'Int', 0, 'UInt', 0x00CC0020)
		; clean up
		DllCall('DeleteObject', 'Ptr', hBlackPen)
		DllCall('DeleteObject', 'Ptr', hWhitePen)
		DllCall('SelectObject', 'Ptr', hdcMem, 'Ptr', oldBmp, 'Ptr')
		DllCall('DeleteObject', 'Ptr', hBmp)
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
;################################################################################
; clsMonitor - gathers info about system monitors
;################################################################################
Class clsMonitor
{
	Static MonList	:= []

	isPrim	:= 0
	_name	:= ''
	Name	=> RegExReplace(this._name, '[\\.]')
	bL		:= 0																				; left-edge	 of bounding box
	bR		:= 0																				; right-edge of bounding box
	bT		:= 0																				; top-edge	 of bounding box
	bB		:= 0																				; bot-edge	 of bounding box
	aL		:= 0																				; left-edge	 of working area
	aR		:= 0																				; right-edge of working area
	aT		:= 0																				; top-edge	 of working area
	aB		:= 0																				; bot-edge	 of working area
	;############################################################################
	__New(name,bL,bT,bR,bB,aL,aT,aR,aB) {
		this._name := name
		this.bL := bL, this.bT := bT, this.bR := bR, this.bB := bB
		this.aL := aL, this.aT := aT, this.aR := aR, this.aB := aB
	}
	;############################################################################
	Static _boundWithin(obj, x,y) {
		if (!(obj is clsMonitor)) {
			return 0
		}
		return (x >= obj.bL && x <= obj.bR && y >= obj.bT && y <= obj.bB)
		;return (x >= obj.aL && x <= obj.aR && y >= obj.aT && y <= obj.aB)
	}
	;############################################################################
	Static GetMonitorFromPoint(x,y) {
		pt := (x & 0xFFFFFFFF) | (y << 32)
		return DllCall("MonitorFromPoint", "Int64", pt, "UInt", 0x2, "Ptr")						; return handle of monitor
	}
	;############################################################################
	Static GetMonitorProfiles() {
		prim := MonitorGetPrimary()
		loop MonitorGetCount() {
			curMon	:= MonitorGet(A_Index, &bL, &bT, &bR, &bB)
			curMon	:= MonitorGetWorkArea(A_Index, &aL, &aT, &aR, &aB)
			name	:= MonitorGetName(A_Index)
			monProf := clsMonitor(name,bL,bT,bR,bB,aL,aT,aR,aB)
			monProf.isPrim := !!(curMon = prim)
			this.MonList.Push(monProf)
		}
	}
	;############################################################################
	Static HostDisplay(x,y) {
		for i, obj in this.monList {
			if (this._boundWithin(obj,x,y))
				return obj
		}
		msg := '`nUnable to identify Host Display for coords:`n[' x ', ' y ']'
		throw(A_ThisFunc msg)
	}
}
;#################################  FUNCTIONS  ##################################
;################################################################################
																 getDisplayInfo()				; get details related to display
;################################################################################
{
	getScale()																					; grab dpi scaling from system
	getVirtualDimensions()																		; grab virtual display dimensions (for multi-display support)
	clsMonitor.getMonitorProfiles()																; grab profiles for monitors
}
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
													  guiForceLoupeUpdate(dur:=0)				; forces a loupe update for specified duration
;################################################################################
{
	static start := 0, maxDur := 1000
	if (!gLoup.IsActive) {																		; if loupe tool in NOT active...
		setTimer(%A_ThisFunc%, 0), start := 0													; ... disable timer
		return
	}
	if (dur) {																					; if new duration request...
		setTimer(%A_ThisFunc%, 0)																; ... reset, just in case
		maxDur := dur, start := A_TickCount														; set new max dur and start time
		setTimer(%A_ThisFunc%, 20)																; start the timer for this callback
		return
	}
	; timer is running... check to see if max time is exceeded
	elapsed := A_TickCount - start																; get elapsed time since timer started
	if (elapsed >= maxDur) {																	; if elapsed has exceeded max time...
		setTimer(%A_ThisFunc%, 0), start := 0													; ... disable timer
		return
	}
	gLoup.UpdateLoup(1)																			; force an update to loupe gui
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
	if (hwnd = gLoup.Hwnd)
		return 1																				; ... BUT ONLY return a value for loupe gui!
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
	;SendMessage(0x0080, 0, hIcon, gLoup.Hwnd) ; WM_SETICON (Small Icon)
	;SendMessage(0x0080, 1, hIcon, gLoup.Hwnd) ; WM_SETICON (Large Icon)
}
;################################################################################
																	scaled(value)				; applies scaling to passed setting
;################################################################################
{
	return value * getScale()
}
;################################################################################
										 WM_DPICHANGED(wParam, lParam, msg, hwnd)				; allows loupe gui to detect dpi changes on the fly
;################################################################################
{
	if (hwnd != gLoup.hwnd)
		return
	; dpi has changed - make adustments
	getScale()																					; get new scale
	getVirtualDimensions()																		; get full virtual display dimensions
	gLoup.Resize(0)																				; resize loupe gui as needed
	guiForceLoupeUpdate(1000)																	; force loupe update
}
;################################################################################
										WM_LBUTTONDOWN(wParam, lParam, msg, hwnd)				; allows user to move HKList or loupe guis if desired
;################################################################################
{
	if (WinGetTitle(hwnd) = 'HHHKLIST') {														; if user is moving HKList...
		PostMessage(0xA1,2,,,hwnd)																; ... allow click/move anywhere in window
		KeyWait("LButton")																		; ... wait for user to release left mouse button
		gHKGui.SavePos()																		; ... save new win pos
	}
	if (hwnd = gLoup.Hwnd && gLoup.LoupLock) {													; if user is moving loupe gui...
		PostMessage(0xA1,2,,,hwnd)																; ... allow click/move anywhere in window
		KeyWait("LButton")																		; ... wait for user to release left mouse button
		gLoup.SavePos()																			; ... save new win pos
	}
}
;################################################################################
													  shellMsg(wParam, lParam, *)				; get notified when active window changes
;################################################################################
{
	if (!gLoup.IsActive)
		return
	; 4 = HSHELL_WINDOWACTIVATED, 32772 = HSHELL_RUDELEVELTOPACTIVATED
	if (wParam = 4 || wParam = 32772) {															; if active window changed...
		guiForceLoupeUpdate(1500)																; ... force an update to loupe gui
	}
}
;#################################  SHORTCUTS  ##################################
;################################################################################
#HotIf			(gInitialized && gLoup.IsActive)												; hotkeys only work when tool is active
+Up::
+Right::
+WheelUp::			gLoup.Resize(10)
+Down::
+Left::
+WheelDown::		gLoup.Resize(-10)
^Up::
^WheelUp::			gLoup.ZoomIn()
^Down::
^WheelDown::		gLoup.ZoomOut()
~WheelUp::
~WheelDown::
~LButton::
~RButton::			guiForceLoupeUpdate(1000)													; forces update for mouse clicks/scrolling
~Up::				MouseMove(0, -1,  0, 'R')
~Down::				MouseMove(0,  1,  0, 'R')
~Left::				MouseMove(-1, 0,  0, 'R')
~Right::			MouseMove(1,  0,  0, 'R')
!Up::				MouseMove(0, -10, 0, 'R')
!Down::				MouseMove(0,  10, 0, 'R')
!Left::				MouseMove(-10, 0, 0, 'R')
!Right::			MouseMove(10,  0, 0, 'R')
!h::
!c::				gLoup.CopyToClip(A_ThisHotkey)
!l::				gLoup.ToggleLock()
#HotIf			(gInitialized && !WinActive('HHHKLIST'))										; do not show HK list if currently displayed
!s::				guiHKListShow()
#HotIf			(gInitialized)																	; hotkeys that work whether tool is active or not
~Esc::				guiHKListHide()																; close HK list if open
^Esc::				AppClose()																	; quit app
F8::				gLoup.ToggleActive()														; show/hide loupe gui
#HotIf
;################################################################################
;################################################################################
; Base64 ICO to HICON engine func
Base64ICO_to_HICON(Base64ICO) {
	Local BLen		:= StrLen(Base64ICO)
	Local nBytes	:= Floor(StrLen(RTrim(Base64ICO, "=")) * 3 / 4)
	Local Bin		:= Buffer(nBytes)

	; decode Base64 string into binary memory buffer
	If (!DllCall("Crypt32\CryptStringToBinary", "Str", Base64ICO, "UInt", BLen
		, "UInt", 1, "Ptr", Bin, "UIntP", &nBytes, "Ptr", 0, "Ptr", 0))
		Return 0
	; find offset where raw icon bits actually begin inside ICO container
	; an ICO file structure stores image offset at byte pos 18 (Directory Entry)
	Local icoOffset	:= NumGet(Bin, 18, "UInt")
	Local icoSize	:= NumGet(Bin, 14, "UInt")
	; create HICON pointer using exact data bits offset
	Local pBits		:= Bin.Ptr + icoOffset
	Return DllCall("CreateIconFromResourceEx", "Ptr", pBits, "UInt", icoSize
		, "Int", True, "UInt", 0x30000, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
}
;################################################################################
appIco() {																						; app icon Base64 string
return "AAABAAEAUlIAAAEAIAAQbQAAFgAAACgAAABSAAAApAAAAAEAIAAAAAAAEGkAAHQSAAB0EgAAAAAAAAAAAAAaGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//wAAAP8AAAD/AAAA/wAAAP//AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///////8AAAD/AAAA/wAAAP8AAAD/AAAA//8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD//wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP//AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A//8AAAD/AAAA/wAAAP8AAAD/AAAA////////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//AAAA/wAAAP8AAAD/AAAA/wAAAP//AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///////wAAAP8AAAD/AAAA/wAAAP8AAAD//wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP//AAAA//8A////AP///wD///8A////AP//AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA//8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD//wAAAP///////wD///8A////AP///wD//wAAAP8AAAD/AAAA/wAAAP8AAAD///////8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////Ghoa/xoaGv8aGhr//wD///8A////AP///wD///8A////AP///wD///8A//8AAAD/AAAA/wAAAP//AP///wD///8A//8AAAD/AAAA/wAAAP8AAAD/AAAA//8A////AP///wD///8A////AP///wD//xoaGv8aGhr///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A/xoaGv8aGhr/AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///xoaGv8aGhr/Ghoa//8A////AP///wD///8A////AP///wD///8A////AP//AAAA/wAAAP8AAAD///////8A////////AAAA/wAAAP8AAAD/AAAA/wAAAP//AP///wD///8A////AP///wD///8A//8aGhr/Ghoa////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP8aGhr/Ghoa/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8aGhr/Ghoa/xoaGv//AP///wD///8A////AP///wD///8A////AP///wD//wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD//wD///8A////AP///wD///8A////AP//Ghoa/xoaGv///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP////////////////////////////////////////////////8AAAD/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP//////////////////////////////////////AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD//////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT//////////////////////////////////////wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD///////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP//////////////////////////////////////AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD//////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT//////////////////////////////////////wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD///////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP//////////////////////////////////////AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD//////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT//////////////////////////////////////wAAAP8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD///////////////////////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD/////////////////////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP//////////////////////////////////////AAAA/wAAAP8AAAD/AAAA/wAAAP8AAAD//////////////////////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT//////////////////////////////////////wAAAP8AAAD/AAAA/wAAAP8AAAD///////////////////////////////////////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/AAAA/wAAAP8AAAD/////////////////////////////////////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP//////////////////////////////////////AAAA/wAAAP8AAAD//////////////////////////////////////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT//////////////////////////////////////wAAAP8AAAD///////////////////////////////////////////////////////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk//////////////////////////////////////8AAAD/////////////////////////////////////////////////////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//Ghoa/xoaGv8aGhr/ZGRk////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////ZGRk/xoaGv8aGhr//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI/xoaGv8aGhr/AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//xoaGv8aGhr/Ghoa/2RkZP///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////2RkZP8aGhr/Ghoa//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP8aGhr/Ghoa/wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8AgP//AID//wCA//8aGhr/Ghoa/xoaGv9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/ZGRk/2RkZP9kZGT/Ghoa/xoaGv//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj//wCI//8AiP//AIj/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//xoaGv8aGhr/Ghoa/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8aGhr/Ghoa//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8aGhr/Ghoa/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8aGhr/Ghoa/xoaGv8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/Ghoa/xoaGv//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD/Ghoa/xoaGv8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//Ghoa/xoaGv8aGhr/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/wD/AP8A/xoaGv8aGhr//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/Ghoa/xoaGv8aGhr/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
}
