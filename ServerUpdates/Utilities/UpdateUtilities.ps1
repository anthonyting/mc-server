function New-UpdateStagingDirectory {
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    $stagingRoot = Join-Path (Get-Location) "downloading"
    New-Item -Path $stagingRoot -ItemType Directory -Force | Out-Null

    $stagingDirectory = Join-Path $stagingRoot ($Name + "-" + [guid]::NewGuid().ToString("N"))
    New-Item -Path $stagingDirectory -ItemType Directory -Force | Out-Null
    return $stagingDirectory
}

function Get-PluginInstallPath {
    param (
        [Parameter(Mandatory)]
        [string]$FileName
    )

    return Join-Path (Join-Path (Get-Location) "plugins") $FileName
}

function Remove-UpdateStagingDirectory {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-ValidatedUpdateDownloadUri {
    param (
        [Parameter(Mandatory)]
        [string]$Uri,
        [Parameter(Mandatory)]
        [string]$ExpectedHost,
        [Parameter(Mandatory)]
        [string]$ArtifactName
    )

    $downloadUri = [uri]$Uri
    if (-not $downloadUri.IsAbsoluteUri -or
        $downloadUri.Scheme -ne "https" -or
        $downloadUri.Host -ne $ExpectedHost) {
        throw "Unexpected download URL for $ArtifactName; refusing to update."
    }

    return $downloadUri
}

function Get-UpdateRequestHeaders {
    return @{
        "Accept" = "application/json"
    }
}

function Get-LatestGitHubStableRelease {
    param (
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [string]$ComponentName
    )

    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$Repository/releases/latest" `
        -Headers (Get-UpdateRequestHeaders) `
        -ErrorAction Stop
    if ($release.draft -or $release.prerelease -or [string]::IsNullOrWhiteSpace($release.tag_name)) {
        throw "GitHub did not return a valid stable $ComponentName release."
    }

    return $release
}

function Invoke-UpdateDownload {
    param (
        [Parameter(Mandatory)]
        [string]$Uri,
        [Parameter(Mandatory)]
        [string]$ExpectedHost,
        [Parameter(Mandatory)]
        [string]$ArtifactName,
        [Parameter(Mandatory)]
        [string]$OutFile,
        [hashtable[]]$ExpectedHashes = @()
    )

    $downloadUri = Get-ValidatedUpdateDownloadUri `
        -Uri $Uri `
        -ExpectedHost $ExpectedHost `
        -ArtifactName $ArtifactName

    $hashLengths = @{
        SHA256 = 64
        SHA512 = 128
    }
    foreach ($expectedHash in $ExpectedHashes) {
        $algorithm = ([string]$expectedHash.Algorithm).ToUpperInvariant()
        $expectedValue = [string]$expectedHash.Hash
        if (-not $hashLengths.ContainsKey($algorithm)) {
            throw "Unsupported hash algorithm '$algorithm' for $ArtifactName."
        }
        $hashLength = $hashLengths[$algorithm]

        if ($expectedValue -notmatch "^[0-9a-fA-F]{$hashLength}$") {
            throw "Missing or invalid $algorithm verification metadata for $ArtifactName."
        }
    }

    Invoke-WebRequest -Uri $downloadUri.AbsoluteUri -OutFile $OutFile -ErrorAction Stop | Out-Null

    foreach ($expectedHash in $ExpectedHashes) {
        $algorithm = ([string]$expectedHash.Algorithm).ToUpperInvariant()
        $actualHash = (Get-FileHash -Path $OutFile -Algorithm $algorithm -ErrorAction Stop).Hash
        if ($actualHash -ine [string]$expectedHash.Hash) {
            throw "$algorithm verification failed for $ArtifactName; the installed file was not changed."
        }
    }
}

function Install-UpdateArtifacts {
    param (
        [Parameter(Mandatory)]
        [object[]]$Artifacts
    )

    foreach ($artifact in $Artifacts) {
        $targetDirectory = Split-Path -Path $artifact.Target -Parent
        if (-not [string]::IsNullOrWhiteSpace($targetDirectory)) {
            New-Item -Path $targetDirectory -ItemType Directory -Force | Out-Null
        }

        Move-Item -Path $artifact.Path -Destination $artifact.Target -Force -ErrorAction Stop
    }
}
