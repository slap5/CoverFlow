param([Parameter(Mandatory=$true)][string]$RequestPath,[Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference='Stop'
try {
    $request=[IO.File]::ReadAllText($RequestPath) | ConvertFrom-Json
    $target=[string]$request.target
    if($request.kind -eq 'file') {
        if(-not [IO.Path]::IsPathRooted($target) -or [IO.Path]::GetExtension($target).ToLowerInvariant() -notin @('.exe','.lnk','.url') -or -not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Game file is missing or unsupported.' }
        # Parameter values remain data. No shell command strings are constructed.
        Start-Process -FilePath $target -WorkingDirectory ([IO.Path]::GetDirectoryName($target)) -ErrorAction Stop
    } elseif($request.kind -eq 'xbox' -and $target -match '^shell:AppsFolder\\[A-Za-z0-9._-]+![A-Za-z0-9._-]+$') {
        Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList $target -ErrorAction Stop
    } else { throw 'Unsupported launch request.' }
    $result=@{ok=$true;message='Launch request sent.'}
} catch { $result=@{ok=$false;message=$_.Exception.Message} }
[IO.File]::WriteAllText($ResultPath,($result | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
