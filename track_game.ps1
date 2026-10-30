param([Parameter(Mandatory=$true)][string]$RequestPath,[Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference = 'Stop'
# No injection, game modification, accounts, network calls or elevated access.
function Normalize-Path([string]$value) {
 if (-not $value) { return '' }
 return [IO.Path]::GetFullPath($value).TrimEnd('\','/').ToLowerInvariant()
}
function Test-GameProcess($process,[string]$exact,[string]$root) {
 if (-not $process.ExecutablePath) { return $false }
 $name = [IO.Path]::GetFileNameWithoutExtension((([string]$process.ExecutablePath) -split '[\\/]')[-1])
 if ($name -match '(?i)^(steam|steamwebhelper|epicgameslauncher|epicwebhelper|galaxyclient|galaxyclientservice|eadesktop|eabackgroundservice|origin|ubisoftconnect|upc|uplay|launcher|launcherpatcher|socialclubhelper|rockstarservice|gamelauncher|crashreporter|crashreportclient|werfault|unins.*|uninstall.*|setup|vc_redist.*|dxsetup|easyanticheat.*|beservice.*|battleye.*)$') { return $false }
 $path = Normalize-Path ([string]$process.ExecutablePath)
 if ($exact) { return $path -eq $exact }
 return $root -and $path.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)
}
# Dot-source the pure matching functions in tests without starting the monitor.
if ($MyInvocation.InvocationName -eq '.') { return }
$request = $null
try {
 $request = [IO.File]::ReadAllText($RequestPath) | ConvertFrom-Json
 $exact = Normalize-Path ([string]$request.executable)
 $root = Normalize-Path ([string]$request.install_path)
 if (-not $exact -and (-not $root -or $root.Length -le 3)) { throw 'Choose the actual game EXE with Track EXE to enable playtime.' }
 $clock = [Diagnostics.Stopwatch]::StartNew()
 $lastTick = 0.0; $seconds = 0.0; $started = $false; $wasRunning = $false; $missing = 0; $state = 'waiting'; $lastPlayed = ''; $message = 'Waiting for the game (up to 3 minutes)...'
 function Write-State {
  $payload = @{session=$request.session;started=$started;seconds=$seconds;state=$state;last_played=$lastPlayed;message=$message;heartbeat=$clock.Elapsed.TotalSeconds}
  [IO.File]::WriteAllText($ResultPath+'.tmp',($payload | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath ($ResultPath+'.tmp') -Destination $ResultPath -Force
 }
 while ($true) {
  if (Test-Path -LiteralPath ($RequestPath+'.stop')) { $state='ended'; $message='Tracking stopped.'; Write-State; break }
  if (-not (Get-Process -Id ([int]$request.parent_pid) -ErrorAction SilentlyContinue)) { $state='ended'; $message='CoverFlow closed; tracking stopped.'; Write-State; break }
  $processes = @(Get-CimInstance -ClassName Win32_Process -Property ExecutablePath,ProcessId,Name -ErrorAction Stop)
  $running = @($processes | Where-Object { Test-GameProcess $_ $exact $root }).Count -gt 0
  $now = $clock.Elapsed.TotalSeconds
  $delta = $now - $lastTick
  # Count only observed running intervals. Large gaps (sleep/suspend) never add hours.
  if ($running -and $wasRunning -and $delta -le 10) { $seconds += $delta }
  $lastTick = $now; $wasRunning = $running
  if ($running) {
   $started = $true; $missing=0; $state='running'
   $lastPlayed = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
   $message='Tracking while the game is running.'
  } elseif ($started) {
   $missing++
   $state='checking'; $message='Checking whether the game has closed...'
   if ($missing -ge 3) { $state='ended'; $message='Session saved.' }
  } elseif ($now -ge 180) {
   $state='timeout'; $message='No game process detected. Use Track EXE to choose the actual game executable.'
  }
  Write-State
  if ($state -in @('ended','timeout')) { break }
  Start-Sleep -Seconds 3
 }
} catch {
 $payload = @{session=if($request){$request.session}else{''};state='error';started=$false;message=('Tracking unavailable: '+$_.Exception.Message)}
 [IO.File]::WriteAllText($ResultPath,($payload | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}
