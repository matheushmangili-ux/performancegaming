/**
 * History store — persists completed scans to %APPDATA% via the Rust
 * history command module, and caches the list in-memory for the /history
 * route and any sparkline in the app header.
 */
import { writable } from 'svelte/store';
import type { ScanSummary, FullScanRecord } from '$lib/ipc/tauri';
import {
	listScans,
	saveScan as invokeSaveScan,
	loadScan as invokeLoadScan,
	deleteScan as invokeDeleteScan
} from '$lib/ipc/tauri';

interface HistoryModel {
	loaded: boolean;
	items: ScanSummary[];
	error: string | null;
}

const store = writable<HistoryModel>({ loaded: false, items: [], error: null });
export const history = { subscribe: store.subscribe };

function isTauri(): boolean {
	return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
}

export async function refreshHistory(): Promise<void> {
	if (!isTauri()) {
		store.set({ loaded: true, items: [], error: null });
		return;
	}
	try {
		const items = await listScans();
		store.set({ loaded: true, items, error: null });
	} catch (err) {
		const msg = err instanceof Error ? err.message : String(err);
		store.set({ loaded: true, items: [], error: msg });
	}
}

export async function saveScanRecord(record: FullScanRecord): Promise<void> {
	if (!isTauri()) return;
	try {
		await invokeSaveScan(record);
		await refreshHistory();
	} catch (err) {
		console.error('[history] saveScan failed:', err);
	}
}

export async function loadScanRecord(id: string): Promise<FullScanRecord | null> {
	if (!isTauri()) return null;
	try {
		return await invokeLoadScan(id);
	} catch (err) {
		console.error('[history] loadScan failed:', err);
		return null;
	}
}

export async function deleteScanRecord(id: string): Promise<void> {
	if (!isTauri()) return;
	try {
		await invokeDeleteScan(id);
		await refreshHistory();
	} catch (err) {
		console.error('[history] deleteScan failed:', err);
	}
}
