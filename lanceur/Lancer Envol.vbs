' Lance Envol sans fenêtre de console. Argument /silencieux : mise à jour en arrière-plan.
Set fso = CreateObject("Scripting.FileSystemObject")
dossier = fso.GetParentFolderName(WScript.ScriptFullName)
args = ""
If WScript.Arguments.Count > 0 Then
  If LCase(WScript.Arguments(0)) = "/silencieux" Then args = " -Silencieux"
End If
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & dossier & "\Envol.ps1""" & args
CreateObject("WScript.Shell").Run cmd, 0, False
