"""Crée le raccourci Envol.lnk (wscript + Lancer Envol.vbs, icône de l'emblème)."""
import sys
import pylnk3

dossier, sortie = sys.argv[1], sys.argv[2]
pylnk3.for_file(r"C:\Windows\System32\wscript.exe", sortie,
                arguments='"' + dossier + r'\Lancer Envol.vbs"',
                description="Envol : mise à jour de l'addon WoW Forever",
                icon_file=dossier + r"\assets\Envol.ico", icon_index=0, work_dir=dossier)
print("raccourci :", sortie)
