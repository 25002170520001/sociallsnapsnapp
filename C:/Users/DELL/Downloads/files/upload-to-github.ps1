param(
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string]$Repo,
  [string]$TokenEnvVar = "GITHUB_TOKEN"
)

$tokenItem = Get-Item -Path "env:$TokenEnvVar" -ErrorAction SilentlyContinue
if (-not $tokenItem) {
  Write-Host "Set your PAT in environment variable `$env:$TokenEnvVar` first."
  exit 1
}
$token = $tokenItem.Value
$baseApi = "https://api.github.com"

# Create repo (fine-grained tokens may require different endpoints/permissions)
$createBody = @{ name = $Repo; description = "Website: Wedding Snapp × Sociall Snap"; private = $false } | ConvertTo-Json
try {
  $resp = Invoke-RestMethod -Headers @{ Authorization = "token $token"; "User-Agent"="upload-script" } -Method POST -Uri "$baseApi/user/repos" -Body $createBody -ErrorAction Stop
  Write-Host "Repository '$Repo' created or already exists."
} catch {
  Write-Host "Could not create repo (may already exist). Continuing to upload files..."
}

function Upload-File($localPath, $repoPath) {
  $contentBytes = [System.IO.File]::ReadAllBytes($localPath)
  $contentB64 = [System.Convert]::ToBase64String($contentBytes)
  $message = "Add $repoPath"
  $body = @{ message = $message; content = $contentB64 } | ConvertTo-Json
  $uri = "$baseApi/repos/$Owner/$Repo/contents/$repoPath"
  try {
    Invoke-RestMethod -Headers @{ Authorization = "token $token"; "User-Agent"="upload-script" } -Method PUT -Uri $uri -Body $body -ErrorAction Stop
    Write-Host "Uploaded: $repoPath"
  } catch {
    # If file exists, update it by providing sha
    try {
      $get = Invoke-RestMethod -Headers @{ Authorization = "token $token"; "User-Agent"="upload-script" } -Method GET -Uri $uri -ErrorAction Stop
      $sha = $get.sha
      $body2 = @{ message = "Update $repoPath"; content = $contentB64; sha = $sha } | ConvertTo-Json
      Invoke-RestMethod -Headers @{ Authorization = "token $token"; "User-Agent"="upload-script" } -Method PUT -Uri $uri -Body $body2 -ErrorAction Stop
      Write-Host "Updated: $repoPath"
    } catch {
      Write-Host "Failed to upload ${repoPath}: $($_.Exception.Message)"
    }
  }
}

# Upload files (skip .vercel, .git)
$cwd = Get-Location
Get-ChildItem -Recurse -File | Where-Object { $_.FullName -notmatch "\\\\.git\\\\" -and $_.FullName -notmatch "\\\\.vercel\\\\" -and $_.FullName -notmatch "\\\\node_modules\\\\" } | ForEach-Object {
  $relative = $_.FullName.Replace($cwd.Path + "\\", "")
  $repoPath = $relative -replace "\\", "/"
  Upload-File $_.FullName $repoPath
}

Write-Host "Done. Visit https://github.com/$Owner/$Repo"
