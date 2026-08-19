# 扫描单个项目自 -Since 以来的变化，供 sync-experience 技能使用
# 用法: powershell -ExecutionPolicy Bypass -File scan-project.ps1 -Path C:\LFZProject\Xxx -Since 2026-08-19
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Since
)

if (-not (Test-Path $Path)) { Write-Output "ERROR: path not found: $Path"; exit 1 }
$sinceDate = [datetime]::Parse($Since)   # 同为当日 00:00，与 git --since 口径一致

# git 输出 UTF-8；本机控制台默认 GBK，不改这里读回来的中文提交信息全是乱码
$prevEnc = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 按路径分段精确匹配，不用正则：避免 bin 误伤 binding、也免去转义地狱
$excludeDirs = @('bin','obj','packages','node_modules','.vs','.git','.svn','Log','Logs','x64','x86',
                 'Release','Debug','models','dist','build','DataSet','TestResults','图片','测试图')
$includeExt  = @('.cs','.csproj','.sln','.md','.txt','.json','.xml','.config','.py','.ps1','.sh',
                 '.h','.hpp','.c','.cpp','.hdev','.js','.ts','.tsx','.yml','.yaml','.props','.targets')
$sep = [char]92

function Test-Excluded([string]$fullName, [string]$root) {
    $rel = $fullName.Substring($root.Length).Trim($sep)
    foreach ($seg in $rel.Split($sep)) {
        if ($excludeDirs -contains $seg) { return $true }
        if ($seg -like 'publish_*') { return $true }
    }
    return $false
}

Write-Output "=== PROJECT: $Path (since $Since) ==="

# --- git 历史与工作区状态 ---
$isRepo = $false
git -C $Path rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $isRepo = $true }

if ($isRepo) {
    Write-Output ''
    Write-Output "--- GIT LOG (since $Since) ---"
    $log = git -C $Path log --since="$Since 00:00:00" --pretty=format:'%h %ad %s' --date=short
    if ($log) { $log } else { Write-Output '(no commits)' }

    Write-Output ''
    Write-Output '--- CHANGED FILES IN THOSE COMMITS ---'
    $diff = git -C $Path log --since="$Since 00:00:00" --name-only --pretty=format: | Where-Object { $_ } | Sort-Object -Unique
    if ($diff) { $diff } else { Write-Output '(none)' }

    Write-Output ''
    Write-Output '--- UNCOMMITTED ---'
    $st = git -C $Path status --porcelain
    if ($st) { $st } else { Write-Output '(clean)' }

    Write-Output ''
    Write-Output '--- BRANCHES ---'
    git -C $Path branch -vv --no-color

    Write-Output ''
    Write-Output '--- UNPUSHED COMMITS ---'
    $unpushed = git -C $Path log --branches --not --remotes --pretty=format:'%h %d %s' 2>$null
    if ($unpushed) { $unpushed } else { Write-Output '(none)' }
} else {
    Write-Output ''
    Write-Output '--- GIT: not a repository ---'
}

# --- 按文件时间戳找变化：覆盖非 git 项目，以及 git 外的产物（测试报告、基线等）---
Write-Output ''
Write-Output "--- CHANGED FILES ON DISK (mtime > $Since) ---"
$root = $Path.TrimEnd($sep)
$files = Get-ChildItem -Path $root -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object {
        $_.LastWriteTime -gt $sinceDate -and
        $includeExt -contains $_.Extension -and
        -not (Test-Excluded $_.FullName $root)
    } | Sort-Object LastWriteTime -Descending

if ($files) {
    $files | ForEach-Object {
        '{0:yyyy-MM-dd HH:mm}  {1,9}  {2}' -f $_.LastWriteTime, $_.Length, $_.FullName.Substring($root.Length).TrimStart($sep)
    }
    Write-Output ''
    Write-Output "TOTAL_CHANGED: $($files.Count)"
} else {
    Write-Output 'NO_CHANGES'
}

[Console]::OutputEncoding = $prevEnc
