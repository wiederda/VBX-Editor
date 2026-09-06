#use proc,zip

Dim rootDir = app.ScriptDir()
Dim releaseDir = rootDir & "\build\windows\x64\runner\Release"
Dim outputZip = rootDir & "\vbx-editor-windows.zip"

Print "Baue Windows-Release ..."

Dim buildResult = proc.ExecEx("cmd", 180000, "flutter","build", "windows", "--release")
Dim exitCode = buildResult(3)

If exitCode <> 0 Then
    Print "Build fehlgeschlagen (Exit-Code " & exitCode & "):"
    Print buildResult(2)
    Exit
End If

Print "Build erfolgreich, erstelle ZIP ..."

If file.Exists(outputZip) Then
    file.Delete(outputZip)
End If

Dim ok = zip.Create(outputZip, releaseDir)

If ok Then
    Print "Fertig: " & outputZip
    Print "Inhalt zur Kontrolle:"

    Dim entries = zip.List(outputZip)
    Print "Anzahl Einträge: " & array.Length(entries)

    Dim i
    For i = 0 To array.Length(entries) - 1
        Print entries(i)["Name"] & " (" & entries(i)["Size"] & " bytes)"
    Next
Else
    Print "ZIP-Erstellung fehlgeschlagen."
    Exit
End If