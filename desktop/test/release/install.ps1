# Installs RetroHub silently from the RetroHub-Setup-*.exe in a folder, and returns RetroHub.exe once
# it's there (and, with -Version, once it's that version: an upgrade replaces the file in place).
# The installer can hand over to a second copy of itself and exit before the install is done, so
# this waits for the result rather than for the installer.
function Install-RetroHub([string] $Folder, [string] $Version) {
    $setup = Get-Item "$Folder\RetroHub-Setup-*.exe"
    Start-Process -FilePath $setup.FullName -ArgumentList '/S' -Wait
    # Windows version numbers have no "-preview.1": compare 1.7.0 with 1.7.0.
    $wanted = if ($Version) { ($Version -split '-')[0] } else { $null }
    $places = "$env:LOCALAPPDATA\Programs", $env:ProgramFiles, ${env:ProgramFiles(x86)}
    for ($i = 0; $i -lt 120; $i++) {
        $app = Get-ChildItem $places -Recurse -Depth 3 -Filter RetroHub.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        $found = if ($app) { $app.VersionInfo.ProductVersion } else { $null }
        if ($app -and (-not $wanted -or $found -like "$wanted*")) {
            Start-Sleep -Seconds 2   # let the installer finish writing
            return $app
        }
        if ($i % 15 -eq 0) { Write-Host "waiting for RetroHub.exe$(if ($wanted) { " $wanted" }): found $(if ($app) { "$($app.FullName), version $found" } else { 'nothing yet' })" }
        Start-Sleep -Seconds 1
    }
    Write-Host 'Uninstall entries for RetroHub:'
    Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*RetroHub*' } | Format-List DisplayName, DisplayVersion, InstallLocation | Out-String | Write-Host
    throw "RetroHub.exe not found after installing $($setup.Name)"
}
