"""Construit Envol de bout en bout : sources à jour -> données -> tests -> dist/Envol.zip.

Variables d'environnement facultatives : ENVOL_RXP, ENVOL_PS (dossiers des sources déjà clonées).
Sans elles, les dépôts sont clonés dans upstream/.
"""
import hashlib, os, subprocess, sys, zipfile, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
BASE_VERSION = "1.1"
SOURCES = {
    "ENVOL_RXP": ("upstream/RXPGuides", "https://github.com/RestedXP/RXPGuides.git"),
    "ENVOL_PS": ("upstream/polestar", "https://github.com/fitzforge/polestar.git"),
}


def run(*cmd, **kw):
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, check=True, **kw)


def git_sha(path):
    return subprocess.run(["git", "-C", path, "rev-parse", "--short=7", "HEAD"], capture_output=True,
                          text=True).stdout.strip() or "inconnu"


env = dict(os.environ)
for var, (path, url) in SOURCES.items():
    if not env.get(var):
        if os.path.isdir(os.path.join(path, ".git")):
            run("git", "-C", path, "pull", "--ff-only", "-q")
        else:
            os.makedirs("upstream", exist_ok=True)
            run("git", "clone", "--depth", "1", "-q", url, path)
        env[var] = path
env.setdefault("ENVOL_WORK", "work")
env.setdefault("ENVOL_ADDON", "addon/Envol")

py = [sys.executable, "-I"]
for step in ("dump_polestar.py", "build_rxp.py", "build_ps.py", "build_lua.py", "build_gear.py", "build_talents.py", "build_lanceur.py"):
    run(*py, os.path.join("tools", step), env=env, stdout=subprocess.DEVNULL if step == "build_rxp.py" else None)

addon = env["ENVOL_ADDON"]
# flèches en relief : 64 angles par couleur, rendus une fois (même résultat à chaque construction)
relief = os.path.join(addon, "Media", "Relief")
os.makedirs(relief, exist_ok=True)
for couleur in ("Arcane", "Givre", "Nature", "Or", "Feu", "Sang", "Ombre"):
    cible = os.path.join(relief, couleur + ".tga")
    if not os.path.exists(cible) or os.path.getmtime(cible) < os.path.getmtime(os.path.join("tools", "fleche3d.py")):
        run(*py, os.path.join("tools", "fleche3d.py"), cible, "--angles", "64", "--taille", "128", "--couleur", couleur,
            "--angles-lua", os.path.join(addon, "Data", "Relief.lua"))
# empreinte de tout le contenu (hors Version.lua) : sert à savoir s'il y a du nouveau
h = hashlib.sha256()
files = []
for d, _, fs in os.walk(addon):
    for f in fs:
        p = os.path.join(d, f)
        if os.path.basename(p) != "Version.lua":
            files.append(p)
for p in sorted(files):
    h.update(p.replace(os.sep, "/").encode())
    h.update(open(p, "rb").read())
digest = h.hexdigest()[:10]
today = datetime.date.today()
version = f"{BASE_VERSION}.{today:%Y%m%d}-{digest[:6]}"
with open(os.path.join(addon, "Data", "Version.lua"), "w", encoding="utf-8") as f:
    f.write("-- Généré à la construction. Ne pas modifier.\n")
    f.write(f'EnvolData.build = {{ version = "{version}", date = "{today:%Y-%m-%d}", '
            f'rxp = "{git_sha(env["ENVOL_RXP"])}", ps = "{git_sha(env["ENVOL_PS"])}", hash = "{digest}" }}\n')
# même version dans le .toc
toc = os.path.join(addon, "Envol.toc")
lines = open(toc, encoding="utf-8").read().splitlines()
lines = [f"## Version: {version}" if l.startswith("## Version:") else l for l in lines]
open(toc, "w", encoding="utf-8").write("\n".join(lines) + "\n")

run(*py[:1], os.path.join("tests", "run_tests.py"), env=env)

os.makedirs("dist", exist_ok=True)
zpath = os.path.join("dist", "Envol.zip")
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
    for d, _, fs in os.walk(addon):
        for f in sorted(fs):
            p = os.path.join(d, f)
            z.write(p, os.path.join("Envol", os.path.relpath(p, addon)))
open(os.path.join("dist", "version.txt"), "w").write(version + "\n")
open(os.path.join("dist", "hash.txt"), "w").write(digest + "\n")
print("Envol", version, "->", zpath)
