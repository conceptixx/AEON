# bootstrap.ps1
# AEON Windows Bootstrap -> WSL (Ubuntu-22.04) -> Linux bootstrap (bash)
# Flags/Caps:
#   -c/-C/--cli-enable/--enable-cli
#   -w/-W/--web-enable/--enable-web
#   -n/-N/--noninteractive
# Unknown flag => usage + exit 1
# No -h/--help on purpose

$ErrorActionPreference = "Stop"

function bootstrap_main {
  function usage {
    @"
AEON bootstrap flags:
  -c | -C | --cli-enable | --enable-cli         Enable CLI/TUI capability setup
  -w | -W | --web-enable | --enable-web         Enable WebUI capability setup
  -n | -N | --noninteractive                    Noninteractive mode

Unknown flags will show this screen and exit with code 1.
"@ | Write-Host
  }

  function is_admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  }

  function need_cmd([string]$cmd) {
    return $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
  }

  function parse_flags([string[]]$argv) {
    $cli = $false
    $web = $false
    $non = $false

    foreach ($a in $argv) {
      switch -Regex ($a) {
        '^-c$|^-C$|^--cli-enable$|^--enable-cli$' { $cli = $true; continue }
        '^-w$|^-W$|^--web-enable$|^--enable-web$' { $web = $true; continue }
        '^-n$|^-N$|^--noninteractive$'            { $non = $true; continue }
        default {
          usage
          exit 1
        }
      }
    }

    return [PSCustomObject]@{
      CLI = $cli
      WEB = $web
      NON = $non
    }
  }

  function wsl_available {
    if (-not (need_cmd "wsl.exe")) { return $false }
    try {
      & wsl.exe --status *> $null
      return $true
    } catch {
      return $false
    }
  }

  function ensure_wsl_and_distro([string]$distro) {
    if (-not (need_cmd "wsl.exe")) {
      Write-Host "[aeon-bootstrap][ERROR] wsl.exe not found. Your Windows version may not support WSL."
      exit 4
    }

    # If WSL isn't initialized, we try to install it (may require admin + reboot).
    if (-not (wsl_available)) {
      if (-not (is_admin)) {
        Write-Host "[aeon-bootstrap] WSL not available yet. Relaunching as Administrator to install WSL..."
        $args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$PSCommandPath) + $global:AEON_ORIG_ARGS
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $args
        exit 0
      }

      Write-Host "[aeon-bootstrap] Installing WSL (this may take a while and might require a reboot)..."
      try {
        & wsl.exe --install | Write-Host
      } catch {
        Write-Host "[aeon-bootstrap][ERROR] WSL install failed: $($_.Exception.Message)"
        exit 10
      }

      Write-Host "[aeon-bootstrap] WSL install initiated. If Windows asks for a reboot, reboot and run this again."
      exit 0
    }

    # Best-effort update (won't hurt if already up to date)
    try {
      Write-Host "[aeon-bootstrap] Updating WSL (best-effort)..."
      & wsl.exe --update | Out-Null
    } catch {
      # ignore update errors; some systems restrict it
    }

    # Ensure distro exists
    $list = @()
    try { $list = & wsl.exe -l -q 2>$null } catch { $list = @() }

    $installed = $false
    foreach ($line in $list) {
      if ($line.Trim() -eq $distro) { $installed = $true; break }
    }

    if (-not $installed) {
      Write-Host "[aeon-bootstrap] Installing distro: $distro"
      try {
        & wsl.exe --install -d $distro | Write-Host
      } catch {
        Write-Host "[aeon-bootstrap][ERROR] Distro install failed: $($_.Exception.Message)"
        exit 11
      }

      Write-Host "[aeon-bootstrap] Distro install initiated."
      Write-Host "[aeon-bootstrap] If this is the first install, open '$distro' once from the Start Menu to complete user setup,"
      Write-Host "[aeon-bootstrap] then run this bootstrap again."
      exit 0
    }
  }

  function build_linux_args($caps) {
    $args = New-Object System.Collections.Generic.List[string]
    if ($caps.CLI) { $args.Add("-c") }
    if ($caps.WEB) { $args.Add("-w") }
    if ($caps.NON) { $args.Add("-n") }
    return $args.ToArray()
  }

  function build_linux_env($caps) {
    # Extra redundancy: also export ENV vars inside WSL
    $envParts = New-Object System.Collections.Generic.List[string]
    if ($caps.CLI) { $envParts.Add("AEON_ENABLE_CLI=1") } else { $envParts.Add("AEON_ENABLE_CLI=0") }
    if ($caps.WEB) { $envParts.Add("AEON_ENABLE_WEB=1") } else { $envParts.Add("AEON_ENABLE_WEB=0") }
    if ($caps.NON) { $envParts.Add("AEON_NONINTERACTIVE=1") } else { $envParts.Add("AEON_NONINTERACTIVE=0") }
    return ($envParts -join " ")
  }

  function run_linux_bootstrap_in_wsl([string]$distro, [string]$linuxBootstrapUrl, [string[]]$linuxArgs, [string]$linuxEnv) {
    # Important:
    # - Use bash -lc for a clean login shell
    # - Use "bash -- <args>" so -c/-w/-n are script args, not bash options
    $argStr = ""
    if ($linuxArgs.Count -gt 0) { $argStr = ($linuxArgs -join " ") }

    $cmd = @"
set -e
$linuxEnv
export $linuxEnv
curl -fsSL '$linuxBootstrapUrl' | bash -- $argStr
"@

    Write-Host "[aeon-bootstrap] Starting Linux bootstrap inside WSL ($distro)..."
    & wsl.exe -d $distro -- bash -lc $cmd
    exit $LASTEXITCODE
  }

  function main([string[]]$argv) {
    # === CONFIG ===
    $Distro = "Ubuntu-22.04"
    $LinuxBootstrapUrl = "https://YOUR.DOMAIN/bootstrap"  # <- set this to your One-URL or bootstrap.sh URL
    # ==============

    $caps = parse_flags $argv

    ensure_wsl_and_distro $Distro

    $linuxArgs = build_linux_args $caps
    $linuxEnv  = build_linux_env  $caps

    run_linux_bootstrap_in_wsl $Distro $LinuxBootstrapUrl $linuxArgs $linuxEnv
  }

  # Preserve original args (used for admin relaunch)
  $global:AEON_ORIG_ARGS = $args

  main $args
}

bootstrap_main