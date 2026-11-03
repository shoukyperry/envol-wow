' Lance Envol sans fenêtre de console. Argument /silencieux : mise à jour en arrière-plan.
On Error Resume Next
Set fso = CreateObject("Scripting.FileSystemObject")
dossier = fso.GetParentFolderName(WScript.ScriptFullName)
args = ""
If WScript.Arguments.Count > 0 Then
  If LCase(WScript.Arguments(0)) = "/silencieux" Then args = " -Silencieux"
End If
ps = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
cmd = """" & ps & """ -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & dossier & "\Envol.ps1""" & args
CreateObject("WScript.Shell").Run cmd, 0, False
If Err.Number <> 0 Then MsgBox "Envol n'a pas pu lancer PowerShell : " & Err.Description, vbCritical, "Envol"
