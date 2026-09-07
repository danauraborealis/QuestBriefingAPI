#requires -Version 5.1
[CmdletBinding()]
param([string]$SPTPath = $env:SPT_PATH, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$project = Join-Path $root 'QuestBriefingAPIClient\QuestBriefingAPIClient.csproj'
$exampleResources = Join-Path $root 'QuestBriefingAPIExample\Resources'
if ([string]::IsNullOrWhiteSpace($SPTPath)) {
    $SPTPath = (& dotnet msbuild $project -getProperty:SPTPath -nologo | Out-String).Trim()
    if ($LASTEXITCODE -or [string]::IsNullOrWhiteSpace($SPTPath)) {
        throw 'Set SPTPath in Directory.Build.props, set SPT_PATH, or pass -SPTPath.'
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $SPTPath 'EscapeFromTarkov_Data\Managed\Assembly-CSharp.dll') -PathType Leaf)) {
    throw "Game references were not found in '$SPTPath'. Pass -SPTPath pointing to your SPT installation root."
}
$SPTPath = (Resolve-Path -LiteralPath $SPTPath).Path
Write-Host "Building against SPT at $SPTPath"
& dotnet restore $project --configfile "$root\NuGet.Config" "-p:SPTPath=$SPTPath" -v minimal
if ($LASTEXITCODE) { throw 'Plugin restore failed.' }
& dotnet build $project --no-restore -c Release "-p:SPTPath=$SPTPath" -v minimal
if ($LASTEXITCODE) { throw 'Plugin build failed.' }
$metadataJson = & dotnet msbuild $project -getProperty:ModVersion,ModGuid,ModName,RepositoryUrl -nologo
if ($LASTEXITCODE) { throw 'Cannot read release metadata from Directory.Build.props.' }
$metadata = ($metadataJson -join [Environment]::NewLine | ConvertFrom-Json).Properties
$version = $metadata.ModVersion
if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$' -or $metadata.ModName -notmatch '^[A-Za-z0-9]+-[A-Za-z0-9]+$') {
    throw 'Invalid release version/name in Directory.Build.props.'
}
if ($metadata.RepositoryUrl -notmatch '^https://[^\s]+$') { throw 'Set RepositoryUrl to the public source repository in Directory.Build.props.' }
$releaseName = "$($metadata.ModName)-$version.zip"
$sourceName = "$($metadata.ModName)-Source-$version.zip"
$dist = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $root 'dist'
} else { [IO.Path]::GetFullPath($OutputDirectory) }
New-Item -ItemType Directory -Path $dist -Force | Out-Null
if ((Get-Item -LiteralPath $dist).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'dist cannot be a link.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-VerifiedZip([string]$Name, $Files) {
    $temporary = Join-Path $dist ([Guid]::NewGuid().ToString('N') + '.zip')
    $archive = [IO.Compression.ZipFile]::Open($temporary, 'Create')
    $hashes = @{}
    try {
        foreach ($entry in $Files) {
            $hashes[$entry.Name] = (Get-FileHash -LiteralPath $entry.Path -Algorithm SHA256).Hash
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $entry.Path, $entry.Name)
        }
    } finally { $archive.Dispose() }
    $archive = [IO.Compression.ZipFile]::OpenRead($temporary)
    try {
        foreach ($entry in $archive.Entries) {
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $actual = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
            finally { $stream.Dispose(); $sha.Dispose() }
            if ($actual -ne $hashes[$entry.FullName]) { throw "ZIP hash mismatch: $($entry.FullName)" }
            $hashes.Remove($entry.FullName)
        }
        if ($hashes.Count) { throw 'ZIP is missing files.' }
    } finally { $archive.Dispose() }
    $destination = Join-Path $dist $Name
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        [IO.File]::Replace($temporary, $destination, [NullString]::Value)
    } else {
        Move-Item -LiteralPath $temporary -Destination $destination
    }
}

$output = Join-Path $root 'QuestBriefingAPIClient\bin\Release\netstandard2.1'
$dll = Join-Path $output 'QuestBriefingAPI.dll'
$pluginFiles = @(
    @{ Path=$dll; Name='BepInEx/plugins/QuestBriefingAPI/QuestBriefingAPI.dll' },
    @{ Path=(Join-Path $output 'QuestBriefingAPI.xml'); Name='BepInEx/plugins/QuestBriefingAPI/QuestBriefingAPI.xml' },
    @{ Path="$root\LICENSE"; Name='QuestBriefingAPI-LICENSE.txt' }
)
foreach ($document in @('README.md', 'VERSIONING.md')) {
    if (Test-Path -LiteralPath "$root\$document" -PathType Leaf) {
        $pluginFiles += @{ Path="$root\$document"; Name="QuestBriefingAPI-$document" }
    }
}
$releaseInfoPath = Join-Path $dist 'RELEASE-INFO.txt'
@"
$($metadata.ModName) $version
Forge GUID: $($metadata.ModGuid)
Source: $($metadata.RepositoryUrl)

Install: extract this ZIP into your SPT 4.1 installation root.
The compiled DLL is in BepInEx/plugins/QuestBriefingAPI; no build is needed.
Use F12 > $($metadata.ModName) to configure playback, volume, and radio effects.
The config file is BepInEx/config/$($metadata.ModGuid).cfg.
Briefing packs belong in their own directories under BepInEx/plugins.
Copy the bundled example, replace the IDs, add audio, then rename
briefings.json.example to briefings.json. The bundled example is disabled.
For C# integrations, use BepInDependency("$($metadata.ModGuid)", "$version").

For a Forge upload, use the GUID/name/version above and link the source repository.
Commit and push the exact source used for this binary before submitting it.
In-game playback/layout still require testing; metadata checks do not verify them.
"@ | Set-Content -LiteralPath $releaseInfoPath -Encoding utf8
$pluginFiles += @{ Path=$releaseInfoPath; Name='QuestBriefingAPI-RELEASE-INFO.txt' }
# The sample manifest uses .json.example so discovery ignores it until an author enables it.
foreach ($file in (Get-ChildItem -LiteralPath $exampleResources -File -Recurse)) {
    $relative = $file.FullName.Substring($exampleResources.Length + 1).Replace('\','/')
    if ($relative -eq 'briefings.json') { $relative = 'briefings.json.example' }
    $pluginFiles += @{ Path=$file.FullName; Name="BepInEx/plugins/QuestBriefingAPI/examples/MyQuestBriefings/$relative" }
}
Write-VerifiedZip $releaseName $pluginFiles
$sourceFiles = @()
foreach ($file in (Get-ChildItem -LiteralPath $root -File -Force)) {
    if ($file.Extension -in '.ps1','.sln' -or $file.Name -in @('Directory.Build.props','NuGet.Config','.gitignore','README.md','VERSIONING.md','LICENSE')) {
        $sourceFiles += @{ Path=$file.FullName; Name=$file.Name }
    }
}
foreach ($directory in @('QuestBriefingAPIClient','QuestBriefingAPIExample')) {
    foreach ($file in (Get-ChildItem -LiteralPath "$root\$directory" -File -Recurse)) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\','/')
        if ($relative -match '/(bin|obj)/') { continue }
        $sourceFiles += @{ Path=$file.FullName; Name=$relative }
    }
}
Write-VerifiedZip $sourceName $sourceFiles
# Retire the previous separate author kit only after the replacement archives are verified.
$oldAuthorKit = Join-Path $dist "QuestBriefingAPI-AuthorKit-$version.zip"
if (Test-Path -LiteralPath $oldAuthorKit -PathType Leaf) { Remove-Item -LiteralPath $oldAuthorKit }
@($releaseName, $sourceName) | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash -LiteralPath (Join-Path $dist $_) -Algorithm SHA256).Hash, $_
} | Set-Content -LiteralPath "$dist\SHA256SUMS.txt" -Encoding ascii
Write-Host "Release with bundled examples and standalone source ZIPs verified in $dist"
