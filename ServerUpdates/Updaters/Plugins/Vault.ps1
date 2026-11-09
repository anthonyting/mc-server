function Update-Vault {
    param (
        $versionGroup
    )

    Update-ModrinthPlugin `
        -ProjectSlug "vaultunlocked" `
        -ComponentName "Vault" `
        -FileNamePattern '^VaultUnlocked-[0-9][A-Za-z0-9.+-]*\.jar$' `
        -TargetFileName "Vault.jar" `
        -VersionGroup $versionGroup
}
