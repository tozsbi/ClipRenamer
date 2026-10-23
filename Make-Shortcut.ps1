# Creates ClipRenamer shortcuts in the Start menu and on the desktop.
# The shortcut carries the same AppUserModelID as the app window, so a pinned taskbar icon and the open window are one button.
$Root = $PSScriptRoot
$AppId = 'toz.ClipRenamer'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class TozShortcut {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class CShellLink { }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    interface IPropertyStore {
        int GetCount(out uint c);
        int GetAt(uint i, out PropertyKey k);
        int GetValue(ref PropertyKey k, out PropVariant v);
        int SetValue(ref PropertyKey k, ref PropVariant v);
        int Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PropertyKey { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Explicit)]
    public struct PropVariant {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr p;
    }

    public static void SetAppId(string lnkPath, string appId) {
        var link = new CShellLink();
        ((IPersistFile)link).Load(lnkPath, 2);
        var store = (IPropertyStore)link;
        var key = new PropertyKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
        var value = new PropVariant { vt = 31, p = Marshal.StringToCoTaskMemUni(appId) }; // VT_LPWSTR
        store.SetValue(ref key, ref value);
        store.Commit();
        ((IPersistFile)link).Save(lnkPath, true);
        Marshal.FreeCoTaskMem(value.p);
    }
}
'@

$shell = New-Object -ComObject WScript.Shell
$places = @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'ClipRenamer.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'ClipRenamer.lnk')
)
foreach ($lnk in $places) {
    $s = $shell.CreateShortcut($lnk)
    $s.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $s.Arguments = '"' + (Join-Path $Root 'ClipRenamer.vbs') + '"'
    $s.WorkingDirectory = $Root
    $s.IconLocation = (Join-Path $Root 'ClipRenamer.ico') + ',0'
    $s.Description = 'ClipRenamer by toz'
    $s.Save()
    [TozShortcut]::SetAppId($lnk, $AppId)
    Write-Host "Shortcut: $lnk"
}
