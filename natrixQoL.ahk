#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true
Persistent(true)

global APP_VERSION := "2.3.0"

SetWorkingDir(A_ScriptDir)

if (!A_IsAdmin && !InStr(DllCall("GetCommandLine", "Str"), "/restart")) {
    try {
        Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"', A_ScriptDir)
        ExitApp()
    }
}

InstallKeybdHook(true, true)
InstallMouseHook(true, true)

global sevenZip := Find7Zip()
global SEVEN_CLI := sevenZip.cli
global SEVEN_GUI := sevenZip.gui
global ARCHIVE_EXT := "zip|rar|7z|tar|gz|tgz|bz2|tbz|tbz2|xz|txz|zst|tzst|iso|cab|arj|lzh|lha|wim|001|z01|r00"
global OVERWRITE_MODE := "-aou"
global PNG_CLIP_FMT := DllCall("RegisterClipboardFormat", "str", "PNG", "uint")
global lastClipSeq := 0
global lastClipImagePath := ""

A_IconTip := "natrixQoL " APP_VERSION " (QuickExtract | AutoType | SnipPath)"
SetupTrayMenu()
CleanupOldTempSnips()
OnClipboardChange(OnClipChange)

SetupTrayMenu() {
    tray := A_TrayMenu
    tray.Delete()

    tray.Add("natrixQoL " APP_VERSION, (*) => "")
    tray.Disable("natrixQoL " APP_VERSION)
    tray.Add()

    helpMenu := Menu()
    helpMenu.Add("Ctrl+Shift+Win - Quick Extract Archive", (*) => "")
    helpMenu.Add("Ctrl+Shift+F2  - Type Email", (*) => "")
    helpMenu.Add("Ctrl+Shift+F3  - Generate & Type Password", (*) => "")
    helpMenu.Add("Ctrl+Shift+F4  - Show RTSS Window", (*) => "")
    helpMenu.Add("Ctrl+Shift+F5  - Open Gemini", (*) => "")
    helpMenu.Add("Ctrl+V (Dialog) - Paste Clipboard Image Temp Path", (*) => "")
    for idx in [1, 2, 3, 4, 5, 6]
        helpMenu.Disable(idx "&")
    tray.Add("Hotkey Cheatsheet", helpMenu)

    tray.Add()
    tray.Add("Reload Script", (*) => Reload())
    tray.Add("Exit", (*) => ExitApp())
}

CtrlShiftHeld() {
    return (GetKeyState("Control", "P") || GetKeyState("Control"))
        && (GetKeyState("Shift", "P") || GetKeyState("Shift"))
}

#HotIf CtrlShiftHeld()
*LWin::ExtractSelection()
*RWin::ExtractSelection()
#HotIf

#HotIf ShouldPasteImagePath()
$^v::PasteClipboardImagePath()
#HotIf

^+F2::
{
    SendInput("{Ctrl Up}{Shift Up}")
    Sleep(25)
    SendText("natrix852@gmail.com")
}

^+F3::
{
    SendInput("{Ctrl Up}{Shift Up}")
    Sleep(25)
    password := GenerateComplexPassword(16)
    A_Clipboard := password
    SendText(password)
}

^+F4::
{
    ShowRTSS()
}

^+F5::
{
    Run("https://gemini.google.com")
}

GenerateComplexPassword(length := 16) {
    lower := "abcdefghijklmnopqrstuvwxyz"
    upper := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    digits := "0123456789"
    symbols := "!@#$%^&*()_+-=[]{}|;:,.<>?"
    allChars := lower . upper . digits . symbols

    pwd := SubStr(lower, Random(1, StrLen(lower)), 1)
         . SubStr(upper, Random(1, StrLen(upper)), 1)
         . SubStr(digits, Random(1, StrLen(digits)), 1)
         . SubStr(symbols, Random(1, StrLen(symbols)), 1)

    Loop (length - 4) {
        pwd .= SubStr(allChars, Random(1, StrLen(allChars)), 1)
    }

    arr := StrSplit(pwd)
    Loop arr.Length {
        i := A_Index
        j := Random(1, arr.Length)
        tmp := arr[i]
        arr[i] := arr[j]
        arr[j] := tmp
    }

    shuffled := ""
    for char in arr {
        shuffled .= char
    }
    return shuffled
}

ExtractSelection() {
    static lastSeen := 0
    now := A_TickCount
    if ((now - lastSeen) <= 800)
        return
    lastSeen := now

    selection := GetExplorerSelection()
    if (selection.Length = 0) {
        NotifyQoL("Nothing Selected", "Focus Explorer or Desktop and select an archive.")
        return
    }

    jobs := []
    for path in selection {
        if IsExtractable(path)
            jobs.Push(path)
    }
    if (jobs.Length = 0) {
        NotifyQoL("No Archives Selected", "Supported formats: " StrReplace(ARCHIVE_EXT, "|", " "))
        return
    }

    for path in jobs {
        ExtractArchive(path, jobs.Length > 1)
    }
}

ExtractArchive(path, wait := false) {
    global SEVEN_GUI, OVERWRITE_MODE
    SplitPath(path, &fileName, &dir)

    info := AnalyzeArchive(path)
    password := ""

    if (info.needPassword) {
        promptMsg := "Archive is password-protected.`nEnter password for:`n" fileName
        loop {
            ib := InputBox(promptMsg, "Quick Extract - Password Required", "Password* W400 H140")
            if (ib.Result != "OK" || ib.Value == "") {
                NotifyQoL("Extraction Cancelled", fileName)
                return 1
            }

            candidate := ib.Value
            if VerifyPassword(path, candidate) {
                password := candidate
                info := AnalyzeArchive(path, password)
                break
            } else {
                promptMsg := "Incorrect password. Please try again:`n" fileName
            }
        }
    }

    target := info.needsOwnFolder ? (dir "\" BaseName(path)) : dir
    passArg := (password != "") ? (' -p' . EscapeArg(password)) : ''
    cmd := '"' SEVEN_GUI '" x ' OVERWRITE_MODE ' -o"' target '"' passArg ' -- "' path '"'

    if (wait)
        return RunWait(cmd, dir)
    Run(cmd, dir)
    return 0
}

AnalyzeArchive(path, password := "") {
    global SEVEN_CLI
    static counter := 0
    tmp := A_Temp "\quick_extract_" A_TickCount "_" (++counter) "_" Random(1000, 9999) ".txt"

    passArg := (password != "") ? (' -p' . EscapeArg(password)) : ' -p""'
    cmd := A_ComSpec ' /c ""' SEVEN_CLI '" l -slt -ba -sccUTF-8' passArg ' -- "' path '" > "' tmp '" 2>&1"'

    exitCode := RunWait(cmd, , "Hide")
    txt := ""
    try txt := FileRead(tmp, "UTF-8")
    try FileDelete(tmp)

    isHeaderEncrypted := (exitCode != 0) || RegExMatch(txt, "i)(Cannot open encrypted archive|Headers Error|Wrong password)")
    if isHeaderEncrypted {
        return {
            needPassword: true,
            wrongPassword: (password != ""),
            needsOwnFolder: true,
            roots: Map()
        }
    }

    roots := Map()
    hasEncryptedData := false

    for line in StrSplit(txt, "`n", "`r") {
        if (SubStr(line, 1, 7) = "Path = ") {
            rel := SubStr(line, 8)
            parts := StrSplit(rel, ["\", "/"])
            if (parts.Length > 0 && parts[1] != "")
                roots[parts[1]] := true
        } else if (SubStr(line, 1, 12) = "Encrypted = +") {
            hasEncryptedData := true
        }
    }

    isEncrypted := hasEncryptedData
    needsOwnFolder := (roots.Count != 1)

    if (isEncrypted && password == "") {
        return {
            needPassword: true,
            wrongPassword: false,
            needsOwnFolder: needsOwnFolder,
            roots: roots
        }
    }

    return {
        needPassword: false,
        wrongPassword: false,
        needsOwnFolder: needsOwnFolder,
        roots: roots
    }
}

VerifyPassword(path, password) {
    global SEVEN_CLI
    static counter := 0
    tmp := A_Temp "\quick_extract_v_" A_TickCount "_" (++counter) "_" Random(1000, 9999) ".txt"
    cmd := A_ComSpec ' /c ""' SEVEN_CLI '" t -p' EscapeArg(password) ' -- "' path '" > "' tmp '" 2>&1"'
    exitCode := RunWait(cmd, , "Hide")
    txt := ""
    try txt := FileRead(tmp, "UTF-8")
    try FileDelete(tmp)

    if (exitCode != 0 || RegExMatch(txt, "i)(Wrong password|Cannot open encrypted archive|Headers Error)"))
        return false
    return true
}

Find7Zip() {
    candidates := []
    for pf in [EnvGet("ProgramFiles"), EnvGet("ProgramFiles(x86)"), EnvGet("LocalAppData") "\Programs"] {
        if (pf != "") {
            candidates.Push(pf "\7-Zip\7z.exe")
            candidates.Push(pf "\7-Zip\7zG.exe")
        }
    }
    for root in ["HKLM", "HKCU"] {
        try {
            regPath := RegRead(root "\SOFTWARE\7-Zip", "Path")
            if (regPath != "") {
                candidates.Push(RTrim(regPath, "\") "\7z.exe")
                candidates.Push(RTrim(regPath, "\") "\7zG.exe")
            }
        }
    }
    for dir in StrSplit(EnvGet("PATH"), ";") {
        trimmed := Trim(dir)
        if (trimmed != "") {
            candidates.Push(RTrim(trimmed, "\") "\7z.exe")
            candidates.Push(RTrim(trimmed, "\") "\7zG.exe")
        }
    }

    cli := ""
    gui := ""
    for p in candidates {
        if (cli == "" && RegExMatch(p, "i)7z\.exe$") && FileExist(p))
            cli := p
        if (gui == "" && RegExMatch(p, "i)7zG\.exe$") && FileExist(p))
            gui := p
    }

    if (cli != "" && gui == "")
        gui := cli
    else if (gui != "" && cli == "")
        cli := gui

    return { cli: cli, gui: gui }
}

GetExplorerSelection() {
    paths := []
    hwnd := WinExist("A")
    if !hwnd
        return paths
    cls := WinGetClass(hwnd)
    shell := ComObject("Shell.Application")

    if (cls = "Progman" || cls = "WorkerW") {
        try {
            doc := shell.Windows.Item(ComValue(0x13, 8)).Document
            for item in doc.SelectedItems {
                p := item.Path
                if (p != "")
                    paths.Push(p)
            }
        }
        return paths
    }

    if (cls != "CabinetWClass" && cls != "ExploreWClass")
        return paths

    activeTab := 0
    try activeTab := ControlGetHwnd("ShellTabWindowClass1", hwnd)

    for win in shell.Windows {
        try {
            if (win.hwnd != hwnd)
                continue
            if (activeTab) {
                static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
                shellBrowser := ComObjQuery(win, IID_IShellBrowser, IID_IShellBrowser)
                if shellBrowser {
                    ComCall(3, shellBrowser, "uint*", &thisTab := 0)
                    if (thisTab != activeTab)
                        continue
                }
            }
            for item in win.Document.SelectedItems {
                p := item.Path
                if (p != "")
                    paths.Push(p)
            }
            if (activeTab)
                break
        }
    }
    return paths
}

IsExtractable(path) {
    global ARCHIVE_EXT
    if !FileExist(path) || DirExist(path)
        return false
    SplitPath(path, , , &ext, &stem)
    if !RegExMatch(ext, "i)^(" ARCHIVE_EXT ")$")
        return false
    if RegExMatch(stem, "i)\.part0*(\d+)$", &m) && (m[1] + 0) != 1
        return false
    if RegExMatch(ext, "i)^([zr])0*(\d+)$", &m) && (m[2] + 0) != 0 && (m[2] + 0) != 1
        return false
    if RegExMatch(ext, "i)^0*(\d+)$", &m) && (m[1] + 0) != 1
        return false
    return true
}

BaseName(path) {
    SplitPath(path, &name, , &ext, &stem)
    base := stem
    base := RegExReplace(base, "i)\.part\d+$", "")
    base := RegExReplace(base, "i)\.(tar|zip|7z|rar|gz|bz2|xz|zst)$", "")
    return base != "" ? base : name
}

EscapeArg(str) {
    if (str = "")
        return '""'
    return '"' . RegExReplace(str, '(\\*)(")', '$1$1\"') . '"'
}

NotifyQoL(title, text) {
    TrayTip(text, title)
    SetTimer(() => TrayTip(), -3000)
}

ShowRTSS() {
    DetectHiddenWindows(true)
    dummyHwnd := WinExist("RTSS ahk_exe RTSS.exe")
    if dummyHwnd {
        WinHide(dummyHwnd)
    }

    DetectHiddenWindows(false)
    guiHwnd := WinExist("RivaTunerStatisticsServer ahk_exe RTSS.exe")
    if guiHwnd {
        WinRestore(guiHwnd)
        WinActivate(guiHwnd)
        return
    }

    if dummyHwnd {
        PostMessage(0x8001, 0, 0x0202, , dummyHwnd)
        if WinWait("RivaTunerStatisticsServer ahk_exe RTSS.exe", , 1) {
            WinRestore("RivaTunerStatisticsServer ahk_exe RTSS.exe")
            WinActivate("RivaTunerStatisticsServer ahk_exe RTSS.exe")
            return
        }
    }

    rtssPath := FindRTSS()
    if (rtssPath != "") {
        Run('"' rtssPath '"')
    }
}

FindRTSS() {
    for root in ["HKLM", "HKCU"] {
        for subKey in ["SOFTWARE\WOW6432Node\Unwinder\RTSS", "SOFTWARE\Unwinder\RTSS"] {
            try {
                p := RegRead(root "\" subKey, "InstallPath")
                if (p != "" && FileExist(p))
                    return p
            }
        }
    }
    defPath := EnvGet("ProgramFiles(x86)") "\RivaTuner Statistics Server\RTSS.exe"
    if FileExist(defPath)
        return defPath
    return ""
}

OnClipChange(dataType) {
    if (dataType = 2)
        SetTimer(PreCacheClipboardImage, -200)
}

PreCacheClipboardImage() {
    if HasClipboardImageOnly()
        GetOrSaveClipboardImagePath()
}

HasClipboardImageOnly() {
    global PNG_CLIP_FMT
    if DllCall("IsClipboardFormatAvailable", "uint", 13)
        return false
    if DllCall("IsClipboardFormatAvailable", "uint", 15)
        return false
    hasPng := PNG_CLIP_FMT && DllCall("IsClipboardFormatAvailable", "uint", PNG_CLIP_FMT)
    hasBmp := DllCall("IsClipboardFormatAvailable", "uint", 2)
    return (hasPng || hasBmp)
}

ShouldPasteImagePath() {
    if !HasClipboardImageOnly()
        return false
    if WinActive("ahk_class #32770")
        return true
    try {
        ctrl := ControlGetFocus("A")
        if ctrl {
            cls := ControlGetClassNN(ctrl)
            if RegExMatch(cls, "^Edit\d+$")
                return true
        }
    }
    return false
}

PasteClipboardImagePath() {
    path := GetOrSaveClipboardImagePath()
    if (path = "") {
        SendInput("^v")
        return
    }

    try {
        ctrl := ControlGetFocus("A")
        if ctrl {
            cls := ControlGetClassNN(ctrl)
            if RegExMatch(cls, "^Edit\d+$") {
                EditPaste(path, cls, "A")
                return
            }
        }
    }

    if WinActive("ahk_class #32770") {
        try {
            ControlFocus("Edit1", "A")
            ControlSetText("", "Edit1", "A")
            EditPaste(path, "Edit1", "A")
            return
        }
    }

    SendText(path)
}

GetOrSaveClipboardImagePath() {
    global lastClipSeq, lastClipImagePath
    seq := DllCall("GetClipboardSequenceNumber", "uint")
    if (seq != 0 && seq = lastClipSeq && lastClipImagePath != "" && FileExist(lastClipImagePath))
        return lastClipImagePath

    path := SaveClipboardImageToTemp()
    if (path != "") {
        lastClipSeq := seq
        lastClipImagePath := path
    }
    return path
}

SaveClipboardImageToTemp() {
    global PNG_CLIP_FMT
    hasPng := PNG_CLIP_FMT && DllCall("IsClipboardFormatAvailable", "uint", PNG_CLIP_FMT)
    hasBmp := DllCall("IsClipboardFormatAvailable", "uint", 2)
    if (!hasPng && !hasBmp)
        return ""

    outPath := A_Temp "\snip_" A_Now "_" A_MSec ".png"

    opened := false
    Loop 5 {
        if DllCall("OpenClipboard", "ptr", A_ScriptHwnd) {
            opened := true
            break
        }
        Sleep(30)
    }
    if !opened
        return ""

    if hasPng {
        hData := DllCall("GetClipboardData", "uint", PNG_CLIP_FMT, "ptr")
        if hData {
            pData := DllCall("GlobalLock", "ptr", hData, "ptr")
            sz := DllCall("GlobalSize", "ptr", hData, "uptr")
            if (pData && sz > 0) {
                try {
                    f := FileOpen(outPath, "w")
                    f.RawWrite(pData, sz)
                    f.Close()
                }
                DllCall("GlobalUnlock", "ptr", hData)
                DllCall("CloseClipboard")
                if FileExist(outPath)
                    return outPath
            } else if pData {
                DllCall("GlobalUnlock", "ptr", hData)
            }
        }
    }

    if hasBmp {
        hBm := DllCall("GetClipboardData", "uint", 2, "ptr")
        if hBm {
            DllCall("LoadLibrary", "str", "gdiplus", "ptr")
            tok := 0
            gsi := Buffer(24, 0)
            NumPut("uint", 1, gsi, 0)
            if (DllCall("gdiplus\GdiplusStartup", "ptr*", &tok, "ptr", gsi, "ptr", 0) = 0) {
                pBmp := 0
                if (DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hBm, "ptr", 0, "ptr*", &pBmp) = 0 && pBmp) {
                    clsid := Buffer(16, 0)
                    DllCall("ole32\CLSIDFromString", "wstr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "ptr", clsid)
                    DllCall("gdiplus\GdipSaveImageToFile", "ptr", pBmp, "wstr", outPath, "ptr", clsid, "ptr", 0)
                    DllCall("gdiplus\GdipDisposeImage", "ptr", pBmp)
                }
                DllCall("gdiplus\GdiplusShutdown", "ptr", tok)
            }
        }
    }

    DllCall("CloseClipboard")
    return FileExist(outPath) ? outPath : ""
}

CleanupOldTempSnips() {
    cutoff := DateAdd(A_Now, -24, "Hours")
    Loop Files, A_Temp "\snip_*.png" {
        if (DateDiff(A_LoopFileTimeModified, cutoff, "Seconds") < 0)
            try FileDelete(A_LoopFileFullPath)
    }
}

