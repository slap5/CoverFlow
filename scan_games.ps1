param([Parameter(Mandatory=$true)][string]$OutputPath)
# Local, read-only discovery. No accounts, passwords, downloads, or registry writes.
$ErrorActionPreference = 'Stop'
$games = [System.Collections.Generic.List[object]]::new()
$notes = [System.Collections.Generic.List[string]]::new()
$seen = @{}
function Add-Game([string]$id, [string]$name, [string]$source, [string]$path, [string]$target = '') {
    if (-not $id -or -not $name -or $seen.ContainsKey($id)) { return }
    $seen[$id] = $true
    $games.Add([pscustomobject]@{id=$id; name=$name; source=$source; install_path=$path; launch_target=$target; cover=''})
}
function Read-Value([string]$text, [string]$key) {
    $m = [regex]::Match($text, '"' + [regex]::Escape($key) + '"\s*"([^"\r\n]*)"', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value.Replace('\\','\') }
    return ''
}
function Read-Registry([string]$path) {
    return Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
}
try {
    # Steam's configured libraries, including secondary disks.
    $roots = [System.Collections.Generic.List[string]]::new()
    $steam = Read-Registry 'HKCU:\Software\Valve\Steam'
    if ($steam -and $steam.SteamPath) { $roots.Add([string]$steam.SteamPath) }
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')) {
        $reg = Read-Registry $key
        if ($reg -and $reg.InstallPath) { $roots.Add([string]$reg.InstallPath) }
    }
    if (${env:ProgramFiles(x86)}) { $roots.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam')) }
    $libraries = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $libraries.Add($root)
        foreach ($relative in @('steamapps\libraryfolders.vdf','config\libraryfolders.vdf')) {
            $vdf = Join-Path $root $relative
            if (-not (Test-Path -LiteralPath $vdf)) { continue }
            $data = [IO.File]::ReadAllText($vdf)
            foreach ($match in [regex]::Matches($data, '"path"\s*"([^"\r\n]+)"', 'IgnoreCase')) {
                $libraries.Add($match.Groups[1].Value.Replace('\\','\'))
            }
        }
    }
    foreach ($library in @($libraries | Select-Object -Unique)) {
        $apps = Join-Path $library 'steamapps'
        foreach ($file in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
            try {
                $text = [IO.File]::ReadAllText($file.FullName)
                $id = Read-Value $text 'appid'
                $name = Read-Value $text 'name'
                $directory = Read-Value $text 'installdir'
                $flagsText = Read-Value $text 'StateFlags'
                $flags = 0
                [void][int]::TryParse($flagsText, [ref]$flags)
                if (-not $directory -or ($flags -band 4) -eq 0) { continue }
                $path = Join-Path (Join-Path $apps 'common') $directory
                if (Test-Path -LiteralPath $path -PathType Container) {
                    Add-Game "steam:$id" $name 'Steam' $path "steam://rungameid/$id"
                }
            } catch { $notes.Add("Steam: skipped an unreadable manifest ($($file.Name)).") }
        }
    }
} catch { $notes.Add('Steam scan was incomplete: ' + $_.Exception.Message) }
try {
    $manifestRoot = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    foreach ($file in @(Get-ChildItem -LiteralPath $manifestRoot -Filter '*.item' -File -ErrorAction SilentlyContinue)) {
        try {
            $item = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
            if ($item.bIsIncompleteInstall -or -not $item.InstallLocation -or -not $item.AppName) { continue }
            if ($item.MainGameAppName -and $item.MainGameAppName -ne $item.AppName) { continue }
            if (-not (Test-Path -LiteralPath $item.InstallLocation -PathType Container)) { continue }
            $epicIdentity = [string]$item.AppName
            if ($item.CatalogNamespace -and $item.CatalogItemId) { $epicIdentity = [string]$item.CatalogNamespace + ':' + [string]$item.CatalogItemId + ':' + [string]$item.AppName }
            $launchUrl = 'com.epicgames.launcher://apps/' + [Uri]::EscapeDataString($epicIdentity) + '?action=launch&silent=true'
            Add-Game ('epic:' + $item.AppName) ([string]$item.DisplayName) 'Epic Games' ([string]$item.InstallLocation) $launchUrl
        } catch { $notes.Add("Epic: skipped an unreadable manifest ($($file.Name)).") }
    }
} catch { $notes.Add('Epic scan was incomplete: ' + $_.Exception.Message) }
try {
    # Current-user package registrations; do not take ownership of WindowsApps.
    $startApps = @{}
    foreach ($entry in @(Get-StartApps -ErrorAction SilentlyContinue)) { $startApps[$entry.AppID] = $entry.Name }
    $packages = @(Get-AppxPackage -ErrorAction Stop | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage })
    foreach ($package in $packages) {
        try {
            $manifest = Get-AppxPackageManifest -Package $package.PackageFullName -ErrorAction Stop
            $raw = $manifest.OuterXml
            $root = [string]$package.InstallLocation
            $config = if ($root) { Join-Path $root 'MicrosoftGame.config' } else { '' }
            # These are evidence of a game, rather than just any Store application.
            $gameEvidence = $raw -match '(?i)XboxLive|XboxTitleId|Microsoft\.GamingServices|Microsoft\.XboxServices|GameList'
            if ($config -and (Test-Path -LiteralPath $config)) { $gameEvidence = $true }
            if (-not $gameEvidence) { continue }
            if ($package.Name -match '(?i)GamingServices|GamingApp|XboxGamingOverlay|XboxIdentityProvider|XboxGameOverlay|XboxSpeechToTextOverlay') { continue }
            foreach ($app in @($manifest.Package.Applications.Application)) {
                if (-not $app.Id) { continue }
                $aumid = [string]$package.PackageFamilyName + '!' + [string]$app.Id
                if (-not $startApps.ContainsKey($aumid)) { continue }
                Add-Game ('xbox:' + $aumid) ([string]$startApps[$aumid]) 'Xbox / Microsoft Store' $root ('shell:AppsFolder\' + $aumid)
            }
        } catch { $notes.Add('Xbox: could not inspect package ' + $package.Name) }
    }
    $notes.Add('Xbox: uses current-user game package registrations; some Game Pass titles may be missed. Browse for a game if needed.')
} catch { $notes.Add('Xbox scan was incomplete: ' + $_.Exception.Message) }
try {
    foreach ($base in @('HKLM:\SOFTWARE\Rockstar Games','HKLM:\SOFTWARE\WOW6432Node\Rockstar Games','HKCU:\SOFTWARE\Rockstar Games')) {
        foreach ($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
            $reg = Read-Registry $key.PSPath
            if ($key.PSChildName -match '(?i)launcher|social club') { continue }
            foreach ($property in @('InstallFolder','InstallFolderSteam','InstallFolderEpic','InstallLocation')) {
                $path = [string]$reg.$property
                if ($path -and (Test-Path -LiteralPath $path -PathType Container)) {
                    # Prefer an already found Steam/Epic entry for the same installation.
                    $normalized = $path.TrimEnd('\','/').Replace('/','\')
                    $existing = @($games | Where-Object { $_.install_path.TrimEnd('\','/').Replace('/','\') -ieq $normalized })
                    if ($existing.Count -eq 0) { Add-Game ('rockstar:' + $normalized.ToLowerInvariant()) $key.PSChildName 'Rockstar Games' $path }
                }
            }
        }
    }
    foreach ($base in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        foreach ($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
            $reg = Read-Registry $key.PSPath
            if ($reg.Publisher -notmatch '(?i)Rockstar' -or $reg.DisplayName -match '(?i)launcher|social club') { continue }
            $path = [string]$reg.InstallLocation
            if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Container)) { continue }
            $normalized = $path.TrimEnd('\','/').Replace('/','\')
            $existing = @($games | Where-Object { $_.install_path.TrimEnd('\','/').Replace('/','\') -ieq $normalized })
            if ($existing.Count -eq 0) { Add-Game ('rockstar:' + $normalized.ToLowerInvariant()) ([string]$reg.DisplayName) 'Rockstar Games' $path }
        }
    }
    $notes.Add('Rockstar: detection depends on local install registry records; custom or older installations may need Browse.')
} catch { $notes.Add('Rockstar scan was incomplete: ' + $_.Exception.Message) }

# These launchers publish local install records. Inspect both registry views and
# current-user installs; keep Steam/Epic entries when the same folder is shared.
function Add-LocalInstall([string]$prefix, [string]$name, [string]$source, [string]$path, [string]$exe = '') {
    if (-not $path) { return }
    $path = [Environment]::ExpandEnvironmentVariables($path.Trim('"'))
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return }
    $normalized = $path.TrimEnd('\','/').Replace('/','\')
    if (@($games | Where-Object { $_.install_path.TrimEnd('\','/').Replace('/','\') -ieq $normalized }).Count) { return }
    if (-not $name) { $name = Split-Path -Leaf $path.TrimEnd('\','/') }
    if ($name -match '(?i)^(EA app|EA Desktop|Origin|Ubisoft Connect|Uplay|GOG Galaxy)$') { return }
    $target = ''
    if ($exe) {
        $exe = $exe.Trim('"')
        if (-not [IO.Path]::IsPathRooted($exe)) { $exe = Join-Path $path $exe }
        if ([IO.Path]::GetExtension($exe) -ieq '.exe' -and (Test-Path -LiteralPath $exe -PathType Leaf)) { $target = $exe }
    }
    Add-Game ($prefix + ':' + $normalized.ToLowerInvariant()) $name $source $path $target
}
foreach ($hive in @('HKLM:\SOFTWARE','HKLM:\SOFTWARE\WOW6432Node','HKCU:\SOFTWARE')) {
    foreach ($provider in @(
        @{Sub='GOG.com\Games'; Prefix='gog'; Source='GOG Galaxy'; Paths=@('path'); Names=@('gameName','DisplayName')},
        @{Sub='Ubisoft\Launcher\Installs'; Prefix='ubisoft'; Source='Ubisoft Connect'; Paths=@('InstallDir'); Names=@('DisplayName','GameName')},
        @{Sub='EA Games'; Prefix='ea'; Source='EA app'; Paths=@('Install Dir','InstallLocation'); Names=@('DisplayName')},
        @{Sub='Electronic Arts\EA Games'; Prefix='ea'; Source='EA app'; Paths=@('Install Dir','InstallLocation'); Names=@('DisplayName')}
    )) {
        try {
            foreach ($key in @(Get-ChildItem -LiteralPath ($hive + '\' + $provider.Sub) -ErrorAction SilentlyContinue)) {
                try {
                    $reg = Read-Registry $key.PSPath
                    $path = ''
                    foreach ($property in $provider.Paths) { if ($reg.$property) { $path = [string]$reg.$property; break } }
                    $name = ''
                    foreach ($property in $provider.Names) { if ($reg.$property) { $name = [string]$reg.$property; break } }
                    if (-not $name -and $provider.Prefix -eq 'ea') { $name = $key.PSChildName }
                    Add-LocalInstall $provider.Prefix $name $provider.Source $path ([string]$reg.exe)
                } catch { $notes.Add($provider.Source + ': skipped an unreadable install record.') }
            }
        } catch { $notes.Add($provider.Source + ': registry scan was incomplete.') }
    }
    # Uninstall entries also cover older Origin/EA installations and named Ubisoft games.
    foreach ($key in @(Get-ChildItem -LiteralPath ($hive + '\Microsoft\Windows\CurrentVersion\Uninstall') -ErrorAction SilentlyContinue)) {
        try {
            $reg = Read-Registry $key.PSPath
            if ($reg.SystemComponent -eq 1 -or $reg.ParentKeyName -or $reg.DisplayName -match '(?i)launcher|redistributable|dedicated server|anti.?cheat|SDK|update|DLC') { continue }
            if ($reg.Publisher -match '(?i)Electronic Arts|^EA Games$') {
                Add-LocalInstall 'ea' ([string]$reg.DisplayName) 'EA app' ([string]$reg.InstallLocation)
            } elseif ($reg.Publisher -match '(?i)Ubisoft') {
                Add-LocalInstall 'ubisoft' ([string]$reg.DisplayName) 'Ubisoft Connect' ([string]$reg.InstallLocation)
            } elseif ($reg.Publisher -match '(?i)GOG\.com') {
                Add-LocalInstall 'gog' ([string]$reg.DisplayName) 'GOG Galaxy' ([string]$reg.InstallLocation)
            }
        } catch { $notes.Add('Skipped an unreadable launcher uninstall record.') }
    }
}
$notes.Add('GOG Galaxy, EA app and Ubisoft Connect: scans local install records, including custom drives. If no launch file is recorded, use Set launch file once. Unregistered games can be added with Browse.')

$result = @{ games=@($games.ToArray() | Sort-Object source,name); notes=@($notes.ToArray()) }
$json = ConvertTo-Json -InputObject $result -Depth 8
$tempPath = $OutputPath + '.tmp'
[IO.File]::WriteAllText($tempPath, $json, [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $tempPath -Destination $OutputPath -Force
