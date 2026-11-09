function Update-Spigot {
    # Get BuildTools.jar if it doesn't exist.
    if (!(Test-Path "BuildTools.jar")) {
        Write-Host "Downloading BuildTools.jar..."
        Invoke-UpdateHttpRequest -Request {
            Invoke-WebRequest `
                -Uri "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" `
                -OutFile "BuildTools.jar" `
                -ErrorAction Stop
        }
    }

    # Run BuildTools.jar if spigot.jar doesn't exist.
    if (!(Test-Path "spigot.jar")) {
        Write-Host "Running BuildTools.jar..."
        & "java" -jar BuildTools.jar
        Move-Item -Path "spigot-*.jar" -Destination "spigot.jar" -Force
    }
}
