/**
 * Scan store — reactive state container for the /scan route.
 * Shape follows the JSONL protocol defined in lib/json-emit.ps1 and
 * parsed by the Rust orchestrator at src-tauri/src/ps/orchestrator.rs.
 */
import { writable, derived, get } from 'svelte/store';
import type {
	Finding,
	HardwareInventory,
	ScanEvent,
	Severity,
	AuditParams
} from '$lib/ipc/tauri';
import { runAudit, onScanEvent, onScanStderr, onScanRaw } from '$lib/ipc/tauri';
import type { UnlistenFn } from '@tauri-apps/api/event';

export type ScanState = 'idle' | 'running' | 'complete' | 'error';

export interface ScanStats {
	score: number;
	critical: number;
	high: number;
	medium: number;
	total: number;
	duration_ms: number;
}

interface ScanModel {
	state: ScanState;
	startedAt: number | null;
	hardware: HardwareInventory | null;
	findings: Finding[];
	stats: ScanStats | null;
	errorMessage: string | null;
	raw: string[];
	stderr: string[];
}

const initial: ScanModel = {
	state: 'idle',
	startedAt: null,
	hardware: null,
	findings: [],
	stats: null,
	errorMessage: null,
	raw: [],
	stderr: []
};

const store = writable<ScanModel>(initial);
export const scan = { subscribe: store.subscribe };

// Derived helpers for templates.
export const findingsBySeverity = derived(store, ($s) => {
	const groups: Record<Severity, Finding[]> = {
		CRITICO: [],
		ALTO: [],
		MEDIO: [],
		INFO: [],
		OK: []
	};
	for (const f of $s.findings) groups[f.severity].push(f);
	return groups;
});

export const liveScore = derived(store, ($s) => {
	if ($s.stats) return $s.stats.score;
	// Optimistic live score while running: starts at 100 and decays as
	// severities arrive. Matches the PS1 formula in Render-Console.
	if ($s.state === 'running') {
		let s = 100;
		for (const f of $s.findings) {
			if (f.severity === 'CRITICO') s -= 10;
			else if (f.severity === 'ALTO') s -= 5;
			else if (f.severity === 'MEDIO') s -= 2;
		}
		return Math.max(0, s);
	}
	return null;
});

function applyEvent(evt: ScanEvent, s: ScanModel): ScanModel {
	switch (evt.type) {
		case 'start':
			return {
				...initial,
				state: 'running',
				startedAt: Date.now()
			};
		case 'hw':
			return {
				...s,
				hardware: {
					cpu: evt.cpu,
					gpus: evt.gpus,
					ram_gb: evt.ram_gb,
					motherboard: evt.motherboard,
					bios: evt.bios,
					chassis: evt.chassis,
					storage: evt.storage
				}
			};
		case 'finding':
			return {
				...s,
				findings: [
					...s.findings,
					{
						id: evt.id,
						severity: evt.severity,
						category: evt.category,
						title: evt.title,
						current: evt.current,
						why: evt.why,
						impact: evt.impact,
						fix_cmd: evt.fix_cmd,
						revert_cmd: evt.revert_cmd
					}
				]
			};
		case 'done':
			return {
				...s,
				state: 'complete',
				stats: {
					score: evt.score,
					critical: evt.critical,
					high: evt.high,
					medium: evt.medium,
					total: evt.total,
					duration_ms: evt.duration_ms
				}
			};
		case 'error':
			return {
				...s,
				state: 'error',
				errorMessage: `${evt.where}: ${evt.message}`
			};
		default:
			return s;
	}
}

let unlistenEvent: UnlistenFn | null = null;
let unlistenStderr: UnlistenFn | null = null;
let unlistenRaw: UnlistenFn | null = null;

export async function attachListeners(): Promise<void> {
	if (unlistenEvent) return;
	unlistenEvent = await onScanEvent((evt) => {
		store.update((s) => applyEvent(evt, s));
	});
	unlistenStderr = await onScanStderr((line) => {
		store.update((s) => ({ ...s, stderr: [...s.stderr, line].slice(-200) }));
	});
	unlistenRaw = await onScanRaw((line) => {
		store.update((s) => ({ ...s, raw: [...s.raw, line].slice(-200) }));
	});
}

export async function detachListeners(): Promise<void> {
	unlistenEvent?.();
	unlistenStderr?.();
	unlistenRaw?.();
	unlistenEvent = unlistenStderr = unlistenRaw = null;
}

export async function startScan(params: AuditParams = {}): Promise<void> {
	if (get(store).state === 'running') return;
	store.set({ ...initial, state: 'running', startedAt: Date.now() });
	try {
		await runAudit(params);
	} catch (err) {
		const msg = err instanceof Error ? err.message : String(err);
		store.update((s) => ({ ...s, state: 'error', errorMessage: msg }));
	}
}

export function resetScan(): void {
	store.set(initial);
}
