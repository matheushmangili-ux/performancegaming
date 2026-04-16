<script lang="ts">
	interface Props {
		score: number;
		max?: number;
		size?: number;
		label?: string;
		sublabel?: string;
	}

	let { score, max = 100, size = 200, label, sublabel }: Props = $props();

	const stroke = 12;
	const radius = $derived((size - stroke) / 2);
	const circ = $derived(2 * Math.PI * radius);
	const ratio = $derived(Math.max(0, Math.min(score / max, 1)));
	const offset = $derived(circ * (1 - ratio));

	const tierColor = $derived(scoreColor(score, max));

	function scoreColor(s: number, m: number): string {
		const pct = (s / m) * 100;
		if (pct >= 85) return 'var(--color-neon-lime)';
		if (pct >= 70) return 'var(--color-neon-cyan)';
		if (pct >= 50) return 'var(--color-severity-medium)';
		if (pct >= 30) return 'var(--color-neon-amber)';
		return 'var(--color-neon-red)';
	}

	const tierLabel = $derived(scoreTier(score, max));
	function scoreTier(s: number, m: number): string {
		const pct = (s / m) * 100;
		if (pct >= 85) return 'OPTIMAL';
		if (pct >= 70) return 'GOOD';
		if (pct >= 50) return 'FAIR';
		if (pct >= 30) return 'POOR';
		return 'CRITICAL';
	}
</script>

<div class="score-ring" style="width: {size}px; height: {size}px">
	<svg
		{...{}}
		width={size}
		height={size}
		viewBox="0 0 {size} {size}"
		role="img"
		aria-label="Score {score} of {max} — {tierLabel}"
	>
		<defs>
			<filter id="ring-glow-{size}" x="-50%" y="-50%" width="200%" height="200%">
				<feGaussianBlur stdDeviation="4" result="blur" />
				<feMerge>
					<feMergeNode in="blur" />
					<feMergeNode in="SourceGraphic" />
				</feMerge>
			</filter>
		</defs>

		<circle
			cx={size / 2}
			cy={size / 2}
			r={radius}
			stroke="var(--color-border-faint)"
			stroke-width={stroke}
			fill="none"
		/>

		<circle
			class="progress"
			cx={size / 2}
			cy={size / 2}
			r={radius}
			stroke={tierColor}
			stroke-width={stroke}
			fill="none"
			stroke-linecap="round"
			stroke-dasharray={circ}
			stroke-dashoffset={offset}
			transform="rotate(-90 {size / 2} {size / 2})"
			filter="url(#ring-glow-{size})"
		/>
	</svg>
	<div class="center">
		<div class="value" style="color: {tierColor}">{Math.round(score)}</div>
		<div class="tier" style="color: {tierColor}">{tierLabel}</div>
		{#if label}<div class="label">{label}</div>{/if}
		{#if sublabel}<div class="sublabel">{sublabel}</div>{/if}
	</div>
</div>

<style>
	.score-ring {
		position: relative;
		display: inline-block;
	}

	svg {
		display: block;
	}

	.progress {
		transition: stroke-dashoffset var(--dur-slower) var(--ease-smooth);
	}

	.center {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		text-align: center;
		pointer-events: none;
	}

	.value {
		font-family: var(--font-display);
		font-size: calc(1rem + 1.75vw);
		font-weight: var(--fw-black);
		line-height: 1;
		text-shadow: 0 0 12px currentColor;
	}

	.tier {
		margin-top: 6px;
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-display);
		font-weight: var(--fw-bold);
	}

	.label {
		margin-top: 8px;
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		color: var(--color-fg-secondary);
		letter-spacing: var(--ls-wide);
		text-transform: uppercase;
	}

	.sublabel {
		margin-top: 2px;
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		color: var(--color-fg-muted);
	}
</style>
