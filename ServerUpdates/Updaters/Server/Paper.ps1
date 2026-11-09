$script:PaperApiRoot = "https://fill.papermc.io/v3/projects/paper"

function Get-HighestVersion {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Versions,
        [hashtable]$Headers
    )

    process {
        $validVersions = foreach ($v in $Versions) {
            try {
                # Skip all versions that can't be converted into version objects.
                $versionObject = [version]$v

                # Check that a valid build is available for this version.
                $versionInfoUrl = "$script:PaperApiRoot/versions/$v"
                $versionInfo = Invoke-RestMethod -Uri $versionInfoUrl -Headers $Headers -ErrorAction Stop
                if ($versionInfo.builds.Count -eq 0) {
                    throw "$v has no valid builds"
                }

                $versionObject
            }
            catch {
                Write-Warning "Skipped: '$v'. Error: $($_.Exception.Message)"
            }
        }

        if (-not $validVersions) {
            throw "No valid versions found in input."
        }

        ($validVersions | Measure-Object -Maximum).Maximum
    }
}

function Update-Paper {
    param (
        $versionGroup
    )

    $ProgressPreference = 'SilentlyContinue'
    $headers = Get-UpdateRequestHeaders

    $paperFileName = "paper.jar"
    $projectUrl = $script:PaperApiRoot
    $project = Invoke-RestMethod -Uri $projectUrl -Headers $headers -ErrorAction Stop

    $versions = $project.versions.$versionGroup
    if ($null -eq $versions) {
        throw "No versions found for $versionGroup"
    }

    $highestVersion = Get-HighestVersion -Versions $versions -Headers $headers

    Write-Host "Getting build info for version $highestVersion.."
    $latestBuildUrl = "$script:PaperApiRoot/versions/$highestVersion/builds/latest"
    $latestBuildInfo = Invoke-RestMethod -Uri $latestBuildUrl -Headers $headers -ErrorAction Stop
    if ($latestBuildInfo.channel -ne "STABLE") {
        throw "Paper returned a non-stable build for Minecraft $highestVersion; refusing to update."
    }

    $download = $latestBuildInfo.downloads."server:default"
    $expectedSha256 = [string]$download.checksums.sha256
    if ($expectedSha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw "Missing or invalid SHA-256 verification metadata for Paper $highestVersion build $($latestBuildInfo.id)."
    }

    $paperPath = Join-Path (Get-Location) $paperFileName
    $paperVersion = "$($highestVersion.ToString())+build.$($latestBuildInfo.id)"
    $componentVersion = @{ Paper = $paperVersion }
    if (Test-ServerUpdateInstalled -Components $componentVersion -Paths @($paperPath)) {
        Write-Host "Paper $highestVersion build $($latestBuildInfo.id) is already installed; skipping download."
        return
    }

    $stagingDirectory = New-UpdateStagingDirectory -Name "paper"
    $downloadPath = Join-Path $stagingDirectory $paperFileName
    try {
        Write-Host "Downloading Paper $highestVersion build $($latestBuildInfo.id)..."
        Invoke-UpdateDownload `
            -Uri $download.url `
            -ExpectedHost "fill-data.papermc.io" `
            -ArtifactName "Paper $highestVersion build $($latestBuildInfo.id)" `
            -OutFile $downloadPath `
            -ExpectedHashes @(@{ Algorithm = "SHA256"; Hash = $expectedSha256 })

        Install-UpdateArtifacts -Artifacts @(@{
            Path = $downloadPath
            Target = $paperPath
        })
        Set-ServerUpdateVersions -Components $componentVersion
        Write-Host "Installed verified Paper $highestVersion build $($latestBuildInfo.id)."
    }
    finally {
        Remove-UpdateStagingDirectory -Path $stagingDirectory
    }
}
