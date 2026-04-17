//! PowerShell orchestrator.
//!
//! Spawns scripts bundled under `resources/scripts/`, reads the JSONL
//! streaming protocol emitted by `lib/json-emit.ps1`, and forwards
//! each parsed event to the frontend via Tauri events.

use std::path::PathBuf;
use std::process::Stdio;

use serde::Serialize;
use serde_json::Value;
use tauri::path::BaseDirectory;
use tauri::{AppHandle, Emitter, Manager, Runtime};
use thiserror::Error;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

#[derive(Debug, Error)]
pub enum OrchestratorError {
    #[error("script not found in bundle: {0}")]
    ScriptMissing(String),
    #[error("failed to spawn powershell: {0}")]
    Spawn(#[from] std::io::Error),
    #[error("resource path resolution failed: {0}")]
    ResourcePath(String),
    #[error("script exited with non-zero status: {0:?}")]
    NonZeroExit(Option<i32>),
}

impl Serialize for OrchestratorError {
    fn serialize<S: serde::Serializer>(&self, ser: S) -> Result<S::Ok, S::Error> {
        ser.serialize_str(&self.to_string())
    }
}

/// Scripts shipped with the app. Relative to `resources/scripts/`.
#[derive(Debug, Clone, Copy)]
#[allow(dead_code)] // Benchmark / Sentinel are wired in Weeks 6 and 10.
pub enum Script {
    Audit,
    ApplyFix,
    Benchmark,
    Sentinel,
}

impl Script {
    fn filename(self) -> &'static str {
        match self {
            Script::Audit => "Win11-Gaming-Audit.ps1",
            Script::ApplyFix => "apply-fix.ps1",
            Script::Benchmark => "Win11-Gaming-Benchmark.ps1",
            Script::Sentinel => "Win11-Gaming-Sentinel.ps1",
        }
    }

    /// Event name used when emitting parsed JSONL frames to the frontend.
    fn event_name(self) -> &'static str {
        match self {
            Script::Audit => "scan:event",
            Script::ApplyFix => "apply:event",
            Script::Benchmark => "benchmark:event",
            Script::Sentinel => "sentinel:event",
        }
    }
}

pub fn resolve_script<R: Runtime>(
    app: &AppHandle<R>,
    script: Script,
) -> Result<PathBuf, OrchestratorError> {
    let rel = format!("resources/scripts/{}", script.filename());
    app.path()
        .resolve(&rel, BaseDirectory::Resource)
        .map_err(|e| OrchestratorError::ResourcePath(e.to_string()))
        .and_then(|p| {
            if p.exists() {
                Ok(p)
            } else {
                Err(OrchestratorError::ScriptMissing(rel))
            }
        })
}

/// Spawn a PowerShell script with `-StreamJson` and forward its JSONL events
/// to the frontend. Each well-formed JSON line becomes an emitted Tauri event
/// under the script's channel (e.g. `scan:event`). Malformed lines are
/// forwarded on `scan:stderr` for debugging but never abort the run.
pub async fn run_stream<R: Runtime>(
    app: AppHandle<R>,
    script: Script,
    extra_args: Vec<String>,
) -> Result<(), OrchestratorError> {
    let script_path = resolve_script(&app, script)?;
    let channel = script.event_name();

    let mut args: Vec<String> = vec![
        "-NoProfile".into(),
        "-ExecutionPolicy".into(),
        "Bypass".into(),
        "-File".into(),
        script_path.to_string_lossy().into_owned(),
        "-StreamJson".into(),
    ];
    args.extend(extra_args);

    tracing::debug!(script = ?script, args = ?args, "spawning powershell");

    let mut child = Command::new("powershell.exe")
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()?;

    let stdout = child.stdout.take().expect("stdout pipe");
    let stderr = child.stderr.take().expect("stderr pipe");

    let stdout_app = app.clone();
    let stdout_task = tokio::spawn(async move {
        let mut lines = BufReader::new(stdout).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            match serde_json::from_str::<Value>(trimmed) {
                Ok(value) => {
                    if let Err(e) = stdout_app.emit(channel, &value) {
                        tracing::warn!(error = %e, "emit failed");
                    }
                }
                Err(_) => {
                    // Not JSON — likely noise from Write-Host. Forward as raw
                    // so the frontend can surface it in a debug terminal.
                    let _ = stdout_app.emit(
                        &format!("{channel}:raw"),
                        serde_json::json!({ "line": trimmed }),
                    );
                }
            }
        }
    });

    let stderr_app = app.clone();
    let stderr_channel = format!("{channel}:stderr");
    let stderr_task = tokio::spawn(async move {
        let mut lines = BufReader::new(stderr).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let _ = stderr_app.emit(&stderr_channel, serde_json::json!({ "line": trimmed }));
        }
    });

    let status = child.wait().await?;
    let _ = tokio::join!(stdout_task, stderr_task);

    if !status.success() {
        return Err(OrchestratorError::NonZeroExit(status.code()));
    }
    Ok(())
}
