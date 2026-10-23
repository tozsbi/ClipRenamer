' Opens the ClipRenamer app without a black console window
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & here & "\ClipRenamer.ps1""", 0, False
