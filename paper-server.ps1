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
    param (
        $versionGroup
    )

    $ProgressPreference = 'SilentlyContinue'

    $versionGroupURL = "https://api.papermc.io/v2/projects/paper/version_group/$versionGroup"

    # Write-Host "Getting version group info for $versionGroup..."
    $versionGroupInfo = Invoke-RestMethod $versionGroupURL
    $highestVersion = (([version[]] $versionGroupInfo.versions) | Measure-Object -Maximum).Maximum

    # Write-Host "Getting build info for version $highestVersion.."
    $buildsUrl = "https://api.papermc.io/v2/projects/paper/versions/$highestVersion"
    $builds = Invoke-RestMethod $buildsUrl
    $highestBuild = ($builds.builds | Measure-Object -Maximum).Maximum

    Write-Host "Downloading paper build $highestBuild for version $highestVersion..."
    $downloadURL = "https://api.papermc.io/v2/projects/paper/versions/$highestVersion/builds/$highestBuild/downloads/paper-$highestVersion-$highestBuild.jar"
    New-Item -Path "." -Name "downloading" -ItemType "directory" -Force > $null

    Invoke-WebRequest $downloadURL -Outfile "./downloading/paper_downloading"
	Move-Item -Path "./downloading/paper_downloading" -Destination "paper.jar" -Force
}

function Update-Spigot {
    # Get BuildTools.jar if it doesn't exist
    if (!(Test-Path "BuildTools.jar")) {
        Write-Host "Downloading BuildTools.jar..."
        Invoke-WebRequest "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" -OutFile "BuildTools.jar"
    }

    # Run BuildTools.jar if spigot.jar doesn't exist

    if (!(Test-Path "spigot.jar")) {
        Write-Host "Running BuildTools.jar..."
        & "java" -jar BuildTools.jar
        # Move spigot.jar to root
        Move-Item -Path "spigot-*.jar" -Destination "spigot.jar" -Force
    }
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
        $windowTitle,
        $versionGroup,
        $debug
    )

    $Host.UI.RawUI.WindowTitle = $windowTitle + " - Updating"
    if ($debug) {
        Write-Host "Debug mode: using Spigot instead of Paper"
        Update-Spigot
    } else {
        Update-Paper $versionGroup
    }
    Update-Plugin -baseURL "https://ci.lucko.me/view/LuckPerms/job/LuckPerms" -pluginName "LuckPerms"
    Update-Plugin -baseURL "https://ci.ender.zone/job/EssentialsX" -pluginName "EssentialsX"
    Update-Plugin -baseURL "https://ci.ender.zone/job/EssentialsX" -pluginName "EssentialsXChat"
    $Host.UI.RawUI.WindowTitle = $windowTitle
}

function Start-Server {
    param (
        $windowTitle,
        $versionGroup,
        $java,
        $memory,
        $debug
    )

    while($true) {

        $softwareJar = if ($debug) {
            "spigot.jar"
        } else {
            "paper.jar"
        }

        $javaArgs = "-Xms$memory -Xmx$memory -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar $softwareJar nogui"

        if ($debug) {
            Write-Host "Starting server in debug mode..."
            $javaArgs = " -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005 -DIReallyKnowWhatIAmDoingISwear -XX:+AllowEnhancedClassRedefinition -XX:HotswapAgent=fatjar " + $javaArgs
        }

        & $java $javaArgs.split(" ")

        if ($LASTEXITCODE -eq 0) {
            $defaultAction = 'U'
        } else {
            Write-Host "Server exited with exit code: $LASTEXITCODE"
            $defaultAction = 'E'
        }

        $initialAction = Get-Performed-Action -delay 8 -default $defaultAction
        Write-Host $initialAction
        if ($initialAction -eq 'U') {
            Update-All $windowTitle $versionGroup $debug
        } elseif ($initialAction -eq 'E') {
            if ($defaultAction -eq 'E') {
                Read-Host -Prompt "Error detected, press enter to exit"
            }
            return
        }
    }
}

function Main {
    $windowTitle = "PaperServer"
    $Host.UI.RawUI.WindowTitle = $windowTitle

    $settingsPath = "./settings.json"
    if (-not(Test-Path -Path $settingsPath -PathType Leaf)) {
        Copy-Item -Path "./settings.default.json" -Destination $settingsPath
    }

    $settingsText = Get-Content -Path $settingsPath
    
    try {
        $settings = $settingsText | ConvertFrom-Json
        [version] $settings.version | Out-Null
    } catch {
        Write-Host $_.Exception.Message
        return
    }

    $initialAction = Get-Performed-Action -delay 2 -default 'U'
    if ($initialAction -eq 'U') {
        $Host.UI.RawUI.WindowTitle = $windowTitle + " - Updating"
        Update-All $windowTitle $settings.version $settings.debug
    } elseif ($initialAction -eq 'E') {
        return
    }

    Start-Server $windowTitle $settings.version $settings.java $settings.memory $settings.debug
}

Main
