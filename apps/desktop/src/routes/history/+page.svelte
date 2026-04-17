<script lang="ts">
	import { onMount } from 'svelte';
	import GlitchText from '$lib/components/cyberpunk/GlitchText.svelte';
	import NeonButton from '$lib/components/cyberpunk/NeonButton.svelte';
	import { history, refreshHistory, deleteScanRecord } from '$lib/stores/history';

	let inTauri = $state(false);

	onMount(async () => {
		inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
		await refreshHistory();
	});

	// Score sparkline — array of scores oldest→newest for visual trend.
	let sparkline = $derived(
		$history.items
			.slice()
			.reverse()
			.map((s) => s.score)
	);

	let latestScore = $derived($history.items[0]?.score);
	let trend = $derived(() => {
		if ($history.items.length < 2) return null;
		const latest = $history.items[0].score;
		const previous = $history.items[1].score;
		return latest - previous;
	});

	function scoreColor(s: number): string {
		if (s >= 85) return 'var(--color-neon-lime)';
		if (s >= 70) return 'var(--color-neon-cyan)';
		if (s >= 50) return 'var(--color-severity-medium)';
		if (s >= 30) return 'var(--color-neon-amber)';
		return 'var(--color-neon-red)';
	}

	function formatDate(iso: string): string {
		try {
			return new Date(iso).toLocaleString('pt-BR', {
				year: 'numeric',
				month: '2-digit',
				day: '2-digit',
				hour: '2-digit',
				minute: '2-digit'
			});
		} catch {
			return iso;
		}
	}

	async function handleDelete(id: string, e: Event) {
		e.stopPropagation();
		if (!confirm('Delete this scan from history?')) return;
		await deleteScanRecord(id);
	}
</script>

<svelte:head>
	<title>ClockReaper · History</title>
</svelte:head>

<main class="page">
	<header class="page-header">
		<a class="back" href="/">← HOME</a>
		<GlitchText text="SCAN HISTORY" tag="h1" mode="hover" intensity="subtle" />
		<p class="subtitle">
			Local only · stored at <code>%APPDATA%\gg.clockreaper.desktop\history</code>
		</p>
	</header>

	{#if !inTauri}
		<aside class="env-notice">
			<strong>Web preview mode detected.</strong>
			History is persisted on disk and only available in the native desktop build.
		</aside>
	{:else if !$history.loaded}
		<div class="loading">Loading…</div>
	{:else if $history.error}
		<div class="error">Failed to load history: {$history.error}</div>
	{:else if $history.items.length === 0}
		<div class="empty">
			<p>No scans yet. Every completed scan gets saved here automatically.</p>
			<NeonButton variant="primary" onclick={() => (window.location.href = '/scan')}>
				Run first scan
			</NeonButton>
		</div>
	{:else}
		<section class="summary">
			<div class="kpi">
				<div class="kpi-label">LATEST</div>
				<div class="kpi-value" style="color: {scoreColor(latestScore ?? 0)}">
					{latestScore}
				</div>
				<div class="kpi-sub">/ 100</div>
			</div>
			<div class="kpi">
				<div class="kpi-label">SCANS</div>
				<div class="kpi-value">{$history.items.length}</div>
			</div>
			{#if trend() !== null}
				<div class="kpi">
					<div class="kpi-label">TREND</div>
					<div
						class="kpi-value"
						style="color: {(trend() ?? 0) >= 0 ? 'var(--color-neon-lime)' : 'var(--color-neon-red)'}"
					>
						{(trend() ?? 0) >= 0 ? '+' : ''}{trend()}
					</div>
					<div class="kpi-sub">vs previous</div>
				</div>
			{/if}
			<div class="spark">
				<svg viewBox="0 0 200 60" preserveAspectRatio="none" class="spark-svg">
					{#if sparkline.length > 1}
						{@const max = Math.max(...sparkline, 100)}
						{@const min = Math.min(...sparkline, 0)}
						{@const range = Math.max(max - min, 1)}
						{@const points = sparkline.map(
							(v, i) =>
								`${(i / Math.max(sparkline.length - 1, 1)) * 200},${60 - ((v - min) / range) * 56 - 2}`
						)}
						<polyline
							points={points.join(' ')}
							fill="none"
							stroke="var(--color-neon-cyan)"
							stroke-width="2"
							vector-effect="non-scaling-stroke"
						/>
					{/if}
				</svg>
			</div>
		</section>

		<ul class="list">
			{#each $history.items as item (item.id)}
				<li class="row anim-finding-enter">
					<div class="score-cell" style="color: {scoreColor(item.score)}">
						<div class="sv">{item.score}</div>
						<div class="sl">/100</div>
					</div>
					<div class="info">
						<div class="top">
							<span class="ts">{formatDate(item.timestamp)}</span>
							<span class="tag">{item.profile}</span>
							<span class="tag tag--mode">{item.mode}</span>
						</div>
						<div class="counts">
							<span class="c crit">{item.critical} CRIT</span>
							<span class="c high">{item.high} HIGH</span>
							<span class="c med">{item.medium} MED</span>
							<span class="c">{item.total} total</span>
							<span class="c muted">· {(item.durationMs / 1000).toFixed(1)}s</span>
						</div>
					</div>
					<button class="del" onclick={(e) => handleDelete(item.id, e)} title="Delete scan">
						×
					</button>
				</li>
			{/each}
		</ul>
	{/if}
</main>

<style>
	.page {
		max-width: 900px;
		margin: 0 auto;
		padding: var(--space-8) var(--space-8) var(--space-16);
		height: 100vh;
		overflow-y: auto;
	}

	.page-header {
		margin-bottom: var(--space-8);
	}

	.back {
		display: inline-block;
		margin-bottom: var(--space-3);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wider);
		color: var(--color-fg-muted);
		text-decoration: none;
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
	.subtitle code {
		color: var(--color-neon-cyan-soft);
	}

	.env-notice,
	.error {
		padding: var(--space-4) var(--space-5);
		background: rgba(255, 179, 0, 0.08);
		border: 1px solid rgba(255, 179, 0, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-fg-secondary);
		font-size: var(--fs-sm);
	}
	.env-notice strong {
		color: var(--color-neon-amber);
		letter-spacing: var(--ls-wide);
	}

	.loading {
		padding: var(--space-8);
		text-align: center;
		font-family: var(--font-mono);
		font-size: var(--fs-sm);
		color: var(--color-fg-muted);
	}

	.empty {
		padding: var(--space-12);
		text-align: center;
		border: 1px dashed var(--color-border-faint);
		border-radius: var(--radius-md);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-4);
		color: var(--color-fg-muted);
	}

	.summary {
		display: grid;
		grid-template-columns: auto auto auto 1fr;
		gap: var(--space-6);
		padding: var(--space-5);
		background: var(--gradient-panel);
		border: 1px solid var(--color-border-subtle);
		border-radius: var(--radius-lg);
		margin-bottom: var(--space-6);
		align-items: center;
	}

	.kpi {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 2px;
	}
	.kpi-label {
		font-family: var(--font-mono);
		font-size: 10px;
		letter-spacing: var(--ls-wider);
		color: var(--color-fg-muted);
	}
	.kpi-value {
		font-family: var(--font-display);
		font-size: var(--fs-3xl);
		font-weight: var(--fw-black);
		color: var(--color-fg-primary);
		line-height: 1;
	}
	.kpi-sub {
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		color: var(--color-fg-muted);
	}

	.spark {
		height: 60px;
		min-width: 120px;
	}
	.spark-svg {
		width: 100%;
		height: 100%;
		filter: drop-shadow(0 0 4px rgba(0, 240, 255, 0.6));
	}

	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.row {
		display: grid;
		grid-template-columns: 80px 1fr auto;
		align-items: center;
		gap: var(--space-4);
		padding: var(--space-4) var(--space-5);
		background: var(--gradient-panel);
		border: 1px solid var(--color-border-faint);
		border-radius: var(--radius-md);
		transition: border-color var(--dur-fast) var(--ease-sharp);
	}
	.row:hover {
		border-color: var(--color-border-strong);
	}

	.score-cell {
		text-align: center;
		font-family: var(--font-display);
	}
	.sv {
		font-size: var(--fs-2xl);
		font-weight: var(--fw-black);
		line-height: 1;
	}
	.sl {
		font-family: var(--font-mono);
		font-size: 10px;
		color: var(--color-fg-muted);
	}

	.info {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}

	.top {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		font-family: var(--font-mono);
		font-size: var(--fs-sm);
	}
	.ts {
		color: var(--color-fg-primary);
	}
	.tag {
		padding: 1px 6px;
		font-size: 10px;
		letter-spacing: var(--ls-wide);
		color: var(--color-neon-cyan);
		border: 1px solid var(--color-border-subtle);
		border-radius: var(--radius-sm);
		text-transform: uppercase;
	}
	.tag--mode {
		color: var(--color-neon-magenta);
		border-color: var(--color-border-magenta);
	}

	.counts {
		display: flex;
		gap: var(--space-3);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		color: var(--color-fg-secondary);
		flex-wrap: wrap;
	}
	.c.crit {
		color: var(--color-severity-critical);
	}
	.c.high {
		color: var(--color-severity-high);
	}
	.c.med {
		color: var(--color-severity-medium);
	}
	.c.muted {
		color: var(--color-fg-muted);
	}

	.del {
		width: 28px;
		height: 28px;
		border-radius: var(--radius-sm);
		background: transparent;
		border: 1px solid var(--color-border-faint);
		color: var(--color-fg-muted);
		font-size: var(--fs-lg);
		line-height: 1;
		cursor: pointer;
		transition: all var(--dur-fast) var(--ease-sharp);
	}
	.del:hover {
		color: var(--color-neon-red);
		border-color: var(--color-neon-red);
		box-shadow: 0 0 8px rgba(255, 46, 91, 0.4);
	}
</style>
