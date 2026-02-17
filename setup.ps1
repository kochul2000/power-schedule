#Requires -RunAsAdministrator
# ============================================
# Power Plan Auto-Switch Setup
# ============================================

param(
    [switch]$delete,
    [switch]$force
)

# --- Delete mode ---
if ($delete) {
    Write-Host "=== Power Plan Auto-Switch Uninstall ===" -ForegroundColor Red

    schtasks /delete /tn PowerPlan-AutoSwitch /f 2>$null
    if ($?) { Write-Host "  Task removed" -ForegroundColor Green }
    else    { Write-Host "  Task not found (already removed)" -ForegroundColor DarkYellow }

    $plans = (powercfg /list) -join "`n"
    $onMatch = [regex]::Match($plans, '([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}).*?WorkHours-AlwaysOn')
    $offMatch = [regex]::Match($plans, '([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}).*?OffHours-AllowSleep')

    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e

    if ($onMatch.Success) {
        powercfg /delete $onMatch.Groups[1].Value
        Write-Host "  Deleted plan: WorkHours-AlwaysOn ($($onMatch.Groups[1].Value))" -ForegroundColor Green
    }
    if ($offMatch.Success) {
        powercfg /delete $offMatch.Groups[1].Value
        Write-Host "  Deleted plan: OffHours-AllowSleep ($($offMatch.Groups[1].Value))" -ForegroundColor Green
    }

    if (-not $onMatch.Success -and -not $offMatch.Success) {
        Write-Host "  No custom plans found (already removed)" -ForegroundColor DarkYellow
    }

    $switchScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "switch-power-plan.ps1"
    if (Test-Path $switchScript) {
        Remove-Item $switchScript
        Write-Host "  Removed: $switchScript" -ForegroundColor Green
    }

    Write-Host "`nUninstall complete." -ForegroundColor Cyan
    exit
}

# --- Check if already installed ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$switchScript = Join-Path $scriptDir "switch-power-plan.ps1"
$taskExists = Get-ScheduledTask -TaskName "PowerPlan-AutoSwitch" -ErrorAction SilentlyContinue

if ($taskExists -and (Test-Path $switchScript) -and -not $force) {
    Write-Host "=== Power Plan Auto-Switch: Already Installed ===" -ForegroundColor Cyan

    # Read settings from switch-power-plan.ps1
    $content = Get-Content $switchScript -Raw
    $ws = [regex]::Match($content, 'WORK_START\s*=\s*(\d+)').Groups[1].Value
    $we = [regex]::Match($content, 'WORK_END\s*=\s*(\d+)').Groups[1].Value

    # Read sleep plan values via powercfg query
    $plans = (powercfg /list) -join "`n"
    $sleepPlanMatch = [regex]::Match($plans, '([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}).*?OffHours-AllowSleep')
    $monMin = "?"
    $slpMin = "?"
    if ($sleepPlanMatch.Success) {
        $sg = $sleepPlanMatch.Groups[1].Value
        # Use powercfg /query and find the last 0x line (AC value) - works regardless of OS language
        $videoLines = powercfg /query $sg SUB_VIDEO VIDEOIDLE | Select-String '0x[0-9a-fA-F]+'
        $standbyLines = powercfg /query $sg SUB_SLEEP STANDBYIDLE | Select-String '0x[0-9a-fA-F]+'
        if ($videoLines) {
            $lastVideo = ($videoLines | Select-Object -Last 1).Matches[0].Value
            $monMin = [math]::Round([convert]::ToInt32($lastVideo, 16) / 60)
        }
        if ($standbyLines) {
            $lastStandby = ($standbyLines | Select-Object -Last 1).Matches[0].Value
            $slpMin = [math]::Round([convert]::ToInt32($lastStandby, 16) / 60)
        }
    }

    # Read interval from task trigger
    $interval = $taskExists.Triggers[0].Repetition.Interval
    $intervalMatch = [regex]::Match($interval, 'PT(\d+)M')
    $intMin = if ($intervalMatch.Success) { $intervalMatch.Groups[1].Value } else { "?" }

    # Current active plan
    $activePlan = (powercfg /getactivescheme) -join " "
    $currentLabel = if ($activePlan -match 'WorkHours-AlwaysOn') { "WorkHours-AlwaysOn" }
                    elseif ($activePlan -match 'OffHours-AllowSleep') { "OffHours-AllowSleep" }
                    else { "Other" }

    Write-Host ""
    Write-Host "  Current Settings" -ForegroundColor White
    Write-Host "  ----------------"
    Write-Host "  Work hours:      ${ws}:00 ~ ${we}:00  (Always On)"
    Write-Host "  Off hours:       Monitor off ${monMin}min, Sleep ${slpMin}min"
    Write-Host "  Check interval:  every ${intMin} min"
    Write-Host "  Active plan:     $currentLabel"
    Write-Host ""
    Write-Host "  To reinstall with new settings:  .\setup.ps1 -force" -ForegroundColor DarkGray
    Write-Host "  To uninstall:                    .\setup.ps1 -delete" -ForegroundColor DarkGray
    exit
}

# --- Install mode ---
Write-Host "=== Power Plan Auto-Switch Setup ===" -ForegroundColor Cyan
Write-Host "Press Enter to use default values.`n" -ForegroundColor DarkGray

$workStartInput = Read-Host "Work start hour [default: 9]"
$WORK_START = if ($workStartInput) { [int]$workStartInput } else { 9 }

$workEndInput = Read-Host "Work end hour   [default: 22]"
$WORK_END = if ($workEndInput) { [int]$workEndInput } else { 22 }

$monitorInput = Read-Host "Monitor off after (minutes, off-hours) [default: 30]"
$MONITOR_OFF = if ($monitorInput) { [int]$monitorInput } else { 30 }

$sleepInput = Read-Host "Sleep after (minutes, off-hours)       [default: 60]"
$SLEEP_AFTER = if ($sleepInput) { [int]$sleepInput } else { 60 }

Write-Host "`n  Work hours: ${WORK_START}:00 ~ ${WORK_END}:00 -> Always On" -ForegroundColor White
Write-Host "  Off hours:  Monitor off ${MONITOR_OFF}min, Sleep ${SLEEP_AFTER}min" -ForegroundColor White

# 1. Create power plans (skip if already exist)
Write-Host "`n[1/4] Creating power plans..." -ForegroundColor Yellow

$existingPlans = (powercfg /list) -join "`n"
$alwaysOnMatch = [regex]::Match($existingPlans, '([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}).*?WorkHours-AlwaysOn')
$sleepMatch = [regex]::Match($existingPlans, '([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}).*?OffHours-AllowSleep')

if ($alwaysOnMatch.Success) {
    $alwaysOnGuid = $alwaysOnMatch.Groups[1].Value
    Write-Host "  Always-On plan already exists: $alwaysOnGuid" -ForegroundColor DarkYellow
} else {
    $alwaysOnOutput = powercfg /duplicatescheme 381b4222-f694-41f0-9685-ff5bb260df2e
    $alwaysOnGuid = [regex]::Match($alwaysOnOutput, '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}').Value
    powercfg /changename $alwaysOnGuid "WorkHours-AlwaysOn" "Work hours no sleep"
    Write-Host "  Always-On plan created: $alwaysOnGuid" -ForegroundColor Green
}

powercfg /setacvalueindex $alwaysOnGuid SUB_SLEEP STANDBYIDLE 0
powercfg /setacvalueindex $alwaysOnGuid SUB_SLEEP HIBERNATEIDLE 0
powercfg /setacvalueindex $alwaysOnGuid SUB_VIDEO VIDEOIDLE 0

if ($sleepMatch.Success) {
    $sleepGuid = $sleepMatch.Groups[1].Value
    Write-Host "  Allow-Sleep plan already exists: $sleepGuid" -ForegroundColor DarkYellow
} else {
    $sleepOutput = powercfg /duplicatescheme 381b4222-f694-41f0-9685-ff5bb260df2e
    $sleepGuid = [regex]::Match($sleepOutput, '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}').Value
    powercfg /changename $sleepGuid "OffHours-AllowSleep" "Off hours allow sleep"
    Write-Host "  Allow-Sleep plan created: $sleepGuid" -ForegroundColor Green
}

$MONITOR_OFF_SEC = $MONITOR_OFF * 60
$SLEEP_AFTER_SEC = $SLEEP_AFTER * 60
powercfg /setacvalueindex $sleepGuid SUB_SLEEP STANDBYIDLE $SLEEP_AFTER_SEC
powercfg /setacvalueindex $sleepGuid SUB_SLEEP HIBERNATEIDLE 0
powercfg /setacvalueindex $sleepGuid SUB_VIDEO VIDEOIDLE $MONITOR_OFF_SEC

# 2. Generate main switch script
Write-Host "`n[2/4] Creating switch script..." -ForegroundColor Yellow

$mainScript = @"

# Power Plan Auto-Switch (runs periodically)

`$ALWAYS_ON_GUID = "$alwaysOnGuid"
`$SLEEP_GUID     = "$sleepGuid"
`$WORK_START     = $WORK_START
`$WORK_END       = $WORK_END

`$hour = (Get-Date).Hour
`$currentPlan = (powercfg /getactivescheme) -replace '.*([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}).*', '`$1'

if (`$hour -ge `$WORK_START -and `$hour -lt `$WORK_END) {
    `$targetGuid = `$ALWAYS_ON_GUID
    `$label = "WorkHours-AlwaysOn"
} else {
    `$targetGuid = `$SLEEP_GUID
    `$label = "OffHours-AllowSleep"
}

if (`$currentPlan -ne `$targetGuid) {
    powercfg /setactive `$targetGuid
    Write-Output "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Switched to: `$label"
} else {
    Write-Output "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Keeping: `$label"
}
"@

$mainScriptPath = Join-Path $scriptDir "switch-power-plan.ps1"
$mainScript | Out-File -FilePath $mainScriptPath -Encoding UTF8
Write-Host "  Saved: $mainScriptPath" -ForegroundColor Green

# 3. Register scheduled task
Write-Host "`n[3/4] Registering scheduled task..." -ForegroundColor Yellow

$taskName = "PowerPlan-AutoSwitch"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$mainScriptPath`""

$intervalMin = [math]::Max(5, [math]::Floor($SLEEP_AFTER / 2))
Write-Host "  Check interval: every ${intervalMin} min (half of sleep time)" -ForegroundColor DarkGray

$trigger = New-ScheduledTaskTrigger -Daily -At "00:00"
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Minutes $intervalMin)).Repetition

$settings = New-ScheduledTaskSettingsSet `
    -WakeToRun `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -RunLevel Highest `
    -User "SYSTEM" `
    -Description "Auto-switch power plan every ${intervalMin}min (work: ${WORK_START}~${WORK_END})"

Write-Host "  Registered: $taskName" -ForegroundColor Green

# 4. Done
Write-Host "`n[4/4] Setup complete!" -ForegroundColor Cyan
Write-Host @"

  Summary
  -------
  ${WORK_START}:00 ~ $($WORK_END-1):59  ->  Always On (no sleep, no monitor off)
  ${WORK_END}:00 ~ $($WORK_START-1):59  ->  Monitor off ${MONITOR_OFF}min, sleep ${SLEEP_AFTER}min
  Checks every ${intervalMin} minutes
  WakeToRun enabled

  Verify
  ------
  powercfg /list
  powercfg /getactivescheme
  schtasks /query /tn PowerPlan-AutoSwitch

  Uninstall
  ---------
  .\setup.ps1 -delete
"@
