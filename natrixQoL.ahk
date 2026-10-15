#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true
Persistent(true)

global APP_VERSION := "2.4.0"

SetWorkingDir(A_ScriptDir)

if (!A_IsAdmin && !InStr(DllCall("GetCommandLine", "Str"), "/restart")) {
    try {
        Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"', A_ScriptDir)
        ExitApp()
    }
}

InstallKeybdHook(true, true)

global sevenZip := Find7Zip()
global SEVEN_CLI := sevenZip.cli
global SEVEN_GUI := sevenZip.gui
global ARCHIVE_EXT := "zip|rar|7z|tar|gz|tgz|bz2|tbz|tbz2|xz|txz|zst|tzst|iso|cab|arj|lzh|lha|wim|001|z01|r00"
global OVERWRITE_MODE := "-aou"
global PNG_CLIP_FMT := DllCall("RegisterClipboardFormat", "str", "PNG", "uint")
global lastClipSeq := 0
global lastClipImagePath := ""

A_IconTip := "natrixQoL " APP_VERSION " (QuickExtract/Pack | AutoType | SnipPath)"
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
    helpMenu.Add("Ctrl+Shift+Win - Quick Extract / Pack", (*) => "")
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

^+LWin::HandleSelectionAction()
^+RWin::HandleSelectionAction()

#HotIf ShouldPasteImagePath()
$^v::PasteClipboardImagePath()
#HotIf

^+F2::
{
    KeyWait("Ctrl")
    KeyWait("Shift")
    SendText("natrix852@gmail.com")
}

^+F3::
{
    KeyWait("Ctrl")
    KeyWait("Shift")
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
    ShellRun("https://gemini.google.com")
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

HandleSelectionAction() {
    static lastSeen := 0
    now := A_TickCount
    if ((now - lastSeen) <= 800)
        return
    lastSeen := now

    selection := GetExplorerSelection()
    if (selection.Length = 0) {
        NotifyQoL("Nothing Selected", "Focus Explorer or Desktop and select files.")
        return
    }

    archiveJobs := []
    packJobs := []
    for path in selection {
        if IsExtractable(path)
            archiveJobs.Push(path)
        else
            packJobs.Push(path)
    }

    if (archiveJobs.Length > 0) {
        for path in archiveJobs {
            ExtractArchive(path, archiveJobs.Length > 1)
        }
        return
    }

    if (packJobs.Length > 0) {
        PackSelection(packJobs)
        return
    }
}

PackSelection(items) {
    global SEVEN_GUI
    if (items.Length = 0)
        return

    SplitPath(items[1], &firstName, &dir, &firstExt, &firstStem)
    if (dir == "")
        dir := A_Desktop

    if (items.Length = 1) {
        baseArchive := firstStem ".zip"
    } else {
        SplitPath(dir, &parentName)
        baseArchive := (parentName != "" ? parentName : "Archive") ".zip"
    }

    targetPath := dir "\" baseArchive
    if FileExist(targetPath) {
        stem := RegExReplace(baseArchive, "\.zip$", "")
        idx := 1
        while FileExist(dir "\" stem "_" idx ".zip")
            idx++
        targetPath := dir "\" stem "_" idx ".zip"
    }

    cmdArgs := ""
    for path in items {
        cmdArgs .= ' ' . EscapeArg(path)
    }

    SplitPath(targetPath, &targetName)
    cmd := '"' SEVEN_GUI '" a -tzip -- "' targetPath '"' cmdArgs
    NotifyQoL("Packing Started", targetName)
    Run(cmd, dir)
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
            if VerifyPassword(path, candidate, info.isHeaderEncrypted, info.testFile) {
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
    passArg := (password != "") ? (' -p' . EscapeArg(password)) : ' -p""'
    cmd := '"' SEVEN_CLI '" l -slt -ba -sccUTF-8' passArg ' -- "' path '"'

    res := RunWaitStdout(cmd)
    txt := res.output
    exitCode := res.exitCode

    isHeaderEncrypted := (exitCode != 0) || RegExMatch(txt, "i)(Cannot open encrypted archive|Headers Error|Wrong password)")
    if isHeaderEncrypted {
        return {
            needPassword: true,
            isHeaderEncrypted: true,
            testFile: "",
            wrongPassword: (password != ""),
            needsOwnFolder: true,
            roots: Map()
        }
    }

    roots := Map()
    hasEncryptedData := false
    firstEncryptedFile := ""
    currentPath := ""

    for line in StrSplit(txt, "`n", "`r") {
        if (SubStr(line, 1, 7) = "Path = ") {
            currentPath := SubStr(line, 8)
            parts := StrSplit(currentPath, ["\", "/"])
            if (parts.Length > 0 && parts[1] != "")
                roots[parts[1]] := true
        } else if (SubStr(line, 1, 12) = "Encrypted = +") {
            hasEncryptedData := true
            if (firstEncryptedFile == "" && currentPath != "")
                firstEncryptedFile := currentPath
        }
    }

    needsOwnFolder := (roots.Count != 1)

    if (hasEncryptedData && password == "") {
        return {
            needPassword: true,
            isHeaderEncrypted: false,
            testFile: firstEncryptedFile,
            wrongPassword: false,
            needsOwnFolder: needsOwnFolder,
            roots: roots
        }
    }

    return {
        needPassword: false,
        isHeaderEncrypted: false,
        testFile: "",
        wrongPassword: false,
        needsOwnFolder: needsOwnFolder,
        roots: roots
    }
}

VerifyPassword(path, password, isHeaderEncrypted := false, testFile := "") {
    global SEVEN_CLI
    if isHeaderEncrypted {
        cmd := '"' SEVEN_CLI '" l -slt -ba -sccUTF-8 -p' EscapeArg(password) ' -- "' path '"'
        res := RunWaitStdout(cmd)
        if (res.exitCode != 0 || RegExMatch(res.output, "i)(Wrong password|Cannot open encrypted archive|Headers Error)"))
            return false
        return true
    }

    targetArg := (testFile != "") ? (' "' testFile '"') : ' "*"'
    cmd := '"' SEVEN_CLI '" t -p' EscapeArg(password) ' -- "' path '"' targetArg
    res := RunWaitStdout(cmd)
    if (res.exitCode != 0 || RegExMatch(res.output, "i)(Wrong password|Cannot open encrypted archive|Headers Error|Data Error)"))
        return false
    return true
}

RunWaitStdout(cmd, cwd := "") {
    sa := Buffer(24, 0)
    NumPut("uint", 24, sa, 0)
    NumPut("ptr", 0, sa, 8)
    NumPut("int", 1, sa, 16)
    hPipeR := 0, hPipeW := 0
    if !DllCall("CreatePipe", "ptr*", &hPipeR, "ptr*", &hPipeW, "ptr", sa, "uint", 0)
        return { output: "", exitCode: -1 }
    DllCall("SetHandleInformation", "ptr", hPipeR, "uint", 1, "uint", 0)

    si := Buffer(104, 0)
    NumPut("uint", 104, si, 0)
    NumPut("uint", 0x100, si, 60)
    NumPut("ptr", hPipeW, si, 88)
    NumPut("ptr", hPipeW, si, 96)

    pi := Buffer(24, 0)
    if !DllCall("CreateProcessW", "ptr", 0, "str", cmd, "ptr", 0, "ptr", 0, "int", 1, "uint", 0x08000000, "ptr", 0, "ptr", cwd != "" ? StrPtr(cwd) : 0, "ptr", si, "ptr", pi) {
        DllCall("CloseHandle", "ptr", hPipeW)
        DllCall("CloseHandle", "ptr", hPipeR)
        return { output: "", exitCode: -1 }
    }
    DllCall("CloseHandle", "ptr", hPipeW)

    hProcess := NumGet(pi, 0, "ptr")
    hThread := NumGet(pi, 8, "ptr")
    DllCall("CloseHandle", "ptr", hThread)

    out := ""
    buf := Buffer(4096, 0)
    bytesRead := 0
    while DllCall("ReadFile", "ptr", hPipeR, "ptr", buf, "uint", 4096, "uint*", &bytesRead, "ptr", 0) && bytesRead > 0 {
        out .= StrGet(buf, bytesRead, "UTF-8")
    }

    DllCall("WaitForSingleObject", "ptr", hProcess, "uint", 0xFFFFFFFF)
    exitCode := 0
    DllCall("GetExitCodeProcess", "ptr", hProcess, "uint*", &exitCode)
    DllCall("CloseHandle", "ptr", hProcess)
    DllCall("CloseHandle", "ptr", hPipeR)
    return { output: out, exitCode: exitCode }
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

NotifyQoL(title, text := "") {
    static osdGui := 0, titleCtrl := 0, textCtrl := 0

    if !osdGui {
        osdGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        osdGui.BackColor := "18181b"
        osdGui.MarginX := 16
        osdGui.MarginY := 12
        osdGui.SetFont("s10 bold cffffff", "Segoe UI")
        titleCtrl := osdGui.AddText("w280", "")
        osdGui.SetFont("s9 norm ca1a1aa", "Segoe UI")
        textCtrl := osdGui.AddText("w280 yp+22", "")
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", osdGui.Hwnd, "uint", 33, "int*", 2, "uint", 4)
    }

    SetTimer(Dismiss, 0)
    titleCtrl.Value := title
    textCtrl.Value := text
    textCtrl.Visible := (text != "")

    osdGui.Show("AutoSize NoActivate")
    osdGui.GetPos(, , &w, &h)
    x := A_ScreenWidth - w - 24
    y := A_ScreenHeight - h - 56
    osdGui.Move(x, y)
    SetTimer(Dismiss, -2200)

    Dismiss() {
        if osdGui
            osdGui.Hide()
    }
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
    if !WinActive("ahk_class #32770")
        return false
    try {
        ctrl := ControlGetFocus("A")
        if ctrl {
            cls := ControlGetClassNN(ctrl)
            if RegExMatch(cls, "^Edit\d+$")
                return true
        }
        if ControlGetHwnd("Edit1", "A")
            return true
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

ShellRun(filePath, arguments := "", directory := "", operation := "", show := 1) {
    try {
        static VT_UI4 := 0x13, SWC_DESKTOP := ComValue(VT_UI4, 0x8)
        ComObject("Shell.Application").Windows.Item(SWC_DESKTOP).Document.Application
            .ShellExecute(filePath, arguments, directory, operation, show)
    } catch {
        Run(filePath, directory)
    }
}

