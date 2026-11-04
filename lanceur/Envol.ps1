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
        Title="Envol" Width="1080" Height="680" WindowStyle="None" AllowsTransparency="True"
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
    <!-- puces de sélection (race, classe, spé, niveau...) -->
    <Style x:Key="Puce" TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#FFE8DCC0"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,6,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="b" CornerRadius="4" BorderBrush="#AA6E5426" BorderThickness="1" Background="#CC17110B" Padding="10,4">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="#FFF0C860"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="#FFF6D87A"/>
                <Setter TargetName="b" Property="Background">
                  <Setter.Value>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                      <GradientStop Color="#FF9E2216" Offset="0"/><GradientStop Color="#FF5A0D08" Offset="1"/>
                    </LinearGradientBrush>
                  </Setter.Value>
                </Setter>
                <Setter Property="Foreground" Value="#FFFFE38A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ListePuces" TargetType="ListBox">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource Puce}"/>
      <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Disabled"/>
      <Setter Property="ItemsPanel">
        <Setter.Value><ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate></Setter.Value>
      </Setter>
    </Style>

    <!-- lignes de liste (routes, étapes, objets) -->
    <Style x:Key="Ligne" TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#FFE8DCC0"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="b" BorderThickness="2,0,0,0" BorderBrush="Transparent" Background="Transparent" Padding="10,6">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#22F0C860"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="b" Property="Background" Value="#40B3261A"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#FFF0C860"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Liste" TargetType="ListBox">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource Ligne}"/>
      <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Disabled"/>
      <Setter Property="VirtualizingStackPanel.IsVirtualizing" Value="True"/>
      <Setter Property="VirtualizingStackPanel.ScrollUnit" Value="Pixel"/>
    </Style>

    <!-- barre de défilement sobre -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="#AA8C6A30"/></ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- onglets -->
    <Style x:Key="Onglet" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#FFC9AE73"/>
      <Setter Property="FontFamily" Value="{StaticResource Titre}"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="6,0,0,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" CornerRadius="5,5,0,0" BorderBrush="#AA6E5426" BorderThickness="1,1,1,0" Background="#CC120E0A" Padding="18,8">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Foreground" Value="#FFFFE38A"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource Cadre}"/>
                <Setter TargetName="b" Property="Background">
                  <Setter.Value>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                      <GradientStop Color="#FF8E1E14" Offset="0"/><GradientStop Color="#FF3A0806" Offset="1"/>
                    </LinearGradientBrush>
                  </Setter.Value>
                </Setter>
                <Setter Property="Foreground" Value="#FFFFE38A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Panneau" TargetType="Border">
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="BorderBrush" Value="#996E5426"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Background" Value="#E0120E0A"/>
    </Style>
    <Style x:Key="Rubrique" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="{StaticResource Titre}"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="#FFE0B04A"/>
      <Setter Property="Margin" Value="0,0,0,6"/>
    </Style>
  </Window.Resources>

  <Border CornerRadius="10" BorderBrush="{StaticResource Cadre}" BorderThickness="3" Background="#FF0D0A08">
    <Border.Effect><DropShadowEffect ShadowDepth="0" BlurRadius="18" Opacity="0.8"/></Border.Effect>
    <Grid ClipToBounds="True">
      <Grid.OpacityMask>
        <VisualBrush><VisualBrush.Visual><Border Width="1074" Height="674" CornerRadius="7" Background="Black"/></VisualBrush.Visual></VisualBrush>
      </Grid.OpacityMask>

      <Image x:Name="ImgFond" Stretch="UniformToFill"/>
      <Rectangle x:Name="Voile">
        <Rectangle.Fill>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#F2080604" Offset="0"/>
            <GradientStop Color="#D8080604" Offset="0.40"/>
            <GradientStop Color="#40080604" Offset="0.66"/>
            <GradientStop Color="#10080604" Offset="1"/>
          </LinearGradientBrush>
        </Rectangle.Fill>
      </Rectangle>
      <Rectangle VerticalAlignment="Top" Height="150">
        <Rectangle.Fill>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#D0000000" Offset="0"/><GradientStop Color="#00000000" Offset="1"/>
          </LinearGradientBrush>
        </Rectangle.Fill>
      </Rectangle>

      <Grid x:Name="BarreTitre" VerticalAlignment="Top" Height="40" Background="#01000000">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,12,0">
          <Button x:Name="BtnReduire" Content="—" Style="{StaticResource BoutonSombre}" Width="34" Height="26" Margin="0,0,6,0" ToolTip="Réduire"/>
          <Button x:Name="BtnFermer" Content="✕" Style="{StaticResource BoutonSombre}" Width="34" Height="26" ToolTip="Fermer"/>
        </StackPanel>
      </Grid>

      <Grid Margin="32,22,32,30">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- en-tête -->
        <Grid>
          <StackPanel Orientation="Horizontal">
            <Image x:Name="ImgEmbleme" Width="84" Height="84">
              <Image.Effect><DropShadowEffect ShadowDepth="0" BlurRadius="22" Color="#FFFFB940" Opacity="0.55"/></Image.Effect>
            </Image>
            <StackPanel VerticalAlignment="Center" Margin="14,0,0,0">
              <TextBlock Text="ENVOL" FontFamily="{StaticResource Titre}" FontWeight="Bold" FontSize="46" Foreground="{StaticResource Or}">
                <TextBlock.Effect><DropShadowEffect ShadowDepth="2" BlurRadius="6" Color="Black" Opacity="1"/></TextBlock.Effect>
              </TextBlock>
              <TextBlock Text="Guide de leveling · WoW Forever" FontFamily="{StaticResource Titre}" FontSize="13"
                         Foreground="#FFD8C08A" Margin="3,-6,0,0"/>
            </StackPanel>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom">
            <RadioButton x:Name="OngletMaj" Content="Mise à jour" Style="{StaticResource Onglet}" GroupName="o" IsChecked="True"/>
            <RadioButton x:Name="OngletParcours" Content="Parcours" Style="{StaticResource Onglet}" GroupName="o"/>
            <RadioButton x:Name="OngletEquip" Content="Équipement" Style="{StaticResource Onglet}" GroupName="o"/>
          </StackPanel>
        </Grid>

        <!-- ornement -->
        <Grid Grid.Row="1" Margin="0,0,0,14" Height="12">
          <Rectangle Height="1" VerticalAlignment="Center">
            <Rectangle.Fill>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                <GradientStop Color="#00C9A050" Offset="0"/><GradientStop Color="#FFE8C060" Offset="0.5"/><GradientStop Color="#00C9A050" Offset="1"/>
              </LinearGradientBrush>
            </Rectangle.Fill>
          </Rectangle>
          <Rectangle Width="9" Height="9" Fill="{StaticResource Or}" RenderTransformOrigin="0.5,0.5">
            <Rectangle.RenderTransform><RotateTransform Angle="45"/></Rectangle.RenderTransform>
          </Rectangle>
        </Grid>

        <!-- ============ page : mise à jour ============ -->
        <Grid x:Name="PageMaj" Grid.Row="2" Width="460" HorizontalAlignment="Left">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <Border CornerRadius="6" BorderBrush="#996E5426" BorderThickness="1" Background="#B8120E0A" Padding="20,16">
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
                      <GradientStop Color="#FFFFE38A" Offset="0"/><GradientStop Color="#FFE89A26" Offset="0.6"/><GradientStop Color="#FFA85A10" Offset="1"/>
                    </LinearGradientBrush>
                  </ProgressBar.Foreground>
                </ProgressBar>
              </Grid>
            </StackPanel>
          </Border>
          <StackPanel Grid.Row="1" VerticalAlignment="Bottom">
            <StackPanel Orientation="Horizontal">
              <Button x:Name="BtnMaj" Content="Mettre à jour" Style="{StaticResource BoutonRouge}" Width="210"/>
              <Button x:Name="BtnVerifier" Content="Vérifier" Style="{StaticResource BoutonSombre}" Height="40" Margin="12,0,0,0"/>
              <Button x:Name="BtnCle" Content="Clé GitHub" Style="{StaticResource BoutonSombre}" Height="40" Margin="8,0,0,0"/>
            </StackPanel>
            <CheckBox x:Name="ChkAuto" Margin="0,14,0,0" Foreground="#FFD8C9A6" FontSize="12" Cursor="Hand"
                      Content="Mettre à jour automatiquement au démarrage de Windows"/>
          </StackPanel>
        </Grid>

        <!-- ============ page : parcours ============ -->
        <Border x:Name="PageParcours" Grid.Row="2" Style="{StaticResource Panneau}" Padding="18,14" Visibility="Collapsed">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <Grid.ColumnDefinitions><ColumnDefinition Width="340"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <StackPanel Grid.ColumnSpan="3">
              <TextBlock Text="Race" Style="{StaticResource Rubrique}"/>
              <ListBox x:Name="ChoixRace" Style="{StaticResource ListePuces}"/>
              <TextBlock Text="Classe" Style="{StaticResource Rubrique}" Margin="0,4,0,6"/>
              <ListBox x:Name="ChoixClasse" Style="{StaticResource ListePuces}"/>
            </StackPanel>
            <TextBlock Grid.Row="1" x:Name="TxtResumeParcours" Style="{StaticResource Rubrique}" Margin="0,8,0,8"/>
            <TextBlock Grid.Row="1" Grid.Column="2" x:Name="TxtTitreRoute" Style="{StaticResource Rubrique}" Margin="0,8,0,8" TextTrimming="CharacterEllipsis"/>
            <Border Grid.Row="2" Background="#99080604" CornerRadius="4">
              <ListBox x:Name="ListeRoutes" Style="{StaticResource Liste}"/>
            </Border>
            <Border Grid.Row="2" Grid.Column="2" Background="#99080604" CornerRadius="4">
              <ListBox x:Name="ListeEtapes" Style="{StaticResource Liste}"/>
            </Border>
          </Grid>
        </Border>

        <!-- ============ page : équipement ============ -->
        <Border x:Name="PageEquip" Grid.Row="2" Style="{StaticResource Panneau}" Padding="18,14" Visibility="Collapsed">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="20"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="Classe" Style="{StaticResource Rubrique}"/>
                <ListBox x:Name="ChoixClasseEq" Style="{StaticResource ListePuces}"/>
                <TextBlock Text="Spécialisation" Style="{StaticResource Rubrique}" Margin="0,4,0,6"/>
                <ListBox x:Name="ChoixSpe" Style="{StaticResource ListePuces}"/>
              </StackPanel>
              <StackPanel Grid.Column="2" Width="330">
                <TextBlock Text="Faction" Style="{StaticResource Rubrique}"/>
                <ListBox x:Name="ChoixFaction" Style="{StaticResource ListePuces}"/>
                <TextBlock Text="Niveau" Style="{StaticResource Rubrique}" Margin="0,4,0,6"/>
                <ListBox x:Name="ChoixNiveau" Style="{StaticResource ListePuces}"/>
              </StackPanel>
            </Grid>
            <TextBlock Grid.Row="1" x:Name="TxtPriorite" Margin="0,6,0,10" FontSize="13" Foreground="#FFF0D890" TextWrapping="Wrap"/>
            <Border Grid.Row="2" Background="#99080604" CornerRadius="4">
              <ListBox x:Name="ListeObjets" Style="{StaticResource Liste}"/>
            </Border>
          </Grid>
        </Border>
      </Grid>

      <TextBlock HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,16,9" FontSize="10"
                 Foreground="#99E8DCC0" Text="Routes RestedXP &amp; Polestar · objets ForeverLevelingBiS · images générées par IA · police Cinzel (OFL)"/>

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

# ----------------------------------------------------------------- pages Parcours et Équipement

$Pinceau = [System.Windows.Media.BrushConverter]::new()
function Couleur([string]$c) { return $Pinceau.ConvertFromString($c) }
function Prop($o, [string]$k) { $p = $o.PSObject.Properties[$k]; if ($p) { return $p.Value } return $null }
$Titre = $fenetre.FindResource('Titre')

function Dossier-Donnees {
    $a = Dossier-AddOns $script:config
    if (-not $a) { return $null }
    $d = Join-Path $a 'Envol\Lanceur'
    if (Test-Path (Join-Path $d 'index.json')) { return $d }
    return $null
}

function Lire-Json($chemin) { return (Get-Content -Path $chemin -Raw -Encoding UTF8 | ConvertFrom-Json) }

# Conditions des étapes : même règles que l'addon (Core.lua)
function Jeton-Ok([string]$t, $p) {
    if ($t -eq 'Undead') { $t = 'Scourge' }
    if ($t -match '^\d+$') { return ($p.niveau -ge [int]$t) }
    return ($t.ToUpper() -eq $p.classe -or $t -eq $p.race -or $t -eq $p.faction -or $t.ToUpper() -eq 'FOREVER')
}
function Applique($c, $p) {
    if ($null -eq $c) { return $true }
    if ($c -is [string]) {
        foreach ($alt in $c.Split('/')) {
            $ents = [regex]::Matches($alt, '!?\w+')
            if ($ents.Count -eq 0) { continue }
            $ok = $true
            foreach ($e in $ents) {
                $v = $e.Value; $neg = $v.StartsWith('!')
                if ((Jeton-Ok $v.TrimStart('!') $p) -eq $neg) { $ok = $false; break }
            }
            if ($ok) { return $true }
        }
        return $false
    }
    $cl = Prop $c 'cl'; $ra = Prop $c 'ra'; $fa = Prop $c 'fa'
    if ($cl -and ($cl -notcontains $p.classe)) { return $false }
    if ($ra -and ($ra -notcontains $p.race) -and -not ($p.race -eq 'Scourge' -and $ra -contains 'Undead')) { return $false }
    if ($fa -and ($fa -notcontains $p.faction)) { return $false }
    return $true
}

function Ajouter-Puce($liste, [string]$texte, $tag) {
    $li = New-Object System.Windows.Controls.ListBoxItem
    $li.Content = $texte; $li.Tag = $tag
    [void]$liste.Items.Add($li)
    return $li
}
function Choisir($liste, $tag) {
    foreach ($li in $liste.Items) { if ($li.Tag -eq $tag) { $liste.SelectedItem = $li; return $true } }
    if ($liste.Items.Count -gt 0 -and -not $liste.SelectedItem) { $liste.SelectedIndex = 0 }
    return $false
}
function Tag-De($liste) { if ($liste.SelectedItem) { return $liste.SelectedItem.Tag } return $null }

function Texte($t, [double]$taille = 13, [string]$couleur = '#FFE8DCC0') {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $t; $tb.FontSize = $taille; $tb.Foreground = Couleur $couleur; $tb.TextWrapping = 'Wrap'
    return $tb
}

$script:index = $null
$script:cacheRoutes = @{}
$script:equip = $null
$script:pret = $false

$Puces = @{
    accepter = @('!', '#FFFFE38A'); rendre = @('?', '#FFFFC73A'); objectif = @('•', '#FFFF8A6A'); objet = @('•', '#FF6CCBFF')
    niveau = @('▲', '#FFC59BFF'); sort = @('✦', '#FFFFA8F0'); vol = @('➤', '#FF7FE0C0'); foyer = @('⌂', '#FF7FE0C0')
    marchand = @('$', '#FFD0D0D0'); maître = @('✦', '#FFFFA8F0'); mort = @('✝', '#FFB0B0B0'); abandon = @('✕', '#FFB0B0B0')
    info = @('·', '#FF9AA4AD')
}

function Init-Parcours {
    $d = Dossier-Donnees
    if (-not $d) { $ui.TxtResumeParcours.Text = "Données absentes : mettez à jour Envol depuis l'onglet « Mise à jour »."; return $false }
    if (-not $script:index) { $script:index = Lire-Json (Join-Path $d 'index.json') }
    if ($ui.ChoixRace.Items.Count -eq 0) {
        foreach ($r in $script:index.races) { [void](Ajouter-Puce $ui.ChoixRace $r.nom $r.cle) }
        foreach ($c in $script:index.classes) { [void](Ajouter-Puce $ui.ChoixClasse $c.nom $c.cle) }
        [void](Choisir $ui.ChoixRace $script:config.race)
        [void](Choisir $ui.ChoixClasse $script:config.classe)
    }
    return $true
}

function Afficher-Parcours {
    if (-not $script:index) { return }
    $race = Tag-De $ui.ChoixRace; $classe = Tag-De $ui.ChoixClasse
    if (-not ($race -and $classe)) { return }
    $script:config.race = $race; $script:config.classe = $classe
    $liste = Prop $script:index.parcours "$race|$classe"
    $routes = @{}; foreach ($r in $script:index.routes) { $routes[[int]$r.n] = $r }
    $ui.ListeRoutes.Items.Clear()
    foreach ($n in $liste) {
        $r = $routes[[int]$n]
        $sp = New-Object System.Windows.Controls.StackPanel
        $t = Texte $r.nom 13 '#FFF4EBD6'; $t.FontWeight = 'SemiBold'; [void]$sp.Children.Add($t)
        [void]$sp.Children.Add((Texte ("Niveaux {0} à {1} · {2}" -f $r.min, $r.max, $r.src) 11 '#FFB8A57A'))
        $li = New-Object System.Windows.Controls.ListBoxItem
        $li.Content = $sp; $li.Tag = $r
        [void]$ui.ListeRoutes.Items.Add($li)
    }
    $ui.TxtResumeParcours.Text = "Votre parcours : $(@($liste).Count) routes, niveau 1 → 60"
    if ($ui.ListeRoutes.Items.Count -gt 0) { $ui.ListeRoutes.SelectedIndex = 0 }
}

function Afficher-Etapes {
    $li = $ui.ListeRoutes.SelectedItem
    if (-not $li) { return }
    $r = $li.Tag
    $d = Dossier-Donnees
    if (-not $script:cacheRoutes.ContainsKey([int]$r.n)) {
        $script:cacheRoutes[[int]$r.n] = Lire-Json (Join-Path $d "routes\$($r.n).json")
    }
    $etapes = $script:cacheRoutes[[int]$r.n]
    $race, $faction = (Tag-De $ui.ChoixRace).Split('|')
    $p = @{ race = $race; faction = $faction; classe = (Tag-De $ui.ChoixClasse); niveau = [int]$r.max }
    $ui.ListeEtapes.Items.Clear()
    $num = 0
    foreach ($e in $etapes) {
        if (-not (Applique (Prop $e 'c') $p)) { continue }
        $lignes = @($e.l | Where-Object { Applique (Prop $_ 'c') $p })
        if ($lignes.Count -eq 0) { continue }
        $num++
        $sp = New-Object System.Windows.Controls.StackPanel
        $tete = New-Object System.Windows.Controls.TextBlock
        $tete.FontFamily = $Titre; $tete.FontSize = 12; $tete.Foreground = Couleur '#FFE0B04A'; $tete.FontWeight = 'Bold'
        $h = Prop $e 'h'
        $tete.Text = "$num." + $(if ($h) { "  $h" } else { '' }) + $(if (Prop $e 'chemin') { '   (en chemin)' } else { '' })
        [void]$sp.Children.Add($tete)
        foreach ($l in $lignes) {
            $pu = $Puces[[string]$l.k]; if (-not $pu) { $pu = $Puces.info }
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.TextWrapping = 'Wrap'; $tb.FontSize = 12.5; $tb.Margin = '4,2,0,0'
            $b = New-Object System.Windows.Documents.Run ($pu[0] + '  '); $b.Foreground = Couleur $pu[1]; $b.FontWeight = 'Bold'
            $x = New-Object System.Windows.Documents.Run $l.x
            $x.Foreground = Couleur $(if ($l.k -eq 'info') { '#FFB9B0A0' } else { '#FFE8DCC0' })
            [void]$tb.Inlines.Add($b); [void]$tb.Inlines.Add($x)
            [void]$sp.Children.Add($tb)
        }
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = $sp
        [void]$ui.ListeEtapes.Items.Add($item)
    }
    $ui.TxtTitreRoute.Text = "$($r.nom) — $num étapes pour votre personnage"
    if ($ui.ListeEtapes.Items.Count -gt 0) { $ui.ListeEtapes.ScrollIntoView($ui.ListeEtapes.Items[0]) }
}

function Init-Equipement {
    $d = Dossier-Donnees
    if (-not $d) { $ui.TxtPriorite.Text = "Données absentes : mettez à jour Envol depuis l'onglet « Mise à jour »."; return $false }
    if (-not $script:index) { $script:index = Lire-Json (Join-Path $d 'index.json') }
    if (-not $script:equip) {
        $ui.TxtPriorite.Text = 'Chargement des objets…'; Rafraichir
        $script:equip = Lire-Json (Join-Path $d 'equipement.json')
    }
    if ($ui.ChoixClasseEq.Items.Count -eq 0) {
        foreach ($c in $script:index.classes) { [void](Ajouter-Puce $ui.ChoixClasseEq $c.nom $c.cle) }
        foreach ($f in 'Alliance', 'Horde') { [void](Ajouter-Puce $ui.ChoixFaction $f $f) }
        foreach ($n in $script:equip.niveaux) { [void](Ajouter-Puce $ui.ChoixNiveau "$n" ([int]$n)) }
        $fac = $script:config.factionEq
        if (-not $fac -and $script:config.race) { $fac = $script:config.race.Split('|')[1] }
        [void](Choisir $ui.ChoixFaction $fac)
        $niv = $script:config.niveau; if (-not $niv) { $niv = 20 }
        [void](Choisir $ui.ChoixNiveau ([int]$niv))
        [void](Choisir $ui.ChoixClasseEq $(if ($script:config.classeEq) { $script:config.classeEq } else { $script:config.classe }))
    }
    return $true
}

function Remplir-Specs {
    $cl = Tag-De $ui.ChoixClasseEq
    if (-not ($cl -and $script:equip)) { return }
    $script:pret = $false
    $ui.ChoixSpe.Items.Clear()
    $defaut = 0; $i = 0
    foreach ($s in (Prop $script:equip.specs $cl)) {
        [void](Ajouter-Puce $ui.ChoixSpe $s.nom $s.cle)
        if ($s.defaut) { $defaut = $i }
        $i++
    }
    $script:pret = $true
    $ok = $false
    foreach ($li in $ui.ChoixSpe.Items) { if ($li.Tag -eq $script:config.spe) { $ui.ChoixSpe.SelectedItem = $li; $ok = $true } }
    if (-not $ok) { $ui.ChoixSpe.SelectedIndex = $defaut }
}

function Afficher-Equipement {
    if (-not ($script:equip -and $script:pret)) { return }
    $cl = Tag-De $ui.ChoixClasseEq; $sp = Tag-De $ui.ChoixSpe; $fac = Tag-De $ui.ChoixFaction; $niv = Tag-De $ui.ChoixNiveau
    if (-not ($cl -and $sp -and $fac -and $niv)) { return }
    $script:config.classeEq = $cl; $script:config.spe = $sp; $script:config.factionEq = $fac; $script:config.niveau = $niv
    $prio = Prop $script:equip.priorites "$cl|$sp|$niv"
    $nomSpe = $ui.ChoixSpe.SelectedItem.Content
    $ui.TxtPriorite.Text = "Priorité des statistiques ($nomSpe, niveau $niv) :  " + (@($prio) -join '  ›  ')
    $cls = Prop $script:equip.classements "$cl|$sp|$niv|$fac"
    $ui.ListeObjets.Items.Clear()
    foreach ($empl in $script:equip.emplacements) {
        $liste = Prop $cls $empl
        if (-not $liste) { continue }
        $o = Prop $script:equip.objets ([string]$liste[0][0])
        $g = New-Object System.Windows.Controls.Grid
        foreach ($w in 150, 0, 360) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = $(if ($w -eq 0) { New-Object System.Windows.GridLength 1, 'Star' } else { New-Object System.Windows.GridLength $w })
            [void]$g.ColumnDefinitions.Add($cd)
        }
        $te = Texte $empl 12.5 '#FFE0B04A'; $te.FontFamily = $Titre; $te.FontWeight = 'Bold'
        [void]$g.Children.Add($te)
        $mil = New-Object System.Windows.Controls.StackPanel
        $nom = Texte $o.nom 14 $o.c; $nom.FontWeight = 'SemiBold'
        [void]$mil.Children.Add($nom)
        if ($o.stats) { [void]$mil.Children.Add((Texte $o.stats 11 '#FFB9B0A0')) }
        $autres = @()
        for ($i = 1; $i -lt $liste.Count; $i++) { $autres += (Prop $script:equip.objets ([string]$liste[$i][0])).nom }
        if ($autres.Count) { [void]$mil.Children.Add((Texte ("Autres choix : " + ($autres -join ' · ')) 11 '#FF8C8270')) }
        [System.Windows.Controls.Grid]::SetColumn($mil, 1)
        [void]$g.Children.Add($mil)
        $droite = New-Object System.Windows.Controls.StackPanel
        $droite.Margin = '12,0,0,0'
        [void]$droite.Children.Add((Texte ("Dès le niveau " + $o.niv) 11 '#FFC9AE73'))
        foreach ($s in $o.src) { [void]$droite.Children.Add((Texte $s 12 '#FFE8DCC0')) }
        [System.Windows.Controls.Grid]::SetColumn($droite, 2)
        [void]$g.Children.Add($droite)
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = $g
        [void]$ui.ListeObjets.Items.Add($item)
    }
    if ($ui.ListeObjets.Items.Count -eq 0) { $ui.TxtPriorite.Text += "`r`nAucun objet trouvé pour ce choix." }
}

function Montrer-Page([string]$page) {
    $ui.PageMaj.Visibility = $(if ($page -eq 'maj') { 'Visible' } else { 'Collapsed' })
    $ui.PageParcours.Visibility = $(if ($page -eq 'parcours') { 'Visible' } else { 'Collapsed' })
    $ui.PageEquip.Visibility = $(if ($page -eq 'equip') { 'Visible' } else { 'Collapsed' })
    try {
        if ($page -eq 'parcours' -and (Init-Parcours) -and $ui.ListeRoutes.Items.Count -eq 0) { Afficher-Parcours }
        if ($page -eq 'equip' -and (Init-Equipement) -and $ui.ChoixSpe.Items.Count -eq 0) { Remplir-Specs }
    } catch {
        Ecrire-Journal ("Page $page : " + $_.Exception.Message)
        try { Add-Content -Path (Join-Path $Ici 'erreur.log') -Value ("{0:yyyy-MM-dd HH:mm:ss}  page {1} : {2}" -f (Get-Date), $page, $_.Exception.ToString()) -Encoding UTF8 } catch {}
    }
}

$ui.OngletMaj.Add_Checked({ Montrer-Page 'maj' })
$ui.OngletParcours.Add_Checked({ Montrer-Page 'parcours' })
$ui.OngletEquip.Add_Checked({ Montrer-Page 'equip' })
$ui.ChoixRace.Add_SelectionChanged({ if ($ui.ChoixClasse.SelectedItem) { Afficher-Parcours } })
$ui.ChoixClasse.Add_SelectionChanged({ if ($ui.ChoixRace.SelectedItem) { Afficher-Parcours } })
$ui.ListeRoutes.Add_SelectionChanged({ Afficher-Etapes })
$ui.ChoixClasseEq.Add_SelectionChanged({ Remplir-Specs })
$ui.ChoixSpe.Add_SelectionChanged({ Afficher-Equipement })
$ui.ChoixFaction.Add_SelectionChanged({ Afficher-Equipement })
$ui.ChoixNiveau.Add_SelectionChanged({ Afficher-Equipement })
$fenetre.Add_Closing({ try { Ecrire-Config $script:config } catch {} })

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

# Raccourci du bureau : (re)créé par Windows lui-même à chaque ouverture
try {
    $bureau = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Envol.lnk'
    $vbs = Join-Path $Ici 'Lancer Envol.vbs'
    $sh = New-Object -ComObject WScript.Shell
    # toujours réécrit par Windows : un raccourci fabriqué ailleurs peut être illisible
    if ($true) {
        $lnk = $sh.CreateShortcut($bureau)
        $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $lnk.Arguments = '"' + $vbs + '"'
        $lnk.WorkingDirectory = $Ici
        $lnk.IconLocation = (Join-Path $Assets 'Envol.ico') + ',0'
        $lnk.Description = "Envol : mise à jour de l'addon WoW Forever"
        $lnk.Save()
    }
} catch {}

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
        if ($env:ENVOL_CAPTURE -like '*parcours*') {
            $script:config.race = 'Tauren|Horde'; $script:config.classe = 'WARRIOR'
            $ui.OngletParcours.IsChecked = $true; Rafraichir
            $ui.ListeRoutes.SelectedIndex = 2; Rafraichir
        }
        if ($env:ENVOL_CAPTURE -like '*equipement*') {
            $script:config.classe = 'WARRIOR'; $script:config.spe = 'arms'; $script:config.niveau = 30; $script:config.factionEq = 'Horde'
            $ui.OngletEquip.IsChecked = $true; Rafraichir
        }
        Rafraichir; Start-Sleep -Milliseconds 300; Rafraichir
        $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap 1080, 680, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
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
