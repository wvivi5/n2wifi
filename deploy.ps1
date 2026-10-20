<#
  deploy.ps1 -- copy n2wifi to one or many Android phones over ssh.

    .\deploy.ps1 -Serial 4bbc97a9                     # over USB (adb forward)
    .\deploy.ps1 -IPs 192.168.1.50                    # one phone
    .\deploy.ps1 -Range 192.168.1.50-59               # a whole range
    .\deploy.ps1 -Range 192.168.1.50-59 -Key C:\Users\me\.ssh\id_ed25519

  Needs the OpenSSH client (ssh.exe / scp.exe, built into Windows 10+) and,
  for -Serial, adb.  Exit code = number of phones that failed.
#>
[CmdletBinding()]
param(
    [string[]]$IPs,
    [string]$Range,
    [string]$Serial,
    [int]$Port = 8022,
    [string]$User = 'root',
    [string]$Key,
    [string]$Dest = '/usr/local/bin/n2wifi',
    [string]$Adb
)

$ErrorActionPreference = 'Continue'

$Src = Join-Path $PSScriptRoot 'n2wifi'
if (-not (Test-Path $Src)) { throw "missing $Src" }
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    throw "scp.exe not found -- install the OpenSSH client (Settings > Apps > Optional features)"
}

$sshOpt = @('-o', 'StrictHostKeyChecking=accept-new', '-o', 'UserKnownHostsFile=NUL',
            '-o', 'LogLevel=ERROR', '-o', 'ConnectTimeout=10')
$scpOpt = @('-o', 'StrictHostKeyChecking=accept-new', '-o', 'UserKnownHostsFile=NUL',
            '-o', 'LogLevel=ERROR', '-o', 'ConnectTimeout=10')

# Keys: use the one given, else the usual suspects in ~/.ssh.  Nothing found means
# password auth -- and a hidden password prompt in a script just hangs, so fail fast.
if (-not $Key) {
    foreach ($c in @("$env:USERPROFILE\.ssh\id_ed25519", "$env:USERPROFILE\.ssh\id_rsa",
                     "$env:USERPROFILE\.ssh\id_ecdsa", "$env:USERPROFILE\.ssh\note2_key")) {
        if (Test-Path $c) { $Key = $c; break }
    }
}
if ($Key) {
    $sshOpt += @('-i', $Key)
    $scpOpt += @('-i', $Key)
} else {
    Write-Host "! no ssh key found in ~/.ssh -- if the phone wants a password, pass -Key <path>"
    $sshOpt += @('-o', 'BatchMode=yes')
    $scpOpt += @('-o', 'BatchMode=yes')
}

# ---- build the target list -------------------------------------------------
$targets = @()

if ($IPs) {
    foreach ($ip in $IPs) { $targets += $ip }
}

if ($Range) {
    if ($Range -notmatch '^(\d+\.\d+\.\d+)\.(\d+)-(\d+)$') {
        throw "bad -Range '$Range' (expected like 192.168.1.50-59)"
    }
    $prefix = $Matches[1]
    $from = [int]$Matches[2]
    $to = [int]$Matches[3]
    if ($to -lt $from) { throw "bad -Range '$Range' (end < start)" }
    for ($i = $from; $i -le $to; $i++) { $targets += "$prefix.$i" }
}

if ($Serial) {
    if (-not $Adb) {
        $cand = Get-Command adb -ErrorAction SilentlyContinue
        if ($cand) { $Adb = $cand.Source }
    }
    if (-not $Adb) {
        $cand = Join-Path $PSScriptRoot 'platform-tools\adb.exe'
        if (Test-Path $cand) { $Adb = $cand }
    }
    if (-not $Adb) { throw "-Serial needs adb (put it in PATH or pass -Adb)" }
    Write-Host "-> adb forward tcp:$Port for $Serial"
    & $Adb -s $Serial forward "tcp:$Port" "tcp:$Port" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "adb forward failed (is $Serial connected?)" }
    $targets += '127.0.0.1'
}

if (-not $targets) {
    Write-Host "usage: .\deploy.ps1 -Serial <serial> | -IPs a,b | -Range 192.168.1.50-59"
    exit 1
}

# ---- push ------------------------------------------------------------------
$fail = 0
foreach ($h in $targets) {
    $where = "$User@$h"
    Write-Host "-> $where (port $Port)"
    & scp @scpOpt -P $Port $Src "${where}:$Dest"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   [fail] scp"
        $fail++
        continue
    }
    $out = & ssh @sshOpt -p $Port $where "chmod 755 '$Dest' && '$Dest' --version && '$Dest' list" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   [fail] pushed, but the self test failed:"
        $out | ForEach-Object { Write-Host "          $_" }
        $fail++
        continue
    }
    $out | ForEach-Object { Write-Host "   $_" }
    Write-Host "   [ok]"
}

Write-Host ""
Write-Host ("{0} ok, {1} failed" -f ($targets.Count - $fail), $fail)
exit $fail
