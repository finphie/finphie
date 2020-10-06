param (
    [Parameter(Mandatory)]
    [string]$targetRepository,
    [string]$configRepository = 'dotfiles',
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ignoreFiles = @()
)

function Get-EmptyHash {
    [CmdletBinding()]
    param ()

    return Invoke-Expression 'git hash-object -t tree /dev/null'
}

[hashtable]$json = @{}
[string]$hash = ''
[string]$configFilePath = Join-Path $targetRepository ".github/$configRepository.json"

if (Test-Path $configFilePath) {
    [Hashtable]$json = Get-Content $configFilePath | ConvertFrom-Json -AsHashtable
    $hash = $json.ContainsKey('hash') ? $json['hash'] : (Get-EmptyHash)
}
else {
    $hash = Get-EmptyHash
}

Write-Output $hash
$lines = Invoke-Expression "git -C $configRepository diff $hash --name-status"
Write-Output $lines

$ignoreTable = New-Object System.Collections.Generic.HashSet[string] (,[string[]]$ignoreFiles)

foreach ($line in $lines) {
    $x = $line -split '\t'

    if ($ignoreTable.Contains($x[1])) {
        Remove-Item $x[1] -ErrorAction SilentlyContinue
    }
    elseif ($x[0] -eq 'M' -or $x[0] -eq 'A') {
        $path = Join-Path $configRepository $x[1]
        $targetPath = Join-Path $targetRepository $x[1]
        $targetParentPath = Split-Path $targetPath -Parent

        Write-Host "[+] $targetPath" -ForegroundColor Green
        New-Item $targetParentPath -ItemType Directory -Force | Out-Null
        Copy-Item $path $targetPath -Force
    }
    elseif ($x[0] -eq 'D') {
        $targetPath = Join-Path $targetRepository $x[1]

        Write-Host "[-] $targetPath" -ForegroundColor Red
        Remove-Item $targetPath -ErrorAction SilentlyContinue
    }
    elseif ($x[0].StartsWith('R')) {
        $path = Join-Path $configRepository $x[2]
        $targetPath = Join-Path $targetRepository $x[2]
        $targetParentPath = Split-Path $targetPath -Parent
        $oldTargetPath = Join-Path $targetRepository $x[1]

        Write-Host "[-] $oldTargetPath" -ForegroundColor Red
        Remove-Item $oldTargetPath -ErrorAction SilentlyContinue

        Write-Host "[+] $targetPath" -ForegroundColor Green
        New-Item $targetParentPath -ItemType Directory -Force | Out-Null
        Copy-Item $path $targetPath -Force
    }
    else {
        exit -1
    }
}

[string]$newHash = Invoke-Expression "git -C $configRepository rev-parse HEAD"
$json['hash'] = $newHash
$json | ConvertTo-Json | Out-File $configFilePath -NoNewline