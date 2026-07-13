use crate::config::DDNS_UPDATE_URL;
use std::process::Command;

pub fn refresh_ip() -> Result<String, String> {
    let script = format!(
        "(Invoke-WebRequest -UseBasicParsing -Uri '{url}').Content",
        url = DDNS_UPDATE_URL
    );

    let output = Command::new("powershell")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            &script,
        ])
        .output()
        .map_err(|error| format!("Failed to start PowerShell: {error}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        return Err(if stderr.is_empty() { stdout } else { stderr });
    }

    if stdout.is_empty() {
        return Err("Empty response from DDNS server.".to_string());
    }

    Ok(stdout)
}
