<#
.SYNOPSIS
	Installs MathArena's Studio plugins into this machine's Roblox Studio
	Plugins folder.

.DESCRIPTION
	Roblox Studio loads plugins from a fixed per-user folder on disk, NOT
	from the game or from Rojo - a plugin cannot be synced in like normal
	game code, because it has to run in Studio itself rather than inside
	the place. So every developer needs a copy on their own machine, and
	this script is what puts it there.

	Run it once after cloning the repo, and again whenever the plugin
	changes (it overwrites in place). It only ever writes into the Studio
	Plugins folder - it never touches the repo or the game.

.PARAMETER WhatIf
	Show what would be copied without copying anything.

.EXAMPLE
	powershell -ExecutionPolicy Bypass -File tools\StudioPlugins\install.ps1

.NOTES
	Restart Roblox Studio afterward if it does not hot-load the change.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'

# Every .lua sitting next to this script is treated as a plugin to install,
# so adding a second plugin later needs no change here.
$sourceDir = $PSScriptRoot
$plugins = Get-ChildItem -Path $sourceDir -Filter '*.lua' -File

if ($plugins.Count -eq 0) {
	Write-Error "No .lua plugin files found in $sourceDir"
	exit 1
}

# Windows Studio reads plugins from %LOCALAPPDATA%\Roblox\Plugins.
$pluginsDir = Join-Path $env:LOCALAPPDATA 'Roblox\Plugins'

if (-not (Test-Path -LiteralPath $pluginsDir)) {
	Write-Host "Plugins folder doesn't exist yet - creating $pluginsDir"
	if ($PSCmdlet.ShouldProcess($pluginsDir, 'Create directory')) {
		New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
	}
}

$installed = 0
foreach ($plugin in $plugins) {
	$destination = Join-Path $pluginsDir $plugin.Name

	$existing = Test-Path -LiteralPath $destination
	$action = if ($existing) { 'Updating' } else { 'Installing' }
	Write-Host "$action $($plugin.Name) -> $destination"

	if ($PSCmdlet.ShouldProcess($destination, $action)) {
		try {
			Copy-Item -LiteralPath $plugin.FullName -Destination $destination -Force
			$installed++
		}
		catch {
			# Studio holds no lock on plugin files in normal use, so a
			# failure here is usually a permissions or antivirus issue -
			# worth naming rather than swallowing.
			Write-Warning "Couldn't copy $($plugin.Name): $($_.Exception.Message)"
		}
	}
}

Write-Host ""
Write-Host "Done - $installed plugin(s) installed to $pluginsDir"
Write-Host "Restart Roblox Studio if the change doesn't appear automatically."
