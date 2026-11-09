function Set-PluginMetricsDisabled {
    param (
        [Parameter(Mandatory)]
        [string]$ConfigPath,
        [Parameter(Mandatory)]
        [ValidateSet(":", "=")]
        [string]$Separator
    )

    New-Item -Path (Split-Path -Path $ConfigPath -Parent) -ItemType Directory -Force | Out-Null
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        $content = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
    }
    else {
        $content = ""
    }

    $propertyPattern = "(?m)^enabled\s*$([regex]::Escape($Separator))"
    if ($Separator -eq ":") {
        $valueSpacingPattern = '\s+'
        $disabledSetting = "enabled: false"
    }
    else {
        $valueSpacingPattern = '\s*'
        $disabledSetting = "enabled=false"
    }
    $disabledPattern = "$propertyPattern$valueSpacingPattern" + 'false\s*(?:#.*)?$'
    if ($content -match $disabledPattern) {
        return
    }

    if ($content -match $propertyPattern) {
        $content = [regex]::Replace($content, "$propertyPattern.*$", $disabledSetting, 1)
    }
    else {
        $content = $disabledSetting + [Environment]::NewLine + $content
    }

    Set-Content -LiteralPath $ConfigPath -Value $content -Encoding UTF8 -ErrorAction Stop
}

function Disable-PluginMetrics {
    $pluginsDirectory = Join-Path (Get-Location) "plugins"

    # bStats uses one global opt-out for Bukkit plugins.
    Set-PluginMetricsDisabled `
        -ConfigPath (Join-Path (Join-Path $pluginsDirectory "bStats") "config.yml") `
        -Separator ":"

    Set-PluginMetricsDisabled `
        -ConfigPath (Join-Path (Join-Path $pluginsDirectory "faststats") "config.properties") `
        -Separator "="
}
