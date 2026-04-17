/**
 * Typed wrappers around Tauri `invoke` calls + event subscriptions.
 * Keeps the UI free of raw command strings and lets the compiler catch
 * signature drift when Rust commands change.
 */
import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';

// ────────────────────────────────────────────────────────────────────────
// Health
// ────────────────────────────────────────────────────────────────────────
export interface HealthStatus {
	app_version: string;
	backend_ready: boolean;
}

export async function getHealth(): Promise<HealthStatus> {
	return invoke<HealthStatus>('get_health');
}

// ────────────────────────────────────────────────────────────────────────
// Audit / Scan
// Mirror of `src-tauri/src/ps/orchestrator.rs` + json-emit.ps1 protocol.
// ────────────────────────────────────────────────────────────────────────
export type Severity = 'CRITICO' | 'ALTO' | 'MEDIO' | 'OK' | 'INFO';

export interface Finding {
	id: string;
	severity: Severity;
	category: string;
	title: string;
	current: string;
	why: string;
	impact: string;
	fix_cmd: string;
	revert_cmd: string;
}

export interface HardwareInventory {
	cpu?: string;
	gpus?: string[];
	ram_gb?: number;
	motherboard?: string;
	bios?: string;
	chassis?: string;
	storage?: string[];
}

export interface ScanStartEvent {
	type: 'start';
	profile: string;
	pid: number;
	ts: string;
}

export interface ScanHardwareEvent {
	type: 'hw';
	cpu?: string;
	gpus?: string[];
	ram_gb?: number;
	motherboard?: string;
	bios?: string;
	chassis?: string;
	storage?: string[];
}

export interface ScanFindingEvent extends Finding {
	type: 'finding';
}

export interface ScanProgressEvent {
	type: 'progress';
	category: string;
	pct: number;
}

export interface ScanDoneEvent {
	type: 'done';
	score: number;
	critical: number;
	high: number;
	medium: number;
	total: number;
	duration_ms: number;
}

export interface ScanErrorEvent {
	type: 'error';
	message: string;
	where: string;
}

export type ScanEvent =
	| ScanStartEvent
	| ScanHardwareEvent
	| ScanFindingEvent
	| ScanProgressEvent
	| ScanDoneEvent
	| ScanErrorEvent;

export interface AuditParams {
	profile?: 'Competitive' | 'Balanced' | 'Safe';
	skipSlow?: boolean;
	withTemps?: boolean;
}

export async function runAudit(params: AuditParams = {}): Promise<void> {
	await invoke('run_audit', { params });
}

export function onScanEvent(handler: (evt: ScanEvent) => void): Promise<UnlistenFn> {
	return listen<ScanEvent>('scan:event', (e) => handler(e.payload));
}

export function onScanStderr(handler: (line: string) => void): Promise<UnlistenFn> {
	return listen<{ line: string }>('scan:event:stderr', (e) => handler(e.payload.line));
}

export function onScanRaw(handler: (line: string) => void): Promise<UnlistenFn> {
	return listen<{ line: string }>('scan:event:raw', (e) => handler(e.payload.line));
}

// ────────────────────────────────────────────────────────────────────────
// Apply Fix
// Mirror of apply-fix.ps1 protocol.
// ────────────────────────────────────────────────────────────────────────
export type ApplyMode = 'fix' | 'revert';

export interface FixPayload {
	id: string;
	title: string;
	severity: string;
	fix_cmd: string;
	revert_cmd: string;
}

export interface ApplyStartEvent {
	type: 'start';
	mode: ApplyMode;
	total: number;
	restore_pt: boolean;
	pid: number;
	ts: string;
}

export interface ApplyRestorePointEvent {
	type: 'restore_point';
	status: 'creating' | 'created' | 'skipped';
	label?: string;
	reason?: string;
}

export type ApplyItemStatus = 'running' | 'ok' | 'failed' | 'skipped';

export interface ApplyItemEvent {
	type: 'item';
	id: string;
	index: number;
	title: string;
	status: ApplyItemStatus;
	command?: string;
	stdout?: string;
	stderr?: string;
	exit_code?: number;
	message?: string;
	reason?: string;
}

export interface ApplyDoneEvent {
	type: 'done';
	mode: ApplyMode;
	applied: number;
	failed: number;
	skipped: number;
	total: number;
}

export interface ApplyErrorEvent {
	type: 'error';
	message: string;
	where: string;
}

export type ApplyEvent =
	| ApplyStartEvent
	| ApplyRestorePointEvent
	| ApplyItemEvent
	| ApplyDoneEvent
	| ApplyErrorEvent;

export interface ApplyFixParams {
	fixes: FixPayload[];
	mode?: ApplyMode;
	skipRestorePoint?: boolean;
}

export async function applyFix(params: ApplyFixParams): Promise<void> {
	await invoke('apply_fix', { params });
}

export function onApplyEvent(handler: (evt: ApplyEvent) => void): Promise<UnlistenFn> {
	return listen<ApplyEvent>('apply:event', (e) => handler(e.payload));
}
