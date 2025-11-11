<#
PowerShell helper: fix_merge_and_push.ps1
Usage (from repo root):
    powershell -ExecutionPolicy Bypass -File .\scripts\fix_merge_and_push.ps1 -Action delete
Actions:
  delete  - remove .git/.MERGE_MSG.swp (if present), finish merge commit using MERGE_MSG, pull --rebase origin main, push
  abort   - abort current merge or rebase
  status  - show helpful status information

This script attempts to automate the safe flow. If a rebase causes conflicts it will stop and print instructions.
#>
param(
    [ValidateSet("delete","abort","status")]
    [string]$Action = "delete"
)

function Run-Git {
    param([string[]]$Args)
    Write-Host "git $($Args -join ' ')" -ForegroundColor Cyan
    & git @Args
    return $LASTEXITCODE
}

$repo = Get-Location
Write-Host "Repository: $repo" -ForegroundColor Green
$swp = Join-Path $repo ".git\.MERGE_MSG.swp"
$mergeMsg = Join-Path $repo ".git\MERGE_MSG"

if ($Action -eq 'status') {
    Write-Host "Swap file exists:" (Test-Path $swp)
    if (Test-Path $swp) { Write-Host "  $swp" }
    Write-Host "MERGE_MSG exists:" (Test-Path $mergeMsg)
    if (Test-Path $mergeMsg) { Get-Content $mergeMsg | Select-Object -First 50 }
    Run-Git status
    exit 0
}

if ($Action -eq 'abort') {
    Write-Host "Aborting merge/rebase..." -ForegroundColor Yellow
    $c = Run-Git @('merge', '--abort')
    if ($c -ne 0) {
        Write-Host "merge --abort failed (maybe not a merge). Trying rebase --abort..." -ForegroundColor Yellow
        $c2 = Run-Git @('rebase', '--abort')
        if ($c2 -ne 0) {
            Write-Host "Both aborts failed. Check 'git status' manually." -ForegroundColor Red
        }
    }
    Run-Git status
    exit 0
}

# Action = delete (default)
if ($Action -eq 'delete') {
    if (Test-Path $swp) {
        Write-Host "Removing swap file: $swp" -ForegroundColor Yellow
        try { Remove-Item -Force $swp -ErrorAction Stop; Write-Host "Swap file removed." -ForegroundColor Green }
        catch { Write-Host "Failed to remove swap: $_" -ForegroundColor Red; exit 1 }
    }

    # show status
    Run-Git status

    # Finish merge commit with existing MERGE_MSG if present
    if (Test-Path $mergeMsg) {
        $content = (Get-Content $mergeMsg -Raw).Trim()
        if ($content.Length -gt 0) {
            Write-Host "Found existing MERGE_MSG; finishing merge commit using --no-edit." -ForegroundColor Green
            if (Run-Git @('commit', '--no-edit') -ne 0) {
                Write-Host "git commit failed. Inspect the repository state with 'git status'." -ForegroundColor Red
                Run-Git status
                exit 1
            }
        } else {
            Write-Host "MERGE_MSG exists but empty; running 'git commit' to open editor." -ForegroundColor Yellow
            if (Run-Git @('commit') -ne 0) {
                Write-Host "git commit failed or aborted. Inspect with 'git status'." -ForegroundColor Red
                exit 1
            }
        }
    } else {
        Write-Host "No MERGE_MSG found; attempting git commit --no-edit." -ForegroundColor Yellow
        if (Run-Git @('commit', '--no-edit') -ne 0) {
            Write-Host "git commit failed. Possibly there is nothing to commit." -ForegroundColor Yellow
        }
    }

    # Now integrate remote changes using rebase (recommended)
    Write-Host "Fetching origin..." -ForegroundColor Cyan
    if (Run-Git @('fetch','origin') -ne 0) { Write-Host "git fetch failed" -ForegroundColor Red; exit 1 }

    Write-Host "Rebasing onto origin/main..." -ForegroundColor Cyan
    $r = Run-Git @('pull','--rebase','origin','main')
    if ($r -ne 0) {
        Write-Host "git pull --rebase failed. If there are conflicts, resolve them manually. Current status:" -ForegroundColor Red
        Run-Git status
        Write-Host "To continue after resolving conflicts: git add <files>; git rebase --continue" -ForegroundColor Yellow
        Write-Host "If you prefer to abort the rebase: git rebase --abort" -ForegroundColor Yellow
        exit 2
    }

    # Push
    Write-Host "Pushing to origin/main..." -ForegroundColor Cyan
    if (Run-Git @('push','-u','origin','main') -ne 0) {
        Write-Host "git push failed. If the remote changed meanwhile, consider 'git pull --rebase' or push to a new branch." -ForegroundColor Red
        exit 3
    }

    Write-Host "All done: merge finished, rebased onto origin/main, and pushed." -ForegroundColor Green
    exit 0
}

Write-Host "Unknown action: $Action" -ForegroundColor Red
exit 1
