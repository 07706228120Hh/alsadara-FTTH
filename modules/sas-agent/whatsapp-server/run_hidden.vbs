' Launch the Aluklaa WhatsApp server with no console window.
' Node lookup order: bundled runtime\node.exe -> node.exe next to script -> node in PATH.
Option Explicit
Dim sh, fso, scriptDir, nodeExe, cmd
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = scriptDir

If fso.FileExists(scriptDir & "\runtime\node.exe") Then
  nodeExe = scriptDir & "\runtime\node.exe"
ElseIf fso.FileExists(scriptDir & "\node.exe") Then
  nodeExe = scriptDir & "\node.exe"
Else
  nodeExe = "node"
End If

cmd = """" & nodeExe & """ """ & scriptDir & "\server.js"""
' 0 = hidden window, False = do not wait.
sh.Run cmd, 0, False
