# Power Schedule

Windows 전원 계획을 시간대별로 자동 전환하는 PowerShell 도구입니다.

A PowerShell tool that automatically switches Windows power plans based on time of day.

---

## 한국어

### 개요

업무 시간에는 절전/모니터 꺼짐 없이 항상 켜짐 상태를 유지하고, 비업무 시간에는 자동으로 절전 모드로 전환합니다. Windows 작업 스케줄러를 통해 주기적으로 실행됩니다.

### 동작 방식

| 시간대 | 전원 계획 | 설명 |
|--------|-----------|------|
| 업무 시간 (기본 9:00~22:00) | WorkHours-AlwaysOn | 모니터 꺼짐 없음, 절전 없음 |
| 비업무 시간 | OffHours-AllowSleep | 모니터 꺼짐 30분, 절전 60분 (기본값) |

### 설치

관리자 권한 PowerShell에서 실행:

```powershell
.\setup.ps1
```

설치 중 다음 항목을 설정할 수 있습니다:
- 업무 시작/종료 시간
- 비업무 시간 모니터 꺼짐 시간
- 비업무 시간 절전 진입 시간

### 상태 확인

이미 설치된 상태에서 다시 실행하면 현재 설정을 보여줍니다:

```powershell
.\setup.ps1
```

### 재설치 / 삭제

```powershell
# 설정 변경 (재설치)
.\setup.ps1 -force

# 완전 삭제
.\setup.ps1 -delete
```

### 파일 구성

| 파일 | 설명 |
|------|------|
| `setup.ps1` | 설치/삭제/상태 확인 스크립트 |
| `switch-power-plan.ps1` | 작업 스케줄러가 주기적으로 실행하는 전환 스크립트 (설치 시 자동 생성) |

---

## English

### Overview

Keeps your PC always-on during work hours (no sleep, no monitor timeout) and automatically switches to a sleep-enabled power plan during off-hours. Runs periodically via Windows Task Scheduler.

### How It Works

| Time Period | Power Plan | Description |
|-------------|-----------|-------------|
| Work hours (default 9:00–22:00) | WorkHours-AlwaysOn | No monitor off, no sleep |
| Off hours | OffHours-AllowSleep | Monitor off 30min, sleep 60min (defaults) |

### Installation

Run in an elevated (Administrator) PowerShell:

```powershell
.\setup.ps1
```

During setup you can configure:
- Work start/end hours
- Off-hours monitor timeout
- Off-hours sleep timeout

### Check Status

Running setup again when already installed shows current settings:

```powershell
.\setup.ps1
```

### Reinstall / Uninstall

```powershell
# Change settings (reinstall)
.\setup.ps1 -force

# Full uninstall
.\setup.ps1 -delete
```

### Files

| File | Description |
|------|-------------|
| `setup.ps1` | Install / uninstall / status script |
| `switch-power-plan.ps1` | Switching script executed periodically by Task Scheduler (auto-generated on install) |

---

## License

MIT
