Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "pythonw """ & Replace(WScript.ScriptFullName, WScript.ScriptName, "") & "qrdecode_gui.py""", 0, False
