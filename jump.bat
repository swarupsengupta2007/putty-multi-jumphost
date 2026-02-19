@echo off
setlocal enabledelayedexpansion

REM =============================================================
REM jump.bat
REM
REM Purpose:
REM   Proxy command helper for plink that supports repeated -J jump
REM   hosts and forwards to destination host/port provided by plink.
REM
REM Output behavior:
REM   - On success: runs ssh as proxy transport for plink.
REM   - On validation error: prints message to stderr and exits non-zero.
REM   - In --debug mode: prints resolved ssh command and exits 0.
REM
REM Supported input format:
REM   %~nx0 -J [user@]host[:port] [-J [user@]host[:port] ...] host port
REM
REM Intended usage (from another plink command):
REM   plink -proxycmd "jump.bat -J user@gw1 -J user@gw2 %%host %%port" user@server
REM
REM Common examples:
REM   Single jump:
REM     plink -proxycmd "jump.bat -J bastion@gw1.example.net %%host %%port" app@server.example.net
REM
REM   Two jumps:
REM     plink -proxycmd "jump.bat -J bastion@gw1.example.net -J relay@gw2.example.net %%host %%port" app@server.example.net
REM
REM   Two jumps with custom port on last jump host:
REM     plink -proxycmd "jump.bat -J bastion@gw1.example.net -J relay@gw2.example.net:2222 %%host %%port" app@server.example.net
REM
REM Troubleshooting:
REM   - "ssh is not recognized":
REM       Ensure OpenSSH client is installed and ssh.exe is in PATH.
REM
REM   - Authentication fails on a jump host:
REM       Validate usernames/keys and test each hop manually with ssh.
REM
REM   - Timeout or unreachable destination:
REM       Verify routing/firewall and host/port values for each stage.
REM
REM High-level flow:
REM   1) Parse repeated -J hops and destination host/port.
REM   2) Use the last -J host as final ssh endpoint.
REM   3) Use earlier -J hosts as a comma-separated ssh -J list.
REM   4) Execute ssh -W host:port final_host with optional -J list.
REM =============================================================

REM Proxy command script for plink with repeated -J jump hosts.
REM Usage: plink -proxycmd "jump.bat -J gw1 -J gw2 %%host %%port" user@server
REM Transforms: -J gw1 -J gw2 -> ssh -J gw1 -W host:port gw2

set JUMP_COUNT=0
set TARGET_HOST=
set TARGET_PORT=
set DEBUG=0

REM Runtime variables populated after parsing:
REM   JUMP[N]     = Nth jump host argument from -J
REM   FINAL_HOST  = last jump host (actual ssh endpoint)
REM   JUMP_LIST   = comma-separated intermediate jumps for ssh -J

:parse
REM Parse arguments:
REM - Every "-J <hop>" is stored as JUMP[N].
REM - Remaining two args are destination host and port.
REM - Optional --debug can appear before other arguments.
if "%~1"=="" goto end_parse

if /i "%~1"=="--debug" (
    set DEBUG=1
    shift
    goto parse
)

if /i "%~1"=="-J" (
    if "%~2"=="" (
        echo Error: -J requires an argument 1>&2
        exit /b 1
    )
    set /a JUMP_COUNT+=1
    set "JUMP[!JUMP_COUNT!]=%~2"
    shift
    shift
    goto parse
)

if not defined TARGET_HOST (
    set "TARGET_HOST=%~1"
) else if not defined TARGET_PORT (
    set "TARGET_PORT=%~1"
) else (
    echo Error: Unexpected extra argument: %~1 1>&2
    echo Usage: %~nx0 [--debug] -J host1 [-J host2 ...] host port 1>&2
    exit /b 1
)

shift
goto parse

:end_parse

REM Require at least one jump host in proxy mode.
REM plink proxycmd calls this script with destination host/port, but
REM jump path definition still requires at least one -J value.
if %JUMP_COUNT% LSS 1 (
    echo Error: At least one -J jump host is required 1>&2
    echo Usage: %~nx0 [--debug] -J host1 [-J host2 ...] host port 1>&2
    exit /b 1
)

if not defined TARGET_HOST (
    echo Error: Missing destination host 1>&2
    echo Usage: %~nx0 [--debug] -J host1 [-J host2 ...] host port 1>&2
    exit /b 1
)

if not defined TARGET_PORT (
    echo Error: Missing destination port 1>&2
    echo Usage: %~nx0 [--debug] -J host1 [-J host2 ...] host port 1>&2
    exit /b 1
)

REM Final SSH target is the last jump host.
REM All preceding jump hosts become the ssh -J chain.
REM Example:
REM   -J gw1 -J gw2 -J gw3 host port
REM   FINAL_HOST=gw3
REM   JUMP_LIST=gw1,gw2
call set "FINAL_HOST=%%JUMP[%JUMP_COUNT%]%%"
set "JUMP_LIST="

if %JUMP_COUNT% GTR 1 (
    set /a LAST_JUMP=%JUMP_COUNT%-1
    for /l %%i in (1,1,!LAST_JUMP!) do (
        call set "CURRENT_JUMP=%%JUMP[%%i]%%"
        if defined JUMP_LIST (
            set "JUMP_LIST=!JUMP_LIST!,!CURRENT_JUMP!"
        ) else (
            set "JUMP_LIST=!CURRENT_JUMP!"
        )
    )
)

REM Build SSH command
REM ssh -W host:port asks FINAL_HOST to open a raw TCP stream to host:port.
REM If JUMP_LIST exists, ssh reaches FINAL_HOST through ssh -J first.
if "%JUMP_LIST%"=="" (
    REM Only one host - no -J needed
    if "%DEBUG%"=="1" (
        echo [debug] ssh -W %TARGET_HOST%:%TARGET_PORT% %FINAL_HOST%
        exit /b 0
    )
    ssh -W %TARGET_HOST%:%TARGET_PORT% %FINAL_HOST%
) else (
    REM Multiple hosts - use -J for intermediate jumps
    if "%DEBUG%"=="1" (
        echo [debug] ssh -J "%JUMP_LIST%" -W %TARGET_HOST%:%TARGET_PORT% %FINAL_HOST%
        exit /b 0
    )
    ssh -J "%JUMP_LIST%" -W %TARGET_HOST%:%TARGET_PORT% %FINAL_HOST%
)

endlocal
