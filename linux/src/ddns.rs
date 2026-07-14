use crate::config::DDNS_UPDATE_URL;

pub fn refresh_ip() -> Result<String, String> {
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|error| format!("HTTP client error: {error}"))?;

    let response = client
        .get(DDNS_UPDATE_URL)
        .send()
        .map_err(|error| format!("Request failed: {error}"))?;

    let body = response
        .text()
        .map_err(|error| format!("Failed to read response: {error}"))?
        .trim()
        .to_string();

    if body.is_empty() {
        return Err("Empty response from DDNS server.".to_string());
    }

    Ok(body)
}
