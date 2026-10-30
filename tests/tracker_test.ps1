$ErrorActionPreference='Stop'
$helper=Join-Path $PSScriptRoot '../track_game.ps1'
. $helper -RequestPath 'unused' -ResultPath 'unused'
$root=Normalize-Path 'C:\Games\Sample'
function Assert($condition,$message){if(-not $condition){throw $message};'PASS: '+$message}
Assert (Test-GameProcess @{ExecutablePath='C:\Games\Sample\bin\game.exe'} '' $root) 'Game subprocess inside install folder is tracked'
Assert (-not (Test-GameProcess @{ExecutablePath='C:\Games\SampleOther\game.exe'} '' $root)) 'Sibling folder is not counted'
Assert (-not (Test-GameProcess @{ExecutablePath='C:\Games\Sample\steam.exe'} '' $root)) 'Steam launcher is excluded'
Assert (-not (Test-GameProcess @{ExecutablePath='C:\Games\Sample\CrashReportClient.exe'} '' $root)) 'Crash reporter is excluded'
Assert (-not (Test-GameProcess @{ExecutablePath=$null} '' $root)) 'Unreadable executable paths are not guessed'
$exe=Normalize-Path 'C:\Games\Sample\bin\game.exe'
Assert (Test-GameProcess @{ExecutablePath='C:\Games\Sample\bin\game.exe'} $exe '') 'Exact executable override matches'
Assert (-not (Test-GameProcess @{ExecutablePath='C:\Games\Sample\bin\other.exe'} $exe $root)) 'Exact override does not broaden to install folder'
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($helper,[ref]$tokens,[ref]$errors)|Out-Null
Assert ($errors.Count -eq 0) 'PowerShell helper syntax'
# Run actual monitoring loop with mocked process enumeration and no sleep.
$global:trackingTestPoll=0
function Get-CimInstance {param($ClassName,$Property,$ErrorAction)
 $global:trackingTestPoll++
 if($global:trackingTestPoll -le 3){[pscustomobject]@{ExecutablePath='C:\Games\Sample\bin\game.exe'}}
}
function Get-Process {param($Id,$ErrorAction) return @{Id=1}}
function Start-Sleep {param($Seconds)}
$folder=Join-Path $PSScriptRoot 'tracker_fixture';New-Item -ItemType Directory -Force $folder|Out-Null
$request=Join-Path $folder 'request.json';$result=Join-Path $folder 'result.json'
@{session='test';parent_pid=1;install_path='C:\Games\Sample';executable=''}|ConvertTo-Json|Set-Content $request
& $helper -RequestPath $request -ResultPath $result
$out=Get-Content $result -Raw|ConvertFrom-Json
Assert ($out.started -and $out.state -eq 'ended') 'Observed game session ends after process disappears'
Assert ($global:trackingTestPoll -eq 6) 'Exit grace period allows transient launcher handoff'
Assert ($out.seconds -ge 0 -and $out.seconds -lt 10) 'Loop counts only observed runtime'
