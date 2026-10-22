#![cfg(windows)]

use serde::{Deserialize, Serialize};

const SHARE_API_URL: &str = "https://pasty.coderfather.com/api/share";
const SHARE_BASE_URL: &str = "https://pasty.coderfather.com/s/";

#[derive(Serialize)]
struct CreateShareRequest {
    content: String,
}

#[derive(Deserialize)]
struct CreateShareResponse {
    id: String,
    #[allow(dead_code)]
    url: String,
}

#[derive(Deserialize)]
struct ErrorResponse {
    error: String,
}

pub fn upload_share(content: &str) -> Result<String, String> {
    let request = CreateShareRequest {
        content: content.to_string(),
    };

    let body = serde_json::to_string(&request).map_err(|e| format!("序列化失败: {}", e))?;

    let response = ureq::post(SHARE_API_URL)
        .set("Content-Type", "application/json")
        .send_string(&body);

    match response {
        Ok(resp) => {
            let text = resp.into_string().map_err(|e| format!("读取响应失败: {}", e))?;
            let parsed: CreateShareResponse =
                serde_json::from_str(&text).map_err(|e| format!("解析响应失败: {}", e))?;
            Ok(format!("{}{}", SHARE_BASE_URL, parsed.id))
        }
        Err(ureq::Error::Status(status, resp)) => {
            let text = resp.into_string().unwrap_or_default();
            if let Ok(err) = serde_json::from_str::<ErrorResponse>(&text) {
                Err(err.error)
            } else {
                Err(format!("服务器错误 ({})", status))
            }
        }
        Err(e) => Err(format!("网络错误: {}", e)),
    }
}
