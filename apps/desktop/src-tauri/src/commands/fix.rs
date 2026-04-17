use std::io::Write;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Runtime};

use crate::ps::orchestrator::{run_stream, OrchestratorError, Script};

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct FixPayload {
    pub id: String,
    pub title: String,
    pub severity: String,
    pub fix_cmd: String,
    pub revert_cmd: String,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ApplyFixParams {
    pub fixes: Vec<FixPayload>,
    /// "fix" or "revert" — defaults to "fix" if not provided.
    #[serde(default)]
    pub mode: Option<String>,
    /// Disable restore point creation (mostly for testing).
    #[serde(default)]
    pub skip_restore_point: bool,
}

#[tauri::command]
pub async fn apply_fix<R: Runtime>(
    app: AppHandle<R>,
    params: ApplyFixParams,
) -> Result<(), OrchestratorError> {
    // Persist the fix list to a temp JSON file. The PS1 reads it and
    // streams per-item results. Temp file lives until the process exits.
    let tmp_path = std::env::temp_dir().join(format!(
        "clockreaper-fixes-{}.json",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    ));
    let json = serde_json::to_vec_pretty(&params.fixes).map_err(|e| {
        OrchestratorError::ResourcePath(format!("failed to serialize fixes: {e}"))
    })?;
    let mut f = std::fs::File::create(&tmp_path)?;
    f.write_all(&json)?;

    let mut args: Vec<String> = vec![
        "-FixesJson".into(),
        tmp_path.to_string_lossy().into_owned(),
        "-Mode".into(),
        params.mode.unwrap_or_else(|| "fix".into()),
    ];
    if params.skip_restore_point {
        args.push("-SkipRestorePoint".into());
    }

    let result = run_stream(app, Script::ApplyFix, args).await;

    // Best-effort cleanup.
    let _ = std::fs::remove_file(&tmp_path);

    result
}
