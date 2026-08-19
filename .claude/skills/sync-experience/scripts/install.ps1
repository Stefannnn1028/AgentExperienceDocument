# 把仓库里的 sync-experience 技能安装到用户级技能目录，使其在任意项目下可用。
# 仓库是唯一真源；改了 SKILL.md 后重跑本脚本即可。
# 用法: powershell -ExecutionPolicy Bypass -File install.ps1
$src = Split-Path -Parent $PSScriptRoot
$dst = Join-Path $env:USERPROFILE '.claude\skills\sync-experience'

if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Recurse -Force (Join-Path $src '*') $dst

Write-Output "已安装: $dst"
Get-ChildItem -Recurse -File $dst | ForEach-Object { "  " + $_.FullName.Substring($dst.Length).TrimStart('\') }
Write-Output ""
Write-Output "在任意项目目录下用 /sync-experience 触发。"
