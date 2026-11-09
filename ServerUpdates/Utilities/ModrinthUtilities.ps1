function Get-ModrinthPaperRelease {
    param (
        [Parameter(Mandatory)]
        [string]$ProjectSlug,
        [Parameter(Mandatory)]
        [string]$ComponentName,
        [Parameter(Mandatory)]
        [string]$VersionGroup,
        [string]$VersionNumber,
        [switch]$AllowUnlistedGameVersion
    )

    $paperLoader = "paper"
    $stableVersionType = "release"
    $loaderJson = ConvertTo-Json -InputObject @($paperLoader) -Compress
    $loaderFilter = [uri]::EscapeDataString($loaderJson)
    $versionsUrl = "https://api.modrinth.com/v2/project/$ProjectSlug/version?loaders=$loaderFilter"
    $versions = Invoke-UpdateHttpRequest -Request {
        Invoke-RestMethod `
            -Uri $versionsUrl `
            -Headers (Get-UpdateRequestHeaders) `
            -ErrorAction Stop
    }

    if (-not [string]::IsNullOrWhiteSpace($VersionNumber)) {
        $version = $versions |
            Where-Object { $_.version_number -eq $VersionNumber } |
            Select-Object -First 1
        if ($null -eq $version) {
            throw "$ComponentName $VersionNumber is not available on Modrinth."
        }

        if ($version.version_type -ne $stableVersionType -or
            -not ($version.loaders -contains $paperLoader) -or
            (-not $AllowUnlistedGameVersion -and
                -not (Test-PaperGameVersion -SupportedVersions $version.game_versions -VersionGroup $VersionGroup))) {
            throw "$ComponentName $VersionNumber is not a stable Paper release for Minecraft $VersionGroup."
        }

        return $version
    }

    $version = $versions |
        Where-Object {
            $_.version_type -eq $stableVersionType -and
            $_.loaders -contains $paperLoader -and
            (Test-PaperGameVersion -SupportedVersions $_.game_versions -VersionGroup $VersionGroup)
        } |
        Sort-Object { [DateTimeOffset]::Parse($_.date_published) } -Descending |
        Select-Object -First 1

    if ($null -eq $version) {
        throw "No stable $ComponentName Paper release found for Minecraft $VersionGroup."
    }

    return $version
}

function Test-PaperGameVersion {
    param (
        [string[]]$SupportedVersions,
        [string]$VersionGroup
    )

    $escapedVersionGroup = [regex]::Escape($VersionGroup)
    foreach ($supportedVersion in $SupportedVersions) {
        if ($supportedVersion -eq $VersionGroup -or
            $supportedVersion -match "^$escapedVersionGroup\.\d+$") {
            return $true
        }
    }

    return $false
}

function Update-ModrinthPlugin {
    param (
        [Parameter(Mandatory)]
        [string]$ProjectSlug,
        [Parameter(Mandatory)]
        [string]$ComponentName,
        [Parameter(Mandatory)]
        [string]$FileNamePattern,
        [Parameter(Mandatory)]
        [string]$TargetFileName,
        [Parameter(Mandatory)]
        [string]$VersionGroup
    )

    $version = Get-ModrinthPaperRelease `
        -ProjectSlug $ProjectSlug `
        -ComponentName $ComponentName `
        -VersionGroup $VersionGroup

    $file = $version.files |
        Where-Object { $_.filename -match $FileNamePattern } |
        Select-Object -First 1
    if ($null -eq $file) {
        throw "No $ComponentName JAR found in Modrinth version $($version.version_number)."
    }

    $expectedSha512 = [string]$file.hashes.sha512
    if ($expectedSha512 -notmatch '^[0-9a-fA-F]{128}$') {
        throw "Missing or invalid Modrinth SHA-512 verification metadata for $($file.filename)."
    }

    $installedPath = Get-PluginInstallPath -FileName $TargetFileName
    $componentVersion = @{ $ComponentName = $version.version_number }
    if (Test-ServerUpdateInstalled -Components $componentVersion -Paths @($installedPath)) {
        Write-Host "$ComponentName $($version.version_number) is already installed; skipping download."
        return
    }

    $stagingDirectory = New-UpdateStagingDirectory -Name $ComponentName.ToLowerInvariant()
    $downloadPath = Join-Path $stagingDirectory $file.filename
    try {
        Write-Host "Downloading and verifying $ComponentName $($version.version_number)..."
        Invoke-UpdateDownload `
            -Uri $file.url `
            -ExpectedHost "cdn.modrinth.com" `
            -ArtifactName $ComponentName `
            -OutFile $downloadPath `
            -ExpectedHashes @(@{ Algorithm = "SHA512"; Hash = $expectedSha512 })

        Install-UpdateArtifacts -Artifacts @(@{
            Path = $downloadPath
            Target = $installedPath
        })
        Set-ServerUpdateVersions -Components $componentVersion
        Write-Host "Installed verified $ComponentName $($version.version_number)."
    }
    finally {
        Remove-UpdateStagingDirectory -Path $stagingDirectory
    }
}
