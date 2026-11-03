<#
  Envol — lanceur et mise à jour de l'addon Envol pour WoW Forever.

  Sans paramètre : ouvre la fenêtre.
  -Silencieux   : vérifie et installe sans fenêtre (démarrage de Windows), journal dans %LOCALAPPDATA%\Envol\maj.log
#>
param([switch]$Silencieux)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Depot         = 'shoukyperry/envol-wow'
$Ici           = Split-Path -Parent $PSCommandPath
$Assets        = Join-Path $Ici 'assets'
$Dossier       = Join-Path $env:LOCALAPPDATA 'Envol'
$FichierConfig = Join-Path $Dossier 'config.json'
$Journal       = Join-Path $Dossier 'maj.log'
$Demarrage     = Join-Path ([Environment]::GetFolderPath('Startup')) 'Envol - mise à jour.lnk'
$PageJeton     = 'https://github.com/settings/personal-access-tokens/new'
New-Item -ItemType Directory -Force -Path $Dossier | Out-Null

# Toute erreur non prévue : écrite dans erreur.log (à côté du lanceur) et affichée
trap {
    $msg = "{0:yyyy-MM-dd HH:mm:ss}  {1}`r`n{2}`r`n" -f (Get-Date), $_.Exception.ToString(), $_.InvocationInfo.PositionMessage
    try { Add-Content -Path (Join-Path $Ici 'erreur.log') -Value $msg -Encoding UTF8 } catch {}
    if (-not $Silencieux) {
        try {
            Add-Type -AssemblyName PresentationFramework
            [System.Windows.MessageBox]::Show("Envol n'a pas pu démarrer :`r`n`r`n" + $_.Exception.Message, 'Envol', 'OK', 'Error') | Out-Null
        } catch {}
    }
    exit 1
}

function Ecrire-Journal([string]$texte) {
    Add-Content -Path $Journal -Value ('{0:yyyy-MM-dd HH:mm}  {1}' -f (Get-Date), $texte) -Encoding UTF8
}

# ======================================================================= configuration

function Lire-Config {
    $c = @{}
    if (Test-Path $FichierConfig) {
        try {
            $json = Get-Content $FichierConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $json.PSObject.Properties) { $c[$p.Name] = $p.Value }
        } catch {}
    }
    return $c
}

function Ecrire-Config($c) { $c | ConvertTo-Json | Set-Content -Path $FichierConfig -Encoding UTF8 }

function Dossier-AddOns($c) {
    # le lanceur vit dans le dossier du client Forever : Interface\AddOns est juste à côté
    $local = Join-Path (Split-Path -Parent $Ici) 'Interface\AddOns'
    if (Test-Path (Split-Path -Parent $local)) { return $local }
    if ($c.addons) { return $c.addons }
    return $null
}

function Jeton-Clair($c) {
    if (-not $c.jeton) { return $null }
    try {
        $s = $c.jeton | ConvertTo-SecureString
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
    } catch { return $null }
}

function Entetes($jeton) {
    return @{ Authorization = "Bearer $jeton"; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'Envol-lanceur' }
}

# ======================================================================= versions

function Version-Installee($addons) {
    $f = Join-Path $addons 'Envol\Data\Version.lua'
    $r = @{ version = $null; date = $null }
    if (Test-Path $f) {
        $t = Get-Content $f -Raw -Encoding UTF8
        if ($t -match 'version = "([^"]+)"') { $r.version = $Matches[1] }
        if ($t -match 'date = "([^"]+)"') { $r.date = $Matches[1] }
    }
    return $r
}

function Derniere-Version($jeton) {
    $h = Entetes $jeton
    $h.Accept = 'application/vnd.github+json'
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Depot/releases/latest" -Headers $h -TimeoutSec 20
    $asset = $rel.assets | Where-Object { $_.name -eq 'Envol.zip' } | Select-Object -First 1
    return @{ version = ($rel.tag_name -replace '^v', ''); url = $asset.url; taille = $asset.size; date = $rel.published_at }
}

function Message-Erreur($err) {
    $code = $null
    try { $code = $err.Exception.Response.StatusCode.value__ } catch {}
    if ($code -eq 401) { return "Clé GitHub refusée (expirée ?). Cliquez sur « Clé GitHub » pour en saisir une nouvelle." }
    if ($code -eq 403 -or $code -eq 404) { return "Cette clé GitHub n'a pas accès au dépôt $Depot." }
    return "Impossible de joindre GitHub : " + $err.Exception.Message
}

# Lien de téléchargement réel (GitHub redirige vers un serveur de fichiers, sans la clé)
function Lien-Fichier($url, $jeton) {
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.AllowAutoRedirect = $false
    $req.UserAgent = 'Envol-lanceur'
    $req.Accept = 'application/octet-stream'
    $req.Headers.Add('Authorization', "Bearer $jeton")
    $req.Headers.Add('X-GitHub-Api-Version', '2022-11-28')
    $rep = $req.GetResponse()
    try {
        $loc = $rep.Headers['Location']
        if ($loc) { return $loc }
        throw "réponse inattendue de GitHub ($([int]$rep.StatusCode))"
    } finally { $rep.Close() }
}

# Remplace le dossier Envol par celui du zip (l'ancien est gardé en sauvegarde)
function Installer-Zip($zip, $addons) {
    $temp = Join-Path $env:TEMP ('Envol-' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -Path $zip -DestinationPath $temp -Force
        $nouveau = Join-Path $temp 'Envol'
        if (-not (Test-Path (Join-Path $nouveau 'Envol.toc'))) { throw 'archive inattendue (Envol.toc absent)' }
        New-Item -ItemType Directory -Force -Path $addons | Out-Null
        $cible = Join-Path $addons 'Envol'
        $sauvegarde = Join-Path $Dossier 'sauvegarde-Envol'
        if (Test-Path $cible) {
            if (Test-Path $sauvegarde) { Remove-Item -Recurse -Force $sauvegarde }
            Move-Item -Path $cible -Destination $sauvegarde
        }
        try { Move-Item -Path $nouveau -Destination $cible }
        catch {
            if (Test-Path $sauvegarde) { Move-Item -Path $sauvegarde -Destination $cible }
            throw
        }
    } finally { Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue }
}

# ======================================================================= démarrage de Windows

function MAJ-Auto-Active { return (Test-Path $Demarrage) }

function Regler-MAJ-Auto([bool]$actif) {
    if ($actif) {
        $sh = New-Object -ComObject WScript.Shell
        $lnk = $sh.CreateShortcut($Demarrage)
        $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $lnk.Arguments = '"' + (Join-Path $Ici 'Lancer Envol.vbs') + '" /silencieux'
        $lnk.WorkingDirectory = $Ici
        $lnk.IconLocation = (Join-Path $Assets 'Envol.ico') + ',0'
        $lnk.Description = "Vérifie les mises à jour de l'addon Envol"
        $lnk.Save()
    } elseif (Test-Path $Demarrage) {
        Remove-Item $Demarrage -Force
    }
}

# ======================================================================= mode silencieux

if ($Silencieux) {
    try {
        Start-Sleep -Seconds 60   # laisser le réseau démarrer
        $c = Lire-Config
        $addons = Dossier-AddOns $c
        $jeton = Jeton-Clair $c
        if (-not $addons -or -not $jeton) { Ecrire-Journal 'Configuration incomplète : ouvrez Envol une fois.'; exit 1 }
        $ins = Version-Installee $addons
        $dispo = Derniere-Version $jeton
        if ($ins.version -eq $dispo.version) { Ecrire-Journal "À jour ($($ins.version))."; exit 0 }
        $zip = Join-Path $env:TEMP 'Envol-maj.zip'
        Invoke-WebRequest -Uri (Lien-Fichier $dispo.url $jeton) -OutFile $zip -UseBasicParsing
        Installer-Zip $zip $addons
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Ecrire-Journal "Envol $($dispo.version) installé (avant : $($ins.version))."
        exit 0
    } catch {
        Ecrire-Journal ("Échec : " + $_.Exception.Message)
        exit 1
    }
}

# ======================================================================= fenêtre

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$fontes = ([Uri](Join-Path $Assets '/')).AbsoluteUri

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Envol" Width="900" Height="540" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" UseLayoutRounding="True">
  <Window.Resources>
    <FontFamily x:Key="Titre">${fontes}#Cinzel</FontFamily>
    <LinearGradientBrush x:Key="Or" StartPoint="0,0" EndPoint="0,1">
      <GradientStop Color="#FFF9E39A" Offset="0"/>
      <GradientStop Color="#FFE0B04A" Offset="0.45"/>
      <GradientStop Color="#FF9C6A1E" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="Cadre" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#FFF6D87A" Offset="0"/>
      <GradientStop Color="#FF7A5216" Offset="0.35"/>
      <GradientStop Color="#FFE8C060" Offset="0.6"/>
      <GradientStop Color="#FF5E3E10" Offset="1"/>
    </LinearGradientBrush>

    <Style x:Key="BoutonRouge" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFD970"/>
      <Setter Property="FontFamily" Value="{StaticResource Titre}"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="ombre" CornerRadius="5" Background="#99000000" Margin="0,3,0,-3"/>
              <Border x:Name="fond" CornerRadius="5" BorderBrush="{StaticResource Cadre}" BorderThickness="2">
                <Border.Background>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop x:Name="h" Color="#FFB3261A" Offset="0"/>
                    <GradientStop Color="#FF7A140C" Offset="0.55"/>
                    <GradientStop Color="#FF4A0906" Offset="1"/>
                  </LinearGradientBrush>
                </Border.Background>
                <Grid>
                  <Border CornerRadius="3" Margin="2" Height="12" VerticalAlignment="Top" Background="#22FFFFFF"/>
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="18,0">
                    <ContentPresenter.Effect>
                      <DropShadowEffect ShadowDepth="1" BlurRadius="2" Color="Black" Opacity="0.9"/>
                    </ContentPresenter.Effect>
                  </ContentPresenter>
                </Grid>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="fond" Property="Effect">
                  <Setter.Value><DropShadowEffect ShadowDepth="0" BlurRadius="14" Color="#FFFFC040" Opacity="0.75"/></Setter.Value>
                </Setter>
                <Setter Property="Foreground" Value="#FFFFF3C4"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="fond" Property="RenderTransform">
                  <Setter.Value><TranslateTransform Y="2"/></Setter.Value>
                </Setter>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="fond" Property="Opacity" Value="0.45"/>
                <Setter Property="Foreground" Value="#FFB8A070"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="BoutonSombre" TargetType="Button" BasedOn="{StaticResource BoutonRouge}">
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="fond" CornerRadius="4" BorderBrush="#AA9C7A3C" BorderThickness="1" Background="#CC1A140E" Padding="12,0">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="fond" Property="BorderBrush" Value="#FFF0C860"/>
                <Setter TargetName="fond" Property="Background" Value="#EE2A1F12"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Etiquette" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="{StaticResource Titre}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Foreground" Value="#FFC9AE73"/>
      <Setter Property="Margin" Value="0,5,16,5"/>
    </Style>
    <Style x:Key="Valeur" TargetType="TextBlock">
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="#FFF4EBD6"/>
      <Setter Property="Margin" Value="0,5,0,5"/>
    </Style>
  </Window.Resources>

  <Border CornerRadius="10" BorderBrush="{StaticResource Cadre}" BorderThickness="3" Background="#FF0D0A08">
    <Border.Effect><DropShadowEffect ShadowDepth="0" BlurRadius="18" Opacity="0.8"/></Border.Effect>
    <Grid ClipToBounds="True">
      <Grid.OpacityMask>
        <VisualBrush><VisualBrush.Visual><Border Width="894" Height="534" CornerRadius="7" Background="Black"/></VisualBrush.Visual></VisualBrush>
      </Grid.OpacityMask>

      <Image x:Name="ImgFond" Stretch="UniformToFill"/>
      <Rectangle>
        <Rectangle.Fill>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#F2080604" Offset="0"/>
            <GradientStop Color="#D8080604" Offset="0.42"/>
            <GradientStop Color="#40080604" Offset="0.68"/>
            <GradientStop Color="#00080604" Offset="1"/>
          </LinearGradientBrush>
        </Rectangle.Fill>
      </Rectangle>
      <Rectangle VerticalAlignment="Bottom" Height="120">
        <Rectangle.Fill>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#00000000" Offset="0"/>
            <GradientStop Color="#CC000000" Offset="1"/>
          </LinearGradientBrush>
        </Rectangle.Fill>
      </Rectangle>

      <!-- barre du haut : déplacer / réduire / fermer -->
      <Grid x:Name="BarreTitre" VerticalAlignment="Top" Height="36" Background="#01000000">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,6,10,0">
          <Button x:Name="BtnReduire" Content="—" Style="{StaticResource BoutonSombre}" Width="34" Height="26" Margin="0,0,6,0" ToolTip="Réduire"/>
          <Button x:Name="BtnFermer" Content="✕" Style="{StaticResource BoutonSombre}" Width="34" Height="26" ToolTip="Fermer"/>
        </StackPanel>
      </Grid>

      <!-- contenu -->
      <Grid Margin="38,30,0,26" Width="440" HorizontalAlignment="Left">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <StackPanel Orientation="Horizontal">
          <Image x:Name="ImgEmbleme" Width="104" Height="104">
            <Image.Effect><DropShadowEffect ShadowDepth="0" BlurRadius="22" Color="#FFFFB940" Opacity="0.55"/></Image.Effect>
          </Image>
          <StackPanel VerticalAlignment="Center" Margin="16,0,0,0">
            <TextBlock Text="ENVOL" FontFamily="{StaticResource Titre}" FontWeight="Bold" FontSize="54" Foreground="{StaticResource Or}">
              <TextBlock.Effect><DropShadowEffect ShadowDepth="2" BlurRadius="6" Color="Black" Opacity="1"/></TextBlock.Effect>
            </TextBlock>
            <TextBlock Text="Guide de leveling · WoW Forever" FontFamily="{StaticResource Titre}" FontSize="14"
                       Foreground="#FFD8C08A" Margin="3,-6,0,0"/>
          </StackPanel>
        </StackPanel>

        <!-- ornement -->
        <Grid Grid.Row="1" Margin="0,18,0,14" Height="12">
          <Rectangle Height="1" VerticalAlignment="Center">
            <Rectangle.Fill>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                <GradientStop Color="#00C9A050" Offset="0"/>
                <GradientStop Color="#FFE8C060" Offset="0.5"/>
                <GradientStop Color="#00C9A050" Offset="1"/>
              </LinearGradientBrush>
            </Rectangle.Fill>
          </Rectangle>
          <Rectangle Width="9" Height="9" Fill="{StaticResource Or}" RenderTransformOrigin="0.5,0.5">
            <Rectangle.RenderTransform><RotateTransform Angle="45"/></Rectangle.RenderTransform>
          </Rectangle>
        </Grid>

        <!-- panneau d'informations -->
        <Border Grid.Row="2" CornerRadius="6" BorderBrush="#996E5426" BorderThickness="1" Background="#B8120E0A" Padding="20,16">
          <StackPanel>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
              <TextBlock Text="Version installée" Style="{StaticResource Etiquette}"/>
              <TextBlock x:Name="TxtInstallee" Grid.Column="1" Text="…" Style="{StaticResource Valeur}"/>
              <TextBlock Grid.Row="1" Text="Dernière version" Style="{StaticResource Etiquette}"/>
              <TextBlock x:Name="TxtDispo" Grid.Row="1" Grid.Column="1" Text="…" Style="{StaticResource Valeur}"/>
              <TextBlock Grid.Row="2" Text="Routes du" Style="{StaticResource Etiquette}"/>
              <TextBlock x:Name="TxtDate" Grid.Row="2" Grid.Column="1" Text="…" Style="{StaticResource Valeur}"/>
            </Grid>

            <TextBlock x:Name="TxtStatut" Margin="0,12,0,8" FontSize="13" TextWrapping="Wrap" Foreground="#FFF0D890" Text="Vérification…"/>

            <Grid Height="16">
              <Border CornerRadius="8" Background="#FF0A0806" BorderBrush="#FF5E4520" BorderThickness="1"/>
              <ProgressBar x:Name="Barre" Minimum="0" Maximum="100" Value="0" Margin="2" BorderThickness="0" Background="Transparent">
                <ProgressBar.Foreground>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop Color="#FFFFE38A" Offset="0"/>
                    <GradientStop Color="#FFE89A26" Offset="0.6"/>
                    <GradientStop Color="#FFA85A10" Offset="1"/>
                  </LinearGradientBrush>
                </ProgressBar.Foreground>
              </ProgressBar>
            </Grid>
          </StackPanel>
        </Border>

        <!-- actions -->
        <StackPanel Grid.Row="3" Margin="0,18,0,0" VerticalAlignment="Bottom">
          <StackPanel Orientation="Horizontal">
            <Button x:Name="BtnMaj" Content="Mettre à jour" Style="{StaticResource BoutonRouge}" Width="210"/>
            <Button x:Name="BtnVerifier" Content="Vérifier" Style="{StaticResource BoutonSombre}" Height="40" Margin="12,0,0,0"/>
            <Button x:Name="BtnCle" Content="Clé GitHub" Style="{StaticResource BoutonSombre}" Height="40" Margin="8,0,0,0"/>
          </StackPanel>
          <CheckBox x:Name="ChkAuto" Margin="0,14,0,0" Foreground="#FFD8C9A6" FontSize="12" Cursor="Hand"
                    Content="Mettre à jour automatiquement au démarrage de Windows"/>
        </StackPanel>
      </Grid>

      <TextBlock HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,16,10" FontSize="10"
                 Foreground="#99E8DCC0" Text="Routes RestedXP &amp; Polestar · images générées par IA · police Cinzel (OFL)"/>

      <!-- écran de saisie de la clé GitHub -->
      <Grid x:Name="PanneauCle" Visibility="Collapsed" Background="#E6080604">
        <Border Width="560" VerticalAlignment="Center" CornerRadius="8" BorderBrush="{StaticResource Cadre}" BorderThickness="2"
                Background="#FF15100B" Padding="28,22">
          <StackPanel>
            <TextBlock Text="Clé d'accès GitHub" FontFamily="{StaticResource Titre}" FontWeight="Bold" FontSize="24" Foreground="{StaticResource Or}"/>
            <TextBlock TextWrapping="Wrap" Foreground="#FFE8DCC0" FontSize="13" Margin="0,10,0,0" LineHeight="20">
              Envol se télécharge depuis votre dépôt privé. Il faut une clé en <Bold>lecture seule</Bold>, à créer une fois :
            </TextBlock>
            <TextBlock TextWrapping="Wrap" Foreground="#FFD8C9A6" FontSize="12.5" Margin="8,8,0,0" LineHeight="20">
              1. Cliquez sur « Ouvrir GitHub » ci-dessous.<LineBreak/>
              2. Token name : Envol · Expiration : 1 an (ou plus).<LineBreak/>
              3. Repository access : <Bold>Only select repositories</Bold> → envol-wow.<LineBreak/>
              4. Permissions → Repository → <Bold>Contents : Read-only</Bold>.<LineBreak/>
              5. Generate token, copiez la clé et collez-la ici.
            </TextBlock>
            <Button x:Name="BtnOuvrirGithub" Content="Ouvrir GitHub" Style="{StaticResource BoutonSombre}" HorizontalAlignment="Left" Margin="0,14,0,0"/>
            <PasswordBox x:Name="SaisieCle" Margin="0,14,0,0" Height="32" FontSize="13" Padding="8,5"
                         Background="#FF0A0806" Foreground="#FFF4EBD6" BorderBrush="#FF8C6A30" CaretBrush="#FFF0C860"/>
            <TextBlock Foreground="#99D8C9A6" FontSize="11" Margin="0,6,0,0" TextWrapping="Wrap"
                       Text="La clé est chiffrée par votre session Windows et ne sort pas de ce PC (sauf vers GitHub)."/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
              <Button x:Name="BtnAnnulerCle" Content="Annuler" Style="{StaticResource BoutonSombre}" Height="40" Margin="0,0,10,0"/>
              <Button x:Name="BtnEnregistrerCle" Content="Enregistrer" Style="{StaticResource BoutonRouge}" Width="170"/>
            </StackPanel>
          </StackPanel>
        </Border>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

$fenetre = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $n = $_.Attributes['x:Name']; if (-not $n) { $n = $_.Attributes['Name'] }
    if ($n) { $ui[$n.Value] = $fenetre.FindName($n.Value) }
}

function Image-De($chemin) {
    $b = New-Object System.Windows.Media.Imaging.BitmapImage
    $b.BeginInit(); $b.UriSource = New-Object Uri $chemin; $b.CacheOption = 'OnLoad'; $b.EndInit()
    return $b
}
$ui.ImgFond.Source = Image-De (Join-Path $Assets 'fond.jpg')
$ui.ImgEmbleme.Source = Image-De (Join-Path $Assets 'embleme.png')
$fenetre.Icon = Image-De (Join-Path $Assets 'Envol.ico')

# laisse la fenêtre se redessiner pendant les opérations longues
function Rafraichir {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Windows.Threading.DispatcherOperationCallback] { param($f) $f.Continue = $false; $null }, $frame) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Statut([string]$texte, [string]$couleur = '#FFF0D890') {
    $ui.TxtStatut.Text = $texte
    $ui.TxtStatut.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($couleur)
    Rafraichir
}

function Date-FR($d) {
    if ($d -match '^(\d{4})-(\d{2})-(\d{2})') { return "$($Matches[3])/$($Matches[2])/$($Matches[1])" }
    return $d
}

$script:config = Lire-Config
$script:dispo = $null

function Actualiser {
    $ui.BtnMaj.IsEnabled = $false
    $ui.Barre.IsIndeterminate = $false; $ui.Barre.Value = 0
    $addons = Dossier-AddOns $script:config
    if (-not $addons) { Statut "Dossier de WoW Forever introuvable : placez le dossier Envol-Lanceur dans le dossier _forever_." '#FFFF8A70'; return }
    $ins = Version-Installee $addons
    $ui.TxtInstallee.Text = $(if ($ins.version) { $ins.version } else { 'non installé' })
    $ui.TxtDate.Text = $(if ($ins.date) { Date-FR $ins.date } else { '—' })
    $jeton = Jeton-Clair $script:config
    if (-not $jeton) {
        $ui.TxtDispo.Text = '—'
        Statut "Ajoutez votre clé GitHub pour vérifier les mises à jour." '#FFFFC870'
        $ui.PanneauCle.Visibility = 'Visible'
        return
    }
    Statut 'Connexion à GitHub…'
    $ui.Barre.IsIndeterminate = $true; Rafraichir
    try {
        $script:dispo = Derniere-Version $jeton
        $ui.TxtDispo.Text = $script:dispo.version
        if ($ins.version -eq $script:dispo.version) {
            Statut "✔  Envol est à jour. Bon leveling !" '#FF9BE38A'
            $ui.BtnMaj.Content = 'Réinstaller'
        } else {
            Statut "Une nouvelle version est disponible." '#FFFFD970'
            $ui.BtnMaj.Content = 'Mettre à jour'
        }
        $ui.BtnMaj.IsEnabled = $true
    } catch {
        $ui.TxtDispo.Text = '?'
        Statut (Message-Erreur $_) '#FFFF8A70'
    } finally { $ui.Barre.IsIndeterminate = $false }
}

function Mettre-A-Jour {
    $jeton = Jeton-Clair $script:config
    $addons = Dossier-AddOns $script:config
    if (-not ($jeton -and $addons -and $script:dispo)) { return }
    $ui.BtnMaj.IsEnabled = $false; $ui.BtnVerifier.IsEnabled = $false
    $zip = Join-Path $env:TEMP ('Envol-' + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        Statut "Téléchargement d'Envol $($script:dispo.version)…"
        $lien = Lien-Fichier $script:dispo.url $jeton
        # lecture par morceaux : la barre avance et la fenêtre reste vivante
        $req = [System.Net.HttpWebRequest]::Create($lien)
        $req.UserAgent = 'Envol-lanceur'
        $rep = $req.GetResponse()
        $total = [double]$rep.ContentLength
        $src = $rep.GetResponseStream()
        $dst = [System.IO.File]::Create($zip)
        try {
            $buf = New-Object byte[] 65536
            $lu = 0
            while (($n = $src.Read($buf, 0, $buf.Length)) -gt 0) {
                $dst.Write($buf, 0, $n)
                $lu += $n
                if ($total -gt 0) { $ui.Barre.Value = [Math]::Max(3, 80 * $lu / $total) }
                Rafraichir
            }
        } finally { $dst.Close(); $src.Close(); $rep.Close() }
        Statut 'Installation dans les AddOns…'
        $ui.Barre.Value = 90; Rafraichir
        Installer-Zip $zip $addons
        $ui.Barre.Value = 100
        Ecrire-Journal "Envol $($script:dispo.version) installé depuis le lanceur."
        $wow = Get-Process -Name 'Wow*' -ErrorAction SilentlyContinue
        $ins = Version-Installee $addons
        $ui.TxtInstallee.Text = $ins.version
        $ui.TxtDate.Text = Date-FR $ins.date
        if ($wow) { Statut "✔  Installé ! WoW est ouvert : tapez /reload en jeu." '#FF9BE38A' }
        else { Statut "✔  Envol $($ins.version) est installé. Bon leveling !" '#FF9BE38A' }
        $ui.BtnMaj.Content = 'Réinstaller'
    } catch {
        Statut ("Échec : " + $_.Exception.Message) '#FFFF8A70'
        $ui.Barre.Value = 0
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        $ui.BtnMaj.IsEnabled = $true; $ui.BtnVerifier.IsEnabled = $true
    }
}

# ----------------------------------------------------------------- événements

$ui.BarreTitre.Add_MouseLeftButtonDown({ $fenetre.DragMove() })
$fenetre.Add_MouseLeftButtonDown({ if ($_.OriginalSource -is [System.Windows.Controls.Image] -or $_.OriginalSource -is [System.Windows.Shapes.Rectangle]) { $fenetre.DragMove() } })
$ui.BtnFermer.Add_Click({ $fenetre.Close() })
$ui.BtnReduire.Add_Click({ $fenetre.WindowState = 'Minimized' })
$ui.BtnVerifier.Add_Click({ Actualiser })
$ui.BtnMaj.Add_Click({ Mettre-A-Jour })
$ui.BtnCle.Add_Click({ $ui.SaisieCle.Password = ''; $ui.PanneauCle.Visibility = 'Visible' })
$ui.BtnAnnulerCle.Add_Click({ $ui.PanneauCle.Visibility = 'Collapsed' })
$ui.BtnOuvrirGithub.Add_Click({ Start-Process $PageJeton })
$ui.BtnEnregistrerCle.Add_Click({
    $p = $ui.SaisieCle.SecurePassword
    if ($p.Length -lt 20) { $ui.SaisieCle.BorderBrush = [System.Windows.Media.Brushes]::IndianRed; return }
    $script:config.jeton = $p | ConvertFrom-SecureString
    Ecrire-Config $script:config
    $ui.SaisieCle.Password = ''
    $ui.PanneauCle.Visibility = 'Collapsed'
    Actualiser
})

$ui.ChkAuto.IsChecked = MAJ-Auto-Active
$ui.ChkAuto.Add_Click({
    try {
        Regler-MAJ-Auto ([bool]$ui.ChkAuto.IsChecked)
        if ($ui.ChkAuto.IsChecked) { Statut 'Mise à jour automatique activée : vérification à chaque démarrage de Windows.' '#FF9BE38A' }
        else { Statut 'Mise à jour automatique désactivée.' }
    } catch { Statut ("Impossible de régler le démarrage : " + $_.Exception.Message) '#FFFF8A70' }
})

if ($env:ENVOL_CAPTURE) {
    # mode test (GitHub Actions) : capture de la fenêtre en PNG, sans réseau
    $fenetre.Add_ContentRendered({
        $ui.TxtInstallee.Text = '1.1.20261103-925b0c'; $ui.TxtDispo.Text = '1.1.20261104-a1f57b'; $ui.TxtDate.Text = '03/11/2026'
        $ui.Barre.Value = 62
        Statut "Téléchargement d'Envol 1.1.20261104-a1f57b…"
        if ($env:ENVOL_CAPTURE -like '*cle*') { $ui.PanneauCle.Visibility = 'Visible' }
        Rafraichir; Start-Sleep -Milliseconds 300; Rafraichir
        $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap 900, 540, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($fenetre.Content)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [System.IO.File]::Create($env:ENVOL_CAPTURE); $enc.Save($fs); $fs.Close()
        $fenetre.Close()
    })
} else {
    $fenetre.Add_ContentRendered({ Actualiser })
}
[void]$fenetre.ShowDialog()
