# Power Schedule

Windows 전원 계획을 시간대별로 자동 전환하는 PowerShell 도구입니다.

A PowerShell tool that automatically switches Windows power plans based on time of day.

---

## 한국어

### 개요

업무 시간과 비업무 시간에 각각 다른 전원 설정(모니터 꺼짐, 절전/최대 절전/끄기)을 자동 적용합니다. Windows 작업 스케줄러를 통해 주기적으로 실행됩니다.

### 설정 항목

설치 시 업무/비업무 시간 각각에 대해 다음을 개별 설정할 수 있습니다:

| 항목 | 업무 시간 기본값 | 비업무 시간 기본값 |
|------|:---:|:---:|
| 모니터 꺼짐 | 15분 | 15분 |
| 절전 모드 (sleep / hibernate / off) | sleep | sleep |
| 절전 진입 시간 | 0분 (비활성) | 60분 |

추가 옵션:

| 항목 | 기본값 | 설명 |
|------|:---:|------|
| Wake to run | no | PC가 절전 중일 때 깨워서 전원 계획을 전환할지 여부. 끄면 절전 중에는 아무 동작도 하지 않습니다. |

### 설치

`power-schedule.ps1` 파일 하나만 있으면 됩니다. 관리자 권한 PowerShell에서 실행:

```powershell
.\power-schedule.ps1
```

설치 과정에서 대화형으로 모든 값을 입력받습니다. Enter를 누르면 기본값이 적용됩니다.

### 상태 확인

이미 설치된 상태에서 다시 실행하면 현재 설정을 보여줍니다:

```powershell
.\power-schedule.ps1
```

### 재설치 / 삭제

```powershell
# 설정 변경 (재설치)
.\power-schedule.ps1 -force

# 완전 삭제
.\power-schedule.ps1 -delete
```

### 파일 구성

| 파일 | 설명 |
|------|------|
| `power-schedule.ps1` | 설치 / 삭제 / 상태 확인 스크립트 |
| `switch-power-plan.ps1` | 작업 스케줄러가 주기적으로 실행하는 전환 스크립트 (설치 시 자동 생성) |

---

## English

### Overview

Automatically applies different power settings (monitor timeout, sleep/hibernate/off) for work hours and off hours. Runs periodically via Windows Task Scheduler.

### Configuration

During setup, each time period can be configured independently:

| Setting | Work hours default | Off hours default |
|---------|:---:|:---:|
| Monitor off | 15 min | 15 min |
| Suspend mode (sleep / hibernate / off) | sleep | sleep |
| Suspend after | 0 min (disabled) | 60 min |

Additional options:

| Setting | Default | Description |
|---------|:---:|-------------|
| Wake to run | no | Whether to wake the PC from sleep to switch power plans. When off, does nothing while the PC is sleeping. |

### Installation

Only `power-schedule.ps1` is needed. Run in an elevated (Administrator) PowerShell:

```powershell
.\power-schedule.ps1
```

The installer prompts for all values interactively. Press Enter to accept defaults.

### Check Status

Running setup again when already installed shows current settings:

```powershell
.\power-schedule.ps1
```

### Reinstall / Uninstall

```powershell
# Change settings (reinstall)
.\power-schedule.ps1 -force

# Full uninstall
.\power-schedule.ps1 -delete
```

### Files

| File | Description |
|------|-------------|
| `power-schedule.ps1` | Install / uninstall / status script |
| `switch-power-plan.ps1` | Switching script executed periodically by Task Scheduler (auto-generated on install) |

---

## License

MIT
