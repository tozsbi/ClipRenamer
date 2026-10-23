# ClipRenamer

**An idea and project by toz**

> ⚠️ **Early version (beta).** It works, but it's still at an early stage.

## The idea

OBS saves clips with names like `Replay 2026-09-07 14-57-40.mp4`, and after a while you can't find anything.
ClipRenamer moves your clips to one place (such as iCloud Drive, so they upload to the cloud), and gives you a simple list to name each clip after what happened in it.

The long-term idea is for AI to name the clips by itself. I tried it, but the results weren't good enough yet (especially with voice chat in dialects such as Saudi Arabic), so it's **removed for now**. I hope to bring it back once it works well.

![ClipRenamer](docs/screenshot.png)

## Features

| | |
|---|---|
| 🔁 Auto move | Moves OBS clips to the folder you choose, at logon and every 10 minutes, even when the app is closed |
| ✏️ Rename list | Every clip waiting to be named, with a box to type its new name |
| 📅 Date fallback | A clip you don't name within the time you choose (24 hours by default) gets its date as name, like `2026-10-23 00-20-09` |
| 📁 Named clips apart | Named clips go to their own folder, so the list only shows clips still waiting |
| 🛡️ Safe | Never overwrites a file, and never touches a clip OBS is still recording |
| ▶️ 🗑️ Play and delete | Next to every clip. Deleting goes to the Recycle Bin, or to iCloud's "Recently Deleted" |
| 🌐 Two languages | English or Arabic, switch any time with the 🌐 button |
| 📌 Taskbar | Its own icon, shortcut and taskbar button |

## Getting started

1. Download the project (**Code** → **Download ZIP**) and unzip it anywhere.
2. Right-click **`Make-Shortcut.ps1`** → **Run with PowerShell**. This adds ClipRenamer to the Start menu and the desktop.
3. Open **ClipRenamer**. On the **Move** page, pick your folders, then press the big **Start** button on **Home**.
4. To pin it: right-click its icon on the taskbar → **Pin to taskbar**.

## Requirements

- Windows 10 or 11
- [OBS Studio](https://obsproject.com/)
- No Python or installs needed: it's written in PowerShell, which comes with Windows.

## License

MIT © toz
