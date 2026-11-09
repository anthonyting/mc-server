@{
    RootModule = 'ServerUpdates.psm1'
    ModuleVersion = '1.0.0'
    GUID = '5e4d9905-9327-4e84-a17c-4c0dc6e04850'
    Author = 'Anthony Ting'
    Description = 'Updates the Minecraft server and its plugins.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Update-All',
        'Update-Paper',
        'Update-Spigot',
        'Update-LuckPerms',
        'Update-Vault',
        'Update-EssentialsX',
        'Update-PersonalPlugins',
        'Disable-PluginMetrics'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
