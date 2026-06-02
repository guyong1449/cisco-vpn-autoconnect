Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "pythonw """ & Replace(WScript.ScriptFullName, WScript.ScriptName, "") & "tools\vpn-gui.py""", 0, False
