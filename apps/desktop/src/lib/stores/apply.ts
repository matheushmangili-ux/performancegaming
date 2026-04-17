/**
 * Apply-fix store — handles selection of findings to fix/revert and
 * streaming progress from apply-fix.ps1 via Tauri events.
 */
import { writable, derived, get } from 'svelte/store';
import type {
	ApplyEvent,
	ApplyItemStatus,
	ApplyMode,
	Finding,
	FixPayload
} from '$lib/ipc/tauri';
import { applyFix as invokeApplyFix, onApplyEvent } from '$lib/ipc/tauri';
import type { UnlistenFn } from '@tauri-apps/api/event';

export type ApplyPhase = 'idle' | 'confirming' | 'applying' | 'complete' | 'error';

export interface ApplyItemResult {
	id: string;
	title: string;
	status: ApplyItemStatus;
	exitCode?: number;
	stderr?: string;
	stdout?: string;
	message?: string;
	reason?: string;
}

interface ApplyModel {
	phase: ApplyPhase;
	mode: ApplyMode;
	selection: Set<string>;
	currentIndex: number;
	totalToApply: number;
	restorePoint: { status: 'idle' | 'creating' | 'created' | 'skipped'; label?: string; reason?: string };
	results: ApplyItemResult[];
	summary: { applied: number; failed: number; skipped: number; total: number } | null;
	error: string | null;
}

const initial: ApplyModel = {
	phase: 'idle',
	mode: 'fix',
	selection: new Set(),
	currentIndex: -1,
	totalToApply: 0,
	restorePoint: { status: 'idle' },
	results: [],
	summary: null,
	error: null
};

const store = writable<ApplyModel>(initial);
export const apply = { subscribe: store.subscribe };

export const selectionCount = derived(store, ($s) => $s.selection.size);
export const isSelected = derived(store, ($s) => (id: string) => $s.selection.has(id));

export function toggleSelection(id: string): void {
	store.update((s) => {
		const next = new Set(s.selection);
		if (next.has(id)) next.delete(id);
		else next.add(id);
		return { ...s, selection: next };
	});
}

export function selectAll(findings: Finding[]): void {
	store.update((s) => ({
		...s,
		selection: new Set(findings.filter((f) => f.fix_cmd).map((f) => f.id))
	}));
}

export function selectBySeverity(findings: Finding[], severities: string[]): void {
	store.update((s) => ({
		...s,
		selection: new Set(
			findings.filter((f) => severities.includes(f.severity) && f.fix_cmd).map((f) => f.id)
		)
	}));
}

export function clearSelection(): void {
	store.update((s) => ({ ...s, selection: new Set() }));
}

export function startConfirm(mode: ApplyMode = 'fix'): void {
	store.update((s) => ({ ...s, phase: 'confirming', mode }));
}

export function cancelConfirm(): void {
	store.update((s) =>
		s.phase === 'confirming' ? { ...s, phase: 'idle' } : s
	);
}

export function resetApply(): void {
	store.set({ ...initial, selection: get(store).selection });
}

function applyEventReducer(evt: ApplyEvent, s: ApplyModel): ApplyModel {
	switch (evt.type) {
		case 'start':
			return {
				...s,
				phase: 'applying',
				totalToApply: evt.total,
				mode: evt.mode,
				results: [],
				summary: null,
				error: null,
				currentIndex: -1
			};
		case 'restore_point':
			return {
				...s,
				restorePoint: {
					status: evt.status,
					label: evt.label,
					reason: evt.reason
				}
			};
		case 'item': {
			const existingIdx = s.results.findIndex((r) => r.id === evt.id);
			const result: ApplyItemResult = {
				id: evt.id,
				title: evt.title,
				status: evt.status,
				exitCode: evt.exit_code,
				stderr: evt.stderr,
				stdout: evt.stdout,
				message: evt.message,
				reason: evt.reason
			};
			const results = [...s.results];
			if (existingIdx === -1) results.push(result);
			else results[existingIdx] = result;
			return {
				...s,
				currentIndex: evt.index,
				results
			};
		}
		case 'done':
			return {
				...s,
				phase: 'complete',
				summary: {
					applied: evt.applied,
					failed: evt.failed,
					skipped: evt.skipped,
					total: evt.total
				}
			};
		case 'error':
			return {
				...s,
				phase: 'error',
				error: `${evt.where}: ${evt.message}`
			};
		default:
			return s;
	}
}

let unlisten: UnlistenFn | null = null;

export async function attachApplyListener(): Promise<void> {
	if (unlisten) return;
	unlisten = await onApplyEvent((evt) => {
		store.update((s) => applyEventReducer(evt, s));
	});
}

export async function detachApplyListener(): Promise<void> {
	unlisten?.();
	unlisten = null;
}

export async function runApply(findings: Finding[], mode: ApplyMode = 'fix'): Promise<void> {
	const { selection } = get(store);
	const payload: FixPayload[] = findings
		.filter((f) => selection.has(f.id))
		.map((f) => ({
			id: f.id,
			title: f.title,
			severity: f.severity,
			fix_cmd: f.fix_cmd,
			revert_cmd: f.revert_cmd
		}));
	if (payload.length === 0) return;

	store.update((s) => ({
		...s,
		phase: 'applying',
		mode,
		results: [],
		summary: null,
		totalToApply: payload.length,
		currentIndex: -1,
		error: null,
		restorePoint: { status: 'idle' }
	}));

	try {
		await invokeApplyFix({ fixes: payload, mode });
	} catch (err) {
		const msg = err instanceof Error ? err.message : String(err);
		store.update((s) => ({ ...s, phase: 'error', error: msg }));
	}
}
