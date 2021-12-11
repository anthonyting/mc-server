function Get-Performed-Action {
    param (
        $delay,
        $default
    )

    switch($default) {
        'S' {
            $choices = "(S/u/e)"
            break
        }
        'U' {
            $choices = "(s/U/e)"
            break
        }
        'E' {
            $choices = "(s/u/E)"
            break
        }
        default {
            $choices = "(S/u/e)"
            $default = 'S'
        }
    }

    $seconds = 0
    $keyPressed = $false
    $activity = "Start, Update, or Exit? $delay seconds to answer $choices"
    while($seconds -lt ($delay + 1)) {
        if ([Console]::KeyAvailable) {
            $keyPressed = $true
            break   
        }
        Write-Progress -Activity $activity -SecondsRemaining ($delay - $seconds)
        Start-Sleep -Seconds 1
        $seconds += 1
    }
    Write-Progress -Activity $activity -Completed

    if ($keyPressed) {
        $key = [Console]::ReadKey("NoEcho").Key
        if ($key -eq 'S' -or $key -eq 'U' -or $key -eq 'E') {
            Write-Output $key
            return
        }
    }
    Write-Output $default
    return
}

function Update-Paper {
    $ProgressPreference = 'SilentlyContinue'

    $versionGroup = "1.18"
    $versionGroupURL = "https://papermc.io/api/v2/projects/paper/version_group/$versionGroup"

    # Write-Host "Getting version group info for $versionGroup..."
    $versionGroupInfo = Invoke-RestMethod $versionGroupURL
    $highestVersion = (([version[]] $versionGroupInfo.versions) | Measure-Object -Maximum).Maximum

    # Write-Host "Getting build info for version $highestVersion.."
    $buildsUrl = "https://papermc.io/api/v2/projects/paper/versions/$highestVersion"
    $builds = Invoke-RestMethod $buildsUrl
    $highestBuild = ($builds.builds | Measure-Object -Maximum).Maximum

    Write-Host "Downloading paper build $highestBuild for version $highestVersion..."
    $downloadURL = "https://papermc.io/api/v2/projects/paper/versions/$highestVersion/builds/$highestBuild/downloads/paper-$highestVersion-$highestBuild.jar"
    New-Item -Path "." -Name "downloading" -ItemType "directory" -Force > $null

    Invoke-WebRequest $downloadURL -Outfile "./downloading/paper_downloading"
	Move-Item -Path "./downloading/paper_downloading" -Destination "paper.jar" -Force
}

function Update-Plugin {
    param (
        $baseURL,
        $pluginName
    )

    $requestObject = Invoke-RestMethod "$baseURL/lastSuccessfulBuild/api/json"
    $relPath = $null
    foreach ($artifact in $requestObject.artifacts) {
        if ($artifact.displayPath.StartsWith("$pluginName-")) {
            $relPath = $artifact.relativePath
            break
        }
    }
    if ($null -eq $relPath) {
        Write-Host "Error: $pluginName not found at $baseURL. Skipping..."
        return
    }

    $downloadURL = "$baseURL/lastSuccessfulBuild/artifact/$relPath"

    $ProgressPreference = 'SilentlyContinue'
    Write-Host "Downloading from $downloadURL..."
    New-Item -Path "." -Name "downloading" -ItemType "directory" -Force > $null
    Invoke-WebRequest $downloadURL -OutFile (-join("./downloading/", $pluginName, "_downloading"))
    New-Item -Path "." -Name "plugins" -ItemType "directory" -Force > $null
    Move-Item -Path (-join("./downloading/", $pluginName, "_downloading")) -Destination "./plugins/$pluginName.jar" -Force
}

function Update-All {
    param (
        $windowTitle
    )

    $Host.UI.RawUI.WindowTitle = $windowTitle + " - Updating"
    Update-Paper
    Update-Plugin -baseURL "https://ci.lucko.me/view/LuckPerms/job/LuckPerms" -pluginName "LuckPerms"
    Update-Plugin -baseURL "https://ci.ender.zone/job/EssentialsX" -pluginName "EssentialsX"
    Update-Plugin -baseURL "https://ci.ender.zone/job/EssentialsX" -pluginName "EssentialsXChat"
    $Host.UI.RawUI.WindowTitle = $windowTitle
}

function Start-Server {
    param (
        $windowTitle
    )

    $java = "C:\Program Files\Eclipse Adoptium\jdk-17.0.1.12-hotspot\bin\java.exe"

    while($true) {
        & $java -Xms2048M -Xmx2048M -XX:+UseG1GC -XX:+UnlockExperimentalVMOptions -XX:MaxGCPauseMillis=100 -XX:+DisableExplicitGC -XX:TargetSurvivorRatio=90 -XX:G1NewSizePercent=50 -XX:G1MaxNewSizePercent=80 -XX:G1MixedGCLiveThresholdPercent=35 -XX:+AlwaysPreTouch -XX:+ParallelRefProcEnabled -jar paper.jar nogui
        $initialAction = Get-Performed-Action -delay 8 -default 'S'
        Write-Host $initialAction
        if ($initialAction -eq 'U') {
            Update-All $windowTitle
        } elseif ($initialAction -eq 'E') {
            return
        }
    }
}

function Main {
    $windowTitle = "PaperServer"
    $Host.UI.RawUI.WindowTitle = $windowTitle

    $initialAction = Get-Performed-Action -delay 2 -default 'U'
    if ($initialAction -eq 'U') {
        $Host.UI.RawUI.WindowTitle = $windowTitle + " - Updating"
        Update-All $windowTitle
    } elseif ($initialAction -eq 'E') {
        return
    }
    Start-Server $windowTitle
}

Main
