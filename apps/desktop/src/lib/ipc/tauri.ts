/**
 * Typed wrappers around Tauri `invoke` calls.
 * Each backend command has a matching function here so UI code never
 * touches raw `invoke` strings — refactors are safe.
 */
import { invoke } from '@tauri-apps/api/core';

export interface HealthStatus {
	app_version: string;
	backend_ready: boolean;
}

export async function getHealth(): Promise<HealthStatus> {
	return invoke<HealthStatus>('get_health');
}
