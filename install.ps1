#!/usr/bin/env powershell

#Requires -RunAsAdministrator

param (
    [ValidateLength(2, 15)][string]$ComputerName = "POLYHACK-" + "$(-join ((65..90) | Get-Random -Count 5 | % {[char]$_}))", 
    [string]$MainMirror = "http://mirrors.kernel.org/sourceware/cygwin", 
    [string]$PortMirror = "ftp://ftp.cygwinports.org/pub/cygwinports", 
    [string]$PortKey = "http://cygwinports.org/ports.gpg", 
    [string]$InstallationDirectory = "$Env:UserProfile", 
    [int]$Stage = 0
)

# Utility Functions

function Append-Idempotent {

    # the delimiter is expected to be just 1 character
    param (
        [string]$InputString, 
        [string]$OriginalString, 
        [string]$Delimiter = '', 
        [bool]$CaseSensitive = $false
    )

    if ($CaseSensitive -and ("$OriginalString" -cnotlike "*${InputString}*")) {

        "$OriginalString".TrimEnd("$Delimiter") + "$Delimiter" + "$InputString".TrimStart("$Delimiter")

    } elseif (! $CaseSensitive -and ("$OriginalString" -inotlike "*${InputString}*")) {
        
        "$OriginalString".TrimEnd("$Delimiter") + "$Delimiter" + "$InputString".TrimStart("$Delimiter")

    } else {

        "$OriginalString"
    
    }

}

function ScheduleRebootTask {

    param (
        [string]$Name,
        [int]$Stage
    )
    
    # ScheduledTasks action syntax is similar to the syntax used for run.exe commands
    # For some reason the normal -File option of powershell.exe doesn't work in run.exe and hence also doesn't work in the task scheduler
    # So we use an alternative syntax to execute the script
    $Action = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory "$($PWD.Path)" -Argument (
        '-NoLogo -NoProfile -ExecutionPolicy Unrestricted -NoExit ' + 
        "`"& '${PSCommandPath}' -MainMirror '${MainMirror}' -PortMirror '${PortMirror}' -PortKey '${PortKey}' -InstallationDirectory '${InstallationDirectory}' -Stage ${Stage}`""
    )

    # Trigger the script only when the current user has logged on
    $Trigger = New-ScheduledTaskTrigger -AtLogOn -User "$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    
    # -RunLevel Highest will run the job with administrator privileges
    $Principal = New-ScheduledTaskPrincipal `
        -UserId "$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" `
        -LogonType Interactive `
        -RunLevel Highest
    
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -RunOnlyIfNetworkAvailable `
        -DontStopOnIdleEnd `
        -StartWhenAvailable

    Register-ScheduledTask `
        -TaskName "$Name$Stage" `
        -TaskPath "\" `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Force

    Restart-Computer

}

# Bootstrap the computer!

if ($Stage -eq 0) {

    Write-Host "Before you continue the installation, you should RAID with Storage Spaces, switch on NTFS compression, and encrypt with Bitlocker on your drive(s)."
    Read-Host "Enter to continue"
    
    # Copy the transparent.ico icon
    Copy-Item "${PSScriptRoot}\data\transparent.ico" "${Env:SYSTEMROOT}\system32"
    Unblock-File -Path "${Env:SYSTEMROOT}\system32\transparent.ico"

    # Install Powershell Help Files (we can use -?)
    Update-Help -Force

    # Import the registry file
    Start-Process -FilePath "$Env:SystemRoot\system32\reg.exe" -Wait -Verb RunAs -ArgumentList "IMPORT `"${PSScriptRoot}\windows_registry.reg`""
    
    # Enabling Optional Windows Features, these may need a restart

    # Enable Telnet
    Get-WindowsOptionalFeature -Online -FeatureName TelnetClient | Enable-WindowsOptionalFeature -Online -All -NoRestart >$null
    # Enable .NET Framework 3.5, 3.0 and 2.0
    # This is required for some legacy applications and CUDA applications
    Get-WindowsOptionalFeature -Online -FeatureName NetFx3 | Enable-WindowsOptionalFeature -Online -All -NoRestart >$null
    # Enable Windows Containers
    Get-WindowsOptionalFeature -Online -FeatureName Containers | Enable-WindowsOptionalFeature -Online -All -NoRestart >$null
    # Enable Hyper-V hypervisor, this will prevent Virtualbox from running concurrently
    # However Hyper-V can be disabled at boot for when you need to use virtualbox
    # This is needed for Docker on Windows to run
    Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V | Enable-WindowsOptionalFeature -Online -All -NoRestart >$null

    # Setup some Windows Environment Variables and Configuration
    
    # Allow Powershell scripts to be executable
    Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force
    
    # System variables
   
    # Make the `*.ps1` scripts executable without the `.ps1` extension
    # By default Windows will have set `.COM;.EXE;.BAT;.CMD` as path extensions
    [Environment]::SetEnvironmentVariable(
        "PATHEXT", 
        (Append-Idempotent ".PS1" "$Env:PATHEXT" ";" $False), 
        [System.EnvironmentVariableTarget]::Machine
    )
    [Environment]::SetEnvironmentVariable(
        "PATHEXT", 
        (Append-Idempotent ".PS1" "$Env:PATHEXT" ";" $False), 
        [System.EnvironmentVariableTarget]::Process
    )
    CMD /C 'assoc .ps1=Microsoft.PowerShellScript.1' >$null
    CMD /C 'ftype Microsoft.PowerShellScript.1="%SystemRoot%\system32\WindowsPowerShell\v1.0\powershell.exe" "%1"' >$null
    
    # Make Windows Shortcuts `*.lnk` executable without the `.lnk` extension
    [Environment]::SetEnvironmentVariable(
        "PATHEXT", 
        (Append-Idempotent ".LNK" "$Env:PATHEXT" ";" $False), 
        [System.EnvironmentVariableTarget]::Machine
    )
    [Environment]::SetEnvironmentVariable(
        "PATHEXT", 
        (Append-Idempotent ".LNK" "$Env:PATHEXT" ";" $False), 
        [System.EnvironmentVariableTarget]::Process
    )

    # Directory to hold NTFS symlinks and Windows shortcuts to Windows executables installed in the local profile
    # This means ~/Users/AppData/Local/bin
    # The roaming profile should not be used for application installation because applications are architecture specific
    New-Item -ItemType Directory -Force -Path "${Env:LOCALAPPDATA}\bin" >$null

    # Directory to hold NTFS symlinks and Windows shortcuts to Windows executables installed globally
    # This means C:/ProgramData/bin
    # This can be used for applications we install ourselves and for native installers in Chocolatey
    # Native installers are those that are not "*.portable" installations
    New-Item -ItemType Directory -Force -Path "${Env:ALLUSERSPROFILE}\bin" >$null
    
    # User variables

    # Home environment variables
    [Environment]::SetEnvironmentVariable("HOME", $Env:UserProfile, [System.EnvironmentVariableTarget]::User)
    [Environment]::SetEnvironmentVariable("HOME", $Env:UserProfile, [System.EnvironmentVariableTarget]::Process)
    
    # Disable Cygwin warning about Unix file paths
    [Environment]::SetEnvironmentVariable("CYGWIN", "nodosfilewarning", [System.EnvironmentVariableTarget]::User)
    [Environment]::SetEnvironmentVariable("CYGWIN", "nodosfilewarning", [System.EnvironmentVariableTarget]::Process)
    
    # Setup firewall to accept pings for Domain and Private networks but not from Public networks
    Set-NetFirewallRule `
        -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" `
        -Enabled True `
        -Action "Allow" `
        -Profile "Domain,Private"`
        >$null
    Set-NetFirewallRule `
        -DisplayName "File and Printer Sharing (Echo Request - ICMPv6-In)" `
        -Enabled True `
        -Action "Allow" `
        -Profile "Domain,Private"`
        >$null

    # Setup firewall to accept connections from 55555 in Domain and Private networks
    Remove-NetFirewallRule -DisplayName "Polyhack - Private Development Port (TCP-In)" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "Polyhack - Private Development Port (UDP-In)" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "Polyhack - Private Development Port (TCP-In)" `
        -Direction Inbound `
        -EdgeTraversalPolicy Allow `
        -Protocol TCP `
        -LocalPort 55555 `
        -Action Allow `
        -Profile "Domain,Private" `
        -Enabled True `
        >$null
    New-NetFirewallRule `
        -DisplayName "Polyhack - Private Development Port (UDP-In)" `
        -Direction Inbound `
        -EdgeTraversalPolicy Allow `
        -Protocol UDP `
        -LocalPort 55555 `
        -Action Allow `
        -Profile "Domain,Private" `
        -Enabled True `
        >$null

    # Port 22 for Cygwin SSH
    Remove-NetFirewallRule -DisplayName "Polyhack - SSH (TCP-In)" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "Polyhack - SSH (TCP-In)" `
        -Direction Inbound `
        -EdgeTraversalPolicy Allow `
        -Protocol TCP `
        -LocalPort 22 `
        -Action Allow `
        -Profile "Domain,Private" `
        -Program "${InstallationDirectory}\cygwin64\usr\sbin\sshd.exe" `
        -Enabled True `
        >$null

    # Port 80 for HTTP, but blocked by default (switch it on when you need to)
    Remove-NetFirewallRule -DisplayName "Polyhack - HTTP (TCP-In)" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "Polyhack - HTTP (TCP-In)" `
        -Direction Inbound `
        -EdgeTraversalPolicy Allow `
        -Protocol TCP `
        -LocalPort 80 `
        -Action Block `
        -Enabled True `
        >$null

    # Remove useless profile folders
    Remove-Item "${Env:UserProfile}\Contacts" -Recurse -Force
    Remove-Item "${Env:UserProfile}\Favorites" -Recurse -Force
    Remove-Item "${Env:UserProfile}\Links" -Recurse -Force

    # Rename the computer to the new name just before a restart
    Rename-Computer -NewName "$ComputerName" -Force >$null 2>&1

    # Change power settings for the current plan
    
    # Power button hibernates the computer (Battery and Plugged In)
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 2
    powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 2

    # Lid close sleeps the computer (Battery and Plugged In)
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1
    powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1

    # Screen timing in seconds
    # Turn off screen in 10 minutes on battery
    # Turn off screen in 1 hr when plugged in
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE (10 * 60)
    powercfg -setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE (60 * 60)

    # Sleep timing in seconds
    # Sleep in 20 minutes on battery
    # Never sleep when plugged in 
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE (20 * 60)
    powercfg -setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0

    # Hibernate timing in seconds
    # After sleeping for 2 hrs on battery, go to hibernation
    # Never hibernate when plugged in
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE (120 * 60)
    powercfg -setacvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 0

    # Schedule the next stage of this script and reboot
    Unregister-ScheduledTask -TaskName "Dotfiles - 1" -Confirm:$false -ErrorAction SilentlyContinue
    ScheduleRebootTask -Name "Dotfiles - " -Stage 1

} elseif ($Stage -eq 1) {

    Unregister-ScheduledTask -TaskName "Dotfiles - 1" -Confirm:$false

    # Stop the Windows Native SSH Service due to Developer Tools
    Stop-Service -Name "SshBroker" -Force -Confirm:$false -ErrorAction SilentlyContinue
    # Disable both SSH service and the SSH proxy
    Set-Service -Name "SshProxy" -Status Stopped -StartupType Disabled -Confirm:$false -ErrorAction SilentlyContinue
    Set-Service -Name "SshBroker" -Status Stopped -StartupType Disabled -Confirm:$false -ErrorAction SilentlyContinue
    
    # Uninstall Useless Applications
    $AppsToBeUninstalled = @(
        'Microsoft.3DBuilder' 
        'Microsoft.WindowsFeedbackHub' 
        'Microsoft.MicrosoftOfficeHub' 
        'Microsoft.MicrosoftSolitaireCollection*'
        'Microsoft.BingFinance' 
        'Microsoft.BingNews' 
        'Microsoft.SkypeApp' 
        'Microsoft.BingSports' 
        'Microsoft.Office.Sway' 
        'Microsoft.XboxApp' 
        'Microsoft.MicrosoftStickyNotes' 
        'Microsoft.ConnectivityStore' 
        'Microsoft.CommsPhone' 
        'Microsoft.WindowsPhone' 
        'Microsoft.OneConnect' 
        'Microsoft.People' 
        'Microsoft.Appconnector' 
        'Microsoft.Getstarted' 
        'Microsoft.WindowsMaps' 
        'Microsoft.ZuneMusic' 
        'Microsoft.Freshpaint' 
        'Flipboard.Flipboard' 
        '9E2F88E3.Twitter' 
        'king.com.CandyCrushSodaSaga' 
        'Drawboard.DrawboardPDF' 
    )
    
    foreach ($App in $AppsToBeUninstalled) {
        Get-AppxPackage -AllUsers -Name "$App" | Remove-AppxPackage -Confirm:$false
        Get-AppxProvisionedPackage -Online | where DisplayName -EQ "$App" | Remove-AppxProvisionedPackage -Online
    }
    
    # For disabling OneDrive go to gpedit.msc and disable it here: 
    # Local Computer Policy\Computer Configuration\Administrative Templates\Windows Components\OneDrive
    
    # Setup Windows Package Management
    
    # Update Package Management
    Import-Module PackageManagement
    Import-Module PowerShellGet
    # Nuget is needed for PowerShellGet
    Install-PackageProvider -Name Nuget -Force
    # Updating PowerShellGet updates PackageManagement
    Install-Module -Name PowerShellGet -Force
    # Update PackageManagement Explicitly to be Sure
    Install-Module -Name PackageManagement -Force
    # Reimport PackageManagement and PowerShellGet to take advantage of the new commands
    Import-Module PackageManagement -Force
    Import-Module PowerShellGet -Force

    # Install Package Providers
    # There are 2 Chocolatey Providers, the ChocolateGet provider is more stable
    # PowerShellGet is also a package provider
    Install-PackageProvider -Name 'ChocolateyGet' -Force
    Install-PackageProvider -Name 'PowerShellGet' -Force
    
    # The ChocolateyGet bin path is "${Env:ChocolateyInstall}\bin"
    # It is automatically appended to the system PATH environment variable upon installation of the first package
    # The directory is populated for special packages, but won't necessarily be populated by native installers
    # The ChocolateyGet will also automatically install chocolatey package, making the choco commands available as well
    
    # Make PowerShellGet's source trusted
    Set-PackageSource -Name 'PSGallery' -ProviderName 'PowerShellGet' -Trusted -Force
    
    # Nuget doesn't register a package source by default
    Register-PackageSource -Name 'NuGet' -ProviderName 'NuGet' -Location 'https://www.nuget.org/api/v2' -Trusted -Force

    # Install extra Powershell modules
    Install-Module PSReadline -Force -SkipPublisherCheck

    # Acquire the Package Lists
    $WindowsPackages = (Get-Content "${PSScriptRoot}\windows_packages.txt" | Where-Object { 
        $_.trim() -ne '' -and $_.trim() -notmatch '^#' 
    })

    # Install the Windows Packages
    foreach ($Package in $WindowsPackages) {

        $Package = $Package -split ','
        $Name = $Package[0].trim()
        $Version = $Package[1].trim()
        $Provider = $Package[2].trim()
        
        # the fourth parameter is optional completely, there's no need to even have a comma
        if ($Package.Length -eq 4) {
            $AdditionalArguments = $Package[3].trim()
        } else {
            $AdditionalArguments = ''
        }

        $InstallCommand = "Install-Package -Name '$Name' "

        if ($Version -and $Version -ne '*') {
            $InstallCommand += "-RequiredVersion '$Version' "
        }

        if ($Provider) {
            $InstallCommand += "-ProviderName '$Provider' "
        }

        if ($AdditionalArguments) {

            # heredoc in powershell (must have no spaces before ending `'@`)
            $InstallCommand += "-AdditionalArguments @'
                --installargs `"$AdditionalArguments`"
'@ "

        }

        $InstallCommand += '-Force'
        
        Invoke-Expression "$InstallCommand"
        
    }
    
    # Windows packages requiring special instructions
    & "${PSScriptRoot}\windows_packages_special.ps1"

    # Setup Chrome App shortcuts
    # Chrome App shortcuts will be places in $LOCALAPPDATA/bin because the icons are supplied in the LOCALAPPDATA
    $ChromePath = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue).'(Default)'

    if ($ChromePath) {

        $WshShell = New-Object -ComObject WScript.Shell

        $ChromeApps = (Get-Content "${PSScriptRoot}\chrome_apps.txt" | Where-Object { 
            $_.trim() -ne '' -and $_.trim() -notmatch '^#' 
        })

        foreach ($App in $ChromeApps) {

            $App = $App -split ','
            $Name = $App[0].trim()
            $Url = [System.Uri]"$($App[1].trim())"

            try {

                New-Item -ItemType Directory -Force -Path "${Env:LOCALAPPDATA}\Google\Chrome\User Data\Default\Web Applications\$($Url.Host)\$($Url.Scheme)_80" >$null
                Copy-Item -Force "${PSScriptRoot}\data\${Name}.ico" "${Env:LOCALAPPDATA}\Google\Chrome\User Data\Default\Web Applications\$($Url.Host)\$($Url.Scheme)_80\${Name}.ico"
                Unblock-File -Path "${Env:LOCALAPPDATA}\Google\Chrome\User Data\Default\Web Applications\$($Url.Host)\$($Url.Scheme)_80\${Name}.ico"
                $Shortcut = $WshShell.CreateShortcut("${Env:LOCALAPPDATA}\bin\${Name}.lnk")
                $Shortcut.TargetPath = "$ChromePath"
                $Shortcut.Arguments = "--app=$($Url.OriginalString)"
                $Shortcut.WorkingDirectory = "$(Split-Path "$ChromePath" -Parent)"
                $ShortCut.IconLocation = "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Web Applications\$($Url.Host)\$($Url.Scheme)_80\${Name}.ico"
                $Shortcut.Save()

            } catch { 

                echo "Could not create Chrome App shortcut for ${Url.OriginalString} because ${_}"

            }

        }

    } else {

        echo "Could not find path to chrome.exe, therefore could not setup Chrome app shortcuts"

    }

    # Setup any NTFS symlinks required for natively and globally installed applications
    # These will be installed into $ALLUSERSPROFILE\bin
    # This is only required if the installation process did not add a launcher into $ChocolateyInstall\bin
    $GlobalSymlinkMapping = (Get-Content "${PSScriptRoot}\windows_global_symlink_mapping.txt" | Where-Object { 
        $_.trim() -ne '' -and $_.trim() -notmatch '^#' 
    })

    foreach ($Map in $GlobalSymlinkMapping) {

        $Map = $Map -split ','
        $Link = $Map[0].trim()
        $Target = $Map[1].trim()

        # expand MSDOS environment variables
        $Target = [System.Environment]::ExpandEnvironmentVariables("$Target")
        if (Test-Path "$Target" -PathType Leaf) {
            New-Item -ItemType SymbolicLink -Force -Path "${Env:ALLUSERSPROFILE}\bin\${Link}" -Value "$Target"
        }

    }

    # Setup any NTFS symlinks required for locally installed applications
    # These will be installed into $LOCALAPPDATA\bin
    $LocalSymlinkMapping = (Get-Content "${PSScriptRoot}\windows_local_symlink_mapping.txt" | Where-Object { 
        $_.trim() -ne '' -and $_.trim() -notmatch '^#' 
    })

    foreach ($Map in $LocalSymlinkMapping) {

        $Map = $Map -split ','
        $Link = $Map[0].trim()
        $Target = $Map[1].trim()

        # expand MSDOS environment variables
        $Target = [System.Environment]::ExpandEnvironmentVariables("$Target")
        if (Test-Path "$Target" -PathType Leaf) {
            New-Item -ItemType SymbolicLink -Force -Path "${Env:LOCALAPPDATA}\bin\${Link}" -Value "$Target"
        }

    }

    # Installing Cygwin Packages

    # Create the necessary directories

    New-Item -ItemType Directory -Force -Path "$InstallationDirectory\cygwin64" >$null
    New-Item -ItemType Directory -Force -Path "$InstallationDirectory\cygwin64\packages" >$null

    # Acquire Package Lists

    $MainPackages = (Get-Content "${PSScriptRoot}\cygwin_main_packages.txt" | Where-Object { 
        $_.trim() -ne '' -and $_.trim() -notmatch '^#' 
    }) -Join ','
    $PortPackages = (Get-Content "${PSScriptRoot}\cygwin_port_packages.txt" | Where-Object { 
        $_.trim() -ne '' -and $_.trim() -notmatch '^#' 
    }) -Join ','

    # Main Packages

    if ($MainPackages) {
        Start-Process -FilePath "${PSScriptRoot}\profile\bin\cygwin-setup-x86_64.exe" -Wait -Verb RunAs -ArgumentList `
            "--quiet-mode",
            "--download",
            "--local-install",
            "--no-shortcuts",
            "--no-startmenu",
            "--no-desktop",
            "--arch x86_64",
            "--upgrade-also",
            "--delete-orphans",
            "--root `"${InstallationDirectory}\cygwin64`"",
            "--local-package-dir `"${InstallationDirectory}\cygwin64\packages`"",
            "--site `"$MainMirror`"",
            "--packages `"$MainPackages`""
    }

    # Cygwin Port Packages

    if ($PortPackages) {
        Start-Process -FilePath "${PSScriptRoot}\profile\bin\cygwin-setup-x86_64.exe" -Wait -Verb RunAs -ArgumentList `
            "--quiet-mode",
            "--download",
            "--local-install",
            "--no-shortcuts",
            "--no-startmenu",
            "--no-desktop",
            "--arch x86_64",
            "--upgrade-also",
            "--delete-orphans",
            "--root `"${InstallationDirectory}\cygwin64`"",
            "--local-package-dir `"${InstallationDirectory}\cygwin64\packages`"",
            "--site `"$PortMirror`"",
            "--pubkey `"$PortKey`"",
            "--packages `"$PortPackages`""
    }

    # Schedule a final reboot to start the Cygwin setup process
    Unregister-ScheduledTask -TaskName "Dotfiles - 2" -Confirm:$false -ErrorAction SilentlyContinue
    ScheduleRebootTask -Name "Dotfiles - " -Stage 2

} elseif ($Stage -eq 2) {

    Unregister-ScheduledTask -TaskName "Dotfiles - 2" -Confirm:$false

    # Use Carbon's Grant-Privilege feature to give us the ability to create Windows symbolic links
    # Because I am an administrator user, this doesn't give me unelevated access to creating native symlinks.
    # I still need to elevate to be able to create a symlink. This is caused by UAC filtering, which filters out the privilege.
    # See the difference in `whoami /priv` running elevated vs non-elevated in Powershell.
    # However if UAC is disabled, then the administrator user can create symlinks without elevating.
    # If I was a non-administrator user, then I would have the ability to create symlinks without any more work.
    # See: http://superuser.com/q/839580
    Import-Module 'Carbon'
    Grant-Privilege -Identity "$Env:UserName" -Privilege SeCreateSymbolicLinkPrivilege
    
    echo "Finished deploying on Windows. Remember to run ${UserProfile}/bin/clean-path.ps1 after you have installed all manual Windows packages."

    # Add the primary Cygwin bin paths to PATH before launching install.sh directly from Powershell
    # This is because the PATH is not been completely configured for Cygwin before install.sh runs
    # This is only needed temporarily

    $Env:Path = (
        "${InstallationDirectory}\cygwin64\usr\bin;" + 
        "${InstallationDirectory}\cygwin64\usr\sbin;" + 
        "${InstallationDirectory}\cygwin64\bin;" + 
        "${InstallationDirectory}\cygwin64\sbin;" + 
        "${Env:Path}"
    )
    Start-Process -FilePath "$InstallationDirectory\cygwin64\bin\bash.exe" -Wait -Verb RunAs -ArgumentList "`"${PSScriptRoot}\install.sh`""

}