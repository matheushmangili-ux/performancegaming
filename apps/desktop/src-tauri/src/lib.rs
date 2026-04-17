use serde::Serialize;

mod commands;
mod ps;

#[derive(Serialize)]
pub struct HealthStatus {
    app_version: &'static str,
    backend_ready: bool,
}

#[tauri::command]
fn get_health() -> HealthStatus {
    HealthStatus {
        app_version: env!("CARGO_PKG_VERSION"),
        backend_ready: true,
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,clockreaper_lib=debug".into()),
        )
        .init();

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            get_health,
            commands::audit::run_audit,
            commands::fix::apply_fix,
            commands::history::save_scan,
            commands::history::list_scans,
            commands::history::load_scan,
            commands::history::delete_scan,
        ])
        .run(tauri::generate_context!())
        .expect("error while running ClockReaper");
}
