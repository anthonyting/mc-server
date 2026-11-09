function Update-LuckPerms {
    param (
        $versionGroup
    )

    Update-ModrinthPlugin `
        -ProjectSlug "luckperms" `
        -ComponentName "LuckPerms" `
        -FileNamePattern '^LuckPerms-Bukkit-[0-9][A-Za-z0-9.+-]*\.jar$' `
        -TargetFileName "LuckPerms.jar" `
        -VersionGroup $versionGroup
}
