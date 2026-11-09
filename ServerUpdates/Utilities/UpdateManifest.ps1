$script:ServerUpdateManifestSchemaVersion = 1
$script:ServerUpdateManifestFileName = "server-update-manifest.json"

function Get-ServerUpdateManifest {
    $manifestPath = Join-Path (Get-Location) $script:ServerUpdateManifestFileName
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return [pscustomobject]@{
            schemaVersion = $script:ServerUpdateManifestSchemaVersion
            components = [pscustomobject]@{}
        }
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Could not read update manifest '$manifestPath': $($_.Exception.Message)"
    }

    if ($null -eq $manifest -or
        $manifest.schemaVersion -ne $script:ServerUpdateManifestSchemaVersion -or
        $manifest.components -isnot [System.Management.Automation.PSCustomObject]) {
        throw "Update manifest '$manifestPath' has an unsupported or invalid format."
    }

    return $manifest
}

function Test-ServerUpdateInstalled {
    param (
        [Parameter(Mandatory)]
        [hashtable]$Components,
        [Parameter(Mandatory)]
        [string[]]$Paths
    )

    $manifest = Get-ServerUpdateManifest
    foreach ($component in $Components.Keys) {
        $record = $manifest.components.PSObject.Properties[$component]
        if ($null -eq $record -or [string]$record.Value -ne [string]$Components[$component]) {
            return $false
        }
    }

    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            return $false
        }
    }

    return $true
}

function Set-ServerUpdateVersions {
    param (
        [Parameter(Mandatory)]
        [hashtable]$Components
    )

    $manifestPath = Join-Path (Get-Location) $script:ServerUpdateManifestFileName
    $manifest = Get-ServerUpdateManifest
    foreach ($component in $Components.Keys) {
        $version = [string]$Components[$component]
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw "Cannot record an empty version for '$component' in the update manifest."
        }

        $record = $manifest.components.PSObject.Properties[$component]
        if ($null -eq $record) {
            Add-Member -InputObject $manifest.components -MemberType NoteProperty -Name $component -Value $version
        }
        else {
            $record.Value = $version
        }
    }

    $temporaryPath = $manifestPath + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        ConvertTo-Json -InputObject $manifest -Depth 5 |
            Set-Content -LiteralPath $temporaryPath -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force -ErrorAction Stop
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}
