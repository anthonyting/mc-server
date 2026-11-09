. (Join-Path $PSScriptRoot "Utilities\UpdateUtilities.ps1")
. (Join-Path $PSScriptRoot "Utilities\UpdateManifest.ps1")
. (Join-Path $PSScriptRoot "Utilities\ModrinthUtilities.ps1")
. (Join-Path $PSScriptRoot "Utilities\PluginMetrics.ps1")
. (Join-Path $PSScriptRoot "Updaters\Server\Paper.ps1")
. (Join-Path $PSScriptRoot "Updaters\Server\Spigot.ps1")
. (Join-Path $PSScriptRoot "Updaters\Plugins\LuckPerms.ps1")
. (Join-Path $PSScriptRoot "Updaters\Plugins\Vault.ps1")
. (Join-Path $PSScriptRoot "Updaters\Plugins\EssentialsX.ps1")
. (Join-Path $PSScriptRoot "Updaters\Plugins\PersonalPlugins.ps1")

function Update-All {
    param (
        $windowTitle,
        $versionGroup,
        $debug
    )

    $Host.UI.RawUI.WindowTitle = $windowTitle + " - Updating"
    if ($debug) {
        Write-Host "Debug mode: using Spigot instead of Paper"
        Update-Spigot
    }
    else {
        Update-Paper $versionGroup
    }
    Update-PersonalPlugins
    Update-LuckPerms -versionGroup $versionGroup
    Update-Vault -versionGroup $versionGroup
    Update-EssentialsX -versionGroup $versionGroup
    $Host.UI.RawUI.WindowTitle = $windowTitle
}

Export-ModuleMember -Function Update-All, Update-Paper, Update-Spigot, Update-LuckPerms, Update-Vault, Update-EssentialsX, Update-PersonalPlugins, Disable-PluginMetrics
