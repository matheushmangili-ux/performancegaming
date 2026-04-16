<script lang="ts">
	import NeonButton from '$lib/components/cyberpunk/NeonButton.svelte';
	import GlitchText from '$lib/components/cyberpunk/GlitchText.svelte';
	import ScanlineOverlay from '$lib/components/cyberpunk/ScanlineOverlay.svelte';
	import TerminalLog, { type LogLine } from '$lib/components/cyberpunk/TerminalLog.svelte';
	import ScoreRing from '$lib/components/cyberpunk/ScoreRing.svelte';
	import { onMount } from 'svelte';

	let demoScore = $state(0);
	let loadingBtn = $state(false);

	let lines = $state<LogLine[]>([]);
	let streamBusy = $state(false);

	const scriptedLines: Array<Omit<LogLine, 'id'>> = [
		{ text: 'Boot sequence initialized', severity: 'info', timestamp: '00:00.01' },
		{ text: 'Scanning registry keys...', severity: 'muted', timestamp: '00:00.12' },
		{ text: 'CRITICAL: MPO enabled (-15 FPS)', severity: 'error', timestamp: '00:00.84' },
		{ text: 'HIGH: HAGS disabled', severity: 'warn', timestamp: '00:01.02' },
		{ text: 'HIGH: Game DVR capture active', severity: 'warn', timestamp: '00:01.15' },
		{ text: 'OK: TRIM enabled on SSD', severity: 'ok', timestamp: '00:01.33' },
		{ text: 'OK: Power plan = Ultimate Performance', severity: 'ok', timestamp: '00:01.48' },
		{ text: 'MEDIUM: Win32PrioritySeparation = 2 (default)', severity: 'info', timestamp: '00:01.62' },
		{ text: 'Scan complete. Findings: 14. Score: 67/100', severity: 'ok', timestamp: '00:01.89' }
	];

	function runDemoScan() {
		lines = [];
		streamBusy = true;
		demoScore = 0;
		scriptedLines.forEach((line, i) => {
			setTimeout(() => {
				lines = [...lines, { id: i, ...line }];
				if (i === scriptedLines.length - 1) {
					streamBusy = false;
					demoScore = 67;
				}
			}, 250 + i * 220);
		});
	}

	function simulateLoading() {
		loadingBtn = true;
		setTimeout(() => (loadingBtn = false), 1800);
	}

	onMount(() => {
		setTimeout(() => (demoScore = 67), 400);
	});
</script>

<svelte:head>
	<title>ClockReaper · Component Showcase</title>
</svelte:head>

<main class="page">
	<header class="page-header">
		<GlitchText text="COMPONENT SHOWCASE" tag="h1" mode="hover" intensity="subtle" />
		<p class="subtitle">
			Week 2 · primitives. Iteração visual. Rota interna, não entra no build final.
		</p>
	</header>

	<section class="grid">
		<!-- GlitchText -->
		<article class="card">
			<header class="card-head">
				<h2>GlitchText</h2>
				<code>&lt;GlitchText text="..." mode="hover|always|once" intensity="subtle|strong" /&gt;</code>
			</header>
			<div class="card-body stacked">
				<div class="row">
					<span class="lbl">hover / subtle:</span>
					<GlitchText text="HOVER TO GLITCH" tag="span" mode="hover" intensity="subtle" />
				</div>
				<div class="row">
					<span class="lbl">hover / strong:</span>
					<GlitchText text="STRONG GLITCH" tag="span" mode="hover" intensity="strong" />
				</div>
				<div class="row">
					<span class="lbl">always / subtle:</span>
					<GlitchText text="ALWAYS-ON" tag="span" mode="always" intensity="subtle" />
				</div>
				<div class="row">
					<span class="lbl">always / strong:</span>
					<GlitchText text="SYSTEM BREACH" tag="span" mode="always" intensity="strong" />
				</div>
			</div>
		</article>

		<!-- NeonButton -->
		<article class="card">
			<header class="card-head">
				<h2>NeonButton</h2>
				<code>&lt;NeonButton variant="primary|danger|success|ghost" size="sm|md|lg" /&gt;</code>
			</header>
			<div class="card-body stacked">
				<div class="row btn-row">
					<NeonButton variant="primary" size="md">Scan</NeonButton>
					<NeonButton variant="success" size="md">Apply Fix</NeonButton>
					<NeonButton variant="danger" size="md">Revert All</NeonButton>
					<NeonButton variant="ghost" size="md">Cancel</NeonButton>
				</div>
				<div class="row btn-row">
					<NeonButton variant="primary" size="sm">SM</NeonButton>
					<NeonButton variant="primary" size="md">MD</NeonButton>
					<NeonButton variant="primary" size="lg">LG</NeonButton>
				</div>
				<div class="row btn-row">
					<NeonButton variant="primary" onclick={simulateLoading} loading={loadingBtn}>
						{loadingBtn ? 'Running…' : 'Simulate Loading'}
					</NeonButton>
					<NeonButton variant="ghost" disabled>Disabled</NeonButton>
				</div>
			</div>
		</article>

		<!-- ScanlineOverlay -->
		<article class="card">
			<header class="card-head">
				<h2>ScanlineOverlay</h2>
				<code>&lt;ScanlineOverlay intensity="subtle|medium|strong" sweep flicker /&gt;</code>
			</header>
			<div class="card-body scan-grid">
				<ScanlineOverlay intensity="subtle">
					<div class="scan-demo">SUBTLE</div>
				</ScanlineOverlay>
				<ScanlineOverlay intensity="medium" flicker>
					<div class="scan-demo">MEDIUM + FLICKER</div>
				</ScanlineOverlay>
				<ScanlineOverlay intensity="strong" sweep>
					<div class="scan-demo">STRONG + SWEEP</div>
				</ScanlineOverlay>
			</div>
		</article>

		<!-- ScoreRing -->
		<article class="card">
			<header class="card-head">
				<h2>ScoreRing</h2>
				<code>&lt;ScoreRing score={'{n}'} size={'{px}'} label="..." /&gt;</code>
			</header>
			<div class="card-body ring-row">
				<ScoreRing score={92} size={140} label="OPTIMAL" sublabel="—" />
				<ScoreRing score={67} size={160} label="GAMING PROFILE" sublabel="14 FIXES" />
				<ScoreRing score={34} size={140} label="POOR" sublabel="—" />
				<ScoreRing score={demoScore} size={180} label="LIVE SCAN" sublabel="animated" />
			</div>
		</article>

		<!-- TerminalLog -->
		<article class="card card--full">
			<header class="card-head">
				<h2>TerminalLog</h2>
				<code>&lt;TerminalLog lines={'{LogLine[]}'} busy autoScroll /&gt;</code>
			</header>
			<div class="card-body">
				<div class="term-controls">
					<NeonButton variant="primary" size="sm" onclick={runDemoScan}>Run Demo Scan</NeonButton>
					<span class="hint">simula streaming de findings em tempo real</span>
				</div>
				<TerminalLog {lines} busy={streamBusy} maxHeight="260px" />
			</div>
		</article>
	</section>

	<footer class="foot">
		<GlitchText text="NEXT: WEEK 3 — SCAN STREAMING" tag="span" mode="always" intensity="subtle" />
	</footer>
</main>

<style>
	.page {
		max-width: 1200px;
		margin: 0 auto;
		padding: var(--space-10) var(--space-8) var(--space-16);
		height: 100vh;
		overflow-y: auto;
	}

	.page-header {
		margin-bottom: var(--space-10);
		text-align: center;
	}

	.page-header :global(h1) {
		font-size: var(--fs-3xl);
		letter-spacing: var(--ls-display);
	}

	.subtitle {
		margin-top: var(--space-3);
		font-family: var(--font-mono);
		font-size: var(--fs-sm);
		color: var(--color-fg-muted);
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(440px, 1fr));
		gap: var(--space-6);
	}

	.card {
		background: var(--gradient-panel);
		border: 1px solid var(--color-border-subtle);
		border-radius: var(--radius-lg);
		overflow: hidden;
		display: flex;
		flex-direction: column;
	}
	.card--full {
		grid-column: 1 / -1;
	}

	.card-head {
		padding: var(--space-4) var(--space-5);
		border-bottom: 1px solid var(--color-border-faint);
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.card-head h2 {
		font-size: var(--fs-lg);
		letter-spacing: var(--ls-wide);
		color: var(--color-neon-cyan);
	}

	.card-head code {
		font-size: var(--fs-xs);
		color: var(--color-fg-muted);
	}

	.card-body {
		padding: var(--space-6) var(--space-5);
		flex: 1;
	}

	.stacked {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	.row {
		display: flex;
		align-items: center;
		gap: var(--space-4);
		flex-wrap: wrap;
	}

	.lbl {
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		color: var(--color-fg-muted);
		text-transform: uppercase;
		letter-spacing: var(--ls-wide);
		min-width: 140px;
	}

	.btn-row {
		gap: var(--space-3);
	}

	.scan-grid {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-3);
	}

	.scan-demo {
		height: 90px;
		display: grid;
		place-items: center;
		background: var(--color-bg-elevated);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wide);
		color: var(--color-neon-cyan);
		border-radius: var(--radius-sm);
	}

	.ring-row {
		display: flex;
		justify-content: space-around;
		align-items: center;
		gap: var(--space-4);
		flex-wrap: wrap;
	}

	.term-controls {
		display: flex;
		align-items: center;
		gap: var(--space-4);
		margin-bottom: var(--space-4);
	}

	.hint {
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		color: var(--color-fg-muted);
	}

	.foot {
		margin-top: var(--space-12);
		text-align: center;
		font-family: var(--font-mono);
		font-size: var(--fs-sm);
		color: var(--color-fg-muted);
	}
</style>
