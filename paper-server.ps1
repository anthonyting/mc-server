function Get-Performed-Action {
    param (
        $delay,
        $default
    )

    switch ($default) {
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
    while ($seconds -lt ($delay + 1)) {
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

Import-Module (Join-Path $PSScriptRoot "ServerUpdates\ServerUpdates.psd1") -Force

function Start-Server {
    param (
        $windowTitle,
        $versionGroup,
        $java,
        $memory,
        $debug
    )

    while ($true) {
        Disable-PluginMetrics

        $softwareJar = if ($debug) {
            "spigot.jar"
        }
        else {
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
        }
        else {
            Write-Host "Server exited with exit code: $LASTEXITCODE"
            $defaultAction = 'E'
        }

        $initialAction = Get-Performed-Action -delay 8 -default $defaultAction
        Write-Host $initialAction
        if ($initialAction -eq 'U') {
            Update-All $windowTitle $versionGroup $debug
        }
        elseif ($initialAction -eq 'E') {
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
    }
    catch {
        Write-Host $_.Exception.Message
        return
    }

    $initialAction = Get-Performed-Action -delay 2 -default 'U'
    if ($initialAction -eq 'U') {
        $Host.UI.RawUI.WindowTitle = $windowTitle + " - Updating"
        Update-All $windowTitle $settings.version $settings.debug
    }
    elseif ($initialAction -eq 'E') {
        return
    }

    Start-Server $windowTitle $settings.version $settings.java $settings.memory $settings.debug
}

Main
