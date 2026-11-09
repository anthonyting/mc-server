$script:EssentialsXSnapshotRepositoryRoot = "https://repo.essentialsx.net/snapshots/net/essentialsx"

function Get-EssentialsXLatestSnapshotVersion {
    param (
        [Parameter(Mandatory)]
        [string]$ArtifactName
    )

    $snapshotVersionPattern = '^\d+\.\d+\.\d+-SNAPSHOT$'
    $snapshotQualifierPattern = '-SNAPSHOT$'
    $artifactUrl = "$script:EssentialsXSnapshotRepositoryRoot/$ArtifactName"
    $metadata = Invoke-UpdateHttpRequest -Request {
        Invoke-RestMethod -Uri "$artifactUrl/maven-metadata.xml" -ErrorAction Stop
    }
    $snapshotVersions = @($metadata.metadata.versioning.versions.version) |
        ForEach-Object { [string]$_ } |
        Where-Object { $_ -match $snapshotVersionPattern }
    $latestVersion = [string]$metadata.metadata.versioning.latest

    if ($latestVersion -notmatch $snapshotVersionPattern -or
        $snapshotVersions -notcontains $latestVersion) {
        $latestVersion = $snapshotVersions |
            Sort-Object { [version]($_ -replace $snapshotQualifierPattern, '') } -Descending |
            Select-Object -First 1
    }

    if ([string]::IsNullOrWhiteSpace($latestVersion)) {
        throw "Could not find a valid EssentialsX snapshot version for $ArtifactName."
    }

    return $latestVersion
}

function Get-EssentialsXSnapshotArtifact {
    param (
        [Parameter(Mandatory)]
        [string]$ArtifactName,
        [Parameter(Mandatory)]
        [string]$SnapshotVersion
    )

    $repositoryUrl = "$script:EssentialsXSnapshotRepositoryRoot/$ArtifactName/$SnapshotVersion"
    $metadataUrl = "$repositoryUrl/maven-metadata.xml"
    $metadata = Invoke-UpdateHttpRequest -Request {
        Invoke-RestMethod -Uri $metadataUrl -ErrorAction Stop
    }
    $snapshotArtifact = $metadata.metadata.versioning.snapshotVersions.snapshotVersion |
        Where-Object {
            $_.extension -eq "jar" -and
            [string]::IsNullOrWhiteSpace([string]$_.classifier)
        } |
        Select-Object -First 1

    $artifactVersion = [string]$snapshotArtifact.value
    $snapshotQualifierPattern = '-SNAPSHOT$'
    $snapshotNumericVersion = $SnapshotVersion -replace $snapshotQualifierPattern, ''
    $snapshotBaseVersion = [regex]::Escape($snapshotNumericVersion)
    $buildPattern = "^$snapshotBaseVersion-\d{8}\.\d{6}-\d+$"
    if ($artifactVersion -notmatch $buildPattern) {
        throw "Could not resolve a valid $SnapshotVersion JAR for $ArtifactName."
    }

    $fileName = "$ArtifactName-$artifactVersion.jar"
    $checksumUri = "$repositoryUrl/$fileName.sha256"
    $checksum = [string](Invoke-UpdateHttpRequest -Request {
        Invoke-RestMethod -Uri $checksumUri -ErrorAction Stop
    })
    $checksumValue = $checksum.Trim()
    if ($checksumValue -notmatch '^[0-9a-fA-F]{64}$') {
        throw "Missing or invalid SHA-256 verification metadata for $fileName."
    }

    return [pscustomobject]@{
        Version = $artifactVersion
        FileName = $fileName
        Uri = "$repositoryUrl/$fileName"
        Sha256 = $checksumValue
    }
}

function Update-EssentialsX {
    param (
        $versionGroup
    )

    Write-Host "Getting the latest EssentialsX snapshot metadata..."
    $coreArtifactName = "EssentialsX"
    $chatArtifactName = "EssentialsXChat"
    $coreFileName = "$coreArtifactName.jar"
    $chatFileName = "$chatArtifactName.jar"
    $coreSnapshotVersion = Get-EssentialsXLatestSnapshotVersion -ArtifactName $coreArtifactName
    $chatSnapshotVersion = Get-EssentialsXLatestSnapshotVersion -ArtifactName $chatArtifactName
    if ($coreSnapshotVersion -ne $chatSnapshotVersion) {
        throw "EssentialsX Core and Chat do not have the same latest snapshot version."
    }

    $coreArtifact = Get-EssentialsXSnapshotArtifact `
        -ArtifactName $coreArtifactName `
        -SnapshotVersion $coreSnapshotVersion
    $chatArtifact = Get-EssentialsXSnapshotArtifact `
        -ArtifactName $chatArtifactName `
        -SnapshotVersion $chatSnapshotVersion
    if ($coreArtifact.Version -ne $chatArtifact.Version) {
        throw "EssentialsX Core and Chat snapshots do not match; refusing to install different builds."
    }

    $releaseVersion = $coreArtifact.Version
    $essentialsPath = Get-PluginInstallPath -FileName $coreFileName
    $essentialsChatPath = Get-PluginInstallPath -FileName $chatFileName
    $essentialsComponents = @{
        EssentialsX = $releaseVersion
        EssentialsXChat = $releaseVersion
    }
    if (Test-ServerUpdateInstalled `
            -Components $essentialsComponents `
            -Paths @($essentialsPath, $essentialsChatPath)) {
        Write-Host "EssentialsX $releaseVersion artifacts are already installed; skipping downloads."
        return
    }

    $plugins = @(
        @{ Artifact = $coreArtifact; Target = $coreFileName },
        @{ Artifact = $chatArtifact; Target = $chatFileName }
    )
    $verifiedDownloads = @()
    $stagingDirectory = New-UpdateStagingDirectory -Name "essentialsx"
    try {
        foreach ($plugin in $plugins) {
            $artifact = $plugin.Artifact
            $downloadPath = Join-Path $stagingDirectory $artifact.FileName
            Write-Host "Downloading and verifying $($artifact.FileName)..."

            Invoke-UpdateDownload `
                -Uri $artifact.Uri `
                -ExpectedHost "repo.essentialsx.net" `
                -ArtifactName $artifact.FileName `
                -OutFile $downloadPath `
                -ExpectedHashes @(@{ Algorithm = "SHA256"; Hash = $artifact.Sha256 })

            $verifiedDownloads += @{
                Path = $downloadPath
                Target = Get-PluginInstallPath -FileName $plugin.Target
            }
        }

        Install-UpdateArtifacts -Artifacts $verifiedDownloads
        Set-ServerUpdateVersions -Components $essentialsComponents
        Write-Host "Installed verified EssentialsX snapshot $releaseVersion artifacts."
    }
    finally {
        Remove-UpdateStagingDirectory -Path $stagingDirectory
    }
}
