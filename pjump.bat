@echo off
setlocal EnableDelayedExpansion

REM =============================================================
REM pjump.bat
REM
REM Purpose:
REM   Proxy command helper for plink that supports multi-hop jump hosts.
REM   It composes a nested plink -proxycmd chain in memory and then
REM   asks the last jump to open a raw TCP stream to destination.
REM
REM Intended usage (from another plink command):
REM   plink -proxycmd "pjump.bat -J user@gw1 -J user@gw2 %%host %%port" user@server
REM
REM Notes:
REM   - This script is designed to be used as proxycmd.
REM   - It expects destination host and port as the last arguments.
REM   - No temporary hop_*.bat files are created.
REM
REM Supported input format:
REM   %~nx0 [--debug] -J [user@]host[:port] [-J [user@]host[:port] ...] host port
REM
REM Common examples:
REM   Single jump:
REM     plink -proxycmd "pjump.bat -J bastion@gw1.example.net %%host %%port" app@server.example.net
REM
REM   Two jumps:
REM     plink -proxycmd "pjump.bat -J bastion@gw1.example.net -J relay@gw2.example.net %%host %%port" app@server.example.net
REM
REM   Two jumps with custom port on second jump:
REM     plink -proxycmd "pjump.bat -J bastion@gw1.example.net -J relay@gw2.example.net:2222 %%host %%port" app@server.example.net
REM
REM Troubleshooting:
REM   - "plink is not recognized":
REM       Ensure plink.exe is available in PATH or current directory.
REM
REM   - Authentication fails on a hop:
REM       Validate username/key and test each hop manually with plink.
REM
REM   - Timeout or target unreachable:
REM       Verify routing/firewall and each hop host:port.
REM
REM High-level flow:
REM   1) Parse --debug, repeated -J hops, and destination host/port.
REM   2) Normalize hops into plink arguments (including optional -P).
REM   3) Build nested proxy chain:
REM        plink -proxycmd "...previous chain..." <hopN> -nc %%host:%%port
REM   4) Execute final plink through last hop to destination host:port.
REM =============================================================

set JUMP_COUNT=0
set TARGET_HOST=
set TARGET_PORT=
set DEBUG=0

REM Runtime state:
REM   JUMP_RAW_N = raw hop input from each -J argument
REM   JUMP_PLK_N = plink-ready hop argument string
REM   PROXY_CHAIN = nested plink -proxycmd expression for intermediate hops

:parse
REM Parse arguments in a single pass.
REM Accepted tokens:
REM   --debug
REM   -J <hop>
REM   <target-host> <target-port>
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
    set JUMP_RAW_!JUMP_COUNT!=%~2
    shift
    shift
    goto parse
)

if not defined TARGET_HOST (
    set TARGET_HOST=%~1
) else if not defined TARGET_PORT (
    set TARGET_PORT=%~1
) else (
    echo Error: Unexpected extra argument: %~1 1>&2
    echo Usage: %~nx0 [--debug] -J [user@]host[:port] [-J [user@]host[:port] ...] host port 1>&2
    exit /b 1
)
shift
goto parse

:end_parse

if %JUMP_COUNT%==0 (
    echo Error: At least one -J hop is required. 1>&2
    echo Usage: %~nx0 [--debug] -J [user@]host[:port] [-J [user@]host[:port] ...] host port 1>&2
    exit /b 1
)

if not defined TARGET_HOST (
    echo Error: Missing destination host. 1>&2
    echo Usage: %~nx0 [--debug] -J [user@]host[:port] [-J [user@]host[:port] ...] host port 1>&2
    exit /b 1
)

if not defined TARGET_PORT (
    REM Fallback for manual invocation: allow host:port in one token.
    REM Normal plink proxycmd invocation provides host and port separately.
    call :split_host_port "%TARGET_HOST%" TARGET_HOST TARGET_PORT
)

if not defined TARGET_PORT set TARGET_PORT=22

REM Normalize all jump definitions to plink-ready format.
REM Example conversion:
REM   user@gw2.example.net:2222 -> user@gw2.example.net -P 2222
REM   user@gw1.example.net      -> user@gw1.example.net
for /l %%I in (1,1,%JUMP_COUNT%) do (
    call :parse_addr "!JUMP_RAW_%%I!" TMP_PLK
    set JUMP_PLK_%%I=!TMP_PLK!
)

REM Single jump: direct nc from jump host to destination.
if %JUMP_COUNT%==1 (
    if "%DEBUG%"=="1" (
        echo [debug] Single-hop command:
        echo plink !JUMP_PLK_1! -nc %TARGET_HOST%:%TARGET_PORT%
        exit /b 0
    )
    cmd /c plink !JUMP_PLK_1! -nc %TARGET_HOST%:%TARGET_PORT%
    exit /b %errorlevel%
)

REM Build proxy chain to reach hop(N-1) using placeholders expected by plink.
REM The chain starts at hop1 and grows until hop(N-1).
REM Final hop N is executed separately as the outer plink call.
REM
REM For jumps gw1, gw2, gw3:
REM   PROXY_CHAIN becomes:
REM     plink -proxycmd "plink user@gw1 -nc %%host:%%port" user@gw2 -nc %%host:%%port
REM   Final call then uses PROXY_CHAIN to reach gw3, and gw3 does -nc target.
set "PROXY_CHAIN=plink !JUMP_PLK_1! -nc %%host:%%port"
set /a LAST_PREV=%JUMP_COUNT%-1
for /l %%I in (2,1,!LAST_PREV!) do (
    set "PROXY_CHAIN=plink -proxycmd ""!PROXY_CHAIN!"" !JUMP_PLK_%%I! -nc %%host:%%port"
)

REM Connect to final jump through chain, then open raw TCP stream to destination.
if "%DEBUG%"=="1" (
    echo [debug] Proxy chain command:
    echo !PROXY_CHAIN!
    echo [debug] Final command:
    echo plink -proxycmd "!PROXY_CHAIN!" !JUMP_PLK_%JUMP_COUNT%! -nc %TARGET_HOST%:%TARGET_PORT%
    exit /b 0
)

cmd /c plink -proxycmd "!PROXY_CHAIN!" !JUMP_PLK_%JUMP_COUNT%! -nc %TARGET_HOST%:%TARGET_PORT%
exit /b %errorlevel%


:parse_addr
REM -------------------------------------------------------------
REM parse_addr <raw_addr> <out_var>
REM
REM Input formats:
REM   host
REM   host:port
REM   user@host
REM   user@host:port
REM
REM Output written to <out_var>:
REM   user@host            if port is 22 or omitted
REM   user@host -P <port>  if non-default port
REM -------------------------------------------------------------
set "RAW_ADDR=%~1"
set "USER_PART="
set "HOST_PART="
set "PORT_PART=22"
set "HOSTPORT_PART="

echo !RAW_ADDR! | findstr /c:"@" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=1,* delims=@" %%a in ("!RAW_ADDR!") do (
        set "USER_PART=%%a@"
        set "HOSTPORT_PART=%%b"
    )
) else (
    set "HOSTPORT_PART=!RAW_ADDR!"
)

echo !HOSTPORT_PART! | findstr /c:":" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=1,2 delims=:" %%a in ("!HOSTPORT_PART!") do (
        set "HOST_PART=%%a"
        set "PORT_PART=%%b"
    )
) else (
    set "HOST_PART=!HOSTPORT_PART!"
)

if "!PORT_PART!"=="22" (
    set "%~2=!USER_PART!!HOST_PART!"
) else (
    set "%~2=!USER_PART!!HOST_PART! -P !PORT_PART!"
)
goto :eof


:split_host_port
REM -------------------------------------------------------------
REM split_host_port <in_addr> <out_host_var> <out_port_var>
REM
REM Utility fallback for manual script runs where destination may be
REM passed as one token, for example: server.example.net:2200
REM -------------------------------------------------------------
set "IN_ADDR=%~1"
set "OUT_HOST=%~1"
set "OUT_PORT="

echo !IN_ADDR! | findstr /c:":" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=1,2 delims=:" %%a in ("!IN_ADDR!") do (
        set "OUT_HOST=%%a"
        set "OUT_PORT=%%b"
    )
)

set "%~2=!OUT_HOST!"
set "%~3=!OUT_PORT!"
goto :eof
