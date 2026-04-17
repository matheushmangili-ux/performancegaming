use serde::Deserialize;
use tauri::{AppHandle, Runtime};

use crate::ps::orchestrator::{run_stream, OrchestratorError, Script};

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct AuditParams {
    /// "Competitive" | "Balanced" | "Safe". Falls back to Balanced on the PS1 side.
    #[serde(default)]
    pub profile: Option<String>,
    /// Skip slow checks (AppxPackage, game libraries) for faster iteration.
    #[serde(default)]
    pub skip_slow: bool,
    /// Attempt to read thermal zones via WMI (can return bogus values).
    #[serde(default)]
    pub with_temps: bool,
}

#[tauri::command]
pub async fn run_audit<R: Runtime>(
    app: AppHandle<R>,
    params: Option<AuditParams>,
) -> Result<(), OrchestratorError> {
    let params = params.unwrap_or_default();
    let mut args: Vec<String> = Vec::new();
    if let Some(p) = params.profile {
        args.push("-Profile".into());
        args.push(p);
    }
    if params.skip_slow {
        args.push("-SkipSlow".into());
    }
    if params.with_temps {
        args.push("-WithTemps".into());
    }
    run_stream(app, Script::Audit, args).await
}
