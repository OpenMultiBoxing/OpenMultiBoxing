# Microsoft Store submission of a published GitHub release: Store package of its zip's exe, and its notes as the
# Store's "What's new in this version". msstore must be configured first (msstore reconfigure ...).
#   msix\submit.ps1 -Tag v1.2.3 [-NotesOnly]
# -NotesOnly just prints the Store notes of that release.
param(
    [Parameter(Mandatory)][string]$Tag,
    [switch]$NotesOnly
)
$ErrorActionPreference = 'Stop'
$repo = 'OpenMultiBoxing/OpenMultiBoxing'
$appId = '9N0DZ59NL2DW'
# msstore's output (the submission JSON, with the listing texts) must be read as UTF-8
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# Release notes markdown -> Store plain text (max 1500 chars), ending with a link to all the releases
function StoreNotes([string]$body) {
    $lines = foreach ($l in ($body -split "`r?`n")) {
        # headings, the compare link and the binary reminders (Store users always get the right exe)
        if ($l -match '^\s*#' -or $l -match '^\*\*Full Changelog\*\*' -or $l -match '^\s*Reminder:') {
            continue
        }
        $l = $l -replace '^\s*[*-]\s+', '• '
        $l = $l -replace '\[([^\]]+)\]\(([^)]+)\)', '$1 ($2)'
        $l -replace '\*\*', ''
    }
    $text = (($lines -join "`n") -replace "`n{3,}", "`n`n").Trim()
    $more = "All the details and previous versions: https://github.com/$repo/releases"
    $max = 1500 - $more.Length - 2
    if ($text.Length -gt $max) {
        $text = $text.Substring(0, $max - 1) + '…'
    }
    "$text`n`n$more"
}

$headers = @{}
if ($env:GITHUB_TOKEN) {
    $headers.Authorization = "Bearer $env:GITHUB_TOKEN"
}
$release = Invoke-RestMethod -Headers $headers "https://api.github.com/repos/$repo/releases/tags/$Tag"
$notes = StoreNotes $release.body
if ($NotesOnly) {
    return $notes
}
"Store notes:`n$notes`n"

$zip = $release.assets | Where-Object name -like '*.zip' | Select-Object -First 1
if (!$zip) { throw "No zip in release $Tag" }
$dir = Join-Path ([IO.Path]::GetTempPath()) "storesubmit_$PID"
New-Item -ItemType Directory -Force $dir | Out-Null
$zipPath = Join-Path $dir $zip.name
Invoke-WebRequest -Headers $headers $zip.browser_download_url -OutFile $zipPath
Expand-Archive $zipPath -DestinationPath $dir
$exe = Get-ChildItem $dir -Filter *.exe | Select-Object -First 1
$msix = Join-Path $dir "OpenMultiBoxing-$Tag.msix"
& (Join-Path $PSScriptRoot pack.ps1) -Exe $exe.FullName -Version $Tag -Out $msix

# Upload as a draft, set the notes, then commit (publish must come first: it recreates the draft)
msstore publish $msix -id $appId --noCommit
if ($LASTEXITCODE) { throw "msstore publish failed ($LASTEXITCODE)" }
$out = (msstore submission get $appId) -join "`n"
if ($LASTEXITCODE) { throw "msstore submission get failed ($LASTEXITCODE)" }
$start = $out.IndexOf('{')
$json = $out.Substring($start, $out.LastIndexOf('}') - $start + 1)
if ($json.Contains([char]0xFFFD)) {
    throw "Submission JSON wasn't read as UTF-8, not updating it (the draft is in Partner Center, commit it there)"
}
$submission = $json | ConvertFrom-Json
foreach ($listing in $submission.Listings.PSObject.Properties) {
    $listing.Value.BaseListing | Add-Member -NotePropertyName ReleaseNotes -NotePropertyValue $notes -Force
    "Notes set for $($listing.Name)"
}
msstore submission update $appId ($submission | ConvertTo-Json -Depth 100 -Compress)
if ($LASTEXITCODE) { throw "msstore submission update failed ($LASTEXITCODE)" }
msstore submission publish $appId
if ($LASTEXITCODE) { throw "msstore submission publish failed ($LASTEXITCODE)" }
