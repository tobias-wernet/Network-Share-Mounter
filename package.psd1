@{
    Root = 'c:\Temp\Network Share Mounter\Network Share Mounter.ps1'
    OutputPath = 'c:\Temp\Network Share Mounter\out'
    Package = @{
        Enabled = $true
        Obfuscate = $false
        HideConsoleWindow = $true
        DotNetVersion = 'net4.8.1'
        FileVersion = '1.6.2.1'
        HighDPISupport = $true
        FileDescription = 'Network Share Mounter'
        ProductName = 'Network Share Mounter'
        ProductVersion = '1.6.2.1'
        Copyright = 'Tobias Wernet - Albert-Ludwigs-Universität Freiburg'
        RequireElevation = $false
        ApplicationIconPath = 'C:\temp\Logos\folder.ico'
        PackageType = 'Console'
        PowerShellVersion = 'Windows Powershell'
        RuntimeIdentifier = 'win-x64'
        Platform = 'x64'
        PowerShellArguments = ''
        DotNetSdk = '7.0'
        Host = 'Default'
        #Host = 'IronmanPowerShellWinFormsHost'
    }
    Bundle = @{
        Enabled = $true
        Modules = $true
        # IgnoredModules = @()
    }
}
        