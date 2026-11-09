function Update-PersonalPlugins {
    $componentName = "PersonalPlugins"
    $jarFileName = "$componentName.jar"
    $checksumFileName = "$jarFileName.sha256"
    $repository = "anthonyting/personal-plugins"
    $downloadHost = "github.com"

    Write-Host "Getting the latest PersonalPlugins release metadata..."
    $release = Get-LatestGitHubStableRelease `
        -Repository $repository `
        -ComponentName $componentName

    $jarAsset = $release.assets |
        Where-Object { $_.name -eq $jarFileName } |
        Select-Object -First 1
    $checksumAsset = $release.assets |
        Where-Object { $_.name -eq $checksumFileName } |
        Select-Object -First 1
    if ($null -eq $jarAsset -or $null -eq $checksumAsset) {
        throw "The latest $componentName release is missing the JAR or its SHA-256 checksum."
    }

    foreach ($asset in @($jarAsset, $checksumAsset)) {
        $null = Get-ValidatedUpdateDownloadUri `
            -Uri $asset.browser_download_url `
            -ExpectedHost $downloadHost `
            -ArtifactName $asset.name
    }

    $releaseVersion = $release.tag_name -replace '^[vV]', ''
    $componentVersion = @{}
    $componentVersion[$componentName] = $releaseVersion
    $installedJarPath = Get-PluginInstallPath -FileName $jarFileName
    if (Test-ServerUpdateInstalled `
            -Components $componentVersion `
            -Paths @($installedJarPath)) {
        Write-Host "PersonalPlugins $($release.tag_name) is already installed; skipping download."
        return
    }

    $stagingDirectory = New-UpdateStagingDirectory -Name $componentName.ToLowerInvariant()
    $downloadPath = Join-Path $stagingDirectory $jarFileName
    $checksumPath = Join-Path $stagingDirectory $checksumFileName
    try {
        Write-Host "Downloading and verifying PersonalPlugins $($release.tag_name)..."
        Invoke-UpdateDownload `
            -Uri $checksumAsset.browser_download_url `
            -ExpectedHost $downloadHost `
            -ArtifactName $checksumAsset.name `
            -OutFile $checksumPath
        $expectedSha256 = (Get-Content -Path $checksumPath -Raw -ErrorAction Stop).Trim()
        if ($expectedSha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Missing or invalid SHA-256 checksum for $componentName."
        }

        Invoke-UpdateDownload `
            -Uri $jarAsset.browser_download_url `
            -ExpectedHost $downloadHost `
            -ArtifactName $jarAsset.name `
            -OutFile $downloadPath `
            -ExpectedHashes @(@{ Algorithm = "SHA256"; Hash = $expectedSha256 })

        Install-UpdateArtifacts -Artifacts @(@{
            Path = $downloadPath
            Target = $installedJarPath
        })
        Set-ServerUpdateVersions -Components $componentVersion
        Write-Host "Installed verified PersonalPlugins $($release.tag_name)."
    }
    finally {
        Remove-UpdateStagingDirectory -Path $stagingDirectory
    }
}
