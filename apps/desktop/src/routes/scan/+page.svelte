<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import NeonButton from '$lib/components/cyberpunk/NeonButton.svelte';
	import GlitchText from '$lib/components/cyberpunk/GlitchText.svelte';
	import ScoreRing from '$lib/components/cyberpunk/ScoreRing.svelte';
	import TerminalLog, { type LogLine } from '$lib/components/cyberpunk/TerminalLog.svelte';
	import FindingCard from '$lib/components/findings/FindingCard.svelte';
	import ApplyBar from '$lib/components/findings/ApplyBar.svelte';
	import ApplyDialog from '$lib/components/findings/ApplyDialog.svelte';
	import HardwareCard from '$lib/components/hardware/HardwareCard.svelte';
	import ModeToggle from '$lib/components/ModeToggle.svelte';
	import {
		scan,
		liveScore,
		attachListeners,
		detachListeners,
		startScan,
		resetScan,
		setMode
	} from '$lib/stores/scan';
	import {
		apply,
		attachApplyListener,
		detachApplyListener,
		toggleSelection
	} from '$lib/stores/apply';
	import { findingMatchesMode, type AuditParams } from '$lib/ipc/tauri';

	let profile = $state<NonNullable<AuditParams['profile']>>('Balanced');
	let inTauri = $state(false);
	let detectedEnv = $state<'desktop' | 'web'>('web');

	onMount(async () => {
		inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
		detectedEnv = inTauri ? 'desktop' : 'web';
		if (inTauri) {
			await attachListeners();
			await attachApplyListener();
		}
	});

	onDestroy(async () => {
		await detachListeners();
		await detachApplyListener();
	});

	async function handleRun() {
		if (!inTauri) return;
		await startScan({ profile });
	}

	const profiles: Array<NonNullable<AuditParams['profile']>> = ['Safe', 'Balanced', 'Competitive'];

	// Derive terminal log lines from the raw stdout buffer for debug view.
	let terminalLines = $derived<LogLine[]>(
		$scan.raw.map((line, i) => ({
			id: `raw-${i}`,
			text: line,
			severity: 'muted' as const
		}))
	);

	// Filter findings based on selected mode. Severity OK/INFO stay visible
	// regardless because they're informational context, not issues to hide.
	let visibleFindings = $derived(
		$scan.findings.filter(
			(f) =>
				$scan.mode === 'all' ||
				findingMatchesMode(f.category, $scan.mode) ||
				f.severity === 'OK' ||
				f.severity === 'INFO'
		)
	);

	let hiddenCount = $derived($scan.findings.length - visibleFindings.length);
</script>

<svelte:head>
	<title>ClockReaper · Scan</title>
</svelte:head>

<main class="page">
	<header class="page-header">
		<a class="back" href="/">← HOME</a>
		<GlitchText text="SYSTEM SCAN" tag="h1" mode="hover" intensity="subtle" />
		<p class="subtitle">Read-only diagnostic · 15 categories · Estimated 5–15s</p>
	</header>

	{#if !inTauri}
		<aside class="env-notice">
			<strong>Web preview mode detected.</strong>
			<p>
				Scan execution requires the native desktop binary (Tauri + PowerShell). In the web
				preview you can explore the layout and component behavior; real system checks need the
				installer that lands in Week 11.
			</p>
		</aside>
	{/if}

	<section class="controls">
		<div class="profile-row">
			<span class="lbl">PROFILE</span>
			{#each profiles as p (p)}
				<button
					class="profile-btn"
					class:is-active={profile === p}
					onclick={() => (profile = p)}
					disabled={$scan.state === 'running'}
				>
					{p.toUpperCase()}
				</button>
			{/each}
		</div>

		<div class="mode-row">
			<span class="lbl">VIEW</span>
			<ModeToggle value={$scan.mode} onChange={setMode} />
		</div>

		<div class="actions">
			{#if $scan.state === 'idle' || $scan.state === 'error'}
				<NeonButton variant="primary" size="lg" onclick={handleRun} disabled={!inTauri}>
					{inTauri ? 'Run Scan' : 'Scan disabled (web)'}
				</NeonButton>
			{:else if $scan.state === 'running'}
				<NeonButton variant="primary" size="lg" loading>Scanning</NeonButton>
			{:else if $scan.state === 'complete'}
				<NeonButton variant="success" size="lg" onclick={resetScan}>New Scan</NeonButton>
			{/if}
		</div>
	</section>

	{#if $scan.state === 'error' && $scan.errorMessage}
		<div class="error-banner">
			<strong>ERROR:</strong>
			{$scan.errorMessage}
		</div>
	{/if}

	<div class="layout">
		<aside class="side">
			<div class="score-block">
				{#if $liveScore !== null}
					<ScoreRing
						score={$liveScore}
						size={200}
						label={$scan.state === 'running' ? 'LIVE' : 'RESULT'}
						sublabel={$scan.state === 'running'
							? `${$scan.findings.length} issues`
							: $scan.stats
								? `in ${($scan.stats.duration_ms / 1000).toFixed(1)}s`
								: ''}
					/>
				{:else}
					<div class="score-placeholder">
						<span>NO SCAN YET</span>
					</div>
				{/if}
			</div>

			{#if $scan.stats}
				<dl class="tally">
					<div><dt>CRITICAL</dt><dd class="crit">{$scan.stats.critical}</dd></div>
					<div><dt>HIGH</dt><dd class="high">{$scan.stats.high}</dd></div>
					<div><dt>MEDIUM</dt><dd class="med">{$scan.stats.medium}</dd></div>
					<div><dt>TOTAL</dt><dd>{$scan.stats.total}</dd></div>
				</dl>
			{/if}

			<HardwareCard hardware={$scan.hardware} />
		</aside>

		<section class="main-col">
			<header class="col-head">
				<h2>FINDINGS</h2>
				<span class="count">
					{visibleFindings.length}
					{visibleFindings.length === 1 ? 'issue' : 'issues'}
					{#if hiddenCount > 0}
						<span class="muted">· {hiddenCount} hidden by {$scan.mode} filter</span>
					{/if}
				</span>
			</header>

			{#if visibleFindings.length === 0}
				<div class="empty">
					{#if $scan.state === 'idle'}
						<p>Awaiting scan. Choose a profile and hit <strong>Run Scan</strong>.</p>
						<p class="env-hint">Environment: <code>{detectedEnv}</code></p>
					{:else if $scan.state === 'running'}
						<GlitchText text="SCANNING..." mode="always" intensity="subtle" />
					{:else if $scan.findings.length > 0}
						<p>
							No findings in <code>{$scan.mode}</code> mode. Switch to <strong>ALL</strong> to
							see the {$scan.findings.length} other findings.
						</p>
					{/if}
				</div>
			{:else}
				<div class="findings-list">
					{#each visibleFindings as f, i (f.id)}
						<FindingCard
							finding={f}
							index={i}
							selected={$apply.selection.has(f.id)}
							onToggleSelect={toggleSelection}
						/>
					{/each}
				</div>
				<ApplyBar findings={visibleFindings} disabled={!inTauri} />
			{/if}
		</section>
	</div>

	<ApplyDialog findings={$scan.findings} />

	{#if $scan.raw.length > 0 || $scan.stderr.length > 0}
		<details class="debug">
			<summary>
				<span class="dbg-lbl">DEBUG ·</span>
				stream log ({$scan.raw.length} raw / {$scan.stderr.length} stderr)
			</summary>
			<TerminalLog lines={terminalLines} maxHeight="180px" />
		</details>
	{/if}
</main>

<style>
	.page {
		max-width: 1400px;
		margin: 0 auto;
		padding: var(--space-8) var(--space-8) var(--space-16);
		height: 100vh;
		overflow-y: auto;
	}

	.page-header {
		margin-bottom: var(--space-6);
	}

	.back {
		display: inline-block;
		margin-bottom: var(--space-3);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wider);
		color: var(--color-fg-muted);
		text-decoration: none;
		transition: color var(--dur-fast) var(--ease-sharp);
	}
	.back:hover {
		color: var(--color-neon-cyan);
	}

	.page-header :global(h1) {
		font-size: var(--fs-3xl);
	}

	.subtitle {
		margin-top: var(--space-2);
		font-family: var(--font-mono);
		font-size: var(--fs-sm);
		color: var(--color-fg-muted);
	}

	.env-notice {
		margin-bottom: var(--space-6);
		padding: var(--space-4) var(--space-5);
		background: rgba(255, 179, 0, 0.08);
		border: 1px solid rgba(255, 179, 0, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-fg-secondary);
		font-size: var(--fs-sm);
	}
	.env-notice strong {
		display: block;
		margin-bottom: var(--space-2);
		color: var(--color-neon-amber);
		letter-spacing: var(--ls-wide);
	}
	.env-notice p {
		margin: 0;
		line-height: var(--lh-relaxed);
	}

	.controls {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-4);
		padding: var(--space-4) var(--space-5);
		background: var(--gradient-panel);
		border: 1px solid var(--color-border-subtle);
		border-radius: var(--radius-lg);
		margin-bottom: var(--space-6);
		flex-wrap: wrap;
	}

	.profile-row,
	.mode-row {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		flex-wrap: wrap;
	}

	.lbl {
		margin-right: var(--space-2);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wide);
		color: var(--color-fg-muted);
	}

	.profile-btn {
		padding: 6px 14px;
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		font-weight: var(--fw-bold);
		letter-spacing: var(--ls-wide);
		color: var(--color-fg-muted);
		background: transparent;
		border: 1px solid var(--color-border-subtle);
		border-radius: var(--radius-sm);
		cursor: pointer;
		transition: all var(--dur-fast) var(--ease-sharp);
	}
	.profile-btn:hover:not([disabled]) {
		color: var(--color-neon-cyan);
		border-color: var(--color-neon-cyan);
	}
	.profile-btn.is-active {
		color: var(--color-fg-on-neon);
		background: var(--color-neon-cyan);
		border-color: var(--color-neon-cyan);
	}
	.profile-btn[disabled] {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.error-banner {
		margin-bottom: var(--space-6);
		padding: var(--space-4);
		background: rgba(255, 46, 91, 0.1);
		border: 1px solid rgba(255, 46, 91, 0.4);
		border-radius: var(--radius-md);
		color: var(--color-neon-red);
		font-family: var(--font-mono);
		font-size: var(--fs-sm);
	}

	.layout {
		display: grid;
		grid-template-columns: 280px 1fr;
		gap: var(--space-6);
		align-items: start;
	}

	.side {
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
		position: sticky;
		top: var(--space-4);
	}

	.score-block {
		display: flex;
		justify-content: center;
	}

	.score-placeholder {
		width: 200px;
		height: 200px;
		display: grid;
		place-items: center;
		border: 1px dashed var(--color-border-faint);
		border-radius: 50%;
		color: var(--color-fg-muted);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wide);
	}

	.tally {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-3);
		margin: 0;
		padding: var(--space-3);
		background: var(--gradient-panel);
		border: 1px solid var(--color-border-faint);
		border-radius: var(--radius-md);
	}
	.tally > div {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.tally dt {
		font-family: var(--font-mono);
		font-size: 10px;
		letter-spacing: var(--ls-wider);
		color: var(--color-fg-muted);
	}
	.tally dd {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--fs-xl);
		font-weight: var(--fw-black);
		color: var(--color-fg-primary);
	}
	.tally dd.crit {
		color: var(--color-severity-critical);
	}
	.tally dd.high {
		color: var(--color-severity-high);
	}
	.tally dd.med {
		color: var(--color-severity-medium);
	}

	.main-col {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	.col-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		padding-bottom: var(--space-3);
		border-bottom: 1px solid var(--color-border-faint);
	}
	.col-head h2 {
		font-size: var(--fs-lg);
		letter-spacing: var(--ls-display);
		color: var(--color-neon-cyan);
	}
	.count {
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		color: var(--color-fg-muted);
	}
	.count .muted {
		color: var(--color-fg-muted);
		margin-left: var(--space-2);
	}

	.empty {
		padding: var(--space-12) var(--space-6);
		text-align: center;
		color: var(--color-fg-muted);
		font-family: var(--font-mono);
		font-size: var(--fs-sm);
		border: 1px dashed var(--color-border-faint);
		border-radius: var(--radius-md);
	}
	.empty p {
		margin: 0 0 var(--space-3);
	}
	.env-hint {
		font-size: var(--fs-xs);
	}
	.env-hint code {
		color: var(--color-neon-cyan);
	}

	.findings-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}

	.debug {
		margin-top: var(--space-8);
		border-top: 1px solid var(--color-border-faint);
		padding-top: var(--space-4);
	}
	.debug summary {
		cursor: pointer;
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		color: var(--color-fg-muted);
		letter-spacing: var(--ls-wide);
		margin-bottom: var(--space-3);
	}
	.dbg-lbl {
		color: var(--color-neon-cyan);
		font-weight: var(--fw-bold);
	}

	@media (max-width: 900px) {
		.layout {
			grid-template-columns: 1fr;
		}
		.side {
			position: static;
		}
	}
</style>
