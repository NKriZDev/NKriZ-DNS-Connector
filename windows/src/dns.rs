use crate::config::{PRIMARY_DNS, SECONDARY_DNS};
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::OnceLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DnsMode {
    Automatic,
    Custom,
    Mixed,
    Unknown,
}

#[derive(Debug, Clone)]
pub struct DnsStatus {
    pub mode: DnsMode,
    pub message: String,
}

pub fn refresh_status() -> DnsStatus {
    match read_status_powershell() {
        Ok(status) => status,
        Err(error) => DnsStatus {
            mode: DnsMode::Unknown,
            message: format!("Status error: {error}"),
        },
    }
}

pub fn apply_custom_dns() -> Result<String, String> {
    let script = format!(
        r#"
$ErrorActionPreference = 'Stop'
$log = '{log}'
try {{
  $adapters = @(Get-NetAdapter | Where-Object {{ $_.Status -eq 'Up' }} | Select-Object -ExpandProperty Name)
  if ($adapters.Count -eq 0) {{ throw 'No active network adapters found.' }}
  foreach ($alias in $adapters) {{
    Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses @('{primary}','{secondary}')
  }}
  'OK: NKriZ DNS applied on ' + ($adapters -join ', ')
}} catch {{
  $_.Exception.Message
}} | Out-File -FilePath $log -Encoding utf8
"#,
        log = result_log_path().display(),
        primary = PRIMARY_DNS,
        secondary = SECONDARY_DNS,
    );

    run_elevated_powershell(&script)?;
    read_result_log()
}

pub fn apply_automatic_dns() -> Result<String, String> {
    let script = format!(
        r#"
$ErrorActionPreference = 'Stop'
$log = '{log}'
try {{
  $adapters = @(Get-NetAdapter | Where-Object {{ $_.Status -eq 'Up' }} | Select-Object -ExpandProperty Name)
  if ($adapters.Count -eq 0) {{ throw 'No active network adapters found.' }}
  foreach ($alias in $adapters) {{
    Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses
  }}
  'OK: Automatic DNS restored on ' + ($adapters -join ', ')
}} catch {{
  $_.Exception.Message
}} | Out-File -FilePath $log -Encoding utf8
"#,
        log = result_log_path().display(),
    );

    run_elevated_powershell(&script)?;
    read_result_log()
}

fn read_status_powershell() -> Result<DnsStatus, String> {
    let script = format!(
        r#"
$primary = '{primary}'
$secondary = '{secondary}'
$adapters = @(Get-NetAdapter | Where-Object {{ $_.Status -eq 'Up' }} | Select-Object -ExpandProperty Name)
if ($adapters.Count -eq 0) {{
  Write-Output 'UNKNOWN|No active network adapters found.'
  exit 0
}}

$modes = @()
foreach ($alias in $adapters) {{
  $dns = @(Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
  $dns = @($dns | Where-Object {{ $_ }})
  if ($dns.Count -eq 2 -and $dns[0] -eq $primary -and $dns[1] -eq $secondary) {{
    $modes += 'CUSTOM'
  }} else {{
    $modes += 'OTHER'
  }}
}}

if (@($modes | Select-Object -Unique).Count -eq 1 -and $modes[0] -eq 'CUSTOM') {{
  Write-Output ('CUSTOM|NKriZ DNS active on ' + ($adapters -join ', '))
}} elseif (@($modes | Select-Object -Unique).Count -eq 1 -and $modes[0] -eq 'OTHER') {{
  Write-Output ('AUTOMATIC|Automatic DNS active on ' + ($adapters -join ', '))
}} else {{
  Write-Output ('MIXED|Mixed DNS settings across adapters: ' + ($adapters -join ', '))
}}
"#,
        primary = PRIMARY_DNS,
        secondary = SECONDARY_DNS,
    );

    let output = run_powershell(&script)?;
    parse_status_line(&output)
}

fn parse_status_line(raw: &str) -> Result<DnsStatus, String> {
    let line = raw
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or_default();

    let (mode_token, message) = line
        .split_once('|')
        .ok_or_else(|| format!("Unexpected status output: {raw}"))?;

    let mode = match mode_token {
        "CUSTOM" => DnsMode::Custom,
        "AUTOMATIC" => DnsMode::Automatic,
        "MIXED" => DnsMode::Mixed,
        _ => DnsMode::Unknown,
    };

    Ok(DnsStatus {
        mode,
        message: message.to_string(),
    })
}

fn run_powershell(script: &str) -> Result<String, String> {
    let output = Command::new("powershell")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ])
        .output()
        .map_err(|error| format!("Failed to start PowerShell: {error}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        if stderr.is_empty() {
            return Err(if stdout.is_empty() {
                "PowerShell command failed.".to_string()
            } else {
                stdout
            });
        }
        return Err(stderr);
    }

    if stdout.is_empty() && !stderr.is_empty() {
        return Err(stderr);
    }

    Ok(stdout)
}

fn run_elevated_powershell(script: &str) -> Result<(), String> {
    let log_path = result_log_path();
    let _ = fs::remove_file(&log_path);

    let escaped_script = script.replace('\'', "''");
    let launcher = format!(
        "$p = Start-Process powershell -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command','{escaped_script}'); exit $p.ExitCode"
    );

    let output = Command::new("powershell")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            &launcher,
        ])
        .output()
        .map_err(|error| format!("Failed to request administrator privileges: {error}"))?;

    if output.status.code() == Some(1223) {
        return Err("Administrator authorization was cancelled.".to_string());
    }

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            "Elevated PowerShell command failed.".to_string()
        } else {
            stderr
        });
    }

    Ok(())
}

fn read_result_log() -> Result<String, String> {
    let log_path = result_log_path();
    let content = fs::read_to_string(&log_path)
        .map_err(|error| format!("Failed to read command result: {error}"))?
        .trim()
        .trim_start_matches('\u{feff}')
        .to_string();

    if content.is_empty() {
        return Err("Elevated command returned no output.".to_string());
    }

    if let Some(rest) = content.strip_prefix("OK: ") {
        return Ok(rest.to_string());
    }

    Err(content)
}

fn result_log_path() -> PathBuf {
    static LOG_PATH: OnceLock<PathBuf> = OnceLock::new();
    LOG_PATH
        .get_or_init(|| {
            std::env::temp_dir().join("nkriz-dns-connector-result.txt")
        })
        .clone()
}

pub fn is_ip_address(text: &str) -> bool {
    let parts: Vec<&str> = text.trim().split('.').collect();
    if parts.len() != 4 {
        return false;
    }

    parts.iter().all(|part| {
        if part.is_empty() || part.len() > 3 {
            return false;
        }
        if !part.chars().all(|ch| ch.is_ascii_digit()) {
            return false;
        }
        match part.parse::<u16>() {
            Ok(value) => value <= 255,
            Err(_) => false,
        }
    })
}
