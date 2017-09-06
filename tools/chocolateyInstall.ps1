﻿$ErrorActionPreference = 'Stop'; # stop on all errors

$toolsDir = Split-Path $MyInvocation.MyCommand.Definition
. $toolsDir\helpers.ps1

$packageName   = $env:ChocolateyPackageName
$url           = 'https://selenium-release.storage.googleapis.com/3.5/selenium-server-standalone-3.5.3.jar'
$checksum      = '3dd4cad1d343f9d1cb1302ef1b3cec98'
$checksumType  = 'md5'
$toolsLocation = Get-ToolsLocation
$seleniumDir   = "$toolsLocation\selenium"
$seleniumPath  = "$seleniumDir\selenium-server-standalone.jar"
$pp            = Get-SeleniumConfigDefaults
$name          = "Selenium$((Get-Culture).TextInfo.ToTitleCase($pp["role"]))"

if (!(Test-Path $seleniumDir)) {
  New-Item $seleniumDir -ItemType directory
}

if ($pp["log"] -ne $null -and $pp["log"] -ne '' -and !(Test-Path $pp["log"])) {
  New-Item -ItemType "file" -Path $pp["log"]
}

# https://chocolatey.org/docs/helpers-get-chocolatey-web-file
Get-ChocolateyWebFile $packageName $seleniumPath $url -checksum $checksum -checksumType $checksumType

$config = Get-SeleniumConfig($pp)
$configJson = ConvertTo-Json -Depth 99 $config
$configPath = "$seleniumDir\$($pp["role"])config.json"

if ($pp["role"] -ne 'standalone') {
   $configJson | Set-Content $configPath
}

Write-Debug "Selenium configuration: $configJson"

if ($pp["role"] -eq 'hub') {
  $options = "-role hub -hubConfig ""$configPath"""
} elseif ($pp["role"] -eq 'node' ) {
  $options = "-role node -nodeConfig ""$configPath"""
} else { # standalone
  $keys = $config.keys
  foreach ($key in $keys) {
    if ($key -eq 'debug') {
      if ($config[$key] -eq $true) { $options += "-$key " }
    } else {
      $options += "-$key "
      if ($config[$key] -is [String] -and $key -ne 'role') {
        $options += """"
        $options += $config[$key]
        $options += """"
      } else {
        $options += $config[$key]
      }
      $options += " "
    }
  }
}

$cmdParams = "$($pp["args"]) -jar ""$seleniumPath"" $options"
$cmd = "java $cmdParams"

Write-Debug "Selenium command: $cmd"

if ($pp["service"] -eq $true) {
  nssm install $name java
  nssm set $name AppDirectory $seleniumDir
  nssm set $name AppParameters $cmdParams
  if ($pp["autostart"] -eq $true) {
    nssm set $name Start SERVICE_AUTO_START
  }
  if ($pp["log"] -ne $null -and $pp["log"] -ne '') {
    nssm set $name AppStdout $pp["log"]
    nssm set $name AppStderr $pp["log"]
  }
  nssm start $name
} else {
  $cmdPath = "$seleniumDir\$($pp["role"]).cmd"

  if ($pp["log"] -ne $null -and $pp["log"] -ne '') {
     # todo logrotate files if log passed Add-Content
    $cmd | Set-Content $cmdPath
  } else {
    $cmd | Set-Content $cmdPath
  }

  $menuPrograms = [environment]::GetFolderPath([environment+specialfolder]::Programs)
  $shortcutArgs = @{
    shortcutFilePath = "$menuPrograms\Selenium\Selenium $((Get-Culture).TextInfo.ToTitleCase($pp["role"])).lnk"
    targetPath       = $cmdPath
    iconLocation     = "$toolsDir\icon.ico"
    workDirectory    = $seleniumDir
  }
  Install-ChocolateyShortcut @shortcutArgs

  if ($pp["autostart"] -eq $true) {
    $startup = "$env:SystemDrive\Users\$($pp["username"])\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
    $shortcutArgs = @{
      shortcutFilePath = "$startup\Selenium $((Get-Culture).TextInfo.ToTitleCase($pp["role"])).lnk"
      targetPath       = $cmdPath
      iconLocation     = "$toolsDir\icon.ico"
      workDirectory    = $seleniumDir
    }
    Install-ChocolateyShortcut @shortcutArgs
  }
}

$rules = Get-NetFirewallRule
$par = @{
    DisplayName = "$name"
    LocalPort   = $pp["port"]
    Direction   = "Inbound"
    Protocol    = "TCP"
    Action      = "Allow"
}
if (-not $rules.DisplayName.Contains($par.DisplayName)) {New-NetFirewallRule @par}

Write-Debug "Selenium firewall: $par"

