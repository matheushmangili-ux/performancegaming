//! Scan history persistence at %APPDATA%\gg.clockreaper.desktop\history\<id>.json.
//!
//! Each completed scan is stored as a `FullScanRecord` so the UI can replay
//! findings + hardware + summary in the /history route. `list_scans` returns
//! summaries only for the list view; `load_scan` fetches the full record.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, Runtime};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanSummary {
    pub id: String,
    /// ISO-8601 UTC.
    pub timestamp: String,
    pub profile: String,
    pub mode: String,
    pub score: i32,
    pub critical: i32,
    pub high: i32,
    pub medium: i32,
    pub total: i32,
    pub duration_ms: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FullScanRecord {
    pub summary: ScanSummary,
    pub hardware: serde_json::Value,
    pub findings: Vec<serde_json::Value>,
}

fn history_dir<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf, String> {
    let base = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("app_data_dir: {e}"))?;
    let dir = base.join("history");
    std::fs::create_dir_all(&dir).map_err(|e| format!("create_dir_all: {e}"))?;
    Ok(dir)
}

#[tauri::command]
pub async fn save_scan<R: Runtime>(
    app: AppHandle<R>,
    record: FullScanRecord,
) -> Result<(), String> {
    let dir = history_dir(&app)?;
    let filename = format!("{}.json", sanitize_id(&record.summary.id));
    let path = dir.join(filename);
    let json = serde_json::to_vec_pretty(&record).map_err(|e| format!("serialize: {e}"))?;
    std::fs::write(&path, json).map_err(|e| format!("write: {e}"))?;
    Ok(())
}

#[tauri::command]
pub async fn list_scans<R: Runtime>(app: AppHandle<R>) -> Result<Vec<ScanSummary>, String> {
    let dir = history_dir(&app)?;
    let mut entries: Vec<ScanSummary> = Vec::new();
    let read_dir = std::fs::read_dir(&dir).map_err(|e| format!("read_dir: {e}"))?;
    for entry in read_dir.flatten() {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("json") {
            continue;
        }
        let content = match std::fs::read_to_string(&path) {
            Ok(c) => c,
            Err(_) => continue,
        };
        match serde_json::from_str::<FullScanRecord>(&content) {
            Ok(record) => entries.push(record.summary),
            Err(_) => continue,
        }
    }
    entries.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    Ok(entries)
}

#[tauri::command]
pub async fn load_scan<R: Runtime>(
    app: AppHandle<R>,
    id: String,
) -> Result<FullScanRecord, String> {
    let dir = history_dir(&app)?;
    let path = dir.join(format!("{}.json", sanitize_id(&id)));
    let content = std::fs::read_to_string(&path).map_err(|e| format!("read: {e}"))?;
    serde_json::from_str::<FullScanRecord>(&content).map_err(|e| format!("parse: {e}"))
}

#[tauri::command]
pub async fn delete_scan<R: Runtime>(app: AppHandle<R>, id: String) -> Result<(), String> {
    let dir = history_dir(&app)?;
    let path = dir.join(format!("{}.json", sanitize_id(&id)));
    if path.exists() {
        std::fs::remove_file(&path).map_err(|e| format!("remove: {e}"))?;
    }
    Ok(())
}

/// Guards against accidental path traversal from user-supplied ids.
/// Scan ids are UUIDs/timestamps in practice, but defense-in-depth matters
/// when ids eventually flow through URL params.
fn sanitize_id(id: &str) -> String {
    id.chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
        .take(128)
        .collect()
}
