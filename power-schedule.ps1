#Requires -RunAsAdministrator
# ============================================
# Power Plan Auto-Switch Setup
# ============================================

param(
    [switch]$delete,
    [switch]$force
)

$WORK_PLAN_NAME = "PowerSchedule-Work"
$OFF_PLAN_NAME  = "PowerSchedule-Off"
$LEGACY_PATTERN = 'PowerSchedule-Work|WorkHours-AlwaysOn'
$LEGACY_PATTERN_OFF = 'PowerSchedule-Off|OffHours-AllowSleep'

# --- Helper: find plan GUID by name pattern ---
function Find-PlanGuid {
    param([string]$namePattern)
    $plans = (powercfg /list) -join "`n"
    $m = [regex]::Match($plans, "([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}).*?($namePattern)")
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# --- Helper: read power settings from a plan ---
function Get-PlanSleepInfo {
    param([string]$guid)
    $info = @{ MonitorOff = 0; Mode = "off"; SuspendMin = 0 }

    $videoAC     = powercfg /query $guid SUB_VIDEO VIDEOIDLE     | Select-String 'AC.*(0x[0-9a-fA-F]+)'
    $standbyAC   = powercfg /query $guid SUB_SLEEP STANDBYIDLE   | Select-String 'AC.*(0x[0-9a-fA-F]+)'
    $hibernateAC = powercfg /query $guid SUB_SLEEP HIBERNATEIDLE  | Select-String 'AC.*(0x[0-9a-fA-F]+)'

    if ($videoAC) {
        $val = $videoAC.Matches[0].Groups[1].Value
        $info.MonitorOff = [math]::Round([convert]::ToInt32($val, 16) / 60)
    }
    if ($standbyAC) {
        $val = $standbyAC.Matches[0].Groups[1].Value
        $sec = [convert]::ToInt32($val, 16)
        if ($sec -gt 0) { $info.Mode = "sleep"; $info.SuspendMin = [math]::Round($sec / 60) }
    }
    if ($hibernateAC) {
        $val = $hibernateAC.Matches[0].Groups[1].Value
        $sec = [convert]::ToInt32($val, 16)
        if ($sec -gt 0) { $info.Mode = "hibernate"; $info.SuspendMin = [math]::Round($sec / 60) }
    }

    return $info
}

# --- Helper: apply power settings to a plan ---
function Set-PlanPower {
    param([string]$guid, [int]$monitorMin, [int]$suspendMin, [string]$mode)

    powercfg /setacvalueindex $guid SUB_VIDEO VIDEOIDLE ($monitorMin * 60)

    switch ($mode) {
        "sleep" {
            powercfg /setacvalueindex $guid SUB_SLEEP STANDBYIDLE ($suspendMin * 60)
            powercfg /setacvalueindex $guid SUB_SLEEP HIBERNATEIDLE 0
        }
        "hibernate" {
            powercfg /setacvalueindex $guid SUB_SLEEP STANDBYIDLE 0
            powercfg /setacvalueindex $guid SUB_SLEEP HIBERNATEIDLE ($suspendMin * 60)
        }
        default {
            powercfg /setacvalueindex $guid SUB_SLEEP STANDBYIDLE 0
            powercfg /setacvalueindex $guid SUB_SLEEP HIBERNATEIDLE 0
        }
    }
}

# --- Helper: format suspend label ---
function Format-SuspendLabel {
    param([string]$mode, [int]$min)
    if ($mode -eq "off" -or $min -eq 0) { return "off" }
    return "$mode ${min} min"
}

# ============================================
# Delete mode
# ============================================
if ($delete) {
    Write-Host "=== Power Plan Auto-Switch Uninstall ===" -ForegroundColor Red

    schtasks /delete /tn PowerPlan-AutoSwitch /f 2>$null
    if ($?) { Write-Host "  Task removed" -ForegroundColor Green }
    else    { Write-Host "  Task not found (already removed)" -ForegroundColor DarkYellow }

    $workGuid = Find-PlanGuid $LEGACY_PATTERN
    $offGuid  = Find-PlanGuid $LEGACY_PATTERN_OFF

    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e

    if ($workGuid) {
        powercfg /delete $workGuid
        Write-Host "  Deleted work plan: $workGuid" -ForegroundColor Green
    }
    if ($offGuid) {
        powercfg /delete $offGuid
        Write-Host "  Deleted off plan: $offGuid" -ForegroundColor Green
    }
    if (-not $workGuid -and -not $offGuid) {
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

# ============================================
# Status mode (already installed)
# ============================================
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$switchScript = Join-Path $scriptDir "switch-power-plan.ps1"
$taskExists = Get-ScheduledTask -TaskName "PowerPlan-AutoSwitch" -ErrorAction SilentlyContinue

if ($taskExists -and (Test-Path $switchScript) -and -not $force) {
    Write-Host "=== Power Plan Auto-Switch: Already Installed ===" -ForegroundColor Cyan

    $content = Get-Content $switchScript -Raw
    $ws = [regex]::Match($content, 'WORK_START\s*=\s*(\d+)').Groups[1].Value
    $we = [regex]::Match($content, 'WORK_END\s*=\s*(\d+)').Groups[1].Value

    $workGuid = Find-PlanGuid $LEGACY_PATTERN
    $offGuid  = Find-PlanGuid $LEGACY_PATTERN_OFF

    $workInfo = if ($workGuid) { Get-PlanSleepInfo $workGuid } else { @{MonitorOff="?"; Mode="?"; SuspendMin=0} }
    $offInfo  = if ($offGuid)  { Get-PlanSleepInfo $offGuid }  else { @{MonitorOff="?"; Mode="?"; SuspendMin=0} }

    $interval = $taskExists.Triggers[0].Repetition.Interval
    $intervalMatch = [regex]::Match($interval, 'PT(\d+)M')
    $intMin = if ($intervalMatch.Success) { $intervalMatch.Groups[1].Value } else { "?" }

    $activePlan = (powercfg /getactivescheme) -join " "
    $currentLabel = if ($activePlan -match 'PowerSchedule-Work|WorkHours-AlwaysOn') { "Work" }
                    elseif ($activePlan -match 'PowerSchedule-Off|OffHours-AllowSleep') { "Off" }
                    else { "Other" }

    Write-Host ""
    Write-Host "  Current Settings" -ForegroundColor White
    Write-Host "  ----------------"
    Write-Host "  Work hours:       ${ws}:00 ~ ${we}:00"
    Write-Host "    Monitor off:    $($workInfo.MonitorOff) min"
    Write-Host "    Suspend:        $(Format-SuspendLabel $workInfo.Mode $workInfo.SuspendMin)"
    Write-Host "  Off hours:"
    Write-Host "    Monitor off:    $($offInfo.MonitorOff) min"
    Write-Host "    Suspend:        $(Format-SuspendLabel $offInfo.Mode $offInfo.SuspendMin)"
    Write-Host "  Check interval:   every ${intMin} min"
    $wakeStatus = if ($taskExists.Settings.WakeToRun) { "yes" } else { "no" }
    Write-Host "  Wake to run:      $wakeStatus"
    Write-Host "  Active plan:      $currentLabel"
    Write-Host ""
    Write-Host "  To reinstall with new settings:  .\power-schedule.ps1 -force" -ForegroundColor DarkGray
    Write-Host "  To uninstall:                    .\power-schedule.ps1 -delete" -ForegroundColor DarkGray
    exit
}

# ============================================
# Install mode
# ============================================
Write-Host "=== Power Plan Auto-Switch Setup ===" -ForegroundColor Cyan
Write-Host "Press Enter to use default values.`n" -ForegroundColor DarkGray

$validModes = @("sleep", "hibernate", "off")

# --- Time range ---
$workStartInput = Read-Host "Work start hour [default: 9]"
$WORK_START = if ($workStartInput) { [int]$workStartInput } else { 9 }

$workEndInput = Read-Host "Work end hour   [default: 22]"
$WORK_END = if ($workEndInput) { [int]$workEndInput } else { 22 }

# --- Work hours settings ---
Write-Host "`n--- Work Hours Power Settings ---" -ForegroundColor White

$wMonInput = Read-Host "  Monitor off (min) [default: 15]"
$W_MONITOR = if ($wMonInput) { [int]$wMonInput } else { 15 }

$wModeInput = Read-Host "  Suspend mode (sleep/hibernate/off) [default: sleep]"
$W_MODE = if ($wModeInput) { $wModeInput.Trim().ToLower() } else { "sleep" }
if ($W_MODE -notin $validModes) {
    Write-Host "    Invalid mode '$W_MODE', using 'sleep'" -ForegroundColor DarkYellow
    $W_MODE = "sleep"
}

if ($W_MODE -ne "off") {
    $wSuspendInput = Read-Host "  $($W_MODE) after (min, 0=never) [default: 0]"
    $W_SUSPEND = if ($wSuspendInput) { [int]$wSuspendInput } else { 0 }
} else {
    $W_SUSPEND = 0
}

# --- Off hours settings ---
Write-Host "`n--- Off Hours Power Settings ---" -ForegroundColor White

$oMonInput = Read-Host "  Monitor off (min) [default: 15]"
$O_MONITOR = if ($oMonInput) { [int]$oMonInput } else { 15 }

$oModeInput = Read-Host "  Suspend mode (sleep/hibernate/off) [default: sleep]"
$O_MODE = if ($oModeInput) { $oModeInput.Trim().ToLower() } else { "sleep" }
if ($O_MODE -notin $validModes) {
    Write-Host "    Invalid mode '$O_MODE', using 'sleep'" -ForegroundColor DarkYellow
    $O_MODE = "sleep"
}

if ($O_MODE -ne "off") {
    $oSuspendInput = Read-Host "  $($O_MODE) after (min, 0=never) [default: 60]"
    $O_SUSPEND = if ($oSuspendInput) { [int]$oSuspendInput } else { 60 }
} else {
    $O_SUSPEND = 0
}

# --- Task options ---
Write-Host "`n--- Task Options ---" -ForegroundColor White
$wakeInput = Read-Host "  Wake to run (y/n) [default: n]"
$WAKE_TO_RUN = $wakeInput -match '^[yY]'

# --- Summary ---
$wSuspendLabel = Format-SuspendLabel $W_MODE $W_SUSPEND
$oSuspendLabel = Format-SuspendLabel $O_MODE $O_SUSPEND

Write-Host ""
Write-Host "  Work hours:       ${WORK_START}:00 ~ ${WORK_END}:00" -ForegroundColor White
Write-Host "    Monitor off:    ${W_MONITOR} min" -ForegroundColor White
Write-Host "    Suspend:        $wSuspendLabel" -ForegroundColor White
Write-Host "  Off hours:" -ForegroundColor White
Write-Host "    Monitor off:    ${O_MONITOR} min" -ForegroundColor White
Write-Host "    Suspend:        $oSuspendLabel" -ForegroundColor White
$wakeLabel = if ($WAKE_TO_RUN) { "yes" } else { "no" }
Write-Host "  Wake to run:      $wakeLabel" -ForegroundColor White

# ============================================
# 1. Create power plans
# ============================================
Write-Host "`n[1/4] Creating power plans..." -ForegroundColor Yellow

$workGuid = Find-PlanGuid $LEGACY_PATTERN
$offGuid  = Find-PlanGuid $LEGACY_PATTERN_OFF

if ($workGuid) {
    powercfg /changename $workGuid $WORK_PLAN_NAME "Work hours power plan"
    Write-Host "  Work plan exists: $workGuid" -ForegroundColor DarkYellow
} else {
    $workOutput = powercfg /duplicatescheme 381b4222-f694-41f0-9685-ff5bb260df2e
    $workGuid = [regex]::Match($workOutput, '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}').Value
    powercfg /changename $workGuid $WORK_PLAN_NAME "Work hours power plan"
    Write-Host "  Work plan created: $workGuid" -ForegroundColor Green
}

Set-PlanPower -guid $workGuid -monitorMin $W_MONITOR -suspendMin $W_SUSPEND -mode $W_MODE

if ($offGuid) {
    powercfg /changename $offGuid $OFF_PLAN_NAME "Off hours power plan"
    Write-Host "  Off plan exists: $offGuid" -ForegroundColor DarkYellow
} else {
    $offOutput = powercfg /duplicatescheme 381b4222-f694-41f0-9685-ff5bb260df2e
    $offGuid = [regex]::Match($offOutput, '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}').Value
    powercfg /changename $offGuid $OFF_PLAN_NAME "Off hours power plan"
    Write-Host "  Off plan created: $offGuid" -ForegroundColor Green
}

Set-PlanPower -guid $offGuid -monitorMin $O_MONITOR -suspendMin $O_SUSPEND -mode $O_MODE

# ============================================
# 2. Generate switch script
# ============================================
Write-Host "`n[2/4] Creating switch script..." -ForegroundColor Yellow

$mainScript = @"

# Power Plan Auto-Switch (runs periodically)

`$WORK_GUID  = "$workGuid"
`$OFF_GUID   = "$offGuid"
`$WORK_START = $WORK_START
`$WORK_END   = $WORK_END

`$hour = (Get-Date).Hour
`$currentPlan = (powercfg /getactivescheme) -replace '.*([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}).*', '`$1'

if (`$hour -ge `$WORK_START -and `$hour -lt `$WORK_END) {
    `$targetGuid = `$WORK_GUID
    `$label = "Work"
} else {
    `$targetGuid = `$OFF_GUID
    `$label = "Off"
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

# ============================================
# 3. Register scheduled task
# ============================================
Write-Host "`n[3/4] Registering scheduled task..." -ForegroundColor Yellow

$taskName = "PowerPlan-AutoSwitch"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$mainScriptPath`""

# Interval: half of smallest non-zero suspend time, min 5, default 15
$suspendTimes = @($W_SUSPEND, $O_SUSPEND) | Where-Object { $_ -gt 0 }
if ($suspendTimes.Count -gt 0) {
    $intervalMin = [math]::Max(5, [math]::Floor(($suspendTimes | Measure-Object -Minimum).Minimum / 2))
} else {
    $intervalMin = 15
}
Write-Host "  Check interval: every ${intervalMin} min" -ForegroundColor DarkGray

$trigger = New-ScheduledTaskTrigger -Daily -At "00:00"
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Minutes $intervalMin)).Repetition

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

if ($WAKE_TO_RUN) { $settings.WakeToRun = $true }

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -RunLevel Highest `
    -User "SYSTEM" `
    -Description "Auto-switch power plan (work: ${WORK_START}~${WORK_END}, interval: ${intervalMin}min)"

Write-Host "  Registered: $taskName" -ForegroundColor Green

# ============================================
# 4. Done
# ============================================
Write-Host "`n[4/4] Setup complete!" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Current Settings" -ForegroundColor White
Write-Host "  ----------------"
Write-Host "  Work hours:       ${WORK_START}:00 ~ ${WORK_END}:00"
Write-Host "    Monitor off:    ${W_MONITOR} min"
Write-Host "    Suspend:        $wSuspendLabel"
Write-Host "  Off hours:"
Write-Host "    Monitor off:    ${O_MONITOR} min"
Write-Host "    Suspend:        $oSuspendLabel"
Write-Host "  Check interval:   every ${intervalMin} min"
Write-Host "  Wake to run:      $wakeLabel"
Write-Host ""
Write-Host "  Verify:    powercfg /list" -ForegroundColor DarkGray
Write-Host "  Uninstall: .\power-schedule.ps1 -delete" -ForegroundColor DarkGray
