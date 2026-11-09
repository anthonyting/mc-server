$serverUpdatesPath = Join-Path (Split-Path $PSScriptRoot -Parent) "ServerUpdates"
Import-Module (Join-Path $serverUpdatesPath "ServerUpdates.psd1") -Force

$global:fixtureBytes = [System.Text.Encoding]::UTF8.GetBytes("verified plugin fixture")
$global:fixtureSha256 = $null
$global:fixtureSha512 = $null
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$sha512 = [System.Security.Cryptography.SHA512]::Create()
try {
    $global:fixtureSha256 = [BitConverter]::ToString($sha256.ComputeHash($global:fixtureBytes)).Replace("-", "").ToLowerInvariant()
    $global:fixtureSha512 = [BitConverter]::ToString($sha512.ComputeHash($global:fixtureBytes)).Replace("-", "").ToLowerInvariant()
}
finally {
    $sha256.Dispose()
    $sha512.Dispose()
}

function Set-TestUpdateManifest {
    param (
        [string]$Directory,
        [hashtable]$Components
    )

    $manifestPath = Join-Path $Directory "server-update-manifest.json"
    [pscustomobject]@{
        schemaVersion = 1
        components = [pscustomobject]$Components
    } |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

Describe "Paper updater verification" {
    BeforeEach {
        $script:originalLocation = Get-Location
        $script:testDirectory = Join-Path $env:TEMP ("paper-update-test-" + [guid]::NewGuid().ToString("N"))
        New-Item -Path $script:testDirectory -ItemType Directory -Force | Out-Null
        Set-Location $script:testDirectory
        $global:paperDigest = $global:fixtureSha256
        $global:paperChannel = "STABLE"
        $global:paperUrl = "https://fill-data.papermc.io/paper.jar"
        $global:paperDownloadCount = 0

        Mock Invoke-RestMethod -ModuleName ServerUpdates {
            if ($Uri -eq "https://fill.papermc.io/v3/projects/paper") {
                return [pscustomobject]@{ versions = @{ "1.21" = @("1.21") } }
            }
            if ($Uri -eq "https://fill.papermc.io/v3/projects/paper/versions/1.21") {
                return [pscustomobject]@{ builds = @(1) }
            }
            if ($Uri -like "*/builds/latest") {
                return [pscustomobject]@{
                    id = 130
                    channel = $global:paperChannel
                    downloads = @{
                        "server:default" = @{
                            url = $global:paperUrl
                            checksums = @{ sha256 = $global:paperDigest }
                        }
                    }
                }
            }
            throw "Unexpected metadata URL: $Uri"
        }
        Mock Invoke-WebRequest -ModuleName ServerUpdates {
            $global:paperDownloadCount++
            [System.IO.File]::WriteAllBytes($OutFile, $global:fixtureBytes)
        }
    }

    AfterEach {
        Set-Location $script:originalLocation
        Remove-Item -LiteralPath $script:testDirectory -Recurse -Force
    }

    It "installs Paper after the downloaded file matches the published SHA-256" {
        Update-Paper -versionGroup "1.21"

        (Get-FileHash -Path "paper.jar" -Algorithm SHA256).Hash | Should Be $global:fixtureSha256
        $manifest = Get-Content -Path "server-update-manifest.json" -Raw | ConvertFrom-Json
        $manifest.components.Paper | Should Be "1.21+build.130"
    }

    It "skips the Paper download when the manifest version matches and paper.jar exists" {
        Set-TestUpdateManifest -Directory $script:testDirectory -Components @{ Paper = "1.21+build.130" }
        Set-Content -Path "paper.jar" -Value "already-installed"

        Update-Paper -versionGroup "1.21"

        $global:paperDownloadCount | Should Be 0
    }

    It "preserves the installed JAR when the downloaded file has the wrong hash" {
        Set-Content -Path "paper.jar" -Value "existing-paper"
        $global:paperDigest = "0" * 64

        { Update-Paper -versionGroup "1.21" } | Should Throw

        (Get-Content -Path "paper.jar" -Raw).Trim() | Should Be "existing-paper"
    }

    It "refuses builds without a valid checksum or stable channel" {
        $global:paperDigest = "invalid"
        { Update-Paper -versionGroup "1.21" } | Should Throw

        $global:paperDigest = $global:fixtureSha256
        $global:paperChannel = "EXPERIMENTAL"
        { Update-Paper -versionGroup "1.21" } | Should Throw
        (Test-Path "paper.jar") | Should Be $false
    }

    It "refuses download URLs outside Paper's artifact host" {
        $global:paperUrl = "https://example.com/paper.jar"

        { Update-Paper -versionGroup "1.21" } | Should Throw

        (Test-Path "paper.jar") | Should Be $false
    }
}

Describe "EssentialsX updater verification" {
    BeforeEach {
        $script:originalLocation = Get-Location
        $script:testDirectory = Join-Path $env:TEMP ("essentialsx-update-test-" + [guid]::NewGuid().ToString("N"))
        New-Item -Path $script:testDirectory -ItemType Directory -Force | Out-Null
        Set-Location $script:testDirectory
        $global:essentialsSnapshotBaseVersion = "2.22.1-SNAPSHOT"
        $global:essentialsChatSnapshotBaseVersion = $global:essentialsSnapshotBaseVersion
        $global:essentialsSnapshotVersion = "2.22.1-20261103.163335-27"
        $global:essentialsChatSnapshotVersion = $global:essentialsSnapshotVersion
        $global:essentialsDigest = $global:fixtureSha256
        $global:downloadBytes = $global:fixtureBytes
        $global:essentialsDownloadCount = 0
        $global:requestedEssentialsUrls = @()

        Mock Invoke-RestMethod -ModuleName ServerUpdates {
            if ($Uri -like "https://repo.essentialsx.net/snapshots/net/essentialsx/*/*/*.jar.sha256") {
                return $global:essentialsDigest
            }
            if ($Uri -eq "https://repo.essentialsx.net/snapshots/net/essentialsx/EssentialsX/maven-metadata.xml") {
                return [pscustomobject]@{
                    metadata = [pscustomobject]@{
                        versioning = [pscustomobject]@{
                            latest = $global:essentialsSnapshotBaseVersion
                            versions = [pscustomobject]@{
                                version = @("2.22.0-SNAPSHOT", $global:essentialsSnapshotBaseVersion)
                            }
                        }
                    }
                }
            }
            if ($Uri -eq "https://repo.essentialsx.net/snapshots/net/essentialsx/EssentialsXChat/maven-metadata.xml") {
                return [pscustomobject]@{
                    metadata = [pscustomobject]@{
                        versioning = [pscustomobject]@{
                            latest = $global:essentialsChatSnapshotBaseVersion
                            versions = [pscustomobject]@{
                                version = @("2.22.0-SNAPSHOT", $global:essentialsChatSnapshotBaseVersion)
                            }
                        }
                    }
                }
            }
            if ($Uri -eq "https://repo.essentialsx.net/snapshots/net/essentialsx/EssentialsX/$($global:essentialsSnapshotBaseVersion)/maven-metadata.xml") {
                $version = $global:essentialsSnapshotVersion
            }
            elseif ($Uri -eq "https://repo.essentialsx.net/snapshots/net/essentialsx/EssentialsXChat/$($global:essentialsChatSnapshotBaseVersion)/maven-metadata.xml") {
                $version = $global:essentialsChatSnapshotVersion
            }
            else {
                throw "Unexpected metadata URL: $Uri"
            }

            return [pscustomobject]@{
                metadata = [pscustomobject]@{
                    versioning = [pscustomobject]@{
                        snapshotVersions = [pscustomobject]@{
                            snapshotVersion = @([pscustomobject]@{
                                extension = "jar"
                                value = $version
                            })
                        }
                    }
                }
            }
        }
        Mock Invoke-WebRequest -ModuleName ServerUpdates {
            $global:essentialsDownloadCount++
            $global:requestedEssentialsUrls += $Uri
            [System.IO.File]::WriteAllBytes($OutFile, $global:downloadBytes)
        }
    }

    AfterEach {
        Set-Location $script:originalLocation
        Remove-Item -LiteralPath $script:testDirectory -Recurse -Force
    }

    It "installs the Core and Chat snapshots after matching their Maven SHA-256 hashes" {
        Update-EssentialsX -versionGroup "1.21"

        (Get-FileHash -Path "plugins/EssentialsX.jar" -Algorithm SHA256).Hash | Should Be $global:fixtureSha256
        (Get-FileHash -Path "plugins/EssentialsXChat.jar" -Algorithm SHA256).Hash | Should Be $global:fixtureSha256
        ($global:requestedEssentialsUrls -contains "https://repo.essentialsx.net/snapshots/net/essentialsx/EssentialsX/2.22.1-SNAPSHOT/EssentialsX-2.22.1-20261103.163335-27.jar") | Should Be $true
        ($global:requestedEssentialsUrls -contains "https://repo.essentialsx.net/snapshots/net/essentialsx/EssentialsXChat/2.22.1-SNAPSHOT/EssentialsXChat-2.22.1-20261103.163335-27.jar") | Should Be $true
        $manifest = Get-Content -Path "server-update-manifest.json" -Raw | ConvertFrom-Json
        $manifest.components.EssentialsX | Should Be $global:essentialsSnapshotVersion
        $manifest.components.EssentialsXChat | Should Be $global:essentialsSnapshotVersion
    }

    It "uses the same EssentialsX snapshot for any configured Minecraft version group" {
        Update-EssentialsX -versionGroup "26.3"

        (Get-FileHash -Path "plugins/EssentialsX.jar" -Algorithm SHA256).Hash | Should Be $global:fixtureSha256
        (Get-FileHash -Path "plugins/EssentialsXChat.jar" -Algorithm SHA256).Hash | Should Be $global:fixtureSha256
    }

    It "resolves and installs the latest published snapshot version" {
        $global:essentialsSnapshotBaseVersion = "2.22.2-SNAPSHOT"
        $global:essentialsChatSnapshotBaseVersion = $global:essentialsSnapshotBaseVersion
        $global:essentialsSnapshotVersion = "2.22.2-20261108.120000-1"
        $global:essentialsChatSnapshotVersion = $global:essentialsSnapshotVersion

        Update-EssentialsX -versionGroup "26.3"

        $manifest = Get-Content -Path "server-update-manifest.json" -Raw | ConvertFrom-Json
        $manifest.components.EssentialsX | Should Be $global:essentialsSnapshotVersion
        $manifest.components.EssentialsXChat | Should Be $global:essentialsSnapshotVersion
        ($global:requestedEssentialsUrls -contains "https://repo.essentialsx.net/snapshots/net/essentialsx/EssentialsX/2.22.2-SNAPSHOT/EssentialsX-2.22.2-20261108.120000-1.jar") | Should Be $true
    }

    It "skips EssentialsX downloads only when both snapshot artifacts match the manifest" {
        New-Item -Path "plugins" -ItemType Directory | Out-Null
        Set-Content -Path "plugins/EssentialsX.jar" -Value "installed-core"
        Set-Content -Path "plugins/EssentialsXChat.jar" -Value "installed-chat"
        Set-TestUpdateManifest -Directory $script:testDirectory -Components @{
            EssentialsX = $global:essentialsSnapshotVersion
            EssentialsXChat = $global:essentialsSnapshotVersion
        }

        Update-EssentialsX -versionGroup "1.21"

        $global:essentialsDownloadCount | Should Be 0
    }

    It "downloads a newer snapshot when the manifest contains an older build" {
        New-Item -Path "plugins" -ItemType Directory | Out-Null
        Set-Content -Path "plugins/EssentialsX.jar" -Value "old-core"
        Set-Content -Path "plugins/EssentialsXChat.jar" -Value "old-chat"
        Set-TestUpdateManifest -Directory $script:testDirectory -Components @{
            EssentialsX = "2.22.1-20261102.120000-26"
            EssentialsXChat = "2.22.1-20261102.120000-26"
        }

        Update-EssentialsX -versionGroup "1.21"

        $global:essentialsDownloadCount | Should Be 2
        (Get-FileHash -Path "plugins/EssentialsX.jar" -Algorithm SHA256).Hash | Should Be $global:fixtureSha256
        (Get-FileHash -Path "plugins/EssentialsXChat.jar" -Algorithm SHA256).Hash | Should Be $global:fixtureSha256
    }

    It "downloads EssentialsX when one of the manifested artifacts is missing" {
        New-Item -Path "plugins" -ItemType Directory | Out-Null
        Set-Content -Path "plugins/EssentialsX.jar" -Value "installed-core"
        Set-TestUpdateManifest -Directory $script:testDirectory -Components @{
            EssentialsX = $global:essentialsSnapshotVersion
            EssentialsXChat = $global:essentialsSnapshotVersion
        }

        Update-EssentialsX -versionGroup "1.21"

        $global:essentialsDownloadCount | Should Be 2
    }

    It "preserves existing artifacts when either artifact fails hash verification" {
        New-Item -Path "plugins" -ItemType Directory | Out-Null
        Set-Content -Path "plugins/EssentialsX.jar" -Value "existing-core"
        Set-Content -Path "plugins/EssentialsXChat.jar" -Value "existing-chat"
        $global:essentialsDigest = "0" * 64

        { Update-EssentialsX -versionGroup "1.21" } | Should Throw

        (Get-Content -Path "plugins/EssentialsX.jar" -Raw).Trim() | Should Be "existing-core"
        (Get-Content -Path "plugins/EssentialsXChat.jar" -Raw).Trim() | Should Be "existing-chat"
    }

    It "requires valid SHA-256 snapshot metadata" {
        $global:essentialsDigest = "missing"
        { Update-EssentialsX -versionGroup "1.21" } | Should Throw

        (Test-Path "plugins/EssentialsX.jar") | Should Be $false
    }

    It "refuses to install Core and Chat snapshots from different builds" {
        $global:essentialsChatSnapshotVersion = "2.22.1-20261104.100000-28"

        { Update-EssentialsX -versionGroup "1.21" } | Should Throw

        $global:essentialsDownloadCount | Should Be 0
        (Test-Path "plugins/EssentialsX.jar") | Should Be $false
    }
}

Describe "LuckPerms updater verification" {
    BeforeEach {
        $script:originalLocation = Get-Location
        $script:testDirectory = Join-Path $env:TEMP ("luckperms-update-test-" + [guid]::NewGuid().ToString("N"))
        New-Item -Path $script:testDirectory -ItemType Directory -Force | Out-Null
        Set-Location $script:testDirectory
        $global:luckPermsDigest = $global:fixtureSha512
        $global:luckPermsUrl = "https://cdn.modrinth.com/data/Vebnzrzj/LuckPerms-Bukkit-5.5.71.jar"
        $global:requestedLuckPermsUrl = $null
        $global:luckPermsDownloadCount = 0

        Mock Invoke-RestMethod -ModuleName ServerUpdates {
            if ($Uri -like "https://api.modrinth.com/v2/project/luckperms/version*") {
                return @(
                    [pscustomobject]@{
                        version_number = "v5.5.53-bukkit"
                        version_type = "release"
                        date_published = "2024-01-01T00:00:00Z"
                        loaders = @("paper", "bukkit")
                        game_versions = @("1.21")
                        files = @([pscustomobject]@{
                            filename = "LuckPerms-Bukkit-5.5.53.jar"
                            hashes = [pscustomobject]@{ sha512 = $global:fixtureSha512 }
                            url = "https://cdn.modrinth.com/data/Vebnzrzj/LuckPerms-Bukkit-5.5.53.jar"
                        })
                    },
                    [pscustomobject]@{
                        version_number = "v5.5.71-bukkit"
                        version_type = "release"
                        date_published = "2025-01-01T00:00:00Z"
                        loaders = @("paper", "bukkit")
                        game_versions = @("1.21", "1.21.1")
                        files = @([pscustomobject]@{
                            filename = "LuckPerms-Bukkit-5.5.71.jar"
                            hashes = [pscustomobject]@{ sha512 = $global:luckPermsDigest }
                            url = $global:luckPermsUrl
                        })
                    },
                    [pscustomobject]@{
                        version_number = "v5.6.0-bukkit"
                        version_type = "beta"
                        date_published = "2025-02-01T00:00:00Z"
                        loaders = @("paper", "bukkit")
                        game_versions = @("1.21")
                        files = @([pscustomobject]@{
                            filename = "LuckPerms-Bukkit-5.6.0.jar"
                            hashes = [pscustomobject]@{ sha512 = $global:fixtureSha512 }
                            url = $global:luckPermsUrl
                        })
                    }
                )
            }
            throw "Unexpected metadata URL: $Uri"
        }
        Mock Invoke-WebRequest -ModuleName ServerUpdates {
            $global:luckPermsDownloadCount++
            $global:requestedLuckPermsUrl = $Uri
            [System.IO.File]::WriteAllBytes($OutFile, $global:fixtureBytes)
        }
    }

    AfterEach {
        Set-Location $script:originalLocation
        Remove-Item -LiteralPath $script:testDirectory -Recurse -Force
    }

    It "installs the newest stable compatible Paper release after SHA-512 verification" {
        Update-LuckPerms -versionGroup "1.21"

        (Get-FileHash -Path "plugins/LuckPerms.jar" -Algorithm SHA512).Hash | Should Be $global:fixtureSha512
        $global:requestedLuckPermsUrl | Should Be $global:luckPermsUrl
        $manifest = Get-Content -Path "server-update-manifest.json" -Raw | ConvertFrom-Json
        $manifest.components.LuckPerms | Should Be "v5.5.71-bukkit"
    }

    It "skips the LuckPerms download when the manifest version matches and its JAR exists" {
        New-Item -Path "plugins" -ItemType Directory | Out-Null
        Set-Content -Path "plugins/LuckPerms.jar" -Value "installed-luckperms"
        Set-TestUpdateManifest -Directory $script:testDirectory -Components @{
            LuckPerms = "v5.5.71-bukkit"
        }

        Update-LuckPerms -versionGroup "1.21"

        $global:luckPermsDownloadCount | Should Be 0
    }

    It "preserves the installed JAR when the downloaded file has the wrong hash" {
        New-Item -Path "plugins" -ItemType Directory | Out-Null
        Set-Content -Path "plugins/LuckPerms.jar" -Value "existing-luckperms"
        $global:luckPermsDigest = "0" * 128

        { Update-LuckPerms -versionGroup "1.21" } | Should Throw

        (Get-Content -Path "plugins/LuckPerms.jar" -Raw).Trim() | Should Be "existing-luckperms"
    }

    It "requires valid SHA-512 metadata and a Modrinth CDN download URL" {
        $global:luckPermsDigest = "invalid"
        { Update-LuckPerms -versionGroup "1.21" } | Should Throw

        $global:luckPermsDigest = $global:fixtureSha512
        $global:luckPermsUrl = "https://example.com/LuckPerms.jar"
        { Update-LuckPerms -versionGroup "1.21" } | Should Throw

        (Test-Path "plugins/LuckPerms.jar") | Should Be $false
    }
}

Describe "Vault updater verification" {
    BeforeEach {
        $script:originalLocation = Get-Location
        $script:testDirectory = Join-Path $env:TEMP ("vault-update-test-" + [guid]::NewGuid().ToString("N"))
        New-Item -Path $script:testDirectory -ItemType Directory -Force | Out-Null
        Set-Location $script:testDirectory
        $global:vaultDigest = $global:fixtureSha512
        $global:vaultUrl = "https://cdn.modrinth.com/data/ayRaM8J7/VaultUnlocked-2.20.3.jar"
        $global:vaultDownloadCount = 0

        Mock Invoke-RestMethod -ModuleName ServerUpdates {
            if ($Uri -like "https://api.modrinth.com/v2/project/vaultunlocked/version*") {
                return @(
                    [pscustomobject]@{
                        version_number = "2.20.2"
                        version_type = "release"
                        date_published = "2026-06-22T23:05:51Z"
                        loaders = @("paper", "bukkit")
                        game_versions = @("1.21")
                        files = @([pscustomobject]@{
                            filename = "VaultUnlocked-2.20.2.jar"
                            hashes = [pscustomobject]@{ sha512 = $global:fixtureSha512 }
                            url = "https://cdn.modrinth.com/data/ayRaM8J7/VaultUnlocked-2.20.2.jar"
                        })
                    },
                    [pscustomobject]@{
                        version_number = "2.20.3"
                        version_type = "release"
                        date_published = "2026-09-16T22:55:14Z"
                        loaders = @("paper", "bukkit", "purpur")
                        game_versions = @("1.21", "1.21.1")
                        files = @([pscustomobject]@{
                            filename = "VaultUnlocked-2.20.3.jar"
                            hashes = [pscustomobject]@{ sha512 = $global:vaultDigest }
                            url = $global:vaultUrl
                        })
                    },
                    [pscustomobject]@{
                        version_number = "2.21.0"
                        version_type = "beta"
                        date_published = "2026-10-01T00:00:00Z"
                        loaders = @("paper")
                        game_versions = @("1.21")
                        files = @([pscustomobject]@{
                            filename = "VaultUnlocked-2.21.0.jar"
                            hashes = [pscustomobject]@{ sha512 = $global:fixtureSha512 }
                            url = $global:vaultUrl
                        })
                    }
                )
            }
            throw "Unexpected metadata URL: $Uri"
        }
        Mock Invoke-WebRequest -ModuleName ServerUpdates {
            $global:vaultDownloadCount++
            [System.IO.File]::WriteAllBytes($OutFile, $global:fixtureBytes)
        }
    }

    AfterEach {
        Set-Location $script:originalLocation
        Remove-Item -LiteralPath $script:testDirectory -Recurse -Force
    }

    It "installs the newest stable compatible Vault release after SHA-512 verification" {
        Update-Vault -versionGroup "1.21"

        (Get-FileHash -Path "plugins/Vault.jar" -Algorithm SHA512).Hash | Should Be $global:fixtureSha512
        $global:vaultDownloadCount | Should Be 1
        $manifest = Get-Content -Path "server-update-manifest.json" -Raw | ConvertFrom-Json
        $manifest.components.Vault | Should Be "2.20.3"
    }

    It "skips downloads when the manifest version matches and Vault.jar exists" {
        New-Item -Path "plugins" -ItemType Directory | Out-Null
        Set-Content -Path "plugins/Vault.jar" -Value "installed-vault"
        Set-TestUpdateManifest -Directory $script:testDirectory -Components @{ Vault = "2.20.3" }

        Update-Vault -versionGroup "1.21"

        $global:vaultDownloadCount | Should Be 0
    }

    It "preserves the installed JAR when Vault checksum verification fails" {
        New-Item -Path "plugins" -ItemType Directory | Out-Null
        Set-Content -Path "plugins/Vault.jar" -Value "existing-vault"
        $global:vaultDigest = "0" * 128

        { Update-Vault -versionGroup "1.21" } | Should Throw

        (Get-Content -Path "plugins/Vault.jar" -Raw).Trim() | Should Be "existing-vault"
    }

    It "rejects Vault downloads outside Modrinth's CDN" {
        $global:vaultUrl = "https://example.com/VaultUnlocked-2.20.3.jar"

        { Update-Vault -versionGroup "1.21" } | Should Throw

        (Test-Path "plugins/Vault.jar") | Should Be $false
    }
}

Describe "PersonalPlugins updater verification" {
    BeforeEach {
        $script:originalLocation = Get-Location
        $script:testDirectory = Join-Path $env:TEMP ("personalplugins-update-test-" + [guid]::NewGuid().ToString("N"))
        New-Item -Path $script:testDirectory -ItemType Directory -Force | Out-Null
        Set-Location $script:testDirectory
        $global:personalPluginsDigest = $global:fixtureSha256
        $global:personalPluginsJarUrl = "https://github.com/anthonyting/personal-plugins/releases/download/security-test/PersonalPlugins.jar"
        $global:personalPluginsChecksumUrl = "https://github.com/anthonyting/personal-plugins/releases/download/security-test/PersonalPlugins.jar.sha256"
        $global:personalPluginsDownloadBytes = $global:fixtureBytes
        $global:personalPluginsTag = "v1.2.3"
        $global:personalPluginsDownloadCount = 0

        Mock Invoke-RestMethod -ModuleName ServerUpdates {
            if ($Uri -eq "https://api.github.com/repos/anthonyting/personal-plugins/releases/latest") {
                return [pscustomobject]@{
                    draft = $false
                    prerelease = $false
                    tag_name = $global:personalPluginsTag
                    assets = @(
                        [pscustomobject]@{
                            name = "PersonalPlugins.jar"
                            browser_download_url = $global:personalPluginsJarUrl
                        },
                        [pscustomobject]@{
                            name = "PersonalPlugins.jar.sha256"
                            browser_download_url = $global:personalPluginsChecksumUrl
                        }
                    )
                }
            }
            throw "Unexpected metadata URL: $Uri"
        }
        Mock Invoke-WebRequest -ModuleName ServerUpdates {
            $global:personalPluginsDownloadCount++
            if ($Uri -eq $global:personalPluginsChecksumUrl) {
                Set-Content -Path $OutFile -Value $global:personalPluginsDigest -NoNewline
                return
            }
            if ($Uri -eq $global:personalPluginsJarUrl) {
                [System.IO.File]::WriteAllBytes($OutFile, $global:personalPluginsDownloadBytes)
                return
            }
            throw "Unexpected download URL: $Uri"
        }
    }

    AfterEach {
        Set-Location $script:originalLocation
        Remove-Item -LiteralPath $script:testDirectory -Recurse -Force
    }

    It "installs the latest release after matching its SHA-256 checksum" {
        Update-PersonalPlugins

        (Get-FileHash -Path "plugins/PersonalPlugins.jar" -Algorithm SHA256).Hash | Should Be $global:fixtureSha256
        $global:personalPluginsDownloadCount | Should Be 2
    }

    It "skips downloads when the installed version matches the latest release" {
        $pluginsPath = Join-Path $script:testDirectory "plugins"
        $jarPath = Join-Path $pluginsPath "PersonalPlugins.jar"
        New-Item -Path $pluginsPath -ItemType Directory | Out-Null
        Set-Content -Path $jarPath -Value "installed-personalplugins"
        $installedHash = (Get-FileHash -Path $jarPath -Algorithm SHA256).Hash
        Set-TestUpdateManifest -Directory $script:testDirectory -Components @{
            PersonalPlugins = "1.2.3"
        }

        Update-PersonalPlugins

        $global:personalPluginsDownloadCount | Should Be 0
        (Get-FileHash -Path $jarPath -Algorithm SHA256).Hash | Should Be $installedHash
    }

    It "downloads the latest release when the installed version is older" {
        $pluginsPath = Join-Path $script:testDirectory "plugins"
        $jarPath = Join-Path $pluginsPath "PersonalPlugins.jar"
        New-Item -Path $pluginsPath -ItemType Directory | Out-Null
        Set-Content -Path $jarPath -Value "old-personalplugins"
        Set-TestUpdateManifest -Directory $script:testDirectory -Components @{
            PersonalPlugins = "1.2.2"
        }

        Update-PersonalPlugins

        $global:personalPluginsDownloadCount | Should Be 2
        (Get-FileHash -Path $jarPath -Algorithm SHA256).Hash | Should Be $global:fixtureSha256
    }

    It "preserves the installed JAR when the checksum does not match" {
        New-Item -Path "plugins" -ItemType Directory | Out-Null
        Set-Content -Path "plugins/PersonalPlugins.jar" -Value "existing-plugin"
        $global:personalPluginsDigest = "0" * 64

        { Update-PersonalPlugins } | Should Throw

        (Get-Content -Path "plugins/PersonalPlugins.jar" -Raw).Trim() | Should Be "existing-plugin"
    }

    It "requires a valid checksum and GitHub release asset URLs" {
        $global:personalPluginsDigest = "invalid"
        { Update-PersonalPlugins } | Should Throw

        $global:personalPluginsDigest = $global:fixtureSha256
        $global:personalPluginsJarUrl = "https://example.com/PersonalPlugins.jar"
        { Update-PersonalPlugins } | Should Throw

        (Test-Path "plugins/PersonalPlugins.jar") | Should Be $false
    }

    It "rejects a malformed update manifest" {
        Set-Content -Path "server-update-manifest.json" -Value "{"

        { Update-PersonalPlugins } | Should Throw

        $global:personalPluginsDownloadCount | Should Be 0
    }
}

Describe "Plugin metrics configuration" {
    BeforeEach {
        $script:originalLocation = Get-Location
        $script:testDirectory = Join-Path $env:TEMP ("plugin-metrics-test-" + [guid]::NewGuid().ToString("N"))
        New-Item -Path $script:testDirectory -ItemType Directory -Force | Out-Null
        Set-Location $script:testDirectory
    }

    AfterEach {
        Set-Location $script:originalLocation
        Remove-Item -LiteralPath $script:testDirectory -Recurse -Force
    }

    It "creates bStats and FastStats opt-out configs" {
        Disable-PluginMetrics

        Get-Content -Path "plugins/bStats/config.yml" -Raw | Should Match '(?m)^enabled: false\s*$'
        Get-Content -Path "plugins/faststats/config.properties" -Raw | Should Match '(?m)^enabled=false\s*$'
    }

    It "disables metrics without overwriting existing plugin settings" {
        New-Item -Path "plugins/bStats" -ItemType Directory -Force | Out-Null
        Set-Content -Path "plugins/bStats/config.yml" -Value @(
            "enabled:true"
            "serverUuid: preserve-this-value"
            "logSentData: true"
        )
        New-Item -Path "plugins/faststats" -ItemType Directory -Force | Out-Null
        Set-Content -Path "plugins/faststats/config.properties" -Value @(
            "enabled=true"
            "serverId=preserve-this-value"
            "submitAdditionalMetrics=true"
        )

        Disable-PluginMetrics

        $bStatsContent = Get-Content -Path "plugins/bStats/config.yml" -Raw
        $bStatsContent | Should Match '(?m)^enabled: false$'
        $bStatsContent | Should Match '(?m)^serverUuid:\s*preserve-this-value\s*$'
        $bStatsContent | Should Match '(?m)^logSentData:\s*true\s*$'
        $fastStatsContent = Get-Content -Path "plugins/faststats/config.properties" -Raw
        $fastStatsContent | Should Match '(?m)^enabled=false\s*$'
        $fastStatsContent | Should Match '(?m)^serverId=preserve-this-value\s*$'
        $fastStatsContent | Should Match '(?m)^submitAdditionalMetrics=true\s*$'
    }

    It "repairs bStats values that lack YAML-required spacing" {
        New-Item -Path "plugins/bStats" -ItemType Directory -Force | Out-Null
        Set-Content -Path "plugins/bStats/config.yml" -Value "enabled:false"

        Disable-PluginMetrics

        Get-Content -Path "plugins/bStats/config.yml" -Raw | Should Match '(?m)^enabled: false\s*$'
    }
}
