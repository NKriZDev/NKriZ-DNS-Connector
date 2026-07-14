use crate::config::{PRIMARY_DNS, SECONDARY_DNS};
use std::fs;
use std::io::Write;
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
    match read_status() {
        Ok(status) => status,
        Err(error) => DnsStatus {
            mode: DnsMode::Unknown,
            message: format!("Status error: {error}"),
        },
    }
}

pub fn apply_custom_dns() -> Result<String, String> {
    let script = format!(
        r#"#!/bin/bash
set -euo pipefail
log='{log}'
connections=()
while IFS= read -r line; do
  [ -n "$line" ] && connections+=("$line")
done < <(nmcli -t -f NAME connection show --active)

if [ "${{#connections[@]}}" -eq 0 ]; then
  echo "No active network connections found." > "$log"
  exit 1
fi

for conn in "${{connections[@]}}"; do
  nmcli connection modify "$conn" ipv4.dns "{primary},{secondary}"
  nmcli connection modify "$conn" ipv4.ignore-auto-dns yes
  nmcli connection up "$conn" >/dev/null
done

echo "OK: NKriZ DNS applied on ${{connections[*]}}" > "$log"
"#,
        log = result_log_path().display(),
        primary = PRIMARY_DNS,
        secondary = SECONDARY_DNS,
    );

    run_elevated_script(&script)?;
    read_result_log()
}

pub fn apply_automatic_dns() -> Result<String, String> {
    let script = format!(
        r#"#!/bin/bash
set -euo pipefail
log='{log}'
connections=()
while IFS= read -r line; do
  [ -n "$line" ] && connections+=("$line")
done < <(nmcli -t -f NAME connection show --active)

if [ "${{#connections[@]}}" -eq 0 ]; then
  echo "No active network connections found." > "$log"
  exit 1
fi

for conn in "${{connections[@]}}"; do
  nmcli connection modify "$conn" ipv4.dns ""
  nmcli connection modify "$conn" ipv4.ignore-auto-dns no
  nmcli connection up "$conn" >/dev/null
done

echo "OK: Automatic DNS restored on ${{connections[*]}}" > "$log"
"#,
        log = result_log_path().display(),
    );

    run_elevated_script(&script)?;
    read_result_log()
}

fn read_status() -> Result<DnsStatus, String> {
    let connections = active_connections()?;
    if connections.is_empty() {
        return Ok(DnsStatus {
            mode: DnsMode::Unknown,
            message: "No active network connections found".to_string(),
        });
    }

    let mut modes = Vec::new();
    for conn in &connections {
        let dns = dns_for_connection(conn)?;
        if dns.len() == 2 && dns[0] == PRIMARY_DNS && dns[1] == SECONDARY_DNS {
            modes.push(DnsMode::Custom);
        } else {
            modes.push(DnsMode::Automatic);
        }
    }

    let all_custom = modes.iter().all(|mode| *mode == DnsMode::Custom);
    let all_automatic = modes.iter().all(|mode| *mode == DnsMode::Automatic);

    let (mode, message) = if all_custom {
        (
            DnsMode::Custom,
            format!("NKriZ DNS active on {}", connections.join(", ")),
        )
    } else if all_automatic {
        (
            DnsMode::Automatic,
            format!("Automatic DNS active on {}", connections.join(", ")),
        )
    } else {
        (
            DnsMode::Mixed,
            format!("Mixed DNS settings across connections: {}", connections.join(", ")),
        )
    };

    Ok(DnsStatus { mode, message })
}

fn active_connections() -> Result<Vec<String>, String> {
    let output = run_command(
        Command::new("nmcli").args([
            "-t",
            "-f",
            "NAME",
            "connection",
            "show",
            "--active",
        ]),
    )?;

    Ok(output
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect())
}

fn dns_for_connection(connection: &str) -> Result<Vec<String>, String> {
    let output = run_command(
        Command::new("nmcli").args([
            "-t",
            "-f",
            "ipv4.dns",
            "connection",
            "show",
            connection,
        ]),
    )?;

    let mut servers = Vec::new();
    for line in output.lines() {
        let line = line.trim();
        let Some(value) = line.strip_prefix("ipv4.dns:") else {
            continue;
        };
        if value.is_empty() {
            continue;
        }
        let normalized = value.replace(',', " ").replace(';', " ");
        for server in normalized.split_whitespace() {
            let server = server.trim();
            if !server.is_empty() {
                servers.push(server.to_string());
            }
        }
    }

    Ok(servers)
}

fn run_command(command: &mut Command) -> Result<String, String> {
    let output = command
        .output()
        .map_err(|error| format!("Failed to run command: {error}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        return Err(if stderr.is_empty() { stdout } else { stderr });
    }

    Ok(stdout)
}

fn run_elevated_script(script: &str) -> Result<(), String> {
    let log_path = result_log_path();
    let _ = fs::remove_file(&log_path);

    let script_path = temp_script_path();
    {
        let mut file = fs::File::create(&script_path)
            .map_err(|error| format!("Failed to create helper script: {error}"))?;
        file.write_all(script.as_bytes())
            .map_err(|error| format!("Failed to write helper script: {error}"))?;
    }

    let status = Command::new("pkexec")
        .arg("bash")
        .arg(&script_path)
        .status()
        .map_err(|error| format!("Failed to request administrator privileges: {error}"))?;

    let _ = fs::remove_file(&script_path);

    if status.code() == Some(126) || status.code() == Some(127) {
        return Err("Administrator authorization was cancelled.".to_string());
    }

    if !status.success() {
        return Err(read_result_log().unwrap_or_else(|_| {
            "Elevated command failed.".to_string()
        }));
    }

    Ok(())
}

fn read_result_log() -> Result<String, String> {
    let content = fs::read_to_string(result_log_path())
        .map_err(|error| format!("Failed to read command result: {error}"))?
        .trim()
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
        .get_or_init(|| std::env::temp_dir().join("nkriz-dns-connector-result.txt"))
        .clone()
}

fn temp_script_path() -> PathBuf {
    std::env::temp_dir().join("nkriz-dns-connector-action.sh")
}

pub fn is_ip_address(text: &str) -> bool {
    let parts: Vec<&str> = text.trim().split('.').collect();
    if parts.len() != 4 {
        return false;
    }

    parts.iter().all(|part| {
        !part.is_empty()
            && part.len() <= 3
            && part.chars().all(|ch| ch.is_ascii_digit())
            && part.parse::<u16>().is_ok_and(|value| value <= 255)
    })
}
