# Obsidian Bags v0.0.125 optional safe copy tool. Close WoW first.
$ErrorActionPreference = 'Stop'
$gameRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$wtf = Join-Path $gameRoot 'WTF'
if (-not (Test-Path -LiteralPath $wtf -PathType Container)) {
  throw "WTF folder not found at $wtf. Follow MIGRATION.txt manually."
}
$old = @(Get-ChildItem -LiteralPath $wtf -Recurse -File -Filter 'VirtualBagsLab.lua')
if ($old.Count -eq 0) { Write-Host 'No legacy SavedVariables found. Nothing was changed.'; exit 0 }
$copied = 0
foreach ($file in $old) {
  $destination = Join-Path $file.DirectoryName 'ObsidianBags.lua'
  if (Test-Path -LiteralPath $destination) {
    Write-Warning "Existing new SavedVariables not overwritten: $destination"
  } else {
    Copy-Item -LiteralPath $file.FullName -Destination $destination -ErrorAction Stop
    Write-Host "Copied: $($file.FullName)"
    $copied++
  }
}
Write-Host "Finished: $copied new SavedVariables files created; originals retained."
