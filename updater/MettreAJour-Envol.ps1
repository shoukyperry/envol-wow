<#
  Mettre à jour Envol (addon WoW Forever) depuis votre dépôt GitHub privé.

  Utilisation :
    Double-cliquez sur « Mettre a jour Envol.bat ».
    « Activer la mise a jour automatique.bat » : vérifie à chaque ouverture de session Windows.

  Paramètres :
    -Silencieux      aucune question, aucune pause (mode tâche planifiée), journal dans %LOCALAPPDATA%\Envol\maj.log
    -Forcer          réinstalle même si la version est déjà à jour
    -Installer       crée la tâche planifiée « Envol - mise à jour » (à l'ouverture de session)
    -Desinstaller    supprime cette tâche planifiée
    -Reconfigurer    redemande le dossier AddOns et le jeton GitHub
#>
param(
    [switch]$Silencieux,
    [switch]$Forcer,
    [switch]$Installer,
    [switch]$Desinstaller,
    [switch]$Reconfigurer
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Depot = '__DEPOT__'   # rempli à la création du dépôt, ex. : pseudo/envol-wow
$Dossier = Join-Path $env:LOCALAPPDATA 'Envol'
$FichierConfig = Join-Path $Dossier 'config.json'
$Journal = Join-Path $Dossier 'maj.log'
$NomTache = 'Envol - mise à jour'
New-Item -ItemType Directory -Force -Path $Dossier | Out-Null

function Ecrire($texte, $couleur = 'Gray') {
    $ligne = '{0:yyyy-MM-dd HH:mm}  {1}' -f (Get-Date), $texte
    Add-Content -Path $Journal -Value $ligne -Encoding UTF8
    if (-not $Silencieux) { Write-Host $texte -ForegroundColor $couleur }
}

function Terminer($code) {
    if (-not $Silencieux) { Write-Host ''; Read-Host 'Appuyez sur Entrée pour fermer' | Out-Null }
    exit $code
}

# ---------------------------------------------------------------- tâche planifiée
if ($Installer -or $Desinstaller) {
    if ($Desinstaller) {
        Unregister-ScheduledTask -TaskName $NomTache -Confirm:$false -ErrorAction SilentlyContinue
        Ecrire 'Mise à jour automatique désactivée.' 'Green'
        Terminer 0
    }
    # le script est copié dans %LOCALAPPDATA%\Envol : la tâche marche même si vous déplacez ce dossier
    $script = Join-Path $Dossier 'MettreAJour-Envol.ps1'
    if ($PSCommandPath -ne $script) { Copy-Item -Path $PSCommandPath -Destination $script -Force }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`" -Silencieux"
    $declencheur = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $declencheur.Delay = 'PT2M'
    $reglages = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName $NomTache -Action $action -Trigger $declencheur -Settings $reglages `
        -Description 'Télécharge la dernière version de l''addon Envol pour WoW Forever.' -Force | Out-Null
    Ecrire "Mise à jour automatique activée : Envol sera vérifié 2 minutes après chaque ouverture de session." 'Green'
    Ecrire "(Pour l'arrêter : « Desactiver la mise a jour automatique.bat ».)"
    Terminer 0
}

# ---------------------------------------------------------------- configuration
$config = @{}
if ((Test-Path $FichierConfig) -and -not $Reconfigurer) {
    $json = Get-Content $FichierConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $json.PSObject.Properties) { $config[$p.Name] = $p.Value }
}

function Trouver-AddOns {
    $racines = @()
    foreach ($cle in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
                     'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
        try {
            $chemin = (Get-ItemProperty -Path $cle -ErrorAction Stop).InstallPath
            if ($chemin) { $racines += (Split-Path ($chemin.TrimEnd('\')) -Parent) }
        } catch {}
    }
    $racines += "${env:ProgramFiles(x86)}\World of Warcraft", "$env:ProgramFiles\World of Warcraft",
                'C:\World of Warcraft', 'D:\World of Warcraft', 'D:\Jeux\World of Warcraft', 'E:\World of Warcraft'
    $clients = @()
    foreach ($r in ($racines | Select-Object -Unique)) {
        if (Test-Path $r) {
            $clients += Get-ChildItem -Path $r -Directory -Filter '_*_' -ErrorAction SilentlyContinue
        }
    }
    $forever = $clients | Where-Object { $_.Name -match 'forever' }
    if ($forever.Count -eq 1) { return Join-Path $forever[0].FullName 'Interface\AddOns' }
    if ($Silencieux) { return $null }
    Write-Host ''
    Write-Host 'Dans quel client WoW faut-il installer Envol ?' -ForegroundColor Cyan
    $i = 1
    foreach ($c in $clients) { Write-Host ("  {0}. {1}" -f $i, $c.FullName); $i++ }
    Write-Host '  Ou collez le chemin complet du dossier Interface\AddOns de WoW Forever.'
    $rep = Read-Host 'Votre choix'
    if ($rep -match '^\d+$' -and [int]$rep -ge 1 -and [int]$rep -le $clients.Count) {
        return Join-Path $clients[[int]$rep - 1].FullName 'Interface\AddOns'
    }
    return $rep.Trim('"', ' ')
}

if (-not $config.addons) {
    $addons = Trouver-AddOns
    if (-not $addons) { Ecrire 'Dossier AddOns introuvable : lancez la mise à jour à la main une première fois.' 'Red'; Terminer 1 }
    New-Item -ItemType Directory -Force -Path $addons | Out-Null
    $config.addons = $addons
}

if (-not $config.jeton) {
    if ($Silencieux) { Ecrire 'Jeton GitHub manquant : lancez la mise à jour à la main une première fois.' 'Red'; Terminer 1 }
    Write-Host ''
    Write-Host "Il faut un jeton GitHub en lecture seule pour télécharger depuis votre dépôt privé $Depot." -ForegroundColor Cyan
    Write-Host '  1. Ouvrez https://github.com/settings/personal-access-tokens/new'
    Write-Host "  2. Repository access : Only select repositories -> $Depot"
    Write-Host '  3. Permissions -> Repository permissions -> Contents : Read-only'
    Write-Host '  4. Generate token, copiez-le et collez-le ici (il ne sera pas affiché).'
    $secure = Read-Host 'Jeton' -AsSecureString
    if ($secure.Length -eq 0) { Ecrire 'Aucun jeton saisi.' 'Red'; Terminer 1 }
    # chiffré avec votre session Windows (DPAPI) : illisible depuis un autre compte ou un autre PC
    $config.jeton = $secure | ConvertFrom-SecureString
}

$config | ConvertTo-Json | Set-Content -Path $FichierConfig -Encoding UTF8

$jetonClair = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR(($config.jeton | ConvertTo-SecureString)))
$entetes = @{
    Authorization          = "Bearer $jetonClair"
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'Envol-mise-a-jour'
}

# ---------------------------------------------------------------- version installée / disponible
$dossierEnvol = Join-Path $config.addons 'Envol'
$installee = $null
$fichierVersion = Join-Path $dossierEnvol 'Data\Version.lua'
if (Test-Path $fichierVersion) {
    $m = Select-String -Path $fichierVersion -Pattern 'version = "([^"]+)"' | Select-Object -First 1
    if ($m) { $installee = $m.Matches[0].Groups[1].Value }
}

try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Depot/releases/latest" `
        -Headers ($entetes + @{ Accept = 'application/vnd.github+json' })
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 401 -or $code -eq 403 -or $code -eq 404) {
        Ecrire "GitHub refuse l'accès (code $code) : jeton expiré ou sans accès à $Depot. Relancez avec « Reconfigurer Envol.bat »." 'Red'
    } else {
        Ecrire "Impossible de joindre GitHub : $($_.Exception.Message)" 'Red'
    }
    Terminer 1
}

$disponible = $release.tag_name -replace '^v', ''
if ($installee -eq $disponible -and -not $Forcer) {
    Ecrire "Envol est déjà à jour (version $installee)." 'Green'
    Terminer 0
}

$asset = $release.assets | Where-Object { $_.name -eq 'Envol.zip' } | Select-Object -First 1
if (-not $asset) { Ecrire 'La dernière version ne contient pas Envol.zip.' 'Red'; Terminer 1 }

# ---------------------------------------------------------------- téléchargement et installation
$temp = Join-Path $env:TEMP ('Envol-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
    $zip = Join-Path $temp 'Envol.zip'
    Ecrire "Téléchargement d'Envol $disponible..."
    Invoke-WebRequest -Uri $asset.url -OutFile $zip -UseBasicParsing `
        -Headers ($entetes + @{ Accept = 'application/octet-stream' })
    Expand-Archive -Path $zip -DestinationPath (Join-Path $temp 'x') -Force
    $nouveau = Join-Path $temp 'x\Envol'
    if (-not (Test-Path (Join-Path $nouveau 'Envol.toc'))) { throw "archive inattendue (Envol.toc absent)" }

    # l'ancienne version est mise de côté (une seule sauvegarde gardée)
    $sauvegarde = Join-Path $Dossier 'sauvegarde-Envol'
    if (Test-Path $dossierEnvol) {
        if (Test-Path $sauvegarde) { Remove-Item -Recurse -Force $sauvegarde }
        Move-Item -Path $dossierEnvol -Destination $sauvegarde
    }
    try {
        Move-Item -Path $nouveau -Destination $dossierEnvol
    } catch {
        if (Test-Path $sauvegarde) { Move-Item -Path $sauvegarde -Destination $dossierEnvol }
        throw
    }
    $avant = if ($installee) { " (avant : $installee)" } else { '' }
    Ecrire "Envol $disponible installé dans $dossierEnvol$avant." 'Green'
    if (Get-Process -Name 'Wow*' -ErrorAction SilentlyContinue) {
        Ecrire 'WoW est ouvert : tapez /reload en jeu pour charger la nouvelle version.' 'Yellow'
    }
} catch {
    Ecrire "Échec de la mise à jour : $($_.Exception.Message)" 'Red'
    Terminer 1
} finally {
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}
Terminer 0
