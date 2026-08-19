# 扫描单个项目自 -Since 以来的变化，供 sync-experience 技能使用
# 用法: powershell -ExecutionPolicy Bypass -File scan-project.ps1 -Path E:\Project\Xxx -Since 2026-08-19
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Since
)

if (-not (Test-Path $Path)) { Write-Output "ERROR: path not found: $Path"; exit 1 }
$sinceDate = [datetime]::Parse($Since)

$excludeDirs = 'bin|obj|packages|node_modules|\.vs|\.git|Log|Logs|logs|x64|Release|Debug|models|Models|dist|build|图片|测试图|DataSet|publish_'
$includeExt  = '\.(cs|csproj|sln|md|txt|json|xml|config|py|ps1|sh|h|hpp|c|cpp|hdev|js|ts|tsx|yml|yaml)$'

Write-Output "=== PROJECT: $Path (since $Since) ==="

# --- git 历史与工作区状态 ---
$isRepo = $false
try {
    git -C $Path rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($?) { $isRepo = $true }
} catch { }

if ($isRepo) {
    Write-Output ""
    Write-Output "--- GIT LOG (since $Since) ---"
    $log = git -C $Path log --since="$Since" --pretty=format:'%h %ad %s' --date=short
    if ($log) { $log } else { Write-Output "(no commits)" }

    Write-Output ""
    Write-Output "--- UNCOMMITTED ---"
    $st = git -C $Path status --porcelain
    if ($st) { $st } else { Write-Output "(clean)" }

    Write-Output ""
    Write-Output "--- BRANCHES ---"
    git -C $Path branch -vv --no-color

    Write-Output ""
    Write-Output "--- UNPUSHED ---"
    $unpushed = git -C $Path log --branches --not --remotes --pretty=format:'%h %d %s' 2>$null
    if ($unpushed) { $unpushed } else { Write-Output "(none or no remote)" }
} else {
    Write-Output ""
    Write-Output "--- GIT: not a repository ---"
}

# --- 按文件时间戳找变化（覆盖非 git 项目，以及 git 外的产物如报告/基线） ---
Write-Output ""
Write-Output "--- CHANGED FILES (mtime > $Since) ---"
$files = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object {
        $_.LastWriteTime -gt $sinceDate -and
        $_.Extension -match $includeExt -and
        $_.FullName -notmatch "\($excludeDirs)\\"
    } |
    Sort-Object LastWriteTime -Descending

if ($files) {
    $files | ForEach-Object {
        "{0:yyyy-MM-dd HH:mm}  {1,8}  {2}" -f $_.LastWriteTime, $_.Length, $_.FullName.Substring($Path.Length).TrimStart('\')
    }
    Write-Output ""
    Write-Output "TOTAL_CHANGED: $($files.Count)"
} else {
    Write-Output "NO_CHANGES"
}
