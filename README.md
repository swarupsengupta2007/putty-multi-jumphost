# SSH Jump Helpers for PuTTY and OpenSSH

This repository contains two Windows batch scripts for multi hop SSH access when using `plink -proxycmd`.

- `pjump.bat` builds a plink to plink proxy chain
- `jump.bat` delegates proxying to OpenSSH `ssh -J ... -W ...`

Both scripts accept repeated jump arguments in this style:

`-J gw1 -J gw2 -J gw3`

## Files

- `pjump.bat`: Proxy helper based on `plink`
- `jump.bat`: Proxy helper based on `ssh`

## Requirements

### For pjump.bat

- Windows `cmd.exe`
- `plink.exe` available in `PATH`, or in the current directory

### For jump.bat

- Windows `cmd.exe`
- OpenSSH client `ssh.exe` available in `PATH`

## Address Format

Each jump host can be written as:

- `host`
- `host:port`
- `user@host`
- `user@host:port`

Default port is `22` when no port is provided.

## Usage with plink -proxycmd

The scripts are intended to be used from another `plink` command.

General form:

`plink -proxycmd "<script>.bat -J <hop1> -J <hop2> %host %port" user@target`

Important:

- Use `%%host %%port` in a batch file
- Use `%host %port` directly in interactive `cmd`

### Examples with pjump.bat

Single jump:

`plink -proxycmd "pjump.bat -J bastion@gw1.example.net %host %port" app@server.example.net`

Two jumps:

`plink -proxycmd "pjump.bat -J bastion@gw1.example.net -J relay@gw2.example.net %host %port" app@server.example.net`

Two jumps with custom port on second jump:

`plink -proxycmd "pjump.bat -J bastion@gw1.example.net -J relay@gw2.example.net:2222 %host %port" app@server.example.net`

### Examples with jump.bat

Single jump:

`plink -proxycmd "jump.bat -J bastion@gw1.example.net %host %port" app@server.example.net`

Two jumps:

`plink -proxycmd "jump.bat -J bastion@gw1.example.net -J relay@gw2.example.net %host %port" app@server.example.net`

## Debug Mode

Both scripts support `--debug`.

- Prints the resolved proxy command
- Exits without opening a connection

Examples:

`plink -proxycmd "pjump.bat --debug -J u@gw1 -J u@gw2 %host %port" user@server`

`plink -proxycmd "jump.bat --debug -J u@gw1 -J u@gw2 %host %port" user@server`

## How the scripts differ

### pjump.bat

- Uses `plink` for each hop
- Builds nested `plink -proxycmd` commands
- Uses `-nc host:port` on the final hop

### jump.bat

- Uses OpenSSH `ssh`
- Uses last hop as the final SSH endpoint
- Uses previous hops as a comma separated `ssh -J` list
- Uses `ssh -W host:port`

## Troubleshooting

### "plink is not recognized"

- Add the PuTTY directory to `PATH`
- Or use full path to `plink.exe`

### "ssh is not recognized"

- Install OpenSSH Client in Windows optional features
- Confirm `ssh.exe` is in `PATH`

### Authentication failures

- Test each hop directly first
- Verify username, key, agent, and server policy

### Timeouts or unreachable hosts

- Check route and firewall rules
- Confirm hostnames and ports for all hops

## Quick test checklist

1. Validate tool presence:
   - `plink -V`
   - `ssh -V`
2. Test each hop manually
3. Run script with `--debug`
4. Run final `plink -proxycmd ...` command

## License

MIT Licensed
